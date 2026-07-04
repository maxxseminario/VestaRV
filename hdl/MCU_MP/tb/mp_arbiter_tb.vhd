-- =============================================================================
-- mp_arbiter_tb.vhd  (M3c) -- self-checking testbench for mp_arbiter
-- =============================================================================
-- Proves the round-robin full-handshake serializer with SYNTHETIC contending
-- traffic (the M3c pass path: no boot code needed). Four master BFMs hammer one
-- shared single-port RAM concurrently. Each master owns a DISJOINT address range
-- (shared read-modify-write atomicity is M4, not here), writes a known pattern,
-- then reads it back and checks it.
--
-- Checks (all must hold for the banner):
--   * mutual exclusion  -- at most one gnt bit high on every clock (checker proc)
--   * data integrity    -- every master reads back exactly what it wrote
--   * liveness/fairness -- all four masters finish (round-robin => no starvation);
--                          a watchdog fails the test if they don't.
--   * grant-locking (M8) -- all four masters run TILE-ACCURATE lock-held
--     read-modify-write pairs on a COMMON counter word; a critical-section
--     checker fails on any foreign transaction inside a locked pair, and the
--     final counter must be EXACTLY N*N_RMW (any interleaving loses updates).
--
-- M8 BFM hardening: req is held THROUGH the done cycle and dropped one clock
-- later, exactly like a hart tile's sh_acked flop -- the stale-req shape that
-- produced the M5a ghost-transaction bug (the old BFM dropped req at done and
-- could never reproduce that class). This exercises mask_last on every txn.
-- PASS banner: "ALL CHECKS PASSED" (grepped by the runner).
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

-- ---------------------------------------------------------------------------
-- Master BFM: drives one master port of the arbiter through a write pass then a
-- read-back pass, flagging any mismatch on `err`.
-- ---------------------------------------------------------------------------
entity mp_master is
    generic (
        INDEX : natural := 0;
        NTX   : natural := 4;    -- transactions (addresses) per phase
        N_RMW : natural := 8     -- grant-locked RMW pairs on the common counter (M8)
    );
    port (
        clk      : in  std_logic;
        resetn   : in  std_logic;
        -- arbiter master interface (we = 4 active-high byte-lane strobes, M4a)
        req      : out std_logic;
        we       : out std_logic_vector(3 downto 0);
        addr     : out std_logic_vector(11 downto 0);
        wdata    : out std_logic_vector(31 downto 0);
        lock     : out std_logic;   -- M8: grant-lock (the core's amo_lock)
        gnt      : in  std_logic;
        done     : in  std_logic;
        rdata    : in  std_logic_vector(31 downto 0);
        -- status
        finished : out std_logic;
        err      : out std_logic
    );
end entity;

architecture bfm of mp_master is
    -- disjoint address per (master,k); distinct data pattern per (master,k)
    function addr_for(k : natural) return std_logic_vector is
    begin
        return conv_std_logic_vector(INDEX*16 + k, 12);
    end function;
    function data_for(k : natural) return std_logic_vector is
    begin
        return x"A5" & conv_std_logic_vector(INDEX, 8)
                     & conv_std_logic_vector(k, 8) & x"C3";
    end function;
    -- COMMON counter word for the grant-locked RMW pass (outside every
    -- master's private 0..N*16-1 range)
    constant CTR_ADDR : std_logic_vector(11 downto 0) := x"F00";
begin
    process
        variable rd       : std_logic_vector(31 downto 0);
        variable expected : std_logic_vector(31 downto 0);
        variable lane     : natural;
    begin
        req <= '0'; we <= (others => '0'); addr <= (others => '0'); wdata <= (others => '0');
        lock <= '0';
        finished <= '0'; err <= '0';
        wait until resetn = '1';
        wait until rising_edge(clk);

        -- M8 NOTE (tile-accurate req timing, all passes): req is dropped one
        -- clock AFTER the done cycle — a hart tile's sh_acked flop clears req
        -- one mclk after done, so the arbiter's next pick edge sees the served
        -- master's req stale-high (the M5a ghost-txn shape). mask_last must
        -- swallow it on EVERY transaction here.

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

        -- BYTE-LANE pass (M4a): overwrite ONE byte of word 0 with 0xEE and
        -- check the merged word — other lanes must be untouched.
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

        -- GRANT-LOCKED RMW pass (M8): N_RMW lock-held read+increment+write
        -- pairs on the COMMON counter, mimicking the core's AMO flow: lock
        -- rises with the read request (amo_lock spans the whole AMO), the
        -- write follows 2 idle cycles after the read's ack (AMO_WRITEBACK +
        -- AMO_COMPUTE), and lock drops after the write completes
        -- (AMO_COMPLETE). Lost updates here = broken locking.
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

        finished <= '1';
        wait;
    end process;
end architecture;


-- ---------------------------------------------------------------------------
-- Testbench top
-- ---------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity mp_arbiter_tb is
end entity;

architecture sim of mp_arbiter_tb is

    constant N   : natural := 4;
    constant AW  : natural := 12;
    constant DW  : natural := 32;
    constant NTX : natural := 4;
    constant CLK_PERIOD : time := 10 ns;

    signal clk        : std_logic := '0';
    signal resetn     : std_logic := '0';
    signal stop_clock : boolean   := false;

    -- master <-> arbiter (per-master arrays, one driver each -> no bus conflict)
    type slv12_arr is array(0 to N-1) of std_logic_vector(AW-1 downto 0);
    type slv32_arr is array(0 to N-1) of std_logic_vector(DW-1 downto 0);
    type slv4_arr  is array(0 to N-1) of std_logic_vector(3 downto 0);
    signal m_req, m_gnt, m_done : std_logic_vector(N-1 downto 0);
    signal m_lock  : std_logic_vector(N-1 downto 0);   -- M8 grant-lock
    signal m_we    : slv4_arr;
    signal m_addr  : slv12_arr;
    signal m_wdata : slv32_arr;
    signal m_finished, m_err : std_logic_vector(N-1 downto 0) := (others => '0');

    -- flattened buses to the arbiter
    signal f_we    : std_logic_vector(N*4-1 downto 0);
    signal f_addr  : std_logic_vector(N*AW-1 downto 0);
    signal f_wdata : std_logic_vector(N*DW-1 downto 0);
    signal a_rdata : std_logic_vector(DW-1 downto 0);

    -- arbiter <-> shared slave
    signal s_en    : std_logic;
    signal s_we    : std_logic_vector(3 downto 0);
    signal s_addr  : std_logic_vector(AW-1 downto 0);
    signal s_wdata : std_logic_vector(DW-1 downto 0);
    signal s_rdata : std_logic_vector(DW-1 downto 0);

    signal mutex_err : std_logic := '0';
    signal cs_err    : std_logic := '0';   -- M8: foreign txn inside a locked RMW pair
    constant N_RMW   : natural := 8;       -- locked RMW pairs per master
    constant CTR_ADDR_I : natural := 16#F00#;  -- the common counter word

    -- shared single-port RAM (1-cycle registered read latency, active-high en)
    type ram_t is array(0 to 2**AW-1) of std_logic_vector(DW-1 downto 0);
    signal shram : ram_t := (others => (others => '0'));

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
            s_en => s_en, s_we => s_we, s_addr => s_addr,
            s_wdata => s_wdata, s_rdata => s_rdata
        );

    -- shared single-port RAM slave (matches the arbiter's 1-cycle-latency model;
    -- per-byte-lane writes, M4a)
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

    -- M8 critical-section checker: from a lock-holder's READ done to its
    -- WRITE done, NO other master may complete a transaction. (m_we is held
    -- through the done cycle by the BFM, so it classifies the txn type.)
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
    begin
        wait until resetn = '1';
        -- wait for all masters to finish, with a starvation/deadlock watchdog
        for t in 0 to 5000 loop
            wait until rising_edge(clk);
            exit when m_finished = (m_finished'range => '1');
        end loop;

        if m_finished /= (m_finished'range => '1') then
            report "WATCHDOG: not all masters finished (possible starvation/deadlock)"
                severity failure;
        end if;

        wait for 5*CLK_PERIOD;

        -- M8: the grant-locked RMW pass must have lost NO updates — the
        -- common counter is exactly N*N_RMW or some pair was interleaved.
        if shram(CTR_ADDR_I) /= conv_std_logic_vector(N*N_RMW, 32) then
            report "GRANT-LOCK COUNTER MISMATCH: expected " &
                   integer'image(N*N_RMW) & " got " &
                   integer'image(conv_integer(shram(CTR_ADDR_I)(30 downto 0)))
                severity failure;
        end if;

        if (m_err = (m_err'range => '0')) and (mutex_err = '0')
           and (cs_err = '0') then
            report "ALL CHECKS PASSED" severity note;
        else
            report "CHECKS FAILED (m_err, mutex_err or cs_err set)" severity failure;
        end if;

        stop_clock <= true;
        wait;
    end process;

end architecture;
