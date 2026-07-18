# See LICENSE for license details.

#*****************************************************************************
# amoops_b.S  (X2 Zabha directed suite — all nine byte AMOs)
#-----------------------------------------------------------------------------
# Directed functional check of every Zabha byte AMO (funct3=000): rd receives
# the SIGN-EXTENDED old byte, memory's byte lane gets the truncated result, and
# the three adjacent lanes stay intact. Exercises all four lane positions.
#
# ON-POLARITY ONLY (rv32uzicond precedent): the encodings are illegal on a
# zabha-OFF build (they take the terminal illegal-instruction trap), so this
# suite is simulated against a zabha-ON MCU, never the default 124-suite.
#
# gas 13.2 lacks the amoadd.b mnemonics / `zabha` -march, so every Zabha op is
# an explicit `.insn r 0x2f, funct3, funct7, rd, rs1_base, rs2_val`
# (funct7 = funct5<<2, aq=rl=0).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define AMOADD_B(rd,rs1,rs2)   .insn r 0x2f, 0x0, 0x00, rd, rs1, rs2
#define AMOSWAP_B(rd,rs1,rs2)  .insn r 0x2f, 0x0, 0x04, rd, rs1, rs2
#define AMOXOR_B(rd,rs1,rs2)   .insn r 0x2f, 0x0, 0x10, rd, rs1, rs2
#define AMOOR_B(rd,rs1,rs2)    .insn r 0x2f, 0x0, 0x20, rd, rs1, rs2
#define AMOAND_B(rd,rs1,rs2)   .insn r 0x2f, 0x0, 0x30, rd, rs1, rs2
#define AMOMIN_B(rd,rs1,rs2)   .insn r 0x2f, 0x0, 0x40, rd, rs1, rs2
#define AMOMAX_B(rd,rs1,rs2)   .insn r 0x2f, 0x0, 0x50, rd, rs1, rs2
#define AMOMINU_B(rd,rs1,rs2)  .insn r 0x2f, 0x0, 0x60, rd, rs1, rs2
#define AMOMAXU_B(rd,rs1,rs2)  .insn r 0x2f, 0x0, 0x70, rd, rs1, rs2

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # amoadd.b at each of the 4 lanes: base word 0x04030201; add 0x10 to a lane.
    la   s0, amo_w

    # lane 0 (0x01): rd=sext(0x01)=1 ; byte0 -> 0x11
    li   t0, 0x04030201
    sw   t0, 0(s0)
    li   a1, 0x10
    AMOADD_B(a4, s0, a1)
    li   t1, 0x00000001
    bne  a4, t1, zb_fail
    lw   a5, 0(s0)
    li   t1, 0x04030211
    bne  a5, t1, zb_fail

    # lane 1 (0x02): rd=2 ; byte1 -> 0x12
    li   t0, 0x04030201
    sw   t0, 0(s0)
    addi a3, s0, 1
    li   a1, 0x10
    AMOADD_B(a4, a3, a1)
    li   t1, 0x00000002
    bne  a4, t1, zb_fail
    lw   a5, 0(s0)
    li   t1, 0x04031201
    bne  a5, t1, zb_fail

    # lane 2 (0x03): rd=3 ; byte2 -> 0x13
    li   t0, 0x04030201
    sw   t0, 0(s0)
    addi a3, s0, 2
    li   a1, 0x10
    AMOADD_B(a4, a3, a1)
    li   t1, 0x00000003
    bne  a4, t1, zb_fail
    lw   a5, 0(s0)
    li   t1, 0x04130201
    bne  a5, t1, zb_fail

    # lane 3 (0x04): rd=4 ; byte3 -> 0x14
    li   t0, 0x04030201
    sw   t0, 0(s0)
    addi a3, s0, 3
    li   a1, 0x10
    AMOADD_B(a4, a3, a1)
    li   t1, 0x00000004
    bne  a4, t1, zb_fail
    lw   a5, 0(s0)
    li   t1, 0x14030201
    bne  a5, t1, zb_fail

    # amoswap.b lane 0: old sext, byte replaced, adjacent intact
    li   t0, 0xAABBCC80            # byte0 = 0x80 (neg)
    sw   t0, 0(s0)
    li   a1, 0x55
    AMOSWAP_B(a4, s0, a1)
    li   t1, 0xFFFFFF80            # rd = sext(0x80)
    bne  a4, t1, zb_fail
    lw   a5, 0(s0)
    li   t1, 0xAABBCC55
    bne  a5, t1, zb_fail

    # amoand.b / amoor.b / amoxor.b (lane 0)
    li   t0, 0x000000F0
    sw   t0, 0(s0)
    li   a1, 0x3C
    AMOAND_B(a4, s0, a1)
    lbu  a5, 0(s0)
    li   t1, 0x30
    bne  a5, t1, zb_fail
    li   a1, 0x0F
    AMOOR_B(a4, s0, a1)
    lbu  a5, 0(s0)
    li   t1, 0x3F
    bne  a5, t1, zb_fail
    li   a1, 0xFF
    AMOXOR_B(a4, s0, a1)
    lbu  a5, 0(s0)
    li   t1, 0xC0
    bne  a5, t1, zb_fail

    # amomin.b / amomax.b SIGNED  (0x7F vs 0x80=-128)
    li   t0, 0x0000007F
    sw   t0, 0(s0)
    li   a1, 0x80
    AMOMIN_B(a4, s0, a1)           # signed min -> -128 (0x80)
    lbu  a5, 0(s0)
    li   t1, 0x80
    bne  a5, t1, zb_fail
    li   t0, 0x0000007F
    sw   t0, 0(s0)
    li   a1, 0x80
    AMOMAX_B(a4, s0, a1)           # signed max -> 0x7F
    lbu  a5, 0(s0)
    li   t1, 0x7F
    bne  a5, t1, zb_fail

    # amominu.b / amomaxu.b UNSIGNED  (monotonicity of sign-extension)
    li   t0, 0x00000080
    sw   t0, 0(s0)
    li   a1, 0x7F
    AMOMINU_B(a4, s0, a1)          # unsigned min -> 0x7F
    lbu  a5, 0(s0)
    li   t1, 0x7F
    bne  a5, t1, zb_fail
    li   t0, 0x0000007F
    sw   t0, 0(s0)
    li   a1, 0x80
    AMOMAXU_B(a4, s0, a1)          # unsigned max -> 0x80
    lbu  a5, 0(s0)
    li   t1, 0x80
    bne  a5, t1, zb_fail

    RVTEST_PASS

zb_fail:
    RVTEST_FAIL

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .align 2
amo_w: .word 0
RVTEST_DATA_END
