# See LICENSE for license details.

# VestaRV: the machine-information CSRs must read zero and must not trap
# THE FINDING: 0xF11 mvendorid, 0xF12 marchid, 0xF13 mimpid and 0xF15 mconfigptr are ABSENT from maindec.vhd's csr_addr_valid map, whose whole 0xFxx quadrant contains only 0xF14 mhartid, so a plain read of any of the four is an unknown CSR, valid_funct drops, and the illegal-instruction trap lands in the TERMINAL TRAP_STATE, wedging the hart forever. These are required read-only M-mode CSRs: zero is a legal value, but they must exist and must never trap. THE ASSERTION IS TWO-PART and both halves can fail it: the four reads must RETIRE and each must return exactly 0x00000000, so a read that retires with a wrong value is a FAIL.
# THE WRITE SIDE NEEDS NOTHING and this file proves it stays that way: csr_ro_denied is UNGATED, carries no ENABLE_ term and is address-agnostic within the quadrant, and the SYSTEM arm tests it BEFORE csr_addr_valid, so a write form aimed at any 0xF1x address traps in every build, before and after any fix.
# THE POLARITY IS INVERTED relative to the other multi-hart poisons: correct behaviour is the read RETIRING, so it is the PRE-FIX run that must be seen to fail, and that is why the observer exists. Without it a hart-0 subject would wedge on its own first csrr and the finding would present as a 100 ms watchdog hang, loud but undiscriminating and unable to name which CSR trapped. HART 0 NEVER EXECUTES ANY OF THE FOUR, in either polarity, which is what keeps the verdict path alive pre-fix.
# The three tile victims. Hart 1 is the SUBJECT: a stepped PROGRESS word walks all four reads, so one word gives per-CSR diagnosis, and post-fix it publishes the four values. Hart 2 is the two-sided WRITE CONTROL: a legal read of 0xF14, which must not trap, then a write form aimed at 0xF14, which must; 0xF14 is legal in both polarities, so csr_ro_denied is the only thing that can trap it, which is what makes the control mean something before and after. Hart 3 is the OVER-WIDE GUARD on 0xF16, which must keep trapping and wedges by design in both polarities, and with hart 2 it proves the "PROG stops where expected" observation is live pre-fix.
# 0xF10 AND 0xF16 ARE THE GUARDS, NOT 0xF14, which is implemented and legal in both polarities and would prove nothing. The allocated block is exactly 0xF11-0xF15, so the bracketing addresses catch different wrong bounds: 0xF10 a wrong lower bound or a 0xF1x nibble range, 0xF16 a wrong upper bound, an open-ended lower test or the nibble range. Both are oracle-validated as well as RTL-validated.
# THE SLOT ARGUMENT, to be read before moving anything: a must-trap encoding CONSUMES a hart, and four must-trap assertions are wanted while only three wedge slots exist, hart 1's being spent pre-fix on the subject's own first read and hart 0 being unable to take one. So hart 2 carries the 0xF14 write control and hart 3 the 0xF16 guard, both of which need both polarities, while the 0xF10 guard rides hart 1's post-fix runway, because AN OVER-WIDE-FIX GUARD HAS NO INFORMATION CONTENT PRE-FIX. Two further assertions are chained behind unmasked ones and are live only in an already-broken world, kept because each classifies the breakage: a write form aimed at 0xF11 after hart 1's 0xF10, on a different hart from the 0xF14 control so it cannot mask it, and a second 0xF10 read after hart 3's 0xF16, so a nibble-range fix gives a distinctive two-word signature. RESIDUAL: a fix of the exact form 0xF10 <= imm12 <= 0xF15 is caught only by hart 1 and one over-wide upward only by hart 3.
# THE POSITIVE HALF runs on hart 0 before any launch, in both polarities, and its proof is twofold: the values are asserted, and on a default build a wrongly trapped instruction wedges hart 0 terminally, so hart 0 reaching any verdict at all proves none of its legs trapped. POSPROG counts the legs so a wedged run is locatable. The legs are a base-ISA add, then three DISTINCT non-write forms aimed at the read-only quadrant, `csrr t0, mhartid`, `csrrci t2, mhartid, 0` and `csrrsi t1, mhartid, 0`, all of which must read 0; together they are the OVER-NARROW guard. Every encoding hart 0 executes is unconditionally legal on every matrix row, since CSR_MHARTID is the first term of csr_addr_valid with no ENABLE_ qualifier and hart_id is a port of csr_unit, so this file is knob-independent by construction, which an untagged catalog row has to be.
# THE PASS-POLARITY CONTROL -DIDCSRMP_PASS_CONTROL replaces ONLY the subject's four identity-CSR encodings with `li <rd>, 0`, leaving every other instruction, every PROG step, every store and the whole observer untouched, so on the unfixed tree the subject walks to PROG = 5, publishes four zeros and wedges on its 0xF10 runway read, which is exactly the predicted post-fix terminal state, exercising the pass path end to end with no RTL change. A detector never seen to pass is as untrustworthy as one never seen to fail. It makes no claim about the finding.
# Verdicts: a0 = 0xCAFEBABE means the four read zero and do not trap, writes to the read-only quadrant still trap, and neither guard address was admitted. a1 = 0x1DCF0F11/12/13/15 names which identity CSR TRAPPED, the finding, with a2 = PROG; 0x1DA10F11/12/13/15 names one that retired with a NONZERO value; 0x1DBA0F10 0xF10 admitted on hart 1's runway, over-wide low; 0x1DBA0F11 the write form aimed at 0xF11 also retired; 0x1DBA0F16 0xF16 admitted, over-wide high; 0x1DBA0F1F both admitted on hart 3, a nibble range; 0x1DBA0F14 the write form aimed at 0xF14 retired; 0x1DBA0F40 the legal read of 0xF14 trapped, over-narrow; 0x5E1D0001 a positive-half leg returned the wrong value; 0x5E1D0002 a victim never armed; 0x5E1D0003 a shared word did not read back; 0x5E1D0004 base-ISA sanity failed; 0x5E1D0005 POSPROG did not count every leg. NO a0 AT ALL is itself a result: hart 0 wedged inside its own positive half, meaning a fix made a legal read-only-quadrant read illegal; probe POSPROG at 0x10030 to name the leg.
# Invoke explicitly with ./xrun_batch.sh xxrv32ua-p-idcsrmp; post-fix all three tiles are parked in TRAP_STATE forever and never write their a0, which riscv_tb reports as a NOTE rather than a failure. N-agnostic: exactly three victims at any NHARTS and no shared word indexed by hartid. Shared words, all below 0x10500 and inside the bootrom zero range: 0x10014 SUBJPROG, 0x10018 VENDOR, 0x1001C ARCH, 0x10020 IMPID, 0x10024 CFGPTR, 0x10028 WPROG, 0x1002C GPROG, 0x10030 POSPROG. The band 0x10014-0x10030 is free at N=4 and N=18 and does not even overlap at N=18.

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
