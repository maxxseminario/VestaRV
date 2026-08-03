library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.constants.all;

-- This code implements the restoring division algorithm for XLEN-bit signed and unsigned integers.
-- It supports both division and remainder operations, as specified by the RISC-V ISA.
-- Takes XLEN clock cycles +1 start cycle +1 done cycle (XLEN+2 total) to complete the operation.

entity div is
    port (
        resetn     : in  std_logic;
        clk        : in  std_logic;
        start      : in  std_logic;
        a          : in  std_logic_vector(XLEN-1 downto 0);  -- Dividend
        b          : in  std_logic_vector(XLEN-1 downto 0);  -- Divisor
        sel_signed : in  std_logic;                      -- '1' for signed division, '0' for unsigned
        sel_rem    : in  std_logic;                      -- '1' for remainder (rem/remu), '0' for quotient (div/divu)
        result     : out std_logic_vector(XLEN-1 downto 0);  -- Quotient or Remainder
        complete   : out std_logic;                      -- '1' when division is in progress
        rdy        : out std_logic
    );
end div;

architecture rtl of div is

    type state_t is (IDLE, WORK, COMPLETED);
    signal state : state_t;
    signal N, D  : signed(XLEN-1 downto 0);
    signal N_u, D_u : unsigned(XLEN-1 downto 0);
    -- K5 defect A: the signed restoring loop's MAGNITUDES and PARTIAL REMAINDER
    -- are UNSIGNED.  They were `signed(XLEN-1 downto 0)`, and that is the whole
    -- bug: a magnitude of exactly 2**31 -- which is what abs(INT_MIN) is, since
    -- abs() wraps -- reads as NEGATIVE in the loop guard at :154.  Two escapes
    -- followed, both measured:
    --   * b = INT_MIN  => D_Abs read as -2**31, so `R_var >= D_Abs` was TRUE at
    --     all 32 steps and every quotient bit was set.
    --   * a = INT_MIN and abs(b) > 2**30 => the final shift_left produces
    --     exactly 2**31, read as negative, so the last restore was SKIPPED.
    -- No other operand can reach bit 31: at a non-final step the partial
    -- remainder is floor(N_Abs / 2**j) mod D_Abs with j >= 1, hence < 2**30
    -- whenever N_Abs < 2**31.  That is why every non-INT_MIN pair was already
    -- correct, and why the UNSIGNED branch below (R_unsigned/Q_unsigned) never
    -- had the defect at all -- this change simply gives the signed branch the
    -- same unsigned datapath, fed magnitudes.  Signs are applied only at the
    -- result mux (:224/:231), which is otherwise unchanged.
    signal Q : unsigned(XLEN-1 downto 0);
    signal R : unsigned(XLEN-1 downto 0);
    signal cnt : integer range 0 to XLEN;
    signal Q_unsigned : unsigned(XLEN-1 downto 0);
    signal R_unsigned : unsigned(XLEN-1 downto 0);
    signal N_Abs, D_Abs : unsigned(XLEN-1 downto 0);
    signal neg_result : std_logic;
    signal neg_rem : std_logic;
    signal start_reg : std_logic;
    -- Dispatch-time copies of the operand ports. The result process (below)
    -- decides the RISC-V special cases (divide-by-zero, signed overflow, and
    -- the rem-by-zero passthrough) from these LATCHED values instead of the
    -- live a/b ports, so the divider's output depends only on the operands as
    -- captured when the operation started — the same phase-stable-operand
    -- discipline the core uses elsewhere (rs1_value for LR/SC/AMO). This keeps
    -- the divider immune to any regfile activity on its a/b ports during the
    -- multi-cycle run.
    signal a_lat, b_lat : std_logic_vector(XLEN-1 downto 0);

    -- XLEN-wide special-case values (RISC-V div/rem spec): all-ones (-1 /
    -- unsigned max) and the most-negative signed integer (overflow operand).
    constant DIV_ZERO_X    : std_logic_vector(XLEN-1 downto 0) := (others => '0');
    constant DIV_ALLONES_X : std_logic_vector(XLEN-1 downto 0) := (others => '1');
    constant DIV_MININT_X  : std_logic_vector(XLEN-1 downto 0) := (XLEN-1 => '1', others => '0');

begin

    -- Simple rdy assignment based on state
    rdy <= '1' when (resetn = '0' or state = IDLE or state = COMPLETED) else '0';
    -- complete <= '1' when state = COMPLETED else '0';

    process(clk, resetn)
        variable R_var : unsigned(XLEN-1 downto 0);
        variable Q_var : unsigned(XLEN-1 downto 0);
        variable R_u_var : unsigned(XLEN-1 downto 0);
        variable Q_u_var : unsigned(XLEN-1 downto 0);
    begin

        if resetn = '0' then
            state <= IDLE;
            N <= (others => '0');
            D <= (others => '0');
            N_u <= (others => '0');
            D_u <= (others => '0');
            Q <= (others => '0');
            R <= (others => '0');
            Q_unsigned <= (others => '0');
            R_unsigned <= (others => '0');
            cnt <= 0;
            neg_result <= '0';
            neg_rem <= '0';
            start_reg <= '0';
            a_lat <= (others => '0');
            b_lat <= (others => '0');
            -- rdy <= '1';
            complete <= '0';
    
        elsif rising_edge(clk) then
            case state is
                when IDLE =>
                    -- state <= IDLE;
                    complete <= '0';
                    
                    if start = '1' and start_reg = '0' then
                        -- rdy <= '0';
                        -- Latch inputs and initialize
                        -- Latch the raw operand ports for the result-process
                        -- special cases (div-by-zero / overflow / rem passthrough).
                        a_lat <= a;
                        b_lat <= b;
                        if sel_signed = '1' then
                            N <= signed(a);
                            D <= signed(b);
                            -- abs() on signed WRAPS at INT_MIN and returns
                            -- x"80000000".  Read as UNSIGNED that bit pattern is
                            -- 2**31, which is the CORRECT magnitude -- so the
                            -- cast, not a wider adder, is the whole fix.
                            N_Abs <= unsigned(abs(signed(a)));
                            D_Abs <= unsigned(abs(signed(b)));
                            neg_result <= (a(XLEN-1) xor b(XLEN-1));
                            neg_rem <= a(XLEN-1);       -- only dividend sign for remainder
                        else
                            N_u <= unsigned(a);
                            D_u <= unsigned(b);
                        end if;
                        Q <= (others => '0');
                        R <= (others => '0');
                        Q_unsigned <= (others => '0');
                        R_unsigned <= (others => '0');
                        cnt <= XLEN-1;
                        state <= WORK;
                    else 
                        state <= IDLE;
                        -- rdy <= '1';
                    end if;
                    
                    start_reg <= start;
                when WORK =>
                    -- state <= WORK;
                    -- complete <= '0';
                    -- rdy <= '0';
                    if sel_signed = '1' then
                        R_var := shift_left(R, 1);
                        R_var(0) := N_Abs(cnt);
                        Q_var := Q;
                        -- K5 defect A: this compare is now UNSIGNED.  As a signed
                        -- compare it was the single site the defect acted at.
                        if R_var >= D_Abs then
                            R_var := R_var - D_Abs;
                            Q_var(cnt) := '1';
                        end if;
                        R <= R_var;
                        Q <= Q_var;
                    else
                        R_u_var := shift_left(R_unsigned, 1);
                        R_u_var(0) := N_u(cnt);
                        Q_u_var := Q_unsigned;
                        if R_u_var >= D_u then
                            R_u_var := R_u_var - D_u;
                            Q_u_var(cnt) := '1';
                        end if;
                        R_unsigned <= R_u_var;
                        Q_unsigned <= Q_u_var;
                    end if;

                    if cnt = 0 then
                        state <= COMPLETED;
                        complete <= '1';
                    else
                        cnt <= cnt - 1;
                        state <= WORK;
                        complete <= '0';
                    end if;
                when COMPLETED =>
                    complete <= '1';
                    -- rdy <= '1';
                    state <= IDLE;
            end case;
        end if;

    end process;

    

    process(resetn, state, complete, a_lat, b_lat, sel_rem, sel_signed, neg_rem, R, neg_result, Q, R_unsigned, Q_unsigned)
    begin
        if resetn = '0' then
            result <= (others => '0');
        -- elsif state = COMPLETED then
        elsif complete = '1' then
            -- Division by zero cases (RISC-V spec) — decided from the LATCHED
            -- operands (a_lat/b_lat), never the live a/b ports.
            if b_lat = DIV_ZERO_X then
                if sel_rem = '1' then
                    result <= a_lat; -- remu: operand a, rem: operand a
                else
                    if sel_signed = '1' then
                        result <= DIV_ALLONES_X; -- div: -1 (all 1's)
                    else
                        result <= DIV_ALLONES_X; -- divu: all 1's
                    end if;
                end if;
            -- Overflow case for signed division/remainder: a = MIN_INT, b = -1
            elsif (sel_signed = '1') and (a_lat = DIV_MININT_X) and (b_lat = DIV_ALLONES_X) then
                if sel_rem = '1' then
                    result <= DIV_ZERO_X; -- rem: 0
                else
                    result <= DIV_MININT_X; -- div: MIN_INT
                end if;
            else
                if sel_signed = '1' then
                    if sel_rem = '1' then
                        -- REM: signed remainder
                        -- R is UNSIGNED now (defect A), so the negation casts to
                        -- signed explicitly: numeric_std defines unary "-" for
                        -- SIGNED only.  Value-identical to the old `-R`.
                        if neg_rem = '1' then
                            result <= std_logic_vector(-signed(R));
                        else
                            result <= std_logic_vector(R);
                        end if;
                    else
                        -- DIV: signed division
                        if neg_result = '1' then
                            result <= std_logic_vector(-signed(Q));
                        else
                            result <= std_logic_vector(Q);
                        end if;
                    end if;
                else
                    if sel_rem = '1' then
                        -- REMU: unsigned remainder
                        result <= std_logic_vector(R_unsigned);
                    else
                        -- DIVU: unsigned division
                        result <= std_logic_vector(Q_unsigned);
                    end if;
                end if;
            end if;
        -- else
        --     result <= (others => '0');
        end if;
    end process;

end rtl;