-------------------------------------------------------------------------------
-- i2ct_bfm_pkg.vhd
-------------------------------------------------------------------------------
-- Bench-support helpers for the I2C TARGET peripheral testbench (tb/I2CTarget_tb.vhd).
-- I2CTarget.vhd is being written in parallel against the same FROZEN design this bench targets (~/vesta_docs/digperiphs/i2ct_design.md, D1-D20 plus the adjudicated tensions).
-- The slot numbers, CR/SR field positions and SCL-timing constants below are therefore LOCAL to this bench, mirroring onewire_bfm_pkg.vhd, rtc_bfm_pkg.vhd and i3c_bfm_pkg.vhd, and are NOT shared MemoryMap.vhd constants.
-- I2CT0 lives at 0x6A00, and MemoryMap.vhd has no I2CT0 slot constants until the generator knob peripherals.i2ctarget is on (D20).
--
-- CHECKER INDEPENDENCE (the task's binding instruction, and the OneWire/I3C lesson): this package provides ONLY bus-level register plumbing, register-map constants, and TIME-DOMAIN SCL-timing constants derived from the frozen doc's ratio guarantee (D14: f_SCL at most mclk/24), never from I2CTarget.vhd.
-- The host model (i2c_host_model.vhd) multiplies these tick counts by the bench's OWN `tick_period`, a TB-known constant equal to one `clk` period, to get real simulation-time SCL windows.
-- It never reads I2CTarget.vhd's internal FSM, SDA_DIR/SCL_DIR, or registers.
--
-- SCL to clk RATIO: the SCL half-period is I2CT_SCL_HALF_TICKS `clk` cycles, so one full SCL period is 2*I2CT_SCL_HALF_TICKS = 32 clk, a ratio of 32:1.
-- That is comfortably above the frozen-doc guaranteed floor of 24:1 (D14) and about 8x the 4-clk FSM edge-to-drive latency (D14/D15) in each half-period.
-- It is chosen fast, nearer the ratio floor than the 240:1 a 100 kHz bus would give, so wall-clock stays well under the 1-MINUTE RULE.
--
-- Calling convention for the bounded polls copies onewire_bfm_pkg exactly:
-- (signal clk, signal b, signal read_data, [args], done_ok : out boolean).
-- The caller turns done_ok into a scoreboard pass/fail (sb.check_true), so a poll that never satisfies its condition FAILS the run instead of hanging.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.periph_tb_pkg.all;

package i2ct_bfm_pkg is

    -- ---- register word-slot map (frozen, design doc D5) -------------------
    constant I2CT_SLOT_CR  : natural := 0;   -- rw: EN/GCEN/CSEN/IE, SAD, SADM
    constant I2CT_SLOT_SR  : natural := 1;   -- mixed: read-only levels plus W1C events
    constant I2CT_SLOT_TX  : natural := 2;   -- rw: transmit byte (write loads)
    constant I2CT_SLOT_RX  : natural := 3;   -- ro: last received byte (D9)
    constant I2CT_SLOT_WDG : natural := 4;   -- rw: SCL-low watchdog timeout

    -- ---- I2CTCR bit positions (design doc D5, slot 0) ---------------------
    constant I2CT_CR_EN     : natural := 0;
    constant I2CT_CR_GCEN   : natural := 1;
    constant I2CT_CR_CSEN   : natural := 2;
    constant I2CT_CR_AEIE   : natural := 3;
    constant I2CT_CR_DATAIE : natural := 4;
    -- SAD[6:0] is bits 14:8 and SADM[6:0] is bits 22:16.
    constant I2CT_CR_SAD_LO  : natural := 8;
    constant I2CT_CR_SADM_LO : natural := 16;

    -- ---- I2CTSR bit positions (design doc D5, slot 1) ---------------------
    constant I2CT_SR_BUSY    : natural := 0;   -- r
    constant I2CT_SR_TM      : natural := 1;   -- r  (1 = target-transmitter)
    constant I2CT_SR_AMF     : natural := 2;   -- w1c
    constant I2CT_SR_GCF     : natural := 3;   -- w1c
    constant I2CT_SR_RXF     : natural := 4;   -- w1c (frees the RX buffer)
    constant I2CT_SR_TXE     : natural := 5;   -- r
    constant I2CT_SR_OVF     : natural := 6;   -- w1c
    constant I2CT_SR_NACKF   : natural := 7;   -- w1c
    constant I2CT_SR_STOPF   : natural := 8;   -- w1c
    constant I2CT_SR_RSTARTF : natural := 9;   -- w1c
    constant I2CT_SR_ERRF    : natural := 10;  -- w1c (watchdog or protocol error)

    -- ---- host-model transaction op codes ----------------------------------
    constant I2CT_OP_XFER : natural := 0;   -- normal framed segment (S or Sr, data, STOP)
    constant I2CT_OP_WDOG : natural := 1;   -- START plus address, hold SCL low, STOP (watchdog stimulus)

    -- ---- payload container ------------------------------------------------
    constant I2CT_MODEL_MAX_BYTES : natural := 8;
    type i2ct_byte_array is array (natural range <>) of std_logic_vector(7 downto 0);

    -- ---- SCL timing (checker-independent tick counts; see the header) ------
    constant I2CT_SCL_HALF_TICKS : natural := 16;  -- SCL half-period in clk ticks (ratio 32:1)
    constant I2CT_SCL_SAMPLE_TICKS : natural := 8;  -- ticks into tHIGH where the host samples (mid-high)
    -- Bounded guard for the host's wait-for-SCL-to-rise stretch loop (D-doc host requirement: honour stretch, but flag rather than hang).
    -- One iteration is one tick, and 20000 ticks is well inside the tb watchdog.
    constant I2CT_STRETCH_GUARD  : natural := 20000;

    -- Guard bound for the SR polls, following the roughly 20000-iteration shirq precedent.
    -- Each poll iteration is one bus_read (about 1 clk), so this trips well inside the 100 ms-class tb watchdog.
    constant I2CT_POLL_GUARD : natural := 20000;

    -- Build a full 32-bit I2CTCR word (D5 field layout).
    function i2ct_mk_cr(en, gcen, csen, aeie, dataie : std_logic;
                        sad  : std_logic_vector(6 downto 0);
                        sadm : std_logic_vector(6 downto 0))
        return std_logic_vector;

    -- Bounded poll of a single I2CTSR flag bit until it reads exp_val.
    procedure i2ct_wait_flag(signal clk       : in    std_logic;
                             signal b         : inout periph_bus_t;
                             signal read_data : in    std_logic_vector(31 downto 0);
                             bit_idx          : in    natural;
                             exp_val          : in    std_logic;
                             done_ok          : out   boolean);

    -- Bounded poll of I2CTSR.BUSY (bit 0) until it reads '0' (D12: BUSY drops on STOP or watchdog abort).
    -- done_ok comes back false (the poll never hangs) if BUSY has not cleared within the guard count.
    procedure i2ct_wait_busy_clear(signal clk       : in    std_logic;
                                   signal b         : inout periph_bus_t;
                                   signal read_data : in    std_logic_vector(31 downto 0);
                                   done_ok          : out   boolean);

end package i2ct_bfm_pkg;


package body i2ct_bfm_pkg is

    function i2ct_mk_cr(en, gcen, csen, aeie, dataie : std_logic;
                        sad  : std_logic_vector(6 downto 0);
                        sadm : std_logic_vector(6 downto 0))
        return std_logic_vector is
        variable v : std_logic_vector(31 downto 0) := (others => '0');
    begin
        v(I2CT_CR_EN)     := en;
        v(I2CT_CR_GCEN)   := gcen;
        v(I2CT_CR_CSEN)   := csen;
        v(I2CT_CR_AEIE)   := aeie;
        v(I2CT_CR_DATAIE) := dataie;
        v(I2CT_CR_SAD_LO  + 6 downto I2CT_CR_SAD_LO)  := sad;
        v(I2CT_CR_SADM_LO + 6 downto I2CT_CR_SADM_LO) := sadm;
        return v;
    end function;

    procedure i2ct_wait_flag(signal clk       : in    std_logic;
                             signal b         : inout periph_bus_t;
                             signal read_data : in    std_logic_vector(31 downto 0);
                             bit_idx          : in    natural;
                             exp_val          : in    std_logic;
                             done_ok          : out   boolean) is
        variable s     : std_logic_vector(31 downto 0);
        variable guard : natural := 0;
    begin
        done_ok := false;
        loop
            bus_read(clk, b, read_data, I2CT_SLOT_SR, s);
            if to_X01(s(bit_idx)) = exp_val then
                done_ok := true;
                exit;
            end if;
            guard := guard + 1;
            exit when guard > I2CT_POLL_GUARD;   -- bounded (never hangs)
        end loop;
    end procedure;

    procedure i2ct_wait_busy_clear(signal clk       : in    std_logic;
                                   signal b         : inout periph_bus_t;
                                   signal read_data : in    std_logic_vector(31 downto 0);
                                   done_ok          : out   boolean) is
        variable s     : std_logic_vector(31 downto 0);
        variable guard : natural := 0;
    begin
        done_ok := false;
        loop
            bus_read(clk, b, read_data, I2CT_SLOT_SR, s);
            if to_X01(s(I2CT_SR_BUSY)) = '0' then
                done_ok := true;
                exit;
            end if;
            guard := guard + 1;
            exit when guard > I2CT_POLL_GUARD;   -- bounded (never hangs)
        end loop;
    end procedure;

end package body i2ct_bfm_pkg;
