# See LICENSE for license details.

#*****************************************************************************
# shtcm.S  (CPR4 — the TAPE-OUT-CONFIG orchestrator test: read-only TCM
#           apertures, CPR3/R3 + amendments A1/A2/A3)
#-----------------------------------------------------------------------------
# THE ONE ORCHESTRATOR TEST THAT RUNS ON THE TAPE-OUT CONFIGURATION. `shorch`
# keys on the AFE/EIS stub bank and is therefore penta-only (wound drops
# cqAfeStubs); the TCM apertures exist wherever the ORCHESTRATOR does, so this
# file's CATALOG tag is `tiles orch` and it is selected on penta AND
# penta_wound. It is the rehearsed successor of the CPR3 scratch file `zztcmw.S`
# (parked in ~/work/chip_docs/castalia/castalia_penta/): leg A below is that
# file's graded self-read leg, absorbed verbatim, because it is the ONLY
# chip-level coverage of the A3 fix.
#
#   hart 0        = the always-on soft ORCHESTRATOR: boot master, management
#                   hart (the ONE master the apertures answer), tb a0 gate.
#   harts 1..N-1  = the gateable channel tiles.
#
# TCM APERTURE MAP (CPR3/R3). Hart h's private TCM byte B is readable at
#     TCMWIN[h] + (B - 0x8000),  TCMWIN[h] = 0x20000 + 0x4000*h
# so the two marker words at TCM 0xBF00/0xBF04 (above the ISR bank 0xBAFF, far
# below the stack top 0xBFF0) appear at window offset 0x3F00/0x3F04:
#     hart 0 -> 0x23F00   hart 1 -> 0x27F00   hart 2 -> 0x2BF00
#     hart 3 -> 0x2FF00   hart 4 -> 0x33F00
# The port is READ-ONLY, MANAGEMENT-HART-ONLY, and a gated tile's aperture
# completes with zeros (R4/R4-A2). tcm_ext_addr is a TCM WORD index; the
# request is held until done and must drop >= 1 mclk between transactions
# (one-shot rearm); latency is 6 mclk, deterministic.
#
# THE SIX LEGS, IN ORDER, AND WHAT EACH ONE IS FOR
#   READY  every tile plants TWO distinct words in its OWN TCM and publishes
#          READY[h]. Distinct per (hart, word) means no window can alias
#          another and hide: reading tile 3 and getting tile 2's marker is a
#          FAIL, not a coincidence.
#   A      hart 0 reads its OWN window (0x23F00) EIGHT times and SURVIVES it —
#          the CPR3b/A3 leg. THE GRADE IS NOT THE VALUE, IT IS THE SURVIVAL:
#          at CPR3 the data was right (the marker came back six mclk after the
#          request) and the reading core's INSTRUCTION STREAM was not (PC
#          0x83E0 -> 0x842E, into another hart's payload, then tile_park, so a0
#          was never written and the test died on the tb watchdog). Root cause:
#          hart_tile's Q shadow released on a tx_busy-derived timer while the
#          core stays frozen for the WHOLE arbiter transaction (the aperture
#          slave holds s_stall), so live Q — a function of the EXTERNAL address
#          — reached the frozen core's fetch path. The straight-line canaries
#          after the loop are the survival assertion: they are reachable ONLY
#          by executing the instructions the assembler actually emitted. All
#          four tiles are spinning on the shared bus throughout, which is what
#          makes the arbiter transaction — and hart 0's freeze — long.
#   B      hart 0 reads EVERY tile's window: both marker words per tile, then
#          word 0 a second time (the one-shot rearm — a slave that held req
#          across two accesses would get one done and wait forever here).
#   C      NEGATIVE CONTROL WITH A VACUITY GUARD. Tile 2 reads tile 1's window
#          AND hart 0's window: both are DENIED (s_master /= 0) and must read
#          0. In the same breath the same tile reads an ordinary shared word
#          (READY[1], planted nonzero by tile 1) and must SEE it — so "0" is a
#          denial and not a dead prober. Then it publishes DRPT nonzero: hart 0
#          FAILs if DRPT is zero, because a probe that never ran would leave
#          DSEEN at the bootrom's zero and pass a vacuous control.
#   E      WRITE-DROPPED. Hart 0 writes poison to a live tile's window and to
#          its own, and both words read back UNCHANGED (the aperture launches
#          only on sh_we = "0000"; a write is answered with zeros and never
#          reaches the tile).
#   D      THE R4-A2 PROOF. Gate tile 1 (PWRCR bit 1; PWRSR nibble 1 == 3 =
#          OFF) and read its window eight times. THE ASSERTION IS THE
#          TERMINATION: a gated tile's tcm_ext_done is iso-clamped to 0, so an
#          aperture slave that waited for it would hang the shared bus behind a
#          sleeping tile with the management hart stalled on it — that failure
#          is a 100 ms watchdog timeout, not a FAIL. Each read must RETURN and
#          must return zero. Then an ordinary shared read proves the bus
#          survived, PWRCR = 0 re-ignites the tile, and the tile is RELAUNCHED
#          (its TCM is cold — wake is an M12 cold boot) to plant DIFFERENT
#          markers, which hart 0 reads through the same window: the recovery
#          is proven by data that can only have come from the re-ignited tile.
#   A'     the self-read again, in a different chip state (one tile has been
#          through a full gate/wake cycle). Hart 0's window is never gated
#          (R4-A2), so it must still answer and must still be survivable.
#
# Shared-word ledger (CPR4; LEDGER RULE: the per-hart array is 4*NHARTS bytes
# and every control word follows it at base + 4*NHARTS + k, so a bigger N can
# never overrun them; all < 0x10500 and inside the bootrom zero range):
#     READY[h] = 0x103F0 + 4*h      h = 0..N-1 (h=0 unused, uniform indexing
#                                   with TCMWIN[h] — the map this test walks)
#     DSEEN    = 0x103F0 + 4*NHARTS      (N=5: 0x10404) tile 2's denied reads,
#                                   ORed: ANY nonzero bit fails
#     DCTRL    = DSEEN + 4               (N=5: 0x10408) tile 2's vacuity read
#     DRPT     = DSEEN + 8               (N=5: 0x1040C) "the probe ran"
#   Claim = the 8-word block 0x103F0-0x1040C at N=5. Free there: shexec's
#   DONE[h] tops out at 0x103E8 below and shfault's HEARTBEAT starts 0x10440
#   above. At N=18 the block would overlap shexec's DONE tail — benign AND
#   unreachable: this row selects only on `orch`, and no 18-hart orchestrator
#   configuration exists (Argus has no orchestrator), on top of the
#   one-image-per-sim isolation rule.
#
# BUDGETS. MP_STAGE_IMAGE(1024) — 4 KiB carries the IVT and this payload; a
# full 16 KiB copy per launch costs ~4 ms of tile time and four of them would
# crowd the 100 ms tb watchdog. Post-launch gathers are 400000 iterations
# (the zztcmw-proven value; it covers four serialized ROM copies under
# four-way bus contention). NOTE the deliberate tradeoff, since the house rule
# on retry budgets is the opposite one: a 400000-iteration SHARED-bus poll
# does not trip inside the watchdog, so if a launch never lands this reports
# as a HANG and not as a clean FAIL. That is accepted here and only here — a
# tile that has not booted within four ROM copies is a hang either way. Every
# other bound in this file (20000) trips well inside the watchdog.
#
# No smclk-domain peripheral is touched (pwr_ctrl and the apertures are mclk),
# so the bootrom SMCLK->LFXT trap does not apply.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"                /* NHARTS (5 on an orchestrator build) */

#define PWRCTRL_BASE  0x4B00        /* PWRCR +0, PWRSR0 +4 (nibble per hart) */

#define TCM_MARK      0xBF00        /* private TCM marker pair (0xBF00/0xBF04) */
#define WIN_MARK      0x3F00        /* ...its offset inside a 0x4000 window */
#define WIN0          0x23F00       /* TCMWIN[0] + WIN_MARK (hart 0, itself)  */
#define WIN1          0x27F00       /* TCMWIN[1] + WIN_MARK (tile 1)          */
#define WIN_STRIDE    0x4000

#define READY_BASE    0x103F0
#define DSEEN         (READY_BASE + 4*NHARTS)
#define DCTRL         (DSEEN + 4)
#define DRPT          (DSEEN + 8)

#define MARK_BASE     0x7C300000    /* marker = MARK_BASE + (h<<12) + word    */
#define REMARK1       0x7C3B0001    /* tile 1's POST-WAKE markers (only the   */
#define REMARK2       0x7C3B0002    /*  re-ignited tile can have planted them)*/
#define READY_MAGIC   0xC0DE0000    /* READY[h] = READY_MAGIC + h             */
#define REREADY       0xC0DE0101    /* ...and after the relaunch, tile 1 only */
#define DRPT_MAGIC    0xD00D0002    /* tile 2 really executed the probe       */
#define POISON        0xBAD0BAD0    /* what a dropped window write would land */

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry        # only hart 0 runs the orchestration

    li   sp, 0xBFF0             # private TCM top; IRQ_SV pushes PC at sp-4
    li   s2, READY_BASE
    li   s4, PWRCTRL_BASE

    # ---- stage the image, then plant hart 0's OWN marker pair -------------
    MP_STAGE_IMAGE(1024)
    li   t0, TCM_MARK
    li   t1, MARK_BASE + 1      # h = 0
    sw   t1, 0(t0)
    li   t1, MARK_BASE + 2
    sw   t1, 4(t0)

    # ---- launch every tile; each plants its pair and publishes READY[h] ---
    MP_LAUNCH_ALL(tile_entry, 1024)

    li   s7, 1
h0_rdy:
    li   t6, 400000             # covers four serialized ROM copies (header)
    slli t0, s7, 2
    add  t0, t0, s2             # &READY[h]
    li   t1, READY_MAGIC
    add  t1, t1, s7
h0_rdyw:
    lw   t2, 0(t0)
    beq  t2, t1, h0_rdyn
    addi t6, t6, -1
    bnez t6, h0_rdyw
    j    shtcm_fail
h0_rdyn:
    addi s7, s7, 1
    li   t0, NHARTS
    bltu s7, t0, h0_rdy

    # ======== LEG A: hart 0 reads its OWN aperture (A3) ====================
    # See the header: the value is checked eight times, but the GRADE is that
    # the canaries after the loop execute at all.
    li   s7, 8
a_loop:
    li   t0, WIN0
    lw   t1, 0(t0)              # THE SELF-READ
    li   t2, MARK_BASE + 1
    bne  t1, t2, shtcm_fail
    addi s7, s7, -1
    bnez s7, a_loop
    li   t3, 0x5A5A0001         # straight-line canary: only reachable by
    li   t4, 0x5A5A0001         # executing the instructions after the read
    bne  t3, t4, shtcm_fail
    li   t0, WIN0               # ...and the second marker word, to prove the
    lw   t1, 4(t0)              # window ADDRESS decode is real
    li   t2, MARK_BASE + 2
    bne  t1, t2, shtcm_fail

    # ======== LEG B: hart 0 reads EVERY tile's window ======================
    li   s7, 1
b_tile:
    slli t5, s7, 14             # h * WIN_STRIDE (0x4000) — a SHIFT, never a
                                # `mul`: the image build's march has no M on
                                # a mul-off configuration
    li   t0, 0x20000 + WIN_MARK
    add  s5, t5, t0             # s5 = &window[h] marker word 0
    li   t4, MARK_BASE
    slli t0, s7, 12
    add  t4, t4, t0             # t4 = tile h's marker base
    lw   t1, 0(s5)
    addi t2, t4, 1
    bne  t1, t2, shtcm_fail
    lw   t1, 4(s5)
    addi t2, t4, 2
    bne  t1, t2, shtcm_fail
    lw   t1, 0(s5)              # AGAIN: the one-shot rearm (req must go low
    addi t2, t4, 1              # >= 1 mclk between transactions)
    bne  t1, t2, shtcm_fail
    addi s7, s7, 1
    li   t0, NHARTS
    bltu s7, t0, b_tile

    # ======== LEG C: the DENIED prober + its vacuity guard =================
    li   t6, 400000
    li   s5, DRPT
    li   s6, DRPT_MAGIC
c_wait:
    lw   t2, 0(s5)
    beq  t2, s6, c_have
    addi t6, t6, -1
    bnez t6, c_wait
    j    shtcm_fail
c_have:
    li   t0, DSEEN
    lw   t1, 0(t0)
    bnez t1, shtcm_fail         # BOTH denied window reads must be 0
    li   t0, DCTRL              # ...and the prober was ALIVE: it read an
    lw   t1, 0(t0)              # ordinary shared word in the same breath
    li   t2, READY_MAGIC + 1
    bne  t1, t2, shtcm_fail

    # ======== LEG E: a write to a window is DROPPED ========================
    li   t0, WIN1
    li   t1, POISON
    sw   t1, 0(t0)              # dropped (read-only aperture, no bus error)
    lw   t2, 0(t0)
    li   t3, MARK_BASE + 0x1000 + 1
    bne  t2, t3, shtcm_fail     # tile 1's word must be UNCHANGED
    li   t0, WIN0
    li   t1, POISON
    sw   t1, 0(t0)              # ...and hart 0 cannot even write its own
    lw   t2, 0(t0)
    li   t3, MARK_BASE + 1
    bne  t2, t3, shtcm_fail
    li   t0, TCM_MARK           # the PRIVATE path is untouched by all this
    lw   t2, 0(t0)
    bne  t2, t3, shtcm_fail

    # ======== LEG D: gate tile 1, read its dark window, recover ============
    li   t1, 2
    sw   t1, 0(s4)              # PWRCR: gate tile 1
    li   t6, 20000
d_off:
    lw   t2, 4(s4)              # PWRSR
    srli t3, t2, 4
    andi t3, t3, 0xF
    li   t4, 3                  # 3 = OFF
    beq  t3, t4, d_isoff
    addi t6, t6, -1
    bnez t6, d_off
    j    shtcm_fail
d_isoff:
    li   s5, 8                  # eight reads of a DARK tile's window
d_dark:
    li   t0, WIN1
    lw   t1, 0(t0)              # must COMPLETE (no hang) and read 0
    bnez t1, shtcm_fail
    li   t0, WIN1               # ...the second word too
    lw   t1, 4(t0)
    bnez t1, shtcm_fail
    addi s5, s5, -1
    bnez s5, d_dark

    li   t0, WIN_STRIDE * 2 + 0x20000 + WIN_MARK
    lw   t1, 0(t0)              # a LIVE tile's window still answers with the
    li   t2, MARK_BASE + 0x2000 + 1     # gated one's slave sitting dark
    bne  t1, t2, shtcm_fail
    li   t0, READY_BASE + 8     # ...and an ordinary shared word still works
    lw   t1, 0(t0)              # READY[2]
    li   t2, READY_MAGIC + 2
    bne  t1, t2, shtcm_fail

    # ---- re-ignite and RELAUNCH: wake is an M12 cold boot, so the tile's
    # ---- TCM is gone and only a re-run tile can plant the NEW markers.
    sw   x0, 0(s4)              # PWRCR = 0: all tiles run
    li   t6, 20000
d_on:
    lw   t2, 4(s4)
    srli t3, t2, 4
    andi t3, t3, 0xF
    beqz t3, d_ison
    addi t6, t6, -1
    bnez t6, d_on
    j    shtcm_fail
d_ison:
    li   t6, 20000              # ROM re-park settle (the tile's boot path is
d_settle:                       # a few hundred mclk; this is >100x, still far
    lw   t2, 4(s4)              # inside the 100 ms watchdog)
    addi t6, t6, -1
    bnez t6, d_settle

    MP_LAUNCH_HART(1, tile_replant, 1024)
    li   t6, 400000
    li   t0, READY_BASE + 4     # READY[1]
    li   t1, REREADY
d_rdy:
    lw   t2, 0(t0)
    beq  t2, t1, d_have
    addi t6, t6, -1
    bnez t6, d_rdy
    j    shtcm_fail
d_have:
    li   t0, WIN1               # THE RECOVERY PROOF: real data again, and it
    lw   t1, 0(t0)              # is data only the re-ignited tile can have
    li   t2, REMARK1            # planted
    bne  t1, t2, shtcm_fail
    lw   t1, 4(t0)
    li   t2, REMARK2
    bne  t1, t2, shtcm_fail

    # ======== LEG A': the self-read in the post-gate chip state ============
    li   t0, WIN0
    lw   t1, 0(t0)
    li   t2, MARK_BASE + 1
    bne  t1, t2, shtcm_fail
    li   t3, 0x5A5A0002         # the survival canary again
    li   t4, 0x5A5A0002
    bne  t3, t4, shtcm_fail

    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin

shtcm_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # ================= the tiles ==========================================
    # Every tile plants its own distinct marker pair, publishes READY[h] and
    # then HAMMERS the shared bus forever — that traffic is what makes hart
    # 0's aperture transactions long, which is the R4-A1 contention the Q
    # shadow exists for (and what killed the reading core before CPR3b).
tile_entry:
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # re-derive (undefined on a launched hart)
    .option pop
    li   sp, 0xBFF0

    li   t4, MARK_BASE
    slli t0, s10, 12
    add  t4, t4, t0             # my marker base
    li   t0, TCM_MARK
    addi t1, t4, 1
    sw   t1, 0(t0)              # PRIVATE TCM stores — the words hart 0 will
    addi t1, t4, 2
    sw   t1, 4(t0)              # read back through my window

    li   s2, READY_BASE
    slli t0, s10, 2
    add  s3, t0, s2             # &READY[h]
    li   t1, READY_MAGIC
    add  t1, t1, s10
    sw   t1, 0(s3)

    li   t0, 2
    beq  s10, t0, tile2_probe   # tile 2 is also the DENIED prober

tile_spin:
    li   a0, 0xCAFEBABE         # inline PASS (tb latches a0_1..a0_4); my part
ts_loop:                        # is done, and from here I keep the shared bus
    lw   t2, 0(s3)              # busy under hart 0's aperture reads (R4-A1)
    j    ts_loop

    # ---- tile 2: the negative control, with its own vacuity witness ------
tile2_probe:
    li   t6, 400000             # tile 1 must have planted first, or "0" would
    li   t0, READY_BASE + 4     # be an empty word rather than a denial
    li   t1, READY_MAGIC + 1
t2_wait:
    lw   s6, 0(t0)
    beq  s6, t1, t2_go
    addi t6, t6, -1
    bnez t6, t2_wait
    li   a0, 0xDEADBEEF         # tb latches a0_2: a prober that never armed
1:  j    1b                     # is a FAIL, not a silent pass
t2_go:
    li   t0, WIN1
    lw   s7, 0(t0)              # DENIED: another hart's window
    li   t0, WIN0
    lw   s8, 0(t0)              # DENIED: the orchestrator's own window
    or   s7, s7, s8             # ANY nonzero bit from either read fails
    li   t0, READY_BASE + 4
    lw   s9, 0(t0)              # THE VACUITY CONTROL: an ordinary shared word
    li   t0, DSEEN
    sw   s7, 0(t0)
    li   t0, DCTRL
    sw   s9, 0(t0)
    li   t0, DRPT
    li   t1, DRPT_MAGIC
    sw   t1, 0(t0)              # "the probe really ran"
    j    tile_spin

    # ---- tile 1 after the gate/wake cycle: NEW markers (its TCM is cold) --
tile_replant:
    li   sp, 0xBFF0
    li   t0, TCM_MARK
    li   t1, REMARK1
    sw   t1, 0(t0)
    li   t1, REMARK2
    sw   t1, 4(t0)
    li   s3, READY_BASE + 4     # READY[1]
    li   t1, REREADY
    sw   t1, 0(s3)
    j    tile_spin

    # ---- extend the env IVT: slots 83/84 must never fire here ------------
    # (launch msips are consumed by the ROM loader's own ISR, never by us)
    .section .ivt, "ax"
    .org 0x14C
    jal  zero, shtcm_fail       # slot 83 = IRQB_CLINT_MSIP
    jal  zero, shtcm_fail       # slot 84 = IRQB_CLINT_MTIP
    .previous

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
