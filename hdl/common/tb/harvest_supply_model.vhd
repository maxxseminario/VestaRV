-------------------------------------------------------------------------------
-- harvest_supply_model.vhd
-------------------------------------------------------------------------------
-- Behavioral simulation model of a TI bq25570-class energy-harvesting PMIC
-- (boost charger + storage element + buck rail + VBAT_OK "battery good" flag)
-- PLUS a companion `supply_supervisor` entity that turns an analog rail level
-- into the clean digital PGOOD that Castalia's DP-S3 field-power boot gate
-- consumes on package pin 69 (P6.7 -> pwr_ctrl.pgood_pad).
--
-- Datasheet: TI bq25570, SLUSBH2G, MARCH 2013 - REVISED MARCH 2019 (the copy
-- in .devlog/datasheets/BQ25570_datasheet.pdf). Section numbers below refer
-- to that revision.
--
-- ==========================================================================
-- AT A GLANCE: TWO RAILS, ONE STORAGE NODE -- AND WHY
-- ==========================================================================
-- READ THIS BEFORE WIRING THE MODEL. Castalia is DUAL-RAIL (1.0 V core,
-- 3.3 V I/O) and the bq25570 has exactly ONE buck, programmable only over
-- 1.3 V .. VSTOR-0.2 V. So a single bq25570 can supply NEITHER Castalia rail
-- from a 2.5 V supercap: 1.0 V is below its floor and 3.3 V is above its
-- headroom. **A harvested Castalia board needs TWO regulators.** That is a
-- board-topology fact, not a reason to avoid the part -- the bq25570 is still
-- a good harvester/charger/supervisor; it is simply not the whole supply.
--
-- This model therefore exposes BOTH rails off ONE shared storage node:
--
--     harvest in --> [ boost + cold start ] --> VSTOR (the supercap)
--                                                 |
--                          rail A (vout_mv) <-----+  bq25570 buck   [MODELLED]
--                          rail B (vout_aux_mv) <-+  companion reg  [BOARD
--                                                 |                  ASSUMPTION]
--                          VBAT_OK ---------------+--> supply_supervisor
--                                                      --> pgood --> Castalia
--                                                          pin 69 (P6.7)
--                                                          pwr_ctrl.pgood_pad
--
-- Drive BOTH `load_ua` (rail A) and `load_aux_ua` (rail B) so the whole chip
-- draw lands on the one capacitor. Using two instances of this model instead
-- would double-count the supercap -- see the fuller justification below.
--
-- ==========================================================================
-- WHAT THIS IS -- AND, EMPHATICALLY, WHAT IT IS NOT
-- ==========================================================================
-- This is an ENGINEERING-UNITS, DISCRETE-TIME, LUMPED-ENERGY model. It is NOT
-- an analog simulation. There is no inductor current, no switching node, no
-- PFM/PWM pulse train, no control loop, no small-signal anything. State is a
-- single storage-node voltage integrated forward with explicit Euler at a
-- fixed TICK_PERIOD:
--
--     v(t+dt) = v(t) + ( i_harvest - i_load ) * dt / C
--
-- All ports carrying physical quantities are `natural` in ENGINEERING UNITS:
-- millivolts (mV), microamps (uA), microjoules (uJ). Internally the state is
-- `real` volts/amps/joules; the ports are the rounded integer view. Nothing
-- here is an electrical sign-off model and nothing here should ever be used
-- to size a real part -- it exists so that DIGITAL firmware and the DP-S3 boot
-- gate can be exercised against a plausible, datasheet-grounded supply that
-- ramps, saturates, browns out and recovers, instead of against a tcl `force`.
--
-- ACCURACY: explicit Euler with a constant-power load is unconditionally
-- convergent here and the local error is O(dt^2); at the default 10 us tick
-- and a 1 mF cap the 100 ms sizing run below agrees with the closed-form
-- 0.5*C*(V0^2 - V1^2) energy balance to well under 1 mV. Do not shrink C or
-- grow dt without re-checking that.
--
-- ==========================================================================
-- WHY TWO OUTPUT RAILS IN ONE MODEL (justification, per the task brief)
-- ==========================================================================
-- Castalia is dual-rail: 1.0 V core and 3.3 V I/O. The bq25570 has exactly
-- ONE buck (section 7.3.7) and its programmable output range is 1.3 V to
-- VSTOR-0.2 V (section 6.6) -- so a single bq25570 CANNOT produce Castalia's
-- 1.0 V core rail at all. A real board therefore uses the bq25570 buck for one
-- rail and a COMPANION regulator for the other.
--
-- Two instances of this model would be WRONG, because they would each own a
-- private copy of the storage element and so double-count the supercap -- the
-- one thing the sizing question turns on. So: ONE model, ONE storage node, TWO
-- output rails:
--
--   rail A (vout_mv)     = the bq25570 buck. Setpoint VOUT_A_MV, efficiency
--                          BUCK_EFF_PCT, current limit IOUT_A_LIM_UA. THIS IS
--                          THE MODELLED PART.
--   rail B (vout_aux_mv) = a COMPANION off-part regulator fed from VSTOR.
--                          NOT a bq25570 feature. Present only so the second
--                          Castalia rail's draw lands on the same storage
--                          element. AUX_IS_LDO selects linear (i_stor =
--                          i_load, efficiency = Vb/Vstor) vs switching
--                          (AUX_EFF_PCT). Everything about rail B is a BOARD
--                          ASSUMPTION, not a datasheet behavior.
--
-- ==========================================================================
-- DATASHEET GROUNDING (generic defaults)
-- ==========================================================================
--   VIN_CS_MV       = 600  Minimum VIN for the COLD-START circuit. Table 6.5
--                          VIN(CS): typ 600 mV, max 700 mV. *** NOTE: the
--                          widely-quoted "330 mV" figure is from the PRE-2019
--                          revision; this revision's own revision history
--                          (page 1 of the change log) records "Changed From:
--                          VIN(CS) = 330 mV typical. To: VIN(CS) = 600 mV
--                          typical." The task brief quoted 330 mV; 600 mV is
--                          what the datasheet on disk says, so 600 mV is the
--                          default here. Override the generic to explore the
--                          old number.
--   VIN_DC_MIN_MV   = 100  Table 6.5 VIN(DC) min, "cold-start completed" --
--                          i.e. once VSTOR is up, harvesting continues down to
--                          100 mV. (Feature bullet: "Continuous Energy
--                          Harvesting From VIN as low as 100 mV".)
--   PIN_CS_UW       = 15   Table 6.5 PIN(CS): minimum cold-start input power.
--   VSTOR_CHGEN_MV  = 1730 Table 6.5 VSTOR(CHGEN) typ (min 1.6 / max 1.9 V);
--                          section 7.1 quotes "1.8 V typical" in prose. Above
--                          this the main boost charger takes over from the
--                          cold-start circuit.
--   ICHG_LIM_UA     = 230000 Table 6.5 ICHG(CBC_LIM) typ 230 mA.
--   VBAT_OV_MV      = 4200 User-programmable via ROV1/ROV2 (eq. 2), range
--                          2.2 - 5.5 V (Table 6.5). 4.2 V = the datasheet's
--                          own worked example.
--   VBAT_OV_HYST_MV = 24   Table 6.5 VBAT_OV_HYST typ 24 mV (max 55).
--   VBAT_UV_MV      = 1950 Table 6.5 VBAT_UV, INTERNALLY SET, typ 1.95 V
--                          (min 1.91 / max 2.00). NOT programmable.
--   VBAT_UV_HYST_MV = 15   Table 6.5 VBAT_UV_HYST typ 15 mV (max 32).
--   VBAT_OK_PROG_MV = 2400 Falling ("turn the load off") threshold, set by
--                          ROK1/ROK2 (eq. 3). Must be >= VBAT_UV (7.3.4).
--   VBAT_OK_HYST_MV = 2800 Rising ("turn the load on") threshold, set by
--                          ROK1/ROK2/ROK3 (eq. 4).
--   IQ_NA           = 488  Table 6.5, full operating mode typ 488 nA.
--   OK_RSER_OHM     = 20000 Section 7.3.4: the VBAT_OK high level equals VSTOR
--                          "with ~20 kOhm internally in series to limit the
--                          available current in order to prevent MCU damage
--                          until the MCU is fully powered". The low level is
--                          ground. THIS 20 k IS THE ORIGIN OF THE SLOW PGOOD
--                          EDGE -- see the open-question note below.
--   VDROP_MV        = 200  From the buck's programmable range ceiling
--                          "VSTOR - 0.2 V" (Table 6.6): the rail falls out of
--                          regulation when VSTOR gets within 200 mV of it.
--   BUCK_EFF_PCT    = 80   Section 7.3.7 / feature list claim "up to 93%"; the
--                          efficiency curves fall well below that at the tens-
--                          of-microamp to few-milliamp currents Castalia sits
--                          at. 80% is ALSO the number the VestaRV field-power
--                          page already assumes for its supercap arithmetic,
--                          so it is the default here to keep the two
--                          consistent. ASSUMPTION, not a datasheet number.
--
-- ASSUMPTIONS (NOT from the datasheet -- flagged, per house style):
--   * COLDSTART_EFF_PCT = 5. The datasheet gives PIN(CS) = 15 uW but no
--     cold-start charge-pump efficiency. 5% is the figure TI's harvesting
--     app notes use for this class of cold-start pump. It only sets how LONG
--     cold start takes, never whether it happens.
--   * BOOST_EFF_PCT = 80. The charger efficiency curves (figure on page 1)
--     run roughly 60-90% depending on VIN/VSTOR/IIN; one flat number is a
--     deliberate simplification.
--   * Cold start RE-ARMS when the storage node falls below 100 mV. The
--     datasheet describes entry ("starting from VSTOR = VBAT < 100 mV",
--     section 7.1) but not an explicit re-arm rule.
--   * VBAT and VSTOR are modelled as ONE node. On the real part they are
--     separate pins joined by an internal PFET that opens below VBAT_UV. The
--     single-node view is exactly right for the configuration this project
--     cares about (a supercap as the storage element) and turns VBAT_UV into
--     "the part sheds the load", which is the behavior that matters. What is
--     NOT modelled: the RDS(ON)-BAT 0.95 Ohm drop across that PFET, and the
--     tBAT_HOT_PLUG 50 ms hot-plug switch.
--   * RIPPLE_MV is a REPORTING artifact added to the published vstor_mv and to
--     the VBAT_OK pin drive; it does not perturb the integrated state. It
--     stands in for two real, datasheet-described effects: the 30 mVpp buck
--     output ripple (Table 6.6) and, more importantly, section 7.3.3's "when
--     there is excessive input energy, the VBAT pin voltage will ripple
--     between the VBAT_OV and the VBAT_OV_HYST levels". It is modelled as a
--     square toggle of +/- RIPPLE_MV/2 every tick, which is deterministic and
--     therefore reproducible -- a real converter's ripple is neither.
--   * The current limit is modelled as a CLAMP on the current drawn plus an
--     `ilim` flag. A real buck driven past its limit falls out of regulation;
--     the rail voltage collapse is NOT modelled. Watch the flag, not the rail.
--   * MPPT (VOC_SAMP / VREF_SAMP, 16 s sample period, 256 ms settle), thermal
--     shutdown (TTEMP_SD 125 C), ship mode's <5 nA, and the input-voltage
--     regulation loop (VIN_REG) are NOT modelled at all.
--
-- ==========================================================================
-- THE OPEN QUESTION THIS MODEL EXISTS TO MAKE SIMULATABLE
-- ==========================================================================
-- Recorded against DP-S3: "the real-silicon PGOOD slow-ramp question -- a
-- floating/slowly-rising PGOOD crosses the receiver threshold slowly on a
-- boot-gating path; hysteresis/glitch-filter vs board-always-drives is
-- undecided."
--
-- The physics that makes it a real question is in this model, not invented:
--   (a) VBAT_OK is NOT a push-pull digital output. Its high level is VSTOR
--       through ~20 kOhm (7.3.4). Into any real board capacitance that is an
--       RC with a hundreds-of-microseconds time constant -- OK_RSER_OHM x
--       OK_CLOAD_PF, exposed as generics. `vbat_ok_mv` is that slewed pin
--       voltage; `vbat_ok` is the ideal internal comparator.
--   (b) The storage rail itself ramps at whatever dV/dt = I/C the harvester
--       and the supercap dictate -- volts per SECOND with a 1 mF cap, i.e.
--       millivolts per millisecond. Every threshold crossing is slow.
--   (c) Any real comparator/receiver has input-referred noise, and the rail
--       carries converter ripple. Both are in the model.
--
-- `supply_supervisor` then makes the two candidate fixes A/B-testable as
-- generics: V_HYST_MV (hysteresis) and T_ASSERT/T_DEASSERT (de-glitch). Point
-- three supervisors at ONE ramping node with three settings and count edges;
-- see harvest_supply_model_tb.vhd group G-RAMP.
--
-- ==========================================================================
-- CONNECTING THIS TO CASTALIA
-- ==========================================================================
-- `supply_supervisor.pgood` is a plain std_logic, active high, and is
-- DIRECTLY CONNECTABLE to `pwr_ctrl.pgood_pad` (package pin 69 / P6.7). The
-- intended board wiring is:
--
--   harvester -> harvest_supply_model.vin_mv/iin_ua
--   harvest_supply_model.vbat_ok_mv -> supply_supervisor.vsense_mv
--       (V_RISE_MV = the receiving pad's Vih; V_HYST_MV = the pad's Schmitt
--        hysteresis, ZERO for a plain CMOS input)
--   supply_supervisor.pgood -> pwr_ctrl.pgood_pad
--   Castalia's own draw -> harvest_supply_model.load_ua / load_aux_ua
--
-- Note that pin 69 is a PULL-DOWN pad (PDDW16SDGZ_G): unconnected reads "power
-- not good", which is the safe sense. A supervisor whose own supply has not
-- come up yet is therefore already handled by the pad, and this model does not
-- attempt to reproduce the pad's own 100 us pull settle time.
--
-- This file deliberately does NOT instantiate or modify pwr_ctrl -- it is a
-- standalone model plus its own bench.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity harvest_supply_model is
    generic (
        -- ---- solver ------------------------------------------------------
        TICK_PERIOD       : time    := 10 us;    -- integration step
        CAP_UF            : real    := 1000.0;   -- storage element (1 mF = the
                                                 -- project's supercap target)
        V_INIT_MV         : natural := 0;        -- initial storage voltage

        -- ---- boost charger / cold start (datasheet Table 6.5) ------------
        VIN_CS_MV         : natural := 600;
        VIN_DC_MIN_MV     : natural := 100;
        PIN_CS_UW         : natural := 15;
        VSTOR_CHGEN_MV    : natural := 1730;
        ICHG_LIM_UA       : natural := 230000;
        COLDSTART_EFF_PCT : natural := 5;        -- ASSUMPTION
        BOOST_EFF_PCT     : natural := 80;       -- ASSUMPTION

        -- ---- storage-element management (datasheet Table 6.5 / 7.3.x) ----
        VBAT_OV_MV        : natural := 4200;
        VBAT_OV_HYST_MV   : natural := 24;
        VBAT_UV_MV        : natural := 1950;     -- INTERNALLY SET, not programmable
        VBAT_UV_HYST_MV   : natural := 15;
        VBAT_OK_PROG_MV   : natural := 2400;     -- falling  (load off)
        VBAT_OK_HYST_MV   : natural := 2800;     -- rising   (load on)
        OK_RSER_OHM       : natural := 20000;    -- 7.3.4 internal series R
        OK_CLOAD_PF       : natural := 10000;    -- board cap on the flag net (ASSUMPTION)

        -- ---- rail A: THE bq25570 buck ------------------------------------
        VOUT_A_MV         : natural := 1800;
        VDROP_MV          : natural := 200;
        BUCK_EFF_PCT      : natural := 80;
        IOUT_A_LIM_UA     : natural := 110000;   -- 110 mA peak (feature list)

        -- ---- rail B: COMPANION off-part regulator (BOARD ASSUMPTION) -----
        VOUT_B_MV         : natural := 1000;
        AUX_IS_LDO        : boolean := true;
        AUX_EFF_PCT       : natural := 85;

        -- ---- misc --------------------------------------------------------
        IQ_NA             : natural := 488;      -- quiescent draw
        RIPPLE_MV         : natural := 0         -- reported ripple, pk-pk
    );
    port (
        -- '1' = IC enabled. On the real part this is EN pin LOW (EN high =
        -- ship mode); the sense is inverted here so that the inert default is
        -- the useful one.
        enable      : in  std_logic := '1';
        vout_en     : in  std_logic := '1';      -- VOUT_EN pin: gates rail A

        -- harvester source: available open-circuit-ish voltage and the
        -- current available AT that voltage. Input power = vin_mv * iin_ua.
        vin_mv      : in  natural   := 0;
        iin_ua      : in  natural   := 0;

        -- system draw, per rail, in uA at that rail's regulated voltage
        load_ua     : in  natural   := 0;        -- rail A (buck)
        load_aux_ua : in  natural   := 0;        -- rail B (companion)

        -- storage node (VSTOR = VBAT, single-node simplification)
        vstor_mv    : out natural;

        -- regulated rails
        vout_mv     : out natural;               -- rail A
        vout_aux_mv : out natural;               -- rail B

        -- battery-good flag. `vbat_ok` is the ideal internal comparator;
        -- `vbat_ok_mv` is the PIN, slewed by the 20 k series R into
        -- OK_CLOAD_PF. Feed vbat_ok_mv to supply_supervisor.
        vbat_ok     : out std_logic;
        vbat_ok_mv  : out natural;

        -- status
        cold_start  : out std_logic;             -- cold-start circuit engaged
        charging    : out std_logic;             -- energy is entering storage
        ov          : out std_logic;             -- charging inhibited (overvoltage)
        uv          : out std_logic;             -- under VBAT_UV: load shed
        ilim        : out std_logic;             -- rail A current clamped

        -- cumulative energy accounting, microjoules
        e_in_uj     : out natural;               -- into storage from the harvester
        e_load_uj   : out natural;               -- delivered to the loads
        e_stor_uj   : out natural                -- drawn OUT of storage (load/eff + Iq)
    );
end entity harvest_supply_model;


architecture behavioral of harvest_supply_model is

    constant DT_NS   : integer := TICK_PERIOD / 1 ns;
    constant DT_S    : real    := real(DT_NS) * 1.0e-9;
    constant CAP_F   : real    := CAP_UF * 1.0e-6;
    -- floor used only as a divisor guard for P/V near zero volts
    constant V_FLOOR : real    := 0.05;
    constant TAU_S   : real    := real(OK_RSER_OHM) * real(OK_CLOAD_PF) * 1.0e-12;

    function rmin(a, b : real) return real is
    begin
        if a < b then return a; else return b; end if;
    end function;

    function rmax(a, b : real) return real is
    begin
        if a > b then return a; else return b; end if;
    end function;

    -- volts -> millivolts, clamped at zero
    function mv(v : real) return natural is
        variable i : integer;
    begin
        i := integer(v * 1000.0);
        if i < 0 then return 0; else return i; end if;
    end function;

    -- joules -> microjoules, clamped at zero
    function uj(e : real) return natural is
        variable i : integer;
    begin
        i := integer(e * 1.0e6);
        if i < 0 then return 0; else return i; end if;
    end function;

    function to_sl(c : boolean) return std_logic is
    begin
        if c then return '1'; else return '0'; end if;
    end function;

begin

    -- Elaboration-time sanity against the datasheet's programmable ranges.
    -- WARNING, not FAILURE: an out-of-range configuration is still simulatable
    -- and is sometimes exactly what an exploration wants (see the bench's
    -- idealized sizing instances).
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

    supply : process
        -- integrated state
        variable v       : real;                 -- storage node, volts
        variable pin_v   : real;                 -- VBAT_OK pin, volts
        variable e_in    : real;                 -- joules
        variable e_load  : real;
        variable e_stor  : real;

        -- discrete state
        variable cold    : boolean;
        variable ovs     : boolean;
        variable uvs     : boolean;
        variable oks     : boolean;
        variable rip_sgn : integer;

        -- per-step working values
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
            -----------------------------------------------------------------
            -- 1. threshold state machines, evaluated on the CLEAN node
            -----------------------------------------------------------------
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

            -----------------------------------------------------------------
            -- 2. rails and the current they pull out of storage
            -----------------------------------------------------------------
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
                i_q := 0.0;                           -- ship mode: <5 nA, ignored
            end if;

            i_out := i_a + i_b + i_q;

            -----------------------------------------------------------------
            -- 3. harvest input
            -----------------------------------------------------------------
            p_in  := real(vin_mv) * real(iin_ua) * 1.0e-9;   -- mV * uA -> W
            p_chg := 0.0;
            if enable = '1' and not ovs then
                if cold then
                    -- cold start needs BOTH the 600 mV floor and 15 uW
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

            -----------------------------------------------------------------
            -- 4. energy accounting (uses the PRE-step node voltage)
            -----------------------------------------------------------------
            e_in   := e_in   + p_chg * DT_S;
            e_load := e_load + (p_a + p_b) * DT_S;
            e_stor := e_stor + i_out * v * DT_S;

            -----------------------------------------------------------------
            -- 5. integrate the storage node
            -----------------------------------------------------------------
            v := v + (i_in - i_out) * DT_S / CAP_F;
            if v < 0.0 then
                v := 0.0;
            end if;
            if v > (real(VBAT_OV_MV) / 1000.0) + 0.1 then
                v := (real(VBAT_OV_MV) / 1000.0) + 0.1;
            end if;

            -----------------------------------------------------------------
            -- 6. reported ripple + the RC-slewed VBAT_OK pin (7.3.4)
            -----------------------------------------------------------------
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

            -----------------------------------------------------------------
            -- 7. publish
            -----------------------------------------------------------------
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


-------------------------------------------------------------------------------
-- supply_supervisor
-------------------------------------------------------------------------------
-- Turns an analog rail level (millivolts) into a clean digital PGOOD. Models
-- the three knobs that decide whether a SLOW ramp through the threshold
-- produces one edge or a burst of them:
--
--   V_RISE_MV / V_HYST_MV : comparator thresholds. Asserts at V_RISE_MV,
--       deasserts at V_RISE_MV - V_HYST_MV. V_HYST_MV = 0 models a plain CMOS
--       receiver (no Schmitt) -- the pessimistic case in the open question.
--   T_ASSERT / T_DEASSERT : de-glitch / settle windows. The raw comparator
--       level must hold for this long before the output follows it. 0 ns
--       disables. This is the "glitch filter" candidate fix.
--   VNOISE_MV : input-referred noise, peak-to-peak, sampled every
--       NOISE_PERIOD. Modelled as a DETERMINISTIC 16-bit LFSR dither so that
--       edge counts are reproducible run to run -- real noise is not. When
--       VNOISE_MV = 0 the comparator is purely event-driven (no sampling).
--
-- ASSUMPTION: VNOISE_MV has no datasheet basis -- it is a stand-in for the
-- combined receiver-input noise, reference noise and coupling that make a
-- marginal, slowly-crossed threshold chatter on real hardware. Its VALUE is a
-- knob for exploration; its PRESENCE is the point.
--
-- NOT modelled: the supervisor's own minimum operating voltage (below which a
-- real device's output is undefined), open-drain outputs and their pull-up RC,
-- and any power-on reset timer. On Castalia the undefined-at-power-up case is
-- covered by pin 69 being a pull-DOWN pad, which reads "not good".
--
-- `pgood` is directly connectable to pwr_ctrl.pgood_pad (active high).
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity supply_supervisor is
    generic (
        V_RISE_MV    : natural := 2000;      -- assert threshold (rising)
        V_HYST_MV    : natural := 0;         -- deassert at V_RISE_MV - V_HYST_MV
        T_ASSERT     : time    := 0 ns;      -- de-glitch before asserting
        T_DEASSERT   : time    := 0 ns;      -- de-glitch before deasserting
        VNOISE_MV    : natural := 0;         -- input-referred noise, pk-pk
        NOISE_PERIOD : time    := 10 us;     -- noise/sampling interval
        NOISE_SEED   : natural := 16#ACE1#;  -- LFSR seed (must be non-zero)
        ACTIVE_HIGH  : boolean := true       -- false = open-drain-style /PGOOD sense
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

    -----------------------------------------------------------------------
    -- comparator with hysteresis (+ optional deterministic input noise)
    -----------------------------------------------------------------------
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

    -----------------------------------------------------------------------
    -- de-glitch: the raw level must survive T_ASSERT / T_DEASSERT before the
    -- output follows it. A level that flips back inside the window is
    -- discarded and the loop re-evaluates from the top, so no edge is lost.
    -----------------------------------------------------------------------
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
