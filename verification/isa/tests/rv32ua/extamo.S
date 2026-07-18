# See LICENSE for license details.

#*****************************************************************************
# extamo.S  (core-features work, 2026-07-08)
#-----------------------------------------------------------------------------
# A-extension adaptive probe — see extprobe.S for the group contract.
# Dispatches on misa.A (bit 0 <- ENABLE_ATOMICS):
#   * A advertised  -> AMOADD.W and an LR/SC pair on a private-TCM word must
#                      work (single hart, no contention) -> PASS
#   * A absent      -> the AMOADD.W below must take the illegal-instruction
#                      trap (whole AMO_OPCODE drops out of valid_opcode).
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
    andi t1, t0, 1
    beqz t1, extamo_expect_trap

    # A advertised: AMO + LR/SC must work
    la   t4, extamo_scratch
    li   t5, 100
    sw   t5, 0(t4)
    li   t6, 5
    amoadd.w t2, t6, (t4)       # returns old (100), memory becomes 105
    li   t3, 100
    bne  t2, t3, extamo_fail
    lw   t2, 0(t4)
    li   t3, 105
    bne  t2, t3, extamo_fail

    lr.w t2, (t4)               # 105
    addi t2, t2, 1
    sc.w t3, t2, (t4)           # uncontended same-address SC must succeed
    bnez t3, extamo_fail
    lw   t2, 0(t4)
    li   t3, 106
    bne  t2, t3, extamo_fail

    RVTEST_PASS

extamo_expect_trap:
    # A not advertised: this AMOADD.W must trap. Surviving it = misa/decode disagree.
    la   t4, extamo_scratch
    li   t6, 5
    amoadd.w t2, t6, (t4)
    j    extamo_fail

extamo_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .align 2
extamo_scratch: .word 0
RVTEST_DATA_END
