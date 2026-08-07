# =============================================================================
# dbg_trpheal.tcl -- THE D4 SELF-HEAL LEG.  d4_spec 1.2's promise, graded.
#
#   ./xrun_dbg_verify.sh verify_castaliadebug ../rcf/xxxxrv32ua-p-dbgtrpmp.rcf dbg_trpheal.tcl
#
# BLIND-AUTHORED 2026-08-07 against d4_spec.md (FROZEN).  Committed polarity:
# CORRECT RTL = PASS.  No tcl force plants anything.
#
# RE-SHAPED 2026-08-07 by the D4 VALIDATION wave under the instrument-owner
# pattern (R-D4-3(3), ordered; F-D4V-2).  WHAT CHANGED AND WHY -- read this
# before trusting any older quotation of this file's check numbers:
#
#   The first version graded the RESUME-PATH discriminator (word 34) AFTER the
#   self-heal headline (word 2).  Executing the sealed mutants proved that
#   placement cannot work.  Word 2 is executed on every entry, so a chip that
#   never re-plants on halt (M3) and a chip that re-plants only AFTER seeing
#   TOK_HALTED (M5) both leave the hart spinning on illegal-instruction
#   re-entry, unable to publish another token EVER -- and the entry page is
#   SHARED, so the damage is global and permanent (no later plant can repair
#   what hart_tile's M10 stale ack keeps re-serving; F-D4-1).  Everything
#   downstream was therefore graded on a hart that could not move: M3 and M5
#   came out INDISTINGUISHABLE across all eight D4 legs and all 71 checks, and
#   the sealed mutant set's own M5 note said in advance that if that happened,
#   the discrimination claim had to be withdrawn.  It has been.
#
#   Adding a precondition assertion in front of the old H8-H10 would only have
#   made the failure honest; it would not have restored the discrimination.
#   Nor would moving the second phase to a fresh ROM-parked hart -- the page is
#   shared, so a fresh hart wedges on the same word 2.  The fix is an ORDERING:
#   the word-34 phase now runs FIRST, off the clean planted page that H0-H2
#   have just proven intact, and the word-2 headline runs after it.  Proven on
#   three trees, not argued: pristine ok/ok, M5 ok/ok, M3 fails naming
#   firstbad=word34.
#
#   THE CHECKS ARE RENUMBERED.  Old -> new: H3->H7, H4->H8, H5->H9, H6->H10,
#   H7->H11, H8->H3, H9->H5, H10->H6.  H0/H1/H2 keep their meaning, and H4 is
#   NEW.  Count 11 -> 12.  The new check is not padding: the old H9 conflated
#   "the victim halted" with "the page healed" into one d2_chk, so a failed
#   halt was reported as a failed heal.  The word-34 phase now has its own halt
#   check and the discriminator grades one thing.
#
# THE CLAUSE, and why it is the ORDERING clause in disguise
#   d4_spec 1.2 promises that a corrupted page SELF-HEALS: "a hart halting into
#   garbage spins at zero retires via the F-D2-0 exception re-entry, the DM's
#   plant repairs the page, and the next re-entry executes real code, with NO
#   DMI action beyond normal use."  That promise is only true if the plant
#   happens BEFORE the DM consumes that hart's TOK_HALTED -- which is exactly
#   what the clause says and exactly what an implementation is likeliest to get
#   wrong, because "plant after the hart reports halted" reads just as natural
#   and is a DEADLOCK: the hart cannot report through a broken page, and the DM
#   will not repair it until it does.  So H9 is the ordering test, and it needs
#   no timing at all to be one: H9 either completes or the DM answers
#   cmderr = OTHER on its own 65535-mclk bound.  Both are values, not durations.
#
#   "NO DMI action beyond normal use" is enforced structurally: between the
#   word-2 corruption and H9 this harness issues exactly one haltreq and then
#   reads status.  There is no re-toggle of dmactive, no re-arming, no repair
#   poke.  (The word-34 phase before it is a separate scenario that ends with
#   the page proven intact again, which is what makes H9's precondition real.)
#
#   d4_spec 1.2's promise is scoped to words 1..39 (AMENDED R-D4-2(2), F-D4-1).
#   Both words this leg damages -- 2 and 34 -- are inside that scope.  Word 0 is
#   NOT healable under an already-halted hart on this core; that case is
#   published, not asserted, by dbg_tramp's P0.
#
# THE TWO CORRUPTIONS, and why they are chosen off structure rather than tuned
#   WORD 34 is `dret`, on the RESUME path -- reached only after the debugger
#   acts.  A hart halting into a page damaged THERE still executes words 0..33,
#   still reaches the token store at word 16, and still publishes TOK_HALTED.
#   So a DM that re-plants on halt at all -- in EITHER order -- repairs it,
#   and a DM with no on-halt re-plant does not.  That is the discrimination,
#   and it only works from a clean precondition, which is why it goes first.
#   WORD 2 is one of the unconditional dscratch/mhartid words every entry
#   executes, so the damage is certain to be hit rather than merely present.
#   Both are read off the deliverable's structure, not calibrated.
#
# CHECKS (DMILOG; the runner greps for FAILED):
#   H0  the victim halts (precondition)
#   H1  precondition: the page is planted -- 40/40 through the DM
#   H2  the victim resumes
#   -- phase A: the RESUME-PATH discriminator, off a clean page ---------------
#   H3  the in-band hart store corrupted word 34 ONLY, on the RESUME path
#   H4  the victim halts into that damage (its own check, not folded into H5)
#   H5  THE DISCRIMINATOR: it heals, 40/40 through the DM.  A chip with no
#       on-halt re-plant leaves word 34 broken and fails here naming it; a chip
#       that re-plants after the token still repairs it and PASSES here.  This
#       check separates those two.  It does NOT test the ordering -- H9 does.
#   H6  ...and the repaired `dret` resumes the hart
#   -- phase B: THE SELF-HEAL HEADLINE and the ordering ----------------------
#   H7  the in-band hart store corrupted word 2 (executed on every entry)
#   H8  the victim halts again into the DAMAGED page
#   H9  THE HEADLINE: with no DMI action beyond that haltreq, all 40 words read
#       back through the DM equal the deliverable again -- the page healed, and
#       the plant therefore preceded the token wait.  Had it followed, this is
#       a deadlock and the DM answers cmderr = OTHER.
#   H10 ...and the RAM cells agree
#   H11 the victim resumes again
#
# AT 286921d (D4 UNIMPLEMENTED): H0 passes, H1 fails with the DM's own
#   cmderr = OTHER (7) on an unplanted page, H3 and H7 pass (the corruptions
#   are real), H4 and H8 pass, H5/H9 fail the same way as H1.  The IMAGE fails
#   0x0D260010 with a2 = the number of poison survivors, because this leg's
#   own corruption writes the poison word -- PREDICTION MISS, recorded: the
#   first draft of this header said 0x0D260011 (the all-zero code), forgetting
#   that CMD_CORRUPT plants the same 0x5EAD0000 the poison command uses.
#
# LIVENESS CONTROL (D4_CONTROL=1): force-plant before H0, then release before
# each corruption and re-force before each subsequent halt -- a forced word is
# read-only, so a live force would silently drop the very store being graded.
# Every check must pass.
# =============================================================================
source ../../disable_x_warnings.tcl
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }
if {[file exists dbg_tramp_lib.tcl]} { source dbg_tramp_lib.tcl } else { source ../behavioral_mp/dbg_tramp_lib.tcl }

set VICTIM 1
set RESUME_WORD 34
set ENTRY_WORD  2

set PRESENT [dmi_present]
set WANT [d4_load_words]
if {[llength $WANT] == 0} {
    puts "DMILOG VERDICT=INSTRUMENT_DEAD (no content oracle)"
    d2_summary "dbgtrpmp/heal"
    flush stdout
    exit
}

set ready [d4_wait_ready]

if {$PRESENT && $ready} {
    d4_dmactive_on 0
    run 200 us
    d4_control_plant

    # ---- 1. a normal halt, and the precondition --------------------------
    dm_select $VICTIM
    dm_haltreq $VICTIM
    set s [dm_poll_status $VICTIM dms_allhalted 400 $::HALTREQ_BIT]
    dm_clr_haltreq $VICTIM
    d2_chk [expr {$s >= 0}] "H0: the victim halts (dmstatus [format 0x%08X $s])"

    set r1 [d4_dm_readback $WANT]
    d4_readback_report "H1" $r1 $WANT
    d2_chk [lindex $r1 0] \
        "H1: precondition -- the entry page is planted, 40/40 through the DM (read [lindex $r1 1]/40)"

    dm_resumereq $VICTIM
    set s2 [dm_poll_status $VICTIM dms_allrunning 400]
    d2_chk [expr {$s2 >= 0}] "H2: the victim resumes"

    # =====================================================================
    # PHASE A -- the RESUME-PATH discriminator, graded off the CLEAN page
    # H0-H2 have just proven intact.  This phase runs FIRST on purpose; see
    # the header.  Word 34 is `dret`: a hart halting into damage there still
    # reaches the token store at word 16, so it can still publish TOK_HALTED,
    # which is the premise the discrimination needs and which any earlier
    # word-2 damage would destroy for good.
    # =====================================================================
    d4_control_unplant

    d4_cmd $::DBGTRP_CMD_CORRUPT $RESUME_WORD
    set w1 [sh_get [expr {$::DBG_ENTRY_ADDR + 4*$RESUME_WORD}]]
    # "ONLY" is asserted as "exactly one word holds the POISON value", NOT as
    # "39 words still match the deliverable".  MEASURED DEFECT in this
    # re-shape's own first draft, 2026-08-07, caught by predicting mutant M1
    # before re-running it: M1 corrupts TRAMP word 37, so a match-against-the-
    # deliverable form would report 38/40 and fail here -- turning a TABLE
    # mutation into a false "the store hit the wrong word", and violating a
    # sealed MUST-PASS row that the old H8 satisfied.  A check on what THIS
    # STORE did must not depend on whether the table is correct.
    set c0 [d4_page_census $WANT]
    d2_chk [expr {$w1 == $::D4_POISON && [lindex $c0 2] == 1}] \
        "H3: the in-band hart store corrupted word $RESUME_WORD ONLY, on the RESUME path (reads [format 0x%08X $w1]; exactly [lindex $c0 2] word in the page holds the poison)"

    d4_control_plant

    dm_select $VICTIM
    dm_haltreq $VICTIM
    set s3 [dm_poll_status $VICTIM dms_allhalted 400 $::HALTREQ_BIT]
    dm_clr_haltreq $VICTIM
    d2_chk [expr {$s3 >= 0}] \
        "H4: the victim halts into the resume-path damage (dmstatus [format 0x%08X $s3]) -- its OWN check, so H5 grades the heal and nothing else"

    set r2 [d4_dm_readback $WANT]
    d4_readback_report "H5" $r2 $WANT
    set c1 [d4_page_census $WANT]
    d4_report_census "H5" $c1
    d2_chk [lindex $r2 0] \
        "H5: THE DISCRIMINATOR -- a halt into a page damaged ONLY on the RESUME path heals, 40/40 through the DM (read [lindex $r2 1]/40).  The hart could publish its token here, so a DM that re-plants on halt in EITHER order passes and a DM that never re-plants on halt fails, naming word $RESUME_WORD"

    set ran0 [sh_get $::DBGTRP_RAN]
    dm_resumereq $VICTIM
    set s4 [dm_poll_status $VICTIM dms_allrunning 400]
    run 500 us
    set ran1 [sh_get $::DBGTRP_RAN]
    d2_chk [expr {$s4 >= 0 && $ran1 > $ran0}] \
        "H6: ...and the repaired `dret` resumes the hart, which an unhealed word $RESUME_WORD could not ($ran0 -> $ran1)"

    # =====================================================================
    # PHASE B -- the SELF-HEAL headline and the ORDERING clause.  Word 2 is
    # executed on every entry, so a page broken here cannot publish a token
    # at all: a plant that FOLLOWS the token wait deadlocks and the DM
    # answers cmderr = OTHER on its own bound.  Two values, no duration.
    # This phase goes last because it can leave the hart wedged on any chip
    # that gets the ordering wrong, and nothing may be graded after that.
    # =====================================================================
    d4_control_unplant

    d4_cmd $::DBGTRP_CMD_CORRUPT $ENTRY_WORD
    set w2 [sh_get [expr {$::DBG_ENTRY_ADDR + 4*$ENTRY_WORD}]]
    d2_chk [expr {$w2 == $::D4_POISON}] \
        "H7: the in-band hart store corrupted word $ENTRY_WORD (reads [format 0x%08X $w2]) -- a word every entry executes"

    d4_control_plant

    # ---- one haltreq.  Nothing else. ------------------------------------
    dm_select $VICTIM
    dm_haltreq $VICTIM
    set s5 [dm_poll_status $VICTIM dms_allhalted 400 $::HALTREQ_BIT]
    dm_clr_haltreq $VICTIM
    d2_chk [expr {$s5 >= 0}] "H8: the victim halts again into the DAMAGED page (dmstatus [format 0x%08X $s5])"

    set r3 [d4_dm_readback $WANT]
    d4_readback_report "H9" $r3 $WANT
    d2_chk [lindex $r3 0] \
        "H9: THE SELF-HEAL -- with no DMI action beyond that haltreq, 40/40 words read back through the DM equal the deliverable again (read [lindex $r3 1]/40).  The plant therefore preceded the TOK_HALTED wait; had it followed, this would be a deadlock and the DM would answer cmderr=OTHER."

    set c2 [d4_page_census $WANT]
    d4_report_census "H10" $c2
    d2_chk [expr {[lindex $c2 0] == 40}] \
        "H10: ...and the RAM cells agree (match=[lindex $c2 0]/40, zero=[lindex $c2 1], poison=[lindex $c2 2])"

    dm_resumereq $VICTIM
    set s6 [dm_poll_status $VICTIM dms_allrunning 400]
    d2_chk [expr {$s6 >= 0}] "H11: the victim resumes again"
}

sh_force $::DBGTRP_REL 1
set verdict [d2_run_to_verdict 1600 "25 us"]
d2_report_verdict "dbgtrpmp/heal" $verdict
puts "DMILOG PHASE=[sh_get $::DBGTRP_PHASE] RAN=[sh_get $::DBGTRP_RAN]"
d2_summary "dbgtrpmp/heal" 12
flush stdout
exit
