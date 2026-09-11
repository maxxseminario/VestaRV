-- VestaRV: PWR_CTRL register package
-- Power controller for the switchable hart-tile power domains (M17 MTCMOS cold-gating)
-- Generated from hdl/common/regs/rdl/pwr_ctrl.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.
-- Configuration-dependent: only what is common to NHARTS 1, 5, 8, 9, 18, 32 (the PWRSR word count is ceil(NHARTS/8)) is emitted, the rest stays a generic in pwr_ctrl.vhd.

library ieee;
use ieee.std_logic_1164.all;

package pwr_ctrl_regs_pkg is

    -- PWRCR: Power gate control
    constant PWRCR_WORD               : natural := 0;
    constant PWRCR_ADDR               : natural := 0;
    constant PWRCR_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PWRH0_MSB                : natural := 0;
    constant PWRH0_LSB                : natural := 0;
    constant PWRH0_RESET              : std_logic_vector(0 downto 0) := "0";

    -- PWRSR: Power sequencer state, one read-only nibble per hart (bits 4h+3:4h)
    constant PWRST0_MSB               : natural := 3;
    constant PWRST0_LSB               : natural := 0;
    constant PWRST0_RESET             : std_logic_vector(3 downto 0) := "0000";

    -- PWRWAKE: Boot gate and wake source control
    constant PWRWAKE_WORD             : natural := 5;
    constant PWRWAKE_ADDR             : natural := 20;
    constant PWRWAKE_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PWRWAKE_IMPL             : std_logic_vector(31 downto 0) := "00000000000000000000000000011111";
    constant PWREHOLD_MSB             : natural := 4;
    constant PWREHOLD_LSB             : natural := 4;
    constant PWREHOLD_RESET           : std_logic_vector(0 downto 0) := "0";
    constant PWSWRLS_MSB              : natural := 3;
    constant PWSWRLS_LSB              : natural := 3;
    constant PWSWRLS_RESET            : std_logic_vector(0 downto 0) := "0";
    constant PWRLSFIELD_MSB           : natural := 2;
    constant PWRLSFIELD_LSB           : natural := 2;
    constant PWRLSFIELD_RESET         : std_logic_vector(0 downto 0) := "0";
    constant PWRLSPGOOD_MSB           : natural := 1;
    constant PWRLSPGOOD_LSB           : natural := 1;
    constant PWRLSPGOOD_RESET         : std_logic_vector(0 downto 0) := "0";
    constant PWGATEEN_MSB             : natural := 0;
    constant PWGATEEN_LSB             : natural := 0;
    constant PWGATEEN_RESET           : std_logic_vector(0 downto 0) := "0";

    -- PWRSTS: Boot gate and wake source status, read only: the synchronized live pad levels, the one-shot strap sample that selects the harvested-boot branch of the boot ROM, and the gate state
    constant PWRSTS_WORD              : natural := 6;
    constant PWRSTS_ADDR              : natural := 24;
    constant PWRSTS_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PWRSTS_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PWRRLSLATCH_MSB          : natural := 5;
    constant PWRRLSLATCH_LSB          : natural := 5;
    constant PWRRLSLATCH_RESET        : std_logic_vector(0 downto 0) := "0";
    constant PWBOOTHOLD_MSB           : natural := 4;
    constant PWBOOTHOLD_LSB           : natural := 4;
    constant PWBOOTHOLD_RESET         : std_logic_vector(0 downto 0) := "0";
    constant PWSTRAPVLD_MSB           : natural := 3;
    constant PWSTRAPVLD_LSB           : natural := 3;
    constant PWSTRAPVLD_RESET         : std_logic_vector(0 downto 0) := "0";
    constant PWSTRAP_MSB              : natural := 2;
    constant PWSTRAP_LSB              : natural := 2;
    constant PWSTRAP_RESET            : std_logic_vector(0 downto 0) := "0";
    constant PWFIELDLIV_MSB           : natural := 1;
    constant PWFIELDLIV_LSB           : natural := 1;
    constant PWFIELDLIV_RESET         : std_logic_vector(0 downto 0) := "0";
    constant PWPGOODLIV_MSB           : natural := 0;
    constant PWPGOODLIV_LSB           : natural := 0;
    constant PWPGOODLIV_RESET         : std_logic_vector(0 downto 0) := "0";

    -- TASKWKM: Event-fabric task-wake mask, one bit per gateable tile hart
    constant TASKWKM_WORD             : natural := 7;
    constant TASKWKM_ADDR             : natural := 28;
    constant TASKWKM_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- pwr_ctrl.vhd's own decode identifiers: the word each register is
    -- decoded at, spelled the way that file already spells it, so adopting this
    -- package is a context clause plus a deletion and no assignment moves.
    constant W_PWRWAKE                : natural := 5;
    constant W_PWRSTS                 : natural := 6;
    constant W_TASKWKM                : natural := 7;

end package pwr_ctrl_regs_pkg;
