# See LICENSE for license details.

# VestaRV: Zcmp extension probe
# With CORE_ENABLE_ZCMP defined the test runs a real cm.push and cm.pop round trip. Without it the cm.push encoding executes unconditionally and MUST take the illegal-instruction trap, since C2 funct3 = 101 is reserved without Zcmp, and reaching past it is a FAIL; that arm is wired ONLY into run_extoff.sh.
# gas has no cm.* mnemonics, so the encodings are raw 16-bit `.short` byte images.
#include "riscv_test.h"
#include "test_macros.h"
.option norvc
.option norelax
RVTEST_RV32U
RVTEST_CODE_BEGIN
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, ezp_fail
#ifdef CORE_ENABLE_ZCMP
    la   sp, ezp_stack_hi
    mv   s11, sp
    li   ra, 0x1234ABCD
    li   s0, 0x0F0F0F0F
    .short 0xB852               # cm.push {ra,s0}, -16
    addi t0, s11, -16
    bne  sp, t0, ezp_fail
    li   ra, 0
    li   s0, 0
    .short 0xBA52               # cm.pop {ra,s0}, 16
    bne  sp, s11, ezp_fail
    li   t2, 0x1234ABCD; bne ra, t2, ezp_fail
    li   t2, 0x0F0F0F0F; bne s0, t2, ezp_fail
    RVTEST_PASS
#else
    la   sp, ezp_stack_hi
    .short 0xB852               # cm.push — illegal without Zcmp, MUST trap
    j    ezp_fail
#endif
ezp_fail:
    RVTEST_FAIL
    RVTEST_CODE_END
  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .align 4
ezp_stack_lo: .fill 16, 4, 0
ezp_stack_hi: .word 0
RVTEST_DATA_END
