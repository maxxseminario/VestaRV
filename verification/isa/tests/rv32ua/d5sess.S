# See LICENSE for license details.

#*****************************************************************************
# d5sess.S   (D-series, D5 -- the SESSION image: three live harts, one victim)
#-----------------------------------------------------------------------------
# THE SIBLING IMAGE d5_spec.md section 5.1 MAKES MANDATORY (R-D5-2(1c)).
#
# NEEDS A HARNESS, AND A DEBUGGER.  This image is one third of an instrument.
# The other two thirds are dbg_sessrun.tcl (the bridge + the graders, in the
# simulator) and a real OpenOCD/gdb session driven from outside.  Run it as:
#
#   D5_PROFILE=d5sess D5_PORTFILE=... ./xrun_dbg_verify.sh \
#       verify_castaliadebug ../kba/xrv32ua-p-d5sessmp.rcf dbg_sessrun.tcl
#
# WHY IT EXISTS, MEASURED RATHER THAN ARGUED.  The D4 image `dbgtrpmp` carries
# exactly ONE liveness counter (hart 1's SH_RAN at 0x10074).  d5_spec 5.2's
# headline clause is "halt hart 2 while THE OTHERS keep running, proven by
# their liveness counters advancing across the halt window", and the acceptance
# author measured that clause coming out NOT-GRADED for every hart but one on
# the dbgtrpmp profile.  Three counters make it gradeable with TWO independent
# witnesses (harts 0 and 1) while hart 2 is the victim.
#
# -------------------------------------------------------------------------
# THIS IMAGE HAS NO a0 VERDICT, AND THAT IS THE DESIGN, NOT AN OMISSION.
#   riscv_tb ends the run when hart 0 writes 0xCAFEBABE/0xDEADBEEF to a0.  A
#   real gdb session over the remote_bitbang bridge takes MINUTES of simulated
#   time and its instants are chosen by a human-paced driver, so an image that
#   could terminate on its own schedule would be able to end the session
#   half-way through and leave the graders reading a stopped chip.  So:
#
#       hart 0 NEVER writes a0 and NEVER terminates.
#
#   The verdict of this instrument is dbg_sessrun.tcl's grader summary, not a0.
#   Setup failures are PUBLISHED to the DIAG word (0x10070) and the image keeps
#   running, so a broken setup is visible in every snapshot and in the oracle
#   dump instead of silently ending the run.  A run of this image ALWAYS ends
#   with the tb's 100 ms watchdog banner; the bridge header documents that
#   banner as expected, and the harness exits after grading.
#
#   Consequence, stated because it is a real limitation: this image must never
#   be added to any standing gate list (xrun_parallel.sh / verify_stage.py
#   CATALOG).  It has no PASS to report and would show as a watchdog hang.  It
#   is built out of tree by tools/build_one_rcf.sh for exactly that reason,
#   like every other D-series debug image.
#
# -------------------------------------------------------------------------
# SHARED WORDS CLAIMED -- NONE THAT ARE NEW.  Everything below is inside the
# D-series debug acceptance band 0x10050-0x1007C (12 words), already claimed in
# CLAUDE.md for exactly this reuse-with-different-meanings under the
# one-image-per-sim rule.  The layout is NOT this file's invention: it is
# specified by the acceptance author in dbg_sess_lib.tcl's own header (profile
# `d5sess`) and is transcribed here so claim and use are the same document
# (the F-ID2-1 lesson).
#
#     0x10050  PHASE   hart 0 progress
#     0x10054  READY   image -> harness: all three live harts are running.
#                      d4_wait_ready polls exactly this word.
#     0x10058  LIVE0   hart 0's monotonic liveness counter
#     0x1005C  LIVE1   hart 1's monotonic liveness counter
#     0x10060  LIVE2   hart 2's monotonic liveness counter (THE VICTIM)
#     0x10064  MEMW    seeded here, overwritten by gdb with 0xD5EE7A11
#     0x10068  SEED    the seed MEMW was given, so the grader can require
#                      "held the seed before AND the cookie after" -- two
#                      nonzero values, so neither "it was already zero" nor
#                      "everything is zero" can pass
#     0x1006C  SPARE   written once with a marker, then never touched
#     0x10070  DIAG    setup diagnosis (0 = setup completed)
#     0x10074  -----   LEFT FREE.  This is dbgtrpmp's RAN word, deliberately
#                      untouched so the two images share the band unambiguously
#     0x10078  REL     declared by the profile; see below -- NOT consumed here
#     0x1007C  MARK    0xD5000001, the image identity magic
#
#   REL IS DELIBERATELY NOT CONSUMED.  dbgtrpmp waits on REL for the harness to
#   release it.  This image cannot: the bridge's control channel is PASSIVE-ONLY
#   by design (no force, no run, no DMI), so nothing in the graded architecture
#   is able to write REL, and a release wait that can never be satisfied is a
#   hang with a friendly name.  The word is cleared and left alone.
#
#   THE LIVENESS COUNTERS ARE MONOTONIC AND ARE NEVER RESET BY THIS IMAGE.
#   Every progress grader in dbg_sess_lib.tcl is "strictly greater than", which
#   is immune to sampling instants; a counter this image reset would make a
#   correct chip FAIL.  There is no wrap handling and none is needed: 2^32
#   increments is far beyond any session.
#
#   THE HARNESS MUST NOT FORCE ANY BAND WORD BEFORE READY.  hart 0 clears all
#   twelve words and reads them back at entry; a word forced before that check
#   reads back non-zero and hart 0 publishes DIAG = 0x0D5E0001 instead of
#   completing setup.
#
# -------------------------------------------------------------------------
# THE BREAKPOINT SITE.  d5_spec 5.2 asks for a SOFTWARE breakpoint hit and one
# `stepi`.  The graders take the address, the site's ORIGINAL opcode and the
# successor address, and they assert the pre-session word equals the original,
# so a wrong address FAILS LOUDLY instead of silently covering nothing.
#
#   `d5_bp_site` is a single 32-bit `addi t1, zero, 1493` inside hart 2's
#   counting loop, immediately AFTER the counter store and immediately BEFORE
#   the loop's backward jump.  Three properties, each load-bearing:
#     * it has no effect on any graded word, so a breakpoint on it changes
#       nothing but control flow;
#     * it is reached ONCE PER COUNTER INCREMENT, so "the hart RAN into the
#       breakpoint" (SG-G3: the counter advanced between the resume and the
#       hit) holds no matter where in the loop the asynchronous halt caught it;
#     * under `.option norvc` both it and its successor are 32-bit, so the
#       stepi successor is site+4 -- BUT THAT IS A PREDICTION, NOT EVIDENCE.
#       The three numbers the harness is given are read off OBJDUMP of the
#       built ELF, never off a directive (`.balign` is a silent no-op inside a
#       norvc region; method rule 7).
#
#   NOTE FOR THE DEBUGGER-FACING WRITE-UP: gdb sees ONE flat address space, but
#   0x8000-0xBFFC is PER-TILE PRIVATE TCM on this chip.  A breakpoint planted
#   while hart 2 is selected lands in hart 2's TCM and in no other hart's.
#
# -------------------------------------------------------------------------
# N-AGNOSTIC.  Harts 1 and 2 are launched by number and hart 3 is DELIBERATELY
# left parked in the boot ROM; no word is indexed by hartid, so the layout is
# identical at N=4 and N=18, where harts 3..17 are all parked.  The band does
# not overlap anything at either N (CLAUDE.md's ledger row for it says so).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_PHASE   0x10050
#define SH_READY   0x10054
#define SH_LIVE0   0x10058
#define SH_LIVE1   0x1005C
#define SH_LIVE2   0x10060
#define SH_MEMW    0x10064
#define SH_SEED    0x10068
#define SH_SPARE   0x1006C
#define SH_DIAG    0x10070
#define SH_REL     0x10078
#define SH_MARK    0x1007C

#define MARKVAL    0xD5000001
#define SEEDVAL    0x5EED0D50
#define SPAREVAL   0x5A5E0D50

#define DIAG_BAND      0x0D5E0001
#define DIAG_ISA       0x0D5E0002
#define DIAG_SEED      0x0D5E0003
#define DIAG_TILE1     0x0D5E0005
#define DIAG_TILE2     0x0D5E0006

#define TILE_WORDS 1024
#define START_T    16
#define GLOBAL_BUDGET 20000

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry

    # ---- hart 0: clear the claimed band and prove it cleared ---------------
    li   s9, DIAG_BAND
    li   t0, SH_PHASE
    li   t1, 12                     # 12 words: 0x10050 .. 0x1007C
ds_clr:
    sw   x0, 0(t0)
    lw   t2, 0(t0)
    bnez t2, ds_stuck
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, ds_clr

    # ---- base-ISA sanity ---------------------------------------------------
    li   s9, DIAG_ISA
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, ds_stuck

    # ---- seed MEMW and SEED, and read MEMW back ----------------------------
    # SEED and MEMW get the SAME known-nonzero value.  The memory-write grader
    # requires MEMW == SEED before the session and the cookie after: two
    # nonzero values, so a chip where every shared word reads zero cannot pass.
    li   s9, DIAG_SEED
    li   t0, SH_SEED
    li   t1, SEEDVAL
    sw   t1, 0(t0)
    li   t0, SH_MEMW
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t2, t1, ds_stuck

    li   t0, SH_SPARE
    li   t1, SPAREVAL
    sw   t1, 0(t0)
    li   t0, SH_MARK
    li   t1, MARKVAL
    sw   t1, 0(t0)

    # ---- launch the two tiles ----------------------------------------------
    # hart 3 (and, at N=18, every hart above it) is deliberately NOT launched:
    # it stays parked in the boot ROM's WFI, which is the second tile state a
    # debugger session has to be able to meet.
    MP_STAGE_IMAGE(TILE_WORDS)
    MP_LAUNCH_HART(1, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(2, tile_entry, TILE_WORDS)

    # ---- wait for BOTH tiles to demonstrate execution ----------------------
    # An ORDERING on each tile's own counter, bounded by a retry budget that
    # trips well inside the 100 ms tb watchdog.  Expiry publishes a DIAG code
    # and falls into the liveness loop -- never a fall-through, and never a
    # silent success.
    li   s11, GLOBAL_BUDGET
    li   t4, START_T
    li   s9, DIAG_TILE1
ds_w1:
    li   t0, SH_LIVE1
    lw   t1, 0(t0)
    bge  t1, t4, ds_w1ok
    addi s11, s11, -1
    bnez s11, ds_w1
    j    ds_stuck
ds_w1ok:
    li   s9, DIAG_TILE2
ds_w2:
    li   t0, SH_LIVE2
    lw   t1, 0(t0)
    bge  t1, t4, ds_w2ok
    addi s11, s11, -1
    bnez s11, ds_w2
    j    ds_stuck
ds_w2ok:

    li   t0, SH_PHASE
    li   t1, 1
    sw   t1, 0(t0)
    li   t0, SH_READY
    li   t1, 1
    sw   t1, 0(t0)

    # ---- hart 0's own liveness loop, forever -------------------------------
    # This is the witness that stays running while the debugger halts hart 2,
    # AND the reason the image cannot end: hart 0 is the management hart and a
    # session needs it alive from attach to detach.
    li   t5, SH_LIVE0
ds_h0loop:
    lw   t0, 0(t5)
    addi t0, t0, 1
    sw   t0, 0(t5)
    j    ds_h0loop

    # ---- setup failure: publish and keep running ---------------------------
    # s9 carries the code of the check that was armed when we got here.  We do
    # NOT touch a0: see the header.  The image still runs its hart-0 counter so
    # the snapshots keep working and the failure is visible as a nonzero DIAG
    # in every one of them, next to a PHASE that never reached 1.
ds_stuck:
    li   t0, SH_DIAG
    sw   s9, 0(t0)
    li   t5, SH_LIVE0
ds_stuckloop:
    lw   t0, 0(t5)
    addi t0, t0, 1
    sw   t0, 0(t5)
    j    ds_stuckloop

    # =======================================================================
    # the tiles
    # =======================================================================
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

    # hart 1 -- the second witness, and the victim of the reset-halt and msip
    # legs (harts 1..N-1 only: PWRCR bit 0 is RO-0, so hart 0 has no lever).
    # A plain monotonic counter and nothing else.
tile_h1:
    li   t5, SH_LIVE1
th1_loop:
    lw   t0, 0(t5)
    addi t0, t0, 1
    sw   t0, 0(t5)
    j    th1_loop

    # hart 2 -- THE VICTIM of the halt/cookie/breakpoint/step/resume legs.
    # Neither a5 (x15) nor mscratch is touched anywhere in this image, which is
    # what makes the debugger the only possible author of the cookies the GPR
    # and CSR graders look for.
tile_h2:
    li   t5, SH_LIVE2
th2_loop:
    lw   t0, 0(t5)
    addi t0, t0, 1
    sw   t0, 0(t5)
    .globl d5_bp_site
d5_bp_site:
    addi t1, x0, 1493
    .globl d5_bp_next
d5_bp_next:
    j    th2_loop

    # There is no RVTEST_PASS / RVTEST_FAIL path in this image.  RVTEST_CODE_END
    # is `unimp` in this environment and TRAPS, so nothing may fall through to
    # it; every path above ends in an unconditional backward branch.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
