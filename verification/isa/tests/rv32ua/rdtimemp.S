# See LICENSE for license details.

#*****************************************************************************
# rdtimemp.S   (D-series DD11-N1 -- the BLIND DETECTOR for the `time` CSR hole)
#-----------------------------------------------------------------------------
# THE CONTRACT THIS FILE ASSERTS (a USER decision, authored BEFORE the RTL
# change and never having seen it).  In the SHIPPED DEFAULT build of the chip,
# with no config change of any kind:
#
#     A CSR READ of 0xC01 (`time`) and of 0xC81 (`timeh`) MUST raise
#     illegal-instruction.  Reads of 0xC00 (`cycle`), 0xC02 (`instret`) and
#     0xC03 (`hpmcounter3`) MUST still retire.
#
# Two further must-retire addresses are asserted here that the decision text
# does not name, and the reason is in the RTL rather than in the ruling:
# maindec.vhd:484 admits `CSR_CYCLEH or CSR_TIMEH or CSR_INSTRETH` on ONE LINE,
# so the single likeliest over-wide edit -- deleting the line that carries
# 0xC81 -- takes 0xC80 (`cycleh`) and 0xC82 (`instreth`) with it.  Those two
# are therefore anti-overkill legs as well, alongside the three the ruling
# names.  0xC81 is the only address on that line that may change.
#
# WHY.  There is no `mtime` CSR in RISC-V: the machine timer is the CLINT's
# MEMORY-MAPPED mtime (here at 0x5000 + roundup16(4*NHARTS)).  `time`/`timeh`
# are the USER-VIEW shadows of it, and an implementation that has no mapping
# from the CSR to that memory must NOT invent one -- the spec's expectation is
# that `rdtime` traps and M-mode emulates it.  Answering a `rdtime` with a
# constant is the one behaviour that is worse than trapping: software cannot
# tell a stopped clock from a real one.
#
# WHERE THE RTL SITS TODAY (re-grepped in this file's own authoring pass at
# HEAD 723b78a -- confirm, do not inherit):
#     maindec.vhd:483-484  csr_addr_valid admits, with NO ENABLE_ qualifier:
#                            imm12 = CSR_CYCLE or imm12 = CSR_TIME or
#                            imm12 = CSR_INSTRET ...
#                            imm12 = CSR_CYCLEH or imm12 = CSR_TIMEH or ...
#                          so 0xC01/0xC81 are KNOWN addresses in every build.
#     maindec.vhd:1054     the SYSTEM arm then sets valid_funct <= csr_addr_valid
#                          => '1', so no trap.
#     csr_unit.vhd:560-570 there is NO read arm for CSR_TIME or CSR_TIMEH (there
#                          is one for CSR_CYCLE, CSR_INSTRET and CSR_HPMCOUNTER3),
#                          so both ride `when others => CSR_ZERO_X`.
#     NET EFFECT TODAY: `rdtime` retires and returns 0x00000000, forever.  A
#     stopped clock that software has no way to detect.  THAT is the finding.
#
# THE WRITE SIDE NEEDS NOTHING and is deliberately not re-litigated here.
#   `csr_ro_denied` (maindec.vhd) is UNGATED and address-agnostic within the
#   quadrant, and 0xC01/0xC81 have imm12(11:10) = "11", so a WRITE FORM aimed at
#   either already traps in every build -- before and after this change (F10,
#   rocsrw.S L3 is literally `csrwi time, 0`).  This file changes nothing there
#   and asserts nothing there; rocsrw/rocsrwmp own that claim.
#
# ---------------------------------------------------------------------------
# WHY THIS TEST NEEDS FOUR HARTS
#   Correct behaviour here is a TRAP, and on the shipped default an illegal
#   instruction lands in the TERMINAL TRAP_STATE (self-loop, no handler, no
#   exit).  A hart that reads `time` correctly therefore NEVER writes a0 again,
#   so the hart under test can never be the a0 gate.  VICTIMS are tile harts
#   1, 2 and 3; the OBSERVER is hart 0, which keeps the ordinary PASS/FAIL
#   contract.  This is the trapstor / rocsrwmp / packalias construction, and
#   the polarity is theirs, not idcsrmp's:
#
#                       THIS FILE                    idcsrmp.S
#     correct           the read TRAPS               the read RETIRES
#     pre-change        it retires (silent zero)     the victim WEDGES
#     post-change       the victim WEDGES            it retires
#
#   Each victim writes a PROGRESS word BEFORE its encoding and again AFTER it,
#   so the two states are unambiguous: PROG = k means "reached leg k and is
#   wedged in it", PROG = k+1 means "leg k retired".
#
#   HART 0 EXECUTES NO 0xCxx ENCODING AT ALL, in either polarity, and that is
#   deliberate rather than incidental: it is what keeps the verdict path alive
#   when an over-wide change makes a counter read illegal.  Every encoding
#   hart 0 does execute (base ISA, one `csrr mhartid`) is unconditionally legal
#   on all 28+ matrix rows -- `imm12 = CSR_MHARTID` is the first term of
#   csr_addr_valid and carries no ENABLE_ qualifier, and hart_id is a PORT of
#   the csr_unit.  That is what an UNTAGGED CATALOG row has to be (R-ID0-3),
#   including the trapCsr-OFF row and the debug-OFF rows.
#
# THE THREE VICTIMS
#   hart 1  THE `time` SUBJECT.  One encoding: the canonical `rdtime` form,
#           csrrs rd, 0xC01, x0.  A TRUE SLOT -- it means something in both
#           polarities, and it is the exact encoding gas emits for `rdtime`.
#   hart 2  THE `timeh` SUBJECT.  csrrs rd, 0xC81, x0.  A separate hart and
#           therefore a separate TRUE SLOT, so a change that catches `time` but
#           forgets `timeh` (or vice versa) cannot hide behind the other.
#   hart 3  THE ANTI-OVERKILL WALKER, and the only victim with a POST-CHANGE
#           LIVE TAIL.  It reads 0xC00, 0xC02, 0xC03, 0xC80, 0xC82 in turn --
#           five legs that must RETIRE in every build, before and after --
#           stepping NPROG to its correct terminal value 6, and THEN executes
#           two ALTERNATE READ FORMS of the two subject CSRs (csrrsi/csrrci
#           with the uimm FIELD zero, which are reads, not writes).  Those two
#           are must-trap assertions placed where they are still live once the
#           change lands.
#
# THE SLOT ARGUMENT -- read this before "simplifying" the placement.
#   A must-trap encoding CONSUMES a hart: the victim wedges in it and never
#   reaches anything placed after it.  At N=4 there are exactly three wedge
#   slots (harts 1, 2, 3) and hart 0 cannot take one.  Post-change, harts 1 and
#   2 are spent on their first encoding, so the ONLY position that is still
#   executing after the change lands is hart 3's tail -- because everything in
#   front of it is required to retire.  The two assertions that need to be live
#   POST-change (the narrow-form guards) therefore go THERE, and the two that
#   need a hart to themselves (the canonical time/timeh reads) take the true
#   slots.  This is the right way round for the same reason idcsrmp's is: an
#   assertion that can only speak in the polarity that already exists is worth
#   less than one that speaks in the polarity being created.
#
#   RESIDUAL, stated rather than hidden: hart 3's two tail legs are CHAINED, so
#   a change that catches `csrrsi time` but misses `csrrci timeh` stops NPROG
#   at 4 and is NOT caught.  The first of the pair is placed first because a
#   narrow change is likelier to be narrow in the FORM dimension (it is the one
#   csr_addr_valid does not express) than in the ADDRESS dimension (which
#   harts 1 and 2 already cover independently).  A fourth victim would close
#   it; N=4 does not have one.
#
# THE ANTI-OVERKILL CONTROL IS ON HART 3, NOT HART 0, AND THAT IS THE POINT.
#   Putting `csrr cycle` on hart 0 would make an over-wide change present as a
#   100 ms watchdog HANG -- loud, but undiscriminating, and it would MASK the
#   clean signal from every other victim.  On hart 3 the same over-wide change
#   presents as a0 = 0xDEADBEEF with a1 naming the exact CSR that wrongly
#   trapped (0x0BAD0C00 / 0x0BAD0C02 / 0x0BAD0C03).  The mandated control keeps
#   its full force and gains a diagnosis.
#
# KNOB-INDEPENDENT BY CONSTRUCTION.  Nothing in this file reads a trap CSR, a
#   debug CSR, an FP CSR, a PMP CSR or a jvt.  The seven CSR addresses it does
#   touch are admitted by csr_addr_valid with no ENABLE_ term at all today
#   (0xC00/0xC01/0xC02/0xC80/0xC81/0xC82 by explicit equality, 0xC03 by the
#   ungated CSR_HPMCOUNTER3..0xC1F range compare), and all seven are read from
#   M-mode, so the U-mode `ucnt_denied`/mcounteren path is out of reach.  No
#   -DCORE_ENABLE_* dispatch appears anywhere below, which is the property that
#   lets this file run against the CANONICAL rcf/ image set (DEFINES=(none)) and
#   against every polarity of every knob.
#
# NOT A COSIM TEST.  KEEP IT OUT OF cosim_tests.txt AND cosim_sh_tests.txt.
#   It is trap-poison class: the harts under test end in TRAP_STATE by design,
#   and the reference's --isa always carries `_zicntr`, so Spike RETIRES rdtime
#   and would report a DIVERGE that is the ORACLE's configuration and not the
#   DUT's behaviour.  Nothing here needs lockstep -- the claim is entirely about
#   whether an encoding traps, which a0/a1 already carry.
#
# N-AGNOSTIC.  Exactly three victims are launched (1, 2, 3) at any NHARTS; on an
#   Argus N=18 build harts 4-17 are never launched and stay parked in the
#   bootrom, which riscv_tb reports as a NOTE.  No shared word here is indexed
#   by hartid, so the layout is identical at N=4 and N=18.
#
# THE PASS-POLARITY CONTROL (-DRDTIMEMP_PASS_CONTROL).
#   A detector that has never been seen to PASS is as untrustworthy as one that
#   has never been seen to FAIL: it might be structurally incapable of passing.
#   This arm replaces ONLY the four must-trap encodings with .word 0x0000007F --
#   an opcode absent from maindec's valid_opcode list in every build -- leaving
#   every PROG step, every store, every negative leg and the whole observer
#   untouched.  On the UNCHANGED tree the three victims then reach EXACTLY the
#   predicted post-change terminal state (TPROG 1, HPROG 1, NPROG 6) and hart 0
#   walks the a0 = 0xCAFEBABE path end to end with no RTL change at all.
#   It is a control, not a detector: it makes NO claim about the finding.
#
# ---------------------------------------------------------------------------
# VERDICT.  a0 = 0xCAFEBABE => a read of `time` and of `timeh` traps, in the
# default build, in both the canonical and the immediate read forms, and cycle,
# instret, hpmcounter3, cycleh and instreth all still retire.
# a0 = 0xDEADBEEF with:
#   a1 = 0x0C010001   hart 1 executed PAST `csrrs rd, 0xC01, x0`   <-- THE
#                     FINDING.  `rdtime` retired.  (a2 = TPROG)
#   a1 = 0x0C810001   hart 2 executed PAST `csrrs rd, 0xC81, x0`   <-- THE
#                     FINDING.  `rdtimeh` retired.  (a2 = HPROG)
#   a1 = 0x0C010002   hart 3 executed PAST `csrrsi rd, 0xC01, 0`: the change
#                     misses the immediate read form of `time`  (a2 = NPROG)
#   a1 = 0x0C810002   hart 3 executed PAST `csrrci rd, 0xC81, 0`: the change
#                     misses the immediate read form of `timeh` (a2 = NPROG)
#   a1 = 0x0BAD0C00   hart 3 wedged on `csrr rd, cycle`       -- OVER-WIDE
#   a1 = 0x0BAD0C02   hart 3 wedged on `csrr rd, instret`     -- OVER-WIDE
#   a1 = 0x0BAD0C03   hart 3 wedged on `csrr rd, hpmcounter3` -- OVER-WIDE
#   a1 = 0x0BAD0C80   hart 3 wedged on `csrr rd, cycleh`      -- OVER-WIDE:
#                     maindec.vhd:484's whole line was deleted, not just 0xC81
#   a1 = 0x0BAD0C82   hart 3 wedged on `csrr rd, instreth`    -- OVER-WIDE
#   a1 = 0x5E7A0001   a victim never armed (a2 = TPROG*256 + HPROG*16 + NPROG)
#   a1 = 0x5E7A0002   a shared word did not read back: shared-RAM setup break
#   a1 = 0x5E7A0003   base-ISA sanity failed
# NO a0 AT ALL (tb watchdog) is itself a result: hart 0 can only wedge on
#   `csrr mhartid` or on the shared stores, so it means the decode of the
#   READ-ONLY QUADRANT AT LARGE was made illegal, not just 0xC01/0xC81.
#   Probe :dut:hart0:core:pc and the three PROG words to place it.
#
# SHARED WORDS CLAIMED (all < 0x10500 and inside the bootrom 0x10000-0x107FF
# zero range, so the write-before-read contract is satisfied at boot; hart 0
# clears and reads back all three anyway, before any launch):
#     0x10034  TPROG   hart 1's progress (the `time` subject)
#     0x10038  HPROG   hart 2's progress (the `timeh` subject)
#     0x1003C  NPROG   hart 3's progress (the anti-overkill walker)
#   The band 0x10034-0x1003C is free at N=4 AND at N=18, and it does not even
#   overlap at N=18: below it idcsrmp's claim tops out at 0x10030 (POSPROG) and
#   above it shlrsc's tile hammer array starts at 0x10040 and grows upward only
#   (0x1004C at N=4, 0x10084 at N=18).  This is the gap idcsrmp.S's own header
#   names -- "no ledger entry, and no N-indexed array in the tree, reaches
#   0x10014-0x1003C" -- now claimed rather than merely observed.  Three words is
#   the whole gap; a future instrument needing more must go elsewhere.
#*****************************************************************************

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
