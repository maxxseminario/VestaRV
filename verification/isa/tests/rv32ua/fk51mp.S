# See LICENSE for license details.

# VestaRV: reserved shamt[5] shift forms must trap, and the wrong-funct3 ORC.B/REV8 rows
# THE VERDICT POLARITY IS FIXED-BEHAVIOUR EQUALS PASS: a reserved shamt[5] = 1 encoding that TRAPS passes and one that RETIRES fails. This file began as a measurement instrument asserting the pre-fix behaviour, but a detector that goes red on correct RTL is a standing trap the day anybody wires it into a list, so the committed form is the regression form. Both polarities are proven: it fails against the parent commit's RTL and passes against the fixed RTL, with the half-(a) and control rows identical in both runs.
# HALF (a) IS NOT A DEFECT AND IS ASSERTED UNCHANGED. `is_zbb_i_instr` groups ORC.B and REV8 under funct3 = "001" where the architecture puts both at "101", but those rows are INERT: they are shadowed by `is_zbs_i_instr`, which already admits funct3 = "001" with BSETI_FN7 or BINVI_FN7 for any shamt under the same ENABLE_BITMANIP gate, and real orc.b and rev8 work through the fall-through. Read off constants.vhd, ORC_B_IMM12 is funct7 0010100 with shamt 7 and REV8_IMM12 is funct7 0110100 with shamt 24, so the two rows are a strict subset of one already present and the wrong-funct3 forms are ordinary Zbs instructions: 0x28729313 is `bseti x6, x5, 7` and 0x69829313 is `binvi x6, x5, 24`.
# HALF (b) is the OP-IMM shift space deciding legality on funct7(6:5) alone, which admits an RV32-reserved shamt[5] = 1 form. The three suspects all have a shamt field of 0x23, that is shamt[5] set with shamt[4:0] = 3: 0x02329313 `slli x6, x5, 35`, 0x0232D313 `srli x6, x5, 35` and 0x4232D313 `srai x6, x5, 35`. All three reach their arm with funct7(6:5) in {"00","01"} and are admitted, and the prediction is that shamt[5] is ignored and each computes the shamt = 3 form.
# THIS NEEDS FOUR HARTS, because on a default build an illegal instruction lands in the TERMINAL TRAP_STATE and a hart that traps never writes a0 again, so it cannot be the gate. The victims are tile harts 1, 2 and 3 and the observer is hart 0. Each victim writes a PROGRESS word before its suspect encoding and a higher value after it, so a stall is unambiguous, and it also stores the computed RESULT of every encoding, so the verdict is not merely that it ran but that it ran and produced exactly this. EVERY INSTRUCTION IN A VICTIM'S PREAMBLE IS PLAIN rv32i, because the tiles are built rv32iac with no M, no DIV and no BITMANIP, so a stall can only be the suspect encoding and never the tile's narrowed ISA. That is also why half (a) runs on HART 0, which keeps CORE_ENABLE_BITMANIP, and is the one remaining bitmanip dependence in the file.
# HART 3 IS THE CONTROL and is why the other two verdicts mean anything: it executes funct3 = 001 with funct7 = SHA256_FN7, the one arm in that space that maindec still rejects outright when ENABLE_ZKN is off, and hart 0 REQUIRES it to be stuck. Without it, "the suspects did not trap" would be unfalsifiable, because a build in which nothing traps at all would look identical. The victims wedge in TCM, generate no arbiter traffic, and the instruction after every suspect encoding is an `addi` and never a store, so the TRAP_STATE store-leak cannot fire.
# HART 0'S HALF IS THE ARCHITECTURAL REFERENCE, computed with real instructions gas encodes rather than hand-computed constants: bseti, binvi, slli, srli and srai come from mnemonics while the suspects are raw `.word`s, so the comparison is between what the assembler says the architecture means and what the decoder actually did. RVTEST_CODE_END is `unimp` in this environment, so every path ends in an explicit PASS or FAIL spin and never falls through.

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

# Shared observation words.  All < 0x10500 (the loader-row block) and inside the
# bootrom zero range < 0x10800, per the CLAUDE.md shared-window ledger rule.
# The band 0x104A0-0x104BC is free at N=4: shfault's DONE base is 0x10450,
# shafe's TURN tops out at 0x10498, and the K5 detector family starts at
# 0x104D0.  Tests run in isolation, so a same-address neighbour at another
# NHARTS is benign by the ledger's own rule.
#define SH_PROG1    0x104A0
#define SH_VAL1A    0x104A4
#define SH_VAL1B    0x104A8
#define SH_PROG2    0x104AC
#define SH_VAL2A    0x104B0
#define SH_VAL2B    0x104B4
#define SH_VAL2C    0x104B8
#define SH_PROG3    0x104BC

#define SEED        0x87654321

#define TILE_WORDS  1024        /* covers 0x8000-0x8FFF */
#define ARM_BUDGET  12000
#define WATCH_ITERS 4000

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   sp, 0xBFF0
    .option push
    .option arch, +zicsr
    csrr t0, mhartid
    .option pop
    bnez t0, fk_tile_dispatch

    # ==================================================================
    # hart 0: base sanity, then arm the three progress words
    # ==================================================================
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    li   a1, 0xF510000E
    bne  t2, t3, fk_fail

    li   s1, SH_PROG1
    li   s2, SH_PROG2
    li   s3, SH_PROG3
    sw   x0, 0(s1)
    sw   x0, 0(s2)
    sw   x0, 0(s3)
    li   a1, 0xF510000D
    lw   t1, 0(s1)
    bnez t1, fk_fail
    lw   t1, 0(s2)
    bnez t1, fk_fail
    lw   t1, 0(s3)
    bnez t1, fk_fail

    MP_STAGE_IMAGE(TILE_WORDS)
    MP_LAUNCH_HART(1, fk_tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(2, fk_tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(3, fk_tile_entry, TILE_WORDS)

    # ==================================================================
    # wait (bounded) for all three victims to reach their first encoding
    # ==================================================================
    li   t6, ARM_BUDGET
    li   t5, 1
fk_arm_wait:
    lw   t2, 0(s1)
    blt  t2, t5, fk_arm_next
    lw   t3, 0(s2)
    blt  t3, t5, fk_arm_next
    lw   t4, 0(s3)
    bge  t4, t5, fk_armed
fk_arm_next:
    addi t6, t6, -1
    bnez t6, fk_arm_wait
    li   a1, 0xF5100001                 # a victim never reached its encoding
    j    fk_fail

fk_armed:
    # ==================================================================
    # THE OBSERVATION WINDOW.  Every reserved encoding must STAY trapped for
    # the whole window; if any victim ever advances past its encoding, the
    # reserved form retired and that is the defect.
    #   PROGRESS1 must never reach 2  -- victim 1's `srai x,x,35`
    #                                    (SRL arm, funct7(6:5) = "01")
    #   PROGRESS2 must never reach 2  -- victim 2's `slli x,x,35`
    #                                    (SLL arm, funct7(6:5) = "00")
    #   PROGRESS3 must never reach 2  -- THE CONTROL
    # The two reserved forms are deliberately drawn from the two DIFFERENT
    # decode arms the fix touches, so one passing run exercises both.
    # ==================================================================
    li   t6, WATCH_ITERS
fk_watch:
    li   t5, 2
    lw   t2, 0(s1)
    bge  t2, t5, fk_h1_ran
    lw   t3, 0(s2)
    bge  t3, t5, fk_h2_ran
    lw   t4, 0(s3)
    bge  t4, t5, fk_h3_ran
    addi t6, t6, -1
    bnez t6, fk_watch

    # ==================================================================
    # half (a): the wrong-funct3 ORC.B/REV8 forms are ordinary Zbs ops
    # ==================================================================
    # These two raw words run HERE, on hart 0.  They are Zbs encodings, and the
    # tiles are rv32iac (TILE_ENABLE_BITMANIP = false), so on a victim they trap
    # and say nothing about half (b).  Hart 0 keeps CORE_ENABLE_BITMANIP, so it
    # retires them and the observation words carry real results.
    li   x5, SEED
    .word 0x28729313                    # funct3=001 imm12=ORC_B_IMM12 -> x6
    li   s5, SH_VAL1A
    sw   x6, 0(s5)
    li   x5, SEED
    .word 0x69829313                    # funct3=001 imm12=REV8_IMM12  -> x6
    li   s5, SH_VAL1B
    sw   x6, 0(s5)

    # The rv32ua group builds -march=rv32imac, which has no Zbs, so the
    # architectural reference instructions need their extension enabled
    # locally.  `.option arch, +zbs` is march-INDEPENDENT (the X1/X3 directed
    # tests' pattern) and keeps the reference on the ASSEMBLER's authority
    # rather than on a constant typed into a comment.
    .option push
    .option arch, +zbs
    li   s4, SEED
    bseti t0, s4, 7                     # what the architecture says 0x28729313 is
    li   s5, SH_VAL1A
    lw   t1, 0(s5)
    li   a1, 0xF5100011                 # orc.b-shaped != bseti rd,rs1,7
    bne  t0, t1, fk_fail

    binvi t0, s4, 24                    # what the architecture says 0x69829313 is
    li   s5, SH_VAL1B
    lw   t1, 0(s5)
    li   a1, 0xF5100012                 # rev8-shaped != binvi rd,rs1,24
    bne  t0, t1, fk_fail
    .option pop

    # A non-vacuity guard on the half-(a) comparisons above: `bseti x,x,7` and
    # `binvi x,x,24` of this seed MUST differ from each other and from the seed,
    # so a build in which every observation word read back the same value could
    # not have satisfied both.
    li   a1, 0xF5100013
    beq  t0, s4, fk_fail

    RVTEST_PASS

    # ---- the three ways a reserved encoding can betray itself ---------------
    # Each is a DISTINCT a1, so a failing run is diagnosable from a0/a1 alone
    # without a waveform.
fk_h1_ran:
    li   a1, 0xF5100021                 # victim 1's `srai x,x,35` RETIRED
    j    fk_fail                        #   (SRL arm, funct7(6:5) = "01")
fk_h2_ran:
    li   a1, 0xF5100022                 # victim 2's `slli x,x,35` RETIRED
    j    fk_fail                        #   (SLL arm, funct7(6:5) = "00")
fk_h3_ran:
    li   a1, 0xF5100003                 # THE CONTROL retired -- this build
                                        # traps nothing in that space, so the
                                        # two verdicts above are worthless
fk_fail:
    RVTEST_FAIL

    # ---- tile harts enter here (loader ABI: only sp is defined) -------------
fk_tile_dispatch:
fk_tile_entry:
    li   sp, 0xBFF0
    .option push
    .option arch, +zicsr
    csrr t3, mhartid
    .option pop
    li   t4, 1
    beq  t3, t4, fk_h1
    li   t4, 2
    beq  t3, t4, fk_h2
    li   t4, 3
    beq  t3, t4, fk_h3
fk_park:
    j    fk_park

    # ---- victim 1: half (b) on the SRL arm --------------------------------
    # Every instruction here is rv32i.  The preamble carries no bitmanip, so
    # PROGRESS1 = 1 is reached on a tile of any ISA width and a stall at 1 can
    # only mean the reserved form trapped, which is the verdict this file wants.
fk_h1:
    li   s1, SH_PROG1
    li   x5, SEED
    li   t2, 1
    sw   t2, 0(s1)                      # armed: about to execute the reserved form
    .word 0x4232D313                    # srai x6, x5, 35   (RV32-reserved)
    addi t2, x0, 2                      # never a store: F8 cannot fire here
    sw   t2, 0(s1)                      # PROGRESS1 = 2 ONLY if the form retired
fk_h1_park:
    j    fk_h1_park

    # ---- victim 2: half (b), the three reserved shamt[5]=1 forms ----------
fk_h2:
    li   s2, SH_PROG2
    li   x5, SEED
    li   t2, 1
    sw   t2, 0(s2)                      # armed
    .word 0x02329313                    # slli x6, x5, 35   (RV32-reserved)
    addi t2, x0, 2                      # never a store
    li   s5, SH_VAL2A
    sw   x6, 0(s5)
    sw   t2, 0(s2)
    li   x5, SEED
    .word 0x0232D313                    # srli x6, x5, 35   (RV32-reserved)
    addi t2, x0, 3                      # never a store
    li   s5, SH_VAL2B
    sw   x6, 0(s5)
    sw   t2, 0(s2)
    li   x5, SEED
    .word 0x4232D313                    # srai x6, x5, 35   (RV32-reserved)
    addi t2, x0, 4                      # never a store
    li   s5, SH_VAL2C
    sw   x6, 0(s5)
    sw   t2, 0(s2)
fk_h2_park:
    j    fk_h2_park

    # ---- victim 3: THE CONTROL.  This one MUST trap. ----------------------
fk_h3:
    li   s3, SH_PROG3
    li   x5, SEED
    li   t2, 1
    sw   t2, 0(s3)                      # armed
    .word 0x10029313                    # funct3=001 funct7=SHA256_FN7, ZKN off
    addi t2, x0, 2                      # never a store: F8 cannot fire here
    sw   t2, 0(s3)                      # reached ONLY if the control did NOT trap
fk_h3_park:
    j    fk_h3_park

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
