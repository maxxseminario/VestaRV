# See LICENSE for license details.

#*****************************************************************************
# extzicboz.S   (X3 Zicboz ext-probe, 2026-07-17)
#-----------------------------------------------------------------------------
# Build-time dispatch on CORE_ENABLE_ZICBOZ (extprobe_template.S convention —
# the macro is supplied EXPLICITLY via -DCORE_ENABLE_ZICBOZ when staging the ON
# polarity, NEVER auto-derived from a make-chip header or platform/common/out/
# state; the two build-order traps in that header apply verbatim).
#
#   ON  (#ifdef CORE_ENABLE_ZICBOZ): execute a real cbo.zero on a poisoned
#       64-byte block and CHECK the architectural result -> PASS. Asserts all 16
#       words == 0 AND the words immediately BEFORE and AFTER the block are
#       untouched (the boundary guard).
#
#   OFF (#else): the cbo.zero encoding executed UNCONDITIONALLY. On a build
#       without Zicboz the encoding MUST take the illegal-instruction trap (the
#       FENCE/MISC-MEM funct3=010 imm=0x004 encoding is reserved when Zicboz is
#       off). run_extoff.sh + trap_watch.tcl report TRAP_OK; executing PAST it
#       -> FAIL. Wired ONLY into behavioral_mp_stripped/run_extoff.sh (the
#       a0-watch runner would hang on the terminal TRAP_STATE).
#
# The illegal-SIBLING assertion (cbo.clean/flush/inval always trap) lives in the
# companion terminal-trap poison cbozill.S (run under trap_watch on EVERY build)
# — this core's illegal-instruction trap is TERMINAL (TRAP_STATE self-loops,
# trap_flag high), so an in-test recoverable "cbo.clean traps" check is not
# possible; cbozill.S is the faithful realization (mirrors X2's casill.S).
#
# CORRECTED 2026-08-03 (K2b amendment 2), MEASURED. This header used to claim
# "gas 13.2 has no `zicboz' -march / no cbo.zero mnemonic". That is FALSE on this
# toolchain: gas 2.41 accepts both `-march=rv32imac_zicsr_zicboz' and
# `.option arch, +zicboz', assembles `cbo.zero (a1)' to 0x0045a00f, and refuses
# the mnemonic without the extension ("extension `zicboz' required").
# The explicit `.insn' below is KEPT, and deliberately: it is march-INDEPENDENT,
# so ONE source serves both polarities (the OFF arm must emit the encoding on a
# build whose -march has no zicboz) and no per-polarity -march is needed.
# It encodes the identical word -- objdump on this file's ON build shows
# `0045a00f' at the CBO_ZERO site, the same word the mnemonic produces.
# cbo.zero rs1  ==  .insn i 0x0f (MISC-MEM), funct3=0x2, rd=x0, rs1, imm=0x004.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define CBO_ZERO(rs1)  .insn i 0x0f, 0x2, x0, rs1, 0x4

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity (runs on every build, like extprobe.S) ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, ezb_fail

#ifdef CORE_ENABLE_ZICBOZ
    # =====================================================================
    # FEATURE ON: cbo.zero a poisoned block; assert 16 zeroed + guards intact.
    # =====================================================================
    la   a1, ezb_block           # 64-byte aligned (see .align 6)

    # poison the 16 words to 0xAA and set before/after guard sentinels
    li   t0, 0xAAAAAAAA
    li   t1, 0
1:  slli t2, t1, 2
    add  t2, a1, t2
    sw   t0, 0(t2)
    addi t1, t1, 1
    li   t2, 16
    bne  t1, t2, 1b
    li   t0, 0x11111111
    sw   t0, -4(a1)              # guard BEFORE
    li   t0, 0x22222222
    sw   t0, 64(a1)             # guard AFTER

    CBO_ZERO(a1)                # zero the naturally-aligned 64-byte block

    # check all 16 words are now 0
    li   t1, 0
2:  slli t2, t1, 2
    add  t2, a1, t2
    lw   t0, 0(t2)
    bnez t0, ezb_fail
    addi t1, t1, 1
    li   t2, 16
    bne  t1, t2, 2b
    # check both guards are untouched (boundary guard)
    lw   t0, -4(a1)
    li   t2, 0x11111111
    bne  t0, t2, ezb_fail
    lw   t0, 64(a1)
    li   t2, 0x22222222
    bne  t0, t2, ezb_fail

    RVTEST_PASS

#else
    # =====================================================================
    # FEATURE OFF (extoff POISON): cbo.zero MUST take the illegal-instr trap.
    # =====================================================================
    la   a1, ezb_block
    CBO_ZERO(a1)                # cbo.zero — illegal without Zicboz, must trap
    j    ezb_fail               # reached only if it did NOT trap
#endif

ezb_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .align 6
ezb_guard_lo: .word 0
  .align 6
ezb_block:  .fill 16, 4, 0
ezb_guard_hi: .word 0
  .word 0
RVTEST_DATA_END
