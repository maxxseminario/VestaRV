library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use ieee.math_real.log2;

package constants is

    --Define clock speed (for testing)
    constant clk_hz : integer := 100e6; --100 MHz
    constant clk_period : time := 1 sec / clk_hz; --10ns

    -- Passwords
    constant WDT_UNLCK_PASSWD : std_logic_vector(31 downto 0) := x"5f3759df"; --Password to enable watchdog timer write
    constant WDT_CLR_PASSWD : std_logic_vector(31 downto 0) := x"A0C8A620"; --Password to clear watchdog timer
    
    -- Shortcuts for common data types
	subtype sl			is std_logic;
	subtype slv			is std_logic_vector;
	subtype word		is slv(31 downto 0);
	subtype halfword	is slv(15 downto 0);
	subtype quarterword	is slv(07 downto 0);
	subtype byte		is quarterword;
	type word_array		is array (natural range <>) of word;
	type halfword_array	is array (natural range <>) of halfword;


    -- constant RAM_SIZE       : integer := 16#a000#; -- 40KiB RAMs
    -- constant RAM_START      : integer := 16#a000#; 
    -- constant IVT_BASE_ADDR  : integer := 16#a000#;
    constant cafebabe       : std_logic_vector(31 downto 0) := x"CAFEBABE";
    constant four           : std_logic_vector(31 downto 0) := x"00000004";
    constant MEM_ADDR_WIDTH : integer := 17; 
    constant N_SARADC_CHANNELS : integer := 4;
    constant nop          : std_logic_vector(31 downto 0) := x"00000013"; -- ADDI x0, x0, 0

	constant DCO0_BIAS_DEFAULT : std_logic_vector(11 downto 0) := "100000000000"; 
	constant DCO1_BIAS_DEFAULT : std_logic_vector(11 downto 0) := "100000000000"; 


    -- RV32I RISC-V Integer Instruction Constants
    constant R_OPCODE        : std_logic_vector(6 downto 0) := "0110011"; -- Register-Register (used for both RV32I and RV32M)
    constant I_LOAD_OPCODE   : std_logic_vector(6 downto 0) := "0000011"; -- Immediate Load
    constant I_ARITH_OPCODE  : std_logic_vector(6 downto 0) := "0010011"; -- Immediate Arithmetic/Logic
    constant I_JALR_OPCODE   : std_logic_vector(6 downto 0) := "1100111"; -- JALR (Immediate Jump and Link Register)
    constant S_OPCODE        : std_logic_vector(6 downto 0) := "0100011"; -- Store
    constant B_OPCODE        : std_logic_vector(6 downto 0) := "1100011"; -- Branch
    constant J_OPCODE        : std_logic_vector(6 downto 0) := "1101111"; -- JAL (Jump and Link)
    constant U_AUIPC_OPCODE  : std_logic_vector(6 downto 0) := "0010111"; -- AUIPC (Add Upper Immediate to PC)
    constant U_LUI_OPCODE    : std_logic_vector(6 downto 0) := "0110111"; -- LUI (Load Upper Immediate)
    constant SYSTEM_OPCODE   : std_logic_vector(6 downto 0) := "1110011"; -- SYSTEM (ECALL, EBREAK, CSR)
    constant FENCE_OPCODE    : std_logic_vector(6 downto 0) := "0001111"; -- FENCE/MISC-MEM
    constant CUSTOM_OPCODE  : std_logic_vector(6 downto 0)   := "0001011"; -- Custom IRET instruction opcode
	constant AMO_OPCODE      : std_logic_vector(6 downto 0) := "0101111"; -- RV32A Atomic Memory Operations

    
    -- Function 3 codes for ALU (RV32I)
    constant ADD_FN3  : std_logic_vector(2 downto 0) := "000"; -- Also SUB if NEG_FN7
    constant SLL_FN3  : std_logic_vector(2 downto 0) := "001";
    constant SLT_FN3  : std_logic_vector(2 downto 0) := "010";
    constant SLTU_FN3 : std_logic_vector(2 downto 0) := "011";
    constant XOR_FN3  : std_logic_vector(2 downto 0) := "100";
    constant SRL_FN3  : std_logic_vector(2 downto 0) := "101"; -- Also SRA if NEG_FN7
    constant OR_FN3   : std_logic_vector(2 downto 0) := "110";
    constant AND_FN3  : std_logic_vector(2 downto 0) := "111";
    constant IRET_FN3 : std_logic_vector(2 downto 0) := "000"; -- Custom funct3 for IRET instruction
    constant SLP_FN3 : std_logic_vector(2 downto 0) := "001"; -- Custom funct3 for Sleep/Wake instructions
    constant BEQ_TOP_FN3 : std_logic_vector(1 downto 0) := "00";
    constant BCOMP_TOP_FN3 : std_logic_vector(1 downto 0) := "10";
    constant BCOMPU_TOP_FN3 : std_logic_vector(1 downto 0) := "11";
	constant FENCE_FN3       : std_logic_vector(2 downto 0) := "000"; -- FENCE
	constant FENCE_I_FN3     : std_logic_vector(2 downto 0) := "001"; -- FENCE.I (instruction fence)

    -- Function 7 codes for ALU
    constant POS_FN7  : std_logic_vector(6 downto 0) := "0000000";
    constant NEG_FN7  : std_logic_vector(6 downto 0) := "0100000";
    constant IRET_FN7   : std_logic_vector(6 downto 0) := "0000000"; -- for IRET instruction
    constant SLEEP_FN7   : std_logic_vector(6 downto 0) := "0000000"; -- for Sleep instruction
    constant WAKE_FN7    : std_logic_vector(6 downto 0) := "0000001"; -- for Wake instruction
	constant M_EXT_FN7   : std_logic_vector(6 downto 0) := "0000001"; -- for all RV32M instructions

    -- RV32M (Integer Multiplication and Division) funct3 codes and funct7
    constant MULT_FN7   : std_logic_vector(6 downto 0) := "0000001"; -- for all RV32M instructions
    constant MUL_FN3     : std_logic_vector(2 downto 0) := "000";
    constant MULH_FN3    : std_logic_vector(2 downto 0) := "001";
    constant MULHSU_FN3  : std_logic_vector(2 downto 0) := "010";
    constant MULHU_FN3   : std_logic_vector(2 downto 0) := "011";
    constant DIV_FN3     : std_logic_vector(2 downto 0) := "100";
    constant DIVU_FN3    : std_logic_vector(2 downto 0) := "101";
    constant REM_FN3     : std_logic_vector(2 downto 0) := "110";
    constant REMU_FN3    : std_logic_vector(2 downto 0) := "111";

	-- RV32A (Atomic Operations) funct3 codes
    constant AMO_WIDTH_W : std_logic_vector(2 downto 0) := "010"; -- Word-width atomic operations

	-- RV32A funct5 codes (bits [31:27] of instruction)
    -- Note: For AMO instructions, funct7 = {aq, rl, funct5[4:0]}
    constant LR_FN5      : std_logic_vector(4 downto 0) := "00010"; -- Load-Reserved
    constant SC_FN5      : std_logic_vector(4 downto 0) := "00011"; -- Store-Conditional
    constant AMOSWAP_FN5 : std_logic_vector(4 downto 0) := "00001"; -- Atomic Swap
    constant AMOADD_FN5  : std_logic_vector(4 downto 0) := "00000"; -- Atomic Add
    constant AMOXOR_FN5  : std_logic_vector(4 downto 0) := "00100"; -- Atomic XOR
    constant AMOAND_FN5  : std_logic_vector(4 downto 0) := "01100"; -- Atomic AND
    constant AMOOR_FN5   : std_logic_vector(4 downto 0) := "01000"; -- Atomic OR
    constant AMOMIN_FN5  : std_logic_vector(4 downto 0) := "10000"; -- Atomic MIN (signed)
    constant AMOMAX_FN5  : std_logic_vector(4 downto 0) := "10100"; -- Atomic MAX (signed)
    constant AMOMINU_FN5 : std_logic_vector(4 downto 0) := "11000"; -- Atomic MIN (unsigned)
    constant AMOMAXU_FN5 : std_logic_vector(4 downto 0) := "11100"; -- Atomic MAX (unsigned)


	-- RV32 Zba (Bit Manipulation - Address Generation) constants (R-type instructions)
    constant ZBA_FN7     : std_logic_vector(6 downto 0) := "0010000"; -- funct7 for Zba instructions
    constant SH1ADD_FN3  : std_logic_vector(2 downto 0) := "010";     -- funct3 for sh1add
    constant SH2ADD_FN3  : std_logic_vector(2 downto 0) := "100";     -- funct3 for sh2add  
    constant SH3ADD_FN3  : std_logic_vector(2 downto 0) := "110";     -- funct3 for sh3add

	-- RV32 Zbb (Basic Bit-manipulation) constants

    constant ANDN_FN7    : std_logic_vector(6 downto 0) := "0100000"; -- ANDN
    constant ORN_FN7     : std_logic_vector(6 downto 0) := "0100000"; -- ORN  
    constant XNOR_FN7    : std_logic_vector(6 downto 0) := "0100000"; -- XNOR
    constant MIN_FN7     : std_logic_vector(6 downto 0) := "0000101"; -- MIN
    constant MINU_FN7    : std_logic_vector(6 downto 0) := "0000101"; -- MINU
    constant MAX_FN7     : std_logic_vector(6 downto 0) := "0000101"; -- MAX
    constant MAXU_FN7    : std_logic_vector(6 downto 0) := "0000101"; -- MAXU
    constant ROL_FN7     : std_logic_vector(6 downto 0) := "0110000"; -- ROL
    constant ROR_FN7     : std_logic_vector(6 downto 0) := "0110000"; -- ROR
    constant REV8_FN7    : std_logic_vector(6 downto 0) := "0110100"; -- REV8 (uses funct7[6:2] = 11010)
    constant ZEXT_FN7    : std_logic_vector(6 downto 0) := "0000100"; -- ZEXT.H
    constant SEXT_FN7    : std_logic_vector(6 downto 0) := "0110000"; -- SEXT.B/H
    constant CLZ_FN7     : std_logic_vector(6 downto 0) := "0110000"; -- CLZ
    constant CTZ_FN7     : std_logic_vector(6 downto 0) := "0110000"; -- CTZ  
    constant CPOP_FN7    : std_logic_vector(6 downto 0) := "0110000"; -- CPOP
    constant ORC_B_FN7   : std_logic_vector(6 downto 0) := "0010100"; -- ORC.B

    -- Zbb I-type immediate instructions (use I_ARITH_OPCODE)
    constant RORI_FN7    : std_logic_vector(6 downto 0) := "0110000"; -- RORI (immediate rotate right)
    constant SEXT_B_IMM12 : std_logic_vector(11 downto 0) := "011000000100"; -- SEXT.B immediate encoding
    constant SEXT_H_IMM12 : std_logic_vector(11 downto 0) := "011000000101"; -- SEXT.H immediate encoding
    constant ZEXT_H_IMM12 : std_logic_vector(11 downto 0) := "000010000000"; -- ZEXT.H immediate encoding
    constant CLZ_IMM12   : std_logic_vector(11 downto 0) := "011000000000"; -- CLZ immediate encoding
    constant CTZ_IMM12   : std_logic_vector(11 downto 0) := "011000000001"; -- CTZ immediate encoding
    constant CPOP_IMM12  : std_logic_vector(11 downto 0) := "011000000010"; -- CPOP immediate encoding
    constant ORC_B_IMM12 : std_logic_vector(11 downto 0) := "001010000111"; -- ORC.B immediate encoding
    constant REV8_IMM12  : std_logic_vector(11 downto 0) := "011010011000"; -- REV8 immediate encoding

	-- RV32 Zbs (Single-bit Instructions) constants (R-type instructions)
    constant BCLR_FN7    : std_logic_vector(6 downto 0) := "0100100"; -- BCLR
    constant BEXT_FN7    : std_logic_vector(6 downto 0) := "0100100"; -- BEXT  
    constant BINV_FN7    : std_logic_vector(6 downto 0) := "0110100"; -- BINV
    constant BSET_FN7    : std_logic_vector(6 downto 0) := "0010100"; -- BSET
    
    -- Zbs I-type immediate instructions
    constant BCLRI_FN7   : std_logic_vector(6 downto 0) := "0100100"; -- BCLRI
    constant BEXTI_FN7   : std_logic_vector(6 downto 0) := "0100100"; -- BEXTI
    constant BINVI_FN7   : std_logic_vector(6 downto 0) := "0110100"; -- BINVI
    constant BSETI_FN7   : std_logic_vector(6 downto 0) := "0010100"; -- BSETI

	-- RV32 Zbc (Carry-less Multiplication) constants (R-type instructions)
    constant CLMUL_FN7   : std_logic_vector(6 downto 0) := "0000101"; -- CLMUL (carry-less multiply low)
    constant CLMULH_FN7  : std_logic_vector(6 downto 0) := "0000101"; -- CLMULH (carry-less multiply high)
    constant CLMULR_FN7  : std_logic_vector(6 downto 0) := "0000101"; -- CLMULR (carry-less multiply reverse)
    -- Zbc funct3 codes
    constant CLMUL_FN3   : std_logic_vector(2 downto 0) := "001"; -- CLMUL funct3
    constant CLMULH_FN3  : std_logic_vector(2 downto 0) := "011"; -- CLMULH funct3
    constant CLMULR_FN3  : std_logic_vector(2 downto 0) := "010"; -- CLMULR funct3


	-- RV32 CSR (Control and Status Register) instruction constants
    -- CSR instruction funct3 codes (use SYSTEM_OPCODE)
    constant CSRRW_FN3   : std_logic_vector(2 downto 0) := "001"; -- CSR Read/Write
    constant CSRRS_FN3   : std_logic_vector(2 downto 0) := "010"; -- CSR Read and Set
    constant CSRRC_FN3   : std_logic_vector(2 downto 0) := "011"; -- CSR Read and Clear
    constant CSRRWI_FN3  : std_logic_vector(2 downto 0) := "101"; -- CSR Read/Write Immediate
    constant CSRRSI_FN3  : std_logic_vector(2 downto 0) := "110"; -- CSR Read and Set Immediate
    constant CSRRCI_FN3  : std_logic_vector(2 downto 0) := "111"; -- CSR Read and Clear Immediate
    
    -- Minimal CSR addresses - only performance counters
    -- Machine Counter/Timers (Read/Write)
    constant CSR_MCYCLE     : std_logic_vector(11 downto 0) := x"B00"; -- Machine cycle counter low
    constant CSR_MINSTRET   : std_logic_vector(11 downto 0) := x"B02"; -- Machine instructions retired low
    constant CSR_MCYCLEH    : std_logic_vector(11 downto 0) := x"B80"; -- Machine cycle counter high
    constant CSR_MINSTRETH  : std_logic_vector(11 downto 0) := x"B82"; -- Machine instructions retired high
    
    -- User-accessible counters (Read-only shadows)
    constant CSR_CYCLE      : std_logic_vector(11 downto 0) := x"C00"; -- Cycle counter low
    constant CSR_TIME       : std_logic_vector(11 downto 0) := x"C01"; -- Timer low (often memory-mapped)
    constant CSR_INSTRET    : std_logic_vector(11 downto 0) := x"C02"; -- Instructions retired low
    constant CSR_CYCLEH     : std_logic_vector(11 downto 0) := x"C80"; -- Cycle counter high
    constant CSR_TIMEH      : std_logic_vector(11 downto 0) := x"C81"; -- Timer high (often memory-mapped)
    constant CSR_INSTRETH   : std_logic_vector(11 downto 0) := x"C82"; -- Instructions retired high



    -- I2C constants
    constant i2c0_default_SAD : std_logic_vector(6 downto 0) := "1111001"; -- Default slave address for I2C0 (0x79)
    constant i2c1_default_SAD : std_logic_vector(6 downto 0) := "0100011"; -- Default slave address for I2C1 (0x23)


	constant mem_assert	: std_logic := '0'; -- Active low
	constant mem_deassert: std_logic := '1';

	-- Pad constants 
	constant PAD_DIR_INPUT_LEVEL  : std_logic := '1'; 
    constant PAD_DIR_OUTPUT_LEVEL : std_logic := '0';
    constant PAD_REN_ENABLE_LEVEL : std_logic := '0'; 
    constant PAD_REN_DISABLE_LEVEL: std_logic := '1'; 

	function ceil_log2 (value : positive) return natural;
	function int2slv(x : integer; num_bits : integer) return std_logic_vector;
	function uint2slv(x : integer; num_bits : integer) return std_logic_vector;
	function slv2int(x: slv) return integer;
	function slv2uint(x: slv) return integer;
	function bool2sl(x : boolean) return sl;
	function or_reduct(x : slv) return sl;
	function and_reduct(x : slv) return sl;
	function reverse_slv_order(x : slv) return slv;

end constants;

package body constants is

   ----------------------------------------------------------------------------
	-- Finds the MSbit index required to represent a given positive number.
	----------------------------------------------------------------------------
	function ceil_log2 (value : positive) return natural is
		variable result : natural;
	begin
		result := 0;
		while (value > (2**result)) loop
			result := result + 1;
		end loop;
		return result;
	end function ceil_log2;

	----------------------------------------------------------------------------
	-- Converts a signed integer into a standard logic vector (uses numeric_std)
	----------------------------------------------------------------------------
	function int2slv(x : integer; num_bits : integer) return std_logic_vector is
	begin
		return std_logic_vector(to_signed(x, num_bits));
	end int2slv;

	----------------------------------------------------------------------------
	-- Converts an unsigned integer into a standard logic vector (uses numeric_std)
	----------------------------------------------------------------------------
	function uint2slv(x : integer; num_bits : integer) return std_logic_vector is
	begin
		return std_logic_vector(to_unsigned(x, num_bits));
	end uint2slv;

	----------------------------------------------------------------------------
	-- Converts a standard logic vector into a signed integer (uses numeric_std)
	----------------------------------------------------------------------------
	function slv2int(x: slv) return integer is
	begin
		return to_integer(signed(x));
	end slv2int;

	----------------------------------------------------------------------------
	-- Converts a standard logic vector into an unsigned integer (uses numeric_std)
	----------------------------------------------------------------------------
	function slv2uint(x: slv) return integer is
	begin
		return to_integer(unsigned(x));
	end slv2uint;

	----------------------------------------------------------------------------
	-- Converts a boolean into a std_logic
	----------------------------------------------------------------------------
	function bool2sl(x : boolean) return sl is
	begin
		if x then
			return('1');
		else
			return('0');
		end if;
	end bool2sl;
	
	----------------------------------------------------------------------------
	-- ORs all bits in a std_logic_vector together
	----------------------------------------------------------------------------
	function or_reduct(x : slv) return sl is
		variable ret_val : sl := '0';
	begin
		for i in x'range loop
			ret_val := ret_val or x(i);
		end loop;
		return ret_val;
	
	end or_reduct;
	
	----------------------------------------------------------------------------
	-- ANDs all bits in a std_logic_vector together
	----------------------------------------------------------------------------
	function and_reduct(x : slv) return sl is
		variable ret_val : sl := '1';
	begin
		for i in x'range loop
			ret_val := ret_val and x(i);
		end loop;
		return ret_val;
	end and_reduct;
	
	----------------------------------------------------------------------------
	-- Reverses the ordering of the bits in a standard logic vector
	----------------------------------------------------------------------------
	function reverse_slv_order(x : slv) return slv is
		variable result : slv(x'high downto x'low);
	begin
		for index in x'high downto x'low loop
			result(index) := x(x'high - index);
		end loop;
		return result;
	end reverse_slv_order;

end constants;