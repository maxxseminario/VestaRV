-- VestaRV: DEBUG_MODULE register package
-- The chip's Debug Module: DMI register file, per-hart run control, access-register abstract commands, a two-word program buffer with an implicit third ebreak, and halt groups. One per chip, always-on mclk, never inside a tile.
-- Generated from hdl/common/regs/rdl/debug_module.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.

library ieee;
use ieee.std_logic_1164.all;

package debug_module_regs_pkg is

    -- DMDATA0: Abstract data register 0, datacount = 1. Not a flop in this Debug Module: every access is PROXIED to the backing word at DATA0_ADDR through the DM's own shared-bus master, so a read returns whatever the halted hart's abstract command left there
    constant DMDATA0_WORD             : natural := 4;
    constant DMDATA0_ADDR             : natural := 16;
    constant DMDATA0_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMDATA0_IMPL             : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant DMDATA0_MSB              : natural := 31;
    constant DMDATA0_LSB              : natural := 0;
    -- DMDATA0_RESET is the register constant above; this field carries the register name.

    -- DMCONTROL: Debug Module control
    constant DMCONTROL_WORD           : natural := 16;
    constant DMCONTROL_ADDR           : natural := 64;
    constant DMCONTROL_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMCONTROL_IMPL           : std_logic_vector(31 downto 0) := "10000011111111110000000000001001";
    constant DMHALTREQ_MSB            : natural := 31;
    constant DMHALTREQ_LSB            : natural := 31;
    constant DMHALTREQ_RESET          : std_logic_vector(0 downto 0) := "0";
    constant DMRESUMEREQ_MSB          : natural := 30;
    constant DMRESUMEREQ_LSB          : natural := 30;
    constant DMRESUMEREQ_RESET        : std_logic_vector(0 downto 0) := "0";
    constant DMACKHAVERESET_MSB       : natural := 28;
    constant DMACKHAVERESET_LSB       : natural := 28;
    constant DMACKHAVERESET_RESET     : std_logic_vector(0 downto 0) := "0";
    constant DMHARTSEL_MSB            : natural := 25;
    constant DMHARTSEL_LSB            : natural := 16;
    constant DMHARTSEL_RESET          : std_logic_vector(9 downto 0) := "0000000000";
    constant DMSETRESETHALTREQ_MSB    : natural := 3;
    constant DMSETRESETHALTREQ_LSB    : natural := 3;
    constant DMSETRESETHALTREQ_RESET  : std_logic_vector(0 downto 0) := "0";
    constant DMCLRRESETHALTREQ_MSB    : natural := 2;
    constant DMCLRRESETHALTREQ_LSB    : natural := 2;
    constant DMCLRRESETHALTREQ_RESET  : std_logic_vector(0 downto 0) := "0";
    constant DMACTIVE_MSB             : natural := 0;
    constant DMACTIVE_LSB             : natural := 0;
    constant DMACTIVE_RESET           : std_logic_vector(0 downto 0) := "0";

    -- DMSTATUS: Debug Module status, read only
    constant DMSTATUS_WORD            : natural := 17;
    constant DMSTATUS_ADDR            : natural := 68;
    constant DMSTATUS_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMSTATUS_IMPL            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMIMPEBREAK_MSB          : natural := 22;
    constant DMIMPEBREAK_LSB          : natural := 22;
    constant DMIMPEBREAK_RESET        : std_logic_vector(0 downto 0) := "0";
    constant DMALLHAVERESET_MSB       : natural := 19;
    constant DMALLHAVERESET_LSB       : natural := 19;
    constant DMALLHAVERESET_RESET     : std_logic_vector(0 downto 0) := "0";
    constant DMANYHAVERESET_MSB       : natural := 18;
    constant DMANYHAVERESET_LSB       : natural := 18;
    constant DMANYHAVERESET_RESET     : std_logic_vector(0 downto 0) := "0";
    constant DMALLRESUMEACK_MSB       : natural := 17;
    constant DMALLRESUMEACK_LSB       : natural := 17;
    constant DMALLRESUMEACK_RESET     : std_logic_vector(0 downto 0) := "0";
    constant DMANYRESUMEACK_MSB       : natural := 16;
    constant DMANYRESUMEACK_LSB       : natural := 16;
    constant DMANYRESUMEACK_RESET     : std_logic_vector(0 downto 0) := "0";
    constant DMALLNONEXISTENT_MSB     : natural := 15;
    constant DMALLNONEXISTENT_LSB     : natural := 15;
    constant DMALLNONEXISTENT_RESET   : std_logic_vector(0 downto 0) := "0";
    constant DMANYNONEXISTENT_MSB     : natural := 14;
    constant DMANYNONEXISTENT_LSB     : natural := 14;
    constant DMANYNONEXISTENT_RESET   : std_logic_vector(0 downto 0) := "0";
    constant DMALLUNAVAIL_MSB         : natural := 13;
    constant DMALLUNAVAIL_LSB         : natural := 13;
    constant DMALLUNAVAIL_RESET       : std_logic_vector(0 downto 0) := "0";
    constant DMANYUNAVAIL_MSB         : natural := 12;
    constant DMANYUNAVAIL_LSB         : natural := 12;
    constant DMANYUNAVAIL_RESET       : std_logic_vector(0 downto 0) := "0";
    constant DMALLRUNNING_MSB         : natural := 11;
    constant DMALLRUNNING_LSB         : natural := 11;
    constant DMALLRUNNING_RESET       : std_logic_vector(0 downto 0) := "0";
    constant DMANYRUNNING_MSB         : natural := 10;
    constant DMANYRUNNING_LSB         : natural := 10;
    constant DMANYRUNNING_RESET       : std_logic_vector(0 downto 0) := "0";
    constant DMALLHALTED_MSB          : natural := 9;
    constant DMALLHALTED_LSB          : natural := 9;
    constant DMALLHALTED_RESET        : std_logic_vector(0 downto 0) := "0";
    constant DMANYHALTED_MSB          : natural := 8;
    constant DMANYHALTED_LSB          : natural := 8;
    constant DMANYHALTED_RESET        : std_logic_vector(0 downto 0) := "0";
    constant DMAUTHENTICATED_MSB      : natural := 7;
    constant DMAUTHENTICATED_LSB      : natural := 7;
    constant DMAUTHENTICATED_RESET    : std_logic_vector(0 downto 0) := "0";
    constant DMHASRESETHALTREQ_MSB    : natural := 5;
    constant DMHASRESETHALTREQ_LSB    : natural := 5;
    constant DMHASRESETHALTREQ_RESET  : std_logic_vector(0 downto 0) := "0";
    constant DMVERSION_MSB            : natural := 3;
    constant DMVERSION_LSB            : natural := 0;
    constant DMVERSION_RESET          : std_logic_vector(3 downto 0) := "0000";

    -- DMHARTINFO: Hart information, read only
    constant DMHARTINFO_WORD          : natural := 18;
    constant DMHARTINFO_ADDR          : natural := 72;
    constant DMHARTINFO_RESET         : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMHARTINFO_IMPL          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- DMHALTSUM1: Halt summary 1, read only
    constant DMHALTSUM1_WORD          : natural := 19;
    constant DMHALTSUM1_ADDR          : natural := 76;
    constant DMHALTSUM1_RESET         : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMHALTSUM1_IMPL          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- DMABSTRACTCS: Abstract control and status
    constant DMABSTRACTCS_WORD        : natural := 22;
    constant DMABSTRACTCS_ADDR        : natural := 88;
    constant DMABSTRACTCS_RESET       : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMABSTRACTCS_IMPL        : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMPROGBUFSIZE_MSB        : natural := 28;
    constant DMPROGBUFSIZE_LSB        : natural := 24;
    constant DMPROGBUFSIZE_RESET      : std_logic_vector(4 downto 0) := "00000";
    constant DMBUSY_MSB               : natural := 12;
    constant DMBUSY_LSB               : natural := 12;
    constant DMBUSY_RESET             : std_logic_vector(0 downto 0) := "0";
    constant DMCMDERR_MSB             : natural := 10;
    constant DMCMDERR_LSB             : natural := 8;
    constant DMCMDERR_RESET           : std_logic_vector(2 downto 0) := "000";
    constant DMDATACOUNT_MSB          : natural := 3;
    constant DMDATACOUNT_LSB          : natural := 0;
    constant DMDATACOUNT_RESET        : std_logic_vector(3 downto 0) := "0000";

    -- DMCOMMAND: Abstract command
    constant DMCOMMAND_WORD           : natural := 23;
    constant DMCOMMAND_ADDR           : natural := 92;
    constant DMCOMMAND_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMCOMMAND_IMPL           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMCOMMAND_MSB            : natural := 31;
    constant DMCOMMAND_LSB            : natural := 0;
    -- DMCOMMAND_RESET is the register constant above; this field carries the register name.

    -- DMABSTRACTAUTO: Abstract command autoexec
    constant DMABSTRACTAUTO_WORD      : natural := 24;
    constant DMABSTRACTAUTO_ADDR      : natural := 96;
    constant DMABSTRACTAUTO_RESET     : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMABSTRACTAUTO_IMPL      : std_logic_vector(31 downto 0) := "00000000000000110000000000000001";
    constant DMAUTOEXECPROGBUF_MSB    : natural := 17;
    constant DMAUTOEXECPROGBUF_LSB    : natural := 16;
    constant DMAUTOEXECPROGBUF_RESET  : std_logic_vector(1 downto 0) := "00";
    constant DMAUTOEXECDATA_MSB       : natural := 0;
    constant DMAUTOEXECDATA_LSB       : natural := 0;
    constant DMAUTOEXECDATA_RESET     : std_logic_vector(0 downto 0) := "0";

    -- DMPROGBUF0: Program buffer word 0. Proxied to the backing word like data0, and an access while the master engine is busy is refused with CMDERR = BUSY
    constant DMPROGBUF0_WORD          : natural := 32;
    constant DMPROGBUF0_ADDR          : natural := 128;
    constant DMPROGBUF0_RESET         : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMPROGBUF0_IMPL          : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant DMPROGBUF0_MSB           : natural := 31;
    constant DMPROGBUF0_LSB           : natural := 0;
    -- DMPROGBUF0_RESET is the register constant above; this field carries the register name.

    -- DMPROGBUF1: Program buffer word 1. Same proxy, same busy refusal and same ebreak substitution as progbuf0. The implicit third word is an ebreak (dmstatus
    constant DMPROGBUF1_WORD          : natural := 33;
    constant DMPROGBUF1_ADDR          : natural := 132;
    constant DMPROGBUF1_RESET         : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMPROGBUF1_IMPL          : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant DMPROGBUF1_MSB           : natural := 31;
    constant DMPROGBUF1_LSB           : natural := 0;
    -- DMPROGBUF1_RESET is the register constant above; this field carries the register name.

    -- DMCS2: Halt-group assignment of the selected hart
    constant DMCS2_WORD               : natural := 50;
    constant DMCS2_ADDR               : natural := 200;
    constant DMCS2_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMCS2_IMPL               : std_logic_vector(31 downto 0) := "00000000000000000000000001111101";
    constant DMGROUP_MSB              : natural := 6;
    constant DMGROUP_LSB              : natural := 2;
    constant DMGROUP_RESET            : std_logic_vector(4 downto 0) := "00000";
    constant DMHGWRITE_MSB            : natural := 1;
    constant DMHGWRITE_LSB            : natural := 1;
    constant DMHGWRITE_RESET          : std_logic_vector(0 downto 0) := "0";
    constant DMHGSELECT_MSB           : natural := 0;
    constant DMHGSELECT_LSB           : natural := 0;
    constant DMHGSELECT_RESET         : std_logic_vector(0 downto 0) := "0";

    -- DMSBCS: System Bus Access control and status
    constant DMSBCS_WORD              : natural := 56;
    constant DMSBCS_ADDR              : natural := 224;
    constant DMSBCS_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMSBCS_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- DMHALTSUM0: Halt summary 0, read only
    constant DMHALTSUM0_WORD          : natural := 64;
    constant DMHALTSUM0_ADDR          : natural := 256;
    constant DMHALTSUM0_RESET         : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMHALTSUM0_IMPL          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMHALTSUM0_MSB           : natural := 31;
    constant DMHALTSUM0_LSB           : natural := 0;
    -- DMHALTSUM0_RESET is the register constant above; this field carries the register name.

    -- No periph_regs table section: the Debug Module is not on the peripheral bus at all (DMI, not
    -- EnMemPeriph / WEn / MABPart), so there is no adoption path.
    -- See hdl/common/regs/REGFILE.md.

end package debug_module_regs_pkg;
