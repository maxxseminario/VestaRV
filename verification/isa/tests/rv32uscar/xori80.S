# See LICENSE for license details.

# VestaRV scar: xori with immediate 0x80 executed as zext.h
# Myshkin decoded that one immediate as the bitmanip encoding. 0x81 is the control. GCC emits it for x^0x80.

#include "riscv_test.h"
#include "test_macros.h"
#include "scar.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   t4, 1
    li   a1, 0xFFF7FFFF
    xori a2, a1, 0x81
    li   a3, 0xFFF7FF7E
    bne  a2, a3, scar_fail

    li   t4, 2
    xori a2, a1, 0x80
    li   a3, 0xFFF7FF7F
    bne  a2, a3, scar_fail

    li   t4, 3
    li   a1, 0x12345678
    xori a2, a1, 0x80
    li   a3, 0x123456F8
    bne  a2, a3, scar_fail

    RVTEST_PASS

scar_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF, t4 = failing check

    # RVTEST_CODE_END is unimp, which traps: never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
