# See LICENSE for license details.
#*****************************************************************************
# rv32uzknh sha256.S — directed per-op tests for the Zknh SHA-256 sigma/sum
# ops (ON-polarity suite; run only against a Zkn-ON MCU). Goldens computed
# from the independent standard SHA-256 ror/shr definitions.
#*****************************************************************************
#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

.macro SHA256SIG0 rd,rs1 ; .insn i 0x13, 0x1, \rd, \rs1, 0x102 ; .endm
.macro SHA256SIG1 rd,rs1 ; .insn i 0x13, 0x1, \rd, \rs1, 0x103 ; .endm
.macro SHA256SUM0 rd,rs1 ; .insn i 0x13, 0x1, \rd, \rs1, 0x100 ; .endm
.macro SHA256SUM1 rd,rs1 ; .insn i 0x13, 0x1, \rd, \rs1, 0x101 ; .endm
.macro CK reg,val ; li t5, \val ; bne \reg, t5, fail ; .endm
# one-vector block: a0=input; e0..e3 = sig0,sig1,sum0,sum1 goldens
.macro VEC in,g0,g1,g2,g3
    li a3, \in
    SHA256SIG0 a2, a3 ; CK a2, \g0
    SHA256SIG1 a2, a3 ; CK a2, \g1
    SHA256SUM0 a2, a3 ; CK a2, \g2
    SHA256SUM1 a2, a3 ; CK a2, \g3
.endm

RVTEST_RV32U
RVTEST_CODE_BEGIN

    VEC 0xdeadbeef, 0xabd31b0b, 0x689dbfec, 0xb62e25ac, 0x345e14a3
    VEC 0x00000001, 0x02004000, 0x0000a000, 0x40080400, 0x04200080
    VEC 0xffffffff, 0x1fffffff, 0x003fffff, 0xffffffff, 0xffffffff
    VEC 0x12345678, 0xe7fce6ee, 0xa1f78649, 0x66146474, 0x3561abda

    # rd == rs1 (in-place) must still be correct (write-after-read hazard check)
    li  a3, 0x12345678
    SHA256SIG0 a3, a3 ; CK a3, 0xe7fce6ee

    RVTEST_PASS
fail:
    RVTEST_FAIL
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
