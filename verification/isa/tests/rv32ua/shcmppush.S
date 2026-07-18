# See LICENSE for license details.

#*****************************************************************************
# shcmppush.S  (X3 Zcmp — INTERRUPTED push/pop uninterruptibility proof)
#   [X3 Stage-D red-team deliverable (B)]
#-----------------------------------------------------------------------------
# Build-time dispatch on CORE_ENABLE_ZCMP (explicit -DCORE_ENABLE_ZCMP at ON
# staging; never auto-derived). Hart 0 only (single-hart; tiles park).
#
#   OFF (#else): base sanity + PASS. The cm.* encodings are illegal here and
#       must NOT be emitted (image stays bit-identical to a base build); this
#       keeps the test in the DEFAULT behavioral_mp regression, green.
#
#   ON  (#ifdef): PROVE the Zcmp push/pop sequencer is UNINTERRUPTIBLE — it
#       holds a pending interrupt to the retire boundary, and `sp` commits
#       exactly once, LAST. So an interrupt that becomes pending DURING the
#       burst must be taken only AFTER retire, with the handler seeing sp fully
#       committed and the frame fully written — never a partial frame.
#
#       Mechanism (why a TIMER, not a bare msip): every ordinary
#       instruction-boundary state (EXECUTE / MEMORY_WAIT) takes a pending
#       interrupt immediately, so a self-IPI pended right before the cm.push is
#       taken at the pend-STORE's own MEMORY_WAIT — before the push. To land the
#       interrupt INSIDE the burst we arm CLINT mtimecmp a tuned delta ahead of
#       the free-running mtime (mtime ticks at the 24 MHz shared clock while the
#       core runs at the post-boot LFXT ~32 kHz, so the ~13-store burst is tens
#       of thousands of mtime ticks wide). mtip then rises mid-burst; the
#       uninterruptible sequencer HOLDS it until ZCM_SP_COMMIT -> MEMORY_WAIT
#       retires, where it is finally taken.
#
#       The mtip ISR (IVT slot 84) records, as its FIRST act, the interrupted
#       sp. The HW push-entry (IRQ_SV) decremented sp by 4, so the true
#       interrupted sp = recorded + 4. Invariant asserted:
#         push {ra,s0-s11},-112 : recorded+4 == entry_sp - 112  (committed)
#         pop  {ra,s0-s11}, 112 : recorded+4 == entry_sp         (committed)
#       Because sp commits LAST, "the ISR saw the committed sp" is provable
#       only if the ENTIRE burst retired before the interrupt was taken. A
#       sequencer made interruptible mid-burst (see
#       verification/isa/negctrl/x3_redteam_zcmp_interruptible.patch, which adds
#       an irq_save escape to ZCM_PUSH_GAP) takes mtip mid-burst -> the ISR sees
#       the OLD (uncommitted) sp -> the bne FAILs, BOUNDED (never a watchdog).
#       The frame sentinels + the exact round-trip are the companion guards.
#
# gas 13.2 has no cm.* mnemonics; cm.push/pop are raw 16-bit `.short's (verified
# shcmp.S encodings): cm.push {ra,s0-s11},-112 = 0xB8FE ; cm.pop {..},112 = 0xBAFE.
#
# CLINT (NHARTS=4): base 0x5000; MSIP[0]=0x5000; mtime lo=0x5010; mtimecmp0
# lo/hi = 0x5020/0x5024 (reset all-ones = quiet). Reserved regs (never in an
# rlist, never touched by the ISR): gp(x3)=&cpp_cursp, tp(x4)=entry sp.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

# mtime delta (in 24 MHz ticks) from the arm-time read to the target fire: sized
# to land mid-burst (after the ~few-instruction arm, before the ~13-store retire).
#define MTIP_DELTA 35

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr t0, mhartid
    .option pop
    bnez t0, cpp_pass            # single-hart test; launched tiles just pass

#ifdef CORE_ENABLE_ZCMP
    # base-ISA sanity
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, cpp_fail

    la   gp, cpp_cursp           # ISR sp-capture pointer (x3; ISR-safe)

    # =====================================================================
    # SECTION 1 — timer pending ACROSS a cm.push burst.
    # =====================================================================
    la   sp, cpp_stack_hi
    mv   tp, sp                  # entry sp (x4; ISR-safe)
    li   ra, 0x1A1A1A1A
    li   s0, 0xB0B0B0B0
    li   s1, 0xB1B1B1B1
    li   s2, 0xB2B2B2B2
    li   s3, 0xB3B3B3B3
    li   s4, 0xB4B4B4B4
    li   s5, 0xB5B5B5B5
    li   s6, 0xB6B6B6B6
    li   s7, 0xB7B7B7B7
    li   s8, 0xB8B8B8B8
    li   s9, 0xB9B9B9B9
    li   s10,0xBABABABA
    li   s11,0xBCBCBCBC
    sw   x0, 0(gp)               # cpp_cursp = 0
    la   t0, cpp_isr_ran
    sw   x0, 0(t0)               # cpp_isr_ran = 0

    # arm mtip a tuned delta ahead of mtime (lo while hi still all-ones = quiet,
    # then hi=0 arms), then IMMEDIATELY cm.push so mtip rises mid-burst
    li   t3, 0x5000
    lw   t4, 0x10(t3)           # mtime lo
    li   t5, MTIP_DELTA
    add  t4, t4, t5
    sw   t4, 0x20(t3)           # mtimecmp0 lo (hi still all-ones: quiet)
    sw   x0, 0x24(t3)           # mtimecmp0 hi = 0 : ARMED
    .short 0xB8FE              # cm.push {ra,s0-s11},-112   <-- must retire first

    # wait for the (held) interrupt to be taken now that the push retired
    la   t0, cpp_isr_ran
    li   t6, 20000              # bounded: trips well inside the 100 ms tb watchdog
1:  lw   t1, 0(t0)
    bnez t1, 2f
    addi t6, t6, -1
    bnez t6, 1b
    j    cpp_fail              # ISR never fired -> bounded FAIL

2:  # (a) COMMITTED-sp invariant: recorded sp (+4 for HW push decrement) == entry-112.
    #     Interruptible-mid-burst would have recorded the OLD (uncommitted) sp -> FAIL.
    lw   t0, 0(gp)
    addi t0, t0, 4
    addi t1, tp, -112
    bne  t0, t1, cpp_fail
    # (b) frame intact at the spec offsets (top sentinel + bottom ra)
    lw   t0, -4(tp);  li t1, 0xBCBCBCBC; bne t0, t1, cpp_fail   # s11 at entry-4
    lw   t0, -52(tp); li t1, 0x1A1A1A1A; bne t0, t1, cpp_fail   # ra  at entry-52
    # (c) exact pop round-trip
    li ra,0; li s0,0; li s1,0; li s2,0; li s3,0; li s4,0; li s5,0
    li s6,0; li s7,0; li s8,0; li s9,0; li s10,0; li s11,0
    .short 0xBAFE              # cm.pop {ra,s0-s11},112
    bne  sp, tp, cpp_fail
    li t1,0x1A1A1A1A; bne ra, t1, cpp_fail
    li t1,0xB0B0B0B0; bne s0, t1, cpp_fail
    li t1,0xB4B4B4B4; bne s4, t1, cpp_fail
    li t1,0xBABABABA; bne s10,t1, cpp_fail
    li t1,0xBCBCBCBC; bne s11,t1, cpp_fail

    # =====================================================================
    # SECTION 2 — timer pending ACROSS a cm.pop burst.
    # =====================================================================
    la   sp, cpp_stack_hi
    mv   tp, sp
    li   ra, 0x2A2A2A2A
    li   s0, 0x20202020
    li   s1, 0x21212121
    li   s2, 0x23232323
    li   s3, 0x24242424
    li   s4, 0x25252525
    li   s5, 0x26262626
    li   s6, 0x27272727
    li   s7, 0x28282828
    li   s8, 0x29292929
    li   s9, 0x2B2B2B2B
    li   s10,0x2C2C2C2C
    li   s11,0x2D2D2D2D
    .short 0xB8FE              # cm.push (NOT interrupted — sets up the frame)
    li ra,0; li s0,0; li s1,0; li s2,0; li s3,0; li s4,0; li s5,0
    li s6,0; li s7,0; li s8,0; li s9,0; li s10,0; li s11,0
    sw   x0, 0(gp)             # clear cursp
    la   t0, cpp_isr_ran
    sw   x0, 0(t0)            # clear isr_ran
    # arm mtip mid-pop-burst
    li   t3, 0x5000
    lw   t4, 0x10(t3)
    li   t5, MTIP_DELTA
    add  t4, t4, t5
    sw   t4, 0x20(t3)
    sw   x0, 0x24(t3)         # ARMED
    .short 0xBAFE              # cm.pop {ra,s0-s11},112   <-- must retire first

    la   t0, cpp_isr_ran
    li   t6, 20000
3:  lw   t1, 0(t0)
    bnez t1, 4f
    addi t6, t6, -1
    bnez t6, 3b
    j    cpp_fail

4:  # committed HIGH sp: recorded +4 == entry_sp (pop commits sp LAST)
    lw   t0, 0(gp)
    addi t0, t0, 4
    bne  t0, tp, cpp_fail
    # exact round-trip
    li t1,0x2A2A2A2A; bne ra, t1, cpp_fail
    li t1,0x20202020; bne s0, t1, cpp_fail
    li t1,0x25252525; bne s4, t1, cpp_fail
    li t1,0x2C2C2C2C; bne s10,t1, cpp_fail
    li t1,0x2D2D2D2D; bne s11,t1, cpp_fail

    j    cpp_pass

    # ---- mtip ISR (hart 0; disarm the timer LEVEL before iret) ----
    # FIRST act: record the interrupted sp (= isr-entry sp; the true interrupted
    # sp is this + 4, the HW IRQ_SV push decrement). Then a temp frame BELOW the
    # return-PC (at 0(sp)) to disarm mtimecmp.
mtip_isr:
    sw   sp, 0(gp)             # cpp_cursp = isr-entry sp
    addi sp, sp, -16
    sw   t0, 0(sp)
    sw   t1, 4(sp)
    sw   t2, 8(sp)
    li   t0, 0x5000
    li   t1, -1
    sw   t1, 0x24(t0)          # mtimecmp0 hi = all-ones : level drops
    la   t1, cpp_isr_ran
    li   t2, 1
    sw   t2, 0(t1)
    lw   t0, 0(sp)
    lw   t1, 4(sp)
    lw   t2, 8(sp)
    addi sp, sp, 16
    iret

    # extend the env IVT: DEFINE_IVT emitted slots 0-82; add slot 84 (CLINT MTIP)
    .section .ivt, "ax"
    .org 0x150
    jal  zero, mtip_isr        # slot 84 = IRQB_CLINT_MTIP
    .previous

#else
    # FEATURE OFF: cm.* are illegal — trivial pass, image bit-identical.
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, cpp_fail
    j    cpp_pass
#endif

cpp_pass:
    RVTEST_PASS
cpp_fail:
    RVTEST_FAIL

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
cpp_isr_ran: .word 0
cpp_cursp:   .word 0
  TEST_DATA
  .align 4
cpp_stack_lo: .fill 160, 4, 0    # 640-byte buffer below the frame (frame 112 + ISR temps)
cpp_stack_hi:
  .word 0
RVTEST_DATA_END
