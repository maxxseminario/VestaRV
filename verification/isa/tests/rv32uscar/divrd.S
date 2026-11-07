# See LICENSE for license details.

# VestaRV scar: div, divu, rem and remu failed when rd equalled a source
# The EXECUTE cycle wrote rd before the divider latched its operands, so the operand it then read was already gone.
# A distinct rd is the control. The by-zero cases also read their operands after the run, so they are aliased here too.

#include "riscv_test.h"
#include "test_macros.h"
#include "scar.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

#define CHK(id, reg, val)   \
    li   t4, id;            \
    li   t3, val;           \
    bne  reg, t3, scar_fail

    li   a1, 100
    li   a2, 7
    div  a3, a1, a2
    CHK(1, a3, 14)

    div  a1, a1, a2                 # rd = rs1
    CHK(2, a1, 14)
    li   a1, 100
    div  a2, a1, a2                 # rd = rs2
    CHK(3, a2, 14)

    li   a2, 7
    rem  a1, a1, a2
    CHK(4, a1, 2)
    li   a1, 100
    rem  a2, a1, a2
    CHK(5, a2, 2)

    li   a2, 7
    divu a1, a1, a2
    CHK(6, a1, 14)
    li   a1, 100
    divu a2, a1, a2
    CHK(7, a2, 14)

    li   a2, 7
    remu a1, a1, a2
    CHK(8, a1, 2)
    li   a1, 100
    remu a2, a1, a2
    CHK(9, a2, 2)

    li   a1, 100
    div  a1, a1, zero               # by zero: all ones
    CHK(10, a1, -1)
    li   a1, 100
    rem  a1, a1, zero               # by zero: the dividend
    CHK(11, a1, 100)

    RVTEST_PASS

scar_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF, t4 = failing check

    # RVTEST_CODE_END is unimp, which traps: never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
