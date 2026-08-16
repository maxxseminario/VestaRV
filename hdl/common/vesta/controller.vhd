library IEEE;
use IEEE.std_logic_1164.all;
use work.constants.all;

entity controller is
    generic (
        -- Core ISA feature switches, passed straight through to maindec.
        ENABLE_MUL      : boolean := true;
        ENABLE_DIV      : boolean := true;
        ENABLE_ATOMICS  : boolean := true;
        ENABLE_BITMANIP : boolean := true;
        -- Optional extension switches, default false, also passed straight through to maindec.
        ENABLE_ZICOND   : boolean := false;
        ENABLE_ZIMOP    : boolean := false;
        ENABLE_ZIHINT   : boolean := false;
        ENABLE_ZAWRS    : boolean := false;
        ENABLE_ZABHA    : boolean := false;
        ENABLE_ZACAS    : boolean := false;
        ENABLE_ZICBOZ   : boolean := false;  -- Zicboz cbo.zero.
        ENABLE_ZCMP     : boolean := false;  -- Zcmp push/pop plus moves.
        ENABLE_ZCMT     : boolean := false;  -- Zcmt table jump.
        ENABLE_ZBKB     : boolean := false;
        ENABLE_ZBKC     : boolean := false;
        ENABLE_ZBKX     : boolean := false;
        ENABLE_ZKN      : boolean := false;
        ENABLE_ZFINX    : boolean := false;
        -- Privileged-architecture switches, passed straight through to maindec; default false, and no decode here consumes them directly.
        ENABLE_TRAPCSR  : boolean := false;  -- Trap CSRs plus MRET/ECALL/EBREAK/WFI.
        ENABLE_UMODE    : boolean := false;  -- U-mode privileged-access gating.
        ENABLE_PMP      : boolean := false;  -- PMP/Smpmp.
        ENABLE_DEBUG    : boolean := false   -- Debug mode, the 0x7Bx CSRs and DRET.
    );
    port(
        -- System control.
        resetn           : in  std_logic;
        
        -- Instruction fields.
        op               : in  std_logic_vector(6 downto 0);   -- Opcode field.
        funct3           : in  std_logic_vector(2 downto 0);   -- 3-bit function field.
        funct7           : in  std_logic_vector(6 downto 0);   -- 7-bit function field.
        imm12            : in  std_logic_vector(11 downto 0);  -- 12-bit immediate field.
        mask             : in  std_logic_vector(1 downto 0);   -- Address alignment for load/store.
        
        -- ALU status input.
        Zero             : in  std_logic;                      -- ALU zero flag, used for branches.
        
        -- Datapath control outputs.
        result_src       : out std_logic_vector(2 downto 0);   -- Result source mux control.
        WEN              : out std_logic_vector(XLEN_BYTES-1 downto 0);   -- Memory write enables, one per byte lane.
        pc_src           : out std_logic;                      -- PC source selection: sequential or branch target.
        ALU_src          : out std_logic;                      -- ALU source B selection.
        div_op           : out std_logic;                      -- Division operation flag.
        reg_write        : out std_logic;                      -- Register file write enable.
        jump             : out std_logic;                      -- Jump instruction indicator.
        jalr             : out std_logic;                      -- JALR instruction indicator.
        imm_src          : out std_logic_vector(2 downto 0);   -- Immediate type selector.
        alu_control      : out std_logic_vector(6 downto 0);   -- ALU operation selector.
        mem_access_instr : out std_logic;                      -- Memory access instruction flag.
        
        -- Custom instruction outputs.
        sleep_rq         : out std_logic;                      -- Sleep request.
        wake_rq          : out std_logic;                      -- Wake request.
        wrs_op           : out std_logic;                      -- Zawrs: wrs.nto or wrs.sto.
        wrs_sto          : out std_logic;                      -- Zawrs: the timeout variant.
        isr_ret          : out std_logic;                      -- ISR return instruction.

        -- Standard SYSTEM/PRIV decode, all statically '0' unless ENABLE_TRAPCSR.
        ecall_op         : out std_logic;                      -- ECALL  (SYSTEM f3=000 funct12=0x000).
        ebreak_op        : out std_logic;                      -- EBREAK (SYSTEM f3=000 funct12=0x001).
        mret_op          : out std_logic;                      -- MRET   (SYSTEM f3=000 funct12=0x302).
        wfi_op           : out std_logic;                      -- WFI (SYSTEM f3=000 funct12=0x105).
        dret_op          : out std_logic;                      -- DRET (SYSTEM f3=000 funct12=0x7B2).

        -- Debug-mode decode input, straight through to maindec.
        -- Default '0' is the RESTRICTIVE direction on purpose: an unconnected instantiation is "not in debug mode", so the 0x7Bx block stays denied and DRET stays illegal.
        debug_mode       : in  std_logic := '0';

        -- U-mode decode inputs, straight through to maindec.
        -- The defaults are inert (M-mode, TW=0, no counter enables), so an ENABLE_UMODE=false build and any instantiation that leaves them unconnected are unaffected.
        priv_m           : in  std_logic := '1';                        -- '1'=M, '0'=U.
        status_tw        : in  std_logic := '0';                        -- mstatus.TW.
        mcounteren_bits  : in  std_logic_vector(4 downto 0) := "00000"; -- {HPM4,HPM3,IR,TM,CY}.

        -- The CSR instruction's rs1/uimm FIELD is zero, i.e. this is a read-only instruction form; it goes straight through to maindec, where it qualifies the read-only-CSR illegal-instruction trap.
        -- That trap is UNGATED in EVERY build, so this port is load-bearing; default '1' is a FAIL-SAFE, so an unconnected instantiation traps nothing rather than trapping every read of a read-only CSR.
        csr_rs1_zero     : in  std_logic := '1';

        -- The R-type rs2 FIELD is zero, straight through to maindec, where it qualifies the Zbb ZEXT.H decode row: `zext.h rd,rs1` IS the rs2=x0 point of Zbkb `pack rd,rs1,rs2`, so without this bit the whole pack space aliases onto zext.h on every Zbkb-off build.
        -- Default '0', meaning NOT zero, is a fail-safe: an unconnected instantiation makes zext.h illegal, which is loud, rather than silently reinstating the alias.
        rs2_zero         : in  std_logic := '0';

        -- Atomic memory operation outputs.
        amo_op           : out std_logic;                      -- Atomic memory operation indicator.
        lr_op            : out std_logic;                      -- Load-reserved operation indicator.
        sc_op            : out std_logic;                      -- Store-conditional operation indicator.
        fence_op         : out std_logic;                      -- FENCE instruction indicator.
        cboz_op          : out std_logic;                      -- Zicboz: cbo.zero block-zero.
        zcm_op           : out std_logic;                      -- Zcmp/Zcmt: cm.* sequencer trigger.
        pause_hint       : out std_logic;                      -- Zihintpause: the exact PAUSE hint, fence w,0.

        -- CSR instruction outputs.
        csr_op           : out STD_LOGIC_VECTOR(2 downto 0);   -- CSR access type.
        csr_valid        : out std_logic;                      -- CSR instruction decoded and legal.

        -- Zfinx FP decode outputs and input.
        is_fp_singlecycle : out std_logic;                     -- Single-cycle FP, retired in EXECUTE via fpu_simple.
        is_fp_multicycle  : out std_logic;                     -- Multi-cycle FP, the core goes to FPU_WAIT.
        is_fp_fma         : out std_logic;                     -- FMA, the core goes to FPU_FETCH3.
        frm_valid         : in  std_logic := '1';              -- Current frm validity, for dynamic rounding-mode legality.

        -- Exception handling.
        trap             : out std_logic                       -- Invalid instruction trap.
    );
end controller;

architecture struct of controller is

    -- Component declarations.
    
    -- Main instruction decoder.
    component maindec
        generic (
            ENABLE_MUL      : boolean := true;
            ENABLE_DIV      : boolean := true;
            ENABLE_ATOMICS  : boolean := true;
            ENABLE_BITMANIP : boolean := true;
            -- Optional extension switches, default false.
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
            -- Privileged-architecture switches, default false.
            ENABLE_TRAPCSR  : boolean := false;
            ENABLE_UMODE    : boolean := false;
            ENABLE_PMP      : boolean := false;
            ENABLE_DEBUG    : boolean := false
        );
        port(
            resetn           : in  std_logic;
            op               : in  std_logic_vector(6 downto 0);
            funct3           : in  std_logic_vector(2 downto 0);
            funct7           : in  std_logic_vector(6 downto 0);
            mask             : in  std_logic_vector(1 downto 0);
            imm12            : in  STD_LOGIC_VECTOR(11 downto 0);

            -- Control outputs.
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

            -- Custom instruction outputs.
            isr_ret          : out std_logic;
            sleep_rq         : out std_logic;
            wake_rq          : out std_logic;
            -- Standard SYSTEM/PRIV decode, '0' unless ENABLE_TRAPCSR.
            ecall_op         : out std_logic;
            ebreak_op        : out std_logic;
            mret_op          : out std_logic;
            -- WFI decode plus the U-mode decode inputs.
            wfi_op           : out std_logic;
            -- DRET decode plus the debug-mode decode input; default '0' denies it.
            dret_op          : out std_logic;
            debug_mode       : in  std_logic := '0';
            priv_m           : in  std_logic := '1';
            status_tw        : in  std_logic := '0';
            mcounteren_bits  : in  std_logic_vector(4 downto 0) := "00000";
            -- rs1/uimm field is zero, straight through.
            csr_rs1_zero     : in  std_logic := '1';
            -- R-type rs2 field is zero, straight through.
            rs2_zero         : in  std_logic := '0';
            wrs_op           : out std_logic;
            wrs_sto          : out std_logic;

            -- Atomic memory operation outputs.
            amo_op           : out std_logic;
            lr_op            : out std_logic;
            sc_op            : out std_logic;
            fence_op         : out std_logic;
            cboz_op          : out std_logic;
            zcm_op           : out std_logic;
            pause_hint       : out std_logic;

            -- CSR instruction outputs.
            csr_op           : out STD_LOGIC_VECTOR(2 downto 0);
            csr_valid        : out std_logic;

            -- Zfinx FP decode.
            is_fp_singlecycle : out std_logic;
            is_fp_multicycle  : out std_logic;
            is_fp_fma         : out std_logic;
            frm_valid         : in  std_logic := '1';

            -- Exception handling.
            trap             : out std_logic
        );
    end component;

    -- Branch condition evaluator.
    component branch_valid is
        port(
            Zero             : in  std_logic;
            funct3           : in  std_logic_vector(2 downto 0);
            brnch_cond_met   : out std_logic
        );
    end component;

    -- Internal signals.
    signal branch         : std_logic;      -- Branch instruction decoded.
    signal brnch_cond_met : std_logic;      -- Branch condition satisfied.
    signal jump_sig       : std_logic;      -- Jump instruction decoded.

begin

    -- Main decoder: the opcode and function fields become the datapath control signals.
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
            ENABLE_PMP      => ENABLE_PMP,
            ENABLE_DEBUG    => ENABLE_DEBUG
        )
        port map(
            resetn           => resetn,
            op               => op,
            funct3           => funct3,
            funct7           => funct7,
            mask             => mask,
            imm12            => imm12,  

            -- Control outputs.
            result_src       => result_src,
            WEN              => WEN,
            branch           => branch,          -- Internal branch signal.
            ALU_src          => ALU_src,
            div_op           => div_op,
            reg_write        => reg_write,
            jump             => jump_sig,        -- Internal jump signal.
            jalr             => jalr,
            imm_src          => imm_src,
            alu_control      => alu_control,
            mem_access_instr => mem_access_instr,

            -- Custom instruction outputs.
            isr_ret          => isr_ret,
            sleep_rq         => sleep_rq,
            wake_rq          => wake_rq,
            ecall_op         => ecall_op,
            ebreak_op        => ebreak_op,
            mret_op          => mret_op,
            wfi_op           => wfi_op,
            dret_op          => dret_op,
            debug_mode       => debug_mode,
            priv_m           => priv_m,
            status_tw        => status_tw,
            mcounteren_bits  => mcounteren_bits,
            csr_rs1_zero     => csr_rs1_zero,
            rs2_zero         => rs2_zero,
            wrs_op           => wrs_op,
            wrs_sto          => wrs_sto,
                   
            -- Atomic memory operation outputs.
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

    -- Branch validator: evaluates the branch condition from the ALU flags and the branch type.
    bval: branch_valid
        port map(
            Zero           => Zero,              -- ALU zero flag.
            funct3         => funct3,            -- Branch type: BEQ, BNE, BLT and so on.
            brnch_cond_met => brnch_cond_met    -- Branch taken signal.
        );

    -- PC source: the PC takes the target address on a branch whose condition is met, or on an unconditional jump (JAL/JALR).
    pc_src <= (branch and brnch_cond_met) or jump_sig;
    

    -- Pass the jump signal out to the CPU state machine.
    jump <= jump_sig;

end struct;
