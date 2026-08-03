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
        ENABLE_ZFINX    : boolean := false;  -- X4 (Zfinx): consumed from phase X4 on; scaffolded X0
        -- P0 privileged-architecture scaffolding (default false; decode logic
        -- added by the named phase). These arrive here but are not yet read by
        -- valid_funct / csr_addr_valid -- adding the decode is the phase
        -- agent's job. P1 turns on the SYSTEM PRIV_FN3 arm (MRET 0x302 /
        -- ECALL 0x000 / EBREAK 0x001 / WFI 0x105) and admits the ten new CSR
        -- addresses; P2 adds the U-mode privileged-access gate; P3 adds the
        -- pmpcfg/pmpaddr CSR addresses.
        ENABLE_TRAPCSR  : boolean := false;  -- P1 (trap CSRs + MRET): consumed from phase P1 on; scaffolded P0
        ENABLE_UMODE    : boolean := false;  -- P2 (U-mode): consumed from phase P2 on; scaffolded P0
        ENABLE_PMP      : boolean := false   -- P3 (PMP/Smpmp): consumed from phase P3 on; scaffolded P0
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

        -- P1 standard SYSTEM/PRIV decode (funct3 = PRIV_FN3 = 000). Each is
        -- statically '0' unless ENABLE_TRAPCSR -- with the generic off the three
        -- encodings are NOT in valid_funct either, so they stay illegal
        -- instructions and the OFF build is bit-identical (the P0
        -- privecal/privebrk/privmret poisons pin exactly that). With the generic
        -- ON they are LEGAL decodes in both delivery modes; vesta's FSM routes
        -- them to MTRAP_SV / MTRAP_RET in standard mode and to the terminal
        -- TRAP_STATE in legacy mode (p0_specs.md 1: legacy is bit-identical to
        -- today for everything the legacy suite executes).
        -- rs1/rd are architecturally x0 for all three but are NOT decoded here --
        -- maindec has no rs1/rd ports (the same convention as the X1 Zawrs
        -- wrs.nto/wrs.sto and X3 cbo.zero decodes, which also legalize on
        -- funct12 alone).
        ecall_op         : out STD_LOGIC;
        ebreak_op        : out STD_LOGIC;
        mret_op          : out STD_LOGIC;

        -- P2 standard WFI (SYSTEM PRIV imm12 = 0x105). LEGAL iff ENABLE_TRAPCSR
        -- and (M-mode or mstatus.TW = '0') -- WFI is a TRAPCSR-scope decode, NOT
        -- a U-mode one (p0_specs.md 3.1), so a trapCsr-only build gets it too.
        -- Statically '0' when ENABLE_TRAPCSR is off, where 0x105 stays an illegal
        -- instruction (the privwfi #else poison pins that on the stripped build).
        -- Consumed ONLY by vesta's FSM (enter SLEEPING with the standard wake
        -- rule); never feeds valid_funct/trap.
        wfi_op           : out STD_LOGIC;

        -- ------------------------------------------------------------------
        -- P2 U-mode decode inputs (from csr_unit via controller, the P1
        -- pass-through pattern). FROZEN by p0_specs.md 3.1 -- every one carries
        -- the INERT default, so an instantiation that does not drive them (and
        -- every ENABLE_UMODE=false build) sees M-mode / TW=0 / no counter
        -- enables and the whole U-mode gate below constant-folds away.
        -- ------------------------------------------------------------------
        priv_m           : in  STD_LOGIC := '1';                       -- '1'=M, '0'=U
        status_tw        : in  STD_LOGIC := '0';                       -- mstatus.TW
        mcounteren_bits  : in  STD_LOGIC_VECTOR(4 downto 0) := "00000"; -- {HPM4,HPM3,IR,TM,CY}

        -- F10 (fix pass W4): the rs1/uimm FIELD is zero. maindec has no rs1 port
        -- by convention, so this one bit is passed in the same way as the P2
        -- inputs above -- it is what distinguishes a CSR WRITE from a read-only
        -- CSR instruction form, and the read-only-CSR trap must fire on writes
        -- ONLY (`csrr t0, mhartid` is legal and appears 74 times in the suite).
        -- SAME rule as csr_unit's write enable (csr_unit.vhd:456): CSRRW/CSRRWI
        -- always write; the set/clear forms write iff the FIELD is nonzero.
        -- DEFAULT '1' = "read-only form". This default is SAFETY, not inertness:
        -- the read-only-CSR trap is UNGATED (it applies in every build), so an
        -- instantiation that left this port unconnected would otherwise see
        -- csr_rs1_zero = '0' and trap every CSR instruction aimed at the
        -- read-only quadrant, INCLUDING plain reads like `csrr t0, mhartid`.
        -- Defaulting '1' means an unwired instantiation traps nothing rather
        -- than trapping everything -- it fails safe, it does not "behave as
        -- before". The only instantiation (controller -> vesta) drives it.
        -- (csr_unit's port of the same name defaults '0'; there the safe
        -- direction is the opposite -- writes enabled, i.e. pre-P3 behaviour.
        -- The two defaults differ on purpose; neither is a typo.)
        csr_rs1_zero     : in  STD_LOGIC := '1';

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

        -- X4 Zfinx FP decode outputs. Each is statically '0' unless ENABLE_ZFINX
        -- (the FP opcodes are absent from valid_opcode when off -> the encodings
        -- trap illegal, bit-identical to base). is_fp_singlecycle retires in
        -- EXECUTE via fpu_simple; is_fp_multicycle/is_fp_fma launch vesta's
        -- FPU_WAIT/FPU_FETCH3 stall states (fma needs the extra rs3-fetch cycle).
        is_fp_singlecycle : out STD_LOGIC;
        is_fp_multicycle  : out STD_LOGIC;
        is_fp_fma         : out STD_LOGIC;

        -- X4 Zfinx: current frm validity (from csr_unit). Used ONLY for the
        -- dynamic-rm (rm=111) legality check on rounding-mode-carrying FP ops.
        frm_valid        : in  STD_LOGIC := '1';

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
    -- X4 Zfinx single-precision FP decode helpers (all ENABLE_ZFINX-gated ->
    -- constant '0' when off). fp_rm_ok legalizes the funct3=rm field for the
    -- rounding-mode-carrying ops; is_fp_single = the single-cycle op-selector
    -- family; is_fp_arith_mc = the multi-cycle rounding OP-FP ops (2 src);
    -- is_fp_fma_op = the FMA family (3 src).
    signal fp_rm_ok        : STD_LOGIC;
    signal is_fp_single    : STD_LOGIC;
    signal is_fp_arith_mc  : STD_LOGIC;
    signal is_fp_fma_op    : STD_LOGIC;
    -- P2 U-mode decode gate. u_gate = "this hart is currently executing in
    -- U-mode on a U-capable build" -- statically '0' when ENABLE_UMODE is off
    -- (priv_m defaults/exports '1' there), which is what makes every U-mode
    -- restriction below fold out of the OFF and trapCsr-only netlists.
    signal u_gate          : STD_LOGIC;
    -- '1' when imm12 names a USER-VIEW counter CSR whose mcounteren enable bit
    -- is CLEAR (so a U-mode access to it must trap illegal). Meaningful only
    -- under u_gate. See the assignment for the hpmcounter5-31 ruling.
    signal ucnt_denied     : STD_LOGIC;
    -- '1' when a CSR instruction is DENIED by the U-mode rules (machine/custom
    -- address, or a counter whose mcounteren bit is clear). Drives BOTH the
    -- illegal-instruction trap and the csr_valid write-enable suppression.
    signal u_csr_denied    : STD_LOGIC;
    -- F10 (fix pass W4): '1' when this CSR instruction WRITES a READ-ONLY CSR.
    -- Like u_csr_denied it drives BOTH the illegal-instruction trap and the
    -- csr_valid write-enable suppression, and for the same reason.
    signal csr_ro_denied   : STD_LOGIC;


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
        -- X4 Zfinx fflags/frm/fcsr: KNOWN CSRs only when ENABLE_ZFINX (else
        -- 0x001/0x002/0x003 are unknown CSRs -> illegal, the both-polarity gate).
        (ENABLE_ZFINX and (imm12 = CSR_FFLAGS or imm12 = CSR_FRM or imm12 = CSR_FCSR)) or
        -- P1 standard M-mode trap CSRs + the custom mtrapctl legacy-select bit:
        -- KNOWN CSRs only when ENABLE_TRAPCSR (else 0x300/0x310/0x305/0x304/0x344/
        -- 0x340/0x341/0x342/0x343/0x7C0 are unknown CSRs -> illegal instruction,
        -- the OFF polarity pinned by the P0 privprobe poisons).
        (ENABLE_TRAPCSR and (imm12 = CSR_MSTATUS  or imm12 = CSR_MSTATUSH or
                             imm12 = CSR_MTVEC    or imm12 = CSR_MIE      or
                             imm12 = CSR_MIP      or imm12 = CSR_MSCRATCH or
                             imm12 = CSR_MEPC     or imm12 = CSR_MCAUSE   or
                             imm12 = CSR_MTVAL    or imm12 = CSR_MTRAPCTL)) or
        -- P3 PMP bank: pmpcfg0-3 (0x3A0-0x3A3) + pmpaddr0-15 (0x3B0-0x3BF) are
        -- KNOWN CSRs only when ENABLE_PMP (else all twenty are unknown CSRs ->
        -- illegal instruction, the both-polarity gate). RANGE compares are
        -- correct HERE -- this is the ADDRESS-LEGALITY map, not a write arm; the
        -- csr_unit write arms stay EXACTLY decoded, one per CSR (p0_specs.md
        -- 4.1). The whole ADDRESS range is admitted regardless of PMP_ENTRIES:
        -- with 8 entries the upper half is still legal and reads WARL zero.
        (ENABLE_PMP and ((unsigned(imm12) >= unsigned(CSR_PMPCFG0)  and
                          unsigned(imm12) <= unsigned(CSR_PMPCFG3)) or
                         (unsigned(imm12) >= unsigned(CSR_PMPADDR0) and
                          unsigned(imm12) <= unsigned(CSR_PMPADDR15)))) or
        (unsigned(imm12) >= unsigned(CSR_MHPMCOUNTER3)  and unsigned(imm12) <= x"B1F") or -- mhpmcounter3-31
        (unsigned(imm12) >= unsigned(CSR_MHPMCOUNTER3H) and unsigned(imm12) <= x"B9F") or -- mhpmcounter3h-31h
        (unsigned(imm12) >= unsigned(CSR_MHPMEVENT3)    and unsigned(imm12) <= x"33F") or -- mhpmevent3-31
        (unsigned(imm12) >= unsigned(CSR_HPMCOUNTER3)   and unsigned(imm12) <= x"C1F") or -- hpmcounter3-31 (user)
        (unsigned(imm12) >= unsigned(CSR_HPMCOUNTER3H)  and unsigned(imm12) <= x"C9F")    -- hpmcounter3h-31h (user)
    ) else '0';

    -- ==========================================================================
    -- P2 U-mode decode gating (p0_specs.md 3 / 3.1)
    -- ==========================================================================
    -- ONE gate signal drives every U-mode restriction, and it is statically '0'
    -- unless ENABLE_UMODE -- so an OFF or trapCsr-only build's decode is
    -- bit-identical (priv_m reads '1' there by the frozen csr_unit contract).
    u_gate <= '1' when (ENABLE_UMODE and priv_m = '0') else '0';

    -- mcounteren gating of the USER-VIEW counters. A U-mode read traps illegal
    -- (cause 2) unless the matching mcounteren bit is set:
    --   CY(0)->cycle/cycleh  TM(1)->time/timeh  IR(2)->instret/instreth
    --   HPM3(3)->hpmcounter3/3h  HPM4(4)->hpmcounter4/4h
    -- CONTRACT-SILENT POINT, ruled here and flagged at the gate: mcounteren bits
    -- 5-31 are WARL 0 (only 4:0 have storage), so the REST of the legal user
    -- ranges -- hpmcounter5-31 (0xC05-0xC1F) and their h-forms (0xC85-0xC9F) --
    -- can never be enabled and therefore ALWAYS trap in U-mode. That is the
    -- spec-correct reading (mcounteren bit clear => trap) and the conservative
    -- one; leaving them readable while hpmcounter3 traps would be a hole.
    -- The MACHINE views (0xB00/0x320 ranges) need no term here: they are caught
    -- by the csr_addr(9:8) /= "00" comparator in the SYSTEM arm below.
    ucnt_denied <= '1' when (
        ((imm12 = CSR_CYCLE       or imm12 = CSR_CYCLEH)       and mcounteren_bits(0) = '0') or
        ((imm12 = CSR_TIME        or imm12 = CSR_TIMEH)        and mcounteren_bits(1) = '0') or
        ((imm12 = CSR_INSTRET     or imm12 = CSR_INSTRETH)     and mcounteren_bits(2) = '0') or
        ((imm12 = CSR_HPMCOUNTER3 or imm12 = CSR_HPMCOUNTER3H) and mcounteren_bits(3) = '0') or
        ((imm12 = CSR_HPMCOUNTER4 or imm12 = CSR_HPMCOUNTER4H) and mcounteren_bits(4) = '0') or
        (unsigned(imm12) >= x"C05" and unsigned(imm12) <= x"C1F") or   -- hpmcounter5-31  (mcounteren 5-31 = WARL 0)
        (unsigned(imm12) >= x"C85" and unsigned(imm12) <= x"C9F")      -- hpmcounter5h-31h
    ) else '0';

    -- THE U-mode CSR denial, factored into ONE signal because it has TWO
    -- consumers that must never disagree:
    --   (1) valid_funct in the SYSTEM arm below -> the illegal-instruction trap;
    --   (2) csr_valid -> csr_unit's WRITE ENABLE (csr_write_en <= csr_valid ...).
    -- (2) is LOAD-BEARING and was missing: csr_valid was a bare `is_csr_instr`,
    -- so a U-mode `csrw mtvec/mepc/mtrapctl/mscratch/...` would take the illegal
    -- trap AND STILL COMMIT THE WRITE -- a full escape (rewrite mtvec, or set
    -- mtrapctl.LEGACY, from user code). Trapping an instruction must leave NO
    -- architectural side effect (kickoff 3b class 1, generalised beyond the
    -- regfile). Statically '0' when ENABLE_UMODE is off (u_gate folds), so the
    -- OFF and trapCsr-only builds are bit-identical.
    --   (a) imm12(9:8) /= "00" -- ONE comparator covering EVERY machine
    --       (0x3xx/0xBxx/0xFxx) and custom (0x7C0 mtrapctl) CSR. imm12 IS
    --       csr_addr for a CSR instruction.
    --   (b) a user-view counter whose mcounteren enable bit is clear.
    u_csr_denied <= '1' when (u_gate = '1' and is_csr_instr = '1' and
                              (imm12(9 downto 8) /= "00" or ucnt_denied = '1'))
                    else '0';

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
    -- P2: csr_valid IS csr_unit's write enable, so a U-mode-DENIED access must
    -- clear it or the trapping instruction still commits its write (see the
    -- u_csr_denied comment above). Identity when ENABLE_UMODE is off.
    -- P3-entry (p3_kickoff.md 3 item 2): ALSO qualified by csr_addr_valid --
    -- an UNKNOWN CSR address traps (valid_funct already handles that), and the
    -- write enable must go down with it, for the same trapped-instruction-
    -- commits-nothing rule. Benign today (no csr_unit write arm matches an
    -- unknown address) but a live landmine for the P3 pmpcfg/pmpaddr bank:
    -- 16+4 new write arms, where any arm decoded wider than the exact address
    -- set would otherwise be reachable from a trapping encoding. privcsr
    -- CHECK 35 pins the trap-and-commit-nothing behavior.
    -- F10 (fix pass W4): and by csr_ro_denied, for the identical reason -- a
    -- read-only-CSR write traps, so it must commit nothing. Belt and braces
    -- here (no csr_unit write arm matches a read-only address today), exactly
    -- as the csr_addr_valid term above is.
    csr_valid <= is_csr_instr and csr_addr_valid
                 and (not u_csr_denied) and (not csr_ro_denied);

    -- ==========================================================================
    -- F10 (fix pass W4) -- A WRITE TO A READ-ONLY CSR IS AN ILLEGAL INSTRUCTION
    -- ==========================================================================
    -- THE RULE (RISC-V privileged spec, csr address encoding): csr[11:10] = "11"
    -- marks the address READ-ONLY, and any instruction FORM that would write
    -- such a CSR raises an illegal-instruction exception. Everything below that
    -- quadrant is WRITABLE -- possibly WARL, possibly write-ignored, but NOT a
    -- trap. Spike implements exactly this, which is why the rule is stated as
    -- ONE COMPARATOR on imm12(11:10) and not as an enumeration of the CSRs this
    -- csr_unit happens not to store.
    --
    -- SCOPE NOTE, because the finding as filed was wider than the rule.
    -- rtl_findings.md F10 lists "mhartid, misa, cycle/time/instret[h],
    -- hpmcounter*, mhpmcounter5-31, mhpmevent5-31 ... plus mip => null", i.e.
    -- every address csr_unit ADMITS BUT DOES NOT STORE (csr_unit.vhd's
    -- `csr_addr_stores`). That set is NOT the read-only set, and the difference
    -- is load-bearing: misa (0x301), mip (0x344), mstatush (0x310),
    -- mcountinhibit (0x320), mhpmevent3-31 (0x32x/0x33x) and mhpmcounter3-31
    -- (0xB0x-0xB1F) all sit BELOW the read-only quadrant. They are writable
    -- CSRs whose writes this implementation legally ignores (WARL / not
    -- implemented) -- and the ledger's own justification, "Spike traps", does
    -- NOT hold for them: Spike accepts those writes too. Trapping them would
    -- manufacture divergences rather than remove them. So the trap covers
    -- imm12(11:10)="11" and nothing else, and the write-ignore behaviour of the
    -- rest stays as-is and stays documented in the erratum. In particular
    -- divergence D-2026-07-29-1 (`csrrw zero, mhpmevent3, t0`, address 0x323)
    -- is NOT in this set and is unaffected.
    --
    -- WHY IT IS GATED ON ENABLE_TRAPCSR (D3-bis, 2026-07-31) -- SUPERSEDED:
    -- UNGATED, IN EVERY BUILD (user ruling, 2026-07-31, superseding D3-bis).
    -- An earlier draft gated this on ENABLE_TRAPCSR, on the reasoning that
    -- trapping is only well-defined where a trap architecture exists. That
    -- ruling rested on a premise that measurement removed: it assumed
    -- `rv32ua-p-extzihpm` depended on the accept-and-drop behaviour, which is
    -- true only under the MIS-SCOPED reading above -- all nine of its writes
    -- are writable-quadrant and none of them reach this arm. With the premise
    -- gone the user re-ruled to ungate, and the reasons are worth keeping:
    --   * the SHIPPING configuration gets spec-conformant behaviour, not just
    --     knobs-on builds;
    --   * `unimp` (0xC0001073 = `csrrw x0, cycle, x0`) starts trapping, which
    --     is what CLAUDE.md has always claimed it does. That documented
    --     property was FALSE -- measured, not argued: the F10 detector's hart 2
    --     executed `unimp` and walked straight past it into its park loop with
    --     current_state = EXECUTE. This arm is what makes the doc true, and a
    --     documented safety property that does not hold is worse than an
    --     undocumented one, because tests get written against it;
    --   * the exposure is bounded and was measured, not assumed. Across EVERY
    --     .rcf in the repo (843 files, 10,053,900 halfwords, scanned at BOTH
    --     halfword phases) the only read-only-quadrant CSR write that exists
    --     anywhere is `unimp` -- 273 sites, and ZERO of them in either bootrom
    --     image or any course image. Of the 139 `unimp` instructions in the
    --     built ELFs, 129 sit behind a spin/self-loop, 6 behind an `iret` and 4
    --     behind a `ret`: NONE is fall-through reachable;
    --   * and if one ever were reachable it now fails LOUDLY instead of
    --     silently. On a legacy build the trap enters the terminal TRAP_STATE,
    --     the PC freezes, no a0 is written and the 100 ms tb watchdog reports
    --     the test FAILED. Today that same site is a silent NOP. Turning a
    --     silent wrong-behaviour into a loud one is the point.
    --
    -- THIS IS A REAL BEHAVIOUR CHANGE IN THE DEFAULT BUILD -- there is no
    -- bit-identity argument here and none should be reconstructed. What changes
    -- is exactly: a CSR instruction in a WRITE FORM aimed at an address with
    -- imm12(11:10) = "11" now raises illegal-instruction instead of retiring as
    -- a NOP. Reads of those addresses are untouched, and every writable-quadrant
    -- WARL write-ignore is untouched.
    csr_ro_denied <= '1' when (is_csr_instr = '1' and
                               imm12(11 downto 10) = "11" and
                               (funct3(1 downto 0) = "01" or csr_rs1_zero = '0'))
                     else '0';

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
    --
    -- THE FUNCT5 WHITELIST IS LOAD-BEARING, NOT COSMETIC (P2 red-team finding,
    -- 2026-07-28). It MUST match the AMO_OPCODE arm of valid_funct below,
    -- because an encoding that is illegal there but still raises amo_op gets
    -- BOTH trap='1' AND an AMO memory access: the trap dispatch freezes pc_en
    -- but does NOT force `wen`, and hart_tile's sh_we_lanes carries no FSM-state
    -- qualifier -- so a RESERVED-funct5 word AMO took the illegal-instruction
    -- trap and STILL COMMITTED A WRITE, zeroing the word at its address
    -- (reproduced on the DEFAULT build: pc=0x82BC trapped, 0x82C0 overwritten).
    -- Whitelisting here fixes it at the root: a reserved encoding never becomes
    -- a memory operation, so there is no transaction to suppress downstream.
    -- Unreachable from any compiler (no toolchain emits a reserved AMO funct5),
    -- which is why the X2-era whitelist tightening of valid_funct missed it.
    -- Keep this expression and valid_funct's AMO arm in lockstep forever.
    amo_op <= '1' when (ENABLE_ATOMICS and op = AMO_OPCODE and
                        (is_std_amo_fn5 = '1' or (ENABLE_ZACAS and funct5 = CAS_FN5)) and
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
    -- X4 Zfinx single-precision FP decode
    -- ==========================================
    -- rm-field (funct3) legality for the rounding-mode-carrying ops: 000..100
    -- legal, 101/110 illegal, 111 (dynamic) legal iff frm is a valid mode. The
    -- op-selector ops (fsgnj*/fmin/fmax/fcmp/fclass) do NOT consult this — their
    -- funct3 is checked exactly below. imm12(4:0) = instr[24:20] = the rs2 field.
    fp_rm_ok <= '1' when (funct3 = "000" or funct3 = "001" or funct3 = "010" or
                          funct3 = "011" or funct3 = "100" or
                          (funct3 = FRM_DYN and frm_valid = '1')) else '0';

    -- Single-cycle OP-FP (op-selector funct3, no rounding, retire in EXECUTE).
    -- FCLASS shares funct7 with fmv.x.w; only rm=001/rs2=0 (fclass) is legalized,
    -- so fmv.x.w (rm=000) stays illegal — Zfinx has no fmv.
    is_fp_single <= '1' when (ENABLE_ZFINX and op = OPFP_OPCODE and (
        (funct7 = FSGNJ_FN7   and (funct3 = "000" or funct3 = "001" or funct3 = "010")) or  -- fsgnj/n/x
        (funct7 = FMINMAX_FN7 and (funct3 = "000" or funct3 = "001")) or                    -- fmin/fmax
        (funct7 = FCMP_FN7    and (funct3 = "000" or funct3 = "001" or funct3 = "010")) or  -- fle/flt/feq
        (funct7 = FCLASS_FN7  and funct3 = "001" and imm12(4 downto 0) = "00000")           -- fclass
    )) else '0';

    -- Multi-cycle OP-FP that rounds (2 source regs, no rs3). fmv.w.x (funct7
    -- 1111000) is NOT in this list -> stays illegal.
    is_fp_arith_mc <= '1' when (ENABLE_ZFINX and op = OPFP_OPCODE and fp_rm_ok = '1' and (
        funct7 = FADD_FN7 or funct7 = FSUB_FN7 or funct7 = FMUL_FN7 or funct7 = FDIV_FN7 or
        (funct7 = FSQRT_FN7 and imm12(4 downto 0) = FP_RS2_W) or
        (funct7 = FCVTW_FN7 and (imm12(4 downto 0) = FP_RS2_W or imm12(4 downto 0) = FP_RS2_WU)) or
        (funct7 = FCVTS_FN7 and (imm12(4 downto 0) = FP_RS2_W or imm12(4 downto 0) = FP_RS2_WU))
    )) else '0';

    -- FMA family (3 source regs). fmt = funct7(1:0) must be 00 (single); rs3 =
    -- funct7(6:2) is a don't-care. Distinct opcodes (0x43/0x47/0x4B/0x4F).
    is_fp_fma_op <= '1' when (ENABLE_ZFINX and fp_rm_ok = '1' and funct7(1 downto 0) = "00" and
        (op = FMADD_OPCODE or op = FMSUB_OPCODE or op = FNMSUB_OPCODE or op = FNMADD_OPCODE)) else '0';

    is_fp_singlecycle <= is_fp_single;
    is_fp_multicycle  <= is_fp_arith_mc;
    is_fp_fma         <= is_fp_fma_op;

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
        ((ENABLE_ZCMP or ENABLE_ZCMT) and op = ZCM_SENTINEL_OP) or  -- X3 Zcmp/Zcmt cm.* sentinel
        -- X4 Zfinx FP opcodes (each ENABLE_ZFINX-gated so OFF = current
        -- illegal-trap behaviour, bit-identical).
        (ENABLE_ZFINX and op = OPFP_OPCODE)   or  -- OP-FP (0x53)
        (ENABLE_ZFINX and op = FMADD_OPCODE)  or  -- fmadd.s
        (ENABLE_ZFINX and op = FMSUB_OPCODE)  or  -- fmsub.s
        (ENABLE_ZFINX and op = FNMSUB_OPCODE) or  -- fnmsub.s
        (ENABLE_ZFINX and op = FNMADD_OPCODE)     -- fnmadd.s
    ) else '0';

    process(op, funct3, funct7, funct5, imm12, valid_opcode, is_custom_instr, is_mul_div, is_amo_instr, is_zba_instr, is_zbb_r_instr, is_zbb_i_instr, is_zbs_r_instr, is_zbs_i_instr, is_zbc_instr, is_zicond_instr, is_aes_instr, is_wrs_instr, is_csr_instr, is_zimop_instr, csr_addr_valid, is_std_amo_fn5, is_sha256_instr, is_sha512_instr, is_zbkb_new_r_instr, is_zbkb_new_i_instr, is_zbkb_shared_r_instr, is_zbkb_shared_i_instr, is_zbkx_instr, is_fp_single, is_fp_arith_mc, is_fp_fma_op, u_gate, u_csr_denied, csr_ro_denied, status_tw)
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
                    if u_gate = '1' then
                        -- P2: the three custom Vesta instructions
                        -- (iret / extinguish / ignite) are PRIVILEGED -- they
                        -- drive the legacy irq_handler handshake and the sleep
                        -- state directly, so U-mode must not reach them. The
                        -- whole opcode traps illegal (cause 2) in U-mode.
                        valid_funct <= '0';
                    elsif not ((funct3 = IRET_FN3 and funct7 = IRET_FN7) or
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
                        -- P2: in U-mode two further classes trap illegal:
                        --   (a) csr_addr(9:8) /= "00" -- ONE comparator that
                        --       covers EVERY machine (0x3xx/0xBxx/0xFxx) and
                        --       custom (0x7C0 mtrapctl) CSR, plus the machine
                        --       counter views. imm12 IS csr_addr here.
                        --   (b) a user-view counter whose mcounteren bit is 0.
                        -- ONE expression, shared with the csr_valid write-enable
                        -- suppression (u_csr_denied) so the trap and the
                        -- side-effect block can never disagree.
                        -- F10 (fix pass W4): a WRITE to a READ-ONLY CSR
                        --     (imm12(11:10)="11") is likewise illegal, in EVERY
                        --     build -- csr_ro_denied carries no ENABLE_ term.
                        --     Tested AFTER the U-mode denial only because that
                        --     is older; both report cause 2, so order is moot.
                        if u_csr_denied = '1' then
                            valid_funct <= '0';
                        elsif csr_ro_denied = '1' then
                            valid_funct <= '0';
                        else
                            valid_funct <= csr_addr_valid;
                        end if;
                    elsif is_zimop_instr = '1' then
                        valid_funct <= '1';  -- Zimop mop.r.N / mop.rr.N (rd<-0)
                        valid_funct <= '1';  -- All CSR instructions are valid
                    elsif is_wrs_instr = '1' then
                        valid_funct <= '1';  -- X1 Zawrs wrs.nto/wrs.sto (legal when enabled)
                    elsif ENABLE_TRAPCSR and funct3 = PRIV_FN3 then
                        -- P1/P2: the SYSTEM PRIV arm. Exactly FOUR funct12
                        -- values are legal -- ECALL (0x000), EBREAK (0x001),
                        -- MRET (0x302) and, from P2, WFI (0x105). EVERY other
                        -- funct12 on this arm stays ILLEGAL.
                        if imm12 = ECALL_IMM12 or imm12 = EBREAK_IMM12 then
                            -- ECALL/EBREAK are legal in BOTH privilege modes
                            -- (that is the point of ECALL from U -- cause 8).
                            valid_funct <= '1';
                        elsif imm12 = MRET_IMM12 then
                            -- P2: MRET is M-mode only (illegal-instruction in U).
                            if u_gate = '1' then
                                valid_funct <= '0';
                            else
                                valid_funct <= '1';
                            end if;
                        elsif imm12 = WFI_IMM12 then
                            -- P2: WFI is legal in M always, and in U iff
                            -- mstatus.TW = 0. The TW denial is a DECODE illegal
                            -- (cause 2) -- p0_specs.md 3.1.
                            if u_gate = '1' and status_tw = '1' then
                                valid_funct <= '0';
                            else
                                valid_funct <= '1';
                            end if;
                        else
                            valid_funct <= '0';
                        end if;
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

                -- X4 Zfinx OP-FP: legal iff the exact funct7/funct3/rs2 encoding
                -- decodes to a supported Zfinx op (single- or multi-cycle). This
                -- arm is reached ONLY when ENABLE_ZFINX (valid_opcode gates it);
                -- rm-illegal, fmv.w.x/fmv.x.w, and reserved encodings fall through
                -- to '0' = illegal.
                when OPFP_OPCODE =>
                    if is_fp_single = '1' or is_fp_arith_mc = '1' then
                        valid_funct <= '1';
                    else
                        valid_funct <= '0';
                    end if;

                -- X4 Zfinx FMA opcodes: legal iff fmt=00 (single) and rm legal.
                when FMADD_OPCODE | FMSUB_OPCODE | FNMSUB_OPCODE | FNMADD_OPCODE =>
                    if is_fp_fma_op = '1' then
                        valid_funct <= '1';
                    else
                        valid_funct <= '0';
                    end if;

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
    -- P2: all three carry the U-mode qualifier for the SAME reason csr_valid
    -- does -- valid_funct='0' makes them trap, but these outputs are SIDE
    -- EFFECTS that fire independently of the trap: isr_ret pulses the legacy
    -- irq_handler EOI, and sleep_rq/wake_rq set/clear the `sleep_cpu` flop in
    -- vesta (an unconditional process on the free-running clk). Without the
    -- qualifier a U-mode `extinguish` would trap AND leave sleep_cpu set, so a
    -- later legacy-mode IRQ_REST would return M-mode to SLEEPING -- a U-mode
    -- denial of service on M. Identity when ENABLE_UMODE is off (u_gate folds).
    isr_ret  <= '1' when (op = CUSTOM_OPCODE and funct3 = IRET_FN3 and funct7 = IRET_FN7  and u_gate = '0') else '0';
    sleep_rq <= '1' when (op = CUSTOM_OPCODE and funct3 = SLP_FN3 and funct7 = SLEEP_FN7 and u_gate = '0') else '0';
    wake_rq  <= '1' when (op = CUSTOM_OPCODE and funct3 = SLP_FN3 and funct7 = WAKE_FN7  and u_gate = '0') else '0';

    -- ==========================================
    -- P1 standard SYSTEM/PRIV decode outputs (ENABLE_TRAPCSR)
    -- ==========================================
    -- All three are statically '0' when the generic is off, exactly matching the
    -- valid_funct arm above that keeps the encodings illegal on an OFF build.
    -- Consumed ONLY by vesta's FSM dispatch arms (which additionally qualify on
    -- the delivery mode) -- these signals never feed valid_funct/trap.
    ecall_op  <= '1' when (ENABLE_TRAPCSR and op = SYSTEM_OPCODE and
                           funct3 = PRIV_FN3 and imm12 = ECALL_IMM12)  else '0';
    ebreak_op <= '1' when (ENABLE_TRAPCSR and op = SYSTEM_OPCODE and
                           funct3 = PRIV_FN3 and imm12 = EBREAK_IMM12) else '0';
    -- P3-entry (p3_kickoff.md 3 item 4 / P2 red-team A17): mret_op carries the
    -- U-mode qualifier like wfi_op below -- structural consistency, so no new
    -- consumer can ever see a dispatch strobe for an encoding that trapped in
    -- U. (Today it is redundant: every vesta FSM arm checks `trap` before
    -- mret_op, which is why A17 was HARDENING, not a defect.)
    mret_op   <= '1' when (ENABLE_TRAPCSR and op = SYSTEM_OPCODE and
                           funct3 = PRIV_FN3 and imm12 = MRET_IMM12 and
                           u_gate = '0')                               else '0';

    -- P2 standard WFI. Carries its OWN legality qualifier (M-mode, or TW=0) so
    -- the dispatch signal can never be high for an encoding valid_funct just
    -- declared illegal -- belt and braces: vesta checks `trap` FIRST in every
    -- decode arm, so a TW-denied WFI takes the illegal path regardless.
    wfi_op    <= '1' when (ENABLE_TRAPCSR and op = SYSTEM_OPCODE and
                           funct3 = PRIV_FN3 and imm12 = WFI_IMM12 and
                           not (u_gate = '1' and status_tw = '1')) else '0';

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
                 '1' when (is_fp_single = '1' or is_fp_arith_mc = '1' or is_fp_fma_op = '1') else  -- X4 Zfinx: all FP ops write rd
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
    -- F5.2 (fix pass W1): this comment described a 2-BIT encoding
    -- ("00: ALU result, 01: Memory data, 10: PC+4, 11: PC+immediate"), but
    -- result_src is THREE bits (:53) and half the codes below are outside that
    -- list. The real encoding:
    --   000 ALU result          001 Memory data        010 PC+4
    --   011 PC+immediate        100 CSR read value     101 Zimop (rd <- 0)
    --   110 RSRC_FP_SINGLE      111 RSRC_FP_MULTI      (constants.vhd:522-523)
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
                  RSRC_FP_SINGLE when is_fp_single = '1' else  -- X4 single-cycle FP (fpu_simple, EXECUTE)
                  RSRC_FP_MULTI  when (is_fp_arith_mc = '1' or is_fp_fma_op = '1') else  -- X4 multi-cycle FP (fpu, FPU_DONE)
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

