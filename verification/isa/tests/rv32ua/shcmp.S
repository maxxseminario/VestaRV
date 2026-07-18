# See LICENSE for license details.

#*****************************************************************************
# shcmp.S  (X3 Zcmp — compressed push/pop + reg-moves directed functional test)
#-----------------------------------------------------------------------------
# Build-time dispatch on CORE_ENABLE_ZCMP (explicit -DCORE_ENABLE_ZCMP at ON
# staging; never auto-derived). Runs on hart 0 (single-hart; tiles park).
#
#   OFF (#else): base sanity + PASS. The cm.* encodings are illegal here and
#       must NOT be emitted (image stays bit-identical to a base build).
#
#   ON  (#ifdef): the full push/pop/move matrix. For several (rlist,spimm):
#       seed the listed regs with sentinels, cm.push, verify the frame memory
#       holds them at the SPEC offsets, clobber, cm.pop, verify EXACT round-trip
#       AND sp restored. Plus cm.mvsa01/cm.mva01s round-trip and cm.popretz
#       (a0=0 + control redirect to ra).
#
# gas 13.2 has no cm.* mnemonics, so each is emitted as a raw 16-bit `.short'
# (BYTE-IMAGE encoding). Encodings (C2 op=10, funct3=101):
#   cm.push  rlist,spimm : 12:8=11000  cm.pop     : 11010
#   cm.popretz           : 11100       cm.popret  : 11110
#   cm.mvsa01 s1,s2      : 12:10=011,6:5=01   cm.mva01s : 6:5=11
# The stack is a .data buffer (TCM), so nothing else is disturbed.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr t0, mhartid
    .option pop
    bnez t0, cmp_pass            # single-hart test; launched tiles just pass

#ifdef CORE_ENABLE_ZCMP
    # base-ISA sanity
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, cmp_fail

    # =====================================================================
    # Section B: cm.push/pop {ra,s0-s3} (rlist=8), spimm=1 -> stack_adj=48.
    #   5 regs, memory layout: s3 at sp-4, s2 sp-8, s1 sp-12, s0 sp-16, ra sp-20.
    # =====================================================================
    la   sp, cmp_stack_hi
    mv   s11, sp                 # save entry sp (s11 not in this list)
    li   ra, 0x1A1A1A1A
    li   s0, 0xB0B0B0B0
    li   s1, 0xB1B1B1B1
    li   s2, 0xB2B2B2B2
    li   s3, 0xB3B3B3B3
    .short 0xB886                # cm.push {ra,s0-s3}, -48
    # sp must have dropped by 48
    addi t0, s11, -48
    bne  sp, t0, cmp_fail
    # memory-below-frame holds the sentinels at the spec offsets
    lw   t1, -4(s11);  li t2, 0xB3B3B3B3; bne t1, t2, cmp_fail   # s3 at sp-4
    lw   t1, -8(s11);  li t2, 0xB2B2B2B2; bne t1, t2, cmp_fail   # s2 at sp-8
    lw   t1, -12(s11); li t2, 0xB1B1B1B1; bne t1, t2, cmp_fail   # s1 at sp-12
    lw   t1, -16(s11); li t2, 0xB0B0B0B0; bne t1, t2, cmp_fail   # s0 at sp-16
    lw   t1, -20(s11); li t2, 0x1A1A1A1A; bne t1, t2, cmp_fail   # ra at sp-20
    # clobber all listed regs
    li   ra, 0xDEAD; li s0, 0; li s1, 0; li s2, 0; li s3, 0
    .short 0xBA86                # cm.pop {ra,s0-s3}, 48
    bne  sp, s11, cmp_fail       # sp restored
    li   t2, 0x1A1A1A1A; bne ra, t2, cmp_fail
    li   t2, 0xB0B0B0B0; bne s0, t2, cmp_fail
    li   t2, 0xB1B1B1B1; bne s1, t2, cmp_fail
    li   t2, 0xB2B2B2B2; bne s2, t2, cmp_fail
    li   t2, 0xB3B3B3B3; bne s3, t2, cmp_fail

    # =====================================================================
    # Section C: cm.push/pop {ra} (rlist=4), spimm=0 -> stack_adj=16. ra at sp-4.
    # =====================================================================
    la   sp, cmp_stack_hi
    mv   s11, sp
    li   ra, 0xCAFE0004
    .short 0xB842                # cm.push {ra}, -16
    addi t0, s11, -16
    bne  sp, t0, cmp_fail
    lw   t1, -4(s11); li t2, 0xCAFE0004; bne t1, t2, cmp_fail
    li   ra, 0
    .short 0xBA42                # cm.pop {ra}, 16
    bne  sp, s11, cmp_fail
    li   t2, 0xCAFE0004; bne ra, t2, cmp_fail

    # =====================================================================
    # Section D: cm.push/pop {ra,s0-s11} (rlist=15), spimm=3 -> stack_adj=112.
    #   13 regs. Seed each = 0xD0+idx pattern; check round-trip.
    # =====================================================================
    la   sp, cmp_stack_hi
    mv   t6, sp                  # entry sp (t6 not in list)
    li   ra, 0xD1D1D1D1
    li   s0, 0xD8D8D8D8
    li   s1, 0xD9D9D9D9
    li   s2, 0xE2E2E2E2
    li   s3, 0xE3E3E3E3
    li   s4, 0xE4E4E4E4
    li   s5, 0xE5E5E5E5
    li   s6, 0xE6E6E6E6
    li   s7, 0xE7E7E7E7
    li   s8, 0xE8E8E8E8
    li   s9, 0xE9E9E9E9
    li   s10,0xEAEAEAEA
    li   s11,0xEBEBEBEB
    .short 0xB8FE                # cm.push {ra,s0-s11}, -112
    addi t0, t6, -112
    bne  sp, t0, cmp_fail
    # clobber every listed reg
    li ra,0; li s0,0; li s1,0; li s2,0; li s3,0; li s4,0; li s5,0
    li s6,0; li s7,0; li s8,0; li s9,0; li s10,0; li s11,0
    .short 0xBAFE                # cm.pop {ra,s0-s11}, 112
    bne  sp, t6, cmp_fail
    li t2,0xD1D1D1D1; bne ra, t2, cmp_fail
    li t2,0xD8D8D8D8; bne s0, t2, cmp_fail
    li t2,0xD9D9D9D9; bne s1, t2, cmp_fail
    li t2,0xE2E2E2E2; bne s2, t2, cmp_fail
    li t2,0xE3E3E3E3; bne s3, t2, cmp_fail
    li t2,0xE4E4E4E4; bne s4, t2, cmp_fail
    li t2,0xE5E5E5E5; bne s5, t2, cmp_fail
    li t2,0xE6E6E6E6; bne s6, t2, cmp_fail
    li t2,0xE7E7E7E7; bne s7, t2, cmp_fail
    li t2,0xE8E8E8E8; bne s8, t2, cmp_fail
    li t2,0xE9E9E9E9; bne s9, t2, cmp_fail
    li t2,0xEAEAEAEA; bne s10,t2, cmp_fail
    li t2,0xEBEBEBEB; bne s11,t2, cmp_fail

    # =====================================================================
    # Section E: cm.mvsa01 / cm.mva01s round-trip through s1(x9)/s2(x18).
    #   mvsa01 s1',s2' : x[s1']=a0, x[s2']=a1  (s1'=1->x9, s2'=2->x18)
    #   mva01s s1',s2' : a0=x[s1'], a1=x[s2']
    # =====================================================================
    li   a0, 0x0A0A0A0A
    li   a1, 0x0B0B0B0B
    li   s1, 0
    li   s2, 0
    .short 0xACAA                # cm.mvsa01 s1,s2  (s9<-a0, x18<-a1)
    li   t2, 0x0A0A0A0A; bne s1, t2, cmp_fail
    li   t2, 0x0B0B0B0B; bne s2, t2, cmp_fail
    # now clobber a0/a1 and move back
    li   a0, 0
    li   a1, 0
    .short 0xACEA                # cm.mva01s s1,s2  (a0<-s9, a1<-x18)
    li   t2, 0x0A0A0A0A; bne a0, t2, cmp_fail
    li   t2, 0x0B0B0B0B; bne a1, t2, cmp_fail

    # =====================================================================
    # Section F: cm.popretz {ra,s0} (rlist=5), spimm=0 -> a0=0 + control at ra.
    # =====================================================================
    la   sp, cmp_stack_hi
    mv   s11, sp
    la   ra, prz_land            # ra = redirect target
    li   s0, 0x5A5A5A5A
    .short 0xB852                # cm.push {ra,s0}, -16
    li   ra, 0xDEAD              # clobber
    li   s0, 0
    li   a0, 0x12345678          # non-zero; popretz must zero it
    .short 0xBC52                # cm.popretz {ra,s0}, 16 -> a0=0, sp+=16, ret ra
    j    cmp_fail                # must NOT fall through (control went to ra)
prz_land:
    bnez a0, cmp_fail            # a0 must be 0
    li   t2, 0x5A5A5A5A; bne s0, t2, cmp_fail   # s0 restored
    bne  sp, s11, cmp_fail       # sp restored

    # =====================================================================
    # Section G: cm.popret {ra,s0} -> control at ra, a0 UNCHANGED.
    # =====================================================================
    la   sp, cmp_stack_hi
    mv   s11, sp
    la   ra, pr_land
    li   s0, 0x6B6B6B6B
    .short 0xB852                # cm.push {ra,s0}, -16
    li   ra, 0xDEAD
    li   s0, 0
    li   a0, 0x0BADF00D          # popret must NOT touch a0
    .short 0xBE52                # cm.popret {ra,s0}, 16 -> sp+=16, ret ra
    j    cmp_fail
pr_land:
    li   t2, 0x0BADF00D; bne a0, t2, cmp_fail   # a0 unchanged
    li   t2, 0x6B6B6B6B; bne s0, t2, cmp_fail
    bne  sp, s11, cmp_fail

    j    cmp_pass

#else
    # FEATURE OFF: cm.* are illegal — trivial pass, image bit-identical.
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, cmp_fail
    j    cmp_pass
#endif

cmp_pass:
    RVTEST_PASS
cmp_fail:
    RVTEST_FAIL

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .align 4
cmp_stack_lo: .fill 80, 4, 0     # 320-byte stack buffer (>112 frame)
cmp_stack_hi:
  .word 0
RVTEST_DATA_END
