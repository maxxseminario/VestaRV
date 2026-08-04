library IEEE;
use IEEE.std_logic_1164.all;
use work.constants.all;

entity controller is
    generic (
        -- Core ISA feature switches — passed straight through to maindec.
        ENABLE_MUL      : boolean := true;
        ENABLE_DIV      : boolean := true;
        ENABLE_ATOMICS  : boolean := true;
        ENABLE_BITMANIP : boolean := true;
        -- X0 scaffolding: passed straight through to maindec (default false)
        ENABLE_ZICOND   : boolean := false;
        ENABLE_ZIMOP    : boolean := false;
        ENABLE_ZIHINT   : boolean := false;
        ENABLE_ZAWRS    : boolean := false;
        ENABLE_ZABHA    : boolean := false;
        ENABLE_ZACAS    : boolean := false;
        ENABLE_ZICBOZ   : boolean := false;  -- X3 (Zicboz cbo.zero)
        ENABLE_ZCMP     : boolean := false;  -- X3 (Zcmp push/pop + moves)
        ENABLE_ZCMT     : boolean := false;  -- X3 (Zcmt table jump)
        ENABLE_ZBKB     : boolean := false;
        ENABLE_ZBKC     : boolean := false;
        ENABLE_ZBKX     : boolean := false;
        ENABLE_ZKN      : boolean := false;
        ENABLE_ZFINX    : boolean := false;
        -- P0 privileged-architecture scaffolding: passed straight through to
        -- maindec (default false; no decode consumes them yet)
        ENABLE_TRAPCSR  : boolean := false;  -- P1 (trap CSRs + MRET/ECALL/EBREAK/WFI)
        ENABLE_UMODE    : boolean := false;  -- P2 (U-mode privileged-access gating)
        ENABLE_PMP      : boolean := false   -- P3 (PMP/Smpmp)
    );
    port(
        -- ==========================================
        -- System Control
        -- ==========================================
        resetn           : in  std_logic;
        
        -- ==========================================
        -- Instruction Fields
        -- ==========================================
        op               : in  std_logic_vector(6 downto 0);   -- Opcode field
        funct3           : in  std_logic_vector(2 downto 0);   -- Function field (3-bit)
        funct7           : in  std_logic_vector(6 downto 0);   -- Function field (7-bit)
        imm12            : in  std_logic_vector(11 downto 0);  -- Immediate field (12-bit)
        mask             : in  std_logic_vector(1 downto 0);   -- Address alignment for load/store
        
        -- ==========================================
        -- ALU Status Input
        -- ==========================================
        Zero             : in  std_logic;                      -- ALU zero flag for branches
        
        -- ==========================================
        -- Datapath Control Outputs
        -- ==========================================
        result_src       : out std_logic_vector(2 downto 0);   -- Result source mux control
        WEN              : out std_logic_vector(XLEN_BYTES-1 downto 0);   -- Memory write enable (byte enables)
        pc_src           : out std_logic;                      -- PC source selection (sequential/branch)
        ALU_src          : out std_logic;                      -- ALU source B selection
        div_op           : out std_logic;                      -- Division operation flag
        reg_write        : out std_logic;                      -- Register file write enable
        jump             : out std_logic;                      -- Jump instruction indicator
        jalr             : out std_logic;                      -- JALR instruction indicator
        imm_src          : out std_logic_vector(2 downto 0);   -- Immediate type selector
        alu_control      : out std_logic_vector(6 downto 0);   -- ALU operation selector
        mem_access_instr : out std_logic;                      -- Memory access instruction flag
        
        -- ==========================================
        -- Custom Instruction Outputs
        -- ==========================================
        sleep_rq         : out std_logic;                      -- Sleep request
        wake_rq          : out std_logic;                      -- Wake request
        wrs_op           : out std_logic;                      -- X1 Zawrs: wrs.nto/wrs.sto
        wrs_sto          : out std_logic;                      -- X1 Zawrs: timeout variant
        isr_ret          : out std_logic;                      -- ISR return instruction

        -- P1 standard SYSTEM/PRIV decode (all statically '0' unless ENABLE_TRAPCSR)
        ecall_op         : out std_logic;                      -- ECALL  (SYSTEM f3=000 funct12=0x000)
        ebreak_op        : out std_logic;                      -- EBREAK (SYSTEM f3=000 funct12=0x001)
        mret_op          : out std_logic;                      -- MRET   (SYSTEM f3=000 funct12=0x302)
        wfi_op           : out std_logic;                      -- P2 WFI (SYSTEM f3=000 funct12=0x105)

        -- P2 U-mode decode inputs, straight through to maindec (inert defaults:
        -- M-mode / TW=0 / no counter enables — an ENABLE_UMODE=false build and
        -- any instantiation that leaves them unconnected see today's behaviour)
        priv_m           : in  std_logic := '1';                        -- '1'=M, '0'=U
        status_tw        : in  std_logic := '0';                        -- mstatus.TW
        mcounteren_bits  : in  std_logic_vector(4 downto 0) := "00000"; -- {HPM4,HPM3,IR,TM,CY}

        -- F10 (fix pass W4): the CSR instruction's rs1/uimm FIELD is zero, i.e.
        -- this is a read-only instruction form. Straight through to maindec,
        -- where it qualifies the read-only-CSR illegal-instruction trap. That
        -- trap is UNGATED -- it applies in EVERY build, not just knobs-on ones
        -- -- so this port is load-bearing in the shipping configuration.
        -- Default '1' (= read-only form) is a FAIL-SAFE, not an identity: an
        -- unconnected instantiation traps nothing, rather than trapping every
        -- read of a read-only CSR. It does not preserve pre-fix behaviour.
        csr_rs1_zero     : in  std_logic := '1';

        -- F-BV1 (K5): the R-type rs2 FIELD is zero. Straight through to
        -- maindec, where it qualifies the Zbb ZEXT.H decode row -- `zext.h
        -- rd,rs1` IS the rs2=x0 point of Zbkb `pack rd,rs1,rs2`, and without
        -- this bit the whole pack space aliased onto zext.h on every Zbkb-off
        -- build. Default '0' (= NOT zero) is a fail-safe: an unconnected
        -- instantiation makes zext.h illegal (loud) rather than silently
        -- reinstating the alias. It does not preserve pre-fix behaviour.
        rs2_zero         : in  std_logic := '0';

        -- ==========================================
        -- Atomic Memory Operation Outputs
        -- ==========================================
        amo_op           : out std_logic;                      -- Atomic memory operation indicator
        lr_op            : out std_logic;                      -- Load-reserved operation indicator
        sc_op            : out std_logic;                      -- Store-conditional operation indicator
        fence_op         : out std_logic;                      -- FENCE instruction indicator
        cboz_op          : out std_logic;                      -- X3 Zicboz: cbo.zero block-zero
        zcm_op           : out std_logic;                      -- X3 Zcmp/Zcmt: cm.* sequencer trigger
        pause_hint       : out std_logic;                      -- X1 Zihintpause: exact PAUSE hint (fence w,0)

        -- ==========================================
        -- CSR instruction outputs
        -- ==========================================
        csr_op           : out STD_LOGIC_VECTOR(2 downto 0);
        csr_valid        : out std_logic;

        -- ==========================================
        -- X4 Zfinx FP decode outputs / input
        -- ==========================================
        is_fp_singlecycle : out std_logic;                     -- single-cycle FP (EXECUTE retire via fpu_simple)
        is_fp_multicycle  : out std_logic;                     -- multi-cycle FP (-> FPU_WAIT)
        is_fp_fma         : out std_logic;                     -- FMA (-> FPU_FETCH3)
        frm_valid         : in  std_logic := '1';              -- current frm validity (dynamic-rm legality)

        -- ==========================================
        -- Exception Handling
        -- ==========================================
        trap             : out std_logic                       -- Invalid instruction trap
    );
end controller;

architecture struct of controller is

    -- ==========================================
    -- Component Declarations
    -- ==========================================
    
    -- Main instruction decoder
    component maindec
        generic (
            ENABLE_MUL      : boolean := true;
            ENABLE_DIV      : boolean := true;
            ENABLE_ATOMICS  : boolean := true;
            ENABLE_BITMANIP : boolean := true;
            -- X0 scaffolding (default false)
            ENABLE_ZICOND   : boolean := false;
            ENABLE_ZIMOP    : boolean := false;
            ENABLE_ZIHINT   : boolean := false;
            ENABLE_ZAWRS    : boolean := false;
            ENABLE_ZABHA    : boolean := false;
            ENABLE_ZACAS    : boolean := false;
            ENABLE_ZICBOZ   : boolean := false;
            ENABLE_ZCMP     : boolean := false;
            ENABLE_ZCMT     : boolean := false;
            ENABLE_ZBKB     : boolean := false;
            ENABLE_ZBKC     : boolean := false;
            ENABLE_ZBKX     : boolean := false;
            ENABLE_ZKN      : boolean := false;
            ENABLE_ZFINX    : boolean := false;
            -- P0 privileged-architecture scaffolding (default false)
            ENABLE_TRAPCSR  : boolean := false;
            ENABLE_UMODE    : boolean := false;
            ENABLE_PMP      : boolean := false
        );
        port(
            resetn           : in  std_logic;
            op               : in  std_logic_vector(6 downto 0);
            funct3           : in  std_logic_vector(2 downto 0);
            funct7           : in  std_logic_vector(6 downto 0);
            mask             : in  std_logic_vector(1 downto 0);
            imm12            : in  STD_LOGIC_VECTOR(11 downto 0);

            -- Control outputs
            result_src       : out std_logic_vector(2 downto 0);
            WEN              : out std_logic_vector(XLEN_BYTES-1 downto 0);
            branch           : out std_logic;
            ALU_src          : out std_logic;
            div_op           : out std_logic;
            reg_write        : out std_logic;
            jump             : out std_logic;
            jalr             : out std_logic;
            imm_src          : out std_logic_vector(2 downto 0);
            alu_control      : out std_logic_vector(6 downto 0);
            mem_access_instr : out std_logic;

            -- Custom instruction outputs
            isr_ret          : out std_logic;
            sleep_rq         : out std_logic;
            wake_rq          : out std_logic;
            -- P1 standard SYSTEM/PRIV decode ('0' unless ENABLE_TRAPCSR)
            ecall_op         : out std_logic;
            ebreak_op        : out std_logic;
            mret_op          : out std_logic;
            -- P2 WFI decode + the U-mode decode inputs
            wfi_op           : out std_logic;
            priv_m           : in  std_logic := '1';
            status_tw        : in  std_logic := '0';
            mcounteren_bits  : in  std_logic_vector(4 downto 0) := "00000";
            -- F10 (fix pass W4): rs1/uimm-field-is-zero, straight through
            csr_rs1_zero     : in  std_logic := '1';
            -- F-BV1 (K5): R-type rs2-field-is-zero, straight through
            rs2_zero         : in  std_logic := '0';
            wrs_op           : out std_logic;
            wrs_sto          : out std_logic;

            -- Atomic memory operation outputs
            amo_op           : out std_logic;
            lr_op            : out std_logic;
            sc_op            : out std_logic;
            fence_op         : out std_logic;
            cboz_op          : out std_logic;
            zcm_op           : out std_logic;
            pause_hint       : out std_logic;

            -- CSR instruction outputs
            csr_op           : out STD_LOGIC_VECTOR(2 downto 0);
            csr_valid        : out std_logic;

            -- X4 Zfinx FP decode
            is_fp_singlecycle : out std_logic;
            is_fp_multicycle  : out std_logic;
            is_fp_fma         : out std_logic;
            frm_valid         : in  std_logic := '1';

            -- Exception handling
            trap             : out std_logic
        );
    end component;

    -- Branch condition evaluator
    component branch_valid is
        port(
            Zero             : in  std_logic;
            funct3           : in  std_logic_vector(2 downto 0);
            brnch_cond_met   : out std_logic
        );
    end component;

    -- ==========================================
    -- Internal Signal Declarations
    -- ==========================================
    signal branch         : std_logic;      -- Branch instruction decoded
    signal brnch_cond_met : std_logic;      -- Branch condition satisfied
    signal jump_sig       : std_logic;      -- Jump instruction decoded

begin

    -- ==========================================
    -- Main Decoder Instance
    -- ==========================================
    -- Decodes instruction opcode and function fields to generate control signals
    md: maindec
        generic map(
            ENABLE_MUL      => ENABLE_MUL,
            ENABLE_DIV      => ENABLE_DIV,
            ENABLE_ATOMICS  => ENABLE_ATOMICS,
            ENABLE_BITMANIP => ENABLE_BITMANIP,
            ENABLE_ZICOND   => ENABLE_ZICOND,
            ENABLE_ZIMOP    => ENABLE_ZIMOP,
            ENABLE_ZIHINT   => ENABLE_ZIHINT,
            ENABLE_ZAWRS    => ENABLE_ZAWRS,
            ENABLE_ZABHA    => ENABLE_ZABHA,
            ENABLE_ZACAS    => ENABLE_ZACAS,
            ENABLE_ZICBOZ   => ENABLE_ZICBOZ,
            ENABLE_ZCMP     => ENABLE_ZCMP,
            ENABLE_ZCMT     => ENABLE_ZCMT,
            ENABLE_ZBKB     => ENABLE_ZBKB,
            ENABLE_ZBKC     => ENABLE_ZBKC,
            ENABLE_ZBKX     => ENABLE_ZBKX,
            ENABLE_ZKN      => ENABLE_ZKN,
            ENABLE_ZFINX    => ENABLE_ZFINX,
            ENABLE_TRAPCSR  => ENABLE_TRAPCSR,
            ENABLE_UMODE    => ENABLE_UMODE,
            ENABLE_PMP      => ENABLE_PMP
        )
        port map(
            resetn           => resetn,
            op               => op,
            funct3           => funct3,
            funct7           => funct7,
            mask             => mask,
            imm12            => imm12,  

            -- Control outputs
            result_src       => result_src,
            WEN              => WEN,
            branch           => branch,          -- Internal branch signal
            ALU_src          => ALU_src,
            div_op           => div_op,
            reg_write        => reg_write,
            jump             => jump_sig,        -- Internal jump signal
            jalr             => jalr,
            imm_src          => imm_src,
            alu_control      => alu_control,
            mem_access_instr => mem_access_instr,

            -- Custom instruction outputs
            isr_ret          => isr_ret,
            sleep_rq         => sleep_rq,
            wake_rq          => wake_rq,
            ecall_op         => ecall_op,
            ebreak_op        => ebreak_op,
            mret_op          => mret_op,
            wfi_op           => wfi_op,
            priv_m           => priv_m,
            status_tw        => status_tw,
            mcounteren_bits  => mcounteren_bits,
            csr_rs1_zero     => csr_rs1_zero,
            rs2_zero         => rs2_zero,
            wrs_op           => wrs_op,
            wrs_sto          => wrs_sto,
                   
            -- Atomic memory operation outputs
            amo_op           => amo_op,
            lr_op            => lr_op,
            sc_op            => sc_op,
            fence_op         => fence_op,
            cboz_op          => cboz_op,
            zcm_op           => zcm_op,
            pause_hint       => pause_hint,

            csr_op           => csr_op,
            csr_valid        => csr_valid,

            is_fp_singlecycle => is_fp_singlecycle,
            is_fp_multicycle  => is_fp_multicycle,
            is_fp_fma         => is_fp_fma,
            frm_valid         => frm_valid,

            trap             => trap
        );

    -- ==========================================
    -- Branch Validator Instance
    -- ==========================================
    -- Evaluates branch conditions based on ALU flags and branch type
    bval: branch_valid
        port map(
            Zero           => Zero,              -- ALU zero flag
            funct3         => funct3,            -- Branch type (BEQ, BNE, BLT, etc.)
            brnch_cond_met => brnch_cond_met    -- Branch taken signal
        );

    -- ==========================================
    -- PC Source Control Logic
    -- ==========================================
    -- PC updates to target address when:
    -- 1. Branch instruction AND condition is met, OR
    -- 2. Unconditional jump (JAL/JALR)
    pc_src <= (branch and brnch_cond_met) or jump_sig;
    

    -- Pass through jump signal to CPU for state machine control
    jump <= jump_sig;

end struct;
