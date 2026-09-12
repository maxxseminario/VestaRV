-- VestaRV: CLINT register package
-- Core-local interruptor for the five harts
-- Generated from hdl/common/regs/rdl/clint.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.
-- Configuration-dependent: only what is common to NHARTS 1, 4, 5, 18, 32 (MTIME_W = ceil(4*NHARTS/16)*4, CMP_W = MTIME_W + 4) is emitted, the rest stays a generic in clint.vhd.

library ieee;
use ieee.std_logic_1164.all;

package clint_regs_pkg is

    -- MSIP0: Hart 0 software interrupt (IPI) register
    constant MSIP0_WORD               : natural := 0;
    constant MSIP0_ADDR               : natural := 0;
    constant MSIP0_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant MSIP0_IMPL               : std_logic_vector(31 downto 0) := "00000000000000000000000000000001";
    constant CLINTMSIPH0_MSB          : natural := 0;
    constant CLINTMSIPH0_LSB          : natural := 0;
    constant CLINTMSIPH0_RESET        : std_logic_vector(0 downto 0) := "0";

    -- MTIMEL: Machine time counter, lower 32 bits
    constant MTIMEL_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant MTIMEL_IMPL              : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant CLINTMTIMEL_MSB          : natural := 31;
    constant CLINTMTIMEL_LSB          : natural := 0;
    constant CLINTMTIMEL_RESET        : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- MTIMEH: Machine time counter, upper 32 bits
    constant MTIMEH_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant MTIMEH_IMPL              : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant CLINTMTIMEH_MSB          : natural := 31;
    constant CLINTMTIMEH_LSB          : natural := 0;
    constant CLINTMTIMEH_RESET        : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- MTIMECMP0L: Hart 0 timer compare register, lower 32 bits
    constant MTIMECMP0L_RESET         : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant MTIMECMP0L_IMPL          : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant CLINTMTIMECMP0L_MSB      : natural := 31;
    constant CLINTMTIMECMP0L_LSB      : natural := 0;
    constant CLINTMTIMECMP0L_RESET    : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";

    -- MTIMECMP0H: Hart 0 timer compare register, upper 32 bits
    constant MTIMECMP0H_RESET         : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant MTIMECMP0H_IMPL          : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant CLINTMTIMECMP0H_MSB      : natural := 31;
    constant CLINTMTIMECMP0H_LSB      : natural := 0;
    constant CLINTMTIMECMP0H_RESET    : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";

    -- No periph_regs table section: the register set is a function of the hart count,
    -- so its register set is not fixed at elaboration.
    -- See hdl/common/regs/REGFILE.md.

end package clint_regs_pkg;
