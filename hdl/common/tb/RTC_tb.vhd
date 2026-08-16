-------------------------------------------------------------------------------
-- RTC_tb.vhd
-------------------------------------------------------------------------------
-- Standalone, self-checking testbench for the RTC peripheral, on the shared support packages tb/periph_tb_pkg.vhd (scoreboard + register-bus BFM) and tb/rtc_bfm_pkg.vhd (slot/CR/SR constants, the rtc_mk_cr packer, rtc_combined/rtc_within, and the bounded SR polls).
-- The DUT is declared as a COMPONENT, not an entity instantiation, so this bench compiles standalone; VHDL default binding resolves it to the entity of the same name once RTC.vhd is analyzed into work.
-- Three clocks: clk is the free-running 20 ns bus/CDC reference, ClkMem the gated bus clock (clk while EnMemPeriph='0'), lfxt_in the ungated 32.768 kHz wall clock compressed to a 100 ns period so the 2-FF CDC still sees a real fast/slow ratio.
-- CHECKER INDEPENDENCE (mandatory): the bench keeps its OWN 47-bit wall-clock reference by counting lfxt_in rising edges in TB code, never reading a DUT internal, and every SEC/SUB compare allows read-snapshot staleness inside a [lo,hi] reference window (CMP_BOUND).
-- to_X01 normalizes every sampled DUT level that could be weak or meta, but full reset-default word reads are compared RAW so an uninitialized X is caught.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.periph_tb_pkg.all;
use work.rtc_bfm_pkg.all;

entity RTC_tb is
end entity RTC_tb;

architecture sim of RTC_tb is

    constant PERIOD   : time    := 20 ns;    -- clk / bus reference, free-running
    constant LFXT_HALF: time    := 50 ns;    -- lfxt_in half period, so a 100 ns wall-clock tick

    -- Snapshot-staleness + CDC-skew tolerance in lfxt ticks for every reference-vs-DUT compare: read snapshot (1-2) + write-side 2-FF sync and edge-detect delay (2-4) + poll/phase jitter (1-2).
    -- Real failures (missed carry, wrong load) miss by thousands of ticks, so 8 stays a sharp discriminator.
    constant CMP_BOUND : natural := 8;

    -- DUT declared as a component so the bench compiles standalone; the EVFAB taps must be listed here so default binding sees the FULL entity port list.
    -- evt_alarm/evt_tick are the synchronized event edges, exported PRE-IE.
    component RTC is
        port (
            clk         : in  std_logic;
            resetn      : in  std_logic;
            lfxt_in     : in  std_logic;
            irq_rtc     : out std_logic;
            ClkMem      : in  std_logic;
            EnMemPeriph : in  std_logic;
            WEn         : in  std_logic_vector(3 downto 0);
            MABPart     : in  std_logic_vector(7 downto 2);
            wdata       : in  std_logic_vector(31 downto 0);
            rdata_out   : out std_logic_vector(31 downto 0);

            evt_alarm   : out std_logic;
            evt_tick    : out std_logic
        );
    end component;

    -- clocks / reset
    signal clk     : std_logic := '0';
    signal ClkMem  : std_logic := '0';
    signal lfxt_in : std_logic := '0';
    signal resetn  : std_logic := '0';

    -- interrupt
    signal irq_rtc : std_logic;

    -- register bus
    signal pbus      : periph_bus_t := PERIPH_BUS_IDLE;
    signal rdata_out : std_logic_vector(31 downto 0);

    -- ---- EVFAB taps -------------------------------------------------------
    signal evt_alarm : std_logic;
    signal evt_tick  : std_logic;

    -- ---- EVFAB pulse monitor (reads only the exported taps) ---------------
    -- Continuous tracker of evt_alarm/evt_tick: counts pulse STARTS and total HIGH samples at clk rising edges since the last evt_mon_clear.
    -- Exactly N one-clk-wide pulses give starts=N AND highs=N: a wider pulse pushes highs above starts, a missed pulse leaves starts short.
    signal evt_alarm_starts, evt_alarm_highs : natural := 0;
    signal evt_tick_starts,  evt_tick_highs  : natural := 0;
    signal evt_alarm_prev, evt_tick_prev     : std_logic := '0';
    signal evt_mon_clear : std_logic := '0';

    -- ---- TB independent wall-clock reference, never driven from a DUT internal ----
    -- ref_count counts lfxt_in rising edges while ref_en='1'; ref_load anchors it to ref_load_val on the next lfxt rising edge at each set-time commit.
    signal ref_count    : unsigned(RTC_CNT_BITS - 1 downto 0) := (others => '0');
    signal ref_en       : std_logic := '0';
    signal ref_load     : std_logic := '0';
    signal ref_load_val : unsigned(RTC_CNT_BITS - 1 downto 0) := (others => '0');

    signal tb_done : boolean := false;

    shared variable sb : scoreboard;

begin

    ----------------------------------------------------------------------------
    -- clock / gated register-bus clock
    ----------------------------------------------------------------------------
    clk     <= not clk after PERIOD / 2;
    lfxt_in <= not lfxt_in after LFXT_HALF;
    ClkMem  <= clk when pbus.en_mem = '0' else '0';

    ----------------------------------------------------------------------------
    -- Independent reference wall clock: counts lfxt_in rising edges, anchored by ref_load at each set-time commit.
    ----------------------------------------------------------------------------
    ref_proc : process(lfxt_in)
    begin
        if rising_edge(lfxt_in) then
            if ref_load = '1' then
                ref_count <= ref_load_val;
            elsif ref_en = '1' then
                ref_count <= ref_count + 1;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- EVFAB pulse monitor: samples evt_alarm/evt_tick (to_X01-normalized) on every clk rising edge, windowed by evt_mon_clear.
    ----------------------------------------------------------------------------
    evt_mon_proc : process(clk)
        variable a_lvl, t_lvl : std_logic;
    begin
        if rising_edge(clk) then
            a_lvl := to_X01(evt_alarm);
            t_lvl := to_X01(evt_tick);
            if evt_mon_clear = '1' then
                evt_alarm_starts <= 0;
                evt_alarm_highs  <= 0;
                evt_tick_starts  <= 0;
                evt_tick_highs   <= 0;
                evt_alarm_prev   <= a_lvl;
                evt_tick_prev    <= t_lvl;
            else
                if a_lvl = '1' then
                    evt_alarm_highs <= evt_alarm_highs + 1;
                    if evt_alarm_prev /= '1' then
                        evt_alarm_starts <= evt_alarm_starts + 1;
                    end if;
                end if;
                if t_lvl = '1' then
                    evt_tick_highs <= evt_tick_highs + 1;
                    if evt_tick_prev /= '1' then
                        evt_tick_starts <= evt_tick_starts + 1;
                    end if;
                end if;
                evt_alarm_prev <= a_lvl;
                evt_tick_prev  <= t_lvl;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------------
    dut : component RTC
        port map (
            clk         => clk,
            resetn      => resetn,
            lfxt_in     => lfxt_in,
            irq_rtc     => irq_rtc,
            ClkMem      => ClkMem,
            EnMemPeriph => pbus.en_mem,
            WEn         => pbus.wen,
            MABPart     => pbus.addr_periph,
            wdata       => pbus.write_data,
            rdata_out   => rdata_out,
            evt_alarm   => evt_alarm,
            evt_tick    => evt_tick
        );

    ----------------------------------------------------------------------------
    -- Watchdog: abort with a FAIL banner if the stimulus ever hangs.
    -- Expected sim time is under 1 ms, so this fires only on a true hang; std.env.stop from stim kills it on a clean run.
    ----------------------------------------------------------------------------
    watchdog : process
    begin
        wait for 20 ms;
        if not tb_done then
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   RTC_TB FAIL (WATCHDOG TIMEOUT -- stimulus never finished)" & LF &
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
        variable rdw     : std_logic_vector(31 downto 0);
        variable secw    : std_logic_vector(31 downto 0);
        variable subw    : std_logic_vector(31 downto 0);
        variable dut47   : unsigned(RTC_CNT_BITS - 1 downto 0);
        variable ref_lo  : unsigned(RTC_CNT_BITS - 1 downto 0);
        variable ref_hi  : unsigned(RTC_CNT_BITS - 1 downto 0);
        variable prev47  : unsigned(RTC_CNT_BITS - 1 downto 0);
        variable ok      : boolean;
        variable alm_base: unsigned(31 downto 0) := x"00000100";
        variable d0, d1  : unsigned(RTC_CNT_BITS - 1 downto 0);
        variable delta   : integer;
        variable tickcnt : natural;

        -- W1C the given SR mask, then a dummy CR read to retire the gated-ClkMem write pulse before the next SR read.
        procedure w1c(mask : std_logic_vector(31 downto 0)) is
            variable r : std_logic_vector(31 downto 0);
        begin
            bus_write(clk, pbus, RTC_SLOT_SR, mask);
            bus_read (clk, pbus, rdata_out, RTC_SLOT_CR, r);
        end procedure;

        -- ---- EVFAB tap helper -----------------------------------------------

        -- Clear the evt_alarm/evt_tick pulse monitor's accumulators, holding evt_mon_clear across one clk edge.
        -- Call only OUTSIDE a timing-critical window.
        procedure evt_mon_reset is
        begin
            wait until clk = '0';
            evt_mon_clear <= '1';
            wait until clk = '1';
            wait until clk = '0';
            evt_mon_clear <= '0';
        end procedure;

        -- Read the coherent SEC/SUB snapshot pair and return the TB 47-bit combined value plus the reference window [ref_lo, ref_hi] captured around the two bus reads.
        procedure read_wall(dutv : out unsigned(RTC_CNT_BITS - 1 downto 0);
                            lo   : out unsigned(RTC_CNT_BITS - 1 downto 0);
                            hi   : out unsigned(RTC_CNT_BITS - 1 downto 0)) is
            variable s, u : std_logic_vector(31 downto 0);
        begin
            lo := ref_count;
            bus_read(clk, pbus, rdata_out, RTC_SLOT_SEC, s);
            bus_read(clk, pbus, rdata_out, RTC_SLOT_SUB, u);
            hi := ref_count;
            dutv := rtc_combined(s, u);
        end procedure;

        -- Set-time to {sec, sub}: stage SUB, commit both by writing SEC, poll SR.SYNC from busy to clear, and anchor the TB reference to the same value.
        -- Leaves the wall clock counting from {sec, sub}.
        procedure set_time(sec : std_logic_vector(31 downto 0);
                           sub : std_logic_vector(14 downto 0)) is
            variable done_ok : boolean;
        begin
            bus_write(clk, pbus, RTC_SLOT_SUB, x"0000" & '0' & sub);   -- stage SUB [14:0]
            -- Anchor the reference AT the commit write, BEFORE the SYNC poll: the DUT applies the load 2-4 lfxt edges later (wr_req 2-FF sync + edge detect) and so runs that constant amount BEHIND the reference, which is the direction the "dut never ahead of ref_hi" check needs and stays inside CMP_BOUND.
            -- Anchoring after the SYNC-clear poll instead puts the DUT AHEAD of the reference and fails that check.
            ref_load_val <= unsigned(sec) & unsigned(sub);
            ref_load     <= '1';
            bus_write(clk, pbus, RTC_SLOT_SEC, sec);                   -- commit {SEC,SUB}
            wait for 2 * LFXT_HALF;        -- ~1 lfxt period: exactly 1-2 anchor edges
            ref_load     <= '0';
            rtc_wait_sync_clear(clk, pbus, rdata_out, done_ok);
            sb.check_true("set_time: SR.SYNC asserted then cleared (D8)", done_ok);
        end procedure;

        -- Make BOTH ALMF and TICKF pending: jump near a prescaler wrap, arm an alarm one second out and a fast periodic tick, then wait for the alarm match (by which time several ticks have also fired).
        -- Leaves both engines enabled with both sticky flags set.
        procedure make_both_pending(secbase : std_logic_vector(31 downto 0)) is
            variable done_ok : boolean;
        begin
            set_time(secbase, "111111100000000");         -- SUB = 0x7F00 (256 from wrap)
            bus_write(clk, pbus, RTC_SLOT_ALM,
                      std_logic_vector(unsigned(secbase) + 1));
            rtc_wait_sync_clear(clk, pbus, rdata_out, done_ok);
            bus_write(clk, pbus, RTC_SLOT_PER, x"00000004");
            rtc_wait_sync_clear(clk, pbus, rdata_out, done_ok);
            -- Clear any STALE flags left by a previous leg, THEN enable and wait for BOTH flags to be freshly pending.
            -- A masked ALMF left pending would satisfy the ALMF wait instantly, freezing the engines before any tick fires.
            w1c(x"00000006");
            bus_write(clk, pbus, RTC_SLOT_CR,
                      rtc_mk_cr('1', '1', '1', '1', '1'));  -- all EN + all IE
            rtc_wait_flag(clk, pbus, rdata_out, RTC_SR_ALMF, '1', done_ok);
            rtc_wait_flag(clk, pbus, rdata_out, RTC_SR_TICKF, '1', done_ok);
        end procedure;

    begin
        ------------------------------------------------------------------
        -- Reset (resetn low for a few hundred ns at t=0)
        ------------------------------------------------------------------
        resetn <= '0';
        pbus   <= PERIPH_BUS_IDLE;
        ref_en <= '0';
        wait for 12 * PERIOD;    -- ~240 ns
        wait for 1 ns;
        resetn <= '1';
        wait for 8 * PERIOD;

        ------------------------------------------------------------------
        -- GROUP G0: reset defaults
        ------------------------------------------------------------------
        report "=== GROUP G0: reset defaults ===" severity note;
        bus_read(clk, pbus, rdata_out, RTC_SLOT_CR, rdw);
        sb.check_slv("G0: CR resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SR, rdw);
        sb.check_slv("G0: SR resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SEC, rdw);
        sb.check_slv("G0: SEC resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SUB, rdw);
        sb.check_slv("G0: SUB resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, RTC_SLOT_ALM, rdw);
        sb.check_slv("G0: ALM resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, RTC_SLOT_PER, rdw);
        sb.check_slv("G0: PER resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, RTC_SLOT_TRIM, rdw);
        sb.check_slv("G0: TRIM (reserved) reads 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, 7, rdw);
        sb.check_slv("G0: slot 7 reads 0", rdw, x"00000000");
        sb.check_bit("G0: irq_rtc = 0 out of reset", to_X01(irq_rtc), '0');

        ------------------------------------------------------------------
        -- GROUP G1: wall-clock advance
        -- Enable RTCEN, start the TB reference at the SAME moment, then confirm the DUT snapshot advances monotonically and tracks the reference within the staleness bound, never AHEAD of it.
        ------------------------------------------------------------------
        report "=== GROUP G1: wall-clock advance ===" severity note;
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '0', '0', '0', '0'));  -- RTCEN
        ref_en <= '1';                     -- TB reference starts counting too
        wait for 200 * (2 * LFXT_HALF);    -- ~200 lfxt ticks: let both settle

        prev47 := (others => '0');
        for i in 0 to 5 loop
            wait for 300 * (2 * LFXT_HALF); -- advance ~300 lfxt ticks between reads
            read_wall(dut47, ref_lo, ref_hi);
            sb.check_true("G1: DUT wall clock advanced (monotonic non-decreasing)",
                          dut47 >= prev47);
            sb.check_true("G1: DUT snapshot never ahead of reference (dut <= ref_hi)",
                          dut47 <= ref_hi);
            sb.check_true("G1: DUT snapshot within staleness bound of reference",
                          rtc_within(dut47, ref_lo, CMP_BOUND));
            sb.check_true("G1: SUB field in range (< 32768)",
                          to_integer(dut47(RTC_SUB_BITS - 1 downto 0)) < RTC_SUB_MOD);
            prev47 := dut47;
        end loop;

        ------------------------------------------------------------------
        -- GROUP G2: coherent snapshot
        -- The firmware SEC,SUB,SEC-recompare idiom: repeated reads are never torn and each coherent pair tracks the reference within bound.
        ------------------------------------------------------------------
        report "=== GROUP G2: coherent snapshot ===" severity note;
        prev47 := dut47;
        for i in 0 to 19 loop
            ref_lo := ref_count;
            bus_read(clk, pbus, rdata_out, RTC_SLOT_SEC, secw);   -- SEC
            bus_read(clk, pbus, rdata_out, RTC_SLOT_SUB, subw);   -- SUB
            bus_read(clk, pbus, rdata_out, RTC_SLOT_SEC, rdw);    -- SEC again
            ref_hi := ref_count;
            dut47  := rtc_combined(secw, subw);
            if secw = rdw then
                -- SEC unchanged across the pair means the SEC/SUB pair is coherent.
                sb.check_true("G2: coherent pair SUB in range (< 32768)",
                              to_integer(unsigned(subw(RTC_SUB_BITS - 1 downto 0))) < RTC_SUB_MOD);
                sb.check_true("G2: coherent pair within staleness bound of reference",
                              rtc_within(dut47, ref_lo, CMP_BOUND) and (dut47 <= ref_hi));
                sb.check_true("G2: coherent pair monotonic vs previous read",
                              dut47 >= prev47);
                prev47 := dut47;
            else
                -- SEC ticked mid-idiom (allowed): the driver would retry, so just confirm the second SEC did not go backwards.
                sb.check_true("G2: SEC recompare only advances (retry case)",
                              unsigned(rdw) >= unsigned(secw));
            end if;
            wait for 40 * (2 * LFXT_HALF);
        end loop;

        ------------------------------------------------------------------
        -- GROUP G3: set-time
        -- Stage SUB then commit SEC (atomic {SEC,SUB} load): SR.SYNC asserts then clears, read-back equals the loaded value, counting resumes from it, and a sub-carry set-time increments SEC by exactly one.
        ------------------------------------------------------------------
        report "=== GROUP G3: set-time ===" severity note;
        -- Stage SUB=0x3FF0, commit SEC=0x12345678 (set_time waits for SR.SYNC and anchors the TB reference).
        set_time(x"12345678", "011111111110000");    -- 0x3FF0

        read_wall(dut47, ref_lo, ref_hi);
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SEC, secw);
        sb.check_slv("G3: SEC read-back = loaded 0x12345678", secw, x"12345678");
        sb.check_true("G3: loaded {SEC,SUB} within staleness bound of reference",
                      rtc_within(dut47, ref_lo, CMP_BOUND) and (dut47 <= ref_hi));

        prev47 := dut47;
        wait for 200 * (2 * LFXT_HALF);               -- let it run
        read_wall(dut47, ref_lo, ref_hi);
        sb.check_true("G3: counting resumes from loaded value (strictly greater)",
                      dut47 > prev47);

        -- Sub-carry: load SUB=0x7FF0 (16 ticks from wrap) so SEC increments by exactly one at the prescaler roll-over.
        -- Read SEC before and after.
        set_time(x"00001000", "111111111110000");     -- 0x7FF0
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SEC, secw);   -- before wrap
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SUB, subw);
        sb.check_slv("G3: pre-wrap SEC = 0x1000", secw, x"00001000");
        wait for 40 * (2 * LFXT_HALF);                -- > 16 lfxt ticks: cross the wrap
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SEC, rdw);    -- after wrap
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SUB, subw);
        sb.check_slv("G3: sub-carry: SEC incremented by exactly one", rdw, x"00001001");

        -- Hygiene: leave RTCEN on (always-on wall clock), ensure flags clear.
        w1c(x"00000006");                             -- W1C ALMF|TICKF (none set yet)

        ------------------------------------------------------------------
        -- GROUP G4: alarm
        -- Compressed via the set-time-near-wrap trick: SUB loaded at 0x7F00 is 256 lfxt ticks from the prescaler roll-over, so an alarm at SEC+1 fires ~256 ticks later.
        -- Legs proved: fire plus irq; W1C clears the flag and drops irq; one-shot (no re-fire across the match second); re-arm fires again; ALMEN=0 suppresses.
        ------------------------------------------------------------------
        report "=== GROUP G4: alarm ===" severity note;

        -- G4a: program ALM = current-second + 1, arm, wait for the match.
        set_time(x"00000100", "111111100000000");     -- SEC=0x100, SUB=0x7F00
        bus_write(clk, pbus, RTC_SLOT_ALM, x"00000101");   -- ALM = 0x101
        rtc_wait_sync_clear(clk, pbus, rdata_out, ok);
        sb.check_true("G4a: ALM commit SR.SYNC cleared", ok);
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '1', '0', '1', '0')); -- RTCEN|ALMEN|ALMIE
        rtc_wait_flag(clk, pbus, rdata_out, RTC_SR_ALMF, '1', ok);
        sb.check_true("G4a: ALMF set at the alarm match (bounded wait)", ok);
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SR, rdw);
        sb.check_bit("G4a: ALMF sticky set", to_X01(rdw(RTC_SR_ALMF)), '1');
        wait for 4 * PERIOD;
        sb.check_bit("G4a: irq_rtc asserted (ALMF & ALMIE)", to_X01(irq_rtc), '1');

        -- G4b: W1C ALMF clears the flag and drops irq.
        w1c(x"00000002");                              -- W1C ALMF
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SR, rdw);
        sb.check_bit("G4b: ALMF cleared after W1C", to_X01(rdw(RTC_SR_ALMF)), '0');
        wait for 4 * PERIOD;
        sb.check_bit("G4b: irq_rtc dropped after ALMF W1C", to_X01(irq_rtc), '0');

        -- G4c: one-shot: with ALM unchanged, SEC rolls from 0x101 to 0x102, leaving the match with no new rising edge of equality, so no re-fire.
        wait for 400 * (2 * LFXT_HALF);                -- cross out of the match second
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SR, rdw);
        sb.check_bit("G4c: one-shot -- no ALMF re-fire the next second",
                     to_X01(rdw(RTC_SR_ALMF)), '0');

        -- G4d: re-arm (write a new ALM, jump near the next boundary) fires again.
        bus_write(clk, pbus, RTC_SLOT_ALM, x"00000103");   -- ALM = 0x103
        rtc_wait_sync_clear(clk, pbus, rdata_out, ok);
        set_time(x"00000102", "111111100000000");     -- SEC=0x102, SUB=0x7F00
        rtc_wait_flag(clk, pbus, rdata_out, RTC_SR_ALMF, '1', ok);
        sb.check_true("G4d: re-armed alarm fires again", ok);
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SR, rdw);
        sb.check_bit("G4d: ALMF set on re-arm", to_X01(rdw(RTC_SR_ALMF)), '1');
        w1c(x"00000002");

        -- G4e: ALMEN=0 suppression: program a match but leave ALMEN clear.
        bus_write(clk, pbus, RTC_SLOT_ALM, x"00000201");   -- ALM = 0x201
        rtc_wait_sync_clear(clk, pbus, rdata_out, ok);
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '0', '0', '1', '0')); -- RTCEN, ALMEN=0
        set_time(x"00000200", "111111100000000");     -- SEC=0x200, SUB=0x7F00
        wait for 400 * (2 * LFXT_HALF);                -- past the would-be match
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SR, rdw);
        sb.check_bit("G4e: ALMEN=0 suppresses ALMF (no fire)",
                     to_X01(rdw(RTC_SR_ALMF)), '0');

        -- Hygiene: disable alarm engine, clear flags, back to RTCEN only.
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '0', '0', '0', '0'));
        w1c(x"00000006");

        ------------------------------------------------------------------
        -- GROUP G5: periodic tick, PER=4 giving a tick every PER+1 = 5 lfxt ticks.
        -- Catch N consecutive ticks, W1C each, check the cadence against the independent lfxt-edge reference, reprogram PER=9 for cadence 10, and confirm SEC/SUB is undisturbed by the tick engine.
        ------------------------------------------------------------------
        report "=== GROUP G5: periodic tick ===" severity note;
        bus_write(clk, pbus, RTC_SLOT_PER, x"00000004");   -- PER = 4
        rtc_wait_sync_clear(clk, pbus, rdata_out, ok);
        sb.check_true("G5: PER commit SR.SYNC cleared", ok);
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '0', '1', '0', '1')); -- RTCEN|TICKEN|TICKIE

        -- Prime: catch and clear the first tick (its phase includes the enable cross), then measure the cadence of the following ticks.
        rtc_wait_flag(clk, pbus, rdata_out, RTC_SR_TICKF, '1', ok);
        sb.check_true("G5: first TICKF observed (bounded)", ok);
        wait for 2 * PERIOD;
        sb.check_bit("G5: irq_rtc asserted (TICKF & TICKIE)", to_X01(irq_rtc), '1');
        d0 := ref_count;
        w1c(x"00000004");                              -- W1C TICKF

        for i in 0 to 4 loop
            rtc_wait_flag(clk, pbus, rdata_out, RTC_SR_TICKF, '1', ok);
            d1 := ref_count;
            sb.check_true("G5: TICKF recurs (bounded wait)", ok);
            delta := to_integer(d1 - d0);              -- small positive difference
            sb.check_true("G5: tick cadence ~= PER+1 (=5) lfxt ticks",
                          delta >= 3 and delta <= 7);
            w1c(x"00000004");
            d0 := d1;
        end loop;

        -- Reprogram PER=9 for cadence 10, then check the new spacing.
        bus_write(clk, pbus, RTC_SLOT_PER, x"00000009");   -- PER = 9
        rtc_wait_sync_clear(clk, pbus, rdata_out, ok);
        rtc_wait_flag(clk, pbus, rdata_out, RTC_SR_TICKF, '1', ok);  -- resync phase
        d0 := ref_count;
        w1c(x"00000004");
        for i in 0 to 2 loop
            rtc_wait_flag(clk, pbus, rdata_out, RTC_SR_TICKF, '1', ok);
            d1 := ref_count;
            sb.check_true("G5: TICKF recurs after PER reprogram", ok);
            delta := to_integer(d1 - d0);
            sb.check_true("G5: new cadence ~= PER+1 (=10) lfxt ticks",
                          delta >= 8 and delta <= 12);
            w1c(x"00000004");
            d0 := d1;
        end loop;

        -- The tick engine does not disturb the wall clock: SEC/SUB still track the independent reference.
        read_wall(dut47, ref_lo, ref_hi);
        sb.check_true("G5: wall clock undisturbed by tick engine (tracks reference)",
                      rtc_within(dut47, ref_lo, CMP_BOUND) and (dut47 <= ref_hi));

        -- Hygiene: disable tick engine, clear flags.
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '0', '0', '0', '0'));
        w1c(x"00000006");

        ------------------------------------------------------------------
        -- GROUP G6: combined-IRQ demux + IE masking, irq_rtc = (ALMF and ALMIE) or (TICKF and TICKIE), combinational.
        -- With both flags pending, W1C each in turn (irq drops only when BOTH are cleared), then mask ALMIE / TICKIE independently; engines are frozen with ALMEN/TICKEN=0 first so flags cannot re-arm mid-check.
        ------------------------------------------------------------------
        report "=== GROUP G6: combined-IRQ demux ===" severity note;
        make_both_pending(x"00000300");
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SR, rdw);
        sb.check_bit("G6: ALMF pending", to_X01(rdw(RTC_SR_ALMF)), '1');
        sb.check_bit("G6: TICKF pending", to_X01(rdw(RTC_SR_TICKF)), '1');
        wait for 2 * PERIOD;
        sb.check_bit("G6: irq_rtc high with both flags pending", to_X01(irq_rtc), '1');

        -- Freeze the event engines (keep both IEs) so flags stop re-arming.
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '0', '0', '1', '1'));
        wait for 12 * (2 * LFXT_HALF);

        w1c(x"00000002");                              -- W1C ALMF, leaving only TICKF
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SR, rdw);
        sb.check_bit("G6: ALMF cleared, TICKF still pending", to_X01(rdw(RTC_SR_TICKF)), '1');
        wait for 2 * PERIOD;
        sb.check_bit("G6: irq_rtc still high (TICKF & TICKIE)", to_X01(irq_rtc), '1');
        w1c(x"00000004");                              -- W1C TICKF, none left
        wait for 2 * PERIOD;
        sb.check_bit("G6: irq_rtc drops only when BOTH cleared", to_X01(irq_rtc), '0');

        -- Mask ALMIE=0, TICKIE=1: irq reflects TICKF only.
        make_both_pending(x"00000400");
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '0', '0', '0', '1')); -- freeze, ALMIE=0, TICKIE=1
        wait for 12 * (2 * LFXT_HALF);
        sb.check_bit("G6: ALMIE=0/TICKIE=1 -> irq high from TICKF", to_X01(irq_rtc), '1');
        w1c(x"00000004");                              -- clear TICKF; ALMF still set but masked
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SR, rdw);
        sb.check_bit("G6: ALMF still pending under ALMIE=0", to_X01(rdw(RTC_SR_ALMF)), '1');
        wait for 2 * PERIOD;
        sb.check_bit("G6: irq low with ALMF pending but ALMIE=0 (masked)", to_X01(irq_rtc), '0');

        -- Mask both IE=0: irq stays low with BOTH flags pending.
        make_both_pending(x"00000500");
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '0', '0', '0', '0')); -- freeze, both IE=0
        wait for 12 * (2 * LFXT_HALF);
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SR, rdw);
        sb.check_bit("G6: ALMF pending, IE masked", to_X01(rdw(RTC_SR_ALMF)), '1');
        sb.check_bit("G6: TICKF pending, IE masked", to_X01(rdw(RTC_SR_TICKF)), '1');
        sb.check_bit("G6: irq low with both flags set but both IE=0", to_X01(irq_rtc), '0');

        -- Hygiene: clear flags, back to RTCEN only.
        w1c(x"00000006");

        ------------------------------------------------------------------
        -- GROUP G7a: with the bus IDLE (ClkMem gated off) the flag path still sets TICKF and raises irq_rtc autonomously, observed on the free-running clk with ZERO bus activity in the window.
        -- GROUP G7b: assert resetn mid-count, so the LFXT domain resets cleanly, SEC/SUB/CR read back 0 and the counter restarts from 0.
        ------------------------------------------------------------------
        report "=== GROUP G7: always-on / reset-sync ===" severity note;
        -- Arm a fast tick, then stop touching the bus entirely.
        set_time(x"00000600", "000000000000000");
        bus_write(clk, pbus, RTC_SLOT_PER, x"00000004");
        rtc_wait_sync_clear(clk, pbus, rdata_out, ok);
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '0', '1', '0', '1')); -- RTCEN|TICKEN|TICKIE
        w1c(x"00000006");                              -- clear flags before the idle window
        pbus <= PERIPH_BUS_IDLE;                       -- bus quiescent: ClkMem stops
        wait for 2 * PERIOD;

        ok := false;
        for i in 0 to 400 loop                         -- observe irq only (no bus access)
            wait until clk = '1';
            if to_X01(irq_rtc) = '1' then
                ok := true;
                exit;
            end if;
        end loop;
        sb.check_true("G7a: irq_rtc rose autonomously with the bus idle (D2)", ok);
        w1c(x"00000004");                              -- clear TICKF (bus back)
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '0', '0', '0', '0'));

        -- (b) Reset mid-count.
        wait for 100 * (2 * LFXT_HALF);                -- let it count a while
        resetn <= '0';
        ref_en <= '0';
        wait for 5 * PERIOD;
        resetn <= '1';
        ref_load_val <= (others => '0');               -- zero the TB reference too
        ref_load     <= '1';
        wait for 2 * LFXT_HALF * 2;
        ref_load     <= '0';
        wait for 8 * PERIOD;

        bus_read(clk, pbus, rdata_out, RTC_SLOT_SEC, rdw);
        sb.check_slv("G7b: SEC back to 0 after reset", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SUB, rdw);
        sb.check_slv("G7b: SUB back to 0 after reset", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, RTC_SLOT_CR, rdw);
        sb.check_slv("G7b: CR back to 0 after reset", rdw, x"00000000");
        sb.check_bit("G7b: irq_rtc low after reset", to_X01(irq_rtc), '0');

        -- The counter restarts cleanly.
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '0', '0', '0', '0'));  -- RTCEN
        ref_en <= '1';
        wait for 300 * (2 * LFXT_HALF);
        read_wall(dut47, ref_lo, ref_hi);
        sb.check_true("G7b: counter restarts and advances from 0",
                      dut47 > to_unsigned(0, RTC_CNT_BITS));
        sb.check_true("G7b: restarted count tracks reference within bound",
                      rtc_within(dut47, ref_lo, CMP_BOUND) and (dut47 <= ref_hi));

        ------------------------------------------------------------------
        -- GROUP G-EV: EVFAB taps.
        -- evt_alarm/evt_tick are the same synchronized event edges the sticky ALMF/TICKF flags set from, exported PRE-IE, so ALMIE/TICKIE must have ZERO effect on them; pulse counts come from evt_mon_proc, windowed by evt_mon_reset.
        ------------------------------------------------------------------
        report "=== GROUP G-EV: EVFAB taps (evt_alarm/evt_tick) ===" severity note;

        -- G-EV-a: evt_tick pulse count vs TICKF at PER=4 (cadence 5 lfxt ticks).
        -- Catch and clear the first "prime" tick outside the window, since its phase includes the enable-cross CDC latency, then open the monitor and catch exactly 5 more ticks by SR poll/W1C while counting evt_tick pulses independently.
        bus_write(clk, pbus, RTC_SLOT_PER, x"00000004");   -- PER = 4
        rtc_wait_sync_clear(clk, pbus, rdata_out, ok);
        sb.check_true("G-EV a0: PER commit SR.SYNC cleared", ok);
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '0', '1', '0', '1')); -- RTCEN|TICKEN|TICKIE

        rtc_wait_flag(clk, pbus, rdata_out, RTC_SR_TICKF, '1', ok);
        sb.check_true("G-EV a1: first TICKF observed (bounded, priming the cadence)", ok);
        w1c(x"00000004");

        evt_mon_reset;
        tickcnt := 0;
        for i in 0 to 4 loop                           -- 5 more ticks
            rtc_wait_flag(clk, pbus, rdata_out, RTC_SR_TICKF, '1', ok);
            sb.check_true("G-EV a2: TICKF recurs (bounded wait)", ok);
            w1c(x"00000004");
            tickcnt := tickcnt + 1;
        end loop;
        sb.check_true("G-EV a3: evt_tick pulses exactly N times matching N TICKF events",
                      evt_tick_starts = tickcnt);
        sb.check_true("G-EV a4: every evt_tick pulse is exactly one clk wide (highs = starts)",
                      evt_tick_highs = evt_tick_starts);

        -- Hygiene: disable tick engine, clear flags.
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '0', '0', '0', '0'));
        w1c(x"00000006");

        -- G-EV-b: evt_alarm, one alarm match (near-wrap set-time, ALM = SEC+1, RTCEN|ALMEN|ALMIE), giving exactly one evt_alarm pulse, one clk wide.
        set_time(x"00000700", "111111100000000");      -- SEC=0x700, SUB=0x7F00
        bus_write(clk, pbus, RTC_SLOT_ALM, x"00000701");   -- ALM = 0x701
        rtc_wait_sync_clear(clk, pbus, rdata_out, ok);
        sb.check_true("G-EV b0: ALM commit SR.SYNC cleared", ok);

        evt_mon_reset;
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '1', '0', '1', '0')); -- RTCEN|ALMEN|ALMIE
        rtc_wait_flag(clk, pbus, rdata_out, RTC_SR_ALMF, '1', ok);
        sb.check_true("G-EV b1: ALMF set at the alarm match (bounded wait)", ok);
        sb.check_true("G-EV b2: evt_alarm pulsed exactly once for the alarm match",
                      evt_alarm_starts = 1);
        sb.check_true("G-EV b3: that evt_alarm pulse is exactly one clk wide",
                      evt_alarm_highs = 1);

        -- Hygiene: disable alarm engine, clear flags.
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '0', '0', '0', '0'));
        w1c(x"00000002");

        -- G-EV-c: mask BOTH IE (ALMIE=0, TICKIE=0) and provoke a fresh tick plus alarm with the near-wrap PER=4 / ALM=SEC+1 shape.
        -- evt_tick/evt_alarm must STILL pulse (pre-IE taps) and irq_rtc must stay LOW throughout, proving ALMIE/TICKIE have zero effect on them.
        set_time(x"00000800", "111111100000000");      -- SEC=0x800, SUB=0x7F00
        bus_write(clk, pbus, RTC_SLOT_ALM, x"00000801");   -- ALM = 0x801
        rtc_wait_sync_clear(clk, pbus, rdata_out, ok);
        bus_write(clk, pbus, RTC_SLOT_PER, x"00000004");   -- PER = 4
        rtc_wait_sync_clear(clk, pbus, rdata_out, ok);
        w1c(x"00000006");                                  -- clear any stale flags

        evt_mon_reset;
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '1', '1', '0', '0')); -- RTCEN|ALMEN|TICKEN, both IE=0
        sb.check_bit("G-EV c0: irq_rtc low right after enabling with both IE=0",
                     to_X01(irq_rtc), '0');

        rtc_wait_flag(clk, pbus, rdata_out, RTC_SR_TICKF, '1', ok);
        sb.check_true("G-EV c1: TICKF still sets with TICKIE=0 (bounded wait)", ok);
        sb.check_true("G-EV c2: evt_tick still pulsed (>=1) with TICKIE=0 (pre-IE tap)",
                      evt_tick_starts >= 1);
        sb.check_bit("G-EV c3: irq_rtc stays low with TICKF pending but TICKIE=0",
                     to_X01(irq_rtc), '0');
        w1c(x"00000004");                                  -- W1C TICKF (TICKEN stays on)

        rtc_wait_flag(clk, pbus, rdata_out, RTC_SR_ALMF, '1', ok);
        sb.check_true("G-EV c4: ALMF still sets with ALMIE=0 (bounded wait)", ok);
        sb.check_true("G-EV c5: evt_alarm still pulsed exactly once with ALMIE=0 (pre-IE tap, one-shot)",
                      evt_alarm_starts = 1);
        sb.check_true("G-EV c6: that evt_alarm pulse is exactly one clk wide",
                      evt_alarm_highs = 1);
        sb.check_bit("G-EV c7: irq_rtc stays low with ALMF pending but ALMIE=0",
                     to_X01(irq_rtc), '0');

        -- Hygiene: disable engines, clear flags.
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '0', '0', '0', '0'));
        w1c(x"00000006");

        -- G-EV-d: quiet window, both engines disabled, flags clear, nothing pending, so both taps stay 0 over a bounded window.
        evt_mon_reset;
        wait for 200 * (2 * LFXT_HALF);                    -- ~200 lfxt ticks, idle
        sb.check_true("G-EV d1: evt_tick stays 0 with nothing pending (bounded window)",
                      evt_tick_starts = 0 and evt_tick_highs = 0);
        sb.check_true("G-EV d2: evt_alarm stays 0 with nothing pending (bounded window)",
                      evt_alarm_starts = 0 and evt_alarm_highs = 0);

        ------------------------------------------------------------------
        -- GROUP G-NEG: NEGATIVE CONTROL (mandatory, LAST): exactly ONE deliberately-wrong expected value so the scoreboard proves it can fail.
        -- Compare a freshly-read SEC against a wrong literal.
        ------------------------------------------------------------------
        report "=== GROUP G-NEG: NEGATIVE CONTROL ===" severity note;
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SEC, secw);
        sb.check_slv("NEGATIVE CONTROL: wrong expected SEC (must FAIL)",
                     secw, std_logic_vector(unsigned(secw) + 1));

        ------------------------------------------------------------------
        -- Final verdict: sb.errors must be EXACTLY 1 (the negative control).
        ------------------------------------------------------------------
        wait for 1 us;
        sb.report_summary("RTC TB");

        if sb.errors = 1 then
            report LF & LF &
                "    ##################################################" & LF &
                "    ##   RTC_TB PASS (1 expected negative-control failure)" & LF &
                "    ##   RTC TB:  ALL CHECKS PASSED" & LF &
                "    ##################################################" & LF
                severity note;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   RTC_TB FAIL (expected exactly 1 failure [negative control], got " &
                integer'image(sb.errors) & ")" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        tb_done <= true;
        stop;
        wait;
    end process stim_proc;

end architecture sim;
