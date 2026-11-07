# See LICENSE for license details.

# VestaRV scar: jalr did not clear bit 0 of its target
# The odd PC survives the jump, so auipc at the target shows it. Checks both operands that can set the bit, and the link.

#include "riscv_test.h"
#include "test_macros.h"
#include "scar.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   t4, 1
    la   a4, jt1
    addi a4, a4, 1                  # odd base
    jalr a5, 0(a4)
ret1:
    j    scar_fail
    .align 2
jt1:
    auipc a6, 0
    andi a7, a6, 3
    bnez a7, scar_fail

    li   t4, 2
    la   a6, ret1                   # the link is the return address, not the target
    bne  a5, a6, scar_fail

    li   t4, 3
    la   a4, jt2
    jalr a5, 1(a4)                  # odd immediate
    j    scar_fail
    .align 2
jt2:
    auipc a6, 0
    andi a7, a6, 3
    bnez a7, scar_fail

    RVTEST_PASS

scar_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF, t4 = failing check

    # RVTEST_CODE_END is unimp, which traps: never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
