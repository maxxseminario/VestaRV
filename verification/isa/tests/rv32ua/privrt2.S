# See LICENSE for license details.

#*****************************************************************************
# privrt2.S   (P2 RED TEAM — PRIVILEGE-STATE INTEGRITY + the mcounteren surface)
#-----------------------------------------------------------------------------
# ON-ONLY DIRECTED TEST (needs a trapCsr+umode build).  Companion to privrt1
# (which owns the trap-entry side-effect class); this file owns the state
# machine around `priv` and the counter-access surface, filling the holes the
# P2 test set leaves open:
#
#   PHASE A — MPP IS PUSHED FROM THE LIVE PRIVILEGE, NOT LEFT ALONE.
#       csr_unit's trap-entry arm is `mst_mpp <= priv_m & priv_m`.  A trap
#       taken IN M must therefore OVERWRITE a previously-staged MPP=00 with
#       11.  Nothing in privumode/privucsr pins that direction: they only ever
#       trap from U (where the push happens to agree with the staged value).
#       The seed p2rt_mppush pins it from the other side.
#       This is also the spec's "an inner trap destroys the outer mstatus" —
#       software must save it — recorded here as a property, not a bug.
#
#   PHASE B — AN INTERRUPT DELIVERED TO A U-MODE HART.
#       COMPLETELY UNCOVERED before this file: privirq takes msip in M only.
#       Proven here: mcause = 0x80000003, the PUSHED mstatus carries MPP=00
#       (the interrupted privilege was U) and MPIE=1 (U was running with
#       MIE=1), the handler MRETs and U RESUMES.  mepc is a resume PC, so it
#       is checked as a RANGE inside the U block rather than an exact word —
#       the interrupt is taken at whichever U instruction retires first.
#
#   PHASE C — THE csr_addr(9:8) COMPARATOR vs A FULLY-OPEN mcounteren.
#       With mcounteren = 0x1F every USER view (cycle/time/instret/
#       hpmcounter3-4 and all five h-forms) must read in U, while the MACHINE
#       views of the same counters (0xB00 mcycle, 0xB80 mcycleh) and
#       mcountinhibit (0x320) must still trap.  That is the one comparator
#       doing its job with the counter gate wide open — the exact combination
#       no other test reaches.  hpmcounter5 / hpmcounter5h (0xC05 / 0xC85) are
#       the CONTRACT-SILENT ruling in maindec: mcounteren bits 5-31 are WARL 0,
#       so those addresses can NEVER be enabled and must trap even at 0x1F.
#
#   PHASE D — mcounteren BIT INDEPENDENCE.
#       privucsr proves CY+HPM3 together (with TM off).  Here TM and HPM4 are
#       enabled TOGETHER while CY/IR/HPM3 stay off, then IR alone with TM off:
#       across the two files each of the five bits is shown to gate its own
#       CSR and only its own.  The seed p2rt_ucnttm drops the TM term.
#
# EVERY failure path is a bounded compare-and-branch into RVTEST_FAIL: the U
# code carries its own expected trap count in s11 and re-checks it after each
# poison, so "a poison that failed to trap" is caught IN U, immediately.
#
# REGISTER CONTRACT (standard mode pushes NOTHING; M and U share the regfile):
#   s0  the poison's own address — published by the U code, checked as mepc
#   s1  U-mode witness word;  s2  handler address
#   s3  trap counter (handler increments)
#   s4  mcause captured in the handler;  s5  mepc captured in the handler
#   s6  mstatus captured INSIDE the trap (the PUSHED state)
#   s7  trap-count snapshot around must-NOT-trap reads
#   s8  CLINT msip[hart 0] (0x5000)
#   s9  M-mode continuation address (handler `jr s9` on a U ECALL)
#   s11 the U code's EXPECTED trap count
#   t4  CHECK ID at every comparison
#
# BUILD-TIME DISPATCH: ON iff BOTH -DCORE_ENABLE_TRAPCSR and -DCORE_ENABLE_UMODE
# are appended to RISCV_GCC_OPTS.  privrt2 is deliberately NOT in the default
# behavioral_mp runner array, so the #else arm must never execute.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity: prove the core runs before any privilege work ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, pv2_fail

#if defined(CORE_ENABLE_TRAPCSR) && defined(CORE_ENABLE_UMODE)

    .option push
    .option arch, +zicsr

    li   sp, 0xBFF0
    li   s0, 0
    li   s1, 0
    li   s3, 0
    li   s11, 0
    li   s8, 0x00005000             # CLINT msip[hart 0]
    li   a1, 0
    li   a2, 0

    li   t4, 1                      # arm mtvec BEFORE opting into standard mode
    la   s2, pv2_handler
    csrw 0x305, s2
    csrr t2, 0x305
    bne  t2, s2, pv2_fail

    li   t4, 2                      # STANDARD delivery (mtrapctl.LEGACY = 0)
    csrw 0x7C0, x0
    csrr t2, 0x7C0
    bne  t2, x0, pv2_fail

    li   t4, 3                      # quiet machine state
    csrw 0x300, x0
    csrw 0x304, x0
    csrw 0x306, x0
    csrr t2, 0x300
    bne  t2, x0, pv2_fail

    # =====================================================================
    # PHASE A — MPP is pushed from the LIVE privilege.  Stage MPP = 00 (as
    # software would just before an MRET into U), then take an
    # illegal-instruction trap IN M.  The pushed MPP must read 11.
    # =====================================================================
    li   t4, 4
    csrw 0x300, x0                  # MPP = 00 staged, MIE = 0
    csrr t2, 0x300
    bne  t2, x0, pv2_fail

    li   t4, 5
    la   s0, pv2_pa
pv2_pa:
    .word 0xFFFFFFFF                # illegal instruction, taken in M
    li   t3, 1
    bne  s3, t3, pv2_fail           # it must have trapped exactly once

    li   t4, 6                      # cause / mepc of the M-mode exception
    li   t3, 2
    bne  s4, t3, pv2_fail
    bne  s5, s0, pv2_fail

    li   t4, 7                      # THE CHECK: MPP pushed 11, not the
    srli t2, s6, 11                 #   staged 00.  [seed p2rt_mppush]
    andi t2, t2, 3
    li   t3, 3
    bne  t2, t3, pv2_fail

    li   t4, 8                      # the staged 00 really is GONE: the handler
    csrr t2, 0x300                  #   MRETed with MPP = 11, so it returned to
    srli t2, t2, 11                 #   M and left MPP <- 00 behind (the second
    andi t2, t2, 3                  #   half of the MRET contract, from the M->M
    bne  t2, x0, pv2_fail           #   side).  The pending U transition is dead.

    # =====================================================================
    # PHASE B — an interrupt delivered to a U-MODE hart.
    # msip[0] is raised while M still has MIE = 0, so nothing is delivered in
    # M; the MRET into U sets MIE <- MPIE = 1 and the trap lands in U.
    # =====================================================================
    li   t4, 10
    li   t1, 0x00000008
    csrw 0x304, t1                  # mie.MSIE
    li   t1, 1
    sw   t1, 0(s8)                  # raise msip[0]
    li   t2, 4096                   # bounded: the level crosses the registered
pv2_wait_mip:                       #   tile boundary
    csrr t0, 0x344
    andi t0, t0, 0x8
    bnez t0, pv2_armed
    addi t2, t2, -1
    bnez t2, pv2_wait_mip
    j    pv2_fail                   # mip never mirrored msip
pv2_armed:

    li   t4, 11                     # MPIE = 1, MPP = 00  ->  MRET: priv <- U,
    li   t1, 0x00000080             #   MIE <- 1
    csrw 0x300, t1
    csrr t2, 0x300
    bne  t2, t1, pv2_fail

    li   t4, 12
    li   s3, 0                      # restart the trap counter for PHASE B
    li   s11, 0
    la   s9, pv2_mb
    la   t0, pv2_ub
    csrw 0x341, t0
    mret                            # ---- U-MODE, MIE = 1, msip pending ----

pv2_ub:
    li   s1, 0x11110000             # retires; the interrupt is taken around here
    nop
    nop
    nop
    li   t4, 13
    li   t3, 1
    bne  s3, t3, pv2_fail           # the U-mode interrupt must have arrived

    li   t4, 22                     # AND WE ARE STILL IN U.  The handler MRETed
    addi s11, s11, 1                #   with the PUSHED MPP; if that push had
    la   s0, pv2_ubp                #   recorded M instead of the live U, the
pv2_ubp:                            #   MRET would have escalated us to M for
    csrr t0, 0x300                  #   good and this machine-CSR read would
    li   t3, 2                      #   SUCCEED.  [seed p2rt_mppush]
    bne  s3, t3, pv2_fail

    ecall                           # -> M
    j    pv2_fail

pv2_mb:
    li   t4, 14                     # machine SOFTWARE interrupt.  a1/a2 are the
    li   t3, 0x80000003             #   INTERRUPT's own snapshots — s4/s5/s6 have
    bne  a1, t3, pv2_fail           #   since been overwritten by the U ECALL.

    li   t4, 15                     # the PUSHED mstatus: MPP = 00, i.e. the
    srli t2, a2, 11                 #   INTERRUPTED privilege was U
    andi t2, t2, 3
    bne  t2, x0, pv2_fail

    li   t4, 16                     # ... and MPIE = 1: U really was running
    srli t2, a2, 7                  #   with mstatus.MIE = 1
    andi t2, t2, 1
    li   t3, 1
    bne  t2, t3, pv2_fail

    li   t4, 19                     # exactly TWO traps in the U-mode leg (the
    li   t3, 2                      #   interrupt + the CHECK-22 poison); the
                                    #   ECALL leaves via `jr s9`, uncounted
    bne  s3, t3, pv2_fail

    li   t4, 17                     # the U code ran, and RESUMED after the
    li   t3, 0x11110000             #   handler MRETed back into U (the ECALL
    bne  s1, t3, pv2_fail           #   that got us here is three insns later)

    li   t4, 18                     # msip was cleared by the handler
    csrr t0, 0x344
    andi t0, t0, 0x8
    bnez t0, pv2_fail
    csrw 0x304, x0                  # mie = 0
    csrw 0x300, x0                  # mstatus = 0 (MIE off, MPP 00)

    # =====================================================================
    # PHASE C — the csr_addr(9:8) comparator with mcounteren WIDE OPEN.
    # =====================================================================
    li   t4, 20
    li   t1, 0x0000001F
    csrw 0x306, t1
    csrr t2, 0x306
    bne  t2, t1, pv2_fail

    li   t4, 21
    li   s3, 0
    li   s11, 0
    la   s9, pv2_mc
    la   t0, pv2_uc
    csrw 0x341, t0
    mret                            # ---- U-MODE, mcounteren = 0x1F ----

pv2_uc:
    li   t4, 30                     # all TEN user views must read without a trap
    mv   s7, s3
    csrr t0, 0xC00                  # cycle
    csrr t0, 0xC80                  # cycleh
    csrr t0, 0xC01                  # time
    csrr t0, 0xC81                  # timeh
    csrr t0, 0xC02                  # instret
    csrr t0, 0xC82                  # instreth
    csrr t0, 0xC03                  # hpmcounter3
    csrr t0, 0xC83                  # hpmcounter3h
    csrr t0, 0xC04                  # hpmcounter4
    csrr t0, 0xC84                  # hpmcounter4h
    bne  s3, s7, pv2_fail           # any trap here => an enable was ignored

    li   t4, 31                     # MACHINE view of the SAME counter: mcycle
    addi s11, s11, 1
    la   s0, pv2_c1
pv2_c1:
    csrr t0, 0xB00
    bne  s3, s11, pv2_fail

    li   t4, 32                     # mcycleh
    addi s11, s11, 1
    la   s0, pv2_c2
pv2_c2:
    csrr t0, 0xB80
    bne  s3, s11, pv2_fail

    li   t4, 33                     # mcountinhibit (0x320)
    addi s11, s11, 1
    la   s0, pv2_c3
pv2_c3:
    csrr t0, 0x320
    bne  s3, s11, pv2_fail

    li   t4, 34                     # hpmcounter5: mcounteren bit 5 is WARL 0,
    addi s11, s11, 1                #   so this can NEVER be enabled
    la   s0, pv2_c4
pv2_c4:
    csrr t0, 0xC05
    bne  s3, s11, pv2_fail

    li   t4, 35                     # hpmcounter5h
    addi s11, s11, 1
    la   s0, pv2_c5
pv2_c5:
    csrr t0, 0xC85
    bne  s3, s11, pv2_fail

    ecall                           # -> M
    j    pv2_fail

pv2_mc:
    li   t4, 36
    li   t3, 5
    bne  s3, t3, pv2_fail

    # =====================================================================
    # PHASE D — mcounteren bit independence.  D1: TM + HPM4 only.
    # =====================================================================
    li   t4, 40
    li   t1, 0x00000012             # TM(1) | HPM4(4)
    csrw 0x306, t1
    csrr t2, 0x306
    bne  t2, t1, pv2_fail

    li   s3, 0
    li   s11, 0
    la   s9, pv2_md1
    la   t0, pv2_ud1
    csrw 0x341, t0
    mret                            # ---- U-MODE, mcounteren = 0x12 ----

pv2_ud1:
    li   t4, 50                     # the two ENABLED views must read
    mv   s7, s3
    csrr t0, 0xC01                  # time      (TM = 1)
    csrr t0, 0xC81                  # timeh
    csrr t0, 0xC04                  # hpmcounter4  (HPM4 = 1)
    csrr t0, 0xC84                  # hpmcounter4h
    bne  s3, s7, pv2_fail

    li   t4, 51                     # cycle: CY = 0 -> traps
    addi s11, s11, 1
    la   s0, pv2_d1a
pv2_d1a:
    csrr t0, 0xC00
    bne  s3, s11, pv2_fail

    li   t4, 52                     # instret: IR = 0 -> traps
    addi s11, s11, 1
    la   s0, pv2_d1b
pv2_d1b:
    csrr t0, 0xC02
    bne  s3, s11, pv2_fail

    li   t4, 53                     # hpmcounter3: HPM3 = 0 -> traps
    addi s11, s11, 1
    la   s0, pv2_d1c
pv2_d1c:
    csrr t0, 0xC03
    bne  s3, s11, pv2_fail

    ecall
    j    pv2_fail

pv2_md1:
    li   t4, 54
    li   t3, 3
    bne  s3, t3, pv2_fail

    # =====================================================================
    # PHASE D2 — IR only.  time must now TRAP (it read fine one phase ago),
    # which is what makes the TM term of ucnt_denied observable.
    # =====================================================================
    li   t4, 60
    li   t1, 0x00000004             # IR(2) only
    csrw 0x306, t1
    csrr t2, 0x306
    bne  t2, t1, pv2_fail

    li   s3, 0
    li   s11, 0
    la   s9, pv2_md2
    la   t0, pv2_ud2
    csrw 0x341, t0
    mret                            # ---- U-MODE, mcounteren = 0x04 ----

pv2_ud2:
    li   t4, 70                     # instret / instreth must read
    mv   s7, s3
    csrr t0, 0xC02
    csrr t0, 0xC82
    bne  s3, s7, pv2_fail

    li   t4, 71                     # time: TM = 0 -> traps  [seed p2rt_ucnttm]
    addi s11, s11, 1
    la   s0, pv2_d2a
pv2_d2a:
    csrr t0, 0xC01
    bne  s3, s11, pv2_fail

    li   t4, 72                     # timeh: TM = 0 -> traps
    addi s11, s11, 1
    la   s0, pv2_d2b
pv2_d2b:
    csrr t0, 0xC81
    bne  s3, s11, pv2_fail

    li   t4, 73                     # hpmcounter4: HPM4 back to 0 -> traps
    addi s11, s11, 1
    la   s0, pv2_d2c
pv2_d2c:
    csrr t0, 0xC04
    bne  s3, s11, pv2_fail

    ecall
    j    pv2_fail

pv2_md2:
    li   t4, 74
    li   t3, 3
    bne  s3, t3, pv2_fail

    # =====================================================================
    # PHASE E — WFI IS LEGAL IN U WHEN mstatus.TW = 0.  privucsr only covers
    # the DENIED direction (TW = 1); nothing proved the permitted one, and
    # nothing exercised the `wfi_slept` entry marker from U at all.
    #
    # BOUNDEDNESS BY CONSTRUCTION: mie.MSIE and CLINT msip[0] are both raised
    # BEFORE the WFI, so (mip and mie) /= 0 already holds and the standard
    # wake rule fires immediately.  mstatus.MIE stays 0, so nothing may be
    # DELIVERED -- "resumed at WFI+4 with no trap" is the exact observable.
    # A WFI wrongly denied in U traps instead, s3 advances, and the bounded
    # `bne s3, s7` catches it.  Neither path can hang.
    # =====================================================================
    li   t4, 76
    csrw 0x306, x0                  # mcounteren = 0
    li   t1, 0x00000008
    csrw 0x304, t1                  # mie.MSIE
    li   t1, 1
    sw   t1, 0(s8)                  # raise msip[0]
    li   t2, 4096
pv2_wait_mip2:
    csrr t0, 0x344
    andi t0, t0, 0x8
    bnez t0, pv2_armed2
    addi t2, t2, -1
    bnez t2, pv2_wait_mip2
    j    pv2_fail
pv2_armed2:

    li   t4, 77
    csrw 0x300, x0                  # MPP=00, MPIE=0, MIE=0, TW=0
    li   s3, 0
    li   s11, 0
    li   s1, 0
    la   s9, pv2_me
    la   t0, pv2_ue
    csrw 0x341, t0
    mret                            # ---- U-MODE, TW = 0, MIE = 0 ----

pv2_ue:
    li   t4, 78
    mv   s7, s3
    la   s0, pv2_uew                # publish the WFI's own pc so that a WRONGLY
pv2_uew:                            #   denied WFI takes the ordinary poison path
    .word 0x10500073                #   (handler skips it, s3++) and lands on the
    li   s1, 0x22220000             #   bounded count check below instead of the
    bne  s3, s7, pv2_fail           #   handler's mepc guard.  [seed p2rt_wfiudeny]
    ecall
    j    pv2_fail

pv2_me:
    li   t4, 79
    li   t3, 0x22220000
    bne  s1, t3, pv2_fail           # the instruction after WFI really ran
    bne  s3, x0, pv2_fail           # and nothing was delivered (MIE was 0)

    # =====================================================================
    # Restore and finish.  Clear every source BEFORE returning to LEGACY.
    # =====================================================================
    li   t4, 80
    sw   x0, 0(s8)                  # drop msip[0]
    li   t2, 4096
pv2_wait_clr:
    csrr t0, 0x344
    andi t0, t0, 0x8
    beqz t0, pv2_quiet
    addi t2, t2, -1
    bnez t2, pv2_wait_clr
    j    pv2_fail
pv2_quiet:
    csrw 0x300, x0
    csrw 0x304, x0
    csrw 0x306, x0
    li   t1, 0x00000001
    csrw 0x7C0, t1                  # back to LEGACY delivery
    csrr t2, 0x7C0
    bne  t2, t1, pv2_fail
    csrr t2, 0x306
    bne  t2, x0, pv2_fail

    RVTEST_PASS

    # =====================================================================
    # The mtvec handler.  Captures cause/mepc/pushed-mstatus for the M-mode
    # checks, verifies every U-mode poison in place, and services the one
    # machine software interrupt.
    # =====================================================================
    .align 2
pv2_handler:
    csrr s4, 0x342                  # mcause
    csrr s5, 0x341                  # mepc
    csrr s6, 0x300                  # the PUSHED mstatus (MPP = trapped priv)
    li   t3, 0x80000003
    beq  s4, t3, pv2_h_msi          # machine software interrupt
    li   t3, 8
    beq  s4, t3, pv2_h_tom          # ECALL from U = "give me M-mode back"
    li   t3, 2                      # everything else must be illegal-instruction
    bne  s4, t3, pv2_h_bad
    bne  s5, s0, pv2_h_pc           # ... at the poison's OWN pc
    addi s3, s3, 1
    addi t6, s5, 4                  # skip the 4-byte poison
    csrw 0x341, t6
    mret

pv2_h_msi:
    mv   a1, s4                     # snapshot cause + pushed mstatus into a1/a2:
    mv   a2, s6                     #   s4/s5/s6 are clobbered by every later trap
                                    #   (the U ECALL that hands M-mode back)
    sw   x0, 0(s8)                  # clear msip[0] at the source
    li   t3, 4096
pv2_h_mw:
    csrr t0, 0x344
    andi t0, t0, 0x8
    beqz t0, pv2_h_mq
    addi t3, t3, -1
    bnez t3, pv2_h_mw
    li   t4, 95                     # msip never cleared
    j    pv2_fail
pv2_h_mq:
    addi s3, s3, 1
    mret                            # resume U at mepc

pv2_h_tom:
    jr   s9

pv2_h_bad:
    li   t4, 96                     # unexpected mcause
    j    pv2_fail
pv2_h_pc:
    li   t4, 97                     # right cause, wrong mepc
    j    pv2_fail

    .option pop

#else
    li   t4, 0
    j    pv2_fail
#endif

pv2_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF (t4 = failing check id)

    # NOTE: RVTEST_CODE_END is 'unimp' (traps!) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
