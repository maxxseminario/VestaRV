# See LICENSE for license details.

#*****************************************************************************
# zffms.S   (X4 Zfinx OFF-polarity poison)
#-----------------------------------------------------------------------------
# Unconditionally executes fmsub.s a0,a1,a2,a3 (FMSUB opcode 0x47), which MUST take the illegal-instruction trap
# when ENABLE_ZFINX is off. Zfinx sets NO misa bit and every FP encoding is
# illegal on the base core today, so this is a negative control for the X4
# gating: the encoding is emitted as a raw .word so it is PRESENT regardless of
# -march, and run ONLY under the trap-watching harness (behavioral_mp_stripped/
# run_extoff.sh + trap_watch.tcl, where trap_flag => TRAP_OK) -- NOT in the main
# behavioral_mp suite (it deliberately dead-ends in this core's TRAP_STATE).
# One of the four fused-multiply-add major opcodes.
# Surviving PAST the encoding => decode/gating disagree => explicit FAIL.
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
    bne  t2, t3, zffms_fail

    .word 0x68c5f547   # fmsub.s a0,a1,a2,a3 (FMSUB opcode 0x47) -- MUST trap illegal when Zfinx off
    j    zffms_fail                # reached only if it did NOT trap -> FAIL

zffms_fail:
    RVTEST_FAIL

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
