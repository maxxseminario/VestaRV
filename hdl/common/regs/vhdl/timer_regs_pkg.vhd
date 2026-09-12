-- VestaRV: TIMER register package
-- 32-bit Timer/Counter with input capture, output compare, and pulse-width modulation functionality
-- Generated from hdl/common/regs/rdl/timer.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.

library ieee;
use ieee.std_logic_1164.all;
library work;
use work.constants.all;

package timer_regs_pkg is

    -- TIMxCR: Timer/Counter control register
    constant TIMxCR_WORD              : natural := 0;
    constant TIMxCR_ADDR              : natural := 0;
    constant TIMxCR_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant TIMxCR_IMPL              : std_logic_vector(31 downto 0) := "00000000000011111111111111111111";
    constant DIV_MSB                  : natural := 19;
    constant DIV_LSB                  : natural := 16;
    constant DIV_RESET                : std_logic_vector(3 downto 0) := "0000";
    constant CMP1IH_MSB               : natural := 15;
    constant CMP1IH_LSB               : natural := 15;
    constant CMP1IH_RESET             : std_logic_vector(0 downto 0) := "0";
    constant CMP0IH_MSB               : natural := 14;
    constant CMP0IH_LSB               : natural := 14;
    constant CMP0IH_RESET             : std_logic_vector(0 downto 0) := "0";
    constant CAP1FE_MSB               : natural := 13;
    constant CAP1FE_LSB               : natural := 13;
    constant CAP1FE_RESET             : std_logic_vector(0 downto 0) := "0";
    constant CAP0FE_MSB               : natural := 12;
    constant CAP0FE_LSB               : natural := 12;
    constant CAP0FE_RESET             : std_logic_vector(0 downto 0) := "0";
    constant CAP1EN_MSB               : natural := 11;
    constant CAP1EN_LSB               : natural := 11;
    constant CAP1EN_RESET             : std_logic_vector(0 downto 0) := "0";
    constant CAP0EN_MSB               : natural := 10;
    constant CAP0EN_LSB               : natural := 10;
    constant CAP0EN_RESET             : std_logic_vector(0 downto 0) := "0";
    constant SSEL_MSB                 : natural := 9;
    constant SSEL_LSB                 : natural := 8;
    constant SSEL_RESET               : std_logic_vector(1 downto 0) := "00";
    constant CMP2RST_MSB              : natural := 7;
    constant CMP2RST_LSB              : natural := 7;
    constant CMP2RST_RESET            : std_logic_vector(0 downto 0) := "0";
    constant TEN_MSB                  : natural := 6;
    constant TEN_LSB                  : natural := 6;
    constant TEN_RESET                : std_logic_vector(0 downto 0) := "0";
    constant CAP1IE_MSB               : natural := 5;
    constant CAP1IE_LSB               : natural := 5;
    constant CAP1IE_RESET             : std_logic_vector(0 downto 0) := "0";
    constant CAP0IE_MSB               : natural := 4;
    constant CAP0IE_LSB               : natural := 4;
    constant CAP0IE_RESET             : std_logic_vector(0 downto 0) := "0";
    constant OVIE_MSB                 : natural := 3;
    constant OVIE_LSB                 : natural := 3;
    constant OVIE_RESET               : std_logic_vector(0 downto 0) := "0";
    constant CMP2IE_MSB               : natural := 2;
    constant CMP2IE_LSB               : natural := 2;
    constant CMP2IE_RESET             : std_logic_vector(0 downto 0) := "0";
    constant CMP1IE_MSB               : natural := 1;
    constant CMP1IE_LSB               : natural := 1;
    constant CMP1IE_RESET             : std_logic_vector(0 downto 0) := "0";
    constant CMP0IE_MSB               : natural := 0;
    constant CMP0IE_LSB               : natural := 0;
    constant CMP0IE_RESET             : std_logic_vector(0 downto 0) := "0";

    -- TIMxSR: Timer/Counter status register
    constant TIMxSR_WORD              : natural := 1;
    constant TIMxSR_ADDR              : natural := 4;
    constant TIMxSR_RESET             : std_logic_vector(7 downto 0) := "00000000";
    constant TIMxSR_IMPL              : std_logic_vector(7 downto 0) := "00000000";
    constant CMP1OUT_MSB              : natural := 7;
    constant CMP1OUT_LSB              : natural := 7;
    constant CMP1OUT_RESET            : std_logic_vector(0 downto 0) := "0";
    constant CMP0OUT_MSB              : natural := 6;
    constant CMP0OUT_LSB              : natural := 6;
    constant CMP0OUT_RESET            : std_logic_vector(0 downto 0) := "0";
    constant CAP1IF_MSB               : natural := 5;
    constant CAP1IF_LSB               : natural := 5;
    constant CAP1IF_RESET             : std_logic_vector(0 downto 0) := "0";
    constant CAP0IF_MSB               : natural := 4;
    constant CAP0IF_LSB               : natural := 4;
    constant CAP0IF_RESET             : std_logic_vector(0 downto 0) := "0";
    constant OVIF_MSB                 : natural := 3;
    constant OVIF_LSB                 : natural := 3;
    constant OVIF_RESET               : std_logic_vector(0 downto 0) := "0";
    constant CMP2IF_MSB               : natural := 2;
    constant CMP2IF_LSB               : natural := 2;
    constant CMP2IF_RESET             : std_logic_vector(0 downto 0) := "0";
    constant CMP1IF_MSB               : natural := 1;
    constant CMP1IF_LSB               : natural := 1;
    constant CMP1IF_RESET             : std_logic_vector(0 downto 0) := "0";
    constant CMP0IF_MSB               : natural := 0;
    constant CMP0IF_LSB               : natural := 0;
    constant CMP0IF_RESET             : std_logic_vector(0 downto 0) := "0";

    -- TIMxVAL: Timer/Counter value register
    constant TIMxVAL_WORD             : natural := 2;
    constant TIMxVAL_ADDR             : natural := 8;
    constant TIMxVAL_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant TIMxVAL_IMPL             : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant VAL_MSB                  : natural := 31;
    constant VAL_LSB                  : natural := 0;
    constant VAL_RESET                : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- TIMxCMP0: Timer/Counter Compare 0 threshold register
    constant TIMxCMP0_WORD            : natural := 3;
    constant TIMxCMP0_ADDR            : natural := 12;
    constant TIMxCMP0_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant TIMxCMP0_IMPL            : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant CMP0_MSB                 : natural := 31;
    constant CMP0_LSB                 : natural := 0;
    constant CMP0_RESET               : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- TIMxCMP1: Timer/Counter Compare 1 threshold register
    constant TIMxCMP1_WORD            : natural := 4;
    constant TIMxCMP1_ADDR            : natural := 16;
    constant TIMxCMP1_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant TIMxCMP1_IMPL            : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant CMP1_MSB                 : natural := 31;
    constant CMP1_LSB                 : natural := 0;
    constant CMP1_RESET               : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- TIMxCMP2: Timer/Counter Compare 2 threshold register
    constant TIMxCMP2_WORD            : natural := 5;
    constant TIMxCMP2_ADDR            : natural := 20;
    constant TIMxCMP2_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant TIMxCMP2_IMPL            : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant CMP2_MSB                 : natural := 31;
    constant CMP2_LSB                 : natural := 0;
    constant CMP2_RESET               : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- TIMxCAP0: Timer/Counter Capture 0 value register
    constant TIMxCAP0_WORD            : natural := 6;
    constant TIMxCAP0_ADDR            : natural := 24;
    constant TIMxCAP0_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant TIMxCAP0_IMPL            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant CAP0_MSB                 : natural := 31;
    constant CAP0_LSB                 : natural := 0;
    constant CAP0_RESET               : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- TIMxCAP1: Timer/Counter Capture 1 value register
    constant TIMxCAP1_WORD            : natural := 7;
    constant TIMxCAP1_ADDR            : natural := 28;
    constant TIMxCAP1_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant TIMxCAP1_IMPL            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant CAP1_MSB                 : natural := 31;
    constant CAP1_LSB                 : natural := 0;
    constant CAP1_RESET               : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- TIMER.vhd's own decode identifiers: the word each register is
    -- decoded at, spelled the way that file already spells it, so adopting this
    -- package is a context clause plus a deletion and no assignment moves.
    constant RegSlotTIMxCR            : natural := 0;
    constant RegSlotTIMxSR            : natural := 1;
    constant RegSlotTIMxVAL           : natural := 2;
    constant RegSlotTIMxCMP0          : natural := 3;
    constant RegSlotTIMxCMP1          : natural := 4;
    constant RegSlotTIMxCMP2          : natural := 5;
    constant RegSlotTIMxCAP0          : natural := 6;
    constant RegSlotTIMxCAP1          : natural := 7;

    -- periph_regs tables (hdl/common/periph_regs.vhd), one row per word in slot
    -- order. Every mask below is a property of this description. RDTHRU, WIDEWR,
    -- FULLWR and STROBE_HOLD are the entity's own and are set at the instance;
    -- hdl/common/regs/REGFILE.md says why they cannot come from SystemRDL.
    constant NWORDS                   : natural := 8;
    subtype  reg_arr_t is word_array(0 to NWORDS-1);

    -- reset word, loaded on the asynchronous resetn
    constant RSTVAL   : reg_arr_t := (
        x"00000000",   -- TIMxCR
        x"00000000",   -- TIMxSR
        x"00000000",   -- TIMxVAL
        x"00000000",   -- TIMxCMP0
        x"00000000",   -- TIMxCMP1
        x"00000000",   -- TIMxCMP2
        x"00000000",   -- TIMxCAP0
        x"00000000"    -- TIMxCAP1
    );

    -- bits that hold a software-written flop; periph_regs stores exactly these
    constant IMPL     : reg_arr_t := (
        x"000FFFFF",   -- TIMxCR
        x"00000000",   -- TIMxSR
        x"FFFFFFFF",   -- TIMxVAL
        x"FFFFFFFF",   -- TIMxCMP0
        x"FFFFFFFF",   -- TIMxCMP1
        x"FFFFFFFF",   -- TIMxCMP2
        x"00000000",   -- TIMxCAP0
        x"00000000"    -- TIMxCAP1
    );

    -- a written 1 clears (onwrite = woclr): drives w1c_hit
    constant W1C      : reg_arr_t := (
        x"00000000",   -- TIMxCR
        x"0000003F",   -- TIMxSR
        x"00000000",   -- TIMxVAL
        x"00000000",   -- TIMxCMP0
        x"00000000",   -- TIMxCMP1
        x"00000000",   -- TIMxCMP2
        x"00000000",   -- TIMxCAP0
        x"00000000"    -- TIMxCAP1
    );

    -- a written 1 sets (onwrite = woset): drives woset_hit
    constant WOSET    : reg_arr_t := (
        x"00000000",   -- TIMxCR
        x"00000000",   -- TIMxSR
        x"00000000",   -- TIMxVAL
        x"00000000",   -- TIMxCMP0
        x"00000000",   -- TIMxCMP1
        x"00000000",   -- TIMxCMP2
        x"00000000",   -- TIMxCAP0
        x"00000000"    -- TIMxCAP1
    );

    -- a written 1 toggles (onwrite = wot): drives wot_hit
    constant WOT      : reg_arr_t := (
        x"00000000",   -- TIMxCR
        x"00000000",   -- TIMxSR
        x"00000000",   -- TIMxVAL
        x"00000000",   -- TIMxCMP0
        x"00000000",   -- TIMxCMP1
        x"00000000",   -- TIMxCMP2
        x"00000000",   -- TIMxCAP0
        x"00000000"    -- TIMxCAP1
    );

    -- self-clearing strobe (singlepulse): drives wr_pulse, stores nothing
    constant PULSE    : reg_arr_t := (
        x"00000000",   -- TIMxCR
        x"00000000",   -- TIMxSR
        x"00000000",   -- TIMxVAL
        x"00000000",   -- TIMxCMP0
        x"00000000",   -- TIMxCMP1
        x"00000000",   -- TIMxCMP2
        x"00000000",   -- TIMxCAP0
        x"00000000"    -- TIMxCAP1
    );

    -- a read retires (onread = rclr): drives rd_clr
    constant RCLR     : reg_arr_t := (
        x"00000000",   -- TIMxCR
        x"00000000",   -- TIMxSR
        x"00000000",   -- TIMxVAL
        x"00000000",   -- TIMxCMP0
        x"00000000",   -- TIMxCMP1
        x"00000000",   -- TIMxCMP2
        x"00000000",   -- TIMxCAP0
        x"00000000"    -- TIMxCAP1
    );

    -- bits hardware drives (hw = w or rw): what hw_we / hw_set / hw_clr may touch
    constant HWOWN    : reg_arr_t := (
        x"00000040",   -- TIMxCR
        x"000000FF",   -- TIMxSR
        x"FFFFFFFF",   -- TIMxVAL
        x"00000000",   -- TIMxCMP0
        x"00000000",   -- TIMxCMP1
        x"00000000",   -- TIMxCMP2
        x"FFFFFFFF",   -- TIMxCAP0
        x"FFFFFFFF"    -- TIMxCAP1
    );

end package timer_regs_pkg;
