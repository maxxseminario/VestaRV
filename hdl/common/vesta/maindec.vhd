library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.constants.all;

entity maindec is
    generic (
        -- Core ISA feature switches (config-driven from generate.py; defaults =
        -- the full RV32IMAC+Zba/Zbb/Zbs/Zbc core, so existing instantiations are
        -- unchanged). A disabled extension's encodings fall out of
        -- valid_opcode/valid_funct and take the illegal-instruction trap path.
        ENABLE_MUL      : boolean := true;
        ENABLE_DIV      : boolean := true;
        ENABLE_ATOMICS  : boolean := true;
        ENABLE_BITMANIP : boolean := true;
        -- X0 ISA-extension scaffolding (default false; decode logic added by the
        -- named phase). These arrive here but are not yet read by valid_funct/
        -- alu_control -- adding the decode is the phase agent's job.
        ENABLE_ZICOND   : boolean := false;  -- X1 (Zicond): consumed from phase X1 on; scaffolded X0
        ENABLE_ZIMOP    : boolean := false;  -- X1 (Zimop): consumed from phase X1 on; scaffolded X0
        ENABLE_ZIHINT   : boolean := false;  -- X1 (Zihint): consumed from phase X1 on; scaffolded X0
        ENABLE_ZAWRS    : boolean := false;  -- X1 (Zawrs): consumed from phase X1 on; scaffolded X0
        ENABLE_ZABHA    : boolean := false;  -- X2 (Zabha): consumed from phase X2 on; scaffolded X0
        ENABLE_ZACAS    : boolean := false;  -- X2 (Zacas): consumed from phase X2 on; scaffolded X0
        ENABLE_ZICBOZ   : boolean := false;  -- X3 (Zicboz): cbo.zero cache-block zero
        ENABLE_ZCMP     : boolean := false;  -- X3 (Zcmp): compressed push/pop + reg-moves
        ENABLE_ZCMT     : boolean := false;  -- X3 (Zcmt): compressed table jump + jvt CSR
        ENABLE_ZBKB     : boolean := false;  -- X3 (Zbkb): consumed from phase X3 on; scaffolded X0
        ENABLE_ZBKC     : boolean := false;  -- X3 (Zbkc): consumed from phase X3 on; scaffolded X0
        ENABLE_ZBKX     : boolean := false;  -- X3 (Zbkx): consumed from phase X3 on; scaffolded X0
        ENABLE_ZKN      : boolean := false;  -- X3 (Zkn): consumed from phase X3 on; scaffolded X0
        ENABLE_ZFINX    : boolean := false   -- X4 (Zfinx): consumed from phase X4 on; scaffolded X0
    );
    port (
        resetn           : in  STD_LOGIC;
        op               : in  STD_LOGIC_VECTOR(6 downto 0);
        funct3           : in  STD_LOGIC_VECTOR(2 downto 0);
        funct7           : in  STD_LOGIC_VECTOR(6 downto 0);
        mask             : in  STD_LOGIC_VECTOR(1 downto 0);
        imm12            : in  STD_LOGIC_VECTOR(11 downto 0); 
        
        -- Control outputs
        result_src       : out STD_LOGIC_VECTOR(2 downto 0);
        WEN              : out STD_LOGIC_VECTOR(XLEN_BYTES-1 downto 0);
        branch           : out STD_LOGIC;
        ALU_src          : out STD_LOGIC;
        div_op           : out STD_LOGIC;
        reg_write        : out STD_LOGIC;
        jump             : out STD_LOGIC;
        jalr             : out STD_LOGIC;
        imm_src          : out STD_LOGIC_VECTOR(2 downto 0);
        alu_control      : out STD_LOGIC_VECTOR(6 downto 0);  --  Now 7 bits
        mem_access_instr : out STD_LOGIC;
        
        -- Custom instruction outputs
        isr_ret          : out STD_LOGIC;
        sleep_rq         : out STD_LOGIC;
        wake_rq          : out STD_LOGIC;

        -- X1 Zawrs: wrs_op = decoded wrs.nto or wrs.sto (illegal unless
        -- ENABLE_ZAWRS and ENABLE_ATOMICS); wrs_sto = the timeout variant.
        wrs_op           : out STD_LOGIC;
        wrs_sto          : out STD_LOGIC;
        
        -- RV32A atomic operation signals
        amo_op           : out STD_LOGIC;
        lr_op            : out STD_LOGIC;
        sc_op            : out STD_LOGIC;
        fence_op         : out STD_LOGIC;

        -- X3 Zicboz: '1' for the exact cbo.zero encoding (MISC-MEM, funct3=010,
        -- imm12=0x004) when ENABLE_ZICBOZ; statically '0' otherwise (the encoding
        -- then traps illegal via the FENCE valid_funct fall-through). Consumed by
        -- vesta's FSM to launch the 16-word block-zero store sequencer.
        cboz_op          : out STD_LOGIC;

        -- X3 Zcmp/Zcmt: '1' for a legal cm.* SENTINEL (op = ZCM_SENTINEL_OP,
        -- produced only by c_dec, gated on the generics) -- launches vesta's
        -- push/pop/move/table-jump sequencer. Statically '0' when both generics
        -- are off (the sentinel opcode is then never valid). Sub-op + operand
        -- fields are read from the instruction word by vesta; maindec only needs
        -- to legalize the sentinel and flag it.
        zcm_op           : out STD_LOGIC;

        -- X1 Zihintpause: '1' for the exact PAUSE hint (fence w,0) when
        -- ENABLE_ZIHINT; statically '0' otherwise (so a disabled build's FENCE
        -- path is bit-identical). Consumed by vesta's FSM to open the PAUSE
        -- arbiter-yield window; never affects legality/trap (PAUSE is a FENCE).
        pause_hint       : out STD_LOGIC;

        -- CSR control signals
        csr_op           : out STD_LOGIC_VECTOR(2 downto 0); 
        csr_valid        : out STD_LOGIC;                    
        
        -- Trap signal for invalid instructions
        trap             : out STD_LOGIC
    );
end maindec;

architecture behave of maindec is

    -- ==========================================
    -- Internal Signal Declarations
    -- ==========================================
    signal read_data_flag  : std_logic;
    signal write_data_flag : std_logic;
    signal rtype_sub       : STD_LOGIC;
    signal valid_opcode    : STD_LOGIC;
    signal valid_funct     : STD_LOGIC;
    signal is_custom_instr : STD_LOGIC;
    signal is_mul_div      : STD_LOGIC;
    signal is_amo_instr    : STD_LOGIC;
    signal funct5          : STD_LOGIC_VECTOR(4 downto 0);
    signal is_fence        : STD_LOGIC;
    signal is_zba_instr    : STD_LOGIC;
    signal is_zbb_r_instr  : STD_LOGIC;  
    signal is_zbb_i_instr  : STD_LOGIC;  
    signal is_zbs_r_instr  : STD_LOGIC;  
    signal is_zbs_i_instr  : STD_LOGIC;
    signal is_zbc_instr    : STD_LOGIC;
    -- X3 Stage B scalar-crypto bit-manip helpers (Zbkb new ops, Zbkb/Zbb shared
    -- subset gated by ENABLE_ZBKB, and Zbkx crossbar permute). Zbkc reuses the
    -- existing is_zbc_instr (OR-gated below); it adds no new helper.
    signal is_zbkb_new_r_instr    : STD_LOGIC;  -- pack / packh
    signal is_zbkb_new_i_instr    : STD_LOGIC;  -- brev8 / zip / unzip
    signal is_zbkb_shared_r_instr : STD_LOGIC;  -- andn/orn/xnor/rol/ror when Zbb off
    signal is_zbkb_shared_i_instr : STD_LOGIC;  -- rori / rev8 when Zbb off
    signal is_zbkx_instr          : STD_LOGIC;  -- xperm8 / xperm4
    signal is_zicond_instr : STD_LOGIC;
    signal is_aes_instr    : STD_LOGIC;  -- X3 Zknd/Zkne: any aes32{e,d}s[m]i (gated by ENABLE_ZKN)
    signal is_csr_instr    : STD_LOGIC;
    -- X1 Zihpm base repair (UNCONDITIONAL): '1' iff the CSR address (imm12 =
    -- instr(31:20)) is architecturally KNOWN. A CSR instruction to an unknown
    -- address now drops valid_funct -> illegal-instruction trap, closing the
    -- priv-spec gap where every unknown CSR silently read zero.
    signal csr_addr_valid  : STD_LOGIC;
    signal is_zimop_instr  : STD_LOGIC;  -- X1 Zimop: mop.r.N / mop.rr.N (rd<-0)
    signal is_pause        : STD_LOGIC;
    signal is_cboz         : STD_LOGIC;  -- X3 Zicboz (cbo.zero)
    signal is_zcm          : STD_LOGIC;  -- X3 Zcmp/Zcmt (the cm.* sentinel)
    signal is_wrs_instr    : STD_LOGIC;  -- X1 Zawrs (wrs.nto / wrs.sto)
    signal is_std_amo_fn5  : STD_LOGIC;  -- X2 Zacas: one of the nine standard AMO funct5 codes (AMO decode-legality whitelist)
    -- X3 Zknh: SHA-256 (OP-IMM unary) / SHA-512 (OP binary) sigma/sum helpers,
    -- each gated on ENABLE_ZKN. Disabled -> both '0' -> the encodings trap illegal.
    signal is_sha256_instr : STD_LOGIC;  -- sha256sig0/sig1/sum0/sum1
    signal is_sha512_instr : STD_LOGIC;  -- sha512sig0l/h, sig1l/h, sum0r, sum1r


begin

    -- ==========================================
    -- Helper Signals
    -- ==========================================
    
    is_mul_div <= '1' when ((ENABLE_MUL or ENABLE_DIV) and op = R_OPCODE and funct7 = MULT_FN7) else '0';
    is_custom_instr <= '1' when (op = CUSTOM_OPCODE) else '0';
    is_amo_instr <= '1' when (ENABLE_ATOMICS and op = AMO_OPCODE) else '0';
    is_fence <= '1' when (op = FENCE_OPCODE and funct3 = FENCE_FN3) else '0';
    -- X1 Zawrs: SYSTEM opcode, funct3=000, funct12 (imm12) = 0x00D (nto) / 0x01D
    -- (sto). rs1/rd are architecturally x0 but not decoded here (maindec has no
    -- rs1/rd ports — the funct12 uniquely identifies these, as WFI is decoded).
    -- Gated on BOTH ENABLE_ZAWRS and ENABLE_ATOMICS (spec: useful only with A).
    is_wrs_instr <= '1' when (ENABLE_ZAWRS and ENABLE_ATOMICS and op = SYSTEM_OPCODE
                              and funct3 = "000"
                              and (imm12 = WRS_NTO_IMM12 or imm12 = WRS_STO_IMM12)) else '0';
    funct5 <= funct7(6 downto 2);
    -- X2 Zacas: the nine standard word/sub-word AMO funct5 codes. Used by the
    -- AMO_OPCODE decode-legality case to whitelist funct5 (LR/SC and CAS are
    -- handled separately; every other funct5 is a RESERVED encoding and traps).
    is_std_amo_fn5 <= '1' when (funct5 = AMOADD_FN5  or funct5 = AMOSWAP_FN5 or
                               funct5 = AMOXOR_FN5  or funct5 = AMOAND_FN5  or
                               funct5 = AMOOR_FN5   or funct5 = AMOMIN_FN5  or
                               funct5 = AMOMAX_FN5  or funct5 = AMOMINU_FN5 or
                               funct5 = AMOMAXU_FN5) else '0';
    rtype_sub <= funct7(5) and op(5);  -- TRUE for R-type subtract


    is_zba_instr <= '1' when (ENABLE_BITMANIP and op = R_OPCODE and funct7 = ZBA_FN7 and
                              (funct3 = SH1ADD_FN3 or funct3 = SH2ADD_FN3 or funct3 = SH3ADD_FN3)) else '0';


    is_zbb_r_instr <= '1' when (ENABLE_BITMANIP and op = R_OPCODE and (
        -- ANDN, ORN, XNOR
        (funct7 = ANDN_FN7 and (funct3 = "111" or funct3 = "110" or funct3 = "100")) or
        -- MIN, MINU, MAX, MAXU
        (funct7 = MIN_FN7 and (funct3 = "100" or funct3 = "101" or funct3 = "110" or funct3 = "111")) or
        -- ROL, ROR
        (funct7 = ROL_FN7 and (funct3 = "001" or funct3 = "101")) or
        -- ZEXT.H 
        (funct7 = ZEXT_FN7 and funct3 = "100")
    )) else '0';


    is_zbb_i_instr <= '1' when (ENABLE_BITMANIP and op = I_ARITH_OPCODE and (
        -- RORI 
        (funct3 = "101" and funct7 = RORI_FN7) or
        -- CLZ, CTZ, CPOP, SEXT.B, SEXT.H, ORC.B, REV8 
        (funct3 = "001" and (imm12 = CLZ_IMM12 or imm12 = CTZ_IMM12 or imm12 = CPOP_IMM12 or
                             imm12 = SEXT_B_IMM12 or imm12 = SEXT_H_IMM12 or 
                             imm12 = ORC_B_IMM12 or imm12 = REV8_IMM12)) or
        -- ZEXT.H via ANDI special encoding
        (funct3 = "100" and imm12 = ZEXT_H_IMM12)
    )) else '0';


    is_zbs_r_instr <= '1' when (ENABLE_BITMANIP and op = R_OPCODE and (
        -- BCLR, BEXT (same funct7, different funct3)
        (funct7 = BCLR_FN7 and (funct3 = "001" or funct3 = "101")) or
        -- BINV
        (funct7 = BINV_FN7 and funct3 = "001") or
        -- BSET
        (funct7 = BSET_FN7 and funct3 = "001")
    )) else '0';

    is_zbs_i_instr <= '1' when (ENABLE_BITMANIP and op = I_ARITH_OPCODE and (
        -- BCLRI, BEXTI (same funct7, different funct3)
        (funct3 = "001" and funct7 = BCLRI_FN7) or
        (funct3 = "101" and funct7 = BEXTI_FN7) or
        -- BINVI
        (funct3 = "001" and funct7 = BINVI_FN7 and funct7(6) = '0') or
        -- BSETI
        (funct3 = "001" and funct7 = BSETI_FN7 and funct7(6) = '0')
    )) else '0';

    -- Zbc / Zbkc carry-less multiply. Zbkc (clmul/clmulh) OR-gates onto the
    -- existing Zbc decode row (decode condition = BITMANIP or ZBKC); clmulr is
    -- Zbc-only (not part of Zbkc). No new alu_control codes -- the CLMUL/CLMULH/
    -- CLMULR rows are shared, and the ALU arms OR-gate ZBKC to match.
    is_zbc_instr <= '1' when (op = R_OPCODE and funct7 = CLMUL_FN7 and (
                            ((ENABLE_BITMANIP or ENABLE_ZBKC) and (funct3 = CLMUL_FN3 or funct3 = CLMULH_FN3)) or
                            (ENABLE_BITMANIP and funct3 = CLMULR_FN3))) else '0';

    -- ==========================================
    -- X3 Zbkb / Zbkx (scalar crypto bit-manip) decode helpers
    -- ==========================================
    -- New Zbkb R-type ops: pack (funct3=100) / packh (funct3=111), funct7=0000100.
    -- pack shares funct7/funct3 with Zbb ZEXT.H (rs2=x0 case) -- pack is the superset.
    is_zbkb_new_r_instr <= '1' when (ENABLE_ZBKB and op = R_OPCODE and funct7 = PACK_FN7 and
                                     (funct3 = PACK_FN3 or funct3 = PACKH_FN3)) else '0';
    -- New Zbkb OP-IMM ops: brev8 / zip / unzip (distinguished by funct3 + imm12).
    is_zbkb_new_i_instr <= '1' when (ENABLE_ZBKB and op = I_ARITH_OPCODE and (
        (funct3 = "101" and imm12 = BREV8_IMM12) or   -- brev8
        (funct3 = "001" and imm12 = ZIP_IMM12)   or   -- zip
        (funct3 = "101" and imm12 = UNZIP_IMM12)      -- unzip
    )) else '0';
    -- Zbkb shares a subset with Zbb (andn orn xnor rol ror rori rev8). ENABLE_ZBKB
    -- makes ONLY that subset legal when Zbb (ENABLE_BITMANIP) is off; with Zbb on
    -- it is already legal via is_zbb_*. Non-shared Zbb ops (min/max/clz/cpop/sext/
    -- orc.b/zext.h) are NOT in Zbkb, so these helpers match only the shared subset
    -- and add no new alu_control codes (they reuse the existing rows).
    is_zbkb_shared_r_instr <= '1' when (ENABLE_ZBKB and op = R_OPCODE and (
        (funct7 = ANDN_FN7 and (funct3 = "111" or funct3 = "110" or funct3 = "100")) or  -- ANDN/ORN/XNOR
        (funct7 = ROL_FN7 and (funct3 = "001" or funct3 = "101"))                         -- ROL/ROR
    )) else '0';
    is_zbkb_shared_i_instr <= '1' when (ENABLE_ZBKB and op = I_ARITH_OPCODE and (
        (funct3 = "101" and funct7 = RORI_FN7) or      -- RORI (funct3=101, funct7=0110000)
        (funct3 = "101" and imm12 = REV8_IMM12)        -- REV8  (funct3=101, imm12=0x698; SRL_FN3 group)
    )) else '0';
    -- Zbkx crossbar permute: xperm8 (funct3=100) / xperm4 (funct3=010), funct7=0010100.
    is_zbkx_instr <= '1' when (ENABLE_ZBKX and op = R_OPCODE and funct7 = XPERM_FN7 and
                               (funct3 = XPERM8_FN3 or funct3 = XPERM4_FN3)) else '0';

    -- RV32 Zicond: czero.eqz (funct3=101) / czero.nez (funct3=111), OP funct7=0000111
    is_zicond_instr <= '1' when (ENABLE_ZICOND and op = R_OPCODE and funct7 = ZICOND_FN7 and
                            (funct3 = CZERO_EQZ_FN3 or funct3 = CZERO_NEZ_FN3)) else '0';

    -- X3 Zknd/Zkne AES-32: OP opcode, funct3=000, funct5 (= funct7(4 downto 0)) one
    -- of the four aes32* codes. bs (= funct7(6 downto 5) = instr[31:30]) is a
    -- don't-care in decode -- all four byte-select values are legal encodings, so
    -- the decode gate deliberately ignores funct7(6 downto 5). Gated on ENABLE_ZKN,
    -- so an OFF build reduces this to a constant '0' and the encoding traps illegal.
    is_aes_instr <= '1' when (ENABLE_ZKN and op = R_OPCODE and funct3 = AES_FN3 and
                            (funct7(4 downto 0) = AES32ESI_FN5  or funct7(4 downto 0) = AES32ESMI_FN5 or
                             funct7(4 downto 0) = AES32DSI_FN5  or funct7(4 downto 0) = AES32DSMI_FN5)) else '0';

    is_csr_instr <= '1' when (op = SYSTEM_OPCODE and
                              (funct3 = CSRRW_FN3 or funct3 = CSRRS_FN3 or funct3 = CSRRC_FN3 or
                               funct3 = CSRRWI_FN3 or funct3 = CSRRSI_FN3 or funct3 = CSRRCI_FN3)) else '0';

    -- X3 Zknh SHA-256 (unary): OP-IMM, funct3=001, bits[31:25]=0001000, rs2-field
    -- (imm12[4:0]) in {00000..00011}. Any other rs2-field with this funct7 is a
    -- RESERVED encoding and traps. Gated on ENABLE_ZKN.
    is_sha256_instr <= '1' when (ENABLE_ZKN and op = I_ARITH_OPCODE and funct3 = SHA256_FN3 and
                                 funct7 = SHA256_FN7 and
                                 (imm12 = SHA256SUM0_IMM12 or imm12 = SHA256SUM1_IMM12 or
                                  imm12 = SHA256SIG0_IMM12 or imm12 = SHA256SIG1_IMM12)) else '0';

    -- X3 Zknh SHA-512 (binary, RV32 halves): OP opcode, funct3=000, funct7 one of
    -- the six sha512* codes (bits[31:30]=01). Gated on ENABLE_ZKN.
    is_sha512_instr <= '1' when (ENABLE_ZKN and op = R_OPCODE and funct3 = SHA512_FN3 and
                                 (funct7 = SHA512SUM0R_FN7 or funct7 = SHA512SUM1R_FN7 or
                                  funct7 = SHA512SIG0L_FN7 or funct7 = SHA512SIG1L_FN7 or
                                  funct7 = SHA512SIG0H_FN7 or funct7 = SHA512SIG1H_FN7)) else '0';

    -- CSR-address validity map (Deliverable A, ships regardless of any generic).
    -- KNOWN = every CSR the csr_unit implements + the full hpm ranges (legal
    -- read-zero/write-ignore) + mcountinhibit/mcounteren. Everything else is an
    -- unknown CSR -> illegal instruction. hpm ranges use unsigned compares.
    csr_addr_valid <= '1' when (
        imm12 = CSR_MHARTID   or imm12 = CSR_MISA      or
        imm12 = CSR_MCYCLE    or imm12 = CSR_MINSTRET  or
        imm12 = CSR_MCYCLEH   or imm12 = CSR_MINSTRETH or
        imm12 = CSR_CYCLE     or imm12 = CSR_TIME      or imm12 = CSR_INSTRET or
        imm12 = CSR_CYCLEH    or imm12 = CSR_TIMEH     or imm12 = CSR_INSTRETH or
        imm12 = CSR_MCOUNTINHIBIT or imm12 = CSR_MCOUNTEREN or
        -- X3 Zcmt jvt: a KNOWN CSR only when ENABLE_ZCMT (else read/write to 0x017
        -- is an unknown CSR -> illegal instruction, the both-polarity gate).
        (ENABLE_ZCMT and imm12 = CSR_JVT) or
        (unsigned(imm12) >= unsigned(CSR_MHPMCOUNTER3)  and unsigned(imm12) <= x"B1F") or -- mhpmcounter3-31
        (unsigned(imm12) >= unsigned(CSR_MHPMCOUNTER3H) and unsigned(imm12) <= x"B9F") or -- mhpmcounter3h-31h
        (unsigned(imm12) >= unsigned(CSR_MHPMEVENT3)    and unsigned(imm12) <= x"33F") or -- mhpmevent3-31
        (unsigned(imm12) >= unsigned(CSR_HPMCOUNTER3)   and unsigned(imm12) <= x"C1F") or -- hpmcounter3-31 (user)
        (unsigned(imm12) >= unsigned(CSR_HPMCOUNTER3H)  and unsigned(imm12) <= x"C9F")    -- hpmcounter3h-31h (user)
    ) else '0';

    -- ==========================================
    -- Zimop may-be-operations (X1): mop.r.N / mop.rr.N
    -- ==========================================
    -- SYSTEM opcode, funct3=100 (MOP_FN3) -- a decode hole today, so gated purely
    -- on ENABLE_ZIMOP. Fixed bits per the ratified/riscv-opcodes encoding:
    --   funct7(6)=instr31=1, funct7(4:3)=instr29..28="00".
    --   mop.r.N  : funct7(0)=instr25=0 AND imm12(4:2)=instr24..22="111" (bits25..22=0111);
    --              index bits {30,27,26,21,20} are don't-care (all 32 variants admitted).
    --   mop.rr.N : funct7(0)=instr25=1; bits24..20=rs2, index bits {30,27,26} don't-care.
    -- Semantics: rd <- 0 (a real x0-safe zero write). No memory, no CSR, no trap
    -- when enabled. Disabled -> is_zimop_instr='0' -> illegal-instruction (hole).
    is_zimop_instr <= '1' when (ENABLE_ZIMOP and op = SYSTEM_OPCODE and funct3 = MOP_FN3 and
                                funct7(6) = '1' and funct7(4 downto 3) = "00" and
                                ( (funct7(0) = '0' and imm12(4 downto 2) = "111") or  -- mop.r.N
                                  (funct7(0) = '1') )) else '0';                        -- mop.rr.N

    -- ==========================================
    -- RV32ZISCR CSR Control Signals
    -- ==========================================
    csr_op <= funct3 when is_csr_instr = '1' else "000";
    csr_valid <= is_csr_instr;

    -- ==========================================
    -- RV32A Atomic Operation Signals
    -- ==========================================
    -- Load-Reserved operation
    lr_op <= '1' when (ENABLE_ATOMICS and op = AMO_OPCODE and funct3 = AMO_WIDTH_W and funct5 = LR_FN5) else '0';

    -- Store-Conditional operation
    sc_op <= '1' when (ENABLE_ATOMICS and op = AMO_OPCODE and funct3 = AMO_WIDTH_W and funct5 = SC_FN5) else '0';

    -- Atomic Memory Operation (excluding LR/SC). X2 Zabha: byte (funct3=000)
    -- and halfword (funct3=001) AMOs join the word path when ENABLE_ZABHA;
    -- LR/SC stay word-only (Zabha excludes lr.b/h and sc.b/h).
    amo_op <= '1' when (ENABLE_ATOMICS and op = AMO_OPCODE and
                        funct5 /= LR_FN5 and funct5 /= SC_FN5 and
                        (funct3 = AMO_WIDTH_W or
                         (ENABLE_ZABHA and (funct3 = AMO_WIDTH_B or funct3 = AMO_WIDTH_H)))) else '0';

    fence_op <= is_fence;

    -- X1 Zihintpause detect (helper-signal pattern). PAUSE = `fence w,0`
    -- (imm12 = 0x010, funct3 = 000). Gated by ENABLE_ZIHINT so an OFF build
    -- leaves pause_hint statically '0' and the FENCE nop path unchanged. This
    -- NEVER touches valid_opcode/valid_funct: PAUSE is a legal FENCE encoding
    -- in both polarities (the generic gates only the arbiter-yield side-effect).
    is_pause <= '1' when (ENABLE_ZIHINT and is_fence = '1' and imm12 = PAUSE_IMM12) else '0';
    pause_hint <= is_pause;

    -- X3 Zicboz decode: the exact cbo.zero encoding (MISC-MEM opcode, funct3=010,
    -- imm12=0x004). Gated on ENABLE_ZICBOZ so an OFF build leaves cboz_op
    -- statically '0' AND cbo.zero traps illegal (the FENCE valid_funct arm below
    -- only legalizes it under the same generic). rd-field(00000)/rs1 are not
    -- decoded here (maindec has no rd/rs1 ports; the imm12 uniquely identifies
    -- cbo.zero, as WFI/PAUSE are). cbo.clean/flush/inval share this funct3 but
    -- carry imm12 0x001/0x002/0x000 -> never match -> stay illegal (both polarities).
    is_cboz <= '1' when (ENABLE_ZICBOZ and op = FENCE_OPCODE and funct3 = CBO_FN3
                         and imm12 = CBOZ_IMM12) else '0';
    cboz_op <= is_cboz;

    -- X3 Zcmp/Zcmt: recognise the cm.* sentinel. c_dec emits op = ZCM_SENTINEL_OP
    -- ONLY for a legal, enabled cm.* (validity, rlist>=4, r1s'/=r2s' all checked
    -- there), so maindec trusts the sentinel and just gates on the generics. The
    -- sentinel opcode's bits(1:0)="10" can never be produced by a real
    -- decompressed instruction or a raw 32-bit word, so this cannot fire on
    -- anything c_dec did not synthesise. zcm_op launches the FSM sequencer; the
    -- sub-op and operands are decoded from the instruction word inside vesta.
    is_zcm <= '1' when ((ENABLE_ZCMP or ENABLE_ZCMT) and op = ZCM_SENTINEL_OP) else '0';
    zcm_op <= is_zcm;

    -- ==========================================
    -- Valid Instruction Detection
    -- ==========================================
    -- Check for valid RV32IMAC+Zba+Zbb opcodes
    valid_opcode <= '1' when (
        op = I_LOAD_OPCODE   or  -- Load instructions
        op = S_OPCODE        or  -- Store instructions
        op = R_OPCODE        or  -- R-type instructions (including Zba/Zbb)
        op = B_OPCODE        or  -- Branch instructions
        op = I_ARITH_OPCODE  or  -- I-type arithmetic (including Zbb)
        op = J_OPCODE        or  -- Jump
        op = U_AUIPC_OPCODE  or  -- AUIPC
        op = U_LUI_OPCODE    or  -- LUI
        op = I_JALR_OPCODE   or  -- JALR
        (ENABLE_ATOMICS and op = AMO_OPCODE) or  -- RV32A Atomic operations
        op = CUSTOM_OPCODE   or  -- Custom Vesta instructions
        op = FENCE_OPCODE    or  -- FENCE instruction
        op = SYSTEM_OPCODE   or  -- SYSTEM instruction
        ((ENABLE_ZCMP or ENABLE_ZCMT) and op = ZCM_SENTINEL_OP)  -- X3 Zcmp/Zcmt cm.* sentinel
    ) else '0';

    process(op, funct3, funct7, funct5, imm12, valid_opcode, is_custom_instr, is_mul_div, is_amo_instr, is_zba_instr, is_zbb_r_instr, is_zbb_i_instr, is_zbs_r_instr, is_zbs_i_instr, is_zbc_instr, is_zicond_instr, is_aes_instr, is_wrs_instr, is_csr_instr, is_zimop_instr, csr_addr_valid, is_std_amo_fn5, is_sha256_instr, is_sha512_instr, is_zbkb_new_r_instr, is_zbkb_new_i_instr, is_zbkb_shared_r_instr, is_zbkb_shared_i_instr, is_zbkx_instr)
    begin
        valid_funct <= '1';
        
        if valid_opcode = '1' then
            case op is
                when R_OPCODE =>
                    if funct7 = MULT_FN7 then
                        -- MUL* legal only with ENABLE_MUL, DIV*/REM* only with
                        -- ENABLE_DIV; anything else on MULT_FN7 traps.
                        if not ((ENABLE_MUL and (funct3 = MUL_FN3 or funct3 = MULH_FN3 or
                                                 funct3 = MULHSU_FN3 or funct3 = MULHU_FN3)) or
                                (ENABLE_DIV and (funct3 = DIV_FN3 or funct3 = DIVU_FN3 or
                                                 funct3 = REM_FN3 or funct3 = REMU_FN3))) then
                            valid_funct <= '0';
                        end if;
                    elsif is_zba_instr = '1' then
                        valid_funct <= '1';
                    elsif is_zbb_r_instr = '1' then
                        valid_funct <= '1';
                    elsif is_zbs_r_instr = '1' then
                        valid_funct <= '1';
                    elsif is_zbc_instr = '1' then
                        valid_funct <= '1';  -- Zbc instructions are valid
                    elsif is_zicond_instr = '1' then
                        valid_funct <= '1';  -- Zicond czero.eqz/czero.nez are valid
                    elsif is_aes_instr = '1' then
                        valid_funct <= '1';  -- X3 Zknd/Zkne aes32{e,d}s[m]i are valid
                    elsif is_sha512_instr = '1' then
                        valid_funct <= '1';  -- X3 Zknh sha512* (enabled) are valid
                    elsif is_zbkb_new_r_instr = '1' then
                        valid_funct <= '1';  -- X3 Zbkb pack/packh
                    elsif is_zbkb_shared_r_instr = '1' then
                        valid_funct <= '1';  -- X3 Zbkb andn/orn/xnor/rol/ror (Zbb off)
                    elsif is_zbkx_instr = '1' then
                        valid_funct <= '1';  -- X3 Zbkx xperm8/xperm4
                    elsif funct7 = "0000000" or funct7 = "0100000" then
                        -- Standard R-type instructions
                        if funct3 = SRL_FN3 then
                            if not (funct7(5) = '0' or funct7(5) = '1') then
                                valid_funct <= '0';
                            end if;
                        elsif funct3 = ADD_FN3 then
                            if not (funct7 = "0000000" or funct7 = "0100000") then
                                valid_funct <= '0';
                            end if;
                        elsif not (funct3 = SLL_FN3 or funct3 = SLT_FN3 or 
                                  funct3 = SLTU_FN3 or funct3 = XOR_FN3 or 
                                  funct3 = OR_FN3 or funct3 = AND_FN3) then
                            valid_funct <= '0';
                        end if;
                    else
                        valid_funct <= '0';
                    end if;

                when I_ARITH_OPCODE =>
                    if is_zbb_i_instr = '1' then
                        valid_funct <= '1';
                    elsif is_zbs_i_instr = '1' then
                        valid_funct <= '1';
                    elsif is_zbkb_new_i_instr = '1' then
                        valid_funct <= '1';  -- X3 Zbkb brev8/zip/unzip
                    elsif is_zbkb_shared_i_instr = '1' then
                        valid_funct <= '1';  -- X3 Zbkb rori/rev8 (Zbb off)
                    elsif funct3 = SRL_FN3 then
                        if ENABLE_BITMANIP and funct7 = RORI_FN7 then
                            valid_funct <= '1';
                        elsif (not ENABLE_BITMANIP) and not (funct7 = "0000000" or funct7 = "0100000") then
                            -- Without Zb*, only exact SRLI/SRAI encodings are
                            -- legal (RORI etc. must trap, not alias to SRAI).
                            valid_funct <= '0';
                        elsif not (funct7(6 downto 5) = "00" or funct7(6 downto 5) = "01") then
                            valid_funct <= '0';
                        end if;
                    elsif funct3 = SLL_FN3 then
                        if is_sha256_instr = '1' then
                            valid_funct <= '1';  -- X3 Zknh sha256sig0/sig1/sum0/sum1 (enabled)
                        elsif funct7 = SHA256_FN7 then
                            -- SHA-256 funct7 hole (bits[31:25]=0001000): legal ONLY
                            -- as an enabled sha256* op above. Otherwise (ENABLE_ZKN
                            -- off, or a reserved rs2-field) it is illegal -- do NOT
                            -- let the loose funct7(6:5)="00" check below alias it to
                            -- a valid shift.
                            valid_funct <= '0';
                        elsif (not ENABLE_BITMANIP) and funct7 /= "0000000" then
                            -- Without Zb*, only the exact SLLI encoding is legal
                            -- (BSETI/BINVI/CLZ-class encodings must trap).
                            valid_funct <= '0';
                        elsif funct7(6 downto 5) /= "00" and is_zbb_i_instr = '0' and is_zbs_i_instr = '0' then
                            valid_funct <= '0';
                        end if;
                    end if;
                -- S-type store instructions
                when S_OPCODE =>
                    if not (funct3 = "000" or  -- SB
                           funct3 = "001" or  -- SH
                           funct3 = "010") then  -- SW
                        valid_funct <= '0';
                    end if;
                
                -- Branch instructions
                when B_OPCODE =>
                    if not (funct3 = "000" or  -- BEQ
                           funct3 = "001" or  -- BNE
                           funct3 = "100" or  -- BLT
                           funct3 = "101" or  -- BGE
                           funct3 = "110" or  -- BLTU
                           funct3 = "111") then  -- BGEU
                        valid_funct <= '0';
                    end if;
                
                -- JALR - only funct3 = 000 is valid
                when I_JALR_OPCODE =>
                    if funct3 /= "000" then
                        valid_funct <= '0';
                    end if;
                
                -- Custom instructions
                when CUSTOM_OPCODE =>
                    if not ((funct3 = IRET_FN3 and funct7 = IRET_FN7) or
                           (funct3 = SLP_FN3 and funct7 = SLEEP_FN7) or
                           (funct3 = SLP_FN3 and funct7 = WAKE_FN7) or
                           (funct3 = "000" and funct7 = "0000000")) then
                        valid_funct <= '0';
                    end if;
                -- FENCE / MISC-MEM instructions
                when FENCE_OPCODE =>
                    if funct3 = FENCE_FN3 or funct3 = FENCE_I_FN3 then
                        valid_funct <= '1';  -- FENCE / FENCE.I
                    elsif ENABLE_ZICBOZ and funct3 = CBO_FN3 and imm12 = CBOZ_IMM12 then
                        -- X3 Zicboz: cbo.zero legal ONLY when the generic is on.
                        valid_funct <= '1';
                    else
                        -- Everything else on MISC-MEM traps, INCLUDING the
                        -- cbo.clean/flush/inval siblings (D4: always illegal) and
                        -- cbo.zero itself when ENABLE_ZICBOZ is off.
                        valid_funct <= '0';
                    end if;
                -- SYSTEM instructions (CSR, ECALL, EBREAK)
                when SYSTEM_OPCODE =>
                    if is_csr_instr = '1' then
                        -- CSR instruction legal ONLY for a known CSR address;
                        -- unknown addresses trap (Deliverable A base repair).
                        valid_funct <= csr_addr_valid;
                    elsif is_zimop_instr = '1' then
                        valid_funct <= '1';  -- Zimop mop.r.N / mop.rr.N (rd<-0)
                        valid_funct <= '1';  -- All CSR instructions are valid
                    elsif is_wrs_instr = '1' then
                        valid_funct <= '1';  -- X1 Zawrs wrs.nto/wrs.sto (legal when enabled)
                    -- elsif funct3 = PRIV_FN3 then
                    --     -- ECALL/EBREAK/MRET instructions
                    --     if imm12 = x"000" or imm12 = x"001" or imm12 = x"302" then
                    --         valid_funct <= '1';  -- ECALL, EBREAK, MRET
                    --     else
                    --         valid_funct <= '0';
                    --     end if;
                    else
                        valid_funct <= '0';
                    end if;

                -- RV32A / X2 Zabha / X2 Zacas atomic operations. Decode legality
                -- is a funct5 WHITELIST per width:
                --   Word (funct3=010): the nine standard AMOs + LR + SC always,
                --     + CAS (amocas.w) only when ENABLE_ZACAS. Every other funct5
                --     is RESERVED and traps. (X2 Zabha tightened the sub-word hole;
                --     X2 Zacas tightens this word hole too -- pre-X2 the word arm
                --     admitted ALL funct5, so amocas.w did NOT trap with ZACAS off.
                --     No existing test exercises the reserved word funct5 codes.)
                --   Byte/half (000/001): legal ONLY with ENABLE_ZABHA, and only
                --     the nine standard AMOs + CAS (amocas.b/.h, requires ZACAS
                --     AND ZABHA). lr.b/h and sc.b/h stay illegal (Zabha excludes
                --     them); reserved sub-word funct5 traps.
                --   Any other width (011 incl. amocas.d, and 1xx) always traps.
                when AMO_OPCODE =>
                    if funct3 = AMO_WIDTH_W then
                        if is_std_amo_fn5 = '1' or funct5 = LR_FN5 or funct5 = SC_FN5 then
                            valid_funct <= '1';
                        elsif ENABLE_ZACAS and funct5 = CAS_FN5 then
                            valid_funct <= '1';
                        else
                            valid_funct <= '0';
                        end if;
                    elsif ENABLE_ZABHA and (funct3 = AMO_WIDTH_B or funct3 = AMO_WIDTH_H) then
                        if is_std_amo_fn5 = '1' then
                            valid_funct <= '1';
                        elsif ENABLE_ZACAS and funct5 = CAS_FN5 then
                            valid_funct <= '1';
                        else
                            valid_funct <= '0';
                        end if;
                    else
                        valid_funct <= '0';
                    end if;

                -- X3 Zcmp/Zcmt: the cm.* sentinel is already fully validated by
                -- c_dec (only a legal, enabled cm.* reaches this opcode), so it is
                -- unconditionally legal here. valid_opcode gates it on the generics,
                -- so an OFF build never reaches this arm (traps as an unknown op).
                when ZCM_SENTINEL_OP =>
                    valid_funct <= '1';

                -- J, LUI, AUIPC don't use funct3/funct7
                when others =>
                    -- TODO
                    valid_funct <= '1';
            end case;
        else
            valid_funct <= '0';
        end if;
    end process;

    -- ==========================================
    -- Trap Signal Generation
    -- ==========================================
    -- Trap on invalid opcode or invalid function field combination
    trap <= not (valid_opcode and valid_funct);

    -- ==========================================
    -- Custom Vesta Instructions
    -- ==========================================
    isr_ret  <= '1' when (op = CUSTOM_OPCODE and funct3 = IRET_FN3 and funct7 = IRET_FN7) else '0';
    sleep_rq <= '1' when (op = CUSTOM_OPCODE and funct3 = SLP_FN3 and funct7 = SLEEP_FN7) else '0';
    wake_rq  <= '1' when (op = CUSTOM_OPCODE and funct3 = SLP_FN3 and funct7 = WAKE_FN7) else '0';

    -- X1 Zawrs decode outputs (both '0' unless the extension is enabled).
    wrs_op  <= is_wrs_instr;
    wrs_sto <= '1' when (is_wrs_instr = '1' and imm12 = WRS_STO_IMM12) else '0';

    -- ==========================================
    -- Register Write Enable
    -- ==========================================
    reg_write <= '1' when op = I_LOAD_OPCODE   else  -- Load instructions
                 '1' when op = R_OPCODE         else  -- R-type instructions (including Zba/Zbb)
                 '1' when op = I_ARITH_OPCODE   else  -- I-type arithmetic (including Zbb)
                 '1' when op = J_OPCODE         else  -- JAL
                 '1' when op = U_AUIPC_OPCODE   else  -- AUIPC
                 '1' when op = U_LUI_OPCODE     else  -- LUI
                 '1' when op = I_JALR_OPCODE    else  -- JALR
                 '1' when (ENABLE_ATOMICS and op = AMO_OPCODE and funct5 /= SC_FN5) else -- All AMO except SC (SC writes conditionally)
                 '1' when (ENABLE_ATOMICS and op = AMO_OPCODE and funct5 = SC_FN5)  else -- SC also writes (success/fail flag)
                 '1' when is_zimop_instr = '1'  else  -- Zimop mop.r/mop.rr write rd<-0
                 '1' when is_csr_instr = '1'    else
                 '0' when (op = FENCE_OPCODE)        else  -- FENCE instruction
                 '0';  -- No write for stores, branches, custom instructions

    -- ==========================================
    -- Immediate Source Selection
    -- ==========================================
    -- 000: I-type, 001: S-type, 010: B-type, 011: J-type, 100: U-type
    -- Note: AMO instructions use R-type format (no immediate)
    imm_src <= "000" when op = I_LOAD_OPCODE   else  -- I-type
               "001" when op = S_OPCODE         else  -- S-type
               "010" when op = B_OPCODE         else  -- B-type
               "000" when op = I_ARITH_OPCODE   else  -- I-type
               "011" when op = J_OPCODE         else  -- J-type
               "100" when op = U_AUIPC_OPCODE   else  -- U-type
               "100" when op = U_LUI_OPCODE     else  -- U-type
               "000" when op = I_JALR_OPCODE    else  -- I-type
               "000" when op = AMO_OPCODE       else  -- No immediate for AMO
               "000";

    -- ==========================================
    -- ALU Source Selection
    -- ==========================================
    -- 0: Register, 1: Immediate
    -- Zba/Zbb R-type instructions use register operands
    -- Zbb I-type pseudo-instructions actually use rs1 only
    ALU_src <= '1' when op = I_LOAD_OPCODE   else  -- Use immediate
               '1' when op = S_OPCODE         else  -- Use immediate
               '0' when op = R_OPCODE         else  -- Use register (includes Zba/Zbb)
               '0' when op = B_OPCODE         else  -- Use register
               '1' when op = I_ARITH_OPCODE   else  -- Use immediate (most Zbb pseudo-ops ignore rs2/imm)
               '0' when op = J_OPCODE         else  -- Not used
               '-' when op = U_AUIPC_OPCODE   else  -- Don't care
               '1' when op = U_LUI_OPCODE     else  -- Use immediate
               '-' when op = I_JALR_OPCODE    else  -- Don't care
               '0' when op = AMO_OPCODE       else  -- Use register (rs1 for address)
               '1' when (is_csr_instr = '1' and funct3(2) = '1') else  -- CSR immediate
               '0' when (is_csr_instr = '1' and funct3(2) = '0') else -- CSR register
               '0';

    -- ==========================================
    -- Write Enable for Memory Operations
    -- ==========================================
    -- Generate byte enable signals based on store type and address offset
    -- Note: SC and AMO operations always work on words
    WEN <= -- Store Byte (SB)
           "1110" when (op = S_OPCODE and funct3 = "000" and mask = "00") else
           "1101" when (op = S_OPCODE and funct3 = "000" and mask = "01") else
           "1011" when (op = S_OPCODE and funct3 = "000" and mask = "10") else
           "0111" when (op = S_OPCODE and funct3 = "000" and mask = "11") else
           -- Store Halfword (SH)
           "1100" when (op = S_OPCODE and funct3 = "001" and mask(1) = '0') else
           "0011" when (op = S_OPCODE and funct3 = "001" and mask(1) = '1') else
           -- Store Word (SW)
           "0000" when (op = S_OPCODE and funct3 = "010") else
           -- Store-Conditional and AMO operations (word access)
           "0000" when (op = AMO_OPCODE and (sc_op = '1' or amo_op = '1')) else
           -- No write for all other instructions (including LR)
           "1111";

    -- ==========================================
    -- Result Source Selection
    -- ==========================================
    -- 00: ALU result, 01: Memory data, 10: PC+4, 11: PC+immediate
    result_src <= "001" when op = I_LOAD_OPCODE   else  -- Memory data
                  "000" when op = S_OPCODE         else  -- ALU result
                  "000" when op = R_OPCODE         else  -- ALU result (includes Zba/Zbb)
                  "000" when op = B_OPCODE         else  -- ALU result
                  "000" when op = I_ARITH_OPCODE   else  -- ALU result (includes Zbb)
                  "010" when op = J_OPCODE         else  -- PC+4
                  "011" when op = U_AUIPC_OPCODE   else  -- PC+immediate
                  "000" when op = U_LUI_OPCODE     else  -- ALU result
                  "010" when op = I_JALR_OPCODE    else  -- PC+4
                  "001" when (op = AMO_OPCODE and lr_op = '1') else  -- Memory data for LR
                  "000" when (op = AMO_OPCODE and sc_op = '1') else  -- Success/fail for SC
                  "001" when (op = AMO_OPCODE and amo_op = '1') else -- Memory data for AMO
                  "101" when is_zimop_instr = '1'  else  -- Zimop: unused mux code -> Result forced 0 (rd<-0)
                  "100" when is_csr_instr = '1'    else  -- CSR read value
                  "001";

    -- ==========================================
    -- Branch Control
    -- ==========================================
    branch <= '1' when op = B_OPCODE else '0';

    -- ==========================================
    -- Jump Control
    -- ==========================================
    jump <= '1' when op = J_OPCODE      else
            '1' when op = I_JALR_OPCODE else
            '0';

    -- ==========================================
    -- JALR Control
    -- ==========================================
    jalr <= '1' when op = I_JALR_OPCODE else '0';

    -- ==========================================
    -- Memory Access Flags
    -- ==========================================
    read_data_flag <= '1' when op = I_LOAD_OPCODE else
                      '1' when (op = CUSTOM_OPCODE and funct3 = "000" and funct7 = "0000000") else
                      '1' when (ENABLE_ATOMICS and op = AMO_OPCODE) else  -- All AMO operations read memory
                      '0';

    write_data_flag <= '1' when op = S_OPCODE else 
                       '1' when (op = AMO_OPCODE and (sc_op = '1' or amo_op = '1')) else  -- SC and AMO write
                       '0';

    mem_access_instr <= read_data_flag or write_data_flag;

    -- ==========================================
    -- Division Operation Flag
    -- ==========================================
    div_op <= '1' when (ENABLE_DIV and op = R_OPCODE and funct7 = MULT_FN7 and
                       (funct3 = DIV_FN3 or funct3 = DIVU_FN3 or
                        funct3 = REM_FN3 or funct3 = REMU_FN3)) else '0';

    -- ==========================================
    -- ALU Control Signal Generation (7-bit)
    -- ==========================================
    -- Clean 7-bit encoding with no conflicts
    alu_control <= 
        -- Load and Store operations (ADD for address calculation)
        "0000000" when op = I_LOAD_OPCODE else
        "0000000" when op = S_OPCODE else
        
        -- Custom instructions
        "0000000" when op = CUSTOM_OPCODE else
        
        -- RV32 Zba instructions (shift-and-add)
        "0011000" when (op = R_OPCODE and funct7 = ZBA_FN7 and funct3 = SH1ADD_FN3) else  -- SH1ADD
        "0011001" when (op = R_OPCODE and funct7 = ZBA_FN7 and funct3 = SH2ADD_FN3) else  -- SH2ADD
        "0011010" when (op = R_OPCODE and funct7 = ZBA_FN7 and funct3 = SH3ADD_FN3) else  -- SH3ADD

        -- X3 Zbkb crypto bit-manip (pack/packh R-type; brev8/zip/unzip OP-IMM).
        -- Every row is ENABLE_ZBKB-gated so an OFF build is bit-identical (the rows
        -- vanish under constant propagation). PACK precedes the ZEXT.H row below so
        -- the shared funct7/funct3 decodes to PACK when Zbkb is on (pack rs2=x0 ==
        -- zext.h); with Zbkb off it falls through to ZEXT.H unchanged.
        "0110101" when (op = R_OPCODE and funct7 = PACK_FN7 and funct3 = PACK_FN3 and ENABLE_ZBKB) else   -- PACK
        "0110110" when (op = R_OPCODE and funct7 = PACK_FN7 and funct3 = PACKH_FN3 and ENABLE_ZBKB) else  -- PACKH
        "0110111" when (op = I_ARITH_OPCODE and funct3 = "101" and imm12 = BREV8_IMM12 and ENABLE_ZBKB) else -- BREV8
        "0111000" when (op = I_ARITH_OPCODE and funct3 = "001" and imm12 = ZIP_IMM12   and ENABLE_ZBKB) else -- ZIP
        "0111001" when (op = I_ARITH_OPCODE and funct3 = "101" and imm12 = UNZIP_IMM12 and ENABLE_ZBKB) else -- UNZIP
        -- X3 Zbkx crossbar permute (ENABLE_ZBKX-gated)
        "0111010" when (op = R_OPCODE and funct7 = XPERM_FN7 and funct3 = XPERM8_FN3 and ENABLE_ZBKX) else -- XPERM8
        "0111011" when (op = R_OPCODE and funct7 = XPERM_FN7 and funct3 = XPERM4_FN3 and ENABLE_ZBKX) else -- XPERM4

        -- RV32 Zbb R-type instructions
        "0011011" when (op = R_OPCODE and funct7 = ANDN_FN7 and funct3 = "111") else     -- ANDN
        "0011100" when (op = R_OPCODE and funct7 = ORN_FN7 and funct3 = "110") else      -- ORN
        "0011101" when (op = R_OPCODE and funct7 = XNOR_FN7 and funct3 = "100") else     -- XNOR
        "0011110" when (op = R_OPCODE and funct7 = MIN_FN7 and funct3 = "100") else      -- MIN
        "0011111" when (op = R_OPCODE and funct7 = MIN_FN7 and funct3 = "101") else      -- MINU
        "0100000" when (op = R_OPCODE and funct7 = MIN_FN7 and funct3 = "110") else      -- MAX
        "0100001" when (op = R_OPCODE and funct7 = MIN_FN7 and funct3 = "111") else      -- MAXU
        "0100010" when (op = R_OPCODE and funct7 = ROL_FN7 and funct3 = "001") else      -- ROL
        "0100011" when (op = R_OPCODE and funct7 = ROR_FN7 and funct3 = "101") else      -- ROR
        "0101001" when (op = R_OPCODE and funct7 = ZEXT_FN7 and funct3 = "100") else     -- ZEXT.H (R-type encoding)
        
        -- RV32 Zbb I-type instructions
        "0100011" when (op = I_ARITH_OPCODE and funct3 = "101" and funct7 = RORI_FN7) else  -- RORI (reuse ROR)
        "0100100" when (op = I_ARITH_OPCODE and funct3 = "001" and imm12 = CLZ_IMM12) else  -- CLZ
        "0100101" when (op = I_ARITH_OPCODE and funct3 = "001" and imm12 = CTZ_IMM12) else  -- CTZ
        "0100110" when (op = I_ARITH_OPCODE and funct3 = "001" and imm12 = CPOP_IMM12) else -- CPOP
        "0100111" when (op = I_ARITH_OPCODE and funct3 = "001" and imm12 = SEXT_B_IMM12) else -- SEXT.B
        "0101000" when (op = I_ARITH_OPCODE and funct3 = "001" and imm12 = SEXT_H_IMM12) else -- SEXT.H
        "0101001" when (op = I_ARITH_OPCODE and funct3 = "100" and imm12 = ZEXT_H_IMM12) else -- ZEXT.H (I-type)
        "0101010" when (op = I_ARITH_OPCODE and funct3 = "101" and imm12 = ORC_B_IMM12) else  -- ORC.B -- TODO: Edited
        "0101011" when (op = I_ARITH_OPCODE and funct3 = "101" and imm12 = REV8_IMM12) else   -- REV8

        -- RV32 Zknh SHA-256 sigma/sum (X3). is_sha256_instr already pins
        -- ENABLE_ZKN + funct3=001 + funct7=0001000 + the exact rs2-field, so these
        -- take priority over the generic SLLI arm below.
        "1000000" when (is_sha256_instr = '1' and imm12 = SHA256SIG0_IMM12) else  -- sha256sig0
        "1000001" when (is_sha256_instr = '1' and imm12 = SHA256SIG1_IMM12) else  -- sha256sig1
        "1000010" when (is_sha256_instr = '1' and imm12 = SHA256SUM0_IMM12) else  -- sha256sum0
        "1000011" when (is_sha256_instr = '1' and imm12 = SHA256SUM1_IMM12) else  -- sha256sum1

        -- RV32 Zbs R-type instructions (Single-bit operations)
        "0101100" when (op = R_OPCODE and funct7 = BCLR_FN7 and funct3 = "001") else   -- BCLR
        "0101101" when (op = R_OPCODE and funct7 = BEXT_FN7 and funct3 = "101") else   -- BEXT
        "0101110" when (op = R_OPCODE and funct7 = BINV_FN7 and funct3 = "001") else   -- BINV
        "0101111" when (op = R_OPCODE and funct7 = BSET_FN7 and funct3 = "001") else   -- BSET
        
        -- RV32 Zbs I-type instructions (Single-bit immediate operations)
        "0101100" when (op = I_ARITH_OPCODE and funct3 = "001" and funct7 = BCLRI_FN7 and funct7(6) = '0') else  -- BCLRI
        "0101101" when (op = I_ARITH_OPCODE and funct3 = "101" and funct7 = BEXTI_FN7 and funct7(6) = '0') else  -- BEXTI
        "0101110" when (op = I_ARITH_OPCODE and funct3 = "001" and funct7 = BINVI_FN7 and funct7(6) = '0') else  -- BINVI
        "0101111" when (op = I_ARITH_OPCODE and funct3 = "001" and funct7 = BSETI_FN7 and funct7(6) = '0') else  -- BSETI

        -- RV32 Zbc instructions (Carry-less Multiplication)
        "0110000" when (op = R_OPCODE and funct7 = CLMUL_FN7 and funct3 = CLMUL_FN3) else   -- CLMUL
        "0110001" when (op = R_OPCODE and funct7 = CLMULH_FN7 and funct3 = CLMULH_FN3) else -- CLMULH
        "0110010" when (op = R_OPCODE and funct7 = CLMULR_FN7 and funct3 = CLMULR_FN3) else -- CLMULR

        -- RV32 Zicond conditional-zero operations
        "0110011" when (op = R_OPCODE and funct7 = ZICOND_FN7 and funct3 = CZERO_EQZ_FN3) else -- CZERO.EQZ
        "0110100" when (op = R_OPCODE and funct7 = ZICOND_FN7 and funct3 = CZERO_NEZ_FN3) else -- CZERO.NEZ

        -- RV32 Zknd/Zkne AES-32 (X3). funct5 = funct7(4 downto 0); bs = funct7(6:5)
        -- is a SEPARATE ALU input (wired from instr[31:30] in the datapath), NOT
        -- part of alu_control. Gated on ENABLE_ZKN so the OFF build's alu_control
        -- mux is bit-identical to base (these encodings then trap upstream). Placed
        -- BEFORE the generic R-type funct3=000 ADD/SUB path (funct7(5)=bs(1) would
        -- otherwise alias an aes32*i with bs>=2 onto SUB).
        "0111100" when (ENABLE_ZKN and op = R_OPCODE and funct3 = AES_FN3 and funct7(4 downto 0) = AES32ESI_FN5)  else -- aes32esi  (0x3C)
        "0111101" when (ENABLE_ZKN and op = R_OPCODE and funct3 = AES_FN3 and funct7(4 downto 0) = AES32ESMI_FN5) else -- aes32esmi (0x3D)
        "0111110" when (ENABLE_ZKN and op = R_OPCODE and funct3 = AES_FN3 and funct7(4 downto 0) = AES32DSI_FN5)  else -- aes32dsi  (0x3E)
        "0111111" when (ENABLE_ZKN and op = R_OPCODE and funct3 = AES_FN3 and funct7(4 downto 0) = AES32DSMI_FN5) else -- aes32dsmi (0x3F)
        -- RV32 Zknh SHA-512 sigma/sum halves (X3). is_sha512_instr pins ENABLE_ZKN
        -- + funct3=000 + the exact funct7; funct7 uniquely selects the op.
        "1000100" when (is_sha512_instr = '1' and funct7 = SHA512SIG0L_FN7) else  -- sha512sig0l
        "1000101" when (is_sha512_instr = '1' and funct7 = SHA512SIG0H_FN7) else  -- sha512sig0h
        "1000110" when (is_sha512_instr = '1' and funct7 = SHA512SIG1L_FN7) else  -- sha512sig1l
        "1000111" when (is_sha512_instr = '1' and funct7 = SHA512SIG1H_FN7) else  -- sha512sig1h
        "1001000" when (is_sha512_instr = '1' and funct7 = SHA512SUM0R_FN7) else  -- sha512sum0r
        "1001001" when (is_sha512_instr = '1' and funct7 = SHA512SUM1R_FN7) else  -- sha512sum1r


        -- RV32A Atomic operations
        "0000000" when (op = AMO_OPCODE and (lr_op = '1' or sc_op = '1')) else  -- LR/SC use address directly
        "0000000" when (op = AMO_OPCODE and funct5 = AMOADD_FN5)  else  -- AMOADD uses ADD
        "0000100" when (op = AMO_OPCODE and funct5 = AMOXOR_FN5)  else  -- AMOXOR uses XOR
        "0000010" when (op = AMO_OPCODE and funct5 = AMOAND_FN5)  else  -- AMOAND uses AND
        "0000011" when (op = AMO_OPCODE and funct5 = AMOOR_FN5)   else  -- AMOOR uses OR
        "0001010" when (op = AMO_OPCODE and funct5 = AMOSWAP_FN5) else  -- AMOSWAP (pass through B/rs2)
        "0010100" when (op = AMO_OPCODE and funct5 = AMOMIN_FN5)  else  -- AMOMIN (signed MIN)
        "0010101" when (op = AMO_OPCODE and funct5 = AMOMAX_FN5)  else  -- AMOMAX (signed MAX)
        "0010110" when (op = AMO_OPCODE and funct5 = AMOMINU_FN5) else  -- AMOMINU (unsigned MIN)
        "0010111" when (op = AMO_OPCODE and funct5 = AMOMAXU_FN5) else  -- AMOMAXU (unsigned MAX)
        "0001010" when (op = AMO_OPCODE and ENABLE_ZACAS and funct5 = CAS_FN5) else  -- X2 Zacas amocas.w/.b/.h: pass B (rs2 swap value) to the AMO write path
        
        -- R-type M-extension operations
        "0001100" when (is_mul_div = '1' and funct3 = MUL_FN3)    else  -- MUL
        "0001101" when (is_mul_div = '1' and funct3 = MULH_FN3)   else  -- MULH
        "0001111" when (is_mul_div = '1' and funct3 = MULHSU_FN3) else  -- MULHSU
        "0001110" when (is_mul_div = '1' and funct3 = MULHU_FN3)  else  -- MULHU
        "0010000" when (is_mul_div = '1' and funct3 = DIV_FN3)    else  -- DIV
        "0010001" when (is_mul_div = '1' and funct3 = DIVU_FN3)   else  -- DIVU
        "0010010" when (is_mul_div = '1' and funct3 = REM_FN3)    else  -- REM
        "0010011" when (is_mul_div = '1' and funct3 = REMU_FN3)   else  -- REMU
        
        -- R-type standard ALU operations
        "0000000" when (op = R_OPCODE and funct3 = ADD_FN3 and rtype_sub = '0')  else  -- ADD
        "0000001" when (op = R_OPCODE and funct3 = ADD_FN3 and rtype_sub = '1')  else  -- SUB
        "0000110" when (op = R_OPCODE and funct3 = SLL_FN3)                      else  -- SLL
        "0000101" when (op = R_OPCODE and funct3 = SLT_FN3)                      else  -- SLT
        "0001001" when (op = R_OPCODE and funct3 = SLTU_FN3)                     else  -- SLTU
        "0000100" when (op = R_OPCODE and funct3 = XOR_FN3)                      else  -- XOR
        "0001000" when (op = R_OPCODE and funct3 = SRL_FN3 and funct7(5) = '1')  else  -- SRA
        "0000111" when (op = R_OPCODE and funct3 = SRL_FN3 and funct7(5) = '0')  else  -- SRL
        "0000011" when (op = R_OPCODE and funct3 = OR_FN3)                       else  -- OR
        "0000010" when (op = R_OPCODE and funct3 = AND_FN3)                      else  -- AND
        
        -- Branch operations
        "0000001" when (op = B_OPCODE and funct3(2 downto 1) = BEQ_TOP_FN3)    else  -- BEQ/BNE
        "0000101" when (op = B_OPCODE and funct3(2 downto 1) = BCOMP_TOP_FN3)  else  -- BLT/BGE
        "0001001" when (op = B_OPCODE and funct3(2 downto 1) = BCOMPU_TOP_FN3) else  -- BLTU/BGEU
        
        -- I-type arithmetic operations
        "0000000" when (op = I_ARITH_OPCODE and funct3 = ADD_FN3)                      else  -- ADDI
        "0000110" when (op = I_ARITH_OPCODE and funct3 = SLL_FN3)                      else  -- SLLI
        "0000101" when (op = I_ARITH_OPCODE and funct3 = SLT_FN3)                      else  -- SLTI
        "0001001" when (op = I_ARITH_OPCODE and funct3 = SLTU_FN3)                     else  -- SLTIU
        "0000100" when (op = I_ARITH_OPCODE and funct3 = XOR_FN3)                      else  -- XORI
        "0001000" when (op = I_ARITH_OPCODE and funct3 = SRL_FN3 and funct7(5) = '1')  else  -- SRAI
        "0000111" when (op = I_ARITH_OPCODE and funct3 = SRL_FN3 and funct7(5) = '0')  else  -- SRLI
        "0000011" when (op = I_ARITH_OPCODE and funct3 = OR_FN3)                       else  -- ORI
        "0000010" when (op = I_ARITH_OPCODE and funct3 = AND_FN3)                      else  -- ANDI
        
        -- Jump operations
        "0000000" when op = J_OPCODE else  -- JAL
        
        -- AUIPC (ADD PC + immediate)
        "0000000" when op = U_AUIPC_OPCODE else
        
        -- LUI (pass immediate through)
        "0001010" when op = U_LUI_OPCODE else
        
        -- JALR (ADD for address calculation)
        "0000000" when op = I_JALR_OPCODE else
        
        -- Default
        "0000000";

end behave;

