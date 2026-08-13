# =============================================================================
# dbg_rbbunit.tcl -- unit proof for the BRIDGE'S DECODE SHADOW (the TAP FSM,
# the IR, and the request/response DR that give the heartbeat its `dmiresets`
# and its TARGET-WEDGE observable).
#
# Runs in a STANDALONE tclsh, not in xmsim -- it stubs `force`/`value`/`run`
# and drives rbb_fsm_edge directly, so it needs no simulator, no license and
# no elaboration:
#
#   cd xcelium/riscv_test/behavioral_mp
#   $XCELIUM_HOME/tools.lnx86/tcltk-8.6.8/bin/64bit/tclsh8.6 dbg_rbbunit.tcl
#
# BAR: `RBB_UNIT: ALL PASSED (11 checks)`.
#
# WHY IT EXISTS, and it is not ceremony -- it caught two real defects in the
# bridge before the bridge ever touched the chip:
#
#   1. The TAP state ordinals were hard-coded and ALL FOUR WERE WRONG
#      (SHIFT_DR is 4, not 2).  Now looked up from dbg_tap.tcl's own
#      ::TAP_NAMES so the bridge and the BFM cannot disagree about the graph.
#
#   2. `switch -- $::RBB_IR $::IR_DMI {...}` compared STRINGS: the shifted IR
#      is the integer 17 while $::IR_DMI is the literal "0x11", so every scan
#      fell through to `default` and EVERY DR WAS SIZED AS BYPASS.  The
#      transport would have worked perfectly and every diagnostic would have
#      been silently empty -- dmiresets pinned at 0, which reads as "the
#      transport never had to recover".  That is exactly the F1
#      false-reassurance class.
#
# THE SECOND ONE IS WHY EVERY CHECK BELOW ASSERTS A KNOWN-NONZERO VALUE
# (method rule 4): reassemble one SPECIFIC 41-bit DMI request, detect one
# SPECIFIC dtmcs DMIRESET.  A test that only asserted "dmiresets == 0 on a
# clean scan" would have PASSED on the broken code.
#
# A third defect was found in THIS FILE rather than in the bridge -- a walk
# from UPDATE_DR that lands in SHIFT_IR, not SHIFT_DR -- and is recorded in
# place below rather than silently corrected.
# =============================================================================
proc force args {}; proc value args {return '0'}; proc run args {}; proc tap_run {ns} {}
proc tap_bit {v} { return 0 }
set ::TAP_NAMES {TEST_LOGIC_RESET RUN_TEST_IDLE SELECT_DR_SCAN CAPTURE_DR SHIFT_DR EXIT1_DR PAUSE_DR EXIT2_DR UPDATE_DR SELECT_IR_SCAN CAPTURE_IR SHIFT_IR EXIT1_IR PAUSE_IR EXIT2_IR UPDATE_IR}
set ::TAP_NEXT {{1 0} {1 2} {3 9} {4 5} {4 5} {6 8} {6 7} {4 8} {1 2} {10 0} {11 12} {11 12} {13 15} {13 14} {11 15} {1 2}}
proc tap_sidx {n} { lsearch -exact $::TAP_NAMES $n }
set ::IR_IDCODE 0x01; set ::IR_DTMCS 0x10; set ::IR_DMI 0x11; set ::IR_BYPASS 0x1F
set ::DRLEN_IDCODE 32; set ::DRLEN_DTMCS 32; set ::DRLEN_DMI 41; set ::DRLEN_BYPASS 1
set ::TAP_TCK a; set ::TAP_TMS b; set ::TAP_TDI c; set ::TAP_TDO d; set ::TAP_TRSTN e
set ::TAP_WATCH_READY 0
source dbg_rbb_bridge.tcl
proc edge {tms {tdi 0}} { rbb_fsm_edge $tms $tdi }
set fails 0
proc chk {cond msg} { if {[uplevel 1 [list expr $cond]]} { puts "  ok   $msg" } else { puts "  FAIL $msg" ; incr ::fails } }
set ::RBB_ST 0
foreach t {0 1 1 0 0} { edge $t }
chk {$::RBB_ST == 11} "TLR->Shift-IR walk lands in SHIFT_IR (got [lindex $::TAP_NAMES $::RBB_ST])"
foreach b {1 0 0 0} { edge 0 $b }
edge 1 1
chk {$::RBB_IR == 0x11} "IR shadow = 0x11 IR_DMI (got [format 0x%02X $::RBB_IR])"
edge 1 ; edge 1 ; edge 0 ; edge 0
chk {$::RBB_ST == 4}     "walk lands in SHIFT_DR"
chk {$::RBB_DRN == 41}   "DR sized 41 for IR_DMI (got $::RBB_DRN)  <-- the string-vs-int bug"
set dr [expr {2 | (0xDEADBEEF << 2) | (0x10 << 34)}]
for {set i 0} {$i < 40} {incr i} { edge 0 [expr {($dr >> $i) & 1}] }
edge 1 [expr {($dr >> 40) & 1}]
edge 1
chk {$::RBB_DR == $dr}   "41-bit DMI request reassembled: [format 0x%011X $::RBB_DR] == [format 0x%011X $dr]"
chk {$::RBB_DMI_XACT == 1} "dmi_xact counted the write (got $::RBB_DMI_XACT)"
chk {$::RBB_DMIRESETS == 0} "no spurious dmireset from a DMI scan (got $::RBB_DMIRESETS)"
# Load IR = DTMCS properly (walk to Shift-IR, shift 0x10 = 10000b LSB-first),
# then walk UPDATE_IR -> SELECT_DR -> CAPTURE_DR -> SHIFT_DR.  The first draft
# of THIS TEST poked ::RBB_IR directly and then walked 1,1,0,0 from UPDATE_DR,
# which lands in SHIFT_IR, not SHIFT_DR -- so DRN correctly stayed 41 and the
# TEST was wrong, not the bridge.  Recorded rather than silently corrected.
edge 1 ; edge 1 ; edge 0 ; edge 0
chk {$::RBB_ST == 11} "walk lands in SHIFT_IR to load a new IR"
foreach b {0 0 0 0} { edge 0 $b }
edge 1 1
chk {$::RBB_IR == 0x10} "IR shadow = 0x10 IR_DTMCS (got [format 0x%02X $::RBB_IR])"
edge 1
edge 1 ; edge 0 ; edge 0
chk {$::RBB_ST == 4}     "walk lands in SHIFT_DR for the dtmcs scan"
chk {$::RBB_DRN == 32}   "DR sized 32 for IR_DTMCS (got $::RBB_DRN)"
set d2 [expr {1 << 16}]
for {set i 0} {$i < 31} {incr i} { edge 0 [expr {($d2 >> $i) & 1}] }
edge 1 [expr {($d2 >> 31) & 1}]
edge 1
chk {$::RBB_DMIRESETS == 1} "dmireset (dtmcs bit 16) DETECTED -- the known-nonzero leg (got $::RBB_DMIRESETS)"

# =============================================================================
# THE RE-ENTRANCY LEG (added 2026-08-10, ordered by Fable after the defect it
# proves was found on the chip).  THE THIRD REAL DEFECT THIS FILE HAS CAUGHT,
# and the only one that had already reached silicon-facing measurements.
#
# WHAT THE DEFECT WAS.  rbb_process advances simulation time (`run`) from
# inside a socket fileevent callback, and MEASURED IN XCELIUM, `run` PUMPS THE
# TCL EVENT LOOP: a real attach counted 763,700 re-entries of the rbb callback
# in a 36,044-TCK session.  Before the guard, each of those re-entered
# rbb_process and interleaved a second chunk's pin-sets with the first one's,
# MID-SCAN.  The result is not a crash and not a hang -- it is a handful of
# scrambled bits in a session whose every counter looks healthy, so it reads
# as a chip returning garbage.  It cost a wave of chip-side hypotheses (an
# image blamed for bus load, a CDC contract blamed for marginality, a force
# blamed for silently failing -- all three refuted by measurement) before the
# transport itself was suspected.
#
# WHY THE ASSERTIONS BELOW ARE SPECIFIC VALUES AND NOT "no errors" (rule 4).
# The interleaved chunk performs a COMPLETE IR load to BYPASS.  On the broken
# code that lands in the shadow as the SPECIFIC value 0x1F while the outer
# 41-bit request is destroyed; on the fixed code the IR is untouched at the
# SPECIFIC value 0x11 and the request reassembles EXACTLY.  A test asserting
# only "the DR is not corrupt" would pass on code that never re-entered at
# all, which is why R4 asserts the deferral counter is NONZERO: the hazard
# must be shown to have HAPPENED and been ABSORBED, not merely to be absent.
# R5 then proves the guard DEFERS rather than DROPS -- a guard that lost the
# bytes would pass R1-R4 and silently truncate every real session.
#
# The two legs differ in ONE line, and it is the line the fix added: the
# pre-fix model re-enters via rbb_process (which is what rbb_on_rbb used to
# do), the post-fix model re-enters via the guarded rbb_on_rbb.  BOTH legs
# enter from the OUTSIDE through rbb_on_rbb, and that is not cosmetic --
# A FOURTH DEFECT, IN THIS FILE RATHER THAN IN THE BRIDGE, is recorded here
# rather than silently corrected (the same treatment as the UPDATE_DR walk
# above): the first draft made the OUTER call `rbb_process` in both legs, so
# ::RBB_INCB was never set, the guard had nothing to guard, and the post-fix
# leg measured reentry=0 and a corrupted DR -- i.e. it reported the FIX as
# broken when the TEST was.  R4's nonzero assertion is what exposed it; a leg
# asserting only "the DR reassembled" would have been a silent false alarm.
# =============================================================================
proc fakech {cmd args} {
    switch -- $cmd {
        initialize { return {initialize finalize watch read write configure cget cgetall blocking} }
        finalize   -
        watch      -
        blocking   -
        configure  { return }
        cget       { return "" }
        cgetall    { return "" }
        read {
            lassign $args ch count
            if {[string length $::FEED] == 0} { return -code error EAGAIN }
            set n [expr {$count < [string length $::FEED] ? $count : [string length $::FEED]}]
            set r [string range $::FEED 0 [expr {$n - 1}]]
            set ::FEED [string range $::FEED $n end]
            return $r
        }
        write { lassign $args ch data ; return [string length $data] }
    }
}
# one remote_bitbang TCK: the low phase carries tms/tdi, then the rising edge
proc rb {tms tdi} {
    return [format %c%c [expr {48 + ($tms << 1) + $tdi}] [expr {48 + 4 + ($tms << 1) + $tdi}]]
}
proc rb_tms {seq} { set s "" ; foreach t $seq { append s [rb $t 0] } ; return $s }
proc rb_ir {ir} {
    set s ""
    for {set k 0} {$k < 5} {incr k} { append s [rb [expr {$k == 4}] [expr {($ir >> $k) & 1}]] }
    return $s
}

set ::R1 [expr {2 | (0xCAFEBABE << 2) | (0x11 << 34)}]
set ::OUTER "[rb_tms {1 1 1 1 1}][rb_tms {0 1 1 0 0}][rb_ir 0x11][rb_tms {1 1 0 0}]"
for {set i 0} {$i < 40} {incr i} { append ::OUTER [rb 0 [expr {($::R1 >> $i) & 1}]] }
append ::OUTER [rb 1 [expr {($::R1 >> 40) & 1}]][rb_tms {1}]
# a complete, self-contained IR load to BYPASS, entered from mid-Shift-DR
set ::NESTED "[rb_tms {1 1 1 1 0 0}][rb_ir 0x1F][rb_tms {1}]"

proc rbb_reset_state {} {
    set ::RBB_ST 0 ; set ::RBB_IR $::IR_IDCODE ; set ::RBB_DR 0 ; set ::RBB_DRN 1
    set ::RBB_DRO 0 ; set ::RBB_DROB 0 ; set ::RBB_TCK 0 ; set ::RBB_TCKV 0
    set ::RBB_TMSV 0 ; set ::RBB_TDIV 0 ; set ::RBB_BUSY 0 ; set ::RBB_INCB 0
    set ::RBB_REENTRY 0 ; set ::RBB_PENDING 0 ; set ::RBB_DONE 0
    set ::INJECTED 0
}
# The injector IS the model of Xcelium pumping the event loop inside `run`.
proc tap_run {ns} {
    if {!$::INJECTED && $::RBB_TCK >= 40} {
        set ::INJECTED 1
        append ::FEED $::NESTED
        $::REENTER_VIA $::CH
    }
}

foreach {leg via} {PRE-FIX rbb_process POST-FIX rbb_on_rbb} {
    set ::CH [chan create {read write} fakech]
    fconfigure $::CH -translation binary -buffering full -blocking 0
    set ::REENTER_VIA $via
    rbb_reset_state
    set ::FEED $::OUTER
    rbb_on_rbb $::CH
    if {$leg eq "PRE-FIX"} {
        chk {$::RBB_IR == 0x1F} "R1 PRE-FIX: the interleaved chunk's IR load took effect MID-SCAN -- IR shadow is 0x1F BYPASS (got [format 0x%02X $::RBB_IR]).  This is the corruption, reproduced"
        chk {$::RBB_DR != $::R1} "R2 PRE-FIX: the outer 41-bit request did NOT reassemble ([format 0x%011X $::RBB_DR] != [format 0x%011X $::R1]) -- a scrambled scan in a session whose counters all look healthy"
    } else {
        chk {$::RBB_DR == $::R1} "R3 POST-FIX: the outer 41-bit request reassembled EXACTLY across the re-entrancy ([format 0x%011X $::RBB_DR]) and the IR shadow is untouched at [format 0x%02X $::RBB_IR]"
        chk {$::RBB_REENTRY > 0} "R4 POST-FIX: the hazard OCCURRED and was ABSORBED -- reentry=$::RBB_REENTRY.  A zero here would mean the leg proved nothing but that nothing happened"
        # Tcl's fileevent is level-triggered, so the deferred bytes are re-offered
        # as soon as the outer call returns.  Model that, and prove the guard
        # DEFERS rather than DROPS: a guard that lost them would pass R3 and R4.
        #
        # THE ASSERTION IS BYTE CONSUMPTION, NOT WHAT THE BYTES MEAN, and the
        # first draft got this wrong -- recorded, not silently corrected.  It
        # asserted the re-offered chunk would load IR 0x1F, but that chunk is a
        # walk written to start from mid-Shift-DR; replayed from Update-DR
        # (where the outer scan ends) the same TMS sequence lands in
        # Run-Test/Idle and loads nothing, so the check FAILED on a guard that
        # was working perfectly.  Deferral is a statement about bytes, so the
        # check is about bytes.
        set before_in $::RBB_BYTES_IN
        rbb_on_rbb $::CH
        chk {($::RBB_BYTES_IN - $before_in) == [string length $::NESTED] && $::FEED eq ""} \
            "R5 POST-FIX: the deferred chunk was NOT LOST -- all [string length $::NESTED] byte(s) were consumed on the re-offer (delta=[expr {$::RBB_BYTES_IN - $before_in}], feed empty=[expr {$::FEED eq {}}]).  A guard that DROPPED them would pass R3 and R4 and silently truncate every real session"
    }
    catch {close $::CH}
}
proc tap_run {ns} {}

puts [expr {$fails == 0 ? "RBB_UNIT: ALL PASSED (16 checks)" : "RBB_UNIT: FAILURES $fails"}]
