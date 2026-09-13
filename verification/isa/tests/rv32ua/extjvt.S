# See LICENSE for license details.

# VestaRV: Zcmt jvt CSR access probe
# With CORE_ENABLE_ZCMT defined, jvt (0x017) is a known URW CSR: the test writes a 64-byte-aligned base and reads it back, with the mode field WARL-pinned to 0. Without it, jvt is an unknown CSR in the csr_valid map, so the csrrw MUST take the illegal-instruction trap and reaching past it is a FAIL. That arm is wired ONLY into run_extoff.sh.
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
    bne  t2, t3, ejv_fail
    .option push
    .option arch, +zicsr
#ifdef CORE_ENABLE_ZCMT
    li   t0, 0x00010040          # some 64B-aligned base (low 6 bits 0)
    csrw 0x017, t0
    csrr t1, 0x017
    .option pop
    bne  t1, t0, ejv_fail        # base preserved, mode 0
    RVTEST_PASS
#else
    li   t0, 0x00010040
    csrw 0x017, t0               # jvt access — illegal without Zcmt, MUST trap
    .option pop
    j    ejv_fail
#endif
ejv_fail:
    RVTEST_FAIL
    RVTEST_CODE_END
  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
