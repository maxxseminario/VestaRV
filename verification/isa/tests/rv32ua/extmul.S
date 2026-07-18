# See LICENSE for license details.

#*****************************************************************************
# extmul.S  (core-features work, 2026-07-08)
#-----------------------------------------------------------------------------
# M-extension (multiply half) adaptive probe — see extprobe.S for the group
# contract. Whole-file norvc/norelax base-ISA skeleton; dispatches on misa.M
# (bit 12, advertised only when BOTH ENABLE_MUL and ENABLE_DIV are true):
#   * M advertised  -> MUL/MULH must produce correct results -> PASS
#   * M absent      -> the MUL below must take the illegal-instruction trap
#                      (stripped-build harness watches trap_flag); executing
#                      PAST it is an explicit FAIL — misa lied.
# LIMITATION: with a split config (ENABLE_MUL /= ENABLE_DIV) misa.M is 0 but
# mul still executes -> this test reports FAIL. Split-M configs need their
# own CORE_ENABLE_*-aware build (not part of the all-on/all-off controls).
#*****************************************************************************

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
