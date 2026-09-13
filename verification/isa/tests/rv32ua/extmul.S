# See LICENSE for license details.

# VestaRV: M-extension adaptive probe, multiply half
# Whole-file norvc and norelax base-ISA skeleton, dispatching on misa.M, bit 12, which is advertised only when BOTH ENABLE_MUL and ENABLE_DIV are true. With M advertised, MUL and MULH must produce correct results; with M absent, the MUL must take the illegal-instruction trap, and executing past it is an explicit FAIL, because misa lied.
# LIMITATION: with a split configuration where ENABLE_MUL and ENABLE_DIV differ, misa.M reads 0 while mul still executes, so this test reports FAIL. A split-M configuration needs its own CORE_ENABLE_-aware build. See extprobe.S for the group contract.

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr t0, misa
    .option pop
    srli t1, t0, 12
    andi t1, t1, 1
    beqz t1, extmul_expect_trap

    # M advertised: multiply must work
    li   t0, 7
    li   t1, 11
    mul  t2, t0, t1
    li   t3, 77
    bne  t2, t3, extmul_fail
    li   t0, 0x40000000
    li   t1, 4
    mulh t2, t0, t1             # (2^30 * 4) >> 32 = 1
    li   t3, 1
    bne  t2, t3, extmul_fail

    RVTEST_PASS

extmul_expect_trap:
    # M not advertised: this MUL must trap. Surviving it = misa/decode disagree.
    li   t0, 7
    li   t1, 11
    mul  t2, t0, t1
    j    extmul_fail

extmul_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
