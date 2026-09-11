-- VestaRV: I2CTARGET register package
-- Hardware-Autonomous I2C Target: an I2C slave engine that handles the protocol in hardware: 7-bit address match with a wildcard mask and optional general-call response, byte-at-a-time receive and transmit with ready/empty status, hardware clock stretching for lossless flow control, START / STOP / repeated-START / NACK framing detection, and a configurable stuck-SCL watchdog
-- Generated from hdl/common/regs/rdl/i2ctarget.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.

library ieee;
use ieee.std_logic_1164.all;

package i2ctarget_regs_pkg is

    -- I2CTxCR: I2C target control register
    constant I2CTxCR_WORD             : natural := 0;
    constant I2CTxCR_ADDR             : natural := 0;
    constant I2CTxCR_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant I2CTxCR_IMPL             : std_logic_vector(31 downto 0) := "00000000011111110111111100011111";
    constant I2CTSADM_MSB             : natural := 22;
    constant I2CTSADM_LSB             : natural := 16;
    constant I2CTSADM_RESET           : std_logic_vector(6 downto 0) := "0000000";
    constant I2CTSAD_MSB              : natural := 14;
    constant I2CTSAD_LSB              : natural := 8;
    constant I2CTSAD_RESET            : std_logic_vector(6 downto 0) := "0000000";
    constant I2CTDATAIE_MSB           : natural := 4;
    constant I2CTDATAIE_LSB           : natural := 4;
    constant I2CTDATAIE_RESET         : std_logic_vector(0 downto 0) := "0";
    constant I2CTAEIE_MSB             : natural := 3;
    constant I2CTAEIE_LSB             : natural := 3;
    constant I2CTAEIE_RESET           : std_logic_vector(0 downto 0) := "0";
    constant I2CTCSEN_MSB             : natural := 2;
    constant I2CTCSEN_LSB             : natural := 2;
    constant I2CTCSEN_RESET           : std_logic_vector(0 downto 0) := "0";
    constant I2CTGCEN_MSB             : natural := 1;
    constant I2CTGCEN_LSB             : natural := 1;
    constant I2CTGCEN_RESET           : std_logic_vector(0 downto 0) := "0";
    constant I2CTEN_MSB               : natural := 0;
    constant I2CTEN_LSB               : natural := 0;
    constant I2CTEN_RESET             : std_logic_vector(0 downto 0) := "0";

    -- I2CTxSR: I2C target status register
    constant I2CTxSR_WORD             : natural := 1;
    constant I2CTxSR_ADDR             : natural := 4;
    constant I2CTxSR_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant I2CTxSR_IMPL             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant I2CTERRF_MSB             : natural := 10;
    constant I2CTERRF_LSB             : natural := 10;
    constant I2CTERRF_RESET           : std_logic_vector(0 downto 0) := "0";
    constant I2CTRSTARTF_MSB          : natural := 9;
    constant I2CTRSTARTF_LSB          : natural := 9;
    constant I2CTRSTARTF_RESET        : std_logic_vector(0 downto 0) := "0";
    constant I2CTSTOPF_MSB            : natural := 8;
    constant I2CTSTOPF_LSB            : natural := 8;
    constant I2CTSTOPF_RESET          : std_logic_vector(0 downto 0) := "0";
    constant I2CTNACKF_MSB            : natural := 7;
    constant I2CTNACKF_LSB            : natural := 7;
    constant I2CTNACKF_RESET          : std_logic_vector(0 downto 0) := "0";
    constant I2CTOVF_MSB              : natural := 6;
    constant I2CTOVF_LSB              : natural := 6;
    constant I2CTOVF_RESET            : std_logic_vector(0 downto 0) := "0";
    constant I2CTTXE_MSB              : natural := 5;
    constant I2CTTXE_LSB              : natural := 5;
    constant I2CTTXE_RESET            : std_logic_vector(0 downto 0) := "0";
    constant I2CTRXF_MSB              : natural := 4;
    constant I2CTRXF_LSB              : natural := 4;
    constant I2CTRXF_RESET            : std_logic_vector(0 downto 0) := "0";
    constant I2CTGCF_MSB              : natural := 3;
    constant I2CTGCF_LSB              : natural := 3;
    constant I2CTGCF_RESET            : std_logic_vector(0 downto 0) := "0";
    constant I2CTAMF_MSB              : natural := 2;
    constant I2CTAMF_LSB              : natural := 2;
    constant I2CTAMF_RESET            : std_logic_vector(0 downto 0) := "0";
    constant I2CTTM_MSB               : natural := 1;
    constant I2CTTM_LSB               : natural := 1;
    constant I2CTTM_RESET             : std_logic_vector(0 downto 0) := "0";
    constant I2CTBUSY_MSB             : natural := 0;
    constant I2CTBUSY_LSB             : natural := 0;
    constant I2CTBUSY_RESET           : std_logic_vector(0 downto 0) := "0";

    -- I2CTxTX: Transmit byte buffer
    constant I2CTxTX_WORD             : natural := 2;
    constant I2CTxTX_ADDR             : natural := 8;
    constant I2CTxTX_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant I2CTxTX_IMPL             : std_logic_vector(31 downto 0) := "00000000000000000000000011111111";
    constant I2CTTX_MSB               : natural := 7;
    constant I2CTTX_LSB               : natural := 0;
    constant I2CTTX_RESET             : std_logic_vector(7 downto 0) := "00000000";

    -- I2CTxRX: Last received byte (read-only, side-effect-free, D9): the most recent host-written byte, valid while RXF is set
    constant I2CTxRX_WORD             : natural := 3;
    constant I2CTxRX_ADDR             : natural := 12;
    constant I2CTxRX_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant I2CTxRX_IMPL             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant I2CTRX_MSB               : natural := 7;
    constant I2CTRX_LSB               : natural := 0;
    constant I2CTRX_RESET             : std_logic_vector(7 downto 0) := "00000000";

    -- I2CTxWDG: SCL-low watchdog timeout
    constant I2CTxWDG_WORD            : natural := 4;
    constant I2CTxWDG_ADDR            : natural := 16;
    constant I2CTxWDG_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant I2CTxWDG_IMPL            : std_logic_vector(31 downto 0) := "00000000000000001111111111111111";
    constant I2CTWDTO_MSB             : natural := 15;
    constant I2CTWDTO_LSB             : natural := 0;
    constant I2CTWDTO_RESET           : std_logic_vector(15 downto 0) := "0000000000000000";

    -- I2CTarget.vhd's own decode identifiers: the word each register is
    -- decoded at, spelled the way that file already spells it, so adopting this
    -- package is a context clause plus a deletion and no assignment moves.
    constant SLOT_CR                  : natural := 0;
    constant SLOT_SR                  : natural := 1;
    constant SLOT_TX                  : natural := 2;
    constant SLOT_RX                  : natural := 3;
    constant SLOT_WDG                 : natural := 4;

end package i2ctarget_regs_pkg;
