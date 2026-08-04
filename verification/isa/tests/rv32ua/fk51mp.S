# See LICENSE for license details.

#*****************************************************************************
# fk51mp.S   (K5 queue item 5 -- the DEFAULT-BUILD MEASUREMENT detector for F-K5-1)
#-----------------------------------------------------------------------------
# THE VERDICT POLARITY IS FIXED-BEHAVIOUR = PASS, and R-K5-8 (3) is why.
# This file began life as a MEASUREMENT instrument: it asserted what the RTL did
# BEFORE the fix, so it passed on the defective tree and failed on the corrected
# one.  That form did its job -- it is what measured F-K5-1 and what showed the
# two halves are not mechanically coupled -- but it must not be the form that
# gets committed.  A detector that goes RED on correct RTL is a standing trap
# the day anybody wires it into a list: the next reader sees a failing test on a
# healthy tree and learns to ignore it.  So the committed form is the REGRESSION
# form, and its verdicts are inverted:
#
#     reserved shamt[5]=1 encoding TRAPS   -> PASS   (correct, post-fix)
#     reserved shamt[5]=1 encoding RETIRES -> FAIL   (the defect, pre-fix)
#
# Both polarities are proven, and neither is a claim: the file FAILS against the
# parent commit's RTL and PASSES against the fixed RTL, with the half-(a) and
# control rows identical in both runs.  This is the packalias construction's own
# design point (R-K5-4), reused deliberately.
#
# HALF (a) IS NOT FIXED and this file asserts it UNCHANGED.  R-K5-7 (2) ruled it
# INERT-AS-MEASURED: the funct3=001 ORC.B/REV8 rows in is_zbb_i_instr are dead,
# shadowed by is_zbs_i_instr, and real orc.b/rev8 work through the fall-through.
# The two rows below therefore keep RETIRING and keep computing their Zbs
# results, in both polarities -- which is what makes them the control that says
# a half-(b) verdict moved for the half-(b) reason.
#
# THE FINDING, IN ITS OWN TERMS (maindec.vhd + constants.vhd)
#   half (a)  `is_zbb_i_instr` groups ORC.B and REV8 under funct3 = "001".
#             The architecture puts both at funct3 = "101".
#   half (b)  the OP-IMM shift space decides legality on funct7(6:5) alone, so
#             an RV32-RESERVED shamt[5] = 1 form is admitted.
#
# WHAT THE ENCODINGS ACTUALLY ARE -- read off constants.vhd, not assumed:
#   ORC_B_IMM12 = 001010000111 = funct7 0010100 (== BSETI_FN7) + shamt 00111 (7)
#   REV8_IMM12  = 011010011000 = funct7 0110100 (== BINVI_FN7) + shamt 11000 (24)
# and `is_zbs_i_instr` already admits funct3="001" with BSETI_FN7 or BINVI_FN7
# for ANY shamt, under the SAME ENABLE_BITMANIP gate.  So half (a)'s two rows
# are a STRICT SUBSET of a row that is already there, and the prediction this
# detector tests is that the wrong-funct3 forms are ordinary Zbs instructions:
#   0x28729313  "orc.b-shaped"  ==  bseti x6, x5, 7
#   0x69829313  "rev8-shaped"   ==  binvi x6, x5, 24
#
# THE THREE RESERVED SHIFTS (half b), shamt field = 0x23 = 35, i.e. shamt[5]=1
# with shamt[4:0] = 3:
#   0x02329313  funct3=001 funct7=0000001   "slli x6, x5, 35"
#   0x0232D313  funct3=101 funct7=0000001   "srli x6, x5, 35"
#   0x4232D313  funct3=101 funct7=0100001   "srai x6, x5, 35"
# All three reach their arm with funct7(6:5) in {"00","01"} and are admitted.
# The prediction is that shamt[5] is IGNORED and each computes the shamt=3 form.
#
# WHY THIS NEEDS FOUR HARTS -- the rocsrwmp construction, ratified by R-K5-4
#   On a default build an illegal instruction lands in the TERMINAL TRAP_STATE
#   (self-loop, pc_en = '0'), so a hart that traps NEVER writes a0 again and
#   cannot be the gate.  The VICTIMS are tile harts 1, 2 and 3; the OBSERVER is
#   hart 0, which keeps the ordinary PASS/FAIL contract.
#
#   Each victim writes a PROGRESS word BEFORE its suspect encoding and a higher
#   value AFTER it, so the two states are unambiguous:
#       PROGRESS stuck below the end value  -> that encoding TRAPPED
#       PROGRESS reached the end value      -> every encoding RETIRED
#   and each victim also STORES THE COMPUTED RESULT of every encoding, so the
#   verdict is not merely "it ran" but "it ran and produced exactly this".
#
#   HART 3 IS THE CONTROL, and it is the reason the other two verdicts mean
#   anything (method rule 1: a detector never seen to fail proves nothing).  It
#   executes funct3=001 with funct7 = SHA256_FN7 = 0001000, which maindec
#   rejects OUTRIGHT when ENABLE_ZKN is off -- the one arm in that space that
#   still says `valid_funct <= '0'`.  Hart 0 REQUIRES hart 3 to be stuck at 1.
#   Without it, "the suspects did not trap" would be unfalsifiable: a build in
#   which nothing traps at all would look identical.
#
#   The victims wedge in TCM, generate no arbiter traffic, and the instruction
#   after every suspect encoding is an `addi`, never a store, so F8 (TRAP_STATE
#   commits the word at pc+4 if it decodes as a store) cannot fire.
#
# HART 0's OWN HALF is the ARCHITECTURAL REFERENCE, computed with real
# instructions that `gas` encodes -- never with hand-computed constants in a
# comment.  bseti/binvi/slli/srli/srai are assembled from mnemonics; the
# suspects are raw `.word`s.  The comparison is therefore between what the
# assembler says the architecture means and what the decoder actually did.
#
# BITMANIP DEPENDENCE, stated: both halves live inside `ENABLE_BITMANIP` arms,
# so this detector is meaningful only on a bitmanip-ON build.  The default
# Castalia config is bitmanip-ON, which is the build R-K5-5 (2) is about.  On a
# bitmanip-OFF build every suspect encoding traps and hart 1/2 would stick --
# hart 0 then FAILs with a distinguishing a1 code rather than passing vacuously.
#
# NOTE: `RVTEST_CODE_END` is `unimp` in this env (it TRAPS since F10) -- every
# path below ends in an explicit PASS or FAIL spin and never falls through.
#*****************************************************************************

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
    # HALF (a) MUST RUN THROUGH.  Victim 1 executes the two funct3=001
    # ORC.B/REV8 forms and reaches PROGRESS1 = 3; they are ruled inert and
    # must keep retiring in BOTH polarities.  A stall here is not a half-(b)
    # verdict and must not be reported as one.
    # ==================================================================
    li   t6, ARM_BUDGET
    li   t5, 3
fk_run_wait:
    lw   t2, 0(s1)
    bge  t2, t5, fk_ran
    addi t6, t6, -1
    bnez t6, fk_run_wait
    li   a1, 0xF5100004                 # half (a) did NOT retire -- see above
    j    fk_fail

fk_ran:
    # ==================================================================
    # THE OBSERVATION WINDOW.  Every reserved encoding must STAY trapped for
    # the whole window; if any victim ever advances past its encoding, the
    # reserved form retired and that is the defect.
    #   PROGRESS1 must never reach 4  -- victim 1's trailing `srai x,x,35`
    #                                    (SRL arm, funct7(6:5) = "01")
    #   PROGRESS2 must never reach 2  -- victim 2's `slli x,x,35`
    #                                    (SLL arm, funct7(6:5) = "00")
    #   PROGRESS3 must never reach 2  -- THE CONTROL
    # The two reserved forms are deliberately drawn from the two DIFFERENT
    # decode arms the fix touches, so one passing run exercises both.
    # ==================================================================
    li   t6, WATCH_ITERS
fk_watch:
    lw   t2, 0(s1)
    li   t5, 4
    bge  t2, t5, fk_h1_ran
    lw   t3, 0(s2)
    li   t5, 2
    bge  t3, t5, fk_h2_ran
    lw   t4, 0(s3)
    bge  t4, t5, fk_h3_ran
    addi t6, t6, -1
    bnez t6, fk_watch

    # ==================================================================
    # half (a): the wrong-funct3 ORC.B/REV8 forms are ordinary Zbs ops
    # ==================================================================
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

    # ---- victim 1: half (a), the two wrong-funct3 forms -------------------
fk_h1:
    li   s1, SH_PROG1
    li   x5, SEED
    li   t2, 1
    sw   t2, 0(s1)                      # armed: about to execute encoding A1
    .word 0x28729313                    # funct3=001 imm12=ORC_B_IMM12 -> x6
    addi t2, x0, 2                      # never a store: F8 cannot fire here
    li   s5, SH_VAL1A
    sw   x6, 0(s5)
    sw   t2, 0(s1)                      # reached ONLY if A1 did not trap
    li   x5, SEED
    .word 0x69829313                    # funct3=001 imm12=REV8_IMM12  -> x6
    addi t2, x0, 3                      # never a store
    li   s5, SH_VAL1B
    sw   x6, 0(s5)
    sw   t2, 0(s1)                      # PROGRESS1 = 3: half (a) both retired
    # ...and now the half-(b) form from the OTHER decode arm the fix touches.
    # Post-fix this traps and PROGRESS1 stays at 3, which is what the observer
    # requires; pre-fix it retired and PROGRESS1 reached 4.
    li   x5, SEED
    .word 0x4232D313                    # srai x6, x5, 35   (RV32-reserved)
    addi t2, x0, 4                      # never a store: F8 cannot fire here
    sw   t2, 0(s1)
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
