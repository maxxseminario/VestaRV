library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.Constants.all;
use work.MemoryMap.all;

entity TIMER is
    port (
        -- ==========================================
        -- Clock Inputs
        -- ==========================================
        mclk         : in  std_logic;                      -- Main clock
        smclk        : in  std_logic;                      -- Sub-main clock
        clk_lfxt     : in  std_logic;                      -- Low-frequency crystal clock
        clk_hfxt     : in  std_logic;                      -- High-frequency crystal clock
        resetn       : in  std_logic;                      -- System reset (active-low)

        -- ==========================================
        -- Interrupt Outputs
        -- ==========================================
        irq_cap0     : out std_logic;                      -- Capture 0 interrupt request
        irq_cap1     : out std_logic;                      -- Capture 1 interrupt request
        irq_ovf      : out std_logic;                      -- Overflow interrupt request
        irq_cmp0     : out std_logic;                      -- Compare 0 interrupt request
        irq_cmp1     : out std_logic;                      -- Compare 1 interrupt request
        irq_cmp2     : out std_logic;                      -- Compare 2 interrupt request

        -- ==========================================
        -- Memory-Mapped Register Interface
        -- ==========================================
        clk_mem      : in  std_logic;                      -- Memory interface clock
        en_mem       : in  std_logic;                      -- Memory enable (active-low)
        wen          : in  std_logic_vector(3 downto 0);   -- Write enable (active-low)
        addr_periph  : in  std_logic_vector(7 downto 2);   -- Peripheral register address
        write_data   : in  std_logic_vector(31 downto 0);  -- Write data bus
        read_data    : out std_logic_vector(31 downto 0);  -- Read data bus

        -- ==========================================
        -- Compare Output 0 Pin Interface
        -- ==========================================
        cmp0_ren_in  : in  std_logic;                      -- Compare 0 resistor config
        cmp0_out     : out std_logic;                      -- Compare 0 output value
        cmp0_dir     : out std_logic;                      -- Compare 0 direction (always output)
        cmp0_ren     : out std_logic;                      -- Compare 0 resistor enable

        -- ==========================================
        -- Compare Output 1 Pin Interface
        -- ==========================================
        cmp1_ren_in  : in  std_logic;                      -- Compare 1 resistor config
        cmp1_out     : out std_logic;                      -- Compare 1 output value
        cmp1_dir     : out std_logic;                      -- Compare 1 direction (always output)
        cmp1_ren     : out std_logic;                      -- Compare 1 resistor enable

        -- ==========================================
        -- Capture Input 0 Pin Interface
        -- ==========================================
        cap0_ren_in  : in  std_logic;                      -- Capture 0 resistor config
        cap0_in      : in  std_logic;                      -- Capture 0 input signal
        cap0_dir     : out std_logic;                      -- Capture 0 direction (always input)
        cap0_ren     : out std_logic;                      -- Capture 0 resistor enable

        -- ==========================================
        -- Capture Input 1 Pin Interface
        -- ==========================================
        cap1_ren_in  : in  std_logic;                      -- Capture 1 resistor config
        cap1_in      : in  std_logic;                      -- Capture 1 input signal
        cap1_dir     : out std_logic;                      -- Capture 1 direction (always input)
        cap1_ren     : out std_logic                       -- Capture 1 resistor enable
    );
end TIMER;

architecture rtl of TIMER is

    -- ==========================================
    -- Timer Registers
    -- ==========================================
    signal control_reg         : std_logic_vector(19 downto 0);  -- Timer control register
    signal status_reg          : std_logic_vector(7 downto 0);   -- Timer status register
    signal status_reg_latched  : std_logic_vector(7 downto 0);   -- Latched status for read
    signal timer_value         : std_logic_vector(31 downto 0);  -- Current timer count value
    signal timer_value_latched : std_logic_vector(31 downto 0);  -- Latched timer value for read
    signal compare0_reg        : std_logic_vector(31 downto 0);  -- Compare 0 threshold
    signal compare1_reg        : std_logic_vector(31 downto 0);  -- Compare 1 threshold
    signal compare2_reg        : std_logic_vector(31 downto 0);  -- Compare 2 threshold (reset)
    signal capture0_reg        : std_logic_vector(31 downto 0);  -- Capture 0 value
    signal capture1_reg        : std_logic_vector(31 downto 0);  -- Capture 1 value
    signal capture0_latched    : std_logic_vector(31 downto 0);  -- Latched capture 0 for read
    signal capture1_latched    : std_logic_vector(31 downto 0);  -- Latched capture 1 for read

    -- ==========================================
    -- Control Register Bit Fields
    -- ==========================================
    signal clock_divider       : std_logic_vector(3 downto 0);   -- Clock divider selection
    signal compare1_init_level : std_logic;                      -- Compare 1 initial output level
    signal compare0_init_level : std_logic;                      -- Compare 0 initial output level
    signal capture1_fall_edge  : std_logic;                      -- Capture 1 on falling edge enable
    signal capture0_fall_edge  : std_logic;                      -- Capture 0 on falling edge enable
    signal capture1_enable     : std_logic;                      -- Capture 1 enable
    signal capture0_enable     : std_logic;                      -- Capture 0 enable
    signal clock_source_select : std_logic_vector(1 downto 0);   -- Clock source selection
    signal compare2_reset_en   : std_logic;                      -- Reset timer on compare 2 match
    signal timer_enable        : std_logic;                      -- Timer enable
    signal capture1_int_enable : std_logic;                      -- Capture 1 interrupt enable
    signal capture0_int_enable : std_logic;                      -- Capture 0 interrupt enable
    signal overflow_int_enable : std_logic;                      -- Overflow interrupt enable
    signal compare2_int_enable : std_logic;                      -- Compare 2 interrupt enable
    signal compare1_int_enable : std_logic;                      -- Compare 1 interrupt enable
    signal compare0_int_enable : std_logic;                      -- Compare 0 interrupt enable

    -- ==========================================
    -- Status Register Bit Fields
    -- ==========================================
    signal compare1_output     : std_logic;                      -- Compare 1 current output level
    signal compare0_output     : std_logic;                      -- Compare 0 current output level
    signal capture1_int_flag   : std_logic;                      -- Capture 1 interrupt flag
    signal capture0_int_flag   : std_logic;                      -- Capture 0 interrupt flag
    signal overflow_int_flag   : std_logic;                      -- Overflow interrupt flag
    signal compare2_int_flag   : std_logic;                      -- Compare 2 interrupt flag
    signal compare1_int_flag   : std_logic;                      -- Compare 1 interrupt flag
    signal compare0_int_flag   : std_logic;                      -- Compare 0 interrupt flag

    -- ==========================================
    -- Timer Core Signals
    -- ==========================================
    signal clock_mux_output    : std_logic;                      -- Selected clock from mux
    signal clock_source        : std_logic;                      -- Gated clock source
    signal divider_counter     : std_logic_vector(14 downto 0);  -- Clock divider counter
    signal timer_clock         : std_logic;                      -- Final timer clock after division
    signal divider_input       : std_logic;                      -- Clock divider input
    signal divider_enable      : std_logic;                      -- Clock divider enable

    -- ==========================================
    -- Timer Control Signals
    -- ==========================================
    signal latch_timer_value   : std_logic;                      -- Latch new timer value
    signal timer_overflowing   : std_logic;                      -- Timer overflow detection
    signal clear_timer_value   : std_logic;                      -- Clear timer to zero
    signal clear_capture0_flag : std_logic;                      -- Clear capture 0 interrupt flag
    signal clear_capture1_flag : std_logic;                      -- Clear capture 1 interrupt flag
    signal clear_overflow_flag : std_logic;                      -- Clear overflow interrupt flag
    signal clear_compare0_flag : std_logic;                      -- Clear compare 0 interrupt flag
    signal clear_compare1_flag : std_logic;                      -- Clear compare 1 interrupt flag
    signal clear_compare2_flag : std_logic;                      -- Clear compare 2 interrupt flag

    -- ==========================================
    -- Capture Clock Signals
    -- ==========================================
    signal capture0_clock      : std_logic;                      -- Edge-detected clock for capture 0
    signal capture1_clock      : std_logic;                      -- Edge-detected clock for capture 1

    -- ==========================================
    -- Memory Interface Signals
    -- ==========================================
    signal reg_address         : natural range 0 to 63;          -- Decoded register address
    signal timer_value_write   : std_logic_vector(31 downto 0);  -- Timer value from write bus

begin

    -- ==========================================
    -- Control Register Field Extraction
    -- ==========================================
    clock_divider       <= control_reg(19 downto 16);
    compare1_init_level <= control_reg(15);
    compare0_init_level <= control_reg(14);
    capture1_fall_edge  <= control_reg(13);
    capture0_fall_edge  <= control_reg(12);
    capture1_enable     <= control_reg(11);
    capture0_enable     <= control_reg(10);
    clock_source_select <= control_reg(9 downto 8);
    compare2_reset_en   <= control_reg(7);
    timer_enable        <= control_reg(6);
    capture1_int_enable <= control_reg(5);
    capture0_int_enable <= control_reg(4);
    overflow_int_enable <= control_reg(3);
    compare2_int_enable <= control_reg(2);
    compare1_int_enable <= control_reg(1);
    compare0_int_enable <= control_reg(0);

    -- ==========================================
    -- Status Register Assembly
    -- ==========================================
    status_reg <= (
        7 => compare1_output,
        6 => compare0_output,
        5 => capture1_int_flag,
        4 => capture0_int_flag,
        3 => overflow_int_flag,
        2 => compare2_int_flag,
        1 => compare1_int_flag,
        0 => compare0_int_flag
    );

    -- ==========================================
    -- Pin Direction Configuration
    -- ==========================================
    -- Capture pins are always inputs
    cap0_dir <= '0';
    cap0_ren <= cap0_ren_in;
    cap1_dir <= '0';
    cap1_ren <= cap1_ren_in;

    -- Compare pins are always outputs
    cmp0_dir <= '1';
    cmp0_ren <= cmp0_ren_in;
    cmp1_dir <= '1';
    cmp1_ren <= cmp1_ren_in;

    -- ==========================================
    -- Clock Source Selection and Division
    -- ==========================================
    -- Glitch-free clock multiplexer
    clk_mux: entity work.ClockMuxGlitchFree
    generic map (
        CLK_COUNT   => 4,
        SEL_WIDTH   => 2,
        CLK_DEFAULT => 0
    )
    port map (
        resetn      => resetn,
        Sel         => clock_source_select, -- Look into delaying this a half cycle to avoid glitches? As if we are selecting mclk, this may be on same edge 
        ClkIn(0)    => smclk,
        ClkIn(1)    => mclk,
        ClkIn(2)    => clk_lfxt,
        ClkIn(3)    => clk_hfxt,
        ClkEn       => open,
        ClkOut      => clock_mux_output
    );

    -- Gate clock when timer disabled
    clock_gate_timer: entity work.ClkGate
    port map (
        ClkIn  => clock_mux_output,
        En     => timer_enable,
        ClkOut => clock_source
    );

    -- Enable divider only when needed
    divider_enable <= '1' when timer_enable = '1' and (clock_divider /= "0000") else '0';
    
    clock_gate_divider: entity work.ClkGate
    port map (
        ClkIn  => clock_mux_output,
        En     => divider_enable,
        ClkOut => divider_input
    );

    -- ==========================================
    -- Clock Divider Counter
    -- ==========================================
    divider_process: process(resetn, divider_input, timer_enable, clock_divider)
    begin
        if (resetn = '0') or (timer_enable = '0') or (clock_divider = "0000") then
            divider_counter <= (others => '0');
        elsif rising_edge(divider_input) then
            divider_counter <= divider_counter + 1;
        end if;
    end process;

    -- Select divided clock output
    with clock_divider select timer_clock <=
        clock_source         when "0000",  -- Divide by 1 (no division)
        divider_counter(0)   when "0001",  -- Divide by 2
        divider_counter(1)   when "0010",  -- Divide by 4
        divider_counter(2)   when "0011",  -- Divide by 8
        divider_counter(3)   when "0100",  -- Divide by 16
        divider_counter(4)   when "0101",  -- Divide by 32
        divider_counter(5)   when "0110",  -- Divide by 64
        divider_counter(6)   when "0111",  -- Divide by 128
        divider_counter(7)   when "1000",  -- Divide by 256
        divider_counter(8)   when "1001",  -- Divide by 512
        divider_counter(9)   when "1010",  -- Divide by 1024
        divider_counter(10)  when "1011",  -- Divide by 2048
        divider_counter(11)  when "1100",  -- Divide by 4096
        divider_counter(12)  when "1101",  -- Divide by 8192
        divider_counter(13)  when "1110",  -- Divide by 16384
        divider_counter(14)  when others;  -- Divide by 32768

    -- ==========================================
    -- Timer Counter
    -- ==========================================
    timer_counter: process(resetn, timer_clock, latch_timer_value, timer_value_write)
    begin
        if resetn = '0' then
            timer_value <= (others => '0');
        elsif latch_timer_value = '1' then
            -- Load new value from register write 
            -- timer_value_write is latched here - from memory write process
            timer_value <= timer_value_write;
        elsif rising_edge(timer_clock) then
            if clear_timer_value = '1' then
                timer_value <= (others => '0');
            else
                timer_value <= timer_value + 1;
            end if;
        end if;
    end process;

    -- ==========================================
    -- Input Capture 0 Logic
    -- ==========================================
    -- Generate edge-sensitive capture clock
    capture0_clock <= '0' when capture0_enable = '0' else 
                     cap0_in xor capture0_fall_edge;

    capture0_process: process(resetn, clear_capture0_flag, capture0_clock)
    begin
        if resetn = '0' then
            capture0_reg <= (others => '0');
            capture0_int_flag <= '0';
        elsif clear_capture0_flag = '1' then
            capture0_int_flag <= '0';
        elsif rising_edge(capture0_clock) then
            capture0_reg <= timer_value;  -- Capture current timer value
            capture0_int_flag <= '1';     -- Set interrupt flag
        end if;
    end process;

    -- ==========================================
    -- Input Capture 1 Logic
    -- ==========================================
    -- Generate edge-sensitive capture clock
    capture1_clock <= '0' when capture1_enable = '0' else 
                     cap1_in xor capture1_fall_edge;

    capture1_process: process(resetn, clear_capture1_flag, capture1_clock)
    begin
        if resetn = '0' then
            capture1_reg <= (others => '0');
            capture1_int_flag <= '0';
        elsif clear_capture1_flag = '1' then
            capture1_int_flag <= '0';
        elsif rising_edge(capture1_clock) then
            capture1_reg <= timer_value;  -- Capture current timer value
            capture1_int_flag <= '1';     -- Set interrupt flag
        end if;
    end process;

    -- ==========================================
    -- Timer Overflow Detection
    -- ==========================================
    timer_overflowing <= '1' when timer_value = X"FFFFFFFF" else '0';

    overflow_process: process(resetn, timer_clock, clear_overflow_flag)
    begin
        if resetn = '0' or clear_overflow_flag = '1' then
            overflow_int_flag <= '0';
        elsif rising_edge(timer_clock) then
            if timer_overflowing = '1' then
                overflow_int_flag <= '1';
            end if;
        end if;
    end process;

    -- ==========================================
    -- Compare Match and PWM Generation
    -- ==========================================
    compare_process: process(resetn, timer_clock, clear_compare0_flag, clear_compare1_flag, 
                           timer_value, timer_enable, compare0_init_level)
    begin
        if resetn = '0' or timer_enable = '0' then
            -- Initialize outputs to configured levels
            compare0_output <= compare0_init_level;
            compare1_output <= compare1_init_level;
        elsif rising_edge(timer_clock) then
            -- Compare 0 match detection
            if timer_value = compare0_reg then
                compare0_int_flag <= '1';
                compare0_output <= not compare0_init_level;  -- Toggle output
            end if;
            
            -- Compare 1 match detection
            if timer_value = compare1_reg then
                compare1_int_flag <= '1';
                compare1_output <= not compare1_init_level;  -- Toggle output
            end if;

            -- Reset outputs on timer reset or overflow
            if clear_timer_value = '1' or timer_overflowing = '1' then
                compare0_output <= compare0_init_level;
                compare1_output <= compare1_init_level;
            end if;
        end if;

        -- Clear interrupt flags
        if resetn = '0' or clear_compare0_flag = '1' then
            compare0_int_flag <= '0';
        end if;
        if resetn = '0' or clear_compare1_flag = '1' then
            compare1_int_flag <= '0';
        end if;
    end process;

    -- ==========================================
    -- Compare 2 Timer Reset Logic
    -- ==========================================
    -- Reset timer when it matches compare2 register (if enabled)
    clear_timer_value <= '1' when (compare2_reset_en = '1' and timer_value = compare2_reg) else '0';

    compare2_process: process(resetn, timer_clock, clear_compare2_flag, timer_enable, timer_value)
    begin
        if resetn = '0' or clear_compare2_flag = '1' or timer_enable = '0' then
            compare2_int_flag <= '0';
        elsif rising_edge(timer_clock) then
            if clear_timer_value = '1' then
                compare2_int_flag <= '1';
            end if;
        end if;
    end process;

    -- ==========================================
    -- Compare Output Assignments
    -- ==========================================
    cmp0_out <= compare0_output;
    cmp1_out <= compare1_output;

    -- ==========================================
    -- Interrupt Request Generation
    -- ==========================================
    irq_cap0 <= capture0_int_flag and capture0_int_enable;
    irq_cap1 <= capture1_int_flag and capture1_int_enable;
    irq_ovf  <= overflow_int_flag and overflow_int_enable;
    irq_cmp0 <= compare0_int_flag and compare0_int_enable;
    irq_cmp1 <= compare1_int_flag and compare1_int_enable;
    irq_cmp2 <= compare2_int_flag and compare2_int_enable;

    -- ==========================================
    -- Register Synchronization for Memory Read
    -- ==========================================
    reg_sync: process(en_mem)
    begin
        if falling_edge(en_mem) then
            status_reg_latched  <= not status_reg;
            timer_value_latched <= not timer_value;
            capture0_latched    <= not capture0_reg;
            capture1_latched    <= not capture1_reg;
        end if;
    end process;

    -- ==========================================
    -- Memory-Mapped Register Interface
    -- ==========================================
    -- Address decoding
    reg_address <= slv2uint(addr_periph) when en_mem = '0' else 0;

    -- Register write process
    reg_write_proc: process(resetn, clk_mem, en_mem)
    begin
        if resetn = '0' then
            control_reg <= (others => '0');
            compare0_reg <= (others => '0');
            compare1_reg <= (others => '0');
            compare2_reg <= (others => '0');
        elsif rising_edge(clk_mem) then
            if en_mem = '0' then
                case reg_address is
                    -- Control register write
                    when RegSlotTIMxCR =>
                        if wen(0) = '0' then
                            control_reg(7 downto 0) <= write_data(7 downto 0);
                        end if;
                        if wen(1) = '0' then
                            control_reg(15 downto 8) <= write_data(15 downto 8);
                        end if;
                        if wen(2) = '0' then
                            control_reg(19 downto 16) <= write_data(19 downto 16);
                        end if;
                    
                    -- Status register write (clear flags)
                    when RegSlotTIMxSR =>
                        if wen(0) = '0' then
                            if write_data(0) = '1' then clear_compare0_flag <= '1'; end if;
                            if write_data(1) = '1' then clear_compare1_flag <= '1'; end if;
                            if write_data(2) = '1' then clear_compare2_flag <= '1'; end if;
                            if write_data(3) = '1' then clear_overflow_flag <= '1'; end if;
                            if write_data(4) = '1' then clear_capture0_flag <= '1'; end if;
                            if write_data(5) = '1' then clear_capture1_flag <= '1'; end if;
                        end if;
                    
                    -- Timer value write
                    when RegSlotTIMxVAL =>
                        if wen /= "1111" then
                            timer_value_write <= write_data;
                            latch_timer_value <= '1';
                        end if;
                    
                    -- Compare 0 register write
                    when RegSlotTIMxCMP0 =>
                        if wen(0) = '0' then compare0_reg(7 downto 0)   <= write_data(7 downto 0);   end if;
                        if wen(1) = '0' then compare0_reg(15 downto 8)  <= write_data(15 downto 8);  end if;
                        if wen(2) = '0' then compare0_reg(23 downto 16) <= write_data(23 downto 16); end if;
                        if wen(3) = '0' then compare0_reg(31 downto 24) <= write_data(31 downto 24); end if;
                    
                    -- Compare 1 register write
                    when RegSlotTIMxCMP1 =>
                        if wen(0) = '0' then compare1_reg(7 downto 0)   <= write_data(7 downto 0);   end if;
                        if wen(1) = '0' then compare1_reg(15 downto 8)  <= write_data(15 downto 8);  end if;
                        if wen(2) = '0' then compare1_reg(23 downto 16) <= write_data(23 downto 16); end if;
                        if wen(3) = '0' then compare1_reg(31 downto 24) <= write_data(31 downto 24); end if;
                    
                    -- Compare 2 register write
                    when RegSlotTIMxCMP2 =>
                        if wen(0) = '0' then compare2_reg(7 downto 0)   <= write_data(7 downto 0);   end if;
                        if wen(1) = '0' then compare2_reg(15 downto 8)  <= write_data(15 downto 8);  end if;
                        if wen(2) = '0' then compare2_reg(23 downto 16) <= write_data(23 downto 16); end if;
                        if wen(3) = '0' then compare2_reg(31 downto 24) <= write_data(31 downto 24); end if;
                    
                    when others =>
                        null;
                end case;
            end if;
        end if;
        
        -- Clear control signals when not active
        if resetn = '0' or en_mem = '1' then
            clear_compare0_flag <= '0';
            clear_compare1_flag <= '0';
            clear_compare2_flag <= '0';
            clear_overflow_flag <= '0';
            clear_capture0_flag <= '0';
            clear_capture1_flag <= '0';
            latch_timer_value <= '0';
        end if;
    end process;

    -- ==========================================
    -- Register Read Process
    -- ==========================================
    reg_read_proc: process(clk_mem)
    begin
        if rising_edge(clk_mem) then
            case reg_address is
                when RegSlotTIMxCR =>
                    read_data <= (31 downto 20 => '0') & control_reg;
                
                when RegSlotTIMxSR =>
                    read_data <= (31 downto 8 => '0') & (not status_reg_latched);
                
                when RegSlotTIMxVAL =>
                    read_data <= timer_value;
                
                when RegSlotTIMxCAP0 =>
                    read_data <= not capture0_latched;
                
                when RegSlotTIMxCAP1 =>
                    read_data <= not capture1_latched;
                
                when RegSlotTIMxCMP0 =>
                    read_data <= compare0_reg;
                
                when RegSlotTIMxCMP1 =>
                    read_data <= compare1_reg;
                
                when RegSlotTIMxCMP2 =>
                    read_data <= compare2_reg;
                
                when others =>
                    read_data <= (others => '0');  -- Return zeros for unmapped addresses
            end case;
        end if;
    end process;

end rtl;


