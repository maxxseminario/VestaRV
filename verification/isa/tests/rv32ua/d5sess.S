# See LICENSE for license details.

# VestaRV: debug-session image, three live harts and one victim
# ONE THIRD OF AN INSTRUMENT. The other two thirds are dbg_sessrun.tcl, the bridge and graders inside the simulator, and a real OpenOCD and gdb session driven from outside. Run it as `D5_PROFILE=d5sess D5_PORTFILE=... ./xrun_dbg_verify.sh verify_castaliadebug ../kba/xrv32ua-p-d5sessmp.rcf dbg_sessrun.tcl`. Three liveness counters make "halt one hart while the others keep running" gradeable with two independent witnesses, harts 0 and 1, while hart 2 is the victim.
# THIS IMAGE HAS NO a0 VERDICT AND NEVER TERMINATES, BY DESIGN. riscv_tb ends the run when hart 0 writes a0, but a real gdb session takes minutes of simulated time at a human-paced driver's instants, so an image able to end on its own schedule could stop the chip half way through grading. Setup failures are published to DIAG and the image keeps running, so a broken setup is visible in every snapshot instead of silently ending the run. A run ALWAYS ends with the tb's 100 ms watchdog banner, which the harness expects. CONSEQUENCE: this image must never be added to a standing gate list, where it would show as a watchdog hang; it is built out of tree by tools/build_one_rcf.sh for that reason.
# Shared words, all inside the D-series debug acceptance band 0x10050-0x1007C, whose layout is specified by dbg_sess_lib.tcl's `d5sess` profile and transcribed here so claim and use are the same document: 0x10050 PHASE, 0x10054 READY (the word the harness polls), 0x10058/5C/60 LIVE0/LIVE1/LIVE2 with LIVE2 the victim, 0x10064 MEMW (seeded here, overwritten by gdb with 0xD5EE7A11), 0x10068 SEED (so the grader can require the seed before and the cookie after, two nonzero values, so neither "already zero" nor "everything is zero" can pass), 0x1006C SPARE, 0x10070 DIAG (0 means setup completed), 0x10074 LEFT FREE because it is another image's word, 0x10078 REL, 0x1007C MARK = 0xD5000001.
# REL IS DELIBERATELY NOT CONSUMED: the bridge's control channel is passive-only, so nothing in the graded architecture can write REL and a release wait would be a hang with a friendly name. The LIVENESS COUNTERS ARE MONOTONIC AND ARE NEVER RESET HERE, because every progress grader is a strict increase, which is immune to sampling instants; a reset would make a correct chip fail. THE HARNESS MUST NOT FORCE ANY BAND WORD BEFORE READY: hart 0 clears all twelve and reads them back at entry, and a word forced before that check makes hart 0 publish DIAG = 0x0D5E0001 instead of completing setup.
# THE BREAKPOINT SITE `d5_bp_site` is a single 32-bit `addi t1, zero, 1493` inside hart 2's counting loop, immediately after the counter store and before the backward jump. Three properties are load-bearing: it affects no graded word, so a breakpoint changes only control flow; it is reached once per counter increment, so "the hart ran into the breakpoint" holds wherever an asynchronous halt caught it; and under `.option norvc` both it and its successor are 32 bits. The address, the original opcode and the successor address handed to the harness are READ OFF OBJDUMP OF THE BUILT ELF, never off a directive, because `.balign` is a silent no-op inside a norvc region. gdb sees one flat address space, but 0x8000-0xBFFC is per-tile private TCM, so a breakpoint planted while hart 2 is selected lands in hart 2's TCM alone.
# N-agnostic: harts 1 and 2 are launched by number, hart 3 is deliberately left parked in the boot ROM, and no word is indexed by hartid, so the layout is identical at N=4 and N=18.

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
