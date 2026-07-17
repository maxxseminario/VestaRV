# See LICENSE for license details.

#*****************************************************************************
# extzicond.S   (X1 Zicond ext-probe; derived from extprobe_template.S)
#-----------------------------------------------------------------------------
# Build-time-adaptive probe for the Zicond conditional-zero ops. Zicond has NO
# misa bit, so this dispatches at BUILD TIME on the CORE_ENABLE_ZICOND macro.
# (The generated Castalia MemoryMap.h carries a matching #define, but it CANNOT
# be #included from an assembly test -- it unconditionally pulls <stdint.h>/
# <bits.h>/<custom_ops.S>, whose C typedefs the assembler rejects; the
# extprobe_template's "#include MemoryMap.h" idiom does not work for this header.)
#
# The macro is passed EXPLICITLY via -D, never auto-derived from the gitignored
# make-chip header (a stale header would silently compile the ON arm against OFF
# RTL and dead-end the trap). Convention:
#   * DEFAULT (zicond OFF) build: compile with NO -D -> OFF arm.
#         cd verification/isa && rm -rf build/ && make rv32ua-flash   # (or build_mp_images.sh)
#   * ON (zicond) build: stage the ON MemoryMap.vhd, then rebuild images with
#     -DCORE_ENABLE_ZICOND explicitly appended to RISCV_GCC_OPTS -> ON arm:
#         cd verification/isa && rm -rf build/ && \
#         make rv32ua-flash RISCV_GCC_OPTS="-static -mcmodel=medany \
#             -fvisibility=hidden -nostdlib -nostartfiles -DNHARTS=4 \
#             -DCORE_ENABLE_ZICOND"
#   Always `rm -rf build/` on a polarity flip (shared-header/opts dep) so the -D
#   tracks the RTL being simulated.
#
#   czero.eqz rd,rs1,rs2 : rd = (rs2==0) ? 0 : rs1   (OP 0110011, f3=101, f7=0000111)
#   czero.nez rd,rs1,rs2 : rd = (rs2!=0) ? 0 : rs1   (OP 0110011, f3=111, f7=0000111)
#
# ON arm  (#ifdef CORE_ENABLE_ZICOND): execute the real encodings, CHECK every
#   architectural result, RVTEST_PASS.
# OFF arm (#else): base-ISA sanity only, then RVTEST_PASS. It deliberately does
#   NOT execute a czero encoding: this core has NO software trap recovery
#   (vesta TRAP_STATE is terminal, trap_flag latched high, PC frozen), so an
#   illegal-instruction trap here would hang riscv_tb's 100 ms watchdog and
#   turn the DEFAULT (zicond-off) behavioral_mp suite RED. The OFF-polarity
#   illegal-instruction trap is proven instead by running the ON-arm image
#   (czero executes) against the zicond-OFF RTL under trap_watch.tcl -> TRAP_OK
#   (see the X1-zicond self-report / negctrl notes).
#
# Encodings use `.insn` so the file assembles under the suite's base
# -march=rv32imac (zicond is NOT in -march). norvc/norelax = fixed-width image.
#*****************************************************************************

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
