-- VestaRV: ONEWIRE register package
-- 1-Wire Master: a Dallas/Maxim 1-Wire link-layer controller that runs the five microsecond-scale bus primitives in hardware (reset+presence, write-bit, read-bit, write-byte and read-byte) off a programmable time base, leaving ROM search and CRC-8 to firmware over those primitives
-- Generated from hdl/common/regs/rdl/onewire.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.

library ieee;
use ieee.std_logic_1164.all;
library work;
use work.constants.all;

package onewire_regs_pkg is

    -- OWxCR: 1-Wire control register
    constant OWxCR_WORD               : natural := 0;
    constant OWxCR_ADDR               : natural := 0;
    constant OWxCR_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant OWxCR_IMPL               : std_logic_vector(31 downto 0) := "00000000000000000000000000011111";
    constant OWERRIE_MSB              : natural := 4;
    constant OWERRIE_LSB              : natural := 4;
    constant OWERRIE_RESET            : std_logic_vector(0 downto 0) := "0";
    constant OWTCIE_MSB               : natural := 3;
    constant OWTCIE_LSB               : natural := 3;
    constant OWTCIE_RESET             : std_logic_vector(0 downto 0) := "0";
    constant OWSPUEN_MSB              : natural := 2;
    constant OWSPUEN_LSB              : natural := 2;
    constant OWSPUEN_RESET            : std_logic_vector(0 downto 0) := "0";
    constant OWODS_MSB                : natural := 1;
    constant OWODS_LSB                : natural := 1;
    constant OWODS_RESET              : std_logic_vector(0 downto 0) := "0";
    constant OWEN_MSB                 : natural := 0;
    constant OWEN_LSB                 : natural := 0;
    constant OWEN_RESET               : std_logic_vector(0 downto 0) := "0";

    -- OWxCMD: 1-Wire command register
    constant OWxCMD_WORD              : natural := 1;
    constant OWxCMD_ADDR              : natural := 4;
    constant OWxCMD_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant OWxCMD_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000000000100000111";
    constant OWBITVAL_MSB             : natural := 8;
    constant OWBITVAL_LSB             : natural := 8;
    constant OWBITVAL_RESET           : std_logic_vector(0 downto 0) := "0";
    constant OWOP_MSB                 : natural := 2;
    constant OWOP_LSB                 : natural := 0;
    constant OWOP_RESET               : std_logic_vector(2 downto 0) := "000";

    -- OWxTX: Next write byte, the write-byte (OP = 011) source, transmitted LSB-first
    constant OWxTX_WORD               : natural := 2;
    constant OWxTX_ADDR               : natural := 8;
    constant OWxTX_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant OWxTX_IMPL               : std_logic_vector(31 downto 0) := "00000000000000000000000011111111";
    constant OWTX_MSB                 : natural := 7;
    constant OWTX_LSB                 : natural := 0;
    constant OWTX_RESET               : std_logic_vector(7 downto 0) := "00000000";

    -- OWxRX: Last received data (read-only, side-effect-free, A3): a read-byte (OP = 100) assembles into [7:0] LSB-first; a read-bit (OP = 010) lands in [0]
    constant OWxRX_WORD               : natural := 3;
    constant OWxRX_ADDR               : natural := 12;
    constant OWxRX_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant OWxRX_IMPL               : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant OWRX_MSB                 : natural := 7;
    constant OWRX_LSB                 : natural := 0;
    constant OWRX_RESET               : std_logic_vector(7 downto 0) := "00000000";

    -- OWxDIV: Time-base divisor
    constant OWxDIV_WORD              : natural := 4;
    constant OWxDIV_ADDR              : natural := 16;
    constant OWxDIV_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant OWxDIV_IMPL              : std_logic_vector(31 downto 0) := "00000000000000001111111111111111";
    constant OWDIV_MSB                : natural := 15;
    constant OWDIV_LSB                : natural := 0;
    constant OWDIV_RESET              : std_logic_vector(15 downto 0) := "0000000000000000";

    -- OWxSR: 1-Wire status register
    constant OWxSR_WORD               : natural := 5;
    constant OWxSR_ADDR               : natural := 20;
    constant OWxSR_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant OWxSR_IMPL               : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant OWSHORT_MSB              : natural := 4;
    constant OWSHORT_LSB              : natural := 4;
    constant OWSHORT_RESET            : std_logic_vector(0 downto 0) := "0";
    constant OWNOPRES_MSB             : natural := 3;
    constant OWNOPRES_LSB             : natural := 3;
    constant OWNOPRES_RESET           : std_logic_vector(0 downto 0) := "0";
    constant OWPRES_MSB               : natural := 2;
    constant OWPRES_LSB               : natural := 2;
    constant OWPRES_RESET             : std_logic_vector(0 downto 0) := "0";
    constant OWTCIF_MSB               : natural := 1;
    constant OWTCIF_LSB               : natural := 1;
    constant OWTCIF_RESET             : std_logic_vector(0 downto 0) := "0";
    constant OWBUSY_MSB               : natural := 0;
    constant OWBUSY_LSB               : natural := 0;
    constant OWBUSY_RESET             : std_logic_vector(0 downto 0) := "0";

    -- OWxSPU: Reserved for the strong-pullup / parasite-power stage (D15)
    constant OWxSPU_WORD              : natural := 6;
    constant OWxSPU_ADDR              : natural := 24;
    constant OWxSPU_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant OWxSPU_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- OneWire.vhd's own decode identifiers: the word each register is
    -- decoded at, spelled the way that file already spells it, so adopting this
    -- package is a context clause plus a deletion and no assignment moves.
    constant SLOT_CR                  : natural := 0;
    constant SLOT_CMD                 : natural := 1;
    constant SLOT_TX                  : natural := 2;
    constant SLOT_RX                  : natural := 3;
    constant SLOT_DIV                 : natural := 4;
    constant SLOT_SR                  : natural := 5;
    constant SLOT_SPU                 : natural := 6;

    -- periph_regs tables (hdl/common/periph_regs.vhd), one row per word in slot
    -- order. Every mask below is a property of this description. RDTHRU, WIDEWR
    -- and STROBE_HOLD are the entity's own and are set at the instance;
    -- hdl/common/regs/REGFILE.md says why they cannot come from SystemRDL.
    constant NWORDS                   : natural := 7;
    subtype  reg_arr_t is word_array(0 to NWORDS-1);

    -- reset word, loaded on the asynchronous resetn
    constant RSTVAL   : reg_arr_t := (
        x"00000000",   -- OWxCR
        x"00000000",   -- OWxCMD
        x"00000000",   -- OWxTX
        x"00000000",   -- OWxRX
        x"00000000",   -- OWxDIV
        x"00000000",   -- OWxSR
        x"00000000"    -- OWxSPU
    );

    -- bits that hold a software-written flop; periph_regs stores exactly these
    constant IMPL     : reg_arr_t := (
        x"0000001F",   -- OWxCR
        x"00000107",   -- OWxCMD
        x"000000FF",   -- OWxTX
        x"00000000",   -- OWxRX
        x"0000FFFF",   -- OWxDIV
        x"00000000",   -- OWxSR
        x"00000000"    -- OWxSPU
    );

    -- a written 1 clears (onwrite = woclr): drives w1c_hit
    constant W1C      : reg_arr_t := (
        x"00000000",   -- OWxCR
        x"00000000",   -- OWxCMD
        x"00000000",   -- OWxTX
        x"00000000",   -- OWxRX
        x"00000000",   -- OWxDIV
        x"0000001A",   -- OWxSR
        x"00000000"    -- OWxSPU
    );

    -- a written 1 sets (onwrite = woset): drives woset_hit
    constant WOSET    : reg_arr_t := (
        x"00000000",   -- OWxCR
        x"00000000",   -- OWxCMD
        x"00000000",   -- OWxTX
        x"00000000",   -- OWxRX
        x"00000000",   -- OWxDIV
        x"00000000",   -- OWxSR
        x"00000000"    -- OWxSPU
    );

    -- a written 1 toggles (onwrite = wot): drives wot_hit
    constant WOT      : reg_arr_t := (
        x"00000000",   -- OWxCR
        x"00000000",   -- OWxCMD
        x"00000000",   -- OWxTX
        x"00000000",   -- OWxRX
        x"00000000",   -- OWxDIV
        x"00000000",   -- OWxSR
        x"00000000"    -- OWxSPU
    );

    -- self-clearing strobe (singlepulse): drives wr_pulse, stores nothing
    constant PULSE    : reg_arr_t := (
        x"00000000",   -- OWxCR
        x"00000000",   -- OWxCMD
        x"00000000",   -- OWxTX
        x"00000000",   -- OWxRX
        x"00000000",   -- OWxDIV
        x"00000000",   -- OWxSR
        x"00000000"    -- OWxSPU
    );

    -- a read retires (onread = rclr): drives rd_clr
    constant RCLR     : reg_arr_t := (
        x"00000000",   -- OWxCR
        x"00000000",   -- OWxCMD
        x"00000000",   -- OWxTX
        x"00000000",   -- OWxRX
        x"00000000",   -- OWxDIV
        x"00000000",   -- OWxSR
        x"00000000"    -- OWxSPU
    );

    -- bits hardware drives (hw = w or rw): what hw_we / hw_set / hw_clr may touch
    constant HWOWN    : reg_arr_t := (
        x"00000000",   -- OWxCR
        x"00000000",   -- OWxCMD
        x"00000000",   -- OWxTX
        x"000000FF",   -- OWxRX
        x"00000000",   -- OWxDIV
        x"0000001F",   -- OWxSR
        x"00000000"    -- OWxSPU
    );

end package onewire_regs_pkg;
