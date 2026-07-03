# See LICENSE for license details.

#*****************************************************************************
# shcount.S  (M4c)
#-----------------------------------------------------------------------------
# Multi-hart ATOMIC COUNTER test — the end-to-end cross-hart LR/SC proof.
#
# The three preloaded harts (shmem_mp phase 2) each commit exactly 64 LR/SC
# increments to the shared counter at 0x10080, concurrently, from t=0. This
# test (hart 0, via SPI boot) commits its own 64 increments under the other
# harts' live hammer traffic, then requires the counter to equal EXACTLY
# 4*64 = 256:
#   * any LOST update (broken cross-hart atomicity) -> counter < 256 forever
#     -> the spin below never exits -> testbench watchdog FAIL
#   * any DOUBLE commit -> counter > 256 -> explicit FAIL
# A hart whose SC fails 64 times consecutively declares livelock -> FAIL
# (the serializing round-robin arbiter guarantees forward progress).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   s7, 0x10080            # common atomic counter (word 32 of the window)
    li   s8, 64                 # increments to commit
    li   s9, 64                 # consecutive-failure budget (livelock detector)

count_loop:
    lr.w t3, (s7)
    addi t3, t3, 1
    sc.w t4, t3, (s7)
    beqz t4, count_ok           # committed
    addi s9, s9, -1
    beqz s9, shcount_fail
    li   t3, 4                  # backoff (symmetry breaker; see shmem_mp.S —
1:  addi t3, t3, -1             # hart 0 arrives ms late, so contention with
    bnez t3, 1b                 # the preloaded harts' hammer only)
    j    count_loop
count_ok:
    li   s9, 64
    addi s8, s8, -1
    bnez s8, count_loop

    # ---- all four harts contributed: counter must reach EXACTLY 256 ----
    li   t5, 256
wait_full:
    lw   t3, 0(s7)
    blt  t3, t5, wait_full      # lost update -> spins forever -> watchdog
    bne  t3, t5, shcount_fail   # overshoot -> double commit

    RVTEST_PASS                 # a0 = 0xCAFEBABE

shcount_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
