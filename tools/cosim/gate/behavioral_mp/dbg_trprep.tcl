# =============================================================================
# dbg_trprep.tcl -- THE D4 RE-PLANT-ON-TOGGLE LEG.  d4_spec 1.3 and 6.
#
#   ./xrun_dbg_verify.sh verify_castaliadebug ../rcf/xxxxrv32ua-p-dbgtrpmp.rcf dbg_trprep.tcl
#
# BLIND-AUTHORED 2026-08-07 against d4_spec.md (FROZEN).  Committed polarity:
# CORRECT RTL = PASS.  No tcl force plants anything.
#
# THE CLAUSE.  d4_spec 1.3: "dmactive -> 0 clears the plant-done state ...
# Toggling dmactive is therefore a real re-plant."  d4_probe C4 measured why
# the clause has to be written down at all: the in-tree `epi_done`-class latch
# is cleared ONLY by `resetn` and is absent from the six registers the
# dmactive-write handler clears, so the natural implementation -- one more
# write-once latch beside epi_done -- gives a chip on which toggling dmactive
# does NOTHING.  That chip passes dbg_trpact.tcl and dbg_tramp.tcl and fails
# only here.
#
# THE CORRUPTION IS A HART STORE, as d4_spec 6 requires.  It is issued by the
# image's agent hart (dbgtrpmp.S, ta_corrupt): a real `sw` on a real hart
# through mp_arbiter.  Nothing here poisons by force -- a forced word is
# read-only and the plant under test could not repair it, so a force-corrupted
# page would test the opposite of what this leg is for.
#
# NO HART IS HALTED between the corruption and the observation.  That is the
# isolation: the on-halt trigger of d4_spec 1.2 is unavailable, so a repaired
# page can only be the dmactive rise.  R5 asserts it at the end.
#
# CHECKS (DMILOG; the runner greps for FAILED):
#   R0  precondition: after the FIRST dmactive rise the page is planted (in
#       band, running hart).  If this fails the leg below is unreachable and
#       says so -- it is dbg_trpact.tcl's finding, not this file's.
#   R1  the in-band corruption of word 5 landed (peek)
#   R2  ...and the in-band channel sees it too: the running hart's hash no
#       longer matches the deliverable.  A corruption only a peek can see
#       would not be a corruption the machine suffers.
#   R3  THE HEADLINE: after dmactive 1->0->1, and with no hart halted at any
#       point, the running hart's scan hashes to the deliverable again
#   R4  ...and the RAM cells agree
#   R5  no hart was halted during R0..R4 -- so R3 is the toggle and nothing else
#   R6  the FIRST abstract command after the toggle still works.  d4_spec 1.3
#       leaves it to the implementer whether the epilogue latch joins the
#       dmactive-0 clear, and requires the consequence to be measured either
#       way; this is that measurement, in the only form that matters to a
#       debugger -- an abstract GPR read on a freshly-toggled DM.
#   R7  ...and the victim resumes afterwards
#
# AT 286921d (D4 UNIMPLEMENTED): R0 fails first (nothing planted at all), and
#   the log says so with the page reading all zeros; R1/R2 still pass (the
#   corruption is real), R3 fails with the page still unplanted.  The image
#   fails 0x0D260010 with a2 = 1.  PREDICTION MISS, recorded: the first draft
#   of this header said 0x0D260011 (the all-zero code) on the reasoning that
#   this leg never runs CMD_POISON -- but CMD_CORRUPT writes the SAME
#   0x5EAD0000 word, so exactly one poison survivor is left and the poison
#   check fires first.  Measured: a1=0x0D260010 a2=0x00000001 a3=0x00000027
#   (39 zero words).  The a2/a3 pair still distinguishes the two situations,
#   which is what the code was for; the code itself does not.
#
# LIVENESS CONTROL (D4_CONTROL=1): force-plant before R0, release before the
# corruption, re-force after the toggle -- each step standing in for the RTL
# step it names.  Every check must pass.
# =============================================================================
source ../../disable_x_warnings.tcl
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }
if {[file exists dbg_tramp_lib.tcl]} { source dbg_tramp_lib.tcl } else { source ../behavioral_mp/dbg_tramp_lib.tcl }

set VICTIM 1
set CORRUPT_WORD 5

set PRESENT [dmi_present]
set WANT [d4_load_words]
if {[llength $WANT] == 0} {
    puts "DMILOG VERDICT=INSTRUMENT_DEAD (no content oracle)"
    d2_summary "dbgtrpmp/rep"
    flush stdout
    exit
}
set WANT_HASH [d4_hash $WANT]

set ready [d4_wait_ready]

if {$PRESENT && $ready} {
    d4_control_plant

    # ---- 1. first rise, and the precondition ------------------------------
    d4_dmactive_on 0
    run 500 us
    set s1 [d4_inband_scan]
    d2_chk [expr {[lindex $s1 0] && [lindex $s1 1] == $WANT_HASH}] \
        "R0: precondition -- after the first dmactive rise the page is planted (in-band hash [format 0x%08X [lindex $s1 1]], want [format 0x%08X $WANT_HASH])"

    d4_control_unplant

    # ---- 2. corrupt one word IN BAND -------------------------------------
    d4_cmd $::DBGTRP_CMD_CORRUPT $CORRUPT_WORD
    set w [sh_get [expr {$::DBG_ENTRY_ADDR + 4*$CORRUPT_WORD}]]
    d2_chk [expr {$w == $::D4_POISON}] \
        "R1: the in-band hart store corrupted word $CORRUPT_WORD (reads [format 0x%08X $w], want [format 0x%08X $::D4_POISON])"

    set s2 [d4_inband_scan]
    d2_chk [expr {[lindex $s2 0] && [lindex $s2 1] != $WANT_HASH}] \
        "R2: ...and the running hart sees the damage too (hash [format 0x%08X [lindex $s2 1]] != [format 0x%08X $WANT_HASH])"

    # ---- 3. the trigger under test: dmactive 1 -> 0 -> 1 ------------------
    d4_dmactive_off
    run 200 us
    d4_dmactive_on 0
    run 500 us

    d4_control_plant

    set s3 [d4_inband_scan]
    d2_chk [expr {[lindex $s3 0] && [lindex $s3 1] == $WANT_HASH}] \
        "R3: after dmactive 1->0->1 the page is planted AGAIN (in-band hash [format 0x%08X [lindex $s3 1]], want [format 0x%08X $WANT_HASH])"

    set c [d4_page_census $WANT]
    d4_report_census "R4" $c
    d2_chk [expr {[lindex $c 0] == 40}] \
        "R4: ...and the RAM cells agree (match=[lindex $c 0]/40, zero=[lindex $c 1], poison=[lindex $c 2])"

    dm_select $VICTIM
    set st [dmi_read $::DM_DMSTATUS]
    d2_chk [expr {$st >= 0 && [dms_allrunning $st] == 1 && [dms_anyhalted $st] == 0}] \
        "R5: no hart was halted anywhere in R0..R4 (dmstatus [format 0x%08X $st]) -- R3 is the toggle and nothing else"

    # ---- 4. the epilogue consequence, measured ---------------------------
    dm_haltreq $VICTIM
    set sh [dm_poll_status $VICTIM dms_allhalted 400 $::HALTREQ_BIT]
    dm_clr_haltreq $VICTIM
    if {$sh >= 0} {
        ac_clear_cmderr
        set r [d4_abs_read 0x1009]
        d2_chk [expr {[lindex $r 1] == 0}] \
            "R6: the FIRST abstract command after a dmactive toggle still works (cmderr=[lindex $r 1], x9 read [format 0x%08X [lindex $r 0]])"
        dm_resumereq $VICTIM
        set sr [dm_poll_status $VICTIM dms_allrunning 400]
        d2_chk [expr {$sr >= 0}] "R7: ...and the victim resumes afterwards"
    } else {
        d2_chk 0 "R6: the victim did not halt after the dmactive toggle, so the abstract-command measurement is unreachable"
        d2_chk 0 "R7: (unreachable -- see R6)"
    }
}

sh_force $::DBGTRP_REL 1
set verdict [d2_run_to_verdict 1600 "25 us"]
d2_report_verdict "dbgtrpmp/rep" $verdict
puts "DMILOG PHASE=[sh_get $::DBGTRP_PHASE] RAN=[sh_get $::DBGTRP_RAN] CHK=[format 0x%08X [sh_get $::DBGTRP_CHK]]"
d2_summary "dbgtrpmp/rep" 8
flush stdout
exit
