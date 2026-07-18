# See LICENSE for license details.

#*****************************************************************************
# zbk.S   (X3 Stage B directed test: Zbkb + Zbkx + Zbkc, 2026-07-17)
#-----------------------------------------------------------------------------
# Single-hart, purely combinational ALU directed test with KNOWN-ANSWER vectors
# for every new scalar-crypto bit-manip op:
#   Zbkb: pack packh brev8 zip unzip
#   Zbkx: xperm8 xperm4  (incl. out-of-range index -> 0 lanes)
#   Zbkc: clmul clmulh   (OR-gated onto the existing Zbc datapath)
#
# BOTH-POLARITY (shzabha convention): the OFF build is the DEFAULT build (none of
# CORE_ENABLE_ZBK* defined) and degrades to a trivially-passing arm so the suite
# stays green; the ON build is produced by EXPLICITLY appending
# -DCORE_ENABLE_ZBKB -DCORE_ENABLE_ZBKX -DCORE_ENABLE_ZBKC (mirrors the RTL
# generics set true in MemoryMap.vhd). gas 13.2 has no zbk* mnemonics, so every
# op is emitted with a raw `.insn` encoding under the base -march.
#
# Pass = 0xCAFEBABE in a0.  CORE_ENABLE_ZBK* come from the build -D flags, never
# an include.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

# ---- raw encodings (authoritative; re-verified vs ratified Zbkb/Zbkx) --------
# R-type:  .insn r opcode, funct3, funct7, rd, rs1, rs2
#define PACK(rd,rs1,rs2)   .insn r 0x33, 0x4, 0x04, rd, rs1, rs2
#define PACKH(rd,rs1,rs2)  .insn r 0x33, 0x7, 0x04, rd, rs1, rs2
#define XPERM8(rd,rs1,rs2) .insn r 0x33, 0x4, 0x14, rd, rs1, rs2
#define XPERM4(rd,rs1,rs2) .insn r 0x33, 0x2, 0x14, rd, rs1, rs2
#define CLMUL(rd,rs1,rs2)  .insn r 0x33, 0x1, 0x05, rd, rs1, rs2
#define CLMULH(rd,rs1,rs2) .insn r 0x33, 0x3, 0x05, rd, rs1, rs2
# OP-IMM:  .insn i opcode, funct3, rd, rs1, simm12  (simm12 = instr[31:20])
#define BREV8(rd,rs1)      .insn i 0x13, 0x5, rd, rs1, 0x687
#define ZIP(rd,rs1)        .insn i 0x13, 0x1, rd, rs1, 0x08F
#define UNZIP(rd,rs1)      .insn i 0x13, 0x5, rd, rs1, 0x08F
# Zbb-shared subset (legal under Zbkb even when Zbb is off): andn/orn/xnor/rol/ror/rori/rev8
#define ANDN(rd,rs1,rs2)   .insn r 0x33, 0x7, 0x20, rd, rs1, rs2
#define ORN(rd,rs1,rs2)    .insn r 0x33, 0x6, 0x20, rd, rs1, rs2
#define XNOR(rd,rs1,rs2)   .insn r 0x33, 0x4, 0x20, rd, rs1, rs2
#define ROL(rd,rs1,rs2)    .insn r 0x33, 0x1, 0x30, rd, rs1, rs2
#define ROR(rd,rs1,rs2)    .insn r 0x33, 0x5, 0x30, rd, rs1, rs2
#define RORI(rd,rs1,sh)    .insn i 0x13, 0x5, rd, rs1, (0x600 + (sh))
#define REV8(rd,rs1)       .insn i 0x13, 0x5, rd, rs1, 0x698

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li  TESTNUM, 0

#if defined(CORE_ENABLE_ZBKB)
    #-------------------------------------------------------------
    # Zbkb: pack / packh
    #-------------------------------------------------------------
    # pack rd = (rs2[15:0] << 16) | rs1[15:0]
    TEST_CASE( 2, x28, 0xDEF05678, li x29,0x12345678; li x30,0x9ABCDEF0; PACK(x28,x29,x30) )
    # pack rs2=x0 == zext.h(rs1)
    TEST_CASE( 3, x28, 0x00005678, li x29,0x12345678; PACK(x28,x29,x0) )
    # packh rd = zext16( (rs2[7:0]<<8) | rs1[7:0] )
    TEST_CASE( 4, x28, 0x0000F078, li x29,0x12345678; li x30,0x9ABCDEF0; PACKH(x28,x29,x30) )

    #-------------------------------------------------------------
    # Zbkb: brev8 (reverse bits within each byte)
    #-------------------------------------------------------------
    TEST_CASE( 5, x28, 0x482C6A1E, li x29,0x12345678; BREV8(x28,x29) )
    TEST_CASE( 6, x28, 0x00000000, li x29,0x00000000; BREV8(x28,x29) )
    TEST_CASE( 7, x28, 0xFFFFFFFF, li x29,0xFFFFFFFF; BREV8(x28,x29) )

    #-------------------------------------------------------------
    # Zbkb: zip / unzip (RV32 bit interleave, mutually inverse)
    #-------------------------------------------------------------
    # zip 0x0000FFFF -> even bits set -> 0x55555555
    TEST_CASE( 8, x28, 0x55555555, li x29,0x0000FFFF; ZIP(x28,x29) )
    # unzip 0x55555555 -> low half all ones -> 0x0000FFFF (inverse of above)
    TEST_CASE( 9, x28, 0x0000FFFF, li x29,0x55555555; UNZIP(x28,x29) )
    # round-trip: unzip(zip(x)) == x
    TEST_CASE(10, x28, 0xDEADBEEF, li x29,0xDEADBEEF; ZIP(x28,x29); UNZIP(x28,x28) )

    #-------------------------------------------------------------
    # Zbkb / Zbb-SHARED subset (andn/orn/xnor/rol/ror/rori/rev8).
    # These MUST be legal + correct under Zbkb even when Zbb (BITMANIP) is OFF
    # -- this section is the ONLY exerciser of the ZBKB-vs-BITMANIP OR-gating in
    # a Zbkb-only build (see the CORE_ENABLE_BITMANIP=false directed run).
    #-------------------------------------------------------------
    TEST_CASE(17, x28, 0xF000F000, li x29,0xFF00FF00; li x30,0x0F0F0F0F; ANDN(x28,x29,x30) )
    TEST_CASE(18, x28, 0xFFF0FFF0, li x29,0xFF00FF00; li x30,0x0F0F0F0F; ORN(x28,x29,x30) )
    TEST_CASE(19, x28, 0x0FF00FF0, li x29,0xFF00FF00; li x30,0x0F0F0F0F; XNOR(x28,x29,x30) )
    TEST_CASE(20, x28, 0x34567812, li x29,0x12345678; li x30,8; ROL(x28,x29,x30) )
    TEST_CASE(21, x28, 0x78123456, li x29,0x12345678; li x30,8; ROR(x28,x29,x30) )
    TEST_CASE(22, x28, 0x81234567, li x29,0x12345678; RORI(x28,x29,4) )
    TEST_CASE(23, x28, 0x78563412, li x29,0x12345678; REV8(x28,x29) )
#endif

#if defined(CORE_ENABLE_ZBKX)
    #-------------------------------------------------------------
    # Zbkx: xperm8 (byte crossbar; index rs2.byte[i], >=4 -> 0)
    #-------------------------------------------------------------
    # rs1=0xAABBCCDD (byte0..3 = DD CC BB AA), rs2 bytes = {02,01,00,03}
    #   -> rd bytes = {rs1[2],rs1[1],rs1[0],rs1[3]} = {BB,CC,DD,AA} = 0xAADDCCBB
    TEST_CASE(11, x28, 0xAADDCCBB, li x29,0xAABBCCDD; li x30,0x03000102; XPERM8(x28,x29,x30) )
    # out-of-range: rs2 byte3=0x04 (>=4) -> rd byte3 = 0 ; others select 1,2,3
    TEST_CASE(12, x28, 0x00AABBCC, li x29,0xAABBCCDD; li x30,0x04030201; XPERM8(x28,x29,x30) )

    #-------------------------------------------------------------
    # Zbkx: xperm4 (nibble crossbar; index rs2.nibble[i], >=8 -> 0)
    #-------------------------------------------------------------
    # rs1=0x76543210 (nibble j == j), rs2 nibbles reverse-index -> nibble i = 7-i
    TEST_CASE(13, x28, 0x01234567, li x29,0x76543210; li x30,0x01234567; XPERM4(x28,x29,x30) )
    # out-of-range: all rs2 nibbles = 8 (>=8) -> rd = 0
    TEST_CASE(14, x28, 0x00000000, li x29,0x76543210; li x30,0x88888888; XPERM4(x28,x29,x30) )
#endif

#if defined(CORE_ENABLE_ZBKC)
    #-------------------------------------------------------------
    # Zbkc: clmul / clmulh  (carry-less multiply; Zbc datapath, ZBKC-gated)
    #-------------------------------------------------------------
    # clmul(3,5): 0b11 (*) 0b101 = 0b1111 = 0xF
    TEST_CASE(15, x28, 0x0000000F, li x29,0x3; li x30,0x5; CLMUL(x28,x29,x30) )
    # clmulh(0x80000000, 2): (a<<1) high word = bit32 -> 0x1
    TEST_CASE(16, x28, 0x00000001, li x29,0x80000000; li x30,0x2; CLMULH(x28,x29,x30) )
#endif

    # Fall-through (all cases passed, or OFF build ran nothing): force a nonzero
    # TESTNUM so TEST_PASSFAIL reports PASS. A failing case above already branched
    # straight to `fail` inside TEST_CASE, so this never masks a real miscompare.
    li  TESTNUM, 0xB
    TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
