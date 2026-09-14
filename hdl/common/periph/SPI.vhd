-- VestaRV: SPI controller
-- Master/slave SPI with CR/SR/TX/RX/FOS registers, a two-chained-ClkGate baud divider and one IRQ each for transfer-complete and transmit-empty.
-- ENABLE_EXTENDED_MEM instantiates the SPI flash XIP core, which adds a second read port on en_mem_flash.

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.constants.all;
-- Word offsets, field ranges, resets and implemented-bit masks: generated from hdl/common/regs/rdl/spi.rdl, which replaces the work.MemoryMap clause (both would make every slot name an ambiguous homograph).
use work.spi_regs_pkg.all;

entity SPI is
    generic
    (
        ENABLE_EXTENDED_MEM : boolean := false  -- true instantiates the SPI flash XIP core  
    );
    port
    (
        clk         : in std_logic;
        mclk        : in std_logic;
        resetn      : in std_logic;

        -- IRQ Signals
        irq_tc      : out std_logic;
        irq_te      : out std_logic;

        -- Peripheral register bus: clk_mem is the gated bus clock, wen is active low per byte lane
        clk_mem      : in std_logic; 
        en_mem       : in std_logic; 
        wen          : in std_logic_vector(3 downto 0); 
        write_data   : in std_logic_vector(31 downto 0); 
        read_data    : out std_logic_vector(31 downto 0); 
        addr_periph  : in std_logic_vector(7 downto 2); 

        cs_in       : in std_logic;

        sck_in     : in std_logic;
        sck_out    : out std_logic;
        sck_dir    : out std_logic;
        sck_ren    : out std_logic;
        sck_ren_in : in std_logic;

        mosi_in    : in  std_logic;
        mosi_out   : out std_logic;
        mosi_dir   : out std_logic;
        mosi_ren   : out std_logic;
        mosi_ren_in : in std_logic;

        miso_in    : in  std_logic;
        miso_out   : out std_logic;
        miso_dir   : out std_logic;
        miso_ren   : out std_logic;
        miso_ren_in : in std_logic;
        
        -- Extended Memory Interface (conditional on ENABLE_EXTENDED_MEM)
        en_mem_flash    : in std_logic;
        clk_mem_flash   : in std_logic;
        mab             : in std_logic_vector(31 downto 0);
        rdata_flash     : out std_logic_vector(31 downto 0);
        disable_clk_cpu : out std_logic;
        
        -- Flash Chip Select
        cs_flash_out    : out std_logic;
        cs_flash_dir    : out std_logic;
        cs_flash_ren    : out std_logic

    );

end entity SPI;

architecture behavioral of SPI is


    -- The bus side is one periph_regs instance driven by spi_regs_pkg's tables;
    -- see hdl/common/regs/REGFILE.md. SPIxCR, SPIxTX and SPIxFOS are its storage;
    -- SPIxSR and SPIxRX hold no flop there, because the hardware that sets those
    -- flags and that fills the receive register owns them, and their pre-latch
    -- CDC lives below.
    signal regs_q  : reg_arr_t;
    signal hw_rd_s : reg_arr_t;
    signal w1c_s   : reg_arr_t;                        -- a 1 written to a SPIxSR flag
    signal wrh_s   : std_logic_vector(0 to NWORDS-1);  -- ... and the access is a lane write
    signal rd_str  : std_logic_vector(0 to NWORDS-1);
    signal wr_str  : std_logic_vector(0 to NWORDS-1);
    signal sr_rd, rx_rd : std_logic_vector(31 downto 0);

    -- SPI1 is built with ENABLE_EXTENDED_MEM = false, where SPIxFOS ignores writes
    -- and reads 0. The word stays in the table and RDTHRU with hw_rd = 0 is the
    -- read half; the write half is inert because the only reader of that storage,
    -- the flash address adder, is inside the ENABLE_EXTENDED_MEM generate and is
    -- not elaborated. The other option the survey named, holding the word at 0
    -- through hw_we, is not available: spi.rdl gives SPIxFOS hw = r, so its HWOWN
    -- row is zero and a hook wired to it would be dropped.
    function fosRdThru return std_logic_vector is
        variable r : std_logic_vector(0 to NWORDS-1) := (others => '0');
    begin
        if not ENABLE_EXTENDED_MEM then
            r(RegSlotSPIxFOS) := '1';
        end if;
        return r;
    end function;

    constant SPI_RDTHRU : std_logic_vector(0 to NWORDS-1) := fosRdThru;

    -- Register Signals 
    signal SPIxSR : std_logic_vector(2 downto 0); -- Status Register
    signal SPIxSR_ltch : std_logic_vector(2 downto 0); -- Status Register Latched
    signal SPIxRX : std_logic_vector(31 downto 0); -- Receive Register
    signal SPIxRX_ltch : std_logic_vector(31 downto 0); -- Receive Register Latched
    signal SPIxTX : std_logic_vector(31 downto 0); -- Transmit Register (tap of the register file)
    signal SPIxFOS : std_logic_vector(23 downto 0); -- SPI Flash memory address offset (tap of the register file)


    -- Register Bit Field Declarations
    -- SPIxCR Bit Fields
    signal spi_fen : std_logic; -- SPI Flash extended memory enable (bit 19)
    signal spi_mode : std_logic; -- 0 = Master, 1 = Slave (bit 18)
    signal spi_tx_sb : std_logic; -- Transmit swap bytes: '0' = no byte swap, '1' = bytes swapped
    signal spi_rx_sb : std_logic; -- Receive swap bytes: '0' = no byte swap, '1' = bytes swapped
    signal spi_br : std_logic_vector(7 downto 0); -- Baud Rate. Baud rate = SMCLK / (2 * (1 + SCBR))
    signal spi_en : std_logic; -- Enable SPI. '0' = disabled, '1' = enabled
    signal spi_msb : std_logic; -- MSB first. '0' = LSB first, '1' = MSB first
    signal spi_tcie : std_logic; -- Transmit Complete Interrupt Enable. '0' = disabled, '1' = enabled
    signal spi_teie : std_logic; -- Transmit Buffer Empty Interrupt Enable. '0' = disabled, '1' = enabled
    signal spi_dl : std_logic_vector(1 downto 0); -- Data length: "00" = 8-bit transfers, "01" = 16-bit, "10" = 32-bit, "11" = reserved
    signal spi_cpol : std_logic; -- Clock polarity. '0' = low when idle, '1' = high when idle
    signal spi_cpha : std_logic; -- Clock phase. '0' = data sampled on first edge, '1' = data sampled on second edge (master only)

    -- SPIxSR Bit Fields
    signal spi_busy : std_logic; -- SPI Busy. '0' = not busy, '1' = busy
    signal spi_tcif : std_logic; -- Transmit Complete Interrupt Flag. '0' = not completed transmission, '1' = completed transmission
    signal spi_txeif : std_logic; -- Transmit Buffer Empty. '0' = not empty, '1' = empty

    -- SPI Master Internal Signals
    signal en_clk_baud_src : std_logic; -- Enable Clock Baud Rate Source
    signal clk_baud_src : std_logic; -- Clock Baud Rate Source
    signal en_clk_baud : std_logic; -- Enable Clock Baud Rate
    signal clk_baud : std_logic; -- Clock Baud. Frequency selected from CR
    signal baud_counter : std_logic_vector(7 downto 0); -- Baud Rate Counter
    signal start_tx : std_logic; -- Start Transmit
    signal clr_start_tx : std_logic; -- Clear Start Transmit
    signal tx_in_progress : std_logic; -- Transmit in Progress
    signal m_counter : std_logic_vector(5 downto 0); -- Master bit counter, dictates the data length of the transfer 
    signal m_spi_tcif : std_logic; -- Master SPI Transmit Complete Interrupt Flag
    signal m_spi_teif : std_logic; -- Master SPI Transmit Empty Interrupt Flag
    signal m_tx_sreg : std_logic_vector(31 downto 0); -- Master Tx Shift Reg
    signal m_rx_sreg : std_logic_vector(31 downto 0); -- Master Rx Shift Reg
    signal m_SPIxRX : std_logic_vector(31 downto 0); -- Master Receive Register
    signal m_rx_sreg_rev : std_logic_vector(31 downto 0); -- Master Rx Shift Reg Reversed
    signal sck : std_logic; -- SPI Clock

    -- SPI Slave Internal Signals
    signal s_counter : std_logic_vector(5 downto 0); -- Slave Counter
    signal s_spi_tcif : std_logic; -- Slave SPI Transmit Complete Interrupt Flag
    signal s_spi_teif : std_logic; -- Slave SPI Transmit Empty Interrupt Flag
    -- The inter-transfer gap, registered in the sck_slave domain (W5b-2). s_counter is a BINARY counter clocked by the external SCK pad; its zero decode sampled on clk is the crossing hdl/common/sync.vhd forbids by name, because the bits that fall at a carry can reach the decode before the bit that rises and 000111 -> 001000 reads transiently as zero. Registering the decode where it is generated makes the crossing one glitch-free bit, which work.sync then carries.
    signal s_gap : std_logic;
    signal gap_sync_d, gap_sync_q : std_logic_vector(0 downto 0);
    signal s_tx_sreg : std_logic_vector(31 downto 0); -- Slave Tx Shift Reg
    signal s_rx_sreg : std_logic_vector(31 downto 0); -- Slave Rx Shift Reg
    signal s_SPIxRX : std_logic_vector(31 downto 0); -- Slave Receive Register
    signal s_rx_hold_rev : std_logic_vector(31 downto 0); -- Slave Rx Hold Reg Reversed
    signal s_rx_hold : std_logic_vector(31 downto 0); -- Slave Rx Hold Reg: the completed word, captured on the sck_slave falling edge that wraps s_counter
    signal sck_slave : std_logic; -- SPI Clock for Slave. May be inverted sck depending on cpol and cpha

    -- GP Signals 
    signal tx_data_align : std_logic_vector(31 downto 0); -- Aligns and orders Tx Data
    signal m_rx_data_align : std_logic_vector(31 downto 0); -- Aligns and orders Rx Master Data
    signal s_rx_data_align : std_logic_vector(31 downto 0); -- Aligns and orders Rx Slave Data
    signal tx_order_sel : std_logic_vector(3 downto 0); 
    signal rx_order_sel : std_logic_vector(3 downto 0);
    signal clr_spi_teif : std_logic; -- Clear SPI Transmit Empty Interrupt Flag
    signal clr_spi_tcif : std_logic; -- Clear SPI Transmit Complete Interrupt Flag
    signal clr_spi_tcif_req : std_logic;
    signal spi_tx_buf_rev : std_logic_vector(31 downto 0); -- SPI Transmit Buffer Reversed


    -- SPI Flash Extended Memory Signals
    type FlashState_t is (FlashStateCSHigh, FlashStateSendCmd, FlashStateWaitCmd, FlashStateAddr, FlashStateRead, FlashStateIdle1, FlashStateIdle2);
    signal FlashState       : FlashState_t;
    signal ClkFlash         : std_logic;
    signal EnClkFlash       : std_logic;
    signal FlashDelay       : std_logic_vector(1 downto 0);
    signal NextMAB          : std_logic_vector(23 downto 2);
    signal StartTXFlash     : std_logic;
    signal FlashActive      : std_logic;
    signal ClearFlashActive : std_logic;
    signal FlashDL          : std_logic;   -- '0' = 8-bit transfer, '1' = 32-bit transfer
    signal TXDataFlash      : std_logic_vector(31 downto 0);
    signal TXDataFlash_reversed : std_logic_vector(31 downto 0);
    signal mab_top          : std_logic_vector(23 downto 2);

    -- SPIFEM synchronizer signals
    signal en_mem_flash_d1 : std_logic;
    signal en_mem_flash_falling : std_logic;
    signal flash_access_request : std_logic;
    signal flash_complete : std_logic;

    -- New signals for mclk domain synchronization
    signal ClearFlashActive_smclk : std_logic;
    -- The old 3-bit shift was a 2-FF synchroniser plus one edge-detect delay flop. work.sync at DEPTH 2 reproduces stages 0 and 1 exactly, so ClearFlashActive_s2 is the old sync(1) and ClearFlashActive_s3 the old sync(2): same latency, same pulse cycle.
    signal cfa_sync_d, cfa_sync_q : std_logic_vector(0 downto 0);
    signal ClearFlashActive_s2 : std_logic;
    signal ClearFlashActive_s3 : std_logic;
    signal ClearFlashActive_pulse : std_logic;

begin


    /* ------------------- Signal Routing ---------------------
       Register Signal Routing
       SPIxCR, SPIxTX and SPIxFOS come out of the register file; the field
       positions are spi_regs_pkg's, so no bit literal in this file describes a
       register. */
        spi_fen     <= regs_q(RegSlotSPIxCR)(SPIFEN_LSB) when ENABLE_EXTENDED_MEM else '0';
        spi_mode    <= regs_q(RegSlotSPIxCR)(SPISM_LSB);
        spi_tx_sb   <= regs_q(RegSlotSPIxCR)(SPITXSB_LSB);
        spi_rx_sb   <= regs_q(RegSlotSPIxCR)(SPIRXSB_LSB);
        spi_br      <= regs_q(RegSlotSPIxCR)(SPIBR_MSB downto SPIBR_LSB);
        spi_en      <= regs_q(RegSlotSPIxCR)(SPIEN_LSB);
        spi_msb     <= regs_q(RegSlotSPIxCR)(SPIMSB_LSB);
        spi_tcie    <= regs_q(RegSlotSPIxCR)(SPITCIE_LSB);
        spi_teie    <= regs_q(RegSlotSPIxCR)(SPITEIE_LSB);
        spi_dl      <= regs_q(RegSlotSPIxCR)(SPIDL_MSB downto SPIDL_LSB);
        spi_cpol    <= regs_q(RegSlotSPIxCR)(SPICPOL_LSB);
        spi_cpha    <= regs_q(RegSlotSPIxCR)(SPICPHA_LSB);

        SPIxTX      <= regs_q(RegSlotSPIxTX)(SPITX_MSB downto SPITX_LSB);
        SPIxFOS     <= regs_q(RegSlotSPIxFOS)(SPIFOS_MSB downto SPIFOS_LSB);

        -- SPIxSR Bit Field Assignments
        SPIxSR(SPIBUSY_LSB) <= spi_busy; -- Busy
        SPIxSR(SPITCIF_LSB) <= spi_tcif; -- Transmit Complete Interrupt Flag
        SPIxSR(SPITEIF_LSB) <= spi_txeif; -- Transmit Buffer Empty

        -- Pad Routing 
        sck_out <= sck; -- SPI Clock Output
        sck_dir <= '1' when spi_mode = '0' else '0'; -- Note: Do not put this as not spi_mode, as it will not work in Slave Mode
        sck_ren <= sck_ren_in; -- SPI Clock Resistor Enable

        mosi_out <= m_tx_sreg(0); -- SPI MOSI Output
        mosi_dir <= '1' when spi_mode = '0' else '0'; -- Note: Do not put this as not spi_mode, as it will not work in Slave Mode
        mosi_ren <= mosi_ren_in; -- SPI MOSI Resistor Enable

        miso_out <= s_tx_sreg(0); -- SPI MISO Output
        miso_dir <= '0' when spi_mode = '0' or cs_in = '1' or spi_en = '0' else '1'; -- Note: Do not put this as not spi_mode, as it will not work in Slave Mode
        miso_ren <= miso_ren_in; -- SPI MISO Resistor Enable

        SPIxRX <= 
            m_SPIxRX when spi_mode = '0' 
            else s_SPIxRX; 
        
        -- Interrupt Signal Routing
        -- Master is busy while a transfer is pending or running; slave is busy while CS is asserted.
        spi_busy <= (tx_in_progress or start_tx or StartTXFlash) when spi_mode = '0' else not cs_in; 

        spi_tcif <= m_spi_tcif or s_spi_tcif;
        spi_txeif <= m_spi_teif or s_spi_teif;


        irq_tc <= '1' when (spi_tcie = '1' and spi_tcif = '1') else '0';
        irq_te <= '1' when (spi_teie = '1' and spi_txeif = '1') else '0';

        -- Baud Clock Generation
        en_clk_baud_src <= spi_en and 
                            (tx_in_progress or start_tx or StartTXFlash) and 
                            (not spi_mode);

    --End Signal Routing ---------------------

    -- The `not clk` on both baud gates selects which edge of the smclk-domain peripheral clock the baud counter and the master shift FSM advance on; it is NOT the SPI clock polarity (spi_cpol sets the idle sck and the sck_slave xor, spi_cpha toggles sck at transfer start).
    -- Keep both gates on the same edge family: en_clk_baud is combinational off baud_counter=0 and must be stable before clk_baud's active edge, or the baud counter double-counts.
    cg_clk_baud_src: entity work.ClkGate
        port map (
            ClkIn   => not clk, -- baud/shift-clock edge selection, not CPOL
            En      => en_clk_baud_src,
            ClkOut  => clk_baud_src
        );


    -- Baud Rate Counter Process
    baud_cntr_proc: process(clk_baud_src, resetn, spi_en)
    begin
        if resetn = '0' or spi_en = '0' then
            baud_counter <= (others => '0');
        elsif rising_edge(clk_baud_src) then
            if baud_counter = "00000000" then
                baud_counter <= spi_br; -- Set baud counter to baud rate
            else
                baud_counter <= baud_counter - 1;
            end if;
        end if;
    end process;

  
    -- Baud Clock Generation Process
    en_clk_baud <= '1' when baud_counter = "00000000" and en_clk_baud_src = '1' else '0'; 
    cg_clk_baud: entity work.ClkGate
        port map (
            ClkIn   => not clk, -- baud/shift-clock edge selection, not CPOL
            En      => en_clk_baud,
            ClkOut  => clk_baud
    );

    -- Reverse Register Order 
    spi_tx_buf_rev <= reverse_slv_order(SPIxTX);
    m_rx_sreg_rev <= reverse_slv_order(m_rx_sreg);
    s_rx_hold_rev <= reverse_slv_order(s_rx_hold);

    tx_order_sel <= spi_tx_sb & spi_msb & spi_dl; -- Tx Order Selection
    rx_order_sel <= spi_rx_sb & spi_msb & spi_dl; -- Rx Order Selection
 

    --  Align and Order Tx Data ------------------
    process(tx_order_sel, SPIxTX, spi_tx_buf_rev, spi_fen, TXDataFlash_reversed)
    begin
        if spi_fen = '1' and ENABLE_EXTENDED_MEM then
            -- Flash mode: use flash data
            tx_data_align <= TXDataFlash_reversed;
        else
            -- Normal mode: use regular TX data alignment
            case tx_order_sel is
                when "0000" => tx_data_align <= x"000000" & SPIxTX(7 downto 0); -- 8-bit Tx. LSB first, No byte swap 
                when "0001" => tx_data_align <= x"0000" & SPIxTX(15 downto 0); -- 16-bit Tx. LSB first, No byte swap
                when "0010" => tx_data_align <= SPIxTX; -- 32-bit Tx. LSB first, No byte swap
                when "0011" => tx_data_align <= SPIxTX; -- 32-bit Tx. MSB first, No byte swap. Datalength of 11 is dont care
                when "0100" => tx_data_align <= x"000000" & spi_tx_buf_rev(31 downto 24); -- 8-bit Tx. MSB first, No byte swap
                when "0101" => tx_data_align <= x"0000" & spi_tx_buf_rev(31 downto 16); -- 16-bit Tx. MSB first, No byte swap
                when "0110" => tx_data_align <= spi_tx_buf_rev; -- 32-bit Tx. MSB first, No byte swap
                when "0111" => tx_data_align <= spi_tx_buf_rev; -- 32-bit Tx. LSB first, No byte swap. Datalength of 11 is dont care
                when "1000" => tx_data_align <= x"000000" & SPIxTX(7 downto 0); -- 8-bit Tx. LSB first, Byte swap
                when "1001" => tx_data_align <= x"0000" & SPIxTX(7 downto 0) & SPIxTX(15 downto 8); -- 16-bit Tx. LSB first, Byte swap
                when "1010" => tx_data_align <= SPIxTX(7 downto 0) & SPIxTX(15 downto 8) & SPIxTX(23 downto 16) & SPIxTX(31 downto 24); -- 32-bit Tx. LSB first, Byte swap
                when "1011" => tx_data_align <= SPIxTX(7 downto 0) & SPIxTX(15 downto 8) & SPIxTX(23 downto 16) & SPIxTX(31 downto 24); -- 32-bit Tx. MSB first, Byte swap
                when "1100" => tx_data_align <= x"000000" & spi_tx_buf_rev(31 downto 24); -- 8-bit Tx. MSB first, Byte swap
                when "1101" => tx_data_align <= x"0000" & spi_tx_buf_rev(23 downto 16) & spi_tx_buf_rev(31 downto 24); -- 16-bit Tx. MSB first, Byte swap
                when "1110" => tx_data_align <= spi_tx_buf_rev(7 downto 0) & spi_tx_buf_rev(15 downto 8) & spi_tx_buf_rev(23 downto 16) & spi_tx_buf_rev(31 downto 24); -- 32-bit Tx. MSB first, Byte swap
                when others => tx_data_align <= spi_tx_buf_rev(7 downto 0) & spi_tx_buf_rev(15 downto 8) & spi_tx_buf_rev(23 downto 16) & spi_tx_buf_rev(31 downto 24); -- 32-bit Tx. MSB first, Byte swap
            end case;
        end if;
    end process;
        
        -- Align and Order Rx Master Data
        with rx_order_sel select
            m_rx_data_align <=
                x"000000" & m_rx_sreg(31 downto 24)                                                                             when "0000", -- 8-bit Rx. LSB first, No byte swap
                x"0000" & m_rx_sreg(31 downto 16)                                                                               when "0001", -- 16-bit Rx. LSB first, No byte swap
                m_rx_sreg                                                                                                       when "0010", -- 32-bit Rx. LSB first, No byte swap
                m_rx_sreg                                                                                                       when "0011", -- 32-bit Rx. MSB first, No byte swap. Datalength of 11 is dont care
                x"000000" & m_rx_sreg_rev(7 downto 0)                                                                           when "0100", -- 8-bit Rx. MSB first, No byte swap
                x"0000" & m_rx_sreg_rev(15 downto 0)                                                                            when "0101", -- 16-bit Rx. MSB first, No byte swap
                m_rx_sreg_rev                                                                                                   when "0110", -- 32-bit Rx. MSB first, No byte swap
                m_rx_sreg_rev                                                                                                   when "0111", -- 32-bit Rx. LSB first, No byte swap. Datalength of 11 is dont care
                x"000000" & m_rx_sreg(31 downto 24)                                                                             when "1000", -- 8-bit Rx. LSB first, Byte swap
                x"0000" & m_rx_sreg(23 downto 16) & m_rx_sreg(31 downto 24)                                                     when "1001", -- 16-bit Rx. LSB first, Byte swap
                m_rx_sreg(7 downto 0) & m_rx_sreg(15 downto 8) & m_rx_sreg(23 downto 16) & m_rx_sreg(31 downto 24)              when "1010", -- 32-bit Rx. LSB first, Byte swap
                m_rx_sreg(7 downto 0) & m_rx_sreg(15 downto 8) & m_rx_sreg(23 downto 16) & m_rx_sreg(31 downto 24)              when "1011", -- 32-bit Rx. MSB first, Byte swap
                x"000000" & m_rx_sreg_rev(7 downto 0)                                                                           when "1100", -- 8-bit Rx. MSB first, Byte swap
                x"0000" & m_rx_sreg_rev(7 downto 0) & m_rx_sreg_rev(15 downto 8)                                                when "1101", -- 16-bit Rx. MSB first, Byte swap
                m_rx_sreg_rev(7 downto 0) & m_rx_sreg_rev(15 downto 8) & m_rx_sreg_rev(23 downto 16) & m_rx_sreg_rev(31 downto 24) when "1110", -- 32-bit Rx. MSB first, Byte swap
                m_rx_sreg_rev(7 downto 0) & m_rx_sreg_rev(15 downto 8) & m_rx_sreg_rev(23 downto 16) & m_rx_sreg_rev(31 downto 24) when others; -- 32-bit Rx. MSB first, Byte swap
        
        with rx_order_sel select
            s_rx_data_align <=
                x"000000" & s_rx_hold(31 downto 24)                                         when "0000", -- 8-bit Rx. LSB first, No byte swap
                x"0000" & s_rx_hold(31 downto 16)                                           when "0001", -- 16-bit Rx. LSB first, No byte swap
                s_rx_hold(31 downto 0)                                                      when "0010", -- 32-bit Rx. LSB first, No byte swap
                s_rx_hold(31 downto 0)                                                      when "0011", -- 32-bit Rx. MSB first, No byte swap. Datalength of 11 is dont care
                x"000000" & s_rx_hold_rev(7 downto 0)                                       when "0100", -- 8-bit Rx. MSB first, No byte swap
                x"0000" & s_rx_hold_rev(15 downto 0)                                        when "0101", -- 16-bit Rx. MSB first, No byte swap
                s_rx_hold_rev(31 downto 0)                                                  when "0110", -- 32-bit Rx. MSB first, No byte swap
                s_rx_hold_rev(31 downto 0)                                                  when "0111", -- 32-bit Rx. LSB first, No byte swap. Datalength of 11 is dont care
                x"000000" & s_rx_hold(31 downto 24)                                         when "1000", -- 8-bit Rx. LSB first, Byte swap
                x"0000" & s_rx_hold(23 downto 16) & s_rx_hold(31 downto 24)                 when "1001", -- 16-bit Rx. LSB first, Byte swap
                s_rx_hold(7 downto 0) & s_rx_hold(15 downto 8) & s_rx_hold(23 downto 16) & s_rx_hold(31 downto 24) when "1010", -- 32-bit Rx. LSB first, Byte swap
                s_rx_hold(7 downto 0) & s_rx_hold(15 downto 8) & s_rx_hold(23 downto 16) & s_rx_hold(31 downto 24) when "1011", -- 32-bit Rx. LSB first, Byte swap
                x"000000" & s_rx_hold_rev(7 downto 0)                                       when "1100", -- 8-bit Rx. MSB first, Byte swap
                x"0000" & s_rx_hold_rev(7 downto 0) & s_rx_hold_rev(15 downto 8)            when "1101", -- 16-bit Rx. MSB first, Byte swap
                s_rx_hold_rev(7 downto 0) & s_rx_hold_rev(15 downto 8) & s_rx_hold_rev(23 downto 16) & s_rx_hold_rev(31 downto 24) when "1110", -- Byte swap, MSB first, 32-bit
                s_rx_hold_rev(7 downto 0) & s_rx_hold_rev(15 downto 8) & s_rx_hold_rev(23 downto 16) & s_rx_hold_rev(31 downto 24) when others; -- Byte swap, MSB first, 32-bit

    -- SPI Master FSM: loads tx_data_align, toggles sck and shifts one bit per clk_baud edge
    process(resetn, clk_baud, spi_en, spi_mode, tx_in_progress, start_tx, StartTXFlash, clr_spi_teif, clr_spi_tcif, spi_cpol, spi_fen)
    begin
        if resetn = '0' or spi_en = '0' or spi_mode = '1' then
            -- Reset State
            tx_in_progress <= '0';
            clr_start_tx <= '0';
            m_tx_sreg <= (others => '0');
            m_rx_sreg <= (others => '0');
        elsif rising_edge(clk_baud) then
            clr_start_tx <= '0'; -- Clear start transmit signal
            if tx_in_progress = '0' then
                -- Not currently transmitting
                if start_tx = '1' or StartTXFlash = '1' then
                    -- Start Transmit State
                    tx_in_progress <= '1';
                    clr_start_tx <= '1';
                    
                    -- Determine data length based on flash mode
                    if spi_fen = '0' or not ENABLE_EXTENDED_MEM then
                        -- Normal mode
                        case spi_dl is
                            when "00" =>
                                m_counter <= "001111"; -- 8-bit transfer
                            when "01" =>
                                m_counter <= "011111"; -- 16-bit transfer
                            when "10" =>
                                m_counter <= "111111"; -- 32-bit transfer
                            when others =>
                                null;
                        end case;
                    else
                        -- Flash mode
                        if FlashDL = '0' then
                            m_counter <= "001111"; -- 8-bit transfer
                        else
                            m_counter <= "111111"; -- 32-bit transfer
                        end if;
                    end if;
                    
                    if spi_cpha = '1' then 
                        sck <= not sck;
                    end if;
                    m_tx_sreg <= tx_data_align; -- Load Tx Data
                    
                    -- Set TEIF only for non-flash transfers
                    if spi_fen = '0' or not ENABLE_EXTENDED_MEM then
                        m_spi_teif <= '1'; -- new data can be loaded in Tx
                    end if;
                end if;
            else 
                -- Currently transmitting
                if not (m_counter = "000000" and start_tx = '0' and StartTXFlash = '0' and spi_cpha = '1') then
                    sck <= not sck;
                end if;
                if m_counter(0) = '0' then 
                    m_tx_sreg <= '0' & m_tx_sreg(31 downto 1); -- Shift out data
                else --m_counter(0) = '1'
                    m_rx_sreg <= miso_in & m_rx_sreg(31 downto 1); -- Shift in data
                end if;
                -- Check if transmission is complete
                if m_counter = "000000" then
                    -- Set TCIF only for non-flash transfers
                    if spi_fen = '0' or not ENABLE_EXTENDED_MEM then
                        m_spi_tcif <= '1'; -- Set Transmit Complete Interrupt Flag
                    end if;
                    m_SPIxRX <= m_rx_data_align; -- Align received data

                    -- Check for another transfer start condition
                    if start_tx = '1' or StartTXFlash = '1' then
                        clr_start_tx <= '1'; -- Clear start transmit signal
                        m_tx_sreg <= tx_data_align; -- Load Tx Data

                        -- Determine data length based on flash mode
                        if spi_fen = '0' or not ENABLE_EXTENDED_MEM then
                            case spi_dl is
                                when "00" =>
                                    m_counter <= "001111"; -- 8-bit transfer
                                when "01" =>
                                    m_counter <= "011111"; -- 16-bit transfer
                                when "10" =>
                                    m_counter <= "111111"; -- 32-bit transfer
                                when others =>
                                    null;
                            end case;
                        else
                            if FlashDL = '0' then
                                m_counter <= "001111"; -- 8-bit transfer
                            else
                                m_counter <= "111111"; -- 32-bit transfer
                            end if;
                        end if;
                        
                        -- Set TEIF only for non-flash transfers
                        if spi_fen = '0' or not ENABLE_EXTENDED_MEM then
                            m_spi_teif <= '1'; -- new data can be loaded in Tx
                        end if;
                    else
                        tx_in_progress <= '0'; -- Transmission complete, reset state
                    end if;
                else
                -- Transmission in progress
                    m_counter <= m_counter - 1; -- Decrement counter
                end if;
            end if;
        end if;

        -- Check if spi_teif flag clear condtion is met
        if resetn = '0' or clr_spi_teif = '1' or spi_en = '0' or spi_mode = '1' then
            m_spi_teif <= '0'; -- Clear Transmit Empty Interrupt Flag
        end if;

        -- Check if spi_tcif flag clear condition is met
        if resetn = '0' or clr_spi_tcif = '1' or spi_en = '0' or spi_mode = '1' then
            m_spi_tcif <= '0'; -- Clear Transmit Complete Interrupt Flag
        end if;

        -- sck pol value 
        if tx_in_progress = '0' and start_tx = '0' and StartTXFlash = '0' then
            sck <= spi_cpol; -- Set sck to cpol value
        end if;
    end process;



    -- SPI Slave FSM, update phase on the leading edge of sck_slave
    sck_slave <= sck_in xor spi_cpol; -- Invert SCK for Slave if CPOL is set
    process(resetn, spi_mode, spi_en, cs_in, sck_slave, tx_data_align, s_counter)
    begin
        if resetn = '0' or spi_en = '0' or spi_mode = '0' then
            -- Reset State
            s_tx_sreg <= (others => '0');
        elsif s_counter = "000000" then
            -- Asynchronously reload the slave shift register between transfers
            s_tx_sreg <= tx_data_align; -- Load Tx Data
        elsif rising_edge(sck_slave) then -- Leading edge of sck_slave: update phase
                -- Shift Data 
                s_tx_sreg <= '0' & s_tx_sreg(31 downto 1); -- Shift out data
        end if;
    end process;

    -- Slave transmit-empty flag, F12 (2026-09-05). Was set inside the process above by the LEVEL s_counter = 0 and cleared by a trailing if: an SR latch by construction (Genus CDFG-241; 2 LATQX1 cells in every cut). Sampled on clk instead: the gap holds for the whole inter-transfer interval, so the flag rises at the first clk edge of that gap and stays until the bus clears it; its readers (the SR shadow, the irq) are clk-domain, and the clear keeps its priority exactly as before.
    -- What crosses is s_gap, one bit registered on the sck_slave edge that creates the gap, and not the six-bit s_counter's combinational zero decode (W5b-2). F12 moved the flag off the latch and was right to; it left the multi-bit sample behind, which is what this completes. 8-bit mode was immune because the counter only ever spans 0 to 7 and enters zero by the intended wrap; 16-bit mode had one hazardous carry per word and 32-bit mode two.
    gap_sync_d(0) <= s_gap;

    u_sync_s_gap : entity work.sync
        generic map (WIDTH => 1, DEPTH => 2)
        port map (clk => clk, areset => resetn, d => gap_sync_d, q => gap_sync_q);

    process(clk, resetn, clr_spi_teif, spi_en, spi_mode)
    begin
        if resetn = '0' or clr_spi_teif = '1' or spi_en = '0' or spi_mode = '0' then
            s_spi_teif <= '0'; -- Clear Transmit Empty Interrupt Flag
        elsif rising_edge(clk) then
            if gap_sync_q(0) = '1' then
                s_spi_teif <= '1'; -- Set Transmit Empty Interrupt Flag
            end if;
        end if;
    end process;

    -- Was a self-feedback latch ("... when s_counter = 0 else s_SPIxRX") whose enable is an unconstrained level in the external sck_slave pad domain; the capture is now the s_rx_hold register below, matching the master-side m_SPIxRX idiom.
    s_SPIxRX <= s_rx_data_align; -- Assign Slave Receive Register

    -- SPI Slave FSM, sample phase on the trailing edge of sck_slave
    process(resetn, sck_slave, spi_en, spi_mode, cs_in, clr_spi_tcif)
    begin 
        if resetn = '0' or spi_en = '0' or spi_mode = '0' or cs_in = '1' then
            -- Reset State
            s_counter <= (others => '0');
            s_rx_sreg <= (others => '0');
            s_gap     <= '1'; -- deselected or disabled is one long inter-transfer gap

        elsif falling_edge(sck_slave) then -- Sample phase
            s_counter <= s_counter + 1; -- Increment counter
            s_gap     <= '0'; -- default: mid-word; the terminal-count arms below re-raise it
            
            -- Transaction Complete Check
            case spi_dl is
                when "00" => -- 8-bit transfer
                    if s_counter = "000111" then
                        s_spi_tcif <= '1'; -- Set Transmit Complete Interrupt Flag
                        s_counter <= (others => '0'); -- Reset counter
                        s_gap <= '1'; -- word done: the gap opens on this same edge
                        s_rx_hold <= mosi_in & s_rx_sreg(31 downto 1); -- Capture the completed word, including the bit shifted in on this same edge
                    end if;
                when "01" => -- 16-bit transfer
                    if s_counter = "001111" then
                        s_spi_tcif <= '1'; -- Set Transmit Complete Interrupt Flag
                        s_counter <= (others => '0'); -- Reset counter
                        s_gap <= '1'; -- word done: the gap opens on this same edge
                        s_rx_hold <= mosi_in & s_rx_sreg(31 downto 1); -- Capture the completed word, including the bit shifted in on this same edge
                    end if;
                when "10" => -- 32-bit transfer
                    if s_counter = "011111" then
                        s_spi_tcif <= '1'; -- Set Transmit Complete Interrupt Flag
                        s_counter <= (others => '0'); -- Reset counter
                        s_gap <= '1'; -- word done: the gap opens on this same edge
                        s_rx_hold <= mosi_in & s_rx_sreg(31 downto 1); -- Capture the completed word, including the bit shifted in on this same edge
                    end if;
                when others =>
                    -- Reserved or unsupported data length, do nothing. s_gap therefore stays low here, so SPITEIF does not set in the reserved mode; before W5b-2 the free-running counter's wrap through zero set it once every 64 edges, which was an accident of the decode and not a documented behaviour.
                    null;
            end case;

             -- Shift in data
            s_rx_sreg <= mosi_in & s_rx_sreg(31 downto 1); -- Shift in data
           
        end if;

        -- The receive hold register survives cs_in deassertion, unlike the shift register; only a disable or reset clears it.
        if resetn = '0' or spi_en = '0' or spi_mode = '0' then
            s_rx_hold <= (others => '0');
        end if;
        -- Check if spi_tcif flag clear condition is met
        if resetn = '0' or clr_spi_tcif = '1' or spi_en = '0' or spi_mode = '0' then
            s_spi_tcif <= '0'; -- Clear Transmit Complete Interrupt Flag
        end if;
    end process;

    

    -- SPI Flash Extended Memory Core ----------
    -- Generate Flash logic only if ENABLE_EXTENDED_MEM is true
    gen_flash: if ENABLE_EXTENDED_MEM generate
        -- ClearFlashActive crosses smclk to mclk, then a single mclk-cycle pulse on its rising edge.
        cfa_sync_d(0) <= ClearFlashActive_smclk;
        u_sync_ClearFlashActive_smclk : entity work.sync
            generic map (WIDTH => 1, DEPTH => 2)
            port map (clk => mclk, areset => resetn, d => cfa_sync_d, q => cfa_sync_q);
        ClearFlashActive_s2 <= cfa_sync_q(0);

        process(mclk, resetn)
        begin
            if resetn = '0' then
                ClearFlashActive_s3 <= '0';
                ClearFlashActive_pulse <= '0';
            elsif rising_edge(mclk) then
                -- Edge-detect delay flop, the old third shift stage.
                ClearFlashActive_s3 <= ClearFlashActive_s2;
                -- Generate single cycle pulse on rising edge
                ClearFlashActive_pulse <= ClearFlashActive_s2 and not ClearFlashActive_s3;
            end if;
        end process;

        -- Use the pulse for ClearFlashActive in mclk domain
        ClearFlashActive <= ClearFlashActive_pulse;

        -- Activity monitor: a flash fetch on clk_mem_flash raises FlashActive until the FSM clears it
        process (resetn, spi_en, spi_fen, ClearFlashActive, clk_mem_flash, mclk)
        begin
            if resetn = '0' or spi_en = '0' or spi_fen = '0' or ClearFlashActive = '1' then
                FlashActive <= '0';
            elsif rising_edge(clk_mem_flash) then
                if en_mem_flash = '0' then
                    FlashActive <= '1';
                end if;
            end if;
        end process;

        -- Clock generator
        -- clk is smclk
        EnClkFlash <= FlashActive or ClearFlashActive_smclk;
        CGFlash: entity work.ClkGate
        port map
        (
            ClkIn   => clk,
            En      => EnClkFlash,
            ClkOut  => ClkFlash
        );

        -- Flash read FSM: CS-high delay, then command, address, data word, then idle
        process (resetn, spi_en, spi_fen, ClkFlash, clr_start_tx)
        begin
            if resetn = '0' or spi_en = '0' or spi_fen = '0' then
                FlashState <= FlashStateCSHigh;
                FlashDelay <= (others => '0');
                StartTXFlash <= '0';
                ClearFlashActive_smclk <= '0';
                NextMAB <= (others => '0');
            elsif rising_edge(ClkFlash) then
                ClearFlashActive_smclk <= '0';

                if clr_start_tx = '1' then
                    StartTXFlash <= '0';
                end if;

                case FlashState is
                    when FlashStateCSHigh =>
                        -- Hold CS high for the flash deselect delay: 4 ClkFlash cycles, i.e. 4 lfxt cycles when smclk is lfxt
                        FlashDelay <= FlashDelay + 1;

                        if FlashDelay = "11" then
                            FlashDelay <= (others => '0');
                            FlashState <= FlashStateSendCmd;
                        end if;
                    when FlashStateSendCmd =>
                        -- Send the "Continuous Array Read (High Frequency mode)" command: 0x0B
                        StartTXFlash <= '1';
                        FlashState <= FlashStateWaitCmd;
                    when FlashStateWaitCmd =>
                        -- Wait for the command to finish
                        if tx_in_progress = '0' and StartTXFlash = '0' then
                            StartTXFlash <= '1';
                            FlashState <= FlashStateAddr;
                            NextMAB <= mab(23 downto 2);
                        end if;
                    when FlashStateAddr =>
                        -- Send the 24-bit address followed by a blank dummy byte
                        if tx_in_progress = '0' and StartTXFlash = '0' then
                            StartTXFlash <= '1';
                            FlashState <= FlashStateRead;
                        end if;
                    when FlashStateRead =>
                        -- Read the 32-bit word from the SPI flash
                        if tx_in_progress = '0' and StartTXFlash = '0' then
                            FlashState <= FlashStateIdle1;
                            ClearFlashActive_smclk <= '1';
                            NextMAB <= NextMAB + 1;
                        end if;
                    when FlashStateIdle1 =>
                        -- One clock cycle of slack so ClearFlashActive_smclk is back at '0' before Idle2
                        FlashState <= FlashStateIdle2;
                    when FlashStateIdle2 =>
                        -- If the CPU wants the word this stream is already positioned on, keep reading; otherwise raise CS and restart the command.
                        if mab(23 downto 2) = NextMAB then
                            StartTXFlash <= '1';
                            FlashState <= FlashStateRead;
                        else
                            FlashState <= FlashStateCSHigh;
                        end if;
                end case;
            end if;
        end process;

        mab_top <= mab(23 downto 2);

        TXDataFlash <=
            X"0B000000" when FlashState = FlashStateWaitCmd else
            (mab(23 downto 0) + SPIxFOS) & X"00" when FlashState = FlashStateAddr else
            (others => '0');


        TXDataFlash_reversed <= reverse_slv_order(TXDataFlash);
        
        FlashDL <= '0' when FlashState = FlashStateWaitCmd else '1';

        disable_clk_cpu <= FlashActive;
        rdata_flash <= m_SPIxRX;

        cs_flash_out <= '1' when FlashState = FlashStateCSHigh else '0';
        cs_flash_dir <= '1';
        cs_flash_ren <= '0';

    end generate;

    -- Default values when flash is not enabled
    gen_no_flash: if not ENABLE_EXTENDED_MEM generate
        FlashActive <= '0';
        ClearFlashActive <= '0';
        ClearFlashActive_smclk <= '0';
        StartTXFlash <= '0';
        FlashDL <= '0';
        TXDataFlash <= (others => '0');
        TXDataFlash_reversed <= (others => '0');
        disable_clk_cpu <= '0';
        rdata_flash <= (others => '0');
        cs_flash_out <= '1';
        cs_flash_dir <= '0';
        cs_flash_ren <= '0';
    end generate;


    -- Register Synchronization Process
    -- RX and SR are latched INVERTED at the end of the bus access and inverted again on read, so a read returns the value sampled when en_mem fell.
    reg_sync: process(en_mem, SPIxRX, SPIxSR)
    begin
        if falling_edge(en_mem) then 
            SPIxRX_ltch <= not SPIxRX; -- Latch Receive Register
            SPIxSR_ltch <= not SPIxSR; -- Latch Status Register
        end if;
    end process;

    --  Memory Logic ---------------------------

    -- The two words the register file does not store: the status and receive
    -- snapshots, re-inverted here.
    sr_rd <= (31 downto SPIxSR_ltch'high + 1 => '0') & (not SPIxSR_ltch);
    rx_rd <= not SPIxRX_ltch;

    hw_rd_s <= (RegSlotSPIxSR => sr_rd,
                RegSlotSPIxRX => rx_rd,
                others        => (others => '0'));

    -- STROBE_HOLD is true: every strobe this block consumes reaches an
    -- ASYNCHRONOUS clear in a gated baud or slave-sck domain (the four flag
    -- processes below), so it has to be a level held for the whole access and not
    -- a one-clk_mem pulse -- which is byte for byte what the clr_spi_* signals of
    -- the deleted reg_write process were, retired on `en_mem = '1'`.
    -- No WIDEWR: every word here merges per byte lane, as the case decode did.
    u_regs: entity work.periph_regs
        generic map (
            NWORDS      => NWORDS,
            RSTVAL      => RSTVAL,
            IMPL        => IMPL,
            W1C         => W1C,
            WOSET       => WOSET,
            WOT         => WOT,
            PULSE       => PULSE,
            RCLR        => RCLR,
            HWOWN       => HWOWN,
            RDTHRU      => SPI_RDTHRU,
            STROBE_HOLD => true)
        port map (
            ClkMem      => clk_mem,
            resetn      => resetn,
            EnMemPeriph => en_mem,
            WEn         => wen,
            MABPart     => addr_periph,
            wdata       => write_data,
            rdata_out   => read_data,
            regs        => regs_q,
            hw_rd       => hw_rd_s,
            acc_hit     => open,
            rd_hit      => open,
            wr_hit      => wrh_s,
            rd_strobe   => rd_str,
            wr_strobe   => wr_str,
            wr_pulse    => open,
            w1c_hit     => w1c_s,
            woset_hit   => open,
            wot_hit     => open,
            rd_clr      => open);

    -- The transmit-empty flag retires only on a written 1 to its own SR bit.
    clr_spi_teif <= w1c_s(RegSlotSPIxSR)(SPITEIF_LSB);

    -- The transmit-complete flag retires on a written 1 to its SR bit OR on ANY
    -- access to SPIxRX, a read as much as a write. That is a read side effect on a
    -- DIFFERENT register, so it is a hook here rather than an onread property there.
    clr_spi_tcif <= w1c_s(RegSlotSPIxSR)(SPITCIF_LSB)
                    or rd_str(RegSlotSPIxRX) or wr_str(RegSlotSPIxRX);

    -- A write to SPIxTX launches a transfer on the edge it lands, so the set term
    -- takes the module's COMBINATIONAL wr_hit, which is acc_hit qualified by the
    -- lanes exactly as the raw decode's wen /= "1111" was; the registered
    -- wr_strobe would slip the launch a cycle.
    -- Any enabled lane arms it, and in flash mode the launch belongs to the flash
    -- FSM instead. clr_start_tx is asynchronous and wins over a coincident set,
    -- which is the order the deleted reg_write process wrote its two branches in.
    start_tx_proc: process(resetn, clk_mem, clr_start_tx)
    begin
        if resetn = '0' or clr_start_tx = '1' then
            start_tx <= '0'; -- Clear Start Transmit Signal
        elsif rising_edge(clk_mem) then
            if wrh_s(RegSlotSPIxTX) = '1'
               and (spi_fen = '0' or not ENABLE_EXTENDED_MEM) then
                start_tx <= '1';
            end if;
        end if;
    end process;

end behavioral;