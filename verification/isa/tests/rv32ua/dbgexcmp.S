# See LICENSE for license details.

#*****************************************************************************
# dbgexcmp.S   (D-series, D2 -- F-D2-0: A SYNCHRONOUS EXCEPTION TAKEN IN DEBUG
#               MODE MUST RE-ENTER DEBUG MODE, IN BOTH DELIVERY POLARITIES)
#-----------------------------------------------------------------------------
# BLIND-AUTHORED 2026-08-06 against the F-D2-0 contract statement only, by an
# agent that has not seen and will never see the implementer's fix (R-D2-3(5)
# bars the author from d2_implementation_report.md; the wall runs both ways for
# this finding).  Committed polarity: CORRECT RTL = PASS (R-K5-8).
#
# NEEDS A HARNESS:  ./xrun_dbg.sh rv32ua-p-dbgexcmp dbg_exc.tcl
# No Debug Module is required and none exists: the harness forces the tile's
# `dbg_haltreq` port directly, the D1 mechanism, so this detector lives on the
# debug row's instrument set from today and does not wait for D2's DM.
#
# ---------------------------------------------------------------------------
# THE CONTRACT, and the four separate ways to break it
#   A hart that takes a synchronous exception WHILE IN DEBUG MODE must
#   re-enter debug mode at DEBUG_ENTRY_ADDR with `dpc` and `dcsr` UNCHANGED.
#   It must not enter TRAP_STATE, must not latch `trap_flag`, must not clobber
#   `mepc`/`mcause`, and must come out able to run and be halted again.
#   Those are four different pieces of RTL and a build can get any one of them
#   wrong on its own, so each has its own verdict code.
#
#   BOTH DELIVERY POLARITIES ARE EXERCISED, on two victims, because the two
#   fail DIFFERENTLY and a detector that only ran one of them would report a
#   green half as if it were the whole:
#     hart 1  LEGACY delivery (mtrapctl.LEGACY = 1, the RESET configuration
#             every hart boots in).  A wrong build takes the ordinary trap
#             path; on the shipped default that is the TERMINAL TRAP_STATE, so
#             the failure is a WEDGE and its in-band signature is a missing
#             second entry.  There is no positive tripwire available on this
#             path -- an illegal instruction in legacy mode does not reach an
#             IVT slot -- so the harness's cpu_state read is what names it.
#     hart 2  STANDARD delivery (the hart executes `csrw 0x7C0, x0` first).  A
#             wrong build vectors to `mtvec`, and THAT one can be caught
#             positively: this hart points mtvec at a TRIPWIRE that publishes
#             a magic and spins.  If the tripwire ever fires, standard
#             delivery took an exception away from a hart that was in debug
#             mode, and the verdict names it outright instead of reporting a
#             timeout.
#     hart 3  BYSTANDER.  It only counts.  If a fault on one hart takes the
#             chip down, its counter stops and that is a separate code.
#
# THE EXCEPTION IS AN ILLEGAL INSTRUCTION, NOT AN `ebreak`, ON PURPOSE.
#   `ebreak` in debug mode is the one re-entry d1_spec already defines and
#   dbgstepmp already covers, so using it here would test the covered path.
#   `.word 0x0000007F` is absent from maindec's valid_opcode list on EVERY
#   build -- the same positive control rocsrw.S and dbghaltmp.S use -- so it
#   is a synchronous exception on every matrix row and needs no knob.
#
# WHY dpc/dcsr MUST BE UNCHANGED, and how that is read
#   The re-entry is not a new debug entry: the hart is already in debug mode
#   and `dpc`/`dcsr` still describe the ORIGINAL entry.  A build that rewrites
#   them has destroyed the debugger's resume address -- the hart would `dret`
#   into the middle of its own debug stub.  So the stub records dpc/dcsr on
#   entry 1 and again on entry 2, and hart 0 compares them.  The assertion is
#   an EQUALITY between two measured values, not a comparison against a
#   constant anyone calibrated (method rule 7).
#
# mepc IS SEEDED WITH A MAGIC BEFORE THE PARK, deliberately.  Comparing
#   mepc-before against mepc-after would pass on a build that zeroes it twice.
#   Seeding it with 0x0D26E9C0 means a clobber to the fault PC, to zero, or to
#   anything else is visible in the verdict's a2.  mcause is recorded rather
#   than seeded (it is the trap unit's to write, and inventing a required
#   value for it would be testing the invention).
#
# ---------------------------------------------------------------------------
# VERDICT.  a0 = 0xCAFEBABE => an exception in debug mode re-entered debug mode
# on BOTH delivery polarities, with dpc, dcsr, mepc and mcause all intact, and
# both victims came back out and ran.  a0 = 0xDEADBEEF with:
#   a1 = 0x0D260001   a shared word did not read back
#   a1 = 0x0D260002   base-ISA sanity failed
#   a1 = 0x0D260003   a victim never published READY (a2 = the hart index)
#   a1 = 0x0D26h005   THE STD TRIPWIRE FIRED on hart h (a2 = TRIP): standard
#                     delivery vectored an exception to mtvec while the hart
#                     was in debug mode.  The positive form of the finding.
#   a1 = 0x0D26h004   hart h NEVER RE-ENTERED debug mode after the exception
#                     (a2 = ENTRIES[h], 1 = it entered once and never came
#                     back).  On the legacy polarity this is the finding, and
#                     the harness's EXCLOG lines say whether the hart is
#                     wedged in TRAP_STATE or parked with dbg_halted still
#                     asserted (the unrecoverable-park class).
#   a1 = 0x0D26h006   dpc CHANGED across the re-entry (a2 = DPC2, a3 = DPC1)
#   a1 = 0x0D26h007   dcsr CHANGED across the re-entry (a2 = DCSR2, a3 = DCSR1)
#   a1 = 0x0D26h008   mepc was CLOBBERED (a2 = MEPC2, a3 = MEPC1)
#   a1 = 0x0D26h009   mcause was CLOBBERED (a2 = MCAUSE2, a3 = MCAUSE1)
#   a1 = 0x0D26h00A   hart h never resumed after its `dret` (a2 = POST)
#   a1 = 0x0D26000B   the BYSTANDER stopped counting (a2 = CNT[3]): the fault
#                     did not stay on the victims
# NO a0 AT ALL (tb watchdog): hart 0 wedged in its own preamble.
#
# NEGATIVE CONTROL -- how the non-debug half was SEEN TO WORK:
#   -DDBGEXC_NC_SELFENTRY.  Each victim JUMPS to its own planted stub instead
#   of waiting to be halted, and the stub publishes CONSTANTS shaped exactly
#   like the real thing (a synthetic dcsr/dpc) and skips both the debug-CSR
#   reads and the fault, so it runs on a tree with no debug mode at all.  The
#   planting, the hartid dispatch, both polarities' setup, every publish, both
#   victims' resume, hart 0's whole assertion chain and the verdict path all
#   execute for real.  A PASS on that arm proves the instrument is LIVE and
#   that a later FAIL is about the RTL, not about the plumbing (method rule 5).
#   It is a CONTROL: it makes no claim about debug mode and must never be
#   quoted as a D2 result.
#
# WHERE THE STUB IS PLANTED, and why in TWO places
#   DEBUG_ENTRY_ADDR is the VHDL generic default 0xBE00 on the tree as it
#   stands, and becomes shared 0x10780 when the generator's debug-ON emission
#   lands (R-D2-1(3)).  This detector must work on BOTH trees -- it is the
#   FAIL leg today and the PASS leg after the fix -- so it plants the same
#   position-independent stub at BOTH addresses: hart 0 plants the shared copy
#   once, and every victim plants its own private-TCM copy.  Whichever address
#   the build's generic carries, the stub is there.  Two plants, no #ifdef,
#   and no dependence on which change lands first.
#
# N-AGNOSTIC.  Exactly three tiles are launched at any NHARTS and no shared
#   word is indexed past hart 3.
#
# SHARED WORDS CLAIMED -- the D2 CORE-DETECTOR BAND 0x10880-0x108FF (32 words),
#   two 16-word per-hart blocks at 0x10840 + 0x40*h for h = 1, 2.  The band is
#   above the debug entry page (which ends 0x1087F) and below shlock's JOURNAL
#   at 0x11000, and nothing else claims 0x10880-0x10FFF at either N.  It is
#   OUTSIDE the bootrom zero range, so hart 0 clears it and reads it back
#   before anything else -- the write-before-read contract, discharged in band.
#   REUSED with different meanings by dbgirqmp.S (one image per sim; the two
#   never coexist -- the shdma/wdma precedent).
#     +0x00 ENTRIES   +0x04 DPC1     +0x08 DPC2    +0x0C DCSR1
#     +0x10 DCSR2     +0x14 MEPC1    +0x18 MEPC2   +0x1C MCAUSE1
#     +0x20 MCAUSE2   +0x24 CNT      +0x28 TRIP    +0x2C READY
#     +0x30 REL       +0x34 POST     +0x38 EXTRA   +0x3C (spare)
#   hart 3's block is 0x10900-0x1093F and its CNT is at 0x10900 + O_CNT.
#   (The first draft mis-addressed it at 0x10940 -- outside every block -- and
#   the liveness control caught that too: a1 = 0x0D27000B with a2 = 0.)
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define BLK_BASE     0x10840        /* block(h) = BLK_BASE + 0x40*h */
#define O_ENTRIES    0
#define O_DPC1       4
#define O_DPC2       8
#define O_DCSR1      12
#define O_DCSR2      16
#define O_MEPC1      20
#define O_MEPC2      24
#define O_MCAUSE1    28
#define O_MCAUSE2    32
#define O_CNT        36
#define O_TRIP       40
#define O_READY      44
#define O_REL        48
#define O_POST       52
#define O_EXTRA      56

#define MEPC_MAGIC   0x0D26E9C0
#define TRIP_MAGIC   0x0D264719     /* the std mtvec tripwire's magic */
#define POST_MAGIC   0x0D26D057     /* "the victim came back out"     */

#define TILE_WORDS   1024
#define ARM_BUDGET   40000
#define BADOP        0x0000007F     /* absent from valid_opcode on every build */
#define DRET_INSN    0x7B200073
#define MTRAPCTL     0x7C0

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry

    # ==================================================================
    # clear the band and prove it read back.  The band is ABOVE the
    # bootrom zero range, so this is the write-before-read contract
    # being discharged, not a formality.
    # ==================================================================
    li   a1, 0x0D260001
    li   t0, 0x10880
    li   t1, 48                     # 0x10880-0x1093F: blocks for harts 1,2,3
dx_clr:
    sw   x0, 0(t0)
    lw   t2, 0(t0)
    bnez t2, dx_fail
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, dx_clr

    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    li   a1, 0x0D260002
    bne  t2, t3, dx_fail

    jal  ra, dx_plant_shared        # ONE shared plant, before any launch

    MP_STAGE_IMAGE(TILE_WORDS)
    MP_LAUNCH_HART(1, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(2, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(3, tile_entry, TILE_WORDS)

    # ==================================================================
    # both victims must be READY before the harness can mean anything
    # ==================================================================
    li   t6, ARM_BUDGET
dx_rdy:
    li   t0, 0x10880
    lw   t2, O_READY(t0)
    li   t0, 0x108C0
    lw   t3, O_READY(t0)
    beqz t2, dx_rdy_next
    bnez t3, dx_armed
dx_rdy_next:
    addi t6, t6, -1
    bnez t6, dx_rdy
    li   a2, 1
    beqz t2, 1f
    li   a2, 2
1:  li   a1, 0x0D260003
    j    dx_fail

dx_armed:
    # ==================================================================
    # wait for BOTH victims to reach ENTRIES == 2 (entered, faulted,
    # re-entered).  The tripwire is sampled every round, so a std-side
    # failure reports positively instead of waiting out the budget.
    # ==================================================================
    li   t6, ARM_BUDGET
dx_wait:
    li   t0, 0x10880
    lw   t4, O_TRIP(t0)
    bnez t4, dx_trip1
    li   t0, 0x108C0
    lw   t4, O_TRIP(t0)
    bnez t4, dx_trip2
    li   t0, 0x10880
    lw   t2, O_ENTRIES(t0)
    li   t0, 0x108C0
    lw   t3, O_ENTRIES(t0)
    li   t5, 2
    blt  t2, t5, dx_wait_next
    bge  t3, t5, dx_both
dx_wait_next:
    addi t6, t6, -1
    bnez t6, dx_wait
    # name the victim that never came back
    li   s5, 1
    mv   a2, t2
    li   t5, 2
    blt  t2, t5, dx_noreentry
    li   s5, 2
    mv   a2, t3
dx_noreentry:
    slli a1, s5, 8
    li   t2, 0x0D260004
    add  a1, a1, t2
    j    dx_fail

dx_trip1:
    li   s5, 1
    mv   a2, t4
    j    dx_trip
dx_trip2:
    li   s5, 2
    mv   a2, t4
dx_trip:
    slli a1, s5, 8
    li   t2, 0x0D260005
    add  a1, a1, t2
    j    dx_fail

dx_both:
    # ==================================================================
    # per-victim equalities.  Every expected value is a MEASUREMENT the
    # same stub took a moment earlier, never a constant.
    # ==================================================================
    li   s5, 1
dx_loopchk:
    slli s6, s5, 6
    li   s7, BLK_BASE
    add  s7, s7, s6                 # s7 = block(h)

    lw   a2, O_DPC2(s7)
    lw   a3, O_DPC1(s7)
    slli a1, s5, 8
    li   t2, 0x0D260006
    add  a1, a1, t2
    bne  a2, a3, dx_fail

    lw   a2, O_DCSR2(s7)
    lw   a3, O_DCSR1(s7)
    slli a1, s5, 8
    li   t2, 0x0D260007
    add  a1, a1, t2
    bne  a2, a3, dx_fail

    lw   a2, O_MEPC2(s7)
    lw   a3, O_MEPC1(s7)
    slli a1, s5, 8
    li   t2, 0x0D260008
    add  a1, a1, t2
    bne  a2, a3, dx_fail

    lw   a2, O_MCAUSE2(s7)
    lw   a3, O_MCAUSE1(s7)
    slli a1, s5, 8
    li   t2, 0x0D260009
    add  a1, a1, t2
    bne  a2, a3, dx_fail

    addi s5, s5, 1
    li   t0, 3
    blt  s5, t0, dx_loopchk

    # ==================================================================
    # release both victims and require them to come back out
    # ==================================================================
    li   t0, 0x10880
    li   t1, 1
    sw   t1, O_REL(t0)
    li   t0, 0x108C0
    sw   t1, O_REL(t0)

    li   t6, ARM_BUDGET
dx_post:
    li   t0, 0x10880
    lw   t2, O_POST(t0)
    li   t0, 0x108C0
    lw   t3, O_POST(t0)
    beqz t2, dx_post_next
    bnez t3, dx_posted
dx_post_next:
    addi t6, t6, -1
    bnez t6, dx_post
    li   s5, 1
    mv   a2, t2
    beqz t2, 1f
    li   s5, 2
    mv   a2, t3
1:  slli a1, s5, 8
    li   t2, 0x0D26000A
    add  a1, a1, t2
    j    dx_fail

dx_posted:
    li   t0, 0x10900                # block(3); the bystander must still work
    lw   a2, O_CNT(t0)
    li   t1, 8
    li   a1, 0x0D26000B
    blt  a2, t1, dx_fail

    RVTEST_PASS                     # a0 = 0xCAFEBABE

dx_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    # =====================================================================
    # dx_plant_shared -- copy the stub to the SHARED entry page 0x10780.
    # dx_plant_tcm    -- copy the same stub to TCM 0xBE00 in THIS hart.
    # Both clobber t0-t3.  The stub is planted at BOTH addresses because the
    # tree's DEBUG_ENTRY_ADDR is 0xBE00 today and 0x10780 after the
    # generator's debug-ON emission lands; this detector has to work on both.
    # =====================================================================
dx_plant_shared:
    la   t0, dx_stub_start
    la   t1, dx_stub_end
    li   t2, 0x10780
    j    dx_copy
dx_plant_tcm:
    la   t0, dx_stub_start
    la   t1, dx_stub_end
    li   t2, 0xBE00
dx_copy:
1:  lw   t3, 0(t0)
    sw   t3, 0(t2)
    addi t0, t0, 4
    addi t2, t2, 4
    blt  t0, t1, 1b
    ret

    # =====================================================================
    # THE DEBUG STUB.  Copied verbatim to DEBUG_ENTRY_ADDR.  Relocation
    # rules as in every D-series stub: no `la`, no `auipc`, no branch or jump
    # leaving the block; every absolute address arrives via `li`; the entry
    # counter lives in dscratch0, which is what that CSR is for.
    #
    # ENTRY 1 records dpc/dcsr/mepc/mcause and then EXECUTES THE FAULT.
    # ENTRY 2 -- which exists only if the RTL honours the contract -- records
    # them again and returns.  ENTRY >= 3 is a runaway re-entry: it records
    # nothing (so a deliberate later halt cannot disturb the equalities) but
    # publishes its count in EXTRA, and returns immediately rather than
    # faulting again, so a broken build cannot spin here forever.
    # =====================================================================
    .option push
    .option arch, +zicsr
dx_stub_start:
#ifdef DBGEXC_NC_SELFENTRY
    # CONTROL ARM: dscratch0 is a DEBUG-MODE-ONLY CSR (0x7B2).  Reading it
    # outside debug mode is an illegal instruction -- which on hart 2, with
    # std delivery armed, fires this file's own mtvec tripwire and reports a
    # finding that is entirely the control arm's fault.  MEASURED on the
    # first control run (a1 = 0x0D260205, a2 = TRIP_MAGIC).  So the control
    # keeps its entry count in an ordinary register, the dbgstepmp NC-arm
    # precedent, and touches no 0x7Bx address at all.
    addi a6, a6, 1
    mv   t2, a6
    li   t0, 0x0D26DBC0             # a synthetic "dpc"
    li   t1, 0x400000C3             # ...and "dcsr": ver=4, cause=3, prv=3
#else
    csrr t2, dscratch0
    addi t2, t2, 1
    csrw dscratch0, t2
    csrr t0, dpc
    csrr t1, dcsr
#endif
    csrr a4, mhartid
    slli a3, a4, 6
    li   a5, BLK_BASE
    add  a5, a5, a3                 # a5 = block(h)
    li   a2, 3
    blt  t2, a2, 2f
    sw   t2, O_EXTRA(a5)            # runaway: record and leave
    j    9f
2:  sw   t2, O_ENTRIES(a5)
    li   a2, 1
    bne  t2, a2, 3f
    sw   t0, O_DPC1(a5)
    sw   t1, O_DCSR1(a5)
    csrr t3, mepc
    sw   t3, O_MEPC1(a5)
    csrr t4, mcause
    sw   t4, O_MCAUSE1(a5)
#ifndef DBGEXC_NC_SELFENTRY
    .word BADOP                     # THE SYNCHRONOUS EXCEPTION, IN DEBUG MODE
#endif
    j    9f
3:  sw   t0, O_DPC2(a5)
    sw   t1, O_DCSR2(a5)
    csrr t3, mepc
    sw   t3, O_MEPC2(a5)
    csrr t4, mcause
    sw   t4, O_MCAUSE2(a5)
9:
#ifdef DBGEXC_NC_SELFENTRY
    ret                             # CONTROL ARM: an ordinary return
#else
    .word DRET_INSN
#endif
dx_stub_end:
    .option pop

    # =====================================================================
    # THE STD-POLARITY TRIPWIRE.  hart 2 points mtvec here.  Reaching it at
    # all means standard delivery took a trap that belonged to debug mode.
    # It does NOT `mret`: the state is left exactly as it was for the
    # harness to read, and hart 0 reports the magic.
    # =====================================================================
dx_mtvec_trip:
    .option push
    .option arch, +zicsr
    csrr t1, mhartid
    .option pop
    slli t1, t1, 6
    li   t0, BLK_BASE
    add  t0, t0, t1
    li   t1, TRIP_MAGIC
    sw   t1, O_TRIP(t0)
1:  j    1b

    # ---- tile harts enter here (loader ABI: only sp is defined) ----------
tile_entry:
    li   sp, 0xBFF0
    jal  ra, dx_plant_tcm           # this hart's own private-TCM copy
    .option push
    .option arch, +zicsr
    csrr t3, mhartid
    .option pop
    slli s6, t3, 6
    li   s7, BLK_BASE
    add  s7, s7, s6                 # s7 = this hart's block

    li   t4, 3
    beq  t3, t4, dx_bystander

    .option push
    .option arch, +zicsr
    li   t4, 2
    bne  t3, t4, 1f
    # ---- hart 2 only: STANDARD delivery, and a tripwire on mtvec --------
    csrw MTRAPCTL, x0               # clear LEGACY: std delivery from here
    la   t0, dx_mtvec_trip
    csrw mtvec, t0
1:  li   t0, MEPC_MAGIC             # seed mepc so a clobber is visible
    csrw mepc, t0
    .option pop

    li   t0, 1
    sw   t0, O_READY(s7)            # publish LAST

#ifdef DBGEXC_NC_SELFENTRY
    # CONTROL ARM: no debug mode exists on the tree this was authored against,
    # so each victim visits its own stub twice by hand -- once for each entry
    # the real flow produces -- and everything downstream runs for real.
    li   t0, 0xBE00
    jalr ra, t0, 0
    li   t0, 0xBE00
    jalr ra, t0, 0
#endif

    # THE PARK.  A counting loop, so "it resumed" is observable, and it holds
    # no live register across an iteration except its own block pointer --
    # a debug visit that clobbers t0-t4 and a2-a5 is invisible to it.
dx_park:
    lw   t0, O_CNT(s7)
    addi t0, t0, 1
    sw   t0, O_CNT(s7)
    lw   t1, O_REL(s7)
    beqz t1, dx_park
    li   t0, POST_MAGIC
    sw   t0, O_POST(s7)
dx_vpark:
    j    dx_vpark

dx_bystander:
    lw   t0, O_CNT(s7)
    addi t0, t0, 1
    sw   t0, O_CNT(s7)
    j    dx_bystander

    # NOTE: RVTEST_CODE_END is `unimp` in this env (it traps) -- never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
