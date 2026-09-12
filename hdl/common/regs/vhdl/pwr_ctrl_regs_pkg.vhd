-- VestaRV: PWR_CTRL register package
-- Power controller for the switchable hart-tile power domains (M17 MTCMOS cold-gating)
-- Generated from hdl/common/regs/rdl/pwr_ctrl.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.
-- Configuration-dependent: only what is common to NHARTS 1, 5, 8, 9, 18, 32 (the PWRSR word count is ceil(NHARTS/8)) is emitted, the rest stays a generic in pwr_ctrl.vhd.

library ieee;
use ieee.std_logic_1164.all;
library work;
use work.constants.all;

package pwr_ctrl_regs_pkg is

    -- PWRCR: Power gate control
    constant PWRCR_WORD               : natural := 0;
    constant PWRCR_ADDR               : natural := 0;
    constant PWRCR_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PWRH0_MSB                : natural := 0;
    constant PWRH0_LSB                : natural := 0;
    constant PWRH0_RESET              : std_logic_vector(0 downto 0) := "0";

    -- PWRSR: Power sequencer state, one read-only nibble per hart (bits 4h+3:4h)
    constant PWRST0_MSB               : natural := 3;
    constant PWRST0_LSB               : natural := 0;
    constant PWRST0_RESET             : std_logic_vector(3 downto 0) := "0000";

    -- PWRWAKE: Boot gate and wake source control
    constant PWRWAKE_WORD             : natural := 5;
    constant PWRWAKE_ADDR             : natural := 20;
    constant PWRWAKE_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PWRWAKE_IMPL             : std_logic_vector(31 downto 0) := "00000000000000000000000000011111";
    constant PWREHOLD_MSB             : natural := 4;
    constant PWREHOLD_LSB             : natural := 4;
    constant PWREHOLD_RESET           : std_logic_vector(0 downto 0) := "0";
    constant PWSWRLS_MSB              : natural := 3;
    constant PWSWRLS_LSB              : natural := 3;
    constant PWSWRLS_RESET            : std_logic_vector(0 downto 0) := "0";
    constant PWRLSFIELD_MSB           : natural := 2;
    constant PWRLSFIELD_LSB           : natural := 2;
    constant PWRLSFIELD_RESET         : std_logic_vector(0 downto 0) := "0";
    constant PWRLSPGOOD_MSB           : natural := 1;
    constant PWRLSPGOOD_LSB           : natural := 1;
    constant PWRLSPGOOD_RESET         : std_logic_vector(0 downto 0) := "0";
    constant PWGATEEN_MSB             : natural := 0;
    constant PWGATEEN_LSB             : natural := 0;
    constant PWGATEEN_RESET           : std_logic_vector(0 downto 0) := "0";

    -- PWRSTS: Boot gate and wake source status, read only: the synchronized live pad levels, the one-shot strap sample that selects the harvested-boot branch of the boot ROM, and the gate state
    constant PWRSTS_WORD              : natural := 6;
    constant PWRSTS_ADDR              : natural := 24;
    constant PWRSTS_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PWRSTS_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PWRRLSLATCH_MSB          : natural := 5;
    constant PWRRLSLATCH_LSB          : natural := 5;
    constant PWRRLSLATCH_RESET        : std_logic_vector(0 downto 0) := "0";
    constant PWBOOTHOLD_MSB           : natural := 4;
    constant PWBOOTHOLD_LSB           : natural := 4;
    constant PWBOOTHOLD_RESET         : std_logic_vector(0 downto 0) := "0";
    constant PWSTRAPVLD_MSB           : natural := 3;
    constant PWSTRAPVLD_LSB           : natural := 3;
    constant PWSTRAPVLD_RESET         : std_logic_vector(0 downto 0) := "0";
    constant PWSTRAP_MSB              : natural := 2;
    constant PWSTRAP_LSB              : natural := 2;
    constant PWSTRAP_RESET            : std_logic_vector(0 downto 0) := "0";
    constant PWFIELDLIV_MSB           : natural := 1;
    constant PWFIELDLIV_LSB           : natural := 1;
    constant PWFIELDLIV_RESET         : std_logic_vector(0 downto 0) := "0";
    constant PWPGOODLIV_MSB           : natural := 0;
    constant PWPGOODLIV_LSB           : natural := 0;
    constant PWPGOODLIV_RESET         : std_logic_vector(0 downto 0) := "0";

    -- TASKWKM: Event-fabric task-wake mask, one bit per gateable tile hart
    constant TASKWKM_WORD             : natural := 7;
    constant TASKWKM_ADDR             : natural := 28;
    constant TASKWKM_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- pwr_ctrl.vhd's own decode identifiers: the word each register is
    -- decoded at, spelled the way that file already spells it, so adopting this
    -- package is a context clause plus a deletion and no assignment moves.
    constant W_PWRWAKE                : natural := 5;
    constant W_PWRSTS                 : natural := 6;
    constant W_TASKWKM                : natural := 7;

    -- periph_regs tables (hdl/common/periph_regs.vhd), built AT ELABORATION from
    -- this block's own generics: the register set is a function of the
    -- configuration, so the rows are a function and not a constant aggregate.
    -- Layout: eight words at every hart count; only the per-hart masks move.
    -- The entity passes NWORDS(NHARTS) and each table below straight
    -- into its periph_regs generic map. RDTHRU, WIDEWR, FULLWR and STROBE_HOLD
    -- are the entity's own; hdl/common/regs/REGFILE.md says why.
    function NWORDS (NHARTS : natural) return natural;
    -- reset word, loaded on the asynchronous resetn
    function RSTVAL (NHARTS : natural) return word_array;
    -- bits that hold a software-written flop; periph_regs stores exactly these
    function IMPL   (NHARTS : natural) return word_array;
    -- a written 1 clears (onwrite = woclr): drives w1c_hit
    function W1C    (NHARTS : natural) return word_array;
    -- a written 1 sets (onwrite = woset): drives woset_hit
    function WOSET  (NHARTS : natural) return word_array;
    -- a written 1 toggles (onwrite = wot): drives wot_hit
    function WOT    (NHARTS : natural) return word_array;
    -- self-clearing strobe (singlepulse): drives wr_pulse, stores nothing
    function PULSE  (NHARTS : natural) return word_array;
    -- a read retires (onread = rclr): drives rd_clr
    function RCLR   (NHARTS : natural) return word_array;
    -- bits hardware drives (hw = w or rw): what hw_we / hw_set / hw_clr may touch
    function HWOWN  (NHARTS : natural) return word_array;

end package pwr_ctrl_regs_pkg;


library ieee;
use ieee.std_logic_1164.all;
library work;
use work.constants.all;

package body pwr_ctrl_regs_pkg is

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

    function NWORDS (NHARTS : natural) return natural is
    begin
        return 8;
    end function NWORDS;

    -- reset word, loaded on the asynchronous resetn
    function RSTVAL (NHARTS : natural) return word_array is
        variable r : word_array(0 to NWORDS(NHARTS) - 1) := (others => (others => '0'));
    begin
        -- PWRCR: one gate bit per tile hart, and hart 0 always-on at bit 0
        r(0) := PWRCR_RESET;   -- PWRCR
        -- PWRWAKE: the boot-gate and wake-source control, at a fixed word
        r(PWRWAKE_WORD) := PWRWAKE_RESET;   -- PWRWAKE
        -- PWRSTS: read-only pad and gate status, every bit hardware driven
        r(PWRSTS_WORD) := PWRSTS_RESET;   -- PWRSTS
        -- TASKWKM: the event-fabric task-wake mask, PWRCR bit for bit
        r(TASKWKM_WORD) := TASKWKM_RESET;   -- TASKWKM
        return r;
    end function RSTVAL;

    -- bits that hold a software-written flop; periph_regs stores exactly these
    function IMPL   (NHARTS : natural) return word_array is
        variable r : word_array(0 to NWORDS(NHARTS) - 1) := (others => (others => '0'));
    begin
        -- PWRCR: one gate bit per tile hart, and hart 0 always-on at bit 0
        r(0) := bitRun(NHARTS-1, 1);   -- PWRCR
        -- PWRWAKE: the boot-gate and wake-source control, at a fixed word
        r(PWRWAKE_WORD) := PWRWAKE_IMPL;   -- PWRWAKE
        -- PWRSTS: read-only pad and gate status, every bit hardware driven
        r(PWRSTS_WORD) := PWRSTS_IMPL;   -- PWRSTS
        -- TASKWKM: the event-fabric task-wake mask, PWRCR bit for bit
        r(TASKWKM_WORD) := bitRun(NHARTS-1, 1);   -- TASKWKM
        return r;
    end function IMPL;

    -- a written 1 clears (onwrite = woclr): drives w1c_hit
    function W1C    (NHARTS : natural) return word_array is
        variable r : word_array(0 to NWORDS(NHARTS) - 1) := (others => (others => '0'));
    begin
        -- The description declares none of these in this block.
        return r;
    end function W1C;

    -- a written 1 sets (onwrite = woset): drives woset_hit
    function WOSET  (NHARTS : natural) return word_array is
        variable r : word_array(0 to NWORDS(NHARTS) - 1) := (others => (others => '0'));
    begin
        -- The description declares none of these in this block.
        return r;
    end function WOSET;

    -- a written 1 toggles (onwrite = wot): drives wot_hit
    function WOT    (NHARTS : natural) return word_array is
        variable r : word_array(0 to NWORDS(NHARTS) - 1) := (others => (others => '0'));
    begin
        -- The description declares none of these in this block.
        return r;
    end function WOT;

    -- self-clearing strobe (singlepulse): drives wr_pulse, stores nothing
    function PULSE  (NHARTS : natural) return word_array is
        variable r : word_array(0 to NWORDS(NHARTS) - 1) := (others => (others => '0'));
    begin
        -- The description declares none of these in this block.
        return r;
    end function PULSE;

    -- a read retires (onread = rclr): drives rd_clr
    function RCLR   (NHARTS : natural) return word_array is
        variable r : word_array(0 to NWORDS(NHARTS) - 1) := (others => (others => '0'));
    begin
        -- The description declares none of these in this block.
        return r;
    end function RCLR;

    -- bits hardware drives (hw = w or rw): what hw_we / hw_set / hw_clr may touch
    function HWOWN  (NHARTS : natural) return word_array is
        variable r : word_array(0 to NWORDS(NHARTS) - 1) := (others => (others => '0'));
    begin
        -- PWRCR: one gate bit per tile hart, and hart 0 always-on at bit 0
        r(0) := bitRun(NHARTS-1, 1) or bitRun(PWRH0_MSB, PWRH0_LSB);   -- PWRCR
        -- PWRSR: ceil(NHARTS/8) read-only words of one 4-bit state nibble per hart
        for k in 0 to (NHARTS + 7) / 8 - 1 loop
            r(1 + k) := bitRun(4*(NHARTS - 8*k) - 1, 0);   -- PWRSR{k}
        end loop;
        -- PWRSTS: read-only pad and gate status, every bit hardware driven
        r(PWRSTS_WORD) := bitRun(PWRRLSLATCH_MSB, PWPGOODLIV_LSB);   -- PWRSTS
        return r;
    end function HWOWN;

end package body pwr_ctrl_regs_pkg;
