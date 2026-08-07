# =============================================================================
# dbg_trpact.tcl -- THE D4 PLANT-ON-DMACTIVE LEG, and the poison leg.
# d4_spec 1.1, and the named-optional "poison pattern standing in for silicon
# power-up garbage" of d4_spec 6 -- TAKEN, and taken IN BAND.
#
#   ./xrun_dbg_verify.sh verify_castaliadebug ../rcf/xxxxrv32ua-p-dbgtrpmp.rcf dbg_trpact.tcl
#
# BLIND-AUTHORED 2026-08-07 against d4_spec.md (FROZEN).  Committed polarity:
# CORRECT RTL = PASS.  No tcl force plants anything (the lib's guard enforces).
#
# WHAT IT ISOLATES, and why no hart may halt in this file
#   d4_spec 1 gives the plant TWO triggers.  An observation taken after a halt
#   cannot tell them apart.  So this leg halts NOTHING: it poisons the page in
#   band, raises dmactive, and then reads the page back with a RUNNING hart's
#   own loads.  A5 asserts, at the end, that the victim was running throughout
#   -- so the only mechanism that can have repaired the page is the dmactive
#   0->1 trigger.  dbg_tramp.tcl is the mirror image (poison AFTER dmactive,
#   observe after a halt), and the two verdicts together say WHICH trigger a
#   partial implementation is missing.
#
# THE POISON LEG, and why the behavioural zero-fill made it necessary
#   d4_probe's "could not measure" 5: the shared RAM model zero-fills, so an
#   unplanted page reads 0x00000000 and a plant that wrote nothing is
#   indistinguishable from a page nobody has touched.  Every expected-zero
#   needs independent proof the instrument was live (method rule 5).  Forcing
#   a poison pattern is not available -- a forced word is read-only, so the
#   plant under test could not overwrite it, and a deposit does not survive
#   (measured, dbg_bfm.tcl header).  The poison is therefore written BY A HART,
#   which is both the only mechanism that works and the closest behavioural
#   analogue of power-up garbage: real, non-zero, and overwritable.
#
# CHECKS (DMILOG; the runner greps for FAILED):
#   A0  the in-band poison landed on all 40 words (peek census)
#   A1  ...and the IN-BAND scan agrees: a running hart's own loads hash to the
#       all-poison hash.  This validates the in-band channel against a KNOWN
#       NONZERO before A2 asks it about the value that matters (method rule 4).
#   A2  THE HEADLINE: after dmactive 0->1, and with no hart ever halted, the
#       running hart's scan hashes to the built deliverable's hash, and its
#       word 0 and word 39 samples match it too
#   A3  ...and the RAM cells agree (corroboration)
#   A4  the page TAIL (words 57..63) still holds the image's mark
#   A5  no hart was ever halted in this leg -- dmstatus reports the victim
#       RUNNING, so A2 cannot be attributed to an on-halt plant
#
# AT 286921d (D4 UNIMPLEMENTED): A0 and A1 pass, A2 fails with the in-band scan
#   still hashing to the all-poison value and W0/W39 still reading 0x5EAD0000,
#   A3 reports 40/40 poison survivors, A5 passes.  The image fails 0x0D260010.
#   Nothing times out: the failure is a value, quoted.
#
# LIVENESS CONTROL (D4_CONTROL=1): the trampoline is force-planted after the
# poison and before dmactive, standing in for the dmactive plant.  Every check
# must pass.
# =============================================================================
source ../../disable_x_warnings.tcl
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }
if {[file exists dbg_tramp_lib.tcl]} { source dbg_tramp_lib.tcl } else { source ../behavioral_mp/dbg_tramp_lib.tcl }

set VICTIM 1

set PRESENT [dmi_present]
set WANT [d4_load_words]
if {[llength $WANT] == 0} {
    puts "DMILOG VERDICT=INSTRUMENT_DEAD (no content oracle)"
    d2_summary "dbgtrpmp/act"
    flush stdout
    exit
}
set WANT_HASH [d4_hash $WANT]
set POISON_PAGE {}
for {set n 0} {$n < 40} {incr n} { lappend POISON_PAGE $::D4_POISON }
set POISON_HASH [d4_hash $POISON_PAGE]
puts "DMILOG oracle hash=[format 0x%08X $WANT_HASH]  all-poison hash=[format 0x%08X $POISON_HASH]"
flush stdout

set ready [d4_wait_ready]

if {$PRESENT && $ready} {
    # ---- 1. poison the page BEFORE any debugger exists -------------------
    d4_cmd $::DBGTRP_CMD_POISON
    set c [d4_page_census $WANT]
    d4_report_census "A0" $c
    d2_chk [expr {[lindex $c 2] == 40}] \
        "A0: the in-band poison landed on all 40 entry-page words (poison=[lindex $c 2]/40)"

    set s1 [d4_inband_scan]
    d2_chk [expr {[lindex $s1 0] && [lindex $s1 1] == $POISON_HASH}] \
        "A1: the IN-BAND channel is live and correct against a KNOWN NONZERO -- a running hart's own loads hash to [format 0x%08X [lindex $s1 1]] (want the all-poison [format 0x%08X $POISON_HASH])"

    d4_control_plant

    # ---- 2. the trigger under test: dmactive 0 -> 1 ----------------------
    # Nothing else happens.  No haltreq, no command, no resethaltreq.
    d4_dmactive_on 0
    run 500 us

    # ---- 3. observe with a RUNNING hart ----------------------------------
    set s2 [d4_inband_scan]
    d2_chk [expr {[lindex $s2 0] && [lindex $s2 1] == $WANT_HASH}] \
        "A2: after dmactive 0->1 the RUNNING hart's own scan of 0x10780-0x1081F hashes to [format 0x%08X [lindex $s2 1]] (want the deliverable's [format 0x%08X $WANT_HASH])"
    d2_chk [expr {[lindex $s2 2] == [lindex $WANT 0] && [lindex $s2 3] == [lindex $WANT 39]}] \
        "A2b: ...and its word0/word39 samples are [format 0x%08X [lindex $s2 2]]/[format 0x%08X [lindex $s2 3]] (want [format 0x%08X [lindex $WANT 0]]/[format 0x%08X [lindex $WANT 39]])"

    set c2 [d4_page_census $WANT]
    d4_report_census "A3" $c2
    d2_chk [expr {[lindex $c2 0] == 40}] \
        "A3: ...and the RAM cells agree (match=[lindex $c2 0]/40, zero=[lindex $c2 1], poison=[lindex $c2 2])"

    set t [d4_tail_intact]
    d2_chk [lindex $t 0] \
        "A4: the page TAIL (words 57..63) still holds the image's mark (badword=[lindex $t 1] got=[lindex $t 2])"

    # ---- 4. the isolation assertion --------------------------------------
    dm_select $VICTIM
    set st [dmi_read $::DM_DMSTATUS]
    d2_chk [expr {$st >= 0 && [dms_allrunning $st] == 1 && [dms_anyhalted $st] == 0}] \
        "A5: the victim was NEVER halted in this leg (dmstatus [format 0x%08X $st]) -- so A2 can only be the dmactive-rise plant"
}

sh_force $::DBGTRP_REL 1
set verdict [d2_run_to_verdict 1600 "25 us"]
d2_report_verdict "dbgtrpmp/act" $verdict
puts "DMILOG PHASE=[sh_get $::DBGTRP_PHASE] RAN=[sh_get $::DBGTRP_RAN] CHK=[format 0x%08X [sh_get $::DBGTRP_CHK]]"
d2_summary "dbgtrpmp/act" 6
flush stdout
exit
