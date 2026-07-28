-------------------------------------------------------------------------------
-- ptx30w_model.vhd
-------------------------------------------------------------------------------
-- BEHAVIORAL simulation model of the Renesas PTX30W "NFC Forum Wireless
-- Charging (WLC) Listener" IC, written so a Castalia board that carries one can
-- be simulated end to end: Castalia is the I2C MASTER on I2C0 (chip pins 37/38)
-- and takes the PTX30W's dedicated IRQ pin on a GPIO.
--
-- Source: Renesas PTX30W datasheet R35DS0090EU0102 Rev.1.02, Sep 4 2024
-- (on disk at .devlog/datasheets/PTX30W_datasheet.pdf). Every section number
-- quoted below is from that document.
--
-- THIS IS NOT AN ANALOG MODEL AND NOT A SIGN-OFF MODEL.
--   There is no electrical simulation here of any kind. The rectifier, limiter,
--   LDO, charger and battery are represented by INTEGER ENGINEERING-UNIT ports
--   (millivolts, microamps, milliwatts) updated on a fixed simulation tick
--   (G_PWR_TICK). The bench DRIVES the environment (rf_field_present,
--   rf_available_mw, the load currents, ntc_mv, tj_degc) and the model REPORTS
--   the resulting rail/charger state. Use it for firmware bring-up and board
--   bring-up sequencing, never for power-integrity or accuracy claims.
--   The RF/NFC link itself is NOT modelled at all: the poller side of the
--   Transparent Data Channel is a bench-side stimulus interface (see BENCH
--   ABSTRACTION below), not an ISO/IEC 14443-3 Type A radio.
--
-- ============================================================================
-- WHAT IS MODELLED
-- ============================================================================
-- 1. PINS (section 2.2). The digital pins are modelled properly:
--      SCL / SDA  - I2C target, open drain, `*_oe` convention (see below)
--      IRQ        - dedicated host IRQ, push-pull, polarity from IRQ_POLARITY
--      GPO_0/1    - configurable open-drain active-low outputs, `*_oe`
--      SM         - shipping-mode push button, active low, >5 s to toggle
--    The supply/analog pins (VDBAT, VDDC, VDBUFC, VDMCU, NTC, VS, RF1, RF2) are
--    NOT electrical nets here. They appear as engineering-unit in/out ports:
--    RF1/RF2 collapse into (rf_field_present, rf_available_mw); VDBUFC and VS
--    have no behavioural role and are absent; VDBAT/VDDC/VDMCU/NTC appear as
--    vbat_mv / vddc_mv / vdmcu_mv / ntc_mv.
--
-- 2. I2C TARGET (section 4.8.4). 7-bit addressing, default address 0x4B
--    (parameter I2C_ADDR, section 4.8.1). Fast mode up to 1 Mbit/s -- this
--    model imposes NO timing minima, it is edge-driven off the master's SCL, so
--    the bench chooses the bit rate. Open drain both ways: the model only ever
--    PULLS LOW (sda_oe='1', sda_out='0') or RELEASES (sda_oe='0'). It never
--    drives an active high, and it never stretches SCL (scl_oe is tied '0' --
--    the datasheet documents no clock stretching for this part).
--
-- 3. STANDBY WAKE-UP (section 4.8.4, verbatim): "When PTX30W is in standby
--    mode, it cannot process the incoming command (the I2C module does not
--    acknowledge the target address). However, the command wakes up the device,
--    and the device stays in normal mode for at least 100ms for the command to
--    be resent." Modelled exactly: the FIRST addressed transfer while the part
--    is in standby is address-NACKed and arms a wake window of G_WAKE_HOLD
--    (default 100 ms); a retry inside that window is ACKed. Standby is only
--    entered with no RF field (section 4, "System supply from Battery (standby
--    mode)"), so a listener sitting on a poller always answers first time.
--
-- 4. HOST INTERFACE PROTOCOL, HIP (section 4.8.3) -- the priority item.
--    Frame = LEN(2, MSB first) | FCB | payload | optional CRC | padding.
--      * LEN counts FCB + payload + CRC, and excludes SOF, LEN and padding
--        (4.8.3.1). Valid range 1..4095; anything else is "invalid length".
--        NOTE: over I2C there is NO SOF byte -- the I2C START is the SOF. That
--        is what every worked example in 4.8.4.1-4.8.4.4 shows (the first byte
--        after the address is LEN[15:8]).
--      * FCB (Table 21): [7:4] OPCODE, [3] RFU, [2] RAK, [1] CRC, [0] RFU.
--      * CRC is CRC_B (ISO/IEC 14443-3 Type B): poly 0x1021 reflected (0x8408),
--        init 0xFFFF, result inverted. Computed over LEN+FCB+payload.
--      * Padding after the frame is discarded and is not counted in LEN.
--    Commands implemented (Table 23), all five:
--      0x1 RST  - System Reset (4.8.3.6.1). Payload DFYS; only 0x01 is valid,
--                 anything else is NAK 0x04. Reset happens AFTER the ACK.
--      0x2 RSS  - Read System Status (4.8.3.6.2 + Table 18). Payload N; N=0 is
--                 NAK 0x04. Response payload = the 21-byte status block
--                 {ACK/NAK, HW_VERSION, FW_VERSION[2], DIE_INFO[16],
--                 OEM_VALID_FLAG}, truncated or 0x00-padded to N bytes.
--      0x7 WMSG - Write Message (4.8.3.6.3). Payload = ADDR + data. Only
--                 ADDR=0 exists (4.8.2: "the Host must use the WMSG command of
--                 the HIP with an input buffer address set to 0"); any other
--                 ADDR is NAK 0x04. A write into a full input buffer is
--                 NAK 0x05, an over-long payload NAK 0x02.
--      0x8 RMSG - Read Message (4.8.3.6.5). Payload N(2, MSB first); N=0 means
--                 "the whole message". Response is N bytes, 0x00-padded.
--      0x9 RML  - Read Message Length (4.8.3.6.4). No payload; response is
--                 ML(2, MSB first), 0 when nothing is pending.
--    Response framing: the response FCB carries the SAME opcode as the command
--    and mirrors the command's CRC bit (4.8.3.1: "If CRC is included in a
--    command frame, the corresponding response frame is also included").
--    An ACK frame (4.8.3.4) sets FCB.RAK=1 and carries the single byte 0x00.
--    NO RESPONSE is produced (4.8.3.3) for an erroneous command frame, or for
--    a valid WRITE command (RST/WMSG) with FCB.RAK=0. The NAK value is stored
--    and is readable as the first byte of the next RSS response (Table 22:
--    0x01 invalid command, 0x02 invalid length, 0x03 CRC error, 0x04 invalid
--    parameter, 0x05 write buffer full).
--
-- 5. NSC LAYER over HIP (section 4.8.2), i.e. what a WMSG payload/RMSG payload
--    actually contains:
--      0x01 NSC_CONFIG_CMD    - one-shot OEM parameter block (4.8.2.1).
--                               Response {0x01, EC}.
--      0x02 NSC_SET_PARAM_CMD - (ID,value) list terminated by 0x00 EoC
--                               (4.8.2.2 + Table 16). Response {0x02, EC}.
--      0x03 NSC_GET_PARAM_CMD - Response {0x03, EC, then the eight RD
--                               parameters of Table 17 in order: BC_ENABLE,
--                               RFF_STATUS, ERROR_STATUS, BC_STATUS,
--                               VDBAT_ADC_VAL, VDDC_ADC_VAL, NTC_STATUS,
--                               WLCP_CONNECTED} = 10 bytes, which is exactly
--                               the RML=0x0A shown in Figure 36.
--      0x80 NSC_DATA_MSG      - top two bits "10", low six bits = payload
--                               length 0..63 (Table 19). Length 0 with no
--                               payload is NSC_DATA_ACK (Figure 24).
--    Error codes (Table 20): 0x00 none, 0x01 invalid command, 0x02 invalid
--    parameter, 0x03 NVM write error.
--    IRQ (4.8.2, receive sequence): the model asserts IRQ whenever a message is
--    pending in its output buffer; the host clears it by (1) RML to learn the
--    length and (2) RMSG to read it. IRQ drops when the pending message has
--    actually been clocked out (end of the RMSG read frame), and re-asserts
--    immediately if another chunk/ACK is already queued behind it.
--
-- 6. TRANSPARENT DATA CHANNEL, TDC (section 4.6.2). Two 64-byte buffers,
--    TDC_BUF_POL (poller -> listener) and TDC_BUF_LIS (listener -> poller),
--    with the datasheet's buffer-free / buffer-full handshake:
--      poller->host: on a poller write the model turns the message into
--        NSC_DATA_MSG chunks of at most 63 payload bytes (one buffer-full each,
--        H1 + 63 data = the 64-byte buffer) and delivers them ONE AT A TIME.
--        Only when the host has read chunk k (step 18: "After the
--        NSC_DATA_MSG has been read by the Host, the listener sets the first
--        byte of TDC_BUF_POL[0] to 0, indicating to the poller that the buffer
--        is free") does the next chunk appear and IRQ re-assert. A 70-byte
--        poller message therefore arrives as 63 + 7, exactly Figure 10.
--      host->poller: an NSC_DATA_MSG written by the host is copied into
--        TDC_BUF_LIS, byte 0 = H1 with bit 7 set ("If TDC_BUF_LIS[0][7] bit is
--        set, the buffer contains a valid message"). While that bit is set the
--        input buffer is FULL and a further data WMSG is rejected with HIP
--        NAK 0x05. When the poller has read it, the model clears bit 7 and
--        sends the host an NSC_DATA_ACK (step 6), which is the host's licence
--        to send the next chunk (4.8.2.5.2 flow control).
--
-- 7. POWER PATH / CHARGER, as an abstraction (sections 3.4, 4.1-4.5).
--      * Harvest: rf_available_mw is the DC power the rectifier can deliver.
--        VDDC target = clamp(VDBAT + VDBAT_OFFSET_HIGH, VDDC_TH_LOW, LIM_TH)
--        (the section 4.6.1.1 regulation windows, with LIM_TH default 5.2 V).
--        Available current = rf_available_mw / VDDC.
--      * Power selector (4.5.1) with the datasheet's priority: system supply
--        first, battery charged from the RESIDUAL current; if the system needs
--        more than the field provides the battery makes up the difference; with
--        no field at all everything comes from the battery.
--      * MCU LDO (4.2, 3.4 "VDMCU pin"): VDMCU_MODE 0b01 = 1.8 V out,
--        0b10 = 3.3 V out, 0b11 = input (the PTX30WCC16D7A2 variant, where
--        vdmcu_ext_mv is the externally supplied reference). Output range
--        1.6-3.6 V, output current limit IVDMCU = 50 mA -- above that the model
--        folds the rail back (vdmcu_mv = target*50/load) and drops vdmcu_good.
--      * VDDC brownout (3.4 "Brownout Reset Voltage Thresholds"): VVDDC_BOD_SET
--        (reset threshold, 2.2-2.8 V, default midpoint 2.5 V) asserts the
--        internal reset; VVDDC_BOD_RESET (power-up threshold, 2.30-3.25 V,
--        default 2.8 V) releases it. While the BOD holds the part in reset the
--        I2C target does not answer.
--      * Charger phase machine (4.4 + Figure 5 + Table 12):
--          TCM  vbat <  VTRICKLE            I = 10% of ICHG
--          CCM  VTRICKLE <= vbat < VTERM    I = ICHG
--          CVM  vbat >= VTERM               V clamped, I decays
--          DONE I < ITERM                   charging complete
--          recharge when vbat < VRCHG
--        Thresholds come from the parameter tables in 4.8.1:
--          ICHG  = 1.96 mA * BC_ICHG_CTRL + 1.92 mA (code 0x02..0x7F)
--          ITERM = 1.39 mA * BC_ITERM_CTRL - 0.34 mA (code 4..59)
--          VTERM  from the 32-entry BC_VTERM_CTRL table (0x00=3.59 V ..
--                 0x1F=4.65 V; note the datasheet's "3 bits" size column is a
--                 typo, Table 16 gives bitfield 4:0)
--          VTRK   from the 8-entry BC_VTRK_CTRL table (0b000=3.00 V ...)
--          VRCHG  from the 16-entry BC_VRCHG_CTRL table (0b0000=2.91 V ...)
--        BC_STATUS follows Table 12: with the RF field off the status reads 0
--        (disabled) unless the battery is full, which reads 4.
--      * NTC (4.4.2 + 3.4 "NTC Monitor Specifications"): ntc_mv is compared
--        against the eCold/Cold/Hot/eHot set and reset thresholds WITH their
--        datasheet hysteresis; the model reports NTC_STATUS (0x00 normal,
--        0x02 cold, 0x03 eCold, 0x04 hot, 0x0C eHot) and scales or stops the
--        charge current per BC_ICHG_PCT_COLD / BC_ICHG_PCT_HOT.
--      * Chip over-temperature (section 4, "Chip Over-Temperature"):
--        tj_degc >= TJ_ALERT_SET (120 C) detunes the RF interface (no harvest,
--        no NFC) until it drops below TJ_ALERT_RESET (100 C); the host supply
--        keeps running.
--      * Shipping mode (4.4): entered by SHIPPING_MODE_ENABLE or by SM held low
--        for >5 s; left by the RF field appearing or by another >5 s SM press.
--        In shipping mode the battery is isolated, so with no field there is no
--        supply and the I2C target is dead. The third documented entry path
--        (VDBAT below VBAT_LOW_TH = 3.0 V) is deliberately NOT modelled: it
--        would fire during every low-battery trickle-charge test.
--
-- ============================================================================
-- BENCH ABSTRACTION (explicitly NOT part of the device)
-- ============================================================================
-- Everything below the "-- BENCH ABSTRACTION" comment in the port list exists
-- only so a testbench can play the roles the model refuses to simulate:
--   rf_field_present / rf_available_mw / vddc_load_ma / vdmcu_load_ma /
--   vdmcu_ext_mv / ntc_mv / tj_degc / bat_connected -- the analog environment.
--   tdc_pol_go / tdc_pol_len / tdc_pol_data -- "the poller just wrote N bytes
--     into TDC_BUF_POL". This stands in for the NFC Forum T2T WRITE sequence of
--     Figure 10 (or the proprietary PTX write of Figure 11); the model does the
--     buffer-size chunking that those figures describe, but there is no RF
--     link, no T2T block addressing and no NFC frame anywhere in this file.
--   tdc_lis_rd_go / obs_lis_* -- "the poller just read TDC_BUF_LIS". Stands in
--     for the T2T READ sequence of Figure 12 / the PTX read of Figure 13.
--   gpo_poller_ctl -- the "controlled by poller" GPO source (4.8.1
--     GPO_x_CONFIG = 0b0101), which really comes over the RF link.
--   vdmcu_good -- THERE IS NO SUCH PIN ON THE REAL PART. It is a modelled
--     status flag with the semantics defined at its declaration; on a real
--     board this is what an external supply supervisor watching VDMCU would
--     produce, and it is the signal a Castalia board would gate its POR with.
--
-- ============================================================================
-- ASSUMPTIONS (datasheet does not specify; flagged here, house style)
-- ============================================================================
-- A1. HIP PAYLOAD BYTE ORDER FOR THE CRC FIELD. 4.8.3.1 says multi-byte
--     parameters are MSB first "unless otherwise specified" but CRC_B is
--     conventionally transmitted least-significant byte first, and the
--     datasheet's worked examples never enable CRC. The model transmits and
--     expects CRC_B LSB-byte-first; generic G_CRC_MSB_FIRST flips it if silicon
--     disagrees.
-- A2. READ WITH NOTHING STAGED. The datasheet says only that no response is
--     sent. It does not say what the I2C target does if the host reads anyway.
--     This model ACKs the address (the part is awake) and streams 0xFF. It does
--     NOT address-NACK, because an address NACK is the standby indication
--     (item 3) and conflating the two would mislead firmware.
-- A3. WHEN THE PENDING MESSAGE IS RETIRED. Modelled at the END of the RMSG read
--     frame, once the host has actually clocked out at least ML bytes -- not at
--     RMSG command-parse time. A short read (N < ML) leaves the message pending
--     and IRQ asserted.
-- A4. "INPUT BUFFER FULL" (NAK 0x05) is modelled as "TDC_BUF_LIS still holds an
--     unread listener->poller message". Control commands (CONFIG/SET_PARAM/
--     GET_PARAM) are never rejected for buffer-full; only NSC_DATA_MSGs are.
-- A5. NSC_CONFIG_CMD replay. 4.8.2.1 says the command "is executed only once
--     and is deactivated afterwards" but gives no error code for the second
--     attempt; this model answers EC=0x01 (invalid command).
-- A6. UNKNOWN NSC OPCODE. Answered as {opcode, 0x01} (invalid command). The
--     datasheet defines no such response.
-- A7. GPO ACTIVE LEVEL. 2.2 calls the GPOs "open drain, internal pull-up,
--     active low" and 4.8.1 lists the selectable SOURCES but never states the
--     mapping. This model pulls the pin LOW when the selected condition is
--     TRUE (error present / charging / field present / poller connected).
-- A8. ERROR_STATUS IS AN ENUMERATION, NOT A BITFIELD. The Table values overlap
--     bitwise (0x0C "TCM timeout" is 0x04|0x08), so the model reports ONE value
--     with priority battery-temperature > battery-not-connected > IC-temperature.
--     Charging timeouts (0x0C/0x10/0x14) are NOT modelled at all.
-- A9. WLCP_CONNECTED is derived, not driven: 0b00 with no field, 0b01 with a
--     field, 0b11 once the charger has actually started a phase. The real value
--     tracks WLCP-INFO/WLCL-CTL records over the (unmodelled) RF link.
-- A10. CV taper. Real CV current decays over minutes; a fixed per-tick decay
--     factor G_CV_DECAY is used so a simulation reaches termination in a
--     sensible number of ticks. G_BAT_CAP_MAH is likewise expected to be scaled
--     down by a bench that wants to see a full charge inside a sim.
-- A11. OEM parameter block indices. Section 4.8.2.1's byte-index table is only
--     partly legible in the PDF's text layer; the model applies the entries it
--     could read (see APPLY_OEM below) and stores the rest inertly.
--
-- ============================================================================
-- NOT MODELLED, deliberately
-- ============================================================================
--   * The RF link: NFC Type 2 Tag activation/anticollision, the T2T and
--     proprietary PTX READ/WRITE commands (4.7.2), the T2T memory map (4.7.3),
--     the custom NDEF record (4.7.4), load modulation, the UID (4.7.1).
--   * The WLC power-negotiation protocol itself: WPT cycles, ADJ/TCM/CCM/CVM
--     WPT durations, WLCL-CTL/WLCP-INFO records, WPT_REQ (4.6, 4.6.1). The
--     parameters are stored, but no cycle timing is generated.
--   * Any real timing: I2C setup/hold/frequency limits, the 100 ms wake window
--     is a plain deadline, NVM write time, ADC conversion time.
--   * The startup circuit (4.4.1), overvoltage limiter current sensing (4.3),
--     antenna detuning as an RF effect (only the "no harvest" consequence),
--     charging timeouts, battery short/overcurrent protection, thermal
--     regulation of the charge current.
--   * DIE_INFO / HW / FW version content: these are generics, not real values.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------
-- Support package (kept in this file so the model + its bench are the whole
-- deliverable -- no third file to register).
-------------------------------------------------------------------------------
package ptx30w_pkg is

    type ptx_byte_array is array (natural range <>) of std_logic_vector(7 downto 0);

    -- Buffer/geometry constants, all from the datasheet.
    constant PTX_TDC_BUF_SIZE : natural := 64;    -- 4.6.2: two 64-byte buffers
    constant PTX_NSC_DATA_MAX : natural := 63;    -- Table 19: 6-bit length field
    constant PTX_MSG_MAX      : natural := 264;   -- 4.8.2: "256+8 bytes"
    constant PTX_FRAME_MAX    : natural := 300;   -- HIP frame staging (LEN+FCB+payload+CRC)
    constant PTX_RSS_LEN      : natural := 21;    -- Table 18: 1+1+2+16+1

    subtype ptx_msg_t   is ptx_byte_array(0 to PTX_MSG_MAX - 1);
    subtype ptx_buf64_t is ptx_byte_array(0 to PTX_TDC_BUF_SIZE - 1);

    -- HIP opcodes (Table 23)
    constant PTX_OP_RST  : natural := 16#1#;
    constant PTX_OP_RSS  : natural := 16#2#;
    constant PTX_OP_WMSG : natural := 16#7#;
    constant PTX_OP_RMSG : natural := 16#8#;
    constant PTX_OP_RML  : natural := 16#9#;

    -- HIP ACK/NAK values (Table 22)
    constant PTX_NAK_NONE  : std_logic_vector(7 downto 0) := x"00";
    constant PTX_NAK_CMD   : std_logic_vector(7 downto 0) := x"01";
    constant PTX_NAK_LEN   : std_logic_vector(7 downto 0) := x"02";
    constant PTX_NAK_CRC   : std_logic_vector(7 downto 0) := x"03";
    constant PTX_NAK_PARAM : std_logic_vector(7 downto 0) := x"04";
    constant PTX_NAK_FULL  : std_logic_vector(7 downto 0) := x"05";

    -- NSC opcodes (4.8.2.1 .. 4.8.2.5)
    constant PTX_NSC_CONFIG    : std_logic_vector(7 downto 0) := x"01";
    constant PTX_NSC_SET_PARAM : std_logic_vector(7 downto 0) := x"02";
    constant PTX_NSC_GET_PARAM : std_logic_vector(7 downto 0) := x"03";

    -- NSC error codes (Table 20)
    constant PTX_EC_NONE  : std_logic_vector(7 downto 0) := x"00";
    constant PTX_EC_CMD   : std_logic_vector(7 downto 0) := x"01";
    constant PTX_EC_PARAM : std_logic_vector(7 downto 0) := x"02";
    constant PTX_EC_NVM   : std_logic_vector(7 downto 0) := x"03";

    -- BC_STATUS values (Table 12 / 4.8.1)
    constant PTX_BC_DISABLED : natural := 0;
    constant PTX_BC_TCM      : natural := 1;
    constant PTX_BC_CCM      : natural := 2;
    constant PTX_BC_CVM      : natural := 3;
    constant PTX_BC_DONE     : natural := 4;

    -- NTC_STATUS values (4.8.1)
    constant PTX_NTC_NORMAL : natural := 16#00#;
    constant PTX_NTC_COLD   : natural := 16#02#;
    constant PTX_NTC_ECOLD  : natural := 16#03#;
    constant PTX_NTC_HOT    : natural := 16#04#;
    constant PTX_NTC_EHOT   : natural := 16#0C#;

    -- ERROR_STATUS values actually produced (4.8.1; see ASSUMPTION A8)
    constant PTX_ERR_NONE    : natural := 16#00#;
    constant PTX_ERR_ICTEMP  : natural := 16#01#;
    constant PTX_ERR_NOBAT   : natural := 16#04#;
    constant PTX_ERR_BATTEMP : natural := 16#08#;

    -- NSC WR parameter IDs (Table 16)
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

    -- CRC_B, ISO/IEC 14443-3 Type B (4.8.3.1): poly 0x8408 reflected,
    -- init 0xFFFF, final inversion. Returns the 16-bit value; the byte order it
    -- is placed in the frame with is a model generic (ASSUMPTION A1).
    function ptx_crc_b(d : ptx_byte_array) return std_logic_vector;

    -- Charger threshold/current decode tables from section 4.8.1.
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

    -- BC_VTERM_CTRL table, 4.8.1 (millivolts). Codes 0x00..0x1F.
    type mv_tbl32 is array (0 to 31) of natural;
    constant VTERM_TBL : mv_tbl32 :=
        (3590, 3620, 3650, 3670, 3700, 3730, 3750, 3810,
         3830, 3860, 3910, 3940, 3970, 4020, 4080, 4130,
         4160, 4180, 4240, 4260, 4290, 4320, 4340, 4400,
         4420, 4450, 4510, 4530, 4560, 4590, 4610, 4650);

    type mv_tbl8 is array (0 to 7) of natural;
    -- BC_VTRK_CTRL table, 4.8.1 (millivolts). Note the non-monotonic code order.
    constant VTRK_TBL : mv_tbl8 := (3000, 2500, 2600, 2700, 2800, 2900, 3100, 3200);

    type mv_tbl16 is array (0 to 15) of natural;
    -- BC_VRCHG_CTRL table, 4.8.1 (millivolts).
    constant VRCHG_TBL : mv_tbl16 :=
        (2910, 3020, 3130, 3230, 3340, 3440, 3550, 3660,
         3730, 3770, 3820, 3870, 4040, 4200, 4300, 4420);
    -- LIM_TH_SEL table, 4.8.1 (millivolts); codes 0..2 are invalid, 13..15 too.
    constant LIMTH_TBL : mv_tbl16 :=
        (5200, 5200, 5200, 3400, 3600, 3800, 4000, 4200,
         4400, 4600, 4800, 5000, 5200, 5200, 5200, 5200);

    function ptx_vterm_mv(code : natural) return natural is
    begin
        if code > 31 then return VTERM_TBL(31); end if;
        return VTERM_TBL(code);
    end function;

    function ptx_vtrk_mv(code : natural) return natural is
    begin
        if code > 7 then return VTRK_TBL(0); end if;
        return VTRK_TBL(code);
    end function;

    function ptx_vrchg_mv(code : natural) return natural is
    begin
        if code > 15 then return VRCHG_TBL(11); end if;
        return VRCHG_TBL(code);
    end function;

    function ptx_limth_mv(code : natural) return natural is
    begin
        if code > 15 then return LIMTH_TBL(12); end if;
        return LIMTH_TBL(code);
    end function;

    -- 4.8.1 BC_ICHG_CTRL: ICHG = 1.96 mA * ICHG_CODE + 1.92 mA, code 0x02..0x7F.
    -- Returned in microamps so the phase machine can carry the 10% trickle
    -- current and the percentage scaling without rounding to nothing.
    function ptx_ichg_ua(code : natural) return natural is
        variable c : natural := code;
    begin
        if c < 2 then c := 2; end if;
        if c > 127 then c := 127; end if;
        return 1960 * c + 1920;
    end function;

    -- 4.8.1 BC_ITERM_CTRL: ITERM = 1.39 mA * code - 0.34 mA, code 4..59.
    function ptx_iterm_ua(code : natural) return natural is
        variable c : natural := code;
    begin
        if c < 4 then c := 4; end if;
        if c > 59 then c := 59; end if;
        return 1390 * c - 340;
    end function;

    -- 4.8.1 BC_ICHG_PCT_COLD / BC_ICHG_PCT_HOT: 0=100, 1=75, 2=50, 3=25,
    -- 4=0 percent; "others: RFU (is interpreted as 0)".
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
        G_I2C_ADDR        : std_logic_vector(6 downto 0) := "1001011";  -- 0x4B (I2C_ADDR default, 4.8.1)
        G_IRQ_ACTIVE_HIGH : boolean := true;                            -- IRQ_POLARITY = 0b0 default
        G_CRC_MSB_FIRST   : boolean := false;                           -- see ASSUMPTION A1
        G_HW_VERSION      : std_logic_vector(7 downto 0)  := x"30";
        G_FW_VERSION      : std_logic_vector(15 downto 0) := x"148B";   -- 5259 decimal
        G_DIE_INFO_SEED   : std_logic_vector(7 downto 0)  := x"D0";     -- DIE_INFO[k] = seed + k
        G_OEM_VALID       : boolean := true;                            -- OEM_VALID_FLAG in the RSS block

        -- ---- standby / wake (4.8.4) -----------------------------------
        G_STANDBY_EN      : boolean := true;
        G_WAKE_HOLD       : time    := 100 ms;

        -- ---- power model tick + battery (see ASSUMPTION A10) ----------
        G_PWR_TICK        : time    := 100 us;
        G_BAT_CAP_MAH     : real    := 40.0;    -- scale DOWN in a bench that wants a full charge
        G_VBAT_INIT_MV    : natural := 2800;
        G_VBAT_EMPTY_MV   : natural := 2400;    -- soc=0.0 terminal voltage
        G_VBAT_FULL_MV    : natural := 4400;    -- soc=1.0 terminal voltage
        G_CV_DECAY        : real    := 0.97;    -- CV current taper per tick

        -- ---- rails ----------------------------------------------------
        G_VDDC_BOD_SET_MV : natural := 2500;    -- VVDDC_BOD_SET  (3.4: 2.2-2.8 V)
        G_VDDC_BOD_RST_MV : natural := 2800;    -- VVDDC_BOD_RESET(3.4: 2.30-3.25 V)
        G_LDO_DROPOUT_MV  : natural := 200;
        G_VDMCU_ILIM_MA   : natural := 50;      -- IVDMCU (3.4)

        -- ---- OEM/reset defaults for the parameters we act on ----------
        G_VDMCU_MODE      : std_logic_vector(1 downto 0) := "10";  -- 0b10 = 3.3 V out
        G_GPO0_CONFIG     : natural := 6;       -- 0b0110 startup circuit enable (OEM default)
        G_GPO1_CONFIG     : natural := 0;       -- 0b0000 GPO disabled (OEM default)
        G_SM_HOLD         : time    := 5 sec    -- 4.4: SM low for >5 s toggles shipping mode
    );
    port (
        ---------------------------------------------------------------
        -- REAL DEVICE PINS (section 2.2)
        ---------------------------------------------------------------
        -- I2C, open drain. scl/sda_in are the RESOLVED nets (the bench ties the
        -- master's and the model's open-drain drivers together with a weak 'H'
        -- pull-up). '1' on a *_oe means THIS model is pulling that pin low.
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
        -- BENCH ABSTRACTION: the analog environment the bench drives.
        -- NONE of these are device pins.
        ---------------------------------------------------------------
        rf_field_present : in boolean := false;  -- poller field on the antenna
        rf_available_mw  : in natural := 0;      -- DC power the rectifier can deliver
        vddc_load_ma     : in natural := 0;      -- host load taken straight off VDDC
        vdmcu_load_ma    : in natural := 0;      -- host load on the MCU LDO
        vdmcu_ext_mv     : in natural := 0;      -- only when VDMCU_MODE = 0b11 (input)
        ntc_mv           : in natural := 1400;   -- voltage on the NTC pin
        tj_degc          : in natural := 25;     -- junction temperature
        bat_connected    : in boolean := true;   -- a cell is present on VDBAT
        gpo_poller_ctl   : in std_logic := '0';  -- GPO_x_CONFIG = 0b0101 source

        ---------------------------------------------------------------
        -- Reported power/charger state, in engineering units.
        ---------------------------------------------------------------
        -- vdmcu_good SEMANTICS (there is no such pin on the real part; see the
        -- BENCH ABSTRACTION note in the header). '1' means, and only means:
        --   * the MCU LDO is configured as an OUTPUT (VDMCU_MODE 0b01/0b10) and
        --     is enabled, or is configured as an INPUT and the externally
        --     supplied VDMCU is inside the datasheet's 1.6-3.6 V input range;
        --   * the VDDC brownout detector is NOT asserted;
        --   * VDDC is at least G_LDO_DROPOUT_MV above the programmed VDMCU
        --     target, so the LDO is out of dropout;
        --   * the VDMCU load is within the 50 mA IVDMCU limit;
        -- i.e. VDMCU is sitting at its programmed 1.8 V / 3.3 V target and may
        -- be trusted as a Castalia core/IO supply. It goes '0' the instant any
        -- of those stops being true. Treat it as the output of a supply
        -- supervisor: gate power-on-reset with it, do not use it as a
        -- millivolt measurement (that is vdmcu_mv).
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
        -- BENCH ABSTRACTION: the poller side of the Transparent Data
        -- Channel. Stands in for the NFC link; see section 4.6.2 and the
        -- header. Both *_go ports are RISING-EDGE triggered.
        ---------------------------------------------------------------
        tdc_pol_go    : in  std_logic := '0';   -- "poller wrote tdc_pol_len bytes"
        tdc_pol_len   : in  natural   := 0;
        tdc_pol_data  : in  ptx_msg_t := (others => (others => '0'));
        tdc_lis_rd_go : in  std_logic := '0';   -- "poller read TDC_BUF_LIS"
        obs_lis_valid : out std_logic := '0';   -- TDC_BUF_LIS[0][7]
        obs_lis_len   : out natural   := 0;
        obs_lis_data  : out ptx_buf64_t := (others => (others => '0'));
        obs_lis_msgs  : out natural   := 0;     -- listener->poller messages completed

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
    -- Configuration written by the host interface (process hip), consumed by
    -- the power model (process pwr). Single driver each: `hip`.
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

    function to_sl(c : boolean) return std_logic is
    begin
        if c then return '1'; else return '0'; end if;
    end function;

    function u8(n : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(n mod 256, 8));
    end function;

    -- 4.8.1 VDBAT_ADC_VAL / VDDC_ADC_VAL: V = 12.5 mV * code + 2.4 V, and the
    -- code reads 0 when the ADC cannot measure (below the 2.4 V floor).
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
    -- GPO_0 / GPO_1 (4.8.1 GPO_x_CONFIG). Open drain, active low: the pin is
    -- PULLED LOW when the selected condition is true (ASSUMPTION A7).
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
        -- GPO_1 has no "startup circuit enable" option (4.8.1); cfg 6 is RFU
        -- there and therefore reads as disabled.
        if s_gpo1_cfg = 6 then
            gpo1_oe <= '0';
        else
            gpo1_oe <= gpo_level(s_gpo1_cfg, s_err_stat, s_bc_status, s_wlcp,
                                 s_ship, gpo_poller_ctl, rf_field_present);
        end if;
    end process gpo_proc;


    ---------------------------------------------------------------------------
    -- POWER / CHARGER MODEL (sections 4.1-4.5, thresholds from 3.4 and 4.8.1).
    -- Fixed-tick, integer engineering units, no electrical simulation.
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

        -- soc <-> terminal voltage: a straight line between the two generics.
        function v_of_soc(s : real) return natural is
            variable v : real;
        begin
            v := real(G_VBAT_EMPTY_MV)
                 + s * real(G_VBAT_FULL_MV - G_VBAT_EMPTY_MV);
            if v < 0.0 then return 0; end if;
            return natural(v);
        end function;

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
            -- HIP system reset (4.8.3.6.1): back to the OEM/reset charger state.
            ------------------------------------------------------------------
            if s_rst_tog /= rst_tog_l then
                rst_tog_l := s_rst_tog;
                bc        := PTX_BC_DISABLED;
                i_cv_ua   := 0.0;
                err       := PTX_ERR_NONE;
                started   := false;
            end if;

            ------------------------------------------------------------------
            -- NTC state with the 3.4 set/reset hysteresis. NTC voltage FALLS as
            -- the cell gets hotter (constant 69 uA source into the thermistor).
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
            -- Chip over-temperature (section 4): TJ_ALERT_SET 120 C /
            -- TJ_ALERT_RESET 100 C. Detunes the RF interface -> no harvest.
            ------------------------------------------------------------------
            if tj_degc >= 120 then overtemp := true;
            elsif tj_degc < 100 then overtemp := false; end if;

            ------------------------------------------------------------------
            -- Shipping mode (4.4): entered by the host parameter, by VDBAT
            -- below VBAT_LOW_TH (3.0 V) or by a >5 s SM press; left by the RF
            -- field appearing or another >5 s SM press.
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
            -- Charger parameter decode (4.8.1 tables).
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
            -- ERROR_STATUS (single enumerated value, ASSUMPTION A8).
            ------------------------------------------------------------------
            if s_err_ack /= err_ack_l then
                err_ack_l := s_err_ack;
                err := PTX_ERR_NONE;        -- "cleared when read" (4.8.1)
            end if;
            if ecold or ehot or (pct = 0 and (cold or hot)) then
                err := PTX_ERR_BATTEMP;
            elsif (not bat_connected) and s_batoff_en = '0' then
                err := PTX_ERR_NOBAT;
            elsif overtemp then
                err := PTX_ERR_ICTEMP;
            end if;

            ------------------------------------------------------------------
            -- Harvest + power selection (4.5.1).
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
            -- Charger phase machine (4.4, Figure 5, Table 12).
            ------------------------------------------------------------------
            if s_bc_enable = '0' or (not rf_field_present) or overtemp
               or ship = '1' or pct = 0 or ecold or ehot
               or ((not bat_connected) and s_batoff_en = '0') then
                -- Table 12: RF field off reads 0 unless the battery is full,
                -- which keeps reading 4.
                if bc /= PTX_BC_DONE then bc := PTX_BC_DISABLED; end if;
                i_target := 0;
                i_cv_ua  := 0.0;
            else
                case bc is
                    when PTX_BC_DISABLED =>
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
                        i_target := (ichg_ua * pct / 100) / 10;   -- ITRICKLE = 10% of ICHG
                        if vbat >= vtrk then bc := PTX_BC_CCM; end if;

                    when PTX_BC_CCM =>
                        i_target := ichg_ua * pct / 100;
                        if vbat >= vterm then
                            bc      := PTX_BC_CVM;
                            i_cv_ua := real(i_target);
                        end if;

                    when PTX_BC_CVM =>
                        i_cv_ua  := i_cv_ua * G_CV_DECAY;
                        i_target := natural(i_cv_ua);
                        if i_target < iterm_ua then
                            bc       := PTX_BC_DONE;
                            i_target := 0;
                        end if;

                    when others =>   -- PTX_BC_DONE
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

            -- The charge current can never exceed what the field left over
            -- (4.5.1: "the battery is charged with residual current").
            if i_target > i_budget then i_chg := i_budget; else i_chg := i_target; end if;

            ------------------------------------------------------------------
            -- Battery integration.
            ------------------------------------------------------------------
            if bc = PTX_BC_CVM or bc = PTX_BC_DONE then
                -- CV holds the terminal voltage at VTERM while the current
                -- tapers (ASSUMPTION A10), so pin soc there rather than letting
                -- the linear soc model push vbat past VTERM.
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
            -- Brownout detector with hysteresis (3.4).
            ------------------------------------------------------------------
            if vddc < G_VDDC_BOD_SET_MV then
                bod := '1';
            elsif vddc >= G_VDDC_BOD_RST_MV then
                bod := '0';
            end if;

            ------------------------------------------------------------------
            -- MCU LDO (4.2 + 3.4 "VDMCU pin").
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
            -- WLCP_CONNECTED (ASSUMPTION A9).
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
    -- I2C TARGET + HOST INTERFACE PROTOCOL + NSC LAYER + TDC.
    --
    -- Bit engine: `edge` counts SCL rising edges since the last START/repeated
    -- START, so group g = edge/9 and bit-in-group bp = edge mod 9 (group 0 is
    -- address+RnW+ACK, group N>=1 is data byte N-1 + its ACK). This is the
    -- i3c_target_model.vhd / qspi_flash_model.vhd phase-boundary-counting
    -- technique. SAMPLE on the rising edge, set the model's own drive up on the
    -- falling edge.
    ---------------------------------------------------------------------------
    hip : process (scl, sda_in, tdc_pol_go, tdc_lis_rd_go)

        ---- I2C bit/frame state -----------------------------------------
        variable active   : boolean := false;
        variable edge     : natural := 0;
        variable shift    : std_logic_vector(7 downto 0) := (others => '0');
        variable is_read  : boolean := false;
        variable addr_ok  : boolean := false;
        variable rd_bytes : natural := 0;
        -- Once the master has NACKed a read byte the model must RELEASE SDA for
        -- the rest of the frame; otherwise the phantom next byte's MSB=0 would
        -- hold SDA low across the master's STOP and the STOP would never be
        -- seen (the i3c_target_model.vhd "ruling 3" hazard).
        variable read_done : boolean := false;
        variable g, bp, bidx : natural;
        variable bitv     : std_logic;

        ---- standby / wake (4.8.4) --------------------------------------
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
        -- 0-based copy of a WMSG data payload: an unconstrained formal takes
        -- the ACTUAL's index range, so a raw rx_buf slice would arrive indexed
        -- from p0+1 and every d(0) below would be out of range.
        variable nsc_tmp  : ptx_msg_t := (others => (others => '0'));

        -----------------------------------------------------------------
        -- Output-message helpers
        -----------------------------------------------------------------
        procedure out_clear is
        begin
            out_len := 0;
        end procedure;

        procedure out_put(b : std_logic_vector(7 downto 0)) is
        begin
            if out_len < PTX_MSG_MAX then
                out_buf(out_len) := b;
                out_len := out_len + 1;
            end if;
        end procedure;

        procedure out_commit is
        begin
            out_valid := true;
        end procedure;

        -- Stage the next NSC_DATA_MSG chunk of a poller message: at most 63
        -- payload bytes, which is the 64-byte TDC_BUF_POL minus its H1 header
        -- (4.6.2 / Table 19).
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

        -- Called once the host has finished reading the pending message: free
        -- the output buffer and immediately hand over whatever was queued
        -- behind it (the next poller chunk, or a pending NSC_DATA_ACK).
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
        procedure resp_begin(op : natural; ack : boolean) is
            variable fcb : std_logic_vector(7 downto 0);
        begin
            fcb := std_logic_vector(to_unsigned(op * 16, 8));   -- OPCODE in [7:4]
            if ack    then fcb(2) := '1'; end if;   -- FCB.RAK
            if crc_en then fcb(1) := '1'; end if;   -- FCB.CRC
            tx_buf(2) := fcb;
            tx_ptr    := 3;
        end procedure;

        procedure resp_put(b : std_logic_vector(7 downto 0)) is
        begin
            if tx_ptr < PTX_FRAME_MAX then
                tx_buf(tx_ptr) := b;
                tx_ptr := tx_ptr + 1;
            end if;
        end procedure;

        procedure resp_end is
            variable lf : natural;
            variable c  : std_logic_vector(15 downto 0);
        begin
            lf := tx_ptr - 2;                       -- FCB + payload
            if crc_en then lf := lf + 2; end if;    -- ... + CRC (4.8.3.1)
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
        -- NSC layer (4.8.2). `d` is the WMSG data payload.
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
                -- NSC_DATA_MSG from the host (Table 19 / 4.6.2.3 step 1)
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
                -- NSC_CONFIG_CMD (4.8.2.1): one-shot OEM block.
                ------------------------------------------------------------
                if oem_done then
                    ec := PTX_EC_CMD;                    -- ASSUMPTION A5
                else
                    ec := PTX_EC_NONE;
                    oem_done := true;
                    -- APPLY_OEM: the byte indices that are legible in 4.8.2.1
                    -- (ASSUMPTION A11). Parameter #k lives at d(k).
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
                -- NSC_SET_PARAM_CMD (4.8.2.2 + Table 16): (ID,V)* then EoC 0.
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
                            -- CUSTOM_NDEF_MSG: value is a length byte followed
                            -- by that many payload bytes (Table 16 note 1).
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
                -- NSC_GET_PARAM_CMD (4.8.2.3 + Table 17): opcode, EC, then the
                -- eight RD parameters in order = 10 bytes = the RML=0x0A of
                -- Figure 36.
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
                s_err_ack <= not s_err_ack;   -- "cleared when read" (4.8.1)

            else
                ------------------------------------------------------------
                -- Unknown NSC opcode (ASSUMPTION A6)
                ------------------------------------------------------------
                out_clear;
                out_put(op);
                out_put(PTX_EC_CMD);
                out_commit;
            end if;
        end procedure;

        -----------------------------------------------------------------
        -- HIP frame parse + dispatch (4.8.3).
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
                -- 4.8.3.1: computed over the whole frame except SOF and padding
                -- (i.e. LEN + FCB + payload), inverted CRC_B.
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
                when PTX_OP_RST =>          -- 4.8.3.6.1
                    if plen /= 1 or rx_buf(p0) /= x"01" then
                        last_nak := PTX_NAK_PARAM;
                        return;
                    end if;
                    last_nak := PTX_NAK_NONE;
                    frames   := frames + 1;
                    if rak then
                        resp_begin(PTX_OP_RST, true);
                        resp_put(x"00");                       -- ACK value (4.8.3.4)
                        resp_end;
                    end if;
                    -- "The system reset is performed after the acknowledge ...
                    -- is sent to the Host" -- state is cleared here; the ACK
                    -- frame is already staged in tx_buf.
                    out_valid := false; out_len := 0;
                    pol_len := 0; pol_ptr := 0; ack_pend := false;
                    lis_valid := false; lis_len := 0;
                    s_ship_req <= '0';
                    s_rst_tog  <= not s_rst_tog;

                ----------------------------------------------------------
                when PTX_OP_RSS =>          -- 4.8.3.6.2 + Table 18
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
                        else                    resp_put(x"00");   -- padded (4.8.3.6.2)
                        end if;
                    end loop;
                    resp_end;
                    last_nak := PTX_NAK_NONE;
                    frames   := frames + 1;

                ----------------------------------------------------------
                when PTX_OP_WMSG =>         -- 4.8.3.6.3
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
                    -- "write buffer full" (ASSUMPTION A4): a data message while
                    -- TDC_BUF_LIS still holds an unread one.
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
                when PTX_OP_RML =>          -- 4.8.3.6.4
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
                when PTX_OP_RMSG =>         -- 4.8.3.6.5
                    if plen /= 2 then
                        last_nak := PTX_NAK_LEN;
                        return;
                    end if;
                    np := to_integer(unsigned(rx_buf(p0))) * 256
                          + to_integer(unsigned(rx_buf(p0 + 1)));
                    if np = 0 then np := out_len; end if;      -- N=0 => whole message
                    resp_begin(PTX_OP_RMSG, false);
                    for i in 0 to np - 1 loop
                        if out_valid and i < out_len then resp_put(out_buf(i));
                        else                              resp_put(x"00");
                        end if;
                    end loop;
                    resp_end;
                    -- ASSUMPTION A3: retire the message only once it has really
                    -- been clocked out, and only on a full-length read.
                    pend_consume := out_valid and (np >= out_len);
                    last_nak := PTX_NAK_NONE;
                    frames   := frames + 1;

                ----------------------------------------------------------
                when others =>
                    last_nak := PTX_NAK_CMD;                   -- Table 22 0x01
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

        -- End of a read phase.
        procedure end_read_phase is
        begin
            if pend_consume and rd_bytes >= tx_len then
                retire_out_msg;
                obs_msg_out <= msg_out;
            end if;
            pend_consume := false;
        end procedure;

        procedure publish_tdc is
        begin
            obs_lis_valid <= to_sl(lis_valid);
            obs_lis_len   <= lis_len;
            obs_lis_data  <= lis_buf;
            obs_lis_msgs  <= lis_msgs;
        end procedure;

        -- Awake? 4.8.4 standby rule + the brownout/shipping-mode dead cases.
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
        -- BENCH ABSTRACTION: the poller read TDC_BUF_LIS. 4.6.2.3 steps 5+6:
        -- clear TDC_BUF_LIS[0][7], then send the host an NSC_DATA_ACK.
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
        -- SCL FALLING EDGE: set up this model's drive for the NEXT sample
        -- (edge has already been incremented past that sample's index).
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
                        -- 4.8.4: even a NACKed command wakes the device for
                        -- at least 100 ms so the host can resend it.
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
                        -- ASSUMPTION A2: 0xFF past the end of the staged response.
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

        -- IRQ tracks "a message is pending for the host" (4.8.2 step 1).
        s_irq <= to_sl(out_valid);
        obs_lis_valid <= to_sl(lis_valid);
        obs_lis_len   <= lis_len;
        obs_lis_data  <= lis_buf;
        obs_lis_msgs  <= lis_msgs;
    end process hip;

end architecture behavioral;
