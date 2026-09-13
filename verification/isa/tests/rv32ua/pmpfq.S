# See LICENSE for license details.

# VestaRV: PMP instruction-fault on an odd-halfword fetch, the is_compressed exposed path
# ON-ONLY, needing a pmp, umode, trapCsr build. The is_compressed inferred latch is observable only when instr_curr selects instr_decomp, EXCEPT on one path: the hoisted PMP instruction-access-fault arm, which does not assign is_compressed and can run with pc(1) = '1', repeat_if = '0' and quadrant_upper /= "11". Four things must hold at once, and this file constructs three of them by layout: a PMP-denied INSTRUCTION fetch, a denied PC on an ODD halfword, and arrival by a JUMP rather than a straddle completion, so repeat_if is 0, which is what makes this a different shape from pmprt6.S, whose fault is on the upper half of a straddling instruction. THE FOURTH IS NOT CONSTRUCTIBLE FROM SOFTWARE: on a denied fetch pmp_if_park re-aims the fetch at PC_RST_VAL, so the decode sees the boot ROM's word 0, 0xF14022F3, whose bits 17:16 are "00". That is derived, not calibrated, and is measured by the W_F55_EXPOSED witness in verification/formal/core_pmp_witness.psl.
# THE GEOMETRY, with entry 0 fencing ONE word NA4 with no permissions and the jump landing on the ODD halfword inside it, so the very first fetch after the jump is the denied one: B+0 `j f55_odd`, a 32-bit permitted word; B+4 THE FENCED WORD, holding a c.nop that is never fetched; B+6 `c.li s11, 7`, THE TARGET, which must never execute; B+8 c.nop, permitted, where the handler resumes; B+10 `c.li s10, 5`, a compressed instruction at an odd halfword executed after the fault; B+12 `la s7, fq_uexit`, 8 bytes, re-aiming the resume point; B+20 `lw t3, 4(s2)`, a DATA read into the fenced word; B+24 `ecall` back to M.
# Under test: that the fault fires on this shape at all with cause 1; that mepc = mtval = B+6, since pmp_f_addr_r takes pc_next and the jump made pc_next = B+6, unlike pmprt6 where the two differ; that the denied instruction COMMITTED NOTHING, so s11 stays 0; that the next compressed instruction at an odd halfword still decodes as itself, so s10 = 5 and the trap left no decode residue; and the load arm, where a denied load raises cause 5 with mtval the byte-precise data address. THAT LOAD LEG EXISTS SO ONE TEST DRIVES BOTH DENIAL ARMS: it is the stimulus the suppression property in verification/formal/core_pmp_props.psl needs, and without it that property's data-side witness cannot fire and its green is uninterpretable.
# WHAT THIS FILE DOES NOT PROVE, and no a0-watching test can: that the HELD is_compressed value is harmless. The arm's trap observables are decode-independent and the held value reaches only instr_curr_prev, so the honest claim is that the exposed path is exercised and the architectural result is correct, never that the latch is harmless. That needs the clocked property.
# Compressed encodings are raw `.half` words, so the file can stay `.option norvc` and the layout is byte-exact: 0x0001 is c.nop, 0x4D9D is `c.li s11, 7` and 0x4D15 is `c.li s10, 5`. Boundedness: the U fragment is straight-line into `ecall` and the handler bails to M after 8 traps, so a mis-decoded instruction cannot loop.
# Verdict codes in a1: 0x0F550001 an mtvec, mtrapctl or pmpcfg precondition failed; 0x0F550002 the fenced word is not where the layout says; 0x0F550003 the jump target is not 4n+2, so the layout moved; 0x0F550010 no fault fired at all; 0x0F550011 wrong cause; 0x0F550012 wrong mepc; 0x0F550013 wrong mtval; 0x0F550014 s11 is nonzero, so THE DENIED INSTRUCTION EXECUTED; 0x0F550015 s10 is not 5, so the post-fault odd-halfword decode is corrupted; 0x0F550016 wrong total trap count; 0x0F550020 the denied load did not fault; 0x0F550021 wrong cause on the denied load; 0x0F550022 wrong mtval on it; 0x5E10BAD0 built on the wrong polarity. No shared words are claimed: single hart, TCM and CSRs only.

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
