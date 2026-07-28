-------------------------------------------------------------------------------
-- st25dv_model.vhd
-------------------------------------------------------------------------------
-- Behavioral simulation model of the STMicroelectronics ST25DV64KC dynamic
-- NFC/RFID tag IC (64-Kbit EEPROM, fast transfer mode mailbox, energy
-- harvesting), as seen from the CONTACT (I2C) side. Castalia is the I2C
-- MASTER (I2C0 on pads 37/38 or I2C1 on 39/40); this model is the I2C SLAVE.
--
-- PURPOSE: firmware bring-up and board-level design exploration against a
-- plausible, datasheet-grounded device. This is NOT a sign-off model and must
-- never be treated as one -- see the LIMITATIONS + ASSUMPTIONS blocks below.
--
-- DATASHEET GROUNDING
--   ST25DV04KC / ST25DV16KC / ST25DV64KC datasheet, DS13519 Rev 2, July 2021
--   (obtained from the SparkFun mirror cdn.sparkfun.com/assets/f/5/4/e/d/
--   st25dv04kc-2450072.pdf; www.st.com and www.mouser.com were unreachable
--   from this machine -- see the model's devlog note). Section / table numbers
--   quoted below are from that document. Everything NOT traceable to a quoted
--   table is flagged as an ASSUMPTION.
--
-- WHAT THIS MODEL IMPLEMENTS
--   * The full I2C slave bit protocol on open-drain SCL/SDA: START, repeated
--     START, STOP, 8-bit device select + R/notW, 16-bit (2-byte) memory
--     address, byte / sequential write, current-address read, random address
--     read, sequential read, per-byte ACK/NACK. (DS 6.1 - 6.5.)
--   * TWO device select codes (DS Table 88 + Table 263), which is the single
--     most common ST25DV firmware bring-up trap:
--        1010 E2 E1 E0 R/notW, with I2C_DEVICE_CODE[3:0] (default 1010b) and
--        E0 (default 1b) taken LIVE from the I2C_CFG static register.
--        E1 = 1 selects a memory access; E2 = 0 -> user memory / dynamic
--        registers / FTM mailbox (A6h write, A7h read); E2 = 1 -> system
--        configuration memory (AEh write, AFh read).
--        E1 = 0 with R/notW = 0 is the I2C "RFSwitchOff" (E2=0, A2h) /
--        "RFSwitchOn" (E2=1, AAh) command pair, which is ACKed only when
--        I2C_CFG.I2C_RF_SWITCHOFF_EN is set (factory value 0 -> NACK).
--   * 8 KB (64 Kbit) user EEPROM at 0000h..1FFFh (DS Table 3), factory-
--     initialized to 00h (DS 4.2 Note).
--   * The internal write cycle: after the STOP that closes a successful EEPROM
--     write the device disconnects from the bus and NACKs its own device
--     select until programming finishes (DS 6.4, Table 265/266, Figure 33 --
--     ACK polling). Duration = T_W generic (DS Table 250: tW = 5 ms) times the
--     number of 16-byte EEPROM rows touched (DS 6.4.2). Writes to the DYNAMIC
--     REGISTERS and to the MAILBOX are immediate -- no tW, no polling needed
--     (DS 6.4.1 / 6.4.2 / the note under Figure 33).
--   * The 256-byte fast transfer mode (FTM) mailbox at 2008h..2107h with the
--     MB_CTRL_Dyn / MB_LEN_Dyn semantics of DS 5.1.2 and Figure 12:
--       - writes must start at 2008h, need MB_EN=1 and a FREE mailbox
--         (HOST_PUT_MSG=0 and RF_PUT_MSG=0), otherwise every data byte is
--         NACKed and nothing is programmed;
--       - a completed I2C message write sets MB_LEN_Dyn = length-1,
--         HOST_PUT_MSG and HOST_CURRENT_MSG (MB_CTRL_Dyn 43h);
--       - an RF message (bench stimulus, below) sets RF_PUT_MSG and
--         RF_CURRENT_MSG (MB_CTRL_Dyn 85h);
--       - RF_PUT_MSG is cleared at the STOP that follows the read of the LAST
--         message byte by I2C (MB_CTRL_Dyn 81h); an I2C read NEVER clears
--         HOST_PUT_MSG;
--       - a mailbox read past the end of the message returns FFh, no rollover.
--   * Dynamic registers at 2000h..2007h (DS Table 13): GPO_CTRL_Dyn,
--     EH_CTRL_Dyn, RF_MNGT_Dyn, I2C_SSO_Dyn (RO), IT_STS_Dyn (RO, CLEARED BY
--     READING -- DS Table 36 note), MB_CTRL_Dyn, MB_LEN_Dyn (RO). Only one
--     byte may be written per transaction (DS 4.4: "not written in
--     continuity").
--   * System configuration EEPROM at 0000h..0023h (DS Table 12) with the
--     factory values of DS Tables 30/32/39/79/81/83/85: GPO1=11h, GPO2=0Ch,
--     EH_MODE=01h, FTM=00h, I2C_CFG=1Ah, MEM_SIZE=07FFh (LSB at 0014h),
--     BLK_SIZE=03h, IC_REF=51h (ST25DV64KC), UID bytes 5/6/7 = 51h/02h/E0h.
--     0010h..0023h are read-only. Writes need an OPEN I2C security session and
--     are limited to ONE byte per transaction (DS 6.4.1 / 6.4.2).
--   * The I2C present-password / write-password commands (DS 6.6.1, 6.6.2,
--     Figures 35/36): device select E2=1 E1=1 R/notW=0, address 09h 00h, then
--     8 password bytes, a validation code (09h = present, 07h = write), then
--     the SAME 8 password bytes again. Mismatching copies abort the command.
--     A correct present opens the session (I2C_SSO_Dyn = 01h); a wrong one
--     closes it. Factory password = 0000000000000000h (DS 5.6.2).
--   * GPO (DS 5.4): open-drain pin, PULSE outputs whose width is
--     301 us - IT_TIME * 37.65 us (DS Eq. 1, IT_TIME = GPO2 bits 4..2).
--     Sources modeled: FIELD_CHANGE (GPO1 b4), RF_PUT_MSG (b5), RF_GET_MSG
--     (b6), RF_WRITE (b7), I2C_WRITE (GPO2 b0, fires at the END of the tW
--     programming), I2C_RF_OFF (GPO2 b1). The output is gated by
--     GPO_CTRL_Dyn.GPO_EN ONLY -- per DS Table 37 the dynamic bit is
--     "prevalent" and GPO1.GPO_EN alone cannot enable the pin; GPO1.GPO_EN is
--     copied into GPO_CTRL_Dyn at boot and on every GPO1 write (DS Table 34
--     notes). Events are recorded in IT_STS_Dyn even when GPO output is
--     disabled (DS Table 36 note).
--   * Energy harvesting (DS 5.5): EH_MODE static register selects the boot
--     strategy (DS Table 42: EH_MODE=0 -> EH_EN=1 at boot, EH_MODE=1 ->
--     EH_EN=0, "on demand"); writing 0 into EH_MODE at any time forces EH_EN
--     to 1, writing 1 leaves EH_EN alone. EH_CTRL_Dyn exposes EH_EN (RW),
--     EH_ON (= EH_EN), FIELD_ON and VCC_ON (DS Table 41).
--
-- WHAT THIS MODEL DOES *NOT* IMPLEMENT (deliberate, do not assume otherwise)
--   * The RF / ISO-IEC 15693 side. There is NO RF protocol here at all. The
--     rf_* input ports are a BENCH ABSTRACTION: a rising edge on one of them
--     means "a reader did that", nothing more. RF commands, anticollision,
--     inventory, Manage GPO, RF passwords and RF security sessions are absent.
--   * User-memory AREA partitioning and protection: ENDA1..3, RFA1SS..RFA4SS,
--     I2CSS and LOCK_CCFILE are storage-only. No area-border write inhibition
--     and no read/write protection of user memory is enforced. (DS 4.2.1,
--     5.6.3.) A firmware that relies on area protection will see this model be
--     permissive.
--   * The FTM watchdog (FTM.MB_WDG, DS Table 16): HOST_MISS_MSG /
--     RF_MISS_MSG are never set and a stale message never frees itself.
--   * LOCK_CFG / LOCK_DSFID / LOCK_AFI enforcement, RF configuration locking.
--   * GPO sources RF_USER, RF_ACTIVITY and RF_INTERRUPT (all driven by the RF
--     "Manage GPO" command, which does not exist here); IT_STS_Dyn bits 0..2
--     are therefore always 0.
--   * The 12-pin CMOS GPO variant (VDCG). Only the 8-pin OPEN-DRAIN GPO is
--     modeled -- gpo_oe='1' means "this model pulls GPO low".
--   * LPD (low power down) pin, standby currents, POR thresholds, any analog
--     or AC timing beyond the tW write cycle. There is NO SCL setup/hold
--     checking and the model never stretches SCL (the ST25DV has no clock
--     stretch: it NACKs instead -- hence no scl_oe port).
--
-- ASSUMPTIONS (flagged, NOT datasheet-quoted -- house style)
--   A1. tW ROW COUNT. DS 6.4.2 says the programming time is tW times the
--       number of internal EEPROM "rows of 16 bytes", but its own two worked
--       examples disagree with each other: 40 bytes from 0010h -> 3 x tW
--       (consistent with 16-byte rows aligned on address bits 3..0) while
--       40 bytes from 0008h -> 4 x tW (16-byte rows would give 3). This model
--       implements the FIRST, self-consistent reading: rows_touched =
--       last_addr/16 - first_addr/16 + 1. Do not calibrate firmware timing
--       against this number.
--   A2. PRESENT PASSWORD TIMING. DS 6.6.1 describes only a comparison, with
--       no write cycle, so this model makes a present-password command take
--       effect IMMEDIATELY at the STOP (no tW busy window). The WRITE password
--       command (validation code 07h) does trigger tW, which DS 6.6.2 states
--       explicitly.
--   A3. NACK SCOPE DURING tW. DS Table 265 shows the device NACKing its own
--       device select while busy. This model NACKs EVERY device select
--       (both A6h/A7h and AEh/AFh families) while busy, on the grounds that
--       "the serial data (SDA) signal is disabled internally, and the device
--       does not respond to any requests" (DS 6.4).
--   A4. FIRST-NACK KILLS THE WHOLE WRITE. DS 6.4.2 says "If some bytes have
--       been NotAck'ed, no internal programming is done (0 byte written)" and
--       DS 6.4 says the address counter stops incrementing after the first
--       NoAck. This model therefore latches a per-frame `dead` flag on the
--       first inhibited byte, NACKs everything after it, and commits nothing.
--   A5. E2=0 ADDRESSES ABOVE 1FFFh. DS 4.2 says user-memory reads have "no
--       roll-over" at the end of memory but does not say what a sequential
--       read walking off 1FFFh returns. Since 2000h..2107h are the dynamic
--       registers / mailbox in the SAME E2=0 space, this model simply lets the
--       counter walk into them. Addresses above 2107h read FFh.
--   A6. UID bytes 0..4. DS Table 85 says these are an ST serial number written
--       on the production line, so they have no defined value. This model uses
--       11h 22h 33h 44h 55h as an obviously-synthetic pattern; bytes 5..7
--       (51h 02h E0h) ARE the datasheet values for a ST25DV64KC-IE.
--   A7. IC_REV. DS Table 87 says "depending on revision" -- the generic
--       IC_REV_VAL (default 01h) is a placeholder, not a real revision code.
--   A8. V_EH LEVEL / CURRENT. The datasheet gives NO digital encoding of the
--       harvested level: DS 2.5 / 5.5.2 only say V_EH is an UNREGULATED analog
--       output that is High-Z when EH is off or the field is too weak, and DS
--       Figure 26 note 2 reduces it to "V_EH = 1 means some uW are available".
--       There is no I_EH table in DS13519 Rev 2. This model therefore does NOT
--       invent register bits: `veh_active` is the pure High-Z / delivering
--       flag, and `veh_avail_ua` simply ECHOES the bench-supplied `cfg_veh_ua`
--       input while delivering. Wire cfg_veh_ua from a board-level supply /
--       coupling model; it is a bench abstraction, not device behavior.
--   A9. GPO PULSE OVERLAP. Overlapping interrupt sources are not merged: each
--       new event RE-TRIGGERS the pulse (the projected waveform is replaced).
--       The datasheet does not describe collision behavior.
--  A10. BOOT TIME. DS 5.5.2 says "During boot, EH is not delivered", but gives
--       no boot duration for the I2C side, so this model boots instantly on
--       the rising edge of resetn. There is no unresponsive window after POR.
--  A11. The RFSwitchOff/On commands are decoded and ACK/NACKed per
--       I2C_CFG.I2C_RF_SWITCHOFF_EN, and RFSwitchOff raises the I2C_RF_OFF GPO
--       source, but the RF side they switch does not exist here, so the only
--       observable effect is obs_rf_off.
--  A12. I2C_WRITE ON A CONFIGURATION WRITE. DS Table 32 says the I2C_WRITE
--       interrupt fires "at completion of valid I2C write operation in
--       EEPROM"; DS Table 30's note ("the updated value is valid for the next
--       command") is written about GPO1 only. This model evaluates the GPO2
--       enable AFTER storing the written byte, so enabling I2C_WRITE_EN by
--       writing GPO2 makes THAT write raise its own interrupt. Firmware that
--       arms GPO2 should expect one extra pulse.
--
-- BUS CONVENTION (house style, tb/i3c_target_model.vhd + tb/i2c_host_model.vhd)
--   sda_out is tied '0' and only sda_oe toggles: '1' = THIS MODEL pulls SDA
--   low, '0' = released. The model NEVER drives an active high onto the
--   open-drain bus -- the testbench resolves the shared wire with a weak 'H'
--   pull and every sample is to_X01-normalized. gpo_out/gpo_oe follow the same
--   convention. The SCL edge cadence is the i3c_target_model "9-edge group"
--   technique: `edge` counts SCL RISING edges since the last START/Sr, so
--   g = edge/9 is the byte group (g=0 = device select) and bp = edge mod 9 is
--   the bit position (bp=8 = the ACK slot). SAMPLE on the rising edge, DRIVE
--   (set up the next sample) on the falling edge.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity st25dv_model is
    generic (
        -- EEPROM internal write time for ONE 16-byte row (DS Table 250: 5 ms).
        T_W        : time := 5 ms;
        -- Device-parameter registers (DS Tables 83 / 87). IC_REF 51h is the
        -- ST25DV64KC value; IC_REV is an ASSUMPTION (A7).
        IC_REF_VAL : std_logic_vector(7 downto 0) := x"51";
        IC_REV_VAL : std_logic_vector(7 downto 0) := x"01"
    );
    port (
        -- ---- power / reset -------------------------------------------------
        resetn : in std_logic := '1';   -- POR, active low; rising edge = boot
        vcc_on : in std_logic := '1';   -- VCC present (EH_CTRL_Dyn.VCC_ON, DS Table 41)

        -- ---- I2C slave, open drain (the TB resolves the shared nets) -------
        scl     : in  std_logic;
        sda_in  : in  std_logic;
        sda_out : out std_logic := '0';   -- tied '0'; only sda_oe toggles
        sda_oe  : out std_logic := '0';   -- '1' = this model pulls SDA low

        -- ---- GPO, open drain (8-pin package variant, DS 2.4.2) ------------
        gpo_out : out std_logic := '0';   -- tied '0'
        gpo_oe  : out std_logic := '0';   -- '1' = this model pulls GPO low

        -- ---- V_EH energy harvesting (see ASSUMPTION A8) --------------------
        -- eh_enabled = EH_CTRL_Dyn.EH_EN. veh_active = the pin is actually
        -- delivering (EH enabled AND an RF field is present); '0' = High-Z.
        -- veh_avail_ua echoes cfg_veh_ua while delivering: it is a BENCH
        -- ABSTRACTION for a board-level supply model, NOT a device register.
        eh_enabled   : out std_logic := '0';
        veh_active   : out std_logic := '0';
        veh_avail_ua : out natural   := 0;
        cfg_veh_ua   : in  natural   := 0;

        -- ---- RF-side stimulus: BENCH ABSTRACTION, NOT ISO/IEC 15693 --------
        -- rf_field    : level, RF carrier present (drives FIELD_ON, the
        --               FIELD_CHANGE interrupt and EH delivery).
        -- rf_put_msg  : rising edge = "a reader wrote a message into the
        --               mailbox" of rf_put_len bytes, byte i = rf_put_seed + i.
        -- rf_get_msg  : rising edge = "a reader read the whole I2C message out
        --               of the mailbox" (clears HOST_PUT_MSG).
        -- rf_write_ee : rising edge = "a reader completed an EEPROM write"
        --               (raises the RF_WRITE interrupt only; the model does
        --               NOT change user memory -- it has no RF command set).
        rf_field    : in std_logic := '0';
        rf_put_msg  : in std_logic := '0';
        rf_put_len  : in natural   := 0;
        rf_put_seed : in std_logic_vector(7 downto 0) := x"00";
        rf_get_msg  : in std_logic := '0';
        rf_write_ee : in std_logic := '0';

        -- ---- observations (for the bench scoreboard; held until changed) ---
        obs_devsel      : out std_logic_vector(7 downto 0) := (others => '0');
        obs_addr        : out natural   := 0;   -- internal address counter
        obs_txn_count   : out natural   := 0;   -- completed START..STOP frames
        obs_wcommit     : out natural   := 0;   -- committed write operations
        obs_devsel_nack : out natural   := 0;   -- device selects NACKed
        obs_busy        : out std_logic := '0'; -- internal write cycle running
        obs_it_sts      : out std_logic_vector(7 downto 0) := (others => '0');
        obs_mb_ctrl     : out std_logic_vector(7 downto 0) := (others => '0');
        obs_mb_len      : out std_logic_vector(7 downto 0) := (others => '0');
        obs_i2c_sso     : out std_logic := '0';
        obs_rf_off      : out std_logic := '0'  -- last I2C RFSwitchOff/On state
    );
end entity st25dv_model;


architecture behavioral of st25dv_model is

    type byte_mem_t is array (natural range <>) of std_logic_vector(7 downto 0);

    -- address-space landmarks (DS Tables 3, 12, 13, 14)
    constant A_USER_TOP : natural := 16#1FFF#;
    constant A_DYN_LO   : natural := 16#2000#;
    constant A_DYN_HI   : natural := 16#2007#;
    constant A_MB_LO    : natural := 16#2008#;
    constant A_MB_HI    : natural := 16#2107#;
    constant A_SYS_TOP  : natural := 16#0023#;
    constant A_SYS_RO   : natural := 16#0010#;   -- 0010h..0023h are read-only
    constant A_PWD      : natural := 16#0900#;

begin

    -- Open drain only: this model never drives either pin high.
    sda_out <= '0';
    gpo_out <= '0';

    dev : process (scl, sda_in, resetn, vcc_on,
                   rf_field, rf_put_msg, rf_get_msg, rf_write_ee, cfg_veh_ua)

        ------------------------------------------------------------------
        -- NONVOLATILE state (EEPROM; survives resetn)
        ------------------------------------------------------------------
        variable umem : byte_mem_t(0 to 8191) := (others => x"00");  -- DS 4.2 note
        variable pwd  : byte_mem_t(0 to 7)    := (others => x"00");  -- DS 5.6.2

        -- system configuration area 0000h..0023h, factory values from
        -- DS Tables 30 (GPO1=11h), 32 (GPO2=0Ch), 39 (EH_MODE=01h),
        -- 16 (FTM=00h), 90 (I2C_CFG=1Ah), 79 (MEM_SIZE=07FFh),
        -- 81 (BLK_SIZE=03h), 83 (IC_REF), 85 (UID) and 87 (IC_REV).
        variable sysr : byte_mem_t(0 to 35) := (
            16#00# => x"11",              -- GPO1   : GPO_EN + FIELD_CHANGE_EN
            16#01# => x"0C",              -- GPO2   : IT_TIME = 011b
            16#02# => x"01",              -- EH_MODE: 1 = EH on demand
            16#0E# => x"1A",              -- I2C_CFG: code 1010b, E0=1, RFSW off
            16#14# => x"FF",              -- MEM_SIZE LSB (07FFh = 2048 blocks)
            16#15# => x"07",              -- MEM_SIZE MSB
            16#16# => x"03",              -- BLK_SIZE
            16#17# => IC_REF_VAL,         -- IC_REF
            16#18# => x"11", 16#19# => x"22", 16#1A# => x"33",   -- UID 0..2 (A6)
            16#1B# => x"44", 16#1C# => x"55",                     -- UID 3..4 (A6)
            16#1D# => x"51", 16#1E# => x"02", 16#1F# => x"E0",    -- UID 5..7
            16#20# => IC_REV_VAL,         -- IC_REV (A7)
            others => x"00");

        ------------------------------------------------------------------
        -- VOLATILE state (dynamic registers + mailbox; reset at boot)
        ------------------------------------------------------------------
        variable mbox        : byte_mem_t(0 to 255) := (others => x"00");
        variable gpo_dyn_en  : std_logic := '1';   -- GPO_CTRL_Dyn b0 <= GPO1 b0
        variable eh_en       : std_logic := '0';   -- EH_MODE=01h => EH_EN=0 (DS Table 42)
        variable rf_mngt_dyn : std_logic_vector(7 downto 0) := (others => '0');
        variable sso         : std_logic := '0';   -- I2C_SSO_Dyn b0
        variable it_sts      : std_logic_vector(7 downto 0) := (others => '0');
        variable mb_ctrl     : std_logic_vector(7 downto 0) := (others => '0');
        variable mb_len      : std_logic_vector(7 downto 0) := (others => '0');
        variable rf_off_v    : std_logic := '0';

        ------------------------------------------------------------------
        -- I2C frame state
        ------------------------------------------------------------------
        variable active    : boolean := false;   -- inside START..STOP
        variable edge      : natural := 0;       -- SCL rising edges since START/Sr
        variable shift     : std_logic_vector(7 downto 0) := (others => '0');
        variable dev_ok    : boolean := false;   -- device select matched (ACKed)
        variable rfsw      : boolean := false;   -- this frame is an RFSwitch cmd
        variable is_read   : boolean := false;
        variable e2v       : std_logic := '0';
        variable base_hi   : std_logic_vector(7 downto 0) := (others => '0');
        variable base_addr : natural := 0;
        variable addr_ctr  : natural := 0;
        variable wcnt      : natural := 0;       -- data bytes accepted this frame
        variable wbuf      : byte_mem_t(0 to 255) := (others => x"00");
        variable dead      : boolean := false;   -- I2C dead state (A4)
        variable rbyte     : std_logic_vector(7 downto 0) := (others => '0');
        variable rd_dead   : boolean := false;
        variable mb_end_rd : boolean := false;   -- last mailbox message byte read
        variable busy_to   : time    := 0 ns;    -- internal write cycle end time

        variable txn_v, wcommit_v, dsnack_v : natural := 0;

        -- scratch
        variable g, bp, kk, k : natural;
        variable ackit, okv   : boolean;

        ------------------------------------------------------------------
        -- helpers (declared AFTER the variables they read)
        ------------------------------------------------------------------

        -- DS Eq. (1): pulse = 301 us - IT_TIME * 37.65 us, IT_TIME = GPO2[4:2].
        impure function gpo_pulse_len return time is
        begin
            return 301 us - to_integer(unsigned(sysr(16#01#)(4 downto 2))) * 37650 ns;
        end function;

        -- Emit one GPO pulse if `src_en` (the per-source GPO1/GPO2 enable) is
        -- set AND the output is enabled. DS Table 37: GPO_CTRL_Dyn.GPO_EN is
        -- the ONLY gate ("prevalent" over GPO1.GPO_EN).
        procedure gpo_pulse(src_en : in std_logic) is
        begin
            if src_en = '1' and gpo_dyn_en = '1' then
                gpo_oe <= '1', '0' after gpo_pulse_len;
            end if;
        end procedure;

        -- Read one byte at address `a` in space `e2` (DS 6.5). ok=false means
        -- an UNSUCCESSFUL read: the master sees FFh and the internal address
        -- counter freezes (I2C dead state).
        procedure rd_fetch(a  : in  natural;
                           e2 : in  std_logic;
                           d  : out std_logic_vector(7 downto 0);
                           ok : out boolean) is
        begin
            d  := x"FF";
            ok := false;
            if e2 = '1' then
                if a <= A_SYS_TOP then
                    d := sysr(a); ok := true;
                elsif a >= A_PWD and a <= A_PWD + 7 then
                    -- DS Table 57: readable only with the session open
                    if sso = '1' then
                        d := pwd(a - A_PWD); ok := true;
                    end if;
                end if;
            else
                if a <= A_USER_TOP then
                    d := umem(a); ok := true;
                elsif a = 16#2000# then                    -- GPO_CTRL_Dyn
                    d := "0000000" & gpo_dyn_en; ok := true;
                elsif a = 16#2001# then                    -- ST reserved
                    d := x"00"; ok := true;
                elsif a = 16#2002# then                    -- EH_CTRL_Dyn
                    d := "0000" & to_X01(vcc_on) & to_X01(rf_field) & eh_en & eh_en;
                    ok := true;
                elsif a = 16#2003# then                    -- RF_MNGT_Dyn
                    d := rf_mngt_dyn; ok := true;
                elsif a = 16#2004# then                    -- I2C_SSO_Dyn
                    d := "0000000" & sso; ok := true;
                elsif a = 16#2005# then                    -- IT_STS_Dyn
                    d := it_sts; ok := true;
                elsif a = 16#2006# then                    -- MB_CTRL_Dyn
                    d := mb_ctrl; ok := true;
                elsif a = 16#2007# then                    -- MB_LEN_Dyn
                    d := mb_len; ok := true;
                elsif a >= A_MB_LO and a <= A_MB_HI then   -- FTM mailbox
                    if mb_ctrl(0) = '1' then
                        ok := true;                        -- readable...
                        if (a - A_MB_LO) <= to_integer(unsigned(mb_len)) then
                            d := mbox(a - A_MB_LO);
                        else
                            d := x"FF";                    -- ...but past the message end (DS 5.1.2)
                        end if;
                    end if;
                end if;
            end if;
        end procedure;

        -- Write inhibition for data byte index `k` of the current frame
        -- (DS 6.4.1 bullet list + DS 6.4.2 additions). ok=true means ACK.
        procedure wr_allowed(k : in natural; ok : out boolean) is
            variable aa : natural;
        begin
            ok := false;
            aa := base_addr + k;
            if e2v = '1' then
                if base_addr = A_PWD then
                    -- present / write password command (DS 6.6): 17 data bytes.
                    -- DS 6.6.2 caution: NotACKed while FTM is active.
                    if mb_ctrl(0) = '1' then
                        ok := false;
                    elsif k < 17 then
                        ok := true;
                    end if;
                elsif base_addr <= A_SYS_TOP then
                    if k > 0 then                 ok := false;   -- one byte only (DS 6.4.2)
                    elsif sso = '0' then          ok := false;   -- session closed
                    elsif base_addr >= A_SYS_RO then ok := false; -- read-only register
                    else                          ok := true;
                    end if;
                end if;
            else
                if base_addr <= A_USER_TOP then
                    if mb_ctrl(0) = '1' then      ok := false;   -- FTM active (DS 6.4 caution)
                    elsif k >= 256 then           ok := false;   -- 256-byte limit
                    elsif aa > A_USER_TOP then    ok := false;   -- no rollover
                    else                          ok := true;
                    end if;
                elsif base_addr >= A_DYN_LO and base_addr <= A_DYN_HI then
                    if k > 0 then                 ok := false;   -- not written in continuity
                    elsif base_addr = 16#2001# or base_addr = 16#2004# or
                          base_addr = 16#2005# or base_addr = 16#2007# then
                        ok := false;                             -- read-only dynamic register
                    else                          ok := true;
                    end if;
                elsif base_addr = A_MB_LO then
                    if mb_ctrl(0) = '0' then      ok := false;   -- FTM not activated
                    elsif mb_ctrl(1) = '1' or mb_ctrl(2) = '1' then
                        ok := false;                             -- mailbox busy
                    elsif aa > A_MB_HI then       ok := false;   -- mailbox border
                    else                          ok := true;
                    end if;
                end if;
                -- base_addr in 2009h..2107h: a mailbox write must start at
                -- 2008h (DS 5.1.2) -> ok stays false.
            end if;
        end procedure;

        -- Commit the accepted write bytes at the STOP condition (DS 6.4).
        procedure commit_write is
            variable n, r0, r1, rows : natural;
            variable wt              : time;
            variable code            : std_logic_vector(7 downto 0);
            variable same            : boolean;
        begin
            n := wcnt;
            if dead or n = 0 then
                return;                                  -- A4: nothing programmed
            end if;

            wt := 0 ns;

            if e2v = '1' and base_addr = A_PWD then
                ------------------------------------------------------------
                -- I2C present / write password (DS 6.6.1 / 6.6.2)
                ------------------------------------------------------------
                if n = 17 then
                    code := wbuf(8);
                    same := true;
                    for j in 0 to 7 loop
                        if wbuf(j) /= wbuf(9 + j) then same := false; end if;
                    end loop;
                    if same then
                        if code = x"09" then                  -- PRESENT
                            sso := '1';
                            for j in 0 to 7 loop
                                if wbuf(j) /= pwd(j) then sso := '0'; end if;
                            end loop;
                            -- A2: comparison only, no write cycle
                        elsif code = x"07" then               -- WRITE password
                            if sso = '1' then
                                for j in 0 to 7 loop pwd(j) := wbuf(j); end loop;
                                wt := T_W;
                            end if;
                        end if;
                    end if;
                end if;

            elsif e2v = '1' then
                ------------------------------------------------------------
                -- system configuration EEPROM, single byte (DS 6.4.2)
                ------------------------------------------------------------
                sysr(base_addr) := wbuf(0);
                wt := T_W;
                -- side effects of the static registers that have a dynamic image
                if base_addr = 16#00# then
                    gpo_dyn_en := wbuf(0)(0);            -- DS Table 34 note
                elsif base_addr = 16#02# then
                    if wbuf(0)(0) = '0' then eh_en := '1'; end if;  -- DS 5.5.2
                elsif base_addr = 16#0D# then
                    if wbuf(0)(0) = '0' then mb_ctrl(0) := '0'; end if; -- DS Table 18 note 1
                end if;

            elsif base_addr <= A_USER_TOP then
                ------------------------------------------------------------
                -- user EEPROM (DS 6.4.1 / 6.4.2)
                ------------------------------------------------------------
                for j in 0 to n - 1 loop
                    umem(base_addr + j) := wbuf(j);
                end loop;
                r0   := base_addr / 16;
                r1   := (base_addr + n - 1) / 16;
                rows := r1 - r0 + 1;                     -- ASSUMPTION A1
                wt   := rows * T_W;

            elsif base_addr >= A_DYN_LO and base_addr <= A_DYN_HI then
                ------------------------------------------------------------
                -- dynamic registers: immediate, single byte (DS 4.4)
                ------------------------------------------------------------
                if base_addr = 16#2000# then
                    gpo_dyn_en := wbuf(0)(0);
                elsif base_addr = 16#2002# then
                    eh_en := wbuf(0)(0);
                elsif base_addr = 16#2003# then
                    rf_mngt_dyn := wbuf(0);
                elsif base_addr = 16#2006# then
                    -- MB_EN can only be set while FTM.MB_MODE is 1 (DS Table 18)
                    mb_ctrl(0) := wbuf(0)(0) and sysr(16#0D#)(0);
                    if mb_ctrl(0) = '0' then
                        mb_ctrl(7 downto 1) := (others => '0');   -- DS Figure 12: MB_CTRL_Dyn=00h
                        mb_len := (others => '0');
                    end if;
                end if;

            elsif base_addr = A_MB_LO then
                ------------------------------------------------------------
                -- FTM mailbox message from I2C: immediate (DS 5.1.2)
                ------------------------------------------------------------
                for j in 0 to n - 1 loop
                    mbox(j) := wbuf(j);
                end loop;
                mb_len     := std_logic_vector(to_unsigned(n - 1, 8));
                mb_ctrl(1) := '1';                        -- HOST_PUT_MSG
                mb_ctrl(6) := '1';                        -- HOST_CURRENT_MSG
                mb_ctrl(7) := '0';                        -- RF_CURRENT_MSG
            end if;

            wcommit_v := wcommit_v + 1;

            if wt > 0 ns then
                busy_to  := now + wt;
                obs_busy <= '1', '0' after wt;
                -- I2C_WRITE interrupt fires at COMPLETION of the write (DS Table 32)
                if sysr(16#01#)(0) = '1' and gpo_dyn_en = '1' then
                    gpo_oe <= '0', '1' after wt, '0' after wt + gpo_pulse_len;
                end if;
            end if;
        end procedure;

        -- Full boot / power-on reset of the VOLATILE state (DS 4.4, 5.5.2).
        procedure do_boot is
        begin
            gpo_dyn_en  := sysr(16#00#)(0);         -- GPO_EN copied from GPO1
            eh_en       := not sysr(16#02#)(0);     -- DS Table 42
            rf_mngt_dyn := sysr(16#03#);
            sso         := '0';
            it_sts      := (others => '0');
            mb_ctrl     := (others => '0');
            mb_len      := (others => '0');
            rf_off_v    := '0';
            active      := false;
            dev_ok      := false;
            rfsw        := false;
            is_read     := false;
            dead        := false;
            rd_dead     := false;
            mb_end_rd   := false;
            edge        := 0;
            wcnt        := 0;
            addr_ctr    := 0;
            base_addr   := 0;
            busy_to     := 0 ns;
            sda_oe      <= '0';
            gpo_oe      <= '0';
            obs_busy    <= '0';
        end procedure;

    begin
        ------------------------------------------------------------------
        -- POR / boot
        ------------------------------------------------------------------
        if resetn'event and to_X01(resetn) = '1' then
            do_boot;
        end if;

        ------------------------------------------------------------------
        -- RF-side stimulus (BENCH ABSTRACTION -- no ISO/IEC 15693 here)
        ------------------------------------------------------------------
        if rf_field'event then
            if to_X01(rf_field) = '1' then
                it_sts(4) := '1';                       -- FIELD_RISING
            else
                it_sts(3) := '1';                       -- FIELD_FALLING
            end if;
            gpo_pulse(sysr(16#00#)(4));                 -- FIELD_CHANGE_EN
        end if;

        if rf_put_msg'event and to_X01(rf_put_msg) = '1' then
            -- "an RF reader wrote a message into the mailbox": needs FTM
            -- enabled and a free mailbox (DS 5.1.2).
            if mb_ctrl(0) = '1' and mb_ctrl(1) = '0' and mb_ctrl(2) = '0'
               and rf_put_len > 0 and rf_put_len <= 256 then
                for i in 0 to rf_put_len - 1 loop
                    mbox(i) := std_logic_vector(unsigned(rf_put_seed) +
                                                to_unsigned(i mod 256, 8));
                end loop;
                mb_len     := std_logic_vector(to_unsigned(rf_put_len - 1, 8));
                mb_ctrl(2) := '1';                      -- RF_PUT_MSG
                mb_ctrl(7) := '1';                      -- RF_CURRENT_MSG
                mb_ctrl(6) := '0';                      -- HOST_CURRENT_MSG
                it_sts(5)  := '1';
                gpo_pulse(sysr(16#00#)(5));             -- RF_PUT_MSG_EN
            end if;
        end if;

        if rf_get_msg'event and to_X01(rf_get_msg) = '1' then
            -- "an RF reader read the whole I2C message": frees the mailbox by
            -- clearing HOST_PUT_MSG (DS 5.1.2). RF_CURRENT_MSG/HOST_CURRENT_MSG
            -- are NOT cleared (DS Figure 12 shows 41h).
            if mb_ctrl(0) = '1' and mb_ctrl(1) = '1' then
                mb_ctrl(1) := '0';
                it_sts(6)  := '1';
                gpo_pulse(sysr(16#00#)(6));             -- RF_GET_MSG_EN
            end if;
        end if;

        if rf_write_ee'event and to_X01(rf_write_ee) = '1' then
            it_sts(7) := '1';                           -- RF_WRITE
            gpo_pulse(sysr(16#00#)(7));                 -- RF_WRITE_EN
        end if;

        ------------------------------------------------------------------
        -- I2C bus: START / Sr / STOP, then SAMPLE (rising) / DRIVE (falling)
        ------------------------------------------------------------------
        if sda_in'event and to_X01(scl) = '1' then
            if to_X01(sda_in) = '0' then
                -- START or repeated START: (re)synchronize the frame. The
                -- internal ADDRESS COUNTER deliberately survives an Sr -- that
                -- is exactly how a random address read works (DS 6.5.1).
                edge      := 0;
                shift     := (others => '0');
                dev_ok    := false;
                rfsw      := false;
                is_read   := false;
                dead      := false;
                rd_dead   := false;
                mb_end_rd := false;
                wcnt      := 0;
                active    := true;
                sda_oe    <= '0';
            else
                -- STOP
                if active then
                    if not is_read then
                        commit_write;
                    end if;
                    if mb_end_rd then
                        -- DS 5.1.2: RF_PUT_MSG is cleared at the STOP that
                        -- follows the read of the last message byte.
                        mb_ctrl(2) := '0';
                        mb_end_rd  := false;
                    end if;
                    txn_v := txn_v + 1;
                end if;
                active := false;
                sda_oe <= '0';
            end if;

        ------------------------------------------------------------------
        -- SCL RISING edge: SAMPLE
        ------------------------------------------------------------------
        elsif active and scl'event and to_X01(scl) = '1' then
            g  := edge / 9;
            bp := edge mod 9;

            if bp < 8 then
                if g = 0 or (dev_ok and (not rfsw) and (not is_read)) then
                    shift := shift(6 downto 0) & to_X01(sda_in);
                end if;
                -- read-data bits: this model is the driver, nothing to sample.
            else
                if g = 0 then
                    null;                       -- address ACK: driven at the falling edge
                elsif dev_ok and (not rfsw) and is_read then
                    -- The byte just clocked out is complete. Apply its read
                    -- side effects and advance the counter, THEN look at the
                    -- master's ACK/NACK.
                    if not rd_dead then
                        if e2v = '0' and addr_ctr = 16#2005# then
                            it_sts := (others => '0');    -- DS Table 36 note
                        end if;
                        if e2v = '0' and addr_ctr >= A_MB_LO and addr_ctr <= A_MB_HI
                           and mb_ctrl(0) = '1'
                           and (addr_ctr - A_MB_LO) = to_integer(unsigned(mb_len)) then
                            mb_end_rd := true;
                        end if;
                        addr_ctr := addr_ctr + 1;
                    end if;
                    if to_X01(sda_in) = '1' then
                        rd_dead := true;                  -- master NACK = last byte
                    end if;
                end if;
            end if;

            edge := edge + 1;

        ------------------------------------------------------------------
        -- SCL FALLING edge: DRIVE (set up the UPCOMING sample; `edge` has
        -- already been incremented by the preceding rising edge)
        ------------------------------------------------------------------
        elsif active and scl'event and to_X01(scl) = '0' then
            g  := edge / 9;
            bp := edge mod 9;

            if g = 0 then
                if bp = 8 then
                    ----------------------------------------------------------
                    -- DEVICE SELECT decision (DS Table 88 / Table 263)
                    ----------------------------------------------------------
                    obs_devsel <= shift;
                    is_read    := (shift(0) = '1');
                    e2v        := shift(3);
                    dev_ok     := false;
                    rfsw       := false;

                    if now < busy_to then
                        dev_ok := false;                  -- ASSUMPTION A3
                    elsif shift(7 downto 4) = sysr(16#0E#)(3 downto 0)
                          and shift(1) = sysr(16#0E#)(4) then
                        if shift(2) = '1' then
                            dev_ok := true;               -- memory access
                        elsif shift(0) = '0' and sysr(16#0E#)(5) = '1' then
                            -- I2C RFSwitchOff (E2=0) / RFSwitchOn (E2=1), A11
                            dev_ok := true;
                            rfsw   := true;
                            if shift(3) = '0' then
                                rf_off_v := '1';
                                gpo_pulse(sysr(16#01#)(1));  -- I2C_RF_OFF_EN
                            else
                                rf_off_v := '0';
                            end if;
                        end if;
                    end if;

                    if dev_ok then
                        sda_oe <= '1';                    -- ACK (pull SDA low)
                    else
                        sda_oe   <= '0';                  -- NACK (release)
                        dsnack_v := dsnack_v + 1;
                    end if;
                else
                    sda_oe <= '0';                        -- master drives the address bits
                end if;

            elsif dev_ok and (not rfsw) and (not is_read) then
                ----------------------------------------------------------
                -- WRITE frame: group 1 = address MSB, group 2 = address LSB,
                -- groups 3.. = data bytes (DS 6.4).
                ----------------------------------------------------------
                if bp = 8 then
                    kk    := g - 1;
                    ackit := false;
                    if kk = 0 then
                        base_hi := shift;
                        ackit   := true;
                    elsif kk = 1 then
                        base_addr := to_integer(unsigned(base_hi)) * 256 +
                                     to_integer(unsigned(shift));
                        addr_ctr  := base_addr;
                        obs_addr  <= base_addr;
                        ackit     := true;
                    else
                        k := kk - 2;
                        if dead then
                            ackit := false;
                        else
                            wr_allowed(k, ackit);
                            if ackit then
                                wbuf(k) := shift;
                                wcnt    := k + 1;
                            else
                                dead := true;             -- A4
                            end if;
                        end if;
                    end if;
                    if ackit then sda_oe <= '1'; else sda_oe <= '0'; end if;
                else
                    sda_oe <= '0';                        -- master drives the data bits
                end if;

            elsif dev_ok and (not rfsw) and is_read then
                ----------------------------------------------------------
                -- READ frame: this model sources the data bytes (DS 6.5).
                ----------------------------------------------------------
                if bp = 0 then
                    if rd_dead then
                        rbyte := x"FF";
                    else
                        rd_fetch(addr_ctr, e2v, rbyte, okv);
                        if not okv then
                            rd_dead := true;              -- I2C dead state (DS 6.5)
                            rbyte   := x"FF";
                        end if;
                    end if;
                    obs_addr <= addr_ctr;
                end if;
                if bp < 8 then
                    if rbyte(7 - bp) = '0' then
                        sda_oe <= '1';                    -- drive a 0 low
                    else
                        sda_oe <= '0';                    -- release a 1
                    end if;
                else
                    sda_oe <= '0';                        -- master drives ACK/NACK
                end if;

            else
                sda_oe <= '0';                            -- not addressed: stay off the bus
            end if;
        end if;

        ------------------------------------------------------------------
        -- Publish observations + the V_EH abstraction (ASSUMPTION A8)
        ------------------------------------------------------------------
        obs_txn_count   <= txn_v;
        obs_wcommit     <= wcommit_v;
        obs_devsel_nack <= dsnack_v;
        obs_it_sts      <= it_sts;
        obs_mb_ctrl     <= mb_ctrl;
        obs_mb_len      <= mb_len;
        obs_i2c_sso     <= sso;
        obs_rf_off      <= rf_off_v;

        eh_enabled <= eh_en;
        if eh_en = '1' and to_X01(rf_field) = '1' then
            veh_active   <= '1';
            veh_avail_ua <= cfg_veh_ua;
        else
            veh_active   <= '0';
            veh_avail_ua <= 0;
        end if;
    end process dev;

end architecture behavioral;
