-------------------------------------------------------------------------------
-- harvest_supply_model_tb.vhd
-------------------------------------------------------------------------------
-- Self-checking bench for harvest_supply_model (a bq25570-class harvesting PMIC) and its companion supply_supervisor.
-- The pair drives the field-power PGOOD input on package pin 69 / P6.7, which feeds pwr_ctrl.pgood_pad.
-- Compile after periph_tb_pkg.vhd and harvest_supply_model.vhd; run xcelium/cots_test/harvest_supply/run_harvest_supply.sh.
-- Groups: G-INIT discharged board, G-COLD cold start to regulation, G-SIZE supercap sizing, G-BROWN droop and recover, G-UV VBAT_UV load shed, G-RAMP receiver chatter on a slow ramp, G-NEG negative control.
-- The bench never touches pwr_ctrl; with NEGCTRL set, exactly 1 tallied failure is the PASS condition.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.periph_tb_pkg.all;

entity harvest_supply_model_tb is
    generic (
        -- Selects the deliberately-wrong expectation; clear it to run the bench as a pure pass.
        NEGCTRL : boolean := true
    );
end entity harvest_supply_model_tb;


architecture tb of harvest_supply_model_tb is

    shared variable sb : scoreboard;

    function n2s(n : integer) return string is
    begin
        return integer'image(n);
    end function;

    ---------------------------------------------------------------------
    -- G-COLD / G-BROWN / G-RAMP / G-SIZE stimulus + observation nets
    ---------------------------------------------------------------------
    -- u_cold : realistic board, 4.7 uF CSTOR, supercap-free, buck at 3.3 V for the I/O rail and a companion switcher at 1.0 V for the core.
    -- The split is forced by the bq25570 buck's 1.3 V floor.
    signal cd_vin, cd_iin, cd_la, cd_lb : natural := 0;
    signal cd_vstor, cd_vout, cd_vaux, cd_okmv : natural;
    signal cd_ok, cd_cs, cd_chg, cd_ov, cd_ilim : std_logic;
    signal cd_pgood : std_logic;

    -- u_size1 / u_size2 : the sizing experiment, idealized on purpose (dropout and the VBAT_UV load shed disabled) so it reproduces the plain arithmetic.
    -- The part's real behavior is checked in the same group as an arithmetic comparison.
    signal sz_la : natural := 0;
    signal s1_vstor, s1_estor, s1_eload : natural;
    signal s2_vstor : natural;

    -- u_brown : 100 uF buffer, 1.8 V system rail, datasheet-default battery management thresholds.
    signal br_vin, br_iin, br_la : natural := 0;
    signal br_vstor, br_okmv, br_vout : natural;
    signal br_ok, br_uv : std_logic;
    signal br_pgood : std_logic;

    -- u_ramp : 10 uF charged slowly through a supervisor threshold, with converter ripple riding on it.
    signal rp_vin, rp_iin : natural := 0;
    signal rp_vstor : natural;
    signal pg_a, pg_b, pg_c : std_logic;

    -- PGOOD edge counters and their arming controls
    signal ramp_arm : std_logic := '0';
    signal br_arm   : std_logic := '0';
    signal n_a, n_b, n_c, n_br : natural := 0;

    -- G-RAMP supervisor settings, shared so the three differ in ONE knob only
    constant RAMP_VTH   : natural := 2550;
    constant RAMP_NOISE : natural := 20;
    constant RAMP_SEED  : natural := 16#BEEF#;

begin

    ---------------------------------------------------------------------
    -- DUT instances
    ---------------------------------------------------------------------
    u_cold : entity work.harvest_supply_model
        generic map (
            TICK_PERIOD     => 10 us,
            CAP_UF          => 4.7,        -- datasheet CSTOR
            V_INIT_MV       => 0,
            VOUT_A_MV       => 3300,       -- bq25570 buck, Castalia 3.3 V I/O rail
            VOUT_B_MV       => 1000,       -- companion switcher, 1.0 V core rail
            AUX_IS_LDO      => false,
            AUX_EFF_PCT     => 85,
            VBAT_OV_MV      => 4200,
            VBAT_OK_PROG_MV => 2400,
            VBAT_OK_HYST_MV => 2800
        )
        port map (
            vin_mv      => cd_vin,
            iin_ua      => cd_iin,
            load_ua     => cd_la,
            load_aux_ua => cd_lb,
            vstor_mv    => cd_vstor,
            vout_mv     => cd_vout,
            vout_aux_mv => cd_vaux,
            vbat_ok     => cd_ok,
            vbat_ok_mv  => cd_okmv,
            cold_start  => cd_cs,
            charging    => cd_chg,
            ov          => cd_ov,
            uv          => open,
            ilim        => cd_ilim,
            e_in_uj     => open,
            e_load_uj   => open,
            e_stor_uj   => open
        );

    -- Castalia's receiving pad: Vih of a 3.3 V CMOS input, no Schmitt.
    sup_cold : entity work.supply_supervisor
        generic map (V_RISE_MV => 2000, V_HYST_MV => 0)
        port map (vsense_mv => cd_okmv, pgood => cd_pgood);

    u_size1 : entity work.harvest_supply_model
        generic map (
            TICK_PERIOD     => 10 us,
            CAP_UF          => 1000.0,     -- the project's 1 mF supercap target
            V_INIT_MV       => 2500,
            VOUT_A_MV       => 1800,
            VDROP_MV        => 0,          -- idealized
            BUCK_EFF_PCT    => 80,
            VBAT_UV_MV      => 1000,       -- idealized: no load shed
            VBAT_OK_PROG_MV => 1000,
            VBAT_OK_HYST_MV => 1100,
            VBAT_OV_MV      => 5000,
            IQ_NA           => 0           -- idealized: pure arithmetic
        )
        port map (
            load_ua   => sz_la,
            vstor_mv  => s1_vstor,
            vout_mv   => open, vout_aux_mv => open,
            vbat_ok   => open, vbat_ok_mv  => open,
            cold_start => open, charging => open, ov => open, uv => open,
            ilim      => open,
            e_in_uj   => open,
            e_load_uj => s1_eload,
            e_stor_uj => s1_estor
        );

    u_size2 : entity work.harvest_supply_model
        generic map (
            TICK_PERIOD     => 10 us,
            CAP_UF          => 500.0,      -- the analytic minimum, to the mV
            V_INIT_MV       => 2500,
            VOUT_A_MV       => 1800,
            VDROP_MV        => 0,
            BUCK_EFF_PCT    => 80,
            VBAT_UV_MV      => 1000,
            VBAT_OK_PROG_MV => 1000,
            VBAT_OK_HYST_MV => 1100,
            VBAT_OV_MV      => 5000,
            IQ_NA           => 0
        )
        port map (
            load_ua   => sz_la,
            vstor_mv  => s2_vstor,
            vout_mv   => open, vout_aux_mv => open,
            vbat_ok   => open, vbat_ok_mv  => open,
            cold_start => open, charging => open, ov => open, uv => open,
            ilim      => open,
            e_in_uj   => open, e_load_uj => open, e_stor_uj => open
        );

    u_brown : entity work.harvest_supply_model
        generic map (
            TICK_PERIOD     => 10 us,
            CAP_UF          => 100.0,
            V_INIT_MV       => 3000,
            VOUT_A_MV       => 1800,
            VOUT_B_MV       => 1000,
            AUX_IS_LDO      => false,
            VBAT_OV_MV      => 4200,
            VBAT_OK_PROG_MV => 2400,
            VBAT_OK_HYST_MV => 2800
        )
        port map (
            vin_mv     => br_vin,
            iin_ua     => br_iin,
            load_ua    => br_la,
            vstor_mv   => br_vstor,
            vout_mv    => br_vout,
            vout_aux_mv => open,
            vbat_ok    => br_ok,
            vbat_ok_mv => br_okmv,
            cold_start => open, charging => open, ov => open,
            uv         => br_uv,
            ilim       => open,
            e_in_uj    => open, e_load_uj => open, e_stor_uj => open
        );

    -- Same receiver model as u_cold's, but with 200 mV of pad hysteresis.
    sup_brown : entity work.supply_supervisor
        generic map (V_RISE_MV => 2000, V_HYST_MV => 200)
        port map (vsense_mv => br_okmv, pgood => br_pgood);

    u_ramp : entity work.harvest_supply_model
        generic map (
            TICK_PERIOD     => 10 us,
            CAP_UF          => 10.0,
            V_INIT_MV       => 2400,
            RIPPLE_MV       => 30,         -- Table 6.6 buck ripple, 30 mVpp
            VOUT_A_MV       => 1800,
            VBAT_UV_MV      => 1000,
            VBAT_OK_PROG_MV => 1000,
            VBAT_OK_HYST_MV => 1100,
            VBAT_OV_MV      => 5000
        )
        port map (
            vin_mv     => rp_vin,
            iin_ua     => rp_iin,
            vstor_mv   => rp_vstor,
            vout_mv    => open, vout_aux_mv => open,
            vbat_ok    => open, vbat_ok_mv  => open,
            cold_start => open, charging => open, ov => open, uv => open,
            ilim       => open,
            e_in_uj    => open, e_load_uj => open, e_stor_uj => open
        );

    -- A: the pessimistic real receiver, no hysteresis and no filter.
    sup_a : entity work.supply_supervisor
        generic map (V_RISE_MV => RAMP_VTH, V_HYST_MV => 0,
                     VNOISE_MV => RAMP_NOISE, NOISE_SEED => RAMP_SEED)
        port map (vsense_mv => rp_vstor, pgood => pg_a);

    -- B: candidate fix 1, hysteresis wider than ripple plus noise.
    sup_b : entity work.supply_supervisor
        generic map (V_RISE_MV => RAMP_VTH, V_HYST_MV => 100,
                     VNOISE_MV => RAMP_NOISE, NOISE_SEED => RAMP_SEED)
        port map (vsense_mv => rp_vstor, pgood => pg_b);

    -- C: candidate fix 2, de-glitch longer than the crossing takes.
    sup_c : entity work.supply_supervisor
        generic map (V_RISE_MV => RAMP_VTH, V_HYST_MV => 0,
                     T_ASSERT => 3 ms, T_DEASSERT => 3 ms,
                     VNOISE_MV => RAMP_NOISE, NOISE_SEED => RAMP_SEED)
        port map (vsense_mv => rp_vstor, pgood => pg_c);

    ---------------------------------------------------------------------
    -- edge counters (armed by the bench so earlier groups cannot pollute)
    ---------------------------------------------------------------------
    cnt_a : process (pg_a, ramp_arm)
    begin
        if ramp_arm = '0' then
            n_a <= 0;
        elsif pg_a'event then
            n_a <= n_a + 1;
        end if;
    end process cnt_a;

    cnt_b : process (pg_b, ramp_arm)
    begin
        if ramp_arm = '0' then
            n_b <= 0;
        elsif pg_b'event then
            n_b <= n_b + 1;
        end if;
    end process cnt_b;

    cnt_c : process (pg_c, ramp_arm)
    begin
        if ramp_arm = '0' then
            n_c <= 0;
        elsif pg_c'event then
            n_c <= n_c + 1;
        end if;
    end process cnt_c;

    -- The G-BROWN counter watches the brownout supervisor, not the G-RAMP trio.
    cnt_br : process (br_pgood, br_arm)
    begin
        if br_arm = '0' then
            n_br <= 0;
        elsif br_pgood'event then
            n_br <= n_br + 1;
        end if;
    end process cnt_br;

    ---------------------------------------------------------------------
    -- stimulus / checks
    ---------------------------------------------------------------------
    stim : process
        variable t0, t1  : time;
        variable lag_us  : integer;
        variable ok      : boolean;
        variable e_j     : real;
        variable c_ideal : real;
        variable c_real  : real;
        variable v_hold  : natural;
        variable exp_err : natural;
    begin
        ---------------------------------------------------------------
        report "G-INIT: discharged board";
        ---------------------------------------------------------------
        wait for 100 us;
        sb.check_true("G-INIT u_cold cold_start asserted (VSTOR = 0)", cd_cs = '1');
        sb.check_true("G-INIT u_cold vstor = 0 mV, got " & n2s(cd_vstor),
                      cd_vstor = 0);
        sb.check_true("G-INIT u_cold vbat_ok deasserted", cd_ok = '0');
        sb.check_true("G-INIT u_cold PGOOD deasserted", cd_pgood = '0');

        ---------------------------------------------------------------
        report "G-COLD: cold start, boost takeover, VBAT_OK, rails, OV, ilim";
        ---------------------------------------------------------------
        -- 500 mV is below VIN(CS) = 600 mV, while 2.5 mW is 166x the 15 uW PIN(CS) floor: voltage is the gate here, not power.
        cd_vin <= 500;
        cd_iin <= 5000;
        wait for 5 ms;
        sb.check_true("G-COLD no charge below VIN(CS) despite 2.5 mW offered, "
                      & "vstor = " & n2s(cd_vstor) & " mV", cd_vstor = 0);
        sb.check_true("G-COLD charging deasserted below VIN(CS)", cd_chg = '0');

        -- at VIN(CS) the cold-start pump engages
        t0 := now;
        cd_vin <= 600;
        wait for 100 us;
        sb.check_true("G-COLD charging asserted at VIN(CS) = 600 mV", cd_chg = '1');
        sb.check_true("G-COLD still in cold start", cd_cs = '1');

        -- VSTOR(CHGEN) = 1730 mV ends cold start.
        -- Analytic budget: 0.5*4.7uF*1.73^2 = 7.03 uJ at 5% of 3 mW = 150 uW, so 46.9 ms.
        ok := true;
        if cd_cs /= '0' then
            wait until cd_cs = '0' for 120 ms;
            if cd_cs /= '0' then ok := false; end if;
        end if;
        t1 := now;
        sb.check_true("G-COLD cold start completes (VSTOR reaches VSTOR_CHGEN)", ok);
        lag_us := (t1 - t0) / 1 us;
        sb.check_true("G-COLD cold-start duration " & n2s(lag_us)
                      & " us within the 7.03 uJ / 150 uW budget [30000,60000]",
                      lag_us >= 30000 and lag_us <= 60000);
        sb.check_true("G-COLD VSTOR at cold-start exit >= 1730 mV, got "
                      & n2s(cd_vstor), cd_vstor >= 1730);

        -- main boost charger (80%) now runs; VBAT_OK asserts at 2800 mV
        ok := true;
        if cd_ok /= '1' then
            wait until cd_ok = '1' for 50 ms;
            if cd_ok /= '1' then ok := false; end if;
        end if;
        t0 := now;
        sb.check_true("G-COLD VBAT_OK asserts at the rising threshold", ok);
        sb.check_true("G-COLD VSTOR at VBAT_OK >= 2800 mV, got " & n2s(cd_vstor),
                      cd_vstor >= 2800);

        -- the flag PIN is VSTOR through ~20 kOhm (7.3.4): PGOOD lags
        ok := true;
        if cd_pgood /= '1' then
            wait until cd_pgood = '1' for 5 ms;
            if cd_pgood /= '1' then ok := false; end if;
        end if;
        t1 := now;
        lag_us := (t1 - t0) / 1 us;
        sb.check_true("G-COLD PGOOD follows VBAT_OK", ok);
        sb.check_true("G-COLD PGOOD lags VBAT_OK by " & n2s(lag_us)
                      & " us -- the 20 k / 10 nF flag-pin RC, expect [100,1000]",
                      lag_us >= 100 and lag_us <= 1000);

        -- charge on to the programmed overvoltage clamp
        ok := true;
        if cd_ov /= '1' then
            wait until cd_ov = '1' for 50 ms;
            if cd_ov /= '1' then ok := false; end if;
        end if;
        sb.check_true("G-COLD overvoltage clamp engages at VBAT_OV", ok);
        wait for 100 us;
        sb.check_true("G-COLD charger stops under OV", cd_chg = '0');
        sb.check_true("G-COLD buck rail regulates at 3300 mV, got " & n2s(cd_vout),
                      cd_vout >= 3295 and cd_vout <= 3305);
        sb.check_true("G-COLD companion rail regulates at 1000 mV, got "
                      & n2s(cd_vaux), cd_vaux >= 995 and cd_vaux <= 1005);

        -- buck peak output current is 110 mA (feature list); ask for 200 mA
        cd_la <= 200000;
        wait for 30 us;
        sb.check_true("G-COLD ilim flags a 200 mA demand on a 110 mA buck",
                      cd_ilim = '1');
        cd_la <= 0;
        wait for 50 us;
        sb.check_true("G-COLD ilim clears when the demand goes away", cd_ilim = '0');

        ---------------------------------------------------------------
        -- G-SIZE: 3333 uA on a 1.8 V rail is 6.00 mW of load, 7.50 mW out of storage at eta = 0.8, so 0.750 mJ per 100 ms transaction window.
        -- Closed form C_min = 2E / (Vhi^2 - Vlo^2); both instances start at 2500 mV, u_size1 at the 1 mF target and u_size2 at the 500 uF analytic minimum, which lands exactly on the 1.8 V floor.
        ---------------------------------------------------------------
        report "G-SIZE: supercap sizing";
        sz_la <= 3333;
        wait for 100 ms;
        sz_la <= 0;
        wait for 100 us;

        sb.check_true("G-SIZE energy out of storage = " & n2s(s1_estor)
                      & " uJ (documented 750 uJ)",
                      s1_estor >= 745 and s1_estor <= 755);
        sb.check_true("G-SIZE energy delivered to the load = " & n2s(s1_eload)
                      & " uJ (6.00 mW x 100 ms = 600 uJ)",
                      s1_eload >= 595 and s1_eload <= 605);
        sb.check_true("G-SIZE 1 mF ends at " & n2s(s1_vstor)
                      & " mV (closed form 2179 mV), well clear of the 1800 mV floor",
                      s1_vstor >= 2174 and s1_vstor <= 2184);
        sb.check_true("G-SIZE 500 uF ends at " & n2s(s2_vstor)
                      & " mV -- the analytic minimum lands ON the 1800 mV floor",
                      s2_vstor >= 1798 and s2_vstor <= 1808);

        e_j     := 0.75e-3;
        c_ideal := 2.0 * e_j / (2.5 * 2.5 - 1.8 * 1.8);
        c_real  := 2.0 * e_j / (2.5 * 2.5 - 2.0 * 2.0);
        report "G-SIZE closed form: C_min(2.5 V -> 1.8 V) = "
               & n2s(integer(c_ideal * 1.0e6)) & " uF; "
               & "C_min(2.5 V -> 2.0 V, the bq25570 floor) = "
               & n2s(integer(c_real * 1.0e6)) & " uF";
        sb.check_true("G-SIZE closed-form C_min for the documented 2.5->1.8 V "
                      & "droop is " & n2s(integer(c_ideal * 1.0e6))
                      & " uF, matching the simulated 500 uF result",
                      c_ideal >= 490.0e-6 and c_ideal <= 510.0e-6);
        -- The part will not let the storage node reach 1.8 V with a 1.8 V rail up: the buck needs VSTOR at or above VOUT + 0.2 V and VBAT_UV is internally set at 1.95 V, so the honest floor is 2.0 V.
        sb.check_true("G-SIZE 1 mF still covers the bq25570's REAL floor "
                      & "(2.0 V, needing " & n2s(integer(c_real * 1.0e6))
                      & " uF) -- but at 1.5x margin, not 2x",
                      1000.0e-6 >= c_real);

        ---------------------------------------------------------------
        report "G-BROWN: brownout and recover";
        ---------------------------------------------------------------
        br_arm <= '1';
        wait for 100 us;
        sb.check_true("G-BROWN precondition: PGOOD up on a charged buffer",
                      br_pgood = '1');
        sb.check_true("G-BROWN precondition: not in undervoltage", br_uv = '0');

        -- all-harts-awake, 12.3 mW on the 1.8 V rail, harvest absent
        br_la <= 6833;
        ok := true;
        wait until br_pgood = '0' for 60 ms;
        if br_pgood /= '0' then ok := false; end if;
        sb.check_true("G-BROWN PGOOD deasserts when the buffer droops", ok);
        sb.check_true("G-BROWN VBAT_OK deasserted at the falling threshold, "
                      & "vstor = " & n2s(br_vstor) & " mV (threshold 2400)",
                      br_ok = '0' and br_vstor <= 2450);

        -- harvest returns and the chip drops to its parked 5.45 mW draw
        br_la  <= 3028;
        br_vin <= 2000;
        br_iin <= 10000;
        ok := true;
        wait until br_pgood = '1' for 80 ms;
        if br_pgood /= '1' then ok := false; end if;
        sb.check_true("G-BROWN PGOOD re-asserts once the buffer recovers", ok);
        sb.check_true("G-BROWN VSTOR back above the rising threshold, got "
                      & n2s(br_vstor), br_vstor >= 2800);
        wait for 1 ms;
        sb.check_true("G-BROWN exactly 2 PGOOD edges over the cycle, got "
                      & n2s(n_br) & " -- no chatter at either crossing",
                      n_br = 2);
        br_la <= 0;

        ---------------------------------------------------------------
        -- G-UV: the VBAT_UV load shed. VBAT_UV is internally set at 1.95 V typ and is not programmable, so it must be exercised, not merely configured.
        -- Every check pins the threshold value in one direction or the other: UV asserts at 1950 mV shedding rail A, the storage node then holds under an unchanged 12.3 mW demand, and UV clears 15 mV higher by VBAT_UV_HYST.
        ---------------------------------------------------------------
        report "G-UV: VBAT_UV load shed and its 15 mV rising hysteresis";
        br_vin <= 0;
        br_iin <= 0;
        br_la  <= 6833;                 -- all-harts-awake, 12.3 mW, no harvest

        -- checkpoint ABOVE VBAT_UV: still regulating, nothing shed
        wait until br_vstor <= 2150 for 60 ms;
        sb.check_true("G-UV at " & n2s(br_vstor) & " mV (above VBAT_UV = 1950) "
                      & "the rails are still up and UV is clear, vout = "
                      & n2s(br_vout) & " mV",
                      br_uv = '0' and br_vout >= 1795 and br_vout <= 1805);

        -- the crossing
        ok := true;
        if br_uv /= '1' then
            wait until br_uv = '1' for 40 ms;
            if br_uv /= '1' then ok := false; end if;
        end if;
        sb.check_true("G-UV undervoltage asserts on the way down", ok);
        sb.check_true("G-UV UV asserted at " & n2s(br_vstor)
                      & " mV -- the internally-set 1950 mV threshold, "
                      & "expect [1900,1965]",
                      br_vstor >= 1900 and br_vstor <= 1965);
        sb.check_true("G-UV rail A is shed at UV, vout = " & n2s(br_vout)
                      & " mV", br_vout = 0);

        -- Hold the 12.3 mW demand: the shed must leave only the 488 nA Iq, so the storage node stops falling.
        v_hold := br_vstor;
        wait for 5 ms;
        sb.check_true("G-UV the shed really removes the load: VSTOR held at "
                      & n2s(br_vstor) & " mV across 5 ms of continued 12.3 mW "
                      & "demand (was " & n2s(v_hold) & " mV)",
                      br_vstor >= v_hold - 2 and br_vstor <= v_hold);

        -- release: VBAT_UV_HYST = 15 mV, so recovery is at 1965, not 1950
        br_la  <= 0;
        br_vin <= 2000;
        br_iin <= 10000;
        ok := true;
        if br_uv /= '0' then
            wait until br_uv = '0' for 40 ms;
            if br_uv /= '0' then ok := false; end if;
        end if;
        sb.check_true("G-UV undervoltage clears once the harvester returns", ok);
        sb.check_true("G-UV UV released at " & n2s(br_vstor)
                      & " mV -- above the 1950 mV falling threshold by the "
                      & "15 mV internal hysteresis, expect [1963,1980]",
                      br_vstor >= 1963 and br_vstor <= 1980);
        wait until br_vstor >= 2100 for 40 ms;
        sb.check_true("G-UV rail A regulates again, vout = " & n2s(br_vout)
                      & " mV", br_vout >= 1795 and br_vout <= 1805);
        br_vin <= 0;
        br_iin <= 0;

        ---------------------------------------------------------------
        -- G-RAMP: one storage node ramping at ~27 mV/ms (10 uF charged at ~270 uA) with 30 mVpp of converter ripple on it.
        -- Three supervisors share ONE noise realization (same seed, same 20 mV pk-pk) and differ only in the fix under test.
        ---------------------------------------------------------------
        report "G-RAMP: slow ramp through the PGOOD threshold";
        ramp_arm <= '1';
        wait for 100 us;
        sb.check_true("G-RAMP precondition: all three supervisors start low",
                      pg_a = '0' and pg_b = '0' and pg_c = '0');
        sb.check_true("G-RAMP precondition: node starts below the threshold, "
                      & n2s(rp_vstor) & " mV < " & n2s(RAMP_VTH),
                      rp_vstor < RAMP_VTH);

        rp_vin <= 1000;
        rp_iin <= 800;
        wait for 25 ms;
        rp_vin <= 0;
        rp_iin <= 0;
        wait for 100 us;

        report "G-RAMP edge counts: A(no hyst, no filter) = " & n2s(n_a)
               & "  B(hyst 100 mV) = " & n2s(n_b)
               & "  C(de-glitch 3 ms) = " & n2s(n_c);

        sb.check_true("G-RAMP node crossed the threshold, ended at "
                      & n2s(rp_vstor) & " mV", rp_vstor > RAMP_VTH + 100);
        sb.check_true("G-RAMP A CHATTERS: " & n2s(n_a)
                      & " PGOOD edges with zero hysteresis and no filter",
                      n_a >= 10);
        sb.check_true("G-RAMP B is CLEAN: " & n2s(n_b)
                      & " edge with 100 mV of hysteresis", n_b = 1);
        sb.check_true("G-RAMP C is CLEAN: " & n2s(n_c)
                      & " edge with a 3 ms de-glitch", n_c = 1);
        sb.check_true("G-RAMP all three end asserted",
                      pg_a = '1' and pg_b = '1' and pg_c = '1');

        ---------------------------------------------------------------
        report "G-NEG: negative control (this failure is EXPECTED)";
        ---------------------------------------------------------------
        if NEGCTRL then
            sb.check_true("G-NEG (EXPECTED FAILURE) 1 mF ends at 9999 mV, got "
                          & n2s(s1_vstor), s1_vstor = 9999);
        end if;

        ---------------------------------------------------------------
        -- verdict
        ---------------------------------------------------------------
        if NEGCTRL then
            exp_err := 1;
        else
            exp_err := 0;
        end if;

        sb.report_summary("HARVEST SUPPLY TB");

        if sb.errors = exp_err then
            report LF & LF &
                "    ##################################################" & LF &
                "    ##   HARVEST_SUPPLY_MODEL_TB PASS ("
                & n2s(exp_err) & " expected negative-control failure)" & LF &
                "    ##   HARVEST SUPPLY TB:  ALL CHECKS PASSED" & LF &
                "    ##   ALL TESTS PASSED" & LF &
                "    ##################################################" & LF
                severity note;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   HARVEST_SUPPLY_MODEL_TB FAIL (expected exactly "
                & n2s(exp_err) & " failure(s), got " & n2s(sb.errors) & ")" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        stop;
        wait;
    end process stim;

end architecture tb;
