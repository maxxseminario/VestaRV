# See LICENSE for license details.

#*****************************************************************************
# pmpfq.S   (K4 R-DK1 row A3 -- F5.5: the is_compressed latch's EXPOSED PATH)
#-----------------------------------------------------------------------------
# F5.5 is the last unreached item of the F-series residue list
# (`method_rules.md` §5: "the `is_compressed` inferred latch -- exposed only in
# an ENABLE_PMP build").  vesta.vhd states the exposure in its own words
# (re-grepped at ac8b40a; every line number in every document is stale):
#
#     the ONLY reader is `instr_to_decomp`, qualified `EXECUTE and pc(1)='1'
#     and repeat_if='0'`; the value is OBSERVABLE only when `instr_curr`
#     selects `instr_decomp`, i.e. additionally `quadrant_upper /= "11"` ...
#     EXCEPT on one path: the hoisted PMP instruction-access-fault arm, which
#     does NOT assign is_compressed and can run with pc(1)='1', repeat_if='0',
#     quadrant_upper /= "11".
#
# So the shape needs FOUR things at once, and this file constructs three of
# them by layout and inherits the fourth from the RTL:
#
#   ENABLE_PMP        the build (tag `pmp umode trapCsr atomics`)
#   pmp_f_deny_r='1'  a PMP-denied INSTRUCTION fetch
#   pc(1)='1'         the denied fetch's PC is an ODD halfword
#   repeat_if='0'     we arrive by a JUMP, not by a straddle completion --
#                     which is what makes this a DIFFERENT shape from
#                     pmprt6.S, whose fault is on the UPPER half of a
#                     straddling instruction and therefore has repeat_if='1'
#   quadrant_upper/="11"   NOT constructible from software: on a denied fetch
#                     `pmp_if_park` re-aims the fetch at PC_RST_VAL, so the
#                     word the decode sees is the boot ROM's word 0 =
#                     0xF14022F3 (`csrr t0, mhartid`), whose bits 17:16 are
#                     "00".  DERIVED, not calibrated -- and MEASURED rather
#                     than argued by the W_F55_EXPOSED witness in
#                     verification/formal/core_pmp_witness.psl.
#
# THE GEOMETRY.  entry0 fences ONE word (NA4, no permissions); the jump lands
# on the ODD halfword INSIDE it, so the very first fetch after the jump is the
# denied one:
#
#     B+0    j f55_odd            32-bit, permitted word
#     B+4    <-- THE FENCED WORD (NA4, no permissions)
#     B+4    c.nop                never fetched
#     B+6    c.li s11, 7          <-- THE TARGET.  Must NEVER execute.
#     B+8    c.nop                permitted word; the handler resumes here
#     B+10   c.li s10, 5          a COMPRESSED instruction at an ODD halfword,
#                                 executed AFTER the fault -- the post-fault
#                                 decode check (pmprt6's check-14 idiom)
#     B+12   la s7, fq_uexit      (auipc+addi, 8 bytes) re-aim the resume point
#     B+20   lw t3, 4(s2)         a DATA read INTO the fenced word: the D5
#                                 load/store arm, cause 5, mtval = B+4
#     B+24   ecall                back to M
#
# WHAT IS UNDER TEST
#   (a) the fault fires on this shape at all, with cause 1;
#   (b) mepc = mtval = B+6.  The denied fetch's address IS the faulting PC
#       here (unlike pmprt6, where mepc=B+2 and mtval=B+4), because
#       pmp_f_addr_r takes pc_next and the jump made pc_next = B+6;
#   (c) the denied instruction COMMITTED NOTHING: s11 stays 0;
#   (d) the next compressed instruction at an odd halfword still decodes as
#       itself (s10 = 5) -- i.e. the trap left no decode residue;
#   (e) THE D5 ARM ITSELF: a denied LOAD raises cause 5 with mtval = the
#       byte-precise data address.  This leg exists so ONE test drives both
#       PMP denial arms -- it is the stimulus the D5 suppression property
#       (verification/formal/core_pmp_props.psl) needs, and without it that
#       property's data-side witness cannot fire and its green is
#       uninterpretable (R-S4-2's standing rule).
#
# WHAT THIS FILE DOES NOT PROVE, and no a0-watching test can:
# that the HELD `is_compressed` value is harmless.  The arm's trap observables
# are decode-INDEPENDENT (mtrap_disp_code's first arm is x"1" gated on
# pmp_f_deny_r, mtrap_disp_val is pmp_f_addr_r, mepc is pc), and the held value
# reaches only `instr_curr_prev`.  This file's honest claim is "the exposed
# path is EXERCISED and the architectural result is correct" -- never "the
# latch is harmless".  That needs the clocked property, which is why
# verification/formal/core_pmp_props.psl exists.
#
# BOUNDEDNESS: the U fragment is straight-line into `ecall`, and the handler
# BAILS to M after 8 traps, so a mis-decoded instruction cannot loop.
#
# Compressed encodings are raw `.half` words (the extrvc/pmprt6 idiom) so the
# file can stay `.option norvc` and the layout is byte-exact:
#   0x0001 = c.nop     0x4D9D = c.li s11, 7     0x4D15 = c.li s10, 5
#
# VERDICT CODES (a1 at the failure):
#   0x0F550001  an mtvec / mtrapctl / pmpcfg precondition failed
#   0x0F550002  the fenced word is not where the layout says it is
#   0x0F550003  the jump target is not 4n+2 -- the layout moved
#   0x0F550010  no fault fired at all: the shape was never entered
#   0x0F550011  wrong cause (expected 1, instruction access fault)
#   0x0F550012  wrong mepc  (expected B+6)
#   0x0F550013  wrong mtval (expected B+6)
#   0x0F550014  s11 != 0: THE DENIED INSTRUCTION EXECUTED
#   0x0F550015  s10 != 5: the post-fault odd-halfword decode is corrupted
#   0x0F550016  wrong total trap count
#   0x0F550020  the denied LOAD did not fault (the D5 arm never fired)
#   0x0F550021  wrong cause on the denied load (expected 5)
#   0x0F550022  wrong mtval on the denied load (expected B+4)
#   0x5E10BAD0  built on the wrong polarity
#
# SHARED WORDS CLAIMED: NONE.  Single hart, TCM and CSRs only.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define FQ_TORTOP  0x00020000

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, fq_fail

#if defined(CORE_ENABLE_TRAPCSR) && defined(CORE_ENABLE_UMODE) && defined(CORE_ENABLE_PMP)

    .option push
    .option arch, +zicsr

    li   sp, 0xBFF0
    li   s3, 0                      # trap counter
    li   s4, 0                      # first-fault  cause (0 = not captured yet)
    li   s8, 0                      # second-fault cause (0 = not captured yet)
    li   s1, 0                      # second-fault mtval
    li   s10, 0
    li   s11, 0

    li   a1, 0x0F550001
    la   t0, fq_handler
    csrw 0x305, t0
    csrr t1, 0x305
    bne  t1, t0, fq_fail
    csrw 0x7C0, x0                  # mtrapctl.LEGACY = 0 -> standard delivery
    csrr t1, 0x7C0
    bnez t1, fq_fail
    csrw 0x304, x0                  # no interrupts

    # ---- the map: entry0 fences the word at B+4 ONLY -------------------
    la   s2, fq_base
    addi t0, s2, 4
    srli t0, t0, 2
    csrw 0x3B0, t0                  # pmpaddr0 = (B+4) >> 2   (NA4)
    csrw 0x3B1, x0                  # pmpaddr1 = 0            (TOR lower bound)
    li   t0, FQ_TORTOP
    srli t0, t0, 2
    csrw 0x3B2, t0                  # pmpaddr2 = top          (TOR upper bound)
    li   t0, 0x000F0010             # cfg2=TOR RWX  cfg1=OFF  cfg0=NA4 no-perms
    csrw 0x3A0, t0
    csrr t1, 0x3A0
    bne  t1, t0, fq_fail

    # ---- the layout, checked STRUCTURALLY, never calibrated ------------
    li   a1, 0x0F550002
    la   t0, fq_fenced
    addi t1, s2, 4
    bne  t0, t1, fq_fail            # the fenced word really is B+4
    li   a1, 0x0F550003
    la   t0, fq_odd
    addi t1, s2, 6
    bne  t0, t1, fq_fail            # the jump target really is B+6
    andi t1, t0, 3
    li   t2, 2
    bne  t1, t2, fq_fail            # ... and 4n+2, i.e. pc(1) = '1'

    # ---- enter U at B, resuming (after the fault) at B+8 ---------------
    la   s9, fq_m2
    addi s7, s2, 8
    csrw 0x341, s2
    csrw 0x300, x0                  # MPP=00 (U), MIE=0, MPRV=0
    mret                            # ---- U ----

fq_m2:
    li   a1, 0x0F550010
    beqz s4, fq_fail                # nothing faulted: the shape never fired
    li   a1, 0x0F550011
    li   t1, 1
    bne  s4, t1, fq_fail            # cause 1 = instruction access fault
    li   a1, 0x0F550012
    addi t1, s2, 6
    bne  s5, t1, fq_fail            # mepc  = the faulting PC = B+6
    li   a1, 0x0F550013
    addi t1, s2, 6
    bne  s6, t1, fq_fail            # mtval = the denied fetch address = B+6
    li   a1, 0x0F550014
    bnez s11, fq_fail               # the denied `c.li s11,7` committed NOTHING
    li   a1, 0x0F550015
    li   t1, 5
    bne  s10, t1, fq_fail           # the odd-halfword c.li AFTER the fault ran
    li   a1, 0x0F550020
    beqz s8, fq_fail                # the denied LOAD never faulted
    li   a1, 0x0F550021
    li   t1, 5
    bne  s8, t1, fq_fail            # cause 5 = load access fault
    li   a1, 0x0F550022
    addi t1, s2, 4
    bne  s1, t1, fq_fail            # mtval = the byte-precise data address
    li   a1, 0x0F550016
    li   t1, 3                      # 1 fetch fault + 1 load fault + 1 ECALL
    bne  s3, t1, fq_fail

    csrw 0x3A0, x0                  # drop the map before leaving
    li   t1, 0x00000001
    csrw 0x7C0, t1
    csrw 0x300, x0

    RVTEST_PASS

    # =====================================================================
    # THE U FRAGMENT.  Byte-exact; do not reorder or re-align.
    # =====================================================================
    .align 2
fq_base:
    j    fq_odd                     # B+0 .. B+3   (permitted word)
fq_fenced:
    .half 0x0001                    # B+4   c.nop   -- inside the FENCED word
fq_odd:
    .half 0x4D9D                    # B+6   c.li s11, 7  <-- MUST NOT EXECUTE
fq_resume:
    .half 0x0001                    # B+8   c.nop
    .half 0x4D15                    # B+10  c.li s10, 5  <-- odd halfword, runs
fq_uload:
    la   s7, fq_uexit               # B+12  re-aim the handler's resume point
    lw   t3, 4(s2)                  #       DATA read INTO the fenced word
fq_uexit:
    ecall
    j    fq_uexit

    .align 2
fq_handler:
    csrr t0, 0x342
    addi s3, s3, 1
    li   t1, 8
    beq  t0, t1, fq_hdl_ecall       # ECALL from U
    li   t1, 11
    beq  t0, t1, fq_hdl_ecall       # ECALL from M
    bnez s4, fq_hdl_second
    mv   s4, t0                     # capture the FIRST fault
    csrr s5, 0x341
    csrr s6, 0x343
    j    fq_hdl_nocap
fq_hdl_second:
    bnez s8, fq_hdl_nocap
    mv   s8, t0                     # capture the SECOND fault
    csrr s1, 0x343
fq_hdl_nocap:
    li   t1, 8
    blt  t1, s3, fq_hdl_ecall       # BAIL to M after 8 traps (boundedness)
    csrw 0x341, s7
    mret
fq_hdl_ecall:
    jr   s9

    .option pop

#else
    li   a1, 0x5E10BAD0
    j    fq_fail
#endif

fq_fail:
    RVTEST_FAIL

    # NOTE: RVTEST_CODE_END is 'unimp' (traps!) in this env -- never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
