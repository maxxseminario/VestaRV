# See LICENSE for license details.

# VestaRV: C-extension adaptive probe
# The file is built norvc, so the ONLY compressed encodings in the image are the two hand-emitted .half words below. It dispatches on misa.C, bit 2, which follows ENABLE_COMPRESSED: with C advertised the raw c.li pair executes and its result is verified, and with C absent fetching the first 16-bit encoding must take the illegal-instruction trap, since c_dec is generated away and instr_decomp is tied to the all-zeros illegal opcode. See extprobe.S for the group contract.

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr t0, misa
    .option pop
    srli t1, t0, 2
    andi t1, t1, 1
    beqz t1, extrvc_expect_trap

    # C advertised: execute two raw compressed instructions (word-aligned pair
    # so the surrounding 32-bit stream stays aligned)
    li   a1, 0
    .align 2
    .half 0x4585                # c.li a1, 1
    .half 0x0001                # c.nop
    li   t3, 1
    bne  a1, t3, extrvc_fail

    RVTEST_PASS

extrvc_expect_trap:
    # C not advertised: this 16-bit encoding must trap. If the core somehow
    # decodes past the pair, the branch lands on the FAIL path.
    li   a1, 0
    .align 2
    .half 0x4585                # c.li a1, 1 — must trap with C disabled
    .half 0x0001                # c.nop
    j    extrvc_fail

extrvc_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
