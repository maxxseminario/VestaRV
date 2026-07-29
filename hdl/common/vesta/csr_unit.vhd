library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.constants.all;

entity csr_unit is
    generic (
        -- Core ISA feature switches — advertised through the read-only misa
        -- CSR (0x301) so software can probe what this chip was built with.
        ENABLE_MUL        : boolean := true;
        ENABLE_DIV        : boolean := true;
        ENABLE_ATOMICS    : boolean := true;
        ENABLE_COMPRESSED : boolean := true;
        ENABLE_BITMANIP   : boolean := true;
        -- X1 Zihpm: real 64-bit hardware performance counters 3/4 behind this
        -- generic. Default false => counters 3-31 hardwired zero (read-zero /
        -- write-ignore / no trap), fully back-compatible with the X0 scaffold.
        ENABLE_ZIHPM      : boolean := false;  -- X1 (Zihpm): real hpm counters
        -- X3 Zcmt: the jvt (jump-vector-table base) CSR (0x017, URW) lives here.
        -- Default false => jvt hardwired zero, and maindec's csr_valid map makes
        -- 0x017 an illegal CSR, so read/write traps (both-polarity gate).
        ENABLE_ZCMT       : boolean := false;  -- X3 (Zcmt): jvt CSR
        ENABLE_ZFINX      : boolean := false;  -- X4 (Zfinx): consumed from phase X4 on; scaffolded X0
        -- P0 privileged-architecture scaffolding (default false / 16 entries).
        -- The CSR FILE for all three phases lives here: P1's mstatus/mstatush/
        -- mtvec/mie/mip/mscratch/mepc/mcause/mtval + mtrapctl (0x7C0), P2's
        -- privilege register + real mcounteren, P3's pmpcfg0-3/pmpaddr0-15
        -- bank (PMP_ENTRIES sizes the bank; the CSR ADDRESS map stays the
        -- 16-entry superset, entries above the count reading WARL zero).
        -- Nothing consumes them yet -- adding the CSRs is the phase agent's job.
        ENABLE_TRAPCSR    : boolean := false;  -- P1 (trap CSRs): consumed from phase P1 on; scaffolded P0
        ENABLE_UMODE      : boolean := false;  -- P2 (U-mode): consumed from phase P2 on; scaffolded P0
        ENABLE_PMP        : boolean := false;  -- P3 (PMP/Smpmp): consumed from phase P3 on; scaffolded P0
        PMP_ENTRIES       : integer := 16      -- P3 (PMP entry count {8,16}): consumed from phase P3 on; scaffolded P0
    );
    port (
        clk              : in  std_logic;
        resetn           : in  std_logic;

        -- X3 Zcmt: jvt base exported to vesta's table-jump FSM ({jvt[31:6],6'b0}
        -- is the table base). Held zero when ENABLE_ZCMT is off.
        jvt_value        : out std_logic_vector(31 downto 0);

        -- X4 Zfinx fcsr/fflags/frm. All inert when ENABLE_ZFINX is off (fp_csr
        -- held zero, never written). fp_flags_we/fp_flags_val sticky-OR the
        -- completing FP op's flags into fflags (driven by vesta INDEPENDENT of rd,
        -- so rd=x0 still sets flags). frm_value/frm_valid export the rounding mode
        -- to decode/FPU (dynamic-rm legality + effective-rm resolution).
        fp_flags_we      : in  std_logic := '0';                    -- strobe: OR fp_flags_val into fflags
        fp_flags_val     : in  std_logic_vector(4 downto 0) := (others => '0');
        frm_value        : out std_logic_vector(2 downto 0);        -- fp_csr[7:5]
        frm_valid        : out std_logic;                          -- '1' iff frm in {000..100}

        -- M13: hart id is a PORT (was the HARTID generic) so all four hart
        -- tiles share ONE netlist (tile hardening, M14); wired per instance.
        hart_id          : in  std_logic_vector(XLEN-1 downto 0) := (others => '0'); -- Value returned by mhartid (0xF14)

        -- CSR instruction interface
        csr_addr         : in  std_logic_vector(11 downto 0);  -- CSR address
        csr_write_data   : in  std_logic_vector(XLEN-1 downto 0);  -- Data to write (from rs1 or immediate)
        csr_op           : in  std_logic_vector(2 downto 0);   -- CSR operation (funct3)
        csr_valid        : in  std_logic;                      -- Valid CSR operation
        csr_read_data    : out std_logic_vector(XLEN-1 downto 0);  -- Data read from CSR

        -- Performance counter input
        inst_retired     : in  std_logic;                      -- Instruction retired signal

        -- X1 Zihpm event inputs (from vesta internal signals — NOT tile/MCU
        -- boundary ports). All default inactive so non-Zihpm instantiations and
        -- the OFF build are unaffected. csr_unit derives the grant/trap edges
        -- internally from these levels (it runs on the free-running clk, so the
        -- levels are sampled every real cycle even while clk_cpu is gated).
        ev_bus_stall     : in  std_logic := '0';  -- '1' = arbiter request asserted, grant not held (mem_ready low)
        ev_sleep         : in  std_logic := '0';  -- '1' = hart in WFI/sleep state
        ev_trap_entry    : in  std_logic := '0';  -- '1' while in a trap-entry state (IRQ_SV / TRAP_STATE)

        -- ------------------------------------------------------------------
        -- P1 trap-CSR interface (inert when ENABLE_TRAPCSR = false).
        -- FROZEN by ~/vesta_docs/priv_arch/p0_specs.md 2.4 — names, widths and
        -- inert defaults are the binding contract between this file (Agent A)
        -- and the vesta trap FSM (Agent B). Every port has a default so any
        -- existing instantiation and the OFF polarity are untouched.
        -- ------------------------------------------------------------------
        irq_msip         : in  std_logic := '0';  -- CLINT msip level  -> mip.MSIP(3)
        irq_mtip         : in  std_logic := '0';  -- CLINT mtip level  -> mip.MTIP(7)
        irq_meip         : in  std_logic := '0';  -- router meip level -> mip.MEIP(11)
        -- MTRAP_SV strobe: mepc<=trap_pc, mcause<=trap_cause, mtval<=trap_value,
        -- MPIE<=MIE, MIE<='0' (P2 adds MPP<=priv).
        trap_entry_we    : in  std_logic := '0';
        trap_pc          : in  std_logic_vector(XLEN-1 downto 0) := (others => '0'); -- per the 2.2 mepc column
        trap_cause       : in  std_logic_vector(XLEN-1 downto 0) := (others => '0'); -- bit 31 + code(3:0) stored, rest discarded
        trap_value       : in  std_logic_vector(XLEN-1 downto 0) := (others => '0');
        -- MRET strobe: MIE<=MPIE, MPIE<='1' (P2 adds priv<=MPP, MPP<="00").
        mret_we          : in  std_logic := '0';
        mtvec_value      : out std_logic_vector(XLEN-1 downto 0); -- {BASE(31:2),"00"}
        mepc_value       : out std_logic_vector(XLEN-1 downto 0); -- MRET jump target (bit0 always '0')
        mstatus_mie      : out std_logic;
        mie_bits         : out std_logic_vector(2 downto 0);      -- {MEIE, MTIE, MSIE}
        -- mtrapctl.LEGACY. MUST read '1' when ENABLE_TRAPCSR is false so vesta's
        -- delivery muxes constant-fold to the legacy (irq_handler/IVT) path.
        legacy_mode      : out std_logic;

        -- ------------------------------------------------------------------
        -- P2 U-mode interface (inert when ENABLE_UMODE = false).
        -- FROZEN by ~/vesta_docs/priv_arch/p0_specs.md 3.1. The PRIVILEGE
        -- REGISTER lives in THIS file (the P1 comment contract): vesta drives
        -- nothing new into csr_unit for P2 -- the priv push/pop rides the
        -- EXISTING trap_entry_we / mret_we strobes below.
        -- ------------------------------------------------------------------
        priv_mode        : out std_logic;                     -- '1'=M, '0'=U; reset '1'.
                                                              --   MUST read '1' when ENABLE_UMODE is false.
        status_tw        : out std_logic;                     -- mstatus.TW (21); '0' when UMODE off
        mcounteren_bits  : out std_logic_vector(4 downto 0)   -- {HPM4,HPM3,IR,TM,CY}; "00000" when off
    );
end csr_unit;

architecture behave of csr_unit is

    function b2sl(b : boolean) return std_logic is
    begin
        if b then
            return '1';
        else
            return '0';
        end if;
    end function;

    -- misa: MXL=01 (RV32) in bits 31:30; extension letters A(0), B(1), C(2),
    -- I(8), M(12). M is advertised only when BOTH mul and div are present
    -- (the M extension is all-or-nothing per the spec). B (ratified 2024) =
    -- Zba+Zbb+Zbs, all of which this core implements when ENABLE_BITMANIP
    -- (Zbc rides the same switch but has no misa letter). Read-only — writes
    -- are ignored like the other fixed CSRs. Zihpm adds NO misa bit.
    -- NOTE: misa is XLEN-wide but the MXL field POSITION is XLEN-relative
    -- (bits XLEN-1:XLEN-2) and its VALUE differs per width (01=RV32, 10=RV64)
    -- — bit 30 here is the RV32 encoding, revisit with any real RV64 work.
    -- P2: bit 20 (U) is THE one misa change of the whole P-series program
    -- (p0_specs.md 3/6) -- set iff ENABLE_UMODE, so an OFF build's misa is
    -- bit-identical. M-mode is not a misa letter, and S (bit 18) stays clear
    -- (D2: S-mode is out of scope).
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

    -- X1 Zihpm: real counters 3 and 4 + their event selectors + mcountinhibit.
    -- When ENABLE_ZIHPM is false these signals are held at reset (zero) and
    -- never written, so every read arm below returns zero for BOTH polarities.
    signal hpm3       : std_logic_vector(63 downto 0);
    signal hpm4       : std_logic_vector(63 downto 0);
    signal mhpmevent3 : std_logic_vector(XLEN-1 downto 0);
    signal mhpmevent4 : std_logic_vector(XLEN-1 downto 0);
    signal mcountinhibit : std_logic_vector(XLEN-1 downto 0);

    -- X3 Zcmt jvt CSR (0x017). WARL: mode = bits(5:0) pinned 0 (Jump Table Mode
    -- only), base = bits(31:6) writable (64-byte aligned). Held zero and never
    -- written when ENABLE_ZCMT is false, so both read arm and export return zero.
    signal jvt        : std_logic_vector(XLEN-1 downto 0);

    -- X4 Zfinx fcsr: frm = fp_csr(7:5), fflags = fp_csr(4:0) = {NV,DZ,OF,UF,NX}.
    -- Held zero and never written when ENABLE_ZFINX is off (both read arms and
    -- exports then return zero, and fflags/frm/fcsr are illegal CSRs via csr_valid).
    signal fp_csr     : std_logic_vector(7 downto 0);
    -- Edge trackers (clk domain) for the grant (stall falling edge) and
    -- trap-entry (rising edge) events.
    signal prev_stall : std_logic;
    signal prev_trap  : std_logic;

    -- ----------------------------------------------------------------------
    -- P1 standard M-mode trap CSR file (p0_specs.md 2.1). Every one of these
    -- is written ONLY under `if ENABLE_TRAPCSR` (the ENABLE_ZFINX/jvt idiom),
    -- so with the generic off they stay at their RESET values forever and the
    -- ten addresses are illegal CSRs anyway (maindec csr_addr_valid).
    -- Two reset values are deliberately NOT zero:
    --   * mst_mpp resets "11" — MPP is WARL {11} in P1 (M-mode only), so 11 is
    --     the only legal value the field can ever hold. P2 widens it to
    --     {00,11} and drives it from the privilege register.
    --   * mtrapctl_legacy resets '1' — LEGACY is the reset default (D1), and
    --     the freeze REQUIRES legacy_mode = '1' on an ENABLE_TRAPCSR=false
    --     build so vesta's delivery muxes constant-fold to the legacy path.
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
    -- P2 U-mode state (p0_specs.md 3/3.1). Every one of these is written ONLY
    -- under `if ENABLE_UMODE`, so with the generic off they hold their RESET
    -- values forever:
    --   * priv_m resets '1' (M). The freeze REQUIRES priv_mode to read '1' on
    --     an ENABLE_UMODE=false build, which is what makes maindec's U-mode
    --     decode gate statically false there.
    --   * mst_tw resets '0' (mstatus.TW: no WFI timeout wait).
    --   * mcounteren_r resets "00000" -- and STAYS there when UMODE is off, so
    --     mcounteren keeps reading zero / ignoring writes exactly as before
    --     (the address has always been legal, constants.vhd 353).
    -- MPP WARL widens here from P1's {11} to {00,11}. FROZEN RULE (P2 prompt):
    -- the two UNSUPPORTED encodings 01/10 map to "11" (M), the CONSERVATIVE
    -- direction -- an MRET after such a write returns to M, never to a mode the
    -- writer did not ask for. (WARL permits any supported value; mapping down
    -- to 00 would silently DROP privilege and is the surprising choice.)
    -- ----------------------------------------------------------------------
    constant MPP_U : std_logic_vector(1 downto 0) := "00";  -- mstatus.MPP = U-mode

    signal priv_m          : std_logic;                      -- privilege: '1'=M, '0'=U (reset M)
    signal mst_tw          : std_logic;                      -- mstatus.TW (21), WARL {0,1} iff UMODE
    signal mcounteren_r    : std_logic_vector(4 downto 0);   -- mcounteren {HPM4,HPM3,IR,TM,CY}

    -- mcause bits 30:4 read 0 (WLRL: only bit31 + code(3:0) are stored).
    constant MCAUSE_RSVD27 : std_logic_vector(26 downto 0) := (others => '0');

    -- Internal signals
    signal csr_write_en  : std_logic;
    signal csr_read_val  : std_logic_vector(XLEN-1 downto 0);
    signal csr_new_val   : std_logic_vector(XLEN-1 downto 0);

    -- XLEN-wide comparison/mask constants (slv "=" on unequal lengths is
    -- silently false — never compare against a literal of another width)
    constant CSR_ZERO_X : std_logic_vector(XLEN-1 downto 0) := (others => '0');
    -- mcountinhibit implemented bits: 0 (cycle), 2 (instret), 3/4 (hpm3/4)
    constant MCOUNTINHIBIT_MASK : std_logic_vector(XLEN-1 downto 0) :=
        (0 => '1', 2 => '1', 3 => '1', 4 => '1', others => '0');

    -- Event decode: returns true when the counter whose selector is `sel`
    -- should increment this cycle. Event set is FIXED (X1.5 spec / D2):
    --   0 off | 1 arbiter-stall cycles | 2 shared-bus grants |
    --   3 sleep cycles | 4 trap entries. Unsupported values count nothing.
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

    -- CSR write enable (don't write on read-only operations when rs1/uimm = 0)
    csr_write_en <= csr_valid when (csr_op(1) = '1' or csr_op(0) = '1'
                                or (csr_write_data /= CSR_ZERO_X))
                                else '0';

    -- CSR read process
    process(csr_addr, mcycle, minstret, hart_id,
            hpm3, hpm4, mhpmevent3, mhpmevent4, mcountinhibit, jvt, fp_csr,
            mst_mie, mst_mpie, mst_mpp, mtvec_base, mie_msie, mie_mtie, mie_meie,
            mscratch, mepc_r, mcause_int, mcause_code, mtval_r, mtrapctl_legacy,
            irq_msip, irq_mtip, irq_meip,
            mst_tw, mcounteren_r)
    begin
        case csr_addr is
            -- Machine Information Registers (Read-only)
            when CSR_MHARTID   => csr_read_val <= hart_id;
            when CSR_MISA      => csr_read_val <= MISA_VALUE;

            -- X3 Zcmt jvt (read arm unconditional; jvt is held zero when
            -- ENABLE_ZCMT is off, and 0x017 is an illegal CSR there anyway).
            when CSR_JVT       => csr_read_val <= jvt;

            -- X4 Zfinx fflags/frm/fcsr (read arms unconditional like jvt; fp_csr
            -- is zero when ENABLE_ZFINX is off, and the addresses are illegal there
            -- via csr_valid). Reserved high bits read 0 (WPRI).
            when CSR_FFLAGS    => csr_read_val <= x"000000" & "000" & fp_csr(4 downto 0);
            when CSR_FRM       => csr_read_val <= x"000000" & "00000" & fp_csr(7 downto 5);
            when CSR_FCSR      => csr_read_val <= x"000000" & fp_csr(7 downto 0);

            -- Machine Counters (Read/Write)
            when CSR_MCYCLE    => csr_read_val <= mcycle(XLEN-1 downto 0);
            when CSR_MINSTRET  => csr_read_val <= minstret(XLEN-1 downto 0);
            when CSR_MCYCLEH   => csr_read_val <= mcycle(63 downto 32);
            when CSR_MINSTRETH => csr_read_val <= minstret(63 downto 32);

            -- User-readable counters (Read-only shadows of machine counters).
            -- This M-mode-only core implements NO mcounteren: cycle/instret read
            -- unconditionally, so the hpm user-view arms below do the same (see
            -- report -- mcounteren reads zero rather than gating/trapping).
            when CSR_CYCLE     => csr_read_val <= mcycle(XLEN-1 downto 0);
            when CSR_INSTRET   => csr_read_val <= minstret(XLEN-1 downto 0);
            when CSR_CYCLEH    => csr_read_val <= mcycle(63 downto 32);
            when CSR_INSTRETH  => csr_read_val <= minstret(63 downto 32);

            -- X1 Zihpm counters 3/4 (machine + user-view alias). Read zero when
            -- ENABLE_ZIHPM is false (signals held at reset). Counters 5-31 and
            -- time/timeh fall through to `others` => zero (legal, no trap).
            when CSR_MHPMEVENT3    => csr_read_val <= mhpmevent3;
            when CSR_MHPMEVENT4    => csr_read_val <= mhpmevent4;
            when CSR_MHPMCOUNTER3  | CSR_HPMCOUNTER3  => csr_read_val <= hpm3(XLEN-1 downto 0);
            when CSR_MHPMCOUNTER4  | CSR_HPMCOUNTER4  => csr_read_val <= hpm4(XLEN-1 downto 0);
            when CSR_MHPMCOUNTER3H | CSR_HPMCOUNTER3H => csr_read_val <= hpm3(63 downto 32);
            when CSR_MHPMCOUNTER4H | CSR_HPMCOUNTER4H => csr_read_val <= hpm4(63 downto 32);
            when CSR_MCOUNTINHIBIT => csr_read_val <= mcountinhibit;

            -- P2 mcounteren (0x306) becomes REAL: CY(0)/TM(1)/IR(2)/HPM3(3)/
            -- HPM4(4); bits 31:5 WARL 0. The address has ALWAYS been legal
            -- (read-zero / write-ignore) -- with ENABLE_UMODE off mcounteren_r
            -- is stuck at "00000", so this arm returns the identical zero the
            -- `others` arm used to, bit-for-bit.
            when CSR_MCOUNTEREN    => csr_read_val <= x"000000" & "000" & mcounteren_r;

            -- ==============================================================
            -- P1 standard M-mode trap CSRs (p0_specs.md 2.1).
            -- Read arms are UNCONDITIONAL (the jvt/fcsr precedent): the state
            -- is held at reset when ENABLE_TRAPCSR is off, and all ten
            -- addresses are illegal CSRs there, so nothing can observe them.
            -- CLASS-4 (readback completeness) NOTE: every reserved/WPRI bit is
            -- driven to its spec value here, not left to the `others` arm.
            -- ==============================================================
            -- mstatus: MIE(3), MPIE(7), MPP(12:11) and -- from P2 -- TW(21).
            -- Everything else still reads 0 (MPRV stays 0: U-mode memory access
            -- is unrestricted until P3). mst_tw is stuck '0' with ENABLE_UMODE
            -- off, so the OFF/trapCsr-only read value is unchanged.
            when CSR_MSTATUS   => csr_read_val <= (21 => mst_tw,
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
            -- mip: READ-ONLY live mirror of the three interrupt level wires
            -- (no storage — every source clears at the source: CLINT msip
            -- write, mtimecmp, irq_router claim/complete). Forced to zero on an
            -- OFF build so the levels cannot leak into an unreachable arm.
            when CSR_MIP       =>
                if ENABLE_TRAPCSR then
                    csr_read_val <= (11 => irq_meip, 7 => irq_mtip,
                                     3 => irq_msip, others => '0');
                else
                    csr_read_val <= CSR_ZERO_X;
                end if;
            when CSR_MSCRATCH  => csr_read_val <= mscratch;
            -- mepc: bit0 hardwired 0 (bit1 too on a no-C build — see the write).
            when CSR_MEPC      => csr_read_val <= mepc_r & '0';
            -- mcause: Interrupt(31) + ExceptionCode(3:0); bits 30:4 read 0.
            when CSR_MCAUSE    => csr_read_val <= mcause_int & MCAUSE_RSVD27 & mcause_code;
            when CSR_MTVAL     => csr_read_val <= mtval_r;
            -- mtrapctl (custom 0x7C0): bit0 LEGACY, bits 31:1 WARL 0.
            when CSR_MTRAPCTL  => csr_read_val <= x"0000000" & "000" & mtrapctl_legacy;

            when others        => csr_read_val <= CSR_ZERO_X;
        end case;
    end process;

    -- CSR operation computation
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

    -- CSR write process
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

            -- P1 trap CSR file. mie resets 0 (standard mode wakes masked —
            -- the legacy hardwire-enable path is untouched); MPP resets to M
            -- and mtrapctl.LEGACY resets '1' (see the declaration comment).
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

            -- P2 U-mode state. priv resets to M ('1') -- REQUIRED to read '1'
            -- forever on an ENABLE_UMODE=false build (freeze 3.1).
            priv_m          <= '1';
            mst_tw          <= '0';
            mcounteren_r    <= (others => '0');

        elsif rising_edge(clk) then
            -- X4 Zfinx: sticky-OR the completing FP op's flags into fflags. Driven
            -- by vesta INDEPENDENT of rd (rd=x0 still sets flags — spec-required).
            -- A same-cycle CSR write to fflags/frm/fcsr overrides this below
            -- (later assignment wins), matching the mcycle write-precedence idiom.
            -- A CSR-write instruction is never itself an FP op, so they never
            -- collide within one instruction; the precedence is defined anyway.
            if ENABLE_ZFINX and fp_flags_we = '1' then
                fp_csr(4 downto 0) <= fp_csr(4 downto 0) or fp_flags_val;
            end if;

            -- Cycle counter: free-running, optionally inhibited by
            -- mcountinhibit(0) (only reachable when ENABLE_ZIHPM writes it).
            if not (ENABLE_ZIHPM and mcountinhibit(0) = '1') then
                mcycle <= std_logic_vector(unsigned(mcycle) + 1);
            end if;

            -- Instruction counter: on retire, optionally inhibited by bit 2.
            if inst_retired = '1' and not (ENABLE_ZIHPM and mcountinhibit(2) = '1') then
                minstret <= std_logic_vector(unsigned(minstret) + 1);
            end if;

            -- X1 Zihpm: real counters 3/4. Whole block prunes when the generic
            -- is false (constant-false conditions), leaving hpm3/4 at zero.
            if ENABLE_ZIHPM then
                -- Derive the two edge events from the sampled levels. prev_*
                -- still holds LAST cycle's value at this point (the updates
                -- below schedule next-cycle values).
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

            -- Handle CSR writes. A later assignment to a counter half here wins
            -- over the increment above (write precedence, same as mcycle today).
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

                    -- X1 Zihpm writable CSRs (ignored when ENABLE_ZIHPM off so
                    -- they stay hardwired zero for the OFF polarity).
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

                    -- X3 Zcmt jvt write (WARL): mode(5:0) pinned 0, base(31:6)
                    -- writable. Gated on ENABLE_ZCMT so it stays hardwired zero for
                    -- the OFF polarity (and 0x017 traps illegal there via csr_valid).
                    when CSR_JVT =>
                        if ENABLE_ZCMT then
                            jvt <= csr_new_val(31 downto 6) & "000000";
                        end if;

                    -- X4 Zfinx CSR writes REPLACE the addressed sub-field, gated on
                    -- ENABLE_ZFINX (hardwired zero for the OFF polarity; illegal CSR
                    -- there anyway). These win over the sticky-OR above (later wins).
                    when CSR_FFLAGS =>
                        if ENABLE_ZFINX then fp_csr(4 downto 0) <= csr_new_val(4 downto 0); end if;
                    when CSR_FRM =>
                        if ENABLE_ZFINX then fp_csr(7 downto 5) <= csr_new_val(2 downto 0); end if;
                    when CSR_FCSR =>
                        if ENABLE_ZFINX then fp_csr <= csr_new_val(7 downto 0); end if;

                    -- ======================================================
                    -- P1 standard M-mode trap CSR writes (p0_specs.md 2.1).
                    -- All gated on ENABLE_TRAPCSR so the file stays at reset
                    -- for the OFF polarity (and the addresses trap there).
                    -- ======================================================
                    when CSR_MSTATUS =>
                        if ENABLE_TRAPCSR then
                            mst_mie  <= csr_new_val(3);
                            mst_mpie <= csr_new_val(7);
                            if ENABLE_UMODE then
                                -- P2: MPP WARL widens to {00, 11}. A written 00
                                -- stores 00 (U); 11 stores 11 (M); the two
                                -- UNSUPPORTED encodings 01/10 map to 11 (M) --
                                -- the FROZEN conservative direction (see the
                                -- MPP_U declaration comment).
                                if csr_new_val(12 downto 11) = MPP_U then
                                    mst_mpp <= MPP_U;
                                else
                                    mst_mpp <= MPP_M;
                                end if;
                                -- TW (21) is WARL {0,1} from P2 (M-only build:
                                -- hardwired 0, the else arm below).
                                mst_tw <= csr_new_val(21);
                            else
                                -- MPP is WARL {11} without U-mode: a write of
                                -- ANY value stores 11 (the only supported mode).
                                mst_mpp  <= MPP_M;
                            end if;
                        end if;

                    -- P2 mcounteren (0x306): CY/TM/IR/HPM3/HPM4 writable; bits
                    -- 31:5 WARL 0 (no storage). Gated on ENABLE_UMODE so the
                    -- register stays hardwired zero (write-ignore) otherwise --
                    -- bit-identical to the pre-P2 `others => null` behaviour.
                    when CSR_MCOUNTEREN =>
                        if ENABLE_UMODE then
                            mcounteren_r <= csr_new_val(4 downto 0);
                        end if;

                    -- mstatush: legal, write-ignore (no implemented bits).
                    when CSR_MSTATUSH =>
                        null;

                    when CSR_MTVEC =>
                        -- MODE(1:0) is WARL {00} (direct only) — never stored.
                        if ENABLE_TRAPCSR then
                            mtvec_base <= csr_new_val(31 downto 2);
                        end if;

                    when CSR_MIE =>
                        if ENABLE_TRAPCSR then
                            mie_msie <= csr_new_val(3);
                            mie_mtie <= csr_new_val(7);
                            mie_meie <= csr_new_val(11);
                        end if;

                    -- mip: read-only mirror of the level wires — writes ignored.
                    when CSR_MIP =>
                        null;

                    when CSR_MSCRATCH =>
                        if ENABLE_TRAPCSR then
                            mscratch <= csr_new_val;
                        end if;

                    when CSR_MEPC =>
                        -- bit0 is not stored (hardwired '0'); bit1 is writable
                        -- only on a C build (a no-C hart cannot have a
                        -- 2-byte-aligned PC, so bit1 is WARL 0 there).
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

                    when others =>
                        null;  -- Read-only CSRs, user-view aliases, or hardwired-zero hpm indices
                end case;
            end if;

            -- ==============================================================
            -- P1 trap-entry / MRET hardware writeback (p0_specs.md 2.3/2.4).
            -- ASSIGNED AFTER the csr_write_en case ON PURPOSE: a later
            -- assignment in the same process wins, so these strobes take
            -- PRECEDENCE over a same-cycle CSR write. They cannot in fact
            -- coincide BY CONSTRUCTION — trap_entry_we is driven only from
            -- MTRAP_SV and mret_we only from the MRET arm, dedicated FSM
            -- states in which no CSR instruction retires (freeze rule (a)) —
            -- but the ordering is defined anyway so it can never become a
            -- silent hazard. The whole block prunes when ENABLE_TRAPCSR is
            -- false (constant-false condition, ports tied inert).
            -- ==============================================================
            if ENABLE_TRAPCSR then
                if trap_entry_we = '1' then
                    -- mepc <= faulting/resume PC (same WARL mask as a software
                    -- write: bit0 dropped, bit1 only on a C build).
                    mepc_r(31 downto 2) <= trap_pc(31 downto 2);
                    if ENABLE_COMPRESSED then
                        mepc_r(1) <= trap_pc(1);
                    else
                        mepc_r(1) <= '0';
                    end if;
                    mcause_int  <= trap_cause(31);
                    mcause_code <= trap_cause(3 downto 0);
                    mtval_r     <= trap_value;
                    -- mstatus stack PUSH: MPIE <= MIE, MIE <= 0.
                    mst_mpie    <= mst_mie;
                    mst_mie     <= '0';
                    -- P2 PRIVILEGE PUSH, riding the SAME strobe: MPP <= the
                    -- interrupted privilege, then priv <= M. Traps ALWAYS
                    -- deliver to M -- there is no delegation (medeleg/mideleg
                    -- stay illegal CSRs, correct for an M/U-only core).
                    -- Without ENABLE_UMODE, MPP is already pinned to M and priv
                    -- never leaves '1', so this block is pure P2 cost.
                    if ENABLE_UMODE then
                        mst_mpp <= priv_m & priv_m;   -- '1'->"11" (M), '0'->"00" (U)
                        priv_m  <= '1';
                    end if;
                elsif mret_we = '1' then
                    -- mstatus stack POP: MIE <= MPIE, MPIE <= 1.
                    mst_mie  <= mst_mpie;
                    mst_mpie <= '1';
                    -- P2 PRIVILEGE POP, riding the SAME strobe: priv <= MPP,
                    -- THEN MPP <= "00" (U, the least-privileged supported mode
                    -- -- spec-required so a second MRET cannot re-escalate; the
                    -- p2_mppstuck negative control drops exactly this line).
                    -- MPP is WARL {00,11}, so MPP_M is the only M encoding.
                    if ENABLE_UMODE then
                        if mst_mpp = MPP_M then
                            priv_m <= '1';
                        else
                            priv_m <= '0';
                        end if;
                        mst_mpp <= MPP_U;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Output read data
    csr_read_data <= csr_read_val;

    -- X3 Zcmt: export the jvt base (held zero when ENABLE_ZCMT is off).
    jvt_value <= jvt;

    -- X4 Zfinx: export the rounding mode + its validity. A dynamic-rm (rm=111)
    -- instruction is legal only when frm is a valid mode (000..100); 101/110/111
    -- in frm are reserved/invalid. When ENABLE_ZFINX is off fp_csr=0 so
    -- frm_value="000"/frm_valid='1' (harmless — no FP op decodes anyway).
    frm_value <= fp_csr(7 downto 5);
    frm_valid <= '0' when (fp_csr(7 downto 5) = "101" or fp_csr(7 downto 5) = "110" or
                           fp_csr(7 downto 5) = "111") else '1';

    -- ----------------------------------------------------------------------
    -- P1 trap-CSR exports (p0_specs.md 2.4). csr_unit exports STATE only —
    -- the interrupt-take decision (`mstatus_mie and ((meip and MEIE) or
    -- (msip and MSIE) or (mtip and MTIE))`, priority MEI > MSI > MTI) is
    -- vesta's, never this file's.
    -- With ENABLE_TRAPCSR false every export is its reset value: mtvec/mepc
    -- zero, MIE low, mie_bits "000" — and legacy_mode '1', which is what makes
    -- vesta's delivery muxes constant-fold to the legacy IVT path.
    -- ----------------------------------------------------------------------
    mtvec_value <= mtvec_base & "00";   -- MODE is WARL "00" (direct)
    mepc_value  <= mepc_r & '0';        -- bit0 always '0'
    mstatus_mie <= mst_mie;
    mie_bits    <= mie_meie & mie_mtie & mie_msie;  -- {MEIE, MTIE, MSIE}
    legacy_mode <= mtrapctl_legacy;

    -- ----------------------------------------------------------------------
    -- P2 U-mode exports (p0_specs.md 3.1). All three are STATE, never policy:
    -- the U-mode decode gate lives in maindec and the ECALL cause mux in vesta.
    -- With ENABLE_UMODE false these are the reset constants for all time --
    -- priv_mode '1' (M), status_tw '0', mcounteren_bits "00000" -- exactly the
    -- inert defaults maindec declares, so the U-mode decode logic constant-folds
    -- away on a non-U build.
    -- ----------------------------------------------------------------------
    priv_mode       <= priv_m;
    status_tw       <= mst_tw;
    mcounteren_bits <= mcounteren_r;

end behave;
