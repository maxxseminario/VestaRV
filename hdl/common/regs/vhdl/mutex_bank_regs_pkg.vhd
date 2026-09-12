-- VestaRV: MUTEX_BANK register package
-- Hardware mutex bank: sixteen word-mapped advisory locks providing single-instruction cross-hart mutual exclusion
-- Generated from hdl/common/regs/rdl/mutex_bank.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.
-- Configuration-dependent: only what is common to (NMUTEX, MW, NHARTS) = (16, 3, 5), (32, 5, 18), (16, 2, 1) is emitted, the rest stays a generic in mutex_bank.vhd.

library ieee;
use ieee.std_logic_1164.all;
library work;
use work.constants.all;

package mutex_bank_regs_pkg is

    -- MUTEX0: Hardware mutex 0. Read to claim: a returned value of 0 means the mutex was free and the reading hart now holds it; a nonzero value is the current owner's marker (hartid+1)
    constant MUTEX0_WORD              : natural := 0;
    constant MUTEX0_ADDR              : natural := 0;
    constant MUTEX0_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant MTXOWN0_LSB              : natural := 0;

    -- MUTEX1: Hardware mutex 1. Read to claim: a returned value of 0 means the mutex was free and the reading hart now holds it; a nonzero value is the current owner's marker (hartid+1)
    constant MUTEX1_WORD              : natural := 1;
    constant MUTEX1_ADDR              : natural := 4;
    constant MUTEX1_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant MTXOWN1_LSB              : natural := 0;

    -- MUTEX2: Hardware mutex 2. Read to claim: a returned value of 0 means the mutex was free and the reading hart now holds it; a nonzero value is the current owner's marker (hartid+1)
    constant MUTEX2_WORD              : natural := 2;
    constant MUTEX2_ADDR              : natural := 8;
    constant MUTEX2_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant MTXOWN2_LSB              : natural := 0;

    -- MUTEX3: Hardware mutex 3. Read to claim: a returned value of 0 means the mutex was free and the reading hart now holds it; a nonzero value is the current owner's marker (hartid+1)
    constant MUTEX3_WORD              : natural := 3;
    constant MUTEX3_ADDR              : natural := 12;
    constant MUTEX3_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant MTXOWN3_LSB              : natural := 0;

    -- MUTEX4: Hardware mutex 4. Read to claim: a returned value of 0 means the mutex was free and the reading hart now holds it; a nonzero value is the current owner's marker (hartid+1)
    constant MUTEX4_WORD              : natural := 4;
    constant MUTEX4_ADDR              : natural := 16;
    constant MUTEX4_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant MTXOWN4_LSB              : natural := 0;

    -- MUTEX5: Hardware mutex 5. Read to claim: a returned value of 0 means the mutex was free and the reading hart now holds it; a nonzero value is the current owner's marker (hartid+1)
    constant MUTEX5_WORD              : natural := 5;
    constant MUTEX5_ADDR              : natural := 20;
    constant MUTEX5_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant MTXOWN5_LSB              : natural := 0;

    -- MUTEX6: Hardware mutex 6. Read to claim: a returned value of 0 means the mutex was free and the reading hart now holds it; a nonzero value is the current owner's marker (hartid+1)
    constant MUTEX6_WORD              : natural := 6;
    constant MUTEX6_ADDR              : natural := 24;
    constant MUTEX6_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant MTXOWN6_LSB              : natural := 0;

    -- MUTEX7: Hardware mutex 7. Read to claim: a returned value of 0 means the mutex was free and the reading hart now holds it; a nonzero value is the current owner's marker (hartid+1)
    constant MUTEX7_WORD              : natural := 7;
    constant MUTEX7_ADDR              : natural := 28;
    constant MUTEX7_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant MTXOWN7_LSB              : natural := 0;

    -- MUTEX8: Hardware mutex 8. Read to claim: a returned value of 0 means the mutex was free and the reading hart now holds it; a nonzero value is the current owner's marker (hartid+1)
    constant MUTEX8_WORD              : natural := 8;
    constant MUTEX8_ADDR              : natural := 32;
    constant MUTEX8_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant MTXOWN8_LSB              : natural := 0;

    -- MUTEX9: Hardware mutex 9. Read to claim: a returned value of 0 means the mutex was free and the reading hart now holds it; a nonzero value is the current owner's marker (hartid+1)
    constant MUTEX9_WORD              : natural := 9;
    constant MUTEX9_ADDR              : natural := 36;
    constant MUTEX9_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant MTXOWN9_LSB              : natural := 0;

    -- MUTEX10: Hardware mutex 10. Read to claim: a returned value of 0 means the mutex was free and the reading hart now holds it; a nonzero value is the current owner's marker (hartid+1)
    constant MUTEX10_WORD             : natural := 10;
    constant MUTEX10_ADDR             : natural := 40;
    constant MUTEX10_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant MTXOWN10_LSB             : natural := 0;

    -- MUTEX11: Hardware mutex 11. Read to claim: a returned value of 0 means the mutex was free and the reading hart now holds it; a nonzero value is the current owner's marker (hartid+1)
    constant MUTEX11_WORD             : natural := 11;
    constant MUTEX11_ADDR             : natural := 44;
    constant MUTEX11_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant MTXOWN11_LSB             : natural := 0;

    -- MUTEX12: Hardware mutex 12. Read to claim: a returned value of 0 means the mutex was free and the reading hart now holds it; a nonzero value is the current owner's marker (hartid+1)
    constant MUTEX12_WORD             : natural := 12;
    constant MUTEX12_ADDR             : natural := 48;
    constant MUTEX12_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant MTXOWN12_LSB             : natural := 0;

    -- MUTEX13: Hardware mutex 13. Read to claim: a returned value of 0 means the mutex was free and the reading hart now holds it; a nonzero value is the current owner's marker (hartid+1)
    constant MUTEX13_WORD             : natural := 13;
    constant MUTEX13_ADDR             : natural := 52;
    constant MUTEX13_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant MTXOWN13_LSB             : natural := 0;

    -- MUTEX14: Hardware mutex 14. Read to claim: a returned value of 0 means the mutex was free and the reading hart now holds it; a nonzero value is the current owner's marker (hartid+1)
    constant MUTEX14_WORD             : natural := 14;
    constant MUTEX14_ADDR             : natural := 56;
    constant MUTEX14_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant MTXOWN14_LSB             : natural := 0;

    -- MUTEX15: Hardware mutex 15. Read to claim: a returned value of 0 means the mutex was free and the reading hart now holds it; a nonzero value is the current owner's marker (hartid+1)
    constant MUTEX15_WORD             : natural := 15;
    constant MUTEX15_ADDR             : natural := 60;
    constant MUTEX15_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant MTXOWN15_LSB             : natural := 0;

    -- periph_regs tables (hdl/common/periph_regs.vhd), built AT ELABORATION from
    -- this block's own generics: the register set is a function of the
    -- configuration, so the rows are a function and not a constant aggregate.
    -- Layout: NMUTEX identical owner words, the owner field MW downto MTXOWN0_LSB.
    -- The entity passes NWORDS(NMUTEX, MW) and each table below straight
    -- into its periph_regs generic map. RDTHRU, WIDEWR, FULLWR and STROBE_HOLD
    -- are the entity's own; hdl/common/regs/REGFILE.md says why.
    function NWORDS (NMUTEX, MW : natural) return natural;
    -- reset word, loaded on the asynchronous resetn
    function RSTVAL (NMUTEX, MW : natural) return word_array;
    -- bits that hold a software-written flop; periph_regs stores exactly these
    function IMPL   (NMUTEX, MW : natural) return word_array;
    -- a written 1 clears (onwrite = woclr): drives w1c_hit
    function W1C    (NMUTEX, MW : natural) return word_array;
    -- a written 1 sets (onwrite = woset): drives woset_hit
    function WOSET  (NMUTEX, MW : natural) return word_array;
    -- a written 1 toggles (onwrite = wot): drives wot_hit
    function WOT    (NMUTEX, MW : natural) return word_array;
    -- self-clearing strobe (singlepulse): drives wr_pulse, stores nothing
    function PULSE  (NMUTEX, MW : natural) return word_array;
    -- a read retires (onread = rclr): drives rd_clr
    function RCLR   (NMUTEX, MW : natural) return word_array;
    -- bits hardware drives (hw = w or rw): what hw_we / hw_set / hw_clr may touch
    function HWOWN  (NMUTEX, MW : natural) return word_array;

end package mutex_bank_regs_pkg;


library ieee;
use ieee.std_logic_1164.all;
library work;
use work.constants.all;

package body mutex_bank_regs_pkg is

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

    function NWORDS (NMUTEX, MW : natural) return natural is
    begin
        return NMUTEX;
    end function NWORDS;

    -- reset word, loaded on the asynchronous resetn
    function RSTVAL (NMUTEX, MW : natural) return word_array is
        variable r : word_array(0 to NWORDS(NMUTEX, MW) - 1) := (others => (others => '0'));
    begin
        -- MUTEX{i}: the owner marker, hardware written by the claim read
        for k in 0 to NMUTEX - 1 loop
            r(0 + k) := MUTEX0_RESET;   -- MUTEX{i}
        end loop;
        return r;
    end function RSTVAL;

    -- bits that hold a software-written flop; periph_regs stores exactly these
    function IMPL   (NMUTEX, MW : natural) return word_array is
        variable r : word_array(0 to NWORDS(NMUTEX, MW) - 1) := (others => (others => '0'));
    begin
        -- MUTEX{i}: the owner marker, hardware written by the claim read
        for k in 0 to NMUTEX - 1 loop
            r(0 + k) := bitRun(MW, MTXOWN0_LSB);   -- MUTEX{i}
        end loop;
        return r;
    end function IMPL;

    -- a written 1 clears (onwrite = woclr): drives w1c_hit
    function W1C    (NMUTEX, MW : natural) return word_array is
        variable r : word_array(0 to NWORDS(NMUTEX, MW) - 1) := (others => (others => '0'));
    begin
        -- The description declares none of these in this block.
        return r;
    end function W1C;

    -- a written 1 sets (onwrite = woset): drives woset_hit
    function WOSET  (NMUTEX, MW : natural) return word_array is
        variable r : word_array(0 to NWORDS(NMUTEX, MW) - 1) := (others => (others => '0'));
    begin
        -- The description declares none of these in this block.
        return r;
    end function WOSET;

    -- a written 1 toggles (onwrite = wot): drives wot_hit
    function WOT    (NMUTEX, MW : natural) return word_array is
        variable r : word_array(0 to NWORDS(NMUTEX, MW) - 1) := (others => (others => '0'));
    begin
        -- The description declares none of these in this block.
        return r;
    end function WOT;

    -- self-clearing strobe (singlepulse): drives wr_pulse, stores nothing
    function PULSE  (NMUTEX, MW : natural) return word_array is
        variable r : word_array(0 to NWORDS(NMUTEX, MW) - 1) := (others => (others => '0'));
    begin
        -- The description declares none of these in this block.
        return r;
    end function PULSE;

    -- a read retires (onread = rclr): drives rd_clr
    function RCLR   (NMUTEX, MW : natural) return word_array is
        variable r : word_array(0 to NWORDS(NMUTEX, MW) - 1) := (others => (others => '0'));
    begin
        -- The description declares none of these in this block.
        return r;
    end function RCLR;

    -- bits hardware drives (hw = w or rw): what hw_we / hw_set / hw_clr may touch
    function HWOWN  (NMUTEX, MW : natural) return word_array is
        variable r : word_array(0 to NWORDS(NMUTEX, MW) - 1) := (others => (others => '0'));
    begin
        -- MUTEX{i}: the owner marker, hardware written by the claim read
        for k in 0 to NMUTEX - 1 loop
            r(0 + k) := bitRun(MW, MTXOWN0_LSB);   -- MUTEX{i}
        end loop;
        return r;
    end function HWOWN;

end package body mutex_bank_regs_pkg;
