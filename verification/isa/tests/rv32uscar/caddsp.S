# See LICENSE for license details.

# VestaRV scar: compressed stack adjustments and calls were wrong
# A negative c.addi16sp left its low four bits set, and c.jal and c.jalr linked pc+4 instead of pc+2.
# A positive c.addi16sp is the control. The calls run at both halfword alignments.

#include "riscv_test.h"
#include "test_macros.h"
#include "scar.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

// A compressed call at this alignment must link pc + 2.
#define CALL_CHECK(id, at, tgt, ...)    \
    li   t4, id;                        \
    la   t0, tgt;                       \
    .option push;                       \
    .option rvc;                        \
at: __VA_ARGS__;                        \
    c.nop;                              \
    c.nop;                              \
    .option pop;                        \
    .align 2;                           \
tgt:                                    \
    la   t1, at;                        \
    sub  t1, ra, t1;                    \
    li   t2, 2;                         \
    bne  t1, t2, scar_fail

    li   t4, 1
    li   sp, 0x9200
    .option push
    .option rvc
    c.addi16sp sp, 32
    .option pop
    li   t3, 0x9220
    bne  sp, t3, scar_fail

    li   t4, 2
    li   sp, 0x9200
    .option push
    .option rvc
    c.addi16sp sp, -32
    .option pop
    li   t3, 0x91E0
    bne  sp, t3, scar_fail

    li   t4, 3
    li   sp, 0x9200
    .option push
    .option rvc
    c.addi16sp sp, -496
    .option pop
    li   t3, 0x9010
    bne  sp, t3, scar_fail

    .align 2
    CALL_CHECK(4, at_jalr0, tg_jalr0, c.jalr t0)
    .align 2
    CALL_CHECK(5, at_jal0, tg_jal0, c.jal tg_jal0)

    .align 2
    .2byte 0x0001                   # c.nop: the next call sits on a halfword
    CALL_CHECK(6, at_jalr2, tg_jalr2, c.jalr t0)
    .align 2
    .2byte 0x0001
    CALL_CHECK(7, at_jal2, tg_jal2, c.jal tg_jal2)

    RVTEST_PASS

scar_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF, t4 = failing check

    # RVTEST_CODE_END is unimp, which traps: never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
