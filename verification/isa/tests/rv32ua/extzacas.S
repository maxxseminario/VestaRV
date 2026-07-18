# See LICENSE for license details.

#*****************************************************************************
# extzacas.S   (X2 Zacas ext-probe, 2026-07-17)
#-----------------------------------------------------------------------------
# Build-time dispatch on CORE_ENABLE_ZACAS (extprobe_template.S convention —
# the macro is supplied EXPLICITLY via -DCORE_ENABLE_ZACAS when staging the ON
# polarity, NEVER auto-derived from a make-chip header or platform/common/out/
# state; the two build-order traps in that header apply verbatim).
#
#   ON  (#ifdef CORE_ENABLE_ZACAS): execute real amocas.w encodings and CHECK
#       the architectural results -> PASS. Functional matrix: both compare
#       outcomes + aliasing spot-checks (rd==rs1, rd==rs2). Sub-word amocas.b/.h
#       are additionally gated on CORE_ENABLE_ZABHA (they ride Zabha's lane
#       machinery and are legal ONLY when both extensions are built).
#
#   OFF (#else): the amocas.w encoding executed UNCONDITIONALLY. On a build
#       without Zacas the encoding MUST take the illegal-instruction trap
#       (funct5 whitelist: amocas.w is a RESERVED word AMO funct5 when Zacas is
#       off). run_extoff.sh + trap_watch.tcl report TRAP_OK; executing PAST it
#       -> FAIL. Wired ONLY into behavioral_mp_stripped/run_extoff.sh (the
#       a0-watch runner would hang on the terminal TRAP_STATE).
#
# gas 13.2 has no amocas mnemonic / no `zacas' -march (verified at X2 bring-up),
# so every CAS is an explicit `.insn' R-type (funct5=00101, funct7=0x14):
#     .insn r 0x2f, funct3, 0x14, rd, rs1_base, rs2_val
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define AMOCAS_W(rd,rs1,rs2)  .insn r 0x2f, 0x2, 0x14, rd, rs1, rs2
#define AMOCAS_B(rd,rs1,rs2)  .insn r 0x2f, 0x0, 0x14, rd, rs1, rs2
#define AMOCAS_H(rd,rs1,rs2)  .insn r 0x2f, 0x1, 0x14, rd, rs1, rs2

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity (runs on every build, like extprobe.S) ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, ezct_fail

#ifdef CORE_ENABLE_ZACAS
    # =====================================================================
    # FEATURE ON: functional amocas.w — both outcomes + aliasing.
    # =====================================================================

    # -- word CAS SUCCESS: rd==mem -> mem<-rs2, rd<-old --
    la   a1, ezc_word
    li   t0, 0x0000CAFE
    sw   t0, 0(a1)
    li   a2, 0x0000CAFE          # rd = compare (== mem)
    li   a3, 0xF00DBABE          # rs2 = swap
    AMOCAS_W(a2, a1, a3)
    li   t1, 0x0000CAFE
    bne  a2, t1, ezct_fail       # rd = old
    lw   a4, 0(a1)
    li   t1, 0xF00DBABE
    bne  a4, t1, ezct_fail       # mem swapped

    # -- word CAS FAIL: rd!=mem -> mem unchanged, rd<-old --
    la   a1, ezc_word
    li   t0, 0x0000CAFE
    sw   t0, 0(a1)
    li   a2, 0x12345678          # rd != mem
    li   a3, 0xF00DBABE          # rs2 (must NOT be written)
    AMOCAS_W(a2, a1, a3)
    li   t1, 0x0000CAFE
    bne  a2, t1, ezct_fail       # rd = old
    lw   a4, 0(a1)
    bne  a4, t1, ezct_fail       # mem unchanged

    # -- alias rd==rs1 SUCCESS: store the address so the compare matches --
    la   a2, ezc_word
    sw   a2, 0(a2)               # mem = address -> compare(rd==addr) matches
    li   a3, 0x5A5AA5A5          # rs2 = swap
    AMOCAS_W(a2, a2, a3)
    la   t2, ezc_word
    bne  a2, t2, ezct_fail       # rd = old = address
    lw   a4, 0(t2)
    li   t1, 0x5A5AA5A5
    bne  a4, t1, ezct_fail       # mem swapped at the registered address

    # -- alias rd==rs2 FAIL: compare != mem, swap value unused --
    la   a1, ezc_word
    li   t0, 0x11112222
    sw   t0, 0(a1)
    li   a2, 0x33334444          # rd == rs2 != mem
    AMOCAS_W(a2, a1, a2)
    li   t1, 0x11112222
    bne  a2, t1, ezct_fail       # rd = old
    lw   a4, 0(a1)
    bne  a4, t1, ezct_fail       # mem unchanged

#if defined(CORE_ENABLE_ZABHA)
    # -- sub-word amocas.b SUCCESS (only when Zabha is ALSO built) --
    la   a1, ezc_word
    li   t0, 0x44332211
    sw   t0, 0(a1)
    li   a2, 0x11               # rd low byte = compare (== mem byte0)
    li   a3, 0xAA               # rs2 low byte = swap
    AMOCAS_B(a2, a1, a3)
    li   t1, 0x00000011
    bne  a2, t1, ezct_fail      # rd = sext(old byte)
    lw   a4, 0(a1)
    li   t1, 0x443322AA         # only byte0 changed
    bne  a4, t1, ezct_fail

    # -- sub-word amocas.h FAIL (mem unchanged) --
    la   a1, ezc_word
    li   t0, 0x12348000
    sw   t0, 0(a1)
    li   a2, 0x1234            # rd low half != mem half0 (0x8000)
    li   a3, 0x0BAD           # rs2 (must NOT be written)
    AMOCAS_H(a2, a1, a3)
    li   t1, 0xFFFF8000         # rd = sext(old half0)
    bne  a2, t1, ezct_fail
    lw   a4, 0(a1)
    li   t1, 0x12348000         # mem unchanged
    bne  a4, t1, ezct_fail
#endif

    RVTEST_PASS

#else
    # =====================================================================
    # FEATURE OFF (extoff POISON): amocas.w MUST take the illegal-instr trap.
    # =====================================================================
    la   a1, ezc_word
    li   a2, 0x0
    li   a3, 0x1
    AMOCAS_W(a2, a1, a3)         # amocas.w — illegal without Zacas, must trap
    j    ezct_fail               # reached only if it did NOT trap

#endif

ezct_fail:
    RVTEST_FAIL                  # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .align 2
ezc_word: .word 0
RVTEST_DATA_END
