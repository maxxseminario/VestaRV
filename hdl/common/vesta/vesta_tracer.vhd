/* vesta_tracer.vhd: retire-event trace writer for lockstep co-simulation, one ASCII file per hart.
   A PURE OBSERVER: no output ports, drives no signal, never touches the memory path.
   Instantiated in vesta.vhd inside `gen_trace: if TRACE_ENABLE generate`, so an OFF build elaborates none of it.
   It logs what COMMITTED, not what decode intended: every value comes from an actual write port, sampled pre-edge on rising_edge(clk_cpu).
   -V200X only: no VHDL-2008, no external names, no to_hstring; hex is hand-rolled below and std.textio is the only I/O. */

library IEEE;
use IEEE.std_logic_1164.all;
use std.textio.all;
library work;
use work.constants.all;

entity vesta_tracer is
    generic (
        -- Base name of the trace file, giving <TRACE_FILE>_h<xx>.trace; the hart suffix is appended at runtime because a generic cannot depend on the hart_id PORT.
        TRACE_FILE        : string  := "vesta_trace";
        -- Statically-known feature knobs, mirrored from vesta so the retire exclusion terms fold exactly as the FSM's do.
        ENABLE_PMP        : boolean := false;
        ENABLE_COMPRESSED : boolean := true;
        -- Rate limit for the #TRAPSTORE diagnostic: TRAP_STATE self-loops forever and can commit a store every cycle.
        TRAPSTORE_LIMIT   : natural := 8;
        -- Ordinal-count tripwire: vesta passes `cpu_state'pos(cpu_state'high) + 1` and the concurrent assert below fails elaboration when it disagrees with ST_COUNT.
        -- Default 0 is the fail-safe direction: an instantiation that forgets this generic fails the assert loudly instead of opting out of the check.
        STATE_COUNT       : natural := 0
    );
    port (
        -- EVERY PORT IS `in`. There is deliberately no output of any kind.
        clk_cpu          : in std_logic;                       -- the GATED core clock
        resetn           : in std_logic;
        hart_id          : in std_logic_vector(XLEN-1 downto 0);

        -- FSM state as an ordinal (see the ST_* table below).
        state            : in natural;                         -- cpu_state'pos(current_state)
        next_state       : in natural;                         -- cpu_state'pos(next_state)

        -- PC, the raw instruction bus, and the four dispatch-shape selectors.
        pc               : in std_logic_vector(XLEN-1 downto 0);
        instr            : in std_logic_vector(ILEN-1 downto 0);  -- the read_data bus itself
        instr_curr       : in std_logic_vector(ILEN-1 downto 0);  -- decoded/held
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

        -- The GLOBAL SC verdict from resv_unit: in SC_CHECK the core drives `wen` on its LOCAL check alone, so the port shows a store that resv_unit's `s_we_gated` then suppresses.
        -- It is stable by the end of the SC_CHECK cycle, which is the edge sampled here, and default '0' is fail-safe: an unwired instantiation drops no store record.
        sc_fail_ext      : in std_logic := '0';

        -- csr_unit's COMMITTED-write export, asserted only when a write `case` arm actually stores.
        csr_addr         : in std_logic_vector(11 downto 0);
        csr_commit_we    : in std_logic;
        csr_commit_val   : in std_logic_vector(XLEN-1 downto 0);
        mstatus_value    : in std_logic_vector(XLEN-1 downto 0); -- for MTRAP_RET's mret pop
        -- `fflags_value` is csr_unit's fflags REGISTER, read before this edge's sticky OR commits, so the post-op value is `fflags_value or fp_flags_val`.
        fflags_value     : in std_logic_vector(XLEN-1 downto 0); -- fflags PRE-edge
        -- `fp_flags_we` strobes on every edge an FP op commits flags, from both the multi-cycle (FPU_DONE) and single-cycle (EXECUTE) arms.
        -- Default '0' is the LOUD direction: an unwired instantiation emits no `C 001`, which is exactly right on a zfinx-off build and an immediate record-kind divergence on a Zfinx one.
        fp_flags_we      : in std_logic := '0';
        fp_flags_val     : in std_logic_vector(4 downto 0) := (others => '0');

        -- Decode class, for the EXECUTE retire exclusions.
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

    -- cpu_state ordinals: MUST match the DECLARATION ORDER of vesta.vhd's `type cpu_state` (find it with `grep -n "type cpu_state" vesta.vhd`).
    -- A wrong ordinal is silent, so every diagnostic line below prints the raw ordinal to make a mismatch visible.
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
    -- Debug-mode states, tail-appended exactly as in vesta.vhd.
    constant ST_DBG_SV        : natural := 39;
    constant ST_DBG_JUMP      : natural := 40;
    constant ST_DBG_RET       : natural := 41;
    constant ST_COUNT         : natural := 42;

    -- Buffer depths: a cm.pop commits up to 13 rd writes plus 1 sp write for ONE architectural instruction and a cbo.zero commits CBOZ_WORDS stores, each flushed as one retire.
    constant MAX_RD  : natural := 16;
    constant MAX_MEM : natural := 24;

    -- Nibble alphabet for the hand-rolled hex printers below.
    constant HEXCHARS : string(1 to 16) := "0123456789abcdef";

    -- Hand-rolled hex, because to_hstring is VHDL-2008.
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
                -- A literal 'x' nibble means the sampled RTL state carried an X there; no value is ever invented, and the comparator treats such a record as INVESTIGATE, never as a match.
                s(ND-i) := 'x';
            else
                s(ND-i) := HEXCHARS(d+1);
            end if;
        end loop;
        return s;
    end function hexstr;

    -- `hexstr` stays NIBBLE-granular so every compared field keeps its frozen width, and the three functions below add the bit-granular detail on a companion `# XBITS` line instead.
    -- The mask says WHICH bits were undriven, which a widened `000000xx` field could never distinguish from a defined '0' the program then branches on.

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

    -- The value with every undriven bit forced to '0': not an invented value, and meaningful only under the mask emitted beside it.
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
    -- Truncates from the top if nd is too small, which is harmless because the cycle field is debug-only and never compared.
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
    -- IMPURE because it reads the hart_id SIGNAL, which a pure function may not do; the cycle is a parameter so that read stays the only impurity.
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

    -- The one and only process, sampled on rising_edge(clk_cpu).
    -- The values read here are the PRE-EDGE values, i.e. exactly what the regfile, RAM and sequencer flops capture on this same edge.
    trace_proc: process(clk_cpu)
        file     f            : text;
        variable fopened      : boolean := false;
        variable cyc          : natural := 0;
        variable hstr         : string(1 to 2);
        -- In-flight architectural instruction: latched at dispatch, never re-read from the bus.
        variable iv_valid     : boolean := false;
        variable iv_pc        : std_logic_vector(XLEN-1 downto 0);
        variable iv_insn      : std_logic_vector(ILEN-1 downto 0);
        variable iv_c16       : boolean := false;
        -- Committed register writes for the in-flight instruction, one R record each.
        variable rd_n         : natural := 0;
        variable rd_a         : addr5_arr(0 to MAX_RD-1);
        variable rd_v         : word_arr(0 to MAX_RD-1);
        -- Committed memory transactions for the in-flight instruction.
        variable mm_n         : natural := 0;
        variable mm_st        : bool_arr(0 to MAX_MEM-1);
        variable mm_ad        : word_arr(0 to MAX_MEM-1);
        variable mm_da        : word_arr(0 to MAX_MEM-1);
        variable mm_sz        : nat_arr(0 to MAX_MEM-1);
        -- The address the AMO and LR re-read suppressions are bounded against.
        variable cap_addr     : std_logic_vector(XLEN-1 downto 0);
        variable cap_vld      : boolean := false;
        -- The returned load word is not on the bus at the ISSUE edge; it arrives one clk_cpu edge later, on the edge where the core itself consumes it.
        -- fl_pend and fl_idx back-fill the buffered L record's data field on that later edge.
        variable fl_pend      : boolean := false;
        variable fl_idx       : natural := 0;
        -- Pending explicit CSR write.
        variable csr_p        : boolean := false;
        variable csr_pa       : std_logic_vector(11 downto 0);
        variable csr_pv       : std_logic_vector(XLEN-1 downto 0);
        -- Legacy trap entry: captured at IRQ_SV, emitted at IRQ_JUMP.
        variable t_pend       : boolean := false;
        variable t_epc        : std_logic_vector(XLEN-1 downto 0);
        -- Miscellaneous one-shots and counters.
        variable wfi_armed    : boolean := false;   -- armed by the wfi dispatch
        variable ts_count     : natural := 0;       -- TRAPSTORE rate limit
        variable init_seen    : boolean := false;   -- INITIALIZE probe one-shot
        -- Per-edge combinational scratch.
        variable sP, sQ, sE, sD, sC, sA, sB : boolean;
        variable is_disp, ret_exec, retire  : boolean;
        variable is_load, is_store, own     : boolean;
        variable sz, lo, k                  : natural;
        variable dat                        : std_logic_vector(XLEN-1 downto 0);
        -- The POST-op fflags word: fflags_value with its low 5 bits OR'd with the completing op's flags.
        -- Held in a variable rather than written twice, so the record and its `# XBITS` companion cannot drift apart.
        variable ffpost                     : std_logic_vector(XLEN-1 downto 0);

        -- Write one finished record line to the trace file.
        procedure emit(s : string) is
            variable ll : line;
        begin
            write(ll, s);
            writeline(f, ll);
        end procedure emit;

        -- `# XBITS <hart> <cycle> <field> <mask> <defined>`, binding BACKWARD to the record on the line above and emitted only when that field is actually tainted.
        -- The call sits inside the record procedures so nothing can break that adjacency; mask is 1 at every undriven bit and defined is the value with those bits forced to 0, both the field's own width.
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
                -- Arm the one-edge-late data back-fill for a LOAD here, the single arming point, so no push site can forget it.
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

            -- Lazy open plus the mandatory trace header line: if that line is missing, a TRACE_ENABLE=false snapshot ran.
            if not fopened then
                hstr := hexstr(hart_id(7 downto 0));
                file_open(f, TRACE_FILE & "_h" & hstr & ".trace", write_mode);
                fopened := true;
                emit("# vesta_tracer TRACE_ENABLE=true " & TRACE_FILE & " hart=" & hstr);
                -- The format list tells a consumer which record shapes to expect; bump it whenever what this file emits changes.
                emit("# spec v1_retire_enumeration.md rev2 ; format RECORD_FORMAT.md A1-A7,A10,A16,A17");
            end if;

            if resetn = '1' then
                -- ---------- Dispatch shapes, mutually exclusive, P and Q evaluated first.
                sP := ENABLE_PMP and pmp_f_deny_r = '1';
                sQ := (not ENABLE_COMPRESSED) and pc(1) = '1';
                sE := (pc(1) = '1') and (quadrant_upper =  "11") and repeat_if = '0';
                sD := (pc(1) = '1') and repeat_if = '1';
                sC := (pc(1) = '1') and (quadrant_upper /= "11") and repeat_if = '0';
                sA := (pc(1) = '0') and (quadrant_lower =  "11");
                sB := (pc(1) = '0') and (quadrant_lower /= "11");
                is_disp := (state = ST_EXECUTE) and (not sP) and (not sQ) and (not sE);

                -- ---------- The retire condition.
                ret_exec := is_disp
                            and trap = '0' and ecall_op = '0' and ebreak_op = '0'
                            and mret_op = '0'
                            and not (ENABLE_PMP and pmp_d_deny = '1')
                            -- DBG_SV is in the whitelist, mirroring vesta.vhd's retire_now: a halt or step divert out of EXECUTE withdraws only pc_en, so the diverted instruction still retires.
                            -- This list must track vesta's; the deliberate difference between the two is the MEMORY_WAIT isr_ret term below, and nothing else.
                            and (next_state = ST_EXECUTE  or next_state = ST_IRQ_SV or
                                 next_state = ST_MTRAP_SV or next_state = ST_FENCE_WAIT or
                                 next_state = ST_DBG_SV);
                retire := ret_exec
                       or (state = ST_MEMORY_WAIT and isr_ret = '0')
                       or (state = ST_SLEEPING and next_state /= ST_SLEEPING and wfi_armed)
                       or state = ST_DIV_DONE  or state = ST_FPU_DONE
                       or state = ST_LR_READ   or state = ST_SC_CHECK
                       or state = ST_AMO_WRITE or state = ST_MTRAP_RET
                       -- DRET retires beside MRET: unlike `iret` it is a standard encoding the reference knows, so the retire is comparable.
                       or state = ST_DBG_RET
                       or state = ST_ZCM_RET   or state = ST_ZCM_JT_WB
                       or (state = ST_PAUSE_WAIT and next_state = ST_EXECUTE)
                       or (state = ST_WRS_WAIT  and next_state = ST_EXECUTE);

                -- ---------- Back-fill the load data issued on the PREVIOUS edge.
                -- `instr` IS the unified read bus and this edge is where the core itself consumes it; every load-issuing state is followed by its consuming state after exactly one clk_cpu edge, since a memory stall gates clk_cpu rather than adding edges.
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
                    if sD then          -- 32-bit instruction split across two fetches, rejoined with the held instr_lower_half
                        iv_insn := instr(15 downto 0) & instr_lower_half;
                        iv_c16  := false;
                    elsif sA then       -- aligned 32-bit instruction
                        iv_insn := instr;
                        iv_c16  := false;
                    elsif sC then       -- compressed instruction in the upper half of the fetched word
                        iv_insn := x"0000" & instr(31 downto 16);
                        iv_c16  := true;
                    else                -- sB: compressed instruction in the lower half
                        iv_insn := x"0000" & instr(15 downto 0);
                        iv_c16  := true;
                    end if;
                end if;

                -- ---------- Arm the WFI one-shot on the real dispatch only.
                if state = ST_EXECUTE and next_state = ST_SLEEPING then
                    wfi_armed := true;
                end if;

                -- ---------- Committed register writes on the regfile main port.
                if reg_write = '1' and rd_addr /= "00000" then
                    if rd_n < MAX_RD then
                        rd_a(rd_n) := rd_addr; rd_v(rd_n) := rd_data; rd_n := rd_n + 1;
                    else
                        emit("# BUFOVF " & hdr(cyc) & "rd");
                    end if;
                end if;
                -- The sp port: only ZCM_SP_COMMIT is a retire-owned sp write, while IRQ_SV's sp-4 and IRQ_REST's sp+4 belong to the T and X records instead.
                if sp_write_en = '1' and state = ST_ZCM_SP_COMMIT and rd_n < MAX_RD then
                    rd_a(rd_n) := "00010"; rd_v(rd_n) := sp_write_data; rd_n := rd_n + 1;
                end if;

                -- ---------- Memory transactions.
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
                        -- The AMO and LR re-reads are suppressed, bounded by EQUALITY against the already-logged address.
                        if not (cap_vld and data_addr = cap_addr) then
                            emit("# ADDRMISMATCH " & hdr(cyc) & hexnat(state, 2) & " "
                                 & hexstr(cap_addr) & " " & hexstr(data_addr));
                            push_mem(false, data_addr, sz, (others => '0'));
                        end if;
                    elsif state = ST_SC_CHECK then
                        -- A FAILED sc.w still reads at rs1.
                        emit("# SCFAILRD " & hdr(cyc) & hexstr(data_addr));
                    else
                        if iv_valid and own then
                            push_mem(false, data_addr, sz, (others => '0'));
                        else
                            -- An L emitted OUTSIDE a retire group is written at the issue edge, so its data cannot be back-filled: it keeps a zero and says so, and the injector then refuses it rather than injecting a fabricated 0.
                            emit_m(false, data_addr, sz, (others => '0'));
                            emit("# NODATA " & hdr(cyc) & "unowned " & hexstr(data_addr));
                        end if;
                        if not cap_vld then cap_addr := data_addr; cap_vld := true; end if;
                        -- The iret dispatch's phantom read at ALU_Result, which is 0.
                        if state = ST_EXECUTE and isr_ret = '1' then
                            emit("# IRETPHANTOM " & hdr(cyc) & hexstr(data_addr));
                        end if;
                    end if;
                end if;

                -- The iret POP rides MEMORY_WAIT with mem_access_instr='0' AND wen="1111", so it is invisible to both tests above.
                if state = ST_MEMORY_WAIT and isr_ret = '1' then
                    -- The pop is the return half of a trap EVENT with no owning retire, so it is a diagnostic bounded by an equality rather than a compared `M L`.
                    -- The pop address is `stack_pointer` by construction (the IRQ_REST arm of the data_addr mux), so a pop from anywhere else is LOUD; the popped WORD is not logged because read_data does not carry it until the following IRQ_REST edge.
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
                        -- TRAP_STATE self-loops and can store EVERY cycle, hence the rate limit.
                        if ts_count < TRAPSTORE_LIMIT then
                            emit("# TRAPSTORE " & hdr(cyc) & hexstr(data_addr) & " "
                                 & hexnat(sz, 1) & " " & hexstr(dat));
                        elsif ts_count = TRAPSTORE_LIMIT then
                            emit("# TRAPSTORE " & hdr(cyc) & "further occurrences suppressed");
                        end if;
                        ts_count := ts_count + 1;
                    elsif state = ST_IRQ_SV then
                        -- The legacy trap entry's return-PC push is a real committed store with no reference counterpart: it belongs to the T event, not to the compared stream.
                        -- IRQ_SV drives BOTH data_addr and sp_write_data from sp-4 in the same cycle, so comparing them bounds the push against the actual hardware contract and a push that misses the slot is LOUD.
                        if sp_write_en = '1' and data_addr = sp_write_data then
                            emit("# IRQPUSH " & hdr(cyc) & hexstr(data_addr) & " "
                                 & hexnat(sz, 1) & " " & hexstr(dat));
                        else
                            emit("# IRQPUSHBAD " & hdr(cyc) & hexstr(data_addr) & " "
                                 & hexstr(sp_write_data) & " " & hexnat(sz, 1) & " "
                                 & hexstr(dat) & " spwe " & std_logic'image(sp_write_en));
                        end if;
                    elsif state = ST_SC_CHECK and sc_fail_ext /= '0' then
                        /* A GLOBALLY-failed sc.w: the core's local reservation check passed so `wen` is live, but resv_unit gates the write off downstream and memory is NOT modified.
                           It is therefore never buffered as an `M ... S`, which would claim a commit that never happened, but emitted as a diagnostic carrying the full suppressed store.
                           X-taint is REFUSED, never guessed: an unreadable verdict cannot prove the write was dropped, so the record is KEPT, because a kept ghost is caught downstream while a wrongly-dropped real store is invisible. */
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

                -- ---------- Flags committed on a non-retire edge are a loud leak, never a silent drop, exactly like an off-retire CSR write.
                -- Expected to stay silent: vesta's EXECUTE arm carries the same pmp, compressed and half-fetch guards as `is_disp`, and FPU_DONE is an unconditional retire.
                if fp_flags_we = '1' and not retire then
                    emit("# FPFLAGSLEAK " & hdr(cyc) & hexnat(state, 2) & " "
                         & hexstr(fp_flags_val));
                end if;

                -- ---------- A compared C record only on a retire edge; any other edge's CSR commit is a loud leak.
                if csr_commit_we = '1' then
                    if retire then
                        csr_p := true; csr_pa := csr_addr; csr_pv := csr_commit_val;
                    else
                        emit("# CSRLEAK " & hdr(cyc) & hexnat(state, 2) & " "
                             & hexstr(csr_addr) & " " & hexstr(csr_commit_val));
                    end if;
                end if;

                -- ---------- On a sequencer PMP abort, flush what DID commit.
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
                        for i in 0 to rd_n-1 loop            -- one R record per committed write
                            emit_r(rd_a(i), rd_v(i));
                        end loop;
                    end if;
                    flush_mem;
                    -- The `# XBITS` companions cover the COMPARED set (R, M and C) only: T and X are RTL-side and never compared, so a mask on them would be decorative.
                    -- mret's mstatus pop is the one C record keyed on state rather than on a commit strobe.
                    if state = ST_MTRAP_RET then
                        emit("C " & hdr(cyc) & "300 " & hexstr(mstatus_value));
                        emit_xbits("val", mstatus_value);
                    end if;
                    -- Keyed on the STROBE, not on ST_FPU_DONE: `fp_flags_we` also has an EXECUTE arm for the single-cycle ops (fmin/fmax/fsgnj/fcmp/fclass), whose records a state key would drop.
                    -- The value is the committed sticky OR, built here from the same two operands the CSR flop captures rather than read back a cycle later where a `csrrw fflags` could have moved it.
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

                -- ---------- T records: trap entries.
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

                -- ---------- X records: events with no reference counterpart.
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
                        emit("# SLEEPEXIT " & hdr(cyc) & "unarmed");
                    end if;
                    wfi_armed := false;
                end if;

                -- ---------- One-shot probe: does INITIALIZE ever execute?
                if state = ST_INITIALIZE and not init_seen then
                    emit("# INIT " & hdr(cyc) & "INITIALIZE entered");
                    init_seen := true;
                end if;
            end if;

            cyc := cyc + 1;
        end if;
    end process trace_proc;

    -- The state-ordinal count assert: `cpu_state` cannot cross a port boundary but its CARDINALITY can, so an added or removed state fails elaboration here.
    -- It does NOT catch a pure REORDER at constant count; no cheap construct does.
    assert STATE_COUNT = ST_COUNT
        report "TRACER ORDINAL CONTRACT BROKEN: vesta declares "
             & integer'image(STATE_COUNT) & " cpu_state values, this tracer's "
             & "ST_* table has " & integer'image(ST_COUNT)
             & ". Update the ST_* block AND ST_COUNT in vesta_tracer.vhd."
        severity failure;

end architecture behav;
