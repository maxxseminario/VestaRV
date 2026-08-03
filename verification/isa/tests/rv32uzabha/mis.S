# See LICENSE for license details.

#*****************************************************************************
# mis.S      (X2 Zabha — misaligned halfword AMO behaviour)
#-----------------------------------------------------------------------------
# SPEC-vs-CORE NOTE (flagged in the X2 self-report): the Zabha spec says a
# misaligned halfword AMO raises a store/AMO-address-misaligned exception. THIS
# core has NO data-address-misalignment exception and NO mcause/mtval CSRs — and
# WORD AMOs likewise do not trap on misalignment. "Misaligned exactly like word
# AMOs" therefore means NON-TRAPPING here: the sub-word datapath rounds down to
# the containing half (lane select keys on address bit 1 only, exactly like
# SH/LH/word-AMO), so a naturally-aligned software contract holds and a
# misaligned access is benign (no trap, no hang, no cross-half corruption).
#
# This test proves that observable behaviour: an amoadd.h at offset 1 (bit0=1,
# bit1=0) accesses HALF0 just like offset 0, and an amoadd.h at offset 3 accesses
# HALF1 just like offset 2 — no hang, the other half stays intact.
# ON-POLARITY ONLY. Encodings via `.insn`.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define AMOADD_H(rd,rs1,rs2)   .insn r 0x2f, 0x1, 0x00, rd, rs1, rs2

RVTEST_RV32U
RVTEST_CODE_BEGIN

    la   s0, amo_w

    # offset 1 (misaligned): must behave like offset 0 -> accesses HALF0
    li   t0, 0x11110000            # half0=0x0000, half1=0x1111
    sw   t0, 0(s0)
    addi a3, s0, 1                 # misaligned by 1
    li   a1, 0x0007
    AMOADD_H(a4, a3, a1)           # rounds to half0: 0x0000 + 7 -> 0x0007
    lw   a5, 0(s0)
    li   t1, 0x11110007            # half1 intact, half0 updated
    bne  a5, t1, zm_fail
    li   t1, 0x00000000            # rd = sext(old half0 = 0)
    bne  a4, t1, zm_fail

    # offset 3 (misaligned): must behave like offset 2 -> accesses HALF1
    li   t0, 0x22220000            # half0=0x0000, half1=0x2222
    sw   t0, 0(s0)
    addi a3, s0, 3                 # misaligned by 1 into the high half
    li   a1, 0x0003
    AMOADD_H(a4, a3, a1)           # rounds to half1: 0x2222 + 3 -> 0x2225
    lw   a5, 0(s0)
    li   t1, 0x22250000            # half0 intact, half1 updated
    bne  a5, t1, zm_fail
    li   t1, 0x00002222            # rd = sext(old half1 = 0x2222)
    bne  a4, t1, zm_fail

    RVTEST_PASS

zm_fail:
    RVTEST_FAIL

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .align 2
amo_w: .word 0
RVTEST_DATA_END
