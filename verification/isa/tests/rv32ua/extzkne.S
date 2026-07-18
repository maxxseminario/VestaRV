# See LICENSE for license details.

#*****************************************************************************
# extzkne.S   (X3 Zkne ext-probe, 2026-07-17)
#-----------------------------------------------------------------------------
# Build-time dispatch on CORE_ENABLE_ZKN (extprobe_template.S convention — the
# macro is supplied EXPLICITLY via -DCORE_ENABLE_ZKN when staging the ON polarity,
# NEVER auto-derived from a make-chip header or platform/common/out/ state; the
# two build-order traps in that header apply verbatim).
#
#   ON  (#ifdef CORE_ENABLE_ZKN): execute real aes32esi/aes32esmi encodings and
#       CHECK the architectural results -> PASS.
#   OFF (#else): the aes32esmi encoding executed UNCONDITIONALLY. On a build
#       without Zkn the OP funct5=10011/funct3=000 encoding MUST take the
#       illegal-instruction trap. run_extoff.sh + trap_watch.tcl report TRAP_OK;
#       executing PAST it -> FAIL. Wired ONLY into behavioral_mp_stripped/
#       run_extoff.sh (the a0-watch runner would hang on the terminal TRAP_STATE).
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

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity (runs on every build, like extprobe.S) ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, ekne_fail

#ifdef CORE_ENABLE_ZKN
    # =====================================================================
    # FEATURE ON: directed aes32esi/aes32esmi checks.
    # =====================================================================
    li   a1, 0xdeadbeef
    li   a2, 0x89abcdef
    AES32ESI(a3, a1, a2, 0)
    li   a4, 0xdeadbe30
    bne  a3, a4, ekne_fail

    AES32ESMI(a3, a1, a2, 0)
    li   a4, 0xa472614a
    bne  a3, a4, ekne_fail

    li   a1, 0x11223344
    AES32ESMI(a3, a1, a2, 1)
    li   a4, 0xac9f5298
    bne  a3, a4, ekne_fail

    RVTEST_PASS

#else
    # =====================================================================
    # FEATURE OFF (extoff POISON): aes32esmi MUST take the illegal-instr trap.
    # =====================================================================
    li   a1, 0xdeadbeef
    li   a2, 0x89abcdef
    AES32ESMI(a3, a1, a2, 0)     # illegal without Zkn — must trap
    j    ekne_fail               # reached only if it did NOT trap

#endif

ekne_fail:
    RVTEST_FAIL                  # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
