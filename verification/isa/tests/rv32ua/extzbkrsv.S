# See LICENSE for license details.

#*****************************************************************************
# extzbkrsv.S   (X3 Stage B Zbkb reserved-encoding trap probe, 2026-07-17)
#-----------------------------------------------------------------------------
# PURE POISON (always executes; no #ifdef). The OP-IMM encoding funct3=001,
# imm12=0x698 (== BINVI rd,rs1,24, a Zbs encoding) must take the illegal-
# instruction trap on ANY build without the Zbs (BITMANIP) extension.
#
# This is the exact encoding the Stage-B1 decode bug wrongly admitted: an early
# is_zbkb_shared_i clause matched funct3=001 (instead of the correct funct3=101)
# on imm12=REV8_IMM12=0x698, so on a ZBKB-on build it was decoded valid even
# though it is NOT a Zbkb instruction (real rev8 is funct3=101). The fix makes
# is_zbkb_shared_i match ONLY funct3=101, so this encoding is again ZBKB-
# independent and falls to the SRL/SLL-group illegal path -> trap.
#
# Verified via the trap_watch harness (behavioral_mp_stripped/run_extoff.sh):
#   * all-off stripped build (Zbs off, ZBKB off) -> TRAP_OK
#   * ZBKB-on / BITMANIP-off build               -> TRAP_OK (the fix's target)
# Wired into POISON_RCFS, not the a0-watch 118-suite (a terminal trap would hang
# the a0 watchdog).
#*****************************************************************************

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
