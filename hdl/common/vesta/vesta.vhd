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
        PMP_ENTRIES       : integer := 16;     -- P3 (PMP entry count {8,16}): consumed from phase P3 on; scaffolded P0
        -- D1 (2026-08-05) core-side DEBUG MODE: dcsr/dpc/dscratch0/1, DRET,
        -- halt request + halt-on-reset, ebreak-to-debug and single-step.
        -- DEFAULT FALSE, and it must stay false at EVERY declaration site --
        -- policed by tools/python/check_entity_defaults.py, because the
        -- hart_tile-vs-vesta default DISAGREEMENT that already exists for
        -- ENABLE_TRAPCSR is exactly how the frozen Argus snapshot ran
        -- TRAPCSR-ON for two days with no way to say so (F-K7-4). A debug port
        -- silently enabled on a snapshot is an area and attack-surface
        -- surprise, not a convenience (method rule 15).
        -- REQUIRES ENABLE_TRAPCSR -- see the concurrent assert below.
        ENABLE_DEBUG      : boolean := false;
        -- Where a debug entry lands. FROZEN at 0xBE00 (d1_spec.md 1, amended
        -- R-D1-1(2)): the first free 256-byte slot in the TCM ISR bank above
        -- .isr_eis @0xBD00, below the 0xBF00-0xBFEF headroom and the stack top
        -- at 0xBFF0, and inside the MP_STAGE_IMAGE window so a tile gets its
        -- debug stub from the ordinary image copy. 0xBB00 was REJECTED on
        -- purpose: it is the parking target of every unused IVT slot, so a stub
        -- there would also be entered by a stray interrupt, and a tripwire two
        -- mechanisms can trip is not a tripwire. It is a GENERIC and not a
        -- constant so a bench can re-aim it (hdl/common/tb/dbg_iface_tb.vhd
        -- points it into its own responder window); the shipped chips take
        -- this default, so MCU.vhd does not name it.
        DEBUG_ENTRY_ADDR  : std_logic_vector(XLEN-1 downto 0) := x"0000BE00";
        -- V1 (Spike lockstep co-simulation): instantiate the read-only
        -- vesta_tracer. Following the ENABLE_* scaffolding idiom exactly --
        -- default FALSE, so `gen_trace` elaborates nothing and the netlist,
        -- the cell lists and the full regression are untouched. The tracer has
        -- no output ports and drives no signal; its only effect is a text file
        -- named <TRACE_FILE>_h<hart>.trace (the hart suffix is appended at
        -- runtime because a generic cannot depend on the hart_id PORT).
        -- Spec: ~/vesta_docs/lockstep/v1_retire_enumeration.md rev 2.
        TRACE_ENABLE      : boolean := false;
        TRACE_FILE        : string  := "vesta_trace"
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

        -- ------------------------------------------------------------------
        -- D1 DEBUG INTERFACE (all inert when ENABLE_DEBUG = false).
        -- Three LEVELS, no handshake, no resumereq: resume at D1 is the
        -- exclusive job of `dret` executed by debug code, and DM-side
        -- sequencing is D2's.
        --   dbg_haltreq      : raise to halt. UNMASKABLE -- neither
        --                      mstatus.MIE nor mtrapctl.LEGACY qualifies it.
        --                      A debugger drops it once dbg_halted reads '1';
        --                      leaving it high would re-halt the hart the
        --                      instant its `dret` retired, forever.
        --   dbg_resethaltreq : hold across reset release to halt before the
        --                      hart runs anything.
        --   dbg_halted       : '1' while the hart is IN DEBUG MODE. It is a
        --                      STATE, not a level follower -- it stays high
        --                      after dbg_haltreq drops.
        -- BOTH INPUTS DEFAULT '0', and that direction is the fail-safe one
        -- (method rule 15): an unconnected instantiation -- which is every
        -- MCU-level tile at D1, since no Debug Module exists yet to drive
        -- them -- requests nothing and halts nothing. A '1' default would halt
        -- the whole chip out of reset.
        -- ------------------------------------------------------------------
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
            -- P1 standard SYSTEM/PRIV decode ('0' unless ENABLE_TRAPCSR)
            ecall_op         : out std_logic;
            ebreak_op        : out std_logic;
            mret_op          : out std_logic;
            -- P2 WFI decode + the U-mode decode inputs (inert defaults)
            wfi_op           : out std_logic;
            -- D1 DRET decode + the debug-mode decode input (default '0' = denied)
            dret_op          : out std_logic;
            debug_mode       : in  std_logic := '0';
            priv_m           : in  std_logic := '1';
            status_tw        : in  std_logic := '0';
            mcounteren_bits  : in  std_logic_vector(4 downto 0) := "00000";
            -- F10 (fix pass W4): CSR rs1/uimm-field-is-zero (read-only form)
            csr_rs1_zero     : in  std_logic := '1';
            -- F-BV1 (K5): R-type rs2-field-is-zero (qualifies the ZEXT.H row)
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
            -- V1 lockstep tracer taps (read-only; the regfile a3/wd3 nets)
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
            PMP_ENTRIES       : integer := 16;
            -- D1 debug-mode CSR file (dcsr/dpc/dscratch0/1 + debug_mode)
            ENABLE_DEBUG      : boolean := false;
            TRACE_ENABLE      : boolean := false
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
            mcounteren_bits : out std_logic_vector(4 downto 0);

            -- P3-entry interface (p3_kickoff.md 3): CSR write-form qualifier
            -- in, effective data-access privilege (mstatus.MPRV redirect) out
            csr_rs1_zero   : in  std_logic := '0';
            data_priv_m    : out std_logic;
            -- P3 red-team F1: the MRET return privilege (MPP mapped)
            mret_priv_m    : out std_logic;

            -- D1 debug-mode interface (inert defaults; see csr_unit.vhd)
            dbg_entry_we   : in  std_logic := '0';
            dbg_pc         : in  std_logic_vector(XLEN-1 downto 0) := (others => '0');
            dbg_cause      : in  std_logic_vector(2 downto 0) := (others => '0');
            dbg_ret_we     : in  std_logic := '0';
            debug_mode     : out std_logic;
            dcsr_ebreakm   : out std_logic;
            dcsr_ebreaku   : out std_logic;
            dcsr_step      : out std_logic;
            dpc_value      : out std_logic_vector(XLEN-1 downto 0);

            -- P3 PMP bank exports (p0_specs.md §4.1); all-zero when ENABLE_PMP
            -- is false.
            pmp_cfg_flat   : out std_logic_vector(127 downto 0);
            pmp_addr_flat  : out std_logic_vector(479 downto 0);
            -- V1 lockstep tracer exports (read-only)
            csr_commit_we  : out std_logic;
            csr_commit_val : out std_logic_vector(XLEN-1 downto 0);
            mstatus_value  : out std_logic_vector(XLEN-1 downto 0);
            fflags_value   : out std_logic_vector(XLEN-1 downto 0)
        );
    end component;

    -- P3 (PMP/Smpmp): the pure-combinational match / priority / permission
    -- decoder. Ports and semantics are FROZEN by p0_specs.md §4.1; the bank
    -- STORAGE lives in csr_unit and every CHECK POINT lives in this file.
    -- Instantiated ONLY inside `gen_pmp: if ENABLE_PMP generate`, so an OFF
    -- build's hand-maintained cell lists and netlist are untouched.
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

    -- ==========================================================
    -- V1 lockstep tracer (TRACE_ENABLE only). A COMPONENT declaration,
    -- deliberately NOT direct entity instantiation: `entity work.x` binds at
    -- ANALYSIS, so it hard-errors (*E,SELLIB) in every one of the ~16 cell
    -- lists that compile this file without vesta_tracer.vhd. A component
    -- binds at ELABORATION and is therefore skipped entirely inside a
    -- statically-false generate -- which is exactly why the pmp_unit
    -- precedent uses this idiom. Only the flow that actually turns tracing
    -- ON needs vesta_tracer.vhd in its file list.
    -- ==========================================================
    component vesta_tracer
        generic (
            TRACE_FILE        : string  := "vesta_trace";
            ENABLE_PMP        : boolean := false;
            ENABLE_COMPRESSED : boolean := true;
            TRAPSTORE_LIMIT   : natural := 8;
            -- D1: cpu_state'pos(cpu_state'high)+1, checked against ST_COUNT
            STATE_COUNT       : natural := 0
        );
        port (
            clk_cpu          : in std_logic;                       -- the GATED core clock
            resetn           : in std_logic;
            hart_id          : in std_logic_vector(XLEN-1 downto 0);
            state            : in natural;                         -- cpu_state'pos(current_state)
            next_state       : in natural;                         -- cpu_state'pos(next_state)
            pc               : in std_logic_vector(XLEN-1 downto 0);
            instr            : in std_logic_vector(ILEN-1 downto 0);  -- = read_data (vesta:951)
            instr_curr       : in std_logic_vector(ILEN-1 downto 0);  -- decoded/held (vesta:1328)
            instr_lower_half : in std_logic_vector(15 downto 0);
            quadrant_upper   : in std_logic_vector(1 downto 0);
            quadrant_lower   : in std_logic_vector(1 downto 0);
            repeat_if        : in std_logic;
            reg_write        : in std_logic;                        -- reg_write_dp -> we3
            rd_addr          : in std_logic_vector(4 downto 0);     -- rf_a3_addr   -> a3
            rd_data          : in std_logic_vector(XLEN-1 downto 0); -- Result      -> wd3
            sp_write_en      : in std_logic;
            sp_write_data    : in std_logic_vector(XLEN-1 downto 0);
            stack_pointer    : in std_logic_vector(XLEN-1 downto 0);
            data_addr        : in std_logic_vector(XLEN-1 downto 0);
            wen              : in std_logic_vector(XLEN_BYTES-1 downto 0);  -- ACTIVE LOW per byte
            write_data       : in std_logic_vector(XLEN-1 downto 0);
            mem_access_instr : in std_logic;
            funct3           : in std_logic_vector(2 downto 0); sc_fail_ext : in std_logic := '0';  -- instr_curr(14:12); A16/T2 verdict SHARES THIS LINE ON PURPOSE -- see the port map
            csr_addr         : in std_logic_vector(11 downto 0);
            csr_commit_we    : in std_logic;
            csr_commit_val   : in std_logic_vector(XLEN-1 downto 0);
            mstatus_value    : in std_logic_vector(XLEN-1 downto 0); -- for MTRAP_RET's mret pop
            fflags_value     : in std_logic_vector(XLEN-1 downto 0); fp_flags_we : in std_logic := '0'; fp_flags_val : in std_logic_vector(4 downto 0) := (others => '0');  -- fflags PRE-edge + A17's post-op OR operands; THREE PORTS SHARE THIS LINE ON PURPOSE (the A16 rule at :484) -- see the port map
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
        ZCM_JT_WB,    -- capture target; cm.jalt writes ra=pc+2; redirect PC
        -- D1 debug mode (ENABLE_DEBUG). **TAIL-APPENDED, AND THAT IS A HARD
        -- REQUIREMENT, NOT A STYLE CHOICE** (D0/P1 1a): vesta_tracer.vhd's ST_*
        -- table mirrors this declaration ORDER positionally and a mismatch is
        -- SILENT. Appending leaves all 39 existing ordinals valid, so the
        -- tracer diff is purely additive; inserting a DBG_SV beside MTRAP_SV --
        -- which reads as the tidy choice -- would renumber 26 states and
        -- invalidate every lockstep record. The S-series permission tables are
        -- keyed by NAME (commit_perm_t is array (cpu_state)), so they are
        -- insertion-safe; the tracer is the ONLY positional consumer, which is
        -- exactly what makes the trap asymmetric and easy to walk into. Since
        -- D1 there is also an ELABORATION-TIME COUNT ASSERT (the STATE_COUNT
        -- generic on vesta_tracer) -- it catches an ADD or a REMOVE, and it
        -- does NOT catch a reorder at constant count. Nothing cheap does.
        --
        -- All three are UNREACHABLE when ENABLE_DEBUG is false: every
        -- transition into them is qualified by dbg_halt_take / dbg_ebreak_take
        -- / dret_op, each statically '0' there -- so the OFF build's state
        -- encoding is bit-identical. None of them declares ANY commit intent
        -- beyond ci_pc_advance, so the permission tables' `others => '0'`
        -- denial makes them inert by construction (verified, not assumed:
        -- rd/sp/lanes are all absent from their arms).
        DBG_SV,       -- debug ENTRY: dpc/dcsr.cause/prv/debug_mode <- ... ; PC <- DEBUG_ENTRY_ADDR
        DBG_JUMP,     -- debug RE-ENTRY (ebreak in debug mode): PC <- DEBUG_ENTRY_ADDR, no CSR write
        DBG_RET       -- DRET: PC <- dpc, debug_mode <- 0, priv <- dcsr.prv
    );

    signal current_state, next_state : cpu_state;

    -- ==========================================
    -- S-series commit-intent interface (S0 interface spec, section 2)
    -- ==========================================
    -- A state DECLARES what it commits; the commit block at the tail of
    -- next_state_logic is the only place that turns intent into the four nets
    -- (reg_write_dp / sp_write_en / wen / pc_en).  Every default is the
    -- FAIL-SAFE direction: a state that declares nothing commits nothing and
    -- holds the PC.  Note ci_st_lanes is ACTIVE-HIGH -- the active-low wen
    -- convention is re-derived at 64 sites today and exists in exactly one
    -- line (`wen <= not ci_st_lanes`) after migration.
    --
    -- S1 adds a declaration exactly where a state's CURRENT effective drive
    -- differs from that fail-safe value.  That includes the paths which reach
    -- a non-default value by FALLING THROUGH to the process defaults
    -- (reg_write_ctrl / wen_controller / pc_en '1'), which is why arms that
    -- assign nothing today still declare here -- and it excludes the arms that
    -- force '0' / all-ones / pc-hold, which the default already covers.  Where
    -- an earlier declaration in the SAME path has already moved a signal off
    -- its default, restoring it takes an explicit declaration (the pc_en '1'
    -- then '0' shape of AMO_WRITE, LR_READ, SC_CHECK, DIV_DONE, ...).
    --
    -- ONE DELIBERATE EXCEPTION, for `wen` only (rulings R-S1-1c, R-S1-2):
    -- **a wen fall-through in a NON-DISPATCH state declares NOTHING.**  There,
    -- no-store is the INTENDED behaviour and it holds today only by a
    -- cross-file decode coincidence over a HELD word (census N1), so mirroring
    -- it would blind the shadow checker to that coincidence breaking.  The
    -- sites: SLEEPING, DIV_WAIT, DIV_DONE, FPU_FETCH3, FPU_WAIT, FPU_DONE,
    -- IRQ_REST's irq_save and std_irq_take paths, and `when others`.
    -- IN EXECUTE THE MIRROR STAYS: there the live decode is the DISPATCHING
    -- word's own intent, so `not wen_controller` on a div / fp / lr / trap-entry
    -- branch is that instruction's true no-store, not a coincidence.
    signal ci_rd_commit  : std_logic;                     -- default '0' : no rd write
    signal ci_sp_commit  : std_logic;                     -- default '0' : no sp write
    signal ci_st_lanes   : std_logic_vector(3 downto 0);  -- ACTIVE-HIGH, default "0000" : no store
    signal ci_pc_advance : std_logic;                     -- default '0' : PC holds

    -- ==========================================
    -- S3 COMMIT PERMISSION MASKS (S0 interface spec, section 3.1)
    -- ==========================================
    -- "No commit outside a retire group", made STRUCTURAL rather than declared.
    -- Each table names the states in which the corresponding commit is
    -- LEGITIMATE; the commit block ANDs intent with the table, so a state that
    -- declares a commit it has no business making cannot make one.
    --
    -- DERIVED FROM THE TREE, not adopted from prose (spec section 4 requires the
    -- re-derivation and treats any difference as a finding): a state is allowed
    -- exactly when its own arm can produce a NONZERO value for that intent
    -- signal.  Because S2 made every state's intent explicit, that derivation is
    -- mechanical and complete -- which is also why masking is a no-op today and
    -- why any behavioural movement here means a table is wrong.
    --
    -- Retire GROUPS, not `retire_now` (R-S0-1 item 2): commit state /= retire
    -- state for 6 of the 12 commit sites -- AMO_WRITEBACK commits where
    -- AMO_WRITE retires, ZCM_POP_WB/A0Z/MV1/MV2 commit where ZCM_RET or
    -- MEMORY_WAIT retires.  A mask keyed on retirement would be wrong.
    --
    -- NOTE on ci_pc_advance: there is deliberately NO pc table.  A wrong PC hold
    -- is loud by construction (the machine stops), and a table naming every
    -- state that may advance the PC would be a second copy of the state machine
    -- -- a decorative instrument, which is worse than none.
    -- The tables are std_logic / std_logic_vector rather than boolean so the
    -- mask is a plain AND against the intent signal -- no type juggling and no
    -- conditional-assignment form (which VHDL-93 does not allow inside a
    -- process).  The lane table holds the PERMITTED LANE MASK directly.
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
        ZCM_A0Z       => '1',   -- cm.popretz a0 <- 0
        ZCM_MV1       => '1',   -- cm.mv, first
        ZCM_MV2       => '1',   -- cm.mv, second
        ZCM_JT_WB     => '1',   -- cm.jalt links ra (conditional on zcm_jt_link)
        others        => '0');

    constant sp_commit_allowed : commit_perm_t := (
        IRQ_SV        => '1',   -- push: sp <- sp-4
        IRQ_REST      => '1',   -- pop:  sp <- sp+4 (both legs)
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
    -- INITIALIZE is in the store list because its arm declares
    -- `ci_st_lanes <= not wen_controller` -- a LIVE DECODE, so store-capable.
    -- Spec section 4's list omits it and instead names MEMORY_WAIT, which
    -- declares no lanes at all (its pre-S2 `wen` site drove the all-ones
    -- NO-STORE value).  The two errors cancel in the count, so a count-only
    -- check passes; the membership is what matters.  Derivation over prose --
    -- see the S3 implementation report.

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
    -- F11 (fix pass W1): pc_next_ret_ltch is RETIRED -- see :1109.
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
    -- F5.5 (fix pass W1) -- DOCUMENTED, DELIBERATELY NOT CHANGED.
    -- is_compressed is assigned in the RESET branch and in four EXECUTE arms,
    -- but is ABSENT from the FSM process's else-branch default list, so it
    -- HOLDS in every other state => a third inferred latch (is_compressed_reg,
    -- a real LATQX1MA10TH in the netlist). Adding it to the default list would
    -- retire that latch, and the enumeration says it is ALMOST safe:
    --   * the ONLY reader is instr_to_decomp (:1447), qualified
    --     `EXECUTE and pc(1)='1' and repeat_if='0'`; the held value in
    --     non-EXECUTE states is therefore never read;
    --   * the value is OBSERVABLE only when instr_curr selects instr_decomp,
    --     i.e. additionally `quadrant_upper /= "11"` -- and in the normal case
    --     that condition lands exactly on the EXECUTE arm that ASSIGNS
    --     is_compressed <= '1'. No held value is ever observed there.
    -- EXCEPT on one path: the hoisted PMP instruction-access-fault arm
    -- (ENABLE_PMP and pmp_f_deny_r='1'), which does NOT assign is_compressed
    -- and can run with pc(1)='1', repeat_if='0', quadrant_upper /= "11".
    -- That path looks harmless (it forces pc_en/reg_write_dp/mem_access_instr
    -- '0' and wen all-ones; mtrap_disp_code's FIRST arm is x"1" gated on
    -- pmp_f_deny_r and mtrap_disp_val is pmp_f_addr_r, so cause/mtval/mepc are
    -- all decode-independent) -- but it writes instr_curr_prev, and the whole
    -- argument lives in an OPT-IN ENABLE_PMP build that this wave's gates do
    -- not exercise. The default build folds that arm away statically, so a
    -- green 136-suite would prove nothing about the only exposed path.
    -- Not demonstrable => not changed. See ~/vesta_docs/fixpass/w1_report.md.
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
    signal div_dispatch           : std_logic;  -- K5 defect B; derived at :4710-ish

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
    -- P3-entry: the CSR instruction's rs1/uimm FIELD is zero (csr_unit
    -- write-form rule -- CSRRS/C[I] with rs1/uimm = 0 must not write).
    signal csr_rs1_zero           : std_logic;
    -- F-BV1 (K5): the R-type rs2 FIELD is zero (decode legality only -- never
    -- the register's VALUE). Feeds maindec's ZEXT.H row via controller.
    signal rs2_zero               : std_logic;
    -- P3-entry: effective DATA-access privilege from csr_unit (mstatus.MPRV
    -- redirection). CONSUMER = the P3 PMP data-side check (Agent B); carried
    -- unconsumed until then.
    signal eff_data_priv_m        : std_logic;
    -- P3 red-team F1: the MRET return privilege (MPP mapped) from csr_unit --
    -- the privilege the MRET-target FETCH is checked at during MTRAP_RET.
    signal mret_priv_m            : std_logic;
    -- P3 red-team F1: the effective FETCH-check privilege -- trap_priv_mode
    -- normally, but mret_priv_m during MTRAP_RET (the one privilege-LOWERING
    -- state whose issued fetch is consumed at the new, lower privilege).
    signal pmp_f_priv             : std_logic;
    -- P2 TRAP-ENTRY SIDE-EFFECT BLOCK (see the assignment near the trap glue).
    signal trap_entry_seq         : std_logic;
    signal csr_valid_eff          : std_logic;
    signal isr_ret_eff            : std_logic;
    -- W3 (fix pass, F1/F1+): THE STRUCTURAL RETIRE PATH. `retire_now` is the
    -- architectural predicate "an instruction retires at this clk_cpu edge"
    -- (v1_retire_enumeration.md §3-R0 + one documented deviation);
    -- `retire_wfi_armed` is its SLEEPING one-shot; `inst_retired` is the same
    -- predicate qualified into the free-running clk domain that csr_unit's
    -- minstret counts on. The old `en_cg_insret` + `cg_insret` ClkGate pair is
    -- DELETED -- see the assignments in the clock-gating section for why.
    signal retire_now             : std_logic;
    signal retire_wfi_armed       : std_logic;
    signal inst_retired           : std_logic;

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

    -- ------------------------------------------------------------------
    -- D1 DEBUG MODE (ENABLE_DEBUG)
    -- ------------------------------------------------------------------
    -- csr_unit's exports. All are reset constants on an OFF build
    -- (debug_mode '0', the three dcsr bits '0', dpc zero), which is what makes
    -- every take signal below statically '0' and every FSM arm fold.
    signal debug_mode             : std_logic;
    signal dcsr_ebreakm           : std_logic;
    signal dcsr_ebreaku           : std_logic;
    signal dcsr_step              : std_logic;
    signal dbg_dpc_value          : std_logic_vector(XLEN-1 downto 0);
    -- maindec's DRET decode ('0' unless ENABLE_DEBUG **and** in debug mode).
    signal dret_op                : std_logic;
    -- THE THREE TAKES. Separate signals with different qualifier sets, the
    -- std_irq_take / std_wfi_pend precedent: one decides whether an
    -- ASYNCHRONOUS halt is recognised, one whether a SYNCHRONOUS ebreak
    -- diverts, and they are tested at different points in the decode tree.
    signal dbg_halt_take          : std_logic;   -- haltreq | resethaltreq | step, and not already halted
    signal dbg_step_take          : std_logic;   -- the step re-entry alone (feeds the cause mux)
    signal dbg_ebreak_take        : std_logic;   -- ebreak diverts to debug rather than to the trap path
    -- D2 / F-D2-0 (R-D2-3(1)). A SYNCHRONOUS exception taken while ALREADY in
    -- debug mode re-enters at DEBUG_ENTRY_ADDR instead of taking the trap
    -- path. Fourth "take" in the same family and named the same way, because
    -- it is tested at the same dispatch points as dbg_ebreak_take but answers
    -- a different question: not "does this ebreak divert" but "is this hart
    -- allowed to leave debug mode through a trap at all".
    signal dbg_exc_take           : std_logic;
    -- D2 / F-D2-1 (R-D2-3(3)). Interrupt delivery is suppressed in debug
    -- mode, on BOTH paths. Deliberately a SEPARATE signal from dbg_exc_take
    -- even though the predicate is identical: they are two separately-ruled
    -- findings with two separate detectors, and either must be revertible
    -- without touching the other. The duplicate term is combinational and
    -- costs nothing -- the same argument the dbg_halt_pend comment above
    -- makes for its own duplicate of dbg_halt_take.
    signal dbg_irq_block          : std_logic;
    -- The en_clk_cpu ungate (F-D0P1-3). Same expression as dbg_halt_take; a
    -- separate name because it is consumed in a DIFFERENT domain question
    -- (does this hart get a clock at all) and conflating the two is how a
    -- future edit to one silently changes the other.
    signal dbg_halt_pend          : std_logic;
    -- WAIT-FOR-RELEASE on the halt request (the mp_arbiter `need_release`
    -- idiom, and the same hazard it exists for). See the assignment below.
    signal dbg_req_mask           : std_logic;
    signal dbg_haltreq_eff        : std_logic;
    -- Halt-on-reset. dbg_rsthalt_r level-follows dbg_resethaltreq from reset
    -- release until the FIRST debug entry, then is disarmed forever by
    -- dbg_rst_armed. Level-following rather than a single sample at the reset
    -- edge is deliberate: hart_tile registers the request at the tile boundary
    -- AND holds the core in reset until its boot fetch lands, so "the first
    -- core-clk edge after release" is not a well-defined sampling point from
    -- inside this file.
    signal dbg_rsthalt_r          : std_logic;
    signal dbg_rst_armed          : std_logic;
    -- SINGLE-STEP. Armed at the DRET that carried dcsr.step, consumed by the
    -- next entry. THE STEP DIVERTS AT THE STEPPED INSTRUCTION'S OWN DISPATCH
    -- CYCLE, not at the next one -- exactly like an interrupt divert, so the
    -- stepped instruction RETIRES (ci_rd_commit/ci_st_lanes are declared) and
    -- dpc becomes pc_next_reg = the address of the following instruction.
    -- Diverting at the NEXT instruction's dispatch instead would retire TWO
    -- instructions per step, which is the natural wrong implementation.
    signal dbg_step_armed         : std_logic;
    -- Dispatch-cycle cause classification + its latch (the mtrap_cause_proc
    -- idiom): read ONLY at the clk_cpu edge that ENTERS DBG_SV, so the value
    -- is stable for the whole state and for the free-clk strobe that consumes
    -- it. Codes: 1 ebreak, 3 haltreq, 4 step, 5 resethaltreq.
    signal dbg_disp_cause         : std_logic_vector(2 downto 0);
    signal dbg_cause_r            : std_logic_vector(2 downto 0);
    -- The dpc value, selected by the LATCHED cause: a synchronous ebreak
    -- records its OWN pc; a halt or a step records pc_next_reg, the resume PC
    -- (provably the same word the legacy IRQ_SV pushes at sp-4).
    signal dbg_pc_val             : std_logic_vector(XLEN-1 downto 0);
    -- The two one-shots, generated on the csr_unit clock domain exactly as
    -- mtrap_sv_lvl / mtrap_ret_lvl are -- the ONLY mechanism in this core for
    -- a gated-clk state to commit a free-clk CSR side effect exactly once.
    signal dbg_sv_lvl             : std_logic;
    signal dbg_sv_d               : std_logic;
    signal dbg_ret_lvl            : std_logic;
    signal dbg_ret_d              : std_logic;
    signal dbg_entry_we_sig       : std_logic;
    signal dbg_ret_we_sig         : std_logic;

    -- ------------------------------------------------------------------
    -- P3 PMP CHECK INTEGRATION (ENABLE_PMP) -- the D5 strict-pre-issue diff
    -- ------------------------------------------------------------------
    -- EVERY signal below is statically '0'/'1'/zero when ENABLE_PMP is false
    -- (the gen_pmp_off generate ties the unit outputs and the two flops), so
    -- the OFF netlist and the LEGACY delivery path are bit-identical.
    --
    -- THE SUPPRESSION MECHANISM (why "no transaction" is structural here):
    -- hart_tile derives the arbiter request from the ADDRESS ALONE --
    --   sh_sel <= <window decode of data_addr>;  sh_req <= sh_sel and not ack
    -- -- so "a denied access issues NO transaction" is EXACTLY "the denied
    -- address never reaches `data_addr`". Both check points are shaped to
    -- that single invariant:
    --   DATA  : the EXECUTE-cycle data address only reaches data_addr through
    --           `mem_access_instr` (loads/stores/LR/AMO) or through a
    --           sequencer STATE term (CBOZ_WRITE / ZCM_*). A denial forces
    --           mem_access_instr '0' + wen all-ones AND gates the sequencer
    --           terms, so data_addr stays on the fetch fall-through; SC's only
    --           transaction lives in SC_CHECK, which a denial never enters.
    --   FETCH : the fall-through `pc_next` arm of the data_addr mux is the ONE
    --           place this core issues an instruction fetch. A denial parks
    --           data_addr on PC_RST_VAL (the reset vector -- fetchable and
    --           side-effect-free by construction in every instantiation).
    signal pmp_cfg_flat_sig       : std_logic_vector(127 downto 0);
    signal pmp_addr_flat_sig      : std_logic_vector(479 downto 0);
    -- Fetch port. f_addr is pc_next: the address the CURRENT cycle would put
    -- on the bus as an instruction fetch.
    signal pmp_f_grant            : std_logic;
    signal pmp_f_deny             : std_logic;
    -- ...and its 1-deep clk_cpu pipeline. INVARIANT: in any EXECUTE cycle,
    -- pmp_f_deny_r/pmp_f_addr_r describe the fetch the IMMEDIATELY PRECEDING
    -- core cycle issued -- which is always the word this EXECUTE decodes (or,
    -- on a repeat_if completion, the UPPER half of the straddling 32-bit
    -- instruction). That is why ONE fetch port covers both halves.
    signal pmp_f_deny_r           : std_logic;
    signal pmp_f_addr_r           : std_logic_vector(XLEN-1 downto 0);
    -- '1' in the EXECUTE cycle that would consume a fetch which never issued:
    -- the decoder is looking at the PARK word, so this cycle must commit
    -- NOTHING (the trap_entry_seq lesson, applied one cycle earlier).
    signal pmp_if_squash          : std_logic;
    -- trap_entry_seq OR pmp_if_squash: the decode-bypassing side effects
    -- (csr_valid, isr_ret, sleep_cpu) are killed by either.
    signal dec_squash             : std_logic;
    -- W2 (F7/F3/F3+/F3++): the POSITIVE form of that rule -- '1' in exactly the
    -- cycle in which the decode of instr_curr is a DISPATCHING instruction and
    -- may therefore commit a side effect that bypasses the FSM. See the
    -- assignment for the per-term justification.
    signal dec_dispatch           : std_logic;
    -- data_addr park select (see the mechanism note above).
    signal pmp_if_park            : std_logic;
    -- Data port.
    signal pmp_d_grant            : std_logic;
    signal pmp_d_addr             : std_logic_vector(XLEN-1 downto 0);
    signal pmp_d_rd               : std_logic;
    signal pmp_d_wr               : std_logic;
    signal pmp_d_active           : std_logic;
    -- '1' when the denied access is of the STORE class (store / SC / AMO /
    -- cbo.zero / cm.push) => cause 7; '0' for the LOAD class (load / LR /
    -- cm.pop / Zcmt table fetch) => cause 5. NOTE this is the ACCESS CLASS,
    -- not the permission need: LR/SC/AMO all check R AND W (frozen §4), but a
    -- denied LR reports cause 5, per the §2.2 row it belongs to.
    signal pmp_d_st_class         : std_logic;
    signal pmp_d_deny             : std_logic;
    -- The faulting address for mtval (causes 1/5/7): combinational at the
    -- dispatch cycle, LATCHED at the MTRAP_SV dispatch edge because neither
    -- source is stable during MTRAP_SV.
    signal mtrap_disp_val         : std_logic_vector(XLEN-1 downto 0);
    signal mtrap_val_r            : std_logic_vector(XLEN-1 downto 0);

    -- ------------------------------------------------------------------
    -- V1 LOCKSTEP TRACER TAPS (read-only). These carry the committed-write
    -- values that are NOT otherwise visible at this level: two from datapath
    -- (the regfile's a3/wd3) and four from csr_unit. They are mapped
    -- unconditionally -- a port map cannot be conditional -- but TRACE_ENABLE is
    -- threaded into both sub-blocks, so with TRACE_ENABLE=false the logic that
    -- would drive them does not exist at all (their `gen_trc_off` arms tie them
    -- to constants) and nothing reads them here either. Identical BY
    -- CONSTRUCTION, not by unloaded-logic removal -- the first cut relied on the
    -- optimiser and cost +174 cells / +745.8 area at elaborate.
    -- See v1_retire_enumeration.md §2.1/§2.4/§7-A/§7-B.
    -- ------------------------------------------------------------------
    signal trc_rd_addr            : std_logic_vector(4 downto 0);
    signal trc_rd_data            : std_logic_vector(XLEN-1 downto 0);
    signal csr_commit_we          : std_logic;
    signal csr_commit_val         : std_logic_vector(XLEN-1 downto 0);
    signal mstatus_value          : std_logic_vector(XLEN-1 downto 0);
    signal fflags_value           : std_logic_vector(XLEN-1 downto 0);

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
        elsif r < 4 then
            -- Reserved rlist encodings (0-3) never reach the ZCM states, but
            -- this lookup is a concurrent statement evaluated from reset with
            -- rlist = "0000": r-3 would violate zcm_nregs_val's range 1..13
            -- (GHDL bound check). Clamp reserved encodings to the range floor;
            -- defined encodings (4-15) are untouched.
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
    -- D1 (F-D0P1-3): THE PARKED-HART UNGATE, and on this chip it is not a
    -- corner case -- it is the DEFAULT BOOT STATE OF EVERY HART BUT HART 0.
    -- Harts 1..N-1 park in SLEEPING via `extinguish` (bootrom_mp start.S), with
    -- clk_cpu GATED OFF: the FSM gets no edge, so it cannot evaluate the
    -- SLEEPING arm and cannot sample a halt request at all. Without this term
    -- "attach a debugger and halt hart 2" is impossible by construction on
    -- three quarters of the harts, at N=4 and at N=18 alike -- and every
    -- knob-OFF gate stays green while it is missing, which is what makes it the
    -- single most likely D1 omission. Same precedence and the same shape as the
    -- P1/P2 terms above it, and statically '0' when ENABLE_DEBUG is off (via
    -- dbg_halt_take), so the OFF build's en_clk_cpu is bit-identical.
    -- COROLLARY, and it must not be "optimised": the DEBUG-HALTED state is
    -- deliberately NOT added to the gating list below. A halted core keeps
    -- clk_cpu running -- that is what lets it execute debug-ROM / program-buffer
    -- instructions at all. Gating it would look like a power win and would make
    -- the feature non-functional.
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

    -- ==========================================
    -- THE RETIRE STROBE  (fix pass W3: findings F1 and F1+)
    -- ==========================================
    -- This is roadmap step 10, "make the retire path structural" -- not a
    -- counter patch. Spec: ~/vesta_docs/fixpass/specs/w3_spec.md; condition:
    -- ~/vesta_docs/lockstep/v1_retire_enumeration.md §3-R0 (+ §5's 39-row
    -- table); detector: rv32ua-p-insretov.
    --
    -- WHAT WAS HERE, AND WHY IT WAS WRONG. Two independent defects:
    --
    --     en_cg_insret <= '1' when next_state = EXECUTE else '0';
    --     cg_insret: entity work.ClkGate
    --         port map (ClkIn => not clk_cpu, En => en_cg_insret,
    --                   ClkOut => inst_retired);
    --
    -- F1 -- THE CONDITION. `next_state = EXECUTE` is not "an instruction
    -- retired": through a `not clk_cpu`-clocked ClkGate it makes minstret count
    -- EXECUTE CYCLES, and the compressed straddling fetch (the shape-E
    -- half-fetch bubble, the `else` at :2726 below) spends TWO EXECUTE cycles
    -- on ONE instruction. Measured +1 per straddling 32-bit instruction
    -- (d1s = 5 vs the word-aligned control d1a = 4).
    --   Do NOT re-add "+1 per FENCE / per AMO / per interrupt entry" to this
    --   list. Three separate reviews asserted it; all three counted a trailing
    --   state's fire without checking whether the DISPATCH EXECUTE cycle fired
    --   at all. It does not: FENCE_WAIT / AMO_COMPLETE / MEMORY_WAIT etc. are
    --   the FETCH-NEXT states, so the dispatch cycle has next_state /= EXECUTE
    --   and the trailing fire is the ONLY fire. Measured correct today
    --   (d2f = d3a = d2n = 2). The standing habit: before believing any
    --   "+1 from state X" claim about this counter, write out the
    --   instruction's whole state trajectory and count its EXECUTE cycles.
    --
    -- F1+ -- THE DOMAIN, and the dominant term. `inst_retired` was a GATED
    -- CLOCK consumed as a LEVEL on the free-running clk (csr_unit :681, inside
    -- `elsif rising_edge(clk)`). With ClkIn = not clk_cpu the ClkGate latch is
    -- transparent only while clk_cpu is HIGH, so once clk_cpu gated off with
    -- the enable latched '1' the level STUCK HIGH and minstret incremented
    -- once per free-running clk cycle for the whole stall.
    --   It fires per shared-window instruction FETCH, not per shared-window
    --   ACCESS: hart_tile's `mem_ready_sh <= (not sh_sel) or sh_ack_ok` is a
    --   combinational decode of data_addr, so a shared DATA access freezes the
    --   core inside an EXECUTE whose next_state is MEMORY_WAIT -- the latch
    --   holds '0' and the stall integrates nothing. Measured: two bursts
    --   stalling for exactly the same 48 clk, the fetch case gained 48 phantom
    --   retires and the data case 0 -- one phantom retire per stalled clk
    --   cycle, exactly. Every hart boots from the SHARED ROM (M12), so ~79 %
    --   of all boot clk cycles were counted as retired instructions.
    --
    -- THE FIX, part 1: the condition.  `retire_now` implements §3-R0. That
    -- boolean is not a sketch -- it was adopted from the lockstep red team's
    -- R5/R7, re-verified arm by arm, and every state ordinal in it checked
    -- against §5's 39-row table. Do not "simplify" an arm; each term has a
    -- named counter-example:
    --   * `next_state in {EXECUTE, IRQ_SV, MTRAP_SV, FENCE_WAIT}` is what
    --     separates a RETIRE from a multi-cycle DISPATCH. Verified complete
    --     against the four surviving EXECUTE arms (the four `else`
    --     next_state <= EXECUTE tails, irq_save->IRQ_SV, std_irq_take->
    --     MTRAP_SV, fence_op-non-PAUSE->FENCE_WAIT, wrs_op-with-no-reservation
    --     ->EXECUTE). An interrupt divert takes away only pc_en, so the
    --     interrupted instruction still retires -- the retire condition is a
    --     function of current_state + decode class + next_state, and NEVER of
    --     pc_en (pc_en is neither necessary nor sufficient: it is '1' with no
    --     retire in INITIALIZE, IRQ_JUMP, MTRAP_JUMP, FENCE_WAIT and
    --     AMO_COMPLETE).
    --   * the hoisted shapes P (:2476, ENABLE_PMP fetch deny) and Q (:2503,
    --     non-compressed build, pc(1)='1') sit ABOVE every shape selector and
    --     leave the quadrant/pc bits untouched, so they need their own
    --     exclusions; the trap / ecall_op / ebreak_op / mret_op / pmp_d_deny
    --     sub-arms each MATCH a shape predicate and must be excluded too
    --     (in standard mode they target MTRAP_SV, which is in the allowed
    --     next_state set). All exclusions are ANDed, so this expression does
    --     not depend on the FSM's arm ORDER.
    --   * shape E (:2726, "need to fetch upper half") emits nothing -- that is
    --     the F1 half-fetch bubble itself.
    --   * SLEEPING retires on the EXIT cycle only, and only for a real
    --     WFI/extinguish dispatch. SLEEPING has a SECOND entry -- IRQ_REST's
    --     sleep_cpu arm (:3755), the bootrom park contract for harts 1..N-1 --
    --     so an unqualified "retire on every SLEEPING exit" would invent a
    --     retire on every parked-hart ISR round trip, i.e. on every sh* test.
    --     retire_wfi_armed below is the one-shot that separates them.
    --
    -- THE ONE DOCUMENTED DEVIATION FROM §3-R0: `iret` RETIRES.
    -- (Ruling: w3_spec.md §6.3.) §3-R0 rule 2 reads
    --     RETIRE_MEMORY_WAIT = (current_state = MEMORY_WAIT) and isr_ret = '0'
    -- and that `isr_ret = '0'` qualifier is deliberately NOT reproduced here.
    -- §3-R0 is the TRACER'S COMPARISON CONTRACT, not an architectural
    -- definition of retirement: it excludes `iret` only because Spike has no
    -- encoding for this custom instruction, so the tracer emits X instead of
    -- R. That is a statement about what can be COMPARED, not about what
    -- EXECUTED. §3-R0 already treats `mret` as a retire (§5 row 16) and `iret`
    -- is the legacy-path analogue of `mret`; counting one and not the other in
    -- an architectural counter is indefensible. `iret`'s real trajectory is
    -- EXECUTE -> MEMORY_WAIT -> IRQ_REST (the three EXECUTE isr_ret arms are
    -- dead code, :2224-2235 and enumeration R1), and MEMORY_WAIT is a
    -- single-cycle state, so dropping the qualifier counts it EXACTLY ONCE.
    -- DO NOT "correct" this to match the tracer.
    --   Nothing is added on IRQ_REST's re-park arm, and that is deliberate:
    --   the re-parking `iret` is ALREADY counted here, exactly like the
    --   resuming one (measured d_fb = d4 + 1 = 3 over a 498-clk gated park).
    --   Adding a count there would DOUBLE-count every parked-hart msip round
    --   trip -- every sh* test on harts 1..N-1.
    retire_now <=
        -- 1. EXECUTE -- §3-R0 rule 1.
        '1' when (current_state = EXECUTE
                  and not (ENABLE_PMP and pmp_f_deny_r = '1')            -- shape P
                  and not ((not ENABLE_COMPRESSED) and pc(1) = '1')      -- shape Q
                  and not (pc(1) = '1' and quadrant_upper = "11"
                           and repeat_if = '0')                          -- shape E
                  and trap = '0' and ecall_op = '0' and ebreak_op = '0'  -- trap sub-arms
                  and mret_op = '0'                                      -- retires at MTRAP_RET
                  and not (ENABLE_PMP and pmp_d_deny = '1')              -- the P3 D5 arm
                  -- D1: DBG_SV joins this CLOSED whitelist, and it MUST
                  -- (D0/P1 F-D0P1-2). A halt or step divert out of EXECUTE
                  -- takes away only pc_en, exactly as an interrupt divert
                  -- does, so the diverted instruction still retires -- and for
                  -- SINGLE-STEP that retire IS the step: the one instruction
                  -- the step is defined to execute. Omitting it here would
                  -- silently drop one minstret and one lockstep retire record
                  -- PER HALT AND PER STEP, a bug whose signature is "the
                  -- counters are one low, sometimes". vesta_tracer.vhd carries
                  -- the SAME addition to its own copy of this condition; the
                  -- two copies differ ON PURPOSE elsewhere (the MEMORY_WAIT
                  -- isr_ret term) and a mismatch here is as silent as the
                  -- ordinal one. Unreachable knob-OFF (DBG_SV has no reachable
                  -- transition there), so the OFF retire stream is unchanged.
                  and (next_state = EXECUTE  or next_state = IRQ_SV or
                       next_state = MTRAP_SV or next_state = FENCE_WAIT or
                       next_state = DBG_SV)) else
        -- 2. MEMORY_WAIT -- §3-R0 rule 2 WITHOUT its `isr_ret = '0'` qualifier;
        --    that omission is the one documented deviation (see above).
        '1' when (current_state = MEMORY_WAIT) else
        -- 3. SLEEPING -- §3-R0 rule 3: the exit cycle of an armed sleep only.
        '1' when (current_state = SLEEPING and next_state /= SLEEPING
                  and retire_wfi_armed = '1') else
        -- 4..11. Unconditional in the state -- no arm can suppress the commit.
        -- D1: DBG_RET joins the unconditional list beside MTRAP_RET -- the
        -- same shape, the same argument, and `dret` is a STANDARD encoding the
        -- reference knows (unlike `iret`), so its retire is comparable.
        -- DBG_SV and DBG_JUMP do NOT retire: an entry executes nothing (the
        -- retire that accompanies a halt belongs to the DIVERTING state, above).
        '1' when (current_state = DIV_DONE  or current_state = FPU_DONE  or
                  current_state = LR_READ   or current_state = SC_CHECK  or
                  current_state = AMO_WRITE or current_state = MTRAP_RET or
                  current_state = DBG_RET   or
                  current_state = ZCM_RET   or current_state = ZCM_JT_WB) else
        -- 12. PAUSE_WAIT retires on the window-close cycle only.
        '1' when (current_state = PAUSE_WAIT and pause_cnt = 0) else
        -- 13. WRS_WAIT retires on the wake cycle only.
        '1' when (current_state = WRS_WAIT and wrs_wake = '1') else
        '0';

    -- The SLEEPING one-shot (§3-R0's `trc_wfi_armed`, core-side equivalent).
    -- Set at the ONLY real WFI/extinguish dispatch edge (EXECUTE -> SLEEPING,
    -- the sleep_rq and wfi_op arms at :2596/:2599 and :2892/:2895); cleared on
    -- the first SLEEPING exit, whichever arm takes it. Set and clear cannot
    -- coincide (one needs current_state = EXECUTE, the other SLEEPING).
    -- NOT reusable: wfi_slept looks identical but is set from `wfi_enter`,
    -- which the extinguish arms do NOT raise (it selects the STANDARD wake
    -- rule), and which is statically '0' on a non-ENABLE_TRAPCSR build -- so
    -- reusing it would drop the retire of every extinguish in the default
    -- config. This flop is the one piece of new state W3 adds.
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

    -- THE FIX, part 2: the domain crossing -- one clk_cpu cycle, exactly one
    -- increment. This is what the author's own commented-out line was reaching
    -- for, and it deletes the cg_insret ClkGate entirely.
    --
    -- clk_cpu is ClkGate(clk, en_clk_cpu): its edges are a SUBSET of clk's,
    -- same source, no phase relationship -- an edge-REMOVAL problem, not a CDC
    -- problem. csr_unit samples inst_retired on rising_edge(clk). The question
    -- is whether "en_clk_cpu sampled at a clk rising edge" is the same
    -- predicate as "this edge is also a clk_cpu edge". IT IS, IN BOTH VIEWS:
    --   * hdl/common/sim/ClkGate.vhd is the classic latch-then-AND
    --     (`if ClkIn = '0' then ClkSync <= En;` + `ClkOut <= ClkSync and
    --     ClkIn`), so a clk_cpu edge occurs iff ClkSync = '1', and ClkSync at
    --     that edge is en_clk_cpu as of the END OF THE LOW PHASE -- exactly
    --     the value a clk-edge flop samples under setup;
    --   * hdl/common/commune/ClkGate_cmn65gp_ARM.vhd wraps PREICGX1BA10TH, a
    --     standard integrated clock gate with the same latch-then-AND
    --     semantics, so the argument holds in gates as well as in sim.
    -- Both files re-confirmed unchanged at W3. Un-stalled, every clk edge is a
    -- clk_cpu edge and the strobe is high for exactly the retiring cycle => one
    -- increment. Stalled (or slept, or externally sleep-gated), en_clk_cpu = '0'
    -- kills it => the stall integrates NOTHING, and the cycle in which the
    -- stall releases counts once.
    --   The toggle-flop alternative is deliberately NOT used: it adds a
    --   same-edge launch/capture path into a tile with picosecond setup margin.
    inst_retired <= retire_now and en_clk_cpu;

    -- BINDING (w3_spec.md §2.3): vesta_tracer must NOT consume `retire_now`.
    -- The tracer implements §3-R0 independently (its own `wfi_armed`
    -- variable). Wiring this signal into it would make the two agree BY
    -- CONSTRUCTION and destroy the only thing that makes their agreement
    -- evidence: two independent implementations of one spec agreeing over
    -- 4.6 M records is a result; one implementation observed twice is a
    -- tautology. Keep them separate -- do NOT "de-duplicate" them.


    -- ==========================================
    -- PC Return Value Latching
    -- ==========================================
    -- F11 (fix pass W1): this WAS a 32-bit transparent latch bank plus a
    -- guard flop, and the latch was DEAD -- provably always transparent.
    --
    --     pc_next_ret_gt_proc: process(resetn, clk_cpu) ...
    --         elsif rising_edge(clk_cpu) then
    --             if en_clk_cpu = '0' then pc_next_ret_ltch <= '1';
    --             else                     pc_next_ret_ltch <= '0'; end if;
    --     pc_next_ret <= read_data when pc_next_ret_ltch = '0' else pc_next_ret;
    --
    -- WHY IT WAS DEAD. clk_cpu is the ClkGate output, and ClkGate is
    -- `ClkSync <= En while ClkIn = '0'` + `ClkOut <= ClkSync and ClkIn`
    -- (hdl/common/sim/ClkGate.vhd; the PREICGX1BA10TH synthesis cell samples
    -- the enable while the clock is low in the same way). So clk_cpu can only
    -- RISE when ClkSync = '1', i.e. when en_clk_cpu was '1' at the end of the
    -- preceding low phase -- EVERY rising edge of clk_cpu therefore has
    -- en_clk_cpu = '1', the process always took its `else` arm, and
    -- pc_next_ret_ltch was a constant '0' after reset. (A mid-HIGH fall of
    -- en_clk_cpu cannot create an edge: ClkOut is already high. And the
    -- process cannot race it: en_clk_cpu's inputs -- mem_ready, irq_active,
    -- sleep, current_state -- all settle at delta +1/+2 after an edge, while
    -- this process ran at delta 0 and read the pre-edge '1'.)
    --
    -- MEASURED, not merely argued. A TEMP concurrent assertion whose
    -- predicate is always false makes its FIRE COUNT equal the number of
    -- transitions of the signal. Over the full behavioral_mp suite, the
    -- single-hart lockstep sweep and the multi-hart sweep -- 258 sims x
    -- 4 harts = 1032 hart-instances -- it fired exactly 4 times per sim,
    -- always at time 0 FS: the 'U'->'0' reset settle, and never again.
    -- The netlist agreed, to the digit: `sequential` 2284 -> 2251 instances
    -- and 21,650.800 -> 21,487.600 area, exactly the predicted -33 / -163.200
    -- (32 latches @ 4.8 + one DFFRPQX1MA10TH @ 9.6). pc_next_ret_ltch has
    -- zero residue in the netlist. The latches that REMAIN -- 32 result_reg,
    -- 32 sp_write_data_reg, is_compressed_reg, reg_write_dp_reg -- are other
    -- inferences and are not this finding.
    --
    -- So pc_next_ret is simply read_data, and its one consumer -- the
    -- IRQ_REST arm of the pc_next mux (:1527) -- samples the popped return
    -- PC off the bus at the IRQ_REST clk_cpu edge, which is precisely the
    -- cycle in which read_data carries it. Keeping the name documents that.
    -- DO NOT "restore" the latch: it never held anything.
    pc_next_ret <= read_data;

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
    -- P3: pmp_if_squash excludes the EXECUTE cycle that decodes the park word
    -- of a PMP-denied fetch (statically '0' when ENABLE_PMP is false).
    fp_flags_we <= '1' when (current_state = FPU_DONE) else
                   '1' when (current_state = EXECUTE and is_fp_singlecycle = '1' and trap = '0'
                             and pmp_if_squash = '0'
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
                  -- W2/F5.4: a SECOND `current_state = IRQ_SV` arm used to sit
                  -- here. It was DEAD -- the `instr when (current_state =
                  -- IRQ_SV)` arm at the head of this mux (:1484) matches first
                  -- and wins -- so IRQ_SV has always decoded the RAW BUS WORD,
                  -- which on this path is deterministically the next instruction
                  -- in program order. That live decode is F3. The head arm is
                  -- deliberately LEFT AS IS (changing it to hold would move
                  -- mtval / PC-target behaviour in the legacy entry path, which
                  -- is out of scope); instead the raw word is now INERT, because
                  -- dec_dispatch (:1992) gates every strobe that could have
                  -- acted on it -- csr_valid_eff (F3) and the sleep_cpu flop in
                  -- BOTH directions (F3+/F3++) -- and the FSM arm (:3461) forces
                  -- reg_write_dp='0' and wen all-ones.
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
    -- D1: the debug states use the same idiom. DEBUG_ENTRY_ADDR is a GENERIC,
    -- not a CSR -- there is no dm-programmable entry vector at D1 -- so both
    -- entry arms load a constant and DBG_RET loads dpc, which is the MTRAP_RET
    -- arm one line above with a different CSR. All three carry pc_en='1' from
    -- their FSM arms, so data_addr falls through to pc_next and the fetch from
    -- the new PC issues in the SAME cycle.
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

    -- P3 (PMP, D5 strict pre-issue): the three SEQUENCER address terms are
    -- selected by STATE, not by mem_access_instr, so suppressing the FSM's
    -- request alone would still leave the denied word on data_addr for one
    -- cycle (and hart_tile's sh_req is a pure decode of data_addr). Gate them
    -- with pmp_d_deny -- statically '0' when ENABLE_PMP is false, so this
    -- folds bit-for-bit. The EXECUTE-dispatch terms need no such gate: they
    -- are already qualified by mem_access_instr, which the denial forces '0'.
    -- The PC_RST_VAL arm is the FETCH suppression point: it replaces the
    -- single `pc_next` fall-through through which every instruction fetch of
    -- this core issues.
    data_addr <= cboz_zero_addr when (current_state = CBOZ_WRITE and pmp_d_deny = '0') else
                 zcm_mem_addr when ((current_state = ZCM_PUSH_ST or current_state = ZCM_POP_LD)
                                    and pmp_d_deny = '0') else
                 zcm_jt_addr  when (current_state = ZCM_JT_LD and pmp_d_deny = '0') else
                 -- F2 (fix pass W1): the SC_CHECK term is gated by the SAME
                 -- LOCAL reservation predicate that gates its wen and its
                 -- mem_access_instr (the :2900 SC_CHECK arm) -- keep all three
                 -- identical. Steering the address is not optional: sh_sel is a
                 -- pure decode of data_addr, so suppressing only the request
                 -- would still have issued the transaction (spec W1-0). On the
                 -- failing path this arm drops out and data_addr falls through
                 -- to pc_next = pc_next_reg (:1511) -- the redundant early fetch
                 -- of the word AMO_COMPLETE presents next cycle.
                 -- ***** SC-SUCCESS PREDICATE: FOUR COPIES, ALL IDENTICAL *****
                 -- `reservation_valid = '1' and reservation_addr = rs1_value` is
                 -- duplicated at FOUR sites. Change all four or none -- a
                 -- divergence between them is SILENT. By role, not line number
                 -- (three of the four WRAP across lines, so a line-based grep
                 -- under-reports them):
                 --   1. THIS arm of the data_addr mux   (steers rs1_value)
                 --   2. amo_phase                       ("101" SC-success)
                 --   3. lr_sc_bus                       ("10" SC-write tag)
                 --   4. the SC_CHECK FSM arm            (store lanes +
                 --                                       mem_access_instr)
                 rs1_value  when (current_state = SC_CHECK
                                  and reservation_valid = '1'
                                  and reservation_addr = rs1_value) else
                 -- F6 (fix pass W4): LR JOINS SC AND AMO ON THE PHASE-INDEPENDENT
                 -- rs1 ADDRESS. `valid_funct` whitelists AMO_OPCODE on funct3 +
                 -- funct5 only (maindec:952-971) and lr_op has no rs2 term
                 -- (maindec:606), so `lr.w rd, rs2, (rs1)` with a NON-ZERO rs2
                 -- FIELD is a legal decode; ALU_src is '0' for AMO_OPCODE
                 -- (maindec:1112) and alu_control is ADD for LR/SC
                 -- (maindec:1307), so ALU_Result = rs1 + reg[rs2]. Before this
                 -- fix BOTH the EXECUTE dispatch and LR_READ fell through to that
                 -- ALU_Result while the reservation armed at rs1_value (:1377) --
                 -- the read and the reservation landed on DIFFERENT addresses.
                 -- lr.w is the one member of the family that was left out of the
                 -- M4b/M8 rs1_value rule (see the SC note at :2680 and the
                 -- EXECUTE+amo_op term folded in below).
                 --
                 -- BOTH TERMS ARE REQUIRED; either alone is a HALF FIX:
                 --  * EXECUTE alone -- the LR's read transaction rides the
                 --    EXECUTE cycle (:1947's `lr_sc_bus <= "01"` says so), and it
                 --    is data_addr in THAT cycle that the resv_unit sees, so this
                 --    term is what moves the GLOBAL reservation to rs1 as well as
                 --    the read. But LR_READ would then re-present a DIFFERENT
                 --    word address to a window whose ack is word-address
                 --    qualified (hart_tile.vhd:701/715 sh_acked_addr), dropping
                 --    sh_ack_ok and re-arbitrating a second, wrong-address read.
                 --  * LR_READ alone -- the read and the global reservation both
                 --    stay at rs1+reg[rs2], so a later shared `sc.w` at rs1 can
                 --    never succeed (W4 measured exactly that, a7 = 1).
                 -- Moving both keeps the two cycles' word addresses EQUAL, which
                 -- is what lets hart_tile absorb LR_READ into the EXECUTE ack
                 -- (hart_tile.vhd:682-683) exactly as it does today.
                 --
                 -- Canonical `lr.w` has rs2 = x0, so rs1 + 0 = rs1: today's
                 -- behaviour for every assembler-emitted LR is unchanged, and
                 -- Spike decodes lr.w ignoring rs2 -- forcing the address (rather
                 -- than trapping the encoding) is what keeps lockstep clean.
                 -- NOTE: the ALU_Result arm below keeps its `current_state =
                 -- LR_READ` term, now SHADOWED by the arm above. It is left in
                 -- place as the AMO_READ/AMO_WRITE symmetry it was written as;
                 -- removing it would change nothing.
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
    -- same condition that drives the store lanes in SC_CHECK; the old valid-only
    -- term let an address-mismatched SC report success while skipping the write)
    -- AND the EXTERNAL verdict (sc_fail_ext, from the global resv_unit for shared
    -- addresses; ties '0' for private/single-master use).
    -- ***** SC-SUCCESS PREDICATE: FOUR COPIES, ALL IDENTICAL *****
    -- `reservation_valid = '1' and reservation_addr = rs1_value` is duplicated at
    -- FOUR sites. Change all four or none -- a divergence between them is SILENT.
    -- By role, not line number (three of the four WRAP across lines, so a
    -- line-based grep under-reports them):
    --   1. the data_addr mux's SC_CHECK term  (steers rs1_value)
    --   2. THIS term, amo_phase               ("101" SC-success, with sc_fail_ext)
    --   3. lr_sc_bus                          ("10" SC-write tag)
    --   4. the SC_CHECK FSM arm               (store lanes + mem_access_instr)
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
    -- P3: a PMP-DENIED LR issues no read transaction at all (mem_access_instr
    -- is forced '0', so data_addr stays on the fetch fall-through). Without
    -- this qualifier the "01" tag would ride that FETCH transaction into the
    -- arbiter and arm a global reservation on the fetch address. pmp_d_deny is
    -- statically '0' when ENABLE_PMP is false => the OFF tag is unchanged.
    -- ***** SC-SUCCESS PREDICATE: FOUR COPIES, ALL IDENTICAL *****
    -- `reservation_valid = '1' and reservation_addr = rs1_value` is duplicated at
    -- FOUR sites. Change all four or none -- a divergence between them is SILENT.
    -- By role, not line number (three of the four WRAP across lines, so a
    -- line-based grep under-reports them):
    --   1. the data_addr mux's SC_CHECK term  (steers rs1_value)
    --   2. amo_phase                          ("101" SC-success, with sc_fail_ext)
    --   3. THIS term, lr_sc_bus               ("10" SC-write tag)
    --   4. the SC_CHECK FSM arm               (store lanes + mem_access_instr)
    lr_sc_bus <= "01" when current_state = EXECUTE and lr_op = '1' and pmp_d_deny = '0' else
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
    -- F-D2-1 (R-D2-3(3)): dbg_irq_block suppresses STANDARD delivery in debug
    -- mode. It sits here, at the single source, rather than on the 13
    -- recognition arms -- a fix applied arm-by-arm is a fix that can be
    -- half-applied, and the detector is built to catch exactly that.
    -- The interrupt stays LEVEL-pending; it is delivered after the dret,
    -- which is the required behaviour, not a side effect.
    std_irq_take <= '1' when (std_mode = '1' and dbg_irq_block = '0' and
                              trap_mstatus_mie = '1' and
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
    -- P3 adds three EXCEPTION classes to this mux. Priority is EXACTLY the FSM
    -- arm order (a cause mux that disagrees with the arm order silently
    -- mislabels traps):
    --   1. instruction access fault -- FIRST in EXECUTE, because the word
    --      being decoded is the PARK word: `trap` / ecall_op / ebreak_op are
    --      all meaningless on it.
    --   2. the existing misaligned-PC / illegal / ECALL / EBREAK classes.
    --   3. load/store access fault -- the FSM arm sits after mret_op, and it
    --      also fires from the SEQUENCER states (CBOZ_WRITE/ZCM_*), which is
    --      why it is not qualified by `current_state = EXECUTE`.
    --   4. anything else => interrupt.
    -- The three original arms gain an explicit `current_state = EXECUTE`
    -- qualifier that the old leading `/= EXECUTE` term supplied implicitly --
    -- with the PMP terms tied off the result is bit-identical.
    mtrap_disp_int <=
        '0' when (ENABLE_PMP and current_state = EXECUTE and pmp_f_deny_r = '1') else         -- 1 instr access fault
        '0' when (current_state = EXECUTE and (not ENABLE_COMPRESSED) and pc(1) = '1') else   -- instruction-address-misaligned
        '0' when (current_state = EXECUTE and
                  (trap = '1' or ecall_op = '1' or ebreak_op = '1')) else                     -- illegal / ECALL / EBREAK
        '0' when (pmp_d_deny = '1') else                                                      -- 5/7 load-store access fault
        '1' when (current_state /= EXECUTE) else                                 -- MEMORY_WAIT/DIV_DONE/AMO_*/SLEEPING/... => interrupt
        '1';                                                                     -- EXECUTE + none of the above => interrupt

    mtrap_disp_code <=
        x"1" when (ENABLE_PMP and current_state = EXECUTE and pmp_f_deny_r = '1') else        -- 1  instruction access fault
        x"0" when (current_state = EXECUTE and (not ENABLE_COMPRESSED) and pc(1) = '1') else  -- 0  instr addr misaligned
        x"2" when (current_state = EXECUTE and trap = '1') else                               -- 2  illegal instruction
        -- P2: the ECALL cause is the CURRENT privilege (p0_specs.md 2.2 rows
        -- "ECALL from M" / "ECALL from U"). trap_priv_mode is stuck '1' (M) on
        -- any ENABLE_UMODE=false build, so this collapses to the P1 constant 11.
        x"8" when (current_state = EXECUTE and ecall_op = '1' and trap_priv_mode = '0') else  -- 8  ecall from U
        x"B" when (current_state = EXECUTE and ecall_op = '1') else                           -- 11 ecall from M
        x"3" when (current_state = EXECUTE and ebreak_op = '1') else                          -- 3  breakpoint
        -- P3 data-side access faults. The class (not the permission need) picks
        -- the code: store / SC / AMO / cbo.zero / cm.push => 7, load / LR /
        -- cm.pop / Zcmt table fetch => 5.
        x"7" when (pmp_d_deny = '1' and pmp_d_st_class = '1') else                            -- 7  store/AMO access fault
        x"5" when (pmp_d_deny = '1') else                                                     -- 5  load access fault
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
    --   P3: for the three ACCESS-FAULT causes mtval is the FAULTING ADDRESS,
    --           taken from the dispatch-edge latch (mtrap_val_r) because
    --           neither pmp_d_addr nor pmp_f_addr_r is stable during MTRAP_SV.
    --           mtrap_val_r is all-zero on an ENABLE_PMP=false build.
    trap_value_val <= instr_curr_prev when (mtrap_cause_int = '0' and mtrap_cause_code = x"2") else
                      pc              when (mtrap_cause_int = '0' and mtrap_cause_code = x"0") else
                      mtrap_val_r     when (ENABLE_PMP and mtrap_cause_int = '0' and
                                            (mtrap_cause_code = x"1" or mtrap_cause_code = x"5" or
                                             mtrap_cause_code = x"7")) else
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
    -- F-D2-1 (R-D2-3(3)): the SAME neutralization mechanism, extended to debug
    -- mode. Masking every enable pins the handler FSM in IDLE, so irq_save can
    -- never fire while the hart is in debug mode -- the legacy half of the
    -- fix, and it reuses the proven idiom rather than inventing a second one.
    -- The IRQ sources are LEVEL, so nothing is lost: unmasking at the dret
    -- re-presents whatever is still pending.
    -- Statically the identity function when ENABLE_DEBUG is off (dbg_irq_block
    -- folds to '0'), so an OFF build keeps exactly the P1 expression.
    irq_en_eff <= irq_en when (std_mode = '0' and dbg_irq_block = '0')
                  else (others => '0');

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
    -- D1 DEBUG-MODE GLUE (ENABLE_DEBUG)
    -- ==========================================
    -- ENABLE_DEBUG REQUIRES ENABLE_TRAPCSR, and the coupling is real, not
    -- tidiness: `ebreak_op` and the whole SYSTEM PRIV_FN3 legality arm are
    -- ENABLE_TRAPCSR-gated in maindec, so on a trapCsr-OFF build `ebreak` does
    -- not decode at all and dcsr.ebreakm would have nothing to interpose on --
    -- a chip with a Debug Module that cannot recognise a software breakpoint
    -- (D0/P2 N8). generate.py's validator enforces the implication for every
    -- config; this assert catches anyone instantiating the core directly.
    assert not (ENABLE_DEBUG and not ENABLE_TRAPCSR)
        report "vesta: ENABLE_DEBUG requires ENABLE_TRAPCSR (ebreak and the "
             & "SYSTEM PRIV arm do not decode without it)"
        severity failure;

    -- THE HALT TAKE. Qualified by NEITHER mstatus.MIE NOR mtrapctl.LEGACY: a
    -- halt request is unmaskable and must fire in a legacy-mode build exactly
    -- as in a standard-delivery one. The only qualifier is `not debug_mode` --
    -- a hart already in debug mode must not re-enter and overwrite its own dpc.
    -- Three sources, one signal, because all three land on the same 14 FSM
    -- recognition points; the CAUSE mux below is what tells them apart.
    -- WAIT-FOR-RELEASE: ONE ENTRY PER ASSERTION OF dbg_haltreq.
    -- THE HAZARD, measured 2026-08-05 before this term existed. dbg_haltreq is
    -- a LEVEL, and a debugger cannot drop it until it has SEEN dbg_halted --
    -- an observation that costs a JTAG round trip in silicon and a polling
    -- interval in a testbench. Without this mask the hart re-entered debug the
    -- instant each `dret` retired, walking forward exactly one instruction per
    -- round trip and rewriting its own dpc/dcsr every time. Measured: the
    -- halt-reachability instrument's running victim never reached the store
    -- that proves it resumed, because it was still bouncing in and out of the
    -- stub when the orchestrating hart read the result; and single-step is
    -- outright IMPOSSIBLE that way, because the second entry reports cause
    -- haltreq instead of cause step and the dpc ledger never advances by 4.
    -- THE FIX IS THE ARBITER'S, VERBATIM. mp_arbiter masks a served master via
    -- WAIT-FOR-RELEASE -- eligible again only after its req is OBSERVED low --
    -- because the M5a one-pick mask leaked ghost transactions from exactly this
    -- shape: a request line that is legitimately still high after it has been
    -- served. A halt request is the same object. One flop, on the FREE-RUNNING
    -- clk so a hart whose clk_cpu is gated cannot miss the release.
    -- RELEASE WINS over set, so a debugger that drops and re-raises the line
    -- gets a second halt immediately; only a CONTINUOUS assertion is collapsed
    -- to one entry.
    -- The other two entry sources need no mask: dbg_rsthalt_r is disarmed by
    -- the first entry (once per reset), and dbg_step_armed is cleared by the
    -- entry it causes.
    -- NOT PINNED BY d1_spec.md, which says only "dbg_haltreq (in, level)" --
    -- recorded here as a DESIGN DECISION, not as a reading of the spec.
    dbg_haltreq_eff <= dbg_haltreq and not dbg_req_mask;

    dbg_halt_take <= '1' when (ENABLE_DEBUG and debug_mode = '0' and
                               (dbg_haltreq_eff = '1' or dbg_rsthalt_r = '1' or
                                dbg_step_armed = '1'))
                     else '0';
    dbg_step_take <= '1' when (ENABLE_DEBUG and debug_mode = '0' and
                               dbg_step_armed = '1')
                     else '0';
    dbg_halt_pend <= dbg_halt_take;

    -- THE EXCEPTION TAKE (D2, F-D2-0, ruled R-D2-3(1)).
    -- MEASURED at abf9fac, both delivery polarities, before this existed: a
    -- non-ebreak synchronous exception taken in debug mode did NOT re-enter.
    -- Legacy polarity it wedged in the terminal TRAP_STATE with dbg_halted
    -- still asserted and trap_flag latched; standard polarity it vectored to
    -- mtvec -- whose RESET VALUE is 0, i.e. the shared boot ROM -- re-ran the
    -- ROM's not-hart-0 park sequence and extinguished, all with debug_mode
    -- still '1'. That second outcome is UNRECOVERABLE: dbg_halt_take is
    -- qualified by debug_mode = '0', so no fresh halt request can reach a
    -- hart that has left its debug code this way, and only a dret nothing
    -- will ever execute clears the mode.
    -- The fix redirects every synchronous-exception dispatch to DBG_JUMP --
    -- the state that ALREADY means "re-enter, dpc and dcsr survive" (see its
    -- arm below). So this adds no state, no flop and no commit interface: the
    -- 18 new arms declare mem_access_instr only, exactly as the
    -- ebreak-in-debug-mode arm beside them does, and inherit the fail-safe
    -- commit defaults from the S2 structural block.
    -- WHY NOT INTERCEPT IN THE SINK STATES. TRAP_STATE unconditionally drives
    -- trap_flag <= '1' (a hart_tile output the testbench monitors), so a
    -- debug-mode fault must never ENTER it; and MTRAP_SV's CSR writeback
    -- rides trap_entry_we, a one-shot of that state, so mepc/mcause/mtval
    -- would already be corrupted before any redirect. Both were rejected on
    -- those measurements, not on taste.
    -- NOT REDIRECTED, and ruled so rather than left silent (R-D2-3(2)): the
    -- four mret_op blocks, whose legacy arm also lands in TRAP_STATE. mret is
    -- not an exception -- in debug mode it executes architecturally with
    -- debug_mode unchanged, which is Spike-consistent, and the trampoline
    -- never executes one.
    -- Statically '0' when ENABLE_DEBUG is off, so every new arm constant-
    -- folds and the OFF FSM is bit-identical -- the dbg_halt_take argument.
    dbg_exc_take <= '1' when (ENABLE_DEBUG and debug_mode = '1') else '0';

    -- THE INTERRUPT BLOCK (D2, F-D2-1, ruled R-D2-3(3)).
    -- d1_spec.md 2 froze "interrupts NOT taken (all recognition qualified by
    -- `not debug_mode`)" and the RTL never carried the qualifier: dbg_halt_take
    -- sits ABOVE irq_save and std_irq_take in all 13 recognition chains but
    -- does not BLOCK them -- in debug mode it is '0' and the chain falls
    -- straight through to the interrupt arms. MEASURED: a halted hart spinning
    -- at DEBUG_ENTRY_ADDR reached IRQ_JUMP 200 ns after msip rose, vectored
    -- through IVT slot 83 into the ROM's loader ISR and looped there, with
    -- dbg_halted asserted throughout.
    -- The suppression is applied at the two SOURCES rather than at the 13
    -- chains, so it cannot be half-applied: see std_irq_take and irq_en_eff.
    -- Statically '0' when ENABLE_DEBUG is off; both consumers then reduce to
    -- their pre-D2 expressions exactly.
    dbg_irq_block <= '1' when (ENABLE_DEBUG and debug_mode = '1') else '0';

    -- THE EBREAK TAKE. dcsr.ebreakm RESETS 0 and is writable only from debug
    -- mode, so no M-mode software can ever arm it -- which is what makes
    -- "ebreak takes an ordinary breakpoint exception" the standing behaviour
    -- and dbgdenymp.S's hart 3 a real detector rather than a tautology.
    -- ebreaku rides ENABLE_UMODE (dcsr_ebreaku is stuck '0' without it).
    -- The debug_mode term is the re-entry clause (d1_spec.md 2): an ebreak
    -- executed BY debug code always re-enters, regardless of ebreakm.
    dbg_ebreak_take <= '1' when (ENABLE_DEBUG and
                                 (debug_mode = '1' or
                                  dcsr_ebreakm = '1' or
                                  (ENABLE_UMODE and trap_priv_mode = '0' and
                                   dcsr_ebreaku = '1')))
                       else '0';

    -- Dispatch-cycle cause classification. PRIORITY MIRRORS THE FSM ARM ORDER
    -- EXACTLY -- the ebreak arm sits above the halt arm in the EXECUTE decode
    -- tree, so ebreak is first here. A cause mux that disagrees with the arm
    -- order silently mislabels entries (the mtrap_disp_code lesson).
    dbg_disp_cause <=
        "001" when (current_state = EXECUTE and ebreak_op = '1' and
                    dbg_ebreak_take = '1') else                 -- 1 ebreak
        "101" when (dbg_rsthalt_r = '1') else                   -- 5 resethaltreq
        "011" when (dbg_haltreq_eff = '1') else                 -- 3 haltreq
        "100" when (dbg_step_take = '1') else                   -- 4 step
        "011";                                                  -- default: haltreq

    -- The cause LATCH lives inside gen_debug below, not here. Its write
    -- condition is statically false on an OFF build, so Genus would very
    -- likely constant-propagate it away -- but "very likely pruned" is not the
    -- standard this file holds itself to. gen_trapcsr_wb/gen_trapcsr_wb_off is
    -- the house pattern precisely because it makes the OFF netlist identical BY
    -- CONSTRUCTION rather than by unloaded-logic removal, and the D1 inertness
    -- claim is the programme's crown jewel. Same for every other debug flop.

    -- dpc, valid throughout DBG_SV. A SYNCHRONOUS ebreak reports its OWN
    -- address (pc; pc_en is '0' from the dispatch edge on, so pc still holds
    -- it) -- NOT the instruction after, which is why debug code that wants to
    -- resume past an ebreak must add 4 itself. Every other cause is taken
    -- BETWEEN instructions, so the resume PC is pc_next_reg -- the same word
    -- MTRAP_SV uses as mepc for an interrupt.
    dbg_pc_val <= pc when dbg_cause_r = "001" else pc_next_reg;

    -- The one-shots, and the halt-on-reset / single-step state. All inside the
    -- generate pair so an OFF netlist carries no extra flops at all and every
    -- strobe is hard-tied '0' -- the gen_trapcsr_wb pattern, verbatim.
    dbg_sv_lvl  <= '1' when current_state = DBG_SV  else '0';
    dbg_ret_lvl <= '1' when current_state = DBG_RET else '0';

    gen_debug: if ENABLE_DEBUG generate
        -- The dispatch-cycle cause latch. 3 flops on clk_cpu; the 32-bit dpc
        -- value is NOT registered -- it is re-derived from pc / pc_next_reg,
        -- both provably held through DBG_SV.
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

        -- HALT ON RESET. Armed by reset, disarmed by the first debug entry.
        -- While armed, dbg_rsthalt_r simply follows the (boundary-registered)
        -- request line, so the halt is taken at the first recognition site the
        -- hart reaches -- i.e. before it retires anything of its own. It is
        -- held stable across the entry, which is what lets the cause mux report
        -- 5 rather than 3. On the free-running clk, so a hart whose clk_cpu is
        -- still gated cannot miss the arming.
        -- The wait-for-release flop. Clear (release observed) has PRIORITY.
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
                    if dbg_entry_we_sig = '1' then
                        dbg_rst_armed <= '0';
                        dbg_rsthalt_r <= '0';
                    else
                        dbg_rsthalt_r <= dbg_resethaltreq;
                    end if;
                end if;
            end if;
        end process;

        -- SINGLE-STEP ARMING. Set on the DRET cycle iff dcsr.step is set --
        -- read at that edge, so debug code that CLEARS step before its dret
        -- (entry 5 of dbgstepmp.S) resumes free-running. Cleared by the entry
        -- it causes. The two conditions cannot coincide: one needs
        -- current_state = DBG_RET, the other next_state = DBG_SV from another
        -- state. On clk_cpu, because it is sampled by the FSM.
        -- NOTE step is NOT active in debug mode: dbg_step_take carries
        -- `not debug_mode`, so the several instructions the debug stub
        -- executes after `csrsi dcsr, 4` do not step.
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

    -- HALTED IS A STATE, NOT A LEVEL FOLLOWER. It is simply "this hart is in
    -- debug mode", so it rises with the entry edge and stays high after the
    -- debugger drops dbg_haltreq -- only a `dret` lowers it. A build that
    -- wired dbg_halted <= dbg_haltreq would pass an entry test and fail
    -- exactly here (dbg_iface_tb check C).
    dbg_halted <= debug_mode;

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
    -- P3 extends the SAME rule one cycle EARLIER. A PMP-denied instruction
    -- FETCH never issued, so the EXECUTE cycle that would have consumed it is
    -- decoding the PARK word (PC_RST_VAL's contents) instead of a real
    -- instruction. reg_write_dp / mem_access_instr / wen / pc_en are all
    -- forced by the FSM arm, but the same four decode outputs that bypass the
    -- FSM (csr_valid -> csr_unit's WRITE ENABLE, isr_ret, sleep_rq/wake_rq)
    -- would otherwise commit a side effect for an instruction the hart is not
    -- allowed to execute -- the identical escape shape privucsr CHECK 27
    -- found in P2. pmp_if_squash is statically '0' when ENABLE_PMP is false,
    -- so dec_squash degenerates to trap_entry_seq and the OFF build is
    -- bit-identical.
    dec_squash     <= trap_entry_seq or pmp_if_squash;
    -- ==========================================
    -- W2 DECODE-DISPATCH QUALIFICATION (F7, F3, F3+)
    -- ==========================================
    -- dec_squash is a STATE BLACKLIST, and a blacklist is only ever as good as
    -- the list. It named the P1/P3 trap-entry states and missed six legacy ones
    -- (IRQ_SV, IRQ_JUMP, FENCE_WAIT, PAUSE_WAIT, WRS_WAIT, TRAP_STATE -- F3) and
    -- the compressed half-fetch bubble inside EXECUTE itself (F7). In every one
    -- of those cycles instr_curr is NOT the instruction the hart is dispatching:
    -- it is either the raw bus word (IRQ_SV, :1484) or the PREVIOUS, already
    -- retired encoding (instr_curr_prev, :1486/:1490+). Any strobe that bypasses
    -- the FSM's own suppression therefore fires for an instruction that is not
    -- executing.
    --
    -- dec_dispatch replaces the blacklist with a POSITIVE qualification: name
    -- the ONE cycle in which a decoded instruction may commit a bypassing side
    -- effect. That is closed against the seventh state nobody wrote down.
    -- Term by term:
    --   current_state = EXECUTE
    --       EXECUTE is the only state in which an explicit CSR write commits
    --       (v1_retire_enumeration.md 5 row 3, re-verified against csr_unit's
    --       write process: the only other architectural CSR effects are
    --       fp_flags_we, trap_entry_we and mret_we, each on its own dedicated
    --       strobe). Every other state either holds instr_curr_prev -- whose
    --       encoding cannot be a CSR/sleep op, because those states are entered
    --       only from a load/store, div, FP or trap dispatch -- or decodes a
    --       live word that is not executing at all.
    --   dec_squash = '0'
    --       inherits P2's trap-entry suppression and P3's PMP park squash
    --       unchanged (:1932-1946). EXECUTE is reachable with pmp_if_squash='1'.
    --   not (pc(1)='1' and quadrant_upper="11" and repeat_if='0')
    --       shape E, the 32-bit split-fetch bubble (the SHAPE_E arm of the
    --       EXECUTE dispatch tree). That cycle's reg_write_dp/pc_en/wen are
    --       driven -- by the S-series commit block since S2 commit 2, to the
    --       same fail-safe values the arm forced directly before it -- but
    --       NOTHING drives csr_valid, while instr_curr is HELD at the previous
    --       instruction (:1486) -- so a just-retired `csrrw rd,csr,rd` re-fires
    --       csr_write_en with csr_wdata read LIVE from rf[rs1], reverting the
    --       CSR to its own old value (F7).
    --       The legitimate dispatch of a straddling 32-bit instruction is the
    --       repeat_if='1' completion cycle, which this term keeps. Copied
    --       verbatim from fp_op_latch (:1338-1339) and fp_flags_we (:1365),
    --       where this exact class was already fixed -- and not applied here.
    --   (ENABLE_COMPRESSED or pc(1)='0')
    --       shape Q: on a non-C build a halfword-aligned PC is an
    --       instruction-address-misaligned TRAP arm (:2320), never a dispatch.
    --       Statically true on the Castalia/Argus C-on builds, so this term
    --       cannot change the shipping configuration. Also from fp_flags_we
    --       (:1364).
    dec_dispatch   <= '1' when (current_state = EXECUTE
                                and dec_squash = '0'
                                and not (pc(1) = '1' and quadrant_upper = "11" and repeat_if = '0')
                                and (ENABLE_COMPRESSED or pc(1) = '0'))
                      else '0';
    csr_valid_eff  <= csr_valid and dec_dispatch;
    -- isr_ret_eff is DELIBERATELY NOT re-qualified (W2 ruling, spec 1).
    -- irq_handler's sm_proc runs on the FREE-RUNNING clk and consumes isr_ret as
    -- a LEVEL, both inside WAIT_EOI (irq_handler.vhd:355) and in
    -- next_state_logic (:431) to leave it. instr_curr holds the iret encoding
    -- across EXECUTE -> MEMORY_WAIT -> IRQ_REST, so isr_ret_eff is high for that
    -- whole span; narrowing it to EXECUTE would shrink the window over which the
    -- EOI and its exit condition are asserted, on the one path where a mistake
    -- hangs the chip, in exchange for no finding -- nothing in the ledger claims
    -- isr_ret leaks. It IS an instance of "a level consumed on the free-running
    -- clock", but unlike F1+ it is IDEMPOTENT (the EOI clears a flag, it does
    -- not increment a counter), so it integrates nothing and is not a defect.
    isr_ret_eff    <= isr_ret   and not dec_squash;

    -- The entry-reason flop. Set at the WFI dispatch edge, cleared at EVERY
    -- SLEEPING exit (whichever arm takes it). wfi_enter is driven ONLY from the
    -- real-dispatch decode arms of EXECUTE, so it can never be set on a
    -- compressed half-fetch cycle (kickoff 3b class 5), and it cannot coincide
    -- with the clear (that needs current_state = SLEEPING).
    -- ==========================================
    -- P3 PMP CHECK POINTS (ENABLE_PMP) -- p0_specs.md §4.1 "vesta integration"
    -- ==========================================
    -- THE DATA ADDRESS UNDER TEST. Deliberately NOT `data_addr`: data_addr is
    -- a function of mem_access_instr, which the denial has to drive -- reading
    -- it back here would be a combinational loop. Every term below is either a
    -- STATE-selected registered sequencer address or a regfile/ALU export that
    -- the data_addr mux would have chosen in the same cycle:
    --   EXECUTE + LR/SC/AMO : rs1_value  (the M4b/M8 phase-independent address --
    --                      ALU_Result holds rs1<op>rs2 in those cycles). F6 (fix
    --                      pass W4) ADDED lr_op here: data_addr's EXECUTE term
    --                      now takes rs1_value for an LR too (:1857), and this
    --                      mux exists precisely to mirror data_addr's choice. A
    --                      malformed `lr.w` with a non-zero rs2 field would
    --                      otherwise be PMP-checked at rs1+reg[rs2] while the
    --                      access issued at rs1 -- check and access disagreeing
    --                      is the one thing a pre-issue check may never do.
    --                      (ENABLE_PMP is false in every standing build, so this
    --                      arm folds away there; it is correctness for the
    --                      knobs-on build, not a default-build change.)
    --   EXECUTE + load/store : ALU_Result (rs1+imm, exactly data_addr's term)
    --   CBOZ_WRITE / ZCM_PUSH_ST / ZCM_POP_LD / ZCM_JT_LD : the sequencer's own
    --                      generated address for THIS step (§4 "each generated
    --                      address is checked pre-issue at its own dispatch").
    -- In every other cycle the value is don't-care because pmp_d_active is '0'.
    pmp_d_addr <= cboz_zero_addr when (current_state = CBOZ_WRITE) else
                  zcm_mem_addr   when (current_state = ZCM_PUSH_ST or current_state = ZCM_POP_LD) else
                  zcm_jt_addr    when (current_state = ZCM_JT_LD) else
                  rs1_value      when (current_state = EXECUTE and (amo_op = '1' or sc_op = '1'
                                                                    or lr_op = '1')) else
                  ALU_Result;

    -- Permission NEEDS (frozen §4: LR/SC/AMO drive BOTH R and W). A plain
    -- access is a store iff its byte-lane enables are not all inactive --
    -- wen_controller is "1111" for every load and for LR (maindec:1135).
    --
    -- P3 red-team F2/F3 FIX: the `isr_ret` (iret) decode ALSO raises
    -- read_data_flag => mem_access_controller (maindec:1186), so without a
    -- guard iret looks like a load here and PMP-checks a PHANTOM read at its
    -- ALU_Result (= 0 for the canonical encoding). A locked/no-perm entry over
    -- that address then faults EVERY M-mode iret (an M-mode DoS -- F2). iret is
    -- u-gated (M-mode only) and its real transaction is the return-PC pop off
    -- the PRIVATE stack (TCM 0x8000-0xBFFF by the sp-validity contract), never
    -- a shared-window side-effecting address -- so legacy interrupt entry/
    -- return stack traffic is deliberately OUT of PMP scope (documented,
    -- p0_specs.md §4.1). `and isr_ret = '0'` removes iret from the data check
    -- entirely (the IRQ_SV push / IRQ_REST pop states already carry no PMP
    -- term -- F3, the same exemption).
    --
    -- F12 RESIDUE (fix pass W4, COMMENT ONLY -- deliberately not changed).
    -- That `and isr_ret = '0'` guard SILENTLY STOPS APPLYING IN U-MODE: isr_ret
    -- is u-gated (maindec:1027) so it reads '0' there, while
    -- mem_access_controller is NOT u-gated and still reads '1' for the iret
    -- encoding. A U-mode iret on an ENABLE_PMP build therefore raises
    -- pmp_d_active and, over a denying region, pmp_d_deny. It is INERT TODAY --
    -- and only by ARM ORDERING: the `trap = '1'` arm is the FIRST arm of all
    -- four EXECUTE shapes (:2594/:2867/:2982/:3145), above the D5 pmp_d_deny arm
    -- (:2637 etc.), and a U-mode CUSTOM opcode is illegal (maindec:849-856), so
    -- the illegal-instruction trap wins and reports cause 2. W4 MEASURED that
    -- (mcause 2, mepc = the iret's own pc, mtval = its own encoding, bus
    -- silent) on an ENABLE_UMODE build; the ENABLE_PMP leg is argued from
    -- source, not measured. IF A FUTURE CHANGE EVER HOISTS THE PMP DATA ARM
    -- ABOVE THE TRAP ARM, a U-mode iret starts reporting cause 5 instead of
    -- cause 2. The one-line repair at that point is `and isr_ret_arch = '0'`
    -- against a NON-u-gated iret decode -- not a reordering.
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

    -- ACCESS CLASS for the cause code (see the signal declaration): LR is a
    -- READ that checks R&W, so it is deliberately absent from this term.
    pmp_d_st_class <= '1' when (current_state = EXECUTE and (sc_op = '1' or amo_op = '1')) else
                      '1' when (current_state = EXECUTE and mem_access_controller = '1'
                                and wen_controller /= "1111") else
                      '1' when (current_state = CBOZ_WRITE or current_state = ZCM_PUSH_ST) else
                      '0';

    -- "a data transaction would issue this cycle". NOTE this is '1' on a
    -- compressed HALF-FETCH cycle too (instr_curr still holds the PREVIOUS,
    -- already-retired instruction there -- kickoff §3b class 5). That is
    -- harmless BY CONSTRUCTION: the half-fetch branch of the EXECUTE decode
    -- tree has no PMP arm (it is a separate else-branch with an unconditional
    -- next_state <= EXECUTE), so pmp_d_deny can never dispatch a trap from it,
    -- and nothing else consumes it in EXECUTE. The qualifier is the FSM arm
    -- placement, exactly as amo_lock qualifies its EXECUTE term.
    pmp_d_active <= pmp_d_rd or pmp_d_wr;
    pmp_d_deny   <= '1' when (ENABLE_PMP and pmp_d_active = '1' and pmp_d_grant = '0') else '0';

    -- FETCH side. pc_next IS the fetch address: the data_addr mux falls
    -- through to it in every cycle that issues an instruction fetch.
    --
    -- P3 red-team F1 FIX: the fetch is X-checked at pmp_f_priv, which is the
    -- current privilege (trap_priv_mode) EXCEPT during MTRAP_RET. MTRAP_RET is
    -- the one state that both issues a fetch (pc_next = mepc, pc_en='1') AND
    -- lowers privilege on the SAME edge that latches the verdict -- so the
    -- fetch it issues is CONSUMED at the post-MRET privilege (MPP), and
    -- checking it at the still-current M would let the first instruction after
    -- an MRET into U run with X denied (the F1 escape). mret_priv_m is MPP
    -- mapped, read combinationally before the pop, i.e. the return privilege.
    -- Every other privilege change RAISES privilege (trap entry -> M), so its
    -- issued fetch is checked at the stricter old privilege -- the safe
    -- direction; only the LOWERING MRET case needs this override.
    pmp_f_priv <= mret_priv_m when current_state = MTRAP_RET else trap_priv_mode;

    pmp_f_deny <= '1' when (ENABLE_PMP and pmp_f_grant = '0') else '0';

    pmp_if_squash <= '1' when (ENABLE_PMP and current_state = EXECUTE and pmp_f_deny_r = '1')
                     else '0';

    -- PARK SELECT. Three cases, all ENABLE_PMP-gated:
    --   (a) pmp_f_deny      -- the address this cycle would fetch is X-denied.
    --   (b) pmp_if_squash   -- the EXECUTE cycle that consumes a denied fetch:
    --       its pc_next is derived from the PARK word's decode, i.e. from an
    --       instruction the hart never legitimately executed. Parking keeps
    --       that arbitrary address off the bus.
    --   (c) MTRAP_SV of an instruction-access-fault entry -- the trap-entry
    --       RE-PRESENTATION window (p0_specs.md §4.1 / kickoff §6b): pc_next
    --       there is pc_next_reg, registered from (b)'s cycle, and privilege
    --       has already flipped to M so the fetch check would now GRANT it.
    --       MTRAP_JUMP is deliberately NOT parked -- it issues the mtvec fetch.
    -- All three park on the SAME address, so hart_tile's ack latch
    -- (sh_acked_addr/sh_acked_we) absorbs them into ONE benign ROM read.
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
                -- FETCH: X at the effective fetch privilege (current priv,
                -- or the return privilege during MTRAP_RET -- F1). Never
                -- MPRV-redirected (MPRV governs data accesses only).
                f_addr        => pc_next,
                f_priv_m      => pmp_f_priv,
                f_grant       => pmp_f_grant,
                -- DATA: R/W at the EFFECTIVE data privilege (mstatus.MPRV).
                d_addr        => pmp_d_addr,
                d_priv_m      => eff_data_priv_m,
                d_read        => pmp_d_rd,
                d_write       => pmp_d_wr,
                d_grant       => pmp_d_grant
            );

        -- The fetch-check pipeline. Sampled on EVERY clk_cpu edge, which is
        -- what makes the "previous core cycle's fetch" invariant hold without
        -- enumerating states: whenever the FSM redirects the PC (MTRAP_JUMP ->
        -- mtvec, MTRAP_RET -> mepc, IRQ_JUMP -> ivt_entry, ZCM_RET/ZCM_JT_WB,
        -- SLEEPING/WRS_WAIT resume) the redirected address is on pc_next in
        -- that very cycle and is therefore the value this flop carries into
        -- the EXECUTE that consumes it.
        pmp_ifetch_proc: process(clk_cpu, resetn)
        begin
            if resetn = '0' then
                pmp_f_deny_r <= '0';
                pmp_f_addr_r <= (others => '0');
            elsif rising_edge(clk_cpu) then
                pmp_f_deny_r <= pmp_f_deny;
                pmp_f_addr_r <= pc_next;
            end if;
        end process;

        -- mtval latch, on the SAME edge and the SAME condition as
        -- mtrap_cause_proc (kept a separate process so the 32 flops are inside
        -- the generate and an OFF build carries none of them).
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
        -- Grant everything, no flops, no unit: the OFF netlist folds to today's
        -- and the OFF cell lists need no pmp_unit entry.
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
                             wfi_op, std_wfi_wake,
                             pmp_f_deny_r, pmp_d_deny,
                             -- D1: THE FOUR DEBUG DECISION SIGNALS, and leaving
                             -- them out is a SIMULATION-ONLY defect that hides
                             -- in exactly the two states debug exists to reach.
                             -- MEASURED (2026-08-05): with these absent, a halt
                             -- request diverted a RUNNING hart correctly --
                             -- EXECUTE re-evaluates this process every cycle
                             -- anyway, because pc/instr/... are in the list --
                             -- while a hart parked in SLEEPING or wedged in
                             -- TRAP_STATE sat with dbg_halt_take = '1',
                             -- en_clk_cpu ungated to '1', and next_state stuck
                             -- at its own value FOREVER. Nothing else in the
                             -- list moves in an absorbing state, so the process
                             -- never re-ran to see the request. Synthesis
                             -- ignores sensitivity lists entirely, so the
                             -- netlist would have been RIGHT and every
                             -- behavioural gate WRONG -- the worst direction.
                             dbg_halt_take, dbg_ebreak_take, dbg_exc_take, dret_op, debug_mode,
                             -- R-S2-2: THE COMMIT TAIL READS THESE FOUR.  A
                             -- same-process signal read returns the PREVIOUS
                             -- delta's value, so without these entries the
                             -- process does not re-evaluate when intent settles
                             -- and a migrated shape can be driven from STALE
                             -- intent (a retiring instruction's ci_pc_advance='1'
                             -- leaking into SHAPE_E's bubble cycle and advancing
                             -- the PC mid-instruction).  Genus infers the intended
                             -- logic either way, so RTL sim would be the lying
                             -- instrument.  Verified before adding them: every
                             -- ci_* right-hand side is a literal or one of
                             -- reg_write_ctrl / wen_controller / amo_wen /
                             -- zcm_jt_link, none of which is a function of the
                             -- four owned outputs or of any ci_* -- no feedback,
                             -- so the extra evaluation settles in one delta.
                             ci_rd_commit, ci_sp_commit, ci_st_lanes, ci_pc_advance)
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
            -- RESET-VALUE EXACTNESS (spec section 3, ruling R-S1-1a) -- the
            -- obligation S1 deferred, discharged here by deliberately changing
            -- NOTHING above.  Two of the reset branch's four owned-net drives
            -- are NOT the fail-safe intent values: `wen <= wen_controller` (not
            -- all-ones) and `pc_en <= '1'` (not hold).  The commit block sits in
            -- the ELSE branch, so it cannot reach reset and cannot reproduce
            -- them -- therefore the four reset drives STAY, exactly as written.
            -- Spec section 3 anticipated this: "if that requires keeping two
            -- explicit reset lines, keep them -- a simple edit beats a clever
            -- one."  This is why the final census is 4 reset + 4 block = 8, and
            -- why "one assignment site per signal" means one OUTSIDE reset.
            -- The intent defaults below are still FAIL-SAFE (spec section 2), so
            -- intent and the live nets disagree during reset by construction --
            -- which is why the shadow checker is qualified with resetn='1'.
            ci_rd_commit  <= '0';
            ci_sp_commit  <= '0';
            ci_st_lanes   <= "0000";
            ci_pc_advance <= '0';

        else
            -- Default signal values.  NOTE: the four commit-block nets
            -- (reg_write_dp / sp_write_en / wen / pc_en) are deliberately ABSENT
            -- from this list.  They are driven unconditionally by the commit
            -- block at the end of this branch, from the ci_* intent each state
            -- declares -- a default here would be dead code overwritten every
            -- cycle, and worse, would read as though a state could rely on it.
            mem_access_instr <= '0';
            repeat_if_req <= '0';
            clr_repeat_if <= '0';
            div_start <= '0';
            ltch_lh_inst <= '0';
            irq_save_ack <= '0';
            trap_flag <= '0';
            wfi_enter <= '0';   -- P2: only the WFI dispatch arms raise this
            -- S-series intent defaults: FAIL-SAFE (S0 spec section 2).
            ci_rd_commit  <= '0';
            ci_sp_commit  <= '0';
            ci_st_lanes   <= "0000";
            ci_pc_advance <= '0';

            case current_state is
                -- ==========================================
                -- INITIALIZE State
                -- ==========================================
                when INITIALIZE =>
                    -- S2 c7: MIGRATED.  This arm passes the LIVE DECODE through to
                    -- rd and to the store lanes, and that is safe for a reason
                    -- worth writing down rather than rediscovering: instr_curr is
                    -- forced to a nop whenever this state is current --
                    --   instr_curr <= nop when (resetn = '0' or
                    --                           current_state = INITIALIZE) else ...
                    -- and nop is x"00000013" (ADDI x0,x0,0; constants.vhd).  So
                    -- reg_write_ctrl is '1' here (OP-IMM decodes a write) and the
                    -- pass-through is inert NOT because the decode is quiet but
                    -- because **rd is x0**, which the regfile discards; the lane
                    -- strobes are all-ones because a nop is not a store.  The
                    -- block reproduces both exactly, so nothing is special-cased.
                    --
                    -- NOTE, measured 2026-08-02: this state is UNREACHABLE by
                    -- design.  current_state has exactly two writers -- an async
                    -- reset to EXECUTE, and `<= next_state` -- and the only
                    -- producer of next_state = INITIALIZE sits inside the
                    -- `resetn = '0'` branch, where the async reset dominates.  The
                    -- machine resets into EXECUTE and never enters this arm; only
                    -- a corrupted state encoding can land here.  The arm is kept
                    -- (and kept correct) for exactly that case.
                    next_state <= EXECUTE;
                    mem_access_instr <= '0';
                    div_start <= '0';
                    is_compressed <= '0';
                    ci_rd_commit  <= reg_write_ctrl;
                    ci_st_lanes   <= not wen_controller;
                    ci_pc_advance <= '1';

                -- ==========================================
                -- EXECUTE State - Main instruction execution
                -- ==========================================
                when EXECUTE =>
                    -- P3 PMP INSTRUCTION ACCESS FAULT (cause 1) -- FIRST, above
                    -- every other decode arm, because the fetch that would have
                    -- delivered this word NEVER ISSUED: the decoder is looking at
                    -- the PARK word, so `trap`, ecall_op, ebreak_op, the quadrant
                    -- bits and the whole compressed/half-fetch sub-tree below are
                    -- all decoded from a word this hart is not allowed to execute.
                    -- Hoisting the arm to the top of the state (rather than into
                    -- the four dispatch sub-trees) is what keeps a park word whose
                    -- bits 17:16 happen to read "11" out of the half-fetch branch.
                    --   mepc  = pc (pc_en '0'): the faulting instruction's own PC,
                    --           which for a STRADDLING 32-bit instruction is the
                    --           LOWER half's address even when the UPPER half is
                    --           the denied one -- exactly the frozen rule.
                    --   mtval = pmp_f_addr_r, the denied half's address.
                    -- Legacy mode keeps the terminal TRAP_STATE, like any other
                    -- P3 fault (p0_specs.md §4).
                    if ENABLE_PMP and pmp_f_deny_r = '1' then
                        -- S2 c2: SHAPE_P MIGRATED.  Its three owned drives were
                        -- pc_en '0' / reg_write_dp '0' / wen all-ones -- exactly
                        -- the fail-safe intent defaults -- so this shape declares
                        -- nothing and the deletion is value-neutral by
                        -- construction (R-S2-1).  sp_write_en fell through to '0'
                        -- and the block drives ci_sp_commit '0'.
                        mem_access_instr <= '0';
                        -- P3 red-team F4 FIX: clear a pending repeat_if. When
                        -- the DENIED fetch is the UPPER half of a straddling
                        -- 32-bit instruction, the lower-half cycle already set
                        -- repeat_if_req='1'. This arm is hoisted ABOVE the
                        -- repeat_if branch that normally clears it, so without
                        -- this line the stale flag survives the trap and
                        -- hijacks the first compressed instruction the handler
                        -- fetches (instr <= decomp(instr_assembled), pc+=4).
                        -- Harmless when repeat_if was already 0 (the clear is a
                        -- no-op via the repeat_if_req-precedence in its flop).
                        clr_repeat_if    <= '1';
                        if dbg_exc_take = '1' then
                            -- D2/F-D2-0 re-entry (see dbg_exc_take): debug mode never traps out.
                            mem_access_instr <= '0';
                            next_state <= DBG_JUMP;
                        elsif std_mode = '1' then
                            next_state <= MTRAP_SV;
                        else
                            next_state <= TRAP_STATE;
                        end if;
                    -- With the C extension disabled a halfword-aligned PC is an
                    -- instruction-address-misaligned condition (only reachable
                    -- via a jump/branch to a non-word boundary) — trap instead
                    -- of decoding garbage instruction halves. The condition is
                    -- static-false when ENABLE_COMPRESSED, so the default
                    -- build's FSM is untouched.
                    elsif (not ENABLE_COMPRESSED) and pc(1) = '1' then
                        -- P1: instruction-address-misaligned. Standard mode takes
                        -- it as a RECOVERABLE exception (cause 0, mtval = the
                        -- misaligned PC); legacy mode keeps today's terminal
                        -- TRAP_STATE. Statically dead in the Castalia/Argus
                        -- configs (C is on) -- implemented for contract parity.
                        --
                        -- S2 c2: SHAPE_Q MIGRATED, AND THIS ONE CHANGES BEHAVIOUR.
                        -- The arm drove pc_en only; reg_write_dp and wen fell
                        -- through to the LIVE DECODE (reg_write_ctrl /
                        -- wen_controller), so the misaligned-fetch trap could
                        -- commit the faulting encoding's rd and its store lanes on
                        -- the cycle it trapped -- census finding N2.  Migration
                        -- deletes the pc_en drive AND the S1 mirror declarations,
                        -- so the block now drives reg_write_dp '0' and wen
                        -- all-ones here: the N2 fix, ordered by R-DS2 and ruled in
                        -- R-S2-1.  LATENT ONLY -- this predicate is statically
                        -- false wherever ENABLE_COMPRESSED is true, which is every
                        -- shipped config (MemoryMap CORE_ENABLE_COMPRESSED = true,
                        -- Castalia and Argus alike), so no gate can observe it.
                        if dbg_exc_take = '1' then
                            -- D2/F-D2-0 re-entry (see dbg_exc_take): debug mode never traps out.
                            mem_access_instr <= '0';
                            next_state <= DBG_JUMP;
                        elsif std_mode = '1' then
                            next_state <= MTRAP_SV;
                        else
                            next_state <= TRAP_STATE;
                        end if;
                    elsif pc(1) = '1' then
                        -- Current instruction on half-word boundary
                        if quadrant_upper = "11" or repeat_if = '1' then
                            -- Instruction not compressed or fetching upper half
                            is_compressed <= '0';
                            
                            if repeat_if = '1' then
                                -- Completing split fetch of 32-bit instruction
                                -- S2 c3: SHAPE_STRADDLE MIGRATED.  The first shape
                                -- with real work: retiring tails, every memory /
                                -- div / FP / atomic dispatch, the trap arms and
                                -- both IRQ takes.  37 of its 38 owned drives were
                                -- the fail-safe values ('0' / '0' / all-ones); the
                                -- 38th (the FENCE_WAIT pc_en '1') is carried by the
                                -- ci_pc_advance declaration beside it.
                                clr_repeat_if <= '1';
                                
                                -- Determine next state based on instruction type
                                if trap = '1' then
                                    if dbg_exc_take = '1' then
                                        -- D2/F-D2-0 re-entry (see dbg_exc_take): debug mode never traps out.
                                        mem_access_instr <= '0';
                                        next_state <= DBG_JUMP;
                                    elsif std_mode = '1' then
                                        -- P1: RECOVERABLE illegal-instruction
                                        -- exception (cause 2, mtval = the faulting
                                        -- encoding). Zero memory transactions.
                                        next_state <= MTRAP_SV;
                                        mem_access_instr <= '0';
                                    else
                                        next_state <= TRAP_STATE;
                                        -- The LEGACY trap-entry cycle has no
                                        -- reg_write_dp / wen arm, so both keep the
                                        -- live decode's drives.
                                        ci_rd_commit <= reg_write_ctrl;
                                        ci_st_lanes  <= not wen_controller;
                                    end if;
                                -- D1 EBREAK -> DEBUG MODE. Tested ABOVE the shared ecall/ebreak arm
                                -- because that disjunction currently absorbs ebreak_op; the cause mux
                                -- at :2174 already distinguishes the two, so only the FSM arm splits.
                                -- Two destinations, and the difference is the whole of the spec's
                                -- "ebreak in debug mode re-enters" clause:
                                --   NOT in debug mode -> DBG_SV, a full entry (dpc <- this ebreak's OWN
                                --     pc -- a synchronous exception reports its own address, not the
                                --     next one -- cause 1, prv, debug_mode).
                                --   ALREADY in debug mode -> DBG_JUMP, which reloads the PC and writes
                                --     NOTHING: dpc and dcsr.cause must survive an ebreak taken by debug
                                --     code itself, or the debugger loses its own return address.
                                -- dbg_ebreak_take is statically '0' when ENABLE_DEBUG is off, so both
                                -- arms constant-fold and the ecall/ebreak behaviour below is untouched
                                -- in every shipped build (dcsr.ebreakm RESETS 0 and no M-mode software
                                -- can set it -- dbgdenymp.S hart 3 is the standing detector for that).
                                elsif ebreak_op = '1' and dbg_ebreak_take = '1' then
                                    mem_access_instr <= '0';
                                    if debug_mode = '1' then
                                        next_state <= DBG_JUMP;
                                    else
                                        next_state <= DBG_SV;
                                    end if;
                                elsif ecall_op = '1' or ebreak_op = '1' then
                                    -- P1 ECALL (cause 11) / EBREAK (cause 3), both
                                    -- with mtval = 0 and mepc = the instruction's
                                    -- OWN PC. In legacy mode they are legal decodes
                                    -- with no legacy semantics, so they land in the
                                    -- terminal TRAP_STATE -- exactly where the OFF
                                    -- build's illegal-instruction path puts them.
                                    mem_access_instr <= '0';
                                    if dbg_exc_take = '1' then
                                        -- D2/F-D2-0 re-entry (see dbg_exc_take): debug mode never traps out.
                                        next_state <= DBG_JUMP;
                                    elsif std_mode = '1' then
                                        next_state <= MTRAP_SV;
                                    else
                                        next_state <= TRAP_STATE;
                                    end if;
                                -- D1 DRET: the MRET shape exactly (D0/P1 1d) -- a CSR-based restore in
                                -- ONE state, no memory transaction, PC <- dpc. dret_op already carries
                                -- its own debug_mode qualifier from maindec, so this arm cannot fire
                                -- outside debug mode; outside it the encoding is an illegal instruction
                                -- and takes the `trap` arm above. Statically '0' when ENABLE_DEBUG is
                                -- off. NOTE there is no std_mode branch here: debug mode is not a
                                -- delivery mode, and `debug => trapCsr` makes std_mode's machinery
                                -- present in every build that can reach this arm at all.
                                elsif dret_op = '1' then
                                    mem_access_instr <= '0';
                                    next_state <= DBG_RET;
                                elsif mret_op = '1' then
                                    -- P1 MRET: PC <- mepc + the mstatus pop, in the
                                    -- dedicated MTRAP_RET state (JALR shape, no
                                    -- memory access, no writeback). Legacy mode:
                                    -- terminal TRAP_STATE, as above.
                                    mem_access_instr <= '0';
                                    if std_mode = '1' then
                                        next_state <= MTRAP_RET;
                                    else
                                        next_state <= TRAP_STATE;
                                    end if;
                                elsif ENABLE_PMP and pmp_d_deny = '1' then
                                    -- P3 PMP LOAD/STORE ACCESS FAULT -- THE D5 ARM
                                    -- (cause 5 load/LR, 7 store/SC/AMO; mtval = the
                                    -- byte-precise data address; mepc = pc).
                                    -- It sits HERE, after trap/ECALL/EBREAK/MRET and
                                    -- before every memory dispatch arm, so an illegal
                                    -- encoding still reports cause 2 and a memory
                                    -- instruction can never reach its own arm.
                                    -- THE PRE-ISSUE GUARANTEE: mem_access_instr stays
                                    -- '0', so data_addr keeps the fetch fall-through
                                    -- and the denied address is never decoded by
                                    -- hart_tile's sh_sel => sh_req never rises for it
                                    -- (no request is yanked, so the arbiter's
                                    -- WAIT-FOR-RELEASE contract is untouched). wen
                                    -- all-ones kills the private-RAM lane strobes; an
                                    -- SC/AMO never enters SC_CHECK/AMO_READ at all,
                                    -- and amo_lock -- qualified by mem_access_instr --
                                    -- never pins the grant.
                                    mem_access_instr <= '0';
                                    if dbg_exc_take = '1' then
                                        -- D2/F-D2-0 re-entry (see dbg_exc_take): debug mode never traps out.
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
                                    wfi_enter  <= '1';
                                    ci_rd_commit <= reg_write_ctrl;
                                    ci_st_lanes  <= not wen_controller;
                                elsif wrs_op = '1' then
                                    -- X1 Zawrs: stall only if a global reservation
                                    -- is live; else the hint retires immediately.
                                    ci_rd_commit <= reg_write_ctrl;
                                    ci_st_lanes  <= not wen_controller;
                                    if resv_valid_ext = '1' then
                                        next_state <= WRS_WAIT;
                                    else
                                        next_state <= EXECUTE;  -- pc_en defaults '1'
                                        ci_pc_advance <= '1';
                                    end if;
                                elsif lr_op = '1' then
                                    -- Load-Reserved operation
                                    mem_access_instr <= '1';
                                    next_state <= LR_READ;
                                    ci_st_lanes <= not wen_controller;
                                elsif sc_op = '1' then
                                    -- Store-Conditional operation
                                    -- M4b FIX: no EXECUTE-phase access — the
                                    -- ALU holds rs1+rs2 here (garbage addr);
                                    -- the only SC access is SC_CHECK's write.
                                    mem_access_instr <= '0';
                                    next_state <= SC_CHECK;
                                    -- M4b FIX: wen_controller decodes SC as a
                                    -- word store, which committed the write
                                    -- HERE — before the reservation check. The
                                    -- only (conditional) SC write is SC_CHECK's.
                                    -- S2 c3: the suppression is now the block's
                                    -- fail-safe default, not a local drive.
                                elsif amo_op = '1' then
                                    -- Atomic memory operation
                                    mem_access_instr <= '1';
                                    next_state <= AMO_READ;
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
                                elsif fence_op = '1' then
                                    -- X1 Zihintpause (D6): the exact PAUSE hint
                                    -- enters the arbiter-yield window instead of
                                    -- the 1-cycle FENCE nop. pc_en frozen so the
                                    -- PAUSE holds (retires when the window closes);
                                    -- ENABLE_ZIHINT + window>0 are static, so a
                                    -- disabled/seeded build takes the FENCE arm =
                                    -- bit-identical today.
                                    ci_rd_commit <= reg_write_ctrl;
                                    ci_st_lanes  <= not wen_controller;
                                    if ENABLE_ZIHINT and pause_hint = '1' and PAUSE_WINDOW_CYCLES > 0 then
                                        next_state <= PAUSE_WAIT;
                                    else
                                        next_state <= FENCE_WAIT;
                                        ci_pc_advance <= '1';
                                    end if;
                                elsif mem_access_controller = '1' then
                                    -- ==========================================
                                    -- F9 (fix pass W4) -- AN `iret` IS NOT A LOAD
                                    -- ==========================================
                                    -- maindec's read_data_flag has an arm for
                                    -- op=CUSTOM_OPCODE, funct3=000, funct7=0
                                    -- (maindec:1186) -- that IS the `iret`
                                    -- encoding -- so mem_access_controller
                                    -- (maindec:1194) is high for an iret and THIS
                                    -- arm, tested above the `elsif isr_ret` arm at
                                    -- :2849, is the one an iret takes. (The isr_ret
                                    -- arm below is dead; the trajectory it names is
                                    -- reached through MEMORY_WAIT instead, :3694.)
                                    --
                                    -- With mem_access_instr='1' the data_addr mux
                                    -- (:1861) put ALU_Result on the bus for that
                                    -- cycle, and for CUSTOM_OPCODE the ALU ADDS TWO
                                    -- REGISTERS (alu_control="0000000" at
                                    -- maindec:1213; ALU_src has no CUSTOM row and
                                    -- falls through to '0' = register operand),
                                    -- while the custom decode never inspects
                                    -- rs1/rs2 (maindec:849-862 whitelists funct3 +
                                    -- funct7 only). So every ISR return issued a
                                    -- REAL, SIDE-EFFECTING read at reg[rs1]+reg[rs2]
                                    -- -- 0 for the canonical macro (riscv_test.h
                                    -- `.insn r 0x0b,0,0,x0,x0,x0`), which is inside
                                    -- the shared boot ROM, hence a genuine arbiter
                                    -- transaction: sh_sel is a PURE DECODE of
                                    -- data_addr (hart_tile.vhd:654, sh_req_int :726).
                                    -- W4's detector steered it with a hand-assembled
                                    -- rs1 and the iret CLAIMED A HARDWARE MUTEX.
                                    -- MEASURED cost: 6 clk per ISR return, chip-wide.
                                    --
                                    -- FIX = SUPPRESS THE REQUEST, KEEP THE
                                    -- TRAJECTORY. next_state / pc_en / reg_write_dp
                                    -- are untouched, so EXECUTE -> MEMORY_WAIT ->
                                    -- IRQ_REST still holds and the REAL pop is still
                                    -- addressed from stack_pointer in MEMORY_WAIT
                                    -- (:1865). wen is already "1111" for CUSTOM
                                    -- (maindec:1135) -- the phantom was a READ.
                                    -- With the request suppressed the ALU_Result arm
                                    -- drops out and data_addr falls through the mux
                                    -- to pc_next: an ordinary early fetch of the word
                                    -- this ISR was about to fetch anyway -- the same
                                    -- fall-through idiom F2 relies on at :1810. For a
                                    -- TCM-resident ISR (every committed test; the ISR
                                    -- bank is 0xB100-0xBAFF) that is a private access
                                    -- and the stall disappears entirely; for an ISR
                                    -- executing FROM the shared window (the bootrom
                                    -- park/loader ISR) it is a legitimate instruction
                                    -- fetch of read-only ROM instead of a data read
                                    -- at a register-dependent address.
                                    --
                                    -- U-MODE: `isr_ret` is u-gated (maindec:1027) so
                                    -- this qualifier does not fire in U -- and it
                                    -- does not need to. W4 MEASURED (knobs-on build)
                                    -- that a U-mode iret takes the `trap = '1'` arm,
                                    -- which is the FIRST arm of all four shapes
                                    -- (:2594/:2867/:2982/:3145): mcause 2, mepc = its
                                    -- own pc, mtval = its own encoding, bus silent.
                                    -- It never reaches this arm. (F12 REFUTED.)
                                    mem_access_instr <= not isr_ret;
                                    next_state <= MEMORY_WAIT;
                                    ci_st_lanes <= not wen_controller;
                                elsif is_div_op = '1' then
                                    next_state <= DIV_WAIT;
                                    -- Div-aliasing fix: suppress the EXECUTE-cycle
                                    -- writeback. The decode says reg_write='1' for
                                    -- a DIV, so an unsuppressed dispatch cycle
                                    -- writes rd with the ALU's idle ResultSignal
                                    -- (=0) BEFORE the divider latches its operands
                                    -- in DIV_WAIT. When rd==rs1 that zero becomes
                                    -- the latched dividend (result 0); when rd==rs2
                                    -- it zeroes the divisor read (spurious
                                    -- div-by-zero). rd is written exactly once, at
                                    -- DIV_DONE, like lr/sc/amo/mem_access.
                                    -- S2 c3: the suppression is now STRUCTURAL --
                                    -- this arm declares no rd commit, so the block
                                    -- drives '0'. There is no longer a drive to
                                    -- forget.
                                    ci_st_lanes <= not wen_controller;
                                elsif is_fp_fma = '1' then
                                    -- X4 Zfinx FMA: fetch rs3 then run. pc_en frozen
                                    -- and reg_write_dp forced '0' across the whole
                                    -- dispatch+wait window (writeback lands only in
                                    -- FPU_DONE) — the div-arm ungated-write bug class.
                                    next_state <= FPU_FETCH3;
                                    ci_st_lanes <= not wen_controller;
                                elsif is_fp_multicycle = '1' then
                                    next_state <= FPU_WAIT;
                                    ci_st_lanes <= not wen_controller;
                                -- D1: THE HALT/STEP RECOGNITION SITE, above BOTH delivery takes. A halt
                                -- request is UNMASKABLE -- neither mstatus.MIE nor mtrapctl.LEGACY
                                -- qualifies it -- so it must be tested before irq_save and std_irq_take,
                                -- and it rides the SAME 13 points an interrupt already diverts from
                                -- (d1_spec.md 2). The commit declarations are copied from the irq_save
                                -- arm verbatim: a halt is taken BETWEEN instructions, so the in-flight
                                -- instruction still retires and dpc becomes the address of the NEXT one.
                                -- dbg_halt_take is statically '0' when ENABLE_DEBUG is off, so every one
                                -- of these arms constant-folds and the OFF FSM is bit-identical.
                                elsif dbg_halt_take = '1' then
                                    next_state <= DBG_SV;
                                    ci_rd_commit <= reg_write_ctrl;
                                    ci_st_lanes  <= not wen_controller;
                                elsif irq_save = '1' then
                                    next_state <= IRQ_SV;
                                    ci_rd_commit <= reg_write_ctrl;
                                    ci_st_lanes  <= not wen_controller;
                                elsif std_irq_take = '1' then
                                    -- P1 standard delivery: the SAME check point, no new one. In
                                    -- standard mode irq_save can never fire (irq_en_eff is masked
                                    -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                                    -- legacy mode std_irq_take is '0' -- the two arms are mutually
                                    -- exclusive by construction. The X3 uninterruptible sequencers
                                    -- stay uninterruptible: they have no irq_save site, so they get
                                    -- no std_irq_take site either.
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
                                -- Need to fetch upper half of instruction
                                -- S2 c2: SHAPE_E MIGRATED.  Its three owned drives
                                -- were reg_write_dp '0' / pc_en '0' / wen all-ones
                                -- -- the fail-safe defaults -- so it declares
                                -- nothing and the deletion is value-neutral.  This
                                -- is the ONLY shape in this commit with live
                                -- coverage: the bubble fires on every straddling
                                -- 32-bit instruction.
                                ltch_lh_inst <= '1';
                                repeat_if_req <= '1';
                                next_state <= EXECUTE;
                            end if;
                        else
                            
                            -- Compressed instruction on half-word boundary
                            -- S2 c5: SHAPE_HWC MIGRATED.  A PURE deletion: all 21
                            -- of its owned drives were the fail-safe values, none
                            -- depended on a declaration.  This shape has no
                            -- fence/lr/sc/amo/cboz/wfi/wrs/fp arms at all (the F4
                            -- assert (4) class), so it has no FENCE_WAIT pc_en '1'
                            -- exception the way STRADDLE and WA32 do.
                            is_compressed <= '1';
                            if trap = '1' then
                                if dbg_exc_take = '1' then
                                    -- D2/F-D2-0 re-entry (see dbg_exc_take): debug mode never traps out.
                                    mem_access_instr <= '0';
                                    next_state <= DBG_JUMP;
                                elsif std_mode = '1' then
                                    -- P1: recoverable illegal-instruction exception
                                    next_state <= MTRAP_SV;
                                    mem_access_instr <= '0';
                                else
                                    next_state <= TRAP_STATE;
                                    ci_rd_commit <= reg_write_ctrl;
                                    ci_st_lanes  <= not wen_controller;
                                end if;
                            -- D1 ebreak -> debug entry, above the shared ecall/ebreak arm (see the
                            -- first site, in EXECUTE shape STRADDLE, for the full argument).
                            elsif ebreak_op = '1' and dbg_ebreak_take = '1' then
                                mem_access_instr <= '0';
                                if debug_mode = '1' then
                                    next_state <= DBG_JUMP;
                                else
                                    next_state <= DBG_SV;
                                end if;
                            elsif ecall_op = '1' or ebreak_op = '1' then
                                -- P1: c.ebreak DECOMPRESSES to EBREAK (c_dec:~676),
                                -- so this compressed arm really can see ebreak_op.
                                -- Same routing as the 32-bit arm. (ECALL/MRET have
                                -- no compressed form; the term costs nothing and
                                -- keeps the four decode arms uniform.)
                                mem_access_instr <= '0';
                                if dbg_exc_take = '1' then
                                    -- D2/F-D2-0 re-entry (see dbg_exc_take): debug mode never traps out.
                                    next_state <= DBG_JUMP;
                                elsif std_mode = '1' then
                                    next_state <= MTRAP_SV;
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            -- D1 DRET (see the first site, in EXECUTE shape STRADDLE).
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
                                -- P3 PMP load/store access fault -- the D5 arm; see
                                -- the split-fetch arm above for the full rationale.
                                -- (A compressed c.lw/c.sw reaches it through
                                -- mem_access_controller exactly like a 32-bit one;
                                -- cm.* sequencer steps are checked in their OWN
                                -- states, so pmp_d_active is '0' at a zcm dispatch.)
                                mem_access_instr <= '0';
                                if dbg_exc_take = '1' then
                                    -- D2/F-D2-0 re-entry (see dbg_exc_take): debug mode never traps out.
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
                                -- F9 (fix pass W4): see shape A's block at :2747.
                                -- SHAPE B is the HALF-WORD-ALIGNED COMPRESSED shape,
                                -- so `isr_ret` is statically '0' here: isr_ret needs
                                -- op = CUSTOM_OPCODE and c_dec NEVER emits it (the
                                -- same F5.3 argument recorded at :3240 for shape D --
                                -- which is why shape B's own `elsif isr_ret` arm at
                                -- :2970 is equally dead). The qualifier is carried on
                                -- all four arms anyway so the rule is uniform and a
                                -- fifth shape would inherit it; it folds away here.
                                mem_access_instr <= not isr_ret;
                                next_state <= MEMORY_WAIT;
                                ci_st_lanes <= not wen_controller;
                            elsif is_div_op = '1' then
                                next_state <= DIV_WAIT;
                                -- Div-aliasing fix: suppress the EXECUTE-cycle
                                -- writeback. The decode says reg_write='1' for a
                                -- DIV, so an unsuppressed dispatch cycle clobbers
                                -- rd with the ALU's idle ResultSignal (=0) before
                                -- the divider latches its operands. rd is written
                                -- exactly once, at DIV_DONE.  S2 c5: the
                                -- suppression is STRUCTURAL here now -- this arm
                                -- declares no rd commit, so the block drives '0'.
                                ci_st_lanes <= not wen_controller;
                            -- D1 halt/step recognition, above both delivery takes (see the
                            -- first site, in EXECUTE shape STRADDLE, for the full argument).
                            elsif dbg_halt_take = '1' then
                                next_state <= DBG_SV;
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                            elsif irq_save = '1' then
                                next_state <= IRQ_SV;
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                            elsif std_irq_take = '1' then
                                -- P1 standard delivery: the SAME check point, no new one. In
                                -- standard mode irq_save can never fire (irq_en_eff is masked
                                -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                                -- legacy mode std_irq_take is '0' -- the two arms are mutually
                                -- exclusive by construction. The X3 uninterruptible sequencers
                                -- stay uninterruptible: they have no irq_save site, so they get
                                -- no std_irq_take site either.
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
                            -- Not compressed
                            -- S2 c4: SHAPE_WA32 MIGRATED -- the word-aligned
                            -- 32-bit shape, and the most-executed one in the
                            -- machine.  Structurally identical to SHAPE_STRADDLE:
                            -- 37 of its 38 owned drives were the fail-safe values,
                            -- the 38th (the FENCE_WAIT pc_en '1') is carried by the
                            -- ci_pc_advance declaration beside it.
                            is_compressed <= '0';
                            
                            if trap = '1' then
                                if dbg_exc_take = '1' then
                                    -- D2/F-D2-0 re-entry (see dbg_exc_take): debug mode never traps out.
                                    mem_access_instr <= '0';
                                    next_state <= DBG_JUMP;
                                elsif std_mode = '1' then
                                    -- P1: recoverable illegal-instruction exception
                                    -- (cause 2, mtval = the faulting encoding).
                                    next_state <= MTRAP_SV;
                                    mem_access_instr <= '0';
                                else
                                    next_state <= TRAP_STATE;
                                    ci_rd_commit <= reg_write_ctrl;
                                    ci_st_lanes  <= not wen_controller;
                                end if;
                            -- D1 ebreak -> debug entry, above the shared ecall/ebreak arm (see the
                            -- first site, in EXECUTE shape STRADDLE, for the full argument).
                            elsif ebreak_op = '1' and dbg_ebreak_take = '1' then
                                mem_access_instr <= '0';
                                if debug_mode = '1' then
                                    next_state <= DBG_JUMP;
                                else
                                    next_state <= DBG_SV;
                                end if;
                            elsif ecall_op = '1' or ebreak_op = '1' then
                                -- P1 ECALL (11) / EBREAK (3); see the split-fetch
                                -- arm above for the full rationale.
                                mem_access_instr <= '0';
                                if dbg_exc_take = '1' then
                                    -- D2/F-D2-0 re-entry (see dbg_exc_take): debug mode never traps out.
                                    next_state <= DBG_JUMP;
                                elsif std_mode = '1' then
                                    next_state <= MTRAP_SV;
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            -- D1 DRET (see the first site, in EXECUTE shape STRADDLE).
                            elsif dret_op = '1' then
                                mem_access_instr <= '0';
                                next_state <= DBG_RET;
                            elsif mret_op = '1' then
                                -- P1 MRET; see the split-fetch arm above.
                                mem_access_instr <= '0';
                                if std_mode = '1' then
                                    next_state <= MTRAP_RET;
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            elsif ENABLE_PMP and pmp_d_deny = '1' then
                                -- P3 PMP load/store access fault -- the D5 arm; see
                                -- the split-fetch arm above for the full rationale.
                                mem_access_instr <= '0';
                                if dbg_exc_take = '1' then
                                    -- D2/F-D2-0 re-entry (see dbg_exc_take): debug mode never traps out.
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
                                -- P2 standard WFI (see the split-fetch arm above
                                -- for the full rationale). WFI is a 32-bit
                                -- SYSTEM encoding with no compressed form, so
                                -- these two word-dispatch arms are the ONLY
                                -- places it can appear -- exactly like
                                -- extinguish/sleep_rq, whose arms it sits beside.
                                next_state <= SLEEPING;
                                wfi_enter  <= '1';
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                            elsif wrs_op = '1' then
                                -- X1 Zawrs: stall only if a global reservation is
                                -- live; else the hint retires immediately.
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                                if resv_valid_ext = '1' then
                                    next_state <= WRS_WAIT;
                                else
                                    next_state <= EXECUTE;  -- pc_en defaults '1'
                                    ci_pc_advance <= '1';
                                end if;
                            elsif lr_op = '1' then
                                -- Load-Reserved operation
                                mem_access_instr <= '1';
                                next_state <= LR_READ;
                                ci_st_lanes <= not wen_controller;
                            elsif sc_op = '1' then
                                -- Store-Conditional operation
                                -- M4b FIX: no EXECUTE-phase access (see the
                                -- half-word path above).
                                mem_access_instr <= '0';
                                next_state <= SC_CHECK;
                                -- M4b FIX: no unconditional EXECUTE-phase SC
                                -- write (see the half-word path above).  S2 c4:
                                -- the suppression is now the block's fail-safe
                                -- default, not a local drive.
                            elsif amo_op = '1' then
                                -- Atomic memory operation
                                mem_access_instr <= '1';
                                next_state <= AMO_READ;
                            elsif cboz_op = '1' then
                                -- X3 Zicboz: launch the cbo.zero block-zero store
                                -- sequencer (see the half-word arm above for the
                                -- rationale). No access this cycle; PC frozen;
                                -- cboz_base latched from rs1 on this transition.
                                mem_access_instr <= '0';
                                next_state <= CBOZ_WRITE;
                            elsif fence_op = '1' then
                                -- X1 Zihintpause (D6): PAUSE -> arbiter-yield
                                -- window; any other FENCE -> 1-cycle nop. See the
                                -- half-word path above for the rationale.
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                                if ENABLE_ZIHINT and pause_hint = '1' and PAUSE_WINDOW_CYCLES > 0 then
                                    next_state <= PAUSE_WAIT;
                                else
                                    next_state <= FENCE_WAIT;
                                    ci_pc_advance <= '1';
                                end if;
                            elsif mem_access_controller = '1' then
                                -- F9 (fix pass W4): see shape A's block at :2747.
                                -- SHAPE C is the word-aligned 32-bit shape, so this
                                -- arm and shape A's are the two that really carry an
                                -- `iret`.
                                mem_access_instr <= not isr_ret;
                                next_state <= MEMORY_WAIT;
                                ci_st_lanes <= not wen_controller;
                            elsif is_div_op = '1' then
                                next_state <= DIV_WAIT;
                                -- Div-aliasing fix: suppress the EXECUTE-cycle
                                -- writeback. The decode says reg_write='1' for a
                                -- DIV, so an unsuppressed dispatch cycle clobbers
                                -- rd with the ALU's idle ResultSignal (=0) before
                                -- the divider latches its operands. rd is written
                                -- exactly once, at DIV_DONE.  S2 c4: the
                                -- suppression is STRUCTURAL here now -- this arm
                                -- declares no rd commit, so the block drives '0'.
                                ci_st_lanes <= not wen_controller;
                            elsif is_fp_fma = '1' then
                                -- X4 Zfinx FMA (see the half-word arm for rationale):
                                -- freeze pc_en, force reg_write_dp '0' across dispatch.
                                next_state <= FPU_FETCH3;
                                ci_st_lanes <= not wen_controller;
                            elsif is_fp_multicycle = '1' then
                                next_state <= FPU_WAIT;
                                ci_st_lanes <= not wen_controller;
                            -- D1 halt/step recognition, above both delivery takes (see the
                            -- first site, in EXECUTE shape STRADDLE, for the full argument).
                            elsif dbg_halt_take = '1' then
                                next_state <= DBG_SV;
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                            elsif irq_save = '1' then
                                next_state <= IRQ_SV;
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                            elsif std_irq_take = '1' then
                                -- P1 standard delivery: the SAME check point, no new one. In
                                -- standard mode irq_save can never fire (irq_en_eff is masked
                                -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                                -- legacy mode std_irq_take is '0' -- the two arms are mutually
                                -- exclusive by construction. The X3 uninterruptible sequencers
                                -- stay uninterruptible: they have no irq_save site, so they get
                                -- no std_irq_take site either.
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
                            -- Compressed instruction
                            -- S2 c6: SHAPE_WAC MIGRATED -- the last of the seven.
                            -- A pure deletion like SHAPE_HWC, whose missing-arm set
                            -- it shares.  With this arm the EXECUTE state holds no
                            -- direct drive of the four owned nets at all.
                            is_compressed <= '1';
                            if trap = '1' then
                                if dbg_exc_take = '1' then
                                    -- D2/F-D2-0 re-entry (see dbg_exc_take): debug mode never traps out.
                                    mem_access_instr <= '0';
                                    next_state <= DBG_JUMP;
                                elsif std_mode = '1' then
                                    -- P1: recoverable illegal-instruction exception
                                    next_state <= MTRAP_SV;
                                    mem_access_instr <= '0';
                                else
                                    next_state <= TRAP_STATE;
                                    ci_rd_commit <= reg_write_ctrl;
                                    ci_st_lanes  <= not wen_controller;
                                end if;
                            -- D1 ebreak -> debug entry, above the shared ecall/ebreak arm (see the
                            -- first site, in EXECUTE shape STRADDLE, for the full argument).
                            elsif ebreak_op = '1' and dbg_ebreak_take = '1' then
                                mem_access_instr <= '0';
                                if debug_mode = '1' then
                                    next_state <= DBG_JUMP;
                                else
                                    next_state <= DBG_SV;
                                end if;
                            elsif ecall_op = '1' or ebreak_op = '1' then
                                -- P1: c.ebreak decompresses to EBREAK (c_dec:~676).
                                mem_access_instr <= '0';
                                if dbg_exc_take = '1' then
                                    -- D2/F-D2-0 re-entry (see dbg_exc_take): debug mode never traps out.
                                    next_state <= DBG_JUMP;
                                elsif std_mode = '1' then
                                    next_state <= MTRAP_SV;
                                else
                                    next_state <= TRAP_STATE;
                                end if;
                            -- D1 DRET (see the first site, in EXECUTE shape STRADDLE).
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
                                -- P3 PMP load/store access fault -- the D5 arm; see
                                -- the split-fetch arm above for the full rationale.
                                -- (A compressed c.lw/c.sw reaches it through
                                -- mem_access_controller exactly like a 32-bit one;
                                -- cm.* sequencer steps are checked in their OWN
                                -- states, so pmp_d_active is '0' at a zcm dispatch.)
                                mem_access_instr <= '0';
                                if dbg_exc_take = '1' then
                                    -- D2/F-D2-0 re-entry (see dbg_exc_take): debug mode never traps out.
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
                                -- F9 (fix pass W4): see shape A's block at :2747.
                                -- SHAPE D is the WORD-ALIGNED COMPRESSED shape, so
                                -- `isr_ret` is statically '0' here for the F5.3
                                -- reason spelled out at :3240 below. Carried anyway
                                -- for uniformity; it folds away.
                                mem_access_instr <= not isr_ret;
                                next_state <= MEMORY_WAIT;
                                ci_st_lanes <= not wen_controller;
                            elsif is_div_op = '1' then
                                next_state <= DIV_WAIT;
                                -- Div-aliasing fix: suppress the EXECUTE-cycle
                                -- writeback. The decode says reg_write='1' for a
                                -- DIV, so an unsuppressed dispatch cycle clobbers
                                -- rd with the ALU's idle ResultSignal (=0) before
                                -- the divider latches its operands. rd is written
                                -- exactly once, at DIV_DONE.  S2 c6: the
                                -- suppression is STRUCTURAL here now -- this arm
                                -- declares no rd commit, so the block drives '0'.
                                ci_st_lanes <= not wen_controller;
                            -- D1 halt/step recognition, above both delivery takes (see the
                            -- first site, in EXECUTE shape STRADDLE, for the full argument).
                            elsif dbg_halt_take = '1' then
                                next_state <= DBG_SV;
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                            elsif irq_save = '1' then
                                next_state <= IRQ_SV;
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                            elsif std_irq_take = '1' then
                                -- P1 standard delivery: the SAME check point, no new one. In
                                -- standard mode irq_save can never fire (irq_en_eff is masked
                                -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                                -- legacy mode std_irq_take is '0' -- the two arms are mutually
                                -- exclusive by construction. The X3 uninterruptible sequencers
                                -- stay uninterruptible: they have no irq_save site, so they get
                                -- no std_irq_take site either.
                                next_state <= MTRAP_SV;
                                ci_rd_commit <= reg_write_ctrl;
                                ci_st_lanes  <= not wen_controller;
                            -- F5.3 (fix pass W1): this arm -- the WORD-ALIGNED
                            -- COMPRESSED shape -- deliberately has NO
                            -- `elsif isr_ret = '1'` branch, unlike its three
                            -- siblings. That is CORRECT, not an omission, and
                            -- the branch must not be added: isr_ret requires
                            -- op = CUSTOM_OPCODE (maindec.vhd:921;
                            -- constants.vhd:65 = "0001011", a 32-bit encoding
                            -- with bits[1:0]="11"), and c_dec NEVER emits
                            -- CUSTOM_OPCODE -- so no compressed instruction can
                            -- decompress into an `iret` and this branch would be
                            -- unreachable by construction. Adding it would be an
                            -- FSM behaviour change bought for nothing.
                            -- F9 (fix pass W4) COROLLARY, measured by the W4
                            -- detector agent against c_dec's complete opcode set
                            -- (c_dec.vhd:790, one `instr_out <= dec` assignment;
                            -- the literals it can emit are 0010011 0110011 0100011
                            -- 0000011 1101111 1100111 1100011 0110111 +
                            -- ZCM_SENTINEL_OP -- 0001011 is NOT among them): the
                            -- SAME argument makes shape B's *present* `elsif
                            -- isr_ret` arm at :2970 dead too. So shape D's missing
                            -- arm is not the asymmetry -- shape B's spare one is.
                            -- Neither is removed: deleting a dead arm from one of
                            -- four near-identical shapes is a bigger readability
                            -- hazard than leaving it documented.
                            else
                                next_state <= EXECUTE;
                                ci_rd_commit  <= reg_write_ctrl;
                                ci_st_lanes   <= not wen_controller;
                                ci_pc_advance <= '1';
                            end if;
                        end if;
                    end if;

                -- ==========================================
                -- AMO_READ State - Read phase of atomic operation
                -- ==========================================
                when AMO_READ =>
                    -- S2 c10: MIGRATED.  Read phase: no store lanes, no rd yet --
                    -- all three are the fail-safe values, so the arm declares
                    -- nothing and the block supplies them.  mem_access_instr stays
                    -- here: it is not an owned signal and it encodes the AMO bus
                    -- protocol (read phase asserts the request).
                    mem_access_instr <= '1';
                    next_state <= AMO_WRITEBACK;
                -- ==========================================
                -- AMO_WRITEBACK State - Write value to rd
                -- ==========================================
                when AMO_WRITEBACK =>
                    -- S2 c10: MIGRATED.  This is the AMO's rd commit site -- it
                    -- returns the OLD memory value to rd, which is why the
                    -- declaration is an unconditional '1' rather than the live
                    -- decode: the value committed here is the state's own, not the
                    -- decoder's.  No memory access this cycle.
                    mem_access_instr <= '0';
                    ci_rd_commit <= '1';
                    next_state <= AMO_COMPUTE;

                -- ==========================================
                -- AMO_COMPUTE State - Compute phase of atomic operation
                -- ==========================================
                when AMO_COMPUTE =>
                    -- S2 c10: MIGRATED.  rd was already committed in
                    -- AMO_WRITEBACK, so this cycle commits nothing and declares
                    -- nothing -- the fail-safe default IS the intent here.
                    mem_access_instr <= '0';
                    next_state <= AMO_WRITE;

                -- ==========================================
                -- AMO_WRITE State - Write phase of atomic operation
                -- ==========================================
                when AMO_WRITE =>
                    -- S2 c10: MIGRATED.  The store lanes are the COMPUTED vector
                    -- amo_wen (X2 Zabha: byte-lane enables, word AMO = "0000");
                    -- only the drive moved, the computation stays at its own site.
                    -- ci_st_lanes is ACTIVE-HIGH, hence the inversion.
                    mem_access_instr <= '1';
                    ci_pc_advance <= '1';
                    ci_st_lanes   <= not amo_wen;
                    
                    -- D1 halt/step recognition, above both delivery takes (see the
                    -- first site, in EXECUTE shape STRADDLE, for the full argument).
                    if dbg_halt_take = '1' then
                        next_state <= DBG_SV;
                        ci_pc_advance <= '0';
                    elsif irq_save = '1' then
                        next_state <= IRQ_SV;
                        ci_pc_advance <= '0';
                    elsif std_irq_take = '1' then
                        -- P1 standard delivery: the SAME check point, no new one. In
                        -- standard mode irq_save can never fire (irq_en_eff is masked
                        -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                        -- legacy mode std_irq_take is '0' -- the two arms are mutually
                        -- exclusive by construction. The X3 uninterruptible sequencers
                        -- stay uninterruptible: they have no irq_save site, so they get
                        -- no std_irq_take site either.
                        next_state <= MTRAP_SV;
                        ci_pc_advance <= '0';
                    else
                        -- Need to fetch next instruction from memory
                        next_state <= AMO_COMPLETE;
                    end if;

                -- ==========================================
                -- AMO COMPLETE State - Fetch next instruction
                -- ==========================================
                when AMO_COMPLETE =>
                    -- S2 c10: MIGRATED.  The AMO's retire bubble: no access, no
                    -- commit, PC advances unless an interrupt is taken here.
                    mem_access_instr <= '0';
                    ci_pc_advance <= '1';
                    -- D1 halt/step recognition, above both delivery takes (see the
                    -- first site, in EXECUTE shape STRADDLE, for the full argument).
                    if dbg_halt_take = '1' then
                        next_state <= DBG_SV;
                        ci_pc_advance <= '0';
                    elsif irq_save = '1' then
                        next_state <= IRQ_SV;
                        ci_pc_advance <= '0';
                    elsif std_irq_take = '1' then
                        -- P1 standard delivery: the SAME check point, no new one. In
                        -- standard mode irq_save can never fire (irq_en_eff is masked
                        -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                        -- legacy mode std_irq_take is '0' -- the two arms are mutually
                        -- exclusive by construction. The X3 uninterruptible sequencers
                        -- stay uninterruptible: they have no irq_save site, so they get
                        -- no std_irq_take site either.
                        next_state <= MTRAP_SV;
                        ci_pc_advance <= '0';
                    else
                        next_state <= EXECUTE;
                    end if;

                -- ==========================================
                -- LR_READ State - Load-Reserved read
                -- ==========================================
                when LR_READ =>
                    -- S2 c11: MIGRATED.  The LR's rd commit site -- it returns the
                    -- loaded word, so the declaration is an unconditional '1'
                    -- (the value is the state's own, not the decoder's).  Read
                    -- operation: no store lanes, which is the fail-safe default.
                    -- mem_access_instr stays -- not owned, and it is what makes
                    -- this a read.
                    mem_access_instr <= '1';
                    ci_pc_advance <= '1';
                    ci_rd_commit  <= '1';
                    
                    -- D1 halt/step recognition, above both delivery takes (see the
                    -- first site, in EXECUTE shape STRADDLE, for the full argument).
                    if dbg_halt_take = '1' then
                        next_state <= DBG_SV;
                        ci_pc_advance <= '0';
                    elsif irq_save = '1' then
                        next_state <= IRQ_SV;
                        ci_pc_advance <= '0';
                    elsif std_irq_take = '1' then
                        -- P1 standard delivery: the SAME check point, no new one. In
                        -- standard mode irq_save can never fire (irq_en_eff is masked
                        -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                        -- legacy mode std_irq_take is '0' -- the two arms are mutually
                        -- exclusive by construction. The X3 uninterruptible sequencers
                        -- stay uninterruptible: they have no irq_save site, so they get
                        -- no std_irq_take site either.
                        next_state <= MTRAP_SV;
                        ci_pc_advance <= '0';
                    else
                        next_state <= AMO_COMPLETE;
                    end if;

                -- ==========================================
                -- SC_CHECK State - Store-Conditional check and write
                -- ==========================================
                when SC_CHECK =>
                    -- S2 c11: MIGRATED.  rd is committed unconditionally here --
                    -- the SC writes its success/fail result to rd on BOTH paths,
                    -- which is why the declaration is '1' and sits above the
                    -- reservation test rather than inside it.  Only the STORE
                    -- LANES are conditional (below).
                    ci_pc_advance <= '1';
                    ci_rd_commit  <= '1';

                    -- Only write if reservation is valid and addresses match
                    -- F2 (fix pass W1): and only ISSUE A BUS ACCESS AT ALL under
                    -- that same condition. mem_access_instr used to be asserted
                    -- here UNCONDITIONALLY, so a locally-FAILED sc.w still put
                    -- rs1 on data_addr (via the SC_CHECK term of the data_addr
                    -- mux -- copy 1 of the four listed below) with
                    -- only the lanes suppressed -- and hart_tile's sh_sel is a
                    -- PURE DECODE of data_addr (hart_tile.vhd:654, sh_req_int
                    -- :726), so the failed SC performed a real, side-effecting
                    -- shared-window READ: an atomic claim of a HW mutex, an
                    -- atomic CLAIM of the IRQ router, an SPIxRX TCIF auto-clear.
                    -- BOTH halves of the fix are required. Suppressing the
                    -- request alone would drop the mux through to the
                    -- `ALU_Result when mem_access_instr = '1'` arm, and the ALU
                    -- is in pass-B during SC_CHECK (ALU_Result = the SC's rd,
                    -- 0 or 1) -- a WORSE phantom address, inside the boot ROM.
                    -- So the data_addr mux's SC_CHECK term carries the SAME
                    -- literal predicate; they must be kept textually identical.
                    -- On the failing path data_addr falls through to pc_next,
                    -- which during SC_CHECK is pc_next_reg -- the very address the
                    -- following AMO_COMPLETE bubble presents anyway, i.e. a
                    -- redundant, harmless early fetch of the pending word.
                    -- Untouched on purpose: the reservation unit and the success
                    -- path.
                    -- Detector: rv32ua-p-scfailrd.
                    --
                    -- ***** SC-SUCCESS PREDICATE: FOUR COPIES, ALL IDENTICAL *****
                    -- `reservation_valid = '1' and reservation_addr = rs1_value`
                    -- is duplicated at FOUR sites.  Change all four or none -- a
                    -- divergence between them is SILENT.  By role, not line
                    -- number (numbers rot; three of the four also WRAP across
                    -- lines, so a line-based grep finds only this one):
                    --   1. the data_addr mux's SC_CHECK term  (steers rs1_value)
                    --   2. amo_phase                          ("101" SC-success,
                    --                                          with sc_fail_ext)
                    --   3. lr_sc_bus                          ("10" SC-write tag)
                    --   4. THIS arm                           (store lanes +
                    --                                          mem_access_instr)
                    -- S2 c11 replaced the old two-site SYNC notes, which named
                    -- one sibling each and missed copies 2 and 3 entirely.
                    if reservation_valid = '1' and reservation_addr = rs1_value then  -- M4b: rs1, not the phase-dependent ALU_result
                        ci_st_lanes <= "1111";   -- write word (success)
                        mem_access_instr <= '1';
                    else
                        -- no lanes declared => fail-safe "0000" => wen all-ones
                        mem_access_instr <= '0';  -- F2: and no READ either
                    end if;
                    
                    -- D1 halt/step recognition, above both delivery takes (see the
                    -- first site, in EXECUTE shape STRADDLE, for the full argument).
                    if dbg_halt_take = '1' then
                        next_state <= DBG_SV;
                        ci_pc_advance <= '0';
                    elsif irq_save = '1' then
                        next_state <= IRQ_SV;
                        ci_pc_advance <= '0';
                    elsif std_irq_take = '1' then
                        -- P1 standard delivery: the SAME check point, no new one. In
                        -- standard mode irq_save can never fire (irq_en_eff is masked
                        -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                        -- legacy mode std_irq_take is '0' -- the two arms are mutually
                        -- exclusive by construction. The X3 uninterruptible sequencers
                        -- stay uninterruptible: they have no irq_save site, so they get
                        -- no std_irq_take site either.
                        next_state <= MTRAP_SV;
                        ci_pc_advance <= '0';
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
                -- P3 (§4 "sequencer steps check each generated address pre-issue
                -- and abort with NO sp/rd commit; mepc = the cm/cbo instruction"):
                -- the per-word check rides THIS state, because the burst address
                -- (cboz_base + 4*cboz_idx) only exists here. Denied => no lane
                -- strobe, no request, and the data_addr mux term for CBOZ_WRITE is
                -- gated by the same pmp_d_deny, so the denied word is never on the
                -- bus. cboz.zero writes no register, and pc_en has been '0' since
                -- dispatch, so pc still holds the cbo.zero itself => mepc is right.
                -- Zicboz is OFF in the Castalia/Argus configs: this arm is
                -- structural (it folds away with ENABLE_ZICBOZ) and sim-untested
                -- in P3 -- flagged for the red team.
                when CBOZ_WRITE =>
                    -- S2 c12: MIGRATED.  PC frozen and no rd commit for the whole
                    -- burst -- both are the fail-safe defaults, so neither is
                    -- declared.  Only the store lanes differ per branch: the
                    -- PMP-deny path declares nothing (=> all-ones, no strobe) and
                    -- the store path declares the FULL-WORD "1111".
                    -- mem_access_instr is not owned and keeps its per-branch
                    -- protocol values.
                    if ENABLE_PMP and pmp_d_deny = '1' then
                        mem_access_instr <= '0';
                        if dbg_exc_take = '1' then
                            -- D2/F-D2-0 re-entry (see dbg_exc_take): debug mode never traps out.
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
                    -- S2 c12: MIGRATED.  A pure hold cycle: no PC advance, no rd
                    -- commit, no store -- all three are the fail-safe defaults, so
                    -- this arm declares nothing at all.  mem_access_instr '0' is
                    -- what makes it the req-low settle the arbiter needs.
                    mem_access_instr <= '0';
                    if cboz_idx = CBOZ_WORDS - 1 then
                        next_state <= MEMORY_WAIT;
                    else
                        next_state <= CBOZ_WRITE;
                    end if;

                -- X3 Zcmp/Zcmt sequencer states. All UNINTERRUPTIBLE (no irq_save);
                -- sp committed once, last (ZCM_SP_COMMIT); indices/addresses all
                -- from registered state.
                -- P3: per-slot pre-issue check, same contract as CBOZ_WRITE. sp is
                -- committed ONCE and LAST (ZCM_SP_COMMIT), which a fault here never
                -- reaches -- so the "no sp/rd commit" half of §4 is structural, and
                -- pc (frozen since dispatch) is the cm.push itself. Zcmp/Zcmt are
                -- OFF in the Castalia/Argus configs => structural, sim-untested.
                when ZCM_PUSH_ST =>
                    -- S2 c13: MIGRATED.  PC frozen and no rd commit for the whole
                    -- push sequence (sp is committed ONCE, LAST, in
                    -- ZCM_SP_COMMIT) -- both fail-safe, so neither is declared.
                    -- Only the store lanes differ per branch, exactly as in
                    -- CBOZ_WRITE: the PMP-deny path declares nothing (=> all-ones,
                    -- no strobe), the store path declares the FULL-WORD "1111".
                    if ENABLE_PMP and pmp_d_deny = '1' then
                        mem_access_instr <= '0';
                        if dbg_exc_take = '1' then
                            -- D2/F-D2-0 re-entry (see dbg_exc_take): debug mode never traps out.
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

                when ZCM_PUSH_GAP =>
                    -- S2 c13: MIGRATED -- pure settle cycle, declares nothing.
                    mem_access_instr <= '0';
                    if zcm_idx = zcm_nregs_val - 1 then
                        next_state <= ZCM_SP_COMMIT;
                    else
                        next_state <= ZCM_PUSH_ST;
                    end if;

                -- P3: per-slot pre-issue check (cause 5 -- a pop slot is a LOAD).
                -- The register writeback happens in ZCM_POP_WB, which a fault never
                -- reaches => no rd commit. Structural, sim-untested (Zcmp OFF).
                when ZCM_POP_LD =>
                    -- S2 c13: MIGRATED -- issues the frame-slot load; the
                    -- writeback is ZCM_POP_WB's, so this cycle declares nothing.
                    if ENABLE_PMP and pmp_d_deny = '1' then
                        mem_access_instr <= '0';
                        if dbg_exc_take = '1' then
                            -- D2/F-D2-0 re-entry (see dbg_exc_take): debug mode never traps out.
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

                when ZCM_POP_WB =>
                    -- S2 c13: MIGRATED -- a cm.pop rd commit site.  The value is
                    -- the loaded frame word, so the declaration is '1'.
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

                when ZCM_A0Z =>
                    -- S2 c13: MIGRATED -- cm.popretz's a0 <- 0, an rd commit.
                    ci_rd_commit     <= '1';
                    mem_access_instr <= '0';
                    next_state       <= ZCM_SP_COMMIT;

                when ZCM_SP_COMMIT =>
                    -- S2 c13: MIGRATED, and the one PAIRING to be careful with.
                    -- sp_write_en is OWNED and migrates; sp_write_data is NOT
                    -- owned and stays right here.  They remain same-cycle: the
                    -- commit block is COMBINATIONAL and lives in this very
                    -- process, so it assigns sp_write_en later in the SAME
                    -- evaluation that assigns sp_write_data below -- both settle
                    -- in the same delta and land on the same clock edge.  Only
                    -- which statement writes the enable moved.  (A REGISTERED
                    -- interface would have broken exactly this; spec section 0
                    -- rejected one, and this arm is why it matters.)
                    mem_access_instr <= '0';
                    ci_sp_commit     <= '1';
                    sp_write_data    <= zcm_final_sp;
                    if zcm_is_popret = '1' then
                        next_state <= ZCM_RET;
                    else
                        next_state <= MEMORY_WAIT;
                    end if;

                when ZCM_RET =>
                    -- S2 c13: MIGRATED -- cm.popret's PC redirect; no commit.
                    ci_pc_advance    <= '1';
                    mem_access_instr <= '0';
                    next_state       <= EXECUTE;

                when ZCM_MV1 =>
                    -- S2 c13: MIGRATED -- first of the two cm.mv rd commits.
                    ci_rd_commit     <= '1';
                    mem_access_instr <= '0';
                    next_state       <= ZCM_MV2;

                when ZCM_MV2 =>
                    -- S2 c13: MIGRATED -- second cm.mv rd commit; retires via
                    -- MEMORY_WAIT.
                    ci_rd_commit     <= '1';
                    mem_access_instr <= '0';
                    next_state       <= MEMORY_WAIT;

                -- P3: the Zcmt jump-TABLE fetch is a DATA read of jvt+4*index
                -- (it rides data_addr, not the fetch path), so it is checked on the
                -- data port and reports cause 5. The target capture and the ra link
                -- both live in ZCM_JT_WB, which a fault never reaches. Structural,
                -- sim-untested (Zcmt OFF).
                when ZCM_JT_LD =>
                    -- S2 c13: MIGRATED -- issues the jvt table read; the target
                    -- capture and the ra link both land in ZCM_JT_WB.
                    if ENABLE_PMP and pmp_d_deny = '1' then
                        mem_access_instr <= '0';
                        if dbg_exc_take = '1' then
                            -- D2/F-D2-0 re-entry (see dbg_exc_take): debug mode never traps out.
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

                when ZCM_JT_WB =>
                    -- S2 c13: MIGRATED.  The rd commit is CONDITIONAL on the
                    -- computed zcm_jt_link (cm.jalt links ra, cm.jt does not) --
                    -- the declaration carries that value verbatim; the
                    -- computation stays at its own site.
                    ci_pc_advance    <= '1';
                    ci_rd_commit     <= zcm_jt_link;
                    mem_access_instr <= '0';
                    next_state       <= EXECUTE;

                -- ==========================================
                -- FENCE State - Fence operation
                -- ==========================================
                -- Note - for single core - fence may be treated as nop
                when FENCE_WAIT =>
                    -- S2 c15: MIGRATED.  The fence retires here, so the PC
                    -- advance is declared; no store and no rd commit are the
                    -- fail-safe defaults.  (The deleted lane drive was spelled
                    -- `WEN` in upper case -- the S0 census's case-insensitivity
                    -- landmark; a case-sensitive edit would have left a live
                    -- drive behind in a migrated state.)
                    next_state <= EXECUTE;
                    ci_pc_advance <= '1';

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
                    -- S2 c15: MIGRATED.  A hold with a conditional retire: the
                    -- window-closed branch declares the PC advance, the holding
                    -- branch declares nothing.  No store, no rd commit -- both
                    -- fail-safe.  pause_cnt is untouched.
                    mem_access_instr <= '0';
                    if pause_cnt = 0 then
                        next_state <= EXECUTE;   -- window closed: PAUSE retires
                        ci_pc_advance <= '1';
                    else
                        next_state <= PAUSE_WAIT;
                    end if;

                -- ==========================================
                -- MEMORY_WAIT State
                -- ==========================================
                when MEMORY_WAIT =>
                    -- S2 c8: MIGRATED -- the first LIVE commit site to go through
                    -- the table.  This state is the LOAD's rd commit site: its rd
                    -- write is CARRIED, not suppressed, on every one of the four
                    -- paths out, which is why the declaration sits at the arm top
                    -- rather than in a branch.  The value is the live decode, and
                    -- it is the same expression the process default used to supply
                    -- -- only the carrier changed.  F4 assert (1) polices it and
                    -- is unaffected: it reads the net, which still evaluates to
                    -- reg_write_ctrl on every cycle.
                    ci_rd_commit <= reg_write_ctrl;
                    -- D1 halt/step recognition, above both delivery takes (see the
                    -- first site, in EXECUTE shape STRADDLE, for the full argument).
                    if dbg_halt_take = '1' then
                        next_state <= DBG_SV;
                    elsif irq_save = '1' then
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
                    elsif isr_ret = '1' then
                        next_state <= IRQ_REST;
                    else
                        next_state <= EXECUTE;
                        ci_pc_advance <= '1';
                    end if;

                -- ==========================================
                -- DIV_WAIT State
                -- ==========================================
                when DIV_WAIT =>
                    -- N1 / R-S1-1c CLOSED HERE BY S2 c9.  This state never drove
                    -- wen, so wen used to fall through to the decoder's live lane
                    -- strobes and was a non-store only by a cross-file decode
                    -- coincidence.  ci_st_lanes still declares NOTHING, but that
                    -- now MEANS something: the block drives all-ones here
                    -- structurally.  The coincidence is closed, not relied on.
                    -- The evidence it was safe to close is the shadow checker's
                    -- silence at this exact site since S1 -- which is what
                    -- declaring nothing was for.
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
                    -- S2 c9: MIGRATED.  This is the DIV's rd commit site: it
                    -- CARRIES the live decode through to rd rather than
                    -- suppressing it, which is why the declaration is
                    -- reg_write_ctrl and not '0'.  F4 assert (2) polices it and is
                    -- unaffected -- it reads the net, which still evaluates to
                    -- reg_write_ctrl on every cycle.  wen is the N1 site closed
                    -- here (see DIV_WAIT).
                    ci_pc_advance <= '1';
                    ci_rd_commit  <= reg_write_ctrl;

                    -- D1 halt/step recognition, above both delivery takes (see the
                    -- first site, in EXECUTE shape STRADDLE, for the full argument).
                    if dbg_halt_take = '1' then
                        next_state <= DBG_SV;
                        ci_pc_advance <= '0';
                    elsif irq_save = '1' then
                        next_state <= IRQ_SV;
                        ci_pc_advance <= '0';
                    elsif std_irq_take = '1' then
                        -- P1 standard delivery: the SAME check point, no new one. In
                        -- standard mode irq_save can never fire (irq_en_eff is masked
                        -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                        -- legacy mode std_irq_take is '0' -- the two arms are mutually
                        -- exclusive by construction. The X3 uninterruptible sequencers
                        -- stay uninterruptible: they have no irq_save site, so they get
                        -- no std_irq_take site either.
                        next_state <= MTRAP_SV;
                        ci_pc_advance <= '0';
                    -- S2 c9 (R-DS2 item 9): the dead `elsif isr_ret = '1'` arm that
                    -- stood here is DELETED.  w5_report residue 4 recorded it and
                    -- handed it to "the next programme that opens vesta.vhd for a
                    -- real change".  Deadness, from the tree: isr_ret requires
                    -- op = CUSTOM_OPCODE (F5.3 note at the WORD-ALIGNED COMPRESSED
                    -- arm), DIV_DONE holds the dispatching encoding via the
                    -- instr_curr mux's `instr_curr_prev when current_state =
                    -- DIV_DONE` term, and DIV_DONE is reachable only from DIV_WAIT,
                    -- itself reachable only from EXECUTE's is_div_op arm -- so the
                    -- held encoding is necessarily a DIV (op = OP) and isr_ret is
                    -- statically '0'.  The `else` below already handled these
                    -- cycles.  NOTE: Genus could not prove this (isr_ret is a live
                    -- controller output off a flop-held instr_curr), so the mux
                    -- term was really synthesised and this deletion removes gates.
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
                    -- N1 / R-S1-1c closed here by S2 c9 (see DIV_WAIT).
                    next_state <= FPU_WAIT;

                -- ==========================================
                -- FPU_WAIT State (X4 Zfinx) - run the multi-cycle unit
                -- ==========================================
                -- Exactly the DIV_WAIT contract: PC frozen, no rd commit, instr
                -- held -- all three now declared through the commit block rather
                -- than driven here. fpu_start is asserted (concurrently, from
                -- state = FPU_WAIT) while waiting; fpu_done ends the stall.
                when FPU_WAIT =>
                    -- N1 / R-S1-1c closed here by S2 c9 (see DIV_WAIT).
                    if fpu_done_sig = '1' then
                        next_state <= FPU_DONE;
                    else
                        next_state <= FPU_WAIT;
                    end if;

                -- ==========================================
                -- FPU_DONE State (X4 Zfinx) - writeback + flags
                -- ==========================================
                -- Mirrors DIV_DONE exactly: this state CARRIES the live decode
                -- through to rd (reg_write_ctrl = 1 for an FP op) and the
                -- writeback of the fpu result (result_src=111) lands in this cycle.
                -- IRQ handling is identical to DIV_DONE.
                when FPU_DONE =>
                    -- S2 c9: MIGRATED, and the FP rd commit site -- carried, not
                    -- suppressed, exactly as at DIV_DONE.  F4 assert (3) polices it
                    -- and is unaffected: it reads the net, still reg_write_ctrl on
                    -- every cycle.  wen is the N1 site closed here (see DIV_WAIT).
                    ci_pc_advance <= '1';
                    ci_rd_commit  <= reg_write_ctrl;

                    -- D1 halt/step recognition, above both delivery takes (see the
                    -- first site, in EXECUTE shape STRADDLE, for the full argument).
                    if dbg_halt_take = '1' then
                        next_state <= DBG_SV;
                        ci_pc_advance <= '0';
                    elsif irq_save = '1' then
                        next_state <= IRQ_SV;
                        ci_pc_advance <= '0';
                    elsif std_irq_take = '1' then
                        -- P1 standard delivery: the SAME check point, no new one. In
                        -- standard mode irq_save can never fire (irq_en_eff is masked
                        -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                        -- legacy mode std_irq_take is '0' -- the two arms are mutually
                        -- exclusive by construction. The X3 uninterruptible sequencers
                        -- stay uninterruptible: they have no irq_save site, so they get
                        -- no std_irq_take site either.
                        next_state <= MTRAP_SV;
                        ci_pc_advance <= '0';
                    -- S2 c9 (R-DS2 item 9): dead `elsif isr_ret = '1'` arm DELETED
                    -- here too -- same argument as DIV_DONE's, with FPU_DONE
                    -- reachable only from FPU_WAIT and holding an FP encoding, so
                    -- isr_ret is statically '0'.  w5_report residue 4.
                    else
                        next_state <= EXECUTE;
                    end if;

                -- ==========================================
                -- IRQ_SV State - Save context for interrupt
                -- ==========================================
                when IRQ_SV =>
                    -- S2 c14: MIGRATED.  The full-word PC push -- the ONE active
                    -- store declaration outside the data states.  ACTIVE-HIGH
                    -- "1111" here is the block's `wen <= not ci_st_lanes`
                    -- all-lanes-low strobe.
                    ci_st_lanes <= "1111";

                    -- Update stack pointer.  sp_write_en is OWNED and now arrives
                    -- from the commit block via ci_sp_commit; sp_write_data is NOT
                    -- owned and stays here.  Same-evaluation, combinational block:
                    -- the two settle within deltas of one another and take effect
                    -- on the same edge, which is all their clocked consumers see.
                    ci_sp_commit <= '1';
                    sp_write_data <= std_logic_vector(unsigned(stack_pointer) - 4);

                    -- No writeback belongs to the IRQ dispatch cycles: the
                    -- instruction mux shows the already-retired interrupted
                    -- instruction here (a load decodes RegWrite=1 and would
                    -- re-write its rd with garbage) and raw read_data during
                    -- IRQ_JUMP (arbitrary image -> arbitrary rd).  That
                    -- suppression is now STRUCTURAL: this arm declares no rd
                    -- commit, so the block drives '0' and there is no drive left
                    -- to forget.  Caught by rv32ui-p-irqctx (phantom t1 write
                    -- during IRQ_JUMP).
                    next_state <= IRQ_JUMP;

                -- ==========================================
                -- IRQ_JUMP State - Jump to interrupt vector
                -- ==========================================
                when IRQ_JUMP =>
                    -- S2 c14: MIGRATED.  Loads the IVT entry; no store, no rd
                    -- commit (see IRQ_SV's note -- read_data is an arbitrary
                    -- image here), both now structural.
                    irq_save_ack <= '1';
                    ci_pc_advance <= '1';
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
                    -- S2 c14: MIGRATED.  Every memory effect this state must NOT
                    -- have -- no push, no sp touch, no writeback -- is now the
                    -- fail-safe default, so the arm declares nothing at all.
                    mem_access_instr <= '0';
                    next_state       <= MTRAP_JUMP;

                -- ==========================================
                -- MTRAP_JUMP State - P1 standard trap entry (vector)
                -- ==========================================
                -- PC <- mtvec.BASE&"00" via the pc_next mux arm; the same cycle
                -- issues the fetch from there (data_addr falls through to
                -- pc_next), exactly like IRQ_JUMP loading ivt_entry.
                when MTRAP_JUMP =>
                    -- S2 c14: MIGRATED.
                    ci_pc_advance    <= '1';
                    mem_access_instr <= '0';
                    next_state       <= EXECUTE;

                -- ==========================================
                -- MTRAP_RET State - P1 MRET
                -- ==========================================
                -- PC <- mepc (pc_next mux arm) plus the mstatus POP in csr_unit
                -- (MIE<=MPIE, MPIE<='1') via the mret_we one-shot. No memory
                -- access, no writeback, no sp touch -- the JALR shape.
                when MTRAP_RET =>
                    -- S2 c14: MIGRATED.  The JALR shape: PC <- mepc, no access,
                    -- no writeback, no sp touch -- all fail-safe.
                    ci_pc_advance    <= '1';
                    mem_access_instr <= '0';
                    next_state       <= EXECUTE;

                -- ==========================================
                -- D1 DEBUG-MODE STATES (ENABLE_DEBUG)
                -- ==========================================
                -- All three are the MTRAP_RET / IRQ_JUMP shape: declare
                -- ci_pc_advance, hold mem_access_instr low so data_addr falls
                -- through to pc_next and the SAME cycle issues the fetch from
                -- the new PC, and declare NOTHING else. That is the entire
                -- commit interface a halt, a re-entry and a resume need
                -- (D0/P1 1b) -- zero new suppression terms.
                --
                -- WHY DBG_SV IS ONE STATE AND MTRAP_SV IS TWO. The CSR write
                -- rides the dbg_entry_we one-shot, which fires on the FIRST
                -- free-clk edge of the state, and csr_unit samples dbg_pc at
                -- that same edge -- i.e. the PRE-edge value of pc/pc_next_reg,
                -- which is what the entry must record. pc_en is '1' in the
                -- same cycle, so debug_mode and pc <- DEBUG_ENTRY_ADDR land on
                -- ONE edge. That simultaneity is load-bearing for the
                -- halt-on-reset instrument, which reads pc at the moment
                -- dbg_halted rises and requires it to be DEBUG_ENTRY_ADDR.
                -- If clk_cpu is gated here (a DEBUG_ENTRY_ADDR in the shared
                -- window stalls its own fetch) the state simply holds; the
                -- one-shot is on the free clk and still fires exactly once.
                when DBG_SV =>
                    ci_pc_advance    <= '1';
                    mem_access_instr <= '0';
                    next_state       <= EXECUTE;

                -- Re-entry from an ebreak taken BY DEBUG CODE. Identical to
                -- DBG_SV minus the strobe: dpc and dcsr.cause must survive, or
                -- the debugger loses its own return address.
                when DBG_JUMP =>
                    ci_pc_advance    <= '1';
                    mem_access_instr <= '0';
                    next_state       <= EXECUTE;

                -- DRET. PC <- dpc via the pc_next mux arm, plus the debug_mode
                -- clear and the privilege pop in csr_unit via the dbg_ret_we
                -- one-shot. Retires, exactly as MTRAP_RET does.
                when DBG_RET =>
                    ci_pc_advance    <= '1';
                    mem_access_instr <= '0';
                    next_state       <= EXECUTE;

                -- ==========================================
                -- IRQ_REST State - Restore context from interrupt
                -- ==========================================
                when IRQ_REST =>
                    -- W2/F4a: NOTHING may write rd here.  This arm used to fall
                    -- through to the `reg_write_dp <= reg_write_ctrl` default in
                    -- the else branch of this process (the pre-case default
                    -- block) and was correct only by a DECODE COINCIDENCE:
                    -- instr_curr is held at the `iret`, which is CUSTOM_OPCODE,
                    -- and maindec's reg_write list (:960-973) happens to end
                    -- `'0'; -- No write for stores, branches, custom
                    -- instructions`.  Nothing enforced that, in either file.
                    -- Unlike MEMORY_WAIT / DIV_DONE / FPU_DONE -- which are REAL
                    -- COMMIT SITES, each CARRYING the live decode through to rd
                    -- (by whichever mechanism currently delivers it), and which
                    -- therefore get an assertion instead -- IRQ_REST has no rd to
                    -- commit at all, so the coincidence is simply removed.
                    -- S2 c14: MIGRATED.  The rd suppression above is now
                    -- STRUCTURAL -- this arm declares no rd commit, so the block
                    -- drives '0'; the coincidence is closed, not relied on.
                    -- D1 halt/step recognition, above both delivery takes (see the
                    -- first site, in EXECUTE shape STRADDLE, for the full argument).
                    if dbg_halt_take = '1' then
                        next_state <= DBG_SV;
                    elsif irq_save = '1' then
                        -- Nested interrupt
                        next_state <= IRQ_SV;
                        -- N1 / R-S1-2 CLOSED HERE BY c14: this path has no wen
                        -- arm, so wen used to fall through to the live decode of
                        -- the HELD word -- the `iret` -- in a NON-DISPATCH state.
                        -- ci_st_lanes still declares NOTHING, but that now MEANS
                        -- something: the block drives all-ones structurally.  The
                        -- evidence it was safe to close is the shadow checker's
                        -- silence at this exact site since S1.
                    elsif std_irq_take = '1' then
                        -- P1 standard delivery: the SAME check point, no new one. In
                        -- standard mode irq_save can never fire (irq_en_eff is masked
                        -- all-zero, so the irq_handler FSM is pinned in IDLE), and in
                        -- legacy mode std_irq_take is '0' -- the two arms are mutually
                        -- exclusive by construction. The X3 uninterruptible sequencers
                        -- stay uninterruptible: they have no irq_save site, so they get
                        -- no std_irq_take site either.
                        next_state <= MTRAP_SV;
                        -- N1 / R-S1-2 closed here by c14, as on the irq_save path.
                    elsif sleep_cpu = '1' then
                        -- Return to sleep after interrupt.  sp_write_data stays
                        -- here; the enable now arrives from the block via
                        -- ci_sp_commit -- same evaluation, same edge (IRQ_SV).
                        next_state <= SLEEPING;
                        ci_sp_commit <= '1';
                        sp_write_data <= std_logic_vector(unsigned(stack_pointer) + 4);
                    else
                        -- Return to normal execution
                        next_state <= EXECUTE;
                        ci_sp_commit <= '1';
                        sp_write_data <= std_logic_vector(unsigned(stack_pointer) + 4);
                        ci_pc_advance <= '1';
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
                    -- S2 c15: MIGRATED.  Two things this arm used to hold by
                    -- coincidence are now structural, which matters more here than
                    -- anywhere else because a sleep lasts an unbounded, clock-gated
                    -- number of cycles:
                    --   * rd (W2/F4a): the held encoding is the `extinguish`/`wfi`
                    --     that put us here, so reg_write_ctrl was '0' only by the
                    --     maindec coincidence.  This arm now declares no rd
                    --     commit, so the block drives '0' outright.
                    --   * lanes (N1 / R-S1-1c): there is no wen site here, so wen
                    --     used to fall through to the live decode.  ci_st_lanes
                    --     still declares NOTHING, and that now MEANS all-ones from
                    --     the block.  This was the LAST live N1 site; the licence
                    --     to close it is the shadow checker's silence here across
                    --     every gate since S1.
                    -- The PC is held by declaring nothing; the only ci_pc_advance
                    -- below sits in the P2 std_wfi_wake leg, which is statically
                    -- unreachable while ENABLE_TRAPCSR is false -- real wakes take
                    -- the irq_save leg and must NOT advance the PC, since it is the
                    -- return address IRQ_SV is about to push.

                    -- D1 halt/step recognition, above both delivery takes (see the
                    -- first site, in EXECUTE shape STRADDLE, for the full argument).
                    if dbg_halt_take = '1' then
                        next_state <= DBG_SV;
                    elsif irq_save = '1' then
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
                        ci_pc_advance <= '1';
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
                    -- S2 c15: MIGRATED.  Same shape as PAUSE_WAIT: the wake branch
                    -- declares the PC advance and retires the hint; the stalled
                    -- branch declares nothing.  wrs_wake is untouched.
                    mem_access_instr <= '0';
                    if wrs_wake = '1' then
                        next_state <= EXECUTE;
                        ci_pc_advance <= '1';
                    else
                        next_state <= WRS_WAIT;
                    end if;

                -- ==========================================
                -- TRAP State
                -- ==========================================
                when TRAP_STATE =>
                    -- F8 (fix pass W1), and S2 c14 makes it STRUCTURAL.
                    -- HISTORY, which must not be lost: TRAP_STATE originally
                    -- assigned no `wen` at all, so it inherited the process
                    -- default `wen <= wen_controller` -- the DECODER's live lane
                    -- strobes. TRAP_STATE is also absent from the instr_curr hold
                    -- list, so instr_curr = instr_decomp of the live bus word; a
                    -- store encoding on read_data therefore committed a REAL
                    -- store at data_addr every cycle of this self-loop, until the
                    -- tb watchdog. F8 fixed it with an explicit all-ones drive.
                    -- NOW: this arm declares no store lanes, so the block drives
                    -- all-ones -- the protection is the fail-safe default rather
                    -- than a line someone must remember to keep. The F8 class
                    -- cannot recur here: there is no drive left to omit.
                    -- mem_access_instr is at its '0' default and the state is
                    -- terminal, so nothing downstream consumes an access from it.
                    -- Detector: rv32ua-p-trapstor.
                    --
                    -- D1 (R-D0-3(6), d1_spec.md 2): THE 14TH RECOGNITION SITE,
                    -- and the only one that is not also an interrupt site. A
                    -- WEDGED HART IS THE HIGHEST-VALUE HALT TARGET a debugger
                    -- has, and until now it was the one state a halt could not
                    -- reach. This is an addition to the RECOGNITION set, not a
                    -- suppression term: it declares no commit, so the state's
                    -- fail-safe drives are untouched on the halt cycle too.
                    -- IT IS A REAL SEMANTIC MOVE, ruled deliberately: a
                    -- terminal state becomes non-terminal WHEN A DEBUGGER IS
                    -- ATTACHED AND THE KNOB IS ON. Knob-OFF, dbg_halt_take is
                    -- statically '0' and this collapses to the unconditional
                    -- self-loop it has always been -- bit-identical, which is
                    -- what the standing sweeps pin. Do NOT read this as
                    -- "TRAP_STATE is diagnosable now": in the reset
                    -- configuration nothing raises dbg_haltreq, so the wedge is
                    -- exactly as terminal as it was.
                    if dbg_halt_take = '1' then
                        next_state <= DBG_SV;
                    else
                        next_state <= TRAP_STATE;
                    end if;
                    trap_flag <= '1';

                -- ==========================================
                -- Default Case
                -- ==========================================
                when others =>
                    -- F5.1 (fix pass W1), CLOSED STRUCTURALLY BY THE S2 CLEANUP.
                    -- HISTORY: `reg_write_dp <= reg_write_dp` here was a
                    -- self-assignment that overrode the process default and so
                    -- inferred a SECOND latch -- `reg_write_dp_reg` was a real
                    -- LATQX1MA10TH in the netlist, not a lint curiosity.  The
                    -- arm looks unreachable in the STATE enumeration, but the
                    -- enumeration is encoded in more bits than it has values, so
                    -- an illegal encoding reaches here and holding reg_write_dp
                    -- would have committed a stale regfile write.  F5.1 replaced
                    -- the hold with an explicit '0'.  The arm itself stays: VHDL
                    -- requires it.
                    --
                    -- S2 deferred migrating that '0' until this commit, and the
                    -- order was load-bearing (R-S2-6): while the commit block was
                    -- still gated by a per-cpu_state table, this arm had no row
                    -- to turn on -- it covers NON-values of the type -- so under
                    -- an illegal encoding the lookup was a synthesis don't-care
                    -- and deleting the drive could have dropped rd back onto the
                    -- live decode, recreating F5.1 exactly.  The gate is now
                    -- GONE: the block drives all four nets unconditionally, from
                    -- intent, whatever the state register holds.  This arm
                    -- declares no rd commit, so rd is driven '0' by construction
                    -- -- the protection no longer depends on anyone remembering
                    -- a line, and the latch cannot return.
                    --
                    -- pc_en's fall-through to '1' is genuine and is declared
                    -- below.  wen is NOT declared (R-S1-2): a store committing in
                    -- the illegal-encoding recovery arm would be a real finding,
                    -- and leaving it undeclared means the block drives all-ones
                    -- rather than the live decode -- the safe direction.
                    next_state <= EXECUTE;
                    ci_pc_advance <= '1';
            end case;

            -- =====================================================
            -- COMMIT BLOCK (S-series; S0 interface spec section 3)
            -- =====================================================
            -- THIS IS THE ONLY ASSIGNMENT SITE FOR THE FOUR NETS outside the
            -- resetn branch.  It is UNCONDITIONAL: every state reaches it, and
            -- what each state commits is decided entirely by the ci_* intent it
            -- declared in its own arm.  A state that declares nothing commits
            -- nothing and holds the PC -- so there is no longer anywhere to
            -- forget a `reg_write_dp <= '0'`, which is the whole point of the
            -- exercise (S0 spec section 6).
            --
            -- (History, because the scaffolding is gone and left no trace:
            -- migration ran state-by-state behind two temporary gates -- a
            -- constant table `state_commits_via_block` indexed by cpu_state, and
            -- for the five commits that split EXECUTE a process variable
            -- `v_exec_via_block`.  The variable died when EXECUTE's seven
            -- dispatch shapes were all migrated; the table died here, when all
            -- 39 rows had become true and it selected everything.  Both were
            -- built with a scheduled death and both met it.)
            -- It sits INSIDE the else branch on purpose: the resetn branch is
            -- out of its reach, and reproduces its own four values exactly --
            -- two of which are deliberately NOT the fail-safe ones.  See the
            -- reset branch's note (spec section 3, ruling R-S1-1a).
            -- S3: intent is GATED BY PERMISSION.  A state may commit only what
            -- its permission table allows; anything else is squashed here and
            -- shouted about by s3_perm_assert_proc.  pc_advance is deliberately
            -- ungated (see the tables' note).
            reg_write_dp <= ci_rd_commit  and rd_commit_allowed(current_state);
            sp_write_en  <= ci_sp_commit  and sp_commit_allowed(current_state);
            wen          <= not (ci_st_lanes and st_commit_allowed(current_state));
            pc_en        <= ci_pc_advance;
        end if;
    end process;

    -- ==========================================
    -- S3 COMMIT-PERMISSION ASSERTIONS (S-series; PERMANENT)
    -- ==========================================
    -- WHAT REPLACED THE S1 SHADOW CHECKER, deleted in this commit.
    --
    -- The shadow checker existed to prove, before anything depended on it, that
    -- the commit block could reproduce the machine it was going to own.  It did
    -- that job across S1 and all of S2 -- it is why every migration could be
    -- made value-equal by MEASUREMENT rather than by argument, and it caught the
    -- N1 decode coincidences at nine sites as they closed one by one.  When the
    -- S2 cleanup made the block the sole driver in every state, the checker
    -- began comparing the block's outputs against the block's own inputs: it
    -- became tautological EVERYWHERE and its silence stopped being coverage.
    -- Keeping it would have been a decorative instrument (method rule 9/11), so
    -- it is gone.
    --
    -- THE REPLACEMENT, so no one has to reconstruct it:
    --   1. the PERMISSION MASKS in the commit block -- a state can no longer
    --      commit anything its table does not allow, structurally;
    --   2. THIS process -- the masks made loud.  A mask that silently squashes
    --      is exactly instrument rule 11's defect, so every squash is an
    --      assertion failure naming the signal and the state;
    --   3. the standing BIT-EXACT LOCKSTEP GATES, which were the real gate on
    --      every one of the sixteen migration commits and remain so;
    --   4. f4_assert_proc's four decode assertions, at the end of this
    --      architecture, which police a DIFFERENT property -- which encoding may
    --      be held when a permitted commit happens.  The masks and those four
    --      are complementary; neither subsumes the other.
    --
    -- Note what this process does NOT check: it says nothing about whether a
    -- PERMITTED commit carries the right VALUE.  That is the lockstep stream's
    -- job, and it compares every retire's rd across 4,668,509 records.
    --
    -- CLOCKED, not concurrent: a concurrent assertion samples mid-settle (F4b's
    -- first cut fired on 23 of 136 tests for exactly that reason).  Style,
    -- severity and the "a firing assertion is a FINDING, do not tune it away"
    -- contract are f4_assert_proc's -- read its block comment before touching
    -- this one.  These are PERMANENT: they compile into every configuration.
    --
    -- SCOPE: post-reset, on every rising clk_cpu edge.  The `resetn = '1'`
    -- qualifier is load-bearing (the reset branch drives its own values, which
    -- the block cannot reach).  clk_cpu is GATED, so a stalled cycle is
    -- structurally unchecked; the honest claim is "every core-advance edge".
    --
    -- Simulation-only in effect: assertions, no signal drives, so Genus emits
    -- nothing for them (VHDL-644).
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

    -- ==========================================
    -- Sleep/Wake Control Logic
    -- ==========================================
    -- Track CPU sleep state based on custom instructions
    process(clk, resetn)
    begin
        if resetn = '0' then
            sleep_cpu <= '0';
        elsif rising_edge(clk) then
            -- W2/F3+ and F3++: this flop is on the FREE-RUNNING clk while
            -- sleep_rq and wake_rq are PURE DECODES of instr_curr
            -- (maindec.vhd:922-923 -- no state qualification at all beyond the
            -- P2 u_gate), so it used to update in every state the old
            -- dec_squash blacklist did not name. BOTH directions leak, and they
            -- are two separate mechanisms sharing one live decode -- the raw bus
            -- word IRQ_SV puts on instr_curr (:1484), which on this path is
            -- deterministically the next instruction in program order:
            --
            --   F3+  (the SET leak). An `extinguish` encoding sitting there set
            --        sleep_cpu behind the FSM's back, and IRQ_REST's
            --        `elsif sleep_cpu = '1'` arm (:3557) then sent the hart to
            --        SLEEPING instead of resuming. A HANG, invisible to the a0
            --        contract, for a word the hart never executed.
            --   F3++ (the CLEAR leak -- the mirror image). An `ignite` encoding
            --        in the same position CLEARS the flop, so a hart that was
            --        legitimately asleep resumes instead of re-parking. That
            --        breaks the bootrom park contract DIRECTLY: the stray-msip
            --        ISRs (start.S:582-585, and the tile park at :468) rely on
            --        `iret` WITHOUT `ignite` leaving sleep_cpu SET so IRQ_REST
            --        returns the hart to its sleep. A silently-awake parked hart
            --        then spins in its `j <park>` paranoia loop, burning power
            --        and shared-bus bandwidth on a chip that gated its rails.
            --
            -- Hence the whole `if` is re-qualified, not just the set arm.
            --
            -- dec_dispatch (:1992) SUPERSEDES dec_squash here and subsumes it
            -- (dec_squash='0' is one of its terms), so both the P2 trap-entry
            -- rule -- a U-mode extinguish/ignite traps illegal and must not
            -- touch this flop -- and the P3 PMP park-word rule are preserved
            -- exactly. Nothing legitimate is lost: every real sleep/wake
            -- dispatch is an EXECUTE cycle (the extinguish/wfi arms at :2413 and
            -- :2709 are EXECUTE sub-arms, and the bootrom park/loader contract
            -- is EXECUTE-only too -- `EXTINGUISH` at start.S:468 and `IGNITE` at
            -- start.S:510 are both ordinary dispatches).
            --
            -- The one non-EXECUTE update that DOES disappear is benign, and it
            -- is worth naming so nobody re-derives it as a regression: SLEEPING
            -- holds instr_curr_prev (:1519) = the `extinguish` itself, so
            -- sleep_rq stayed HIGH for the whole sleep and this flop re-set an
            -- already-set bit on every free-running clk edge. Dropping that
            -- changes no value -- the flop holds, and no state that can run
            -- while asleep drives wake_rq. The return-to-sleep contract works by
            -- NOT clearing the flop, so this change can only remove spurious
            -- updates, never add one.
            if dec_dispatch = '1' then
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
            -- P2: the standard WFI decode out, and the three U-mode decode
            -- inputs straight from csr_unit's frozen 3.1 exports.
            wfi_op           => wfi_op,
            -- D1: the DRET decode out, and the debug-mode decode input from
            -- csr_unit -- the same route priv_m takes, for the same reason.
            dret_op          => dret_op,
            debug_mode       => debug_mode,
            priv_m           => trap_priv_mode,
            status_tw        => trap_status_tw,
            mcounteren_bits  => trap_mcounteren,
            -- F10 (fix pass W4): the SAME csr_rs1_zero the csr_unit already
            -- consumes for its write enable (:4479 below), so the decode's
            -- read-only-CSR trap and the write path can never disagree about
            -- what counts as a write.
            csr_rs1_zero     => csr_rs1_zero,
            -- F-BV1 (K5): the R-type rs2 field is zero -- the one bit maindec
            -- needs to tell Zbb `zext.h rd,rs1` apart from Zbkb
            -- `pack rd,rs1,rs2`, which are the SAME funct7/funct3/opcode.
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



    -- ==========================================
    -- K5 DEFECT B: the divide dispatch qualification
    -- ==========================================
    -- The ALU's divide FSM used to arm itself off `div_start_rq`, a bare
    -- combinational decode of `alu_control` (alu.vhd).  `alu_control` decodes
    -- `instr_curr`, and there are cycles in which instr_curr is NOT the
    -- instruction the hart is dispatching -- exactly the class :2307 names:
    --   * SHAPE E, the 32-bit split-fetch bubble (:1777): instr_curr is HELD at
    --     the PREVIOUS instruction.  MEASURED as the live trigger.
    --   * IRQ_SV (:1775): the RAW BUS WORD.
    --   * IRQ_JUMP / TRAP_STATE: they fall through this mux's tail to
    --     `instr_decomp`, a decode of the live bus word.
    -- In any of those, a divide-looking encoding armed the FSM, which latched
    -- the PREVIOUS divide's sel_signed/sel_rem and then STUCK in ALU_DIV_WAIT
    -- (only div_complete leaves it), so the next divide executed under the
    -- wrong opcode's selects.
    --
    -- The fix is a POSITIVE qualification, not a state blacklist -- :2307's own
    -- text records why a blacklist is only ever as good as the list, and that
    -- list had already missed six states once.  `next_state = DIV_WAIT` IS the
    -- dispatch: DIV_WAIT is reachable only from EXECUTE's is_div_op arms (the
    -- four shapes at :3021/:3164/:3323/:3434), so this term is exact BY
    -- CONSTRUCTION and cannot drift out of step with those guards the way a
    -- copy of their trap/shape predicates would.  Qualifying with
    -- `current_state = EXECUTE` narrows it to the dispatch cycle itself (during
    -- DIV_WAIT next_state is DIV_WAIT again while alu_done is low).
    --
    -- NOT a loop: div_dispatch feeds only the ALU FSM's CLOCKED arm, so nothing
    -- combinational returns from it to next_state.
    -- Timing is UNCHANGED on the correct path: the old arm also fired in this
    -- same EXECUTE cycle, so alu_state is still ALU_DIV_WAIT by the time the
    -- core reaches DIV_WAIT and alu_done's ALU_IDLE term still holds.
    div_dispatch <= '1' when (current_state = EXECUTE and next_state = DIV_WAIT) else '0';

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
            ENABLE_ZFINX    => ENABLE_ZFINX,
            TRACE_ENABLE    => TRACE_ENABLE
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
            -- V1 tracer taps: the regfile a3/wd3 nets (read-only)
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
    -- P3-entry: the rs1/uimm FIELD of the CSR instruction (same instruction
    -- source as csr_addr; for the immediate forms instr(19:15) IS uimm).
    -- Feeds csr_unit's write-form rule: CSRRS/CSRRC with rs1=x0 and
    -- CSRRSI/CSRRCI with uimm=0 must not assert the write enable.
    csr_rs1_zero <= '1' when instr_curr(19 downto 15) = "00000" else '0';
    -- F-BV1 (K5): the R-type rs2 FIELD (instr[24:20]) is zero. SAME instruction
    -- source as csr_addr/csr_rs1_zero, so the decode can never disagree with
    -- itself about which instruction it is looking at. Consumed ONLY by
    -- maindec's Zbb ZEXT.H legality row: `zext.h rd,rs1` and Zbkb
    -- `pack rd,rs1,x0` are one encoding (0x080ece33 for x28,x29), so rs2 is the
    -- only field that separates a legal zext.h from an unimplemented pack.
    -- A decompressed C.ZEXT.H arrives here with instr[24:20] = "00000"
    -- (c_dec.vhd's Zcb expansion writes that field explicitly), so the
    -- compressed form stays legal.
    rs2_zero <= '1' when instr_curr(24 downto 20) = "00000" else '0';

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
            csr_valid      => csr_valid_eff,   -- P2/W2: qualified by dec_dispatch
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
            mcounteren_bits => trap_mcounteren,

            -- P3-entry (p3_kickoff.md 3): write-form qualifier in; effective
            -- data-access privilege out (PMP data-side check consumer -- P3
            -- Agent B wires it into the check; unconsumed until then).
            csr_rs1_zero   => csr_rs1_zero,
            data_priv_m    => eff_data_priv_m,
            mret_priv_m    => mret_priv_m,   -- P3 red-team F1

            -- D1 debug-mode interface. The two strobes are the gen_debug
            -- one-shots; everything coming back is STATE that vesta's FSM,
            -- clock gate and (via controller) maindec consume.
            dbg_entry_we   => dbg_entry_we_sig,
            dbg_pc         => dbg_pc_val,
            dbg_cause      => dbg_cause_r,
            dbg_ret_we     => dbg_ret_we_sig,
            debug_mode     => debug_mode,
            dcsr_ebreakm   => dcsr_ebreakm,
            dcsr_ebreaku   => dcsr_ebreaku,
            dcsr_step      => dcsr_step,
            dpc_value      => dbg_dpc_value,

            -- P3 (p0_specs.md §4.1): the pmpcfg0-3 / pmpaddr0-15 bank,
            -- flattened. Both are all-zero when ENABLE_PMP is false (nothing
            -- ever writes the flops), which is the second half of the OFF fold
            -- -- the first being that gen_pmp does not instantiate pmp_unit.
            pmp_cfg_flat   => pmp_cfg_flat_sig,
            pmp_addr_flat  => pmp_addr_flat_sig,

            -- V1 tracer exports (read-only). csr_commit_we is generated INSIDE
            -- csr_unit and is asserted only when a write-case arm actually
            -- stores -- a vesta-level reproduction of csr_write_en would log
            -- writes that never committed (red-team R4 / finding F10).
            csr_commit_we  => csr_commit_we,
            csr_commit_val => csr_commit_val,
            mstatus_value  => mstatus_value,
            fflags_value   => fflags_value
        );

    -- ==========================================================
    -- V1 SPIKE-LOCKSTEP TRACER (TRACE_ENABLE only)
    -- ==========================================================
    -- A PURE OBSERVER: vesta_tracer has no output ports, so this block cannot
    -- affect the design in the ON build either -- it only writes a file.
    -- Elaboration removes the whole block when TRACE_ENABLE is false.
    --
    -- THE STATE-ORDINAL CONTRACT: `cpu_state` is declared in this architecture
    -- and cannot cross a port boundary in VHDL-93, so the FSM state is passed
    -- as `cpu_state'pos(...)`. The ST_* constants in vesta_tracer.vhd MUST
    -- match the DECLARATION ORDER of the type at ~line 425 of this file.
    -- IF YOU ADD, REMOVE OR REORDER A STATE THERE, UPDATE vesta_tracer.vhd.
    -- (The two ordinal signals live inside the generate so the OFF build
    -- carries not even the conversion.)
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
                -- D1 (R-D0-3(1)): THE ORDINAL-COUNT ASSERT. `cpu_state` cannot
                -- cross a port boundary in VHDL-93, but its CARDINALITY is a
                -- natural and can. vesta_tracer compares this against its own
                -- ST_COUNT and FAILS AT ELABORATION on a mismatch, closing the
                -- add/remove half of a contract that had ZERO mechanical
                -- enforcement before (ST_COUNT was declared and never read).
                -- It does NOT catch a reorder at constant count; nothing cheap
                -- does, and saying so is better than implying the gap is shut.
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
                repeat_if        => repeat_if,
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
                -- A16/T2: the tracer's only new input. `sc_fail_ext` is an
                -- EXISTING vesta input port, so this creates no signal and no
                -- logic -- it is a wire already present in every build, read by
                -- an observer that only exists when TRACE_ENABLE is true.
                --
                -- WHY ITS COMPONENT DECLARATION SHARES A LINE WITH `funct3`
                -- (:483, and it looks wrong until you know this): Genus derives
                -- internal net names from the SOURCE LINE of the expression that
                -- creates them -- `add_1469_57`, `plus_3919_83`. Inserting even
                -- a comment line above ~3919 renumbers them, and the OFF-build
                -- netlist then differs from its predecessor in 1,794 lines of
                -- pure renaming. Measured, not feared: the first cut of this
                -- change did exactly that, and the diff was provably nothing
                -- else (identical cell counts, identical area to 3 decimals,
                -- byte-identical after normalising 7 line/col keys).
                -- A netlist A/B is the evidence that a tracer edit invalidates
                -- no hardened block, so it is worth keeping that A/B checkable
                -- with `grep -v 'Generated on' | md5sum` instead of a bespoke
                -- normaliser. Hence: NO NEW LINE above the last generated name.
                -- Anything below here is free -- which is why this comment can
                -- afford to exist at all.
                sc_fail_ext      => sc_fail_ext,
                csr_addr         => csr_addr,
                csr_commit_we    => csr_commit_we,
                csr_commit_val   => csr_commit_val,
                mstatus_value    => mstatus_value,
                fflags_value     => fflags_value,
                -- A17/F-K2b-1: the tracer's two new inputs. Both are EXISTING
                -- vesta signals (`fp_flags_we` :~1652, `fp_flags_val` :~1660,
                -- already wired to csr_unit) so this creates no logic and no
                -- net -- an observer reading wires that are present in every
                -- build. Their COMPONENT declaration shares :489 with
                -- `fflags_value` for the reason spelled out above `sc_fail_ext`:
                -- no new line may appear above the last Genus-named expression.
                -- Down here the port map is free, which is why this comment can
                -- exist at all.
                --
                -- WHY BOTH, AND WHY NOT READ THE CSR BACK INSTEAD. The committed
                -- fflags is `fflags_value or fp_flags_val` on THIS edge; reading
                -- the register on the NEXT edge would give the same answer only
                -- until an instruction writes fflags in between, and the Zfinx
                -- test harness does exactly that (`csrrw a1,fflags,x0` after
                -- every tested op). The tracer therefore computes the commit
                -- from the same two operands the flop captures, which is
                -- invariant 7 ("log what COMMITTED") applied literally.
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

    -- ==========================================
    -- W2/F4b DESIGN ASSERTIONS -- the decode coincidences, made CHECKED
    -- ==========================================
    -- Simulation-only by construction: a VHDL assertion has no hardware and
    -- Genus emits none for it (verified -- `sequential` and the gate census are
    -- unchanged with these present).
    --
    -- Findings F4 and F4-shapes-B/C are both of the form "this is correct only
    -- because two files happen to agree, and nothing checks that they do".  The
    -- fix for a coincidence is not to remove the mechanism -- MEMORY_WAIT,
    -- DIV_DONE and FPU_DONE are REAL COMMIT SITES: each CARRIES the live decode
    -- through to rd rather than suppressing it, and that is precisely how a
    -- load, a div and an FP op write their rd (v1_retire_enumeration.md 5,
    -- rows 4, 6, 9).  Removing the carrier would break them.  The S-series is
    -- MOVING that carrier, state by state, from the process default to the
    -- commit block -- which changes who delivers the value, never the value --
    -- so do not read "fall-through" into these three; read "not suppressed".
    -- The fix is to make the coincidence FAIL LOUDLY the day someone breaks it.
    --
    -- CLOCKED, NOT CONCURRENT -- and this is load-bearing, not style.  The
    -- first cut of this block used concurrent assertions, and assertion (4)
    -- then fired on 23 of the 136 standing tests (every AMO / LR-SC / sh* cell)
    -- as a pure FALSE POSITIVE.  A concurrent assertion re-evaluates on EVERY
    -- delta in which any of its operands moves, i.e. it samples the
    -- combinational cone MID-SETTLE.  Probed at the fire point on
    -- rv32ua-p-amoadd_w: state=EXECUTE, is_compressed='1', pc(1)='0',
    -- quadrant_lower="00" (a genuine shape-C compressed cycle) -- but
    -- amo_op='1' with instr_curr=0x00000000, which is impossible in any settled
    -- state.  amo_op was simply one delta stale, still holding the PREVIOUS
    -- cycle's AMO decode while the shape terms had already advanced to the next
    -- (compressed) instruction.
    --   The design was never in that state.  c_dec.vhd emits ZERO instances of
    --   the AMO (0101111), FENCE (0001111), SYSTEM (1110011) and OP-FP
    --   (1010011) opcodes, so the guarded mechanism remains unreachable.
    -- Sampling at `rising_edge(clk_cpu)` reads the SETTLED pre-edge values, and
    -- it is also the more faithful property: every one of these is a statement
    -- about what a COMMIT EDGE does, not about a combinational instant.
    -- LESSON, worth more than the assertions: assertion (4) was built on
    -- `is_compressed`, a signal W1 had ALREADY documented (:615-625) as an
    -- inferred latch whose value is only meaningful under
    -- `EXECUTE and pc(1)='1' and repeat_if='0'`.  An assertion never seen to
    -- fire would have shipped this.
    --
    -- SEVERITY `error` -- AND IN THIS ENVIRONMENT THAT ABORTS THE SIMULATION.
    -- Measured, not assumed (W2, xrun/xmsim 20.09-s006): a firing assertion
    -- prints `ASSERT/ERROR ... F4 ASSERT: <text>` with the file and line, and
    -- the run STOPS THERE -- no TEST PASSED/FAILED, no a0 verdict, xmsim exits.
    -- Deliberate, and the choice is on the record: this project's history is
    -- silent coincidences surviving a year, so the failure mode to design
    -- against is being IGNORED, not being disruptive.
    -- THE CONSEQUENCE, for whoever hits this: if a future knobs-on
    -- configuration legitimately trips one of these, IT WILL KILL THE
    -- REGRESSION RUN, and the sim will die at the first occurrence rather than
    -- finishing with a report.  That is not a broken testbench.  Read the
    -- report string, then treat it as a FINDING -- these four encode decode
    -- coincidences across vesta.vhd, maindec.vhd and c_dec.vhd, and an
    -- assertion firing means the coincidence has broken.  Do not tune the
    -- assertion to fit the new build; fix the arm it is pointing at.
    -- These compile into every configuration, including the Argus N=18 suite
    -- and every opt-in P-series build.
    f4_assert_proc: process(clk_cpu)
    begin
        if rising_edge(clk_cpu) then

            -- (1) MEMORY_WAIT is the LOAD's commit site.  Every other encoding
            --     that can be held here -- STORE, cbo.zero, cm.push/cm.pop/
            --     cm.mv, and the `iret` (whose trajectory is
            --     EXECUTE -> MEMORY_WAIT -> IRQ_REST, v1 rev-2 R1) -- must
            --     decode reg_write='0' in maindec.  If one ever does not, it
            --     writes a garbage rd here -- and NOTHING STRUCTURAL STOPS IT,
            --     because MEMORY_WAIT is a legitimate rd commit site and its
            --     S3 permission mask therefore ALLOWS the write.  The masks
            --     police WHICH STATE may commit; this assertion polices WHICH
            --     ENCODING may be held when it does.  That is why the two are
            --     complementary and why neither retires the other.
            --     NOTE the scope caveat: with ENABLE_ZCMP on, the Zcmp rd
            --     commits happen in ZCM_POP_WB / ZCM_A0Z / ZCM_MV1 / ZCM_MV2,
            --     NOT here -- what reaches MEMORY_WAIT is the held ZCM sentinel,
            --     which decodes reg_write='0'.  So LOAD-only holds with the knob
            --     either way, and if a future Zcmp change made the sentinel
            --     write, this firing is the DESIRED outcome.
            assert not (current_state = MEMORY_WAIT and reg_write_dp = '1'
                        and instr_curr(6 downto 0) /= I_LOAD_OPCODE)
                report "F4 ASSERT: reg_write_dp asserted in MEMORY_WAIT for a non-LOAD encoding"
                severity error;

            -- (2) DIV_DONE is the DIV/DIVU/REM/REMU commit site.  The held
            --     encoding must still be the div that dispatched us here.
            assert not (current_state = DIV_DONE and reg_write_dp = '1'
                        and is_div_op = '0')
                report "F4 ASSERT: reg_write_dp asserted in DIV_DONE for a non-DIV encoding"
                severity error;

            -- (3) FPU_DONE is the multi-cycle / FMA FP commit site.  (Single-
            --     cycle FP retires in EXECUTE and never reaches this state.)
            --     Statically unreachable in the default build, where
            --     ENABLE_ZFINX is false and no FP op decodes at all -- so this
            --     one is a guard for the knobs-on configurations only, and the
            --     standing gates cannot exercise it.
            assert not (current_state = FPU_DONE and reg_write_dp = '1'
                        and is_fp_multicycle = '0' and is_fp_fma = '0')
                report "F4 ASSERT: reg_write_dp asserted in FPU_DONE for a non-multicycle-FP encoding"
                severity error;

            -- (4) The shapes-B/C missing-arm class.  The two COMPRESSED EXECUTE
            --     arms have NO lr_op / sc_op / amo_op / cboz_op / fence_op /
            --     wfi_op / wrs_op / is_fp_* branches at all.  That is
            --     unreachable TODAY only because no compressed encoding
            --     decompresses to any of them -- a property of c_dec.vhd that
            --     nothing in vesta.vhd enforces.  If a future Zc* extension ever
            --     emits one, the instruction would silently retire as a plain
            --     ALU op with its memory/atomic/FP side effect simply not
            --     performed.
            --     The shape terms are spelled out rather than reusing
            --     `is_compressed`, for the latch reason in the block comment
            --     above: these are exactly the two `instr_decomp` arms of the
            --     instr_curr mux (:1487 and :1489), written in terms of pc (a
            --     flop), repeat_if (a flop) and the quadrant bits (combinational
            --     off the bus) -- no latched FSM output is read.
            assert not (current_state = EXECUTE
                        and ((pc(1) = '1' and repeat_if = '0' and quadrant_upper /= "11")
                             or (pc(1) = '0' and quadrant_lower /= "11"))
                        and (lr_op = '1' or sc_op = '1' or amo_op = '1' or cboz_op = '1'
                             or fence_op = '1' or wfi_op = '1' or wrs_op = '1'
                             or is_fp_singlecycle = '1' or is_fp_multicycle = '1'
                             or is_fp_fma = '1'))
                report "F4 ASSERT: c_dec emitted a sequencer/FP encoding -- shapes B/C have no arm for it"
                severity error;

        end if;
    end process;

end architecture;


