-- VestaRV: SPI controller
-- Master/slave SPI with CR/SR/TX/RX/FOS registers, a two-chained-ClkGate baud divider and one IRQ each for transfer-complete and transmit-empty.
-- ENABLE_EXTENDED_MEM instantiates the SPI flash XIP core, which adds a second read port on en_mem_flash.
-- The SLAVE is OVERSAMPLED: SCK, MOSI and CS reach the slave logic through work.sync on clk, the two SCK edges are decoded from the synchronised value, and the slave shift registers, the bit counter and the gap flag are all clk flops. No flop in this file has an external pad on its clock pin. The cost is launch latency on MISO, which is what fixes the maximum slave SCK at an eighth of the peripheral clock: PCLK_HZ / SCK_SLAVE_MAX_HZ state it and it is asserted at elaboration.

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
        ENABLE_EXTENDED_MEM : boolean := false;  -- true instantiates the SPI flash XIP core
        -- The peripheral clock (the clk port) and the fastest SCK an external master may drive into the slave port, both in Hz. They infer no logic: they state the ratio the oversampled slave needs and are checked at elaboration. Master-mode SCK is unaffected -- that one is generated here and SPIxCR.SPIBR sets it.
        PCLK_HZ             : natural := 24000000;
        SCK_SLAVE_MAX_HZ    : natural := 3000000
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
    -- flags and that fills the receive register owns them, and the CDC that
    -- carries them into clk_mem lives below.
    signal regs_q  : reg_arr_t;
    signal hw_rd_s : reg_arr_t;
    signal w1c_s   : reg_arr_t;                        -- a 1 written to a SPIxSR flag
    signal wrh_s   : std_logic_vector(0 to NWORDS-1);  -- ... and the access is a lane write
    signal acc_s   : std_logic_vector(0 to NWORDS-1);  -- combinational: this slot is addressed now
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
    signal SPIxSR_mem : std_logic_vector(2 downto 0); -- SPIxSR carried into clk_mem, three independent flag chains
    signal SPIxRX : std_logic_vector(31 downto 0); -- Receive Register
    signal SPIxRX_mem : std_logic_vector(31 downto 0); -- clk_mem copy of the receive word, loaded at the synchronized receive-event edge
    -- The receive-event toggles, one per core, and their crossing into clk_mem.
    -- A toggle rather than the flag itself: SPITCIF is sticky and a second word
    -- arriving before software clears it raises no new edge, so the copy would
    -- freeze on the first word where the pre-latch returned the newest one.
    signal m_rx_tgl : std_logic;  -- clk_baud domain: master receive-word event
    signal s_rx_tgl : std_logic;  -- clk domain (was the sck_slave domain): slave receive-word event
    signal rx_tgl_d, rx_tgl_q : std_logic_vector(1 downto 0);  -- bit 1 slave, bit 0 master
    signal m_rx_prev, s_rx_prev : std_logic;  -- clk_mem edge-detect stage
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
    -- The inter-transfer gap. W5b-2 made it a flop in the sck_slave domain carried through work.sync, because s_counter was a BINARY counter clocked by the external SCK pad and its zero decode sampled on clk is the crossing hdl/common/sync.vhd forbids by name: at a carry the falling bits can reach the decode before the rising one and 000111 -> 001000 reads transiently as zero. With the counter oversampled, s_gap is generated on clk and read on clk, so the crossing is gone rather than synchronised and u_sync_s_gap went with it. The flag itself is unchanged: raised in the reset arm and at each terminal count, cleared on every other sampled edge.
    signal s_gap : std_logic;
    signal sr_sync_d, sr_sync_q : std_logic_vector(2 downto 0);
    signal tcif_clr_pipe, teif_clr_pipe : std_logic_vector(1 downto 0);
    signal tcif_shadow, teif_shadow : std_logic;
    signal clr_tcif_now, clr_teif_now : std_logic;
    signal busy_pend : std_logic;  -- launch taken, synchronized SPIBUSY not yet high
    signal s_tx_sreg : std_logic_vector(31 downto 0); -- Slave Tx Shift Reg
    signal s_rx_sreg : std_logic_vector(31 downto 0); -- Slave Rx Shift Reg
    signal s_SPIxRX : std_logic_vector(31 downto 0); -- Slave Receive Register
    signal s_rx_hold_rev : std_logic_vector(31 downto 0); -- Slave Rx Hold Reg Reversed
    signal s_rx_hold : std_logic_vector(31 downto 0); -- Slave Rx Hold Reg: the completed word, captured at the sck_slave trailing edge that wraps s_counter
    signal sck_slave : std_logic; -- SPI Clock for Slave, SYNCHRONISED and then inverted by cpol. A data signal, not a clock.

    -- Slave-side pin sampling on clk. See `u_sync_slave_pins`.
    signal slv_sync_d, slv_sync_q : std_logic_vector(2 downto 0); -- (2) cs_in, (1) sck_in, (0) mosi_in
    signal cs_s        : std_logic;  -- synchronised chip select
    signal sck_pin_s   : std_logic;  -- synchronised SCK pad, before the cpol inversion
    signal mosi_s      : std_logic;  -- synchronised MOSI
    signal sck_slave_d : std_logic;  -- sck_slave one clk edge old
    signal sck_lead    : std_logic;  -- decoded leading edge, one clk wide
    signal sck_trail   : std_logic;  -- decoded trailing edge, one clk wide

    /* Minimum peripheral-clock-to-slave-SCK ratio, and where the number comes from.
       The RECEIVE path needs four: the synchroniser resolves a level in two clk
       edges and the edge decode takes a third, so each SCK phase must hold at
       least two clk periods for both edges to be seen. The TRANSMIT path is what
       binds. MISO is launched from the decoded LEADING edge, three clk periods
       after the pad edge in the worst case, and an external master latches it at
       the TRAILING edge one half period later, so the half period must exceed
       three clk periods. Eight clk periods per SCK period is that with one
       period of margin, and it is 3 MHz at 24 MHz.
       No generic keeps the pad-clocked slave alive beside this one. Nothing in
       the tree specifies a slave SCK above 3 MHz -- spi.rdl documents the MASTER
       baud ladder only, and that one is untouched -- and a second architecture
       would have kept sck_slave on a flop clock pin in every mechanical count
       and in the CDC manifest, which is the thing this change exists to remove. */
    constant MIN_PCLK_PER_SCK : natural := 8;

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

    assert PCLK_HZ >= MIN_PCLK_PER_SCK * SCK_SLAVE_MAX_HZ
        report "SPI: peripheral clock " & integer'image(PCLK_HZ)
               & " Hz is below the " & integer'image(MIN_PCLK_PER_SCK)
               & "x minimum for SCK_SLAVE_MAX_HZ " & integer'image(SCK_SLAVE_MAX_HZ)
               & " Hz; the oversampled slave cannot follow that master."
        severity failure;


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
            m_rx_tgl <= '0';
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
                    m_rx_tgl <= not m_rx_tgl;    -- receive-word event into clk_mem

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



    /* -------- Slave-side pin sampling ----------
       SCK, MOSI and CS are asynchronous pads driven by an external master. Until
       2026-09-15 sck_slave was the clock pin of the two processes below, which on
       an FPGA is a fabric clock net (the cpol xor put a LUT between the pad and
       the clock, so it could not even take the dedicated pin route) and in the
       ASIC is a clock domain with one pad in it.

       work.sync carries all three into clk as three INDEPENDENT chains, and the
       cpol inversion is applied AFTER the synchroniser, so the pad reaches a flop
       D pin and nothing else. The two SCK edges are then decoded on clk and every
       slave flop runs on clk. spi_cpol is only ever changed while the block is
       disabled, so the xor cannot manufacture an edge in service. */
    slv_sync_d <= cs_in & sck_in & mosi_in;

    u_sync_slave_pins : entity work.sync
        generic map (WIDTH => 3, DEPTH => 2, RST_VAL => "100")
        port map (clk => clk, areset => resetn, d => slv_sync_d, q => slv_sync_q);

    cs_s      <= slv_sync_q(2);
    sck_pin_s <= slv_sync_q(1);
    mosi_s    <= slv_sync_q(0);

    sck_slave <= sck_pin_s xor spi_cpol; -- Invert SCK for Slave if CPOL is set

    sck_edge_proc: process(clk, resetn)
    begin
        if resetn = '0' then
            sck_slave_d <= '0';
        elsif rising_edge(clk) then
            sck_slave_d <= sck_slave;
        end if;
    end process;

    sck_lead  <= sck_slave and not sck_slave_d;
    sck_trail <= (not sck_slave) and sck_slave_d;

    -- SPI Slave FSM, update phase on the leading edge of sck_slave
    process(resetn, spi_mode, spi_en, clk)
    begin
        if resetn = '0' or spi_en = '0' or spi_mode = '0' then
            -- Reset State
            s_tx_sreg <= (others => '0');
        elsif rising_edge(clk) then
            if s_counter = "000000" then
                -- Reload the slave shift register between transfers. This branch keeps its PRIORITY over the shift below, as it had when it was an asynchronous level: the counter reads zero for the whole of the first bit period, so bit 0 is held there and bit k is presented in bit period k. SPI_tb GROUP 11 grades that stream bit for bit.
                s_tx_sreg <= tx_data_align; -- Load Tx Data
            elsif sck_lead = '1' then -- Leading edge of sck_slave: update phase
                -- Shift Data
                s_tx_sreg <= '0' & s_tx_sreg(31 downto 1); -- Shift out data
            end if;
        end if;
    end process;

    -- Slave transmit-empty flag, F12 (2026-09-05). Was set inside the process above by the LEVEL s_counter = 0 and cleared by a trailing if: an SR latch by construction (Genus CDFG-241; 2 LATQX1 cells in every cut). Sampled on clk instead: the gap holds for the whole inter-transfer interval, so the flag rises at the first clk edge of that gap and stays until the bus clears it; its readers (the SR shadow, the irq) are clk-domain, and the clear keeps its priority exactly as before.
    -- What it reads is s_gap, one bit raised at the edge that creates the gap, and not the six-bit s_counter's combinational zero decode (W5b-2). W5b-2 carried that bit across a domain boundary with work.sync; with the slave oversampled there is no boundary left, s_gap is a clk flop, and the synchroniser is gone. 8-bit mode was immune to the original defect because the counter only ever spans 0 to 7 and enters zero by the intended wrap; 16-bit mode had one hazardous carry per word and 32-bit mode two.
    process(clk, resetn, clr_spi_teif, spi_en, spi_mode)
    begin
        if resetn = '0' or clr_spi_teif = '1' or spi_en = '0' or spi_mode = '0' then
            s_spi_teif <= '0'; -- Clear Transmit Empty Interrupt Flag
        elsif rising_edge(clk) then
            if s_gap = '1' then
                s_spi_teif <= '1'; -- Set Transmit Empty Interrupt Flag
            end if;
        end if;
    end process;

    -- Was a self-feedback latch ("... when s_counter = 0 else s_SPIxRX") whose enable is an unconstrained level in the external sck_slave pad domain; the capture is now the s_rx_hold register below, matching the master-side m_SPIxRX idiom.
    s_SPIxRX <= s_rx_data_align; -- Assign Slave Receive Register

    -- SPI Slave FSM, sample phase on the trailing edge of sck_slave.
    -- The reset takes the SYNCHRONISED chip select, so no pad reaches a flop's asynchronous clear either.
    process(resetn, spi_en, spi_mode, cs_s, clr_spi_tcif, clk)
    begin 
        if resetn = '0' or spi_en = '0' or spi_mode = '0' or cs_s = '1' then
            -- Reset State
            s_counter <= (others => '0');
            s_rx_sreg <= (others => '0');
            s_gap     <= '1'; -- deselected or disabled is one long inter-transfer gap

        elsif rising_edge(clk) then
          if sck_trail = '1' then -- Sample phase
            s_counter <= s_counter + 1; -- Increment counter
            s_gap     <= '0'; -- default: mid-word; the terminal-count arms below re-raise it
            
            -- Transaction Complete Check
            case spi_dl is
                when "00" => -- 8-bit transfer
                    if s_counter = "000111" then
                        s_spi_tcif <= '1'; -- Set Transmit Complete Interrupt Flag
                        s_counter <= (others => '0'); -- Reset counter
                        s_gap <= '1'; -- word done: the gap opens on this same edge
                        s_rx_hold <= mosi_s & s_rx_sreg(31 downto 1); -- Capture the completed word, including the bit shifted in on this same edge
                        s_rx_tgl  <= not s_rx_tgl;  -- receive-word event into clk_mem
                    end if;
                when "01" => -- 16-bit transfer
                    if s_counter = "001111" then
                        s_spi_tcif <= '1'; -- Set Transmit Complete Interrupt Flag
                        s_counter <= (others => '0'); -- Reset counter
                        s_gap <= '1'; -- word done: the gap opens on this same edge
                        s_rx_hold <= mosi_s & s_rx_sreg(31 downto 1); -- Capture the completed word, including the bit shifted in on this same edge
                        s_rx_tgl  <= not s_rx_tgl;  -- receive-word event into clk_mem
                    end if;
                when "10" => -- 32-bit transfer
                    if s_counter = "011111" then
                        s_spi_tcif <= '1'; -- Set Transmit Complete Interrupt Flag
                        s_counter <= (others => '0'); -- Reset counter
                        s_gap <= '1'; -- word done: the gap opens on this same edge
                        s_rx_hold <= mosi_s & s_rx_sreg(31 downto 1); -- Capture the completed word, including the bit shifted in on this same edge
                        s_rx_tgl  <= not s_rx_tgl;  -- receive-word event into clk_mem
                    end if;
                when others =>
                    -- Reserved or unsupported data length, do nothing. s_gap therefore stays low here, so SPITEIF does not set in the reserved mode; before W5b-2 the free-running counter's wrap through zero set it once every 64 edges, which was an accident of the decode and not a documented behaviour.
                    null;
            end case;

             -- Shift in data
            s_rx_sreg <= mosi_s & s_rx_sreg(31 downto 1); -- Shift in data

          end if;
        end if;

        -- The receive hold register survives cs_in deassertion, unlike the shift register; only a disable or reset clears it.
        if resetn = '0' or spi_en = '0' or spi_mode = '0' then
            s_rx_hold <= (others => '0');
            s_rx_tgl  <= '0';
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


    /* -------- Register read CDC ---------------------------------------------
       Nothing here is clocked by en_mem. The two volatile words are carried into
       clk_mem permanently and periph_regs' read register captures them on the
       rising clk_mem edge of the access, so the word it returns is one register's
       value from one edge.

       SPIxSR is three INDEPENDENT flags (busy in the cs_in / clk_baud domains,
       TCIF and TEIF in clk_baud and clk; the slave halves stood in the sck_slave
       domain until it was oversampled), which is what work.sync's WIDTH is for; each bit is two clk_mem edges behind its source. SPIBUSY then ORs
       busy_pend back in, the launch-side pending bit: firmware reads SPIBUSY on
       the very next bus access to see its own launch, and the synchronized copy
       is two clk_mem edges behind it. busy_pend is set by the same wr_hit the
       launch takes and retired by the first clk_mem edge at which the
       synchronized SPIBUSY reads high, so the two overlap and the level never
       dips mid-transfer. It cannot stick: spi_busy is start_tx OR tx_in_progress
       and neither drops before the other rises, so the level is continuously
       high for the whole transfer, which is at least sixteen baud periods; in
       SLAVE mode, where SPIBUSY is not cs_in and start_tx is never consumed, the
       pending bit is not armed at all.

       SPIxRX is a 32-bit word and may not cross bit by bit, so it does not go
       through work.sync at all: the receive-word EVENT crosses as a toggle and
       the data is copied by an ordinary clk_mem flop on the synchronized edge.
       At that edge the source has been stable for two clk_mem periods, because
       the core that wrote it cannot write it again before the next word. */
    sr_sync_d <= SPIxSR;
    u_sync_SPIxSR : entity work.sync
        generic map (WIDTH => 3, DEPTH => 2)
        port map (clk => clk_mem, areset => resetn, d => sr_sync_d, q => sr_sync_q);

    /* Clear shadow. The two W1C flags are cleared ASYNCHRONOUSLY in their own
       domains, so the clear needs the same two clk_mem edges to travel back
       through u_sync_SPIxSR that the set needed coming in, and a read on the
       access after the clearing write would still see the old 1. The two edges
       are masked here, so a flag retires on the next access exactly as it did
       off the falling-en pre-latch. A hardware set inside the window is not
       lost: the source flag is sticky and reappears when the mask retires.
       The arming terms are the COMBINATIONAL access conditions, valid AT the
       access edge, and not the registered clr_spi_* levels: those are held
       strobes that rise after the edge and retire on deselect, so no clk_mem
       edge ever samples them high. */
    clr_tcif_now <= (wrh_s(RegSlotSPIxSR) and not wen(0) and write_data(SPITCIF_LSB))
                    or acc_s(RegSlotSPIxRX);
    clr_teif_now <= wrh_s(RegSlotSPIxSR) and not wen(0) and write_data(SPITEIF_LSB);

    clr_shadow_proc: process(clk_mem, resetn)
    begin
        if resetn = '0' then
            tcif_clr_pipe <= (others => '0');
            teif_clr_pipe <= (others => '0');
        elsif rising_edge(clk_mem) then
            if clr_tcif_now = '1' then tcif_clr_pipe <= (others => '1');
            else tcif_clr_pipe <= '0' & tcif_clr_pipe(1); end if;
            if clr_teif_now = '1' then teif_clr_pipe <= (others => '1');
            else teif_clr_pipe <= '0' & teif_clr_pipe(1); end if;
        end if;
    end process;

    tcif_shadow <= tcif_clr_pipe(0) or tcif_clr_pipe(1);
    teif_shadow <= teif_clr_pipe(0) or teif_clr_pipe(1);

    busy_pend_proc: process(clk_mem, resetn)
    begin
        if resetn = '0' then
            busy_pend <= '0';
        elsif rising_edge(clk_mem) then
            -- Master only, and retired by a disable: in SLAVE mode SPIBUSY is
            -- `not cs_in` and start_tx is never consumed, so a pending bit armed
            -- there would never see a synchronized BUSY and would stick.
            if spi_en = '0' or spi_mode = '1' then
                busy_pend <= '0';
            elsif wrh_s(RegSlotSPIxTX) = '1'
               and (spi_fen = '0' or not ENABLE_EXTENDED_MEM) then
                busy_pend <= '1';
            elsif sr_sync_q(SPIBUSY_LSB) = '1' then
                busy_pend <= '0';
            end if;
        end if;
    end process;

    SPIxSR_mem(SPIBUSY_LSB)  <= sr_sync_q(SPIBUSY_LSB) or busy_pend;
    SPIxSR_mem(SPITCIF_LSB)  <= sr_sync_q(SPITCIF_LSB) and not tcif_shadow;
    SPIxSR_mem(SPITEIF_LSB)  <= sr_sync_q(SPITEIF_LSB) and not teif_shadow;

    rx_tgl_d <= s_rx_tgl & m_rx_tgl;
    u_sync_rx_tgl : entity work.sync
        generic map (WIDTH => 2, DEPTH => 2)
        port map (clk => clk_mem, areset => resetn, d => rx_tgl_d, q => rx_tgl_q);

    -- Master and slave are mutually exclusive by spi_mode, so only one arm ever fires.
    rx_cap_proc: process(clk_mem, resetn)
    begin
        if resetn = '0' then
            m_rx_prev  <= '0';
            s_rx_prev  <= '0';
            SPIxRX_mem <= (others => '0');
        elsif rising_edge(clk_mem) then
            m_rx_prev <= rx_tgl_q(0);
            s_rx_prev <= rx_tgl_q(1);
            if rx_tgl_q(0) /= m_rx_prev then
                SPIxRX_mem <= m_SPIxRX;
            end if;
            if rx_tgl_q(1) /= s_rx_prev then
                SPIxRX_mem <= s_SPIxRX;
            end if;
        end if;
    end process;

    --  Memory Logic ---------------------------

    -- The two words the register file does not store: the clk_mem status and
    -- receive copies built above.
    sr_rd <= (31 downto SPIxSR_mem'high + 1 => '0') & SPIxSR_mem;
    rx_rd <= SPIxRX_mem;

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
            acc_hit     => acc_s,
            rd_hit      => open,
            wr_hit      => wrh_s,
            rd_strobe   => rd_str,
            wr_strobe   => wr_str,
            wr_pulse    => open,
            w1c_hit     => w1c_s,
            woset_hit   => open,
            wot_hit     => open,
            rd_clr      => open);

    /* The two flag clears reach ASYNCHRONOUS clears in the clk_baud and slave-sck
       domains, so their width is what makes them land. They take the registered
       held strobe as before, WIDENED by the clk_mem clear shadow: the access
       condition plus the two shadow stages is a level about two and a half clk_mem
       periods wide, in the clk_mem domain, and it does not depend on how long the
       fabric holds the select. The held strobe alone does: periph_regs retires it
       asynchronously on EnMemPeriph, which the MCU deasserts on the same mclk edge
       the strobe is set, so with the falling-mclk en_q shim gone it would be a runt.
       This is additive - nothing the held strobe did is taken away. */
    clr_spi_teif <= w1c_s(RegSlotSPIxSR)(SPITEIF_LSB) or clr_teif_now or teif_shadow;

    -- The transmit-complete flag retires on a written 1 to its SR bit OR on ANY
    -- access to SPIxRX, a read as much as a write. That is a read side effect on a
    -- DIFFERENT register, so it is a hook here rather than an onread property there.
    clr_spi_tcif <= w1c_s(RegSlotSPIxSR)(SPITCIF_LSB)
                    or rd_str(RegSlotSPIxRX) or wr_str(RegSlotSPIxRX)
                    or clr_tcif_now or tcif_shadow;

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