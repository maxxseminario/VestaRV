library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.constants.all;

entity alu is
    generic (
        -- Core ISA feature switches.
        -- maindec already traps disabled extensions at decode; these switches additionally prune the execution hardware (multipliers, iterative divider, AMO min/max, Zb* logic) so a disabled extension costs no area.
        ENABLE_MUL      : boolean := true;
        ENABLE_DIV      : boolean := true;
        ENABLE_ATOMICS  : boolean := true;
        ENABLE_BITMANIP : boolean := true;
        ENABLE_ZICOND   : boolean := false;  -- Zicond conditional zero
        ENABLE_ZBKB     : boolean := false;  -- Zbkb crypto bit-manip
        ENABLE_ZBKC     : boolean := false;  -- Zbkc carry-less multiply
        ENABLE_ZBKX     : boolean := false;  -- Zbkx crossbar permute
        ENABLE_ZKN      : boolean := false;  -- Zkn scalar crypto (AES, SHA)
        ENABLE_ZFINX    : boolean := false   -- Zfinx single-precision FP in the integer regfile
    );
    port (
        resetn      : in  std_logic;
        clk         : in  std_logic;
        a, b        : in  std_logic_vector(XLEN-1 downto 0);
        alu_control : in  std_logic_vector(6 downto 0);
        bs          : in  std_logic_vector(1 downto 0);   -- Zknd/Zkne AES byte-select (instr[31:30]); only used by the aes32* arms
        div_start   : in  std_logic;  -- Start signal from CPU to initiate division
        -- The ONE cycle in which the core is really dispatching a DIV/DIVU/REM/REMU, supplied as a positive qualification by the core FSM.
        -- It must NOT be re-derived from alu_control: alu_control decodes instr_curr, which in the compressed split-fetch bubble and in IRQ_SV / IRQ_JUMP / TRAP_STATE is not the instruction the hart is dispatching.
        div_dispatch : in  std_logic;
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


    -- Carry-less (GF(2)) multiply of two XLEN-bit words, returning the full 2*XLEN-bit product.
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

    -- Count leading zeros; an all-zero word returns XLEN.
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

    -- Count trailing zeros; an all-zero word returns XLEN.
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

    -- Count set bits (population count).
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


    /* ========== Zknd/Zkne AES-32 shared crypto primitives ==========
       ONE forward S-box and ONE inverse S-box (256 B each) serve all four aes32* ops through a single aes32_datapath() body byte-steered by bs, with the GF(2^8) MixColumn terms computed combinationally.
       Everything here must stay pure combinational, with fixed latency and data-independent timing, to hold the constant-time invariant. */
    type aes_sbox_t is array (0 to 255) of std_logic_vector(7 downto 0);

    constant AES_SBOX_FWD : aes_sbox_t := (
        x"63", x"7c", x"77", x"7b", x"f2", x"6b", x"6f", x"c5", x"30", x"01", x"67", x"2b", x"fe", x"d7", x"ab", x"76",
        x"ca", x"82", x"c9", x"7d", x"fa", x"59", x"47", x"f0", x"ad", x"d4", x"a2", x"af", x"9c", x"a4", x"72", x"c0",
        x"b7", x"fd", x"93", x"26", x"36", x"3f", x"f7", x"cc", x"34", x"a5", x"e5", x"f1", x"71", x"d8", x"31", x"15",
        x"04", x"c7", x"23", x"c3", x"18", x"96", x"05", x"9a", x"07", x"12", x"80", x"e2", x"eb", x"27", x"b2", x"75",
        x"09", x"83", x"2c", x"1a", x"1b", x"6e", x"5a", x"a0", x"52", x"3b", x"d6", x"b3", x"29", x"e3", x"2f", x"84",
        x"53", x"d1", x"00", x"ed", x"20", x"fc", x"b1", x"5b", x"6a", x"cb", x"be", x"39", x"4a", x"4c", x"58", x"cf",
        x"d0", x"ef", x"aa", x"fb", x"43", x"4d", x"33", x"85", x"45", x"f9", x"02", x"7f", x"50", x"3c", x"9f", x"a8",
        x"51", x"a3", x"40", x"8f", x"92", x"9d", x"38", x"f5", x"bc", x"b6", x"da", x"21", x"10", x"ff", x"f3", x"d2",
        x"cd", x"0c", x"13", x"ec", x"5f", x"97", x"44", x"17", x"c4", x"a7", x"7e", x"3d", x"64", x"5d", x"19", x"73",
        x"60", x"81", x"4f", x"dc", x"22", x"2a", x"90", x"88", x"46", x"ee", x"b8", x"14", x"de", x"5e", x"0b", x"db",
        x"e0", x"32", x"3a", x"0a", x"49", x"06", x"24", x"5c", x"c2", x"d3", x"ac", x"62", x"91", x"95", x"e4", x"79",
        x"e7", x"c8", x"37", x"6d", x"8d", x"d5", x"4e", x"a9", x"6c", x"56", x"f4", x"ea", x"65", x"7a", x"ae", x"08",
        x"ba", x"78", x"25", x"2e", x"1c", x"a6", x"b4", x"c6", x"e8", x"dd", x"74", x"1f", x"4b", x"bd", x"8b", x"8a",
        x"70", x"3e", x"b5", x"66", x"48", x"03", x"f6", x"0e", x"61", x"35", x"57", x"b9", x"86", x"c1", x"1d", x"9e",
        x"e1", x"f8", x"98", x"11", x"69", x"d9", x"8e", x"94", x"9b", x"1e", x"87", x"e9", x"ce", x"55", x"28", x"df",
        x"8c", x"a1", x"89", x"0d", x"bf", x"e6", x"42", x"68", x"41", x"99", x"2d", x"0f", x"b0", x"54", x"bb", x"16"
    );

    constant AES_SBOX_INV : aes_sbox_t := (
        x"52", x"09", x"6a", x"d5", x"30", x"36", x"a5", x"38", x"bf", x"40", x"a3", x"9e", x"81", x"f3", x"d7", x"fb",
        x"7c", x"e3", x"39", x"82", x"9b", x"2f", x"ff", x"87", x"34", x"8e", x"43", x"44", x"c4", x"de", x"e9", x"cb",
        x"54", x"7b", x"94", x"32", x"a6", x"c2", x"23", x"3d", x"ee", x"4c", x"95", x"0b", x"42", x"fa", x"c3", x"4e",
        x"08", x"2e", x"a1", x"66", x"28", x"d9", x"24", x"b2", x"76", x"5b", x"a2", x"49", x"6d", x"8b", x"d1", x"25",
        x"72", x"f8", x"f6", x"64", x"86", x"68", x"98", x"16", x"d4", x"a4", x"5c", x"cc", x"5d", x"65", x"b6", x"92",
        x"6c", x"70", x"48", x"50", x"fd", x"ed", x"b9", x"da", x"5e", x"15", x"46", x"57", x"a7", x"8d", x"9d", x"84",
        x"90", x"d8", x"ab", x"00", x"8c", x"bc", x"d3", x"0a", x"f7", x"e4", x"58", x"05", x"b8", x"b3", x"45", x"06",
        x"d0", x"2c", x"1e", x"8f", x"ca", x"3f", x"0f", x"02", x"c1", x"af", x"bd", x"03", x"01", x"13", x"8a", x"6b",
        x"3a", x"91", x"11", x"41", x"4f", x"67", x"dc", x"ea", x"97", x"f2", x"cf", x"ce", x"f0", x"b4", x"e6", x"73",
        x"96", x"ac", x"74", x"22", x"e7", x"ad", x"35", x"85", x"e2", x"f9", x"37", x"e8", x"1c", x"75", x"df", x"6e",
        x"47", x"f1", x"1a", x"71", x"1d", x"29", x"c5", x"89", x"6f", x"b7", x"62", x"0e", x"aa", x"18", x"be", x"1b",
        x"fc", x"56", x"3e", x"4b", x"c6", x"d2", x"79", x"20", x"9a", x"db", x"c0", x"fe", x"78", x"cd", x"5a", x"f4",
        x"1f", x"dd", x"a8", x"33", x"88", x"07", x"c7", x"31", x"b1", x"12", x"10", x"59", x"27", x"80", x"ec", x"5f",
        x"60", x"51", x"7f", x"a9", x"19", x"b5", x"4a", x"0d", x"2d", x"e5", x"7a", x"9f", x"93", x"c9", x"9c", x"ef",
        x"a0", x"e0", x"3b", x"4d", x"ae", x"2a", x"f5", x"b0", x"c8", x"eb", x"bb", x"3c", x"83", x"53", x"99", x"61",
        x"17", x"2b", x"04", x"7e", x"ba", x"77", x"d6", x"26", x"e1", x"69", x"14", x"63", x"55", x"21", x"0c", x"7d"
    );

    -- GF(2^8) xtime (multiply by x, AES reduction polynomial 0x11B).
    function aes_xtime(bin : std_logic_vector(7 downto 0)) return std_logic_vector is
        variable r : std_logic_vector(7 downto 0);
    begin
        r := bin(6 downto 0) & '0';
        if bin(7) = '1' then
            r := r xor x"1b";
        end if;
        return r;
    end function;

    -- GF(2^8) multiply of x by a small constant y (2, 3, 9, b, d, e) via peasant multiplication over xtime: ONE routine covers every MixColumn term.
    function aes_gfmul(x : std_logic_vector(7 downto 0);
                       y : std_logic_vector(3 downto 0)) return std_logic_vector is
        variable acc : std_logic_vector(7 downto 0) := (others => '0');
        variable tmp : std_logic_vector(7 downto 0);
    begin
        tmp := x;
        for i in 0 to 3 loop
            if y(i) = '1' then
                acc := acc xor tmp;
            end if;
            tmp := aes_xtime(tmp);
        end loop;
        return acc;
    end function;

    /* Shared aes32 datapath (rs1 = a_in, rs2 = b_in, byte-select bs): decrypt picks the inverse S-box and inverse MixColumn constants, and mix adds the MixColumn step.
         si = byte bs of rs2 ; so = SBOX(si)
         x  = MixColumn(so) (or zext(so) for the *si ops)
         rd = rs1 XOR rol32(x, 8*bs) */
    function aes32_datapath(a_in, b_in : std_logic_vector(31 downto 0);
                            bsel       : std_logic_vector(1 downto 0);
                            decrypt    : boolean;
                            mix        : boolean) return std_logic_vector is
        variable idx    : integer;
        variable shamt  : integer;
        variable bshift : std_logic_vector(31 downto 0);
        variable si     : std_logic_vector(7 downto 0);
        variable so     : std_logic_vector(7 downto 0);
        variable x32    : std_logic_vector(31 downto 0);
        variable rot    : std_logic_vector(31 downto 0);
    begin
        idx   := to_integer(unsigned(bsel));
        shamt := 8 * idx;
        -- si = (rs2 >> 8*bs)[7:0]  (byte bs of rs2)
        bshift := std_logic_vector(shift_right(unsigned(b_in), shamt));
        si     := bshift(7 downto 0);
        if decrypt then
            so := AES_SBOX_INV(to_integer(unsigned(si)));
        else
            so := AES_SBOX_FWD(to_integer(unsigned(si)));
        end if;
        if mix then
            if decrypt then
                -- inverse MixColumn column {b, d, 9, e}
                x32 := aes_gfmul(so, x"b") & aes_gfmul(so, x"d") &
                       aes_gfmul(so, x"9") & aes_gfmul(so, x"e");
            else
                -- forward MixColumn column {3, s, s, 2}
                x32 := aes_gfmul(so, x"3") & so & so & aes_gfmul(so, x"2");
            end if;
        else
            x32 := x"000000" & so;
        end if;
        -- rd = rs1 XOR rol32(x32, 8*bs)
        rot := std_logic_vector(rotate_left(unsigned(x32), shamt));
        return a_in xor rot;
    end function;

    type alu_state_t is (ALU_IDLE, ALU_DIV_WAIT, ALU_DIV_DONE);
    signal alu_state : alu_state_t;
    signal div_operation : std_logic;
    signal ResultSignal : std_logic_vector(XLEN-1 downto 0);

    -- XLEN-wide zero, used as a comparison constant: an slv equality on unequal lengths is silently false, so never compare against a literal of another width.
    constant ALU_ZERO_X : std_logic_vector(XLEN-1 downto 0) := (others => '0');

    -- Divider interface signals
    signal div_sel_signed   : std_logic;
    signal div_sel_rem      : std_logic;
    signal div_result       : std_logic_vector(XLEN-1 downto 0);
    signal div_complete     : std_logic;
    signal div_rdy          : std_logic;
    -- div_operation, div_rq and clr_div_start_rq are dead: nothing in the design consumes them.

    signal div_rq : std_logic;

    signal clr_div_start_rq : std_logic;

    signal signed_a : signed(XLEN-1 downto 0);
    signal signed_b : signed(XLEN-1 downto 0);
    signal unsigned_a : unsigned(XLEN-1 downto 0);
    signal unsigned_b : unsigned(XLEN-1 downto 0);

begin

    -- Detect a divide op from alu_control (DIV/DIVU/REM/REMU); dead, as nothing consumes div_operation.
    div_operation <= '1' when (alu_control = "0010000" or alu_control = "0010001" or 
                              alu_control = "0010010" or alu_control = "0010011") else '0';

    signed_a   <= signed(a);
    signed_b   <= signed(b);
    unsigned_a <= unsigned(a);
    unsigned_b <= unsigned(b);

    -- The ALU retires in one cycle except while the iterative divider is running, so alu_done is high in ALU_IDLE and again on the divider's completion cycle.
    alu_done <= '1' when alu_state = ALU_IDLE else
                '1' when div_complete = '1' else
                '0';

    -- ALU FSM: idle unless an iterative divide is in flight, and it latches the divider's selects at dispatch.
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
                    -- The guard MUST be div_dispatch, never a bare decode of alu_control: in the split-fetch bubble instr_curr is held at the previous instruction, so an unqualified guard latches the previous divide's selects and then sticks in ALU_DIV_WAIT until a later, wrongly-configured divide completes.
                    if div_dispatch = '1' and div_rdy = '1' then
                        div_rq <= '1';
                        case alu_control is
                            when "0010000" => -- DIV
                                div_sel_signed <= '1';
                                div_sel_rem <= '0';
                            when "0010001" => -- DIVU
                                div_sel_signed <= '0';
                                div_sel_rem <= '0';
                            when "0010010" => -- REM
                                div_sel_signed <= '1';
                                div_sel_rem <= '1';
                            when "0010011" => -- REMU
                                div_sel_signed <= '0';
                                div_sel_rem <= '1';
                            when others =>  -- not one of the four divide codes: leave the selects as they are
                        end case;
                        alu_state <= ALU_DIV_WAIT;
                    end if;
                    
                -- Stall here for the whole iterative divide; only div_complete leaves this state.
                when ALU_DIV_WAIT =>
                    if div_complete = '1' then
                        alu_state <= ALU_DIV_DONE;
                        div_rq <= '0';
                    end if;
                -- One cycle for the result mux to hand div_result to writeback, then back to idle.
                when ALU_DIV_DONE =>
                    alu_state <= ALU_IDLE;
                -- Unreachable state encoding: recover to idle.
                when others =>
                    alu_state <= ALU_IDLE;
            end case;
        end if;
    end process;

    -- Combinational result mux: one arm per alu_control code, defaulting to zero so an unused arm never latches.
    process(a, b, bs, alu_control, div_rdy, div_complete, alu_state, div_result, resetn)
        variable mult_result : std_logic_vector(2*XLEN-1 downto 0);
        variable shift_amount : integer;

        -- RV32 Zbs Bit Manipulation
        variable bit_index : integer;
        variable bit_mask  : std_logic_vector(XLEN-1 downto 0);

    begin
        if resetn = '0' then
            ResultSignal <= (others => '0');
            mult_result := (others => '0');
        else
            mult_result := (others => '0');
            ResultSignal <= (others => '0');

            case alu_control is
                -- ========== Base RV32I operations (7-bit alu_control encoding) ==========
                when "0000000" => -- Addition
                    ResultSignal <= std_logic_vector(unsigned(a) + unsigned(b));
                when "0000001" => -- Subtraction
                    ResultSignal <= std_logic_vector(unsigned(a) - unsigned(b));
                when "0000010" => -- AND
                    ResultSignal <= a and b;
                when "0000011" => -- OR
                    ResultSignal <= a or b;
                when "0000100" => -- XOR
                    ResultSignal <= a xor b;
                when "0000101" => -- SLT (Set if Less Than)
                    if signed(a) < signed(b) then
                        ResultSignal(0) <= '1';
                    end if;
                when "0000110" => -- Shift Left (Logical)
                    ResultSignal <= std_logic_vector(shift_left(unsigned(a), to_integer(unsigned(b(SHAMT_W-1 downto 0)))));
                when "0000111" => -- Shift Right (Logical)
                    ResultSignal <= std_logic_vector(shift_right(unsigned(a), to_integer(unsigned(b(SHAMT_W-1 downto 0)))));
                when "0001000" => -- Shift Right Arithmetic
                    ResultSignal <= std_logic_vector(shift_right(signed(a), to_integer(unsigned(b(SHAMT_W-1 downto 0)))));
                when "0001001" => -- SLTU (Set if Less Than Unsigned)
                    if unsigned(a) < unsigned(b) then
                        ResultSignal(0) <= '1';
                    end if;
                when "0001010" => -- Pass B
                    ResultSignal <= b;
                when "0001011" => -- Pass A (added for AMO)
                    ResultSignal <= a;

                -- ========== RV32M multiply/divide operations ==========
                when "0001100" => -- MUL (signed * signed, low 32 bits)
                    if ENABLE_MUL then
                        mult_result := std_logic_vector(signed(a)*signed(b));
                        ResultSignal <= mult_result(XLEN-1 downto 0);
                    end if;
                when "0001101" => -- MULH (signed * signed, high XLEN bits)
                    if ENABLE_MUL then
                        mult_result := std_logic_vector(signed(a)*signed(b));
                        ResultSignal <= mult_result(2*XLEN-1 downto XLEN);
                    end if;
                when "0001110" => -- MULHU (unsigned * unsigned, high XLEN bits)
                    if ENABLE_MUL then
                        mult_result := std_logic_vector(unsigned(a)*unsigned(b));
                        ResultSignal <= mult_result(2*XLEN-1 downto XLEN);
                    end if;
                when "0001111" => -- MULHSU
                    if ENABLE_MUL then
                        mult_result := std_logic_vector(resize(signed(a) * signed('0' & b), 2*XLEN));
                        ResultSignal <= mult_result(2*XLEN-1 downto XLEN);
                    end if;
                when "0010000" | "0010001" | "0010010" | "0010011" => -- Division operations
                    if ENABLE_DIV then
                        -- Result capture only: this arm raises no dispatch request, it just hands the divider's answer to writeback at DIV_DONE.
                        if alu_state = ALU_DIV_WAIT or alu_state = ALU_DIV_DONE then
                            if div_complete = '1' then
                                ResultSignal <= div_result;
                            end if;
                        end if;
                    end if;
                    
                -- ========== RV32A atomic MIN/MAX operations ==========
                when "0010100" => -- AMOMIN (signed)
                    if ENABLE_ATOMICS then
                        if signed(a) < signed(b) then
                            ResultSignal <= a;
                        else
                            ResultSignal <= b;
                        end if;
                    end if;

                when "0010101" => -- AMOMAX (signed)
                    if ENABLE_ATOMICS then
                        if signed(a) > signed(b) then
                            ResultSignal <= a;
                        else
                            ResultSignal <= b;
                        end if;
                    end if;

                when "0010110" => -- AMOMINU (unsigned)
                    if ENABLE_ATOMICS then
                        if unsigned(a) < unsigned(b) then
                            ResultSignal <= a;
                        else
                            ResultSignal <= b;
                        end if;
                    end if;

                when "0010111" => -- AMOMAXU (unsigned)
                    if ENABLE_ATOMICS then
                        if unsigned(a) > unsigned(b) then
                            ResultSignal <= a;
                        else
                            ResultSignal <= b;
                        end if;
                    end if;

                -- ========== RV32 Zba Shift-and-Add Instructions ==========
                when "0011000" => -- SH1ADD: rd = (rs1 << 1) + rs2
                    if ENABLE_BITMANIP then
                        ResultSignal <= std_logic_vector(unsigned(a(XLEN-2 downto 0) & '0') + unsigned(b));
                    end if;

                when "0011001" => -- SH2ADD: rd = (rs1 << 2) + rs2
                    if ENABLE_BITMANIP then
                        -- Keep the std_logic_vector' qualification: without it the bare string literal makes the concatenation overload ambiguous once the array types in scope are visible.
                        ResultSignal <= std_logic_vector(unsigned(std_logic_vector'(a(XLEN-3 downto 0) & "00")) + unsigned(b));
                    end if;

                when "0011010" => -- SH3ADD: rd = (rs1 << 3) + rs2
                    if ENABLE_BITMANIP then
                        -- std_logic_vector' qualification: same concatenation-overload ambiguity as SH2ADD.
                        ResultSignal <= std_logic_vector(unsigned(std_logic_vector'(a(XLEN-4 downto 0) & "000")) + unsigned(b));
                    end if;

                -- ========== RV32 Zbb Basic Bit-manipulation Instructions ==========

                -- Logical operations with complement
                when "0011011" => -- ANDN: rd = rs1 & ~rs2 (Zbb or Zbkb-shared)
                    if ENABLE_BITMANIP or ENABLE_ZBKB then
                        ResultSignal <= a and (not b);
                    end if;

                when "0011100" => -- ORN: rd = rs1 | ~rs2 (Zbb or Zbkb-shared)
                    if ENABLE_BITMANIP or ENABLE_ZBKB then
                        ResultSignal <= a or (not b);
                    end if;

                when "0011101" => -- XNOR: rd = ~(rs1 ^ rs2) (Zbb or Zbkb-shared)
                    if ENABLE_BITMANIP or ENABLE_ZBKB then
                        ResultSignal <= not (a xor b);
                    end if;

                -- Min/Max operations (Zbb versions)
                when "0011110" => -- MIN (signed)
                    if ENABLE_BITMANIP then
                        if signed(a) < signed(b) then
                            ResultSignal <= a;
                        else
                            ResultSignal <= b;
                        end if;
                    end if;

                when "0011111" => -- MINU (unsigned)
                    if ENABLE_BITMANIP then
                        if unsigned(a) < unsigned(b) then
                            ResultSignal <= a;
                        else
                            ResultSignal <= b;
                        end if;
                    end if;

                when "0100000" => -- MAX (signed)
                    if ENABLE_BITMANIP then
                        if signed(a) > signed(b) then
                            ResultSignal <= a;
                        else
                            ResultSignal <= b;
                        end if;
                    end if;

                when "0100001" => -- MAXU (unsigned)
                    if ENABLE_BITMANIP then
                        if unsigned(a) > unsigned(b) then
                            ResultSignal <= a;
                        else
                            ResultSignal <= b;
                        end if;
                    end if;
                
                -- Rotate operations
                -- Live rotate arms, built on the numeric_std rotate_left/rotate_right operators.
                when "0100010" => -- ROL: rotate left (Zbb or Zbkb-shared)
                    if ENABLE_BITMANIP or ENABLE_ZBKB then
                        shift_amount := to_integer(unsigned(b(SHAMT_W-1 downto 0)));
                        ResultSignal <= std_logic_vector(rotate_left(unsigned(a), shift_amount));
                    end if;

                when "0100011" => -- ROR/RORI: rotate right (Zbb or Zbkb-shared)
                    if ENABLE_BITMANIP or ENABLE_ZBKB then
                        shift_amount := to_integer(unsigned(b(SHAMT_W-1 downto 0)));
                        ResultSignal <= std_logic_vector(rotate_right(unsigned(a), shift_amount));
                    end if;

                -- Bit counting operations
                when "0100100" => -- CLZ: count leading zeros
                    if ENABLE_BITMANIP then
                        ResultSignal <= std_logic_vector(to_unsigned(count_leading_zeros(a), XLEN));
                    end if;

                when "0100101" => -- CTZ: count trailing zeros
                    if ENABLE_BITMANIP then
                        ResultSignal <= std_logic_vector(to_unsigned(count_trailing_zeros(a), XLEN));
                    end if;

                when "0100110" => -- CPOP: population count (count ones)
                    if ENABLE_BITMANIP then
                        ResultSignal <= std_logic_vector(to_unsigned(count_ones(a), XLEN));
                    end if;

                -- Sign/Zero extension
                when "0100111" => -- SEXT.B: sign extend byte
                    if ENABLE_BITMANIP then
                        ResultSignal <= (XLEN-1 downto 8 => a(7)) & a(7 downto 0);
                    end if;

                when "0101000" => -- SEXT.H: sign extend halfword
                    if ENABLE_BITMANIP then
                        ResultSignal <= (XLEN-1 downto 16 => a(15)) & a(15 downto 0);
                    end if;

                when "0101001" => -- ZEXT.H: zero extend halfword
                    if ENABLE_BITMANIP then
                        ResultSignal <= (XLEN-1 downto 16 => '0') & a(15 downto 0);
                    end if;

                -- Byte operations
                when "0101010" => -- ORC.B
                    if ENABLE_BITMANIP then
                        for i in 0 to XLEN_BYTES-1 loop
                            if a(i*8+7 downto i*8) /= x"00" then
                                ResultSignal(i*8+7 downto i*8) <= (others => '1');
                            else
                                ResultSignal(i*8+7 downto i*8) <= (others => '0');
                            end if;
                        end loop;
                    end if;

                when "0101011" => -- REV8: byte reverse (endianness swap) (Zbb or Zbkb-shared)
                    if ENABLE_BITMANIP or ENABLE_ZBKB then
                        for i in 0 to XLEN_BYTES-1 loop
                            ResultSignal(XLEN-1-i*8 downto XLEN-8-i*8) <= a(i*8+7 downto i*8);
                        end loop;
                    end if;


                -- ========== RV32 Zbs Single-bit Instructions ==========
                when "0101100" => -- BCLR/BCLRI: Bit clear (rd = rs1 & ~(1 << rs2))
                    if ENABLE_BITMANIP then
                        bit_index := to_integer(unsigned(b(SHAMT_W-1 downto 0)));
                        bit_mask := (others => '1');
                        bit_mask(bit_index) := '0';
                        ResultSignal <= a and bit_mask;
                    end if;

                when "0101101" => -- BEXT/BEXTI: Bit extract (rd = (rs1 >> rs2) & 1)
                    if ENABLE_BITMANIP then
                        bit_index := to_integer(unsigned(b(SHAMT_W-1 downto 0)));
                        ResultSignal <= (others => '0');
                        ResultSignal(0) <= a(bit_index);
                    end if;

                when "0101110" => -- BINV/BINVI: Bit invert (rd = rs1 ^ (1 << rs2))
                    if ENABLE_BITMANIP then
                        bit_index := to_integer(unsigned(b(SHAMT_W-1 downto 0)));
                        bit_mask := (others => '0');
                        bit_mask(bit_index) := '1';
                        ResultSignal <= a xor bit_mask;
                    end if;

                when "0101111" => -- BSET/BSETI: Bit set (rd = rs1 | (1 << rs2))
                    if ENABLE_BITMANIP then
                        bit_index := to_integer(unsigned(b(SHAMT_W-1 downto 0)));
                        bit_mask := (others => '0');
                        bit_mask(bit_index) := '1';
                        ResultSignal <= a or bit_mask;
                    end if;


                -- ========== RV32 Zbc Carry-less Multiplication Instructions ==========
                when "0110000" => -- CLMUL: carry-less multiply, low half (Zbc or Zbkc)
                    if ENABLE_BITMANIP or ENABLE_ZBKC then
                        mult_result := clmul_64(a, b);
                        ResultSignal <= mult_result(XLEN-1 downto 0);
                    end if;

                when "0110001" => -- CLMULH: carry-less multiply, high half (Zbc or Zbkc)
                    if ENABLE_BITMANIP or ENABLE_ZBKC then
                        mult_result := clmul_64(a, b);
                        ResultSignal <= mult_result(2*XLEN-1 downto XLEN);
                    end if;

                when "0110010" => -- CLMULR: carry-less multiply, reversed (Zbc only)
                    -- Take the middle 32 bits of the 64-bit product, which is the bit-reversed form the spec defines.
                    if ENABLE_BITMANIP then
                        mult_result := clmul_64(a, b);
                        ResultSignal <= mult_result(2*XLEN-2 downto XLEN-1);
                    end if;

                -- ========== RV32 Zicond Conditional-Zero Instructions (a = rs1, b = rs2) ==========
                when "0110011" => -- CZERO.EQZ: rd = (rs2==0) ? 0 : rs1
                    if ENABLE_ZICOND then
                        if b = ALU_ZERO_X then
                            ResultSignal <= (others => '0');
                        else
                            ResultSignal <= a;
                        end if;
                    end if;

                when "0110100" => -- CZERO.NEZ: rd = (rs2!=0) ? 0 : rs1
                    if ENABLE_ZICOND then
                        if b /= ALU_ZERO_X then
                            ResultSignal <= (others => '0');
                        else
                            ResultSignal <= a;
                        end if;
                    end if;

                -- ========== RV32 Zknd/Zkne AES-32 instructions ==========
                -- Single-cycle combinational, sharing one S-box pair and the GF MixColumn terms; a = rs1, b = rs2, bs = instr[31:30] on a separate ALU input.
                when "0111100" => -- aes32esi:  encrypt, SubBytes only
                    if ENABLE_ZKN then
                        ResultSignal <= aes32_datapath(a, b, bs, false, false);
                    end if;
                when "0111101" => -- aes32esmi: encrypt, SubBytes + MixColumns
                    if ENABLE_ZKN then
                        ResultSignal <= aes32_datapath(a, b, bs, false, true);
                    end if;
                when "0111110" => -- aes32dsi:  decrypt, inv-SubBytes only
                    if ENABLE_ZKN then
                        ResultSignal <= aes32_datapath(a, b, bs, true, false);
                    end if;
                when "0111111" => -- aes32dsmi: decrypt, inv-SubBytes + inv-MixColumns
                    if ENABLE_ZKN then
                        ResultSignal <= aes32_datapath(a, b, bs, true, true);
                    end if;

                -- ========== RV32 Zknh SHA-256 and SHA-512 sigma/sum ops ==========
                -- Pure combinational xor/rotate/shift trees: single-cycle and constant-time, with a = rs1 and b = rs2, and rotate/shift amounts taken from the ratified Zknh pseudocode.

                -- SHA-256 (unary: operate on rs1 = a only).
                when "1000000" => -- sha256sig0: ror(a,7) ^ ror(a,18) ^ (a>>3)
                    if ENABLE_ZKN then
                        ResultSignal <= std_logic_vector(
                            rotate_right(unsigned(a),  7) xor
                            rotate_right(unsigned(a), 18) xor
                            shift_right (unsigned(a),  3));
                    end if;
                when "1000001" => -- sha256sig1: ror(a,17) ^ ror(a,19) ^ (a>>10)
                    if ENABLE_ZKN then
                        ResultSignal <= std_logic_vector(
                            rotate_right(unsigned(a), 17) xor
                            rotate_right(unsigned(a), 19) xor
                            shift_right (unsigned(a), 10));
                    end if;
                when "1000010" => -- sha256sum0: ror(a,2) ^ ror(a,13) ^ ror(a,22)
                    if ENABLE_ZKN then
                        ResultSignal <= std_logic_vector(
                            rotate_right(unsigned(a),  2) xor
                            rotate_right(unsigned(a), 13) xor
                            rotate_right(unsigned(a), 22));
                    end if;
                when "1000011" => -- sha256sum1: ror(a,6) ^ ror(a,11) ^ ror(a,25)
                    if ENABLE_ZKN then
                        ResultSignal <= std_logic_vector(
                            rotate_right(unsigned(a),  6) xor
                            rotate_right(unsigned(a), 11) xor
                            rotate_right(unsigned(a), 25));
                    end if;

                -- SHA-512 (binary: combine the rs1 = a and rs2 = b halves into one 32-bit half).
                when "1000100" => -- sha512sig0l: (a>>1)^(a>>7)^(a>>8) ^ (b<<31)^(b<<25)^(b<<24)
                    if ENABLE_ZKN then
                        ResultSignal <= std_logic_vector(
                            shift_right(unsigned(a),  1) xor
                            shift_right(unsigned(a),  7) xor
                            shift_right(unsigned(a),  8) xor
                            shift_left (unsigned(b), 31) xor
                            shift_left (unsigned(b), 25) xor
                            shift_left (unsigned(b), 24));
                    end if;
                when "1000101" => -- sha512sig0h: (a>>1)^(a>>7)^(a>>8) ^ (b<<31)^(b<<24)
                    if ENABLE_ZKN then
                        ResultSignal <= std_logic_vector(
                            shift_right(unsigned(a),  1) xor
                            shift_right(unsigned(a),  7) xor
                            shift_right(unsigned(a),  8) xor
                            shift_left (unsigned(b), 31) xor
                            shift_left (unsigned(b), 24));
                    end if;
                when "1000110" => -- sha512sig1l: (a<<3)^(a>>6)^(a>>19) ^ (b>>29)^(b<<26)^(b<<13)
                    if ENABLE_ZKN then
                        ResultSignal <= std_logic_vector(
                            shift_left (unsigned(a),  3) xor
                            shift_right(unsigned(a),  6) xor
                            shift_right(unsigned(a), 19) xor
                            shift_right(unsigned(b), 29) xor
                            shift_left (unsigned(b), 26) xor
                            shift_left (unsigned(b), 13));
                    end if;
                when "1000111" => -- sha512sig1h: (a<<3)^(a>>6)^(a>>19) ^ (b>>29)^(b<<13)
                    if ENABLE_ZKN then
                        ResultSignal <= std_logic_vector(
                            shift_left (unsigned(a),  3) xor
                            shift_right(unsigned(a),  6) xor
                            shift_right(unsigned(a), 19) xor
                            shift_right(unsigned(b), 29) xor
                            shift_left (unsigned(b), 13));
                    end if;
                when "1001000" => -- sha512sum0r: (a<<25)^(a<<30)^(a>>28) ^ (b>>7)^(b>>2)^(b<<4)
                    if ENABLE_ZKN then
                        ResultSignal <= std_logic_vector(
                            shift_left (unsigned(a), 25) xor
                            shift_left (unsigned(a), 30) xor
                            shift_right(unsigned(a), 28) xor
                            shift_right(unsigned(b),  7) xor
                            shift_right(unsigned(b),  2) xor
                            shift_left (unsigned(b),  4));
                    end if;
                when "1001001" => -- sha512sum1r: (a<<23)^(a>>14)^(a>>18) ^ (b>>9)^(b<<18)^(b<<14)
                    if ENABLE_ZKN then
                        ResultSignal <= std_logic_vector(
                            shift_left (unsigned(a), 23) xor
                            shift_right(unsigned(a), 14) xor
                            shift_right(unsigned(a), 18) xor
                            shift_right(unsigned(b),  9) xor
                            shift_left (unsigned(b), 18) xor
                            shift_left (unsigned(b), 14));
                    end if;

                -- ========== Zbkb crypto bit-manip, single-cycle combinational (a = rs1, b = rs2) ==========
                when "0110101" => -- PACK: rd = (rs2[15:0] << 16) | rs1[15:0]
                    if ENABLE_ZBKB then
                        ResultSignal <= b(15 downto 0) & a(15 downto 0);
                    end if;

                when "0110110" => -- PACKH: rd = zext16( (rs2[7:0] << 8) | rs1[7:0] )
                    if ENABLE_ZBKB then
                        ResultSignal <= x"0000" & b(7 downto 0) & a(7 downto 0);
                    end if;

                when "0110111" => -- BREV8: reverse the bits within each byte
                    if ENABLE_ZBKB then
                        for i in 0 to 3 loop
                            for j in 0 to 7 loop
                                ResultSignal(i*8 + j) <= a(i*8 + 7 - j);
                            end loop;
                        end loop;
                    end if;

                when "0111000" => -- ZIP: interleave low/high halves (RV32 shuffle)
                    if ENABLE_ZBKB then
                        for i in 0 to 15 loop
                            ResultSignal(2*i)     <= a(i);       -- low half into the even bits
                            ResultSignal(2*i + 1) <= a(i + 16);  -- high half into the odd bits
                        end loop;
                    end if;

                when "0111001" => -- UNZIP: de-interleave (inverse of ZIP)
                    if ENABLE_ZBKB then
                        for i in 0 to 15 loop
                            ResultSignal(i)      <= a(2*i);      -- even bits into the low half
                            ResultSignal(i + 16) <= a(2*i + 1);  -- odd bits into the high half
                        end loop;
                    end if;

                -- ========== Zbkx crossbar permute (fixed mux tree, single-cycle) ==========
                -- Each result byte or nibble i takes rs1's byte or nibble at the index in rs2, or zero when that index is out of range.
                when "0111010" => -- XPERM8: byte crossbar (index rs2.byte[i], <4)
                    if ENABLE_ZBKX then
                        for i in 0 to 3 loop
                            if unsigned(b(i*8 + 7 downto i*8)) < 4 then
                                case b(i*8 + 1 downto i*8) is
                                    when "00"   => ResultSignal(i*8 + 7 downto i*8) <= a( 7 downto  0);
                                    when "01"   => ResultSignal(i*8 + 7 downto i*8) <= a(15 downto  8);
                                    when "10"   => ResultSignal(i*8 + 7 downto i*8) <= a(23 downto 16);
                                    when others => ResultSignal(i*8 + 7 downto i*8) <= a(31 downto 24);
                                end case;
                            else
                                ResultSignal(i*8 + 7 downto i*8) <= (others => '0');
                            end if;
                        end loop;
                    end if;

                when "0111011" => -- XPERM4: nibble crossbar (index rs2.nibble[i], <8)
                    if ENABLE_ZBKX then
                        for i in 0 to 7 loop
                            if unsigned(b(i*4 + 3 downto i*4)) < 8 then
                                case b(i*4 + 2 downto i*4) is
                                    when "000"  => ResultSignal(i*4 + 3 downto i*4) <= a( 3 downto  0);
                                    when "001"  => ResultSignal(i*4 + 3 downto i*4) <= a( 7 downto  4);
                                    when "010"  => ResultSignal(i*4 + 3 downto i*4) <= a(11 downto  8);
                                    when "011"  => ResultSignal(i*4 + 3 downto i*4) <= a(15 downto 12);
                                    when "100"  => ResultSignal(i*4 + 3 downto i*4) <= a(19 downto 16);
                                    when "101"  => ResultSignal(i*4 + 3 downto i*4) <= a(23 downto 20);
                                    when "110"  => ResultSignal(i*4 + 3 downto i*4) <= a(27 downto 24);
                                    when others => ResultSignal(i*4 + 3 downto i*4) <= a(31 downto 28);
                                end case;
                            else
                                ResultSignal(i*4 + 3 downto i*4) <= (others => '0');
                            end if;
                        end loop;
                    end if;

                -- Unassigned alu_control code: return zero rather than hold a stale result.
                when others =>
                    ResultSignal <= (others => '0');
            end case;
        end if;
    end process;

    -- The iterative divider only exists when the DIV feature is enabled; with it disabled the decode traps DIV/DIVU/REM/REMU upstream and these ports are tied to benign idle values (rdy='1' keeps the ALU FSM sane).
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

    -- DIV disabled: tie the divider interface off so the FSM sees a permanently ready, never-completing divider.
    gen_no_div: if not ENABLE_DIV generate
        div_result   <= (others => '0');
        div_complete <= '0';
        div_rdy      <= '1';
    end generate;

    ALU_result <= ResultSignal; 
    
    -- Zero flag for the branch comparators: high when the whole result is zero.
    checkZero: process(ResultSignal)
    begin
        if ResultSignal = ALU_ZERO_X then
            Zero <= '1';
        else
            Zero <= '0';
        end if;
    end process;

end architecture behav;



