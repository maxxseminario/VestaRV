-- =============================================================================
-- dbg_iface_tb.vhd: port-level conformance bench for the hart_tile debug interface (dbg_haltreq, dbg_resethaltreq, dbg_halted and the DEBUG_ENTRY_ADDR generic), checking inertness with no request pending, entry on a running hart, halt as a latched state, the fail-safe tie-off of an instance with the ports omitted, and halt on reset; run it with xcelium/mp_test/run_dbg_iface.sh, PASS iff the log prints "ALL CHECKS PASSED" and contains no "CHECK FAILED".
-- It deliberately does NOT assert dpc, dcsr.cause, dcsr.prv, step, dret or ebreak: those are architectural state readable only by code executing at DEBUG_ENTRY_ADDR, and this bench has no assembler behind it.
-- Shared-window responder: one master, so grant is unconditional and done is a one-cycle pulse after a req held until done, every read returns 0x00000013 (a nop) and every write is dropped, so each tile boots from address 0 and retires NOPs with pc walking up inside the window for far longer than any window used below, and DEBUG_ENTRY_ADDR is aimed into that same window so debug entry lands on NOPs rather than on uninitialised TCM.
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
    -- Aimed inside the bench responder's window, not at the shipped default: DEBUG_ENTRY_ADDR is a generic precisely so a bench can re-aim it.
    constant DBG_ENTRY_C : std_logic_vector(31 downto 0) := x"00000100";

    -- Budgets in mclk cycles, deliberately generous: entry latency is unspecified (halt is sampled at the IRQ recognition sites and a stalled shared access lasts several cycles), so a tight budget would calibrate rather than check.
    -- What is tested is "eventually" versus "never".
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

    -- Instance 2: the three debug ports OMITTED, the shape an MCU tile has with no Debug Module driving them.
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

    -- An omitted output port cannot be observed, so instance 2 instead proves that a tile with the debug INPUTS unconnected still elaborates, boots and RUNS, i.e. that the tie-off direction is '0'.
    -- A tile tied haltreq='1' would halt instantly and stop fetching, which check D catches through this shared-window request count.
    signal t2_reqs     : integer := 0;

    -- Report one check and tally it, without ever stopping the run.
    procedure chk(cond : boolean; msg : string; signal f : inout integer) is
    begin
        if cond then
            report "CHECK ok: " & msg severity note;
        else
            -- Severity WARNING, not error: an error stops the run at the first failure and hides every later check, so the runner greps the log instead.
            report "CHECK FAILED: " & msg severity warning;
            f <= f + 1;
        end if;
    end procedure;

begin

    mclk <= not mclk after MCLK_PERIOD / 2 when not done else '0';

    -- Two shared-window responders, one per tile: each sees a single master, so grant is unconditional and done is a single-cycle pulse one clock after req.
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

    -- Same responder for tile 2, plus a request count: that is how checks A2 and D observe that the tie-off instance keeps fetching.
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

    -- DUT 1: every debug port named, which makes this the elaboration probe.
    tile1: entity work.hart_tile
        generic map (
            PC_RST_VAL       => x"00000000",
            SH_AW            => SH_AW_C,
            ENABLE_TRAPCSR   => true,      -- Debug implies trapCsr.
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

    -- DUT 2: ENABLE_DEBUG on with all three debug ports OMITTED, the shape an MCU.vhd tile has when no Debug Module drives them.
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

    -- Stimulus: reset both tiles, then run checks A through E in order.
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
        -- ENABLE_DEBUG is on and both request inputs are held low, so a build that halts with nobody asking fails here and in no other gate.
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
        -- The responder feeds NOPs from address 0 upward, so the hart is genuinely executing and not merely stalled.
        t1_haltreq <= '1';
        halted_seen := false;
        for i in 0 to W_ENTER-1 loop
            wait until rising_edge(mclk);
            if t1_halted = '1' then halted_seen := true; end if;
        end loop;
        chk(halted_seen, "B: dbg_haltreq raised dbg_halted on a running hart",
            fails);

        -- ---- C: halt is a state, not a level follower. ------------------
        -- A debugger drops haltreq as soon as it sees halted, so an implementation that drives dbg_halted from the request passes A and B and fails only here; only dret may resume.
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
        -- This is what proves the omitted debug ports carry defaults and that the default direction is the safe one.
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
