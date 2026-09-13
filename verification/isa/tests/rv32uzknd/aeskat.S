# See LICENSE for license details.

# VestaRV: AES-128 known-answer test over the scalar-crypto instructions
# ON-POLARITY ONLY, built with -DCORE_ENABLE_ZKN. It encrypts AND decrypts the FIPS-197 Appendix B and C.1 vector with the aes32e* and aes32d* instructions and asserts both the ciphertext and the recovered plaintext against the published constants: key 2b7e151628aed2a6abf7158809cf4f3c, plaintext 3243f6a8885a308d313198a2e0370734, ciphertext 3925841d02dc09fbdc118597196a0b32.
# THE ROUND KEYS ARE PRECOMPUTED AND BAKED IN AS .word DATA, both the encrypt schedule and the inverse-cipher schedule, so the test contains NO software key expansion and no software InvMixColumns and exercises only the aes32* datapath. The values are validated by a host golden model that mirrors the ALU's AES datapath exactly and reproduces the FIPS-197 constants.
# Word j of a 16-byte block or key is the little-endian load of bytes 4j through 4j+3. An encrypt round column is the round key XORed with esmi over the ShiftRows-selected state bytes at byte selects 0 to 3, with the final round using esi; a decrypt column is the inverse-cipher round key XORed with dsmi over the InvShiftRows-selected bytes, with the final round using dsi and the original key.
# gas 13.2 has neither the aes32* mnemonics nor a zkn -march token, so every operation is an explicit `.insn` R-type with OP 0x33, funct3 = 0 and funct7 = (bs << 5) | fn5, where fn5 is 0x11 for esi, 0x13 for esmi, 0x15 for dsi and 0x17 for dsmi, and rd = rs1 XOR f(rs2, bs).

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define AES32ESI(rd,rs1,rs2,bs)  .insn r 0x33, 0x0, (0x11|((bs)<<5)), rd, rs1, rs2
#define AES32ESMI(rd,rs1,rs2,bs) .insn r 0x33, 0x0, (0x13|((bs)<<5)), rd, rs1, rs2
#define AES32DSI(rd,rs1,rs2,bs)  .insn r 0x33, 0x0, (0x15|((bs)<<5)), rd, rs1, rs2
#define AES32DSMI(rd,rs1,rs2,bs) .insn r 0x33, 0x0, (0x17|((bs)<<5)), rd, rs1, rs2

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity (runs on every build, like extprobe.S) ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, kat_fail

    # =====================================================================
    # ENCRYPT: state s2..s5 = plaintext XOR ek0 ; 9 esmi rounds ; esi final.
    # =====================================================================
    la    a4, aes_pt
    la    a3, aes_ek
    lw    s2, 0(a3); lw s3, 4(a3); lw s4, 8(a3); lw s5, 12(a3)   # ek0
    lw    t4, 0(a4); xor s2, s2, t4
    lw    t4, 4(a4); xor s3, s3, t4
    lw    t4, 8(a4); xor s4, s4, t4
    lw    t4,12(a4); xor s5, s5, t4
    addi  a3, a3, 16                 # -> ek1
    li    a5, 9
enc_loop:
    lw    t0, 0(a3); lw t1, 4(a3); lw t2, 8(a3); lw t3, 12(a3)   # round key -> n
    AES32ESMI(t0,t0,s2,0); AES32ESMI(t0,t0,s3,1); AES32ESMI(t0,t0,s4,2); AES32ESMI(t0,t0,s5,3)
    AES32ESMI(t1,t1,s3,0); AES32ESMI(t1,t1,s4,1); AES32ESMI(t1,t1,s5,2); AES32ESMI(t1,t1,s2,3)
    AES32ESMI(t2,t2,s4,0); AES32ESMI(t2,t2,s5,1); AES32ESMI(t2,t2,s2,2); AES32ESMI(t2,t2,s3,3)
    AES32ESMI(t3,t3,s5,0); AES32ESMI(t3,t3,s2,1); AES32ESMI(t3,t3,s3,2); AES32ESMI(t3,t3,s4,3)
    mv    s2, t0; mv s3, t1; mv s4, t2; mv s5, t3
    addi  a3, a3, 16
    addi  a5, a5, -1
    bnez  a5, enc_loop
    # final round (ek10 at a3): esi (SubBytes+ShiftRows, no MixColumns)
    lw    t0, 0(a3); lw t1, 4(a3); lw t2, 8(a3); lw t3, 12(a3)
    AES32ESI(t0,t0,s2,0); AES32ESI(t0,t0,s3,1); AES32ESI(t0,t0,s4,2); AES32ESI(t0,t0,s5,3)
    AES32ESI(t1,t1,s3,0); AES32ESI(t1,t1,s4,1); AES32ESI(t1,t1,s5,2); AES32ESI(t1,t1,s2,3)
    AES32ESI(t2,t2,s4,0); AES32ESI(t2,t2,s5,1); AES32ESI(t2,t2,s2,2); AES32ESI(t2,t2,s3,3)
    AES32ESI(t3,t3,s5,0); AES32ESI(t3,t3,s2,1); AES32ESI(t3,t3,s3,2); AES32ESI(t3,t3,s4,3)
    la    a4, aes_ct
    lw    t4, 0(a4); bne t0, t4, kat_fail
    lw    t4, 4(a4); bne t1, t4, kat_fail
    lw    t4, 8(a4); bne t2, t4, kat_fail
    lw    t4,12(a4); bne t3, t4, kat_fail

    # =====================================================================
    # DECRYPT: state = ciphertext XOR ek10 ; 9 dsmi rounds (dw9..dw1) ; dsi
    # final with ek0. Recovers the plaintext.
    # =====================================================================
    la    a4, aes_ct
    la    a3, aes_ek
    addi  a3, a3, 160                # -> ek10 (40 words = 160 B)
    lw    s2, 0(a3); lw s3, 4(a3); lw s4, 8(a3); lw s5, 12(a3)   # ek10
    lw    t4, 0(a4); xor s2, s2, t4
    lw    t4, 4(a4); xor s3, s3, t4
    lw    t4, 8(a4); xor s4, s4, t4
    lw    t4,12(a4); xor s5, s5, t4
    la    a3, aes_dw
    addi  a3, a3, 128                # -> dw9 (dw index 8 = 8*16 B)
    li    a5, 9
dec_loop:
    lw    t0, 0(a3); lw t1, 4(a3); lw t2, 8(a3); lw t3, 12(a3)   # dw[r] -> n
    AES32DSMI(t0,t0,s2,0); AES32DSMI(t0,t0,s5,1); AES32DSMI(t0,t0,s4,2); AES32DSMI(t0,t0,s3,3)
    AES32DSMI(t1,t1,s3,0); AES32DSMI(t1,t1,s2,1); AES32DSMI(t1,t1,s5,2); AES32DSMI(t1,t1,s4,3)
    AES32DSMI(t2,t2,s4,0); AES32DSMI(t2,t2,s3,1); AES32DSMI(t2,t2,s2,2); AES32DSMI(t2,t2,s5,3)
    AES32DSMI(t3,t3,s5,0); AES32DSMI(t3,t3,s4,1); AES32DSMI(t3,t3,s3,2); AES32DSMI(t3,t3,s2,3)
    mv    s2, t0; mv s3, t1; mv s4, t2; mv s5, t3
    addi  a3, a3, -16
    addi  a5, a5, -1
    bnez  a5, dec_loop
    # final round: ek0, dsi (InvSubBytes+InvShiftRows, no InvMixColumns)
    la    a3, aes_ek
    lw    t0, 0(a3); lw t1, 4(a3); lw t2, 8(a3); lw t3, 12(a3)
    AES32DSI(t0,t0,s2,0); AES32DSI(t0,t0,s5,1); AES32DSI(t0,t0,s4,2); AES32DSI(t0,t0,s3,3)
    AES32DSI(t1,t1,s3,0); AES32DSI(t1,t1,s2,1); AES32DSI(t1,t1,s5,2); AES32DSI(t1,t1,s4,3)
    AES32DSI(t2,t2,s4,0); AES32DSI(t2,t2,s3,1); AES32DSI(t2,t2,s2,2); AES32DSI(t2,t2,s5,3)
    AES32DSI(t3,t3,s5,0); AES32DSI(t3,t3,s4,1); AES32DSI(t3,t3,s3,2); AES32DSI(t3,t3,s2,3)
    la    a4, aes_pt
    lw    t4, 0(a4); bne t0, t4, kat_fail
    lw    t4, 4(a4); bne t1, t4, kat_fail
    lw    t4, 8(a4); bne t2, t4, kat_fail
    lw    t4,12(a4); bne t3, t4, kat_fail

    RVTEST_PASS

kat_fail:
    RVTEST_FAIL                      # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .align 2
# FIPS-197 plaintext / ciphertext (word j = little-endian bytes 4j..4j+3)
aes_pt: .word 0xa8f64332, 0x8d305a88, 0xa2983131, 0x340737e0
aes_ct: .word 0x1d842539, 0xfb09dc02, 0x978511dc, 0x320b6a19
# Encrypt round keys ek0..ek10
aes_ek:
    .word 0x16157e2b, 0xa6d2ae28, 0x8815f7ab, 0x3c4fcf09
    .word 0x17fefaa0, 0xb12c5488, 0x3939a323, 0x05766c2a
    .word 0xf295c2f2, 0x43b9967a, 0x7a803559, 0x7ff65973
    .word 0x7d47803d, 0x3efe1647, 0x447e231e, 0x3b887a6d
    .word 0x41a544ef, 0x7f5b52a8, 0x3b2571b6, 0x00ad0bdb
    .word 0xf8c6d1d4, 0x879d837c, 0xbcb8f2ca, 0xbc15f911
    .word 0x7aa3886d, 0xfd3e0b11, 0x4186f9db, 0xfd9300ca
    .word 0x0ef7544e, 0xf3c95f5f, 0xb24fa684, 0x4fdca64e
    .word 0x2173d2ea, 0xd2ba8db5, 0x60f52b31, 0x2f298d7f
    .word 0xf36677ac, 0x21dcfa19, 0x4129d128, 0x6e005c57
    .word 0xa8f914d0, 0x8925eec9, 0xc80c3fe1, 0xa60c63b6
# Decrypt keys dw1..dw9 = InvMixColumns(w[round])
aes_dw:
    .word 0xa708372b, 0x05d462f2, 0xbfbd3ebc, 0x627d614b
    .word 0xeb0575cc, 0xeed1173e, 0x516c2982, 0x331148c9
    .word 0xf7131f7c, 0x19c20842, 0x48ae21c0, 0x7bbf6909
    .word 0x13448890, 0x0a8680d2, 0x4228a112, 0x3997c81b
    .word 0xfc0aa36e, 0xf68c23bc, 0xb4a482ae, 0x8d334ab5
    .word 0x76d8fc6e, 0x8054dfd2, 0x34f05d7c, 0xb9c317c9
    .word 0x4776c012, 0xc7221fc0, 0xf3d242bc, 0x4a115575
    .word 0x5a927ddf, 0x9db0621f, 0x6e6220a3, 0x247375d6
    .word 0x635a7b0c, 0xfeea1913, 0x908839b0, 0xb4fb4c66
RVTEST_DATA_END
