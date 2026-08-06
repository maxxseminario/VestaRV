# See LICENSE for license details.

#*****************************************************************************
# dbgdmimp.S   (D-series, D2 -- THE HEADLINE: halt ONE hart through the DM
#                while the others demonstrably keep running, then resume it)
#-----------------------------------------------------------------------------
# BLIND-AUTHORED against d2_spec.md sections 2-4, FROZEN 2026-08-05, by an agent
# that has not seen and will never see the D2 implementation.  Committed
# polarity: CORRECT RTL = PASS (R-K5-8).
#
# THIS TEST NEEDS A TESTBENCH HARNESS AND CANNOT RUN WITHOUT ONE.
#     ./xrun_dbg.sh rv32ua-p-dbgdmimp dbg_dmi.tcl
# The harness is the DEBUGGER: it drives the MCU's d2_spec-2 DMI port (which
# riscv_tb.vhd leaves unassociated, so it sits at its entity defaults and a
# hierarchical force is the only driver) and issues dmcontrol.haltreq for
# hart 2 and later dmcontrol.resumereq.  NOTHING in this harness forces a tile
# dbg_* port: the DM does the halting, which is the whole difference between
# this instrument and D1's dbghaltmp.  Running this image under the ordinary
# xrun_batch.sh is a guaranteed FAIL with a1 = 0x0D210004 -- no debugger, so
# no hart ever stops.
#
# ---------------------------------------------------------------------------
# THE MEASUREMENT, AND WHY IT IS MADE IN BAND RATHER THAN BY THE HARNESS
#   d2_spec section 8 asks for "halt hart 2 from the DM while 0/1/3 keep
#   running ... prove the others never stalled".  A harness CAN read dmstatus
#   and see hart 2 halted; it CANNOT see that harts 1 and 3 kept making
#   forward progress, because dmstatus's "running" bit is a state, not a
#   liveness statement -- a hart wedged in TRAP_STATE, a hart spinning on a
#   grant it never gets, and a hart doing useful work all read `running`.
#   So the liveness half is measured by the harts themselves:
#
#     * harts 1, 2 and 3 each spin incrementing their OWN shared counter
#       CNT[h].  The counter lives in shared RAM, so every increment is a real
#       arbiter round trip -- a hart that stops being scheduled, stops being
#       clocked, or stops retiring shows up as a flat counter, and a hart that
#       merely changed state does not.
#     * hart 0 samples all three counters, DWELLs, samples again, and looks
#       for the ONE pattern that a correct DM halt produces: exactly one delta
#       zero and the other two large.  It records which hart, waits for that
#       delta to become nonzero again (the resume), and asserts that the two
#       bystanders advanced across the WHOLE halted window.
#
#   Neither hart 0 nor the harness knows when the halt will land, and nothing
#   here is calibrated onto it -- see the budget note below.
#
# THE BUDGETS ARE SELF-CALIBRATING, AND THEY WERE NOT AT FIRST
#   The first draft counted fixed "rounds" of a fixed instruction dwell.  Its
#   own liveness control FAILED at unimplemented HEAD with a1 = ...0003 -- the
#   victims never all started counting -- and the harness log showed why: the
#   tiles need ~5 ms after MP_LAUNCH to finish the bootrom loader copy, a
#   shared-RAM increment costs ~40 us with three harts contending, and 30
#   rounds of a 600-iteration dwell is nowhere near either number.  A budget
#   that expires before the subject exists fails on CORRECT RTL too, so it is
#   an instrument defect and not a finding; it is recorded here because the
#   control is what caught it, which is the whole reason a liveness control
#   exists (method rule 5).
#   The rework removes every fixed duration.  hart 0 now:
#     * waits until each victim's counter passes START_T -- an absolute
#       threshold, not a rate, so it cannot expire early merely because the
#       tiles were slow to boot;
#     * ends each observation round when the FASTEST victim has advanced by
#       ADV_K -- i.e. the victims' own progress is the clock, which is
#       exactly the edge method rule 7 asks for instead of a tuned delay;
#     * spends ONE GLOBAL POLL BUDGET across every phase, so the whole test
#       is guaranteed to trip inside the 100 ms tb watchdog no matter which
#       phase stalls.
#   A halted victim contributes 0 to every delta and the round still ends,
#   because the other two are still advancing -- which is the property that
#   makes "the fastest is the clock" safe here.
#
# WHAT THE THREE ASSERTIONS ARE, precisely
#   1. SOMETHING STOPPED.        a1 = 0x0D210004 if no hart ever stalls.
#   2. IT WAS HART 2, AND ONLY HART 2.  Two separate codes, because they fail
#      for different reasons: 0x0D210005 = the wrong hart stopped (hartsel
#      decoded to somebody else -- the failure a 4-hart chip hides best,
#      because 3 of 4 wrong answers still stop *a* hart); 0x0D210006 = more
#      than one hart stopped at once (a halt request that is not per-hart, or
#      a halt that stops the shared fabric).
#   3. IT RESUMED, AND THE BYSTANDERS NEVER STOPPED.  0x0D210007 = the
#      resumereq never took effect; 0x0D210008 = a bystander advanced by less
#      than MINADV across the halted window, i.e. halting one hart stalled
#      another.
#   4. THE RE-ARMED WIRE (PHASE 4, added 2026-08-06 under R-D2-2(5)).
#      d2_spec 4 as amended DEFINES what `resumereq` written while
#      `dmcontrol.haltreq` is still held must do on VestaRV: the hart resumes
#      (`resumeack` sets) and then RE-HALTS with no further DMI write.  The
#      D1 core deliberately does NOT do that -- its wait-for-release flop
#      collapses a continuously held request to exactly ONE entry -- so the
#      re-halt has to come from the DM re-arming the wire, and this is the
#      only place in the acceptance set where that obligation is observable
#      at all.
#      *** WHERE THE OBSERVATION LIVES, AND WHY NOT HERE.  The re-arm's
#      signature is an ORDERING OF DMI READS -- resumeack sets, then halted
#      sets again, with nothing written in between -- and dbg_dmi.tcl's R1-R4
#      make it.  hart 0 CANNOT make it: the window between the `dret` and the
#      DM's fresh halt may retire only a handful of instructions and quite
#      possibly ZERO shared-RAM increments, so a counter observer would be
#      sampling something it cannot be guaranteed to see.  Claiming otherwise
#      would be a decorative metric (method rule 9).
#      What hart 0 contributes instead is the BRACKET, which it can see
#      reliably: hart 2 goes flat again for the whole held-haltreq period
#      (0x0D21000A if it never does), and it runs again once the request is
#      finally released (0x0D21000B if it never does) -- with the bystanders
#      still advancing across both.  So the leg is a DMI-face assertion with
#      an in-band liveness bracket, and this comment is here so nobody later
#      mistakes the bracket for the assertion.
#
# WHY HART 2 AND NOT HART 1
#   hartsel is 2 bits at N=4.  Hart 1 is 0b01 and hart 3 is 0b11; hart 2 is
#   0b10, the only value whose two bits DIFFER, so a DM that swaps, drops or
#   duplicates a hartsel bit selects a different hart for 2 and can still get
#   1 and 3 right.  At N=18 (5 bits) the same argument holds and 2 is still a
#   value with a single set bit above bit 0.  Assertion 2 is what reads it.
#
# ---------------------------------------------------------------------------
# VERDICT.  a0 = 0xCAFEBABE => the DM halted exactly hart 2 through DMI, harts
# 1 and 3 kept retiring throughout, and hart 2 resumed.  a0 = 0xDEADBEEF with:
#   a1 = 0x0D210001   a shared word did not read back: shared-RAM setup break
#   a1 = 0x0D210002   base-ISA sanity failed
#   a1 = 0x0D210003   the three victims never all started counting
#                     (a2 = the delta bitmap: bit h set = hart h advanced)
#   a1 = 0x0D210004   NO HART EVER STOPPED.  Under xrun_batch.sh this is the
#                     expected result and means nothing; under dbg_dmi.tcl it
#                     is THE finding -- cross-read the DMILOG lines to see
#                     whether the DM ever reported the hart halted.
#   a1 = 0x0D210005   a hart stopped, but not hart 2 (a2 = the hart index)
#   a1 = 0x0D210006   more than one hart stopped at once (a2 = the bitmap):
#                     the halt is not per-hart
#   a1 = 0x0D210007   the stopped hart never resumed (a2 = its counter)
#   a1 = 0x0D210008   a bystander advanced by less than MINADV across the
#                     halted window (a2 = the hart index, a3 = its advance)
#   (0x0D21000A and 0x0D21000B are RETIRED -- see the PHASE 4 note.  REARM at
#    0x10074 is now PUBLISHED and asserted by nothing: 1 = hart 2 was observed
#    flat in the re-arm round, 2 = it was observed moving.  Read it as a
#    diagnostic beside dbg_dmi.tcl's R1-R4, never as a verdict.)
# NO a0 AT ALL (tb watchdog): hart 0 wedged in its own preamble.
#
# TWO NEGATIVE CONTROLS.
#
#   -DDBGDMI_NC_SELFSTOP -DDBGDMI_NC_NOREARM -- HOW PHASE 4 WAS SEEN TO FAIL.
#   PHASE 4 cannot fail at unimplemented HEAD by the ordinary route, because
#   the run never reaches it: PHASE 2 reports 0x0D210004 first and stops.  So
#   its seen-to-FAIL leg is a BUILD ARM, which is the D1 protocol for exactly
#   this case.  This arm gives hart 2 ONE self-stop instead of two, so PHASES
#   1-3 are satisfied for real and PHASE 4 then finds no second stop and
#   reports 0x0D21000A.  It removes exactly one thing -- the second stop --
#   and nothing else, so the run exercises the new leg's failure path end to
#   end.
#
# -DDBGDMI_NC_SELFSTOP -- how the non-DM half of this file was SEEN TO WORK at
#   unimplemented HEAD, where no DMI port exists and nothing can be halted:
#   Hart 2 stops ITSELF once its counter passes a threshold: it leaves the
#   counting loop, dwells without touching CNT[2], and then rejoins.  Harts 1
#   and 3 are untouched.  That reproduces EXACTLY the observable a DM halt
#   produces -- one flat counter, two advancing ones, then all three advancing
#   -- so hart 0's snapshot machinery, the stall detector, the which-hart
#   assertion, the resume detector, the bystander-advance assertion and the
#   whole verdict path all execute for real.  A PASS on that arm proves the
#   instrument is LIVE and that a later FAIL is about the DM, not about the
#   plumbing (method rule 5).  It is a CONTROL: it makes no claim about the
#   DM, it can detect nothing, and it must never be quoted as a D2 result.
#
# N-AGNOSTIC.  Exactly three victims are launched at any NHARTS and no shared
#   word is indexed past hart 3, so the same source serves Castalia (N=4) and
#   the argus_debug row (N=18); on Argus harts 4-17 stay parked in the bootrom
#   and riscv_tb reports the usual silent/parked NOTE.
#
# SHARED WORDS CLAIMED -- the D-series debug acceptance band 0x10050-0x1007C
#   (12 words), the SAME band D1's dbgdenymp/dbghaltmp/dbgstepmp use, REUSED
#   here with this file's meanings.  Safe for the shdma/wdma reason: one image
#   per sim, and the D-series debug instruments never coexist.
#     0x10050  PHASE      hart 0's progress word (diagnosis only)
#     0x10054  CNT[1]  ) CNT[h] = 0x10050 + 4*h, incremented by hart h
#     0x10058  CNT[2]  )
#     0x1005C  CNT[3]  )
#     0x10060  STOPPED_H  the hart hart 0 observed stall
#     0x10064  RESUMED_H  the hart hart 0 observed resume
#     0x10068  ADV1       hart 1's advance across the halted window
#     0x1006C  ADV3       hart 3's advance across the halted window
#     0x10070  STALLMAP   bit h = hart h was flat in the deciding sample
#     0x10074  REARM      hart 0's PHASE-4 progress: 1 = hart 2 stopped a
#                         second time, 2 = it ran again after the release
#     0x10078-0x1007C  unused by this file
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_PHASE     0x10050
#define SH_CNT_BASE  0x10050        /* CNT[h] = base + 4*h, h = 1..3 */
#define SH_STOPPED   0x10060
#define SH_RESUMED   0x10064
#define SH_ADV1      0x10068
#define SH_ADV3      0x1006C
#define SH_STALLMAP  0x10070
#define SH_REARM     0x10074

#define TILE_WORDS   1024
/* See "THE BUDGETS ARE SELF-CALIBRATING" in the header.  One poll is three
   shared loads plus a little loop, ~2 us measured, so GLOBAL_BUDGET is about
   30 ms -- comfortably inside the 100 ms tb watchdog even if every phase
   runs to its end, and it is shared across ALL phases so they cannot add up
   to an overrun.                                                          */
#define GLOBAL_BUDGET 15000
#define START_T      16             /* absolute count every victim must pass */
#define ADV_K        16             /* a round ends when the FASTEST gains K */
#define MINADV       4              /* a bystander's floor: a stalled hart
                                       gives 0, a running one gives >= 8    */
#define NC_THRESHOLD 300            /* control arm only: hart 2's self-stop  */
#define NC_THRESHOLD2 600           /* control arm only: its SECOND self-stop */
#define NC_DWELL     20000          /* control arm only: its flat interval   */

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry

    # ==================================================================
    # clear every claimed word and prove it read back
    # ==================================================================
    li   a1, 0x0D210001
    li   t0, SH_PHASE
    li   t1, 12                     # 12 words: 0x10050 .. 0x1007C
dm_clr:
    sw   x0, 0(t0)
    lw   t2, 0(t0)
    bnez t2, dm_fail
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, dm_clr

    li   t0, 1234                   # base-ISA sanity
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    li   a1, 0x0D210002
    bne  t2, t3, dm_fail

    MP_STAGE_IMAGE(TILE_WORDS)
    MP_LAUNCH_HART(1, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(2, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(3, tile_entry, TILE_WORDS)

    li   s11, GLOBAL_BUDGET         # ONE budget for every phase below

    # ==================================================================
    # PHASE 1 -- all three victims must be counting before anything else
    # means anything.  Without this a "hart 2 is flat" reading could be a
    # hart 2 that never started.  An ABSOLUTE threshold, so a slow tile
    # bring-up cannot expire it (see the header).
    # ==================================================================
    li   t0, SH_PHASE
    li   t1, 1
    sw   t1, 0(t0)
    jal  ra, dm_startwait
    bnez t6, dm_started
    # name which ones never got there
    li   a2, 0
    li   t1, START_T
    blt  s1, t1, 1f
    ori  a2, a2, 2
1:  blt  s2, t1, 1f
    ori  a2, a2, 4
1:  blt  s3, t1, 1f
    ori  a2, a2, 8
1:  li   a1, 0x0D210003
    j    dm_fail

dm_started:
    # ==================================================================
    # PHASE 2 -- watch for EXACTLY ONE flat counter.
    #   s4/s5/s6 hold the pre-dwell snapshot of the round that decides, so
    #   the bystanders' advance is measured across the SAME interval in
    #   which the stall was observed and not across a later one.
    # ==================================================================
    li   t0, SH_PHASE
    li   t1, 2
    sw   t1, 0(t0)
dm_watch:
    jal  ra, dm_round               # deltas in s7/s8/s9; t6 = 0 if budget out
    beqz t6, dm_nostall
    # build the flat-counter bitmap in a2
    li   a2, 0
    bnez s7, 1f
    ori  a2, a2, 2
1:  bnez s8, 1f
    ori  a2, a2, 4
1:  bnez s9, 1f
    ori  a2, a2, 8
1:  bnez a2, dm_stalled
    j    dm_watch
dm_nostall:
    li   a1, 0x0D210004             # nothing ever stopped
    j    dm_fail

dm_stalled:
    li   t0, SH_STALLMAP
    sw   a2, 0(t0)
    # EXACTLY ONE flat counter?  a2 must be a power of two.  If two or three
    # went flat together the halt was not per-hart, and a2 (the bitmap) is
    # the diagnosis -- so it is reported unmodified.
    addi t1, a2, -1
    and  t1, t1, a2
    li   a1, 0x0D210006
    bnez t1, dm_fail
    # ...and the one must be hart 2, i.e. bitmap bit 2.
    li   t2, 4
    beq  a2, t2, dm_stall_is_h2
    # name the offender instead of the bitmap: 2 -> hart 1, 8 -> hart 3
    li   t2, 2
    li   t3, 1
    beq  a2, t2, 1f
    li   t3, 3
1:  mv   a2, t3
    li   a1, 0x0D210005
    j    dm_fail

dm_stall_is_h2:
    li   t0, SH_STOPPED
    li   t1, 2
    sw   t1, 0(t0)
    # bystanders must have advanced across the very interval in which
    # hart 2 was flat -- "the others never stalled", measured.
    li   t0, SH_ADV1
    sw   s7, 0(t0)
    li   t0, SH_ADV3
    sw   s9, 0(t0)
    li   t1, MINADV
    li   a1, 0x0D210008
    li   a2, 1
    mv   a3, s7
    blt  s7, t1, dm_fail
    li   a2, 3
    mv   a3, s9
    blt  s9, t1, dm_fail

    # ==================================================================
    # PHASE 3 -- the resume.  CNT[2] must start advancing again, and the
    # bystanders must still be advancing when it does.
    # ==================================================================
    li   t0, SH_PHASE
    li   t1, 3
    sw   t1, 0(t0)
dm_wait_resume:
    jal  ra, dm_round
    beqz t6, dm_noresume
    bnez s8, dm_resumed
    j    dm_wait_resume
dm_noresume:
    li   t0, SH_CNT_BASE
    lw   a2, 8(t0)
    li   a1, 0x0D210007
    j    dm_fail

dm_resumed:
    li   t0, SH_RESUMED
    li   t1, 2
    sw   t1, 0(t0)
    li   t1, MINADV                 # ...and 1 and 3 are STILL running
    li   a1, 0x0D210008
    li   a2, 1
    mv   a3, s7
    blt  s7, t1, dm_fail
    li   a2, 3
    mv   a3, s9
    blt  s9, t1, dm_fail

    # ==================================================================
    # PHASE 4 -- THE RE-ARMED WIRE (R-D2-2(5)).  The harness now re-asserts
    # haltreq and HOLDS it across a resumereq; d2_spec 4 requires the hart
    # to resume and then RE-HALT unprompted.  hart 0 supplies the bracket
    # only -- see the header for why the ordering assertion itself is
    # dbg_dmi.tcl's and cannot be hart 0's.
    #
    # Both waits are ORDERINGS on hart 2's own counter, not durations
    # (the rule the J6 rework produced): flat again, then advancing again.
    # ==================================================================
    li   t0, SH_PHASE
    li   t1, 4
    sw   t1, 0(t0)
    # THE IN-BAND BRACKET IS RETIRED TO PUBLISHED-NOT-ASSERTED (R-D2-7(3),
    # dispositioned by its author at validation).  It was measured
    # NON-DETERMINISTIC -- REARM read 1 on one run and 0 on the next with the
    # SAME DM and the SAME harness -- and the cause is the one I named when I
    # declined to strengthen it at wave A: whether hart 0's observation round
    # lands inside the re-halt window depends on whether the resumed window
    # retires a SHARED increment at all, and nothing guarantees it does.  I
    # cannot make it deterministic without a guarantee the architecture does
    # not offer, and rule 9 is explicit that a leg which can neither be made
    # deterministic nor quoted as evidence is decoration -- worse than absent,
    # because it reads as evidence.  So it PUBLISHES what it saw and asserts
    # nothing, the D1 DPC[2] idiom.
    # THE SIGNAL FOR THE RE-ARM IS THE DM SIDE: dbg_dmi.tcl's R1-R4, whose
    # ordering (halted -> resumeack -> halted again with NOTHING written in
    # between) is exact, is the thing sealed mutant M7 flips, and is where any
    # future re-arm regression will show.
    jal  ra, dm_round
    beqz t6, dm_rearm_pub
    bnez s8, dm_rearm_pub           # CNT[2] moving  -> record 2
    li   t1, 1                      # CNT[2] flat    -> record 1
    li   t0, SH_REARM
    sw   t1, 0(t0)
    j    dm_rearm_done
dm_rearm_pub:
    li   t0, SH_REARM
    li   t1, 2
    sw   t1, 0(t0)
dm_rearm_done:

    li   t0, SH_PHASE
    li   t1, 5
    sw   t1, 0(t0)
    RVTEST_PASS                     # a0 = 0xCAFEBABE

dm_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    # =====================================================================
    # dm_snap     -- s1/s2/s3 = CNT[1]/CNT[2]/CNT[3].  Clobbers t0 only.
    # dm_startwait-- poll until every counter passes START_T.  t6 = 1 ok,
    #                0 = the GLOBAL budget (s11) ran out.
    # dm_round    -- take a snapshot, then poll until the FASTEST victim has
    #                advanced by ADV_K; leave the three deltas in s7/s8/s9.
    #                The victims' own progress is the clock, so nothing here
    #                is a tuned delay, and a halted victim does not stall the
    #                round because the other two still advance.
    #                t6 = 1 ok, 0 = budget out.  Both use s0 to hold ra.
    # None of them touches a1-a3.
    # =====================================================================
dm_snap:
    li   t0, SH_CNT_BASE
    lw   s1, 4(t0)
    lw   s2, 8(t0)
    lw   s3, 12(t0)
    ret

dm_startwait:
    mv   s0, ra
1:  jal  ra, dm_snap
    li   t1, START_T
    blt  s1, t1, 2f
    blt  s2, t1, 2f
    blt  s3, t1, 2f
    li   t6, 1
    mv   ra, s0
    ret
2:  addi s11, s11, -1
    bnez s11, 1b
    li   t6, 0
    mv   ra, s0
    ret

dm_round:
    mv   s0, ra
    jal  ra, dm_snap
    mv   s4, s1
    mv   s5, s2
    mv   s6, s3
1:  jal  ra, dm_snap
    sub  s7, s1, s4
    sub  s8, s2, s5
    sub  s9, s3, s6
    li   t1, ADV_K
    bge  s7, t1, 2f
    bge  s8, t1, 2f
    bge  s9, t1, 2f
    addi s11, s11, -1
    bnez s11, 1b
    li   t6, 0
    mv   ra, s0
    ret
2:  li   t6, 1
    mv   ra, s0
    ret

    # ---- tile harts enter here (loader ABI: only sp is defined) ----------
    # The loop body holds NO live register across an iteration except its own
    # counter address, so a debug visit that clobbers t0-t2 is invisible to
    # it -- the loop must be unaffected by having been halted, or "it resumed"
    # would be measuring the stub instead of the resume.
tile_entry:
    li   sp, 0xBFF0
    .option push
    .option arch, +zicsr
    csrr t3, mhartid
    .option pop
    slli t4, t3, 2
    li   t5, SH_CNT_BASE
    add  t5, t5, t4                 # t5 = &CNT[h]
#ifdef DBGDMI_NC_SELFSTOP
    li   t6, 2
    bne  t3, t6, tile_loop          # only hart 2 self-stops
    li   t6, NC_THRESHOLD
nc_loop:
    lw   t0, 0(t5)
    addi t0, t0, 1
    sw   t0, 0(t5)
    blt  t0, t6, nc_loop
    # CONTROL ARM: stop touching CNT[2] for a while, exactly as a halted hart
    # would.  The interval only has to outlast one of hart 0's rounds, and a
    # round is ADV_K increments of a bystander (~640 us measured); NC_DWELL
    # register iterations is several times that.
    li   t0, NC_DWELL
1:  addi t0, t0, -1
    bnez t0, 1b
#ifndef DBGDMI_NC_NOREARM
    # ...then run, then stop a SECOND time, then run again: the bracket
    # PHASE 4 observes.  Without this second pair the control would exercise
    # only half the file and the liveness proof would shrink silently -- and
    # WITHOUT it deliberately (-DDBGDMI_NC_NOREARM) is how PHASE 4 itself was
    # seen to fail, since it cannot be reached at unimplemented HEAD.
    li   t6, NC_THRESHOLD2
nc_loop2:
    lw   t0, 0(t5)
    addi t0, t0, 1
    sw   t0, 0(t5)
    blt  t0, t6, nc_loop2
    li   t0, NC_DWELL
2:  addi t0, t0, -1
    bnez t0, 2b
#endif
#endif
tile_loop:
    lw   t0, 0(t5)
    addi t0, t0, 1
    sw   t0, 0(t5)
    j    tile_loop

    # NOTE: RVTEST_CODE_END is `unimp` in this env (it traps) -- never fall
    # through; every hart-0 path above ends in a spin and every tile path in
    # an unconditional jump.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
