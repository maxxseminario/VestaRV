/* harvest_supply_model: behavioral bq25570-class energy-harvesting PMIC, with cold-start and boost charger, one storage node, the buck rail, a companion regulator rail and the VBAT_OK flag.
   Engineering-units lumped-energy model, not an analog simulation: ports are natural mV/uA/uJ, internal state is a real storage voltage stepped by explicit Euler every TICK_PERIOD.
   The part has exactly ONE buck, programmable only over 1.3 V to VSTOR-0.2 V, so a dual-rail chip needs a companion regulator; both rails hang off the one storage node modelled here.
   Drive BOTH load_ua (rail A, the buck) and load_aux_ua (rail B, the companion) so the whole chip draw lands on that node; two instances of this model would double-count the storage element.
   Not modelled: switching node, control loop, MPPT, thermal shutdown, ship mode, input-voltage regulation, and the VSTOR/VBAT pass PFET (the two are one node here). */

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity harvest_supply_model is
    generic (
        -- ---- solver ------------------------------------------------------
        TICK_PERIOD       : time    := 10 us;    -- integration step
        CAP_UF            : real    := 1000.0;   -- storage element, 1 mF is the project's supercap target
        V_INIT_MV         : natural := 0;        -- initial storage voltage

        -- ---- boost charger / cold start (datasheet Table 6.5) ------------
        VIN_CS_MV         : natural := 600;      -- cold start needs BOTH this VIN floor and PIN_CS_UW of input power
        VIN_DC_MIN_MV     : natural := 100;      -- harvesting floor once cold start has completed
        PIN_CS_UW         : natural := 15;
        VSTOR_CHGEN_MV    : natural := 1730;     -- above this the main boost charger takes over from the cold-start pump
        ICHG_LIM_UA       : natural := 230000;
        COLDSTART_EFF_PCT : natural := 5;        -- ASSUMPTION: sets how long cold start takes, never whether it happens
        BOOST_EFF_PCT     : natural := 80;       -- ASSUMPTION: one flat number for a 60-90% efficiency surface

        -- ---- storage-element management (datasheet Table 6.5 / 7.3.x) ----
        VBAT_OV_MV        : natural := 4200;
        VBAT_OV_HYST_MV   : natural := 24;
        VBAT_UV_MV        : natural := 1950;     -- INTERNALLY SET, not programmable
        VBAT_UV_HYST_MV   : natural := 15;
        VBAT_OK_PROG_MV   : natural := 2400;     -- falling  (load off)
        VBAT_OK_HYST_MV   : natural := 2800;     -- rising   (load on)
        OK_RSER_OHM       : natural := 20000;    -- internal series R on the flag pin: this RC is what makes the PGOOD edge slow
        OK_CLOAD_PF       : natural := 10000;    -- board cap on the flag net (ASSUMPTION)

        -- ---- rail A: THE modelled buck -----------------------------------
        VOUT_A_MV         : natural := 1800;
        VDROP_MV          : natural := 200;      -- rail falls out of regulation once VSTOR gets within this of it
        BUCK_EFF_PCT      : natural := 80;       -- ASSUMPTION: the "up to 93%" claim does not hold at these load currents
        IOUT_A_LIM_UA     : natural := 110000;   -- 110 mA peak, modelled as a clamp plus the ilim flag, not as a rail collapse

        -- ---- rail B: COMPANION off-part regulator (BOARD ASSUMPTION) -----
        VOUT_B_MV         : natural := 1000;
        AUX_IS_LDO        : boolean := true;     -- true is linear (i_stor = i_load), false uses AUX_EFF_PCT
        AUX_EFF_PCT       : natural := 85;

        -- ---- misc --------------------------------------------------------
        IQ_NA             : natural := 488;      -- quiescent draw
        RIPPLE_MV         : natural := 0         -- reported ripple pk-pk: a reporting artifact only, it never perturbs the integrated state
    );
    port (
        -- '1' enables the IC: the sense is inverted from the real EN pin (EN high is ship mode) so the inert default is the useful one.
        enable      : in  std_logic := '1';
        vout_en     : in  std_logic := '1';      -- VOUT_EN pin: gates rail A

        -- Harvester source: available voltage and the current available at that voltage, so input power is vin_mv * iin_ua.
        vin_mv      : in  natural   := 0;
        iin_ua      : in  natural   := 0;

        -- System draw, per rail, in uA at that rail's regulated voltage.
        load_ua     : in  natural   := 0;        -- rail A (buck)
        load_aux_ua : in  natural   := 0;        -- rail B (companion)

        -- Storage node; VSTOR and VBAT are one node here.
        vstor_mv    : out natural;

        -- Regulated rails.
        vout_mv     : out natural;               -- rail A
        vout_aux_mv : out natural;               -- rail B

        -- Battery-good flag: vbat_ok is the ideal internal comparator, vbat_ok_mv is the PIN slewed by OK_RSER_OHM into OK_CLOAD_PF.
        -- Feed vbat_ok_mv, not vbat_ok, to supply_supervisor.
        vbat_ok     : out std_logic;
        vbat_ok_mv  : out natural;

        -- Status flags.
        cold_start  : out std_logic;             -- cold-start circuit engaged
        charging    : out std_logic;             -- energy is entering storage
        ov          : out std_logic;             -- charging inhibited (overvoltage)
        uv          : out std_logic;             -- under VBAT_UV: load shed
        ilim        : out std_logic;             -- rail A current clamped

        -- Cumulative energy accounting, microjoules.
        e_in_uj     : out natural;               -- into storage from the harvester
        e_load_uj   : out natural;               -- delivered to the loads
        e_stor_uj   : out natural                -- drawn OUT of storage (load/eff + Iq)
    );
end entity harvest_supply_model;


architecture behavioral of harvest_supply_model is

    constant DT_NS   : integer := TICK_PERIOD / 1 ns;
    constant DT_S    : real    := real(DT_NS) * 1.0e-9;
    constant CAP_F   : real    := CAP_UF * 1.0e-6;
    -- Floor used only as a divisor guard for P/V near zero volts.
    constant V_FLOOR : real    := 0.05;
    constant TAU_S   : real    := real(OK_RSER_OHM) * real(OK_CLOAD_PF) * 1.0e-12;

    -- Real-valued min/max helpers (no VHDL-2008 minimum/maximum in this compile).
    function rmin(a, b : real) return real is
    begin
        if a < b then return a; else return b; end if;
    end function;

    function rmax(a, b : real) return real is
    begin
        if a > b then return a; else return b; end if;
    end function;

    -- Volts to millivolts, clamped at zero.
    function mv(v : real) return natural is
        variable i : integer;
    begin
        i := integer(v * 1000.0);
        if i < 0 then return 0; else return i; end if;
    end function;

    -- Joules to microjoules, clamped at zero.
    function uj(e : real) return natural is
        variable i : integer;
    begin
        i := integer(e * 1.0e6);
        if i < 0 then return 0; else return i; end if;
    end function;

    -- Boolean state to a drivable std_logic level.
    function to_sl(c : boolean) return std_logic is
    begin
        if c then return '1'; else return '0'; end if;
    end function;

begin

    -- Sanity checks against the part's programmable ranges: WARNING and not FAILURE, since an out-of-range configuration is still simulatable and is sometimes deliberate.
    assert VOUT_A_MV >= 1300
        report "harvest_supply_model: VOUT_A_MV below the bq25570 buck minimum "
             & "of 1.3 V (Table 6.6) -- not realizable with this part"
        severity warning;
    assert VBAT_OK_PROG_MV >= VBAT_UV_MV
        report "harvest_supply_model: VBAT_OK_PROG_MV below VBAT_UV -- section "
             & "7.3.4 requires the OK threshold to be >= the UV threshold"
        severity warning;
    assert VBAT_OK_HYST_MV >= VBAT_OK_PROG_MV
        report "harvest_supply_model: VBAT_OK_HYST_MV (rising) must be >= "
             & "VBAT_OK_PROG_MV (falling)"
        severity warning;
    assert VBAT_OV_MV >= 2200 and VBAT_OV_MV <= 5500
        report "harvest_supply_model: VBAT_OV_MV outside the 2.2-5.5 V "
             & "programmable range (Table 6.5)"
        severity warning;

    -- The whole model: one fixed-step loop that integrates the storage node and republishes every port each TICK_PERIOD.
    supply : process
        -- Integrated state.
        variable v       : real;                 -- storage node, volts
        variable pin_v   : real;                 -- VBAT_OK pin, volts
        variable e_in    : real;                 -- joules
        variable e_load  : real;
        variable e_stor  : real;

        -- Discrete threshold state.
        variable cold    : boolean;
        variable ovs     : boolean;
        variable uvs     : boolean;
        variable oks     : boolean;
        variable rip_sgn : integer;

        -- Per-step working values.
        variable rip     : real;
        variable va, vb  : real;
        variable la_ua   : natural;
        variable ilim_v  : boolean;
        variable p_in    : real;
        variable p_chg   : real;
        variable p_a     : real;
        variable p_b     : real;
        variable i_in    : real;
        variable i_a     : real;
        variable i_b     : real;
        variable i_q     : real;
        variable i_out   : real;
        variable pin_tgt : real;
        variable k       : real;
        variable rails   : boolean;
    begin
        v       := real(V_INIT_MV) / 1000.0;
        pin_v   := 0.0;
        e_in    := 0.0;
        e_load  := 0.0;
        e_stor  := 0.0;
        cold    := v < (real(VSTOR_CHGEN_MV) / 1000.0);
        ovs     := v >= (real(VBAT_OV_MV) / 1000.0);
        uvs     := v <  (real(VBAT_UV_MV) / 1000.0);
        oks     := false;
        rip_sgn := 1;

        loop
            -- 1. Threshold state machines, evaluated on the CLEAN node (no reported ripple).
            if v >= (real(VSTOR_CHGEN_MV) / 1000.0) then
                cold := false;
            elsif v < 0.1 then                        -- ASSUMPTION: re-arm rule
                cold := true;
            end if;

            if v >= (real(VBAT_OV_MV) / 1000.0) then
                ovs := true;
            elsif v <= (real(VBAT_OV_MV) - real(VBAT_OV_HYST_MV)) / 1000.0 then
                ovs := false;
            end if;

            if v < (real(VBAT_UV_MV) / 1000.0) then
                uvs := true;
            elsif v >= (real(VBAT_UV_MV) + real(VBAT_UV_HYST_MV)) / 1000.0 then
                uvs := false;
            end if;

            if uvs or cold then
                oks := false;                         -- cannot be "good" while shed
            elsif v >= (real(VBAT_OK_HYST_MV) / 1000.0) then
                oks := true;
            elsif v < (real(VBAT_OK_PROG_MV) / 1000.0) then
                oks := false;
            end if;

            -- 2. Rails, and the current they pull out of storage.
            rails  := (enable = '1') and (not uvs);
            ilim_v := false;

            if rails and vout_en = '1' then
                va := rmin(real(VOUT_A_MV) / 1000.0,
                           rmax(v - real(VDROP_MV) / 1000.0, 0.0));
            else
                va := 0.0;
            end if;

            la_ua := load_ua;
            if la_ua > IOUT_A_LIM_UA then
                la_ua  := IOUT_A_LIM_UA;
                ilim_v := true;
            end if;

            p_a := va * real(la_ua) * 1.0e-6;
            if p_a > 0.0 then
                i_a := (p_a / (real(BUCK_EFF_PCT) / 100.0)) / rmax(v, V_FLOOR);
            else
                i_a := 0.0;
            end if;

            if rails then
                vb := rmin(real(VOUT_B_MV) / 1000.0, v);
            else
                vb := 0.0;
            end if;
            p_b := vb * real(load_aux_ua) * 1.0e-6;
            if not rails then
                i_b := 0.0;
            elsif AUX_IS_LDO then
                i_b := real(load_aux_ua) * 1.0e-6;    -- linear pass element
            elsif p_b > 0.0 then
                i_b := (p_b / (real(AUX_EFF_PCT) / 100.0)) / rmax(v, V_FLOOR);
            else
                i_b := 0.0;
            end if;

            if enable = '1' then
                i_q := real(IQ_NA) * 1.0e-9;
            else
                i_q := 0.0;                           -- ship mode draws under 5 nA, ignored here
            end if;

            i_out := i_a + i_b + i_q;

            -- 3. Harvest input: cold-start pump below VSTOR(CHGEN), main boost above it.
            p_in  := real(vin_mv) * real(iin_ua) * 1.0e-9;   -- mV times uA gives W
            p_chg := 0.0;
            if enable = '1' and not ovs then
                if cold then
                    -- Cold start needs BOTH the 600 mV floor and 15 uW of input power.
                    if vin_mv >= VIN_CS_MV and p_in >= real(PIN_CS_UW) * 1.0e-6 then
                        p_chg := p_in * real(COLDSTART_EFF_PCT) / 100.0;
                    end if;
                else
                    if vin_mv >= VIN_DC_MIN_MV then
                        p_chg := p_in * real(BOOST_EFF_PCT) / 100.0;
                    end if;
                end if;
            end if;
            i_in := p_chg / rmax(v, V_FLOOR);
            if i_in > real(ICHG_LIM_UA) * 1.0e-6 then
                i_in  := real(ICHG_LIM_UA) * 1.0e-6;
                p_chg := i_in * v;
            end if;

            -- 4. Energy accounting, using the PRE-step node voltage.
            e_in   := e_in   + p_chg * DT_S;
            e_load := e_load + (p_a + p_b) * DT_S;
            e_stor := e_stor + i_out * v * DT_S;

            -- 5. Integrate the storage node one explicit-Euler step, then clamp it.
            -- Local error is O(dt^2): re-check the energy balance before shrinking CAP_UF or growing TICK_PERIOD.
            v := v + (i_in - i_out) * DT_S / CAP_F;
            if v < 0.0 then
                v := 0.0;
            end if;
            if v > (real(VBAT_OV_MV) / 1000.0) + 0.1 then
                v := (real(VBAT_OV_MV) / 1000.0) + 0.1;
            end if;

            -- 6. Reported ripple (a deterministic square toggle, for reproducibility) and the RC-slewed VBAT_OK pin.
            rip := real(rip_sgn) * real(RIPPLE_MV) / 2000.0;

            if oks then
                pin_tgt := rmax(v + rip, 0.0);
            else
                pin_tgt := 0.0;
            end if;
            if TAU_S <= 0.0 then
                pin_v := pin_tgt;
            else
                k := DT_S / TAU_S;
                if k > 1.0 then
                    k := 1.0;
                end if;
                pin_v := pin_v + (pin_tgt - pin_v) * k;
            end if;

            -- 7. Publish every port, then flip the ripple sign for the next tick.
            vstor_mv    <= mv(rmax(v + rip, 0.0));
            vout_mv     <= mv(va);
            vout_aux_mv <= mv(vb);
            vbat_ok     <= to_sl(oks);
            vbat_ok_mv  <= mv(pin_v);
            cold_start  <= to_sl(cold);
            charging    <= to_sl(p_chg > 0.0);
            ov          <= to_sl(ovs);
            uv          <= to_sl(uvs);
            ilim        <= to_sl(ilim_v);
            e_in_uj     <= uj(e_in);
            e_load_uj   <= uj(e_load);
            e_stor_uj   <= uj(e_stor);

            rip_sgn := -rip_sgn;
            wait for TICK_PERIOD;
        end loop;
    end process supply;

end architecture behavioral;


/* supply_supervisor: turns an analog rail level in millivolts into a clean digital PGOOD, active high; ACTIVE_HIGH false gives the inverted, open-drain-style sense.
   Models the three knobs that decide whether a SLOW ramp through the threshold gives one edge or a burst of them: hysteresis, de-glitch and input noise.
   Comparator asserts at V_RISE_MV and deasserts at V_RISE_MV - V_HYST_MV; V_HYST_MV = 0 is a plain CMOS receiver with no Schmitt, the pessimistic case.
   T_ASSERT / T_DEASSERT are the hold times the raw level must survive before the output follows it, 0 ns disables; VNOISE_MV is a deterministic LFSR dither so edge counts are reproducible.
   Not modelled: the supervisor's own minimum operating voltage, open-drain outputs and their pull-up RC, and any power-on reset timer. */

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity supply_supervisor is
    generic (
        V_RISE_MV    : natural := 2000;      -- assert threshold (rising)
        V_HYST_MV    : natural := 0;         -- deassert at V_RISE_MV - V_HYST_MV
        T_ASSERT     : time    := 0 ns;      -- de-glitch before asserting
        T_DEASSERT   : time    := 0 ns;      -- de-glitch before deasserting
        VNOISE_MV    : natural := 0;         -- input-referred noise pk-pk; 0 makes the comparator purely event-driven, with no sampling
        NOISE_PERIOD : time    := 10 us;     -- noise/sampling interval
        NOISE_SEED   : natural := 16#ACE1#;  -- LFSR seed (must be non-zero)
        ACTIVE_HIGH  : boolean := true       -- false gives the open-drain-style /PGOOD sense
    );
    port (
        vsense_mv : in  natural := 0;
        pgood     : out std_logic := '0'
    );
end entity supply_supervisor;


architecture behavioral of supply_supervisor is

    signal raw : std_logic := '0';   -- comparator output, before de-glitch
    signal lvl : std_logic := '0';   -- de-glitched level

begin

    assert V_HYST_MV <= V_RISE_MV
        report "supply_supervisor: V_HYST_MV exceeds V_RISE_MV -- the falling "
             & "threshold would be negative"
        severity warning;

    -- Comparator with hysteresis, plus optional deterministic input noise.
    cmp : process
        variable lfsr : unsigned(15 downto 0);
        variable fb   : std_logic;
        variable s    : integer;
        variable dith : integer;
        variable out_v: std_logic := '0';
        variable v_fall : integer;
    begin
        if NOISE_SEED = 0 then
            lfsr := to_unsigned(16#ACE1#, 16);
        else
            lfsr := to_unsigned(NOISE_SEED mod 65536, 16);
        end if;
        if V_HYST_MV <= V_RISE_MV then
            v_fall := V_RISE_MV - V_HYST_MV;
        else
            v_fall := 0;
        end if;

        loop
            if VNOISE_MV = 0 then
                s := vsense_mv;
            else
                lfsr := lfsr(14 downto 0) &
                        (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
                dith := (to_integer(lfsr) mod (VNOISE_MV + 1)) - (VNOISE_MV / 2);
                s    := vsense_mv + dith;
            end if;

            if s >= V_RISE_MV then
                out_v := '1';
            elsif s < v_fall then
                out_v := '0';
            end if;                        -- inside the band: hold
            raw <= out_v;

            if VNOISE_MV = 0 then
                wait on vsense_mv;
            else
                wait for NOISE_PERIOD;
            end if;
        end loop;
    end process cmp;

    -- De-glitch: the raw level must survive T_ASSERT / T_DEASSERT before the output follows it.
    -- A level that flips back inside the window is discarded and re-evaluated from the top, so no edge is lost.
    dgl : process
        variable out_v : std_logic := '0';
    begin
        loop
            if raw = out_v then
                wait on raw;
            else
                if raw = '1' then
                    if T_ASSERT > 0 ns then
                        wait on raw for T_ASSERT;
                    end if;
                else
                    if T_DEASSERT > 0 ns then
                        wait on raw for T_DEASSERT;
                    end if;
                end if;
                if raw /= out_v then
                    out_v := raw;
                    lvl   <= out_v;
                end if;
            end if;
        end loop;
    end process dgl;

    pgood <= lvl when ACTIVE_HIGH else not lvl;

end architecture behavioral;
