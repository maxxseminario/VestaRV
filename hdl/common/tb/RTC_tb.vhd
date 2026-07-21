-------------------------------------------------------------------------------
-- RTC_tb.vhd
-------------------------------------------------------------------------------
-- Standalone, self-checking testbench for the RTC real-time-clock peripheral
-- (hdl/common/periph/RTC.vhd), written AGAINST THE FROZEN ENTITY + REGISTER MAP
-- (~/vesta_docs/digperiphs/rtc_design.md, D1-D17 + orchestrator A1-A4) while the
-- RTL is written in parallel. The DUT is declared as a COMPONENT (not an entity
-- instantiation) so this bench compiles standalone with xmvhdl before RTC.vhd
-- exists; VHDL default binding resolves it to the entity of the same name once
-- RTC.vhd is analyzed into the work library. Mirrors NFC_tb.vhd's structure.
--
-- Uses the shared support packages tb/periph_tb_pkg.vhd (scoreboard +
-- register-bus BFM) and tb/rtc_bfm_pkg.vhd (RTC slot/CR/SR constants, the
-- rtc_mk_cr packer, the reference-counter helpers rtc_combined/rtc_within, and
-- the bounded SR polls rtc_wait_sync_clear / rtc_wait_flag).
--
-- THREE clock domains (design doc D1/D2):
--   * clk     : the free-running fast reference (bound to MCLK at integration,
--               A2). Hosts the LFXT->bus CDC synchronizers, the mclk-domain
--               sticky W1C flags and the combinational IRQ combiner. Also the
--               reference clock the register-bus BFM times off. 20 ns period.
--   * ClkMem  : the GATED bus clock -- ticks only while EnMemPeriph='0', driven
--               clk when b.en_mem = '0' else '0' (periph_tb_pkg idiom).
--   * lfxt_in : the UNGATED 32.768 kHz always-on wall clock (D1). Compressed to
--               a brisk 100 ns period here (5x slower than clk) so the 2-FF CDC
--               sees a real fast/slow ratio; the 32768 prescaler modulus is
--               FIXED (exact 1 Hz, D6) so nothing is scaled to wall clock.
--
-- CHECKER INDEPENDENCE (mandatory): the bench keeps its OWN 47-bit wall-clock
-- reference (ref_count) by counting lfxt_in RISING edges in TB code -- it NEVER
-- reads a DUT internal -- and hand-computes the expected alarm/tick instants.
-- Every SEC/SUB compare allows the D7 snapshot staleness (a DUT read is a
-- coherent snapshot <= ~1 lfxt period + ~3 clk behind the live count, and is
-- never AHEAD of the live count): the reference is sampled in a [lo,hi] window
-- around the read and the DUT value must sit within CMP_BOUND of it.
--
-- to_X01 normalizes every sampled DUT LEVEL where a weak/meta level could
-- appear (irq_rtc, and the single SR/flag bits polled in rtc_bfm_pkg). Full
-- reset-default word reads are compared RAW so an uninitialized X is caught.
--
-- COMPRESSED TIMING: brisk lfxt (100 ns) + set-time jumps near a prescaler wrap
-- make every alarm/tick match arrive in a few hundred lfxt ticks, so the whole
-- run is well under a millisecond of sim time and the 1-minute rule. A
-- top-level watchdog aborts with a FAIL banner if the stimulus ever hangs.
--
-- DEVIATIONS / clarifications vs the design doc bench plan noted while writing
-- (flagged, not resolved -- see the bench author's report):
--   * The doc's "|ref - dut| <= 2 lfxt ticks" bound is honored as the SNAPSHOT
--     staleness; a slightly larger CMP_BOUND folds in the enable-cross / commit
--     CDC skew (2-FF held-level and toggle-handshake latency) that also
--     separates the TB reference start from the DUT's, since neither the enable
--     nor the set-time commit cross instantaneously. Named-constant + windowed
--     so it is trivially retuned once the real RTL is connected.
--   * rtc_wait_sync_clear / rtc_wait_flag copy nfc_bfm_pkg's calling convention
--     EXACTLY (done_ok : out boolean); the caller turns done_ok into the
--     scoreboard fail, rather than passing the protected-type scoreboard into
--     the procedure (kept out for -V200X portability).
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

    constant PERIOD   : time    := 20 ns;    -- clk / bus reference (free-running ref, A2)
    constant LFXT_HALF: time    := 50 ns;    -- lfxt_in half period => 100 ns wall-clock tick

    -- Snapshot-staleness + CDC-skew tolerance, in lfxt ticks, for every
    -- reference-vs-DUT combined-value compare (see the header deviation note).
    -- Budget: D7 read-snapshot staleness (1-2 ticks) + wr_req/enable 2-FF sync +
    -- edge-detect apply delay behind the write-time reference anchor (2-4 ticks)
    -- + 1-2 ticks poll/phase jitter. Real failures (missed carry, wrong load)
    -- miss by >= thousands of ticks, so 8 stays a sharp discriminator.
    constant CMP_BOUND : natural := 8;

    -- FROZEN DUT entity (design doc D3), declared as a component so the bench
    -- compiles standalone before hdl/common/periph/RTC.vhd exists.
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
            rdata_out   : out std_logic_vector(31 downto 0)
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

    -- ---- TB independent wall-clock reference (checker independence) -------
    -- ref_count counts lfxt_in rising edges while ref_en='1'; ref_load anchors
    -- it to ref_load_val (applied on the next lfxt rising edge) at each set-time
    -- commit so subsequent groups track the loaded time. NEVER driven from any
    -- DUT internal.
    signal ref_count    : unsigned(RTC_CNT_BITS - 1 downto 0) := (others => '0');
    signal ref_en       : std_logic := '0';
    signal ref_load     : std_logic := '0';
    signal ref_load_val : unsigned(RTC_CNT_BITS - 1 downto 0) := (others => '0');

    signal tb_done : boolean := false;

    shared variable sb : scoreboard;

begin

    ----------------------------------------------------------------------------
    -- clock / gated register-bus clock (mirrors NFC_tb / I2C_tb / I3C_tb)
    ----------------------------------------------------------------------------
    clk     <= not clk after PERIOD / 2;
    lfxt_in <= not lfxt_in after LFXT_HALF;
    ClkMem  <= clk when pbus.en_mem = '0' else '0';

    ----------------------------------------------------------------------------
    -- Independent reference wall clock: counts lfxt_in rising edges (checker
    -- independence). Anchored by ref_load at each set-time commit.
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
            rdata_out   => rdata_out
        );

    ----------------------------------------------------------------------------
    -- Watchdog: abort with a FAIL banner if the stimulus ever hangs (cloned
    -- from the NFC/I3C bounded-abort idiom). Expected sim time is < 1 ms; this
    -- fires only on a true hang. std.env.stop from stim kills it on a clean run.
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

        -- W1C the given SR mask, then a dummy CR read to retire the gated-ClkMem
        -- write pulse before the next SR read (the NFC/QSPI/UART clear idiom).
        procedure w1c(mask : std_logic_vector(31 downto 0)) is
            variable r : std_logic_vector(31 downto 0);
        begin
            bus_write(clk, pbus, RTC_SLOT_SR, mask);
            bus_read (clk, pbus, rdata_out, RTC_SLOT_CR, r);
        end procedure;

        -- Read the coherent SEC/SUB snapshot pair and return the TB 47-bit
        -- combined value plus the reference window [ref_lo, ref_hi] captured
        -- around the two bus reads.
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

        -- Set-time to {sec, sub}: stage SUB, commit both by writing SEC, poll
        -- SR.SYNC busy->clear (D8), and anchor the TB reference to the same
        -- value. Leaves the wall clock counting from {sec, sub}.
        procedure set_time(sec : std_logic_vector(31 downto 0);
                           sub : std_logic_vector(14 downto 0)) is
            variable done_ok : boolean;
        begin
            bus_write(clk, pbus, RTC_SLOT_SUB, x"0000" & '0' & sub);   -- stage SUB [14:0]
            -- Anchor the reference AT the commit write (one lfxt edge), BEFORE the
            -- SYNC poll: the DUT applies the load ~2-4 lfxt edges later (wr_req
            -- 2-FF sync + edge detect), so the DUT then runs a constant 2-4 ticks
            -- BEHIND the reference -- the correct direction for dut <= ref_hi, and
            -- inside CMP_BOUND together with the D7 snapshot staleness. (Anchoring
            -- after the SYNC-clear poll put the DUT AHEAD of the reference --
            -- first-run G3/G5 failures.)
            ref_load_val <= unsigned(sec) & unsigned(sub);
            ref_load     <= '1';
            bus_write(clk, pbus, RTC_SLOT_SEC, sec);                   -- commit {SEC,SUB}
            wait for 2 * LFXT_HALF;        -- ~1 lfxt period: exactly 1-2 anchor edges
            ref_load     <= '0';
            rtc_wait_sync_clear(clk, pbus, rdata_out, done_ok);
            sb.check_true("set_time: SR.SYNC asserted then cleared (D8)", done_ok);
        end procedure;

        -- Make BOTH ALMF and TICKF pending: jump near a prescaler wrap, arm an
        -- alarm one second out and a fast periodic tick, then wait for the alarm
        -- match (by which time several ticks have also fired). Leaves both
        -- engines enabled with both sticky flags set. Used by G6.
        procedure make_both_pending(secbase : std_logic_vector(31 downto 0)) is
            variable done_ok : boolean;
        begin
            set_time(secbase, "111111100000000");         -- SUB = 0x7F00 (256 from wrap)
            bus_write(clk, pbus, RTC_SLOT_ALM,
                      std_logic_vector(unsigned(secbase) + 1));
            rtc_wait_sync_clear(clk, pbus, rdata_out, done_ok);
            bus_write(clk, pbus, RTC_SLOT_PER, x"00000004");
            rtc_wait_sync_clear(clk, pbus, rdata_out, done_ok);
            -- Clear any STALE flags left by a previous leg (a masked ALMF left
            -- pending would satisfy the ALMF wait instantly, freezing the engines
            -- before any tick fires -- first-run G6 leg-3 failure), THEN enable
            -- and wait for BOTH flags to be freshly pending.
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
        -- GROUP G0: reset defaults (design doc G0)
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
        -- GROUP G1: wall-clock advance (design doc G1)
        -- Enable RTCEN, start the TB reference at the SAME moment, run a few
        -- thousand lfxt ticks and confirm the DUT snapshot advances
        -- monotonically and tracks the independent reference within the
        -- staleness/CDC bound (dut is never AHEAD of the reference, D7).
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
        -- GROUP G2: coherent snapshot (design doc G2)
        -- The firmware SEC,SUB,SEC-recompare idiom (D7): repeated reads are
        -- never torn and each coherent pair tracks the reference within bound.
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
                -- SEC unchanged across the pair => the SEC/SUB pair is coherent.
                sb.check_true("G2: coherent pair SUB in range (< 32768)",
                              to_integer(unsigned(subw(RTC_SUB_BITS - 1 downto 0))) < RTC_SUB_MOD);
                sb.check_true("G2: coherent pair within staleness bound of reference",
                              rtc_within(dut47, ref_lo, CMP_BOUND) and (dut47 <= ref_hi));
                sb.check_true("G2: coherent pair monotonic vs previous read",
                              dut47 >= prev47);
                prev47 := dut47;
            else
                -- SEC ticked mid-idiom (allowed): the driver would retry. Just
                -- confirm the second SEC did not go backwards.
                sb.check_true("G2: SEC recompare only advances (retry case)",
                              unsigned(rdw) >= unsigned(secw));
            end if;
            wait for 40 * (2 * LFXT_HALF);
        end loop;

        ------------------------------------------------------------------
        -- GROUP G3: set-time (design doc G3)
        -- Stage SUB then commit SEC (atomic {SEC,SUB} load, D8); SR.SYNC
        -- asserts then clears; read-back equals the loaded value; counting
        -- resumes from it; a sub-carry set-time increments SEC by exactly one.
        ------------------------------------------------------------------
        report "=== GROUP G3: set-time ===" severity note;
        -- Stage SUB=0x3FF0, commit SEC=0x12345678 (set_time waits SR.SYNC and
        -- anchors the TB reference).
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

        -- Sub-carry: load SUB=0x7FF0 (16 ticks from wrap) so SEC increments by
        -- exactly one at the prescaler roll-over. Read SEC before and after.
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
        -- GROUP G4: alarm (design doc G4)
        -- Compressed via the set-time-near-wrap trick: SUB loaded at 0x7F00 is
        -- 256 lfxt ticks from the prescaler roll-over, so an alarm at SEC+1
        -- fires ~256 ticks later. Prove: fire + irq; W1C clears + drops irq;
        -- one-shot (no re-fire across the match second); re-arm fires again;
        -- ALMEN=0 suppresses. (This proves the same one-shot/re-arm contract as
        -- the doc's SEC=0x101 double-set choreography, using a wait-and-confirm
        -- for the "no re-fire" leg -- flagged in the bench author's report.)
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

        -- G4b: W1C ALMF -> clears + irq drops.
        w1c(x"00000002");                              -- W1C ALMF
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SR, rdw);
        sb.check_bit("G4b: ALMF cleared after W1C", to_X01(rdw(RTC_SR_ALMF)), '0');
        wait for 4 * PERIOD;
        sb.check_bit("G4b: irq_rtc dropped after ALMF W1C", to_X01(irq_rtc), '0');

        -- G4c: one-shot -- with ALM unchanged, SEC rolls from 0x101 to 0x102
        -- (leaving the match, no new rising edge of equality) -> no re-fire.
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

        -- G4e: ALMEN=0 suppression -- program a match but leave ALMEN clear.
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
        -- GROUP G5: periodic tick (design doc G5)
        -- PER=4 -> a tick every PER+1 = 5 lfxt ticks (D12). Catch N consecutive
        -- ticks, W1C each, and check the cadence against the independent
        -- lfxt-edge reference (delta ~= PER+1). Reprogram PER=9 -> cadence 10.
        -- Confirm the wall clock (SEC/SUB) is undisturbed by the tick engine.
        ------------------------------------------------------------------
        report "=== GROUP G5: periodic tick ===" severity note;
        bus_write(clk, pbus, RTC_SLOT_PER, x"00000004");   -- PER = 4
        rtc_wait_sync_clear(clk, pbus, rdata_out, ok);
        sb.check_true("G5: PER commit SR.SYNC cleared", ok);
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '0', '1', '0', '1')); -- RTCEN|TICKEN|TICKIE

        -- prime: catch and clear the first tick (its phase includes the enable
        -- cross), then measure the cadence of the following ticks.
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

        -- Reprogram PER=9 -> cadence 10; check the new spacing.
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

        -- The tick engine does not disturb the wall clock (D12): SEC/SUB still
        -- track the independent reference.
        read_wall(dut47, ref_lo, ref_hi);
        sb.check_true("G5: wall clock undisturbed by tick engine (tracks reference)",
                      rtc_within(dut47, ref_lo, CMP_BOUND) and (dut47 <= ref_hi));

        -- Hygiene: disable tick engine, clear flags.
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '0', '0', '0', '0'));
        w1c(x"00000006");

        ------------------------------------------------------------------
        -- GROUP G6: combined-IRQ demux + IE masking (design doc G6)
        -- irq_rtc = (ALMF & ALMIE) or (TICKF & TICKIE), combinational (D13).
        -- With both flags pending: W1C each in turn -> irq drops only when BOTH
        -- are cleared; then mask ALMIE / TICKIE independently to prove the
        -- gating. Event engines are frozen (ALMEN/TICKEN=0) before clearing so
        -- flags don't re-arm under us.
        ------------------------------------------------------------------
        report "=== GROUP G6: combined-IRQ demux ===" severity note;
        make_both_pending(x"00000300");
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SR, rdw);
        sb.check_bit("G6: ALMF pending", to_X01(rdw(RTC_SR_ALMF)), '1');
        sb.check_bit("G6: TICKF pending", to_X01(rdw(RTC_SR_TICKF)), '1');
        wait for 2 * PERIOD;
        sb.check_bit("G6: irq_rtc high with both flags pending", to_X01(irq_rtc), '1');

        -- freeze the event engines (keep both IEs) so flags stop re-arming.
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '0', '0', '1', '1'));
        wait for 12 * (2 * LFXT_HALF);

        w1c(x"00000002");                              -- W1C ALMF -> only TICKF left
        bus_read(clk, pbus, rdata_out, RTC_SLOT_SR, rdw);
        sb.check_bit("G6: ALMF cleared, TICKF still pending", to_X01(rdw(RTC_SR_TICKF)), '1');
        wait for 2 * PERIOD;
        sb.check_bit("G6: irq_rtc still high (TICKF & TICKIE)", to_X01(irq_rtc), '1');
        w1c(x"00000004");                              -- W1C TICKF -> none left
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
        -- GROUP G7: always-on / reset-sync (design doc G7)
        -- (a) With the bus IDLE (ClkMem gated off), the smclk-hosted flag path
        --     (D2) still sets TICKF and raises irq_rtc autonomously -- observed
        --     on the free-running clk with ZERO bus activity in the window.
        -- (b) Assert resetn mid-count: the LFXT domain resets cleanly (D14),
        --     SEC/SUB/CR read back 0 and the counter restarts from 0.
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

        -- (b) reset mid-count.
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

        -- counter restarts cleanly.
        bus_write(clk, pbus, RTC_SLOT_CR, rtc_mk_cr('1', '0', '0', '0', '0'));  -- RTCEN
        ref_en <= '1';
        wait for 300 * (2 * LFXT_HALF);
        read_wall(dut47, ref_lo, ref_hi);
        sb.check_true("G7b: counter restarts and advances from 0",
                      dut47 > to_unsigned(0, RTC_CNT_BITS));
        sb.check_true("G7b: restarted count tracks reference within bound",
                      rtc_within(dut47, ref_lo, CMP_BOUND) and (dut47 <= ref_hi));

        ------------------------------------------------------------------
        -- GROUP G-NEG: NEGATIVE CONTROL (mandatory, LAST) -- exactly ONE
        -- deliberately-wrong expected value so the scoreboard proves it can
        -- fail. Compare a freshly-read SEC against a wrong literal.
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
