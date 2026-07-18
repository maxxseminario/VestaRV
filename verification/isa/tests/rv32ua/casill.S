# See LICENSE for license details.

#*****************************************************************************
# casill.S   (X2 Zacas — amocas.d is ALWAYS illegal on RV32)
#-----------------------------------------------------------------------------
# amocas.d (funct3=011, funct5=00101) requires an XLEN-pair register file and is
# UNSUPPORTED on RV32 (gate decision D5). Its width case is illegal on EVERY
# build — Zacas ON or OFF — so this is a pure POISON: the encoding MUST take the
# illegal-instruction trap. Run through the trap_watch harness (the a0-watch
# runner would hang on the terminal TRAP_STATE); executing PAST it -> FAIL.
#
# This is the "amocas.d traps EVEN when Zacas is ON" probe: it is built and run
# against a Zacas-ON MCU as well as the stripped build.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define AMOCAS_D(rd,rs1,rs2)  .insn r 0x2f, 0x3, 0x14, rd, rs1, rs2

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, cill_fail

    la   a1, cill_word
    li   a2, 0
    li   a4, 1
    AMOCAS_D(a2, a1, a4)         # amocas.d — illegal on RV32 (must trap on ANY build)
    j    cill_fail               # reached only if it did NOT trap

cill_fail:
    RVTEST_FAIL                  # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .align 3
cill_word: .dword 0
RVTEST_DATA_END
