# See LICENSE for license details.

# VestaRV: Zbkb reserved-encoding trap probe
# PURE POISON, always executed with no ifdef. The OP-IMM encoding with funct3 = 001 and imm12 = 0x698, which is `binvi rd, rs1, 24`, a Zbs encoding, must take the illegal-instruction trap on ANY build without Zbs.
# THIS IS THE EXACT ENCODING A DECODE BUG WRONGLY ADMITTED: an early is_zbkb_shared_i clause matched funct3 = 001 instead of the correct 101 on imm12 = REV8_IMM12 = 0x698, so on a Zbkb-on build it decoded valid even though real rev8 is funct3 = 101. With is_zbkb_shared_i matching only funct3 = 101 the encoding is Zbkb-independent again and falls to the SRL/SLL-group illegal path.
# Verified under the trap_watch harness on both the all-off stripped build and the Zbkb-on, BITMANIP-off build. It is wired into POISON_RCFS and not the a0-watch suite, where a terminal trap would hang the watchdog.

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

# funct3=001, imm12=0x698 (BINVI rd,rs1,24) -- illegal without Zbs.
#define RSV_BINVI24(rd,rs1) .insn i 0x13, 0x1, rd, rs1, 0x698

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity (runs on every build, like extprobe.S) ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, ezr_fail

    # ---- POISON: the reserved encoding MUST trap here ----
    li   x29, 0x12345678
    RSV_BINVI24(x28, x29)          # illegal without Zbs -> trap; falling through = FAIL
    j    ezr_fail

ezr_fail:
    RVTEST_FAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
