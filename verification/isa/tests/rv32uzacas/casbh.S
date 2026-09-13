# See LICENSE for license details.

# VestaRV: Zacas sub-word compare-and-swap directed suite
# ON-POLARITY ONLY. SUB-WORD CAS IS LEGAL ONLY WHEN BOTH Zacas AND Zabha ARE BUILT, because it rides Zabha's byte-lane machinery, so this test is simulated on an MCU with both on. gas 13.2 has no amocas mnemonic, so the encodings are explicit `.insn` R-types with funct5 00101 shifted into funct7, funct3 000 for the byte form and 001 for the half form.
# The sub-word semantics: compare the addressed sub-word, sign-extending BOTH the old memory sub-word and rd's low sub-word, since equality is extension-invariant; rd takes the sign-extended old sub-word, as on the Zabha load path; and on a match the addressed lane takes rs2's low sub-word while the adjacent lanes are untouched.
# Coverage is both compare outcomes crossed with lane placement, all four byte lanes and both halves, plus sign-extension of rd, adjacent-lane guards, and the sub-word aliasing cases, rd == rs1 for the lane-select regression and rd == rs2 for the operand regression, with the stale-compare class covered through the failing arms.

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define AMOCAS_B(rd,rs1,rs2)  .insn r 0x2f, 0x0, 0x14, rd, rs1, rs2
#define AMOCAS_H(rd,rs1,rs2)  .insn r 0x2f, 0x1, 0x14, rd, rs1, rs2

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, cbt_fail

    # =====================================================================
    # 1. amocas.b lane 0, SUCCESS: rd<-sext(old byte); only byte0 written
    # =====================================================================
    la   a1, cb_word
    li   t0, 0x44332211
    sw   t0, 0(a1)
    li   a2, 0x11                 # rd low byte = compare (== mem byte0)
    li   a3, 0xAA                 # rs2 low byte = swap value
    AMOCAS_B(a2, a1, a3)          # match ; byte0<-0xAA ; a2<-sext(0x11)=0x11
    li   t1, 0x00000011
    bne  a2, t1, cbt_fail
    lw   a4, 0(a1)
    li   t1, 0x443322AA           # only byte0 changed
    bne  a4, t1, cbt_fail

    # =====================================================================
    # 2. amocas.b lane 0, FAIL (stale-compare detector): mem unchanged
    # =====================================================================
    la   a1, cb_word
    li   t0, 0x44332211
    sw   t0, 0(a1)
    li   a2, 0x99                 # rd low byte != mem byte0 (0x11)
    li   a3, 0xAA                 # rs2 (must NOT be written)
    AMOCAS_B(a2, a1, a3)          # mismatch ; mem stays ; a2<-sext(0x11)=0x11
    li   t1, 0x00000011
    bne  a2, t1, cbt_fail
    lw   a4, 0(a1)
    li   t1, 0x44332211           # untouched
    bne  a4, t1, cbt_fail

    # =====================================================================
    # 3. amocas.b lane 3, NEGATIVE old byte -> rd sign-extended; SUCCESS
    # =====================================================================
    la   a1, cb_word
    li   t0, 0x80332211
    sw   t0, 0(a1)
    addi a1, a1, 3                # address byte 3 (0x80)
    li   a2, 0x80                 # rd low byte = compare (matches byte3 sub-word)
    li   a3, 0x7E                 # rs2 low byte = swap
    AMOCAS_B(a2, a1, a3)          # match ; byte3<-0x7E ; a2<-sext(0x80)=0xFFFFFF80
    li   t1, 0xFFFFFF80
    bne  a2, t1, cbt_fail
    la   a1, cb_word
    lw   a4, 0(a1)
    li   t1, 0x7E332211           # only byte3 changed, adjacent lanes intact
    bne  a4, t1, cbt_fail

    # =====================================================================
    # 4. amocas.h low half, SUCCESS: rd<-sext(old half); only low half written
    # =====================================================================
    la   a1, cb_word
    li   t0, 0x12348000
    sw   t0, 0(a1)               # half0=0x8000, half1=0x1234
    li   a2, 0x8000             # rd low half = compare (== mem half0)
    li   a3, 0x0BAD            # rs2 low half = swap
    AMOCAS_H(a2, a1, a3)         # match ; half0<-0x0BAD ; a2<-sext(0x8000)=0xFFFF8000
    li   t1, 0xFFFF8000
    bne  a2, t1, cbt_fail
    lw   a4, 0(a1)
    li   t1, 0x12340BAD          # high half untouched
    bne  a4, t1, cbt_fail

    # =====================================================================
    # 5. amocas.h HIGH half (addr+2), FAIL: mem + low half unchanged
    # =====================================================================
    la   a1, cb_word
    li   t0, 0x11112222
    sw   t0, 0(a1)
    addi a1, a1, 2               # high half (0x1111)
    li   a2, 0x2222            # rd low half != mem half1 (0x1111)
    li   a3, 0xF00D           # rs2 (must NOT be written)
    AMOCAS_H(a2, a1, a3)         # mismatch ; mem stays ; a2<-sext(0x1111)=0x00001111
    li   t1, 0x00001111
    bne  a2, t1, cbt_fail
    la   a1, cb_word
    lw   a4, 0(a1)
    li   t1, 0x11112222          # unchanged (both halves)
    bne  a4, t1, cbt_fail

    # =====================================================================
    # 6. amocas.h HIGH half, SUCCESS: only high half written
    # =====================================================================
    la   a1, cb_word
    li   t0, 0x11112222
    sw   t0, 0(a1)
    addi a1, a1, 2
    li   a2, 0x1111            # compare == mem half1
    li   a3, 0xF00D           # swap
    AMOCAS_H(a2, a1, a3)         # match ; half1<-0xF00D ; a2<-sext(0x1111)=0x1111
    li   t1, 0x00001111
    bne  a2, t1, cbt_fail
    la   a1, cb_word
    lw   a4, 0(a1)
    li   t1, 0xF00D2222          # only high half changed
    bne  a4, t1, cbt_fail

    # =====================================================================
    # 7. ALIAS rd==rs1 (F1 regression): lane select from the REGISTERED addr.
    #    a2 = byte-1 address; rd low byte = (address & 0xFF). Store that byte
    #    into mem lane 1 so the compare matches; success writes rs2 to lane 1.
    #    The buggy F1 RTL keys the lane off the clobbered rd (old byte) and
    #    picks the wrong lane -> adjacent-lane guard mismatch.
    # =====================================================================
    la   a1, cb_word
    li   t0, 0xAABBCCDD          # b3=AA b2=BB b1=CC b0=DD
    sw   t0, 0(a1)
    addi a2, a1, 1              # a2 = &cb_word+1 (lane 1) AND rd (alias rd==rs1)
    andi t3, a2, 0xFF          # low byte of the address
    sb   t3, 1(a1)             # mem lane1 <- (address & 0xFF) so the compare matches
    li   a3, 0x77              # rs2 low byte = swap
    AMOCAS_B(a2, a2, a3)       # match ; lane1<-0x77 ; a2<-sext(old lane1)
    slli t5, t3, 24
    srai t5, t5, 24            # sext(address low byte) as a signed byte
    bne  a2, t5, cbt_fail      # rd = sext(old lane1) = sext(addr&0xFF)
    la   a1, cb_word
    lw   a4, 0(a1)
    li   t1, 0xAABB77DD        # ONLY lane1 written: b1 CC->t3->0x77 (F1 wrong lane -> mismatch)
    bne  a4, t1, cbt_fail

    # =====================================================================
    # 8. ALIAS rd==rs2 (F2 regression), amocas.b SUCCESS: compare and swap
    #    are the same register. mem byte0 == a2 low byte -> match -> byte0
    #    <- a2 low byte (same); rd <- sext(old byte).
    # =====================================================================
    la   a1, cb_word
    li   t0, 0x00000042
    sw   t0, 0(a1)
    li   a2, 0x42              # rd == rs2 == compare == swap (low byte)
    AMOCAS_B(a2, a1, a2)       # match ; byte0<-0x42 ; a2<-sext(0x42)=0x42
    li   t1, 0x00000042
    bne  a2, t1, cbt_fail
    lw   a4, 0(a1)
    li   t1, 0x00000042        # byte0 holds the swap (== compare) value
    bne  a4, t1, cbt_fail

    RVTEST_PASS

cbt_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .align 2
cb_word: .word 0
RVTEST_DATA_END
