# See LICENSE for license details.

#*****************************************************************************
# extzawrsx.S   (X1 Zawrs OFF-polarity poison)
#-----------------------------------------------------------------------------
# The Zawrs OFF control. Unconditionally executes the wrs encoding, which MUST
# take the illegal-instruction trap when ENABLE_ZAWRS is off (these funct12
# values are illegal SYSTEM encodings today). Used ONLY by the negative-control
# / stripped harness (behavioral_mp_stripped/run_extoff.sh + trap_watch.tcl,
# where trap_flag => TRAP_OK) and by a targeted trap-watch run on the default
# build — NOT in the main behavioral_mp suite (it deliberately traps into this
# core's terminal TRAP_STATE). Surviving PAST the encoding => decode/gating
# disagree => explicit FAIL.
#*****************************************************************************

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
