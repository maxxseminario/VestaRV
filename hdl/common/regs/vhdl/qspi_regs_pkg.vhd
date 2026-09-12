-- VestaRV: QSPI register package
-- Quad Serial Peripheral Interface flash controller
-- Generated from hdl/common/regs/rdl/qspi.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.

library ieee;
use ieee.std_logic_1164.all;
library work;
use work.constants.all;

package qspi_regs_pkg is

    -- QSPIxCR: QSPI control register
    constant QSPIxCR_WORD             : natural := 0;
    constant QSPIxCR_ADDR             : natural := 0;
    constant QSPIxCR_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant QSPIxCR_IMPL             : std_logic_vector(31 downto 0) := "00011111111111111111111111111111";
    constant QSPIRXFIE_MSB            : natural := 28;
    constant QSPIRXFIE_LSB            : natural := 28;
    constant QSPIRXFIE_RESET          : std_logic_vector(0 downto 0) := "0";
    constant QSPITCIE_MSB             : natural := 27;
    constant QSPITCIE_LSB             : natural := 27;
    constant QSPITCIE_RESET           : std_logic_vector(0 downto 0) := "0";
    constant QSPIBR_MSB               : natural := 26;
    constant QSPIBR_LSB               : natural := 19;
    constant QSPIBR_RESET             : std_logic_vector(7 downto 0) := "00000000";
    constant QSPICSSEL_MSB            : natural := 18;
    constant QSPICSSEL_LSB            : natural := 16;
    constant QSPICSSEL_RESET          : std_logic_vector(2 downto 0) := "000";
    constant QSPIDUMMY_MSB            : natural := 15;
    constant QSPIDUMMY_LSB            : natural := 11;
    constant QSPIDUMMY_RESET          : std_logic_vector(4 downto 0) := "00000";
    constant QSPIAWID_MSB             : natural := 10;
    constant QSPIAWID_LSB             : natural := 9;
    constant QSPIAWID_RESET           : std_logic_vector(1 downto 0) := "00";
    constant QSPICPHA_MSB             : natural := 8;
    constant QSPICPHA_LSB             : natural := 8;
    constant QSPICPHA_RESET           : std_logic_vector(0 downto 0) := "0";
    constant QSPICPOL_MSB             : natural := 7;
    constant QSPICPOL_LSB             : natural := 7;
    constant QSPICPOL_RESET           : std_logic_vector(0 downto 0) := "0";
    constant QSPIDATW_MSB             : natural := 6;
    constant QSPIDATW_LSB             : natural := 5;
    constant QSPIDATW_RESET           : std_logic_vector(1 downto 0) := "00";
    constant QSPIADRW_MSB             : natural := 4;
    constant QSPIADRW_LSB             : natural := 3;
    constant QSPIADRW_RESET           : std_logic_vector(1 downto 0) := "00";
    constant QSPICMDW_MSB             : natural := 2;
    constant QSPICMDW_LSB             : natural := 1;
    constant QSPICMDW_RESET           : std_logic_vector(1 downto 0) := "00";
    constant QSPIEN_MSB               : natural := 0;
    constant QSPIEN_LSB               : natural := 0;
    constant QSPIEN_RESET             : std_logic_vector(0 downto 0) := "0";

    -- QSPIxCMD: QSPI command register
    constant QSPIxCMD_WORD            : natural := 1;
    constant QSPIxCMD_ADDR            : natural := 4;
    constant QSPIxCMD_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant QSPIxCMD_IMPL            : std_logic_vector(31 downto 0) := "00000000000000000000011111111111";
    constant QSPIDIR_MSB              : natural := 10;
    constant QSPIDIR_LSB              : natural := 10;
    constant QSPIDIR_RESET            : std_logic_vector(0 downto 0) := "0";
    constant QSPIDLEN_MSB             : natural := 9;
    constant QSPIDLEN_LSB             : natural := 8;
    constant QSPIDLEN_RESET           : std_logic_vector(1 downto 0) := "00";
    constant QSPICMD_MSB              : natural := 7;
    constant QSPICMD_LSB              : natural := 0;
    constant QSPICMD_RESET            : std_logic_vector(7 downto 0) := "00000000";

    -- QSPIxADR: QSPI transaction address
    constant QSPIxADR_WORD            : natural := 2;
    constant QSPIxADR_ADDR            : natural := 8;
    constant QSPIxADR_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant QSPIxADR_IMPL            : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant QSPIADR_MSB              : natural := 31;
    constant QSPIADR_LSB              : natural := 0;
    constant QSPIADR_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- QSPIxTX: QSPI transmit data
    constant QSPIxTX_WORD             : natural := 3;
    constant QSPIxTX_ADDR             : natural := 12;
    constant QSPIxTX_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant QSPIxTX_IMPL             : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant QSPITX_MSB               : natural := 31;
    constant QSPITX_LSB               : natural := 0;
    constant QSPITX_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- QSPIxRX: QSPI receive data
    constant QSPIxRX_WORD             : natural := 4;
    constant QSPIxRX_ADDR             : natural := 16;
    constant QSPIxRX_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant QSPIxRX_IMPL             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant QSPIRX_MSB               : natural := 31;
    constant QSPIRX_LSB               : natural := 0;
    constant QSPIRX_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- QSPIxSR: QSPI status register
    constant QSPIxSR_WORD             : natural := 5;
    constant QSPIxSR_ADDR             : natural := 20;
    constant QSPIxSR_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant QSPIxSR_IMPL             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant QSPITCIF_MSB             : natural := 3;
    constant QSPITCIF_LSB             : natural := 3;
    constant QSPITCIF_RESET           : std_logic_vector(0 downto 0) := "0";
    constant QSPIRXFULL_MSB           : natural := 2;
    constant QSPIRXFULL_LSB           : natural := 2;
    constant QSPIRXFULL_RESET         : std_logic_vector(0 downto 0) := "0";
    constant QSPITXEIF_MSB            : natural := 1;
    constant QSPITXEIF_LSB            : natural := 1;
    constant QSPITXEIF_RESET          : std_logic_vector(0 downto 0) := "0";
    constant QSPIBUSY_MSB             : natural := 0;
    constant QSPIBUSY_LSB             : natural := 0;
    constant QSPIBUSY_RESET           : std_logic_vector(0 downto 0) := "0";

    -- QSPI.vhd's own decode identifiers: the word each register is
    -- decoded at, spelled the way that file already spells it, so adopting this
    -- package is a context clause plus a deletion and no assignment moves.
    constant SLOT_CR                  : natural := 0;
    constant SLOT_CMD                 : natural := 1;
    constant SLOT_ADR                 : natural := 2;
    constant SLOT_TX                  : natural := 3;
    constant SLOT_RX                  : natural := 4;
    constant SLOT_SR                  : natural := 5;

    -- periph_regs tables (hdl/common/periph_regs.vhd), one row per word in slot
    -- order. Every mask below is a property of this description. RDTHRU, WIDEWR,
    -- FULLWR and STROBE_HOLD are the entity's own and are set at the instance;
    -- hdl/common/regs/REGFILE.md says why they cannot come from SystemRDL.
    constant NWORDS                   : natural := 6;
    subtype  reg_arr_t is word_array(0 to NWORDS-1);

    -- reset word, loaded on the asynchronous resetn
    constant RSTVAL   : reg_arr_t := (
        x"00000000",   -- QSPIxCR
        x"00000000",   -- QSPIxCMD
        x"00000000",   -- QSPIxADR
        x"00000000",   -- QSPIxTX
        x"00000000",   -- QSPIxRX
        x"00000000"    -- QSPIxSR
    );

    -- bits that hold a software-written flop; periph_regs stores exactly these
    constant IMPL     : reg_arr_t := (
        x"1FFFFFFF",   -- QSPIxCR
        x"000007FF",   -- QSPIxCMD
        x"FFFFFFFF",   -- QSPIxADR
        x"FFFFFFFF",   -- QSPIxTX
        x"00000000",   -- QSPIxRX
        x"00000000"    -- QSPIxSR
    );

    -- a written 1 clears (onwrite = woclr): drives w1c_hit
    constant W1C      : reg_arr_t := (
        x"00000000",   -- QSPIxCR
        x"00000000",   -- QSPIxCMD
        x"00000000",   -- QSPIxADR
        x"00000000",   -- QSPIxTX
        x"00000000",   -- QSPIxRX
        x"0000000E"    -- QSPIxSR
    );

    -- a written 1 sets (onwrite = woset): drives woset_hit
    constant WOSET    : reg_arr_t := (
        x"00000000",   -- QSPIxCR
        x"00000000",   -- QSPIxCMD
        x"00000000",   -- QSPIxADR
        x"00000000",   -- QSPIxTX
        x"00000000",   -- QSPIxRX
        x"00000000"    -- QSPIxSR
    );

    -- a written 1 toggles (onwrite = wot): drives wot_hit
    constant WOT      : reg_arr_t := (
        x"00000000",   -- QSPIxCR
        x"00000000",   -- QSPIxCMD
        x"00000000",   -- QSPIxADR
        x"00000000",   -- QSPIxTX
        x"00000000",   -- QSPIxRX
        x"00000000"    -- QSPIxSR
    );

    -- self-clearing strobe (singlepulse): drives wr_pulse, stores nothing
    constant PULSE    : reg_arr_t := (
        x"00000000",   -- QSPIxCR
        x"00000000",   -- QSPIxCMD
        x"00000000",   -- QSPIxADR
        x"00000000",   -- QSPIxTX
        x"00000000",   -- QSPIxRX
        x"00000000"    -- QSPIxSR
    );

    -- a read retires (onread = rclr): drives rd_clr
    constant RCLR     : reg_arr_t := (
        x"00000000",   -- QSPIxCR
        x"00000000",   -- QSPIxCMD
        x"00000000",   -- QSPIxADR
        x"00000000",   -- QSPIxTX
        x"00000000",   -- QSPIxRX
        x"00000000"    -- QSPIxSR
    );

    -- bits hardware drives (hw = w or rw): what hw_we / hw_set / hw_clr may touch
    constant HWOWN    : reg_arr_t := (
        x"00000000",   -- QSPIxCR
        x"00000000",   -- QSPIxCMD
        x"00000000",   -- QSPIxADR
        x"00000000",   -- QSPIxTX
        x"FFFFFFFF",   -- QSPIxRX
        x"0000000F"    -- QSPIxSR
    );

end package qspi_regs_pkg;
