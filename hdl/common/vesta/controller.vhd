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
        ENABLE_ZBKB     : boolean := false;
        ENABLE_ZBKC     : boolean := false;
        ENABLE_ZBKX     : boolean := false;
        ENABLE_ZKN      : boolean := false;
        ENABLE_ZFINX    : boolean := false
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
        WEN              : out std_logic_vector(3 downto 0);   -- Memory write enable (byte enables)
        pc_src           : out std_logic;                      -- PC source selection (sequential/branch)
        ALU_src          : out std_logic;                      -- ALU source B selection
        div_op           : out std_logic;                      -- Division operation flag
        reg_write        : out std_logic;                      -- Register file write enable
        jump             : out std_logic;                      -- Jump instruction indicator
        jalr             : out std_logic;                      -- JALR instruction indicator
        imm_src          : out std_logic_vector(2 downto 0);   -- Immediate type selector
        alu_control      : out std_logic_vector(5 downto 0);   -- ALU operation selector
        mem_access_instr : out std_logic;                      -- Memory access instruction flag
        
        -- ==========================================
        -- Custom Instruction Outputs
        -- ==========================================
        sleep_rq         : out std_logic;                      -- Sleep request
        wake_rq          : out std_logic;                      -- Wake request
        isr_ret          : out std_logic;                      -- ISR return instruction

        -- ==========================================
        -- Atomic Memory Operation Outputs
        -- ==========================================
        amo_op           : out std_logic;                      -- Atomic memory operation indicator
        lr_op            : out std_logic;                      -- Load-reserved operation indicator
        sc_op            : out std_logic;                      -- Store-conditional operation indicator
        fence_op         : out std_logic;                      -- FENCE instruction indicator
        pause_hint       : out std_logic;                      -- X1 Zihintpause: exact PAUSE hint (fence w,0)

        -- ==========================================
        -- CSR instruction outputs
        -- ==========================================
        csr_op           : out STD_LOGIC_VECTOR(2 downto 0); 
        csr_valid        : out std_logic;
        
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
            ENABLE_ZBKB     : boolean := false;
            ENABLE_ZBKC     : boolean := false;
            ENABLE_ZBKX     : boolean := false;
            ENABLE_ZKN      : boolean := false;
            ENABLE_ZFINX    : boolean := false
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
            WEN              : out std_logic_vector(3 downto 0);
            branch           : out std_logic;
            ALU_src          : out std_logic;
            div_op           : out std_logic;
            reg_write        : out std_logic;
            jump             : out std_logic;
            jalr             : out std_logic;
            imm_src          : out std_logic_vector(2 downto 0);
            alu_control      : out std_logic_vector(5 downto 0);
            mem_access_instr : out std_logic;

            -- Custom instruction outputs
            isr_ret          : out std_logic;
            sleep_rq         : out std_logic;
            wake_rq          : out std_logic;

            -- Atomic memory operation outputs
            amo_op           : out std_logic;
            lr_op            : out std_logic;
            sc_op            : out std_logic;
            fence_op         : out std_logic;
            pause_hint       : out std_logic;

            -- CSR instruction outputs
            csr_op           : out STD_LOGIC_VECTOR(2 downto 0); 
            csr_valid        : out std_logic;

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
            ENABLE_ZBKB     => ENABLE_ZBKB,
            ENABLE_ZBKC     => ENABLE_ZBKC,
            ENABLE_ZBKX     => ENABLE_ZBKX,
            ENABLE_ZKN      => ENABLE_ZKN,
            ENABLE_ZFINX    => ENABLE_ZFINX
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
                   
            -- Atomic memory operation outputs
            amo_op           => amo_op,
            lr_op            => lr_op,
            sc_op            => sc_op,
            fence_op         => fence_op,
            pause_hint       => pause_hint,

            csr_op           => csr_op,
            csr_valid        => csr_valid,
            
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
