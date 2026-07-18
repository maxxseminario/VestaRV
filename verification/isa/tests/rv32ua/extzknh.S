# See LICENSE for license details.

#*****************************************************************************
# extzknh.S   (ISA extension program, X3 Stage B — Zknh SHA-256/512)
#-----------------------------------------------------------------------------
# Ext-probe + KAT for the RV32 Zknh scalar-crypto instructions (ENABLE_ZKN):
#   sha256sig0/sig1/sum0/sum1  (OP-IMM unary)
#   sha512sig0l/h sig1l/h sum0r sum1r  (OP binary, RV32 64-bit halves)
#
# Build-time polarity dispatch on CORE_ENABLE_ZKN (extprobe_template idiom):
#   ON  (#ifdef, built with -DCORE_ENABLE_ZKN): execute every op, CHECK the
#        architectural result against goldens, run the SHA-256("abc") full-block
#        KAT + the SHA-512 64-bit-sigma/sum KAT, then PASS.
#   OFF (#else, default build): fall INTO a sha256 encoding — it MUST take the
#        illegal-instruction trap (the behavioral_mp_stripped/run_extoff.sh
#        harness reports TRAP_OK; surviving past it -> FAIL).
#
# Goldens are computed from INDEPENDENT references (standard SHA-256 ror/shr
# defs; independent 64-bit ror64 SHA-512 sigma/sum defs; the FIPS "abc" digest),
# so a wrong rotate/shift constant fails the test. See verification/isa/negctrl/
# x3_sha256_rotate_seed.patch (seed a wrong sig0 rotate -> the KAT FAILs).
#
# Encodings via .insn so the file assembles under the base -march (Zknh is not
# in gas 13.2's -march). norvc/norelax keeps fixed-width base + explicit encodings.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

# NOTE: CORE_ENABLE_ZKN is supplied EXPLICITLY via -DCORE_ENABLE_ZKN when
# building the ON polarity (see the header comment). We do NOT #include
# "MemoryMap.h" here -- the generated header pulls <stdint.h>/<bits.h>/
# <custom_ops.S>, which the assembler rejects (extzicond precedent).

.option norvc
.option norelax

# ---- Zknh encoding macros -------------------------------------------------
# SHA-256 (OP-IMM, funct3=001, funct12 = 0001000_<rs2field>)
.macro SHA256SIG0 rd,rs1 ; .insn i 0x13, 0x1, \rd, \rs1, 0x102 ; .endm
.macro SHA256SIG1 rd,rs1 ; .insn i 0x13, 0x1, \rd, \rs1, 0x103 ; .endm
.macro SHA256SUM0 rd,rs1 ; .insn i 0x13, 0x1, \rd, \rs1, 0x100 ; .endm
.macro SHA256SUM1 rd,rs1 ; .insn i 0x13, 0x1, \rd, \rs1, 0x101 ; .endm
# SHA-512 (OP, funct3=000, funct7 selects op)
.macro SHA512SIG0L rd,rs1,rs2 ; .insn r 0x33, 0x0, 0x2a, \rd, \rs1, \rs2 ; .endm
.macro SHA512SIG0H rd,rs1,rs2 ; .insn r 0x33, 0x0, 0x2e, \rd, \rs1, \rs2 ; .endm
.macro SHA512SIG1L rd,rs1,rs2 ; .insn r 0x33, 0x0, 0x2b, \rd, \rs1, \rs2 ; .endm
.macro SHA512SIG1H rd,rs1,rs2 ; .insn r 0x33, 0x0, 0x2f, \rd, \rs1, \rs2 ; .endm
.macro SHA512SUM0R rd,rs1,rs2 ; .insn r 0x33, 0x0, 0x28, \rd, \rs1, \rs2 ; .endm
.macro SHA512SUM1R rd,rs1,rs2 ; .insn r 0x33, 0x0, 0x29, \rd, \rs1, \rs2 ; .endm

# check a2 == imm32, else fail
.macro CK reg,val ; li t5, \val ; bne \reg, t5, extt_fail ; .endm

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity (runs on every build) ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, extt_fail

#ifdef CORE_ENABLE_ZKN
    # =====================================================================
    # FEATURE ON — directed per-op checks (a=0xdeadbeef; sha512 rs1=0x01234567,
    # rs2=0x89abcdef). Goldens from independent references.
    # =====================================================================
    # NOTE: a0/a1 (x10/x11) are the tb PASS/FAIL watch registers -- test inputs
    # go in a3/a4 so an input value never spuriously trips the tb's DEADBEEF/
    # CAFEBABE latch (0xdeadbeef as an input collides with the FAIL marker).
    li   a3, 0xdeadbeef
    SHA256SIG0 a2, a3 ; CK a2, 0xabd31b0b
    SHA256SIG1 a2, a3 ; CK a2, 0x689dbfec
    SHA256SUM0 a2, a3 ; CK a2, 0xb62e25ac
    SHA256SUM1 a2, a3 ; CK a2, 0x345e14a3

    li   a3, 0x01234567          # rs1
    li   a4, 0x89abcdef          # rs2
    SHA512SIG0L a2, a3, a4 ; CK a2, 0xb192c77c
    SHA512SIG0H a2, a3, a4 ; CK a2, 0x6f92c77c
    SHA512SIG1L a2, a3, a4 ; CK a2, 0xcca3460d
    SHA512SIG1H a2, a3, a4 ; CK a2, 0x70a3460d
    SHA512SUM0R a2, a3, a4 ; CK a2, 0xb7c57a10
    SHA512SUM1R a2, a3, a4 ; CK a2, 0x77031123

    # =====================================================================
    # SHA-512 64-bit KAT: for X = 0x0123456789abcdef split into H=hi32,L=lo32,
    # the instruction pairs must reconstruct the true 64-bit ror64 sigma/sum:
    #   Sigma0(X)=6f92c77c6c4f1aa1  Sigma1(X)=70a3460dbbd4317a
    #   Sum0(X)  =b7c57a100c7ec1ab  Sum1(X)  =7703112333475567
    #   lo = ins_l(L,H) / sumr(L,H) ; hi = ins_h(H,L) / sumr(H,L)
    # =====================================================================
    li   s0, 0x01234567          # H (hi 32)
    li   s1, 0x89abcdef          # L (lo 32)
    SHA512SIG0H a2, s0, s1 ; CK a2, 0x6f92c77c    # Sigma0 hi
    SHA512SIG0L a2, s1, s0 ; CK a2, 0x6c4f1aa1    # Sigma0 lo
    SHA512SIG1H a2, s0, s1 ; CK a2, 0x70a3460d    # Sigma1 hi
    SHA512SIG1L a2, s1, s0 ; CK a2, 0xbbd4317a    # Sigma1 lo
    SHA512SUM0R a2, s0, s1 ; CK a2, 0xb7c57a10    # Sum0 hi
    SHA512SUM0R a2, s1, s0 ; CK a2, 0x0c7ec1ab    # Sum0 lo
    SHA512SUM1R a2, s0, s1 ; CK a2, 0x77031123    # Sum1 hi
    SHA512SUM1R a2, s1, s0 ; CK a2, 0x33475567    # Sum1 lo

    # =====================================================================
    # SHA-256("abc") full-block KAT. Message schedule uses sha256sig0/sig1;
    # compression uses sha256sum0/sum1. Digest must equal the FIPS-180 vector
    #   ba7816bf 8f01cfea 414140de 5dae2223
    #   b00361a3 96177a9c b410ff61 f20015ad
    # =====================================================================
    la   s10, sha_w              # W[0..63] scratch (word buffer)
    la   s11, sha_k              # K[0..63]

    # --- init W[0..15] = padded "abc" block (W[0]=0x61626380, W[15]=0x18, rest 0)
    li   t0, 0
    addi t1, s10, 64             # &W[16]
1:  sw   zero, 0(s10)            # zero W[0..15] first (reuse s10 as running ptr)
    addi s10, s10, 4
    bne  s10, t1, 1b
    la   s10, sha_w
    li   t0, 0x61626380
    sw   t0, 0(s10)              # W[0]
    li   t0, 0x18
    sw   t0, 60(s10)             # W[15]

    # --- message schedule: W[t]=sig1(W[t-2])+W[t-7]+sig0(W[t-15])+W[t-16], t=16..63
    addi t6, s10, 64             # p = &W[16]
    addi t5, s10, 256            # end = &W[64]
2:  lw   t0, -8(t6)             # W[t-2]
    SHA256SIG1 t0, t0
    lw   t1, -28(t6)            # W[t-7]
    lw   t2, -60(t6)            # W[t-15]
    SHA256SIG0 t2, t2
    lw   t3, -64(t6)           # W[t-16]
    add  t0, t0, t1
    add  t2, t2, t3
    add  t0, t0, t2
    sw   t0, 0(t6)
    addi t6, t6, 4
    bne  t6, t5, 2b

    # --- compression. a..h = s0..s7 ; K/W indexed by s9 (byte offset).
    li   s0, 0x6a09e667          # a
    li   s1, 0xbb67ae85          # b
    li   s2, 0x3c6ef372          # c
    li   s3, 0xa54ff53a          # d
    li   s4, 0x510e527f          # e
    li   s5, 0x9b05688c          # f
    li   s6, 0x1f83d9ab          # g
    li   s7, 0x5be0cd19          # h
    li   s9, 0                   # t*4
3:  add  t0, s11, s9             # &K[t]
    lw   t0, 0(t0)               # K[t]
    add  t1, s10, s9             # &W[t]
    lw   t1, 0(t1)               # W[t]
    # T1 = h + sum1(e) + Ch(e,f,g) + K[t] + W[t]
    SHA256SUM1 t2, s4            # sum1(e)
    and  t3, s4, s5              # e & f
    not  t4, s4                  # ~e
    and  t4, t4, s6              # ~e & g
    xor  t3, t3, t4              # Ch
    add  t2, t2, s7              # + h
    add  t2, t2, t3              # + Ch
    add  t2, t2, t0              # + K[t]
    add  t2, t2, t1              # + W[t]   => T1 in t2
    # T2 = sum0(a) + Maj(a,b,c)
    SHA256SUM0 t3, s0            # sum0(a)
    and  t4, s0, s1              # a & b
    and  t0, s0, s2              # a & c
    xor  t4, t4, t0
    and  t0, s1, s2              # b & c
    xor  t4, t4, t0              # Maj
    add  t3, t3, t4              # T2 in t3
    # shift the working vars
    mv   s7, s6                  # h = g
    mv   s6, s5                  # g = f
    mv   s5, s4                  # f = e
    add  s4, s3, t2              # e = d + T1
    mv   s3, s2                  # d = c
    mv   s2, s1                  # c = b
    mv   s1, s0                  # b = a
    add  s0, t2, t3              # a = T1 + T2
    addi s9, s9, 4
    li   t5, 256
    bne  s9, t5, 3b

    # --- add working vars to the initial hash -> digest words
    li   t0, 0x6a09e667 ; add s0, s0, t0 ; CK s0, 0xba7816bf
    li   t0, 0xbb67ae85 ; add s1, s1, t0 ; CK s1, 0x8f01cfea
    li   t0, 0x3c6ef372 ; add s2, s2, t0 ; CK s2, 0x414140de
    li   t0, 0xa54ff53a ; add s3, s3, t0 ; CK s3, 0x5dae2223
    li   t0, 0x510e527f ; add s4, s4, t0 ; CK s4, 0xb00361a3
    li   t0, 0x9b05688c ; add s5, s5, t0 ; CK s5, 0x96177a9c
    li   t0, 0x1f83d9ab ; add s6, s6, t0 ; CK s6, 0xb410ff61
    li   t0, 0x5be0cd19 ; add s7, s7, t0 ; CK s7, 0xf20015ad

    RVTEST_PASS

#else
    # =====================================================================
    # FEATURE OFF: the sha256sig0 encoding MUST take the illegal-instr trap.
    # =====================================================================
    li   a3, 0xdeadbeef
    SHA256SIG0 a2, a3            # illegal here — trap expected
    j    extt_fail              # reached only if it did NOT trap
#endif

extt_fail:
    RVTEST_FAIL

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA

.balign 4
sha_k:
    .word 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5
    .word 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5
    .word 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3
    .word 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
    .word 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc
    .word 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da
    .word 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7
    .word 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967
    .word 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13
    .word 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85
    .word 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3
    .word 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070
    .word 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5
    .word 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3
    .word 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208
    .word 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2

.balign 4
sha_w:
    .fill 64, 4, 0

RVTEST_DATA_END
