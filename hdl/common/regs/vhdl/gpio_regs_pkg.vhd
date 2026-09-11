-- VestaRV: GPIO register package
-- General Purpose Input Output
-- Generated from hdl/common/regs/rdl/gpio.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.

library ieee;
use ieee.std_logic_1164.all;

package gpio_regs_pkg is

    -- PxIN: GPIO read pin register
    constant PxIN_WORD                : natural := 0;
    constant PxIN_ADDR                : natural := 0;
    constant PxIN_RESET               : std_logic_vector(7 downto 0) := "00000000";
    constant PxIN_IMPL                : std_logic_vector(7 downto 0) := "00000000";
    constant PxIN_MSB                 : natural := 7;
    constant PxIN_LSB                 : natural := 0;
    -- PxIN_RESET is the register constant above; this field carries the register name.

    -- PxOUT: GPIO output drive register
    constant PxOUT_WORD               : natural := 1;
    constant PxOUT_ADDR               : natural := 4;
    constant PxOUT_RESET              : std_logic_vector(7 downto 0) := "00000000";
    constant PxOUT_IMPL               : std_logic_vector(7 downto 0) := "11111111";
    constant PxOUT_MSB                : natural := 7;
    constant PxOUT_LSB                : natural := 0;
    -- PxOUT_RESET is the register constant above; this field carries the register name.

    -- PxOUTS: GPIO output drive set register
    constant PxOUTS_WORD              : natural := 2;
    constant PxOUTS_ADDR              : natural := 8;
    constant PxOUTS_RESET             : std_logic_vector(7 downto 0) := "00000000";
    constant PxOUTS_IMPL              : std_logic_vector(7 downto 0) := "00000000";
    constant PxOUTS_MSB               : natural := 7;
    constant PxOUTS_LSB               : natural := 0;
    -- PxOUTS_RESET is the register constant above; this field carries the register name.

    -- PxOUTC: GPIO output drive clear register
    constant PxOUTC_WORD              : natural := 3;
    constant PxOUTC_ADDR              : natural := 12;
    constant PxOUTC_RESET             : std_logic_vector(7 downto 0) := "00000000";
    constant PxOUTC_IMPL              : std_logic_vector(7 downto 0) := "00000000";
    constant PxOUTC_MSB               : natural := 7;
    constant PxOUTC_LSB               : natural := 0;
    -- PxOUTC_RESET is the register constant above; this field carries the register name.

    -- PxOUTT: GPIO output drive toggle register
    constant PxOUTT_WORD              : natural := 4;
    constant PxOUTT_ADDR              : natural := 16;
    constant PxOUTT_RESET             : std_logic_vector(7 downto 0) := "00000000";
    constant PxOUTT_IMPL              : std_logic_vector(7 downto 0) := "00000000";
    constant PxOUTT_MSB               : natural := 7;
    constant PxOUTT_LSB               : natural := 0;
    -- PxOUTT_RESET is the register constant above; this field carries the register name.

    -- PxDIR: GPIO pin direction register
    constant PxDIR_WORD               : natural := 5;
    constant PxDIR_ADDR               : natural := 20;
    constant PxDIR_RESET              : std_logic_vector(7 downto 0) := "00000000";
    constant PxDIR_IMPL               : std_logic_vector(7 downto 0) := "11111111";
    constant PxDIR_MSB                : natural := 7;
    constant PxDIR_LSB                : natural := 0;
    -- PxDIR_RESET is the register constant above; this field carries the register name.

    -- PxIF: GPIO interrupt flag register
    constant PxIF_WORD                : natural := 6;
    constant PxIF_ADDR                : natural := 24;
    constant PxIF_RESET               : std_logic_vector(7 downto 0) := "00000000";
    constant PxIF_IMPL                : std_logic_vector(7 downto 0) := "00000000";
    constant PxIF_MSB                 : natural := 7;
    constant PxIF_LSB                 : natural := 0;
    -- PxIF_RESET is the register constant above; this field carries the register name.

    -- PxIES: GPIO interrupt edge select register
    constant PxIES_WORD               : natural := 7;
    constant PxIES_ADDR               : natural := 28;
    constant PxIES_RESET              : std_logic_vector(7 downto 0) := "00000000";
    constant PxIES_IMPL               : std_logic_vector(7 downto 0) := "11111111";
    constant PxIES_MSB                : natural := 7;
    constant PxIES_LSB                : natural := 0;
    -- PxIES_RESET is the register constant above; this field carries the register name.

    -- PxIE: GPIO interrupt enable register
    constant PxIE_WORD                : natural := 8;
    constant PxIE_ADDR                : natural := 32;
    constant PxIE_RESET               : std_logic_vector(7 downto 0) := "00000000";
    constant PxIE_IMPL                : std_logic_vector(7 downto 0) := "11111111";
    constant PxIE_MSB                 : natural := 7;
    constant PxIE_LSB                 : natural := 0;
    -- PxIE_RESET is the register constant above; this field carries the register name.

    -- PxSEL: GPIO peripheral select register
    constant PxSEL_WORD               : natural := 9;
    constant PxSEL_ADDR               : natural := 36;
    constant PxSEL_RESET              : std_logic_vector(7 downto 0) := "00000000";
    constant PxSEL_IMPL               : std_logic_vector(7 downto 0) := "11111111";
    constant PxSEL_MSB                : natural := 7;
    constant PxSEL_LSB                : natural := 0;
    -- PxSEL_RESET is the register constant above; this field carries the register name.

    -- PxREN: GPIO resistor enable register
    constant PxREN_WORD               : natural := 10;
    constant PxREN_ADDR               : natural := 40;
    constant PxREN_RESET              : std_logic_vector(7 downto 0) := "00000000";
    constant PxREN_IMPL               : std_logic_vector(7 downto 0) := "11111111";
    constant PxREN_MSB                : natural := 7;
    constant PxREN_LSB                : natural := 0;
    -- PxREN_RESET is the register constant above; this field carries the register name.

    -- PxAFS: GPIO alternate function select register
    constant PxAFS_WORD               : natural := 11;
    constant PxAFS_ADDR               : natural := 44;
    constant PxAFS_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PxAFS_IMPL               : std_logic_vector(31 downto 0) := "01110111011101110111011101110111";
    constant PxAFS7_MSB               : natural := 30;
    constant PxAFS7_LSB               : natural := 28;
    constant PxAFS7_RESET             : std_logic_vector(2 downto 0) := "000";
    constant PxAFS6_MSB               : natural := 26;
    constant PxAFS6_LSB               : natural := 24;
    constant PxAFS6_RESET             : std_logic_vector(2 downto 0) := "000";
    constant PxAFS5_MSB               : natural := 22;
    constant PxAFS5_LSB               : natural := 20;
    constant PxAFS5_RESET             : std_logic_vector(2 downto 0) := "000";
    constant PxAFS4_MSB               : natural := 18;
    constant PxAFS4_LSB               : natural := 16;
    constant PxAFS4_RESET             : std_logic_vector(2 downto 0) := "000";
    constant PxAFS3_MSB               : natural := 14;
    constant PxAFS3_LSB               : natural := 12;
    constant PxAFS3_RESET             : std_logic_vector(2 downto 0) := "000";
    constant PxAFS2_MSB               : natural := 10;
    constant PxAFS2_LSB               : natural := 8;
    constant PxAFS2_RESET             : std_logic_vector(2 downto 0) := "000";
    constant PxAFS1_MSB               : natural := 6;
    constant PxAFS1_LSB               : natural := 4;
    constant PxAFS1_RESET             : std_logic_vector(2 downto 0) := "000";
    constant PxAFS0_MSB               : natural := 2;
    constant PxAFS0_LSB               : natural := 0;
    constant PxAFS0_RESET             : std_logic_vector(2 downto 0) := "000";

    -- PxTASK: GPIO event-fabric task pin-select register
    constant PxTASK_WORD              : natural := 12;
    constant PxTASK_ADDR              : natural := 48;
    constant PxTASK_RESET             : std_logic_vector(7 downto 0) := "00000000";
    constant PxTASK_IMPL              : std_logic_vector(7 downto 0) := "11111111";
    constant PxTASK_MSB               : natural := 7;
    constant PxTASK_LSB               : natural := 0;
    -- PxTASK_RESET is the register constant above; this field carries the register name.

end package gpio_regs_pkg;
