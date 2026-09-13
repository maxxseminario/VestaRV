# See LICENSE for license details.

# VestaRV: detector for `lr.w` reading rs1 + rs2 while reserving rs1
# THE DEFECT: the AMO valid_funct arm whitelists on funct3 and funct5 only, with no rs2 term anywhere, so an `lr.w` with a NON-ZERO rs2 field is a legal decode on this core even though the ISA reserves it. ALU_src falls through to 0 for the AMO opcode and the ALU does ADD, so ALU_Result = reg[rs1] + reg[rs2]; data_addr takes rs1_value only for the `EXECUTE and amo_op` arm, which lr_op is not in, so BOTH the EXECUTE cycle and LR_READ address at rs1 + reg[rs2], while reservation_addr takes rs1_value in LR_READ. Read and reservation therefore land on DIFFERENT addresses. The sibling members of the family were all fixed for exactly this reason and say so in the RTL; `lr.w` is the one that was left out.
# THE ASSEMBLER WILL NOT EMIT THIS, since `lr.w rd,(rs1)` forces rs2 = x0, so the test uses `.insn r 0x2f, 2, 0x08, rd, rs1, rs2`, which is AMO opcode, funct3 010 for word width, funct7 0001000 being funct5 = LR with aq and rl clear. THE ENCODING IS VERIFIED FROM objdump ON THE BUILT IMAGE, never from the source.
# THE OBSERVABLE is which address was actually read. Two words hold two distinct sentinels, VAL_A = 0xA5A50001 at rs1 and VAL_B = 0x5A5A0002 at rs1 + rs2, and reg[rs2] is computed at run time with a `sub` so nothing is hardcoded and the leg cannot silently stop discriminating if the linker moves anything. rd equal to VAL_B means the read went to rs1 + reg[rs2]; rd equal to VAL_A means it went to rs1. Leg 1 runs in the private TCM and leg 2 in the shared window, and both are required.
# TWO CONTROLS PIN THE RESERVATION SIDE. (a) The LOCAL reservation in leg 1: reservation_addr is already rs1_value, so an `sc.w` at rs1 succeeds both before and after any fix, and a fix that broke this changed the wrong thing. (b) The GLOBAL reservation in leg 2: hart_tile drives the lr_sc bus during the LR's EXECUTE cycle and the resv_unit arms at whatever data_addr carried, so a later `sc.w` at rs1 fails through sc_fail_ext even though the local check passes, and leg 2's `sc.w` must succeed once the read is steered correctly.
# LEG 2 IS THE CRITERION A HALF FIX CANNOT SATISFY: steering LR_READ alone leaves the global reservation and the EXECUTE-cycle transaction at rs1 + rs2, so leg 2's store-conditional still fails; steering the EXECUTE arm alone leaves LR_READ re-presenting a different word address to a window whose ack is word-address-qualified, so leg 2's rd comes back from the wrong place again. Only a consistent fix makes both shared checks green while leaving both TCM controls untouched.
# ANTI-VACUOUS GATES, enforced in both polarities: both sentinels are written and READ BACK before the probe, so a leg can never pass because the memory never held what the test thinks; the two sentinels are different and the delta is nonzero, checked rather than assumed; a CANARY word sits between the two targets in each leg and must be untouched, so a store landing near a target cannot be mistaken for a clean run; and rs2's value is computed, never a literal.
# Verdicts: a0 = 0xCAFEBABE passes. a0 = 0xDEADBEEF with a1 = 0xF6F60001 leg 1 in TCM read rs1 + rs2; 0xF6F60002 leg 2 in shared read rs1 + rs2; 0xF6F60003 leg 2's store-conditional at rs1 failed, so the global reservation was armed at rs1 + rs2; 0x5E600001 TCM sentinel setup or read-back broke; 0x5E600002 shared sentinel setup or read-back broke; 0x5E600003 the two sentinels are equal or a delta is 0, so the probe could not discriminate; 0x5E600004 control (a) failed, so the LOCAL reservation moved and this is not a result about the read; 0x5E600005 a canary moved, so a store landed near a target.
# Registers live at the verdict: a2 leg 1's lr rd, a3 its sc rd, a4 the TCM A word after the store and a5 the TCM B word; a6 leg 2's lr rd, a7 its sc rd, s6 the shared A word after the store and s7 the shared B word; s2 and s5 the TCM and shared deltas.
# Shared words claimed: 0x10408 to 0x10414, four words, all written before read, being SH_A at 0x10408, a canary at 0x1040C, SH_B at 0x10410 and a second canary at 0x10414. They are free at N=4, filling the gap between neighbouring bands, and are below 0x10500 and inside the bootrom zero range; at N=18 they overlap another test's array, which is benign under the one-image-per-sim rule, and this test is single-hart and not in the standing runner array.
# Single hart: tiles 1-3 are never launched. RVTEST_CODE_END is `unimp` here, so every path ends in an explicit PASS or FAIL spin.

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
