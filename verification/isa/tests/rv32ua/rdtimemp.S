# See LICENSE for license details.

# VestaRV: the `time` and `timeh` CSRs must trap, cycle and instret must not
# THE CONTRACT, in the shipped default build with no configuration change: a CSR READ of 0xC01 and of 0xC81 MUST raise illegal-instruction, while reads of 0xC00, 0xC02 and 0xC03 MUST still retire. Two more must-retire addresses are asserted, 0xC80 and 0xC82, for a reason in the RTL rather than in the ruling: csr_addr_valid admits CSR_CYCLEH, CSR_TIMEH and CSR_INSTRETH ON ONE LINE, so the likeliest over-wide edit, deleting the line carrying 0xC81, takes the other two with it. 0xC81 is the only address on that line that may change.
# WHY: there is no mtime CSR in RISC-V, the machine timer being the CLINT's MEMORY-MAPPED mtime, and `time` and `timeh` are the user-view shadows of it. An implementation with no mapping from the CSR to that memory must NOT invent one; the spec's expectation is that rdtime traps and M-mode emulates it. ANSWERING A rdtime WITH A CONSTANT IS WORSE THAN TRAPPING, because software cannot tell a stopped clock from a real one. Today csr_addr_valid admits both addresses with no ENABLE_ qualifier, so valid_funct is set and no trap occurs, while csr_unit has no read arm for either, so both ride the `when others` zero: a stopped clock software has no way to detect.
# THE WRITE SIDE NEEDS NOTHING and is deliberately not re-litigated: csr_ro_denied is ungated and address-agnostic within the quadrant, and both addresses have imm12(11:10) = "11", so a write form already traps in every build. rocsrw and rocsrwmp own that claim.
# THIS NEEDS FOUR HARTS, because correct behaviour here is a TRAP and on the shipped default an illegal instruction lands in the TERMINAL TRAP_STATE, so a hart that reads `time` correctly never writes a0 again. The victims are tile harts 1, 2 and 3 and the observer is hart 0. Each victim writes a PROGRESS word before its encoding and again after it, so PROG = k means it reached leg k and is wedged in it while PROG = k+1 means leg k retired. HART 0 EXECUTES NO 0xCxx ENCODING AT ALL in either polarity, deliberately, because that is what keeps the verdict path alive when an over-wide change makes a counter read illegal; everything it does execute is unconditionally legal on every matrix row, which an untagged catalog row has to be.
# The three victims. Hart 1 is the `time` subject with one encoding, the canonical `csrrs rd, 0xC01, x0` that gas emits for rdtime, a true slot meaning something in both polarities. Hart 2 is the `timeh` subject on a separate hart and therefore a separate true slot, so a change that catches one and forgets the other cannot hide. Hart 3 is the ANTI-OVERKILL WALKER and the only victim with a live tail after the change: it reads 0xC00, 0xC02, 0xC03, 0xC80 and 0xC82 in turn, five legs that must retire in every build, then executes two ALTERNATE READ FORMS of the two subjects, csrrsi and csrrci with the uimm FIELD zero, which are reads and not writes, placed where they are still live once the change lands.
# THE SLOT ARGUMENT, to be read before moving anything: a must-trap encoding CONSUMES a hart, there are exactly three wedge slots and hart 0 cannot take one. After the change harts 1 and 2 are spent on their first encoding, so the only position still executing is hart 3's tail, because everything in front of it is required to retire; the assertions that need to be live after the change therefore go there and the ones that need a hart to themselves take the true slots. RESIDUAL: hart 3's two tail legs are CHAINED, so a change that catches the first immediate form but misses the second is not caught; the first is placed first because a narrow change is likelier to be narrow in the FORM dimension, which csr_addr_valid does not express, than in the ADDRESS dimension, which harts 1 and 2 cover independently. A fourth victim would close it.
# THE ANTI-OVERKILL CONTROL IS ON HART 3, NOT HART 0, AND THAT IS THE POINT: putting a counter read on hart 0 would make an over-wide change present as a 100 ms watchdog hang, loud but undiscriminating, and it would mask the clean signal from every other victim. On hart 3 the same change presents as a failure whose a1 names the exact CSR that wrongly trapped.
# KNOB-INDEPENDENT BY CONSTRUCTION: nothing here reads a trap, debug, FP, PMP or jvt CSR, the seven addresses it does touch are admitted with no ENABLE_ term, and all are read from M-mode so the U-mode counter-enable path is out of reach. No -DCORE_ENABLE_* dispatch appears anywhere, which is what lets this file run against the canonical image set and against every polarity of every knob. NOT A COSIM TEST, and it must stay out of the cosim lists: it is trap-poison class, the harts under test end in TRAP_STATE by design, and the reference's --isa always carries _zicntr, so Spike retires rdtime and would report a divergence that is the oracle's configuration rather than the DUT's behaviour.
# THE PASS-POLARITY CONTROL -DRDTIMEMP_PASS_CONTROL replaces ONLY the four must-trap encodings with `.word 0x0000007F`, an opcode absent from valid_opcode in every build, leaving every PROG step, every store, every negative leg and the whole observer untouched, so on the unchanged tree the three victims reach exactly the predicted post-change terminal state and hart 0 walks the passing path end to end with no RTL change. A detector never seen to pass is as untrustworthy as one never seen to fail. It makes no claim about the finding.
# Verdicts: a0 = 0xCAFEBABE means both reads trap in the default build in both the canonical and the immediate form while the five counter reads still retire. a0 = 0xDEADBEEF with a1 = 0x0C010001 hart 1 executed past the canonical `time` read, the finding; 0x0C810001 hart 2 executed past the canonical `timeh` read, the finding; 0x0C010002 and 0x0C810002 hart 3 executed past an immediate read form, so the change misses that form; 0x0BAD0C00, 0x0BAD0C02, 0x0BAD0C03, 0x0BAD0C80 or 0x0BAD0C82 hart 3 wedged on a counter read, which is OVER-WIDE, and the last two mean the whole shared line was deleted rather than just 0xC81; 0x5E7A0001 a victim never armed; 0x5E7A0002 a shared word did not read back; 0x5E7A0003 base-ISA sanity failed. NO a0 AT ALL is itself a result: hart 0 can only wedge on `csrr mhartid` or on its shared stores, so it means the decode of the READ-ONLY QUADRANT AT LARGE was made illegal.
# Shared words, all below 0x10500 and inside the bootrom zero range, and cleared and read back by hart 0 before any launch: 0x10034 TPROG, 0x10038 HPROG, 0x1003C NPROG. The band is free at N=4 and at N=18 and does not even overlap at N=18; THREE WORDS IS THE WHOLE GAP, so a future instrument needing more must go elsewhere.

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_TPROG    0x10034
#define SH_HPROG    0x10038
#define SH_NPROG    0x1003C

#define TILE_WORDS  1024        /* covers 0x8000-0x8FFF */
#define ARM_BUDGET  12000
#define WATCH_ITERS 4000

/* Every CSR encoding under test is spelled as a .word so the test cannot depend
   on gas's CSR name table or on it choosing a form for us.  All seven were
   cross-checked against riscv-none-elf-as before the first build.           */
#define CSRR_S0_C01   0xC0102473    /* csrrs  s0, 0xC01, x0   time    MUST TRAP */
#define CSRR_S1_C81   0xC81024F3    /* csrrs  s1, 0xC81, x0   timeh   MUST TRAP */
#define CSRR_S2_C00   0xC0002973    /* csrrs  s2, 0xC00, x0   cycle    must retire */
#define CSRR_S3_C02   0xC02029F3    /* csrrs  s3, 0xC02, x0   instret  must retire */
#define CSRR_S4_C03   0xC0302A73    /* csrrs  s4, 0xC03, x0   hpmc3    must retire */
#define CSRR_S7_C80   0xC8002BF3    /* csrrs  s7, 0xC80, x0   cycleh   must retire */
#define CSRR_S8_C82   0xC8202C73    /* csrrs  s8, 0xC82, x0   instreth must retire */
#define CSRSI_S5_C01  0xC0106AF3    /* csrrsi s5, 0xC01, 0    uimm FIELD 0: a READ */
#define CSRCI_S6_C81  0xC8107B73    /* csrrci s6, 0xC81, 0    uimm FIELD 0: a READ */
#define ALWAYS_ILLEGAL 0x0000007F   /* opcode absent from valid_opcode, all builds */

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr -- enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry            # belt-and-braces: only hart 0 orchestrates

    li   s2, SH_TPROG
    li   s3, SH_HPROG
    li   s4, SH_NPROG

    # ==================================================================
    # clear every claimed word and prove it read back
    # ==================================================================
    li   a1, 0x5E7A0002
    sw   x0, 0(s2)
    lw   t1, 0(s2)
    bnez t1, rdt_fail
    sw   x0, 0(s3)
    lw   t1, 0(s3)
    bnez t1, rdt_fail
    sw   x0, 0(s4)
    lw   t1, 0(s4)
    bnez t1, rdt_fail

    # base-ISA sanity: a broken image is distinguishable from a broken decode
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    li   a1, 0x5E7A0003
    bne  t2, t3, rdt_fail

    # ==================================================================
    # launch the three victims
    # ==================================================================
    MP_STAGE_IMAGE(TILE_WORDS)
    MP_LAUNCH_HART(1, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(2, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(3, tile_entry, TILE_WORDS)

    # ==================================================================
    # bounded wait for every victim to reach its EXPECTED terminal state:
    #   TPROG >= 1   hart 1 reached the `time` read
    #   HPROG >= 1   hart 2 reached the `timeh` read
    #   NPROG >= 6   hart 3's five must-retire counter reads all retired
    # An over-wide change stalls NPROG at 1..5 and this budget expires -- a
    # clean, CSR-naming failure rather than a watchdog hang.
    # ==================================================================
    li   s7, 1
    li   s8, 1
    li   s9, 6
    li   t6, ARM_BUDGET
rdt_wait:
    lw   t2, 0(s2)
    blt  t2, s7, rdt_wait_next
    lw   t3, 0(s3)
    blt  t3, s8, rdt_wait_next
    lw   t4, 0(s4)
    bge  t4, s9, rdt_armed
rdt_wait_next:
    addi t6, t6, -1
    bnez t6, rdt_wait

    # ---- the budget expired: name the reason ----------------------------
    lw   t2, 0(s2)
    lw   t3, 0(s3)
    lw   a2, 0(s4)                  # a2 = NPROG, the discriminating word

    li   t5, 1
    li   a1, 0x0BAD0C00
    beq  a2, t5, rdt_fail           # wedged ON the cycle read
    li   t5, 2
    li   a1, 0x0BAD0C02
    beq  a2, t5, rdt_fail           # wedged ON the instret read
    li   t5, 3
    li   a1, 0x0BAD0C03
    beq  a2, t5, rdt_fail           # wedged ON the hpmcounter3 read
    li   t5, 4
    li   a1, 0x0BAD0C80
    beq  a2, t5, rdt_fail           # wedged ON the cycleh read
    li   t5, 5
    li   a1, 0x0BAD0C82
    beq  a2, t5, rdt_fail           # wedged ON the instreth read

    slli t2, t2, 8
    slli t3, t3, 4
    add  a2, a2, t2
    add  a2, a2, t3                 # a2 = TPROG*256 + HPROG*16 + NPROG
    li   a1, 0x5E7A0001             # something never armed at all
    j    rdt_fail

rdt_armed:
    # ==================================================================
    # observe: no victim may advance past its correct terminal state
    # ==================================================================
    li   t6, WATCH_ITERS
rdt_watch:
    lw   t2, 0(s2)
    bne  t2, s7, rdt_time_ran       # TPROG must STAY 1
    lw   t3, 0(s3)
    bne  t3, s8, rdt_timeh_ran      # HPROG must STAY 1
    lw   t4, 0(s4)
    bne  t4, s9, rdt_neg_over       # NPROG must STAY 6
    addi t6, t6, -1
    bnez t6, rdt_watch

    RVTEST_PASS                     # a0 = 0xCAFEBABE

rdt_time_ran:
    mv   a2, t2
    li   a1, 0x0C010001             # `csrr rd, time` RETIRED  <-- THE FINDING
    j    rdt_fail
rdt_timeh_ran:
    mv   a2, t3
    li   a1, 0x0C810001             # `csrr rd, timeh` RETIRED <-- THE FINDING
    j    rdt_fail
rdt_neg_over:
    mv   a2, t4
    li   t5, 7
    li   a1, 0x0C010002             # the immediate read form of time retired
    beq  t4, t5, rdt_fail
    li   a1, 0x0C810002             # ...and the one of timeh retired too
rdt_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    # ---- tile harts enter here (loader ABI: only sp is defined) -------------
tile_entry:
    li   sp, 0xBFF0
    .option push
    .option arch, +zicsr
    csrr t3, mhartid
    .option pop
    li   t4, 1
    beq  t3, t4, tile_h1
    li   t4, 2
    beq  t3, t4, tile_h2
    li   t4, 3
    beq  t3, t4, tile_h3
tile_park:
    j    tile_park

    # ------------------------------------------------------------------------
    # hart 1: THE `time` SUBJECT.
    # The instruction immediately after every encoding under test is an `addi`,
    # never a store, so F8 (TRAP_STATE decoding and committing the word at
    # pc_next_trad_reg) cannot fire on any of them.  The victims wedge in TCM,
    # not in the shared window, so they generate no arbiter traffic and cannot
    # disturb hart 0's observation.
    # ------------------------------------------------------------------------
tile_h1:
    li   t0, SH_TPROG
    li   t1, 1
    sw   t1, 0(t0)                  # PROG=1: about to read `time` -- TERMINAL
#ifdef RDTIMEMP_PASS_CONTROL
    .word ALWAYS_ILLEGAL            # PASS CONTROL: a trap that needs no change
#else
    .word CSRR_S0_C01               # csrrs s0, 0xC01, x0 -- MUST TRAP
#endif
    addi t1, x0, 2
    sw   t1, 0(t0)                  # PROG=2: reached ONLY if the read RETIRED
tile_h1_park:
    j    tile_h1_park

    # ---- hart 2: THE `timeh` SUBJECT ---------------------------------------
tile_h2:
    li   t0, SH_HPROG
    li   t1, 1
    sw   t1, 0(t0)                  # PROG=1: about to read `timeh` -- TERMINAL
#ifdef RDTIMEMP_PASS_CONTROL
    .word ALWAYS_ILLEGAL
#else
    .word CSRR_S1_C81               # csrrs s1, 0xC81, x0 -- MUST TRAP
#endif
    addi t1, x0, 2
    sw   t1, 0(t0)                  # PROG=2: reached ONLY if the read RETIRED
tile_h2_park:
    j    tile_h2_park

    # ------------------------------------------------------------------------
    # hart 3: THE ANTI-OVERKILL WALKER + the two narrow-form guards.
    # Legs 1-5 (cycle, instret, hpmcounter3, cycleh, instreth) must RETIRE in
    # every build, before and after the change; NPROG=6 is the correct terminal
    # value.  Legs 6-7 -- the two IMMEDIATE read forms of the subject CSRs --
    # are the post-change-live tail.
    # ------------------------------------------------------------------------
tile_h3:
    li   t0, SH_NPROG
    li   t1, 1
    sw   t1, 0(t0)                  # PROG=1: about to read `cycle`
    .word CSRR_S2_C00               # csrrs s2, 0xC00, x0 -- MUST NOT TRAP
    addi t1, x0, 2
    sw   t1, 0(t0)                  # PROG=2: about to read `instret`
    .word CSRR_S3_C02               # csrrs s3, 0xC02, x0 -- MUST NOT TRAP
    addi t1, x0, 3
    sw   t1, 0(t0)                  # PROG=3: about to read `hpmcounter3`
    .word CSRR_S4_C03               # csrrs s4, 0xC03, x0 -- MUST NOT TRAP
    addi t1, x0, 4
    sw   t1, 0(t0)                  # PROG=4: about to read `cycleh`
    .word CSRR_S7_C80               # csrrs s7, 0xC80, x0 -- MUST NOT TRAP
    addi t1, x0, 5
    sw   t1, 0(t0)                  # PROG=5: about to read `instreth`
    .word CSRR_S8_C82               # csrrs s8, 0xC82, x0 -- MUST NOT TRAP
    addi t1, x0, 6
    sw   t1, 0(t0)                  # PROG=6: all five retired -- TERMINAL
#ifdef RDTIMEMP_PASS_CONTROL
    .word ALWAYS_ILLEGAL
#else
    .word CSRSI_S5_C01              # csrrsi s5, 0xC01, 0 -- MUST TRAP
#endif
    addi t1, x0, 7
    sw   t1, 0(t0)                  # PROG=7: the immediate read form retired
#ifdef RDTIMEMP_PASS_CONTROL
    .word ALWAYS_ILLEGAL
#else
    .word CSRCI_S6_C81              # csrrci s6, 0xC81, 0 -- MUST TRAP (chained)
#endif
    addi t1, x0, 8
    sw   t1, 0(t0)                  # PROG=8: the timeh immediate form too
tile_h3_park:
    j    tile_h3_park

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) -- never fall
    # through; every hart-0 path above ends in a spin and every tile path ends
    # in an unconditional jump.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
