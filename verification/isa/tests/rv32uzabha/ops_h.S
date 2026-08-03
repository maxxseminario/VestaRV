# See LICENSE for license details.

#*****************************************************************************
# ops_h.S      (X2 Zabha directed suite — halfword AMOs, both lanes)
#-----------------------------------------------------------------------------
# Directed functional check of Zabha halfword AMOs (funct3=001): rd receives the
# SIGN-EXTENDED old halfword, memory's addressed half gets the truncated result,
# and the OTHER half stays intact. Exercises half0 (addr+0) and half1 (addr+2).
# ON-POLARITY ONLY. Encodings via `.insn` (see ops_b.S header).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define AMOADD_H(rd,rs1,rs2)   .insn r 0x2f, 0x1, 0x00, rd, rs1, rs2
#define AMOSWAP_H(rd,rs1,rs2)  .insn r 0x2f, 0x1, 0x04, rd, rs1, rs2
#define AMOMAX_H(rd,rs1,rs2)   .insn r 0x2f, 0x1, 0x50, rd, rs1, rs2
#define AMOMINU_H(rd,rs1,rs2)  .insn r 0x2f, 0x1, 0x60, rd, rs1, rs2

RVTEST_RV32U
RVTEST_CODE_BEGIN

    la   s0, amo_w

    # amoadd.h half0, negative half -> rd sign-extended, half1 intact
    li   t0, 0x12348000            # half0=0x8000, half1=0x1234
    sw   t0, 0(s0)
    li   a1, 0x0001
    AMOADD_H(a4, s0, a1)
    li   t1, 0xFFFF8000            # rd = sext(0x8000)
    bne  a4, t1, zh_fail
    lw   a5, 0(s0)
    li   t1, 0x12348001            # half1 untouched
    bne  a5, t1, zh_fail

    # amoswap.h half1 (addr+2) -> only high half written
    li   t0, 0x11112222
    sw   t0, 0(s0)
    addi a3, s0, 2
    li   a1, 0xF00D
    AMOSWAP_H(a4, a3, a1)
    li   t1, 0x00001111            # rd = sext(0x1111)
    bne  a4, t1, zh_fail
    lw   a5, 0(s0)
    li   t1, 0xF00D2222            # low half untouched
    bne  a5, t1, zh_fail

    # amomax.h SIGNED half0: max(0x7FFF, 0x8000=-32768) = 0x7FFF
    li   t0, 0x00007FFF
    sw   t0, 0(s0)
    li   a1, 0x8000
    AMOMAX_H(a4, s0, a1)
    lhu  a5, 0(s0)
    li   t1, 0x7FFF
    bne  a5, t1, zh_fail

    # amominu.h UNSIGNED half0: min(0x8000, 0x7FFF) = 0x7FFF ; rd=sext(0x8000)
    li   t0, 0x00008000
    sw   t0, 0(s0)
    li   a1, 0x7FFF
    AMOMINU_H(a4, s0, a1)
    li   t1, 0xFFFF8000
    bne  a4, t1, zh_fail
    lhu  a5, 0(s0)
    li   t1, 0x7FFF
    bne  a5, t1, zh_fail

    RVTEST_PASS

zh_fail:
    RVTEST_FAIL

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .align 2
amo_w: .word 0
RVTEST_DATA_END
