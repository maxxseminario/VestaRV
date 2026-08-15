library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.constants.all;

entity csr_unit is
    generic (
        -- Core ISA feature switches, advertised through the read-only misa CSR (0x301) so software can probe what this chip was built with.
        ENABLE_MUL        : boolean := true;
        ENABLE_DIV        : boolean := true;
        ENABLE_ATOMICS    : boolean := true;
        ENABLE_COMPRESSED : boolean := true;
        ENABLE_BITMANIP   : boolean := true;
        -- X1 Zihpm: real 64-bit hardware performance counters 3/4 behind this generic.
        -- Default false leaves counters 3-31 hardwired zero (read-zero, write-ignore, no trap), fully back-compatible with the X0 scaffold.
        ENABLE_ZIHPM      : boolean := false;  -- X1 (Zihpm): real hpm counters
        -- X3 Zcmt: the jvt (jump-vector-table base) CSR (0x017, URW) lives here.
        -- Default false leaves jvt hardwired zero, and maindec's csr_valid map makes 0x017 an illegal CSR, so reads and writes trap (both-polarity gate).
        ENABLE_ZCMT       : boolean := false;  -- X3 (Zcmt): jvt CSR
        ENABLE_ZFINX      : boolean := false;  -- X4 (Zfinx): consumed from phase X4 on; scaffolded X0
        -- P0 privileged-architecture scaffolding (default false, 16 entries).
        -- The CSR FILE for all three phases lives here: P1's mstatus/mstatush/mtvec/mie/mip/mscratch/mepc/mcause/mtval plus mtrapctl (0x7C0), P2's privilege register plus real mcounteren, and P3's pmpcfg0-3/pmpaddr0-15 bank.
        -- PMP_ENTRIES sizes the bank; the CSR ADDRESS map stays the 16-entry superset, with entries above the count reading WARL zero.
        -- Nothing consumes them yet: the CSRs are added by the phase that consumes them.
        ENABLE_TRAPCSR    : boolean := false;  -- P1 (trap CSRs): consumed from phase P1 on; scaffolded P0
        ENABLE_UMODE      : boolean := false;  -- P2 (U-mode): consumed from phase P2 on; scaffolded P0
        ENABLE_PMP        : boolean := false;  -- P3 (PMP/Smpmp): consumed from phase P3 on; scaffolded P0
        PMP_ENTRIES       : integer := 16;     -- P3 (PMP entry count {8,16}): consumed from phase P3 on; scaffolded P0
        -- D1 debug mode (2026-08-05), default false.
        -- THE DEBUG-MODE CSR FILE LIVES HERE, beside priv_m, for the same four reasons (D0/P1 1f).
        -- Entry must set debug_mode, save priv into dcsr.prv and force M in ONE action, and `dret` must undo all three.
        -- This file runs on the FREE-RUNNING clk, which is what makes the mtrap_*_lvl one-shot idiom work at all.
        -- The priv_mode export route into maindec already exists for debug_mode to follow.
        -- And the OFF-build fold is the house pattern.
        ENABLE_DEBUG      : boolean := false;  -- D1 (dcsr/dpc/dscratch0/1 + debug_mode)
        -- V1 lockstep tracer: gates the read-only export block at the end of this architecture.
        -- Default FALSE so the OFF netlist is identical BY CONSTRUCTION rather than by unloaded-logic removal.
        TRACE_ENABLE      : boolean := false
    );
    port (
        clk              : in  std_logic;
        resetn           : in  std_logic;

        -- X3 Zcmt: jvt base exported to vesta's table-jump FSM; the table base is {jvt[31:6],6'b0}.
        -- Held zero when ENABLE_ZCMT is off.
        jvt_value        : out std_logic_vector(31 downto 0);

        -- X4 Zfinx fcsr/fflags/frm, all inert when ENABLE_ZFINX is off (fp_csr held zero, never written).
        -- fp_flags_we/fp_flags_val sticky-OR the completing FP op's flags into fflags, driven by vesta INDEPENDENT of rd, so rd=x0 still sets flags.
        -- frm_value/frm_valid export the rounding mode to decode and the FPU (dynamic-rm legality plus effective-rm resolution).
        fp_flags_we      : in  std_logic := '0';                    -- strobe: OR fp_flags_val into fflags
        fp_flags_val     : in  std_logic_vector(4 downto 0) := (others => '0');
        frm_value        : out std_logic_vector(2 downto 0);        -- fp_csr[7:5]
        frm_valid        : out std_logic;                          -- '1' iff frm in {000..100}

        -- M13: hart id is a PORT (it was the HARTID generic) so all hart tiles share ONE netlist (tile hardening, M14), wired per instance.
        hart_id          : in  std_logic_vector(XLEN-1 downto 0) := (others => '0'); -- Value returned by mhartid (0xF14)

        -- CSR instruction interface
        csr_addr         : in  std_logic_vector(11 downto 0);  -- CSR address
        csr_write_data   : in  std_logic_vector(XLEN-1 downto 0);  -- Data to write (from rs1 or immediate)
        csr_op           : in  std_logic_vector(2 downto 0);   -- CSR operation (funct3)
        csr_valid        : in  std_logic;                      -- Valid CSR operation
        csr_read_data    : out std_logic_vector(XLEN-1 downto 0);  -- Data read from CSR

        -- Performance counter input
        inst_retired     : in  std_logic;                      -- Instruction retired signal

        -- X1 Zihpm event inputs, taken from vesta internal signals, NOT from tile or MCU boundary ports.
        -- All default inactive so non-Zihpm instantiations and the OFF build are unaffected.
        -- csr_unit derives the grant and trap edges internally from these levels; it runs on the free-running clk, so the levels are sampled every real cycle even while clk_cpu is gated.
        ev_bus_stall     : in  std_logic := '0';  -- '1' = arbiter request asserted, grant not held (mem_ready low)
        ev_sleep         : in  std_logic := '0';  -- '1' = hart in WFI/sleep state
        ev_trap_entry    : in  std_logic := '0';  -- '1' while in a trap-entry state (IRQ_SV / TRAP_STATE)

        -- ------------------------------------------------------------------
        -- P1 trap-CSR interface (inert when ENABLE_TRAPCSR = false).
        -- FROZEN by ~/vesta_docs/priv_arch/p0_specs.md 2.4: names, widths and inert defaults are the binding contract between this file and the vesta trap FSM.
        -- Every port has a default so any existing instantiation and the OFF polarity are untouched.
        -- ------------------------------------------------------------------
        irq_msip         : in  std_logic := '0';  -- CLINT msip level, read back as mip.MSIP(3)
        irq_mtip         : in  std_logic := '0';  -- CLINT mtip level, read back as mip.MTIP(7)
        irq_meip         : in  std_logic := '0';  -- router meip level, read back as mip.MEIP(11)
        -- MTRAP_SV strobe: mepc takes trap_pc, mcause takes trap_cause, mtval takes trap_value, MPIE takes MIE and MIE clears (P2 also loads MPP from priv).
        trap_entry_we    : in  std_logic := '0';
        trap_pc          : in  std_logic_vector(XLEN-1 downto 0) := (others => '0'); -- per the 2.2 mepc column
        trap_cause       : in  std_logic_vector(XLEN-1 downto 0) := (others => '0'); -- bit 31 + code(3:0) stored, rest discarded
        trap_value       : in  std_logic_vector(XLEN-1 downto 0) := (others => '0');
        -- MRET strobe: MIE takes MPIE and MPIE sets to '1' (P2 also loads priv from MPP and forces MPP to "00").
        mret_we          : in  std_logic := '0';
        mtvec_value      : out std_logic_vector(XLEN-1 downto 0); -- {BASE(31:2),"00"}
        mepc_value       : out std_logic_vector(XLEN-1 downto 0); -- MRET jump target (bit0 always '0')
        mstatus_mie      : out std_logic;
        mie_bits         : out std_logic_vector(2 downto 0);      -- {MEIE, MTIE, MSIE}
        -- mtrapctl.LEGACY: MUST read '1' when ENABLE_TRAPCSR is false so vesta's delivery muxes constant-fold to the legacy irq_handler/IVT path.
        legacy_mode      : out std_logic;

        -- ------------------------------------------------------------------
        -- P2 U-mode interface (inert when ENABLE_UMODE = false), FROZEN by ~/vesta_docs/priv_arch/p0_specs.md 3.1.
        -- The PRIVILEGE REGISTER lives in THIS file (the P1 comment contract): vesta drives nothing new into csr_unit for P2, the priv push/pop rides the EXISTING trap_entry_we and mret_we strobes below.
        -- ------------------------------------------------------------------
        priv_mode        : out std_logic;                     -- '1'=M, '0'=U; reset '1'.
                                                              --   MUST read '1' when ENABLE_UMODE is false.
        status_tw        : out std_logic;                     -- mstatus.TW (21); '0' when UMODE off
        mcounteren_bits  : out std_logic_vector(4 downto 0);  -- {HPM4,HPM3,IR,TM,CY}; "00000" when off

        -- ------------------------------------------------------------------
        -- P3-entry interface (p3_kickoff.md 3, 2026-07-29): two additions landed AHEAD of the PMP phase.
        --  * csr_rs1_zero: '1' when the CSR instruction's rs1/uimm FIELD (instr(19:15)) is zero.
        --    Spec rule: CSRRS/CSRRC with rs1=x0 and CSRRSI/CSRRCI with uimm=0 must NOT write, while CSRRW/CSRRWI always write.
        --    Feeds the csr_write_en form qualifier below.
        --    Default '0' means "field nonzero", i.e. always write, so an instantiation that does not drive it keeps the historic behavior.
        --  * data_priv_m: the EFFECTIVE DATA-ACCESS privilege ('1' = M).
        --    mstatus.MPRV redirection (priv spec): when MPRV=1 loads and stores are checked at privilege MPP, while instruction fetches always check at priv_mode.
        --    Its consumer is the P3 PMP data-side check, unconsumed until the vesta side wires it.
        --    Constant '1' when ENABLE_UMODE is off (MPRV is read-only 0 without U-mode).
        -- ------------------------------------------------------------------
        csr_rs1_zero     : in  std_logic := '0';
        data_priv_m      : out std_logic;
        -- P3 red-team F1 fix (2026-07-29): the privilege an MRET would RETURN to, i.e. mstatus.MPP mapped as '1'=M, '0'=U.
        -- vesta checks the MRET-target FETCH at THIS privilege during MTRAP_RET, not at the still-current M.
        -- Otherwise the return instruction is X-checked one cycle too early at the higher privilege, and the first instruction after an MRET into U escapes its X-permission (the F1 escape).
        -- Constant '1' when ENABLE_UMODE is off (MPP pinned M).
        mret_priv_m      : out std_logic;

        -- ------------------------------------------------------------------
        -- D1 DEBUG-MODE interface (inert when ENABLE_DEBUG = false).
        -- Structurally the trap_entry_we and mret_we pair one level up: vesta owns the FSM and the decision, this file owns the state.
        --   dbg_entry_we : DBG_SV strobe, ONE action from one strobe. dpc takes dbg_pc (same IALIGN-WARL mask a software write gets), dcsr.cause takes dbg_cause, dcsr.prv takes the interrupted privilege, debug_mode sets, and with U-mode priv is forced to M.
        --   dbg_ret_we   : DBG_RET strobe. debug_mode clears and priv is restored from dcsr.prv.
        -- Every export below is a reset constant on an OFF build: debug_mode '0' (so maindec keeps the 0x7Bx block denied and DRET illegal), ebreakm/ebreaku/step '0' (so vesta's dbg_ebreak_take and the step machinery fold), and dpc_value zero.
        -- ------------------------------------------------------------------
        dbg_entry_we     : in  std_logic := '0';
        dbg_pc           : in  std_logic_vector(XLEN-1 downto 0) := (others => '0');
        dbg_cause        : in  std_logic_vector(2 downto 0) := (others => '0');
        dbg_ret_we       : in  std_logic := '0';
        debug_mode       : out std_logic;                     -- '1' = executing in debug mode
        dcsr_ebreakm     : out std_logic;                     -- dcsr(15)
        dcsr_ebreaku     : out std_logic;                     -- dcsr(12); RO-0 without U-mode
        dcsr_step        : out std_logic;                     -- dcsr(2)
        dpc_value        : out std_logic_vector(XLEN-1 downto 0); -- DRET jump target (bit0 always '0')

        -- ------------------------------------------------------------------
        -- P3 PMP interface (inert when ENABLE_PMP = false), FROZEN by ~/vesta_docs/priv_arch/p0_specs.md 4.1.
        -- csr_unit owns the pmpcfg0-3 and pmpaddr0-15 STORAGE, WARL and LOCK semantics; the match/priority/permission decode is pmp_unit.vhd and the check-point integration is vesta's.
        -- These two flat exports are the ONLY coupling.
        --   entry i cfg byte  = pmp_cfg_flat(8*i+7  downto 8*i)
        --   entry i pmpaddr   = pmp_addr_flat(30*i+29 downto 30*i)  (= phys 31:2)
        -- Both are ALL-ZERO when ENABLE_PMP is false (the flops are written only under `if ENABLE_PMP`, so they hold their all-zero reset forever), and the upper half is all-zero whenever PMP_ENTRIES < 16.
        -- ------------------------------------------------------------------
        pmp_cfg_flat     : out std_logic_vector(127 downto 0);
        pmp_addr_flat    : out std_logic_vector(479 downto 0);

        -- ------------------------------------------------------------------
        -- V1 LOCKSTEP TRACER EXPORTS (read-only; section 7-A of ~/vesta_docs/lockstep/v1_retire_enumeration.md rev 2).
        -- Consumed ONLY by vesta_tracer under TRACE_ENABLE.
        -- They are pure taps on existing nets plus one address decode, so an OFF build prunes them (nothing reads the vesta-level signals they drive).
        --
        -- csr_commit_we MUST be generated HERE, not reproduced at vesta level: `csr_write_en` is only the STROBE, and maindec's csr_addr_valid admits 20+ addresses that have NO storing arm in the write case (mhartid, misa, cycle/instret[h], hpmcounter3-31, mhpmcounter5-31, mhpmevent5-31) plus CSR_MIP and CSR_MSTATUSH (both `null`).
        -- A vesta-level reproduction would log CSR writes that never committed (red-team R4, finding F10).
        -- ------------------------------------------------------------------
        csr_commit_we    : out std_logic;
        csr_commit_val   : out std_logic_vector(XLEN-1 downto 0);
        mstatus_value    : out std_logic_vector(XLEN-1 downto 0);
        fflags_value     : out std_logic_vector(XLEN-1 downto 0)
    );
end csr_unit;

architecture behave of csr_unit is

    -- Map a generic boolean onto a std_logic bit for the misa aggregate below.
    function b2sl(b : boolean) return std_logic is
    begin
        if b then
            return '1';
        else
            return '0';
        end if;
    end function;

    -- misa: MXL=01 (RV32) in bits 31:30, extension letters A(0), B(1), C(2), I(8), M(12).
    -- M is advertised only when BOTH mul and div are present, since the M extension is all-or-nothing per the spec.
    -- B (ratified 2024) is Zba+Zbb+Zbs, all of which this core implements when ENABLE_BITMANIP (Zbc rides the same switch but has no misa letter).
    -- Read-only: writes are ignored like the other fixed CSRs, and Zihpm adds NO misa bit.
    -- NOTE: misa is XLEN-wide but the MXL field POSITION is XLEN-relative (bits XLEN-1:XLEN-2) and its VALUE differs per width (01=RV32, 10=RV64), so bit 30 here is the RV32 encoding; revisit it with any real RV64 work.
    -- P2: bit 20 (U) is THE one misa change of the whole P-series program (p0_specs.md 3/6), set iff ENABLE_UMODE, so an OFF build's misa is bit-identical.
    -- M-mode is not a misa letter, and S (bit 18) stays clear (D2: S-mode is out of scope).
    constant MISA_VALUE : std_logic_vector(XLEN-1 downto 0) := (
        30 => '1',                                -- MXL = 01 (RV32)
        20 => b2sl(ENABLE_UMODE),                 -- U (P2)
        12 => b2sl(ENABLE_MUL and ENABLE_DIV),    -- M
        8  => '1',                                -- I (always)
        2  => b2sl(ENABLE_COMPRESSED),            -- C
        1  => b2sl(ENABLE_BITMANIP),              -- B = Zba/Zbb/Zbs
        0  => b2sl(ENABLE_ATOMICS),               -- A
        others => '0');

    -- Performance counters (64-bit)
    signal mcycle     : std_logic_vector(63 downto 0);
    signal minstret   : std_logic_vector(63 downto 0);

    -- X1 Zihpm: real counters 3 and 4, their event selectors and mcountinhibit.
    -- When ENABLE_ZIHPM is false these signals are held at reset (zero) and never written, so every read arm below returns zero for BOTH polarities.
    signal hpm3       : std_logic_vector(63 downto 0);
    signal hpm4       : std_logic_vector(63 downto 0);
    signal mhpmevent3 : std_logic_vector(XLEN-1 downto 0);
    signal mhpmevent4 : std_logic_vector(XLEN-1 downto 0);
    signal mcountinhibit : std_logic_vector(XLEN-1 downto 0);

    -- X3 Zcmt jvt CSR (0x017), WARL: mode bits(5:0) pinned 0 (Jump Table Mode only), base bits(31:6) writable (64-byte aligned).
    -- Held zero and never written when ENABLE_ZCMT is false, so both the read arm and the export return zero.
    signal jvt        : std_logic_vector(XLEN-1 downto 0);

    -- X4 Zfinx fcsr: frm = fp_csr(7:5), fflags = fp_csr(4:0) = {NV,DZ,OF,UF,NX}.
    -- Held zero and never written when ENABLE_ZFINX is off (read arms and exports then return zero, and fflags/frm/fcsr are illegal CSRs via csr_valid).
    signal fp_csr     : std_logic_vector(7 downto 0);
    -- Edge trackers in the clk domain for the grant event (stall falling edge) and the trap-entry event (rising edge).
    signal prev_stall : std_logic;
    signal prev_trap  : std_logic;

    -- ----------------------------------------------------------------------
    -- P1 standard M-mode trap CSR file (p0_specs.md 2.1).
    -- Every one of these is written ONLY under `if ENABLE_TRAPCSR` (the ENABLE_ZFINX/jvt idiom), so with the generic off they stay at their RESET values forever, and the ten addresses are illegal CSRs anyway (maindec csr_addr_valid).
    -- Two reset values are deliberately NOT zero:
    --   * mst_mpp resets "11": MPP is WARL {11} in P1 (M-mode only), so 11 is the only legal value the field can ever hold.
    --     P2 widens it to {00,11} and drives it from the privilege register.
    --   * mtrapctl_legacy resets '1': LEGACY is the reset default (D1), and the freeze REQUIRES legacy_mode = '1' on an ENABLE_TRAPCSR=false build so vesta's delivery muxes constant-fold to the legacy path.
    -- Both are unobservable on an OFF build (illegal CSR addresses).
    -- ----------------------------------------------------------------------
    constant MPP_M : std_logic_vector(1 downto 0) := "11";  -- mstatus.MPP = M-mode

    signal mst_mie         : std_logic;                      -- mstatus.MIE   (3)
    signal mst_mpie        : std_logic;                      -- mstatus.MPIE  (7)
    signal mst_mpp         : std_logic_vector(1 downto 0);   -- mstatus.MPP   (12:11), WARL {11}
    signal mtvec_base      : std_logic_vector(31 downto 2);  -- mtvec.BASE    (MODE pinned "00")
    signal mie_msie        : std_logic;                      -- mie.MSIE      (3)
    signal mie_mtie        : std_logic;                      -- mie.MTIE      (7)
    signal mie_meie        : std_logic;                      -- mie.MEIE      (11)
    signal mscratch        : std_logic_vector(XLEN-1 downto 0);
    signal mepc_r          : std_logic_vector(31 downto 1);  -- mepc, bit0 hardwired '0'
    signal mcause_int      : std_logic;                      -- mcause.Interrupt (31)
    signal mcause_code     : std_logic_vector(3 downto 0);   -- mcause.ExceptionCode (3:0)
    signal mtval_r         : std_logic_vector(XLEN-1 downto 0);
    signal mtrapctl_legacy : std_logic;                      -- mtrapctl.LEGACY (0), reset '1'

    -- ----------------------------------------------------------------------
    -- D1 DEBUG-MODE STATE (d1_spec.md 1).
    -- Written only under `if ENABLE_DEBUG` (software writes) or by the two debug strobes (also generic-gated), so with the generic off every one holds its reset value forever and the exports are compile-time constants.
    --   * debug_mode_r resets '0', and maindec reads it as the affirmative "in debug mode".
    --     '0' therefore means DENIED, which is the direction an unconnected or OFF build must have.
    --   * dcsr.cause is READ-ONLY to software: hardware writes it on entry.
    --   * dcsr.prv resets to "11" (M) and STAYS there on a non-U build, which is what makes a read of dcsr report prv = M without a U-mode privilege register to consult.
    --   * xdebugver is a CONSTANT 4 in the read assembly, not a flop.
    --   * dpc_r is 31 bits: bit 0 is hardwired '0', exactly as mepc_r is.
    -- ----------------------------------------------------------------------
    signal dcsr_ebreakm_r  : std_logic;                      -- dcsr(15)
    signal dcsr_ebreaku_r  : std_logic;                      -- dcsr(12), WARL {0} without U-mode
    signal dcsr_step_r     : std_logic;                      -- dcsr(2)
    signal dcsr_cause_r    : std_logic_vector(2 downto 0);   -- dcsr(8:6), READ-ONLY to software
    signal dcsr_prv_r      : std_logic_vector(1 downto 0);   -- dcsr(1:0), WARL to implemented modes
    signal dpc_r           : std_logic_vector(31 downto 1);  -- dpc, bit0 hardwired '0'
    signal dscratch0_r     : std_logic_vector(XLEN-1 downto 0);
    signal dscratch1_r     : std_logic_vector(XLEN-1 downto 0);
    signal debug_mode_r    : std_logic;                      -- '1' = executing in debug mode (reset '0')

    -- ----------------------------------------------------------------------
    -- P2 U-mode state (p0_specs.md 3/3.1).
    -- Every one of these is written ONLY under `if ENABLE_UMODE`, so with the generic off they hold their RESET values forever:
    --   * priv_m resets '1' (M).
    --     The freeze REQUIRES priv_mode to read '1' on an ENABLE_UMODE=false build, which is what makes maindec's U-mode decode gate statically false there.
    --   * mst_tw resets '0' (mstatus.TW: no WFI timeout wait).
    --   * mcounteren_r resets "00000" and STAYS there when UMODE is off, so mcounteren keeps reading zero and ignoring writes exactly as before (the address has always been legal, constants.vhd 353).
    -- MPP WARL widens here from P1's {11} to {00,11}.
    -- FROZEN RULE (P2 prompt): the two UNSUPPORTED encodings 01/10 map to "11" (M), the CONSERVATIVE direction, so an MRET after such a write returns to M and never to a mode the writer did not ask for.
    -- WARL permits any supported value; mapping down to 00 would silently DROP privilege and is the surprising choice.
    -- ----------------------------------------------------------------------
    constant MPP_U : std_logic_vector(1 downto 0) := "00";  -- mstatus.MPP = U-mode

    signal priv_m          : std_logic;                      -- privilege: '1'=M, '0'=U (reset M)
    signal mst_tw          : std_logic;                      -- mstatus.TW (21), WARL {0,1} iff UMODE
    signal mcounteren_r    : std_logic_vector(4 downto 0);   -- mcounteren {HPM4,HPM3,IR,TM,CY}
    -- P3-entry: mstatus.MPRV (17), WARL {0,1} iff UMODE (priv spec: MPRV is read-only 0 when U-mode is not supported).
    -- Written ONLY under `if ENABLE_UMODE`, so it holds reset ('0') forever otherwise.
    -- An MRET to a privilege below M CLEARS it (spec requirement, see the mret_we arm).
    signal mst_mprv        : std_logic;                      -- mstatus.MPRV (17)

    -- ----------------------------------------------------------------------
    -- P3 PMP CSR bank (p0_specs.md 4/4.1): sixteen cfg bytes and sixteen 30-bit addresses, ALL reset to zero (spec-required A=OFF, L=0).
    -- Every flop is written ONLY under `if ENABLE_PMP` (the ENABLE_TRAPCSR/ENABLE_ZFINX idiom), so with the generic off the whole bank stays at reset forever, both exports read all-zero, and the twenty addresses are illegal CSRs anyway (maindec csr_addr_valid).
    --
    -- With PMP_ENTRIES < 16, entries at or above the count are never written either: the `i < PMP_ENTRIES` guard below is GENERIC-STATIC, so synthesis prunes their flops entirely.
    -- Their CSR ADDRESSES stay legal and read WARL zero, exactly as the freeze requires.
    --
    -- The ARRAY is a plain 0-to-15 array, NOT sized by PMP_ENTRIES: the CSR address map and both flat exports are the 16-entry superset regardless, so indexing stays uniform and no bound can go negative at PMP_ENTRIES=0.
    -- ----------------------------------------------------------------------
    constant PMP_MAX_ENTRIES : integer := 16;
    type pmp_cfg_array_t  is array (0 to PMP_MAX_ENTRIES-1) of std_logic_vector(7 downto 0);
    type pmp_addr_array_t is array (0 to PMP_MAX_ENTRIES-1) of std_logic_vector(29 downto 0);

    signal pmp_cfg  : pmp_cfg_array_t;    -- entry cfg byte: R(0) W(1) X(2) A(4:3) L(7)
    signal pmp_addr : pmp_addr_array_t;   -- entry address bits 29:0 (= phys addr 31:2)

    -- WARL mask for a cfg byte write (p0_specs.md 4/4.1):
    --   bit 7 L   stored as written (writing L=1 to an UNLOCKED entry takes effect, including L=1 with A=OFF, a spec-legal locked hole)
    --   bits 6:5  reserved, pinned 0 (no storage)
    --   bits 4:3  A, all four encodings legal (G = 0)
    --   bit 2 X   stored as written
    --   bit 1 W   PINNED 0 WHEN R = 0 (the reserved R=0/W=1 combo WARL rule)
    --   bit 0 R   stored as written
    function pmp_cfg_warl(v : std_logic_vector(7 downto 0)) return std_logic_vector is
        variable r : std_logic_vector(7 downto 0);
    begin
        r(7)          := v(7);
        r(6 downto 5) := "00";
        r(4 downto 3) := v(4 downto 3);
        r(2)          := v(2);
        r(1)          := v(1) and v(0);   -- W pinned 0 when R = 0
        r(0)          := v(0);
        return r;
    end function;

    -- Is entry i's own lock bit set?
    -- Entries at or above PMP_ENTRIES have no storage and read zero, so they can never lock anything.
    function pmp_locked(cfgv : std_logic_vector(7 downto 0)) return boolean is
    begin
        return cfgv(7) = '1';
    end function;

    -- May pmpaddr(i) be written? TWO lock sources (p0_specs.md 4/4.1):
    --   (a) entry i's OWN L bit: a locked entry's cfg byte AND address are immutable until reset.
    --   (b) entry i+1 locked with A=TOR: that entry's region runs from pmpaddr[i] up to but not including pmpaddr[i+1], so pmpaddr[i] is its BASE and must be locked down with it.
    -- `own_cfg` and `next_cfg` are the CURRENT (pre-write) register values, because the lock decision must never consult the value being written: a write that clears L on a locked entry would otherwise unlock itself in the same cycle.
    -- Entry 15 has no successor, so callers pass all-zeros, which reads as "unlocked, A=OFF" and contributes nothing.
    -- Entries at or above PMP_ENTRIES read all-zero for the same reason.
    function pmp_addr_writable(own_cfg  : std_logic_vector(7 downto 0);
                               next_cfg : std_logic_vector(7 downto 0)) return boolean is
    begin
        return (own_cfg(7) = '0') and
               not (next_cfg(7) = '1' and next_cfg(4 downto 3) = PMP_A_TOR);
    end function;

    constant PMP_NO_NEXT : std_logic_vector(7 downto 0) := (others => '0');

    -- mcause bits 30:4 read 0 (WLRL: only bit31 + code(3:0) are stored).
    constant MCAUSE_RSVD27 : std_logic_vector(26 downto 0) := (others => '0');

    -- V1 tracer export helper: does this CSR address have a write-case arm that actually STORES?
    -- See the concurrent assignments at the end of this architecture for why this cannot live at vesta level.
    -- It mirrors the arm gating exactly; CSR_MIP and CSR_MSTATUSH are `null` arms and return false.
    function csr_addr_stores(a : std_logic_vector(11 downto 0)) return boolean is
    begin
        case a is
            when CSR_MCYCLE | CSR_MCYCLEH | CSR_MINSTRET | CSR_MINSTRETH =>
                return true;
            when CSR_MHPMEVENT3    | CSR_MHPMEVENT4    | CSR_MHPMCOUNTER3 |
                 CSR_MHPMCOUNTER3H | CSR_MHPMCOUNTER4  | CSR_MHPMCOUNTER4H |
                 CSR_MCOUNTINHIBIT =>
                return ENABLE_ZIHPM;
            when CSR_JVT =>
                return ENABLE_ZCMT;
            when CSR_FFLAGS | CSR_FRM | CSR_FCSR =>
                return ENABLE_ZFINX;
            when CSR_MSTATUS | CSR_MTVEC  | CSR_MIE   | CSR_MSCRATCH |
                 CSR_MEPC    | CSR_MCAUSE | CSR_MTVAL | CSR_MTRAPCTL =>
                return ENABLE_TRAPCSR;
            when CSR_MCOUNTEREN =>
                return ENABLE_UMODE;
            -- D1: all four Debug-Mode CSRs have STORING write arms under ENABLE_DEBUG (dcsr stores four writable fields, dpc/dscratch0/1 store outright), so the tracer must export their commits.
            -- dcsr.cause is read-only to software, but the arm still stores the other fields, so the address counts as storing.
            when CSR_DCSR | CSR_DPC | CSR_DSCRATCH0 | CSR_DSCRATCH1 =>
                return ENABLE_DEBUG;
            when CSR_PMPCFG0  | CSR_PMPCFG1  | CSR_PMPCFG2  | CSR_PMPCFG3  |
                 CSR_PMPADDR0 | CSR_PMPADDR1 | CSR_PMPADDR2 | CSR_PMPADDR3 |
                 CSR_PMPADDR4 | CSR_PMPADDR5 | CSR_PMPADDR6 | CSR_PMPADDR7 |
                 CSR_PMPADDR8 | CSR_PMPADDR9 | CSR_PMPADDR10 | CSR_PMPADDR11 |
                 CSR_PMPADDR12 | CSR_PMPADDR13 | CSR_PMPADDR14 | CSR_PMPADDR15 =>
                return ENABLE_PMP;   -- approximation: run-time lock not modelled
            when others =>
                return false;        -- incl. CSR_MIP / CSR_MSTATUSH (null arms)
        end case;
    end function csr_addr_stores;

    -- Internal signals
    signal csr_write_en  : std_logic;
    signal csr_read_val  : std_logic_vector(XLEN-1 downto 0);
    signal csr_new_val   : std_logic_vector(XLEN-1 downto 0);

    -- XLEN-wide comparison and mask constants: an slv "=" on unequal lengths is silently false, so never compare against a literal of another width.
    constant CSR_ZERO_X : std_logic_vector(XLEN-1 downto 0) := (others => '0');
    -- mcountinhibit implemented bits: 0 (cycle), 2 (instret), 3/4 (hpm3/4)
    constant MCOUNTINHIBIT_MASK : std_logic_vector(XLEN-1 downto 0) :=
        (0 => '1', 2 => '1', 3 => '1', 4 => '1', others => '0');

    -- Event decode: returns true when the counter whose selector is `sel` should increment this cycle.
    -- The event set is FIXED (X1.5 spec, D2): 0 off, 1 arbiter-stall cycles, 2 shared-bus grants, 3 sleep cycles, 4 trap entries.
    -- Unsupported selector values count nothing.
    function hpm_fires(sel        : std_logic_vector(XLEN-1 downto 0);
                       stall_lvl  : std_logic;
                       stall_fell : std_logic;
                       sleep_lvl  : std_logic;
                       trap_rose  : std_logic) return boolean is
    begin
        case sel is
            when x"00000001" => return stall_lvl  = '1';  -- arbiter-stall cycles
            when x"00000002" => return stall_fell = '1';  -- shared-bus grants (one per completed txn)
            when x"00000003" => return sleep_lvl  = '1';  -- sleep cycles
            when x"00000004" => return trap_rose  = '1';  -- trap entries taken
            when others      => return false;             -- 0 = off; unsupported = count nothing
        end case;
    end function;

begin

    -- CSR write enable, the spec's INSTRUCTION-FORM rule (P3-entry fix, p3_kickoff.md 3 item 3).
    -- CSRRW/CSRRWI (funct3(1:0) = "01") ALWAYS write; the set/clear forms write only when the rs1/uimm FIELD is nonzero, i.e. the register NUMBER and not its value (csr_rs1_zero is decoded from instr(19:15) in vesta, which for the immediate forms IS uimm).
    -- The old guard (`csr_op(1)='1' or csr_op(0)='1' or write_data /= 0`) was satisfied by ALL SIX CSR funct3 values, so a plain `csrr` also asserted the write enable.
    -- That was spec-wrong and benign only because every write arm was idempotent under read-modify-write; its one observable was freezing mcycle/minstret for the instruction's duration via the write-precedence rule, and privcsr CHECK 34 pins the fixed behavior.
    -- The P3 pmpcfg/pmpaddr bank is why this lands now: locked entries must never see probing writes from read-only instruction forms.
    csr_write_en <= csr_valid when (csr_op(1 downto 0) = "01" or csr_rs1_zero = '0')
                                else '0';

    -- CSR read decode: one arm per implemented address, every other address reads zero.
    process(csr_addr, mcycle, minstret, hart_id,
            hpm3, hpm4, mhpmevent3, mhpmevent4, mcountinhibit, jvt, fp_csr,
            mst_mie, mst_mpie, mst_mpp, mtvec_base, mie_msie, mie_mtie, mie_meie,
            mscratch, mepc_r, mcause_int, mcause_code, mtval_r, mtrapctl_legacy,
            irq_msip, irq_mtip, irq_meip,
            mst_tw, mcounteren_r, mst_mprv,
            dcsr_ebreakm_r, dcsr_ebreaku_r, dcsr_step_r, dcsr_cause_r,
            dcsr_prv_r, dpc_r, dscratch0_r, dscratch1_r,
            pmp_cfg, pmp_addr)
    begin
        case csr_addr is
            -- Machine Information Registers (Read-only)
            when CSR_MHARTID   => csr_read_val <= hart_id;
            when CSR_MISA      => csr_read_val <= MISA_VALUE;

            -- X3 Zcmt jvt: the read arm is unconditional, since jvt is held zero when ENABLE_ZCMT is off and 0x017 is an illegal CSR there anyway.
            when CSR_JVT       => csr_read_val <= jvt;

            -- X4 Zfinx fflags/frm/fcsr: read arms unconditional like jvt, since fp_csr is zero when ENABLE_ZFINX is off and the addresses are illegal there via csr_valid.
            -- Reserved high bits read 0 (WPRI).
            when CSR_FFLAGS    => csr_read_val <= x"000000" & "000" & fp_csr(4 downto 0);
            when CSR_FRM       => csr_read_val <= x"000000" & "00000" & fp_csr(7 downto 5);
            when CSR_FCSR      => csr_read_val <= x"000000" & fp_csr(7 downto 0);

            -- Machine Counters (Read/Write)
            when CSR_MCYCLE    => csr_read_val <= mcycle(XLEN-1 downto 0);
            when CSR_MINSTRET  => csr_read_val <= minstret(XLEN-1 downto 0);
            when CSR_MCYCLEH   => csr_read_val <= mcycle(63 downto 32);
            when CSR_MINSTRETH => csr_read_val <= minstret(63 downto 32);

            -- User-readable counters: read-only shadows of the machine counters.
            -- This M-mode-only core implements NO mcounteren, so cycle/instret read unconditionally and the hpm user-view arms below do the same; mcounteren reads zero rather than gating or trapping.
            when CSR_CYCLE     => csr_read_val <= mcycle(XLEN-1 downto 0);
            when CSR_INSTRET   => csr_read_val <= minstret(XLEN-1 downto 0);
            when CSR_CYCLEH    => csr_read_val <= mcycle(63 downto 32);
            when CSR_INSTRETH  => csr_read_val <= minstret(63 downto 32);

            -- X1 Zihpm counters 3/4, machine view plus user-view alias.
            -- They read zero when ENABLE_ZIHPM is false (signals held at reset).
            -- Counters 5-31 fall through to the `others` arm and read zero, which is legal and does not trap.
            -- time/timeh USED to ride that same `others`; since DD11-N1 they are not KNOWN CSRs at all (maindec's csr_addr_valid drops them), so 0xC01/0xC81 never reach this decoder and raise illegal-instruction instead.
            -- Adding a read arm for them here would do NOTHING without re-admitting them in maindec first.
            when CSR_MHPMEVENT3    => csr_read_val <= mhpmevent3;
            when CSR_MHPMEVENT4    => csr_read_val <= mhpmevent4;
            when CSR_MHPMCOUNTER3  | CSR_HPMCOUNTER3  => csr_read_val <= hpm3(XLEN-1 downto 0);
            when CSR_MHPMCOUNTER4  | CSR_HPMCOUNTER4  => csr_read_val <= hpm4(XLEN-1 downto 0);
            when CSR_MHPMCOUNTER3H | CSR_HPMCOUNTER3H => csr_read_val <= hpm3(63 downto 32);
            when CSR_MHPMCOUNTER4H | CSR_HPMCOUNTER4H => csr_read_val <= hpm4(63 downto 32);
            when CSR_MCOUNTINHIBIT => csr_read_val <= mcountinhibit;

            -- P2 mcounteren (0x306) becomes REAL: CY(0), TM(1), IR(2), HPM3(3), HPM4(4), with bits 31:5 WARL 0.
            -- The address has ALWAYS been legal (read-zero, write-ignore), and with ENABLE_UMODE off mcounteren_r is stuck at "00000", so this arm returns the identical zero the `others` arm used to, bit-for-bit.
            when CSR_MCOUNTEREN    => csr_read_val <= x"000000" & "000" & mcounteren_r;

            -- ==============================================================
            -- P1 standard M-mode trap CSRs (p0_specs.md 2.1).
            -- Read arms are UNCONDITIONAL (the jvt/fcsr precedent): the state is held at reset when ENABLE_TRAPCSR is off, and all ten addresses are illegal CSRs there, so nothing can observe them.
            -- CLASS-4 (readback completeness) NOTE: every reserved or WPRI bit is driven to its spec value here, not left to the `others` arm.
            -- ==============================================================
            -- mstatus: MIE(3), MPIE(7), MPP(12:11), TW(21) from P2 and MPRV(17) from P3-entry; everything else still reads 0.
            -- mst_tw and mst_mprv are both stuck '0' with ENABLE_UMODE off, so the read value on an OFF or trapCsr-only build is unchanged.
            when CSR_MSTATUS   => csr_read_val <= (21 => mst_tw, 17 => mst_mprv,
                                                  12 => mst_mpp(1), 11 => mst_mpp(0),
                                                   7 => mst_mpie, 3 => mst_mie,
                                                   others => '0');
            -- mstatush: legal but wholly unimplemented (RV32 priv >=1.12).
            when CSR_MSTATUSH  => csr_read_val <= CSR_ZERO_X;
            -- mtvec: BASE(31:2) + MODE(1:0) WARL "00" (direct mode only).
            when CSR_MTVEC     => csr_read_val <= mtvec_base & "00";
            -- mie: MSIE(3)/MTIE(7)/MEIE(11).
            when CSR_MIE       => csr_read_val <= (11 => mie_meie, 7 => mie_mtie,
                                                   3 => mie_msie, others => '0');
            -- mip: READ-ONLY live mirror of the three interrupt level wires, with no storage, because every source clears at the source (CLINT msip write, mtimecmp, irq_router claim/complete).
            -- Forced to zero on an OFF build so the levels cannot leak into an unreachable arm.
            when CSR_MIP       =>
                if ENABLE_TRAPCSR then
                    csr_read_val <= (11 => irq_meip, 7 => irq_mtip,
                                     3 => irq_msip, others => '0');
                else
                    csr_read_val <= CSR_ZERO_X;
                end if;
            when CSR_MSCRATCH  => csr_read_val <= mscratch;
            -- mepc: bit0 hardwired 0, and bit1 too on a no-C build (see the write arm).
            when CSR_MEPC      => csr_read_val <= mepc_r & '0';
            -- mcause: Interrupt(31) + ExceptionCode(3:0); bits 30:4 read 0.
            when CSR_MCAUSE    => csr_read_val <= mcause_int & MCAUSE_RSVD27 & mcause_code;
            when CSR_MTVAL     => csr_read_val <= mtval_r;
            -- mtrapctl (custom 0x7C0): bit0 LEGACY, bits 31:1 WARL 0.
            when CSR_MTRAPCTL  => csr_read_val <= x"0000000" & "000" & mtrapctl_legacy;

            -- ==============================================================
            -- D1 Debug-Mode CSRs (d1_spec.md 1).
            -- Read arms are UNCONDITIONAL (the P1/jvt/fcsr precedent): the state is held at reset when ENABLE_DEBUG is off and all four addresses are illegal CSRs there, so nothing can observe them.
            -- Even with the generic ON, maindec's dbg_csr_denied traps every access from outside debug mode, so these arms are reachable only from debug code.
            -- CLASS-4 (readback completeness): every reserved or unimplemented dcsr bit is driven HERE, not left to the `others` arm.
            --   dcsr = xdebugver(31:28) CONSTANT 4 (a literal, not a flop), ebreakm(15), ebreaku(12), cause(8:6), step(2), prv(1:0).
            --          stepie(11), stopcount(10), stoptime(9), ebreakvs, ebreakvu, ebreaks, nmip, mprven, pelp and v are all read-zero WARL.
            when CSR_DCSR      => csr_read_val <= (30 => '1',
                                                  15 => dcsr_ebreakm_r,
                                                  12 => dcsr_ebreaku_r,
                                                   8 => dcsr_cause_r(2),
                                                   7 => dcsr_cause_r(1),
                                                   6 => dcsr_cause_r(0),
                                                   2 => dcsr_step_r,
                                                   1 => dcsr_prv_r(1),
                                                   0 => dcsr_prv_r(0),
                                                  others => '0');
            -- dpc: bit0 hardwired 0, and bit1 too on a no-C build (see the write arm).
            when CSR_DPC       => csr_read_val <= dpc_r & '0';
            when CSR_DSCRATCH0 => csr_read_val <= dscratch0_r;
            when CSR_DSCRATCH1 => csr_read_val <= dscratch1_r;

            -- ==============================================================
            -- P3 PMP bank (p0_specs.md 4.1).
            -- Read arms are UNCONDITIONAL (the jvt/fcsr/P1 precedent): the bank is held at reset when ENABLE_PMP is off and all twenty addresses are illegal CSRs there, so nothing can observe them.
            -- CLASS-4 (readback completeness): the reserved bits are driven to their spec value HERE, never left to the `others` arm.
            --   pmpcfg(n)  = the four WARL-masked cfg bytes as stored; bits 6:5 of every byte are zero because the WRITE masks them, so the readback is complete by construction.
            --   pmpaddr(i) = "00" & the 30 stored bits, so bits 31:30 read 0.
            -- Entries at or above PMP_ENTRIES have no storage and read zero.
            -- ==============================================================
            when CSR_PMPCFG0   => csr_read_val <= pmp_cfg(3)  & pmp_cfg(2)  & pmp_cfg(1)  & pmp_cfg(0);
            when CSR_PMPCFG1   => csr_read_val <= pmp_cfg(7)  & pmp_cfg(6)  & pmp_cfg(5)  & pmp_cfg(4);
            when CSR_PMPCFG2   => csr_read_val <= pmp_cfg(11) & pmp_cfg(10) & pmp_cfg(9)  & pmp_cfg(8);
            when CSR_PMPCFG3   => csr_read_val <= pmp_cfg(15) & pmp_cfg(14) & pmp_cfg(13) & pmp_cfg(12);

            when CSR_PMPADDR0  => csr_read_val <= "00" & pmp_addr(0);
            when CSR_PMPADDR1  => csr_read_val <= "00" & pmp_addr(1);
            when CSR_PMPADDR2  => csr_read_val <= "00" & pmp_addr(2);
            when CSR_PMPADDR3  => csr_read_val <= "00" & pmp_addr(3);
            when CSR_PMPADDR4  => csr_read_val <= "00" & pmp_addr(4);
            when CSR_PMPADDR5  => csr_read_val <= "00" & pmp_addr(5);
            when CSR_PMPADDR6  => csr_read_val <= "00" & pmp_addr(6);
            when CSR_PMPADDR7  => csr_read_val <= "00" & pmp_addr(7);
            when CSR_PMPADDR8  => csr_read_val <= "00" & pmp_addr(8);
            when CSR_PMPADDR9  => csr_read_val <= "00" & pmp_addr(9);
            when CSR_PMPADDR10 => csr_read_val <= "00" & pmp_addr(10);
            when CSR_PMPADDR11 => csr_read_val <= "00" & pmp_addr(11);
            when CSR_PMPADDR12 => csr_read_val <= "00" & pmp_addr(12);
            when CSR_PMPADDR13 => csr_read_val <= "00" & pmp_addr(13);
            when CSR_PMPADDR14 => csr_read_val <= "00" & pmp_addr(14);
            when CSR_PMPADDR15 => csr_read_val <= "00" & pmp_addr(15);

            when others        => csr_read_val <= CSR_ZERO_X;
        end case;
    end process;

    -- CSR read-modify-write value: the funct3 form picks write, set or clear.
    process(csr_op, csr_read_val, csr_write_data)
    begin
        case csr_op is
            when CSRRW_FN3 | CSRRWI_FN3 =>  -- Write
                csr_new_val <= csr_write_data;
            when CSRRS_FN3 | CSRRSI_FN3 =>  -- Set bits
                csr_new_val <= csr_read_val or csr_write_data;
            when CSRRC_FN3 | CSRRCI_FN3 =>  -- Clear bits
                csr_new_val <= csr_read_val and (not csr_write_data);
            when others =>
                csr_new_val <= csr_read_val;
        end case;
    end process;

    -- CSR state process: counters increment, software writes commit, and the trap and debug strobes write back, all on the free-running clk.
    process(clk, resetn)
        variable v_stall_fell : std_logic;
        variable v_trap_rose  : std_logic;
    begin
        if resetn = '0' then
            -- Reset counters to zero
            mcycle   <= (others => '0');
            minstret <= (others => '0');
            hpm3     <= (others => '0');
            hpm4     <= (others => '0');
            mhpmevent3 <= (others => '0');
            mhpmevent4 <= (others => '0');
            mcountinhibit <= (others => '0');
            jvt        <= (others => '0');
            fp_csr     <= (others => '0');
            prev_stall <= '0';
            prev_trap  <= '0';

            -- P1 trap CSR file: mie resets 0, so standard mode wakes masked and the legacy hardwire-enable path is untouched.
            -- MPP resets to M and mtrapctl.LEGACY resets '1' (see the declaration comment).
            mst_mie         <= '0';
            mst_mpie        <= '0';
            mst_mpp         <= MPP_M;
            mtvec_base      <= (others => '0');
            mie_msie        <= '0';
            mie_mtie        <= '0';
            mie_meie        <= '0';
            mscratch        <= (others => '0');
            mepc_r          <= (others => '0');
            mcause_int      <= '0';
            mcause_code     <= (others => '0');
            mtval_r         <= (others => '0');
            mtrapctl_legacy <= '1';

            -- D1 debug-mode state: debug_mode resets '0', i.e. NOT in debug mode, the restrictive direction that keeps the 0x7Bx block denied and DRET illegal out of reset.
            -- dcsr.prv resets "11" (M) and never moves on a non-U build, so a dcsr read reports M.
            -- dcsr.step/ebreakm/ebreaku reset '0': a chip out of reset takes no ebreak to debug mode and single-steps nothing, so nothing can enter debug mode without an explicit external request.
            dcsr_ebreakm_r  <= '0';
            dcsr_ebreaku_r  <= '0';
            dcsr_step_r     <= '0';
            dcsr_cause_r    <= (others => '0');
            dcsr_prv_r      <= MPP_M;
            dpc_r           <= (others => '0');
            dscratch0_r     <= (others => '0');
            dscratch1_r     <= (others => '0');
            debug_mode_r    <= '0';

            -- P2 U-mode state: priv resets to M ('1'), REQUIRED to read '1' forever on an ENABLE_UMODE=false build (freeze 3.1).
            priv_m          <= '1';
            mst_tw          <= '0';
            mcounteren_r    <= (others => '0');
            mst_mprv        <= '0';

            -- P3 PMP bank: ALL ZERO (spec-required A=OFF and L=0 at reset).
            -- A lock is released ONLY by reset, which is the whole point of the L bit and why the write arms below never clear it.
            pmp_cfg         <= (others => (others => '0'));
            pmp_addr        <= (others => (others => '0'));

        elsif rising_edge(clk) then
            -- X4 Zfinx: sticky-OR the completing FP op's flags into fflags, driven by vesta INDEPENDENT of rd, since rd=x0 must still set flags.
            -- A same-cycle CSR write to fflags/frm/fcsr overrides this below because the later assignment wins, matching the mcycle write-precedence idiom.
            -- A CSR-write instruction is never itself an FP op, so they never collide within one instruction, but the precedence is defined anyway.
            if ENABLE_ZFINX and fp_flags_we = '1' then
                fp_csr(4 downto 0) <= fp_csr(4 downto 0) or fp_flags_val;
            end if;

            -- Cycle counter: free-running, optionally inhibited by mcountinhibit(0), which is only reachable when ENABLE_ZIHPM lets software write it.
            if not (ENABLE_ZIHPM and mcountinhibit(0) = '1') then
                mcycle <= std_logic_vector(unsigned(mcycle) + 1);
            end if;

            -- Instruction counter: on retire, optionally inhibited by bit 2.
            if inst_retired = '1' and not (ENABLE_ZIHPM and mcountinhibit(2) = '1') then
                minstret <= std_logic_vector(unsigned(minstret) + 1);
            end if;

            -- X1 Zihpm real counters 3/4: the whole block prunes when the generic is false (constant-false conditions), leaving hpm3/4 at zero.
            if ENABLE_ZIHPM then
                -- Derive the two edge events from the sampled levels.
                -- prev_* still holds LAST cycle's value at this point, since the updates below only schedule next-cycle values.
                v_stall_fell := prev_stall and (not ev_bus_stall);  -- a stalled txn just completed = one grant
                v_trap_rose  := ev_trap_entry and (not prev_trap);  -- entered a trap-handling state
                prev_stall <= ev_bus_stall;
                prev_trap  <= ev_trap_entry;

                -- Counter 3
                if mcountinhibit(3) = '0' then
                    if hpm_fires(mhpmevent3, ev_bus_stall, v_stall_fell, ev_sleep, v_trap_rose) then
                        hpm3 <= std_logic_vector(unsigned(hpm3) + 1);
                    end if;
                end if;

                -- Counter 4
                if mcountinhibit(4) = '0' then
                    if hpm_fires(mhpmevent4, ev_bus_stall, v_stall_fell, ev_sleep, v_trap_rose) then
                        hpm4 <= std_logic_vector(unsigned(hpm4) + 1);
                    end if;
                end if;
            end if;

            -- Handle CSR writes: a later assignment to a counter half here wins over the increment above (write precedence, same as mcycle today).
            if csr_write_en = '1' then
                case csr_addr is
                    when CSR_MCYCLE =>
                        mcycle(XLEN-1 downto 0) <= csr_new_val;
                    when CSR_MCYCLEH =>
                        mcycle(63 downto 32) <= csr_new_val;
                    when CSR_MINSTRET =>
                        minstret(XLEN-1 downto 0) <= csr_new_val;
                    when CSR_MINSTRETH =>
                        minstret(63 downto 32) <= csr_new_val;

                    -- X1 Zihpm writable CSRs, ignored when ENABLE_ZIHPM is off so they stay hardwired zero for the OFF polarity.
                    when CSR_MHPMEVENT3 =>
                        if ENABLE_ZIHPM then mhpmevent3 <= csr_new_val; end if;
                    when CSR_MHPMEVENT4 =>
                        if ENABLE_ZIHPM then mhpmevent4 <= csr_new_val; end if;
                    when CSR_MHPMCOUNTER3 =>
                        if ENABLE_ZIHPM then hpm3(XLEN-1 downto 0) <= csr_new_val; end if;
                    when CSR_MHPMCOUNTER3H =>
                        if ENABLE_ZIHPM then hpm3(63 downto 32) <= csr_new_val; end if;
                    when CSR_MHPMCOUNTER4 =>
                        if ENABLE_ZIHPM then hpm4(XLEN-1 downto 0) <= csr_new_val; end if;
                    when CSR_MHPMCOUNTER4H =>
                        if ENABLE_ZIHPM then hpm4(63 downto 32) <= csr_new_val; end if;
                    when CSR_MCOUNTINHIBIT =>
                        -- Only bits 0,2,3,4 are implemented; 1 and 5-31 read-only zero.
                        if ENABLE_ZIHPM then
                            mcountinhibit <= csr_new_val and MCOUNTINHIBIT_MASK;
                        end if;

                    -- X3 Zcmt jvt write (WARL): mode(5:0) pinned 0, base(31:6) writable.
                    -- Gated on ENABLE_ZCMT so it stays hardwired zero for the OFF polarity, where 0x017 traps as an illegal CSR via csr_valid.
                    when CSR_JVT =>
                        if ENABLE_ZCMT then
                            jvt <= csr_new_val(31 downto 6) & "000000";
                        end if;

                    -- X4 Zfinx CSR writes REPLACE the addressed sub-field, gated on ENABLE_ZFINX (hardwired zero for the OFF polarity, and an illegal CSR there anyway).
                    -- These win over the sticky-OR above, since the later assignment wins.
                    when CSR_FFLAGS =>
                        if ENABLE_ZFINX then fp_csr(4 downto 0) <= csr_new_val(4 downto 0); end if;
                    when CSR_FRM =>
                        if ENABLE_ZFINX then fp_csr(7 downto 5) <= csr_new_val(2 downto 0); end if;
                    when CSR_FCSR =>
                        if ENABLE_ZFINX then fp_csr <= csr_new_val(7 downto 0); end if;

                    -- ======================================================
                    -- P1 standard M-mode trap CSR writes (p0_specs.md 2.1).
                    -- All gated on ENABLE_TRAPCSR so the file stays at reset for the OFF polarity, where the addresses trap anyway.
                    -- ======================================================
                    when CSR_MSTATUS =>
                        if ENABLE_TRAPCSR then
                            mst_mie  <= csr_new_val(3);
                            mst_mpie <= csr_new_val(7);
                            if ENABLE_UMODE then
                                -- P2: MPP WARL widens to {00, 11}.
                                -- A written 00 stores 00 (U) and 11 stores 11 (M), while the two UNSUPPORTED encodings 01/10 map to 11 (M), the FROZEN conservative direction (see the MPP_U declaration comment).
                                if csr_new_val(12 downto 11) = MPP_U then
                                    mst_mpp <= MPP_U;
                                else
                                    mst_mpp <= MPP_M;
                                end if;
                                -- TW (21) is WARL {0,1} from P2; on an M-only build it is hardwired 0 via the else arm below.
                                mst_tw <= csr_new_val(21);
                                -- P3-entry: MPRV (17), WARL {0,1} iff UMODE, read-only 0 without U-mode per spec.
                                mst_mprv <= csr_new_val(17);
                            else
                                -- MPP is WARL {11} without U-mode: a write of ANY value stores 11, the only supported mode.
                                mst_mpp  <= MPP_M;
                            end if;
                        end if;

                    -- P2 mcounteren (0x306): CY/TM/IR/HPM3/HPM4 writable, bits 31:5 WARL 0 (no storage).
                    -- Gated on ENABLE_UMODE so the register otherwise stays hardwired zero (write-ignore), bit-identical to the pre-P2 behaviour where it fell into the null `others` arm.
                    when CSR_MCOUNTEREN =>
                        if ENABLE_UMODE then
                            mcounteren_r <= csr_new_val(4 downto 0);
                        end if;

                    -- mstatush: legal, write-ignore (no implemented bits).
                    when CSR_MSTATUSH =>
                        null;

                    when CSR_MTVEC =>
                        -- MODE(1:0) is WARL {00} (direct only) and is never stored.
                        if ENABLE_TRAPCSR then
                            mtvec_base <= csr_new_val(31 downto 2);
                        end if;

                    when CSR_MIE =>
                        if ENABLE_TRAPCSR then
                            mie_msie <= csr_new_val(3);
                            mie_mtie <= csr_new_val(7);
                            mie_meie <= csr_new_val(11);
                        end if;

                    -- mip: read-only mirror of the level wires, so writes are ignored.
                    when CSR_MIP =>
                        null;

                    when CSR_MSCRATCH =>
                        if ENABLE_TRAPCSR then
                            mscratch <= csr_new_val;
                        end if;

                    when CSR_MEPC =>
                        -- bit0 is not stored (hardwired '0'), and bit1 is writable only on a C build, since a no-C hart cannot have a 2-byte-aligned PC and bit1 is WARL 0 there.
                        if ENABLE_TRAPCSR then
                            mepc_r(31 downto 2) <= csr_new_val(31 downto 2);
                            if ENABLE_COMPRESSED then
                                mepc_r(1) <= csr_new_val(1);
                            else
                                mepc_r(1) <= '0';
                            end if;
                        end if;

                    when CSR_MCAUSE =>
                        -- WLRL: store Interrupt(31) + code(3:0) only.
                        if ENABLE_TRAPCSR then
                            mcause_int  <= csr_new_val(31);
                            mcause_code <= csr_new_val(3 downto 0);
                        end if;

                    when CSR_MTVAL =>
                        if ENABLE_TRAPCSR then
                            mtval_r <= csr_new_val;
                        end if;

                    when CSR_MTRAPCTL =>
                        -- bit0 LEGACY R/W; bits 31:1 WARL 0 (no storage).
                        if ENABLE_TRAPCSR then
                            mtrapctl_legacy <= csr_new_val(0);
                        end if;

                    -- ======================================================
                    -- D1 Debug-Mode CSR writes (d1_spec.md 1).
                    -- All gated on ENABLE_DEBUG so the file stays at reset for the OFF polarity, where the addresses are illegal anyway.
                    -- A SECOND gate is already in force and is the one that matters at run time: maindec kills csr_valid for any 0x7Bx access from outside debug mode, so these arms are reachable ONLY from debug code even on an ON build.
                    -- ======================================================
                    when CSR_DCSR =>
                        if ENABLE_DEBUG then
                            dcsr_ebreakm_r <= csr_new_val(15);
                            -- ebreaku exists only where U-mode does, and is WARL 0 otherwise since there is no U-mode to break from.
                            if ENABLE_UMODE then
                                dcsr_ebreaku_r <= csr_new_val(12);
                            end if;
                            dcsr_step_r <= csr_new_val(2);
                            -- prv is WARL to the IMPLEMENTED modes, the same conservative direction as mstatus.MPP: only an explicit "00" on a U-mode build selects U, everything else reads back M.
                            -- A dret therefore never returns to a mode the writer did not ask for, and on a non-U build prv is pinned M.
                            if ENABLE_UMODE and csr_new_val(1 downto 0) = MPP_U then
                                dcsr_prv_r <= MPP_U;
                            else
                                dcsr_prv_r <= MPP_M;
                            end if;
                            -- cause(8:6) and xdebugver(31:28) are READ-ONLY, so they deliberately get no storage here.
                        end if;

                    when CSR_DPC =>
                        -- The mepc WARL mask, verbatim: bit0 is not stored (hardwired '0') and bit1 is writable only on a C build.
                        if ENABLE_DEBUG then
                            dpc_r(31 downto 2) <= csr_new_val(31 downto 2);
                            if ENABLE_COMPRESSED then
                                dpc_r(1) <= csr_new_val(1);
                            else
                                dpc_r(1) <= '0';
                            end if;
                        end if;

                    when CSR_DSCRATCH0 =>
                        if ENABLE_DEBUG then
                            dscratch0_r <= csr_new_val;
                        end if;

                    when CSR_DSCRATCH1 =>
                        if ENABLE_DEBUG then
                            dscratch1_r <= csr_new_val;
                        end if;

                    -- ======================================================
                    -- P3 PMP bank writes (p0_specs.md 4/4.1).
                    -- EXACTLY DECODED, one `when` arm per implemented CSR, NEVER a range or wildcard decode.
                    -- The upstream csr_valid AND csr_addr_valid gate is defense-in-depth, not license (p3e_entry_seeds.repro.txt item 3): a write arm decoded wider than its own address would be reachable from a TRAPPING encoding.
                    --
                    -- Three orthogonal guards on every byte and word:
                    --   ENABLE_PMP        the whole bank folds away when off
                    --   i < PMP_ENTRIES   generic-static, so the upper half has no flops and reads WARL zero
                    --   the LOCK filter   applied PER BYTE inside a pmpcfg word, so an unlocked byte in the same word still writes, and the lock checks read the CURRENT (pre-write) cfg values
                    -- The WARL mask (pmp_cfg_warl) pins bits 6:5 to 0 and W to 0 when R=0; pmpaddr stores bits 29:0 only (31:30 WARL 0).
                    -- ======================================================
                    when CSR_PMPCFG0 =>
                        if ENABLE_PMP then
                            if 0 < PMP_ENTRIES and not pmp_locked(pmp_cfg(0)) then
                                pmp_cfg(0) <= pmp_cfg_warl(csr_new_val(7 downto 0));
                            end if;
                            if 1 < PMP_ENTRIES and not pmp_locked(pmp_cfg(1)) then
                                pmp_cfg(1) <= pmp_cfg_warl(csr_new_val(15 downto 8));
                            end if;
                            if 2 < PMP_ENTRIES and not pmp_locked(pmp_cfg(2)) then
                                pmp_cfg(2) <= pmp_cfg_warl(csr_new_val(23 downto 16));
                            end if;
                            if 3 < PMP_ENTRIES and not pmp_locked(pmp_cfg(3)) then
                                pmp_cfg(3) <= pmp_cfg_warl(csr_new_val(31 downto 24));
                            end if;
                        end if;

                    when CSR_PMPCFG1 =>
                        if ENABLE_PMP then
                            if 4 < PMP_ENTRIES and not pmp_locked(pmp_cfg(4)) then
                                pmp_cfg(4) <= pmp_cfg_warl(csr_new_val(7 downto 0));
                            end if;
                            if 5 < PMP_ENTRIES and not pmp_locked(pmp_cfg(5)) then
                                pmp_cfg(5) <= pmp_cfg_warl(csr_new_val(15 downto 8));
                            end if;
                            if 6 < PMP_ENTRIES and not pmp_locked(pmp_cfg(6)) then
                                pmp_cfg(6) <= pmp_cfg_warl(csr_new_val(23 downto 16));
                            end if;
                            if 7 < PMP_ENTRIES and not pmp_locked(pmp_cfg(7)) then
                                pmp_cfg(7) <= pmp_cfg_warl(csr_new_val(31 downto 24));
                            end if;
                        end if;

                    when CSR_PMPCFG2 =>
                        if ENABLE_PMP then
                            if 8 < PMP_ENTRIES and not pmp_locked(pmp_cfg(8)) then
                                pmp_cfg(8) <= pmp_cfg_warl(csr_new_val(7 downto 0));
                            end if;
                            if 9 < PMP_ENTRIES and not pmp_locked(pmp_cfg(9)) then
                                pmp_cfg(9) <= pmp_cfg_warl(csr_new_val(15 downto 8));
                            end if;
                            if 10 < PMP_ENTRIES and not pmp_locked(pmp_cfg(10)) then
                                pmp_cfg(10) <= pmp_cfg_warl(csr_new_val(23 downto 16));
                            end if;
                            if 11 < PMP_ENTRIES and not pmp_locked(pmp_cfg(11)) then
                                pmp_cfg(11) <= pmp_cfg_warl(csr_new_val(31 downto 24));
                            end if;
                        end if;

                    when CSR_PMPCFG3 =>
                        if ENABLE_PMP then
                            if 12 < PMP_ENTRIES and not pmp_locked(pmp_cfg(12)) then
                                pmp_cfg(12) <= pmp_cfg_warl(csr_new_val(7 downto 0));
                            end if;
                            if 13 < PMP_ENTRIES and not pmp_locked(pmp_cfg(13)) then
                                pmp_cfg(13) <= pmp_cfg_warl(csr_new_val(15 downto 8));
                            end if;
                            if 14 < PMP_ENTRIES and not pmp_locked(pmp_cfg(14)) then
                                pmp_cfg(14) <= pmp_cfg_warl(csr_new_val(23 downto 16));
                            end if;
                            if 15 < PMP_ENTRIES and not pmp_locked(pmp_cfg(15)) then
                                pmp_cfg(15) <= pmp_cfg_warl(csr_new_val(31 downto 24));
                            end if;
                        end if;

                    when CSR_PMPADDR0 =>
                        if ENABLE_PMP and 0 < PMP_ENTRIES and
                           pmp_addr_writable(pmp_cfg(0), pmp_cfg(1)) then
                            pmp_addr(0) <= csr_new_val(29 downto 0);
                        end if;
                    when CSR_PMPADDR1 =>
                        if ENABLE_PMP and 1 < PMP_ENTRIES and
                           pmp_addr_writable(pmp_cfg(1), pmp_cfg(2)) then
                            pmp_addr(1) <= csr_new_val(29 downto 0);
                        end if;
                    when CSR_PMPADDR2 =>
                        if ENABLE_PMP and 2 < PMP_ENTRIES and
                           pmp_addr_writable(pmp_cfg(2), pmp_cfg(3)) then
                            pmp_addr(2) <= csr_new_val(29 downto 0);
                        end if;
                    when CSR_PMPADDR3 =>
                        if ENABLE_PMP and 3 < PMP_ENTRIES and
                           pmp_addr_writable(pmp_cfg(3), pmp_cfg(4)) then
                            pmp_addr(3) <= csr_new_val(29 downto 0);
                        end if;
                    when CSR_PMPADDR4 =>
                        if ENABLE_PMP and 4 < PMP_ENTRIES and
                           pmp_addr_writable(pmp_cfg(4), pmp_cfg(5)) then
                            pmp_addr(4) <= csr_new_val(29 downto 0);
                        end if;
                    when CSR_PMPADDR5 =>
                        if ENABLE_PMP and 5 < PMP_ENTRIES and
                           pmp_addr_writable(pmp_cfg(5), pmp_cfg(6)) then
                            pmp_addr(5) <= csr_new_val(29 downto 0);
                        end if;
                    when CSR_PMPADDR6 =>
                        if ENABLE_PMP and 6 < PMP_ENTRIES and
                           pmp_addr_writable(pmp_cfg(6), pmp_cfg(7)) then
                            pmp_addr(6) <= csr_new_val(29 downto 0);
                        end if;
                    when CSR_PMPADDR7 =>
                        if ENABLE_PMP and 7 < PMP_ENTRIES and
                           pmp_addr_writable(pmp_cfg(7), pmp_cfg(8)) then
                            pmp_addr(7) <= csr_new_val(29 downto 0);
                        end if;
                    when CSR_PMPADDR8 =>
                        if ENABLE_PMP and 8 < PMP_ENTRIES and
                           pmp_addr_writable(pmp_cfg(8), pmp_cfg(9)) then
                            pmp_addr(8) <= csr_new_val(29 downto 0);
                        end if;
                    when CSR_PMPADDR9 =>
                        if ENABLE_PMP and 9 < PMP_ENTRIES and
                           pmp_addr_writable(pmp_cfg(9), pmp_cfg(10)) then
                            pmp_addr(9) <= csr_new_val(29 downto 0);
                        end if;
                    when CSR_PMPADDR10 =>
                        if ENABLE_PMP and 10 < PMP_ENTRIES and
                           pmp_addr_writable(pmp_cfg(10), pmp_cfg(11)) then
                            pmp_addr(10) <= csr_new_val(29 downto 0);
                        end if;
                    when CSR_PMPADDR11 =>
                        if ENABLE_PMP and 11 < PMP_ENTRIES and
                           pmp_addr_writable(pmp_cfg(11), pmp_cfg(12)) then
                            pmp_addr(11) <= csr_new_val(29 downto 0);
                        end if;
                    when CSR_PMPADDR12 =>
                        if ENABLE_PMP and 12 < PMP_ENTRIES and
                           pmp_addr_writable(pmp_cfg(12), pmp_cfg(13)) then
                            pmp_addr(12) <= csr_new_val(29 downto 0);
                        end if;
                    when CSR_PMPADDR13 =>
                        if ENABLE_PMP and 13 < PMP_ENTRIES and
                           pmp_addr_writable(pmp_cfg(13), pmp_cfg(14)) then
                            pmp_addr(13) <= csr_new_val(29 downto 0);
                        end if;
                    when CSR_PMPADDR14 =>
                        if ENABLE_PMP and 14 < PMP_ENTRIES and
                           pmp_addr_writable(pmp_cfg(14), pmp_cfg(15)) then
                            pmp_addr(14) <= csr_new_val(29 downto 0);
                        end if;
                    when CSR_PMPADDR15 =>
                        -- Entry 15 has NO successor, so only its own L bit can lock it (PMP_NO_NEXT reads as "unlocked, A=OFF").
                        if ENABLE_PMP and 15 < PMP_ENTRIES and
                           pmp_addr_writable(pmp_cfg(15), PMP_NO_NEXT) then
                            pmp_addr(15) <= csr_new_val(29 downto 0);
                        end if;

                    when others =>
                        null;  -- Read-only CSRs, user-view aliases, or hardwired-zero hpm indices
                end case;
            end if;

            -- ==============================================================
            -- P1 trap-entry and MRET hardware writeback (p0_specs.md 2.3/2.4).
            -- ASSIGNED AFTER the csr_write_en case ON PURPOSE: a later assignment in the same process wins, so these strobes take PRECEDENCE over a same-cycle CSR write.
            -- They cannot in fact coincide BY CONSTRUCTION, since trap_entry_we is driven only from MTRAP_SV and mret_we only from the MRET arm, dedicated FSM states in which no CSR instruction retires (freeze rule (a)), but the ordering is defined anyway so it can never become a silent hazard.
            -- The whole block prunes when ENABLE_TRAPCSR is false (constant-false condition, ports tied inert).
            -- ==============================================================
            if ENABLE_TRAPCSR then
                if trap_entry_we = '1' then
                    -- mepc takes the faulting or resume PC, under the same WARL mask as a software write: bit0 dropped, bit1 only on a C build.
                    mepc_r(31 downto 2) <= trap_pc(31 downto 2);
                    if ENABLE_COMPRESSED then
                        mepc_r(1) <= trap_pc(1);
                    else
                        mepc_r(1) <= '0';
                    end if;
                    mcause_int  <= trap_cause(31);
                    mcause_code <= trap_cause(3 downto 0);
                    mtval_r     <= trap_value;
                    -- mstatus stack PUSH: MPIE takes MIE, then MIE clears.
                    mst_mpie    <= mst_mie;
                    mst_mie     <= '0';
                    -- P2 PRIVILEGE PUSH, riding the SAME strobe: MPP takes the interrupted privilege, then priv is forced to M.
                    -- Traps ALWAYS deliver to M, since there is no delegation (medeleg/mideleg stay illegal CSRs, correct for an M/U-only core).
                    -- Without ENABLE_UMODE, MPP is already pinned to M and priv never leaves '1', so this block is pure P2 cost.
                    if ENABLE_UMODE then
                        mst_mpp <= priv_m & priv_m;   -- '1' gives "11" (M), '0' gives "00" (U)
                        priv_m  <= '1';
                    end if;
                elsif mret_we = '1' then
                    -- mstatus stack POP: MIE takes MPIE, then MPIE sets to 1.
                    mst_mie  <= mst_mpie;
                    mst_mpie <= '1';
                    -- P2 PRIVILEGE POP, riding the SAME strobe: priv takes MPP, THEN MPP is forced to "00" (U), the least-privileged supported mode.
                    -- That force is spec-required so a second MRET cannot re-escalate, and the p2_mppstuck negative control drops exactly this line.
                    -- MPP is WARL {00,11}, so MPP_M is the only M encoding.
                    if ENABLE_UMODE then
                        if mst_mpp = MPP_M then
                            priv_m <= '1';
                        else
                            priv_m <= '0';
                            -- P3-entry: an MRET that returns to a privilege BELOW M also clears MPRV, which the priv spec requires.
                            -- Without it, M-privileged data-access semantics would ride into U, an escape vector the moment PMP consumes data_priv_m.
                            -- Negative control: p3e_mprvmret drops exactly this line.
                            mst_mprv <= '0';
                        end if;
                        mst_mpp <= MPP_U;
                    end if;
                end if;
            end if;

            -- ==============================================================
            -- D1 DEBUG ENTRY and DRET SIDE EFFECTS (d1_spec.md 2).
            -- ASSIGNED AFTER the P1 block for the same reason it is assigned after the write case: a later assignment in the same process wins, so a debug entry takes precedence over both a same-cycle CSR write and a same-cycle trap entry.
            -- They cannot in fact coincide BY CONSTRUCTION, since dbg_entry_we is driven only from DBG_SV and dbg_ret_we only from DBG_RET, dedicated FSM states in which no CSR instruction retires and no MTRAP_* state is current, but the ordering is defined anyway so it can never become a silent hazard.
            -- The whole block prunes when ENABLE_DEBUG is false (constant-false condition, ports tied inert).
            --
            -- ENTRY IS ONE ACTION: dpc, cause, prv, the privilege force and debug_mode all move on ONE strobe.
            -- That is the D0/P1 1f atomicity argument: two flops in two domains updated by two mechanisms is the F1+ defect class.
            -- ==============================================================
            if ENABLE_DEBUG then
                if dbg_entry_we = '1' then
                    -- dpc takes the interrupted PC, under the SAME IALIGN-WARL mask a software write gets (bit0 dropped, bit1 only on a C build).
                    -- vesta picks the value: pc for a synchronous ebreak, pc_next_reg for a halt or step (the resume PC).
                    dpc_r(31 downto 2) <= dbg_pc(31 downto 2);
                    if ENABLE_COMPRESSED then
                        dpc_r(1) <= dbg_pc(1);
                    else
                        dpc_r(1) <= '0';
                    end if;
                    dcsr_cause_r <= dbg_cause;
                    -- prv takes the interrupted privilege, and debug code then executes at M.
                    -- Without U-mode both are already M, so the else arm is a constant and the priv force is pure P2 cost.
                    if ENABLE_UMODE then
                        dcsr_prv_r <= priv_m & priv_m;   -- '1' gives "11" (M), '0' gives "00" (U)
                        priv_m     <= '1';
                    else
                        dcsr_prv_r <= MPP_M;
                    end if;
                    debug_mode_r <= '1';
                elsif dbg_ret_we = '1' then
                    -- DRET: leave debug mode and restore the privilege dcsr.prv names.
                    -- dcsr.prv is WARL to implemented modes, so MPP_M is the only M encoding it can hold.
                    debug_mode_r <= '0';
                    if ENABLE_UMODE then
                        if dcsr_prv_r = MPP_M then
                            priv_m <= '1';
                        else
                            priv_m <= '0';
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Output read data
    csr_read_data <= csr_read_val;

    -- X3 Zcmt: export the jvt base (held zero when ENABLE_ZCMT is off).
    jvt_value <= jvt;

    -- X4 Zfinx: export the rounding mode and its validity.
    -- A dynamic-rm (rm=111) instruction is legal only when frm holds a valid mode (000..100); 101, 110 and 111 in frm are reserved and invalid.
    -- When ENABLE_ZFINX is off fp_csr is zero, so frm_value is "000" and frm_valid is '1', which is harmless because no FP op decodes anyway.
    frm_value <= fp_csr(7 downto 5);
    frm_valid <= '0' when (fp_csr(7 downto 5) = "101" or fp_csr(7 downto 5) = "110" or
                           fp_csr(7 downto 5) = "111") else '1';

    -- ----------------------------------------------------------------------
    -- P1 trap-CSR exports (p0_specs.md 2.4).
    -- csr_unit exports STATE only: the interrupt-take decision (`mstatus_mie and ((meip and MEIE) or (msip and MSIE) or (mtip and MTIE))`, priority MEI first, then MSI, then MTI) is vesta's, never this file's.
    -- With ENABLE_TRAPCSR false every export is its reset value: mtvec and mepc zero, MIE low, mie_bits "000", and legacy_mode '1', which is what makes vesta's delivery muxes constant-fold to the legacy IVT path.
    -- ----------------------------------------------------------------------
    mtvec_value <= mtvec_base & "00";   -- MODE is WARL "00" (direct)
    mepc_value  <= mepc_r & '0';        -- bit0 always '0'
    mstatus_mie <= mst_mie;
    mie_bits    <= mie_meie & mie_mtie & mie_msie;  -- {MEIE, MTIE, MSIE}
    legacy_mode <= mtrapctl_legacy;

    -- ----------------------------------------------------------------------
    -- P2 U-mode exports (p0_specs.md 3.1).
    -- All three are STATE, never policy: the U-mode decode gate lives in maindec and the ECALL cause mux in vesta.
    -- With ENABLE_UMODE false these are the reset constants for all time (priv_mode '1' for M, status_tw '0', mcounteren_bits "00000"), exactly the inert defaults maindec declares, so the U-mode decode logic constant-folds away on a non-U build.
    -- ----------------------------------------------------------------------
    priv_mode       <= priv_m;
    status_tw       <= mst_tw;
    mcounteren_bits <= mcounteren_r;

    -- ----------------------------------------------------------------------
    -- D1 debug-mode exports (d1_spec.md 1).
    -- All STATE, never policy: the entry and exit decisions and the halt/step/ebreak recognition all live in vesta's FSM, and the CSR access rule lives in maindec.
    -- With ENABLE_DEBUG false these are the reset constants for all time (debug_mode '0', ebreakm/ebreaku/step '0', dpc zero), so maindec's dbg_csr_denied is a constant deny, its DRET arm folds away, and every vesta debug arm is statically unreachable.
    -- ----------------------------------------------------------------------
    debug_mode      <= debug_mode_r;
    dcsr_ebreakm    <= dcsr_ebreakm_r;
    dcsr_ebreaku    <= dcsr_ebreaku_r;
    dcsr_step       <= dcsr_step_r;
    dpc_value       <= dpc_r & '0';     -- bit0 always '0'

    -- ----------------------------------------------------------------------
    -- P3-entry: effective DATA-access privilege (p3_kickoff.md 3 item 1).
    -- When mstatus.MPRV = 1, loads and stores are checked at privilege MPP while instruction fetches keep priv_mode.
    -- MPRV can only be 1 in M-mode (an MRET below M clears it, and U cannot write mstatus), so in practice this lets M-mode software perform data accesses with U-mode privilege, exactly the input the P3 PMP data-side check needs.
    -- Constant '1' when ENABLE_UMODE is off (mst_mprv stuck '0', priv_m stuck '1').
    -- ----------------------------------------------------------------------
    data_priv_m <= priv_m when mst_mprv = '0' else
                   '1'    when mst_mpp = MPP_M else
                   '0';

    -- P3 red-team F1: the return privilege, i.e. mstatus.MPP mapped.
    -- Read COMBINATIONALLY, so during MTRAP_RET, before the mret_we edge pops priv and MPP, it is the privilege the returned-to instruction will run at.
    -- Same expression the MRET pop uses to reload priv_m, and '1' (M) when UMODE is off, since MPP is then pinned to MPP_M.
    mret_priv_m <= '1' when mst_mpp = MPP_M else '0';

    -- ----------------------------------------------------------------------
    -- P3 PMP exports (p0_specs.md 4.1): a pure flattening of the bank.
    -- csr_unit exports STORAGE, never match or priority policy (that is pmp_unit's) and never a check point (that is vesta's).
    --   entry i cfg byte = pmp_cfg_flat(8*i+7  downto 8*i)
    --   entry i pmpaddr  = pmp_addr_flat(30*i+29 downto 30*i)   (= phys 31:2)
    -- All-zero with ENABLE_PMP false (nothing ever writes the bank), and the entries at or above PMP_ENTRIES are all-zero for the same reason, so an OFF build's pmp_unit folds to "grant everything" and a PMP_ENTRIES=8 build's upper half folds to A=OFF, which never matches.
    -- ----------------------------------------------------------------------
    gen_pmp_flat: for i in 0 to PMP_MAX_ENTRIES-1 generate
        pmp_cfg_flat(8*i+7 downto 8*i)     <= pmp_cfg(i);
        pmp_addr_flat(30*i+29 downto 30*i) <= pmp_addr(i);
    end generate;

    -- ----------------------------------------------------------------------
    -- V1 LOCKSTEP TRACER EXPORTS (read-only, see the port-list comment).
    -- ----------------------------------------------------------------------
    -- csr_addr_stores() lists EXACTLY the addresses whose write-case arm stores, carrying the SAME ENABLE_* gate the arm carries.
    -- ** KEEP IT IN SYNC WITH THE `case csr_addr` WRITE BLOCK ABOVE. **
    -- Two documented approximations, both outside the V2 (default-config) scope and both listed in v1_report.md:
    --   * the PMP arms additionally test RUN-TIME conditions (pmp_locked, pmp_addr_writable) that a static address decode cannot see, so a write to a LOCKED entry would export a commit that did not happen.
    --     ENABLE_PMP is false in the Castalia and Argus configs.
    --   * csr_commit_val is csr_new_val, i.e. the value the RMW REQUESTS, whereas for the WARL-masked CSRs (mcountinhibit, jvt, fflags/frm/fcsr, mtvec, mcause, mstatus, mtrapctl, mcounteren, pmpcfg) the value STORED is a masked subset.
    --     It is exact for every CSR the V2 suite writes: rv32ziscr writes only mcycle/mcycleh/minstret/minstreth, all pass-through arms.
    gen_trc: if TRACE_ENABLE generate
        csr_commit_we  <= csr_write_en when csr_addr_stores(csr_addr) else '0';
        csr_commit_val <= csr_new_val;

        -- The same assembly the CSR_MSTATUS read arm uses, so the mret pop that MTRAP_RET performs is observable as a `C 300` record.
        mstatus_value  <= (21 => mst_tw, 17 => mst_mprv,
                           12 => mst_mpp(1), 11 => mst_mpp(0),
                            7 => mst_mpie, 3 => mst_mie,
                           others => '0');

        fflags_value   <= (XLEN-1 downto 5 => '0') & fp_csr(4 downto 0);
    end generate;

    -- Tracer OFF: every export is a hard constant, so no tracer logic is inferred.
    gen_trc_off: if not TRACE_ENABLE generate
        csr_commit_we  <= '0';
        csr_commit_val <= (others => '0');
        mstatus_value  <= (others => '0');
        fflags_value   <= (others => '0');
    end generate;

end behave;
