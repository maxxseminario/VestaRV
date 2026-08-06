# See LICENSE for license details.

#*****************************************************************************
# dbgdenymp.S   (D-series, D1 -- the IN-BAND, PORT-FREE debug detector)
#-----------------------------------------------------------------------------
# BLIND-AUTHORED against d1_spec.md sections 1-2, FROZEN 2026-08-05, by an agent
# that has not seen and will never see the D1 implementation.  Committed
# polarity: CORRECT RTL = PASS (R-K5-8).  This file must PASS on the tree as it
# stands today (no debug RTL at all) and must go on passing after D1 lands, in
# BOTH knob polarities.  That is not a weakness -- see "WHAT MAKES A
# BOTH-POLARITY TEST WORTH ITS SLOT" below.
#
# WHAT IT COVERS, and why none of it needs a port
#   d1_spec.md section 5's minimum instrument set contains three items that are
#   SOFTWARE-visible with no debug-module, no halt request and no testbench
#   surgery whatsoever:
#       * the 0x7Bx CSR block must trap from M-mode, in BOTH knob polarities
#       * `dret` outside debug mode must be an illegal instruction
#       * `ebreak` with dcsr.ebreakm = 0 must NOT enter debug mode
#   and one that is best expressed here as a standing negative:
#       * NOTHING may reach DEBUG_ENTRY_ADDR unless a debugger asked
#   All four are checked below.  Because nothing here forces a signal, this is
#   the only D1 instrument that can join the standing lists.
#
# WHAT MAKES A BOTH-POLARITY TEST WORTH ITS SLOT (the R-ID0-1 lesson, applied)
#   A test that passes before and after the change under test proves nothing by
#   passing -- unless it can be shown to be LIVE.  Two devices do that here:
#     1. THE WRITE-FORM CONTROL ON AN ADDRESS LEGAL TODAY.  Hart 0 executes
#        `csrw misa, t0` (0x30129073).  0x301 is the FIRST term of maindec's
#        csr_addr_valid and carries no ENABLE_ qualifier (checked in the tree,
#        not assumed), it is in the WRITABLE quadrant (bits 11:10 = "01") so
#        csr_ro_denied cannot reach it, and its csr_unit arm is WARL-ignore.
#        It must RETIRE on all 28 matrix rows, today and forever.  If a D1
#        decode change spills outside 0x7Bx, this is what catches it, and a
#        hart-0 wedge here is unmissable (a default build's TRAP_STATE is
#        terminal, so hart 0 stops writing a0 at all).
#     2. THE THREE VICTIMS ARE OBSERVED, NOT ASSUMED.  Each publishes a stepped
#        PROGRESS word and hart 0 asserts each one STOPS at its expected value
#        AND STAYS there.  A victim that never armed is a distinct verdict code
#        from a victim that advanced too far.
#
# THE DEBUG-ENTRY TRIPWIRE -- the part of this file that is a real detector
#   HART 0 plants a short stub at DEBUG_ENTRY_ADDR -- since 2026-08-05 in the
#   SHARED window, so one plant covers every hart -- before it launches
#   anybody.  The stub
#   writes a hart-identifying magic into the shared word DBGMARK and spins.
#   Today the stub is dead code: nothing ever jumps to DEBUG_ENTRY_ADDR,
#   because there is no debug mode.  After D1 it is STILL dead code on a
#   correct build -- no halt request exists in this test, and dcsr.ebreakm
#   RESETS TO 0, so `ebreak` must take an ordinary breakpoint exception.
#   DBGMARK becoming nonzero therefore means exactly one thing: A HART ENTERED
#   DEBUG MODE WITH NOBODY ASKING.  The three implementation mistakes it
#   catches, none of which any other D1 instrument sees:
#       * `ebreak` routed to debug entry regardless of dcsr.ebreakm
#       * a 0x7Bx access from M-mode routed to debug entry instead of trapping
#       * `dret` outside debug mode implemented as a jump to DEBUG_ENTRY_ADDR
#   and the magic NAMES the hart, so the verdict says which encoding did it.
#
#   The stub is planted by COPYING, not by a linker section, deliberately: a
#   new section in verification/env/p/link.ld changes build/.imgset and wipes
#   the whole build tree for every suite (CLAUDE.md), and this instrument is
#   not worth that.  The stub therefore contains no PC-relative reference to
#   anything outside itself; its one internal branch is a self-loop, whose
#   offset is relocation-invariant.  Since the 2026-08-05 migration the
#   destination is the SHARED window, so ONE plant by hart 0 serves every
#   hart and the victims plant nothing.
#
# DEBUG_ENTRY_ADDR = 0x10780 -- MIGRATED 2026-08-05 FROM TCM 0xBE00.
#   D1 froze DEBUG_ENTRY_ADDR at 0xBE00, inside this hart's PRIVATE TCM
#   (R-D1-1(2), on this file's own memory-map argument).  D2's probe then
#   proved, four independent ways, that a tile's TCM is UNREACHABLE from the
#   shared bus -- no slave port, no second RAM port, the arbiter's default arm
#   literally commented "no slave (TCM page, unmapped)".  A Debug Module
#   therefore CANNOT place code at 0xBE00, and an abstract command is a
#   code-execution mechanism; so R-DD3 moved debug entry into the shared
#   window and R-D2-1(3) set it to 0x10780 for every debug-ON build.
#
#   WHAT CHANGED HERE, and what did not.  The stub is still planted by
#   COOPERATING FIRMWARE with an ordinary store loop -- shared RAM is writable
#   by this test exactly as the TCM was, the plant happens after boot and
#   inside the bootrom's zero range, and no linker section is added (a new
#   section changes build/.imgset and wipes every rv32ua image).  What DID
#   change is that the entry page is now GLOBAL rather than per-hart, so
#   HART 0 PLANTS IT ONCE before it launches anybody, instead of every hart
#   planting its own private copy.  That is strictly stronger for this file's
#   purpose: the tripwire is in place before any victim exists, so no hart can
#   reach a must-trap encoding untripwired -- which is what the old
#   plant-before-your-primary discipline was for.
#
#   EXECUTION FROM SHARED IS PROVEN, NOT ASSUMED: shexec.S is the M10
#   instrument for it (a payload fetched from the shared window, with a
#   backward branch inside it), and all four harts already reset-fetch the
#   shared boot ROM.  The constraint that comes with it is `.option norvc`,
#   which this file already sets: compressed/misaligned execution from shared
#   is UNTESTED (CLAUDE.md's shexec bullet).
#
#   IF THE RULING MOVES AGAIN, one #define changes here, one in dbghaltmp.S,
#   one in dbgstepmp.S and one `set DBG_ENTRY` in dbg_rst.tcl -- that fourth
#   site is easy to miss and is named here for that reason.
#
# THE SLOT ARGUMENT (the idcsrmp construction; read before "simplifying")
#   A must-trap encoding CONSUMES a victim: on the shipped default a trap lands
#   in the TERMINAL TRAP_STATE, so the victim never reaches anything placed
#   after it.  Six must-trap encodings are wanted and only three victims exist
#   at N=4, and hart 0 can take none of them (a trap there wedges the verdict).
#   Placement, one PRIMARY per victim and the rest chained behind it:
#       hart 1  csrr dcsr (0x7B0)   PRIMARY -- the block's first address
#               chained: 0x7B1, 0x7B2, 0x7B3, then a WRITE FORM at 0x7B0
#       hart 2  dret outside debug  PRIMARY -- d1_spec.md section 2's last clause
#               chained: 0x7B4, the over-wide-HIGH guard
#       hart 3  ebreak              PRIMARY -- the dcsr.ebreakm = 0 polarity
#               chained: 0x7AF, the over-wide-LOW guard
#   The chained assertions are live only in an already-broken world.  They are
#   kept because each still CLASSIFIES the breakage: hart 1 reaching PROG 5
#   says "the whole 0x7Bx block was admitted for reads", PROG 6 adds "and the
#   write form too", and the two guards separate a correct four-equality decode
#   from a 0x7Bx nibble range or a sloppy 0x7Ax..0x7Bx interval.
#   RESIDUAL, stated rather than hidden: with three victims, a fix that admits
#   exactly one of 0x7B1/0x7B2/0x7B3 and not 0x7B0 is invisible here.  No
#   arrangement of three victims covers all six encodings independently.
#
# WHY `dret` IS ONLY PARTLY OBSERVABLE HERE, stated as a miss and not papered
# over.  Hart 2's assertion is "the instruction after the dret is not reached".
# That catches the natural wrong implementation -- a `dret` admitted by the
# decoder and then executed as a NOP, which is what a half-finished FSM arm
# looks like.  It does NOT catch a `dret` that executes and JUMPS to dpc: dpc
# resets to something the test cannot set (0x7B1 is denied outside debug), the
# hart lands somewhere it cannot report from, and PROG stops at 1 exactly as it
# does when the dret traps.  The DBGMARK tripwire covers the sub-case where dpc
# happens to be DEBUG_ENTRY_ADDR.  The full `dret` semantics are dbgstepmp.S's,
# which reaches debug mode and can write dpc.
#
# KNOB-INDEPENDENT BY CONSTRUCTION, which is what an untagged CATALOG row has
# to be (R-ID0-3).  Everything hart 0 executes -- base ISA, `csrr mhartid`,
# `csrw misa`, `csrr misa`, plain loads and stores, MP_STAGE_IMAGE and
# MP_LAUNCH_HART -- is legal on all 28 matrix rows including castalia_notrapcsr.
# Nothing here reads a counter, an FP CSR or a trap CSR.  The victims' primaries
# trap in every polarity: 0x7Bx is not in csr_addr_valid on ANY row today;
# `dret`'s funct12 is not one of the four the SYSTEM PRIV arm admits; and
# `ebreak` is legal-but-trapping when trapCsr is on and illegal-and-trapping
# when it is off -- the same observable either way.
#
# N-AGNOSTIC.  Exactly three victims are launched at any NHARTS; on an Argus
# N=18 build harts 4-17 stay parked in the bootrom (riscv_tb reports a NOTE).
# No shared word here is indexed by hartid.
#
# ---------------------------------------------------------------------------
# VERDICT.  a0 = 0xCAFEBABE => the 0x7Bx block, `dret` and `ebreak` all still
# trap from M-mode; no hart reached DEBUG_ENTRY_ADDR; and the legal-today
# control still retires.  a0 = 0xDEADBEEF with:
#   a1 = 0x0DB60001   a victim never armed          (a2 = SUBJ, a3 = W*16+G)
#   a1 = 0x0DB60002   a shared word did not read back: shared-RAM setup break
#   a1 = 0x0DB60003   base-ISA sanity failed
#   a1 = 0x0DB60004   a positive-half leg returned the wrong value
#   a1 = 0x0DB60005   POSPROG did not count every positive leg
#   a1 = 0x0D7B0000   hart 1 advanced past PROG 1: 0x7B0 was ADMITTED for read
#                     (a2 = SUBJPROG names how far: 2/3/4 = 0x7B1/0x7B2/0x7B3
#                     also admitted, 5 = the whole block, 6 = the WRITE FORM too)
#   a1 = 0x0D7B00D6   hart 2 advanced past PROG 1: `dret` DID NOT TRAP outside
#                     debug mode        (a2 = 2 -> also 0x7B4 admitted, over-wide HIGH)
#   a1 = 0x0D7B00EB   hart 3 advanced past PROG 1: `ebreak` did not trap
#                     (a2 = 2 -> also 0x7AF admitted, over-wide LOW)
#   a1 = 0x0DB6DEB6   DBGMARK is nonzero: A HART ENTERED DEBUG MODE UNASKED
#                     (a2 = the magic: 0xD0B00001/2/3 names the hart, 0xD0B00000
#                     is hart 0 -- and hart 0 entering debug means the verdict
#                     path itself ran in debug mode)
# NO a0 AT ALL (tb watchdog) is itself a result: hart 0 wedged inside its own
#   positive half, i.e. a D1 decode change made a legal M-mode CSR access
#   illegal.  Probe POSPROG (0x1005C) and :dut:hart0:core:pc to name the leg.
#
# THE THREE NEGATIVE CONTROLS -- how this file was SEEN TO FAIL.
#   A both-polarity detector passes at unimplemented HEAD by construction, so
#   its seen-to-FAIL leg (d1_spec.md section 5 part 1) cannot be a HEAD run.
#   These three build-time arms produce it instead, with no RTL change at all:
#   each removes exactly ONE assertion's subject and nothing else, so the run
#   that follows exercises the detector's failure path end to end.
#       -DDBGDENY_NC_7B0    hart 1's `csrr dcsr` becomes a nop.  It walks to
#                           PROG 2 and wedges on 0x7B1 instead.  Expected
#                           verdict: a0 = 0xDEADBEEF, a1 = 0x0D7B0000, a2 = 2.
#       -DDBGDENY_NC_DRET   hart 2's `dret` becomes a nop -- literally the
#                           "admitted and executed as a NOP" implementation
#                           this instrument exists to catch.  Expected:
#                           a1 = 0x0D7B00D6, a2 = 2.
#       -DDBGDENY_NC_MARK   hart 3 jumps to DEBUG_ENTRY_ADDR instead of
#                           executing `ebreak`, i.e. it does exactly what an
#                           ebreakm-ignoring implementation would do to it.
#                           Expected: a1 = 0x0DB6DEB6, a2 = 0xD0B00003.
#   Build them out of tree (the .imgset wipe is shared state):
#       ./tools/build_one_rcf.sh tests/rv32ua/dbgdenymp.S rv32ua-p-ddnc7b0 -DDBGDENY_NC_7B0
#   They are CONTROLS, not detectors: they make no claim about the RTL.
#
# STAGED, NOT IN ANY STANDING LIST.  Entry into xrun_parallel.sh's TEST_FILES
#   and into the verify_stage.py CATALOG is a deliberate re-pin (suite 142 ->
#   143, Argus 143 -> 144, D2 canary 68 -> 69) and belongs to whoever validates
#   D1, not to this file.  Invoke explicitly:
#       ./xrun_batch.sh rv32ua-p-dbgdenymp
#   Post-D1 all three tiles are parked in TRAP_STATE forever and never write
#   a0_1/a0_2/a0_3; riscv_tb reports "tile hart(s) silent/parked", a NOTE
#   (the trapstor/idcsrmp precedent).
#
# SHARED WORDS CLAIMED (all < 0x10500, inside the bootrom zero range):
#     0x10050  SUBJPROG  hart 1's stepped progress word
#     0x10054  WPROG     hart 2's stepped progress word
#     0x10058  GPROG     hart 3's stepped progress word
#     0x1005C  POSPROG   hart 0's positive-half leg counter
#     0x10060  DBGMARK   the debug-entry tripwire (must stay 0)
#   Plus, since the 2026-08-05 migration, the SHARED DEBUG ENTRY PAGE at
#   0x10780-0x1087F (d2_spec section 1 as amended by R-D2-2(3)), where the
#   tripwire stub is planted.  This file's stub is 7 words.
#   These five data words sit inside the 12-word D1 band 0x10050-0x1007C in
#   CLAUDE.md's ledger for the three D1 debug tests jointly; the band is
#   REUSED with different meanings by dbghaltmp.S and dbgstepmp.S, which is
#   safe for the same reason shdma and wdma share theirs -- one image per sim,
#   the three never coexist.  At N=4 the band is free: shlrsc's tile hammer
#   array tops out at 0x1004C below it and shmem_mp/shcount's atomic counter
#   is at 0x10080 above it.  At N=18 shlrsc's hammer reaches 0x10084 and the
#   band overlaps it -- benign by the ledger's isolation rule, and stated here
#   rather than left for the next reader to discover.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_SUBJPROG  0x10050
#define SH_WPROG     0x10054
#define SH_GPROG     0x10058
#define SH_POSPROG   0x1005C
#define SH_DBGMARK   0x10060

/* R-D2-1(3): the debug entry page in the SHARED window.  See the header for
   why it moved off the TCM and what else changes if the ruling moves again.
   The 7-word tripwire stub fits inside the 64-word entry page
   0x10780-0x1087F (R-D2-2(3)) many times over.                                      */
#define DBG_ENTRY    0x10780

/* 1024 words = 0x8000-0x8FFF, which covers the IVT and the whole image (the
   linked size is ~0x87D0).  The debug stub does NOT ride the staged copy at
   all any more: since the migration it lives in the SHARED window and hart 0
   plants it once.  A full-TCM 4096-word stage would add ~7 ms of serialized
   arbiter traffic for nothing.                                             */
#define TILE_WORDS   1024
#define ARM_BUDGET   12000
#define WATCH_ITERS  4000

/* Every encoding under test is a raw .word so gas cannot rewrite it and so the
   file does not depend on gas's CSR name table.  All eight were verified with
   riscv-none-elf-as + objdump before the first build.                       */
#define CSRR_S0_7B0   0x7B002473    /* csrrs s0, 0x7B0, x0   dcsr       */
#define CSRR_S1_7B1   0x7B1024F3    /* csrrs s1, 0x7B1, x0   dpc        */
#define CSRR_S2_7B2   0x7B202973    /* csrrs s2, 0x7B2, x0   dscratch0  */
#define CSRR_S3_7B3   0x7B3029F3    /* csrrs s3, 0x7B3, x0   dscratch1  */
#define CSRR_S4_7B4   0x7B402A73    /* csrrs s4, 0x7B4, x0   unallocated ABOVE */
#define CSRR_S5_7AF   0x7AF02AF3    /* csrrs s5, 0x7AF, x0   unallocated BELOW */
#define CSRW_7B0_T0   0x7B029073    /* csrrw x0,  0x7B0, t0   write form */
#define DRET_INSN     0x7B200073    /* dret                             */
#define EBREAK_INSN   0x00100073    /* ebreak                           */
#define CSRW_MISA_T0  0x30129073    /* csrrw x0,  0x301, t0   LEGAL TODAY */
#define CSRR_T1_MISA  0x30102373    /* csrrs t1,  0x301, x0   LEGAL TODAY */
#define CSRR_T0_F14   0xF14022F3    /* csrrs t0,  0xF14, x0   mhartid    */

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry            # only hart 0 orchestrates

    li   s2, SH_SUBJPROG
    li   s3, SH_WPROG
    li   s4, SH_GPROG
    li   s5, SH_POSPROG
    li   s6, SH_DBGMARK

    # ==================================================================
    # clear every claimed word and prove it read back
    # ==================================================================
    li   a1, 0x0DB60002
    sw   x0, 0(s2)
    lw   t1, 0(s2)
    bnez t1, dd_fail
    sw   x0, 0(s3)
    lw   t1, 0(s3)
    bnez t1, dd_fail
    sw   x0, 0(s4)
    lw   t1, 0(s4)
    bnez t1, dd_fail
    sw   x0, 0(s5)
    lw   t1, 0(s5)
    bnez t1, dd_fail
    sw   x0, 0(s6)
    lw   t1, 0(s6)
    bnez t1, dd_fail

    # THE PLANT.  Since the migration to the shared window the entry page is
    # GLOBAL: hart 0 plants it once, here, before anything else and long
    # before any victim exists.  It covers the orchestrator too -- if hart 0
    # itself enters debug mode the verdict path is running in debug mode, and
    # that has to be visible.
    jal  ra, dd_plant

    li   s7, 0                      # POSPROG register shadow

    # ==================================================================
    # THE POSITIVE HALF.  Four legs, every one unconditionally legal on
    # every matrix row.  Proof is LIVENESS (a wrongly-trapped instruction
    # wedges hart 0 terminally) plus the asserted values.
    # ==================================================================
    .macro DD_OK
    addi s7, s7, 1
    sw   s7, 0(s5)
    .endm

    li   t0, 1234                   # P0: base ISA sanity
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    DD_OK
    li   a1, 0x0DB60003
    bne  t2, t3, dd_fail

    li   t0, 0x5A5A5A5A             # P1: csrr t0, mhartid -- must read 0
    .word CSRR_T0_F14
    DD_OK
    li   a1, 0x0DB60004
    bnez t0, dd_fail

    li   t0, 0x5A5A5A5A             # P2: THE WRITE-FORM CONTROL.
    .word CSRW_MISA_T0              #     csrw misa, t0 -- writable quadrant,
    DD_OK                           #     WARL-ignore, must RETIRE forever
    li   a1, 0x0DB60004
    li   t1, 0
    .word CSRR_T1_MISA              # P3: csrr t1, misa -- must retire nonzero
    DD_OK
    beqz t1, dd_fail                #     (and prove P2 left no damage)

    lw   t1, 0(s5)
    li   t2, 4
    li   a1, 0x0DB60005
    bne  t1, t2, dd_fail            # four legs, all survived, all recorded

    # ==================================================================
    # launch the three victims
    # ==================================================================
    MP_STAGE_IMAGE(TILE_WORDS)
    MP_LAUNCH_HART(1, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(2, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(3, tile_entry, TILE_WORDS)

    # ==================================================================
    # bounded wait for every victim to reach its EXPECTED terminal state.
    # All three expect PROG = 1: each victim's PRIMARY encoding is its
    # first, and it must trap.
    # ==================================================================
    li   s8, 1
    li   t6, ARM_BUDGET
dd_wait:
    lw   t2, 0(s2)
    blt  t2, s8, dd_wait_next
    lw   t3, 0(s3)
    blt  t3, s8, dd_wait_next
    lw   t4, 0(s4)
    bge  t4, s8, dd_armed
dd_wait_next:
    addi t6, t6, -1
    bnez t6, dd_wait

    lw   a2, 0(s2)
    lw   t3, 0(s3)
    lw   t4, 0(s4)
    slli a3, t3, 4
    add  a3, a3, t4
    li   a1, 0x0DB60001
    j    dd_fail

dd_armed:
    # ==================================================================
    # observe: no victim may advance past PROG = 1, ever
    # ==================================================================
    li   t6, WATCH_ITERS
dd_watch:
    lw   t2, 0(s2)
    bne  t2, s8, dd_subj_over
    lw   t3, 0(s3)
    bne  t3, s8, dd_wctl_over
    lw   t4, 0(s4)
    bne  t4, s8, dd_guard_over
    lw   t5, 0(s6)
    bnez t5, dd_mark_set            # THE TRIPWIRE, sampled every round
    addi t6, t6, -1
    bnez t6, dd_watch

    # ==================================================================
    # final tripwire read, and the verdict
    # ==================================================================
    lw   t5, 0(s6)
    bnez t5, dd_mark_set

    RVTEST_PASS                     # a0 = 0xCAFEBABE

dd_subj_over:
    mv   a2, t2
    li   a1, 0x0D7B0000             # 0x7B0 admitted for read (a2 says how far)
    j    dd_fail
dd_wctl_over:
    mv   a2, t3
    li   a1, 0x0D7B00D6             # dret did not trap outside debug mode
    j    dd_fail
dd_guard_over:
    mv   a2, t4
    li   a1, 0x0D7B00EB             # ebreak did not trap with ebreakm = 0
    j    dd_fail
dd_mark_set:
    mv   a2, t5
    li   a1, 0x0DB6DEB6             # a hart entered debug mode unasked
dd_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    # =====================================================================
    # dd_plant -- copy the tripwire stub to DEBUG_ENTRY_ADDR in the SHARED
    # window.  No arguments: the stub identifies its own hart by reading
    # mhartid, so ONE copy serves all four.  Clobbers t0-t3.
    # MIGRATION NOTE (2026-08-05): the entry page is now global, so this is
    # called ONCE, by hart 0, BEFORE any victim is launched.  The victims no
    # longer plant -- there is nothing per-hart left to plant -- and the
    # tripwire is in place strictly earlier than it used to be.
    # =====================================================================
dd_plant:
    la   t0, dd_stub_start
    la   t1, dd_stub_end
    li   t2, DBG_ENTRY
1:  lw   t3, 0(t0)
    sw   t3, 0(t2)
    addi t0, t0, 4
    addi t2, t2, 4
    blt  t0, t1, 1b
    ret

    # ---- THE TRIPWIRE STUB.  Copied verbatim to DEBUG_ENTRY_ADDR. --------
    # RELOCATION RULES obeyed here: no `la`, no `auipc`, no branch or jump
    # whose target lies outside this block.  The one branch is a self-loop,
    # whose offset is the same wherever the block lands.  `li` of an absolute
    # constant and `csrr` of an absolute CSR number are both position-free.
    # It reads mhartid so ONE copy serves all four harts.  NO .align here:
    # `.balign`/`.align` are silent no-ops inside a `.option norvc` region
    # (CLAUDE.md), and every instruction in this file is 4 bytes anyway, so
    # the block is word-aligned by construction.
dd_stub_start:
    .option push
    .option arch, +zicsr
    csrr a4, mhartid
    .option pop
    li   a3, 0xD0B00000
    add  a4, a4, a3                 # 0xD0B0000h -- names the hart
    li   a3, SH_DBGMARK
    sw   a4, 0(a3)
2:  j    2b
dd_stub_end:

    # ---- tile harts enter here (loader ABI: only sp is defined) ----------
tile_entry:
    li   sp, 0xBFF0
    # No plant here since the migration: the entry page is SHARED and hart 0
    # planted it before this hart was launched.  (Planting again would be
    # harmless -- identical bytes -- but it would suggest the page were
    # per-hart, which is exactly the misreading the migration exists to end.)
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

    # ---- hart 1: THE 0x7Bx READ BLOCK -----------------------------------
    # The instruction immediately after every encoding under test is an
    # `addi`, never a store, so F8 (TRAP_STATE decoding and committing the
    # word at pc_next_trad_reg) cannot fire on any of them.
tile_h1:
    li   t0, SH_SUBJPROG
    li   t1, 1
    sw   t1, 0(t0)                  # PROG=1: about to read dcsr -- TERMINAL
#ifdef DBGDENY_NC_7B0
    nop                             # NEGATIVE CONTROL: the primary is removed
#else
    .word CSRR_S0_7B0               # 0x7B0 -- MUST TRAP from M-mode
#endif
    addi t1, x0, 2
    sw   t1, 0(t0)                  # PROG=2: reached only if 0x7B0 admitted
    .word CSRR_S1_7B1               # 0x7B1 -- chained
    addi t1, x0, 3
    sw   t1, 0(t0)
    .word CSRR_S2_7B2               # 0x7B2 -- chained
    addi t1, x0, 4
    sw   t1, 0(t0)
    .word CSRR_S3_7B3               # 0x7B3 -- chained
    addi t1, x0, 5
    sw   t1, 0(t0)                  # PROG=5: the whole block admitted for read
    .word CSRW_7B0_T0               # a WRITE FORM at 0x7B0 -- chained
    addi t1, x0, 6
    sw   t1, 0(t0)                  # PROG=6: the write form retired too
tile_h1_park:
    j    tile_h1_park

    # ---- hart 2: `dret` OUTSIDE DEBUG MODE ------------------------------
tile_h2:
    li   t0, SH_WPROG
    li   t1, 1
    sw   t1, 0(t0)                  # PROG=1: about to execute dret -- TERMINAL
#ifdef DBGDENY_NC_DRET
    nop                             # NEGATIVE CONTROL: the primary is removed
#else
    .word DRET_INSN                 # MUST be illegal-instruction outside debug
#endif
    addi t1, x0, 2
    sw   t1, 0(t0)                  # PROG=2: the dret RETIRED (or NOP'd)
    .word CSRR_S4_7B4               # 0x7B4 -- over-wide-HIGH guard, chained
    addi t1, x0, 3
    sw   t1, 0(t0)                  # PROG=3: 0x7B4 admitted too
tile_h2_park:
    j    tile_h2_park

    # ---- hart 3: `ebreak` WITH dcsr.ebreakm = 0 -------------------------
    # d1_spec.md section 1: dcsr.ebreakm is a debug-mode-only field and RESETS
    # TO 0, so no M-mode software can ever set it.  `ebreak` must therefore
    # take an ordinary breakpoint exception (cause 3) -- terminal TRAP_STATE on
    # the shipped default -- and must NOT reach DEBUG_ENTRY_ADDR.  On the
    # trapCsr-OFF row `ebreak` is an illegal instruction instead: the same
    # observable, which is what keeps this leg row-independent.
tile_h3:
    li   t0, SH_GPROG
    li   t1, 1
    sw   t1, 0(t0)                  # PROG=1: about to ebreak -- TERMINAL
#ifdef DBGDENY_NC_MARK
    li   t2, DBG_ENTRY              # NEGATIVE CONTROL: jump to the debug entry
    jalr x0, t2, 0                  # vector as a spontaneous debug entry would
#else
    .word EBREAK_INSN               # MUST NOT enter debug mode
#endif
    addi t1, x0, 2
    sw   t1, 0(t0)                  # PROG=2: the ebreak did not trap at all
    .word CSRR_S5_7AF               # 0x7AF -- over-wide-LOW guard, chained
    addi t1, x0, 3
    sw   t1, 0(t0)                  # PROG=3: 0x7AF admitted too
tile_h3_park:
    j    tile_h3_park

    # NOTE: RVTEST_CODE_END is `unimp` in this env (it traps) -- never fall
    # through; every hart-0 path above ends in a spin and every tile path ends
    # in an unconditional jump.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
