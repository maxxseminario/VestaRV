# See LICENSE for license details.

# VestaRV scar: c.lui x0, nzimm stopped the core
# That encoding is a HINT and must retire with no effect. Myshkin treated it as reserved and stopped.
# c.lui x0, 0 stays reserved, which is the control where the trap CSRs can report it.

#include "riscv_test.h"
#include "test_macros.h"
#include "scar.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

#ifdef CORE_ENABLE_TRAPCSR
    .option push
    .option arch, +zicsr
    SCAR_TRAPS_ON(scar_trap)
    li   s6, 2
#endif

    li   t4, 1
    li   a1, 0x55
    .2byte 0x6005                   # c.lui x0, 1
    .2byte 0x0001                   # c.nop
    li   a2, 0x55
    bne  a1, a2, scar_fail

#ifdef CORE_ENABLE_TRAPCSR
    li   t4, 2                      # the HINT took no trap
    bnez s3, scar_fail

    li   t4, 3
    .2byte 0x6001                   # c.lui x0, 0: reserved
    .2byte 0x0001
    li   t3, 1
    bne  s3, t3, scar_fail
    li   t3, 2                      # illegal instruction
    bne  s4, t3, scar_fail

    SCAR_TRAPS_OFF
#endif
    RVTEST_PASS

#ifdef CORE_ENABLE_TRAPCSR
    SCAR_HANDLER(scar_trap)
    .option pop
#endif

scar_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF, t4 = failing check

    # RVTEST_CODE_END is unimp, which traps: never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
