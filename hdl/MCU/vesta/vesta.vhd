library IEEE;
use IEEE.std_logic_1164.all;
use work.constants.all;
use IEEE.NUMERIC_STD.all;

entity vesta is
    generic (
        PC_RST_VAL : std_logic_vector(31 downto 0) := (others => '0');
        NUM_IRQS   : natural := 16
    );
    port (
        clk        : in  std_logic;
        resetn     : in  std_logic;
        sleep      : in  std_logic;
        clk_cpu    : out std_logic;

        -- Memory Interface
        data_addr  : out std_logic_vector(31 downto 0);
        wen        : out std_logic_vector(3 downto 0);
        write_data : out std_logic_vector(31 downto 0);
        read_data  : in  std_logic_vector(31 downto 0);
        mask       : in  std_logic_vector(1 downto 0);

        -- mem_instr : out std_logic; -- Rising edge when instruction has completed
        -- mem_access : out std_logic; -- rising edge when memory access

        -- IRQ Interface
        irq_vector   : in  std_logic_vector(NUM_IRQS-1 downto 0);
        irq_priority : in  std_logic_vector(NUM_IRQS-1 downto 0);
        irq_en       : in  std_logic_vector(NUM_IRQS-1 downto 0);
        irq_recursion_en : in std_logic;
        isr_ret      : out std_logic;

        -- Trap Output
        trap_flag      : out std_logic;

        -- Debug Output
        a0           : out std_logic_vector(31 downto 0)
    );
end entity;

architecture struct of vesta is

    -- ==========================================
    -- Component Declarations
    -- ==========================================
    
    component controller
        port (
            resetn           : in  std_logic;
            op               : in  std_logic_vector(6 downto 0);
            funct3           : in  std_logic_vector(2 downto 0);
            imm12            : in  std_logic_vector(11 downto 0);
            funct7           : in  std_logic_vector(6 downto 0);
            mask             : in  std_logic_vector(1 downto 0);
            Zero             : in  std_logic;
            result_src       : out std_logic_vector(2 downto 0);
            wen              : out std_logic_vector(3 downto 0);
            pc_src           : out std_logic;
            ALU_src          : out std_logic;
            div_op           : out std_logic;
            reg_write        : out std_logic;
            jump             : out std_logic;
            jalr             : out std_logic;
            imm_src          : out std_logic_vector(2 downto 0);
            alu_control      : out std_logic_vector(5 downto 0);
            mem_access_instr : out std_logic;

            isr_ret          : out std_logic;
            sleep_rq         : out std_logic;
            wake_rq          : out std_logic;
            
            
            -- RV32A signals
            amo_op           : out std_logic;
            lr_op            : out std_logic;
            sc_op            : out std_logic;
            fence_op         : out std_logic;
            
            csr_op           : out std_logic_vector(2 downto 0);
            csr_valid        : out std_logic;

            trap             : out std_logic
        );
    end component;

    component datapath
        port (
            clk          : in  std_logic;
            resetn       : in  std_logic;
            pc           : in  std_logic_vector(31 downto 0);
            pc_plus_4    : in  std_logic_vector(31 downto 0);
            result_src   : in  std_logic_vector(2 downto 0);
            pc_src       : in  std_logic;
            ALU_src      : in  std_logic;
            reg_write    : in  std_logic;
            jalr         : in  std_logic;
            imm_src      : in  std_logic_vector(2 downto 0);
            funct3       : in  std_logic_vector(2 downto 0);
            mask         : in  std_logic_vector(1 downto 0);
            alu_control  : in  std_logic_vector(5 downto 0);
            div_start    : in  std_logic;
            amo_phase    : in  std_logic_vector(2 downto 0);  -- 000: normal, 001: AMO_READ, 010: AMO_COMPUTE, 011: AMO_WRITE, 100: SC fail, 101: SC success
            Zero         : out std_logic;
            pc_target    : out std_logic_vector(31 downto 0);
            instr        : in  std_logic_vector(31 downto 0);
            ALU_result   : out std_logic_vector(31 downto 0);
            alu_done     : out std_logic;
            write_data   : out std_logic_vector(31 downto 0);
            read_data    : in  std_logic_vector(31 downto 0);
            -- Stack pointer management for IRQ
            sp_in        : in  std_logic_vector(31 downto 0);
            sp_out       : out std_logic_vector(31 downto 0);
            sp_write_en  : in  std_logic;
            csr_valid    : in  std_logic;
            csr_rdata    : in std_logic_vector(31 downto 0);
            csr_wdata    : out std_logic_vector(31 downto 0);
            a0           : out std_logic_vector(31 downto 0)
        );
    end component;

    component irq_handler
        generic (
            NUM_IRQS   : integer := NUM_IRQS;
            DATA_WIDTH : integer := 32
        );
        port (
            clk             : in  std_logic;
            resetn          : in  std_logic;
            irq             : in  std_logic_vector(NUM_IRQS-1 downto 0);
            irq_en          : in  std_logic_vector(NUM_IRQS-1 downto 0);
            irq_pri         : in  std_logic_vector(NUM_IRQS-1 downto 0);
            irq_recursion_en: in  std_logic;
            irq_active      : out std_logic;
            isr_ret         : in  std_logic;
            irq_save        : out std_logic;
            irq_save_ack    : in  std_logic;
            irq_restore     : out std_logic;
            irq_restore_ack : in  std_logic;
            ivt_jump        : out std_logic;
            ivt_entry       : out std_logic_vector(31 downto 0)
        );
    end component;

    component c_dec
        port (
            resetn        : in  std_logic;
            instr_in      : in  std_logic_vector(31 downto 0);
            instr_out     : out std_logic_vector(31 downto 0);
            is_compressed : out std_logic
        );
    end component;
    
    component csr_unit is
        port (
            clk            : in  std_logic;
            resetn         : in  std_logic;

            -- CSR instruction interface
            csr_addr       : in  std_logic_vector(11 downto 0);
            csr_write_data : in  std_logic_vector(31 downto 0);
            csr_op         : in  std_logic_vector(2 downto 0);
            csr_valid      : in  std_logic;
            csr_read_data  : out std_logic_vector(31 downto 0);

            -- Performance counter input
            inst_retired   : in  std_logic
        );
    end component;

    -- ==========================================
    -- State Machine Definition
    -- ==========================================
    type cpu_state is (
        INITIALIZE,   -- Initial state after reset
        SLEEPING,     -- CPU in sleep mode
        EXECUTE,      -- Normal instruction execution
        MEMORY_WAIT,  -- Wait for memory operation
        DIV_WAIT,     -- Wait for division to complete
        DIV_DONE,     -- Division completed
        IRQ_SV,       -- Save context for IRQ
        IRQ_REST,     -- Restore context from IRQ
        IRQ_JUMP,     -- Jump to interrupt vector
        TRAP_STATE,   -- Trap state for illegal instructions
        -- RV32A atomic states
        AMO_READ,     -- Read phase of atomic operation
        AMO_WRITEBACK,-- Writeback value to rd 
        AMO_COMPUTE,  -- Compute phase of atomic operation
        AMO_WRITE,    -- Write phase of atomic operation
        AMO_COMPLETE, -- Complete AMO operation
        LR_READ,      -- Load-Reserved read
        SC_CHECK,      -- Store-Conditional check and write
        FENCE_WAIT    -- FENCE operation wait state
    );

    signal current_state, next_state : cpu_state;

    -- ==========================================
    -- PC Management Signals
    -- ==========================================
    signal pc, pc_next           : std_logic_vector(31 downto 0);
    signal pc_plus_2, pc_plus_4  : std_logic_vector(31 downto 0);
    signal pc_target              : std_logic_vector(31 downto 0);
    signal pc_next_trad           : std_logic_vector(31 downto 0);  -- Traditional PC next value
    signal pc_next_reg            : std_logic_vector(31 downto 0);  -- Registered PC next
    signal pc_next_trad_reg       : std_logic_vector(31 downto 0);  -- Registered traditional PC next
    signal pc_next_ret            : std_logic_vector(31 downto 0);  -- Return PC after IRQ
    signal pc_next_ret_ltch       : std_logic;                      -- Latch for return PC
    signal pc_en                  : std_logic;                      -- PC update enable
    signal pc_src                 : std_logic;                      -- PC source select

    -- ==========================================
    -- Instruction Handling Signals
    -- ==========================================
    signal instr                  : std_logic_vector(31 downto 0);
    signal instr_curr             : std_logic_vector(31 downto 0);  -- Current instruction being executed
    signal instr_curr_prev        : std_logic_vector(31 downto 0);  -- Previous instruction (for timing)
    signal instr_decomp           : std_logic_vector(31 downto 0);  -- Decompressed instruction
    signal instr_to_decomp        : std_logic_vector(31 downto 0);  -- Instruction to decompress
    signal instr_lower_half       : std_logic_vector(15 downto 0);  -- Lower half for split fetch
    signal instr_upper_half       : std_logic_vector(15 downto 0);  -- Upper half for split fetch
    signal instr_assembled        : std_logic_vector(31 downto 0);  -- Assembled from split fetch
    signal data_addr_reg          : std_logic_vector(31 downto 0);  -- Return PC after IRQ

    -- ==========================================
    -- Compressed Instruction Signals
    -- ==========================================
    signal is_compressed          : std_logic;
    signal is_compressed_cdec     : std_logic;  -- From decompressor (unused)
    signal quadrant_upper         : std_logic_vector(1 downto 0);  -- Upper half instruction type
    signal quadrant_lower         : std_logic_vector(1 downto 0);  -- Lower half instruction type
    signal repeat_if              : std_logic;  -- Repeat instruction fetch flag
    signal repeat_if_req          : std_logic;  -- Request to repeat fetch
    signal clr_repeat_if          : std_logic;  -- Clear repeat fetch flag
    signal ltch_lh_inst           : std_logic;  -- Latch lower half instruction

    -- ==========================================
    -- Control Signals
    -- ==========================================
    signal ALU_src                : std_logic;
    signal jump                   : std_logic;
    signal jalr                   : std_logic;
    signal Zero                   : std_logic;
    signal result_src             : std_logic_vector(2 downto 0);
    signal imm_src                : std_logic_vector(2 downto 0);
    signal alu_control            : std_logic_vector(5 downto 0); -- from control unit
    signal alu_control_dp         : std_logic_vector(5 downto 0); -- to datapath
    signal wen_controller         : std_logic_vector(3 downto 0);
    signal mem_access_controller  : std_logic;
    signal mem_access_instr       : std_logic;
    signal reg_write_ctrl         : std_logic;  -- From controller
    signal reg_write_dp           : std_logic;  -- To datapath
    signal trap                   : std_logic;

    -- ==========================================
    -- ALU and Division Signals
    -- ==========================================
    signal ALU_result             : std_logic_vector(31 downto 0);
    signal alu_done               : std_logic;
    signal is_div_op              : std_logic;
    signal div_start              : std_logic;

    -- ==========================================
    -- Stack Pointer Management
    -- ==========================================
    signal sp_write_data          : std_logic_vector(31 downto 0);  -- New SP value
    signal stack_pointer          : std_logic_vector(31 downto 0);  -- Current SP value
    signal sp_write_en            : std_logic;                      -- SP write enable
    signal write_data_dp          : std_logic_vector(31 downto 0);  -- Write data from datapath

    -- ==========================================
    -- Interrupt Handling Signals
    -- ==========================================
    signal irq_save               : std_logic;
    signal irq_save_int           : std_logic;
    signal irq_save_ack           : std_logic;
    signal irq_restore            : std_logic;
    signal irq_restore_ack        : std_logic;
    signal irq_active             : std_logic;
    signal ivt_jump               : std_logic;
    signal ivt_entry              : std_logic_vector(31 downto 0);

    -- ==========================================
    -- Clock Gating and Power Management
    -- ==========================================
    signal en_clk_cpu             : std_logic;
    -- signal clk_cpu                : std_logic;
    signal sleep_rq               : std_logic;  -- Sleep request from instruction
    signal wake_rq                : std_logic;  -- Wake request from instruction
    signal sleep_cpu              : std_logic;  -- CPU sleep state
    
    -- ==========================================
    -- RV32A Atomic Operation Signals
    -- ==========================================
    signal amo_op                 : std_logic;  -- AMO operation (not LR/SC)
    signal lr_op                  : std_logic;  -- Load-Reserved operation
    signal sc_op                  : std_logic;  -- Store-Conditional operation
    signal fence_op               : std_logic;  -- FENCE instruction indicator
    signal amo_read_data          : std_logic_vector(31 downto 0);  -- Saved read data for AMO
    signal amo_new_data           : std_logic_vector(31 downto 0);  -- Computed data for AMO write
    signal reservation_valid      : std_logic;  -- LR/SC reservation valid
    signal reservation_addr       : std_logic_vector(31 downto 0);  -- LR/SC reservation address
    signal amo_phase              : std_logic_vector(2 downto 0);  -- 000: normal, 001: AMO_READ, 010: AMO_COMPUTE, 011: AMO_WRITE, 100: SC fail, 101: SC success
    signal amo_write_data         : std_logic_vector(31 downto 0);  -- Data to write for AMO operations

    -- ==========================================
    -- RV32SI (RV32ZISCR) CSR Signals
    -- ==========================================
    signal csr_addr               : std_logic_vector(11 downto 0);
    signal csr_rdata              : std_logic_vector(31 downto 0);
    signal csr_wdata              : std_logic_vector(31 downto 0);
    signal csr_op                 : std_logic_vector(2 downto 0);
    signal csr_valid              : std_logic;
    signal en_cg_insret           : std_logic;
    signal inst_retired          : std_logic;

    begin

    -- ==========================================
    -- Signal Assignments
    -- ==========================================
    instr <= read_data;

    -- ==========================================
    -- Clock Gating Logic
    -- ==========================================
    -- Enable CPU clock when:
    -- - IRQ is active (always process interrupts)
    -- - Not in external sleep mode
    -- - Not in SLEEPING state
    en_clk_cpu <= '1' when irq_active = '1' else
                  '0' when sleep = '1' else
                  '0' when current_state = SLEEPING else
                  '1';

    cg_clk_cpu: entity work.ClkGate
        port map (
            ClkIn  => clk,
            En     => en_clk_cpu,
            ClkOut => clk_cpu
        );

    -- Signal for counting how many instructions have retired
    en_cg_insret <= '1' when next_state = EXECUTE else '0';
    cg_insret: entity work.ClkGate
        port map (
            ClkIn  => not clk_cpu,
            En     => en_cg_insret,
            ClkOut => inst_retired
        );

    -- inst_retired <= clk_inst_ret when en_clk_cpu = '1' else '0';


    -- ==========================================
    -- PC Return Value Latching
    -- ==========================================
    -- Latch PC return value when clock is gated off
    pc_next_ret_gt_proc: process(resetn, clk_cpu)
    begin
        if resetn = '0' then
            pc_next_ret_ltch <= '0';
        elsif rising_edge(clk_cpu) then
            if en_clk_cpu = '0' then
                pc_next_ret_ltch <= '1';
            else
                pc_next_ret_ltch <= '0';
            end if;
        end if;
    end process;

    -- Select PC return value based on latch state
    pc_next_ret <= read_data when pc_next_ret_ltch = '0' else pc_next_ret;

    -- ==========================================
    -- RV32A Reservation Management
    -- ==========================================
    reservation_proc: process(clk_cpu, resetn)
    begin
        if resetn = '0' then
            reservation_valid <= '0';
            reservation_addr <= (others => '0');
            amo_read_data <= (others => '0');
        elsif rising_edge(clk_cpu) then
            -- Set reservation on LR
            if current_state = LR_READ then
                reservation_valid <= '1';
                reservation_addr <= ALU_result;
            -- Clear reservation on SC, interrupt, or context switch
            elsif current_state = SC_CHECK or current_state = IRQ_SV then
                reservation_valid <= '0';
            end if;
            
            -- Save read data during AMO read phase
            if current_state = AMO_READ then
                amo_read_data <= read_data;
            elsif current_state = LR_READ then
                amo_read_data <= read_data;
            end if;
            if current_state = AMO_COMPUTE then
                amo_write_data <= ALU_result;  -- Computed data for AMO write
            end if;
        end if;
    end process;

    -- ==========================================
    -- State Machine Sequential Logic
    -- ==========================================
    state_reg: process(clk_cpu, resetn)
    begin
        if resetn = '0' then
            current_state <= EXECUTE;
            repeat_if <= '0';
            pc <= PC_RST_VAL;
            -- instr_curr_prev <= nop;
            instr_lower_half <= (others => '0');
            pc_next_reg <= PC_RST_VAL;
            pc_next_trad_reg <= PC_RST_VAL;
            irq_restore_ack <= '0';
            data_addr_reg <= (others => '0');
        elsif rising_edge(clk_cpu) then
            -- Update state machine
            current_state <= next_state;
            -- instr_curr_prev <= instr_curr;
            pc_next_reg <= pc_next;
            pc_next_trad_reg <= pc_next_trad;
            data_addr_reg <= data_addr;

            -- IRQ restore acknowledgment (1-cycle delay)
            irq_restore_ack <= irq_restore;

            -- Update PC when enabled
            if pc_en = '1' then
                pc <= pc_next;
            end if;

            -- Handle repeat instruction fetch
            if repeat_if_req = '1' then
                repeat_if <= '1';
            elsif clr_repeat_if = '1' then
                repeat_if <= '0';
            end if;

            -- Latch lower half of instruction for split fetch
            if ltch_lh_inst = '1' then
                instr_lower_half <= instr(31 downto 16);
            end if;
        end if;
    end process;

    -- Added - experienced some timing issues when instr_curr assigned to instr_curr_prev - advance by half cycle
    state_reg_fe: process(clk_cpu, resetn)
    begin
        if resetn = '0' then
            instr_curr_prev <= nop;
        elsif rising_edge(clk_cpu) then
            instr_curr_prev <= instr_curr;
        end if;
    end process;

    -- ==========================================
    -- PC Calculation Logic
    -- ==========================================
    pc_plus_2 <= std_logic_vector(unsigned(pc) + 2);
    pc_plus_4 <= std_logic_vector(unsigned(pc) + 4);

    -- ==========================================
    -- Instruction Type Detection
    -- ==========================================
    quadrant_upper <= instr(17 downto 16);
    quadrant_lower <= instr(1 downto 0);
    instr_upper_half <= instr(15 downto 0);
    instr_assembled <= instr_upper_half & instr_lower_half;

    -- ==========================================
    -- Instruction Assembly for Decompression
    -- ==========================================
    -- Select instruction to decompress based on fetch state
    instr_to_decomp <= instr_assembled when current_state = EXECUTE and pc(1) = '1' and repeat_if = '1' else
                       x"0000" & instr(31 downto 16) when current_state = EXECUTE and pc(1) = '1' and is_compressed = '1' else
                       instr;

    -- ==========================================
    -- Current Instruction Selection
    -- ==========================================
    -- Multiplexer for selecting current instruction based on state and alignment
    instr_curr <= nop when (resetn = '0' or current_state = INITIALIZE) else
                  instr when (current_state = IRQ_SV) else  -- IVT entries are never compressed
                  instr_decomp when (current_state = EXECUTE and pc(1) = '1' and repeat_if = '1') else
                  instr_curr_prev when (current_state = EXECUTE and pc(1) = '1' and quadrant_upper = "11" and repeat_if = '0') else
                  instr_decomp when (current_state = EXECUTE and pc(1) = '1' and quadrant_upper /= "11") else
                  instr when (current_state = EXECUTE and pc(1) = '0' and quadrant_lower = "11") else
                  instr_decomp when (current_state = EXECUTE and pc(1) = '0' and quadrant_lower /= "11") else
                  instr_curr_prev when (current_state = MEMORY_WAIT) else
                  instr_curr_prev when (current_state = DIV_WAIT) else
                  instr_curr_prev when (current_state = DIV_DONE) else
                  instr_curr_prev when (current_state = IRQ_SV) else
                  instr_curr_prev when (current_state = IRQ_REST) else
                  instr_curr_prev when (current_state = SLEEPING) else
                  instr_curr_prev when (current_state = AMO_READ) else  -- Keep instruction during AMO
                  instr_curr_prev when (current_state = AMO_WRITEBACK) else
                  instr_curr_prev when (current_state = AMO_COMPUTE) else
                  instr_curr_prev when (current_state = AMO_COMPLETE) else -- TODO: Added
                  instr_curr_prev when (current_state = AMO_WRITE) else
                  instr_curr_prev when (current_state = LR_READ) else
                  instr_curr_prev when (current_state = SC_CHECK) else
                  instr_decomp;

    -- ==========================================
    -- PC Next Traditional Calculation
    -- ==========================================
    -- Calculate next PC for normal operation (no interrupt)
    -- Hold PC during atomic operations
    pc_next_trad <= PC_RST_VAL when (resetn = '0' or current_state = INITIALIZE) else
                    pc_target when ((current_state = EXECUTE or current_state = IRQ_SV) and pc(1) = '1' and repeat_if = '1' and pc_src = '1') else
                    pc_plus_4 when (current_state = EXECUTE and pc(1) = '1' and repeat_if = '1' and pc_src = '0') else
                    pc_plus_2 when (current_state = EXECUTE and pc(1) = '1' and quadrant_upper = "11" and repeat_if = '0') else
                    pc_target when (current_state = EXECUTE and pc(1) = '1' and quadrant_upper /= "11" and pc_src = '1') else
                    pc_plus_2 when (current_state = EXECUTE and pc(1) = '1' and quadrant_upper /= "11" and pc_src = '0') else
                    pc_target when ((current_state = EXECUTE or current_state = IRQ_SV) and pc(1) = '0' and quadrant_lower = "11" and pc_src = '1') else
                    pc_plus_4 when (current_state = EXECUTE and pc(1) = '0' and quadrant_lower = "11" and pc_src = '0') else
                    pc_target when (current_state = EXECUTE and pc(1) = '0' and quadrant_lower /= "11" and pc_src = '1') else
                    pc_plus_2 when (current_state = EXECUTE and pc(1) = '0' and quadrant_lower /= "11" and pc_src = '0') else
                    pc_next_trad_reg;  -- Hold value for other states including atomic operations

    -- ==========================================
    -- PC Next Final Selection
    -- ==========================================
    pc_next <= ivt_entry   when (current_state = IRQ_JUMP) else
               pc_next_ret when (current_state = IRQ_REST) else
               pc_next_reg when (current_state = SLEEPING) else
               pc_next_reg when (current_state = IRQ_SV) else
               pc_next_reg when (current_state = AMO_READ or current_state = AMO_WRITEBACK or 
                                current_state = AMO_COMPUTE or current_state = AMO_WRITE) else
               pc_next_reg when (current_state = LR_READ or current_state = SC_CHECK) else
               pc_next_trad;

    -- ==========================================
    -- Memory Interface Address Selection
    -- ==========================================
    data_addr <= ALU_Result when (mem_access_instr = '1' or 
                                  current_state = AMO_READ or current_state = AMO_WRITE or 
                                  current_state = LR_READ or current_state = SC_CHECK) else
                 std_logic_vector(unsigned(stack_pointer) - 4) when (current_state = IRQ_SV) else
                 stack_pointer when next_state = IRQ_REST else
                 pc_next;

    -- ==========================================
    -- Memory Write Data Selection
    -- ==========================================
    -- For AMO operations, use computed result; for SC, use rs2 data
    write_data <= pc_next when (current_state = IRQ_SV) else 
                  amo_write_data when (current_state = AMO_WRITE) else  -- Use ALU result for AMO write
                  write_data_dp;  -- Use rs2 for normal stores and SC

    -- ==========================================
    -- Atomic Operation Phase Signal - Pass to Datapath to use ALU for computation
    -- ==========================================
    amo_phase <=    "001" when current_state = AMO_READ or current_state = LR_READ else  -- Reading address
                    "010" when current_state = AMO_COMPUTE else  -- Computing with memory data
                    "011" when current_state = AMO_WRITE else     -- Writing result back
                    "100" when current_state = SC_CHECK and reservation_valid = '0' else  -- SC failed
                    "101" when current_state = SC_CHECK and reservation_valid = '1' else  -- SC succeeded
                    "000";  -- Normal operation


    

    -- ==========================================
    -- FSM Next State Logic (Combinational)
    -- ==========================================
    next_state_logic: process(resetn, current_state, pc, instr, quadrant_upper, quadrant_lower, 
                             repeat_if, instr_upper_half, instr_lower_half, instr_decomp, 
                             irq_save, mem_access_controller, is_div_op, pc_src, pc_target, 
                             pc_plus_4, pc_plus_2, alu_done, irq_save_ack, isr_ret, 
                             reg_write_ctrl, wen_controller, sleep_rq, wake_rq, trap, 
                             stack_pointer, sleep_cpu, reg_write_dp, amo_op, lr_op, sc_op,
                             reservation_valid, reservation_addr, ALU_result)
    begin
        if resetn = '0' then
            -- Reset all control signals
            next_state <= INITIALIZE;
            mem_access_instr <= '0';
            reg_write_dp <= '0';
            repeat_if_req <= '0';
            clr_repeat_if <= '0';
            wen <= wen_controller;
            div_start <= '0';
            ltch_lh_inst <= '0';
            pc_en <= '1';
            sp_write_en <= '0';
            irq_save_ack <= '0';
            is_compressed <= '0';
            trap_flag <= '0';
            
        else
            -- Default signal values
            pc_en <= '1';
            mem_access_instr <= '0';
            reg_write_dp <= reg_write_ctrl;
            repeat_if_req <= '0';
            clr_repeat_if <= '0';
            wen <= wen_controller;
            div_start <= '0';
            ltch_lh_inst <= '0';
            sp_write_en <= '0';
            irq_save_ack <= '0';
            trap_flag <= '0';

            case current_state is
                -- ==========================================
                -- INITIALIZE State
                -- ==========================================
                when INITIALIZE =>
                    next_state <= EXECUTE;
                    mem_access_instr <= '0';
                    reg_write_dp <= reg_write_ctrl;
                    div_start <= '0';
                    wen <= wen_controller;
                    is_compressed <= '0';

                -- ==========================================
                -- EXECUTE State - Main instruction execution
                -- ==========================================
                when EXECUTE =>
                    if pc(1) = '1' then
                        -- Current instruction on half-word boundary
                        if quadrant_upper = "11" or repeat_if = '1' then
                            -- Instruction not compressed or fetching upper half
                            is_compressed <= '0';
                            
                            if repeat_if = '1' then
                                -- Completing split fetch of 32-bit instruction
                                clr_repeat_if <= '1';
                                
                                -- Determine next state based on instruction type
                                if trap = '1' then
                                    next_state <= TRAP_STATE;
                                    pc_en <= '0';
                                elsif sleep_rq = '1' then
                                    next_state <= SLEEPING;
                                    pc_en <= '0';
                                elsif lr_op = '1' then
                                    -- Load-Reserved operation
                                    mem_access_instr <= '1';
                                    next_state <= LR_READ;
                                    pc_en <= '0';
                                    reg_write_dp <= '0';
                                elsif sc_op = '1' then
                                    -- Store-Conditional operation
                                    mem_access_instr <= '1';
                                    next_state <= SC_CHECK;
                                    pc_en <= '0';
                                    reg_write_dp <= '0';
                                elsif amo_op = '1' then
                                    -- Atomic memory operation
                                    mem_access_instr <= '1';
                                    next_state <= AMO_READ;
                                    pc_en <= '0';
                                    reg_write_dp <= '0';
                                    wen <= (others => '1'); -- TODO - added
                                elsif fence_op = '1' then
                                    next_state <= FENCE_WAIT;
                                    pc_en <= '1';
                                elsif mem_access_controller = '1' then
                                    mem_access_instr <= '1';
                                    next_state <= MEMORY_WAIT;
                                    pc_en <= '0';
                                    reg_write_dp <= '0';
                                elsif is_div_op = '1' then
                                    next_state <= DIV_WAIT;
                                    pc_en <= '0';
                                elsif irq_save = '1' then
                                    next_state <= IRQ_SV;
                                    pc_en <= '0';
                                elsif isr_ret = '1' then
                                    next_state <= IRQ_REST;
                                else
                                    next_state <= EXECUTE;
                                end if;
                            else
                                -- Need to fetch upper half of instruction
                                ltch_lh_inst <= '1';
                                repeat_if_req <= '1';
                                next_state <= EXECUTE;
                                reg_write_dp <= '0';
                                pc_en <= '0';
                                wen <= (others => '1');
                            end if;
                        else
                            
                            -- Compressed instruction on half-word boundary
                            is_compressed <= '1';
                            if trap = '1' then
                                next_state <= TRAP_STATE;
                                pc_en <= '0';
                            elsif mem_access_controller = '1' then
                                mem_access_instr <= '1';
                                next_state <= MEMORY_WAIT;
                                pc_en <= '0';
                                reg_write_dp <= '0';
                            elsif is_div_op = '1' then
                                next_state <= DIV_WAIT;
                                pc_en <= '0';
                            elsif irq_save = '1' then
                                next_state <= IRQ_SV;
                                pc_en <= '0';
                            elsif isr_ret = '1' then
                                next_state <= IRQ_REST;
                            else
                                next_state <= EXECUTE;
                            end if;
                        end if;
                    else
                        -- Full word boundary
                        if quadrant_lower = "11" then
                            -- Not compressed
                            is_compressed <= '0';
                            
                            if trap = '1' then
                                next_state <= TRAP_STATE;
                                pc_en <= '0';
                            elsif sleep_rq = '1' then
                                next_state <= SLEEPING;
                                pc_en <= '0';
                            elsif lr_op = '1' then
                                -- Load-Reserved operation
                                mem_access_instr <= '1';
                                next_state <= LR_READ;
                                pc_en <= '0';
                                reg_write_dp <= '0';
                            elsif sc_op = '1' then
                                -- Store-Conditional operation
                                mem_access_instr <= '1';
                                next_state <= SC_CHECK;
                                pc_en <= '0';
                                reg_write_dp <= '0';
                            elsif amo_op = '1' then
                                -- Atomic memory operation
                                mem_access_instr <= '1';
                                next_state <= AMO_READ;
                                pc_en <= '0';
                                reg_write_dp <= '0';
                                wen <= (others => '1'); -- TODO - added
                            elsif fence_op = '1' then
                                next_state <= FENCE_WAIT;
                                pc_en <= '1';  
                            elsif mem_access_controller = '1' then
                                mem_access_instr <= '1';
                                next_state <= MEMORY_WAIT;
                                reg_write_dp <= '0';
                                pc_en <= '0';
                            elsif is_div_op = '1' then
                                next_state <= DIV_WAIT;
                                pc_en <= '0';
                            elsif irq_save = '1' then
                                next_state <= IRQ_SV;
                                pc_en <= '0';
                            elsif isr_ret = '1' then
                                next_state <= IRQ_REST;
                            else
                                next_state <= EXECUTE;
                            end if;
                        else
                            -- Compressed instruction
                            is_compressed <= '1';
                            if trap = '1' then
                                next_state <= TRAP_STATE;
                                pc_en <= '0';
                            elsif mem_access_controller = '1' then
                                mem_access_instr <= '1';
                                next_state <= MEMORY_WAIT;
                                reg_write_dp <= '0';
                                pc_en <= '0';
                            elsif is_div_op = '1' then
                                next_state <= DIV_WAIT;
                                pc_en <= '0';
                            elsif irq_save = '1' then
                                next_state <= IRQ_SV;
                                pc_en <= '0';
                            else
                                next_state <= EXECUTE;
                            end if;
                        end if;
                    end if;

                -- ==========================================
                -- AMO_READ State - Read phase of atomic operation
                -- ==========================================
                when AMO_READ =>
                    pc_en <= '0';
                    wen <= (others => '1');  -- Read operation
                    mem_access_instr <= '1';
                    reg_write_dp <= '0';  -- Don't write yet
                    next_state <= AMO_WRITEBACK;
                -- ==========================================
                -- AMO_WRITEBACK State - Write value to rd
                -- ==========================================
                when AMO_WRITEBACK =>
                    pc_en <= '0';
                    wen <= (others => '1');  -- No memory access
                    mem_access_instr <= '0';
                    reg_write_dp <= '1';  -- Write old value to rd
                    next_state <= AMO_COMPUTE;

                -- ==========================================
                -- AMO_COMPUTE State - Compute phase of atomic operation
                -- ==========================================
                when AMO_COMPUTE =>
                    pc_en <= '0';
                    wen <= (others => '1');  -- No memory access
                    mem_access_instr <= '0';
                    reg_write_dp <= '0';  -- Already wrote in AMO_WRITEBACK
                    next_state <= AMO_WRITE;

                -- ==========================================
                -- AMO_WRITE State - Write phase of atomic operation
                -- ==========================================
                when AMO_WRITE =>
                    pc_en <= '1';  -- Ready to fetch next instruction
                    wen <= "0000";  -- Write word
                    mem_access_instr <= '1';
                    reg_write_dp <= '0';
                    
                    if irq_save = '1' then
                        next_state <= IRQ_SV;
                        pc_en <= '0';
                    else
                        -- Need to fetch next instruction from memory
                        next_state <= AMO_COMPLETE; 
                    end if;

                -- ==========================================
                -- AMO COMPLETE State - Fetch next instruction
                -- ==========================================
                when AMO_COMPLETE =>
                    pc_en <= '1';  -- Ready to fetch next instruction
                    wen <= (others => '1');  -- No memory access
                    mem_access_instr <= '0';
                    reg_write_dp <= '0';
                    if irq_save = '1' then
                        next_state <= IRQ_SV;
                        pc_en <= '0';
                    else
                        next_state <= EXECUTE;
                    end if;

                -- ==========================================
                -- LR_READ State - Load-Reserved read
                -- ==========================================
                when LR_READ =>
                    pc_en <= '1';  -- Ready to fetch next instruction
                    wen <= (others => '1');  -- Read operation
                    mem_access_instr <= '1';
                    reg_write_dp <= '1';  -- Write value to rd
                    
                    if irq_save = '1' then
                        next_state <= IRQ_SV;
                        pc_en <= '0';
                    else
                        next_state <= AMO_COMPLETE;
                    end if;

                -- ==========================================
                -- SC_CHECK State - Store-Conditional check and write
                -- ==========================================
                when SC_CHECK =>
                    pc_en <= '1';  -- Ready to fetch next instruction
                    mem_access_instr <= '1';
                    reg_write_dp <= '1';  -- Write success/fail to rd
                    
                    -- Only write if reservation is valid and addresses match
                    if reservation_valid = '1' and reservation_addr = ALU_result then
                        wen <= "0000";  -- Write word (success)
                    else
                        wen <= (others => '1');  -- No write (fail)
                    end if;
                    
                    if irq_save = '1' then
                        next_state <= IRQ_SV;
                        pc_en <= '0';
                    else
                        next_state <= AMO_COMPLETE;
                    end if;
                -- ==========================================
                -- FENCE State - Fence operation
                -- ==========================================
                -- Note - for single core - fence may be treated as nop
                when FENCE_WAIT =>
                    next_state <= EXECUTE;
                    pc_en <= '1';
                    WEN <= (others => '1');  -- No memory write
                    reg_write_dp <= '0';     -- No register write

                -- ==========================================
                -- MEMORY_WAIT State
                -- ==========================================
                when MEMORY_WAIT =>
                    if irq_save = '1' then
                        next_state <= IRQ_SV;
                        pc_en <= '0';
                    elsif isr_ret = '1' then
                        next_state <= IRQ_REST;
                        pc_en <= '0';
                    else
                        next_state <= EXECUTE;
                        pc_en <= '1';
                    end if;
                    wen <= (others => '1');  -- Disable write

                -- ==========================================
                -- DIV_WAIT State
                -- ==========================================
                when DIV_WAIT =>
                    pc_en <= '0';
                    reg_write_dp <= '0';
                    if alu_done = '1' then
                        next_state <= DIV_DONE;
                        div_start <= '0';
                    else
                        next_state <= DIV_WAIT;
                        div_start <= '1';
                    end if;

                -- ==========================================
                -- DIV_DONE State
                -- ==========================================
                when DIV_DONE =>
                    pc_en <= '1';
                    
                    if irq_save = '1' then
                        next_state <= IRQ_SV;
                        pc_en <= '0';
                    elsif isr_ret = '1' then
                        next_state <= IRQ_REST;
                    else
                        next_state <= EXECUTE;
                    end if;

                -- ==========================================
                -- IRQ_SV State - Save context for interrupt
                -- ==========================================
                when IRQ_SV =>
                    wen <= (others => '0');  -- Enable write to save PC
                    
                    -- Update stack pointer
                    sp_write_en <= '1';
                    sp_write_data <= std_logic_vector(unsigned(stack_pointer) - 4);
                    
                    pc_en <= '0';
                    next_state <= IRQ_JUMP;

                -- ==========================================
                -- IRQ_JUMP State - Jump to interrupt vector
                -- ==========================================
                when IRQ_JUMP =>
                    irq_save_ack <= '1';
                    pc_en <= '1';  -- Load IVT entry
                    wen <= (others => '1');
                    next_state <= EXECUTE;

                -- ==========================================
                -- IRQ_REST State - Restore context from interrupt
                -- ==========================================
                when IRQ_REST =>
                    if irq_save = '1' then
                        -- Nested interrupt
                        next_state <= IRQ_SV;
                        pc_en <= '0';
                    elsif sleep_cpu = '1' then
                        -- Return to sleep after interrupt
                        next_state <= SLEEPING;
                        pc_en <= '0';
                        wen <= (others => '1');
                        sp_write_en <= '1';
                        sp_write_data <= std_logic_vector(unsigned(stack_pointer) + 4);
                    else
                        -- Return to normal execution
                        next_state <= EXECUTE;
                        wen <= (others => '1');
                        sp_write_en <= '1';
                        sp_write_data <= std_logic_vector(unsigned(stack_pointer) + 4);
                        pc_en <= '1';
                    end if;

                -- ==========================================
                -- SLEEPING State
                -- ==========================================
                when SLEEPING =>
                    pc_en <= '0';
                    
                    if irq_save = '1' then
                        next_state <= IRQ_SV;
                    else
                        next_state <= SLEEPING;
                    end if;
                
                -- ==========================================
                -- TRAP State
                -- ==========================================
                when TRAP_STATE =>
                    pc_en <= '0';
                    reg_write_dp <= '0';
                    next_state <= TRAP_STATE;
                    trap_flag <= '1';

                -- ==========================================
                -- Default Case
                -- ==========================================
                when others =>
                    next_state <= EXECUTE;
                    reg_write_dp <= reg_write_dp;
            end case;
        end if;
    end process;

    -- ==========================================
    -- Sleep/Wake Control Logic
    -- ==========================================
    -- Track CPU sleep state based on custom instructions
    process(clk, resetn)
    begin
        if resetn = '0' then
            sleep_cpu <= '0';
        elsif rising_edge(clk) then
            if wake_rq = '1' then
                sleep_cpu <= '0';
            elsif sleep_rq = '1' then
                sleep_cpu <= '1';
            end if;
        end if;
    end process;

    -- ==========================================
    -- Controller Instance
    -- ==========================================
    controller_inst: controller
        port map (
            resetn           => resetn,
            op               => instr_curr(6 downto 0),
            funct3           => instr_curr(14 downto 12),
            funct7           => instr_curr(31 downto 25),
            imm12            => instr_curr(31 downto 20),
            mask             => mask,
            Zero             => Zero,
            result_src       => result_src,
            wen              => wen_controller,
            pc_src           => pc_src,
            ALU_src          => ALU_src,
            div_op           => is_div_op,
            reg_write        => reg_write_ctrl,
            jump             => jump,
            jalr             => jalr,
            imm_src          => imm_src,
            alu_control      => alu_control,
            isr_ret          => isr_ret,
            sleep_rq         => sleep_rq,
            wake_rq          => wake_rq,
            mem_access_instr => mem_access_controller,
            trap             => trap,
            amo_op           => amo_op,
            lr_op            => lr_op,
            sc_op            => sc_op,
            fence_op         => fence_op,
            csr_op           => csr_op,
            csr_valid        => csr_valid
        );

    -- ==========================================
    -- IRQ Ready Process
    -- ==========================================
    -- Signal IRQ handler when ready to process interrupt
    irq_rdy_proc: process(clk_cpu)
    begin
        if rising_edge(clk_cpu) then
            if (next_state = IRQ_SV) then
                irq_save_int <= '1';
            else
                irq_save_int <= '0';
            end if;
        end if;
    end process;



    alu_control_dp <=   "001011" when (current_state = AMO_READ or current_state = AMO_WRITE) else 
                        "001010" when (current_state = SC_CHECK) else -- ALU passes b
                        alu_control;

    -- ==========================================
    -- Component Instantiations
    -- ==========================================
    datapath_inst: datapath
        port map (
            clk         => clk_cpu,
            resetn      => resetn,
            pc          => pc,
            pc_plus_4   => pc_plus_4,
            result_src  => result_src,
            pc_src      => pc_src,
            ALU_src     => ALU_src,
            reg_write   => reg_write_dp,
            jalr        => jalr,
            imm_src     => imm_src,
            funct3      => instr_curr(14 downto 12),
            mask        => mask,
            alu_control => alu_control_dp,
            div_start   => div_start,
            amo_phase   => amo_phase,
            Zero        => Zero,
            pc_target   => pc_target,
            instr       => instr_curr,
            ALU_result  => ALU_result,
            alu_done    => alu_done,
            write_data  => write_data_dp,
            read_data   => read_data, --TODO
            sp_in       => sp_write_data,
            sp_out      => stack_pointer,
            sp_write_en => sp_write_en,
            csr_valid   => csr_valid,
            csr_rdata   => csr_rdata,
            csr_wdata   => csr_wdata,
            a0          => a0
        );

    irq_handler_inst: irq_handler
        generic map (
            NUM_IRQS   => NUM_IRQS,
            DATA_WIDTH => 32
        )
        port map (
            clk             => clk,
            resetn          => resetn,
            irq             => irq_vector,
            irq_en          => irq_en,
            irq_pri         => irq_priority,
            irq_recursion_en => irq_recursion_en,
            irq_active      => irq_active,
            isr_ret         => isr_ret,
            irq_save        => irq_save,
            irq_save_ack    => irq_save_ack,
            irq_restore     => irq_restore,
            irq_restore_ack => irq_restore_ack,
            ivt_jump        => ivt_jump,
            ivt_entry       => ivt_entry
        );

    c_dec_inst: c_dec
        port map (
            resetn        => resetn,
            instr_in      => instr_to_decomp,
            instr_out     => instr_decomp,
            is_compressed => is_compressed_cdec
        );

 
    csr_addr <= instr_curr(31 downto 20);

    csr_unit_inst : csr_unit
        port map (
            clk            => clk,
            resetn         => resetn,
            csr_addr       => csr_addr,
            csr_write_data => csr_wdata, 
            csr_op         => csr_op,
            csr_valid      => csr_valid,
            csr_read_data  => csr_rdata,
            inst_retired   => inst_retired
        );

end architecture;


