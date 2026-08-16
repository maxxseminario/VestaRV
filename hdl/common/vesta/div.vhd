library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.constants.all;

/* Restoring division for XLEN-bit signed and unsigned integers.
   It supports both division and remainder operations, as specified by the RISC-V ISA.
   One operation takes XLEN clock cycles plus one start cycle plus one done cycle, XLEN+2 in total. */

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
    -- The signed loop's magnitudes and partial remainder MUST stay unsigned: abs(INT_MIN) wraps to exactly 2**31, which a signed `R_var >= D_Abs` compare reads as negative and mis-steps the restoring loop.
    -- Signs are applied only at the result mux, never inside the loop.
    signal Q : unsigned(XLEN-1 downto 0);
    signal R : unsigned(XLEN-1 downto 0);
    signal cnt : integer range 0 to XLEN;
    signal Q_unsigned : unsigned(XLEN-1 downto 0);
    signal R_unsigned : unsigned(XLEN-1 downto 0);
    signal N_Abs, D_Abs : unsigned(XLEN-1 downto 0);
    signal neg_result : std_logic;
    signal neg_rem : std_logic;
    signal start_reg : std_logic;
    -- Dispatch-time copies of the operand ports: the result process decides the special cases (divide-by-zero, signed overflow, rem-by-zero passthrough) from these, never from the live a/b ports.
    -- The output therefore depends only on the operands captured at start, immune to regfile activity during the multi-cycle run.
    signal a_lat, b_lat : std_logic_vector(XLEN-1 downto 0);

    -- XLEN-wide special-case values from the RISC-V div/rem spec: zero, all-ones (-1 signed, maximum unsigned), and the most-negative signed integer, which is the overflow operand.
    constant DIV_ZERO_X    : std_logic_vector(XLEN-1 downto 0) := (others => '0');
    constant DIV_ALLONES_X : std_logic_vector(XLEN-1 downto 0) := (others => '1');
    constant DIV_MININT_X  : std_logic_vector(XLEN-1 downto 0) := (XLEN-1 => '1', others => '0');

begin

    -- The unit is ready whenever it is not stepping through a division.
    rdy <= '1' when (resetn = '0' or state = IDLE or state = COMPLETED) else '0';

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
            complete <= '0';
    
        elsif rising_edge(clk) then
            case state is
                when IDLE =>       -- Wait for a rising start strobe, then latch operands and arm the loop.
                    complete <= '0';
                    
                    if start = '1' and start_reg = '0' then
                        -- Latch inputs and initialize the loop state.
                        a_lat <= a;
                        b_lat <= b;
                        if sel_signed = '1' then
                            N <= signed(a);
                            D <= signed(b);
                            -- abs() on signed wraps at INT_MIN and returns x"80000000", which read as unsigned is the correct magnitude 2**31.
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
                    end if;
                    
                    start_reg <= start;
                when WORK =>       -- One restoring step per clock, from bit XLEN-1 down to bit 0.
                    if sel_signed = '1' then
                        R_var := shift_left(R, 1);
                        R_var(0) := N_Abs(cnt);
                        Q_var := Q;
                        -- Keep this compare unsigned: a signed one mis-reads a 2**31 magnitude as negative.
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
                    state <= IDLE;
            end case;
        end if;

    end process;

    

    -- Result mux: applies the RISC-V special cases first, then the sign to the loop's magnitude result.
    process(resetn, state, complete, a_lat, b_lat, sel_rem, sel_signed, neg_rem, R, neg_result, Q, R_unsigned, Q_unsigned)
    begin
        if resetn = '0' then
            result <= (others => '0');
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
                        -- REM: signed remainder; R is unsigned, so negation casts to signed because numeric_std defines unary "-" for signed only.
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
        end if;
    end process;

end rtl;