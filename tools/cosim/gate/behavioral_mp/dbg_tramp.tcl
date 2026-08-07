# =============================================================================
# dbg_tramp.tcl -- THE D4 PLANT DETECTOR.  d4_spec 1.2 and 6, bullet 1.
#
#   ./xrun_dbg_verify.sh verify_castaliadebug ../rcf/xxxxrv32ua-p-dbgtrpmp.rcf dbg_tramp.tcl
#
# BLIND-AUTHORED 2026-08-07 against d4_spec.md (FROZEN) by an agent that has
# not seen and will never see the D4 implementation.  Committed polarity
# (R-K5-8): CORRECT RTL = PASS.  NO tcl force plants anything here -- the
# no-force guard in dbg_tramp_lib.tcl makes that a run-failing offence rather
# than a promise.
#
# WHAT IT ISOLATES.  The page is poisoned IN BAND (a running hart's stores)
# AFTER dmactive has already risen, so whatever the dmactive-rise plant did is
# destroyed before anything is graded.  The only mechanism left that can put
# the trampoline back is d4_spec 1.2: "on any hart's dbg_halted rising edge the
# DM re-streams the trampoline BEFORE consuming that hart's TOK_HALTED".  So a
# chip that plants only at dmactive fails T2 here and passes dbg_trpact.tcl,
# and the pair of results names which trigger is missing.
#
# -----------------------------------------------------------------------------
# THE POISON IS SCOPED TO WORDS 1..39, AND THAT IS A MEASUREMENT, NOT A RETREAT
# (re-shaped 2026-08-07 by the D4 VALIDATION wave under the instrument-owner
#  pattern -- R-D4-2(2), F-K2b-1 via succession; d4_spec 1.2 AS AMENDED)
#
#   The first draft of this leg poisoned all 40 words, and it read 5/7 on a
#   CORRECT implementation.  The cause is not the Debug Module: hart_tile's M10
#   same-word ack hold (`sh_acked_addr`) exists so that a `j .` self-loop re-uses
#   its held word instead of re-arbitrating, and a hart that halts into a page
#   whose FIRST word is illegal asks for that same word forever -- exception,
#   re-entry at DEBUG_ENTRY_ADDR, same address, ack still held.  The DM's repair
#   lands in the RAM underneath and the hart never sees it.  Measured directly at
#   the tile boundary with the RAM already repaired: rdata_reg=0x5EAD0000 while
#   cell0=0x7B241073, and measured TRIGGER-INDEPENDENT (an eager on-halt arm that
#   completed before the harness could sample changed nothing).  Ruled F-D4-1, a
#   NAMED D5 CARRYOVER, and d4_spec 1.2 now scopes the self-heal promise to words
#   1..39.
#
#   So this leg grades the scenario the design actually promises.  It does NOT
#   weaken clause 1.2a: the poison still lands AFTER dmactive, so all 39 poisoned
#   words can be repaired by exactly one mechanism -- the on-halt re-plant -- and
#   T2 still compares ALL FORTY against the deliverable.  Word 0 being left alone
#   creates no second repair path for words 1..39; it only removes the one word
#   whose repair this CORE cannot deliver to a halted hart.
#
#   The word-0 scenario is not dropped, it is DEMOTED: check P0 below runs it on
#   every graded run and PUBLISHES the result without asserting on it.  An
#   instrument keyed on a known hole must not report zero and read as success
#   (method rule 11), and when D5 closes the ack hold this probe is already in
#   place to notice.
#
# WHY THE READBACK IS THE GRADED CHANNEL (d4_probe P7, method rule 11)
#   A plant that silently did nothing is invisible to every pre-D4 harness.  A
#   tcl peek of the RAM cells would see the words, but a peek cannot tell the
#   design's own visibility from the simulator's: the criterion d4_spec 6 sets
#   is that the DM must be able to SHOW you the planted words.  So T2 makes the
#   DM drive the halted victim through a progbuf `lw` of each of the 40 words
#   and reads each one back over DMI as a GPR.  Every link in that chain -- the
#   master engine that planted it, the hart's load, the abstract sequence, the
#   DMI response -- is the design's.  The peek census (T3) corroborates and
#   diagnoses; it never grades alone.
#
# CHECKS (DMILOG; the runner greps for FAILED):
#   T0  the in-band poison LANDED: entry-page words 1..39 read 0x5EAD0000, all
#       thirty-nine of them, and word 0 does NOT (the scoping is asserted, not
#       assumed -- a poison loop that silently ran from the wrong base would
#       otherwise make T2 pass for the wrong reason).
#       This is the known-nonzero validation of the whole measurement (method
#       rule 4): every other check below is a comparison against the built
#       deliverable, and a channel that has only ever been asked about a value
#       it agrees with has not been shown to disagree with anything.
#   T1  the victim halts on haltreq (precondition; independent of the plant --
#       a hart halts into an unplanted page perfectly well, it just cannot do
#       anything afterwards)
#   T2  THE HEADLINE: all 40 words read back THROUGH THE DM equal the built
#       software/dbg_trampoline/bin/dbg_trampoline.words, word for word
#   T3  ...and the RAM cells agree (corroboration, and the diagnosis when T2
#       fails: zero page vs surviving poison vs wrong content)
#   T4  the page TAIL (words 57..63) still holds the image's mark -- the plant
#       wrote words 0..39 and did not walk into the DM's own area
#   T5  the halted victim retired NOTHING while all of that happened (its
#       liveness counter is frozen across the readback)
#   T6  resume puts it back to running, and the counter moves again
#
#   P0  PUBLISHED, NOT ASSERTED (no d2_chk, no effect on the verdict): the same
#       scenario re-run against WORD 0.  Corrupt word 0 in band, halt the victim,
#       and report what the DM readback answers next to what the RAM cell holds.
#       On this core the expected publication is exactly the F-D4-1 signature --
#       cell0 repaired, readback cmderr=OTHER(7) -- because the hart is holding a
#       stale ack for an address it never stops asking for.  It is here so the
#       hole stays under observation and so the day it closes is a visible event.
#       Skipped under D4_CONTROL=1, where the forced page is read-only and the
#       corruption could not land in the first place.
#
# AT 286921d (D4 UNIMPLEMENTED) the expected failure is NOT a timeout shrug:
#   T0 passes (the poison lands), T1 passes (the hart halts), and T2 fails with
#   the DM's own answer -- cmderr = OTHER (7), which debug_module.vhd's S_WAITH
#   bound exists to produce and whose comment names "an unplanted entry page"
#   as the case it is there to catch.  T3 then reports 39 poison survivors and
#   a zero word 0.  The image fails 0x0D260010.
#
# LIVENESS CONTROL: run with D4_CONTROL=1 in the environment.  The trampoline
# is planted by tcl force at the point where the DM's on-halt plant would fire
# -- after the poison, before the halt -- and every check must PASS.  That arm
# proves the instrument is capable of passing; it is not a graded leg and says
# so in its own log.
# =============================================================================
source ../../disable_x_warnings.tcl
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }
if {[file exists dbg_tramp_lib.tcl]} { source dbg_tramp_lib.tcl } else { source ../behavioral_mp/dbg_tramp_lib.tcl }

set VICTIM 1

set PRESENT [dmi_present]
set WANT [d4_load_words]
if {[llength $WANT] == 0} {
    puts "DMILOG VERDICT=INSTRUMENT_DEAD (no content oracle -- see D4_WORDS_* above)"
    d2_summary "dbgtrpmp/tramp"
    flush stdout
    exit
}
puts "DMILOG oracle: 40 words, hash=[format 0x%08X [d4_hash $WANT]] word0=[format 0x%08X [lindex $WANT 0]] word39=[format 0x%08X [lindex $WANT 39]]"
flush stdout

set ready [d4_wait_ready]

if {$PRESENT && $ready} {
    # ---- 1. raise dmactive, then destroy whatever it planted --------------
    d4_dmactive_on 0
    run 200 us

    # Words 1..39 only, one CMD_CORRUPT per word.  CMD_POISON is the image's
    # all-40 loop and is NOT used here: the image is a frozen, byte-pinned
    # deliverable (md5 989edff15030068039046f8cd43b83f6, and the N=18 build is
    # byte-identical to it), so the scoping is done by driving the command the
    # image ALREADY has -- a real store, on a real hart, through the real
    # arbiter, thirty-nine times -- rather than by rebuilding the image.  Each
    # d4_cmd is an ORDERING (the agent echoes SEQ into ACK), never a delay.
    set ncorrupt 0
    for {set n 1} {$n < $::D4_TRAMP_WORDS} {incr n} {
        if {[d4_cmd $::DBGTRP_CMD_CORRUPT $n]} { incr ncorrupt }
    }
    puts "DMILOG T0 in-band corrupt commands acknowledged: $ncorrupt/39 (words 1..39)"
    flush stdout

    set c [d4_page_census $WANT]
    d4_report_census "T0" $c
    set w0 [sh_get $::DBG_ENTRY_ADDR]
    puts "DMILOG T0 word0 (deliberately NOT poisoned -- F-D4-1 scoping) = [format 0x%08X $w0]"
    flush stdout
    d2_chk [expr {[lindex $c 2] == 39 && $w0 != $::D4_POISON}] \
        "T0: the in-band poison landed on entry-page words 1..39 and ONLY those (poison=[lindex $c 2]/39, word0=[format 0x%08X $w0]) -- the known-nonzero that makes every later comparison mean something"

    # The liveness-control arm plants HERE, standing in for the on-halt plant.
    d4_control_plant

    # ---- 2. halt the victim: the trigger under test ----------------------
    dm_select $VICTIM
    dm_haltreq $VICTIM
    set s [dm_poll_status $VICTIM dms_allhalted 400 $::HALTREQ_BIT]
    d2_chk [expr {$s >= 0}] "T1: the victim halted on haltreq (dmstatus [format 0x%08X $s])"
    dm_clr_haltreq $VICTIM

    # T5's baseline is sampled HERE, after the halt is confirmed, and not
    # before the haltreq.  MEASURED DEFECT, 2026-08-07, first run of this file:
    # the first draft sampled it before the request, so the increment the
    # victim legitimately performed in the microseconds between the sample and
    # the halt taking effect read as "the halted hart retired something" --
    # 363 -> 364, a false failure on a leg whose whole job is to be believed
    # when it fails.  A baseline for "nothing happened after X" has to be taken
    # after X.
    set ran0 [sh_get $::DBGTRP_RAN]

    if {$s >= 0} {
        # ---- 3. THE HEADLINE: read the page back through the DM ----------
        set r [d4_dm_readback $WANT]
        d4_readback_report "T2" $r $WANT
        d2_chk [lindex $r 0] \
            "T2: all 40 entry-page words read back THROUGH THE DEBUG MODULE equal the built deliverable (read [lindex $r 1]/40)"

        set c2 [d4_page_census $WANT]
        d4_report_census "T3" $c2
        d2_chk [expr {[lindex $c2 0] == 40}] \
            "T3: ...and the RAM cells agree (match=[lindex $c2 0]/40, zero=[lindex $c2 1], poison=[lindex $c2 2])"

        set t [d4_tail_intact]
        d2_chk [lindex $t 0] \
            "T4: the page TAIL (words 57..63) still holds the image's mark -- the plant did not walk past word 39 (badword=[lindex $t 1] got=[lindex $t 2])"

        set ran1 [sh_get $::DBGTRP_RAN]
        d2_chk [expr {$ran1 == $ran0}] \
            "T5: the halted victim retired NOTHING across the whole readback (counter $ran0 -> $ran1)"

        # ---- 4. resume ---------------------------------------------------
        dm_resumereq $VICTIM
        set s3 [dm_poll_status $VICTIM dms_allrunning 400]
        run 500 us
        set ran2 [sh_get $::DBGTRP_RAN]
        d2_chk [expr {$s3 >= 0 && $ran2 > $ran1}] \
            "T6: resume puts the victim back to running and its counter moves again ($ran1 -> $ran2)"

        # ---- 5. P0: the word-0 probe.  PUBLISHED, NOT ASSERTED. ----------
        # d4_spec 1.2 AS AMENDED scopes the self-heal promise to words 1..39;
        # this runs the excluded case anyway and reports it.  No d2_chk: an
        # assertion here would fail on correct RTL, and a leg that fails for a
        # reason the spec has already ruled out of scope teaches the next reader
        # to ignore it.  A publication does not rot the same way.
        if {[info exists ::env(D4_CONTROL)] && $::env(D4_CONTROL) eq "1"} {
            puts "DMILOG P0 SKIPPED under D4_CONTROL=1 -- the forced page is read-only,"
            puts "DMILOG   so the word-0 store could not land and the probe would"
            puts "DMILOG   publish a heal that never happened."
            flush stdout
        } elseif {$s3 >= 0} {
            d4_cmd $::DBGTRP_CMD_CORRUPT 0
            set p0w [sh_get $::DBG_ENTRY_ADDR]
            dm_select $VICTIM
            dm_haltreq $VICTIM
            set s4 [dm_poll_status $VICTIM dms_allhalted 400 $::HALTREQ_BIT]
            dm_clr_haltreq $VICTIM
            set r0 [d4_dm_readback $WANT]
            set p0cell [sh_get $::DBG_ENTRY_ADDR]
            puts "DMILOG ============================================================"
            puts "DMILOG P0 PUBLISHED-NOT-ASSERTED (F-D4-1; d4_spec 1.2 as amended)"
            puts "DMILOG   word 0 corrupted in band -> [format 0x%08X $p0w]; victim re-halted (dmstatus [format 0x%08X $s4])"
            puts "DMILOG   RAM cell 0 after the halt = [format 0x%08X $p0cell] (want [format 0x%08X [lindex $WANT 0]])"
            puts "DMILOG   DM readback: nread=[lindex $r0 1]/40 cmderr=[lindex $r0 4] ([d4_cmderr_name [lindex $r0 4]])"
            if {[lindex $r0 0]} {
                puts "DMILOG   >>> THE WORD-0 HOLE HEALED.  That is a CHANGE OF BEHAVIOUR,"
                puts "DMILOG   >>> not a pass: F-D4-1 says this core cannot do it (hart_tile"
                puts "DMILOG   >>> M10 sh_acked_addr).  Re-open the D5 carryover and re-scope"
                puts "DMILOG   >>> d4_spec 1.2 -- do not simply widen this leg."
            } elseif {$p0cell == [lindex $WANT 0]} {
                puts "DMILOG   >>> the F-D4-1 signature exactly: the DM's repair reached the"
                puts "DMILOG   >>> RAM and the hart never saw it -- it is holding a stale ack"
                puts "DMILOG   >>> for an address it never stops asking for.  Recovery on"
                puts "DMILOG   >>> silicon is a PWRCTRL tile reset; ndmreset is read-zero WARL."
            } else {
                puts "DMILOG   >>> NEITHER known outcome: the RAM cell was not repaired either."
                puts "DMILOG   >>> That is a THIRD case and is a finding -- run it down."
            }
            puts "DMILOG ============================================================"
            flush stdout
        }
    }
}

sh_force $::DBGTRP_REL 1
set verdict [d2_run_to_verdict 1600 "25 us"]
d2_report_verdict "dbgtrpmp/tramp" $verdict
puts "DMILOG PHASE=[sh_get $::DBGTRP_PHASE] RAN=[sh_get $::DBGTRP_RAN] CHK=[format 0x%08X [sh_get $::DBGTRP_CHK]] DIAG=[format 0x%08X [sh_get $::DBGTRP_DIAG]]"
d2_summary "dbgtrpmp/tramp" 6
flush stdout
exit
