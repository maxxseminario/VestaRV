-- VestaRV: NPU register package
-- Fixed-point multilayer perceptron (MLP) neural network processing unit
-- Generated from hdl/common/regs/rdl/npu.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.

library ieee;
use ieee.std_logic_1164.all;
library work;
use work.constants.all;

package npu_regs_pkg is

    -- NPUCR: NPU control register
    constant NPUCR_WORD               : natural := 0;
    constant NPUCR_ADDR               : natural := 0;
    constant NPUCR_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant NPUCR_IMPL               : std_logic_vector(31 downto 0) := "00001111111111111111111111111111";
    constant NPUXPK_MSB               : natural := 27;
    constant NPUXPK_LSB               : natural := 27;
    constant NPUXPK_RESET             : std_logic_vector(0 downto 0) := "0";
    constant NPUWPK_MSB               : natural := 26;
    constant NPUWPK_LSB               : natural := 26;
    constant NPUWPK_RESET             : std_logic_vector(0 downto 0) := "0";
    constant NPUACTF_MSB              : natural := 25;
    constant NPUACTF_LSB              : natural := 23;
    constant NPUACTF_RESET            : std_logic_vector(2 downto 0) := "000";
    constant NPUMODE_MSB              : natural := 22;
    constant NPUMODE_LSB              : natural := 20;
    constant NPUMODE_RESET            : std_logic_vector(2 downto 0) := "000";
    constant NPUTDIE_MSB              : natural := 19;
    constant NPUTDIE_LSB              : natural := 19;
    constant NPUTDIE_RESET            : std_logic_vector(0 downto 0) := "0";
    constant NPUBEN_MSB               : natural := 18;
    constant NPUBEN_LSB               : natural := 18;
    constant NPUBEN_RESET             : std_logic_vector(0 downto 0) := "0";
    constant NPUAEN_MSB               : natural := 17;
    constant NPUAEN_LSB               : natural := 17;
    constant NPUAEN_RESET             : std_logic_vector(0 downto 0) := "0";
    constant NPUTHINK_MSB             : natural := 16;
    constant NPUTHINK_LSB             : natural := 16;
    constant NPUTHINK_RESET           : std_logic_vector(0 downto 0) := "0";
    constant NPUNI_MSB                : natural := 15;
    constant NPUNI_LSB                : natural := 8;
    constant NPUNI_RESET              : std_logic_vector(7 downto 0) := "00000000";
    constant NPUNN_MSB                : natural := 7;
    constant NPUNN_LSB                : natural := 0;
    constant NPUNN_RESET              : std_logic_vector(7 downto 0) := "00000000";

    -- NPUIVSAR: Input vector start word index within the shared NPU staging RAM: the byte offset from the start of the staging RAM (0xC000) divided by 4. For example, an input vector at byte address 0xC100 has word index 0x40. Each input is a signed Q0.24 value stored in bits 24:0 of its 32-bit SRAM word; bits 31:25 are ignored
    constant NPUIVSAR_WORD            : natural := 1;
    constant NPUIVSAR_ADDR            : natural := 4;
    constant NPUIVSAR_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant NPUIVSAR_IMPL            : std_logic_vector(31 downto 0) := "00000000000000000000111111111111";
    constant NPUIVSAR_MSB             : natural := 11;
    constant NPUIVSAR_LSB             : natural := 0;
    -- NPUIVSAR_RESET is the register constant above; this field carries the register name.

    -- NPUWVSAR: Synaptic weight matrix start word index within the shared NPU staging RAM: the byte offset from the start of the staging RAM (0xC000) divided by 4. Each weight is a signed Q7.24 value occupying all 32 bits of its SRAM word; bit 31 is the sign bit
    constant NPUWVSAR_WORD            : natural := 2;
    constant NPUWVSAR_ADDR            : natural := 8;
    constant NPUWVSAR_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant NPUWVSAR_IMPL            : std_logic_vector(31 downto 0) := "00000000000000000000111111111111";
    constant NPUWVSAR_MSB             : natural := 11;
    constant NPUWVSAR_LSB             : natural := 0;
    -- NPUWVSAR_RESET is the register constant above; this field carries the register name.

    -- NPUOVSAR: Output vector start word index within the shared NPU staging RAM: the byte offset from the start of the staging RAM (0xC000) divided by 4. Each output is a signed Q7.24 value occupying all 32 bits of its SRAM word; bit 31 is the sign bit
    constant NPUOVSAR_WORD            : natural := 3;
    constant NPUOVSAR_ADDR            : natural := 12;
    constant NPUOVSAR_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant NPUOVSAR_IMPL            : std_logic_vector(31 downto 0) := "00000000000000000000111111111111";
    constant NPUOVSAR_MSB             : natural := 11;
    constant NPUOVSAR_LSB             : natural := 0;
    -- NPUOVSAR_RESET is the register constant above; this field carries the register name.

    -- NPUSR: NPU status register
    constant NPUSR_WORD               : natural := 4;
    constant NPUSR_ADDR               : natural := 16;
    constant NPUSR_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant NPUSR_IMPL               : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant NPUTHINKDONE_MSB         : natural := 0;
    constant NPUTHINKDONE_LSB         : natural := 0;
    constant NPUTHINKDONE_RESET       : std_logic_vector(0 downto 0) := "0";

    -- NPUCFG1: NPU mode configuration word 1. The interpretation depends on NPUCR
    constant NPUCFG1_WORD             : natural := 5;
    constant NPUCFG1_ADDR             : natural := 20;
    constant NPUCFG1_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant NPUCFG1_IMPL             : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant NPUCFG1_MSB              : natural := 31;
    constant NPUCFG1_LSB              : natural := 0;
    -- NPUCFG1_RESET is the register constant above; this field carries the register name.

    -- NPUCFG2: NPU mode configuration word 2. The interpretation depends on NPUCR
    constant NPUCFG2_WORD             : natural := 6;
    constant NPUCFG2_ADDR             : natural := 24;
    constant NPUCFG2_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant NPUCFG2_IMPL             : std_logic_vector(31 downto 0) := "00000000000000001111111111111111";
    constant NPUCFG2_MSB              : natural := 15;
    constant NPUCFG2_LSB              : natural := 0;
    -- NPUCFG2_RESET is the register constant above; this field carries the register name.

    -- NPU.vhd's own decode identifiers: the word each register is
    -- decoded at, spelled the way that file already spells it, so adopting this
    -- package is a context clause plus a deletion and no assignment moves.
    constant MmrAddrNPUCR             : natural := 0;
    constant MmrAddrNPUIVSAR          : natural := 1;
    constant MmrAddrNPUWVSAR          : natural := 2;
    constant MmrAddrNPUOVSAR          : natural := 3;
    constant MmrAddrNPUSR             : natural := 4;
    constant MmrAddrNPUCFG1           : natural := 5;
    constant MmrAddrNPUCFG2           : natural := 6;

    -- periph_regs tables (hdl/common/periph_regs.vhd), one row per word in slot
    -- order. Every mask below is a property of this description. RDTHRU, WIDEWR
    -- and STROBE_HOLD are the entity's own and are set at the instance;
    -- hdl/common/regs/REGFILE.md says why they cannot come from SystemRDL.
    constant NWORDS                   : natural := 7;
    subtype  reg_arr_t is word_array(0 to NWORDS-1);

    -- reset word, loaded on the asynchronous resetn
    constant RSTVAL   : reg_arr_t := (
        x"00000000",   -- NPUCR
        x"00000000",   -- NPUIVSAR
        x"00000000",   -- NPUWVSAR
        x"00000000",   -- NPUOVSAR
        x"00000000",   -- NPUSR
        x"00000000",   -- NPUCFG1
        x"00000000"    -- NPUCFG2
    );

    -- bits that hold a software-written flop; periph_regs stores exactly these
    constant IMPL     : reg_arr_t := (
        x"0FFFFFFF",   -- NPUCR
        x"00000FFF",   -- NPUIVSAR
        x"00000FFF",   -- NPUWVSAR
        x"00000FFF",   -- NPUOVSAR
        x"00000000",   -- NPUSR
        x"FFFFFFFF",   -- NPUCFG1
        x"0000FFFF"    -- NPUCFG2
    );

    -- a written 1 clears (onwrite = woclr): drives w1c_hit
    constant W1C      : reg_arr_t := (
        x"00000000",   -- NPUCR
        x"00000000",   -- NPUIVSAR
        x"00000000",   -- NPUWVSAR
        x"00000000",   -- NPUOVSAR
        x"00000001",   -- NPUSR
        x"00000000",   -- NPUCFG1
        x"00000000"    -- NPUCFG2
    );

    -- a written 1 sets (onwrite = woset): drives woset_hit
    constant WOSET    : reg_arr_t := (
        x"00000000",   -- NPUCR
        x"00000000",   -- NPUIVSAR
        x"00000000",   -- NPUWVSAR
        x"00000000",   -- NPUOVSAR
        x"00000000",   -- NPUSR
        x"00000000",   -- NPUCFG1
        x"00000000"    -- NPUCFG2
    );

    -- a written 1 toggles (onwrite = wot): drives wot_hit
    constant WOT      : reg_arr_t := (
        x"00000000",   -- NPUCR
        x"00000000",   -- NPUIVSAR
        x"00000000",   -- NPUWVSAR
        x"00000000",   -- NPUOVSAR
        x"00000000",   -- NPUSR
        x"00000000",   -- NPUCFG1
        x"00000000"    -- NPUCFG2
    );

    -- self-clearing strobe (singlepulse): drives wr_pulse, stores nothing
    constant PULSE    : reg_arr_t := (
        x"00000000",   -- NPUCR
        x"00000000",   -- NPUIVSAR
        x"00000000",   -- NPUWVSAR
        x"00000000",   -- NPUOVSAR
        x"00000000",   -- NPUSR
        x"00000000",   -- NPUCFG1
        x"00000000"    -- NPUCFG2
    );

    -- a read retires (onread = rclr): drives rd_clr
    constant RCLR     : reg_arr_t := (
        x"00000000",   -- NPUCR
        x"00000000",   -- NPUIVSAR
        x"00000000",   -- NPUWVSAR
        x"00000000",   -- NPUOVSAR
        x"00000000",   -- NPUSR
        x"00000000",   -- NPUCFG1
        x"00000000"    -- NPUCFG2
    );

    -- bits hardware drives (hw = w or rw): what hw_we / hw_set / hw_clr may touch
    constant HWOWN    : reg_arr_t := (
        x"00010000",   -- NPUCR
        x"00000000",   -- NPUIVSAR
        x"00000000",   -- NPUWVSAR
        x"00000000",   -- NPUOVSAR
        x"00000001",   -- NPUSR
        x"00000000",   -- NPUCFG1
        x"00000000"    -- NPUCFG2
    );

end package npu_regs_pkg;
