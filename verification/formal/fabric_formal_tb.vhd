-- =====================================================================
-- Directed bench for three fabric contracts: mutex_bank claim atomicity,
-- resv_unit foreign-write reservation break, arbiter locked RMW window.
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

    -- mp_arbiter grant-locking window.
    -- Lock residency is not inferable from a_lock at the ports: a master may assert lock long before it is granted, so the bench declares the window with a flag.
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
        -- 1. master 1 claims a FREE mutex 0: rdata must be the OLD value (free = 0).
        mx_addr <= "0000"; mx_master <= "01"; mx_we <= "0000"; mx_en <= '1';
        mx_exp <= (others => '0'); mx_exp_valid <= '1'; mx_claim_held <= '0';
        tick; mx_en <= '0'; tick; mx_exp_valid <= '0'; tick;

        -- 2. master 2 claims the SAME, now-HELD mutex: must return the holder as id+1 = 2.
        -- Ownership must NOT move; this is the steal-proof shape.
        mx_master <= "10"; mx_we <= "0000"; mx_en <= '1';
        mx_exp <= x"00000002"; mx_exp_valid <= '1'; mx_claim_held <= '1';
        tick; mx_en <= '0'; tick; mx_exp_valid <= '0'; mx_claim_held <= '0'; tick;

        -- 3. master 2 claims again: still master 1's, since a stolen mutex would read back as 3.
        mx_master <= "10"; mx_we <= "0000"; mx_en <= '1';
        mx_exp <= x"00000002"; mx_exp_valid <= '1'; mx_claim_held <= '1';
        tick; mx_en <= '0'; tick; mx_exp_valid <= '0'; mx_claim_held <= '0'; tick;

        -- 4. owner releases (write 0), then a claim must see FREE again
        mx_master <= "01"; mx_we <= "1111"; mx_wdata <= (others => '0'); mx_en <= '1';
        tick; mx_en <= '0'; tick;
        mx_master <= "11"; mx_we <= "0000"; mx_en <= '1';
        mx_exp <= (others => '0'); mx_exp_valid <= '1';
        tick; mx_en <= '0'; tick; mx_exp_valid <= '0'; tick;

        -- ============ resv_unit: the foreign-write rule ============
        -- master 0 takes a reservation at address 0x20.
        rv_addr <= x"20"; rv_gnt <= "0001"; rv_lrsc <= "00000001";  -- m0 = LR
        rv_sen <= '1'; rv_we <= "0000"; tick;
        rv_sen <= '0'; rv_lrsc <= (others => '0'); rv_gnt <= "0000"; tick;

        -- master 1 WRITES the same address: this must break m0's reservation.
        rv_addr <= x"20"; rv_gnt <= "0010"; rv_lrsc <= (others => '0');
        rv_sen <= '1'; rv_we <= "1111"; tick;
        foreign_write_done <= '1';
        rv_sen <= '0'; rv_we <= "0000"; rv_gnt <= "0000"; tick; tick;

        -- master 0 now attempts its SC at the same address: it MUST FAIL.
        rv_addr <= x"20"; rv_gnt <= "0001"; rv_lrsc <= "00000010";  -- m0 = SC
        rv_sen <= '1'; rv_we <= "1111"; tick;
        rv_sen <= '0'; rv_we <= "0000"; rv_gnt <= "0000"; rv_lrsc <= (others=>'0');
        tick; tick;

        -- ============ mp_arbiter: grant-locked RMW window ============
        -- Masters 1..3 request throughout via the BFMs below, so the window is genuinely contended; this process drives master 0 only.
        -- The full handshake is mandatory: a master's req must be observed low before the wait-for-release mask honors it again, the write out of LOCKED included.
        for k in 0 to 9 loop tick; end loop;

        -- master 0's RMW, first half: a READ (we slice "0000") with lock high.
        -- The arbiter enters LOCKED on its completion; no other master may be granted until master 0's write completes.
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

    -- Masters 1..3: full-handshake BFMs that request continuously, dropping req for one cycle after each done per the arbiter's ghost-txn rule.
    -- They give master 0's locked window real contenders; without them the lock-atomicity check holds vacuously.
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
