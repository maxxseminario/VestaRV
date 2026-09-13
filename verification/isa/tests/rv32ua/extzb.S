# See LICENSE for license details.

# VestaRV: bit-manipulation adaptive probe
# Dispatches on misa.B, bit 1, which follows ENABLE_BITMANIP; the ratified B letter is Zba, Zbb and Zbs, all carried by that one switch. The rv32ua -march has no Zb*, so SH1ADD is hand-encoded as `.word 0x2062A3B3`, which is `sh1add t2, t0, t1` with funct7 0010000 and funct3 010. With B advertised it must compute (t0 << 1) + t1; with B absent the encoding must take the illegal-instruction trap, since the R-type funct7 whitelist is strict when Zb* is off. See extprobe.S for the group contract.

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
    srli t1, t0, 1
    andi t1, t1, 1
    beqz t1, extzb_expect_trap

    # B advertised: SH1ADD must work
    li   t0, 3
    li   t1, 10
    .word 0x2062A3B3            # sh1add t2, t0, t1 -> (3<<1)+10 = 16
    li   t3, 16
    bne  t2, t3, extzb_fail

    RVTEST_PASS

extzb_expect_trap:
    # B not advertised: this SH1ADD encoding must trap. Surviving it =
    # misa/decode disagree.
    li   t0, 3
    li   t1, 10
    .word 0x2062A3B3            # sh1add t2, t0, t1 — must trap with Zb* off
    j    extzb_fail

extzb_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
