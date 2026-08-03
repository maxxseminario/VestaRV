# See LICENSE for license details.

#*****************************************************************************
# shcboz.S  (X3 Zicboz — cbo.zero directed functional test)
#-----------------------------------------------------------------------------
# Build-time dispatch on CORE_ENABLE_ZICBOZ (extprobe_template.S convention: the
# macro is supplied EXPLICITLY via -DCORE_ENABLE_ZICBOZ when staging the ON
# polarity, NEVER auto-derived from a make-chip header). This is the functional
# proof that runs in BOTH polarities of the behavioral_mp regression:
#
#   OFF (#else): base-ISA sanity + RVTEST_PASS. cbo.zero is illegal here (it
#       would trap terminally), so the default build must NOT execute it — the
#       stub keeps the default suite green and the image bit-identical to a base
#       build (no cbo.zero encoding is emitted).
#
#   ON  (#ifdef CORE_ENABLE_ZICBOZ): the full functional matrix on hart 0 (tiles
#       stay parked — a single-hart test). For each of a PRIVATE TCM block and a
#       SHARED-RAM block (exercising both the private and the arbiter store
#       paths of the sequencer):
#         * poison all 16 words of a naturally-aligned 64-byte block to 0xAA and
#           set a sentinel GUARD word immediately BEFORE and immediately AFTER it;
#         * cbo.zero the block; assert all 16 words == 0 AND both guards UNTOUCHED
#           (the boundary guard — a wrong ~63 base mask clobbers a guard; a short
#           15-word burst leaves the tail word non-zero);
#         * repeat with a MISALIGNED base (block_base+20): cbo.zero must round the
#           address DOWN to the same 64-byte block and zero exactly that block,
#           leaving the guards untouched.
#
# CORRECTED 2026-08-03 (K2b amendment 2), MEASURED. This header used to claim
# "gas 13.2 has no `zicboz' -march and no cbo.zero mnemonic". That is FALSE on
# this toolchain: gas 2.41 accepts both `-march=rv32imac_zicsr_zicboz' and
# `.option arch, +zicboz', assembles `cbo.zero (a1)' to 0x0045a00f, and refuses
# the mnemonic without the extension. The explicit `.insn' below is KEPT, and
# deliberately: it is march-INDEPENDENT, so ONE source serves both polarities
# and no per-polarity -march is needed. objdump on this file's ON build shows
# `0045a00f' at all FOUR CBO_ZERO sites -- the same word the mnemonic produces.
#     cbo.zero rs1  ==  .insn i 0x0f, 0x2, x0, rs1, 0x4
#
# Shared-window map (N=4; isolation — benign overlap at other N). The block sits
# in the free gap above the shlock JOURNAL (0x11000-0x110FF at N=4) and below
# COUNTS (0x11800); write-before-read (the test poisons it), so initial contents
# do not matter:
#     SH_GUARD_LO = 0x113FC   (guard word before the shared block)
#     SH_BLOCK    = 0x11400   (64-byte aligned block to zero)
#     SH_GUARD_HI = 0x11440   (guard word after the shared block)
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define CBO_ZERO(rs1)  .insn i 0x0f, 0x2, x0, rs1, 0x4

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr t0, mhartid
    .option pop
    bnez t0, cbz_pass            # single-hart test; tiles (if launched) just pass

#ifdef CORE_ENABLE_ZICBOZ
    # =====================================================================
    # base-ISA sanity
    # =====================================================================
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, cbz_fail

    # ---- Block 1: PRIVATE TCM block (aligned base) ----
    la   a1, cbz_tcm_block       # 64-byte aligned (see .align 6 in .data)
    jal  cbz_poison              # poison 16 words + both guards
    CBO_ZERO(a1)                 # zero the naturally-aligned block
    jal  cbz_check               # assert 16 == 0 AND guards untouched

    # ---- Block 1b: PRIVATE TCM, MISALIGNED base (base+20) ----
    la   a1, cbz_tcm_block
    jal  cbz_poison
    addi a1, a1, 20              # unaligned within the block
    CBO_ZERO(a1)                 # must round down to cbz_tcm_block
    la   a1, cbz_tcm_block       # check against the aligned base
    jal  cbz_check

    # ---- Block 2: SHARED-RAM block (aligned base, arbiter store path) ----
    li   a1, 0x11400             # SH_BLOCK (64-byte aligned)
    jal  cbz_poison
    CBO_ZERO(a1)
    jal  cbz_check

    # ---- Block 2b: SHARED-RAM, MISALIGNED base ----
    li   a1, 0x11400
    jal  cbz_poison
    addi a1, a1, 44
    CBO_ZERO(a1)
    li   a1, 0x11400
    jal  cbz_check

    j    cbz_pass

    # ---------------------------------------------------------------------
    # cbz_poison: a1 = 64-aligned block base. Write 0xAAAAAAAA to the 16
    #   words [a1 .. a1+60], and distinct sentinels to a1-4 and a1+64.
    #   Clobbers t0,t1,t2. Returns via ra.
    # ---------------------------------------------------------------------
cbz_poison:
    li   t0, 0xAAAAAAAA
    li   t1, 0                   # word index
1:  slli t2, t1, 2
    add  t2, a1, t2
    sw   t0, 0(t2)               # block[i] = 0xAAAAAAAA
    addi t1, t1, 1
    li   t2, 16
    bne  t1, t2, 1b
    li   t0, 0x11111111
    sw   t0, -4(a1)              # guard BEFORE the block
    li   t0, 0x22222222
    sw   t0, 64(a1)              # guard AFTER the block
    ret

    # ---------------------------------------------------------------------
    # cbz_check: a1 = 64-aligned block base. Assert block[0..15] == 0 AND
    #   guard-before == 0x11111111 AND guard-after == 0x22222222.
    #   Clobbers t0,t1,t2. Jumps to cbz_fail on mismatch; else returns.
    # ---------------------------------------------------------------------
cbz_check:
    li   t1, 0                   # word index
1:  slli t2, t1, 2
    add  t2, a1, t2
    lw   t0, 0(t2)
    bnez t0, cbz_fail            # any non-zero word -> FAIL (catches short burst)
    addi t1, t1, 1
    li   t2, 16
    bne  t1, t2, 1b
    lw   t0, -4(a1)              # guard BEFORE must be intact
    li   t2, 0x11111111
    bne  t0, t2, cbz_fail        # clobbered guard -> FAIL (catches wrong base mask)
    lw   t0, 64(a1)              # guard AFTER must be intact
    li   t2, 0x22222222
    bne  t0, t2, cbz_fail
    ret

#else
    # =====================================================================
    # FEATURE OFF: cbo.zero is illegal on this build — do NOT execute it.
    # Trivial pass keeps the default suite green and bit-identical.
    # =====================================================================
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, cbz_fail
    j    cbz_pass
#endif

cbz_pass:
    RVTEST_PASS

cbz_fail:
    RVTEST_FAIL

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .align 6                       # 64-byte aligned block base
cbz_tcm_guard_lo: .word 0        # a word at block-... (padding; real guard is block-4)
  .align 6
cbz_tcm_block:  .fill 16, 4, 0   # the 16-word (64-byte) block to zero
cbz_tcm_guard_hi: .word 0        # block+64 guard
  .word 0
RVTEST_DATA_END
