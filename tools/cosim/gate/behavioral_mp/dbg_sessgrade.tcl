# =============================================================================
# dbg_sessgrade.tcl -- THE FAIL LEG OF THE D5 SESSION GRADERS, and the file
# the implementer copies when they wire the graders around a real session.
#
#   ./xrun_dbg_verify.sh verify_castaliadebug ../kba/xrv32ua-p-dbgtrpmp.rcf dbg_sessgrade.tcl
#   ./xrun_dbg_verify.sh verify_argusdebug    ../kf0/xrv32ua-p-dbgtrpmp.rcf dbg_sessgrade.tcl
#
# BLIND-AUTHORED 2026-08-10 against d5_spec.md 5.2/5.4 (FROZEN).
#
# WHAT THIS RUN IS
#   A knob-ON chip, booted, running its image, with NO DEBUGGER ANYWHERE: no
#   bridge, no OpenOCD, no gdb, and -- deliberately -- not one DMI transaction
#   from this harness either.  It is the "debugger-less target" FAIL leg
#   d5_spec 8 asks for, and it is the natural one: nothing about a session can
#   be true in it.
#
#   It is ALSO the wiring template.  The implementer's own harness differs from
#   this file in exactly one way: where this file calls `run`, theirs calls the
#   bridge's serve loop, and the snapshots are taken at the same named points.
#
# WHAT MUST HAPPEN HERE (predicted before the first run):
#   SG-A  attach ............... FAIL  (entry page 0/40 both sides)
#   SG-B  hart census .......... FAIL  (no hart ever published TOK_HALTED)
#   SG-Ca halt-one victim ...... FAIL  (nothing ever halted)
#   SG-Cb victim zero-retire ... FAIL when the victim has a LIVE counter (it is
#                                running, so the counter MOVES), NOT-GRADED when
#                                the profile has none
#   SG-Cc others keep running .. **PASS**, and that is the point: it is this
#                                file's known-nonzero control.  A FAIL leg in
#                                which every clause fails has only proved the
#                                instrument noticed an idle chip.
#   SG-D/E cookie writes ....... FAIL  (cookie absent before AND after)
#   SG-F  memory write ......... NOT-GRADED under the dbgtrpmp profile
#   SG-G  sw breakpoint ........ FAIL  (no ebreak was planted)
#   SG-H  stepi ................ FAIL  (dpc did not move to the next address)
#   SG-I  resume ............... FAIL  (nothing was halted to resume)
#   SG-J  reset-halt ........... FAIL  (no tile was gated, nothing halted)
#   SG-K  msip wedge/rescue .... FAIL  (the wedge was never walked into)
#   SG-L  sticky clear ......... **PASS** -- the DTM is untouched, so dmistat
#                                is 00.  An OBSERVATION grader, correctly green
#                                on a chip nobody has scanned; it earns its
#                                keep only across a real session.
#
# TWO GRADERS PASS IN THE FAIL LEG AND BOTH ARE DECLARED ABOVE, IN ADVANCE.
# That is the discipline: a grader that cannot pass here is not thereby
# stronger, and one that can must say so before it does.
#
# ---------------------------------------------------------------------------
# WHAT THE FIRST RUNS ACTUALLY MEASURED, AND THE FOUR PREDICTION MISSES.
# Kept verbatim rather than folded into the table above, because a prediction
# quietly widened afterwards is not a prediction.
#
#  MISS 1 (harness): the first draft ran 3 ms instead of waiting for READY, so
#         every snapshot was taken with the tiles still parked in the boot ROM.
#         SG-Cc -- the known-nonzero control -- FAILED (h1:0->0) instead of
#         passing.  A FAIL leg whose control does not fire proves much less
#         than it appears to.  Fixed with d4_wait_ready; the control now reads
#         h1:592->978.
#  MISS 2 (grader SG-Cb): PASSED on the parked chip.  "counter unchanged across
#         the halt window" is satisfied perfectly by a counter frozen at 0.
#         SG-Cb is now an ordering over THREE snapshots -- advancing before,
#         unchanged across -- and correctly FAILS here.
#  MISS 3 (graders SG-G3, SG-I2): both PASSED on the running chip, because
#         "the counter advanced between two snapshots" is free on any hart
#         nobody halted.  Both now carry an explicit halted precondition.
#  MISS 4 (graders SG-K2, SG-K3): both PASSED on a chip where nothing had
#         happened -- msip reads 0 for free and no hart is in TRAP_STATE for
#         free.  K2 is now an ORDERING (set, then cleared) and K3 is
#         NOT-GRADED unless the caller states the wedge was reached.
#
# ALL FOUR ARE THE SAME DEFECT CLASS: a clause of the form "X did not happen"
# or "Y advanced" is vacuous without a precondition establishing the subject
# was in the state that makes it meaningful.  Every one of them was invisible
# from the graded direction and was found by running the instrument in the
# direction where it is supposed to succeed.
#
# NEVER pipe the runner through `head`.
# =============================================================================
source ../../disable_x_warnings.tcl
if {[file exists dbg_sess_lib.tcl]} { source dbg_sess_lib.tcl } else { source ../behavioral_mp/dbg_sess_lib.tcl }

set N $::D5_NHARTS
puts "DMILOG ================ dbg_sessgrade: the DEBUGGER-LESS FAIL LEG ================"
puts "DMILOG   NHARTS=$N profile=$::D5_PROFILE"
puts "DMILOG   No bridge, no OpenOCD, no gdb, and no DMI transaction from this harness."
flush stdout

sess_probe_report

# ---- let the image boot and LAUNCH ITS TILES -------------------------------
# d4_wait_ready is the established idiom and it is REQUIRED, not decorative:
# dbgtrpmp's hart 0 SPI-copies the image, launches harts 1 and 2, waits for
# hart 1's counter to move, and only then publishes READY.  MEASURED
# 2026-08-10: a first draft that simply ran 3 ms took all its snapshots while
# every tile was still parked in the boot ROM, and the known-nonzero control
# below (SG-Cc) therefore FAILED instead of passing -- a FAIL leg in which the
# control does not fire proves much less than it looks like it proves.
if {![d4_wait_ready]} {
    puts "DMILOG dbg_sessgrade: the image never reached READY -- the FAIL leg below"
    puts "DMILOG   would be measuring a parked chip rather than a running one."
    flush stdout
}

# The ONLY `run` calls in this file.  In the implementer's version the session
# happens between these snapshots instead.
sess_snap A0
run 300 us
sess_snap A1
run 300 us
sess_snap A2

# ---------------------------------------------------------------------------
# Every grader, called exactly as the implementer will call it.
# ---------------------------------------------------------------------------
sess_grade_attach A0 A1
sess_grade_hartcensus A1 [list 1 2]

# victim 2 / others {1}: exercises SG-Ca (fails: nothing halted) and SG-Cc
# (PASSES: hart 1's counter really is advancing -- the known-nonzero control)
sess_grade_halt_one A0 A1 A2 2 [list 1]
# victim 1 / others {2}: exercises SG-Cb (fails: a RUNNING hart's counter moves
# across the window, which is what the three-snapshot form was built to catch)
sess_grade_halt_one A0 A1 A2 1 [list 2]

sess_grade_gpr_write A0 A1 1
sess_grade_csr_write A0 A1 1
sess_grade_mem_write A0 A1

# The breakpoint site.  In a real run bpaddr and origword come off objdump of
# the session image at a labelled site (method rule 7).  Here they are the
# tile entry 0x8000 and the word actually there, so G1 fails on the ebreak
# clause and NOT on the site clause -- which is what makes this FAIL leg a
# statement about "no breakpoint was planted" rather than about a bad address.
set BP 0x8000
set PREV [sess_tcm_word 1 $BP]
sess_grade_swbp $PREV A1 A2 1 $BP $PREV

sess_grade_step A1 A2 1 0x00008004
sess_grade_resume A1 A2 1
sess_grade_reset_halt A0 A1 A2 2
set wedged [sess_grade_msip_wedge A1 A2 2]
sess_grade_msip_rescue A1 A2 A2 2 $wedged
sess_grade_sticky "end of a session-less run"

sess_oracle_dump 1 [list 0x10050 0x10054 0x10074]

set verdict [d2_run_to_verdict 800 "25 us"]
d2_report_verdict "dbg_sessgrade" $verdict
foreach h [list 1 2 3] { puts "DMILOG   hart$h state=[d2_state $h]" }
sess_grade_summary "dbg_sessgrade" 15
flush stdout
exit
