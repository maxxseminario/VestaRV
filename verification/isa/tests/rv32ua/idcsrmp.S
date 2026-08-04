# See LICENSE for license details.

#*****************************************************************************
# idcsrmp.S   (ID-series, ID2 -- the BLIND DETECTOR for the identity-CSR hole)
#-----------------------------------------------------------------------------
# THE FINDING (ID0 probe SS1.1, re-verified in this file's own authoring pass at
# HEAD c8f84ae).  The four machine-information CSRs
#
#     0xF11 mvendorid   0xF12 marchid   0xF13 mimpid   0xF15 mconfigptr
#
# are ABSENT from maindec.vhd's `csr_addr_valid` map.  The whole 0xFxx quadrant
# contains exactly ONE address today -- 0xF14 `mhartid` -- so a plain READ of
# any of the four is an unknown CSR, `valid_funct <= csr_addr_valid` = '0', and
# the hart raises illegal-instruction.  On the shipped default that lands in the
# TERMINAL TRAP_STATE (self-loop, no exit), so the read WEDGES the hart forever.
# These are REQUIRED read-only M-mode CSRs: zero is a legal value, but they must
# exist and must never trap.
#
# THE USER'S RULING (R-DID1): all four read ZERO.  So the assertion is TWO-part
# and both halves must fail the test:  the four reads must RETIRE, *and* each
# must return exactly 0x00000000.  A read that retires with a wrong value is a
# FAIL here, not a pass.
#
# THE WRITE SIDE NEEDS NOTHING and this file proves it stays that way.
# `csr_ro_denied` (maindec.vhd:624-627) is UNGATED -- no ENABLE_ term -- and it
# is address-agnostic within the quadrant:
#     csr_ro_denied <= '1' when (is_csr_instr = '1' and
#                                imm12(11 downto 10) = "11" and
#                                (funct3(1 downto 0) = "01" or csr_rs1_zero = '0'))
# and the SYSTEM arm tests it BEFORE csr_addr_valid (maindec.vhd:943-948), so a
# WRITE FORM aimed at any 0xF1x address traps in every build, before and after
# any fix.
#
# ---------------------------------------------------------------------------
# WHY THIS TEST NEEDS FOUR HARTS, AND WHY THE OBSERVER EARNS ITS KEEP PRE-FIX
#   This is the rocsrwmp/trapstor/packalias construction, but the POLARITY IS
#   INVERTED relative to all three of them, and that inversion is the reason the
#   observer exists:
#
#                       rocsrwmp / packalias        THIS FILE
#     correct behaviour the encoding TRAPS          the read RETIRES
#     pre-fix           it retires (silent alias)   the victim WEDGES on it
#     post-fix          the victim WEDGES           it retires, reports values
#
#   So here the observer is needed for the PRE-FIX run -- the run that must be
#   SEEN TO FAIL.  Without it, a hart-0 subject would simply wedge on its own
#   first csrr and the finding would present as a 100 ms watchdog HANG: loud,
#   but undiscriminating (a hang is the same signal as a dozen unrelated
#   breakages, and it cannot name WHICH CSR trapped).  With it, the pre-fix run
#   is a clean a0 = 0xDEADBEEF whose a1 names the exact CSR address.
#
#   HART 0 NEVER EXECUTES ANY OF THE FOUR, in either polarity.  That is what
#   keeps the verdict path alive pre-fix, and it is deliberate, not incidental.
#
# THE THREE TILE VICTIMS
#   hart 1  SUBJECT.  A stepped PROGRESS word walks all four reads, so ONE word
#           gives per-CSR diagnosis: PROG = k names exactly which read trapped.
#           Post-fix it publishes the four values for hart 0 to check against
#           R-DID1's zero.  Its post-fix RUNWAY then carries two more assertions
#           (see the slot argument below).
#   hart 2  WRITE CONTROL, two-sided.  A legal read of 0xF14 (must not trap)
#           followed by a WRITE FORM aimed at 0xF14 (must trap).  0xF14 is
#           `mhartid` -- a LEGAL address in BOTH polarities -- so csr_ro_denied
#           is the only thing that can trap it, which is exactly what makes this
#           the control that means something before AND after.
#   hart 3  OVER-WIDE GUARD.  0xF16, an unallocated address that must keep
#           trapping.  It wedges by design, forever, in both polarities -- which
#           also makes it (with hart 2) the proof that the "PROG stops at its
#           expected value" observation is LIVE PRE-FIX, the packalias hart-3
#           argument.
#
# WHY 0xF10 AND 0xF16 AND NOT 0xF14 (correcting the kickoff, per R-ID0-1(1)).
#   0xF14 is `mhartid`: implemented, in the map, legal in BOTH polarities.  It
#   cannot be an over-wide-fix guard -- it would prove nothing.  The allocated
#   machine-information block is exactly 0xF11-0xF15, so the two addresses that
#   BRACKET it are 0xF10 and 0xF16, and each catches a different wrong bound:
#       0xF10  catches a wrong LOWER bound  (`>= 0xF10 ...`, and the nibble
#              range `0xF10..0xF1F`)
#       0xF16  catches a wrong UPPER bound  (`... <= 0xF1F`, an open-ended
#              `>= 0xF11`, and the nibble range)
#   Both are oracle-validated as well as RTL-validated: ID0 SS2.2 measured stock
#   spike and vesta_ref trapping both of them, so the guard is spec-correct and
#   not merely implementation-correct.
#
# THE SLOT ARGUMENT -- read this before "simplifying" the placement.
#   A must-trap encoding CONSUMES a hart: the victim wedges on it and never
#   reaches anything placed after it.  Four must-trap assertions are wanted
#   (0xF10 guard, 0xF16 guard, the 0xF14 write control, a 0xF11 write form) but
#   only THREE independent wedge slots exist at N=4 -- harts 1, 2 and 3 -- and
#   hart 1's is spent, pre-fix, on the subject's own first read.  Hart 0 cannot
#   take one: anything that traps there wedges the verdict.
#
#   What hart 1 DOES have is POST-FIX RUNWAY: once the four reads retire it is
#   still running, and one further must-trap encoding can be observed there.
#   The placement is therefore:
#       hart 2   0xF14 write control   -- needs BOTH polarities  -> a true slot
#       hart 3   0xF16 guard           -- needs BOTH polarities  -> a true slot
#       hart 1   0xF10 guard           -- post-fix runway
#   and this is the right way round, for a reason worth stating: AN OVER-WIDE-FIX
#   GUARD HAS NO INFORMATION CONTENT PRE-FIX, because pre-fix there is no fix to
#   be over-wide.  Pre-fix, 0xF10 traps for exactly the reason 0xF11 traps, and
#   hart 1's own PROG = 1 demonstrates that mechanism directly.  A guard placed
#   on a true slot but MASKED post-fix would be silent in the only polarity
#   where it can say anything.
#
#   Two assertions are chained behind an unmasked one and are therefore live
#   only in an already-broken world.  Both are recorded as secondary, not
#   deleted, because each still classifies the breakage:
#       hart 1, after 0xF10:  a WRITE FORM aimed at 0xF11 (the post-fix write
#           assertion).  It is on a DIFFERENT HART from the 0xF14 control, so it
#           cannot mask it -- which is the sequencing question the spec asks.
#           Its mechanism is fully covered by hart 2: csr_ro_denied names no
#           address, only the quadrant.
#       hart 3, after 0xF16:  the 0xF10 read again, so that a nibble-range fix
#           produces a distinctive TWO-word signature (hart 3 PROG = 3 as well
#           as hart 1 PROG = 6) instead of one.
#   RESIDUAL, stated rather than hidden: a fix of the exact form
#   `0xF10 <= imm12 <= 0xF15` is caught by hart 1 (PROG = 6) but NOT by hart 3,
#   and a fix that is over-wide only upward is caught by hart 3 and not hart 1.
#   Between them the four named wrong-fix shapes are all covered; no single
#   victim covers all of them, and with three victims none can.
#
# THE POSITIVE HALF runs on HART 0, before any launch, in both polarities, and
#   must pass today AND forever.  Its proof is twofold -- the VALUES are
#   asserted, and on a default build a wrongly-trapped instruction wedges hart 0
#   terminally, so hart 0 reaching any verdict at all is proof none of its legs
#   trapped (LIVENESS).  POSPROG counts the legs so a wedged run is locatable.
#       P0  base ISA add
#       P1  csrr   t0, mhartid      csrrs form, rs1 = x0   -> must read 0
#       P2  csrrci t2, mhartid, 0   uimm FIELD 0           -> must read 0
#       P3  csrrsi t1, mhartid, 0   uimm FIELD 0           -> must read 0
#   P1-P3 are three DISTINCT non-write forms aimed at the read-only quadrant.
#   Together they are the OVER-NARROW guard: a fix that made the quadrant, or
#   0xF1x-adjacent decode, illegal for reads shows up here as a hart-0 wedge.
#
#   EVERY encoding hart 0 executes is UNCONDITIONALLY legal on all 28 matrix
#   rows.  `imm12 = CSR_MHARTID` is the first term of csr_addr_valid and carries
#   no ENABLE_ qualifier (checked in the tree, not assumed), and hart_id is a
#   PORT of the csr_unit.  Nothing here reads a counter, an FP CSR or a trap
#   CSR, so this file is knob-independent by construction -- which is what an
#   UNTAGGED CATALOG row has to be (R-ID0-3), including the trapCsr-OFF row.
#
# N-AGNOSTIC.  Exactly three victims are launched (1, 2, 3) at any NHARTS; on an
#   Argus N=18 build harts 4-17 are never launched and stay parked in the
#   bootrom, which riscv_tb reports as a NOTE.  No shared word here is indexed
#   by hartid, so the layout is identical at N=4 and N=18.
#
# THE PASS-POLARITY CONTROL (-DIDCSRMP_PASS_CONTROL, default build only).
#   A detector that has never been seen to PASS is as untrustworthy as one that
#   has never been seen to FAIL: it might be structurally incapable of passing.
#   This arm replaces ONLY the subject's four identity-CSR encodings with
#   `li <rd>, 0`, leaving every other instruction, every PROG step, every store
#   and the whole observer untouched.  On the UNFIXED tree the subject then
#   walks to PROG = 5, publishes four zeros, and wedges on its 0xF10 runway
#   read -- which is EXACTLY the predicted post-fix terminal state -- so the
#   a0 = 0xCAFEBABE path is exercised end to end with no RTL change.
#   It is a control, not a detector: it makes NO claim about the finding.
#
# ---------------------------------------------------------------------------
# VERDICT.  a0 = 0xCAFEBABE => the four identity CSRs read zero and do not trap,
# writes to the read-only quadrant still trap, and neither 0xF10 nor 0xF16 was
# admitted.  a0 = 0xDEADBEEF with:
#   a1 = 0x1DCF0F11   csrr mvendorid  TRAPPED   <-- THE FINDING (a2 = PROG = 1)
#   a1 = 0x1DCF0F12   csrr marchid    TRAPPED   <-- THE FINDING (a2 = PROG = 2)
#   a1 = 0x1DCF0F13   csrr mimpid     TRAPPED   <-- THE FINDING (a2 = PROG = 3)
#   a1 = 0x1DCF0F15   csrr mconfigptr TRAPPED   <-- THE FINDING (a2 = PROG = 4)
#   a1 = 0x1DA10F11   mvendorid  retired with a NONZERO value (a2 = the value)
#   a1 = 0x1DA10F12   marchid    retired with a NONZERO value (a2 = the value)
#   a1 = 0x1DA10F13   mimpid     retired with a NONZERO value (a2 = the value)
#   a1 = 0x1DA10F15   mconfigptr retired with a NONZERO value (a2 = the value)
#   a1 = 0x1DBA0F10   0xF10 was ADMITTED on hart 1's runway -- over-wide LOW
#   a1 = 0x1DBA0F11   ...and the WRITE FORM aimed at 0xF11 also retired
#   a1 = 0x1DBA0F16   0xF16 was ADMITTED on hart 3 -- over-wide HIGH
#   a1 = 0x1DBA0F1F   0xF16 AND 0xF10 admitted on hart 3 -- a 0xF1x NIBBLE RANGE
#   a1 = 0x1DBA0F14   the WRITE FORM aimed at 0xF14 RETIRED -- an F10 regression
#   a1 = 0x1DBA0F40   the LEGAL read of 0xF14 TRAPPED on hart 2 -- OVER-NARROW
#   a1 = 0x5E1D0001   a positive-half leg returned the wrong value
#   a1 = 0x5E1D0002   a victim never armed (a2 = SUBJPROG, a3 = WPROG*16+GPROG)
#   a1 = 0x5E1D0003   a shared word did not read back: shared-RAM setup break
#   a1 = 0x5E1D0004   base-ISA sanity failed
#   a1 = 0x5E1D0005   POSPROG did not count every positive leg
# NO a0 AT ALL (tb watchdog) is itself a result: hart 0 wedged inside its own
#   positive half, i.e. A FIX MADE A LEGAL READ-ONLY-QUADRANT READ ILLEGAL.
#   Probe POSPROG (0x10030) and :dut:hart0:core:pc to name the leg.
#
# STAGED, NOT IN ANY STANDING LIST YET.  Post-fix all three tiles are parked in
#   TRAP_STATE forever and never write a0_1/a0_2/a0_3; riscv_tb reports "tile
#   hart(s) silent/parked", a NOTE, not a failure (the trapstor precedent proves
#   a permanently-wedged victim is not suite-disqualifying).  Invoke explicitly
#   with ./xrun_batch.sh xxrv32ua-p-idcsrmp.  Entry into xrun_parallel.sh's
#   TEST_FILES and into the verify_stage.py CATALOG is ID4's deliberate re-pin.
#
# SHARED WORDS CLAIMED (all < 0x10500 and inside the bootrom zero range):
#     0x10014  SUBJPROG  hart 1's stepped progress word
#     0x10018  VENDOR    hart 1's mvendorid  read-back
#     0x1001C  ARCH      hart 1's marchid    read-back
#     0x10020  IMPID     hart 1's mimpid     read-back
#     0x10024  CFGPTR    hart 1's mconfigptr read-back
#     0x10028  WPROG     hart 2's progress (the 0xF14 write control)
#     0x1002C  GPROG     hart 3's progress (the 0xF16/0xF10 guard)
#     0x10030  POSPROG   hart 0's positive-half leg counter
#   The band 0x10014-0x10030 is free at N=4 AND at N=18, and it is one of the
#   few remaining bands that does not even overlap at N=18: below it shmem tops
#   out at 0x10008 and shlrsc's two fixed words are 0x1000C/0x10010; above it
#   shlrsc's tile hammer array starts at 0x10040 and grows UPWARD only
#   (0x1004C at N=4, 0x10084 at N=18).  No ledger entry, and no N-indexed array
#   in the tree, reaches 0x10014-0x1003C.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_SUBJPROG  0x10014
#define SH_VENDOR    0x10018
#define SH_ARCH      0x1001C
#define SH_IMPID     0x10020
#define SH_CFGPTR    0x10024
#define SH_WPROG     0x10028
#define SH_GPROG     0x1002C
#define SH_POSPROG   0x10030

#define TILE_WORDS   1024       /* covers 0x8000-0x8FFF */
#define ARM_BUDGET   12000
#define WATCH_ITERS  4000

/* Every CSR encoding under test is spelled as a .word, so the test does not
   depend on gas's CSR name table (gas 2.41 has no `mconfigptr` name at all).
   All eleven were verified by objdump before the first build.               */
#define CSRR_S0_F11   0xF1102473    /* csrrs s0, 0xF11, x0   mvendorid       */
#define CSRR_S1_F12   0xF12024F3    /* csrrs s1, 0xF12, x0   marchid         */
#define CSRR_S2_F13   0xF1302973    /* csrrs s2, 0xF13, x0   mimpid          */
#define CSRR_S3_F15   0xF15029F3    /* csrrs s3, 0xF15, x0   mconfigptr      */
#define CSRR_S4_F10   0xF1002A73    /* csrrs s4, 0xF10, x0   unallocated     */
#define CSRR_S5_F16   0xF1602AF3    /* csrrs s5, 0xF16, x0   unallocated     */
#define CSRR_T3_F14   0xF1402E73    /* csrrs t3, 0xF14, x0   mhartid  LEGAL  */
#define CSRW_F14_T0   0xF1429073    /* csrrw x0, 0xF14, t0   MUST TRAP       */
#define CSRW_F11_T0   0xF1129073    /* csrrw x0, 0xF11, t0   MUST TRAP       */
#define CSRR_T0_F14   0xF14022F3    /* csrrs  t0, 0xF14, x0                  */
#define CSRCI_T2_F14  0xF14073F3    /* csrrci t2, 0xF14, 0                   */
#define CSRSI_T1_F14  0xF1406373    /* csrrsi t1, 0xF14, 0                   */

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

    li   s2, SH_SUBJPROG
    li   s3, SH_WPROG
    li   s4, SH_GPROG
    li   s5, SH_POSPROG

    # ==================================================================
    # clear every claimed word and prove it read back
    # ==================================================================
    li   a1, 0x5E1D0003
    sw   x0, 0(s2)
    lw   t1, 0(s2)
    bnez t1, id_fail
    sw   x0, 0(s3)
    lw   t1, 0(s3)
    bnez t1, id_fail
    sw   x0, 0(s4)
    lw   t1, 0(s4)
    bnez t1, id_fail
    sw   x0, 0(s5)
    lw   t1, 0(s5)
    bnez t1, id_fail

    li   t0, SH_VENDOR
    sw   x0, 0(t0)
    lw   t1, 0(t0)
    bnez t1, id_fail
    li   t0, SH_ARCH
    sw   x0, 0(t0)
    lw   t1, 0(t0)
    bnez t1, id_fail
    li   t0, SH_IMPID
    sw   x0, 0(t0)
    lw   t1, 0(t0)
    bnez t1, id_fail
    li   t0, SH_CFGPTR
    sw   x0, 0(t0)
    lw   t1, 0(t0)
    bnez t1, id_fail

    li   s6, 0                      # POSPROG register shadow

    # ==================================================================
    # THE POSITIVE HALF.  Three distinct NON-WRITE forms aimed at the
    # read-only quadrant, all unconditionally legal on every config.
    # Proof is LIVENESS plus the asserted values.
    # ==================================================================
    .macro ID_OK
    addi s6, s6, 1
    sw   s6, 0(s5)
    .endm

    li   t0, 1234                   # P0: base ISA sanity
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    ID_OK
    li   a1, 0x5E1D0004
    bne  t2, t3, id_fail

    li   t0, 0x5A5A5A5A
    .word CSRR_T0_F14               # P1: csrr t0, mhartid
    ID_OK
    li   a1, 0x5E1D0001
    bnez t0, id_fail                # hart 0 -> mhartid must read 0

    li   t2, 0x5A5A5A5A
    .word CSRCI_T2_F14              # P2: csrrci t2, mhartid, 0
    ID_OK
    li   a1, 0x5E1D0001
    bnez t2, id_fail

    li   t1, 0x5A5A5A5A
    .word CSRSI_T1_F14              # P3: csrrsi t1, mhartid, 0
    ID_OK
    li   a1, 0x5E1D0001
    bnez t1, id_fail

    lw   t1, 0(s5)
    li   t2, 4
    li   a1, 0x5E1D0005
    bne  t1, t2, id_fail            # four legs, all survived, all recorded

    # ==================================================================
    # launch the three victims
    # ==================================================================
    MP_STAGE_IMAGE(TILE_WORDS)
    MP_LAUNCH_HART(1, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(2, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(3, tile_entry, TILE_WORDS)

    # ==================================================================
    # bounded wait for every victim to reach its EXPECTED terminal state:
    #   SUBJPROG >= 5   all four identity reads retired and published
    #   WPROG    >= 2   the legal 0xF14 read retired
    #   GPROG    >= 1   the guard victim reached its 0xF16 read
    # Pre-fix SUBJPROG sticks at 1..4 and this budget expires -- which is
    # the FINDING's clean, diagnosable failure, not a watchdog hang.
    # ==================================================================
    li   s7, 5
    li   s8, 2
    li   s9, 1
    li   t6, ARM_BUDGET
id_wait:
    lw   t2, 0(s2)
    blt  t2, s7, id_wait_next
    lw   t3, 0(s3)
    blt  t3, s8, id_wait_next
    lw   t4, 0(s4)
    bge  t4, s9, id_armed
id_wait_next:
    addi t6, t6, -1
    bnez t6, id_wait

    # ---- the budget expired: name the reason ----------------------------
    lw   a2, 0(s2)                  # a2 = SUBJPROG, for the probe and for a1
    lw   t3, 0(s3)
    lw   t4, 0(s4)
    slli a3, t3, 4
    add  a3, a3, t4                 # a3 = WPROG*16 + GPROG

    li   t5, 1
    li   a1, 0x1DCF0F11
    beq  a2, t5, id_fail            # wedged ON the mvendorid read
    li   t5, 2
    li   a1, 0x1DCF0F12
    beq  a2, t5, id_fail            # wedged ON the marchid read
    li   t5, 3
    li   a1, 0x1DCF0F13
    beq  a2, t5, id_fail            # wedged ON the mimpid read
    li   t5, 4
    li   a1, 0x1DCF0F15
    beq  a2, t5, id_fail            # wedged ON the mconfigptr read
    li   t5, 1
    li   a1, 0x1DBA0F40
    beq  t3, t5, id_fail            # hart 2 wedged on a LEGAL 0xF14 read
    li   a1, 0x5E1D0002             # something never armed at all
    j    id_fail

id_armed:
    # ==================================================================
    # observe: no victim may advance past its correct terminal state
    # ==================================================================
    li   t6, WATCH_ITERS
id_watch:
    lw   t2, 0(s2)
    bne  t2, s7, id_subj_over       # SUBJPROG must STAY 5
    lw   t3, 0(s3)
    bne  t3, s8, id_wctl_over       # WPROG must STAY 2
    lw   t4, 0(s4)
    bne  t4, s9, id_guard_over      # GPROG must STAY 1
    addi t6, t6, -1
    bnez t6, id_watch

    # ==================================================================
    # R-DID1: every published value must be exactly zero
    # ==================================================================
    li   t0, SH_VENDOR
    lw   a2, 0(t0)
    li   a1, 0x1DA10F11
    bnez a2, id_fail
    li   t0, SH_ARCH
    lw   a2, 0(t0)
    li   a1, 0x1DA10F12
    bnez a2, id_fail
    li   t0, SH_IMPID
    lw   a2, 0(t0)
    li   a1, 0x1DA10F13
    bnez a2, id_fail
    li   t0, SH_CFGPTR
    lw   a2, 0(t0)
    li   a1, 0x1DA10F15
    bnez a2, id_fail

    RVTEST_PASS                     # a0 = 0xCAFEBABE

id_subj_over:
    mv   a2, t2
    li   t5, 6
    li   a1, 0x1DBA0F10             # 0xF10 admitted on the runway
    beq  t2, t5, id_fail
    li   a1, 0x1DBA0F11             # ...and the 0xF11 write form retired too
    j    id_fail
id_wctl_over:
    mv   a2, t3
    li   a1, 0x1DBA0F14             # csrw mhartid retired: F10 regression
    j    id_fail
id_guard_over:
    mv   a2, t4
    li   t5, 2
    li   a1, 0x1DBA0F16             # 0xF16 admitted
    beq  t4, t5, id_fail
    li   a1, 0x1DBA0F1F             # 0xF16 AND 0xF10 admitted: nibble range
id_fail:
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

    # ---- hart 1: THE SUBJECT ------------------------------------------------
    # The instruction immediately after every encoding under test is an `addi`,
    # never a store, so F8 (TRAP_STATE decoding and committing the word at
    # pc_next_trad_reg) cannot fire on any of them.
tile_h1:
    li   t0, SH_SUBJPROG
    li   t1, 1
    sw   t1, 0(t0)                  # PROG=1: about to read mvendorid
#ifdef IDCSRMP_PASS_CONTROL
    li   s0, 0                      # PASS CONTROL: the read is not executed
#else
    .word CSRR_S0_F11               # csrr s0, mvendorid   0xF11
#endif
    addi t1, x0, 2
    sw   t1, 0(t0)                  # PROG=2: about to read marchid
#ifdef IDCSRMP_PASS_CONTROL
    li   s1, 0
#else
    .word CSRR_S1_F12               # csrr s1, marchid     0xF12
#endif
    addi t1, x0, 3
    sw   t1, 0(t0)                  # PROG=3: about to read mimpid
#ifdef IDCSRMP_PASS_CONTROL
    li   s2, 0
#else
    .word CSRR_S2_F13               # csrr s2, mimpid      0xF13
#endif
    addi t1, x0, 4
    sw   t1, 0(t0)                  # PROG=4: about to read mconfigptr
#ifdef IDCSRMP_PASS_CONTROL
    li   s3, 0
#else
    .word CSRR_S3_F15               # csrr s3, mconfigptr  0xF15
#endif
    addi t1, x0, 5
    li   t2, SH_VENDOR              # publish the four values BEFORE PROG=5,
    sw   s0, 0(t2)                  # so PROG=5 means "read AND published"
    li   t2, SH_ARCH
    sw   s1, 0(t2)
    li   t2, SH_IMPID
    sw   s2, 0(t2)
    li   t2, SH_CFGPTR
    sw   s3, 0(t2)
    sw   t1, 0(t0)                  # PROG=5: all four retired -- TERMINAL
    .word CSRR_S4_F10               # 0xF10 -- MUST TRAP (over-wide-LOW guard)
    addi t1, x0, 6
    sw   t1, 0(t0)                  # PROG=6: reached ONLY if 0xF10 was admitted
    .word CSRW_F11_T0               # csrw 0xF11, t0 -- MUST TRAP (chained)
    addi t1, x0, 7
    sw   t1, 0(t0)                  # PROG=7: the RO-quadrant write retired too
tile_h1_park:
    j    tile_h1_park

    # ---- hart 2: THE TWO-SIDED WRITE CONTROL --------------------------------
tile_h2:
    li   t0, SH_WPROG
    li   t1, 1
    sw   t1, 0(t0)                  # PROG=1: about to read 0xF14 (legal)
    .word CSRR_T3_F14               # csrr t3, mhartid -- MUST NOT TRAP
    addi t1, x0, 2
    sw   t1, 0(t0)                  # PROG=2: the legal read retired -- TERMINAL
    .word CSRW_F14_T0               # csrw mhartid, t0 -- MUST TRAP, both sides
    addi t1, x0, 3
    sw   t1, 0(t0)                  # PROG=3: reached ONLY if it did NOT trap
tile_h2_park:
    j    tile_h2_park

    # ---- hart 3: THE OVER-WIDE GUARD ----------------------------------------
tile_h3:
    li   t0, SH_GPROG
    li   t1, 1
    sw   t1, 0(t0)                  # PROG=1: about to read 0xF16 -- TERMINAL
    .word CSRR_S5_F16               # 0xF16 -- MUST TRAP, both polarities
    addi t1, x0, 2
    sw   t1, 0(t0)                  # PROG=2: reached ONLY if 0xF16 was admitted
    .word CSRR_S4_F10               # 0xF10 -- MUST TRAP (chained secondary)
    addi t1, x0, 3
    sw   t1, 0(t0)                  # PROG=3: a 0xF1x NIBBLE RANGE was admitted
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
