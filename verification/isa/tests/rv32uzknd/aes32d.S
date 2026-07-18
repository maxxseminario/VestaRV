# See LICENSE for license details.

#*****************************************************************************
# aes32d.S   (X3 Zknd directed per-op test: aes32dsi / aes32dsmi, 2026-07-17)
#-----------------------------------------------------------------------------
# ON-POLARITY ONLY suite (rv32uzknd, built with -DCORE_ENABLE_ZKN). Directed
# known-answer checks for the two AES decrypt ops across all four byte-selects
# (bs 0..3) plus a rd==rs1 accumulate alias. Expected values from a host golden
# model that mirrors alu.vhd aes32_datapath() exactly.
#
#   aes32dsi  rd,rs1,rs2,bs : rd = rs1 XOR rol(zext(invSBOX(byte bs of rs2)),8*bs)
#   aes32dsmi rd,rs1,rs2,bs : rd = rs1 XOR rol(invMixCol(invSBOX(byte bs)),8*bs)
#
# gas 13.2 has no aes32* mnemonic; explicit `.insn' R-type (OP 0x33, funct3=0,
# funct7=(bs<<5)|fn5, fn5 dsi=0x15 dsmi=0x17).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define AES32DSI(rd,rs1,rs2,bs)  .insn r 0x33, 0x0, (0x15|((bs)<<5)), rd, rs1, rs2
#define AES32DSMI(rd,rs1,rs2,bs) .insn r 0x33, 0x0, (0x17|((bs)<<5)), rd, rs1, rs2

#define CK_DSI(rs1v,rs2v,bs,exp)  \
    li a1, rs1v; li a2, rs2v; AES32DSI(a3,a1,a2,bs);  li a4, exp; bne a3, a4, d32_fail
#define CK_DSMI(rs1v,rs2v,bs,exp) \
    li a1, rs1v; li a2, rs2v; AES32DSMI(a3,a1,a2,bs); li a4, exp; bne a3, a4, d32_fail

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, d32_fail

    # ---- aes32dsi across bs 0..3 ----
    CK_DSI(0xdeadbeef, 0x89abcdef, 0, 0xdeadbe8e)
    CK_DSI(0x11223344, 0x89abcdef, 1, 0x1122b344)
    CK_DSI(0xffffffff, 0x00010203, 2, 0xfff6ffff)
    CK_DSI(0x00000000, 0xa5a5a5a5, 3, 0x29000000)
    CK_DSI(0xcafebabe, 0x5c5c5c5c, 1, 0xcafe1dbe)

    # ---- aes32dsmi across bs 0..3 ----
    CK_DSMI(0xdeadbeef, 0x89abcdef, 0, 0x5876fa97)
    CK_DSMI(0x11223344, 0x89abcdef, 1, 0xcbce72b3)
    CK_DSMI(0xffffffff, 0x00010203, 2, 0xbe81ac9a)
    CK_DSMI(0x00000000, 0xa5a5a5a5, 3, 0xa528de7a)
    CK_DSMI(0xcafebabe, 0x5c5c5c5c, 1, 0x88160a03)

    # ---- rd==rs1 accumulate alias ----
    li   a3, 0xdeadbeef
    li   a2, 0x89abcdef
    AES32DSMI(a3, a3, a2, 0)
    li   a4, 0x5876fa97
    bne  a3, a4, d32_fail

    RVTEST_PASS

d32_fail:
    RVTEST_FAIL

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
