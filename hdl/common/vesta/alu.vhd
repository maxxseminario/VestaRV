library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.constants.all;

entity alu is
    generic (
        -- Core ISA feature switches. Decode already traps disabled extensions
        -- upstream (maindec); these additionally prune the execution hardware
        -- (multipliers, the iterative divider, AMO min/max, Zb* logic) so a
        -- disabled extension costs no area at synthesis.
        ENABLE_MUL      : boolean := true;
        ENABLE_DIV      : boolean := true;
        ENABLE_ATOMICS  : boolean := true;
        ENABLE_BITMANIP : boolean := true;
        -- X0 ISA-extension scaffolding (default false; the arithmetic/crypto
        -- op cases are added by the named phase -- these arrive unused for now).
        ENABLE_ZICOND   : boolean := false;  -- X1 (Zicond): consumed from phase X1 on; scaffolded X0
        ENABLE_ZBKB     : boolean := false;  -- X3 (Zbkb): consumed from phase X3 on; scaffolded X0
        ENABLE_ZBKC     : boolean := false;  -- X3 (Zbkc): consumed from phase X3 on; scaffolded X0
        ENABLE_ZBKX     : boolean := false;  -- X3 (Zbkx): consumed from phase X3 on; scaffolded X0
        ENABLE_ZKN      : boolean := false;  -- X3 (Zkn): consumed from phase X3 on; scaffolded X0
        ENABLE_ZFINX    : boolean := false   -- X4 (Zfinx): consumed from phase X4 on; scaffolded X0
    );
    port (
        resetn      : in  std_logic;
        clk         : in  std_logic;
        a, b        : in  std_logic_vector(XLEN-1 downto 0);
        alu_control : in  std_logic_vector(5 downto 0);  
        div_start   : in  std_logic;  -- Start signal from CPU to initiate division
        ALU_result  : out std_logic_vector(XLEN-1 downto 0); 
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
            a          : in  std_logic_vector(XLEN-1 downto 0);  -- Dividend
            b          : in  std_logic_vector(XLEN-1 downto 0);  -- Divisor
            sel_signed : in  std_logic;                      -- '1' for signed division, '0' for unsigned
            sel_rem    : in  std_logic;                      -- '1' for remainder (rem/remu), '0' for quotient (div/divu)
            result     : out std_logic_vector(XLEN-1 downto 0);
            complete   : out std_logic;
            rdy        : out std_logic
        );
    end component;


    -- Function for carry-less multiplication
    function clmul_64(op1 : std_logic_vector(XLEN-1 downto 0); 
                      op2 : std_logic_vector(XLEN-1 downto 0)) 
                      return std_logic_vector is
        variable result : std_logic_vector(2*XLEN-1 downto 0);
        variable temp : std_logic_vector(2*XLEN-1 downto 0);
    begin
        result := (others => '0');
        for i in 0 to XLEN-1 loop
            if op2(i) = '1' then
                temp := (others => '0');
                temp(i+XLEN-1 downto i) := op1;
                result := result xor temp;
            end if;
        end loop;
        return result;
    end function;

    -- Function to count leading zeros
    function count_leading_zeros(input : std_logic_vector(XLEN-1 downto 0)) return integer is
        variable count : integer := 0;
    begin
        for i in XLEN-1 downto 0 loop
            if input(i) = '1' then
                return count;
            else
                count := count + 1;
            end if;
        end loop;
        return XLEN;
    end function;

    -- Function to count trailing zeros
    function count_trailing_zeros(input : std_logic_vector(XLEN-1 downto 0)) return integer is
        variable count : integer := 0;
    begin
        for i in 0 to XLEN-1 loop
            if input(i) = '1' then
                return count;
            else
                count := count + 1;
            end if;
        end loop;
        return XLEN;
    end function;

    -- Function to count set bits (population count)
    function count_ones(input : std_logic_vector(XLEN-1 downto 0)) return integer is
        variable count : integer := 0;
    begin
        for i in 0 to XLEN-1 loop
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
    signal ResultSignal : std_logic_vector(XLEN-1 downto 0);

    -- XLEN-wide zero (comparison constant; slv "=" on unequal lengths is
    -- silently false, so never compare against a literal of another width)
    constant ALU_ZERO_X : std_logic_vector(XLEN-1 downto 0) := (others => '0');

    -- Divider Signals 
    signal div_sel_signed   : std_logic;
    signal div_sel_rem      : std_logic;
    signal div_result       : std_logic_vector(XLEN-1 downto 0);
    signal div_complete     : std_logic;
    signal div_rdy          : std_logic;
    signal div_start_rq     : std_logic;

    signal div_rq : std_logic;

    signal clr_div_start_rq : std_logic;

    signal signed_a : signed(XLEN-1 downto 0);
    signal signed_b : signed(XLEN-1 downto 0);
    signal unsigned_a : unsigned(XLEN-1 downto 0);
    signal unsigned_b : unsigned(XLEN-1 downto 0);

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
        variable mult_result : std_logic_vector(2*XLEN-1 downto 0);
        variable shift_amount : integer;

        -- RV32 Zbs Bit Manipulation
        variable bit_index : integer;
        variable bit_mask  : std_logic_vector(XLEN-1 downto 0);

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
                    ResultSignal <= std_logic_vector(shift_left(unsigned(a), to_integer(unsigned(b(SHAMT_W-1 downto 0))))); 
                when "000111" => -- Shift Right (Logical)
                    ResultSignal <= std_logic_vector(shift_right(unsigned(a), to_integer(unsigned(b(SHAMT_W-1 downto 0))))); 
                when "001000" => -- Shift Right Arithmetic
                    ResultSignal <= std_logic_vector(shift_right(signed(a), to_integer(unsigned(b(SHAMT_W-1 downto 0)))));
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
                    if ENABLE_MUL then
                        mult_result := std_logic_vector(signed(a)*signed(b));
                        ResultSignal <= mult_result(XLEN-1 downto 0);
                    end if;
                when "001101" => -- MULH (signed * signed, high XLEN bits)
                    if ENABLE_MUL then
                        mult_result := std_logic_vector(signed(a)*signed(b));
                        ResultSignal <= mult_result(2*XLEN-1 downto XLEN);
                    end if;
                when "001110" => -- MULHU (unsigned * unsigned, high XLEN bits)
                    if ENABLE_MUL then
                        mult_result := std_logic_vector(unsigned(a)*unsigned(b));
                        ResultSignal <= mult_result(2*XLEN-1 downto XLEN);
                    end if;
                when "001111" => -- MULHSU
                    if ENABLE_MUL then
                        mult_result := std_logic_vector(resize(signed(a) * signed('0' & b), 2*XLEN));
                        ResultSignal <= mult_result(2*XLEN-1 downto XLEN);
                    end if;
                when "010000" | "010001" | "010010" | "010011" => -- Division operations
                    if ENABLE_DIV then
                        div_start_rq <= '1';
                        if alu_state = ALU_DIV_WAIT or alu_state = ALU_DIV_DONE then
                            div_start_rq <= '0';
                            if div_complete = '1' then
                                ResultSignal <= div_result;
                                div_start_rq <= '0';
                            end if;
                        end if;
                    end if;
                    
                -- ==========================================
                -- RV32A Atomic MIN/MAX operations (6-bit encoding)
                -- ==========================================
                when "010100" => -- AMOMIN (signed)
                    if ENABLE_ATOMICS then
                        if signed(a) < signed(b) then
                            ResultSignal <= a;
                        else
                            ResultSignal <= b;
                        end if;
                    end if;

                when "010101" => -- AMOMAX (signed)
                    if ENABLE_ATOMICS then
                        if signed(a) > signed(b) then
                            ResultSignal <= a;
                        else
                            ResultSignal <= b;
                        end if;
                    end if;

                when "010110" => -- AMOMINU (unsigned)
                    if ENABLE_ATOMICS then
                        if unsigned(a) < unsigned(b) then
                            ResultSignal <= a;
                        else
                            ResultSignal <= b;
                        end if;
                    end if;

                when "010111" => -- AMOMAXU (unsigned)
                    if ENABLE_ATOMICS then
                        if unsigned(a) > unsigned(b) then
                            ResultSignal <= a;
                        else
                            ResultSignal <= b;
                        end if;
                    end if;

                -- ==========================================
                -- RV32 Zba Shift-and-Add Instructions
                -- ==========================================
                when "011000" => -- SH1ADD: rd = (rs1 << 1) + rs2
                    if ENABLE_BITMANIP then
                        ResultSignal <= std_logic_vector(unsigned(a(XLEN-2 downto 0) & '0') + unsigned(b));
                    end if;

                when "011001" => -- SH2ADD: rd = (rs1 << 2) + rs2
                    if ENABLE_BITMANIP then
                        ResultSignal <= std_logic_vector(unsigned(a(XLEN-3 downto 0) & "00") + unsigned(b));
                    end if;

                when "011010" => -- SH3ADD: rd = (rs1 << 3) + rs2
                    if ENABLE_BITMANIP then
                        ResultSignal <= std_logic_vector(unsigned(a(XLEN-4 downto 0) & "000") + unsigned(b));
                    end if;

                -- ==========================================
                -- RV32 Zbb Basic Bit-manipulation Instructions
                -- ==========================================
                
                -- Logical operations with complement
                when "011011" => -- ANDN: rd = rs1 & ~rs2
                    if ENABLE_BITMANIP then
                        ResultSignal <= a and (not b);
                    end if;

                when "011100" => -- ORN: rd = rs1 | ~rs2
                    if ENABLE_BITMANIP then
                        ResultSignal <= a or (not b);
                    end if;

                when "011101" => -- XNOR: rd = ~(rs1 ^ rs2)
                    if ENABLE_BITMANIP then
                        ResultSignal <= not (a xor b);
                    end if;

                -- Min/Max operations (Zbb versions)
                when "011110" => -- MIN (signed)
                    if ENABLE_BITMANIP then
                        if signed(a) < signed(b) then
                            ResultSignal <= a;
                        else
                            ResultSignal <= b;
                        end if;
                    end if;

                when "011111" => -- MINU (unsigned)
                    if ENABLE_BITMANIP then
                        if unsigned(a) < unsigned(b) then
                            ResultSignal <= a;
                        else
                            ResultSignal <= b;
                        end if;
                    end if;

                when "100000" => -- MAX (signed)
                    if ENABLE_BITMANIP then
                        if signed(a) > signed(b) then
                            ResultSignal <= a;
                        else
                            ResultSignal <= b;
                        end if;
                    end if;

                when "100001" => -- MAXU (unsigned)
                    if ENABLE_BITMANIP then
                        if unsigned(a) > unsigned(b) then
                            ResultSignal <= a;
                        else
                            ResultSignal <= b;
                        end if;
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
                    if ENABLE_BITMANIP then
                        shift_amount := to_integer(unsigned(b(SHAMT_W-1 downto 0)));
                        ResultSignal <= std_logic_vector(rotate_left(unsigned(a), shift_amount)); -- ieee_numeric_std has rotate_left function
                    end if;

                when "100011" => -- ROR/RORI: rotate right
                    if ENABLE_BITMANIP then
                        shift_amount := to_integer(unsigned(b(SHAMT_W-1 downto 0)));
                        ResultSignal <= std_logic_vector(rotate_right(unsigned(a), shift_amount));
                    end if;

                -- Bit counting operations
                when "100100" => -- CLZ: count leading zeros
                    if ENABLE_BITMANIP then
                        ResultSignal <= std_logic_vector(to_unsigned(count_leading_zeros(a), XLEN));
                    end if;

                when "100101" => -- CTZ: count trailing zeros
                    if ENABLE_BITMANIP then
                        ResultSignal <= std_logic_vector(to_unsigned(count_trailing_zeros(a), XLEN));
                    end if;

                when "100110" => -- CPOP: population count (count ones)
                    if ENABLE_BITMANIP then
                        ResultSignal <= std_logic_vector(to_unsigned(count_ones(a), XLEN));
                    end if;

                -- Sign/Zero extension
                when "100111" => -- SEXT.B: sign extend byte
                    if ENABLE_BITMANIP then
                        ResultSignal <= (XLEN-1 downto 8 => a(7)) & a(7 downto 0);
                    end if;

                when "101000" => -- SEXT.H: sign extend halfword
                    if ENABLE_BITMANIP then
                        ResultSignal <= (XLEN-1 downto 16 => a(15)) & a(15 downto 0);
                    end if;

                when "101001" => -- ZEXT.H: zero extend halfword
                    if ENABLE_BITMANIP then
                        ResultSignal <= (XLEN-1 downto 16 => '0') & a(15 downto 0);
                    end if;

                -- Byte operations
                when "101010" => -- ORC.B
                    if ENABLE_BITMANIP then
                        for i in 0 to XLEN_BYTES-1 loop
                            if a(i*8+7 downto i*8) /= x"00" then
                                ResultSignal(i*8+7 downto i*8) <= (others => '1');
                            else
                                ResultSignal(i*8+7 downto i*8) <= (others => '0');
                            end if;
                        end loop;
                    end if;

                when "101011" => -- REV8: byte reverse (endianness swap)
                    if ENABLE_BITMANIP then
                        for i in 0 to XLEN_BYTES-1 loop
                            ResultSignal(XLEN-1-i*8 downto XLEN-8-i*8) <= a(i*8+7 downto i*8);
                        end loop;
                    end if;


                -- ==========================================
                -- RV32 Zbs Single-bit Instructions
                -- ==========================================
                when "101100" => -- BCLR/BCLRI: Bit clear (rd = rs1 & ~(1 << rs2))
                    if ENABLE_BITMANIP then
                        bit_index := to_integer(unsigned(b(SHAMT_W-1 downto 0)));
                        bit_mask := (others => '1');
                        bit_mask(bit_index) := '0';
                        ResultSignal <= a and bit_mask;
                    end if;

                when "101101" => -- BEXT/BEXTI: Bit extract (rd = (rs1 >> rs2) & 1)
                    if ENABLE_BITMANIP then
                        bit_index := to_integer(unsigned(b(SHAMT_W-1 downto 0)));
                        ResultSignal <= (others => '0');
                        ResultSignal(0) <= a(bit_index);
                    end if;

                when "101110" => -- BINV/BINVI: Bit invert (rd = rs1 ^ (1 << rs2))
                    if ENABLE_BITMANIP then
                        bit_index := to_integer(unsigned(b(SHAMT_W-1 downto 0)));
                        bit_mask := (others => '0');
                        bit_mask(bit_index) := '1';
                        ResultSignal <= a xor bit_mask;
                    end if;

                when "101111" => -- BSET/BSETI: Bit set (rd = rs1 | (1 << rs2))
                    if ENABLE_BITMANIP then
                        bit_index := to_integer(unsigned(b(SHAMT_W-1 downto 0)));
                        bit_mask := (others => '0');
                        bit_mask(bit_index) := '1';
                        ResultSignal <= a or bit_mask;
                    end if;


                -- ==========================================
                -- RV32 Zbc Carry-less Multiplication Instructions
                -- ==========================================
                when "110000" => -- CLMUL: Carry-less multiply (low part)
                    if ENABLE_BITMANIP then
                        mult_result := clmul_64(a, b);
                        ResultSignal <= mult_result(XLEN-1 downto 0);
                    end if;

                when "110001" => -- CLMULH: Carry-less multiply (high part)
                    if ENABLE_BITMANIP then
                        mult_result := clmul_64(a, b);
                        ResultSignal <= mult_result(2*XLEN-1 downto XLEN);
                    end if;

                when "110010" => -- CLMULR: Carry-less multiply (reversed)
                    -- Reverse operand order for polynomial reduction
                    if ENABLE_BITMANIP then
                        mult_result := clmul_64(a, b);
                        ResultSignal <= mult_result(2*XLEN-2 downto XLEN-1);
                    end if;

                -- ==========================================
                -- RV32 Zicond Conditional-Zero Instructions
                -- (a = rs1, b = rs2)
                -- ==========================================
                when "110011" => -- CZERO.EQZ: rd = (rs2==0) ? 0 : rs1
                    if ENABLE_ZICOND then
                        if b = ALU_ZERO_X then
                            ResultSignal <= (others => '0');
                        else
                            ResultSignal <= a;
                        end if;
                    end if;

                when "110100" => -- CZERO.NEZ: rd = (rs2!=0) ? 0 : rs1
                    if ENABLE_ZICOND then
                        if b /= ALU_ZERO_X then
                            ResultSignal <= (others => '0');
                        else
                            ResultSignal <= a;
                        end if;
                    end if;


                when others =>
                    ResultSignal <= (others => '0');
            end case;
        end if;
    end process;

    -- The iterative divider only exists when the DIV feature is enabled; with
    -- it disabled the decode traps DIV/DIVU/REM/REMU upstream and these ports
    -- are tied to benign idle values (rdy='1' keeps the ALU FSM sane).
    gen_div: if ENABLE_DIV generate
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
    end generate;

    gen_no_div: if not ENABLE_DIV generate
        div_result   <= (others => '0');
        div_complete <= '0';
        div_rdy      <= '1';
    end generate;

    ALU_result <= ResultSignal; 
    
    checkZero: process(ResultSignal)
    begin
        if ResultSignal = ALU_ZERO_X then
            Zero <= '1';
        else
            Zero <= '0';
        end if;
    end process;

end architecture behav;



