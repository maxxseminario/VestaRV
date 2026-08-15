-------------------------------------------------------------------------------
-- st25r3916_model.vhd
-------------------------------------------------------------------------------
-- Behavioral simulation model of the ST ST25R3916 NFC reader/writer IC, used as the off-die analog front end (AFE) for Castalia's on-chip NFC0 block (hdl/common/periph/NFC.vhd, decision D2: the rf_* ports are the ONLY link, the AFE is on the PCB).
-- NFC.vhd's header records the ST25R3916 in TRANSPARENT MODE as the best-match COTS part; this model is the layer that tb/nfc_reader_model.vhd does NOT cover.
--
-- DIVISION OF LABOUR. READ THIS FIRST.
--   tb/nfc_reader_model.vhd already models the whole ISO-14443A RF link at NFC0's pin level: modified-Miller pause encoding on rf_rx, Manchester/subcarrier decode of rf_txmod/rf_tx_en, rf_clk generation, field_detect, FDT measurement, CRC_A/parity.
--   THIS model implements NONE of that and deliberately duplicates NO protocol logic.
--   What it adds is the part nfc_reader_model cannot represent: the ST25R3916's own SPI register interface and its transparent-mode gating, i.e. the configuration front end the MCU must drive over SPI BEFORE the five shared pins stop being an SPI bus and become the raw pin-level RF link.
--
-- THE TRAP THIS MODEL EXISTS TO EXPOSE.
--   In the recorded NFC.vhd pin mapping the SAME physical wires carry SPI during configuration and raw RF signals in transparent mode:
--
--     ST25R3916 pin | normal (SPI) mode        | transparent mode, NFC0 pin
--     --------------+--------------------------+---------------------------
--     MOSI          | SPI master-out           | Tx modulation IN  (rf_txmod)
--     MISO          | SPI slave-out (tristate) | digitized RX OUT  (rf_rx)
--     SCLK          | SPI serial clock         | receiver enable   (afe_en)
--     MCU_CLK       | optional MCU clock out   | extracted carrier (rf_clk)
--     EXT_LM        | external load-mod driver | field detector    (field_detect)
--     IRQ           | interrupt out            | 2nd demod tap (ASK)
--     BSS (NSS)     | slave select, active low | MODE SELECTOR (see below)
--
--   BSS is the mode selector, and it is not a register bit.
--   Transparent mode is armed by direct command 0xDC and ENGAGES ON THE RISING EDGE OF BSS at the end of that SPI frame; it persists only while BSS stays HIGH.
--   Pulling BSS low to start ANY subsequent SPI frame silently drops the chip back out of transparent mode.
--   So on a real Castalia board a stray SPI transaction on SPI1 (or a chip-select glitch) kills the RF link with no error indication, and conversely NFC0 driving rf_txmod/afe_en while the part is NOT transparent puts arbitrary logic levels onto MOSI/SCLK of a live SPI bus.
--   Both directions of that gating are modelled and both are checked by the bench (tb/st25r3916_model_tb.vhd, groups G-GATE-RF and G-GATE-SPI).
--
-- INTENDED BOARD-LEVEL WIRING (what a composed bench looks like), with the driver of each link named in the right-hand column:
--
--    +---------------------+                +------------------+
--    |  nfc_reader_model   |                |  st25r3916_model |
--    |  (PCD / reader,     |                |  (off-die AFE)   |
--    |   the RF world)     |                |                  |
--    |         rf_clk  o---|----------------|o rf_clk_in       |   reader drives
--    |         rf_rx   o---|----------------|o rf_env_in       |   reader drives
--    |    field_detect o---|----------------|o rf_field_in     |   reader drives
--    |         rf_txmod  o-|----------------|o rf_loadmod_out  |   AFE drives
--    |         rf_tx_en  o-|----------------|o rf_loadmod_en   |   AFE drives
--    +---------------------+                |                  |
--                                           |   shared pins    |
--    +---------------------+                |                  |
--    |  Castalia (MCU)     |   pin_bss_n  o-|o (SPI1 CS)       |   MCU drives
--    |                     |   pin_sclk   o-|o SCLK / afe_en   |   MCU drives
--    |  SPI1 master   -----|   pin_mosi   o-|o MOSI / rf_txmod |   MCU drives
--    |  NFC0 rf_*     -----|   pin_miso   o-|o MISO / rf_rx    |   AFE drives
--    |                     |   pin_mcu_clk o|o MCU_CLK/ rf_clk |   AFE drives
--    |                     |   pin_ext_lm o-|o EXT_LM /f_detect|   AFE drives
--    |                     |   pin_irq    o-|o IRQ             |   AFE drives
--    +---------------------+                +------------------+
--
--   In such a bench the MCU-side wires are BOTH SPI1's four pins AND NFC0's rf_* pins, which is the point.
--   NFC0's rf_tx_en has no ST25R3916 pin in this mapping (rf_txmod is already OOK-gated per NFC.vhd D5), so it is offered here only as the clearly labelled BENCH-ONLY input mcu_rf_tx_en, used to drive nfc_reader_model's rf_tx_en decode trigger.
--
-- DATASHEET GROUNDING (ST25R3916/7 DS12484 Rev 8, saved in .devlog/datasheets/, plus ST's own RFAL headers st25r3916.h / st25r3916_com.h and the two ST community threads cited in NFC.vhd):
--   [S1] Sect. 4.3.3 "Serial peripheral interface (SPI)": clock polarity 0, clock phase 1, active-low slave select BSS.
--        "The MOSI pin is samples [sic] on the falling edge of SCLK, and the state of the MISO pin is updated on the rising edge of the SCLK signal. Data are transferred byte-wise, most significant bit first."
--   [S2] Table 11 "SPI operation modes": the first two bits of the first byte after the BSS falling edge select the operation mode: 00|A5..A0 register write, 01|A5..A0 register read, 0x80 FIFO load, 0x9F FIFO read, 0xA0/0xA8/0xAC PT_memory load, 0xBF PT_memory read, 11|C5..C0 direct command.
--        All read/write modes auto-increment.
--   [S3] Sect. 4.3 text under Table 11: "Register read and write operations are possible in all ST25R3916/7 operation modes. FIFO and PT_memory operations are possible in case en (bit 7 of the Operation control register) is set and the crystal oscillator is stable."
--   [S4] Sect. 4.4.13 "Transparent mode" (VERBATIM): "This command sets the receiver and transmitter into the transparent mode. The device enters the transparent mode on the rising edge of the BSS signal of the SPI frame used to send the direct command. The transparent mode is maintained as long as signal BSS is kept high, that is, the following SPI command sent from the microcontroller will automatically stop the transparent mode."
--        There is NO exit command and NO exit register bit.
--   [S5] Table 13 "List of direct commands": 0xC1 Set default, 0xC2 Stop all activities, 0xC4/0xC5 Transmit with/without CRC, 0xC6 Transmit REQA, 0xC7 Transmit WUPA, 0xD3 Measure amplitude, 0xDB Clear FIFO, 0xDC Enter Transparent mode (Chaining: No; requires operation-mode bit en), 0xFB Register space-B access, 0xFC Test access.
--        Cross-checked byte-for-byte against ST's RFAL st25r3916.h ST25R3916_CMD_* defines.
--   [S6] Sect. 2.2.12 / 2.2.13: "In Transparent mode, the framing and FIFO are bypassed, and the MOSI pin directly drives the modulation of the transmitter." and "In Transparent mode the framing and FIFO are bypassed. The digitized subcarrier signal directly drives the MISO pin."
--   [S7] Sect. 4.3.1 (MCU_CLK): "If the Transparent mode is used the use of MCU_CLK is mandatory since a clock synchronous with the field carrier frequency is needed to implement receive and transmit framing in the external controller."
--        Table 19 out_cl<1:0>: 00 = 3.39 MHz, 01 = 6.78 MHz, 10 = 13.56 MHz, 11 = MCU_CLK output permanently low.
--        lf_clk_off = 0 puts the 32 kHz LF clock on MCU_CLK when the crystal oscillator is not running.
--   [S8] Table 21 Operation control register (0x02): bit 7 en, bit 6 rx_en, bit 3 tx_en, bits 1:0 en_fd_c<1:0> external field detector (00 = off, 01/10 = manual thresholds, 11 = automatic).
--   [S9] Sect. 4.5.x register tables: every register in both spaces resets to 0x00 EXCEPT Mode definition (0x03), whose om0 default of 1 makes it 0x08, and IC identity (0x3F, read-only), whose default ic_type<4:0>=00101 / ic_rev<2:0>=010 makes it 0x2A.
--   [S10] Sect. 4.3.1 interrupts: "After a particular interrupt register is read, its content is reset to 0".
--        The IRQ pin goes low once the bit(s) that raised it have been read; masking is per Mask interrupt register (a set mask bit suppresses the PIN, not the status bit).
--   [S11] Table 17/18 register lists: space A is contiguous 0x00..0x3F; space B is SPARSE (only 05,06,0B,0C,0D,0F,15,28,29,2A,2B,2C,30..33 exist on the plain ST25R3916) and is reached by prefixing the read/write frame with direct command 0xFB, which stays active until BSS rises.
--   [S12] ST community thread "ST25R3916 transparent mode details" (community.st.com .../td-p/134598, ST staff answer) gives the FULL transparent-mode pin table quoted above: MOSI = Tx modulation in, MISO = demodulated OOK out, IRQ = ASK demodulation out, SCLK = receiver enable, MCU_CLK = extracted field clock, EXT_LM = field detector output.
--        This is the ONLY source for the SCLK / EXT_LM / IRQ rows; the datasheet itself documents only MOSI and MISO [S6].
--
-- WHAT THIS MODEL DOES NOT IMPLEMENT (deliberate; do not read absence as silicon behavior):
--   * No analog anything: no antenna driver, no AM/OOK modulator, no receiver gain/squelch/correlator, no RSSI, no amplitude/phase/capacitance measurement, no regulators.
--     Commands that only touch those (0xD3, 0xD6, 0xD8, 0xD9, 0xDA, 0xDD, 0xDE, 0xDF) are ACCEPTED and COUNTED but have no modelled effect.
--   * No framing engine: no CRC/parity generation or checking, no automatic anticollision, no passive-target state machine, no bit-rate handling.
--     The Transmit commands (0xC4..0xC9) do not move FIFO data onto the air.
--     Any bench needing real ISO-14443A traffic uses nfc_reader_model for it.
--   * No timers (MRT/NRT/GPT/PPON2/wake-up), so 0xE0..0xE8 are inert.
--   * No PT_memory (passive-target 48-byte RAM): mode bytes 0xA0/0xA8/0xAC/0xBF are RECOGNIZED (so they do not get mis-parsed as something else) and then ignored for the rest of the frame.
--   * No I2C interface (I2C_EN is assumed tied to GND = SPI, [S12 datasheet Sect. 4.3.2]); the I2C flavour of transparent-mode entry/exit is not here.
--   * No test-register space (0xFC) and no stream modes (om = 0xE/0xF): stream mode keeps the FIFO and is a different feature from transparent mode.
--   * Crystal-oscillator start-up time is ZERO: setting en makes "oscillator stable" immediately, so the FIFO/en gate of [S3] engages with no delay.
--
-- ASSUMPTIONS (flagged, house style; none of these are datasheet-sourced):
--   [A1] TRANSPARENT-MODE SIGNAL POLARITY IS UNSPECIFIED.
--        ST publishes no polarity, timing or setup/hold for any transparent-mode pin (and told the community thread it will not).
--        This model passes the digitized envelope through NON-INVERTING, i.e. it adopts NFC.vhd's D4 convention ('1' = field / no pause, '0' = pause) directly.
--        Set cfg_rx_invert to explore the other convention; a real board WILL need this checked on hardware.
--   [A2] The transparent-mode RX path is gated by BOTH rx_en (op-control bit 6) and the SCLK-as-receiver-enable line [S12].
--        The datasheet says nothing about how "receiver enable" combines with rx_en; set cfg_sclk_is_afe_en = false to drop the pin-level gate and rely on rx_en alone.
--        When the RX path is gated off, MISO is held at the no-pause idle level '1' (RX_IDLE) rather than tristated; a real part might do either.
--   [A3] The transmit (load-modulation) path is gated by en only.
--        Whether tx_en (op-control bit 3) must also be set for transparent-mode load modulation in target mode is not documented; it is NOT required here.
--   [A4] MCU_CLK DIVISION IS NOT MODELLED.
--        out_cl<1:0> = 11 correctly holds the output low [S7], but 00/01/10 all simply PASS rf_clk_in through, because in a Castalia bench rf_clk_in is already the compressed carrier-derived protocol clock nfc_reader_model generates, not a real 13.56 MHz carrier.
--        Do not use this model to check RFDIV/NFCxTIM divider arithmetic.
--   [A5] The IRQ pin's transparent-mode "ASK demodulation" tap [S12] is modelled as the SAME digitized envelope as MISO.
--        The real part has two physically distinct demodulator taps (OOK vs ASK); this model has one.
--   [A6] EXT_LM is driven with the field-present level whenever the external field detector is enabled (en_fd_c /= 00, [S8]).
--        The datasheet pin table describes EXT_LM in NORMAL mode as an analog output, "External load modulation MOS gate driver" (pin 17, type AO), so the field-detector role is a transparent-mode REPURPOSING known only from [S12].
--        No detector threshold, hysteresis or debounce is modelled, and the normal-mode load-modulation driver role is not modelled at all.
--   [A7] Register write protection is modelled only as a read-only ADDRESS list.
--        Per-bit RFU/read-only behavior inside otherwise-writable registers is not enforced, and the [S9] "Mode definition register can be written only when oscok = 1" restriction is NOT enforced.
--   [A8] Only registers whose reset value is explicitly cited in [S9] are trustworthy after reset.
--        Every other address resets to 0x00 here because the datasheet's per-register Default columns are 0 for all the registers this model names; do not treat this model as a reference for reset values of registers it does not name.
--   [A9] Direct command 0xDC is marked "Chaining: No" [S5], so this model ignores the remainder of the SPI frame after a 0xDC byte.
--        The datasheet does not say what the part does with such trailing bytes.
--   [A10] Nothing here is timed against real silicon: there are no SPI setup/hold checks, no command execution durations (the datasheet gives e.g. 25 us for Measure amplitude), and no oscillator/regulator settling.
--        This is a functional model for firmware bring-up and board wiring exploration, NOT a sign-off model.
--
-- House conventions followed: cfg_* inputs let the bench tell the model what shape to expect, and obs_* outputs are held for the scoreboard.
-- The tristate MISO uses the pin_miso / pin_miso_oe pair ('1' on the _oe port means this model is driving that pin) exactly like qspi_flash_model's io_oe and i3c_target_model's sda_oe, so the BENCH resolves the shared wire.
-- -V200X only (VHDL-93 + numeric_std): no VHDL-2008 constructs anywhere.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity st25r3916_model is
    generic (
        -- Half period of the 32 kHz low-frequency clock the part puts on MCU_CLK while the crystal oscillator is not running [S7].
        -- Real part: ~15.26 us; benches compress it like every other time constant here.
        LF_HALF    : time    := 500 ns;
        -- FIFO depth. Real part: 512 bytes [datasheet Sect. 2.2.14]. Shrink for speed.
        FIFO_DEPTH : natural := 512
    );
    port (
        -------------------------------------------------------------------
        -- SHARED PHYSICAL PINS (MCU side): their meaning depends on the mode, and that dual use is the whole point of this model.
        -------------------------------------------------------------------
        pin_bss_n   : in  std_logic := '1';   -- BSS/NSS, ACTIVE LOW slave select
                                              --   also THE transparent-mode selector [S4]
        pin_sclk    : in  std_logic := '0';   -- SPI SCLK | transparent: receiver enable (afe_en)
        pin_mosi    : in  std_logic := '0';   -- SPI MOSI | transparent: Tx modulation in (rf_txmod)
        pin_miso    : out std_logic := '0';   -- SPI MISO | transparent: digitized RX out (rf_rx)
        pin_miso_oe : out std_logic := '0';   -- '1' = this model drives pin_miso
        pin_mcu_clk : out std_logic := '0';   -- MCU_CLK  | transparent: extracted carrier (rf_clk)
        pin_irq     : out std_logic := '0';   -- IRQ      | transparent: 2nd demod tap [A5]
        pin_ext_lm  : out std_logic := '0';   -- EXT_LM   | transparent: field detector [A6]

        -------------------------------------------------------------------
        -- ANTENNA / RF-WORLD SIDE (wire these to nfc_reader_model)
        -------------------------------------------------------------------
        rf_field_in    : in  std_logic := '0';  -- reader field present
        rf_env_in      : in  std_logic := '1';  -- reader's envelope at the antenna
        rf_clk_in      : in  std_logic := '0';  -- carrier-derived clock
        rf_loadmod_out : out std_logic := '0';  -- drives nfc_reader_model.rf_txmod
        rf_loadmod_en  : out std_logic := '0';  -- drives nfc_reader_model.rf_tx_en

        -- BENCH-ONLY: there is NO ST25R3916 pin for this, since NFC0's rf_tx_en has no home in the five-pin transparent mapping (rf_txmod is already OOK-gated, NFC.vhd D5).
        -- It exists so a composed bench can hand nfc_reader_model the response-window trigger its decoder needs.
        mcu_rf_tx_en   : in  std_logic := '0';

        -------------------------------------------------------------------
        -- PER-TEST CONFIGURATION (held stable by the bench)
        -------------------------------------------------------------------
        cfg_rx_invert      : in boolean := false;  -- [A1] invert the digitized envelope
        cfg_sclk_is_afe_en : in boolean := true;   -- [A2] honour SCLK as receiver enable

        -- Inject an interrupt condition: a rising edge on cfg_irq_trigger ORs cfg_irq_bits into the Main interrupt register (0x1A).
        -- Lets a bench exercise the [S10] read-and-clear IRQ contract without an RF engine.
        cfg_irq_trigger    : in std_logic                    := '0';
        cfg_irq_bits       : in std_logic_vector(7 downto 0) := (others => '0');

        -------------------------------------------------------------------
        -- OBSERVATIONS (held until the next event of the same kind)
        -------------------------------------------------------------------
        transparent_mode      : out std_logic := '0';   -- THE mode output
        obs_frame_count       : out natural := 0;       -- completed SPI frames (BSS low then high)
        obs_cmd_count         : out natural := 0;       -- direct commands executed
        obs_last_cmd          : out std_logic_vector(7 downto 0) := (others => '0');
        obs_last_mode         : out std_logic_vector(7 downto 0) := (others => '0');
        obs_last_addr         : out std_logic_vector(5 downto 0) := (others => '0');
        obs_space_b           : out std_logic := '0';   -- space-B prefix currently active
        obs_reg_writes        : out natural := 0;       -- register writes COMMITTED
        obs_reg_reads         : out natural := 0;       -- register bytes SOURCED
        obs_reject_count      : out natural := 0;       -- refused writes / refused ops
        obs_fifo_level        : out natural := 0;
        -- The two gating proofs:
        obs_spi_ignored_edges : out natural := 0;       -- SCLK edges ignored while transparent
        obs_rf_blocked_edges  : out natural := 0        -- RF envelope edges NOT passed on
    );
end entity st25r3916_model;


architecture behavioral of st25r3916_model is

    constant NREG : natural := 64;
    type reg_array  is array (0 to NREG - 1) of std_logic_vector(7 downto 0);
    type fifo_array is array (0 to FIFO_DEPTH - 1) of std_logic_vector(7 downto 0);

    -- Named registers ([S11] addresses, cross-checked against RFAL st25r3916_com.h ST25R3916_REG_* defines).
    constant R_IO_CONF1  : natural := 16#00#;
    constant R_IO_CONF2  : natural := 16#01#;
    constant R_OP_CTRL   : natural := 16#02#;
    constant R_MODE      : natural := 16#03#;
    constant R_BIT_RATE  : natural := 16#04#;
    constant R_ISO14443A : natural := 16#05#;
    constant R_STREAM    : natural := 16#09#;
    constant R_AUX       : natural := 16#0A#;
    constant R_MASK_MAIN : natural := 16#16#;
    constant R_IRQ_MAIN  : natural := 16#1A#;
    constant R_IRQ_LAST  : natural := 16#1D#;
    constant R_IC_ID     : natural := 16#3F#;

    -- Direct commands ([S5]).
    constant CMD_SET_DEFAULT : std_logic_vector(7 downto 0) := x"C1";
    constant CMD_STOP        : std_logic_vector(7 downto 0) := x"C2";
    constant CMD_CLEAR_FIFO  : std_logic_vector(7 downto 0) := x"DB";
    constant CMD_TRANSPARENT : std_logic_vector(7 downto 0) := x"DC";
    constant CMD_SPACE_B     : std_logic_vector(7 downto 0) := x"FB";

    -- SPI operation-mode first bytes ([S2]).
    constant MB_FIFO_LOAD : std_logic_vector(7 downto 0) := x"80";
    constant MB_FIFO_READ : std_logic_vector(7 downto 0) := x"9F";

    -- SPI frame parser states, kept as naturals rather than an enum: that keeps this -V200X-plain and lets the states be compared inside procedures without type games.
    constant ST_MODE   : natural := 0;   -- expecting an operation-mode byte
    constant ST_WDATA  : natural := 1;   -- register write data (auto-increment)
    constant ST_RDATA  : natural := 2;   -- register read data  (auto-increment)
    constant ST_FIFO_W : natural := 3;   -- FIFO load data
    constant ST_FIFO_R : natural := 4;   -- FIFO read data
    constant ST_IGN    : natural := 5;   -- consume the rest of the frame

    -- [A2] Level MISO/IRQ sit at when the transparent RX path is gated off: the 14443A "field present, no pause" idle of NFC.vhd D4.
    constant RX_IDLE : std_logic := '1';

    -- Published copy of the space-A register file, so the RF-path concurrent assignments below can see en / rx_en / en_fd_c / out_cl / lf_clk_off.
    signal s_regs_a : reg_array := (others => (others => '0'));
    signal s_tp     : std_logic := '0';   -- published transparent-mode flag

    -- MISO sources: the SPI slave output and its enable, and the transparent-mode RX output.
    signal miso_spi    : std_logic := '0';
    signal miso_spi_oe : std_logic := '0';
    signal miso_tp     : std_logic := RX_IDLE;

    -- Register-file taps used by the pin paths ([S7]/[S8]).
    signal s_en     : std_logic := '0';                          -- op-control en
    signal s_rx_en  : std_logic := '0';                          -- op-control rx_en
    signal s_fd     : std_logic_vector(1 downto 0) := "00";      -- en_fd_c<1:0>
    signal s_outcl  : std_logic_vector(1 downto 0) := "00";      -- out_cl<1:0>
    signal s_lfoff  : std_logic := '0';                          -- lf_clk_off

    signal rx_gate  : std_logic := '0';     -- transparent RX path open
    signal env_dig  : std_logic := RX_IDLE; -- digitized envelope after [A1] polarity choice
    signal irq_spi  : std_logic := '0';     -- normal-mode IRQ pin level
    signal lf_clk   : std_logic := '0';     -- free-running 32 kHz LF clock

    function to_sl(b : boolean) return std_logic is
    begin
        if b then return '1'; else return '0'; end if;
    end function;

    -- [S9]/[A8]: everything resets to 0x00 except MODE (om0 = 1) and the read-only IC identity byte (ic_type = 00101, ic_rev = 010).
    function defaults_a return reg_array is
        variable r : reg_array := (others => (others => '0'));
    begin
        r(R_MODE)  := x"08";
        r(R_IC_ID) := x"2A";
        return r;
    end function;

    -- Space B has no cited non-zero reset values, so every byte resets to 0x00 [A8].
    function defaults_b return reg_array is
        variable r : reg_array := (others => (others => '0'));
    begin
        return r;
    end function;

    -- Space-A read-only addresses ([S11] register-list types: interrupt status, FIFO status, collision/PT display, bit-rate detection, ADC output, RSSI, gain reduction, capacitive-sensor and auxiliary displays, the measurement display registers and IC identity).
    function is_ro_a(a : natural) return boolean is
    begin
        if a >= 16#1A# and a <= 16#21# then return true; end if;   -- IRQ status, FIFO status, displays
        if a = 16#24# or a = 16#25# then return true; end if;      -- bit-rate detect, ADC out
        if a = 16#2D# or a = 16#2E# then return true; end if;      -- RSSI, gain reduction
        if a = 16#30# or a = 16#31# then return true; end if;      -- cap-sensor display, aux display
        if a = 16#35# or a = 16#36# then return true; end if;      -- amplitude avg / display
        if a = 16#39# or a = 16#3A# then return true; end if;      -- phase avg / display
        if a = 16#3D# or a = 16#3E# then return true; end if;      -- capacitance avg / display
        if a = R_IC_ID then return true; end if;
        return false;
    end function;

    -- Space B is SPARSE ([S11] Table 18, plain ST25R3916).
    function exists_b(a : natural) return boolean is
    begin
        case a is
            when 16#05# | 16#06# | 16#0B# | 16#0C# | 16#0D# | 16#0F# | 16#15# |
                 16#28# | 16#29# | 16#2A# | 16#2B# | 16#2C# |
                 16#30# | 16#31# | 16#32# | 16#33# => return true;
            when others => return false;
        end case;
    end function;

    -- Space-B read-only addresses.
    function is_ro_b(a : natural) return boolean is
    begin
        -- 2B TX driver timing display, 2C regulator display.
        if a = 16#2B# or a = 16#2C# then return true; end if;
        return false;
    end function;

begin

    ---------------------------------------------------------------------------
    -- SPI SLAVE + REGISTER FILE + TRANSPARENT-MODE STATE MACHINE
    --
    -- [S1] CPOL = 0, CPHA = 1: MOSI is SAMPLED on the FALLING edge of SCLK and MISO is UPDATED on the RISING edge, MSB first, while BSS is low.
    -- bitpos is the index within the current byte and is shared by both edges: at the rising edge the bit being SET UP has index bitpos, and it is CONSUMED at the falling edge with the same bitpos.
    -- So bitpos = 0 on a rising edge is exactly the start of a new byte, which is where a read fetches its next source byte.
    -- The parser state machine is re-armed to ST_MODE after a direct command, which is [S5] "direct command chaining".
    ---------------------------------------------------------------------------
    spi_proc : process (pin_bss_n, pin_sclk, cfg_irq_trigger)
        variable rega    : reg_array  := defaults_a;   -- space-A register file
        variable regb    : reg_array  := defaults_b;   -- space-B register file
        variable fifo    : fifo_array := (others => (others => '0'));
        variable fifo_wp : natural := 0;               -- FIFO write pointer
        variable fifo_rp : natural := 0;               -- FIFO read pointer
        variable fifo_lv : natural := 0;               -- FIFO fill level

        variable tp      : std_logic := '0';   -- transparent mode, live value
        variable pend_tp : boolean   := false; -- 0xDC seen, arms on BSS rise [S4]
        variable spb     : boolean   := false; -- space-B prefix active [S11]

        variable st      : natural := ST_MODE; -- parser state
        variable bitpos  : natural := 0;       -- bit index within the current byte
        variable shift   : std_logic_vector(7 downto 0) := (others => '0');  -- MOSI receive shifter
        variable rdbyte  : std_logic_vector(7 downto 0) := (others => '0');  -- byte currently sourced onto MISO
        variable cur     : natural := 0;       -- auto-incrementing register address

        -- Observation counters, published at the end of every call.
        variable frames  : natural := 0;       -- completed SPI frames
        variable cmds    : natural := 0;       -- direct commands executed
        variable wrs     : natural := 0;       -- register writes committed
        variable rds     : natural := 0;       -- register bytes sourced
        variable rejs    : natural := 0;       -- refused writes and refused operations
        variable ign     : natural := 0;       -- SCLK edges ignored while transparent

        -----------------------------------------------------------------------
        -- Empty the FIFO ([S5] Set default, Stop all activities, Clear FIFO).
        procedure fifo_clear is
        begin
            fifo_wp := 0; fifo_rp := 0; fifo_lv := 0;
        end procedure;

        -- Append one byte from a FIFO-load frame.
        procedure fifo_push(d : std_logic_vector(7 downto 0)) is
        begin
            if fifo_wp < FIFO_DEPTH then
                fifo(fifo_wp) := d;
                fifo_wp := fifo_wp + 1;
                fifo_lv := fifo_wp - fifo_rp;
            else
                rejs := rejs + 1;              -- FIFO overflow: data dropped
            end if;
        end procedure;

        -- Source the next byte of a FIFO-read frame.
        procedure fifo_pop(d : out std_logic_vector(7 downto 0)) is
        begin
            if fifo_rp < fifo_wp then
                d := fifo(fifo_rp);
                fifo_rp := fifo_rp + 1;
                fifo_lv := fifo_wp - fifo_rp;
            else
                d := x"00";                    -- [S3 text] empty FIFO reads 0
            end if;
        end procedure;

        -- Clear the four IRQ status registers and with them the IRQ line ([S5] Set default, Stop all activities and Clear FIFO all do this).
        procedure irq_clear is
        begin
            for a in R_IRQ_MAIN to R_IRQ_LAST loop
                rega(a) := x"00";
            end loop;
        end procedure;

        -- Commit one register write, or count it as refused.
        -- [S2]: "If the register ... does not exist or it is a read only register no write is performed".
        procedure do_write(a : natural; d : std_logic_vector(7 downto 0)) is
        begin
            if spb then
                if exists_b(a) and not is_ro_b(a) then
                    regb(a) := d; wrs := wrs + 1;
                else
                    rejs := rejs + 1;          -- absent or read-only space-B address
                end if;
            else
                if is_ro_a(a) then
                    rejs := rejs + 1;
                else
                    rega(a) := d; wrs := wrs + 1;
                end if;
            end if;
        end procedure;

        -- Source one register byte for a read frame; absent space-B addresses read 0x00.
        procedure reg_fetch(a : natural; d : out std_logic_vector(7 downto 0)) is
        begin
            if spb then
                if exists_b(a) then d := regb(a); else d := x"00"; end if;
            else
                d := rega(a);
                if a >= R_IRQ_MAIN and a <= R_IRQ_LAST then
                    rega(a) := x"00";          -- [S10] read-and-clear
                end if;
            end if;
            rds := rds + 1;
        end procedure;

        -- Execute one direct command ([S5]); unmodelled commands are still accepted and counted.
        procedure do_cmd(c : std_logic_vector(7 downto 0)) is
        begin
            cmds := cmds + 1;
            obs_last_cmd <= c;
            if c = CMD_SET_DEFAULT then
                rega := defaults_a;            -- [S5] 4.4.1: power-up state
                regb := defaults_b;
                fifo_clear;
            elsif c = CMD_STOP then
                fifo_clear;                    -- [S5] 4.4.2: stop all activities
                irq_clear;
            elsif c = CMD_CLEAR_FIFO then
                fifo_clear;
                irq_clear;
            elsif c = CMD_SPACE_B then
                spb := true;                   -- [S11] active until BSS rises
            elsif c = CMD_TRANSPARENT then
                -- [S5] Table 13: the operation-mode column reads "en", so the command is refused unless en is set.
                -- [S4]: the mode engages on the BSS RISING edge of THIS frame, not now.
                if rega(R_OP_CTRL)(7) = '1' then
                    pend_tp := true;
                else
                    rejs := rejs + 1;
                end if;
                st := ST_IGN;                  -- [A9] "Chaining: No"
            else
                null;                          -- accepted + counted, no effect
            end if;
        end procedure;

        -- Absorb one fully received MOSI byte according to the parser state.
        procedure consume_byte(b : std_logic_vector(7 downto 0)) is
            variable dummy : std_logic_vector(7 downto 0);
        begin
            if st = ST_MODE then
                obs_last_mode <= b;
                if b(7 downto 6) = "00" then                 -- register write [S2]
                    cur := to_integer(unsigned(b(5 downto 0)));
                    obs_last_addr <= b(5 downto 0);
                    st := ST_WDATA;
                elsif b(7 downto 6) = "01" then              -- register read [S2]
                    cur := to_integer(unsigned(b(5 downto 0)));
                    obs_last_addr <= b(5 downto 0);
                    st := ST_RDATA;
                elsif b = MB_FIFO_LOAD then
                    if rega(R_OP_CTRL)(7) = '1' then         -- [S3] needs en
                        st := ST_FIFO_W;
                    else
                        st := ST_IGN; rejs := rejs + 1;
                    end if;
                elsif b = MB_FIFO_READ then
                    if rega(R_OP_CTRL)(7) = '1' then
                        st := ST_FIFO_R;
                    else
                        st := ST_IGN; rejs := rejs + 1;
                    end if;
                elsif b(7 downto 6) = "10" then              -- PT_memory: recognized but not modelled
                    st := ST_IGN;
                else                                         -- "11" direct command
                    do_cmd(b);
                    if st /= ST_IGN then
                        st := ST_MODE;                       -- [S5] command chaining
                    end if;
                end if;
            elsif st = ST_WDATA then
                do_write(cur, b);
                cur := (cur + 1) mod NREG;                   -- [S2] auto-increment
            elsif st = ST_FIFO_W then
                fifo_push(b);
            else
                null;      -- read states / ST_IGN: MOSI bytes are don't-care
            end if;
        end procedure;
        -----------------------------------------------------------------------

    begin
        -- Bench-driven interrupt injection (see cfg_irq_trigger).
        if cfg_irq_trigger'event and to_X01(cfg_irq_trigger) = '1' then
            rega(R_IRQ_MAIN) := rega(R_IRQ_MAIN) or cfg_irq_bits;
        end if;

        if pin_bss_n'event and to_X01(pin_bss_n) = '0' then
            ------------------------------------------------------------------
            -- BSS FALLING: start of an SPI frame.
            -- [S4] "the following SPI command sent from the microcontroller will automatically stop the transparent mode", so THIS edge is the silent exit.
            ------------------------------------------------------------------
            tp      := '0';
            pend_tp := false;
            spb     := false;
            st      := ST_MODE;
            bitpos  := 0;
            shift   := (others => '0');
            miso_spi_oe <= '0';

        elsif pin_bss_n'event and to_X01(pin_bss_n) = '1' then
            ------------------------------------------------------------------
            -- BSS RISING: end of the frame.
            -- [S4] transparent mode ENGAGES HERE if this frame carried 0xDC, and space-B access also ends here.
            ------------------------------------------------------------------
            frames := frames + 1;
            if pend_tp then
                tp := '1';
                pend_tp := false;
            end if;
            spb    := false;
            st     := ST_MODE;
            bitpos := 0;
            miso_spi_oe <= '0';

        elsif pin_sclk'event and tp = '1' then
            ------------------------------------------------------------------
            -- TRANSPARENT MODE: the SPI engine is DEAD.
            -- SCLK is the receiver enable, not a clock, so every edge here is deliberately refused.
            ------------------------------------------------------------------
            ign := ign + 1;

        elsif pin_sclk'event and to_X01(pin_bss_n) = '0' and to_X01(pin_sclk) = '1' then
            ------------------------------------------------------------------
            -- SCLK RISING: update MISO [S1].
            ------------------------------------------------------------------
            if bitpos = 0 then
                if st = ST_RDATA then
                    reg_fetch(cur, rdbyte);
                    cur := (cur + 1) mod NREG;
                elsif st = ST_FIFO_R then
                    fifo_pop(rdbyte);
                else
                    rdbyte := (others => '0');
                end if;
            end if;
            if st = ST_RDATA or st = ST_FIFO_R then
                miso_spi    <= rdbyte(7 - bitpos);
                miso_spi_oe <= '1';
            else
                miso_spi_oe <= '0';   -- [S2 text] MISO tristate when no output data
            end if;

        elsif pin_sclk'event and to_X01(pin_bss_n) = '0' and to_X01(pin_sclk) = '0' then
            ------------------------------------------------------------------
            -- SCLK FALLING: sample MOSI [S1], MSB first.
            ------------------------------------------------------------------
            shift := shift(6 downto 0) & to_X01(pin_mosi);
            if bitpos = 7 then
                consume_byte(shift);
                bitpos := 0;
            else
                bitpos := bitpos + 1;
            end if;
        end if;

        -- Publish the live state to the observation ports and the pin paths.
        s_regs_a              <= rega;
        s_tp                  <= tp;
        transparent_mode      <= tp;
        obs_frame_count       <= frames;
        obs_cmd_count         <= cmds;
        obs_space_b           <= to_sl(spb);
        obs_reg_writes        <= wrs;
        obs_reg_reads         <= rds;
        obs_reject_count      <= rejs;
        obs_fifo_level        <= fifo_lv;
        obs_spi_ignored_edges <= ign;
    end process spi_proc;

    ---------------------------------------------------------------------------
    -- Register-file taps used by the analog/pin paths.
    ---------------------------------------------------------------------------
    s_en    <= s_regs_a(R_OP_CTRL)(7);            -- [S8] oscillator + regulator
    s_rx_en <= s_regs_a(R_OP_CTRL)(6);            -- [S8] receiver enable
    s_fd    <= s_regs_a(R_OP_CTRL)(1 downto 0);   -- [S8] en_fd_c<1:0>
    s_outcl <= s_regs_a(R_IO_CONF1)(2 downto 1);  -- [S7] out_cl<1:0>
    s_lfoff <= s_regs_a(R_IO_CONF1)(0);           -- [S7] lf_clk_off

    ---------------------------------------------------------------------------
    -- RX PATH (reader to MCU), live ONLY in transparent mode [S6], and then only when the receiver is enabled ([A2]: rx_en AND the SCLK receiver-enable line).
    -- Outside transparent mode the envelope is HELD and never passed on, which is the "refuse to pass RF while not transparent" half of the gating contract.
    ---------------------------------------------------------------------------
    env_dig <= (not to_X01(rf_env_in)) when cfg_rx_invert else to_X01(rf_env_in);  -- [A1]

    rx_gate <= '1' when (s_tp = '1' and s_rx_en = '1' and
                         ((not cfg_sclk_is_afe_en) or to_X01(pin_sclk) = '1'))
                    else '0';

    miso_tp <= env_dig when rx_gate = '1' else RX_IDLE;

    -- MISO is the SPI slave output outside transparent mode (tristate unless sourcing read data) and the digitized RX output inside it [S6].
    pin_miso    <= miso_tp when s_tp = '1' else miso_spi;
    pin_miso_oe <= '1'     when s_tp = '1' else miso_spi_oe;

    ---------------------------------------------------------------------------
    -- TX PATH (MCU to reader).
    -- [S6] MOSI directly drives the modulator, but only in transparent mode; [A3] gated by en alone.
    ---------------------------------------------------------------------------
    rf_loadmod_out <= to_X01(pin_mosi)     when (s_tp = '1' and s_en = '1') else '0';
    rf_loadmod_en  <= to_X01(mcu_rf_tx_en) when (s_tp = '1' and s_en = '1') else '0';

    ---------------------------------------------------------------------------
    -- EXT_LM as the field-detector output [S12]/[A6]: only when the external field detector is enabled via en_fd_c<1:0> [S8].
    ---------------------------------------------------------------------------
    pin_ext_lm <= to_X01(rf_field_in) when s_fd /= "00" else '0';

    ---------------------------------------------------------------------------
    -- MCU_CLK [S7]/[A4]: out_cl = 11 holds it low.
    -- Otherwise it carries the crystal-derived clock (here rf_clk_in, passed through undivided) when en is set, else the 32 kHz LF clock unless lf_clk_off suppresses it.
    ---------------------------------------------------------------------------
    -- Free-running low-frequency clock source for MCU_CLK.
    lfgen : process
    begin
        lf_clk <= '0';
        wait for LF_HALF;
        lf_clk <= '1';
        wait for LF_HALF;
    end process lfgen;

    pin_mcu_clk <= '0'               when s_outcl = "11" else
                   to_X01(rf_clk_in) when s_en    = '1'  else
                   lf_clk            when s_lfoff = '0'  else
                   '0';

    ---------------------------------------------------------------------------
    -- IRQ pin in normal mode: [S10] active high while an UNMASKED main-interrupt status bit is set, and reading 0x1A clears it.
    -- IRQ pin in transparent mode: [S12]/[A5] the second demodulator tap.
    ---------------------------------------------------------------------------
    irq_spi <= '1' when (s_regs_a(R_IRQ_MAIN) and (not s_regs_a(R_MASK_MAIN))) /= x"00"
                   else '0';

    pin_irq <= miso_tp when s_tp = '1' else irq_spi;

    ---------------------------------------------------------------------------
    -- Gating evidence: count envelope transitions the AFE did NOT forward.
    -- Together with obs_spi_ignored_edges this makes both directions of the transparent-mode gate observable to a scoreboard.
    ---------------------------------------------------------------------------
    blocked_proc : process (rf_env_in)
        variable n : natural := 0;
    begin
        if rf_env_in'event then
            if s_tp = '0' or rx_gate = '0' then
                n := n + 1;
                obs_rf_blocked_edges <= n;
            end if;
        end if;
    end process blocked_proc;

end architecture behavioral;
