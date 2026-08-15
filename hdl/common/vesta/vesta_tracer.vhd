-- =============================================================================
-- vesta_tracer.vhd, V1 of the Spike lockstep co-simulation program.
--
-- A PURE OBSERVER. It has NO output ports, drives NO signal, and its only side effect is an ASCII text file.
-- Instantiated in vesta.vhd inside `gen_trace: if TRACE_ENABLE generate`, so an OFF build elaborates none of it.
--
-- Spec: ~/vesta_docs/lockstep/v1_retire_enumeration.md rev 2, the retire-event enumeration.
--       Section 3-R0 of it is implemented verbatim below.
-- Wire format: ~/vestarv/tools/cosim/RECORD_FORMAT.md plus Amendments A1-A7.
--       A6 (V3): an `M L` record's data field carries the RETURNED BUS WORD (it was a hardcoded zero through V2).
--                Back-filled one clk_cpu edge after the issue; see the A6 block in the process.
--       A7 (V3): the legacy IRQ_SV return-PC push and the iret stack pop LEAVE the compared stream (# IRQPUSH / # IRETPOP).
--                Each is bounded by an equality so a wrong address is loud, not invisible.
--       A10 (WT): BIT-GRANULAR x. The compared fields are UNCHANGED: `hexstr` is still nibble-granular and every width is frozen.
--                A tainted compared field now additionally emits `# XBITS <hart> <cycle> <field> <mask> <defined>` on the line BELOW its record.
--                `mask` is 1 at each undriven bit; `defined` is the value with those bits forced to 0.
--                A clean trace is byte-identical to a pre-A10 one.
--       A16 (WT, finding T2): a GLOBALLY-failed sc.w no longer emits an `M ... S`.
--                It never committed, because resv_unit gates the write off downstream, so the record contradicted section 2's definition of `M`.
--                It is now `# SCGHOST`, which retires the SHAPE that compare.py's amendment A15 existed to filter.
--                A15 stays as a compatibility shim for pre-A16 traces.
--       A17 (K2b, finding F-K2b-1): the Zfinx `C 001` record is emitted on ANY retire whose `fp_flags_we` is asserted, not only on ST_FPU_DONE.
--                It carries the POST-op value `fflags_value or fp_flags_val`, not the pre-op CSR register.
--                Both halves are corrections of a record that violated section 3.
--                The old emission described the state BEFORE the op it belonged to.
--                Single-cycle FP ops (fmin/fmax/fsgnj/fcmp/fclass, which retire in EXECUTE) emitted no record at all even when they raised NV.
--                Statically inert in a zfinx-off build.
--
-- INVARIANTS THIS FILE MUST HOLD (kickoff section 3):
--   1. -V200X. No VHDL-2008: no external names, no to_hstring, no 2008 aggregates.
--      Hex is hand-rolled below. std.textio only.
--   7. It logs what COMMITTED, not what decode intended.
--      Every value arrives from the actual write PORT (regfile we3/a3/wd3, the sp port, the memory interface, csr_unit's committed-write export).
--      Sampling is pre-edge on rising_edge(clk_cpu), i.e. exactly the values the flops capture on that same edge.
--   3b. It never drives or muxes anything on the memory path.
--
-- THE STATE-ORDINAL CONTRACT (read this before touching `type cpu_state`):
--   `cpu_state` is declared inside vesta's architecture, so it cannot cross a port boundary in VHDL-93.
--   vesta therefore passes `cpu_state'pos(...)` and the ST_* constants below MUST match the DECLARATION ORDER of that type.
--   If you add, remove or REORDER a state you MUST update the ST_* block here.
--   A mismatch is silent. The tracer prints the raw ordinal in every diagnostic line so a mismatch is at least visible.
--   FIND IT WITH `grep -n "type cpu_state" vesta.vhd`, NOT with a line number.
--   This comment used to say ":425-493", which was already stale by two waves: the declaration was at :509-577 when A17 re-checked the contract, and the old range now lands inside this component's own port list.
--   Method rule section 3, first line: a wrong reference is worse than none.
-- =============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use std.textio.all;
library work;
use work.constants.all;

entity vesta_tracer is
    generic (
        -- Base name of the trace file, giving <TRACE_FILE>_h<xx>.trace.
        -- The hart suffix is appended at runtime because a generic cannot depend on the hart_id PORT.
        TRACE_FILE        : string  := "vesta_trace";
        -- Statically-known feature knobs, mirrored from vesta so the section 3-R0 exclusion terms fold exactly as the FSM's do.
        ENABLE_PMP        : boolean := false;
        ENABLE_COMPRESSED : boolean := true;
        -- Rate limit for the unbounded #TRAPSTORE diagnostic (finding F8: TRAP_STATE self-loops forever and can commit a store every cycle).
        TRAPSTORE_LIMIT   : natural := 8;
        -- D1 (R-D0-3(1)): THE ORDINAL-COUNT TRIPWIRE.
        -- vesta passes `cpu_state'pos(cpu_state'high) + 1` here, and the concurrent assert at the end of this architecture compares it against ST_COUNT and FAILS AT ELABORATION on a mismatch.
        -- Until D1 the contract below had ZERO mechanical enforcement: ST_COUNT was declared and never read, so the constant that LOOKS like a tripwire was not one.
        -- DEFAULT 0 IS THE FAIL-SAFE DIRECTION, not an "unspecified" sentinel.
        -- An instantiation that forgets this generic fails the assert loudly rather than silently opting out of the check.
        STATE_COUNT       : natural := 0
    );
    port (
        -- ---------------------------------------------------------------------
        -- EVERY PORT IS `in`. There is deliberately no output of any kind.
        -- ---------------------------------------------------------------------
        clk_cpu          : in std_logic;                       -- the GATED core clock
        resetn           : in std_logic;
        hart_id          : in std_logic_vector(XLEN-1 downto 0);

        -- FSM state as an ordinal (see THE STATE-ORDINAL CONTRACT above).
        state            : in natural;                         -- cpu_state'pos(current_state)
        next_state       : in natural;                         -- cpu_state'pos(next_state)

        -- PC, the raw instruction bus, and the four dispatch-shape selectors.
        pc               : in std_logic_vector(XLEN-1 downto 0);
        instr            : in std_logic_vector(ILEN-1 downto 0);  -- the read_data bus itself (vesta:951)
        instr_curr       : in std_logic_vector(ILEN-1 downto 0);  -- decoded/held (vesta:1328)
        instr_lower_half : in std_logic_vector(15 downto 0);
        quadrant_upper   : in std_logic_vector(1 downto 0);
        quadrant_lower   : in std_logic_vector(1 downto 0);
        repeat_if        : in std_logic;

        -- Committed regfile MAIN write port (datapath: we3 / a3 / wd3).
        reg_write        : in std_logic;                        -- reg_write_dp drives we3
        rd_addr          : in std_logic_vector(4 downto 0);     -- rf_a3_addr drives a3
        rd_data          : in std_logic_vector(XLEN-1 downto 0); -- Result drives wd3

        -- Committed regfile SECOND (sp) write port.
        sp_write_en      : in std_logic;
        sp_write_data    : in std_logic_vector(XLEN-1 downto 0);
        stack_pointer    : in std_logic_vector(XLEN-1 downto 0);

        -- Memory interface: the vesta boundary ports themselves.
        data_addr        : in std_logic_vector(XLEN-1 downto 0);
        wen              : in std_logic_vector(XLEN_BYTES-1 downto 0);  -- ACTIVE LOW per byte
        write_data       : in std_logic_vector(XLEN-1 downto 0);
        mem_access_instr : in std_logic;
        funct3           : in std_logic_vector(2 downto 0);     -- instr_curr(14 downto 12)

        -- A16 (finding T2): the GLOBAL SC verdict from resv_unit.
        -- In SC_CHECK the core drives `wen` on its LOCAL check alone, so the port shows a store for a write that resv_unit's `s_we_gated` then suppresses.
        -- This is the one input the tracer needs to tell a presentation from a commit.
        -- Sampling it HERE is sound and needs no holding mechanism: vesta.vhd:92-95 contracts it stable by the end of the SC_CHECK cycle (latched from the arbiter done for a stalled shared SC).
        -- The core itself consumes it combinationally in that same cycle to pick `amo_phase` "101"/"100" (vesta.vhd:1930-1933), and the edge this process samples IS the end of that cycle.
        -- DEFAULT '0' is the FAIL-SAFE direction (R-W4-12): an unwired instantiation reports "no external failure" and therefore behaves EXACTLY as the pre-A16 tracer did, dropping nothing.
        -- The opposite default would silently delete every shared SC's store record.
        sc_fail_ext      : in std_logic := '0';

        -- csr_unit's COMMITTED-write export, generated inside csr_unit and asserted only when a write `case` arm actually stores (R4/F10).
        csr_addr         : in std_logic_vector(11 downto 0);
        csr_commit_we    : in std_logic;
        csr_commit_val   : in std_logic_vector(XLEN-1 downto 0);
        mstatus_value    : in std_logic_vector(XLEN-1 downto 0); -- for MTRAP_RET's mret pop
        -- A17 (F-K2b-1). `fflags_value` is csr_unit's fflags REGISTER, i.e. the value BEFORE this edge's sticky OR commits (csr_unit.vhd:670-671 and :1205).
        -- On its own it therefore describes the state before the op that owns the record.
        -- The post-op value is `fflags_value or fp_flags_val`.
        -- `fp_flags_we` is the strobe that says an FP op is committing flags on THIS edge (vesta.vhd's `fp_flags_we`, both arms: FPU_DONE for the multi-cycle ops and EXECUTE for the single-cycle ones).
        fflags_value     : in std_logic_vector(XLEN-1 downto 0); -- fflags PRE-edge
        -- DEFAULTS, AND WHY THIS DIRECTION (method rule 15 / R-W4-12).
        -- An unwired instantiation gets `fp_flags_we = '0'` and emits NO `C 001` at all.
        -- That is NOT "behaves like the pre-A17 tracer" and is not claimed to be: it is the LOUD direction.
        -- A missing `C 001` on a Zfinx build is an immediate record-KIND divergence at the first flag-raising op (the reference presents `c1_fflags` there and the RTL presents nothing), while on a zfinx-off build it is exactly correct.
        -- The opposite default ('1') would fabricate a `C 001` on EVERY retire of EVERY build, destroying traces that are otherwise sound.
        -- Neither default can produce the F-K2b-1 shape, a plausible-looking record carrying the wrong value, which is the failure mode that cost a wave to find.
        fp_flags_we      : in std_logic := '0';
        fp_flags_val     : in std_logic_vector(4 downto 0) := (others => '0');

        -- Decode class, for the section 3-R0 EXECUTE exclusions.
        trap             : in std_logic;
        ecall_op         : in std_logic;
        ebreak_op        : in std_logic;
        mret_op          : in std_logic;
        isr_ret          : in std_logic;
        pmp_f_deny_r     : in std_logic;
        pmp_d_deny       : in std_logic;

        -- Trap-record sources.
        trap_pc_val      : in std_logic_vector(XLEN-1 downto 0);  -- MTRAP_SV mepc
        trap_cause_val   : in std_logic_vector(XLEN-1 downto 0);  -- MTRAP_SV mcause
        trap_value_val   : in std_logic_vector(XLEN-1 downto 0);  -- MTRAP_SV mtval
        mtrap_disp_int   : in std_logic;                          -- dispatch-cycle classification
        mtrap_disp_code  : in std_logic_vector(3 downto 0);
        ivt_entry        : in std_logic_vector(XLEN-1 downto 0)   -- legacy vector taken
    );
end entity vesta_tracer;

architecture behav of vesta_tracer is

    -- ==========================================================
    -- cpu_state ordinals: MUST match the declaration order of vesta.vhd's `type cpu_state`.
    -- ==========================================================
    constant ST_INITIALIZE    : natural :=  0;
    constant ST_SLEEPING      : natural :=  1;
    constant ST_EXECUTE       : natural :=  2;
    constant ST_MEMORY_WAIT   : natural :=  3;
    constant ST_DIV_WAIT      : natural :=  4;
    constant ST_DIV_DONE      : natural :=  5;
    constant ST_FPU_FETCH3    : natural :=  6;
    constant ST_FPU_WAIT      : natural :=  7;
    constant ST_FPU_DONE      : natural :=  8;
    constant ST_IRQ_SV        : natural :=  9;
    constant ST_IRQ_REST      : natural := 10;
    constant ST_IRQ_JUMP      : natural := 11;
    constant ST_TRAP_STATE    : natural := 12;
    constant ST_MTRAP_SV      : natural := 13;
    constant ST_MTRAP_JUMP    : natural := 14;
    constant ST_MTRAP_RET     : natural := 15;
    constant ST_AMO_READ      : natural := 16;
    constant ST_AMO_WRITEBACK : natural := 17;
    constant ST_AMO_COMPUTE   : natural := 18;
    constant ST_AMO_WRITE     : natural := 19;
    constant ST_AMO_COMPLETE  : natural := 20;
    constant ST_LR_READ       : natural := 21;
    constant ST_SC_CHECK      : natural := 22;
    constant ST_FENCE_WAIT    : natural := 23;
    constant ST_PAUSE_WAIT    : natural := 24;
    constant ST_WRS_WAIT      : natural := 25;
    constant ST_CBOZ_WRITE    : natural := 26;
    constant ST_CBOZ_GAP      : natural := 27;
    constant ST_ZCM_PUSH_ST   : natural := 28;
    constant ST_ZCM_PUSH_GAP  : natural := 29;
    constant ST_ZCM_POP_LD    : natural := 30;
    constant ST_ZCM_POP_WB    : natural := 31;
    constant ST_ZCM_A0Z       : natural := 32;
    constant ST_ZCM_SP_COMMIT : natural := 33;
    constant ST_ZCM_RET       : natural := 34;
    constant ST_ZCM_MV1       : natural := 35;
    constant ST_ZCM_MV2       : natural := 36;
    constant ST_ZCM_JT_LD     : natural := 37;
    constant ST_ZCM_JT_WB     : natural := 38;
    -- D1 debug-mode states, TAIL-APPENDED exactly as they are in vesta.vhd.
    constant ST_DBG_SV        : natural := 39;
    constant ST_DBG_JUMP      : natural := 40;
    constant ST_DBG_RET       : natural := 41;
    constant ST_COUNT         : natural := 42;

    -- Buffer depths.
    -- A Zcmp cm.pop commits up to 13 rd writes plus 1 sp write for ONE architectural instruction, and a cbo.zero commits CBOZ_WORDS stores.
    -- Both are flushed as one retire (Amendment A2, spec sections 6.5 and 6.6).
    constant MAX_RD  : natural := 16;
    constant MAX_MEM : natural := 24;

    -- Nibble alphabet for the hand-rolled hex printers below.
    constant HEXCHARS : string(1 to 16) := "0123456789abcdef";

    -- ==========================================================
    -- Hand-rolled hex (invariant 1: no to_hstring, no VHDL-2008).
    -- ==========================================================
    -- Any bit that is not '0' or '1' makes its whole nibble print as 'x', so an X-corrupted value is visible in the trace instead of crashing the run.
    function hexstr(v : std_logic_vector) return string is
        constant ND     : natural := (v'length + 3) / 4;
        variable padded : std_logic_vector(ND*4-1 downto 0);
        variable s      : string(1 to ND);
        variable d      : integer;
        variable bad    : boolean;
    begin
        padded := (others => '0');
        padded(v'length-1 downto 0) := v;
        for i in 0 to ND-1 loop
            d   := 0;
            bad := false;
            for j in 0 to 3 loop
                if padded(i*4+j) = '1' then
                    d := d + 2**j;
                elsif padded(i*4+j) /= '0' then
                    bad := true;
                end if;
            end loop;
            if bad then
                -- RECORD_FORMAT Amendment A5: a literal 'x' nibble means the sampled RTL state carried an X at that position.
                -- We never invent a value; the comparator treats any record containing 'x' as INVESTIGATE, never as a match.
                s(ND-i) := 'x';
            else
                s(ND-i) := HEXCHARS(d+1);
            end if;
        end loop;
        return s;
    end function hexstr;

    -- ==========================================================
    -- A10 (WT): BIT-GRANULAR x.
    -- `hexstr` above is NIBBLE-granular by design and STAYS THAT WAY, so the compared field keeps its frozen width and its meaning and every existing consumer is untouched.
    -- What A5 could not say is WHICH BITS were undriven, and that is the whole of A10.
    -- The three functions below let the tracer emit a companion `# XBITS` line carrying the exact undriven-bit MASK and the exact DEFINED bits, alongside the record and never instead of it.
    --
    -- Why the extra line rather than a wider field: a `000000xx` data field says eight bits MIGHT be undriven.
    -- It does not say that seven are and one is a defined '0' that the program then branches on, which is exactly `rv32ui-p-afsel`'s shape and exactly why it is uninjectable.
    -- True when any bit of v is neither '0' nor '1'.
    function has_x(v : std_logic_vector) return boolean is
        variable a : std_logic_vector(v'length-1 downto 0);
    begin
        a := v;
        for i in 0 to v'length-1 loop
            if a(i) /= '0' and a(i) /= '1' then
                return true;
            end if;
        end loop;
        return false;
    end function has_x;

    -- 1 at every position `hexstr` would have had to call `x`.
    function x_mask_of(v : std_logic_vector) return std_logic_vector is
        variable a : std_logic_vector(v'length-1 downto 0);
        variable r : std_logic_vector(v'length-1 downto 0);
    begin
        a := v;
        for i in 0 to v'length-1 loop
            if a(i) = '0' or a(i) = '1' then r(i) := '0'; else r(i) := '1'; end if;
        end loop;
        return r;
    end function x_mask_of;

    -- The value with every undriven bit forced to '0'.
    -- This is NOT an invented value and must never be read as one: it is only meaningful UNDER the mask.
    -- The mask is emitted beside it precisely so a consumer cannot use one without the other.
    function x_def_of(v : std_logic_vector) return std_logic_vector is
        variable a : std_logic_vector(v'length-1 downto 0);
        variable r : std_logic_vector(v'length-1 downto 0);
    begin
        a := v;
        for i in 0 to v'length-1 loop
            if a(i) = '1' then r(i) := '1'; else r(i) := '0'; end if;
        end loop;
        return r;
    end function x_def_of;

    -- Fixed-width hex of a natural: the cycle field, and the state ordinals in diagnostics.
    -- Truncates from the top if nd is too small, which is fine because the cycle field is debug-only and NEVER compared (RECORD_FORMAT section 0).
    function hexnat(n : natural; nd : natural) return string is
        variable s : string(1 to nd);
        variable t : natural;
    begin
        t := n;
        for i in 0 to nd-1 loop
            s(nd-i) := HEXCHARS((t mod 16) + 1);
            t := t / 16;
        end loop;
        return s;
    end function hexnat;

    -- Decimal image of a natural (integer'image is VHDL-87 and legal here).
    function natstr(n : natural) return string is
    begin
        return integer'image(n);
    end function natstr;

    -- "<hart> <cycle> ", the two leading fields every record shares.
    -- IMPURE because it reads the hart_id SIGNAL: a VHDL-93 pure function may not reference a signal or a variable from an enclosing declarative region.
    -- `impure function` is itself VHDL-93 (LRM 93 section 2.1), so this is the correct and portable spelling, not merely what the tool tolerates.
    -- The cycle is taken as a PARAMETER rather than read from the process variable, which keeps the signal read as the ONLY impurity.
    impure function hdr(c : natural) return string is
    begin
        return hexstr(hart_id(7 downto 0)) & " " & hexnat(c, 8) & " ";
    end function hdr;

    -- mcause bits 30:4 are hardwired 0 (csr_unit stores only bit31 + code(3:0)).
    constant RSVD27 : std_logic_vector(26 downto 0) := (others => '0');

    -- Buffer types for the per-retire record groups.
    type word_arr  is array (natural range <>) of std_logic_vector(XLEN-1 downto 0);
    type addr5_arr is array (natural range <>) of std_logic_vector(4 downto 0);
    type nat_arr   is array (natural range <>) of natural;
    type bool_arr  is array (natural range <>) of boolean;

begin

    -- =====================================================================
    -- The one and only process, sampled on rising_edge(clk_cpu).
    -- The values read here are the PRE-EDGE values, i.e. exactly what the regfile, RAM and sequencer flops capture on this same edge (invariant 7).
    -- =====================================================================
    trace_proc: process(clk_cpu)
        file     f            : text;
        variable fopened      : boolean := false;
        variable cyc          : natural := 0;
        variable hstr         : string(1 to 2);
        -- In-flight architectural instruction (spec section 3-I1, "latch, don't re-read").
        variable iv_valid     : boolean := false;
        variable iv_pc        : std_logic_vector(XLEN-1 downto 0);
        variable iv_insn      : std_logic_vector(ILEN-1 downto 0);
        variable iv_c16       : boolean := false;
        -- Committed register writes for the in-flight instruction (A2: n R records).
        variable rd_n         : natural := 0;
        variable rd_a         : addr5_arr(0 to MAX_RD-1);
        variable rd_v         : word_arr(0 to MAX_RD-1);
        -- Committed memory transactions for the in-flight instruction.
        variable mm_n         : natural := 0;
        variable mm_st        : bool_arr(0 to MAX_MEM-1);
        variable mm_ad        : word_arr(0 to MAX_MEM-1);
        variable mm_da        : word_arr(0 to MAX_MEM-1);
        variable mm_sz        : nat_arr(0 to MAX_MEM-1);
        -- The address the S1/S2 suppressions are bounded against (A3).
        variable cap_addr     : std_logic_vector(XLEN-1 downto 0);
        variable cap_vld      : boolean := false;
        -- A6: the returned load word is not on the bus at the ISSUE edge; it arrives one clk_cpu edge later, on the edge where the core itself consumes it.
        -- fl_pend and fl_idx back-fill the buffered L record's data field, which before A6 was a hardcoded zero.
        variable fl_pend      : boolean := false;
        variable fl_idx       : natural := 0;
        -- Pending explicit CSR write (A1).
        variable csr_p        : boolean := false;
        variable csr_pa       : std_logic_vector(11 downto 0);
        variable csr_pv       : std_logic_vector(XLEN-1 downto 0);
        -- Legacy trap entry: captured at IRQ_SV, emitted at IRQ_JUMP (spec section 3-T1).
        variable t_pend       : boolean := false;
        variable t_epc        : std_logic_vector(XLEN-1 downto 0);
        -- Miscellaneous one-shots and counters.
        variable wfi_armed    : boolean := false;   -- R5: trc_wfi_armed
        variable ts_count     : natural := 0;       -- F8 rate limit
        variable init_seen    : boolean := false;   -- R6 probe one-shot
        -- Per-edge combinational scratch.
        variable sP, sQ, sE, sD, sC, sA, sB : boolean;
        variable is_disp, ret_exec, retire  : boolean;
        variable is_load, is_store, own     : boolean;
        variable sz, lo, k                  : natural;
        variable dat                        : std_logic_vector(XLEN-1 downto 0);
        -- A17: the POST-op fflags word, i.e. fflags_value with its low 5 bits OR'd with the completing op's flags.
        -- Held in a variable rather than written as an expression twice, so the record and its `# XBITS` companion can never drift apart and an `x` in either operand propagates to both.
        variable ffpost                     : std_logic_vector(XLEN-1 downto 0);

        -- Write one finished record line to the trace file.
        procedure emit(s : string) is
            variable ll : line;
        begin
            write(ll, s);
            writeline(f, ll);
        end procedure emit;

        -- A10: the companion line for ONE tainted field of the record on the line immediately above.
        -- Emitted only when the field is actually tainted, so a clean trace is byte-identical to a pre-A10 one.
        -- BINDS BACKWARD, like `# NODATA` and unlike `# SCFAILRD` and `# SCGHOST`, which are written at their event edge, before the retire flush.
        -- The two conventions coexist in this file already; the discriminator is simply where the emit sits.
        -- A10's sits INSIDE the record procedures so the adjacency cannot be broken by a later edit.
        --   # XBITS <hart> <cycle> <field> <mask> <defined>
        -- `mask` is 1 at every undriven bit; `defined` is the value with those bits forced to 0.
        -- Both are the SAME WIDTH as the field they describe.
        procedure emit_xbits(fld : string; v : std_logic_vector) is
        begin
            if has_x(v) then
                emit("# XBITS " & hdr(cyc) & fld & " "
                     & hexstr(x_mask_of(v)) & " " & hexstr(x_def_of(v)));
            end if;
        end procedure emit_xbits;

        -- One `R` record for the in-flight instruction, narrowed to 16 bits when it was compressed.
        procedure emit_r(a : std_logic_vector(4 downto 0);
                         v : std_logic_vector(XLEN-1 downto 0)) is
        begin
            if iv_c16 then
                emit("R " & hdr(cyc) & hexstr(iv_pc) & " " & hexstr(iv_insn(15 downto 0))
                     & " " & hexstr(a) & " " & hexstr(v));
                emit_xbits("insn", iv_insn(15 downto 0));
            else
                emit("R " & hdr(cyc) & hexstr(iv_pc) & " " & hexstr(iv_insn)
                     & " " & hexstr(a) & " " & hexstr(v));
                emit_xbits("insn", iv_insn);
            end if;
            emit_xbits("pc",    iv_pc);
            emit_xbits("rd",    a);
            emit_xbits("rdval", v);
        end procedure emit_r;

        -- One `M` record: st selects the store ("S") or load ("L") form.
        procedure emit_m(st : boolean; ad : std_logic_vector(XLEN-1 downto 0);
                         n : natural; dt : std_logic_vector(XLEN-1 downto 0)) is
            variable c : string(1 to 1);
        begin
            if st then c := "S"; else c := "L"; end if;
            emit("M " & hdr(cyc) & c & " " & hexstr(ad) & " " & hexnat(n, 1) & " " & hexstr(dt));
            emit_xbits("addr", ad);
            emit_xbits("data", dt);
        end procedure emit_m;

        -- Buffer one memory transaction until the owning instruction retires; overflow is reported, never silently dropped.
        procedure push_mem(st : boolean; ad : std_logic_vector(XLEN-1 downto 0);
                           n : natural; dt : std_logic_vector(XLEN-1 downto 0)) is
        begin
            if mm_n < MAX_MEM then
                -- A6: arm the one-edge-late data back-fill for a LOAD.
                -- Single point of arming, so no push site can forget it.
                if not st then
                    fl_pend := true;
                    fl_idx  := mm_n;
                end if;
                mm_st(mm_n) := st; mm_ad(mm_n) := ad;
                mm_sz(mm_n) := n;  mm_da(mm_n) := dt;
                mm_n := mm_n + 1;
            else
                emit("# BUFOVF " & hdr(cyc) & "mem");
            end if;
        end procedure push_mem;

        -- Emit every buffered M in the mandated order: all L, then all S.
        procedure flush_mem is
        begin
            for i in 0 to mm_n-1 loop
                if not mm_st(i) then emit_m(false, mm_ad(i), mm_sz(i), mm_da(i)); end if;
            end loop;
            for i in 0 to mm_n-1 loop
                if mm_st(i) then emit_m(true, mm_ad(i), mm_sz(i), mm_da(i)); end if;
            end loop;
            mm_n := 0;
        end procedure flush_mem;

        -- Drop the in-flight instruction and every buffer that belonged to it.
        procedure clear_inflight is
        begin
            iv_valid := false; rd_n := 0; mm_n := 0;
            csr_p := false; cap_vld := false;
        end procedure clear_inflight;
    begin
        if rising_edge(clk_cpu) then

            -- Lazy open plus the MANDATORY provenance header.
            -- Stale-snapshot trap: if this line is missing from the trace, the OFF snapshot ran.
            if not fopened then
                hstr := hexstr(hart_id(7 downto 0));
                file_open(f, TRACE_FILE & "_h" & hstr & ".trace", write_mode);
                fopened := true;
                emit("# vesta_tracer TRACE_ENABLE=true " & TRACE_FILE & " hart=" & hstr);
                -- The format list is the CONSUMER'S vintage signal.
                -- compare.py and mk_inject must be able to tell a pre-A16 trace, which still carries failed-SC ghost stores filtered by A15, from a post-A16 one, which does not.
                -- Bump it whenever an amendment changes what this file emits.
                emit("# spec v1_retire_enumeration.md rev2 ; format RECORD_FORMAT.md A1-A7,A10,A16,A17");
            end if;

            if resetn = '1' then
                -- ---------- Section 3-I1 dispatch shapes, mutually exclusive, P and Q evaluated first.
                sP := ENABLE_PMP and pmp_f_deny_r = '1';                            -- :2051
                sQ := (not ENABLE_COMPRESSED) and pc(1) = '1';                      -- :2078
                sE := (pc(1) = '1') and (quadrant_upper =  "11") and repeat_if = '0'; -- :2301
                sD := (pc(1) = '1') and repeat_if = '1';                            -- :2096
                sC := (pc(1) = '1') and (quadrant_upper /= "11") and repeat_if = '0'; -- :2310
                sA := (pc(1) = '0') and (quadrant_lower =  "11");                    -- :2416
                sB := (pc(1) = '0') and (quadrant_lower /= "11");                    -- :2576
                is_disp := (state = ST_EXECUTE) and (not sP) and (not sQ) and (not sE);

                -- ---------- Section 3-R0 retire condition, implemented verbatim.
                ret_exec := is_disp
                            and trap = '0' and ecall_op = '0' and ebreak_op = '0'
                            and mret_op = '0'
                            and not (ENABLE_PMP and pmp_d_deny = '1')
                            -- D1: DBG_SV joins the whitelist, mirroring vesta.vhd's retire_now.
                            -- A halt or step divert out of EXECUTE withdraws only pc_en, so the diverted instruction still retires, and for single-step that retire IS the step.
                            -- THE TWO COPIES OF THIS CONDITION DIFFER ON PURPOSE ELSEWHERE (the MEMORY_WAIT isr_ret term below).
                            -- This addition is NOT one of the deliberate differences, and a mismatch here would be as silent as an ordinal one.
                            and (next_state = ST_EXECUTE  or next_state = ST_IRQ_SV or
                                 next_state = ST_MTRAP_SV or next_state = ST_FENCE_WAIT or
                                 next_state = ST_DBG_SV);
                retire := ret_exec
                       or (state = ST_MEMORY_WAIT and isr_ret = '0')
                       or (state = ST_SLEEPING and next_state /= ST_SLEEPING and wfi_armed)
                       or state = ST_DIV_DONE  or state = ST_FPU_DONE
                       or state = ST_LR_READ   or state = ST_SC_CHECK
                       or state = ST_AMO_WRITE or state = ST_MTRAP_RET
                       -- D1: DRET retires, beside MRET and for the same reason.
                       -- Unlike `iret` it is a STANDARD encoding the reference knows, so the retire is comparable.
                       or state = ST_DBG_RET
                       or state = ST_ZCM_RET   or state = ST_ZCM_JT_WB
                       or (state = ST_PAUSE_WAIT and next_state = ST_EXECUTE)
                       or (state = ST_WRS_WAIT  and next_state = ST_EXECUTE);

                -- ---------- A6: back-fill the load data issued on the PREVIOUS edge.
                -- `instr` IS the unified read bus (vesta.vhd:1052 assigns it from read_data), and THIS edge is the one on which the core itself consumes it.
                -- Every load-issuing state is followed by its consuming state after exactly ONE clk_cpu edge, and the core's own capture of the same signal proves the timing per case:
                --   EXECUTE then MEMORY_WAIT     datapath's Result takes read_data; the tracer's own retire condition makes MEMORY_WAIT unable to self-loop
                --   EXECUTE then AMO_READ        vesta.vhd:1152/1154 amo_read_data
                --   EXECUTE then LR_READ         retires here, rd takes read_data
                --   ZCM_POP_LD then ZCM_POP_WB, ZCM_JT_LD then ZCM_JT_WB   vesta.vhd:1240
                -- A multi-cycle memory is invisible here: the stall is implemented by GATING clk_cpu, so there is no multi-edge wait to track.
                -- A fill that cannot land, because a sequencer abort flushed the buffer first, is LOUD, never silently zero.
                if fl_pend then
                    if fl_idx < mm_n and not mm_st(fl_idx) then
                        mm_da(fl_idx) := instr;
                    else
                        emit("# NODATA " & hdr(cyc) & "fill-lost idx " & natstr(fl_idx));
                    end if;
                    fl_pend := false;
                end if;

                -- ---------- Capture the architectural instruction at dispatch.
                if is_disp then
                    clear_inflight;
                    iv_valid := true;
                    iv_pc    := pc;
                    if sD then          -- 32-bit instruction split across two fetches, upper half held in instr_lower_half
                        iv_insn := instr(15 downto 0) & instr_lower_half;  -- :1313-1314
                        iv_c16  := false;
                    elsif sA then       -- aligned 32-bit instruction
                        iv_insn := instr;
                        iv_c16  := false;
                    elsif sC then       -- compressed instruction in the upper half of the fetched word
                        iv_insn := x"0000" & instr(31 downto 16);
                        iv_c16  := true;
                    else                                                  -- sB: compressed instruction in the lower half
                        iv_insn := x"0000" & instr(15 downto 0);
                        iv_c16  := true;
                    end if;
                end if;

                -- ---------- R5: arm the WFI one-shot on the real dispatch only.
                if state = ST_EXECUTE and next_state = ST_SLEEPING then
                    wfi_armed := true;
                end if;

                -- ---------- Committed register writes (regfile_sbirq.vhd:71/76).
                if reg_write = '1' and rd_addr /= "00000" then
                    if rd_n < MAX_RD then
                        rd_a(rd_n) := rd_addr; rd_v(rd_n) := rd_data; rd_n := rd_n + 1;
                    else
                        emit("# BUFOVF " & hdr(cyc) & "rd");
                    end if;
                end if;
                -- The sp port. Only ZCM_SP_COMMIT is a retire-owned sp write (spec section 0-C5).
                -- IRQ_SV's sp-4 and IRQ_REST's sp+4 belong to the T and X records instead.
                if sp_write_en = '1' and state = ST_ZCM_SP_COMMIT and rd_n < MAX_RD then
                    rd_a(rd_n) := "00010"; rd_v(rd_n) := sp_write_data; rd_n := rd_n + 1;
                end if;

                -- ---------- Section 3-M1 memory transactions.
                -- wen is ACTIVE LOW per byte lane, so all-ones means no store this edge.
                is_store := (wen /= "1111");
                is_load  := (mem_access_instr = '1') and (wen = "1111");
                -- The states in which a memory transaction belongs to the in-flight instruction.
                own := (state = ST_EXECUTE)     or (state = ST_SC_CHECK)
                    or (state = ST_AMO_WRITE)   or (state = ST_CBOZ_WRITE)
                    or (state = ST_ZCM_PUSH_ST) or (state = ST_ZCM_POP_LD)
                    or (state = ST_ZCM_JT_LD);
                -- Access width from funct3: byte, halfword, otherwise word.
                if funct3 = "000" or funct3 = "100" then sz := 1;
                elsif funct3 = "001" or funct3 = "101" then sz := 2;
                else sz := 4; end if;

                if is_load then
                    if state = ST_AMO_READ or state = ST_LR_READ then
                        -- S1/S2: the AMO and LR re-reads are suppressed, bounded by EQUALITY against the already-logged address (A3).
                        if not (cap_vld and data_addr = cap_addr) then
                            emit("# ADDRMISMATCH " & hdr(cyc) & hexnat(state, 2) & " "
                                 & hexstr(cap_addr) & " " & hexstr(data_addr));
                            push_mem(false, data_addr, sz, (others => '0'));
                        end if;
                    elsif state = ST_SC_CHECK then
                        -- S3 (A3): a FAILED sc.w still reads at rs1, finding F2.
                        emit("# SCFAILRD " & hdr(cyc) & hexstr(data_addr));
                    else
                        if iv_valid and own then
                            push_mem(false, data_addr, sz, (others => '0'));
                        else
                            -- A6: an L emitted OUTSIDE a retire group is written to the file at the issue edge, so its data cannot be back-filled.
                            -- It keeps the pre-A6 zero and says so, so that V3's injector REFUSES it rather than injecting a fabricated 0.
                            emit_m(false, data_addr, sz, (others => '0'));
                            emit("# NODATA " & hdr(cyc) & "unowned " & hexstr(data_addr));
                        end if;
                        if not cap_vld then cap_addr := data_addr; cap_vld := true; end if;
                        -- F9: the iret dispatch's phantom read at ALU_Result, which is 0.
                        if state = ST_EXECUTE and isr_ret = '1' then
                            emit("# IRETPHANTOM " & hdr(cyc) & hexstr(data_addr));
                        end if;
                    end if;
                end if;

                -- R1: the iret POP rides MEMORY_WAIT with mem_access_instr='0' AND wen="1111", so it is invisible to both general tests (vesta:1461).
                if state = ST_MEMORY_WAIT and isr_ret = '1' then
                    -- A7 (this WAS the `V3 TODO`): the pop is the return half of a trap EVENT, and `retire` excludes MEMORY_WAIT when isr_ret='1'.
                    -- As a compared `M L` it therefore had no owning retire and misaligned the stream the moment an interrupt was taken.
                    -- It is now a diagnostic, BOUNDED BY AN EQUALITY, following the A3 principle of never reclassifying on state alone.
                    -- The pop address is `stack_pointer` by construction (vesta.vhd:1562, the IRQ_REST arm of the data_addr mux), so a pop from anywhere else is LOUD.
                    -- The popped WORD is deliberately not logged: read_data does not carry it until the following IRQ_REST edge, and the value is already provable from the T record's epc versus the first post-iret retire pc.
                    if data_addr = stack_pointer then
                        emit("# IRETPOP " & hdr(cyc) & hexstr(data_addr));
                    else
                        emit("# IRETPOPBAD " & hdr(cyc) & hexstr(data_addr) & " "
                             & hexstr(stack_pointer));
                    end if;
                end if;

                if is_store then
                    -- Find the lowest active byte lane and the store width.
                    lo := 0; sz := 0; dat := (others => '0');
                    for i in 0 to XLEN_BYTES-1 loop
                        if wen(i) = '0' then
                            if sz = 0 then lo := i; end if;
                            sz := sz + 1;
                        end if;
                    end loop;
                    -- Pack the active lanes down to bit 0, which is the record's data convention.
                    for i in 0 to XLEN_BYTES-1 loop
                        if wen(i) = '0' then
                            k := i - lo;
                            dat(k*8+7 downto k*8) := write_data(i*8+7 downto i*8);
                        end if;
                    end loop;
                    -- The lowest active lane must agree with the address's low two bits.
                    if (lo = 0 and data_addr(1 downto 0) /= "00") or
                       (lo = 1 and data_addr(1 downto 0) /= "01") or
                       (lo = 2 and data_addr(1 downto 0) /= "10") or
                       (lo = 3 and data_addr(1 downto 0) /= "11") then
                        emit("# LANEMISMATCH " & hdr(cyc) & hexstr(data_addr) & " " & natstr(lo));
                    end if;
                    if state = ST_TRAP_STATE then
                        -- F8: TRAP_STATE self-loops and can store EVERY cycle, hence the rate limit.
                        if ts_count < TRAPSTORE_LIMIT then
                            emit("# TRAPSTORE " & hdr(cyc) & hexstr(data_addr) & " "
                                 & hexnat(sz, 1) & " " & hexstr(dat));
                        elsif ts_count = TRAPSTORE_LIMIT then
                            emit("# TRAPSTORE " & hdr(cyc) & "further occurrences suppressed");
                        end if;
                        ts_count := ts_count + 1;
                    elsif state = ST_IRQ_SV then
                        -- A7: the legacy trap entry's return-PC push is a real committed store with NO Spike counterpart, emitted outside any retire.
                        -- It belongs to the T event, not to the compared stream.
                        -- BOUNDED BY AN EQUALITY (A3), and the bound needs no arithmetic: IRQ_SV drives BOTH data_addr and sp_write_data from sp-4 in the same cycle (vesta.vhd:1561 and :3286).
                        -- Comparing them therefore checks the actual hardware contract, so a push that misses the slot sp is about to become is LOUD.
                        if sp_write_en = '1' and data_addr = sp_write_data then
                            emit("# IRQPUSH " & hdr(cyc) & hexstr(data_addr) & " "
                                 & hexnat(sz, 1) & " " & hexstr(dat));
                        else
                            emit("# IRQPUSHBAD " & hdr(cyc) & hexstr(data_addr) & " "
                                 & hexstr(sp_write_data) & " " & hexnat(sz, 1) & " "
                                 & hexstr(dat) & " spwe " & std_logic'image(sp_write_en));
                        end if;
                    elsif state = ST_SC_CHECK and sc_fail_ext /= '0' then
                        -- A16 (finding T2): a GLOBALLY-failed sc.w.
                        -- The core's local reservation check passed, so `wen` is live and this looks exactly like a committed store.
                        -- resv_unit gates the write off downstream (resv_unit.vhd:120-123) and returns sc_fail_ext, so memory is NOT modified.
                        -- Emitting an `M ... S` here violated section 2's own definition of `M` as "a COMMITTED memory transaction": the record described a presentation, not a commit.
                        -- It is therefore not buffered at all.
                        --
                        -- The evidence stays visible to a human: this is a diagnostic, not a silent deletion.
                        -- It carries the full store it would have emitted so a triage can see exactly what was suppressed and where.
                        -- Amendment A15 (compare.py) used to remove the same record from the COMPARED stream; on a post-A16 trace it now finds nothing to drop, which is the intended end state.
                        --
                        -- X-taint is REFUSED, never guessed, following the A5/A15 discipline.
                        -- If the verdict itself is unreadable we cannot know whether the write committed, so the record is KEPT.
                        -- That is the conservative direction: a kept ghost is caught downstream by A15 or by the next load, while a wrongly-dropped real store is invisible.
                        if sc_fail_ext = '1' then
                            emit("# SCGHOST " & hdr(cyc) & hexstr(data_addr) & " "
                                 & hexnat(sz, 1) & " " & hexstr(dat));
                        else
                            emit("# SCGHOSTX " & hdr(cyc) & hexstr(data_addr) & " "
                                 & hexnat(sz, 1) & " " & hexstr(dat) & " scfe "
                                 & std_logic'image(sc_fail_ext));
                            if iv_valid and own then
                                push_mem(true, data_addr, sz, dat);
                            else
                                emit_m(true, data_addr, sz, dat);
                            end if;
                        end if;
                    elsif iv_valid and own then
                        push_mem(true, data_addr, sz, dat);
                    else
                        emit_m(true, data_addr, sz, dat);
                    end if;
                end if;

                -- ---------- A17: the A1 discipline, applied to the fflags strobe.
                -- A1 fixed the compared-`C` discriminator as "a retire happens on this edge" and made every OTHER edge's CSR-port activity a loud `# CSRLEAK` rather than a silent drop.
                -- The sticky-OR strobe is a second, independent write path into the same architectural register, so it gets the same treatment.
                -- `fp_flags_we` on a non-retire edge means flags committed outside any retire, which is exactly the F3/F7 leak class in a different port.
                -- This is EXPECTED to be silent: vesta.vhd's EXECUTE arm carries the same pmp, compressed and half-fetch guards that the tracer's own `is_disp` does, and FPU_DONE is an unconditional retire.
                -- But "expected silent" is precisely the claim that has to be instrumented rather than asserted.
                if fp_flags_we = '1' and not retire then
                    emit("# FPFLAGSLEAK " & hdr(cyc) & hexnat(state, 2) & " "
                         & hexstr(fp_flags_val));
                end if;

                -- ---------- Section 3-C1 and A1: a compared C record only on a retire edge.
                if csr_commit_we = '1' then
                    if retire then
                        csr_p := true; csr_pa := csr_addr; csr_pv := csr_commit_val;
                    else
                        emit("# CSRLEAK " & hdr(cyc) & hexnat(state, 2) & " "
                             & hexstr(csr_addr) & " " & hexstr(csr_commit_val));
                    end if;
                end if;

                -- ---------- R8: on a sequencer PMP abort, flush what DID commit.
                if (state = ST_CBOZ_WRITE or state = ST_ZCM_PUSH_ST or
                    state = ST_ZCM_POP_LD or state = ST_ZCM_JT_LD) and
                   (next_state = ST_TRAP_STATE or next_state = ST_MTRAP_SV) then
                    flush_mem;                    -- committed stores/loads are real
                    clear_inflight;               -- no R: nothing architectural completed
                end if;

                -- ---------- The retire flush: R records, then M records, then C records.
                if retire then
                    -- A retire with no committed rd write still emits one R record, writing x0.
                    if rd_n = 0 then
                        emit_r("00000", (others => '0'));
                    else
                        for i in 0 to rd_n-1 loop            -- A2: n R records
                            emit_r(rd_a(i), rd_v(i));
                        end loop;
                    end if;
                    flush_mem;
                    -- A10 covers the COMPARED set (R, M and C) and stops there.
                    -- T and X are RTL-side only and never compared (spec sections 4 and 5), so a mask on them would be a metric nothing can act on: decorative, which is worse than absent (R-W3-4).
                    -- mret's mstatus pop is the one C record keyed on state rather than on a commit strobe.
                    if state = ST_MTRAP_RET then
                        emit("C " & hdr(cyc) & "300 " & hexstr(mstatus_value));
                        emit_xbits("val", mstatus_value);
                    end if;
                    -- A17 (F-K2b-1): TWO corrections in one condition.
                    --   * WHEN. The strobe, not the state.
                    --     `fp_flags_we` has two arms in vesta.vhd: FPU_DONE for the multi-cycle ops and EXECUTE for the single-cycle ones (fmin/fmax/fsgnj/fcmp/fclass).
                    --     Keying on ST_FPU_DONE alone dropped every single-cycle op's record; measured, an `fmin.s` on a signalling NaN raised NV, the reference logged it, and the trace said nothing.
                    --   * WHAT. `fflags_value` is the fflags REGISTER read PRE-EDGE, and csr_unit's sticky OR commits on THIS edge, so the old record carried the value from before the op it belonged to.
                    --     The committed value is the OR, computed here from the same two operands the CSR flop captures (csr_unit.vhd:670-671).
                    --     It is not re-derived, and not read back a cycle later where an intervening `csrrw fflags` could have moved it.
                    -- This is a strict superset of the pre-A17 emission: at FPU_DONE `fp_flags_we` is unconditionally '1' and `state = ST_FPU_DONE` is unconditionally a retire, so no record that used to be emitted stops being emitted.
                    if fp_flags_we = '1' then
                        ffpost := fflags_value;
                        ffpost(4 downto 0) := fflags_value(4 downto 0) or fp_flags_val;
                        emit("C " & hdr(cyc) & "001 " & hexstr(ffpost));
                        emit_xbits("val", ffpost);
                    end if;
                    -- The explicit CSR write captured earlier on this same edge.
                    if csr_p then
                        emit("C " & hdr(cyc) & hexstr(csr_pa) & " " & hexstr(csr_pv));
                        emit_xbits("csr", csr_pa);
                        emit_xbits("val", csr_pv);
                    end if;
                    clear_inflight;
                end if;

                -- ---------- T records (spec section 3-T1).
                if state = ST_IRQ_SV then          -- legacy path: capture here, emit at IRQ_JUMP
                    t_pend := true;
                    t_epc  := write_data;          -- pc_next, the pushed return PC
                end if;
                -- The legacy vector is only known once IRQ_JUMP presents it.
                if state = ST_IRQ_JUMP and t_pend then
                    emit("T " & hdr(cyc) & "8000007f " & hexstr(t_epc) & " "
                         & hexstr(ivt_entry) & " 3");
                    t_pend := false;
                end if;
                -- Standard M-mode trap entry: mepc, mcause and mtval are all valid in MTRAP_SV.
                if state = ST_MTRAP_SV then
                    emit("T " & hdr(cyc) & hexstr(trap_cause_val) & " " & hexstr(trap_pc_val)
                         & " " & hexstr(trap_value_val) & " 3");
                end if;
                -- Entry into the terminal TRAP_STATE, logged once on the transition edge.
                if next_state = ST_TRAP_STATE and state /= ST_TRAP_STATE then
                    emit("T " & hdr(cyc)
                         & hexstr(mtrap_disp_int & RSVD27 & mtrap_disp_code)
                         & " " & hexstr(pc) & " " & hexstr(instr_curr) & " 3");
                end if;

                -- ---------- X records (spec section 3-X1).
                if state = ST_MTRAP_RET then
                    emit("X " & hdr(cyc) & "mret");
                end if;
                -- The legacy `iret` has no reference counterpart, so it is an X, not a retire.
                if state = ST_MEMORY_WAIT and isr_ret = '1' then
                    emit("X " & hdr(cyc) & "iret");
                end if;
                if state = ST_EXECUTE and next_state = ST_SLEEPING then
                    emit("X " & hdr(cyc) & "wfi_enter");
                end if;
                -- Any exit from SLEEPING; unarmed means we never saw the matching wfi dispatch.
                if state = ST_SLEEPING and next_state /= ST_SLEEPING then
                    if wfi_armed then
                        emit("X " & hdr(cyc) & "wfi_wake");
                    else
                        emit("# SLEEPEXIT " & hdr(cyc) & "unarmed");   -- R5
                    end if;
                    wfi_armed := false;
                end if;

                -- ---------- R6 probe: does INITIALIZE ever execute? (spec section 10-Reb1).
                if state = ST_INITIALIZE and not init_seen then
                    emit("# INIT " & hdr(cyc) & "INITIALIZE entered");
                    init_seen := true;
                end if;
            end if;

            cyc := cyc + 1;
        end if;
    end process trace_proc;

    -- ==========================================================
    -- D1 (R-D0-3(1)): THE STATE-ORDINAL COUNT ASSERT
    -- ==========================================================
    -- The contract above is enforced by prose in two files and by nothing else.
    -- This closes the ADD and REMOVE halves of it at ELABORATION time, in every configuration that instantiates the tracer at all.
    -- `cpu_state` cannot cross a port boundary in VHDL-93 but its CARDINALITY is a `natural` and can, which is the whole trick.
    -- WHAT IT DOES NOT CATCH, stated plainly rather than left to be assumed: a pure REORDER at constant count.
    -- No cheap VHDL-93 construct catches that, and presenting this as complete coverage would be worse than the gap.
    assert STATE_COUNT = ST_COUNT
        report "TRACER ORDINAL CONTRACT BROKEN: vesta declares "
             & integer'image(STATE_COUNT) & " cpu_state values, this tracer's "
             & "ST_* table has " & integer'image(ST_COUNT)
             & ". Update the ST_* block AND ST_COUNT in vesta_tracer.vhd."
        severity failure;

end architecture behav;
