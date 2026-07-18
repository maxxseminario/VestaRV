# See LICENSE for license details.
#*****************************************************************************
# extzcmt.S   (X3 Zcmt ext-probe — cm.jt encoding)
#   ON  (#ifdef CORE_ENABLE_ZCMT): build a jvt, csrw jvt, fence.i, cm.jt to a
#       target and confirm control reached it -> PASS.
#   OFF (#else, extoff POISON): the cm.jt encoding executed unconditionally MUST
#       take the illegal-instruction trap (C2 funct3=101 reserved without Zcmt).
#       Reached-past -> FAIL. Wired ONLY into run_extoff.sh. (The jvt-CSR-access
#       trap has its own poison, extjvt.S.)
#*****************************************************************************
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
    bne  t2, t3, ezt_fail
#ifdef CORE_ENABLE_ZCMT
    la   t0, ezt_jvt
    la   t1, ezt_target
    sw   t1, 20(t0)             # entry[5]
    .option push
    .option arch, +zicsr
    csrw 0x017, t0
    .option pop
    .option push
    .option arch, +zifencei
    fence.i
    .option pop
    li   ra, 0x55AA55AA
    .short 0xA016               # cm.jt 5 -> ezt_target (index 5 = bits9:2=0000101)
    j    ezt_fail
ezt_target:
    li   t2, 0x55AA55AA
    bne  ra, t2, ezt_fail        # cm.jt does not link
    RVTEST_PASS
#else
    .short 0xA016               # cm.jt — illegal without Zcmt, MUST trap
    j    ezt_fail
#endif
ezt_fail:
    RVTEST_FAIL
    RVTEST_CODE_END
  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .align 6
ezt_jvt: .fill 32, 4, 0
RVTEST_DATA_END
