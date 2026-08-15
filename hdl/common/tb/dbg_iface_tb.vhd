-- =============================================================================
-- dbg_iface_tb.vhd  (D1 acceptance instrument I2, BLIND-AUTHORED, 2026-08-05)
-- =============================================================================
-- THE PORT-LEVEL CONFORMANCE BENCH for the D1 frozen interface (d1_spec.md 1).
-- It is the ONLY instrument in the D1 set that names the three debug ports and the DEBUG_ENTRY_ADDR generic in VHDL, so its FAIL leg at unimplemented HEAD is an ELABORATION ERROR rather than a verdict word.
-- That is exactly the two-part seen-to-FAIL protocol of d1_spec.md 5 part 1.
--
-- WHAT IT ASSERTS, and why each assertion is not free
-- ---------------------------------------------------------------------------
--   A  INERTNESS OF THE REQUEST-FREE CHIP.
--      ENABLE_DEBUG is TRUE here and both request inputs are held '0', so dbg_halted must stay '0' for the whole window.
--      A build that halts with nobody asking is the worst possible failure of the knob-ON arm, and it would never show up in a knob-OFF gate sweep.
--   B  ENTRY.
--      Raising dbg_haltreq on a RUNNING hart must raise dbg_halted within the budget.
--      The hart really is running: the bench's shared-window responder feeds it NOPs from address 0 upward, so it is executing rather than stalled, as described in the responder note below.
--      A bench whose hart never runs would "pass" this by accident on an implementation that halts only stalled harts.
--   C  HALT IS A STATE, NOT A LEVEL FOLLOWER.
--      After entry, dbg_haltreq is DEASSERTED and dbg_halted must STAY '1'.
--      A real debugger drops haltreq as soon as it sees halted, so an implementation that drives dbg_halted straight from dbg_haltreq, or that resumes when the request goes away, passes A and B and fails only here.
--      d1_spec.md 2 makes resume the exclusive job of dret, and there is no resumereq at D1, so a hart that leaves debug mode on its own has left it for no legal reason.
--   D  FAIL-SAFE TIE-OFF (method rule 15, and d1_spec.md 1's explicit requirement).
--      A SECOND hart_tile instantiated with the three debug ports OMITTED runs the same stimulus window, and it must never halt.
--      This is what proves the ports carry defaults AND that the default direction is the safe one.
--      It is also the shape every MCU-level instantiation has at D1, since no DM exists yet to drive them.
--   E  HALT-ON-RESET.
--      dbg_resethaltreq held across reset release must raise dbg_halted, asserted on the fully connected instance only.
--
-- WHAT IT DELIBERATELY DOES NOT ASSERT
--   dpc, dcsr.cause, dcsr.prv, step, dret and ebreak.
--   All of those are ARCHITECTURAL state readable only by code executing at DEBUG_ENTRY_ADDR, and this bench has no assembler behind it.
--   They are covered in-band by dbghaltmp.S and dbgstepmp.S, which read them with real csrr instructions.
--   Splitting it this way keeps this file small enough to be reviewed line by line, which is the only reason to trust a bench that grades itself.
--
-- THE SHARED-WINDOW RESPONDER
--   30 lines, and deliberately trivial: every read returns 0x00000013, a nop, and every write is accepted and dropped.
--   The hart therefore boots from address 0 (M12 single-ROM boot: PC_RST_VAL = 0, and the core is held in reset until its first boot fetch lands), then retires NOPs with pc walking upward.
--   pc stays inside the shared window, region 000, 0x0-0x3FFF, for 4096 instructions, roughly 20,000 mclk at about 5 mclk per stalled fetch.
--   That is two orders of magnitude beyond every window used below, so the hart is unambiguously RUNNING for the whole test.
--   DEBUG_ENTRY_ADDR is pointed INTO that same window, 0x00000100, so debug entry lands on NOPs rather than on the uninitialised TCM.
--   The bench never asserts what the halted hart executes, only that it is halted.
--   The responder is NOT the mp_arbiter: there is one master, so grant is immediate.
--   Protocol per hart_tile.vhd: req is held until done, and done is a 1-cycle pulse.
--
-- RUN IT:  xcelium/mp_test/run_dbg_iface.sh
-- PASS iff the log prints "ALL CHECKS PASSED" and contains no "CHECK FAILED".
--
-- BLINDNESS NOTE: this was written before any D1 RTL exists.
-- If it fails to elaborate, read the error: that is the instrument working, not the instrument broken.
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

library work;
use work.constants.all;

entity dbg_iface_tb is
end entity;

architecture sim of dbg_iface_tb is

    constant MCLK_PERIOD : time := 41.667 ns;          -- 24 MHz, the chip mclk.
    constant SH_AW_C     : natural := 15;
    -- Deliberately inside the bench responder's window, as described in the header.
    -- This is NOT the shipped default the implementer must choose: the whole point of DEBUG_ENTRY_ADDR being a GENERIC is that a bench may re-aim it.
    constant DBG_ENTRY_C : std_logic_vector(31 downto 0) := x"00000100";

    -- Budgets in mclk cycles, deliberately generous.
    -- Entry latency is unspecified at D1, since halt is sampled at the IRQ recognition sites and a stalled shared access can be several cycles long, so a tight budget would be a calibration rather than a check (method rule 7).
    -- What is being tested is "eventually" versus "never", and 4000 cycles either side of the answer cannot turn one into the other.
    constant W_IDLE  : integer := 2000;   -- A: the window in which it must NOT halt.
    constant W_ENTER : integer := 4000;   -- B and E: the window within which it must halt.
    constant W_HOLD  : integer := 4000;   -- C: the window over which it must STAY halted.

    signal mclk   : std_logic := '0';
    signal resetn : std_logic := '0';
    signal done   : boolean   := false;
    signal fails  : integer   := 0;

    -- Instance 1: every debug port CONNECTED.
    signal t1_haltreq  : std_logic := '0';
    signal t1_rsthalt  : std_logic := '0';
    signal t1_halted   : std_logic;
    signal t1_req      : std_logic;
    signal t1_we       : std_logic_vector(3 downto 0);
    signal t1_addr     : std_logic_vector(SH_AW_C-1 downto 0);
    signal t1_wdata    : std_logic_vector(31 downto 0);
    signal t1_gnt      : std_logic := '0';
    signal t1_done     : std_logic := '0';
    signal t1_rdata    : std_logic_vector(31 downto 0) := (others => '0');
    signal t1_lrsc     : std_logic_vector(1 downto 0);
    signal t1_lock     : std_logic;
    signal t1_a0       : std_logic_vector(31 downto 0);
    signal t1_trap     : std_logic;
    signal t1_fmen     : std_logic;
    signal t1_fclk     : std_logic;
    signal t1_fmab     : std_logic_vector(31 downto 0);

    -- Instance 2: the three debug ports OMITTED, which is the D1 MCU shape.
    signal t2_req      : std_logic;
    signal t2_we       : std_logic_vector(3 downto 0);
    signal t2_addr     : std_logic_vector(SH_AW_C-1 downto 0);
    signal t2_wdata    : std_logic_vector(31 downto 0);
    signal t2_gnt      : std_logic := '0';
    signal t2_done     : std_logic := '0';
    signal t2_rdata    : std_logic_vector(31 downto 0) := (others => '0');
    signal t2_lrsc     : std_logic_vector(1 downto 0);
    signal t2_lock     : std_logic;
    signal t2_a0       : std_logic_vector(31 downto 0);
    signal t2_trap     : std_logic;
    signal t2_fmen     : std_logic;
    signal t2_fclk     : std_logic;
    signal t2_fmab     : std_logic_vector(31 downto 0);

    -- Instance 2's halted line is read through a LOCAL signal that the tile does not drive, so it must stay at its initial '0'.
    -- That is a weaker statement than reading the port, and it is the honest one: an omitted output port cannot be observed at all, and pretending otherwise would be a decorative metric (method rule 9).
    -- What instance 2 really tests is that a tile with the debug INPUTS unconnected still elaborates, boots and RUNS, i.e. that the tie-off direction is '0' and not '1'.
    -- A tile tied haltreq='1' would halt instantly and stop fetching, which check D detects through its shared-window request count.
    signal t2_reqs     : integer := 0;

    -- Report one check and tally it, without ever stopping the run.
    procedure chk(cond : boolean; msg : string; signal f : inout integer) is
    begin
        if cond then
            report "CHECK ok: " & msg severity note;
        else
            -- Severity WARNING, not error: Xcelium stops the run at the first error, and a bench that stops at check B can never tell you whether C, D and E would also have failed.
            -- The runner greps the log instead.
            report "CHECK FAILED: " & msg severity warning;
            f <= f + 1;
        end if;
    end procedure;

begin

    mclk <= not mclk after MCLK_PERIOD / 2 when not done else '0';

    -- -------------------------------------------------------------------
    -- Two shared-window responders, one per tile, as described in the header.
    -- Each sees a single master, so grant is unconditional, and done is a single-cycle pulse one clock after req.
    -- -------------------------------------------------------------------
    resp1: process(mclk)
    begin
        if rising_edge(mclk) then
            t1_done <= '0';
            t1_gnt  <= t1_req;
            if t1_req = '1' and t1_done = '0' and t1_gnt = '1' then
                t1_done  <= '1';
                t1_rdata <= x"00000013";           -- Every read returns a nop.
            end if;
        end if;
    end process;

    -- Same responder for tile 2, but it also counts requests, which is how checks A2 and D observe that the tie-off instance keeps fetching.
    resp2: process(mclk)
    begin
        if rising_edge(mclk) then
            t2_done <= '0';
            t2_gnt  <= t2_req;
            if t2_req = '1' and t2_done = '0' and t2_gnt = '1' then
                t2_done  <= '1';
                t2_rdata <= x"00000013";           -- Every read returns a nop.
                t2_reqs  <= t2_reqs + 1;
            end if;
        end if;
    end process;

    -- -------------------------------------------------------------------
    -- DUT 1: every debug port named, which makes this the elaboration probe.
    -- -------------------------------------------------------------------
    tile1: entity work.hart_tile
        generic map (
            PC_RST_VAL       => x"00000000",
            SH_AW            => SH_AW_C,
            ENABLE_TRAPCSR   => true,      -- R-DD1: debug implies trapCsr.
            ENABLE_DEBUG     => true,
            DEBUG_ENTRY_ADDR => DBG_ENTRY_C
        )
        port map (
            clk       => mclk,
            resetn    => resetn,
            hart_id   => x"00000000",
            dbg_haltreq      => t1_haltreq,
            dbg_resethaltreq => t1_rsthalt,
            dbg_halted       => t1_halted,
            flash_mem_en  => t1_fmen,
            flash_clk_mem => t1_fclk,
            flash_mab     => t1_fmab,
            sh_req    => t1_req,
            sh_we     => t1_we,
            sh_addr   => t1_addr,
            sh_wdata  => t1_wdata,
            sh_gnt    => t1_gnt,
            sh_done   => t1_done,
            sh_rdata  => t1_rdata,
            sh_lrsc   => t1_lrsc,
            sh_lock   => t1_lock,
            trap_flag => t1_trap,
            a0        => t1_a0
        );

    -- -------------------------------------------------------------------
    -- DUT 2: ENABLE_DEBUG on, all three debug ports OMITTED.
    -- This is the shape every MCU.vhd tile has at D1, since no DM exists yet to drive them.
    -- -------------------------------------------------------------------
    tile2: entity work.hart_tile
        generic map (
            PC_RST_VAL       => x"00000000",
            SH_AW            => SH_AW_C,
            ENABLE_TRAPCSR   => true,
            ENABLE_DEBUG     => true,
            DEBUG_ENTRY_ADDR => DBG_ENTRY_C
        )
        port map (
            clk       => mclk,
            resetn    => resetn,
            hart_id   => x"00000001",
            flash_mem_en  => t2_fmen,
            flash_clk_mem => t2_fclk,
            flash_mab     => t2_fmab,
            sh_req    => t2_req,
            sh_we     => t2_we,
            sh_addr   => t2_addr,
            sh_wdata  => t2_wdata,
            sh_gnt    => t2_gnt,
            sh_done   => t2_done,
            sh_rdata  => t2_rdata,
            sh_lrsc   => t2_lrsc,
            sh_lock   => t2_lock,
            trap_flag => t2_trap,
            a0        => t2_a0
        );

    -- -------------------------------------------------------------------
    -- Stimulus: reset both tiles, then run checks A through E in order.
    -- -------------------------------------------------------------------
    stim: process
        variable halted_seen : boolean;
        variable reqs_a      : integer;
    begin
        report "dbg_iface_tb: D1 port-conformance bench starting" severity note;
        t1_haltreq <= '0';
        t1_rsthalt <= '0';
        resetn     <= '0';
        for i in 0 to 19 loop wait until rising_edge(mclk); end loop;
        resetn <= '1';

        -- ---- A: a request-free chip must never halt. ---------------------
        halted_seen := false;
        for i in 0 to W_IDLE-1 loop
            wait until rising_edge(mclk);
            if t1_halted = '1' then halted_seen := true; end if;
        end loop;
        chk(not halted_seen,
            "A: dbg_halted stayed low with no halt request (knob-ON inertness)",
            fails);
        reqs_a := t2_reqs;
        chk(reqs_a > 4,
            "A2: the tie-off instance is RUNNING (shared fetches observed) -- "
            & "proves the omitted-port default is '0', not '1'", fails);

        -- ---- B: entry on a running hart. -------------------------------
        t1_haltreq <= '1';
        halted_seen := false;
        for i in 0 to W_ENTER-1 loop
            wait until rising_edge(mclk);
            if t1_halted = '1' then halted_seen := true; end if;
        end loop;
        chk(halted_seen, "B: dbg_haltreq raised dbg_halted on a running hart",
            fails);

        -- ---- C: halt is a state, not a level follower. ------------------
        t1_haltreq <= '0';
        halted_seen := true;
        for i in 0 to W_HOLD-1 loop
            wait until rising_edge(mclk);
            if t1_halted = '0' then halted_seen := false; end if;
        end loop;
        chk(halted_seen,
            "C: dbg_halted STAYED high after dbg_haltreq was dropped "
            & "(only dret may resume)", fails);

        -- ---- D: the tie-off instance never halted and kept fetching. ----
        chk(t2_reqs > reqs_a,
            "D: the omitted-debug-port tile kept fetching throughout "
            & "(it never halted itself)", fails);

        -- ---- E: halt on reset. -----------------------------------------
        resetn     <= '0';
        t1_haltreq <= '0';
        t1_rsthalt <= '1';
        for i in 0 to 19 loop wait until rising_edge(mclk); end loop;
        resetn <= '1';
        halted_seen := false;
        for i in 0 to W_ENTER-1 loop
            wait until rising_edge(mclk);
            if t1_halted = '1' then halted_seen := true; end if;
        end loop;
        chk(halted_seen,
            "E: dbg_resethaltreq held across reset release raised dbg_halted",
            fails);

        wait for 1 us;
        if fails = 0 then
            report "ALL CHECKS PASSED" severity note;
        else
            report "dbg_iface_tb: FAILURES" severity note;
        end if;
        done <= true;
        wait;
    end process;

end architecture;
