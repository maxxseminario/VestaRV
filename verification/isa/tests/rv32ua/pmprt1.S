# See LICENSE for license details.

#*****************************************************************************
# pmprt1.S   (P3 RED TEAM — the MRET-TARGET FETCH is checked at the OLD
#             privilege, so U executes ONE X-denied instruction)
#-----------------------------------------------------------------------------
# ON-ONLY DIRECTED TEST (needs a trapCsr+umode+pmp build).
#
# THE HYPOTHESIS.  vesta's fetch check is
#     f_addr   = pc_next
#     f_priv_m = trap_priv_mode          (vesta.vhd:1861-1862)
# sampled into `pmp_f_deny_r` on EVERY clk_cpu edge (vesta.vhd:1878-1889).
# MTRAP_RET drives pc_next = mepc and `pc_en <= '1'` (vesta.vhd:3202-3207), so
# the MRET TARGET's fetch transaction issues DURING MTRAP_RET — but the
# privilege POP (csr_unit `mret_we` arm, csr_unit.vhd:1006-1029) lands on the
# SAME clock edge that ends MTRAP_RET.  The fetch is therefore permission-
# checked at the OLD privilege (M) and CONSUMED at the NEW one (U).
#
# THE VEHICLE.  Entry 0 fences ONE code word (NA4, R=1 W=0 X=0) — U may READ
# it but must never EXECUTE it.  M then MRETs straight at that word.
#   * SPEC-CORRECT: an instruction access fault (cause 1) with
#     mepc = mtval = the fenced word's address, taken FROM U.
#   * CURRENT RTL (the hypothesis): the word EXECUTES in U.  It is
#     `addi s10, s10, 1`, so s10 is the escape witness; the next word
#     (outside the NA4 region, so legitimately fetchable in U) jumps to the
#     common exit and the test reports.
# Either way the flow is BOUNDED — there is no loop anywhere in this file.
#
# CLASSIFICATION IF IT BITES: a one-instruction execute-permission ESCAPE.
# Not reachable by U alone (U controls neither mepc nor MPP), so it is a
# privilege-boundary DEVIATION rather than a U-exploitable hole — but it is
# exactly the window a "revoke X, then resume the task" handler relies on.
#
# THE MAP:
#   entry 0  NA4  &rt1_xword   R=1 W=0 X=0   the fenced CODE word
#   entry 1  OFF  0                          entry 2's TOR base
#   entry 2  TOR  0x00000000-0x0001FFFF  R=W=X=1
#
# REGISTER CONTRACT (standard mode pushes NOTHING — a U sp is untrusted):
#   s3  trap counter          s4/s5/s6  cause/mepc/mtval of the LAST non-ECALL
#   s7  handler resume PC     s9  M continuation after ECALL
#   s10 ESCAPE WITNESS (must stay 0)      t4  CHECK ID
#
# BUILD-TIME DISPATCH: ON iff -DCORE_ENABLE_TRAPCSR -DCORE_ENABLE_UMODE
# -DCORE_ENABLE_PMP.  Deliberately NOT in the default behavioral_mp array.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define RT1_TORTOP   0x00020000

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity ------------------------------------------------
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, rt1_fail

#if defined(CORE_ENABLE_TRAPCSR) && defined(CORE_ENABLE_UMODE) && defined(CORE_ENABLE_PMP)

    .option push
    .option arch, +zicsr

    li   sp, 0xBFF0
    li   s3, 0
    li   s10, 0                     # THE ESCAPE WITNESS

    # ---- CHECK 1/2 : mtvec, then STANDARD delivery ----------------------
    li   t4, 1
    la   t0, rt1_handler
    csrw 0x305, t0
    csrr t1, 0x305
    bne  t1, t0, rt1_fail

    li   t4, 2
    csrw 0x7C0, x0
    csrr t1, 0x7C0
    bne  t1, x0, rt1_fail

    # ---- CHECK 3/4 : the map (addresses first, cfg last) ----------------
    li   t4, 3
    la   s2, rt1_xword
    srli t0, s2, 2
    csrw 0x3B0, t0
    csrr t1, 0x3B0
    bne  t1, t0, rt1_fail
    csrw 0x3B1, x0                  # entry 2's TOR base
    li   t0, RT1_TORTOP
    srli t0, t0, 2
    csrw 0x3B2, t0

    li   t4, 4
    li   t0, 0x000F0011             # cfg2=R|W|X|TOR cfg1=OFF cfg0=R|NA4
    csrw 0x3A0, t0
    csrr t1, 0x3A0
    bne  t1, t0, rt1_fail

    # ---- CHECK 5 : the fence really is X-denied to U --------------------
    # POSITIVE CONTROL for the vehicle.  A plain U-mode JALR into the same
    # word MUST fault with cause 1 (this is the path privpmp already proves).
    # If this control does not fire the map is wrong and CHECK 10 proves
    # nothing.  Entered by MRET at rt1_uctl, which IS a permitted word.
    li   t4, 5
    la   s9, rt1_m1
    la   s7, rt1_uexit
    la   t0, rt1_uctl
    csrw 0x341, t0
    csrw 0x300, x0                  # MPP=00 (U), MIE=0, MPRV=0
    mret                            # ---- U ----

rt1_m1:
    li   t4, 6
    li   t1, 2                      # 1 access fault + 1 ECALL
    bne  s3, t1, rt1_fail
    li   t4, 7
    li   t1, 1
    bne  s4, t1, rt1_fail           # cause 1 on the control JALR
    li   t4, 8
    bne  s5, s2, rt1_fail
    li   t4, 9
    bne  s6, s2, rt1_fail

    # =====================================================================
    # CHECK 10..14 — THE ATTACK.  MRET STRAIGHT AT the fenced word.
    # =====================================================================
    la   s9, rt1_m2
    la   s7, rt1_uexit
    csrw 0x341, s2                  # mepc = &rt1_xword
    csrw 0x300, x0                  # MPP=00 (U)
    mret                            # ---- U, at the X-denied word ----

rt1_m2:
    li   t4, 10
    bne  s10, x0, rt1_fail          # THE VERDICT: the fenced word EXECUTED
    li   t4, 11
    li   t1, 4                      # 2 (control) + 1 access fault + 1 ECALL
    bne  s3, t1, rt1_fail
    li   t4, 12
    li   t1, 1
    bne  s4, t1, rt1_fail           # cause 1 (instruction access fault)
    li   t4, 13
    bne  s5, s2, rt1_fail           # mepc  = the fenced word
    li   t4, 14
    bne  s6, s2, rt1_fail           # mtval = the fenced word

    # ---- restore: release the map, back to LEGACY delivery --------------
    li   t4, 15
    csrw 0x3A0, x0
    csrr t1, 0x3A0
    bne  t1, x0, rt1_fail
    li   t1, 0x00000001
    csrw 0x7C0, t1
    csrw 0x300, x0

    RVTEST_PASS

    # =====================================================================
    # U-mode fragments + the handler.  All AFTER the PASS spin loop, so they
    # are reachable only deliberately (by MRET or by a hardware trap).
    # =====================================================================
    .align 2
rt1_uctl:                           # CONTROL: an ordinary U-mode fetch fault
    la   t2, rt1_xword
    jalr ra, t2, 0
rt1_uexit:
    ecall
    j    rt1_uexit                  # resuming here means U->M never happened

    # THE FENCED CODE WORD — exactly one word, its own NA4 region.
    .align 2
rt1_xword:
    addi s10, s10, 1                # <-- MUST NEVER EXECUTE
    j    rt1_uexit                  # (this word is OUTSIDE the NA4 region)

    .align 2
rt1_handler:
    csrr t0, 0x342                  # mcause
    addi s3, s3, 1
    li   t1, 8
    beq  t0, t1, rt1_hdl_ecall      # ECALL from U
    li   t1, 11
    beq  t0, t1, rt1_hdl_ecall      # ECALL from M
    mv   s4, t0
    csrr s5, 0x341
    csrr s6, 0x343
    csrw 0x341, s7                  # resume in the TRAPPED privilege
    mret
rt1_hdl_ecall:
    jr   s9

    .option pop

#else
    li   t4, 0
    j    rt1_fail
#endif

rt1_fail:
    RVTEST_FAIL

    # NOTE: RVTEST_CODE_END is 'unimp' (traps!) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
