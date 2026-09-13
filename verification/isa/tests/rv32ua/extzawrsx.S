# See LICENSE for license details.

# VestaRV: Zawrs off-polarity poison
# It unconditionally executes the wrs encoding, which MUST take the illegal-instruction trap when ENABLE_ZAWRS is off, since those funct12 values are illegal SYSTEM encodings without it. Surviving past the encoding means decode and gating disagree and is an explicit FAIL.
# It is used ONLY by the stripped negative-control harness (behavioral_mp_stripped/run_extoff.sh with trap_watch.tcl) and by a targeted trap-watch run on the default build, never in the main suite, because it deliberately traps into this core's terminal TRAP_STATE.

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # base-ISA sanity: prove the core runs before the illegal encoding
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, extzx_fail

    # wrs.nto (SYSTEM funct12=0x00D) MUST trap illegal when Zawrs is off
    .word 0x00d00073
    j    extzx_fail                 # reached only if it did NOT trap -> FAIL

extzx_fail:
    RVTEST_FAIL

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
