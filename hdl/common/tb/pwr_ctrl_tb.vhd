-- =============================================================================
-- pwr_ctrl_tb.vhd  (DP-S3)
-- =============================================================================
-- Unit proof for the reworked power controller: the M17 per-tile MTCMOS
-- sequencers PLUS the DP-S3 PGOOD/field boot gate + strap self-arm. Drives the
-- arbiter slave port directly (en = one-cycle strobe, we = active-high lanes,
-- addr = word offset, 1-cycle registered read valid the cycle after the
-- strobe) and drives the three async pad inputs (pgood_pad/strap_pad/
-- field_detect) which are 2-FF synchronized inside the DUT.
--
-- Checks (self-checking; prints ALL TESTS PASSED / TB FAILED):
--   1. M17 backward-compat: reset NO-OP + tile-1 gate->OFF->wake->ON sequence
--      with the pd_* controls asserted/released in order; PWRSTS/PWRWAKE sane.
--   2. strap sample, latch-once: harvested board self-arms and holds on !PGOOD;
--      strap is a one-shot (mid-run pad change ignored).
--   3. self-arm release + brownout re-hold (strap ORs REHOLD).
--   4. software-arm path (no strap): arm+RLS_PGOOD holds, PGOOD releases,
--      one-shot latch survives the PGOOD drop (RLS_LATCHED).
--   5. negctrl: a DISABLED wake source (field, RLS_FIELD off) does not release;
--      enabling RLS_FIELD then releases on the same field level.
--   6. negctrl: an armed gate with NO release source holds through live PGOOD
--      AND field; SW_RELEASE releases (pgood_rstn is load-bearing).
--   7. PWRWAKE readback (only bits 4:0 stick) + reserved words 7..15 read 0 +
--      PWRSR word above NSRW reads 0.
--   8. independence: with the boot gate armed-and-released, the tile MTCMOS
--      sequencer still gates/wakes tile 1 (the two FSMs are independent).
--
-- Run: xcelium/mp_test/run_pwr_ctrl.sh (compiles this against
-- hdl/common/pwr_ctrl.vhd only — no other DUT dependencies). Small delay
-- generics (T_SEQ=2, T_RAIL=8, STRAP_SETTLE=8) keep the sim short.
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity pwr_ctrl_tb is
    generic (
        NHARTS       : natural := 4;
        T_SEQ        : natural := 2;
        T_RAIL       : natural := 8;
        STRAP_SETTLE : natural := 8
    );
end entity;

architecture tb of pwr_ctrl_tb is

    constant CLK_PERIOD : time := 10 ns;

    signal clk    : std_logic := '0';
    signal resetn : std_logic := '0';

    signal en    : std_logic := '0';
    signal we    : std_logic_vector(3 downto 0) := (others => '0');
    signal addr  : std_logic_vector(3 downto 0) := (others => '0');
    signal wdata : std_logic_vector(31 downto 0) := (others => '0');
    signal rdata : std_logic_vector(31 downto 0);

    signal pd_iso_en : std_logic_vector(NHARTS-1 downto 1);
    signal pd_sleep  : std_logic_vector(NHARTS-1 downto 1);
    signal pd_rstn   : std_logic_vector(NHARTS-1 downto 1);

    signal pgood_pad    : std_logic := '1';   -- unused-tie default
    signal strap_pad    : std_logic := '0';
    signal field_detect : std_logic := '0';
    signal pgood_rstn   : std_logic;

    signal done  : boolean := false;
    signal fails : integer := 0;

    -- register word offsets (mirror the DUT map)
    constant PWRCR   : natural := 0;
    constant PWRSR0  : natural := 1;
    constant PWRWAKE : natural := 5;
    constant PWRSTS  : natural := 6;

    -- PWRWAKE bits
    constant GATE_EN    : std_logic_vector(31 downto 0) := x"00000001";
    constant RLS_PGOOD  : std_logic_vector(31 downto 0) := x"00000002";
    constant RLS_FIELD  : std_logic_vector(31 downto 0) := x"00000004";
    constant SW_RELEASE : std_logic_vector(31 downto 0) := x"00000008";
    constant REHOLD     : std_logic_vector(31 downto 0) := x"00000010";

    -- PWRSTS bit indices
    constant B_PGOOD_LIVE  : natural := 0;
    constant B_FIELD_LIVE  : natural := 1;
    constant B_STRAP       : natural := 2;
    constant B_STRAP_VALID : natural := 3;
    constant B_BOOT_HOLD   : natural := 4;
    constant B_RLS_LATCHED : natural := 5;

    -- PWRSR nibble values
    constant N_ON  : std_logic_vector(3 downto 0) := x"0";
    constant N_OFF : std_logic_vector(3 downto 0) := x"3";

    constant NSRW : natural := (NHARTS + 7) / 8;

begin

    clk <= not clk after CLK_PERIOD / 2 when not done else '0';

    dut: entity work.pwr_ctrl
        generic map (
            NHARTS       => NHARTS,
            T_SEQ        => T_SEQ,
            T_RAIL       => T_RAIL,
            STRAP_SETTLE => STRAP_SETTLE
        )
        port map (
            clk          => clk,
            resetn       => resetn,
            en           => en,
            we           => we,
            addr         => addr,
            wdata        => wdata,
            rdata        => rdata,
            pd_iso_en    => pd_iso_en,
            pd_sleep     => pd_sleep,
            pd_rstn      => pd_rstn,
            pgood_pad    => pgood_pad,
            strap_pad    => strap_pad,
            field_detect => field_detect,
            pgood_rstn   => pgood_rstn
        );

    stim: process

        procedure tick(n : natural) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        -- one-cycle strobe; registered read sampled the cycle after
        procedure bus_read(waddr : natural;
                           variable v : out std_logic_vector(31 downto 0)) is
        begin
            wait until rising_edge(clk);
            en   <= '1';
            we   <= "0000";
            addr <= conv_std_logic_vector(waddr, 4);
            wait until rising_edge(clk);
            en <= '0';
            wait until rising_edge(clk);
            v := rdata;
        end procedure;

        procedure bus_write(waddr : natural;
                            v : std_logic_vector(31 downto 0);
                            lanes : std_logic_vector(3 downto 0)) is
        begin
            wait until rising_edge(clk);
            en    <= '1';
            we    <= lanes;
            addr  <= conv_std_logic_vector(waddr, 4);
            wdata <= v;
            wait until rising_edge(clk);
            en <= '0';
            we <= "0000";
            wait until rising_edge(clk);
        end procedure;

        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                fails <= fails + 1;
                report "CHECK FAILED: " & msg severity error;
                wait for 0 ns;  -- let the fails increment land
            end if;
        end procedure;

        -- pulse reset; pad inputs must already be set by the caller. Waits
        -- past the strap-settle window so the boot gate has resolved on return.
        procedure do_reset is
        begin
            resetn <= '0';
            en <= '0'; we <= "0000";
            tick(4);
            resetn <= '1';
            tick(STRAP_SETTLE + 6);
        end procedure;

        -- poll PWRSR until hart's nibble hits target (or give up)
        procedure poll_nibble(hart : natural;
                              target : std_logic_vector(3 downto 0);
                              variable ok : out boolean) is
            variable rd    : std_logic_vector(31 downto 0);
            variable wword : natural;
            variable boff  : natural;
        begin
            wword := PWRSR0 + hart / 8;
            boff  := 4 * (hart mod 8);
            ok := false;
            for i in 0 to 60 loop
                bus_read(wword, rd);
                if rd(boff + 3 downto boff) = target then
                    ok := true;
                    exit;
                end if;
            end loop;
        end procedure;

        variable rd  : std_logic_vector(31 downto 0);
        variable sr  : std_logic_vector(31 downto 0);
        variable ok  : boolean;
    begin
        -- initial pad ties for case 1 (unused-feature config)
        pgood_pad    <= '1';
        strap_pad    <= '0';
        field_detect <= '0';
        do_reset;

        -- === 1. M17 backward-compat ==========================================
        check(pgood_rstn = '1', "1: pgood_rstn not released after reset");
        bus_read(PWRCR, rd);
        check(rd = x"00000000", "1: PWRCR not 0 at reset");
        bus_read(PWRWAKE, rd);
        check(rd = x"00000000", "1: PWRWAKE not 0 at reset");
        bus_read(PWRSTS, rd);
        check(rd(B_PGOOD_LIVE)  = '1', "1: PGOOD_LIVE not 1");
        check(rd(B_STRAP)       = '0', "1: STRAP set with strap_pad=0");
        check(rd(B_STRAP_VALID) = '1', "1: STRAP_VALID not set after settle");
        check(rd(B_BOOT_HOLD)   = '0', "1: BOOT_HOLD set with no arm");

        -- gate tile 1
        bus_write(PWRCR, x"00000002", "1111");
        poll_nibble(1, N_OFF, ok);
        check(ok, "1: tile 1 did not reach OFF");
        check(pd_iso_en(1) = '1', "1: pd_iso_en(1) not asserted in OFF");
        check(pd_sleep(1)  = '1', "1: pd_sleep(1) not asserted in OFF");
        check(pd_rstn(1)   = '0', "1: pd_rstn(1) not held in OFF");
        -- wake tile 1
        bus_write(PWRCR, x"00000000", "1111");
        poll_nibble(1, N_ON, ok);
        check(ok, "1: tile 1 did not wake to ON");
        check(pd_iso_en(1) = '0', "1: pd_iso_en(1) not released");
        check(pd_sleep(1)  = '0', "1: pd_sleep(1) not released");
        check(pd_rstn(1)   = '1', "1: pd_rstn(1) not released");

        -- === 2. strap sample, latch-once =====================================
        strap_pad    <= '1';
        pgood_pad    <= '0';
        field_detect <= '0';
        do_reset;
        bus_read(PWRSTS, rd);
        check(rd(B_STRAP)       = '1', "2: STRAP not latched from strap_pad=1");
        check(rd(B_STRAP_VALID) = '1', "2: STRAP_VALID not set");
        check(rd(B_BOOT_HOLD)   = '1', "2: BOOT_HOLD not set (self-arm)");
        check(pgood_rstn = '0', "2: pgood_rstn not held (self-arm on !PGOOD)");
        -- one-shot: dropping the pad must not clear the latched strap
        strap_pad <= '0';
        tick(6);
        bus_read(PWRSTS, rd);
        check(rd(B_STRAP)     = '1', "2: STRAP cleared on pad drop (not one-shot)");
        check(rd(B_BOOT_HOLD) = '1', "2: BOOT_HOLD released without PGOOD");

        -- === 3. self-arm release + brownout re-hold ==========================
        pgood_pad <= '1';          -- PGOOD arrives
        tick(6);
        bus_read(PWRSTS, rd);
        check(rd(B_BOOT_HOLD) = '0', "3: BOOT_HOLD not released on PGOOD");
        check(pgood_rstn = '1', "3: pgood_rstn not released on PGOOD");
        pgood_pad <= '0';          -- brownout
        tick(6);
        bus_read(PWRSTS, rd);
        check(rd(B_BOOT_HOLD) = '1', "3: BOOT_HOLD did not re-hold on brownout");
        check(pgood_rstn = '0', "3: pgood_rstn not re-held on brownout");
        pgood_pad <= '1';          -- recovery
        tick(6);
        bus_read(PWRSTS, rd);
        check(rd(B_BOOT_HOLD) = '0', "3: BOOT_HOLD not released on PGOOD return");

        -- === 4. software-arm path (no strap) =================================
        strap_pad    <= '0';
        pgood_pad    <= '0';
        field_detect <= '0';
        do_reset;
        bus_write(PWRWAKE, GATE_EN or RLS_PGOOD, "1111");   -- arm, wait on PGOOD
        tick(2);
        bus_read(PWRSTS, rd);
        check(rd(B_BOOT_HOLD)   = '1', "4: BOOT_HOLD not set on SW arm");
        check(rd(B_RLS_LATCHED) = '0', "4: RLS_LATCHED set before release");
        pgood_pad <= '1';
        tick(6);
        bus_read(PWRSTS, rd);
        check(rd(B_BOOT_HOLD)   = '0', "4: BOOT_HOLD not released on PGOOD");
        check(rd(B_RLS_LATCHED) = '1', "4: RLS_LATCHED not set after release");
        pgood_pad <= '0';          -- drop; REHOLD=0 -> one-shot, stays released
        tick(6);
        bus_read(PWRSTS, rd);
        check(rd(B_BOOT_HOLD)   = '0', "4: one-shot re-held on PGOOD drop");
        check(rd(B_RLS_LATCHED) = '1', "4: RLS_LATCHED lost after drop");

        -- === 5. negctrl: disabled source does not release ====================
        strap_pad    <= '0';
        pgood_pad    <= '0';
        field_detect <= '0';
        do_reset;
        bus_write(PWRWAKE, GATE_EN or RLS_PGOOD, "1111");   -- RLS_FIELD NOT set
        field_detect <= '1';                                -- assert the source
        tick(10);
        bus_read(PWRSTS, rd);
        check(rd(B_FIELD_LIVE) = '1', "5: FIELD_LIVE not synced");
        check(rd(B_BOOT_HOLD)  = '1', "5: disabled field released the gate");
        -- now enable RLS_FIELD: the same field level must release
        bus_write(PWRWAKE, GATE_EN or RLS_PGOOD or RLS_FIELD, "1111");
        tick(4);
        bus_read(PWRSTS, rd);
        check(rd(B_BOOT_HOLD) = '0', "5: enabled field did not release");

        -- === 6. negctrl: armed gate with no release source holds =============
        strap_pad    <= '0';
        pgood_pad    <= '0';
        field_detect <= '0';
        do_reset;
        bus_write(PWRWAKE, GATE_EN, "1111");                -- arm, no release src
        pgood_pad    <= '1';                                -- both live inputs high
        field_detect <= '1';
        tick(18);
        bus_read(PWRSTS, rd);
        check(rd(B_PGOOD_LIVE) = '1', "6: PGOOD_LIVE not high");
        check(rd(B_FIELD_LIVE) = '1', "6: FIELD_LIVE not high");
        check(rd(B_BOOT_HOLD)  = '1', "6: gate released with no enabled source");
        check(pgood_rstn = '0', "6: pgood_rstn released with no enabled source");
        bus_write(PWRWAKE, GATE_EN or SW_RELEASE, "1111");  -- forced proceed
        tick(4);
        bus_read(PWRSTS, rd);
        check(rd(B_BOOT_HOLD) = '0', "6: SW_RELEASE did not release");
        check(pgood_rstn = '1', "6: pgood_rstn not released by SW_RELEASE");

        -- === 7. PWRWAKE readback + reserved words ============================
        strap_pad <= '0';
        pgood_pad <= '1';
        do_reset;
        bus_write(PWRWAKE, x"0000001F", "1111");            -- all 5 live bits
        bus_read(PWRWAKE, rd);
        check(rd = x"0000001F", "7: PWRWAKE 5-bit readback wrong");
        bus_write(PWRWAKE, x"FFFFFFFF", "1111");            -- upper bits must not stick
        bus_read(PWRWAKE, rd);
        check(rd = x"0000001F", "7: PWRWAKE stored bits above 4:0");
        bus_write(PWRWAKE, x"00000000", "1111");            -- disarm for cleanliness
        -- reserved words 7..15 read 0
        bus_read(7, rd);
        check(rd = x"00000000", "7: word 7 not 0");
        bus_read(10, rd);
        check(rd = x"00000000", "7: word 10 not 0");
        bus_read(15, rd);
        check(rd = x"00000000", "7: word 15 not 0");
        -- PWRSR word above the live array reads 0 (guarded: keep below PWRWAKE)
        if NSRW + 1 < PWRWAKE then
            bus_read(NSRW + 1, rd);
            check(rd = x"00000000", "7: PWRSR word above NSRW not 0");
        end if;

        -- === 8. boot-gate / tile-FSM independence ============================
        strap_pad    <= '0';
        pgood_pad    <= '1';
        field_detect <= '0';
        do_reset;
        -- arm AND immediately release via SW_RELEASE (one-shot)
        bus_write(PWRWAKE, GATE_EN or SW_RELEASE, "1111");
        tick(4);
        bus_read(PWRSTS, rd);
        check(rd(B_BOOT_HOLD)   = '0', "8: boot gate not released");
        check(rd(B_RLS_LATCHED) = '1', "8: boot gate release not latched");
        -- with the boot gate settled, the tile sequencer must still work
        bus_write(PWRCR, x"00000002", "1111");
        poll_nibble(1, N_OFF, ok);
        check(ok, "8: tile 1 did not gate while boot gate released");
        check(pd_rstn(1) = '0', "8: pd_rstn(1) not held in OFF (indep)");
        bus_write(PWRCR, x"00000000", "1111");
        poll_nibble(1, N_ON, ok);
        check(ok, "8: tile 1 did not wake while boot gate released");
        check(pd_rstn(1) = '1', "8: pd_rstn(1) not released after wake (indep)");
        -- boot gate must be untouched by the tile activity
        bus_read(PWRSTS, rd);
        check(rd(B_BOOT_HOLD) = '0', "8: tile activity disturbed the boot gate");

        -- === verdict =========================================================
        tick(2);
        if fails = 0 then
            report "ALL TESTS PASSED" severity note;
        else
            report "TB FAILED: " & integer'image(fails) severity error;
        end if;
        done <= true;
        wait;
    end process;

end architecture;
