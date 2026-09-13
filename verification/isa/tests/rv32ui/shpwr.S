# See LICENSE for license details.

# VestaRV: MTCMOS cold-gate power gating of a live tile
# pwr_ctrl at 0x4B00 gates tile hart h through a hardware sequencer, isolating, resetting and cutting the rail, and on wake restoring the rail, settling, un-isolating and releasing reset. FUNCTIONALLY THE COLD GATE IS THE RESET, because pd_rstn folds into the tile's resetn, so the observable is that the tile's shared-window hammer FREEZES when gated and that after wake the tile re-runs the shared-ROM boot, parks in WFI and accepts a NORMAL loader relaunch.
# Hart 0 stages this image and launches tile 1 into a shared-word hammer, proves it is ALIVE by sampling the hammer word twice, gates it and polls its PWRSR nibble to the OFF encoding, WALKS EVERY OTHER TILE NIBBLE and requires them ON, verifies PWRCR reads back, then proves the tile is DEAD by requiring the hammer word FROZEN across a delay. That step also exercises gating a tile with transactions in flight: the clamped and reset request must look RELEASED to the wait-for-release arbiter and must never wedge the shared bus, and hart 0 keeps using the window throughout. It then wakes the tile, polls the nibble back to ON, waits out the cold ROM re-park, and relaunches it through the ordinary loader row and msip.
# THE NIBBLE WALK IS DERIVED FROM NHARTS, NOT A FIXED MASK: a hardcoded two-nibble mask is BLIND to the nibbles a wider configuration adds, so the check would pass with a tile gated underneath it.
# EPISODE 2 GATES THE TOP TILE, hart NHARTS-1, which no earlier episode covered even though it is the bit a wider configuration adds and the one whose tile was not gateable before the renumber. It gets the full treatment, launch, alive, gate, dead, wake and relaunch, with tile 1 still running its done payload, and it is written as NHARTS-1 rather than a literal so it is the top tile at any hart count.
# Shared words, three fixed N-agnostic words with no hartid-indexed entry, all inside the bootrom zero range and clear of the neighbouring bands: HAMMER = 0x10470, the live counter used by both episodes; PDONE = 0x10474 from the relaunched tile 1; PDONE2 = 0x10478 from the relaunched top tile. PDONE2 IS A SEPARATE WORD RATHER THAN A PER-HART ARRAY ON PURPOSE, because tile 1's done payload spins verifying that its own magic survives, so a second tile writing the same word would fail the first tile rather than prove anything.
# Tiles that are never launched stay parked in the ROM for the whole test, and the nibble walk proves they also stay ON.

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
