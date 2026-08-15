-------------------------------------------------------------------------------
-- PWM_tb.vhd
-------------------------------------------------------------------------------
-- Standalone, self-checking testbench for the PWM buffered-PWM-generator peripheral (hdl/common/periph/PWM.vhd).
-- Written AGAINST THE FROZEN ENTITY AND REGISTER MAP (~/vesta_docs/digperiphs/pwm_design.md, D1-D21 plus orchestrator A1-A7) while the RTL was written in parallel.
-- The DUT is declared as a COMPONENT (not an entity instantiation) so this bench compiles standalone with xmvhdl before PWM.vhd exists; VHDL default binding resolves it to the entity of the same name once PWM.vhd is analyzed into the work library.
-- Mirrors RTC_tb.vhd's structure (I3C_tb discipline).
--
-- Uses the shared support packages tb/periph_tb_pkg.vhd (scoreboard plus register-bus BFM) and tb/pwm_bfm_pkg.vhd (PWM slot/CR/POL/SR constants, the pwm_mk_cr/pwm_mk_pol packers, the bounded SR polls pwm_wait_flag and pwm_wait_updf_clear, and the checker-independent measurement primitive pwm_wait_transition).
--
-- ONE clock family (design doc D1): `clk` (free-running MCLK engine reference) and `ClkMem` (gated bus clock) are driven from the SAME mclk net, exactly as at integration, and `ClkMem` just gates off while the bus is idle (the periph_tb_pkg BFM idiom: `ClkMem <= clk when b.en_mem = '0' else '0'`).
-- There is NO lfxt or second domain in this block (contrast RTC), so no CDC synchronizers are exercised here: every handoff the design doc describes (D2) is a same-clock-family toggle or level.
--
-- CHECKER INDEPENDENCE (mandatory): period and per-channel duty are measured by counting `clk` RISING edges between observed `pwm_out` transitions (pwm_bfm_pkg.pwm_wait_transition) and compared against values HAND-COMPUTED from the PER/DTY/PSC the bench itself programmed; the DUT's internal counter and comparators are never read.
--
-- GLITCH-FREEDOM MONITOR (HARD RULE, the G2 headline check): a CONTINUOUS background process (mon_proc below) tracks, per channel, the shortest completed high run and the shortest completed low run of pwm_out since the last mon_reset.
-- It is entirely independent of the directed stimulus sequencing, so a mid-period duty change that produces a runt pulse anywhere in a monitored window is caught even if the directed checks around it did not happen to be looking at that exact instant.
-- mon_reset is called before each window of interest, never inside the precise timing-critical portion of a check, to avoid perturbing the exact elapsed-edge counts the directed checks depend on.
-- A small "floor" slop (mon_min_* >= EXPECTED_MIN - 2, see MON_FLOOR_SLOP) absorbs the monitor's own 1-2 clk reset-to-alignment latency while staying far above any real runt (0-1 clk).
--
-- to_X01 normalizes every sampled DUT LEVEL (pwm_out(1:0), irq_fault, irq_evt, rdata_out) at its sample point.
-- Full reset-default word reads are compared RAW so an uninitialized X is caught.
--
-- COMPRESSED TIMING: PSC=0 throughout, PER in {0,7,15,31} (periods of 8-32 clk); G2 and G7 use the longer end of that range (PER=31, period=32) so that the several-clk cost of an interposed SR read or W1C is a small fraction of a period (pacing fix, see the G2/G7 header comments below).
-- The whole run is still well under 1 ms of sim time, far inside the 1-minute rule.
-- A top-level watchdog aborts with a FAIL banner if the stimulus ever hangs.
--
-- DEVIATIONS from the design doc's bench plan (flagged, not resolved; see the bench author's report):
--   * Between most groups the bench issues a `resetn` pulse before reprogramming, rather than relying on staged writes to settle across a stale non-degenerate active period.
--     This is NOT required by the design (D9's idempotent-every-boundary commit handles a live reprogram fine): it is a bench-side simplification chosen so every measured window starts from the well-understood "per_active=0 self-commits on the first psc_tick" reset corner (D10), keeping the exact elapsed-edge arithmetic simple and unambiguous.
--     G2 (the headline glitch-freedom check) deliberately does NOT reset between its setup and its mid-period writes: that is the whole point of the group.
--   * The continuous glitch monitor is windowed (mon_reset per window of interest) rather than free-running for the entire simulation, to keep the legitimate 1-tick degenerate-period pulses at G1/G4's PWMEN-enable instants (D10 period=0 corner) from polluting a single sim-wide floor check.
--     Each window's floor is still a genuine, DUT-internals-free, continuously-sampled independent check.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.periph_tb_pkg.all;
use work.pwm_bfm_pkg.all;

entity PWM_tb is
end entity PWM_tb;

architecture sim of PWM_tb is

    constant PERIOD : time := 20 ns;   -- clk / bus reference (free-running MCLK, D1)

    -- Floor slop for the continuous glitch monitor (see header): the monitor's own mon_reset-to-alignment latency, a couple of clk edges, can truncate the very first run recorded in a window.
    -- Subtracting this from an expected minimum keeps the floor check meaningful without false-failing on that harmless truncation.
    -- A real runt (0-1 clk) is still caught by a wide margin against any interval used in this bench (every intentional interval here is at least 3 clk).
    constant MON_FLOOR_SLOP : natural := 2;

    -- FROZEN DUT entity (design doc D3), declared as a component so the bench compiles standalone before hdl/common/periph/PWM.vhd exists.
    -- The EVFAB taps (event_fabric_spec.md 2026-07-24) are in the component too, so default binding sees the FULL entity port list; task_flttrig carries the same '0' default as the entity.
    component PWM is
        port (
            clk         : in  std_logic;
            resetn      : in  std_logic;
            irq_fault   : out std_logic;
            irq_evt     : out std_logic;
            pwm_out     : out std_logic_vector(1 downto 0);
            ClkMem      : in  std_logic;
            EnMemPeriph : in  std_logic;
            WEn         : in  std_logic_vector(3 downto 0);
            MABPart     : in  std_logic_vector(7 downto 2);
            wdata       : in  std_logic_vector(31 downto 0);
            rdata_out   : out std_logic_vector(31 downto 0);

            evt_period   : out std_logic;
            evt_fault    : out std_logic;
            task_flttrig : in  std_logic := '0'
        );
    end component;

    -- clocks / reset
    signal clk    : std_logic := '0';
    signal ClkMem : std_logic := '0';
    signal resetn : std_logic := '0';

    -- outputs / interrupts
    signal pwm_out   : std_logic_vector(1 downto 0);
    signal irq_fault : std_logic;
    signal irq_evt   : std_logic;

    -- register bus
    signal pbus      : periph_bus_t := PERIPH_BUS_IDLE;
    signal rdata_out : std_logic_vector(31 downto 0);

    -- ---- EVFAB taps (event_fabric_spec.md 2026-07-24, G-EV) ---------------
    signal evt_period   : std_logic;
    signal evt_fault    : std_logic;
    signal task_flttrig : std_logic := '0';   -- tb-driven, default '0'

    -- ---- continuous glitch-freedom monitor (checker independence) ---------
    -- Per-channel shortest-completed-run tracker, windowed via mon_reset.
    -- It NEVER reads a DUT internal: pwm_out is the only signal it samples.
    type nat_arr2 is array (0 to 1) of natural;
    signal mon_min_high : nat_arr2 := (others => natural'high);
    signal mon_min_low  : nat_arr2 := (others => natural'high);
    signal mon_run_high : nat_arr2 := (others => 0);
    signal mon_run_low  : nat_arr2 := (others => 0);
    signal mon_prev     : std_logic_vector(1 downto 0) := (others => '0');
    signal mon_clear    : std_logic := '0';

    -- ---- EVFAB pulse monitor (checker independence, G-EV) -----------------
    -- Continuous background tracker of BOTH tap ports (evt_period and evt_fault): it counts pulse STARTS (rising transitions) and total HIGH samples, both at `clk` rising edges, since the last evt_mon_clear pulse.
    -- Mirrors mon_proc above but for scalar comb taps rather than run length.
    -- A run of exactly N one-clk-wide pulses satisfies starts=N AND highs=N simultaneously: any wider pulse pushes highs above starts, and any missed pulse leaves starts short.
    -- It NEVER reads a DUT internal: only the exported evt_period and evt_fault ports.
    signal evt_period_starts, evt_period_highs : natural := 0;
    signal evt_fault_starts,  evt_fault_highs  : natural := 0;
    signal evt_period_prev, evt_fault_prev     : std_logic := '0';
    signal evt_mon_clear : std_logic := '0';

    signal tb_done : boolean := false;

    shared variable sb : scoreboard;

begin

    ----------------------------------------------------------------------------
    -- clock / gated register-bus clock (D1: same mclk net; periph_tb_pkg idiom)
    ----------------------------------------------------------------------------
    clk    <= not clk after PERIOD / 2;
    ClkMem <= clk when pbus.en_mem = '0' else '0';

    ----------------------------------------------------------------------------
    -- Continuous glitch-freedom monitor (see header).
    -- Tracks the shortest COMPLETED high run and low run per channel since the last mon_clear pulse, purely from the pwm_out port.
    ----------------------------------------------------------------------------
    mon_proc : process(clk)
        variable lvl : std_logic;
    begin
        if rising_edge(clk) then
            for ch in 0 to 1 loop
                lvl := to_X01(pwm_out(ch));
                if mon_clear = '1' then
                    mon_min_high(ch) <= natural'high;
                    mon_min_low(ch)  <= natural'high;
                    mon_run_high(ch) <= 0;
                    mon_run_low(ch)  <= 0;
                    mon_prev(ch)     <= lvl;
                elsif lvl = mon_prev(ch) then
                    if lvl = '1' then
                        mon_run_high(ch) <= mon_run_high(ch) + 1;
                    else
                        mon_run_low(ch) <= mon_run_low(ch) + 1;
                    end if;
                else
                    -- transition: close out the run that just ended
                    if mon_prev(ch) = '1' then
                        if mon_run_high(ch) < mon_min_high(ch) then
                            mon_min_high(ch) <= mon_run_high(ch);
                        end if;
                        mon_run_low(ch) <= 1;
                    else
                        if mon_run_low(ch) < mon_min_low(ch) then
                            mon_min_low(ch) <= mon_run_low(ch);
                        end if;
                        mon_run_high(ch) <= 1;
                    end if;
                    mon_prev(ch) <= lvl;
                end if;
            end loop;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- EVFAB pulse monitor (see the signal-declaration comment above): samples evt_period and evt_fault, to_X01-normalized, on every clk rising edge, windowed via evt_mon_clear the same way mon_proc is windowed via mon_clear.
    ----------------------------------------------------------------------------
    evt_mon_proc : process(clk)
        variable p_lvl, f_lvl : std_logic;
    begin
        if rising_edge(clk) then
            p_lvl := to_X01(evt_period);
            f_lvl := to_X01(evt_fault);
            if evt_mon_clear = '1' then
                evt_period_starts <= 0;
                evt_period_highs  <= 0;
                evt_fault_starts  <= 0;
                evt_fault_highs   <= 0;
                evt_period_prev   <= p_lvl;
                evt_fault_prev    <= f_lvl;
            else
                if p_lvl = '1' then
                    evt_period_highs <= evt_period_highs + 1;
                    if evt_period_prev /= '1' then
                        evt_period_starts <= evt_period_starts + 1;
                    end if;
                end if;
                if f_lvl = '1' then
                    evt_fault_highs <= evt_fault_highs + 1;
                    if evt_fault_prev /= '1' then
                        evt_fault_starts <= evt_fault_starts + 1;
                    end if;
                end if;
                evt_period_prev <= p_lvl;
                evt_fault_prev  <= f_lvl;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------------
    dut : component PWM
        port map (
            clk          => clk,
            resetn       => resetn,
            irq_fault    => irq_fault,
            irq_evt      => irq_evt,
            pwm_out      => pwm_out,
            ClkMem       => ClkMem,
            EnMemPeriph  => pbus.en_mem,
            WEn          => pbus.wen,
            MABPart      => pbus.addr_periph,
            wdata        => pbus.write_data,
            rdata_out    => rdata_out,
            evt_period   => evt_period,
            evt_fault    => evt_fault,
            task_flttrig => task_flttrig
        );

    ----------------------------------------------------------------------------
    -- Watchdog: abort with a FAIL banner if the stimulus ever hangs.
    -- Expected sim time is well under 1 ms, so this fires only on a true hang.
    ----------------------------------------------------------------------------
    watchdog : process
    begin
        wait for 20 ms;
        if not tb_done then
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   PWM_TB FAIL (WATCHDOG TIMEOUT -- stimulus never finished)" & LF &
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
        variable rdw, sw     : std_logic_vector(31 downto 0);
        variable ok, ok2     : boolean;
        variable e_a, e_b, e_c, e_d : natural;
        variable lvl_a, lvl_b, lvl_c, lvl_d : std_logic;
        variable hi, lo      : natural;

        -- Reset pulse: resetn low for a few PERIODs then back high.
        -- Leaves the bus idle and the monitor un-cleared; callers call mon_reset when they start a window of interest.
        procedure reset_pulse is
        begin
            resetn <= '0';
            pbus   <= PERIPH_BUS_IDLE;
            wait for 6 * PERIOD;
            wait for 1 ns;
            resetn <= '1';
            wait for 4 * PERIOD;
        end procedure;

        -- W1C the given SR mask, then do a dummy CR read to retire the gated-ClkMem write pulse before the next SR read (the RTC/NFC/QSPI idiom).
        procedure w1c(mask : std_logic_vector(31 downto 0)) is
            variable r : std_logic_vector(31 downto 0);
        begin
            bus_write(clk, pbus, PWM_SLOT_SR, mask);
            bus_read (clk, pbus, rdata_out, PWM_SLOT_CR, r);
        end procedure;

        -- Clear the continuous glitch monitor's accumulators; per the header, call this only OUTSIDE a timing-critical window.
        procedure mon_reset is
        begin
            wait until clk = '0';
            mon_clear <= '1';
            wait until clk = '1';
            wait until clk = '0';
            mon_clear <= '0';
        end procedure;

        -- ---- G-EV helpers (EVFAB taps) -------------------------------------

        -- Clear the evt_period/evt_fault pulse monitor's accumulators; see the signal-declaration comment, it mirrors mon_reset exactly.
        -- Call it only OUTSIDE a timing-critical window, the same discipline as mon_reset.
        procedure evt_mon_reset is
        begin
            wait until clk = '0';
            evt_mon_clear <= '1';
            wait until clk = '1';
            wait until clk = '0';
            evt_mon_clear <= '0';
        end procedure;

        -- Let exactly `n` clk RISING edges pass, then settle to the following falling edge before returning.
        -- A caller reading evt_period_* or evt_fault_* right after the call therefore never races the same-delta update of evt_mon_proc, which is a process concurrent with this one.
        procedure wait_edges(n : natural) is
        begin
            for i in 1 to n loop
                wait until clk = '1';
            end loop;
            wait until clk = '0';
        end procedure;

        -- Bounded wait for evt_period to sample '1' on a clk rising edge, used once to absorb the D10 degenerate first-enable boundary before G-EV-a opens its exact-count window.
        -- It never reads a DUT internal, only the exported evt_period port, referenced directly like every other local procedure in this bench (clk and pwm_out above).
        procedure wait_for_evt_period_high(guard : natural; ok : out boolean) is
            variable g : natural := 0;
        begin
            ok := false;
            loop
                wait until clk = '1';
                if to_X01(evt_period) = '1' then
                    ok := true;
                    exit;
                end if;
                g := g + 1;
                exit when g > guard;   -- bounded (never hangs)
            end loop;
        end procedure;

        -- Drive task_flttrig high across EXACTLY one clk rising edge, the same held-across-one-edge idiom as the mon_clear pulse in mon_reset and evt_mon_reset, then drop it back to '0'.
        procedure pulse_task_flttrig is
        begin
            wait until clk = '0';
            task_flttrig <= '1';
            wait until clk = '1';
            wait until clk = '0';
            task_flttrig <= '0';
        end procedure;

        -- Stage PER, DTY0 and DTY1 (the buffered waveform words, D9).
        -- Safe to call at any time; the staged values take effect at the next period boundary once PWMEN=1.
        procedure stage_waveform(per, dty0, dty1 : natural) is
        begin
            bus_write(clk, pbus, PWM_SLOT_PER,  std_logic_vector(to_unsigned(per,  32)));
            bus_write(clk, pbus, PWM_SLOT_DTY0, std_logic_vector(to_unsigned(dty0, 32)));
            bus_write(clk, pbus, PWM_SLOT_DTY1, std_logic_vector(to_unsigned(dty1, 32)));
        end procedure;

        -- Sync to the next RISING edge of pwm_out(ch), discarding any falling edge seen first.
        -- Bounded, since each pwm_wait_transition call is internally guarded, and it gives up with ok=false after a few tries.
        procedure sync_rising(ch : natural range 0 to 1; ok : out boolean) is
            variable e   : natural;
            variable lvl : std_logic;
            variable tries : natural := 0;
        begin
            ok := false;
            loop
                pwm_wait_transition(clk, pwm_out, ch, e, lvl, ok2);
                if not ok2 then
                    exit;   -- no transition at all within the guard, so give up
                end if;
                if lvl = '1' then
                    ok := true;
                    exit;
                end if;
                tries := tries + 1;
                exit when tries > 4;
            end loop;
        end procedure;

        -- Measure one full high-plus-low cycle starting from the NEXT rising edge of pwm_out(ch).
        -- Returns the high-run length and the following low-run length, both in clk edges, and stays checker-independent because it only watches pwm_out.
        procedure measure_cycle(ch : natural range 0 to 1;
                                hi_len, lo_len : out natural;
                                ok : out boolean) is
            variable e   : natural;
            variable lvl : std_logic;
            variable ok1, ok3 : boolean;
        begin
            sync_rising(ch, ok1);
            if not ok1 then
                hi_len := 0; lo_len := 0; ok := false; return;
            end if;
            pwm_wait_transition(clk, pwm_out, ch, hi_len, lvl, ok2);   -- expect falling
            pwm_wait_transition(clk, pwm_out, ch, lo_len, lvl, ok3);   -- expect rising
            ok := ok1 and ok2 and ok3;
        end procedure;

        -- Confirm pwm_out(ch) stays at a constant level for `window` clk edges, used for the D10 duty=0 and duty>=PER+1 constant corners and for the safe-level checks.
        -- Never reads a DUT internal.
        procedure expect_constant(ch : natural range 0 to 1; window : natural;
                                  lvl_out : out std_logic; ok : out boolean) is
            variable lvl0 : std_logic;
        begin
            lvl0 := to_X01(pwm_out(ch));
            ok := true;
            for i in 1 to window loop
                wait until clk = '1';
                if to_X01(pwm_out(ch)) /= lvl0 then
                    ok := false;
                end if;
            end loop;
            lvl_out := lvl0;
        end procedure;

        -- G8 helper: arm PWMEN, CH0EN, CH1EN and FLTEN with the given IE bits, wait for a fresh PEVF, trip FLTTRIG (an explicit-act write, then a restoring write with FLTTRIG=0), wait for FLTF, then FREEZE the engine (PWMEN=0, the RTC make_both_pending precedent) so neither flag re-arms while the caller exercises the W1C and mask checks.
        -- It does not itself check pass or fail: the caller reads SR and the irqs afterward.
        procedure arm_and_freeze(fltie, pevie : std_logic) is
            variable ok_local : boolean;
        begin
            bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', pevie, fltie, '1', '0', "0000"));
            pwm_wait_flag(clk, pbus, rdata_out, PWM_SR_PEVF, '1', ok_local);
            bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', pevie, fltie, '1', '1', "0000"));
            bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', pevie, fltie, '1', '0', "0000"));
            pwm_wait_flag(clk, pbus, rdata_out, PWM_SR_FLTF, '1', ok_local);
            bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('0', '0', '0', pevie, fltie, '1', '0', "0000"));
            wait for 2 * PERIOD;
        end procedure;

    begin
        ------------------------------------------------------------------
        -- Reset (resetn low for a few PERIODs at t=0)
        ------------------------------------------------------------------
        reset_pulse;

        ------------------------------------------------------------------
        -- GROUP G0: reset defaults (design doc G0)
        ------------------------------------------------------------------
        report "=== GROUP G0: reset defaults ===" severity note;
        bus_read(clk, pbus, rdata_out, PWM_SLOT_CR, rdw);
        sb.check_slv("G0: CR resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, PWM_SLOT_PER, rdw);
        sb.check_slv("G0: PER resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, PWM_SLOT_DTY0, rdw);
        sb.check_slv("G0: DTY0 resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, PWM_SLOT_DTY1, rdw);
        sb.check_slv("G0: DTY1 resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, PWM_SLOT_DTY2, rdw);
        sb.check_slv("G0: DTY2 (reserved) reads 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, PWM_SLOT_DTY3, rdw);
        sb.check_slv("G0: DTY3 (reserved) reads 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, PWM_SLOT_POL, rdw);
        sb.check_slv("G0: POL resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, PWM_SLOT_DT, rdw);
        sb.check_slv("G0: DT (reserved) reads 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, PWM_SLOT_SR, rdw);
        sb.check_slv("G0: SR resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, 9, rdw);
        sb.check_slv("G0: slot 9 reads 0", rdw, x"00000000");
        sb.check_bit("G0: pwm_out(0) = 0 (safe/low) out of reset", to_X01(pwm_out(0)), '0');
        sb.check_bit("G0: pwm_out(1) = 0 (safe/low) out of reset", to_X01(pwm_out(1)), '0');
        sb.check_bit("G0: irq_fault = 0 out of reset", to_X01(irq_fault), '0');
        sb.check_bit("G0: irq_evt = 0 out of reset", to_X01(irq_evt), '0');

        ------------------------------------------------------------------
        -- GROUP G1: basic PWM shape, measured (design doc G1)
        -- Two settings (PSC=0 and PSC=1) separated by a fresh resetn pulse, so each starts from the D10 "per_active=0 self-commits on the first psc_tick" corner: a clean, unambiguous settle (see the header deviation note).
        ------------------------------------------------------------------
        report "=== GROUP G1: basic PWM shape (measured) ===" severity note;

        -- Setting A: PSC=0 (/1), PER=15 (period=16 clks), DTY0=4, DTY1=8.
        stage_waveform(15, 4, 8);
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '0', '0', '0', "0000"));
        measure_cycle(0, hi, lo, ok);
        sb.check_true("G1a: CH0 measured (rising/falling/rising all observed)", ok);
        sb.check_true("G1a: CH0 measured duty = DTY0*2^PSC = 4", hi = 4);
        sb.check_true("G1a: CH0 measured period = (PER+1)*2^PSC = 16", hi + lo = 16);
        measure_cycle(1, hi, lo, ok);
        sb.check_true("G1a: CH1 measured (rising/falling/rising all observed)", ok);
        sb.check_true("G1a: CH1 measured duty = DTY1*2^PSC = 8", hi = 8);
        sb.check_true("G1a: CH1 measured period = (PER+1)*2^PSC = 16", hi + lo = 16);

        -- Setting B: PSC=1 (divide by 2), PER=7 (period=(7+1)*2=16 clks), DTY0=3 (=6 clks), DTY1=5 (=10 clks).
        -- Exercises the 2^PSC scaling directly in clk-edge counts: pwm_wait_transition counts clk edges, not psc_ticks, so the PSC divide shows up arithmetically here.
        reset_pulse;
        stage_waveform(7, 3, 5);
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '0', '0', '0', "0001"));
        measure_cycle(0, hi, lo, ok);
        sb.check_true("G1b: CH0 measured (PSC=1)", ok);
        sb.check_true("G1b: CH0 measured duty = DTY0*2^PSC = 6", hi = 6);
        sb.check_true("G1b: CH0 measured period = (PER+1)*2^PSC = 16", hi + lo = 16);
        measure_cycle(1, hi, lo, ok);
        sb.check_true("G1b: CH1 measured (PSC=1)", ok);
        sb.check_true("G1b: CH1 measured duty = DTY1*2^PSC = 10", hi = 10);
        sb.check_true("G1b: CH1 measured period = (PER+1)*2^PSC = 16", hi + lo = 16);

        ------------------------------------------------------------------
        -- GROUP G2: buffered-update glitch-freedom (design doc G2, the HEADLINE check).
        -- Deliberately NO reset before Leg A: take a fresh reset out of G1b's PSC=1 setting, re-settle to PSC=0, PER=31 (period=32), DTY0=12, DTY1=16, then run the mid-period-change legs WHILE the engine keeps running, which is the whole point of the group.
        --
        -- PACING (fixed after the first full run against the RTL; see the bench author's report, and note the rule: only the edge/phase model and pacing change, no exact-count check is loosened):
        --   * bus_write, called EXACTLY at a synced rising-edge instant, deterministically costs ONE extra clk edge before its capture (periph_tb_pkg's wait-until-clk='0'/'1'/'0' handshake: from a rising-edge start it waits a half period to the next falling edge, then a further full period to the capture rising edge).
        --     So a write issued immediately after sync_rising (at true cnt=0) is captured at true cnt=1, and a pwm_wait_transition chained IMMEDIATELY after it, with nothing else interposed, starts measuring from cnt=1: hence "OLD_DTY - 1" below.
        --   * The original run interposed an SR bus_read (the UPDF=1 check) BETWEEN the write and the interval measurement, and that read alone costs about 2 more clk edges, which with the old DTY0=4 overran the remaining 1-tick margin to the fall.
        --     The measurement then started AFTER the real transition had already happened and caught the NEXT, wrong-polarity edge instead.
        --     Fix: the exact-count chain (e_a to e_d below) now runs with NOTHING interposed between the sync/write and the four transition catches, and UPDF's set and absorb behavior is proven separately by a bounded poll (Leg A'), which is timing-INSENSITIVE by construction rather than relying on a fixed tick budget.
        ------------------------------------------------------------------
        report "=== GROUP G2: buffered-update glitch-freedom ===" severity note;
        reset_pulse;
        stage_waveform(31, 12, 16);
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '0', '0', '0', "0000"));
        measure_cycle(0, hi, lo, ok);   -- let the shape settle once, discard
        sb.check_true("G2 setup: CH0 settled to the baseline shape", ok and hi = 12 and hi + lo = 32);

        -- Leg A: mid-period DTY0 write (12 becomes 24), exact chain, nothing interposed.
        -- mon_reset happens BEFORE the sync-to-boundary loop, never inside the timing-critical window that follows (see header).
        mon_reset;
        sync_rising(0, ok);
        sb.check_true("G2a: synced to a CH0 period boundary", ok);
        bus_write(clk, pbus, PWM_SLOT_DTY0, x"00000018"); -- stage DTY0 = 24 (buffered, D9), captured at true cnt=1 (see header)
        pwm_wait_transition(clk, pwm_out, 0, e_a, lvl_a, ok);       -- expect falling
        sb.check_true("G2a: (a) interval straddling the write observed", ok);
        sb.check_bit("G2a: (a) it is a falling edge", lvl_a, '0');
        sb.check_true("G2a: (a) straddling interval = OLD duty EXACTLY (write captured at " &
                      "cnt=1, so 1+e = 12, no runt)", 1 + e_a = 12);

        pwm_wait_transition(clk, pwm_out, 0, e_b, lvl_b, ok);       -- expect rising (next boundary)
        sb.check_true("G2a: boundary-rising edge observed", ok);
        sb.check_bit("G2a: it is a rising edge", lvl_b, '1');
        sb.check_true("G2a: old period length UNCHANGED up to this boundary (low = PERIOD-OLD_DTY = 20)",
                      e_b = 20);

        pwm_wait_transition(clk, pwm_out, 0, e_c, lvl_c, ok);       -- expect falling at NEW duty
        sb.check_true("G2a: post-boundary falling edge observed", ok);
        sb.check_bit("G2a: it is a falling edge", lvl_c, '0');
        sb.check_true("G2a: (b) first interval reflecting NEW duty begins at the boundary (=24, not before)",
                      e_c = 24);

        pwm_wait_transition(clk, pwm_out, 0, e_d, lvl_d, ok);       -- expect rising (settled new period)
        sb.check_true("G2a: settled-period rising edge observed", ok);
        sb.check_true("G2a: settled low = PERIOD-NEW_DTY = 8 (period itself unaffected)", e_d = 8);

        sb.check_true("G2a: glitch monitor CH0 min-high floor (no runt, expect>=11-2)",
                      mon_min_high(0) >= 11 - MON_FLOOR_SLOP);
        sb.check_true("G2a: glitch monitor CH0 min-low floor (no runt, expect>=8-2)",
                      mon_min_low(0) >= 8 - MON_FLOOR_SLOP);

        -- Leg A': UPDF set and absorb timing (design doc (c)), proven with a BOUNDED POLL (pwm_wait_updf_clear) rather than a fixed-tick interposed read, so it is robust to however many clk the SR reads themselves cost (see the pacing note above).
        sync_rising(0, ok);
        sb.check_true("G2a-prime: synced to a CH0 period boundary", ok);
        bus_read(clk, pbus, rdata_out, PWM_SLOT_SR, sw);
        sb.check_bit("G2a-prime: UPDF clear with no pending write", to_X01(sw(PWM_SR_UPDF)), '0');
        bus_write(clk, pbus, PWM_SLOT_DTY0, x"00000012");   -- stage DTY0 = 18 (buffered, D9)
        bus_read(clk, pbus, rdata_out, PWM_SLOT_SR, sw);
        sb.check_bit("G2a-prime: UPDF set immediately after the buffered write", to_X01(sw(PWM_SR_UPDF)), '1');
        pwm_wait_updf_clear(clk, pbus, rdata_out, ok);
        sb.check_true("G2a-prime: (c) UPDF clears once the boundary absorbs the write (bounded poll)", ok);

        -- Leg B: fresh setup (PER=31 for period=32, DTY0=12 as in Leg A's baseline), then a mid-period PER write, i.e. a frequency change from 32 to 48.
        -- It must land only at the boundary (design doc G2, "repeat changing PER"), under the same exact-chain-with-nothing-interposed discipline as Leg A.
        reset_pulse;
        stage_waveform(31, 12, 16);
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '0', '0', '0', "0000"));
        measure_cycle(0, hi, lo, ok);
        sb.check_true("G2b setup: CH0 settled to the baseline shape", ok and hi = 12 and hi + lo = 32);

        mon_reset;
        sync_rising(0, ok);
        sb.check_true("G2b: synced to a CH0 period boundary", ok);
        bus_write(clk, pbus, PWM_SLOT_PER, x"0000002F"); -- stage PER = 47 (new period = 48), captured at true cnt=1 (see header)
        pwm_wait_transition(clk, pwm_out, 0, e_a, lvl_a, ok);       -- expect falling, duty unaffected
        sb.check_true("G2b: straddling falling edge observed", ok);
        sb.check_true("G2b: duty UNCHANGED by a PER-only write (write captured at cnt=1, " &
                      "so 1+e = DTY0 = 12)", 1 + e_a = 12);

        pwm_wait_transition(clk, pwm_out, 0, e_b, lvl_b, ok);       -- expect rising, OLD period still governs
        sb.check_true("G2b: boundary-rising edge observed", ok);
        sb.check_true("G2b: OLD period (32) still governs this boundary (low = 32-12 = 20)", e_b = 20);

        pwm_wait_transition(clk, pwm_out, 0, e_c, lvl_c, ok);       -- expect falling, still DTY0=12
        sb.check_true("G2b: post-boundary falling edge observed", ok);
        sb.check_true("G2b: duty still 12 (untouched)", e_c = 12);

        pwm_wait_transition(clk, pwm_out, 0, e_d, lvl_d, ok);       -- expect rising, NEW period=48
        sb.check_true("G2b: settled-period rising edge observed", ok);
        sb.check_true("G2b: new period now governs (low = NEW_PERIOD-DTY0 = 48-12 = 36)", e_d = 36);

        sb.check_true("G2b: glitch monitor CH0 min-high floor (no runt, expect>=11-2)",
                      mon_min_high(0) >= 11 - MON_FLOOR_SLOP);
        sb.check_true("G2b: glitch monitor CH0 min-low floor (no runt, expect>=20-2)",
                      mon_min_low(0) >= 20 - MON_FLOOR_SLOP);

        -- Leg B': UPDF set and absorb timing for a PER-only write, the same bounded-poll discipline as Leg A'.
        sync_rising(0, ok);
        sb.check_true("G2b-prime: synced to a CH0 period boundary", ok);
        bus_write(clk, pbus, PWM_SLOT_PER, x"00000037");   -- stage PER = 55 (new period = 56)
        bus_read(clk, pbus, rdata_out, PWM_SLOT_SR, sw);
        sb.check_bit("G2b-prime: UPDF set immediately after the buffered PER write", to_X01(sw(PWM_SR_UPDF)), '1');
        pwm_wait_updf_clear(clk, pbus, rdata_out, ok);
        sb.check_true("G2b-prime: UPDF clears once the boundary absorbs the PER write (bounded poll)", ok);

        ------------------------------------------------------------------
        -- GROUP G3: polarity (design doc G3)
        -- POL0=1 inverts CH0 while POL1=0 leaves CH1 unchanged.
        -- The measured pin level during the "active" window flips, so CH0's LOW run now equals the duty instead of its HIGH run, while the active-tick COUNT (DTY0=4, the same value G1a measured as CH0's HIGH run) is unchanged.
        ------------------------------------------------------------------
        report "=== GROUP G3: polarity ===" severity note;
        reset_pulse;
        stage_waveform(15, 4, 8);
        bus_write(clk, pbus, PWM_SLOT_POL, pwm_mk_pol('1', '0', '0', '0'));
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '0', '0', '0', "0000"));

        measure_cycle(0, hi, lo, ok);
        sb.check_true("G3: CH0 (POL0=1) measured", ok);
        sb.check_true("G3: CH0 physical HIGH run = PERIOD-DTY0 = 12 (inactive level, pol=1)", hi = 12);
        sb.check_true("G3: CH0 physical LOW run = DTY0 = 4 (active-tick count UNCHANGED vs G1a's hi=4)",
                      lo = 4);
        sb.check_true("G3: CH0 period unaffected by polarity", hi + lo = 16);

        measure_cycle(1, hi, lo, ok);
        sb.check_true("G3: CH1 (POL1=0, unchanged) measured", ok);
        sb.check_true("G3: CH1 duty unaffected (=DTY1=8)", hi = 8);
        sb.check_true("G3: CH1 period unaffected (=16)", hi + lo = 16);

        ------------------------------------------------------------------
        -- GROUP G4: corner cases (design doc G4, D10)
        ------------------------------------------------------------------
        report "=== GROUP G4: corner cases (D10) ===" severity note;

        -- duty=0 gives a constant inactive level, duty>=PER+1 a constant active level.
        reset_pulse;
        stage_waveform(15, 0, 20);   -- PER=15 (period 16): DTY0=0, DTY1=20 (>= PER+1=16)
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '0', '0', '0', "0000"));
        wait for 20 * PERIOD;        -- let the engine pass the initial degenerate commit tick

        expect_constant(0, 40, lvl_a, ok);
        sb.check_true("G4a: CH0 (duty=0) never transitions over 40 clks (constant)", ok);
        sb.check_bit("G4a: CH0 (duty=0) constant level = pol0 = 0 (inactive)", lvl_a, '0');

        expect_constant(1, 40, lvl_b, ok);
        sb.check_true("G4a: CH1 (duty>=PER+1) never transitions over 40 clks (constant)", ok);
        sb.check_bit("G4a: CH1 (duty>=PER+1) constant level = 1 (active)", lvl_b, '1');

        -- period=0: per_active=0 makes every psc_tick a boundary.
        -- DTY0=0 holds CH0 constant inactive, and DTY1=1 (at least per_active+1=1) holds CH1 constant active.
        -- PEVF pulses every tick (bounded observation, recurring).
        reset_pulse;
        stage_waveform(0, 0, 1);     -- PER=0, DTY0=0, DTY1=1
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '1', '0', '0', '0', "0000")); -- + PEVIE

        expect_constant(0, 30, lvl_a, ok);
        sb.check_true("G4b: CH0 (period=0, duty=0) constant over 30 clks", ok);
        sb.check_bit("G4b: CH0 constant level = 0", lvl_a, '0');
        expect_constant(1, 30, lvl_b, ok);
        sb.check_true("G4b: CH1 (period=0, duty>=1) constant over 30 clks", ok);
        sb.check_bit("G4b: CH1 constant level = 1", lvl_b, '1');

        pwm_wait_flag(clk, pbus, rdata_out, PWM_SR_PEVF, '1', ok);
        sb.check_true("G4b: PEVF sets (bounded wait, period=0 fires every psc_tick)", ok);
        w1c(x"00000002");   -- W1C PEVF
        pwm_wait_flag(clk, pbus, rdata_out, PWM_SR_PEVF, '1', ok);
        sb.check_true("G4b: PEVF re-fires almost immediately (recurring, every tick)", ok);
        w1c(x"00000002");

        ------------------------------------------------------------------
        -- GROUP G5: enable/disable safe level (design doc G5, D11)
        -- POL0=0 with SAFE0=1, and POL1=1 with SAFE1=0, are chosen so SAFE differs from the derived inactive-per-polarity value, which would be pol0=0 and pol1=1 respectively.
        -- That makes this the decisive test that SAFE is an ABSOLUTE field (A1), not a polarity-derived level.
        ------------------------------------------------------------------
        report "=== GROUP G5: enable/disable safe level (D11 absolute) ===" severity note;
        reset_pulse;
        stage_waveform(15, 4, 8);
        bus_write(clk, pbus, PWM_SLOT_POL, pwm_mk_pol('0', '1', '1', '0'));  -- SAFE0=1, SAFE1=0

        -- CH0EN=0: CH0 forced safe, CH1 (enabled) unaffected.
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '0', '1', '0', '0', '0', '0', "0000"));
        expect_constant(0, 30, lvl_a, ok);
        sb.check_true("G5a: CH0 (CH0EN=0) constant safe over 30 clks", ok);
        sb.check_bit("G5a: CH0 forced to SAFE0=1 (absolute, differs from derived pol0=0)", lvl_a, '1');
        measure_cycle(1, hi, lo, ok);
        sb.check_true("G5a: CH1 (CH1EN=1) unaffected, still running", ok);
        sb.check_true("G5a: CH1 physical HIGH = PERIOD-DTY1 = 8 (pol1=1 inverted)", hi = 8);
        sb.check_true("G5a: CH1 physical LOW = DTY1 = 8", lo = 8);

        -- CH0EN=1: CH0 resumes tracking the waveform.
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '0', '0', '0', "0000"));
        measure_cycle(0, hi, lo, ok);
        sb.check_true("G5b: CH0EN=1 -> CH0 resumes running (measured)", ok);
        sb.check_true("G5b: CH0 duty = DTY0 = 4 (pol0=0)", hi = 4);

        -- PWMEN=0: BOTH channels forced to their SAFE levels.
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('0', '1', '1', '0', '0', '0', '0', "0000"));
        expect_constant(0, 20, lvl_a, ok);
        sb.check_true("G5c: CH0 (PWMEN=0) constant safe", ok);
        sb.check_bit("G5c: CH0 = SAFE0 = 1", lvl_a, '1');
        expect_constant(1, 20, lvl_b, ok);
        sb.check_true("G5c: CH1 (PWMEN=0) constant safe", ok);
        sb.check_bit("G5c: CH1 = SAFE1 = 0", lvl_b, '0');

        -- Reprogram SAFE0 and SAFE1 while still disabled: the driven ABSOLUTE level follows immediately, since POL is not buffered (D11).
        bus_write(clk, pbus, PWM_SLOT_POL, pwm_mk_pol('0', '1', '0', '1'));  -- SAFE0=0, SAFE1=1
        expect_constant(0, 20, lvl_a, ok);
        sb.check_true("G5d: CH0 tracks reprogrammed SAFE0 (still PWMEN=0)", ok);
        sb.check_bit("G5d: CH0 now = SAFE0 = 0", lvl_a, '0');
        expect_constant(1, 20, lvl_b, ok);
        sb.check_true("G5d: CH1 tracks reprogrammed SAFE1", ok);
        sb.check_bit("G5d: CH1 now = SAFE1 = 1", lvl_b, '1');

        ------------------------------------------------------------------
        -- GROUP G6: fault (design doc G6, D12/A2/A3)
        ------------------------------------------------------------------
        report "=== GROUP G6: fault ===" severity note;
        reset_pulse;
        stage_waveform(15, 4, 8);
        bus_write(clk, pbus, PWM_SLOT_POL, pwm_mk_pol('0', '0', '1', '0'));  -- SAFE0=1, SAFE1=0
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '1', '1', '0', "0000")); -- +FLTIE+FLTEN
        measure_cycle(0, hi, lo, ok);
        sb.check_true("G6 setup: CH0 running baseline before fault", ok and hi = 4);

        -- FLTTRIG: write 1 as an explicit act, then a restoring write with FLTTRIG=0 (A2: writes are explicit acts and there are no read side effects).
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '1', '1', '1', "0000"));
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '1', '1', '0', "0000"));

        pwm_wait_flag(clk, pbus, rdata_out, PWM_SR_FLTF, '1', ok);
        sb.check_true("G6a: FLTF sets after FLTTRIG (FLTEN=1)", ok);
        sb.check_bit("G6a: pwm_out(0) forced to SAFE0=1 (same-cycle override, D12)", to_X01(pwm_out(0)), '1');
        sb.check_bit("G6a: pwm_out(1) forced to SAFE1=0", to_X01(pwm_out(1)), '0');
        wait for 2 * PERIOD;
        sb.check_bit("G6a: irq_fault asserted (FLTF & FLTIE)", to_X01(irq_fault), '1');

        -- W1C and re-arm: the output resumes tracking the STILL-RUNNING comparator (A3: the counter runs during a fault).
        w1c(x"00000001");
        bus_read(clk, pbus, rdata_out, PWM_SLOT_SR, rdw);
        sb.check_bit("G6b: FLTF cleared after W1C", to_X01(rdw(PWM_SR_FLTF)), '0');
        wait for 2 * PERIOD;
        sb.check_bit("G6b: irq_fault dropped after FLTF W1C", to_X01(irq_fault), '0');
        measure_cycle(0, hi, lo, ok);
        sb.check_true("G6b: CH0 resumes tracking the running comparator (measured)", ok);
        sb.check_true("G6b: CH0 duty back to DTY0=4 (phase-continuous, counter never stopped)", hi = 4);

        -- With FLTEN=0 the FLTTRIG write is ignored: no trip and no safe-force.
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '1', '0', '0', "0000")); -- FLTEN=0
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '1', '0', '1', "0000")); -- FLTTRIG=1
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '1', '0', '0', "0000")); -- restore
        pwm_wait_flag(clk, pbus, rdata_out, PWM_SR_FLTF, '1', ok);
        sb.check_true("G6c: FLTEN=0 -> FLTTRIG ignored (FLTF never sets, bounded wait)", not ok);
        measure_cycle(0, hi, lo, ok);
        sb.check_true("G6c: CH0 still running normally (no safe force)", ok);
        sb.check_true("G6c: CH0 duty still DTY0=4", hi = 4);

        ------------------------------------------------------------------
        -- GROUP G7: period event (design doc G7, D13)
        --
        -- PACING (fixed after the first full run against the RTL; see the bench author's report): the original PER=7 (period=8) was too short relative to the several clk each PEVF SR read plus W1C costs.
        -- Worse, the loop re-used pwm_wait_transition's CHAIN CONTINUITY across those interposed bus ops without re-syncing, so any drift they introduced silently shifted which edge the NEXT iteration's cadence pair was chasing: for a D-tick drift the e_a+e_b sum measures period minus D, not the true period, an aliasing artifact rather than a DUT defect.
        -- Fix: (1) a much longer period so the bus-op cost is a small fraction of it, AND (2) a re-sync via sync_rising at the top of every loop iteration, which is self-correcting regardless of how many clk the previous iteration's SR read and W1C consumed.
        -- No exact-count check is loosened, only the re-synchronization discipline changes.
        ------------------------------------------------------------------
        report "=== GROUP G7: period event ===" severity note;
        reset_pulse;
        stage_waveform(31, 10, 16);   -- PER=31 (period=32), DTY0=10, DTY1=16
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '1', '0', '0', '0', "0000")); -- +PEVIE
        sync_rising(0, ok);
        sb.check_true("G7 setup: synced to a CH0 boundary", ok);
        w1c(x"00000002");   -- clear any stale PEVF caught by the sync

        for i in 0 to 2 loop
            sync_rising(0, ok);   -- re-sync every iteration (pacing fix, see header)
            sb.check_true("G7: re-synced to a CH0 boundary", ok);
            pwm_wait_transition(clk, pwm_out, 0, e_a, lvl_a, ok);   -- falling (duty)
            sb.check_true("G7: falling edge observed", ok);
            pwm_wait_transition(clk, pwm_out, 0, e_b, lvl_b, ok);   -- rising (boundary)
            sb.check_true("G7: boundary rising edge observed", ok);
            sb.check_true("G7: cadence matches measured period ((PER+1)*2^PSC = 32)", e_a + e_b = 32);
            bus_read(clk, pbus, rdata_out, PWM_SLOT_SR, rdw);
            sb.check_bit("G7: PEVF set at this boundary", to_X01(rdw(PWM_SR_PEVF)), '1');
            if i = 0 then
                wait for 2 * PERIOD;
                sb.check_bit("G7: irq_evt asserted (PEVF & PEVIE)", to_X01(irq_evt), '1');
            end if;
            w1c(x"00000002");   -- W1C PEVF, which drops irq_evt
        end loop;

        -- Freeze the engine before the final irq-low check (pacing fix): the last W1C above legitimately leaves the engine free-running, and the NEXT boundary would re-pend PEVF and re-assert irq_evt before this check could possibly observe it low.
        -- That is correct DUT behavior, since PEVF re-arms every boundary, so the fix is to stop new boundaries from occurring while we check rather than to weaken the check.
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('0', '1', '1', '1', '0', '0', '0', "0000"));
        wait for 2 * PERIOD;
        sb.check_bit("G7: irq_evt dropped after the last W1C (engine frozen, no re-arm)", to_X01(irq_evt), '0');

        -- PEVIE=0 suppresses irq_evt while the flag still sets; re-enable the engine first.
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '0', '0', '0', "0000"));
        pwm_wait_flag(clk, pbus, rdata_out, PWM_SR_PEVF, '1', ok);
        sb.check_true("G7: PEVF still sets with PEVIE=0 (flag independent of IE)", ok);
        wait for 2 * PERIOD;
        sb.check_bit("G7: irq_evt suppressed by PEVIE=0", to_X01(irq_evt), '0');
        w1c(x"00000002");

        -- The PWM shape at the pins is unaffected by clearing PEVF.
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '0', '0', '0', "0000"));
        measure_cycle(0, hi, lo, ok);
        sb.check_true("G7: CH0 shape unaffected by PEVF clears (measured)", ok);
        sb.check_true("G7: CH0 duty still DTY0=10", hi = 10);
        sb.check_true("G7: CH0 period still 32", hi + lo = 32);

        ------------------------------------------------------------------
        -- GROUP G8: combined-IRQ demux/masking (design doc G8, D18)
        ------------------------------------------------------------------
        report "=== GROUP G8: combined-IRQ demux/masking ===" severity note;
        reset_pulse;
        stage_waveform(7, 3, 4);

        -- Both flags pending: both irqs go high.
        arm_and_freeze('1', '1');   -- FLTIE=1, PEVIE=1
        bus_read(clk, pbus, rdata_out, PWM_SLOT_SR, rdw);
        sb.check_bit("G8a: FLTF pending", to_X01(rdw(PWM_SR_FLTF)), '1');
        sb.check_bit("G8a: PEVF pending", to_X01(rdw(PWM_SR_PEVF)), '1');
        sb.check_bit("G8a: irq_fault high with FLTF & FLTIE", to_X01(irq_fault), '1');
        sb.check_bit("G8a: irq_evt high with PEVF & PEVIE", to_X01(irq_evt), '1');

        -- W1C each flag in turn: each drops only its own irq.
        w1c(x"00000001");   -- W1C FLTF only
        bus_read(clk, pbus, rdata_out, PWM_SLOT_SR, rdw);
        sb.check_bit("G8b: FLTF cleared, PEVF still pending", to_X01(rdw(PWM_SR_PEVF)), '1');
        sb.check_bit("G8b: irq_fault dropped", to_X01(irq_fault), '0');
        sb.check_bit("G8b: irq_evt still high (PEVF & PEVIE)", to_X01(irq_evt), '1');
        w1c(x"00000002");   -- W1C PEVF
        bus_read(clk, pbus, rdata_out, PWM_SLOT_SR, rdw);
        sb.check_slv("G8b: SR fully clear", rdw(3 downto 0), "0000");
        sb.check_bit("G8b: irq_evt dropped once both cleared", to_X01(irq_evt), '0');

        -- FLTIE=0 with PEVIE=1: irq_fault is masked despite FLTF pending.
        arm_and_freeze('0', '1');
        bus_read(clk, pbus, rdata_out, PWM_SLOT_SR, rdw);
        sb.check_bit("G8c: FLTF pending", to_X01(rdw(PWM_SR_FLTF)), '1');
        sb.check_bit("G8c: PEVF pending", to_X01(rdw(PWM_SR_PEVF)), '1');
        sb.check_bit("G8c: irq_fault masked (FLTIE=0) despite FLTF=1", to_X01(irq_fault), '0');
        sb.check_bit("G8c: irq_evt = PEVF & PEVIE = 1", to_X01(irq_evt), '1');
        w1c(x"00000003");

        -- FLTIE=1 with PEVIE=0: irq_evt is masked despite PEVF pending.
        arm_and_freeze('1', '0');
        bus_read(clk, pbus, rdata_out, PWM_SLOT_SR, rdw);
        sb.check_bit("G8d: FLTF pending", to_X01(rdw(PWM_SR_FLTF)), '1');
        sb.check_bit("G8d: PEVF pending", to_X01(rdw(PWM_SR_PEVF)), '1');
        sb.check_bit("G8d: irq_fault = FLTF & FLTIE = 1", to_X01(irq_fault), '1');
        sb.check_bit("G8d: irq_evt masked (PEVIE=0) despite PEVF=1", to_X01(irq_evt), '0');
        w1c(x"00000003");

        ------------------------------------------------------------------
        -- GROUP G-EV: EVFAB taps (event_fabric_spec.md 2026-07-24 SS2/SS3)
        -- evt_period is period_boundary (P-mode, only while PWMEN=1).
        -- evt_fault is THE fault SET condition (a register FLTTRIG edge OR the task_flttrig pulse, both FLTEN-gated), so it fires identically whether the trip came from the register or the fabric task.
        -- Pulse counts are proven with the continuous evt_mon_proc background monitor, which keeps checker independence by sampling only the exported evt_period and evt_fault ports and never a DUT internal, windowed via evt_mon_reset the same way G2's glitch monitor is windowed via mon_reset.
        ------------------------------------------------------------------
        report "=== GROUP G-EV: EVFAB taps (evt_period/evt_fault/task_flttrig) ===" severity note;

        -- G-EV-a: evt_period with the engine running, PER=15 (period=16 clk), the same shape as G1a.
        -- Enabling PWMEN degenerately self-commits per_active at the very first psc_tick (the D10 corner, the same mechanism G1a relies on implicitly), so absorb that one pulse with a bounded wait before opening the exact-count window, leaving the window spanning only the two REAL, settled 16-clk periods.
        reset_pulse;
        stage_waveform(15, 4, 8);
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '0', '0', '0', "0000"));
        wait_for_evt_period_high(PWM_POLL_GUARD, ok);
        sb.check_true("G-EV a0: evt_period pulses at PWMEN-enable (D10 degenerate first boundary, bounded wait)", ok);

        evt_mon_reset;
        wait_edges(32);   -- exactly 2 full periods (2 * 16 clk)
        sb.check_true("G-EV a1: evt_period pulses exactly 2 times over 2 full periods", evt_period_starts = 2);
        sb.check_true("G-EV a2: every evt_period pulse is exactly one clk wide (highs = starts)",
                      evt_period_highs = evt_period_starts);

        -- PWMEN=0: zero evt_period pulses over a bounded window.
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('0', '1', '1', '0', '0', '0', '0', "0000"));
        evt_mon_reset;
        wait_edges(40);
        sb.check_true("G-EV a3: evt_period never pulses while PWMEN=0 (bounded 40-clk window)",
                      evt_period_starts = 0 and evt_period_highs = 0);

        -- G-EV-b: evt_fault via the REGISTER FLTTRIG path.
        -- With FLTEN=1 a write-1 then restore FLTTRIG pair (A2: an explicit act) produces exactly one evt_fault pulse; with FLTEN=0 the same write pair produces none.
        reset_pulse;
        stage_waveform(15, 4, 8);
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '0', '1', '0', "0000")); -- FLTEN=1
        evt_mon_reset;
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '0', '1', '1', "0000")); -- FLTTRIG=1
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '0', '1', '0', "0000")); -- restore
        wait_edges(8);
        sb.check_true("G-EV b1: evt_fault pulses exactly once for a register FLTTRIG write (FLTEN=1)",
                      evt_fault_starts = 1);
        sb.check_true("G-EV b2: that evt_fault pulse is exactly one clk wide", evt_fault_highs = 1);
        w1c(x"00000001");   -- clear FLTF before the next leg

        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '0', '0', '0', "0000")); -- FLTEN=0
        evt_mon_reset;
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '0', '0', '1', "0000")); -- FLTTRIG=1
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '0', '0', '0', "0000")); -- restore
        wait_edges(8);
        sb.check_true("G-EV b3: evt_fault never pulses from a register FLTTRIG write while FLTEN=0",
                      evt_fault_starts = 0 and evt_fault_highs = 0);

        -- G-EV-c: evt_fault via the EVFAB TASK pulse (task_flttrig) with FLTEN=1.
        -- SAFE0=1 and SAFE1=0 differ from the POL-derived levels, the same discipline as G5, so the safe-force is unambiguous against normal running levels.
        -- A one-clk task_flttrig pulse must trip FLTF exactly like a register FLTTRIG write: one evt_fault pulse, FLTF=1, outputs go SAFE, and a W1C resumes normal tracking.
        reset_pulse;
        stage_waveform(15, 4, 8);
        bus_write(clk, pbus, PWM_SLOT_POL, pwm_mk_pol('0', '0', '1', '0'));   -- SAFE0=1, SAFE1=0
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '0', '1', '0', "0000")); -- FLTEN=1
        measure_cycle(0, hi, lo, ok);
        sb.check_true("G-EV c0: CH0 baseline running before the task pulse", ok and hi = 4);

        evt_mon_reset;
        pulse_task_flttrig;   -- exactly one clk high
        wait_edges(4);
        sb.check_true("G-EV c1: evt_fault pulses exactly once for a task_flttrig pulse (FLTEN=1)",
                      evt_fault_starts = 1);
        sb.check_true("G-EV c2: that evt_fault pulse is exactly one clk wide", evt_fault_highs = 1);

        bus_read(clk, pbus, rdata_out, PWM_SLOT_SR, rdw);
        sb.check_bit("G-EV c3: FLTF reads 1 after the task_flttrig pulse (trips exactly like a "
                     & "register FLTTRIG)", to_X01(rdw(PWM_SR_FLTF)), '1');
        sb.check_bit("G-EV c4: pwm_out(0) forced to SAFE0=1", to_X01(pwm_out(0)), '1');
        sb.check_bit("G-EV c5: pwm_out(1) forced to SAFE1=0", to_X01(pwm_out(1)), '0');

        w1c(x"00000001");   -- W1C FLTF
        bus_read(clk, pbus, rdata_out, PWM_SLOT_SR, rdw);
        sb.check_bit("G-EV c6: FLTF cleared after W1C", to_X01(rdw(PWM_SR_FLTF)), '0');
        measure_cycle(0, hi, lo, ok);
        sb.check_true("G-EV c7: CH0 resumes tracking the running comparator after W1C (measured)",
                      ok and hi = 4);

        -- G-EV-d: task_flttrig is INERT when FLTEN=0, so there is no evt_fault, FLTF stays 0 and the outputs are unaffected (this mirrors G6c's register-path corner).
        reset_pulse;
        stage_waveform(15, 4, 8);
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '0', '0', '0', "0000")); -- FLTEN=0
        measure_cycle(0, hi, lo, ok);
        sb.check_true("G-EV d0: CH0 baseline running before the inert task pulse", ok and hi = 4);

        evt_mon_reset;
        pulse_task_flttrig;
        wait_edges(4);
        sb.check_true("G-EV d1: evt_fault never pulses from task_flttrig while FLTEN=0",
                      evt_fault_starts = 0 and evt_fault_highs = 0);

        bus_read(clk, pbus, rdata_out, PWM_SLOT_SR, rdw);
        sb.check_bit("G-EV d2: FLTF stays 0 (a task pulse with FLTEN=0 does nothing)",
                     to_X01(rdw(PWM_SR_FLTF)), '0');
        measure_cycle(0, hi, lo, ok);
        sb.check_true("G-EV d3: CH0 output unaffected by the inert task pulse (still running, duty=4)",
                      ok and hi = 4);

        ------------------------------------------------------------------
        -- GROUP G-NEG: NEGATIVE CONTROL (mandatory, LAST): exactly ONE deliberately-wrong expected value so the scoreboard proves it can fail.
        -- It compares a freshly-measured CH0 duty against a wrong literal.
        ------------------------------------------------------------------
        report "=== GROUP G-NEG: NEGATIVE CONTROL ===" severity note;
        reset_pulse;
        stage_waveform(15, 4, 8);
        bus_write(clk, pbus, PWM_SLOT_CR, pwm_mk_cr('1', '1', '1', '0', '0', '0', '0', "0000"));
        measure_cycle(0, hi, lo, ok);
        sb.check_true("NEGATIVE CONTROL: wrong expected CH0 duty (must FAIL)", ok and hi = 4 + 1);

        ------------------------------------------------------------------
        -- Final verdict: sb.errors must be EXACTLY 1 (the negative control).
        ------------------------------------------------------------------
        wait for 1 us;
        sb.report_summary("PWM TB");

        if sb.errors = 1 then
            report LF & LF &
                "    ##################################################" & LF &
                "    ##   PWM_TB PASS (1 expected negative-control failure)" & LF &
                "    ##   PWM TB:  ALL CHECKS PASSED" & LF &
                "    ##################################################" & LF
                severity note;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   PWM_TB FAIL (expected exactly 1 failure [negative control], got " &
                integer'image(sb.errors) & ")" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        tb_done <= true;
        stop;
        wait;
    end process stim_proc;

end architecture sim;
