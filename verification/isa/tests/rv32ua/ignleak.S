# See LICENSE for license details.

# VestaRV: detector for an `ignite` leaked by the legacy interrupt-entry state
# THE DEFECT is the mirror image of the `extinguish` leak slpleak.S covers, and the second consumer of the same live IRQ_SV decode: an `ignite` encoding decoded in IRQ_SV CLEARS sleep_cpu, so a SLEEPING hart RESUMES instead of re-parking. `instr_curr <= instr when current_state = IRQ_SV` is the first matching arm of the mux, so IRQ_SV decodes the raw bus word; maindec's wake_rq is a PURE DECODE with no state qualification; and the sleep_cpu flop is on the free-running clock, gated only by dec_squash, which is low on the legacy path. IRQ_REST's re-park arm is then not taken.
# THAT MATTERS ON SILICON: the boot ROM park contract is built on iret-WITHOUT-ignite meaning "go back to sleep", both for the harvested-boot stray-msip ISR and for the tile park. A parked tile that silently wakes spins in its paranoia loop, burning power and shared-bus bandwidth on a chip that has just gated its rails.
# THE BUS WORD IS MADE DETERMINISTIC with no interrupt-latency calibration, using the SLEEPING to IRQ_SV edge: in SLEEPING pc_next is held at pc_next_reg and the fetch of that word has already been issued every sleeping cycle, so `extinguish` followed by the word under test makes the leaked encoding a compile-time constant. That is also why this file needs none of slpleak.S's two-pass self-patching, which exists because its subject must catch an AWAKE hart.
# THE TEST IS A COUNT, NOT A TIMEOUT: park, let mtip fire, and have the ISR iret WITHOUT ignite while re-arming mtip far out. With the leak the hart resumes and reaches the verdict having seen ONE ISR; without it sleep_cpu survives, IRQ_REST re-parks, and a second mtip wakes the hart into an ISR that does ignite, so the verdict sees TWO. Neither polarity is a watchdog timeout.
# THE ANTI-VACUOUS GATE IS THE LOAD-BEARING PART: a count of two could also come from a hart that resumed, ran on and took the second mtip elsewhere. So BOTH pushed return PCs are recorded and both must equal &f3pp_word, the first proving the word IRQ_SV decoded really was the `ignite` and the second proving the hart was STILL PARKED AT THE SAME PC when the second interrupt arrived. A resumed hart cannot produce that address.
# THE RE-ARM DELTA IS SIZED, NOT GUESSED: it must be long enough that the leaking path, iret, resume, execute the ignite and disarm mtip, about four instructions of which one is a shared-window store, cannot be overtaken by the second mtip, or a leaking run would falsely count two. mtime runs at about the core clock rate, the exposure window is under 100 cycles, and MTIP_REARM is 4096, roughly a 40x margin; in the other direction 4096 ticks of extra sleep is about 170 us against the 100 ms watchdog. THE VERDICT PATH DISARMS FIRST, before it reads anything.
# Verdicts: a0 = 0xCAFEBABE means the hart re-parked. a0 = 0xDEADBEEF with a1 = 0xF3F30001 means exactly one ISR ran, so the iret without ignite resumed the hart, with a2 the count and a3 and a4 the two return PCs; a1 = 0x5E800001 no ISR ran at all; 0x5E800002 the first return PC is not &f3pp_word, so the leaked bus word was not the encoding under test; 0x5E800003 the second return PC is not &f3pp_word, so the second interrupt did not find the hart parked; 0x5E800004 more than two ISRs, so the re-arm looped.
# No shared window is claimed; the only non-private addresses touched are the CLINT registers. `.option arch, +zicsr` is needed because rv32ua's -march has none, and `.option norvc` throughout with ONE rvc-enabled `.balign 4` at the top keeps every instruction 4-byte aligned, which keeps the half-fetch bubble out of this image. RVTEST_CODE_END is `unimp` here, so every path spins.

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
