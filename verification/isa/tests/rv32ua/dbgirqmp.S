# See LICENSE for license details.

#*****************************************************************************
# dbgirqmp.S   (D-series, D2 -- F-D2-1: A HART IN DEBUG MODE TAKES NO
#               INTERRUPT, IN BOTH DELIVERY POLARITIES)
#-----------------------------------------------------------------------------
# BLIND-AUTHORED 2026-08-06 against the F-D2-1 contract statement only, by an
# agent that has not seen and will never see the implementer's fix (R-D2-3(5)
# bars the author from d2_implementation_report.md).  Committed polarity:
# CORRECT RTL = PASS (R-K5-8).
#
# NEEDS A HARNESS:  ./xrun_dbg.sh rv32ua-p-dbgirqmp dbg_irq.tcl
# No Debug Module is required: the harness forces the tile's `dbg_haltreq`
# port, the D1 mechanism.
#
# ---------------------------------------------------------------------------
# THE TRAP THIS FILE EXISTS TO AVOID, AND HOW IT AVOIDS IT
#   "No interrupt was taken" is the easiest claim in verification to make
#   vacuously true.  A test that never made one pending, or made one pending
#   on a hart that could not have taken it anyway -- wrong polarity, mie
#   clear, mstatus.MIE clear, IVT slot parked -- reports a clean zero and
#   proves nothing (method rule 4: validate the method against a KNOWN
#   NONZERO before its answer is load-bearing).  So each victim proves the
#   interrupt is takeable THREE times, twice around the measurement:
#
#     1. THE PRE-DEBUG CONTROL.  Before it is ever halted, hart 0 sends the
#        victim an msip.  The victim's ISR fires, clears the level, and
#        counts.  ISR_CNT[h] must be exactly 1 and CTRL[h] must be set, or
#        the whole arm is declared not-proven with its own verdict code
#        (0x0D27h004) instead of passing.  THIS is the known-nonzero.
#     2. THE MEASUREMENT.  The victim is halted; while it is in debug mode
#        hart 0 sends a SECOND msip.  Nothing may happen: ISR_CNT must not
#        move, DBGISR must stay zero, and the msip level must stay ASSERTED
#        (hart 0 reads it back from the CLINT -- an ISR would have cleared
#        it, so a cleared msip is itself the finding).
#     3. THE POST-RESUME CONFIRMATION, and this is the one that closes the
#        loop.  After the `dret`, that SAME still-pending msip must be taken
#        AT ONCE: ISR_CNT becomes 2 and the level clears.  So the interrupt
#        was genuinely pending and genuinely deliverable throughout -- it was
#        DEFERRED, not absent.  Without this leg, "not taken in debug mode"
#        and "not takeable at all" are indistinguishable.
#
#   Every one of those is an ORDERING on counters and levels the harts
#   themselves publish (method rule 17), not a duration.  The one bounded
#   wait -- hart 0 watching the msip level stay high -- is diagnostic only:
#   the FAILURE is detected as an EVENT (the level clearing, or ISR_CNT
#   moving), never as the expiry of a timer.
#
# BOTH DELIVERY POLARITIES, on two victims, because they are two different
# pieces of RTL and d1_spec's frozen clause covers both:
#     hart 1  LEGACY delivery (mtrapctl.LEGACY = 1, the reset configuration).
#             CLINT msip is IVT slot 83, hardware-vectored, `iret`-returning.
#             The slot is armed in this image's own .ivt section, so the
#             bootrom's loader-ISR arming is overwritten by the staged copy.
#     hart 2  STANDARD delivery (`csrw 0x7C0, x0`), mtvec + mstatus.MIE +
#             mie.MSIE, `mret`-returning.  Its handler decodes mcause.
#   A build that added the debug-mode qualifier to ONE path passes half of
#   this file and fails the other half, which is the point of running both.
#
# hart 3 is a BYSTANDER that only counts: if halting one hart or leaving an
#   interrupt pending on it disturbs the chip, its counter stops.
#
# ---------------------------------------------------------------------------
# VERDICT.  a0 = 0xCAFEBABE => on BOTH polarities the victim took the control
# interrupt, took NOTHING while in debug mode, and took the still-pending
# interrupt immediately after resuming.  a0 = 0xDEADBEEF with:
#   a1 = 0x0D270001   a shared word did not read back
#   a1 = 0x0D270002   base-ISA sanity failed
#   a1 = 0x0D270003   a victim never published READY (a2 = the hart index)
#   a1 = 0x0D27h004   THE KNOWN-NONZERO CONTROL FAILED on hart h (a2 =
#                     ISR_CNT[h], a3 = CTRL[h]): the interrupt was never
#                     taken even OUTSIDE debug mode, so nothing this file
#                     could report about debug mode would mean anything.
#                     This is a test/config finding, not an RTL one.
#   a1 = 0x0D27h005   the victim never entered debug mode (a2 = ENTRIES[h]):
#                     the harness's halt never landed
#   a1 = 0x0D27h006   AN ISR RAN WHILE THE HART WAS IN DEBUG MODE (a2 =
#                     DBGISR[h], a3 = ISR_CNT[h]).  THE FINDING, positively.
#   a1 = 0x0D27h007   ISR_CNT MOVED across the debug window (a2 = ISR_CNT at
#                     window end, a3 = 1 expected).  The same finding read
#                     from the counter instead of from the flag -- kept
#                     separate because a build could clear the level without
#                     running the handler.
#   a1 = 0x0D27h008   the msip LEVEL was cleared during the debug window
#                     (a2 = the readback): something consumed the interrupt
#   a1 = 0x0D27h009   after the resume the pending interrupt was NOT taken
#                     (a2 = ISR_CNT[h], 2 expected).  This is the leg that
#                     makes the whole measurement meaningful; without it a
#                     PASS could mean "never deliverable".
#   a1 = 0x0D27h00A   the victim never resumed after its `dret` (a2 = POST)
#   a1 = 0x0D27000B   the BYSTANDER stopped counting (a2 = CNT[3])
# NO a0 AT ALL (tb watchdog): hart 0 wedged in its own preamble.
#
# NEGATIVE CONTROL -- how the non-debug half was SEEN TO WORK:
#   -DDBGIRQ_NC_NODEBUG.  The victims never park for a halt and never enter
#   debug mode; hart 0 skips the debug window and asserts only the control
#   legs -- both polarities' ISRs fire, both counters reach 1, and the whole
#   IVT/mtvec/mie/mstatus setup, both handlers, every publish and the verdict
#   path run for real on a tree with no debug mode at all.  A PASS proves the
#   interrupt plumbing is LIVE, which is exactly the premise the real arm's
#   measurement rests on (method rule 5).  It is a CONTROL: it makes no claim
#   about debug mode and must never be quoted as a D2 result.
#
# STUB PLANTED AT BOTH ADDRESSES, for the reason dbgexcmp.S's header gives:
#   DEBUG_ENTRY_ADDR is 0xBE00 on the tree as it stands and shared 0x10780
#   after the generator's debug-ON emission lands, and this detector must
#   work on both.
#
# N-AGNOSTIC.  Three tiles at any NHARTS; no shared word indexed past hart 3.
#
# SHARED WORDS CLAIMED -- the D2 CORE-DETECTOR BAND 0x10880-0x1093F (48
#   words), three
#   16-word per-hart blocks at 0x10840 + 0x40*h for h = 1, 2, 3 (0x10880 /
#   0x108C0 / 0x10900), REUSED with this file's meanings (one image per sim;
#   dbgexcmp.S and this file never coexist -- the shdma/wdma precedent).
#     +0x00 ENTRIES    +0x04 ISR_CNT   +0x08 CTRL      +0x0C WINDOW
#     +0x10 DBGISR     +0x14 IN_DEBUG  +0x18 GO        +0x1C WIN_SNAP
#     +0x20 CNT        +0x24 READY     +0x28 POST      +0x2C MSIP_SEEN
#     +0x30 REL        +0x34 (spare)   +0x38 (spare)   +0x3C (spare)
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define BLK_BASE     0x10840        /* block(h) = BLK_BASE + 0x40*h */
#define O_ENTRIES    0
#define O_ISR_CNT    4
#define O_CTRL       8
#define O_WINDOW     12
#define O_DBGISR     16
#define O_IN_DEBUG   20
#define O_GO         24
#define O_WIN_SNAP   28
#define O_CNT        32
#define O_READY      36
#define O_POST       40
#define O_MSIP_SEEN  44
#define O_REL        48

#define DBGISR_MAGIC 0x0D27BAD0
#define POST_MAGIC   0x0D27D057
#define CLINT_MSIP   0x5000
#define TILE_WORDS   1024
#define ARM_BUDGET   40000
#define WIN_BUDGET   8000           /* diagnostic only -- see the header    */
#define DRET_INSN    0x7B200073
#define MTRAPCTL     0x7C0
#define MIE_MSIE     0x008          /* mie bit 3  */
#define MSTATUS_MIE  0x008          /* mstatus bit 3 */

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry

    li   a1, 0x0D270001
    li   t0, 0x10880
    li   t1, 48                     # 0x10880-0x1093F: blocks for harts 1,2,3
dq_clr:
    sw   x0, 0(t0)
    lw   t2, 0(t0)
    bnez t2, dq_fail
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, dq_clr

    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    li   a1, 0x0D270002
    bne  t2, t3, dq_fail

    jal  ra, dq_plant_shared

    MP_STAGE_IMAGE(TILE_WORDS)
    MP_LAUNCH_HART(1, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(2, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(3, tile_entry, TILE_WORDS)

    # ---- both victims READY (armed and parked) ---------------------------
    li   t6, ARM_BUDGET
dq_rdy:
    li   t0, 0x10880
    lw   t2, O_READY(t0)
    li   t0, 0x108C0
    lw   t3, O_READY(t0)
    beqz t2, dq_rdy_next
    bnez t3, dq_ready
dq_rdy_next:
    addi t6, t6, -1
    bnez t6, dq_rdy
    li   a2, 1
    beqz t2, 1f
    li   a2, 2
1:  li   a1, 0x0D270003
    j    dq_fail

dq_ready:
    # ==================================================================
    # 1. THE KNOWN-NONZERO CONTROL.  Send each victim an msip while it is
    # plainly NOT in debug mode and require its ISR to run.  Everything
    # after this is worthless if this fails, so it fails LOUDLY and with
    # its own code rather than letting the run continue.
    # ==================================================================
    li   s5, 1
dq_ctrl_loop:
    slli s6, s5, 6
    li   s7, BLK_BASE
    add  s7, s7, s6
    slli t0, s5, 2
    li   t1, CLINT_MSIP
    add  t0, t0, t1
    li   t1, 1
    sw   t1, 0(t0)                  # msip[h] = 1
    li   t6, ARM_BUDGET
1:  lw   t2, O_CTRL(s7)
    bnez t2, 2f
    addi t6, t6, -1
    bnez t6, 1b
2:  lw   a2, O_ISR_CNT(s7)
    lw   a3, O_CTRL(s7)
    li   t1, 1
    slli a1, s5, 8
    li   t2, 0x0D270004
    add  a1, a1, t2
    bne  a2, t1, dq_fail            # the control interrupt was never taken
    beqz a3, dq_fail
    addi s5, s5, 1
    li   t0, 3
    blt  s5, t0, dq_ctrl_loop

#ifdef DBGIRQ_NC_NODEBUG
    li   t0, 0x10880
    li   t1, 1
    sw   t1, O_REL(t0)
    li   t0, 0x108C0
    sw   t1, O_REL(t0)
    # CONTROL ARM: stop here.  Both victims took their control interrupt on
    # their own delivery path, which is the premise the real arm's whole
    # measurement rests on -- and it is exercised for real, on a tree with no
    # debug mode at all.  Nothing below is reachable without a debugger.
    j    dq_ctrl_done
#endif

    # ==================================================================
    # 2. THE MEASUREMENT.  The harness halts both victims; each stub
    # publishes IN_DEBUG and opens its WINDOW.  hart 0 then sends the
    # SECOND msip and watches the level.
    # ==================================================================
    li   s5, 1
dq_meas_loop:
    slli s6, s5, 6
    li   s7, BLK_BASE
    add  s7, s7, s6

    li   t6, ARM_BUDGET             # wait for this victim to be in debug
1:  lw   t2, O_IN_DEBUG(s7)
    bnez t2, 2f
    addi t6, t6, -1
    bnez t6, 1b
    lw   a2, O_ENTRIES(s7)
    slli a1, s5, 8
    li   t2, 0x0D270005
    add  a1, a1, t2
    j    dq_fail

2:  slli s8, s5, 2                  # s8 = &msip[h]
    li   t1, CLINT_MSIP
    add  s8, s8, t1
    li   t1, 1
    sw   t1, 0(s8)                  # msip[h] = 1, WHILE IT IS IN DEBUG MODE

    # Watch the level.  A cleared level is an EVENT and reports at once; the
    # budget's expiry is the ordinary, correct outcome.
    li   t6, WIN_BUDGET
3:  lw   t2, 0(s8)
    beqz t2, dq_level_gone
    lw   t3, O_DBGISR(s7)
    bnez t3, dq_dbgisr
    addi t6, t6, -1
    bnez t6, 3b

    lw   t2, 0(s8)                  # the level survived the whole window
    sw   t2, O_MSIP_SEEN(s7)
    lw   a2, O_ISR_CNT(s7)
    sw   a2, O_WIN_SNAP(s7)         # snapshot BEFORE the release
    li   a3, 1
    slli a1, s5, 8
    li   t2, 0x0D270007
    add  a1, a1, t2
    bne  a2, a3, dq_fail            # the counter moved: an ISR ran

    li   t1, 1                      # release this victim's stub
    sw   t1, O_GO(s7)
    addi s5, s5, 1
    li   t0, 3
    blt  s5, t0, dq_meas_loop
    j    dq_released

dq_level_gone:
    lw   a2, 0(s8)
    sw   a2, O_MSIP_SEEN(s7)
    slli a1, s5, 8
    li   t2, 0x0D270008
    add  a1, a1, t2
    j    dq_fail

dq_dbgisr:
    lw   a2, O_DBGISR(s7)
    lw   a3, O_ISR_CNT(s7)
    slli a1, s5, 8
    li   t2, 0x0D270006
    add  a1, a1, t2
    j    dq_fail

dq_released:
    # ==================================================================
    # 3. THE POST-RESUME CONFIRMATION.  The same still-pending msip must
    # be taken as soon as debug mode ends.  This is what stops a PASS
    # from meaning "the interrupt was never deliverable".
    # ==================================================================
    li   s5, 1
dq_post_loop:
    slli s6, s5, 6
    li   s7, BLK_BASE
    add  s7, s7, s6
    li   t6, ARM_BUDGET
1:  lw   t2, O_ISR_CNT(s7)
    li   t1, 2
    beq  t2, t1, 2f
    addi t6, t6, -1
    bnez t6, 1b
    lw   a2, O_ISR_CNT(s7)
    slli a1, s5, 8
    li   t2, 0x0D270009
    add  a1, a1, t2
    j    dq_fail
2:  addi s5, s5, 1
    li   t0, 3
    blt  s5, t0, dq_post_loop

    # ---- and both victims must come back out ----------------------------
    li   t0, 0x10880
    li   t1, 1
    sw   t1, O_REL(t0)
    li   t0, 0x108C0
    sw   t1, O_REL(t0)
    li   t6, ARM_BUDGET
dq_wpost:
    li   t0, 0x10880
    lw   t2, O_POST(t0)
    li   t0, 0x108C0
    lw   t3, O_POST(t0)
    beqz t2, dq_wpost_next
    bnez t3, dq_done
dq_wpost_next:
    addi t6, t6, -1
    bnez t6, dq_wpost
    li   s5, 1
    mv   a2, t2
    beqz t2, 1f
    li   s5, 2
    mv   a2, t3
1:  slli a1, s5, 8
    li   t2, 0x0D27000A
    add  a1, a1, t2
    j    dq_fail

dq_ctrl_done:
dq_done:
    li   t0, 0x10900                # block(3); the bystander must still work
    lw   a2, O_CNT(t0)
    li   t1, 8
    li   a1, 0x0D27000B
    blt  a2, t1, dq_fail
    RVTEST_PASS

dq_fail:
    RVTEST_FAIL

    # =====================================================================
    # plants -- both addresses, for the dbgexcmp.S reason
    # =====================================================================
dq_plant_shared:
    la   t0, dq_stub_start
    la   t1, dq_stub_end
    li   t2, 0x10780
    j    dq_copy
dq_plant_tcm:
    la   t0, dq_stub_start
    la   t1, dq_stub_end
    li   t2, 0xBE00
dq_copy:
1:  lw   t3, 0(t0)
    sw   t3, 0(t2)
    addi t0, t0, 4
    addi t2, t2, 4
    blt  t0, t1, 1b
    ret

    # =====================================================================
    # THE DEBUG STUB.  Relocation rules as in every D-series stub.  It opens
    # the pending-interrupt WINDOW, publishes IN_DEBUG, and spins until hart 0
    # plants GO -- so the window is bounded by an EVENT, not by a delay, and
    # the ISR (if a broken build runs one) can see WINDOW set and say so.
    # The spin is bounded too: a build that never lets hart 0's store land
    # must not hang the run.
    # =====================================================================
    .option push
    .option arch, +zicsr
dq_stub_start:
    csrr t2, dscratch0
    addi t2, t2, 1
    csrw dscratch0, t2
    csrr a4, mhartid
    slli a3, a4, 6
    li   a5, BLK_BASE
    add  a5, a5, a3
    sw   t2, O_ENTRIES(a5)
    li   t0, 1
    sw   t0, O_WINDOW(a5)           # the ISR's discriminator, set FIRST
    sw   t0, O_IN_DEBUG(a5)         # ...then the word hart 0 waits on
    li   t1, 200000
1:  lw   t0, O_GO(a5)
    bnez t0, 2f
    addi t1, t1, -1
    bnez t1, 1b
2:  sw   x0, O_WINDOW(a5)
    .word DRET_INSN
dq_stub_end:
    .option pop

    # =====================================================================
    # THE ISRs.  Both do the same three things: clear the msip LEVEL, count,
    # and -- if this hart's WINDOW is open -- record that an interrupt was
    # taken in debug mode.  They differ only in how they were entered and how
    # they return, which is the whole point of running two polarities.
    # `la` is legal here: these live at their linked addresses and are never
    # relocated (only the stub above is).
    # =====================================================================
    .option push
    .option arch, +zicsr
dq_msip_isr:                        # LEGACY: IVT slot 83, hardware-vectored
    addi sp, sp, -20
    sw   t0, 0(sp)
    sw   t1, 4(sp)
    sw   t2, 8(sp)
    sw   t3, 12(sp)
    sw   t4, 16(sp)
    csrr t3, mhartid
    slli t4, t3, 6
    li   t0, BLK_BASE
    add  t0, t0, t4                 # t0 = block(h)
    slli t1, t3, 2
    li   t2, CLINT_MSIP
    add  t1, t1, t2
    sw   x0, 0(t1)                  # clear MSIP[h] -- the LEVEL, first
    lw   t1, O_ISR_CNT(t0)
    addi t1, t1, 1
    sw   t1, O_ISR_CNT(t0)
    li   t2, 1
    sw   t2, O_CTRL(t0)
    lw   t2, O_WINDOW(t0)
    beqz t2, 1f
    li   t2, DBGISR_MAGIC
    sw   t2, O_DBGISR(t0)           # AN ISR RAN IN DEBUG MODE
1:  lw   t0, 0(sp)
    lw   t1, 4(sp)
    lw   t2, 8(sp)
    lw   t3, 12(sp)
    lw   t4, 16(sp)
    addi sp, sp, 20
    iret

dq_mtvec:                           # STANDARD: mtvec, mcause-decoded, mret
    addi sp, sp, -20
    sw   t0, 0(sp)
    sw   t1, 4(sp)
    sw   t2, 8(sp)
    sw   t3, 12(sp)
    sw   t4, 16(sp)
    csrr t3, mhartid
    slli t4, t3, 6
    li   t0, BLK_BASE
    add  t0, t0, t4
    slli t1, t3, 2
    li   t2, CLINT_MSIP
    add  t1, t1, t2
    sw   x0, 0(t1)                  # clear MSIP[h]
    lw   t1, O_ISR_CNT(t0)
    addi t1, t1, 1
    sw   t1, O_ISR_CNT(t0)
    li   t2, 1
    sw   t2, O_CTRL(t0)
    lw   t2, O_WINDOW(t0)
    beqz t2, 1f
    li   t2, DBGISR_MAGIC
    sw   t2, O_DBGISR(t0)
1:  lw   t0, 0(sp)
    lw   t1, 4(sp)
    lw   t2, 8(sp)
    lw   t3, 12(sp)
    lw   t4, 16(sp)
    addi sp, sp, 20
    mret
    .option pop

    # ---- extend the env IVT: DEFINE_IVT emitted slots 0-82 ---------------
    # Slot 83 = IRQB_CLINT_MSIP, the LEGACY delivery path this file needs.
    # The staged image carries this IVT into every tile's TCM, overwriting the
    # bootrom loader's own slot-83 arming -- which is exactly what the loader
    # contract expects a launched image to do.
    .section .ivt, "ax"
    .org 0x14C
    jal  zero, dq_msip_isr          # slot 83 = IRQB_CLINT_MSIP
    jal  zero, 0x0BB00              # slot 84 = mtip: parked
    .previous

    # ---- tile harts enter here (loader ABI: only sp is defined) ----------
tile_entry:
    li   sp, 0xBFF0
    jal  ra, dq_plant_tcm
    .option push
    .option arch, +zicsr
    csrr t3, mhartid
    .option pop
    slli s6, t3, 6
    li   s7, BLK_BASE
    add  s7, s7, s6

    li   t4, 3
    beq  t3, t4, dq_bystander

    .option push
    .option arch, +zicsr
    li   t4, 2
    bne  t3, t4, 1f
    # ---- hart 2 only: STANDARD delivery ------------------------------
    csrw MTRAPCTL, x0
    la   t0, dq_mtvec
    csrw mtvec, t0
    li   t0, MIE_MSIE
    csrs mie, t0
    li   t0, MSTATUS_MIE
    csrs mstatus, t0
1:
    .option pop

    li   t0, 1
    sw   t0, O_READY(s7)            # publish LAST: armed and about to park

    # The park is a counting loop, so "it resumed" is observable, and it holds
    # no live register across an iteration except its own block pointer.
dq_park:
    lw   t0, O_CNT(s7)
    addi t0, t0, 1
    sw   t0, O_CNT(s7)
    lw   t1, O_REL(s7)
    beqz t1, dq_park
    li   t0, POST_MAGIC
    sw   t0, O_POST(s7)
dq_vpark:
    j    dq_vpark

dq_bystander:
    lw   t0, O_CNT(s7)
    addi t0, t0, 1
    sw   t0, O_CNT(s7)
    j    dq_bystander

    # NOTE: RVTEST_CODE_END is `unimp` in this env (it traps) -- never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
