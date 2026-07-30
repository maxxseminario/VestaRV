# See LICENSE for license details.

#*****************************************************************************
# ignleak.S   (F-series fix pass, W2 -- the DETECTOR for finding F3++)
#-----------------------------------------------------------------------------
# F3++ is the MIRROR IMAGE of F3+, and the second consumer of the same live
# IRQ_SV decode:
#
#   F3+  (slpleak.S)  an `extinguish` encoding decoded in IRQ_SV SETS sleep_cpu,
#                     so a RUNNING hart is sent to SLEEPING by IRQ_REST -- a hang.
#   F3++ (this test)  an `ignite` encoding decoded in IRQ_SV CLEARS sleep_cpu,
#                     so a SLEEPING hart RESUMES instead of re-parking.
#
# Mechanism, re-anchored to the RTL (hdl/common/vesta/vesta.vhd, rtl-fixpass):
#   * instr_curr <= instr when current_state = IRQ_SV is the FIRST matching arm
#     of the instr_curr mux, so IRQ_SV decodes the RAW unified-bus word.
#   * maindec: wake_rq <= '1' when (op = CUSTOM_OPCODE and funct3 = SLP_FN3 and
#     funct7 = WAKE_FN7 and u_gate = '0') -- a PURE DECODE, no state
#     qualification at all.
#   * the sleep_cpu flop is on the FREE-RUNNING clk and was gated only by
#     dec_squash, which is '0' on the legacy path.  So wake_rq='1' in IRQ_SV
#     clears sleep_cpu for a word the hart never executed.
#   * IRQ_REST's `elsif sleep_cpu = '1' then next_state <= SLEEPING` arm is then
#     NOT taken, and the hart resumes.
#
# WHY THAT MATTERS ON SILICON (this is not a synthetic shape): the bootrom park
#   contract is built on iret-WITHOUT-ignite meaning "go back to sleep".
#   software/bootrom_mp/src/start.S:582-585 says so in as many words for the
#   harvested-boot stray-msip ISR, and the tile park at :468 relies on the same
#   rule.  A parked tile that silently wakes spins in its `j <park>` paranoia
#   loop, burning power and shared-bus bandwidth on a chip that has just gated
#   its rails.
#
# HOW THE BUS WORD IS MADE DETERMINISTIC (no interrupt-latency calibration):
#   the same SLEEPING -> IRQ_SV edge csrleak.S uses.  In SLEEPING, pc_next is
#   held at pc_next_reg and the fetch of that word has been issued from
#   data_addr every SLEEPING cycle already, so `extinguish` followed by the
#   word under test makes the leaked encoding a COMPILE-TIME CONSTANT.
#   (This is why F3++ needs none of slpleak.S's two-pass self-patching: F3+
#   must catch an AWAKE hart, which forces a calibration; F3++ wants a SLEEPING
#   one, which is exactly the edge that is structurally determined.)
#
# THE TEST, and the reason it is a COUNT and not a timeout:
#   park; mtip #1 fires; the ISR irets WITHOUT ignite and re-arms mtip far out.
#     * pre-fix   the IRQ_SV leak already cleared sleep_cpu, so IRQ_REST
#                 RESUMES.  The hart reaches the verdict having seen ONE ISR.
#     * post-fix  sleep_cpu survives, IRQ_REST re-parks, and mtip #2 wakes the
#                 hart -- that ISR does ignite.  The verdict sees TWO ISRs.
#   So the polarity is count==1 FAIL / count==2 PASS, and neither polarity is a
#   watchdog timeout: both ends of the test render a real a0.
#
# THE ANTI-VACUOUS GATE, and it is the load-bearing part:
#   a green count==2 could also be produced by a hart that resumed, ran on, and
#   took the second mtip somewhere else entirely.  So BOTH pushed return PCs are
#   recorded and BOTH must equal &f3pp_word:
#     * retpc1 == &f3pp_word  =>  the word IRQ_SV decoded really was the `ignite`
#     * retpc2 == &f3pp_word  =>  the hart was STILL PARKED AT THE SAME PC when
#                                 the second interrupt arrived, i.e. it really
#                                 did re-park.  A resumed hart cannot produce
#                                 this address.
#
# THE RACE, and how it is sized:  the re-arm delta must be long enough that the
#   PRE-fix path (iret -> resume -> execute the ignite -> disarm mtip, ~4
#   instructions of which one is a shared-window store) cannot be overtaken by
#   mtip #2, or a pre-fix run would falsely count 2.  Measured from csrleak.S's
#   green run, mtime advances ~64 ticks while mcycle advances ~55, i.e. mtime
#   runs at about the core clock rate.  The exposure window is <100 cycles;
#   MTIP_REARM is 4096, an ~40x margin.  The verdict path DISARMS FIRST, before
#   it reads anything.  In the post-fix direction 4096 ticks of extra sleep is
#   ~170 us against the 100 ms testbench watchdog.
#
# Verdict / a1 codes:
#   a0=0xCAFEBABE                   PASS  (the hart re-parked; post-fix)
#   a0=0xDEADBEEF, a1=0xF3F30001    F3++ FIRED -- exactly ONE ISR ran, i.e. the
#                                   iret-without-ignite resumed the hart
#                                   (a2 = the count, a3/a4 = the two retpcs)
#   a0=0xDEADBEEF, a1=0x5E800001    setup: no ISR ran at all
#   a0=0xDEADBEEF, a1=0x5E800002    setup: retpc1 != &f3pp_word -- the leaked
#                                   bus word was not the encoding under test
#   a0=0xDEADBEEF, a1=0x5E800003    setup: retpc2 != &f3pp_word -- the second
#                                   interrupt did not find the hart parked
#   a0=0xDEADBEEF, a1=0x5E800004    setup: more than two ISRs (the re-arm looped)
#
# Shared window: NONE claimed.  The only non-private addresses touched are the
#   CLINT registers themselves (0x5000 page).
#
# Conventions: `.option arch, +zicsr` (rv32ua's -march has no zicsr);
#   `.option norvc` throughout with ONE rvc-enabled `.balign 4` at the top, so
#   every instruction is 4-byte aligned and the F7 half-fetch bubble
#   (csrrevrt.S) is kept OUT of this image entirely.
#   RVTEST_CODE_END is `unimp` in this env, so every path spins.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"                 /* NHARTS (default 4) */

.option norelax

#define MTIP_REARM    4096

/* CLINT offsets from base 0x5000 -- the RTL's N-parameterized layout */
#define MTIME_OFF     ((4*NHARTS + 15) & ~15)
#define MTIME_LO      (MTIME_OFF)
#define MTIMECMP0_LO  (MTIME_OFF + 0x10)
#define MTIMECMP0_HI  (MTIME_OFF + 0x14)

RVTEST_RV32U
RVTEST_CODE_BEGIN

.option arch, +zicsr
.option rvc
    .balign 4                       /* one c.nop of padding if .text.init      */
.option norvc                       /*   started on a halfword -- from here on */
                                    /*   every instruction is 4-byte aligned   */

    li   sp, 0xBFF0                 # sp MUST be valid before any IRQ

    # ---- clear the observation words ------------------------------------
    la   t3, f3pp_count
    sw   x0, 0(t3)
    la   t3, f3pp_retpc1
    sw   x0, 0(t3)
    la   t3, f3pp_retpc2
    sw   x0, 0(t3)

    # ---- arm mtip a little in the future --------------------------------
    li   s2, 0x5000
    lw   t1, MTIME_LO(s2)
    addi t1, t1, 64
    sw   t1, MTIMECMP0_LO(s2)       # cmp lo FIRST (cmp hi still all-ones: quiet)
    sw   x0, MTIMECMP0_HI(s2)       # ...then hi = 0: ARMED

    # ---- park.  The next word is what IRQ_SV will decode. ---------------
    extinguish                      # -> SLEEPING; data_addr = pc_next_reg =
                                    #    &f3pp_word for every cycle of the park
f3pp_word:
    ignite                          # DECODED LIVE IN IRQ_SV (pre-fix that CLEARS
                                    #   sleep_cpu).  When finally EXECUTED for
                                    #   real the hart is already awake, so this
                                    #   is architecturally a no-op either way --
                                    #   the leak is the only thing it can prove.

f3pp_resume:
    # =====================================================================
    # VERDICT.  DISARM FIRST -- before reading anything -- so a late mtip #2
    # can never turn a pre-fix run into a false PASS.
    # =====================================================================
    li   t5, 0x5000
    li   t6, -1
    sw   t6, MTIMECMP0_HI(t5)       # cmp hi = all-ones: mtip quiet forever

    la   t3, f3pp_count
    lw   a2, 0(t3)
    beqz a2, f3pp_setup1            # no ISR ran at all

    la   t3, f3pp_retpc1
    lw   a3, 0(t3)
    la   t5, f3pp_word
    bne  a3, t5, f3pp_setup2        # a different word was on the bus

    li   t4, 1
    beq  a2, t4, f3pp_fired         # exactly ONE ISR => the hart never re-parked

    li   t4, 2
    bne  a2, t4, f3pp_setup4        # three or more => the re-arm looped

    la   t3, f3pp_retpc2
    lw   a4, 0(t3)
    la   t5, f3pp_word
    bne  a4, t5, f3pp_setup3        # #2 did not find the hart parked here
    RVTEST_PASS                     # a0 = 0xCAFEBABE

f3pp_fired:
    li   a1, 0xF3F30001
    j    f3pp_fail
f3pp_setup1:
    li   a1, 0x5E800001
    j    f3pp_fail
f3pp_setup2:
    li   a1, 0x5E800002
    j    f3pp_fail
f3pp_setup3:
    li   a1, 0x5E800003
    j    f3pp_fail
f3pp_setup4:
    li   a1, 0x5E800004
f3pp_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    # =====================================================================
    # mtip ISR (IVT slot 84, hardware-vectored).
    #   entry 1: record, RE-ARM, iret WITHOUT ignite  <- the mechanism under test
    #   entry 2: record, DISARM, ignite, iret         <- the post-fix exit
    # =====================================================================
f3pp_mtip_isr:
    addi sp, sp, -20
    sw   t2, 0(sp)
    sw   t3, 4(sp)
    sw   t4, 8(sp)
    sw   t5, 12(sp)
    sw   t6, 16(sp)

    lw   t4, 20(sp)                 # the return PC hardware pushed at sp-4

    la   t3, f3pp_count
    lw   t2, 0(t3)
    addi t2, t2, 1
    sw   t2, 0(t3)                  # count := count + 1

    li   t5, 1
    bne  t2, t5, f3pp_isr_second

    # ---- entry 1: stash retpc1, re-arm mtip far out, iret WITHOUT ignite -
    la   t3, f3pp_retpc1
    sw   t4, 0(t3)

    li   t5, 0x5000
    lw   t6, MTIME_LO(t5)
    li   t3, MTIP_REARM
    add  t6, t6, t3
    sw   t6, MTIMECMP0_LO(t5)       # lo first...
    sw   x0, MTIMECMP0_HI(t5)       # ...then hi = 0: re-ARMED

    lw   t2, 0(sp)
    lw   t3, 4(sp)
    lw   t4, 8(sp)
    lw   t5, 12(sp)
    lw   t6, 16(sp)
    addi sp, sp, 20
    iret                            # NO ignite: sleep_cpu must carry us back
                                    #   to SLEEPING.  Pre-fix the IRQ_SV leak
                                    #   already cleared it and we resume here.

f3pp_isr_second:
    # ---- entry 2 (post-fix only): stash retpc2, disarm, ignite, iret -----
    la   t3, f3pp_retpc2
    sw   t4, 0(t3)

    li   t5, 0x5000
    li   t6, -1
    sw   t6, MTIMECMP0_HI(t5)       # disarm

    lw   t2, 0(sp)
    lw   t3, 4(sp)
    lw   t4, 8(sp)
    lw   t5, 12(sp)
    lw   t6, 16(sp)
    addi sp, sp, 20
    ignite                          # the hart IS sleeping here: wake it
    iret

    # ---- extend the env IVT: DEFINE_IVT emitted slots 0-82 ---------------
    .section .ivt, "ax"
    .org 0x14C
    jal  zero, 0x0BB00              # slot 83 = IRQB_CLINT_MSIP -- parked
    jal  zero, f3pp_mtip_isr        # slot 84 = IRQB_CLINT_MTIP
    .previous

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
f3pp_count:  .word 0
f3pp_retpc1: .word 0
f3pp_retpc2: .word 0
  TEST_DATA
RVTEST_DATA_END
