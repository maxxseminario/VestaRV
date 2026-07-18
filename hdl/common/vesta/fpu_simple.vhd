-- =============================================================================
-- fpu_simple.vhd  (X4 Zfinx, Stage 2a)
-- =============================================================================
-- PURE-COMBINATIONAL single-cycle FP block (gatekeeper correction C2).
-- Ops (fp_s_op[3:0], correction C3):
--   0 FSGNJ  1 FSGNJN  2 FSGNJX  3 FEQ  4 FLT  5 FLE  6 FMIN  7 FMAX  8 FCLASS
--
-- Fed LIVE rd1/rd2 in EXECUTE (consumed same-cycle pre-writeback). Sets no flags
-- for fsgnj*/fclass; NV only for feq(sNaN)/flt,fle(any NaN)/fmin,fmax(sNaN).
-- All single-precision, no NaN-boxing (RV32 + single fills the register).
-- Compile: -V200X (no VHDL-2008). Stage 3 unifies the op constants into
-- constants.vhd; declared locally here (same VALUES mandatory).
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity fpu_simple is
    port (
        fp_s_op     : in  std_logic_vector(3 downto 0);
        fp_s_a      : in  std_logic_vector(31 downto 0);
        fp_s_b      : in  std_logic_vector(31 downto 0);
        fp_s_result : out std_logic_vector(31 downto 0);
        fp_s_flags  : out std_logic_vector(4 downto 0)   -- {NV,DZ,OF,UF,NX}
    );
end entity;

architecture rtl of fpu_simple is
    constant OPS_FSGNJ  : std_logic_vector(3 downto 0) := "0000";
    constant OPS_FSGNJN : std_logic_vector(3 downto 0) := "0001";
    constant OPS_FSGNJX : std_logic_vector(3 downto 0) := "0010";
    constant OPS_FEQ    : std_logic_vector(3 downto 0) := "0011";
    constant OPS_FLT    : std_logic_vector(3 downto 0) := "0100";
    constant OPS_FLE    : std_logic_vector(3 downto 0) := "0101";
    constant OPS_FMIN   : std_logic_vector(3 downto 0) := "0110";
    constant OPS_FMAX   : std_logic_vector(3 downto 0) := "0111";
    constant OPS_FCLASS : std_logic_vector(3 downto 0) := "1000";

    constant QNAN  : std_logic_vector(31 downto 0) := x"7FC00000";
    constant PZERO : std_logic_vector(31 downto 0) := x"00000000";
    constant NZERO : std_logic_vector(31 downto 0) := x"80000000";
begin

    process(fp_s_op, fp_s_a, fp_s_b)
        variable a, b   : std_logic_vector(31 downto 0);
        variable sa, sb : std_logic;
        variable ea, eb : unsigned(7 downto 0);
        variable ma, mb : unsigned(22 downto 0);
        variable a_zero, a_sub, a_inf, a_nan, a_snan : boolean;
        variable b_zero, b_sub, b_inf, b_nan, b_snan : boolean;
        variable maga, magb : unsigned(30 downto 0);
        variable a_lt, num_eq, both_zero : boolean;
        variable res   : std_logic_vector(31 downto 0);
        variable flags : std_logic_vector(4 downto 0);
        variable cls   : std_logic_vector(9 downto 0);
    begin
        a := fp_s_a;  b := fp_s_b;
        sa := a(31); sb := b(31);
        ea := unsigned(a(30 downto 23)); ma := unsigned(a(22 downto 0));
        eb := unsigned(b(30 downto 23)); mb := unsigned(b(22 downto 0));

        a_zero := (ea = 0)   and (ma = 0);
        a_sub  := (ea = 0)   and (ma /= 0);
        a_inf  := (ea = 255) and (ma = 0);
        a_nan  := (ea = 255) and (ma /= 0);
        a_snan := a_nan and (a(22) = '0');

        b_zero := (eb = 0)   and (mb = 0);
        b_sub  := (eb = 0)   and (mb /= 0);
        b_inf  := (eb = 255) and (mb = 0);
        b_nan  := (eb = 255) and (mb /= 0);
        b_snan := b_nan and (b(22) = '0');

        maga := unsigned(a(30 downto 0));
        magb := unsigned(b(30 downto 0));
        both_zero := a_zero and b_zero;
        num_eq := (a = b) or both_zero;

        -- ordered less-than (valid only when neither is NaN)
        if sa = '1' and sb = '0' then
            a_lt := not both_zero;      -- negative < positive (unless both zero)
        elsif sa = '0' and sb = '1' then
            a_lt := false;
        elsif sa = '0' and sb = '0' then
            a_lt := maga < magb;
        else                            -- both negative
            a_lt := maga > magb;
        end if;

        res   := (others => '0');
        flags := (others => '0');

        case fp_s_op is
            when OPS_FSGNJ =>
                res := b(31) & a(30 downto 0);
            when OPS_FSGNJN =>
                res := (not b(31)) & a(30 downto 0);
            when OPS_FSGNJX =>
                res := (a(31) xor b(31)) & a(30 downto 0);

            when OPS_FEQ =>
                if a_nan or b_nan then
                    res := (others => '0');
                    if a_snan or b_snan then flags(4) := '1'; end if;   -- NV
                elsif num_eq then
                    res := (0 => '1', others => '0');
                end if;

            when OPS_FLT =>
                if a_nan or b_nan then
                    res := (others => '0'); flags(4) := '1';            -- NV any NaN
                elsif a_lt then
                    res := (0 => '1', others => '0');
                end if;

            when OPS_FLE =>
                if a_nan or b_nan then
                    res := (others => '0'); flags(4) := '1';            -- NV any NaN
                elsif a_lt or num_eq then
                    res := (0 => '1', others => '0');
                end if;

            when OPS_FMIN =>
                if a_nan and b_nan then
                    res := QNAN;
                    if a_snan or b_snan then flags(4) := '1'; end if;
                elsif a_nan then
                    res := b;
                    if a_snan then flags(4) := '1'; end if;
                elsif b_nan then
                    res := a;
                    if b_snan then flags(4) := '1'; end if;
                elsif both_zero and (sa /= sb) then
                    res := NZERO;                                       -- fmin(-0,+0) = -0
                elsif a_lt then
                    res := a;
                else
                    res := b;
                end if;

            when OPS_FMAX =>
                if a_nan and b_nan then
                    res := QNAN;
                    if a_snan or b_snan then flags(4) := '1'; end if;
                elsif a_nan then
                    res := b;
                    if a_snan then flags(4) := '1'; end if;
                elsif b_nan then
                    res := a;
                    if b_snan then flags(4) := '1'; end if;
                elsif both_zero and (sa /= sb) then
                    res := PZERO;                                       -- fmax(-0,+0) = +0
                elsif a_lt then
                    res := b;
                else
                    res := a;
                end if;

            when OPS_FCLASS =>
                cls := (others => '0');
                if a_inf and sa = '1' then cls(0) := '1'; end if;      -- -inf
                if (not a_zero) and (not a_sub) and (not a_inf) and (not a_nan) and sa = '1' then
                    cls(1) := '1';                                     -- -normal
                end if;
                if a_sub and sa = '1' then cls(2) := '1'; end if;      -- -subnormal
                if a_zero and sa = '1' then cls(3) := '1'; end if;     -- -0
                if a_zero and sa = '0' then cls(4) := '1'; end if;     -- +0
                if a_sub and sa = '0' then cls(5) := '1'; end if;      -- +subnormal
                if (not a_zero) and (not a_sub) and (not a_inf) and (not a_nan) and sa = '0' then
                    cls(6) := '1';                                     -- +normal
                end if;
                if a_inf and sa = '0' then cls(7) := '1'; end if;      -- +inf
                if a_snan then cls(8) := '1'; end if;                  -- sNaN
                if a_nan and (not a_snan) then cls(9) := '1'; end if;  -- qNaN
                res := (others => '0');
                res(9 downto 0) := cls;

            when others =>
                res := (others => '0');
        end case;

        fp_s_result <= res;
        fp_s_flags  <= flags;
    end process;

end rtl;
