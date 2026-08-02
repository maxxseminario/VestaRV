-- =====================================================================
-- verification/formal/fabric_formal_tb.vhd   (R-S4-3 items 3 and 5)
-- Tracked directed bench for the two contracts the mutation campaign
-- found checked by NOTHING:
--   * mutex_bank claim atomicity / steal-proofness  (mutant F4)
--   * resv_unit's headline M4b rule: a FOREIGN WRITE between LR and SC
--     must break the reservation and fail the SC          (mutant F6)
-- arb_lat_tb drives both units but never produces these shapes -- its
-- masters never write to another master's reserved address, and its
-- mutex storm never re-claims a HELD slot from a different master.
-- pmp_unit_tb / arb_lat_tb are left untouched; this is additive.
-- =====================================================================
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;

entity fabric_formal_tb is end entity;

architecture tb of fabric_formal_tb is
    constant N  : natural := 4;
    constant AW : natural := 8;
    signal clk    : std_logic := '0';
    signal resetn : std_logic := '0';
    signal stopc  : boolean   := false;

    -- mutex_bank
    signal mx_en    : std_logic := '0';
    signal mx_we    : std_logic_vector(3 downto 0) := "0000";
    signal mx_addr  : std_logic_vector(3 downto 0) := (others => '0');
    signal mx_wdata : std_logic_vector(31 downto 0) := (others => '0');
    signal mx_master: std_logic_vector(1 downto 0) := "00";
    signal mx_rdata : std_logic_vector(31 downto 0);
    -- reference model: what rdata MUST be on the cycle after a claim
    signal mx_exp        : std_logic_vector(31 downto 0) := (others => '0');
    signal mx_exp_valid  : std_logic := '0';
    signal mx_claim_held : std_logic := '0';   -- this claim targets a HELD mutex

    -- resv_unit
    signal rv_lrsc   : std_logic_vector(N*2-1 downto 0) := (others => '0');
    signal rv_gnt    : std_logic_vector(N-1 downto 0)   := (others => '0');
    signal rv_sen    : std_logic := '0';
    signal rv_we     : std_logic_vector(3 downto 0) := "0000";
    signal rv_addr   : std_logic_vector(AW-1 downto 0) := (others => '0');
    signal rv_weg    : std_logic_vector(3 downto 0);
    signal rv_scfail : std_logic_vector(N-1 downto 0);
    signal rv_valid  : std_logic_vector(N-1 downto 0);
    signal foreign_write_done : std_logic := '0';  -- a foreign write hit m0's addr

    -- ---- mp_arbiter, for the M8 grant-locking window (R-S4-3 item 4) ----
    -- Residency is NOT inferable from a_lock at the ports: a master may
    -- assert lock long before it is granted, and the arbiter pins only on
    -- its DATA->LOCKED edge.  Both earlier property forms fired on clean
    -- RTL for exactly that reason.  So the BENCH declares the window --
    -- the same bench-controlled-flag pattern that fixed NAPOT/TOR.
    signal ab_req   : std_logic_vector(N-1 downto 0) := (others => '0');
    signal ab_lock  : std_logic_vector(N-1 downto 0) := (others => '0');
    signal ab_we    : std_logic_vector(N*4-1 downto 0) := (others => '0');
    signal ab_addr  : std_logic_vector(N*12-1 downto 0) := (others => '0');
    signal ab_wdata : std_logic_vector(N*32-1 downto 0) := (others => '0');
    signal ab_gnt, ab_done : std_logic_vector(N-1 downto 0);
    signal ab_rdata : std_logic_vector(31 downto 0);
    signal ab_sen   : std_logic;
    signal ab_smst  : std_logic_vector(1 downto 0);
    signal ab_swe   : std_logic_vector(3 downto 0);
    signal ab_saddr : std_logic_vector(11 downto 0);
    signal ab_swdat : std_logic_vector(31 downto 0);
    signal lock_window : std_logic := '0';   -- m0 holds the arbiter LOCKED
begin
    clk <= not clk after 5 ns when not stopc else '0';

    mtx : entity work.mutex_bank generic map (NMUTEX => 16, AW => 4, MW => 2)
        port map (clk, resetn, mx_en, mx_we, mx_addr, mx_wdata, mx_master, mx_rdata);

    arb : entity work.mp_arbiter generic map (N => N, ADDR_WIDTH => 12, DATA_WIDTH => 32, MW => 2)
        port map (clk, resetn, ab_req, ab_we, ab_addr, ab_wdata, ab_lock,
                  ab_gnt, ab_done, ab_rdata,
                  ab_sen, ab_smst, ab_swe, ab_saddr, ab_swdat, x"DEADBEEF");

    rsv : entity work.resv_unit generic map (N => N, ADDR_WIDTH => AW)
        port map (clk, resetn, rv_lrsc, rv_gnt, rv_sen, rv_we, rv_addr,
                  rv_weg, rv_scfail, rv_valid);

    stim : process
        procedure tick is begin wait until rising_edge(clk); end procedure;
    begin
        resetn <= '0'; tick; tick; resetn <= '1'; tick;

        -- ============ mutex_bank: claim atomicity + steal-proof ============
        -- 1. master 1 claims a FREE mutex 0 -> rdata must be the OLD value (free = 0)
        mx_addr <= "0000"; mx_master <= "01"; mx_we <= "0000"; mx_en <= '1';
        mx_exp <= (others => '0'); mx_exp_valid <= '1'; mx_claim_held <= '0';
        tick; mx_en <= '0'; tick; mx_exp_valid <= '0'; tick;

        -- 2. master 2 claims the SAME, now-HELD mutex -> must return the HOLDER
        --    (master 1 -> id+1 = 2) and must NOT take ownership.  This is the
        --    steal-proof shape: F4 deletes the owner=FREE guard.
        mx_master <= "10"; mx_we <= "0000"; mx_en <= '1';
        mx_exp <= x"00000002"; mx_exp_valid <= '1'; mx_claim_held <= '1';
        tick; mx_en <= '0'; tick; mx_exp_valid <= '0'; mx_claim_held <= '0'; tick;

        -- 3. master 2 claims AGAIN -- still master 1's.  A stolen mutex would
        --    now read back as master 2's (3), so this re-read is the witness
        --    that ownership did not move.
        mx_master <= "10"; mx_we <= "0000"; mx_en <= '1';
        mx_exp <= x"00000002"; mx_exp_valid <= '1'; mx_claim_held <= '1';
        tick; mx_en <= '0'; tick; mx_exp_valid <= '0'; mx_claim_held <= '0'; tick;

        -- 4. owner releases (write 0), then a claim must see FREE again
        mx_master <= "01"; mx_we <= "1111"; mx_wdata <= (others => '0'); mx_en <= '1';
        tick; mx_en <= '0'; tick;
        mx_master <= "11"; mx_we <= "0000"; mx_en <= '1';
        mx_exp <= (others => '0'); mx_exp_valid <= '1';
        tick; mx_en <= '0'; tick; mx_exp_valid <= '0'; tick;

        -- ============ resv_unit: THE M4b FOREIGN-WRITE RULE ============
        -- master 0 takes a reservation at address 0x20
        rv_addr <= x"20"; rv_gnt <= "0001"; rv_lrsc <= "00000001";  -- m0 = LR
        rv_sen <= '1'; rv_we <= "0000"; tick;
        rv_sen <= '0'; rv_lrsc <= (others => '0'); rv_gnt <= "0000"; tick;

        -- master 1 WRITES the same address.  M4b: this must break m0's
        -- reservation.  arb_lat_tb never produces this shape.
        rv_addr <= x"20"; rv_gnt <= "0010"; rv_lrsc <= (others => '0');
        rv_sen <= '1'; rv_we <= "1111"; tick;
        foreign_write_done <= '1';
        rv_sen <= '0'; rv_we <= "0000"; rv_gnt <= "0000"; tick; tick;

        -- master 0 now attempts its SC at the same address -> MUST FAIL
        rv_addr <= x"20"; rv_gnt <= "0001"; rv_lrsc <= "00000010";  -- m0 = SC
        rv_sen <= '1'; rv_we <= "1111"; tick;
        rv_sen <= '0'; rv_we <= "0000"; rv_gnt <= "0000"; rv_lrsc <= (others=>'0');
        tick; tick;

        -- ============ mp_arbiter: M8 GRANT-LOCKED RMW WINDOW ============
        -- Masters 1..3 are driven by the bfm_other processes below and are
        -- requesting throughout, so the window is genuinely CONTENDED (see
        -- witness W_CONTENDED); this process drives master 0 ONLY.
        -- The full handshake is mandatory here: a master's req must be
        -- OBSERVED LOW before the arbiter's wait-for-release mask will honor
        -- it again -- including for the follow-up write out of LOCKED.
        for k in 0 to 9 loop tick; end loop;

        -- master 0's RMW, first half: a READ (we slice "0000") with lock high.
        -- This is the transaction on whose completion the arbiter enters
        -- LOCKED; from here until master 0's write completes, no other master
        -- may be granted.
        ab_lock(0) <= '1'; ab_we(3 downto 0) <= "0000"; ab_req(0) <= '1';
        wait until rising_edge(clk) and ab_done(0) = '1';

        lock_window <= '1';            -- the arbiter is now in LOCKED
        ab_req(0) <= '0'; tick;        -- observed-low release window
        ab_we(3 downto 0) <= "1111"; ab_req(0) <= '1';   -- the RMW's WRITE half
        wait until rising_edge(clk) and ab_done(0) = '1';

        lock_window <= '0'; ab_lock(0) <= '0'; ab_req(0) <= '0';
        for k in 0 to 9 loop tick; end loop;

        report "fabric_formal_tb: stimulus complete" severity note;
        stopc <= true; wait;
    end process;

    -- Masters 1..3: full-handshake BFMs that request CONTINUOUSLY (dropping
    -- req for one cycle after each done, per the arbiter's ghost-txn rule).
    -- They exist so master 0's locked window has real contenders in it --
    -- without them P_LOCK_ATOMIC would hold vacuously.
    g_bfm_other : for i in 1 to N-1 generate
        bfm_other : process
        begin
            wait until resetn = '1';
            loop
                ab_req(i) <= '1';
                wait until rising_edge(clk) and ab_done(i) = '1';
                ab_req(i) <= '0';
                wait until rising_edge(clk);
            end loop;
        end process;
    end generate;
end architecture;
