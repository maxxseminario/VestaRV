# See LICENSE for license details.

# VestaRV: Zknd extension probe
# BUILD-TIME DISPATCH on CORE_ENABLE_ZKN, supplied EXPLICITLY with -DCORE_ENABLE_ZKN when staging the ON polarity and never auto-derived from a generated header or build output. With it defined, the real aes32dsi and aes32dsmi encodings execute and their results are checked. Without it the aes32dsmi encoding executes unconditionally and the OP funct5 = 10111, funct3 = 000 encoding must take the illegal-instruction trap; run_extoff.sh with trap_watch.tcl reports TRAP_OK, and executing past it is a FAIL. IT IS WIRED ONLY INTO behavioral_mp_stripped/run_extoff.sh.
# gas 13.2 has no aes32* mnemonic, so every operation is an explicit `.insn` R-type with OP 0x33, funct3 = 0 and funct7 = (bs << 5) | fn5, where fn5 is 0x15 for dsi and 0x17 for dsmi.

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define AES32DSI(rd,rs1,rs2,bs)  .insn r 0x33, 0x0, (0x15|((bs)<<5)), rd, rs1, rs2
#define AES32DSMI(rd,rs1,rs2,bs) .insn r 0x33, 0x0, (0x17|((bs)<<5)), rd, rs1, rs2

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity (runs on every build, like extprobe.S) ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, eknd_fail

#ifdef CORE_ENABLE_ZKN
    # =====================================================================
    # FEATURE ON: directed aes32dsi/aes32dsmi checks.
    # =====================================================================
    li   a1, 0xdeadbeef
    li   a2, 0x89abcdef
    AES32DSI(a3, a1, a2, 0)
    li   a4, 0xdeadbe8e
    bne  a3, a4, eknd_fail

    AES32DSMI(a3, a1, a2, 0)
    li   a4, 0x5876fa97
    bne  a3, a4, eknd_fail

    li   a1, 0x11223344
    AES32DSMI(a3, a1, a2, 1)
    li   a4, 0xcbce72b3
    bne  a3, a4, eknd_fail

    RVTEST_PASS

#else
    # =====================================================================
    # FEATURE OFF (extoff POISON): aes32dsmi MUST take the illegal-instr trap.
    # =====================================================================
    li   a1, 0xdeadbeef
    li   a2, 0x89abcdef
    AES32DSMI(a3, a1, a2, 0)     # illegal without Zkn — must trap
    j    eknd_fail               # reached only if it did NOT trap

#endif

eknd_fail:
    RVTEST_FAIL                  # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
