# See LICENSE for license details.

#*****************************************************************************
# casw.S   (X2 Zacas directed suite — amocas.w word compare-and-swap)
#-----------------------------------------------------------------------------
# ON-POLARITY ONLY (rv32uzabha/rv32uzicond precedent): the amocas encodings
# trap illegal on a zacas-OFF build, so this suite runs against a zacas-ON MCU
# and is NOT wired into the default runner. gas 13.2 has no amocas mnemonic /
# no `zacas' -march (verified at X2 bring-up), so every CAS is an explicit
# `.insn' R-type:
#     amocas.w rd,rs2,(rs1)  -> funct3=010, funct5=00101, funct7=funct5<<2=0x14
#     .insn r 0x2f, 0x2, 0x14, rd, rs1_base, rs2_val
#
# amocas semantics (rd is a SOURCE — the compare value — AND the destination):
#     temp = mem[rs1]; if temp == rd then mem[rs1] = rs2; rd = temp
#
# Coverage: both compare outcomes, and the FULL aliasing matrix (rd==rs1,
# rd==rs2, rs1==rs2, rd==rs1==rs2) for both outcomes where meaningful. The
# SUCCESS/FAIL "self-overwrite" arms are also the live-detector for the
# stale-compare bug class (AMO_WRITEBACK writes the old value into rd BEFORE
# the compare; a compare that re-reads the LIVE rd port sees the clobbered
# value and flips the verdict).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define AMOCAS_W(rd,rs1,rs2)  .insn r 0x2f, 0x2, 0x14, rd, rs1, rs2

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity (runs on every build, like extprobe.S) ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, cwt_fail

    # =====================================================================
    # 1. WORD CAS, compare SUCCEEDS: rd==mem -> mem<-rs2, rd<-old
    # =====================================================================
    la   a1, cw_word
    li   t0, 0xAAAA5555
    sw   t0, 0(a1)
    li   a2, 0xAAAA5555            # rd = compare value == mem
    li   a3, 0x12345678            # rs2 = swap value
    AMOCAS_W(a2, a1, a3)           # match: mem<-0x12345678 ; a2<-old 0xAAAA5555
    li   t1, 0xAAAA5555
    bne  a2, t1, cwt_fail          # rd = old memory value
    lw   a4, 0(a1)
    li   t1, 0x12345678
    bne  a4, t1, cwt_fail          # mem swapped

    # =====================================================================
    # 2. WORD CAS, compare FAILS: rd!=mem -> mem UNCHANGED, rd<-old
    #    (STALE-COMPARE DETECTOR: buggy re-read of rd after AMO_WRITEBACK
    #     would see mem's old value on rd, falsely MATCH, and swap.)
    # =====================================================================
    la   a1, cw_word
    li   t0, 0xAAAA5555
    sw   t0, 0(a1)
    li   a2, 0xDEADBEEF            # rd = compare value != mem
    li   a3, 0x12345678            # rs2 = swap value (must NOT be written)
    AMOCAS_W(a2, a1, a3)           # mismatch: mem stays ; a2<-old 0xAAAA5555
    li   t1, 0xAAAA5555
    bne  a2, t1, cwt_fail          # rd = old memory value
    lw   a4, 0(a1)
    li   t1, 0xAAAA5555
    bne  a4, t1, cwt_fail          # mem NOT changed (write suppressed)

    # =====================================================================
    # 3. ALIAS rd==rs2 (compare value IS the swap value), SUCCESS
    #    mem == a2 -> match -> mem <- a2 (same value) ; rd <- old
    # =====================================================================
    la   a1, cw_word
    li   t0, 0x0BADF00D
    sw   t0, 0(a1)
    li   a2, 0x0BADF00D            # rd == rs2 == compare == swap
    AMOCAS_W(a2, a1, a2)           # match ; mem<-0x0BADF00D ; a2<-old
    li   t1, 0x0BADF00D
    bne  a2, t1, cwt_fail          # rd = old
    lw   a4, 0(a1)
    bne  a4, t1, cwt_fail          # mem holds the swap value

    # =====================================================================
    # 4. ALIAS rd==rs2, FAIL: mem != a2 -> no write ; rd <- old
    # =====================================================================
    la   a1, cw_word
    li   t0, 0x11112222
    sw   t0, 0(a1)
    li   a2, 0x33334444            # rd == rs2 != mem
    AMOCAS_W(a2, a1, a2)           # mismatch ; mem stays ; a2<-old
    li   t1, 0x11112222
    bne  a2, t1, cwt_fail          # rd = old
    lw   a4, 0(a1)
    bne  a4, t1, cwt_fail          # mem unchanged

    # =====================================================================
    # 5. ALIAS rd==rs1 (base address IS the compare value), SUCCESS
    #    Store the ADDRESS into mem so the compare (rd==addr) matches.
    #    F1-adjacent: the write address must come from the REGISTERED addr,
    #    not the rd port that AMO_WRITEBACK clobbers with the old value.
    # =====================================================================
    la   a2, cw_word              # a2 = base address AND compare value
    sw   a2, 0(a2)                # mem[cw_word] = address -> compare matches
    li   a3, 0x12345678           # rs2 = swap value
    AMOCAS_W(a2, a2, a3)          # match ; mem<-0x12345678 ; a2<-old(==address)
    la   t2, cw_word
    bne  a2, t2, cwt_fail         # rd = old = the address
    lw   a4, 0(t2)
    li   t1, 0x12345678
    bne  a4, t1, cwt_fail         # mem swapped at the registered address

    # =====================================================================
    # 6. ALIAS rs1==rs2 (base address IS the swap value), SUCCESS
    #    mem == rd -> match -> mem <- a1 (the address) ; rd <- old
    # =====================================================================
    la   a1, cw_word              # a1 = base AND swap value
    li   t0, 0x55556666
    sw   t0, 0(a1)
    li   a2, 0x55556666           # rd = compare == mem
    AMOCAS_W(a2, a1, a1)          # match ; mem<-a1(address) ; a2<-old 0x55556666
    li   t1, 0x55556666
    bne  a2, t1, cwt_fail         # rd = old
    lw   a4, 0(a1)
    bne  a4, a1, cwt_fail         # mem now holds the address (the swap value)

    # =====================================================================
    # 7. ALIAS rd==rs1==rs2 (ALL one register), SUCCESS
    #    Store the address into mem so compare(rd==addr) matches; on success
    #    mem <- rs2 (==address, unchanged) and rd <- old (==address).
    # =====================================================================
    la   a2, cw_word              # a2 = base = compare = swap
    sw   a2, 0(a2)                # mem = address -> compare matches
    AMOCAS_W(a2, a2, a2)          # match ; mem<-address ; a2<-old(==address)
    la   t2, cw_word
    bne  a2, t2, cwt_fail         # rd = old = address
    lw   a4, 0(t2)
    bne  a4, t2, cwt_fail         # mem still holds the address

    # =====================================================================
    # 8. ALIAS rd==rs1==rs2, FAIL: mem != address -> no write ; rd<-old
    # =====================================================================
    la   a2, cw_word
    li   t0, 0x7EAD7EAD           # mem != the address of cw_word
    sw   t0, 0(a2)
    AMOCAS_W(a2, a2, a2)          # mismatch ; mem stays ; a2<-old
    li   t1, 0x7EAD7EAD
    bne  a2, t1, cwt_fail         # rd = old
    la   t2, cw_word
    lw   a4, 0(t2)
    bne  a4, t1, cwt_fail         # mem unchanged

    RVTEST_PASS

cwt_fail:
    RVTEST_FAIL                    # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .align 2
cw_word: .word 0
RVTEST_DATA_END
