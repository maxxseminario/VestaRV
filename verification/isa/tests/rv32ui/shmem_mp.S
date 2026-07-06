# See LICENSE for license details.

#*****************************************************************************
# shmem_mp.S  (M3c.4; M12 single-ROM boot rework)
#-----------------------------------------------------------------------------
# HART-GENERIC contention test for the MCU_MP shared-RAM window at 0x10000
# (region 4, behind mp_arbiter on the free-running mclk).
#
# M12: this WAS the default tile-preload image (harts 1-3 hammered from t=0).
# Nothing preloads the tiles now, so hart 0 stages this TCM image once and
# launches all three tiles into tile_body through the bootrom loader
# (mp_boot.h); each tile then runs the SAME hammer body it always did, and
# hart 0 falls through to run it too. The "tiles hammer FOREVER after passing"
# property is preserved — hart 0 always contends with three live masters.
#
# Each hart reads mhartid and hammers its OWN word at 0x10040 + 4*hartid —
# DISJOINT per hart (shared-word atomicity needs the M4 resv_unit/byte lanes),
# and clear of shmem.S's words at 0x10000/0x10004 so it can run on harts 1-3
# concurrently with hart 0's shmem regression test.
#
# Phase 1: a fully-verified write/readback sweep -> set a0 = 0xCAFEBABE (PASS).
# Phase 2: keep hammering FOREVER (write, read back twice, compare) so hart 0
# always contends with three live arbiter masters for the whole regression run.
# The tb latches pass AND fail independently, so a post-PASS mismatch (lost
# arbitration grant, cross-master data corruption) still fails the run via
# RVTEST_FAIL (a0 = 0xDEADBEEF).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

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
    MP_LAUNCH_HART(1, tile_body, 4096)
    MP_LAUNCH_HART(2, tile_body, 4096)
    MP_LAUNCH_HART(3, tile_body, 4096)

tile_body:                      # entry ABI: only sp defined — re-derive mhartid
    .option push
    .option arch, +zicsr
    csrr t0, mhartid            # 0..3
    .option pop
    li   sp, 0xBFF0             # test convention (bootrom left 0xBFFC)
    slli t1, t0, 2              # hartid * 4
    li   t2, 0x10040
    add  s2, t2, t1             # s2 = my disjoint shared word

    # per-hart pattern seed (hartid in the top byte -> cross-hart corruption
    # is visible as a wrong top byte, not just a wrong count)
    slli s3, t0, 24
    li   t2, 0x00C0FFEE
    xor  s3, s3, t2             # s3 = pattern base

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
    # All preloaded harts run this concurrently from t=0 -> real same-word
    # LR/SC contention through resv_unit in EVERY regression run. The counter
    # (0x10080) deterministically reaches 64*3=192 (+64 when hart 0 runs
    # shcount, which then checks ==256).
    #
    # LIVELOCK (found the hard way): three IDENTICAL harts released together
    # and served by a fair round-robin arbiter livelock on a naked LR/SC retry
    # loop — the schedule is perfectly periodic, so the same losers lose every
    # round (the RISC-V forward-progress guarantee assumes de-synchronizing
    # factors). The hartid-scaled BACKOFF after a failed SC breaks the
    # symmetry; 64 consecutive failures WITH backoff -> RVTEST_FAIL.
    .option push
    .option arch, +a
    mv   s10, t0                # hartid (still live from the csrr above)
    li   s7, 0x10080            # common atomic counter
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
