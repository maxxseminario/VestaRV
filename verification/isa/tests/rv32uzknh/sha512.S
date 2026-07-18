# See LICENSE for license details.
#*****************************************************************************
# rv32uzknh sha512.S — directed per-op tests for the Zknh SHA-512 sigma/sum
# half ops (ON-polarity suite; run only against a Zkn-ON MCU). Goldens from
# the ratified per-instruction shift formulas AND cross-checked to compose to
# the independent 64-bit ror64 SHA-512 sigma/sum definitions (see the X3
# self-report cross-check).
#*****************************************************************************
#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

.macro SHA512SIG0L rd,rs1,rs2 ; .insn r 0x33, 0x0, 0x2a, \rd, \rs1, \rs2 ; .endm
.macro SHA512SIG0H rd,rs1,rs2 ; .insn r 0x33, 0x0, 0x2e, \rd, \rs1, \rs2 ; .endm
.macro SHA512SIG1L rd,rs1,rs2 ; .insn r 0x33, 0x0, 0x2b, \rd, \rs1, \rs2 ; .endm
.macro SHA512SIG1H rd,rs1,rs2 ; .insn r 0x33, 0x0, 0x2f, \rd, \rs1, \rs2 ; .endm
.macro SHA512SUM0R rd,rs1,rs2 ; .insn r 0x33, 0x0, 0x28, \rd, \rs1, \rs2 ; .endm
.macro SHA512SUM1R rd,rs1,rs2 ; .insn r 0x33, 0x0, 0x29, \rd, \rs1, \rs2 ; .endm
.macro CK reg,val ; li t5, \val ; bne \reg, t5, fail ; .endm

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # --- per-op directed (rs1=0x01234567, rs2=0x89abcdef) ---
    li a3, 0x01234567
    li a4, 0x89abcdef
    SHA512SIG0L a2, a3, a4 ; CK a2, 0xb192c77c
    SHA512SIG0H a2, a3, a4 ; CK a2, 0x6f92c77c
    SHA512SIG1L a2, a3, a4 ; CK a2, 0xcca3460d
    SHA512SIG1H a2, a3, a4 ; CK a2, 0x70a3460d
    SHA512SUM0R a2, a3, a4 ; CK a2, 0xb7c57a10
    SHA512SUM1R a2, a3, a4 ; CK a2, 0x77031123

    # --- corner vectors (rs1=all-ones/rs2=0 and rs1=0/rs2=all-ones) ---
    li a3, 0xffffffff ; li a4, 0x00000000
    SHA512SIG0L a2, a3, a4 ; CK a2, 0x7effffff
    SHA512SIG1H a2, a3, a4 ; CK a2, 0xfc001ff8
    SHA512SUM0R a2, a3, a4 ; CK a2, 0x3e00000f
    li a3, 0x00000000 ; li a4, 0xffffffff
    SHA512SIG0H a2, a3, a4 ; CK a2, 0x7f000000
    SHA512SIG1L a2, a3, a4 ; CK a2, 0x03ffe007
    SHA512SUM1R a2, a3, a4 ; CK a2, 0x007c3fff

    # --- 64-bit KAT: X=0x0123456789abcdef, H=hi32,L=lo32; the instruction
    #     pairs must reconstruct the true 64-bit sigma/sum:
    #       Sigma0=6f92c77c6c4f1aa1  Sigma1=70a3460dbbd4317a
    #       Sum0  =b7c57a100c7ec1ab  Sum1  =7703112333475567
    li s0, 0x01234567   # H
    li s1, 0x89abcdef   # L
    SHA512SIG0H a2, s0, s1 ; CK a2, 0x6f92c77c
    SHA512SIG0L a2, s1, s0 ; CK a2, 0x6c4f1aa1
    SHA512SIG1H a2, s0, s1 ; CK a2, 0x70a3460d
    SHA512SIG1L a2, s1, s0 ; CK a2, 0xbbd4317a
    SHA512SUM0R a2, s0, s1 ; CK a2, 0xb7c57a10
    SHA512SUM0R a2, s1, s0 ; CK a2, 0x0c7ec1ab
    SHA512SUM1R a2, s0, s1 ; CK a2, 0x77031123
    SHA512SUM1R a2, s1, s0 ; CK a2, 0x33475567

    # rd aliases rs2 (in-place) hazard check
    li a3, 0x01234567 ; li a4, 0x89abcdef
    SHA512SUM0R a4, a3, a4 ; CK a4, 0xb7c57a10

    RVTEST_PASS
fail:
    RVTEST_FAIL
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
