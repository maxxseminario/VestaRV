# See LICENSE for license details.

#*****************************************************************************
# irqctx.S
#-----------------------------------------------------------------------------
# Hart-0 directed test of the HARDWARE IRQ context save/restore contract,
# using a CLINT msip self-IPI as the interrupt source (runs against the
# default shmem_mp contention tiles like shclint).
#
# The vesta core's contract (IRQ_SV / IRQ_REST states):
#   entry: mem[sp-4] <= return PC (pc_next), THEN sp <= sp-4
#          -> the ISR sees the saved PC at 0(sp) at entry
#   iret:  PC <= mem[sp] (RE-READ FROM RAM), sp <= sp+4
#
# Checks:
#   1. SAVE-TO-RAM: the push slot (0xFFEC) is pre-poisoned; after the IRQ it
#      must hold a PC inside the triggering spin loop, and the SAME value the
#      ISR captured from 0(sp)+its-frame. The word AT sp (0xFFF0) keeps its
#      poison -- hardware wrote only mem[sp-4].
#   2. SP DISCIPLINE: the ISR records its entry sp; it must be exactly
#      0xFFF0-4. After iret, main-line sp must be back to 0xFFF0.
#   3. REGISTER TRANSPARENCY: 27 GPRs (all but sp and the spin loop's
#      s3/t0/t6) hold per-register patterns across the whole IRQ round trip
#      -- hardware saves ONLY the PC, and the ISR's own save/restore of what
#      it touches must be invisible.
#   4. RESTORE-FROM-RAM: on a second IPI the ISR OVERWRITES the stacked PC
#      with redirect_target; iret must land there (a core that returns via
#      an internal latch instead of re-reading mem[sp] stays in the wait
#      loop and fails on the bounded budget).
#
# ISR contract as ever: clear the LEVEL before iret; bounded budgets must
# trip inside the 100ms tb watchdog (20000 iters, shclint precedent).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   sp, 0xFFF0             # private RAM1 top; IRQ_SV pushes PC at sp-4
    la   s3, isr_flags
    sw   x0, 0(s3)

    # ---- poison the stack: push slot AND the word at sp -------------------
    li   t0, 0x55AA55AA
    sw   t0, -4(sp)             # 0xFFEC: hardware MUST overwrite this
    li   t0, 0x0BADF00D
    sw   t0, 0(sp)              # 0xFFF0: hardware must NOT touch this

    # ---- unmask CLINT msip on hart 0 (SYSTEM regs) -------------------------
    # SYS_IRQ_ENU write packing QUIRK: EN bit 83 (msip) = write_data bit 27
    li   t0, 0x4900             # SYSTEM base
    li   t1, 0x08000000
    sw   t1, 0x1C(t0)           # SYS_IRQ_ENU
    li   t1, 1
    sw   t1, 0x2C(t0)           # SYS_IRQ_CR: irq_gen (global enable)

    # ---- pattern every GPR except sp, s3, t0, t6 ---------------------------
    # (s3 = flag pointer, t0 = poll scratch, t6 = bounded budget)
    li   ra, 0xC0DE0001
    li   gp, 0xC0DE0003
    li   tp, 0xC0DE0004
    li   t1, 0xC0DE0006
    li   t2, 0xC0DE0007
    li   s0, 0xC0DE0008
    li   s1, 0xC0DE0009
    li   a0, 0xC0DE000A
    li   a1, 0xC0DE000B
    li   a2, 0xC0DE000C
    li   a3, 0xC0DE000D
    li   a4, 0xC0DE000E
    li   a5, 0xC0DE000F
    li   a6, 0xC0DE0010
    li   a7, 0xC0DE0011
    li   s2, 0xC0DE0012
    li   s4, 0xC0DE0014
    li   s5, 0xC0DE0015
    li   s6, 0xC0DE0016
    li   s7, 0xC0DE0017
    li   s8, 0xC0DE0018
    li   s9, 0xC0DE0019
    li   s10, 0xC0DE001A
    li   s11, 0xC0DE001B
    li   t3, 0xC0DE001C
    li   t4, 0xC0DE001D
    li   t5, 0xC0DE001E

    # ---- 1st self-IPI: IRQ lands somewhere in [ipi1_go, spin_done] ---------
ipi1_go:
    li   t0, 0x11000            # CLINT base
    li   t6, 1
    sw   t6, 0(t0)              # MSIP[0] = 1
    li   t6, 20000
spin_loop:
    lw   t0, 0(s3)
    bnez t0, spin_done
    addi t6, t6, -1
    bnez t6, spin_loop
    j    irqctx_fail
spin_done:

    # ---- 3. register transparency across the IRQ round trip ---------------
    li   t0, 0xC0DE0001
    bne  ra, t0, irqctx_fail
    li   t0, 0xC0DE0003
    bne  gp, t0, irqctx_fail
    li   t0, 0xC0DE0004
    bne  tp, t0, irqctx_fail
    li   t0, 0xC0DE0006
    bne  t1, t0, irqctx_fail
    li   t0, 0xC0DE0007
    bne  t2, t0, irqctx_fail
    li   t0, 0xC0DE0008
    bne  s0, t0, irqctx_fail
    li   t0, 0xC0DE0009
    bne  s1, t0, irqctx_fail
    li   t0, 0xC0DE000A
    bne  a0, t0, irqctx_fail
    li   t0, 0xC0DE000B
    bne  a1, t0, irqctx_fail
    li   t0, 0xC0DE000C
    bne  a2, t0, irqctx_fail
    li   t0, 0xC0DE000D
    bne  a3, t0, irqctx_fail
    li   t0, 0xC0DE000E
    bne  a4, t0, irqctx_fail
    li   t0, 0xC0DE000F
    bne  a5, t0, irqctx_fail
    li   t0, 0xC0DE0010
    bne  a6, t0, irqctx_fail
    li   t0, 0xC0DE0011
    bne  a7, t0, irqctx_fail
    li   t0, 0xC0DE0012
    bne  s2, t0, irqctx_fail
    li   t0, 0xC0DE0014
    bne  s4, t0, irqctx_fail
    li   t0, 0xC0DE0015
    bne  s5, t0, irqctx_fail
    li   t0, 0xC0DE0016
    bne  s6, t0, irqctx_fail
    li   t0, 0xC0DE0017
    bne  s7, t0, irqctx_fail
    li   t0, 0xC0DE0018
    bne  s8, t0, irqctx_fail
    li   t0, 0xC0DE0019
    bne  s9, t0, irqctx_fail
    li   t0, 0xC0DE001A
    bne  s10, t0, irqctx_fail
    li   t0, 0xC0DE001B
    bne  s11, t0, irqctx_fail
    li   t0, 0xC0DE001C
    bne  t3, t0, irqctx_fail
    li   t0, 0xC0DE001D
    bne  t4, t0, irqctx_fail
    li   t0, 0xC0DE001E
    bne  t5, t0, irqctx_fail
    la   t0, isr_flags          # s3 too (was live in the loop)
    bne  s3, t0, irqctx_fail

    # ---- 2. sp discipline ---------------------------------------------------
    li   t0, 0xFFF0
    bne  sp, t0, irqctx_fail    # iret restored sp (+4 after the -4 push)
    la   t1, ctx_sp
    lw   t1, 0(t1)
    li   t2, 0xFFF0 - 4
    bne  t1, t2, irqctx_fail    # ISR-entry sp was exactly sp-4

    # ---- 1. the saved PC landed in RAM, inside the trigger window ----------
    la   t1, ctx_pc
    lw   t1, 0(t1)              # PC the ISR read from its stack frame
    la   t2, ipi1_go
    bltu t1, t2, irqctx_fail
    la   t2, spin_done
    bgtu t1, t2, irqctx_fail
    lw   t2, -4(sp)             # the push slot itself (0xFFEC)...
    bne  t2, t1, irqctx_fail    # ...still holds that exact PC (not poison)
    lw   t2, 0(sp)              # word AT sp:
    li   t1, 0x0BADF00D
    bne  t2, t1, irqctx_fail    # untouched -- hardware wrote ONLY sp-4

    # ---- 4. iret takes the PC from RAM: doctored return ---------------------
    # isr_flags is now 1, so the ISR takes its redirect path this time.
    li   t0, 0x11000
    li   t1, 1
    sw   t1, 0(t0)              # 2nd MSIP[0] = 1
    li   t6, 20000
p2_wait:
    addi t6, t6, -1
    bnez t6, p2_wait
    j    irqctx_fail            # still here => iret ignored the doctored PC

redirect_target:
    # reachable ONLY through the ISR overwriting the stacked PC
    lw   t0, 0(s3)
    li   t1, 2
    bne  t0, t1, irqctx_fail    # redirect path really ran
    li   t1, 0xFFF0
    bne  sp, t1, irqctx_fail    # sp discipline held through the redirect too
    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin

irqctx_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # ---- msip ISR (hart 0; clear the LEVEL before iret) ----------------------
    # Frame: 8 bytes of own saves; the HW-pushed return PC sits at 8(sp).
msip_isr:
    addi sp, sp, -8
    sw   t0, 0(sp)
    sw   t1, 4(sp)
    li   t0, 0x11000
    sw   x0, 0(t0)              # clear MSIP[0] (the level) before iret
    la   t0, isr_flags
    lw   t1, 0(t0)
    bnez t1, isr_redirect
    # pass 1: capture the HW-saved context for the main line to judge
    lw   t1, 8(sp)              # the PC hardware pushed at (entry sp)
    la   t0, ctx_pc
    sw   t1, 0(t0)
    addi t1, sp, 8              # reconstruct ISR-entry sp
    la   t0, ctx_sp
    sw   t1, 0(t0)
    la   t0, isr_flags
    li   t1, 1
    sw   t1, 0(t0)
    j    isr_out
isr_redirect:
    # pass 2: DOCTOR the stacked return PC -- iret must fetch it from RAM
    la   t0, redirect_target
    sw   t0, 8(sp)
    la   t0, isr_flags
    li   t1, 2
    sw   t1, 0(t0)
isr_out:
    lw   t0, 0(sp)
    lw   t1, 4(sp)
    addi sp, sp, 8
    iret

    # ---- extend the env IVT: DEFINE_IVT emitted slots 0-82 ------------------
    .section .ivt, "ax"
    .org 0x14C
    jal  zero, msip_isr         # slot 83 = IRQB_CLINT_MSIP
    .previous

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
isr_flags: .word 0
ctx_pc:    .word 0
ctx_sp:    .word 0
  TEST_DATA
RVTEST_DATA_END
