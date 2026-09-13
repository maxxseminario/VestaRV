# See LICENSE for license details.

# VestaRV: detector for a CSR write leaked by the legacy interrupt-entry state
# THE DEFECT: IRQ_SV decodes a LIVE BUS WORD and csr_valid is not suppressed there, so an instruction that never executes commits a CSR write. `instr_curr <= instr when current_state = IRQ_SV` is the first matching arm of the instr_curr mux and wins over the hold arm, csr_addr comes from instr_curr(31:20), and csr_valid_eff is only squashed by trap_entry_seq or pmp_if_squash, both low on the legacy path. IRQ_SV forces reg_write_dp low, so the phantom decode writes no register and the CSR write is the only escaping side effect, which is why it survived a year of regression.
# THE BUS WORD IS MADE DETERMINISTIC BY CONSTRUCTION. In every state preceding IRQ_SV data_addr falls through to pc_next, so the word on read_data during IRQ_SV is the instruction at the resume PC. This test uses the SLEEPING to IRQ_SV edge, where the SLEEPING arm holds pc_next = pc_next_reg and the fetch of that word has already been issued every sleeping cycle, so `extinguish` followed by the trap word makes the leaked encoding a compile-time constant with no interrupt-latency calibration.
# THE SYMMETRY TRAP: the leaked word is the same encoding with the same source register the hart will legitimately execute after iret, so both writes carry the same value and the leak would be invisible. The observation is therefore made INSIDE the ISR, BEFORE the trap word has ever executed, and all three conditions are required: mcycle at ISR entry already holds the payload, the trap word's rd is still 0, and the hardware-pushed return PC is the trap word's address. The last two are the anti-vacuous-pass gate.
# mcycle, NOT mscratch OR minstret: in the default build csr_unit's csr_addr_stores admits only mcycle, mcycleh, minstret and minstreth, and minstret is another finding's subject, so a detector built on it would couple two waves' evidence. mcycle free-runs, and the payload 0xC5C5C5C5 is about 137 s of 24 MHz counting away from anything this test can otherwise produce. ALWAYS RANGE-CHECK IT, NEVER COMPARE FOR EQUALITY.
# Verdicts: a0 = 0xCAFEBABE passes; a0 = 0xDEADBEEF with a1 = 0xF3F3F3F3 means the leak fired and a2 holds the value read at ISR entry; a1 = 0x5E800001 means the mtip ISR never ran; 0x5E800002 means the pushed return PC is not the trap word, in a3, so the leaked bus word was not the encoding under test; 0x5E800003 means the trap word's rd was already written, in a4, so it executed before the ISR and the observation proves nothing.
# No shared window is claimed; the only non-private addresses touched are the CLINT registers. `.option arch, +zicsr` is needed because rv32ua's -march has none, and `.option norvc` throughout with ONE rvc-enabled `.balign 4` at the top keeps every instruction 4-byte aligned, which keeps the half-fetch bubble out of this test so any leak is attributable to IRQ_SV alone. RVTEST_CODE_END is `unimp` here, so every path spins.

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"                 /* NHARTS (default 4) */

.option norelax

#define MCYCLE        0xB00

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
    la   t3, f3_flag
    sw   x0, 0(t3)
    la   t3, f3_mcycle
    sw   x0, 0(t3)
    la   t3, f3_retpc
    sw   x0, 0(t3)
    la   t3, f3_witness
    sw   x0, 0(t3)

    # ---- arm mtip a little in the future --------------------------------
    li   s2, 0x5000
    lw   t1, MTIME_LO(s2)
    addi t1, t1, 64
    sw   t1, MTIMECMP0_LO(s2)       # cmp lo FIRST (cmp hi still all-ones: quiet)
    sw   x0, MTIMECMP0_HI(s2)       # ...then hi = 0: ARMED

    # ---- the two registers the leaked decode will read ------------------
    li   t0, 0xC5C5C5C5             # rs1 of the trap word: the payload
    li   t1, 0                      # rd  of the trap word: the WITNESS

    # ---- low anchor so the payload is unmistakable ----------------------
    li   t2, 0x00001000
    csrrw x0, MCYCLE, t2            # mcycle <- 0x1000

    # ---- park.  The next word is what IRQ_SV will decode. ---------------
    extinguish                      # -> SLEEPING; data_addr = pc_next_reg =
                                    #    &f3_trap for every cycle of the park
f3_trap:
    csrrw t1, MCYCLE, t0            # DECODED LIVE IN IRQ_SV (pre-fix), and
                                    #   only LATER executed for real, after
                                    #   the ISR has already made its reading
f3_after:

    # =====================================================================
    # VERDICT (t0/t1 have been clobbered by the real execution of f3_trap;
    #          everything load-bearing was captured into memory by the ISR)
    # =====================================================================
    la   t3, f3_flag
    lw   t4, 0(t3)
    beqz t4, f3_setup1              # the ISR never ran

    la   t3, f3_retpc
    lw   a3, 0(t3)
    la   t5, f3_trap
    bne  a3, t5, f3_setup2          # a different word was on the bus

    la   t3, f3_witness
    lw   a4, 0(t3)
    bnez a4, f3_setup3              # the trap word had already executed

    la   t3, f3_mcycle
    lw   a2, 0(t3)                  # mcycle as read at ISR entry
    li   t5, 0xC5C5C5C5
    bgeu a2, t5, f3_fired           # it already held the payload => LEAK
    RVTEST_PASS                     # a0 = 0xCAFEBABE

f3_fired:
    li   a1, 0xF3F3F3F3
    j    f3_fail
f3_setup1:
    li   a1, 0x5E800001
    j    f3_fail
f3_setup2:
    li   a1, 0x5E800002
    j    f3_fail
f3_setup3:
    li   a1, 0x5E800003
f3_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    # =====================================================================
    # mtip ISR (IVT slot 84, hardware-vectored).  Hart 0 is ASLEEP here, so
    # it MUST ignite before iret or the iret returns it straight to SLEEPING.
    # =====================================================================
f3_mtip_isr:
    addi sp, sp, -20
    sw   t2, 0(sp)
    sw   t3, 4(sp)
    sw   t4, 8(sp)
    sw   t5, 12(sp)
    sw   t6, 16(sp)

    csrrs t2, MCYCLE, x0            # THE OBSERVABLE, read as early as possible
    la   t3, f3_mcycle
    sw   t2, 0(t3)

    la   t3, f3_witness             # the trap word's rd -- must still be 0
    sw   t1, 0(t3)

    lw   t4, 20(sp)                 # the return PC hardware pushed at sp-4
    la   t3, f3_retpc
    sw   t4, 0(t3)

    li   t4, 1
    la   t3, f3_flag
    sw   t4, 0(t3)

    li   t5, 0x5000                 # disarm mtip: cmp hi back to all-ones
    li   t6, -1
    sw   t6, MTIMECMP0_HI(t5)

    lw   t2, 0(sp)
    lw   t3, 4(sp)
    lw   t4, 8(sp)
    lw   t5, 12(sp)
    lw   t6, 16(sp)
    addi sp, sp, 20
    ignite                          # the hart was SLEEPING: wake it
    iret

    # ---- extend the env IVT: DEFINE_IVT emitted slots 0-82 ---------------
    .section .ivt, "ax"
    .org 0x14C
    jal  zero, 0x0BB00              # slot 83 = IRQB_CLINT_MSIP -- parked
    jal  zero, f3_mtip_isr          # slot 84 = IRQB_CLINT_MTIP
    .previous

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
f3_flag:    .word 0
f3_mcycle:  .word 0
f3_retpc:   .word 0
f3_witness: .word 0
  TEST_DATA
RVTEST_DATA_END
