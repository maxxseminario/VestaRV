# See LICENSE for license details.

#*****************************************************************************
# privirq.S   (P1 standard M-mode trap DELIVERY — INTERRUPTS through mtvec)
#-----------------------------------------------------------------------------
# ON-ONLY DIRECTED TEST, the interrupt half of the P1 delivery proof (privecall
# is the exception half). Frozen contract,
# ~/work/chip_docs/castalia/priv_arch/p0_specs.md 2.2/2.3:
#
#   take iff  mstatus.MIE and (mip and mie) /= 0     (priority MEI > MSI > MTI)
#   machine software irq (CLINT msip level) -> mcause 0x80000003, mtval 0,
#                                              mepc = the RESUME pc
#   mip is a READ-ONLY live mirror of the msip/mtip/meip level wires — it is
#   enable-agnostic, so a MASKED source still shows up in mip while provably
#   NOT being delivered.
#
# Sequence: arm mtvec, enable mstatus.MIE + mie.MSIE, opt into standard delivery
# (mtrapctl.LEGACY=0), then write CLINT msip[hart 0] at 0x5000 to interrupt
# OURSELVES. The handler reads mcause/mepc/mstatus/mip, clears the level at the
# CLINT (a level-sensitive source that is not cleared re-fires forever) and
# MRETs — WITHOUT adjusting mepc, because an interrupt's mepc already IS the
# resume pc, not a faulting pc.
#
# Then the negative half: mie.MSIE=0, raise msip again, prove mip SEES it and
# that NO trap is delivered inside a bounded window.
#
# EVERY wait in this file is a bounded down-counter that FAILs (compare and
# branch into RVTEST_FAIL) rather than spinning — kickoff rule: a bounded-retry
# budget must trip well inside the 100 ms tb watchdog. 4096/2048-iteration
# loops at mclk = 24 MHz are ~1 ms class (shspin uses 4096/20000).
#
# REGISTER CONTRACT (standard mode pushes NOTHING — no sp is touched):
#   s0  CLINT msip[0] address
#   s3  trap counter (handler increments)
#   s4  mcause captured in the handler
#   s5  mepc   captured in the handler (the RESUME pc)
#   s6  mstatus captured INSIDE the trap
#   s7  mtval  captured in the handler
#   s8  mip    captured in the handler BEFORE the source is cleared
#   s2  handler address
#   t5/t6 handler scratch
#   t4  CHECK ID at every comparison
#
# BUILD-TIME DISPATCH: ON iff -DCORE_ENABLE_TRAPCSR (privcsr / extjvt idiom).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

# P2 COMPATIBILITY (2026-07-28): mstatus.MPP is WARL {11} on a trapCsr-only
# build (any write stores 11) but WARL {00,11} once U-mode exists — where a
# written 00 stays 00 AND **MRET forces MPP<-00**. P_MPP0 is the MPP field as
# it reads after writing 0 to mstatus and, identically, after an MRET, so this
# file is a valid gate on BOTH ON flavours. The value captured INSIDE the trap
# is unaffected (trap entry sets MPP<-priv; this test only ever traps from M).
#ifdef CORE_ENABLE_UMODE
#define P_MPP0  0x00000000
#else
#define P_MPP0  0x00001800
#endif

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity: prove the core runs before any trap work ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, pirq_fail

#ifdef CORE_ENABLE_TRAPCSR

    .option push
    .option arch, +zicsr

    li   sp, 0xBFF0
    li   s3, 0                      # trap counter
    li   s0, 0x00005000             # CLINT msip[hart 0]

    # =====================================================================
    # CHECK 1 — arm mtvec first.
    # =====================================================================
    li   t4, 1
    la   s2, pirq_handler
    csrw 0x305, s2
    csrr t2, 0x305
    bne  t2, s2, pirq_fail

    # ---- CHECK 2: mip reads 0 — no interrupt source is armed yet ----
    li   t4, 2
    csrr t2, 0x344
    bne  t2, x0, pirq_fail

    # ---- CHECK 3: mstatus.MIE = 1 and mie.MSIE = 1 (bit 3) ----
    li   t4, 3
    li   t1, 0x00000008
    csrw 0x300, t1                  # mstatus.MIE
    li   t1, 0x00000008
    csrw 0x304, t1                  # mie.MSIE
    csrr t2, 0x304
    li   t3, 0x00000008
    bne  t2, t3, pirq_fail
    csrr t2, 0x300
    li   t3, (P_MPP0|0x00000008)
    bne  t2, t3, pirq_fail

    # ---- CHECK 4: opt into STANDARD delivery ----
    li   t4, 4
    csrw 0x7C0, x0
    csrr t2, 0x7C0
    bne  t2, x0, pirq_fail

    # =====================================================================
    # CHECK 5 — fire the CLINT software interrupt at ourselves and wait,
    # BOUNDED, for delivery. The trap lands somewhere inside this loop; the
    # handler MRETs back into it and the s3 test then falls out.
    # =====================================================================
    li   t4, 5
    li   t1, 1
    sw   t1, 0(s0)
pirq_armed:                         # earliest legal resume pc (the msip level
                                    # can rise while the store is still in
                                    # MEMORY_WAIT, so the very first eligible
                                    # check point produces mepc = HERE)
    li   t2, 4096
pirq_w1:
    bne  s3, x0, pirq_got1
    addi t2, t2, -1
    bne  t2, x0, pirq_w1
    j    pirq_fail                  # bounded: msip never delivered
pirq_got1:

    li   t4, 6                      # exactly one delivery
    li   t3, 1
    bne  s3, t3, pirq_fail

    li   t4, 7                      # mcause = 0x8000_0003 (machine software irq)
    li   t3, 0x80000003
    bne  s4, t3, pirq_fail

    li   t4, 8                      # mip.MSIP(3) was set when the handler ran
    li   t3, 0x00000008
    bne  s8, t3, pirq_fail

    li   t4, 9                      # mtval = 0 for an interrupt
    bne  s7, x0, pirq_fail

    li   t4, 10                     # inside the trap: MPIE<=MIE(1), MIE<=0
    li   t3, 0x00001880
    bne  s6, t3, pirq_fail

    # mepc is the RESUME pc: it must point into the arm-and-wait region above
    # (the only code that was executing) — i.e. into [pirq_armed, pirq_got1].
    # A mepc that skidded, or that captured a faulting pc instead of the resume
    # pc, or garbage, fails this window test.
    li   t4, 11
    la   t0, pirq_armed
    la   t1, pirq_got1
    bltu s5, t0, pirq_fail
    bgtu s5, t1, pirq_fail

    li   t4, 12                     # MRET popped: MIE<=MPIE(1), MPIE<=1
    csrr t2, 0x300                  # (U-mode build: MRET also forces MPP<-00)
    li   t3, (P_MPP0|0x00000088)
    bne  t2, t3, pirq_fail

    li   t4, 13                     # the handler cleared the source: mip back to 0
    li   t2, 2048
pirq_w2:
    csrr t0, 0x344
    beq  t0, x0, pirq_clr1
    addi t2, t2, -1
    bne  t2, x0, pirq_w2
    j    pirq_fail                  # bounded: the CLINT level never dropped
pirq_clr1:

    # =====================================================================
    # CHECK 14..16 — THE MASK PROOF. With mie.MSIE = 0 the SAME source must
    # show in mip (read-only live mirror, enable-agnostic) and must NOT be
    # delivered inside a bounded window.
    # =====================================================================
    li   t4, 14
    csrw 0x304, x0                  # mie.MSIE = 0
    csrr t2, 0x304
    bne  t2, x0, pirq_fail

    li   t1, 1
    sw   t1, 0(s0)                  # raise msip again

    li   t4, 15                     # mip SEES the masked level (bounded poll)
    li   t2, 2048
pirq_w3:
    csrr t0, 0x344
    andi t0, t0, 0x00000008
    bne  t0, x0, pirq_up2
    addi t2, t2, -1
    bne  t2, x0, pirq_w3
    j    pirq_fail                  # bounded: the level never appeared in mip
pirq_up2:

    li   t4, 16                     # ...and NOTHING is delivered while masked
    li   t3, 1
    li   t2, 2048
pirq_w4:
    bne  s3, t3, pirq_fail          # a delivery here = the mask was ignored
    addi t2, t2, -1
    bne  t2, x0, pirq_w4

    # =====================================================================
    # RESTORE: drop the CLINT level, mask everything, and go back to LEGACY
    # delivery so an ON build running the rest of the suite is unaffected.
    # =====================================================================
    li   t4, 17
    sw   x0, 0(s0)
    li   t2, 2048
pirq_w5:
    csrr t0, 0x344
    beq  t0, x0, pirq_clr2
    addi t2, t2, -1
    bne  t2, x0, pirq_w5
    j    pirq_fail                  # bounded: msip stuck high
pirq_clr2:

    li   t4, 18
    li   t1, 0x00000001
    csrw 0x7C0, t1                  # mtrapctl.LEGACY = 1
    csrw 0x300, x0
    csrw 0x304, x0
    csrr t2, 0x7C0
    li   t3, 0x00000001
    bne  t2, t3, pirq_fail
    csrr t2, 0x300
    li   t3, P_MPP0                 # MPP field; MIE/MPIE cleared
    bne  t2, t3, pirq_fail

    RVTEST_PASS

    # =====================================================================
    # The mtvec handler. Only ever reached by a hardware trap (it sits after
    # the RVTEST_PASS spin loop). mepc is NOT adjusted — for an interrupt it
    # already IS the resume pc. The CLINT level is cleared AT THE SOURCE and
    # the handler waits, BOUNDED, for mip to drop before MRET: returning with
    # the level still high would re-enter immediately once MRET restores MIE.
    # =====================================================================
    .align 2
pirq_handler:
    csrr s4, 0x342                  # mcause
    csrr s5, 0x341                  # mepc (resume pc)
    csrr s6, 0x300                  # mstatus AS PUSHED
    csrr s7, 0x343                  # mtval
    csrr s8, 0x344                  # mip BEFORE the source is cleared
    addi s3, s3, 1
    li   t5, 0x00005000
    sw   x0, 0(t5)                  # clear CLINT msip[hart 0]
    li   t6, 256
pirq_h_wait:
    csrr t5, 0x344
    andi t5, t5, 0x00000008
    beq  t5, x0, pirq_h_done
    addi t6, t6, -1
    bne  t6, x0, pirq_h_wait
    j    pirq_fail                  # bounded: level stuck -> FAIL, never a loop
pirq_h_done:
    mret

    .option pop

#else
    # OFF build: the ten P1 CSR addresses are unknown CSRs and MRET is an
    # illegal instruction — this core DEAD-ENDS in the terminal TRAP_STATE, so
    # none of the above may be assembled. privirq is deliberately NOT in the
    # default behavioral_mp runner array; reaching here means the ON/OFF staging
    # discipline was violated.
    li   t4, 0
    j    pirq_fail
#endif

pirq_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF (t4 = failing check id)

    # NOTE: RVTEST_CODE_END is 'unimp' (traps!) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
