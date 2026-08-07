# =============================================================================
# dbg_tap.tcl -- the D3 harness library: a TCK-LEVEL JTAG TAP bus-functional
# model over the MCU's five new d3_spec-0 JTAG ports, plus a TAP-backed
# `dmi_xact` that lets any D2 harness be REPLAYED THROUGH THE TAP unmodified.
# SOURCED by every D3 tcl harness; it is not a harness itself.
#
# BLIND-AUTHORED 2026-08-06 against d3_spec.md and d3_cdc_spec.md (both FROZEN)
# by an agent that has not seen and will never see the D3 implementation.  At
# authoring time (HEAD f3d5172) NO JTAG PORT EXISTS anywhere in hdl/common,
# hdl/argus or platform/common -- verified, not assumed -- so every check in
# this family is written against the frozen text alone.
#
# ---------------------------------------------------------------------------
# WHY A tcl PIN-LEVEL BFM AND NOT A VHDL ONE (the family-A lineage)
#   hdl/common/tb/riscv_tb.vhd:32 declares MCU as a COMPONENT whose port list
#   ends at a0_3 (verified at HEAD: no dmi_*, no jtag).  So on a D3 chip every
#   one of the five JTAG ports of the MCU ENTITY is UNASSOCIATED and sits at
#   the entity default d3_spec 0 requires ("fail-safe defaults: trstn '0'
#   holds the TAP in reset => inert").  An unassociated formal input is exactly
#   what D1 forced at :dut:hart1:dbg_haltreq and D2 forced at
#   :dut:dmi_req_valid, and both were proven to reach the logic.  So the
#   debugger here is a tcl process wiggling the same five pads a bench wire --
#   and, after the DD6 cut, a real probe -- will wiggle.
#
#   The companion VHDL bench hdl/common/tb/dbg_tap_tb.vhd (instrument J3) is
#   the file that NAMES the five ports in VHDL, so a missing or misspelled port
#   is an ELABORATION ERROR there.  Neither file makes the other redundant:
#   J3 catches an absent port at compile time, this family grades TAP behaviour
#   on riscv_tb -- the environment the whole 143-test suite runs in every day.
#   That split is dbg_conf.tcl's own argument (its header, lines 7-24) and it
#   is inherited here deliberately.
#
# ---------------------------------------------------------------------------
# THE PIN PROTOCOL, AND WHY IT IS SHAPED LIKE THIS
#   d3_spec 1: "TMS sampled on TCK rising; TDO changes on falling, LSB-first".
#   Spike's jtag_dtm.cc:79-131 is the reference and was READ, not remembered:
#     * on the rising call it uses the PREVIOUSLY LATCHED pins
#       (`_state = next[_state][_tms]`, `dr |= _tdi << (dr_length-1)`), so
#       TMS/TDI must be presented while TCK is LOW and be stable across the
#       rising edge;
#     * on the non-rising call it updates TDO from the state it has just
#       entered (`SHIFT_DR: _tdo = dr & 1`), so TDO for bit k is valid after
#       the k-th falling edge and must be SAMPLED BEFORE the next rising edge.
#   tap_step therefore runs THREE times per TCK cycle: a setup window with the
#   new TMS/TDI and TCK still low, the high phase, and the low phase in which
#   TDO settles.  Driving TMS and TCK at the same simulation time would be a
#   race against the DUT's own edge process, and a race that resolves in the
#   BFM's favour today can resolve the other way after any RTL edit -- which
#   is the classic instrument that stops being evidence without saying so.
#
#   TCK RATE.  Default half-period 60 ns + 20 ns setup = 140 ns period
#   (~7.1 MHz) against mclk 41.667 ns (24 MHz, riscv_tb.vhd:90) -- a ratio a
#   real debugger would use, and slow enough that nothing here depends on
#   TCK being fast.  Override with D3_TCK_HALF_NS / D3_TCK_SETUP_NS.  NOTHING
#   in this file assumes a TCK:mclk ratio: every crossing wait is expressed in
#   TCK cycles or in the DUT's own observable progress, never in wall or sim
#   time (method rule 17).
#
# EVERY LOOP IN THIS FILE IS BOUNDED.  A poll that never satisfies its
# condition must FAIL the run, never hang it (the dbg_bfm.tcl rule, and the
# 1-minute rule).
# =============================================================================

# ---------------------------------------------------------------------------
# The five JTAG pins, and the ONE place their existence is decided.
# Prefix is overridable so the same library serves riscv_tb (:dut:) and the
# J3 unit bench, and so a mutation scratch run can point somewhere else.
# ---------------------------------------------------------------------------
if {![info exists ::TAP_PFX]} { set ::TAP_PFX ":dut:" }
set ::TAP_TCK   "${::TAP_PFX}tck"
set ::TAP_TMS   "${::TAP_PFX}tms"
set ::TAP_TDI   "${::TAP_PFX}tdi"
set ::TAP_TDO   "${::TAP_PFX}tdo"
set ::TAP_TRSTN "${::TAP_PFX}trstn"

# The IDCODE values are USER decisions (R-DD4(1)); the chip is selected by
# NHARTS, which is the only chip discriminator a harness has in-band.
set ::TAP_IDCODE_CASTALIA 0x1CA57EEF
set ::TAP_IDCODE_ARGUS    0x1A265EEF

# IR opcodes (d3_spec 1)
set ::IR_IDCODE 0x01
set ::IR_DTMCS  0x10
set ::IR_DMI    0x11
set ::IR_BYPASS 0x1F
set ::IR_LEN    5

# DR lengths (d3_spec 1)
set ::DRLEN_IDCODE 32
set ::DRLEN_DTMCS  32
set ::DRLEN_DMI    41
set ::DRLEN_BYPASS 1

# dmi DR field geometry: op[1:0], data[33:2], address[40:34] (Spike
# jtag_dtm.cc:28-40, and abits=7 matches the frozen port exactly).
set ::DMI_OP_LO   0
set ::DMI_DATA_LO 2
set ::DMI_ADDR_LO 34

# dtmcs bit geometry (Spike jtag_dtm.cc:21-26 == debug_defines.h:76-117)
proc dtmcs_version {v} { d2_fld $v 3 0 }
proc dtmcs_abits   {v} { d2_fld $v 9 4 }
proc dtmcs_dmistat {v} { d2_fld $v 11 10 }
proc dtmcs_idle    {v} { d2_fld $v 14 12 }
set ::DTMCS_DMIRESET_BIT     16
set ::DTMCS_DMIHARDRESET_BIT 17

# DMI response ops as they appear IN THE CAPTURED DR (Spike's status enum)
set ::TAPRSP_SUCCESS 0
set ::TAPRSP_FAILED  2
set ::TAPRSP_BUSY    3

# TCK timing
set ::TAP_HALF_NS  60
set ::TAP_SETUP_NS 20
if {[info exists ::env(D3_TCK_HALF_NS)]}  { set ::TAP_HALF_NS  $::env(D3_TCK_HALF_NS) }
if {[info exists ::env(D3_TCK_SETUP_NS)]} { set ::TAP_SETUP_NS $::env(D3_TCK_SETUP_NS) }

# Bookkeeping the harnesses report so a run's cost is on the record
set ::TAP_CYCLES   0
set ::TAP_SCANS    0
set ::TAP_DMIRESETS 0

# ---------------------------------------------------------------------------
# THE 16-STATE GRAPH.  Transcribed from Spike jtag_dtm.cc:60-77 (READ at
# authoring time from /home/mseminario2/local/src/spike-src, HEAD 3d8eb089),
# in Spike's own enum order (jtag_dtm.h:8-25).  Entry i = {next_if_tms0
# next_if_tms1}.  This is the standard IEEE 1149.1 graph; Spike is quoted
# because d3_spec 1 names it as THE reference.
# ---------------------------------------------------------------------------
set ::TAP_NAMES {TEST_LOGIC_RESET RUN_TEST_IDLE SELECT_DR_SCAN CAPTURE_DR
                 SHIFT_DR EXIT1_DR PAUSE_DR EXIT2_DR UPDATE_DR SELECT_IR_SCAN
                 CAPTURE_IR SHIFT_IR EXIT1_IR PAUSE_IR EXIT2_IR UPDATE_IR}
set ::TAP_NEXT {
    {1 0}    {1 2}    {3 9}    {4 5}
    {4 5}    {6 8}    {6 7}    {4 8}
    {1 2}    {10 0}   {11 12}  {11 12}
    {13 15}  {13 14}  {11 15}  {1 2}
}
proc tap_sname {i} { lindex $::TAP_NAMES $i }
proc tap_sidx  {n} { lsearch -exact $::TAP_NAMES $n }

# The BFM's MODEL of where the TAP is.  It is a model, never a measurement:
# the TAP's state register is internal and no harness here reads it.  Every
# assertion about the graph is made through an OBSERVABLE consequence (what a
# subsequent scan returns), which is the only thing a pad-level debugger has.
set ::TAP_STATE 0

# ---------------------------------------------------------------------------
# presence.  Present iff EVERY one of the five frozen names resolves.  Partial
# presence is reported as absence AND named, because a half-implemented port is
# a finding and must not read as "no TAP yet" (the dmi_present shape).
# ---------------------------------------------------------------------------
proc tap_present {} {
    set missing {}
    foreach p [list $::TAP_TCK $::TAP_TMS $::TAP_TDI $::TAP_TDO $::TAP_TRSTN] {
        if {[catch {value $p} e]} { lappend missing "$p ($e)" }
    }
    if {[llength $missing] == 0} { return 1 }
    puts "DMILOG TAP_PORT_ABSENT count=[llength $missing] of 5"
    foreach m $missing { puts "DMILOG   missing: $m" }
    if {[llength $missing] < 5} {
        puts "DMILOG PARTIAL_TAP_PORT -- some jtag names resolve and some do not."
        puts "DMILOG   That is a FINDING, not an unimplemented feature."
    }
    puts "DMILOG VERDICT=INSTRUMENT_DEAD (no d3_spec-0 JTAG port in this build)"
    flush stdout
    return 0
}

# ---------------------------------------------------------------------------
# tap_run -- the ONLY place simulation time advances inside the BFM.
#
# When ::TAP_WATCH_READY is set it subdivides into 10 ns steps and counts
# RISING EDGES of the MCU's dmi_req_ready output.  That counter is how the
# ONE-SHOT clause (d3_cdc_spec 2) is instrumented: "exactly one DM accept per
# Update-DR" is a statement about the number of ack pulses, and ack pulses are
# one mclk wide (41.667 ns), so 10 ns sampling sees each of them ~4 times and
# cannot step over one -- the D1 dbg_halt.tcl lesson, where a 25 us poll walked
# past a 2 us window.
# ---------------------------------------------------------------------------
set ::TAP_WATCH_READY 0
set ::TAP_RDY_EDGES   0
set ::TAP_RDY_PREV    0
# tap_bit -- a std_logic read back from the simulator, as a 0/1 integer.
#
# FOUND BY THE LIVE CONTROL, 2026-08-06, and it had silently disabled EVERY
# TDO-dependent check in the D3 set.  `value` returns a std_logic as the
# three characters 'x' -- APOSTROPHES, not double quotes.  The first draft
# stripped double quotes (copied from d2_hex, which handles std_logic_VECTORs,
# where the delimiter really is ") and then compared to "1", so tap_tdo
# returned 0 for every bit ever sampled.  Against the reference stub that
# produced IDCODE = 0x00000000 and 9 of 12 control checks failing -- with the
# stub proven correct by direct probing in the same session.
#
# This is exactly the failure the control exists to catch: on a tree with no
# TAP the instruments would have reported INSTRUMENT_DEAD and looked fine, and
# the defect would have surfaced only after the implementer delivered, where
# it reads as an RTL bug.
proc tap_bit {v} {
    set s [string trim [string map {\" ""} $v] "'"]
    if {$s eq "1" || $s eq "H"} { return 1 }
    return 0
}
proc tap_run {ns} {
    if {!$::TAP_WATCH_READY} { eval run $ns ns ; return }
    set steps [expr {int($ns) / 10}]
    if {$steps < 1} { set steps 1 }
    for {set i 0} {$i < $steps} {incr i} {
        run 10 ns
        set v [tap_bit [d2_val $::DMI_RQR]]
        if {$v == 1 && $::TAP_RDY_PREV == 0} { incr ::TAP_RDY_EDGES }
        set ::TAP_RDY_PREV $v
    }
}
proc tap_watch_ready_begin {} {
    set ::TAP_RDY_EDGES 0
    set ::TAP_RDY_PREV [tap_bit [d2_val $::DMI_RQR]]
    set ::TAP_WATCH_READY 1
}
proc tap_watch_ready_end {} {
    set ::TAP_WATCH_READY 0
    return $::TAP_RDY_EDGES
}

# ---------------------------------------------------------------------------
# THE SAMPLER THAT ADVANCES ITS OWN TIME (instrument defect I-4, fixed under
# author ownership at the validation wave, R-D3-5(6)).
#
# WHAT WAS WRONG.  tap_watch_ready_begin installs a counter inside `tap_run`,
# which is the TAP BFM's own time advance.  That is correct for the TAP-side
# one-shot legs (T3 D19-D21), where every nanosecond of the transaction is
# spent inside tap_step.  It is USELESS for anything driven through
# dbg_bfm.tcl's `dmi_xact`, which advances time with its OWN `run 10 ns` loop:
# no tap_run executes between begin and end, so the counter cannot move and
# the answer is structurally 0.  T6's C4 could therefore only ever read zero,
# and C2 (inertness) got its expected 0 FOR THE WRONG REASON -- it would have
# passed on a DTM that was hammering the DM continuously.  A check that cannot
# fail is not a check.
#
# THE FIX, and it is the general rule: SAMPLE INSIDE THE LOOP THAT RUNS.  Both
# procs below own their time advance, so the acknowledge cannot slip past
# between two samples that never happened.
#
# 10 ns granularity is the same one dbg_bfm.tcl uses and is chosen for the
# same reason: `ready_r` is one mclk wide (41.667 ns), so each pulse is seen
# ~4 times and cannot be stepped over.
# ---------------------------------------------------------------------------

# Advance `steps` x 10 ns, counting rising edges of dmi_req_ready.  Used for
# the inertness window, where nothing else may happen by definition.
proc tap_accepts_window {steps} {
    set edges 0
    set prev [tap_bit [d2_val $::DMI_RQR]]
    for {set i 0} {$i < $steps} {incr i} {
        run 10 ns
        set v [tap_bit [d2_val $::DMI_RQR]]
        if {$v == 1 && $prev == 0} { incr edges }
        set prev $v
    }
    return $edges
}

# A RAW forced DMI transaction (the dbg_bfm.tcl handshake, family A) whose own
# poll loops count the acknowledge.  Returns {ok rsp_op rsp_data accepts}.
#
# THE TAIL WINDOW IS LOAD-BEARING, not padding.  The DM's re-capture lockout
# re-opens 9 mclk AFTER a capture (rsp_hold/rsp_arm; re-derived at authoring
# time from debug_module.vhd:814-827 and :1121-1123).  A duplicate accept is
# therefore a LATE event, and a counter that stopped at the response would
# report 1 for a master that goes on to earn a second accept.  The default
# tail is 6000 x 10 ns = 60 us, matching the window the implementer's
# independent diagnostic used to measure the same quantity.
proc tap_raw_xact_counted {op addr data {budget 6000} {tail 6000}} {
    set edges 0
    set prev [tap_bit [d2_val $::DMI_RQR]]
    catch {force $::DMI_RQA  "\"[d2_bits $addr 7]\""}
    catch {force $::DMI_RQD  "\"[d2_bits $data 32]\""}
    catch {force $::DMI_RQOP "\"[d2_bits $op 2]\""}
    catch {force $::DMI_RQV  '1'}

    set accepted 0
    for {set i 0} {$i < $budget} {incr i} {
        run 10 ns
        set v [tap_bit [d2_val $::DMI_RQR]]
        if {$v == 1 && $prev == 0} { incr edges }
        set prev $v
        if {$v == 1} { set accepted 1 ; break }
    }
    catch {force $::DMI_RQV  '0'}
    catch {force $::DMI_RQOP "\"00\""}
    if {!$accepted} {
        puts "DMILOG RAWCNT_NO_READY op=$op addr=[format 0x%02X $addr]"
        flush stdout
        return [list 0 -1 -1 $edges]
    }

    set rop -1 ; set rdat -1 ; set got 0
    for {set i 0} {$i < $budget} {incr i} {
        run 10 ns
        set v [tap_bit [d2_val $::DMI_RQR]]
        if {$v == 1 && $prev == 0} { incr edges }
        set prev $v
        if {[tap_bit [d2_val $::DMI_RSV]]} {
            set rop  [d2_int [d2_val $::DMI_RSOP]]
            set rdat [d2_int [d2_val $::DMI_RSD]]
            set got 1
            break
        }
    }
    for {set i 0} {$i < $tail} {incr i} {
        run 10 ns
        set v [tap_bit [d2_val $::DMI_RQR]]
        if {$v == 1 && $prev == 0} { incr edges }
        set prev $v
    }
    return [list $got $rop $rdat $edges]
}

# ---------------------------------------------------------------------------
# tap_step -- ONE TCK cycle.  TCK is LOW on entry and LOW on exit, and TDO is
# settled and readable on exit.  See the header for the three-phase rationale.
# ---------------------------------------------------------------------------
proc tap_step {tms {tdi 0}} {
    catch {force $::TAP_TMS [expr {$tms ? "'1'" : "'0'"}]}
    catch {force $::TAP_TDI [expr {$tdi ? "'1'" : "'0'"}]}
    tap_run $::TAP_SETUP_NS
    catch {force $::TAP_TCK '1'}
    tap_run $::TAP_HALF_NS
    catch {force $::TAP_TCK '0'}
    tap_run $::TAP_HALF_NS
    set ::TAP_STATE [lindex [lindex $::TAP_NEXT $::TAP_STATE] $tms]
    incr ::TAP_CYCLES
}
proc tap_tdo {} { return [tap_bit [d2_val $::TAP_TDO]] }

# tap_idle -- park in RUN_TEST_IDLE for n TCK cycles.  This is the dwell
# dtmcs.idle advertises (d3_cdc_spec 4) and the only place the DUT is given
# crossing time.  Expressed in TCK CYCLES, never in nanoseconds.
proc tap_idle {n} {
    tap_goto RUN_TEST_IDLE
    for {set i 0} {$i < $n} {incr i} { tap_step 0 0 }
}

# ---------------------------------------------------------------------------
# tap_reset -- TMS high for 5 TCK cycles reaches TEST_LOGIC_RESET from ANY of
# the 16 states.  Five is not folklore: the longest TMS=1 walk to TLR in the
# table above is SHIFT_DR -> EXIT1_DR -> UPDATE_DR -> SELECT_DR -> SELECT_IR ->
# TLR, which is exactly 5.  The BFM asserts nothing here; the CHECK that this
# really reaches TLR lives in dbg_tapconf.tcl and is made by reading IDCODE.
# ---------------------------------------------------------------------------
proc tap_reset {} {
    for {set i 0} {$i < 5} {incr i} { tap_step 1 0 }
    set ::TAP_STATE 0
    set ::TAP_IR $::IR_IDCODE     ;# TLR sets IR = IDCODE (d3_spec 1)
}

# tap_trst_pulse -- assert the ASYNC reset with TCK PARKED LOW, so a design
# that only reaches TLR through a TCK edge fails this and a truly async one
# passes.  Holding it for whole TCK periods rather than a fixed ns count keeps
# the leg rate-independent.
proc tap_trst_pulse {{periods 4}} {
    catch {force $::TAP_TRSTN '0'}
    for {set i 0} {$i < $periods} {incr i} {
        tap_run [expr {$::TAP_SETUP_NS + 2*$::TAP_HALF_NS}]
    }
    catch {force $::TAP_TRSTN '1'}
    tap_run [expr {$::TAP_SETUP_NS + 2*$::TAP_HALF_NS}]
    set ::TAP_STATE 0
    set ::TAP_IR $::IR_IDCODE
}

# tap_init -- park the pins in their idle condition and release the TAP from
# reset.  trstn IDLES HIGH here: the entity DEFAULT is '0' (inert), and this
# BFM is the thing that plugs a debugger in.
proc tap_init {} {
    catch {force $::TAP_TCK   '0'}
    catch {force $::TAP_TMS   '1'}
    catch {force $::TAP_TDI   '0'}
    catch {force $::TAP_TRSTN '0'}
    tap_run 200
    catch {force $::TAP_TRSTN '1'}
    tap_run 200
    set ::TAP_STATE 0
    set ::TAP_IR $::IR_IDCODE
    tap_reset
}

# ---------------------------------------------------------------------------
# tap_goto -- navigate to a named state by breadth-first search over the SAME
# table the DUT is supposed to implement.  Bounded by construction (16 states).
# ---------------------------------------------------------------------------
proc tap_path {from to} {
    if {$from == $to} { return {} }
    set prev {} ; set act {}
    for {set i 0} {$i < 16} {incr i} { lappend prev -1 ; lappend act -1 }
    set q [list $from] ; lset prev $from -2
    while {[llength $q]} {
        set s [lindex $q 0] ; set q [lrange $q 1 end]
        foreach t {0 1} {
            set n [lindex [lindex $::TAP_NEXT $s] $t]
            if {[lindex $prev $n] == -1} {
                lset prev $n $s ; lset act $n $t
                if {$n == $to} {
                    set path {} ; set cur $n
                    while {$cur != $from} {
                        set path [linsert $path 0 [lindex $act $cur]]
                        set cur [lindex $prev $cur]
                    }
                    return $path
                }
                lappend q $n
            }
        }
    }
    return {}
}
proc tap_goto {name} {
    set to [tap_sidx $name]
    if {$to < 0} { error "tap_goto: no such TAP state '$name'" }
    foreach t [tap_path $::TAP_STATE $to] { tap_step $t 0 }
}

# ---------------------------------------------------------------------------
# tap_shift_ir -- load IR, return the value CAPTURED in Capture-IR.
# LSB-first, last bit with TMS=1 (Exit1-IR), then Update-IR, then Run-Test/Idle.
# ---------------------------------------------------------------------------
set ::TAP_IR 0x01
proc tap_shift_ir {ir} {
    tap_goto SHIFT_IR
    set cap 0
    for {set k 0} {$k < $::IR_LEN} {incr k} {
        if {[tap_tdo]} { set cap [expr {$cap | (1 << $k)}] }
        tap_step [expr {$k == $::IR_LEN-1}] [expr {($ir >> $k) & 1}]
    }
    tap_goto UPDATE_IR
    tap_goto RUN_TEST_IDLE
    set ::TAP_IR $ir
    incr ::TAP_SCANS
    return $cap
}
# Load IR only if it is not already loaded.  Every logical DMI transaction is
# two DR scans, and re-loading IR before each would triple the TCK cost for no
# coverage -- the IR-persistence itself is checked once, explicitly, in
# dbg_tapconf.tcl rather than assumed here.
proc tap_ir {ir} {
    if {$::TAP_IR != $ir} { tap_shift_ir $ir }
}

# ---------------------------------------------------------------------------
# tap_shift_dr -- shift n bits LSB-first out of `out`, return the n captured
# bits.  Values are kept <= 32 bits everywhere; the 41-bit dmi DR is handled by
# tap_dmi_scan below, which shifts from THREE fields so no tcl integer ever
# has to be wider than 32 bits (portability across the simulator's tcl).
# ---------------------------------------------------------------------------
proc tap_shift_dr {out n} {
    tap_goto SHIFT_DR
    set cap 0
    for {set k 0} {$k < $n} {incr k} {
        if {[tap_tdo]} { set cap [expr {$cap | (1 << $k)}] }
        tap_step [expr {$k == $n-1}] [expr {($out >> $k) & 1}]
    }
    tap_goto UPDATE_DR
    tap_goto RUN_TEST_IDLE
    incr ::TAP_SCANS
    return $cap
}

# ---------------------------------------------------------------------------
# tap_dmi_scan -- ONE 41-bit dmi DR scan.  Shifts out {op,data,addr} and
# returns the captured {op data addr} as three separate values.
#
# THE CAPTURED WORD IS THE PREVIOUS OPERATION'S RESULT (d3_cdc_spec 2's
# Capture-DR clause), never this scan's.  Every caller here treats it that way;
# a caller that reads its own result out of the same scan is reading the one
# before it, which is precisely the bug this shape exists to make impossible.
# ---------------------------------------------------------------------------
# `endstate` exists for ONE purpose: the sticky-busy provocation needs to reach
# Capture-DR by the SHORTEST legal path (Update-DR -> Select-DR -> Capture-DR,
# two TCK cycles) instead of parking in Run-Test/Idle first.  See
# tap_dmi_capture_now for why two cycles is the rate-independent provocation.
proc tap_dmi_scan {op data addr {endstate RUN_TEST_IDLE}} {
    tap_ir $::IR_DMI
    tap_goto SHIFT_DR
    set cop 0 ; set cdata 0 ; set caddr 0
    for {set k 0} {$k < $::DRLEN_DMI} {incr k} {
        set b [tap_tdo]
        if {$b} {
            if {$k < 2} {
                set cop [expr {$cop | (1 << $k)}]
            } elseif {$k < 34} {
                set cdata [expr {$cdata | (1 << ($k - 2))}]
            } else {
                set caddr [expr {$caddr | (1 << ($k - 34))}]
            }
        }
        if {$k < 2} {
            set o [expr {($op >> $k) & 1}]
        } elseif {$k < 34} {
            set o [expr {($data >> ($k - 2)) & 1}]
        } else {
            set o [expr {($addr >> ($k - 34)) & 1}]
        }
        tap_step [expr {$k == $::DRLEN_DMI-1}] $o
    }
    tap_goto UPDATE_DR
    if {$endstate ne "UPDATE_DR"} { tap_goto $endstate }
    incr ::TAP_SCANS
    return [list $cop [expr {$cdata & 0xFFFFFFFF}] $caddr]
}

# ---------------------------------------------------------------------------
# tap_dmi_capture_now -- capture the dmi DR by the SHORTEST path from Update-DR:
# Update-DR --TMS=1--> Select-DR --TMS=0--> Capture-DR --TMS=0--> Shift-DR.
# Two TCK cycles elapse between the Update that armed the request and the
# Capture that samples the result.
#
# WHY THIS PROVOKES BUSY AT ANY TCK RATE, and it is an argument from the FROZEN
# spec rather than from a measured delay: d3_cdc_spec 1 mandates a THREE-FLOP
# destination chain (2-FF sync + edge detect), and 2 of the frozen response
# path's flops live in the TCK domain.  A response toggle therefore cannot be
# observed by the TCK side in fewer than 3 TCK edges no matter how fast the DM
# answers.  A capture 2 TCK cycles after the Update is by construction earlier
# than that, so the DTM MUST still read itself as in-flight.  No number of
# nanoseconds appears in this reasoning, which is the point (method rule 17).
#
# Shifts in an all-zero word, so the Update at the end of the capture scan is a
# NOP and cannot arm anything.
# ---------------------------------------------------------------------------
proc tap_dmi_capture_now {} {
    # IR MUST be selected here, and its absence was instrument defect I-6 --
    # found by the author during the validation wave, by the two NEW checks
    # (D25/D26) that were the first callers to reach this proc with a
    # different IR loaded.
    #
    # The proc was written for one caller shape: "you are parked in Update-DR
    # of a dmi scan, capture by the shortest path", where IR is dmi by
    # construction.  D25 arrives after `tap_dmihardreset` and D26 after
    # `tap_reset`, which leave IR = DTMCS and IR = IDCODE respectively -- so
    # the capture shifted 41 bits out of a 32-bit dtmcs register and reported
    # the result as a dmi word.  The tell was op = 1 (RESERVED, a value
    # nothing produces) with data 0x00001C1C, which is dtmcs's 0x71 shifted
    # down by the two op bits.
    #
    # IT ALSO MEANS D16a AND D18a HAD BEEN PASSING VACUOUSLY: both assert
    # "the capture does NOT carry hartinfo's address", and a misread dtmcs
    # trivially satisfies that.  Selecting IR here makes those two checks
    # real for the first time.  Re-loading IR is exactly what a debugger does
    # between a dtmcs access and a dmi access, and it disturbs no DTM state.
    tap_ir $::IR_DMI
    tap_goto SHIFT_DR
    set cop 0 ; set cdata 0 ; set caddr 0
    for {set k 0} {$k < $::DRLEN_DMI} {incr k} {
        if {[tap_tdo]} {
            if {$k < 2} {
                set cop [expr {$cop | (1 << $k)}]
            } elseif {$k < 34} {
                set cdata [expr {$cdata | (1 << ($k - 2))}]
            } else {
                set caddr [expr {$caddr | (1 << ($k - 34))}]
            }
        }
        tap_step [expr {$k == $::DRLEN_DMI-1}] 0
    }
    tap_goto UPDATE_DR
    tap_goto RUN_TEST_IDLE
    incr ::TAP_SCANS
    return [list $cop [expr {$cdata & 0xFFFFFFFF}] $caddr]
}

# dtmcs helpers
proc tap_read_dtmcs {} {
    tap_ir $::IR_DTMCS
    return [tap_shift_dr 0 $::DRLEN_DTMCS]
}
proc tap_dmireset {} {
    tap_ir $::IR_DTMCS
    tap_shift_dr [expr {1 << $::DTMCS_DMIRESET_BIT}] $::DRLEN_DTMCS
    incr ::TAP_DMIRESETS
}
proc tap_dmihardreset {} {
    tap_ir $::IR_DTMCS
    tap_shift_dr [expr {1 << $::DTMCS_DMIHARDRESET_BIT}] $::DRLEN_DTMCS
}
proc tap_read_idcode {} {
    tap_ir $::IR_IDCODE
    return [tap_shift_dr 0 $::DRLEN_IDCODE]
}

# The dwell used between arming a DMI request and capturing its result.
# tap_calibrate_idle sets it from the DUT's OWN advertised dtmcs.idle, with a
# floor so that a design advertising 0 (which d3_cdc_spec 4 permits if the
# crossing really is that fast) still gets a workable replay.  The TRUTHFULNESS
# of `idle` is checked separately and exactly, in dbg_tapdtm.tcl -- this is the
# ROBUSTNESS knob, not the assertion.
set ::TAP_IDLE_DWELL 8
set ::TAP_IDLE_ADV   -1
proc tap_calibrate_idle {{floor 8}} {
    set v [tap_read_dtmcs]
    set ::TAP_IDLE_ADV [dtmcs_idle $v]
    set ::TAP_IDLE_DWELL [expr {$::TAP_IDLE_ADV > $floor ? $::TAP_IDLE_ADV : $floor}]
    puts "DMILOG TAP dtmcs=[format 0x%08X $v] version=[dtmcs_version $v] abits=[dtmcs_abits $v] idle=$::TAP_IDLE_ADV dmistat=[dtmcs_dmistat $v] -> dwell $::TAP_IDLE_DWELL"
    flush stdout
    return $v
}

# ---------------------------------------------------------------------------
# tap_dmi_xact -- ONE LOGICAL DMI TRANSACTION THROUGH THE TAP.
# Returns {ok rsp_op rsp_data} -- byte-for-byte the contract of dbg_bfm.tcl's
# dmi_xact, which is what makes the whole-stack replay possible.
#
# Shape: arm with a real op, dwell in Run-Test/Idle, then capture the result
# with a NOP scan.  Two scans per transaction, deliberately:
#   * the NOP scan is the only way to read a result without arming another
#     request, and "NOP scans never arm busy" is a frozen clause (d3_spec 2);
#   * the pipelined one-scan idiom OpenOCD uses would make every result the
#     PREVIOUS caller's, and a harness that quietly reads a stale word is the
#     silent class this programme keeps finding.
#
# STICKY HANDLING IS THE DEBUGGER'S JOB, AND IT IS DONE HERE, NOT HIDDEN:
# a captured op of BUSY(3) means the crossing had not finished -- d3_cdc_spec 4
# calls busy "a normal outcome, not an error" -- so the transaction is
# RE-ISSUED after dmireset, which per d3_spec 2 also ABANDONS the outstanding
# transaction.  A captured FAILED(2) is a real answer and is RETURNED to the
# caller, but it also latches dmistat, so dmireset is issued before the next
# transaction can be accepted.  Both paths are counted (::TAP_DMIRESETS) and
# every harness prints the count: a replay that silently needed 400 dmiresets
# is a finding about the crossing even when every check passes.
# ---------------------------------------------------------------------------
proc tap_dmi_xact {op addr data} {
    set ATTEMPTS 8
    for {set a 0} {$a < $ATTEMPTS} {incr a} {
        tap_dmi_scan $op $data $addr          ;# arm (capture discarded)
        tap_idle $::TAP_IDLE_DWELL
        set r [tap_dmi_scan 0 0 0]            ;# NOP scan: capture THIS result
        set cop [lindex $r 0]
        if {$cop == $::TAPRSP_BUSY} {
            tap_dmireset
            continue
        }
        if {$cop == $::TAPRSP_FAILED} { tap_dmireset }
        return [list 1 $cop [lindex $r 1]]
    }
    puts "DMILOG TAP_XACT_STUCK_BUSY op=$op addr=[format 0x%02X $addr] after $ATTEMPTS attempts"
    flush stdout
    return [list 0 -1 -1]
}

# ---------------------------------------------------------------------------
# TAP-NATIVE convenience wrappers.  These are deliberately NOT named
# dmi_read/dmi_write: a harness that wants the TAP transport explicitly (T3,
# T5) calls these, and a harness that wants to REPLAY a D2 file unmodified
# (T4) installs the backend below instead.  Keeping the two spellings apart
# means no file is ever ambiguous about which transport it just used -- the
# misattribution class this programme keeps paying for.
# ---------------------------------------------------------------------------
set ::TAPOK  0
set ::TAPROP -1
proc dmi_read_tap {addr} {
    set r [tap_dmi_xact 1 $addr 0]
    set ::TAPOK  [lindex $r 0]
    set ::TAPROP [lindex $r 1]
    return [lindex $r 2]
}
proc dmi_write_tap {addr data} {
    set r [tap_dmi_xact 2 $addr $data]
    set ::TAPOK  [lindex $r 0]
    set ::TAPROP [lindex $r 1]
    return [lindex $r 2]
}
proc ac_clear_cmderr_tap {} { dmi_write_tap $::DM_ABSTRACTCS [expr {7 << 8}] }

# ---------------------------------------------------------------------------
# INSTALLING THE TAP AS THE DMI BACKEND.
#
# dbg_bfm.tcl funnels EVERY DM access through one proc, `dmi_xact`
# (dbg_bfm.tcl:179-215; dmi_read/dmi_write are thin wrappers at :219-230).
# Replacing that one proc therefore re-points the entire D2 harness library --
# all of dm_select / dm_haltreq / dm_poll_status / ac_read_reg / dbg_conf's 38
# checks -- at the JTAG pins, with NOTHING ELSE CHANGED and, crucially, with
# the canonical harness files executing verbatim.  That is the whole-stack
# proof d3_spec 6 asks for: the same list, the same file, a different transport.
# ---------------------------------------------------------------------------
proc tap_install_dmi_backend {} {
    proc dmi_xact {op addr data} { return [tap_dmi_xact $op $addr $data] }
    proc dmi_present {} { return [tap_present] }
    puts "DMILOG TAP backend INSTALLED -- dmi_xact now runs over TCK/TMS/TDI/TDO"
    flush stdout
}

# ---------------------------------------------------------------------------
# tap_measure_len -- MEASURE a scan chain's length instead of inferring it.
# Flush the selected register with ones, then count how many shifts a zero
# takes to reach TDO.  The count IS the length.
#
# THE FLUSH IS VERIFIED, AND THAT VERIFICATION IS NOT DECORATION.  The first
# draft simply pushed ones and then counted zeros -- and a TDO STUCK AT 0
# returns 1 from that loop, which is indistinguishable from a genuine one-bit
# BYPASS.  Measured 2026-08-06 during the live-control run: with tap_bit
# broken, the BYPASS length checks PASSED while every value check failed, i.e.
# the two checks that should have been most obviously wrong were the two
# reporting ok.  So the flush now asserts that TDO actually went high; if it
# never does, the answer is -2 (TDO_STUCK) and the caller reports that rather
# than a plausible length.
#
# Returns: the length, -1 if no zero emerged inside the bound, -2 if TDO never
# went high during the flush (stuck low / not driven).
#
# SAFETY: leaves the register ALL ZERO and exits through Update, so the
# unavoidable Update commits a NOP for every IR a caller here selects.  Getting
# that wrong would let a conformance harness write dmcontrol with random bits
# -- including dmactive = 0 -- and then report on a DM it had just reset.
# ---------------------------------------------------------------------------
proc tap_measure_len {shiftstate {maxlen 128}} {
    tap_goto $shiftstate
    set sawhigh 0
    for {set i 0} {$i < $maxlen} {incr i} {
        tap_step 0 1
        if {[tap_tdo]} { set sawhigh 1 }
    }
    set len -1
    if {!$sawhigh} {
        set len -2
    } else {
        for {set i 1} {$i <= $maxlen} {incr i} {
            tap_step 0 0
            if {![tap_tdo]} { set len $i ; break }
        }
    }
    for {set i 0} {$i < $maxlen} {incr i} { tap_step 0 0 }
    if {$shiftstate eq "SHIFT_IR"} {
        # leave a SAFE, DEFINED IR behind: BYPASS.  An all-zero IR would be an
        # unsupported opcode, which is legal (it selects BYPASS) but would make
        # the next check depend on the very deviation it is testing.
        for {set k 0} {$k < $::IR_LEN} {incr k} {
            tap_step [expr {$k == $::IR_LEN-1}] [expr {($::IR_BYPASS >> $k) & 1}]
        }
        tap_goto UPDATE_IR
        set ::TAP_IR $::IR_BYPASS
    } else {
        tap_step 1 0
        tap_goto UPDATE_DR
    }
    tap_goto RUN_TEST_IDLE
    return $len
}

# ---------------------------------------------------------------------------
# tap_summary -- THE VERDICT LINE, and it exists because the obvious one is
# WRONG.
#
# FOUND BY THE AUTHOR'S OWN FAIL-LEG DEMONSTRATION (2026-08-06, HEAD f3d5172):
# running dbg_tapconf.tcl on a tree with no JTAG port printed
#
#     DMILOG TAP_PORT_ABSENT count=5 of 5
#     DMILOG VERDICT=INSTRUMENT_DEAD
#     DMILOG dbg_tapconf ALL CHECKS PASSED (0 checks)
#
# -- because d2_summary reports success whenever the failure count is zero, and
# zero checks have zero failures.  Any runner grepping for "ALL CHECKS PASSED"
# would have graded a build with NO DEBUG TRANSPORT AT ALL as a pass.  That is
# the same shape as a check that passes on correct RTL for the wrong reason,
# pointed the other way, and it would have been invisible until the day the
# port regressed.
#
# So: a D3 harness reports PASSED only if it ran at least `min` checks AND the
# transport was present.  Absent transport is reported as INSTRUMENT_DEAD, and
# INSTRUMENT_DEAD is not a pass.
# ---------------------------------------------------------------------------
proc tap_summary {tag present {min 1}} {
    if {!$present} {
        puts "DMILOG $tag INSTRUMENT_DEAD -- the JTAG transport is absent, so"
        puts "DMILOG   NOTHING WAS MEASURED.  This is not a pass and must never be"
        puts "DMILOG   greppable as one ($::D2_CHECKS checks ran)."
        flush stdout
        return
    }
    if {$::D2_CHECKS < $min} {
        puts "DMILOG $tag UNDER_RAN -- only $::D2_CHECKS checks executed, expected at least $min."
        puts "DMILOG   A harness that stopped early has not passed; it has stopped."
        flush stdout
        return
    }
    d2_summary $tag
}

# ---------------------------------------------------------------------------
# tap_cost -- print what the run actually cost in the subject's own units.
# ---------------------------------------------------------------------------
proc tap_cost {tag} {
    puts "DMILOG TAPCOST $tag tck_cycles=$::TAP_CYCLES scans=$::TAP_SCANS dmiresets=$::TAP_DMIRESETS idle_adv=$::TAP_IDLE_ADV dwell=$::TAP_IDLE_DWELL half=${::TAP_HALF_NS}ns setup=${::TAP_SETUP_NS}ns"
    flush stdout
}
