# See LICENSE for license details.

#*****************************************************************************
# pmprt3.S   (P3 RED TEAM — MPRV corner MPP=M, and the UNCHECKED IRQ_REST
#             stack pop)
#-----------------------------------------------------------------------------
# ON-ONLY DIRECTED TEST (needs a trapCsr+umode+pmp build).  Two independent
# probes, ordered so the non-destructive one runs first.
#
# ---------------------------------------------------------------------------
# PART 1 (CHECK 10..15) — MPRV=1 WITH MPP=M MUST STAY M-CHECKED.
#   csr_unit.vhd:1085-1087
#       data_priv_m <= priv_m when mst_mprv = '0' else
#                      '1'    when mst_mpp  = MPP_M else '0';
#   The failure mode this hunts is "MPRV=1 is treated as 'check at U'" — which
#   would spuriously RESTRICT M-mode software that legitimately sets MPRV
#   while MPP still holds M (e.g. a trap taken from M, handler sets MPRV
#   before it has re-pointed MPP).  The discriminator is a single unlocked
#   full-span deny entry: with MPP=M the load must PASS (an unlocked entry
#   never constrains M), with MPP=U the SAME load must FAULT.
#
# ---------------------------------------------------------------------------
# PART 2 (CHECK 20..27) — THE IRQ_REST POP IS PMP-EXEMPT (ruled, not a bug).
#   The red team found the legacy interrupt stack path (IRQ_SV push / IRQ_REST
#   pop) carries no PMP term: pmp_d_rd/pmp_d_wr check EXECUTE + the four
#   sequencer states only, and the data_addr IRQ_SV/IRQ_REST arms have no
#   pmp_d_deny gate. GATEKEEPER RULING (Fable, 2026-07-29): this is INTENTIONAL
#   and now DOCUMENTED (p0_specs.md §4.1, TRM §5.7). The rationale:
#     * these states target the PRIVATE stack (TCM 0x8000-0xBFFF) by the
#       sp-validity contract — never the shared window whose side-effecting
#       reads (mutex claim / router CLAIM) are the entire point of D5;
#     * `iret` is M-only (u-gated, maindec.vhd:921) — no U-mode escape;
#     * IRQ_SV/IRQ_REST fire ONLY in legacy delivery (standard mode's MTRAP_SV
#       has zero memory transactions), and legacy-mode PMP faults dead-end in
#       TRAP_STATE by the frozen §4 — legacy delivery is not PMP-integrated;
#     * the ONLY way to reach IRQ_REST on a standard-mode PMP build is an
#       `iret`, which in standard mode is a DEFINED-BOUNDED software error
#       (p0_specs.md §1) — exempting its pop cannot wedge or escalate.
#   The same ruling dispositions the `iret` EXECUTE-cycle phantom read
#   (red-team F2): both are the iret sequence, both exempt (vesta.vhd
#   pmp_d_rd carries `and isr_ret = '0'`).
#
#   This test now PINS the exemption: the fenced-stack `iret` returns
#   NORMALLY (CHECK 25/26), while the plain U-view load positive control
#   (CHECK 22) still faults — proving the fence is real and the pop bypassed
#   it BY DESIGN. A future change that PMP-checked the pop would fault it,
#   resume at rt3_p2_flt, and FAIL (t4=24) — a change-detector on the ruling.
#
# BOUNDEDNESS: no loop.  Every probe either completes or lands in the handler,
# which resumes at s7.
#
# REGISTER CONTRACT:
#   s3 trap counter   s4/s5/s6 cause/mepc/mtval   s7 handler resume PC
#   s11 trap-count snapshot                       t4 CHECK ID
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define RT3_TORTOP   0x00020000
#define RT3_STK      0x0000BF00
#define RT3_SCRATCH  0x0000BE00

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, rt3_fail

#if defined(CORE_ENABLE_TRAPCSR) && defined(CORE_ENABLE_UMODE) && defined(CORE_ENABLE_PMP)

    .option push
    .option arch, +zicsr

    li   sp, 0xBFF0
    li   s3, 0

    li   t4, 1
    la   t0, rt3_handler
    csrw 0x305, t0
    csrr t1, 0x305
    bne  t1, t0, rt3_fail

    li   t4, 2
    csrw 0x7C0, x0
    csrr t1, 0x7C0
    bne  t1, x0, rt3_fail
    csrw 0x300, x0
    csrw 0x304, x0

    # seed the scratch word while nothing is fenced
    li   t0, RT3_SCRATCH
    li   t1, 0x5A5A0011
    sw   t1, 0(t0)

    # =====================================================================
    # PART 1 — MPRV with MPP = M.
    # entry0 = NAPOT with pmpaddr = all-ones  => the WHOLE address space,
    # R=W=X=0, UNLOCKED.  Nothing else is programmed, so this single entry
    # decides every access.
    # =====================================================================
    li   t4, 10
    li   t0, 0x3FFFFFFF             # 30 stored bits, all ones = full span
    csrw 0x3B0, t0
    csrr t1, 0x3B0
    bne  t1, t0, rt3_fail
    li   t4, 11
    li   t0, 0x00000018             # cfg0 = NAPOT, R=W=X=0, L=0
    csrw 0x3A0, t0
    csrr t1, 0x3A0
    bne  t1, t0, rt3_fail

    # ---- CHECK 12 : MPRV=1, MPP=M  =>  M view  =>  GRANTED ---------------
    li   t4, 12
    li   t2, RT3_SCRATCH
    mv   s11, s3
    la   s7, rt3_p1_mfault
    li   t1, 0x00021800             # MPRV=1, MPP=11 (M)
    csrw 0x300, t1
    lw   t3, 0(t2)
    csrw 0x300, x0
    li   t1, 0x5A5A0011
    bne  t3, t1, rt3_fail
    li   t4, 13
    bne  s3, s11, rt3_fail          # and it must not have trapped
    j    rt3_p1_u

rt3_p1_mfault:                      # MPRV=1/MPP=M was wrongly U-checked
    csrw 0x300, x0
    li   t4, 14
    j    rt3_fail

    # ---- CHECK 15 : MPRV=1, MPP=U  =>  U view  =>  DENIED ----------------
rt3_p1_u:
    li   t4, 15
    mv   s11, s3
    la   s7, rt3_p1_ufault
    li   t1, 0x00020000             # MPRV=1, MPP=00 (U)
    csrw 0x300, t1
    lw   t3, 0(t2)                  # must FAULT
    csrw 0x300, x0
    j    rt3_fail                   # granted: MPRV/MPP=U is not taking effect

rt3_p1_ufault:
    csrw 0x300, x0
    li   t4, 16
    addi t1, s11, 1
    bne  s3, t1, rt3_fail
    li   t4, 17
    li   t1, 5
    bne  s4, t1, rt3_fail
    li   t4, 18
    li   t1, RT3_SCRATCH
    bne  s6, t1, rt3_fail

    # =====================================================================
    # PART 2 — the IRQ_REST pop.
    # Rebuild the map: entry0 fences EXACTLY mem[sp] (NA4, no permissions),
    # entry1 is OFF and carries entry2's TOR base, entry2 grants everything
    # everything else in 0x0..0x1FFFF (so `iret`'s own phantom read of address 0 —
    # see pmprt2 — is granted and cannot confound this probe).
    # =====================================================================
    li   t4, 20
    li   s2, RT3_STK
    srli t0, s2, 2
    csrw 0x3B0, t0
    csrw 0x3B1, x0
    li   t0, RT3_TORTOP
    srli t0, t0, 2
    csrw 0x3B2, t0
    li   t0, 0x000F0010             # cfg2=R|W|X|TOR cfg1=OFF cfg0=NA4 no-perms
    csrw 0x3A0, t0
    csrr t1, 0x3A0
    bne  t1, t0, rt3_fail

    # plant the resume word BEFORE the fence can matter (M view, MPRV=0)
    la   t0, rt3_p2_ok
    sw   t0, 0(s2)

    # ---- CHECK 21 : POSITIVE CONTROL — a plain U-view load from mem[sp]
    #      must fault.  Without this, "no fault on the pop" could just mean
    #      the fence is misprogrammed.
    li   t4, 21
    mv   s11, s3
    la   s7, rt3_p2_ctlflt
    li   t1, 0x00020000             # MPRV=1, MPP=U
    csrw 0x300, t1
    lw   t3, 0(s2)
    csrw 0x300, x0
    j    rt3_fail                   # granted: the fence is wrong

rt3_p2_ctlflt:
    csrw 0x300, x0
    li   t4, 22
    li   t1, 5
    bne  s4, t1, rt3_fail
    li   t4, 23
    bne  s6, s2, rt3_fail           # mtval = mem[sp]'s address

    # ---- THE PROBE : `iret` under the SAME U data view. Its IRQ_REST pop
    #      reads mem[sp]. GATEKEEPER RULING (2026-07-29, p0_specs.md §4.1):
    #      legacy interrupt stack traffic (the IRQ_SV push / IRQ_REST pop) and
    #      iret's implicit stack access are OUT of PMP scope by design — they
    #      target the PRIVATE stack (TCM 0x8000-0xBFFF) by the sp-validity
    #      contract, iret is M-only (u-gated), and in standard mode iret is a
    #      DEFINED-BOUNDED software error (p0_specs.md §1). The D5 hazard is
    #      SHARED-WINDOW side-effecting reads; the stack is not that. So the
    #      pop is NOT PMP-checked and the iret RETURNS NORMALLY to mem[sp].
    #      This test PINS that exemption: the exempt return lands at
    #      rt3_p2_ok (PASS). s7 still points at rt3_p2_flt, so if a future
    #      change ever DID fault the pop, the handler would resume there and
    #      the test FAILS (t4=24) — a change-detector on the ruling.
    li   sp, RT3_STK
    mv   s11, s3
    la   s7, rt3_p2_flt
    li   t1, 0x00020000             # MPRV=1, MPP=U (stack fenced in this view)
    csrw 0x300, t1
    iret                            # exempt: pops mem[sp], returns to rt3_p2_ok
    j    rt3_fail                   # iret must not fall through

rt3_p2_flt:                         # the pop was CHECKED — exemption VIOLATED
    csrw 0x300, x0
    li   sp, 0xBFF0
    li   t4, 24
    j    rt3_fail

rt3_p2_ok:                          # <-- the exempt pop returned here: CORRECT
    csrw 0x300, x0
    li   sp, 0xBFF0
    li   t4, 25
    bne  s3, s11, rt3_fail          # the pop itself raised NO trap
    li   t4, 26                     # and the U-view lw positive control DID
    li   t1, 5                      #   fault earlier (CHECK 22 above), so the
    bne  s4, t1, rt3_fail           #   fence is real — the pop bypassed it

    li   t4, 27
    csrw 0x3A0, x0
    csrr t1, 0x3A0
    bne  t1, x0, rt3_fail
    li   t1, 0x00000001
    csrw 0x7C0, t1
    csrw 0x300, x0

    RVTEST_PASS

    .align 2
rt3_handler:
    csrr t0, 0x342
    addi s3, s3, 1
    mv   s4, t0
    csrr s5, 0x341
    csrr s6, 0x343
    csrw 0x341, s7
    mret

    .option pop

#else
    li   t4, 0
    j    rt3_fail
#endif

rt3_fail:
    RVTEST_FAIL

    # NOTE: RVTEST_CODE_END is 'unimp' (traps!) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
