library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use ieee.math_real.log2;

package constants is

    -- XLEN is the vesta DATAPATH width (registers, ALU operands, addresses, PC, CSR values); ILEN is the INSTRUCTION word width, kept separate because on RV64 it stays 32 while XLEN doubles.
    -- Every core width reference goes through one of these or a width derived below, never a bare 32, but only XLEN=32 is implemented: the SoC fabric (arbiter, tile boundary, peripherals, SRAMs) is a fixed 32-bit bus, so XLEN is a starting point, not a knob.
    constant XLEN       : natural := 32;              -- datapath/register width
    constant ILEN       : natural := 32;              -- instruction word width (32 even on RV64)
    constant XLEN_BYTES : natural := XLEN / 8;        -- bus byte lanes (wen width)
    constant SHAMT_W    : natural := 5;               -- shift-amount width = ceil_log2(XLEN)

    -- Define clock speed (for testing)
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


    constant cafebabe       : std_logic_vector(31 downto 0) := x"CAFEBABE";
    constant four           : std_logic_vector(31 downto 0) := x"00000004";
    constant MEM_ADDR_WIDTH : integer := 17;
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

    -- Zihintpause: PAUSE = `fence w,0` = 0x0100000F, whose FENCE immediate instr[31:20] = fm(0) | pred(W=0001) | succ(0000) = 0x010.
    -- maindec detects the exact PAUSE hint on (FENCE_OPCODE, FENCE_FN3, imm12=PAUSE_IMM12) gated by ENABLE_ZIHINT; every other FENCE encoding stays an ordering nop.
    constant PAUSE_IMM12     : std_logic_vector(11 downto 0) := "000000010000"; -- 0x010

    -- PAUSE side-effect window: with ENABLE_ZIHINT a retiring PAUSE holds this hart OUT of the shared-bus request contest for this many clk_cpu cycles, its arbiter req staying low while it waits in PAUSE_WAIT.
    -- Long enough for a competing hart to win arbitration and far below any timeout scale; 0 removes the side-effect, leaving PAUSE a plain fence-nop.
    constant PAUSE_WINDOW_CYCLES : natural := 16;

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
    constant AMO_WIDTH_B : std_logic_vector(2 downto 0) := "000"; -- Zabha: byte-width atomic operations
    constant AMO_WIDTH_H : std_logic_vector(2 downto 0) := "001"; -- Zabha: halfword-width atomic operations

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
    constant CAS_FN5     : std_logic_vector(4 downto 0) := "00101"; -- Zacas: Compare-and-Swap (amocas.w/.b/.h)

    -- Zawrs (Wait-on-Reservation-Set): SYSTEM opcode (1110011), funct3=000, rs1=x0, rd=x0, distinguished by the 12-bit funct12 (imm12) field.
    -- These are currently-illegal SYSTEM encodings when ENABLE_ZAWRS is false.
    constant WRS_NTO_IMM12 : std_logic_vector(11 downto 0) := x"00D"; -- wrs.nto (wait, no timeout)
    constant WRS_STO_IMM12 : std_logic_vector(11 downto 0) := x"01D"; -- wrs.sto (wait, short timeout)
    -- (wrs.sto short-timeout count lives as WRS_TIMEOUT_CYCLES in vesta.vhd.)

    /* Zicboz (cache-block zero, i.e. cbo.zero): MISC-MEM/FENCE opcode (0001111), funct3=010 (CBO_FN3), rd-field=00000, and the imm12 field selects the op.
         cbo.zero  = 0x004  (legal only under ENABLE_ZICBOZ)
         cbo.clean = 0x001 / cbo.flush = 0x002 / cbo.inval = 0x000 are ALWAYS ILLEGAL (otherwise-reserved MISC-MEM funct3=010)
       The effective address is X[rs1] with no offset, and cbo.zero writes 0x00000000 to the 16 words of the naturally-aligned CBOZ_BLOCK_SIZE-byte block containing it. */
    constant CBO_FN3         : std_logic_vector(2 downto 0)  := "010";  -- cbo.* funct3 (MISC-MEM)
    constant CBOZ_IMM12      : std_logic_vector(11 downto 0) := x"004"; -- cbo.zero imm[11:0]
    -- Spec-fixed granule; the cboz_idx range and base mask in vesta.vhd derive from these two constants, so a bump is a one-line change here.
    constant CBOZ_BLOCK_SIZE : natural := 64;                    -- bytes (16 words)
    constant CBOZ_WORDS      : natural := CBOZ_BLOCK_SIZE / 4;   -- word stores per cbo.zero

    /* ==========================================================================
       Zcmp / Zcmt (compressed push/pop + table jump)
       ==========================================================================
       These live in the C2 quadrant funct3=101 slot (the c.fsdsp slot, free on this no-F/D core); c_dec.vhd emits the fixed-shape 32-bit SENTINEL word below for a LEGAL cm.*, while an illegal pattern or generic-off leaves dec=0 (illegal).
       maindec turns op = ZCM_SENTINEL_OP into zcm_op plus valid for vesta's push/pop/move/jump SEQUENCER: all six push/pop/move insns and cm.jt/cm.jalt need multiple register writes, a memory burst or a control-flow redirect, so none can be a single expanded 32-bit instruction. */

    -- Sentinel opcode bits(1:0) = "10", so NO real decompressed instruction (which always ends "11") and no reserved-compressed hole (dec all-zero, op "0000000") can ever collide with it.
    -- The ONLY producer of this op pattern is c_dec's sentinel synthesis, itself gated on ENABLE_ZCMP/ENABLE_ZCMT, so a raw 32-bit word can never be mistaken for a cm.*.
    constant ZCM_SENTINEL_OP : std_logic_vector(6 downto 0) := "0101010"; -- Zcmp/Zcmt sentinel opcode (bits 1:0 = 10)
    -- Sub-op selector, carried in sentinel bits(14:12) (the funct3 field position):
    constant ZCM_SUB_PUSH    : std_logic_vector(2 downto 0) := "000"; -- cm.push
    constant ZCM_SUB_POP     : std_logic_vector(2 downto 0) := "001"; -- cm.pop
    constant ZCM_SUB_POPRET  : std_logic_vector(2 downto 0) := "010"; -- cm.popret
    constant ZCM_SUB_POPRETZ : std_logic_vector(2 downto 0) := "011"; -- cm.popretz
    constant ZCM_SUB_MVSA01  : std_logic_vector(2 downto 0) := "100"; -- cm.mvsa01 (a0/a1 into the s-regs)
    constant ZCM_SUB_MVA01S  : std_logic_vector(2 downto 0) := "101"; -- cm.mva01s (s-regs into a0/a1)
    constant ZCM_SUB_TABJUMP : std_logic_vector(2 downto 0) := "110"; -- cm.jt / cm.jalt (index selects)
    /* The original 16-bit compressed instruction is embedded in sentinel(31:16), so vesta slices the operand fields directly at their spec bit positions:
         rlist = i16(7:4)  = sentinel(23:20)     spimm = i16(3:2) = sentinel(19:18)
         sreg1 = i16(9:7)  = sentinel(25:23)     sreg2 = i16(4:2) = sentinel(20:18)
         index = i16(9:2)  = sentinel(25:18) */

    -- rlist gives the Zcmp reg count: 4..14 means rlist-3 regs, 15 means 13 regs (it adds s10 and s11), and 0..3 are reserved (c_dec emits illegal).
    -- stack_adj = stack_adj_base + spimm*16, base 16 (rlist 4-7) / 32 (8-11) / 48 (12-14) / 64 (15); the Zcmt table is 256 x 32b at {jvt[31:6],6'b0}, target = mem[base+idx*4].


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

	-- RV32 Zbkb / Zbkx (scalar-crypto bit-manip) constants.
    -- pack/packh share funct7 with Zbb ZEXT.H (both 0000100); pack rs2=x0 == zext.h.
    constant PACK_FN7    : std_logic_vector(6 downto 0)  := "0000100";      -- pack / packh (R-type)
    constant PACK_FN3    : std_logic_vector(2 downto 0)  := "100";          -- pack
    constant PACKH_FN3   : std_logic_vector(2 downto 0)  := "111";          -- packh
    -- brev8/zip/unzip are OP-IMM: funct7 and rs2 are fixed, so imm12 = instr[31:20].
    constant BREV8_IMM12 : std_logic_vector(11 downto 0) := "011010000111"; -- brev8 (0x687: funct7=0110100,rs2=00111,funct3=101)
    constant ZIP_IMM12   : std_logic_vector(11 downto 0) := "000010001111"; -- zip   (0x08F: funct7=0000100,rs2=01111,funct3=001)
    constant UNZIP_IMM12 : std_logic_vector(11 downto 0) := "000010001111"; -- unzip (0x08F: funct7=0000100,rs2=01111,funct3=101)
    -- xperm8/xperm4 crossbar permute (R-type; funct7 0010100 == BSETI_FN7 but distinguished by funct3 100/010 against BSET's 001, so no decode overlap).
    constant XPERM_FN7   : std_logic_vector(6 downto 0)  := "0010100";      -- xperm8 / xperm4 (R-type)
    constant XPERM8_FN3  : std_logic_vector(2 downto 0)  := "100";          -- xperm8
    constant XPERM4_FN3  : std_logic_vector(2 downto 0)  := "010";          -- xperm4


	-- RV32 Zicond (Integer Conditional Operations) constants (R-type instructions)
    constant ZICOND_FN7    : std_logic_vector(6 downto 0) := "0000111"; -- funct7 for czero.eqz/czero.nez
    constant CZERO_EQZ_FN3 : std_logic_vector(2 downto 0) := "101";     -- czero.eqz: rd = (rs2==0) ? 0 : rs1
    constant CZERO_NEZ_FN3 : std_logic_vector(2 downto 0) := "111";     -- czero.nez: rd = (rs2!=0) ? 0 : rs1

    -- RV32 Zknd/Zkne (AES-32): OP opcode 0110011, funct3=000, with instruction bits 31..30 = bs (the byte-select, a SEPARATE ALU input) and bits 29..25 = funct5 (funct7(4 downto 0)).
    -- All four ops share funct3=000, the funct5 field selects the operation, and bs is a don't-care in decode, so all four bs values are legal.
    constant AES_FN3       : std_logic_vector(2 downto 0) := "000";     -- funct3 for all aes32* ops
    constant AES32ESI_FN5  : std_logic_vector(4 downto 0) := "10001";   -- aes32esi  (encrypt, SubBytes only)
    constant AES32ESMI_FN5 : std_logic_vector(4 downto 0) := "10011";   -- aes32esmi (encrypt, SubBytes + MixColumns)
    constant AES32DSI_FN5  : std_logic_vector(4 downto 0) := "10101";   -- aes32dsi  (decrypt, inv-SubBytes)
    constant AES32DSMI_FN5 : std_logic_vector(4 downto 0) := "10111";   -- aes32dsmi (decrypt, inv-SubBytes + inv-MixColumns)
    /* ==========================================
       RV32 Zknh (SHA-256 / SHA-512) scalar-crypto constants
       ==========================================
       SHA-256 sigma/sum: UNARY, OP-IMM opcode (I_ARITH_OPCODE), funct3=001, bits[31:25]=0001000 (SHA256_FN7), and the rs2-field (imm12[4:0]) selects the op.
       Encoded here as the full 12-bit funct12 (imm12 = 0001000_<rs2field>) so the alu_control emitter can match it exactly and take priority over SLLI. */
    constant SHA256_FN3       : std_logic_vector(2 downto 0)  := "001";           -- OP-IMM funct3 for sha256*
    constant SHA256_FN7       : std_logic_vector(6 downto 0)  := "0001000";       -- bits[31:25] for sha256*
    constant SHA256SUM0_IMM12 : std_logic_vector(11 downto 0) := "000100000000";  -- rs2field=00000
    constant SHA256SUM1_IMM12 : std_logic_vector(11 downto 0) := "000100000001";  -- rs2field=00001
    constant SHA256SIG0_IMM12 : std_logic_vector(11 downto 0) := "000100000010";  -- rs2field=00010
    constant SHA256SIG1_IMM12 : std_logic_vector(11 downto 0) := "000100000011";  -- rs2field=00011

    -- SHA-512 sigma/sum (RV32): BINARY, OP opcode (R_OPCODE), funct3=000, and the full funct7 selects the op (bits[31:30]=01).
    -- rs1 and rs2 supply the two 32-bit halves.
    constant SHA512_FN3       : std_logic_vector(2 downto 0)  := "000";           -- OP funct3 for sha512*
    constant SHA512SUM0R_FN7  : std_logic_vector(6 downto 0)  := "0101000";       -- funct5=01000
    constant SHA512SUM1R_FN7  : std_logic_vector(6 downto 0)  := "0101001";       -- funct5=01001
    constant SHA512SIG0L_FN7  : std_logic_vector(6 downto 0)  := "0101010";       -- funct5=01010
    constant SHA512SIG1L_FN7  : std_logic_vector(6 downto 0)  := "0101011";       -- funct5=01011
    constant SHA512SIG0H_FN7  : std_logic_vector(6 downto 0)  := "0101110";       -- funct5=01110
    constant SHA512SIG1H_FN7  : std_logic_vector(6 downto 0)  := "0101111";       -- funct5=01111


	-- RV32 CSR (Control and Status Register) instruction constants
    -- CSR instruction funct3 codes (use SYSTEM_OPCODE)
    constant CSRRW_FN3   : std_logic_vector(2 downto 0) := "001"; -- CSR Read/Write
    constant CSRRS_FN3   : std_logic_vector(2 downto 0) := "010"; -- CSR Read and Set
    constant CSRRC_FN3   : std_logic_vector(2 downto 0) := "011"; -- CSR Read and Clear
    constant CSRRWI_FN3  : std_logic_vector(2 downto 0) := "101"; -- CSR Read/Write Immediate
    constant CSRRSI_FN3  : std_logic_vector(2 downto 0) := "110"; -- CSR Read and Set Immediate
    constant CSRRCI_FN3  : std_logic_vector(2 downto 0) := "111"; -- CSR Read and Clear Immediate

    -- Zimop may-be-operations (mop.r.N / mop.rr.N) share this SYSTEM funct3; it is not a CSR or PRIV funct3, so it is a decode hole.
    -- Encoding: SYSTEM opcode, funct3=100, bit31=1, bits29..28=00, and bit25 picks the form, 0 giving mop.r (bits25..22=0111) and 1 giving mop.rr.
    constant MOP_FN3     : std_logic_vector(2 downto 0) := "100"; -- Zimop mop.r/mop.rr funct3
    
    -- Minimal CSR addresses: only performance counters
    -- Machine Information Registers (Read-only)
    constant CSR_MHARTID    : std_logic_vector(11 downto 0) := x"F14"; -- Hart ID (0 in single-core; unique per hart in MCU_MP)
    -- The rest of the machine-information block; all four read ZERO and never trap.
    constant CSR_MVENDORID  : std_logic_vector(11 downto 0) := x"F11"; -- Vendor ID (0 = non-commercial implementation)
    constant CSR_MARCHID    : std_logic_vector(11 downto 0) := x"F12"; -- Architecture ID (0 = not assigned)
    constant CSR_MIMPID     : std_logic_vector(11 downto 0) := x"F13"; -- Implementation ID (0 = not implemented)
    constant CSR_MCONFIGPTR : std_logic_vector(11 downto 0) := x"F15"; -- Config-structure pointer (0 = no structure)
    constant CSR_MISA       : std_logic_vector(11 downto 0) := x"301"; -- ISA and extensions (read-only; reflects the ENABLE_* generics)
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

    -- Zihpm hardware performance-monitor CSRs: counters 3 and 4 are real 64-bit event counters when ENABLE_ZIHPM, counters 5-31 are hardwired zero.
    -- The full ranges (0xB03-0xB1F/0xB83-0xB9F machine, 0x323-0x33F event selectors, 0xC03-0xC1F/0xC83-0xC9F user-view) are LEGAL CSR addresses in the csr_valid map, so unimplemented indices read zero and ignore writes WITHOUT an illegal trap.
    constant CSR_MCOUNTINHIBIT : std_logic_vector(11 downto 0) := x"320"; -- Counter-inhibit (bits 3/4 gate hpm3/4; 0/2 gate mcycle/minstret)
    constant CSR_MCOUNTEREN    : std_logic_vector(11 downto 0) := x"306"; -- Counter-enable (M-mode-only core: read-zero/write-ignore)
    constant CSR_MHPMEVENT3    : std_logic_vector(11 downto 0) := x"323"; -- Event selector for mhpmcounter3
    constant CSR_MHPMEVENT4    : std_logic_vector(11 downto 0) := x"324"; -- Event selector for mhpmcounter4
    constant CSR_MHPMCOUNTER3  : std_logic_vector(11 downto 0) := x"B03"; -- Machine perf counter 3 low
    constant CSR_MHPMCOUNTER4  : std_logic_vector(11 downto 0) := x"B04"; -- Machine perf counter 4 low
    constant CSR_MHPMCOUNTER3H : std_logic_vector(11 downto 0) := x"B83"; -- Machine perf counter 3 high
    constant CSR_MHPMCOUNTER4H : std_logic_vector(11 downto 0) := x"B84"; -- Machine perf counter 4 high
    constant CSR_HPMCOUNTER3   : std_logic_vector(11 downto 0) := x"C03"; -- User-view perf counter 3 low
    constant CSR_HPMCOUNTER4   : std_logic_vector(11 downto 0) := x"C04"; -- User-view perf counter 4 low
    constant CSR_HPMCOUNTER3H  : std_logic_vector(11 downto 0) := x"C83"; -- User-view perf counter 3 high
    constant CSR_HPMCOUNTER4H  : std_logic_vector(11 downto 0) := x"C84"; -- User-view perf counter 4 high

    -- Zcmt jump-vector-table base CSR at 0x017, permission URW, which on this M-mode-only core means accessible.
    -- WARL: mode = bits(5:0) pinned 0 (Jump Table Mode only), base = bits(31:6) writable (64-byte aligned table); routed through the csr_valid map so a read or write is illegal when ENABLE_ZCMT is off.
    constant CSR_JVT           : std_logic_vector(11 downto 0) := x"017"; -- Zcmt jump-vector-table base (URW)

    /* ==========================================================================
       Privileged architecture: standard M-mode trap CSRs (ENABLE_TRAPCSR)
       ==========================================================================
       LEGAL only when ENABLE_TRAPCSR (maindec csr_addr_valid gates all ten); otherwise every one of these addresses is an unknown CSR and traps illegal instruction.
       Field and WARL behaviour is implemented in csr_unit.vhd; mtrapctl is the custom M-mode R/W CSR selecting legacy (irq_handler/IVT) against standard (mtvec) trap delivery. */
    constant CSR_MSTATUS   : std_logic_vector(11 downto 0) := x"300"; -- MIE(3)/MPIE(7)/MPP(12:11) WARL {11}; other bits read 0
    constant CSR_MSTATUSH  : std_logic_vector(11 downto 0) := x"310"; -- RV32 high half: legal, read-zero / write-ignore
    constant CSR_MTVEC     : std_logic_vector(11 downto 0) := x"305"; -- BASE(31:2) R/W; MODE(1:0) WARL {00} (direct only)
    constant CSR_MIE       : std_logic_vector(11 downto 0) := x"304"; -- MSIE(3)/MTIE(7)/MEIE(11) R/W; others 0; resets 0
    constant CSR_MIP       : std_logic_vector(11 downto 0) := x"344"; -- read-only mirror of the msip/mtip/meip level wires
    constant CSR_MSCRATCH  : std_logic_vector(11 downto 0) := x"340"; -- full 32-bit R/W scratch
    constant CSR_MEPC      : std_logic_vector(11 downto 0) := x"341"; -- bit0 always 0; bit1 writable iff ENABLE_COMPRESSED
    constant CSR_MCAUSE    : std_logic_vector(11 downto 0) := x"342"; -- Interrupt(31) + code(3:0); bits 30:4 read 0
    constant CSR_MTVAL     : std_logic_vector(11 downto 0) := x"343"; -- trap value (32-bit R/W; hardware-written on entry)
    constant CSR_MTRAPCTL  : std_logic_vector(11 downto 0) := x"7C0"; -- custom: bit0 LEGACY (reset 1); bits 31:1 WARL 0

    /* ==========================================================================
       Debug mode: the Debug-Mode CSR block 0x7B0-0x7B3 (ENABLE_DEBUG)
       ==========================================================================
       ACCESSIBLE ONLY IN DEBUG MODE, enforced by two deliberately asymmetric and purely combinational rules:
         ADMIT NARROW: maindec's csr_addr_valid names these FOUR addresses as explicit equalities under ENABLE_DEBUG, so 0x7B4-0x7BF keep trapping in every build.
         DENY WIDE: maindec's dbg_csr_denied blocks the WHOLE imm12(11:4)=0x7B nibble whenever debug_mode = '0', UNGATED by ENABLE_DEBUG, so a future fifth debug CSR cannot be admitted without also being denied. */
    constant CSR_DCSR      : std_logic_vector(11 downto 0) := x"7B0"; -- xdebugver(31:28)=4 RO, ebreakm(15), ebreaku(12), cause(8:6) RO, step(2), prv(1:0)
    constant CSR_DPC       : std_logic_vector(11 downto 0) := x"7B1"; -- bit0 always 0; bit1 writable iff ENABLE_COMPRESSED (the mepc WARL shape)
    constant CSR_DSCRATCH0 : std_logic_vector(11 downto 0) := x"7B2"; -- full 32-bit R/W scratch (debug mode only)
    constant CSR_DSCRATCH1 : std_logic_vector(11 downto 0) := x"7B3"; -- full 32-bit R/W scratch (debug mode only)

    /* ==========================================================================
       PMP (Smpmp) CSR bank (ENABLE_PMP)
       ==========================================================================
       LEGAL only when ENABLE_PMP (maindec csr_addr_valid admits 0x3A0-0x3A3 and 0x3B0-0x3BF as one gated range pair); otherwise every one of these twenty addresses is an unknown CSR and traps illegal instruction.
       With PMP_ENTRIES = 8 the upper half (pmpcfg2/3, pmpaddr8-15) stays LEGAL but has no storage: WARL all-zero, write-ignore. */

    /* Field, WARL and lock behaviour, implemented in csr_unit.vhd:
         pmpcfg<n> packs FOUR entry cfg bytes (entry 4n+j = bits 8j+7 downto 8j).
         cfg byte = R(0) W(1) X(2) A(4:3) L(7), bits 6:5 WARL 0, W pinned 0 when R=0, A in {OFF=00, TOR=01, NA4=10, NAPOT=11} (G=0, all four legal).
         pmpaddr<i> stores bits 29:0 only, which are physical address bits 31:2; bits 31:30 are WARL 0 (they would name phys bits 33:32, beyond this 32-bit fabric).
         L=1 makes that entry's cfg byte AND pmpaddr<i> write-ignored until reset; an entry i locked with A=TOR also write-locks pmpaddr<i-1>. */

    -- The ADDRESSES ARE CONTIGUOUS BY CONSTRUCTION (0x3A0+n, 0x3B0+i), so csr_addr_valid uses unsigned range compares over these endpoints.
    -- The csr_unit WRITE arms stay EXACTLY decoded, one arm per constant: the csr_valid AND csr_addr_valid gate is defense-in-depth, never license for a wide write-arm decode.
    constant CSR_PMPCFG0   : std_logic_vector(11 downto 0) := x"3A0"; -- entries 0-3   cfg bytes
    constant CSR_PMPCFG1   : std_logic_vector(11 downto 0) := x"3A1"; -- entries 4-7   cfg bytes
    constant CSR_PMPCFG2   : std_logic_vector(11 downto 0) := x"3A2"; -- entries 8-11  cfg bytes
    constant CSR_PMPCFG3   : std_logic_vector(11 downto 0) := x"3A3"; -- entries 12-15 cfg bytes
    constant CSR_PMPADDR0  : std_logic_vector(11 downto 0) := x"3B0"; -- entry 0  address (bits 29:0 = phys 31:2)
    constant CSR_PMPADDR1  : std_logic_vector(11 downto 0) := x"3B1";
    constant CSR_PMPADDR2  : std_logic_vector(11 downto 0) := x"3B2";
    constant CSR_PMPADDR3  : std_logic_vector(11 downto 0) := x"3B3";
    constant CSR_PMPADDR4  : std_logic_vector(11 downto 0) := x"3B4";
    constant CSR_PMPADDR5  : std_logic_vector(11 downto 0) := x"3B5";
    constant CSR_PMPADDR6  : std_logic_vector(11 downto 0) := x"3B6";
    constant CSR_PMPADDR7  : std_logic_vector(11 downto 0) := x"3B7";
    constant CSR_PMPADDR8  : std_logic_vector(11 downto 0) := x"3B8";
    constant CSR_PMPADDR9  : std_logic_vector(11 downto 0) := x"3B9";
    constant CSR_PMPADDR10 : std_logic_vector(11 downto 0) := x"3BA";
    constant CSR_PMPADDR11 : std_logic_vector(11 downto 0) := x"3BB";
    constant CSR_PMPADDR12 : std_logic_vector(11 downto 0) := x"3BC";
    constant CSR_PMPADDR13 : std_logic_vector(11 downto 0) := x"3BD";
    constant CSR_PMPADDR14 : std_logic_vector(11 downto 0) := x"3BE";
    constant CSR_PMPADDR15 : std_logic_vector(11 downto 0) := x"3BF"; -- entry 15 address

    -- PMP cfg-byte field encodings, shared by csr_unit's WARL masking and pmp_unit's match decode: one source of truth for the A field.
    constant PMP_A_OFF     : std_logic_vector(1 downto 0) := "00";  -- null region (never matches)
    constant PMP_A_TOR     : std_logic_vector(1 downto 0) := "01";  -- top of range: pmpaddr[i-1] <= a < pmpaddr[i]
    constant PMP_A_NA4     : std_logic_vector(1 downto 0) := "10";  -- naturally aligned 4-byte
    constant PMP_A_NAPOT   : std_logic_vector(1 downto 0) := "11";  -- naturally aligned power-of-two >= 8

    -- SYSTEM/PRIV encodings: funct3 = 000 and the funct12 selects the op, LEGAL only when ENABLE_TRAPCSR (maindec's SYSTEM valid_funct arm); with the generic off all four stay illegal instructions.
    -- WFI is legal in M-mode always and in U-mode iff mstatus.TW = 0; the TW denial is a DECODE illegal, cause 2.
    constant PRIV_FN3      : std_logic_vector(2 downto 0)  := "000";  -- SYSTEM privileged/system funct3
    constant ECALL_IMM12   : std_logic_vector(11 downto 0) := x"000"; -- ECALL  (0x00000073)
    constant EBREAK_IMM12  : std_logic_vector(11 downto 0) := x"001"; -- EBREAK (0x00100073)
    constant MRET_IMM12    : std_logic_vector(11 downto 0) := x"302"; -- MRET   (0x30200073)
    constant WFI_IMM12     : std_logic_vector(11 downto 0) := x"105"; -- WFI    (0x10500073)
    -- DRET (0x7B200073) joins the legal set when ENABLE_DEBUG, and ONLY in debug mode; outside it the encoding falls to the PRIV arm's `else valid_funct <= '0'` and is an illegal instruction.
    -- NOTE the funct12 0x7B2 collides numerically with the dscratch0 CSR ADDRESS above: the two never meet, because a CSR instruction has funct3 /= PRIV_FN3 by construction (is_csr_instr).
    constant DRET_IMM12    : std_logic_vector(11 downto 0) := x"7B2"; -- DRET   (0x7B200073)

    /* ==========================================================================
       Zfinx (single-precision FP in x-registers) constants
       ==========================================================================
       FP status CSRs, LEGAL only when ENABLE_ZFINX (csr_addr_valid gates them); otherwise these three addresses are unknown CSRs and trap illegal instruction. */
    constant CSR_FFLAGS  : std_logic_vector(11 downto 0) := x"001"; -- accrued flags {NV,DZ,OF,UF,NX}
    constant CSR_FRM     : std_logic_vector(11 downto 0) := x"002"; -- dynamic rounding mode [2:0]
    constant CSR_FCSR    : std_logic_vector(11 downto 0) := x"003"; -- frm[7:5] | fflags[4:0]

    -- OP-FP and FMA opcodes (RV32F encodings, reused by Zfinx on x-registers).
    -- fmv.w.x and fmv.x.w are DELIBERATELY absent (no separate F regfile in Zfinx), so their funct7 codes never appear in the legal decode and stay illegal.
    constant OPFP_OPCODE   : std_logic_vector(6 downto 0) := "1010011"; -- 0x53 OP-FP
    constant FMADD_OPCODE  : std_logic_vector(6 downto 0) := "1000011"; -- 0x43 FMADD
    constant FMSUB_OPCODE  : std_logic_vector(6 downto 0) := "1000111"; -- 0x47 FMSUB
    constant FNMSUB_OPCODE : std_logic_vector(6 downto 0) := "1001011"; -- 0x4B FNMSUB
    constant FNMADD_OPCODE : std_logic_vector(6 downto 0) := "1001111"; -- 0x4F FNMADD

    -- OP-FP funct7 fields (single precision, fmt=00).
    constant FADD_FN7    : std_logic_vector(6 downto 0) := "0000000"; -- fadd.s
    constant FSUB_FN7    : std_logic_vector(6 downto 0) := "0000100"; -- fsub.s
    constant FMUL_FN7    : std_logic_vector(6 downto 0) := "0001000"; -- fmul.s
    constant FDIV_FN7    : std_logic_vector(6 downto 0) := "0001100"; -- fdiv.s
    constant FSQRT_FN7   : std_logic_vector(6 downto 0) := "0101100"; -- fsqrt.s   (rs2=00000)
    constant FSGNJ_FN7   : std_logic_vector(6 downto 0) := "0010000"; -- fsgnj/n/x (rm 000/001/010)
    constant FMINMAX_FN7 : std_logic_vector(6 downto 0) := "0010100"; -- fmin/fmax (rm 000/001)
    constant FCMP_FN7    : std_logic_vector(6 downto 0) := "1010000"; -- fle/flt/feq (rm 000/001/010)
    constant FCVTW_FN7   : std_logic_vector(6 downto 0) := "1100000"; -- fcvt.w.s/fcvt.wu.s (rs2 00000/00001)
    constant FCVTS_FN7   : std_logic_vector(6 downto 0) := "1101000"; -- fcvt.s.w/fcvt.s.wu (rs2 00000/00001)
    constant FCLASS_FN7  : std_logic_vector(6 downto 0) := "1110000"; -- fclass.s (rm=001); fmv.x.w (rm=000) stays illegal

    -- rs2 selector field for the two-operand converts / sqrt (instr[24:20]).
    constant FP_RS2_W    : std_logic_vector(4 downto 0) := "00000"; -- .w  / sqrt rs2
    constant FP_RS2_WU   : std_logic_vector(4 downto 0) := "00001"; -- .wu

    -- Dynamic rounding-mode selector in funct3: rm=111 means use frm.
    constant FRM_DYN     : std_logic_vector(2 downto 0) := "111";

    -- FPU op encodings, multi-cycle unit fp_op[3:0]:
    constant FPOP_FADD     : std_logic_vector(3 downto 0) := "0000"; -- 0
    constant FPOP_FSUB     : std_logic_vector(3 downto 0) := "0001"; -- 1
    constant FPOP_FMUL     : std_logic_vector(3 downto 0) := "0010"; -- 2
    constant FPOP_FDIV     : std_logic_vector(3 downto 0) := "0011"; -- 3
    constant FPOP_FSQRT    : std_logic_vector(3 downto 0) := "0100"; -- 4
    constant FPOP_FMADD    : std_logic_vector(3 downto 0) := "0101"; -- 5
    constant FPOP_FMSUB    : std_logic_vector(3 downto 0) := "0110"; -- 6
    constant FPOP_FNMSUB   : std_logic_vector(3 downto 0) := "0111"; -- 7
    constant FPOP_FNMADD   : std_logic_vector(3 downto 0) := "1000"; -- 8
    constant FPOP_FCVT_W_S : std_logic_vector(3 downto 0) := "1001"; -- 9
    constant FPOP_FCVT_WU_S: std_logic_vector(3 downto 0) := "1010"; -- 10
    constant FPOP_FCVT_S_W : std_logic_vector(3 downto 0) := "1011"; -- 11
    constant FPOP_FCVT_S_WU: std_logic_vector(3 downto 0) := "1100"; -- 12

    -- Single-cycle unit fp_s_op[3:0]:
    constant FPSOP_FSGNJ   : std_logic_vector(3 downto 0) := "0000"; -- 0
    constant FPSOP_FSGNJN  : std_logic_vector(3 downto 0) := "0001"; -- 1
    constant FPSOP_FSGNJX  : std_logic_vector(3 downto 0) := "0010"; -- 2
    constant FPSOP_FEQ     : std_logic_vector(3 downto 0) := "0011"; -- 3
    constant FPSOP_FLT     : std_logic_vector(3 downto 0) := "0100"; -- 4
    constant FPSOP_FLE     : std_logic_vector(3 downto 0) := "0101"; -- 5
    constant FPSOP_FMIN    : std_logic_vector(3 downto 0) := "0110"; -- 6
    constant FPSOP_FMAX    : std_logic_vector(3 downto 0) := "0111"; -- 7
    constant FPSOP_FCLASS  : std_logic_vector(3 downto 0) := "1000"; -- 8

    -- FP writeback result_src codes: 110 is the single-cycle fpu_simple result in EXECUTE, 111 is the multi-cycle fpu result at FPU_DONE.
    -- 101 is taken by Zimop.
    constant RSRC_FP_SINGLE : std_logic_vector(2 downto 0) := "110";
    constant RSRC_FP_MULTI  : std_logic_vector(2 downto 0) := "111";



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

   /* --------------------------------------------------------------------------
      Finds the MSbit index required to represent a given positive number.
      -------------------------------------------------------------------------- */
	function ceil_log2 (value : positive) return natural is
		variable result : natural;
	begin
		result := 0;
		while (value > (2**result)) loop
			result := result + 1;
		end loop;
		return result;
	end function ceil_log2;

	/* --------------------------------------------------------------------------
	   Converts a signed integer into a standard logic vector (uses numeric_std)
	   -------------------------------------------------------------------------- */
	function int2slv(x : integer; num_bits : integer) return std_logic_vector is
	begin
		return std_logic_vector(to_signed(x, num_bits));
	end int2slv;

	/* --------------------------------------------------------------------------
	   Converts an unsigned integer into a standard logic vector (uses numeric_std)
	   -------------------------------------------------------------------------- */
	function uint2slv(x : integer; num_bits : integer) return std_logic_vector is
	begin
		return std_logic_vector(to_unsigned(x, num_bits));
	end uint2slv;

	/* --------------------------------------------------------------------------
	   Converts a standard logic vector into a signed integer (uses numeric_std)
	   -------------------------------------------------------------------------- */
	function slv2int(x: slv) return integer is
	begin
		return to_integer(signed(x));
	end slv2int;

	/* --------------------------------------------------------------------------
	   Converts a standard logic vector into an unsigned integer (uses numeric_std)
	   -------------------------------------------------------------------------- */
	function slv2uint(x: slv) return integer is
	begin
		return to_integer(unsigned(x));
	end slv2uint;

	/* --------------------------------------------------------------------------
	   Converts a boolean into a std_logic
	   -------------------------------------------------------------------------- */
	function bool2sl(x : boolean) return sl is
	begin
		if x then
			return('1');
		else
			return('0');
		end if;
	end bool2sl;
	
	/* --------------------------------------------------------------------------
	   ORs all bits in a std_logic_vector together
	   -------------------------------------------------------------------------- */
	function or_reduct(x : slv) return sl is
		variable ret_val : sl := '0';
	begin
		for i in x'range loop
			ret_val := ret_val or x(i);
		end loop;
		return ret_val;
	
	end or_reduct;
	
	/* --------------------------------------------------------------------------
	   ANDs all bits in a std_logic_vector together
	   -------------------------------------------------------------------------- */
	function and_reduct(x : slv) return sl is
		variable ret_val : sl := '1';
	begin
		for i in x'range loop
			ret_val := ret_val and x(i);
		end loop;
		return ret_val;
	end and_reduct;
	
	/* --------------------------------------------------------------------------
	   Reverses the ordering of the bits in a standard logic vector
	   -------------------------------------------------------------------------- */
	function reverse_slv_order(x : slv) return slv is
		variable result : slv(x'high downto x'low);
	begin
		for index in x'high downto x'low loop
			result(index) := x(x'high - index);
		end loop;
		return result;
	end reverse_slv_order;

end constants;