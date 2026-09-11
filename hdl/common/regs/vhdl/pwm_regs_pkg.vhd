-- VestaRV: PWM register package
-- Buffered PWM Generator: a glitch-free 2-channel edge-aligned PWM engine (16-bit period + two 16-bit per-channel duties) with double-buffered waveform update, per-channel polarity and an absolute programmable safe/off level, a software fault trip that forces both outputs safe the same cycle, and a period-event tick
-- Generated from hdl/common/regs/rdl/pwm.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.

library ieee;
use ieee.std_logic_1164.all;

package pwm_regs_pkg is

    -- PWMxCR: PWM control register
    constant PWMxCR_WORD              : natural := 0;
    constant PWMxCR_ADDR              : natural := 0;
    constant PWMxCR_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PWMxCR_IMPL              : std_logic_vector(31 downto 0) := "00000000000011110001000110000111";
    constant PSC_MSB                  : natural := 19;
    constant PSC_LSB                  : natural := 16;
    constant PSC_RESET                : std_logic_vector(3 downto 0) := "0000";
    constant FLTTRIG_MSB              : natural := 14;
    constant FLTTRIG_LSB              : natural := 14;
    constant FLTTRIG_RESET            : std_logic_vector(0 downto 0) := "0";
    constant FLTEN_MSB                : natural := 12;
    constant FLTEN_LSB                : natural := 12;
    constant FLTEN_RESET              : std_logic_vector(0 downto 0) := "0";
    constant FLTIE_MSB                : natural := 8;
    constant FLTIE_LSB                : natural := 8;
    constant FLTIE_RESET              : std_logic_vector(0 downto 0) := "0";
    constant PEVIE_MSB                : natural := 7;
    constant PEVIE_LSB                : natural := 7;
    constant PEVIE_RESET              : std_logic_vector(0 downto 0) := "0";
    constant CH1EN_MSB                : natural := 2;
    constant CH1EN_LSB                : natural := 2;
    constant CH1EN_RESET              : std_logic_vector(0 downto 0) := "0";
    constant CH0EN_MSB                : natural := 1;
    constant CH0EN_LSB                : natural := 1;
    constant CH0EN_RESET              : std_logic_vector(0 downto 0) := "0";
    constant PWMEN_MSB                : natural := 0;
    constant PWMEN_LSB                : natural := 0;
    constant PWMEN_RESET              : std_logic_vector(0 downto 0) := "0";

    -- PWMxPER: PWM period modulus (buffered, D9)
    constant PWMxPER_WORD             : natural := 1;
    constant PWMxPER_ADDR             : natural := 4;
    constant PWMxPER_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PWMxPER_IMPL             : std_logic_vector(31 downto 0) := "00000000000000001111111111111111";
    constant PWMPER_MSB               : natural := 15;
    constant PWMPER_LSB               : natural := 0;
    constant PWMPER_RESET             : std_logic_vector(15 downto 0) := "0000000000000000";

    -- PWMxDTY0: Channel 0 duty compare (buffered, D9)
    constant PWMxDTY0_WORD            : natural := 2;
    constant PWMxDTY0_ADDR            : natural := 8;
    constant PWMxDTY0_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PWMxDTY0_IMPL            : std_logic_vector(31 downto 0) := "00000000000000001111111111111111";
    constant PWMDTY0_MSB              : natural := 15;
    constant PWMDTY0_LSB              : natural := 0;
    constant PWMDTY0_RESET            : std_logic_vector(15 downto 0) := "0000000000000000";

    -- PWMxDTY1: Channel 1 duty compare (buffered, D9)
    constant PWMxDTY1_WORD            : natural := 3;
    constant PWMxDTY1_ADDR            : natural := 12;
    constant PWMxDTY1_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PWMxDTY1_IMPL            : std_logic_vector(31 downto 0) := "00000000000000001111111111111111";
    constant PWMDTY1_MSB              : natural := 15;
    constant PWMDTY1_LSB              : natural := 0;
    constant PWMDTY1_RESET            : std_logic_vector(15 downto 0) := "0000000000000000";

    -- PWMxDTY2: Reserved for the channel 2 duty compare (4-channel bolt-on, D16)
    constant PWMxDTY2_WORD            : natural := 4;
    constant PWMxDTY2_ADDR            : natural := 16;
    constant PWMxDTY2_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PWMxDTY2_IMPL            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- PWMxDTY3: Reserved for the channel 3 duty compare (4-channel bolt-on, D16)
    constant PWMxDTY3_WORD            : natural := 5;
    constant PWMxDTY3_ADDR            : natural := 20;
    constant PWMxDTY3_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PWMxDTY3_IMPL            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- PWMxPOL: Per-channel polarity and absolute safe/off level (immediate, NOT buffered, D11; program before enabling)
    constant PWMxPOL_WORD             : natural := 6;
    constant PWMxPOL_ADDR             : natural := 24;
    constant PWMxPOL_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PWMxPOL_IMPL             : std_logic_vector(31 downto 0) := "00000000000000000000000000110011";
    constant SAFE1_MSB                : natural := 5;
    constant SAFE1_LSB                : natural := 5;
    constant SAFE1_RESET              : std_logic_vector(0 downto 0) := "0";
    constant SAFE0_MSB                : natural := 4;
    constant SAFE0_LSB                : natural := 4;
    constant SAFE0_RESET              : std_logic_vector(0 downto 0) := "0";
    constant POL1_MSB                 : natural := 1;
    constant POL1_LSB                 : natural := 1;
    constant POL1_RESET               : std_logic_vector(0 downto 0) := "0";
    constant POL0_MSB                 : natural := 0;
    constant POL0_LSB                 : natural := 0;
    constant POL0_RESET               : std_logic_vector(0 downto 0) := "0";

    -- PWMxDT: Reserved for the deadtime value (deadtime / complementary-pair bolt-on, D16)
    constant PWMxDT_WORD              : natural := 7;
    constant PWMxDT_ADDR              : natural := 28;
    constant PWMxDT_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PWMxDT_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- PWMxSR: PWM status register
    constant PWMxSR_WORD              : natural := 8;
    constant PWMxSR_ADDR              : natural := 32;
    constant PWMxSR_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PWMxSR_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant UPDF_MSB                 : natural := 2;
    constant UPDF_LSB                 : natural := 2;
    constant UPDF_RESET               : std_logic_vector(0 downto 0) := "0";
    constant PEVF_MSB                 : natural := 1;
    constant PEVF_LSB                 : natural := 1;
    constant PEVF_RESET               : std_logic_vector(0 downto 0) := "0";
    constant FLTF_MSB                 : natural := 0;
    constant FLTF_LSB                 : natural := 0;
    constant FLTF_RESET               : std_logic_vector(0 downto 0) := "0";

    -- PWM.vhd's own decode identifiers: the word each register is
    -- decoded at, spelled the way that file already spells it, so adopting this
    -- package is a context clause plus a deletion and no assignment moves.
    constant SLOT_CR                  : natural := 0;
    constant SLOT_PER                 : natural := 1;
    constant SLOT_DTY0                : natural := 2;
    constant SLOT_DTY1                : natural := 3;
    constant SLOT_DTY2                : natural := 4;
    constant SLOT_DTY3                : natural := 5;
    constant SLOT_POL                 : natural := 6;
    constant SLOT_DT                  : natural := 7;
    constant SLOT_SR                  : natural := 8;

end package pwm_regs_pkg;
