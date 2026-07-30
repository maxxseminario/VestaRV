# See LICENSE for license details.

#*****************************************************************************
# csrleak.S   (F-series fix pass, W2 -- the DETECTOR for finding F3)
#-----------------------------------------------------------------------------
# F3: the legacy interrupt-entry state IRQ_SV DECODES A LIVE BUS WORD, and
# csr_valid is not suppressed there, so an unexecuted instruction commits a
# CSR write.
#
# Mechanism, re-anchored to the RTL (hdl/common/vesta/vesta.vhd, rtl-fixpass):
#   * instr_curr <= instr when current_state = IRQ_SV  is the FIRST matching
#     arm of the instr_curr mux, so it WINS over the instr_curr_prev hold arm
#     further down. IRQ_SV therefore decodes the raw unified-bus word.
#   * csr_addr <= instr_curr(31 downto 20) and csr_valid_eff = csr_valid and
#     not dec_squash; dec_squash is trap_entry_seq/pmp_if_squash only, both
#     '0' on the legacy path. So csr_write_en fires in IRQ_SV with csr_wdata
#     read LIVE from rf[rs1].
#   * IRQ_SV's own FSM arm forces reg_write_dp <= '0', so the phantom decode
#     writes NO register -- the CSR write is the only escaping side effect,
#     which is exactly why it survived twelve months of regression.
#
# HOW THE BUS WORD IS MADE DETERMINISTIC (this is the design of the test):
#   In every state that precedes IRQ_SV, data_addr falls through to pc_next,
#   so the word that lands on read_data during IRQ_SV is the instruction at
#   the resume PC. Rather than race an interrupt against a running pipeline,
#   this test uses the SLEEPING -> IRQ_SV edge: the SLEEPING arm holds
#   pc_next = pc_next_reg and the RTL's own comment states that the fetch of
#   that word "has been issued from data_addr every SLEEPING cycle already".
#   So `extinguish` followed by the trap word makes the leaked encoding a
#   COMPILE-TIME CONSTANT, with no interrupt-latency calibration at all.
#
# THE SYMMETRY TRAP, and how it is broken:
#   The leaked word is the same encoding, with the same source register, that
#   the hart will legitimately execute after iret -- so both writes would
#   carry the same value and the leak would be invisible. The observation is
#   therefore made INSIDE the ISR, BEFORE the trap word has ever executed:
#     * mcycle read at ISR entry ~= the payload  => the leak already wrote it
#     * the trap word's rd (t1) still 0          => it has NOT executed
#     * the hardware-pushed return PC == the trap word's address
#   All three are required; the last two are the anti-vacuous-pass gate.
#
# WHY mcycle AND NOT mscratch/minstret: see csrrevrt.S -- in the DEFAULT build
#   csr_unit.vhd's csr_addr_stores() admits only mcycle/mcycleh/minstret/
#   minstreth, and minstret is finding F1's subject (wave W3 changes how it
#   counts), so a detector built on it would couple two waves' evidence.
#   mcycle free-runs; the payload 0xC5C5C5C5 is ~137 s of 24 MHz counting away
#   from any value this test can otherwise produce. RANGE check, never equality.
#
# Verdict / a1 codes:
#   a0=0xCAFEBABE                   PASS  (no leak; post-fix expectation)
#   a0=0xDEADBEEF, a1=0xF3F3F3F3    F3 FIRED -- mcycle already held the payload
#                                   at ISR entry (a2 = the value read there)
#   a0=0xDEADBEEF, a1=0x5E800001    setup: the mtip ISR never ran
#   a0=0xDEADBEEF, a1=0x5E800002    setup: the pushed return PC is not the trap
#                                   word (a3 = what was pushed) -- the leaked
#                                   bus word was NOT the encoding under test
#   a0=0xDEADBEEF, a1=0x5E800003    setup: the trap word's rd was already
#                                   written (a4) -- it executed before the ISR,
#                                   so the observation proves nothing
#
# Shared window: NONE claimed. The only non-private addresses touched are the
#   CLINT registers themselves (0x5000 page); no shared scratch word is used.
#
# Conventions: `.option arch, +zicsr` (rv32ua's -march has no zicsr);
#   `.option norvc` throughout with ONE rvc-enabled `.balign 4` at the top so
#   every instruction in this image is 4-byte aligned -- that keeps the F7
#   half-fetch bubble (csrrevrt.S) OUT of this test entirely, so any CSRLEAK
#   this image emits is attributable to IRQ_SV (tracer state 09) alone.
#   RVTEST_CODE_END is `unimp` in this env, so every path spins.
#*****************************************************************************

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
