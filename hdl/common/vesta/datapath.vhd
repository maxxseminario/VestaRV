library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library work;
use work.constants.ALL;

-- Vesta datapath: register file, immediate extender, ALU, load/store formatting, the AMO/CAS staging registers, and the optional Zfinx FP units.
entity datapath is
    generic (
        -- Core ISA feature switches, passed straight through to the ALU.
        ENABLE_MUL      : boolean := true;
        ENABLE_DIV      : boolean := true;
        ENABLE_ATOMICS  : boolean := true;
        ENABLE_BITMANIP : boolean := true;
        -- Optional extension switches, also passed straight through to the ALU (default false).
        ENABLE_ZICOND   : boolean := false;
        ENABLE_ZBKB     : boolean := false;
        ENABLE_ZBKC     : boolean := false;
        ENABLE_ZBKX     : boolean := false;
        ENABLE_ZKN      : boolean := false;
        ENABLE_ZFINX    : boolean := false;
        -- Lockstep tracer: gates the read-only trc_* taps below.
        -- False so the OFF netlist is identical BY CONSTRUCTION, not by relying on the optimiser to strip unloaded logic.
        TRACE_ENABLE    : boolean := false
    );
    port (
        clk          : in  std_logic;
        resetn       : in  std_logic;
        
        -- ==========================================
        -- Program Counter Interface
        -- ==========================================
        pc           : in  std_logic_vector(XLEN-1 downto 0);      -- Current PC value
        pc_plus_4    : in  std_logic_vector(XLEN-1 downto 0);      -- PC + 4 for next sequential instruction
        
        -- ==========================================
        -- Control Signals from Controller
        -- ==========================================
        result_Src   : in  std_logic_vector(2 downto 0);       -- Selects result source (000:ALU, 001:Mem, 010:PC+4, 011:PC_target, 100:CSR)
        pc_src       : in  std_logic;                          -- PC source selection
        ALU_src      : in  std_logic;                          -- ALU operand B source (0:register, 1:immediate)
        reg_write    : in  std_logic;                          -- Register file write enable
        jalr         : in  std_logic;                          -- JALR instruction indicator
        imm_src      : in  std_logic_vector(2 downto 0);       -- Immediate type selector
        funct3       : in  std_logic_vector(2 downto 0);       -- Function field for load/store operations
        mask         : in  std_logic_vector(1 downto 0);       -- Byte/halfword position for loads/stores
        alu_control  : in  std_logic_vector(6 downto 0);       -- ALU operation selector
        div_start    : in  std_logic;                          -- Start signal for division operation
        div_dispatch : in  std_logic;                          -- The real DIV dispatch cycle (arms the ALU divide FSM)
        
        -- ==========================================
        -- Atomic operation control signals
        -- ==========================================
        amo_phase    : in  std_logic_vector(2 downto 0);       -- 000: normal, 001: AMO_READ, 010: AMO_COMPUTE, 011: AMO_WRITE, 100: SC fail, 101: SC success
        cas_op       : in  std_logic;                          -- Zacas: this AMO is an amocas (steers the rs2 read port to rd in AMO_WRITEBACK; gates the CAS compare)

        -- ==========================================
        -- Zcmp/Zcmt sequencer regfile steering
        -- ==========================================
        -- The push/pop/move/table-jump FSM drives the regfile ports from REGISTERED sequencer indices, never re-reading a live instruction field mid-sequence.
        -- All default inactive, so a non-Zcm build is bit-identical: the muxes fold to plain instr-field addressing.
        zcm_rs_addr  : in  std_logic_vector(4 downto 0) := "00000";  -- rs1 read port (a1) index: src_a/rs1_value becomes reg[zcm_rs_addr] (push store data; a0 takes x0, ret reads x1)
        zcm_rs_sel   : in  std_logic := '0';
        zcm_rd_addr  : in  std_logic_vector(4 downto 0) := "00000";  -- write port (a3) index: the pop-loaded word or move result lands in reg[zcm_rd_addr]
        zcm_rd_sel   : in  std_logic := '0';
        zcm_move_sel : in  std_logic := '0';   -- Result is src_a (reg-reg move cm.mvsa01/mva01s, a0=0)
        zcm_loadwb_sel : in std_logic := '0';  -- Result is read_data (cm.pop raw loaded word; word access, so equal to loadext's funct3=010 passthrough)
        
        -- ==========================================
        -- Instruction and Memory Interface
        -- ==========================================
        instr        : in  std_logic_vector(ILEN-1 downto 0);      -- Current instruction
        read_data    : in  std_logic_vector(XLEN-1 downto 0);      -- Data from memory (for loads)
        write_data   : out std_logic_vector(XLEN-1 downto 0);      -- Data to memory (for stores)
        
        -- ==========================================
        -- Datapath Outputs
        -- ==========================================
        Zero         : out std_logic;                          -- ALU zero flag
        pc_target    : out std_logic_vector(XLEN-1 downto 0);      -- Target PC for branches/jumps
        ALU_result   : out std_logic_vector(XLEN-1 downto 0);      -- ALU computation result
        rs1_value    : out std_logic_vector(XLEN-1 downto 0);      -- rs1 register value (phase-independent address for LR/SC reservation compares)
        amo_addr_low : out std_logic_vector(1 downto 0);       -- Registered AMO address low bits (alias-proof byte-lane select)
        cas_match    : out std_logic;                          -- Registered CAS compare verdict (1=match, gates the conditional write)
        alu_done     : out std_logic;                          -- ALU operation complete (for multi-cycle ops)
        
        -- ==========================================
        -- Stack Pointer Management for IRQ
        -- ==========================================
        sp_in        : in  std_logic_vector(XLEN-1 downto 0);      -- New stack pointer value on irq_save
        sp_out       : out std_logic_vector(XLEN-1 downto 0);      -- Current stack pointer value
        sp_write_en  : in  std_logic;       
        
        -- ==========================================
        -- CSR Interface
        -- ==========================================
        csr_valid   : in  std_logic;                          -- Valid CSR operation
        csr_rdata   : in  std_logic_vector(XLEN-1 downto 0);      -- Data read from CSR
        csr_wdata   : out std_logic_vector(XLEN-1 downto 0);      -- Data to write to CSR

        -- ==========================================
        -- Zfinx FPU control / status, all default inert.
        -- The whole FP datapath is behind gen_fpu, so an OFF build is bit-identical to base.
        -- ==========================================
        fp_op_latch  : in  std_logic := '0';                   -- EXECUTE-dispatch strobe: latch rs1/rs2
        fp_fetch3    : in  std_logic := '0';                   -- FPU_FETCH3: steer a2 to rs3, latch rs3
        fpu_start    : in  std_logic := '0';                   -- FPU_WAIT: run the multi-cycle unit
        frm_value    : in  std_logic_vector(2 downto 0) := "000"; -- current frm (dynamic-rm resolution)
        fpu_done     : out std_logic;                          -- multi-cycle FP complete (like alu_done)
        fp_flags     : out std_logic_vector(4 downto 0);       -- flags of the completing FP op (mc at FPU_DONE / sc in EXECUTE)


        -- ==========================================
        -- LOCKSTEP TRACER TAPS (read-only)
        -- ==========================================
        -- Only the two committed-write-port nets invisible from vesta need ports; we3, sp_write and sp_in are already datapath INPUTS wired straight to the regfile pins with no intervening logic.
        -- Both are pure taps on nets that already drive the regfile, so the TRACE_ENABLE=false netlist is unchanged.
        trc_rd_addr  : out std_logic_vector(4 downto 0);           -- = a3  (rf_a3_addr)
        trc_rd_data  : out std_logic_vector(XLEN-1 downto 0);      -- = wd3 (Result)

        -- ==========================================
        -- Test output: stores the pass/fail result of instruction tests
        -- ==========================================
        a0           : out std_logic_vector(XLEN-1 downto 0)       -- Register x10 (a0) value for testing
    );
end datapath;

architecture struct of datapath is

    -- ==========================================
    -- Component Declarations
    -- ==========================================
    
    component regfile
        port (
            clk      : in  std_logic;
            resetn   : in  std_logic;
            we3      : in  std_logic;
            a1, a2, a3 : in  std_logic_vector(4 downto 0);
            wd3      : in  std_logic_vector(XLEN-1 downto 0);
            rd1, rd2 : out std_logic_vector(XLEN-1 downto 0);
            sp_in    : in  std_logic_vector(XLEN-1 downto 0);
            sp_out   : out std_logic_vector(XLEN-1 downto 0);
            sp_write : in  std_logic;
            a0       : out std_logic_vector(XLEN-1 downto 0)
        );
    end component;

    component extend
        port (
            instr    : in  std_logic_vector(ILEN-1 downto 7);
            imm_src  : in  std_logic_vector(2 downto 0);
            imm_ext  : out std_logic_vector(XLEN-1 downto 0)
        );
    end component;

    component alu
        generic (
            ENABLE_MUL      : boolean := true;
            ENABLE_DIV      : boolean := true;
            ENABLE_ATOMICS  : boolean := true;
            ENABLE_BITMANIP : boolean := true;
            -- Optional extensions (default false)
            ENABLE_ZICOND   : boolean := false;
            ENABLE_ZBKB     : boolean := false;
            ENABLE_ZBKC     : boolean := false;
            ENABLE_ZBKX     : boolean := false;
            ENABLE_ZKN      : boolean := false;
            ENABLE_ZFINX    : boolean := false
        );
        port (
            resetn      : in  std_logic;
            clk         : in  std_logic;
            a, b        : in  std_logic_vector(XLEN-1 downto 0);
            alu_control : in  std_logic_vector(6 downto 0);
            bs          : in  std_logic_vector(1 downto 0);
            div_start   : in  std_logic;
            div_dispatch : in  std_logic;
            ALU_result  : out std_logic_vector(XLEN-1 downto 0);
            alu_done    : out std_logic;
            Zero        : out std_logic
        );
    end component;

    component loadext
        port (
            clk           : in  std_logic;
            funct3        : in  std_logic_vector(2 downto 0);
            mask          : in  std_logic_vector(1 downto 0);
            read_data     : in  std_logic_vector(XLEN-1 downto 0);
            extended_data : out std_logic_vector(XLEN-1 downto 0)
        );
    end component;

    component store_ext
        port (
            funct3        : in  std_logic_vector(2 downto 0);
            read_data     : in  std_logic_vector(XLEN-1 downto 0);
            extended_data : out std_logic_vector(XLEN-1 downto 0)
        );
    end component;

    -- Zfinx FP units, instantiated behind gen_fpu: a multi-cycle unit and a single-cycle one.
    component fpu
        port (
            clk       : in  std_logic;
            resetn    : in  std_logic;
            fpu_start : in  std_logic;
            fp_op     : in  std_logic_vector(3 downto 0);
            rm        : in  std_logic_vector(2 downto 0);
            fp_a      : in  std_logic_vector(31 downto 0);
            fp_b      : in  std_logic_vector(31 downto 0);
            fp_c      : in  std_logic_vector(31 downto 0);
            fpu_done  : out std_logic;
            fp_result : out std_logic_vector(31 downto 0);
            fp_flags  : out std_logic_vector(4 downto 0)
        );
    end component;

    component fpu_simple
        port (
            fp_s_op     : in  std_logic_vector(3 downto 0);
            fp_s_a      : in  std_logic_vector(31 downto 0);
            fp_s_b      : in  std_logic_vector(31 downto 0);
            fp_s_result : out std_logic_vector(31 downto 0);
            fp_s_flags  : out std_logic_vector(4 downto 0)
        );
    end component;

    -- ==========================================
    -- Internal Signal Declarations
    -- ==========================================
    
    -- Register file signals
    signal src_a              : std_logic_vector(XLEN-1 downto 0);  -- Register file output A (rs1)
    signal write_data_reg_val : std_logic_vector(XLEN-1 downto 0);  -- Register file output B (rs2)
    
    -- Immediate and ALU signals
    signal imm_ext            : std_logic_vector(XLEN-1 downto 0);  -- Sign-extended immediate
    signal SrcB               : std_logic_vector(XLEN-1 downto 0);  -- ALU input B (muxed)
    signal ALU_A              : std_logic_vector(XLEN-1 downto 0);  -- ALU input A (muxed for AMO)
    signal ALU_B              : std_logic_vector(XLEN-1 downto 0);  -- ALU input B (muxed for AMO)
    signal amo_b_ext          : std_logic_vector(XLEN-1 downto 0);  -- Zabha: rs2 sub-word sign-extended for AMO compute
    
    -- Result signals
    signal Result             : std_logic_vector(XLEN-1 downto 0);  -- Final result to write back
    signal extended_data      : std_logic_vector(XLEN-1 downto 0);  -- Load-extended data from memory
    signal ALU_result_internal: std_logic_vector(XLEN-1 downto 0);  -- Internal ALU result
    
    -- PC calculation signals
    signal PC_targetbase      : std_logic_vector(XLEN-1 downto 0);  -- Base address for PC target calculation
    
    -- AMO saved values
    signal amo_addr_reg       : std_logic_vector(XLEN-1 downto 0);  -- Saved address for AMO
    signal amo_read_data_reg  : std_logic_vector(XLEN-1 downto 0);  -- Saved read data for AMO
    signal amo_rs2_reg        : std_logic_vector(XLEN-1 downto 0);  -- Zabha: latched rs2 (alias-proof AMO compute operand)
    -- Zacas compare value is the ORIGINAL rd, and the AMO_WRITEBACK edge clobbers rd with the old memory value, so it must be captured no later than that edge.
    -- amo_cmp_reg latches rf[rd] through the rs2 read port steered to rd during AMO_WRITEBACK (amo_phase="110"); the async read still presents the PRE-write value on the writing edge.
    signal amo_cmp_reg        : std_logic_vector(XLEN-1 downto 0);  -- Zacas: latched original rd (compare value)
    signal amo_cmp_ext        : std_logic_vector(XLEN-1 downto 0);  -- Zacas: amo_cmp_reg sign-extended to the AMO width
    signal cas_match_comb     : std_logic;                      -- Zacas: combinational compare of two registered operands
    signal cas_match_reg      : std_logic;                      -- Zacas: phase-independent verdict, latched at AMO_COMPUTE, used in AMO_WRITE
    signal rf_a2_addr         : std_logic_vector(4 downto 0);   -- Zacas: rs2 read-port address (steered to rd during the CAS AMO_WRITEBACK)
    signal rf_a1_addr         : std_logic_vector(4 downto 0);   -- Zcmp: rs1 read-port address (steered to the sequencer reg index)
    signal rf_a3_addr         : std_logic_vector(4 downto 0);   -- Zcmp: write-port address (steered to the sequencer reg index)

    signal rd_amo            : std_logic_vector(XLEN-1 downto 0);  -- Data read during AMO operations

    -- Zfinx FP signals, at architecture level so the Result mux can reference them; driven in gen_fpu, tied to 0 in gen_no_fpu.
    -- The registered operand copies are the ONLY thing the multi-cycle unit consumes across FPU_WAIT: rs1/rs2 latched at EXECUTE dispatch (pre-writeback), rs3 latched in FPU_FETCH3 from the steered rs2 read port.
    signal fp_rs1_reg   : std_logic_vector(31 downto 0);
    signal fp_rs2_reg   : std_logic_vector(31 downto 0);
    signal fp_rs3_reg   : std_logic_vector(31 downto 0);
    signal fp_op        : std_logic_vector(3 downto 0);
    signal fp_s_op      : std_logic_vector(3 downto 0);
    signal eff_rm       : std_logic_vector(2 downto 0);
    signal fp_result_mc : std_logic_vector(31 downto 0);
    signal fp_s_result  : std_logic_vector(31 downto 0);
    signal fp_flags_mc  : std_logic_vector(4 downto 0);
    signal fp_s_flags   : std_logic_vector(4 downto 0);
    signal fpu_done_i   : std_logic;

begin

    -- ==========================================
    -- AMO Data Registers
    -- ==========================================
    -- Save address, memory data and the CAS operands across the AMO phases.
    amo_reg_proc: process(clk, resetn)
    begin
        if resetn = '0' then
            amo_addr_reg <= (others => '0');
            amo_read_data_reg <= (others => '0');
            amo_rs2_reg <= (others => '0');
            amo_cmp_reg <= (others => '0');
            cas_match_reg <= '0';
        elsif rising_edge(clk) then
            -- Save address during AMO_READ phase
            if amo_phase = "001" then  -- AMO_READ
                amo_addr_reg <= src_a;  -- Save rs1 (address)
                amo_read_data_reg <= read_data;  -- Save memory data
                amo_rs2_reg <= write_data_reg_val;  -- Latch the original rs2 (alias-proof)
            end if;

            -- Capture the ORIGINAL rd (the CAS compare value) at the AMO_WRITEBACK edge, one edge before AMO_COMPUTE consumes it.
            -- rf_a2_addr steers the rs2 read port to rd this cycle, so write_data_reg_val is the PRE-write rf[rd]; the swap value was latched at AMO_READ from the un-steered port, so both operands are alias-proof.
            if amo_phase = "110" and cas_op = '1' then  -- AMO_WRITEBACK, CAS only
                amo_cmp_reg <= write_data_reg_val;
            end if;

            -- Register the compare verdict at AMO_COMPUTE from two registered inputs (rd_amo, amo_cmp_ext), so it is stable and phase-independent when it gates the write in AMO_WRITE.
            if amo_phase = "010" and cas_op = '1' then  -- AMO_COMPUTE, CAS only
                cas_match_reg <= cas_match_comb;
            end if;

            rd_amo <= Result; -- Result delayed one clock cycle, consumed by AMO_COMPUTE
        end if;

    end process;

    -- Byte-lane select source, registered at AMO_READ one cycle before the AMO_WRITEBACK rd write, so an AMO with rd equal to rs1 cannot corrupt it.
    amo_addr_low <= amo_addr_reg(1 downto 0);

    -- rs2 read-port address, normally rs2 (instr[24:20]); steered to the rd index (instr[11:7]) ONLY during the CAS AMO_WRITEBACK so amo_cmp_reg can capture the original rd before rd is overwritten.
    -- During FPU_FETCH3 it takes the FMA rs3 index (instr[31:27]) instead, so fp_rs3_reg captures reg[rs3] with NO third read port; ENABLE_ZFINX-gated, so it folds away in the OFF build.
    rf_a2_addr <= instr(31 downto 27) when (ENABLE_ZFINX and fp_fetch3 = '1') else
                  instr(11 downto 7)  when (cas_op = '1' and amo_phase = "110") else
                  instr(24 downto 20);

    -- Sign-extend the captured compare value to the AMO width, matching the sign-extended old sub-word that loadext places on rd_amo.
    -- Equality is extension-invariant, so sign-extending BOTH sides keeps the compare consistent (word CAS keeps the full 32-bit value).
    amo_cmp_ext <= (31 downto 8 => amo_cmp_reg(7)) & amo_cmp_reg(7 downto 0)   when funct3 = "000" else
                   (31 downto 16 => amo_cmp_reg(15)) & amo_cmp_reg(15 downto 0) when funct3 = "001" else
                   amo_cmp_reg;

    -- The CAS compare itself: during AMO_COMPUTE rd_amo carries the old memory value (sub-word sign-extended by loadext) and amo_cmp_ext the original rd extended the same way.
    -- Both are REGISTERED, so there is no phase-dependent compare.
    cas_match_comb <= '1' when rd_amo = amo_cmp_ext else '0';

    -- Export the registered verdict to vesta for the amo_wen gating.
    cas_match <= cas_match_reg;

    -- ==========================================
    -- CSR write data. TODO: this could be better abstracted.
    -- ==========================================
    -- CSRxI forms take the zero-extended 5-bit uimm from instr[19:15]; the register forms take rs1.
    csr_wdata <= (XLEN-1 downto 5 => '0') & instr(19 downto 15) when (csr_valid = '1' and funct3(2) = '1') else
                src_a;  -- rs1 value       
    

    -- ==========================================
    -- PC Target Calculation
    -- ==========================================
    -- For JALR: use register value as base
    -- For branches/JAL: use current PC as base
    PC_targetbase <= src_a when jalr = '1' else pc;
    
    -- Calculate target PC by adding immediate to base
    pc_target <= std_logic_vector(unsigned(PC_targetbase) + unsigned(imm_ext));

    -- ==========================================
    -- Register File Instance
    -- ==========================================
    -- 32 general-purpose registers with special stack pointer handling.
    -- The Zcmp sequencer steers the rs1 read port (a1) and the write port (a3) to its REGISTERED reg index during a push/pop/move step; both selects fold to '0' when the Zcm generics are off.
    rf_a1_addr <= zcm_rs_addr when zcm_rs_sel = '1' else instr(19 downto 15);
    rf_a3_addr <= zcm_rd_addr when zcm_rd_sel = '1' else instr(11 downto 7);

    -- Lockstep tracer taps: the two committed-write-port nets not visible from vesta, read-only and adding no logic.
    -- Behind a generate so an OFF build carries not even the tap.
    gen_trc: if TRACE_ENABLE generate
        trc_rd_addr <= rf_a3_addr;
        trc_rd_data <= Result;
    end generate;
    -- Tracer OFF: drive the taps to zero so the ports are never left dangling.
    gen_trc_off: if not TRACE_ENABLE generate
        trc_rd_addr <= (others => '0');
        trc_rd_data <= (others => '0');
    end generate;

    rf: regfile
        port map (
            clk      => clk,
            resetn   => resetn,
            we3      => reg_write,                    -- Write enable
            a1       => rf_a1_addr,                   -- rs1 address (Zcmp: steered to the sequencer reg index)
            a2       => rf_a2_addr,                   -- rs2 address (Zacas: steered to rd during CAS AMO_WRITEBACK)
            a3       => rf_a3_addr,                   -- rd address (Zcmp: steered to the sequencer reg index)
            wd3      => Result,                       -- Write data
            rd1      => src_a,                       -- Read data 1 (rs1)
            rd2      => write_data_reg_val,          -- Read data 2 (rs2)
            sp_in    => sp_in,                       -- Stack pointer input for IRQ
            sp_out   => sp_out,                      -- Stack pointer output
            sp_write => sp_write_en,                 -- Stack pointer write enable
            a0       => a0                            -- Debug output (x10/a0)
        );
    
    -- ==========================================
    -- Immediate Extension Unit
    -- ==========================================
    -- Sign-extends immediate values based on instruction type
    ext: extend
        port map (
            instr   => instr(31 downto 7),           -- Instruction bits containing immediate
            imm_src => imm_src,                       -- Immediate type selector
            imm_ext => imm_ext                        -- Extended 32-bit immediate
        );

    -- ==========================================
    -- ALU Source B Multiplexer (before AMO mux)
    -- ==========================================
    -- Select between register value and immediate for ALU input B
    SrcB <= imm_ext when ALU_src = '1' else          -- Use immediate
            write_data_reg_val;                       -- Use register rs2

    -- ==========================================
    -- ALU Input Multiplexers for AMO Support
    -- ==========================================
    -- ALU input A selection based on AMO phase
    ALU_A <= src_a           when amo_phase = "000" else  -- Normal: use rs1
             src_a           when amo_phase = "001" else  -- AMO_READ: use rs1 for address
             rd_amo          when amo_phase = "010" else  -- AMO_COMPUTE: use saved read data
             amo_addr_reg    when amo_phase = "011" else  -- AMO_WRITE: use saved address
             src_a;

    -- ALU input B by AMO phase, with Zabha sign-extending the rs2 low byte/half for sub-word AMO compute so the ALU min/max compares (and add/logical, truncated on write) see the sub-word operand, not the full register.
    -- Sign-extension is monotonic in the unsigned sub-word value, so it serves the unsigned min/max forms too; word AMOs and every non-AMO op keep the full register.
    amo_b_ext <= (31 downto 8 => amo_rs2_reg(7)) & amo_rs2_reg(7 downto 0)   when funct3 = "000" else
                 (31 downto 16 => amo_rs2_reg(15)) & amo_rs2_reg(15 downto 0) when funct3 = "001" else
                 amo_rs2_reg;

    ALU_B <= SrcB                     when amo_phase = "000" else  -- Normal: use SrcB (rs2 or immediate)
            (0 => '1', others => '0') when amo_phase = "100" else  -- SC fail: write nonzero to rd
            (others => '0')           when amo_phase = "101" else  -- SC success: write 0 to rd
             amo_b_ext                when amo_phase = "010" else  -- Zabha: sub-word rs2 for AMO_COMPUTE (word AMO uses the full rs2)
             SrcB;

    -- ==========================================
    -- Arithmetic Logic Unit Instance
    -- ==========================================
    -- Performs all arithmetic and logical operations including multiply/divide
    mainalu: alu
        generic map (
            ENABLE_MUL      => ENABLE_MUL,
            ENABLE_DIV      => ENABLE_DIV,
            ENABLE_ATOMICS  => ENABLE_ATOMICS,
            ENABLE_BITMANIP => ENABLE_BITMANIP,
            ENABLE_ZICOND   => ENABLE_ZICOND,
            ENABLE_ZBKB     => ENABLE_ZBKB,
            ENABLE_ZBKC     => ENABLE_ZBKC,
            ENABLE_ZBKX     => ENABLE_ZBKX,
            ENABLE_ZKN      => ENABLE_ZKN,
            ENABLE_ZFINX    => ENABLE_ZFINX
        )
        port map (
            resetn      => resetn,
            clk         => clk,
            a           => ALU_A,                     -- Muxed for AMO operations
            b           => ALU_B,                     -- Muxed for AMO operations
            alu_control => alu_control,               -- Operation selector
            bs          => instr(31 downto 30),       -- AES byte-select (aes32* only)
            div_start   => div_start,                 -- Start division
            div_dispatch => div_dispatch,             -- The real dispatch cycle
            ALU_result  => ALU_result_internal,       -- Operation result
            alu_done    => alu_done,                  -- Multi-cycle operation complete
            Zero        => Zero                       -- Zero flag for branches
        );

    -- Output ALU result
    ALU_result <= ALU_result_internal;

    -- rs1 straight from the regfile: the SC/LR address WITHOUT the amo_phase-dependent ALU_B mux.
    -- ALU_result is rs1 + 0/1 during SC_CHECK depending on the pass/fail phase, so comparing reservation_addr against ALU_result there forms a combinational loop with two stable solutions.
    rs1_value <= src_a;

    -- ==========================================
    -- Result Source Multiplexer
    -- ==========================================
    -- Select the final result to write back to the register file; for SC, write success (0) or failure (1) from the reservation check.
    -- The Zcmp/Zcmt sequencer sources take highest priority: zcm_move_sel picks src_a (reg[steered a1], or 0 when a1 is steered to x0), zcm_loadwb_sel the raw loaded word; both fold to '0' when the generics are off.
    Result <= src_a               when zcm_move_sel   = '1' else  -- Zcmp reg-reg move, a0 takes x0
              read_data           when zcm_loadwb_sel = '1' else  -- Zcmp pop: raw loaded word, a word access so equal to loadext's funct3=010
              ALU_result_internal when result_Src = "000" else  -- ALU operation result
            extended_data       when result_Src = "001" else  -- Load from memory
            pc_plus_4           when result_Src = "010" else  -- Return address (JAL/JALR)
            pc_target           when result_Src = "011" else  -- PC + immediate (AUIPC)
            csr_rdata           when result_Src = "100" else  -- CSR read data
            fp_s_result         when result_Src = RSRC_FP_SINGLE else  -- Single-cycle FP (EXECUTE)
            fp_result_mc        when result_Src = RSRC_FP_MULTI  else  -- Multi-cycle FP (FPU_DONE)
            (others => '0');
    
    -- ==========================================
    -- Load Extension Unit Instance
    -- ==========================================
    -- Sign/zero extends loaded data based on load type (LB/LBU/LH/LHU/LW)
    loadextender: loadext
        port map(
            clk           => clk,
            funct3        => funct3,                 -- Load type (byte/halfword/word)
            mask          => mask,                    -- Byte position
            read_data     => read_data,              -- Raw data from memory
            extended_data => extended_data           -- Properly extended 32-bit value
        );

    -- ==========================================
    -- Store Extension Unit Instance
    -- ==========================================
    -- Formats store data based on store type (SB/SH/SW)
    storeextender: store_ext
        port map(
            funct3        => funct3,                 -- Store type (byte/halfword/word)
            read_data     => write_data_reg_val,     -- Data from rs2
            extended_data => write_data              -- Formatted data for memory
        );

    -- ==========================================
    -- Zfinx FP datapath, behind gen_fpu so it is 100% pruned in the OFF build
    -- ==========================================
    gen_fpu: if ENABLE_ZFINX generate
        -- Effective rounding mode: instruction rm, or frm when rm=111 (dynamic).
        eff_rm <= frm_value when instr(14 downto 12) = FRM_DYN else instr(14 downto 12);

        -- Multi-cycle op decode (fp_op[3:0], constants FPOP_*).
        -- imm12-equivalent rs2 field is instr[24:20]; funct7 is instr[31:25].
        fp_op <= FPOP_FADD     when (instr(6 downto 0) = OPFP_OPCODE and instr(31 downto 25) = FADD_FN7) else
                 FPOP_FSUB     when (instr(6 downto 0) = OPFP_OPCODE and instr(31 downto 25) = FSUB_FN7) else
                 FPOP_FMUL     when (instr(6 downto 0) = OPFP_OPCODE and instr(31 downto 25) = FMUL_FN7) else
                 FPOP_FDIV     when (instr(6 downto 0) = OPFP_OPCODE and instr(31 downto 25) = FDIV_FN7) else
                 FPOP_FSQRT    when (instr(6 downto 0) = OPFP_OPCODE and instr(31 downto 25) = FSQRT_FN7) else
                 FPOP_FCVT_W_S when (instr(6 downto 0) = OPFP_OPCODE and instr(31 downto 25) = FCVTW_FN7 and instr(24 downto 20) = FP_RS2_W)  else
                 FPOP_FCVT_WU_S when (instr(6 downto 0) = OPFP_OPCODE and instr(31 downto 25) = FCVTW_FN7 and instr(24 downto 20) = FP_RS2_WU) else
                 FPOP_FCVT_S_W when (instr(6 downto 0) = OPFP_OPCODE and instr(31 downto 25) = FCVTS_FN7 and instr(24 downto 20) = FP_RS2_W)  else
                 FPOP_FCVT_S_WU when (instr(6 downto 0) = OPFP_OPCODE and instr(31 downto 25) = FCVTS_FN7 and instr(24 downto 20) = FP_RS2_WU) else
                 FPOP_FMADD    when (instr(6 downto 0) = FMADD_OPCODE)  else
                 FPOP_FMSUB    when (instr(6 downto 0) = FMSUB_OPCODE)  else
                 FPOP_FNMSUB   when (instr(6 downto 0) = FNMSUB_OPCODE) else
                 FPOP_FNMADD   when (instr(6 downto 0) = FNMADD_OPCODE) else
                 FPOP_FADD;

        -- Single-cycle op decode (fp_s_op[3:0], constants FPSOP_*).
        fp_s_op <= FPSOP_FSGNJ  when (instr(31 downto 25) = FSGNJ_FN7   and instr(14 downto 12) = "000") else
                   FPSOP_FSGNJN when (instr(31 downto 25) = FSGNJ_FN7   and instr(14 downto 12) = "001") else
                   FPSOP_FSGNJX when (instr(31 downto 25) = FSGNJ_FN7   and instr(14 downto 12) = "010") else
                   FPSOP_FMIN   when (instr(31 downto 25) = FMINMAX_FN7 and instr(14 downto 12) = "000") else
                   FPSOP_FMAX   when (instr(31 downto 25) = FMINMAX_FN7 and instr(14 downto 12) = "001") else
                   FPSOP_FLE    when (instr(31 downto 25) = FCMP_FN7    and instr(14 downto 12) = "000") else
                   FPSOP_FLT    when (instr(31 downto 25) = FCMP_FN7    and instr(14 downto 12) = "001") else
                   FPSOP_FEQ    when (instr(31 downto 25) = FCMP_FN7    and instr(14 downto 12) = "010") else
                   FPSOP_FCLASS when (instr(31 downto 25) = FCLASS_FN7  and instr(14 downto 12) = "001") else
                   FPSOP_FSGNJ;

        -- Operand latches: rs1/rs2 captured at the EXECUTE dispatch edge from the live read ports and consumed pre-writeback that cycle, rs3 in FPU_FETCH3 from the rs2 port steered to instr[31:27].
        -- NOTHING reads a live regfile port across FPU_WAIT.
        fp_lat_proc: process(clk, resetn)
        begin
            if resetn = '0' then
                fp_rs1_reg <= (others => '0');
                fp_rs2_reg <= (others => '0');
                fp_rs3_reg <= (others => '0');
            elsif rising_edge(clk) then
                if fp_op_latch = '1' then
                    fp_rs1_reg <= src_a;               -- rd1 = reg[rs1]
                    fp_rs2_reg <= write_data_reg_val;  -- rd2 = reg[rs2]
                end if;
                if fp_fetch3 = '1' then
                    fp_rs3_reg <= write_data_reg_val;  -- rd2 (a2 steered to rs3)
                end if;
            end if;
        end process;

        -- Multi-cycle unit: runs only on the REGISTERED operand copies.
        fpu_i: fpu
            port map (
                clk       => clk,
                resetn    => resetn,
                fpu_start => fpu_start,
                fp_op     => fp_op,
                rm        => eff_rm,
                fp_a      => fp_rs1_reg,
                fp_b      => fp_rs2_reg,
                fp_c      => fp_rs3_reg,
                fpu_done  => fpu_done_i,
                fp_result => fp_result_mc,
                fp_flags  => fp_flags_mc
            );

        -- Single-cycle unit: fed LIVE rd1/rd2, consumed same-cycle in EXECUTE.
        fpu_s_i: fpu_simple
            port map (
                fp_s_op     => fp_s_op,
                fp_s_a      => src_a,
                fp_s_b      => write_data_reg_val,
                fp_s_result => fp_s_result,
                fp_s_flags  => fp_s_flags
            );
    end generate;

    -- Zfinx OFF: tie every FP signal inert so the Result mux and the status outputs fold away.
    gen_no_fpu: if not ENABLE_ZFINX generate
        fp_op        <= (others => '0');
        fp_s_op      <= (others => '0');
        eff_rm       <= (others => '0');
        fp_rs1_reg   <= (others => '0');
        fp_rs2_reg   <= (others => '0');
        fp_rs3_reg   <= (others => '0');
        fp_result_mc <= (others => '0');
        fp_s_result  <= (others => '0');
        fp_flags_mc  <= (others => '0');
        fp_s_flags   <= (others => '0');
        fpu_done_i   <= '0';
    end generate;

    -- FP status to vesta: fpu_done paces the FPU_WAIT to FPU_DONE transition.
    -- The flag bus presents the single-cycle op's flags while one is retiring (result_Src=110), else the multi-cycle op's flags (valid at FPU_DONE, result_Src=111); vesta's fp_flags_we picks the commit cycle.
    fpu_done <= fpu_done_i;
    fp_flags <= fp_s_flags when result_Src = RSRC_FP_SINGLE else fp_flags_mc;

end architecture struct;



