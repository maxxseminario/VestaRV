# See LICENSE for license details.

#*****************************************************************************
# extprobe.S  (core-features work, 2026-07-08)
#-----------------------------------------------------------------------------
# Base-ISA + misa probe — the POSITIVE control of the configurable-extension
# (ENABLE_MUL/DIV/ATOMICS/COMPRESSED/BITMANIP generic) test group. Built
# whole-file `.option norvc`/`norelax` so the image contains ONLY 32-bit
# base-ISA encodings and runs on ANY core configuration, including a chip
# with every extension stripped:
#   * exercises RV32I arithmetic, branches, and a load/store round trip
#   * reads misa (new read-only CSR 0x301) and requires MXL=01 (RV32) + I
# PASSES on every build. Its five extoff siblings (extmul/extdiv/extamo/
# extrvc/extzb) share this skeleton and dispatch on the misa extension bits:
# extension advertised -> execute it and check results -> PASS; extension
# absent -> fall INTO the instruction, which must take the illegal-instruction
# trap (observed as trap_flag by the stripped-build harness; surviving it is
# an explicit FAIL).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity: arithmetic + branches ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, extprobe_fail
    sub  t2, t3, t1
    bne  t2, t0, extprobe_fail
    slli t2, t0, 4
    srli t2, t2, 4
    bne  t2, t0, extprobe_fail

    # ---- base-ISA sanity: load/store round trip (private TCM .data) ----
    la   t4, extprobe_scratch
    li   t5, 0x5CA1AB1E
    sw   t5, 0(t4)
    lw   t6, 0(t4)
    bne  t6, t5, extprobe_fail

    # ---- misa: MXL must read 01 (RV32) and I (bit 8) must be set ----
    .option push
    .option arch, +zicsr
    csrr t0, misa
    .option pop
    srli t1, t0, 30
    li   t2, 1
    bne  t1, t2, extprobe_fail  # MXL != 01
    srli t1, t0, 8
    andi t1, t1, 1
    beqz t1, extprobe_fail      # I letter missing

    RVTEST_PASS

extprobe_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
extprobe_scratch: .word 0
RVTEST_DATA_END
