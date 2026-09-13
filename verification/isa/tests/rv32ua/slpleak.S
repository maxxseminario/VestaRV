# See LICENSE for license details.

# VestaRV: detector for an `extinguish` leaked by the legacy interrupt-entry state
# THE DEFECT: the same live decode in IRQ_SV also drives sleep_rq, so an `extinguish` encoding that merely happens to sit on the bus during interrupt entry sends an AWAKE hart to SLEEPING when it should have resumed. THAT IS A HANG, NOT A WRONG NUMBER, which is why the detector has this shape. maindec's sleep_rq is a pure decode of instr_curr with no state qualification, instr_curr takes the raw bus word in IRQ_SV, and the sleep_cpu flop runs on the free-running clock gated only by dec_squash, which is low on the legacy path, so IRQ_REST takes its sleep arm and the hart never resumes. sleep_cpu gates no clock, so the ISR itself runs normally and the hart dies on the iret, one state after the handler returns, where nothing in the a0 contract can see it.
# THIS ONE MUST CALIBRATE ITSELF. The sibling detector can make the leaked word a compile-time constant by parking the hart first, because SLEEPING holds pc_next; that is unavailable here, because THE VICTIM MUST BE AWAKE or the spurious set is masked by a legitimate one. For an awake hart the leaked word is whatever sits at the resume PC, which depends on interrupt latency, so the test MEASURES it in two passes over the same code. Pass 1 arms a self-IPI and falls into a sled of nops; the interrupt lands somewhere and the ISR reads the return PC hardware pushed at sp-4, which for any legacy interrupt entry is exactly the word IRQ_SV decoded. The ISR PATCHES that word in place with the extinguish encoding, since the image runs from writable TCM, remembers it, rewrites the stacked return PC to the retry label and irets. Pass 2 runs the identical path so the interrupt lands on the same instruction, but now IRQ_SV decodes an `extinguish`; the ISR requires the SAME address, records the markers, rewrites the stacked return PC to the resume label and, the whole point, does NOT ignite.
# THE RETURN-PC REWRITE IS ALSO WHAT KEEPS THE PATCHED WORD FROM EVER BEING EXECUTED, so a legitimate sleep can never be mistaken for the leak, and requiring pass 2 to land on the same address as pass 1 is what stops a shifted landing from becoming a silent pass.
# POLARITY, TO BE READ BEFORE CALLING THE TEST GREEN. With the defect, pass 2 sets sleep_cpu from the phantom decode, the iret lands in SLEEPING with msip already cleared, and hart 0 NEVER writes a0, so the run ends on the testbench watchdog; the corroboration is state that survives into SLEEPING, a5 = 0xF3F30000 meaning the mechanism was reached, a3 the patched address and a4 the pass-1 landing with the same value, plus the RTL showing current_state SLEEPING with sleep_cpu set and no msip pending. Without the defect the iret resumes at the resume label, which re-checks the markers before passing.
# Verdicts on the resuming side only: a0 = 0xCAFEBABE passes; a1 = 0x5E800001 means the calibration failed, with pass 1 landing outside the sled or pass 2 landing elsewhere, which is NOT a pass because the mechanism was not reached; 0x5E800002 the hart ran off the end of the sled; 0x5E800003 it resumed without the markers.
# No shared window is claimed; the only non-private address is the CLINT msip register. `.option norvc` throughout with one rvc-enabled `.balign 4` at the top keeps every instruction 4-byte aligned so the half-fetch bubble cannot contaminate this image, and RVTEST_CODE_END is `unimp` here, so every path spins.

#include "riscv_test.h"
#include "test_macros.h"

.option norelax

#define MSIP0           0x5000
#define F3P_N           16            /* sled length, in 4-byte nops */
#define EXTINGUISH_ENC  0x0000100B    /* .insn r 0x0b, 1, 0, x0, x0, x0 */

RVTEST_RV32U
RVTEST_CODE_BEGIN

.option arch, +zicsr
.option rvc
    .balign 4
.option norvc

    li   sp, 0xBFF0                 # sp MUST be valid before any IRQ
    la   t0, f3p_stage
    sw   x0, 0(t0)
    la   t0, f3p_target
    sw   x0, 0(t0)

    # =====================================================================
    # One pass: arm a self-IPI, then fall into the sled.  Run TWICE -- the
    # ISR sends us back here after the calibration pass.
    # =====================================================================
    .balign 4
f3p_retry:
    li   t2, MSIP0
    li   t1, 1
    sw   t1, 0(t2)                  # MSIP[0] = 1 (level) -- ARM
f3p_sled:
    .rept F3P_N
    nop
    .endr
f3p_guard:
    li   a4, 0xBAD00001             # only reachable if the sled overran, i.e.
    j    f3p_overrun                #   the interrupt never landed in it

    # =====================================================================
    # Post-fix resume point (the ISR rewrote the stacked return PC to here)
    # =====================================================================
f3p_resume:
    li   t0, 0xF3F30000
    bne  a5, t0, f3p_setup3         # marker absent: got here some other way
    la   t1, f3p_target
    lw   t2, 0(t1)
    bne  a3, t2, f3p_setup3
    RVTEST_PASS                     # a0 = 0xCAFEBABE

f3p_notreached:
    li   a1, 0x5E800001
    j    f3p_fail
f3p_overrun:
    li   a1, 0x5E800002
    j    f3p_fail
f3p_setup3:
    li   a1, 0x5E800003
f3p_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    # =====================================================================
    # msip ISR (IVT slot 83, hardware-vectored).  a3/a4/a5 are the diagnostic
    # channel and are deliberately NOT saved/restored.
    # =====================================================================
f3p_isr:
    addi sp, sp, -20
    sw   t0, 0(sp)
    sw   t1, 4(sp)
    sw   t2, 8(sp)
    sw   t3, 12(sp)
    sw   t4, 16(sp)

    li   t0, MSIP0
    sw   x0, 0(t0)                  # clear the msip LEVEL before any iret
    lw   t1, 20(sp)                 # R = the return PC hardware pushed at sp-4

    la   t2, f3p_stage
    lw   t3, 0(t2)
    bnez t3, f3p_pass2

    # ---- PASS 1: calibrate, then patch R with the extinguish encoding ----
    mv   a4, t1                     # diagnostic: where the interrupt landed
    la   t2, f3p_sled
    bltu t1, t2, f3p_giveup         # landed before the sled
    la   t2, f3p_guard
    bgeu t1, t2, f3p_giveup         # landed at/after the guard
    li   t4, EXTINGUISH_ENC
    sw   t4, 0(t1)                  # PATCH: the word IRQ_SV will decode next time
    la   t2, f3p_target
    sw   t1, 0(t2)
    la   t2, f3p_stage
    li   t4, 1
    sw   t4, 0(t2)
    la   t2, f3p_retry
    sw   t2, 20(sp)                 # go round again
    j    f3p_isr_out

    # ---- PASS 2: IRQ_SV has just decoded the patched extinguish ----------
f3p_pass2:
    la   t2, f3p_target
    lw   t3, 0(t2)
    bne  t1, t3, f3p_moved          # the landing shifted: prove nothing
    mv   a3, t1
    li   a5, 0xF3F30000             # "the mechanism was reached"
    la   t2, f3p_resume
    sw   t2, 20(sp)
    lw   t0, 0(sp)
    lw   t1, 4(sp)
    lw   t2, 8(sp)
    lw   t3, 12(sp)
    lw   t4, 16(sp)
    addi sp, sp, 20
    iret                            # NO ignite: sleep_cpu is left exactly as
                                    #   the RTL set it -- that IS the detector

f3p_moved:
    mv   a4, t1
f3p_giveup:
    la   t2, f3p_notreached
    sw   t2, 20(sp)
f3p_isr_out:
    lw   t0, 0(sp)
    lw   t1, 4(sp)
    lw   t2, 8(sp)
    lw   t3, 12(sp)
    lw   t4, 16(sp)
    addi sp, sp, 20
    ignite                          # recover from any legitimate sleep
    iret

    # ---- extend the env IVT: DEFINE_IVT emitted slots 0-82 ---------------
    .section .ivt, "ax"
    .org 0x14C
    jal  zero, f3p_isr              # slot 83 = IRQB_CLINT_MSIP
    jal  zero, 0x0BB00              # slot 84 = IRQB_CLINT_MTIP -- parked
    .previous

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
f3p_stage:  .word 0
f3p_target: .word 0
  TEST_DATA
RVTEST_DATA_END
