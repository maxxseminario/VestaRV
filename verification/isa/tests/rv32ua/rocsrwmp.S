# See LICENSE for license details.

#*****************************************************************************
# rocsrwmp.S   (F-series fix pass, wave W5 -- the DEFAULT-BUILD detector for F10)
#-----------------------------------------------------------------------------
# F10: a WRITE FORM aimed at a CSR whose address has bits[11:10] = "11" (the
# READ-ONLY quadrant) is accepted and silently dropped instead of raising an
# illegal-instruction exception.  The mechanism is documented in the sibling
# file rocsrw.S; in one line: maindec.vhd:790-795 sets
# `valid_funct <= csr_addr_valid`, and csr_addr_valid (maindec.vhd:381-419) is
# a pure ADDRESS map with no reference to csr_op or to the rs1/uimm field --
# while csr_unit.vhd:456 already decodes the write form correctly and uses it
# only as a store strobe.
#
# THE USER'S RULING: the trap applies in EVERY build, not just a knobs-on one.
# rocsrw.S can only test a build where CORE_ENABLE_TRAPCSR is true, because it
# needs a recoverable trap.  THIS file covers the DEFAULT build -- the one the
# ruling actually changes -- and that build has no trap handler at all.
#
# WHY THIS TEST NEEDS THREE HARTS
#   On a default build an illegal instruction lands in the TERMINAL TRAP_STATE
#   (self-loop, no exit, pc_en = '0').  A hart that enters it NEVER writes a0
#   again, so the offending hart can never be the a0 gate.  Here the VICTIMS
#   are tile harts 1 and 2 and the OBSERVER is hart 0, which keeps the ordinary
#   PASS/FAIL contract -- the trapstor.S (W1) pattern.
#
#   Each victim writes a PROGRESS word BEFORE its illegal encoding and again
#   AFTER it.  The two states are unambiguous:
#       PROGRESS = 1  the victim reached the encoding and is wedged in it
#                     => the write TRAPPED   (post-fix, the PASS condition)
#       PROGRESS = 2  the victim executed straight through the encoding
#                     => the write was a silent NOP   (pre-fix, THE FINDING)
#   Hart 0 refuses to render any verdict until it has seen PROGRESS = 1 from
#   BOTH victims, so a tile that never launched FAILs rather than vacuously
#   passing.
#
#   The victims wedge in TCM, not in the shared window: TRAP_STATE's fetch
#   address is pc_next_trad_reg (a TCM address here), so the wedged harts
#   generate no arbiter traffic and cannot disturb hart 0's observation.  The
#   instruction placed immediately after each illegal encoding is an `addi`,
#   never a store, so F8 (TRAP_STATE commits the word at pc+4 if it decodes as
#   a store) cannot fire either.
#
# THE VICTIM ENCODINGS
#   hart 1   f1429073   csrw mhartid, t0    CSRRW at 0xF14, [11:10] = "11"
#   hart 2   c0001073   `unimp` itself      = csrrw x0, cycle, x0 at 0xC00.
#                                           CLAUDE.md has always claimed unimp
#                                           traps in this environment; today it
#                                           is a silent NOP.  This victim is
#                                           that claim, made testable in the
#                                           very build the claim is about.
#
# THE NEGATIVE HALF runs on HART 0 ITSELF, before any launch, and its proof is
#   LIVENESS: on a default build a wrongly-trapped instruction wedges hart 0
#   terminally, so if hart 0 reaches its verdict at all, none of the eight
#   negative encodings trapped.  Each one bumps a shared counter first, so a
#   wedged run can still be located precisely with a tcl probe of NEGPROG and
#   :dut:hart0:core:pc.  The eight (all unconditionally in csr_addr_valid on a
#   default build -- note mip 0x344 is deliberately ABSENT, it is an unknown
#   CSR without CORE_ENABLE_TRAPCSR and would trap for an unrelated reason):
#       f14022f3  csrr t0, mhartid        read of a READ-ONLY CSR
#       c0006373  csrrsi t1, cycle, 0     uimm FIELD 0 => not a write
#       f14073f3  csrrci t2, mhartid, 0   uimm FIELD 0 => not a write
#       32329073  csrw mhpmevent3, t0     0x323, WRITABLE quadrant
#       32029073  csrw mcountinhibit, t0  0x320, WARL-ignore
#       b0301073  csrw mhpmcounter3, x0   0xB03, WRITABLE quadrant
#       b0501073  csrw mhpmcounter5, x0   0xB05, dropped in BOTH ZIHPM
#                                         polarities -- still not F10
#       30129073  csrw misa, t0           0x301, WARL-ignore
#   Three of these (mhpmevent3, mhpmcounter3, mhpmcounter5) are VERBATIM from
#   the nine writes rv32ua-p-extzihpm executes on its default path.  Hart 0
#   surviving them IS the proof that the correctly-scoped F10 cannot move the
#   136/136 suite floor.
#
# ---------------------------------------------------------------------------
# VERDICT.  a0 = 0xCAFEBABE => F10 is FIXED, in the DEFAULT build, correctly
# scoped.  a0 = 0xDEADBEEF with:
#   a1 = 0xF10A0001   hart 1 executed PAST `csrw mhartid, t0`   <-- THE FINDING
#   a1 = 0xF10A0002   hart 2 executed PAST `unimp`              <-- THE FINDING
#   a1 = 0x5E1A0001   a negative-half READ returned the wrong value
#   a1 = 0x5E1A0002   a victim never armed: it did not reach the encoding
#   a1 = 0x5E1A0003   NEGPROG did not read back: shared RAM setup break
# NO a0 AT ALL (tb watchdog) is itself a result on a post-fix build: it means
#   hart 0 wedged inside its own negative half, i.e. THE FIX OVER-REACHES.
#   Probe NEGPROG (0x104F0) and :dut:hart0:core:pc to name the leg.
#
# NOT IN THE STANDING SUITE.  Post-fix both victims are parked in TRAP_STATE
#   forever and never write a0_1/a0_2; riscv_tb reports "tile hart(s)
#   silent/parked", a NOTE, not a failure.  Keep this file OUT of
#   xrun_parallel.sh's TEST_FILES array (floor stays 136); invoke it explicitly
#   with ./xrun_batch.sh xxxxrv32ua-p-rocsrwmp.
#
# SHARED WORDS CLAIMED (all < 0x10500 and inside the bootrom zero range):
#     0x104E8  PROG1    hart 1's progress
#     0x104EC  PROG2    hart 2's progress
#     0x104F0  NEGPROG  hart 0's negative-half counter
#   The band 0x104E8-0x104F4 is free at N=4 AND at N=18: below it shevfab's
#   WAKE tops out at 0x104E4 (its SRC is 0x104E0) and shafe's N=18 TURN at
#   0x104D0; above it the bootrom loader rows start at 0x10500.  Unlike the
#   W1/W3/W4 bands this one does not even overlap at N=18.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_PROG1    0x104E8
#define SH_PROG2    0x104EC
#define SH_NEGPROG  0x104F0

#define TILE_WORDS  1024        /* covers 0x8000-0x8FFF */
#define ARM_BUDGET  12000
#define WATCH_ITERS 4000

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

    li   s2, SH_PROG1
    li   s3, SH_PROG2
    li   s4, SH_NEGPROG
    li   s6, 0x5A5A5A5A             # a distinctive write source, never 0

    sw   x0, 0(s4)                  # NEGPROG starts clear
    li   s5, 0                      # ...and its register shadow

    .option push
    .option arch, +zicsr

    # ==================================================================
    # THE NEGATIVE HALF.  Proof is LIVENESS: on this build a wrongly
    # trapped instruction wedges hart 0 terminally and no a0 is ever
    # written.  NEGPROG makes a wedged run locatable.
    # ==================================================================
    .macro ROCA_OK enc
    .word \enc
    addi s5, s5, 1
    sw   s5, 0(s4)
    .endm

    mv   t0, s6
    ROCA_OK 0xF14022F3                  # csrr t0, mhartid
    li   a1, 0x5E1A0001
    bnez t0, rocmp_fail                 # hart 0 -> mhartid must read 0

    ROCA_OK 0xC0006373                  # csrrsi t1, cycle, 0
    li   a1, 0x5E1A0001
    beqz t1, rocmp_fail                 # cycle must be counting

    mv   t2, s6
    ROCA_OK 0xF14073F3                  # csrrci t2, mhartid, 0
    li   a1, 0x5E1A0001
    bnez t2, rocmp_fail

    mv   t0, s6
    ROCA_OK 0x32329073                  # csrw mhpmevent3, t0     (extzihpm)
    mv   t0, s6
    ROCA_OK 0x32029073                  # csrw mcountinhibit, t0
    ROCA_OK 0xB0301073                  # csrw mhpmcounter3, x0   (extzihpm)
    ROCA_OK 0xB0501073                  # csrw mhpmcounter5, x0   (extzihpm)
    mv   t0, s6
    ROCA_OK 0x30129073                  # csrw misa, t0

    .option pop

    li   a1, 0x5E1A0003
    lw   t1, 0(s4)
    li   t2, 8
    bne  t1, t2, rocmp_fail             # eight legs, all survived, all recorded

    # ==================================================================
    # arm the victims' progress words, then launch tiles 1 and 2
    # ==================================================================
    sw   x0, 0(s2)
    lw   t1, 0(s2)
    li   a1, 0x5E1A0003
    bnez t1, rocmp_fail
    sw   x0, 0(s3)
    lw   t1, 0(s3)
    bnez t1, rocmp_fail

    MP_STAGE_IMAGE(TILE_WORDS)
    MP_LAUNCH_HART(1, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(2, tile_entry, TILE_WORDS)

    # ==================================================================
    # wait (bounded) for BOTH victims to say they reached the encoding
    # ==================================================================
    li   t6, ARM_BUDGET
    li   t5, 1
arm_wait:
    lw   t2, 0(s2)
    blt  t2, t5, arm_next
    lw   t3, 0(s3)
    bge  t3, t5, armed
arm_next:
    addi t6, t6, -1
    bnez t6, arm_wait
    li   a1, 0x5E1A0002                 # a victim never reached the encoding
    j    rocmp_fail

armed:
    # ==================================================================
    # observe: neither victim may ever advance to 2
    # ==================================================================
    li   t6, WATCH_ITERS
    li   t5, 2
watch_loop:
    lw   t2, 0(s2)
    beq  t2, t5, rocmp_h1_ran
    lw   t3, 0(s3)
    beq  t3, t5, rocmp_h2_ran
    addi t6, t6, -1
    bnez t6, watch_loop

    RVTEST_PASS                         # a0 = 0xCAFEBABE

rocmp_h1_ran:
    li   a1, 0xF10A0001                 # csrw mhartid, t0 did not trap
    j    rocmp_fail
rocmp_h2_ran:
    li   a1, 0xF10A0002                 # unimp did not trap
rocmp_fail:
    RVTEST_FAIL                         # a0 = 0xDEADBEEF

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
tile_park:
    j    tile_park

tile_h1:
    li   t0, SH_PROG1
    li   t1, 1
    sw   t1, 0(t0)                      # armed: about to execute the encoding
    .word 0xF1429073                    # csrw mhartid, t0  -- MUST TRAP
    addi t1, x0, 2                      # never a store: F8 cannot fire here
    sw   t1, 0(t0)                      # reached ONLY if it did NOT trap
tile_h1_park:
    j    tile_h1_park

tile_h2:
    li   t0, SH_PROG2
    li   t1, 1
    sw   t1, 0(t0)                      # armed
    .word 0xC0001073                    # unimp = csrrw x0,cycle,x0 -- MUST TRAP
    addi t1, x0, 2                      # never a store: F8 cannot fire here
    sw   t1, 0(t0)                      # reached ONLY if it did NOT trap
tile_h2_park:
    j    tile_h2_park

    # NOTE: RVTEST_CODE_END is 'unimp' in this env -- never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
