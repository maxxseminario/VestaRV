library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity alu is
    port (
        resetn      : in  std_logic;
        clk         : in  std_logic;
        a, b        : in  std_logic_vector(31 downto 0);
        alu_control : in  std_logic_vector(5 downto 0);  
        div_start   : in  std_logic;  -- Start signal from CPU to initiate division
        ALU_result  : out std_logic_vector(31 downto 0); 
        alu_done    : out std_logic;
        Zero        : out std_logic
    );
end entity alu;

architecture behav of alu is

    component div
        port (
            resetn     : in  std_logic;
            clk        : in  std_logic;
            start      : in  std_logic;
            a          : in  std_logic_vector(31 downto 0);  -- Dividend
            b          : in  std_logic_vector(31 downto 0);  -- Divisor
            sel_signed : in  std_logic;                      -- '1' for signed division, '0' for unsigned
            sel_rem    : in  std_logic;                      -- '1' for remainder (rem/remu), '0' for quotient (div/divu)
            result     : out std_logic_vector(31 downto 0);
            complete   : out std_logic;
            rdy        : out std_logic
        );
    end component;


    -- Function for carry-less multiplication
    function clmul_64(op1 : std_logic_vector(31 downto 0); 
                      op2 : std_logic_vector(31 downto 0)) 
                      return std_logic_vector is
        variable result : std_logic_vector(63 downto 0);
        variable temp : std_logic_vector(63 downto 0);
    begin
        result := (others => '0');
        for i in 0 to 31 loop
            if op2(i) = '1' then
                temp := (others => '0');
                temp(i+31 downto i) := op1;
                result := result xor temp;
            end if;
        end loop;
        return result;
    end function;

    -- Function to count leading zeros
    function count_leading_zeros(input : std_logic_vector(31 downto 0)) return integer is
        variable count : integer := 0;
    begin
        for i in 31 downto 0 loop
            if input(i) = '1' then
                return count;
            else
                count := count + 1;
            end if;
        end loop;
        return 32;
    end function;

    -- Function to count trailing zeros
    function count_trailing_zeros(input : std_logic_vector(31 downto 0)) return integer is
        variable count : integer := 0;
    begin
        for i in 0 to 31 loop
            if input(i) = '1' then
                return count;
            else
                count := count + 1;
            end if;
        end loop;
        return 32;
    end function;

    -- Function to count set bits (population count)
    function count_ones(input : std_logic_vector(31 downto 0)) return integer is
        variable count : integer := 0;
    begin
        for i in 0 to 31 loop
            if input(i) = '1' then
                count := count + 1;
            end if;
        end loop;
        return count;
    end function;

    -- -- Function to perform rotate left
    -- function rol32(x: std_logic_vector(31 downto 0); s: integer) return std_logic_vector is
    --     variable result: std_logic_vector(31 downto 0);
    -- begin
    --     for i in 0 to 31 loop
    --         result(i) := x((i - s + 32) mod 32);
    --     end loop;
    --     return result;
    -- end function;

    -- -- Function to perform rotate right
    -- function ror32(x: std_logic_vector(31 downto 0); s: integer) return std_logic_vector is
    --     variable result: std_logic_vector(31 downto 0);
    -- begin
    --     for i in 0 to 31 loop
    --         result(i) := x((i + s) mod 32);
    --     end loop;
    --     return result;
    -- end function;


    type alu_state_t is (ALU_IDLE, ALU_DIV_WAIT, ALU_DIV_DONE);
    signal alu_state : alu_state_t;
    signal div_operation : std_logic;
    signal ResultSignal : std_logic_vector(31 downto 0);

    -- Divider Signals 
    signal div_sel_signed   : std_logic;
    signal div_sel_rem      : std_logic;
    signal div_result       : std_logic_vector(31 downto 0);
    signal div_complete     : std_logic;
    signal div_rdy          : std_logic;
    signal div_start_rq     : std_logic;

    signal div_rq : std_logic;

    signal clr_div_start_rq : std_logic;

    signal signed_a : signed(31 downto 0);
    signal signed_b : signed(31 downto 0);
    signal unsigned_a : unsigned(31 downto 0);
    signal unsigned_b : unsigned(31 downto 0);

begin

    -- Detect division operations (updated for 6-bit control)
    div_operation <= '1' when (alu_control = "010000" or alu_control = "010001" or 
                              alu_control = "010010" or alu_control = "010011") else '0';

    signed_a   <= signed(a);
    signed_b   <= signed(b);
    unsigned_a <= unsigned(a);
    unsigned_b <= unsigned(b);

    alu_done <= '1' when alu_state = ALU_IDLE else
                '1' when div_complete = '1' else
                '0';

    -- ALU FSM
    fsm: process(clk, resetn)
    begin
        if resetn = '0' then
            alu_state <= ALU_IDLE;
            div_sel_signed <= '0';
            div_sel_rem <= '0';
            div_rq <= '0';
        elsif rising_edge(clk) then
            case alu_state is
                when ALU_IDLE =>
                    if div_start_rq = '1' and div_rdy = '1' then
                        div_rq <= '1';
                        case alu_control is
                            when "010000" => -- DIV
                                div_sel_signed <= '1';
                                div_sel_rem <= '0';
                            when "010001" => -- DIVU
                                div_sel_signed <= '0';
                                div_sel_rem <= '0';
                            when "010010" => -- REM
                                div_sel_signed <= '1';
                                div_sel_rem <= '1';
                            when "010011" => -- REMU
                                div_sel_signed <= '0';
                                div_sel_rem <= '1';
                            when others =>
                        end case;
                        alu_state <= ALU_DIV_WAIT;
                    end if;
                    
                when ALU_DIV_WAIT =>
                    if div_complete = '1' then
                        alu_state <= ALU_DIV_DONE;
                        div_rq <= '0';
                    end if;
                when ALU_DIV_DONE =>
                    alu_state <= ALU_IDLE;
                when others =>
                    alu_state <= ALU_IDLE;
            end case;
        end if;
    end process;

    process(a, b, alu_control, div_rdy, div_complete, alu_state, div_result, resetn)
        variable mult_result : std_logic_vector(63 downto 0);
        variable shift_amount : integer;

        -- RV32 Zbs Bit Manipulation
        variable bit_index : integer;
        variable bit_mask  : std_logic_vector(31 downto 0);

    begin
        if resetn = '0' then
            ResultSignal <= (others => '0');
            div_start_rq <= '0';
            mult_result := (others => '0');
        else
            mult_result := (others => '0');
            div_start_rq <= '0';
            ResultSignal <= (others => '0');

            case alu_control is
                -- ==========================================
                -- Original RV32I Instructions (6-bit encoding)
                -- ==========================================
                when "000000" => -- Addition
                    ResultSignal <= std_logic_vector(unsigned(a) + unsigned(b));
                when "000001" => -- Subtraction
                    ResultSignal <= std_logic_vector(unsigned(a) - unsigned(b));
                when "000010" => -- AND
                    ResultSignal <= a and b;
                when "000011" => -- OR
                    ResultSignal <= a or b;
                when "000100" => -- XOR
                    ResultSignal <= a xor b;
                when "000101" => -- SLT (Set if Less Than)
                    if signed(a) < signed(b) then
                        ResultSignal(0) <= '1';
                    end if;
                when "000110" => -- Shift Left (Logical)
                    ResultSignal <= std_logic_vector(shift_left(unsigned(a), to_integer(unsigned(b(4 downto 0))))); 
                when "000111" => -- Shift Right (Logical)
                    ResultSignal <= std_logic_vector(shift_right(unsigned(a), to_integer(unsigned(b(4 downto 0))))); 
                when "001000" => -- Shift Right Arithmetic
                    ResultSignal <= std_logic_vector(shift_right(signed(a), to_integer(unsigned(b(4 downto 0)))));
                when "001001" => -- SLTU (Set if Less Than Unsigned)
                    if unsigned(a) < unsigned(b) then
                        ResultSignal(0) <= '1';
                    end if;
                when "001010" => -- Pass B
                    ResultSignal <= b;
                when "001011" => -- Pass A (added for AMO)
                    ResultSignal <= a;

                -- ==========================================
                -- RV32M Multiply/Divide Extensions (6-bit encoding)
                -- ==========================================
                when "001100" => -- MUL (signed * signed, low 32 bits)
                    mult_result := std_logic_vector(signed(a)*signed(b));
                    ResultSignal <= mult_result(31 downto 0);
                when "001101" => -- MULH (signed * signed, high 32 bits)
                    mult_result := std_logic_vector(signed(a)*signed(b));
                    ResultSignal <= mult_result(63 downto 32);
                when "001110" => -- MULHU (unsigned * unsigned, high 32 bits)
                    mult_result := std_logic_vector(unsigned(a)*unsigned(b));
                    ResultSignal <= mult_result(63 downto 32);
                when "001111" => -- MULHSU 
                    mult_result := std_logic_vector(resize(signed(a) * signed('0' & b), 64)); 
                    ResultSignal <= mult_result(63 downto 32);
                when "010000" | "010001" | "010010" | "010011" => -- Division operations
                    div_start_rq <= '1';
                    if alu_state = ALU_DIV_WAIT or alu_state = ALU_DIV_DONE then 
                        div_start_rq <= '0';
                        if div_complete = '1' then
                            ResultSignal <= div_result;
                            div_start_rq <= '0';
                        end if;
                    end if;
                    
                -- ==========================================
                -- RV32A Atomic MIN/MAX operations (6-bit encoding)
                -- ==========================================
                when "010100" => -- AMOMIN (signed)
                    if signed(a) < signed(b) then
                        ResultSignal <= a;
                    else
                        ResultSignal <= b;
                    end if;
                    
                when "010101" => -- AMOMAX (signed)
                    if signed(a) > signed(b) then
                        ResultSignal <= a;
                    else
                        ResultSignal <= b;
                    end if;
                    
                when "010110" => -- AMOMINU (unsigned)
                    if unsigned(a) < unsigned(b) then
                        ResultSignal <= a;
                    else
                        ResultSignal <= b;
                    end if;
                    
                when "010111" => -- AMOMAXU (unsigned)
                    if unsigned(a) > unsigned(b) then
                        ResultSignal <= a;
                    else
                        ResultSignal <= b;
                    end if;

                -- ==========================================
                -- RV32 Zba Shift-and-Add Instructions
                -- ==========================================
                when "011000" => -- SH1ADD: rd = (rs1 << 1) + rs2
                    ResultSignal <= std_logic_vector(unsigned(a(30 downto 0) & '0') + unsigned(b));
                    
                when "011001" => -- SH2ADD: rd = (rs1 << 2) + rs2
                    ResultSignal <= std_logic_vector(unsigned(a(29 downto 0) & "00") + unsigned(b));
                    
                when "011010" => -- SH3ADD: rd = (rs1 << 3) + rs2
                    ResultSignal <= std_logic_vector(unsigned(a(28 downto 0) & "000") + unsigned(b));

                -- ==========================================
                -- RV32 Zbb Basic Bit-manipulation Instructions
                -- ==========================================
                
                -- Logical operations with complement
                when "011011" => -- ANDN: rd = rs1 & ~rs2
                    ResultSignal <= a and (not b);
                    
                when "011100" => -- ORN: rd = rs1 | ~rs2
                    ResultSignal <= a or (not b);
                    
                when "011101" => -- XNOR: rd = ~(rs1 ^ rs2)
                    ResultSignal <= not (a xor b);
                
                -- Min/Max operations (Zbb versions)
                when "011110" => -- MIN (signed)
                    if signed(a) < signed(b) then
                        ResultSignal <= a;
                    else
                        ResultSignal <= b;
                    end if;
                    
                when "011111" => -- MINU (unsigned)
                    if unsigned(a) < unsigned(b) then
                        ResultSignal <= a;
                    else
                        ResultSignal <= b;
                    end if;
                    
                when "100000" => -- MAX (signed)
                    if signed(a) > signed(b) then
                        ResultSignal <= a;
                    else
                        ResultSignal <= b;
                    end if;
                    
                when "100001" => -- MAXU (unsigned)
                    if unsigned(a) > unsigned(b) then
                        ResultSignal <= a;
                    else
                        ResultSignal <= b;
                    end if;
                
                -- Rotate operations
                -- when "100010" => -- ROL: rotate left
                --     shift_amount := to_integer(unsigned(b(4 downto 0)));
                --     ResultSignal <= rol32(a, shift_amount);
                    
                -- when "100011" => -- ROR/RORI: rotate right
                --     shift_amount := to_integer(unsigned(b(4 downto 0)));
                --     ResultSignal <= ror32(a, shift_amount);
                -- In the rotate operations section:
                when "100010" => -- ROL: rotate left
                    shift_amount := to_integer(unsigned(b(4 downto 0)));
                    ResultSignal <= std_logic_vector(rotate_left(unsigned(a), shift_amount)); -- ieee_numeric_std has rotate_left function
                    
                when "100011" => -- ROR/RORI: rotate right
                    shift_amount := to_integer(unsigned(b(4 downto 0)));
                    ResultSignal <= std_logic_vector(rotate_right(unsigned(a), shift_amount));
                
                -- Bit counting operations
                when "100100" => -- CLZ: count leading zeros
                    ResultSignal <= std_logic_vector(to_unsigned(count_leading_zeros(a), 32));
                    
                when "100101" => -- CTZ: count trailing zeros
                    ResultSignal <= std_logic_vector(to_unsigned(count_trailing_zeros(a), 32));
                    
                when "100110" => -- CPOP: population count (count ones)
                    ResultSignal <= std_logic_vector(to_unsigned(count_ones(a), 32));
                
                -- Sign/Zero extension
                when "100111" => -- SEXT.B: sign extend byte
                    ResultSignal <= (31 downto 8 => a(7)) & a(7 downto 0);
                    
                when "101000" => -- SEXT.H: sign extend halfword
                    ResultSignal <= (31 downto 16 => a(15)) & a(15 downto 0);
                    
                when "101001" => -- ZEXT.H: zero extend halfword
                    ResultSignal <= x"0000" & a(15 downto 0);
                
                -- Byte operations
                when "101010" => -- ORC.B
                    for i in 0 to 3 loop
                        if a(i*8+7 downto i*8) /= x"00" then
                            ResultSignal(i*8+7 downto i*8) <= (others => '1');
                        else
                            ResultSignal(i*8+7 downto i*8) <= (others => '0');
                        end if;
                    end loop;
                    
                when "101011" => -- REV8: byte reverse (endianness swap)
                    ResultSignal <= a(7 downto 0) & a(15 downto 8) & a(23 downto 16) & a(31 downto 24);


                -- ==========================================
                -- RV32 Zbs Single-bit Instructions
                -- ==========================================
                when "101100" => -- BCLR/BCLRI: Bit clear (rd = rs1 & ~(1 << rs2))
                    bit_index := to_integer(unsigned(b(4 downto 0)));
                    bit_mask := (others => '1');
                    bit_mask(bit_index) := '0';
                    ResultSignal <= a and bit_mask;
                    
                when "101101" => -- BEXT/BEXTI: Bit extract (rd = (rs1 >> rs2) & 1)
                    bit_index := to_integer(unsigned(b(4 downto 0)));
                    ResultSignal <= (others => '0');
                    ResultSignal(0) <= a(bit_index);
                    
                when "101110" => -- BINV/BINVI: Bit invert (rd = rs1 ^ (1 << rs2))
                    bit_index := to_integer(unsigned(b(4 downto 0)));
                    bit_mask := (others => '0');
                    bit_mask(bit_index) := '1';
                    ResultSignal <= a xor bit_mask;
                    
                when "101111" => -- BSET/BSETI: Bit set (rd = rs1 | (1 << rs2))
                    bit_index := to_integer(unsigned(b(4 downto 0)));
                    bit_mask := (others => '0');
                    bit_mask(bit_index) := '1';
                    ResultSignal <= a or bit_mask;


                -- ==========================================
                -- RV32 Zbc Carry-less Multiplication Instructions
                -- ==========================================
                when "110000" => -- CLMUL: Carry-less multiply (low part)
                    mult_result := clmul_64(a, b);
                    ResultSignal <= mult_result(31 downto 0);
                    
                when "110001" => -- CLMULH: Carry-less multiply (high part)
                    mult_result := clmul_64(a, b);
                    ResultSignal <= mult_result(63 downto 32);
                    
                when "110010" => -- CLMULR: Carry-less multiply (reversed)
                    -- Reverse operand order for polynomial reduction
                    mult_result := clmul_64(a, b);
                    ResultSignal <= mult_result(62 downto 31);


                when others =>
                    ResultSignal <= (others => '0');
            end case;
        end if;
    end process;

    divider : div
    port map (
        resetn     => resetn,
        clk        => clk,
        start      => div_start,
        a          => a,
        b          => b,
        sel_signed => div_sel_signed,
        sel_rem    => div_sel_rem,
        result     => div_result,
        complete   => div_complete,
        rdy        => div_rdy
    );

    ALU_result <= ResultSignal; 
    
    checkZero: process(ResultSignal)
    begin
        if ResultSignal = x"00000000" then
            Zero <= '1';
        else
            Zero <= '0';
        end if;
    end process;

end architecture behav;



