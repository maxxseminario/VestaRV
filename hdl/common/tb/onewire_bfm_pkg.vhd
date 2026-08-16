-------------------------------------------------------------------------------
-- onewire_bfm_pkg.vhd: bench-support helpers for the 1-Wire master peripheral testbench.
-- The slot numbers, CR/CMD/SR field positions and timing-window constants here are LOCAL to this bench and are NOT shared MemoryMap.vhd constants; OW0 lives at 0x6700.
-- CHECKER INDEPENDENCE: this package provides only bus-level plumbing, register-map constants and timing windows taken from the 1-Wire specification, never anything read out of OneWire.vhd.
-- Time base is 0.5 us per tick (OW0DIV=11 at 24 MHz nominal), so every slot-timing count here is DOUBLE the spec table's raw microsecond figure; the target model converts ticks to simulation time with the bench's own tick_period, which is the OW0DIV the TB programs, left at its power-on default 0, hence one clk period.
-- Bounded polls take (signal clk, signal b, signal read_data, [args], done_ok : out boolean), and the caller turns done_ok into a scoreboard pass/fail, so a poll that never satisfies its condition FAILS the run instead of hanging.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.periph_tb_pkg.all;

package onewire_bfm_pkg is

    -- ---- register word-slot map -------------------------------------------
    constant OW_SLOT_CR  : natural := 0;
    constant OW_SLOT_CMD : natural := 1;   -- lane-0 write LAUNCHES
    constant OW_SLOT_TX  : natural := 2;
    constant OW_SLOT_RX  : natural := 3;   -- r, side-effect-free
    constant OW_SLOT_DIV : natural := 4;
    constant OW_SLOT_SR  : natural := 5;
    constant OW_SLOT_SPU : natural := 6;   -- reserved: reads 0

    -- ---- OW0CR bit positions (slot 0) --------------------------------------
    constant OW_CR_OWEN  : natural := 0;
    constant OW_CR_ODS   : natural := 1;   -- overdrive speed select
    constant OW_CR_SPUEN : natural := 2;   -- reserved stub, no effect
    constant OW_CR_TCIE  : natural := 3;
    constant OW_CR_ERRIE : natural := 4;

    -- ---- OW0CMD field positions (slot 1) -----------------------------------
    -- OP is [2:0]; BITVAL (WRBIT value) is bit 8.
    constant OW_OP_RESET  : std_logic_vector(2 downto 0) := "000";
    constant OW_OP_WRBIT  : std_logic_vector(2 downto 0) := "001";
    constant OW_OP_RDBIT  : std_logic_vector(2 downto 0) := "010";
    constant OW_OP_WRBYTE : std_logic_vector(2 downto 0) := "011";
    constant OW_OP_RDBYTE : std_logic_vector(2 downto 0) := "100";

    -- ---- OW0SR bit positions (slot 5) --------------------------------------
    constant OW_SR_BUSY   : natural := 0;   -- r
    constant OW_SR_TCIF   : natural := 1;   -- w1c
    constant OW_SR_PRES   : natural := 2;   -- r
    constant OW_SR_NOPRES : natural := 3;   -- w1c
    constant OW_SR_SHORT  : natural := 4;   -- w1c

    -- ---- timing windows, half-us ticks (spec column, DOUBLED) --------------
    -- Pulse-width ACCEPT windows the target model checks the MASTER's driven-low durations against; a correctly-timed DUT always lands strictly inside them, and the FSM's own programmed count is noted per constant.
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
    constant OW_T_RL_STD_MIN   : natural := 2;     -- 1 us;   FSM drives 12 (tRL), same window as tW1L
    constant OW_T_RL_STD_MAX   : natural := 30;    -- 15 us
    constant OW_T_RL_OD_MIN    : natural := 2;     -- 1 us;   FSM drives 2
    constant OW_T_RL_OD_MAX    : natural := 4;     -- 2 us

    -- Write-bit classification threshold in ticks, roughly midway between the two windows above: it separates a short tW1L-class pulse from a long tW0L-class one.
    -- It only decides which window a pulse is checked against and is not itself a spec value.
    constant OW_WBIT_THRESH_STD : natural := 60;
    constant OW_WBIT_THRESH_OD  : natural := 9;

    -- ---- target-model response timing: the bench's own answers, derived from the tPRES, tMSR, tSLOT and tRSTH windows and never read from the DUT ----
    -- Presence: drive low immediately at reset release, hold long enough to cover the tPRES sample window ([120,150] STD, [15,20] OD) with margin, and release well before tRSTH (960 or 96) ends so it never looks like a SHORT.
    constant OW_PRES_HOLD_STD : natural := 200;
    constant OW_PRES_HOLD_OD  : natural := 25;
    -- Read bit=0: extend the master's initiating low pulse to cover the tMSR sample point (26 STD, 3 OD) with margin, releasing well before tSLOT (140 or 20) ends so the next slot's recovery is undisturbed.
    constant OW_RD_HOLD_STD : natural := 60;
    constant OW_RD_HOLD_OD  : natural := 8;
    -- Stuck/short: the onset falls AFTER the tPRES sample window closes, so a RESET's presence sample sees a clean release and NOPRES would normally arm, but BEFORE tRSTH's recovery check, so SHORT wins and fires at end-of-recovery.
    constant OW_STUCK_DELAY_STD : natural := 300;  -- > tPRES window (150), < tRSTH (960)
    constant OW_STUCK_DELAY_OD  : natural := 40;   -- > tPRES window (20), < tRSTH (96)

    -- Guard bound for the SR polls: the longest legitimate wait is a standard RESET at about 2061 FSM ticks, and each poll iteration is one bus_read of roughly one clk period.
    constant OW_POLL_GUARD : natural := 6000;

    -- Build a full 32-bit OW0CMD word (OP[2:0], BITVAL bit 8).
    function ow_mk_cmd(op : std_logic_vector(2 downto 0); bitval : std_logic)
        return std_logic_vector;

    -- Build a full 32-bit OW0CR word.
    function ow_mk_cr(owen, ods, spuen, tcie, errie : std_logic)
        return std_logic_vector;

    -- Convert a tick count into simulation time using the bench's own tick period, which is a TB-known constant and never a DUT read.
    function ow_ticks(n : natural; tick_period : time) return time;

    -- Pulse-width checker: returns '1' (violation) if low_dur falls outside [min_ticks,max_ticks] * tick_period, or unconditionally when force_viol is set.
    -- force_viol is the timing-corruption self-test flag: it proves the checker's flag path fires without relying on exact boundary math.
    function ow_win_violation(low_dur           : time;
                              min_ticks, max_ticks : natural;
                              tick_period          : time;
                              force_viol           : boolean)
        return std_logic;

    -- Bounded poll of OW0SR.BUSY (bit 0) until it reads '0', which happens at OW_DONE.
    -- done_ok comes back false, and the poll never hangs, if BUSY has not cleared within the guard count.
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
        -- TICK-QUANTIZATION FLOOR: the DUT asserts its drive-low mid-tick, unaligned to the free-running OW0DIV tick, so a phase programmed for n ticks produces a low pulse in ((n-1), n] * tick_period.
        -- The floor is therefore (min-1)*P, which accepts that whole quantization band yet still fails any pulse a full tick or more short; the max side needs no relaxation, since a pulse is never longer than n*P.
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
        -- LAUNCH-LATENCY GUARD: a CMD write flips launch_tgl in the ClkMem domain and BUSY only asserts once that toggle crosses the 2-FF synchronizer and the FSM leaves OW_IDLE, about 3 clk later, so a bare busy-clear poll would sample the pre-launch BUSY=0 and call the op done before it started.
        -- Wait for BUSY to ASSERT first, bounded, then poll for it to clear; an op shorter than the assert poll, or a suppressed launch, exits on aguard and reads BUSY=0 in the clear poll, which is correct for an already-finished op.
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
