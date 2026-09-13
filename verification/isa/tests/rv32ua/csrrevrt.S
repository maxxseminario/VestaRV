# See LICENSE for license details.

# VestaRV: detector for a CSR write reverted by the compressed half-fetch bubble
# THE DEFECT: an EXECUTE cycle with pc(1) = '1', quadrant_upper = "11" and repeat_if = '0' is the split-fetch bubble of a 32-bit instruction starting on a halfword boundary. Its FSM arm suppresses reg_write_dp, wen and pc_en and nothing else, while instr_curr holds instr_curr_prev, so the PREVIOUS, ALREADY RETIRED instruction is decoded again. csr_valid_eff is only squashed by trap_entry_seq or pmp_if_squash, both low here, so csr_write_en re-fires with csr_wdata read live from rf[rs1]. For the swap idiom `csrrw rd, csr, rd` the previous cycle already committed rd = the OLD csr value, so the bubble writes the CSR back to its own old value and the architectural write is REVERTED.
# mcycle, NOT mscratch OR minstret: in the default build every ENABLE_* knob is false and csr_unit's csr_addr_stores then admits exactly four storing CSRs, mcycle, mcycleh, minstret and minstreth, so a detector aimed at mscratch, mtvec, jvt, fflags or the PMP registers is green before and after the fix and proves nothing. minstret is another finding's subject and is avoided so this evidence stays uncoupled. mcycle free-runs, and the payload 0xC5C5C5C5 is about 137 s of 24 MHz counting away from any boot-era count. ALWAYS RANGE-CHECK IT, NEVER COMPARE FOR EQUALITY.
# The same two-instruction idiom runs twice. STEP 1 is misaligned: the csrrw at 4n+2 and the reading csrrs at 4n+6, so the reader's own half-fetch bubble re-fires the csrrw's write. STEP 2 is the aligned control, an identical pair at 4n and 4n+4 with no bubble. THE CONTROL MUST ALWAYS READ BACK THE PAYLOAD; only the misaligned read moves, which isolates alignment as the cause rather than the CSR, the register choice or the read path.
# Verdicts: a0 = 0xCAFEBABE passes; a0 = 0xDEADBEEF with a1 = 0xF7F7F7F7 means the revert fired and a2 holds the pre-swap counter the misaligned read saw; a1 = 0x5E800001 means the misaligned csrrw did not swap; a1 = 0x5E800002 means the ALIGNED control also failed, so the CSR write path itself is broken and step 1 proves nothing. At the verdict a2 is step 1's read-back, a3 is step 1's csrrw rd and a4 is step 2's read-back.
# No shared window is claimed and no peripheral is touched; the test runs entirely out of hart 0's private TCM. `.option arch, +zicsr` is needed because rv32ua's -march has none, `.option norvc` is used everywhere except the two deliberate c.nop alignment shims, and RVTEST_CODE_END is `unimp` here, so every path spins.

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
