library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use ieee.math_real.log2;

package constants is

    -- Core width parameterization (2026-07-18). XLEN is the vesta DATAPATH
    -- width: registers, ALU operands, addresses, PC, CSR values. ILEN is the
    -- INSTRUCTION word width — a separate constant because on RV64 it stays 32
    -- while XLEN doubles; every core width reference is categorized against one
    -- of these (or a derived width below), never a bare 32. Only XLEN=32 is
    -- implemented/verified: the SoC fabric (arbiter, tile boundary, peripherals,
    -- SRAMs) is a fixed 32-bit bus, and the RV64-only instructions/CSR layouts
    -- do not exist yet. Changing XLEN here is a starting point, not a knob.
    constant XLEN       : natural := 32;              -- datapath/register width
    constant ILEN       : natural := 32;              -- instruction word width (32 even on RV64)
    constant XLEN_BYTES : natural := XLEN / 8;        -- bus byte lanes (wen width)
    constant SHAMT_W    : natural := 5;               -- shift-amount width = ceil_log2(XLEN)

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

    -- X1 Zihintpause: PAUSE = `fence w,0` = 0x0100000F. Its FENCE immediate
    -- field instr[31:20] = fm(0) | pred(W=0001) | succ(0000) = 0x010. maindec
    -- detects the exact PAUSE hint on (FENCE_OPCODE, FENCE_FN3, imm12=PAUSE_IMM12)
    -- gated by ENABLE_ZIHINT; every other FENCE encoding stays an ordering nop.
    constant PAUSE_IMM12     : std_logic_vector(11 downto 0) := "000000010000"; -- 0x010

    -- X1 Zihintpause side-effect window (decision D6): when ENABLE_ZIHINT, a
    -- retiring PAUSE holds this hart OUT of the shared-bus request contest for
    -- this many clk_cpu cycles (its arbiter req stays low while it waits in the
    -- PAUSE_WAIT state), long enough for a competing hart to win arbitration
    -- and far below any timeout scale. 0 = no side-effect (PAUSE is a plain
    -- fence-nop) -- the value the negative-control seed forces to prove the
    -- directed mp latency test actually observes the window.
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
    constant AMO_WIDTH_B : std_logic_vector(2 downto 0) := "000"; -- X2 Zabha: byte-width atomic operations
    constant AMO_WIDTH_H : std_logic_vector(2 downto 0) := "001"; -- X2 Zabha: halfword-width atomic operations

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
    constant CAS_FN5     : std_logic_vector(4 downto 0) := "00101"; -- X2 Zacas: Compare-and-Swap (amocas.w/.b/.h)

    -- X1 Zawrs (Wait-on-Reservation-Set). SYSTEM opcode (1110011), funct3=000,
    -- rs1=x0, rd=x0; distinguished by the 12-bit funct12 (imm12) field. These
    -- are currently-illegal SYSTEM encodings when ENABLE_ZAWRS is false.
    constant WRS_NTO_IMM12 : std_logic_vector(11 downto 0) := x"00D"; -- wrs.nto (wait, no timeout)
    constant WRS_STO_IMM12 : std_logic_vector(11 downto 0) := x"01D"; -- wrs.sto (wait, short timeout)
    -- (wrs.sto short-timeout count lives as WRS_TIMEOUT_CYCLES in vesta.vhd.)

    -- X3 Zicboz (cache-block zero — cbo.zero). MISC-MEM/FENCE opcode (0001111),
    -- funct3=010 (CBO_FN3), rd-field=00000; the imm12 field selects the op:
    --   cbo.zero  = 0x004  (legal only under ENABLE_ZICBOZ)
    --   cbo.clean = 0x001 / cbo.flush = 0x002 / cbo.inval = 0x000 -> ALWAYS
    --   ILLEGAL in both polarities (D4; otherwise-reserved MISC-MEM funct3=010).
    -- Effective address = X[rs1] (no offset); cbo.zero writes 0x00000000 to the
    -- 16 words of the naturally-aligned CBOZ_BLOCK_SIZE-byte block containing it.
    constant CBO_FN3         : std_logic_vector(2 downto 0)  := "010";  -- cbo.* funct3 (MISC-MEM)
    constant CBOZ_IMM12      : std_logic_vector(11 downto 0) := x"004"; -- cbo.zero imm[11:0]
    -- Spec-fixed granule (x35_specs.md §X3.5.1): a future bump is a one-line
    -- change here (cboz_idx range + base mask in vesta.vhd derive from these).
    constant CBOZ_BLOCK_SIZE : natural := 64;                    -- bytes (16 words)
    constant CBOZ_WORDS      : natural := CBOZ_BLOCK_SIZE / 4;   -- word stores per cbo.zero

    -- ==========================================================================
    -- X3 Zcmp / Zcmt (compressed push/pop + table jump)
    -- ==========================================================================
    -- These live in the C2 quadrant funct3=101 slot (the c.fsdsp slot, free on
    -- this no-F/D core). c_dec.vhd recognises the compressed encodings and, for a
    -- LEGAL cm.* (generic on + valid fields), emits a fixed-shape 32-bit SENTINEL
    -- word (below); an illegal cm.* pattern or generic-off leaves dec=0 (illegal),
    -- so the OFF build is bit-identical. The sentinel is consumed by maindec
    -- (op = ZCM_SENTINEL_OP -> zcm_op, valid) and by vesta's push/pop/move/jump
    -- SEQUENCER. All six push/pop/move insns and cm.jt/cm.jalt need multiple
    -- register writes / a memory burst / a control-flow redirect, so none can be a
    -- single expanded 32-bit instruction (unlike Zcb) -- they run in the FSM.
    --
    -- Sentinel opcode: bits(1:0) = "10" so NO real decompressed instruction (which
    -- always ends "11") and no reserved-compressed hole (dec = all-zero, op
    -- "0000000") can ever collide with it. The ONLY producer of this op pattern is
    -- c_dec's sentinel synthesis, itself gated on ENABLE_ZCMP/ENABLE_ZCMT -- so a
    -- raw 32-bit word can never be mistaken for a cm.* (a raw custom-opcode word
    -- keeps trapping illegal exactly as in the base).
    constant ZCM_SENTINEL_OP : std_logic_vector(6 downto 0) := "0101010"; -- Zcmp/Zcmt sentinel opcode (bits 1:0 = 10)
    -- Sub-op selector, carried in sentinel bits(14:12) (the funct3 field position):
    constant ZCM_SUB_PUSH    : std_logic_vector(2 downto 0) := "000"; -- cm.push
    constant ZCM_SUB_POP     : std_logic_vector(2 downto 0) := "001"; -- cm.pop
    constant ZCM_SUB_POPRET  : std_logic_vector(2 downto 0) := "010"; -- cm.popret
    constant ZCM_SUB_POPRETZ : std_logic_vector(2 downto 0) := "011"; -- cm.popretz
    constant ZCM_SUB_MVSA01  : std_logic_vector(2 downto 0) := "100"; -- cm.mvsa01 (a0/a1 -> s-regs)
    constant ZCM_SUB_MVA01S  : std_logic_vector(2 downto 0) := "101"; -- cm.mva01s (s-regs -> a0/a1)
    constant ZCM_SUB_TABJUMP : std_logic_vector(2 downto 0) := "110"; -- cm.jt / cm.jalt (index selects)
    -- The original 16-bit compressed instruction is embedded in sentinel(31:16),
    -- so vesta slices the operand fields directly at their spec bit positions:
    --   rlist = i16(7:4)  = sentinel(23:20)     spimm = i16(3:2) = sentinel(19:18)
    --   sreg1 = i16(9:7)  = sentinel(25:23)     sreg2 = i16(4:2) = sentinel(20:18)
    --   index = i16(9:2)  = sentinel(25:18)
    -- rlist -> reg count (Zcmp): rlist 4..14 -> rlist-3 regs; rlist 15 -> 13 regs
    -- (adds s10+s11); rlist 0..3 are reserved (c_dec emits illegal). stack_adj =
    -- stack_adj_base + spimm*16; base 16 (rlist 4-7) / 32 (8-11) / 48 (12-14) /
    -- 64 (15). Zcmt table = 256 x 32b at {jvt[31:6],6'b0}; target = mem[base+idx*4].


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

	-- RV32 Zbkb / Zbkx (scalar-crypto bit-manip, X3 Stage B) constants.
    -- pack/packh share funct7 with Zbb ZEXT.H (both 0000100); pack rs2=x0 == zext.h.
    constant PACK_FN7    : std_logic_vector(6 downto 0)  := "0000100";      -- pack / packh (R-type)
    constant PACK_FN3    : std_logic_vector(2 downto 0)  := "100";          -- pack
    constant PACKH_FN3   : std_logic_vector(2 downto 0)  := "111";          -- packh
    -- brev8/zip/unzip are OP-IMM (funct7+rs2 fixed -> imm12 = instr[31:20]).
    constant BREV8_IMM12 : std_logic_vector(11 downto 0) := "011010000111"; -- brev8 (0x687: funct7=0110100,rs2=00111,funct3=101)
    constant ZIP_IMM12   : std_logic_vector(11 downto 0) := "000010001111"; -- zip   (0x08F: funct7=0000100,rs2=01111,funct3=001)
    constant UNZIP_IMM12 : std_logic_vector(11 downto 0) := "000010001111"; -- unzip (0x08F: funct7=0000100,rs2=01111,funct3=101)
    -- xperm8/xperm4 crossbar permute (R-type; funct7 0010100 == BSETI_FN7 but
    -- distinguished by funct3 100/010 vs BSET's 001, so no decode overlap).
    constant XPERM_FN7   : std_logic_vector(6 downto 0)  := "0010100";      -- xperm8 / xperm4 (R-type)
    constant XPERM8_FN3  : std_logic_vector(2 downto 0)  := "100";          -- xperm8
    constant XPERM4_FN3  : std_logic_vector(2 downto 0)  := "010";          -- xperm4


	-- RV32 Zicond (Integer Conditional Operations) constants (R-type instructions)
    constant ZICOND_FN7    : std_logic_vector(6 downto 0) := "0000111"; -- funct7 for czero.eqz/czero.nez
    constant CZERO_EQZ_FN3 : std_logic_vector(2 downto 0) := "101";     -- czero.eqz: rd = (rs2==0) ? 0 : rs1
    constant CZERO_NEZ_FN3 : std_logic_vector(2 downto 0) := "111";     -- czero.nez: rd = (rs2!=0) ? 0 : rs1

    -- RV32 Zknd/Zkne (AES-32) constants (X3). OP opcode 0110011, funct3=000, with
    -- instruction bits 31..30 = bs (the byte-select, a SEPARATE ALU input) and
    -- bits 29..25 = funct5 (funct7(4 downto 0)). All four ops share funct3=000; the
    -- funct5 field selects the operation and bs is a don't-care in decode (all four
    -- bs values legal). Authoritative from riscv-opcodes rv32_zknd / rv32_zkne.
    constant AES_FN3       : std_logic_vector(2 downto 0) := "000";     -- funct3 for all aes32* ops
    constant AES32ESI_FN5  : std_logic_vector(4 downto 0) := "10001";   -- aes32esi  (encrypt, SubBytes only)
    constant AES32ESMI_FN5 : std_logic_vector(4 downto 0) := "10011";   -- aes32esmi (encrypt, SubBytes + MixColumns)
    constant AES32DSI_FN5  : std_logic_vector(4 downto 0) := "10101";   -- aes32dsi  (decrypt, inv-SubBytes)
    constant AES32DSMI_FN5 : std_logic_vector(4 downto 0) := "10111";   -- aes32dsmi (decrypt, inv-SubBytes + inv-MixColumns)
    -- ==========================================
    -- RV32 Zknh (SHA-256 / SHA-512) scalar-crypto constants (X3 Stage B)
    -- ==========================================
    -- SHA-256 sigma/sum: UNARY, OP-IMM opcode (I_ARITH_OPCODE), funct3=001,
    -- bits[31:25]=0001000 (SHA256_FN7); the rs2-field (imm12[4:0]) selects the op.
    -- Encoded here as the full 12-bit funct12 (imm12 = 0001000_<rs2field>) so the
    -- alu_control emitter can match it exactly (and take priority over SLLI).
    -- Authoritative: riscv-opcodes rv32_zknh / ratified Zknh spec.
    constant SHA256_FN3       : std_logic_vector(2 downto 0)  := "001";           -- OP-IMM funct3 for sha256*
    constant SHA256_FN7       : std_logic_vector(6 downto 0)  := "0001000";       -- bits[31:25] for sha256*
    constant SHA256SUM0_IMM12 : std_logic_vector(11 downto 0) := "000100000000";  -- rs2field=00000
    constant SHA256SUM1_IMM12 : std_logic_vector(11 downto 0) := "000100000001";  -- rs2field=00001
    constant SHA256SIG0_IMM12 : std_logic_vector(11 downto 0) := "000100000010";  -- rs2field=00010
    constant SHA256SIG1_IMM12 : std_logic_vector(11 downto 0) := "000100000011";  -- rs2field=00011

    -- SHA-512 sigma/sum (RV32): BINARY, OP opcode (R_OPCODE), funct3=000, full
    -- funct7 selects the op (bits[31:30]=01). rs1,rs2 supply the two 32-bit halves.
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

    -- Zimop may-be-operations (mop.r.N / mop.rr.N) share this SYSTEM funct3;
    -- it is not a CSR/PRIV funct3, so it is a decode hole today (X1 Zimop).
    -- Authoritative encoding (riscv-opcodes rv_zimop): SYSTEM opcode, funct3=100,
    -- bit31=1, bits29..28=00, bit25=0 -> mop.r (bits25..22=0111), bit25=1 -> mop.rr.
    constant MOP_FN3     : std_logic_vector(2 downto 0) := "100"; -- Zimop mop.r/mop.rr funct3
    
    -- Minimal CSR addresses - only performance counters
    -- Machine Information Registers (Read-only)
    constant CSR_MHARTID    : std_logic_vector(11 downto 0) := x"F14"; -- Hart ID (0 in single-core; unique per hart in MCU_MP)
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

    -- X1 Zihpm: hardware performance-monitor CSRs. Counters 3/4 are real 64-bit
    -- event counters when ENABLE_ZIHPM; counters 5-31 are hardwired zero. The
    -- full ranges (0xB03-0xB1F/0xB83-0xB9F machine, 0x323-0x33F event selectors,
    -- 0xC03-0xC1F/0xC83-0xC9F user-view) are LEGAL CSR addresses (csr_valid map)
    -- so unimplemented indices read-zero/write-ignore WITHOUT an illegal trap.
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

    -- X3 Zcmt: jump-vector-table base CSR. Address 0x017, permission URW. On this
    -- M-mode-only core URW = accessible. WARL: mode = bits(5:0) pinned 0 (only Jump
    -- Table Mode), base = bits(31:6) writable (64-byte aligned table). Routed
    -- through the csr_valid map so a read/write is illegal when ENABLE_ZCMT is off.
    constant CSR_JVT           : std_logic_vector(11 downto 0) := x"017"; -- Zcmt jump-vector-table base (URW)



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