# See LICENSE for license details.

# VestaRV: M-extension adaptive probe, divide half
# Exercises the ITERATIVE DIVIDER, which is its own hardware unit and is generated away entirely when ENABLE_DIV is false. With M advertised, DIV and REM must produce correct results; with M absent, the DIV must take the illegal-instruction trap. See extprobe.S for the group contract and extmul.S for the misa.M dispatch and its split-configuration limitation.

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr t0, misa
    .option pop
    srli t1, t0, 12
    andi t1, t1, 1
    beqz t1, extdiv_expect_trap

    # M advertised: divide/remainder must work (multi-cycle DIV_WAIT path)
    li   t0, 77
    li   t1, 11
    div  t2, t0, t1
    li   t3, 7
    bne  t2, t3, extdiv_fail
    li   t0, 78
    rem  t2, t0, t1             # 78 % 11 = 1
    li   t3, 1
    bne  t2, t3, extdiv_fail

    RVTEST_PASS

extdiv_expect_trap:
    # M not advertised: this DIV must trap. Surviving it = misa/decode disagree.
    li   t0, 77
    li   t1, 11
    div  t2, t0, t1
    j    extdiv_fail

extdiv_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
