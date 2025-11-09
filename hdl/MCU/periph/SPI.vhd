library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.constants.all;
use work.MemoryMap.all;

entity SPI is
    generic
    (
        ENABLE_EXTENDED_MEM : boolean := false  
    );
    port
    (
        clk         : in std_logic;
        mclk        : in std_logic;
        resetn      : in std_logic;

        -- IRQ Signals
        irq_tc      : out std_logic;
        irq_te      : out std_logic;

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


    -- Register Signals 
    signal SPIxCR : std_logic_vector(19 downto 0); -- Control Register (extended to 19 for SPIFEN)
    signal SPIxSR : std_logic_vector(2 downto 0); -- Status Register
    signal SPIxSR_ltch : std_logic_vector(2 downto 0); -- Status Register Latched
    signal SPIxRX : std_logic_vector(31 downto 0); -- Receive Register
    signal SPIxRX_ltch : std_logic_vector(31 downto 0); -- Receive Register Latched
    signal SPIxTX : std_logic_vector(31 downto 0); -- Transmit Register
    signal SPIxFOS : std_logic_vector(23 downto 0); -- SPI Flash memory address offset (for extended memory)


    -- Register Bit Field Declarations
    -- SPIxCR Bit Fields
    signal spi_fen : std_logic; -- SPI Flash extended memory enable (bit 19)
    signal spi_mode : std_logic; -- 0 = Master, 1 = Slave (bit 18)
    signal spi_tx_sb : std_logic; -- Transmit swap bytes. '0' <= no byte swap; '1' <= bytes swapped
    signal spi_rx_sb : std_logic; -- Receive swap bytes. '0' <= no byte swap; '1' <= bytes swapped
    signal spi_br : std_logic_vector(7 downto 0); -- Baud Rate. Baud rate = SMCLK / (2 * (1 + SCBR))
    signal spi_en : std_logic; -- Enable SPI. '0' = disabled, '1' = enabled
    signal spi_msb : std_logic; -- MSB first. '0' = LSB first, '1' = MSB first
    signal spi_tcie : std_logic; -- Transmit Complete Interrupt Enable. '0' = disabled, '1' = enabled
    signal spi_teie : std_logic; -- Transmit Buffer Empty Interrupt Enable. '0' = disabled, '1' = enabled
    signal spi_dl : std_logic_vector(1 downto 0); -- Data length. "00" <= 8 bit transfers; "01" <= 16-bit transfers; "10" <= 32-bit transfers; "11" <= reserved
    signal spi_cpol : std_logic; -- Clock polarity. '0' = low when idle, '1' = high when idle
    signal spi_cpha : std_logic; -- Clock phase. '0' = data sampled on first edge, '1' = data sampled on second edge (master only)

    -- SPIxSR Bit Fields
    signal spi_busy : std_logic; -- SPI Busy. '0' = not busy, '1' = busy
    signal spi_tcif : std_logic; -- Transmit Complete Interrupt Flag. '0' = not completed transmission, '1' = completed transmission
    signal spi_txeif : std_logic; -- Transmit Buffer Empty. '0' = not empty, '1' = empty

    -- Memory Map Signals 
    signal en_addr_periph : natural range 0 to 63; -- Enable Memory Peripheral

    -- SPI Master Internal Signals
    signal en_clk_baud_src : std_logic; -- Enable Clock Baud Rate Source
    signal clk_baud_src : std_logic; -- Clock Baud Rate Source
    signal en_clk_baud : std_logic; -- Enable Clock Baud Rate
    signal clk_baud : std_logic; -- Clock Baud. Frequency selected from CR
    signal baud_counter : std_logic_vector(7 downto 0); -- Baud Rate Counter
    signal start_tx : std_logic; -- Start Transmit
    signal clr_start_tx : std_logic; -- Clear Start Transmit
    signal tx_in_progress : std_logic; -- Transmit in Progress
    signal m_counter : std_logic_vector(5 downto 0); --Dictates data length of system 
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
    signal s_tx_sreg : std_logic_vector(31 downto 0); -- Slave Tx Shift Reg
    signal s_rx_sreg : std_logic_vector(31 downto 0); -- Slave Rx Shift Reg
    signal s_SPIxRX : std_logic_vector(31 downto 0); -- Slave Receive Register
    signal s_rx_sreg_rev : std_logic_vector(31 downto 0); -- Slave Rx Shift Reg Reversed
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
    signal FlashDL          : std_logic;   -- '0' <= 8 bits, '1' <= 32 bits
    signal TXDataFlash      : std_logic_vector(31 downto 0);
    signal TXDataFlash_reversed : std_logic_vector(31 downto 0);
    signal mab_top          : std_logic_vector(23 downto 2);
    -- signal clr_flash_active_ack : std_logic;

    -- SPIFEM synchronizer signals
    signal en_mem_flash_d1 : std_logic;
    signal en_mem_flash_falling : std_logic;
    signal flash_access_request : std_logic;
    signal flash_access_request_sync : std_logic_vector(1 downto 0);
    signal flash_complete : std_logic;
    signal flash_complete_sync : std_logic_vector(1 downto 0);

    -- New signals for mclk domain synchronization
    signal ClearFlashActive_smclk : std_logic;
    signal ClearFlashActive_sync : std_logic_vector(2 downto 0);
    signal ClearFlashActive_pulse : std_logic;

begin


    --------------------- Signal Routing ---------------------
        -- Register Signal Routing 
        -- SPIxCR Bit Field Assignments
        spi_fen     <= SPIxCR(19) when ENABLE_EXTENDED_MEM else '0';
        spi_mode    <= SPIxCR(18);
        spi_tx_sb   <= SPIxCR(17);
        spi_rx_sb   <= SPIxCR(16);
        spi_br      <= SPIxCR(15 downto 8);
        spi_en      <= SPIxCR(7);
        spi_msb     <= SPIxCR(6);
        spi_tcie    <= SPIxCR(5);
        spi_teie    <= SPIxCR(4);
        spi_dl      <= SPIxCR(3 downto 2);
        spi_cpol    <= SPIxCR(1);
        spi_cpha    <= SPIxCR(0);

        -- SPIxSR Bit Field Assignments
        SPIxSR(2) <= spi_busy; -- Busy
        SPIxSR(1) <= spi_tcif; -- Transmit Complete Interrupt Flag
        SPIxSR(0) <= spi_txeif; -- Transmit Buffer Empty

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
        spi_busy <= (tx_in_progress or start_tx or StartTXFlash) when spi_mode = '0' else not cs_in; 

        spi_tcif <= m_spi_tcif or s_spi_tcif;
        spi_txeif <= m_spi_teif or s_spi_teif;


        irq_tc <= '1' when (spi_tcie = '1' and spi_tcif = '1') else '0';
        irq_te <= '1' when (spi_teie = '1' and spi_txeif = '1') else '0';

        -- Baud Clock Generation
        en_clk_baud_src <= spi_en and 
                            (tx_in_progress or start_tx or StartTXFlash) and 
                            (not spi_mode);

    ---------------------End Signal Routing ---------------------

    cg_clk_baud_src: entity work.ClkGate
        port map (
            ClkIn   => clk,
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
            ClkIn   => not clk,
            En      => en_clk_baud,
            ClkOut  => clk_baud
    );

    -- Reverse Register Order 
    spi_tx_buf_rev <= reverse_slv_order(SPIxTX);
    m_rx_sreg_rev <= reverse_slv_order(m_rx_sreg);
    s_rx_sreg_rev <= reverse_slv_order(s_rx_sreg);

    tx_order_sel <= spi_tx_sb & spi_msb & spi_dl; -- Tx Order Selection
    rx_order_sel <= spi_rx_sb & spi_msb & spi_dl; -- Rx Order Selection
 

    ------------------  Align and Order Tx Data ------------------
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
                x"000000" & s_rx_sreg(31 downto 24)                                         when "0000", -- 8-bit Rx. LSB first, No byte swap
                x"0000" & s_rx_sreg(31 downto 16)                                           when "0001", -- 16-bit Rx. LSB first, No byte swap
                s_rx_sreg(31 downto 0)                                                      when "0010", -- 32-bit Rx. LSB first, No byte swap
                s_rx_sreg(31 downto 0)                                                      when "0011", -- 32-bit Rx. MSB first, No byte swap. Datalength of 11 is dont care
                x"000000" & s_rx_sreg_rev(7 downto 0)                                       when "0100", -- 8-bit Rx. MSB first, No byte swap
                x"0000" & s_rx_sreg_rev(15 downto 0)                                        when "0101", -- 16-bit Rx. MSB first, No byte swap
                s_rx_sreg_rev(31 downto 0)                                                  when "0110", -- 32-bit Rx. MSB first, No byte swap
                s_rx_sreg_rev(31 downto 0)                                                  when "0111", -- 32-bit Rx. LSB first, No byte swap. Datalength of 11 is dont care
                x"000000" & s_rx_sreg(31 downto 24)                                         when "1000", -- 8-bit Rx. LSB first, Byte swap
                x"0000" & s_rx_sreg(23 downto 16) & s_rx_sreg(31 downto 24)                 when "1001", -- 16-bit Rx. LSB first, Byte swap
                s_rx_sreg(7 downto 0) & s_rx_sreg(15 downto 8) & s_rx_sreg(23 downto 16) & s_rx_sreg(31 downto 24) when "1010", -- 32-bit Rx. LSB first, Byte swap
                s_rx_sreg(7 downto 0) & s_rx_sreg(15 downto 8) & s_rx_sreg(23 downto 16) & s_rx_sreg(31 downto 24) when "1011", -- 32-bit Rx. LSB first, Byte swap
                x"000000" & s_rx_sreg_rev(7 downto 0)                                       when "1100", -- 8-bit Rx. MSB first, Byte swap
                x"0000" & s_rx_sreg_rev(7 downto 0) & s_rx_sreg_rev(15 downto 8)            when "1101", -- 16-bit Rx. MSB first, Byte swap
                s_rx_sreg_rev(7 downto 0) & s_rx_sreg_rev(15 downto 8) & s_rx_sreg_rev(23 downto 16) & s_rx_sreg_rev(31 downto 24) when "1110", -- Byte swap, MSB first, 32-bit
                s_rx_sreg_rev(7 downto 0) & s_rx_sreg_rev(15 downto 8) & s_rx_sreg_rev(23 downto 16) & s_rx_sreg_rev(31 downto 24) when others; -- Byte swap, MSB first, 32-bit

    -- SPI Master FSM
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



    -- SPI Slave FSM (Update Phase - Leading Edge of spi_clk_in)
    sck_slave <= sck_in xor spi_cpol; -- Invert SCK for Slave if CPOL is set
    process(resetn, spi_mode, spi_en, cs_in, sck_slave, clr_spi_teif, tx_data_align, s_counter)
    begin
        if resetn = '0' or spi_en = '0' or spi_mode = '0' then
            -- Reset State
            s_tx_sreg <= (others => '0');
        elsif s_counter = "000000" then
            -- asynchronous latch s_tx_sreg
            s_tx_sreg <= tx_data_align; -- Load Tx Data
            s_spi_teif <= '1'; -- Set Transmit Empty Interrupt Flag

        elsif rising_edge(sck_slave) then --leading edge of sck_slave (update phase)
                -- Shift Data 
                s_tx_sreg <= '0' & s_tx_sreg(31 downto 1); -- Shift out data
        end if;
        -- Check if spi_teif flag clear condtion is met
        if resetn = '0' or clr_spi_teif = '1' or spi_en = '0' or spi_mode = '0' then
            s_spi_teif <= '0'; -- Clear Transmit Empty Interrupt Flag
        end if;
    end process;

    s_SPIxRX <= s_rx_data_align when s_counter = "000000" else s_SPIxRX; -- Assign Slave Receive Register

    -- SPI_Slave FSM (Sample Phase - Trailing Edge of spi_clk_in)
    process(resetn, sck_slave, spi_en, spi_mode, cs_in, clr_spi_tcif)
    begin 
        if resetn = '0' or spi_en = '0' or spi_mode = '0' or cs_in = '1' then
            -- Reset State
            s_counter <= (others => '0');
            s_rx_sreg <= (others => '0');

        elsif falling_edge(sck_slave) then --Sample Phase
            s_counter <= s_counter + 1; -- Increment counter
            
            -- Transaction Complete Check
            case spi_dl is
                when "00" => -- 8-bit transfer
                    if s_counter = "000111" then
                        s_spi_tcif <= '1'; -- Set Transmit Complete Interrupt Flag
                        s_counter <= (others => '0'); -- Reset counter
                    end if;
                when "01" => -- 16-bit transfer
                    if s_counter = "001111" then
                        s_spi_tcif <= '1'; -- Set Transmit Complete Interrupt Flag
                        s_counter <= (others => '0'); -- Reset counter
                    end if;
                when "10" => -- 32-bit transfer
                    if s_counter = "011111" then
                        s_spi_tcif <= '1'; -- Set Transmit Complete Interrupt Flag
                        s_counter <= (others => '0'); -- Reset counter
                    end if;
                when others =>
                    null; -- Reserved or unsupported data length, do nothing
            end case;

             -- Shift in data
            s_rx_sreg <= mosi_in & s_rx_sreg(31 downto 1); -- Shift in data
           
        end if;

        -- Check if spi_tcif flag clear condition is met
        if resetn = '0' or clr_spi_tcif = '1' or spi_en = '0' or spi_mode = '0' then
            s_spi_tcif <= '0'; -- Clear Transmit Complete Interrupt Flag
        end if;
    end process;

    

    ---------- SPI Flash Extended Memory Core ----------
    -- Generate Flash logic only if ENABLE_EXTENDED_MEM is true
    gen_flash: if ENABLE_EXTENDED_MEM generate
        -- Synchronizer for ClearFlashActive from smclk to mclk domain
        -- Creates a single mclk cycle pulse when ClearFlashActive_smclk is asserted
        process(mclk, resetn)
        begin
            if resetn = '0' then
                ClearFlashActive_sync <= (others => '0');
                ClearFlashActive_pulse <= '0';
            elsif rising_edge(mclk) then
                -- Synchronize the signal
                ClearFlashActive_sync <= ClearFlashActive_sync(1 downto 0) & ClearFlashActive_smclk;
                -- Generate single cycle pulse on rising edge
                ClearFlashActive_pulse <= ClearFlashActive_sync(1) and not ClearFlashActive_sync(2);
            end if;
        end process;

        -- Use the pulse for ClearFlashActive in mclk domain
        ClearFlashActive <= ClearFlashActive_pulse;

        -- Activity monitor 
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

        -- State machine 
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
                        -- Set CS high and wait for the delay time (4 cycles of lfxt as smclk !)
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
                        -- This is simply a 1 clock cycle buffer to set ClearFlashActive_smclk back to '0' before Idle2
                        FlashState <= FlashStateIdle2;
                    when FlashStateIdle2 =>
                        -- 
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
    reg_sync: process(en_mem, SPIxRX, SPIxSR)
    begin
        if falling_edge(en_mem) then 
            SPIxRX_ltch <= not SPIxRX; -- Latch Receive Register
            SPIxSR_ltch <= not SPIxSR; -- Latch Status Register
        end if;
    end process;

    --------------------------  Memory Logic ---------------------------
    en_addr_periph <= slv2uint(addr_periph) when en_mem = '0' else 0; -- Enable Memory Peripheral based on address

    -- Register Write Process 
    reg_write: process(resetn, clk_mem, en_mem, clr_start_tx)
    begin
        if resetn = '0' then
            SPIxCR <= (others => '0'); -- Reset Control Register
            SPIxTX <= (others => '0'); -- Reset Transmit Register
            SPIxFOS <= (others => '0'); -- Reset Flash Offset Register
        elsif rising_edge(clk_mem) then
            if en_mem = '0' then 
                case en_addr_periph is 
                    when RegSlotSPIxSR =>
                        if wen(0) = '0' then
                            if write_data(0) = '1' then 
                                clr_spi_teif <= '1'; -- Clear Transmit Empty Interrupt Flag
                            end if;
                            if write_data(1) = '1' then 
                                clr_spi_tcif <= '1'; -- Clear Transmit Complete Interrupt Flag
                            end if;
                        end if;
                    when RegSlotSPIxCR =>
                        if wen(0) = '0' then
                            SPIxCR(7 downto 0) <= write_data(7 downto 0); 
                        end if;
                        if wen(1) = '0' then
                            SPIxCR(15 downto 8) <= write_data(15 downto 8);
                        end if;
                        if wen(2) = '0' then
                            SPIxCR(19 downto 16) <= write_data(19 downto 16);
                        end if;
                    when RegSlotSPIxTX =>
                        -- Writing to TX register only starts normal transmission when not in flash mode
                        if wen(0) = '0' then
                            SPIxTX(7 downto 0) <= write_data(7 downto 0);
                            if spi_fen = '0' or not ENABLE_EXTENDED_MEM then
                                start_tx <= '1';
                            end if;
                        end if;
                        if wen(1) = '0' then
                            SPIxTX(15 downto 8) <= write_data(15 downto 8);
                            if spi_fen = '0' or not ENABLE_EXTENDED_MEM then
                                start_tx <= '1';
                            end if;
                        end if;
                        if wen(2) = '0' then
                            SPIxTX(23 downto 16) <= write_data(23 downto 16);
                            if spi_fen = '0' or not ENABLE_EXTENDED_MEM then
                                start_tx <= '1';
                            end if;
                        end if;
                        if wen(3) = '0' then
                            SPIxTX(31 downto 24) <= write_data(31 downto 24);
                            if spi_fen = '0' or not ENABLE_EXTENDED_MEM then
                                start_tx <= '1';
                            end if;
                        end if;
                    when RegSlotSPIxRX =>
                        clr_spi_tcif <= '1'; -- Clear Transmit Complete Interrupt Flag when reading RX register
                    when RegSlotSPIxFOS =>
                        if ENABLE_EXTENDED_MEM then
                            if wen(0) = '0' then
                                SPIxFOS(7 downto 0) <= write_data(7 downto 0);
                            end if;
                            if wen(1) = '0' then
                                SPIxFOS(15 downto 8) <= write_data(15 downto 8);
                            end if;
                            if wen(2) = '0' then
                                SPIxFOS(23 downto 16) <= write_data(23 downto 16);
                            end if;
                        end if;
                    when others =>
                        null; -- No action for other addresses
                end case;
            end if;
        end if;

        -- Latch signals 
        if resetn = '0' or clr_start_tx = '1' then
            start_tx <= '0'; -- Clear Start Transmit Signal
        end if;
        if resetn = '0' or en_mem = '1' then
            clr_spi_teif <= '0'; -- Clear Transmit Empty Interrupt Flag
            clr_spi_tcif <= '0'; -- Clear Transmit Complete Interrupt Flag
        end if;
    end process;


    -- Register Read Process (Synchronous Read)
    process(clk_mem)
    begin
        if rising_edge(clk_mem) then
            -- Latch Status Register
            case en_addr_periph is
                when RegSlotSPIxSR =>
                    read_data <= (31 downto SPIxSR'high + 1 => '0') & (not SPIxSR_ltch);
                when RegSlotSPIxRX =>
                    -- read_data <= (31 downto SPIxRX'high + 1 => '0') & (not SPIxRX_ltch);
                    -- read_data <= (others => '0') 
                    read_data <= (not SPIxRX_ltch); -- RX register is read as 8-bit only, upper bits are 0
                when RegSlotSPIxTX =>
                    read_data <= SPIxTX;
                when RegSlotSPIxCR =>
                    read_data <= (31 downto SPIxCR'high + 1 => '0') & SPIxCR;
                when RegSlotSPIxFOS =>
                    if ENABLE_EXTENDED_MEM then
                        read_data <= (31 downto SPIxFOS'high + 1 => '0') & SPIxFOS;
                    else
                        read_data <= (others => '0');
                    end if;
                when others =>
                    read_data <= (others => '0');
            end case;
        end if;
    end process;

end behavioral;