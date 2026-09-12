-- VestaRV: EVFAB register package
-- Event/trigger fabric: a PPI-style crossbar that lets peripherals command each other with no processor in the loop
-- Generated from hdl/common/regs/rdl/evfab.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.

library ieee;
use ieee.std_logic_1164.all;
library work;
use work.constants.all;

package evfab_regs_pkg is

    -- EVFCR: Event fabric control register
    constant EVFCR_WORD               : natural := 0;
    constant EVFCR_ADDR               : natural := 0;
    constant EVFCR_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCR_IMPL               : std_logic_vector(31 downto 0) := "00000000000000000000000000000001";
    constant EVFEN_MSB                : natural := 0;
    constant EVFEN_LSB                : natural := 0;
    constant EVFEN_RESET              : std_logic_vector(0 downto 0) := "0";

    -- EVFSR: Event fabric status register
    constant EVFSR_WORD               : natural := 1;
    constant EVFSR_ADDR               : natural := 4;
    constant EVFSR_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFSR_IMPL               : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFOVRIF_MSB             : natural := 1;
    constant EVFOVRIF_LSB             : natural := 1;
    constant EVFOVRIF_RESET           : std_logic_vector(0 downto 0) := "0";
    constant EVFFIREDIF_MSB           : natural := 0;
    constant EVFFIREDIF_LSB           : natural := 0;
    constant EVFFIREDIF_RESET         : std_logic_vector(0 downto 0) := "0";

    -- EVFIE: Reserved interrupt-enable register
    constant EVFIE_WORD               : natural := 2;
    constant EVFIE_ADDR               : natural := 8;
    constant EVFIE_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFIE_IMPL               : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- EVFCAP: Capability register (read-only constant)
    constant EVFCAP_WORD              : natural := 3;
    constant EVFCAP_ADDR              : natural := 12;
    constant EVFCAP_RESET             : std_logic_vector(31 downto 0) := "00000001000010100001000000001000";
    constant EVFCAP_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFVER_MSB               : natural := 31;
    constant EVFVER_LSB               : natural := 24;
    constant EVFVER_RESET             : std_logic_vector(7 downto 0) := "00000001";
    constant EVFNTASK_MSB             : natural := 23;
    constant EVFNTASK_LSB             : natural := 16;
    constant EVFNTASK_RESET           : std_logic_vector(7 downto 0) := "00001010";
    constant EVFNEV_MSB               : natural := 15;
    constant EVFNEV_LSB               : natural := 8;
    constant EVFNEV_RESET             : std_logic_vector(7 downto 0) := "00010000";
    constant EVFNCH_MSB               : natural := 7;
    constant EVFNCH_LSB               : natural := 0;
    constant EVFNCH_RESET             : std_logic_vector(7 downto 0) := "00001000";

    -- EVFCHEN: Channel enable register
    constant EVFCHEN_WORD             : natural := 4;
    constant EVFCHEN_ADDR             : natural := 16;
    constant EVFCHEN_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCHEN_IMPL             : std_logic_vector(31 downto 0) := "00000000000000000000000011111111";
    constant EVFCHEN_MSB              : natural := 7;
    constant EVFCHEN_LSB              : natural := 0;
    -- EVFCHEN_RESET is the register constant above; this field carries the register name.

    -- EVFCHENSET: Channel enable SET alias
    constant EVFCHENSET_WORD          : natural := 5;
    constant EVFCHENSET_ADDR          : natural := 20;
    constant EVFCHENSET_RESET         : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCHENSET_IMPL          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCHENSET_MSB           : natural := 7;
    constant EVFCHENSET_LSB           : natural := 0;
    -- EVFCHENSET_RESET is the register constant above; this field carries the register name.

    -- EVFCHENCLR: Channel enable CLEAR alias
    constant EVFCHENCLR_WORD          : natural := 6;
    constant EVFCHENCLR_ADDR          : natural := 24;
    constant EVFCHENCLR_RESET         : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCHENCLR_IMPL          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCHENCLR_MSB           : natural := 7;
    constant EVFCHENCLR_LSB           : natural := 0;
    -- EVFCHENCLR_RESET is the register constant above; this field carries the register name.

    -- EVFCHTRIG: Channel trigger injection register
    constant EVFCHTRIG_WORD           : natural := 7;
    constant EVFCHTRIG_ADDR           : natural := 28;
    constant EVFCHTRIG_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCHTRIG_IMPL           : std_logic_vector(31 downto 0) := "00000000000000000000000011111111";
    constant EVFCHTRIG_MSB            : natural := 7;
    constant EVFCHTRIG_LSB            : natural := 0;
    -- EVFCHTRIG_RESET is the register constant above; this field carries the register name.

    -- EVFFIRED: Sticky channel-fired flags
    constant EVFFIRED_WORD            : natural := 8;
    constant EVFFIRED_ADDR            : natural := 32;
    constant EVFFIRED_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFFIRED_IMPL            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFFIRED_MSB             : natural := 7;
    constant EVFFIRED_LSB             : natural := 0;
    -- EVFFIRED_RESET is the register constant above; this field carries the register name.

    -- EVFOVR: Sticky channel-overrun flags
    constant EVFOVR_WORD              : natural := 9;
    constant EVFOVR_ADDR              : natural := 36;
    constant EVFOVR_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFOVR_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFOVR_MSB               : natural := 7;
    constant EVFOVR_LSB               : natural := 0;
    -- EVFOVR_RESET is the register constant above; this field carries the register name.

    -- EVFEVSTAT: Sticky raw-event record
    constant EVFEVSTAT_WORD           : natural := 10;
    constant EVFEVSTAT_ADDR           : natural := 40;
    constant EVFEVSTAT_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFEVSTAT_IMPL           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFEVSTAT_MSB            : natural := 15;
    constant EVFEVSTAT_LSB            : natural := 0;
    -- EVFEVSTAT_RESET is the register constant above; this field carries the register name.

    -- EVFEVTRIG: Raw event injection register
    constant EVFEVTRIG_WORD           : natural := 11;
    constant EVFEVTRIG_ADDR           : natural := 44;
    constant EVFEVTRIG_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFEVTRIG_IMPL           : std_logic_vector(31 downto 0) := "00000000000000001111111111111111";
    constant EVFEVTRIG_MSB            : natural := 15;
    constant EVFEVTRIG_LSB            : natural := 0;
    -- EVFEVTRIG_RESET is the register constant above; this field carries the register name.

    -- EVFGPIOMASK: GPIO0 edge-path mask
    constant EVFGPIOMASK_WORD         : natural := 15;
    constant EVFGPIOMASK_ADDR         : natural := 60;
    constant EVFGPIOMASK_RESET        : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFGPIOMASK_IMPL         : std_logic_vector(31 downto 0) := "00000000000000000000000011111111";
    constant EVFGPIOMASK_MSB          : natural := 7;
    constant EVFGPIOMASK_LSB          : natural := 0;
    -- EVFGPIOMASK_RESET is the register constant above; this field carries the register name.

    -- EVFCH0CFG: Channel 0 configuration
    constant EVFCH0CFG_WORD           : natural := 16;
    constant EVFCH0CFG_ADDR           : natural := 64;
    constant EVFCH0CFG_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCH0CFG_IMPL           : std_logic_vector(31 downto 0) := "00000000000000000000111100011111";
    constant EVFENR0_MSB              : natural := 31;
    constant EVFENR0_LSB              : natural := 31;
    constant EVFENR0_RESET            : std_logic_vector(0 downto 0) := "0";
    constant EVFTASKSEL0_MSB          : natural := 11;
    constant EVFTASKSEL0_LSB          : natural := 8;
    constant EVFTASKSEL0_RESET        : std_logic_vector(3 downto 0) := "0000";
    constant EVFEVSEL0_MSB            : natural := 4;
    constant EVFEVSEL0_LSB            : natural := 0;
    constant EVFEVSEL0_RESET          : std_logic_vector(4 downto 0) := "00000";

    -- EVFCH1CFG: Channel 1 configuration
    constant EVFCH1CFG_WORD           : natural := 17;
    constant EVFCH1CFG_ADDR           : natural := 68;
    constant EVFCH1CFG_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCH1CFG_IMPL           : std_logic_vector(31 downto 0) := "00000000000000000000111100011111";
    constant EVFENR1_MSB              : natural := 31;
    constant EVFENR1_LSB              : natural := 31;
    constant EVFENR1_RESET            : std_logic_vector(0 downto 0) := "0";
    constant EVFTASKSEL1_MSB          : natural := 11;
    constant EVFTASKSEL1_LSB          : natural := 8;
    constant EVFTASKSEL1_RESET        : std_logic_vector(3 downto 0) := "0000";
    constant EVFEVSEL1_MSB            : natural := 4;
    constant EVFEVSEL1_LSB            : natural := 0;
    constant EVFEVSEL1_RESET          : std_logic_vector(4 downto 0) := "00000";

    -- EVFCH2CFG: Channel 2 configuration
    constant EVFCH2CFG_WORD           : natural := 18;
    constant EVFCH2CFG_ADDR           : natural := 72;
    constant EVFCH2CFG_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCH2CFG_IMPL           : std_logic_vector(31 downto 0) := "00000000000000000000111100011111";
    constant EVFENR2_MSB              : natural := 31;
    constant EVFENR2_LSB              : natural := 31;
    constant EVFENR2_RESET            : std_logic_vector(0 downto 0) := "0";
    constant EVFTASKSEL2_MSB          : natural := 11;
    constant EVFTASKSEL2_LSB          : natural := 8;
    constant EVFTASKSEL2_RESET        : std_logic_vector(3 downto 0) := "0000";
    constant EVFEVSEL2_MSB            : natural := 4;
    constant EVFEVSEL2_LSB            : natural := 0;
    constant EVFEVSEL2_RESET          : std_logic_vector(4 downto 0) := "00000";

    -- EVFCH3CFG: Channel 3 configuration
    constant EVFCH3CFG_WORD           : natural := 19;
    constant EVFCH3CFG_ADDR           : natural := 76;
    constant EVFCH3CFG_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCH3CFG_IMPL           : std_logic_vector(31 downto 0) := "00000000000000000000111100011111";
    constant EVFENR3_MSB              : natural := 31;
    constant EVFENR3_LSB              : natural := 31;
    constant EVFENR3_RESET            : std_logic_vector(0 downto 0) := "0";
    constant EVFTASKSEL3_MSB          : natural := 11;
    constant EVFTASKSEL3_LSB          : natural := 8;
    constant EVFTASKSEL3_RESET        : std_logic_vector(3 downto 0) := "0000";
    constant EVFEVSEL3_MSB            : natural := 4;
    constant EVFEVSEL3_LSB            : natural := 0;
    constant EVFEVSEL3_RESET          : std_logic_vector(4 downto 0) := "00000";

    -- EVFCH4CFG: Channel 4 configuration
    constant EVFCH4CFG_WORD           : natural := 20;
    constant EVFCH4CFG_ADDR           : natural := 80;
    constant EVFCH4CFG_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCH4CFG_IMPL           : std_logic_vector(31 downto 0) := "00000000000000000000111100011111";
    constant EVFENR4_MSB              : natural := 31;
    constant EVFENR4_LSB              : natural := 31;
    constant EVFENR4_RESET            : std_logic_vector(0 downto 0) := "0";
    constant EVFTASKSEL4_MSB          : natural := 11;
    constant EVFTASKSEL4_LSB          : natural := 8;
    constant EVFTASKSEL4_RESET        : std_logic_vector(3 downto 0) := "0000";
    constant EVFEVSEL4_MSB            : natural := 4;
    constant EVFEVSEL4_LSB            : natural := 0;
    constant EVFEVSEL4_RESET          : std_logic_vector(4 downto 0) := "00000";

    -- EVFCH5CFG: Channel 5 configuration
    constant EVFCH5CFG_WORD           : natural := 21;
    constant EVFCH5CFG_ADDR           : natural := 84;
    constant EVFCH5CFG_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCH5CFG_IMPL           : std_logic_vector(31 downto 0) := "00000000000000000000111100011111";
    constant EVFENR5_MSB              : natural := 31;
    constant EVFENR5_LSB              : natural := 31;
    constant EVFENR5_RESET            : std_logic_vector(0 downto 0) := "0";
    constant EVFTASKSEL5_MSB          : natural := 11;
    constant EVFTASKSEL5_LSB          : natural := 8;
    constant EVFTASKSEL5_RESET        : std_logic_vector(3 downto 0) := "0000";
    constant EVFEVSEL5_MSB            : natural := 4;
    constant EVFEVSEL5_LSB            : natural := 0;
    constant EVFEVSEL5_RESET          : std_logic_vector(4 downto 0) := "00000";

    -- EVFCH6CFG: Channel 6 configuration
    constant EVFCH6CFG_WORD           : natural := 22;
    constant EVFCH6CFG_ADDR           : natural := 88;
    constant EVFCH6CFG_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCH6CFG_IMPL           : std_logic_vector(31 downto 0) := "00000000000000000000111100011111";
    constant EVFENR6_MSB              : natural := 31;
    constant EVFENR6_LSB              : natural := 31;
    constant EVFENR6_RESET            : std_logic_vector(0 downto 0) := "0";
    constant EVFTASKSEL6_MSB          : natural := 11;
    constant EVFTASKSEL6_LSB          : natural := 8;
    constant EVFTASKSEL6_RESET        : std_logic_vector(3 downto 0) := "0000";
    constant EVFEVSEL6_MSB            : natural := 4;
    constant EVFEVSEL6_LSB            : natural := 0;
    constant EVFEVSEL6_RESET          : std_logic_vector(4 downto 0) := "00000";

    -- EVFCH7CFG: Channel 7 configuration
    constant EVFCH7CFG_WORD           : natural := 23;
    constant EVFCH7CFG_ADDR           : natural := 92;
    constant EVFCH7CFG_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCH7CFG_IMPL           : std_logic_vector(31 downto 0) := "00000000000000000000111100011111";
    constant EVFENR7_MSB              : natural := 31;
    constant EVFENR7_LSB              : natural := 31;
    constant EVFENR7_RESET            : std_logic_vector(0 downto 0) := "0";
    constant EVFTASKSEL7_MSB          : natural := 11;
    constant EVFTASKSEL7_LSB          : natural := 8;
    constant EVFTASKSEL7_RESET        : std_logic_vector(3 downto 0) := "0000";
    constant EVFEVSEL7_MSB            : natural := 4;
    constant EVFEVSEL7_LSB            : natural := 0;
    constant EVFEVSEL7_RESET          : std_logic_vector(4 downto 0) := "00000";

    -- EVFCH8CFG: Reserved channel-8 configuration slot
    constant EVFCH8CFG_WORD           : natural := 24;
    constant EVFCH8CFG_ADDR           : natural := 96;
    constant EVFCH8CFG_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCH8CFG_IMPL           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- EVFCH9CFG: Reserved channel-9 configuration slot
    constant EVFCH9CFG_WORD           : natural := 25;
    constant EVFCH9CFG_ADDR           : natural := 100;
    constant EVFCH9CFG_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCH9CFG_IMPL           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- EVFCH10CFG: Reserved channel-10 configuration slot
    constant EVFCH10CFG_WORD          : natural := 26;
    constant EVFCH10CFG_ADDR          : natural := 104;
    constant EVFCH10CFG_RESET         : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCH10CFG_IMPL          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- EVFCH11CFG: Reserved channel-11 configuration slot
    constant EVFCH11CFG_WORD          : natural := 27;
    constant EVFCH11CFG_ADDR          : natural := 108;
    constant EVFCH11CFG_RESET         : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCH11CFG_IMPL          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- EVFCH12CFG: Reserved channel-12 configuration slot
    constant EVFCH12CFG_WORD          : natural := 28;
    constant EVFCH12CFG_ADDR          : natural := 112;
    constant EVFCH12CFG_RESET         : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCH12CFG_IMPL          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- EVFCH13CFG: Reserved channel-13 configuration slot
    constant EVFCH13CFG_WORD          : natural := 29;
    constant EVFCH13CFG_ADDR          : natural := 116;
    constant EVFCH13CFG_RESET         : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCH13CFG_IMPL          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- EVFCH14CFG: Reserved channel-14 configuration slot
    constant EVFCH14CFG_WORD          : natural := 30;
    constant EVFCH14CFG_ADDR          : natural := 120;
    constant EVFCH14CFG_RESET         : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCH14CFG_IMPL          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- EVFCH15CFG: Reserved channel-15 configuration slot
    constant EVFCH15CFG_WORD          : natural := 31;
    constant EVFCH15CFG_ADDR          : natural := 124;
    constant EVFCH15CFG_RESET         : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant EVFCH15CFG_IMPL          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- EVFAB.vhd's own decode identifiers: the word each register is
    -- decoded at, spelled the way that file already spells it, so adopting this
    -- package is a context clause plus a deletion and no assignment moves.
    constant SLOT_CR                  : natural := 0;
    constant SLOT_SR                  : natural := 1;
    constant SLOT_IE                  : natural := 2;
    constant SLOT_CAP                 : natural := 3;
    constant SLOT_CHEN                : natural := 4;
    constant SLOT_CHENSET             : natural := 5;
    constant SLOT_CHENCLR             : natural := 6;
    constant SLOT_CHTRIG              : natural := 7;
    constant SLOT_FIRED               : natural := 8;
    constant SLOT_OVR                 : natural := 9;
    constant SLOT_EVSTAT              : natural := 10;
    constant SLOT_EVTRIG              : natural := 11;
    constant SLOT_GPIOMASK            : natural := 15;
    constant SLOT_CH0CFG              : natural := 16;

    -- periph_regs tables (hdl/common/periph_regs.vhd), one row per word in slot
    -- order. Every mask below is a property of this description. RDTHRU, WIDEWR,
    -- FULLWR and STROBE_HOLD are the entity's own and are set at the instance;
    -- hdl/common/regs/REGFILE.md says why they cannot come from SystemRDL.
    -- The table is SPARSE: words 12-14 carry no register here, and the
    -- all-zero _reserved_<word> row is what makes it read 0, store nothing
    -- and take no hook, which is the `when others` arm it replaces.
    constant NWORDS                   : natural := 32;
    subtype  reg_arr_t is word_array(0 to NWORDS-1);

    -- reset word, loaded on the asynchronous resetn
    constant RSTVAL   : reg_arr_t := (
        x"00000000",   -- EVFCR
        x"00000000",   -- EVFSR
        x"00000000",   -- EVFIE
        x"010A1008",   -- EVFCAP
        x"00000000",   -- EVFCHEN
        x"00000000",   -- EVFCHENSET
        x"00000000",   -- EVFCHENCLR
        x"00000000",   -- EVFCHTRIG
        x"00000000",   -- EVFFIRED
        x"00000000",   -- EVFOVR
        x"00000000",   -- EVFEVSTAT
        x"00000000",   -- EVFEVTRIG
        x"00000000",   -- _reserved_12
        x"00000000",   -- _reserved_13
        x"00000000",   -- _reserved_14
        x"00000000",   -- EVFGPIOMASK
        x"00000000",   -- EVFCH0CFG
        x"00000000",   -- EVFCH1CFG
        x"00000000",   -- EVFCH2CFG
        x"00000000",   -- EVFCH3CFG
        x"00000000",   -- EVFCH4CFG
        x"00000000",   -- EVFCH5CFG
        x"00000000",   -- EVFCH6CFG
        x"00000000",   -- EVFCH7CFG
        x"00000000",   -- EVFCH8CFG
        x"00000000",   -- EVFCH9CFG
        x"00000000",   -- EVFCH10CFG
        x"00000000",   -- EVFCH11CFG
        x"00000000",   -- EVFCH12CFG
        x"00000000",   -- EVFCH13CFG
        x"00000000",   -- EVFCH14CFG
        x"00000000"    -- EVFCH15CFG
    );

    -- bits that hold a software-written flop; periph_regs stores exactly these
    constant IMPL     : reg_arr_t := (
        x"00000001",   -- EVFCR
        x"00000000",   -- EVFSR
        x"00000000",   -- EVFIE
        x"00000000",   -- EVFCAP
        x"000000FF",   -- EVFCHEN
        x"00000000",   -- EVFCHENSET
        x"00000000",   -- EVFCHENCLR
        x"000000FF",   -- EVFCHTRIG
        x"00000000",   -- EVFFIRED
        x"00000000",   -- EVFOVR
        x"00000000",   -- EVFEVSTAT
        x"0000FFFF",   -- EVFEVTRIG
        x"00000000",   -- _reserved_12
        x"00000000",   -- _reserved_13
        x"00000000",   -- _reserved_14
        x"000000FF",   -- EVFGPIOMASK
        x"00000F1F",   -- EVFCH0CFG
        x"00000F1F",   -- EVFCH1CFG
        x"00000F1F",   -- EVFCH2CFG
        x"00000F1F",   -- EVFCH3CFG
        x"00000F1F",   -- EVFCH4CFG
        x"00000F1F",   -- EVFCH5CFG
        x"00000F1F",   -- EVFCH6CFG
        x"00000F1F",   -- EVFCH7CFG
        x"00000000",   -- EVFCH8CFG
        x"00000000",   -- EVFCH9CFG
        x"00000000",   -- EVFCH10CFG
        x"00000000",   -- EVFCH11CFG
        x"00000000",   -- EVFCH12CFG
        x"00000000",   -- EVFCH13CFG
        x"00000000",   -- EVFCH14CFG
        x"00000000"    -- EVFCH15CFG
    );

    -- a written 1 clears (onwrite = woclr): drives w1c_hit
    constant W1C      : reg_arr_t := (
        x"00000000",   -- EVFCR
        x"00000000",   -- EVFSR
        x"00000000",   -- EVFIE
        x"00000000",   -- EVFCAP
        x"00000000",   -- EVFCHEN
        x"00000000",   -- EVFCHENSET
        x"000000FF",   -- EVFCHENCLR
        x"00000000",   -- EVFCHTRIG
        x"000000FF",   -- EVFFIRED
        x"000000FF",   -- EVFOVR
        x"0000FFFF",   -- EVFEVSTAT
        x"00000000",   -- EVFEVTRIG
        x"00000000",   -- _reserved_12
        x"00000000",   -- _reserved_13
        x"00000000",   -- _reserved_14
        x"00000000",   -- EVFGPIOMASK
        x"00000000",   -- EVFCH0CFG
        x"00000000",   -- EVFCH1CFG
        x"00000000",   -- EVFCH2CFG
        x"00000000",   -- EVFCH3CFG
        x"00000000",   -- EVFCH4CFG
        x"00000000",   -- EVFCH5CFG
        x"00000000",   -- EVFCH6CFG
        x"00000000",   -- EVFCH7CFG
        x"00000000",   -- EVFCH8CFG
        x"00000000",   -- EVFCH9CFG
        x"00000000",   -- EVFCH10CFG
        x"00000000",   -- EVFCH11CFG
        x"00000000",   -- EVFCH12CFG
        x"00000000",   -- EVFCH13CFG
        x"00000000",   -- EVFCH14CFG
        x"00000000"    -- EVFCH15CFG
    );

    -- a written 1 sets (onwrite = woset): drives woset_hit
    constant WOSET    : reg_arr_t := (
        x"00000000",   -- EVFCR
        x"00000000",   -- EVFSR
        x"00000000",   -- EVFIE
        x"00000000",   -- EVFCAP
        x"00000000",   -- EVFCHEN
        x"000000FF",   -- EVFCHENSET
        x"00000000",   -- EVFCHENCLR
        x"00000000",   -- EVFCHTRIG
        x"00000000",   -- EVFFIRED
        x"00000000",   -- EVFOVR
        x"00000000",   -- EVFEVSTAT
        x"00000000",   -- EVFEVTRIG
        x"00000000",   -- _reserved_12
        x"00000000",   -- _reserved_13
        x"00000000",   -- _reserved_14
        x"00000000",   -- EVFGPIOMASK
        x"00000000",   -- EVFCH0CFG
        x"00000000",   -- EVFCH1CFG
        x"00000000",   -- EVFCH2CFG
        x"00000000",   -- EVFCH3CFG
        x"00000000",   -- EVFCH4CFG
        x"00000000",   -- EVFCH5CFG
        x"00000000",   -- EVFCH6CFG
        x"00000000",   -- EVFCH7CFG
        x"00000000",   -- EVFCH8CFG
        x"00000000",   -- EVFCH9CFG
        x"00000000",   -- EVFCH10CFG
        x"00000000",   -- EVFCH11CFG
        x"00000000",   -- EVFCH12CFG
        x"00000000",   -- EVFCH13CFG
        x"00000000",   -- EVFCH14CFG
        x"00000000"    -- EVFCH15CFG
    );

    -- a written 1 toggles (onwrite = wot): drives wot_hit
    constant WOT      : reg_arr_t := (
        x"00000000",   -- EVFCR
        x"00000000",   -- EVFSR
        x"00000000",   -- EVFIE
        x"00000000",   -- EVFCAP
        x"00000000",   -- EVFCHEN
        x"00000000",   -- EVFCHENSET
        x"00000000",   -- EVFCHENCLR
        x"00000000",   -- EVFCHTRIG
        x"00000000",   -- EVFFIRED
        x"00000000",   -- EVFOVR
        x"00000000",   -- EVFEVSTAT
        x"00000000",   -- EVFEVTRIG
        x"00000000",   -- _reserved_12
        x"00000000",   -- _reserved_13
        x"00000000",   -- _reserved_14
        x"00000000",   -- EVFGPIOMASK
        x"00000000",   -- EVFCH0CFG
        x"00000000",   -- EVFCH1CFG
        x"00000000",   -- EVFCH2CFG
        x"00000000",   -- EVFCH3CFG
        x"00000000",   -- EVFCH4CFG
        x"00000000",   -- EVFCH5CFG
        x"00000000",   -- EVFCH6CFG
        x"00000000",   -- EVFCH7CFG
        x"00000000",   -- EVFCH8CFG
        x"00000000",   -- EVFCH9CFG
        x"00000000",   -- EVFCH10CFG
        x"00000000",   -- EVFCH11CFG
        x"00000000",   -- EVFCH12CFG
        x"00000000",   -- EVFCH13CFG
        x"00000000",   -- EVFCH14CFG
        x"00000000"    -- EVFCH15CFG
    );

    -- self-clearing strobe (singlepulse): drives wr_pulse, stores nothing
    constant PULSE    : reg_arr_t := (
        x"00000000",   -- EVFCR
        x"00000000",   -- EVFSR
        x"00000000",   -- EVFIE
        x"00000000",   -- EVFCAP
        x"00000000",   -- EVFCHEN
        x"00000000",   -- EVFCHENSET
        x"00000000",   -- EVFCHENCLR
        x"00000000",   -- EVFCHTRIG
        x"00000000",   -- EVFFIRED
        x"00000000",   -- EVFOVR
        x"00000000",   -- EVFEVSTAT
        x"00000000",   -- EVFEVTRIG
        x"00000000",   -- _reserved_12
        x"00000000",   -- _reserved_13
        x"00000000",   -- _reserved_14
        x"00000000",   -- EVFGPIOMASK
        x"00000000",   -- EVFCH0CFG
        x"00000000",   -- EVFCH1CFG
        x"00000000",   -- EVFCH2CFG
        x"00000000",   -- EVFCH3CFG
        x"00000000",   -- EVFCH4CFG
        x"00000000",   -- EVFCH5CFG
        x"00000000",   -- EVFCH6CFG
        x"00000000",   -- EVFCH7CFG
        x"00000000",   -- EVFCH8CFG
        x"00000000",   -- EVFCH9CFG
        x"00000000",   -- EVFCH10CFG
        x"00000000",   -- EVFCH11CFG
        x"00000000",   -- EVFCH12CFG
        x"00000000",   -- EVFCH13CFG
        x"00000000",   -- EVFCH14CFG
        x"00000000"    -- EVFCH15CFG
    );

    -- a read retires (onread = rclr): drives rd_clr
    constant RCLR     : reg_arr_t := (
        x"00000000",   -- EVFCR
        x"00000000",   -- EVFSR
        x"00000000",   -- EVFIE
        x"00000000",   -- EVFCAP
        x"00000000",   -- EVFCHEN
        x"00000000",   -- EVFCHENSET
        x"00000000",   -- EVFCHENCLR
        x"00000000",   -- EVFCHTRIG
        x"00000000",   -- EVFFIRED
        x"00000000",   -- EVFOVR
        x"00000000",   -- EVFEVSTAT
        x"00000000",   -- EVFEVTRIG
        x"00000000",   -- _reserved_12
        x"00000000",   -- _reserved_13
        x"00000000",   -- _reserved_14
        x"00000000",   -- EVFGPIOMASK
        x"00000000",   -- EVFCH0CFG
        x"00000000",   -- EVFCH1CFG
        x"00000000",   -- EVFCH2CFG
        x"00000000",   -- EVFCH3CFG
        x"00000000",   -- EVFCH4CFG
        x"00000000",   -- EVFCH5CFG
        x"00000000",   -- EVFCH6CFG
        x"00000000",   -- EVFCH7CFG
        x"00000000",   -- EVFCH8CFG
        x"00000000",   -- EVFCH9CFG
        x"00000000",   -- EVFCH10CFG
        x"00000000",   -- EVFCH11CFG
        x"00000000",   -- EVFCH12CFG
        x"00000000",   -- EVFCH13CFG
        x"00000000",   -- EVFCH14CFG
        x"00000000"    -- EVFCH15CFG
    );

    -- bits hardware drives (hw = w or rw): what hw_we / hw_set / hw_clr may touch
    constant HWOWN    : reg_arr_t := (
        x"00000000",   -- EVFCR
        x"00000003",   -- EVFSR
        x"00000000",   -- EVFIE
        x"FFFFFFFF",   -- EVFCAP
        x"00000000",   -- EVFCHEN
        x"000000FF",   -- EVFCHENSET
        x"000000FF",   -- EVFCHENCLR
        x"00000000",   -- EVFCHTRIG
        x"000000FF",   -- EVFFIRED
        x"000000FF",   -- EVFOVR
        x"0000FFFF",   -- EVFEVSTAT
        x"00000000",   -- EVFEVTRIG
        x"00000000",   -- _reserved_12
        x"00000000",   -- _reserved_13
        x"00000000",   -- _reserved_14
        x"00000000",   -- EVFGPIOMASK
        x"80000000",   -- EVFCH0CFG
        x"80000000",   -- EVFCH1CFG
        x"80000000",   -- EVFCH2CFG
        x"80000000",   -- EVFCH3CFG
        x"80000000",   -- EVFCH4CFG
        x"80000000",   -- EVFCH5CFG
        x"80000000",   -- EVFCH6CFG
        x"80000000",   -- EVFCH7CFG
        x"00000000",   -- EVFCH8CFG
        x"00000000",   -- EVFCH9CFG
        x"00000000",   -- EVFCH10CFG
        x"00000000",   -- EVFCH11CFG
        x"00000000",   -- EVFCH12CFG
        x"00000000",   -- EVFCH13CFG
        x"00000000",   -- EVFCH14CFG
        x"00000000"    -- EVFCH15CFG
    );

end package evfab_regs_pkg;
