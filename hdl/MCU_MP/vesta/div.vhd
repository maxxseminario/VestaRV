library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.constants.all;

-- This code implements the restoring division algorithm for 32-bit signed and unsigned integers.
-- It supports both division and remainder operations, as specified by the RISC-V ISA.
-- Takes 32 clock cycles +1 start cycle +1 done cycle (34 total) to complete the operation.

entity div is
    port (
        resetn     : in  std_logic;
        clk        : in  std_logic;
        start      : in  std_logic;
        a          : in  std_logic_vector(31 downto 0);  -- Dividend
        b          : in  std_logic_vector(31 downto 0);  -- Divisor
        sel_signed : in  std_logic;                      -- '1' for signed division, '0' for unsigned
        sel_rem    : in  std_logic;                      -- '1' for remainder (rem/remu), '0' for quotient (div/divu)
        result     : out std_logic_vector(31 downto 0);  -- Quotient or Remainder
        complete   : out std_logic;                      -- '1' when division is in progress
        rdy        : out std_logic
    );
end div;

architecture rtl of div is

    type state_t is (IDLE, WORK, COMPLETED);
    signal state : state_t;
    signal N, D  : signed(31 downto 0);
    signal N_u, D_u : unsigned(31 downto 0);
    signal Q : signed(31 downto 0);
    signal R : signed(31 downto 0);
    signal cnt : integer range 0 to 32;
    signal Q_unsigned : unsigned(31 downto 0);
    signal R_unsigned : unsigned(31 downto 0);
    signal N_Abs, D_Abs : signed(31 downto 0);
    signal neg_result : std_logic;
    signal neg_rem : std_logic;
    signal start_reg : std_logic;

begin

    -- Simple rdy assignment based on state
    rdy <= '1' when (resetn = '0' or state = IDLE or state = COMPLETED) else '0';
    -- complete <= '1' when state = COMPLETED else '0';

    process(clk, resetn)
        variable R_var : signed(31 downto 0);
        variable Q_var : signed(31 downto 0);
        variable R_u_var : unsigned(31 downto 0);
        variable Q_u_var : unsigned(31 downto 0);
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
                        if sel_signed = '1' then
                            N <= signed(a);
                            D <= signed(b);
                            N_Abs <= abs(signed(a));
                            D_Abs <= abs(signed(b));
                            neg_result <= (a(31) xor b(31));
                            neg_rem <= a(31);       -- only dividend sign for remainder
                        else
                            N_u <= unsigned(a);
                            D_u <= unsigned(b);
                        end if;
                        Q <= (others => '0');
                        R <= (others => '0');
                        Q_unsigned <= (others => '0');
                        R_unsigned <= (others => '0');
                        cnt <= 31;
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

    

    process(resetn, state, complete, a, b, sel_rem, sel_signed, neg_rem, R, neg_result, Q, R_unsigned, Q_unsigned)
    begin
        if resetn = '0' then
            result <= (others => '0');
        -- elsif state = COMPLETED then
        elsif complete = '1' then
            -- Division by zero cases (RISC-V spec)
            if b = x"00000000" then
                if sel_rem = '1' then
                    result <= a; -- remu: operand a, rem: operand a
                else
                    if sel_signed = '1' then
                        result <= x"FFFFFFFF"; -- div: -1 (all 1's)
                    else
                        result <= x"FFFFFFFF"; -- divu: all 1's
                    end if;
                end if;
            -- Overflow case for signed division/remainder: a = 0x80000000, b = 0xFFFFFFFF
            elsif (sel_signed = '1') and (a = x"80000000") and (b = x"FFFFFFFF") then
                if sel_rem = '1' then
                    result <= x"00000000"; -- rem: 0
                else
                    result <= x"80000000"; -- div: 0x80000000
                end if;
            else
                if sel_signed = '1' then
                    if sel_rem = '1' then
                        -- REM: signed remainder
                        if neg_rem = '1' then
                            result <= std_logic_vector(-R);
                        else
                            result <= std_logic_vector(R);
                        end if;
                    else
                        -- DIV: signed division
                        if neg_result = '1' then
                            result <= std_logic_vector(-Q);
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