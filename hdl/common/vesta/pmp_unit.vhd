-- =============================================================================
-- pmp_unit.vhd  (P3: RISC-V physical memory protection, Smpmp)
-- =============================================================================
-- PURE COMBINATIONAL match / priority / permission decode for the PMP bank.
-- No clock, no reset, no state: the sixteen cfg bytes and sixteen 30-bit addresses arrive flattened from csr_unit, which owns the STORAGE, WARL and LOCK semantics.
-- This file answers exactly two questions per cycle, at the privilege each access is checked with: "may this fetch address be executed?" and "may this data address be read or written?".
--
-- Ports, generics and semantics are FROZEN by ~/vesta_docs/priv_arch/p0_specs.md 4.1.
-- The three-way split is:
--   csr_unit  : pmpcfg0-3 / pmpaddr0-15 storage, WARL and lock (Agent A)
--   pmp_unit  : THIS FILE, match, priority, permission (Agent A)
--   vesta     : the D5 strict-pre-issue check points, fault causes 1/5/7, and the "a denied access issues NO transaction" guarantee (Agent B).
--               vesta instantiates this unit inside `gen_pmp: if ENABLE_PMP generate` and ties both grants to '1' in the else branch, so an OFF build's netlist folds to today's.
--
-- DECODE RULES (p0_specs.md 4.1, spec-collapsed under this core's alignment):
--   * GRANULARITY. Every access this core makes is 4 bytes or fewer and never crosses a word boundary (loadext and store-lane construction), and every PMP region boundary is word-aligned (pmpaddr encodes address bits 31:2, and NA4 is the G=0 minimum).
--     The spec's byte-span rule therefore collapses to: an access matches iff its WORD ADDRESS (addr 31:2) lies in the region.
--   * A = OFF   : never matches.
--   * A = TOR   : matches when pmpaddr[i-1] <= a < pmpaddr[i], and entry 0's lower bound is 0.
--                 The LIVE pmpaddr[i-1] VALUE is used even when entry i-1 is OFF; by spec rule the predecessor's A field is irrelevant.
--                 An empty or inverted range (hi <= lo) matches nothing.
--   * A = NA4   : matches when a equals pmpaddr[i].
--   * A = NAPOT : mask taken from the LOWEST CLEAR BIT of pmpaddr[i], and an all-ones pmpaddr is the whole address space.
--   * PRIORITY  : the LOWEST-NUMBERED matching entry decides ALONE; a higher-numbered entry never rescues a denial and never revokes a grant.
--                 Negative control for this rule: priority inverted.
--   * MATCHED   : privilege M with L=0 grants unconditionally, but locked entries DO enforce on M, which is the whole point of L.
--                 Otherwise grant iff every needed permission bit is set.
--   * NO MATCH  : M grants, U denies, the spec rule once PMP is implemented.
--
-- The needed permissions are the caller's, not this file's policy:
--   fetch       needs X
--   plain load  needs R
--   plain store needs W
--   LR/SC/AMO   needs R and W together, the frozen 4 rule; vesta drives both
--
-- ENABLE_PMP = false: BOTH grants are constant '1' and vesta does not even instantiate the unit, so the OFF polarity is bit-identical to a pre-P3 chip.
-- PMP_ENTRIES < 16: entries at or above the count are never examined, and csr_unit also holds their storage at zero, so the fold is doubly safe.
--
-- Compile is -V200X: VHDL-93 only, no VHDL-2008 constructs anywhere.
--
-- Unit proof: xcelium/mp_test/run_pmp_unit.sh drives hdl/common/tb/pmp_unit_tb.vhd against this file alone, with no other DUT dependencies.
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.constants.all;

entity pmp_unit is
    generic (
        -- Mirrors the csr_unit / vesta generics of the same names.
        -- With ENABLE_PMP false every output folds to '1', granting everything.
        ENABLE_PMP  : boolean := false;
        -- Legal values are 8 and 16.
        -- Entries at or above the count never match, because csr_unit holds their storage at zero, i.e. A = OFF.
        PMP_ENTRIES : integer := 16
    );
    port (
        -- The bank, flattened by csr_unit:
        --   entry i cfg byte = pmp_cfg_flat(8*i+7  downto 8*i)
        --   entry i pmpaddr  = pmp_addr_flat(30*i+29 downto 30*i), physical address bits 31:2
        pmp_cfg_flat  : in  std_logic_vector(127 downto 0);
        pmp_addr_flat : in  std_logic_vector(479 downto 0);

        -- Fetch port: X permission at the CURRENT privilege (priv_mode).
        -- f_addr is the word-aligned address of the instruction-fetch bus transaction.
        -- A 32-bit instruction straddling two words is two separately checked fetches, which is vesta's concern and not this file's.
        f_addr        : in  std_logic_vector(31 downto 0);
        f_priv_m      : in  std_logic;
        f_grant       : out std_logic;

        -- Data port: R/W permission at the EFFECTIVE DATA privilege, csr_unit's data_priv_m.
        -- That privilege is mstatus.MPRV-redirected, so an M-mode access with MPRV=1 and MPP=U is checked as U.
        d_addr        : in  std_logic_vector(31 downto 0);
        d_priv_m      : in  std_logic;
        d_read        : in  std_logic;
        d_write       : in  std_logic;
        d_grant       : out std_logic
    );
end pmp_unit;

architecture behave of pmp_unit is

    constant PMP_MAX_ENTRIES : integer := 16;

    -- Word-address width: pmpaddr holds physical address bits 31:2.
    constant PMP_AW : integer := 30;

    subtype pmp_word_t is unsigned(PMP_AW-1 downto 0);

    constant PMP_WORD_ZERO : pmp_word_t := (others => '0');

    -- ----------------------------------------------------------------------
    -- Slice helpers, written as functions rather than inline slices so every piece of index arithmetic appears exactly once.
    -- An off-by-one in the flattening would silently shift the WHOLE bank and every match with it.
    -- ----------------------------------------------------------------------
    function cfg_of(flat : std_logic_vector(127 downto 0);
                    i    : integer) return std_logic_vector is
    begin
        return flat(8*i+7 downto 8*i);
    end function;

    function addr_of(flat : std_logic_vector(479 downto 0);
                     i    : integer) return pmp_word_t is
    begin
        return unsigned(flat(30*i+29 downto 30*i));
    end function;

    -- ----------------------------------------------------------------------
    -- NAPOT don't-care mask.
    -- pmpaddr has the form y..y 0 1..1 with the lowest CLEAR bit at position j, and the region compares bits above j while ignoring bits j downto 0.
    -- P xor (P+1) sets exactly bits j downto 0, because P+1 clears the low run of ones and sets bit j, so it IS the don't-care mask.
    -- For an all-ones P, P+1 wraps to 0 and P xor (P+1) is all ones, so nothing is compared and the region becomes the entire address space, exactly the frozen "all-ones is full span" rule.
    -- No special case is needed.
    -- ----------------------------------------------------------------------
    function napot_dontcare(p : pmp_word_t) return pmp_word_t is
    begin
        return p xor (p + 1);
    end function;

    -- ----------------------------------------------------------------------
    -- Does entry i match word address `a`?
    -- `lo` is the TOR lower bound the caller supplies: 0 for entry 0, otherwise the LIVE pmpaddr[i-1] regardless of entry i-1's A field.
    -- ----------------------------------------------------------------------
    function pmp_match(cfgv : std_logic_vector(7 downto 0);
                       hi   : pmp_word_t;
                       lo   : pmp_word_t;
                       a    : pmp_word_t) return boolean is
        variable dc : pmp_word_t;
    begin
        case cfgv(4 downto 3) is
            when PMP_A_TOR =>       -- Top of range: half-open interval from the predecessor's value.
                return (a >= lo) and (a < hi);
            when PMP_A_NA4 =>       -- Naturally aligned single word.
                return a = hi;
            when PMP_A_NAPOT =>     -- Power-of-two region: compare only the bits above the don't-care run.
                dc := napot_dontcare(hi);
                return ((a xor hi) and (not dc)) = PMP_WORD_ZERO;
            when others =>          -- PMP_A_OFF: a null region, never matches.
                return false;
        end case;
    end function;

    -- ----------------------------------------------------------------------
    -- THE check: walks entries 0 to PMP_ENTRIES-1 in order, stops at the FIRST match so the lowest-numbered entry decides alone, and applies the permission rule.
    -- With no match at all, M grants and U denies.
    -- ----------------------------------------------------------------------
    function pmp_check(cfg_flat  : std_logic_vector(127 downto 0);
                       addr_flat : std_logic_vector(479 downto 0);
                       byte_addr : std_logic_vector(31 downto 0);
                       priv_m    : std_logic;
                       need_r    : std_logic;
                       need_w    : std_logic;
                       need_x    : std_logic;
                       entries   : integer) return std_logic is
        variable a       : pmp_word_t;
        variable lo      : pmp_word_t;
        variable hi      : pmp_word_t;
        variable cfgv    : std_logic_vector(7 downto 0);
        variable hit     : boolean;
        variable hit_cfg : std_logic_vector(7 downto 0);
        variable g       : std_logic;
    begin
        a       := unsigned(byte_addr(31 downto 2));
        hit     := false;
        hit_cfg := (others => '0');

        for i in 0 to PMP_MAX_ENTRIES-1 loop
            if i < entries and not hit then
                cfgv := cfg_of(cfg_flat, i);
                hi   := addr_of(addr_flat, i);
                if i = 0 then
                    lo := PMP_WORD_ZERO;                 -- Entry 0's TOR base is 0.
                else
                    lo := addr_of(addr_flat, i-1);       -- LIVE predecessor value.
                end if;
                if pmp_match(cfgv, hi, lo, a) then
                    hit     := true;
                    hit_cfg := cfgv;
                end if;
            end if;
        end loop;

        if not hit then
            -- No matching entry: M-mode is unrestricted, U-mode faults.
            return priv_m;
        end if;

        -- Matched: an UNLOCKED entry does not constrain M-mode at all, while a LOCKED entry enforces its R/W/X on M exactly as it does on U.
        if priv_m = '1' and hit_cfg(7) = '0' then
            return '1';
        end if;

        -- Grant only if every permission the caller asked for is present in the matching entry.
        g := '1';
        if need_r = '1' and hit_cfg(0) = '0' then g := '0'; end if;
        if need_w = '1' and hit_cfg(1) = '0' then g := '0'; end if;
        if need_x = '1' and hit_cfg(2) = '0' then g := '0'; end if;
        return g;
    end function;

begin

    -- Fetch: X permission at priv_mode.
    -- With ENABLE_PMP false the condition is generic-static, so the whole comparator tree constant-folds away.
    f_grant <= '1' when not ENABLE_PMP else
               pmp_check(pmp_cfg_flat, pmp_addr_flat, f_addr, f_priv_m,
                         '0', '0', '1', PMP_ENTRIES);

    -- Data: R and/or W at the effective data privilege.
    -- vesta drives d_read = d_write = '1' for LR/SC/AMO, the frozen R-and-W rule.
    d_grant <= '1' when not ENABLE_PMP else
               pmp_check(pmp_cfg_flat, pmp_addr_flat, d_addr, d_priv_m,
                         d_read, d_write, '0', PMP_ENTRIES);

end behave;
