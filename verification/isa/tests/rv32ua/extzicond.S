# See LICENSE for license details.

# VestaRV: Zicond extension probe
# BUILD-TIME DISPATCH on CORE_ENABLE_ZICOND, because Zicond has NO misa bit. The macro is passed EXPLICITLY with -D and never auto-derived from the gitignored generated header, since a stale header would silently compile the ON arm against OFF RTL and dead-end the trap. It also cannot come from #include "MemoryMap.h": that header unconditionally pulls in C typedefs the assembler rejects. ALWAYS `rm -rf build/` ON A POLARITY FLIP, so the -D tracks the RTL being simulated.
# The operations: `czero.eqz rd, rs1, rs2` gives rd = (rs2 == 0) ? 0 : rs1, encoded OP 0110011 with funct3 101 and funct7 0000111; `czero.nez rd, rs1, rs2` gives rd = (rs2 != 0) ? 0 : rs1, the same with funct3 111.
# With the macro defined the real encodings execute and every architectural result is checked. Without it the file does base-ISA sanity only and passes, and it DELIBERATELY DOES NOT EXECUTE A czero ENCODING: this core has no software trap recovery, so an illegal-instruction trap here would hang the 100 ms watchdog and turn the default suite red. The OFF-polarity trap is proven instead by running the ON-arm image against Zicond-OFF RTL under trap_watch.tcl.
# Encodings use `.insn` so the file assembles under the suite's base -march, which has no zicond, and norvc with norelax keeps the image fixed-width.

#include "riscv_test.h"
#include "test_macros.h"

# NOTE: CORE_ENABLE_ZICOND is supplied EXPLICITLY via -D when building the ON
# polarity (see the header comment). We do NOT #include "MemoryMap.h" here -- it
# is not assembly-includable.

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
    # FEATURE ON: execute the real encodings and CHECK the results -> PASS.
    # (a0 = rs1 payload throughout)
    # =====================================================================
    li   a0, 0xABCD1234

    # --- czero.eqz a2, a0, a1 ---
    # rs2 == 0  ->  a2 = 0
    li   a1, 0
    .insn r 0x33, 0x5, 0x07, a2, a0, a1
    bnez a2, extt_fail
    # rs2 != 0  ->  a2 = a0
    li   a1, 1
    .insn r 0x33, 0x5, 0x07, a2, a0, a1
    bne  a2, a0, extt_fail
    # rs2 = large nonzero (sign bit set) -> a2 = a0
    li   a1, 0xFFFFFFFF
    .insn r 0x33, 0x5, 0x07, a2, a0, a1
    bne  a2, a0, extt_fail

    # --- czero.nez a2, a0, a1 ---
    # rs2 != 0  ->  a2 = 0
    li   a1, 7
    .insn r 0x33, 0x7, 0x07, a2, a0, a1
    bnez a2, extt_fail
    # rs2 == 0  ->  a2 = a0
    li   a1, 0
    .insn r 0x33, 0x7, 0x07, a2, a0, a1
    bne  a2, a0, extt_fail
    # rs2 = large nonzero -> a2 = 0
    li   a1, 0x80000000
    .insn r 0x33, 0x7, 0x07, a2, a0, a1
    bnez a2, extt_fail

    # --- rs1 = 0 edge: result is 0 in every case ---
    li   a0, 0
    li   a1, 0
    .insn r 0x33, 0x5, 0x07, a2, a0, a1   # czero.eqz: rs2==0 -> 0
    bnez a2, extt_fail
    li   a1, 5
    .insn r 0x33, 0x7, 0x07, a2, a0, a1   # czero.nez: rs2!=0 -> 0
    bnez a2, extt_fail

    # --- rd == rs1 (in-place) sanity: czero.nez t2,t2,x0 keeps t2 ---
    li   t2, 0x0000BEEF
    .insn r 0x33, 0x7, 0x07, t2, t2, x0   # rs2==0 -> t2 unchanged
    li   t3, 0x0000BEEF
    bne  t2, t3, extt_fail

    RVTEST_PASS

#else
    # =====================================================================
    # FEATURE OFF: base ISA already validated above. Do NOT execute a czero
    # encoding here (trapless core would hang the watchdog; see header).
    # =====================================================================
    RVTEST_PASS
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
