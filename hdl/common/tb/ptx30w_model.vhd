-------------------------------------------------------------------------------
-- ptx30w_model.vhd
-------------------------------------------------------------------------------
-- Behavioral model of the Renesas PTX30W NFC wireless-charging (WLC) listener IC: I2C target at 0x4B, dedicated host IRQ, HIP frames carrying the NSC layer and the transparent data channel (TDC).
-- Board context: Castalia is the I2C master on I2C0 (chip pins 37/38) and takes the PTX30W IRQ pin on a GPIO.
-- Power path, charger and rails are an ABSTRACTION: integer engineering units (mV, uA, mW) recomputed every G_PWR_TICK, no electrical simulation, never an accuracy or sign-off claim.
-- The RF link is not modelled; the ports under the BENCH ABSTRACTION headings are bench stimulus (poller side of the TDC, analog environment), not device pins.
-- In standby the first addressed transfer is address-NACKed and arms a 100 ms wake window; the retry inside that window is ACKed.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------
-- Support package, kept in this file so the model and its bench are the whole deliverable.
-------------------------------------------------------------------------------
package ptx30w_pkg is

    type ptx_byte_array is array (natural range <>) of std_logic_vector(7 downto 0);

    -- Buffer and geometry constants.
    constant PTX_TDC_BUF_SIZE : natural := 64;    -- the two TDC buffers are 64 bytes each
    constant PTX_NSC_DATA_MAX : natural := 63;    -- NSC_DATA_MSG 6-bit length field
    constant PTX_MSG_MAX      : natural := 264;   -- message buffer, 256+8 bytes
    constant PTX_FRAME_MAX    : natural := 300;   -- HIP frame staging (LEN+FCB+payload+CRC)
    constant PTX_RSS_LEN      : natural := 21;    -- status block 1+1+2+16+1

    subtype ptx_msg_t   is ptx_byte_array(0 to PTX_MSG_MAX - 1);
    subtype ptx_buf64_t is ptx_byte_array(0 to PTX_TDC_BUF_SIZE - 1);

    -- HIP opcodes: reset, read system status, write message, read message, read message length.
    constant PTX_OP_RST  : natural := 16#1#;
    constant PTX_OP_RSS  : natural := 16#2#;
    constant PTX_OP_WMSG : natural := 16#7#;
    constant PTX_OP_RMSG : natural := 16#8#;
    constant PTX_OP_RML  : natural := 16#9#;

    -- HIP ACK/NAK values; the NAK is stored and reads back as the first byte of the next RSS response.
    constant PTX_NAK_NONE  : std_logic_vector(7 downto 0) := x"00";
    constant PTX_NAK_CMD   : std_logic_vector(7 downto 0) := x"01";
    constant PTX_NAK_LEN   : std_logic_vector(7 downto 0) := x"02";
    constant PTX_NAK_CRC   : std_logic_vector(7 downto 0) := x"03";
    constant PTX_NAK_PARAM : std_logic_vector(7 downto 0) := x"04";
    constant PTX_NAK_FULL  : std_logic_vector(7 downto 0) := x"05";

    -- NSC opcodes; 0x80 plus a 6-bit length is NSC_DATA_MSG, and 0x80 alone is NSC_DATA_ACK.
    constant PTX_NSC_CONFIG    : std_logic_vector(7 downto 0) := x"01";
    constant PTX_NSC_SET_PARAM : std_logic_vector(7 downto 0) := x"02";
    constant PTX_NSC_GET_PARAM : std_logic_vector(7 downto 0) := x"03";

    -- NSC error codes
    constant PTX_EC_NONE  : std_logic_vector(7 downto 0) := x"00";
    constant PTX_EC_CMD   : std_logic_vector(7 downto 0) := x"01";
    constant PTX_EC_PARAM : std_logic_vector(7 downto 0) := x"02";
    constant PTX_EC_NVM   : std_logic_vector(7 downto 0) := x"03";

    -- BC_STATUS (charger phase) values
    constant PTX_BC_DISABLED : natural := 0;
    constant PTX_BC_TCM      : natural := 1;
    constant PTX_BC_CCM      : natural := 2;
    constant PTX_BC_CVM      : natural := 3;
    constant PTX_BC_DONE     : natural := 4;

    -- NTC_STATUS values
    constant PTX_NTC_NORMAL : natural := 16#00#;
    constant PTX_NTC_COLD   : natural := 16#02#;
    constant PTX_NTC_ECOLD  : natural := 16#03#;
    constant PTX_NTC_HOT    : natural := 16#04#;
    constant PTX_NTC_EHOT   : natural := 16#0C#;

    -- ERROR_STATUS values actually produced: one enumerated value, never a bitfield (the defined values overlap bitwise).
    constant PTX_ERR_NONE    : natural := 16#00#;
    constant PTX_ERR_ICTEMP  : natural := 16#01#;
    constant PTX_ERR_NOBAT   : natural := 16#04#;
    constant PTX_ERR_BATTEMP : natural := 16#08#;

    -- NSC WR parameter IDs
    constant PTX_ID_ICHG      : natural := 16#01#;
    constant PTX_ID_VTERM     : natural := 16#02#;
    constant PTX_ID_VTRK      : natural := 16#03#;
    constant PTX_ID_VRCHG     : natural := 16#04#;
    constant PTX_ID_BC_EN     : natural := 16#05#;
    constant PTX_ID_HOST_WPT  : natural := 16#06#;
    constant PTX_ID_NDEF      : natural := 16#07#;
    constant PTX_ID_SHIP      : natural := 16#08#;
    constant PTX_ID_WPT_REQ   : natural := 16#09#;
    constant PTX_ID_DETUNE    : natural := 16#0A#;
    constant PTX_ID_NFC_EN    : natural := 16#0B#;
    constant PTX_ID_LIM_TH    : natural := 16#0C#;

    -- CRC_B, ISO/IEC 14443-3 Type B: poly 0x8408 reflected, init 0xFFFF, final inversion, over LEN+FCB+payload.
    -- Returns the 16-bit value; G_CRC_MSB_FIRST picks the byte order it goes into the frame with.
    function ptx_crc_b(d : ptx_byte_array) return std_logic_vector;

    -- Charger threshold and current decode tables.
    function ptx_vterm_mv(code : natural) return natural;   -- BC_VTERM_CTRL, 32 entries
    function ptx_vtrk_mv (code : natural) return natural;   -- BC_VTRK_CTRL,   8 entries
    function ptx_vrchg_mv(code : natural) return natural;   -- BC_VRCHG_CTRL, 16 entries
    function ptx_limth_mv(code : natural) return natural;   -- LIM_TH_SEL,    16 entries
    function ptx_ichg_ua (code : natural) return natural;   -- 1.96mA*code + 1.92mA
    function ptx_iterm_ua(code : natural) return natural;   -- 1.39mA*code - 0.34mA
    function ptx_ichg_pct(code : natural) return natural;   -- BC_ICHG_PCT_{COLD,HOT}

end package ptx30w_pkg;


package body ptx30w_pkg is

    function ptx_crc_b(d : ptx_byte_array) return std_logic_vector is
        variable crc : std_logic_vector(15 downto 0) := x"FFFF";
    begin
        for i in d'range loop
            crc := crc xor (x"00" & d(i));
            for b in 0 to 7 loop
                if crc(0) = '1' then
                    crc := ('0' & crc(15 downto 1)) xor x"8408";
                else
                    crc := '0' & crc(15 downto 1);
                end if;
            end loop;
        end loop;
        return not crc;
    end function;

    -- BC_VTERM_CTRL table, millivolts, codes 0x00 to 0x1F.
    type mv_tbl32 is array (0 to 31) of natural;
    constant VTERM_TBL : mv_tbl32 :=
        (3590, 3620, 3650, 3670, 3700, 3730, 3750, 3810,
         3830, 3860, 3910, 3940, 3970, 4020, 4080, 4130,
         4160, 4180, 4240, 4260, 4290, 4320, 4340, 4400,
         4420, 4450, 4510, 4530, 4560, 4590, 4610, 4650);

    type mv_tbl8 is array (0 to 7) of natural;
    -- BC_VTRK_CTRL table, millivolts; note the non-monotonic code order.
    constant VTRK_TBL : mv_tbl8 := (3000, 2500, 2600, 2700, 2800, 2900, 3100, 3200);

    type mv_tbl16 is array (0 to 15) of natural;
    -- BC_VRCHG_CTRL table, millivolts.
    constant VRCHG_TBL : mv_tbl16 :=
        (2910, 3020, 3130, 3230, 3340, 3440, 3550, 3660,
         3730, 3770, 3820, 3870, 4040, 4200, 4300, 4420);
    -- LIM_TH_SEL table, millivolts; codes 0 to 2 and 13 to 15 are invalid and read as the 5.2 V default.
    constant LIMTH_TBL : mv_tbl16 :=
        (5200, 5200, 5200, 3400, 3600, 3800, 4000, 4200,
         4400, 4600, 4800, 5000, 5200, 5200, 5200, 5200);

    -- The table lookups below clamp an out-of-range code to a defined entry rather than failing an index check.
    function ptx_vterm_mv(code : natural) return natural is
    begin
        if code > 31 then return VTERM_TBL(31); end if;   -- clamp to the top entry
        return VTERM_TBL(code);
    end function;

    function ptx_vtrk_mv(code : natural) return natural is
    begin
        if code > 7 then return VTRK_TBL(0); end if;      -- clamp to the 3.00 V reset entry
        return VTRK_TBL(code);
    end function;

    function ptx_vrchg_mv(code : natural) return natural is
    begin
        if code > 15 then return VRCHG_TBL(11); end if;   -- clamp to the 3.87 V reset entry
        return VRCHG_TBL(code);
    end function;

    function ptx_limth_mv(code : natural) return natural is
    begin
        if code > 15 then return LIMTH_TBL(12); end if;   -- clamp to the 5.2 V default
        return LIMTH_TBL(code);
    end function;

    -- BC_ICHG_CTRL: ICHG = 1.96 mA * code + 1.92 mA, code 0x02 to 0x7F.
    -- Returned in microamps so the 10% trickle current and the percentage scaling do not round away to nothing.
    function ptx_ichg_ua(code : natural) return natural is
        variable c : natural := code;
    begin
        if c < 2 then c := 2; end if;
        if c > 127 then c := 127; end if;
        return 1960 * c + 1920;
    end function;

    -- BC_ITERM_CTRL: ITERM = 1.39 mA * code - 0.34 mA, code 4 to 59.
    function ptx_iterm_ua(code : natural) return natural is
        variable c : natural := code;
    begin
        if c < 4 then c := 4; end if;
        if c > 59 then c := 59; end if;
        return 1390 * c - 340;
    end function;

    -- BC_ICHG_PCT_COLD / BC_ICHG_PCT_HOT: 0=100, 1=75, 2=50, 3=25, 4=0 percent; every other code is RFU and reads as 0.
    function ptx_ichg_pct(code : natural) return natural is
    begin
        case code is
            when 0      => return 100;
            when 1      => return 75;
            when 2      => return 50;
            when 3      => return 25;
            when others => return 0;
        end case;
    end function;

end package body ptx30w_pkg;


-------------------------------------------------------------------------------
-- The device
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ptx30w_pkg.all;

entity ptx30w_model is
    generic (
        -- ---- identity / interface -------------------------------------
        G_I2C_ADDR        : std_logic_vector(6 downto 0) := "1001011";  -- 0x4B, the I2C_ADDR default
        G_IRQ_ACTIVE_HIGH : boolean := true;                            -- IRQ_POLARITY = 0b0 default
        G_CRC_MSB_FIRST   : boolean := false;                           -- CRC_B byte order in the frame; LSB byte first by default
        G_HW_VERSION      : std_logic_vector(7 downto 0)  := x"30";
        G_FW_VERSION      : std_logic_vector(15 downto 0) := x"148B";   -- 5259 decimal
        G_DIE_INFO_SEED   : std_logic_vector(7 downto 0)  := x"D0";     -- DIE_INFO[k] = seed + k
        G_OEM_VALID       : boolean := true;                            -- OEM_VALID_FLAG in the RSS block

        -- ---- standby / wake -------------------------------------------
        G_STANDBY_EN      : boolean := true;
        G_WAKE_HOLD       : time    := 100 ms;

        -- ---- power model tick + battery -------------------------------
        G_PWR_TICK        : time    := 100 us;
        G_BAT_CAP_MAH     : real    := 40.0;    -- scale DOWN in a bench that wants a full charge
        G_VBAT_INIT_MV    : natural := 2800;
        G_VBAT_EMPTY_MV   : natural := 2400;    -- soc=0.0 terminal voltage
        G_VBAT_FULL_MV    : natural := 4400;    -- soc=1.0 terminal voltage
        G_CV_DECAY        : real    := 0.97;    -- CV current taper per tick

        -- ---- rails ----------------------------------------------------
        G_VDDC_BOD_SET_MV : natural := 2500;    -- VVDDC_BOD_SET, spec range 2.2-2.8 V
        G_VDDC_BOD_RST_MV : natural := 2800;    -- VVDDC_BOD_RESET, spec range 2.30-3.25 V
        G_LDO_DROPOUT_MV  : natural := 200;
        G_VDMCU_ILIM_MA   : natural := 50;      -- IVDMCU output current limit

        -- ---- OEM/reset defaults for the parameters we act on ----------
        G_VDMCU_MODE      : std_logic_vector(1 downto 0) := "10";  -- 0b10 = 3.3 V out
        G_GPO0_CONFIG     : natural := 6;       -- 0b0110 startup circuit enable (OEM default)
        G_GPO1_CONFIG     : natural := 0;       -- 0b0000 GPO disabled (OEM default)
        G_SM_HOLD         : time    := 5 sec    -- SM low for >5 s toggles shipping mode
    );
    port (
        ---------------------------------------------------------------
        -- REAL DEVICE PINS
        ---------------------------------------------------------------
        -- I2C, open drain: scl/sda_in are the RESOLVED nets, so the bench ties the master's and the model's open-drain drivers together with a weak 'H' pull-up.
        -- '1' on a *_oe means THIS model is pulling that pin low; the model never drives an active high.
        scl     : in  std_logic;
        sda_in  : in  std_logic;
        sda_out : out std_logic := '0';
        sda_oe  : out std_logic := '0';
        scl_out : out std_logic := '0';
        scl_oe  : out std_logic := '0';   -- tied '0': this part never stretches

        irq     : out std_logic;          -- dedicated host IRQ, push-pull
        gpo0_oe : out std_logic := '0';   -- GPO_0, open drain active low
        gpo1_oe : out std_logic := '0';   -- GPO_1, open drain active low
        sm_n    : in  std_logic := '1';   -- SM push button to GND, active low

        ---------------------------------------------------------------
        -- BENCH ABSTRACTION: the analog environment the bench drives; none of these are device pins.
        ---------------------------------------------------------------
        rf_field_present : in boolean := false;  -- poller field on the antenna
        rf_available_mw  : in natural := 0;      -- DC power the rectifier can deliver
        vddc_load_ma     : in natural := 0;      -- host load taken straight off VDDC
        vdmcu_load_ma    : in natural := 0;      -- host load on the MCU LDO
        vdmcu_ext_mv     : in natural := 0;      -- only when VDMCU_MODE = 0b11 (input)
        ntc_mv           : in natural := 1400;   -- voltage on the NTC pin
        tj_degc          : in natural := 25;     -- junction temperature
        bat_connected    : in boolean := true;   -- a cell is present on VDBAT
        gpo_poller_ctl   : in std_logic := '0';  -- the "controlled by poller" GPO source, GPO_x_CONFIG 0b0101

        ---------------------------------------------------------------
        -- Reported power/charger state, in engineering units.
        ---------------------------------------------------------------
        -- vdmcu_good is a modelled supply-supervisor flag, not a pin: '1' only when the LDO is out of dropout (VDDC at least G_LDO_DROPOUT_MV above target) or the external VDMCU is inside 1.6-3.6 V, the brownout detector is clear, and the load is within the 50 mA limit.
        -- It drops the instant any of that stops holding, so gate power-on-reset with it and read vdmcu_mv for the actual millivolts.
        vdmcu_good   : out std_logic := '0';
        vdmcu_mv     : out natural := 0;
        vddc_mv      : out natural := 0;
        vbat_mv      : out natural := 0;
        ibat_ua      : out natural := 0;   -- charge current INTO the battery
        charge_state : out natural := PTX_BC_DISABLED;  -- BC_STATUS
        ntc_state    : out natural := PTX_NTC_NORMAL;   -- NTC_STATUS
        error_state  : out natural := PTX_ERR_NONE;     -- ERROR_STATUS latch
        bod_reset    : out std_logic := '0';            -- VDDC brownout asserted
        shipping     : out std_logic := '0';

        ---------------------------------------------------------------
        -- BENCH ABSTRACTION: the poller side of the transparent data channel, standing in for the NFC link.
        -- Both *_go ports are RISING-EDGE triggered.
        ---------------------------------------------------------------
        tdc_pol_go    : in  std_logic := '0';   -- "poller wrote tdc_pol_len bytes"
        tdc_pol_len   : in  natural   := 0;
        tdc_pol_data  : in  ptx_msg_t := (others => (others => '0'));
        tdc_lis_rd_go : in  std_logic := '0';   -- "poller read TDC_BUF_LIS"
        obs_lis_valid : out std_logic := '0';   -- TDC_BUF_LIS[0][7]
        obs_lis_len   : out natural   := 0;
        obs_lis_data  : out ptx_buf64_t := (others => (others => '0'));
        obs_lis_msgs  : out natural   := 0;     -- listener-to-poller messages completed

        ---------------------------------------------------------------
        -- Observability for the bench scoreboard.
        ---------------------------------------------------------------
        obs_frames     : out natural := 0;      -- HIP command frames ACCEPTED
        obs_last_nak   : out std_logic_vector(7 downto 0) := PTX_NAK_NONE;
        obs_addr_nack  : out natural := 0;      -- address NACKs (standby / dead)
        obs_msg_out    : out natural := 0       -- messages delivered to the host
    );
end entity ptx30w_model;


architecture behavioral of ptx30w_model is

    -----------------------------------------------------------------------
    -- Configuration written by the host interface (process hip, the single driver of each) and consumed by the power model (process pwr).
    -----------------------------------------------------------------------
    signal s_bc_enable   : std_logic := '1';                 -- BC_ENABLE default 0b1
    signal s_ichg_code   : natural := 16#02#;                -- 6 mA
    signal s_iterm_code  : natural := 16#0E#;                -- 19 mA
    signal s_vterm_code  : natural := 16#11#;                -- 4.18 V
    signal s_vtrk_code   : natural := 0;                     -- 3.00 V
    signal s_vrchg_code  : natural := 16#0B#;                -- 3.87 V
    signal s_pct_cold    : natural := 0;                     -- 100%
    signal s_pct_hot     : natural := 0;                     -- 100%
    signal s_voff_cold   : natural := 0;                     -- VTERM code offset
    signal s_voff_hot    : natural := 0;
    signal s_vdmcu_mode  : std_logic_vector(1 downto 0) := G_VDMCU_MODE;
    signal s_limth_code  : natural := 12;                    -- 5.2 V
    signal s_vdbat_off_h : natural := 16#40#;                -- 0.8 V (12.5 mV steps)
    signal s_vddc_th_low : natural := 16#60#;                -- 3.6 V
    signal s_ship_req    : std_logic := '0';                 -- SHIPPING_MODE_ENABLE
    signal s_batoff_en   : std_logic := '0';                 -- BC_LO_BATOFF_EN
    signal s_gpo0_cfg    : natural := G_GPO0_CONFIG;
    signal s_gpo1_cfg    : natural := G_GPO1_CONFIG;
    signal s_err_ack     : std_logic := '0';                 -- toggled when ERROR_STATUS is read
    signal s_rst_tog     : std_logic := '0';                 -- toggled by a HIP RST

    -----------------------------------------------------------------------
    -- State published by the power model (process pwr), read by `hip`.
    -----------------------------------------------------------------------
    signal s_bc_status : natural := PTX_BC_DISABLED;
    signal s_ntc_stat  : natural := PTX_NTC_NORMAL;
    signal s_err_stat  : natural := PTX_ERR_NONE;
    signal s_vbat_mv   : natural := G_VBAT_INIT_MV;
    signal s_vddc_mv   : natural := 0;
    signal s_bod       : std_logic := '0';
    signal s_ship      : std_logic := '0';
    signal s_wlcp      : natural := 0;

    signal s_irq : std_logic := '0';

    -- A boolean condition as a single std_logic level.
    function to_sl(c : boolean) return std_logic is
    begin
        if c then return '1'; else return '0'; end if;
    end function;

    -- An integer as one byte, wrapped modulo 256.
    function u8(n : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(n mod 256, 8));
    end function;

    -- VDBAT_ADC_VAL / VDDC_ADC_VAL: V = 12.5 mV * code + 2.4 V, and the code reads 0 when the ADC cannot measure (below the 2.4 V floor).
    function adc_code(mv : natural) return natural is
        variable c : natural;
    begin
        if mv < 2400 then return 0; end if;
        c := ((mv - 2400) * 10) / 125;
        if c > 255 then return 255; end if;
        return c;
    end function;

begin

    ---------------------------------------------------------------------------
    -- Pin drives that are pure functions of state.
    ---------------------------------------------------------------------------
    sda_out <= '0';           -- open drain: only ever pulls low
    scl_out <= '0';
    scl_oe  <= '0';           -- this part does not clock-stretch

    irq <= s_irq when G_IRQ_ACTIVE_HIGH else not s_irq;

    shipping  <= s_ship;
    bod_reset <= s_bod;

    ---------------------------------------------------------------------------
    -- GPO_0 / GPO_1, open drain and active low: the pin is PULLED LOW when the selected GPO_x_CONFIG condition is true.
    ---------------------------------------------------------------------------
    gpo_proc : process (s_gpo0_cfg, s_gpo1_cfg, s_err_stat, s_bc_status,
                        s_wlcp, s_ship, gpo_poller_ctl, rf_field_present)
        function gpo_level(cfg : natural; err : natural; bc : natural;
                           wlcp : natural; ship : std_logic; poller : std_logic;
                           field : boolean) return std_logic is
        begin
            case cfg is
                when 1      => return to_sl(err /= PTX_ERR_NONE);          -- error status
                when 2      => return to_sl(bc = PTX_BC_TCM or bc = PTX_BC_CCM
                                            or bc = PTX_BC_CVM);           -- charging status
                when 3      => return to_sl(field);                        -- RF field present
                when 4      => return to_sl(wlcp /= 0);                    -- poller connected
                when 5      => return poller;                              -- controlled by poller
                when 6      => return not ship;                            -- startup circuit enable
                when others => return '0';                                 -- disabled / RFU
            end case;
        end function;
    begin
        gpo0_oe <= gpo_level(s_gpo0_cfg, s_err_stat, s_bc_status, s_wlcp,
                             s_ship, gpo_poller_ctl, rf_field_present);
        -- GPO_1 has no startup-circuit-enable option: cfg 6 is RFU there and reads as disabled.
        if s_gpo1_cfg = 6 then
            gpo1_oe <= '0';
        else
            gpo1_oe <= gpo_level(s_gpo1_cfg, s_err_stat, s_bc_status, s_wlcp,
                                 s_ship, gpo_poller_ctl, rf_field_present);
        end if;
    end process gpo_proc;


    ---------------------------------------------------------------------------
    -- POWER / CHARGER MODEL: fixed-tick, integer engineering units, no electrical simulation.
    ---------------------------------------------------------------------------
    pwr : process
        constant TICK_H : real := real(G_PWR_TICK / 1 ns) / 3.6e12;  -- tick in hours

        variable soc      : real := 0.0;
        variable vbat     : natural := G_VBAT_INIT_MV;
        variable vddc     : natural := 0;
        variable vddc_tgt : natural := 0;
        variable vdmcu_t  : natural := 0;
        variable vdmcu    : natural := 0;
        variable good     : std_logic := '0';
        variable bod      : std_logic := '0';
        variable ship     : std_logic := '0';
        variable overtemp : boolean := false;

        variable bc       : natural := PTX_BC_DISABLED;
        variable i_cv_ua  : real := 0.0;
        variable i_chg    : natural := 0;   -- uA into the battery
        variable i_out    : natural := 0;   -- uA out of the battery
        variable i_avail  : natural := 0;   -- uA the field can supply at vddc
        variable i_load   : natural := 0;   -- uA the host system draws
        variable i_budget : natural := 0;
        variable i_target : natural := 0;

        variable ichg_ua, iterm_ua, vterm, vtrk, vrchg, limth : natural;
        variable pct : natural;

        variable ecold, cold, hot, ehot : boolean := false;
        variable ntc  : natural := PTX_NTC_NORMAL;
        variable err  : natural := PTX_ERR_NONE;

        variable sm_ticks   : natural := 0;
        variable sm_armed   : boolean := true;
        variable err_ack_l  : std_logic := '0';
        variable rst_tog_l  : std_logic := '0';
        variable wlcp       : natural := 0;
        variable started    : boolean := false;

        constant SM_TICKS_REQ : natural := (G_SM_HOLD / G_PWR_TICK);

        -- State of charge to terminal voltage: a straight line between the two generics.
        function v_of_soc(s : real) return natural is
            variable v : real;
        begin
            v := real(G_VBAT_EMPTY_MV)
                 + s * real(G_VBAT_FULL_MV - G_VBAT_EMPTY_MV);
            if v < 0.0 then return 0; end if;
            return natural(v);
        end function;

        -- Terminal voltage back to state of charge, the inverse of v_of_soc.
        function soc_of_v(mv : natural) return real is
        begin
            return (real(mv) - real(G_VBAT_EMPTY_MV))
                   / real(G_VBAT_FULL_MV - G_VBAT_EMPTY_MV);
        end function;
    begin
        -- power-on initial state
        soc  := soc_of_v(G_VBAT_INIT_MV);
        if soc < 0.0 then soc := 0.0; end if;
        if soc > 1.0 then soc := 1.0; end if;

        loop
            wait for G_PWR_TICK;

            ------------------------------------------------------------------
            -- HIP system reset: back to the OEM/reset charger state.
            ------------------------------------------------------------------
            if s_rst_tog /= rst_tog_l then
                rst_tog_l := s_rst_tog;
                bc        := PTX_BC_DISABLED;
                i_cv_ua   := 0.0;
                err       := PTX_ERR_NONE;
                started   := false;
            end if;

            ------------------------------------------------------------------
            -- NTC state with set/reset hysteresis; the NTC voltage FALLS as the cell gets hotter (constant 69 uA source into the thermistor).
            ------------------------------------------------------------------
            if ntc_mv >= 1785 then ecold := true;  elsif ntc_mv <  1717 then ecold := false; end if;
            if ntc_mv >= 1175 then cold  := true;  elsif ntc_mv <  1115 then cold  := false; end if;
            if ntc_mv <=  377 then hot   := true;  elsif ntc_mv >   437 then hot   := false; end if;
            if ntc_mv <=  247 then ehot  := true;  elsif ntc_mv >   305 then ehot  := false; end if;

            if    ehot  then ntc := PTX_NTC_EHOT;
            elsif hot   then ntc := PTX_NTC_HOT;
            elsif ecold then ntc := PTX_NTC_ECOLD;
            elsif cold  then ntc := PTX_NTC_COLD;
            else             ntc := PTX_NTC_NORMAL;
            end if;

            ------------------------------------------------------------------
            -- Chip over-temperature, set 120 C and reset 100 C: the RF interface detunes, so no harvest, while the host supply keeps running.
            ------------------------------------------------------------------
            if tj_degc >= 120 then overtemp := true;
            elsif tj_degc < 100 then overtemp := false; end if;

            ------------------------------------------------------------------
            -- Shipping mode: entered by the host parameter or a >5 s SM press, left by the RF field appearing or another >5 s SM press, and it isolates the battery so an unfielded part is dead.
            -- Entry on VDBAT below VBAT_LOW_TH is deliberately not modelled: it would fire during every low-battery trickle-charge test.
            ------------------------------------------------------------------
            if to_X01(sm_n) = '0' then
                if sm_ticks < SM_TICKS_REQ then sm_ticks := sm_ticks + 1; end if;
                if sm_ticks >= SM_TICKS_REQ and sm_armed then
                    ship     := not ship;
                    sm_armed := false;
                end if;
            else
                sm_ticks := 0;
                sm_armed := true;
            end if;
            if s_ship_req = '1' then ship := '1'; end if;
            if rf_field_present and not overtemp then ship := '0'; end if;

            ------------------------------------------------------------------
            -- Charger parameter decode.
            ------------------------------------------------------------------
            ichg_ua  := ptx_ichg_ua(s_ichg_code);
            iterm_ua := ptx_iterm_ua(s_iterm_code);
            limth    := ptx_limth_mv(s_limth_code);
            vtrk     := ptx_vtrk_mv(s_vtrk_code);
            vrchg    := ptx_vrchg_mv(s_vrchg_code);
            if cold and not ecold then
                if s_voff_cold >= s_vterm_code then vterm := ptx_vterm_mv(0);
                else vterm := ptx_vterm_mv(s_vterm_code - s_voff_cold); end if;
                pct := ptx_ichg_pct(s_pct_cold);
            elsif hot and not ehot then
                if s_voff_hot >= s_vterm_code then vterm := ptx_vterm_mv(0);
                else vterm := ptx_vterm_mv(s_vterm_code - s_voff_hot); end if;
                pct := ptx_ichg_pct(s_pct_hot);
            else
                vterm := ptx_vterm_mv(s_vterm_code);
                pct   := 100;
            end if;

            ------------------------------------------------------------------
            -- ERROR_STATUS, one enumerated value: battery temperature first, then battery absent, then IC temperature.
            ------------------------------------------------------------------
            if s_err_ack /= err_ack_l then
                err_ack_l := s_err_ack;
                err := PTX_ERR_NONE;        -- cleared when read
            end if;
            if ecold or ehot or (pct = 0 and (cold or hot)) then
                err := PTX_ERR_BATTEMP;
            elsif (not bat_connected) and s_batoff_en = '0' then
                err := PTX_ERR_NOBAT;
            elsif overtemp then
                err := PTX_ERR_ICTEMP;
            end if;

            ------------------------------------------------------------------
            -- Harvest and power selection: the system supply comes first and the battery is charged from the residual, or makes up the shortfall when the field cannot cover the load.
            -- VDDC target is VDBAT + VDBAT_OFFSET_HIGH clamped between VDDC_TH_LOW and LIM_TH, and the available current is rf_available_mw / VDDC.
            ------------------------------------------------------------------
            i_load := (vddc_load_ma + vdmcu_load_ma) * 1000;

            if rf_field_present and not overtemp then
                vddc_tgt := vbat + (s_vdbat_off_h * 125) / 10;
                if vddc_tgt < (s_vddc_th_low * 125) / 10 + 2400 then
                    vddc_tgt := (s_vddc_th_low * 125) / 10 + 2400;
                end if;
                if vddc_tgt > limth then vddc_tgt := limth; end if;
                if vddc_tgt < 1 then vddc_tgt := 1; end if;
                i_avail := (rf_available_mw * 1000000) / vddc_tgt;
            else
                vddc_tgt := vbat;
                i_avail  := 0;
            end if;

            if i_avail >= i_load then
                -- field covers the system: the battery gets the residual
                i_budget := i_avail - i_load;
                i_out    := 0;
                vddc     := vddc_tgt;
            elsif bat_connected and ship = '0' and vbat > 0 then
                -- battery makes up the difference; VDDC falls back to VDBAT
                i_budget := 0;
                i_out    := i_load - i_avail;
                if vddc_tgt > vbat then vddc := vbat; else vddc := vddc_tgt; end if;
            else
                -- no battery help: the rail collapses in proportion
                i_budget := 0;
                i_out    := 0;
                if i_load = 0 then
                    vddc := vddc_tgt;
                else
                    vddc := (vddc_tgt * i_avail) / i_load;
                end if;
            end if;

            ------------------------------------------------------------------
            -- Charger phase machine: TCM below VTRICKLE at 10% of ICHG, CCM at ICHG up to VTERM, CVM tapering until ITERM, DONE until vbat falls below VRCHG.
            ------------------------------------------------------------------
            if s_bc_enable = '0' or (not rf_field_present) or overtemp
               or ship = '1' or pct = 0 or ecold or ehot
               or ((not bat_connected) and s_batoff_en = '0') then
                -- With the RF field off BC_STATUS reads 0 (disabled) unless the battery is full, which keeps reading 4 (done).
                if bc /= PTX_BC_DONE then bc := PTX_BC_DISABLED; end if;
                i_target := 0;
                i_cv_ua  := 0.0;
            else
                case bc is
                    when PTX_BC_DISABLED =>
                        -- Entry arm: pick the phase that matches the present cell voltage, no current this tick.
                        if vbat < vtrk then
                            bc := PTX_BC_TCM;
                        elsif vbat < vterm then
                            bc := PTX_BC_CCM;
                        else
                            bc := PTX_BC_CVM;
                            i_cv_ua := real(ichg_ua * pct / 100);
                        end if;
                        i_target := 0;

                    when PTX_BC_TCM =>
                        -- Trickle charge below VTRICKLE.
                        i_target := (ichg_ua * pct / 100) / 10;   -- ITRICKLE = 10% of ICHG
                        if vbat >= vtrk then bc := PTX_BC_CCM; end if;

                    when PTX_BC_CCM =>
                        -- Constant current at ICHG until the cell reaches VTERM.
                        i_target := ichg_ua * pct / 100;
                        if vbat >= vterm then
                            bc      := PTX_BC_CVM;
                            i_cv_ua := real(i_target);
                        end if;

                    when PTX_BC_CVM =>
                        -- Constant voltage: the current tapers until it falls under ITERM.
                        i_cv_ua  := i_cv_ua * G_CV_DECAY;
                        i_target := natural(i_cv_ua);
                        if i_target < iterm_ua then
                            bc       := PTX_BC_DONE;
                            i_target := 0;
                        end if;

                    when others =>   -- PTX_BC_DONE: charging complete, watch for the recharge threshold
                        i_target := 0;
                        if vbat < vrchg then
                            if vbat < vtrk then bc := PTX_BC_TCM;
                            else                bc := PTX_BC_CCM; end if;
                        end if;
                end case;
                if bc /= PTX_BC_DISABLED and bc /= PTX_BC_DONE then
                    started := true;
                end if;
            end if;

            -- The charge current can never exceed the residual the field left over.
            if i_target > i_budget then i_chg := i_budget; else i_chg := i_target; end if;

            ------------------------------------------------------------------
            -- Battery integration.
            ------------------------------------------------------------------
            if bc = PTX_BC_CVM or bc = PTX_BC_DONE then
                -- CV holds the terminal voltage at VTERM while the current tapers: pin soc there so the linear soc model cannot push vbat past VTERM.
                if i_out = 0 then
                    soc := soc_of_v(vterm);
                else
                    soc := soc - (real(i_out) / 1000.0) * TICK_H / G_BAT_CAP_MAH;
                end if;
            else
                soc := soc + ((real(i_chg) - real(i_out)) / 1000.0) * TICK_H / G_BAT_CAP_MAH;
            end if;
            if soc < 0.0 then soc := 0.0; end if;
            if soc > 1.0 then soc := 1.0; end if;
            if bat_connected then vbat := v_of_soc(soc); else vbat := 0; end if;

            ------------------------------------------------------------------
            -- Brownout detector with hysteresis; while it holds, the I2C target does not answer.
            ------------------------------------------------------------------
            if vddc < G_VDDC_BOD_SET_MV then
                bod := '1';
            elsif vddc >= G_VDDC_BOD_RST_MV then
                bod := '0';
            end if;

            ------------------------------------------------------------------
            -- MCU LDO: VDMCU_MODE 0b01 gives 1.8 V out, 0b10 gives 3.3 V out, 0b11 takes VDMCU as an input; over the 50 mA limit the rail folds back.
            ------------------------------------------------------------------
            case s_vdmcu_mode is
                when "01"   => vdmcu_t := 1800;
                when "10"   => vdmcu_t := 3300;
                when others => vdmcu_t := 0;      -- 0b11 input, 0b00 RFU
            end case;

            if vdmcu_t = 0 then
                vdmcu := vdmcu_ext_mv;
                good  := to_sl(vdmcu_ext_mv >= 1600 and vdmcu_ext_mv <= 3600);
            elsif bod = '1' or vddc < vdmcu_t + G_LDO_DROPOUT_MV then
                if vddc > G_LDO_DROPOUT_MV then vdmcu := vddc - G_LDO_DROPOUT_MV;
                else                            vdmcu := 0; end if;
                if vdmcu > vdmcu_t then vdmcu := vdmcu_t; end if;
                good := '0';
            elsif vdmcu_load_ma > G_VDMCU_ILIM_MA then
                vdmcu := (vdmcu_t * G_VDMCU_ILIM_MA) / vdmcu_load_ma;  -- foldback
                good  := '0';
            else
                vdmcu := vdmcu_t;
                good  := '1';
            end if;

            ------------------------------------------------------------------
            -- WLCP_CONNECTED is derived, not driven: 0 with no field, 1 with a field, 3 once the charger has actually started a phase.
            ------------------------------------------------------------------
            if not rf_field_present then
                wlcp    := 0;
                started := false;
            elsif started then
                wlcp := 3;
            else
                wlcp := 1;
            end if;

            ------------------------------------------------------------------
            -- Publish.
            ------------------------------------------------------------------
            s_vbat_mv   <= vbat;
            s_vddc_mv   <= vddc;
            s_bc_status <= bc;
            s_ntc_stat  <= ntc;
            s_err_stat  <= err;
            s_bod       <= bod;
            s_ship      <= ship;
            s_wlcp      <= wlcp;

            vbat_mv      <= vbat;
            vddc_mv      <= vddc;
            vdmcu_mv     <= vdmcu;
            vdmcu_good   <= good;
            ibat_ua      <= i_chg;
            charge_state <= bc;
            ntc_state    <= ntc;
            error_state  <= err;
        end loop;
    end process pwr;


    ---------------------------------------------------------------------------
    -- I2C TARGET + HOST INTERFACE PROTOCOL + NSC LAYER + TDC; no timing minima are imposed, so the bench picks the bit rate.
    -- Bit engine: `edge` counts SCL rising edges since the last START, so group g = edge/9 and bit-in-group bp = edge mod 9 (group 0 is address+RnW+ACK, group N>=1 is data byte N-1 plus its ACK).
    -- Sample on the rising edge, set this model's own drive up on the falling edge.
    ---------------------------------------------------------------------------
    hip : process (scl, sda_in, tdc_pol_go, tdc_lis_rd_go)

        ---- I2C bit/frame state -----------------------------------------
        variable active   : boolean := false;
        variable edge     : natural := 0;
        variable shift    : std_logic_vector(7 downto 0) := (others => '0');
        variable is_read  : boolean := false;
        variable addr_ok  : boolean := false;
        variable rd_bytes : natural := 0;
        -- Once the master has NACKed a read byte the model must RELEASE SDA for the rest of the frame.
        -- Otherwise the phantom next byte's MSB=0 holds SDA low across the master's STOP and the STOP is never seen.
        variable read_done : boolean := false;
        variable g, bp, bidx : natural;
        variable bitv     : std_logic;

        ---- standby / wake ----------------------------------------------
        variable wake_deadline : time    := 0 ns;
        variable nack_cnt      : natural := 0;

        ---- HIP staging -------------------------------------------------
        variable rx_buf  : ptx_byte_array(0 to PTX_FRAME_MAX - 1) := (others => (others => '0'));
        variable rx_len  : natural := 0;
        variable tx_buf  : ptx_byte_array(0 to PTX_FRAME_MAX - 1) := (others => (others => '0'));
        variable tx_len  : natural := 0;
        variable tx_ptr  : natural := 0;   -- build cursor
        variable crc_en  : boolean := false;
        variable last_nak : std_logic_vector(7 downto 0) := PTX_NAK_NONE;
        variable frames   : natural := 0;
        variable pend_consume : boolean := false;

        ---- NSC output message (what RML/RMSG serve) --------------------
        variable out_buf   : ptx_msg_t := (others => (others => '0'));
        variable out_len   : natural := 0;
        variable out_valid : boolean := false;
        variable msg_out   : natural := 0;

        ---- TDC ---------------------------------------------------------
        variable pol_msg : ptx_msg_t := (others => (others => '0'));
        variable pol_len : natural := 0;
        variable pol_ptr : natural := 0;
        variable ack_pend : boolean := false;
        variable lis_buf : ptx_buf64_t := (others => (others => '0'));
        variable lis_len : natural := 0;
        variable lis_valid : boolean := false;
        variable lis_msgs  : natural := 0;
        variable pol_go_l  : std_logic := '0';
        variable lis_rd_l  : std_logic := '0';

        ---- device state ------------------------------------------------
        variable oem_done : boolean := false;
        variable n        : natural := 0;
        -- 0-based copy of a WMSG data payload: an unconstrained formal takes the ACTUAL's index range, so a raw rx_buf slice would arrive indexed from p0+1 and every d(0) below would be out of range.
        variable nsc_tmp  : ptx_msg_t := (others => (others => '0'));

        -----------------------------------------------------------------
        -- Output-message helpers
        -----------------------------------------------------------------
        -- Drop whatever was being built in the output message.
        procedure out_clear is
        begin
            out_len := 0;
        end procedure;

        -- Append one byte to the output message, silently ignoring an overflow past PTX_MSG_MAX.
        procedure out_put(b : std_logic_vector(7 downto 0)) is
        begin
            if out_len < PTX_MSG_MAX then
                out_buf(out_len) := b;
                out_len := out_len + 1;
            end if;
        end procedure;

        -- Publish the built message to the host, which also raises IRQ.
        procedure out_commit is
        begin
            out_valid := true;
        end procedure;

        -- Stage the next NSC_DATA_MSG chunk of a poller message: at most 63 payload bytes, the 64-byte TDC_BUF_POL minus its H1 header, so a 70-byte poller message arrives as 63 then 7.
        procedure stage_pol_chunk is
            variable c : natural;
        begin
            c := pol_len - pol_ptr;
            if c > PTX_NSC_DATA_MAX then c := PTX_NSC_DATA_MAX; end if;
            out_clear;
            out_put(std_logic_vector(to_unsigned(16#80# + c, 8)));
            for i in 0 to c - 1 loop
                out_put(pol_msg(pol_ptr + i));
            end loop;
            pol_ptr := pol_ptr + c;
            out_commit;
        end procedure;

        -- Called once the host has finished reading the pending message: free the output buffer and immediately hand over whatever was queued behind it (the next poller chunk, or a pending NSC_DATA_ACK).
        procedure retire_out_msg is
        begin
            out_valid := false;
            out_len   := 0;
            msg_out   := msg_out + 1;
            if ack_pend then
                ack_pend := false;
                out_clear;
                out_put(x"80");          -- NSC_DATA_ACK: opcode "10", length 0
                out_commit;
            elsif pol_ptr < pol_len then
                stage_pol_chunk;
            end if;
        end procedure;

        -----------------------------------------------------------------
        -- HIP response builders
        -----------------------------------------------------------------
        -- Open a response frame: FCB goes at byte 2, the payload builds from byte 3, LEN is filled in by resp_end.
        procedure resp_begin(op : natural; ack : boolean) is
            variable fcb : std_logic_vector(7 downto 0);
        begin
            fcb := std_logic_vector(to_unsigned(op * 16, 8));   -- OPCODE in [7:4]
            if ack    then fcb(2) := '1'; end if;   -- FCB.RAK
            if crc_en then fcb(1) := '1'; end if;   -- FCB.CRC
            tx_buf(2) := fcb;
            tx_ptr    := 3;
        end procedure;

        -- Append one byte to the response frame being built.
        procedure resp_put(b : std_logic_vector(7 downto 0)) is
        begin
            if tx_ptr < PTX_FRAME_MAX then
                tx_buf(tx_ptr) := b;
                tx_ptr := tx_ptr + 1;
            end if;
        end procedure;

        -- Close the response frame: write LEN and append the CRC when the command asked for one.
        procedure resp_end is
            variable lf : natural;
            variable c  : std_logic_vector(15 downto 0);
        begin
            lf := tx_ptr - 2;                       -- FCB + payload
            if crc_en then lf := lf + 2; end if;    -- plus the CRC bytes
            tx_buf(0) := u8(lf / 256);
            tx_buf(1) := u8(lf mod 256);
            if crc_en then
                c := ptx_crc_b(tx_buf(0 to tx_ptr - 1));
                if G_CRC_MSB_FIRST then
                    resp_put(c(15 downto 8)); resp_put(c(7 downto 0));
                else
                    resp_put(c(7 downto 0));  resp_put(c(15 downto 8));
                end if;
            end if;
            tx_len := tx_ptr;
        end procedure;

        -----------------------------------------------------------------
        -- NSC layer: `d` is the WMSG data payload and `dn` its length.
        -----------------------------------------------------------------
        procedure nsc_handle(d : ptx_byte_array; dn : natural) is
            variable op   : std_logic_vector(7 downto 0);
            variable ec   : std_logic_vector(7 downto 0);
            variable idx  : natural;
            variable id   : natural;
            variable val  : std_logic_vector(7 downto 0);
            variable dlen : natural;
        begin
            if dn = 0 then return; end if;
            op := d(0);

            if op(7 downto 6) = "10" then
                ------------------------------------------------------------
                -- NSC_DATA_MSG from the host: copied into TDC_BUF_LIS with bit 7 of H1 set, which marks the buffer full until the poller reads it.
                ------------------------------------------------------------
                dlen := to_integer(unsigned(op(5 downto 0)));
                if dlen = 0 then
                    return;                              -- NSC_DATA_ACK; nothing to do
                end if;
                if dlen > dn - 1 then dlen := dn - 1; end if;
                lis_buf := (others => (others => '0'));
                lis_buf(0) := std_logic_vector(to_unsigned(16#80# + dlen, 8));  -- H1, bit7 set
                for i in 0 to dlen - 1 loop
                    lis_buf(i + 1) := d(i + 1);
                end loop;
                lis_len   := dlen;
                lis_valid := true;
                return;                                  -- the ACK comes after the poller read

            elsif op = PTX_NSC_CONFIG then
                ------------------------------------------------------------
                -- NSC_CONFIG_CMD: one-shot OEM block, a replay is answered invalid-command.
                ------------------------------------------------------------
                if oem_done then
                    ec := PTX_EC_CMD;                    -- already executed once
                else
                    ec := PTX_EC_NONE;
                    oem_done := true;
                    -- OEM block: parameter #k lives at d(k), and the indices not decoded here have no modelled effect.
                    if dn > 3  then s_vdbat_off_h <= to_integer(unsigned(d(3))); end if;
                    if dn > 10 then s_bc_enable   <= d(10)(0); end if;
                    if dn > 11 then s_voff_cold   <= to_integer(unsigned(d(11)(2 downto 0))); end if;
                    if dn > 12 then s_voff_hot    <= to_integer(unsigned(d(12)(2 downto 0))); end if;
                    if dn > 13 then s_pct_cold    <= to_integer(unsigned(d(13)(2 downto 0))); end if;
                    if dn > 14 then s_pct_hot     <= to_integer(unsigned(d(14)(2 downto 0))); end if;
                    if dn > 15 then s_iterm_code  <= to_integer(unsigned(d(15)(5 downto 0))); end if;
                    if dn > 16 then
                        s_vtrk_code  <= to_integer(unsigned(d(16)(7 downto 5)));
                        s_vterm_code <= to_integer(unsigned(d(16)(4 downto 0)));
                    end if;
                    if dn > 17 then s_vrchg_code  <= to_integer(unsigned(d(17)(3 downto 0))); end if;
                    if dn > 18 then s_ichg_code   <= to_integer(unsigned(d(18)(6 downto 0))); end if;
                    if dn > 21 then s_vdmcu_mode  <= d(21)(1 downto 0); end if;
                    if dn > 23 then s_gpo1_cfg    <= to_integer(unsigned(d(23)(3 downto 0))); end if;
                    if dn > 24 then s_gpo0_cfg    <= to_integer(unsigned(d(24)(3 downto 0))); end if;
                    if dn > 25 then s_vddc_th_low <= to_integer(unsigned(d(25))); end if;
                end if;
                out_clear;
                out_put(PTX_NSC_CONFIG);
                out_put(ec);
                out_commit;

            elsif op = PTX_NSC_SET_PARAM then
                ------------------------------------------------------------
                -- NSC_SET_PARAM_CMD: (ID,value) pairs terminated by the EoC byte 0.
                ------------------------------------------------------------
                ec  := PTX_EC_NONE;
                idx := 1;
                while idx < dn loop
                    id := to_integer(unsigned(d(idx)));
                    exit when id = 0;                    -- EoC
                    if idx + 1 >= dn then
                        ec := PTX_EC_PARAM;              -- truncated pair
                        exit;
                    end if;
                    val := d(idx + 1);
                    case id is
                        when PTX_ID_ICHG     => s_ichg_code  <= to_integer(unsigned(val(6 downto 0)));
                        when PTX_ID_VTERM    => s_vterm_code <= to_integer(unsigned(val(4 downto 0)));
                        when PTX_ID_VTRK     => s_vtrk_code  <= to_integer(unsigned(val(7 downto 5)));
                        when PTX_ID_VRCHG    => s_vrchg_code <= to_integer(unsigned(val(3 downto 0)));
                        when PTX_ID_BC_EN    => s_bc_enable  <= val(0);
                        when PTX_ID_HOST_WPT => null;    -- stored inertly (no WPT timing here)
                        when PTX_ID_SHIP     => s_ship_req   <= val(0);
                        when PTX_ID_WPT_REQ  => null;
                        when PTX_ID_DETUNE   => null;
                        when PTX_ID_NFC_EN   => null;
                        when PTX_ID_LIM_TH   => s_limth_code <= to_integer(unsigned(val(3 downto 0)));
                        when PTX_ID_NDEF     =>
                            -- CUSTOM_NDEF_MSG: the value is a length byte followed by that many payload bytes.
                            idx := idx + to_integer(unsigned(val));
                        when others          => ec := PTX_EC_PARAM;
                    end case;
                    exit when ec /= PTX_EC_NONE;
                    idx := idx + 2;
                end loop;
                out_clear;
                out_put(PTX_NSC_SET_PARAM);
                out_put(ec);
                out_commit;

            elsif op = PTX_NSC_GET_PARAM then
                ------------------------------------------------------------
                -- NSC_GET_PARAM_CMD: opcode, EC, then the eight RD parameters in order, so the message length reads 10 bytes.
                ------------------------------------------------------------
                out_clear;
                out_put(PTX_NSC_GET_PARAM);
                out_put(PTX_EC_NONE);
                out_put("0000000" & s_bc_enable);                       -- 1 BC_ENABLE
                out_put("0000000" & to_sl(rf_field_present));           -- 2 RFF_STATUS
                out_put(u8(s_err_stat));                                -- 3 ERROR_STATUS
                out_put(u8(s_bc_status));                               -- 4 BC_STATUS
                out_put(u8(adc_code(s_vbat_mv)));                       -- 5 VDBAT_ADC_VAL
                out_put(u8(adc_code(s_vddc_mv)));                       -- 6 VDDC_ADC_VAL
                out_put(u8(s_ntc_stat));                                -- 7 NTC_STATUS
                out_put(u8(s_wlcp));                                    -- 8 WLCP_CONNECTED
                out_commit;
                s_err_ack <= not s_err_ack;   -- ERROR_STATUS is cleared when read

            else
                ------------------------------------------------------------
                -- Unknown NSC opcode: answered {opcode, invalid command}.
                ------------------------------------------------------------
                out_clear;
                out_put(op);
                out_put(PTX_EC_CMD);
                out_commit;
            end if;
        end procedure;

        -----------------------------------------------------------------
        -- HIP frame parse and dispatch: LEN(2, MSB first) then FCB, payload, optional CRC and padding, with the I2C START standing in for the SOF byte.
        -- LEN counts FCB + payload + CRC only and must be 1 to 4095; FCB is [7:4] opcode, [2] RAK, [1] CRC, and the response mirrors both the opcode and the CRC bit.
        -----------------------------------------------------------------
        procedure process_frame is
            variable lenf, opcode, np : natural;
            variable fcb  : std_logic_vector(7 downto 0);
            variable rak  : boolean;
            variable plen : natural;
            variable p0   : natural;
            variable rxc  : std_logic_vector(15 downto 0);
            variable status : ptx_byte_array(0 to PTX_RSS_LEN - 1);
        begin
            tx_len       := 0;
            pend_consume := false;
            crc_en       := false;

            -- LEN + FCB is the minimum readable frame.
            if rx_len < 3 then
                last_nak := PTX_NAK_LEN;
                return;
            end if;
            lenf := to_integer(unsigned(rx_buf(0))) * 256 + to_integer(unsigned(rx_buf(1)));
            if lenf < 1 or lenf > 4095 or rx_len < lenf + 2 or lenf + 2 > PTX_FRAME_MAX then
                last_nak := PTX_NAK_LEN;
                return;
            end if;

            fcb    := rx_buf(2);
            crc_en := (fcb(1) = '1');
            rak    := (fcb(2) = '1');
            opcode := to_integer(unsigned(fcb(7 downto 4)));
            plen   := lenf - 1;
            p0     := 3;

            if crc_en then
                if plen < 2 then
                    last_nak := PTX_NAK_LEN;
                    return;
                end if;
                plen := plen - 2;
                -- Inverted CRC_B over LEN + FCB + payload, i.e. the whole frame except SOF and padding.
                if G_CRC_MSB_FIRST then
                    rxc := rx_buf(lenf) & rx_buf(lenf + 1);
                else
                    rxc := rx_buf(lenf + 1) & rx_buf(lenf);
                end if;
                if ptx_crc_b(rx_buf(0 to lenf - 1)) /= rxc then
                    last_nak := PTX_NAK_CRC;
                    crc_en   := false;
                    return;
                end if;
            end if;

            case opcode is
                ----------------------------------------------------------
                when PTX_OP_RST =>          -- System Reset: payload must be the single byte 0x01
                    if plen /= 1 or rx_buf(p0) /= x"01" then
                        last_nak := PTX_NAK_PARAM;
                        return;
                    end if;
                    last_nak := PTX_NAK_NONE;
                    frames   := frames + 1;
                    if rak then
                        resp_begin(PTX_OP_RST, true);
                        resp_put(x"00");                       -- an ACK frame is RAK plus the single byte 0x00
                        resp_end;
                    end if;
                    -- The reset happens after the ACK is sent, so state is cleared here with the ACK frame already staged in tx_buf.
                    out_valid := false; out_len := 0;
                    pol_len := 0; pol_ptr := 0; ack_pend := false;
                    lis_valid := false; lis_len := 0;
                    s_ship_req <= '0';
                    s_rst_tog  <= not s_rst_tog;

                ----------------------------------------------------------
                when PTX_OP_RSS =>          -- Read System Status: N bytes of the 21-byte status block, truncated or zero-padded
                    if plen /= 1 then
                        last_nak := PTX_NAK_LEN;
                        return;
                    end if;
                    np := to_integer(unsigned(rx_buf(p0)));
                    if np = 0 then
                        last_nak := PTX_NAK_PARAM;
                        return;
                    end if;
                    status(0) := last_nak;                     -- ACK/NAK of the PREVIOUS command
                    status(1) := G_HW_VERSION;
                    status(2) := G_FW_VERSION(15 downto 8);
                    status(3) := G_FW_VERSION(7 downto 0);
                    for i in 0 to 15 loop
                        status(4 + i) := std_logic_vector(
                            unsigned(G_DIE_INFO_SEED) + to_unsigned(i, 8));
                    end loop;
                    if G_OEM_VALID then status(20) := x"01"; else status(20) := x"00"; end if;
                    resp_begin(PTX_OP_RSS, false);
                    for i in 0 to np - 1 loop
                        if i < PTX_RSS_LEN then resp_put(status(i));
                        else                    resp_put(x"00");   -- padded past the end of the block
                        end if;
                    end loop;
                    resp_end;
                    last_nak := PTX_NAK_NONE;
                    frames   := frames + 1;

                ----------------------------------------------------------
                when PTX_OP_WMSG =>         -- Write Message: payload is the buffer address then the data
                    if plen < 1 then
                        last_nak := PTX_NAK_LEN;
                        return;
                    end if;
                    if rx_buf(p0) /= x"00" then
                        last_nak := PTX_NAK_PARAM;             -- only input buffer 0 exists
                        return;
                    end if;
                    n := plen - 1;                             -- data length
                    if n > PTX_MSG_MAX then
                        last_nak := PTX_NAK_LEN;               -- exceeds the input buffer
                        return;
                    end if;
                    -- Write buffer full: a data message arriving while TDC_BUF_LIS still holds an unread one; control commands are never rejected this way.
                    if n >= 1 and lis_valid then
                        if rx_buf(p0 + 1)(7 downto 6) = "10"
                           and rx_buf(p0 + 1)(5 downto 0) /= "000000" then
                            last_nak := PTX_NAK_FULL;
                            return;
                        end if;
                    end if;
                    last_nak := PTX_NAK_NONE;
                    frames   := frames + 1;
                    if rak then
                        resp_begin(PTX_OP_WMSG, true);
                        resp_put(x"00");
                        resp_end;
                    end if;
                    nsc_tmp := (others => (others => '0'));
                    for i in 0 to n - 1 loop
                        nsc_tmp(i) := rx_buf(p0 + 1 + i);
                    end loop;
                    nsc_handle(nsc_tmp, n);

                ----------------------------------------------------------
                when PTX_OP_RML =>          -- Read Message Length: 0 when nothing is pending
                    if plen /= 0 then
                        last_nak := PTX_NAK_LEN;
                        return;
                    end if;
                    resp_begin(PTX_OP_RML, false);
                    if out_valid then
                        resp_put(u8(out_len / 256));
                        resp_put(u8(out_len mod 256));
                    else
                        resp_put(x"00");
                        resp_put(x"00");
                    end if;
                    resp_end;
                    last_nak := PTX_NAK_NONE;
                    frames   := frames + 1;

                ----------------------------------------------------------
                when PTX_OP_RMSG =>         -- Read Message: N bytes, zero-padded
                    if plen /= 2 then
                        last_nak := PTX_NAK_LEN;
                        return;
                    end if;
                    np := to_integer(unsigned(rx_buf(p0))) * 256
                          + to_integer(unsigned(rx_buf(p0 + 1)));
                    if np = 0 then np := out_len; end if;      -- N=0 means the whole message
                    resp_begin(PTX_OP_RMSG, false);
                    for i in 0 to np - 1 loop
                        if out_valid and i < out_len then resp_put(out_buf(i));
                        else                              resp_put(x"00");
                        end if;
                    end loop;
                    resp_end;
                    -- Retire the message only once it has really been clocked out, and only on a full-length read; a short read leaves it pending with IRQ asserted.
                    pend_consume := out_valid and (np >= out_len);
                    last_nak := PTX_NAK_NONE;
                    frames   := frames + 1;

                ----------------------------------------------------------
                when others =>
                    last_nak := PTX_NAK_CMD;                   -- undefined opcode
            end case;
        end procedure;

        -- End of a write phase (repeated START or STOP closes the command).
        procedure end_write_phase is
        begin
            if rx_len > 0 then
                process_frame;
                obs_frames   <= frames;
                obs_last_nak <= last_nak;
            end if;
            rx_len := 0;
        end procedure;

        -- End of a read phase; the pending message retires only after a full-length read.
        procedure end_read_phase is
        begin
            if pend_consume and rd_bytes >= tx_len then
                retire_out_msg;
                obs_msg_out <= msg_out;
            end if;
            pend_consume := false;
        end procedure;

        -- Mirror the listener-buffer state onto the observation ports.
        procedure publish_tdc is
        begin
            obs_lis_valid <= to_sl(lis_valid);
            obs_lis_len   <= lis_len;
            obs_lis_data  <= lis_buf;
            obs_lis_msgs  <= lis_msgs;
        end procedure;

        -- Can the I2C target answer at all: the standby rule plus the brownout and shipping-mode dead cases.
        impure function awake return boolean is
        begin
            if s_bod = '1' then return false; end if;
            if s_ship = '1' and not rf_field_present then return false; end if;
            if not G_STANDBY_EN then return true; end if;
            if rf_field_present then return true; end if;
            return now < wake_deadline;
        end function;

    begin
        ------------------------------------------------------------------
        -- BENCH ABSTRACTION: the poller wrote TDC_BUF_POL.
        ------------------------------------------------------------------
        if tdc_pol_go'event and to_X01(tdc_pol_go) = '1' and pol_go_l = '0' then
            pol_go_l := '1';
            pol_msg  := tdc_pol_data;
            pol_len  := tdc_pol_len;
            pol_ptr  := 0;
            if pol_len > 0 and not out_valid then
                stage_pol_chunk;
            end if;
        elsif tdc_pol_go'event and to_X01(tdc_pol_go) = '0' then
            pol_go_l := '0';

        ------------------------------------------------------------------
        -- BENCH ABSTRACTION: the poller read TDC_BUF_LIS.
        -- Clear TDC_BUF_LIS[0][7], then send the host the NSC_DATA_ACK that licences its next chunk.
        ------------------------------------------------------------------
        elsif tdc_lis_rd_go'event and to_X01(tdc_lis_rd_go) = '1' and lis_rd_l = '0' then
            lis_rd_l := '1';
            if lis_valid then
                lis_valid  := false;
                lis_buf(0) := lis_buf(0) and x"7F";
                lis_msgs   := lis_msgs + 1;
                if out_valid then
                    ack_pend := true;          -- delivered when the buffer frees
                else
                    out_clear;
                    out_put(x"80");            -- NSC_DATA_ACK
                    out_commit;
                end if;
            end if;
            publish_tdc;
        elsif tdc_lis_rd_go'event and to_X01(tdc_lis_rd_go) = '0' then
            lis_rd_l := '0';

        ------------------------------------------------------------------
        -- START / repeated START / STOP: SDA moves while SCL is high.
        ------------------------------------------------------------------
        elsif sda_in'event and to_X01(scl) = '1' then
            if to_X01(sda_in) = '0' then
                -- START or repeated START: close whatever phase was running.
                if active then
                    if is_read then end_read_phase; else end_write_phase; end if;
                end if;
                active    := true;
                edge      := 0;
                shift     := (others => '0');
                is_read   := false;
                addr_ok   := false;
                rd_bytes  := 0;
                read_done := false;
                sda_oe    <= '0';
            else
                -- STOP
                if active then
                    if is_read then end_read_phase; else end_write_phase; end if;
                end if;
                active := false;
                sda_oe <= '0';
            end if;

        ------------------------------------------------------------------
        -- SCL RISING EDGE: sample.
        ------------------------------------------------------------------
        elsif active and scl'event and to_X01(scl) = '1' then
            g  := edge / 9;
            bp := edge mod 9;
            if bp < 8 then
                if g = 0 or not is_read then
                    shift := shift(6 downto 0) & to_X01(sda_in);
                end if;
            else
                if g = 0 then
                    null;                       -- our address ACK, already driven
                elsif not is_read then
                    if addr_ok and rx_len < PTX_FRAME_MAX then
                        rx_buf(rx_len) := shift;
                        rx_len := rx_len + 1;
                    end if;
                else
                    rd_bytes := rd_bytes + 1;   -- master's ACK/NACK on our byte
                    if to_X01(sda_in) = '1' then
                        read_done := true;      -- NACK: release for the rest of the frame
                    end if;
                end if;
            end if;
            edge := edge + 1;

        ------------------------------------------------------------------
        -- SCL FALLING EDGE: set up this model's drive for the NEXT sample, since edge has already been incremented past that sample's index.
        ------------------------------------------------------------------
        elsif active and scl'event and to_X01(scl) = '0' then
            g  := edge / 9;
            bp := edge mod 9;

            if read_done then
                sda_oe <= '0';

            elsif g = 0 then
                if bp = 8 then
                    -- Address decision.
                    is_read := (shift(0) = '1');
                    addr_ok := (shift(7 downto 1) = G_I2C_ADDR) and awake;
                    if shift(7 downto 1) = G_I2C_ADDR then
                        -- Even a NACKed command wakes the device for at least 100 ms so the host can resend it.
                        wake_deadline := now + G_WAKE_HOLD;
                        if not addr_ok then
                            nack_cnt := nack_cnt + 1;
                            obs_addr_nack <= nack_cnt;
                        end if;
                    end if;
                    if addr_ok then
                        sda_oe <= '1';                       -- ACK: pull SDA low
                        if is_read then rd_bytes := 0; end if;
                    else
                        sda_oe <= '0';                       -- NACK: release
                    end if;
                else
                    sda_oe <= '0';                           -- master drives the address bits
                end if;

            else
                bidx := g - 1;
                if bp < 8 then
                    if is_read and addr_ok then
                        -- Past the end of the staged response the model streams 0xFF; it must not address-NACK, since that is the standby indication.
                        if bidx < tx_len then bitv := tx_buf(bidx)(7 - bp);
                        else                  bitv := '1';
                        end if;
                        if bitv = '0' then sda_oe <= '1';    -- open drain: pull low
                        else               sda_oe <= '0';    -- release, pull-up wins
                        end if;
                    else
                        sda_oe <= '0';                       -- master drives write data
                    end if;
                else
                    if is_read then
                        sda_oe <= '0';                       -- master drives ACK/NACK
                    elsif addr_ok then
                        sda_oe <= '1';                       -- we ACK every accepted byte
                    else
                        sda_oe <= '0';
                    end if;
                end if;
            end if;
        end if;

        -- IRQ tracks "a message is pending for the host": it drops when that message has been clocked out and re-asserts at once if another chunk or ACK is queued behind it.
        s_irq <= to_sl(out_valid);
        obs_lis_valid <= to_sl(lis_valid);
        obs_lis_len   <= lis_len;
        obs_lis_data  <= lis_buf;
        obs_lis_msgs  <= lis_msgs;
    end process hip;

end architecture behavioral;
