library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.constants.all;

entity maindec is
    generic (
        -- Core ISA feature switches; the defaults select the full RV32IMAC+Zba/Zbb/Zbs/Zbc core.
        -- A disabled extension's encodings fall out of valid_opcode/valid_funct and take the illegal-instruction trap path.
        ENABLE_MUL      : boolean := true;
        ENABLE_DIV      : boolean := true;
        ENABLE_ATOMICS  : boolean := true;
        ENABLE_BITMANIP : boolean := true;
        ENABLE_ZICOND   : boolean := false;  -- Zicond conditional zero
        ENABLE_ZIMOP    : boolean := false;  -- Zimop may-be-operations
        ENABLE_ZIHINT   : boolean := false;  -- Zihintpause
        ENABLE_ZAWRS    : boolean := false;  -- Zawrs wrs.nto / wrs.sto
        ENABLE_ZABHA    : boolean := false;  -- Zabha byte/halfword AMOs
        ENABLE_ZACAS    : boolean := false;  -- Zacas compare-and-swap
        ENABLE_ZICBOZ   : boolean := false;  -- Zicboz: cbo.zero cache-block zero
        ENABLE_ZCMP     : boolean := false;  -- Zcmp: compressed push/pop + reg-moves
        ENABLE_ZCMT     : boolean := false;  -- Zcmt: compressed table jump + jvt CSR
        ENABLE_ZBKB     : boolean := false;  -- Zbkb crypto bit-manip
        ENABLE_ZBKC     : boolean := false;  -- Zbkc carry-less multiply
        ENABLE_ZBKX     : boolean := false;  -- Zbkx crossbar permute
        ENABLE_ZKN      : boolean := false;  -- Zkn scalar crypto (AES, SHA)
        ENABLE_ZFINX    : boolean := false;  -- Zfinx single-precision FP in the integer regfile
        -- Privileged-architecture switches: ENABLE_TRAPCSR opens the SYSTEM PRIV_FN3 arm (ECALL 0x000, EBREAK 0x001, WFI 0x105, MRET 0x302) and the M-mode trap CSRs.
        ENABLE_TRAPCSR  : boolean := false;  -- M-mode trap CSRs + MRET/ECALL/EBREAK/WFI
        ENABLE_UMODE    : boolean := false;  -- U-mode privileged-access gate
        ENABLE_PMP      : boolean := false;  -- PMP (Smpmp) CSR addresses
        -- Core-side debug mode: admits the four Debug-Mode CSR addresses (0x7B0-0x7B3) and the DRET encoding.
        -- Both are additionally qualified by the live debug_mode input below, so this generic alone never opens anything; it must default false at every declaration site.
        ENABLE_DEBUG    : boolean := false   -- debug mode
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
        alu_control      : out STD_LOGIC_VECTOR(6 downto 0);  -- 7-bit ALU operation code
        mem_access_instr : out STD_LOGIC;
        
        -- Custom instruction outputs
        isr_ret          : out STD_LOGIC;
        sleep_rq         : out STD_LOGIC;
        wake_rq          : out STD_LOGIC;

        -- Standard SYSTEM/PRIV decode (funct3 = PRIV_FN3 = 000), each statically '0' unless ENABLE_TRAPCSR, where the three encodings are absent from valid_funct too and stay illegal instructions.
        -- rs1/rd are architecturally x0 for all three but are NOT decoded here, because maindec has no rs1/rd ports; funct12 alone legalizes them, as it does for Zawrs and cbo.zero.
        ecall_op         : out STD_LOGIC;
        ebreak_op        : out STD_LOGIC;
        mret_op          : out STD_LOGIC;

        -- Standard WFI (SYSTEM PRIV imm12 = 0x105), legal iff ENABLE_TRAPCSR and (M-mode or mstatus.TW = '0'), and statically '0' when the generic is off, where 0x105 stays illegal.
        -- Consumed ONLY by vesta's FSM (enter SLEEPING with the standard wake rule); it never feeds valid_funct or trap.
        wfi_op           : out STD_LOGIC;

        -- DRET (SYSTEM PRIV imm12 = 0x7B2), legal iff ENABLE_DEBUG and the hart is in debug mode; outside debug mode the encoding falls to the PRIV arm's final else and raises illegal-instruction.
        -- Statically '0' when ENABLE_DEBUG is off; consumed ONLY by vesta's FSM.
        dret_op          : out STD_LOGIC;

        -- Debug-mode decode input, from csr_unit via controller.
        -- It defaults '0' so an unconnected port means NOT in debug mode, leaving the 0x7Bx block denied and DRET illegal; never invert this into a dbg_allow input defaulting '1'.
        debug_mode       : in  STD_LOGIC := '0';                       -- '1' = executing in debug mode

        -- U-mode decode inputs, from csr_unit via controller.
        -- Every one carries the INERT default, so an instantiation that does not drive them, like every ENABLE_UMODE=false build, sees M-mode with TW=0 and no counter enables and folds the U-mode gate away.
        priv_m           : in  STD_LOGIC := '1';                       -- '1'=M, '0'=U
        status_tw        : in  STD_LOGIC := '0';                       -- mstatus.TW
        mcounteren_bits  : in  STD_LOGIC_VECTOR(4 downto 0) := "00000"; -- {HPM4,HPM3,IR,TM,CY}

        -- The rs1/uimm FIELD is zero: it distinguishes a CSR WRITE form from a read-only CSR instruction form, and the read-only-CSR trap must fire on write forms ONLY, since `csrr t0, mhartid` is legal.
        -- Same rule as csr_unit's write enable: CSRRW/CSRRWI always write, while the set/clear forms write iff the field is nonzero.
        -- DEFAULT '1' (read-only form) is a SAFETY choice, not inertness: the read-only-CSR trap is ungated, so an unwired port must trap nothing rather than trap every read-only-quadrant access. csr_unit's port of the same name defaults '0', where the safe direction is the opposite; the two differ on purpose.
        csr_rs1_zero     : in  STD_LOGIC := '1';

        -- The R-type rs2 FIELD is zero, arriving as a port because maindec decodes no register fields.
        -- It qualifies EXACTLY ONE decode row, Zbb `zext.h rd,rs1` (funct7 = ZEXT_FN7, funct3=100), which is bit-identical to Zbkb `pack rd,rs1,x0`; without this term the whole pack encoding space aliases onto the ZEXT.H row on a Zbkb-off build and retires silently instead of trapping.
        -- DEFAULT '0' (rs2 NOT zero) is fail-safe: an unwired port makes zext.h illegal in every build, which is loud, where defaulting '1' would silently reinstate the alias this port exists to close.
        rs2_zero         : in  STD_LOGIC := '0';

        -- Zawrs: wrs_op is a decoded wrs.nto or wrs.sto (illegal unless ENABLE_ZAWRS and ENABLE_ATOMICS), and wrs_sto marks the timeout variant.
        wrs_op           : out STD_LOGIC;
        wrs_sto          : out STD_LOGIC;
        
        -- RV32A atomic operation signals
        amo_op           : out STD_LOGIC;
        lr_op            : out STD_LOGIC;
        sc_op            : out STD_LOGIC;
        fence_op         : out STD_LOGIC;

        -- Zicboz: '1' for the exact cbo.zero encoding (MISC-MEM, funct3=010, imm12=0x004) when ENABLE_ZICBOZ, statically '0' otherwise, where the encoding traps illegal via the FENCE valid_funct fall-through.
        -- Consumed by vesta's FSM to launch the 16-word block-zero store sequencer.
        cboz_op          : out STD_LOGIC;

        -- Zcmp/Zcmt: '1' for a legal cm.* SENTINEL (op = ZCM_SENTINEL_OP, produced only by c_dec and gated on the generics), which launches vesta's push/pop/move/table-jump sequencer.
        -- Statically '0' when both generics are off, since the sentinel opcode is then never valid; the sub-op and operand fields are read from the instruction word by vesta.
        zcm_op           : out STD_LOGIC;

        -- Zihintpause: '1' for the exact PAUSE hint (fence w,0) when ENABLE_ZIHINT, statically '0' otherwise, so a disabled build's FENCE path is unchanged.
        -- Consumed by vesta's FSM to open the PAUSE arbiter-yield window; it never affects legality or trap, since PAUSE is a FENCE.
        pause_hint       : out STD_LOGIC;

        -- CSR control signals
        csr_op           : out STD_LOGIC_VECTOR(2 downto 0);
        csr_valid        : out STD_LOGIC;

        -- Zfinx FP decode outputs, each statically '0' unless ENABLE_ZFINX: the FP opcodes are then absent from valid_opcode and the encodings trap illegal.
        -- is_fp_singlecycle retires in EXECUTE via fpu_simple; is_fp_multicycle and is_fp_fma launch vesta's FPU_WAIT/FPU_FETCH3 stall states (fma needs the extra rs3-fetch cycle).
        is_fp_singlecycle : out STD_LOGIC;
        is_fp_multicycle  : out STD_LOGIC;
        is_fp_fma         : out STD_LOGIC;

        -- Zfinx: current frm validity, from csr_unit.
        -- Used ONLY for the dynamic-rm (rm=111) legality check on rounding-mode-carrying FP ops.
        frm_valid        : in  STD_LOGIC := '1';

        -- Trap signal for invalid instructions
        trap             : out STD_LOGIC
    );
end maindec;

architecture behave of maindec is

    -- ========== Internal Signal Declarations ==========
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
    -- Scalar-crypto bit-manip helpers: the new Zbkb ops, the Zbkb/Zbb shared subset gated by ENABLE_ZBKB, and the Zbkx crossbar permute.
    -- Zbkc reuses is_zbc_instr (OR-gated below) and adds no new helper.
    signal is_zbkb_new_r_instr    : STD_LOGIC;  -- pack / packh
    signal is_zbkb_new_i_instr    : STD_LOGIC;  -- brev8 / zip / unzip
    signal is_zbkb_shared_r_instr : STD_LOGIC;  -- andn/orn/xnor/rol/ror when Zbb off
    signal is_zbkb_shared_i_instr : STD_LOGIC;  -- rori / rev8 when Zbb off
    signal is_zbkx_instr          : STD_LOGIC;  -- xperm8 / xperm4
    signal is_zicond_instr : STD_LOGIC;
    signal is_aes_instr    : STD_LOGIC;  -- Zknd/Zkne: any aes32{e,d}s[m]i (gated by ENABLE_ZKN)
    signal is_csr_instr    : STD_LOGIC;
    -- '1' iff the CSR address (imm12 = instr(31:20)) is architecturally KNOWN; a CSR instruction to an unknown address drops valid_funct and takes the illegal-instruction trap.
    signal csr_addr_valid  : STD_LOGIC;
    signal is_zimop_instr  : STD_LOGIC;  -- Zimop: mop.r.N / mop.rr.N (rd gets 0)
    signal is_pause        : STD_LOGIC;
    signal is_cboz         : STD_LOGIC;  -- Zicboz (cbo.zero)
    signal is_zcm          : STD_LOGIC;  -- Zcmp/Zcmt (the cm.* sentinel)
    signal is_wrs_instr    : STD_LOGIC;  -- Zawrs (wrs.nto / wrs.sto)
    signal is_std_amo_fn5  : STD_LOGIC;  -- one of the nine standard AMO funct5 codes (decode-legality whitelist)
    -- Zknh sigma/sum helpers: SHA-256 (OP-IMM unary) and SHA-512 (OP binary), each gated on ENABLE_ZKN.
    -- With ZKN disabled both stay '0' and the encodings trap illegal.
    signal is_sha256_instr : STD_LOGIC;  -- sha256sig0/sig1/sum0/sum1
    signal is_sha512_instr : STD_LOGIC;  -- sha512sig0l/h, sig1l/h, sum0r, sum1r
    -- Zfinx single-precision FP decode helpers, all ENABLE_ZFINX-gated so they fold to a constant '0' when off.
    -- fp_rm_ok legalizes the funct3=rm field; is_fp_single is the single-cycle op-selector family; is_fp_arith_mc is the multi-cycle rounding OP-FP ops (2 sources); is_fp_fma_op is the FMA family (3 sources).
    signal fp_rm_ok        : STD_LOGIC;
    signal is_fp_single    : STD_LOGIC;
    signal is_fp_arith_mc  : STD_LOGIC;
    signal is_fp_fma_op    : STD_LOGIC;
    -- U-mode decode gate: '1' when this hart is executing in U-mode on a U-capable build.
    -- Statically '0' when ENABLE_UMODE is off (priv_m reads '1' there), which folds every U-mode restriction below out of the netlist.
    signal u_gate          : STD_LOGIC;
    -- '1' when imm12 names a USER-VIEW counter CSR whose mcounteren enable bit is CLEAR, so a U-mode access must trap illegal; meaningful only under u_gate.
    signal ucnt_denied     : STD_LOGIC;
    -- '1' when a CSR instruction is DENIED by the U-mode rules: a machine or custom address, or a counter whose mcounteren bit is clear.
    -- Drives BOTH the illegal-instruction trap and the csr_valid write-enable suppression.
    signal u_csr_denied    : STD_LOGIC;
    -- '1' when this CSR instruction WRITES a READ-ONLY CSR.
    -- Like u_csr_denied it drives BOTH the illegal-instruction trap and the csr_valid write-enable suppression, and for the same reason.
    signal csr_ro_denied   : STD_LOGIC;
    -- '1' when a CSR instruction names the Debug-Mode block (imm12(11:4) = 0x7B) from OUTSIDE debug mode.
    -- It is a THIRD deny signal, not an extension of u_csr_denied, which folds to a constant '0' whenever ENABLE_UMODE is false; like the other two it drives both the trap and the csr_valid suppression.
    signal dbg_csr_denied  : STD_LOGIC;


begin

    -- ========== Helper Signals ==========

    -- Instruction-class detects shared by the legality checks and the output muxes below.
    is_mul_div <= '1' when ((ENABLE_MUL or ENABLE_DIV) and op = R_OPCODE and funct7 = MULT_FN7) else '0';
    is_custom_instr <= '1' when (op = CUSTOM_OPCODE) else '0';
    is_amo_instr <= '1' when (ENABLE_ATOMICS and op = AMO_OPCODE) else '0';
    is_fence <= '1' when (op = FENCE_OPCODE and funct3 = FENCE_FN3) else '0';
    -- Zawrs: SYSTEM opcode, funct3=000, funct12 (imm12) = 0x00D for nto and 0x01D for sto.
    -- Gated on BOTH ENABLE_ZAWRS and ENABLE_ATOMICS, since wrs is useful only with A; rs1/rd are x0 but not decoded here, exactly as for WFI.
    is_wrs_instr <= '1' when (ENABLE_ZAWRS and ENABLE_ATOMICS and op = SYSTEM_OPCODE
                              and funct3 = "000"
                              and (imm12 = WRS_NTO_IMM12 or imm12 = WRS_STO_IMM12)) else '0';
    funct5 <= funct7(6 downto 2);
    -- The nine standard word and sub-word AMO funct5 codes.
    -- Used by the AMO_OPCODE decode-legality case to whitelist funct5; LR/SC and CAS are handled separately, and every other funct5 is a RESERVED encoding that traps.
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
        -- ZEXT.H, and rs2 MUST be x0: ZEXT_FN7 and PACK_FN7 are the same seven bits and `zext.h rd,rs1` IS `pack rd,rs1,x0`, so without the rs2 term this row legalises the entire Zbkb pack space.
        -- A nonzero rs2 falls through to the ENABLE_ZBKB arm below (is_zbkb_new_r_instr), which the valid_funct chain reaches only because this row is narrowed here.
        (funct7 = ZEXT_FN7 and funct3 = "100" and rs2_zero = '1')
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

    -- Zbc and Zbkc carry-less multiply: clmul/clmulh are in both, so the gate is BITMANIP or ZBKC, while clmulr is Zbc-only.
    -- No new alu_control codes: the CLMUL/CLMULH/CLMULR rows are shared, and the ALU arms OR-gate ZBKC to match.
    is_zbc_instr <= '1' when (op = R_OPCODE and funct7 = CLMUL_FN7 and (
                            ((ENABLE_BITMANIP or ENABLE_ZBKC) and (funct3 = CLMUL_FN3 or funct3 = CLMULH_FN3)) or
                            (ENABLE_BITMANIP and funct3 = CLMULR_FN3))) else '0';

    -- ========== Zbkb / Zbkx (scalar crypto bit-manip) decode helpers ==========
    -- New Zbkb R-type ops: pack (funct3=100) and packh (funct3=111), both funct7 = PACK_FN7.
    -- pack shares funct7 and funct3 with Zbb ZEXT.H (the rs2=x0 case); pack is the superset.
    is_zbkb_new_r_instr <= '1' when (ENABLE_ZBKB and op = R_OPCODE and funct7 = PACK_FN7 and
                                     (funct3 = PACK_FN3 or funct3 = PACKH_FN3)) else '0';
    -- New Zbkb OP-IMM ops: brev8, zip and unzip, distinguished by funct3 plus imm12.
    is_zbkb_new_i_instr <= '1' when (ENABLE_ZBKB and op = I_ARITH_OPCODE and (
        (funct3 = "101" and imm12 = BREV8_IMM12) or   -- brev8
        (funct3 = "001" and imm12 = ZIP_IMM12)   or   -- zip
        (funct3 = "101" and imm12 = UNZIP_IMM12)      -- unzip
    )) else '0';
    -- Zbkb shares a subset with Zbb (andn, orn, xnor, rol, ror, rori, rev8), and ENABLE_ZBKB makes ONLY that subset legal when Zbb is off; with Zbb on it is already legal via is_zbb_*.
    -- The non-shared Zbb ops (min, max, clz, cpop, sext, orc.b, zext.h) are NOT in Zbkb, so these helpers match the shared subset only and reuse the existing alu_control rows.
    is_zbkb_shared_r_instr <= '1' when (ENABLE_ZBKB and op = R_OPCODE and (
        (funct7 = ANDN_FN7 and (funct3 = "111" or funct3 = "110" or funct3 = "100")) or  -- ANDN/ORN/XNOR
        (funct7 = ROL_FN7 and (funct3 = "001" or funct3 = "101"))                         -- ROL/ROR
    )) else '0';
    is_zbkb_shared_i_instr <= '1' when (ENABLE_ZBKB and op = I_ARITH_OPCODE and (
        (funct3 = "101" and funct7 = RORI_FN7) or      -- RORI
        (funct3 = "101" and imm12 = REV8_IMM12)        -- REV8  (funct3=101, imm12=0x698; SRL_FN3 group)
    )) else '0';
    -- Zbkx crossbar permute: xperm8 (funct3=100) and xperm4 (funct3=010), both funct7 = XPERM_FN7.
    is_zbkx_instr <= '1' when (ENABLE_ZBKX and op = R_OPCODE and funct7 = XPERM_FN7 and
                               (funct3 = XPERM8_FN3 or funct3 = XPERM4_FN3)) else '0';

    -- RV32 Zicond: czero.eqz (funct3=101) and czero.nez (funct3=111), OP funct7 = ZICOND_FN7.
    is_zicond_instr <= '1' when (ENABLE_ZICOND and op = R_OPCODE and funct7 = ZICOND_FN7 and
                            (funct3 = CZERO_EQZ_FN3 or funct3 = CZERO_NEZ_FN3)) else '0';

    -- Zknd/Zkne AES-32: OP opcode, funct3=000, and funct5 (funct7(4 downto 0)) one of the four aes32* codes, gated on ENABLE_ZKN so an OFF build folds this to '0' and the encoding traps.
    -- bs (funct7(6 downto 5), i.e. instr[31:30]) is a decode don't-care: all four byte-select values are legal encodings.
    is_aes_instr <= '1' when (ENABLE_ZKN and op = R_OPCODE and funct3 = AES_FN3 and
                            (funct7(4 downto 0) = AES32ESI_FN5  or funct7(4 downto 0) = AES32ESMI_FN5 or
                             funct7(4 downto 0) = AES32DSI_FN5  or funct7(4 downto 0) = AES32DSMI_FN5)) else '0';

    is_csr_instr <= '1' when (op = SYSTEM_OPCODE and
                              (funct3 = CSRRW_FN3 or funct3 = CSRRS_FN3 or funct3 = CSRRC_FN3 or
                               funct3 = CSRRWI_FN3 or funct3 = CSRRSI_FN3 or funct3 = CSRRCI_FN3)) else '0';

    -- Zknh SHA-256 (unary): OP-IMM, funct3=001, funct7 = SHA256_FN7, rs2-field (imm12[4:0]) in the range 00000 to 00011, gated on ENABLE_ZKN.
    -- Any other rs2-field with this funct7 is a RESERVED encoding and traps.
    is_sha256_instr <= '1' when (ENABLE_ZKN and op = I_ARITH_OPCODE and funct3 = SHA256_FN3 and
                                 funct7 = SHA256_FN7 and
                                 (imm12 = SHA256SUM0_IMM12 or imm12 = SHA256SUM1_IMM12 or
                                  imm12 = SHA256SIG0_IMM12 or imm12 = SHA256SIG1_IMM12)) else '0';

    -- Zknh SHA-512 (binary, RV32 halves): OP opcode, funct3=000, funct7 one of the six sha512* codes, gated on ENABLE_ZKN.
    is_sha512_instr <= '1' when (ENABLE_ZKN and op = R_OPCODE and funct3 = SHA512_FN3 and
                                 (funct7 = SHA512SUM0R_FN7 or funct7 = SHA512SUM1R_FN7 or
                                  funct7 = SHA512SIG0L_FN7 or funct7 = SHA512SIG1L_FN7 or
                                  funct7 = SHA512SIG0H_FN7 or funct7 = SHA512SIG1H_FN7)) else '0';

    -- CSR-address validity map, live regardless of any generic: KNOWN means every CSR csr_unit implements, plus the full hpm ranges (legal read-zero, write-ignore), plus mcountinhibit and mcounteren.
    -- Everything else is an unknown CSR and raises illegal-instruction; the hpm ranges use unsigned compares, and time/timeh (0xC01/0xC81) are deliberately NOT known.
    csr_addr_valid <= '1' when (
        imm12 = CSR_MHARTID   or imm12 = CSR_MISA      or
        -- The rest of the machine-information block, 0xF11-0xF15: required read-only M-mode CSRs, so a read must RETIRE and never trap, while writes trap via the ungated csr_ro_denied.
        -- Their VALUE is all-zeros from csr_unit's catch-all `others` read arm, so anyone adding a read arm above that `others` must know these four ride it.
        -- FOUR EXPLICIT EQUALITIES, not a range: 0xF10 and 0xF16 bracket the block and must keep trapping.
        imm12 = CSR_MVENDORID or imm12 = CSR_MARCHID   or
        imm12 = CSR_MIMPID    or imm12 = CSR_MCONFIGPTR or
        imm12 = CSR_MCYCLE    or imm12 = CSR_MINSTRET  or
        imm12 = CSR_MCYCLEH   or imm12 = CSR_MINSTRETH or
        -- The USER-VIEW counter block admitted here is cycle and instret plus their h-forms ONLY.
        -- time (0xC01) and timeh (0xC81) are DELIBERATELY ABSENT: no real time source is wired to the core, so a read raises illegal-instruction (cause 2) in every build, M-mode and U-mode alike, regardless of mcounteren.TM.
        -- Do NOT re-admit them without a real time source behind them; returning zero is a wrong answer to a legal question that software cannot tell from a stopped clock.
        imm12 = CSR_CYCLE     or imm12 = CSR_INSTRET   or
        imm12 = CSR_CYCLEH    or imm12 = CSR_INSTRETH  or
        imm12 = CSR_MCOUNTINHIBIT or imm12 = CSR_MCOUNTEREN or
        -- Zcmt jvt: a KNOWN CSR only when ENABLE_ZCMT; otherwise a read or write of 0x017 is an unknown CSR and raises illegal-instruction.
        (ENABLE_ZCMT and imm12 = CSR_JVT) or
        -- Zfinx fflags/frm/fcsr: KNOWN CSRs only when ENABLE_ZFINX; otherwise 0x001/0x002/0x003 are unknown CSRs and raise illegal-instruction.
        (ENABLE_ZFINX and (imm12 = CSR_FFLAGS or imm12 = CSR_FRM or imm12 = CSR_FCSR)) or
        -- Standard M-mode trap CSRs plus the custom mtrapctl legacy-select bit: KNOWN CSRs only when ENABLE_TRAPCSR.
        -- Otherwise 0x300/0x310/0x305/0x304/0x344/0x340/0x341/0x342/0x343/0x7C0 are unknown CSRs and raise illegal-instruction.
        (ENABLE_TRAPCSR and (imm12 = CSR_MSTATUS  or imm12 = CSR_MSTATUSH or
                             imm12 = CSR_MTVEC    or imm12 = CSR_MIE      or
                             imm12 = CSR_MIP      or imm12 = CSR_MSCRATCH or
                             imm12 = CSR_MEPC     or imm12 = CSR_MCAUSE   or
                             imm12 = CSR_MTVAL    or imm12 = CSR_MTRAPCTL)) or
        -- Debug-Mode CSRs dcsr/dpc/dscratch0/dscratch1: KNOWN CSRs only when ENABLE_DEBUG, otherwise all four are unknown CSRs and raise illegal-instruction.
        -- FOUR EXPLICIT EQUALITIES, not an imm12(11:4) = 0x7B range, so 0x7AF and 0x7B4 keep trapping; and admission is not access, since dbg_csr_denied below still traps all four outside debug mode.
        (ENABLE_DEBUG and (imm12 = CSR_DCSR      or imm12 = CSR_DPC or
                           imm12 = CSR_DSCRATCH0 or imm12 = CSR_DSCRATCH1)) or
        -- PMP bank pmpcfg0-3 (0x3A0-0x3A3) and pmpaddr0-15 (0x3B0-0x3BF): KNOWN CSRs only when ENABLE_PMP, otherwise all twenty raise illegal-instruction.
        -- RANGE compares are correct HERE because this is the ADDRESS-LEGALITY map, not a write arm; the whole range is admitted regardless of PMP_ENTRIES, and the unimplemented upper half reads WARL zero.
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

    -- ========== U-mode decode gating ==========
    -- ONE gate signal drives every U-mode restriction, and it is statically '0' unless ENABLE_UMODE, since priv_m reads '1' there by the csr_unit contract.
    u_gate <= '1' when (ENABLE_UMODE and priv_m = '0') else '0';

    -- mcounteren gating of the USER-VIEW counters: a U-mode read traps illegal (cause 2) unless the matching mcounteren bit is set.
    --   CY(0)   enables cycle/cycleh          IR(2)   enables instret/instreth
    --   HPM3(3) enables hpmcounter3/3h        HPM4(4) enables hpmcounter4/4h
    -- TM(1) has NO term and enables nothing, since time/timeh are not KNOWN CSRs and csr_addr_valid kills those instructions first; bits 5-31 are WARL 0, so hpmcounter5-31 (0xC05-0xC1F) and their h-forms always trap in U-mode, and the MACHINE views (the 0xB00 and 0x320 ranges) need no term here at all, being caught by the csr_addr(9:8) /= "00" comparator in the SYSTEM arm below.
    ucnt_denied <= '1' when (
        ((imm12 = CSR_CYCLE       or imm12 = CSR_CYCLEH)       and mcounteren_bits(0) = '0') or
        ((imm12 = CSR_INSTRET     or imm12 = CSR_INSTRETH)     and mcounteren_bits(2) = '0') or
        ((imm12 = CSR_HPMCOUNTER3 or imm12 = CSR_HPMCOUNTER3H) and mcounteren_bits(3) = '0') or
        ((imm12 = CSR_HPMCOUNTER4 or imm12 = CSR_HPMCOUNTER4H) and mcounteren_bits(4) = '0') or
        (unsigned(imm12) >= x"C05" and unsigned(imm12) <= x"C1F") or   -- hpmcounter5-31  (mcounteren 5-31 = WARL 0)
        (unsigned(imm12) >= x"C85" and unsigned(imm12) <= x"C9F")      -- hpmcounter5h-31h
    ) else '0';

    -- THE U-mode CSR denial, factored into ONE signal because two consumers must never disagree: valid_funct's illegal-instruction trap, and csr_valid, which is csr_unit's WRITE ENABLE.
    -- Both are load-bearing, since a trapping instruction must leave NO architectural side effect: a U-mode `csrw mtvec` that traps but still commits its write is a full escape.
    -- Statically '0' when ENABLE_UMODE is off, and two denial classes: (a) imm12(9:8) /= "00", one comparator covering every machine (0x3xx/0xBxx/0xFxx) and custom (0x7C0 mtrapctl) CSR, and (b) a user-view counter whose mcounteren enable bit is clear.
    u_csr_denied <= '1' when (u_gate = '1' and is_csr_instr = '1' and
                              (imm12(9 downto 8) /= "00" or ucnt_denied = '1'))
                    else '0';

    -- Zimop mop.r.N / mop.rr.N: SYSTEM opcode, funct3=100 (MOP_FN3), an otherwise unused decode hole, so gated purely on ENABLE_ZIMOP.
    --   fixed bits : funct7(6)=instr31=1, funct7(4:3)=instr29..28="00"
    --   mop.r.N    : funct7(0)=instr25=0 AND imm12(4:2)=instr24..22="111"; index bits {30,27,26,21,20} are don't-care
    --   mop.rr.N   : funct7(0)=instr25=1; bits24..20=rs2, index bits {30,27,26} don't-care
    -- Semantics: rd gets 0, an x0-safe zero write with no memory access, no CSR access and no trap; disabled, the encoding raises illegal-instruction.
    is_zimop_instr <= '1' when (ENABLE_ZIMOP and op = SYSTEM_OPCODE and funct3 = MOP_FN3 and
                                funct7(6) = '1' and funct7(4 downto 3) = "00" and
                                ( (funct7(0) = '0' and imm12(4 downto 2) = "111") or  -- mop.r.N
                                  (funct7(0) = '1') )) else '0';                        -- mop.rr.N

    -- ========== CSR Control Signals ==========
    -- csr_op passes funct3 through for a CSR instruction and reads 000 otherwise.
    csr_op <= funct3 when is_csr_instr = '1' else "000";
    -- csr_valid IS csr_unit's write enable, so every denial must take it down or a trapping CSR instruction still commits its write.
    -- csr_addr_valid, u_csr_denied, csr_ro_denied and dbg_csr_denied all qualify it; that is belt and braces wherever no csr_unit write arm matches the denied address, but load-bearing for any write arm decoded wider than its exact address set, such as the pmpcfg/pmpaddr bank.
    csr_valid <= is_csr_instr and csr_addr_valid
                 and (not u_csr_denied) and (not csr_ro_denied)
                 and (not dbg_csr_denied);

    -- dcsr/dpc/dscratch0/dscratch1 are accessible ONLY in debug mode; from M or U they raise illegal-instruction.
    -- The DENIAL is deliberately wider than csr_addr_valid's four equalities and blocks the whole imm12(11:4) = 0x7B nibble, so admitting a fifth debug CSR cannot forget to deny it; it stops at that nibble because the trigger CSRs at 0x7A0-0x7AF are M-mode-visible (Sdtrig).
    -- UNGATED by ENABLE_DEBUG on purpose: it is purely combinational, changes nothing in an OFF build (csr_addr_valid already rejects 0x7B0-0x7B3 there), and means a mis-set admission gate can never open the CSRs.
    dbg_csr_denied <= '1' when (is_csr_instr = '1' and
                                imm12(11 downto 4) = x"7B" and
                                debug_mode = '0')
                      else '0';

    -- csr[11:10] = "11" marks a CSR address READ-ONLY, and any instruction FORM that would write such a CSR raises illegal-instruction; reads of those addresses are untouched.
    -- ONE COMPARATOR on imm12(11:10), deliberately NOT an enumeration of the CSRs csr_unit happens not to store: misa (0x301), mip (0x344), mstatush (0x310), mcountinhibit (0x320), mhpmevent3-31 and mhpmcounter3-31 all sit BELOW the quadrant, so their writes stay legally write-ignored and must NOT trap.
    -- UNGATED, so it applies in every build: `unimp` (0xC0001073 = `csrrw x0, cycle, x0`) traps here, which is exactly what a reserved encoding must do rather than retire as a silent NOP.
    csr_ro_denied <= '1' when (is_csr_instr = '1' and
                               imm12(11 downto 10) = "11" and
                               (funct3(1 downto 0) = "01" or csr_rs1_zero = '0'))
                     else '0';

    -- ========== RV32A Atomic Operation Signals ==========
    -- Load-Reserved operation
    lr_op <= '1' when (ENABLE_ATOMICS and op = AMO_OPCODE and funct3 = AMO_WIDTH_W and funct5 = LR_FN5) else '0';

    -- Store-Conditional operation
    sc_op <= '1' when (ENABLE_ATOMICS and op = AMO_OPCODE and funct3 = AMO_WIDTH_W and funct5 = SC_FN5) else '0';

    -- Atomic Memory Operation, excluding LR/SC.
    -- Zabha: byte (funct3=000) and halfword (funct3=001) AMOs join the word path when ENABLE_ZABHA; LR/SC stay word-only, since Zabha excludes lr.b/h and sc.b/h.
    -- THE FUNCT5 WHITELIST IS LOAD-BEARING and MUST stay in lockstep with the AMO_OPCODE arm of valid_funct: an encoding illegal there but still raising amo_op takes the trap AND commits the memory write, because trap dispatch freezes pc_en without forcing `wen` and hart_tile's sh_we_lanes carries no FSM-state qualifier.
    amo_op <= '1' when (ENABLE_ATOMICS and op = AMO_OPCODE and
                        (is_std_amo_fn5 = '1' or (ENABLE_ZACAS and funct5 = CAS_FN5)) and
                        (funct3 = AMO_WIDTH_W or
                         (ENABLE_ZABHA and (funct3 = AMO_WIDTH_B or funct3 = AMO_WIDTH_H)))) else '0';

    -- A plain FENCE retires as a nop in vesta; only the hint decodes below change behaviour.
    fence_op <= is_fence;

    -- Zihintpause detect: PAUSE is `fence w,0` (imm12 = 0x010, funct3 = 000), gated by ENABLE_ZIHINT so an OFF build leaves pause_hint statically '0' and the FENCE nop path unchanged.
    -- This NEVER touches valid_opcode or valid_funct: PAUSE is a legal FENCE encoding in both polarities, and the generic gates only the arbiter-yield side effect.
    is_pause <= '1' when (ENABLE_ZIHINT and is_fence = '1' and imm12 = PAUSE_IMM12) else '0';
    pause_hint <= is_pause;

    -- Zicboz decode: the exact cbo.zero encoding (MISC-MEM opcode, funct3=010, imm12=0x004), gated on ENABLE_ZICBOZ so an OFF build leaves cboz_op '0' and cbo.zero traps illegal.
    -- rd and rs1 are not decoded here, since imm12 identifies cbo.zero uniquely; cbo.clean/flush/inval share the funct3 but carry imm12 0x001/0x002/0x000 and stay illegal in both polarities.
    is_cboz <= '1' when (ENABLE_ZICBOZ and op = FENCE_OPCODE and funct3 = CBO_FN3
                         and imm12 = CBOZ_IMM12) else '0';
    cboz_op <= is_cboz;

    -- Recognise the cm.* sentinel: c_dec emits op = ZCM_SENTINEL_OP ONLY for a legal, enabled cm.*, so maindec trusts the sentinel, gates on the generics and lets vesta decode the sub-op and operands.
    -- The sentinel opcode's bits(1:0)="10" can never be produced by a real decompressed instruction or a raw 32-bit word, so this cannot fire on anything c_dec did not synthesise.
    is_zcm <= '1' when ((ENABLE_ZCMP or ENABLE_ZCMT) and op = ZCM_SENTINEL_OP) else '0';
    zcm_op <= is_zcm;

    -- ========== Zfinx single-precision FP decode ==========
    -- rm-field (funct3) legality for the rounding-mode-carrying ops: 000 to 100 are legal, 101 and 110 are illegal, and 111 (dynamic) is legal iff frm is a valid mode.
    -- The op-selector ops (fsgnj*, fmin, fmax, fcmp, fclass) do NOT consult this; their funct3 and rs2 field (imm12(4:0) = instr[24:20]) are checked exactly below.
    fp_rm_ok <= '1' when (funct3 = "000" or funct3 = "001" or funct3 = "010" or
                          funct3 = "011" or funct3 = "100" or
                          (funct3 = FRM_DYN and frm_valid = '1')) else '0';

    -- Single-cycle OP-FP: op-selector funct3, no rounding, retires in EXECUTE.
    -- FCLASS shares funct7 with fmv.x.w, and only rm=001 with rs2=0 (fclass) is legalized, so fmv.x.w (rm=000) stays illegal: Zfinx has no fmv.
    is_fp_single <= '1' when (ENABLE_ZFINX and op = OPFP_OPCODE and (
        (funct7 = FSGNJ_FN7   and (funct3 = "000" or funct3 = "001" or funct3 = "010")) or  -- fsgnj/n/x
        (funct7 = FMINMAX_FN7 and (funct3 = "000" or funct3 = "001")) or                    -- fmin/fmax
        (funct7 = FCMP_FN7    and (funct3 = "000" or funct3 = "001" or funct3 = "010")) or  -- fle/flt/feq
        (funct7 = FCLASS_FN7  and funct3 = "001" and imm12(4 downto 0) = "00000")           -- fclass
    )) else '0';

    -- Multi-cycle OP-FP that rounds, with 2 source registers and no rs3.
    -- fmv.w.x is NOT in this list and stays illegal.
    is_fp_arith_mc <= '1' when (ENABLE_ZFINX and op = OPFP_OPCODE and fp_rm_ok = '1' and (
        funct7 = FADD_FN7 or funct7 = FSUB_FN7 or funct7 = FMUL_FN7 or funct7 = FDIV_FN7 or
        (funct7 = FSQRT_FN7 and imm12(4 downto 0) = FP_RS2_W) or
        (funct7 = FCVTW_FN7 and (imm12(4 downto 0) = FP_RS2_W or imm12(4 downto 0) = FP_RS2_WU)) or
        (funct7 = FCVTS_FN7 and (imm12(4 downto 0) = FP_RS2_W or imm12(4 downto 0) = FP_RS2_WU))
    )) else '0';

    -- FMA family, 3 source registers: fmt = funct7(1:0) must be 00 (single), and rs3 = funct7(6:2) is a don't-care.
    -- These have their own distinct opcodes, 0x43/0x47/0x4B/0x4F.
    is_fp_fma_op <= '1' when (ENABLE_ZFINX and fp_rm_ok = '1' and funct7(1 downto 0) = "00" and
        (op = FMADD_OPCODE or op = FMSUB_OPCODE or op = FNMSUB_OPCODE or op = FNMADD_OPCODE)) else '0';

    -- Export the three FP decode classes to vesta's FSM.
    is_fp_singlecycle <= is_fp_single;
    is_fp_multicycle  <= is_fp_arith_mc;
    is_fp_fma         <= is_fp_fma_op;

    -- ========== Valid Instruction Detection ==========
    -- First legality stage: is the opcode itself one this configuration implements?
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
        ((ENABLE_ZCMP or ENABLE_ZCMT) and op = ZCM_SENTINEL_OP) or  -- Zcmp/Zcmt cm.* sentinel
        -- Zfinx FP opcodes, each ENABLE_ZFINX-gated so that an OFF build keeps the illegal-trap behaviour.
        (ENABLE_ZFINX and op = OPFP_OPCODE)   or  -- OP-FP (0x53)
        (ENABLE_ZFINX and op = FMADD_OPCODE)  or  -- fmadd.s
        (ENABLE_ZFINX and op = FMSUB_OPCODE)  or  -- fmsub.s
        (ENABLE_ZFINX and op = FNMSUB_OPCODE) or  -- fnmsub.s
        (ENABLE_ZFINX and op = FNMADD_OPCODE)     -- fnmadd.s
    ) else '0';

    -- Second legality stage: with the opcode accepted, check funct3/funct7/funct12 for that opcode.
    -- valid_funct defaults to '1' and every arm below only ever narrows it, so an opcode with no encoding constraints needs no arm.
    process(op, funct3, funct7, funct5, imm12, valid_opcode, is_custom_instr, is_mul_div, is_amo_instr, is_zba_instr, is_zbb_r_instr, is_zbb_i_instr, is_zbs_r_instr, is_zbs_i_instr, is_zbc_instr, is_zicond_instr, is_aes_instr, is_wrs_instr, is_csr_instr, is_zimop_instr, csr_addr_valid, is_std_amo_fn5, is_sha256_instr, is_sha512_instr, is_zbkb_new_r_instr, is_zbkb_new_i_instr, is_zbkb_shared_r_instr, is_zbkb_shared_i_instr, is_zbkx_instr, is_fp_single, is_fp_arith_mc, is_fp_fma_op, u_gate, u_csr_denied, csr_ro_denied, status_tw)
    begin
        valid_funct <= '1';
        
        if valid_opcode = '1' then
            case op is
                when R_OPCODE =>
                    if funct7 = MULT_FN7 then
                        -- MUL* is legal only with ENABLE_MUL and DIV*/REM* only with ENABLE_DIV; anything else on MULT_FN7 traps.
                        if not ((ENABLE_MUL and (funct3 = MUL_FN3 or funct3 = MULH_FN3 or
                                                 funct3 = MULHSU_FN3 or funct3 = MULHU_FN3)) or
                                (ENABLE_DIV and (funct3 = DIV_FN3 or funct3 = DIVU_FN3 or
                                                 funct3 = REM_FN3 or funct3 = REMU_FN3))) then
                            valid_funct <= '0';
                        end if;
                    elsif is_zba_instr = '1' then
                        valid_funct <= '1';  -- Zba sh1add/sh2add/sh3add
                    elsif is_zbb_r_instr = '1' then
                        valid_funct <= '1';  -- Zbb R-type (andn/orn/xnor, min/max, rol/ror, zext.h)
                    elsif is_zbs_r_instr = '1' then
                        valid_funct <= '1';  -- Zbs R-type single-bit ops
                    elsif is_zbc_instr = '1' then
                        valid_funct <= '1';  -- Zbc/Zbkc carry-less multiply
                    elsif is_zicond_instr = '1' then
                        valid_funct <= '1';  -- Zicond czero.eqz/czero.nez are valid
                    elsif is_aes_instr = '1' then
                        valid_funct <= '1';  -- Zknd/Zkne aes32{e,d}s[m]i are valid
                    elsif is_sha512_instr = '1' then
                        valid_funct <= '1';  -- Zknh sha512* (enabled) are valid
                    elsif is_zbkb_new_r_instr = '1' then
                        valid_funct <= '1';  -- Zbkb pack/packh
                    elsif is_zbkb_shared_r_instr = '1' then
                        valid_funct <= '1';  -- Zbkb andn/orn/xnor/rol/ror (Zbb off)
                    elsif is_zbkx_instr = '1' then
                        valid_funct <= '1';  -- Zbkx xperm8/xperm4
                    elsif funct7 = "0000000" or funct7 = "0100000" then
                        -- Standard R-type instructions: the two base funct7 values.
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
                        -- Any other R-type funct7 is a reserved encoding.
                        valid_funct <= '0';
                    end if;

                when I_ARITH_OPCODE =>
                    if is_zbb_i_instr = '1' then
                        valid_funct <= '1';  -- Zbb OP-IMM (rori, clz/ctz/cpop, sext/zext, orc.b, rev8)
                    elsif is_zbs_i_instr = '1' then
                        valid_funct <= '1';  -- Zbs OP-IMM single-bit immediates
                    elsif is_zbkb_new_i_instr = '1' then
                        valid_funct <= '1';  -- Zbkb brev8/zip/unzip
                    elsif is_zbkb_shared_i_instr = '1' then
                        valid_funct <= '1';  -- Zbkb rori/rev8 (Zbb off)
                    elsif funct3 = SRL_FN3 then
                        if ENABLE_BITMANIP and funct7 = RORI_FN7 then
                            valid_funct <= '1';
                        elsif funct7(0) = '1' then
                            -- imm12(5) IS shamt[5] and RV32 RESERVES shamt[5] = 1 for the OP-IMM shifts, so `srli/srai x, x, 35` must trap here rather than execute silently as the shamt[4:0] form.
                            -- The tests below decide on funct7(6:5) alone and would admit it; RORI is checked above with funct7(0) = 0, so this cannot shadow it, and every Zbb/Zbs/Zbkb immediate form reaches its own arm earlier still.
                            valid_funct <= '0';
                        elsif (not ENABLE_BITMANIP) and not (funct7 = "0000000" or funct7 = "0100000") then
                            -- Without Zb*, only the exact SRLI/SRAI encodings are legal: RORI and friends must trap rather than alias to SRAI.
                            valid_funct <= '0';
                        elsif not (funct7(6 downto 5) = "00" or funct7(6 downto 5) = "01") then
                            valid_funct <= '0';
                        end if;
                    elsif funct3 = SLL_FN3 then
                        if is_sha256_instr = '1' then
                            valid_funct <= '1';  -- Zknh sha256sig0/sig1/sum0/sum1 (enabled)
                        elsif funct7(0) = '1' and funct7 /= SHA256_FN7 then
                            -- The SLLI half of the same shamt[5] reservation, placed BEFORE the SHA-256 hole so that hole keeps its own explicit refusal.
                            valid_funct <= '0';
                        elsif funct7 = SHA256_FN7 then
                            -- The SHA-256 funct7 hole is legal ONLY as an enabled sha256* op above; with ENABLE_ZKN off or a reserved rs2-field it is illegal.
                            -- Do NOT let the loose funct7(6:5)="00" check below alias it to a valid shift.
                            valid_funct <= '0';
                        elsif (not ENABLE_BITMANIP) and funct7 /= "0000000" then
                            -- Without Zb*, only the exact SLLI encoding is legal: the BSETI/BINVI/CLZ-class encodings must trap.
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
                        -- The three custom Vesta instructions (iret, extinguish, ignite) are PRIVILEGED, since they drive the legacy irq_handler handshake and the sleep state directly, so the whole opcode traps illegal (cause 2) in U-mode.
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
                        -- cbo.zero is legal ONLY when the generic is on.
                        valid_funct <= '1';
                    else
                        -- Everything else on MISC-MEM traps, INCLUDING the always-illegal cbo.clean/flush/inval siblings and cbo.zero itself when ENABLE_ZICBOZ is off.
                        valid_funct <= '0';
                    end if;
                -- SYSTEM instructions (CSR, ECALL, EBREAK)
                when SYSTEM_OPCODE =>
                    if is_csr_instr = '1' then
                        -- A CSR instruction is legal ONLY for a known CSR address; unknown addresses trap.
                        -- Three further denials, all reporting cause 2 so their test order is moot: u_csr_denied (U-mode machine/custom addresses and disabled counter views), csr_ro_denied (a write form aimed at imm12(11:10)="11") and dbg_csr_denied (a 0x7Bx access outside debug mode).
                        -- The last two carry no ENABLE_ term and so apply in EVERY build; all three are shared with the csr_valid write-enable suppression, so the trap and the side-effect block can never disagree.
                        if u_csr_denied = '1' then
                            valid_funct <= '0';
                        elsif csr_ro_denied = '1' then
                            valid_funct <= '0';
                        elsif dbg_csr_denied = '1' then
                            valid_funct <= '0';
                        else
                            valid_funct <= csr_addr_valid;
                        end if;
                    elsif is_zimop_instr = '1' then
                        valid_funct <= '1';  -- Zimop mop.r.N / mop.rr.N (rd gets 0)
                    elsif is_wrs_instr = '1' then
                        valid_funct <= '1';  -- Zawrs wrs.nto/wrs.sto (legal when enabled)
                    elsif ENABLE_TRAPCSR and funct3 = PRIV_FN3 then
                        -- The SYSTEM PRIV arm, where exactly four funct12 values are legal: ECALL (0x000), EBREAK (0x001), WFI (0x105) and MRET (0x302).
                        -- EVERY other funct12 on this arm stays ILLEGAL.
                        if imm12 = ECALL_IMM12 or imm12 = EBREAK_IMM12 then
                            -- ECALL and EBREAK are legal in BOTH privilege modes; that is the point of ECALL from U, which reports cause 8.
                            valid_funct <= '1';
                        elsif imm12 = MRET_IMM12 then
                            -- MRET is M-mode only, raising illegal-instruction in U.
                            if u_gate = '1' then
                                valid_funct <= '0';
                            else
                                valid_funct <= '1';
                            end if;
                        elsif imm12 = WFI_IMM12 then
                            -- WFI is always legal in M, and legal in U iff mstatus.TW = 0; the TW denial is a DECODE illegal-instruction, cause 2.
                            if u_gate = '1' and status_tw = '1' then
                                valid_funct <= '0';
                            else
                                valid_funct <= '1';
                            end if;
                        elsif ENABLE_DEBUG and imm12 = DRET_IMM12 then
                            -- DRET (0x7B2) is a FIFTH legal funct12 on this arm, and ONLY in debug mode; the explicit '0' outside debug mode is written out so the denial reads as deliberate and keyed on the LIVE mode, not on the generic.
                            -- This arm is reachable only because the whole PRIV_FN3 block is gated on ENABLE_TRAPCSR; vesta carries a concurrent assert that debug implies trapCsr for anyone instantiating the core directly.
                            if debug_mode = '1' then
                                valid_funct <= '1';
                            else
                                valid_funct <= '0';
                            end if;
                        else
                            valid_funct <= '0';
                        end if;
                    else
                        valid_funct <= '0';
                    end if;

                -- RV32A, Zabha and Zacas atomics, where decode legality is a funct5 WHITELIST per width:
                --   word (funct3=010)  : the nine standard AMOs plus LR and SC always, plus CAS (amocas.w) only with ENABLE_ZACAS; every other funct5 is RESERVED and traps
                --   byte/half (000/001): only with ENABLE_ZABHA, and only the nine standard AMOs plus CAS (amocas.b/.h needs ZACAS and ZABHA); lr.b/h and sc.b/h stay illegal, as Zabha excludes them
                --   any other width (011, which includes amocas.d, and 1xx) always traps
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

                -- The cm.* sentinel is already fully validated by c_dec, since only a legal, enabled cm.* reaches this opcode, so it is unconditionally legal here.
                -- valid_opcode gates it on the generics, so an OFF build never reaches this arm and the encoding traps as an unknown opcode.
                when ZCM_SENTINEL_OP =>
                    valid_funct <= '1';

                -- Zfinx OP-FP: legal iff the exact funct7/funct3/rs2 encoding decodes to a supported Zfinx op, single- or multi-cycle.
                -- This arm is reached ONLY when ENABLE_ZFINX, since valid_opcode gates it; rm-illegal forms, fmv.w.x, fmv.x.w and reserved encodings all fall through to illegal.
                when OPFP_OPCODE =>
                    if is_fp_single = '1' or is_fp_arith_mc = '1' then
                        valid_funct <= '1';
                    else
                        valid_funct <= '0';
                    end if;

                -- Zfinx FMA opcodes: legal iff fmt=00 (single) and the rm field is legal.
                when FMADD_OPCODE | FMSUB_OPCODE | FNMSUB_OPCODE | FNMADD_OPCODE =>
                    if is_fp_fma_op = '1' then
                        valid_funct <= '1';
                    else
                        valid_funct <= '0';
                    end if;

                -- J, LUI and AUIPC carry no funct3/funct7 fields, so any encoding of an accepted opcode is legal.
                when others =>
                    -- TODO
                    valid_funct <= '1';
            end case;
        else
            -- The opcode itself is not implemented in this configuration.
            valid_funct <= '0';
        end if;
    end process;

    -- ========== Trap Signal Generation ==========
    -- Trap on invalid opcode or invalid function field combination
    trap <= not (valid_opcode and valid_funct);

    -- ========== Custom Vesta Instructions ==========
    -- All three carry the U-mode qualifier because they are SIDE EFFECTS that fire independently of the trap: isr_ret pulses the legacy irq_handler EOI, and sleep_rq/wake_rq set and clear vesta's `sleep_cpu` flop on the free-running clk.
    -- Without it a U-mode `extinguish` would trap AND leave sleep_cpu set, so a later legacy-mode IRQ_REST would return M-mode to SLEEPING: a U-mode denial of service on M.
    isr_ret  <= '1' when (op = CUSTOM_OPCODE and funct3 = IRET_FN3 and funct7 = IRET_FN7  and u_gate = '0') else '0';
    sleep_rq <= '1' when (op = CUSTOM_OPCODE and funct3 = SLP_FN3 and funct7 = SLEEP_FN7 and u_gate = '0') else '0';
    wake_rq  <= '1' when (op = CUSTOM_OPCODE and funct3 = SLP_FN3 and funct7 = WAKE_FN7  and u_gate = '0') else '0';

    -- ========== Standard SYSTEM/PRIV decode outputs (ENABLE_TRAPCSR) ==========
    -- All three are statically '0' when the generic is off, matching the valid_funct arm above that keeps the encodings illegal there.
    -- They are consumed ONLY by vesta's FSM dispatch arms, which additionally qualify on the delivery mode; these signals never feed valid_funct or trap.
    ecall_op  <= '1' when (ENABLE_TRAPCSR and op = SYSTEM_OPCODE and
                           funct3 = PRIV_FN3 and imm12 = ECALL_IMM12)  else '0';
    ebreak_op <= '1' when (ENABLE_TRAPCSR and op = SYSTEM_OPCODE and
                           funct3 = PRIV_FN3 and imm12 = EBREAK_IMM12) else '0';
    -- mret_op carries the U-mode qualifier like wfi_op below, so no consumer can ever see a dispatch strobe for an encoding that trapped in U; it is redundant while every vesta FSM arm checks `trap` first.
    mret_op   <= '1' when (ENABLE_TRAPCSR and op = SYSTEM_OPCODE and
                           funct3 = PRIV_FN3 and imm12 = MRET_IMM12 and
                           u_gate = '0')                               else '0';

    -- Standard WFI, carrying its OWN legality qualifier (M-mode, or TW=0) so the dispatch signal can never be high for an encoding valid_funct just declared illegal.
    -- That is belt and braces: vesta checks `trap` FIRST in every decode arm, so a TW-denied WFI takes the illegal path regardless.
    wfi_op    <= '1' when (ENABLE_TRAPCSR and op = SYSTEM_OPCODE and
                           funct3 = PRIV_FN3 and imm12 = WFI_IMM12 and
                           not (u_gate = '1' and status_tw = '1')) else '0';

    -- DRET, carrying the SAME debug_mode qualifier that valid_funct's arm carries, so the dispatch strobe can never be high for an encoding just declared illegal.
    -- Statically '0' when ENABLE_DEBUG is off, so vesta's DBG_RET dispatch arms constant-fold away.
    dret_op   <= '1' when (ENABLE_DEBUG and op = SYSTEM_OPCODE and
                           funct3 = PRIV_FN3 and imm12 = DRET_IMM12 and
                           debug_mode = '1')                          else '0';

    -- Zawrs decode outputs, both '0' unless the extension is enabled.
    wrs_op  <= is_wrs_instr;
    wrs_sto <= '1' when (is_wrs_instr = '1' and imm12 = WRS_STO_IMM12) else '0';

    -- ========== Register Write Enable ==========
    reg_write <= '1' when op = I_LOAD_OPCODE   else  -- Load instructions
                 '1' when op = R_OPCODE         else  -- R-type instructions (including Zba/Zbb)
                 '1' when op = I_ARITH_OPCODE   else  -- I-type arithmetic (including Zbb)
                 '1' when op = J_OPCODE         else  -- JAL
                 '1' when op = U_AUIPC_OPCODE   else  -- AUIPC
                 '1' when op = U_LUI_OPCODE     else  -- LUI
                 '1' when op = I_JALR_OPCODE    else  -- JALR
                 '1' when (ENABLE_ATOMICS and op = AMO_OPCODE and funct5 /= SC_FN5) else -- All AMO except SC (SC writes conditionally)
                 '1' when (ENABLE_ATOMICS and op = AMO_OPCODE and funct5 = SC_FN5)  else -- SC also writes (success/fail flag)
                 '1' when is_zimop_instr = '1'  else  -- Zimop mop.r/mop.rr write 0 to rd
                 '1' when is_csr_instr = '1'    else  -- CSR read value goes to rd
                 '1' when (is_fp_single = '1' or is_fp_arith_mc = '1' or is_fp_fma_op = '1') else  -- Zfinx: all FP ops write rd
                 '0' when (op = FENCE_OPCODE)        else  -- FENCE instruction
                 '0';  -- No write for stores, branches, custom instructions

    -- ========== Immediate Source Selection ==========
    -- Encoding: 000 I-type, 001 S-type, 010 B-type, 011 J-type, 100 U-type.
    -- AMO instructions use the R-type format and carry no immediate.
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

    -- ========== ALU Source Selection ==========
    -- 0 selects the register operand, 1 selects the immediate; Zba/Zbb R-type ops use registers, and the Zbb I-type pseudo-instructions read rs1 only.
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

    -- ========== Write Enable for Memory Operations ==========
    -- Byte enables from the store type and the address offset, ACTIVE-LOW per lane; SC and AMO operations always work on words.
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

    -- ========== Result Source Selection (3-bit) ==========
    --   000 ALU result          001 Memory data        010 PC+4
    --   011 PC+immediate        100 CSR read value     101 Zimop (rd gets 0)
    --   110 RSRC_FP_SINGLE      111 RSRC_FP_MULTI
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
                  "101" when is_zimop_instr = '1'  else  -- Zimop: an unused mux code, so the result is forced to 0 and rd gets 0
                  "100" when is_csr_instr = '1'    else  -- CSR read value
                  RSRC_FP_SINGLE when is_fp_single = '1' else  -- single-cycle FP (fpu_simple, EXECUTE)
                  RSRC_FP_MULTI  when (is_fp_arith_mc = '1' or is_fp_fma_op = '1') else  -- multi-cycle FP (fpu, FPU_DONE)
                  "001";

    -- ========== Branch Control ==========
    branch <= '1' when op = B_OPCODE else '0';

    -- ========== Jump Control ==========
    jump <= '1' when op = J_OPCODE      else
            '1' when op = I_JALR_OPCODE else
            '0';

    -- ========== JALR Control ==========
    jalr <= '1' when op = I_JALR_OPCODE else '0';

    -- ========== Memory Access Flags ==========
    -- mem_access_instr tells vesta this instruction has a data-phase transaction; data_addr is valid only in the EXECUTE cycle.
    read_data_flag <= '1' when op = I_LOAD_OPCODE else
                      '1' when (op = CUSTOM_OPCODE and funct3 = "000" and funct7 = "0000000") else
                      '1' when (ENABLE_ATOMICS and op = AMO_OPCODE) else  -- All AMO operations read memory
                      '0';

    write_data_flag <= '1' when op = S_OPCODE else 
                       '1' when (op = AMO_OPCODE and (sc_op = '1' or amo_op = '1')) else  -- SC and AMO write
                       '0';

    mem_access_instr <= read_data_flag or write_data_flag;

    -- ========== Division Operation Flag ==========
    div_op <= '1' when (ENABLE_DIV and op = R_OPCODE and funct7 = MULT_FN7 and
                       (funct3 = DIV_FN3 or funct3 = DIVU_FN3 or
                        funct3 = REM_FN3 or funct3 = REMU_FN3)) else '0';

    -- ========== ALU Control Signal Generation (7-bit) ==========
    -- One 7-bit code per ALU operation, allocated so that no two decode rows collide.
    -- The rows are ORDER-SENSITIVE, earlier rows winning, which is how the shared funct7/funct3 encodings (PACK before ZEXT.H, AES before the generic ADD/SUB path) are resolved.
    alu_control <= 
        -- Load and Store operations (ADD for the address calculation)
        "0000000" when op = I_LOAD_OPCODE else
        "0000000" when op = S_OPCODE else
        
        -- Custom instructions
        "0000000" when op = CUSTOM_OPCODE else
        
        -- RV32 Zba instructions (shift-and-add)
        "0011000" when (op = R_OPCODE and funct7 = ZBA_FN7 and funct3 = SH1ADD_FN3) else  -- SH1ADD
        "0011001" when (op = R_OPCODE and funct7 = ZBA_FN7 and funct3 = SH2ADD_FN3) else  -- SH2ADD
        "0011010" when (op = R_OPCODE and funct7 = ZBA_FN7 and funct3 = SH3ADD_FN3) else  -- SH3ADD

        -- Zbkb crypto bit-manip (pack/packh R-type; brev8/zip/unzip OP-IMM), every row ENABLE_ZBKB-gated so the rows vanish under constant propagation in an OFF build.
        -- PACK precedes the ZEXT.H row below, so the shared funct7/funct3 decodes to PACK when Zbkb is on and falls through to ZEXT.H when it is off.
        "0110101" when (op = R_OPCODE and funct7 = PACK_FN7 and funct3 = PACK_FN3 and ENABLE_ZBKB) else   -- PACK
        "0110110" when (op = R_OPCODE and funct7 = PACK_FN7 and funct3 = PACKH_FN3 and ENABLE_ZBKB) else  -- PACKH
        "0110111" when (op = I_ARITH_OPCODE and funct3 = "101" and imm12 = BREV8_IMM12 and ENABLE_ZBKB) else -- BREV8
        "0111000" when (op = I_ARITH_OPCODE and funct3 = "001" and imm12 = ZIP_IMM12   and ENABLE_ZBKB) else -- ZIP
        "0111001" when (op = I_ARITH_OPCODE and funct3 = "101" and imm12 = UNZIP_IMM12 and ENABLE_ZBKB) else -- UNZIP
        -- Zbkx crossbar permute (ENABLE_ZBKX-gated)
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
        "0101010" when (op = I_ARITH_OPCODE and funct3 = "101" and imm12 = ORC_B_IMM12) else  -- ORC.B (TODO: Edited)
        "0101011" when (op = I_ARITH_OPCODE and funct3 = "101" and imm12 = REV8_IMM12) else   -- REV8

        -- RV32 Zknh SHA-256 sigma/sum: is_sha256_instr already pins ENABLE_ZKN, funct3=001, funct7 = SHA256_FN7 and the exact rs2-field, so these take priority over the generic SLLI arm below.
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

        -- RV32 Zknd/Zkne AES-32: funct5 = funct7(4 downto 0), while bs = funct7(6:5) is a SEPARATE ALU input wired from instr[31:30] in the datapath and is NOT part of alu_control.
        -- ENABLE_ZKN-gated, and placed BEFORE the generic R-type funct3=000 ADD/SUB path, where funct7(5)=bs(1) would otherwise alias an aes32*i with bs>=2 onto SUB.
        "0111100" when (ENABLE_ZKN and op = R_OPCODE and funct3 = AES_FN3 and funct7(4 downto 0) = AES32ESI_FN5)  else -- aes32esi  (0x3C)
        "0111101" when (ENABLE_ZKN and op = R_OPCODE and funct3 = AES_FN3 and funct7(4 downto 0) = AES32ESMI_FN5) else -- aes32esmi (0x3D)
        "0111110" when (ENABLE_ZKN and op = R_OPCODE and funct3 = AES_FN3 and funct7(4 downto 0) = AES32DSI_FN5)  else -- aes32dsi  (0x3E)
        "0111111" when (ENABLE_ZKN and op = R_OPCODE and funct3 = AES_FN3 and funct7(4 downto 0) = AES32DSMI_FN5) else -- aes32dsmi (0x3F)
        -- RV32 Zknh SHA-512 sigma/sum halves: is_sha512_instr pins ENABLE_ZKN and funct3=000, and funct7 uniquely selects the op.
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
        "0001010" when (op = AMO_OPCODE and ENABLE_ZACAS and funct5 = CAS_FN5) else  -- Zacas amocas.w/.b/.h: pass B (rs2 swap value) to the AMO write path
        
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

