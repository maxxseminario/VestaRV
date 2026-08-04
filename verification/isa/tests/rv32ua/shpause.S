// See LICENSE for license details.

//*****************************************************************************
// shpause.S  (X1 Zihintpause -- directed multi-hart PAUSE arbiter-yield test)
//-----------------------------------------------------------------------------
// THE observable evidence that ENABLE_ZIHINT's PAUSE side-effect is live: the
// ANTAGONIST (hart 1) runs a FIXED bus-work burst (NITER iterations of a
// shared store + load), and the MEASURER (hart 0) times the burst with the
// FREE-RUNNING CLINT mtime (0x5000 + roundup16(4*NHARTS), +1 per mclk --
// advances even while a hart is stalled, so it is a true wall-clock). The burst
// is run twice:
//   Phase 1 CONTROL : antagonist runs the burst with NO pause      -> RCTL
//   Phase 2 PAUSE   : antagonist adds PAUSE each iteration (16-cycle bus
//                     yield, D6)                                    -> RPAU
// Each PAUSE drops the antagonist OUT of the arbiter request contest for the
// window (verified at RTL: the core enters PAUSE_WAIT with its shared-bus
// request de-asserted), so the SAME fixed bus work takes deterministically
// LONGER wall-clock with PAUSE: RPAU > RCTL by ~NITER*window mclk. The burst is
// pure bus traffic (no lock) so it always completes -- bounded, no livelock.
//
//   ON build  (#ifdef CORE_ENABLE_ZIHINT): ASSERT RPAU > RCTL + MARGIN.
//       The negative-control seed (PAUSE_WINDOW_CYCLES = 0) makes PAUSE a plain
//       fence-nop -> RPAU ~= RCTL -> this assertion FAILS (that is the point).
//   OFF build (#else): PAUSE is a plain fence-nop; the comparison is
//       meaningless, so it degrades to a forward-progress check (both bursts
//       timed, all tiles reported DONE) and PASSES -- keeping the suite green
//       under the DEFAULT (off) build.
//
// RCTL/RPAU are stored to shared words (and left in s4/s5) for readback.
//
// SYNCHRONISATION (tiles boot SERIALLY through the ROM loader): the measurer
// waits for the antagonist's READY flag before phase 1 so BOTH phases see a
// live antagonist, and waits for every tile's DONE flag before the verdict so a
// still-booting tile can never masquerade as the failure.
//
// CPP GOTCHA (cost a debug cycle): inline `#` comments on `#define`s are NOT
// stripped by cpp and leak into the macro body, so `NAME + 4` puts the `+ 4`
// inside an assembler comment and silently drops it. Every define below uses
// `//` (cpp-stripped) and every derived address uses REGISTER arithmetic.
//*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"
// CORE_ENABLE_ZIHINT comes from the per-polarity feature header staged in env/p
// (a dependency-free extract of the make-chip CORE_ENABLE defines; see
// env/p/core_features.h). Committed = off => the #else forward-progress arm.
#include "core_features.h"

// --- shared scratch (bootrom-zeroed 0x10000-0x107FF, isolation-safe band) ---
#define MODE    0x10300        // 0 idle, 1 control-run, 2 pause-run, 3 stop
#define READY1  0x10304        // antagonist booted & polling MODE
#define PDONE   0x10308        // antagonist finished the current phase's burst
#define RCTL    0x1030C        // control-phase burst time (readback)
#define RPAU    0x10310        // pause-phase   burst time (readback)
#define DONEB   0x1031C        // DONE[h] base: DONE[h] = DONEB + 4*h (h=1..3)

// CLINT mtime lo: free-running, +1 per mclk. N-PARAMETERISED -- the msip array
// is 4*NHARTS bytes and mtime follows it at the next 16-byte boundary, so this
// is 0x5010 at N=4 and 0x5050 at N=18. It was the LITERAL 0x5010 until K5, which
// made this test read `msip[4]` on an 18-hart build: the timer read back 0, the
// elapsed-time check `beqz s4` fired, and the row FAILED (R-K2-4's measurement).
// `extzawrs.S` is the pattern this now follows.
#define MTIME_OFF ((4*NHARTS + 15) & ~15)
#define MTIME_LO  (0x5000 + MTIME_OFF)
#define NITER   256            // antagonist bus-work iterations per phase
#define MARGIN  2000           // required RPAU-over-RCTL mtime gap on the ON build
                               // (window=16 gap ~4400 mclk; window=0 gap ~0 --
                               //  MARGIN sits safely between, so the seed fails)

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry            // only hart 0 launches

    // hart 0: stage this TCM image once, launch the tiles, then measure.
    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_ALL(tile_entry, 4096)
    j    measurer

tile_entry:                         // tiles enter here (loader ABI: only sp defined)
    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    li   sp, 0xBFF0
    li   t0, 1
    beq  s10, t0, antagonist        // hart 1 = antagonist
    // harts 2..NHARTS-1: benign -- record DONE[h], inline PASS, park quietly.
    li   t1, DONEB
    slli t0, s10, 2
    add  t1, t1, t0                 // &DONE[h] (register arithmetic)
    li   t2, 1
    sw   t2, 0(t1)
    li   a0, 0xCAFEBABE
1:  j    1b

// =====================================================================
// ANTAGONIST (hart 1): per phase, run a FIXED NITER bus-work burst (with
// PAUSE each iter in pause mode), signal PDONE, wait for the next MODE.
// =====================================================================
antagonist:
    li   s0, 0x102F0                // s0 = AWORD (private-band shared word for traffic)
    li   s1, MODE
    li   s2, PDONE
    li   t0, 1
    li   t1, READY1
    sw   t0, 0(t1)                  // READY1 = 1 (booted, entering the loop)
a_loop:
    lw   a3, 0(s1)                  // current MODE
    beqz a3, a_loop                 // idle: wait for the measurer to open a phase
    li   t0, 3
    beq  a3, t0, a_finish           // stop
    // MODE 1 or 2 -> run the fixed burst. BOTH modes execute a FENCE-class
    // instruction each iteration so the only timing difference between the
    // phases is PAUSE's side-effect (the window), NOT the presence of an extra
    // instruction. Control uses a plain `fence` (FENCE_WAIT, no side-effect);
    // pause uses `pause` (PAUSE_WAIT + window). With the window=0 seed, pause
    // decodes down the SAME FENCE_WAIT path => the phases match => the negative
    // control fails, exactly isolating the side-effect.
    li   a4, NITER
a_iter:
    sw   x0, 0(s0)                  // bus traffic: shared store
    lw   t0, 0(s0)                  // bus traffic: shared load
    li   t0, 2
    beq  a3, t0, a_do_pause
    fence                           // control mode: ordinary fence nop
    j    a_iter_end
a_do_pause:
    .word 0x0100000F               // pause mode: PAUSE (fence w,0) -- bus yield
a_iter_end:
    addi a4, a4, -1
    bnez a4, a_iter
    // burst complete: signal PDONE, then wait for MODE to change off a3
    li   t0, 1
    sw   t0, 0(s2)                  // PDONE = 1
a_wait_mode:
    lw   t0, 0(s1)
    beq  t0, a3, a_wait_mode        // hold until the measurer opens the next phase
    j    a_loop
a_finish:
    li   t1, 0x10320               // DONE[1] (= DONEB + 4, spelled out to dodge cpp)
    li   t0, 1
    sw   t0, 0(t1)
    li   a0, 0xCAFEBABE             // inline PASS (tb latches a0_1)
2:  j    2b

// =====================================================================
// MEASURER (hart 0): wait for the antagonist, time both bursts, compare.
// =====================================================================
measurer:
    li   s1, MODE
    li   s2, PDONE
    li   s6, MTIME_LO

    // ---- wait for the antagonist to boot and start polling MODE ----
    li   t1, READY1
    li   t6, 300000                // bounded (covers the serial tile ROM copies)
rw_loop:
    lw   t0, 0(t1)
    bnez t0, rw_done
    addi t6, t6, -1
    bnez t6, rw_loop
    j    shpause_fail              // antagonist never booted
rw_done:

    // ---- Phase 1: CONTROL (antagonist burst, no pause) ----
    li   t0, 1
    sw   t0, 0(s1)                  // MODE = 1
    jal  ra, time_burst            // -> a5 = elapsed mtime for the burst
    mv   s4, a5                     // RCTL
    li   t0, RCTL
    sw   s4, 0(t0)

    // ---- Phase 2: PAUSE (antagonist burst, PAUSE each iter) ----
    sw   x0, 0(s2)                  // clear PDONE for the next phase
    li   t0, 2
    sw   t0, 0(s1)                  // MODE = 2
    jal  ra, time_burst
    mv   s5, a5                     // RPAU
    li   t0, RPAU
    sw   s5, 0(t0)

    // ---- stop the antagonist, then wait for EVERY tile's DONE ----
    li   t0, 3
    sw   t0, 0(s1)                  // MODE = 3
    li   s7, DONEB
    li   s3, 1                      // h = 1
dw_loop:
    slli t0, s3, 2
    add  t1, s7, t0                // &DONE[h]
    li   t6, 300000
dw_wait:
    lw   t0, 0(t1)
    bnez t0, dw_next
    addi t6, t6, -1
    bnez t6, dw_wait
    j    shpause_fail              // a tile never reported DONE
dw_next:
    addi s3, s3, 1
    li   t0, NHARTS
    bltu s3, t0, dw_loop

    // ---- both bursts must have measured real (nonzero) elapsed time ----
    beqz s4, shpause_fail
    beqz s5, shpause_fail

#ifdef CORE_ENABLE_ZIHINT
    // ON build: the PAUSE burst must take deterministically LONGER wall-clock
    // than the control burst (each of NITER iterations yields the bus for the
    // window). Require RCTL + MARGIN < RPAU. The window=0 negative-control seed
    // makes RPAU ~= RCTL, so RCTL+MARGIN >= RPAU there -> FAIL (control live).
    li   t0, MARGIN
    add  t0, s4, t0                // RCTL + MARGIN
    bge  t0, s5, shpause_fail      // fail unless RCTL + MARGIN < RPAU
#endif
    // OFF build (or ON + assertion held): both bursts timed, all tiles passed.
    RVTEST_PASS                    // a0 = 0xCAFEBABE

// ---------------------------------------------------------------------
// time_burst: open a phase (MODE already set) and return the free-running
// mtime elapsed until the antagonist signals PDONE. Inputs s2=PDONE,
// s6=MTIME_LO. Returns a5 = elapsed mtime lo. Clobbers t0,t1,t6,a5. Leaf.
// ---------------------------------------------------------------------
time_burst:
    lw   a5, 0(s6)                 // T0 = mtime lo (free-running)
    li   t6, 2000000              // bounded wait (broken antagonist -> FAIL via 0)
tb_wait:
    lw   t0, 0(s2)                 // PDONE
    bnez t0, tb_done
    addi t6, t6, -1
    beqz t6, tb_fail               // budget exhausted -> fail
    j    tb_wait
tb_fail:
    li   a5, 0                     // signal failure (guarded by beqz above)
    ret
tb_done:
    lw   t1, 0(s6)                 // T1 = mtime lo
    sub  a5, t1, a5               // elapsed mclk over the burst
    ret

shpause_fail:
    li   a0, 0xDEADBEEF            // explicit FAIL (RVTEST_FAIL label used once)
3:  j    3b

    // RVTEST_CODE_END is 'unimp' (traps) -- every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
