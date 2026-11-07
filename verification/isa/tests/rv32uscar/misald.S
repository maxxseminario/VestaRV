# See LICENSE for license details.

# VestaRV scar: misaligned loads and stores used the aligned location
# Each access must trap once, with cause 4 or 6, mepc on the access and mtval the address, leaving rd and memory alone.
# Aligned and byte accesses are the controls.
# ON-ONLY: without the trap CSRs the cause cannot be reported. An OFF build fails with t4 = 0.

#include "riscv_test.h"
#include "test_macros.h"
#include "scar.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

// One misaligned access: it traps once, with this cause, at this pc, reporting this address.
#define MA_TRAP(id, cause, addr_reg, ...)   \
    li   t4, id;                            \
    la   s0, 9f;                            \
    addi s8, s8, 1;                         \
9:  __VA_ARGS__;                            \
    bne  s3, s8, scar_fail;                 \
    li   t3, cause;                         \
    bne  s4, t3, scar_fail;                 \
    bne  s5, s0, scar_fail;                 \
    bne  s7, addr_reg, scar_fail

#ifdef CORE_ENABLE_TRAPCSR
    .option push
    .option arch, +zicsr
    SCAR_TRAPS_ON(scar_trap)
    li   s8, 0                      # traps expected

    la   s1, scar_data
    li   t4, 1
    lw   a2, 0(s1)
    li   a3, 0x11223344
    bne  a2, a3, scar_fail
    lbu  a2, 1(s1)
    li   a3, 0x33
    bne  a2, a3, scar_fail
    lhu  a2, 2(s1)
    li   a3, 0x1122
    bne  a2, a3, scar_fail
    bne  s3, s8, scar_fail

    li   a2, 0x0BADF00D             # a trapped load must leave rd alone
    addi s2, s1, 1
    MA_TRAP(2, 4, s2, lw a2, 1(s1))
    addi s2, s1, 2
    MA_TRAP(3, 4, s2, lw a2, 2(s1))
    addi s2, s1, 3
    MA_TRAP(4, 4, s2, lw a2, 3(s1))
    addi s2, s1, 1
    MA_TRAP(5, 4, s2, lh a2, 1(s1))
    addi s2, s1, 3
    MA_TRAP(6, 4, s2, lhu a2, 3(s1))
    li   t4, 7
    li   a3, 0x0BADF00D
    bne  a2, a3, scar_fail

    li   a3, 0xAABBCCDD
    addi s1, s1, 8                  # the zeroed words
    addi s2, s1, 1
    MA_TRAP(8, 6, s2, sw a3, 1(s1))
    addi s2, s1, 2
    MA_TRAP(9, 6, s2, sw a3, 2(s1))
    addi s2, s1, 3
    MA_TRAP(10, 6, s2, sw a3, 3(s1))
    addi s2, s1, 1
    MA_TRAP(11, 6, s2, sh a3, 1(s1))
    addi s2, s1, 3
    MA_TRAP(12, 6, s2, sh a3, 3(s1))
    li   t4, 13                     # a trapped store writes nothing
    lw   a2, 0(s1)
    bnez a2, scar_fail
    li   t4, 14
    lw   a2, 4(s1)
    bnez a2, scar_fail

    addi s2, s1, 2
    MA_TRAP(15, 4, s2, lr.w a2, (s2))
    MA_TRAP(16, 6, s2, sc.w a2, a3, (s2))
    MA_TRAP(17, 6, s2, amoadd.w a2, a3, (s2))
    li   t4, 18
    lw   a2, 0(s1)
    bnez a2, scar_fail

    SCAR_TRAPS_OFF
    RVTEST_PASS

    SCAR_HANDLER(scar_trap)
    .option pop
#else
    li   t4, 0
    j    scar_fail
#endif

scar_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF, t4 = failing check

    # RVTEST_CODE_END is unimp, which traps: never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
    .align 3
scar_data:
    .word 0x11223344
    .word 0x55667788
    .word 0
    .word 0
  TEST_DATA
RVTEST_DATA_END
