-- Unit proof for the power controller: the per-tile MTCMOS sequencers plus the PGOOD/field boot gate and strap self-arm.
-- It drives the arbiter slave port directly: en is a one-cycle strobe, we is the active-high lane vector, addr is a word offset, and the registered read is valid the cycle after the strobe.
-- It also drives the three async pad inputs (pgood_pad, strap_pad, field_detect), which are 2-FF synchronized inside the DUT.
-- Self-checking: every check reports and keeps going, and the bench ends with ALL TESTS PASSED or TB FAILED.
-- Runs standalone against pwr_ctrl.vhd through xcelium/mp_test/run_pwr_ctrl.sh, with small delay generics (T_SEQ=2, T_RAIL=8, STRAP_SETTLE=8) to keep the sim short.

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

    signal pgood_pad    : std_logic := '1';   -- default tie for the unused-feature config
    signal strap_pad    : std_logic := '0';
    signal field_detect : std_logic := '0';
    signal pgood_rstn   : std_logic;

    -- Event-fabric task-wake tap: a one-mclk pulse, inert by default like the DUT port default.
    signal task_wake : std_logic := '0';

    signal done  : boolean := false;   -- stops the clock once the verdict is printed
    signal fails : integer := 0;       -- failed-check tally driving the verdict

    -- Register word offsets, mirroring the DUT map.
    constant PWRCR    : natural := 0;
    constant PWRSR0   : natural := 1;
    constant PWRWAKE  : natural := 5;
    constant PWRSTS   : natural := 6;
    constant TASKWKM  : natural := 7;

    -- PWRWAKE bit masks (boot-gate arm and release-source enables).
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

    -- PWRSR per-tile state nibbles.
    constant N_ON  : std_logic_vector(3 downto 0) := x"0";
    constant N_OFF : std_logic_vector(3 downto 0) := x"3";

    -- Number of live PWRSR words: 8 tile nibbles per 32-bit word.
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
            pgood_rstn   => pgood_rstn,
            task_wake    => task_wake
        );

    stim: process

        procedure tick(n : natural) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        -- One-cycle strobe; the registered read is sampled the cycle after it.
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

        -- One-cycle write strobe with an explicit byte-lane mask.
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

        -- One-mclk task_wake pulse, using the bus_write idiom: asserted after one clock edge, sampled by the DUT at the next, then deasserted.
        procedure pulse_task_wake is
        begin
            wait until rising_edge(clk);
            task_wake <= '1';
            wait until rising_edge(clk);
            task_wake <= '0';
            wait until rising_edge(clk);
        end procedure;

        -- Record a failed expectation and keep going, so one run reports every defect.
        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                fails <= fails + 1;
                report "CHECK FAILED: " & msg severity error;
                wait for 0 ns;  -- let the fails increment land
            end if;
        end procedure;

        -- Pulse reset; the caller must already have set the pad inputs.
        -- It waits past the strap-settle window, so the boot gate has resolved by the time it returns.
        procedure do_reset is
        begin
            resetn <= '0';
            en <= '0'; we <= "0000";
            tick(4);
            resetn <= '1';
            tick(STRAP_SETTLE + 6);
        end procedure;

        -- Poll PWRSR until that hart's nibble reaches the target, giving up after a bounded number of reads.
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
        variable ok2 : boolean;
        variable wv  : std_logic_vector(31 downto 0);
        variable exp : std_logic_vector(31 downto 0);
    begin
        -- Initial pad ties for case 1, the unused-feature config.
        pgood_pad    <= '1';
        strap_pad    <= '0';
        field_detect <= '0';
        do_reset;

        -- === 1. backward-compat: reset is a no-op, PWRCR gates and wakes ======
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

        -- Gate tile 1 and check the OFF-state controls.
        bus_write(PWRCR, x"00000002", "1111");
        poll_nibble(1, N_OFF, ok);
        check(ok, "1: tile 1 did not reach OFF");
        check(pd_iso_en(1) = '1', "1: pd_iso_en(1) not asserted in OFF");
        check(pd_sleep(1)  = '1', "1: pd_sleep(1) not asserted in OFF");
        check(pd_rstn(1)   = '0', "1: pd_rstn(1) not held in OFF");
        -- Wake tile 1 again and check every control is released.
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
        -- One-shot: dropping the pad must not clear the latched strap.
        strap_pad <= '0';
        tick(6);
        bus_read(PWRSTS, rd);
        check(rd(B_STRAP)     = '1', "2: STRAP cleared on pad drop (not one-shot)");
        check(rd(B_BOOT_HOLD) = '1', "2: BOOT_HOLD released without PGOOD");

        -- === 3. self-arm release + brownout re-hold ==========================
        pgood_pad <= '1';          -- PGOOD arrives, so the self-armed gate should release
        tick(6);
        bus_read(PWRSTS, rd);
        check(rd(B_BOOT_HOLD) = '0', "3: BOOT_HOLD not released on PGOOD");
        check(pgood_rstn = '1', "3: pgood_rstn not released on PGOOD");
        pgood_pad <= '0';          -- brownout: the strap ORs REHOLD, so the gate must come back
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
        bus_write(PWRWAKE, GATE_EN or RLS_PGOOD, "1111");   -- arm the gate and wait on PGOOD
        tick(2);
        bus_read(PWRSTS, rd);
        check(rd(B_BOOT_HOLD)   = '1', "4: BOOT_HOLD not set on SW arm");
        check(rd(B_RLS_LATCHED) = '0', "4: RLS_LATCHED set before release");
        pgood_pad <= '1';
        tick(6);
        bus_read(PWRSTS, rd);
        check(rd(B_BOOT_HOLD)   = '0', "4: BOOT_HOLD not released on PGOOD");
        check(rd(B_RLS_LATCHED) = '1', "4: RLS_LATCHED not set after release");
        pgood_pad <= '0';          -- drop PGOOD; with REHOLD=0 the release is a one-shot and stays released
        tick(6);
        bus_read(PWRSTS, rd);
        check(rd(B_BOOT_HOLD)   = '0', "4: one-shot re-held on PGOOD drop");
        check(rd(B_RLS_LATCHED) = '1', "4: RLS_LATCHED lost after drop");

        -- === 5. negctrl: disabled source does not release ====================
        strap_pad    <= '0';
        pgood_pad    <= '0';
        field_detect <= '0';
        do_reset;
        bus_write(PWRWAKE, GATE_EN or RLS_PGOOD, "1111");   -- RLS_FIELD deliberately NOT set
        field_detect <= '1';                                -- assert the disabled source
        tick(10);
        bus_read(PWRSTS, rd);
        check(rd(B_FIELD_LIVE) = '1', "5: FIELD_LIVE not synced");
        check(rd(B_BOOT_HOLD)  = '1', "5: disabled field released the gate");
        -- Now enable RLS_FIELD: the same held field level must release the gate.
        bus_write(PWRWAKE, GATE_EN or RLS_PGOOD or RLS_FIELD, "1111");
        tick(4);
        bus_read(PWRSTS, rd);
        check(rd(B_BOOT_HOLD) = '0', "5: enabled field did not release");

        -- === 6. negctrl: armed gate with no release source holds =============
        strap_pad    <= '0';
        pgood_pad    <= '0';
        field_detect <= '0';
        do_reset;
        bus_write(PWRWAKE, GATE_EN, "1111");                -- arm with no release source enabled
        pgood_pad    <= '1';                                -- drive both live inputs high
        field_detect <= '1';
        tick(18);
        bus_read(PWRSTS, rd);
        check(rd(B_PGOOD_LIVE) = '1', "6: PGOOD_LIVE not high");
        check(rd(B_FIELD_LIVE) = '1', "6: FIELD_LIVE not high");
        check(rd(B_BOOT_HOLD)  = '1', "6: gate released with no enabled source");
        check(pgood_rstn = '0', "6: pgood_rstn released with no enabled source");
        bus_write(PWRWAKE, GATE_EN or SW_RELEASE, "1111");  -- forced proceed, the software override
        tick(4);
        bus_read(PWRSTS, rd);
        check(rd(B_BOOT_HOLD) = '0', "6: SW_RELEASE did not release");
        check(pgood_rstn = '1', "6: pgood_rstn not released by SW_RELEASE");

        -- === 7. PWRWAKE readback + reserved words ============================
        strap_pad <= '0';
        pgood_pad <= '1';
        do_reset;
        bus_write(PWRWAKE, x"0000001F", "1111");            -- all five live bits
        bus_read(PWRWAKE, rd);
        check(rd = x"0000001F", "7: PWRWAKE 5-bit readback wrong");
        bus_write(PWRWAKE, x"FFFFFFFF", "1111");            -- upper bits must not stick
        bus_read(PWRWAKE, rd);
        check(rd = x"0000001F", "7: PWRWAKE stored bits above 4:0");
        bus_write(PWRWAKE, x"00000000", "1111");            -- disarm again to leave a clean state
        -- Reserved words 7 to 15 must read 0.
        bus_read(7, rd);
        check(rd = x"00000000", "7: word 7 not 0");
        bus_read(10, rd);
        check(rd = x"00000000", "7: word 10 not 0");
        bus_read(15, rd);
        check(rd = x"00000000", "7: word 15 not 0");
        -- A PWRSR word above the live array reads 0; the guard keeps the probe below PWRWAKE.
        if NSRW + 1 < PWRWAKE then
            bus_read(NSRW + 1, rd);
            check(rd = x"00000000", "7: PWRSR word above NSRW not 0");
        end if;

        -- === 8. boot-gate / tile-FSM independence ============================
        strap_pad    <= '0';
        pgood_pad    <= '1';
        field_detect <= '0';
        do_reset;
        -- Arm AND immediately release through SW_RELEASE, a one-shot.
        bus_write(PWRWAKE, GATE_EN or SW_RELEASE, "1111");
        tick(4);
        bus_read(PWRSTS, rd);
        check(rd(B_BOOT_HOLD)   = '0', "8: boot gate not released");
        check(rd(B_RLS_LATCHED) = '1', "8: boot gate release not latched");
        -- With the boot gate settled, the tile sequencer must still work.
        bus_write(PWRCR, x"00000002", "1111");
        poll_nibble(1, N_OFF, ok);
        check(ok, "8: tile 1 did not gate while boot gate released");
        check(pd_rstn(1) = '0', "8: pd_rstn(1) not held in OFF (indep)");
        bus_write(PWRCR, x"00000000", "1111");
        poll_nibble(1, N_ON, ok);
        check(ok, "8: tile 1 did not wake while boot gate released");
        check(pd_rstn(1) = '1', "8: pd_rstn(1) not released after wake (indep)");
        -- The boot gate must be untouched by that tile activity.
        bus_read(PWRSTS, rd);
        check(rd(B_BOOT_HOLD) = '0', "8: tile activity disturbed the boot gate");

        -- === 9. task-wake tap ================================================
        strap_pad    <= '0';
        pgood_pad    <= '1';
        field_detect <= '0';
        task_wake    <= '0';
        do_reset;

        -- --- 9a. W_TASKWKM RW readback: reset 0, walking-1, with bit 0 and out-of-range bits read-only 0.
        bus_read(TASKWKM, rd);
        check(rd = x"00000000", "9a: TASKWKM not 0 at reset");
        for h in 1 to NHARTS-1 loop
            wv := (others => '0');
            wv(h) := '1';
            bus_write(TASKWKM, wv, "1111");
            bus_read(TASKWKM, rd);
            check(rd = wv, "9a: TASKWKM walking-1 bit " & integer'image(h) & " readback wrong");
        end loop;
        -- Bit 0 is hart 0, always-on, so it has no storage and reads back 0.
        bus_write(TASKWKM, x"00000001", "1111");
        bus_read(TASKWKM, rd);
        check(rd = x"00000000", "9a: TASKWKM bit 0 not RO 0");
        -- The out-of-range bit just above NHARTS-1 has no storage either, so it reads back 0.
        wv := (others => '0');
        wv(NHARTS) := '1';
        bus_write(TASKWKM, wv, "1111");
        bus_read(TASKWKM, rd);
        check(rd = x"00000000", "9a: TASKWKM out-of-range bit not RO 0");
        -- All-ones write: only bits NHARTS-1 down to 1 stick.
        bus_write(TASKWKM, x"FFFFFFFF", "1111");
        exp := (others => '0');
        exp(NHARTS-1 downto 1) := (others => '1');
        bus_read(TASKWKM, rd);
        check(rd = exp, "9a: TASKWKM all-ones write did not mask to NHARTS-1:1");
        bus_write(TASKWKM, x"00000000", "1111");   -- clean up

        -- --- 9b. Task-wake basics: gate tile 1, mask tile 1, and a pulse must wake it.
        bus_write(PWRCR, x"00000002", "1111");      -- gate tile 1
        poll_nibble(1, N_OFF, ok);
        check(ok, "9b: tile 1 did not reach OFF before task-wake");
        wv := (others => '0');
        wv(1) := '1';
        bus_write(TASKWKM, wv, "1111");             -- the mask selects tile 1
        pulse_task_wake;
        bus_read(PWRCR, rd);
        check(rd(1) = '0', "9b: task_wake did not clear gate_req(1)");
        poll_nibble(1, N_ON, ok);
        check(ok, "9b: tile 1 did not sequence rail-up after task_wake");
        check(pd_iso_en(1) = '0', "9b: pd_iso_en(1) not released after task-wake");
        check(pd_sleep(1)  = '0', "9b: pd_sleep(1) not released after task-wake");
        check(pd_rstn(1)   = '1', "9b: pd_rstn(1) not released after task-wake");
        bus_write(TASKWKM, x"00000000", "1111");    -- clean up

        -- --- 9c. With mask=0 a pulse must change nothing.
        bus_write(PWRCR, x"00000002", "1111");      -- gate tile 1 again
        poll_nibble(1, N_OFF, ok);
        check(ok, "9c: tile 1 did not reach OFF before mask=0 pulse");
        pulse_task_wake;                            -- task_wkm is still all zeros
        tick(4);
        bus_read(PWRCR, rd);
        check(rd(1) = '1', "9c: mask=0 task_wake cleared gate_req(1)");
        bus_read(PWRSR0, sr);
        check(sr(4*1+3 downto 4*1) = N_OFF, "9c: mask=0 task_wake moved tile 1 out of OFF");
        -- Wake tile 1 the ordinary way again, ready for the next check.
        bus_write(PWRCR, x"00000000", "1111");
        poll_nibble(1, N_ON, ok);
        check(ok, "9c: tile 1 did not wake via PWRCR after mask=0 pulse check");

        -- --- 9d. Selectivity: two tiles gated, and the mask selects only tile 1.
        bus_write(PWRCR, x"00000006", "1111");      -- gate tiles 1 and 2
        poll_nibble(1, N_OFF, ok);
        poll_nibble(2, N_OFF, ok2);
        check(ok  and ok2, "9d: tiles 1/2 did not both reach OFF");
        wv := (others => '0');
        wv(1) := '1';                                -- mask covers tile 1 only
        bus_write(TASKWKM, wv, "1111");
        pulse_task_wake;
        bus_read(PWRCR, rd);
        check(rd(1) = '0', "9d: masked tile 1 did not clear");
        check(rd(2) = '1', "9d: unmasked tile 2 was disturbed");
        poll_nibble(1, N_ON, ok);
        check(ok, "9d: masked tile 1 did not wake");
        bus_read(PWRSR0, sr);
        check(sr(4*2+3 downto 4*2) = N_OFF, "9d: unmasked tile 2 left OFF");
        check(pd_rstn(2) = '0', "9d: unmasked tile 2 pd_rstn disturbed");
        bus_write(TASKWKM, x"00000000", "1111");
        bus_write(PWRCR, x"00000000", "1111");       -- cleanup: wake tile 2 as well
        poll_nibble(2, N_ON, ok2);
        check(ok2, "9d: tile 2 did not wake on cleanup");

        -- --- 9e. Merge and precedence when a PWRCR write and a task_wake pulse land in the same cycle, with both tiles ON and task_wkm selecting tile 1.
        -- The CPU asks to gate tiles 1 and 2: the masked bit (tile 1) must end 0 because the task wins, while the unmasked bit (tile 2) takes the CPU value of 1.
        wv := (others => '0');
        wv(1) := '1';
        bus_write(TASKWKM, wv, "1111");
        wait until rising_edge(clk);
        en    <= '1';
        we    <= "1111";
        addr  <= conv_std_logic_vector(PWRCR, 4);
        wdata <= x"00000006";                        -- the CPU asks to gate tiles 1 and 2
        task_wake <= '1';                             -- coincident task pulse
        wait until rising_edge(clk);                  -- the DUT samples both on this edge
        en        <= '0';
        we        <= "0000";
        task_wake <= '0';
        wait until rising_edge(clk);
        bus_read(PWRCR, rd);
        check(rd(1) = '0', "9e: merge did not let task win the masked bit");
        check(rd(2) = '1', "9e: merge did not preserve the CPU value on the unmasked bit");
        poll_nibble(2, N_OFF, ok);
        check(ok, "9e: unmasked tile 2 did not gate per the CPU write");
        bus_read(PWRSR0, sr);
        check(sr(4*1+3 downto 4*1) = N_ON, "9e: masked tile 1 was gated despite task_wake clearing its bit");
        bus_write(TASKWKM, x"00000000", "1111");
        bus_write(PWRCR, x"00000000", "1111");        -- cleanup: wake tile 2
        poll_nibble(2, N_ON, ok2);
        check(ok2, "9e: tile 2 did not wake on cleanup");

        -- --- 9f. Boot-gate isolation: task_wake pulses in the normal-on state must not perturb pgood_rstn or PWRSTS, i.e. rls_latch and boot_hold.
        strap_pad    <= '0';
        pgood_pad    <= '1';
        field_detect <= '0';
        do_reset;                                     -- normal-on state, with the gate released
        bus_read(PWRSTS, rd);
        check(pgood_rstn      = '1', "9f: pgood_rstn not released before task_wake probing");
        check(rd(B_BOOT_HOLD) = '0', "9f: BOOT_HOLD set before task_wake probing");
        wv := (others => '0');
        wv(NHARTS-1 downto 1) := (others => '1');      -- mask covers every tile
        bus_write(TASKWKM, wv, "1111");
        pulse_task_wake;
        pulse_task_wake;
        pulse_task_wake;
        tick(4);
        check(pgood_rstn = '1', "9f: pgood_rstn disturbed by task_wake pulses");
        bus_read(PWRSTS, rd);
        check(rd(B_BOOT_HOLD)   = '0', "9f: BOOT_HOLD disturbed by task_wake pulses");
        check(rd(B_RLS_LATCHED) = '0', "9f: RLS_LATCHED disturbed by task_wake pulses");
        bus_write(TASKWKM, x"00000000", "1111");       -- clean up

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
