-- =============================================================================
-- fpu_simple.vhd  (X4 Zfinx, Stage 2a)
-- =============================================================================
-- PURE-COMBINATIONAL single-cycle FP block (gatekeeper correction C2).
-- Ops (fp_s_op[3:0], correction C3):
--   0 FSGNJ  1 FSGNJN  2 FSGNJX  3 FEQ  4 FLT  5 FLE  6 FMIN  7 FMAX  8 FCLASS
--
-- Fed LIVE rd1/rd2 in EXECUTE and consumed the same cycle, before writeback.
-- Sets no flags for fsgnj* and fclass; NV only for feq(sNaN), flt and fle (any NaN), and fmin and fmax (sNaN).
-- All single-precision, no NaN-boxing (RV32 plus single precision fills the whole register).
-- Compile is -V200X, so no VHDL-2008.
-- Stage 3 unifies the op constants into constants.vhd; they are declared locally here and the VALUES must stay the same.
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

    -- One combinational block: unpack and classify both operands, then select the result for the requested op.
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
        -- Split both operands into sign, biased exponent and mantissa.
        a := fp_s_a;  b := fp_s_b;
        sa := a(31); sb := b(31);
        ea := unsigned(a(30 downto 23)); ma := unsigned(a(22 downto 0));
        eb := unsigned(b(30 downto 23)); mb := unsigned(b(22 downto 0));

        -- Classify operand A: an all-ones exponent is inf or NaN, and a clear mantissa MSB makes a NaN signalling.
        a_zero := (ea = 0)   and (ma = 0);
        a_sub  := (ea = 0)   and (ma /= 0);
        a_inf  := (ea = 255) and (ma = 0);
        a_nan  := (ea = 255) and (ma /= 0);
        a_snan := a_nan and (a(22) = '0');

        -- Same classification for operand B.
        b_zero := (eb = 0)   and (mb = 0);
        b_sub  := (eb = 0)   and (mb /= 0);
        b_inf  := (eb = 255) and (mb = 0);
        b_nan  := (eb = 255) and (mb /= 0);
        b_snan := b_nan and (b(22) = '0');

        -- Magnitudes drive the ordered compare, and +0 must compare equal to -0.
        maga := unsigned(a(30 downto 0));
        magb := unsigned(b(30 downto 0));
        both_zero := a_zero and b_zero;
        num_eq := (a = b) or both_zero;

        -- Ordered less-than, valid only when neither operand is NaN.
        if sa = '1' and sb = '0' then
            a_lt := not both_zero;      -- a negative is below a positive unless both are zero
        elsif sa = '0' and sb = '1' then
            a_lt := false;              -- a positive is never below a negative
        elsif sa = '0' and sb = '0' then
            a_lt := maga < magb;        -- both positive: magnitude order is the value order
        else                            -- both negative: magnitude order is reversed
            a_lt := maga > magb;
        end if;

        -- Default result and flags, overridden by the op selected below.
        res   := (others => '0');
        flags := (others => '0');

        case fp_s_op is
            -- Sign injection: keep A's magnitude, take the sign from B.
            when OPS_FSGNJ =>
                res := b(31) & a(30 downto 0);
            -- Sign injection, negated: take the inverse of B's sign.
            when OPS_FSGNJN =>
                res := (not b(31)) & a(30 downto 0);
            -- Sign injection, xor: the two signs combine.
            when OPS_FSGNJX =>
                res := (a(31) xor b(31)) & a(30 downto 0);

            -- Quiet compare: NaN operands compare false, and only a signalling NaN raises NV.
            when OPS_FEQ =>
                if a_nan or b_nan then
                    res := (others => '0');
                    if a_snan or b_snan then flags(4) := '1'; end if;   -- NV
                elsif num_eq then
                    res := (0 => '1', others => '0');
                end if;

            -- Signalling compare: any NaN operand raises NV.
            when OPS_FLT =>
                if a_nan or b_nan then
                    res := (others => '0'); flags(4) := '1';            -- NV on any NaN
                elsif a_lt then
                    res := (0 => '1', others => '0');
                end if;

            -- Signalling compare: any NaN operand raises NV.
            when OPS_FLE =>
                if a_nan or b_nan then
                    res := (others => '0'); flags(4) := '1';            -- NV on any NaN
                elsif a_lt or num_eq then
                    res := (0 => '1', others => '0');
                end if;

            -- Minimum: one NaN operand is ignored, two give qNaN, and only a signalling NaN raises NV.
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

            -- Maximum: same NaN handling as fmin, with the opposite pick.
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

            -- Classify operand A into the ten-bit one-hot class mask, sets no flags.
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

            -- Unused encodings return zero with no flags.
            when others =>
                res := (others => '0');
        end case;

        fp_s_result <= res;
        fp_s_flags  <= flags;
    end process;

end rtl;
