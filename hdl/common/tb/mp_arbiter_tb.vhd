/* =============================================================================
   mp_arbiter_tb.vhd : self-checking testbench for mp_arbiter
   =============================================================================
   Four master BFMs hammer one shared single-port RAM concurrently, each writing and reading back a known pattern over its own disjoint address range.
   Checks mutual exclusion (at most one gnt per clock), data integrity, liveness under round-robin (watchdog on any starvation), grant-locking (lock-held read-modify-write pairs on a COMMON counter, whose final value must be exactly N*N_RMW), and the slave-side `s_stall` handshake.
   Stall properties: S0 every unstalled transaction takes exactly BASE_LAT, S1 a stall of SP_LEN cycles delays done by SP_LEN with correct rdata, S2 no other master completes during a stall, S3 a 1-cycle stall released mid-transaction still completes.
   BFMs hold req THROUGH the done cycle and drop it one clock later like a hart tile's sh_acked flop, so wait-for-release masking of a stale req is exercised on every transaction.
   PASS banner: "ALL CHECKS PASSED" (grepped by the runner).
   ============================================================================= */

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

/* ---------------------------------------------------------------------------
   Master BFM: drives one master port of the arbiter through a write pass then a read-back pass, flagging any mismatch on `err`.
   --------------------------------------------------------------------------- */
entity mp_master is
    generic (
        INDEX : natural := 0;
        NTX   : natural := 4;    -- transactions (addresses) per phase
        N_RMW : natural := 8     -- grant-locked RMW pairs on the common counter
    );
    port (
        clk      : in  std_logic;
        resetn   : in  std_logic;
        -- arbiter master interface (we = 4 active-high byte-lane strobes)
        req      : out std_logic;
        we       : out std_logic_vector(3 downto 0);
        addr     : out std_logic_vector(11 downto 0);
        wdata    : out std_logic_vector(31 downto 0);
        lock     : out std_logic;   -- grant-lock, the core's amo_lock
        gnt      : in  std_logic;
        done     : in  std_logic;
        rdata    : in  std_logic_vector(31 downto 0);
        -- STALL PASS handshake: the master parks on `ready` when its own passes are done, then serves one read per `sp_phase` step.
        -- That keeps all four requesting SIMULTANEOUSLY when the top asserts s_stall, so queueing behind a stalled transaction is a real property and not a solo run.
        sp_phase : in  integer;
        ready    : out std_logic;
        -- status
        finished : out std_logic;
        err      : out std_logic
    );
end entity;

architecture bfm of mp_master is
    -- Disjoint address per (master,k), with a distinct data pattern per (master,k).
    function addr_for(k : natural) return std_logic_vector is
    begin
        return conv_std_logic_vector(INDEX*16 + k, 12);
    end function;
    function data_for(k : natural) return std_logic_vector is
    begin
        return x"A5" & conv_std_logic_vector(INDEX, 8)
                     & conv_std_logic_vector(k, 8) & x"C3";
    end function;
    -- COMMON counter word for the grant-locked RMW pass, outside every master's private 0..N*16-1 range.
    constant CTR_ADDR : std_logic_vector(11 downto 0) := x"F00";
begin
    process
        variable rd       : std_logic_vector(31 downto 0);
        variable expected : std_logic_vector(31 downto 0);
        variable lane     : natural;
    begin
        req <= '0'; we <= (others => '0'); addr <= (others => '0'); wdata <= (others => '0');
        lock <= '0';
        finished <= '0'; err <= '0'; ready <= '0';
        wait until resetn = '1';
        wait until rising_edge(clk);

        -- Tile-accurate req timing in every pass: req is dropped one clock AFTER the done cycle, like a hart tile's sh_acked flop.
        -- The arbiter's next pick edge therefore sees the served master's req stale-high and must mask it on EVERY transaction.

        -- WRITE pass (full word: all four lane strobes)
        for k in 0 to NTX-1 loop
            req <= '1'; we <= "1111"; addr <= addr_for(k); wdata <= data_for(k);
            wait until done = '1';           -- transaction complete
            wait until rising_edge(clk);      -- hold req through the done cycle
            req <= '0'; we <= (others => '0');
            wait until rising_edge(clk);      -- re-request 2 cycles after done
        end loop;

        -- READ-BACK pass
        for k in 0 to NTX-1 loop
            req <= '1'; we <= (others => '0'); addr <= addr_for(k);
            wait until done = '1';
            rd := rdata;                      -- valid on the done cycle
            if rd /= data_for(k) then
                err <= '1';
                report "mp_master " & integer'image(INDEX) &
                       " readback MISMATCH at k=" & integer'image(k) severity error;
            end if;
            wait until rising_edge(clk);
            req <= '0';
            wait until rising_edge(clk);
        end loop;

        -- BYTE-LANE pass: overwrite ONE byte of word 0 with 0xEE and check the merged word, since the other lanes must be untouched.
        lane := INDEX mod 4;
        req <= '1'; addr <= addr_for(0); wdata <= x"EEEEEEEE";
        we <= (others => '0'); we(lane) <= '1';
        wait until done = '1';
        wait until rising_edge(clk);
        req <= '0'; we <= (others => '0');
        wait until rising_edge(clk);

        expected := data_for(0);
        expected((lane+1)*8-1 downto lane*8) := x"EE";
        req <= '1'; we <= (others => '0'); addr <= addr_for(0);
        wait until done = '1';
        rd := rdata;
        if rd /= expected then
            err <= '1';
            report "mp_master " & integer'image(INDEX) &
                   " BYTE-LANE merge MISMATCH (lane " & integer'image(lane) & ")"
                severity error;
        end if;
        wait until rising_edge(clk);
        req <= '0';
        wait until rising_edge(clk);

        -- GRANT-LOCKED RMW pass: N_RMW lock-held read, increment and write pairs on the COMMON counter, mimicking the core's AMO flow.
        -- lock rises with the read request, the write follows 2 idle cycles after the read's ack, lock drops after the write completes; any lost update here means broken locking.
        for k in 0 to N_RMW-1 loop
            lock <= '1';
            req <= '1'; we <= (others => '0'); addr <= CTR_ADDR;
            wait until done = '1';
            rd := rdata;                      -- counter old value
            wait until rising_edge(clk);      -- stale req through the done cycle
            req <= '0';
            wait until rising_edge(clk);      -- AMO_WRITEBACK
            wait until rising_edge(clk);      -- AMO_COMPUTE
            req <= '1'; we <= "1111"; addr <= CTR_ADDR;
            wdata <= rd + 1;                  -- read-modify-write
            wait until done = '1';
            wait until rising_edge(clk);
            req <= '0'; we <= (others => '0');
            lock <= '0';                      -- AMO_COMPLETE
            wait until rising_edge(clk);
        end loop;

        /* ---------------------------------------------------------------
           STALL PASS: two synchronised rounds; in each, all four masters read their own word 0 at once and the top stalls whichever transaction the arbiter picks first.
           The data check reuses the `expected` word from the byte-lane pass, so a stalled transaction completing with a fabricated word fails here.
           --------------------------------------------------------------- */
        ready <= '1';
        for p in 1 to 2 loop
            -- Poll, never `wait until sp_phase = p`: a master arriving after the phase has stepped would wait forever for an event that is already gone.
            while sp_phase < p loop
                wait until rising_edge(clk);
            end loop;
            req <= '1'; we <= (others => '0'); addr <= addr_for(0);
            wait until done = '1';
            rd := rdata;
            if rd /= expected then
                err <= '1';
                report "mp_master " & integer'image(INDEX) &
                       " STALL-PASS readback MISMATCH (phase " &
                       integer'image(p) & ")" severity error;
            end if;
            wait until rising_edge(clk);
            req <= '0';
            wait until rising_edge(clk);
        end loop;

        finished <= '1';
        wait;
    end process;
end architecture;


/* ---------------------------------------------------------------------------
   Testbench top
   --------------------------------------------------------------------------- */
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity mp_arbiter_tb is
end entity;

architecture sim of mp_arbiter_tb is

    constant N   : natural := 4;
    constant AW  : natural := 12;  -- BFM-internal width; the MCU runs a wider SH_AW.
                                   -- The protocol properties proven here (wait-for-release masking, LOCKED pairs, LR/SC ordering) are ADDRESS-WIDTH-INDEPENDENT, and the arbiter and resv_unit are generic.
    constant DW  : natural := 32;
    constant NTX : natural := 4;
    constant CLK_PERIOD : time := 10 ns;

    signal clk        : std_logic := '0';
    signal resetn     : std_logic := '0';
    signal stop_clock : boolean   := false;

    -- Master side of the arbiter: per-master arrays, one driver each, so no bus conflict.
    type slv12_arr is array(0 to N-1) of std_logic_vector(AW-1 downto 0);
    type slv32_arr is array(0 to N-1) of std_logic_vector(DW-1 downto 0);
    type slv4_arr  is array(0 to N-1) of std_logic_vector(3 downto 0);
    signal m_req, m_gnt, m_done : std_logic_vector(N-1 downto 0);
    signal m_lock  : std_logic_vector(N-1 downto 0);   -- grant-lock
    signal m_we    : slv4_arr;
    signal m_addr  : slv12_arr;
    signal m_wdata : slv32_arr;
    signal m_finished, m_err : std_logic_vector(N-1 downto 0) := (others => '0');
    signal m_ready : std_logic_vector(N-1 downto 0) := (others => '0');

    -- flattened buses to the arbiter
    signal f_we    : std_logic_vector(N*4-1 downto 0);
    signal f_addr  : std_logic_vector(N*AW-1 downto 0);
    signal f_wdata : std_logic_vector(N*DW-1 downto 0);
    signal a_rdata : std_logic_vector(DW-1 downto 0);

    -- Slave side of the arbiter, going to the shared RAM.
    signal s_en    : std_logic;
    signal s_we    : std_logic_vector(3 downto 0);
    signal s_addr  : std_logic_vector(AW-1 downto 0);
    signal s_wdata : std_logic_vector(DW-1 downto 0);
    signal s_rdata : std_logic_vector(DW-1 downto 0);

    signal mutex_err : std_logic := '0';
    signal cs_err    : std_logic := '0';   -- foreign txn inside a locked RMW pair

    /* =========================================================================
       the s_stall apparatus
       ========================================================================= */
    signal s_stall   : std_logic;
    signal sp_arm    : std_logic := '0';   -- stall the NEXT transaction
    signal sp_launch : std_logic;          -- combinational, with the s_en strobe
    signal sp_busy   : std_logic;
    signal sp_cnt    : integer := 0;
    signal sp_load   : integer := 0;       -- SP_LEN for the armed stall
    signal sp_phase  : integer := 0;       -- 0 idle, 1 = S1/S2 round, 2 = S3 round

    constant SP_LEN_LONG  : integer := 12; -- S1/S2: longer than the 6-mclk TCM read
    constant SP_LEN_SHORT : integer := 1;  -- S3: the abort shape, shortest legal

    -- Latency is counted in edges at which the monitor OBSERVED, from s_en high to done high.
    -- An unstalled transaction is 3 in those units: s_en presented in IDLE, then LATCH, then DATA/done, each seen one edge after it is driven.
    constant BASE_LAT : integer := 3;
    signal n_txn      : integer := 0;   -- transactions the monitor timed
    signal n_unstall  : integer := 0;   -- of which unstalled
    signal lat_bad    : integer := 0;   -- unstalled transactions NOT at BASE_LAT
    signal n_stalled  : integer := 0;
    signal stall_lat1 : integer := 0;   -- observed latency of the S1 stall
    signal stall_cyc1 : integer := 0;   -- and how many cycles that stall lasted
    signal stall_lat2 : integer := 0;   -- observed latency of the S3 stall
    signal stall_cyc2 : integer := 0;   -- and how many cycles that stall lasted
    signal foreign_done_err : std_logic := '0';   -- a done while s_stall was up
    constant N_RMW   : natural := 8;       -- locked RMW pairs per master
    constant CTR_ADDR_I : natural := 16#F00#;  -- the common counter word

    -- shared single-port RAM (1-cycle registered read latency, active-high en)
    type ram_t is array(0 to 2**AW-1) of std_logic_vector(DW-1 downto 0);
    signal shram : ram_t := (others => (others => '0'));

    -- s_stall is named explicitly: it defaults to '0' on the entity, so a declaration that omits it still binds and elaborates, leaving the port untested.
    component mp_arbiter
        generic (N : natural; ADDR_WIDTH : natural; DATA_WIDTH : natural);
        port (
            clk    : in  std_logic;
            resetn : in  std_logic;
            req    : in  std_logic_vector(N-1 downto 0);
            we     : in  std_logic_vector(N*4-1 downto 0);
            addr   : in  std_logic_vector(N*ADDR_WIDTH-1 downto 0);
            wdata  : in  std_logic_vector(N*DATA_WIDTH-1 downto 0);
            lock   : in  std_logic_vector(N-1 downto 0);
            gnt    : out std_logic_vector(N-1 downto 0);
            done   : out std_logic_vector(N-1 downto 0);
            rdata  : out std_logic_vector(DATA_WIDTH-1 downto 0);
            s_en    : out std_logic;
            s_stall : in  std_logic;
            s_we    : out std_logic_vector(3 downto 0);
            s_addr  : out std_logic_vector(ADDR_WIDTH-1 downto 0);
            s_wdata : out std_logic_vector(DATA_WIDTH-1 downto 0);
            s_rdata : in  std_logic_vector(DATA_WIDTH-1 downto 0)
        );
    end component;

begin

    -- clock / reset
    clk <= not clk after CLK_PERIOD/2 when not stop_clock else '0';
    resetn <= '0', '1' after 3*CLK_PERIOD;

    -- flatten per-master arrays into the arbiter's buses
    gen_flat: for i in 0 to N-1 generate
        f_we((i+1)*4-1 downto i*4)      <= m_we(i);
        f_addr((i+1)*AW-1 downto i*AW)  <= m_addr(i);
        f_wdata((i+1)*DW-1 downto i*DW) <= m_wdata(i);
    end generate;

    -- master BFMs (4 concurrent contenders)
    gen_masters: for i in 0 to N-1 generate
        mst: entity work.mp_master
            generic map (INDEX => i, NTX => NTX, N_RMW => N_RMW)
            port map (
                clk => clk, resetn => resetn,
                req => m_req(i), we => m_we(i),
                addr => m_addr(i), wdata => m_wdata(i),
                lock => m_lock(i),
                gnt => m_gnt(i), done => m_done(i), rdata => a_rdata,
                sp_phase => sp_phase, ready => m_ready(i),
                finished => m_finished(i), err => m_err(i)
            );
    end generate;

    -- DUT
    dut: mp_arbiter
        generic map (N => N, ADDR_WIDTH => AW, DATA_WIDTH => DW)
        port map (
            clk => clk, resetn => resetn,
            req => m_req, we => f_we, addr => f_addr, wdata => f_wdata,
            lock => m_lock,
            gnt => m_gnt, done => m_done, rdata => a_rdata,
            s_en => s_en, s_stall => s_stall, s_we => s_we, s_addr => s_addr,
            s_wdata => s_wdata, s_rdata => s_rdata
        );

    /* -------------------------------------------------------------------------
       THE STALL GENERATOR, same shape as the real aperture sequencer: s_stall is `launch or busy`, combinational on the enable strobe.
       It MUST be combinational: the arbiter samples s_stall at the edge that would otherwise take it from LATCH to DATA, so a purely registered stall arrives one cycle too late and is a silent no-op.
       ------------------------------------------------------------------------- */
    sp_launch <= s_en and sp_arm;
    sp_busy   <= '1' when sp_cnt /= 0 else '0';
    s_stall   <= sp_launch or sp_busy;

    -- sp_arm and sp_load are owned HERE (one driver) and armed by the phase stepping.
    -- The arm is a one-shot: exactly one transaction per phase is stalled, so everything else in the run stays on the identity path.
    stall_gen: process(clk)
        variable ph_prev : integer := 0;
    begin
        if rising_edge(clk) then
            if sp_phase /= ph_prev then
                ph_prev := sp_phase;
                if sp_phase = 1 then
                    -- S1/S2 round: a long stall, so the other masters queue behind it.
                    sp_arm  <= '1';
                    sp_load <= SP_LEN_LONG;
                elsif sp_phase = 2 then
                    -- S3 round: the abort shape, the shortest legal stall.
                    sp_arm  <= '1';
                    sp_load <= SP_LEN_SHORT;
                end if;
            end if;
            if sp_launch = '1' then
                sp_arm <= '0';
                sp_cnt <= sp_load - 1;
            elsif sp_cnt /= 0 then
                sp_cnt <= sp_cnt - 1;
            end if;
        end if;
    end process;

    /* -------------------------------------------------------------------------
       THE LATENCY MONITOR: times every arbiter transaction from the edge s_en is observed to the edge done is observed, counting how many of those edges had s_stall up.
       Invariants: an unstalled transaction always takes BASE_LAT, a stalled one takes BASE_LAT plus the cycles stalled, and no master may complete while s_stall is up.
       ------------------------------------------------------------------------- */
    lat_mon: process(clk)
        variable active : boolean := false;
        variable n      : integer := 0;
        variable sc     : integer := 0;
    begin
        if rising_edge(clk) then
            if s_stall = '1' and m_done /= (m_done'range => '0') then
                foreign_done_err <= '1';
                report "S2 VIOLATED: a transaction completed while s_stall was high"
                    severity error;
            end if;
            if (not active) and s_en = '1' then
                active := true; n := 0; sc := 0;
            end if;
            if active then
                n := n + 1;
                if s_stall = '1' then sc := sc + 1; end if;
                if m_done /= (m_done'range => '0') then
                    active := false;
                    n_txn <= n_txn + 1;
                    if sc = 0 then
                        n_unstall <= n_unstall + 1;
                        if n /= BASE_LAT then
                            lat_bad <= lat_bad + 1;
                            report "S0 VIOLATED: unstalled transaction latency " &
                                   integer'image(n) & " (expected " &
                                   integer'image(BASE_LAT) & ")" severity error;
                        end if;
                    else
                        n_stalled <= n_stalled + 1;
                        if sp_phase = 1 then
                            stall_lat1 <= n; stall_cyc1 <= sc;
                        else
                            stall_lat2 <= n; stall_cyc2 <= sc;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Shared single-port RAM slave: matches the arbiter's 1-cycle-latency model, with per-byte-lane writes.
    slave: process(clk)
        variable merged : std_logic_vector(DW-1 downto 0);
    begin
        if rising_edge(clk) then
            if s_en = '1' then
                merged := shram(conv_integer(s_addr));
                for l in 0 to 3 loop
                    if s_we(l) = '1' then
                        merged((l+1)*8-1 downto l*8) := s_wdata((l+1)*8-1 downto l*8);
                    end if;
                end loop;
                shram(conv_integer(s_addr)) <= merged;
                s_rdata <= merged;   -- read returns stored (merged) word
            end if;
        end if;
    end process;

    -- mutual-exclusion checker: never more than one grant asserted
    mutex_chk: process(clk)
        variable cnt : natural;
    begin
        if rising_edge(clk) then
            cnt := 0;
            for i in 0 to N-1 loop
                if m_gnt(i) = '1' then cnt := cnt + 1; end if;
            end loop;
            if cnt > 1 then
                mutex_err <= '1';
                report "MUTUAL EXCLUSION VIOLATED: " & integer'image(cnt) &
                       " grants asserted simultaneously" severity error;
            end if;
        end if;
    end process;

    -- Critical-section checker: from a lock-holder's READ done to its WRITE done, NO other master may complete a transaction.
    -- m_we is held through the done cycle by the BFM, so it classifies the transaction type.
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
                        cs_active := false;          -- the pair's write landed
                    elsif m_lock(i) = '1' and m_we(i) = "0000" then
                        cs_active := true;           -- locked read opens the CS
                        cs_owner  := i;
                    end if;
                end if;
            end loop;
        end if;
    end process;

    -- scoreboard / banner
    report_proc: process
        variable txn0 : integer;
    begin
        wait until resetn = '1';

        /* =====================================================================
           STALL PASS, run BEFORE the finish watchdog: the masters park on `ready` and only set `finished` once both stall rounds are through them.
           ===================================================================== */
        for t in 0 to 5000 loop
            wait until rising_edge(clk);
            exit when m_ready = (m_ready'range => '1');
        end loop;
        if m_ready /= (m_ready'range => '1') then
            report "WATCHDOG: masters never reached the stall pass" severity failure;
        end if;

        for p in 1 to 2 loop
            txn0 := n_txn;
            sp_phase <= p;
            for t in 0 to 2000 loop
                wait until rising_edge(clk);
                exit when n_txn >= txn0 + N;
            end loop;
            if n_txn < txn0 + N then
                report "STALL PASS WATCHDOG: only " & integer'image(n_txn - txn0) &
                       " of " & integer'image(N) & " masters completed in phase " &
                       integer'image(p) & " -- s_stall did not release"
                    severity failure;
            end if;
            wait for 10*CLK_PERIOD;
        end loop;
        sp_phase <= 0;

        -- S1: the long stall.  Delayed done, by exactly the stall length.
        if not (stall_cyc1 = SP_LEN_LONG and stall_lat1 = BASE_LAT + SP_LEN_LONG) then
            report "S1 FAILED: stalled transaction latency " &
                   integer'image(stall_lat1) & " with " &
                   integer'image(stall_cyc1) & " stalled cycles (expected " &
                   integer'image(BASE_LAT + SP_LEN_LONG) & " / " &
                   integer'image(SP_LEN_LONG) & ")" severity failure;
        end if;
        -- S3: the abort shape, a stall released after the shortest possible time, by the requester rather than by a completion.
        if not (stall_cyc2 = SP_LEN_SHORT and stall_lat2 = BASE_LAT + SP_LEN_SHORT) then
            report "S3 FAILED: aborted-stall transaction latency " &
                   integer'image(stall_lat2) & " with " &
                   integer'image(stall_cyc2) & " stalled cycles (expected " &
                   integer'image(BASE_LAT + SP_LEN_SHORT) & " / " &
                   integer'image(SP_LEN_SHORT) & ")" severity failure;
        end if;
        if n_stalled /= 2 then
            report "STALL PASS: " & integer'image(n_stalled) &
                   " transactions were stalled, expected exactly 2" severity failure;
        end if;
        if foreign_done_err /= '0' then
            report "S2 FAILED: a transaction completed while s_stall was high"
                severity failure;
        end if;
        report "mp_arbiter_tb: s_stall pass -- " & integer'image(n_txn) &
               " transactions timed, " & integer'image(n_unstall) &
               " unstalled (all at latency " & integer'image(BASE_LAT) &
               ", lat_bad=" & integer'image(lat_bad) & "), 2 stalled: " &
               integer'image(stall_lat1) & " mclk for a " &
               integer'image(SP_LEN_LONG) & "-cycle stall and " &
               integer'image(stall_lat2) & " mclk for a " &
               integer'image(SP_LEN_SHORT) & "-cycle stall" severity note;

        -- Wait for all masters to finish, with a starvation/deadlock watchdog.
        for t in 0 to 5000 loop
            wait until rising_edge(clk);
            exit when m_finished = (m_finished'range => '1');
        end loop;

        if m_finished /= (m_finished'range => '1') then
            report "WATCHDOG: not all masters finished (possible starvation/deadlock)"
                severity failure;
        end if;

        wait for 5*CLK_PERIOD;

        -- The grant-locked RMW pass must have lost NO updates: the common counter is exactly N*N_RMW, or some pair was interleaved.
        if shram(CTR_ADDR_I) /= conv_std_logic_vector(N*N_RMW, 32) then
            report "GRANT-LOCK COUNTER MISMATCH: expected " &
                   integer'image(N*N_RMW) & " got " &
                   integer'image(conv_integer(shram(CTR_ADDR_I)(30 downto 0)))
                severity failure;
        end if;

        -- S0 identity regression: every transaction not deliberately stalled took exactly BASE_LAT, so s_stall = '0' costs nothing, measured rather than inferred from the port default.
        if lat_bad /= 0 then
            report "S0 FAILED: " & integer'image(lat_bad) &
                   " unstalled transactions did not take " &
                   integer'image(BASE_LAT) & " mclk" severity failure;
        end if;
        if n_unstall < 40 then
            report "S0 VACUOUS: only " & integer'image(n_unstall) &
                   " unstalled transactions were timed" severity failure;
        end if;

        if (m_err = (m_err'range => '0')) and (mutex_err = '0')
           and (cs_err = '0') and (foreign_done_err = '0') and (lat_bad = 0) then
            report "ALL CHECKS PASSED" severity note;
        else
            report "CHECKS FAILED (m_err, mutex_err or cs_err set)" severity failure;
        end if;

        stop_clock <= true;
        wait;
    end process;

end architecture;
