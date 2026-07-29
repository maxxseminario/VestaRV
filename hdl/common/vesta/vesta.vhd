library IEEE;
use IEEE.std_logic_1164.all;
use work.constants.all;
-- P1: the standard mip CSR mirrors the three interrupt LEVEL wires, which reach
-- this core as irq_vector bits at the MemoryMap slot indices IRQB_CLINT_MSIP /
-- IRQB_CLINT_MTIP / IRQB_EXT_MEIP. MemoryMap is compiled before vesta in every
-- cell list / genus read_hdl order (hart_tile already depends on it) and shares
-- no declaration name with work.constants, so this adds no ambiguity.
use work.MemoryMap.all;
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
        ENABLE_ZICBOZ     : boolean := false;  -- X3 (Zicboz): cbo.zero block-zero store sequencer
        ENABLE_ZCMP       : boolean := false;  -- X3 (Zcmp): compressed push/pop + reg-moves (memory sequencer)
        ENABLE_ZCMT       : boolean := false;  -- X3 (Zcmt): compressed table jump + jvt CSR
        ENABLE_ZBKB       : boolean := false;  -- X3 (Zbkb): consumed from phase X3 on; scaffolded X0
        ENABLE_ZBKC       : boolean := false;  -- X3 (Zbkc): consumed from phase X3 on; scaffolded X0
        ENABLE_ZBKX       : boolean := false;  -- X3 (Zbkx): consumed from phase X3 on; scaffolded X0
        ENABLE_ZKN        : boolean := false;  -- X3 (Zkn): consumed from phase X3 on; scaffolded X0
        ENABLE_ZFINX      : boolean := false;  -- X4 (Zfinx): consumed from phase X4 on; scaffolded X0
        -- P0 privileged-architecture scaffolding: all default false / 16 entries,
        -- zero behavioral change. Fanned out to the sub-blocks that will consume
        -- them (maindec via controller for the MRET/ECALL/EBREAK/WFI decode and
        -- the csr_addr_valid map; csr_unit for the CSR file itself). The trap
        -- entry/MRET FSM arms and the PMP check points land at THIS level from
        -- their phase on. -- consumed from phase P<n> on; scaffolded P0
        ENABLE_TRAPCSR    : boolean := false;  -- P1 (trap CSRs + MRET): consumed from phase P1 on; scaffolded P0
        ENABLE_UMODE      : boolean := false;  -- P2 (U-mode, requires TRAPCSR): consumed from phase P2 on; scaffolded P0
        ENABLE_PMP        : boolean := false;  -- P3 (PMP/Smpmp, requires UMODE): consumed from phase P3 on; scaffolded P0
        PMP_ENTRIES       : integer := 16      -- P3 (PMP entry count {8,16}): consumed from phase P3 on; scaffolded P0
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
            ENABLE_ZICBOZ   : boolean := false;
            ENABLE_ZCMP     : boolean := false;
            ENABLE_ZCMT     : boolean := false;
            ENABLE_ZBKB     : boolean := false;
            ENABLE_ZBKC     : boolean := false;
            ENABLE_ZBKX     : boolean := false;
            ENABLE_ZKN      : boolean := false;
            ENABLE_ZFINX    : boolean := false;
            -- P0 scaffolding: the subset maindec will consume (default false)
            ENABLE_TRAPCSR  : boolean := false;
            ENABLE_UMODE    : boolean := false;
            ENABLE_PMP      : boolean := false
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
            alu_control      : out std_logic_vector(6 downto 0);
            mem_access_instr : out std_logic;

            isr_ret          : out std_logic;
            sleep_rq         : out std_logic;
            wake_rq          : out std_logic;
            -- P1 standard SYSTEM/PRIV decode ('0' unless ENABLE_TRAPCSR)
            ecall_op         : out std_logic;
            ebreak_op        : out std_logic;
            mret_op          : out std_logic;
            -- P2 WFI decode + the U-mode decode inputs (inert defaults)
            wfi_op           : out std_logic;
            priv_m           : in  std_logic := '1';
            status_tw        : in  std_logic := '0';
            mcounteren_bits  : in  std_logic_vector(4 downto 0) := "00000";
            wrs_op           : out std_logic;
            wrs_sto          : out std_logic;


            -- RV32A signals
            amo_op           : out std_logic;
            lr_op            : out std_logic;
            sc_op            : out std_logic;
            fence_op         : out std_logic;
            cboz_op          : out std_logic;
            zcm_op           : out std_logic;
            pause_hint       : out std_logic;

            csr_op           : out std_logic_vector(2 downto 0);
            csr_valid        : out std_logic;

            -- X4 Zfinx FP decode
            is_fp_singlecycle : out std_logic;
            is_fp_multicycle  : out std_logic;
            is_fp_fma         : out std_logic;
            frm_valid         : in  std_logic := '1';

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
            alu_control  : in  std_logic_vector(6 downto 0);
            div_start    : in  std_logic;
            amo_phase    : in  std_logic_vector(2 downto 0);  -- 000: normal, 001: AMO_READ, 010: AMO_COMPUTE, 011: AMO_WRITE, 100: SC fail, 101: SC success
            cas_op       : in  std_logic;  -- X2 Zacas: current AMO is an amocas
            -- X3 Zcmp/Zcmt sequencer regfile steering (all default inactive)
            zcm_rs_addr  : in  std_logic_vector(4 downto 0) := "00000";
            zcm_rs_sel   : in  std_logic := '0';
            zcm_rd_addr  : in  std_logic_vector(4 downto 0) := "00000";
            zcm_rd_sel   : in  std_logic := '0';
            zcm_move_sel : in  std_logic := '0';
            zcm_loadwb_sel : in std_logic := '0';
            Zero         : out std_logic;
            pc_target    : out std_logic_vector(XLEN-1 downto 0);
            instr        : in  std_logic_vector(ILEN-1 downto 0);
            ALU_result   : out std_logic_vector(XLEN-1 downto 0);
            rs1_value    : out std_logic_vector(XLEN-1 downto 0);
            amo_addr_low : out std_logic_vector(1 downto 0);
            cas_match    : out std_logic;  -- X2 Zacas: registered CAS compare verdict
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
            -- X4 Zfinx FPU control/status (all default inert)
            fp_op_latch  : in  std_logic := '0';
            fp_fetch3    : in  std_logic := '0';
            fpu_start    : in  std_logic := '0';
            frm_value    : in  std_logic_vector(2 downto 0) := "000";
            fpu_done     : out std_logic;
            fp_flags     : out std_logic_vector(4 downto 0);
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
            ENABLE_ZIMOP : boolean := false;
            -- X3 Zcmp/Zcmt: C2 funct3=101 sentinel emit (default false)
            ENABLE_ZCMP  : boolean := false;
            ENABLE_ZCMT  : boolean := false
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
            ENABLE_ZCMT       : boolean := false;  -- X3 Zcmt: jvt CSR
            ENABLE_ZFINX      : boolean := false;
            -- P0 scaffolding: the trap-CSR file, the U-mode privilege state and
            -- the PMP config/address CSR bank all live in csr_unit from their
            -- phase on (default false / 16 entries)
            ENABLE_TRAPCSR    : boolean := false;
            ENABLE_UMODE      : boolean := false;
            ENABLE_PMP        : boolean := false;
            PMP_ENTRIES       : integer := 16
        );
        port (
            clk            : in  std_logic;
            resetn         : in  std_logic;
            hart_id        : in  std_logic_vector(XLEN-1 downto 0) := (others => '0');

            -- X3 Zcmt jvt base export
            jvt_value      : out std_logic_vector(31 downto 0);

            -- X4 Zfinx fcsr/fflags/frm
            fp_flags_we    : in  std_logic := '0';
            fp_flags_val   : in  std_logic_vector(4 downto 0) := (others => '0');
            frm_value      : out std_logic_vector(2 downto 0);
            frm_valid      : out std_logic;

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
            ev_trap_entry  : in  std_logic := '0';

            -- P1 trap-CSR interface (p0_specs.md 2.4 FREEZE; inert defaults)
            irq_msip       : in  std_logic := '0';
            irq_mtip       : in  std_logic := '0';
            irq_meip       : in  std_logic := '0';
            trap_entry_we  : in  std_logic := '0';
            trap_pc        : in  std_logic_vector(XLEN-1 downto 0) := (others => '0');
            trap_cause     : in  std_logic_vector(XLEN-1 downto 0) := (others => '0');
            trap_value     : in  std_logic_vector(XLEN-1 downto 0) := (others => '0');
            mret_we        : in  std_logic := '0';
            mtvec_value    : out std_logic_vector(XLEN-1 downto 0);
            mepc_value     : out std_logic_vector(XLEN-1 downto 0);
            mstatus_mie    : out std_logic;
            mie_bits       : out std_logic_vector(2 downto 0);
            legacy_mode    : out std_logic;

            -- P2 U-mode interface (p0_specs.md 3.1 FREEZE)
            priv_mode      : out std_logic;
            status_tw      : out std_logic;
            mcounteren_bits : out std_logic_vector(4 downto 0)
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
        -- X4 Zfinx FP multi-cycle stall states (modeled on DIV_WAIT/DIV_DONE, all
        -- gated so they are UNREACHABLE when ENABLE_ZFINX is off — the transitions
        -- into them are constant-false via the ENABLE_ZFINX-gated decode signals).
        -- FPU_FETCH3 (FMA only) latches rs3 through the steered rs2 read port;
        -- FPU_WAIT holds the unit running (fpu_start high, §C1); FPU_DONE retires
        -- the writeback exactly like DIV_DONE (reg_write_dp defaults to '1').
        FPU_FETCH3,   -- FMA rs3 fetch cycle (no 3rd regfile port)
        FPU_WAIT,     -- Wait for the multi-cycle FP unit
        FPU_DONE,     -- FP op completed (writeback here)
        IRQ_SV,       -- Save context for IRQ
        IRQ_REST,     -- Restore context from IRQ
        IRQ_JUMP,     -- Jump to interrupt vector
        TRAP_STATE,   -- Trap state for illegal instructions
        -- P1 standard M-mode trap delivery (ENABLE_TRAPCSR + mtrapctl.LEGACY=0).
        -- Shaped on IRQ_SV/IRQ_JUMP but with ZERO memory transactions: no push,
        -- no sp_write_en, wen all-ones, reg_write_dp='0' in every one of them
        -- (kickoff 3b class 1), and no irq_handler handshake (no irq_save_ack).
        -- All three are UNREACHABLE when ENABLE_TRAPCSR is false: every
        -- transition into them is qualified by `std_mode`, which is statically
        -- '0' there -- so the OFF build's state encoding is bit-identical.
        MTRAP_SV,     -- standard trap entry: write mepc/mcause/mtval + mstatus push
        MTRAP_JUMP,   -- standard trap entry: PC <- mtvec.BASE
        MTRAP_RET,    -- MRET: PC <- mepc, mstatus pop (MIE<=MPIE, MPIE<='1')
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
        WRS_WAIT,     -- X1 Zawrs: wait-on-reservation-set stall (wrs.nto/wrs.sto)
        -- X3 Zicboz: cbo.zero block-zero store sequencer. CBOZ_WRITE issues one
        -- full-word 0 store (mem_access='1', wen="0000"); CBOZ_GAP is the req-low
        -- settle cycle (mem_access='0') the shared-bus arbiter's WAIT-FOR-RELEASE
        -- needs BETWEEN same-master transactions (exactly the store->MEMORY_WAIT
        -- cadence — no new arbiter protocol, no grant-lock). The pair repeats
        -- CBOZ_WORDS times, UNINTERRUPTIBLE (no irq_save check), then MEMORY_WAIT.
        CBOZ_WRITE,   -- issue the cbo.zero word store for cboz_idx
        CBOZ_GAP,     -- req-low settle between stores (last -> retire via MEMORY_WAIT)
        -- X3 Zcmp/Zcmt sequencer states (MEMORY / control-flow path). All
        -- UNINTERRUPTIBLE (no irq_save check) and atomic: RAM here is idempotent
        -- and fault-free, so no re-execution machinery is needed and interrupts are
        -- simply held to the retire boundary. sp is committed EXACTLY ONCE, LAST,
        -- through the regfile's dedicated sp_write port (ZCM_SP_COMMIT). Every
        -- register index and address derives from REGISTERED sequencer state
        -- (zcm_idx counter + zcm_rlist/zcm_spimm/zcm_sp0 latched at dispatch), never
        -- a live regfile-port re-read mid-sequence (the X2 phantom-read invariant).
        ZCM_PUSH_ST,  -- cm.push : store reg[reg_at(idx)] at the frame slot
        ZCM_PUSH_GAP, -- req-low settle; advance idx or -> ZCM_SP_COMMIT
        ZCM_POP_LD,   -- cm.pop* : issue the load of the frame slot
        ZCM_POP_WB,   -- writeback reg[reg_at(idx)] = loaded word; settle; advance
        ZCM_A0Z,      -- cm.popretz only : a0 (x10) <- 0 (move from x0)
        ZCM_SP_COMMIT,-- commit sp once (sp_out -/+ stack_adj); push/pop retire here
        ZCM_RET,      -- cm.popret[z] : redirect PC to reg[ra]
        ZCM_MV1,      -- cm.mvsa01/mva01s : first of the two reg-reg moves
        ZCM_MV2,      -- cm.mvsa01/mva01s : second move; retire
        ZCM_JT_LD,    -- cm.jt/jalt : issue the load of the jvt table entry
        ZCM_JT_WB     -- capture target; cm.jalt writes ra=pc+2; redirect PC
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
    signal alu_control            : std_logic_vector(6 downto 0); -- from control unit
    signal alu_control_dp         : std_logic_vector(6 downto 0); -- to datapath
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
    -- X4 Zfinx FP control/status signals
    -- ==========================================
    signal is_fp_singlecycle      : std_logic;  -- fsgnj*/fmin/fmax/fcmp/fclass (EXECUTE retire)
    signal is_fp_multicycle       : std_logic;  -- fadd/sub/mul/div/sqrt/fcvt (-> FPU_WAIT)
    signal is_fp_fma              : std_logic;  -- fmadd/fmsub/fnmadd/fnmsub (-> FPU_FETCH3)
    signal frm_value              : std_logic_vector(2 downto 0);  -- csr_unit fp_csr[7:5]
    signal frm_valid              : std_logic;  -- '1' iff frm in {000..100}
    signal fpu_start              : std_logic;  -- run pulse to fpu (asserted only in FPU_WAIT, §C1)
    signal fpu_done_sig           : std_logic;  -- fpu complete (paces FPU_WAIT->FPU_DONE); _sig avoids the FPU_DONE state name (VHDL is case-insensitive)
    signal fp_op_latch            : std_logic;  -- EXECUTE-dispatch strobe: latch rs1/rs2 in datapath
    signal fp_fetch3              : std_logic;  -- '1' in FPU_FETCH3 (steer a2->rs3)
    signal fp_flags               : std_logic_vector(4 downto 0);  -- completing FP op's flags (from datapath)
    signal fp_flags_we            : std_logic;  -- strobe: OR fp_flags into fflags (to csr_unit)
    signal fp_flags_val           : std_logic_vector(4 downto 0);  -- flag value to csr_unit

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
    -- X3 Zicboz (cbo.zero) block-zero store sequencer state (clk_cpu domain).
    -- cboz_op: exact cbo.zero decode (from maindec, '0' when ENABLE_ZICBOZ off).
    -- cboz_base: the naturally-aligned block base, latched ONCE at dispatch from
    --   the LIVE rs1 port (rs1 & ~(CBOZ_BLOCK_SIZE-1)); NEVER re-read mid-burst
    --   (the X2 rd_amo/amo_*_reg phantom-read lesson — cbo.zero doesn't write rd
    --   so rs1 is stable, but latching is the invariant, not an optimisation).
    -- cboz_idx: 0..CBOZ_WORDS-1, the word being stored this burst step.
    signal cboz_op                : std_logic;
    signal cboz_base              : std_logic_vector(31 downto 0);
    signal cboz_idx               : integer range 0 to CBOZ_WORDS-1;
    signal cboz_zero_addr         : std_logic_vector(31 downto 0);  -- cboz_base + cboz_idx*4

    -- X3 Zcmp / Zcmt sequencer signals (clk_cpu domain). zcm_op: cm.* sentinel
    -- decode from the controller ('0' when both generics off). Registered at
    -- dispatch (the ONLY source of mid-sequence indices/addresses): zcm_subop_r,
    -- zcm_i16_r (the embedded compressed operand bits), zcm_sp0 (old sp),
    -- zcm_idx (position 0..12).
    signal zcm_op                 : std_logic;
    signal zcm_subop              : std_logic_vector(2 downto 0);
    signal zcm_subop_r            : std_logic_vector(2 downto 0);
    signal zcm_i16_r              : std_logic_vector(15 downto 0);
    signal zcm_sp0                : std_logic_vector(31 downto 0);
    signal zcm_idx                : integer range 0 to 12;
    signal zcm_rlist              : std_logic_vector(3 downto 0);
    signal zcm_spimm              : std_logic_vector(1 downto 0);
    signal zcm_nregs_val          : integer range 1 to 13;
    signal zcm_stackadj_val       : integer range 0 to 112;
    signal zcm_high_addr          : std_logic_vector(31 downto 0);
    signal zcm_mem_addr           : std_logic_vector(31 downto 0);
    signal zcm_final_sp           : std_logic_vector(31 downto 0);
    signal zcm_reg_idx            : std_logic_vector(4 downto 0);
    signal zcm_is_push            : std_logic;
    signal zcm_is_popfam          : std_logic;
    signal zcm_is_popret          : std_logic;
    signal zcm_is_popretz         : std_logic;
    signal zcm_is_mvsa            : std_logic;
    signal zcm_is_mva             : std_logic;
    signal zcm_is_move            : std_logic;
    signal zcm_is_tabjump         : std_logic;
    signal jvt_value              : std_logic_vector(31 downto 0);
    signal zcm_index              : std_logic_vector(7 downto 0);
    signal zcm_jt_link            : std_logic;
    signal zcm_jt_addr            : std_logic_vector(31 downto 0);
    signal zcm_jt_target          : std_logic_vector(31 downto 0);
    signal zcm_rs_addr            : std_logic_vector(4 downto 0);
    signal zcm_rs_sel             : std_logic;
    signal zcm_rd_addr            : std_logic_vector(4 downto 0);
    signal zcm_rd_sel             : std_logic;
    signal zcm_move_sel           : std_logic;
    signal zcm_loadwb_sel         : std_logic;
    signal dp_result_src          : std_logic_vector(2 downto 0);
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
    signal amo_write_data_steered : std_logic_vector(XLEN-1 downto 0);  -- X2 Zabha: sub-word-replicated AMO write data
    signal amo_wen                : std_logic_vector(XLEN_BYTES-1 downto 0);  -- X2 Zabha: byte-lane write-enable for sub-word AMO write (active-low)
    signal amo_addr_low           : std_logic_vector(1 downto 0);    -- X2 Zabha F1: registered AMO address low bits (from datapath)
    signal cas_op                 : std_logic;                        -- X2 Zacas: current AMO is an amocas (funct5=CAS_FN5, ENABLE_ZACAS)
    signal cas_match_reg          : std_logic;                        -- X2 Zacas: registered CAS compare verdict from datapath (1=match)

    -- ==========================================
    -- RV32SI (RV32ZISCR) CSR Signals
    -- ==========================================
    signal csr_addr               : std_logic_vector(11 downto 0);
    signal csr_rdata              : std_logic_vector(XLEN-1 downto 0);
    signal csr_wdata              : std_logic_vector(XLEN-1 downto 0);
    signal csr_op                 : std_logic_vector(2 downto 0);
    signal csr_valid              : std_logic;
    -- P2 TRAP-ENTRY SIDE-EFFECT BLOCK (see the assignment near the trap glue).
    signal trap_entry_seq         : std_logic;
    signal csr_valid_eff          : std_logic;
    signal isr_ret_eff            : std_logic;
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

    -- ==========================================
    -- P1 standard M-mode trap CSR file hookup (ENABLE_TRAPCSR)
    -- ==========================================
    -- The three interrupt LEVELS the standard `mip` mirrors. These are the SAME
    -- wires the legacy irq_handler consumes -- irq_vector bits at the MemoryMap
    -- slot indices -- tapped, never latched (mip has no storage by spec).
    signal trap_irq_msip          : std_logic;
    signal trap_irq_mtip          : std_logic;
    signal trap_irq_meip          : std_logic;
    -- csr_unit's trap-CSR exports. NO CONSUMERS YET: the MTRAP_SV/MTRAP_JUMP
    -- states, the MRET arm and the LEGACY delivery mux are the P1 Agent-B diff.
    -- Declared here so the frozen csr_unit port map is complete today.
    signal trap_mtvec_value       : std_logic_vector(XLEN-1 downto 0);
    signal trap_mepc_value        : std_logic_vector(XLEN-1 downto 0);
    signal trap_mstatus_mie       : std_logic;
    signal trap_mie_bits          : std_logic_vector(2 downto 0);
    signal trap_legacy_mode       : std_logic;

    -- ------------------------------------------------------------------
    -- P1 standard trap DELIVERY (this is the Agent-B half of the P1 diff).
    -- ------------------------------------------------------------------
    -- SYSTEM/PRIV decode from maindec (statically '0' when ENABLE_TRAPCSR off).
    signal ecall_op               : std_logic;
    signal ebreak_op              : std_logic;
    signal mret_op                : std_logic;
    -- '1' == standard delivery (ENABLE_TRAPCSR and mtrapctl.LEGACY = 0). This is
    -- THE coexistence mux select: statically '0' on an OFF build (so every new
    -- FSM arm constant-folds away) and '0' at reset on an ON build (LEGACY
    -- resets '1'), which is what makes the full legacy suite run untouched on ON
    -- hardware.
    signal std_mode               : std_logic;
    -- Standard-mode interrupt take: mstatus.MIE and (mip and mie) /= 0.
    signal std_irq_take           : std_logic;
    -- Dispatch-cycle trap classification (combinational; sampled ONLY at the
    -- edge that enters MTRAP_SV, so it can never be read on a compressed
    -- half-fetch cycle -- the half-fetch class is closed by construction here,
    -- see the mtrap_cause_proc comment).
    signal mtrap_disp_int         : std_logic;
    signal mtrap_disp_code        : std_logic_vector(3 downto 0);
    -- ...latched at the dispatch edge (5 flops: Interrupt bit + 4-bit code).
    signal mtrap_cause_int        : std_logic;
    signal mtrap_cause_code       : std_logic_vector(3 downto 0);
    -- csr_unit writeback drive (values are combinational from HELD state).
    signal trap_pc_val            : std_logic_vector(XLEN-1 downto 0);
    signal trap_cause_val         : std_logic_vector(XLEN-1 downto 0);
    signal trap_value_val         : std_logic_vector(XLEN-1 downto 0);
    -- One-shot strobes into csr_unit. csr_unit runs on the FREE-RUNNING clk while
    -- the FSM runs on the GATED clk_cpu, so a plain state-level strobe would be
    -- applied on EVERY clk edge the FSM spends in the state -- and the mstatus
    -- stack push (MPIE<=MIE, MIE<='0') is NOT idempotent: a second application
    -- would destroy MPIE. These are clk-domain rising-edge one-shots of the state
    -- level, so the writeback lands EXACTLY ONCE however long clk_cpu is gated.
    signal mtrap_sv_lvl           : std_logic;
    signal mtrap_sv_d             : std_logic;
    signal mtrap_ret_lvl          : std_logic;
    signal mtrap_ret_d            : std_logic;
    signal trap_entry_we_sig      : std_logic;
    signal mret_we_sig            : std_logic;
    -- irq_handler enable mask after the standard-mode neutralization gate.
    signal irq_en_eff             : std_logic_vector(NUM_IRQS-1 downto 0);
    -- mcause bits 30:4 are hardwired 0 (csr_unit stores only bit31 + code(3:0)).
    constant MTRAP_RSVD27         : std_logic_vector(26 downto 0) := (others => '0');

    -- ------------------------------------------------------------------
    -- P2 U-mode + standard WFI (ENABLE_UMODE / ENABLE_TRAPCSR)
    -- ------------------------------------------------------------------
    -- csr_unit's P2 exports (p0_specs.md 3.1). trap_priv_mode reads '1' (M) for
    -- all time on an ENABLE_UMODE=false build, so maindec's U-mode gate folds.
    signal trap_priv_mode         : std_logic;
    signal trap_status_tw         : std_logic;
    signal trap_mcounteren        : std_logic_vector(4 downto 0);
    -- maindec's standard-WFI decode ('0' unless ENABLE_TRAPCSR).
    signal wfi_op                 : std_logic;
    -- WFI ENTRY-REASON MARKER. SLEEPING is entered by TWO different
    -- instructions with DIFFERENT wake rules:
    --   extinguish (legacy custom insn): wakes only on a TAKEN interrupt
    --                                    (irq_save / std_irq_take) -- unchanged.
    --   WFI        (standard, P2)      : wakes on (mip and mie) /= 0 REGARDLESS
    --                                    of mstatus.MIE; if the interrupt is
    --                                    takeable it vectors (MTRAP_SV), else it
    --                                    RESUMES at the instruction after WFI.
    -- One flop distinguishes them. Set at the WFI dispatch edge (wfi_enter,
    -- driven only from the real-dispatch decode arms -> the compressed
    -- half-fetch class 5 cannot set it), cleared on EVERY exit from SLEEPING.
    signal wfi_slept              : std_logic;
    signal wfi_enter              : std_logic;
    -- (mip and mie) /= 0 -- the ENABLE-agnostic-of-MIE pending term the standard
    -- WFI wake rule uses. Same three sources / same mie packing as std_irq_take,
    -- MINUS the mstatus.MIE qualifier.
    signal std_wfi_pend           : std_logic;
    -- The wake itself: only ever asserted for a WFI-entered sleep.
    signal std_wfi_wake           : std_logic;

    -- X3 Zcmp/Zcmt helper functions (pure combinational, spec tables).
    function zcm_reg_at(p : integer) return std_logic_vector is
    begin
        if p = 0 then
            return "00001";                                   -- x1  (ra)
        elsif p = 1 then
            return "01000";                                   -- x8  (s0)
        elsif p = 2 then
            return "01001";                                   -- x9  (s1)
        else
            return std_logic_vector(to_unsigned(15 + p, 5));  -- x18..x27
        end if;
    end function;

    function zcm_sreg_x(s : std_logic_vector(2 downto 0)) return std_logic_vector is
        variable si : integer;
    begin
        si := to_integer(unsigned(s));
        if si < 2 then
            return std_logic_vector(to_unsigned(8 + si, 5));   -- x8, x9
        else
            return std_logic_vector(to_unsigned(16 + si, 5));  -- x18..x23
        end if;
    end function;

    function zcm_nregs(rlist : std_logic_vector(3 downto 0)) return integer is
        variable r : integer;
    begin
        r := to_integer(unsigned(rlist));
        if r = 15 then
            return 13;
        else
            return r - 3;
        end if;
    end function;

    function zcm_stackadj(rlist : std_logic_vector(3 downto 0);
                          spimm : std_logic_vector(1 downto 0)) return integer is
        variable r    : integer;
        variable base : integer;
    begin
        r := to_integer(unsigned(rlist));
        if r <= 7 then
            base := 16;
        elsif r <= 11 then
            base := 32;
        elsif r <= 14 then
            base := 48;
        else
            base := 64;
        end if;
        return base + to_integer(unsigned(spimm)) * 16;
    end function;

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
    -- P1: in STANDARD delivery mode the irq_handler is held in IDLE, so
    -- irq_active can never rise and the legacy "IRQ is active" ungate above is
    -- dead -- a hart that extinguished into SLEEPING would never get a clk_cpu
    -- edge again and could never reach MTRAP_SV. std_irq_take restores exactly
    -- that ungate for the standard path, at the same precedence. Statically '0'
    -- on an OFF build (std_mode folds to '0'), so en_clk_cpu is bit-identical.
    -- P2: the standard WFI wake needs its OWN ungate, at the same precedence and
    -- for the same reason. std_irq_take carries the mstatus.MIE qualifier, but a
    -- WFI must resume on a pending+enabled interrupt even with MIE=0 -- with no
    -- term here that hart would sleep forever with clk_cpu gated off, never
    -- evaluating the SLEEPING arm. std_wfi_wake is qualified by wfi_slept, so an
    -- extinguish-entered sleep is untouched, and it is statically '0' when
    -- ENABLE_TRAPCSR is off, so the OFF build's en_clk_cpu is bit-identical.
    en_clk_cpu <= '0' when mem_ready = '0' else
                  '1' when irq_active = '1' else
                  '1' when std_irq_take = '1' else
                  '1' when std_wfi_wake = '1' else
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
            elsif current_state = SC_CHECK or current_state = IRQ_SV
                  or current_state = MTRAP_SV then
                -- P1: a standard trap entry is a context switch exactly like the
                -- legacy IRQ_SV, so it kills the local reservation the same way.
                -- MTRAP_SV is unreachable on an OFF/legacy build => no change.
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
    -- X3 Zicboz block-zero sequencer registers
    -- ==========================================
    -- cboz_base is latched ONCE, on the EXECUTE->CBOZ_WRITE dispatch transition,
    -- from the LIVE rs1 port masked to the naturally-aligned block base
    -- (rs1 & ~(CBOZ_BLOCK_SIZE-1)). It is NEVER re-read mid-burst — the address
    -- source is registered state (the X2 phantom-read invariant). cboz_idx resets
    -- to 0 at dispatch and advances one word per COMPLETED store (incremented in
    -- CBOZ_GAP, the post-store settle cycle, so it names the word already written).
    cboz_seq_proc: process(clk_cpu, resetn)
    begin
        if resetn = '0' then
            cboz_base <= (others => '0');
            cboz_idx  <= 0;
        elsif rising_edge(clk_cpu) then
            if current_state /= CBOZ_WRITE and current_state /= CBOZ_GAP
               and next_state = CBOZ_WRITE then
                -- dispatch edge (EXECUTE -> CBOZ_WRITE): latch base, reset index
                cboz_base <= std_logic_vector(unsigned(rs1_value)
                                 and not to_unsigned(CBOZ_BLOCK_SIZE - 1, 32));
                cboz_idx  <= 0;
            elsif current_state = CBOZ_GAP and cboz_idx /= CBOZ_WORDS - 1 then
                cboz_idx <= cboz_idx + 1;
            end if;
        end if;
    end process;

    -- X3 Zcmp/Zcmt sequencer registers. Latch sub-op, embedded operand bits, and
    -- old sp ONCE at dispatch (EXECUTE -> first ZCM state). zcm_idx counts list
    -- position, advancing one per completed element (ZCM_PUSH_GAP / ZCM_POP_WB).
    zcm_seq_proc: process(clk_cpu, resetn)
    begin
        if resetn = '0' then
            zcm_subop_r <= (others => '0');
            zcm_i16_r   <= (others => '0');
            zcm_sp0     <= (others => '0');
            zcm_idx     <= 0;
        elsif rising_edge(clk_cpu) then
            if current_state = EXECUTE and
               (next_state = ZCM_PUSH_ST or next_state = ZCM_POP_LD or
                next_state = ZCM_MV1 or next_state = ZCM_JT_LD) then
                zcm_subop_r <= instr_curr(14 downto 12);
                zcm_i16_r   <= instr_curr(31 downto 16);
                zcm_sp0     <= stack_pointer;
                zcm_idx     <= 0;
            elsif (current_state = ZCM_PUSH_GAP or current_state = ZCM_POP_WB)
                  and zcm_idx /= zcm_nregs_val - 1 then
                zcm_idx <= zcm_idx + 1;
            end if;
        end if;
    end process;

    zcm_subop <= instr_curr(14 downto 12);
    zcm_rlist <= zcm_i16_r(7 downto 4);
    zcm_spimm <= zcm_i16_r(3 downto 2);
    zcm_index <= zcm_i16_r(9 downto 2);
    zcm_nregs_val    <= zcm_nregs(zcm_rlist);
    zcm_stackadj_val <= zcm_stackadj(zcm_rlist, zcm_spimm);
    zcm_is_push    <= '1' when zcm_subop_r = ZCM_SUB_PUSH    else '0';
    zcm_is_popretz <= '1' when zcm_subop_r = ZCM_SUB_POPRETZ else '0';
    zcm_is_popret  <= '1' when (zcm_subop_r = ZCM_SUB_POPRET or zcm_subop_r = ZCM_SUB_POPRETZ) else '0';
    zcm_is_popfam  <= '1' when (zcm_subop_r = ZCM_SUB_POP or zcm_subop_r = ZCM_SUB_POPRET
                                or zcm_subop_r = ZCM_SUB_POPRETZ) else '0';
    zcm_is_mvsa    <= '1' when zcm_subop_r = ZCM_SUB_MVSA01  else '0';
    zcm_is_mva     <= '1' when zcm_subop_r = ZCM_SUB_MVA01S  else '0';
    zcm_is_move    <= zcm_is_mvsa or zcm_is_mva;
    zcm_is_tabjump <= '1' when zcm_subop_r = ZCM_SUB_TABJUMP else '0';
    zcm_reg_idx   <= zcm_reg_at(zcm_idx);
    zcm_high_addr <= std_logic_vector(unsigned(zcm_sp0) + to_unsigned(zcm_stackadj_val, 32))
                         when zcm_is_popfam = '1' else zcm_sp0;
    zcm_mem_addr  <= std_logic_vector(unsigned(zcm_high_addr)
                         - to_unsigned(4 * (zcm_nregs_val - zcm_idx), 32));
    zcm_final_sp  <= std_logic_vector(unsigned(zcm_sp0) - to_unsigned(zcm_stackadj_val, 32))
                         when zcm_is_push = '1'
                         else std_logic_vector(unsigned(zcm_sp0) + to_unsigned(zcm_stackadj_val, 32));
    zcm_jt_link   <= '1' when unsigned(zcm_index) >= 32 else '0';
    zcm_jt_addr   <= std_logic_vector(unsigned(jvt_value)
                         + to_unsigned(to_integer(unsigned(zcm_index)) * 4, 32));
    zcm_jt_target <= read_data;

    zcm_rs_sel <= '1' when ((ENABLE_ZCMP or ENABLE_ZCMT) and
                    (current_state = ZCM_PUSH_ST or current_state = ZCM_RET or
                     current_state = ZCM_A0Z or current_state = ZCM_MV1 or
                     current_state = ZCM_MV2)) else '0';
    zcm_rs_addr <= zcm_reg_idx                      when current_state = ZCM_PUSH_ST else
                   "00001"                          when current_state = ZCM_RET     else
                   "00000"                          when current_state = ZCM_A0Z     else
                   "01010"                          when (current_state = ZCM_MV1 and zcm_is_mvsa = '1') else
                   zcm_sreg_x(zcm_i16_r(9 downto 7)) when (current_state = ZCM_MV1 and zcm_is_mva = '1') else
                   "01011"                          when (current_state = ZCM_MV2 and zcm_is_mvsa = '1') else
                   zcm_sreg_x(zcm_i16_r(4 downto 2)) when (current_state = ZCM_MV2 and zcm_is_mva = '1') else
                   "00000";
    zcm_rd_sel <= '1' when ((ENABLE_ZCMP or ENABLE_ZCMT) and
                    (current_state = ZCM_POP_WB or current_state = ZCM_A0Z or
                     current_state = ZCM_MV1 or current_state = ZCM_MV2 or
                     current_state = ZCM_JT_WB)) else '0';
    zcm_rd_addr <= zcm_reg_idx                      when current_state = ZCM_POP_WB else
                   "01010"                          when current_state = ZCM_A0Z    else
                   "00001"                          when current_state = ZCM_JT_WB  else
                   zcm_sreg_x(zcm_i16_r(9 downto 7)) when (current_state = ZCM_MV1 and zcm_is_mvsa = '1') else
                   "01010"                          when (current_state = ZCM_MV1 and zcm_is_mva = '1') else
                   zcm_sreg_x(zcm_i16_r(4 downto 2)) when (current_state = ZCM_MV2 and zcm_is_mvsa = '1') else
                   "01011"                          when (current_state = ZCM_MV2 and zcm_is_mva = '1') else
                   "00000";
    zcm_move_sel   <= '1' when ((ENABLE_ZCMP or ENABLE_ZCMT) and
                        (current_state = ZCM_A0Z or current_state = ZCM_MV1 or
                         current_state = ZCM_MV2)) else '0';
    zcm_loadwb_sel <= '1' when ((ENABLE_ZCMP or ENABLE_ZCMT) and current_state = ZCM_POP_WB) else '0';
    dp_result_src <= "010" when (ENABLE_ZCMT and current_state = ZCM_JT_WB) else result_src;

    -- ==========================================
    -- X4 Zfinx FP control glue (all constant-'0' when ENABLE_ZFINX is off, so the
    -- OFF-build datapath/CSR wiring folds away)
    -- ==========================================
    -- Latch rs1/rs2 in the datapath during the EXECUTE dispatch cycle of a
    -- multi-cycle/FMA FP op (the operands are read pre-writeback that cycle).
    -- Half-fetch guard (see fp_flags_we below): during the FIRST cycle of a 32-bit
    -- split fetch (pc(1)='1', quadrant_upper="11", repeat_if='0') instr_curr is
    -- HELD at the PREVIOUS instruction (vesta:~1017), so a prior FP op's decode is
    -- still live here — excluding this cycle stops a phantom re-latch of the FP
    -- operand registers from the held op. The legitimate latch is on the repeat_if
    -- ='1' completion cycle, which this term keeps.
    fp_op_latch <= '1' when (current_state = EXECUTE and (is_fp_multicycle = '1' or is_fp_fma = '1')
                             and not (pc(1) = '1' and quadrant_upper = "11" and repeat_if = '0')) else '0';
    -- FPU_FETCH3: steer the rs2 read port to rs3 and latch fp_rs3_reg.
    fp_fetch3   <= '1' when (current_state = FPU_FETCH3) else '0';
    -- fpu_start asserts ONLY in FPU_WAIT (§C1), so every fp_rs*_reg is stable
    -- before the first edge the unit can sample start.
    fpu_start   <= '1' when (current_state = FPU_WAIT) else '0';

    -- fflags sticky-OR strobe: at FPU_DONE (multi-cycle op's registered flags) OR
    -- during the EXECUTE retire of a single-cycle FP op (fpu_simple's combinational
    -- flags). Driven INDEPENDENT of rd, so rd=x0 still sets flags. The EXECUTE case
    -- is guarded so a misaligned FP op (C disabled) that traps does NOT commit
    -- flags. The final term excludes the compressed HALF-FETCH cycle (pc(1)='1',
    -- quadrant_upper="11", repeat_if='0'), where instr_curr is HELD at the PREVIOUS
    -- instruction (vesta:~1017): a single-cycle FP op followed by a split 32-bit
    -- instruction would otherwise RE-fire this strobe on the half-fetch cycle with
    -- fpu_simple re-evaluating flags from possibly-mutated (rd==rs1) operands — the
    -- phantom-side-effect class (X3 lesson 5). A concurrent statement does not
    -- inherit the EXECUTE sub-arm structure that protects the FSM dispatch arms, so
    -- it must qualify its own EXECUTE term — exactly as amo_lock does (vesta:~1207,
    -- qualifying its EXECUTE term to the real dispatch: amo_op and mem_access_instr).
    fp_flags_we <= '1' when (current_state = FPU_DONE) else
                   '1' when (current_state = EXECUTE and is_fp_singlecycle = '1' and trap = '0'
                             and (ENABLE_COMPRESSED or pc(1) = '0')
                             and not (pc(1) = '1' and quadrant_upper = "11" and repeat_if = '0')) else
                   '0';
    -- datapath already muxes: fpu_simple flags when result_src=110 (single-cycle),
    -- else the multi-cycle unit's flags (valid at FPU_DONE, result_src=111).
    fp_flags_val <= fp_flags;

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
               pc_plus_2 when (current_state = ZCM_JT_WB) else  -- X3 Zcmt cm.jalt link ra=pc+2
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
                  instr_curr_prev when (current_state = FPU_FETCH3) else  -- X4 Zfinx: hold FP instr
                  instr_curr_prev when (current_state = FPU_WAIT) else
                  instr_curr_prev when (current_state = FPU_DONE) else
                  instr_curr_prev when (current_state = IRQ_SV) else
                  -- P1: HOLD the faulting/trapping instruction across the standard
                  -- trap-entry pair. Two reasons: (a) mtval for an illegal
                  -- instruction is taken from instr_curr_prev, which stays stable
                  -- only if instr_curr feeds itself here; (b) no decode of a live
                  -- memory word may leak into these cycles (reg_write_dp is forced
                  -- '0' anyway, but this keeps the decoder quiescent).
                  instr_curr_prev when (current_state = MTRAP_SV) else
                  instr_curr_prev when (current_state = MTRAP_JUMP) else
                  instr_curr_prev when (current_state = MTRAP_RET) else
                  instr_curr_prev when (current_state = IRQ_REST) else
                  instr_curr_prev when (current_state = SLEEPING) else
                  instr_curr_prev when (current_state = AMO_READ) else  -- Keep instruction during AMO
                  instr_curr_prev when (current_state = AMO_WRITEBACK) else
                  instr_curr_prev when (current_state = AMO_COMPUTE) else
                  instr_curr_prev when (current_state = AMO_COMPLETE) else -- TODO: Added
                  instr_curr_prev when (current_state = AMO_WRITE) else
                  instr_curr_prev when (current_state = LR_READ) else
                  instr_curr_prev when (current_state = SC_CHECK) else
                  instr_curr_prev when (current_state = CBOZ_WRITE) else  -- X3 Zicboz: hold cbo.zero
                  instr_curr_prev when (current_state = CBOZ_GAP) else
                  instr_curr_prev when (current_state = ZCM_PUSH_ST) else
                  instr_curr_prev when (current_state = ZCM_PUSH_GAP) else
                  instr_curr_prev when (current_state = ZCM_POP_LD) else
                  instr_curr_prev when (current_state = ZCM_POP_WB) else
                  instr_curr_prev when (current_state = ZCM_A0Z) else
                  instr_curr_prev when (current_state = ZCM_SP_COMMIT) else
                  instr_curr_prev when (current_state = ZCM_RET) else
                  instr_curr_prev when (current_state = ZCM_MV1) else
                  instr_curr_prev when (current_state = ZCM_MV2) else
                  instr_curr_prev when (current_state = ZCM_JT_LD) else
                  instr_curr_prev when (current_state = ZCM_JT_WB) else
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
    -- P1 standard delivery: MTRAP_JUMP loads mtvec.BASE&"00" and MTRAP_RET loads
    -- mepc -- the IRQ_JUMP/ivt_entry idiom exactly (pc_en='1' in those states, and
    -- data_addr falls through to pc_next so the SAME cycle also issues the fetch
    -- from the new PC). MTRAP_SV holds pc_next_reg like IRQ_SV, which is what
    -- makes pc_next_reg the interrupt RESUME PC (identical to the word the legacy
    -- IRQ_SV pushes at sp-4) for the whole entry pair.
    pc_next <= ivt_entry   when (current_state = IRQ_JUMP) else
               trap_mtvec_value when (current_state = MTRAP_JUMP) else
               trap_mepc_value  when (current_state = MTRAP_RET) else
               pc_next_reg when (current_state = MTRAP_SV) else
               pc_next_ret when (current_state = IRQ_REST) else
               pc_next_reg when (current_state = SLEEPING) else
               pc_next_reg when (current_state = IRQ_SV) else
               pc_next_reg when (current_state = AMO_READ or current_state = AMO_WRITEBACK or 
                                current_state = AMO_COMPUTE or current_state = AMO_WRITE) else
               pc_next_reg when (current_state = LR_READ or current_state = SC_CHECK) else
               zcm_jt_target when (current_state = ZCM_JT_WB) else  -- X3 Zcmt table-jump target
               rs1_value when (current_state = ZCM_RET) else        -- X3 Zcmp popret[z] -> ra
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
    -- X3 Zicboz: the store address for the current burst word = block base +
    -- cboz_idx*4. Both operands are REGISTERED (cboz_base latched at dispatch,
    -- cboz_idx the burst counter) — no live regfile port is read mid-sequence.
    -- Placed BEFORE the generic mem_access_instr term (which would otherwise
    -- steer data_addr to the stale ALU_Result during CBOZ_WRITE).
    cboz_zero_addr <= std_logic_vector(unsigned(cboz_base) + to_unsigned(cboz_idx * 4, 32));

    data_addr <= cboz_zero_addr when (current_state = CBOZ_WRITE) else
                 zcm_mem_addr when (current_state = ZCM_PUSH_ST or current_state = ZCM_POP_LD) else
                 zcm_jt_addr  when (current_state = ZCM_JT_LD) else
                 rs1_value  when (current_state = SC_CHECK) else
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
    -- X2 Zabha: replicate the computed sub-word result across all byte lanes
    -- (store_ext idiom); the byte-lane wen commits only the addressed lane.
    amo_write_data_steered <= amo_write_data(7 downto 0) & amo_write_data(7 downto 0) &
                              amo_write_data(7 downto 0) & amo_write_data(7 downto 0)
                                  when instr_curr(14 downto 12) = "000" else
                              amo_write_data(15 downto 0) & amo_write_data(15 downto 0)
                                  when instr_curr(14 downto 12) = "001" else
                              amo_write_data;  -- word AMO: full 32-bit result

    -- X2 Zacas: this AMO is an amocas (compare-and-swap). Detected from the held
    -- instruction (funct5 = CAS_FN5) plus the ENABLE_ZACAS generic. Statically '0'
    -- when ENABLE_ZACAS is false (an amocas encoding traps in decode and never
    -- enters the AMO flow). Drives the datapath rs2-port steering and the
    -- conditional-write gating below.
    cas_op <= '1' when (ENABLE_ZACAS and instr_curr(6 downto 0) = AMO_OPCODE
                       and instr_curr(31 downto 27) = CAS_FN5) else '0';

    -- X2 Zabha: active-low byte-lane enables for the sub-word AMO write, keyed
    -- off the REGISTERED AMO address low bits (amo_addr_low = amo_addr_reg(1:0),
    -- latched at AMO_READ). Keying off the live rs1 port was X2-F1: the rd write
    -- in AMO_WRITEBACK clobbers rs1 for a rd==rs1 AMO, corrupting the lane select.
    -- Word AMO writes all four lanes ("0000"), bit-identical to pre-X2.
    -- X2 Zacas: a CAS whose compare FAILED suppresses the write entirely ("1111"
    -- = no lane, active-low) -- write-enable gating ONLY, so the FSM still issues
    -- the identical AMO_WRITE transaction (same LOCKED trajectory) and the global
    -- reservation unit (keyed on committed lane strobes) does NOT kill reservations
    -- on a fail. Mirrors the SC-fail wen. On a CAS success the normal lane logic
    -- applies (word = "0000").
    amo_wen <= "1111" when (cas_op = '1' and cas_match_reg = '0') else
               "1110" when (instr_curr(14 downto 12) = "000" and amo_addr_low = "00") else
               "1101" when (instr_curr(14 downto 12) = "000" and amo_addr_low = "01") else
               "1011" when (instr_curr(14 downto 12) = "000" and amo_addr_low = "10") else
               "0111" when (instr_curr(14 downto 12) = "000" and amo_addr_low = "11") else
               "1100" when (instr_curr(14 downto 12) = "001" and amo_addr_low(1) = '0') else
               "0011" when (instr_curr(14 downto 12) = "001" and amo_addr_low(1) = '1') else
               "0000";  -- word AMO (funct3=010): all four lanes

    write_data <= pc_next when (current_state = IRQ_SV) else
                  amo_write_data_steered when (current_state = AMO_WRITE) else  -- X2 Zabha: sub-word-steered (word = full result)
                  (others => '0') when (current_state = CBOZ_WRITE) else  -- X3 Zicboz: block-zero payload
                  rs1_value when (current_state = ZCM_PUSH_ST) else  -- X3 Zcmp push: reg[reg_at(idx)] via steered rs1
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
                    "110" when current_state = AMO_WRITEBACK else  -- X2 Zacas: rd-capture window (steer rs2 port to rd + latch amo_cmp_reg; ALU output unused here, datapath muxes default like normal)
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
    -- P1 standard M-mode trap delivery glue (ENABLE_TRAPCSR)
    -- ==========================================
    -- THE coexistence select. Statically '0' when the generic is off, so every
    -- MTRAP_* transition below constant-folds and the OFF netlist is unchanged;
    -- '0' at reset when the generic is ON (mtrapctl.LEGACY resets '1'), which is
    -- why the full legacy suite runs untouched on ON hardware.
    std_mode <= '1' when (ENABLE_TRAPCSR and trap_legacy_mode = '0') else '0';

    -- Standard-mode interrupt take (p0_specs.md 2.3 / 2.4 rule (b)): csr_unit
    -- exports STATE only; the pending decision is made HERE.
    --   take = mstatus.MIE and ((meip and MEIE) or (msip and MSIE) or (mtip and MTIE))
    -- mie_bits is the frozen {MEIE(2), MTIE(1), MSIE(0)} packing.
    std_irq_take <= '1' when (std_mode = '1' and trap_mstatus_mie = '1' and
                              ((trap_irq_meip = '1' and trap_mie_bits(2) = '1') or
                               (trap_irq_msip = '1' and trap_mie_bits(0) = '1') or
                               (trap_irq_mtip = '1' and trap_mie_bits(1) = '1')))
                    else '0';

    -- Dispatch-cycle trap classification. Read ONLY at the clk_cpu edge that
    -- enters MTRAP_SV (mtrap_cause_proc), and the FSM arms that make that
    -- transition all live INSIDE the real-dispatch branches of the EXECUTE decode
    -- tree -- the compressed half-fetch branch ("Need to fetch upper half") is a
    -- separate else-branch with next_state <= EXECUTE unconditionally and NO trap
    -- / ecall / ebreak / irq check. So a half-fetch cycle (where instr_curr still
    -- holds the PREVIOUS instruction, kickoff 3b class 5) can never sample these.
    -- Priority mirrors the FSM arm order exactly: misaligned-PC, illegal, ECALL,
    -- EBREAK; anything else that reaches MTRAP_SV is an interrupt.
    mtrap_disp_int <=
        '1' when (current_state /= EXECUTE) else                                 -- MEMORY_WAIT/DIV_DONE/AMO_*/SLEEPING/... => interrupt
        '0' when ((not ENABLE_COMPRESSED) and pc(1) = '1') else                  -- instruction-address-misaligned
        '0' when (trap = '1' or ecall_op = '1' or ebreak_op = '1') else          -- illegal / ECALL / EBREAK
        '1';                                                                     -- EXECUTE + none of the above => interrupt

    mtrap_disp_code <=
        x"0" when (current_state = EXECUTE and (not ENABLE_COMPRESSED) and pc(1) = '1') else  -- 0  instr addr misaligned
        x"2" when (current_state = EXECUTE and trap = '1') else                               -- 2  illegal instruction
        -- P2: the ECALL cause is the CURRENT privilege (p0_specs.md 2.2 rows
        -- "ECALL from M" / "ECALL from U"). trap_priv_mode is stuck '1' (M) on
        -- any ENABLE_UMODE=false build, so this collapses to the P1 constant 11.
        x"8" when (current_state = EXECUTE and ecall_op = '1' and trap_priv_mode = '0') else  -- 8  ecall from U
        x"B" when (current_state = EXECUTE and ecall_op = '1') else                           -- 11 ecall from M
        x"3" when (current_state = EXECUTE and ebreak_op = '1') else                          -- 3  breakpoint
        -- interrupt codes, spec priority MEI > MSI > MTI
        x"B" when (trap_irq_meip = '1' and trap_mie_bits(2) = '1') else                       -- 0x8000000B
        x"3" when (trap_irq_msip = '1' and trap_mie_bits(0) = '1') else                       -- 0x80000003
        x"7";                                                                                 -- 0x80000007

    -- Latch the classification at the dispatch edge. 5 flops total: the 32-bit
    -- mepc/mtval values are NOT registered -- they are re-derived in MTRAP_SV
    -- from state that is provably held there (pc / pc_next_reg / instr_curr_prev).
    mtrap_cause_proc: process(clk_cpu, resetn)
    begin
        if resetn = '0' then
            mtrap_cause_int  <= '0';
            mtrap_cause_code <= (others => '0');
        elsif rising_edge(clk_cpu) then
            if next_state = MTRAP_SV and current_state /= MTRAP_SV then
                mtrap_cause_int  <= mtrap_disp_int;
                mtrap_cause_code <= mtrap_disp_code;
            end if;
        end if;
    end process;

    -- csr_unit writeback values, valid throughout MTRAP_SV:
    --   mepc  = pc_next_reg for an interrupt (the RESUME PC -- provably the same
    --           word the legacy IRQ_SV pushes at sp-4, since IRQ_SV's write_data
    --           is pc_next and pc_next = pc_next_reg there), else `pc` (the
    --           faulting / ECALL's-own PC; pc_en is '0' from the dispatch edge on,
    --           so pc still holds it).
    --   mtval = the faulting 32-bit encoding for an illegal instruction (mtval
    --           TIER-1), the misaligned PC for cause 0, else 0.
    trap_pc_val    <= pc_next_reg when mtrap_cause_int = '1' else pc;
    trap_cause_val <= mtrap_cause_int & MTRAP_RSVD27 & mtrap_cause_code;
    trap_value_val <= instr_curr_prev when (mtrap_cause_int = '0' and mtrap_cause_code = x"2") else
                      pc              when (mtrap_cause_int = '0' and mtrap_cause_code = x"0") else
                      (others => '0');

    -- One-shot generation on the csr_unit clock domain (see the declaration
    -- comment: csr_unit is on the free-running clk, the FSM on the gated
    -- clk_cpu). The whole block is generate-gated so an OFF build carries no
    -- extra flops at all and both strobes are hard-tied '0'.
    mtrap_sv_lvl  <= '1' when current_state = MTRAP_SV  else '0';
    mtrap_ret_lvl <= '1' when current_state = MTRAP_RET else '0';

    gen_trapcsr_wb: if ENABLE_TRAPCSR generate
        mtrap_we_proc: process(clk, resetn)
        begin
            if resetn = '0' then
                mtrap_sv_d  <= '0';
                mtrap_ret_d <= '0';
            elsif rising_edge(clk) then
                mtrap_sv_d  <= mtrap_sv_lvl;
                mtrap_ret_d <= mtrap_ret_lvl;
            end if;
        end process;
        trap_entry_we_sig <= mtrap_sv_lvl  and not mtrap_sv_d;
        mret_we_sig       <= mtrap_ret_lvl and not mtrap_ret_d;
    end generate;

    gen_trapcsr_wb_off: if not ENABLE_TRAPCSR generate
        mtrap_sv_d        <= '0';
        mtrap_ret_d       <= '0';
        trap_entry_we_sig <= '0';
        mret_we_sig       <= '0';
    end generate;

    -- irq_handler NEUTRALIZATION in standard mode (p0_specs.md 1/2.3): mask every
    -- enable so pending_irqs_comb is all-zero, irq_found never rises and the
    -- handler FSM is pinned in IDLE -- irq_save can therefore never fire, which is
    -- what lets the new std_irq_take arms sit BESIDE the existing irq_save arms
    -- without a priority fight. Statically the identity function when
    -- ENABLE_TRAPCSR is off.
    irq_en_eff <= irq_en when std_mode = '0' else (others => '0');

    -- ==========================================
    -- P2 standard WFI wake rule (ENABLE_TRAPCSR)
    -- ==========================================
    -- p0_specs.md 3: WFI wakes when `(mip and mie) /= 0` REGARDLESS of
    -- mstatus.MIE. This is std_irq_take MINUS the MIE qualifier -- the two are
    -- deliberately separate signals: std_irq_take decides whether a trap is
    -- DELIVERED, std_wfi_pend only whether the hart RESUMES.
    std_wfi_pend <= '1' when ((trap_irq_meip = '1' and trap_mie_bits(2) = '1') or
                              (trap_irq_msip = '1' and trap_mie_bits(0) = '1') or
                              (trap_irq_mtip = '1' and trap_mie_bits(1) = '1'))
                    else '0';

    -- Qualified by wfi_slept, so an EXTINGUISH-entered sleep keeps its exact
    -- legacy/P1 behaviour (it wakes only on a taken interrupt) even on an ON
    -- build with mie armed. Gated on ENABLE_TRAPCSR (NOT ENABLE_UMODE): WFI is
    -- legal on a trapCsr-only build -- only the TW/U legality gating is P2.
    -- Statically '0' when ENABLE_TRAPCSR is off, so the OFF FSM/clock-gate are
    -- bit-identical.
    std_wfi_wake <= '1' when (ENABLE_TRAPCSR and wfi_slept = '1' and std_wfi_pend = '1')
                    else '0';

    -- ==========================================
    -- P2 TRAP-ENTRY SIDE-EFFECT BLOCK (ENABLE_TRAPCSR)
    -- ==========================================
    -- MTRAP_SV/MTRAP_JUMP already suppress every side effect the FSM OWNS
    -- (reg_write_dp, wen, mem_access_instr, sp_write_en -- p0_specs.md 2.3).
    -- Four decode outputs BYPASS the FSM and were still live through those two
    -- cycles, because `read_data` (= the instruction during decode) still holds
    -- the FAULTING encoding until the mtvec fetch lands in the next EXECUTE:
    --   csr_valid -> csr_unit's WRITE ENABLE
    --   isr_ret   -> the legacy irq_handler EOI
    --   sleep_rq / wake_rq -> the free-running `sleep_cpu` flop
    -- That is benign in P1 (an illegal CSR ADDRESS matches no write arm), but
    -- it BREAKS the P2 U-mode gate: maindec's u_gate is keyed on the LIVE
    -- privilege, and privilege flips to M inside MTRAP_SV -- so a U-mode
    -- `csrw mtvec/mepc/mtrapctl/mscratch` trapped correctly and THEN COMMITTED
    -- one cycle later, in M, a full escape. (Found by privucsr CHECK 27: the
    -- decode-side suppression alone was NOT enough.) The rule is the one
    -- p0_specs.md 2.3 already states for the FSM-owned effects, extended to
    -- the four that bypass it: DURING TRAP ENTRY THE FAULTING INSTRUCTION
    -- COMMITS NOTHING. Statically '0' when ENABLE_TRAPCSR is off (the states
    -- are unreachable there), so the OFF and legacy paths are bit-identical.
    trap_entry_seq <= '1' when (ENABLE_TRAPCSR and
                                (current_state = MTRAP_SV or current_state = MTRAP_JUMP))
                      else '0';
    csr_valid_eff  <= csr_valid and not trap_entry_seq;
    isr_ret_eff    <= isr_ret   and not trap_entry_seq;

    -- The entry-reason flop. Set at the WFI dispatch edge, cleared at EVERY
    -- SLEEPING exit (whichever arm takes it). wfi_enter is driven ONLY from the
    -- real-dispatch decode arms of EXECUTE, so it can never be set on a
    -- compressed half-fetch cycle (kickoff 3b class 5), and it cannot coincide
    -- with the clear (that needs current_state = SLEEPING).
    wfi_slept_proc: process(clk_cpu, resetn)
    begin
        if resetn = '0' then
            wfi_slept <= '0';
        elsif rising_edge(clk_cpu) then
            if wfi_enter = '1' then
                wfi_slept <= '1';
            elsif current_state = SLEEPING and next_state /= SLEEPING then
                wfi_slept <= '0';
            end if;
        end if;
    end process;


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
                             wrs_op, wrs_wake, resv_valid_ext,
                             cboz_op, cboz_idx,
                             zcm_op, instr_curr, zcm_idx, zcm_nregs_val,
                             zcm_is_popretz, zcm_is_popret, zcm_jt_link, zcm_final_sp,
                             is_fp_multicycle, is_fp_fma, fpu_done_sig,
                             std_mode, std_irq_take, ecall_op, ebreak_op, mret_op,
                             wfi_op, std_wfi_wake)
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
            wfi_enter <= '0';   -- P2 standard-WFI entry marker

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
            wfi_enter <= '0';   -- P2: only the WFI dispatch arms raise this

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
                        -- P1: instruction-address-misaligned. Standard mode takes
                        -- it as a RECOVERABLE exception (cause 0, mtval = the
                        -- misaligned PC); legacy mode keeps today's terminal
                        -- TRAP_STATE. Statically dead in the Castalia/Argus
                        -- configs (C is on) -- implemented for contract parity.
                        if std_mode = '1' then
                            next_state <= MTRAP_SV;
                        else
                            next_state <= TRAP_STATE;
                        end if;
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
                                    pc_en <= '0';
                                    if std_mode = '1' then
                                        -- P1: RECOVERABLE illegal-instruction
                                        -- exception (cause 2, mtval = the faulting
                                        -- encoding). Zero memory transactions.
                                        next_state <= MTRAP_SV;
                                        reg_write_dp <= '0';
                                        mem_access_instr <= '0';
                                        wen <= (others => '1');
                                    else
                                        next_state <= TRAP_STATE;
                                    end if;
                                elsif ecall_op = '1' or ebreak_op = '1' then
                                    -- P1 ECALL (cause 11) / EBREAK (cause 3), both
                                    -- with mtval = 0 and mepc = the instruction's
                                    -- OWN PC. In legacy mode they are legal decodes
                                    -- with no legacy semantics, so they land in the
                                    -- terminal TRAP_STATE -- exactly where the OFF
                                    -- build's illegal-instruction path puts them.
                                    pc_en <= '0';
                                    reg_write_dp <= '0';
                                    mem_access_instr <= '0';
                                    wen <= (others => '1');
                                    if std_mode = '1' then
                                        next_state <= MTRAP_SV;
                                    else
                                        next_state <= TRAP_STATE;
                                    end if;
                                elsif mret_op = '1' then
                                    -- P1 MRET: PC <- mepc + the mstatus pop, in the
                                    -- dedicated MTRAP_RET state (JALR shape, no
                                    -- memory access, no writeback). Legacy mode:
                                    -- terminal TRAP_STATE, as above.
                                    pc_en <= '0';
                                    reg_write_dp <= '0';
                                    mem_access_instr <= '0';
                                    wen <= (others => '1');
                                    if std_mode = '1' then
                                        next_state <= MTRAP_RET;
                                    else
                                        next_state <= TRAP_STATE;
                                    end if;
                                elsif sleep_rq = '1' then
                                    next_state <= SLEEPING;
                                    pc_en <= '0';
                                elsif wfi_op = '1' then
                                    -- P2 standard WFI: enter SLEEPING and RAISE
                                    -- the entry-reason marker, so the SLEEPING
                                    -- arm applies the STANDARD wake rule instead
                                    -- of extinguish's. pc frozen exactly as for
                                    -- extinguish -- pc_next_reg therefore holds
                                    -- WFI+4, which is BOTH the resume PC and
                                    -- (if we vector) the mepc. No memory access,
                                    -- no writeback: reg_write/WEN for a SYSTEM
                                    -- PRIV encoding are already '0'/"1111".
                                    next_state <= SLEEPING;
                                    pc_en      <= '0';
                                    wfi_enter  <= '1';
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
                                elsif cboz_op = '1' then
                                    -- X3 Zicboz: launch the cbo.zero block-zero
                                    -- store sequencer. NO memory access this cycle
                                    -- (the CBOZ_WORDS stores issue in CBOZ_WRITE);
                                    -- PC frozen until the burst retires. cboz_base
                                    -- is latched from the live rs1 in cboz_seq_proc
                                    -- on THIS EXECUTE->CBOZ_WRITE transition. wen
                                    -- forced inactive so the fetch-addressed cycle
                                    -- commits no write.
                                    mem_access_instr <= '0';
                                    next_state <= CBOZ_WRITE;
                                    pc_en <= '0';
                                    reg_write_dp <= '0';
                                    wen <= (others => '1');
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
                                elsif is_fp_fma = '1' then
                                    -- X4 Zfinx FMA: fetch rs3 then run. pc_en frozen
                                    -- and reg_write_dp forced '0' across the whole
                                    -- dispatch+wait window (writeback lands only in
                                    -- FPU_DONE) — the div-arm ungated-write bug class.
                                    next_state <= FPU_FETCH3;
                                    pc_en <= '0';
                                    reg_write_dp <= '0';
                                elsif is_fp_multicycle = '1' then
                                    next_state <= FPU_WAIT;
                                    pc_en <= '0';
                                    reg_write_dp <= '0';
                                elsif irq_save = '1' then
                                    next_state <= IRQ_SV;
                                    pc_en <= '0';
                                elsif std_irq_take = '1' then
                                    -- P1 standard delivery: the SAME check point, no new one. In
                                    -- standard mode irq_save can never fire (irq_en_eff is masked
                                    -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                                    -- legacy mode std_irq_take is '0' -- the two arms are mutually
                                    -- exclusive by construction. The X3 uninterruptible sequencers
                                    -- stay uninterruptible: they have no irq_save site, so they get
                                    -- no std_irq_take site either.
                                    next_state <= MTRAP_SV;
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
                                pc_en <= '0';
                                if std_mode = '1' then
                                    -- P1: recoverable illegal-instruction exception
                                    next_state <= MTRAP_SV;
                                    reg_write_dp <= '0';
                                    mem_access_instr <= '0';
                                    wen <= (others => '1');
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            elsif ecall_op = '1' or ebreak_op = '1' then
                                -- P1: c.ebreak DECOMPRESSES to EBREAK (c_dec:~676),
                                -- so this compressed arm really can see ebreak_op.
                                -- Same routing as the 32-bit arm. (ECALL/MRET have
                                -- no compressed form; the term costs nothing and
                                -- keeps the four decode arms uniform.)
                                pc_en <= '0';
                                reg_write_dp <= '0';
                                mem_access_instr <= '0';
                                wen <= (others => '1');
                                if std_mode = '1' then
                                    next_state <= MTRAP_SV;
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            elsif mret_op = '1' then
                                pc_en <= '0';
                                reg_write_dp <= '0';
                                mem_access_instr <= '0';
                                wen <= (others => '1');
                                if std_mode = '1' then
                                    next_state <= MTRAP_RET;
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            elsif zcm_op = '1' then
                                mem_access_instr <= '0';
                                reg_write_dp <= '0';
                                pc_en <= '0';
                                wen <= (others => '1');
                                if instr_curr(14 downto 12) = ZCM_SUB_TABJUMP then
                                    next_state <= ZCM_JT_LD;
                                elsif instr_curr(14 downto 12) = ZCM_SUB_PUSH then
                                    next_state <= ZCM_PUSH_ST;
                                elsif instr_curr(14 downto 12) = ZCM_SUB_MVSA01 or
                                      instr_curr(14 downto 12) = ZCM_SUB_MVA01S then
                                    next_state <= ZCM_MV1;
                                else
                                    next_state <= ZCM_POP_LD;
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
                                -- writeback (reg_write_dp defaults to '1' for a
                                -- DIV) so rd is not clobbered with the idle
                                -- ResultSignal (=0) before the divider latches its
                                -- operands. rd is written exactly once, at DIV_DONE.
                                reg_write_dp <= '0';
                            elsif irq_save = '1' then
                                next_state <= IRQ_SV;
                                pc_en <= '0';
                            elsif std_irq_take = '1' then
                                -- P1 standard delivery: the SAME check point, no new one. In
                                -- standard mode irq_save can never fire (irq_en_eff is masked
                                -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                                -- legacy mode std_irq_take is '0' -- the two arms are mutually
                                -- exclusive by construction. The X3 uninterruptible sequencers
                                -- stay uninterruptible: they have no irq_save site, so they get
                                -- no std_irq_take site either.
                                next_state <= MTRAP_SV;
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
                                pc_en <= '0';
                                if std_mode = '1' then
                                    -- P1: recoverable illegal-instruction exception
                                    -- (cause 2, mtval = the faulting encoding).
                                    next_state <= MTRAP_SV;
                                    reg_write_dp <= '0';
                                    mem_access_instr <= '0';
                                    wen <= (others => '1');
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            elsif ecall_op = '1' or ebreak_op = '1' then
                                -- P1 ECALL (11) / EBREAK (3); see the split-fetch
                                -- arm above for the full rationale.
                                pc_en <= '0';
                                reg_write_dp <= '0';
                                mem_access_instr <= '0';
                                wen <= (others => '1');
                                if std_mode = '1' then
                                    next_state <= MTRAP_SV;
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            elsif mret_op = '1' then
                                -- P1 MRET; see the split-fetch arm above.
                                pc_en <= '0';
                                reg_write_dp <= '0';
                                mem_access_instr <= '0';
                                wen <= (others => '1');
                                if std_mode = '1' then
                                    next_state <= MTRAP_RET;
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            elsif sleep_rq = '1' then
                                next_state <= SLEEPING;
                                pc_en <= '0';
                            elsif wfi_op = '1' then
                                -- P2 standard WFI (see the split-fetch arm above
                                -- for the full rationale). WFI is a 32-bit
                                -- SYSTEM encoding with no compressed form, so
                                -- these two word-dispatch arms are the ONLY
                                -- places it can appear -- exactly like
                                -- extinguish/sleep_rq, whose arms it sits beside.
                                next_state <= SLEEPING;
                                pc_en      <= '0';
                                wfi_enter  <= '1';
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
                            elsif cboz_op = '1' then
                                -- X3 Zicboz: launch the cbo.zero block-zero store
                                -- sequencer (see the half-word arm above for the
                                -- rationale). No access this cycle; PC frozen;
                                -- cboz_base latched from rs1 on this transition.
                                mem_access_instr <= '0';
                                next_state <= CBOZ_WRITE;
                                pc_en <= '0';
                                reg_write_dp <= '0';
                                wen <= (others => '1');
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
                            elsif is_fp_fma = '1' then
                                -- X4 Zfinx FMA (see the half-word arm for rationale):
                                -- freeze pc_en, force reg_write_dp '0' across dispatch.
                                next_state <= FPU_FETCH3;
                                pc_en <= '0';
                                reg_write_dp <= '0';
                            elsif is_fp_multicycle = '1' then
                                next_state <= FPU_WAIT;
                                pc_en <= '0';
                                reg_write_dp <= '0';
                            elsif irq_save = '1' then
                                next_state <= IRQ_SV;
                                pc_en <= '0';
                            elsif std_irq_take = '1' then
                                -- P1 standard delivery: the SAME check point, no new one. In
                                -- standard mode irq_save can never fire (irq_en_eff is masked
                                -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                                -- legacy mode std_irq_take is '0' -- the two arms are mutually
                                -- exclusive by construction. The X3 uninterruptible sequencers
                                -- stay uninterruptible: they have no irq_save site, so they get
                                -- no std_irq_take site either.
                                next_state <= MTRAP_SV;
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
                                pc_en <= '0';
                                if std_mode = '1' then
                                    -- P1: recoverable illegal-instruction exception
                                    next_state <= MTRAP_SV;
                                    reg_write_dp <= '0';
                                    mem_access_instr <= '0';
                                    wen <= (others => '1');
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            elsif ecall_op = '1' or ebreak_op = '1' then
                                -- P1: c.ebreak decompresses to EBREAK (c_dec:~676).
                                pc_en <= '0';
                                reg_write_dp <= '0';
                                mem_access_instr <= '0';
                                wen <= (others => '1');
                                if std_mode = '1' then
                                    next_state <= MTRAP_SV;
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            elsif mret_op = '1' then
                                pc_en <= '0';
                                reg_write_dp <= '0';
                                mem_access_instr <= '0';
                                wen <= (others => '1');
                                if std_mode = '1' then
                                    next_state <= MTRAP_RET;
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            elsif zcm_op = '1' then
                                mem_access_instr <= '0';
                                reg_write_dp <= '0';
                                pc_en <= '0';
                                wen <= (others => '1');
                                if instr_curr(14 downto 12) = ZCM_SUB_TABJUMP then
                                    next_state <= ZCM_JT_LD;
                                elsif instr_curr(14 downto 12) = ZCM_SUB_PUSH then
                                    next_state <= ZCM_PUSH_ST;
                                elsif instr_curr(14 downto 12) = ZCM_SUB_MVSA01 or
                                      instr_curr(14 downto 12) = ZCM_SUB_MVA01S then
                                    next_state <= ZCM_MV1;
                                else
                                    next_state <= ZCM_POP_LD;
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
                            elsif std_irq_take = '1' then
                                -- P1 standard delivery: the SAME check point, no new one. In
                                -- standard mode irq_save can never fire (irq_en_eff is masked
                                -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                                -- legacy mode std_irq_take is '0' -- the two arms are mutually
                                -- exclusive by construction. The X3 uninterruptible sequencers
                                -- stay uninterruptible: they have no irq_save site, so they get
                                -- no std_irq_take site either.
                                next_state <= MTRAP_SV;
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
                    wen <= amo_wen;  -- X2 Zabha: byte-lane enables (word AMO = "0000")
                    mem_access_instr <= '1';
                    reg_write_dp <= '0';
                    
                    if irq_save = '1' then
                        next_state <= IRQ_SV;
                        pc_en <= '0';
                    elsif std_irq_take = '1' then
                        -- P1 standard delivery: the SAME check point, no new one. In
                        -- standard mode irq_save can never fire (irq_en_eff is masked
                        -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                        -- legacy mode std_irq_take is '0' -- the two arms are mutually
                        -- exclusive by construction. The X3 uninterruptible sequencers
                        -- stay uninterruptible: they have no irq_save site, so they get
                        -- no std_irq_take site either.
                        next_state <= MTRAP_SV;
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
                    elsif std_irq_take = '1' then
                        -- P1 standard delivery: the SAME check point, no new one. In
                        -- standard mode irq_save can never fire (irq_en_eff is masked
                        -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                        -- legacy mode std_irq_take is '0' -- the two arms are mutually
                        -- exclusive by construction. The X3 uninterruptible sequencers
                        -- stay uninterruptible: they have no irq_save site, so they get
                        -- no std_irq_take site either.
                        next_state <= MTRAP_SV;
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
                    elsif std_irq_take = '1' then
                        -- P1 standard delivery: the SAME check point, no new one. In
                        -- standard mode irq_save can never fire (irq_en_eff is masked
                        -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                        -- legacy mode std_irq_take is '0' -- the two arms are mutually
                        -- exclusive by construction. The X3 uninterruptible sequencers
                        -- stay uninterruptible: they have no irq_save site, so they get
                        -- no std_irq_take site either.
                        next_state <= MTRAP_SV;
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
                    elsif std_irq_take = '1' then
                        -- P1 standard delivery: the SAME check point, no new one. In
                        -- standard mode irq_save can never fire (irq_en_eff is masked
                        -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                        -- legacy mode std_irq_take is '0' -- the two arms are mutually
                        -- exclusive by construction. The X3 uninterruptible sequencers
                        -- stay uninterruptible: they have no irq_save site, so they get
                        -- no std_irq_take site either.
                        next_state <= MTRAP_SV;
                        pc_en <= '0';
                    else
                        next_state <= AMO_COMPLETE;
                    end if;
                -- ==========================================
                -- CBOZ_WRITE State - X3 Zicboz cbo.zero block-zero store
                -- ==========================================
                -- Issue the full-word 0 store for word cboz_idx. wen="0000"
                -- (active-low = ALL FOUR lanes: the FULL-WORD strobe) so every
                -- byte of the word is committed; the global reservation unit sees
                -- an ordinary committed store. data_addr = registered block base +
                -- cboz_idx*4, write_data = 0 (both driven by the CBOZ_WRITE mux
                -- terms above). UNINTERRUPTIBLE: no irq_save check here — the burst
                -- runs to completion before any interrupt is taken. RAM on this
                -- core is idempotent and fault-free (no PMP / no bus fault on the
                -- RAM window), so there is no mid-sequence trap and no re-execution
                -- machinery is needed.
                when CBOZ_WRITE =>
                    pc_en            <= '0';
                    reg_write_dp     <= '0';
                    mem_access_instr <= '1';
                    wen              <= "0000";
                    next_state       <= CBOZ_GAP;

                -- ==========================================
                -- CBOZ_GAP State - req-low settle between block-zero stores
                -- ==========================================
                -- The shared-bus arbiter's WAIT-FOR-RELEASE re-grants a served
                -- master only after its sh_req is OBSERVED low; mem_access='0'
                -- here drops sh_req for one cycle so the NEXT word can be granted
                -- (this is exactly the store->MEMORY_WAIT cadence — no grant-lock,
                -- no new arbiter protocol, amo_lock stays '0'). Still
                -- UNINTERRUPTIBLE. After the last word, retire through MEMORY_WAIT
                -- (PC advance + IRQ re-check happen there). cboz_idx advances in
                -- cboz_seq_proc on this state.
                when CBOZ_GAP =>
                    pc_en            <= '0';
                    reg_write_dp     <= '0';
                    mem_access_instr <= '0';
                    wen              <= (others => '1');
                    if cboz_idx = CBOZ_WORDS - 1 then
                        next_state <= MEMORY_WAIT;
                    else
                        next_state <= CBOZ_WRITE;
                    end if;

                -- X3 Zcmp/Zcmt sequencer states. All UNINTERRUPTIBLE (no irq_save);
                -- sp committed once, last (ZCM_SP_COMMIT); indices/addresses all
                -- from registered state.
                when ZCM_PUSH_ST =>
                    pc_en            <= '0';
                    reg_write_dp     <= '0';
                    mem_access_instr <= '1';
                    wen              <= "0000";
                    next_state       <= ZCM_PUSH_GAP;

                when ZCM_PUSH_GAP =>
                    pc_en            <= '0';
                    reg_write_dp     <= '0';
                    mem_access_instr <= '0';
                    wen              <= (others => '1');
                    if zcm_idx = zcm_nregs_val - 1 then
                        next_state <= ZCM_SP_COMMIT;
                    else
                        next_state <= ZCM_PUSH_ST;
                    end if;

                when ZCM_POP_LD =>
                    pc_en            <= '0';
                    reg_write_dp     <= '0';
                    mem_access_instr <= '1';
                    wen              <= (others => '1');
                    next_state       <= ZCM_POP_WB;

                when ZCM_POP_WB =>
                    pc_en            <= '0';
                    reg_write_dp     <= '1';
                    mem_access_instr <= '0';
                    wen              <= (others => '1');
                    if zcm_idx = zcm_nregs_val - 1 then
                        if zcm_is_popretz = '1' then
                            next_state <= ZCM_A0Z;
                        else
                            next_state <= ZCM_SP_COMMIT;
                        end if;
                    else
                        next_state <= ZCM_POP_LD;
                    end if;

                when ZCM_A0Z =>
                    pc_en            <= '0';
                    reg_write_dp     <= '1';
                    mem_access_instr <= '0';
                    wen              <= (others => '1');
                    next_state       <= ZCM_SP_COMMIT;

                when ZCM_SP_COMMIT =>
                    pc_en            <= '0';
                    reg_write_dp     <= '0';
                    mem_access_instr <= '0';
                    wen              <= (others => '1');
                    sp_write_en      <= '1';
                    sp_write_data    <= zcm_final_sp;
                    if zcm_is_popret = '1' then
                        next_state <= ZCM_RET;
                    else
                        next_state <= MEMORY_WAIT;
                    end if;

                when ZCM_RET =>
                    pc_en            <= '1';
                    reg_write_dp     <= '0';
                    mem_access_instr <= '0';
                    wen              <= (others => '1');
                    next_state       <= EXECUTE;

                when ZCM_MV1 =>
                    pc_en            <= '0';
                    reg_write_dp     <= '1';
                    mem_access_instr <= '0';
                    wen              <= (others => '1');
                    next_state       <= ZCM_MV2;

                when ZCM_MV2 =>
                    pc_en            <= '0';
                    reg_write_dp     <= '1';
                    mem_access_instr <= '0';
                    wen              <= (others => '1');
                    next_state       <= MEMORY_WAIT;

                when ZCM_JT_LD =>
                    pc_en            <= '0';
                    reg_write_dp     <= '0';
                    mem_access_instr <= '1';
                    wen              <= (others => '1');
                    next_state       <= ZCM_JT_WB;

                when ZCM_JT_WB =>
                    pc_en            <= '1';
                    reg_write_dp     <= zcm_jt_link;
                    mem_access_instr <= '0';
                    wen              <= (others => '1');
                    next_state       <= EXECUTE;

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
                    elsif std_irq_take = '1' then
                        -- P1 standard delivery: the SAME check point, no new one. In
                        -- standard mode irq_save can never fire (irq_en_eff is masked
                        -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                        -- legacy mode std_irq_take is '0' -- the two arms are mutually
                        -- exclusive by construction. The X3 uninterruptible sequencers
                        -- stay uninterruptible: they have no irq_save site, so they get
                        -- no std_irq_take site either.
                        next_state <= MTRAP_SV;
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
                    elsif std_irq_take = '1' then
                        -- P1 standard delivery: the SAME check point, no new one. In
                        -- standard mode irq_save can never fire (irq_en_eff is masked
                        -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                        -- legacy mode std_irq_take is '0' -- the two arms are mutually
                        -- exclusive by construction. The X3 uninterruptible sequencers
                        -- stay uninterruptible: they have no irq_save site, so they get
                        -- no std_irq_take site either.
                        next_state <= MTRAP_SV;
                        pc_en <= '0';
                    elsif isr_ret = '1' then
                        next_state <= IRQ_REST;
                    else
                        next_state <= EXECUTE;
                    end if;

                -- ==========================================
                -- FPU_FETCH3 State (X4 Zfinx, FMA only) - fetch rs3
                -- ==========================================
                -- The rs2 read port is steered to the FMA rs3 index this cycle
                -- (datapath rf_a2_addr) and fp_rs3_reg is latched at the edge. PC
                -- frozen, no writeback. fpu_start is NOT asserted here (§C1) — it
                -- decodes from FPU_WAIT only, so every operand register is stable
                -- strictly before the first edge at which the unit samples start.
                when FPU_FETCH3 =>
                    pc_en <= '0';
                    reg_write_dp <= '0';
                    next_state <= FPU_WAIT;

                -- ==========================================
                -- FPU_WAIT State (X4 Zfinx) - run the multi-cycle unit
                -- ==========================================
                -- Exactly the DIV_WAIT contract: pc_en frozen, reg_write_dp '0',
                -- instr held. fpu_start is asserted (concurrently, from state =
                -- FPU_WAIT) while waiting; fpu_done ends the stall.
                when FPU_WAIT =>
                    pc_en <= '0';
                    reg_write_dp <= '0';
                    if fpu_done_sig = '1' then
                        next_state <= FPU_DONE;
                    else
                        next_state <= FPU_WAIT;
                    end if;

                -- ==========================================
                -- FPU_DONE State (X4 Zfinx) - writeback + flags
                -- ==========================================
                -- Mirrors DIV_DONE exactly: reg_write_dp is NOT reassigned here, so
                -- it takes the default reg_write_ctrl (=1 for an FP op) and the
                -- writeback of the fpu result (result_src=111) lands in this cycle.
                -- IRQ/isr_ret handling is identical to DIV_DONE.
                when FPU_DONE =>
                    pc_en <= '1';

                    if irq_save = '1' then
                        next_state <= IRQ_SV;
                        pc_en <= '0';
                    elsif std_irq_take = '1' then
                        -- P1 standard delivery: the SAME check point, no new one. In
                        -- standard mode irq_save can never fire (irq_en_eff is masked
                        -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                        -- legacy mode std_irq_take is '0' -- the two arms are mutually
                        -- exclusive by construction. The X3 uninterruptible sequencers
                        -- stay uninterruptible: they have no irq_save site, so they get
                        -- no std_irq_take site either.
                        next_state <= MTRAP_SV;
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
                -- MTRAP_SV State - P1 standard trap entry (CSR writeback)
                -- ==========================================
                -- Shaped on IRQ_SV, MINUS every memory effect (p0_specs.md 2.3):
                --   * NO push: wen all-ones, mem_access_instr '0', and
                --     sp_write_en left at its '0' default -- sp is NEVER touched
                --     (a U-mode sp is untrusted; software uses mscratch).
                --   * NO writeback: reg_write_dp '0' here AND in MTRAP_JUMP, the
                --     kickoff 3b class-1 phantom-regfile-write guard (instr_curr
                --     still shows the already-retired instruction in these
                --     cycles).
                --   * NO irq_handler handshake: irq_save_ack stays '0' (its
                --     default), because the handler is pinned in IDLE.
                -- The csr_unit writeback itself rides trap_entry_we, a clk-domain
                -- ONE-SHOT of this state (see the gen_trapcsr_wb block) with
                -- trap_pc/trap_cause/trap_value derived from held state.
                -- trap_flag is NOT raised: a standard trap is RECOVERABLE, unlike
                -- the terminal TRAP_STATE.
                when MTRAP_SV =>
                    pc_en            <= '0';
                    wen              <= (others => '1');
                    mem_access_instr <= '0';
                    reg_write_dp     <= '0';
                    next_state       <= MTRAP_JUMP;

                -- ==========================================
                -- MTRAP_JUMP State - P1 standard trap entry (vector)
                -- ==========================================
                -- PC <- mtvec.BASE&"00" via the pc_next mux arm; the same cycle
                -- issues the fetch from there (data_addr falls through to
                -- pc_next), exactly like IRQ_JUMP loading ivt_entry.
                when MTRAP_JUMP =>
                    pc_en            <= '1';
                    wen              <= (others => '1');
                    mem_access_instr <= '0';
                    reg_write_dp     <= '0';
                    next_state       <= EXECUTE;

                -- ==========================================
                -- MTRAP_RET State - P1 MRET
                -- ==========================================
                -- PC <- mepc (pc_next mux arm) plus the mstatus POP in csr_unit
                -- (MIE<=MPIE, MPIE<='1') via the mret_we one-shot. No memory
                -- access, no writeback, no sp touch -- the JALR shape.
                when MTRAP_RET =>
                    pc_en            <= '1';
                    wen              <= (others => '1');
                    mem_access_instr <= '0';
                    reg_write_dp     <= '0';
                    next_state       <= EXECUTE;

                -- ==========================================
                -- IRQ_REST State - Restore context from interrupt
                -- ==========================================
                when IRQ_REST =>
                    if irq_save = '1' then
                        -- Nested interrupt
                        next_state <= IRQ_SV;
                        pc_en <= '0';
                    elsif std_irq_take = '1' then
                        -- P1 standard delivery: the SAME check point, no new one. In
                        -- standard mode irq_save can never fire (irq_en_eff is masked
                        -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                        -- legacy mode std_irq_take is '0' -- the two arms are mutually
                        -- exclusive by construction. The X3 uninterruptible sequencers
                        -- stay uninterruptible: they have no irq_save site, so they get
                        -- no std_irq_take site either.
                        next_state <= MTRAP_SV;
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
                -- P2 adds a THIRD exit (std_wfi_wake) that is taken ONLY by a
                -- WFI-entered sleep. Priority is deliberate:
                --   1. irq_save     -- legacy delivery (masked off in std mode)
                --   2. std_irq_take -- standard delivery: MIE and (mip and mie);
                --                      vector to MTRAP_SV with mepc = the resume
                --                      PC (pc_next_reg = WFI+4). This arm ALSO
                --                      serves a WFI sleep, which is why it comes
                --                      first: "if takeable, deliver".
                --   3. std_wfi_wake -- (mip and mie) /= 0 but NOT takeable
                --                      (mstatus.MIE = 0): the spec's resumption
                --                      rule -- resume at the instruction AFTER
                --                      WFI without entering a handler.
                -- The resume is a plain pc_en='1' load of pc_next = pc_next_reg
                -- (the SLEEPING pc_next mux arm), the same shape as WRS_WAIT's
                -- retire; the fetch of that word has been issued from data_addr
                -- every SLEEPING cycle already (data_addr falls through to
                -- pc_next), so EXECUTE consumes the right instruction. wfi_slept
                -- is cleared by wfi_slept_proc on whichever exit is taken.
                when SLEEPING =>
                    pc_en <= '0';

                    if irq_save = '1' then
                        next_state <= IRQ_SV;
                    elsif std_irq_take = '1' then
                        -- P1 standard delivery: the SAME check point, no new one. In
                        -- standard mode irq_save can never fire (irq_en_eff is masked
                        -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                        -- legacy mode std_irq_take is '0' -- the two arms are mutually
                        -- exclusive by construction. The X3 uninterruptible sequencers
                        -- stay uninterruptible: they have no irq_save site, so they get
                        -- no std_irq_take site either.
                        next_state <= MTRAP_SV;
                    elsif std_wfi_wake = '1' then
                        -- P2: WFI resumption. Statically unreachable when
                        -- ENABLE_TRAPCSR is off, and unreachable for an
                        -- extinguish-entered sleep on ANY build (wfi_slept='0').
                        next_state <= EXECUTE;
                        pc_en      <= '1';
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
            -- P2: no sleep-state update while a trap is being entered (see
            -- the trap_entry_seq block) -- a U-mode extinguish/ignite traps
            -- illegal and must not touch this flop.
            if trap_entry_seq = '0' then
                if wake_rq = '1' then
                    sleep_cpu <= '0';
                elsif sleep_rq = '1' then
                    sleep_cpu <= '1';
                end if;
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
            ecall_op         => ecall_op,
            ebreak_op        => ebreak_op,
            mret_op          => mret_op,
            -- P2: the standard WFI decode out, and the three U-mode decode
            -- inputs straight from csr_unit's frozen 3.1 exports.
            wfi_op           => wfi_op,
            priv_m           => trap_priv_mode,
            status_tw        => trap_status_tw,
            mcounteren_bits  => trap_mcounteren,
            wrs_op           => wrs_op,
            wrs_sto          => wrs_sto,
            mem_access_instr => mem_access_controller,
            trap             => trap,
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
            frm_valid         => frm_valid
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



    alu_control_dp <=   "0001011" when (current_state = AMO_READ or current_state = AMO_WRITE) else 
                        "0001010" when (current_state = SC_CHECK) else -- ALU passes b
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
            result_src  => dp_result_src,  -- X3 Zcmt jalt-link override ("010"); else controller's
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
            cas_op      => cas_op,
            zcm_rs_addr    => zcm_rs_addr,
            zcm_rs_sel     => zcm_rs_sel,
            zcm_rd_addr    => zcm_rd_addr,
            zcm_rd_sel     => zcm_rd_sel,
            zcm_move_sel   => zcm_move_sel,
            zcm_loadwb_sel => zcm_loadwb_sel,
            Zero        => Zero,
            pc_target   => pc_target,
            instr       => instr_curr,
            ALU_result  => ALU_result,
            rs1_value   => rs1_value,
            amo_addr_low => amo_addr_low,
            cas_match   => cas_match_reg,
            alu_done    => alu_done,
            write_data  => write_data_dp,
            read_data   => read_data, --TODO
            sp_in       => sp_write_data,
            sp_out      => stack_pointer,
            sp_write_en => sp_write_en,
            csr_valid   => csr_valid,
            csr_rdata   => csr_rdata,
            csr_wdata   => csr_wdata,
            fp_op_latch => fp_op_latch,
            fp_fetch3   => fp_fetch3,
            fpu_start   => fpu_start,
            frm_value   => frm_value,
            fpu_done    => fpu_done_sig,
            fp_flags    => fp_flags,
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
            -- P1: irq_en_eff == irq_en in legacy mode and on any OFF build; it is
            -- forced ALL-ZERO in standard mode so this FSM never leaves IDLE
            -- (p0_specs.md 1). Consequence for `iret` executed in standard mode:
            -- isr_ret is only ever acted on from WAIT_EOI (irq_handler:~355 and
            -- the WAIT_EOI next-state arm), so it is silently IGNORED here --
            -- the "unspecified-but-bounded, must not wedge" contract.
            irq_en          => irq_en_eff,
            irq_pri         => irq_priority,
            irq_recursion_en => irq_recursion_en,
            irq_active      => irq_active,
            isr_ret         => isr_ret_eff,   -- P2: gated by trap_entry_seq
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
                ENABLE_ZIMOP => ENABLE_ZIMOP,
                ENABLE_ZCMP  => ENABLE_ZCMP,
                ENABLE_ZCMT  => ENABLE_ZCMT
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
    -- P1: MTRAP_SV joins the Zihpm "trap entries taken" event -- the event counts
    -- TRAP ENTRIES, and a standard-mode entry is one. (MTRAP_JUMP/MTRAP_RET do
    -- NOT, mirroring IRQ_JUMP/IRQ_REST, so one entry still counts as one cycle.)
    -- Unreachable on an OFF build => the counter is bit-identical there.
    hpm_ev_trap  <= '1' when (current_state = IRQ_SV or current_state = TRAP_STATE
                              or current_state = MTRAP_SV) else '0';

    -- P1: tap the three standard interrupt levels for the `mip` mirror. The
    -- indices are MemoryMap slot numbers (83/84/85 today), so guard the slice
    -- for any instantiation built with a NUM_IRQS smaller than the meip slot
    -- (vesta's own generic default is 16) -- an out-of-range slice would be an
    -- elaboration error, not a warning.
    gen_mip_taps: if NUM_IRQS > IRQB_EXT_MEIP generate
        trap_irq_msip <= irq_vector(IRQB_CLINT_MSIP);
        trap_irq_mtip <= irq_vector(IRQB_CLINT_MTIP);
        trap_irq_meip <= irq_vector(IRQB_EXT_MEIP);
    end generate;
    gen_mip_taps_none: if NUM_IRQS <= IRQB_EXT_MEIP generate
        trap_irq_msip <= '0';
        trap_irq_mtip <= '0';
        trap_irq_meip <= '0';
    end generate;

    csr_unit_inst : csr_unit
        generic map (
            ENABLE_MUL        => ENABLE_MUL,
            ENABLE_DIV        => ENABLE_DIV,
            ENABLE_ATOMICS    => ENABLE_ATOMICS,
            ENABLE_COMPRESSED => ENABLE_COMPRESSED,
            ENABLE_BITMANIP   => ENABLE_BITMANIP,
            ENABLE_ZIHPM      => ENABLE_ZIHPM,
            ENABLE_ZCMT       => ENABLE_ZCMT,
            ENABLE_ZFINX      => ENABLE_ZFINX,
            ENABLE_TRAPCSR    => ENABLE_TRAPCSR,
            ENABLE_UMODE      => ENABLE_UMODE,
            ENABLE_PMP        => ENABLE_PMP,
            PMP_ENTRIES       => PMP_ENTRIES
        )
        port map (
            clk            => clk,
            resetn         => resetn,
            hart_id        => hart_id,
            jvt_value      => jvt_value,
            fp_flags_we    => fp_flags_we,
            fp_flags_val   => fp_flags_val,
            frm_value      => frm_value,
            frm_valid      => frm_valid,
            csr_addr       => csr_addr,
            csr_write_data => csr_wdata, 
            csr_op         => csr_op,
            csr_valid      => csr_valid_eff,   -- P2: gated by trap_entry_seq
            csr_read_data  => csr_rdata,
            inst_retired   => inst_retired,
            ev_bus_stall   => hpm_ev_stall,
            ev_sleep       => hpm_ev_sleep,
            ev_trap_entry  => hpm_ev_trap,

            -- P1 trap-CSR interface (p0_specs.md 2.4), now DRIVEN by the
            -- MTRAP_SV / MTRAP_RET FSM states. trap_entry_we and mret_we are
            -- clk-domain ONE-SHOTS (csr_unit is on the free-running clk, the FSM
            -- on the gated clk_cpu) -- see gen_trapcsr_wb.
            irq_msip       => trap_irq_msip,
            irq_mtip       => trap_irq_mtip,
            irq_meip       => trap_irq_meip,
            trap_entry_we  => trap_entry_we_sig,
            trap_pc        => trap_pc_val,
            trap_cause     => trap_cause_val,
            trap_value     => trap_value_val,
            mret_we        => mret_we_sig,
            mtvec_value    => trap_mtvec_value,
            mepc_value     => trap_mepc_value,
            mstatus_mie    => trap_mstatus_mie,
            mie_bits       => trap_mie_bits,
            legacy_mode    => trap_legacy_mode,

            -- P2 U-mode exports (p0_specs.md 3.1). trap_priv_mode is stuck '1'
            -- (M) unless ENABLE_UMODE, which is what folds every U-mode decode
            -- restriction out of the OFF and trapCsr-only netlists.
            priv_mode      => trap_priv_mode,
            status_tw      => trap_status_tw,
            mcounteren_bits => trap_mcounteren
        );

end architecture;


