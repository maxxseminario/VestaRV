-- VestaRV: timer
-- 16-bit timer with a selectable source (mclk, smclk, LFXT, HFXT), three compare channels with pin outputs, two capture inputs and one IRQ per event.

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.Constants.all;
-- Word offsets, field ranges, resets and implemented-bit masks: generated from hdl/common/regs/rdl/timer.rdl, which replaces the work.MemoryMap clause (both would make every slot name an ambiguous homograph).
use work.timer_regs_pkg.all;

entity TIMER is
    port (
        -- Clock inputs.
        mclk         : in  std_logic;                      -- Main clock
        smclk        : in  std_logic;                      -- Sub-main clock
        clk_lfxt     : in  std_logic;                      -- Low-frequency crystal clock
        clk_hfxt     : in  std_logic;                      -- High-frequency crystal clock
        resetn       : in  std_logic;                      -- System reset (active-low)

        -- Interrupt outputs.
        irq_cap0     : out std_logic;                      -- Capture 0 interrupt request
        irq_cap1     : out std_logic;                      -- Capture 1 interrupt request
        irq_ovf      : out std_logic;                      -- Overflow interrupt request
        irq_cmp0     : out std_logic;                      -- Compare 0 interrupt request
        irq_cmp1     : out std_logic;                      -- Compare 1 interrupt request
        irq_cmp2     : out std_logic;                      -- Compare 2 interrupt request

        -- Memory-mapped register interface.
        clk_mem      : in  std_logic;                      -- Memory interface clock
        en_mem       : in  std_logic;                      -- Memory enable (active-low)
        wen          : in  std_logic_vector(3 downto 0);   -- Write enable (active-low)
        addr_periph  : in  std_logic_vector(7 downto 2);   -- Peripheral register address
        write_data   : in  std_logic_vector(31 downto 0);  -- Write data bus
        read_data    : out std_logic_vector(31 downto 0);  -- Read data bus

        -- Compare output 0 pin interface.
        cmp0_ren_in  : in  std_logic;                      -- Compare 0 resistor config
        cmp0_out     : out std_logic;                      -- Compare 0 output value
        cmp0_dir     : out std_logic;                      -- Compare 0 direction (always output)
        cmp0_ren     : out std_logic;                      -- Compare 0 resistor enable

        -- Compare output 1 pin interface.
        cmp1_ren_in  : in  std_logic;                      -- Compare 1 resistor config
        cmp1_out     : out std_logic;                      -- Compare 1 output value
        cmp1_dir     : out std_logic;                      -- Compare 1 direction (always output)
        cmp1_ren     : out std_logic;                      -- Compare 1 resistor enable

        -- Capture input 0 pin interface.
        cap0_ren_in  : in  std_logic;                      -- Capture 0 resistor config
        cap0_in      : in  std_logic;                      -- Capture 0 input signal
        cap0_dir     : out std_logic;                      -- Capture 0 direction (always input)
        cap0_ren     : out std_logic;                      -- Capture 0 resistor enable

        -- Capture input 1 pin interface.
        cap1_ren_in  : in  std_logic;                      -- Capture 1 resistor config
        cap1_in      : in  std_logic;                      -- Capture 1 input signal
        cap1_dir     : out std_logic;                      -- Capture 1 direction (always input)
        cap1_ren     : out std_logic;                      -- Capture 1 resistor enable

        -- Event-fabric producer toggles: one flip per event in the timer_clock domain, taken from the flags' set conditions and not from the masked IRQs.
        -- They live in their own process so the flags' async clears can never touch them; the fabric front-end does the 2-FF and XOR edge into mclk.
        evt_compare0 : out std_logic;                      -- flips at timer_value = compare0
        evt_overflow : out std_logic;                      -- flips at overflow
        -- Event-fabric consumer tasks: one-mclk pulses in the clk_mem domain, ORed idempotently into CR bit 6.
        -- Stop is evaluated after start, so a same-cycle start and stop resolves to stop, the safe direction.
        task_start   : in  std_logic := '0';               -- set CR(6)
        task_stop    : in  std_logic := '0'                -- clear CR(6)
    );
end TIMER;

architecture rtl of TIMER is

    -- Reflected-binary conversions for the TIMxVAL read CDC.
    function bin2gray(b : std_logic_vector) return std_logic_vector is
        variable g : std_logic_vector(b'range);
    begin
        g(b'high) := b(b'high);
        for i in b'high - 1 downto b'low loop
            g(i) := b(i + 1) xor b(i);
        end loop;
        return g;
    end function;

    function gray2bin(g : std_logic_vector) return std_logic_vector is
        variable b : std_logic_vector(g'range);
    begin
        b(g'high) := g(g'high);
        for i in g'high - 1 downto g'low loop
            b(i) := b(i + 1) xor g(i);
        end loop;
        return b;
    end function;

    -- The bus side is one periph_regs instance driven by timer_regs_pkg's tables;
    -- see hdl/common/regs/REGFILE.md. What is left here is the datapath.
    signal regs_q              : reg_arr_t;                      -- the stored words: CR, VAL staging, CMP0/1/2
    signal hw_rd_s             : reg_arr_t;                      -- read source for the words this block owns
    signal hw_set_s            : reg_arr_t;                      -- task_start on TIMxCR.TEN
    signal hw_clr_s            : reg_arr_t;                      -- task_stop  on TIMxCR.TEN
    signal wr_str              : std_logic_vector(0 to NWORDS-1);
    signal w1c_s               : reg_arr_t;                      -- a 1 written to a TIMxSR flag
    signal sr_rd, cap0_rd      : std_logic_vector(31 downto 0);  -- assembled read words
    signal cap1_rd             : std_logic_vector(31 downto 0);

    -- Timer registers.
    signal status_reg          : std_logic_vector(7 downto 0);   -- Timer status register
    signal status_reg_latched  : std_logic_vector(7 downto 0);   -- Latched status for read
    signal timer_value         : std_logic_vector(31 downto 0);  -- Current timer count value
    signal timer_value_next    : std_logic_vector(31 downto 0);  -- Counter increment, shared by the counter and its gray mirror
    -- TIMxVAL read CDC: timer_value lives in the timer_clock domain, which is asynchronous to clk_mem
    -- for every source but the one SYSTEM also uses for mclk. A gray mirror changes exactly one flop
    -- per increment, so the 2-FF capture below can only return the pre- or post-increment count, never
    -- a torn one. The two multi-bit jumps, a TIMxVAL write and the compare2 auto-clear, are not covered
    -- and need not be: both are software-visible events.
    signal timer_gray          : std_logic_vector(31 downto 0);  -- Gray mirror of timer_value, timer_clock domain
    signal timer_gray_s2       : std_logic_vector(31 downto 0);  -- work.sync output, settled
    signal timer_value_mem     : std_logic_vector(31 downto 0);  -- Coherent count in the clk_mem domain
    signal compare0_reg        : std_logic_vector(31 downto 0);  -- Compare 0 threshold (TIMxCMP0 storage)
    signal compare1_reg        : std_logic_vector(31 downto 0);  -- Compare 1 threshold (TIMxCMP1 storage)
    signal compare2_reg        : std_logic_vector(31 downto 0);  -- Compare 2 threshold (TIMxCMP2 storage)
    signal capture0_reg        : std_logic_vector(31 downto 0);  -- Capture 0 value
    signal capture1_reg        : std_logic_vector(31 downto 0);  -- Capture 1 value
    signal capture0_latched    : std_logic_vector(31 downto 0);  -- Latched capture 0 for read
    signal capture1_latched    : std_logic_vector(31 downto 0);  -- Latched capture 1 for read

    -- Control register bit fields.
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

    -- Status register bit fields.
    signal compare1_output     : std_logic;                      -- Compare 1 current output level
    signal compare0_output     : std_logic;                      -- Compare 0 current output level
    signal capture1_int_flag   : std_logic;                      -- Capture 1 interrupt flag
    signal capture0_int_flag   : std_logic;                      -- Capture 0 interrupt flag
    signal overflow_int_flag   : std_logic;                      -- Overflow interrupt flag
    signal compare2_int_flag   : std_logic;                      -- Compare 2 interrupt flag
    signal compare1_int_flag   : std_logic;                      -- Compare 1 interrupt flag
    signal compare0_int_flag   : std_logic;                      -- Compare 0 interrupt flag

    -- Timer core signals.
    signal clock_mux_output    : std_logic;                      -- Selected clock from mux
    signal clock_source        : std_logic;                      -- Gated clock source
    signal divider_counter     : std_logic_vector(14 downto 0);  -- Clock divider counter
    signal timer_clock         : std_logic;                      -- Final timer clock after division
    signal divider_input       : std_logic;                      -- Clock divider input
    signal divider_enable      : std_logic;                      -- Clock divider enable

    -- Timer control signals.
    signal latch_timer_value   : std_logic;                      -- Latch new timer value
    signal timer_overflowing   : std_logic;                      -- Timer overflow detection
    signal evt_cmp0_tgl        : std_logic;                      -- event toggle: compare0 match
    signal evt_ovf_tgl         : std_logic;                      -- event toggle: overflow
    signal clear_timer_value   : std_logic;                      -- Clear timer to zero
    signal clear_capture0_flag : std_logic;                      -- Clear capture 0 interrupt flag
    signal clear_capture1_flag : std_logic;                      -- Clear capture 1 interrupt flag
    signal clear_overflow_flag : std_logic;                      -- Clear overflow interrupt flag
    signal clear_compare0_flag : std_logic;                      -- Clear compare 0 interrupt flag
    signal clear_compare1_flag : std_logic;                      -- Clear compare 1 interrupt flag
    signal clear_compare2_flag : std_logic;                      -- Clear compare 2 interrupt flag

    -- Capture clock signals.
    signal capture0_clock      : std_logic;                      -- Edge-detected clock for capture 0
    signal capture1_clock      : std_logic;                      -- Edge-detected clock for capture 1

    -- Memory interface signals.
    signal timer_value_write   : std_logic_vector(31 downto 0);  -- Timer value from write bus

begin

    -- Control register field extraction, off the stored TIMxCR word. The ranges
    -- are timer_regs_pkg's, so no bit literal in this file describes a register.
    clock_divider       <= regs_q(RegSlotTIMxCR)(DIV_MSB downto DIV_LSB);
    compare1_init_level <= regs_q(RegSlotTIMxCR)(CMP1IH_LSB);
    compare0_init_level <= regs_q(RegSlotTIMxCR)(CMP0IH_LSB);
    capture1_fall_edge  <= regs_q(RegSlotTIMxCR)(CAP1FE_LSB);
    capture0_fall_edge  <= regs_q(RegSlotTIMxCR)(CAP0FE_LSB);
    capture1_enable     <= regs_q(RegSlotTIMxCR)(CAP1EN_LSB);
    capture0_enable     <= regs_q(RegSlotTIMxCR)(CAP0EN_LSB);
    clock_source_select <= regs_q(RegSlotTIMxCR)(SSEL_MSB downto SSEL_LSB);
    compare2_reset_en   <= regs_q(RegSlotTIMxCR)(CMP2RST_LSB);
    timer_enable        <= regs_q(RegSlotTIMxCR)(TEN_LSB);
    capture1_int_enable <= regs_q(RegSlotTIMxCR)(CAP1IE_LSB);
    capture0_int_enable <= regs_q(RegSlotTIMxCR)(CAP0IE_LSB);
    overflow_int_enable <= regs_q(RegSlotTIMxCR)(OVIE_LSB);
    compare2_int_enable <= regs_q(RegSlotTIMxCR)(CMP2IE_LSB);
    compare1_int_enable <= regs_q(RegSlotTIMxCR)(CMP1IE_LSB);
    compare0_int_enable <= regs_q(RegSlotTIMxCR)(CMP0IE_LSB);

    -- The compare thresholds and the TIMxVAL write staging word are plain
    -- software storage, so periph_regs holds them.
    compare0_reg      <= regs_q(RegSlotTIMxCMP0);
    compare1_reg      <= regs_q(RegSlotTIMxCMP1);
    compare2_reg      <= regs_q(RegSlotTIMxCMP2);
    timer_value_write <= regs_q(RegSlotTIMxVAL);

    -- Status register assembly.
    status_reg <= (
        CMP1OUT_LSB => compare1_output,
        CMP0OUT_LSB => compare0_output,
        CAP1IF_LSB  => capture1_int_flag,
        CAP0IF_LSB  => capture0_int_flag,
        OVIF_LSB    => overflow_int_flag,
        CMP2IF_LSB  => compare2_int_flag,
        CMP1IF_LSB  => compare1_int_flag,
        CMP0IF_LSB  => compare0_int_flag
    );

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

    -- Glitch-free clock source multiplexer.
    clk_mux: entity work.ClockMuxGlitchFree
    generic map (
        CLK_COUNT   => 4,
        SEL_WIDTH   => 2,
        CLK_DEFAULT => 0
    )
    port map (
        resetn      => resetn,
        Sel         => clock_source_select, -- consider delaying this a half cycle: with mclk selected, a select change can land on the same edge
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

    -- Prescaler count, held cleared while the timer is off or the divider is bypassed.
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

    -- Counter with an async load: reset wins, then a register write, then the counted edge.
    timer_counter: process(resetn, timer_clock, latch_timer_value, timer_value_write)
    begin
        if resetn = '0' then
            timer_value <= (others => '0');
        elsif latch_timer_value = '1' then
            -- Load the value staged by the memory write process.
            timer_value <= timer_value_write;
        elsif rising_edge(timer_clock) then
            if clear_timer_value = '1' then
                timer_value <= (others => '0');
            else
                timer_value <= timer_value_next;
            end if;
        end if;
    end process;

    timer_value_next <= timer_value + 1;

    -- Gray mirror of the counter: structurally identical to timer_counter, so timer_gray = bin2gray(timer_value) on every path.
    timer_gray_mirror: process(resetn, timer_clock, latch_timer_value, timer_value_write)
    begin
        if resetn = '0' then
            timer_gray <= (others => '0');
        elsif latch_timer_value = '1' then
            timer_gray <= bin2gray(timer_value_write);
        elsif rising_edge(timer_clock) then
            if clear_timer_value = '1' then
                timer_gray <= (others => '0');
            else
                timer_gray <= bin2gray(timer_value_next);
            end if;
        end if;
    end process;

    -- 2-FF capture into clk_mem, then one decode register so the read mux still sees a flop.
    -- WIDTH=32 is legitimate here ONLY because timer_gray is GRAY CODED: the mirror at
    -- timer_gray_mirror above changes exactly one bit per timer_clock edge, so a bit
    -- caught mid-transition yields the value before or after, never a third word. A
    -- binary bus through the same instance would be the bug work.sync's header forbids.
    u_sync_timer_gray : entity work.sync
        generic map (WIDTH => 32, DEPTH => 2)
        port map (clk => clk_mem, areset => resetn, d => timer_gray, q => timer_gray_s2);

    timer_value_cdc: process(resetn, clk_mem)
    begin
        if resetn = '0' then
            timer_value_mem <= (others => '0');
        elsif rising_edge(clk_mem) then
            timer_value_mem <= gray2bin(timer_gray_s2);
        end if;
    end process;

    -- Edge-sensitive capture clock for capture 0.
    capture0_clock <= '0' when capture0_enable = '0' else 
                     cap0_in xor capture0_fall_edge;

    -- Snapshot the counter on the selected edge and raise the capture 0 flag.
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

    -- Edge-sensitive capture clock for capture 1.
    capture1_clock <= '0' when capture1_enable = '0' else 
                     cap1_in xor capture1_fall_edge;

    -- Snapshot the counter on the selected edge and raise the capture 1 flag.
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

    -- Timer overflow detection.
    timer_overflowing <= '1' when timer_value = X"FFFFFFFF" else '0';

    -- Sticky overflow flag, cleared by reset or by a status-register write.
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

    -- Event toggles in the timer_clock domain, async on resetn only: the flags' clear_* terms must never appear here.
    -- One flip per event, since value=compare0 and overflow each hold for exactly one timer_clock period, and a gated-off clock gives no phantom flips.
    evfab_tgl_process: process(resetn, timer_clock)
    begin
        if resetn = '0' then
            evt_cmp0_tgl <= '0';
            evt_ovf_tgl  <= '0';
        elsif rising_edge(timer_clock) then
            if timer_value = compare0_reg then
                evt_cmp0_tgl <= not evt_cmp0_tgl;
            end if;
            if timer_overflowing = '1' then
                evt_ovf_tgl <= not evt_ovf_tgl;
            end if;
        end if;
    end process;
    evt_compare0 <= evt_cmp0_tgl;
    evt_overflow <= evt_ovf_tgl;

    -- Compare 0/1 match flags plus their toggling outputs; the outputs return to their configured init level on reset, on a timer clear and on overflow.
    compare_process: process(resetn, timer_clock, clear_compare0_flag, clear_compare1_flag, 
                           timer_value, timer_enable, compare0_init_level, compare1_init_level)  -- compare1_init_level is read in the async-init branch; without it RTL sim can hold a stale compare1 init level
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

    -- Reset the timer when it matches the compare 2 register, if enabled.
    clear_timer_value <= '1' when (compare2_reset_en = '1' and timer_value = compare2_reg) else '0';

    -- Compare 2 flag: set on the auto-reset match, cleared by reset, a status write, or a disabled timer.
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

    -- Compare output assignments.
    cmp0_out <= compare0_output;
    cmp1_out <= compare1_output;

    -- Interrupt requests: flag qualified by its enable.
    irq_cap0 <= capture0_int_flag and capture0_int_enable;
    irq_cap1 <= capture1_int_flag and capture1_int_enable;
    irq_ovf  <= overflow_int_flag and overflow_int_enable;
    irq_cmp0 <= compare0_int_flag and compare0_int_enable;
    irq_cmp1 <= compare1_int_flag and compare1_int_enable;
    irq_cmp2 <= compare2_int_flag and compare2_int_enable;

    -- Falling en_mem snapshots the free-running status and capture values for the read mux; they are stored inverted and re-inverted on read.
    -- This stays in the peripheral: which of its signals are asynchronous to clk_mem is a CDC judgement periph_regs cannot make. It feeds hw_rd below.
    -- timer_value is NOT snapshotted here: TIMxVAL reads the gray-coded clk_mem copy built above, and the timer_value_latched flops this process used to write were read by nothing.
    reg_sync: process(en_mem)
    begin
        if falling_edge(en_mem) then
            status_reg_latched  <= not status_reg;
            capture0_latched    <= not capture0_reg;
            capture1_latched    <= not capture1_reg;
        end if;
    end process;

    -- The words this block owns rather than stores: the status snapshot, the
    -- clk_mem-domain count and the two capture snapshots, re-inverted here.
    sr_rd   <= (31 downto status_reg_latched'high + 1 => '0') & (not status_reg_latched);
    cap0_rd <= not capture0_latched;
    cap1_rd <= not capture1_latched;

    hw_rd_s <= (RegSlotTIMxSR   => sr_rd,
                RegSlotTIMxVAL  => timer_value_mem,   -- see the TIMxVAL read CDC above
                RegSlotTIMxCAP0 => cap0_rd,
                RegSlotTIMxCAP1 => cap1_rd,
                others          => (others => '0'));

    -- The event-fabric consumer tasks, as hardware access to TIMxCR.TEN. They act
    -- outside the en_mem gate, they beat a coincident CPU write, and a coincident
    -- start and stop resolves to stop, because periph_regs applies hw_clr last.
    hw_set_s <= (RegSlotTIMxCR => (TEN_LSB => task_start, others => '0'),
                 others        => (others => '0'));
    hw_clr_s <= (RegSlotTIMxCR => (TEN_LSB => task_stop,  others => '0'),
                 others        => (others => '0'));

    -- STROBE_HOLD: every strobe this block consumes reaches an asynchronous clear
    -- or load in the timer_clock domain (the flag processes, the counter's load),
    -- so they must be held levels for the whole access, not one-clk_mem pulses.
    -- RDTHRU / WIDEWR are TIMxVAL's: its storage is the write staging word while
    -- the read is the CDC copy, and any enabled lane writes all 32 bits.
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
            RDTHRU      => "00100000",
            WIDEWR      => "00100000",
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
            hw_set      => hw_set_s,
            hw_clr      => hw_clr_s,
            acc_hit     => open,
            rd_strobe   => open,
            wr_strobe   => wr_str,
            wr_pulse    => open,
            w1c_hit     => w1c_s,
            woset_hit   => open,
            wot_hit     => open,
            rd_clr      => open);

    -- A TIMxVAL write loads the counter asynchronously; the level is held for the
    -- whole access, exactly as the hand-written latch_timer_value strobe was.
    latch_timer_value <= wr_str(RegSlotTIMxVAL);

    -- The TIMxSR flag clears: one per write-1-to-clear bit, in the timer_clock domain.
    clear_compare0_flag <= w1c_s(RegSlotTIMxSR)(CMP0IF_LSB);
    clear_compare1_flag <= w1c_s(RegSlotTIMxSR)(CMP1IF_LSB);
    clear_compare2_flag <= w1c_s(RegSlotTIMxSR)(CMP2IF_LSB);
    clear_overflow_flag <= w1c_s(RegSlotTIMxSR)(OVIF_LSB);
    clear_capture0_flag <= w1c_s(RegSlotTIMxSR)(CAP0IF_LSB);
    clear_capture1_flag <= w1c_s(RegSlotTIMxSR)(CAP1IF_LSB);

end rtl;


