# See LICENSE for license details.

#*****************************************************************************
# extzbkb.S   (X3 Stage B Zbkb ext-probe, 2026-07-17)
#-----------------------------------------------------------------------------
# Build-time dispatch on CORE_ENABLE_ZBKB (extprobe_template.S convention — the
# macro is supplied EXPLICITLY via -DCORE_ENABLE_ZBKB when staging the ON
# polarity, NEVER auto-derived from a make-chip header or platform/common/out/).
#
#   ON  (#ifdef CORE_ENABLE_ZBKB): execute the real pack/packh/brev8 encodings
#       and CHECK the architectural results -> PASS.
#   OFF (#else): the SAME packh encoding executed UNCONDITIONALLY. On a build
#       without Zbkb (the extoff POISON build, all CORE_ENABLE_* false) the
#       encoding MUST take the illegal-instruction trap; run_extoff.sh +
#       trap_watch.tcl report TRAP_OK, executing past it -> FAIL. packh
#       (funct7=0000100,funct3=111) is illegal on a Zbb-ON build too (it is not
#       a Zbb encoding), so this is a clean Zbkb-specific poison.
#
# `.insn` encodings — gas 13.2 has no zbk* mnemonics.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define PACK(rd,rs1,rs2)   .insn r 0x33, 0x4, 0x04, rd, rs1, rs2
#define PACKH(rd,rs1,rs2)  .insn r 0x33, 0x7, 0x04, rd, rs1, rs2
#define BREV8(rd,rs1)      .insn i 0x13, 0x5, rd, rs1, 0x687

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity (runs on every build, like extprobe.S) ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, ezb_fail

#ifdef CORE_ENABLE_ZBKB
    # ============ FEATURE ON: functional pack/packh/brev8 checks ============
    li   x29, 0x12345678
    li   x30, 0x9ABCDEF0
    PACK(x28, x29, x30)            # (rs2[15:0]<<16)|rs1[15:0] = 0xDEF05678
    li   t1, 0xDEF05678
    bne  x28, t1, ezb_fail

    PACKH(x28, x29, x30)           # zext16((rs2[7:0]<<8)|rs1[7:0]) = 0x0000F078
    li   t1, 0x0000F078
    bne  x28, t1, ezb_fail

    BREV8(x28, x29)                # reverse bits per byte of 0x12345678 = 0x482C6A1E
    li   t1, 0x482C6A1E
    bne  x28, t1, ezb_fail

    j    ezb_pass
#else
    # ============ FEATURE OFF (POISON): packh must trap illegal ============
    li   x29, 0x12345678
    li   x30, 0x9ABCDEF0
    PACKH(x28, x29, x30)           # illegal without Zbkb -> trap; falling through = FAIL
    j    ezb_fail
#endif

ezb_pass:
    RVTEST_PASS
ezb_fail:
    RVTEST_FAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
