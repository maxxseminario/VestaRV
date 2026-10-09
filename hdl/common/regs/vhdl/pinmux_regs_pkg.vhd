-- VestaRV: PINMUX register package
-- Pin multiplexer for the spare digital pads
-- Generated from hdl/common/regs/rdl/pinmux.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.
-- Configuration-dependent: only what is common to NPADS 8, 16, 40, 64, 120 (NSELW = ceil(NPADS/8), NINW = ceil(NPADS/32), MAXMENU 8) is emitted, the rest stays a generic in PINMUX.vhd.

library ieee;
use ieee.std_logic_1164.all;
library work;
use work.constants.all;

package pinmux_regs_pkg is

    -- PMXCAP: Pin-mux capability register, read-only
    constant PMXCAP_WORD              : natural := 0;
    constant PMXCAP_ADDR              : natural := 0;
    constant PMXCAP_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PMXCAP_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PMXREV_MSB               : natural := 15;
    constant PMXREV_LSB               : natural := 12;
    constant PMXREV_RESET             : std_logic_vector(3 downto 0) := "0000";
    constant PMXMENU_MSB              : natural := 11;
    constant PMXMENU_LSB              : natural := 8;
    constant PMXMENU_RESET            : std_logic_vector(3 downto 0) := "0000";
    constant PMXNPADS_MSB             : natural := 7;
    constant PMXNPADS_LSB             : natural := 0;
    constant PMXNPADS_RESET           : std_logic_vector(7 downto 0) := "00000000";

    -- PMXIN0: Pin-mux pad input register 0, read-only: the logic level of pads 32*0+31 down to 32*0, whatever function the pad is selecting and whichever way it is driven
    constant PMXIN0_WORD              : natural := 1;
    constant PMXIN0_ADDR              : natural := 4;
    constant PMXIN0_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PMXIN0_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PMXPIN0_MSB              : natural := 31;
    constant PMXPIN0_LSB              : natural := 0;
    constant PMXPIN0_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- PMXCFG0: Pin-mux pad select register 0: one 4-bit select field per pad for pads 8*0+7 down to 8*0. A field at 0 (the reset value) leaves its pad DISABLED, meaning the pad output driver is off, the pull resistor is disabled and the pad is a floating input; a field at 1 through PMXMENU selects that entry of the PAD'S OWN function menu, which is per pad and is tabulated in the pin configuration table of the Pin Multiplexer chapter
    constant PMXCFG0_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PMXCFG0_IMPL             : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant PMXSEL7_MSB              : natural := 31;
    constant PMXSEL7_LSB              : natural := 28;
    constant PMXSEL7_RESET            : std_logic_vector(3 downto 0) := "0000";
    constant PMXSEL6_MSB              : natural := 27;
    constant PMXSEL6_LSB              : natural := 24;
    constant PMXSEL6_RESET            : std_logic_vector(3 downto 0) := "0000";
    constant PMXSEL5_MSB              : natural := 23;
    constant PMXSEL5_LSB              : natural := 20;
    constant PMXSEL5_RESET            : std_logic_vector(3 downto 0) := "0000";
    constant PMXSEL4_MSB              : natural := 19;
    constant PMXSEL4_LSB              : natural := 16;
    constant PMXSEL4_RESET            : std_logic_vector(3 downto 0) := "0000";
    constant PMXSEL3_MSB              : natural := 15;
    constant PMXSEL3_LSB              : natural := 12;
    constant PMXSEL3_RESET            : std_logic_vector(3 downto 0) := "0000";
    constant PMXSEL2_MSB              : natural := 11;
    constant PMXSEL2_LSB              : natural := 8;
    constant PMXSEL2_RESET            : std_logic_vector(3 downto 0) := "0000";
    constant PMXSEL1_MSB              : natural := 7;
    constant PMXSEL1_LSB              : natural := 4;
    constant PMXSEL1_RESET            : std_logic_vector(3 downto 0) := "0000";
    constant PMXSEL0_MSB              : natural := 3;
    constant PMXSEL0_LSB              : natural := 0;
    constant PMXSEL0_RESET            : std_logic_vector(3 downto 0) := "0000";

    -- PINMUX.vhd's own decode identifiers: the word each register is
    -- decoded at, spelled the way that file already spells it, so adopting this
    -- package is a context clause plus a deletion and no assignment moves.
    constant W_PMXCAP                 : natural := 0;

    -- periph_regs tables (hdl/common/periph_regs.vhd), built AT ELABORATION from
    -- this block's own generics: the register set is a function of the
    -- configuration, so the rows are a function and not a constant aggregate.
    -- Layout: PMXCAP at word 0, then ceil(NPADS/32) read-only PMXIN words, then ceil(NPADS/8) PMXCFG words of eight 4-bit select nibbles.
    -- The entity passes NWORDS(NPADS) and each table below straight
    -- into its periph_regs generic map. RDTHRU, WIDEWR, FULLWR and STROBE_HOLD
    -- are the entity's own; hdl/common/regs/REGFILE.md says why.
    function NWORDS (NPADS : natural) return natural;
    -- reset word, loaded on the asynchronous resetn
    function RSTVAL (NPADS : natural) return word_array;
    -- bits that hold a software-written flop; periph_regs stores exactly these
    function IMPL   (NPADS : natural) return word_array;
    -- a written 1 clears (onwrite = woclr): drives w1c_hit
    function W1C    (NPADS : natural) return word_array;
    -- a written 1 sets (onwrite = woset): drives woset_hit
    function WOSET  (NPADS : natural) return word_array;
    -- a written 1 toggles (onwrite = wot): drives wot_hit
    function WOT    (NPADS : natural) return word_array;
    -- self-clearing strobe (singlepulse): drives wr_pulse, stores nothing
    function PULSE  (NPADS : natural) return word_array;
    -- a read retires (onread = rclr): drives rd_clr
    function RCLR   (NPADS : natural) return word_array;
    -- bits hardware drives (hw = w or rw): what hw_we / hw_set / hw_clr may touch
    function HWOWN  (NPADS : natural) return word_array;

end package pinmux_regs_pkg;


library ieee;
use ieee.std_logic_1164.all;
library work;
use work.constants.all;

package body pinmux_regs_pkg is

    -- Bits hi downto lo, all zero when the range is EMPTY (hi < lo, which is
    -- the per-hart mask of a single-hart chip) and saturating at bit 31.
    function bitRun (hi, lo : integer) return word is
        variable r : word := (others => '0');
    begin
        for b in 0 to 31 loop
            if b >= lo and b <= hi then
                r(b) := '1';
            end if;
        end loop;
        return r;
    end function bitRun;

    function NWORDS (NPADS : natural) return natural is
    begin
        return 1 + (NPADS + 31) / 32 + (NPADS + 7) / 8;
    end function NWORDS;

    -- reset word, loaded on the asynchronous resetn
    function RSTVAL (NPADS : natural) return word_array is
        variable r : word_array(0 to NWORDS(NPADS) - 1) := (others => (others => '0'));
    begin
        -- PMXCAP: read-only capability, every bit a constant the hardware drives
        r(0) := PMXCAP_RESET;   -- PMXCAP
        -- PMXIN{k}: the synchronised pad levels, read-only, 32 bits per word
        for k in 0 to (NPADS + 31) / 32 - 1 loop
            r(1 + k) := PMXIN0_RESET;   -- PMXIN{k}
        end loop;
        -- PMXCFG{k}: eight select nibbles, all eight stored at every pad count
        for k in 0 to (NPADS + 7) / 8 - 1 loop
            r(1 + (NPADS + 31) / 32 + k) := PMXCFG0_RESET;   -- PMXCFG{k}
        end loop;
        return r;
    end function RSTVAL;

    -- bits that hold a software-written flop; periph_regs stores exactly these
    function IMPL   (NPADS : natural) return word_array is
        variable r : word_array(0 to NWORDS(NPADS) - 1) := (others => (others => '0'));
    begin
        -- PMXCAP: read-only capability, every bit a constant the hardware drives
        r(0) := PMXCAP_IMPL;   -- PMXCAP
        -- PMXIN{k}: the synchronised pad levels, read-only, 32 bits per word
        for k in 0 to (NPADS + 31) / 32 - 1 loop
            r(1 + k) := PMXIN0_IMPL;   -- PMXIN{k}
        end loop;
        -- PMXCFG{k}: eight select nibbles, all eight stored at every pad count
        for k in 0 to (NPADS + 7) / 8 - 1 loop
            r(1 + (NPADS + 31) / 32 + k) := PMXCFG0_IMPL;   -- PMXCFG{k}
        end loop;
        return r;
    end function IMPL;

    -- a written 1 clears (onwrite = woclr): drives w1c_hit
    function W1C    (NPADS : natural) return word_array is
        variable r : word_array(0 to NWORDS(NPADS) - 1) := (others => (others => '0'));
    begin
        -- The description declares none of these in this block.
        return r;
    end function W1C;

    -- a written 1 sets (onwrite = woset): drives woset_hit
    function WOSET  (NPADS : natural) return word_array is
        variable r : word_array(0 to NWORDS(NPADS) - 1) := (others => (others => '0'));
    begin
        -- The description declares none of these in this block.
        return r;
    end function WOSET;

    -- a written 1 toggles (onwrite = wot): drives wot_hit
    function WOT    (NPADS : natural) return word_array is
        variable r : word_array(0 to NWORDS(NPADS) - 1) := (others => (others => '0'));
    begin
        -- The description declares none of these in this block.
        return r;
    end function WOT;

    -- self-clearing strobe (singlepulse): drives wr_pulse, stores nothing
    function PULSE  (NPADS : natural) return word_array is
        variable r : word_array(0 to NWORDS(NPADS) - 1) := (others => (others => '0'));
    begin
        -- The description declares none of these in this block.
        return r;
    end function PULSE;

    -- a read retires (onread = rclr): drives rd_clr
    function RCLR   (NPADS : natural) return word_array is
        variable r : word_array(0 to NWORDS(NPADS) - 1) := (others => (others => '0'));
    begin
        -- The description declares none of these in this block.
        return r;
    end function RCLR;

    -- bits hardware drives (hw = w or rw): what hw_we / hw_set / hw_clr may touch
    function HWOWN  (NPADS : natural) return word_array is
        variable r : word_array(0 to NWORDS(NPADS) - 1) := (others => (others => '0'));
    begin
        -- PMXCAP: read-only capability, every bit a constant the hardware drives
        r(0) := bitRun(PMXREV_MSB, PMXNPADS_LSB);   -- PMXCAP
        -- PMXIN{k}: the synchronised pad levels, read-only, 32 bits per word
        for k in 0 to (NPADS + 31) / 32 - 1 loop
            r(1 + k) := bitRun(PMXPIN0_MSB, PMXPIN0_LSB);   -- PMXIN{k}
        end loop;
        return r;
    end function HWOWN;

end package body pinmux_regs_pkg;
