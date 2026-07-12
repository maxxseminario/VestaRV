-- =============================================================================
-- arb_lat_tb.vhd  (M10) -- arbiter LATENCY-INSENSITIVITY proof
-- =============================================================================
-- M13 will harden each hart as a P&R tile with REGISTERED I/O at the tile
-- boundary: +N_DELAY cycles EACH WAY on every master<->arbiter signal. This tb
-- proves (or refutes) that the shared-bus protocol tolerates that added
-- latency BEFORE anything moves: mp_arbiter + resv_unit + mutex_bank + a
-- 1-cycle shared-RAM model behind generic pipeline registers on ALL
-- master-side paths (req/we/addr/wdata/lock/lrsc outbound; gnt/done/rdata/
-- scfail inbound — the audit's full boundary-contract list; everything shares
-- ONE depth, as the real tile boundary must).
--
-- Model: mp_arbiter_tb.vhd (M8 tile-accurate BFMs — req held THROUGH the done
-- cycle, dropped one clock later, the M5a ghost-txn shape) + the directed
-- passes M10 demands:
--   1 WRITE / 2 READBACK / 3 BYTE-LANE  -- disjoint-range integrity (M3c/M4a)
--   4 RANDOM      -- LFSR reads/writes in own range, scoreboarded vs a model
--   5 LR/SC       -- 4-way contended increment of ONE word through resv_unit,
--                    bounded retries + hartid-scaled backoff (M4c livelock rule)
--   6 AMO LOCKED  -- grant-locked RMW pairs on ONE counter (M8 pass, verbatim)
--   7 MUTEX STORM -- 1-txn claim-read storms on mutex_bank slot 0, own-marker
--                    re-read check, mutex-protected unlocked RMW counter
--
-- Checkers: per-master data scoreboards, grant mutual-exclusion, locked-pair
-- critical-section, GHOST-DONE (done(i) while master i has nothing in flight
-- -- the delayed-stale-req failure signature), final counter totals.
--
-- NEGATIVE CONTROLS (house rule), via generic BREAK_MODE:
--   0 = clean run (the only PASS-eligible mode)
--   1 = master 0 drops lock EARLY in the AMO pass (right after the locked
--       read) -- interleaving must lose updates => counter check must FAIL
--   2 = the tile boundary skews: req is piped ONE STAGE SHALLOWER than
--       addr/wdata (only meaningful when N_DELAY>0) -- the arbiter's pick
--       edge samples the PREVIOUS transaction's address/data => scoreboard
--       must FAIL. This is "drop a delay stage the DUT was told to expect".
--       (The opposite skew -- addr early, req on time -- is provably benign:
--       the master holds addr stable across the whole transaction, so an
--       early addr only pre-exposes the value before req arrives. The first
--       cut of this control skewed that way and correctly went unnoticed.)
--
-- PASS banner: "ALL CHECKS PASSED" (grepped by xcelium/mp_test/run_arb_lat.sh).
-- Expected runtime: a few seconds (irq_sys_tb-class unit tb).
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

-- ---------------------------------------------------------------------------
-- Master BFM: tile-accurate handshake (hold req through done, drop one clock
-- later). All waits are on the MASTER-SIDE (piped) done/rdata/scfail — the BFM
-- never peeks past the boundary registers, exactly like a hardened tile.
-- ---------------------------------------------------------------------------
entity arb_lat_master is
    generic (
        INDEX      : natural := 0;
        NTX        : natural := 4;    -- words in own disjoint range (passes 1-3)
        N_RND      : natural := 24;   -- random ops (pass 4)
        N_LRSC     : natural := 6;    -- successful LR/SC increments (pass 5)
        N_RMW      : natural := 8;    -- grant-locked RMW pairs (pass 6)
        N_MTX      : natural := 6;    -- mutex-protected increments (pass 7)
        BREAK_MODE : natural := 0;    -- 1 = drop lock early (master 0 only)
        -- A2 (Argus): total master count, for the mutex owner-marker sanity
        -- bounds (owner is 1..N_TOTAL and can exceed 3 bits at N > 7)
        N_TOTAL    : natural := 4
    );
    port (
        clk      : in  std_logic;
        resetn   : in  std_logic;
        req      : out std_logic;
        we       : out std_logic_vector(3 downto 0);
        addr     : out std_logic_vector(11 downto 0);
        wdata    : out std_logic_vector(31 downto 0);
        lock     : out std_logic;
        lrsc     : out std_logic_vector(1 downto 0);
        gnt      : in  std_logic;
        done     : in  std_logic;
        rdata    : in  std_logic_vector(31 downto 0);
        scfail   : in  std_logic;
        busy     : out std_logic;   -- txn in flight (ghost-done checker)
        finished : out std_logic;
        err      : out std_logic
    );
end entity;

architecture bfm of arb_lat_master is
    -- disjoint 16-word range per master; distinct data pattern per (master,k)
    function addr_for(k : natural) return std_logic_vector is
    begin
        return conv_std_logic_vector(INDEX*16 + k, 12);
    end function;
    function data_for(k : natural) return std_logic_vector is
    begin
        return x"A5" & conv_std_logic_vector(INDEX, 8)
                     & conv_std_logic_vector(k, 8) & x"C3";
    end function;
    -- 16-bit xorshift-ish LFSR (taps 16,14,13,11) for the random pass
    function lfsr16(s : std_logic_vector(15 downto 0))
        return std_logic_vector is
        variable fb : std_logic;
    begin
        fb := s(15) xor s(13) xor s(12) xor s(10);
        return s(14 downto 0) & fb;
    end function;
    -- common contended words (top page, clear of every private range)
    constant CTR_ADDR  : std_logic_vector(11 downto 0) := x"F00"; -- AMO pass
    constant LRSC_ADDR : std_logic_vector(11 downto 0) := x"E00"; -- LR/SC pass
    constant PROT_ADDR : std_logic_vector(11 downto 0) := x"D00"; -- mutex-protected
    constant MTX_ADDR  : std_logic_vector(11 downto 0) := x"C00"; -- mutex_bank slot 0, mutex[0]
begin
    process
        type model_t is array(0 to 15) of std_logic_vector(31 downto 0);
        variable model    : model_t;
        variable rd       : std_logic_vector(31 downto 0);
        variable expected : std_logic_vector(31 downto 0);
        variable lane     : natural;
        variable seed     : std_logic_vector(15 downto 0);
        variable off      : natural;
        variable scf      : std_logic;
        variable attempts : natural;
        variable got      : natural;

        -- one full transaction, tile-accurate: raise req (+context), wait for
        -- the piped done, capture rdata/scfail ON the done cycle, hold req
        -- through it, drop one clock later, one idle re-request gap.
        procedure txn(
            a          : in  std_logic_vector(11 downto 0);
            lanes      : in  std_logic_vector(3 downto 0);
            d          : in  std_logic_vector(31 downto 0);
            tag        : in  std_logic_vector(1 downto 0);
            rd_o       : out std_logic_vector(31 downto 0);
            scf_o      : out std_logic
        ) is
        begin
            req <= '1'; we <= lanes; addr <= a; wdata <= d; lrsc <= tag;
            busy <= '1';
            wait until done = '1';
            rd_o  := rdata;                  -- valid on the done cycle
            scf_o := scfail;                 -- aligned with done by the pipe
            wait until rising_edge(clk);     -- hold req THROUGH the done cycle
            req <= '0'; we <= (others => '0'); lrsc <= "00";
            busy <= '0';
            wait until rising_edge(clk);     -- earliest legal re-request: +2
        end procedure;
    begin
        req <= '0'; we <= (others => '0'); addr <= (others => '0');
        wdata <= (others => '0'); lock <= '0'; lrsc <= "00";
        busy <= '0'; finished <= '0'; err <= '0';
        wait until resetn = '1';
        wait until rising_edge(clk);

        -- ---- pass 1: WRITE own range -------------------------------------
        for k in 0 to NTX-1 loop
            txn(addr_for(k), "1111", data_for(k), "00", rd, scf);
        end loop;

        -- ---- pass 2: READBACK own range ----------------------------------
        for k in 0 to NTX-1 loop
            txn(addr_for(k), "0000", x"00000000", "00", rd, scf);
            if rd /= data_for(k) then
                err <= '1';
                report "master " & integer'image(INDEX) &
                       " READBACK mismatch at k=" & integer'image(k)
                    severity error;
            end if;
        end loop;

        -- ---- pass 3: BYTE-LANE merge on word 0 ---------------------------
        lane := INDEX mod 4;
        req <= '1'; addr <= addr_for(0); wdata <= x"EEEEEEEE";
        we <= (others => '0'); we(lane) <= '1'; busy <= '1';
        wait until done = '1';
        wait until rising_edge(clk);
        req <= '0'; we <= (others => '0'); busy <= '0';
        wait until rising_edge(clk);
        expected := data_for(0);
        expected((lane+1)*8-1 downto lane*8) := x"EE";
        txn(addr_for(0), "0000", x"00000000", "00", rd, scf);
        if rd /= expected then
            err <= '1';
            report "master " & integer'image(INDEX) & " BYTE-LANE mismatch"
                severity error;
        end if;

        -- ---- pass 4: RANDOM reads/writes in own range, scoreboarded ------
        -- model init = state after passes 1-3 (words NTX..15 never written -> 0)
        for k in 0 to 15 loop
            if k = 0 then
                model(k) := expected;            -- word 0 carries the lane merge
            elsif k < NTX then
                model(k) := data_for(k);
            else
                model(k) := (others => '0');
            end if;
        end loop;
        seed := conv_std_logic_vector(16#B00B# + INDEX*257, 16);
        for k in 0 to N_RND-1 loop
            seed := lfsr16(seed);
            off  := conv_integer(seed(3 downto 0));
            if seed(4) = '1' then                -- write
                txn(addr_for(off), "1111", seed & (seed xor x"5A5A"), "00", rd, scf);
                model(off) := seed & (seed xor x"5A5A");
            else                                 -- read + check
                txn(addr_for(off), "0000", x"00000000", "00", rd, scf);
                if rd /= model(off) then
                    err <= '1';
                    report "master " & integer'image(INDEX) &
                           " RANDOM mismatch at off=" & integer'image(off)
                        severity error;
                end if;
            end if;
        end loop;

        -- ---- pass 5: LR/SC contended increment (through resv_unit) -------
        -- bounded retries + hartid-scaled backoff (M4c livelock rule)
        for k in 0 to N_LRSC-1 loop
            attempts := 0;
            loop
                txn(LRSC_ADDR, "0000", x"00000000", "01", rd, scf);   -- LR
                txn(LRSC_ADDR, "1111", rd + 1,      "10", rd, scf);   -- SC
                exit when scf = '0';                                  -- success
                attempts := attempts + 1;
                if attempts > 256 then
                    err <= '1';
                    report "master " & integer'image(INDEX) &
                           " LR/SC retry budget EXHAUSTED (livelock?)"
                        severity error;
                    exit;
                end if;
                for b in 0 to INDEX*4 + (attempts mod 5) loop         -- backoff
                    wait until rising_edge(clk);
                end loop;
            end loop;
        end loop;

        -- ---- pass 6: GRANT-LOCKED RMW pairs (M8 AMO shape) ---------------
        -- lock spans read..write; BREAK_MODE=1 on master 0 drops it EARLY
        -- (right after the locked read) — the negative control: interleaving
        -- must lose updates and the final-counter check must fail.
        for k in 0 to N_RMW-1 loop
            lock <= '1';
            req <= '1'; we <= (others => '0'); addr <= CTR_ADDR; busy <= '1';
            wait until done = '1';
            rd := rdata;
            wait until rising_edge(clk);      -- stale req through the done cycle
            req <= '0'; busy <= '0';
            if BREAK_MODE = 1 and INDEX = 0 then
                lock <= '0';                  -- NEGATIVE CONTROL: early drop
            end if;
            wait until rising_edge(clk);      -- AMO_WRITEBACK
            wait until rising_edge(clk);      -- AMO_COMPUTE
            req <= '1'; we <= "1111"; addr <= CTR_ADDR; busy <= '1';
            wdata <= rd + 1;
            wait until done = '1';
            wait until rising_edge(clk);
            req <= '0'; we <= (others => '0'); busy <= '0';
            lock <= '0';                      -- AMO_COMPLETE
            wait until rising_edge(clk);
        end loop;

        -- ---- pass 7: MUTEX claim-read storm (mutex_bank slot 0) ----------
        for k in 0 to N_MTX-1 loop
            attempts := 0;
            loop
                txn(MTX_ADDR, "0000", x"00000000", "00", rd, scf);  -- claim-read
                exit when rd = x"00000000";                          -- acquired
                got := conv_integer(rd(7 downto 0));                 -- owner marker (A2: > 3 bits at N > 7)
                if got = 0 or got > N_TOTAL then                     -- sanity: owner is 1..N_TOTAL
                    err <= '1';
                    report "master " & integer'image(INDEX) &
                           " MUTEX bogus owner readback" severity error;
                end if;
                attempts := attempts + 1;
                if attempts > 4096 then
                    err <= '1';
                    report "master " & integer'image(INDEX) &
                           " MUTEX acquire budget EXHAUSTED" severity error;
                    exit;
                end if;
                for b in 0 to INDEX*4 + (attempts mod 7) loop        -- backoff
                    wait until rising_edge(clk);
                end loop;
            end loop;
            -- own-marker re-read: a held mutex returns owner = INDEX+1 and
            -- the re-read must NOT disturb ownership
            txn(MTX_ADDR, "0000", x"00000000", "00", rd, scf);
            if conv_integer(rd(7 downto 0)) /= INDEX + 1 then
                err <= '1';
                report "master " & integer'image(INDEX) &
                       " MUTEX own-marker mismatch" severity error;
            end if;
            -- mutex-protected UNLOCKED RMW on PROT_ADDR (the mutex IS the lock)
            txn(PROT_ADDR, "0000", x"00000000", "00", rd, scf);
            txn(PROT_ADDR, "1111", rd + 1,      "00", rd, scf);
            -- release
            txn(MTX_ADDR, "1111", x"00000000", "00", rd, scf);
        end loop;

        finished <= '1';
        wait;
    end process;
end architecture;


-- ---------------------------------------------------------------------------
-- Testbench top: BFMs -> [N_DELAY boundary registers] -> mp_arbiter+resv_unit
--                 -> {shared RAM | mutex_bank} -> [N_DELAY registers] -> BFMs
-- ---------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity arb_lat_tb is
    generic (
        N_DELAY    : natural := 0;   -- boundary-register stages, 0/1/2 (M13 emulation)
        BREAK_MODE : natural := 0;   -- 0 clean; 1 early lock drop; 2 skewed addr pipe
        -- A2 (Argus): master count. 4 = the Castalia gate; 18 = the Argus
        -- fabric shape (s_master/MW widen, owner markers pass 3 bits).
        N_MASTERS  : natural := 4
    );
end entity;

architecture sim of arb_lat_tb is

    constant N   : natural := N_MASTERS;

    -- A2: s_master / mutex master width at this master count (mp_arbiter MW)
    function clog2(v : natural) return natural is
        variable w : natural := 0;
    begin
        while 2**w < v loop
            w := w + 1;
        end loop;
        return w;
    end function;
    function max2(a, b : natural) return natural is
    begin
        if a > b then return a; else return b; end if;
    end function;
    constant MW : natural := max2(1, clog2(N));
    constant AW  : natural := 12;  -- BFM-internal width. The MCU is at SH_AW=15 since M11; the
                                   -- protocol properties proven here (wait-for-release masking,
                                   -- LOCKED pairs, LR/SC ordering) are ADDRESS-WIDTH-INDEPENDENT
                                   -- and the arbiter/resv_unit are generic — 12 keeps the
                                   -- hand-built 12-bit BFMs/checkers intact.
    constant DW  : natural := 32;
    constant NTX : natural := 4;
    constant N_RND  : natural := 24;
    constant N_LRSC : natural := 6;
    constant N_RMW  : natural := 8;
    constant N_MTX  : natural := 6;
    constant CLK_PERIOD : time := 10 ns;

    signal clk        : std_logic := '0';
    signal resetn     : std_logic := '0';
    signal stop_clock : boolean   := false;

    type slv12_arr is array(0 to N-1) of std_logic_vector(AW-1 downto 0);
    type slv32_arr is array(0 to N-1) of std_logic_vector(DW-1 downto 0);
    type slv4_arr  is array(0 to N-1) of std_logic_vector(3 downto 0);
    type slv2_arr  is array(0 to N-1) of std_logic_vector(1 downto 0);

    -- master-side (BFM) signals
    signal m_req, m_lock, m_busy       : std_logic_vector(N-1 downto 0);
    signal m_gnt, m_done, m_scfail     : std_logic_vector(N-1 downto 0);
    signal m_we    : slv4_arr;
    signal m_addr  : slv12_arr;
    signal m_wdata : slv32_arr;
    signal m_lrsc  : slv2_arr;
    signal m_rdata : std_logic_vector(DW-1 downto 0);
    signal m_finished, m_err : std_logic_vector(N-1 downto 0) := (others => '0');

    -- flattened master-side buses (pipe sources)
    signal f_we    : std_logic_vector(N*4-1 downto 0);
    signal f_addr  : std_logic_vector(N*AW-1 downto 0);
    signal f_wdata : std_logic_vector(N*DW-1 downto 0);
    signal f_lrsc  : std_logic_vector(N*2-1 downto 0);

    -- =========================================================================
    -- BOUNDARY PIPES. One wide register per direction per stage — every signal
    -- class shares the SAME depth (the M13 contract; audit finding 5). Taps
    -- select depth 0/1/2. BREAK_MODE=2 skews ONLY the addr slice one stage
    -- shallower (a boundary that "dropped a delay stage") — must be caught.
    -- outbound layout: [req N][lock N][lrsc 2N][we 4N][addr AW*N][wdata DW*N]
    -- inbound  layout: [gnt N][done N][scfail N][rdata DW]
    -- =========================================================================
    constant OBW : natural := N + N + N*2 + N*4 + N*AW + N*DW;
    constant IBW : natural := N + N + N + DW;
    signal ob0, ob1, ob2 : std_logic_vector(OBW-1 downto 0) := (others => '0');
    signal ib0, ib1, ib2 : std_logic_vector(IBW-1 downto 0) := (others => '0');
    signal ob_t, ob_tm1  : std_logic_vector(OBW-1 downto 0);
    signal ib_t          : std_logic_vector(IBW-1 downto 0);

    -- outbound slice bases
    constant OB_REQ  : natural := OBW - N;              -- top N bits
    constant OB_LOCK : natural := OB_REQ - N;
    constant OB_LRSC : natural := OB_LOCK - N*2;
    constant OB_WE   : natural := OB_LRSC - N*4;
    constant OB_ADDR : natural := OB_WE - N*AW;
    constant OB_WDA  : natural := 0;                    -- bottom N*DW bits
    -- inbound slice bases
    constant IB_GNT  : natural := IBW - N;
    constant IB_DONE : natural := IB_GNT - N;
    constant IB_SCF  : natural := IB_DONE - N;
    constant IB_RDA  : natural := 0;

    -- arbiter-side (post-pipe) signals
    signal a_req, a_lock  : std_logic_vector(N-1 downto 0);
    signal a_we           : std_logic_vector(N*4-1 downto 0);
    signal a_addr         : std_logic_vector(N*AW-1 downto 0);
    signal a_wdata        : std_logic_vector(N*DW-1 downto 0);
    signal a_lrsc         : std_logic_vector(N*2-1 downto 0);
    signal arb_gnt, arb_done, arb_scfail : std_logic_vector(N-1 downto 0);
    signal arb_rdata      : std_logic_vector(DW-1 downto 0);

    -- arbiter <-> slaves
    signal s_en      : std_logic;
    signal s_master  : std_logic_vector(MW-1 downto 0);
    signal s_we      : std_logic_vector(3 downto 0);
    signal s_we_g    : std_logic_vector(3 downto 0);   -- resv-gated
    signal s_addr    : std_logic_vector(AW-1 downto 0);
    signal s_wdata   : std_logic_vector(DW-1 downto 0);
    signal s_rdata   : std_logic_vector(DW-1 downto 0);

    -- slave sub-decode (mirrors MCU.vhd region-4 style: mutex_bank at the
    -- page-3 slot-0 mirror = words 0xC00-0xC3F; RAM everywhere else)
    signal mtx_sel   : std_logic;
    signal mtx_en    : std_logic;
    signal ram_en    : std_logic;
    signal rd_mtx    : std_logic := '0';   -- registered read-select (house rule)
    signal mtx_rdata : std_logic_vector(DW-1 downto 0);
    signal ram_rdata : std_logic_vector(DW-1 downto 0) := (others => '0');

    -- shared single-port RAM (1-cycle registered read; the HARDCODED slave contract)
    type ram_t is array(0 to 2**AW-1) of std_logic_vector(DW-1 downto 0);
    signal shram : ram_t := (others => (others => '0'));

    signal mutex_err : std_logic := '0';
    signal cs_err    : std_logic := '0';
    signal ghost_err : std_logic := '0';

    constant CTR_ADDR_I  : natural := 16#F00#;
    constant LRSC_ADDR_I : natural := 16#E00#;
    constant PROT_ADDR_I : natural := 16#D00#;

begin

    clk <= not clk after CLK_PERIOD/2 when not stop_clock else '0';
    resetn <= '0', '1' after 3*CLK_PERIOD;

    -- master BFMs
    gen_masters: for i in 0 to N-1 generate
        mst: entity work.arb_lat_master
            generic map (INDEX => i, NTX => NTX, N_RND => N_RND,
                         N_LRSC => N_LRSC, N_RMW => N_RMW, N_MTX => N_MTX,
                         BREAK_MODE => BREAK_MODE, N_TOTAL => N)
            port map (
                clk => clk, resetn => resetn,
                req => m_req(i), we => m_we(i),
                addr => m_addr(i), wdata => m_wdata(i),
                lock => m_lock(i), lrsc => m_lrsc(i),
                gnt => m_gnt(i), done => m_done(i),
                rdata => m_rdata, scfail => m_scfail(i),
                busy => m_busy(i),
                finished => m_finished(i), err => m_err(i)
            );
    end generate;

    -- flatten BFM arrays
    gen_flat: for i in 0 to N-1 generate
        f_we((i+1)*4-1 downto i*4)      <= m_we(i);
        f_addr((i+1)*AW-1 downto i*AW)  <= m_addr(i);
        f_wdata((i+1)*DW-1 downto i*DW) <= m_wdata(i);
        f_lrsc((i+1)*2-1 downto i*2)    <= m_lrsc(i);
    end generate;

    -- boundary pipes (both directions, one wide reg per stage)
    ob0 <= m_req & m_lock & f_lrsc & f_we & f_addr & f_wdata;
    ib0 <= arb_gnt & arb_done & arb_scfail & arb_rdata;

    pipes: process(clk, resetn)
    begin
        if resetn = '0' then
            ob1 <= (others => '0'); ob2 <= (others => '0');
            ib1 <= (others => '0'); ib2 <= (others => '0');
        elsif rising_edge(clk) then
            ob1 <= ob0; ob2 <= ob1;
            ib1 <= ib0; ib2 <= ib1;
        end if;
    end process;

    ob_t   <= ob0 when N_DELAY = 0 else ob1 when N_DELAY = 1 else ob2;
    ob_tm1 <= ob0 when N_DELAY <= 1 else ob1;    -- one stage shallower (BREAK_MODE=2)
    ib_t   <= ib0 when N_DELAY = 0 else ib1 when N_DELAY = 1 else ib2;

    -- arbiter-side unslicing
    a_req   <= ob_t(OB_REQ+N-1     downto OB_REQ) when BREAK_MODE /= 2 else
               ob_tm1(OB_REQ+N-1   downto OB_REQ);  -- NEGATIVE CONTROL: req
                                                    -- one stage EARLY => pick
                                                    -- samples stale addr/wdata
    a_lock  <= ob_t(OB_LOCK+N-1    downto OB_LOCK);
    a_lrsc  <= ob_t(OB_LRSC+N*2-1  downto OB_LRSC);
    a_we    <= ob_t(OB_WE+N*4-1    downto OB_WE);
    a_addr  <= ob_t(OB_ADDR+N*AW-1 downto OB_ADDR);
    a_wdata <= ob_t(OB_WDA+N*DW-1  downto OB_WDA);

    -- master-side unslicing
    m_gnt    <= ib_t(IB_GNT+N-1  downto IB_GNT);
    m_done   <= ib_t(IB_DONE+N-1 downto IB_DONE);
    m_scfail <= ib_t(IB_SCF+N-1  downto IB_SCF);
    m_rdata  <= ib_t(IB_RDA+DW-1 downto IB_RDA);

    -- DUT: the real arbiter
    dut: entity work.mp_arbiter
        generic map (N => N, ADDR_WIDTH => AW, DATA_WIDTH => DW, MW => MW)
        port map (
            clk => clk, resetn => resetn,
            req => a_req, we => a_we, addr => a_addr, wdata => a_wdata,
            lock => a_lock,
            gnt => arb_gnt, done => arb_done, rdata => arb_rdata,
            s_en => s_en, s_master => s_master, s_we => s_we,
            s_addr => s_addr, s_wdata => s_wdata, s_rdata => s_rdata
        );

    -- DUT: the real reservation unit (snoops every txn; gates SC writes)
    resv0: entity work.resv_unit
        generic map (N => N, ADDR_WIDTH => AW)
        port map (
            clk => clk, resetn => resetn,
            lr_sc => a_lrsc, gnt => arb_gnt,
            s_en => s_en, s_we => s_we, s_addr => s_addr,
            s_we_gated => s_we_g, sc_fail => arb_scfail
        );

    -- DUT: the real mutex bank at the page-3 slot-0 mirror (words 0xC00-0xC3F)
    mtx_sel <= '1' when s_addr(11 downto 10) = "11" and s_addr(9 downto 6) = "0000"
               else '0';
    mtx_en  <= s_en and mtx_sel;
    ram_en  <= s_en and not mtx_sel;

    mtx0: entity work.mutex_bank
        generic map (NMUTEX => 16, MW => MW)
        port map (
            clk => clk, resetn => resetn,
            en => mtx_en, we => s_we_g, addr => s_addr(3 downto 0),
            wdata => s_wdata, master => s_master, rdata => mtx_rdata
        );

    -- shared single-port RAM slave: 1-cycle registered read, per-lane writes
    -- through the resv-GATED strobes (a suppressed SC write must not commit)
    slave: process(clk)
        variable merged : std_logic_vector(DW-1 downto 0);
    begin
        if rising_edge(clk) then
            if ram_en = '1' then
                merged := shram(conv_integer(s_addr));
                for l in 0 to 3 loop
                    if s_we_g(l) = '1' then
                        merged((l+1)*8-1 downto l*8) := s_wdata((l+1)*8-1 downto l*8);
                    end if;
                end loop;
                shram(conv_integer(s_addr)) <= merged;
                ram_rdata <= merged;
            end if;
        end if;
    end process;

    -- registered read-select mux (house slave-mux rule, MCU.vhd shslv_rd_sel)
    rd_sel: process(clk, resetn)
    begin
        if resetn = '0' then
            rd_mtx <= '0';
        elsif rising_edge(clk) then
            if s_en = '1' then
                rd_mtx <= mtx_sel;
            end if;
        end if;
    end process;
    s_rdata <= mtx_rdata when rd_mtx = '1' else ram_rdata;

    -- ---- checkers -------------------------------------------------------
    -- grant mutual exclusion (arbiter side)
    mutex_chk: process(clk)
        variable cnt : natural;
    begin
        if rising_edge(clk) then
            cnt := 0;
            for i in 0 to N-1 loop
                if arb_gnt(i) = '1' then cnt := cnt + 1; end if;
            end loop;
            if cnt > 1 then
                mutex_err <= '1';
                report "MUTUAL EXCLUSION VIOLATED" severity error;
            end if;
        end if;
    end process;

    -- locked-pair critical section (master side; BFM holds lock/we across done)
    cs_chk: process(clk)
        variable cs_active : boolean := false;
        variable cs_owner  : natural range 0 to N-1 := 0;
    begin
        if rising_edge(clk) then
            for i in 0 to N-1 loop
                if m_done(i) = '1' then
                    if cs_active and i /= cs_owner then
                        cs_err <= '1';
                        report "GRANT-LOCK VIOLATED: master " & integer'image(i) &
                               " completed a txn inside master " &
                               integer'image(cs_owner) & "'s locked RMW pair"
                            severity error;
                    elsif cs_active and i = cs_owner then
                        cs_active := false;
                    elsif m_lock(i) = '1' and m_we(i) = "0000" then
                        cs_active := true;
                        cs_owner  := i;
                    end if;
                end if;
            end loop;
        end if;
    end process;

    -- GHOST-DONE detector: a done pulse reaching a master with NOTHING in
    -- flight is the delayed-stale-req ghost-transaction signature (M5a class)
    ghost_chk: process(clk)
    begin
        if rising_edge(clk) then
            for i in 0 to N-1 loop
                if m_done(i) = '1' and m_busy(i) = '0' then
                    ghost_err <= '1';
                    report "GHOST DONE: master " & integer'image(i) &
                           " got done with no transaction in flight"
                        severity error;
                end if;
            end loop;
        end if;
    end process;

    -- scoreboard / banner
    report_proc: process
        variable v : natural;
    begin
        wait until resetn = '1';
        -- A2: watchdog scales with the master count (more masters = more
        -- serialized traffic + contention); 200000 cycles at the N=4 gate.
        for t in 0 to 50000 * N loop
            wait until rising_edge(clk);
            exit when m_finished = (m_finished'range => '1');
        end loop;

        if m_finished /= (m_finished'range => '1') then
            report "WATCHDOG: not all masters finished (starvation/deadlock)"
                severity failure;
        end if;

        wait for 5*CLK_PERIOD;

        -- AMO pass: no lost updates
        if shram(CTR_ADDR_I) /= conv_std_logic_vector(N*N_RMW, 32) then
            v := conv_integer(shram(CTR_ADDR_I)(30 downto 0));
            report "GRANT-LOCK COUNTER MISMATCH: expected " &
                   integer'image(N*N_RMW) & " got " & integer'image(v)
                severity failure;
        end if;
        -- LR/SC pass: every successful SC really committed exactly once
        if shram(LRSC_ADDR_I) /= conv_std_logic_vector(N*N_LRSC, 32) then
            v := conv_integer(shram(LRSC_ADDR_I)(30 downto 0));
            report "LR/SC COUNTER MISMATCH: expected " &
                   integer'image(N*N_LRSC) & " got " & integer'image(v)
                severity failure;
        end if;
        -- mutex pass: the mutex really excluded (unlocked RMW under mutex)
        if shram(PROT_ADDR_I) /= conv_std_logic_vector(N*N_MTX, 32) then
            v := conv_integer(shram(PROT_ADDR_I)(30 downto 0));
            report "MUTEX-PROTECTED COUNTER MISMATCH: expected " &
                   integer'image(N*N_MTX) & " got " & integer'image(v)
                severity failure;
        end if;

        if (m_err = (m_err'range => '0')) and mutex_err = '0'
           and cs_err = '0' and ghost_err = '0' then
            report "ALL CHECKS PASSED" severity note;
        else
            report "CHECKS FAILED (m_err/mutex_err/cs_err/ghost_err set)"
                severity failure;
        end if;

        stop_clock <= true;
        wait;
    end process;

end architecture;
