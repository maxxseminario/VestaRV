library IEEE;
use IEEE.std_logic_1164.all;
use work.constants.all;
use IEEE.NUMERIC_STD.all;

entity vesta is
    generic (
        PC_RST_VAL : std_logic_vector(XLEN-1 downto 0) := (others => '0');
        NUM_IRQS   : natural := 16;

        -- Core ISA feature switches (config-driven via make chip; defaults =
        -- the full RV32IMAC+Zba/Zbb/Zbs/Zbc core so existing instantiations
        -- are unchanged). A disabled extension's instructions take the
        -- illegal-instruction trap path and its hardware (multiplier, the
        -- iterative divider, c_dec, Zb* ALU logic) is pruned at elaboration.
        -- The read-only misa CSR (0x301) advertises the enabled set.
        ENABLE_MUL        : boolean := true;   -- M: MUL/MULH/MULHU/MULHSU
        ENABLE_DIV        : boolean := true;   -- M: DIV/DIVU/REM/REMU + div unit
        ENABLE_ATOMICS    : boolean := true;   -- A: LR/SC + AMOs
        ENABLE_COMPRESSED : boolean := true;   -- C: 16-bit instructions (c_dec)
        ENABLE_BITMANIP   : boolean := true;   -- Zba/Zbb/Zbs/Zbc
        -- X0 ISA-extension scaffolding: all default false, zero behavioral change.
        -- Fanned out to the sub-blocks that will consume them (maindec/alu/c_dec/
        -- csr_unit); ZAWRS/ZACAS/ZABHA/ZIHINT are consumed at THIS (FSM/sequencer)
        -- level from their phase on. -- consumed from phase X<n> on; scaffolded X0
        ENABLE_ZICOND     : boolean := false;  -- X1 (Zicond): consumed from phase X1 on; scaffolded X0
        ENABLE_ZCB        : boolean := false;  -- X1 (Zcb): consumed from phase X1 on; scaffolded X0
        ENABLE_ZIMOP      : boolean := false;  -- X1 (Zimop/Zcmop): consumed from phase X1 on; scaffolded X0
        ENABLE_ZIHINT     : boolean := false;  -- X1 (Zihint): consumed from phase X1 on; scaffolded X0
        ENABLE_ZIHPM      : boolean := false;  -- X1 (Zihpm): consumed from phase X1 on; scaffolded X0
        ENABLE_ZAWRS      : boolean := false;  -- X1 (Zawrs): consumed from phase X1 on; scaffolded X0
        ENABLE_ZABHA      : boolean := false;  -- X2 (Zabha): consumed from phase X2 on; scaffolded X0
        ENABLE_ZACAS      : boolean := false;  -- X2 (Zacas): consumed from phase X2 on; scaffolded X0
        ENABLE_ZBKB       : boolean := false;  -- X3 (Zbkb): consumed from phase X3 on; scaffolded X0
        ENABLE_ZBKC       : boolean := false;  -- X3 (Zbkc): consumed from phase X3 on; scaffolded X0
        ENABLE_ZBKX       : boolean := false;  -- X3 (Zbkx): consumed from phase X3 on; scaffolded X0
        ENABLE_ZKN        : boolean := false;  -- X3 (Zkn): consumed from phase X3 on; scaffolded X0
        ENABLE_ZFINX      : boolean := false   -- X4 (Zfinx): consumed from phase X4 on; scaffolded X0
    );
    port (
        clk        : in  std_logic;
        resetn     : in  std_logic;
        sleep      : in  std_logic;
        clk_cpu    : out std_logic;

        -- M13: unique per-hart ID (mhartid CSR) as a PORT (was the HARTID
        -- generic) — all four hart tiles share ONE netlist; wired per instance.
        hart_id    : in  std_logic_vector(XLEN-1 downto 0) := (others => '0');

        -- Memory Interface
        data_addr  : out std_logic_vector(XLEN-1 downto 0);
        wen        : out std_logic_vector(XLEN_BYTES-1 downto 0);
        write_data : out std_logic_vector(XLEN-1 downto 0);
        read_data  : in  std_logic_vector(XLEN-1 downto 0);
        mask       : in  std_logic_vector(1 downto 0);
        mem_ready  : in  std_logic := '1';                    -- Memory back-pressure; '0' stalls the core (freezes clk_cpu). Defaults '1' for single-master use.

        -- Global LR/SC interface (M4b; defaults keep single-master use a no-op).
        -- lr_sc_bus tags the CURRENT memory access: "01" = LR read, "10" = SC
        -- write attempt (local reservation check passed), "00" = plain access.
        -- sc_fail_ext: external (resv_unit) SC verdict for a SHARED SC — '1'
        -- forces the SC rd result to fail (the shared write was suppressed
        -- upstream). Must be stable by the end of the SC_CHECK cycle; for a
        -- stalled shared SC it is latched from the arbiter done, well before
        -- the core's release edge.
        lr_sc_bus   : out std_logic_vector(1 downto 0);
        sc_fail_ext : in  std_logic := '0';

        -- X1 Zawrs: this hart's GLOBAL reservation-valid level from resv_unit
        -- (registered through the tile boundary). A hart stalled in wrs.nto/
        -- wrs.sto wakes when this drops to '0' (a foreign committed store killed
        -- the reservation — the exact snoop the LR/SC unit already relies on).
        -- Defaults '1' so single-master tops (no resv_unit) treat every
        -- reservation as live and fall back to the interrupt/timeout wakes.
        resv_valid_ext : in  std_logic := '1';

        -- M8: cross-hart AMO atomicity. '1' for the whole AMO read-modify-write
        -- flow (the EXECUTE dispatch cycle — where the shared READ transaction
        -- runs, like LR's — through AMO_WRITE, where the WRITE transaction
        -- runs). The MCU-level mp_arbiter samples it at the read's completion
        -- and HOLDS THE GRANT pinned to this hart until the write commits
        -- (grant-locking), making shared AMOs atomic across masters. Leave
        -- open / unconnected in single-master tops.
        amo_lock    : out std_logic;

        -- IRQ Interface
        irq_vector   : in  std_logic_vector(NUM_IRQS-1 downto 0);
        irq_priority : in  std_logic_vector(NUM_IRQS-1 downto 0);
        irq_en       : in  std_logic_vector(NUM_IRQS-1 downto 0);
        irq_recursion_en : in std_logic;
        isr_ret      : out std_logic;

        -- Trap Output
        trap_flag      : out std_logic;

        -- Debug Output
        a0           : out std_logic_vector(XLEN-1 downto 0)
    );
end entity;

architecture struct of vesta is

    -- ==========================================
    -- Component Declarations
    -- ==========================================
    
    component controller
        generic (
            ENABLE_MUL      : boolean := true;
            ENABLE_DIV      : boolean := true;
            ENABLE_ATOMICS  : boolean := true;
            ENABLE_BITMANIP : boolean := true;
            -- X0 scaffolding: the subset maindec will consume (default false)
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
        port (
            resetn           : in  std_logic;
            op               : in  std_logic_vector(6 downto 0);
            funct3           : in  std_logic_vector(2 downto 0);
            imm12            : in  std_logic_vector(11 downto 0);
            funct7           : in  std_logic_vector(6 downto 0);
            mask             : in  std_logic_vector(1 downto 0);
            Zero             : in  std_logic;
            result_src       : out std_logic_vector(2 downto 0);
            wen              : out std_logic_vector(XLEN_BYTES-1 downto 0);
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
            wrs_op           : out std_logic;
            wrs_sto          : out std_logic;


            -- RV32A signals
            amo_op           : out std_logic;
            lr_op            : out std_logic;
            sc_op            : out std_logic;
            fence_op         : out std_logic;
            pause_hint       : out std_logic;

            csr_op           : out std_logic_vector(2 downto 0);
            csr_valid        : out std_logic;

            trap             : out std_logic
        );
    end component;

    component datapath
        generic (
            ENABLE_MUL      : boolean := true;
            ENABLE_DIV      : boolean := true;
            ENABLE_ATOMICS  : boolean := true;
            ENABLE_BITMANIP : boolean := true;
            -- X0 scaffolding: the subset alu will consume (default false)
            ENABLE_ZICOND   : boolean := false;
            ENABLE_ZBKB     : boolean := false;
            ENABLE_ZBKC     : boolean := false;
            ENABLE_ZBKX     : boolean := false;
            ENABLE_ZKN      : boolean := false;
            ENABLE_ZFINX    : boolean := false
        );
        port (
            clk          : in  std_logic;
            resetn       : in  std_logic;
            pc           : in  std_logic_vector(XLEN-1 downto 0);
            pc_plus_4    : in  std_logic_vector(XLEN-1 downto 0);
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
            pc_target    : out std_logic_vector(XLEN-1 downto 0);
            instr        : in  std_logic_vector(ILEN-1 downto 0);
            ALU_result   : out std_logic_vector(XLEN-1 downto 0);
            rs1_value    : out std_logic_vector(XLEN-1 downto 0);
            alu_done     : out std_logic;
            write_data   : out std_logic_vector(XLEN-1 downto 0);
            read_data    : in  std_logic_vector(XLEN-1 downto 0);
            -- Stack pointer management for IRQ
            sp_in        : in  std_logic_vector(XLEN-1 downto 0);
            sp_out       : out std_logic_vector(XLEN-1 downto 0);
            sp_write_en  : in  std_logic;
            csr_valid    : in  std_logic;
            csr_rdata    : in std_logic_vector(XLEN-1 downto 0);
            csr_wdata    : out std_logic_vector(XLEN-1 downto 0);
            a0           : out std_logic_vector(XLEN-1 downto 0)
        );
    end component;

    component irq_handler
        generic (
            NUM_IRQS   : integer := NUM_IRQS;
            DATA_WIDTH : integer := XLEN
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
            ivt_entry       : out std_logic_vector(XLEN-1 downto 0)
        );
    end component;

    component c_dec
        generic (
            -- X0 scaffolding: Zcb expansions + Zcmop (c.mop), default false
            ENABLE_ZCB   : boolean := false;
            ENABLE_ZIMOP : boolean := false
        );
        port (
            resetn        : in  std_logic;
            instr_in      : in  std_logic_vector(ILEN-1 downto 0);
            instr_out     : out std_logic_vector(ILEN-1 downto 0);
            is_compressed : out std_logic
        );
    end component;
    
    component csr_unit is
        generic (
            ENABLE_MUL        : boolean := true;
            ENABLE_DIV        : boolean := true;
            ENABLE_ATOMICS    : boolean := true;
            ENABLE_COMPRESSED : boolean := true;
            ENABLE_BITMANIP   : boolean := true;
            -- X0 scaffolding: hpm counters + Zfinx fcsr, default false
            ENABLE_ZIHPM      : boolean := false;
            ENABLE_ZFINX      : boolean := false
        );
        port (
            clk            : in  std_logic;
            resetn         : in  std_logic;
            hart_id        : in  std_logic_vector(XLEN-1 downto 0) := (others => '0');

            -- CSR instruction interface
            csr_addr       : in  std_logic_vector(11 downto 0);
            csr_write_data : in  std_logic_vector(XLEN-1 downto 0);
            csr_op         : in  std_logic_vector(2 downto 0);
            csr_valid      : in  std_logic;
            csr_read_data  : out std_logic_vector(XLEN-1 downto 0);

            -- Performance counter input
            inst_retired   : in  std_logic;

            -- X1 Zihpm event inputs (internal vesta signals, not tile ports)
            ev_bus_stall   : in  std_logic := '0';
            ev_sleep       : in  std_logic := '0';
            ev_trap_entry  : in  std_logic := '0'
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
        SC_CHECK,     -- Store-Conditional check and write
        FENCE_WAIT,   -- FENCE operation wait state
        PAUSE_WAIT,   -- X1 Zihintpause: arbiter-yield hold window (D6)
        WRS_WAIT      -- X1 Zawrs: wait-on-reservation-set stall (wrs.nto/wrs.sto)
    );

    signal current_state, next_state : cpu_state;

    -- ==========================================
    -- PC Management Signals
    -- ==========================================
    signal pc, pc_next           : std_logic_vector(XLEN-1 downto 0);
    signal pc_plus_2, pc_plus_4  : std_logic_vector(XLEN-1 downto 0);
    signal pc_link               : std_logic_vector(XLEN-1 downto 0);  -- JAL/JALR return addr: pc+2 for compressed, else pc+4
    signal pc_target              : std_logic_vector(XLEN-1 downto 0);
    signal pc_next_trad           : std_logic_vector(XLEN-1 downto 0);  -- Traditional PC next value
    signal pc_next_reg            : std_logic_vector(XLEN-1 downto 0);  -- Registered PC next
    signal pc_next_trad_reg       : std_logic_vector(XLEN-1 downto 0);  -- Registered traditional PC next
    signal pc_next_ret            : std_logic_vector(XLEN-1 downto 0);  -- Return PC after IRQ
    signal pc_next_ret_ltch       : std_logic;                      -- Latch for return PC
    signal pc_en                  : std_logic;                      -- PC update enable
    signal pc_src                 : std_logic;                      -- PC source select

    -- ==========================================
    -- Instruction Handling Signals
    -- ==========================================
    signal instr                  : std_logic_vector(ILEN-1 downto 0);
    signal instr_curr             : std_logic_vector(ILEN-1 downto 0);  -- Current instruction being executed
    signal instr_curr_prev        : std_logic_vector(ILEN-1 downto 0);  -- Previous instruction (for timing)
    signal instr_decomp           : std_logic_vector(ILEN-1 downto 0);  -- Decompressed instruction
    signal instr_to_decomp        : std_logic_vector(ILEN-1 downto 0);  -- Instruction to decompress
    signal instr_lower_half       : std_logic_vector(15 downto 0);  -- Lower half for split fetch
    signal instr_upper_half       : std_logic_vector(15 downto 0);  -- Upper half for split fetch
    signal instr_assembled        : std_logic_vector(ILEN-1 downto 0);  -- Assembled from split fetch
    signal data_addr_reg          : std_logic_vector(XLEN-1 downto 0);  -- Return PC after IRQ

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
    signal wen_controller         : std_logic_vector(XLEN_BYTES-1 downto 0);
    signal mem_access_controller  : std_logic;
    signal mem_access_instr       : std_logic;
    signal reg_write_ctrl         : std_logic;  -- From controller
    signal reg_write_dp           : std_logic;  -- To datapath
    signal trap                   : std_logic;

    -- ==========================================
    -- ALU and Division Signals
    -- ==========================================
    signal ALU_result             : std_logic_vector(XLEN-1 downto 0);
    signal rs1_value              : std_logic_vector(XLEN-1 downto 0);  -- M4b: phase-independent rs1 for reservation compares
    signal alu_done               : std_logic;
    signal is_div_op              : std_logic;
    signal div_start              : std_logic;

    -- ==========================================
    -- Stack Pointer Management
    -- ==========================================
    signal sp_write_data          : std_logic_vector(XLEN-1 downto 0);  -- New SP value
    signal stack_pointer          : std_logic_vector(XLEN-1 downto 0);  -- Current SP value
    signal sp_write_en            : std_logic;                      -- SP write enable
    signal write_data_dp          : std_logic_vector(XLEN-1 downto 0);  -- Write data from datapath

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
    signal ivt_entry              : std_logic_vector(XLEN-1 downto 0);

    -- ==========================================
    -- Clock Gating and Power Management
    -- ==========================================
    signal en_clk_cpu             : std_logic;
    -- signal clk_cpu                : std_logic;
    signal sleep_rq               : std_logic;  -- Sleep request from instruction
    signal wake_rq                : std_logic;  -- Wake request from instruction
    signal sleep_cpu              : std_logic;  -- CPU sleep state

    -- X1 Zawrs wait-on-reservation-set. WRS_TIMEOUT_CYCLES = the wrs.sto short
    -- timeout, in clk_cpu cycles (named, parameterizable — one line to retune).
    constant WRS_TIMEOUT_CYCLES   : integer := 1024;
    signal wrs_op                 : std_logic;  -- decoded wrs.nto or wrs.sto
    signal wrs_sto                : std_logic;  -- '1' for wrs.sto (has timeout)
    signal wrs_int_pending        : std_logic;  -- any IRQ source asserted (raw, enable-agnostic)
    signal wrs_timeout            : std_logic;  -- wrs.sto short-timeout elapsed
    signal wrs_wake               : std_logic;  -- combined wake condition
    signal wrs_cnt                : integer range 0 to WRS_TIMEOUT_CYCLES;  -- timeout counter (clk_cpu cycles)
    signal wrs_is_sto             : std_logic;  -- latched-at-entry: this WRS is the timeout variant
                                                -- (instr_curr does not persist through the stall)
    
    -- ==========================================
    -- RV32A Atomic Operation Signals
    -- ==========================================
    signal amo_op                 : std_logic;  -- AMO operation (not LR/SC)
    signal lr_op                  : std_logic;  -- Load-Reserved operation
    signal sc_op                  : std_logic;  -- Store-Conditional operation
    signal fence_op               : std_logic;  -- FENCE instruction indicator
    signal pause_hint             : std_logic;  -- X1 Zihintpause: exact PAUSE hint (fence w,0), '0' when ENABLE_ZIHINT off
    -- X1 Zihintpause window counter (clk_cpu domain). Range is a fixed generous
    -- span (NOT tied to PAUSE_WINDOW_CYCLES) so the negative-control seed can set
    -- the window to 0 without a dead-branch static-range elaboration issue.
    signal pause_cnt              : natural range 0 to 1023 := 0;
    signal amo_read_data          : std_logic_vector(XLEN-1 downto 0);  -- Saved read data for AMO
    signal amo_new_data           : std_logic_vector(XLEN-1 downto 0);  -- Computed data for AMO write
    signal reservation_valid      : std_logic;  -- LR/SC reservation valid
    signal reservation_addr       : std_logic_vector(XLEN-1 downto 0);  -- LR/SC reservation address
    signal amo_phase              : std_logic_vector(2 downto 0);  -- 000: normal, 001: AMO_READ, 010: AMO_COMPUTE, 011: AMO_WRITE, 100: SC fail, 101: SC success
    signal amo_write_data         : std_logic_vector(XLEN-1 downto 0);  -- Data to write for AMO operations

    -- ==========================================
    -- RV32SI (RV32ZISCR) CSR Signals
    -- ==========================================
    signal csr_addr               : std_logic_vector(11 downto 0);
    signal csr_rdata              : std_logic_vector(XLEN-1 downto 0);
    signal csr_wdata              : std_logic_vector(XLEN-1 downto 0);
    signal csr_op                 : std_logic_vector(2 downto 0);
    signal csr_valid              : std_logic;
    signal en_cg_insret           : std_logic;
    signal inst_retired          : std_logic;

    -- X1 Zihpm event levels (fed to csr_unit's hpm counters). Sourced ONLY from
    -- signals already visible inside vesta -- no hart_tile/MCU boundary ports.
    --   hpm_ev_stall: mem_ready low = this hart is requesting a shared txn the
    --                 arbiter has not granted+completed (grant not held).
    --   hpm_ev_sleep: WFI SLEEPING state OR the external tile sleep input.
    --   hpm_ev_trap : in an interrupt- or exception-entry state (IRQ_SV/TRAP).
    signal hpm_ev_stall           : std_logic;
    signal hpm_ev_sleep           : std_logic;
    signal hpm_ev_trap            : std_logic;

    begin

    -- ==========================================
    -- Signal Assignments
    -- ==========================================
    instr <= read_data;

    -- ==========================================
    -- Clock Gating Logic
    -- ==========================================
    -- Enable CPU clock when:
    -- - Memory is ready (mem_ready = '0' freezes the whole core: state, PC, and all
    --   read-data latching stop, while the combinational data_addr/wen request stays
    --   asserted so the arbiter keeps seeing the pending access). This has TOP priority
    --   so a stalled memory access cannot be overridden by an IRQ. With mem_ready tied
    --   '1' (single-master MCU) this term is always false, so en_clk_cpu is unchanged.
    -- - IRQ is active (always process interrupts)
    -- - Not in external sleep mode
    -- - Not in SLEEPING state
    en_clk_cpu <= '0' when mem_ready = '0' else
                  '1' when irq_active = '1' else
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
            amo_write_data <= (others => '0');
        elsif rising_edge(clk_cpu) then
            -- Set reservation on LR
            if current_state = LR_READ then
                reservation_valid <= '1';
                reservation_addr <= rs1_value;  -- M4b: rs1 IS the LR address (phase-independent)
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

    -- ==========================================
    -- X1 Zihintpause window counter (clk_cpu domain)
    -- ==========================================
    -- Loaded when the FSM enters PAUSE_WAIT, then counts down one per clk_cpu
    -- edge. Loading WINDOW-1 makes the hart spend exactly PAUSE_WINDOW_CYCLES
    -- clk_cpu cycles in PAUSE_WAIT (counter values WINDOW-1..0 inclusive). The
    -- load arm is only reachable when PAUSE_WINDOW_CYCLES>0 (the FSM routing
    -- guard), so WINDOW-1 is never negative at runtime.
    pause_cnt_proc: process(clk_cpu, resetn)
    begin
        if resetn = '0' then
            pause_cnt <= 0;
        elsif rising_edge(clk_cpu) then
            if next_state = PAUSE_WAIT and current_state /= PAUSE_WAIT then
                pause_cnt <= PAUSE_WINDOW_CYCLES - 1;
            elsif current_state = PAUSE_WAIT and pause_cnt /= 0 then
                pause_cnt <= pause_cnt - 1;
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

    -- JAL/JALR return address must be the sequential next-PC = pc + (size of the
    -- jump instruction). The datapath link path was hardwired to pc_plus_4, which
    -- is correct for 32-bit jumps but wrong for compressed c.jal/c.jalr (2 bytes).
    -- Mirror the compressed-instruction conditions used by pc_next_trad below so
    -- compressed jumps link pc+2; all other cases keep pc+4 (unchanged behavior).
    pc_link <= pc_plus_2 when (current_state = EXECUTE and pc(1) = '1' and quadrant_upper /= "11" and repeat_if = '0') else
               pc_plus_2 when (current_state = EXECUTE and pc(1) = '0' and quadrant_lower /= "11") else
               pc_plus_4;

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
    -- M4b FIX: during SC_CHECK the ALU is repurposed to produce the SC rd
    -- value (alu_control_dp = pass-B => ALU_result = 0/1), so the write
    -- address must come from rs1 directly — with the old ALU_Result term
    -- every SC write went to address 0x0/0x1 instead of (rs1). Never caught:
    -- no test checked an SC's memory effect before shlrsc.
    -- M8 FIX: during the AMO dispatch cycle (EXECUTE with amo_op) the ALU
    -- computes rs1 <amo-op> rs2 (the controller decodes the AMO's own function
    -- there — ADD/AND/MAX/...), NOT the address, so the EXECUTE-phase access
    -- rode a GARBAGE address — same class as the M4b SC bugs. Private memory
    -- masked it (AMO_READ re-presents the correct pass-A address a cycle
    -- later and the SRAM refreshes Q mid-cycle), but the SHARED window
    -- completes its whole transaction inside the frozen EXECUTE cycle at
    -- that garbage address, and AMO_READ then consumes the stale sh_rdata_reg
    -- — shared AMOs returned wrong data. rs1 IS the AMO address; with it the
    -- shared read rides EXECUTE exactly like the proven LR pattern.
    data_addr <= rs1_value  when (current_state = SC_CHECK) else
                 rs1_value  when (current_state = EXECUTE and amo_op = '1'
                                  and mem_access_instr = '1') else
                 ALU_Result when (mem_access_instr = '1' or
                                  current_state = AMO_READ or current_state = AMO_WRITE or
                                  current_state = LR_READ) else
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
    -- M4b: SC success = LOCAL reservation check (valid AND address match — the
    -- same condition that drives wen in SC_CHECK; the old valid-only term let
    -- an address-mismatched SC report success while skipping the write) AND
    -- the EXTERNAL verdict (sc_fail_ext, from the global resv_unit for shared
    -- addresses; ties '0' for private/single-master use).
    amo_phase <=    "001" when current_state = AMO_READ or current_state = LR_READ else  -- Reading address
                    "010" when current_state = AMO_COMPUTE else  -- Computing with memory data
                    "011" when current_state = AMO_WRITE else     -- Writing result back
                    "101" when current_state = SC_CHECK and reservation_valid = '1'
                               and reservation_addr = rs1_value
                               and sc_fail_ext = '0' else          -- SC succeeded
                    "100" when current_state = SC_CHECK else       -- SC failed
                    "000";  -- Normal operation

    -- M4b: tag the current memory access for the global reservation unit.
    -- PHASING: the LR's bus transaction runs during the EXECUTE (decode) cycle
    -- — data_addr goes live there via mem_access_instr — and LR_READ merely
    -- consumes the returned data, so the "01" tag must ride the EXECUTE cycle.
    -- The SC's conditional WRITE transaction runs during SC_CHECK (EXECUTE
    -- only issues a harmless read for SC after the M4b wen fix). "10" requires
    -- the LOCAL check to pass — a locally failed SC issues no write and must
    -- not be adjudicated as an SC.
    lr_sc_bus <= "01" when current_state = EXECUTE and lr_op = '1' else
                 "10" when current_state = SC_CHECK and reservation_valid = '1'
                           and reservation_addr = rs1_value else
                 "00";

    -- M8: assert for the WHOLE AMO flow. The read transaction completes while
    -- the core is FROZEN in EXECUTE (so the dispatch-cycle term is required —
    -- the arbiter samples lock at that transaction's completion), and the
    -- lock must persist through AMO_WRITE so the write's grant is the pinned
    -- one. It drops at AMO_COMPLETE / IRQ_SV / TRAP, which is the arbiter's
    -- release valve if the write can never issue. mem_access_instr qualifies
    -- the EXECUTE term to the real dispatch (not a compressed half-fetch
    -- cycle where amo_op may be decoded from an incomplete instruction).
    amo_lock <= '1' when (current_state = EXECUTE and amo_op = '1'
                          and mem_access_instr = '1')
                      or current_state = AMO_READ
                      or current_state = AMO_WRITEBACK
                      or current_state = AMO_COMPUTE
                      or current_state = AMO_WRITE
                else '0';


    -- ==========================================
    -- FSM Next State Logic 
    -- ==========================================
    next_state_logic: process(resetn, current_state, pc, instr, quadrant_upper, quadrant_lower, 
                             repeat_if, instr_upper_half, instr_lower_half, instr_decomp, 
                             irq_save, mem_access_controller, is_div_op, pc_src, pc_target, 
                             pc_plus_4, pc_plus_2, alu_done, irq_save_ack, isr_ret, 
                             reg_write_ctrl, wen_controller, sleep_rq, wake_rq, trap, 
                             stack_pointer, sleep_cpu, reg_write_dp, amo_op, lr_op, sc_op,
                             reservation_valid, reservation_addr, ALU_result, fence_op, rs1_value, sc_fail_ext,
                             pause_hint, pause_cnt,
                             wrs_op, wrs_wake, resv_valid_ext)
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
                    -- With the C extension disabled a halfword-aligned PC is an
                    -- instruction-address-misaligned condition (only reachable
                    -- via a jump/branch to a non-word boundary) — trap instead
                    -- of decoding garbage instruction halves. The condition is
                    -- static-false when ENABLE_COMPRESSED, so the default
                    -- build's FSM is untouched.
                    if (not ENABLE_COMPRESSED) and pc(1) = '1' then
                        next_state <= TRAP_STATE;
                        pc_en <= '0';
                    elsif pc(1) = '1' then
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
                                elsif wrs_op = '1' then
                                    -- X1 Zawrs: stall only if a global reservation
                                    -- is live; else the hint retires immediately.
                                    if resv_valid_ext = '1' then
                                        next_state <= WRS_WAIT;
                                        pc_en <= '0';
                                    else
                                        next_state <= EXECUTE;  -- pc_en defaults '1'
                                    end if;
                                elsif lr_op = '1' then
                                    -- Load-Reserved operation
                                    mem_access_instr <= '1';
                                    next_state <= LR_READ;
                                    pc_en <= '0';
                                    reg_write_dp <= '0';
                                elsif sc_op = '1' then
                                    -- Store-Conditional operation
                                    -- M4b FIX: no EXECUTE-phase access — the
                                    -- ALU holds rs1+rs2 here (garbage addr);
                                    -- the only SC access is SC_CHECK's write.
                                    mem_access_instr <= '0';
                                    next_state <= SC_CHECK;
                                    pc_en <= '0';
                                    reg_write_dp <= '0';
                                    -- M4b FIX: wen_controller decodes SC as a
                                    -- word store, which committed the write
                                    -- HERE — before the reservation check. The
                                    -- only (conditional) SC write is SC_CHECK's.
                                    wen <= (others => '1');
                                elsif amo_op = '1' then
                                    -- Atomic memory operation
                                    mem_access_instr <= '1';
                                    next_state <= AMO_READ;
                                    pc_en <= '0';
                                    reg_write_dp <= '0';
                                    wen <= (others => '1'); -- TODO - added
                                elsif fence_op = '1' then
                                    -- X1 Zihintpause (D6): the exact PAUSE hint
                                    -- enters the arbiter-yield window instead of
                                    -- the 1-cycle FENCE nop. pc_en frozen so the
                                    -- PAUSE holds (retires when the window closes);
                                    -- ENABLE_ZIHINT + window>0 are static, so a
                                    -- disabled/seeded build takes the FENCE arm =
                                    -- bit-identical today.
                                    if ENABLE_ZIHINT and pause_hint = '1' and PAUSE_WINDOW_CYCLES > 0 then
                                        next_state <= PAUSE_WAIT;
                                        pc_en <= '0';
                                    else
                                        next_state <= FENCE_WAIT;
                                        pc_en <= '1';
                                    end if;
                                elsif mem_access_controller = '1' then
                                    mem_access_instr <= '1';
                                    next_state <= MEMORY_WAIT;
                                    pc_en <= '0';
                                    reg_write_dp <= '0';
                                elsif is_div_op = '1' then
                                    next_state <= DIV_WAIT;
                                    pc_en <= '0';
                                    -- Div-aliasing fix: suppress the EXECUTE-cycle
                                    -- writeback. reg_write_dp defaults to
                                    -- reg_write_ctrl='1' for a DIV, so without this
                                    -- the EXECUTE->DIV_WAIT edge writes rd with the
                                    -- ALU's idle ResultSignal (=0) BEFORE the divider
                                    -- latches its operands in DIV_WAIT. When rd==rs1
                                    -- that zero becomes the latched dividend (result
                                    -- 0); when rd==rs2 it zeroes the divisor read
                                    -- (spurious div-by-zero). rd is written exactly
                                    -- once, at DIV_DONE, like lr/sc/amo/mem_access.
                                    reg_write_dp <= '0';
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
                                -- Div-aliasing fix: suppress the EXECUTE-cycle
                                -- writeback (reg_write_dp defaults to '1' for a
                                -- DIV) so rd is not clobbered with the idle
                                -- ResultSignal (=0) before the divider latches its
                                -- operands. rd is written exactly once, at DIV_DONE.
                                reg_write_dp <= '0';
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
                            elsif wrs_op = '1' then
                                -- X1 Zawrs: stall only if a global reservation is
                                -- live; else the hint retires immediately.
                                if resv_valid_ext = '1' then
                                    next_state <= WRS_WAIT;
                                    pc_en <= '0';
                                else
                                    next_state <= EXECUTE;  -- pc_en defaults '1'
                                end if;
                            elsif lr_op = '1' then
                                -- Load-Reserved operation
                                mem_access_instr <= '1';
                                next_state <= LR_READ;
                                pc_en <= '0';
                                reg_write_dp <= '0';
                            elsif sc_op = '1' then
                                -- Store-Conditional operation
                                -- M4b FIX: no EXECUTE-phase access (see the
                                -- half-word path above).
                                mem_access_instr <= '0';
                                next_state <= SC_CHECK;
                                pc_en <= '0';
                                reg_write_dp <= '0';
                                -- M4b FIX: no unconditional EXECUTE-phase SC
                                -- write (see the half-word path above).
                                wen <= (others => '1');
                            elsif amo_op = '1' then
                                -- Atomic memory operation
                                mem_access_instr <= '1';
                                next_state <= AMO_READ;
                                pc_en <= '0';
                                reg_write_dp <= '0';
                                wen <= (others => '1'); -- TODO - added
                            elsif fence_op = '1' then
                                -- X1 Zihintpause (D6): PAUSE -> arbiter-yield
                                -- window; any other FENCE -> 1-cycle nop. See the
                                -- half-word path above for the rationale.
                                if ENABLE_ZIHINT and pause_hint = '1' and PAUSE_WINDOW_CYCLES > 0 then
                                    next_state <= PAUSE_WAIT;
                                    pc_en <= '0';
                                else
                                    next_state <= FENCE_WAIT;
                                    pc_en <= '1';
                                end if;
                            elsif mem_access_controller = '1' then
                                mem_access_instr <= '1';
                                next_state <= MEMORY_WAIT;
                                reg_write_dp <= '0';
                                pc_en <= '0';
                            elsif is_div_op = '1' then
                                next_state <= DIV_WAIT;
                                pc_en <= '0';
                                -- Div-aliasing fix: suppress the EXECUTE-cycle
                                -- writeback (reg_write_dp defaults to '1' for a
                                -- DIV) so rd is not clobbered with the idle
                                -- ResultSignal (=0) before the divider latches its
                                -- operands. rd is written exactly once, at DIV_DONE.
                                reg_write_dp <= '0';
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
                                -- Div-aliasing fix: suppress the EXECUTE-cycle
                                -- writeback (reg_write_dp defaults to '1' for a
                                -- DIV) so rd is not clobbered with the idle
                                -- ResultSignal (=0) before the divider latches its
                                -- operands. rd is written exactly once, at DIV_DONE.
                                reg_write_dp <= '0';
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
                    if reservation_valid = '1' and reservation_addr = rs1_value then  -- M4b: rs1, not the phase-dependent ALU_result
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
                -- PAUSE_WAIT State - X1 Zihintpause arbiter-yield window (D6)
                -- ==========================================
                -- The retiring PAUSE parks the hart here for PAUSE_WINDOW_CYCLES
                -- clk_cpu cycles. Why this cannot wedge the arbiter:
                --  * NO new shared transaction is issued while waiting:
                --    mem_access_instr='0' and the PC is frozen, so data_addr
                --    defaults to pc_next -- for a TCM-resident spin loop that is
                --    a TCM address => sh_sel='0' => this hart's sh_req stays low,
                --    which is exactly the arbiter-yield the spec asks for.
                --  * The PAUSE's OWN fetch already completed before this state
                --    (it was decoded in EXECUTE), so no in-flight/granted txn is
                --    ever masked -- this is not the M5a ghost-txn shape.
                --  * The window is a finite down-counter, so forward progress is
                --    guaranteed: the hart always returns to EXECUTE and retires.
                -- Modeled on DIV_WAIT/DIV_DONE (a stall with pc_en frozen). The
                -- window is uninterruptible-short, so (like DIV_WAIT) IRQs are
                -- re-checked on the EXECUTE cycle after the window, not mid-hold.
                when PAUSE_WAIT =>
                    mem_access_instr <= '0';
                    wen              <= (others => '1');
                    reg_write_dp     <= '0';
                    if pause_cnt = 0 then
                        next_state <= EXECUTE;
                        pc_en <= '1';   -- window closed: PAUSE retires, PC advances
                    else
                        next_state <= PAUSE_WAIT;
                        pc_en <= '0';
                    end if;

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

                    -- No writeback belongs to the IRQ dispatch cycles: the
                    -- instruction mux shows the already-retired interrupted
                    -- instruction here (a load decodes RegWrite=1 and would
                    -- re-write its rd with garbage) and raw read_data during
                    -- IRQ_JUMP (arbitrary image -> arbitrary rd). Caught by
                    -- rv32ui-p-irqctx (phantom t1 write during IRQ_JUMP).
                    reg_write_dp <= '0';
                    pc_en <= '0';
                    next_state <= IRQ_JUMP;

                -- ==========================================
                -- IRQ_JUMP State - Jump to interrupt vector
                -- ==========================================
                when IRQ_JUMP =>
                    irq_save_ack <= '1';
                    pc_en <= '1';  -- Load IVT entry
                    wen <= (others => '1');
                    reg_write_dp <= '0';
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
                -- WRS_WAIT State  (X1 Zawrs wait-on-reservation-set)
                -- ==========================================
                -- Stall with the PC frozen (the wrs hint has NOT retired) while
                -- clk_cpu keeps running and wrs_wake is polled. On any wake the
                -- hint retires like a nop (pc_en='1', next=EXECUTE): if the wake
                -- was a pending+enabled interrupt, the standard EXECUTE->IRQ_SV
                -- path then takes it with the return PC = the instruction after
                -- wrs (a WRS is never a trap and changes no architectural state).
                -- Deliberately does NOT set sleep_cpu, so an interrupt taken here
                -- does not leave the hart in the return-to-sleep contract.
                when WRS_WAIT =>
                    pc_en <= '0';
                    wen <= (others => '1');   -- no memory access while stalled
                    mem_access_instr <= '0';
                    reg_write_dp <= '0';
                    if wrs_wake = '1' then
                        next_state <= EXECUTE;
                        pc_en <= '1';         -- retire the hint, advance the PC
                    else
                        next_state <= WRS_WAIT;
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
    -- X1 Zawrs — Wait-on-Reservation-Set wake logic
    -- ==========================================
    -- wrs.nto/wrs.sto stall the hart in the dedicated WRS_WAIT FSM state. Unlike
    -- WFI/extinguish, WRS_WAIT does NOT gate clk_cpu and does NOT touch sleep_cpu:
    -- the FSM simply spins with pc_en frozen while the wake conditions are polled
    -- each clk_cpu edge, so the CLINT ignite / return-to-sleep contract is
    -- provably untouched (a WRS stall is invisible to the sleep machinery). The
    -- core issues no bus transaction while waiting (arbiter req de-asserted).
    --
    -- Wake sources (any one, per the spec):
    --   (a) reservation invalidated — resv_valid_ext dropped to '0' (a foreign
    --       committed store hit the LR address; the snoop resv_unit implements),
    --   (b) an interrupt is pending — RAW irq_vector, enable-agnostic, so it
    --       fires even for a source that would not be taken (spec: wake even if
    --       globally disabled). This core hardwires the CLINT/meip enables on,
    --       so a pending source is also serviced after the WRS retires,
    --   (c) wrs.sto only: the short timeout (WRS_TIMEOUT clk_cpu cycles) elapsed.
    wrs_int_pending <= '1' when irq_vector /= (irq_vector'range => '0') else '0';
    wrs_timeout     <= '1' when (wrs_is_sto = '1' and wrs_cnt = WRS_TIMEOUT_CYCLES) else '0';
    wrs_wake        <= '1' when (resv_valid_ext = '0' or wrs_int_pending = '1' or wrs_timeout = '1') else '0';

    -- Timeout counter: free-runs on clk_cpu only while stalled; cleared whenever
    -- the hart is not in WRS_WAIT. Saturates at WRS_TIMEOUT (wrs.nto never reads
    -- it). Same clock domain as mcycle, so the stall is measurable via mcycle.
    wrs_timeout_proc: process(clk_cpu, resetn)
    begin
        if resetn = '0' then
            wrs_cnt <= 0;
            wrs_is_sto <= '0';
        elsif rising_edge(clk_cpu) then
            if current_state = WRS_WAIT then
                -- stalled: freeze the sto flag (instr_curr no longer holds the
                -- wrs encoding here) and advance the timeout counter.
                if wrs_cnt /= WRS_TIMEOUT_CYCLES then
                    wrs_cnt <= wrs_cnt + 1;
                end if;
            else
                wrs_cnt <= 0;
                -- capture the pending WRS variant each pre-entry cycle; the last
                -- non-WRS_WAIT cycle before entry is the EXECUTE decode of the
                -- wrs, where wrs_sto is valid.
                wrs_is_sto <= wrs_sto;
            end if;
        end if;
    end process;

    -- ==========================================
    -- Controller Instance
    -- ==========================================
    controller_inst: controller
        generic map (
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
            wrs_op           => wrs_op,
            wrs_sto          => wrs_sto,
            mem_access_instr => mem_access_controller,
            trap             => trap,
            amo_op           => amo_op,
            lr_op            => lr_op,
            sc_op            => sc_op,
            fence_op         => fence_op,
            pause_hint       => pause_hint,
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
            clk         => clk_cpu,
            resetn      => resetn,
            pc          => pc,
            pc_plus_4   => pc_link,
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
            rs1_value   => rs1_value,
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
            DATA_WIDTH => XLEN
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

    -- The decompressor only exists when the C extension is enabled. Without
    -- it, instr_decomp is tied to all-zeros — opcode "0000000" is not in
    -- valid_opcode, so any 16-bit encoding reaching decode traps as an
    -- illegal instruction (the EXECUTE-state misaligned-PC check catches the
    -- halfword-aligned fetch case before it gets this far).
    gen_cdec: if ENABLE_COMPRESSED generate
        c_dec_inst: c_dec
            generic map (
                ENABLE_ZCB   => ENABLE_ZCB,
                ENABLE_ZIMOP => ENABLE_ZIMOP
            )
            port map (
                resetn        => resetn,
                instr_in      => instr_to_decomp,
                instr_out     => instr_decomp,
                is_compressed => is_compressed_cdec
            );
    end generate;

    gen_no_cdec: if not ENABLE_COMPRESSED generate
        instr_decomp       <= (others => '0');
        is_compressed_cdec <= '0';
    end generate;

 
    csr_addr <= instr_curr(31 downto 20);

    -- X1 Zihpm event levels (see signal declarations). mem_ready is the arbiter
    -- back-pressure: '0' = pending shared request not yet granted/completed.
    hpm_ev_stall <= not mem_ready;
    hpm_ev_sleep <= '1' when (current_state = SLEEPING or sleep = '1') else '0';
    hpm_ev_trap  <= '1' when (current_state = IRQ_SV or current_state = TRAP_STATE) else '0';

    csr_unit_inst : csr_unit
        generic map (
            ENABLE_MUL        => ENABLE_MUL,
            ENABLE_DIV        => ENABLE_DIV,
            ENABLE_ATOMICS    => ENABLE_ATOMICS,
            ENABLE_COMPRESSED => ENABLE_COMPRESSED,
            ENABLE_BITMANIP   => ENABLE_BITMANIP,
            ENABLE_ZIHPM      => ENABLE_ZIHPM,
            ENABLE_ZFINX      => ENABLE_ZFINX
        )
        port map (
            clk            => clk,
            resetn         => resetn,
            hart_id        => hart_id,
            csr_addr       => csr_addr,
            csr_write_data => csr_wdata, 
            csr_op         => csr_op,
            csr_valid      => csr_valid,
            csr_read_data  => csr_rdata,
            inst_retired   => inst_retired,
            ev_bus_stall   => hpm_ev_stall,
            ev_sleep       => hpm_ev_sleep,
            ev_trap_entry  => hpm_ev_trap
        );

end architecture;


