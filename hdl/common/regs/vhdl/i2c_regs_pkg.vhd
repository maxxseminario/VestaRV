-- VestaRV: I2C register package
-- I2C serial port interface
-- Generated from hdl/common/regs/rdl/i2c.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.

library ieee;
use ieee.std_logic_1164.all;

package i2c_regs_pkg is

    -- I2CxCR: I2C control register
    constant I2CxCR_WORD              : natural := 0;
    constant I2CxCR_ADDR              : natural := 0;
    constant I2CxCR_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant I2CxCR_IMPL              : std_logic_vector(31 downto 0) := "00000000001111111111111111111111";
    constant I2CMEN_MSB               : natural := 21;
    constant I2CMEN_LSB               : natural := 21;
    constant I2CMEN_RESET             : std_logic_vector(0 downto 0) := "0";
    constant I2CSEN_MSB               : natural := 20;
    constant I2CSEN_LSB               : natural := 20;
    constant I2CSEN_RESET             : std_logic_vector(0 downto 0) := "0";
    constant I2CSN_MSB                : natural := 19;
    constant I2CSN_LSB                : natural := 19;
    constant I2CSN_RESET              : std_logic_vector(0 downto 0) := "0";
    constant I2CSCS_MSB               : natural := 18;
    constant I2CSCS_LSB               : natural := 18;
    constant I2CSCS_RESET             : std_logic_vector(0 downto 0) := "0";
    constant I2CGCE_MSB               : natural := 17;
    constant I2CGCE_LSB               : natural := 17;
    constant I2CGCE_RESET             : std_logic_vector(0 downto 0) := "0";
    constant I2CMDIV_MSB              : natural := 16;
    constant I2CMDIV_LSB              : natural := 13;
    constant I2CMDIV_RESET            : std_logic_vector(3 downto 0) := "0000";
    constant I2CSAIE_MSB              : natural := 12;
    constant I2CSAIE_LSB              : natural := 12;
    constant I2CSAIE_RESET            : std_logic_vector(0 downto 0) := "0";
    constant I2CSTXEIE_MSB            : natural := 11;
    constant I2CSTXEIE_LSB            : natural := 11;
    constant I2CSTXEIE_RESET          : std_logic_vector(0 downto 0) := "0";
    constant I2CSOVFIE_MSB            : natural := 10;
    constant I2CSOVFIE_LSB            : natural := 10;
    constant I2CSOVFIE_RESET          : std_logic_vector(0 downto 0) := "0";
    constant I2CSNRIE_MSB             : natural := 9;
    constant I2CSNRIE_LSB             : natural := 9;
    constant I2CSNRIE_RESET           : std_logic_vector(0 downto 0) := "0";
    constant I2CSXCIE_MSB             : natural := 8;
    constant I2CSXCIE_LSB             : natural := 8;
    constant I2CSXCIE_RESET           : std_logic_vector(0 downto 0) := "0";
    constant I2CMSTSIE_MSB            : natural := 7;
    constant I2CMSTSIE_LSB            : natural := 7;
    constant I2CMSTSIE_RESET          : std_logic_vector(0 downto 0) := "0";
    constant I2CMSPSIE_MSB            : natural := 6;
    constant I2CMSPSIE_LSB            : natural := 6;
    constant I2CMSPSIE_RESET          : std_logic_vector(0 downto 0) := "0";
    constant I2CMARBIE_MSB            : natural := 5;
    constant I2CMARBIE_LSB            : natural := 5;
    constant I2CMARBIE_RESET          : std_logic_vector(0 downto 0) := "0";
    constant I2CMTXEIE_MSB            : natural := 4;
    constant I2CMTXEIE_LSB            : natural := 4;
    constant I2CMTXEIE_RESET          : std_logic_vector(0 downto 0) := "0";
    constant I2CMNRIE_MSB             : natural := 3;
    constant I2CMNRIE_LSB             : natural := 3;
    constant I2CMNRIE_RESET           : std_logic_vector(0 downto 0) := "0";
    constant I2CMXCIE_MSB             : natural := 2;
    constant I2CMXCIE_LSB             : natural := 2;
    constant I2CMXCIE_RESET           : std_logic_vector(0 downto 0) := "0";
    constant I2CSTRIE_MSB             : natural := 1;
    constant I2CSTRIE_LSB             : natural := 1;
    constant I2CSTRIE_RESET           : std_logic_vector(0 downto 0) := "0";
    constant I2CSPRIE_MSB             : natural := 0;
    constant I2CSPRIE_LSB             : natural := 0;
    constant I2CSPRIE_RESET           : std_logic_vector(0 downto 0) := "0";

    -- I2CxFCR: I2C flow control register
    constant I2CxFCR_WORD             : natural := 1;
    constant I2CxFCR_ADDR             : natural := 4;
    constant I2CxFCR_RESET            : std_logic_vector(7 downto 0) := "00000000";
    constant I2CxFCR_IMPL             : std_logic_vector(7 downto 0) := "00000000";
    constant I2CSC_MSB                : natural := 3;
    constant I2CSC_LSB                : natural := 3;
    constant I2CSC_RESET              : std_logic_vector(0 downto 0) := "0";
    constant I2CMST_MSB               : natural := 2;
    constant I2CMST_LSB               : natural := 2;
    constant I2CMST_RESET             : std_logic_vector(0 downto 0) := "0";
    constant I2CMSP_MSB               : natural := 1;
    constant I2CMSP_LSB               : natural := 1;
    constant I2CMSP_RESET             : std_logic_vector(0 downto 0) := "0";
    constant I2CMRB_MSB               : natural := 0;
    constant I2CMRB_LSB               : natural := 0;
    constant I2CMRB_RESET             : std_logic_vector(0 downto 0) := "0";

    -- I2CxSR: I2C status register
    constant I2CxSR_WORD              : natural := 2;
    constant I2CxSR_ADDR              : natural := 8;
    constant I2CxSR_RESET             : std_logic_vector(15 downto 0) := "0000000000000000";
    constant I2CxSR_IMPL              : std_logic_vector(15 downto 0) := "0000000000000000";
    constant I2CBS_MSB                : natural := 15;
    constant I2CBS_LSB                : natural := 15;
    constant I2CBS_RESET              : std_logic_vector(0 downto 0) := "0";
    constant I2CMCB_MSB               : natural := 14;
    constant I2CMCB_LSB               : natural := 14;
    constant I2CMCB_RESET             : std_logic_vector(0 downto 0) := "0";
    constant I2CSTM_MSB               : natural := 13;
    constant I2CSTM_LSB               : natural := 13;
    constant I2CSTM_RESET             : std_logic_vector(0 downto 0) := "0";
    constant I2CSA_MSB                : natural := 12;
    constant I2CSA_LSB                : natural := 12;
    constant I2CSA_RESET              : std_logic_vector(0 downto 0) := "0";
    constant I2CSTXE_MSB              : natural := 11;
    constant I2CSTXE_LSB              : natural := 11;
    constant I2CSTXE_RESET            : std_logic_vector(0 downto 0) := "0";
    constant I2CSOVF_MSB              : natural := 10;
    constant I2CSOVF_LSB              : natural := 10;
    constant I2CSOVF_RESET            : std_logic_vector(0 downto 0) := "0";
    constant I2CSNR_MSB               : natural := 9;
    constant I2CSNR_LSB               : natural := 9;
    constant I2CSNR_RESET             : std_logic_vector(0 downto 0) := "0";
    constant I2CSXC_MSB               : natural := 8;
    constant I2CSXC_LSB               : natural := 8;
    constant I2CSXC_RESET             : std_logic_vector(0 downto 0) := "0";
    constant I2CMSTS_MSB              : natural := 7;
    constant I2CMSTS_LSB              : natural := 7;
    constant I2CMSTS_RESET            : std_logic_vector(0 downto 0) := "0";
    constant I2CMSPS_MSB              : natural := 6;
    constant I2CMSPS_LSB              : natural := 6;
    constant I2CMSPS_RESET            : std_logic_vector(0 downto 0) := "0";
    constant I2CMARB_MSB              : natural := 5;
    constant I2CMARB_LSB              : natural := 5;
    constant I2CMARB_RESET            : std_logic_vector(0 downto 0) := "0";
    constant I2CMTXE_MSB              : natural := 4;
    constant I2CMTXE_LSB              : natural := 4;
    constant I2CMTXE_RESET            : std_logic_vector(0 downto 0) := "0";
    constant I2CMNR_MSB               : natural := 3;
    constant I2CMNR_LSB               : natural := 3;
    constant I2CMNR_RESET             : std_logic_vector(0 downto 0) := "0";
    constant I2CMXC_MSB               : natural := 2;
    constant I2CMXC_LSB               : natural := 2;
    constant I2CMXC_RESET             : std_logic_vector(0 downto 0) := "0";
    constant I2CSTR_MSB               : natural := 1;
    constant I2CSTR_LSB               : natural := 1;
    constant I2CSTR_RESET             : std_logic_vector(0 downto 0) := "0";
    constant I2CSPR_MSB               : natural := 0;
    constant I2CSPR_LSB               : natural := 0;
    constant I2CSPR_RESET             : std_logic_vector(0 downto 0) := "0";

    -- I2CxMTX: I2C master transmit register
    constant I2CxMTX_WORD             : natural := 3;
    constant I2CxMTX_ADDR             : natural := 12;
    constant I2CxMTX_RESET            : std_logic_vector(7 downto 0) := "00000000";
    constant I2CxMTX_IMPL             : std_logic_vector(7 downto 0) := "11111111";
    constant I2CxMTX_MSB              : natural := 7;
    constant I2CxMTX_LSB              : natural := 0;
    -- I2CxMTX_RESET is the register constant above; this field carries the register name.

    -- I2CxMRX: I2C master receive register
    constant I2CxMRX_WORD             : natural := 4;
    constant I2CxMRX_ADDR             : natural := 16;
    constant I2CxMRX_RESET            : std_logic_vector(7 downto 0) := "00000000";
    constant I2CxMRX_IMPL             : std_logic_vector(7 downto 0) := "00000000";
    constant I2CxMRX_MSB              : natural := 7;
    constant I2CxMRX_LSB              : natural := 0;
    -- I2CxMRX_RESET is the register constant above; this field carries the register name.

    -- I2CxSTX: I2C slave transmit register
    constant I2CxSTX_WORD             : natural := 5;
    constant I2CxSTX_ADDR             : natural := 20;
    constant I2CxSTX_RESET            : std_logic_vector(7 downto 0) := "00000000";
    constant I2CxSTX_IMPL             : std_logic_vector(7 downto 0) := "11111111";
    constant I2CxSTX_MSB              : natural := 7;
    constant I2CxSTX_LSB              : natural := 0;
    -- I2CxSTX_RESET is the register constant above; this field carries the register name.

    -- I2CxSRX: I2C slave receive register
    constant I2CxSRX_WORD             : natural := 6;
    constant I2CxSRX_ADDR             : natural := 24;
    constant I2CxSRX_RESET            : std_logic_vector(7 downto 0) := "00000000";
    constant I2CxSRX_IMPL             : std_logic_vector(7 downto 0) := "00000000";
    constant I2CxSRX_MSB              : natural := 7;
    constant I2CxSRX_LSB              : natural := 0;
    -- I2CxSRX_RESET is the register constant above; this field carries the register name.

    -- I2CxAR: I2C this slave address register
    constant I2CxAR_WORD              : natural := 7;
    constant I2CxAR_ADDR              : natural := 28;
    constant I2CxAR_RESET             : std_logic_vector(7 downto 0) := "00000000";
    constant I2CxAR_IMPL              : std_logic_vector(7 downto 0) := "01111111";
    constant I2CxAR_MSB               : natural := 6;
    constant I2CxAR_LSB               : natural := 0;
    -- I2CxAR_RESET is the register constant above; this field carries the register name.

    -- I2CxAMR: I2C this slave address mask register
    constant I2CxAMR_WORD             : natural := 8;
    constant I2CxAMR_ADDR             : natural := 32;
    constant I2CxAMR_RESET            : std_logic_vector(7 downto 0) := "00000000";
    constant I2CxAMR_IMPL             : std_logic_vector(7 downto 0) := "01111111";
    constant I2CxAMR_MSB              : natural := 6;
    constant I2CxAMR_LSB              : natural := 0;
    -- I2CxAMR_RESET is the register constant above; this field carries the register name.

    -- I2C.vhd's own decode identifiers: the word each register is
    -- decoded at, spelled the way that file already spells it, so adopting this
    -- package is a context clause plus a deletion and no assignment moves.
    constant RegSlotI2CxCR            : natural := 0;
    constant RegSlotI2CxFCR           : natural := 1;
    constant RegSlotI2CxSR            : natural := 2;
    constant RegSlotI2CxMTX           : natural := 3;
    constant RegSlotI2CxMRX           : natural := 4;
    constant RegSlotI2CxSTX           : natural := 5;
    constant RegSlotI2CxSRX           : natural := 6;
    constant RegSlotI2CxAR            : natural := 7;
    constant RegSlotI2CxAMR           : natural := 8;

end package i2c_regs_pkg;
