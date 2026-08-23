-- vesta: the RV32 core. Multi-cycle FSM, unified instruction/data bus, optional M/A/C/Zb, privileged and debug extensions.
-- read_data doubles as the instruction during decode, so no combinational mux may be keyed off an address decode of it.
library IEEE;
use IEEE.std_logic_1164.all;
use work.constants.all;
-- MemoryMap supplies the irq_vector slot indices (IRQB_CLINT_MSIP / MTIP / IRQB_EXT_MEIP) the standard mip CSR mirrors.
-- It is compiled before vesta in every cell list and genus read order, and shares no declaration name with work.constants.
use work.MemoryMap.all;
use IEEE.NUMERIC_STD.all;

entity vesta is
    generic (
        PC_RST_VAL : std_logic_vector(XLEN-1 downto 0) := (others => '0');
        NUM_IRQS   : natural := 16;

        -- Core ISA feature switches; the defaults are the full RV32IMAC+Zba/Zbb/Zbs/Zbc core and misa (0x301) advertises the enabled set.
        -- A disabled extension traps as an illegal instruction and its hardware (multiplier, divider, c_dec, Zb* ALU logic) is pruned at elaboration.
        ENABLE_MUL        : boolean := true;   -- M: MUL/MULH/MULHU/MULHSU
        ENABLE_DIV        : boolean := true;   -- M: DIV/DIVU/REM/REMU + div unit
        ENABLE_ATOMICS    : boolean := true;   -- A: LR/SC + AMOs
        ENABLE_COMPRESSED : boolean := true;   -- C: 16-bit instructions (c_dec)
        ENABLE_BITMANIP   : boolean := true;   -- Zba/Zbb/Zbs/Zbc
        /* Fetch-ahead for straddling 32-bit instructions; see the if_ahead declaration for the mechanism.
           It costs one flip-flop and issues no bus cycle the core would not otherwise issue one cycle later, and it changes cycle counts only, never an architectural result.
           It has no effect unless ENABLE_COMPRESSED is also set, since a non-C build never reaches a half-word-aligned PC.
           Default FALSE, like every other optional block: an OFF build is bit-identical to a core that carries no such path at all, so an instantiation that omits this generic gets the fetch behaviour it had before the path existed. */
        ENABLE_IF_AHEAD   : boolean := false;
        -- Optional ISA extensions, all default false for zero behavioural change, fanned out to maindec, alu, c_dec and csr_unit.
        -- Zawrs, Zacas, Zabha and Zihint are consumed at this FSM/sequencer level.
        ENABLE_ZICOND     : boolean := false;  -- Zicond
        ENABLE_ZCB        : boolean := false;  -- Zcb
        ENABLE_ZIMOP      : boolean := false;  -- Zimop/Zcmop
        ENABLE_ZIHINT     : boolean := false;  -- Zihint
        ENABLE_ZIHPM      : boolean := false;  -- Zihpm
        ENABLE_ZAWRS      : boolean := false;  -- Zawrs
        ENABLE_ZABHA      : boolean := false;  -- Zabha
        ENABLE_ZACAS      : boolean := false;  -- Zacas
        ENABLE_ZICBOZ     : boolean := false;  -- Zicboz: cbo.zero block-zero store sequencer
        ENABLE_ZCMP       : boolean := false;  -- Zcmp: compressed push/pop + reg-moves (memory sequencer)
        ENABLE_ZCMT       : boolean := false;  -- Zcmt: compressed table jump + jvt CSR
        ENABLE_ZBKB       : boolean := false;  -- Zbkb
        ENABLE_ZBKC       : boolean := false;  -- Zbkc
        ENABLE_ZBKX       : boolean := false;  -- Zbkx
        ENABLE_ZKN        : boolean := false;  -- Zkn
        ENABLE_ZFINX      : boolean := false;  -- Zfinx
        -- Privileged-architecture switches, default false / 16 entries, fanned out to maindec via the controller (MRET/ECALL/EBREAK/WFI decode, csr_addr_valid) and to csr_unit for the CSR file.
        -- The trap-entry and MRET FSM arms and the PMP check points live at this level.
        ENABLE_TRAPCSR    : boolean := false;  -- trap CSRs + MRET
        ENABLE_UMODE      : boolean := false;  -- U-mode (requires TRAPCSR)
        ENABLE_PMP        : boolean := false;  -- PMP/Smpmp (requires UMODE)
        PMP_ENTRIES       : integer := 16;     -- PMP entry count, 8 or 16
        -- Core-side debug mode: dcsr/dpc/dscratch0/1, DRET, halt request plus halt-on-reset, ebreak-to-debug and single-step.
        /* Stays FALSE here and at every CORE-side declaration site: the component declarations that stand for this core, and the debug_module and jtag_dtm entities (check_entity_defaults.py polices that class).
           A top that instantiates this core and names no debug association inherits this default and gets an inert core, because a silently-enabled debug port is an area and attack-surface surprise.
           Enabling debug is therefore always a named association, never an inherited one.
           The hart_tile and orch_tile WRAPPERS are the deliberate exception and default TRUE: they must carry whatever CORE_ENABLE_DEBUG in MemoryMap.vhd ships, so a bare elaboration of a tile hardens the same core the generated assembly wires. */
        -- Requires ENABLE_TRAPCSR, see the concurrent assert below.
        ENABLE_DEBUG      : boolean := false;
        -- Where a debug entry lands: the first free 256-byte slot in the TCM ISR bank, above .isr_eis at 0xBD00 and below the 0xBF00-0xBFEF headroom and the 0xBFF0 stack top, inside the staged-image window so a tile gets its stub from the ordinary image copy.
        -- 0xBB00 must not be used: it is the parking target of every unused IVT slot, so a stray interrupt would enter the stub too. A generic rather than a constant so a bench can re-aim it.
        DEBUG_ENTRY_ADDR  : std_logic_vector(XLEN-1 downto 0) := x"0000BE00";
        -- Spike lockstep co-simulation: instantiate the read-only vesta_tracer. Default FALSE, so gen_trace elaborates nothing and the netlist, cell lists and regression are untouched.
        -- The tracer has no output ports and drives no signal; its only effect is a text file <TRACE_FILE>_h<hart>.trace, the hart suffix appended at runtime because a generic cannot depend on the hart_id PORT.
        TRACE_ENABLE      : boolean := false;
        TRACE_FILE        : string  := "vesta_trace"
    );
    port (
        clk        : in  std_logic;
        resetn     : in  std_logic;
        sleep      : in  std_logic;
        clk_cpu    : out std_logic;

        -- Unique per-hart ID (the mhartid CSR) as a PORT, so all hart tiles share ONE netlist and are wired per instance.
        hart_id    : in  std_logic_vector(XLEN-1 downto 0) := (others => '0');

        -- Memory Interface
        data_addr  : out std_logic_vector(XLEN-1 downto 0);
        wen        : out std_logic_vector(XLEN_BYTES-1 downto 0);
        write_data : out std_logic_vector(XLEN-1 downto 0);
        read_data  : in  std_logic_vector(XLEN-1 downto 0);
        mask       : in  std_logic_vector(1 downto 0);
        mem_ready  : in  std_logic := '1';                    -- Memory back-pressure; '0' stalls the core (freezes clk_cpu). Defaults '1' for single-master use.

        -- Global LR/SC interface; the defaults make single-master use a no-op. lr_sc_bus tags the current access: "01" LR read, "10" SC write attempt (local reservation check passed), "00" plain.
        -- sc_fail_ext is resv_unit's SC verdict for a shared SC ('1' forces the SC rd result to fail) and must be stable by the end of the SC_CHECK cycle.
        lr_sc_bus   : out std_logic_vector(1 downto 0);
        sc_fail_ext : in  std_logic := '0';

        -- Zawrs: this hart's global reservation-valid level from resv_unit. A hart stalled in wrs.nto/wrs.sto wakes when it drops, meaning a foreign committed store killed the reservation.
        -- Defaults '1' so single-master tops with no resv_unit treat every reservation as live and fall back to the interrupt and timeout wakes.
        resv_valid_ext : in  std_logic := '1';

        -- Cross-hart AMO atomicity: '1' for the whole AMO read-modify-write flow, from the EXECUTE dispatch cycle that runs the shared read through AMO_WRITE.
        -- mp_arbiter samples it at the read's completion and pins the grant to this hart until the write commits. Leave unconnected in single-master tops.
        amo_lock    : out std_logic;

        -- IRQ Interface
        irq_vector   : in  std_logic_vector(NUM_IRQS-1 downto 0);
        irq_priority : in  std_logic_vector(NUM_IRQS-1 downto 0);
        irq_en       : in  std_logic_vector(NUM_IRQS-1 downto 0);
        irq_recursion_en : in std_logic;
        isr_ret      : out std_logic;

        /* Debug interface, inert when ENABLE_DEBUG is false: three levels, no handshake and no resumereq, resume being the exclusive job of a `dret` executed by debug code. Both inputs default '0', so an unconnected instantiation halts nothing.
             dbg_haltreq is UNMASKABLE, neither mstatus.MIE nor mtrapctl.LEGACY qualifying it, and must be dropped once dbg_halted reads '1' or the hart re-halts the instant each `dret` retires; dbg_resethaltreq is held across reset release to halt before the hart runs anything.
             dbg_halted is '1' while the hart is IN DEBUG MODE. A STATE, not a level follower: it stays high after dbg_haltreq drops. */
        dbg_haltreq      : in  std_logic := '0';
        dbg_resethaltreq : in  std_logic := '0';
        dbg_halted       : out std_logic;

        -- Trap Output
        trap_flag      : out std_logic;

        -- Debug Output
        a0           : out std_logic_vector(XLEN-1 downto 0)
    );
end entity;

architecture struct of vesta is

    -- Component declarations.

    component controller
        generic (
            ENABLE_MUL      : boolean := true;
            ENABLE_DIV      : boolean := true;
            ENABLE_ATOMICS  : boolean := true;
            ENABLE_BITMANIP : boolean := true;
            -- The optional-extension subset maindec consumes.
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
            -- The privileged subset maindec consumes.
            ENABLE_TRAPCSR  : boolean := false;
            ENABLE_UMODE    : boolean := false;
            ENABLE_PMP      : boolean := false;
            ENABLE_DEBUG    : boolean := false
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
            -- Standard SYSTEM/PRIV decode, '0' unless ENABLE_TRAPCSR.
            ecall_op         : out std_logic;
            ebreak_op        : out std_logic;
            mret_op          : out std_logic;
            -- WFI decode plus the U-mode decode inputs, inert defaults.
            wfi_op           : out std_logic;
            -- DRET decode plus the debug-mode decode input, default '0' meaning denied.
            dret_op          : out std_logic;
            debug_mode       : in  std_logic := '0';
            priv_m           : in  std_logic := '1';
            status_tw        : in  std_logic := '0';
            mcounteren_bits  : in  std_logic_vector(4 downto 0) := "00000";
            -- The CSR rs1/uimm field is zero, the read-only form.
            csr_rs1_zero     : in  std_logic := '1';
            -- The R-type rs2 field is zero; qualifies the ZEXT.H row.
            rs2_zero         : in  std_logic := '0';
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

            -- Zfinx FP decode.
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
            -- The optional-extension subset the alu consumes.
            ENABLE_ZICOND   : boolean := false;
            ENABLE_ZBKB     : boolean := false;
            ENABLE_ZBKC     : boolean := false;
            ENABLE_ZBKX     : boolean := false;
            ENABLE_ZKN      : boolean := false;
            ENABLE_ZFINX    : boolean := false;
            TRACE_ENABLE    : boolean := false
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
            div_dispatch : in  std_logic;
            amo_phase    : in  std_logic_vector(2 downto 0);  -- 000: normal, 001: AMO_READ, 010: AMO_COMPUTE, 011: AMO_WRITE, 100: SC fail, 101: SC success
            cas_op       : in  std_logic;  -- Zacas: the current AMO is an amocas
            -- Zcmp/Zcmt sequencer regfile steering, all default inactive.
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
            cas_match    : out std_logic;  -- Zacas: registered CAS compare verdict
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
            -- Zfinx FPU control and status, all default inert.
            fp_op_latch  : in  std_logic := '0';
            fp_fetch3    : in  std_logic := '0';
            fpu_start    : in  std_logic := '0';
            frm_value    : in  std_logic_vector(2 downto 0) := "000";
            fpu_done     : out std_logic;
            fp_flags     : out std_logic_vector(4 downto 0);
            -- Lockstep tracer taps, read-only: the regfile a3 and wd3 nets.
            trc_rd_addr  : out std_logic_vector(4 downto 0);
            trc_rd_data  : out std_logic_vector(XLEN-1 downto 0);
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
            -- Zcb expansions and Zcmop (c.mop).
            ENABLE_ZCB   : boolean := false;
            ENABLE_ZIMOP : boolean := false;
            -- Zcmp/Zcmt: the C2 funct3=101 sentinel emit.
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
            -- hpm counters and the Zfinx fcsr.
            ENABLE_ZIHPM      : boolean := false;
            ENABLE_ZCMT       : boolean := false;  -- Zcmt: jvt CSR
            ENABLE_ZFINX      : boolean := false;
            -- The trap-CSR file, the U-mode privilege state and the PMP config/address bank all live in csr_unit.
            ENABLE_TRAPCSR    : boolean := false;
            ENABLE_UMODE      : boolean := false;
            ENABLE_PMP        : boolean := false;
            PMP_ENTRIES       : integer := 16;
            -- Debug-mode CSR file: dcsr, dpc, dscratch0/1 and debug_mode.
            ENABLE_DEBUG      : boolean := false;
            TRACE_ENABLE      : boolean := false
        );
        port (
            clk            : in  std_logic;
            resetn         : in  std_logic;
            hart_id        : in  std_logic_vector(XLEN-1 downto 0) := (others => '0');

            -- Zcmt jvt base export.
            jvt_value      : out std_logic_vector(31 downto 0);

            -- Zfinx fcsr/fflags/frm.
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

            -- Zihpm event inputs: internal vesta signals, not tile ports.
            ev_bus_stall   : in  std_logic := '0';
            ev_sleep       : in  std_logic := '0';
            ev_trap_entry  : in  std_logic := '0';

            -- Trap-CSR interface, inert defaults.
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

            -- U-mode interface.
            priv_mode      : out std_logic;
            status_tw      : out std_logic;
            mcounteren_bits : out std_logic_vector(4 downto 0);

            -- The CSR write-form qualifier in, the effective data-access privilege (mstatus.MPRV redirect) out.
            csr_rs1_zero   : in  std_logic := '0';
            data_priv_m    : out std_logic;
            -- The MRET return privilege, MPP mapped.
            mret_priv_m    : out std_logic;

            -- Debug-mode interface, inert defaults; see csr_unit.vhd.
            dbg_entry_we   : in  std_logic := '0';
            dbg_pc         : in  std_logic_vector(XLEN-1 downto 0) := (others => '0');
            dbg_cause      : in  std_logic_vector(2 downto 0) := (others => '0');
            dbg_ret_we     : in  std_logic := '0';
            debug_mode     : out std_logic;
            dcsr_ebreakm   : out std_logic;
            dcsr_ebreaku   : out std_logic;
            dcsr_step      : out std_logic;
            dpc_value      : out std_logic_vector(XLEN-1 downto 0);

            -- PMP bank exports, all-zero when ENABLE_PMP is false.
            pmp_cfg_flat   : out std_logic_vector(127 downto 0);
            pmp_addr_flat  : out std_logic_vector(479 downto 0);
            -- Lockstep tracer exports, read-only.
            csr_commit_we  : out std_logic;
            csr_commit_val : out std_logic_vector(XLEN-1 downto 0);
            mstatus_value  : out std_logic_vector(XLEN-1 downto 0);
            fflags_value   : out std_logic_vector(XLEN-1 downto 0)
        );
    end component;

    -- PMP/Smpmp: the pure-combinational match, priority and permission decoder; the bank STORAGE lives in csr_unit and every CHECK POINT lives in this file.
    -- Instantiated only inside `gen_pmp: if ENABLE_PMP generate`, so an OFF build's hand-maintained cell lists and netlist are untouched.
    component pmp_unit
        generic (
            ENABLE_PMP  : boolean := false;
            PMP_ENTRIES : integer := 16
        );
        port (
            pmp_cfg_flat  : in  std_logic_vector(127 downto 0);
            pmp_addr_flat : in  std_logic_vector(479 downto 0);
            f_addr        : in  std_logic_vector(31 downto 0);
            f_priv_m      : in  std_logic;
            f_grant       : out std_logic;
            d_addr        : in  std_logic_vector(31 downto 0);
            d_priv_m      : in  std_logic;
            d_read        : in  std_logic;
            d_write       : in  std_logic;
            d_grant       : out std_logic
        );
    end component;

    -- The lockstep tracer (TRACE_ENABLE only) is declared as a COMPONENT and never as a direct entity instantiation: `entity work.x` binds at ANALYSIS and hard-errors in every cell list that compiles this file without vesta_tracer.vhd.
    -- A component binds at ELABORATION and is skipped inside a statically-false generate, so only a flow that turns tracing on needs vesta_tracer.vhd in its file list.
    component vesta_tracer
        generic (
            TRACE_FILE        : string  := "vesta_trace";
            ENABLE_PMP        : boolean := false;
            ENABLE_COMPRESSED : boolean := true;
            TRAPSTORE_LIMIT   : natural := 8;
            -- cpu_state'pos(cpu_state'high)+1, checked against the tracer's ST_COUNT.
            STATE_COUNT       : natural := 0
        );
        port (
            clk_cpu          : in std_logic;                       -- the GATED core clock
            resetn           : in std_logic;
            hart_id          : in std_logic_vector(XLEN-1 downto 0);
            state            : in natural;                         -- cpu_state'pos(current_state)
            next_state       : in natural;                         -- cpu_state'pos(next_state)
            pc               : in std_logic_vector(XLEN-1 downto 0);
            instr            : in std_logic_vector(ILEN-1 downto 0);  -- the raw bus word, read_data
            instr_curr       : in std_logic_vector(ILEN-1 downto 0);  -- the decoded or held instruction
            instr_lower_half : in std_logic_vector(15 downto 0);
            quadrant_upper   : in std_logic_vector(1 downto 0);
            quadrant_lower   : in std_logic_vector(1 downto 0);
            repeat_if        : in std_logic;
            reg_write        : in std_logic;                        -- reg_write_dp, the regfile we3 net
            rd_addr          : in std_logic_vector(4 downto 0);     -- rf_a3_addr, the regfile a3 net
            rd_data          : in std_logic_vector(XLEN-1 downto 0); -- Result, the regfile wd3 net
            sp_write_en      : in std_logic;
            sp_write_data    : in std_logic_vector(XLEN-1 downto 0);
            stack_pointer    : in std_logic_vector(XLEN-1 downto 0);
            data_addr        : in std_logic_vector(XLEN-1 downto 0);
            wen              : in std_logic_vector(XLEN_BYTES-1 downto 0);  -- ACTIVE LOW per byte
            write_data       : in std_logic_vector(XLEN-1 downto 0);
            mem_access_instr : in std_logic;
            funct3           : in std_logic_vector(2 downto 0); sc_fail_ext : in std_logic := '0';  -- instr_curr(14:12); sc_fail_ext SHARES THIS LINE ON PURPOSE, see the port map
            csr_addr         : in std_logic_vector(11 downto 0);
            csr_commit_we    : in std_logic;
            csr_commit_val   : in std_logic_vector(XLEN-1 downto 0);
            mstatus_value    : in std_logic_vector(XLEN-1 downto 0); -- for MTRAP_RET's mret pop
            fflags_value     : in std_logic_vector(XLEN-1 downto 0); fp_flags_we : in std_logic := '0'; fp_flags_val : in std_logic_vector(4 downto 0) := (others => '0');  -- fflags pre-edge plus the post-op OR operands; THREE PORTS SHARE THIS LINE ON PURPOSE, see the port map
            trap             : in std_logic;
            ecall_op         : in std_logic;
            ebreak_op        : in std_logic;
            mret_op          : in std_logic;
            isr_ret          : in std_logic;
            pmp_f_deny_r     : in std_logic;
            pmp_d_deny       : in std_logic;
            trap_pc_val      : in std_logic_vector(XLEN-1 downto 0);  -- MTRAP_SV mepc
            trap_cause_val   : in std_logic_vector(XLEN-1 downto 0);  -- MTRAP_SV mcause
            trap_value_val   : in std_logic_vector(XLEN-1 downto 0);  -- MTRAP_SV mtval
            mtrap_disp_int   : in std_logic;                          -- dispatch-cycle classification
            mtrap_disp_code  : in std_logic_vector(3 downto 0);
            ivt_entry        : in std_logic_vector(XLEN-1 downto 0)   -- legacy vector taken
        );
    end component;

    -- State machine definition. The declaration ORDER is a contract: vesta_tracer's ST_* table mirrors it positionally, so append new states at the TAIL and never insert or reorder.
    type cpu_state is (
        INITIALIZE,   -- Initial state after reset
        SLEEPING,     -- CPU in sleep mode
        EXECUTE,      -- Normal instruction execution
        MEMORY_WAIT,  -- Wait for memory operation
        DIV_WAIT,     -- Wait for division to complete
        DIV_DONE,     -- Division completed
        -- Zfinx FP multi-cycle stall states, modelled on DIV_WAIT/DIV_DONE and UNREACHABLE when ENABLE_ZFINX is off, since every transition into them is constant-false there.
        FPU_FETCH3,   -- FMA rs3 fetch cycle (no 3rd regfile port)
        FPU_WAIT,     -- Wait for the multi-cycle FP unit
        FPU_DONE,     -- FP op completed (writeback here)
        IRQ_SV,       -- Save context for IRQ
        IRQ_REST,     -- Restore context from IRQ
        IRQ_JUMP,     -- Jump to interrupt vector
        TRAP_STATE,   -- Trap state for illegal instructions
        -- Standard M-mode trap delivery (ENABLE_TRAPCSR and mtrapctl.LEGACY=0), shaped on IRQ_SV/IRQ_JUMP but with ZERO memory transactions: no push, no sp_write_en, wen all-ones, reg_write_dp '0' and no irq_handler handshake.
        -- All three are UNREACHABLE when ENABLE_TRAPCSR is false, since every transition into them is qualified by std_mode, so the OFF build's state encoding is bit-identical.
        MTRAP_SV,     -- standard trap entry: write mepc/mcause/mtval plus the mstatus push
        MTRAP_JUMP,   -- standard trap entry: PC takes mtvec.BASE
        MTRAP_RET,    -- MRET: PC takes mepc, mstatus pop (MIE gets MPIE, MPIE gets '1')
        -- RV32A atomic states
        AMO_READ,     -- Read phase of atomic operation
        AMO_WRITEBACK,-- Writeback value to rd 
        AMO_COMPUTE,  -- Compute phase of atomic operation
        AMO_WRITE,    -- Write phase of atomic operation
        AMO_COMPLETE, -- Complete AMO operation
        LR_READ,      -- Load-Reserved read
        SC_CHECK,     -- Store-Conditional check and write
        FENCE_WAIT,   -- FENCE operation wait state
        PAUSE_WAIT,   -- Zihintpause: arbiter-yield hold window
        WRS_WAIT,     -- Zawrs: wait-on-reservation-set stall (wrs.nto/wrs.sto)
        -- Zicboz cbo.zero sequencer: CBOZ_WRITE issues one full-word 0 store, CBOZ_GAP is the req-low settle cycle the arbiter's WAIT-FOR-RELEASE needs between same-master transactions.
        -- The pair repeats CBOZ_WORDS times, UNINTERRUPTIBLE (no irq_save check), then retires through MEMORY_WAIT.
        CBOZ_WRITE,   -- issue the cbo.zero word store for cboz_idx
        CBOZ_GAP,     -- req-low settle between stores; the last one retires via MEMORY_WAIT
        -- Zcmp/Zcmt sequencer states, all UNINTERRUPTIBLE and atomic: RAM here is idempotent and fault-free, so interrupts are simply held to the retire boundary. sp is committed EXACTLY ONCE and LAST, in ZCM_SP_COMMIT.
        -- Every register index and address derives from REGISTERED sequencer state, never from a live regfile-port re-read mid-sequence, or an rd write that aliases rs1 corrupts the sequence.
        ZCM_PUSH_ST,  -- cm.push : store reg[reg_at(idx)] at the frame slot
        ZCM_PUSH_GAP, -- req-low settle; advance idx or go to ZCM_SP_COMMIT
        ZCM_POP_LD,   -- cm.pop* : issue the load of the frame slot
        ZCM_POP_WB,   -- writeback reg[reg_at(idx)] = loaded word; settle; advance
        ZCM_A0Z,      -- cm.popretz only : a0 (x10) gets 0, moved from x0
        ZCM_SP_COMMIT,-- commit sp once (sp_out minus/plus stack_adj); push/pop retire here
        ZCM_RET,      -- cm.popret[z] : redirect PC to reg[ra]
        ZCM_MV1,      -- cm.mvsa01/mva01s : first of the two reg-reg moves
        ZCM_MV2,      -- cm.mvsa01/mva01s : second move; retire
        ZCM_JT_LD,    -- cm.jt/jalt : issue the load of the jvt table entry
        ZCM_JT_WB,    -- capture target; cm.jalt writes ra=pc+2; redirect PC
        -- Debug mode (ENABLE_DEBUG), TAIL-APPENDED because the tracer's ST_* table mirrors this order positionally and a mismatch is silent; the STATE_COUNT generic catches an add or a remove but not a reorder.
        -- All three are UNREACHABLE when ENABLE_DEBUG is false (dbg_halt_take, dbg_ebreak_take and dret_op are statically '0'), and none declares commit intent beyond ci_pc_advance, so the permission tables' zero `others` row makes them inert.
        DBG_SV,       -- debug ENTRY: load dpc/dcsr.cause/prv/debug_mode, then PC takes DEBUG_ENTRY_ADDR
        DBG_JUMP,     -- debug RE-ENTRY (ebreak in debug mode): PC takes DEBUG_ENTRY_ADDR, no CSR write
        DBG_RET       -- DRET: PC takes dpc, debug_mode clears, priv takes dcsr.prv
    );

    signal current_state, next_state : cpu_state;

    -- Commit-intent interface: a state DECLARES what it commits, and the commit block at the tail of next_state_logic is the only place that turns intent into the four nets (reg_write_dp, sp_write_en, wen, pc_en).
    -- Every default is FAIL-SAFE, so a state that declares nothing commits nothing and holds the PC. ci_st_lanes is ACTIVE-HIGH; wen takes its inverse in that one line.
    signal ci_rd_commit  : std_logic;                     -- default '0' : no rd write
    signal ci_sp_commit  : std_logic;                     -- default '0' : no sp write
    signal ci_st_lanes   : std_logic_vector(3 downto 0);  -- ACTIVE-HIGH, default "0000" : no store
    signal ci_pc_advance : std_logic;                     -- default '0' : PC holds

    /* Commit permission masks: "no commit outside a retire group" made structural. Each table names the states in which that commit is LEGITIMATE and the commit block ANDs intent with the table, so a state cannot make a commit it has no business making.
       A state is allowed exactly when its own arm can produce a NONZERO value for that intent signal. Commit state is not retire state for 6 of the 12 commit sites, so a mask keyed on retirement would be wrong.
       There is deliberately NO pc table (a wrong PC hold stops the machine and is loud); the tables are std_logic so the mask is a plain AND, and the lane table holds the permitted lane mask directly. */
    type commit_perm_t is array (cpu_state) of std_logic;
    type lanes_perm_t  is array (cpu_state) of std_logic_vector(3 downto 0);

    constant rd_commit_allowed : commit_perm_t := (
        EXECUTE       => '1',   -- every retiring dispatch shape
        INITIALIZE    => '1',   -- x0-inert pass-through, allowed for exactness
        MEMORY_WAIT   => '1',   -- the LOAD's commit site
        DIV_DONE      => '1',   -- the DIV's
        FPU_DONE      => '1',   -- the multi-cycle/FMA FP op's
        AMO_WRITEBACK => '1',   -- returns the OLD memory word to rd
        LR_READ       => '1',   -- returns the loaded word
        SC_CHECK      => '1',   -- returns success/fail on BOTH paths
        ZCM_POP_WB    => '1',   -- cm.pop frame writeback
        ZCM_A0Z       => '1',   -- cm.popretz clears a0
        ZCM_MV1       => '1',   -- cm.mv, first
        ZCM_MV2       => '1',   -- cm.mv, second
        ZCM_JT_WB     => '1',   -- cm.jalt links ra (conditional on zcm_jt_link)
        others        => '0');

    constant sp_commit_allowed : commit_perm_t := (
        IRQ_SV        => '1',   -- push: sp takes sp-4
        IRQ_REST      => '1',   -- pop:  sp takes sp+4 (both legs)
        ZCM_SP_COMMIT => '1',   -- the ONCE-and-LAST cm.* sp commit
        others        => '0');

    constant st_commit_allowed : lanes_perm_t := (
        EXECUTE       => "1111",   -- dispatch stores, via not wen_controller
        INITIALIZE    => "1111",   -- passes the live decode through (see below)
        AMO_WRITE     => "1111",   -- the AMO's write phase, computed lanes
        SC_CHECK      => "1111",   -- the conditional SC write
        CBOZ_WRITE    => "1111",   -- cbo.zero's full-word store
        ZCM_PUSH_ST   => "1111",   -- cm.push's frame store
        IRQ_SV        => "1111",   -- the full-word PC push
        others        => "0000");
    -- INITIALIZE is in the store list because its arm declares ci_st_lanes as the inverse of wen_controller, a LIVE DECODE, so it is store-capable; MEMORY_WAIT declares no lanes at all and is deliberately absent.

    -- PC management signals.
    signal pc, pc_next           : std_logic_vector(XLEN-1 downto 0);
    signal pc_plus_2, pc_plus_4  : std_logic_vector(XLEN-1 downto 0);
    signal pc_link               : std_logic_vector(XLEN-1 downto 0);  -- JAL/JALR return addr: pc+2 for compressed, else pc+4
    signal pc_target              : std_logic_vector(XLEN-1 downto 0);
    signal pc_next_trad           : std_logic_vector(XLEN-1 downto 0);  -- Traditional PC next value
    signal pc_next_reg            : std_logic_vector(XLEN-1 downto 0);  -- Registered PC next
    signal pc_next_trad_reg       : std_logic_vector(XLEN-1 downto 0);  -- Registered traditional PC next
    signal pc_next_ret            : std_logic_vector(XLEN-1 downto 0);  -- Return PC after IRQ
    signal pc_en                  : std_logic;                      -- PC update enable
    signal pc_src                 : std_logic;                      -- PC source select

    -- Instruction handling signals.
    signal instr                  : std_logic_vector(ILEN-1 downto 0);
    signal instr_curr             : std_logic_vector(ILEN-1 downto 0);  -- Current instruction being executed
    signal instr_curr_prev        : std_logic_vector(ILEN-1 downto 0);  -- Previous instruction (for timing)
    signal instr_decomp           : std_logic_vector(ILEN-1 downto 0);  -- Decompressed instruction
    signal instr_to_decomp        : std_logic_vector(ILEN-1 downto 0);  -- Instruction to decompress
    signal instr_lower_half       : std_logic_vector(15 downto 0);  -- Lower half for split fetch
    signal instr_upper_half       : std_logic_vector(15 downto 0);  -- Upper half for split fetch
    signal instr_assembled        : std_logic_vector(ILEN-1 downto 0);  -- Assembled from split fetch
    signal data_addr_reg          : std_logic_vector(XLEN-1 downto 0);  -- Registered copy of the issued data address

    -- Compressed instruction signals.
    -- is_compressed is assigned in the reset branch and in four EXECUTE arms but is absent from the FSM's default list, so it HOLDS elsewhere and infers a latch; its only reader is qualified by EXECUTE with pc(1)='1' and repeat_if='0', so the held value is never read.
    -- Do not add it to the default list without proving the PMP instruction-access-fault arm, which does not assign it and can run with those same qualifiers.
    signal is_compressed          : std_logic;
    signal is_compressed_cdec     : std_logic;  -- From decompressor (unused)
    signal quadrant_upper         : std_logic_vector(1 downto 0);  -- Upper half instruction type
    signal quadrant_lower         : std_logic_vector(1 downto 0);  -- Lower half instruction type
    signal repeat_if              : std_logic;  -- Repeat instruction fetch flag
    signal repeat_if_req          : std_logic;  -- Request to repeat fetch
    signal clr_repeat_if          : std_logic;  -- Clear repeat fetch flag
    signal ltch_lh_inst           : std_logic;  -- Latch lower half instruction

    /* FETCH-AHEAD (ENABLE_IF_AHEAD). The bubble that repeat_if opens exists only because the cycle before it fetched a word the core ALREADY held.
       When the PC advances by two inside a word, or by four from a half-word-aligned PC, the word the ordinary fetch address names is the word already on instr, so that bus cycle carries no new information.
       This path spends it instead on the NEXT word, and latches the half-word at the next PC into instr_lower_half at the same edge, so the straddling instruction dispatches in ONE cycle.
       It is armed only when the half-word at the next PC is VISIBLE this cycle as instr(31 downto 16) and its quadrant is "11", so the word fetched is the upper half of an instruction the core has already SEEN to be 32-bit, not a guess about where control will go.
       In the EXECUTE-to-EXECUTE case that address is exactly the one the bubble would have named one cycle later, since the bubble cycle is not interruptible. The one case in which the word is fetched and then discarded is an interrupt, halt or trap taken out of the MEMORY_WAIT that issued it; the address is still within eight bytes of the retiring instruction, which is the same class of early fetch the fall-through path already issues. */
    signal if_ahead               : std_logic;  -- The lower half of the instruction at pc is in instr_lower_half and instr carries the next word
    signal if_ahead_req           : std_logic;  -- Arm the fetch-ahead at this edge
    -- Either half-holding path. A straddling 32-bit instruction dispatches this cycle from instr_lower_half plus the live bus word, whether it got there through the bubble or through the fetch-ahead.
    signal split_ready            : std_logic;
    -- The address this cycle presents as an instruction fetch: pc_next, or one word beyond it when the fetch-ahead is armed.
    signal fetch_addr             : std_logic_vector(XLEN-1 downto 0);
    signal if_ahead_addr          : std_logic_vector(XLEN-1 downto 0);  -- the word boundary just past the next PC, derived from pc so it stays off the pc_src path
    signal pc_plus_6              : std_logic_vector(XLEN-1 downto 0);

    -- Control signals.
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

    -- ALU and division signals.
    signal ALU_result             : std_logic_vector(XLEN-1 downto 0);
    signal rs1_value              : std_logic_vector(XLEN-1 downto 0);  -- phase-independent rs1, used for reservation compares and atomic addresses
    signal alu_done               : std_logic;
    signal is_div_op              : std_logic;
    signal div_start              : std_logic;
    signal div_dispatch           : std_logic;  -- the divide dispatch qualifier, see its assignment

    -- Zfinx FP control and status signals.
    signal is_fp_singlecycle      : std_logic;  -- fsgnj*/fmin/fmax/fcmp/fclass (EXECUTE retire)
    signal is_fp_multicycle       : std_logic;  -- fadd/sub/mul/div/sqrt/fcvt (enters FPU_WAIT)
    signal is_fp_fma              : std_logic;  -- fmadd/fmsub/fnmadd/fnmsub (enters FPU_FETCH3)
    signal frm_value              : std_logic_vector(2 downto 0);  -- csr_unit fp_csr[7:5]
    signal frm_valid              : std_logic;  -- '1' iff frm in {000..100}
    signal fpu_start              : std_logic;  -- run pulse to fpu, asserted only in FPU_WAIT so every operand is stable first
    signal fpu_done_sig           : std_logic;  -- fpu complete; paces the move from FPU_WAIT to FPU_DONE. The _sig suffix avoids the FPU_DONE state name (VHDL is case-insensitive)
    signal fp_op_latch            : std_logic;  -- EXECUTE-dispatch strobe: latch rs1/rs2 in datapath
    signal fp_fetch3              : std_logic;  -- '1' in FPU_FETCH3 (steers the a2 read port to rs3)
    signal fp_flags               : std_logic_vector(4 downto 0);  -- completing FP op's flags (from datapath)
    signal fp_flags_we            : std_logic;  -- strobe: OR fp_flags into fflags (to csr_unit)
    signal fp_flags_val           : std_logic_vector(4 downto 0);  -- flag value to csr_unit

    -- Stack pointer management.
    signal sp_write_data          : std_logic_vector(XLEN-1 downto 0);  -- New SP value
    signal stack_pointer          : std_logic_vector(XLEN-1 downto 0);  -- Current SP value
    signal sp_write_en            : std_logic;                      -- SP write enable
    signal write_data_dp          : std_logic_vector(XLEN-1 downto 0);  -- Write data from datapath

    -- Interrupt handling signals.
    signal irq_save               : std_logic;
    signal irq_save_int           : std_logic;
    signal irq_save_ack           : std_logic;
    signal irq_restore            : std_logic;
    signal irq_restore_ack        : std_logic;
    signal irq_active             : std_logic;
    signal ivt_jump               : std_logic;
    signal ivt_entry              : std_logic_vector(XLEN-1 downto 0);

    -- Clock gating and power management.
    signal en_clk_cpu             : std_logic;
    signal sleep_rq               : std_logic;  -- Sleep request from instruction
    signal wake_rq                : std_logic;  -- Wake request from instruction
    signal sleep_cpu              : std_logic;  -- CPU sleep state

    -- Zawrs wait-on-reservation-set; WRS_TIMEOUT_CYCLES is the wrs.sto short timeout in clk_cpu cycles, named so retuning is one line.
    constant WRS_TIMEOUT_CYCLES   : integer := 1024;
    signal wrs_op                 : std_logic;  -- decoded wrs.nto or wrs.sto
    signal wrs_sto                : std_logic;  -- '1' for wrs.sto (has timeout)
    signal wrs_int_pending        : std_logic;  -- any IRQ source asserted (raw, enable-agnostic)
    signal wrs_timeout            : std_logic;  -- wrs.sto short-timeout elapsed
    signal wrs_wake               : std_logic;  -- combined wake condition
    signal wrs_cnt                : integer range 0 to WRS_TIMEOUT_CYCLES;  -- timeout counter (clk_cpu cycles)
    signal wrs_is_sto             : std_logic;  -- latched at entry: this WRS is the timeout variant
                                                -- (instr_curr does not persist through the stall)
    
    -- RV32A atomic operation signals.
    signal amo_op                 : std_logic;  -- AMO operation (not LR/SC)
    signal lr_op                  : std_logic;  -- Load-Reserved operation
    signal sc_op                  : std_logic;  -- Store-Conditional operation
    signal fence_op               : std_logic;  -- FENCE instruction indicator
    -- Zicboz cbo.zero block-zero store sequencer state, clk_cpu domain. cboz_op is the exact cbo.zero decode, '0' when ENABLE_ZICBOZ is off, and cboz_idx runs 0..CBOZ_WORDS-1.
    -- cboz_base is the naturally-aligned block base (rs1 masked by CBOZ_BLOCK_SIZE-1), latched ONCE at dispatch and never re-read mid-burst: a mid-sequence regfile re-read is the phantom-read hazard.
    signal cboz_op                : std_logic;
    signal cboz_base              : std_logic_vector(31 downto 0);
    signal cboz_idx               : integer range 0 to CBOZ_WORDS-1;
    signal cboz_zero_addr         : std_logic_vector(31 downto 0);  -- cboz_base + cboz_idx*4

    -- Zcmp/Zcmt sequencer signals, clk_cpu domain; zcm_op is the cm.* sentinel decode from the controller, '0' when both generics are off.
    -- zcm_subop_r, zcm_i16_r (the embedded compressed operand bits), zcm_sp0 (the old sp) and zcm_idx (position 0..12) are registered at dispatch and are the ONLY source of mid-sequence indices and addresses.
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
    signal pause_hint             : std_logic;  -- Zihintpause: the exact PAUSE hint (fence w,0), '0' when ENABLE_ZIHINT is off
    -- Zihintpause window counter, clk_cpu domain. The range is a fixed generous span and deliberately NOT tied to PAUSE_WINDOW_CYCLES, so a window of 0 cannot make the range static-illegal.
    signal pause_cnt              : natural range 0 to 1023 := 0;
    signal amo_read_data          : std_logic_vector(XLEN-1 downto 0);  -- Saved read data for AMO
    signal amo_new_data           : std_logic_vector(XLEN-1 downto 0);  -- Computed data for AMO write
    signal reservation_valid      : std_logic;  -- LR/SC reservation valid
    signal reservation_addr       : std_logic_vector(XLEN-1 downto 0);  -- LR/SC reservation address
    signal amo_phase              : std_logic_vector(2 downto 0);  -- 000: normal, 001: AMO_READ, 010: AMO_COMPUTE, 011: AMO_WRITE, 100: SC fail, 101: SC success
    signal amo_write_data         : std_logic_vector(XLEN-1 downto 0);  -- Data to write for AMO operations
    signal amo_write_data_steered : std_logic_vector(XLEN-1 downto 0);  -- Zabha: sub-word-replicated AMO write data
    signal amo_wen                : std_logic_vector(XLEN_BYTES-1 downto 0);  -- Zabha: byte-lane write-enable for a sub-word AMO write (active-low)
    signal amo_addr_low           : std_logic_vector(1 downto 0);    -- Zabha: registered AMO address low bits, from the datapath
    signal cas_op                 : std_logic;                        -- Zacas: the current AMO is an amocas (funct5=CAS_FN5, ENABLE_ZACAS)
    signal cas_match_reg          : std_logic;                        -- Zacas: registered CAS compare verdict from the datapath, 1 = match

    -- CSR signals.
    signal csr_addr               : std_logic_vector(11 downto 0);
    signal csr_rdata              : std_logic_vector(XLEN-1 downto 0);
    signal csr_wdata              : std_logic_vector(XLEN-1 downto 0);
    signal csr_op                 : std_logic_vector(2 downto 0);
    signal csr_valid              : std_logic;
    -- The CSR instruction's rs1/uimm FIELD is zero: csr_unit's write-form rule is that CSRRS/C[I] with rs1 or uimm = 0 must not write.
    signal csr_rs1_zero           : std_logic;
    -- The R-type rs2 FIELD is zero; decode legality only, never the register's VALUE. Feeds maindec's ZEXT.H row via the controller.
    signal rs2_zero               : std_logic;
    -- Effective DATA-access privilege from csr_unit (the mstatus.MPRV redirection); consumed by the PMP data-side check.
    signal eff_data_priv_m        : std_logic;
    -- The MRET return privilege (MPP mapped) from csr_unit: the privilege the MRET-target FETCH is checked at during MTRAP_RET.
    signal mret_priv_m            : std_logic;
    -- The effective FETCH-check privilege: trap_priv_mode normally, mret_priv_m during MTRAP_RET.
    -- MTRAP_RET is the one privilege-LOWERING state whose issued fetch is consumed at the new, lower privilege.
    signal pmp_f_priv             : std_logic;
    -- Trap-entry side-effect suppression; see the assignment near the trap glue.
    signal trap_entry_seq         : std_logic;
    signal csr_valid_eff          : std_logic;
    signal isr_ret_eff            : std_logic;
    -- The structural retire path. retire_now is the architectural predicate "an instruction retires at this clk_cpu edge", retire_wfi_armed is its SLEEPING one-shot.
    -- inst_retired is the same predicate qualified into the free-running clk domain that csr_unit's minstret counts on.
    signal retire_now             : std_logic;
    signal retire_wfi_armed       : std_logic;
    signal inst_retired           : std_logic;

    -- Zihpm event levels for csr_unit's hpm counters, sourced only from signals already visible inside vesta.
    -- hpm_ev_stall is mem_ready low (a shared transaction not yet granted and completed), hpm_ev_sleep is the SLEEPING state or the tile sleep input, hpm_ev_trap is an interrupt- or exception-entry state.
    signal hpm_ev_stall           : std_logic;
    signal hpm_ev_sleep           : std_logic;
    signal hpm_ev_trap            : std_logic;

    -- Standard M-mode trap CSR file hookup (ENABLE_TRAPCSR). The three interrupt LEVELS the standard mip mirrors are the same wires the legacy irq_handler consumes, tapped and never latched: mip has no storage by spec.
    signal trap_irq_msip          : std_logic;
    signal trap_irq_mtip          : std_logic;
    signal trap_irq_meip          : std_logic;
    -- csr_unit's trap-CSR exports, consumed by the MTRAP_* states and the legacy delivery mux.
    signal trap_mtvec_value       : std_logic_vector(XLEN-1 downto 0);
    signal trap_mepc_value        : std_logic_vector(XLEN-1 downto 0);
    signal trap_mstatus_mie       : std_logic;
    signal trap_mie_bits          : std_logic_vector(2 downto 0);
    signal trap_legacy_mode       : std_logic;

    -- Standard trap delivery. SYSTEM/PRIV decode from maindec, statically '0' when ENABLE_TRAPCSR is off.
    signal ecall_op               : std_logic;
    signal ebreak_op              : std_logic;
    signal mret_op                : std_logic;
    -- The coexistence mux select, '1' for standard delivery (ENABLE_TRAPCSR and mtrapctl.LEGACY = 0).
    -- Statically '0' on an OFF build so every standard FSM arm constant-folds, and '0' at reset on an ON build because LEGACY resets '1', which is what lets the legacy path run untouched.
    signal std_mode               : std_logic;
    -- Standard-mode interrupt take: mstatus.MIE and (mip and mie) /= 0.
    signal std_irq_take           : std_logic;
    -- Dispatch-cycle trap classification: combinational, and sampled ONLY at the edge that enters MTRAP_SV, so it can never be read on a compressed half-fetch cycle.
    signal mtrap_disp_int         : std_logic;
    signal mtrap_disp_code        : std_logic_vector(3 downto 0);
    -- The same classification latched at the dispatch edge: 5 flops, the Interrupt bit plus the 4-bit code.
    signal mtrap_cause_int        : std_logic;
    signal mtrap_cause_code       : std_logic_vector(3 downto 0);
    -- csr_unit writeback drive; the values are combinational from HELD state.
    signal trap_pc_val            : std_logic_vector(XLEN-1 downto 0);
    signal trap_cause_val         : std_logic_vector(XLEN-1 downto 0);
    signal trap_value_val         : std_logic_vector(XLEN-1 downto 0);
    -- One-shot strobes into csr_unit, which runs on the free-running clk while the FSM runs on the gated clk_cpu: a plain state level would be applied on every clk edge spent in the state.
    -- The mstatus stack push (MPIE takes MIE, MIE takes '0') is NOT idempotent, so these are clk-domain rising-edge one-shots and the writeback lands exactly once however long clk_cpu is gated.
    signal mtrap_sv_lvl           : std_logic;
    signal mtrap_sv_d             : std_logic;
    signal mtrap_ret_lvl          : std_logic;
    signal mtrap_ret_d            : std_logic;
    signal trap_entry_we_sig      : std_logic;
    signal mret_we_sig            : std_logic;
    -- irq_handler enable mask after the standard-mode neutralization gate.
    signal irq_en_eff             : std_logic_vector(NUM_IRQS-1 downto 0);
    -- mcause bits 30:4 are hardwired 0; csr_unit stores only bit 31 and code(3:0).
    constant MTRAP_RSVD27         : std_logic_vector(26 downto 0) := (others => '0');

    -- U-mode and standard WFI. csr_unit's exports; trap_priv_mode reads '1' (M) for all time on an ENABLE_UMODE=false build, so maindec's U-mode gate folds.
    signal trap_priv_mode         : std_logic;
    signal trap_status_tw         : std_logic;
    signal trap_mcounteren        : std_logic_vector(4 downto 0);
    -- maindec's standard-WFI decode, '0' unless ENABLE_TRAPCSR.
    signal wfi_op                 : std_logic;
    -- WFI entry-reason marker: SLEEPING is entered by two instructions with DIFFERENT wake rules. `extinguish` wakes only on a TAKEN interrupt; WFI wakes on (mip and mie) /= 0 regardless of mstatus.MIE, vectoring to MTRAP_SV if takeable and otherwise resuming after the WFI.
    -- wfi_enter is set at the WFI dispatch edge only, from the real-dispatch decode arms so a compressed half-fetch cycle cannot set it, and wfi_slept is cleared on EVERY exit from SLEEPING.
    signal wfi_slept              : std_logic;
    signal wfi_enter              : std_logic;
    -- (mip and mie) /= 0, the MIE-agnostic pending term the standard WFI wake rule uses: std_irq_take's three sources and mie packing minus the mstatus.MIE qualifier.
    signal std_wfi_pend           : std_logic;
    -- The wake itself: only ever asserted for a WFI-entered sleep.
    signal std_wfi_wake           : std_logic;

    -- Debug mode (ENABLE_DEBUG). csr_unit's exports are reset constants on an OFF build (debug_mode '0', the three dcsr bits '0', dpc zero), which is what makes every take signal below statically '0' and every FSM arm fold.
    signal debug_mode             : std_logic;
    signal dcsr_ebreakm           : std_logic;
    signal dcsr_ebreaku           : std_logic;
    signal dcsr_step              : std_logic;
    signal dbg_dpc_value          : std_logic_vector(XLEN-1 downto 0);
    -- maindec's DRET decode, '0' unless ENABLE_DEBUG AND in debug mode.
    signal dret_op                : std_logic;
    -- The takes: separate signals with different qualifier sets, tested at different points in the decode tree.
    signal dbg_halt_take          : std_logic;   -- haltreq or resethaltreq or step, and not already halted
    signal dbg_step_take          : std_logic;   -- the step re-entry alone (feeds the cause mux)
    signal dbg_ebreak_take        : std_logic;   -- ebreak diverts to debug rather than to the trap path
    -- A SYNCHRONOUS exception taken while ALREADY in debug mode re-enters at DEBUG_ENTRY_ADDR instead of taking the trap path.
    -- Tested at the same dispatch points as dbg_ebreak_take but answering a different question: whether this hart may leave debug mode through a trap at all.
    signal dbg_exc_take           : std_logic;
    -- Interrupt delivery is suppressed in debug mode, on both the legacy and the standard path.
    -- Kept a SEPARATE signal from dbg_exc_take even though the predicate is identical, so either can be changed without touching the other; the duplicate term is combinational and costs nothing.
    signal dbg_irq_block          : std_logic;
    -- The en_clk_cpu ungate, the same expression as dbg_halt_take under its own name because it answers a different question, whether this hart gets a clock at all.
    signal dbg_halt_pend          : std_logic;
    -- WAIT-FOR-RELEASE on the halt request; see the assignment below.
    signal dbg_req_mask           : std_logic;
    signal dbg_haltreq_eff        : std_logic;
    -- Halt on reset: dbg_rsthalt_r is SAMPLED ONCE, at the first free-clk edge after this core's reset release (dbg_rst_armed is the one-shot), then held until the debug entry it causes.
    -- It must not level-follow the request: a request raised on a RUNNING hart would then halt it, whereas the contract is to halt at the next deassertion of reset.
    signal dbg_rsthalt_r          : std_logic;
    signal dbg_rst_armed          : std_logic;
    -- Single step: armed at the DRET that carried dcsr.step, consumed by the next entry.
    -- The step diverts at the stepped instruction's OWN dispatch cycle, like an interrupt divert, so that instruction retires and dpc becomes pc_next_reg; diverting at the next dispatch would retire two instructions per step.
    signal dbg_step_armed         : std_logic;
    -- Dispatch-cycle cause classification and its latch, read ONLY at the clk_cpu edge that ENTERS DBG_SV so the value is stable for the whole state and for the free-clk strobe that consumes it.
    -- Codes: 1 ebreak, 3 haltreq, 4 step, 5 resethaltreq.
    signal dbg_disp_cause         : std_logic_vector(2 downto 0);
    signal dbg_cause_r            : std_logic_vector(2 downto 0);
    -- The dpc value, selected by the LATCHED cause: a synchronous ebreak records its OWN pc, a halt or a step records pc_next_reg, the resume PC.
    signal dbg_pc_val             : std_logic_vector(XLEN-1 downto 0);
    -- The two one-shots, generated on the csr_unit clock domain exactly as mtrap_sv_lvl and mtrap_ret_lvl are.
    -- That is the only mechanism in this core for a gated-clk state to commit a free-clk CSR side effect exactly once.
    signal dbg_sv_lvl             : std_logic;
    signal dbg_sv_d               : std_logic;
    signal dbg_ret_lvl            : std_logic;
    signal dbg_ret_d              : std_logic;
    signal dbg_entry_we_sig       : std_logic;
    signal dbg_ret_we_sig         : std_logic;

    /* PMP check integration (ENABLE_PMP), strict pre-issue; every signal below is statically '0', '1' or zero when ENABLE_PMP is false. hart_tile derives the arbiter request from the ADDRESS ALONE, so "a denied access issues no transaction" is exactly "the denied address never reaches data_addr", and both check points are shaped to that one invariant:
         DATA  : a denial forces mem_access_instr '0' and wen all-ones and gates the sequencer address terms, so data_addr stays on the fetch fall-through; SC's only transaction lives in SC_CHECK, which a denial never enters.
         FETCH : the fall-through fetch_addr arm of the data_addr mux is the one place this core issues a fetch, and a denial parks data_addr on PC_RST_VAL, which is fetchable and side-effect-free by construction.
                 The park arm sits BELOW every data-access arm of that mux, so a fetch address denied in a cycle that is carrying a load, a store or a sequencer access on the bus cannot displace it. */
    signal pmp_cfg_flat_sig       : std_logic_vector(127 downto 0);
    signal pmp_addr_flat_sig      : std_logic_vector(479 downto 0);
    -- Fetch port; f_addr is fetch_addr, the address the CURRENT cycle would put on the bus as an instruction fetch.
    signal pmp_f_grant            : std_logic;
    signal pmp_f_deny             : std_logic;
    /* The 1-deep clk_cpu pipeline of that port. INVARIANT: in any EXECUTE cycle, pmp_f_deny_r and pmp_f_addr_r describe the fetch the IMMEDIATELY PRECEDING core cycle issued.
       That is always the word this EXECUTE decodes, or on a split-fetch completion the UPPER half of the straddling 32-bit instruction, which is why ONE fetch port covers both halves.
       The fetch-ahead does not weaken this: it moves the upper half's fetch one cycle earlier, into the cycle that retires the instruction before, and that fetch is still the one the IMMEDIATELY PRECEDING cycle issued when the completion cycle reads the flop.
       The address is the same one the bubble would have named, since both name the word boundary just past the next PC, so the denial verdict and the mtval it reports are unchanged. */
    signal pmp_f_deny_r           : std_logic;
    signal pmp_f_addr_r           : std_logic_vector(XLEN-1 downto 0);
    -- '1' in the EXECUTE cycle that would consume a fetch which never issued: the decoder is looking at the PARK word, so this cycle must commit NOTHING.
    signal pmp_if_squash          : std_logic;
    -- trap_entry_seq OR pmp_if_squash: the decode-bypassing side effects (csr_valid, isr_ret, sleep_cpu) are killed by either.
    signal dec_squash             : std_logic;
    -- The POSITIVE form of that rule: '1' in exactly the cycle in which the decode of instr_curr is a DISPATCHING instruction and may commit a side effect that bypasses the FSM. See the assignment for the per-term justification.
    signal dec_dispatch           : std_logic;
    -- data_addr park select (see the mechanism note above).
    signal pmp_if_park            : std_logic;
    -- Data port.
    signal pmp_d_grant            : std_logic;
    signal pmp_d_addr             : std_logic_vector(XLEN-1 downto 0);
    signal pmp_d_rd               : std_logic;
    signal pmp_d_wr               : std_logic;
    signal pmp_d_active           : std_logic;
    -- '1' when the denied access is of the STORE class (store, SC, AMO, cbo.zero, cm.push), reporting cause 7; '0' for the LOAD class (load, LR, cm.pop, Zcmt table fetch), reporting cause 5.
    -- This is the ACCESS CLASS, not the permission need: LR, SC and AMO all check R and W, but a denied LR still reports cause 5.
    signal pmp_d_st_class         : std_logic;
    signal pmp_d_deny             : std_logic;
    -- The faulting address for mtval (causes 1, 5 and 7): combinational at the dispatch cycle, LATCHED at the MTRAP_SV dispatch edge because neither source is stable during MTRAP_SV.
    signal mtrap_disp_val         : std_logic_vector(XLEN-1 downto 0);
    signal mtrap_val_r            : std_logic_vector(XLEN-1 downto 0);

    -- Lockstep tracer taps, read-only: the committed-write values not otherwise visible at this level, two from the datapath (the regfile a3 and wd3 nets) and four from csr_unit.
    -- They are mapped unconditionally, since a port map cannot be conditional, but TRACE_ENABLE is threaded into both sub-blocks so the driving logic does not exist in an OFF build. Do not rely on the optimiser to remove it instead.
    signal trc_rd_addr            : std_logic_vector(4 downto 0);
    signal trc_rd_data            : std_logic_vector(XLEN-1 downto 0);
    signal csr_commit_we          : std_logic;
    signal csr_commit_val         : std_logic_vector(XLEN-1 downto 0);
    signal mstatus_value          : std_logic_vector(XLEN-1 downto 0);
    signal fflags_value           : std_logic_vector(XLEN-1 downto 0);

    -- Zcmp/Zcmt helper functions: pure combinational spec tables.
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
        elsif r < 4 then
            -- Reserved rlist encodings 0-3 never reach the ZCM states, but this lookup is concurrent and is evaluated from reset with rlist = "0000", where r-3 would violate zcm_nregs_val's range 1..13.
            -- Clamp reserved encodings to the range floor; defined encodings 4-15 are untouched.
            return 1;
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

    instr <= read_data;

    /* Enable the CPU clock unless the core is stalled or asleep. mem_ready = '0' freezes state, PC and all read-data latching while the combinational data_addr/wen request stays asserted, and it has TOP priority so a stall cannot be overridden by an interrupt.
       Every wake source needs its OWN ungate at that same precedence, or a hart sleeps forever with clk_cpu gated and never evaluates the SLEEPING arm: irq_active (legacy), std_irq_take (standard, where irq_active can never rise), std_wfi_wake (a WFI resumes even with mstatus.MIE=0) and dbg_halt_pend (a parked hart must still sample a halt request).
       The DEBUG-HALTED state is deliberately NOT in the gating list: a halted core keeps clk_cpu running, which is what lets it execute debug-ROM and program-buffer instructions at all. */
    en_clk_cpu <= '0' when mem_ready = '0' else
                  '1' when irq_active = '1' else
                  '1' when std_irq_take = '1' else
                  '1' when std_wfi_wake = '1' else
                  '1' when dbg_halt_pend = '1' else
                  '0' when sleep = '1' else
                  '0' when current_state = SLEEPING else
                  '1';

    cg_clk_cpu: entity work.ClkGate
        port map (
            ClkIn  => clk,
            En     => en_clk_cpu,
            ClkOut => clk_cpu
        );

    /* THE RETIRE STROBE: "an instruction retires at this clk_cpu edge". Never derive it from a gated clock (a level so derived sticks high through a stall and counts one phantom retire per stalled cycle) or from `next_state = EXECUTE` alone, which counts EXECUTE CYCLES and double-counts every split 32-bit fetch.
       Not a function of pc_en: an interrupt divert takes away only pc_en and the diverted instruction still retires, and pc_en is '1' with no retire in INITIALIZE, IRQ_JUMP, MTRAP_JUMP, FENCE_WAIT and AMO_COMPLETE. All exclusions below are ANDed, so this does not depend on the FSM's arm ORDER.
       `iret` RETIRES here even though the tracer's comparison contract excludes it, the reference model having no encoding for this custom instruction; its trajectory passes through single-cycle MEMORY_WAIT, so rule 2 counts it exactly once. */
    retire_now <=
        -- 1. EXECUTE.
        '1' when (current_state = EXECUTE
                  and not (ENABLE_PMP and pmp_f_deny_r = '1')            -- PMP fetch deny
                  and not ((not ENABLE_COMPRESSED) and pc(1) = '1')      -- misaligned PC on a non-C build
                  and not (pc(1) = '1' and quadrant_upper = "11"
                           and split_ready = '0')                        -- the split-fetch bubble
                  and trap = '0' and ecall_op = '0' and ebreak_op = '0'  -- trap sub-arms
                  and mret_op = '0'                                      -- retires at MTRAP_RET
                  and not (ENABLE_PMP and pmp_d_deny = '1')              -- PMP data deny
                  -- DBG_SV belongs in this closed whitelist: a halt or step divert takes away only pc_en, so the diverted instruction still retires, and for a single step that retire IS the step.
                  -- vesta_tracer carries the same term in its own copy of this condition; the copies differ on purpose only in the MEMORY_WAIT isr_ret term, and any other mismatch is silent.
                  and (next_state = EXECUTE  or next_state = IRQ_SV or
                       next_state = MTRAP_SV or next_state = FENCE_WAIT or
                       next_state = DBG_SV)) else
        -- 2. MEMORY_WAIT, deliberately without an `isr_ret = '0'` qualifier so that `iret` counts.
        '1' when (current_state = MEMORY_WAIT) else
        -- 3. SLEEPING: the exit cycle of an ARMED sleep only. SLEEPING has a second entry, the return-to-sleep arm of IRQ_REST, so an unqualified exit would invent a retire on every parked-hart interrupt round trip.
        '1' when (current_state = SLEEPING and next_state /= SLEEPING
                  and retire_wfi_armed = '1') else
        -- 4 onward: unconditional in the state, no arm can suppress the commit.
        -- DBG_RET sits beside MTRAP_RET on the same argument, but DBG_SV and DBG_JUMP do NOT retire: an entry executes nothing and the retire that accompanies a halt belongs to the diverting state above.
        '1' when (current_state = DIV_DONE  or current_state = FPU_DONE  or
                  current_state = LR_READ   or current_state = SC_CHECK  or
                  current_state = AMO_WRITE or current_state = MTRAP_RET or
                  current_state = DBG_RET   or
                  current_state = ZCM_RET   or current_state = ZCM_JT_WB) else
        -- PAUSE_WAIT retires on the window-close cycle only.
        '1' when (current_state = PAUSE_WAIT and pause_cnt = 0) else
        -- WRS_WAIT retires on the wake cycle only.
        '1' when (current_state = WRS_WAIT and wrs_wake = '1') else
        '0';

    -- The SLEEPING one-shot: set at the only real WFI or extinguish dispatch edge, EXECUTE into SLEEPING, and cleared on the first SLEEPING exit whichever arm takes it; set and clear cannot coincide.
    -- Do not reuse wfi_slept here: it looks identical but is set from wfi_enter, which the extinguish arms never raise and which is statically '0' without ENABLE_TRAPCSR, so it would drop the retire of every extinguish.
    retire_wfi_arm_proc: process(clk_cpu, resetn)
    begin
        if resetn = '0' then
            retire_wfi_armed <= '0';
        elsif rising_edge(clk_cpu) then
            if current_state = EXECUTE and next_state = SLEEPING then
                retire_wfi_armed <= '1';
            elsif current_state = SLEEPING and next_state /= SLEEPING then
                retire_wfi_armed <= '0';
            end if;
        end if;
    end process;

    /* The domain crossing: one clk_cpu cycle gives exactly one increment. clk_cpu is ClkGate(clk, en_clk_cpu), so its edges are a SUBSET of clk's and this is edge removal, not a clock-domain crossing.
       ClkGate latches En while the clock is low, so a clk_cpu edge occurs only where en_clk_cpu was '1' at the end of the low phase, which is exactly what a clk-edge flop in csr_unit samples; a stall therefore integrates nothing and the releasing cycle counts once.
       A toggle flop is deliberately not used here: it adds a same-edge launch/capture path into a tile with picosecond setup margin. */
    inst_retired <= retire_now and en_clk_cpu;

    -- BINDING: vesta_tracer must NOT consume retire_now. It implements the same predicate independently, with its own armed flag.
    -- Wiring this signal into it would make the two agree by construction and destroy the only thing that makes their agreement evidence.


    -- pc_next_ret is simply read_data: its one consumer, the IRQ_REST arm of the pc_next mux, samples the popped return PC off the bus at the IRQ_REST clk_cpu edge, precisely the cycle in which read_data carries it.
    -- Do not add a latch here: clk_cpu can only rise where en_clk_cpu was already '1', so any en_clk_cpu-qualified hold would be permanently transparent.
    pc_next_ret <= read_data;

    -- RV32A reservation management.
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
                reservation_addr <= rs1_value;  -- rs1 IS the LR address, phase-independent
            -- Clear the reservation on SC, interrupt or context switch.
            elsif current_state = SC_CHECK or current_state = IRQ_SV
                  or current_state = MTRAP_SV then
                -- A standard trap entry is a context switch exactly like the legacy IRQ_SV, so it kills the local reservation the same way.
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

    -- Zicboz block-zero sequencer registers. cboz_base is latched ONCE, on the EXECUTE-to-CBOZ_WRITE dispatch transition, from the live rs1 port masked to the naturally-aligned block base, and is never re-read mid-burst.
    -- cboz_idx resets to 0 at dispatch and advances one word per COMPLETED store, in CBOZ_GAP, so it names the word already written.
    cboz_seq_proc: process(clk_cpu, resetn)
    begin
        if resetn = '0' then
            cboz_base <= (others => '0');
            cboz_idx  <= 0;
        elsif rising_edge(clk_cpu) then
            if current_state /= CBOZ_WRITE and current_state /= CBOZ_GAP
               and next_state = CBOZ_WRITE then
                -- Dispatch edge from EXECUTE into CBOZ_WRITE: latch the base, reset the index.
                cboz_base <= std_logic_vector(unsigned(rs1_value)
                                 and not to_unsigned(CBOZ_BLOCK_SIZE - 1, 32));
                cboz_idx  <= 0;
            elsif current_state = CBOZ_GAP and cboz_idx /= CBOZ_WORDS - 1 then
                cboz_idx <= cboz_idx + 1;
            end if;
        end if;
    end process;

    -- Zcmp/Zcmt sequencer registers: latch the sub-op, the embedded operand bits and the old sp ONCE at dispatch, on the edge from EXECUTE into the first ZCM state.
    -- zcm_idx counts list position, advancing one per completed element, in ZCM_PUSH_GAP or ZCM_POP_WB.
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

    /* Zfinx FP control glue, all constant '0' when ENABLE_ZFINX is off so the OFF-build datapath and CSR wiring folds away.
       Latch rs1 and rs2 in the datapath during the EXECUTE dispatch cycle of a multi-cycle or FMA FP op, where the operands are read pre-writeback.
       The final term excludes the first cycle of a 32-bit split fetch, where instr_curr is HELD at the previous instruction: without it a prior FP op re-latches its operands. The legitimate latch is the split_ready='1' completion cycle, reached by either half-holding path. */
    fp_op_latch <= '1' when (current_state = EXECUTE and (is_fp_multicycle = '1' or is_fp_fma = '1')
                             and not (pc(1) = '1' and quadrant_upper = "11" and split_ready = '0')) else '0';
    -- FPU_FETCH3: steer the rs2 read port to rs3 and latch fp_rs3_reg.
    fp_fetch3   <= '1' when (current_state = FPU_FETCH3) else '0';
    -- fpu_start asserts ONLY in FPU_WAIT, so every fp_rs*_reg is stable before the first edge at which the unit can sample start.
    fpu_start   <= '1' when (current_state = FPU_WAIT) else '0';

    /* fflags sticky-OR strobe: at FPU_DONE for the multi-cycle op's registered flags, or during the EXECUTE retire of a single-cycle FP op for fpu_simple's combinational flags.
       Independent of rd, so rd=x0 still sets flags, and guarded so a misaligned FP op that traps commits none. pmp_if_squash excludes the EXECUTE cycle that decodes a denied fetch's park word.
       A concurrent statement does not inherit the EXECUTE sub-arm structure that protects the FSM dispatch arms, so it must exclude the split-fetch cycle itself, or a single-cycle FP op re-fires this strobe over possibly-mutated operands. */
    fp_flags_we <= '1' when (current_state = FPU_DONE) else
                   '1' when (current_state = EXECUTE and is_fp_singlecycle = '1' and trap = '0'
                             and pmp_if_squash = '0'
                             and (ENABLE_COMPRESSED or pc(1) = '0')
                             and not (pc(1) = '1' and quadrant_upper = "11" and split_ready = '0')) else
                   '0';
    -- The datapath already muxes: fpu_simple flags when result_src=110, otherwise the multi-cycle unit's flags, valid at FPU_DONE with result_src=111.
    fp_flags_val <= fp_flags;

    -- State machine sequential logic.
    state_reg: process(clk_cpu, resetn)
    begin
        if resetn = '0' then
            current_state <= EXECUTE;
            repeat_if <= '0';
            if_ahead <= '0';
            pc <= PC_RST_VAL;
            instr_lower_half <= (others => '0');
            pc_next_reg <= PC_RST_VAL;
            pc_next_trad_reg <= PC_RST_VAL;
            irq_restore_ack <= '0';
            data_addr_reg <= (others => '0');
        elsif rising_edge(clk_cpu) then
            -- Update state machine
            current_state <= next_state;
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

            /* Latch lower half of instruction for split fetch. Both arming paths capture the SAME half-word, instr(31 downto 16), and differ only in which cycle they do it.
               The bubble captures it in a cycle that retires nothing; the fetch-ahead captures it in the retiring cycle before, where instr(31 downto 16) is already the half-word at the next PC.
               The two are mutually exclusive: the bubble cycle is not a dispatch, and the fetch-ahead requires one. */
            if ltch_lh_inst = '1' or if_ahead_req = '1' then
                instr_lower_half <= instr(31 downto 16);
            end if;

            /* The fetch-ahead flag. It is HELD across the single MEMORY_WAIT cycle of a load or store, where instr carries read data rather than an instruction word and instr_lower_half is untouched, so the half-word survives the data access.
               Every other transition re-drives it from if_ahead_req, which is '0' outside a sequential EXECUTE retire, so a branch, a trap, an interrupt or any sequencer state clears it by construction rather than by a blacklist. */
            if current_state = MEMORY_WAIT and next_state = EXECUTE then
                if_ahead <= if_ahead;
            else
                if_ahead <= if_ahead_req;
            end if;
        end if;
    end process;

    -- Zihintpause window counter, clk_cpu domain: loaded when the FSM enters PAUSE_WAIT, then counting down one per edge.
    -- Loading WINDOW-1 spends exactly PAUSE_WINDOW_CYCLES cycles in PAUSE_WAIT, and the load arm is reachable only when PAUSE_WINDOW_CYCLES is greater than 0, so it is never negative at runtime.
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

    -- Separate register stage: assigning instr_curr into instr_curr_prev inside the main state process causes timing problems, so it advances here.
    state_reg_fe: process(clk_cpu, resetn)
    begin
        if resetn = '0' then
            instr_curr_prev <= nop;
        elsif rising_edge(clk_cpu) then
            instr_curr_prev <= instr_curr;
        end if;
    end process;

    -- PC calculation.
    pc_plus_2 <= std_logic_vector(unsigned(pc) + 2);
    pc_plus_4 <= std_logic_vector(unsigned(pc) + 4);

    -- The JAL/JALR return address is pc plus the SIZE of the jump instruction, so a compressed c.jal/c.jalr links pc+2 and everything else pc+4.
    -- The conditions mirror the compressed-instruction terms of pc_next_trad below; keep the two in step.
    pc_link <= pc_plus_2 when (current_state = EXECUTE and pc(1) = '1' and quadrant_upper /= "11" and split_ready = '0') else
               pc_plus_2 when (current_state = EXECUTE and pc(1) = '0' and quadrant_lower /= "11") else
               pc_plus_2 when (current_state = ZCM_JT_WB) else  -- Zcmt cm.jalt links ra = pc+2
               pc_plus_4;

    -- Instruction type detection.
    quadrant_upper <= instr(17 downto 16);
    quadrant_lower <= instr(1 downto 0);
    instr_upper_half <= instr(15 downto 0);
    instr_assembled <= instr_upper_half & instr_lower_half;

    /* THE ONE PREDICATE the two half-holding paths share: the lower half of a straddling 32-bit instruction sits in instr_lower_half and instr carries the word holding its upper half.
       repeat_if reaches it by spending a bubble cycle; if_ahead reaches it with no bubble at all, having spent the previous cycle's otherwise-redundant fetch on the upper word.
       Where the two differ is that if_ahead is armed only after PROVING the quadrant is "11", so quadrant_upper, which under if_ahead describes the half-word AFTER this instruction, is never consulted to classify it. */
    split_ready <= repeat_if or if_ahead;

    /* FETCH-AHEAD ARM. Every term is necessary:
         next_state EXECUTE or MEMORY_WAIT keeps this to the two sequential retire paths, so every sequencer, trap, interrupt and debug trajectory clears the flag instead, none of them being reachable at those two next states;
         dec_dispatch is the file's own "this cycle decodes a real dispatching instruction" predicate, which excludes the split-fetch bubble, a trap-entry cycle and a PMP-parked fetch's decode;
         the PC must advance, and it advances at THIS edge for an ALU-class instruction but at the MEMORY_WAIT edge for a load or store, which is why pc_en alone would silently drop every memory op;
         pc_src = '0' makes that advance SEQUENTIAL, excluding a taken branch or jump, whose target word the core does not hold;
         instr(17 downto 16) = "11" is the proof the instruction at the next PC is 32-bit and straddles, which is what makes the ahead fetch non-speculative;
         the two shape terms are the only two sequential advances that land on a half-word-aligned PC inside the word already on instr, so the ordinary fetch address would name a word the core already holds.
       In both shapes instr(31 downto 16) is the half-word AT the next PC, which is why the same latch serves both. */
    if_ahead_req <= '1' when (ENABLE_IF_AHEAD and ENABLE_COMPRESSED
                              and current_state = EXECUTE
                              and dec_dispatch = '1'
                              and not (ENABLE_PMP and pmp_d_deny = '1')
                              and (next_state = EXECUTE or next_state = MEMORY_WAIT)
                              and (pc_en = '1' or next_state = MEMORY_WAIT)
                              and pc_src = '0'
                              and instr(17 downto 16) = "11"
                              and ((pc(1) = '0' and quadrant_lower /= "11")   -- compressed at a word-aligned PC: the next PC is pc+2, inside this word
                                   or (pc(1) = '1' and split_ready = '1')))   -- straddling 32-bit completing: the next PC is pc+4, inside the word on instr
                    else '0';

    /* THE FETCH ADDRESS. It is pc_next in every cycle but the two the fetch-ahead claims, where it is the word boundary just past pc_next.
       That address is derived from pc and NOT from pc_next, and the difference is a timing one: pc_next is downstream of pc_src, which is downstream of the register read, the ALU and the branch comparator, so an adder placed on pc_next would sit at the far end of the core's longest combinational chain, while pc is a register output and the same adder there has a full cycle of slack.
       What is left on the late path is one 2-to-1 mux whose data inputs are both already settled.
       The substitution is exact because the fetch-ahead is armed only where the advance is sequential: from a word-aligned pc the next PC is pc+2, whose following word boundary is pc+4, and from a half-word-aligned pc it is pc+4, whose following word boundary is pc+6.
       MEMORY_WAIT selects from the same expression because a load or store does not advance the PC in its own dispatch cycle, so pc still holds the memory instruction's own address in the MEMORY_WAIT cycle that issues the fetch. */
    pc_plus_6     <= std_logic_vector(unsigned(pc) + 6);
    if_ahead_addr <= pc_plus_4 when pc(1) = '0' else pc_plus_6;

    fetch_addr <= if_ahead_addr when (if_ahead_req = '1' or
                                      (current_state = MEMORY_WAIT and if_ahead = '1')) else
                  pc_next;

    -- Select the instruction to decompress, by fetch state.
    instr_to_decomp <= instr_assembled when current_state = EXECUTE and pc(1) = '1' and split_ready = '1' else
                       x"0000" & instr(31 downto 16) when current_state = EXECUTE and pc(1) = '1' and is_compressed = '1' else
                       instr;

    -- Current-instruction mux, by state and alignment. Every multi-cycle state holds instr_curr_prev so the dispatching encoding stays stable across it.
    instr_curr <= nop when (resetn = '0' or current_state = INITIALIZE) else
                  instr when (current_state = IRQ_SV) else  -- IVT entries are never compressed
                  instr_decomp when (current_state = EXECUTE and pc(1) = '1' and split_ready = '1') else
                  instr_curr_prev when (current_state = EXECUTE and pc(1) = '1' and quadrant_upper = "11" and repeat_if = '0') else
                  instr_decomp when (current_state = EXECUTE and pc(1) = '1' and quadrant_upper /= "11") else
                  instr when (current_state = EXECUTE and pc(1) = '0' and quadrant_lower = "11") else
                  instr_decomp when (current_state = EXECUTE and pc(1) = '0' and quadrant_lower /= "11") else
                  instr_curr_prev when (current_state = MEMORY_WAIT) else
                  instr_curr_prev when (current_state = DIV_WAIT) else
                  instr_curr_prev when (current_state = DIV_DONE) else
                  instr_curr_prev when (current_state = FPU_FETCH3) else  -- hold the FP instruction
                  instr_curr_prev when (current_state = FPU_WAIT) else
                  instr_curr_prev when (current_state = FPU_DONE) else
                  -- IRQ_SV decodes the RAW BUS WORD, via the head arm of this mux; that word is inert because dec_dispatch gates every strobe that could act on it and the FSM arm forces reg_write_dp '0' and wen all-ones.
                  -- The standard trap-entry pair HOLDS the faulting instruction instead: mtval for an illegal instruction comes from instr_curr_prev, which is stable only if instr_curr feeds itself here, and no live memory word may leak into these cycles.
                  instr_curr_prev when (current_state = MTRAP_SV) else
                  instr_curr_prev when (current_state = MTRAP_JUMP) else
                  instr_curr_prev when (current_state = MTRAP_RET) else
                  instr_curr_prev when (current_state = IRQ_REST) else
                  instr_curr_prev when (current_state = SLEEPING) else
                  instr_curr_prev when (current_state = AMO_READ) else  -- keep the instruction during an AMO
                  instr_curr_prev when (current_state = AMO_WRITEBACK) else
                  instr_curr_prev when (current_state = AMO_COMPUTE) else
                  instr_curr_prev when (current_state = AMO_COMPLETE) else
                  instr_curr_prev when (current_state = AMO_WRITE) else
                  instr_curr_prev when (current_state = LR_READ) else
                  instr_curr_prev when (current_state = SC_CHECK) else
                  instr_curr_prev when (current_state = CBOZ_WRITE) else  -- hold the cbo.zero
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

    -- Next PC for normal operation, with no interrupt; the PC holds during atomic operations.
    pc_next_trad <= PC_RST_VAL when (resetn = '0' or current_state = INITIALIZE) else
                    pc_target when ((current_state = EXECUTE or current_state = IRQ_SV) and pc(1) = '1' and split_ready = '1' and pc_src = '1') else
                    pc_plus_4 when (current_state = EXECUTE and pc(1) = '1' and split_ready = '1' and pc_src = '0') else
                    pc_plus_2 when (current_state = EXECUTE and pc(1) = '1' and quadrant_upper = "11" and repeat_if = '0') else
                    pc_target when (current_state = EXECUTE and pc(1) = '1' and quadrant_upper /= "11" and pc_src = '1') else
                    pc_plus_2 when (current_state = EXECUTE and pc(1) = '1' and quadrant_upper /= "11" and pc_src = '0') else
                    pc_target when ((current_state = EXECUTE or current_state = IRQ_SV) and pc(1) = '0' and quadrant_lower = "11" and pc_src = '1') else
                    pc_plus_4 when (current_state = EXECUTE and pc(1) = '0' and quadrant_lower = "11" and pc_src = '0') else
                    pc_target when (current_state = EXECUTE and pc(1) = '0' and quadrant_lower /= "11" and pc_src = '1') else
                    pc_plus_2 when (current_state = EXECUTE and pc(1) = '0' and quadrant_lower /= "11" and pc_src = '0') else
                    pc_next_trad_reg;  -- hold for other states, including atomic operations

    -- Final PC selection. Every vectoring state (IRQ_JUMP, MTRAP_JUMP, MTRAP_RET, the debug entries and DBG_RET) carries pc_en='1', so data_addr falls through to pc_next and the SAME cycle issues the fetch from the new PC.
    -- MTRAP_SV holds pc_next_reg like IRQ_SV, which is what makes pc_next_reg the interrupt RESUME PC, identical to the word the legacy IRQ_SV pushes at sp-4, across the whole entry pair.
    pc_next <= ivt_entry   when (current_state = IRQ_JUMP) else
               DEBUG_ENTRY_ADDR when (current_state = DBG_SV or
                                      current_state = DBG_JUMP) else
               dbg_dpc_value    when (current_state = DBG_RET) else
               trap_mtvec_value when (current_state = MTRAP_JUMP) else
               trap_mepc_value  when (current_state = MTRAP_RET) else
               pc_next_reg when (current_state = MTRAP_SV) else
               pc_next_ret when (current_state = IRQ_REST) else
               pc_next_reg when (current_state = SLEEPING) else
               pc_next_reg when (current_state = IRQ_SV) else
               pc_next_reg when (current_state = AMO_READ or current_state = AMO_WRITEBACK or 
                                current_state = AMO_COMPUTE or current_state = AMO_WRITE) else
               pc_next_reg when (current_state = LR_READ or current_state = SC_CHECK) else
               zcm_jt_target when (current_state = ZCM_JT_WB) else  -- Zcmt table-jump target
               rs1_value when (current_state = ZCM_RET) else        -- Zcmp popret[z] returns through ra
               pc_next_trad;

    /* Memory interface address selection. In SC_CHECK and during an AMO or LR dispatch the ALU is NOT computing the address (it is in pass-B for the SC rd value, or applying the AMO's own function to rs1 and rs2), so those accesses address from rs1_value directly.
       Addressing them from ALU_Result puts a garbage address on the bus; private memory masks it because the next state re-presents the right one, but a shared access completes inside the frozen dispatch cycle and returns the wrong data.
       The cbo.zero store address is the registered block base plus cboz_idx*4, computed here so it can be placed BEFORE the generic mem_access_instr term, which would otherwise steer data_addr to a stale ALU_Result during CBOZ_WRITE. */
    cboz_zero_addr <= std_logic_vector(unsigned(cboz_base) + to_unsigned(cboz_idx * 4, 32));

    -- The three SEQUENCER address terms are selected by STATE, not by mem_access_instr, so a PMP denial must gate them here too: suppressing only the FSM's request would still leave the denied word on data_addr, and sh_req is a pure decode of data_addr.
    -- The EXECUTE-dispatch terms need no such gate, being qualified by mem_access_instr, which a denial forces '0'; the PC_RST_VAL arm is the FETCH suppression point.
    data_addr <= cboz_zero_addr when (current_state = CBOZ_WRITE and pmp_d_deny = '0') else
                 zcm_mem_addr when ((current_state = ZCM_PUSH_ST or current_state = ZCM_POP_LD)
                                    and pmp_d_deny = '0') else
                 zcm_jt_addr  when (current_state = ZCM_JT_LD and pmp_d_deny = '0') else
                 -- SC-SUCCESS PREDICATE, FOUR IDENTICAL COPIES: `reservation_valid = '1' and reservation_addr = rs1_value` appears in this data_addr arm, in amo_phase ("101"), in lr_sc_bus ("10") and in the SC_CHECK FSM arm. Change all four or none, since a divergence is SILENT.
                 -- Steering the address is not optional: sh_sel is a pure decode of data_addr, so suppressing only the request would still issue the transaction. On the failing path this arm drops out and data_addr falls through to pc_next, a harmless early fetch.
                 rs1_value  when (current_state = SC_CHECK
                                  and reservation_valid = '1'
                                  and reservation_addr = rs1_value) else
                 /* LR joins SC and AMO on the phase-independent rs1 address. `lr.w rd, rs2, (rs1)` with a NON-ZERO rs2 field is a legal decode and ALU_Result is then rs1 + reg[rs2], so addressing from the ALU would arm the reservation and issue the read at DIFFERENT addresses.
                    BOTH terms are required: the LR's read transaction rides the EXECUTE cycle, so only that term moves the global reservation, while LR_READ must present the SAME word address or the word-address-qualified ack drops and a second, wrong-address read is arbitrated.
                    Canonical lr.w has rs2 = x0, so this changes nothing for assembler-emitted code; the ALU_Result arm below keeps its now-shadowed LR_READ term for symmetry with AMO_READ/AMO_WRITE. */
                 rs1_value  when (current_state = LR_READ or
                                  (current_state = EXECUTE
                                   and (amo_op = '1' or lr_op = '1')
                                   and mem_access_instr = '1')) else
                 ALU_Result when (mem_access_instr = '1' or
                                  current_state = AMO_READ or current_state = AMO_WRITE or
                                  current_state = LR_READ) else
                 std_logic_vector(unsigned(stack_pointer) - 4) when (current_state = IRQ_SV) else
                 stack_pointer when next_state = IRQ_REST else
                 PC_RST_VAL when pmp_if_park = '1' else
                 fetch_addr;

    -- Memory write data selection: an AMO writes the computed result, an SC writes rs2.
    -- Zabha replicates the computed sub-word result across all byte lanes; the byte-lane wen commits only the addressed lane.
    amo_write_data_steered <= amo_write_data(7 downto 0) & amo_write_data(7 downto 0) &
                              amo_write_data(7 downto 0) & amo_write_data(7 downto 0)
                                  when instr_curr(14 downto 12) = "000" else
                              amo_write_data(15 downto 0) & amo_write_data(15 downto 0)
                                  when instr_curr(14 downto 12) = "001" else
                              amo_write_data;  -- word AMO: the full 32-bit result

    -- Zacas: this AMO is an amocas, detected from the held instruction (funct5 = CAS_FN5) plus the generic, and statically '0' when ENABLE_ZACAS is false since the encoding then traps in decode.
    -- Drives the datapath rs2-port steering and the conditional-write gating below.
    cas_op <= '1' when (ENABLE_ZACAS and instr_curr(6 downto 0) = AMO_OPCODE
                       and instr_curr(31 downto 27) = CAS_FN5) else '0';

    -- Zabha active-low byte-lane enables for the sub-word AMO write, keyed off the REGISTERED AMO address low bits latched at AMO_READ; keying off the live rs1 port corrupts the lane select for an AMO whose rd equals rs1.
    -- A CAS whose compare FAILED suppresses the write entirely ("1111", no lane). That is write-enable gating only, so the FSM still issues the identical AMO_WRITE transaction on the same locked trajectory and the reservation unit, keyed on committed lane strobes, kills no reservation on a fail.
    amo_wen <= "1111" when (cas_op = '1' and cas_match_reg = '0') else
               "1110" when (instr_curr(14 downto 12) = "000" and amo_addr_low = "00") else
               "1101" when (instr_curr(14 downto 12) = "000" and amo_addr_low = "01") else
               "1011" when (instr_curr(14 downto 12) = "000" and amo_addr_low = "10") else
               "0111" when (instr_curr(14 downto 12) = "000" and amo_addr_low = "11") else
               "1100" when (instr_curr(14 downto 12) = "001" and amo_addr_low(1) = '0') else
               "0011" when (instr_curr(14 downto 12) = "001" and amo_addr_low(1) = '1') else
               "0000";  -- word AMO (funct3=010): all four lanes

    write_data <= pc_next when (current_state = IRQ_SV) else
                  amo_write_data_steered when (current_state = AMO_WRITE) else  -- sub-word-steered; a word AMO gets the full result
                  (others => '0') when (current_state = CBOZ_WRITE) else  -- the block-zero payload
                  rs1_value when (current_state = ZCM_PUSH_ST) else  -- cm.push: reg[reg_at(idx)] via the steered rs1 port
                  write_data_dp;  -- rs2 for normal stores and SC

    /* Atomic operation phase, passed to the datapath so the ALU performs the computation.
       SC success is the LOCAL reservation check (valid AND address match, the same condition that drives the store lanes in SC_CHECK) AND the external verdict sc_fail_ext, which ties '0' for private or single-master use.
       SC-SUCCESS PREDICATE, FOUR IDENTICAL COPIES: this amo_phase term, the data_addr mux's SC_CHECK term, lr_sc_bus and the SC_CHECK FSM arm. Change all four or none, since a divergence is SILENT. */
    amo_phase <=    "001" when current_state = AMO_READ or current_state = LR_READ else  -- reading the address
                    "110" when current_state = AMO_WRITEBACK else  -- Zacas rd-capture window: steer the rs2 port to rd and latch the compare; the ALU output is unused here
                    "010" when current_state = AMO_COMPUTE else  -- computing with the memory data
                    "011" when current_state = AMO_WRITE else     -- writing the result back
                    "101" when current_state = SC_CHECK and reservation_valid = '1'
                               and reservation_addr = rs1_value
                               and sc_fail_ext = '0' else          -- SC succeeded
                    "100" when current_state = SC_CHECK else       -- SC failed
                    "000";  -- normal operation

    /* Tag the current memory access for the global reservation unit. The LR's bus transaction runs during the EXECUTE decode cycle and LR_READ only consumes the returned data, so the "01" tag must ride EXECUTE; the SC's conditional write runs in SC_CHECK.
       "10" requires the LOCAL check to pass, since a locally failed SC issues no write and must not be adjudicated as an SC. The pmp_d_deny qualifier keeps a denied LR, which issues no read at all, from tagging the fetch that data_addr falls through to.
       SC-SUCCESS PREDICATE, FOUR IDENTICAL COPIES: this lr_sc_bus term, the data_addr mux's SC_CHECK term, amo_phase and the SC_CHECK FSM arm. Change all four or none, since a divergence is SILENT. */
    lr_sc_bus <= "01" when current_state = EXECUTE and lr_op = '1' and pmp_d_deny = '0' else
                 "10" when current_state = SC_CHECK and reservation_valid = '1'
                           and reservation_addr = rs1_value else
                 "00";

    -- Assert for the WHOLE AMO flow: the read completes while the core is frozen in EXECUTE and the arbiter samples the lock at that completion, so the dispatch-cycle term is required, and the lock must persist through AMO_WRITE for the write to get the pinned grant.
    -- It drops at AMO_COMPLETE, IRQ_SV or TRAP, the release valve if the write can never issue. mem_access_instr qualifies the EXECUTE term to the real dispatch, excluding a half-fetch cycle where amo_op may be decoded from an incomplete instruction.
    amo_lock <= '1' when (current_state = EXECUTE and amo_op = '1'
                          and mem_access_instr = '1')
                      or current_state = AMO_READ
                      or current_state = AMO_WRITEBACK
                      or current_state = AMO_COMPUTE
                      or current_state = AMO_WRITE
                else '0';

    -- Standard M-mode trap delivery glue (ENABLE_TRAPCSR). The coexistence select is statically '0' when the generic is off, so every MTRAP_* transition constant-folds and the OFF netlist is unchanged.
    -- It is also '0' at reset when the generic is ON, because mtrapctl.LEGACY resets '1', which is what lets the legacy path run untouched on ON hardware.
    std_mode <= '1' when (ENABLE_TRAPCSR and trap_legacy_mode = '0') else '0';

    -- Standard-mode interrupt take: csr_unit exports STATE only and the pending decision is made here, as mstatus.MIE and ((meip and MEIE) or (msip and MSIE) or (mtip and MTIE)), with mie_bits packed {MEIE(2), MTIE(1), MSIE(0)}.
    -- dbg_irq_block suppresses standard delivery in debug mode at this single source rather than on each recognition arm, because an arm-by-arm suppression can be half-applied; the interrupt stays LEVEL-pending and is delivered after the dret.
    std_irq_take <= '1' when (std_mode = '1' and dbg_irq_block = '0' and
                              trap_mstatus_mie = '1' and
                              ((trap_irq_meip = '1' and trap_mie_bits(2) = '1') or
                               (trap_irq_msip = '1' and trap_mie_bits(0) = '1') or
                               (trap_irq_mtip = '1' and trap_mie_bits(1) = '1')))
                    else '0';

    /* Dispatch-cycle trap classification, read ONLY at the clk_cpu edge that enters MTRAP_SV. Every FSM arm making that transition lives inside a real-dispatch branch of the EXECUTE decode tree, so a half-fetch cycle, where instr_curr still holds the previous instruction, can never sample it.
       PRIORITY MIRRORS THE FSM ARM ORDER EXACTLY, because a cause mux that disagrees with the arm order silently mislabels traps: instruction access fault first (the word being decoded is the park word, so trap, ecall_op and ebreak_op are meaningless on it), then misaligned PC, illegal, ECALL and EBREAK, then load/store access fault, and anything else is an interrupt.
       The load/store fault arm also fires from the sequencer states, which is why it carries no `current_state = EXECUTE` qualifier. */
    mtrap_disp_int <=
        '0' when (ENABLE_PMP and current_state = EXECUTE and pmp_f_deny_r = '1') else         -- 1 instr access fault
        '0' when (current_state = EXECUTE and (not ENABLE_COMPRESSED) and pc(1) = '1') else   -- instruction-address-misaligned
        '0' when (current_state = EXECUTE and
                  (trap = '1' or ecall_op = '1' or ebreak_op = '1')) else                     -- illegal / ECALL / EBREAK
        '0' when (pmp_d_deny = '1') else                                                      -- 5/7 load-store access fault
        '1' when (current_state /= EXECUTE) else                                 -- MEMORY_WAIT, DIV_DONE, AMO_*, SLEEPING and the rest: interrupt
        '1';                                                                     -- EXECUTE with none of the above: interrupt

    mtrap_disp_code <=
        x"1" when (ENABLE_PMP and current_state = EXECUTE and pmp_f_deny_r = '1') else        -- 1  instruction access fault
        x"0" when (current_state = EXECUTE and (not ENABLE_COMPRESSED) and pc(1) = '1') else  -- 0  instr addr misaligned
        x"2" when (current_state = EXECUTE and trap = '1') else                               -- 2  illegal instruction
        -- The ECALL cause is the CURRENT privilege; trap_priv_mode is stuck '1' (M) on any ENABLE_UMODE=false build, so this collapses to the constant 11.
        x"8" when (current_state = EXECUTE and ecall_op = '1' and trap_priv_mode = '0') else  -- 8  ecall from U
        x"B" when (current_state = EXECUTE and ecall_op = '1') else                           -- 11 ecall from M
        x"3" when (current_state = EXECUTE and ebreak_op = '1') else                          -- 3  breakpoint
        -- Data-side access faults; the access class, not the permission need, picks the code.
        -- Store, SC, AMO, cbo.zero and cm.push give 7; load, LR, cm.pop and the Zcmt table fetch give 5.
        x"7" when (pmp_d_deny = '1' and pmp_d_st_class = '1') else                            -- 7  store/AMO access fault
        x"5" when (pmp_d_deny = '1') else                                                     -- 5  load access fault
        -- Interrupt codes, in the spec priority order MEI, then MSI, then MTI.
        x"B" when (trap_irq_meip = '1' and trap_mie_bits(2) = '1') else                       -- 0x8000000B
        x"3" when (trap_irq_msip = '1' and trap_mie_bits(0) = '1') else                       -- 0x80000003
        x"7";                                                                                 -- 0x80000007

    -- Latch the classification at the dispatch edge, 5 flops total.
    -- The 32-bit mepc and mtval values are NOT registered; they are re-derived in MTRAP_SV from state that is provably held there (pc, pc_next_reg, instr_curr_prev).
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

    -- csr_unit writeback values, valid throughout MTRAP_SV. mepc is pc_next_reg for an interrupt (the resume PC, the same word the legacy IRQ_SV pushes at sp-4), otherwise pc, which still holds the faulting or ECALL's own address because pc_en is '0' from the dispatch edge on.
    -- mtval is the faulting 32-bit encoding for an illegal instruction, the misaligned PC for cause 0, otherwise 0.
    trap_pc_val    <= pc_next_reg when mtrap_cause_int = '1' else pc;
    trap_cause_val <= mtrap_cause_int & MTRAP_RSVD27 & mtrap_cause_code;
    -- For the three ACCESS-FAULT causes mtval is the FAULTING ADDRESS, taken from the dispatch-edge latch because neither pmp_d_addr nor pmp_f_addr_r is stable during MTRAP_SV; the latch is all-zero on an ENABLE_PMP=false build.
    trap_value_val <= instr_curr_prev when (mtrap_cause_int = '0' and mtrap_cause_code = x"2") else
                      pc              when (mtrap_cause_int = '0' and mtrap_cause_code = x"0") else
                      mtrap_val_r     when (ENABLE_PMP and mtrap_cause_int = '0' and
                                            (mtrap_cause_code = x"1" or mtrap_cause_code = x"5" or
                                             mtrap_cause_code = x"7")) else
                      (others => '0');

    -- One-shot generation on the csr_unit clock domain, which is the free-running clk while the FSM is on the gated clk_cpu.
    -- The whole block is generate-gated, so an OFF build carries no extra flops at all and both strobes are hard-tied '0'.
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

    -- irq_handler neutralization: masking every enable makes pending_irqs_comb all-zero, so irq_found never rises and the handler FSM is pinned in IDLE, which is what lets the std_irq_take arms sit BESIDE the irq_save arms without a priority fight.
    -- The same mechanism suppresses legacy delivery in debug mode. Nothing is lost either way, the IRQ sources being LEVEL: unmasking re-presents whatever is still pending. This is the identity function when both knobs are off.
    irq_en_eff <= irq_en when (std_mode = '0' and dbg_irq_block = '0')
                  else (others => '0');

    -- Standard WFI wake rule: a WFI wakes when (mip and mie) /= 0 REGARDLESS of mstatus.MIE.
    -- This is std_irq_take minus the MIE qualifier, and the two are deliberately separate: std_irq_take decides whether a trap is DELIVERED, std_wfi_pend only whether the hart RESUMES.
    std_wfi_pend <= '1' when ((trap_irq_meip = '1' and trap_mie_bits(2) = '1') or
                              (trap_irq_msip = '1' and trap_mie_bits(0) = '1') or
                              (trap_irq_mtip = '1' and trap_mie_bits(1) = '1'))
                    else '0';

    -- Qualified by wfi_slept, so an EXTINGUISH-entered sleep keeps its legacy behaviour of waking only on a taken interrupt even with mie armed.
    -- Gated on ENABLE_TRAPCSR and NOT on ENABLE_UMODE, since WFI is legal on a trapCsr-only build and only the TW and U-mode legality gating needs U-mode.
    std_wfi_wake <= '1' when (ENABLE_TRAPCSR and wfi_slept = '1' and std_wfi_pend = '1')
                    else '0';

    -- Debug-mode glue (ENABLE_DEBUG). ENABLE_DEBUG requires ENABLE_TRAPCSR: ebreak_op and the whole SYSTEM PRIV legality arm are ENABLE_TRAPCSR-gated in maindec, so without it `ebreak` does not decode and dcsr.ebreakm has nothing to interpose on.
    -- The generator's validator enforces the implication for every config; this assert catches anyone instantiating the core directly.
    assert not (ENABLE_DEBUG and not ENABLE_TRAPCSR)
        report "vesta: ENABLE_DEBUG requires ENABLE_TRAPCSR (ebreak and the "
             & "SYSTEM PRIV arm do not decode without it)"
        severity failure;

    /* THE HALT TAKE is qualified by NEITHER mstatus.MIE NOR mtrapctl.LEGACY, only by `not debug_mode`: a halt request is unmaskable, but a hart already in debug mode must not re-enter and overwrite its own dpc. Three sources share one signal; the CAUSE mux below tells them apart.
       WAIT-FOR-RELEASE gives ONE ENTRY PER ASSERTION: dbg_haltreq is a LEVEL that a debugger cannot drop until it has seen dbg_halted, so without the mask the hart re-enters debug the instant each `dret` retires, walks forward one instruction per round trip, rewrites its own dpc and makes single-step impossible.
       One flop, on the FREE-RUNNING clk so a hart whose clk_cpu is gated cannot miss the release, and RELEASE WINS over set so dropping and re-raising the line gets a second halt immediately. The other two sources need no mask: each is cleared by the entry it causes. */
    dbg_haltreq_eff <= dbg_haltreq and not dbg_req_mask;

    dbg_halt_take <= '1' when (ENABLE_DEBUG and debug_mode = '0' and
                               (dbg_haltreq_eff = '1' or dbg_rsthalt_r = '1' or
                                dbg_step_armed = '1'))
                     else '0';
    dbg_step_take <= '1' when (ENABLE_DEBUG and debug_mode = '0' and
                               dbg_step_armed = '1')
                     else '0';
    dbg_halt_pend <= dbg_halt_take;

    /* THE EXCEPTION TAKE: a SYNCHRONOUS exception taken in debug mode must NOT leave debug mode. Without it a fault either wedges in the terminal TRAP_STATE with dbg_halted asserted, or vectors to mtvec (reset value 0, the shared boot ROM) and runs the park sequence with debug_mode still '1', which is unrecoverable because no fresh halt request can reach a hart that is already in debug mode.
       The redirect target is DBG_JUMP, which already means "re-enter, dpc and dcsr survive", so this adds no state, no flop and no commit interface. Intercepting in the sink states instead cannot work: TRAP_STATE unconditionally raises trap_flag, and MTRAP_SV's CSR writeback rides a one-shot of that state, so mepc, mcause and mtval are corrupted before any redirect could run.
       The mret_op arms are deliberately NOT redirected: mret is not an exception and in debug mode it executes architecturally with debug_mode unchanged. */
    dbg_exc_take <= '1' when (ENABLE_DEBUG and debug_mode = '1') else '0';

    -- THE INTERRUPT BLOCK: interrupts are not taken in debug mode. dbg_halt_take sits above irq_save and std_irq_take in every recognition chain but does not BLOCK them, so without this a halted hart spinning at DEBUG_ENTRY_ADDR vectors into an ISR with dbg_halted still asserted.
    -- The suppression is applied at the two SOURCES, std_irq_take and irq_en_eff, rather than at the recognition chains, so it cannot be half-applied.
    dbg_irq_block <= '1' when (ENABLE_DEBUG and debug_mode = '1') else '0';

    -- THE EBREAK TAKE. dcsr.ebreakm resets 0 and is writable only from debug mode, so no M-mode software can arm it and `ebreak` normally takes an ordinary breakpoint exception; ebreaku rides ENABLE_UMODE, dcsr_ebreaku being stuck '0' without it.
    -- The debug_mode term is the re-entry clause: an ebreak executed BY debug code always re-enters, regardless of ebreakm.
    dbg_ebreak_take <= '1' when (ENABLE_DEBUG and
                                 (debug_mode = '1' or
                                  dcsr_ebreakm = '1' or
                                  (ENABLE_UMODE and trap_priv_mode = '0' and
                                   dcsr_ebreaku = '1')))
                       else '0';

    -- Dispatch-cycle cause classification. PRIORITY MIRRORS THE FSM ARM ORDER EXACTLY: the ebreak arm sits above the halt arm in the EXECUTE decode tree, so ebreak is first here.
    -- A cause mux that disagrees with the arm order silently mislabels entries.
    dbg_disp_cause <=
        "001" when (current_state = EXECUTE and ebreak_op = '1' and
                    dbg_ebreak_take = '1') else                 -- 1 ebreak
        "101" when (dbg_rsthalt_r = '1') else                   -- 5 resethaltreq
        "011" when (dbg_haltreq_eff = '1') else                 -- 3 haltreq
        "100" when (dbg_step_take = '1') else                   -- 4 step
        "011";                                                  -- default: haltreq

    -- The cause LATCH and every other debug flop live inside the generate pair below, not here, so the OFF netlist is identical BY CONSTRUCTION rather than by relying on unloaded-logic removal.

    -- dpc, valid throughout DBG_SV. A synchronous ebreak reports its OWN address (pc still holds it, pc_en being '0' from the dispatch edge on), so debug code resuming past an ebreak must add 4 itself.
    -- Every other cause is taken BETWEEN instructions, so the resume PC is pc_next_reg, the same word MTRAP_SV uses as mepc for an interrupt.
    dbg_pc_val <= pc when dbg_cause_r = "001" else pc_next_reg;

    -- The one-shots, plus the halt-on-reset and single-step state, all inside the generate pair so an OFF netlist carries no extra flops and every strobe is hard-tied '0'.
    dbg_sv_lvl  <= '1' when current_state = DBG_SV  else '0';
    dbg_ret_lvl <= '1' when current_state = DBG_RET else '0';

    gen_debug: if ENABLE_DEBUG generate
        -- The dispatch-cycle cause latch, 3 flops on clk_cpu. The 32-bit dpc value is NOT registered: it is re-derived from pc and pc_next_reg, both held through DBG_SV.
        dbg_cause_proc: process(clk_cpu, resetn)
        begin
            if resetn = '0' then
                dbg_cause_r <= (others => '0');
            elsif rising_edge(clk_cpu) then
                if next_state = DBG_SV and current_state /= DBG_SV then
                    dbg_cause_r <= dbg_disp_cause;
                end if;
            end if;
        end process;

        dbg_we_proc: process(clk, resetn)
        begin
            if resetn = '0' then
                dbg_sv_d  <= '0';
                dbg_ret_d <= '0';
            elsif rising_edge(clk) then
                dbg_sv_d  <= dbg_sv_lvl;
                dbg_ret_d <= dbg_ret_lvl;
            end if;
        end process;
        dbg_entry_we_sig <= dbg_sv_lvl  and not dbg_sv_d;
        dbg_ret_we_sig   <= dbg_ret_lvl and not dbg_ret_d;

        /* Halt on reset is SAMPLED AT RESET RELEASE: dbg_rst_armed is a one-shot, so the first free-clk edge after this core's reset release captures dbg_resethaltreq and disarms, and a request arriving later cannot halt a running hart.
           Once captured it is HELD until the entry it causes, and is still stable across that entry, which is what lets the cause mux report resethaltreq rather than haltreq. On the free-running clk, so a hart whose clk_cpu is gated cannot miss the sample.
           Below is the wait-for-release flop; the clear, meaning the release was observed, has PRIORITY. */
        dbg_reqmask_proc: process(clk, resetn)
        begin
            if resetn = '0' then
                dbg_req_mask <= '0';
            elsif rising_edge(clk) then
                if dbg_haltreq = '0' then
                    dbg_req_mask <= '0';
                elsif dbg_entry_we_sig = '1' then
                    dbg_req_mask <= '1';
                end if;
            end if;
        end process;

        dbg_rsthalt_proc: process(clk, resetn)
        begin
            if resetn = '0' then
                dbg_rsthalt_r <= '0';
                dbg_rst_armed <= '1';
            elsif rising_edge(clk) then
                if dbg_rst_armed = '1' then
                    dbg_rsthalt_r <= dbg_resethaltreq;   -- the one sample
                    dbg_rst_armed <= '0';
                elsif dbg_entry_we_sig = '1' then
                    dbg_rsthalt_r <= '0';                -- consumed by its entry
                end if;
            end if;
        end process;

        -- Single-step arming: set on the DRET cycle only if dcsr.step is set, read at that edge, so debug code that clears step before its dret resumes free-running.
        -- Cleared by the entry it causes, and the two conditions cannot coincide. On clk_cpu, because the FSM samples it. Step is not active in debug mode: dbg_step_take carries `not debug_mode`.
        dbg_step_proc: process(clk_cpu, resetn)
        begin
            if resetn = '0' then
                dbg_step_armed <= '0';
            elsif rising_edge(clk_cpu) then
                if current_state = DBG_RET then
                    dbg_step_armed <= dcsr_step;
                elsif next_state = DBG_SV and current_state /= DBG_SV then
                    dbg_step_armed <= '0';
                end if;
            end if;
        end process;
    end generate;

    gen_debug_off: if not ENABLE_DEBUG generate
        dbg_sv_d         <= '0';
        dbg_ret_d        <= '0';
        dbg_entry_we_sig <= '0';
        dbg_ret_we_sig   <= '0';
        dbg_rsthalt_r    <= '0';
        dbg_rst_armed    <= '0';
        dbg_step_armed   <= '0';
        dbg_cause_r      <= (others => '0');
        dbg_req_mask     <= '0';
    end generate;

    -- HALTED IS A STATE, NOT A LEVEL FOLLOWER: it means "this hart is in debug mode", so it rises with the entry edge, stays high after the debugger drops dbg_haltreq, and only a `dret` lowers it.
    -- Driving dbg_halted straight from dbg_haltreq passes an entry test and fails here.
    dbg_halted <= debug_mode;

    -- Trap-entry side-effect suppression. MTRAP_SV and MTRAP_JUMP already suppress every side effect the FSM OWNS (reg_write_dp, wen, mem_access_instr, sp_write_en), but four decode outputs BYPASS the FSM and stay live through those cycles, because read_data still holds the FAULTING encoding until the mtvec fetch lands: csr_valid (csr_unit's write enable), isr_ret (the legacy EOI) and sleep_rq/wake_rq (the free-running sleep_cpu flop).
    -- That breaks the U-mode gate, which is keyed on the LIVE privilege: privilege flips to M inside MTRAP_SV, so a U-mode `csrw` to a trap CSR traps correctly and then COMMITS one cycle later, in M. The rule is that DURING TRAP ENTRY THE FAULTING INSTRUCTION COMMITS NOTHING.
    trap_entry_seq <= '1' when (ENABLE_TRAPCSR and
                                (current_state = MTRAP_SV or current_state = MTRAP_JUMP))
                      else '0';
    -- The same rule, one cycle earlier: a PMP-denied instruction FETCH never issued, so the EXECUTE cycle that would have consumed it decodes the PARK word instead of a real instruction and must commit nothing either.
    -- pmp_if_squash is statically '0' when ENABLE_PMP is false, so dec_squash degenerates to trap_entry_seq and the OFF build is bit-identical.
    dec_squash     <= trap_entry_seq or pmp_if_squash;
    /* DECODE-DISPATCH QUALIFICATION. A state blacklist is only ever as good as the list, and in IRQ_SV, IRQ_JUMP, FENCE_WAIT, PAUSE_WAIT, WRS_WAIT, TRAP_STATE and the split-fetch bubble instr_curr is NOT the instruction being dispatched, so dec_dispatch takes the POSITIVE form instead: the ONE cycle in which a decoded instruction may commit an FSM-bypassing side effect.
         EXECUTE is the only state in which an explicit CSR write commits, every other state either holding a previous encoding that cannot be a CSR or sleep op or decoding a live word that is not executing; dec_squash inherits the trap-entry suppression and the PMP park squash, both reachable inside EXECUTE.
         The split-fetch bubble is excluded because nothing drives csr_valid while instr_curr is HELD at the previous instruction, so a just-retired `csrrw rd,csr,rd` would re-fire with csr_wdata read live from rf[rs1] and revert the CSR; the legitimate dispatch is the split_ready='1' completion cycle, which the term keeps. The last term excludes a halfword-aligned PC on a non-C build, which is a misaligned-address TRAP arm and never a dispatch. */
    dec_dispatch   <= '1' when (current_state = EXECUTE
                                and dec_squash = '0'
                                and not (pc(1) = '1' and quadrant_upper = "11" and split_ready = '0')
                                and (ENABLE_COMPRESSED or pc(1) = '0'))
                      else '0';
    csr_valid_eff  <= csr_valid and dec_dispatch;
    -- isr_ret_eff is deliberately NOT re-qualified to the dispatch cycle. irq_handler runs on the free-running clk and consumes isr_ret as a LEVEL, both inside WAIT_EOI and to leave it, and instr_curr holds the iret encoding across EXECUTE, MEMORY_WAIT and IRQ_REST.
    -- Narrowing it would shrink the window over which the EOI is asserted, on the one path where a mistake hangs the chip; the level is idempotent here, since the EOI clears a flag rather than incrementing a counter.
    isr_ret_eff    <= isr_ret   and not dec_squash;

    /* PMP CHECK POINTS (ENABLE_PMP). The data address under test is deliberately NOT data_addr: data_addr is a function of mem_access_instr, which the denial has to drive, so reading it back here would be a combinational loop.
       Every term below mirrors what the data_addr mux would have chosen in the same cycle: rs1_value for an LR, SC or AMO dispatch (ALU_Result holds rs1 combined with rs2 there), ALU_Result for a plain load or store, and the sequencer's own generated address for this step in CBOZ_WRITE, ZCM_PUSH_ST, ZCM_POP_LD and ZCM_JT_LD.
       Check and access must never disagree about the address; in every other cycle the value is don't-care, pmp_d_active being '0'. */
    pmp_d_addr <= cboz_zero_addr when (current_state = CBOZ_WRITE) else
                  zcm_mem_addr   when (current_state = ZCM_PUSH_ST or current_state = ZCM_POP_LD) else
                  zcm_jt_addr    when (current_state = ZCM_JT_LD) else
                  rs1_value      when (current_state = EXECUTE and (amo_op = '1' or sc_op = '1'
                                                                    or lr_op = '1')) else
                  ALU_Result;

    /* Permission NEEDS: LR, SC and AMO drive BOTH R and W. A plain access is a store exactly when its byte-lane enables are not all inactive, wen_controller being "1111" for every load and for LR.
       `and isr_ret = '0'` keeps an iret out of the data check: its decode also raises mem_access_controller, so without the guard it looks like a load and is checked at a phantom address, which a denying region would turn into an M-mode denial of service. Legacy interrupt entry and return stack traffic is deliberately out of PMP scope.
       That guard stops applying in U-mode, where isr_ret is u-gated to '0' while mem_access_controller is not; it is inert only because the illegal-instruction trap arm sits above the PMP data arm in all four EXECUTE shapes. Hoisting the PMP arm needs a non-u-gated iret decode here, not a reordering. */
    pmp_d_rd <= '1' when (current_state = EXECUTE and
                          (lr_op = '1' or sc_op = '1' or amo_op = '1')) else
                '1' when (current_state = EXECUTE and mem_access_controller = '1'
                          and wen_controller = "1111" and isr_ret = '0') else
                '1' when (current_state = ZCM_POP_LD or current_state = ZCM_JT_LD) else
                '0';
    pmp_d_wr <= '1' when (current_state = EXECUTE and
                          (lr_op = '1' or sc_op = '1' or amo_op = '1')) else
                '1' when (current_state = EXECUTE and mem_access_controller = '1'
                          and wen_controller /= "1111") else
                '1' when (current_state = CBOZ_WRITE or current_state = ZCM_PUSH_ST) else
                '0';

    -- ACCESS CLASS for the cause code: LR is a READ that checks both R and W, so it is deliberately absent from this term.
    pmp_d_st_class <= '1' when (current_state = EXECUTE and (sc_op = '1' or amo_op = '1')) else
                      '1' when (current_state = EXECUTE and mem_access_controller = '1'
                                and wen_controller /= "1111") else
                      '1' when (current_state = CBOZ_WRITE or current_state = ZCM_PUSH_ST) else
                      '0';

    -- "A data transaction would issue this cycle". This is '1' on a half-fetch cycle too, where instr_curr still holds the previous instruction, and that is harmless by construction:
    -- the half-fetch branch has no PMP arm and goes unconditionally to EXECUTE, so pmp_d_deny can never dispatch a trap from it. The qualifier is the FSM arm placement, as it is for amo_lock.
    pmp_d_active <= pmp_d_rd or pmp_d_wr;
    pmp_d_deny   <= '1' when (ENABLE_PMP and pmp_d_active = '1' and pmp_d_grant = '0') else '0';

    /* FETCH side. fetch_addr IS the fetch address: the data_addr mux falls through to it in every cycle that issues an instruction fetch, and it is pc_next except in the two cycles the fetch-ahead claims.
       Checking fetch_addr rather than pc_next is what keeps the pmp_f_deny_r pipeline honest, since that flop must describe the word the bus actually carried.
       A fetch-ahead denial lands in the EXECUTE that consumes the upper half, which is the cycle that dispatches the straddling instruction, so the squash is at the right instruction; the lower half was checked when its own word was fetched.
       The fetch is X-checked at pmp_f_priv, the current privilege EXCEPT during MTRAP_RET, the one state that both issues a fetch and LOWERS privilege on the same edge, so its fetch is consumed at the post-MRET privilege and must be checked there.
       Every other privilege change raises privilege, so its issued fetch is checked at the stricter old privilege, which is the safe direction. */
    pmp_f_priv <= mret_priv_m when current_state = MTRAP_RET else trap_priv_mode;

    pmp_f_deny <= '1' when (ENABLE_PMP and pmp_f_grant = '0') else '0';

    pmp_if_squash <= '1' when (ENABLE_PMP and current_state = EXECUTE and pmp_f_deny_r = '1')
                     else '0';

    -- PARK SELECT, three ENABLE_PMP-gated cases: the address this cycle would fetch is X-denied; the EXECUTE cycle that consumes a denied fetch, whose pc_next comes from the PARK word's decode and is therefore arbitrary; and MTRAP_SV of an instruction-access-fault entry, the re-presentation window, where privilege has already flipped to M so the check would now grant it.
    -- MTRAP_JUMP is deliberately NOT parked, since it issues the mtvec fetch. All three park on the SAME address, so hart_tile's ack latch absorbs them into one benign ROM read.
    pmp_if_park <= '1' when (ENABLE_PMP and
                             (pmp_f_deny = '1' or pmp_if_squash = '1' or
                              (current_state = MTRAP_SV and mtrap_cause_int = '0'
                               and mtrap_cause_code = x"1")))
                   else '0';

    -- mtval source at the dispatch cycle (latched below).
    mtrap_disp_val <= pmp_f_addr_r when (current_state = EXECUTE and pmp_f_deny_r = '1')
                      else pmp_d_addr;

    gen_pmp: if ENABLE_PMP generate
        pmp_inst: pmp_unit
            generic map (
                ENABLE_PMP  => ENABLE_PMP,
                PMP_ENTRIES => PMP_ENTRIES
            )
            port map (
                pmp_cfg_flat  => pmp_cfg_flat_sig,
                pmp_addr_flat => pmp_addr_flat_sig,
                -- FETCH: X at the effective fetch privilege, the current privilege or the return privilege during MTRAP_RET.
                -- Never MPRV-redirected: MPRV governs data accesses only.
                f_addr        => fetch_addr,
                f_priv_m      => pmp_f_priv,
                f_grant       => pmp_f_grant,
                -- DATA: R/W at the EFFECTIVE data privilege, after the mstatus.MPRV redirect.
                d_addr        => pmp_d_addr,
                d_priv_m      => eff_data_priv_m,
                d_read        => pmp_d_rd,
                d_write       => pmp_d_wr,
                d_grant       => pmp_d_grant
            );

        -- The fetch-check pipeline, sampled on EVERY clk_cpu edge, which is what makes the "previous core cycle's fetch" invariant hold without enumerating states.
        -- Whenever the FSM redirects the PC, the redirected address is on pc_next in that very cycle and is therefore the value this flop carries into the EXECUTE that consumes it.
        pmp_ifetch_proc: process(clk_cpu, resetn)
        begin
            if resetn = '0' then
                pmp_f_deny_r <= '0';
                pmp_f_addr_r <= (others => '0');
            elsif rising_edge(clk_cpu) then
                pmp_f_deny_r <= pmp_f_deny;
                pmp_f_addr_r <= fetch_addr;
            end if;
        end process;

        -- mtval latch, on the same edge and condition as mtrap_cause_proc; a separate process so its 32 flops sit inside the generate and an OFF build carries none of them.
        pmp_mtval_proc: process(clk_cpu, resetn)
        begin
            if resetn = '0' then
                mtrap_val_r <= (others => '0');
            elsif rising_edge(clk_cpu) then
                if next_state = MTRAP_SV and current_state /= MTRAP_SV then
                    mtrap_val_r <= mtrap_disp_val;
                end if;
            end if;
        end process;
    end generate;

    gen_pmp_off: if not ENABLE_PMP generate
        -- Grant everything, with no flops and no unit, so the OFF cell lists need no pmp_unit entry.
        pmp_f_grant  <= '1';
        pmp_d_grant  <= '1';
        pmp_f_deny_r <= '0';
        pmp_f_addr_r <= (others => '0');
        mtrap_val_r  <= (others => '0');
    end generate;

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


    -- FSM next-state logic.
    next_state_logic: process(resetn, current_state, pc, instr, quadrant_upper, quadrant_lower,
                             repeat_if, split_ready, instr_upper_half, instr_lower_half, instr_decomp,
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
                             wfi_op, std_wfi_wake,
                             pmp_f_deny_r, pmp_d_deny,
                             -- The debug decision signals MUST be listed: in an absorbing state such as SLEEPING or TRAP_STATE nothing else in this list moves, so without them the process never re-runs to see a halt request and next_state sticks forever.
                             -- A synthesis tool ignores sensitivity lists, so omitting them makes the netlist right and every behavioural run wrong, which is the worst direction.
                             dbg_halt_take, dbg_ebreak_take, dbg_exc_take, dret_op, debug_mode,
                             -- The commit tail reads these four. A same-process signal read returns the PREVIOUS delta's value, so without them a state can be driven from STALE intent, for instance a retiring instruction's ci_pc_advance leaking into the split-fetch bubble and advancing the PC mid-instruction.
                             -- No ci_* right-hand side is a function of the four owned outputs or of any ci_*, so there is no feedback and the extra evaluation settles in one delta.
                             ci_rd_commit, ci_sp_commit, ci_st_lanes, ci_pc_advance)
    begin
        if resetn = '0' then
            -- Reset all control signals.
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
            wfi_enter <= '0';   -- standard-WFI entry marker
            -- The reset branch drives the four owned nets ITSELF, and two of those drives are deliberately NOT the fail-safe intent values: wen takes wen_controller rather than all-ones, and pc_en takes '1' rather than hold.
            -- The commit block sits in the ELSE branch and cannot reach reset, so these four lines stay exactly as written; the intent defaults below are still fail-safe, so intent and the live nets differ during reset by construction.
            ci_rd_commit  <= '0';
            ci_sp_commit  <= '0';
            ci_st_lanes   <= "0000";
            ci_pc_advance <= '0';

        else
            -- Default signal values. The four commit-block nets (reg_write_dp, sp_write_en, wen, pc_en) are deliberately ABSENT: the commit block at the end of this branch drives them unconditionally from the ci_* intent each state declares.
            -- A default here would be dead code overwritten every cycle, and would read as though a state could rely on it.
            mem_access_instr <= '0';
            repeat_if_req <= '0';
            clr_repeat_if <= '0';
            div_start <= '0';
            ltch_lh_inst <= '0';
            irq_save_ack <= '0';
            trap_flag <= '0';
            wfi_enter <= '0';   -- only the WFI dispatch arms raise this
            -- Commit-intent defaults, all fail-safe.
            ci_rd_commit  <= '0';
            ci_sp_commit  <= '0';
            ci_st_lanes   <= "0000";
            ci_pc_advance <= '0';

            case current_state is
                -- INITIALIZE passes the LIVE DECODE through to rd and to the store lanes, which is inert because instr_curr is forced to a nop whenever this state is current: the decode does write rd, but rd is x0 and the regfile discards it, and a nop is not a store.
                -- The state is UNREACHABLE by design, since the only producer of next_state = INITIALIZE sits inside the reset branch where the async reset dominates; it is kept, and kept correct, for a corrupted state encoding.
                when INITIALIZE =>
                    next_state <= EXECUTE;
                    mem_access_instr <= '0';
                    div_start <= '0';
                    is_compressed <= '0';
                    ci_rd_commit  <= reg_write_ctrl;
                    ci_st_lanes   <= not wen_controller;
                    ci_pc_advance <= '1';

                -- EXECUTE: main instruction execution.
                when EXECUTE =>
                    /* PMP INSTRUCTION ACCESS FAULT (cause 1), FIRST and above every other decode arm, because the fetch that would have delivered this word NEVER ISSUED and the decoder is looking at the park word.
                       Hoisting it to the top of the state, rather than into the four dispatch sub-trees, is what keeps a park word whose bits 17:16 happen to read "11" out of the half-fetch branch.
                       mepc is pc, the faulting instruction's own address, which for a straddling 32-bit instruction is the LOWER half's even when the UPPER half is the denied one; mtval is the denied half's address. Legacy mode keeps the terminal TRAP_STATE. */
                    if ENABLE_PMP and pmp_f_deny_r = '1' then
                        mem_access_instr <= '0';
                        -- Clear a pending repeat_if: when the DENIED fetch is the upper half of a straddling instruction the lower-half cycle already set it, and this arm is hoisted above the branch that normally clears it.
                        -- A stale flag would survive the trap and hijack the first compressed instruction the handler fetches. Harmless when repeat_if was already 0.
                        clr_repeat_if    <= '1';
                        if dbg_exc_take = '1' then
                            -- Debug mode never traps out; re-enter instead. See dbg_exc_take.
                            mem_access_instr <= '0';
                            next_state <= DBG_JUMP;
                        elsif std_mode = '1' then
                            next_state <= MTRAP_SV;
                        else
                            next_state <= TRAP_STATE;
                        end if;
                    -- With the C extension disabled a halfword-aligned PC is an instruction-address-misaligned condition, reachable only via a jump or branch to a non-word boundary, so trap instead of decoding garbage instruction halves.
                    -- The condition is statically false when ENABLE_COMPRESSED, so the default build's FSM is untouched.
                    elsif (not ENABLE_COMPRESSED) and pc(1) = '1' then
                        -- Instruction-address-misaligned: standard mode takes it as a RECOVERABLE exception, cause 0 with mtval the misaligned PC, and legacy mode keeps the terminal TRAP_STATE.
                        -- The arm declares no commit, so the block drives reg_write_dp '0' and wen all-ones: a misaligned-fetch trap must not commit the faulting encoding's rd or its store lanes.
                        if dbg_exc_take = '1' then
                            -- Debug mode never traps out; re-enter instead. See dbg_exc_take.
                            mem_access_instr <= '0';
                            next_state <= DBG_JUMP;
                        elsif std_mode = '1' then
                            next_state <= MTRAP_SV;
                        else
                            next_state <= TRAP_STATE;
                        end if;
                    elsif pc(1) = '1' then
                        -- Current instruction on a half-word boundary.
                        if quadrant_upper = "11" or split_ready = '1' then
                            -- Not compressed, or fetching the upper half.
                            is_compressed <= '0';

                            if split_ready = '1' then
                                -- Completing the split fetch of a 32-bit instruction: the full dispatch tree, since this is where a straddling instruction actually issues.
                                -- Reached with a bubble spent (repeat_if) or with none (if_ahead); the two are indistinguishable from here, both having the lower half in instr_lower_half and the upper half on the bus.
                                clr_repeat_if <= '1';

                                -- Choose the next state by instruction class.
                                if trap = '1' then
                                    if dbg_exc_take = '1' then
                                        -- Debug mode never traps out; re-enter instead. See dbg_exc_take.
                                        mem_access_instr <= '0';
                                        next_state <= DBG_JUMP;
                                    elsif std_mode = '1' then
                                        -- Recoverable illegal-instruction exception: cause 2, mtval the faulting encoding, and zero memory transactions.
                                        next_state <= MTRAP_SV;
                                        mem_access_instr <= '0';
                                    else
                                        next_state <= TRAP_STATE;
                                        -- The legacy trap-entry cycle keeps the live decode's rd and lane drives.
                                        ci_rd_commit <= reg_write_ctrl;
                                        ci_st_lanes  <= not wen_controller;
                                    end if;
                                -- An ebreak entering debug mode is tested ABOVE the shared ecall/ebreak arm, which would otherwise absorb it. Not in debug mode goes to DBG_SV, a full entry recording this ebreak's OWN pc;
                                -- already in debug mode goes to DBG_JUMP, which reloads the PC and writes NOTHING, because dpc and dcsr.cause must survive an ebreak taken by debug code or the debugger loses its return address.
                                elsif ebreak_op = '1' and dbg_ebreak_take = '1' then
                                    mem_access_instr <= '0';
                                    if debug_mode = '1' then
                                        next_state <= DBG_JUMP;
                                    else
                                        next_state <= DBG_SV;
                                    end if;
                                elsif ecall_op = '1' or ebreak_op = '1' then
                                    -- ECALL (cause 11) and EBREAK (cause 3), both with mtval 0 and mepc the instruction's OWN PC.
                                    -- In legacy mode they are legal decodes with no legacy semantics, so they land in the terminal TRAP_STATE, where the illegal-instruction path puts them.
                                    mem_access_instr <= '0';
                                    if dbg_exc_take = '1' then
                                        -- Debug mode never traps out; re-enter instead. See dbg_exc_take.
                                        next_state <= DBG_JUMP;
                                    elsif std_mode = '1' then
                                        next_state <= MTRAP_SV;
                                    else
                                        next_state <= TRAP_STATE;
                                    end if;
                                -- DRET is the MRET shape exactly: a CSR-based restore in ONE state, no memory transaction, with the PC taking dpc.
                                -- dret_op carries its own debug_mode qualifier from maindec, so this arm cannot fire outside debug mode, where the encoding is illegal and takes the trap arm above. There is no std_mode branch, debug mode not being a delivery mode.
                                elsif dret_op = '1' then
                                    mem_access_instr <= '0';
                                    next_state <= DBG_RET;
                                elsif mret_op = '1' then
                                    -- MRET: the PC takes mepc and mstatus pops, in the dedicated MTRAP_RET state, a JALR shape with no memory access and no writeback. Legacy mode goes to the terminal TRAP_STATE.
                                    mem_access_instr <= '0';
                                    if std_mode = '1' then
                                        next_state <= MTRAP_RET;
                                    else
                                        next_state <= TRAP_STATE;
                                    end if;
                                elsif ENABLE_PMP and pmp_d_deny = '1' then
                                    /* PMP load/store access fault: cause 5 for a load or LR, 7 for a store, SC or AMO, with mtval the byte-precise data address and mepc the pc.
                                       It sits after the trap, ECALL, EBREAK and MRET arms and before every memory dispatch arm, so an illegal encoding still reports cause 2 and a memory instruction can never reach its own arm.
                                       PRE-ISSUE GUARANTEE: mem_access_instr stays '0', so data_addr keeps the fetch fall-through, sh_req never rises for the denied address and no request is yanked from the arbiter; wen all-ones kills the private-RAM lane strobes. */
                                    mem_access_instr <= '0';
                                    if dbg_exc_take = '1' then
                                        -- Debug mode never traps out; re-enter instead. See dbg_exc_take.
                                        next_state <= DBG_JUMP;
                                    elsif std_mode = '1' then
                                        next_state <= MTRAP_SV;
                                    else
                                        next_state <= TRAP_STATE;
                                    end if;
                                elsif sleep_rq = '1' then
                                    next_state <= SLEEPING;
                                    ci_rd_commit <= reg_write_ctrl;
                                    ci_st_lanes  <= not wen_controller;
                                elsif wfi_op = '1' then
                                    -- Standard WFI: enter SLEEPING and RAISE the entry-reason marker, so the SLEEPING arm applies the standard wake rule instead of extinguish's.
                                    -- pc is frozen exactly as for extinguish, so pc_next_reg holds WFI+4, which is both the resume PC and, if the hart vectors, the mepc.
                                    next_state <= SLEEPING;
                                    wfi_enter  <= '1';
                                    ci_rd_commit <= reg_write_ctrl;
                                    ci_st_lanes  <= not wen_controller;
                                elsif wrs_op = '1' then
                                    -- Zawrs: stall only if a global reservation is live, otherwise the hint retires immediately.
                                    ci_rd_commit <= reg_write_ctrl;
                                    ci_st_lanes  <= not wen_controller;
                                    if resv_valid_ext = '1' then
                                        next_state <= WRS_WAIT;
                                    else
                                        next_state <= EXECUTE;  -- the hint retires here
                                        ci_pc_advance <= '1';
                                    end if;
                                elsif lr_op = '1' then
                                    -- Load-Reserved.
                                    mem_access_instr <= '1';
                                    next_state <= LR_READ;
                                    ci_st_lanes <= not wen_controller;
                                elsif sc_op = '1' then
                                    -- Store-Conditional. NO EXECUTE-phase access: the ALU holds rs1+rs2 here, a garbage address, and the only SC access is SC_CHECK's conditional write.
                                    -- The store lanes must stay suppressed here too, wen_controller decoding SC as a word store, or the write commits before the reservation check.
                                    mem_access_instr <= '0';
                                    next_state <= SC_CHECK;
                                elsif amo_op = '1' then
                                    -- Atomic memory operation.
                                    mem_access_instr <= '1';
                                    next_state <= AMO_READ;
                                elsif cboz_op = '1' then
                                    -- Launch the cbo.zero block-zero store sequencer: no memory access this cycle, since the stores issue in CBOZ_WRITE, and the PC is frozen until the burst retires.
                                    -- cboz_base is latched from the live rs1 on THIS transition, and wen stays inactive so the fetch-addressed cycle commits no write.
                                    mem_access_instr <= '0';
                                    next_state <= CBOZ_WRITE;
                                elsif fence_op = '1' then
                                    -- An exact PAUSE hint enters the arbiter-yield window instead of the one-cycle FENCE nop, with pc_en frozen so it holds and retires when the window closes.
                                    -- The knob and the non-zero window are static, so a disabled build takes the FENCE arm and is bit-identical.
                                    ci_rd_commit <= reg_write_ctrl;
                                    ci_st_lanes  <= not wen_controller;
                                    if ENABLE_ZIHINT and pause_hint = '1' and PAUSE_WINDOW_CYCLES > 0 then
                                        next_state <= PAUSE_WAIT;
                                    else
                                        next_state <= FENCE_WAIT;
                                        ci_pc_advance <= '1';
                                    end if;
                                elsif mem_access_controller = '1' then
                                    /* AN `iret` IS NOT A LOAD, and this is the arm it takes: maindec raises mem_access_controller for the CUSTOM_OPCODE iret encoding, so without the qualifier every ISR return issues a real, side-effecting read at reg[rs1]+reg[rs2],
                                       which for the canonical encoding lands in the shared boot ROM and is a genuine arbiter transaction, and with a steered rs1 could claim a hardware mutex.
                                       Suppressing the request keeps the trajectory: next_state, pc_en and reg_write_dp are untouched, the real pop is still addressed from stack_pointer in MEMORY_WAIT, and data_addr falls through to pc_next, an ordinary early fetch. */
                                    mem_access_instr <= not isr_ret;
                                    next_state <= MEMORY_WAIT;
                                    ci_st_lanes <= not wen_controller;
                                elsif is_div_op = '1' then
                                    next_state <= DIV_WAIT;
                                    -- The EXECUTE-cycle writeback must stay suppressed: the decode says reg_write='1' for a DIV, so an unsuppressed dispatch cycle writes rd with the ALU's idle result, 0, BEFORE the divider latches its operands.
                                    -- With rd equal to rs1 that zero becomes the dividend and the result is 0; with rd equal to rs2 it zeroes the divisor and gives a spurious divide by zero. rd is written exactly once, at DIV_DONE.
                                    ci_st_lanes <= not wen_controller;
                                elsif is_fp_fma = '1' then
                                    -- FMA: fetch rs3, then run. pc_en is frozen and rd stays uncommitted across the whole dispatch and wait window, so the writeback lands only in FPU_DONE, exactly as for a divide.
                                    next_state <= FPU_FETCH3;
                                    ci_st_lanes <= not wen_controller;
                                elsif is_fp_multicycle = '1' then
                                    next_state <= FPU_WAIT;
                                    ci_st_lanes <= not wen_controller;
                                -- THE HALT/STEP RECOGNITION SITE, above BOTH delivery takes: a halt request is unmaskable, so it must be tested before irq_save and std_irq_take, and it rides every point an interrupt already diverts from.
                                -- Its commit declarations match the irq_save arm: a halt is taken BETWEEN instructions, so the in-flight instruction still retires and dpc becomes the address of the NEXT one.
                                elsif dbg_halt_take = '1' then
                                    next_state <= DBG_SV;
                                    ci_rd_commit <= reg_write_ctrl;
                                    ci_st_lanes  <= not wen_controller;
                                elsif irq_save = '1' then
                                    next_state <= IRQ_SV;
                                    ci_rd_commit <= reg_write_ctrl;
                                    ci_st_lanes  <= not wen_controller;
                                elsif std_irq_take = '1' then
                                    -- Standard delivery reuses this check point: irq_save cannot fire in standard mode, where irq_en_eff is masked all-zero and the handler FSM is pinned in IDLE, and std_irq_take is '0' in legacy mode, so the two arms are mutually exclusive by construction.
                                    next_state <= MTRAP_SV;
                                    ci_rd_commit <= reg_write_ctrl;
                                    ci_st_lanes  <= not wen_controller;
                                elsif isr_ret = '1' then
                                    next_state <= IRQ_REST;
                                    ci_rd_commit  <= reg_write_ctrl;
                                    ci_st_lanes   <= not wen_controller;
                                    ci_pc_advance <= '1';
                                else
                                    next_state <= EXECUTE;
                                    ci_rd_commit  <= reg_write_ctrl;
                                    ci_st_lanes   <= not wen_controller;
                                    ci_pc_advance <= '1';
                                end if;
                            else
                                -- Need to fetch the upper half of the instruction. This bubble cycle declares NO commit intent, so it neither writes rd, nor stores, nor advances the PC; it fires on every straddling 32-bit instruction.
                                ltch_lh_inst <= '1';
                                repeat_if_req <= '1';
                                next_state <= EXECUTE;
                            end if;
                        else

                            -- Compressed instruction on a half-word boundary. This shape has no fence, lr, sc, amo, cboz, wfi, wrs or fp arms at all, because no compressed encoding decompresses to one; the last assertion at the end of this file polices that.
                            is_compressed <= '1';
                            if trap = '1' then
                                if dbg_exc_take = '1' then
                                    -- Debug mode never traps out; re-enter instead. See dbg_exc_take.
                                    mem_access_instr <= '0';
                                    next_state <= DBG_JUMP;
                                elsif std_mode = '1' then
                                    -- Recoverable illegal-instruction exception.
                                    next_state <= MTRAP_SV;
                                    mem_access_instr <= '0';
                                else
                                    next_state <= TRAP_STATE;
                                    ci_rd_commit <= reg_write_ctrl;
                                    ci_st_lanes  <= not wen_controller;
                                end if;
                            -- An ebreak taking a debug entry, above the shared ecall/ebreak arm; see the split-fetch dispatch arm above.
                            elsif ebreak_op = '1' and dbg_ebreak_take = '1' then
                                mem_access_instr <= '0';
                                if debug_mode = '1' then
                                    next_state <= DBG_JUMP;
                                else
                                    next_state <= DBG_SV;
                                end if;
                            elsif ecall_op = '1' or ebreak_op = '1' then
                                -- c.ebreak DECOMPRESSES to EBREAK, so this compressed arm really can see ebreak_op and routes it exactly as the 32-bit arm does.
                                -- ECALL and MRET have no compressed form; carrying the term anyway costs nothing and keeps the four decode arms uniform.
                                mem_access_instr <= '0';
                                if dbg_exc_take = '1' then
                                    -- Debug mode never traps out; re-enter instead. See dbg_exc_take.
                                    next_state <= DBG_JUMP;
                                elsif std_mode = '1' then
                                    next_state <= MTRAP_SV;
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            -- DRET; see the split-fetch dispatch arm above.
                            elsif dret_op = '1' then
                                mem_access_instr <= '0';
                                next_state <= DBG_RET;
                            elsif mret_op = '1' then
                                mem_access_instr <= '0';
                                if std_mode = '1' then
                                    next_state <= MTRAP_RET;
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            elsif ENABLE_PMP and pmp_d_deny = '1' then
                                -- PMP load/store access fault; see the split-fetch dispatch arm above.
                                -- A compressed c.lw or c.sw reaches it through mem_access_controller exactly like a 32-bit one; cm.* sequencer steps are checked in their OWN states, so pmp_d_active is '0' at a zcm dispatch.
                                mem_access_instr <= '0';
                                if dbg_exc_take = '1' then
                                    -- Debug mode never traps out; re-enter instead. See dbg_exc_take.
                                    next_state <= DBG_JUMP;
                                elsif std_mode = '1' then
                                    next_state <= MTRAP_SV;
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            elsif zcm_op = '1' then
                                mem_access_instr <= '0';
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
                                -- The iret qualifier; see the split-fetch dispatch arm above. It is statically '0' in this COMPRESSED shape, isr_ret needing op = CUSTOM_OPCODE which c_dec never emits, and folds away.
                                -- It is carried on all four dispatch shapes anyway, so the rule is uniform and a fifth shape would inherit it.
                                mem_access_instr <= not isr_ret;
                                next_state <= MEMORY_WAIT;
                                ci_st_lanes <= not wen_controller;
                            elsif is_div_op = '1' then
                                next_state <= DIV_WAIT;
                                -- The EXECUTE-cycle writeback must stay suppressed: the decode says reg_write='1' for a DIV, so an unsuppressed dispatch cycle clobbers rd with the ALU's idle result, 0, before the divider latches its operands. rd is written exactly once, at DIV_DONE.
                                ci_st_lanes <= not wen_controller;
                            -- Halt/step recognition, above both delivery takes: a halt request is unmaskable, so it is tested before irq_save and std_irq_take.
                            elsif dbg_halt_take = '1' then
                                next_state <= DBG_SV;
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                            elsif irq_save = '1' then
                                next_state <= IRQ_SV;
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                            elsif std_irq_take = '1' then
                                -- Standard delivery reuses this check point: irq_save cannot fire in standard mode, where irq_en_eff is masked all-zero and the handler FSM is pinned in IDLE, and std_irq_take is '0' in legacy mode, so the two arms are mutually exclusive by construction.
                                next_state <= MTRAP_SV;
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                            elsif isr_ret = '1' then
                                next_state <= IRQ_REST;
                                ci_rd_commit  <= reg_write_ctrl;
                                ci_st_lanes   <= not wen_controller;
                                ci_pc_advance <= '1';
                            else
                                next_state <= EXECUTE;
                                ci_rd_commit  <= reg_write_ctrl;
                                ci_st_lanes   <= not wen_controller;
                                ci_pc_advance <= '1';
                            end if;
                        end if;
                    else
                        -- Full word boundary
                        if quadrant_lower = "11" then
                            -- Not compressed: the word-aligned 32-bit shape, the most-executed dispatch in the machine, structurally identical to the split-fetch completion above.
                            is_compressed <= '0';

                            if trap = '1' then
                                if dbg_exc_take = '1' then
                                    -- Debug mode never traps out; re-enter instead. See dbg_exc_take.
                                    mem_access_instr <= '0';
                                    next_state <= DBG_JUMP;
                                elsif std_mode = '1' then
                                    -- Recoverable illegal-instruction exception: cause 2, mtval the faulting encoding.
                                    next_state <= MTRAP_SV;
                                    mem_access_instr <= '0';
                                else
                                    next_state <= TRAP_STATE;
                                    ci_rd_commit <= reg_write_ctrl;
                                    ci_st_lanes  <= not wen_controller;
                                end if;
                            -- An ebreak taking a debug entry, above the shared ecall/ebreak arm; see the split-fetch dispatch arm above.
                            elsif ebreak_op = '1' and dbg_ebreak_take = '1' then
                                mem_access_instr <= '0';
                                if debug_mode = '1' then
                                    next_state <= DBG_JUMP;
                                else
                                    next_state <= DBG_SV;
                                end if;
                            elsif ecall_op = '1' or ebreak_op = '1' then
                                -- ECALL (cause 11) and EBREAK (cause 3); see the split-fetch dispatch arm above.
                                mem_access_instr <= '0';
                                if dbg_exc_take = '1' then
                                    -- Debug mode never traps out; re-enter instead. See dbg_exc_take.
                                    next_state <= DBG_JUMP;
                                elsif std_mode = '1' then
                                    next_state <= MTRAP_SV;
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            -- DRET; see the split-fetch dispatch arm above.
                            elsif dret_op = '1' then
                                mem_access_instr <= '0';
                                next_state <= DBG_RET;
                            elsif mret_op = '1' then
                                -- MRET; see the split-fetch dispatch arm above.
                                mem_access_instr <= '0';
                                if std_mode = '1' then
                                    next_state <= MTRAP_RET;
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            elsif ENABLE_PMP and pmp_d_deny = '1' then
                                -- PMP load/store access fault; see the split-fetch dispatch arm above.
                                mem_access_instr <= '0';
                                if dbg_exc_take = '1' then
                                    -- Debug mode never traps out; re-enter instead. See dbg_exc_take.
                                    next_state <= DBG_JUMP;
                                elsif std_mode = '1' then
                                    next_state <= MTRAP_SV;
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            elsif sleep_rq = '1' then
                                next_state <= SLEEPING;
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                            elsif wfi_op = '1' then
                                -- Standard WFI; see the split-fetch dispatch arm above.
                                -- WFI is a 32-bit SYSTEM encoding with no compressed form, so the two non-compressed dispatch arms are the ONLY places it can appear, like extinguish beside it.
                                next_state <= SLEEPING;
                                wfi_enter  <= '1';
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                            elsif wrs_op = '1' then
                                -- Zawrs: stall only if a global reservation is live, otherwise the hint retires immediately.
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                                if resv_valid_ext = '1' then
                                    next_state <= WRS_WAIT;
                                else
                                    next_state <= EXECUTE;  -- pc_en defaults '1'
                                    ci_pc_advance <= '1';
                                end if;
                            elsif lr_op = '1' then
                                -- Load-Reserved.
                                mem_access_instr <= '1';
                                next_state <= LR_READ;
                                ci_st_lanes <= not wen_controller;
                            elsif sc_op = '1' then
                                -- Store-Conditional: no EXECUTE-phase access and no store lanes, the only SC access being SC_CHECK's conditional write. See the split-fetch dispatch arm above.
                                mem_access_instr <= '0';
                                next_state <= SC_CHECK;
                            elsif amo_op = '1' then
                                -- Atomic memory operation.
                                mem_access_instr <= '1';
                                next_state <= AMO_READ;
                            elsif cboz_op = '1' then
                                -- Launch the cbo.zero sequencer; see the split-fetch dispatch arm above.
                                -- No access this cycle, the PC is frozen, and cboz_base is latched from rs1 on this transition.
                                mem_access_instr <= '0';
                                next_state <= CBOZ_WRITE;
                            elsif fence_op = '1' then
                                -- A PAUSE enters the arbiter-yield window, any other FENCE becomes a one-cycle nop; see the split-fetch dispatch arm above.
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                                if ENABLE_ZIHINT and pause_hint = '1' and PAUSE_WINDOW_CYCLES > 0 then
                                    next_state <= PAUSE_WAIT;
                                else
                                    next_state <= FENCE_WAIT;
                                    ci_pc_advance <= '1';
                                end if;
                            elsif mem_access_controller = '1' then
                                -- The iret qualifier; see the split-fetch dispatch arm above. This word-aligned 32-bit shape and that one are the two that really carry an `iret`.
                                mem_access_instr <= not isr_ret;
                                next_state <= MEMORY_WAIT;
                                ci_st_lanes <= not wen_controller;
                            elsif is_div_op = '1' then
                                next_state <= DIV_WAIT;
                                -- The EXECUTE-cycle writeback must stay suppressed: the decode says reg_write='1' for a DIV, so an unsuppressed dispatch cycle clobbers rd with the ALU's idle result, 0, before the divider latches its operands. rd is written exactly once, at DIV_DONE.
                                ci_st_lanes <= not wen_controller;
                            elsif is_fp_fma = '1' then
                                -- FMA: freeze pc_en and leave rd uncommitted across dispatch; see the split-fetch dispatch arm above.
                                next_state <= FPU_FETCH3;
                                ci_st_lanes <= not wen_controller;
                            elsif is_fp_multicycle = '1' then
                                next_state <= FPU_WAIT;
                                ci_st_lanes <= not wen_controller;
                            -- Halt/step recognition, above both delivery takes: a halt request is unmaskable, so it is tested before irq_save and std_irq_take.
                            elsif dbg_halt_take = '1' then
                                next_state <= DBG_SV;
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                            elsif irq_save = '1' then
                                next_state <= IRQ_SV;
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                            elsif std_irq_take = '1' then
                                -- Standard delivery reuses this check point: irq_save cannot fire in standard mode, where irq_en_eff is masked all-zero and the handler FSM is pinned in IDLE, and std_irq_take is '0' in legacy mode, so the two arms are mutually exclusive by construction.
                                next_state <= MTRAP_SV;
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                            elsif isr_ret = '1' then
                                next_state <= IRQ_REST;
                                ci_rd_commit  <= reg_write_ctrl;
                                ci_st_lanes   <= not wen_controller;
                                ci_pc_advance <= '1';
                            else
                                next_state <= EXECUTE;
                                ci_rd_commit  <= reg_write_ctrl;
                                ci_st_lanes   <= not wen_controller;
                                ci_pc_advance <= '1';
                            end if;
                        else
                            -- Compressed instruction on a word boundary. It shares the half-word compressed shape's missing-arm set: no fence, lr, sc, amo, cboz, wfi, wrs or fp arms, because no compressed encoding decompresses to one.
                            is_compressed <= '1';
                            if trap = '1' then
                                if dbg_exc_take = '1' then
                                    -- Debug mode never traps out; re-enter instead. See dbg_exc_take.
                                    mem_access_instr <= '0';
                                    next_state <= DBG_JUMP;
                                elsif std_mode = '1' then
                                    -- Recoverable illegal-instruction exception.
                                    next_state <= MTRAP_SV;
                                    mem_access_instr <= '0';
                                else
                                    next_state <= TRAP_STATE;
                                    ci_rd_commit <= reg_write_ctrl;
                                    ci_st_lanes  <= not wen_controller;
                                end if;
                            -- An ebreak taking a debug entry, above the shared ecall/ebreak arm; see the split-fetch dispatch arm above.
                            elsif ebreak_op = '1' and dbg_ebreak_take = '1' then
                                mem_access_instr <= '0';
                                if debug_mode = '1' then
                                    next_state <= DBG_JUMP;
                                else
                                    next_state <= DBG_SV;
                                end if;
                            elsif ecall_op = '1' or ebreak_op = '1' then
                                -- c.ebreak decompresses to EBREAK, so this arm can see ebreak_op.
                                mem_access_instr <= '0';
                                if dbg_exc_take = '1' then
                                    -- Debug mode never traps out; re-enter instead. See dbg_exc_take.
                                    next_state <= DBG_JUMP;
                                elsif std_mode = '1' then
                                    next_state <= MTRAP_SV;
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            -- DRET; see the split-fetch dispatch arm above.
                            elsif dret_op = '1' then
                                mem_access_instr <= '0';
                                next_state <= DBG_RET;
                            elsif mret_op = '1' then
                                mem_access_instr <= '0';
                                if std_mode = '1' then
                                    next_state <= MTRAP_RET;
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            elsif ENABLE_PMP and pmp_d_deny = '1' then
                                -- PMP load/store access fault; see the split-fetch dispatch arm above.
                                -- A compressed c.lw or c.sw reaches it through mem_access_controller exactly like a 32-bit one; cm.* sequencer steps are checked in their OWN states, so pmp_d_active is '0' at a zcm dispatch.
                                mem_access_instr <= '0';
                                if dbg_exc_take = '1' then
                                    -- Debug mode never traps out; re-enter instead. See dbg_exc_take.
                                    next_state <= DBG_JUMP;
                                elsif std_mode = '1' then
                                    next_state <= MTRAP_SV;
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            elsif zcm_op = '1' then
                                mem_access_instr <= '0';
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
                                -- The iret qualifier; see the split-fetch dispatch arm above. It is statically '0' in this COMPRESSED shape and is carried only for uniformity.
                                mem_access_instr <= not isr_ret;
                                next_state <= MEMORY_WAIT;
                                ci_st_lanes <= not wen_controller;
                            elsif is_div_op = '1' then
                                next_state <= DIV_WAIT;
                                -- The EXECUTE-cycle writeback must stay suppressed: the decode says reg_write='1' for a DIV, so an unsuppressed dispatch cycle clobbers rd with the ALU's idle result, 0, before the divider latches its operands. rd is written exactly once, at DIV_DONE.
                                ci_st_lanes <= not wen_controller;
                            -- Halt/step recognition, above both delivery takes: a halt request is unmaskable, so it is tested before irq_save and std_irq_take.
                            elsif dbg_halt_take = '1' then
                                next_state <= DBG_SV;
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                            elsif irq_save = '1' then
                                next_state <= IRQ_SV;
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                            elsif std_irq_take = '1' then
                                -- Standard delivery reuses this check point: irq_save cannot fire in standard mode, where irq_en_eff is masked all-zero and the handler FSM is pinned in IDLE, and std_irq_take is '0' in legacy mode, so the two arms are mutually exclusive by construction.
                                next_state <= MTRAP_SV;
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                            -- This shape deliberately has NO `elsif isr_ret` branch, unlike its siblings, and one must not be added: isr_ret requires op = CUSTOM_OPCODE, which c_dec never emits, so no compressed instruction can decompress into an `iret`.
                            -- By the same argument the half-word compressed shape's own isr_ret arm is dead; neither is removed, deleting a dead arm from one of four near-identical shapes being the bigger readability hazard.
                            else
                                next_state <= EXECUTE;
                                ci_rd_commit  <= reg_write_ctrl;
                                ci_st_lanes   <= not wen_controller;
                                ci_pc_advance <= '1';
                            end if;
                        end if;
                    end if;

                -- AMO read phase: it asserts the request but commits nothing yet.
                when AMO_READ =>
                    mem_access_instr <= '1';
                    next_state <= AMO_WRITEBACK;
                -- The AMO's rd commit site: it returns the OLD memory value to rd, so the declaration is an unconditional '1' rather than the live decode, the value being the state's own.
                when AMO_WRITEBACK =>
                    mem_access_instr <= '0';
                    ci_rd_commit <= '1';
                    next_state <= AMO_COMPUTE;

                -- AMO compute phase: rd was already committed in AMO_WRITEBACK, so this cycle commits nothing.
                when AMO_COMPUTE =>
                    mem_access_instr <= '0';
                    next_state <= AMO_WRITE;

                -- AMO write phase. The store lanes are the COMPUTED amo_wen vector, inverted because ci_st_lanes is active-high.
                when AMO_WRITE =>
                    mem_access_instr <= '1';
                    ci_pc_advance <= '1';
                    ci_st_lanes   <= not amo_wen;
                    
                    -- Halt/step recognition, above both delivery takes: a halt request is unmaskable, so it is tested before irq_save and std_irq_take.
                    if dbg_halt_take = '1' then
                        next_state <= DBG_SV;
                        ci_pc_advance <= '0';
                    elsif irq_save = '1' then
                        next_state <= IRQ_SV;
                        ci_pc_advance <= '0';
                    elsif std_irq_take = '1' then
                        -- Standard delivery reuses this check point: irq_save cannot fire in standard mode, where irq_en_eff is masked all-zero and the handler FSM is pinned in IDLE, and std_irq_take is '0' in legacy mode, so the two arms are mutually exclusive by construction.
                        next_state <= MTRAP_SV;
                        ci_pc_advance <= '0';
                    else
                        -- Fetch the next instruction from memory.
                        next_state <= AMO_COMPLETE;
                    end if;

                -- The AMO's retire bubble, which fetches the next instruction: no access, no commit, and the PC advances unless an interrupt is taken here.
                when AMO_COMPLETE =>
                    mem_access_instr <= '0';
                    ci_pc_advance <= '1';
                    -- Halt/step recognition, above both delivery takes: a halt request is unmaskable, so it is tested before irq_save and std_irq_take.
                    if dbg_halt_take = '1' then
                        next_state <= DBG_SV;
                        ci_pc_advance <= '0';
                    elsif irq_save = '1' then
                        next_state <= IRQ_SV;
                        ci_pc_advance <= '0';
                    elsif std_irq_take = '1' then
                        -- Standard delivery reuses this check point: irq_save cannot fire in standard mode, where irq_en_eff is masked all-zero and the handler FSM is pinned in IDLE, and std_irq_take is '0' in legacy mode, so the two arms are mutually exclusive by construction.
                        next_state <= MTRAP_SV;
                        ci_pc_advance <= '0';
                    else
                        next_state <= EXECUTE;
                    end if;

                -- Load-Reserved read, and the LR's rd commit site: it returns the loaded word, so the declaration is an unconditional '1'. A read, so no store lanes.
                when LR_READ =>
                    mem_access_instr <= '1';
                    ci_pc_advance <= '1';
                    ci_rd_commit  <= '1';
                    
                    -- Halt/step recognition, above both delivery takes: a halt request is unmaskable, so it is tested before irq_save and std_irq_take.
                    if dbg_halt_take = '1' then
                        next_state <= DBG_SV;
                        ci_pc_advance <= '0';
                    elsif irq_save = '1' then
                        next_state <= IRQ_SV;
                        ci_pc_advance <= '0';
                    elsif std_irq_take = '1' then
                        -- Standard delivery reuses this check point: irq_save cannot fire in standard mode, where irq_en_eff is masked all-zero and the handler FSM is pinned in IDLE, and std_irq_take is '0' in legacy mode, so the two arms are mutually exclusive by construction.
                        next_state <= MTRAP_SV;
                        ci_pc_advance <= '0';
                    else
                        next_state <= AMO_COMPLETE;
                    end if;

                -- Store-Conditional check and write. rd is committed unconditionally, because the SC writes its success or fail result to rd on BOTH paths, so the declaration sits above the reservation test rather than inside it; only the STORE LANES are conditional.
                when SC_CHECK =>
                    ci_pc_advance <= '1';
                    ci_rd_commit  <= '1';

                    /* Write, and ISSUE A BUS ACCESS AT ALL, only when the reservation is valid and the addresses match: asserting mem_access_instr unconditionally makes a locally-FAILED sc.w perform a real, side-effecting shared-window READ, which can atomically claim a hardware mutex or the IRQ router, or auto-clear an SPI status flag.
                       Suppressing only the request is worse still, data_addr then falling through to ALU_Result, which holds the SC's own rd value here; on the failing path it falls through to pc_next instead, a harmless early fetch of the word the following AMO_COMPLETE bubble presents anyway.
                       SC-SUCCESS PREDICATE, FOUR IDENTICAL COPIES: this arm, the data_addr mux's SC_CHECK term, amo_phase and lr_sc_bus. Change all four or none, since a divergence is SILENT. */
                    if reservation_valid = '1' and reservation_addr = rs1_value then  -- rs1, not the phase-dependent ALU_result
                        ci_st_lanes <= "1111";   -- write the word: success
                        mem_access_instr <= '1';
                    else
                        -- No lanes declared, so the fail-safe intent makes wen all-ones, and no read either.
                        mem_access_instr <= '0';
                    end if;
                    
                    -- Halt/step recognition, above both delivery takes: a halt request is unmaskable, so it is tested before irq_save and std_irq_take.
                    if dbg_halt_take = '1' then
                        next_state <= DBG_SV;
                        ci_pc_advance <= '0';
                    elsif irq_save = '1' then
                        next_state <= IRQ_SV;
                        ci_pc_advance <= '0';
                    elsif std_irq_take = '1' then
                        -- Standard delivery reuses this check point: irq_save cannot fire in standard mode, where irq_en_eff is masked all-zero and the handler FSM is pinned in IDLE, and std_irq_take is '0' in legacy mode, so the two arms are mutually exclusive by construction.
                        next_state <= MTRAP_SV;
                        ci_pc_advance <= '0';
                    else
                        next_state <= AMO_COMPLETE;
                    end if;
                /* cbo.zero block-zero store: issue the full-word zero store for word cboz_idx, from the registered block base plus cboz_idx*4, with all four lanes strobed so the reservation unit sees an ordinary committed store.
                   UNINTERRUPTIBLE, there being no irq_save check, so the burst runs to completion; RAM here is idempotent and fault-free, so no mid-sequence trap and no re-execution machinery is needed.
                   The per-word PMP check rides THIS state, because the burst address only exists here; a denial leaves no lane strobe and no request, and the data_addr term is gated by the same pmp_d_deny. The PC has been frozen since dispatch, so mepc is the cbo.zero itself. */
                when CBOZ_WRITE =>
                    if ENABLE_PMP and pmp_d_deny = '1' then
                        mem_access_instr <= '0';
                        if dbg_exc_take = '1' then
                            -- Debug mode never traps out; re-enter instead. See dbg_exc_take.
                            next_state <= DBG_JUMP;
                        elsif std_mode = '1' then
                            next_state <= MTRAP_SV;
                        else
                            next_state <= TRAP_STATE;
                        end if;
                    else
                        mem_access_instr <= '1';
                        ci_st_lanes      <= "1111";
                        next_state       <= CBOZ_GAP;
                    end if;

                -- Req-low settle between block-zero stores: the arbiter re-grants a served master only after its request is OBSERVED low, so mem_access_instr '0' here drops it for one cycle and the NEXT word can be granted. No grant-lock and no new arbiter protocol.
                -- Still uninterruptible; after the last word the burst retires through MEMORY_WAIT, where the PC advance and the interrupt re-check happen, and cboz_idx advances on this state.
                when CBOZ_GAP =>
                    mem_access_instr <= '0';
                    if cboz_idx = CBOZ_WORDS - 1 then
                        next_state <= MEMORY_WAIT;
                    else
                        next_state <= CBOZ_WRITE;
                    end if;

                -- Zcmp/Zcmt sequencer states: all UNINTERRUPTIBLE, with every index and address taken from registered state, and sp committed ONCE and LAST in ZCM_SP_COMMIT, which a fault here never reaches.
                -- Per-slot pre-issue PMP check, the same contract as CBOZ_WRITE; the PC is frozen from dispatch, so mepc is the cm.push itself.
                when ZCM_PUSH_ST =>
                    if ENABLE_PMP and pmp_d_deny = '1' then
                        mem_access_instr <= '0';
                        if dbg_exc_take = '1' then
                            -- Debug mode never traps out; re-enter instead. See dbg_exc_take.
                            next_state <= DBG_JUMP;
                        elsif std_mode = '1' then
                            next_state <= MTRAP_SV;
                        else
                            next_state <= TRAP_STATE;
                        end if;
                    else
                        mem_access_instr <= '1';
                        ci_st_lanes      <= "1111";
                        next_state       <= ZCM_PUSH_GAP;
                    end if;

                -- A pure req-low settle cycle between frame stores.
                when ZCM_PUSH_GAP =>
                    mem_access_instr <= '0';
                    if zcm_idx = zcm_nregs_val - 1 then
                        next_state <= ZCM_SP_COMMIT;
                    else
                        next_state <= ZCM_PUSH_ST;
                    end if;

                -- Issue the frame-slot load. Its per-slot pre-issue check reports cause 5, a pop slot being a LOAD, and the writeback happens in ZCM_POP_WB, which a fault never reaches, so this cycle commits nothing.
                when ZCM_POP_LD =>
                    if ENABLE_PMP and pmp_d_deny = '1' then
                        mem_access_instr <= '0';
                        if dbg_exc_take = '1' then
                            -- Debug mode never traps out; re-enter instead. See dbg_exc_take.
                            next_state <= DBG_JUMP;
                        elsif std_mode = '1' then
                            next_state <= MTRAP_SV;
                        else
                            next_state <= TRAP_STATE;
                        end if;
                    else
                        mem_access_instr <= '1';
                        next_state       <= ZCM_POP_WB;
                    end if;

                -- A cm.pop rd commit site: the value is the loaded frame word.
                when ZCM_POP_WB =>
                    ci_rd_commit     <= '1';
                    mem_access_instr <= '0';
                    if zcm_idx = zcm_nregs_val - 1 then
                        if zcm_is_popretz = '1' then
                            next_state <= ZCM_A0Z;
                        else
                            next_state <= ZCM_SP_COMMIT;
                        end if;
                    else
                        next_state <= ZCM_POP_LD;
                    end if;

                -- cm.popretz clears a0, which is an rd commit.
                when ZCM_A0Z =>
                    ci_rd_commit     <= '1';
                    mem_access_instr <= '0';
                    next_state       <= ZCM_SP_COMMIT;

                -- The one and only sp commit of a cm.* sequence. The enable comes from the commit block and the DATA is assigned here, and they stay same-cycle only because that block is COMBINATIONAL and lives in this process:
                -- both settle in the same delta and land on the same clock edge. A registered commit interface would break exactly this pairing.
                when ZCM_SP_COMMIT =>
                    mem_access_instr <= '0';
                    ci_sp_commit     <= '1';
                    sp_write_data    <= zcm_final_sp;
                    if zcm_is_popret = '1' then
                        next_state <= ZCM_RET;
                    else
                        next_state <= MEMORY_WAIT;
                    end if;

                -- cm.popret's PC redirect, with no commit.
                when ZCM_RET =>
                    ci_pc_advance    <= '1';
                    mem_access_instr <= '0';
                    next_state       <= EXECUTE;

                -- First of the two cm.mv rd commits.
                when ZCM_MV1 =>
                    ci_rd_commit     <= '1';
                    mem_access_instr <= '0';
                    next_state       <= ZCM_MV2;

                -- Second cm.mv rd commit; retires via MEMORY_WAIT.
                when ZCM_MV2 =>
                    ci_rd_commit     <= '1';
                    mem_access_instr <= '0';
                    next_state       <= MEMORY_WAIT;

                -- Issue the jvt table read. It is a DATA read of jvt + 4*index riding data_addr rather than the fetch path, so it is checked on the data port and reports cause 5; the target capture and the ra link both land in ZCM_JT_WB.
                when ZCM_JT_LD =>
                    if ENABLE_PMP and pmp_d_deny = '1' then
                        mem_access_instr <= '0';
                        if dbg_exc_take = '1' then
                            -- Debug mode never traps out; re-enter instead. See dbg_exc_take.
                            next_state <= DBG_JUMP;
                        elsif std_mode = '1' then
                            next_state <= MTRAP_SV;
                        else
                            next_state <= TRAP_STATE;
                        end if;
                    else
                        mem_access_instr <= '1';
                        next_state       <= ZCM_JT_WB;
                    end if;

                -- Capture the target and redirect the PC. The rd commit is CONDITIONAL on zcm_jt_link, since cm.jalt links ra and cm.jt does not.
                when ZCM_JT_WB =>
                    ci_pc_advance    <= '1';
                    ci_rd_commit     <= zcm_jt_link;
                    mem_access_instr <= '0';
                    next_state       <= EXECUTE;

                -- A fence is a one-cycle nop on this core, and retires here.
                when FENCE_WAIT =>
                    next_state <= EXECUTE;
                    ci_pc_advance <= '1';

                /* The Zihintpause arbiter-yield window: a retiring PAUSE parks the hart here for PAUSE_WINDOW_CYCLES, with mem_access_instr '0' and the PC frozen, so data_addr defaults to pc_next and no new shared transaction is issued.
                   The PAUSE's own fetch completed in EXECUTE, so no in-flight or granted transaction is ever masked, and the window is a finite down-counter, so forward progress is guaranteed.
                   Uninterruptible-short, like DIV_WAIT: interrupts are re-checked on the EXECUTE cycle after the window rather than mid-hold. */
                when PAUSE_WAIT =>
                    mem_access_instr <= '0';
                    if pause_cnt = 0 then
                        next_state <= EXECUTE;   -- window closed, so the PAUSE retires
                        ci_pc_advance <= '1';
                    else
                        next_state <= PAUSE_WAIT;
                    end if;

                -- MEMORY_WAIT is the LOAD's rd commit site: the rd write is CARRIED, not suppressed, on every one of the four paths out, which is why the declaration sits at the arm top rather than in a branch.
                -- The value is the live decode; the first assertion at the end of this file polices which encodings may be held here.
                when MEMORY_WAIT =>
                    ci_rd_commit <= reg_write_ctrl;
                    -- Halt/step recognition, above both delivery takes: a halt request is unmaskable, so it is tested before irq_save and std_irq_take.
                    if dbg_halt_take = '1' then
                        next_state <= DBG_SV;
                    elsif irq_save = '1' then
                        next_state <= IRQ_SV;
                    elsif std_irq_take = '1' then
                        -- Standard delivery reuses this check point: irq_save cannot fire in standard mode, where irq_en_eff is masked all-zero and the handler FSM is pinned in IDLE, and std_irq_take is '0' in legacy mode, so the two arms are mutually exclusive by construction.
                        next_state <= MTRAP_SV;
                    elsif isr_ret = '1' then
                        next_state <= IRQ_REST;
                    else
                        next_state <= EXECUTE;
                        ci_pc_advance <= '1';
                    end if;

                -- Wait for the divider. Declaring NO store lanes is load-bearing: the block then drives wen all-ones structurally, rather than the state inheriting the held encoding's live lane strobes.
                when DIV_WAIT =>
                    if alu_done = '1' then
                        next_state <= DIV_DONE;
                        div_start <= '0';
                    else
                        next_state <= DIV_WAIT;
                        div_start <= '1';
                    end if;

                -- The DIV's rd commit site: it CARRIES the live decode through to rd rather than suppressing it, which is why the declaration is reg_write_ctrl and not '0'.
                when DIV_DONE =>
                    ci_pc_advance <= '1';
                    ci_rd_commit  <= reg_write_ctrl;

                    -- Halt/step recognition, above both delivery takes: a halt request is unmaskable, so it is tested before irq_save and std_irq_take.
                    if dbg_halt_take = '1' then
                        next_state <= DBG_SV;
                        ci_pc_advance <= '0';
                    elsif irq_save = '1' then
                        next_state <= IRQ_SV;
                        ci_pc_advance <= '0';
                    elsif std_irq_take = '1' then
                        -- Standard delivery reuses this check point: irq_save cannot fire in standard mode, where irq_en_eff is masked all-zero and the handler FSM is pinned in IDLE, and std_irq_take is '0' in legacy mode, so the two arms are mutually exclusive by construction.
                        next_state <= MTRAP_SV;
                        ci_pc_advance <= '0';
                    -- There is deliberately no isr_ret arm: DIV_DONE is reachable only from DIV_WAIT and holds the dispatching DIV encoding, so isr_ret is statically '0' here.
                    else
                        next_state <= EXECUTE;
                    end if;

                -- FMA rs3 fetch: the rs2 read port is steered to the rs3 index this cycle and fp_rs3_reg is latched at the edge, with the PC frozen and no writeback.
                -- fpu_start is NOT asserted here, only from FPU_WAIT, so every operand register is stable strictly before the first edge at which the unit samples start.
                when FPU_FETCH3 =>
                    next_state <= FPU_WAIT;

                -- Run the multi-cycle FP unit. The DIV_WAIT contract exactly: the PC is frozen, there is no rd commit, the instruction is held, and no store lanes are declared so wen is driven all-ones structurally.
                when FPU_WAIT =>
                    if fpu_done_sig = '1' then
                        next_state <= FPU_DONE;
                    else
                        next_state <= FPU_WAIT;
                    end if;

                -- FP writeback and flags, the DIV_DONE shape exactly: this state CARRIES the live decode through to rd and the fpu result lands in this cycle. Interrupt handling is identical to DIV_DONE's.
                when FPU_DONE =>
                    ci_pc_advance <= '1';
                    ci_rd_commit  <= reg_write_ctrl;

                    -- Halt/step recognition, above both delivery takes: a halt request is unmaskable, so it is tested before irq_save and std_irq_take.
                    if dbg_halt_take = '1' then
                        next_state <= DBG_SV;
                        ci_pc_advance <= '0';
                    elsif irq_save = '1' then
                        next_state <= IRQ_SV;
                        ci_pc_advance <= '0';
                    elsif std_irq_take = '1' then
                        -- Standard delivery reuses this check point: irq_save cannot fire in standard mode, where irq_en_eff is masked all-zero and the handler FSM is pinned in IDLE, and std_irq_take is '0' in legacy mode, so the two arms are mutually exclusive by construction.
                        next_state <= MTRAP_SV;
                        ci_pc_advance <= '0';
                    -- No isr_ret arm, for DIV_DONE's reason: FPU_DONE is reachable only from FPU_WAIT and holds an FP encoding, so isr_ret is statically '0'.
                    else
                        next_state <= EXECUTE;
                    end if;

                -- Save context for an interrupt: the full-word PC push, the one active store declaration outside the data states, ACTIVE-HIGH here because wen is the inverse of ci_st_lanes.
                -- NO rd may be committed in the IRQ dispatch cycles: the instruction mux shows the already-retired interrupted instruction, whose load decode would re-write its rd with garbage, and IRQ_JUMP shows the raw bus word, an arbitrary image writing an arbitrary rd.
                when IRQ_SV =>
                    ci_st_lanes <= "1111";

                    -- Update the stack pointer: the enable comes from the commit block and the data is assigned here, both settling in the same combinational evaluation and landing on the same edge.
                    ci_sp_commit <= '1';
                    sp_write_data <= std_logic_vector(unsigned(stack_pointer) - 4);

                    next_state <= IRQ_JUMP;

                -- Jump to the interrupt vector, loading the IVT entry with no store and no rd commit.
                when IRQ_JUMP =>
                    irq_save_ack <= '1';
                    ci_pc_advance <= '1';
                    next_state <= EXECUTE;

                -- Standard trap entry, the CSR writeback cycle. Shaped on IRQ_SV MINUS every memory effect: no push, no sp touch (a U-mode sp is untrusted, software uses mscratch), no writeback, and no irq_handler handshake, the handler being pinned in IDLE.
                -- The csr_unit writeback rides trap_entry_we, a clk-domain ONE-SHOT of this state, with trap_pc, trap_cause and trap_value derived from held state. trap_flag is NOT raised: a standard trap is RECOVERABLE, unlike TRAP_STATE.
                when MTRAP_SV =>
                    mem_access_instr <= '0';
                    next_state       <= MTRAP_JUMP;

                -- Standard trap entry, the vector cycle: the PC takes mtvec.BASE and the same cycle issues the fetch from there, data_addr falling through to pc_next exactly as at IRQ_JUMP.
                when MTRAP_JUMP =>
                    ci_pc_advance    <= '1';
                    mem_access_instr <= '0';
                    next_state       <= EXECUTE;

                -- MRET: the PC takes mepc and csr_unit pops mstatus (MIE takes MPIE, MPIE takes '1') via the mret_we one-shot. The JALR shape: no memory access, no writeback and no sp touch.
                when MTRAP_RET =>
                    ci_pc_advance    <= '1';
                    mem_access_instr <= '0';
                    next_state       <= EXECUTE;

                /* The three debug-mode states are all the MTRAP_RET/IRQ_JUMP shape: declare ci_pc_advance, hold mem_access_instr low so data_addr falls through to pc_next and the same cycle issues the fetch from the new PC, and declare nothing else.
                   DBG_SV is ONE state where MTRAP_SV is two, because its CSR write rides a one-shot that fires on the FIRST free-clk edge of the state and csr_unit samples dbg_pc at that same edge, so debug_mode and the PC load of DEBUG_ENTRY_ADDR land together.
                   If clk_cpu is gated here, which happens when a DEBUG_ENTRY_ADDR in the shared window stalls its own fetch, the state simply holds and the one-shot still fires exactly once. */
                when DBG_SV =>
                    ci_pc_advance    <= '1';
                    mem_access_instr <= '0';
                    next_state       <= EXECUTE;

                -- Re-entry from an ebreak taken BY DEBUG CODE, identical to DBG_SV minus the strobe: dpc and dcsr.cause must survive, or the debugger loses its own return address.
                when DBG_JUMP =>
                    ci_pc_advance    <= '1';
                    mem_access_instr <= '0';
                    next_state       <= EXECUTE;

                -- DRET: the PC takes dpc, plus the debug_mode clear and the privilege pop in csr_unit via the dbg_ret_we one-shot. It retires exactly as MTRAP_RET does.
                when DBG_RET =>
                    ci_pc_advance    <= '1';
                    mem_access_instr <= '0';
                    next_state       <= EXECUTE;

                -- Restore context from an interrupt. NOTHING may write rd here: the state declares no rd commit, so the block drives it '0' rather than leaving it to the held `iret` encoding's decode.
                when IRQ_REST =>
                    -- Halt/step recognition, above both delivery takes: a halt request is unmaskable, so it is tested before irq_save and std_irq_take.
                    if dbg_halt_take = '1' then
                        next_state <= DBG_SV;
                    elsif irq_save = '1' then
                        -- Nested interrupt. Declaring no store lanes is what makes the block drive wen all-ones here, instead of the held `iret` word's live decode.
                        next_state <= IRQ_SV;
                    elsif std_irq_take = '1' then
                        -- Standard delivery reuses this check point: irq_save cannot fire in standard mode, where irq_en_eff is masked all-zero and the handler FSM is pinned in IDLE, and std_irq_take is '0' in legacy mode, so the two arms are mutually exclusive by construction.
                        next_state <= MTRAP_SV;
                    elsif sleep_cpu = '1' then
                        -- Return to sleep after the interrupt. The sp enable comes from the commit block and the data is assigned here, as at IRQ_SV.
                        next_state <= SLEEPING;
                        ci_sp_commit <= '1';
                        sp_write_data <= std_logic_vector(unsigned(stack_pointer) + 4);
                    else
                        -- Return to normal execution.
                        next_state <= EXECUTE;
                        ci_sp_commit <= '1';
                        sp_write_data <= std_logic_vector(unsigned(stack_pointer) + 4);
                        ci_pc_advance <= '1';
                    end if;

                /* SLEEPING has three exits, in a deliberate priority: irq_save (legacy delivery, masked off in standard mode), std_irq_take (standard delivery, which also serves a WFI sleep, so if the interrupt is takeable it is delivered),
                   and std_wfi_wake, taken ONLY by a WFI-entered sleep when the interrupt is pending and enabled but not takeable, resuming at the instruction after the WFI without entering a handler.
                   Declaring no rd commit and no store lanes is load-bearing here more than anywhere, a sleep lasting an unbounded clock-gated number of cycles: the block then drives rd '0' and wen all-ones rather than the held encoding's decode. The PC is held the same way, by declaring nothing, and only the std_wfi_wake leg advances it: a real wake takes the irq_save leg and must NOT advance the PC, which is the return address IRQ_SV is about to push. */
                when SLEEPING =>

                    -- Halt/step recognition, above both delivery takes: a halt request is unmaskable, so it is tested before irq_save and std_irq_take.
                    if dbg_halt_take = '1' then
                        next_state <= DBG_SV;
                    elsif irq_save = '1' then
                        next_state <= IRQ_SV;
                    elsif std_irq_take = '1' then
                        -- Standard delivery reuses this check point: irq_save cannot fire in standard mode, where irq_en_eff is masked all-zero and the handler FSM is pinned in IDLE, and std_irq_take is '0' in legacy mode, so the two arms are mutually exclusive by construction.
                        next_state <= MTRAP_SV;
                    elsif std_wfi_wake = '1' then
                        -- WFI resumption, unreachable for an extinguish-entered sleep on any build, where wfi_slept is '0'.
                        next_state <= EXECUTE;
                        ci_pc_advance <= '1';
                    else
                        next_state <= SLEEPING;
                    end if;

                /* Zawrs wait-on-reservation-set: stall with the PC frozen, the hint not having retired, while clk_cpu keeps running and wrs_wake is polled. On any wake the hint retires like a nop.
                   If the wake was a pending enabled interrupt, the ordinary EXECUTE path then takes it with the return PC set to the instruction after the wrs, a WRS being neither a trap nor a change of architectural state.
                   It deliberately does NOT set sleep_cpu, so an interrupt taken here does not leave the hart in the return-to-sleep contract. */
                when WRS_WAIT =>
                    mem_access_instr <= '0';
                    if wrs_wake = '1' then
                        next_state <= EXECUTE;
                        ci_pc_advance <= '1';
                    else
                        next_state <= WRS_WAIT;
                    end if;

                -- The terminal trap state. Declaring NO store lanes is what keeps it silent: TRAP_STATE is absent from the instr_curr hold list, so instr_curr decodes the live bus word, and a store encoding there would commit a REAL store at data_addr on every cycle of this self-loop.
                -- The halt recognition below is the only exit, and the only recognition site that is not also an interrupt site: a wedged hart is the highest-value halt target a debugger has. With ENABLE_DEBUG off this collapses to the unconditional self-loop.
                when TRAP_STATE =>
                    if dbg_halt_take = '1' then
                        next_state <= DBG_SV;
                    else
                        next_state <= TRAP_STATE;
                    end if;
                    trap_flag <= '1';

                -- The illegal-encoding recovery arm. It looks unreachable, but the state register holds more bits than the type has values, so a corrupted encoding lands here; never hold a commit signal in it, or a stale regfile write commits and a latch is inferred.
                -- Declaring no rd commit and no store lanes gives '0' and all-ones by construction; the PC advance is genuine and is declared.
                when others =>
                    next_state <= EXECUTE;
                    ci_pc_advance <= '1';
            end case;

            /* THE COMMIT BLOCK: the ONLY assignment site for the four owned nets outside the reset branch, and unconditional, so what each state commits is decided entirely by the ci_* intent it declared in its own arm.
               A state that declares nothing commits nothing and holds the PC, so there is nowhere left to forget an explicit rd-commit suppression. It sits INSIDE the else branch on purpose: the reset branch drives its own four values and is out of reach.
               Intent is GATED BY PERMISSION: a state may commit only what its table allows, and anything else is squashed here and shouted about by s3_perm_assert_proc. pc_advance is deliberately ungated. */
            reg_write_dp <= ci_rd_commit  and rd_commit_allowed(current_state);
            sp_write_en  <= ci_sp_commit  and sp_commit_allowed(current_state);
            wen          <= not (ci_st_lanes and st_commit_allowed(current_state));
            pc_en        <= ci_pc_advance;
        end if;
    end process;

    /* COMMIT-PERMISSION ASSERTIONS: the masks made loud, since a mask that silently squashes is an instrument that hides its own findings. Every squash is an assertion failure naming the signal and the state.
       They say nothing about whether a PERMITTED commit carries the right VALUE; the f4 assertions below police a different property again, which encoding may be held when a permitted commit happens, and neither set subsumes the other.
       CLOCKED, not concurrent, because a concurrent assertion samples mid-settle and fires on ordinary traffic. Scope is post-reset on every rising clk_cpu edge, the resetn qualifier being load-bearing since the reset branch drives values the block cannot reach, and clk_cpu is GATED, so a stalled cycle is structurally unchecked. */
    s3_perm_assert_proc: process(clk_cpu)
    begin
        if rising_edge(clk_cpu) then
            assert not (resetn = '1' and ci_rd_commit = '1'
                        and rd_commit_allowed(current_state) = '0')
                report "S3 PERM: rd commit DECLARED but NOT PERMITTED in state "
                       & cpu_state'image(current_state)
                severity error;
            assert not (resetn = '1' and ci_sp_commit = '1'
                        and sp_commit_allowed(current_state) = '0')
                report "S3 PERM: sp commit DECLARED but NOT PERMITTED in state "
                       & cpu_state'image(current_state)
                severity error;
            assert not (resetn = '1'
                        and (ci_st_lanes and not st_commit_allowed(current_state)) /= "0000")
                report "S3 PERM: store lanes DECLARED but NOT PERMITTED in state "
                       & cpu_state'image(current_state)
                severity error;
        end if;
    end process;

    -- Sleep and wake control: track the CPU sleep state, driven by the custom sleep and wake instructions.
    process(clk, resetn)
    begin
        if resetn = '0' then
            sleep_cpu <= '0';
        elsif rising_edge(clk) then
            /* THE WHOLE `if` is qualified by dec_dispatch, not just the set arm: this flop is on the FREE-RUNNING clk while sleep_rq and wake_rq are pure decodes of instr_curr, so it would otherwise update in every state that holds a stale or raw word.
               Both directions leak: an `extinguish` encoding on the bus sets sleep_cpu behind the FSM's back and IRQ_REST then sends the hart to SLEEPING instead of resuming, a hang for a word the hart never executed, while an `ignite` encoding clears it, so a legitimately parked hart resumes instead of re-parking, breaking a park contract that works by NOT clearing the flop.
               Nothing legitimate is lost, every real sleep or wake dispatch being an EXECUTE cycle, and dec_dispatch subsumes dec_squash, so the trap-entry and PMP park-word rules are preserved exactly. */
            if dec_dispatch = '1' then
                if wake_rq = '1' then
                    sleep_cpu <= '0';
                elsif sleep_rq = '1' then
                    sleep_cpu <= '1';
                end if;
            end if;
        end if;
    end process;

    /* Zawrs wake logic. wrs.nto and wrs.sto stall the hart in WRS_WAIT, which unlike WFI and extinguish does NOT gate clk_cpu and does NOT touch sleep_cpu, so the return-to-sleep contract is untouched and the stall is invisible to the sleep machinery.
       The core issues no bus transaction while waiting. Any one wake source suffices: the reservation was invalidated by a foreign committed store; an interrupt is pending, taken from the RAW enable-agnostic irq_vector so it fires even for a source that would not be delivered;
       or, for wrs.sto only, the short timeout elapsed. */
    wrs_int_pending <= '1' when irq_vector /= (irq_vector'range => '0') else '0';
    wrs_timeout     <= '1' when (wrs_is_sto = '1' and wrs_cnt = WRS_TIMEOUT_CYCLES) else '0';
    wrs_wake        <= '1' when (resv_valid_ext = '0' or wrs_int_pending = '1' or wrs_timeout = '1') else '0';

    -- Timeout counter: runs on clk_cpu only while stalled and is cleared whenever the hart is not in WRS_WAIT.
    -- It saturates at WRS_TIMEOUT_CYCLES, which wrs.nto never reads, and shares mcycle's clock domain, so the stall is measurable through mcycle.
    wrs_timeout_proc: process(clk_cpu, resetn)
    begin
        if resetn = '0' then
            wrs_cnt <= 0;
            wrs_is_sto <= '0';
        elsif rising_edge(clk_cpu) then
            if current_state = WRS_WAIT then
                -- Stalled: freeze the sto flag, instr_curr no longer holding the wrs encoding here, and advance the timeout counter.
                if wrs_cnt /= WRS_TIMEOUT_CYCLES then
                    wrs_cnt <= wrs_cnt + 1;
                end if;
            else
                wrs_cnt <= 0;
                -- Capture the pending WRS variant each pre-entry cycle; the last non-WRS_WAIT cycle before entry is the EXECUTE decode of the wrs, where wrs_sto is valid.
                wrs_is_sto <= wrs_sto;
            end if;
        end if;
    end process;

    -- Controller instance.
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
            ENABLE_PMP      => ENABLE_PMP,
            ENABLE_DEBUG    => ENABLE_DEBUG
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
            -- The standard WFI decode out, and the three U-mode decode inputs straight from csr_unit.
            wfi_op           => wfi_op,
            -- The DRET decode out, and the debug-mode decode input from csr_unit, the same route priv_m takes and for the same reason.
            dret_op          => dret_op,
            debug_mode       => debug_mode,
            priv_m           => trap_priv_mode,
            status_tw        => trap_status_tw,
            mcounteren_bits  => trap_mcounteren,
            -- The SAME csr_rs1_zero csr_unit consumes for its write enable, so the decode's read-only-CSR trap and the write path can never disagree about what counts as a write.
            csr_rs1_zero     => csr_rs1_zero,
            -- The R-type rs2 field is zero, the one bit maindec needs to tell Zbb `zext.h rd,rs1` apart from Zbkb `pack rd,rs1,rs2`, which share the same funct7, funct3 and opcode.
            rs2_zero         => rs2_zero,
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

    -- Signal the IRQ handler when the core is ready to process an interrupt.
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



    /* THE DIVIDE DISPATCH QUALIFIER. The ALU's divide FSM must arm from this, never from a bare combinational decode of alu_control: alu_control decodes instr_curr, which in the split-fetch bubble, IRQ_SV, IRQ_JUMP and TRAP_STATE is not the instruction being dispatched.
       A divide-looking encoding in any of those arms the FSM, which latches the PREVIOUS divide's signed and remainder selects and sticks in its wait state, so the next real divide executes under the wrong opcode's selects.
       `next_state = DIV_WAIT` IS the dispatch, DIV_WAIT being reachable only from the EXECUTE is_div_op arms, so the term is exact by construction; `current_state = EXECUTE` narrows it to the dispatch cycle itself. Not a loop: it feeds only the ALU FSM's clocked arm. */
    div_dispatch <= '1' when (current_state = EXECUTE and next_state = DIV_WAIT) else '0';

    alu_control_dp <=   "0001011" when (current_state = AMO_READ or current_state = AMO_WRITE) else
                        "0001010" when (current_state = SC_CHECK) else -- the ALU passes B
                        alu_control;

    -- Component instantiations.
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
            ENABLE_ZFINX    => ENABLE_ZFINX,
            TRACE_ENABLE    => TRACE_ENABLE
        )
        port map (
            clk         => clk_cpu,
            resetn      => resetn,
            pc          => pc,
            pc_plus_4   => pc_link,
            result_src  => dp_result_src,  -- the Zcmt jalt-link override ("010"), otherwise the controller's value
            pc_src      => pc_src,
            ALU_src     => ALU_src,
            reg_write   => reg_write_dp,
            jalr        => jalr,
            imm_src     => imm_src,
            funct3      => instr_curr(14 downto 12),
            mask        => mask,
            alu_control => alu_control_dp,
            div_start   => div_start,
            div_dispatch => div_dispatch,
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
            -- Tracer taps: the regfile a3 and wd3 nets, read-only.
            trc_rd_addr => trc_rd_addr,
            trc_rd_data => trc_rd_data,
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
            -- irq_en_eff equals irq_en in legacy mode and on any OFF build, and is forced ALL-ZERO in standard mode so this FSM never leaves IDLE.
            -- An `iret` executed in standard mode is therefore silently ignored, isr_ret only ever being acted on from WAIT_EOI: unspecified but bounded, and it must not wedge.
            irq_en          => irq_en_eff,
            irq_pri         => irq_priority,
            irq_recursion_en => irq_recursion_en,
            irq_active      => irq_active,
            isr_ret         => isr_ret_eff,   -- gated by the trap-entry squash
            irq_save        => irq_save,
            irq_save_ack    => irq_save_ack,
            irq_restore     => irq_restore,
            irq_restore_ack => irq_restore_ack,
            ivt_jump        => ivt_jump,
            ivt_entry       => ivt_entry
        );

    -- The decompressor only exists when the C extension is enabled.
    -- Without it, instr_decomp is tied to all-zeros, and opcode "0000000" is not in valid_opcode, so any 16-bit encoding reaching decode traps as an illegal instruction; the EXECUTE-state misaligned-PC check catches the halfword-aligned fetch case before it gets this far.
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
    -- The rs1/uimm FIELD of the CSR instruction, from the same instruction source as csr_addr; for the immediate forms instr(19:15) IS uimm.
    -- It feeds csr_unit's write-form rule: CSRRS and CSRRC with rs1=x0, and CSRRSI and CSRRCI with uimm=0, must not assert the write enable.
    csr_rs1_zero <= '1' when instr_curr(19 downto 15) = "00000" else '0';
    -- The R-type rs2 FIELD is zero. Same instruction source as csr_addr and csr_rs1_zero, so the decode cannot disagree with itself about which instruction it is looking at.
    -- Consumed ONLY by maindec's ZEXT.H legality row: `zext.h rd,rs1` and `pack rd,rs1,x0` are one encoding, so rs2 is the only field separating a legal zext.h from an unimplemented pack. A decompressed c.zext.h arrives with that field explicitly zero, so the compressed form stays legal.
    rs2_zero <= '1' when instr_curr(24 downto 20) = "00000" else '0';

    -- Zihpm event levels. mem_ready is the arbiter back-pressure, where '0' means a pending shared request has not yet been granted and completed.
    hpm_ev_stall <= not mem_ready;
    hpm_ev_sleep <= '1' when (current_state = SLEEPING or sleep = '1') else '0';
    -- The "trap entries taken" event counts ENTRIES, so MTRAP_SV belongs and MTRAP_JUMP and MTRAP_RET do not, mirroring IRQ_JUMP and IRQ_REST: one entry counts as one cycle.
    hpm_ev_trap  <= '1' when (current_state = IRQ_SV or current_state = TRAP_STATE
                              or current_state = MTRAP_SV) else '0';

    -- Tap the three standard interrupt levels for the mip mirror. The indices are MemoryMap slot numbers, so the slice is guarded for any instantiation whose NUM_IRQS is smaller than the meip slot.
    -- vesta's own generic default is 16, and an out-of-range slice is an elaboration error, not a warning.
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
            PMP_ENTRIES       => PMP_ENTRIES,
            ENABLE_DEBUG      => ENABLE_DEBUG,
            TRACE_ENABLE      => TRACE_ENABLE
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
            csr_valid      => csr_valid_eff,   -- qualified by dec_dispatch
            csr_read_data  => csr_rdata,
            inst_retired   => inst_retired,
            ev_bus_stall   => hpm_ev_stall,
            ev_sleep       => hpm_ev_sleep,
            ev_trap_entry  => hpm_ev_trap,

            -- Trap-CSR interface, driven by the MTRAP_SV and MTRAP_RET states.
            -- trap_entry_we and mret_we are clk-domain ONE-SHOTS, csr_unit being on the free-running clk and the FSM on the gated clk_cpu; see gen_trapcsr_wb.
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

            -- U-mode exports; trap_priv_mode is stuck '1' (M) unless ENABLE_UMODE, which is what folds every U-mode decode restriction out of the other builds.
            priv_mode      => trap_priv_mode,
            status_tw      => trap_status_tw,
            mcounteren_bits => trap_mcounteren,

            -- The CSR write-form qualifier in, the effective data-access privilege out, which the PMP data-side check consumes.
            csr_rs1_zero   => csr_rs1_zero,
            data_priv_m    => eff_data_priv_m,
            mret_priv_m    => mret_priv_m,   -- the MRET return privilege, for the fetch check

            -- Debug-mode interface: the two strobes are the gen_debug one-shots, and everything coming back is STATE that vesta's FSM, its clock gate and, through the controller, maindec consume.
            dbg_entry_we   => dbg_entry_we_sig,
            dbg_pc         => dbg_pc_val,
            dbg_cause      => dbg_cause_r,
            dbg_ret_we     => dbg_ret_we_sig,
            debug_mode     => debug_mode,
            dcsr_ebreakm   => dcsr_ebreakm,
            dcsr_ebreaku   => dcsr_ebreaku,
            dcsr_step      => dcsr_step,
            dpc_value      => dbg_dpc_value,

            -- The pmpcfg and pmpaddr bank, flattened. Both are all-zero when ENABLE_PMP is false, nothing ever writing the flops, which together with gen_pmp not instantiating pmp_unit is the whole OFF fold.
            pmp_cfg_flat   => pmp_cfg_flat_sig,
            pmp_addr_flat  => pmp_addr_flat_sig,

            -- Tracer exports, read-only. csr_commit_we is generated INSIDE csr_unit and asserted only when a write-case arm actually stores; a vesta-level reproduction of csr_write_en would log writes that never committed.
            csr_commit_we  => csr_commit_we,
            csr_commit_val => csr_commit_val,
            mstatus_value  => mstatus_value,
            fflags_value   => fflags_value
        );

    -- The lockstep tracer (TRACE_ENABLE only) is a PURE OBSERVER: vesta_tracer has no output ports, so it cannot affect the design even in an ON build, and elaboration removes the whole block when TRACE_ENABLE is false.
    -- THE STATE-ORDINAL CONTRACT: cpu_state cannot cross a port boundary in VHDL-93, so the FSM state is passed as an ordinal and vesta_tracer's ST_* constants MUST match the type's declaration order. Adding, removing or reordering a state means updating vesta_tracer.vhd.
    gen_trace: if TRACE_ENABLE generate
        signal trc_state      : natural range 0 to 63;
        signal trc_next_state : natural range 0 to 63;
    begin
        trc_state      <= cpu_state'pos(current_state);
        trc_next_state <= cpu_state'pos(next_state);

        tracer_inst: vesta_tracer
            generic map (
                TRACE_FILE        => TRACE_FILE,
                ENABLE_PMP        => ENABLE_PMP,
                ENABLE_COMPRESSED => ENABLE_COMPRESSED,
                -- THE ORDINAL-COUNT ASSERT: cpu_state cannot cross a port boundary, but its CARDINALITY can, and vesta_tracer compares it against its own ST_COUNT and FAILS AT ELABORATION on a mismatch.
                -- It catches an add or a remove, and it does NOT catch a reorder at constant count.
                STATE_COUNT       => cpu_state'pos(cpu_state'high) + 1
            )
            port map (
                clk_cpu          => clk_cpu,
                resetn           => resetn,
                hart_id          => hart_id,
                state            => trc_state,
                next_state       => trc_next_state,
                pc               => pc,
                instr            => instr,
                instr_curr       => instr_curr,
                instr_lower_half => instr_lower_half,
                quadrant_upper   => quadrant_upper,
                quadrant_lower   => quadrant_lower,
                -- split_ready, not repeat_if: the tracer classifies the three half-word-aligned shapes from this port, and the fetch-ahead dispatch is the SAME shape as a bubble completion.
                -- Every tracer term that reads quadrant_upper is qualified by this port being '0', so the half-word that quadrant_upper describes under the fetch-ahead is never consulted there.
                repeat_if        => split_ready,
                reg_write        => reg_write_dp,
                rd_addr          => trc_rd_addr,
                rd_data          => trc_rd_data,
                sp_write_en      => sp_write_en,
                sp_write_data    => sp_write_data,
                stack_pointer    => stack_pointer,
                data_addr        => data_addr,
                wen              => wen,
                write_data       => write_data,
                mem_access_instr => mem_access_instr,
                funct3           => instr_curr(14 downto 12),
                -- sc_fail_ext is an EXISTING vesta input port, so reading it here creates no signal and no logic.
                -- Its component declaration shares a line with funct3 on purpose: the synthesiser derives internal net names from the SOURCE LINE of the expression that creates them, so inserting a line above the last such expression renumbers hundreds of nets and makes a netlist A/B unreadable. Below that point, extra lines are free.
                sc_fail_ext      => sc_fail_ext,
                csr_addr         => csr_addr,
                csr_commit_we    => csr_commit_we,
                csr_commit_val   => csr_commit_val,
                mstatus_value    => mstatus_value,
                fflags_value     => fflags_value,
                -- fp_flags_we and fp_flags_val are EXISTING vesta signals already wired to csr_unit, so reading them creates no logic; their component declaration shares a line for the net-naming reason given above sc_fail_ext.
                -- The tracer needs BOTH rather than reading the CSR back, because the committed fflags is the OR of the two on THIS edge, and a read on the next edge is wrong as soon as an instruction writes fflags in between.
                fp_flags_we      => fp_flags_we,
                fp_flags_val     => fp_flags_val,
                trap             => trap,
                ecall_op         => ecall_op,
                ebreak_op        => ebreak_op,
                mret_op          => mret_op,
                isr_ret          => isr_ret,
                pmp_f_deny_r     => pmp_f_deny_r,
                pmp_d_deny       => pmp_d_deny,
                trap_pc_val      => trap_pc_val,
                trap_cause_val   => trap_cause_val,
                trap_value_val   => trap_value_val,
                mtrap_disp_int   => mtrap_disp_int,
                mtrap_disp_code  => mtrap_disp_code,
                ivt_entry        => ivt_entry
            );
    end generate;

    /* DESIGN ASSERTIONS: the decode coincidences, made checked. Each is of the form "this is correct only because two files happen to agree, and nothing checks that they do", and the fix for a coincidence is to make it FAIL LOUDLY, not to remove the mechanism.
       CLOCKED, NOT CONCURRENT, and that is load-bearing: a concurrent assertion re-evaluates on every delta in which an operand moves, so it samples the combinational cone MID-SETTLE and fires on one-delta-stale decodes during ordinary traffic. A rising_edge sample reads the settled pre-edge values, which is also the more faithful property.
       SEVERITY error ABORTS THE SIMULATION in this environment, deliberately, the failure mode to design against being ignored rather than disruptive: if one fires, treat it as a FINDING and fix the arm it points at, never tune the assertion to fit the build. Simulation-only by construction, an assertion driving no signal, and they compile into every configuration. */
    f4_assert_proc: process(clk_cpu)
    begin
        if rising_edge(clk_cpu) then

            /* (1) MEMORY_WAIT is the LOAD's commit site, so every other encoding that can be held here (store, cbo.zero, cm.push, cm.pop, cm.mv and the `iret`) must decode reg_write='0' in maindec.
                   If one ever does not it writes a garbage rd, and nothing structural stops it, MEMORY_WAIT being a legitimate rd commit site whose permission mask allows the write.
                   The masks police WHICH STATE may commit; this polices WHICH ENCODING may be held when it does. */
            assert not (current_state = MEMORY_WAIT and reg_write_dp = '1'
                        and instr_curr(6 downto 0) /= I_LOAD_OPCODE)
                report "F4 ASSERT: reg_write_dp asserted in MEMORY_WAIT for a non-LOAD encoding"
                severity error;

            -- (2) DIV_DONE is the DIV/DIVU/REM/REMU commit site; the held encoding must still be the div that dispatched us here.
            assert not (current_state = DIV_DONE and reg_write_dp = '1'
                        and is_div_op = '0')
                report "F4 ASSERT: reg_write_dp asserted in DIV_DONE for a non-DIV encoding"
                severity error;

            -- (3) FPU_DONE is the multi-cycle and FMA FP commit site; a single-cycle FP op retires in EXECUTE and never reaches this state.
            --     Unreachable unless ENABLE_ZFINX is set, so this one guards the knobs-on configurations only.
            assert not (current_state = FPU_DONE and reg_write_dp = '1'
                        and is_fp_multicycle = '0' and is_fp_fma = '0')
                report "F4 ASSERT: reg_write_dp asserted in FPU_DONE for a non-multicycle-FP encoding"
                severity error;

            /* (4) The two COMPRESSED EXECUTE arms have NO lr_op, sc_op, amo_op, cboz_op, fence_op, wfi_op, wrs_op or is_fp_* branches at all, which is safe only because no compressed encoding decompresses to any of them, a property of c_dec that nothing in this file enforces.
                   If a future Zc* extension ever emits one, the instruction would silently retire as a plain ALU op with its memory, atomic or FP side effect simply not performed.
                   The shape terms are spelled out rather than reusing is_compressed, which is an inferred latch: they are written in terms of pc, split_ready and the quadrant bits, so no latched FSM output is read. */
            assert not (current_state = EXECUTE
                        and ((pc(1) = '1' and split_ready = '0' and quadrant_upper /= "11")
                             or (pc(1) = '0' and quadrant_lower /= "11"))
                        and (lr_op = '1' or sc_op = '1' or amo_op = '1' or cboz_op = '1'
                             or fence_op = '1' or wfi_op = '1' or wrs_op = '1'
                             or is_fp_singlecycle = '1' or is_fp_multicycle = '1'
                             or is_fp_fma = '1'))
                report "F4 ASSERT: c_dec emitted a sequencer/FP encoding -- shapes B/C have no arm for it"
                severity error;

            /* (5) THE FETCH-AHEAD INVARIANT, in the one form that is cheap to check: in an EXECUTE cycle if_ahead implies a HALF-WORD-ALIGNED pc.
                   Both arming shapes advance the PC to a half-word-aligned address by construction, pc+2 from an even pc and pc+4 from an odd one, and only a half-word-aligned pc can straddle.
                   Were it ever set at an even pc the decode would assemble instr(15 downto 0) with a stale instr_lower_half and dispatch an encoding that is in no way the instruction at pc, silently and with a full commit.
                   MEMORY_WAIT is deliberately outside the scope, and its exclusion is the mechanism rather than an exemption: a load or store does not advance the PC in its own dispatch cycle, so the flag armed there is carried for one cycle alongside a pc that still names the memory instruction, which for a compressed load is word aligned. */
            assert not (resetn = '1' and current_state = EXECUTE and if_ahead = '1' and pc(1) = '0')
                report "IF-AHEAD ASSERT: if_ahead set at a word-aligned pc in EXECUTE"
                severity error;

            /* (6) THE TWO HALF-HOLDING PATHS ARE MUTUALLY EXCLUSIVE, which split_ready's definition as a plain OR quietly assumes.
                   The bubble cycle retires nothing and the fetch-ahead requires a dispatch, so no cycle can arm both, and the completion cycle asserts clr_repeat_if whichever path reached it.
                   Were both ever set, clr_repeat_if would clear only one of them and the survivor would make the NEXT half-word-aligned pc decode as a split completion, assembling a stale instr_lower_half into an instruction that is in no way the one at pc. */
            assert not (resetn = '1' and if_ahead = '1' and repeat_if = '1')
                report "IF-AHEAD ASSERT: if_ahead and repeat_if both set"
                severity error;

            /* (7) THE CLEAR-BY-CONSTRUCTION CLAIM, made checked. if_ahead is armed only for the two sequential retire paths, and every other trajectory re-drives it from if_ahead_req, which is '0' outside them.
                   So the flag must never be observed alive in any state but the EXECUTE that consumes it and the MEMORY_WAIT that carries it across a data access.
                   This is the one property that covers the trap, interrupt, sleep and debug trajectories together, without naming any of them: a state that could reach EXECUTE with a stale half-word held would fire here first, in whatever state it passed through.
                   It is the whole safety argument for the divert cases, which are otherwise reachable only from stimulus this core's benches do not generate. */
            assert not (resetn = '1' and if_ahead = '1'
                        and current_state /= EXECUTE and current_state /= MEMORY_WAIT)
                report "IF-AHEAD ASSERT: if_ahead alive outside EXECUTE and MEMORY_WAIT"
                severity error;

        end if;
    end process;

end architecture;


