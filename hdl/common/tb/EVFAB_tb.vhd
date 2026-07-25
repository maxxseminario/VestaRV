-------------------------------------------------------------------------------
-- EVFAB_tb.vhd
-------------------------------------------------------------------------------
-- Standalone, self-checking testbench for the EVFAB0 event/trigger fabric
-- (hdl/common/periph/EVFAB.vhd, to be written against the FROZEN design
-- ~/vesta_docs/digperiphs/event_fabric_design.md, D1-D25 + the FABLE
-- ADJUDICATION rulings). The DUT is declared as a COMPONENT (not an entity
-- instantiation) so this bench compiles standalone with xmvhdl regardless of
-- whether EVFAB.vhd has landed yet; VHDL default binding resolves it once
-- EVFAB.vhd is analyzed into work. Mirrors TRNG_tb.vhd / OneWire_tb.vhd
-- structurally (periph_tb_pkg scoreboard + register-bus BFM, one clk family,
-- named GROUPS, mandatory G-NEG last).
--
-- Uses tb/periph_tb_pkg.vhd (scoreboard + register-bus BFM, shared) and
-- tb/evfab_bfm_pkg.vhd (slot/CR/SR/CAP/CHnCFG constants, evfab_mk_cfg,
-- evfab_settle, bounded polls, and the TB SHADOW MODEL -- see that package's
-- header for the checker-independence + call-timing contracts).
--
-- ONE clock family (design doc D1/D2): `clk` (bound to MCLK at integration)
-- hosts the whole fabric (front-end, crossbar, output register, stickies,
-- ACTION path); `ClkMem` is the gated bus clock, driven
-- `clk when pbus.en_mem='0' else '0'` exactly like every other bench in this
-- library -- the bench's stricter gated-ClkMem model is deliberate (design
-- doc's FABLE ADJUDICATION note: it is the harder case for G9's autonomy
-- leg, and integration's raw free-running ClkMem is a strict superset of
-- edges).
--
-- Generics bound at the DUT instantiation are the v1 defaults verbatim
-- (D6): EV_MODE_TGL=x"00000370" (EV4/5/6/8/9 = T), EV_MODE_LVL=x"00002000"
-- (EV13 = L), everything else P. evfab_bfm_pkg's EVFAB_MODE_TGL/LVL
-- constants are an INDEPENDENT copy of the same literals (checker
-- independence) -- if the generics here are ever changed, that package's
-- copies must change with them or the mode-dependent stimulus/latency
-- checks below silently stop matching the DUT.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.periph_tb_pkg.all;
use work.evfab_bfm_pkg.all;

entity EVFAB_tb is
end entity EVFAB_tb;

architecture sim of EVFAB_tb is

    constant PERIOD : time := 20 ns;   -- clk reference (D1: free-running mclk)

    -- FROZEN DUT entity (design doc D6), declared as a component so the
    -- bench compiles standalone before/regardless of EVFAB.vhd's analysis.
    component EVFAB is
        generic (
            N_CH        : natural := 8;
            N_EV        : natural := 16;
            N_TASK      : natural := 10;
            EV_GPIO_IDX : natural := 15;
            EV_MODE_TGL : std_logic_vector(31 downto 0) := X"00000370";
            EV_MODE_LVL : std_logic_vector(31 downto 0) := X"00002000";
            VER         : natural := 1
        );
        port (
            clk         : in  std_logic;
            resetn      : in  std_logic;
            irq_evfab   : out std_logic;

            ClkMem      : in  std_logic;
            EnMemPeriph : in  std_logic;
            WEn         : in  std_logic_vector(3 downto 0);
            MABPart     : in  std_logic_vector(7 downto 2);
            wdata       : in  std_logic_vector(31 downto 0);
            rdata_out   : out std_logic_vector(31 downto 0);

            ev_in       : in  std_logic_vector(N_EV-1 downto 0)   := (others => '0');
            gpio0_evin  : in  std_logic_vector(7 downto 0)        := (others => '0');

            task_busy   : in  std_logic_vector(N_TASK-1 downto 0) := (others => '0');
            task_pulse  : out std_logic_vector(N_TASK-1 downto 0)
        );
    end component;

    -- clocks / reset
    signal clk    : std_logic := '0';
    signal ClkMem : std_logic := '0';
    signal resetn : std_logic := '0';

    -- interrupt (vectorless v1, D20 -- constant '0')
    signal irq_evfab : std_logic;

    -- register bus (BFM record + observed rdata_out)
    signal pbus      : periph_bus_t := PERIPH_BUS_IDLE;
    signal rdata_out : std_logic_vector(31 downto 0);

    -- producer / consumer interconnect (D6)
    signal ev_in      : std_logic_vector(EVFAB_N_EV-1 downto 0)   := (others => '0');
    signal gpio0_evin  : std_logic_vector(7 downto 0)              := (others => '0');
    signal task_busy   : std_logic_vector(EVFAB_N_TASK-1 downto 0) := (others => '0');
    signal task_pulse  : std_logic_vector(EVFAB_N_TASK-1 downto 0);

    signal tb_done : boolean := false;

    shared variable sb : scoreboard;

    -- G9 leg 2 (gated-ClkMem autonomy): a free-running edge counter on
    -- ClkMem, sampled before/after the frozen-bus window so the "no edges
    -- at all" claim is a real observation, not an assumption from never
    -- calling bus_read/bus_write during the window.
    signal clkmem_edge_count : natural := 0;

begin

    clkmem_monitor : process(ClkMem)
    begin
        if rising_edge(ClkMem) then
            clkmem_edge_count <= clkmem_edge_count + 1;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- clock / gated register-bus clock (D1/D2; mirrors every other bench)
    ----------------------------------------------------------------------------
    clk    <= not clk after PERIOD / 2;
    ClkMem <= clk when pbus.en_mem = '0' else '0';

    ----------------------------------------------------------------------------
    -- DUT (generics = v1 defaults verbatim, D6)
    ----------------------------------------------------------------------------
    dut : component EVFAB
        generic map (
            N_CH        => 8,
            N_EV        => 16,
            N_TASK      => 10,
            EV_GPIO_IDX => 15,
            EV_MODE_TGL => X"00000370",
            EV_MODE_LVL => X"00002000",
            VER         => 1
        )
        port map (
            clk         => clk,
            resetn      => resetn,
            irq_evfab   => irq_evfab,
            ClkMem      => ClkMem,
            EnMemPeriph => pbus.en_mem,
            WEn         => pbus.wen,
            MABPart     => pbus.addr_periph,
            wdata       => pbus.write_data,
            rdata_out   => rdata_out,
            ev_in       => ev_in,
            gpio0_evin  => gpio0_evin,
            task_busy   => task_busy,
            task_pulse  => task_pulse
        );

    ----------------------------------------------------------------------------
    -- Watchdog: abort with a FAIL banner if the stimulus ever hangs.
    ----------------------------------------------------------------------------
    watchdog : process
    begin
        wait for 60 ms;
        if not tb_done then
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   EVFAB_TB FAIL (WATCHDOG TIMEOUT -- stimulus never finished)" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
            stop;
        end if;
        wait;
    end process;

    ----------------------------------------------------------------------------
    -- stimulus
    ----------------------------------------------------------------------------
    stim_proc : process
        variable rdw, exp : std_logic_vector(31 downto 0);
        variable ok       : boolean;
        variable cyc      : natural;
        variable edges0   : natural;
        variable g9_mismatches : natural := 0;
        variable pulse_cnt : natural := 0;

        -- shadow-model state (G5 / G9 leg 2)
        variable sh     : evfab_shadow_t;
        variable tp_exp : std_logic_vector(EVFAB_N_TASK-1 downto 0);

        -- G5 pseudo-random stream state
        variable lfsr24 : std_logic_vector(23 downto 0) := x"ACE1A5";
        type nat_ch_arr_t is array (0 to EVFAB_N_CH-1) of natural;
        variable g5_evsel, g5_tasksel     : nat_ch_arr_t;
        variable g5_mismatches            : natural := 0;
        variable g5_exp_cnt, g5_real_cnt  : evfab_taskcnt_arr_t := (others => 0);

        -- one step of a 24-bit LFSR (arbitrary taps -- only needs to be a
        -- deterministic, decent pseudo-random bit stream, not a proven
        -- maximal-length polynomial).
        procedure lfsr_step(variable v : inout std_logic_vector(23 downto 0)) is
        begin
            if v(0) = '1' then
                v := ('0' & v(23 downto 1)) xor x"D90000";
            else
                v := '0' & v(23 downto 1);
            end if;
        end procedure;

        ------------------------------------------------------------------
        -- generic edge wait
        ------------------------------------------------------------------
        procedure wait_n(n : natural) is
        begin
            for i in 1 to n loop
                wait until clk = '1';
            end loop;
        end procedure;

        ------------------------------------------------------------------
        -- mode-aware event driving (D9). `ev_lat` returns the design doc's
        -- worked latency (diagrams A/B): 1 clk for P, 3 for T/L. `drive_event`
        -- performs the reference-edge + fire dance for one canonical event;
        -- `clear_event` un-asserts a P-mode pulse (T/L/GPIO self-clear or are
        -- left for the NEXT call's own settle, see evfab_bfm_pkg's header).
        ------------------------------------------------------------------
        function ev_lat(e : natural) return natural is
        begin
            if evfab_ev_is_tgl(e) or evfab_ev_is_lvl(e) then
                return 3;
            else
                return 1;
            end if;
        end function;

        procedure drive_event(e : natural) is
        begin
            if evfab_ev_is_tgl(e) then
                wait until clk = '1';
                ev_in(e) <= not ev_in(e);
            elsif evfab_ev_is_lvl(e) then
                ev_in(e) <= '0';
                wait_n(4);              -- drain the 3-flop pipeline
                wait until clk = '1';
                ev_in(e) <= '1';        -- clean rising edge
            else
                wait until clk = '1';
                ev_in(e) <= '1';        -- P: one-clk pulse (caller clears)
            end if;
        end procedure;

        procedure clear_event(e : natural) is
        begin
            if (not evfab_ev_is_tgl(e)) and (not evfab_ev_is_lvl(e)) then
                ev_in(e) <= '0';        -- P-mode self-clear
            end if;
        end procedure;

        procedure drive_gpio(g : natural) is
        begin
            gpio0_evin(g) <= '0';
            wait_n(4);
            wait until clk = '1';
            gpio0_evin(g) <= '1';
        end procedure;

        procedure clear_gpio(g : natural) is
        begin
            gpio0_evin(g) <= '0';
        end procedure;

        ------------------------------------------------------------------
        -- SAMPLE-POINT CONTRACT (the one thing every task_pulse check in
        -- this bench depends on). `wait until clk = '1'` resumes this
        -- process in the SAME delta cycle in which clk changed, i.e. BEFORE
        -- the DUT's own rising-edge processes have applied their scheduled
        -- updates -- so a registered DUT output read right after that wait
        -- still carries its PRE-edge value. The design doc's worked timing
        -- diagrams A/B count CYCLES (a value shown in Ck lives between edge
        -- k and edge k+1), so the edge at which a pulse becomes OBSERVABLE
        -- here is ONE later than the doc's latency number: P-mode latency 1
        -- is observed at edge 2, T/L latency 3 at edge 4. (evfab_bfm_pkg's
        -- shadow model already encodes exactly this via its `raw_prev` lag,
        -- which is why G5/G9-2 compare cleanly cycle-for-cycle.)
        --
        -- fire_event/fire_gpio fire one event and leave the stimulus process
        -- parked ON that observation edge: they deassert a P-mode drive at
        -- the doc's latency edge (so the input stays a ONE-clk pulse, the D9
        -- producer contract) and then take one more edge. T/L/GPIO drives
        -- self-clear or are level-held, so their clear is a no-op.
        ------------------------------------------------------------------
        procedure fire_event(e : natural) is
        begin
            drive_event(e);
            wait_n(ev_lat(e));
            clear_event(e);
            wait until clk = '1';
        end procedure;

        procedure fire_gpio(g : natural) is
        begin
            drive_gpio(g);
            wait_n(3);
            clear_gpio(g);
            wait until clk = '1';
        end procedure;

        ------------------------------------------------------------------
        -- register-bus write helpers (thin wrappers over periph_tb_pkg's
        -- bus_write, packing the field into the right lane).
        ------------------------------------------------------------------
        procedure w_cr(en : std_logic) is
            variable v : std_logic_vector(31 downto 0) := (others => '0');
        begin
            v(EVFAB_CR_EN) := en;
            bus_write(clk, pbus, EVFAB_SLOT_CR, v);
        end procedure;

        procedure w_chen(val : std_logic_vector(EVFAB_N_CH-1 downto 0)) is
            variable v : std_logic_vector(31 downto 0) := (others => '0');
        begin
            v(EVFAB_N_CH-1 downto 0) := val;
            bus_write(clk, pbus, EVFAB_SLOT_CHEN, v);
        end procedure;

        procedure w_chenset(val : std_logic_vector(EVFAB_N_CH-1 downto 0)) is
            variable v : std_logic_vector(31 downto 0) := (others => '0');
        begin
            v(EVFAB_N_CH-1 downto 0) := val;
            bus_write(clk, pbus, EVFAB_SLOT_CHENSET, v);
        end procedure;

        procedure w_chenclr(val : std_logic_vector(EVFAB_N_CH-1 downto 0)) is
            variable v : std_logic_vector(31 downto 0) := (others => '0');
        begin
            v(EVFAB_N_CH-1 downto 0) := val;
            bus_write(clk, pbus, EVFAB_SLOT_CHENCLR, v);
        end procedure;

        procedure w_cfg(ch : natural; evsel : natural; tasksel : natural) is
        begin
            bus_write(clk, pbus, evfab_slot_ch(ch), evfab_mk_cfg(evsel, tasksel));
        end procedure;

        procedure w_gpiomask(val : std_logic_vector(7 downto 0)) is
            variable v : std_logic_vector(31 downto 0) := (others => '0');
        begin
            v(7 downto 0) := val;
            bus_write(clk, pbus, EVFAB_SLOT_GPIOMASK, v);
        end procedure;

        procedure w_chtrig(mask : std_logic_vector(EVFAB_N_CH-1 downto 0)) is
            variable v : std_logic_vector(31 downto 0) := (others => '0');
        begin
            v(EVFAB_N_CH-1 downto 0) := mask;
            bus_write(clk, pbus, EVFAB_SLOT_CHTRIG, v);
        end procedure;

        procedure w_evtrig(mask : std_logic_vector(EVFAB_N_EV-1 downto 0)) is
            variable v : std_logic_vector(31 downto 0) := (others => '0');
        begin
            v(EVFAB_N_EV-1 downto 0) := mask;
            bus_write(clk, pbus, EVFAB_SLOT_EVTRIG, v);
        end procedure;

        procedure w1c_fired(mask : std_logic_vector(EVFAB_N_CH-1 downto 0)) is
            variable v : std_logic_vector(31 downto 0) := (others => '0');
        begin
            v(EVFAB_N_CH-1 downto 0) := mask;
            bus_write(clk, pbus, EVFAB_SLOT_FIRED, v);
        end procedure;

        procedure w1c_ovr(mask : std_logic_vector(EVFAB_N_CH-1 downto 0)) is
            variable v : std_logic_vector(31 downto 0) := (others => '0');
        begin
            v(EVFAB_N_CH-1 downto 0) := mask;
            bus_write(clk, pbus, EVFAB_SLOT_OVR, v);
        end procedure;

        procedure w1c_evstat(mask : std_logic_vector(EVFAB_N_EV-1 downto 0)) is
            variable v : std_logic_vector(31 downto 0) := (others => '0');
        begin
            v(EVFAB_N_EV-1 downto 0) := mask;
            bus_write(clk, pbus, EVFAB_SLOT_EVSTAT, v);
        end procedure;

        ------------------------------------------------------------------
        -- Full chip-reset pulse, reusable between independent groups (TRNG
        -- precedent): also re-idles every producer-side signal and resets
        -- the shadow model so no group leaks state into the next.
        ------------------------------------------------------------------
        procedure do_reset is
        begin
            resetn     <= '0';
            pbus       <= PERIPH_BUS_IDLE;
            ev_in      <= (others => '0');
            gpio0_evin <= (others => '0');
            task_busy  <= (others => '0');
            wait for 12 * PERIOD;
            wait for 1 ns;
            resetn <= '1';
            wait for 8 * PERIOD;
            evfab_shadow_reset(sh);
        end procedure;

        ------------------------------------------------------------------
        -- G1 sweep helper: program channel `ch` = {e,t}, fire the event
        -- (per-mode), and assert task_pulse(t) asserts at the exact D5/D9
        -- worked latency, exclusively on that one task line, for exactly
        -- one clk.
        ------------------------------------------------------------------
        procedure g1_check(e : natural; t : natural; ch : natural) is
            variable lat : natural;
        begin
            w_cfg(ch, e, t);
            evfab_settle(clk);

            -- fire_event/fire_gpio park us ON the observation edge (see the
            -- SAMPLE-POINT CONTRACT above): `lat` is still the design doc's
            -- worked latency, which is what the check text reports.
            if e = EVFAB_EV_GPIO_IDX then
                lat := 3;
                fire_gpio(0);
            else
                lat := ev_lat(e);
                fire_event(e);
            end if;

            sb.check_bit("G1 e=" & integer'image(e) & " t=" & integer'image(t) &
                         " ch=" & integer'image(ch) & ": task_pulse asserts at latency " &
                         integer'image(lat), to_X01(task_pulse(t)), '1');
            for tt in 0 to EVFAB_N_TASK - 1 loop
                if tt /= t then
                    sb.check_bit("G1 e=" & integer'image(e) & " t=" & integer'image(t) &
                                 " ch=" & integer'image(ch) & ": task_pulse(" &
                                 integer'image(tt) & ") stays low",
                                 to_X01(task_pulse(tt)), '0');
                end if;
            end loop;

            wait until clk = '1';
            sb.check_bit("G1 e=" & integer'image(e) & " t=" & integer'image(t) &
                         " ch=" & integer'image(ch) & ": task_pulse(t) exactly one clk wide",
                         to_X01(task_pulse(t)), '0');
        end procedure;

        ------------------------------------------------------------------
        -- G7 out-of-range helper: sweep every real ev_in-reachable event
        -- (0..14) against a channel config that structurally can never
        -- match (out-of-range EVSEL); task_pulse(t) must stay low throughout.
        ------------------------------------------------------------------
        procedure check_no_fire_all_events(t : natural) is
        begin
            for e in 0 to EVFAB_N_EV - 2 loop
                fire_event(e);      -- parks on the observation edge
                sb.check_bit("G7 out-of-range: task_pulse(" & integer'image(t) &
                             ") stays low sweeping ev_in (e=" & integer'image(e) & ")",
                             to_X01(task_pulse(t)), '0');
                wait_n(1);
            end loop;
        end procedure;

    begin
        ------------------------------------------------------------------
        -- Reset
        ------------------------------------------------------------------
        do_reset;
        report "=== EVFAB_TB start ===" severity note;

        ------------------------------------------------------------------
        -- GROUP G0: reset / CAP / inertness
        ------------------------------------------------------------------
        report "=== GROUP G0: reset / CAP / inertness ===" severity note;

        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_CR, rdw);
        sb.check_slv("G0: CR resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_SR, rdw);
        sb.check_slv("G0: SR resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_CHEN, rdw);
        sb.check_slv("G0: CHEN resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_FIRED, rdw);
        sb.check_slv("G0: FIRED resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_OVR, rdw);
        sb.check_slv("G0: OVR resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_EVSTAT, rdw);
        sb.check_slv("G0: EVSTAT resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_GPIOMASK, rdw);
        sb.check_slv("G0: EVGPIOMASK resets to 0", rdw, x"00000000");

        for ch in 0 to EVFAB_CHCFG_SLOTS - 1 loop
            bus_read(clk, pbus, rdata_out, evfab_slot_ch(ch), rdw);
            sb.check_slv("G0: CH" & integer'image(ch) & "CFG resets to 0", rdw, x"00000000");
        end loop;

        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_IE, rdw);
        sb.check_slv("G0: slot 2 (IE, reserved) reads 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_RSVD12, rdw);
        sb.check_slv("G0: slot 12 (reserved) reads 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_RSVD13, rdw);
        sb.check_slv("G0: slot 13 (reserved) reads 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_RSVD14, rdw);
        sb.check_slv("G0: slot 14 (reserved) reads 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, 32, rdw);
        sb.check_slv("G0: slot 32 (>=32 reserved) reads 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, 47, rdw);
        sb.check_slv("G0: slot 47 (>=32 reserved) reads 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, 63, rdw);
        sb.check_slv("G0: slot 63 (>=32 reserved) reads 0", rdw, x"00000000");

        sb.check_bit("G0: irq_evfab = 0 out of reset (vectorless v1, D20)",
                     to_X01(irq_evfab), '0');
        for tt in 0 to EVFAB_N_TASK - 1 loop
            sb.check_bit("G0: task_pulse(" & integer'image(tt) & ") = 0 out of reset",
                         to_X01(task_pulse(tt)), '0');
        end loop;

        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_CAP, rdw);
        sb.check_slv("G0: CAP = 0x010A1008 (VER=1,NTASK=10,NEV=16,NCH=8, D19)",
                     rdw, EVFAB_CAP_EXPECT);

        -- CAP/SR/IE writes ignored (ro / reserved)
        bus_write(clk, pbus, EVFAB_SLOT_CAP, x"FFFFFFFF");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_CAP, rdw);
        sb.check_slv("G0: CAP write ignored (still reads the ro constant)", rdw, EVFAB_CAP_EXPECT);
        bus_write(clk, pbus, EVFAB_SLOT_SR, x"FFFFFFFF");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_SR, rdw);
        sb.check_slv("G0: SR write ignored (still reads 0)", rdw, x"00000000");
        bus_write(clk, pbus, EVFAB_SLOT_IE, x"FFFFFFFF");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_IE, rdw);
        sb.check_slv("G0: IE (reserved slot 2) write ignored, reads 0", rdw, x"00000000");

        -- With EN=0/CHEN=0 (still reset defaults): pulse EVERY ev_in and
        -- gpio0_evin bit. task_pulse/FIRED/OVR must stay 0 (D13 double
        -- gate) but EVSTAT records every ev_in-reachable event (D14
        -- ungated-tap property); the GPIO0 path stays fully inert because
        -- EVGPIOMASK=0 absorbs it (D10 reset note).
        for e in 0 to EVFAB_N_EV - 2 loop   -- 0..14 (ev_in(15) is ignored, D10)
            drive_event(e);
            wait_n(ev_lat(e));
            clear_event(e);
            wait_n(1);
        end loop;
        for g in 0 to 7 loop
            fire_gpio(g);
            clear_gpio(g);
            wait_n(1);
        end loop;

        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_FIRED, rdw);
        sb.check_slv("G0: FIRED stays 0 while EN=0/CHEN=0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_OVR, rdw);
        sb.check_slv("G0: OVR stays 0 while EN=0/CHEN=0", rdw, x"00000000");
        for tt in 0 to EVFAB_N_TASK - 1 loop
            sb.check_bit("G0: task_pulse(" & integer'image(tt) & ") stays 0 while EN=0/CHEN=0",
                         to_X01(task_pulse(tt)), '0');
        end loop;
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_EVSTAT, rdw);
        sb.check_slv("G0: EVSTAT recorded every ev_in event (0-14) but NOT the masked GPIO event 15",
                     rdw, x"00007FFF");

        w1c_evstat("1111111111111111");   -- clean up for the next group

        ------------------------------------------------------------------
        -- GROUP G1: pulse integrity + latency, full EV x TASK sweep
        ------------------------------------------------------------------
        report "=== GROUP G1: pulse integrity + latency, full EV x TASK sweep ===" severity note;
        w_cr('1');
        w_gpiomask("00000001");     -- enable GPIO0 bit0 for the e=15 sweep legs

        -- full 16x10 sweep through CH0
        w_chen("00000001");
        for e in 0 to EVFAB_N_EV - 1 loop
            for t in 0 to EVFAB_N_TASK - 1 loop
                g1_check(e, t, 0);
            end loop;
        end loop;

        -- spot sweep on CH7 (a representative subset, not the full 160)
        w_chen("10000000");
        for e in 0 to EVFAB_N_EV - 1 loop
            g1_check(e, e mod EVFAB_N_TASK, 7);
        end loop;
        g1_check(4, 3, 7);
        g1_check(13, 6, 7);
        g1_check(15, 9, 7);

        ------------------------------------------------------------------
        -- GROUP G2: enable gating both ways + CHENSET/CHENCLR neighbour-safety
        ------------------------------------------------------------------
        report "=== GROUP G2: enable gating both ways + CHENSET/CHENCLR ===" severity note;
        do_reset;
        w_cfg(0, 2, 3);              -- CH0 = {EV2(P), TASK3}

        -- CHEN(0)=0 -> inert (task/FIRED/OVR), but EVSTAT still records
        w_cr('1');
        fire_event(2);
        sb.check_bit("G2: task_pulse(3) stays low, CHEN(0)=0", to_X01(task_pulse(3)), '0');
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_FIRED, rdw);
        sb.check_bit("G2: FIRED(0) stays 0, CHEN(0)=0", to_X01(rdw(0)), '0');
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_OVR, rdw);
        sb.check_bit("G2: OVR(0) stays 0, CHEN(0)=0", to_X01(rdw(0)), '0');
        clear_event(2);
        wait_n(1);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_EVSTAT, rdw);
        sb.check_bit("G2: EVSTAT(2) still records under CHEN(0)=0", to_X01(rdw(2)), '1');
        w1c_evstat("0000000000000100");

        -- CR.EN=0 with CHEN=0xFF -> still fully inert
        w_cr('0');
        w_chen("11111111");
        fire_event(2);
        sb.check_bit("G2: task_pulse(3) stays low, CR.EN=0 even at CHEN=0xFF",
                     to_X01(task_pulse(3)), '0');
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_FIRED, rdw);
        sb.check_bit("G2: FIRED(0) stays 0, CR.EN=0", to_X01(rdw(0)), '0');
        clear_event(2);
        wait_n(1);

        -- re-enable -> fires again
        w_cr('1');
        w_chen("00000001");
        fire_event(2);
        sb.check_bit("G2: task_pulse(3) fires again once re-enabled", to_X01(task_pulse(3)), '1');
        clear_event(2);
        wait_n(1);

        -- CHENSET/CHENCLR neighbour-safety
        w_chen("01010101");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_CHEN, rdw);
        sb.check_slv("G2: CHEN readback after plain write = 0x55", rdw(7 downto 0), x"55");
        w_chenset("00000010");
        exp := x"00000057";
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_CHEN, rdw);
        sb.check_slv("G2: CHEN after CHENSET(bit1) = 0x57", rdw, exp);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_CHENSET, rdw);
        sb.check_slv("G2: CHENSET readback mirrors CHEN = 0x57", rdw, exp);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_CHENCLR, rdw);
        sb.check_slv("G2: CHENCLR readback mirrors CHEN = 0x57", rdw, exp);

        w_chenclr("01000000");
        exp := x"00000017";
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_CHEN, rdw);
        sb.check_slv("G2: CHEN after CHENCLR(bit6) = 0x17 (no neighbour disturbed)", rdw, exp);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_CHENSET, rdw);
        sb.check_slv("G2: CHENSET readback mirrors CHEN = 0x17", rdw, exp);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_CHENCLR, rdw);
        sb.check_slv("G2: CHENCLR readback mirrors CHEN = 0x17", rdw, exp);

        w_chenset("00000000");    -- write 0 to SET is a no-op
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_CHEN, rdw);
        sb.check_slv("G2: CHENSET(0) is a no-op", rdw, exp);
        w_chenclr("00000000");    -- write 0 to CLR is a no-op
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_CHEN, rdw);
        sb.check_slv("G2: CHENCLR(0) is a no-op", rdw, exp);

        -- ENR(31) mirrors CHEN(n) live: CHEN=0x17 = 0b0001_0111 -> bits 0,1,2,4 set
        bus_read(clk, pbus, rdata_out, evfab_slot_ch(0), rdw);
        sb.check_bit("G2: CH0CFG.ENR mirrors CHEN(0)=1", to_X01(rdw(EVFAB_CHCFG_ENR)), '1');
        bus_read(clk, pbus, rdata_out, evfab_slot_ch(1), rdw);
        sb.check_bit("G2: CH1CFG.ENR mirrors CHEN(1)=1", to_X01(rdw(EVFAB_CHCFG_ENR)), '1');
        bus_read(clk, pbus, rdata_out, evfab_slot_ch(3), rdw);
        sb.check_bit("G2: CH3CFG.ENR mirrors CHEN(3)=0", to_X01(rdw(EVFAB_CHCFG_ENR)), '0');
        bus_read(clk, pbus, rdata_out, evfab_slot_ch(4), rdw);
        sb.check_bit("G2: CH4CFG.ENR mirrors CHEN(4)=1", to_X01(rdw(EVFAB_CHCFG_ENR)), '1');
        bus_read(clk, pbus, rdata_out, evfab_slot_ch(5), rdw);
        sb.check_bit("G2: CH5CFG.ENR mirrors CHEN(5)=0", to_X01(rdw(EVFAB_CHCFG_ENR)), '0');

        ------------------------------------------------------------------
        -- GROUP G3: fan-out same cycle
        ------------------------------------------------------------------
        report "=== GROUP G3: fan-out same cycle ===" severity note;
        do_reset;
        w_cr('1');

        -- 4 channels / same event / 4 different tasks
        w_cfg(0, 2, 0);
        w_cfg(1, 2, 1);
        w_cfg(2, 2, 2);
        w_cfg(3, 2, 3);
        w_chen("00001111");
        fire_event(2);
        for t in 0 to 3 loop
            sb.check_bit("G3(4ch): task_pulse(" & integer'image(t) & ") fires (fan-out)",
                         to_X01(task_pulse(t)), '1');
        end loop;
        for t in 4 to EVFAB_N_TASK - 1 loop
            sb.check_bit("G3(4ch): task_pulse(" & integer'image(t) & ") stays low",
                         to_X01(task_pulse(t)), '0');
        end loop;
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_FIRED, rdw);
        sb.check_slv("G3(4ch): FIRED = 0x0F (4 channels)", rdw(7 downto 0), x"0F");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_OVR, rdw);
        sb.check_slv("G3(4ch): OVR = 0x00 (no merge, distinct tasks, corner 7)", rdw(7 downto 0), x"00");
        clear_event(2);
        wait_n(1);
        w1c_fired("00001111");

        -- 8 channels / same event / 8 different tasks
        for n in 0 to 7 loop
            w_cfg(n, 2, n);
        end loop;
        w_chen("11111111");
        fire_event(2);
        for t in 0 to 7 loop
            sb.check_bit("G3(8ch): task_pulse(" & integer'image(t) & ") fires (fan-out)",
                         to_X01(task_pulse(t)), '1');
        end loop;
        for t in 8 to EVFAB_N_TASK - 1 loop
            sb.check_bit("G3(8ch): task_pulse(" & integer'image(t) & ") stays low",
                         to_X01(task_pulse(t)), '0');
        end loop;
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_FIRED, rdw);
        sb.check_slv("G3(8ch): FIRED = 0xFF (8 channels)", rdw(7 downto 0), x"FF");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_OVR, rdw);
        sb.check_slv("G3(8ch): OVR = 0x00 (no merge, distinct tasks)", rdw(7 downto 0), x"00");
        clear_event(2);
        wait_n(1);
        w1c_fired("11111111");

        ------------------------------------------------------------------
        -- GROUP G4: same-task OR-merge + staggered
        ------------------------------------------------------------------
        report "=== GROUP G4: same-task OR-merge + staggered ===" severity note;
        do_reset;
        w_cr('1');

        -- A: 3 channels, same event, same task, same cycle -> ONE pulse,
        -- FIRED and OVR on all 3 (corner 2).
        w_cfg(0, 1, 5);
        w_cfg(1, 1, 5);
        w_cfg(2, 1, 5);
        w_chen("00000111");
        fire_event(1);
        sb.check_bit("G4A: task_pulse(5) fires (merged)", to_X01(task_pulse(5)), '1');
        for t in 0 to EVFAB_N_TASK - 1 loop
            if t /= 5 then
                sb.check_bit("G4A: task_pulse(" & integer'image(t) & ") stays low",
                             to_X01(task_pulse(t)), '0');
            end if;
        end loop;
        clear_event(1);
        wait_n(1);
        sb.check_bit("G4A: task_pulse(5) is exactly one clk wide (never 2, never 3)",
                     to_X01(task_pulse(5)), '0');
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_FIRED, rdw);
        sb.check_slv("G4A: FIRED = 0x07 (all 3 merging channels)", rdw(7 downto 0), x"07");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_OVR, rdw);
        sb.check_slv("G4A: OVR = 0x07 (merge on all 3, corner 2)", rdw(7 downto 0), x"07");
        w1c_fired("00000111");
        w1c_ovr("00000111");

        -- B: same 3 channels, DIFFERENT events, staggered by 1 clk each ->
        -- 3 separate one-clk pulses on the SAME task, no OVR (corner 3).
        w_cfg(0, 1, 5);
        w_cfg(1, 2, 5);
        w_cfg(2, 3, 5);
        w_chen("00000111");
        -- Stimulus schedule is unchanged; each check sits one edge after the
        -- drive it observes (the SAMPLE-POINT CONTRACT above).
        wait until clk = '1';
        ev_in(1) <= '1';
        wait until clk = '1';
        ev_in(1) <= '0';
        ev_in(2) <= '1';
        wait until clk = '1';
        sb.check_bit("G4B: task_pulse(5) fires from CH0/EV1", to_X01(task_pulse(5)), '1');
        ev_in(2) <= '0';
        ev_in(3) <= '1';
        wait until clk = '1';
        sb.check_bit("G4B: task_pulse(5) fires from CH1/EV2 (staggered)", to_X01(task_pulse(5)), '1');
        ev_in(3) <= '0';
        wait until clk = '1';
        sb.check_bit("G4B: task_pulse(5) fires from CH2/EV3 (staggered)", to_X01(task_pulse(5)), '1');
        wait until clk = '1';
        sb.check_bit("G4B: task_pulse(5) drops after the staggered run", to_X01(task_pulse(5)), '0');
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_OVR, rdw);
        sb.check_slv("G4B: OVR = 0x00 (staggered != merged, corner 3)", rdw(7 downto 0), x"00");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_FIRED, rdw);
        sb.check_slv("G4B: FIRED = 0x07 (all 3 fired, just not merged)", rdw(7 downto 0), x"07");
        w1c_fired("00000111");

        -- C: one channel firing two adjacent cycles -> 2 pulses, no OVR
        -- (corner 4). Reuse CH0 = {EV1(P), TASK5}; CHEN already has bit0 set.
        w_chen("00000001");
        -- ev_in(1) is held across exactly TWO rising edges, so the DUT sees
        -- two one-clk fires; the checks sit one edge later (SAMPLE-POINT).
        wait until clk = '1';
        ev_in(1) <= '1';
        wait until clk = '1';
        wait until clk = '1';
        sb.check_bit("G4C: task_pulse(5) fires (1st of 2 adjacent)", to_X01(task_pulse(5)), '1');
        ev_in(1) <= '0';
        wait until clk = '1';
        sb.check_bit("G4C: task_pulse(5) fires (2nd of 2 adjacent)", to_X01(task_pulse(5)), '1');
        wait until clk = '1';
        sb.check_bit("G4C: task_pulse(5) drops (only 2, not 3)", to_X01(task_pulse(5)), '0');
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_OVR, rdw);
        sb.check_slv("G4C: OVR = 0x00 (same channel repeating, not a merge, corner 4)",
                     rdw(7 downto 0), x"00");
        w1c_fired("00000001");

        ------------------------------------------------------------------
        -- GROUP G5: back-to-back N-for-N (shadow model)
        ------------------------------------------------------------------
        report "=== GROUP G5: back-to-back N-for-N (shadow model) ===" severity note;
        do_reset;
        g5_mismatches := 0;
        g5_exp_cnt    := (others => 0);
        g5_real_cnt   := (others => 0);

        w_cr('1');
        evfab_shadow_set_cr_en(sh, '1');
        w_chen("11111111");
        evfab_shadow_set_chen(sh, "11111111");
        w_gpiomask("11111111");
        evfab_shadow_set_gpiomask(sh, "11111111");

        -- randomized channel map (deterministic LFSR draw -- reproducible)
        for n in 0 to EVFAB_N_CH - 1 loop
            lfsr_step(lfsr24);
            g5_evsel(n) := to_integer(unsigned(lfsr24(3 downto 0)));
            lfsr_step(lfsr24);
            g5_tasksel(n) := to_integer(unsigned(lfsr24(3 downto 0))) mod EVFAB_N_TASK;
            w_cfg(n, g5_evsel(n), g5_tasksel(n));
            evfab_shadow_set_cfg(sh, n, g5_evsel(n), g5_tasksel(n));
        end loop;
        evfab_settle(clk);

        -- ~2000-clk pseudo-random event stream, compared against the
        -- shadow model EVERY clk edge.
        for i in 1 to 2000 loop
            lfsr_step(lfsr24);
            wait until clk = '0';
            ev_in      <= lfsr24(15 downto 0);
            gpio0_evin <= lfsr24(23 downto 16);
            wait until clk = '1';
            evfab_shadow_tick(sh, lfsr24(15 downto 0), lfsr24(23 downto 16), task_busy, tp_exp);
            if to_X01(task_pulse) /= tp_exp then
                g5_mismatches := g5_mismatches + 1;
                report "G5 MISMATCH at cycle " & integer'image(i) severity warning;
            end if;
            for t in 0 to EVFAB_N_TASK - 1 loop
                if tp_exp(t) = '1' then
                    g5_exp_cnt(t) := g5_exp_cnt(t) + 1;
                end if;
                if to_X01(task_pulse(t)) = '1' then
                    g5_real_cnt(t) := g5_real_cnt(t) + 1;
                end if;
            end loop;
        end loop;

        sb.check_true("G5: task_pulse matched the shadow model every cycle (2000-cycle stream)",
                      g5_mismatches = 0);
        for t in 0 to EVFAB_N_TASK - 1 loop
            sb.check_true("G5: task " & integer'image(t) & " pulse count N-for-N (exp=" &
                          integer'image(g5_exp_cnt(t)) & ", got=" & integer'image(g5_real_cnt(t)) & ")",
                          g5_real_cnt(t) = g5_exp_cnt(t));
        end loop;

        -- park the stream, then final FIRED/OVR/EVSTAT readback vs shadow.
        ev_in      <= (others => '0');
        gpio0_evin <= (others => '0');
        evfab_settle(clk);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_FIRED, rdw);
        sb.check_slv("G5: final FIRED readback matches the shadow model",
                     rdw(EVFAB_N_CH - 1 downto 0), sh.fired);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_OVR, rdw);
        sb.check_slv("G5: final OVR readback matches the shadow model",
                     rdw(EVFAB_N_CH - 1 downto 0), sh.ovr);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_EVSTAT, rdw);
        sb.check_slv("G5: final EVSTAT readback matches the shadow model",
                     rdw(EVFAB_N_EV - 1 downto 0), sh.evstat);

        ------------------------------------------------------------------
        -- GROUP G6: CHTRIG / EVTRIG + held-write = exactly one
        ------------------------------------------------------------------
        report "=== GROUP G6: CHTRIG / EVTRIG + held-write = exactly one ===" severity note;
        do_reset;
        w_cr('1');
        w_cfg(0, 31, 2);   -- CH0: EVSEL=31 (NONE) -- only CHTRIG can fire it
        w_chen("00000001");

        -- CHTRIG bit0 -> one pulse + FIRED (D16)
        w_chtrig("00000001");
        evfab_wait_task_pulse(clk, task_pulse, 2, EVFAB_PULSE_GUARD, cyc, ok);
        sb.check_true("G6: CHTRIG(0) produces a task_pulse (bounded)", ok);
        wait until clk = '1';
        sb.check_bit("G6: task_pulse(2) exactly one clk wide after CHTRIG", to_X01(task_pulse(2)), '0');
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_FIRED, rdw);
        sb.check_bit("G6: FIRED(0) sets from CHTRIG", to_X01(rdw(0)), '1');
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_CHTRIG, rdw);
        sb.check_slv("G6: CHTRIG reads 0", rdw, x"00000000");
        w1c_fired("00000001");

        -- CHTRIG to a disabled channel does nothing (D16)
        w_chen("00000000");
        w_chtrig("00000001");
        evfab_wait_task_pulse(clk, task_pulse, 2, 20, cyc, ok);
        sb.check_true("G6: CHTRIG(0) to a DISABLED channel produces nothing", not ok);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_FIRED, rdw);
        sb.check_bit("G6: FIRED(0) stays 0, channel disabled", to_X01(rdw(0)), '0');

        -- CHTRIG with CR.EN=0 does nothing
        w_chen("00000001");
        w_cr('0');
        w_chtrig("00000001");
        evfab_wait_task_pulse(clk, task_pulse, 2, 20, cyc, ok);
        sb.check_true("G6: CHTRIG(0) with CR.EN=0 produces nothing", not ok);
        w_cr('1');

        -- EVTRIG bit e -> EVSTAT records + every channel selecting e fires
        w_cfg(0, 7, 3);
        w_cfg(1, 7, 4);
        w_chen("00000011");
        w_evtrig("0000000010000000");   -- bit 7
        evfab_wait_task_pulse(clk, task_pulse, 3, EVFAB_PULSE_GUARD, cyc, ok);
        sb.check_true("G6: EVTRIG(7) fires CH0/TASK3 (bounded)", ok);
        sb.check_bit("G6: EVTRIG(7) fires CH1/TASK4 the same cycle", to_X01(task_pulse(4)), '1');
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_EVSTAT, rdw);
        sb.check_bit("G6: EVSTAT(7) records from EVTRIG", to_X01(rdw(7)), '1');
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_EVTRIG, rdw);
        sb.check_slv("G6: EVTRIG reads 0", rdw, x"00000000");
        w1c_evstat("0000000010000000");
        w1c_fired("00000011");

        -- held write = exactly one injection (diagram C)
        w_chen("00000001");
        bus_write_hold(clk, pbus, EVFAB_SLOT_CHTRIG, x"00000001", 3);
        evfab_wait_task_pulse(clk, task_pulse, 3, EVFAB_PULSE_GUARD, cyc, ok);
        sb.check_true("G6: held CHTRIG write (3 cyc) produces exactly one pulse (bounded)", ok);
        evfab_wait_task_pulse(clk, task_pulse, 3, 20, cyc, ok);
        sb.check_true("G6: held CHTRIG write did NOT re-fire (only one injection)", not ok);
        w1c_fired("00000001");

        -- Held EVTRIG, 5 cycles. The injection lands INSIDE the hold window
        -- (design doc diagram C: the action applies on the 3rd edge of the
        -- window), so a post-hoc bounded wait would MISS it entirely and then
        -- correctly report "no pulse". Count task_pulse assertions across the
        -- whole window plus a tail instead -- a strictly stronger check than
        -- "one, then none": it proves EXACTLY ONE injection.
        w_chen("00000011");
        pulse_cnt := 0;
        wait until clk = '0';
        pbus.addr_periph <= std_logic_vector(to_unsigned(EVFAB_SLOT_EVTRIG, 6));
        pbus.write_data  <= x"00000080";     -- bit 7
        pbus.wen         <= (others => '0');
        pbus.en_mem      <= '0';
        for i in 1 to 5 loop                 -- the 5 held bus clocks
            wait until clk = '1';
            if to_X01(task_pulse(3)) = '1' then pulse_cnt := pulse_cnt + 1; end if;
        end loop;
        wait until clk = '0';
        pbus.en_mem <= '1';
        pbus.wen    <= (others => '1');
        for i in 1 to 8 loop                 -- tail: nothing may re-fire
            wait until clk = '1';
            if to_X01(task_pulse(3)) = '1' then pulse_cnt := pulse_cnt + 1; end if;
        end loop;
        sb.check_true("G6: held EVTRIG write (5 cyc) produces an injection (counted " &
                      integer'image(pulse_cnt) & ")", pulse_cnt >= 1);
        sb.check_true("G6: held EVTRIG write did NOT re-fire (EXACTLY one injection)",
                      pulse_cnt = 1);
        w1c_fired("00000011");
        w1c_evstat("0000000010000000");

        -- two CHTRIG writes in consecutive (separate) accesses -> two pulses
        -- (the re-arm property, D2.2)
        w_chen("00000001");
        w_chtrig("00000001");
        evfab_wait_task_pulse(clk, task_pulse, 3, EVFAB_PULSE_GUARD, cyc, ok);
        sb.check_true("G6: first of two consecutive CHTRIG writes fires (bounded)", ok);
        w_chtrig("00000001");
        evfab_wait_task_pulse(clk, task_pulse, 3, EVFAB_PULSE_GUARD, cyc, ok);
        sb.check_true("G6: second (separate-access) CHTRIG write ALSO fires (re-arm, D2.2)", ok);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_FIRED, rdw);
        sb.check_bit("G6: FIRED(0) set after the two-write re-arm sequence", to_X01(rdw(0)), '1');
        w1c_fired("00000001");

        -- held W1C of FIRED across 4+ cycles with an event injected mid-write
        -- -> FIRED ends SET (a one-cycle clear cannot eat a later event, D14)
        w_cfg(0, 2, 3);      -- CH0 back to a real P-mode tap (EV2)
        fire_event(2);
        sb.check_bit("G6 setup: CH0 fires so FIRED(0) is set going into the held W1C",
                     to_X01(task_pulse(3)), '1');
        clear_event(2);
        wait_n(1);
        wait until clk = '0';
        pbus.addr_periph <= std_logic_vector(to_unsigned(EVFAB_SLOT_FIRED, 6));
        pbus.write_data  <= x"00000001";
        pbus.wen         <= (others => '0');
        pbus.en_mem      <= '0';
        wait until clk = '1';   -- select window open, edge 1
        wait until clk = '1';   -- edge 2: the clear pulse fires within this window
        ev_in(2) <= '1';        -- a fresh event arrives WHILE the W1C is still held
        wait until clk = '1';   -- edge 3
        ev_in(2) <= '0';
        wait until clk = '1';   -- edge 4: extra margin, still held
        wait until clk = '0';
        pbus.en_mem <= '1';
        pbus.wen    <= (others => '1');
        evfab_settle(clk);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_FIRED, rdw);
        sb.check_bit("G6: FIRED(0) ends SET (a one-cycle clear cannot eat a later event, D14)",
                     to_X01(rdw(0)), '1');
        w1c_fired("00000001");

        ------------------------------------------------------------------
        -- GROUP G7: register RW / W1C / set-wins / out-of-range
        ------------------------------------------------------------------
        report "=== GROUP G7: register RW / W1C / set-wins / out-of-range ===" severity note;
        do_reset;
        w_chen("00000000");   -- keep ENR=0 for every channel during the CHnCFG walk

        -- walking-1 on CHEN
        for b in 0 to EVFAB_N_CH - 1 loop
            exp := (others => '0');
            exp(b) := '1';
            w_chen(exp(EVFAB_N_CH - 1 downto 0));
            bus_read(clk, pbus, rdata_out, EVFAB_SLOT_CHEN, rdw);
            sb.check_slv("G7: CHEN walking-1 bit " & integer'image(b), rdw, exp);
        end loop;
        w_chen("00000000");

        -- walking-1 on EVGPIOMASK
        for b in 0 to 7 loop
            exp := (others => '0');
            exp(b) := '1';
            w_gpiomask(exp(7 downto 0));
            bus_read(clk, pbus, rdata_out, EVFAB_SLOT_GPIOMASK, rdw);
            sb.check_slv("G7: EVGPIOMASK walking-1 bit " & integer'image(b), rdw, exp);
        end loop;
        w_gpiomask("00000000");

        -- walking-1 on all 16 CHnCFG slots (reserved bits r0, ENR not
        -- writable, n >= N_CH reads 0 and ignores writes)
        for ch in 0 to EVFAB_CHCFG_SLOTS - 1 loop
            for b in 0 to 4 loop
                w_cfg(ch, 2**b, 0);
                bus_read(clk, pbus, rdata_out, evfab_slot_ch(ch), rdw);
                if ch < EVFAB_N_CH then
                    sb.check_slv("G7: CH" & integer'image(ch) & "CFG EVSEL walking-1 bit " &
                                 integer'image(b), rdw, evfab_mk_cfg(2**b, 0));
                else
                    sb.check_slv("G7: CH" & integer'image(ch) & "CFG (n>=N_CH) ignores write, reads 0",
                                 rdw, x"00000000");
                end if;
            end loop;
            for b in 0 to 3 loop
                w_cfg(ch, 0, 2**b);
                bus_read(clk, pbus, rdata_out, evfab_slot_ch(ch), rdw);
                if ch < EVFAB_N_CH then
                    sb.check_slv("G7: CH" & integer'image(ch) & "CFG TASKSEL walking-1 bit " &
                                 integer'image(b), rdw, evfab_mk_cfg(0, 2**b));
                else
                    sb.check_slv("G7: CH" & integer'image(ch) & "CFG (n>=N_CH) ignores write, reads 0",
                                 rdw, x"00000000");
                end if;
            end loop;
            bus_write(clk, pbus, evfab_slot_ch(ch), x"80000000");   -- attempt to write ENR
            bus_read(clk, pbus, rdata_out, evfab_slot_ch(ch), rdw);
            sb.check_bit("G7: CH" & integer'image(ch) & "CFG.ENR is not writable",
                        to_X01(rdw(EVFAB_CHCFG_ENR)), '0');
            w_cfg(ch, 0, 0);
        end loop;

        -- reserved slots 2/12/13/14 and 32-63 ignore writes, read 0
        bus_write(clk, pbus, EVFAB_SLOT_IE, x"FFFFFFFF");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_IE, rdw);
        sb.check_slv("G7: slot 2 (IE) write ignored, reads 0", rdw, x"00000000");
        bus_write(clk, pbus, EVFAB_SLOT_RSVD12, x"FFFFFFFF");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_RSVD12, rdw);
        sb.check_slv("G7: slot 12 write ignored, reads 0", rdw, x"00000000");
        bus_write(clk, pbus, EVFAB_SLOT_RSVD13, x"FFFFFFFF");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_RSVD13, rdw);
        sb.check_slv("G7: slot 13 write ignored, reads 0", rdw, x"00000000");
        bus_write(clk, pbus, EVFAB_SLOT_RSVD14, x"FFFFFFFF");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_RSVD14, rdw);
        sb.check_slv("G7: slot 14 write ignored, reads 0", rdw, x"00000000");
        bus_write(clk, pbus, 40, x"FFFFFFFF");
        bus_read(clk, pbus, rdata_out, 40, rdw);
        sb.check_slv("G7: slot 40 (>=32) write ignored, reads 0", rdw, x"00000000");
        bus_write(clk, pbus, 63, x"FFFFFFFF");
        bus_read(clk, pbus, rdata_out, 63, rdw);
        sb.check_slv("G7: slot 63 write ignored, reads 0", rdw, x"00000000");

        -- W1C clears ONLY the written bits
        w_cfg(0, 31, 0);
        w_cfg(1, 31, 1);
        w_cfg(2, 31, 2);
        w_chen("00000111");
        w_cr('1');
        w_chtrig("00000111");
        evfab_settle(clk);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_FIRED, rdw);
        sb.check_slv("G7: FIRED = 0x07 before selective W1C", rdw(7 downto 0), x"07");
        w1c_fired("00000010");
        evfab_settle(clk);   -- D5 GATE CLOSURE FIX: action-visibility (3 clk) before the check
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_FIRED, rdw);
        sb.check_slv("G7: W1C clears ONLY the written bit(s) -> FIRED = 0x05", rdw(7 downto 0), x"05");
        w1c_fired("00000101");

        -- set-wins: align a W1C with a fire -> the flag stays SET
        w_cfg(0, 2, 5);
        w_chen("00000001");
        wait until clk = '0';
        pbus.addr_periph <= std_logic_vector(to_unsigned(EVFAB_SLOT_FIRED, 6));
        pbus.write_data  <= x"00000001";
        pbus.wen         <= (others => '0');
        pbus.en_mem      <= '0';
        -- The action path applies the clear on the THIRD edge of the select
        -- window (2 sync + 1 apply, D5 / diagram C), so the fire must be
        -- driven into the cycle BEFORE that edge to land on it -- the same
        -- alignment the held-W1C leg of G6 uses. Driven one edge earlier the
        -- flag is set at edge 2 and legitimately cleared at edge 3, which
        -- tests nothing about set-wins.
        wait until clk = '1';    -- edge 1: select window open
        wait until clk = '1';    -- edge 2: the clear pulse fires within this window
        ev_in(2) <= '1';         -- fire lands on the SAME edge as the clear
        wait until clk = '1';    -- edge 3: set-wins edge
        ev_in(2) <= '0';
        wait until clk = '1';    -- edge 4
        wait until clk = '0';
        pbus.en_mem <= '1';
        pbus.wen    <= (others => '1');
        evfab_settle(clk);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_FIRED, rdw);
        sb.check_bit("G7: set-wins -- FIRED(0) stays SET when a fire aligns with its own W1C",
                     to_X01(rdw(0)), '1');
        w1c_fired("00000001");

        -- out-of-range EVSEL: 31 (NONE) and 20 (reserved) never fire
        w_cfg(0, 31, 5);
        check_no_fire_all_events(5);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_FIRED, rdw);
        sb.check_bit("G7: EVSEL=31(NONE) never fires (FIRED(0) stays 0)", to_X01(rdw(0)), '0');

        w_cfg(0, 20, 5);
        check_no_fire_all_events(5);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_FIRED, rdw);
        sb.check_bit("G7: EVSEL=20(reserved) never fires (FIRED(0) stays 0)", to_X01(rdw(0)), '0');

        -- out-of-range TASKSEL (corner 5): FIRED sets, no pulse, no OVR
        w_cfg(0, 2, 13);
        fire_event(2);
        for t in 0 to EVFAB_N_TASK - 1 loop
            sb.check_bit("G7 corner5: task_pulse(" & integer'image(t) &
                         ") stays low, TASKSEL out-of-range", to_X01(task_pulse(t)), '0');
        end loop;
        clear_event(2);
        wait_n(1);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_FIRED, rdw);
        sb.check_bit("G7 corner5: FIRED(0) sets despite the out-of-range TASKSEL",
                     to_X01(rdw(0)), '1');
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_OVR, rdw);
        sb.check_bit("G7 corner5: OVR(0) stays 0 (no task line to overrun)", to_X01(rdw(0)), '0');
        w1c_fired("00000001");

        -- SR.FIREDIF drops only when the LAST FIRED bit is cleared
        w_cfg(0, 2, 0);
        w_cfg(1, 3, 1);
        w_chen("00000011");
        fire_event(2); wait_n(1);
        fire_event(3); wait_n(1);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_SR, rdw);
        sb.check_bit("G7: FIREDIF=1 with two FIRED bits set", to_X01(rdw(EVFAB_SR_FIREDIF)), '1');
        w1c_fired("00000001");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_SR, rdw);
        sb.check_bit("G7: FIREDIF stays 1 -- one FIRED bit remains", to_X01(rdw(EVFAB_SR_FIREDIF)), '1');
        w1c_fired("00000010");
        evfab_settle(clk);   -- D5 GATE CLOSURE FIX: action-visibility (3 clk) before the check
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_SR, rdw);
        sb.check_bit("G7: FIREDIF drops only once the LAST bit clears", to_X01(rdw(EVFAB_SR_FIREDIF)), '0');

        -- SR.OVRIF drops only when the LAST OVR bit is cleared
        w_cfg(0, 2, 4);
        w_cfg(1, 2, 4);   -- same event, same task -> merge, OVR on both
        fire_event(2); wait_n(1);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_OVR, rdw);
        sb.check_slv("G7 OVRIF setup: OVR = 0x03 (merge on both)", rdw(7 downto 0), x"03");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_SR, rdw);
        sb.check_bit("G7: OVRIF=1 with two OVR bits set", to_X01(rdw(EVFAB_SR_OVRIF)), '1');
        w1c_ovr("00000001");
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_SR, rdw);
        sb.check_bit("G7: OVRIF stays 1 -- one OVR bit remains", to_X01(rdw(EVFAB_SR_OVRIF)), '1');
        w1c_ovr("00000010");
        evfab_settle(clk);   -- D5 GATE CLOSURE FIX: action-visibility (3 clk) before the check
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_SR, rdw);
        sb.check_bit("G7: OVRIF drops only once the LAST bit clears", to_X01(rdw(EVFAB_SR_OVRIF)), '0');
        w1c_fired("00000011");

        ------------------------------------------------------------------
        -- GROUP G8: task_busy -> OVR while the pulse is still emitted
        ------------------------------------------------------------------
        report "=== GROUP G8: task_busy -> OVR while the pulse is still emitted ===" severity note;
        do_reset;
        w_cr('1');
        w_cfg(0, 2, 4);
        w_chen("00000001");

        -- busy held, channel targeting t fires -> pulse STILL asserts, OVR sets
        task_busy(4) <= '1';
        wait_n(2);
        fire_event(2);
        sb.check_bit("G8: task_pulse(4) still asserts despite task_busy(4)=1 (never suppressed)",
                     to_X01(task_pulse(4)), '1');
        clear_event(2);
        wait_n(1);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_OVR, rdw);
        sb.check_bit("G8: OVR(0) sets from a busy consumer", to_X01(rdw(0)), '1');
        w1c_ovr("00000001");
        w1c_fired("00000001");

        -- drop busy -> no OVR on the next fire
        task_busy(4) <= '0';
        wait_n(2);
        fire_event(2);
        sb.check_bit("G8: task_pulse(4) fires with busy dropped", to_X01(task_pulse(4)), '1');
        clear_event(2);
        wait_n(1);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_OVR, rdw);
        sb.check_bit("G8: OVR(0) stays 0 once busy is dropped", to_X01(rdw(0)), '0');
        w1c_fired("00000001");

        -- busy on a DIFFERENT task -> no OVR
        task_busy(5) <= '1';
        wait_n(2);
        fire_event(2);
        sb.check_bit("G8: task_pulse(4) fires", to_X01(task_pulse(4)), '1');
        clear_event(2);
        wait_n(1);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_OVR, rdw);
        sb.check_bit("G8: OVR(0) stays 0, busy is on a different task (5)", to_X01(rdw(0)), '0');
        task_busy(5) <= '0';
        w1c_fired("00000001");

        -- busy + merge collision -> OVR on ALL colliding channels
        w_cfg(1, 2, 4);
        w_chen("00000011");
        task_busy(4) <= '1';
        wait_n(2);
        fire_event(2);
        sb.check_bit("G8: task_pulse(4) fires (merged + busy)", to_X01(task_pulse(4)), '1');
        clear_event(2);
        wait_n(1);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_OVR, rdw);
        sb.check_slv("G8: OVR = 0x03, both merging channels marked overrun", rdw(7 downto 0), x"03");
        task_busy(4) <= '0';
        w1c_ovr("00000011");
        w1c_fired("00000011");

        -- busy on an untargeted task -> nothing
        w_chen("00000001");
        task_busy(7) <= '1';
        wait_n(2);
        fire_event(2);
        sb.check_bit("G8: task_pulse(4) fires normally", to_X01(task_pulse(4)), '1');
        clear_event(2);
        wait_n(1);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_OVR, rdw);
        sb.check_bit("G8: OVR(0) stays 0, busy is on an untargeted task (7)", to_X01(rdw(0)), '0');
        task_busy(7) <= '0';
        w1c_fired("00000001");

        ------------------------------------------------------------------
        -- GROUP G9: X-collapse + gated-ClkMem autonomy + reset-mid-traffic
        -- (leg 1 RE-SCOPED per the D25 GATE CLOSURE / FABLE ruling: silicon-
        -- meaningful properties only -- input-line X never reaches
        -- task_pulse/FIRED/OVR/rdata_out, plus the GPIO0-mask absorption on
        -- EVSTAT(15); the metavalue-config-register leg and the sacrificial
        -- own-EVSTAT-bit value check are gone, see the leg 1a/1b comments)
        ------------------------------------------------------------------
        report "=== GROUP G9: X-collapse + gated-ClkMem autonomy + reset-mid-traffic ===" severity note;

        -- leg 1a REMOVED (D25 GATE CLOSURE / FABLE RULING, G9-1 re-scope): the
        -- original leg drove a metavalue 'XXXXX' straight into CHnCFG.EVSEL
        -- and swept every event asserting the channel never fires. A real
        -- config flop never holds X in silicon (D11's "X in a select field is
        -- inert" is scoped to RTL-simulation robustness, not a silicon
        -- claim), so this was X-optimism overstating what gate/SDF sim can
        -- prove -- all 17 of its checks (this loop + the FIRED/OVR-clean
        -- follow-ups) failed at gate. Reserved-code inertness on real
        -- synthesizable hardware is already covered, and DOES pass at gate,
        -- by G7's EVSEL=20 (reserved) and TASKSEL=13 (>= N_TASK) legs
        -- (verified: both are ordinary determinate-value writes, no
        -- metavalue involved, and both PASSED unmodified at SDF gate sim) --
        -- no coverage gap from removing this leg.

        -- leg 1b: X/Z/U on an UNSELECTED ev_in bit, and on an UNMASKED
        -- gpio0_evin bit -> no X reaches task_pulse/FIRED/OVR/rdata_out
        -- (these four assertions PASSED at gate). RE-SCOPED (G9-1): no value
        -- check is made on EVSTAT as a whole, because the X-driven line's OWN
        -- EVSTAT bit (EVSTAT(5), fed directly by ev_in(5)) is SACRIFICIAL by
        -- design -- EVSTAT is ungated (D14) and legitimately reads X at gate.
        -- EVSTAT(15) stays checked: it is reached only through the GPIO0
        -- AND-before-OR mask (D10), which DOES absorb the X and pass at gate.
        do_reset;
        w_cr('1');
        w_cfg(0, 2, 3);
        w_chen("00000001");
        w_gpiomask("00000000");     -- GPIO0 fully masked off
        ev_in(5) <= 'X';            -- unselected line (CH0 only selects EV2)
        gpio0_evin(0) <= 'X';       -- unmasked (mask bit0=0) GPIO0 pad
        wait_n(4);
        fire_event(2);
        sb.check_bit("G9-1b: task_pulse(3) fires cleanly despite X on an unselected line",
                     to_X01(task_pulse(3)), '1');
        sb.check_true("G9-1b: task_pulse vector carries no X", not is_x(task_pulse));
        clear_event(2);
        wait_n(1);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_FIRED, rdw);
        sb.check_true("G9-1b: FIRED carries no X", not is_x(rdw));
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_OVR, rdw);
        sb.check_true("G9-1b: OVR carries no X", not is_x(rdw));
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_EVSTAT, rdw);
        sb.check_bit("G9-1b: EVSTAT(15) stays 0 (GPIO0 masked off, X absorbed before the OR-reduce)",
                     to_X01(rdw(EVFAB_EV_GPIO_IDX)), '0');
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_CR, rdw);
        sb.check_true("G9-1b: rdata_out carries no X", not is_x(rdw));
        ev_in(5) <= '0';
        gpio0_evin(0) <= '0';
        w1c_fired("00000001");
        w1c_evstat("0000000000000100");

        -- leg 1c: 'X' on an untargeted task_busy bit -> OVR clean
        task_busy(9) <= 'X';        -- CH0 targets task3, not task9
        wait_n(2);
        fire_event(2);
        clear_event(2);
        wait_n(1);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_OVR, rdw);
        sb.check_true("G9-1c: OVR clean (no X) with an X on an untargeted task_busy bit",
                     not is_x(rdw) and to_X01(rdw(0)) = '0');
        task_busy(9) <= '0';
        w1c_fired("00000001");

        -- leg 2: gated-ClkMem autonomy -- freeze ClkMem (no bus access) for
        -- ~500 clk while driving events; pulses keep firing on schedule and
        -- FIRED/OVR/EVSTAT keep accumulating; re-open the bus and read back
        -- = shadow model. (If any fabric state were on ClkMem, this leg
        -- would read zeros -- a built-in negative control, D1/D2.)
        do_reset;
        w_cr('1');
        evfab_shadow_set_cr_en(sh, '1');
        w_chen("00000001");
        evfab_shadow_set_chen(sh, "00000001");
        w_cfg(0, 2, 3);
        evfab_shadow_set_cfg(sh, 0, 2, 3);
        evfab_settle(clk);

        edges0 := clkmem_edge_count;
        g9_mismatches := 0;
        for i in 1 to 500 loop
            lfsr_step(lfsr24);
            wait until clk = '0';
            ev_in        <= (others => '0');
            ev_in(2)     <= lfsr24(0);
            wait until clk = '1';
            evfab_shadow_tick(sh, ev_in, gpio0_evin, task_busy, tp_exp);
            if to_X01(task_pulse(3)) /= tp_exp(3) then
                g9_mismatches := g9_mismatches + 1;
            end if;
        end loop;
        sb.check_true("G9-2: task_pulse(3) tracked the shadow model for the whole " &
                      "500-cycle frozen-ClkMem window", g9_mismatches = 0);
        sb.check_true("G9-2: ClkMem had ZERO edges during the window (D1/D2 negative control)",
                      clkmem_edge_count = edges0);

        ev_in <= (others => '0');
        evfab_settle(clk);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_FIRED, rdw);
        sb.check_slv("G9-2: FIRED readback after re-opening the bus matches the shadow model",
                     rdw(EVFAB_N_CH - 1 downto 0), sh.fired);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_OVR, rdw);
        sb.check_slv("G9-2: OVR readback matches the shadow model", rdw(EVFAB_N_CH - 1 downto 0), sh.ovr);
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_EVSTAT, rdw);
        sb.check_slv("G9-2: EVSTAT readback matches the shadow model",
                     rdw(EVFAB_N_EV - 1 downto 0), sh.evstat);

        -- leg 3: reset mid-traffic
        do_reset;
        w_cr('1');
        w_chen("00000001");
        w_cfg(0, 4, 3);       -- T-mode event 4
        wait until clk = '1';
        ev_in(4) <= '1';      -- start a toggle, leave it asserted
        wait_n(1);
        resetn <= '0';        -- reset lands mid-flight
        wait_n(4);
        for tt in 0 to EVFAB_N_TASK - 1 loop
            sb.check_bit("G9-3: task_pulse(" & integer'image(tt) & ") clean 0 during reset (no glitch)",
                         to_X01(task_pulse(tt)), '0');
        end loop;
        resetn <= '1';
        wait_n(8);
        for tt in 0 to EVFAB_N_TASK - 1 loop
            sb.check_bit("G9-3: task_pulse(" & integer'image(tt) & ") stays 0 after release " &
                         "(T input left HIGH across reset -> no phantom pulse)",
                         to_X01(task_pulse(tt)), '0');
        end loop;

        -- fabric fires correctly again after reconfiguration
        w_cr('1');
        w_chen("00000001");
        w_cfg(0, 4, 3);
        ev_in(4) <= '0';
        wait_n(4);
        ev_in(4) <= '1';
        wait_n(4);      -- T latency 3, observed one edge later (SAMPLE-POINT)
        sb.check_bit("G9-3: fabric fires correctly again after reconfiguration",
                     to_X01(task_pulse(3)), '1');
        ev_in(4) <= '0';
        wait_n(1);
        w1c_fired("00000001");

        ------------------------------------------------------------------
        -- GROUP G10: input modes
        ------------------------------------------------------------------
        report "=== GROUP G10: input modes ===" severity note;
        do_reset;
        w_cr('1');
        w_chen("00000001");

        -- T-mode (EV4)
        w_cfg(0, 4, 7);
        wait until clk = '1';
        ev_in(4) <= '1';                       -- 0->1
        wait_n(4);
        sb.check_bit("G10 T: 0->1 fires one pulse", to_X01(task_pulse(7)), '1');
        wait_n(1);
        sb.check_bit("G10 T: pulse is exactly one clk wide", to_X01(task_pulse(7)), '0');
        wait_n(5);
        sb.check_bit("G10 T: holding high produces no further pulse", to_X01(task_pulse(7)), '0');
        wait until clk = '1';
        ev_in(4) <= '0';                       -- 1->0
        wait_n(4);
        sb.check_bit("G10 T: 1->0 also fires one pulse", to_X01(task_pulse(7)), '1');
        wait_n(1);
        sb.check_bit("G10 T: falling pulse is exactly one clk wide", to_X01(task_pulse(7)), '0');
        w1c_fired("00000001");

        -- a flip narrower than 2 clk still delivered (toggle, not level):
        -- both the rise and the fall are individually caught.
        wait until clk = '1';
        ev_in(4) <= '1';
        wait until clk = '1';
        ev_in(4) <= '0';
        pulse_cnt := 0;
        for i in 1 to 8 loop
            wait until clk = '1';
            if to_X01(task_pulse(7)) = '1' then
                pulse_cnt := pulse_cnt + 1;
            end if;
        end loop;
        sb.check_true("G10 T: a flip narrower than 2 clk still delivers both edges (2 pulses)",
                      pulse_cnt = 2);
        w1c_fired("00000001");

        -- L-mode (EV13)
        w_cfg(0, 13, 7);
        ev_in(13) <= '0';
        wait_n(4);
        wait until clk = '1';
        ev_in(13) <= '1';                      -- rising
        wait_n(4);
        sb.check_bit("G10 L: rising fires one pulse", to_X01(task_pulse(7)), '1');
        wait_n(1);
        sb.check_bit("G10 L: pulse is exactly one clk wide", to_X01(task_pulse(7)), '0');
        wait_n(5);
        sb.check_bit("G10 L: held high produces no further pulse", to_X01(task_pulse(7)), '0');
        wait until clk = '1';
        ev_in(13) <= '0';                      -- falling
        wait_n(4);
        sb.check_bit("G10 L: falling edge never fires", to_X01(task_pulse(7)), '0');
        wait until clk = '1';
        ev_in(13) <= '1';                      -- re-rise
        wait_n(4);
        sb.check_bit("G10 L: re-rise fires one pulse", to_X01(task_pulse(7)), '1');
        wait_n(1);
        ev_in(13) <= '0';
        wait_n(4);
        w1c_fired("00000001");

        -- P-mode (EV2)
        w_cfg(0, 2, 7);
        fire_event(2);
        sb.check_bit("G10 P: 1-clk pulse fires one pulse", to_X01(task_pulse(7)), '1');
        clear_event(2);
        wait_n(1);
        sb.check_bit("G10 P: pulse is exactly one clk wide", to_X01(task_pulse(7)), '0');
        w1c_fired("00000001");

        -- (contract-violating) 2-clk P input -> two pulses (D9 contract visible)
        -- ev_in(2) is held across exactly TWO rising edges; the checks sit one
        -- edge later than the fires they observe (SAMPLE-POINT CONTRACT).
        wait until clk = '1';
        ev_in(2) <= '1';
        wait until clk = '1';
        wait until clk = '1';
        sb.check_bit("G10 P: 2-clk pulse -- 1st cycle fires", to_X01(task_pulse(7)), '1');
        ev_in(2) <= '0';
        wait until clk = '1';
        sb.check_bit("G10 P: 2-clk pulse -- 2nd cycle ALSO fires (contract violation visible)",
                     to_X01(task_pulse(7)), '1');
        wait until clk = '1';
        sb.check_bit("G10 P: pulse train ends after the held duration", to_X01(task_pulse(7)), '0');
        w1c_fired("00000001");

        -- GPIO0 (event 15)
        w_cfg(0, 15, 7);
        w_gpiomask("00000000");
        for g in 0 to 7 loop
            fire_gpio(g);
            sb.check_bit("G10 GPIO0: bit " & integer'image(g) &
                         " inert while EVGPIOMASK=0 (no event 15)", to_X01(task_pulse(7)), '0');
            clear_gpio(g);
            wait_n(1);
        end loop;
        bus_read(clk, pbus, rdata_out, EVFAB_SLOT_EVSTAT, rdw);
        sb.check_bit("G10 GPIO0: EVSTAT(15) stays 0, mask fully off",
                     to_X01(rdw(EVFAB_EV_GPIO_IDX)), '0');

        -- one bit masked in -> only that pad's rising edge fires
        w_gpiomask("00000001");
        fire_gpio(0);
        sb.check_bit("G10 GPIO0: bit0 (masked in) rising edge fires", to_X01(task_pulse(7)), '1');
        clear_gpio(0);
        wait_n(1);
        w1c_fired("00000001");
        fire_gpio(1);
        sb.check_bit("G10 GPIO0: bit1 (unmasked) rising edge does NOT fire", to_X01(task_pulse(7)), '0');
        clear_gpio(1);
        wait_n(1);

        -- several masked in and rising the same clk -> ONE event-15 pulse
        w_gpiomask("00000011");
        gpio0_evin(0) <= '0';
        gpio0_evin(1) <= '0';
        wait_n(4);
        wait until clk = '1';
        gpio0_evin(0) <= '1';
        gpio0_evin(1) <= '1';
        wait_n(4);
        sb.check_bit("G10 GPIO0: two masked-in bits rising the same clk -> ONE event-15 pulse",
                     to_X01(task_pulse(7)), '1');
        wait_n(1);
        sb.check_bit("G10 GPIO0: merged GPIO0 pulse is exactly one clk wide", to_X01(task_pulse(7)), '0');
        gpio0_evin(0) <= '0';
        gpio0_evin(1) <= '0';
        wait_n(1);
        w1c_fired("00000001");

        -- falling edges never fire
        wait_n(4);
        wait until clk = '1';
        gpio0_evin(0) <= '1';
        wait_n(3);
        clear_gpio(0);
        wait_n(3);
        sb.check_bit("G10 GPIO0: falling edge never fires", to_X01(task_pulse(7)), '0');
        w1c_fired("00000001");

        -- ev_in(15) ignored entirely
        w_gpiomask("00000000");
        ev_in(15) <= '1';
        wait_n(4);
        sb.check_bit("G10 GPIO0: ev_in(15) is ignored entirely", to_X01(task_pulse(7)), '0');
        ev_in(15) <= '0';
        w1c_fired("00000001");
        w1c_evstat("1000000000000000");

        ------------------------------------------------------------------
        -- GROUP G-NEG: NEGATIVE CONTROL (mandatory, LAST) -- exactly ONE
        -- deliberately-wrong expected value.
        ------------------------------------------------------------------
        report "=== GROUP G-NEG: NEGATIVE CONTROL ===" severity note;
        do_reset;
        w_cr('1');
        w_chen("00000001");
        w_cfg(0, 2, 3);
        fire_event(2);
        sb.check_bit("G-NEG setup: task_pulse(3) fires as expected", to_X01(task_pulse(3)), '1');
        sb.check_bit("NEGATIVE CONTROL: expect task_pulse on the WRONG task index (must FAIL)",
                     to_X01(task_pulse(4)), '1');
        clear_event(2);
        wait_n(1);
        w1c_fired("00000001");

        ------------------------------------------------------------------
        -- Final verdict: sb.errors must be EXACTLY 1 (the negative control).
        ------------------------------------------------------------------
        wait for 1 us;
        sb.report_summary("EVFAB TB");

        if sb.errors = 1 then
            report LF & LF &
                "    ##################################################" & LF &
                "    ##   EVFAB_TB PASS (1 expected negative-control failure)" & LF &
                "    ##   EVFAB TB:  ALL CHECKS PASSED" & LF &
                "    ##################################################" & LF
                severity note;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   EVFAB_TB FAIL (expected exactly 1 failure [negative control], got " &
                integer'image(sb.errors) & ")" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        tb_done <= true;
        stop;
        wait;

    end process stim_proc;

end architecture sim;
