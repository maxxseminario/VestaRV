-------------------------------------------------------------------------------
-- i2ct_bfm_pkg.vhd
-------------------------------------------------------------------------------
-- Bench-support helpers for the I2C target peripheral testbench (tb/I2CTarget_tb.vhd).
-- Slot numbers, CR/SR field positions and SCL-timing constants are LOCAL to this bench: I2CT0 sits at 0x6A00 and MemoryMap.vhd carries no I2CT0 constants.
-- The host model (i2c_host_model.vhd) scales these tick counts by one clk period to get real SCL windows; no I2CTarget.vhd internal is ever read.
-- The SCL half-period is I2CT_SCL_HALF_TICKS clk cycles, so a full SCL period is 32 clk: above the 24:1 ratio the target guarantees and about 8x its 4-clk edge-to-drive latency per half-period, while keeping wall-clock short.
-- Bounded polls end with done_ok, which the caller turns into a scoreboard check, so a poll that never satisfies its condition fails the run instead of hanging.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.periph_tb_pkg.all;

package i2ct_bfm_pkg is

    -- ---- register word-slot map -------------------------------------------
    constant I2CT_SLOT_CR  : natural := 0;   -- rw: EN/GCEN/CSEN/IE, SAD, SADM
    constant I2CT_SLOT_SR  : natural := 1;   -- mixed: read-only levels plus W1C events
    constant I2CT_SLOT_TX  : natural := 2;   -- rw: transmit byte (write loads)
    constant I2CT_SLOT_RX  : natural := 3;   -- ro: last received byte
    constant I2CT_SLOT_WDG : natural := 4;   -- rw: SCL-low watchdog timeout

    -- ---- I2CTCR bit positions (slot 0) ------------------------------------
    constant I2CT_CR_EN     : natural := 0;
    constant I2CT_CR_GCEN   : natural := 1;
    constant I2CT_CR_CSEN   : natural := 2;
    constant I2CT_CR_AEIE   : natural := 3;
    constant I2CT_CR_DATAIE : natural := 4;
    -- SAD[6:0] is bits 14:8 and SADM[6:0] is bits 22:16.
    constant I2CT_CR_SAD_LO  : natural := 8;
    constant I2CT_CR_SADM_LO : natural := 16;

    -- ---- I2CTSR bit positions (slot 1) ------------------------------------
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

    -- ---- SCL timing, in clk ticks -----------------------------------------
    constant I2CT_SCL_HALF_TICKS : natural := 16;  -- SCL half-period in clk ticks (ratio 32:1)
    constant I2CT_SCL_SAMPLE_TICKS : natural := 8;  -- ticks into tHIGH where the host samples (mid-high)
    -- Bounded guard for the host's wait-for-SCL-to-rise loop: clock stretch is honoured but flagged rather than waited on forever.
    constant I2CT_STRETCH_GUARD  : natural := 20000;

    -- Guard bound for the SR polls; one iteration is a bus_read of about 1 clk, so this trips well inside the tb watchdog.
    constant I2CT_POLL_GUARD : natural := 20000;

    -- Build a full 32-bit I2CTCR word.
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

    -- Bounded poll of I2CTSR.BUSY (bit 0) until it reads '0'; BUSY drops on STOP or watchdog abort.
    -- done_ok comes back false, never a hang, if BUSY has not cleared within the guard count.
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
