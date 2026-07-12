library IEEE;
use IEEE.STD_LOGIC_1164.all;
use work.constants.all;

entity maindec is
    port (
        resetn           : in  STD_LOGIC;
        op               : in  STD_LOGIC_VECTOR(6 downto 0);
        funct3           : in  STD_LOGIC_VECTOR(2 downto 0);
        funct7           : in  STD_LOGIC_VECTOR(6 downto 0);
        mask             : in  STD_LOGIC_VECTOR(1 downto 0);
        imm12            : in  STD_LOGIC_VECTOR(11 downto 0); 
        
        -- Control outputs
        result_src       : out STD_LOGIC_VECTOR(2 downto 0);
        WEN              : out STD_LOGIC_VECTOR(3 downto 0);
        branch           : out STD_LOGIC;
        ALU_src          : out STD_LOGIC;
        div_op           : out STD_LOGIC;
        reg_write        : out STD_LOGIC;
        jump             : out STD_LOGIC;
        jalr             : out STD_LOGIC;
        imm_src          : out STD_LOGIC_VECTOR(2 downto 0);
        alu_control      : out STD_LOGIC_VECTOR(5 downto 0);  --  Now 6 bits
        mem_access_instr : out STD_LOGIC;
        
        -- Custom instruction outputs
        isr_ret          : out STD_LOGIC;
        sleep_rq         : out STD_LOGIC;
        wake_rq          : out STD_LOGIC;
        
        -- RV32A atomic operation signals
        amo_op           : out STD_LOGIC;
        lr_op            : out STD_LOGIC;
        sc_op            : out STD_LOGIC;
        fence_op         : out STD_LOGIC;

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
    signal is_csr_instr    : STD_LOGIC;


begin

    -- ==========================================
    -- Helper Signals
    -- ==========================================
    
    is_mul_div <= '1' when (op = R_OPCODE and funct7 = MULT_FN7) else '0';
    is_custom_instr <= '1' when (op = CUSTOM_OPCODE) else '0';
    is_amo_instr <= '1' when (op = AMO_OPCODE) else '0';
    is_fence <= '1' when (op = FENCE_OPCODE and funct3 = FENCE_FN3) else '0';
    funct5 <= funct7(6 downto 2);
    rtype_sub <= funct7(5) and op(5);  -- TRUE for R-type subtract


    is_zba_instr <= '1' when (op = R_OPCODE and funct7 = ZBA_FN7 and
                              (funct3 = SH1ADD_FN3 or funct3 = SH2ADD_FN3 or funct3 = SH3ADD_FN3)) else '0';


    is_zbb_r_instr <= '1' when (op = R_OPCODE and (
        -- ANDN, ORN, XNOR
        (funct7 = ANDN_FN7 and (funct3 = "111" or funct3 = "110" or funct3 = "100")) or
        -- MIN, MINU, MAX, MAXU
        (funct7 = MIN_FN7 and (funct3 = "100" or funct3 = "101" or funct3 = "110" or funct3 = "111")) or
        -- ROL, ROR
        (funct7 = ROL_FN7 and (funct3 = "001" or funct3 = "101")) or
        -- ZEXT.H 
        (funct7 = ZEXT_FN7 and funct3 = "100")
    )) else '0';


    is_zbb_i_instr <= '1' when (op = I_ARITH_OPCODE and (
        -- RORI 
        (funct3 = "101" and funct7 = RORI_FN7) or
        -- CLZ, CTZ, CPOP, SEXT.B, SEXT.H, ORC.B, REV8 
        (funct3 = "001" and (imm12 = CLZ_IMM12 or imm12 = CTZ_IMM12 or imm12 = CPOP_IMM12 or
                             imm12 = SEXT_B_IMM12 or imm12 = SEXT_H_IMM12 or 
                             imm12 = ORC_B_IMM12 or imm12 = REV8_IMM12)) or
        -- ZEXT.H via ANDI special encoding
        (funct3 = "100" and imm12 = ZEXT_H_IMM12)
    )) else '0';


    is_zbs_r_instr <= '1' when (op = R_OPCODE and (
        -- BCLR, BEXT (same funct7, different funct3)
        (funct7 = BCLR_FN7 and (funct3 = "001" or funct3 = "101")) or
        -- BINV
        (funct7 = BINV_FN7 and funct3 = "001") or
        -- BSET
        (funct7 = BSET_FN7 and funct3 = "001")
    )) else '0';

    is_zbs_i_instr <= '1' when (op = I_ARITH_OPCODE and (
        -- BCLRI, BEXTI (same funct7, different funct3)
        (funct3 = "001" and funct7 = BCLRI_FN7) or
        (funct3 = "101" and funct7 = BEXTI_FN7) or
        -- BINVI
        (funct3 = "001" and funct7 = BINVI_FN7 and funct7(6) = '0') or
        -- BSETI
        (funct3 = "001" and funct7 = BSETI_FN7 and funct7(6) = '0')
    )) else '0';

    is_zbc_instr <= '1' when (op = R_OPCODE and funct7 = CLMUL_FN7 and 
                            (funct3 = CLMUL_FN3 or funct3 = CLMULH_FN3 or funct3 = CLMULR_FN3)) else '0';

    is_csr_instr <= '1' when (op = SYSTEM_OPCODE and 
                              (funct3 = CSRRW_FN3 or funct3 = CSRRS_FN3 or funct3 = CSRRC_FN3 or
                               funct3 = CSRRWI_FN3 or funct3 = CSRRSI_FN3 or funct3 = CSRRCI_FN3)) else '0';

    -- ==========================================
    -- RV32ZISCR CSR Control Signals
    -- ==========================================
    csr_op <= funct3 when is_csr_instr = '1' else "000";
    csr_valid <= is_csr_instr;

    -- ==========================================
    -- RV32A Atomic Operation Signals
    -- ==========================================
    -- Load-Reserved operation
    lr_op <= '1' when (op = AMO_OPCODE and funct3 = AMO_WIDTH_W and funct5 = LR_FN5) else '0';
    
    -- Store-Conditional operation
    sc_op <= '1' when (op = AMO_OPCODE and funct3 = AMO_WIDTH_W and funct5 = SC_FN5) else '0';
    
    -- Atomic Memory Operation (excluding LR/SC)
    amo_op <= '1' when (op = AMO_OPCODE and funct3 = AMO_WIDTH_W and 
                        funct5 /= LR_FN5 and funct5 /= SC_FN5) else '0';

    fence_op <= is_fence;

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
        op = AMO_OPCODE      or  -- RV32A Atomic operations
        op = CUSTOM_OPCODE   or  -- Custom Vesta instructions
        op = FENCE_OPCODE    or  -- FENCE instruction
        op = SYSTEM_OPCODE     -- SYSTEM instruction
    ) else '0';

    process(op, funct3, funct7, funct5, imm12, valid_opcode, is_custom_instr, is_mul_div, is_amo_instr, is_zba_instr, is_zbb_r_instr, is_zbb_i_instr, is_zbs_r_instr, is_zbs_i_instr, is_zbc_instr, is_csr_instr)
    begin
        valid_funct <= '1';
        
        if valid_opcode = '1' then
            case op is
                when R_OPCODE =>
                    if funct7 = MULT_FN7 then
                        if not (funct3 = MUL_FN3 or funct3 = MULH_FN3 or 
                               funct3 = MULHSU_FN3 or funct3 = MULHU_FN3 or
                               funct3 = DIV_FN3 or funct3 = DIVU_FN3 or 
                               funct3 = REM_FN3 or funct3 = REMU_FN3) then
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
                    elsif funct3 = SRL_FN3 then
                        if funct7 = RORI_FN7 then
                            valid_funct <= '1';
                        elsif not (funct7(6 downto 5) = "00" or funct7(6 downto 5) = "01") then
                            valid_funct <= '0';
                        end if;
                    elsif funct3 = SLL_FN3 then
                        if funct7(6 downto 5) /= "00" and is_zbb_i_instr = '0' and is_zbs_i_instr = '0' then
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
                -- FENCE instruction
                when FENCE_OPCODE =>
                    if not (funct3 = FENCE_FN3 or funct3 = FENCE_I_FN3) then
                        valid_funct <= '0';
                    end if;
                -- SYSTEM instructions (CSR, ECALL, EBREAK)
                when SYSTEM_OPCODE =>
                    if is_csr_instr = '1' then
                        valid_funct <= '1';  -- All CSR instructions are valid
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
                 '1' when (op = AMO_OPCODE and funct5 /= SC_FN5) else -- All AMO except SC (SC writes conditionally)
                 '1' when (op = AMO_OPCODE and funct5 = SC_FN5)  else -- SC also writes (success/fail flag)
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
                      '1' when (op = AMO_OPCODE) else  -- All AMO operations read memory
                      '0';

    write_data_flag <= '1' when op = S_OPCODE else 
                       '1' when (op = AMO_OPCODE and (sc_op = '1' or amo_op = '1')) else  -- SC and AMO write
                       '0';

    mem_access_instr <= read_data_flag or write_data_flag;

    -- ==========================================
    -- Division Operation Flag
    -- ==========================================
    div_op <= '1' when (op = R_OPCODE and funct7 = MULT_FN7 and 
                       (funct3 = DIV_FN3 or funct3 = DIVU_FN3 or 
                        funct3 = REM_FN3 or funct3 = REMU_FN3)) else '0';

    -- ==========================================
    -- ALU Control Signal Generation (6-bit)
    -- ==========================================
    -- Clean 6-bit encoding with no conflicts
    alu_control <= 
        -- Load and Store operations (ADD for address calculation)
        "000000" when op = I_LOAD_OPCODE else
        "000000" when op = S_OPCODE else
        
        -- Custom instructions
        "000000" when op = CUSTOM_OPCODE else
        
        -- RV32 Zba instructions (shift-and-add)
        "011000" when (op = R_OPCODE and funct7 = ZBA_FN7 and funct3 = SH1ADD_FN3) else  -- SH1ADD
        "011001" when (op = R_OPCODE and funct7 = ZBA_FN7 and funct3 = SH2ADD_FN3) else  -- SH2ADD
        "011010" when (op = R_OPCODE and funct7 = ZBA_FN7 and funct3 = SH3ADD_FN3) else  -- SH3ADD
        
        -- RV32 Zbb R-type instructions
        "011011" when (op = R_OPCODE and funct7 = ANDN_FN7 and funct3 = "111") else     -- ANDN
        "011100" when (op = R_OPCODE and funct7 = ORN_FN7 and funct3 = "110") else      -- ORN
        "011101" when (op = R_OPCODE and funct7 = XNOR_FN7 and funct3 = "100") else     -- XNOR
        "011110" when (op = R_OPCODE and funct7 = MIN_FN7 and funct3 = "100") else      -- MIN
        "011111" when (op = R_OPCODE and funct7 = MIN_FN7 and funct3 = "101") else      -- MINU
        "100000" when (op = R_OPCODE and funct7 = MIN_FN7 and funct3 = "110") else      -- MAX
        "100001" when (op = R_OPCODE and funct7 = MIN_FN7 and funct3 = "111") else      -- MAXU
        "100010" when (op = R_OPCODE and funct7 = ROL_FN7 and funct3 = "001") else      -- ROL
        "100011" when (op = R_OPCODE and funct7 = ROR_FN7 and funct3 = "101") else      -- ROR
        "101001" when (op = R_OPCODE and funct7 = ZEXT_FN7 and funct3 = "100") else     -- ZEXT.H (R-type encoding)
        
        -- RV32 Zbb I-type instructions
        "100011" when (op = I_ARITH_OPCODE and funct3 = "101" and funct7 = RORI_FN7) else  -- RORI (reuse ROR)
        "100100" when (op = I_ARITH_OPCODE and funct3 = "001" and imm12 = CLZ_IMM12) else  -- CLZ
        "100101" when (op = I_ARITH_OPCODE and funct3 = "001" and imm12 = CTZ_IMM12) else  -- CTZ
        "100110" when (op = I_ARITH_OPCODE and funct3 = "001" and imm12 = CPOP_IMM12) else -- CPOP
        "100111" when (op = I_ARITH_OPCODE and funct3 = "001" and imm12 = SEXT_B_IMM12) else -- SEXT.B
        "101000" when (op = I_ARITH_OPCODE and funct3 = "001" and imm12 = SEXT_H_IMM12) else -- SEXT.H
        "101001" when (op = I_ARITH_OPCODE and funct3 = "100" and imm12 = ZEXT_H_IMM12) else -- ZEXT.H (I-type)
        "101010" when (op = I_ARITH_OPCODE and funct3 = "101" and imm12 = ORC_B_IMM12) else  -- ORC.B -- TODO: Edited
        "101011" when (op = I_ARITH_OPCODE and funct3 = "101" and imm12 = REV8_IMM12) else   -- REV8

        -- RV32 Zbs R-type instructions (Single-bit operations)
        "101100" when (op = R_OPCODE and funct7 = BCLR_FN7 and funct3 = "001") else   -- BCLR
        "101101" when (op = R_OPCODE and funct7 = BEXT_FN7 and funct3 = "101") else   -- BEXT
        "101110" when (op = R_OPCODE and funct7 = BINV_FN7 and funct3 = "001") else   -- BINV
        "101111" when (op = R_OPCODE and funct7 = BSET_FN7 and funct3 = "001") else   -- BSET
        
        -- RV32 Zbs I-type instructions (Single-bit immediate operations)
        "101100" when (op = I_ARITH_OPCODE and funct3 = "001" and funct7 = BCLRI_FN7 and funct7(6) = '0') else  -- BCLRI
        "101101" when (op = I_ARITH_OPCODE and funct3 = "101" and funct7 = BEXTI_FN7 and funct7(6) = '0') else  -- BEXTI
        "101110" when (op = I_ARITH_OPCODE and funct3 = "001" and funct7 = BINVI_FN7 and funct7(6) = '0') else  -- BINVI
        "101111" when (op = I_ARITH_OPCODE and funct3 = "001" and funct7 = BSETI_FN7 and funct7(6) = '0') else  -- BSETI

        -- RV32 Zbc instructions (Carry-less Multiplication)
        "110000" when (op = R_OPCODE and funct7 = CLMUL_FN7 and funct3 = CLMUL_FN3) else   -- CLMUL
        "110001" when (op = R_OPCODE and funct7 = CLMULH_FN7 and funct3 = CLMULH_FN3) else -- CLMULH
        "110010" when (op = R_OPCODE and funct7 = CLMULR_FN7 and funct3 = CLMULR_FN3) else -- CLMULR
        
        
        -- RV32A Atomic operations
        "000000" when (op = AMO_OPCODE and (lr_op = '1' or sc_op = '1')) else  -- LR/SC use address directly
        "000000" when (op = AMO_OPCODE and funct5 = AMOADD_FN5)  else  -- AMOADD uses ADD
        "000100" when (op = AMO_OPCODE and funct5 = AMOXOR_FN5)  else  -- AMOXOR uses XOR
        "000010" when (op = AMO_OPCODE and funct5 = AMOAND_FN5)  else  -- AMOAND uses AND
        "000011" when (op = AMO_OPCODE and funct5 = AMOOR_FN5)   else  -- AMOOR uses OR
        "001010" when (op = AMO_OPCODE and funct5 = AMOSWAP_FN5) else  -- AMOSWAP (pass through B/rs2)
        "010100" when (op = AMO_OPCODE and funct5 = AMOMIN_FN5)  else  -- AMOMIN (signed MIN)
        "010101" when (op = AMO_OPCODE and funct5 = AMOMAX_FN5)  else  -- AMOMAX (signed MAX)
        "010110" when (op = AMO_OPCODE and funct5 = AMOMINU_FN5) else  -- AMOMINU (unsigned MIN)
        "010111" when (op = AMO_OPCODE and funct5 = AMOMAXU_FN5) else  -- AMOMAXU (unsigned MAX)
        
        -- R-type M-extension operations
        "001100" when (is_mul_div = '1' and funct3 = MUL_FN3)    else  -- MUL
        "001101" when (is_mul_div = '1' and funct3 = MULH_FN3)   else  -- MULH
        "001111" when (is_mul_div = '1' and funct3 = MULHSU_FN3) else  -- MULHSU
        "001110" when (is_mul_div = '1' and funct3 = MULHU_FN3)  else  -- MULHU
        "010000" when (is_mul_div = '1' and funct3 = DIV_FN3)    else  -- DIV
        "010001" when (is_mul_div = '1' and funct3 = DIVU_FN3)   else  -- DIVU
        "010010" when (is_mul_div = '1' and funct3 = REM_FN3)    else  -- REM
        "010011" when (is_mul_div = '1' and funct3 = REMU_FN3)   else  -- REMU
        
        -- R-type standard ALU operations
        "000000" when (op = R_OPCODE and funct3 = ADD_FN3 and rtype_sub = '0')  else  -- ADD
        "000001" when (op = R_OPCODE and funct3 = ADD_FN3 and rtype_sub = '1')  else  -- SUB
        "000110" when (op = R_OPCODE and funct3 = SLL_FN3)                      else  -- SLL
        "000101" when (op = R_OPCODE and funct3 = SLT_FN3)                      else  -- SLT
        "001001" when (op = R_OPCODE and funct3 = SLTU_FN3)                     else  -- SLTU
        "000100" when (op = R_OPCODE and funct3 = XOR_FN3)                      else  -- XOR
        "001000" when (op = R_OPCODE and funct3 = SRL_FN3 and funct7(5) = '1')  else  -- SRA
        "000111" when (op = R_OPCODE and funct3 = SRL_FN3 and funct7(5) = '0')  else  -- SRL
        "000011" when (op = R_OPCODE and funct3 = OR_FN3)                       else  -- OR
        "000010" when (op = R_OPCODE and funct3 = AND_FN3)                      else  -- AND
        
        -- Branch operations
        "000001" when (op = B_OPCODE and funct3(2 downto 1) = BEQ_TOP_FN3)    else  -- BEQ/BNE
        "000101" when (op = B_OPCODE and funct3(2 downto 1) = BCOMP_TOP_FN3)  else  -- BLT/BGE
        "001001" when (op = B_OPCODE and funct3(2 downto 1) = BCOMPU_TOP_FN3) else  -- BLTU/BGEU
        
        -- I-type arithmetic operations
        "000000" when (op = I_ARITH_OPCODE and funct3 = ADD_FN3)                      else  -- ADDI
        "000110" when (op = I_ARITH_OPCODE and funct3 = SLL_FN3)                      else  -- SLLI
        "000101" when (op = I_ARITH_OPCODE and funct3 = SLT_FN3)                      else  -- SLTI
        "001001" when (op = I_ARITH_OPCODE and funct3 = SLTU_FN3)                     else  -- SLTIU
        "000100" when (op = I_ARITH_OPCODE and funct3 = XOR_FN3)                      else  -- XORI
        "001000" when (op = I_ARITH_OPCODE and funct3 = SRL_FN3 and funct7(5) = '1')  else  -- SRAI
        "000111" when (op = I_ARITH_OPCODE and funct3 = SRL_FN3 and funct7(5) = '0')  else  -- SRLI
        "000011" when (op = I_ARITH_OPCODE and funct3 = OR_FN3)                       else  -- ORI
        "000010" when (op = I_ARITH_OPCODE and funct3 = AND_FN3)                      else  -- ANDI
        
        -- Jump operations
        "000000" when op = J_OPCODE else  -- JAL
        
        -- AUIPC (ADD PC + immediate)
        "000000" when op = U_AUIPC_OPCODE else
        
        -- LUI (pass immediate through)
        "001010" when op = U_LUI_OPCODE else
        
        -- JALR (ADD for address calculation)
        "000000" when op = I_JALR_OPCODE else
        
        -- Default
        "000000";

end behave;

