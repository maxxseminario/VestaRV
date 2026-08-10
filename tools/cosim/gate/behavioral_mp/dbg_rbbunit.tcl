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
puts [expr {$fails == 0 ? "RBB_UNIT: ALL PASSED (11 checks)" : "RBB_UNIT: FAILURES $fails"}]
