/* =============================================================================
   tcm_port_tb.vhd  -- unit bench for the hart_tile external TCM slave port
   =============================================================================
   Drives a REAL hart_tile (real vesta core, adddec and sram1p16k_hvt_pg) through tcm_ext_* while the core genuinely executes out of a shared-window BFM; the only models are that BFM (one master, so no arbiter) and the external requester.
   The core must be RUNNING for any of this to mean anything, since the port borrows an SRAM port out from under a core that is using it; PC_RST_VAL = 0 and core_rst_stretch hold the core in reset until its first boot fetch LANDS, so the BFM must serve address 0 or the core never starts.
   The hand-assembled program (PROG_IMG, with its disassembly in the comment column) executes from the shared window: fill TCM words 0..15 with 0xA5A50000+i, poison TCM word 100 (byte 0x8190) with 0xDEADBEEF, publish READY at shared 0x10000, then re-check the planted words forever, publishing iterations at 0x10004 and mismatches at 0x10008.
   Those two words are the core's own verdict on its memory, and the poison value appears nowhere in the checked range, so any leak of external read data into the core's load path is a guaranteed mismatch.
   Self-grading: PASS iff the log prints "ALL CHECKS PASSED" and contains no "CHECK FAILED"; severity is WARNING rather than ERROR so one failing test does not stop the rest.
   ============================================================================= */

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

    /* Shared-window BFM geometry: two disjoint regions, anything else reads zeros and swallows writes like the real unmapped gap.
         word 0..63          = byte 0x0..0xFF        : the instruction stream
         word 0x4000..0x400F = byte 0x10000..0x1003F : the core's report words */
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

    -- The instruction stream, built with riscv-none-elf-as -march=rv32i -mabi=ilp32 and .option norvc.
    -- Compressed execute-from-shared is UNTESTED chip-wide, so this stream is all 32-bit.
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

    -- Budgets, in mclk, generous on purpose: what is under test is "eventually" versus "never" and "bounded" versus "livelock", so a tight budget would be a calibration rather than a check.
    constant W_BOOT   : integer := 60000;   -- READY must appear within
    constant W_XACT   : integer := 200;     -- one external read must complete within
    constant W_PROG   : integer := 60000;   -- the core must advance an iteration within

    signal mclk   : std_logic := '0';
    signal resetn : std_logic := '0';
    signal tb_end : boolean   := false;
    signal fails  : integer   := 0;

    -- shared-window BFM to tile
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

    -- The BFM stall knob for T6: STALL_WORD is the instruction the core fetches while it sits in MEMORY_WAIT on the victim TCM load, word 0x17 (`add t5,t1,t2`), immediately after `lw t3,0(t0)` at 0x16.
    -- Stalling THAT fetch is what makes the core's freeze long, the only structural difference from T2; STALL_N is comfortably longer than a whole external transaction (6 mclk to done plus the rearm gap).
    constant STALL_WORD : integer := 16#17#;
    constant STALL_N    : integer := 24;
    signal stall_arm : std_logic := '0';   -- tb tells the BFM to stall the next such fetch
    signal stall_win : std_logic := '0';   -- BFM tells the tb a stalled fetch is in flight
    signal stall_cnt : integer   := 0;
    signal stall_len : integer   := 0;     -- measured length of the last stall, mclk

    -- Trap latch: a trapped core is a dead bench, so say so rather than time out.
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

    /* -------------------------------------------------------------------------
       The external requester: req is held until done AND THEN RETURNS LOW FOR AT LEAST ONE mclk, because the tile's one-shot (tx_served) rearms on req being low; the trailing wait guarantees that gap so back-to-back calls stay legal.
       `cyc` counts mclk edges from the first edge after req was raised to the edge on which done was sampled, which is the latency the port is pinned by.
       ------------------------------------------------------------------------- */
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

    -- STD_LOGIC_ARITH's conv_integer warns on any 32-bit argument regardless of VALUE ("argument too large") and buries the checks, so read the small report counters through a 16-bit slice.
    -- They never reach 65536 here, and every progress check is a strict-greater-than over a few hundred microseconds, so a wrap would show as "no progress", a FAIL, not a false pass.
    function ctr(v : std_logic_vector(31 downto 0)) return integer is
    begin
        return conv_integer('0' & v(15 downto 0));
    end function;

begin

    mclk <= not mclk after MCLK_PERIOD / 2 when not tb_end else '0';

    /* -------------------------------------------------------------------------
       Shared-window BFM: ONE master, so no arbitration to model, but it does implement the arbiter's WAIT-FOR-RELEASE handshake (R_REL).
       The tile's req is stale-high for a couple of cycles after its done, since the ack flop clears it through the registered boundary, and a BFM that re-serves on that tail manufactures a ghost transaction, which for a STORE would silently double-apply it.
       ------------------------------------------------------------------------- */
    bfm: process(mclk)
        variable wa : integer;
    begin
        if rising_edge(mclk) then
            sh_done <= '0';
            case rstate is
                when R_IDLE =>
                    -- Nothing in flight: grant as soon as the tile raises req.
                    if sh_req = '1' then
                        sh_gnt <= '1';
                        rstate <= R_SERVE;
                    end if;
                when R_STALL =>
                    -- T6: hold the transaction open.
                    -- sh_rdata was already computed in R_SERVE and holds; the core is frozen on mem_ready_sh the entire time, exactly as behind a real stalled aperture transaction.
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
                    -- Serve the access: reads take the program image or the report words, writes land only in the report words.
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
                when others =>            -- R_REL: wait for the tile's req to go low before another grant (no ghost transaction)
                    if sh_req = '0' then
                        rstate <= R_IDLE;
                    end if;
            end case;
        end if;
    end process;

    -- Latch any trap the core takes; checked at every stage so a dead core is reported, not timed out.
    trap_mon: process(mclk)
    begin
        if rising_edge(mclk) then
            if t_trap = '1' then
                trap_seen <= '1';
            end if;
        end if;
    end process;

    /* -------------------------------------------------------------------------
       THE DUT: a real hart_tile.
       pd_sleep, pd_iso_en, tcm_pgen, tcm_retn, msip/mtip/meip and the debug trio are deliberately left at their entity defaults, which is the shape MCU.vhd instantiates.
       ------------------------------------------------------------------------- */
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

        /* =====================================================================
           T5a  REQUEST DURING RESET IS IGNORED: no done pulse, and rdata parked at its reset value.
           Done FIRST, while resetn is still low, because it is the only check that needs the reset state and re-resetting later would restart the core.
           ===================================================================== */
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

        /* =====================================================================
           BOOT.  Release reset and wait for the core to publish READY.
           Not decoration: the core is held in reset until its boot fetch lands, so a READY that never arrives means every later check is vacuously green against a dead core.
           ===================================================================== */
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

        /* =====================================================================
           T1  BASIC.  Read the 16 planted words plus the poison word back through the external port and compare against what the program wrote.
           ===================================================================== */
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

        /* =====================================================================
           T2  CONTENTION.  Same sweep against a core running its check loop, asserting BOTH sides at once: every external word still correct, and the core's mismatch count still 0 with its iteration count advancing.
           The core side catches the interesting bug, since an external read that clobbers the SRAM Q a frozen core still held is invisible from out here; its negative control is an RTL mutation (drop the Q shadow, or switch the ram0 mux on the raw request) re-run against T2.
           ===================================================================== */
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

        /* =====================================================================
           T3  SELF-PROGRESS / NO LIVELOCK.  ext_read issues the minimum legal cadence (one idle mclk between transactions), the worst case the port can be driven at.
           The claim under test is that the stall is BOUNDED: tx_busy must go low for a full cycle before the next request registers, so the core gets at least one clk_cpu edge per transaction and its iteration counter must move DURING the hammer, not merely after it.
           ===================================================================== */
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

        -- The core must also resume cleanly once the hammering stops.
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

        /* =====================================================================
           T5  HANDSHAKE DETAIL.
           ===================================================================== */
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
        -- T5c: rdata HOLDS after done, with the request dropped and the core still running underneath.
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

        -- T5d: back-to-back transactions to DIFFERENT addresses, so rdata must actually change.
        -- That is what rules out a bench which would pass T5c against a port that never updates at all.
        ext_read(mclk, x_req, x_addr, x_done, x_rdata, 3, d, cyc, to_flag);
        chk((not to_flag) and d = plant_val(3),
            "T5d: back-to-back transaction 1 of 2 read word 3 correctly", fails);
        ext_read(mclk, x_req, x_addr, x_done, x_rdata, POISON_IDX, d, cyc, to_flag);
        chk((not to_flag) and d = POISON_VAL,
            "T5d: back-to-back transaction 2 of 2 read word 100 correctly "
            & "(the one-shot rearmed on the single idle cycle)", fails);
        chk(trap_seen = '0', "T5: the core never trapped anywhere in this run",
            fails);

        /* =====================================================================
           T6  SELF-ACCESS / LONG FREEZE.  Each pass arms the BFM to stall the fetch the core issues while it is in MEMORY_WAIT on `lw t3,0(t0)`, waits for that stall to start, lets a few more mclk pass so the external read lands at a different phase of the freeze each time, then fires ONE external read of the poison word.
           The external transaction is ~7 mclk and the freeze is STALL_N+1, so the freeze OUTLASTS it by construction: a Q-shadow hold that expires inside the freeze lets the core consume the external word as its load result, and the core grades that itself (t3 must be 0xA5A50000+i, and 0xDEADBEEF appears nowhere in that range), so any leak is a published mismatch.
           ===================================================================== */
        it0    := ctr(shram(RPT_ITERS));
        n_bad  := 0;
        n_to   := 0;
        for k in 0 to 17 loop
            stall_arm <= '1';
            -- Wait for the stalled fetch to start; bounded, because the core is in its loop and passes STALL_WORD every iteration.
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
            -- Let the stall finish and the core resume before the next pass.
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
