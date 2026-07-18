# See LICENSE for license details.

#*****************************************************************************
# extzbkx.S   (X3 Stage B Zbkx ext-probe, 2026-07-17)
#-----------------------------------------------------------------------------
# Build-time dispatch on CORE_ENABLE_ZBKX (extprobe_template.S convention — the
# macro is supplied EXPLICITLY via -DCORE_ENABLE_ZBKX when staging the ON
# polarity, NEVER auto-derived from a make-chip header or platform/common/out/).
#
#   ON  (#ifdef CORE_ENABLE_ZBKX): execute xperm8/xperm4 (incl. out-of-range
#       index -> 0) and CHECK the architectural results -> PASS.
#   OFF (#else): the SAME xperm8 encoding executed UNCONDITIONALLY. On a build
#       without Zbkx (the extoff POISON build) it MUST take the illegal trap;
#       run_extoff.sh + trap_watch.tcl report TRAP_OK, past it -> FAIL. xperm8
#       (funct7=0010100,funct3=100) is illegal on a Zbb-ON build too (funct7
#       aliases BSET's, but BSET needs funct3=001), so this is a clean poison.
#
# `.insn` encodings — gas 13.2 has no zbk* mnemonics.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define XPERM8(rd,rs1,rs2) .insn r 0x33, 0x4, 0x14, rd, rs1, rs2
#define XPERM4(rd,rs1,rs2) .insn r 0x33, 0x2, 0x14, rd, rs1, rs2

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity (runs on every build, like extprobe.S) ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, ezx_fail

#ifdef CORE_ENABLE_ZBKX
    # ============ FEATURE ON: functional xperm8/xperm4 checks ============
    # rs1=0xAABBCCDD, rs2 bytes {02,01,00,03} -> {BB,CC,DD,AA} = 0xAADDCCBB
    li   x29, 0xAABBCCDD
    li   x30, 0x03000102
    XPERM8(x28, x29, x30)
    li   t1, 0xAADDCCBB
    bne  x28, t1, ezx_fail

    # out-of-range byte index (0x04 >= 4) zeroes that lane -> 0x00AABBCC
    li   x30, 0x04030201
    XPERM8(x28, x29, x30)
    li   t1, 0x00AABBCC
    bne  x28, t1, ezx_fail

    # xperm4: rs1 nibble j == j, rs2 reverse-index -> nibble i = 7-i = 0x01234567
    li   x29, 0x76543210
    li   x30, 0x01234567
    XPERM4(x28, x29, x30)
    li   t1, 0x01234567
    bne  x28, t1, ezx_fail

    # out-of-range nibble index (all 8 >=8) -> 0
    li   x30, 0x88888888
    XPERM4(x28, x29, x30)
    bnez x28, ezx_fail

    j    ezx_pass
#else
    # ============ FEATURE OFF (POISON): xperm8 must trap illegal ============
    li   x29, 0xAABBCCDD
    li   x30, 0x03000102
    XPERM8(x28, x29, x30)          # illegal without Zbkx -> trap; falling through = FAIL
    j    ezx_fail
#endif

ezx_pass:
    RVTEST_PASS
ezx_fail:
    RVTEST_FAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
