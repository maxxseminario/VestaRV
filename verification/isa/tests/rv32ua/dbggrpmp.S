# See LICENSE for license details.

#*****************************************************************************
# dbggrpmp.S   (D-series, D2 -- HALT GROUPS: halt one member, the other member
#               halts with it, and the non-member does not)
#-----------------------------------------------------------------------------
# BLIND-AUTHORED against d2_spec.md section 3 (`dmcs2`, halt groups) and
# section 4, FROZEN 2026-08-05, by an agent that has not seen and will never
# see the D2 implementation.  Committed polarity: CORRECT RTL = PASS.
#
# NEEDS A HARNESS:  ./xrun_dbg.sh rv32ua-p-dbggrpmp dbg_grp.tcl
#
# ---------------------------------------------------------------------------
# WHY A HALT GROUP NEEDS AN IN-BAND INSTRUMENT AT ALL
#   The DMI face of a halt group is easy to fake: dmstatus can report hart 2
#   halted because the DM decided it should be, without hart 2 ever stopping.
#   The observable that cannot be faked is FORWARD PROGRESS, and only the
#   harts can report that.  So, exactly as in dbgdmimp.S, harts 1, 2 and 3
#   each spin incrementing their own shared counter and hart 0 reads the
#   pattern out of the three deltas.
#
#   The pattern this file demands is SPECIFIC and it is the whole test:
#       CNT[1] flat  AND  CNT[2] flat  AND  CNT[3] still advancing.
#   Three distinguishable ways to get it wrong, three verdict codes:
#     * only the requested member stops        -> the group broadcast is
#       dropped                                   (0x0D230005, map = 0x02)
#     * all three stop                         -> the broadcast went to
#       everybody, i.e. membership is not read   (0x0D230006, map = 0x0E)
#     * the non-member stops and a member does not -> membership is decoded
#       wrong                                     (0x0D230005 with the map)
#   The bitmap is published either way, so the log names which shape occurred
#   rather than merely saying "not the expected one".
#
# GROUP ASSIGNMENT IS THE HARNESS'S JOB (dmcs2 is DMI-only; no software can
#   reach it).  The harness puts harts 1 and 2 in group 1 and leaves hart 3 in
#   group 0 -- "no group" and the reset value, so hart 3 is a non-member by
#   the DM's own default and not by anything this test did.  It then halts
#   hart 1 ONLY.
#
# WHY HART 1 IS THE ONE REQUESTED AND HART 2 THE ONE PULLED IN
#   A DM that ignores dmcs2 and simply halts everything passes if the
#   requested hart and the pulled-in hart are indistinguishable.  Requesting
#   the LOWER-numbered member and asserting on the HIGHER one means the
#   broadcast has to travel, and the non-member sits between them in neither
#   direction -- hart 3 is outside the group and above both, so a
#   "halt hartsel and everything above it" bug is caught too.
#
# ---------------------------------------------------------------------------
# VERDICT.  a0 = 0xCAFEBABE => halting one group member halted the other and
# left the non-member running.
#   a1 = 0x0D230001   a shared word did not read back
#   a1 = 0x0D230002   base-ISA sanity failed
#   a1 = 0x0D230003   the three victims never all started counting
#                     (a2 = bitmap, bit h set = hart h advanced)
#   a1 = 0x0D230004   NOTHING EVER STOPPED.  Expected under xrun_batch.sh and
#                     meaningless there; under dbg_grp.tcl it is THE finding.
#   a1 = 0x0D230005   the wrong SET of harts stopped (a2 = the flat bitmap;
#                     0x02 = only the requested member -- broadcast dropped;
#                     0x08 or 0x0A = the non-member stopped -- membership
#                     decoded wrong)
#   a1 = 0x0D230006   ALL THREE stopped (a2 = 0x0E): the broadcast ignores
#                     membership entirely
#   a1 = 0x0D230007   the non-member's advance across the halted window was
#                     below MINADV (a2 = the advance): hart 3 was disturbed
#                     without being halted outright
#
# NEGATIVE CONTROL -- how the non-DM half was SEEN TO WORK at unimplemented
#   HEAD:  -DDBGGRP_NC_SELFSTOP.  Harts 1 AND 2 stop themselves together once
#   their counters pass a threshold, dwell, and rejoin; hart 3 is untouched.
#   That reproduces exactly the observable a correct halt group produces, so
#   hart 0's snapshot machinery, the bitmap classifier, every verdict code
#   path and the whole grading run for real.  A PASS proves the instrument is
#   LIVE (method rule 5) and makes no claim about the DM.
#
# N-AGNOSTIC.  Three victims at any NHARTS; no shared word indexed past hart 3.
#
# SHARED WORDS CLAIMED -- the D-series debug acceptance band 0x10050-0x1007C,
#   REUSED with this file's meanings (one image per sim):
#     0x10050  PHASE      hart 0 progress
#     0x10054  CNT[1]  ) CNT[h] = 0x10050 + 4*h
#     0x10058  CNT[2]  )
#     0x1005C  CNT[3]  )
#     0x10060  FLATMAP    the deciding round's flat-counter bitmap
#     0x10064  ADV3       hart 3's advance across the halted window
#     0x10068-0x1007C  unused by this file
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_PHASE     0x10050
#define SH_CNT_BASE  0x10050        /* CNT[h] = base + 4*h, h = 1..3 */
#define SH_FLATMAP   0x10060
#define SH_ADV3      0x10064

#define TILE_WORDS   1024
/* SELF-CALIBRATING BUDGETS -- identical construction to dbgdmimp.S, and for
   the same measured reason: the first draft's fixed dwell/round budget
   expired before the tiles had finished the bootrom loader copy, and its own
   liveness control caught it (a1 = ...0003).  A budget that expires before
   the subject exists fails on CORRECT RTL too.  hart 0 now waits on an
   ABSOLUTE counter threshold, ends each round when the FASTEST victim has
   advanced by ADV_K (the victims' progress is the clock), and spends ONE
   global poll budget across every phase so the test is guaranteed to trip
   inside the 100 ms tb watchdog.                                          */
#define GLOBAL_BUDGET 15000
#define START_T      16
/* ADV3_K / MINADV -- RE-SHAPED 2026-08-06 (R-D2-6(5)(iv)).  The first draft
   ended each observation round when the FASTEST victim had gained ADV_K = 16.
   During a halt-group window the only hart still running is the NON-MEMBER,
   and the both-members-halted window was MEASURED at <= 10 of its counts --
   so the round could never complete inside the window and NO CORRECT DM
   could pass the ordering.  The round is now clocked on the NON-MEMBER
   alone and needs only ADV3_K of its counts, which is the one quantity the
   window is guaranteed to contain.  3 against a measured 10 is better than
   3x margin; MINADV = 2 keeps a running member (which gains ~1 per
   non-member count) clear of a halted one (which gains 0).             */
#define ADV3_K       3
#define MINADV       2
#define NC_THRESHOLD 300
#define NC_DWELL     20000

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry

    li   a1, 0x0D230001
    li   t0, SH_PHASE
    li   t1, 12
dg_clr:
    sw   x0, 0(t0)
    lw   t2, 0(t0)
    bnez t2, dg_fail
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, dg_clr

    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    li   a1, 0x0D230002
    bne  t2, t3, dg_fail

    MP_STAGE_IMAGE(TILE_WORDS)
    MP_LAUNCH_HART(1, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(2, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(3, tile_entry, TILE_WORDS)

    # ---- all three counting before anything means anything ----------------
    li   s11, GLOBAL_BUDGET         # ONE budget for every phase below
    li   t0, SH_PHASE
    li   t1, 1
    sw   t1, 0(t0)
    jal  ra, dg_startwait
    bnez t6, dg_started
    li   a2, 0
    li   t1, START_T
    blt  s1, t1, 1f
    ori  a2, a2, 2
1:  blt  s2, t1, 1f
    ori  a2, a2, 4
1:  blt  s3, t1, 1f
    ori  a2, a2, 8
1:  li   a1, 0x0D230003
    j    dg_fail

dg_started:
    # ---- watch for ANY flat counter, then classify the SET -----------------
    li   t0, SH_PHASE
    li   t1, 2
    sw   t1, 0(t0)
dg_watch:
    jal  ra, dg_round
    beqz t6, dg_noflat
    li   a2, 0
    bnez s7, 1f
    ori  a2, a2, 2
1:  bnez s8, 1f
    ori  a2, a2, 4
1:  bnez s9, 1f
    ori  a2, a2, 8
1:  bnez a2, dg_flat
    j    dg_watch
dg_noflat:
    li   a1, 0x0D230004
    j    dg_fail

dg_flat:
    li   t0, SH_FLATMAP
    sw   a2, 0(t0)
    li   t0, SH_ADV3
    sw   s9, 0(t0)
    li   t1, 0x0E                   # all three flat
    li   a1, 0x0D230006
    beq  a2, t1, dg_fail
    li   t1, 0x06                   # THE EXPECTED SET: harts 1 and 2
    li   a1, 0x0D230005
    bne  a2, t1, dg_fail
    # ...and the non-member really kept working across that same interval
    li   t1, MINADV
    mv   a2, s9
    li   a1, 0x0D230007
    blt  s9, t1, dg_fail

    li   t0, SH_PHASE
    li   t1, 3
    sw   t1, 0(t0)
    RVTEST_PASS                     # a0 = 0xCAFEBABE

dg_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    # dg_snap / dg_startwait / dg_round.  One global poll budget (s11) bounds
    # every phase; t6 = 1 ok, 0 = budget exhausted; s0 holds ra.
    # THE ROUND IS CLOCKED ON THE NON-MEMBER (hart 3), not on the fastest of
    # the three -- see the ADV3_K note.  During the window under test harts 1
    # and 2 are BOTH halted, so "the fastest" is hart 3 anyway; the change is
    # that the round now needs only 3 of its counts instead of 16, which is
    # what makes the ordering satisfiable inside a window the DM legitimately
    # keeps short.
dg_snap:
    li   t0, SH_CNT_BASE
    lw   s1, 4(t0)
    lw   s2, 8(t0)
    lw   s3, 12(t0)
    ret

dg_startwait:
    mv   s0, ra
1:  jal  ra, dg_snap
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

dg_round:
    mv   s0, ra
    jal  ra, dg_snap
    mv   s4, s1
    mv   s5, s2
    mv   s6, s3
1:  jal  ra, dg_snap
    sub  s7, s1, s4
    sub  s8, s2, s5
    sub  s9, s3, s6
    li   t1, ADV3_K
    bge  s9, t1, 2f                 # the NON-MEMBER is the clock, alone
    addi s11, s11, -1
    bnez s11, 1b
    li   t6, 0
    mv   ra, s0
    ret
2:  li   t6, 1
    mv   ra, s0
    ret

    # ---- tile harts (loader ABI: only sp is defined) ---------------------
tile_entry:
    li   sp, 0xBFF0
    .option push
    .option arch, +zicsr
    csrr t3, mhartid
    .option pop
    slli t4, t3, 2
    li   t5, SH_CNT_BASE
    add  t5, t5, t4
#ifdef DBGGRP_NC_SELFSTOP
    li   t6, 3
    beq  t3, t6, tile_loop          # hart 3 is the non-member: never stops
    li   t6, NC_THRESHOLD
nc_loop:
    lw   t0, 0(t5)
    addi t0, t0, 1
    sw   t0, 0(t5)
    blt  t0, t6, nc_loop
    # CONTROL ARM: harts 1 AND 2 go flat together, exactly as a halt group
    # would make them.  The interval only has to outlast one of hart 0's
    # rounds, and a round is ADV_K increments of the non-member.
    li   t0, NC_DWELL
1:  addi t0, t0, -1
    bnez t0, 1b
#endif
tile_loop:
    lw   t0, 0(t5)
    addi t0, t0, 1
    sw   t0, 0(t5)
    j    tile_loop

    # NOTE: RVTEST_CODE_END is `unimp` in this env (it traps) -- never fall
    # through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
