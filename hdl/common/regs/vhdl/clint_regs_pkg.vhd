-- VestaRV: CLINT register package
-- Core-local interruptor for the five harts
-- Generated from hdl/common/regs/rdl/clint.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.
-- Configuration-dependent: only what is common to NHARTS 1, 4, 5, 18, 32 (MTIME_W = ceil(4*NHARTS/16)*4, CMP_W = MTIME_W + 4) is emitted, the rest stays a generic in clint.vhd.

library ieee;
use ieee.std_logic_1164.all;
library work;
use work.constants.all;

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

    -- periph_regs tables (hdl/common/periph_regs.vhd), built AT ELABORATION from
    -- this block's own generics: the register set is a function of the
    -- configuration, so the rows are a function and not a constant aggregate.
    -- Layout: MSIP[NHARTS] at word 0, mtime at MTIME_W, mtimecmp[NHARTS] at CMP_W.
    -- The entity passes NWORDS(NHARTS, MTIME_W, CMP_W) and each table below straight
    -- into its periph_regs generic map. RDTHRU, WIDEWR, FULLWR and STROBE_HOLD
    -- are the entity's own; hdl/common/regs/REGFILE.md says why.
    function NWORDS (NHARTS, MTIME_W, CMP_W : natural) return natural;
    -- reset word, loaded on the asynchronous resetn
    function RSTVAL (NHARTS, MTIME_W, CMP_W : natural) return word_array;
    -- bits that hold a software-written flop; periph_regs stores exactly these
    function IMPL   (NHARTS, MTIME_W, CMP_W : natural) return word_array;
    -- a written 1 clears (onwrite = woclr): drives w1c_hit
    function W1C    (NHARTS, MTIME_W, CMP_W : natural) return word_array;
    -- a written 1 sets (onwrite = woset): drives woset_hit
    function WOSET  (NHARTS, MTIME_W, CMP_W : natural) return word_array;
    -- a written 1 toggles (onwrite = wot): drives wot_hit
    function WOT    (NHARTS, MTIME_W, CMP_W : natural) return word_array;
    -- self-clearing strobe (singlepulse): drives wr_pulse, stores nothing
    function PULSE  (NHARTS, MTIME_W, CMP_W : natural) return word_array;
    -- a read retires (onread = rclr): drives rd_clr
    function RCLR   (NHARTS, MTIME_W, CMP_W : natural) return word_array;
    -- bits hardware drives (hw = w or rw): what hw_we / hw_set / hw_clr may touch
    function HWOWN  (NHARTS, MTIME_W, CMP_W : natural) return word_array;

end package clint_regs_pkg;


library ieee;
use ieee.std_logic_1164.all;
library work;
use work.constants.all;

package body clint_regs_pkg is

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

    function NWORDS (NHARTS, MTIME_W, CMP_W : natural) return natural is
    begin
        return CMP_W + 2*NHARTS;
    end function NWORDS;

    -- reset word, loaded on the asynchronous resetn
    function RSTVAL (NHARTS, MTIME_W, CMP_W : natural) return word_array is
        variable r : word_array(0 to NWORDS(NHARTS, MTIME_W, CMP_W) - 1) := (others => (others => '0'));
    begin
        -- MSIP{h}: one word per hart, bit 0 only
        for k in 0 to NHARTS - 1 loop
            r(0 + k) := MSIP0_RESET;   -- MSIP{h}
        end loop;
        -- mtime, a free-running counter both halves of which hardware drives
        r(MTIME_W) := MTIMEL_RESET;   -- MTIMEL
        r(MTIME_W + 1) := MTIMEH_RESET;   -- MTIMEH
        -- mtimecmp{h}, lo then hi on an 8-byte stride; resets all-ones
        for k in 0 to NHARTS - 1 loop
            r(CMP_W + 2*k) := MTIMECMP0L_RESET;   -- MTIMECMP{h}L
            r(CMP_W + 2*k + 1) := MTIMECMP0H_RESET;   -- MTIMECMP{h}H
        end loop;
        return r;
    end function RSTVAL;

    -- bits that hold a software-written flop; periph_regs stores exactly these
    function IMPL   (NHARTS, MTIME_W, CMP_W : natural) return word_array is
        variable r : word_array(0 to NWORDS(NHARTS, MTIME_W, CMP_W) - 1) := (others => (others => '0'));
    begin
        -- MSIP{h}: one word per hart, bit 0 only
        for k in 0 to NHARTS - 1 loop
            r(0 + k) := MSIP0_IMPL;   -- MSIP{h}
        end loop;
        -- mtime, a free-running counter both halves of which hardware drives
        r(MTIME_W) := MTIMEL_IMPL;   -- MTIMEL
        r(MTIME_W + 1) := MTIMEH_IMPL;   -- MTIMEH
        -- mtimecmp{h}, lo then hi on an 8-byte stride; resets all-ones
        for k in 0 to NHARTS - 1 loop
            r(CMP_W + 2*k) := MTIMECMP0L_IMPL;   -- MTIMECMP{h}L
            r(CMP_W + 2*k + 1) := MTIMECMP0H_IMPL;   -- MTIMECMP{h}H
        end loop;
        return r;
    end function IMPL;

    -- a written 1 clears (onwrite = woclr): drives w1c_hit
    function W1C    (NHARTS, MTIME_W, CMP_W : natural) return word_array is
        variable r : word_array(0 to NWORDS(NHARTS, MTIME_W, CMP_W) - 1) := (others => (others => '0'));
    begin
        -- The description declares none of these in this block.
        return r;
    end function W1C;

    -- a written 1 sets (onwrite = woset): drives woset_hit
    function WOSET  (NHARTS, MTIME_W, CMP_W : natural) return word_array is
        variable r : word_array(0 to NWORDS(NHARTS, MTIME_W, CMP_W) - 1) := (others => (others => '0'));
    begin
        -- The description declares none of these in this block.
        return r;
    end function WOSET;

    -- a written 1 toggles (onwrite = wot): drives wot_hit
    function WOT    (NHARTS, MTIME_W, CMP_W : natural) return word_array is
        variable r : word_array(0 to NWORDS(NHARTS, MTIME_W, CMP_W) - 1) := (others => (others => '0'));
    begin
        -- The description declares none of these in this block.
        return r;
    end function WOT;

    -- self-clearing strobe (singlepulse): drives wr_pulse, stores nothing
    function PULSE  (NHARTS, MTIME_W, CMP_W : natural) return word_array is
        variable r : word_array(0 to NWORDS(NHARTS, MTIME_W, CMP_W) - 1) := (others => (others => '0'));
    begin
        -- The description declares none of these in this block.
        return r;
    end function PULSE;

    -- a read retires (onread = rclr): drives rd_clr
    function RCLR   (NHARTS, MTIME_W, CMP_W : natural) return word_array is
        variable r : word_array(0 to NWORDS(NHARTS, MTIME_W, CMP_W) - 1) := (others => (others => '0'));
    begin
        -- The description declares none of these in this block.
        return r;
    end function RCLR;

    -- bits hardware drives (hw = w or rw): what hw_we / hw_set / hw_clr may touch
    function HWOWN  (NHARTS, MTIME_W, CMP_W : natural) return word_array is
        variable r : word_array(0 to NWORDS(NHARTS, MTIME_W, CMP_W) - 1) := (others => (others => '0'));
    begin
        -- mtime, a free-running counter both halves of which hardware drives
        r(MTIME_W) := MTIMEL_IMPL;   -- MTIMEL
        r(MTIME_W + 1) := MTIMEH_IMPL;   -- MTIMEH
        return r;
    end function HWOWN;

end package body clint_regs_pkg;
