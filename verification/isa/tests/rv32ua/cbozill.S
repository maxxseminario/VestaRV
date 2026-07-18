# See LICENSE for license details.

#*****************************************************************************
# cbozill.S   (X3 Zicboz — cbo.clean/flush/inval are ALWAYS illegal)
#-----------------------------------------------------------------------------
# The cbo.clean (imm=0x001), cbo.flush (0x002) and cbo.inval (0x000) cache-block
# management encodings share cbo.zero's opcode/funct3 (MISC-MEM, funct3=010) but
# are UNSUPPORTED on this core (gate decision D4) — illegal on EVERY build,
# Zicboz ON or OFF. This is a pure POISON: the cbo.clean encoding MUST take the
# illegal-instruction trap. Run through the trap_watch harness (the a0-watch
# runner would hang on the terminal TRAP_STATE); executing PAST it -> FAIL.
#
# This is the illegal-SIBLING probe: it is built and run against a Zicboz-ON MCU
# as well as the stripped build (mirrors X2's casill.S for amocas.d). The
# negative control "legalize-sibling seed" (admit cbo.clean in maindec) makes
# this probe SURVIVE instead of TRAP_OK.
#
# cbo.clean rs1  ==  .insn i 0x0f, 0x2, x0, rs1, 0x1   (imm=0x001)
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define CBO_CLEAN(rs1)  .insn i 0x0f, 0x2, x0, rs1, 0x1

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, cbi_fail

    la   a1, cbi_word
    CBO_CLEAN(a1)                # cbo.clean — illegal on ANY build (must trap)
    j    cbi_fail                # reached only if it did NOT trap

cbi_fail:
    RVTEST_FAIL                  # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .align 6
cbi_word: .fill 16, 4, 0
RVTEST_DATA_END
