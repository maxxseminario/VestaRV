-- VestaRV: MUTEX_BANK register package
-- Hardware mutex bank: sixteen word-mapped advisory locks providing single-instruction cross-hart mutual exclusion
-- Generated from hdl/common/regs/rdl/mutex_bank.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.
-- Configuration-dependent: only what is common to (NMUTEX, MW, NHARTS) = (16, 3, 5), (32, 5, 18), (16, 2, 1) is emitted, the rest stays a generic in mutex_bank.vhd.

library ieee;
use ieee.std_logic_1164.all;

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

end package mutex_bank_regs_pkg;
