# See LICENSE for license details.

#*****************************************************************************
# shmem_mp.S  (M3c.4)
#-----------------------------------------------------------------------------
# HART-GENERIC contention test for the MCU_MP shared-RAM window at 0x10000
# (region 4, behind mp_arbiter on the free-running mclk).
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

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr t0, mhartid            # 0..3
    .option pop
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

    # ---- phase 2: declare PASS, then hammer forever under contention ----
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
