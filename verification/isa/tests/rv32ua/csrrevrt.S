# See LICENSE for license details.

#*****************************************************************************
# csrrevrt.S   (F-series fix pass, W2 -- the DETECTOR for finding F7)
#-----------------------------------------------------------------------------
# F7: the CSR write is REVERTED by the compressed half-fetch bubble.
#
# Mechanism, re-anchored to the RTL (hdl/common/vesta/vesta.vhd, branch
# rtl-fixpass):
#   * shape E -- EXECUTE with pc(1)='1', quadrant_upper="11", repeat_if='0' --
#     is the split-fetch bubble of a 32-bit instruction that starts on a
#     halfword boundary. Its FSM arm suppresses reg_write_dp, wen and pc_en
#     and NOTHING else.
#   * in that cycle instr_curr = instr_curr_prev, i.e. the PREVIOUS, ALREADY
#     RETIRED instruction is decoded again.
#   * csr_valid_eff = csr_valid and not dec_squash, and dec_squash is
#     trap_entry_seq/pmp_if_squash only -- both '0' here. So csr_write_en
#     re-fires, with csr_addr = instr_curr(31:20) and csr_wdata read LIVE
#     from rf[rs1].
#   For the swap idiom `csrrw rd, csr, rd` the previous cycle already committed
#   rd = the OLD csr value, so the bubble writes the CSR back to its own old
#   value: the architectural write is REVERTED.
#
# WHY mcycle AND NOT mscratch/minstret:
#   In the DEFAULT build every ENABLE_* knob is false (hart_tile.vhd), and
#   csr_unit.vhd's csr_addr_stores() then admits EXACTLY FOUR storing CSRs:
#   mcycle, mcycleh, minstret, minstreth. mscratch/mtvec/jvt/fflags/PMP cannot
#   be written at all, so a detector aimed at them is green before and after
#   the fix and proves nothing.  minstret is deliberately avoided: it is
#   finding F1's subject and wave W3 changes how it counts, which would couple
#   this wave's evidence to another wave's fix.  mcycle free-runs, which is
#   fine -- the payload 0xC5C5C5C5 is ~3.3e9, i.e. ~137 s of 24 MHz counting
#   away from any boot-era count, so a RANGE check separates the two states
#   with an enormous margin. Never compare mcycle for equality.
#
# Shape of the test: the SAME two-instruction idiom is run twice.
#   STEP 1  misaligned (the bug): csrrw at 4n+2, the reading csrrs at 4n+6, so
#           the reader's own half-fetch bubble re-fires the csrrw's write.
#   STEP 2  aligned CONTROL: identical pair at 4n and 4n+4, no bubble.
#   The control must ALWAYS read back the payload; only the misaligned read
#   moves. That isolates the alignment as the cause rather than the CSR, the
#   register choice or the read path.
#
# Verdict / a1 codes:
#   a0=0xCAFEBABE                    PASS  (no revert; post-fix expectation)
#   a0=0xDEADBEEF, a1=0xF7F7F7F7     F7 FIRED -- the misaligned read saw the
#                                    pre-swap counter (a2 holds it)
#   a0=0xDEADBEEF, a1=0x5E800001     setup: the misaligned csrrw did not swap
#   a0=0xDEADBEEF, a1=0x5E800002     setup: the ALIGNED control also failed,
#                                    so the CSR write path itself is broken and
#                                    STEP 1 proves nothing
# Live registers at the verdict: a2 = STEP 1 read-back, a3 = STEP 1 csrrw rd,
#   a4 = STEP 2 (control) read-back.
#
# Shared window: NONE. This test claims no shared scratch word at all and
#   touches no peripheral; it runs entirely out of hart 0's private TCM.
#
# Conventions: `.option arch, +zicsr` because rv32ua's -march has no zicsr;
#   `.option norvc` everywhere except the two deliberate c.nop alignment
#   shims; RVTEST_CODE_END is `unimp` in this env so every path spins.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norelax

#define MCYCLE   0xB00

RVTEST_RV32U
RVTEST_CODE_BEGIN

.option arch, +zicsr
.option norvc

    li   sp, 0xBFF0                 # sp valid before anything (no IRQs here,
                                    #   but the env convention is absolute)

    # =====================================================================
    # STEP 1 -- the MISALIGNED pair.  The whole finding is the alignment.
    # =====================================================================
    li   t0, 0xC5C5C5C5             # the payload the swap puts into mcycle
    li   t1, 0x00001000             # a low anchor so the "old" value is small
    csrrw x0, MCYCLE, t1            # mcycle <- 0x1000 (word-aligned: no bubble)

.option rvc
    .balign 4
    c.nop                           # 2 bytes: PC is now 4n+2, pc(1) = '1'
.option norvc
f7_swap:
    csrrw t0, MCYCLE, t0            # 32-bit @ 4n+2: split fetch, then dispatch.
                                    #   commits t0 = old mcycle, mcycle = payload
f7_read:
    csrrs t2, MCYCLE, x0            # 32-bit @ 4n+6: ITS half-fetch bubble is
                                    #   shape E, and re-decodes f7_swap with
                                    #   rf[t0] = the OLD mcycle -> revert.
                                    #   csrrs with rs1=x0 never writes, so this
                                    #   instruction's own later bubble is inert.
.option rvc
    c.nop                           # realign: PC back to 4n
.option norvc
    .balign 4

    mv   a2, t2                     # STEP 1 read-back  (the observable)
    mv   a3, t0                     # STEP 1 csrrw rd   (must be the old count)

    li   t4, 0xC5C5C5C5
    beq  a3, t4, f7_setup1          # rd untouched => the csrrw never retired
    bgeu a3, t4, f7_setup1          # rd must be the small pre-swap counter

    # =====================================================================
    # STEP 2 -- the ALIGNED control.  Same idiom, no bubble, must always pass.
    # =====================================================================
    li   t0, 0xC5C5C5C5
    li   t1, 0x00001000
    csrrw x0, MCYCLE, t1            # mcycle <- 0x1000 again
    .balign 4
f7_swapa:
    csrrw t0, MCYCLE, t0            # 32-bit @ 4n: shape A, retires in one cycle
f7_reada:
    csrrs t3, MCYCLE, x0            # 32-bit @ 4n+4: shape A, no bubble
    mv   a4, t3

    li   t5, 0xC5D00000
    bltu a4, t4, f7_setup2          # control below the payload => write path broken
    bgeu a4, t5, f7_setup2          # ...or wildly above it

    # =====================================================================
    # VERDICT
    # =====================================================================
    bltu a2, t4, f7_fired           # misaligned read below the payload = REVERT
    bgeu a2, t5, f7_fired
    RVTEST_PASS                     # a0 = 0xCAFEBABE

f7_fired:
    li   a1, 0xF7F7F7F7
    j    f7_fail
f7_setup1:
    li   a1, 0x5E800001
    j    f7_fail
f7_setup2:
    li   a1, 0x5E800002
f7_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
