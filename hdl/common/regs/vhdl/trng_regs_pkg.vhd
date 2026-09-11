-- VestaRV: TRNG register package
-- Ring-oscillator entropy source and harvest engine: a free-running ensemble of NRO ring oscillators (peripherals.trngRings, {4,8}) is XOR-reduced to one noisy bit, 2-FF synchronized into the free-running MCLK, decimated (one raw sample every 2^DECIM MCLK cycles) and direct-packed 32 raw bits at a time into a holding register
-- Generated from hdl/common/regs/rdl/trng.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.

library ieee;
use ieee.std_logic_1164.all;
library work;
use work.constants.all;

package trng_regs_pkg is

    -- TRNGxCR: TRNG control register
    constant TRNGxCR_WORD             : natural := 0;
    constant TRNGxCR_ADDR             : natural := 0;
    constant TRNGxCR_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant TRNGxCR_IMPL             : std_logic_vector(31 downto 0) := "00000000000000000000111111110111";
    constant TRNGDECIM_MSB            : natural := 11;
    constant TRNGDECIM_LSB            : natural := 8;
    constant TRNGDECIM_RESET          : std_logic_vector(3 downto 0) := "0000";
    constant TRNGROSEL_MSB            : natural := 7;
    constant TRNGROSEL_LSB            : natural := 4;
    constant TRNGROSEL_RESET          : std_logic_vector(3 downto 0) := "0000";
    constant TRNGALMIE_MSB            : natural := 2;
    constant TRNGALMIE_LSB            : natural := 2;
    constant TRNGALMIE_RESET          : std_logic_vector(0 downto 0) := "0";
    constant TRNGDRDYIE_MSB           : natural := 1;
    constant TRNGDRDYIE_LSB           : natural := 1;
    constant TRNGDRDYIE_RESET         : std_logic_vector(0 downto 0) := "0";
    constant TRNGEN_MSB               : natural := 0;
    constant TRNGEN_LSB               : natural := 0;
    constant TRNGEN_RESET             : std_logic_vector(0 downto 0) := "0";

    -- TRNGxSR: TRNG status register
    constant TRNGxSR_WORD             : natural := 1;
    constant TRNGxSR_ADDR             : natural := 4;
    constant TRNGxSR_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant TRNGxSR_IMPL             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant TRNGRUN_MSB              : natural := 2;
    constant TRNGRUN_LSB              : natural := 2;
    constant TRNGRUN_RESET            : std_logic_vector(0 downto 0) := "0";
    constant TRNGALMF_MSB             : natural := 1;
    constant TRNGALMF_LSB             : natural := 1;
    constant TRNGALMF_RESET           : std_logic_vector(0 downto 0) := "0";
    constant TRNGDRDY_MSB             : natural := 0;
    constant TRNGDRDY_LSB             : natural := 0;
    constant TRNGDRDY_RESET           : std_logic_vector(0 downto 0) := "0";

    -- TRNGxDR: Entropy data register
    constant TRNGxDR_WORD             : natural := 2;
    constant TRNGxDR_ADDR             : natural := 8;
    constant TRNGxDR_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant TRNGxDR_IMPL             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant TRNGDR_MSB               : natural := 31;
    constant TRNGDR_LSB               : natural := 0;
    constant TRNGDR_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- TRNGxHT: Health-test control/diagnostic register
    constant TRNGxHT_WORD             : natural := 3;
    constant TRNGxHT_ADDR             : natural := 12;
    constant TRNGxHT_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant TRNGxHT_IMPL             : std_logic_vector(31 downto 0) := "00000000000000000000000011111111";
    constant TRNGRUNLEN_MSB           : natural := 21;
    constant TRNGRUNLEN_LSB           : natural := 16;
    constant TRNGRUNLEN_RESET         : std_logic_vector(5 downto 0) := "000000";
    constant TRNGRCTC_MSB             : natural := 7;
    constant TRNGRCTC_LSB             : natural := 0;
    constant TRNGRCTC_RESET           : std_logic_vector(7 downto 0) := "00000000";

    -- TRNG.vhd's own decode identifiers: the word each register is
    -- decoded at, spelled the way that file already spells it, so adopting this
    -- package is a context clause plus a deletion and no assignment moves.
    constant SLOT_CR                  : natural := 0;
    constant SLOT_SR                  : natural := 1;
    constant SLOT_DR                  : natural := 2;
    constant SLOT_HT                  : natural := 3;

    -- periph_regs tables (hdl/common/periph_regs.vhd), one row per word in slot
    -- order. Every mask below is a property of this description. RDTHRU, WIDEWR
    -- and STROBE_HOLD are the entity's own and are set at the instance;
    -- hdl/common/regs/REGFILE.md says why they cannot come from SystemRDL.
    constant NWORDS                   : natural := 4;
    subtype  reg_arr_t is word_array(0 to NWORDS-1);

    -- reset word, loaded on the asynchronous resetn
    constant RSTVAL   : reg_arr_t := (
        x"00000000",   -- TRNGxCR
        x"00000000",   -- TRNGxSR
        x"00000000",   -- TRNGxDR
        x"00000000"    -- TRNGxHT
    );

    -- bits that hold a software-written flop; periph_regs stores exactly these
    constant IMPL     : reg_arr_t := (
        x"00000FF7",   -- TRNGxCR
        x"00000000",   -- TRNGxSR
        x"00000000",   -- TRNGxDR
        x"000000FF"    -- TRNGxHT
    );

    -- a written 1 clears (onwrite = woclr): drives w1c_hit
    constant W1C      : reg_arr_t := (
        x"00000000",   -- TRNGxCR
        x"00000002",   -- TRNGxSR
        x"00000000",   -- TRNGxDR
        x"00000000"    -- TRNGxHT
    );

    -- a written 1 sets (onwrite = woset): drives woset_hit
    constant WOSET    : reg_arr_t := (
        x"00000000",   -- TRNGxCR
        x"00000000",   -- TRNGxSR
        x"00000000",   -- TRNGxDR
        x"00000000"    -- TRNGxHT
    );

    -- a written 1 toggles (onwrite = wot): drives wot_hit
    constant WOT      : reg_arr_t := (
        x"00000000",   -- TRNGxCR
        x"00000000",   -- TRNGxSR
        x"00000000",   -- TRNGxDR
        x"00000000"    -- TRNGxHT
    );

    -- self-clearing strobe (singlepulse): drives wr_pulse, stores nothing
    constant PULSE    : reg_arr_t := (
        x"00000000",   -- TRNGxCR
        x"00000000",   -- TRNGxSR
        x"00000000",   -- TRNGxDR
        x"00000000"    -- TRNGxHT
    );

    -- a read retires (onread = rclr): drives rd_clr
    constant RCLR     : reg_arr_t := (
        x"00000000",   -- TRNGxCR
        x"00000000",   -- TRNGxSR
        x"FFFFFFFF",   -- TRNGxDR
        x"00000000"    -- TRNGxHT
    );

    -- bits hardware drives (hw = w or rw): what hw_we / hw_set / hw_clr may touch
    constant HWOWN    : reg_arr_t := (
        x"00000000",   -- TRNGxCR
        x"00000007",   -- TRNGxSR
        x"FFFFFFFF",   -- TRNGxDR
        x"003F0000"    -- TRNGxHT
    );

end package trng_regs_pkg;
