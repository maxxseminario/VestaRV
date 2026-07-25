-------------------------------------------------------------------------------
-- TIMER_tb.vhd
-------------------------------------------------------------------------------
-- Standalone, self-checking testbench for the TIMER peripheral
-- (hdl/common/periph/TIMER.vhd). TIMER predates the bench ritual (it was
-- covered only at ISA level) and is otherwise a mature, unit-proven block --
-- this bench is deliberately MINIMAL and TAP-FOCUSED: it exists to prove the
-- four new EVFAB taps Fable's RTL edit added (event_fabric_spec.md
-- 2026-07-24), not to re-verify the whole peripheral. It follows the house
-- style of tb/PWM_tb.vhd (component DUT so this bench compiles standalone,
-- work.periph_tb_pkg's scoreboard + register-bus BFM, G-NEG last).
--
-- EVFAB taps under test (see hdl/common/periph/TIMER.vhd's EVFAB comment
-- block, lines ~72-88):
--   evt_compare0 / evt_overflow -- T-mode TOGGLE producers in the
--     timer_clock domain: flip ONCE per compare0-match / overflow
--     occurrence, in their OWN process (resetn-only async), never touched by
--     the flags' W1C clears. Checker independence: a continuous background
--     monitor (evt_mon_proc below) counts FLIPS as the XOR of consecutive
--     `clk` samples -- never reads a DUT internal.
--   task_start / task_stop -- one-clk_mem consumer TASK pulses that set/clear
--     control_reg(6) (timer enable) OUTSIDE the en_mem gate (clk_mem
--     free-runs at integration -- so this bench ties clk_mem directly to the
--     free-running reference clock, no bus-idle gating, unlike some other
--     benches' `ClkMem <= clk when en_mem='0' else '0'` idiom). A task wins
--     its bit on a coincident CPU CR write; same-cycle start+stop resolves to
--     STOP (both per the RTL comment and per CLAUDE.md).
--
-- CLOCKING / THE MUX-RELEASE GOTCHA (CLAUDE.md): TIMER's ClockMuxGlitchFree
-- defaults to the smclk slice (index 0) and needs 3 smclk edges to release
-- it before another source (mclk/lfxt/hfxt) can engage. This bench drives
-- mclk, smclk, clk_lfxt and clk_hfxt ALL from the same free-running 20 ns
-- reference `clk` (so the release condition is satisfied quickly and
-- deterministically) and clk_mem likewise -- matching the header's
-- FREE-RUNNING integration truth. Every group that (re)selects a clock
-- source and enables the timer POLLS TIMxVAL until it visibly counts
-- (poll_val_counting) rather than assuming a fixed edge count before relying
-- on the timer.
--
-- FLIP-COUNTING DISCIPLINE: rather than computing exact edge counts up front
-- (fragile against the mux/gate latencies), each exact-count check uses a
-- bounded POLL until the background monitor's flip tally reaches the
-- expected count, then immediately disables the timer (freezing
-- clock_source, hence timer_clock, hence any further match) and confirms the
-- tally is EXACTLY the expected value (no overshoot). This is
-- timing-insensitive by construction and still an exact check.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.periph_tb_pkg.all;
use work.MemoryMap.all;

entity TIMER_tb is
end entity TIMER_tb;

architecture sim of TIMER_tb is

    constant PERIOD : time := 20 ns;   -- free-running reference clock

    -- FROZEN DUT entity (hdl/common/periph/TIMER.vhd), declared as a
    -- component so default binding resolves it once TIMER.vhd is analyzed
    -- into `work` -- Fable owns the RTL, never edited here.
    component TIMER is
        port (
            mclk         : in  std_logic;
            smclk        : in  std_logic;
            clk_lfxt     : in  std_logic;
            clk_hfxt     : in  std_logic;
            resetn       : in  std_logic;

            irq_cap0     : out std_logic;
            irq_cap1     : out std_logic;
            irq_ovf      : out std_logic;
            irq_cmp0     : out std_logic;
            irq_cmp1     : out std_logic;
            irq_cmp2     : out std_logic;

            clk_mem      : in  std_logic;
            en_mem       : in  std_logic;
            wen          : in  std_logic_vector(3 downto 0);
            addr_periph  : in  std_logic_vector(7 downto 2);
            write_data   : in  std_logic_vector(31 downto 0);
            read_data    : out std_logic_vector(31 downto 0);

            cmp0_ren_in  : in  std_logic;
            cmp0_out     : out std_logic;
            cmp0_dir     : out std_logic;
            cmp0_ren     : out std_logic;

            cmp1_ren_in  : in  std_logic;
            cmp1_out     : out std_logic;
            cmp1_dir     : out std_logic;
            cmp1_ren     : out std_logic;

            cap0_ren_in  : in  std_logic;
            cap0_in      : in  std_logic;
            cap0_dir     : out std_logic;
            cap0_ren     : out std_logic;

            cap1_ren_in  : in  std_logic;
            cap1_in      : in  std_logic;
            cap1_dir     : out std_logic;
            cap1_ren     : out std_logic;

            evt_compare0 : out std_logic;
            evt_overflow : out std_logic;
            task_start   : in  std_logic := '0';
            task_stop    : in  std_logic := '0'
        );
    end component;

    -- ---- clocks / reset ----------------------------------------------------
    -- ALL clock inputs tied to the SAME free-running reference (see header):
    -- guarantees the glitch-free mux's smclk release condition is satisfied
    -- quickly no matter which source CR(9:8) selects.
    signal clk      : std_logic := '0';
    signal mclk     : std_logic;
    signal smclk    : std_logic;
    signal clk_lfxt : std_logic;
    signal clk_hfxt : std_logic;
    signal clk_mem  : std_logic;   -- free-running (task_start/stop act outside en_mem)
    signal resetn   : std_logic := '0';

    -- ---- register bus -------------------------------------------------------
    signal pbus      : periph_bus_t := PERIPH_BUS_IDLE;
    signal read_data : std_logic_vector(31 downto 0);

    -- ---- interrupts -----------------------------------------------------
    signal irq_cap0, irq_cap1, irq_ovf  : std_logic;
    signal irq_cmp0, irq_cmp1, irq_cmp2 : std_logic;

    -- ---- compare/capture pins (tap bench: tie sensibly, capture pins '0') --
    signal cmp0_ren_in, cmp1_ren_in     : std_logic := '0';
    signal cmp0_out, cmp0_dir, cmp0_ren : std_logic;
    signal cmp1_out, cmp1_dir, cmp1_ren : std_logic;
    signal cap0_ren_in : std_logic := '0';
    signal cap0_in     : std_logic := '0';
    signal cap0_dir, cap0_ren : std_logic;
    signal cap1_ren_in : std_logic := '0';
    signal cap1_in     : std_logic := '0';
    signal cap1_dir, cap1_ren : std_logic;

    -- ---- EVFAB taps (event_fabric_spec.md 2026-07-24) ----------------------
    signal evt_compare0 : std_logic;
    signal evt_overflow : std_logic;
    signal task_start   : std_logic := '0';   -- tb-driven, default '0'
    signal task_stop    : std_logic := '0';   -- tb-driven, default '0'

    -- ---- continuous EVFAB flip monitor (checker independence) -------------
    -- Counts toggle FLIPS (XOR of consecutive `clk` samples) on each producer
    -- tap since the last evt_mon_clear pulse. NEVER reads a DUT internal --
    -- only the exported evt_compare0/evt_overflow ports.
    signal evt_cmp0_flips, evt_ovf_flips : natural := 0;
    signal evt_cmp0_prev, evt_ovf_prev   : std_logic := '0';
    signal evt_mon_clear : std_logic := '0';

    signal tb_done : boolean := false;

    shared variable sb : scoreboard;

begin

    ----------------------------------------------------------------------------
    -- clocks: one free-running reference drives every DUT clock input,
    -- including the gated bus clock (clk_mem free-runs at integration -- see
    -- header; task_start/task_stop must be observed even with the bus idle).
    ----------------------------------------------------------------------------
    clk      <= not clk after PERIOD / 2;
    mclk     <= clk;
    smclk    <= clk;
    clk_lfxt <= clk;
    clk_hfxt <= clk;
    clk_mem  <= clk;

    ----------------------------------------------------------------------------
    -- Continuous EVFAB flip monitor (see signal-declaration comment above).
    ----------------------------------------------------------------------------
    evt_mon_proc : process(clk)
        variable c_lvl, o_lvl : std_logic;
    begin
        if rising_edge(clk) then
            c_lvl := to_X01(evt_compare0);
            o_lvl := to_X01(evt_overflow);
            if evt_mon_clear = '1' then
                evt_cmp0_flips <= 0;
                evt_ovf_flips  <= 0;
                evt_cmp0_prev  <= c_lvl;
                evt_ovf_prev   <= o_lvl;
            else
                if c_lvl /= evt_cmp0_prev then
                    evt_cmp0_flips <= evt_cmp0_flips + 1;
                end if;
                if o_lvl /= evt_ovf_prev then
                    evt_ovf_flips <= evt_ovf_flips + 1;
                end if;
                evt_cmp0_prev <= c_lvl;
                evt_ovf_prev  <= o_lvl;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------------
    dut : component TIMER
        port map (
            mclk         => mclk,
            smclk        => smclk,
            clk_lfxt     => clk_lfxt,
            clk_hfxt     => clk_hfxt,
            resetn       => resetn,
            irq_cap0     => irq_cap0,
            irq_cap1     => irq_cap1,
            irq_ovf      => irq_ovf,
            irq_cmp0     => irq_cmp0,
            irq_cmp1     => irq_cmp1,
            irq_cmp2     => irq_cmp2,
            clk_mem      => clk_mem,
            en_mem       => pbus.en_mem,
            wen          => pbus.wen,
            addr_periph  => pbus.addr_periph,
            write_data   => pbus.write_data,
            read_data    => read_data,
            cmp0_ren_in  => cmp0_ren_in,
            cmp0_out     => cmp0_out,
            cmp0_dir     => cmp0_dir,
            cmp0_ren     => cmp0_ren,
            cmp1_ren_in  => cmp1_ren_in,
            cmp1_out     => cmp1_out,
            cmp1_dir     => cmp1_dir,
            cmp1_ren     => cmp1_ren,
            cap0_ren_in  => cap0_ren_in,
            cap0_in      => cap0_in,
            cap0_dir     => cap0_dir,
            cap0_ren     => cap0_ren,
            cap1_ren_in  => cap1_ren_in,
            cap1_in      => cap1_in,
            cap1_dir     => cap1_dir,
            cap1_ren     => cap1_ren,
            evt_compare0 => evt_compare0,
            evt_overflow => evt_overflow,
            task_start   => task_start,
            task_stop    => task_stop
        );

    ----------------------------------------------------------------------------
    -- Watchdog: abort with a FAIL banner if the stimulus ever hangs. This
    -- bench's whole run is a handful of microseconds -- 20 ms is a huge margin.
    ----------------------------------------------------------------------------
    watchdog : process
    begin
        wait for 20 ms;
        if not tb_done then
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   TIMER_TB FAIL (WATCHDOG TIMEOUT -- stimulus never finished)" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
            stop;
        end if;
        wait;
    end process;

    ----------------------------------------------------------------------------
    -- stimulus
    ----------------------------------------------------------------------------
    stim_proc : process
        variable rdw, rdw2 : std_logic_vector(31 downto 0);
        variable ok        : boolean;

        -- Reset pulse: resetn low for a few PERIODs then back high. Leaves
        -- the bus idle and the flip monitor un-cleared (callers evt_mon_reset
        -- when they start a window of interest).
        procedure reset_pulse is
        begin
            resetn     <= '0';
            pbus       <= PERIPH_BUS_IDLE;
            task_start <= '0';
            task_stop  <= '0';
            wait for 6 * PERIOD;
            wait for 1 ns;
            resetn <= '1';
            wait for 4 * PERIOD;
        end procedure;

        -- Clear the EVFAB flip monitor's accumulators. Call only outside a
        -- timing-critical window (same discipline as PWM_tb's mon_reset).
        procedure evt_mon_reset is
        begin
            wait until clk = '0';
            evt_mon_clear <= '1';
            wait until clk = '1';
            wait until clk = '0';
            evt_mon_clear <= '0';
        end procedure;

        -- Let exactly `n` clk RISING edges pass, then settle to the
        -- following falling edge (PWM_tb's wait_edges idiom).
        procedure wait_edges(n : natural) is
        begin
            for i in 1 to n loop
                wait until clk = '1';
            end loop;
            wait until clk = '0';
        end procedure;

        -- Drive `sig` high across exactly one clk_mem rising edge (clk_mem =
        -- clk here), then drop it -- the one-clk_mem task-pulse idiom.
        procedure pulse1(signal sig : out std_logic) is
        begin
            wait until clk = '0';
            sig <= '1';
            wait until clk = '1';
            wait until clk = '0';
            sig <= '0';
        end procedure;

        -- Pulse task_start AND task_stop across the SAME clk_mem rising edge
        -- (the G4 "coincident start+stop" corner).
        procedure pulse_both_tasks is
        begin
            wait until clk = '0';
            task_start <= '1';
            task_stop  <= '1';
            wait until clk = '1';
            wait until clk = '0';
            task_start <= '0';
            task_stop  <= '0';
        end procedure;

        -- CPU CR write coincident with a task pulse, landing on the SAME
        -- clk_mem rising edge (the G4 "coincident CPU write + task" corner).
        -- Mirrors periph_tb_pkg.bus_write's exact timing, with task_start/
        -- task_stop asserted across the same capture edge.
        procedure coincident_cr_write_task(cr_word : std_logic_vector(31 downto 0);
                                            do_start, do_stop : std_logic) is
        begin
            wait until clk = '0';
            pbus.addr_periph <= std_logic_vector(to_unsigned(RegSlotTIMxCR, 6));
            pbus.write_data  <= cr_word;
            pbus.wen         <= (others => '0');
            pbus.en_mem      <= '0';
            task_start       <= do_start;
            task_stop        <= do_stop;
            wait until clk = '1';
            wait until clk = '0';
            pbus.en_mem <= '1';
            pbus.wen    <= (others => '1');
            task_start  <= '0';
            task_stop   <= '0';
        end procedure;

        -- Poll (bounded) until two TIMxVAL reads, a few clk apart, differ --
        -- the mux-release gotcha check (CLAUDE.md): never assume a fixed
        -- edge count before relying on the timer running.
        procedure poll_val_counting(guard : natural; ok : out boolean) is
            variable v0, v1 : std_logic_vector(31 downto 0);
            variable g : natural := 0;
        begin
            ok := false;
            bus_read(clk, pbus, read_data, RegSlotTIMxVAL, v0);
            loop
                wait_edges(3);
                bus_read(clk, pbus, read_data, RegSlotTIMxVAL, v1);
                if v1 /= v0 then
                    ok := true;
                    exit;
                end if;
                v0 := v1;
                g := g + 1;
                exit when g > guard;
            end loop;
        end procedure;

        -- Bounded poll of one TIMxSR bit until it reads `exp`.
        procedure poll_sr_bit(bit_idx : natural; exp : std_logic;
                              guard : natural; ok : out boolean) is
            variable r : std_logic_vector(31 downto 0);
            variable g : natural := 0;
        begin
            ok := false;
            loop
                bus_read(clk, pbus, read_data, RegSlotTIMxSR, r);
                if to_X01(r(bit_idx)) = exp then
                    ok := true;
                    exit;
                end if;
                g := g + 1;
                exit when g > guard;
            end loop;
        end procedure;

        -- Bounded poll until the given flip-count signal (evt_cmp0_flips or
        -- evt_ovf_flips) reaches at least `target`.
        procedure wait_flips_ge(signal cnt : in natural; target : natural;
                                guard_edges : natural; ok : out boolean) is
            variable g : natural := 0;
        begin
            ok := false;
            loop
                wait until clk = '1';
                if cnt >= target then
                    ok := true;
                    exit;
                end if;
                g := g + 1;
                exit when g > guard_edges;
            end loop;
        end procedure;

    begin
        ------------------------------------------------------------------
        -- Reset
        ------------------------------------------------------------------
        reset_pulse;

        ------------------------------------------------------------------
        -- GROUP G1: baseline -- select a fast source (CR 9:8=01, mclk),
        -- small compare0, poll-until-counting (mux-release gotcha), confirm
        -- the compare0 flag sets.
        ------------------------------------------------------------------
        report "=== GROUP G1: baseline (mux-release + compare0 flag) ===" severity note;
        bus_write(clk, pbus, RegSlotTIMxCMP0, x"00000020");   -- compare0 = 32
        bus_write(clk, pbus, RegSlotTIMxCR,   x"00000140");   -- enable(6) + src=01(9:8)=mclk
        poll_val_counting(60, ok);
        sb.check_true("G1: TIMxVAL visibly counting after enable (mux-release gotcha, bounded poll)", ok);
        poll_sr_bit(0, '1', 80, ok);
        sb.check_true("G1: compare0 flag (SR bit0) sets (bounded poll)", ok);

        ------------------------------------------------------------------
        -- GROUP G2: evt_compare0 -- exactly N toggle flips across N compare
        -- events, then zero flips while stopped. Uses the compare2
        -- auto-reset feature (CR bit7) to make compare0 re-lap on a short,
        -- bounded period (33 clks) rather than a full 32-bit wrap.
        ------------------------------------------------------------------
        report "=== GROUP G2: evt_compare0 flip count ===" severity note;
        reset_pulse;
        bus_write(clk, pbus, RegSlotTIMxCMP0, x"00000010");   -- compare0 = 16
        bus_write(clk, pbus, RegSlotTIMxCMP2, x"00000020");   -- compare2 = 32 (period = 33 clks)
        evt_mon_reset;
        bus_write(clk, pbus, RegSlotTIMxCR, x"000001C0");     -- enable + cmp2_reset_en(7) + src=01
        poll_val_counting(60, ok);
        sb.check_true("G2: TIMxVAL visibly counting (mux-release gotcha, bounded poll)", ok);

        wait_flips_ge(evt_cmp0_flips, 3, 400, ok);
        sb.check_true("G2a: evt_compare0 reaches 3 flips across 3 compare events (bounded poll)", ok);
        bus_write(clk, pbus, RegSlotTIMxCR, x"00000000");     -- disable immediately -- freeze, no overshoot
        sb.check_true("G2a: evt_compare0 flip count is EXACTLY 3 (no overshoot after disable)",
                      evt_cmp0_flips = 3);

        -- Stopped (CR(6)=0 via bus): zero flips over a bounded window.
        evt_mon_reset;
        wait_edges(80);
        sb.check_true("G2b: STOPPED timer produces zero evt_compare0 flips over a bounded window",
                      evt_cmp0_flips = 0);
        sb.check_true("G2b: STOPPED timer produces zero evt_overflow flips over the same window",
                      evt_ovf_flips = 0);

        ------------------------------------------------------------------
        -- GROUP G3: evt_overflow -- set TIMxVAL near wrap via the VAL write
        -- path, run to wrap, confirm exactly one flip and the overflow flag.
        ------------------------------------------------------------------
        report "=== GROUP G3: evt_overflow flip count ===" severity note;
        reset_pulse;
        -- compare0_reg resets to 0 along with everything else on resetn --
        -- 0 is exactly the wrap landing value, so leaving it there would
        -- spuriously fire a compare0 match (and an evt_compare0 flip) one
        -- timer_clock after the wrap. Park CMP0 well out of reach of this
        -- group's brief post-wrap observation window instead.
        bus_write(clk, pbus, RegSlotTIMxCMP0, x"00000100");   -- compare0 parked at 256 (unreachable here)
        bus_write(clk, pbus, RegSlotTIMxVAL, x"FFFFFFF0");    -- one lap from wrap (16 counts to go)
        evt_mon_reset;
        bus_write(clk, pbus, RegSlotTIMxCR, x"00000140");     -- enable + src=01=mclk (no cmp2_reset_en)
        poll_val_counting(60, ok);
        sb.check_true("G3: TIMxVAL visibly counting from the loaded value (mux-release gotcha, bounded poll)", ok);

        wait_flips_ge(evt_ovf_flips, 1, 80, ok);
        sb.check_true("G3a: evt_overflow reaches 1 flip after the wrap (bounded poll)", ok);
        bus_write(clk, pbus, RegSlotTIMxCR, x"00000000");     -- disable immediately -- freeze, no overshoot
        sb.check_true("G3a: evt_overflow flip count is EXACTLY 1 (no overshoot after disable)",
                      evt_ovf_flips = 1);
        sb.check_true("G3a: evt_compare0 did not spuriously flip on this run (never neared compare0)",
                      evt_cmp0_flips = 0);

        poll_sr_bit(3, '1', 20, ok);
        sb.check_true("G3b: overflow flag (SR bit3) sets", ok);

        ------------------------------------------------------------------
        -- GROUP G4: task_start / task_stop -- one-clk_mem consumer task
        -- pulses (act outside the en_mem gate; clk_mem free-runs).
        ------------------------------------------------------------------
        report "=== GROUP G4: task_start / task_stop ===" severity note;
        reset_pulse;
        bus_write(clk, pbus, RegSlotTIMxCR, x"00000100");     -- src=01=mclk, enabled=0

        -- task_start: one pulse -> CR(6) reads 1, VAL starts advancing.
        pulse1(task_start);
        bus_read(clk, pbus, read_data, RegSlotTIMxCR, rdw);
        sb.check_bit("G4a: task_start sets CR(6) (timer enable)", to_X01(rdw(6)), '1');
        poll_val_counting(60, ok);
        sb.check_true("G4a: TIMxVAL visibly counting after task_start (bounded poll)", ok);

        -- task_stop: one pulse -> CR(6) reads 0, VAL freezes.
        pulse1(task_stop);
        bus_read(clk, pbus, read_data, RegSlotTIMxCR, rdw);
        sb.check_bit("G4b: task_stop clears CR(6) (timer enable)", to_X01(rdw(6)), '0');
        bus_read(clk, pbus, read_data, RegSlotTIMxVAL, rdw);
        wait_edges(20);
        bus_read(clk, pbus, read_data, RegSlotTIMxVAL, rdw2);
        sb.check_true("G4b: TIMxVAL frozen after task_stop", rdw = rdw2);

        -- Coincident task_start + task_stop on the SAME clk_mem edge -> STOP
        -- wins (CR(6)=0). Prime CR(6)=1 first so the resolution is unambiguous.
        bus_write(clk, pbus, RegSlotTIMxCR, x"00000140");     -- enable=1, src=01
        pulse_both_tasks;
        bus_read(clk, pbus, read_data, RegSlotTIMxCR, rdw);
        sb.check_bit("G4c: coincident task_start+task_stop -> CR(6)=0 (stop wins)", to_X01(rdw(6)), '0');

        -- Coincident CPU CR write + task pulse -> the task's bit value wins.
        -- Direction 1: CPU write sets CR=0 (bit6=0) while task_start pulses
        -- on the SAME edge -> CR(6) ends up 1 (task wins over the write).
        bus_write(clk, pbus, RegSlotTIMxCR, x"00000000");     -- baseline: disabled
        coincident_cr_write_task(x"00000000", '1', '0');      -- CPU writes bit6=0, task_start=1
        bus_read(clk, pbus, read_data, RegSlotTIMxCR, rdw);
        sb.check_bit("G4d: coincident CPU write (bit6=0) + task_start -> CR(6)=1 (task wins)",
                     to_X01(rdw(6)), '1');

        -- Direction 2: CPU write sets CR bit6=1 while task_stop pulses on
        -- the SAME edge -> CR(6) ends up 0 (task wins the other direction).
        coincident_cr_write_task(x"00000040", '0', '1');      -- CPU writes bit6=1, task_stop=1
        bus_read(clk, pbus, read_data, RegSlotTIMxCR, rdw);
        sb.check_bit("G4e: coincident CPU write (bit6=1) + task_stop -> CR(6)=0 (task wins)",
                     to_X01(rdw(6)), '0');

        ------------------------------------------------------------------
        -- GROUP G5: discipline -- evt_compare0 flips on a match even with
        -- the compare0 interrupt ENABLE masked (producer taps are derived
        -- from the flags' SET conditions, never the post-mask IRQs).
        ------------------------------------------------------------------
        report "=== GROUP G5: evt_compare0 independent of the masked IRQ enable ===" severity note;
        reset_pulse;
        bus_write(clk, pbus, RegSlotTIMxCMP0, x"00000020");   -- compare0 = 32
        evt_mon_reset;
        bus_write(clk, pbus, RegSlotTIMxCR, x"00000140");     -- enable + src=01; bit0 (cmp0 IE) = 0 (masked)
        poll_val_counting(60, ok);
        sb.check_true("G5: TIMxVAL visibly counting (mux-release gotcha, bounded poll)", ok);

        wait_flips_ge(evt_cmp0_flips, 1, 80, ok);
        sb.check_true("G5a: evt_compare0 still flips on match with compare0_int_enable masked (bounded poll)", ok);
        sb.check_bit("G5b: irq_cmp0 stays 0 (post-mask IRQ, unlike the raw evt_compare0 tap)",
                     to_X01(irq_cmp0), '0');
        bus_read(clk, pbus, read_data, RegSlotTIMxSR, rdw);
        sb.check_bit("G5c: the raw compare0 flag (SR bit0) is set even though the IRQ is masked",
                     to_X01(rdw(0)), '1');
        bus_write(clk, pbus, RegSlotTIMxCR, x"00000000");     -- disable

        ------------------------------------------------------------------
        -- GROUP G-NEG: NEGATIVE CONTROL (mandatory, LAST) -- exactly ONE
        -- deliberately-wrong expected value so the scoreboard proves it can
        -- fail. Repeat a fresh compare0 flip and assert a wrong flip count.
        ------------------------------------------------------------------
        report "=== GROUP G-NEG: NEGATIVE CONTROL ===" severity note;
        reset_pulse;
        bus_write(clk, pbus, RegSlotTIMxCMP0, x"00000008");   -- compare0 = 8
        evt_mon_reset;
        bus_write(clk, pbus, RegSlotTIMxCR, x"00000140");     -- enable + src=01
        wait_flips_ge(evt_cmp0_flips, 1, 80, ok);
        bus_write(clk, pbus, RegSlotTIMxCR, x"00000000");     -- disable -- freeze
        sb.check_true("NEGATIVE CONTROL: wrong expected evt_compare0 flip count (must FAIL)",
                      ok and evt_cmp0_flips = 2);

        ------------------------------------------------------------------
        -- Final verdict: sb.errors must be EXACTLY 1 (the negative control).
        ------------------------------------------------------------------
        wait for 1 us;
        sb.report_summary("TIMER TB");

        if sb.errors = 1 then
            report LF & LF &
                "    ##################################################" & LF &
                "    ##   TIMER_TB PASS (1 expected negative-control failure)" & LF &
                "    ##   TIMER TB:  ALL CHECKS PASSED" & LF &
                "    ##################################################" & LF
                severity note;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   TIMER_TB FAIL (expected exactly 1 failure [negative control], got " &
                integer'image(sb.errors) & ")" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        tb_done <= true;
        stop;
        wait;
    end process stim_proc;

end architecture sim;
