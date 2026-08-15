# See LICENSE for license details.

#*****************************************************************************
# shpwr.S  (M17 — MTCMOS cold-gate power gating; N-AWARE since CPR4)
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
# WHAT CPR4 CHANGED, AND WHY. Two defects, both N-shaped:
#   (1) The "other tiles are still ON" check read nibbles 2+3 of PWRSR with a
#       hardcoded 0xFF mask. At NHARTS=5 (CPR3/R2 makes pwr_ctrl see numHarts,
#       so PWRCR gains bit 4 and PWRSR gains nibble 4) that mask is BLIND to a
#       live nibble 4 — the check would pass with tile 4 gated underneath it.
#       The nibble walk is now derived from NHARTS and covers every tile row
#       the configuration actually has (`chk_nib`).
#   (2) NO TEST PROVED THE TOP GATE BIT. Every episode gated tile 1 only, so
#       PWRCR bit NHARTS-1 — bit 4 on a penta chip, the bit CPR3/R2 added, and
#       the one whose tile was NOT gateable before the renumber — had no
#       coverage at all. Episode 2 below gates and wakes tile NHARTS-1 with the
#       full live-tile treatment (launch, alive, gate, dead, wake, relaunch).
#       Written as NHARTS-1 rather than 4 so it is the TOP tile at any hart
#       count: at N=4 it exercises tile 3 and the test stays green there.
#
# Hart 0 (SPI boot):
#   1. stage this image; LAUNCH tile 1 into tile_entry (a shared-word hammer)
#   2. prove tile 1 is ALIVE (hammer word changes between two samples)
#   3. PWRCR = 2 (gate tile 1); poll PWRSR nibble 1 == 3 (OFF); walk EVERY
#      other tile nibble and require ON; verify PWRCR reads back 2
#   4. prove tile 1 is DEAD (hammer word FROZEN across a delay — this also
#      exercises gating a tile with transactions in flight: the clamped/reset
#      req must look RELEASED to the wait-for-release arbiter, never wedging
#      the shared bus; hart 0 keeps using the window throughout)
#   5. PWRCR = 0 (wake); poll PWRSR nibble 1 == 0 (ON); delay for the tile's
#      ROM re-park (cold boot: sp, IVT slot 83 arm, WFI — no park signal
#      exists, the settle delay covers it with >100x margin)
#   6. RELAUNCH tile 1 into tile_done via the ordinary loader row + msip;
#      bounded-wait for its magic.
#   7. EPISODE 2, THE TOP TILE (hart NHARTS-1): launch it into the hammer,
#      prove alive, gate it (PWRCR bit NHARTS-1) with tile 1 still running its
#      done payload, walk the nibbles (the top tile OFF, every other tile
#      including the live tile 1 ON), prove dead, wake, relaunch into
#      tile_done2. PASS.
#
# Shared words (>= 0x10470, clear of shfault.S's 0x10440-0x10468 tail at N=5):
#     HAMMER = 0x10470   the live counter (phase 1 payload, both episodes)
#     PDONE  = 0x10474   0xCAFE0001 from the relaunched tile 1
#     PDONE2 = 0x10478   0xCAFE000<NHARTS-1> from the relaunched TOP tile
#   Three fixed words, N-agnostic (no hartid-indexed word), all inside the
#   bootrom zero range and below shafe's GO at 0x10480. PDONE2 is a SEPARATE
#   word rather than a per-hart array on purpose: tile 1's done payload spins
#   verifying that its own magic SURVIVES, so a second tile writing the same
#   word would fail the first tile rather than prove anything.
#
# Tiles never launched stay parked in the ROM the whole test; the nibble walk
# proves they also stay ON.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"                /* NHARTS (4 default, 5 on a penta build) */

#define PWRCTRL_BASE 0x4B00
#define SHPWR_HAMMER 0x10470
#define SHPWR_PDONE  0x10474
#define SHPWR_PDONE2 0x10478

#define TOPTILE      (NHARTS - 1)   /* the highest gateable tile at this N */
#define TOPBIT       (1 << TOPTILE) /* ...its PWRCR bit */
#define TOPSHIFT     (4 * TOPTILE)  /* ...its PWRSR nibble position */

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
    # every OTHER tile must still read ON (0) — the SAME sample, walked over
    # the nibbles this NHARTS actually has (CPR4: nibble NHARTS-1 exists now)
    li   s5, 1                  # the gated one
    jal  ra, chk_nib
    lw   t2, 0(s4)              # PWRCR readback
    li   t3, 2
    bne  t2, t3, shpwr_fail

    # ---- 4. tile dead: hammer FROZEN across a real delay ------------------
    lw   s6, 0(s2)              # sample A
    li   t6, 256
dead_delay:                     # keep the shared bus BUSY meanwhile (the
    lw   t2, 4(s4)              #  arbiter must stay perfectly usable with a
    addi t6, t6, -1             #  gated master — release-valve proof)
    bnez t6, dead_delay
    lw   t2, 0(s2)              # sample B
    bne  t2, s6, shpwr_fail     # any change = the tile survived the gate

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

    # ======== 7. EPISODE 2: the TOP tile (PWRCR bit NHARTS-1) =============
    # Tile 1 is now running its done payload on the shared bus, so this
    # episode also proves the gate is SELECTIVE with a live neighbour.
    li   s8, SHPWR_PDONE2
    MP_LAUNCH_HART(TOPTILE, tile_entry, 4096)

    li   t6, 100000
t_alive:
    lw   t2, 0(s2)              # the top tile now owns the hammer word
    lw   t3, 0(s2)
    bne  t2, t3, t_is_alive
    addi t6, t6, -1
    bnez t6, t_alive
    j    shpwr_fail
t_is_alive:

    li   t1, TOPBIT
    sw   t1, 0(s4)              # PWRCR: GATE the top tile
    li   t6, 20000
t_off_wait:
    lw   t2, 4(s4)              # PWRSR
    srli t3, t2, TOPSHIFT
    andi t3, t3, 0xF
    li   t4, 3                  # 3 = OFF
    beq  t3, t4, t_is_off
    addi t6, t6, -1
    bnez t6, t_off_wait
    j    shpwr_fail
t_is_off:
    li   s5, TOPTILE            # the gated one; tile 1 must read ON in the
    jal  ra, chk_nib            # same sample (selective gating, live neighbour)
    lw   t2, 0(s4)              # PWRCR readback
    li   t3, TOPBIT
    bne  t2, t3, shpwr_fail

    lw   s6, 0(s2)              # dead: hammer FROZEN across a real delay
    li   t6, 256
t_dead_delay:
    lw   t2, 4(s4)
    addi t6, t6, -1
    bnez t6, t_dead_delay
    lw   t2, 0(s2)
    bne  t2, s6, shpwr_fail

    sw   x0, 0(s4)              # wake
    li   t6, 20000
t_on_wait:
    lw   t2, 4(s4)
    srli t3, t2, TOPSHIFT
    andi t3, t3, 0xF
    beqz t3, t_is_on
    addi t6, t6, -1
    bnez t6, t_on_wait
    j    shpwr_fail
t_is_on:
    li   t6, 20000              # ROM re-park settle
t_park_delay:
    lw   t2, 4(s4)
    addi t6, t6, -1
    bnez t6, t_park_delay

    MP_LAUNCH_HART(TOPTILE, tile_done2, 4096)
    li   t6, 100000
t_done_wait:
    lw   t2, 0(s8)
    li   t3, 0xCAFE0000 + TOPTILE
    beq  t2, t3, t_all_done
    addi t6, t6, -1
    bnez t6, t_done_wait
    j    shpwr_fail
t_all_done:

    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin

shpwr_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # ---- chk_nib: walk PWRSR sample t2 over tile nibbles 1..NHARTS-1. The
    # ---- nibble named by s5 must read OFF (3); every other must read ON (0).
    # ---- N-DERIVED (CPR4): the old form masked nibbles 2+3 with a literal
    # ---- 0xFF and was blind to nibble 4. Clobbers t0/t1/t3/t4/t5; returns ra.
chk_nib:
    li   t5, 1
cn_loop:
    slli t0, t5, 2              # nibble position = 4h
    srl  t1, t2, t0
    andi t1, t1, 0xF
    bne  t5, s5, cn_on
    li   t4, 3
    bne  t1, t4, shpwr_fail     # the gated tile must read OFF
    j    cn_next
cn_on:
    bnez t1, shpwr_fail         # every other tile must read ON
cn_next:
    addi t5, t5, 1
    li   t0, NHARTS
    bltu t5, t0, cn_loop
    ret

    # ---- tile phase 1: hammer a shared word forever (dies by cold gate) ---
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

    # ---- top tile, phase 2: its own word, for the same reason -------------
tile_done2:
    li   sp, 0xBFF0
    li   s3, SHPWR_PDONE2
    li   t0, 0xCAFE0000 + TOPTILE
    sw   t0, 0(s3)
    li   a0, 0xCAFEBABE         # inline PASS (tb latches a0_<NHARTS-1>)
done_spin2:
    lw   t1, 0(s3)
    li   t2, 0xCAFE0000 + TOPTILE
    bne  t1, t2, tile_fail
    j    done_spin2

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
