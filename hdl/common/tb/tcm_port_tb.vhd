-- =============================================================================
-- tcm_port_tb.vhd  (CPR2 unit bench for the external TCM slave port, R4)
-- =============================================================================
-- Drives the REAL hart_tile -- a real vesta core, a real adddec, a real
-- sram1p16k_hvt_pg -- through the new tcm_ext_* port while the core is
-- genuinely executing out of a shared-window BFM.  Nothing here is a model of
-- the tile; the only models are the shared bus (one master, so no arbiter) and
-- the external requester.
--
-- WHY THE CORE HAS TO BE RUNNING FOR ANY OF THIS TO MEAN ANYTHING
--   The port's entire risk is CONCURRENCY: it borrows an SRAM port out from
--   under a core that is using it.  A bench that reads a quiescent tile's TCM
--   proves only that a mux exists.  So the tile is booted for real (M12
--   contract: PC_RST_VAL = 0, the core is held in reset by core_rst_stretch
--   until its first boot fetch has LANDED, so the shared BFM must serve
--   address 0 or the core never leaves reset at all), and it is given a real
--   instruction stream that writes known patterns into its own TCM and then
--   spins re-reading and re-checking them forever.  Every external read below
--   happens against that live traffic.
--
-- THE PROGRAM (hand-assembled; the machine words in PROG_IMG were produced by
-- riscv-none-elf-as -march=rv32i and the disassembly is in the comment column,
-- so the two can be diffed by eye).  It executes FROM THE SHARED WINDOW, which
-- is legal since M10 (shexec) and is what a tile does during boot anyway; its
-- DATA lives in the private TCM, which is the split this bench needs.
--     fill   TCM word i (byte 0x8000+4i) <- 0xA5A50000+i, i = 0..15
--     poison TCM word 100 (byte 0x8190)  <- 0xDEADBEEF
--     ready  shared 0x10000              <- 0x11111111
--     loop   re-read TCM words 0..15, compare against 0xA5A50000+i,
--            count mismatches, and publish
--                shared 0x10004 = outer-iteration count  (LIVENESS)
--                shared 0x10008 = mismatch count         (CORRECTNESS)
--   Those two shared words are the core's own verdict on its own memory, and
--   they are how the bench sees a corruption it can never observe directly.
--   The POISON WORD is what makes that verdict sharp: the hammer below reads
--   TCM word 100 (0xDEADBEEF), a value that appears NOWHERE in the range the
--   core is checking, so any leakage of external read data into the core's
--   load path is a guaranteed mismatch rather than a coincidence away from
--   being invisible.
--
-- THE TESTS
--   T1  BASIC.       After the core publishes READY, read all 17 planted words
--                    back through tcm_ext_* and compare.  The port sees what
--                    the core wrote.
--   T2  CONTENTION.  Sweep the same 17 words repeatedly WHILE the core is in
--                    its check loop.  Both sides must be right: every external
--                    read correct AND the core's mismatch count still 0 AND
--                    its iteration count still advancing.
--   T3  SELF-PROGRESS.  Back-to-back external reads with the minimum legal gap,
--                    sustained.  The core's iteration count must still advance
--                    DURING the hammer -- the stall is bounded, not a livelock
--                    -- and must advance again after it stops.
--   T4  NEGATIVE CONTROL.  Not in this file: it is an RTL mutation (drop the Q
--                    shadow, or switch the ram0 mux on the raw request) re-run
--                    against T2.  See xcelium/mp_test/run_tcm_port.sh's header.
--   T5  HANDSHAKE.   done is exactly one mclk wide; rdata is valid with it and
--                    HOLDS afterwards; back-to-back transactions work; and a
--                    request asserted during reset is ignored (no done, no
--                    rdata, no SRAM access).
--   T6  SELF-ACCESS / LONG FREEZE (CPR3b, amendment A3).  The case CPR2 could
--                    not build and CPR3 found in silico: a core frozen on its
--                    OWN shared transaction for LONGER than the external
--                    transaction it is contending with.  In the chip that is a
--                    hart reading its own TCM window -- the aperture sequencer
--                    holds the arbiter in LATCH (mp_arbiter s_stall) while it
--                    drives this very tile's tcm_ext_* port, so the requesting
--                    core's freeze strictly contains the port's tx_busy
--                    window.  Here the shared BFM reproduces exactly that
--                    topology without needing an arbiter or an MCU: it STALLS
--                    the fetch that the core issues while it is in MEMORY_WAIT
--                    on a TCM load (data_addr = pc_next there, and this
--                    program's pc is in the shared window -- so the load's
--                    result must survive on mem_dout(1) for the whole length
--                    of that fetch transaction), and the external read is
--                    fired INSIDE that stall.  Pre-A3, the Q-shadow hold was
--                    tx_busy+1 and expired inside the freeze; the core then
--                    consumed the external word as its load result and its own
--                    mismatch counter says so.  The instruction-fetch flavour
--                    of the same window is the chip-level measurement (PC
--                    0x83E0 -> 0x842E); the mechanism and the fix are one.
--
-- Every check is self-grading.  PASS iff the log prints "ALL CHECKS PASSED"
-- and contains no "CHECK FAILED".  Severity is WARNING, not ERROR, on purpose:
-- Xcelium stops at the first `error` and a bench that stops at T1 cannot tell
-- you whether T2/T3/T5 would also have failed.
--
-- RUN IT:  xcelium/mp_test/run_tcm_port.sh
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

library work;
use work.constants.all;

entity tcm_port_tb is
end entity;

architecture sim of tcm_port_tb is

    constant MCLK_PERIOD : time    := 41.667 ns;   -- 24 MHz, the chip mclk
    constant SH_AW_C     : natural := 15;          -- the Castalia shape

    -- shared-window BFM geometry.  Two disjoint regions, nothing else exists:
    --   word 0..63          = byte 0x0..0xFF     : the instruction stream
    --   word 0x4000..0x400F = byte 0x10000..0x1003F : the core's report words
    -- Anything else reads zeros and swallows writes, exactly like the real
    -- unmapped gap.
    constant SH_RPT_BASE : integer := 16#4000#;
    constant RPT_READY   : integer := 0;           -- 0x10000
    constant RPT_ITERS   : integer := 1;           -- 0x10004
    constant RPT_ERRS    : integer := 2;           -- 0x10008
    constant READY_MAGIC : std_logic_vector(31 downto 0) := x"11111111";

    -- TCM plant
    constant N_PLANT     : integer := 16;          -- words 0..15
    constant PLANT_BASE  : std_logic_vector(31 downto 0) := x"a5a50000";
    constant POISON_IDX  : integer := 100;         -- TCM word 100 = byte 0x8190
    constant POISON_VAL  : std_logic_vector(31 downto 0) := x"deadbeef";

    type mem_t is array (0 to 63) of std_logic_vector(31 downto 0);

    -- The instruction stream.  riscv-none-elf-as -march=rv32i -mabi=ilp32,
    -- .option norvc (compressed execute-from-shared is UNTESTED chip-wide --
    -- see the shexec bullet in CLAUDE.md -- so this stream is all 32-bit).
    constant PROG_IMG : mem_t := (
        16#00# => x"000082b7",   -- lui   t0,0x8            ; t0 = 0x8000 TCM base
        16#01# => x"a5a50337",   -- lui   t1,0xa5a50        ; t1 = 0xa5a50000
        16#02# => x"00000393",   -- li    t2,0              ; i
        16#03# => x"01000e93",   -- li    t4,16             ; N
        -- fill:
        16#04# => x"00730e33",   -- add   t3,t1,t2
        16#05# => x"01c2a023",   -- sw    t3,0(t0)
        16#06# => x"00428293",   -- addi  t0,t0,4
        16#07# => x"00138393",   -- addi  t2,t2,1
        16#08# => x"ffd398e3",   -- bne   t2,t4,fill
        -- poison:
        16#09# => x"deadce37",   -- lui   t3,0xdeadc
        16#0a# => x"eefe0e13",   -- addi  t3,t3,-273        ; t3 = 0xdeadbeef
        16#0b# => x"000082b7",   -- lui   t0,0x8
        16#0c# => x"19028293",   -- addi  t0,t0,400         ; t0 = 0x8190 (word 100)
        16#0d# => x"01c2a023",   -- sw    t3,0(t0)
        -- ready:
        16#0e# => x"000105b7",   -- lui   a1,0x10           ; a1 = 0x10000
        16#0f# => x"11111637",   -- lui   a2,0x11111
        16#10# => x"11160613",   -- addi  a2,a2,273         ; a2 = 0x11111111
        16#11# => x"00c5a023",   -- sw    a2,0(a1)          ; READY
        16#12# => x"00000693",   -- li    a3,0              ; errors
        16#13# => x"00000713",   -- li    a4,0              ; iterations
        -- loop:
        16#14# => x"000082b7",   -- lui   t0,0x8
        16#15# => x"00000393",   -- li    t2,0
        -- inner:
        16#16# => x"0002ae03",   -- lw    t3,0(t0)          ; THE victim load
        16#17# => x"00730f33",   -- add   t5,t1,t2          ; expected
        16#18# => x"01ee0463",   -- beq   t3,t5,ok
        16#19# => x"00168693",   -- addi  a3,a3,1           ; MISMATCH
        -- ok:
        16#1a# => x"00428293",   -- addi  t0,t0,4
        16#1b# => x"00138393",   -- addi  t2,t2,1
        16#1c# => x"ffd394e3",   -- bne   t2,t4,inner
        16#1d# => x"00170713",   -- addi  a4,a4,1
        16#1e# => x"00e5a223",   -- sw    a4,4(a1)          ; publish iterations
        16#1f# => x"00d5a423",   -- sw    a3,8(a1)          ; publish errors
        16#20# => x"fd1ff06f",   -- j     loop
        others => x"00000000"
    );

    -- budgets, in mclk.  Generous on purpose: what is under test is
    -- "eventually" vs "never" and "bounded" vs "livelock", and a tight budget
    -- would be a calibration rather than a check.
    constant W_BOOT   : integer := 60000;   -- READY must appear within
    constant W_XACT   : integer := 200;     -- one external read must complete within
    constant W_PROG   : integer := 60000;   -- the core must advance an iteration within

    signal mclk   : std_logic := '0';
    signal resetn : std_logic := '0';
    signal tb_end : boolean   := false;
    signal fails  : integer   := 0;

    -- shared-window BFM <-> tile
    signal sh_req    : std_logic;
    signal sh_we     : std_logic_vector(3 downto 0);
    signal sh_addr   : std_logic_vector(SH_AW_C-1 downto 0);
    signal sh_wdata  : std_logic_vector(31 downto 0);
    signal sh_gnt    : std_logic := '0';
    signal sh_done   : std_logic := '0';
    signal sh_rdata  : std_logic_vector(31 downto 0) := (others => '0');
    signal sh_lrsc   : std_logic_vector(1 downto 0);
    signal sh_lock   : std_logic;

    -- the tile's other ports
    signal t_a0      : std_logic_vector(31 downto 0);
    signal t_trap    : std_logic;
    signal t_fmen    : std_logic;
    signal t_fclk    : std_logic;
    signal t_fmab    : std_logic_vector(31 downto 0);

    -- THE PORT UNDER TEST
    signal x_req     : std_logic := '0';
    signal x_addr    : std_logic_vector(11 downto 0) := (others => '0');
    signal x_rdata   : std_logic_vector(31 downto 0);
    signal x_done    : std_logic;

    -- BFM state
    signal shram     : mem_t := (others => (others => '0'));
    constant R_IDLE  : std_logic_vector(1 downto 0) := "00";
    constant R_SERVE : std_logic_vector(1 downto 0) := "01";
    constant R_REL   : std_logic_vector(1 downto 0) := "10";
    constant R_STALL : std_logic_vector(1 downto 0) := "11";   -- T6
    signal rstate    : std_logic_vector(1 downto 0) := R_IDLE;

    -- T6 (A3): the BFM's stall knob.  STALL_WORD is the instruction the core
    -- fetches while it sits in MEMORY_WAIT on the victim TCM load -- word 0x17
    -- (`add t5,t1,t2`), the one immediately after `lw t3,0(t0)` at 0x16.
    -- Stalling THAT fetch is what makes the core's freeze long, which is the
    -- only structural difference between this and T2.  STALL_N is chosen to be
    -- comfortably longer than a whole external transaction (6 mclk to done +
    -- the rearm gap), so the pre-A3 hold provably expires inside the freeze.
    constant STALL_WORD : integer := 16#17#;
    constant STALL_N    : integer := 24;
    signal stall_arm : std_logic := '0';   -- tb -> BFM: stall the next such fetch
    signal stall_win : std_logic := '0';   -- BFM -> tb: a stalled fetch is in flight
    signal stall_cnt : integer   := 0;
    signal stall_len : integer   := 0;     -- measured length of the last stall, mclk

    -- trap latch (a trapped core is a dead bench; say so rather than time out)
    signal trap_seen : std_logic := '0';

    procedure chk(cond : boolean; msg : string; signal f : inout integer) is
    begin
        if cond then
            report "CHECK ok: " & msg severity note;
        else
            report "CHECK FAILED: " & msg severity warning;
            f <= f + 1;
        end if;
    end procedure;

    function hex8(v : std_logic_vector(31 downto 0)) return string is
        constant D : string(1 to 16) := "0123456789abcdef";
        variable s : string(1 to 8);
        variable n : integer;
    begin
        for i in 0 to 7 loop
            n := conv_integer('0' & v(4*i+3 downto 4*i));
            s(8-i) := D(n+1);
        end loop;
        return s;
    end function;

    -- -------------------------------------------------------------------------
    -- The external requester.  Implements the frozen protocol EXACTLY as the
    -- port comment states it, including the part that is easy to miss: req is
    -- held until done AND THEN RETURNS LOW FOR AT LEAST ONE mclk, because the
    -- tile's one-shot (tx_served) rearms on req being low -- the same contract
    -- sh_acked has with sh_sel.  The trailing wait is what guarantees that gap,
    -- so a caller can invoke this back-to-back and still be legal.
    -- `cyc` counts mclk edges from the first edge after req was raised to the
    -- edge on which done was sampled; it is the number the latency claim in
    -- hart_tile.vhd is pinned by.
    -- -------------------------------------------------------------------------
    procedure ext_read(signal   clk_s   : in  std_logic;
                       signal   req_s   : out std_logic;
                       signal   addr_s  : out std_logic_vector(11 downto 0);
                       signal   done_s  : in  std_logic;
                       signal   rdata_s : in  std_logic_vector(31 downto 0);
                       constant widx    : in  integer;
                       variable d       : out std_logic_vector(31 downto 0);
                       variable cyc     : out integer;
                       variable timeout : out boolean) is
        variable n : integer := 0;
    begin
        req_s   <= '1';
        addr_s  <= conv_std_logic_vector(widx, 12);
        timeout := false;
        loop
            wait until rising_edge(clk_s);
            n := n + 1;
            exit when done_s = '1';
            if n >= W_XACT then
                timeout := true;
                exit;
            end if;
        end loop;
        d   := rdata_s;
        cyc := n;
        req_s <= '0';
        wait until rising_edge(clk_s);   -- the mandatory one-cycle rearm gap
    end procedure;

    function plant_val(i : integer) return std_logic_vector is
    begin
        return PLANT_BASE + conv_std_logic_vector(i, 32);
    end function;

    -- The report counters are small, but the words holding them are 32 bits and
    -- STD_LOGIC_ARITH's conv_integer warns on any 32-bit argument regardless of
    -- VALUE ("argument too large") -- 660 lines of it per run, which buries the
    -- checks.  Read the counters through a 16-bit slice instead; they never
    -- reach 65536 in a bench that runs for microseconds, and if one ever did,
    -- the progress checks are all strict-greater-than comparisons taken across
    -- a few hundred microseconds, so a wrap would show as "no progress" (a
    -- FAIL) rather than as a false pass.
    function ctr(v : std_logic_vector(31 downto 0)) return integer is
    begin
        return conv_integer('0' & v(15 downto 0));
    end function;

begin

    mclk <= not mclk after MCLK_PERIOD / 2 when not tb_end else '0';

    -- -------------------------------------------------------------------------
    -- Shared-window BFM.  ONE master, so there is no arbitration to model, but
    -- it does implement the arbiter's WAIT-FOR-RELEASE handshake (R_REL): the
    -- tile's req is stale-high for a couple of cycles after its done (the ack
    -- flop clears it through the M13 boundary), and a BFM that re-serves on
    -- that tail manufactures the M5a ghost transaction -- which for a STORE
    -- would silently double-apply it.  Same reason mp_arbiter has need_release.
    -- -------------------------------------------------------------------------
    bfm: process(mclk)
        variable wa : integer;
    begin
        if rising_edge(mclk) then
            sh_done <= '0';
            case rstate is
                when R_IDLE =>
                    if sh_req = '1' then
                        sh_gnt <= '1';
                        rstate <= R_SERVE;
                    end if;
                when R_STALL =>
                    -- T6: hold the transaction open.  sh_rdata was already
                    -- computed in R_SERVE and holds; the core is frozen on
                    -- mem_ready_sh the entire time, exactly as it is behind a
                    -- real s_stall-ed aperture transaction.
                    stall_len <= stall_len + 1;
                    if stall_cnt = 0 then
                        stall_win <= '0';
                        sh_done   <= '1';
                        sh_gnt    <= '0';
                        rstate    <= R_REL;
                    else
                        stall_cnt <= stall_cnt - 1;
                    end if;

                when R_SERVE =>
                    wa := conv_integer(sh_addr);
                    if sh_we = "0000" then
                        if wa <= 63 then
                            sh_rdata <= PROG_IMG(wa);
                        elsif wa >= SH_RPT_BASE and wa <= SH_RPT_BASE + 63 then
                            sh_rdata <= shram(wa - SH_RPT_BASE);
                        else
                            sh_rdata <= (others => '0');
                        end if;
                    else
                        if wa >= SH_RPT_BASE and wa <= SH_RPT_BASE + 63 then
                            for b in 0 to 3 loop
                                if sh_we(b) = '1' then
                                    shram(wa - SH_RPT_BASE)(8*b+7 downto 8*b)
                                        <= sh_wdata(8*b+7 downto 8*b);
                                end if;
                            end loop;
                        end if;
                    end if;
                    if stall_arm = '1' and sh_we = "0000" and wa = STALL_WORD then
                        -- T6: do NOT complete yet.
                        stall_cnt <= STALL_N;
                        stall_len <= 1;
                        stall_win <= '1';
                        rstate    <= R_STALL;
                    else
                        sh_done <= '1';
                        sh_gnt  <= '0';
                        rstate  <= R_REL;
                    end if;
                when others =>            -- R_REL
                    if sh_req = '0' then
                        rstate <= R_IDLE;
                    end if;
            end case;
        end if;
    end process;

    trap_mon: process(mclk)
    begin
        if rising_edge(mclk) then
            if t_trap = '1' then
                trap_seen <= '1';
            end if;
        end if;
    end process;

    -- -------------------------------------------------------------------------
    -- THE DUT: a real hart_tile.  Note what is NOT named -- pd_sleep,
    -- pd_iso_en, tcm_pgen, tcm_retn, msip/mtip/meip, the debug trio -- all
    -- taking their entity defaults, which is the shape MCU.vhd instantiates
    -- today.  If any of the four new ports had been given without a default,
    -- this instantiation would still compile (it names all four), but the
    -- byte-identity gate on MCU.vhd would not; see the port comment.
    -- -------------------------------------------------------------------------
    tile: entity work.hart_tile
        generic map (
            PC_RST_VAL => x"00000000",
            SH_AW      => SH_AW_C
        )
        port map (
            clk       => mclk,
            resetn    => resetn,
            hart_id   => x"00000001",
            flash_mem_en  => t_fmen,
            flash_clk_mem => t_fclk,
            flash_mab     => t_fmab,
            sh_req    => sh_req,
            sh_we     => sh_we,
            sh_addr   => sh_addr,
            sh_wdata  => sh_wdata,
            sh_gnt    => sh_gnt,
            sh_done   => sh_done,
            sh_rdata  => sh_rdata,
            sh_lrsc   => sh_lrsc,
            sh_lock   => sh_lock,
            tcm_ext_req   => x_req,
            tcm_ext_addr  => x_addr,
            tcm_ext_rdata => x_rdata,
            tcm_ext_done  => x_done,
            trap_flag => t_trap,
            a0        => t_a0
        );

    -- -------------------------------------------------------------------------
    stim: process
        variable d        : std_logic_vector(31 downto 0);
        variable cyc      : integer;
        variable to_flag  : boolean;
        variable cyc_min  : integer;
        variable cyc_max  : integer;
        variable n_bad    : integer;
        variable n_to     : integer;
        variable i, k     : integer;
        variable it0, it1 : integer;
        variable boot_ok  : boolean;
        variable saw_done : boolean;
        variable stable   : boolean;
        variable hold_val : std_logic_vector(31 downto 0);
    begin
        report "tcm_port_tb: CPR2 external TCM slave port bench starting" severity note;

        -- =====================================================================
        -- T5a  REQUEST DURING RESET IS IGNORED.
        -- Done FIRST, while resetn is still low, because it is the only check
        -- that needs the reset state and re-resetting later would restart the
        -- core.  What must hold: no done pulse, rdata parked at its reset
        -- value.  (The SRAM is not clocked from this side either -- tx_sel
        -- cannot leave '0' with tx_req_r held at '0' by reset -- but that is a
        -- structural claim about the RTL, not something a port-level bench can
        -- observe, so it is not asserted here.)
        -- =====================================================================
        resetn <= '0';
        x_req  <= '1';
        x_addr <= conv_std_logic_vector(POISON_IDX, 12);
        saw_done := false;
        for n in 0 to 39 loop
            wait until rising_edge(mclk);
            if x_done = '1' then saw_done := true; end if;
        end loop;
        chk(not saw_done,
            "T5a: no tcm_ext_done while resetn is low (request during reset ignored)",
            fails);
        chk(x_rdata = x"00000000",
            "T5a: tcm_ext_rdata parked at its reset value through reset", fails);
        x_req <= '0';
        wait until rising_edge(mclk);
        wait until rising_edge(mclk);

        -- =====================================================================
        -- BOOT.  Release reset and wait for the core to publish READY.  This is
        -- not decoration: core_rst_stretch holds the core in reset until its
        -- boot fetch lands, so a READY that never arrives means the tile never
        -- started, and every later check would be vacuously "green" against a
        -- dead core.
        -- =====================================================================
        resetn <= '1';
        boot_ok := false;
        for n in 0 to W_BOOT-1 loop
            wait until rising_edge(mclk);
            if shram(RPT_READY) = READY_MAGIC then
                boot_ok := true;
                exit;
            end if;
        end loop;
        chk(boot_ok,
            "BOOT: the tile booted from the shared BFM and published READY "
            & "(it planted its TCM patterns)", fails);
        chk(trap_seen = '0', "BOOT: the core did not trap while planting", fails);
        if not boot_ok then
            report "tcm_port_tb: core never booted -- remaining checks are vacuous"
                severity warning;
        end if;

        -- =====================================================================
        -- T1  BASIC.  Read the 16 planted words + the poison word back through
        -- the external port and compare against what the program wrote.
        -- =====================================================================
        n_bad   := 0;
        n_to    := 0;
        cyc_min := 1000000;
        cyc_max := 0;
        for i in 0 to N_PLANT-1 loop
            ext_read(mclk, x_req, x_addr, x_done, x_rdata, i, d, cyc, to_flag);
            if to_flag then
                n_to := n_to + 1;
            else
                if cyc < cyc_min then cyc_min := cyc; end if;
                if cyc > cyc_max then cyc_max := cyc; end if;
                if d /= plant_val(i) then
                    n_bad := n_bad + 1;
                    report "T1 word " & integer'image(i) & ": got " & hex8(d)
                        & " expected " & hex8(plant_val(i)) severity warning;
                end if;
            end if;
        end loop;
        ext_read(mclk, x_req, x_addr, x_done, x_rdata, POISON_IDX, d, cyc, to_flag);
        if to_flag then
            n_to := n_to + 1;
        else
            if cyc < cyc_min then cyc_min := cyc; end if;
            if cyc > cyc_max then cyc_max := cyc; end if;
            if d /= POISON_VAL then
                n_bad := n_bad + 1;
                report "T1 poison word: got " & hex8(d) & " expected "
                    & hex8(POISON_VAL) severity warning;
            end if;
        end if;
        chk(n_to = 0, "T1: every external read completed (no handshake timeout)", fails);
        chk(n_bad = 0,
            "T1: all 17 externally-read words match what the core planted", fails);
        report "tcm_port_tb: external read latency, mclk edges from request to "
            & "done sample: min " & integer'image(cyc_min)
            & " max " & integer'image(cyc_max) severity note;
        chk(cyc_min = cyc_max,
            "T1: the transaction latency is DETERMINISTIC (min = max) -- the "
            & "port does not depend on what the core happens to be doing", fails);

        -- =====================================================================
        -- T2  CONTENTION.  Same sweep, but now the assertion is about BOTH
        -- sides at once.  The core is in its check loop the whole time (it has
        -- been since READY), so every one of these reads lands on a running
        -- core, at an arbitrary point in its fetch/load pipeline.
        --   external side: every word still correct;
        --   core side:     mismatch count still 0, iteration count advancing.
        -- The second half is the half that catches the interesting bug -- an
        -- external read that clobbers the SRAM Q the frozen core was still
        -- holding is invisible from out here and shows up ONLY as the core
        -- disagreeing with its own memory.
        -- =====================================================================
        it0   := ctr(shram(RPT_ITERS));
        n_bad := 0;
        n_to  := 0;
        for k in 0 to 23 loop
            for i in 0 to N_PLANT-1 loop
                ext_read(mclk, x_req, x_addr, x_done, x_rdata, i, d, cyc, to_flag);
                if to_flag then
                    n_to := n_to + 1;
                elsif d /= plant_val(i) then
                    n_bad := n_bad + 1;
                end if;
            end loop;
            ext_read(mclk, x_req, x_addr, x_done, x_rdata, POISON_IDX, d, cyc, to_flag);
            if to_flag then
                n_to := n_to + 1;
            elsif d /= POISON_VAL then
                n_bad := n_bad + 1;
            end if;
        end loop;
        chk(n_to = 0, "T2: every contended external read completed", fails);
        chk(n_bad = 0,
            "T2: every contended external read returned the planted value "
            & "(408 reads against a running core)", fails);
        chk(shram(RPT_ERRS) = x"00000000",
            "T2: the CORE still reads its own TCM correctly under contention "
            & "(its published mismatch count is 0) -- got "
            & hex8(shram(RPT_ERRS)), fails);
        it1 := ctr(shram(RPT_ITERS));
        chk(it1 > it0,
            "T2: the core kept making progress through the contention window "
            & "(iterations " & integer'image(it0) & " -> "
            & integer'image(it1) & ")", fails);
        chk(trap_seen = '0', "T2: the core did not trap under contention", fails);

        -- =====================================================================
        -- T3  SELF-PROGRESS / NO LIVELOCK.  ext_read already issues the minimum
        -- legal cadence (one idle mclk between transactions), so this is the
        -- worst case the port can be driven at.  The claim under test is that
        -- the stall is BOUNDED: tx_busy must go low for a full cycle before the
        -- next request can be registered, so the core gets at least one clk_cpu
        -- edge per transaction and its loop cannot be starved to a standstill.
        -- Measured, not argued: the iteration counter must move DURING the
        -- hammer, not merely after it.
        -- =====================================================================
        it0 := ctr(shram(RPT_ITERS));
        i   := 0;
        n_to := 0;
        while ctr(shram(RPT_ITERS)) <= it0 and i < W_PROG loop
            ext_read(mclk, x_req, x_addr, x_done, x_rdata, POISON_IDX, d, cyc, to_flag);
            if to_flag then n_to := n_to + 1; end if;
            if d /= POISON_VAL then n_bad := n_bad + 1; end if;
            i := i + 10;    -- ext_read burns ~7-8 mclk; this bounds the loop
        end loop;
        it1 := ctr(shram(RPT_ITERS));
        chk(it1 > it0,
            "T3: the core completed a full check iteration WHILE being hammered "
            & "with back-to-back external reads (" & integer'image(it0) & " -> "
            & integer'image(it1) & ") -- the stall is bounded, not a livelock",
            fails);
        chk(n_to = 0, "T3: no external read timed out during the hammer", fails);
        chk(n_bad = 0, "T3: every hammer read returned the poison word", fails);

        -- and it must resume cleanly once the hammering stops
        it0 := ctr(shram(RPT_ITERS));
        boot_ok := false;
        for n in 0 to W_PROG-1 loop
            wait until rising_edge(mclk);
            if ctr(shram(RPT_ITERS)) > it0 then
                boot_ok := true;
                exit;
            end if;
        end loop;
        chk(boot_ok,
            "T3: the core kept running after the hammer stopped", fails);
        chk(shram(RPT_ERRS) = x"00000000",
            "T3: still no core-side mismatches after the hammer -- got "
            & hex8(shram(RPT_ERRS)), fails);

        -- =====================================================================
        -- T5  HANDSHAKE DETAIL.
        -- =====================================================================
        -- T5b: done is exactly ONE mclk wide, and rdata is valid with it.
        x_req  <= '1';
        x_addr <= conv_std_logic_vector(POISON_IDX, 12);
        n_bad  := 0;
        to_flag := false;
        for n in 0 to W_XACT-1 loop
            wait until rising_edge(mclk);
            exit when x_done = '1';
            if n = W_XACT-1 then to_flag := true; end if;
        end loop;
        chk(not to_flag, "T5b: the transaction completed", fails);
        hold_val := x_rdata;
        chk(hold_val = POISON_VAL,
            "T5b: tcm_ext_rdata is VALID WITH the done pulse (value-with-pulse)",
            fails);
        wait until rising_edge(mclk);
        chk(x_done = '0',
            "T5b: tcm_ext_done is exactly ONE mclk wide", fails);
        -- T5c: rdata HOLDS after done, with the request dropped and the core
        -- still running underneath.
        x_req <= '0';
        stable := true;
        for n in 0 to 199 loop
            wait until rising_edge(mclk);
            if x_rdata /= hold_val then stable := false; end if;
            if x_done = '1' then
                stable := false;
                report "T5c: spurious tcm_ext_done with no request" severity warning;
            end if;
        end loop;
        chk(stable,
            "T5c: tcm_ext_rdata HELD its value for 200 mclk after done, and no "
            & "spurious done fired with the request low", fails);

        -- T5d: back-to-back transactions to DIFFERENT addresses -- rdata must
        -- actually change, which is what rules out a bench that would pass T5c
        -- against a port that never updates at all.
        ext_read(mclk, x_req, x_addr, x_done, x_rdata, 3, d, cyc, to_flag);
        chk((not to_flag) and d = plant_val(3),
            "T5d: back-to-back transaction 1 of 2 read word 3 correctly", fails);
        ext_read(mclk, x_req, x_addr, x_done, x_rdata, POISON_IDX, d, cyc, to_flag);
        chk((not to_flag) and d = POISON_VAL,
            "T5d: back-to-back transaction 2 of 2 read word 100 correctly "
            & "(the one-shot rearmed on the single idle cycle)", fails);
        chk(trap_seen = '0', "T5: the core never trapped anywhere in this run",
            fails);

        -- =====================================================================
        -- T6  SELF-ACCESS / LONG FREEZE (CPR3b, A3).  See the header.
        --
        -- Each pass: arm the BFM to stall the fetch the core issues while it is
        -- in MEMORY_WAIT on `lw t3,0(t0)`, wait for that stall to start, let
        -- `ph` more mclk go by (so the external read lands at a different phase
        -- of the freeze every pass), then fire ONE external read of the poison
        -- word.  The external transaction is ~7 mclk and the freeze is
        -- STALL_N+1, so the freeze OUTLASTS it by construction -- which is the
        -- whole point: the pre-A3 hold (tx_busy + 1 mclk) expires with the core
        -- still frozen and still combinationally attached to mem_dout(1).
        --
        -- The victim is the load, and the core grades it: t3 must be
        -- 0xA5A50000+i, the poison word 0xDEADBEEF appears nowhere in that
        -- range, so any leak is a published mismatch.
        -- =====================================================================
        it0    := ctr(shram(RPT_ITERS));
        n_bad  := 0;
        n_to   := 0;
        for k in 0 to 17 loop
            stall_arm <= '1';
            -- wait for the stalled fetch to start (bounded: the core is in its
            -- loop and passes STALL_WORD every iteration)
            to_flag := true;
            for n in 0 to W_PROG-1 loop
                wait until rising_edge(mclk);
                if stall_win = '1' then
                    to_flag := false;
                    exit;
                end if;
            end loop;
            if to_flag then
                report "T6: the BFM never saw the stalled fetch" severity warning;
                exit;
            end if;
            stall_arm <= '0';           -- one stalled fetch per pass
            for n in 0 to (k mod 6) loop
                wait until rising_edge(mclk);
            end loop;
            ext_read(mclk, x_req, x_addr, x_done, x_rdata, POISON_IDX,
                     d, cyc, to_flag);
            if to_flag then
                n_to := n_to + 1;
            elsif d /= POISON_VAL then
                n_bad := n_bad + 1;
            end if;
            -- let the stall finish and the core resume before the next pass
            for n in 0 to 60 loop
                wait until rising_edge(mclk);
            end loop;
        end loop;
        stall_arm <= '0';

        report "tcm_port_tb: T6 stall window measured " &
            integer'image(stall_len) & " mclk (external transaction is ~7)"
            severity note;
        chk(stall_len > 10,
            "T6: the core's freeze really did outlast the external transaction "
            & "(stalled fetch held " & integer'image(stall_len) & " mclk) -- "
            & "the topology under test is present, not vacuous", fails);
        chk(n_to = 0, "T6: every external read inside a long freeze completed",
            fails);
        chk(n_bad = 0,
            "T6: every external read inside a long freeze returned the poison "
            & "word (the PORT side is unaffected by the freeze)", fails);
        chk(shram(RPT_ERRS) = x"00000000",
            "T6: the CORE's own load result survived an external read taken "
            & "while it was frozen on a LONGER shared transaction -- its "
            & "published mismatch count is 0 -- got " & hex8(shram(RPT_ERRS)),
            fails);
        it1 := ctr(shram(RPT_ITERS));
        chk(it1 > it0,
            "T6: the core kept making progress across the long freezes ("
            & integer'image(it0) & " -> " & integer'image(it1) & ")", fails);
        chk(trap_seen = '0',
            "T6: the core did not trap (a corrupted load feeds compare/branch, "
            & "and the chip-level flavour of this bug was a PC excursion)",
            fails);

        -- =====================================================================
        wait for 1 us;
        report "tcm_port_tb: failures = " & integer'image(fails) severity note;
        if fails = 0 then
            report "ALL CHECKS PASSED" severity note;
        else
            report "tcm_port_tb: FAILURES" severity note;
        end if;
        tb_end <= true;
        wait;
    end process;

end architecture;
