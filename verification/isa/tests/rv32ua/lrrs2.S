# See LICENSE for license details.

#*****************************************************************************
# lrrs2.S   (F-series fix pass, wave W4 -- DETECTOR for finding F6)
#-----------------------------------------------------------------------------
# F6: `lr.w` with a NON-ZERO rs2 field reads  rs1 + reg[rs2]  while arming the
#     reservation at  rs1.  Read and reservation land on DIFFERENT addresses.
#
#   maindec.vhd:846-865   the AMO_OPCODE valid_funct arm whitelists on funct3 +
#                         funct5 ONLY.  There is no rs2 term, here or at
#                         maindec.vhd:507 (`lr_op`), so the encoding is a LEGAL
#                         DECODE with any rs2 -- reserved by the ISA, accepted
#                         by this core.
#   maindec.vhd:997-1009  ALU_src falls through to '0' for AMO_OPCODE (comment:
#                         "Use register (rs1 for address)"), and aludec/ALU do
#                         ADD, so ALU_Result = reg[rs1] + reg[rs2].
#   vesta.vhd:2621-2625   the EXECUTE dispatch arm for lr_op asserts
#                         mem_access_instr <= '1' and goes to LR_READ.
#   vesta.vhd:1819-1823   data_addr takes `rs1_value` ONLY for
#                         `EXECUTE and amo_op = '1'` -- lr_op is NOT in that
#                         arm -- so it falls to `ALU_Result when
#                         (mem_access_instr = '1' ... or LR_READ)`.  BOTH the
#                         EXECUTE cycle and LR_READ therefore address at
#                         rs1 + reg[rs2].
#   vesta.vhd:1375-1377   reservation_addr <= rs1_value   in LR_READ.
#                         ("M4b: rs1 IS the LR address (phase-independent)")
#
#   The sibling members of the family were ALL fixed for exactly this reason
#   and say so in the RTL: vesta.vhd:2627-2630 for SC ("M4b FIX: no
#   EXECUTE-phase access -- the ALU holds rs1+rs2 here (garbage addr)") and
#   the `EXECUTE and amo_op` arm for AMO (the M8 dispatch-cycle bug).  `lr.w`
#   is the one member that was left out.
#
# THE ASSEMBLER WILL NOT EMIT THIS.  `lr.w rd,(rs1)` forces rs2 = x0.  The test
# uses `.insn r 0x2f, 2, 0x08, rd, rs1, rs2` -- opcode AMO, funct3 = 010
# (AMO_WIDTH_W), funct7 = 0001000 = {funct5 = LR_FN5 00010, aq = 0, rl = 0} --
# which is a hand-built `lr.w` with the rs2 field set.  The encoding is verified
# from `riscv-none-elf-objdump -d` on the BUILT image, never from the source.
#
# ---------------------------------------------------------------------------
# THE OBSERVABLE: which address was actually READ
# ---------------------------------------------------------------------------
# Two words hold two DISTINCT sentinels.  reg[rs2] is set to (B - A) at run
# time by a `sub`, so nothing is hardcoded and the leg cannot silently stop
# discriminating if the linker moves anything.
#
#   [rs1]      = A : VAL_A = 0xA5A50001
#   [rs1+rs2]  = B : VAL_B = 0x5A5A0002
#
#   rd == VAL_B  ->  the read went to rs1 + reg[rs2].   F6 FIRED.   (pre-fix)
#   rd == VAL_A  ->  the read went to rs1.                          (post-fix)
#
# LEG 1 runs it in the PRIVATE TCM, LEG 2 in the SHARED window.  Both are
# required, and leg 2 is the one a HALF FIX cannot satisfy -- see below.
#
# ---------------------------------------------------------------------------
# THE TWO CONTROLS THAT PIN THE RESERVATION SIDE
# ---------------------------------------------------------------------------
# (a) LOCAL reservation (leg 1, TCM).  reservation_addr is already rs1_value
#     (vesta.vhd:1377), so an `sc.w` to rs1 SUCCEEDS pre-fix and must STILL
#     succeed post-fix.  This is a CONTROL: the fix moves the READ, not the
#     reservation, and a fix that broke this has changed the wrong thing.
#
# (b) GLOBAL reservation (leg 2, SHARED).  hart_tile drives lr_sc_bus = "01"
#     during the LR's EXECUTE cycle (vesta.vhd:1907) and the resv_unit arms at
#     whatever data_addr carried -- i.e. at rs1 + reg[rs2] pre-fix.  A later
#     `sc.w` at rs1 then fails through sc_fail_ext even though the LOCAL check
#     passes.  So leg 2's `sc.w` must SUCCEED post-fix.
#
#     THIS IS THE CRITERION A WRONG FIX CANNOT SATISFY.  A fix that steers only
#     LR_READ, or only the EXECUTE arm, leaves one of the two shared checks
#     broken: steering LR_READ alone leaves the global reservation (and the
#     EXECUTE-cycle transaction) at rs1+rs2, so leg 2's sc.w still fails;
#     steering EXECUTE alone leaves LR_READ re-presenting a DIFFERENT word
#     address to a window whose ack is word-address-qualified
#     (hart_tile.vhd:717 sh_acked_addr), so leg 2's rd comes back from the
#     wrong place again.  Only a consistent fix makes BOTH shared checks green
#     while leaving both TCM controls untouched.
#
# ---------------------------------------------------------------------------
# ANTI-VACUOUS GATES (enforced in the image, both polarities)
# ---------------------------------------------------------------------------
#   * both sentinels are written and READ BACK before the probe, so a leg can
#     never pass because the memory never held what the test thinks;
#   * the two sentinels are DIFFERENT and the delta is nonzero -- checked, not
#     assumed;
#   * a CANARY word sits between A and B in both legs and must be untouched, so
#     a store landing NEAR a target cannot be mistaken for a clean run;
#   * rs2's value is computed (`sub`), never a literal.
#
# ---------------------------------------------------------------------------
# Verdict / a1 codes
# ---------------------------------------------------------------------------
#   a0=0xCAFEBABE                  PASS (post-fix expectation)
#   a0=0xDEADBEEF, a1=0xF6F60001   LEG 1 (TCM):    lr.w read [rs1+rs2]
#   a0=0xDEADBEEF, a1=0xF6F60002   LEG 2 (SHARED): lr.w read [rs1+rs2]
#   a0=0xDEADBEEF, a1=0xF6F60003   LEG 2: the sc.w at rs1 FAILED -- the global
#                                  reservation was armed at rs1+rs2
#   a0=0xDEADBEEF, a1=0x5E600001   TCM sentinel setup/read-back broke
#   a0=0xDEADBEEF, a1=0x5E600002   SHARED sentinel setup/read-back broke
#   a0=0xDEADBEEF, a1=0x5E600003   the two sentinels are equal, or a delta is 0
#                                  -- the probe could not discriminate
#   a0=0xDEADBEEF, a1=0x5E600004   CONTROL (a): the TCM sc.w at rs1 failed, or
#                                  did not store at rs1 -- the LOCAL reservation
#                                  moved.  Not an F6 result.
#   a0=0xDEADBEEF, a1=0x5E600005   a canary moved -- a store landed near a target
#
# Registers live at the verdict:
#   a2 leg-1 lr rd      a3 leg-1 sc rd     a4 mem[TCM A] after sc
#   a5 mem[TCM B]       a6 leg-2 lr rd     a7 leg-2 sc rd
#   s6 mem[SH_A] after sc      s7 mem[SH_B]
#   s2 TCM delta        s5 SHARED delta
#
# ---------------------------------------------------------------------------
# SHARED WORDS CLAIMED: 0x10408 .. 0x10414 (4 words), all written before read.
#   0x10408 = SH_A (rs1 target), 0x1040C = canary, 0x10410 = SH_B (rs1+rs2
#   target), 0x10414 = spare/second canary.
#   FREE AT N=4: shexec.S's DONE[3] tops at 0x103E4 and W3's insretov band ends
#   at 0x10404; W1's scfailrd band starts at 0x10420.  This claim is the gap
#   between them.  Both < 0x10500 and inside the bootrom zero range (< 0x10800).
#   AT N=18 it overlaps shexec's DONE[12..15] -- benign under CLAUDE.md's
#   isolation rule (one image per sim); this test is single-hart and is NOT in
#   the standing TEST_FILES array, so the two can never coexist.
#
# Single hart.  Tiles 1-3 are never launched (tb: "tile hart(s) silent/parked").
# RVTEST_CODE_END is `unimp` in this env, so every path ends in an explicit
# RVTEST_PASS / RVTEST_FAIL spin.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norelax
.option norvc

#define VAL_A     0xA5A50001
#define VAL_B     0x5A5A0002
#define CANVAL    0xC0DEC0DE
#define SCVAL     0x11223344

#define SH_A      0x00010408
#define SH_CAN    0x0001040C
#define SH_B      0x00010410
#define SH_CAN2   0x00010414

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # =====================================================================
    # LEG 1 -- PRIVATE TCM
    # =====================================================================
    la   s0, f6_a
    la   s1, f6_b
    la   s10, f6_can

    li   t0, VAL_A
    sw   t0, 0(s0)
    li   t1, VAL_B
    sw   t1, 0(s1)
    li   t2, CANVAL
    sw   t2, 0(s10)

    lw   t3, 0(s0)                  # read-back: the sentinels really landed
    bne  t3, t0, f6_setup1
    lw   t3, 0(s1)
    bne  t3, t1, f6_setup1
    beq  t0, t1, f6_setup3          # the two sentinels must DIFFER

    sub  s2, s1, s0                 # rs2 value = B - A, computed not literal
    beqz s2, f6_setup3

    # lr.w  rd = a2, rs1 = s0, rs2 = s2   (funct7 = 0001000 = LR_FN5|aq0|rl0)
    .insn r 0x2f, 2, 0x08, a2, s0, s2

    # CONTROL (a): the LOCAL reservation is at rs1, so this must SUCCEED and
    # must store AT rs1 -- pre-fix AND post-fix.
    li   t4, SCVAL
    sc.w a3, t4, (s0)
    lw   a4, 0(s0)
    lw   a5, 0(s1)

    # =====================================================================
    # LEG 2 -- SHARED WINDOW
    # =====================================================================
    li   s3, SH_A
    li   s4, SH_B
    li   s11, SH_CAN

    li   t0, VAL_A
    sw   t0, 0(s3)
    li   t1, VAL_B
    sw   t1, 0(s4)
    li   t2, CANVAL
    sw   t2, 0(s11)
    li   t2, CANVAL
    li   t3, SH_CAN2
    sw   t2, 0(t3)

    lw   t3, 0(s3)                  # read-back through the arbiter
    bne  t3, t0, f6_setup2
    lw   t3, 0(s4)
    bne  t3, t1, f6_setup2

    sub  s5, s4, s3
    beqz s5, f6_setup3

    # lr.w  rd = a6, rs1 = s3, rs2 = s5
    .insn r 0x2f, 2, 0x08, a6, s3, s5

    # CONTROL (b) / discriminator: the GLOBAL reservation must be at rs1 too.
    li   t4, SCVAL
    sc.w a7, t4, (s3)
    lw   s6, 0(s3)
    lw   s7, 0(s4)

    # =====================================================================
    # CANARIES -- a store that landed NEAR a target is not a clean run
    # =====================================================================
    li   t2, CANVAL
    lw   t3, 0(s10)
    bne  t3, t2, f6_setup5
    lw   t3, 0(s11)
    bne  t3, t2, f6_setup5
    li   t3, SH_CAN2
    lw   t3, 0(t3)
    bne  t3, t2, f6_setup5

    # =====================================================================
    # CONTROL (a) -- must hold in BOTH polarities
    # =====================================================================
    bnez a3, f6_setup4              # TCM sc.w must SUCCEED (rd == 0)
    li   t0, SCVAL
    bne  a4, t0, f6_setup4          # ...and must have stored AT rs1
    li   t1, VAL_B
    bne  a5, t1, f6_setup4          # ...and NOT at rs1+rs2

    # =====================================================================
    # THE DISCRIMINATING CHECKS
    # =====================================================================
    li   t0, VAL_A
    bne  a2, t0, f6_leg1            # LEG 1: lr.w must have read [rs1]
    bne  a6, t0, f6_leg2            # LEG 2: same, through the shared window
    bnez a7, f6_leg3                # LEG 2: the shared sc.w at rs1 must succeed

    RVTEST_PASS                     # a0 = 0xCAFEBABE

f6_leg1:    li a1, 0xF6F60001
            j  f6_fail
f6_leg2:    li a1, 0xF6F60002
            j  f6_fail
f6_leg3:    li a1, 0xF6F60003
            j  f6_fail
f6_setup1:  li a1, 0x5E600001
            j  f6_fail
f6_setup2:  li a1, 0x5E600002
            j  f6_fail
f6_setup3:  li a1, 0x5E600003
            j  f6_fail
f6_setup4:  li a1, 0x5E600004
            j  f6_fail
f6_setup5:  li a1, 0x5E600005
f6_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
    .balign 4
f6_a:       .word 0
f6_can:     .word 0
f6_b:       .word 0
  TEST_DATA
RVTEST_DATA_END
