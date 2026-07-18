# See LICENSE for license details.

#*****************************************************************************
# extzabha.S   (X2 Zabha ext-probe, 2026-07-17)
#-----------------------------------------------------------------------------
# Build-time dispatch on CORE_ENABLE_ZABHA (extprobe_template.S convention —
# the macro is supplied EXPLICITLY via -DCORE_ENABLE_ZABHA when staging the ON
# polarity, NEVER auto-derived from a make-chip header or platform/common/out/
# state; the two build-order traps in that header apply verbatim).
#
#   ON  (#ifdef CORE_ENABLE_ZABHA): execute the real byte/halfword AMO
#       encodings and CHECK the architectural results -> PASS. This is the
#       single-hart FUNCTIONAL suite for Zabha (rd sign-extension, byte-lane
#       steering on all four lanes, halfword lanes, signed AND unsigned
#       min/max, and adjacent-lane isolation on a private-TCM word).
#
#   OFF (#else): the SAME byte-AMO encoding executed UNCONDITIONALLY. On a
#       build without Zabha (this is the extoff POISON) the encoding MUST take
#       the illegal-instruction trap. run_extoff.sh + trap_watch.tcl report
#       TRAP_OK; executing PAST it -> FAIL. (The default a0-watch runner would
#       hang on this trap — vesta TRAP_STATE is terminal — so extzabha is wired
#       ONLY into behavioral_mp_stripped/run_extoff.sh, not the 124-suite.)
#
# Encodings use `.insn` because the installed gas (13.2) does NOT know the
# `zabha' -march suffix or the amoadd.b/... mnemonics (verified at X2 bring-up),
# so every Zabha instruction in the suite is emitted as an explicit R-type:
#     .insn r 0x2f, funct3, funct7, rd, rs1_base, rs2_val
#     funct3 = 000 byte / 001 half ; funct7 = funct5<<2 (aq=rl=0)
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

# ---- Zabha .insn encodings (funct7 = funct5<<2, aq=rl=0) --------------------
#define AMOADD_B(rd,rs1,rs2)   .insn r 0x2f, 0x0, 0x00, rd, rs1, rs2
#define AMOADD_H(rd,rs1,rs2)   .insn r 0x2f, 0x1, 0x00, rd, rs1, rs2
#define AMOSWAP_B(rd,rs1,rs2)  .insn r 0x2f, 0x0, 0x04, rd, rs1, rs2
#define AMOSWAP_H(rd,rs1,rs2)  .insn r 0x2f, 0x1, 0x04, rd, rs1, rs2
#define AMOXOR_B(rd,rs1,rs2)   .insn r 0x2f, 0x0, 0x10, rd, rs1, rs2
#define AMOOR_B(rd,rs1,rs2)    .insn r 0x2f, 0x0, 0x20, rd, rs1, rs2
#define AMOAND_B(rd,rs1,rs2)   .insn r 0x2f, 0x0, 0x30, rd, rs1, rs2
#define AMOMIN_B(rd,rs1,rs2)   .insn r 0x2f, 0x0, 0x40, rd, rs1, rs2
#define AMOMAX_B(rd,rs1,rs2)   .insn r 0x2f, 0x0, 0x50, rd, rs1, rs2
#define AMOMINU_B(rd,rs1,rs2)  .insn r 0x2f, 0x0, 0x60, rd, rs1, rs2
#define AMOMAXU_B(rd,rs1,rs2)  .insn r 0x2f, 0x0, 0x70, rd, rs1, rs2

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity (runs on every build, like extprobe.S) ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, ezt_fail

#ifdef CORE_ENABLE_ZABHA
    # =====================================================================
    # FEATURE ON: functional byte/halfword AMO checks on a private-TCM word.
    # =====================================================================

    # -- amoadd.b lane 0, positive byte: rd = sext(old), mem byte0 += rs2 --
    la   a3, ez_word
    li   t0, 0x44332211
    sw   t0, 0(a3)
    li   a1, 0x05
    AMOADD_B(a4, a3, a1)            # a4 <- sext(0x11)=0x11 ; byte0: 0x11+0x05=0x16
    li   t1, 0x00000011
    bne  a4, t1, ezt_fail
    lw   a5, 0(a3)
    li   t1, 0x44332216            # only byte0 changed
    bne  a5, t1, ezt_fail

    # -- amoadd.b lane 3, NEGATIVE byte -> rd sign-extended --
    la   a3, ez_word
    li   t0, 0x80332216
    sw   t0, 0(a3)
    addi a3, a3, 3                 # point at byte 3 (0x80)
    li   a1, 0x00
    AMOADD_B(a4, a3, a1)           # a4 <- sext(0x80)=0xFFFFFF80 ; byte3 unchanged
    li   t1, 0xFFFFFF80
    bne  a4, t1, ezt_fail
    la   a3, ez_word
    lw   a5, 0(a3)
    li   t1, 0x80332216            # adjacent lanes untouched
    bne  a5, t1, ezt_fail

    # -- amoswap.b lane 1: old sext returned, ONLY lane1 written --
    la   a3, ez_word
    li   t0, 0xAABBCCDD
    sw   t0, 0(a3)
    addi a3, a3, 1                 # byte 1 (0xCC)
    li   a1, 0x77
    AMOSWAP_B(a4, a3, a1)          # a4 <- sext(0xCC)=0xFFFFFFCC ; byte1 <- 0x77
    li   t1, 0xFFFFFFCC
    bne  a4, t1, ezt_fail
    la   a3, ez_word
    lw   a5, 0(a3)
    li   t1, 0xAABB77DD            # lanes 0,2,3 untouched (adjacent-lane guard)
    bne  a5, t1, ezt_fail

    # -- amoand.b / amoor.b / amoxor.b lane 0 (logical, low byte) --
    la   a3, ez_word
    li   t0, 0x000000F0
    sw   t0, 0(a3)
    li   a1, 0x0F
    AMOAND_B(a4, a3, a1)           # 0xF0 & 0x0F = 0x00
    lbu  a5, 0(a3)
    bnez a5, ezt_fail
    li   t0, 0x00000030
    sw   t0, 0(a3)
    li   a1, 0x05
    AMOOR_B(a4, a3, a1)            # 0x30 | 0x05 = 0x35
    lbu  a5, 0(a3)
    li   t1, 0x35
    bne  a5, t1, ezt_fail
    li   a1, 0xFF
    AMOXOR_B(a4, a3, a1)           # 0x35 ^ 0xFF = 0xCA
    lbu  a5, 0(a3)
    li   t1, 0xCA
    bne  a5, t1, ezt_fail

    # -- amomax.b SIGNED: max(0x7F=127, 0x80=-128) = 0x7F --
    la   a3, ez_word
    li   t0, 0x0000007F
    sw   t0, 0(a3)
    li   a1, 0x80                  # -128 as a byte
    AMOMAX_B(a4, a3, a1)
    li   t1, 0x0000007F            # rd = sext(old 0x7F)
    bne  a4, t1, ezt_fail
    lbu  a5, 0(a3)
    li   t1, 0x7F                  # 0x7F wins
    bne  a5, t1, ezt_fail

    # -- amomaxu.b UNSIGNED (monotonicity): max(0x7F,0x80)=0x80 --
    li   t0, 0x0000007F
    sw   t0, 0(a3)
    li   a1, 0x80
    AMOMAXU_B(a4, a3, a1)
    li   t1, 0x0000007F            # rd = sext(old 0x7F)
    bne  a4, t1, ezt_fail
    lbu  a5, 0(a3)
    li   t1, 0x80                  # 0x80 wins unsigned
    bne  a5, t1, ezt_fail

    # -- amominu.b UNSIGNED: min(0x80,0x7F)=0x7F ; rd = sext(old 0x80) --
    li   t0, 0x00000080
    sw   t0, 0(a3)
    li   a1, 0x7F
    AMOMINU_B(a4, a3, a1)
    li   t1, 0xFFFFFF80            # rd = sext(old 0x80)
    bne  a4, t1, ezt_fail
    lbu  a5, 0(a3)
    li   t1, 0x7F                  # 0x7F wins unsigned
    bne  a5, t1, ezt_fail

    # -- amomin.b SIGNED: min(0x7F,0x80=-128) = 0x80 --
    li   t0, 0x0000007F
    sw   t0, 0(a3)
    li   a1, 0x80
    AMOMIN_B(a4, a3, a1)
    lbu  a5, 0(a3)
    li   t1, 0x80                  # -128 wins signed
    bne  a5, t1, ezt_fail

    # -- amoadd.h low half, sign-extended rd, ONLY low half written --
    la   a3, ez_word
    li   t0, 0x12348000
    sw   t0, 0(a3)                 # half0=0x8000, half1=0x1234
    li   a1, 0x0001
    AMOADD_H(a4, a3, a1)           # a4 <- sext(0x8000)=0xFFFF8000 ; half0 -> 0x8001
    li   t1, 0xFFFF8000
    bne  a4, t1, ezt_fail
    lw   a5, 0(a3)
    li   t1, 0x12348001            # high half untouched
    bne  a5, t1, ezt_fail

    # -- amoswap.h HIGH half (addr+2): ONLY high half written --
    la   a3, ez_word
    li   t0, 0x11112222
    sw   t0, 0(a3)
    addi a3, a3, 2                 # high half
    li   a1, 0xF00D
    AMOSWAP_H(a4, a3, a1)          # a4 <- sext(0x1111)=0x00001111 ; half1 <- 0xF00D
    li   t1, 0x00001111
    bne  a4, t1, ezt_fail
    la   a3, ez_word
    lw   a5, 0(a3)
    li   t1, 0xF00D2222            # low half untouched (adjacent-half guard)
    bne  a5, t1, ezt_fail

    # ================= rd/rs1/rs2 aliasing (F1 + F2 regression) ==============
    # These arms fail on the pre-fix RTL: F1 = amo_wen keyed on the LIVE rs1 port
    # (clobbered to the sign-extended old value by the AMO_WRITEBACK rd write, so
    # a rd==rs1 sub-word AMO picks the WRONG byte lane); F2 = the AMO compute fed
    # by the LIVE rs2 port (clobbered for rd==rs2). The fixes latch address+rs2 in
    # amo_reg_proc (alias-proof), so all four arms must PASS.

    # amoswap.b rd == rs1 (address lane 1): lane must come from the REGISTERED addr
    la   a3, ez_word
    li   t0, 0xAA11BBCC            # b0=CC b1=BB b2=11 b3=AA
    sw   t0, 0(a3)
    addi a3, a3, 1                 # &ez_word+1 (lane 1) AND the rd target
    li   a4, 0x77
    AMOSWAP_B(a3, a3, a4)          # rd=a3 <- sext(0xBB)=0xFFFFFFBB ; lane1 <- 0x77
    li   t1, 0xFFFFFFBB
    bne  a3, t1, ezt_fail
    la   a5, ez_word
    lw   a5, 0(a5)
    li   t1, 0xAA1177CC            # ONLY lane1 written (F1: wrong lane -> mismatch)
    bne  a5, t1, ezt_fail

    # amoadd.b rd == rs2: compute operand must be the REGISTERED rs2
    la   a4, ez_word
    li   t0, 0x00000010           # byte0 = 0x10
    sw   t0, 0(a4)
    li   a3, 0x05                 # rs2 = 5 (also rd)
    AMOADD_B(a3, a4, a3)          # rd=a3 <- sext(0x10)=0x10 ; byte0 <- 0x10+0x05=0x15
    li   t1, 0x00000010
    bne  a3, t1, ezt_fail
    lbu  a5, 0(a4)
    li   t1, 0x15                 # F2: rs2 clobbered -> 0x10+0x10=0x20 mismatch
    bne  a5, t1, ezt_fail

    # amoadd.h rd == rs1 (high-half address): half lane from the REGISTERED addr
    la   a3, ez_word
    li   t0, 0x1234A5A5           # half0=0xA5A5 half1=0x1234
    sw   t0, 0(a3)
    addi a3, a3, 2                # high-half address AND rd target
    li   a4, 0x0001
    AMOADD_H(a3, a3, a4)          # rd=a3 <- sext(0x1234)=0x1234 ; half1 <- 0x1235
    li   t1, 0x00001234
    bne  a3, t1, ezt_fail
    la   a5, ez_word
    lw   a5, 0(a5)
    li   t1, 0x1235A5A5           # ONLY high half written (F1: wrong half -> mismatch)
    bne  a5, t1, ezt_fail

    # amoadd.b rd == rs1 == rs2 (all one reg = the address): exercises both paths
    la   a3, ez_word
    sw   x0, 0(a3)                # mem = 0
    mv   t2, a3                   # save the address
    AMOADD_B(a3, a3, a3)          # rd=a3 <- sext(0)=0 ; byte0 <- (0 + (addr&0xFF))&0xFF
    bnez a3, ezt_fail             # rd = old byte = 0
    lbu  a5, 0(t2)
    andi t1, t2, 0xFF             # F2: rs2(=addr) clobbered to 0 -> byte 0x00 mismatch
    bne  a5, t1, ezt_fail

    RVTEST_PASS

#else
    # =====================================================================
    # FEATURE OFF (extoff POISON): a byte AMO MUST take the illegal-instr trap.
    # =====================================================================
    la   a3, ez_word
    li   a1, 0x01
    AMOADD_B(a4, a3, a1)           # amoadd.b — illegal without Zabha, must trap
    j    ezt_fail                  # reached only if it did NOT trap

#endif

ezt_fail:
    RVTEST_FAIL                    # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .align 2
ez_word: .word 0
RVTEST_DATA_END
