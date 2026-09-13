# See LICENSE for license details.

# VestaRV: template for a Z-extension build-time probe
# TEMPLATE, NOT WIRED INTO ANY Makefrag OR RUNNER ARRAY. Copy it to a real test name and fill in the encoding and the result check for one extension; the body here is a worked example for Zicond czero.eqz and czero.nez.
# WHY BUILD-TIME DISPATCH: the Z-extensions have NO misa BIT, so the misa-branch idiom of extmul.S and extrvc.S cannot tell whether the chip was built with the extension. The generator emits `#define CORE_ENABLE_<EXT>` only when the generic is true, so `#ifdef` is the exact on/off test: present means built ON, absent means the encoding must trap.
# THE MACRO IS NEVER AUTO-DERIVED from an include path or from generated build state, because a stale header silently flips test arms. It is an EXPLICIT define appended to the compile options only when staging the ON polarity: the default build compiles the #else arm, and the ON build is `rm -rf build/ && make <suite>-flash RISCV_GCC_OPTS="... -DCORE_ENABLE_<EXT>"`.
# TWO BUILD-ORDER TRAPS, each of which has cost a false negative-control pass: build_mp_images.sh hardcodes its own RISCV_GCC_OPTS and DROPS any -DCORE_ENABLE_* from an earlier make, so base images must be built first and the ON suite rebuilt on top; and the simulator reads a directory that is normally a SYMLINK to verification/isa/rcf, which a fresh git worktree can materialise as a real stale directory instead, so check `ls -ld` before trusting a result and sanity-grep an ON-only encoding word in the rcf actually simulated.
# Runtime dispatch is the alternative where the OFF behaviour is observable without trapping, as in extzihpm.S, where one image serves both polarities. Encodings are emitted with `.insn` or `.word` so the file assembles under the suite's base -march, and whole-file norvc with norelax keeps the image fixed-width.

#include "riscv_test.h"
#include "test_macros.h"

# The generated Castalia header carrying CORE_ENABLE_<EXT> (see the include-path
# note above). A phase agent adds -I.../platform/common/out/software/include to
# this suite's flags; until then this include resolves to the Myshkin header,
# which lacks the Z-extension defines, so every arm below takes the OFF path.
#include "MemoryMap.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity (runs on every build, like extprobe.S) ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, extt_fail

#ifdef CORE_ENABLE_ZICOND
    # =====================================================================
    # FEATURE ON: execute the real encoding and CHECK the result -> PASS.
    # czero.eqz rd,rs1,rs2 : rd = (rs2==0) ? 0 : rs1   (OP 0110011, f3=101, f7=0000111)
    # czero.nez rd,rs1,rs2 : rd = (rs2!=0) ? 0 : rs1   (OP 0110011, f3=111, f7=0000111)
    # =====================================================================
    li   a0, 0xABCD1234          # rs1 payload

    # czero.eqz a2, a0, a1  with rs2==0  -> a2 = 0
    li   a1, 0
    .insn r 0x33, 0x5, 0x07, a2, a0, a1
    bnez a2, extt_fail
    # czero.eqz a2, a0, a1  with rs2!=0  -> a2 = a0
    li   a1, 1
    .insn r 0x33, 0x5, 0x07, a2, a0, a1
    bne  a2, a0, extt_fail

    # czero.nez a2, a0, a1  with rs2!=0  -> a2 = 0
    li   a1, 7
    .insn r 0x33, 0x7, 0x07, a2, a0, a1
    bnez a2, extt_fail
    # czero.nez a2, a0, a1  with rs2==0  -> a2 = a0
    li   a1, 0
    .insn r 0x33, 0x7, 0x07, a2, a0, a1
    bne  a2, a0, extt_fail

    RVTEST_PASS

#else
    # =====================================================================
    # FEATURE OFF: the same encoding MUST take the illegal-instruction trap.
    # Surviving PAST it means misa/decode/gating disagree -> explicit FAIL.
    # (The stripped-build harness watches trap_flag via trap_watch.tcl and
    #  reports TRAP_OK when the trap fires here.)
    # =====================================================================
    li   a0, 0xABCD1234
    li   a1, 0
    .insn r 0x33, 0x5, 0x07, a2, a0, a1   # czero.eqz — must be illegal here
    j    extt_fail                        # reached only if the encoding did NOT trap

#endif

extt_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
extt_scratch: .word 0
RVTEST_DATA_END
