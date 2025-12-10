library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.constants.all;
use work.MemoryMap.all;

entity UART is
    port
    (
        -- System Signals
        clk             : in    std_logic;  -- Sub-main clock
        resetn          : in    std_logic;  -- System reset

        irq_rc          : out   std_logic;  -- RX Complete Interrupt
        irq_te          : out   std_logic;  -- TX Empty Interrupt
        irq_tc          : out   std_logic;  -- TX Complete Interrupt
        
        -- Memory Bus
        clk_mem         : in    std_logic;
        en_mem          : in    std_logic;
        wen             : in    std_logic_vector(3 downto 0);
        addr_periph     : in    std_logic_vector(7 downto 2);
        write_data      : in    word;
        read_data       : out   word;
        
        -- Pad Interface
        TX_OUT          : out   std_logic;
        TX_DIR          : out   std_logic;
        TX_REN          : out   std_logic;
        
        RX_IN           : in    std_logic;
        RX_OUT          : out   std_logic;
        RX_DIR          : out   std_logic;
        RX_REN          : out   std_logic
    );
end entity UART;

architecture Behavioral of UART is

    -- =============================================================================
    -- Constants
    -- =============================================================================
    constant BAUD_COUNTER_RESET : std_logic_vector(11 downto 0) := (others => '0');
    constant TX_CLOCK_RESET     : std_logic_vector(3 downto 0) := (others => '0');
    constant TX_CLOCK_MAX       : std_logic_vector(3 downto 0) := (others => '1');
    constant RX_CLOCK_RESET     : std_logic_vector(3 downto 0) := "1111";
    constant BIT_COUNTER_START  : std_logic_vector(3 downto 0) := "1010"; -- 10 bits
    constant UD_COUNTER_INIT    : std_logic_vector(5 downto 0) := "100000"; -- 32 (middle value)
    constant RX_SAMPLE_POINT    : std_logic_vector(3 downto 0) := "0111"; -- Sample at 7/16
    constant BIT_COUNT_PARITY   : std_logic_vector(3 downto 0) := "0001";
    constant BIT_COUNT_STOP     : std_logic_vector(3 downto 0) := "0000";

    -- =============================================================================
    -- Memory-Mapped Registers
    -- =============================================================================
    signal UART_CR : std_logic_vector(5 downto 0);
    signal UART_SR : std_logic_vector(7 downto 0);
    signal UART_RX : std_logic_vector(7 downto 0);
    signal UART_TX : std_logic_vector(7 downto 0);
    signal UART_BR : std_logic_vector(11 downto 0); -- Baud = smclk / (16 * (UARTxBR + 1))
    signal UART_SR_ltch : std_logic_vector(7 downto 0); -- Latched version for reading
    signal UART_RX_ltch : std_logic_vector(7 downto 0); -- Latched version for reading

    -- =============================================================================
    -- UART Control Register Bit Definitions
    -- =============================================================================
    signal UCR_EN   : std_logic; -- UART Enable
    signal UCR_PEN  : std_logic; -- Parity Enable
    signal UCR_PSEL : std_logic; -- Parity Select (0 = Even, 1 = Odd)
    signal UCR_CIE  : std_logic; -- RX Complete Interrupt Enable
    signal UCR_TEIE : std_logic; -- TX Empty Interrupt Enable
    signal UCR_TCIE : std_logic; -- TX Complete Interrupt Enable

    -- =============================================================================
    -- UART Status Register Bit Definitions
    -- =============================================================================
    signal USR_RX_busy : std_logic; -- RX Busy Flag
    signal USR_TX_busy : std_logic; -- TX Busy Flag
    signal USR_FEF     : std_logic; -- Framing Error Flag
    signal USR_PEF     : std_logic; -- Parity Error Flag
    signal USR_OVF     : std_logic; -- RX Overflow Flag
    signal USR_RCIF    : std_logic; -- RX Complete Interrupt Flag
    signal USR_UTEIF   : std_logic; -- TX Empty Interrupt Flag
    signal USR_UTCIF   : std_logic; -- TX Complete Interrupt Flag

    -- =============================================================================
    -- Memory Interface Signals
    -- =============================================================================
    signal en_addr_periph : natural range 0 to 63; -- Enable Memory Peripheral

    -- =============================================================================
    -- Clock Generation Signals
    -- =============================================================================
    signal en_baud_clk_src : std_logic;
    signal baud_clk_src : std_logic;
    signal en_clk_baud : std_logic;
    signal clk_baud : std_logic;
    signal en_clk_tx : std_logic;
    signal clk_tx : std_logic;
    signal baud_cntr : std_logic_vector(11 downto 0);

    -- =============================================================================
    -- UART Transmitter Signals
    -- =============================================================================
    signal tx_sr : std_logic_vector(8 downto 0); -- TX Shift Register 
    signal tx_in_progress : std_logic;
    signal start_tx : std_logic;
    signal tx_write : std_logic; 
    signal clr_start_tx : std_logic;
    signal tx_clk_cntr : std_logic_vector(3 downto 0);
    signal tx_bit_cntr : std_logic_vector(3 downto 0);
    signal tx_parity : std_logic;

    -- =============================================================================
    -- UART Receiver Signals
    -- =============================================================================
    signal rx_sr : std_logic_vector(8 downto 0); -- RX Shift Register
    signal rx_in_progress : std_logic;
    signal clr_rx_in_progress : std_logic;
    signal rx_clk_cntr : std_logic_vector(3 downto 0);
    signal rx_bit_cntr : std_logic_vector(3 downto 0);
    signal rx_parity : std_logic; 
    signal ud_cntr : std_logic_vector(5 downto 0); -- Avg number of 1s and 0s on RX
    signal ud_cntr_next : std_logic_vector(5 downto 0);
    signal rx_in_prev : std_logic; -- Previous RX input state

    -- =============================================================================
    -- Control and Status Signals
    -- =============================================================================
    signal clr_SR_RX : std_logic; -- Clear RX flags in Status Register
    signal clr_UTEIF : std_logic; -- Clear TX Empty Interrupt Flag
    signal clr_UTCIF : std_logic; -- Clear TX Complete Interrupt Flag
    signal clr_URCIF : std_logic; -- Clear RX Complete Interrupt Flag

begin 

    -- =============================================================================
    -- Register Bit Assignments
    -- =============================================================================
    
    -- UART Control Register Bit Mapping
    UCR_EN   <= UART_CR(5);  -- UART Enable
    UCR_PEN  <= UART_CR(4);  -- Parity Enable
    UCR_PSEL <= UART_CR(3);  -- Parity Select (0 = Even, 1 = Odd)
    UCR_CIE  <= UART_CR(2);  -- RX Complete Interrupt Enable
    UCR_TEIE <= UART_CR(1);  -- TX Empty Interrupt Enable
    UCR_TCIE <= UART_CR(0);  -- TX Complete Interrupt Enable

    -- UART Status Register Bit Mapping
    UART_SR(7) <= USR_RX_busy; -- RX Busy Flag
    UART_SR(6) <= USR_TX_busy; -- TX Busy Flag
    UART_SR(5) <= USR_FEF;     -- Framing Error Flag
    UART_SR(4) <= USR_PEF;     -- Parity Error Flag
    UART_SR(3) <= USR_OVF;     -- RX Overflow Flag
    UART_SR(2) <= USR_RCIF;    -- RX Complete Interrupt Flag
    UART_SR(1) <= USR_UTEIF;   -- TX Empty Interrupt Flag
    UART_SR(0) <= USR_UTCIF;   -- TX Complete Interrupt Flag

    -- =============================================================================
    -- Interrupt Outputs
    -- =============================================================================
    irq_rc <= UCR_CIE and USR_RCIF;
    irq_te <= UCR_TEIE and USR_UTEIF;
    irq_tc <= UCR_TCIE and USR_UTCIF;

    -- =============================================================================
    -- Baud Rate Clock Generation
    -- =============================================================================
    
    -- Enable baud clock source when UART is active
    en_baud_clk_src <= UCR_EN and (tx_in_progress or rx_in_progress or start_tx or clr_rx_in_progress);
    -- en_baud_clk_src <= UCR_EN;

    -- Gated baud clock source
    cgu_baud_clk_src : entity work.ClkGate
    port map
    (
        ClkIn => clk,
        En => en_baud_clk_src,
        ClkOut => baud_clk_src
    );

    -- Baud rate counter process
    baud_counter_proc: process(resetn, baud_clk_src, UCR_EN)
    begin 
        if resetn = '0' or UCR_EN = '0' then
            baud_cntr <= BAUD_COUNTER_RESET;
        elsif rising_edge(baud_clk_src) then
            if baud_cntr = BAUD_COUNTER_RESET then
                baud_cntr <= UART_BR;
            else 
                baud_cntr <= std_logic_vector(unsigned(baud_cntr) - 1);
            end if;
        end if;
    end process;

    -- Generate baud clock enable
    en_clk_baud <= '1' when (en_baud_clk_src = '1' and baud_cntr = BAUD_COUNTER_RESET) else '0';

    -- Gated baud clock
    cg_clk_baud : entity work.ClkGate
    port map
    (
        ClkIn => baud_clk_src,
        En => en_clk_baud,
        ClkOut => clk_baud
    );

    -- =============================================================================
    -- UART Transmitter Section
    -- =============================================================================
    
    -- TX Clock Generation Process
    tx_clock_gen_proc: process(resetn, clk_baud, UCR_EN)
    begin 
        if resetn = '0' or UCR_EN = '0' then
            tx_clk_cntr <= TX_CLOCK_RESET;
        elsif rising_edge(clk_baud) then
            if tx_in_progress = '1' or start_tx = '1' then
                if tx_clk_cntr = TX_CLOCK_RESET then
                    tx_clk_cntr <= TX_CLOCK_MAX;
                else
                    tx_clk_cntr <= std_logic_vector(unsigned(tx_clk_cntr) - 1);
                end if;
            end if;
        end if;
    end process;

    -- TX clock enable generation
    en_clk_tx <= '1' when (en_clk_baud = '1' and 
                          (tx_in_progress = '1' or start_tx = '1') and 
                          (tx_clk_cntr = TX_CLOCK_RESET)) else '0';


    -- Gated TX clock
    cg_clk_tx : entity work.ClkGate
    port map
    (
        ClkIn => clk_baud,
        En => en_clk_tx,
        ClkOut => clk_tx
    );

    -- TX Finite State Machine 
    TX_FSM : process(resetn, clk_tx, clr_UTCIF, clr_UTEIF)
    begin 
        if resetn = '0' or UCR_EN = '0' then
            tx_in_progress <= '0';
            tx_sr <= (others => '0'); 
            tx_bit_cntr <= TX_CLOCK_RESET;
            tx_parity <= '0';
            USR_UTEIF <= '0';
            USR_UTCIF <= '0';
            clr_start_tx <= '0';
        elsif rising_edge(clk_tx) then
            -- Default assignments for one-cycle pulses
            clr_start_tx <= '0';

            if tx_in_progress = '0' then
                -- Idle state - not transmitting
                if start_tx = '1' then
                    -- Start new transmission
                    clr_start_tx <= '1';
                    tx_sr <= UART_TX & '0'; -- Load data + start bit
                    tx_bit_cntr <= BIT_COUNTER_START;
                    tx_parity <= UCR_PSEL; -- Initialize parity bit
                    tx_in_progress <= '1';
                    USR_UTEIF <= '1'; -- Set TX Empty flag to indicate ready for new data
                end if;
            else 
                -- Transmission in progress
                tx_sr <= '0' & tx_sr(8 downto 1); -- Shift in stop bit
                
                -- Check for transmission completion
                if (tx_bit_cntr = BIT_COUNT_STOP) or 
                (tx_bit_cntr = BIT_COUNT_PARITY and UCR_PEN = '0') then
                    -- Transmission complete
                    
                    if start_tx = '1' then
                        -- Chain next transmission immediately
                        clr_start_tx <= '1';
                        tx_sr <= UART_TX & '0'; -- Load new data + start bit
                        tx_bit_cntr <= BIT_COUNTER_START;
                        tx_parity <= UCR_PSEL; -- Initialize parity bit
                        USR_UTEIF <= '1'; 
                    else 
                        -- No new transmission, go idle and set completion flag
                        tx_in_progress <= '0';
                        USR_UTCIF <= '1'; -- Set TX Complete flag only when truly complete
                    end if;
                else
                    -- Continue transmission
                    tx_bit_cntr <= std_logic_vector(unsigned(tx_bit_cntr) - 1);
                    tx_parity <= tx_parity xor tx_sr(0); -- Update parity
                end if;
            end if;
        end if;

            -- Handle interrupt flag clearing
            if clr_UTEIF = '1' then
                USR_UTEIF <= '0';
            end if;
            if clr_UTCIF = '1' then
                USR_UTCIF <= '0';
            end if;
 
    end process;

    -- TX Output Logic (Combinational)
    tx_output_proc : process(resetn, UCR_EN, UCR_PEN, tx_in_progress, tx_sr, tx_bit_cntr, tx_parity)
    begin 
        if resetn = '0' or UCR_EN = '0' or tx_in_progress = '0' then
            TX_OUT <= '1'; -- Idle state (mark)
        elsif UCR_PEN = '1' then 
            -- Parity enabled
            if tx_bit_cntr = BIT_COUNT_PARITY then
                TX_OUT <= tx_parity; -- Send parity bit
            elsif tx_bit_cntr = BIT_COUNT_STOP then
                TX_OUT <= '1'; -- Send stop bit
            else 
                TX_OUT <= tx_sr(0); -- Send data and start bits
            end if;
        else 
            -- Parity disabled
            if tx_bit_cntr = BIT_COUNT_PARITY then
                TX_OUT <= '1'; -- Send stop bit (no parity)
            else 
                TX_OUT <= tx_sr(0); -- Send data and start bits
            end if;
        end if;     
    end process;

    -- =============================================================================
    -- UART Receiver Section
    -- =============================================================================


    -- RX Start Bit Detection (Synchronous) - Keep this as is
    rx_start_detect_proc: process(clk, resetn)
        variable rx_in_prev : std_logic := '1';
    begin
        if resetn = '0' then
            rx_in_progress <= '0';
            rx_in_prev := '1';
        elsif falling_edge(clk) then
            if UCR_EN = '0' or clr_rx_in_progress = '1' then
                rx_in_progress <= '0';
            elsif rx_in_prev = '1' and RX_IN = '0' then
                rx_in_progress <= '1'; -- Falling edge detected (start bit)
            end if;
            rx_in_prev := RX_IN;
        end if;
    end process;

    -- RX bit sampling logic
    ud_cntr_next <= std_logic_vector(unsigned(ud_cntr) + 1) when RX_IN = '1' else 
                    std_logic_vector(unsigned(ud_cntr) - 1);


    -- RX Finite State Machine 
    RX_FSM : process(resetn, clk_baud, en_clk_baud, UCR_EN, UCR_PEN, UCR_PSEL, clr_SR_RX, clr_URCIF)
    begin 
        if resetn = '0' or rx_in_progress = '0' then
            rx_bit_cntr <= BIT_COUNTER_START; -- was "1010"
            rx_clk_cntr <= RX_CLOCK_RESET;    -- was (others => '1') = "1111"
            clr_rx_in_progress <= '0';
            ud_cntr <= UD_COUNTER_INIT;       -- was "100000"
        elsif rising_edge(clk_baud) then
            clr_rx_in_progress <= '0';
            if rx_in_progress = '1' then
                ud_cntr <= ud_cntr_next; -- Update average number of 1s and 0s on RX
                if rx_clk_cntr = TX_CLOCK_RESET then -- was "0000"
                    -- sample rx
                    rx_sr <= ud_cntr_next(5) & rx_sr(8 downto 1); -- Shift in new bit
                    rx_parity <= rx_parity xor ud_cntr_next(5); -- Update parity bit

                    -- Ensure valid start bit
                    if rx_bit_cntr = BIT_COUNTER_START then -- was "1010"
                        if ud_cntr_next(5) = '1' then
                            -- invalid
                            clr_rx_in_progress <= '1'; -- Clear RX in progress
                        end if;
                    end if;
                
                    rx_bit_cntr <= std_logic_vector(unsigned(rx_bit_cntr) - 1); -- Decrement bit counter
                    rx_clk_cntr <= RX_CLOCK_RESET; -- Reset clock counter, was "1111"
                    ud_cntr <= UD_COUNTER_INIT; -- Reset average counter, was "100000"
                else
                    rx_clk_cntr <= std_logic_vector(unsigned(rx_clk_cntr) - 1); -- Decrement clock counter

                    -- init RX_Parity 
                    if rx_bit_cntr = BIT_COUNTER_START then -- was "1010"
                        rx_parity <= UCR_PSEL; -- Initialize parity bit
                    end if;

                end if;
                
                if rx_clk_cntr = RX_SAMPLE_POINT and (rx_bit_cntr = BIT_COUNT_STOP or (rx_bit_cntr = BIT_COUNT_PARITY and UCR_PEN = '0')) then
                    -- was: rx_clk_cntr = "0111" and (rx_bit_cntr = "0000" or (rx_bit_cntr = "0001" and UCR_PEN = '0'))
                    -- RX complete

                    -- Update UART_RX and check for parity error
                    if UCR_PEN = '1' then
                        --Set parity error flag if parity does not match
                        USR_PEF <= rx_parity;

                        -- Place received data in UART_RX
                        UART_RX <= rx_sr(7 downto 0); -- Store received data
                    else 
                        USR_PEF <= '0'; -- Clear Parity Error Flag
                        UART_RX <= rx_sr(8 downto 1); -- Store MSBs in UART_RX
                    end if;

                    -- Overflow check 
                    if USR_UTCIF = '1' then 
                        -- RX has not been read by core since last write, therefore there is now overflow 
                        USR_OVF <= '1'; -- Set Overflow Flag
                    end if;

                    USR_FEF <= not RX_IN; -- Set Framing Error Flag if RX_IN is not high (stop bit)
                    USR_RCIF <= '1'; -- Receive Complete
                    clr_rx_in_progress <= '1'; -- Clear RX in progress

                end if;
            end if;       
        end if;

        -- Clear SR when RX is read
        if resetn = '0' or clr_SR_RX = '1' then
            USR_OVF <= '0';
            USR_FEF <= '0';
            USR_RCIF <= '0';
            USR_PEF <= '0';
        end if;
    
        if clr_URCIF = '1' then
            USR_RCIF <= '0';
        end if;

        if resetn = '0' then 
            UART_RX <= (others => '0');
        end if;

    end process;

    -- =============================================================================
    -- Status Signal Assignments
    -- =============================================================================
    USR_RX_busy <= rx_in_progress;
    USR_TX_busy <= tx_in_progress or start_tx;

    -- =============================================================================
    -- Pad Control Assignments
    -- =============================================================================
    TX_DIR <= '1'; -- TX pad in output mode
    TX_REN <= '0'; -- Disable pull resistor
    RX_OUT <= '0'; -- RX_OUT not used
    RX_DIR <= '0'; -- RX pad in input mode
    RX_REN <= '0'; -- Disable pull resistor

    -- =============================================================================
    -- Register Synchronization for Memory Interface
    -- =============================================================================
    reg_sync: process(en_mem, UART_RX, UART_SR)
    begin
        if falling_edge(en_mem) then 
            UART_SR_ltch <= not UART_SR;
            UART_RX_ltch <= not UART_RX;
        end if;
    end process;

    -- =============================================================================
    -- Memory-Mapped Register Interface
    -- =============================================================================
    
    -- Address decoding
    en_addr_periph <= slv2uint(addr_periph) when en_mem = '0' else 0;

    -- Register Write Process 
    reg_write_proc: process(resetn, clk_mem)
    begin
        if resetn = '0' then
            UART_CR <= (others => '0');
            UART_TX <= (others => '0');
            UART_BR <= (others => '0');
            clr_SR_RX <= '0';
            clr_UTCIF <= '0';
            clr_UTEIF <= '0';
            clr_URCIF <= '0';
        elsif rising_edge(clk_mem) then
            -- Default values for one-cycle pulses
            clr_SR_RX <= '0';
            clr_UTCIF <= '0';
            clr_UTEIF <= '0';
            clr_URCIF <= '0';
            
            -- Handle register writes
            if en_mem = '0' then 
                case en_addr_periph is 
                    when RegSlotUARTxCR =>
                        if wen(0) = '0' then
                            UART_CR(5 downto 0) <= write_data(5 downto 0); 
                        end if;
                    when RegSlotUARTxSR =>
                        if wen(0) = '0' then
                            if write_data(0) = '1' then
                                clr_UTCIF <= '1';
                            end if;
                            if write_data(1) = '1' then
                                clr_UTEIF <= '1';
                            end if;
                            if write_data(2) = '1' then 
                                clr_URCIF <= '1';
                            end if;
                        end if;
                    when RegSlotUARTxBR =>
                        if wen(0) = '0' then
                            UART_BR(7 downto 0) <= write_data(7 downto 0);
                        end if;
                        if wen(1) = '0' then
                            UART_BR(11 downto 8) <= write_data(11 downto 8);
                        end if;
                    when RegSlotUARTxTX =>
                        if wen(0) = '0' then
                            UART_TX <= write_data(7 downto 0);
                            -- start_tx handling moved to separate process
                        end if;
                    when RegSlotUARTxRX =>
                        clr_SR_RX <= '1';
                    when others =>
                        null;
                end case;
            end if;
            
            -- -- Handle other clear signals
            -- if en_mem = '1' then
            --     clr_UTCIF <= '0';
            --     clr_UTEIF <= '0';
            --     clr_SR_RX <= '0';
            -- end if;
        end if;
    end process;

    -- Separate process for start_tx with async clear
    start_tx_proc: process(resetn, clk_mem, clr_start_tx)
    begin
        start_tx <= start_tx;
        if resetn = '0' or clr_start_tx = '1' then
            start_tx <= '0';
        elsif rising_edge(clk_mem) then
            -- Set start_tx when writing to TX register
            if en_mem = '0' and en_addr_periph = RegSlotUARTxTX and wen(0) = '0' then
                start_tx <= '1';
            end if;
        end if;
    end process;

    -- Register Read Process 
    reg_read_proc: process(clk_mem)
    begin
        if rising_edge(clk_mem) then
            case en_addr_periph is
                when RegSlotUARTxCR =>
                    read_data <= (31 downto UART_CR'high + 1 => '0') & UART_CR;
                when RegSlotUARTxBR =>
                    read_data <= (31 downto UART_BR'high + 1 => '0') & UART_BR;
                when RegSlotUARTxSR =>
                    read_data <= (31 downto UART_SR'high + 1 => '0') & (not UART_SR_ltch);
                when RegSlotUARTxRX =>
                    read_data <= (31 downto UART_RX'high + 1 => '0') & (not UART_RX_ltch);
                when RegSlotUARTxTX =>
                    read_data <= (31 downto UART_TX'high + 1 => '0') & UART_TX;
                when others =>
                    read_data <= (others => '0'); -- Return zeros for unmapped addresses
            end case;
        end if;
    end process;

end Behavioral;