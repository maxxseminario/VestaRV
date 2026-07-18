# See LICENSE for license details.

#*****************************************************************************
# shpwr.S  (M17 — MTCMOS cold-gate power gating)
#-----------------------------------------------------------------------------
# THE M17 SIGNATURE TEST: gate a LIVE tile, prove it died, wake it, prove the
# wake is a clean M12 cold boot, and relaunch it to a payload PASS.
#
# pwr_ctrl (window slot 11 @0x4B00): PWRCR bit h gates tile hart h through a
# hardware sequencer (iso -> reset -> rail off; on wake rail on -> settle ->
# un-iso -> un-reset). Functionally the cold gate IS the reset (pd_rstn folds
# into the tile's resetn), so this test observes: the tile's shared-window
# hammer FREEZES when gated, and after wake the tile re-runs the shared-ROM
# boot, parks in WFI, and accepts a NORMAL loader relaunch.
#
# Hart 0 (SPI boot):
#   1. stage this image; LAUNCH tile 1 into tile_entry (a shared-word hammer)
#   2. prove tile 1 is ALIVE (hammer word changes between two samples)
#   3. PWRCR = 2 (gate tile 1); poll PWRSR nibble 1 == 3 (OFF); verify PWRCR
#      reads back 2
#   4. prove tile 1 is DEAD (hammer word FROZEN across a delay — this also
#      exercises gating a tile with transactions in flight: the clamped/reset
#      req must look RELEASED to the wait-for-release arbiter, never wedging
#      the shared bus; hart 0 keeps using the window throughout)
#   5. PWRCR = 0 (wake); poll PWRSR nibble 1 == 0 (ON); delay for the tile's
#      ROM re-park (cold boot: sp, IVT slot 83 arm, WFI — no park signal
#      exists, the settle delay covers it with >100x margin)
#   6. RELAUNCH tile 1 into tile_done via the ordinary loader row + msip;
#      bounded-wait for its magic. PASS.
#
# Shared words (>= 0x10470, clear of shfault.S's 0x10440-0x10463):
#     HAMMER = 0x10470   tile 1's live counter (phase 1 payload)
#     PDONE  = 0x10474   0xCAFE0001 from the relaunched tile (phase 2)
#
# Tiles 2/3 stay parked in the ROM the whole test (never launched, never
# gated) — a PWRSR readback proves their nibbles stay 0 (ON).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define PWRCTRL_BASE 0x4B00
#define SHPWR_HAMMER 0x10470
#define SHPWR_PDONE  0x10474

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry        # only hart 0 runs the sequence (safety)

    li   sp, 0xBFF0             # private TCM top; IRQ_SV pushes PC at sp-4
    li   s2, SHPWR_HAMMER
    li   s3, SHPWR_PDONE
    li   s4, PWRCTRL_BASE

    # ---- 1. stage + LAUNCH tile 1 into the hammer ------------------------
    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_HART(1, tile_entry, 4096)

    # ---- 2. tile alive: hammer must be CHANGING --------------------------
    li   t6, 100000             # covers the post-launch ROM copy (M12 budget)
alive_wait:
    lw   t2, 0(s2)              # sample A
    lw   t3, 0(s2)              # sample B (a hammer store lands between the
    bne  t2, t3, is_alive       #  two shared reads once the tile is running)
    addi t6, t6, -1
    bnez t6, alive_wait
    j    shpwr_fail
is_alive:

    # ---- 3. gate tile 1 ---------------------------------------------------
    li   t1, 2
    sw   t1, 0(s4)              # PWRCR: GATE bit 1
    li   t6, 20000
off_wait:
    lw   t2, 4(s4)              # PWRSR
    srli t3, t2, 4
    andi t3, t3, 0xF
    li   t4, 3                  # 3 = OFF
    beq  t3, t4, is_off
    addi t6, t6, -1
    bnez t6, off_wait
    j    shpwr_fail
is_off:
    # tiles 2/3 must still read ON (0) — nibbles 2/3 of the SAME sample
    srli t3, t2, 8
    andi t3, t3, 0xFF           # nibbles 2+3 together
    bnez t3, shpwr_fail
    lw   t2, 0(s4)              # PWRCR readback
    li   t3, 2
    bne  t2, t3, shpwr_fail

    # ---- 4. tile dead: hammer FROZEN across a real delay ------------------
    lw   s5, 0(s2)              # sample A
    li   t6, 256
dead_delay:                     # keep the shared bus BUSY meanwhile (the
    lw   t2, 4(s4)              #  arbiter must stay perfectly usable with a
    addi t6, t6, -1             #  gated master — release-valve proof)
    bnez t6, dead_delay
    lw   t2, 0(s2)              # sample B
    bne  t2, s5, shpwr_fail     # any change = the tile survived the gate

    # ---- 5. wake ----------------------------------------------------------
    sw   x0, 0(s4)              # PWRCR: all run
    li   t6, 20000
on_wait:
    lw   t2, 4(s4)              # PWRSR
    srli t3, t2, 4
    andi t3, t3, 0xF
    beqz t3, is_on
    addi t6, t6, -1
    bnez t6, on_wait
    j    shpwr_fail
is_on:
    li   t6, 20000              # ROM re-park settle (tile boot path is a few
park_delay:                     # hundred mclk; this is >100x, still far
    lw   t2, 4(s4)              # inside the 100 ms watchdog)
    addi t6, t6, -1
    bnez t6, park_delay

    # ---- 6. RELAUNCH tile 1 into the DONE payload — an ordinary M12 launch
    # (the image is still staged; the msip is consumed by the FRESH ROM's
    # loader ISR, proving the cold boot re-armed the whole launch machinery)
    MP_LAUNCH_HART(1, tile_done, 4096)
    li   t6, 100000
done_wait:
    lw   t2, 0(s3)
    li   t3, 0xCAFE0001
    beq  t2, t3, all_done
    addi t6, t6, -1
    bnez t6, done_wait
    j    shpwr_fail
all_done:

    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin

shpwr_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # ---- tile 1, phase 1: hammer a shared word forever (dies by cold gate)
tile_entry:
    li   sp, 0xBFF0
    li   s2, SHPWR_HAMMER
    li   t0, 0
hammer_loop:
    addi t0, t0, 1
    sw   t0, 0(s2)
    j    hammer_loop            # no exit: only the power gate ends this

    # ---- tile 1, phase 2: post-wake relaunch proof ------------------------
tile_done:
    li   sp, 0xBFF0
    li   s3, SHPWR_PDONE
    li   t0, 0xCAFE0001
    sw   t0, 0(s3)              # the relaunch magic
    li   a0, 0xCAFEBABE         # inline PASS (tb latches a0_1)
done_spin:                      # forever: the magic must survive
    lw   t1, 0(s3)
    li   t2, 0xCAFE0001
    bne  t1, t2, tile_fail
    j    done_spin
tile_fail:
    li   a0, 0xDEADBEEF
1:  j    1b

    # ---- extend the env IVT: slots 83/84 must never fire in this test ----
    .section .ivt, "ax"
    .org 0x14C
    jal  zero, shpwr_fail       # slot 83 = IRQB_CLINT_MSIP (launches are
    jal  zero, shpwr_fail       #  eaten by the ROM loader, never by us)
    .previous

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
