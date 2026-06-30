-------------------------------------------------------------------------------
-- TIMER_tb.vhd
-------------------------------------------------------------------------------
-- Standalone, self-checking testbench for the TIMER peripheral
-- (hdl/MCU/periph/TIMER.vhd).
--
-- Drives the peripheral register bus directly plus the timer's clock inputs and
-- capture pins, and checks: register read/write (incl. byte lanes), timer
-- counting at divide-by-1 and divide-by-2, value load, overflow, compare match
-- with PWM output toggle, compare-2 auto-reset, input capture (rising/falling),
-- and the interrupt flag/enable/clear paths.
--
-- Clocking: the timer's source is smclk (clock_source_select = 00, the glitch-
-- free mux's default slice, which passes smclk straight through). smclk is
-- pulsed in controlled bursts (timer_ticks) so counts are exact; the register
-- bus runs off a separate free-running clk. mclk/lfxt/hfxt are unused here.
--
-- Bus contract (see tb/CLAUDE.md): en_mem active-low, wen active-low per byte
-- lane, clk_mem = clk while en_mem='0', SR/CAP read a snapshot taken on the
-- falling edge of en_mem.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.constants.all;
use work.MemoryMap.all;

entity TIMER_tb is
end entity TIMER_tb;

architecture sim of TIMER_tb is

    constant CLK_PERIOD : time := 50 ns;        -- register-bus clock
    constant TICK       : time := 100 ns;       -- smclk timer-tick period

    -- DUT clocks / reset
    signal mclk        : std_logic := '0';
    signal smclk       : std_logic := '0';
    signal clk_lfxt    : std_logic := '0';
    signal clk_hfxt    : std_logic := '0';
    signal resetn      : std_logic := '0';

    -- bus clock
    signal clk         : std_logic := '0';
    signal clk_mem     : std_logic := '0';

    -- interrupts
    signal irq_cap0, irq_cap1, irq_ovf : std_logic;
    signal irq_cmp0, irq_cmp1, irq_cmp2 : std_logic;

    -- register bus
    signal en_mem      : std_logic := '1';
    signal wen         : std_logic_vector(3 downto 0) := (others => '1');
    signal addr_periph : std_logic_vector(7 downto 2) := (others => '0');
    signal write_data  : word := (others => '0');
    signal read_data   : word;

    -- compare 0/1 pins
    signal cmp0_ren_in, cmp1_ren_in : std_logic := '0';
    signal cmp0_out, cmp0_dir, cmp0_ren : std_logic;
    signal cmp1_out, cmp1_dir, cmp1_ren : std_logic;

    -- capture 0/1 pins
    signal cap0_ren_in : std_logic := '0';
    signal cap0_in     : std_logic := '0';
    signal cap0_dir, cap0_ren : std_logic;
    signal cap1_ren_in : std_logic := '0';
    signal cap1_in     : std_logic := '0';
    signal cap1_dir, cap1_ren : std_logic;

    function img(v : std_logic_vector) return string is
    begin
        if is_x(v) then
            return "X";
        else
            return integer'image(to_integer(unsigned(v)));
        end if;
    end function;

begin

    clk     <= not clk after CLK_PERIOD / 2;
    clk_mem <= clk when en_mem = '0' else '0';

    dut : entity work.TIMER
        port map (
            mclk        => mclk,
            smclk       => smclk,
            clk_lfxt    => clk_lfxt,
            clk_hfxt    => clk_hfxt,
            resetn      => resetn,
            irq_cap0    => irq_cap0,
            irq_cap1    => irq_cap1,
            irq_ovf     => irq_ovf,
            irq_cmp0    => irq_cmp0,
            irq_cmp1    => irq_cmp1,
            irq_cmp2    => irq_cmp2,
            clk_mem     => clk_mem,
            en_mem      => en_mem,
            wen         => wen,
            addr_periph => addr_periph,
            write_data  => write_data,
            read_data   => read_data,
            cmp0_ren_in => cmp0_ren_in,
            cmp0_out    => cmp0_out,
            cmp0_dir    => cmp0_dir,
            cmp0_ren    => cmp0_ren,
            cmp1_ren_in => cmp1_ren_in,
            cmp1_out    => cmp1_out,
            cmp1_dir    => cmp1_dir,
            cmp1_ren    => cmp1_ren,
            cap0_ren_in => cap0_ren_in,
            cap0_in     => cap0_in,
            cap0_dir    => cap0_dir,
            cap0_ren    => cap0_ren,
            cap1_ren_in => cap1_ren_in,
            cap1_in     => cap1_in,
            cap1_dir    => cap1_dir,
            cap1_ren    => cap1_ren
        );

    stim_proc : process

        variable error_count : natural := 0;
        variable rdw         : word;

        procedure check_slv(tag : in string;
                            got : in std_logic_vector;
                            exp : in std_logic_vector) is
        begin
            if got = exp then
                report "PASS: " & tag severity note;
            else
                error_count := error_count + 1;
                assert false
                    report "FAIL: " & tag &
                           " (expected " & img(exp) & ", got " & img(got) & ")"
                    severity warning;
            end if;
        end procedure;

        procedure check_bit(tag : in string;
                            got : in std_logic;
                            exp : in std_logic) is
        begin
            if got = exp then
                report "PASS: " & tag severity note;
            else
                error_count := error_count + 1;
                assert false
                    report "FAIL: " & tag &
                           " (expected " & std_logic'image(exp) &
                           ", got " & std_logic'image(got) & ")"
                    severity warning;
            end if;
        end procedure;

        procedure bus_write(slot : in natural;
                            data : in std_logic_vector(31 downto 0)) is
        begin
            wait until falling_edge(clk);
            addr_periph <= std_logic_vector(to_unsigned(slot, 6));
            write_data  <= data;
            wen         <= (others => '0');
            en_mem      <= '0';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            en_mem      <= '1';
            wen         <= (others => '1');
        end procedure;

        procedure bus_read(slot : in natural;
                           data : out std_logic_vector(31 downto 0)) is
        begin
            wait until falling_edge(clk);
            addr_periph <= std_logic_vector(to_unsigned(slot, 6));
            en_mem      <= '0';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            data := read_data;
            en_mem      <= '1';
        end procedure;

        -- Generate n clean rising edges on smclk (the timer source).
        procedure timer_ticks(n : in natural) is
        begin
            for i in 1 to n loop
                smclk <= '1';
                wait for TICK / 2;
                smclk <= '0';
                wait for TICK / 2;
            end loop;
        end procedure;

    begin
        ----------------------------------------------------------------
        -- Reset
        ----------------------------------------------------------------
        resetn <= '0';
        en_mem <= '1';
        wen    <= (others => '1');
        smclk  <= '0';
        wait for 4 * CLK_PERIOD;
        wait for 1 ns;
        resetn <= '1';
        wait for 4 * CLK_PERIOD;

        ----------------------------------------------------------------
        -- GROUP 1: reset / defaults / static pin config
        ----------------------------------------------------------------
        report "=== GROUP 1: reset & defaults ===" severity note;

        bus_read(RegSlotTIMxCR, rdw);
        check_slv("CR resets to 0", rdw(19 downto 0), (19 downto 0 => '0'));
        bus_read(RegSlotTIMxVAL, rdw);
        check_slv("timer value resets to 0", rdw, x"00000000");
        bus_read(RegSlotTIMxSR, rdw);
        check_slv("SR resets to 0", rdw(7 downto 0), x"00");
        bus_read(RegSlotTIMxCMP0, rdw);
        check_slv("CMP0 resets to 0", rdw, x"00000000");

        check_bit("cap0 pin is input", cap0_dir, '0');
        check_bit("cap1 pin is input", cap1_dir, '0');
        check_bit("cmp0 pin is output", cmp0_dir, '1');
        check_bit("cmp1 pin is output", cmp1_dir, '1');

        cap0_ren_in <= '1'; cmp0_ren_in <= '1';
        wait for 1 ns;
        check_bit("cap0_ren passthrough", cap0_ren, '1');
        check_bit("cmp0_ren passthrough", cmp0_ren, '1');
        cap0_ren_in <= '0'; cmp0_ren_in <= '0';

        check_bit("irq_cmp0 low at reset", irq_cmp0, '0');
        check_bit("irq_ovf low at reset",  irq_ovf,  '0');
        check_bit("irq_cap0 low at reset", irq_cap0, '0');

        ----------------------------------------------------------------
        -- GROUP 2: register read/write (control + compare byte lanes)
        ----------------------------------------------------------------
        report "=== GROUP 2: register R/W ===" severity note;

        bus_write(RegSlotTIMxCR, x"000ABCDE");           -- only 20 bits stored
        bus_read(RegSlotTIMxCR, rdw);
        check_slv("CR 20-bit readback", rdw(19 downto 0), x"ABCDE");
        check_slv("CR upper bits read 0", rdw(31 downto 20), x"000");
        bus_write(RegSlotTIMxCR, x"00000000");

        bus_write(RegSlotTIMxCMP0, x"12345678");
        bus_read(RegSlotTIMxCMP0, rdw);
        check_slv("CMP0 32-bit readback", rdw, x"12345678");
        bus_write(RegSlotTIMxCMP1, x"DEADBEEF");
        bus_read(RegSlotTIMxCMP1, rdw);
        check_slv("CMP1 32-bit readback", rdw, x"DEADBEEF");
        bus_write(RegSlotTIMxCMP2, x"0BADF00D");
        bus_read(RegSlotTIMxCMP2, rdw);
        check_slv("CMP2 32-bit readback", rdw, x"0BADF00D");
        bus_write(RegSlotTIMxCMP0, x"00000000");
        bus_write(RegSlotTIMxCMP1, x"00000000");
        bus_write(RegSlotTIMxCMP2, x"00000000");

        ----------------------------------------------------------------
        -- GROUP 3: timer value write (load)
        ----------------------------------------------------------------
        report "=== GROUP 3: timer value load ===" severity note;

        bus_write(RegSlotTIMxVAL, x"0000ABCD");
        bus_read(RegSlotTIMxVAL, rdw);
        check_slv("timer value loaded", rdw, x"0000ABCD");
        bus_write(RegSlotTIMxVAL, x"00000000");

        ----------------------------------------------------------------
        -- GROUP 4: counting at divide-by-1 (exact count)
        ----------------------------------------------------------------
        report "=== GROUP 4: count /1 ===" severity note;

        -- Warm up the glitch-free clock path: the very first smclk edge after a
        -- cold start is absorbed by the mux/gate enable synchronizers, so prime
        -- it once (timer enabled) before relying on exact counts.
        bus_write(RegSlotTIMxCR,  x"00000040");          -- enable, div1, src=smclk
        wait for TICK;
        timer_ticks(2);

        bus_write(RegSlotTIMxVAL, x"00000000");          -- reset count (still enabled)
        timer_ticks(10);
        bus_read(RegSlotTIMxVAL, rdw);
        check_slv("10 ticks -> count 10", rdw, x"0000000A");
        timer_ticks(5);
        bus_read(RegSlotTIMxVAL, rdw);
        check_slv("15 ticks -> count 15", rdw, x"0000000F");

        -- disable freezes the counter
        bus_write(RegSlotTIMxCR, x"00000000");
        timer_ticks(8);                                  -- ignored while disabled
        bus_read(RegSlotTIMxVAL, rdw);
        check_slv("count frozen while disabled", rdw, x"0000000F");

        ----------------------------------------------------------------
        -- GROUP 5: counting at divide-by-2
        ----------------------------------------------------------------
        report "=== GROUP 5: count /2 ===" severity note;

        bus_write(RegSlotTIMxVAL, x"00000000");
        bus_write(RegSlotTIMxCR,  x"00010040");          -- enable, divider=0001 (/2)
        wait for TICK;
        timer_ticks(8);
        bus_read(RegSlotTIMxVAL, rdw);
        check_slv("8 ticks /2 -> count 4", rdw, x"00000004");
        bus_write(RegSlotTIMxCR, x"00000000");

        ----------------------------------------------------------------
        -- GROUP 6: overflow flag + interrupt
        ----------------------------------------------------------------
        report "=== GROUP 6: overflow ===" severity note;

        bus_write(RegSlotTIMxVAL, x"FFFFFFFF");          -- one tick from wrap
        bus_write(RegSlotTIMxCR,  x"00000048");          -- enable + overflow IE (bit3)
        wait for TICK;
        timer_ticks(1);
        bus_read(RegSlotTIMxSR, rdw);
        check_bit("overflow flag set", rdw(3), '1');
        check_bit("irq_ovf asserted",  irq_ovf, '1');
        bus_read(RegSlotTIMxVAL, rdw);
        check_slv("timer wrapped to 0", rdw, x"00000000");

        bus_write(RegSlotTIMxSR, x"00000008");           -- clear overflow (bit3)
        bus_read(RegSlotTIMxSR, rdw);
        check_bit("overflow flag cleared", rdw(3), '0');
        check_bit("irq_ovf deasserted", irq_ovf, '0');
        bus_write(RegSlotTIMxCR, x"00000000");

        ----------------------------------------------------------------
        -- GROUP 7: compare 0 match -> flag + PWM output toggle + irq
        ----------------------------------------------------------------
        report "=== GROUP 7: compare 0 match ===" severity note;

        bus_write(RegSlotTIMxVAL,  x"00000000");
        bus_write(RegSlotTIMxCMP0, x"00000004");
        bus_write(RegSlotTIMxCR,   x"00000041");         -- enable + cmp0 IE, init level 0
        wait for TICK;
        timer_ticks(6);                                  -- crosses count=4
        -- read SR while still enabled (output resets to init when disabled)
        bus_read(RegSlotTIMxSR, rdw);
        check_bit("compare0 flag set", rdw(0), '1');
        check_bit("compare0 output toggled high", rdw(6), '1');
        check_bit("irq_cmp0 asserted", irq_cmp0, '1');

        bus_write(RegSlotTIMxSR, x"00000001");           -- clear cmp0 flag (bit0)
        bus_read(RegSlotTIMxSR, rdw);
        check_bit("compare0 flag cleared", rdw(0), '0');
        check_bit("irq_cmp0 deasserted", irq_cmp0, '0');
        bus_write(RegSlotTIMxCR, x"00000000");

        ----------------------------------------------------------------
        -- GROUP 8: compare 2 auto-reset
        ----------------------------------------------------------------
        report "=== GROUP 8: compare 2 auto-reset ===" severity note;

        bus_write(RegSlotTIMxVAL,  x"00000000");
        bus_write(RegSlotTIMxCMP2, x"00000004");
        bus_write(RegSlotTIMxCR,   x"000000C4");         -- enable + cmp2 reset_en(7) + cmp2 IE(2)
        wait for TICK;
        timer_ticks(7);                                  -- timer resets at count=4
        bus_read(RegSlotTIMxSR, rdw);
        check_bit("compare2 flag set", rdw(2), '1');
        check_bit("irq_cmp2 asserted", irq_cmp2, '1');
        bus_read(RegSlotTIMxVAL, rdw);
        -- after reset at 4, the remaining ticks restart from 0
        check_slv("timer auto-reset wrapped low", rdw, x"00000002");
        bus_write(RegSlotTIMxSR, x"00000004");           -- clear cmp2 flag (bit2)
        bus_read(RegSlotTIMxSR, rdw);
        check_bit("compare2 flag cleared", rdw(2), '0');
        bus_write(RegSlotTIMxCR, x"00000000");

        ----------------------------------------------------------------
        -- GROUP 9: input capture 0 (rising edge)
        ----------------------------------------------------------------
        report "=== GROUP 9: capture 0 (rising) ===" severity note;

        bus_write(RegSlotTIMxVAL, x"000000AA");          -- known frozen timer value
        cap0_in <= '0';
        bus_write(RegSlotTIMxCR, x"00000410");           -- cap0 enable(10) + cap0 IE(4), timer off
        wait for TICK;
        cap0_in <= '1';                                  -- rising edge -> capture
        wait for TICK;
        bus_read(RegSlotTIMxSR, rdw);
        check_bit("capture0 flag set", rdw(4), '1');
        check_bit("irq_cap0 asserted", irq_cap0, '1');
        bus_read(RegSlotTIMxCAP0, rdw);
        check_slv("capture0 grabbed timer value 0xAA", rdw, x"000000AA");
        bus_write(RegSlotTIMxSR, x"00000010");           -- clear cap0 flag (bit4)
        bus_read(RegSlotTIMxSR, rdw);
        check_bit("capture0 flag cleared", rdw(4), '0');
        cap0_in <= '0';
        bus_write(RegSlotTIMxCR, x"00000000");

        ----------------------------------------------------------------
        -- GROUP 10: input capture 1 (falling edge)
        ----------------------------------------------------------------
        report "=== GROUP 10: capture 1 (falling) ===" severity note;

        bus_write(RegSlotTIMxVAL, x"00000055");
        cap1_in <= '1';                                  -- idle high
        bus_write(RegSlotTIMxCR, x"00002820");           -- cap1 en(11)+IE(5)+fall(13)
        wait for TICK;
        cap1_in <= '0';                                  -- falling edge -> capture
        wait for TICK;
        bus_read(RegSlotTIMxSR, rdw);
        check_bit("capture1 flag set", rdw(5), '1');
        check_bit("irq_cap1 asserted", irq_cap1, '1');
        bus_read(RegSlotTIMxCAP1, rdw);
        check_slv("capture1 grabbed timer value 0x55", rdw, x"00000055");
        bus_write(RegSlotTIMxSR, x"00000020");           -- clear cap1 flag (bit5)
        bus_read(RegSlotTIMxSR, rdw);
        check_bit("capture1 flag cleared", rdw(5), '0');
        cap1_in <= '1';
        bus_write(RegSlotTIMxCR, x"00000000");

        ----------------------------------------------------------------
        -- Final verdict
        ----------------------------------------------------------------
        wait for 1 us;
        if error_count = 0 then
            report LF & LF &
                "    ##################################################" & LF &
                "    ##                                              ##" & LF &
                "    ##       TIMER TB:  ALL CHECKS PASSED           ##" & LF &
                "    ##                                              ##" & LF &
                "    ##################################################" & LF
                severity note;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!                                              !!" & LF &
                "    !!   TIMER TB:  " & integer'image(error_count) &
                       " CHECK(S) FAILED" & LF &
                "    !!                                              !!" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        stop;
        wait;
    end process;

end architecture sim;
