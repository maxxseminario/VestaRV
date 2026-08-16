/* =============================================================================
   fpu.vhd: iterative multi-cycle single-precision (Zfinx) FPU
   =============================================================================
   A shared FMA backend (fadd/fsub/fmul, fmadd/fmsub/fnmsub/fnmadd), a radix-2 iterative div/sqrt engine and unpack-only fcvt all feed ONE normalize+round back-end doing a single rounding with G/R/S, all 5 modes, full subnormal support both ways, and UF = tininess-after-rounding AND NX.
     fp_op[3:0] : 0 FADD 1 FSUB 2 FMUL 3 FDIV 4 FSQRT 5 FMADD 6 FMSUB 7 FNMSUB 8 FNMADD 9 FCVT_W_S 10 FCVT_WU_S 11 FCVT_S_W 12 FCVT_S_WU
     rm[2:0]    : EFFECTIVE mode, dynamic already resolved and illegal never arriving: 000 RNE 001 RTZ 010 RDN 011 RUP 100 RMM;  fp_flags = {NV,DZ,OF,UF,NX}
   fp_a/fp_b/fp_c are latched at the start edge and the whole run consumes ONLY those copies, never a live port mid-run; fpu_done, result and flags hold until the next start.
   Registered stage boundaries unpack, product, align-add, normalize, round keep any combinational chain from running the whole length of the datapath; the FMA carries a full 48-bit product into a 128-bit aligner/accumulator and div/sqrt takes at most one radix-2 step per cycle.
   ============================================================================= */
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity fpu is
    port (
        clk       : in  std_logic;
        resetn    : in  std_logic;
        fpu_start : in  std_logic;
        fp_op     : in  std_logic_vector(3 downto 0);
        rm        : in  std_logic_vector(2 downto 0);
        fp_a      : in  std_logic_vector(31 downto 0);
        fp_b      : in  std_logic_vector(31 downto 0);
        fp_c      : in  std_logic_vector(31 downto 0);
        fpu_done  : out std_logic;
        fp_result : out std_logic_vector(31 downto 0);
        fp_flags  : out std_logic_vector(4 downto 0)   -- {NV,DZ,OF,UF,NX}
    );
end entity;

architecture rtl of fpu is

    -- ---------------------------- op encodings ------------------------------
    constant OP_FADD     : std_logic_vector(3 downto 0) := "0000";
    constant OP_FSUB     : std_logic_vector(3 downto 0) := "0001";
    constant OP_FMUL     : std_logic_vector(3 downto 0) := "0010";
    constant OP_FDIV     : std_logic_vector(3 downto 0) := "0011";
    constant OP_FSQRT    : std_logic_vector(3 downto 0) := "0100";
    constant OP_FMADD    : std_logic_vector(3 downto 0) := "0101";
    constant OP_FMSUB    : std_logic_vector(3 downto 0) := "0110";
    constant OP_FNMSUB   : std_logic_vector(3 downto 0) := "0111";
    constant OP_FNMADD   : std_logic_vector(3 downto 0) := "1000";
    constant OP_FCVT_W_S : std_logic_vector(3 downto 0) := "1001";
    constant OP_FCVT_WU_S: std_logic_vector(3 downto 0) := "1010";
    constant OP_FCVT_S_W : std_logic_vector(3 downto 0) := "1011";
    constant OP_FCVT_S_WU: std_logic_vector(3 downto 0) := "1100";

    constant QNAN : std_logic_vector(31 downto 0) := x"7FC00000";

    subtype  exp_t is integer range -8192 to 8192;

    -- unpacked / normalized operand: value = (mant/2^23) * 2^exp, with mant bit23=1 for nonzero finites and subnormals pre-normalized.
    -- The class flags are mutually exclusive.
    type unpacked_t is record
        sign    : std_logic;
        exp     : exp_t;
        mant    : unsigned(23 downto 0);
        is_zero : boolean;
        is_inf  : boolean;
        is_nan  : boolean;
        is_snan : boolean;
    end record;

    type round_out_t is record
        packed : std_logic_vector(31 downto 0);
        of_f   : std_logic;
        uf_f   : std_logic;
        nx_f   : std_logic;
    end record;

    type norm_t is record
        sig     : unsigned(47 downto 0);   -- normalized, bit47 = leading 1
        exp     : exp_t;                    -- unbiased exponent of bit47
        sticky  : std_logic;
        is_zero : boolean;
    end record;

    -- ---------------------------- helpers -----------------------------------
    function unpack(x : std_logic_vector(31 downto 0)) return unpacked_t is
        variable u  : unpacked_t;
        variable e  : integer;
        variable f  : unsigned(22 downto 0);
        variable m  : unsigned(23 downto 0);
        variable sh : integer;
    begin
        u.sign := x(31);
        e := to_integer(unsigned(x(30 downto 23)));
        f := unsigned(x(22 downto 0));
        u.is_zero := (e = 0)   and (f = 0);
        u.is_inf  := (e = 255) and (f = 0);
        u.is_nan  := (e = 255) and (f /= 0);
        u.is_snan := u.is_nan and (x(22) = '0');
        if e = 0 then
            if f = 0 then
                u.mant := (others => '0');
                u.exp  := 0;
            else
                m  := '0' & f;
                sh := 0;
                for i in 0 to 23 loop
                    if m(23) = '0' then
                        m  := shift_left(m, 1);
                        sh := sh + 1;
                    end if;
                end loop;
                u.mant := m;
                u.exp  := -126 - sh;
            end if;
        elsif e = 255 then
            u.mant := '1' & f;
            u.exp  := 128;
        else
            u.mant := '1' & f;
            u.exp  := e - 127;
        end if;
        return u;
    end function;

    -- normalize a wide accumulator (value = acc * 2^e_common) to (sig[47]=1, exp)
    function normalize(acc : unsigned; e_common : exp_t; sticky_pre : std_logic)
        return norm_t is
        variable n   : norm_t;
        variable L   : integer;
        variable stk : std_logic;
    begin
        L := -1;
        for i in 0 to acc'high loop
            if acc(i) = '1' then L := i; end if;
        end loop;
        if L < 0 then
            n.sig := (others => '0');
            n.exp := 0;
            n.sticky := sticky_pre;
            n.is_zero := true;
            return n;
        end if;
        n.is_zero := false;
        n.exp := e_common + L;
        stk := sticky_pre;
        if L >= 47 then
            n.sig := resize(shift_right(acc, L - 47), 48);
            for i in 0 to acc'high loop
                if i <= (L - 48) and acc(i) = '1' then stk := '1'; end if;
            end loop;
        else
            n.sig := resize(shift_left(acc, 47 - L), 48);
        end if;
        n.sticky := stk;
        return n;
    end function;

    -- shared normalize+round back-end: single rounding, all 5 modes, subnormals, overflow-per-mode, UF = tiny-after-rounding AND inexact.
    function round_pack(sign : std_logic; exp_unb : exp_t; sig : unsigned(47 downto 0);
                        sticky_in : std_logic; rm : std_logic_vector(2 downto 0))
        return round_out_t is
        variable r         : round_out_t;
        variable be        : integer;
        variable shift_amt : integer;
        variable g, s, lsb : std_logic;
        variable roundup   : std_logic;
        variable mant      : integer;
        variable mant_slv  : std_logic_vector(22 downto 0);
    begin
        r.of_f := '0'; r.uf_f := '0'; r.nx_f := '0';
        if sig = 0 then
            r.packed := sign & "00000000" & "00000000000000000000000";
            return r;
        end if;
        be := exp_unb + 127;
        shift_amt := 24;
        if be < 1 then
            shift_amt := 24 + (1 - be);
            be := 0;
        end if;
        -- guard = bit(shift_amt-1); sticky = OR(bits below) OR sticky_in
        g := '0';
        s := sticky_in;
        for i in 0 to 47 loop
            if i = shift_amt - 1 then
                g := sig(i);
            elsif i < shift_amt - 1 then
                if sig(i) = '1' then s := '1'; end if;
            end if;
        end loop;
        if shift_amt <= 47 then
            mant := to_integer(shift_right(sig, shift_amt));
        else
            mant := 0;
        end if;
        if (mant mod 2) = 1 then lsb := '1'; else lsb := '0'; end if;

        roundup := '0';
        case rm is
            when "000" => if g = '1' and (s = '1' or lsb = '1') then roundup := '1'; end if;  -- RNE
            when "001" => roundup := '0';                                                     -- RTZ
            when "010" => if sign = '1' and (g = '1' or s = '1') then roundup := '1'; end if;  -- RDN
            when "011" => if sign = '0' and (g = '1' or s = '1') then roundup := '1'; end if;  -- RUP
            when "100" => if g = '1' then roundup := '1'; end if;                              -- RMM
            when others => roundup := '0';
        end case;
        r.nx_f := g or s;

        if roundup = '1' then mant := mant + 1; end if;
        if mant >= 16777216 then          -- 2^24 carry-out
            mant := mant / 2;
            be := be + 1;
        end if;
        if be = 0 and mant >= 8388608 then -- subnormal rounded up to smallest normal
            be := 1;
        end if;

        if be >= 255 then                 -- overflow: inf or max, per mode
            case rm is
                when "001" =>                                    -- RTZ gives max
                    r.packed := sign & "11111110" & "11111111111111111111111";
                when "010" =>                                    -- RDN
                    if sign = '1' then
                        r.packed := sign & "11111111" & "00000000000000000000000";
                    else
                        r.packed := sign & "11111110" & "11111111111111111111111";
                    end if;
                when "011" =>                                    -- RUP
                    if sign = '0' then
                        r.packed := sign & "11111111" & "00000000000000000000000";
                    else
                        r.packed := sign & "11111110" & "11111111111111111111111";
                    end if;
                when others =>                                   -- RNE, RMM give inf
                    r.packed := sign & "11111111" & "00000000000000000000000";
            end case;
            r.of_f := '1';
            r.nx_f := '1';
            return r;
        end if;

        if be = 0 and r.nx_f = '1' then r.uf_f := '1'; end if;

        mant_slv := std_logic_vector(to_unsigned(mant mod 8388608, 23));
        r.packed := sign & std_logic_vector(to_unsigned(be, 8)) & mant_slv;
        return r;
    end function;

    -- ------------------------------ FSM -------------------------------------
    type st_t is (S_IDLE, S_UNPACK, S_MUL, S_ALIGN, S_DIVI, S_SQRTI, S_CVT, S_NORM, S_ROUND, S_DONE);
    signal state : st_t;

    signal start_reg : std_logic;

    -- latched operands: the run consumes ONLY these, never a live port
    signal a_lat, b_lat, c_lat : std_logic_vector(31 downto 0);
    signal op_lat : std_logic_vector(3 downto 0);
    signal rm_lat : std_logic_vector(2 downto 0);

    -- outputs (held stable until next completion)
    signal done_r   : std_logic;
    signal result_r : std_logic_vector(31 downto 0);
    signal flags_r  : std_logic_vector(4 downto 0);

    -- pipeline registers
    signal m1_r, m2_r, ad_r : unpacked_t;         -- FMA operands
    signal prod_sign_r, add_sign_r : std_logic;
    signal prod48_r  : unsigned(47 downto 0);
    signal pexp_r    : exp_t;

    signal acc_r     : unsigned(127 downto 0);
    signal ecommon_r : exp_t;
    signal rsign_r   : std_logic;
    signal stky_r    : std_logic;
    signal zero_r    : boolean;                    -- exact-zero datapath result
    signal zsign_r   : std_logic;

    signal sig_r     : unsigned(47 downto 0);
    signal eunb_r    : exp_t;
    signal nsticky_r : std_logic;
    signal fsign_r   : std_logic;

    -- div/sqrt engine
    signal ua_r, ub_r : unpacked_t;
    signal drem_r     : unsigned(26 downto 0);
    signal dquot_r    : unsigned(31 downto 0);
    signal sq_rad_r   : unsigned(55 downto 0);
    signal sq_rem_r   : unsigned(29 downto 0);
    signal sq_root_r  : unsigned(27 downto 0);
    signal iter_cnt   : integer range 0 to 63;
    signal decommon_r : exp_t;                     -- e_common for div/sqrt normalize

    constant NQ  : integer := 27;                  -- div quotient bits / iterations
    constant SQS : integer := 14;                  -- sqrt guard bits
    constant SQIT: integer := 28;                  -- sqrt iterations: 2 radicand bits each, so the full 56-bit radicand is 28 pairs

    -- unsigned range bounds: VHDL integer is 32-bit signed, so 2^31 and 2^32-1 overflow an integer literal and are built as unsigned constants instead
    constant BND_2P31M1 : unsigned(63 downto 0) := x"000000007FFFFFFF";  -- 2^31-1
    constant BND_2P31   : unsigned(63 downto 0) := x"0000000080000000";  -- 2^31
    constant BND_2P32M1 : unsigned(63 downto 0) := x"00000000FFFFFFFF";  -- 2^32-1

begin

    fpu_done  <= done_r;
    fp_result <= result_r;
    fp_flags  <= flags_r;

    process(clk, resetn)
        -- FMA working variables
        variable m1, m2, ad : unpacked_t;
        variable neg_prod, sub_add : boolean;
        variable ps, as   : std_logic;
        variable any_snan : boolean;
        variable inv0inf  : boolean;
        variable spec     : boolean;
        variable sres     : std_logic_vector(31 downto 0);
        variable sflags   : std_logic_vector(4 downto 0);
        variable raw_add  : std_logic_vector(31 downto 0);
        -- align
        variable e_p, e_c, e_hi, e_common : exp_t;
        variable pos_p, pos_c, k : integer;
        variable pplaced, cplaced : unsigned(127 downto 0);
        variable plost, clost : std_logic;
        variable sig_c48 : unsigned(47 downto 0);
        variable big, small : unsigned(127 downto 0);
        variable small_lost, big_lost : std_logic;
        variable sumv : unsigned(128 downto 0);
        variable accv : unsigned(127 downto 0);
        variable rs   : std_logic;
        variable stpre : std_logic;
        variable zsgn : std_logic;
        variable is_zero_res : boolean;
        -- normalize/round
        variable nrm : norm_t;
        variable ro  : round_out_t;
        -- div/sqrt
        variable ua, ub : unpacked_t;
        variable remv   : unsigned(26 downto 0);
        variable quotv  : unsigned(31 downto 0);
        variable radv   : unsigned(55 downto 0);
        variable sqrem  : unsigned(29 downto 0);
        variable sqroot : unsigned(27 downto 0);
        variable testv  : unsigned(29 downto 0);
        variable e2, oexp : integer;
        -- cvt
        variable uc     : unpacked_t;
        variable mag64  : unsigned(63 downto 0);
        variable gbit, sbit, lbit, rup : std_logic;
        variable shr    : integer;
        variable signed_in : boolean;
        variable neg    : boolean;
        variable ival   : unsigned(31 downto 0);
        variable msb    : integer;
        variable sgnbit : std_logic;

        -- helper: place a 48-bit value at bit position pos in the 128-bit accumulator, capturing bits shifted below bit0 as a sticky.
        procedure place48(v : in unsigned(47 downto 0); pos : in integer;
                          placed : out unsigned(127 downto 0); lost : out std_logic) is
            variable kk : integer;
            variable lo : std_logic;
        begin
            if pos >= 0 then
                placed := resize(shift_left(resize(v, 128), pos), 128);
                lost := '0';
            else
                kk := -pos;
                lo := '0';
                for i in 0 to 47 loop
                    if i < kk and v(i) = '1' then lo := '1'; end if;
                end loop;
                placed := resize(shift_right(resize(v, 128), kk), 128);
                lost := lo;
            end if;
        end procedure;

    begin
        if resetn = '0' then
            state     <= S_IDLE;
            start_reg <= '0';
            done_r    <= '0';
            result_r  <= (others => '0');
            flags_r   <= (others => '0');
            iter_cnt  <= 0;
        elsif rising_edge(clk) then
            done_r <= '0';
            case state is

                -- ---------------------------------------------------------
                -- wait for a start pulse, then latch operands, op and rm for the whole run
                when S_IDLE =>
                    if fpu_start = '1' and start_reg = '0' then
                        a_lat  <= fp_a;
                        b_lat  <= fp_b;
                        c_lat  <= fp_c;
                        op_lat <= fp_op;
                        rm_lat <= rm;
                        state  <= S_UNPACK;
                    end if;
                    start_reg <= fpu_start;

                -- ---------------------------------------------------------
                -- unpack + dispatch + special-case resolution
                when S_UNPACK =>
                    start_reg <= fpu_start;
                    spec   := false;
                    sres   := QNAN;
                    sflags := (others => '0');

                    case op_lat is
                        -------------------------------------------------- FMA family
                        when OP_FADD | OP_FSUB | OP_FMUL |
                             OP_FMADD | OP_FMSUB | OP_FNMSUB | OP_FNMADD =>
                            -- operand mapping to (m1*m2) +/- addend
                            if op_lat = OP_FADD or op_lat = OP_FSUB then
                                m1 := unpack(a_lat);
                                m2 := (sign => '0', exp => 0, mant => x"800000",
                                       is_zero => false, is_inf => false,
                                       is_nan => false, is_snan => false);  -- 1.0
                                ad := unpack(b_lat);
                                raw_add := b_lat;
                            elsif op_lat = OP_FMUL then
                                m1 := unpack(a_lat);
                                m2 := unpack(b_lat);
                                ad := (sign => '0', exp => 0, mant => (others => '0'),
                                       is_zero => true, is_inf => false,
                                       is_nan => false, is_snan => false);  -- +0
                                raw_add := (others => '0');
                            else
                                m1 := unpack(a_lat);
                                m2 := unpack(b_lat);
                                ad := unpack(c_lat);
                                raw_add := c_lat;
                            end if;
                            neg_prod := (op_lat = OP_FNMSUB) or (op_lat = OP_FNMADD);
                            sub_add  := (op_lat = OP_FSUB) or (op_lat = OP_FMSUB) or (op_lat = OP_FNMADD);
                            ps := m1.sign xor m2.sign;
                            if neg_prod then ps := not ps; end if;
                            as := ad.sign;
                            if sub_add then as := not as; end if;

                            any_snan := m1.is_snan or m2.is_snan or ad.is_snan;
                            inv0inf  := (m1.is_zero and m2.is_inf) or (m1.is_inf and m2.is_zero);

                            if m1.is_nan or m2.is_nan or ad.is_nan or inv0inf then
                                spec := true; sres := QNAN;
                                if any_snan or inv0inf then sflags(4) := '1'; end if;   -- NV
                            elsif m1.is_inf or m2.is_inf then          -- product = inf(ps)
                                if ad.is_inf then
                                    if as = ps then
                                        sres := ps & "11111111" & "00000000000000000000000";
                                    else
                                        sres := QNAN; sflags(4) := '1';   -- inf - inf
                                    end if;
                                else
                                    sres := ps & "11111111" & "00000000000000000000000";
                                end if;
                                spec := true;
                            elsif ad.is_inf then                        -- addend inf, product finite
                                spec := true;
                                sres := as & "11111111" & "00000000000000000000000";
                            elsif m1.is_zero or m2.is_zero then         -- product = zero(ps)
                                spec := true;
                                if op_lat = OP_FMUL then
                                    -- fmul: the sign of a zero product is purely the product sign, since the injected +0 addend must NOT trigger the sum-of-zeros rule
                                    sres := ps & "0000000000000000000000000000000";
                                elsif ad.is_zero then
                                    if ps = as then
                                        zsgn := ps;
                                    elsif rm_lat = "010" then           -- RDN gives -0
                                        zsgn := '1';
                                    else
                                        zsgn := '0';
                                    end if;
                                    sres := zsgn & "0000000000000000000000000000000";
                                else
                                    sres := as & raw_add(30 downto 0);  -- result = addend exactly
                                end if;
                            end if;

                            m1_r <= m1; m2_r <= m2; ad_r <= ad;
                            prod_sign_r <= ps; add_sign_r <= as;

                            if spec then
                                result_r <= sres; flags_r <= sflags;
                                done_r   <= '1';
                                state <= S_DONE;
                            else
                                state <= S_MUL;
                            end if;

                        -------------------------------------------------- FDIV
                        when OP_FDIV =>
                            ua := unpack(a_lat); ub := unpack(b_lat);
                            rs := ua.sign xor ub.sign;
                            any_snan := ua.is_snan or ub.is_snan;
                            if ua.is_nan or ub.is_nan then
                                spec := true; sres := QNAN;
                                if any_snan then sflags(4) := '1'; end if;
                            elsif (ua.is_inf and ub.is_inf) or (ua.is_zero and ub.is_zero) then
                                spec := true; sres := QNAN; sflags(4) := '1';   -- inf/inf, 0/0
                            elsif ua.is_inf then
                                spec := true; sres := rs & "11111111" & "00000000000000000000000";
                            elsif ub.is_inf then
                                spec := true; sres := rs & "0000000000000000000000000000000";
                            elsif ub.is_zero then
                                spec := true; sres := rs & "11111111" & "00000000000000000000000";
                                sflags(3) := '1';                                 -- DZ
                            elsif ua.is_zero then
                                spec := true; sres := rs & "0000000000000000000000000000000";
                            end if;
                            ua_r <= ua; ub_r <= ub; rsign_r <= rs;
                            if spec then
                                result_r <= sres; flags_r <= sflags;
                                done_r   <= '1';
                                state <= S_DONE;
                            else
                                -- reduce the initial remainder below the divisor and seed the quotient integer bit, so the loop keeps rem < divisor (restoring-division invariant).
                                if ua.mant >= ub.mant then
                                    drem_r  <= resize(ua.mant - ub.mant, 27);
                                    dquot_r <= to_unsigned(1, 32);
                                else
                                    drem_r  <= resize(ua.mant, 27);
                                    dquot_r <= (others => '0');
                                end if;
                                iter_cnt <= NQ;
                                state <= S_DIVI;
                            end if;

                        -------------------------------------------------- FSQRT
                        when OP_FSQRT =>
                            ua := unpack(a_lat);
                            if ua.is_nan then
                                spec := true; sres := QNAN;
                                if ua.is_snan then sflags(4) := '1'; end if;
                            elsif ua.is_zero then
                                spec := true; sres := ua.sign & "0000000000000000000000000000000";
                            elsif ua.sign = '1' then                  -- negative (incl -inf)
                                spec := true; sres := QNAN; sflags(4) := '1';
                            elsif ua.is_inf then
                                spec := true; sres := "0" & "11111111" & "00000000000000000000000";
                            end if;
                            ua_r <= ua;
                            if spec then
                                result_r <= sres; flags_r <= sflags;
                                done_r   <= '1';
                                state <= S_DONE;
                            else
                                -- build radicand: value = mant_a * 2^(exp-23); split parity
                                e2 := ua.exp - 23;
                                if (e2 mod 2) = 0 then
                                    radv := resize(ua.mant, 56);          -- rad = mant
                                    oexp := e2 / 2;
                                else
                                    radv := resize(ua.mant & '0', 56);    -- rad = 2*mant
                                    oexp := (e2 - 1) / 2;
                                end if;
                                radv := shift_left(radv, 2 * SQS);        -- scale by 2^(2*S)
                                sq_rad_r  <= radv;
                                sq_rem_r  <= (others => '0');
                                sq_root_r <= (others => '0');
                                decommon_r <= oexp - SQS;
                                iter_cnt  <= SQIT;
                                state <= S_SQRTI;
                            end if;

                        -------------------------------------------------- FCVT
                        when OP_FCVT_W_S | OP_FCVT_WU_S | OP_FCVT_S_W | OP_FCVT_S_WU =>
                            state <= S_CVT;

                        -- unrecognised opcode: return zero with no flags rather than hang
                        when others =>
                            result_r <= (others => '0'); flags_r <= (others => '0');
                            done_r   <= '1';
                            state <= S_DONE;
                    end case;

                -- ---------------------------------------------------------
                -- FMA: 24x24 combinational multiply, registered into product stage
                when S_MUL =>
                    start_reg <= fpu_start;
                    prod48_r <= m1_r.mant * m2_r.mant;
                    pexp_r   <= m1_r.exp + m2_r.exp - 46;   -- LSB exponent of prod48
                    state <= S_ALIGN;

                -- ---------------------------------------------------------
                -- FMA: wide align + add/sub (single rounding preserved via GRS)
                when S_ALIGN =>
                    start_reg <= fpu_start;
                    e_p := pexp_r;
                    e_c := ad_r.exp - 23;
                    if ad_r.is_zero then
                        -- addend contributes nothing; force it far below product
                        e_c := e_p - 200;
                    end if;
                    if e_p >= e_c then e_hi := e_p; else e_hi := e_c; end if;
                    e_common := e_hi - 78;
                    pos_p := e_p - e_common;
                    pos_c := e_c - e_common;
                    sig_c48 := resize(ad_r.mant, 48);
                    place48(prod48_r, pos_p, pplaced, plost);
                    place48(sig_c48,  pos_c, cplaced, clost);

                    if prod_sign_r = add_sign_r then          -- effective ADD
                        sumv := ('0' & pplaced) + ('0' & cplaced);
                        accv := sumv(127 downto 0);
                        rs   := prod_sign_r;
                        stpre := plost or clost;
                        is_zero_res := (accv = 0);
                    else                                       -- effective SUBTRACT
                        if pplaced >= cplaced then
                            big := pplaced; small := cplaced;
                            small_lost := clost; big_lost := plost;
                            rs := prod_sign_r;
                        else
                            big := cplaced; small := pplaced;
                            small_lost := plost; big_lost := clost;
                            rs := add_sign_r;
                        end if;
                        if small_lost = '1' then
                            accv := big - small - 1;
                            stpre := '1';
                        else
                            accv := big - small;
                            stpre := big_lost;
                        end if;
                        is_zero_res := (accv = 0) and (stpre = '0');
                    end if;

                    -- exact-cancellation zero sign: +0, except under RDN where it is -0
                    if rm_lat = "010" then zsgn := '1'; else zsgn := '0'; end if;

                    acc_r     <= accv;
                    ecommon_r <= e_common;
                    rsign_r   <= rs;
                    stky_r    <= stpre;
                    zero_r    <= is_zero_res;
                    zsign_r   <= zsgn;
                    state <= S_NORM;

                -- ---------------------------------------------------------
                -- radix-2 restoring division, one quotient bit per cycle
                when S_DIVI =>
                    start_reg <= fpu_start;
                    remv  := drem_r;
                    quotv := dquot_r;
                    remv  := shift_left(remv, 1);
                    quotv := shift_left(quotv, 1);
                    if remv >= resize(ub_r.mant, 27) then
                        remv := remv - resize(ub_r.mant, 27);
                        quotv(0) := '1';
                    end if;
                    drem_r  <= remv;
                    dquot_r <= quotv;
                    if iter_cnt = 1 then
                        -- assemble: value = quot * 2^(ea-eb-NQ); sticky = rem/=0
                        acc_r     <= resize(quotv, 128);
                        ecommon_r <= ua_r.exp - ub_r.exp - NQ;
                        if remv /= 0 then stky_r <= '1'; else stky_r <= '0'; end if;
                        zero_r    <= false;
                        state <= S_NORM;
                    else
                        iter_cnt <= iter_cnt - 1;
                    end if;

                -- ---------------------------------------------------------
                -- radix-2 restoring square root, one root bit per cycle
                when S_SQRTI =>
                    start_reg <= fpu_start;
                    sqrem  := sq_rem_r;
                    sqroot := sq_root_r;
                    radv   := sq_rad_r;
                    -- bring down the top 2 bits of the radicand
                    sqrem  := shift_left(sqrem, 2);
                    sqrem(1 downto 0) := radv(55 downto 54);
                    radv   := shift_left(radv, 2);
                    sqroot := shift_left(sqroot, 1);
                    testv  := resize(sqroot & '1', 30);        -- 2*root + 1
                    if sqrem >= testv then
                        sqrem := sqrem - testv;
                        sqroot(0) := '1';
                    end if;
                    sq_rem_r  <= sqrem;
                    sq_root_r <= sqroot;
                    sq_rad_r  <= radv;
                    if iter_cnt = 1 then
                        acc_r     <= resize(sqroot, 128);
                        ecommon_r <= decommon_r;
                        rsign_r   <= '0';
                        if sqrem /= 0 then stky_r <= '1'; else stky_r <= '0'; end if;
                        zero_r    <= false;
                        state <= S_NORM;
                    else
                        iter_cnt <= iter_cnt - 1;
                    end if;

                -- ---------------------------------------------------------
                -- shared normalize (feeds the round stage)
                when S_NORM =>
                    start_reg <= fpu_start;
                    if zero_r then
                        -- exact zero result: sign per cancellation rule
                        result_r <= zsign_r & "0000000000000000000000000000000";
                        flags_r  <= (others => '0');
                        done_r   <= '1';
                        state    <= S_DONE;
                    else
                        nrm := normalize(acc_r, ecommon_r, stky_r);
                        sig_r     <= nrm.sig;
                        eunb_r    <= nrm.exp;
                        nsticky_r <= nrm.sticky;
                        fsign_r   <= rsign_r;
                        state <= S_ROUND;
                    end if;

                -- ---------------------------------------------------------
                -- shared round + pack
                when S_ROUND =>
                    start_reg <= fpu_start;
                    ro := round_pack(fsign_r, eunb_r, sig_r, nsticky_r, rm_lat);
                    result_r <= ro.packed;
                    flags_r  <= (4 => '0', 3 => '0', 2 => ro.of_f, 1 => ro.uf_f, 0 => ro.nx_f);
                    done_r   <= '1';
                    state    <= S_DONE;

                -- ---------------------------------------------------------
                -- conversions (unpack + round only)
                when S_CVT =>
                    start_reg <= fpu_start;
                    sflags := (others => '0');
                    if op_lat = OP_FCVT_S_W or op_lat = OP_FCVT_S_WU then
                        ---------------------------------------------- int to float
                        signed_in := (op_lat = OP_FCVT_S_W);
                        neg := signed_in and (a_lat(31) = '1');
                        if neg then
                            ival := unsigned(std_logic_vector(0 - signed(a_lat)));
                        else
                            ival := unsigned(a_lat);
                        end if;
                        if ival = 0 then
                            result_r <= (others => '0');
                            flags_r  <= (others => '0');
                            done_r   <= '1';
                            state    <= S_DONE;
                        else
                            msb := 0;
                            for i in 0 to 31 loop
                                if ival(i) = '1' then msb := i; end if;
                            end loop;
                            if neg then sgnbit := '1'; else sgnbit := '0'; end if;
                            -- value = ival * 2^0 ; normalize sig[47]=1, exp = msb
                            ro := round_pack(sgnbit, msb,
                                             resize(shift_left(resize(ival, 48), 47 - msb), 48),
                                             '0', rm_lat);
                            result_r <= ro.packed;
                            flags_r  <= (2 => ro.of_f, 1 => ro.uf_f, 0 => ro.nx_f, others => '0');
                            done_r   <= '1';
                            state    <= S_DONE;
                        end if;
                    else
                        ---------------------------------------------- float to int
                        signed_in := (op_lat = OP_FCVT_W_S);
                        uc := unpack(a_lat);
                        if uc.is_nan then
                            if signed_in then result_r <= x"7FFFFFFF"; else result_r <= x"FFFFFFFF"; end if;
                            flags_r <= (4 => '1', others => '0');
                            done_r <= '1'; state <= S_DONE;
                        elsif uc.is_inf then
                            if uc.sign = '0' then
                                if signed_in then result_r <= x"7FFFFFFF"; else result_r <= x"FFFFFFFF"; end if;
                            else
                                if signed_in then result_r <= x"80000000"; else result_r <= x"00000000"; end if;
                            end if;
                            flags_r <= (4 => '1', others => '0');
                            done_r <= '1'; state <= S_DONE;
                        else
                            -- magnitude = mant * 2^(exp-23) rounded to integer
                            mag64 := (others => '0');
                            gbit := '0'; sbit := '0';
                            if uc.is_zero then
                                mag64 := (others => '0');
                            elsif uc.exp >= 23 then
                                if uc.exp - 23 <= 40 then
                                    mag64 := resize(shift_left(resize(uc.mant, 64), uc.exp - 23), 64);
                                else
                                    mag64 := (others => '1');   -- huge: saturate so the range check below flags overflow
                                end if;
                            else
                                shr := 23 - uc.exp;
                                if shr <= 40 then
                                    mag64 := resize(shift_right(resize(uc.mant, 64), shr), 64);
                                    -- guard = bit(shr-1) of mant, taken as 0 if that index is above the 24-bit mantissa; sticky = OR of the bits below it
                                    if (shr - 1) <= 23 then
                                        gbit := uc.mant(shr - 1);
                                    else
                                        gbit := '0';
                                    end if;
                                    for i in 0 to 23 loop
                                        if i < (shr - 1) and uc.mant(i) = '1' then sbit := '1'; end if;
                                    end loop;
                                else
                                    mag64 := (others => '0');
                                    gbit := '0';
                                    if uc.mant /= 0 then sbit := '1'; end if;
                                end if;
                            end if;
                            if (mag64(0) = '1') then lbit := '1'; else lbit := '0'; end if;
                            rup := '0';
                            -- same rounding decision as round_pack, applied to the integer magnitude
                            case rm_lat is
                                when "000" => if gbit = '1' and (sbit = '1' or lbit = '1') then rup := '1'; end if;   -- RNE
                                when "001" => rup := '0';                                                            -- RTZ
                                when "010" => if uc.sign = '1' and (gbit = '1' or sbit = '1') then rup := '1'; end if; -- RDN
                                when "011" => if uc.sign = '0' and (gbit = '1' or sbit = '1') then rup := '1'; end if; -- RUP
                                when "100" => if gbit = '1' then rup := '1'; end if;                                 -- RMM
                                when others => rup := '0';
                            end case;
                            if rup = '1' then mag64 := mag64 + 1; end if;

                            if signed_in then
                                if uc.sign = '0' then
                                    if mag64 <= BND_2P31M1 then
                                        result_r <= std_logic_vector(mag64(31 downto 0));
                                        flags_r  <= (0 => (gbit or sbit), others => '0');
                                    else
                                        result_r <= x"7FFFFFFF";
                                        flags_r  <= (4 => '1', others => '0');
                                    end if;
                                else
                                    if mag64 <= BND_2P31 then
                                        result_r <= std_logic_vector((not mag64(31 downto 0)) + 1);
                                        flags_r  <= (0 => (gbit or sbit), others => '0');
                                    else
                                        result_r <= x"80000000";
                                        flags_r  <= (4 => '1', others => '0');
                                    end if;
                                end if;
                            else
                                if uc.sign = '1' then
                                    if mag64 = 0 then
                                        -- negative value rounding to 0: in range, inexact if the input was nonzero
                                        result_r <= x"00000000";
                                        flags_r  <= (0 => (gbit or sbit), others => '0');
                                    else
                                        result_r <= x"00000000";
                                        flags_r  <= (4 => '1', others => '0');
                                    end if;
                                else
                                    if mag64 <= BND_2P32M1 then
                                        result_r <= std_logic_vector(mag64(31 downto 0));
                                        flags_r  <= (0 => (gbit or sbit), others => '0');
                                    else
                                        result_r <= x"FFFFFFFF";
                                        flags_r  <= (4 => '1', others => '0');
                                    end if;
                                end if;
                            end if;
                            done_r <= '1'; state <= S_DONE;
                        end if;
                    end if;

                -- ---------------------------------------------------------
                -- one drain cycle: result/flags already hold, so just return to idle
                when S_DONE =>
                    start_reg <= fpu_start;
                    state <= S_IDLE;

                -- unreachable state encoding: recover to idle
                when others =>
                    state <= S_IDLE;
            end case;
        end if;
    end process;

end rtl;
