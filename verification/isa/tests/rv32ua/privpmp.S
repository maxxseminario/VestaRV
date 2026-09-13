# See LICENSE for license details.

# VestaRV: PMP enforcement, TOR/NA4/NAPOT, causes 1/5/7, lock and MPRV
# ON-ONLY, needing a trapCsr, umode and pmp build. privpmpcs proves the CSR bank; this file proves the CHECK INTEGRATION in vesta.vhd. A U-mode load PMP denies gives mcause 5 with mtval = the data address and mepc = the load's own PC; a denied store gives mcause 7 under the same rule; a denied fetch gives mcause 1 with mtval = mepc = the faulting word's address. An UNLOCKED entry does not constrain M-mode, so all three pass from M under the identical map. With NO MATCH, M grants and U faults. PRIORITY: the LOWEST-numbered matching entry decides alone, which is why every fenced address is also inside the permissive TOR entry 4, so a highest-wins implementation grants them. NAPOT size decode is checked at the boundary, the last word inside a 16-byte region denied and the first word after it granted. mstatus.MPRV with MPP = U makes M-mode take the U view on a DATA access and MPRV = 0 restores the M view, while INSTRUCTION FETCH IS NEVER MPRV-REDIRECTED. A LOCKED entry enforces on M-mode and the lock holds against a rewrite.
# THE MAP, programmed once in M with addresses before cfg: entry 0 NA4 on &pvpp_fence_d with R = W = X = 0, the fenced data word; entry 1 NA4 on &pvpp_fenced_fn, the fenced code word; entry 2 NAPOT over pvpp_napot..+15, the boundary probe; entry 3 OFF at 0, the TOR base for entry 4; entry 4 TOR 0x00000000-0x0000FFFF with R = W = X = 1, everything else U may touch; entry 12 NA4 on 0x00010200 with R = W = X = 0 and L = 1, programmed LAST.
# ENTRY BUDGET: PMP LOCKS RELEASE ONLY AT RESET, so the one locked entry is programmed at the very end and covers an address no other check uses. Entries 0-11 stay unlocked throughout. The locked entry must sit ABOVE entry 4 in NUMBER but OUTSIDE entry 4's range in ADDRESS, and 0x10200 is past the TOR top of 0x10000, so no lower entry matches and entry 12 decides.
# BOUNDEDNESS: every check is a compare and branch with no polling loop anywhere, and each access that must not fault sets s7 to a dedicated "if this faults" label first, so an unexpected fault lands on a FAIL path instead of re-executing the faulting instruction forever.
# REGISTER CONTRACT, with standard mode pushing nothing because a U-mode sp is untrusted: s0 the NAPOT region base, s1 the U-side failure id with 0 meaning all U checks passed, s2 the no-match probe address and in the M phase the locked address, s3 the trap counter, s4 mcause, s5 mepc, s6 mtval, s7 the handler resume PC, s8 the expected mepc, s9 the M continuation after ECALL, s10 &pvpp_fence_d, s11 the expected U-side trap count, t4 the CHECK ID at every M-side comparison.
# HANDLER PROTOCOL: on an access fault the handler records cause, mepc and mtval, bumps s3 and resumes at s7 IN THE TRAPPED PRIVILEGE, by writing mepc from s7 and MRETing while MPP still holds it. On an ECALL it leaves with `jr s9` instead, so the U to M transition is one-way and the M flow continues with the pushed state intact.
# BUILD-TIME DISPATCH: assembled only with all three of -DCORE_ENABLE_TRAPCSR, -DCORE_ENABLE_UMODE and -DCORE_ENABLE_PMP on a staged pmp build; the #else arm fails immediately and loudly, and this file is deliberately not in the default runner array.

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define PVPP_NOMATCH  0x00010100     /* past the TOR top: no entry matches   */
#define PVPP_LOCKADDR 0x00010200     /* likewise; the LOCKED entry's target  */
#define PVPP_TORTOP   0x00010000     /* entry 4's upper bound                */

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity: prove the core runs before any privilege work ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, pvpp_fail

#if defined(CORE_ENABLE_TRAPCSR) && defined(CORE_ENABLE_UMODE) && defined(CORE_ENABLE_PMP)

    .option push
    .option arch, +zicsr

    li   sp, 0xBFF0
    li   s3, 0                      # trap counter
    li   s1, 0                      # U-side failure id

    # =====================================================================
    # CHECK 1/2 — arm mtvec, then opt into STANDARD delivery. Order is the
    # contract (a PMP fault is an EXCEPTION: in legacy mode it dead-ends in
    # the terminal TRAP_STATE, so nothing below may run until LEGACY = 0).
    # =====================================================================
    li   t4, 1
    la   t0, pvpp_handler
    csrw 0x305, t0
    csrr t1, 0x305
    bne  t1, t0, pvpp_fail

    li   t4, 2
    csrw 0x7C0, x0
    csrr t1, 0x7C0
    bne  t1, x0, pvpp_fail

    # =====================================================================
    # Seed the fenced data word BEFORE the map goes live, so CHECK 20 can
    # prove an M-mode read really reached memory.
    # =====================================================================
    la   s10, pvpp_fence_d
    li   t0, 0x5A5A0001
    sw   t0, 0(s10)
    la   s0, pvpp_napot
    li   t0, 0x5A5A0002
    sw   t0, 0(s0)
    li   t0, 0x5A5A0003
    sw   t0, 12(s0)                 # last word INSIDE the NAPOT region
    li   t0, 0x5A5A0004
    sw   t0, 16(s0)                 # first word AFTER the NAPOT region

    # =====================================================================
    # CHECK 3..6 — PROGRAM THE MAP. Addresses first, cfg last: a cfg byte is
    # what makes an entry live, so no half-configured region is ever active.
    # =====================================================================
    li   t4, 3
    srli t0, s10, 2                 # pmpaddr0 = &pvpp_fence_d >> 2   (NA4)
    csrw 0x3B0, t0
    csrr t1, 0x3B0
    bne  t1, t0, pvpp_fail

    li   t4, 4
    la   t2, pvpp_fenced_fn
    srli t0, t2, 2                  # pmpaddr1 = &pvpp_fenced_fn >> 2 (NA4)
    csrw 0x3B1, t0
    csrr t1, 0x3B1
    bne  t1, t0, pvpp_fail

    li   t4, 5
    srli t0, s0, 2                  # pmpaddr2 = (base>>2) | 1  => 16-byte NAPOT
    ori  t0, t0, 1
    csrw 0x3B2, t0
    csrr t1, 0x3B2
    bne  t1, t0, pvpp_fail

    csrw 0x3B3, x0                  # pmpaddr3 = 0 : entry 4's TOR BASE
    li   t0, PVPP_TORTOP
    srli t0, t0, 2                  # pmpaddr4 = 0x10000 >> 2 : TOR TOP
    csrw 0x3B4, t0

    li   t4, 6
    li   t0, 0x00181010             # cfg3=OFF cfg2=NAPOT cfg1=NA4 cfg0=NA4
    csrw 0x3A0, t0
    csrr t1, 0x3A0
    bne  t1, t0, pvpp_fail
    li   t0, 0x0000000F             # cfg4 = R|W|X|TOR
    csrw 0x3A1, t0
    csrr t1, 0x3A1
    bne  t1, t0, pvpp_fail

    # =====================================================================
    # CHECK 20..24 — AN UNLOCKED ENTRY DOES NOT CONSTRAIN M-MODE. Every one
    # of these addresses is denied to U by entries 0-2; in M they all pass.
    # (Also the "no match in M grants" half of the frozen no-match rule.)
    # =====================================================================
    la   s7, pvpp_m20f              # if any of these faults, land there
    li   t4, 20
    lw   t0, 0(s10)                 # M load  from the fenced DATA word
    li   t1, 0x5A5A0001
    bne  t0, t1, pvpp_fail
    li   t4, 21
    li   t0, 0x5A5A00FF
    sw   t0, 0(s10)                 # M store to the fenced DATA word
    lw   t1, 0(s10)
    bne  t1, t0, pvpp_fail
    li   t0, 0x5A5A0001
    sw   t0, 0(s10)                 # restore the sentinel
    li   t4, 22
    la   t2, pvpp_fenced_fn
    jalr ra, t2, 0                  # M fetch of the fenced CODE word
    li   t4, 23
    lw   t0, 12(s0)                 # M load from inside the NAPOT region
    li   t1, 0x5A5A0003
    bne  t0, t1, pvpp_fail
    li   t4, 24
    li   s2, PVPP_NOMATCH
    lw   t0, 0(s2)                  # M load where NO entry matches
    j    pvpp_uenter

pvpp_m20f:                          # any M-mode fault above is a FAIL
    li   t4, 25
    j    pvpp_fail

    # =====================================================================
    # ---- ENTER U-MODE. MPP=00, MIE=0, MPRV=0, TW=0. -------------------
    # =====================================================================
pvpp_uenter:
    li   t4, 30
    csrw 0x300, x0
    la   s9, pvpp_m2                # where the ECALL handler resumes the M flow
    la   t0, pvpp_uentry
    csrw 0x341, t0
    mret                            # ---- now in U-MODE ----

# =========================================================================
# U-MODE BODY. Every fenced access sets {s7 = resume, s8 = expected mepc,
# s11 = expected trap count} first. A U check that fails records its id in s1
# and exits via ECALL; M then FAILs with t4 = s1. Nothing here loops.
# =========================================================================
pvpp_uentry:
    # ---- U CHECK 40..43 : DENIED LOAD -> cause 5 ------------------------
    la   s7, pvpp_u1r
    la   s8, pvpp_u1a
    li   s11, 1
pvpp_u1a:
    lw   t0, 0(s10)
pvpp_u1r:
    li   s1, 40
    bne  s3, s11, pvpp_uexit        # a trap must have been delivered
    li   s1, 41
    li   t1, 5
    bne  s4, t1, pvpp_uexit         # mcause = 5 (load access fault)
    li   s1, 42
    bne  s5, s8, pvpp_uexit         # mepc  = the load's own PC
    li   s1, 43
    bne  s6, s10, pvpp_uexit        # mtval = the byte-precise data address

    # ---- U CHECK 44..47 : DENIED STORE -> cause 7 -----------------------
    la   s7, pvpp_u2r
    la   s8, pvpp_u2a
    li   s11, 2
pvpp_u2a:
    sw   t0, 0(s10)
pvpp_u2r:
    li   s1, 44
    bne  s3, s11, pvpp_uexit
    li   s1, 45
    li   t1, 7
    bne  s4, t1, pvpp_uexit         # mcause = 7 (store access fault)
    li   s1, 46
    bne  s5, s8, pvpp_uexit
    li   s1, 47
    bne  s6, s10, pvpp_uexit

    # ---- U CHECK 48..51 : DENIED FETCH -> cause 1 -----------------------
    # The jalr itself RETIRES; the fault is on the fetch of the target word,
    # so mepc = mtval = that word's address (NOT the jalr's PC).
    la   s7, pvpp_u3r
    la   t2, pvpp_fenced_fn
    mv   s8, t2
    li   s11, 3
    jalr ra, t2, 0
pvpp_u3r:
    li   s1, 48
    bne  s3, s11, pvpp_uexit
    li   s1, 49
    li   t1, 1
    bne  s4, t1, pvpp_uexit         # mcause = 1 (instruction access fault)
    li   s1, 50
    bne  s5, s8, pvpp_uexit         # mepc  = the faulting fetch address
    li   s1, 51
    bne  s6, s8, pvpp_uexit         # mtval = the same address

    # ---- U CHECK 52..55 : NO MATCH IN U FAULTS --------------------------
    la   s7, pvpp_u4r
    la   s8, pvpp_u4a
    li   s11, 4
pvpp_u4a:
    lw   t0, 0(s2)
pvpp_u4r:
    li   s1, 52
    bne  s3, s11, pvpp_uexit
    li   s1, 53
    li   t1, 5
    bne  s4, t1, pvpp_uexit
    li   s1, 54
    bne  s5, s8, pvpp_uexit
    li   s1, 55
    bne  s6, s2, pvpp_uexit

    # ---- U CHECK 56..59 : NAPOT — LAST WORD INSIDE IS DENIED ------------
    addi t2, s0, 12
    la   s7, pvpp_u5r
    la   s8, pvpp_u5a
    li   s11, 5
pvpp_u5a:
    lw   t0, 0(t2)
pvpp_u5r:
    li   s1, 56
    bne  s3, s11, pvpp_uexit
    li   s1, 57
    li   t1, 5
    bne  s4, t1, pvpp_uexit
    li   s1, 58
    bne  s5, s8, pvpp_uexit
    li   s1, 59
    bne  s6, t2, pvpp_uexit         # mtval = napot_base + 12

    # ---- U CHECK 60/61 : NAPOT — FIRST WORD AFTER IS GRANTED ------------
    # (entry 2 must NOT cover it; entry 4 then grants R.) A size decode that
    # is one power of two too LARGE denies it and lands on pvpp_u6f; one too
    # SMALL would have granted +12 above and failed CHECK 56 instead.
    la   s7, pvpp_u6f
    addi t2, s0, 16
    lw   t0, 0(t2)
    li   s1, 61
    li   t1, 0x5A5A0004
    bne  t0, t1, pvpp_uexit
    j    pvpp_u7
pvpp_u6f:
    li   s1, 60
    j    pvpp_uexit

    # ---- U CHECK 62/63 : an ORDINARY U access still works ---------------
pvpp_u7:
    la   s7, pvpp_u7f
    la   t2, pvpp_ok
    li   t1, 0x0000ABCD
    sw   t1, 0(t2)
    lw   t0, 0(t2)
    bne  t0, t1, pvpp_u7bad
    li   s1, 0                      # every U check passed
    j    pvpp_uexit
pvpp_u7f:
    li   s1, 62
    j    pvpp_uexit
pvpp_u7bad:
    li   s1, 63

pvpp_uexit:
    ecall                           # -> M (handler leaves with jr s9)
    j    pvpp_uexit                 # resuming HERE means U->M never happened

# =========================================================================
# ---- BACK IN M ----------------------------------------------------------
# =========================================================================
pvpp_m2:
    li   t4, 64                     # the U body's own verdict
    mv   t4, s1
    bne  s1, x0, pvpp_fail

    li   t4, 65                     # exactly 5 access faults + 1 ECALL
    li   t1, 6
    bne  s3, t1, pvpp_fail

    li   t4, 66                     # we really are back in M
    csrr t1, 0x7C0
    bne  t1, x0, pvpp_fail

    # =====================================================================
    # CHECK 70..77 — mstatus.MPRV. With MPRV=1 and MPP=U a DATA access is
    # checked at U; an instruction FETCH never is.
    # =====================================================================
    la   s7, pvpp_m70f
    li   t4, 70
    lw   t0, 0(s10)                 # MPRV=0: the M view still passes
    j    pvpp_m71
pvpp_m70f:
    li   t4, 71
    j    pvpp_fail

pvpp_m71:
    li   t1, 0x00020000             # MPRV=1, MPP=00 (U)
    csrw 0x300, t1
    la   s7, pvpp_m71r
    la   s8, pvpp_m71a
    addi t3, s3, 1
pvpp_m71a:
    lw   t0, 0(s10)                 # SAME load, now checked at U -> fault
pvpp_m71r:
    csrw 0x300, x0                  # clear MPRV FIRST: MRET back to M leaves
                                    # MPRV set but forces MPP=00, so the very
                                    # next data access would be U-checked too.
    li   t4, 72
    bne  s3, t3, pvpp_fail
    li   t4, 73
    li   t1, 5
    bne  s4, t1, pvpp_fail
    li   t4, 74
    bne  s5, s8, pvpp_fail
    li   t4, 75
    bne  s6, s10, pvpp_fail

    li   t4, 76                     # MPRV cleared: the M view is back
    la   s7, pvpp_m76f
    lw   t0, 0(s10)
    li   t1, 0x5A5A0001
    bne  t0, t1, pvpp_fail
    j    pvpp_m77
pvpp_m76f:
    li   t4, 77
    j    pvpp_fail

pvpp_m77:                           # FETCH is NOT MPRV-redirected: executing
    li   t1, 0x00020000             # a U-X-denied word from M under MPRV=1
    csrw 0x300, t1                  # must still be allowed.
    la   s7, pvpp_m78f
    addi t3, s3, 0
    la   t2, pvpp_fenced_fn
    jalr ra, t2, 0
    csrw 0x300, x0                  # restore before any data access
    li   t4, 78
    bne  s3, t3, pvpp_fail
    j    pvpp_m80
pvpp_m78f:
    csrw 0x300, x0
    li   t4, 79
    j    pvpp_fail

    # =====================================================================
    # CHECK 80..86 — L (LOCK). LAST in the file: a lock releases only at
    # RESET. A LOCKED entry enforces on M-mode; the lock itself is immutable.
    # =====================================================================
pvpp_m80:
    li   s2, PVPP_LOCKADDR
    la   s7, pvpp_m80f
    li   t4, 80
    lw   t0, 0(s2)                  # nothing matches yet -> M grants
    j    pvpp_m81
pvpp_m80f:
    li   t4, 81
    j    pvpp_fail

pvpp_m81:
    srli t0, s2, 2
    csrw 0x3BC, t0                  # pmpaddr12 = PVPP_LOCKADDR >> 2
    li   t0, 0x00000090             # cfg12 = L | NA4, R=W=X=0
    csrw 0x3A3, t0
    li   t4, 82
    csrr t1, 0x3A3
    bne  t1, t0, pvpp_fail

    la   s7, pvpp_m83r
    la   s8, pvpp_m83a
    addi t3, s3, 1
pvpp_m83a:
    lw   t0, 0(s2)                  # THE POINT: locked entry denies M
pvpp_m83r:
    li   t4, 83
    bne  s3, t3, pvpp_fail
    li   t4, 84
    li   t1, 5
    bne  s4, t1, pvpp_fail
    li   t4, 85
    bne  s5, s8, pvpp_fail
    li   t4, 86
    bne  s6, s2, pvpp_fail

    li   t4, 87                     # the lock holds against a rewrite
    csrw 0x3A3, x0
    csrr t1, 0x3A3
    li   t0, 0x00000090
    bne  t1, t0, pvpp_fail

    # =====================================================================
    # RESTORE — release entries 0-11 and go back to LEGACY delivery, so an
    # ON build running the rest of the suite is provably unaffected. Entry 12
    # stays locked (hardware rule) but covers only PVPP_LOCKADDR.
    # =====================================================================
    li   t4, 88
    csrw 0x3A0, x0
    csrw 0x3A1, x0
    csrr t1, 0x3A0
    bne  t1, x0, pvpp_fail
    li   t1, 0x00000001
    csrw 0x7C0, t1
    csrw 0x300, x0
    csrw 0x304, x0
    li   t4, 89
    csrr t1, 0x7C0
    li   t0, 0x00000001
    bne  t1, t0, pvpp_fail

    RVTEST_PASS

    # =====================================================================
    # The mtvec handler and the fenced code word. Both are placed AFTER the
    # RVTEST_PASS spin loop, so they can only be reached deliberately.
    # =====================================================================
    .align 2
pvpp_handler:
    csrr s4, 0x342                  # mcause
    csrr s5, 0x341                  # mepc
    csrr s6, 0x343                  # mtval
    addi s3, s3, 1
    li   t0, 8                      # ECALL from U
    beq  s4, t0, pvpp_hdl_ecall
    li   t0, 11                     # ECALL from M
    beq  s4, t0, pvpp_hdl_ecall
    csrw 0x341, s7                  # access fault: resume at s7 in the
    mret                            # TRAPPED privilege (MPP still holds it)
pvpp_hdl_ecall:
    jr   s9                         # one-way exit into the M flow

    # The FENCED CODE WORD: exactly ONE instruction, word-aligned, so entry
    # 1's NA4 region is precisely this fetch. `ret` redirects the PC, so the
    # word after it is never fetched either.
    .align 2
pvpp_fenced_fn:
    ret
    .align 4
    nop

    .option pop

#else
    # OFF / trapCsr / trapCsr+umode build: the twenty PMP CSRs are unknown
    # addresses and this core DEAD-ENDS an illegal instruction in the terminal
    # TRAP_STATE, so none of the above may be assembled. Reaching here means
    # the ON/OFF staging discipline was violated.
    li   t4, 0
    j    pvpp_fail
#endif

pvpp_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF (t4 = failing check id)

    # NOTE: RVTEST_CODE_END is 'unimp' (traps!) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

    .align 4
pvpp_fence_d:  .word 0              # entry 0 (NA4) — its own 16-byte block
               .word 0, 0, 0
    .align 4
pvpp_napot:    .word 0, 0, 0, 0     # entry 2 (16-byte NAPOT), 16-byte aligned
pvpp_after:    .word 0, 0, 0, 0     # the first word here is JUST PAST entry 2
pvpp_ok:       .word 0              # a plainly-permitted data word

  TEST_DATA
RVTEST_DATA_END
