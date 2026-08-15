library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.constants.all;

-- Restoring division for XLEN-bit signed and unsigned integers.
-- It supports both division and remainder operations, as specified by the RISC-V ISA.
-- One operation takes XLEN clock cycles plus one start cycle plus one done cycle, XLEN+2 in total.

entity div is
    port (
        resetn     : in  std_logic;
        clk        : in  std_logic;
        start      : in  std_logic;
        a          : in  std_logic_vector(XLEN-1 downto 0);  -- Dividend.
        b          : in  std_logic_vector(XLEN-1 downto 0);  -- Divisor.
        sel_signed : in  std_logic;                      -- '1' for signed division, '0' for unsigned.
        sel_rem    : in  std_logic;                      -- '1' for remainder (rem/remu), '0' for quotient (div/divu).
        result     : out std_logic_vector(XLEN-1 downto 0);  -- Quotient or remainder.
        complete   : out std_logic;                      -- '1' once the division has finished and result is valid.
        rdy        : out std_logic
    );
end div;

architecture rtl of div is

    type state_t is (IDLE, WORK, COMPLETED);
    signal state : state_t;
    signal N, D  : signed(XLEN-1 downto 0);
    signal N_u, D_u : unsigned(XLEN-1 downto 0);
    -- K5 defect A: the signed restoring loop's MAGNITUDES and PARTIAL REMAINDER are UNSIGNED.
    -- They were `signed(XLEN-1 downto 0)`, and that is the whole bug: a magnitude of exactly 2**31, which is what abs(INT_MIN) is because abs() wraps, reads as NEGATIVE in the WORK-state loop guard, the `R_var >= D_Abs` compare below.
    -- Two escapes followed, both measured:
    --   * b = INT_MIN made D_Abs read as -2**31, so `R_var >= D_Abs` was TRUE at all 32 steps and every quotient bit was set.
    --   * a = INT_MIN with abs(b) greater than 2**30 made the final shift_left produce exactly 2**31, read as negative, so the last restore was SKIPPED.
    -- No other operand can reach bit 31: at a non-final step the partial remainder is floor(N_Abs / 2**j) mod D_Abs with j >= 1, hence below 2**30 whenever N_Abs < 2**31.
    -- That is why every non-INT_MIN pair was already correct, and why the UNSIGNED branch below (R_unsigned/Q_unsigned) never had the defect at all.
    -- The fix simply gives the signed branch the same unsigned datapath, fed magnitudes; signs are applied only at the result mux (the two `-signed(...)` negations in the result process), which is otherwise unchanged.
    signal Q : unsigned(XLEN-1 downto 0);
    signal R : unsigned(XLEN-1 downto 0);
    signal cnt : integer range 0 to XLEN;
    signal Q_unsigned : unsigned(XLEN-1 downto 0);
    signal R_unsigned : unsigned(XLEN-1 downto 0);
    signal N_Abs, D_Abs : unsigned(XLEN-1 downto 0);
    signal neg_result : std_logic;
    signal neg_rem : std_logic;
    signal start_reg : std_logic;
    -- Dispatch-time copies of the operand ports.
    -- The result process below decides the RISC-V special cases (divide-by-zero, signed overflow, and the rem-by-zero passthrough) from these LATCHED values instead of the live a/b ports.
    -- The divider's output therefore depends only on the operands as captured when the operation started, the same phase-stable-operand discipline the core uses elsewhere with rs1_value for LR/SC/AMO.
    -- This keeps the divider immune to any regfile activity on its a/b ports during the multi-cycle run.
    signal a_lat, b_lat : std_logic_vector(XLEN-1 downto 0);

    -- XLEN-wide special-case values from the RISC-V div/rem spec: zero, all-ones (-1 signed, maximum unsigned), and the most-negative signed integer, which is the overflow operand.
    constant DIV_ZERO_X    : std_logic_vector(XLEN-1 downto 0) := (others => '0');
    constant DIV_ALLONES_X : std_logic_vector(XLEN-1 downto 0) := (others => '1');
    constant DIV_MININT_X  : std_logic_vector(XLEN-1 downto 0) := (XLEN-1 => '1', others => '0');

begin

    -- The unit is ready whenever it is not stepping through a division.
    rdy <= '1' when (resetn = '0' or state = IDLE or state = COMPLETED) else '0';
    -- complete <= '1' when state = COMPLETED else '0';

    -- Sequencer: latches the operands on start, then walks one restoring-division step per clock.
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
                when IDLE =>       -- Wait for a rising start strobe, then latch operands and arm the loop.
                    -- state <= IDLE;
                    complete <= '0';
                    
                    if start = '1' and start_reg = '0' then
                        -- rdy <= '0';
                        -- Latch inputs and initialize the loop state.
                        -- The raw operand ports are latched for the result process's special cases: divide-by-zero, overflow, and the rem passthrough.
                        a_lat <= a;
                        b_lat <= b;
                        if sel_signed = '1' then
                            N <= signed(a);
                            D <= signed(b);
                            -- abs() on signed WRAPS at INT_MIN and returns x"80000000".
                            -- Read as UNSIGNED that bit pattern is 2**31, which is the CORRECT magnitude, so the cast and not a wider adder is the whole fix.
                            N_Abs <= unsigned(abs(signed(a)));
                            D_Abs <= unsigned(abs(signed(b)));
                            neg_result <= (a(XLEN-1) xor b(XLEN-1));
                            neg_rem <= a(XLEN-1);       -- The remainder takes the dividend's sign only.
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
                when WORK =>       -- One restoring step per clock, from bit XLEN-1 down to bit 0.
                    -- state <= WORK;
                    -- complete <= '0';
                    -- rdy <= '0';
                    if sel_signed = '1' then
                        R_var := shift_left(R, 1);
                        R_var(0) := N_Abs(cnt);
                        Q_var := Q;
                        -- K5 defect A: this compare is now UNSIGNED; as a signed compare it was the single site the defect acted at.
                        if R_var >= D_Abs then
                            R_var := R_var - D_Abs;
                            Q_var(cnt) := '1';
                        end if;
                        R <= R_var;
                        Q <= Q_var;
                    else
                        -- Unsigned branch: the same step on the operands as given, no magnitudes and no sign fixup.
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
                when COMPLETED =>  -- Hold complete high for one cycle so the result mux is sampled, then go idle.
                    complete <= '1';
                    -- rdy <= '1';
                    state <= IDLE;
            end case;
        end if;

    end process;

    

    -- Result mux: applies the RISC-V special cases first, then the sign to the loop's magnitude result.
    process(resetn, state, complete, a_lat, b_lat, sel_rem, sel_signed, neg_rem, R, neg_result, Q, R_unsigned, Q_unsigned)
    begin
        if resetn = '0' then
            result <= (others => '0');
        -- elsif state = COMPLETED then
        elsif complete = '1' then
            -- Division-by-zero cases from the RISC-V spec, decided from the LATCHED operands a_lat and b_lat, never from the live a/b ports.
            if b_lat = DIV_ZERO_X then
                if sel_rem = '1' then
                    result <= a_lat; -- rem and remu both return the dividend unchanged.
                else
                    if sel_signed = '1' then
                        result <= DIV_ALLONES_X; -- div returns -1, which is all ones.
                    else
                        result <= DIV_ALLONES_X; -- divu returns the unsigned maximum, also all ones.
                    end if;
                end if;
            -- Overflow case for signed division and remainder: a is MIN_INT and b is -1.
            elsif (sel_signed = '1') and (a_lat = DIV_MININT_X) and (b_lat = DIV_ALLONES_X) then
                if sel_rem = '1' then
                    result <= DIV_ZERO_X; -- rem returns 0.
                else
                    result <= DIV_MININT_X; -- div returns MIN_INT, the wrapped quotient.
                end if;
            else
                if sel_signed = '1' then
                    if sel_rem = '1' then
                        -- REM: signed remainder.
                        -- R is UNSIGNED since defect A, so the negation casts to signed explicitly, because numeric_std defines unary "-" for SIGNED only.
                        -- The result is value-identical to the old `-R`.
                        if neg_rem = '1' then
                            result <= std_logic_vector(-signed(R));
                        else
                            result <= std_logic_vector(R);
                        end if;
                    else
                        -- DIV: signed quotient, negated when the operand signs differ.
                        if neg_result = '1' then
                            result <= std_logic_vector(-signed(Q));
                        else
                            result <= std_logic_vector(Q);
                        end if;
                    end if;
                else
                    if sel_rem = '1' then
                        -- REMU: unsigned remainder, taken straight from the loop.
                        result <= std_logic_vector(R_unsigned);
                    else
                        -- DIVU: unsigned quotient, taken straight from the loop.
                        result <= std_logic_vector(Q_unsigned);
                    end if;
                end if;
            end if;
        -- else
        --     result <= (others => '0');
        end if;
    end process;

end rtl;