# See LICENSE for license details.
#*****************************************************************************
# extjvt.S   (X3 Zcmt ext-probe — jvt CSR access)
#   ON  (#ifdef CORE_ENABLE_ZCMT): jvt (0x017) is a known URW CSR: write a
#       64B-aligned base, read it back (mode WARL-pinned 0) -> PASS.
#   OFF (#else, extoff POISON): jvt is an unknown CSR (csr_valid map) so the
#       csrrw MUST take the illegal-instruction trap. Reached-past -> FAIL.
#       Wired ONLY into run_extoff.sh.
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
