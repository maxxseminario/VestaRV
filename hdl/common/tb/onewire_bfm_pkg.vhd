-------------------------------------------------------------------------------
-- onewire_bfm_pkg.vhd
-------------------------------------------------------------------------------
-- Bench-support helpers for the 1-Wire master peripheral testbench (tb/OneWire_tb.vhd).
-- OneWire.vhd is being written in parallel against the same FROZEN design this bench targets (~/vesta_docs/digperiphs/onewire_design.md, D1-D16 plus orchestrator A1-A5).
-- The slot numbers, CR/CMD/SR field positions and timing-window constants below are therefore LOCAL to this bench, mirroring rtc_bfm_pkg.vhd, nfc_bfm_pkg.vhd and i3c_bfm_pkg.vhd, and are NOT shared MemoryMap.vhd constants.
-- OW0 lives at 0x6700; MemoryMap.vhd has no OW0 slot constants until the generator knob is turned on (D16).
--
-- ADJUDICATION A1 (BINDING): the time base is 0.5 us per tick (OW0DIV=11 at 24 MHz nominal), so ALL D7 slot-timing counts DOUBLE relative to the design doc's raw table.
-- The OW_T_*_MIN/MAX window constants below are the D7 "Maxim window" column doubled into half-us ticks, i.e. the min and max ticks a correctly-timed master pulse must fall between.
-- They are NOT the FSM's own single programmed count, which sits inside that window by construction; see the per-constant comments.
-- The OW_PRES_HOLD_*, OW_RD_HOLD_* and OW_STUCK_DELAY_* constants are this BENCH's own target-model response timing, independently derived from the same D7 Maxim windows and never read from the DUT.
--
-- CHECKER INDEPENDENCE (the task's binding instruction, and the I3C/NFC/RTC lesson): this package provides ONLY bus-level plumbing, register-map constants, and time-domain window constants computed from the FROZEN design doc's own Maxim-spec table, never from OneWire.vhd.
-- The target model (onewire_target_model.vhd) multiplies these tick counts by the bench's OWN `tick_period` to get real simulation-time windows, and never reads OneWire.vhd's internal divider or FSM state.
-- `tick_period` is a TB-known constant: it is the OW0DIV the TB actually programs, and OW0DIV is left at its POR default 0, so tick_period is one `clk` period, 20 ns in OneWire_tb.vhd.
--
-- Calling convention for the bounded polls copies rtc_bfm_pkg and nfc_bfm_pkg exactly: (signal clk, signal b, signal read_data, [args], done_ok : out boolean).
-- The caller turns done_ok into a scoreboard pass/fail (sb.check_true), so a poll that never satisfies its condition FAILS the run instead of hanging.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.periph_tb_pkg.all;

package onewire_bfm_pkg is

    -- ---- register word-slot map (frozen, design doc D5) -------------------
    constant OW_SLOT_CR  : natural := 0;
    constant OW_SLOT_CMD : natural := 1;   -- lane-0 write LAUNCHES (D8)
    constant OW_SLOT_TX  : natural := 2;
    constant OW_SLOT_RX  : natural := 3;   -- r, side-effect-free (D9/A3)
    constant OW_SLOT_DIV : natural := 4;
    constant OW_SLOT_SR  : natural := 5;
    constant OW_SLOT_SPU : natural := 6;   -- reserved (D15): reads 0

    -- ---- OW0CR bit positions (design doc D5, slot 0) -----------------------
    constant OW_CR_OWEN  : natural := 0;
    constant OW_CR_ODS   : natural := 1;   -- A2: speed select bit name is ODS
    constant OW_CR_SPUEN : natural := 2;   -- reserved stub (D15), no effect
    constant OW_CR_TCIE  : natural := 3;
    constant OW_CR_ERRIE : natural := 4;

    -- ---- OW0CMD field positions (design doc D5/D9, slot 1) -----------------
    -- OP is [2:0]; BITVAL (WRBIT value) is bit 8.
    constant OW_OP_RESET  : std_logic_vector(2 downto 0) := "000";
    constant OW_OP_WRBIT  : std_logic_vector(2 downto 0) := "001";
    constant OW_OP_RDBIT  : std_logic_vector(2 downto 0) := "010";
    constant OW_OP_WRBYTE : std_logic_vector(2 downto 0) := "011";
    constant OW_OP_RDBYTE : std_logic_vector(2 downto 0) := "100";

    -- ---- OW0SR bit positions (design doc D5, slot 5) ------------------------
    constant OW_SR_BUSY   : natural := 0;   -- r
    constant OW_SR_TCIF   : natural := 1;   -- w1c
    constant OW_SR_PRES   : natural := 2;   -- r
    constant OW_SR_NOPRES : natural := 3;   -- w1c
    constant OW_SR_SHORT  : natural := 4;   -- w1c

    -- ---- D7/A1 timing windows, half-us ticks (Maxim spec column, DOUBLED) --
    -- Pulse-width ACCEPT windows the target model checks the MASTER's driven-low durations against.
    -- A correctly-timed DUT, using the D7/A1 FSM counts noted per constant, always lands strictly inside these.
    constant OW_T_RSTL_STD_MIN : natural := 960;   -- 480 us; FSM drives 960 (tRSTL)
    constant OW_T_RSTL_STD_MAX : natural := 1280;  -- 640 us
    constant OW_T_RSTL_OD_MIN  : natural := 96;    -- 48 us;  FSM drives 96
    constant OW_T_RSTL_OD_MAX  : natural := 160;   -- 80 us
    constant OW_T_W0L_STD_MIN  : natural := 120;   -- 60 us;  FSM drives 120 (tW0L)
    constant OW_T_W0L_STD_MAX  : natural := 240;   -- 120 us
    constant OW_T_W0L_OD_MIN   : natural := 15;    -- 7.5 us; FSM drives 16
    constant OW_T_W0L_OD_MAX   : natural := 28;    -- 14 us
    constant OW_T_W1L_STD_MIN  : natural := 2;     -- 1 us;   FSM drives 12 (tW1L)
    constant OW_T_W1L_STD_MAX  : natural := 30;    -- 15 us
    constant OW_T_W1L_OD_MIN   : natural := 2;     -- 1 us;   FSM drives 2
    constant OW_T_W1L_OD_MAX   : natural := 4;     -- 2 us
    constant OW_T_RL_STD_MIN   : natural := 2;     -- 1 us;   FSM drives 12 (tRL), same window as tW1L (D7)
    constant OW_T_RL_STD_MAX   : natural := 30;    -- 15 us
    constant OW_T_RL_OD_MIN    : natural := 2;     -- 1 us;   FSM drives 2
    constant OW_T_RL_OD_MAX    : natural := 4;     -- 2 us

    -- Write-bit classification threshold in ticks: separates a short tW1L-class pulse from a long tW0L-class pulse, roughly midway between the two windows above.
    -- It is used ONLY to decide which window to check a given pulse against, and is not itself a Maxim spec value.
    constant OW_WBIT_THRESH_STD : natural := 60;
    constant OW_WBIT_THRESH_OD  : natural := 9;

    -- ---- target-model OWN response timing (this bench's answers, derived --
    -- from the D7/A1 tPRES, tMSR, tSLOT and tRSTH windows, never read from the DUT.
    -- Presence: drive low immediately at reset release, hold long enough to cover the tPRES sample window ([120,150] STD, [15,20] OD) with margin, and release well before tRSTH (960 or 96) ends so it never looks like a SHORT.
    constant OW_PRES_HOLD_STD : natural := 200;
    constant OW_PRES_HOLD_OD  : natural := 25;
    -- Read bit=0: extend the master's initiating low pulse to cover the tMSR sample point (26 STD, 3 OD) with margin, releasing well before tSLOT (140 or 20) ends so the next slot's recovery is undisturbed.
    constant OW_RD_HOLD_STD : natural := 60;
    constant OW_RD_HOLD_OD  : natural := 8;
    -- Stuck/short (A5 test): the onset is chosen AFTER the tPRES sample window closes, so a RESET's presence sample sees a clean release and NOPRES would normally arm, but BEFORE tRSTH's recovery check, so SHORT fires at end-of-recovery.
    -- That is exactly the A5 "SHORT wins" scenario.
    constant OW_STUCK_DELAY_STD : natural := 300;  -- > tPRES window (150), < tRSTH (960)
    constant OW_STUCK_DELAY_OD  : natural := 40;   -- > tPRES window (20), < tRSTH (96)

    -- Guard bound for the SR polls: the longest legitimate wait is a standard RESET at about 2061 FSM ticks.
    -- At the bench's OW0DIV=0, 20 ns tick that is about 41.2 us, and each poll iteration is one bus_read of roughly one clk period.
    constant OW_POLL_GUARD : natural := 6000;

    -- Build a full 32-bit OW0CMD word (D5/D9 field layout: OP[2:0], BITVAL[8]).
    function ow_mk_cmd(op : std_logic_vector(2 downto 0); bitval : std_logic)
        return std_logic_vector;

    -- Build a full 32-bit OW0CR word (D5 field layout).
    function ow_mk_cr(owen, ods, spuen, tcie, errie : std_logic)
        return std_logic_vector;

    -- Convert a tick count into simulation time using the bench's own tick period.
    -- Checker-independent: tick_period is a TB-known constant, never a DUT read.
    function ow_ticks(n : natural; tick_period : time) return time;

    -- Pulse-width checker: returns '1' (violation) if low_dur falls outside [min_ticks,max_ticks] * tick_period, or unconditionally when force_viol is set.
    -- force_viol is the design doc's "timing-corruption self-test flag", which proves the checker's flag path fires without relying on exact boundary math.
    function ow_win_violation(low_dur           : time;
                              min_ticks, max_ticks : natural;
                              tick_period          : time;
                              force_viol           : boolean)
        return std_logic;

    -- Bounded poll of OW0SR.BUSY (bit 0) until it reads '0'; per D12, BUSY drops at OW_DONE.
    -- done_ok comes back false, and the poll never hangs, if BUSY has not cleared within the guard count; this mirrors rtc_wait_sync_clear and nfc_wait_busy_clear.
    procedure ow_wait_busy_clear(signal clk       : in    std_logic;
                                 signal b         : inout periph_bus_t;
                                 signal read_data : in    std_logic_vector(31 downto 0);
                                 done_ok          : out   boolean);

    -- Bounded poll of a single OW0SR flag bit until it reads exp_val.
    procedure ow_wait_flag(signal clk       : in    std_logic;
                           signal b         : inout periph_bus_t;
                           signal read_data : in    std_logic_vector(31 downto 0);
                           bit_idx          : in    natural;
                           exp_val          : in    std_logic;
                           done_ok          : out   boolean);

end package onewire_bfm_pkg;


package body onewire_bfm_pkg is

    function ow_mk_cmd(op : std_logic_vector(2 downto 0); bitval : std_logic)
        return std_logic_vector is
        variable v : std_logic_vector(31 downto 0) := (others => '0');
    begin
        v(2 downto 0) := op;
        v(8)          := bitval;
        return v;
    end function;

    function ow_mk_cr(owen, ods, spuen, tcie, errie : std_logic)
        return std_logic_vector is
        variable v : std_logic_vector(31 downto 0) := (others => '0');
    begin
        v(OW_CR_OWEN)  := owen;
        v(OW_CR_ODS)   := ods;
        v(OW_CR_SPUEN) := spuen;
        v(OW_CR_TCIE)  := tcie;
        v(OW_CR_ERRIE) := errie;
        return v;
    end function;

    function ow_ticks(n : natural; tick_period : time) return time is
    begin
        return n * tick_period;
    end function;

    function ow_win_violation(low_dur           : time;
                              min_ticks, max_ticks : natural;
                              tick_period          : time;
                              force_viol           : boolean)
        return std_logic is
    begin
        -- TICK-QUANTIZATION FLOOR.
        -- The DUT is a tick-counting FSM: it asserts the drive-low the cycle it dispatches a phase, mid-tick and unaligned to the free-running OW0DIV tick, then releases on the target-th tick.
        -- So a phase programmed for n ticks produces a wall-clock low pulse in ((n-1), n] * tick_period, ALWAYS a fraction of a tick under n*P unless the assert happens to land exactly on a tick.
        -- That exact-landing case only occurs at OW0DIV=0, where a tick is one clk, which is why an exact-min floor worked there.
        -- For any OW0DIV greater than 0, which is required so the 2-FF DQ sync stays sub-tick for OVERDRIVE reads, demanding low_dur >= min*P wrongly rejects a correctly-programmed min-tick pulse.
        -- The tightest HONEST floor for an unaligned-start tick machine is (min-1)*P: it accepts the whole ((min-1), min] quantization band of a min-tick pulse while still failing any pulse a full tick or more short, i.e. at or below (min-1)*P.
        -- The max side needs no such relaxation, since the pulse is always at most n*P and n*P is at most max*P.
        if force_viol then
            return '1';
        elsif min_ticks > 0 and low_dur <= (min_ticks - 1) * tick_period then
            return '1';
        elsif low_dur > max_ticks * tick_period then
            return '1';
        else
            return '0';
        end if;
    end function;

    procedure ow_wait_busy_clear(signal clk       : in    std_logic;
                                 signal b         : inout periph_bus_t;
                                 signal read_data : in    std_logic_vector(31 downto 0);
                                 done_ok          : out   boolean) is
        variable s      : std_logic_vector(31 downto 0);
        variable guard  : natural := 0;
        variable aguard : natural := 0;
    begin
        done_ok := false;
        -- LAUNCH-LATENCY GUARD (D8): a CMD-write launch flips launch_tgl in the ClkMem domain, and BUSY does not assert until that toggle crosses the clk-domain 2-FF synchronizer and the FSM steps out of OW_IDLE, about 3 clk later.
        -- A busy-clear poll issued immediately after the launch would otherwise sample the pre-launch idle BUSY=0 and declare the op done before it has even started, racing the launch.
        -- So first wait for BUSY to ASSERT, bounded, then poll for it to clear.
        -- An op shorter than the assert-poll window, or a suppressed launch, exits the assert-poll on aguard and falls straight into the clear-poll, which reads BUSY=0; that is correct for an already-finished op.
        loop
            bus_read(clk, b, read_data, OW_SLOT_SR, s);
            exit when to_X01(s(OW_SR_BUSY)) = '1';
            aguard := aguard + 1;
            exit when aguard > 200;
        end loop;
        loop
            bus_read(clk, b, read_data, OW_SLOT_SR, s);
            if to_X01(s(OW_SR_BUSY)) = '0' then
                done_ok := true;
                exit;
            end if;
            guard := guard + 1;
            exit when guard > OW_POLL_GUARD;   -- bounded (never hangs)
        end loop;
    end procedure;

    procedure ow_wait_flag(signal clk       : in    std_logic;
                           signal b         : inout periph_bus_t;
                           signal read_data : in    std_logic_vector(31 downto 0);
                           bit_idx          : in    natural;
                           exp_val          : in    std_logic;
                           done_ok          : out   boolean) is
        variable s     : std_logic_vector(31 downto 0);
        variable guard : natural := 0;
    begin
        done_ok := false;
        loop
            bus_read(clk, b, read_data, OW_SLOT_SR, s);
            if to_X01(s(bit_idx)) = exp_val then
                done_ok := true;
                exit;
            end if;
            guard := guard + 1;
            exit when guard > OW_POLL_GUARD;   -- bounded (never hangs)
        end loop;
    end procedure;

end package body onewire_bfm_pkg;
