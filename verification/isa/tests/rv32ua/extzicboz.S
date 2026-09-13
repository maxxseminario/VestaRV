# See LICENSE for license details.

# VestaRV: Zicboz extension probe
# BUILD-TIME DISPATCH on CORE_ENABLE_ZICBOZ, supplied EXPLICITLY with -DCORE_ENABLE_ZICBOZ when staging the ON polarity and never auto-derived from a generated header or build output. With it defined a real cbo.zero runs on a poisoned 64-byte block and all 16 words must read 0 while the words immediately BEFORE and AFTER the block are untouched, which is the boundary guard.
# Without it the cbo.zero encoding executes unconditionally and must take the illegal-instruction trap, since the MISC-MEM funct3 = 010, imm = 0x004 encoding is reserved when Zicboz is off; run_extoff.sh with trap_watch.tcl reports TRAP_OK, and executing past it is a FAIL. IT IS WIRED ONLY INTO behavioral_mp_stripped/run_extoff.sh, because the a0-watch runner would hang on the terminal TRAP_STATE.
# The illegal-sibling assertion, that cbo.clean, cbo.flush and cbo.inval always trap, lives in the companion terminal-trap poison cbozill.S, run under trap_watch on every build: this core's illegal-instruction trap is TERMINAL, so a recoverable in-test check is not possible.
# gas 2.41 DOES accept `-march=..._zicboz` and `.option arch, +zicboz` and assembles `cbo.zero (a1)` to 0x0045a00f. THE EXPLICIT `.insn` IS KEPT DELIBERATELY, because it is march-independent, so one source serves both polarities and the OFF arm can emit the encoding on a build whose -march has no zicboz. It encodes the identical word: cbo.zero rs1 is `.insn i 0x0f, 0x2, x0, rs1, 0x004`.

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
