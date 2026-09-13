# See LICENSE for license details.

# VestaRV: shared-RAM window contention test
# Hart-generic hammer on the shared window at 0x10000, region 4, behind mp_arbiter on the free-running mclk. Hart 0 stages this TCM image once, launches every tile into tile_body through the boot ROM loader (mp_boot.h), then runs the same body itself.
# THE READY BARRIER IS LOAD-BEARING, not scaffolding: every hart advertises READY[hartid] and none leaves until all NHARTS have. Without it the tiles are still copying their image (about 32768 cycles for 4096 words) while hart 0 finishes in about a thousand of its own, so every phase runs on hart 0 alone and the test passes with no contention at all. The barrier makes the contention real AND makes a missing tile fatal, since it is a bounded wait on a word only that tile writes.
# The 4096-word launch volume is deliberate: shcount launches the same image concurrently at N=4 and N=18 and passes, so the size is proven at both hart counts.
# Each hart hammers its OWN word at 0x10090 + 4*hartid, disjoint per hart, because shared-word atomicity needs the resv_unit and byte lanes. The base must stay clear of the phase-2 atomic counter at 0x10080, which the historical 0x10040 base collided with at N=18; the N=18 span is 0x10090..0x100D4, inside the bootrom-zeroed 0x10000-0x107FF range.
# Phase 1 is a verified write/readback sweep on the hart's own word, phase 2 is 64 LR/SC increments on the common counter under live contention, and phase 3 sets a0 = PASS and then hammers forever, so every hart contends with NHARTS-1 live masters for the rest of the run. The tb latches pass and fail independently, so a mismatch after PASS still fails the run.

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

# T1 FIX — the READY barrier's mailbox. NHARTS words placed by the ledger rule
# "a control word that follows a per-hart array goes at base + 4*NHARTS", the
# array here being the disjoint hammer words at 0x10090. N=4: 0x100A0-0x100AC.
# N=18: 0x100D8-0x1011C, which ends just below shboot's DONE[0] at 0x10120, so
# the band is collision-free at BOTH hart counts. Below the loader rows
# (0x10500) and inside the bootrom-zeroed range (< 0x10800), so the array reads
# 0 at entry with no explicit init.
#define SHMEM_MP_READY   (0x10090 + 4*NHARTS)
#define SHMEM_MP_RMAGIC  0x4EAD0000     # READY[h] = SHMEM_MP_RMAGIC + h

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr t0, mhartid            # 0..3
    .option pop
    bnez t0, tile_body          # M12: only hart 0 launches; tiles enter tile_body

    # hart 0: stage this TCM image once, launch all three tiles into the SAME
    # hammer body, then fall through and run it too (live 4-way contention).
    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_ALL(tile_body, 4096)

tile_body:                      # entry ABI: only sp defined — re-derive mhartid
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..NHARTS-1. Held in a CALLEE-SAVED register
    .option pop                 # for the whole body: the barrier below and
                                # phase 2's backoff both read it. (It used to
                                # live in t0 and be copied to s10 in phase 2
                                # with the comment "still live from the csrr
                                # above" — a correctness claim resting on
                                # nothing but distance.)
    li   sp, 0xBFF0             # test convention (bootrom left 0xBFFC)
    slli t1, s10, 2             # hartid * 4
    li   t2, 0x10090            # Argus A3: rebased from 0x10040 (see header)
    add  s2, t2, t1             # s2 = my disjoint shared word

    # per-hart pattern seed (hartid in the top byte -> cross-hart corruption
    # is visible as a wrong top byte, not just a wrong count)
    slli s3, s10, 24
    li   t2, 0x00C0FFEE
    xor  s3, s3, t2             # s3 = pattern base

    # ---- T1 FIX: READY barrier — no hart runs phase 1 alone ----------------
    # Every hart (hart 0 included) publishes READY[hartid], then spins until
    # ALL NHARTS words carry their magic. Hart 0 reaches here a few hundred
    # cycles after its last launch msip; each tile reaches it only after the
    # bootrom loader has copied the whole image into its TCM, so the barrier
    # is exactly the wait that M12 removed and nobody put back.
    #
    # This is also the falsifiability gate: it is a BOUNDED wait on words that
    # only the tiles write, so a tile that never arrives now produces
    # a0=0xDEADBEEF instead of a green run with three parked harts. Bound
    # 100,000 follows shwfi's post-launch ready_wait, which is the same wait
    # for the same copy and is documented as fitting the tb 100 ms watchdog;
    # here it is one barrier rather than NHARTS-1 serialized waits, so it is
    # strictly the more conservative use of that precedent.
    li   t1, SHMEM_MP_READY
    slli t2, s10, 2
    add  t2, t1, t2             # &READY[hartid]
    li   t3, SHMEM_MP_RMAGIC
    add  t3, t3, s10
    sw   t3, 0(t2)              # READY[hartid] = magic + hartid
    li   t5, 100000             # bounded-retry budget (see above)
barrier_retry:
    li   t1, SHMEM_MP_READY     # rescan from hart 0 every pass
    li   t2, 0                  # h
    li   t6, SHMEM_MP_RMAGIC
barrier_scan:
    lw   t3, 0(t1)              # READY[h]
    add  t4, t6, t2             # expected magic for hart h
    bne  t3, t4, barrier_again
    addi t1, t1, 4
    addi t2, t2, 1
    li   t4, NHARTS
    bltu t2, t4, barrier_scan
    j    barrier_done           # all NHARTS harts are in tile_body
barrier_again:
    addi t5, t5, -1
    beqz t5, shmem_mp_fail      # a tile never arrived — the T1 shape, now FATAL
    j    barrier_retry
barrier_done:

    # ---- phase 1: verified sweep (16 write/readback/compare iterations) ----
    li   s5, 16
    li   s6, 0                  # iteration counter (runs on into phase 2)
sweep_loop:
    add  t3, s3, s6             # pattern for this iteration
    sw   t3, 0(s2)              # shared store  -> arbiter txn (stall/grant/done)
    lw   t4, 0(s2)              # shared load   -> arbiter txn
    bne  t3, t4, shmem_mp_fail
    addi s6, s6, 1
    bne  s6, s5, sweep_loop

    # ---- phase 2 (M4c): 64 LR/SC increments on the COMMON counter word ----
    # All NHARTS harts run this concurrently — the READY barrier above is what
    # makes that true, so this IS real same-word LR/SC contention through
    # resv_unit in every regression run. (Before the T1 fix the sentence here
    # read "all preloaded harts run this concurrently from t=0", which had been
    # false since M12 retired the preload.) The counter at 0x10080 therefore
    # reaches NHARTS*64. This test does not check that total and deliberately
    # does not duplicate it: shcount owns the exact-count check on this very
    # word (`li t5, NHARTS*64` + undershoot/overshoot legs). What shmem_mp
    # gates on is that all NHARTS harts are LIVE and contending, which is the
    # barrier's job.
    #
    # LIVELOCK (found the hard way): three IDENTICAL harts released together
    # and served by a fair round-robin arbiter livelock on a naked LR/SC retry
    # loop — the schedule is perfectly periodic, so the same losers lose every
    # round (the RISC-V forward-progress guarantee assumes de-synchronizing
    # factors). The hartid-scaled BACKOFF after a failed SC breaks the
    # symmetry; 64 consecutive failures WITH backoff -> RVTEST_FAIL.
    .option push
    .option arch, +a
    li   s7, 0x10080            # common atomic counter (s10 = hartid, set at
                                # tile_body entry, drives the backoff below)
    li   s8, 64                 # increments to commit
    li   s9, 64                 # consecutive-failure budget
count_loop:
    lr.w t3, (s7)
    addi t3, t3, 1
    sc.w t4, t3, (s7)
    beqz t4, count_ok           # committed
    addi s9, s9, -1             # SC failed: spend livelock budget
    beqz s9, shmem_mp_fail
    slli t3, s10, 3             # backoff = hartid*8 + 8 spins
    addi t3, t3, 8
1:  addi t3, t3, -1
    bnez t3, 1b
    j    count_loop
count_ok:
    li   s9, 64                 # reset budget
    addi s8, s8, -1
    bnez s8, count_loop
    .option pop

    # ---- phase 3: declare PASS, then hammer forever under contention ----
    # (same a0 write as RVTEST_PASS, but WITHOUT the terminal spin loop)
    li   a0, 0xCAFEBABE
hammer_loop:
    add  t3, s3, s6
    sw   t3, 0(s2)
    lw   t4, 0(s2)
    bne  t3, t4, shmem_mp_fail
    lw   t4, 0(s2)              # re-read: value must survive other harts' traffic
    bne  t3, t4, shmem_mp_fail
    addi s6, s6, 1              # wraps eventually — patterns just repeat, harmless
    j    hammer_loop

shmem_mp_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through to it; phase 2 loops forever and fail spins above.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
