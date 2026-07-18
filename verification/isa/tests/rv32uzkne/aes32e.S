# See LICENSE for license details.

#*****************************************************************************
# aes32e.S   (X3 Zkne directed per-op test: aes32esi / aes32esmi, 2026-07-17)
#-----------------------------------------------------------------------------
# ON-POLARITY ONLY suite (rv32uzkne, built with -DCORE_ENABLE_ZKN). Directed
# known-answer checks for the two AES encrypt ops across all four byte-selects
# (bs 0..3) plus a rd==rs1 accumulate alias. Expected values from a host golden
# model that mirrors alu.vhd aes32_datapath() exactly.
#
#   aes32esi  rd,rs1,rs2,bs : rd = rs1 XOR rol(zext(SBOX(byte bs of rs2)), 8*bs)
#   aes32esmi rd,rs1,rs2,bs : rd = rs1 XOR rol(MixCol(SBOX(byte bs of rs2)), 8*bs)
#
# gas 13.2 has no aes32* mnemonic; explicit `.insn' R-type (OP 0x33, funct3=0,
# funct7=(bs<<5)|fn5, fn5 esi=0x11 esmi=0x13).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define AES32ESI(rd,rs1,rs2,bs)  .insn r 0x33, 0x0, (0x11|((bs)<<5)), rd, rs1, rs2
#define AES32ESMI(rd,rs1,rs2,bs) .insn r 0x33, 0x0, (0x13|((bs)<<5)), rd, rs1, rs2

# CHECK op: a1<-rs1, a2<-rs2, execute op a3,a1,a2,bs, compare a3 vs exp.
#define CK_ESI(rs1v,rs2v,bs,exp)  \
    li a1, rs1v; li a2, rs2v; AES32ESI(a3,a1,a2,bs);  li a4, exp; bne a3, a4, e32_fail
#define CK_ESMI(rs1v,rs2v,bs,exp) \
    li a1, rs1v; li a2, rs2v; AES32ESMI(a3,a1,a2,bs); li a4, exp; bne a3, a4, e32_fail

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, e32_fail

    # ---- aes32esi across bs 0..3 ----
    CK_ESI(0xdeadbeef, 0x89abcdef, 0, 0xdeadbe30)
    CK_ESI(0x11223344, 0x89abcdef, 1, 0x11228e44)
    CK_ESI(0xffffffff, 0x00010203, 2, 0xff83ffff)
    CK_ESI(0x00000000, 0xa5a5a5a5, 3, 0x06000000)
    CK_ESI(0xcafebabe, 0x5c5c5c5c, 1, 0xcafef0be)

    # ---- aes32esmi across bs 0..3 ----
    CK_ESMI(0xdeadbeef, 0x89abcdef, 0, 0xa472614a)
    CK_ESMI(0x11223344, 0x89abcdef, 1, 0xac9f5298)
    CK_ESMI(0xffffffff, 0x00010203, 2, 0x83077b83)
    CK_ESMI(0x00000000, 0xa5a5a5a5, 3, 0x0c0a0606)
    CK_ESMI(0xcafebabe, 0x5c5c5c5c, 1, 0x80b42e60)

    # ---- rd==rs1 accumulate alias (a3 is both src and dst) ----
    li   a3, 0xdeadbeef
    li   a2, 0x89abcdef
    AES32ESMI(a3, a3, a2, 0)
    li   a4, 0xa472614a
    bne  a3, a4, e32_fail

    RVTEST_PASS

e32_fail:
    RVTEST_FAIL

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
