# See LICENSE for license details.

# VestaRV: amocas.d is always illegal on RV32
# amocas.d, funct3 = 011 with funct5 = 00101, requires an XLEN-pair register file and is UNSUPPORTED on RV32, so its width case is illegal on EVERY build whether Zacas is on or off. This is a pure POISON: the encoding MUST take the illegal-instruction trap, and executing past it is a FAIL.
# It is run through the trap_watch harness, because the a0-watch runner would hang on the terminal TRAP_STATE, and it is BUILT AND RUN AGAINST A Zacas-ON MCU as well as the stripped build, which is the whole point of the probe.

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
