# See LICENSE for license details.

#*****************************************************************************
# shfault.S  (Castalia fault-injection / graceful-degradation demonstrator)
#-----------------------------------------------------------------------------
# Empirical backing for the "fault-tolerant" claim in the Castalia paper:
# wedge ONE channel's tile and show the other three keep making forward
# progress and reporting, and that the wedged tile cannot corrupt a healthy
# tile's private state.
#
# Four harts model four sensing channels. Harts 0, 1, 3 are HEALTHY channels
# that run a fixed number of "measurement" passes (private-TCM busywork + one
# shared-bus heartbeat bump per pass) and then publish DONE. Hart FAULT_HART
# (=2) models an electrode-fouling HANG: it runs briefly, then enters an
# infinite loop that keeps HAMMERING the shared bus (a store + a load every
# few instructions) forever, never advancing to completion. It never writes
# DONE[2] and never sets a0_2 (the tb reports it silent/parked — not a FAIL).
#
# What this proves (and, deliberately, what it does NOT):
#   * FORWARD PROGRESS under a babbling master. The round-robin arbiter is
#     fair, so hart 2 hammering the shared window cannot STARVE harts 0/1/3:
#     they still complete WORK_ITERS passes and report DONE within the 100ms
#     tb watchdog. This is the load-bearing result.
#   * PRIVATE-TCM ISOLATION. Hart 0 plants a canary in its own TCM (0x9000)
#     and checks it survives — the babbler physically cannot address another
#     tile's private TCM.
#   * The wedge is a GENUINE active fault, not a benign park: hart 0 samples
#     HEARTBEAT[2] twice and requires it to advance (hart 2 is alive and
#     contending, not halted).
#   NOT claimed: protection against a wild-pointer store INTO shared mailboxes.
#   With no MMU/PMP that is by-convention, exactly as the paper states. The
#   modelled fault is well-behaved-but-hung (spins on the bus), which is the
#   realistic control-loop hang.
#
# Shared words (>= 0x10440, clear of the whole prior mailbox ledger and of the
# bootrom loader rows; all zeroed by the bootrom at boot):
#     HEARTBEAT[h]   = 0x10440 + 4*h             healthy +1/pass; hart 2 forever
#     DONE[h]        = 0x10440 + 4*NHARTS + 4*h  0xD09E0000+h on channel done
#     BABBLE_SCRATCH = 0x10440 + 8*NHARTS        dead word the babbler READS
# Argus A3: DONE is placed AFTER the NHARTS-sized HEARTBEAT array and BABBLE
# after DONE, so nothing overruns at N=18 (the old fixed 0x10450/0x10460 had
# HEARTBEAT[4..] running into DONE at N>4). N=4: DONE 0x10450, BABBLE 0x10460
# (unchanged). N=18: HEARTBEAT 0x10440..0x10484, DONE 0x10488..0x104CC,
# BABBLE 0x104D0 — all < the loader rows at 0x10500.
#
# No interrupts are used (pure polling + mailboxes), so the env DEFINE_IVT
# (slots 0-82) is left untouched — nothing extends the .ivt section here.
#
# Gate: hart 0 launches the three tiles, does its own channel work, then
# verifies DONE[1]/DONE[3] arrived, DONE[2] did not, hart 2 is still spinning,
# and its own TCM canary is intact -> RVTEST_PASS. Any violation -> RVTEST_FAIL.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define FAULT_HART   2          // the wedged channel (change to sweep it)
#define WORK_ITERS   32         // healthy per-channel measurement passes

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..3
    .option pop

    # common per-hart bases
    li   sp, 0xBFF0             # private TCM top (convention; no IRQs here)
    li   s2, 0x10440            # HEARTBEAT base
    li   s3, (0x10440 + 4*NHARTS)  # DONE base (after NHARTS-sized HEARTBEAT)
    li   s6, 0xD09E0000         # DONE magic base

    bnez s10, tile_entry        # only hart 0 launches + verifies

    # ------------------- hart 0: gate / channel / verifier ----------------
    # plant a private-TCM canary (prove no cross-tile corruption of our TCM)
    li   t0, 0x9000
    li   t1, 0xCA11AB1E
    sw   t1, 0(t0)

    MP_STAGE_IMAGE(4096)                    # stage the TCM image once (0x18000)
    MP_LAUNCH_ALL(tile_entry, 4096)         # launch all NHARTS-1 tiles (channels)

    # hart 0 runs its OWN channel work (adds real contention with the babbler)
    mv   a1, s10                # hartid 0
    li   a2, WORK_ITERS
    jal  ra, channel_work
    sw   s6, 0(s3)             # DONE[0] = 0xD09E0000 (our own completion)

    # ---- forward-progress proof: healthy tiles 1 and 3 MUST finish -------
    li   s7, 1
    jal  ra, wait_done          # bounded-wait DONE[1]
    li   s7, 3
    jal  ra, wait_done          # bounded-wait DONE[3]

    # ---- faulted tile 2 must NOT have completed --------------------------
    li   t0, (0x10440 + 4*NHARTS) + 4*FAULT_HART   # DONE[FAULT_HART]
    lw   t1, 0(t0)
    li   t2, 0xD09E0000 + FAULT_HART
    beq  t1, t2, shfault_fail   # if it "finished", the fault model is invalid

    # ---- faulted tile 2 must be ACTIVELY spinning (alive, not halted) ----
    li   s8, 0x10440 + 4*FAULT_HART   # HEARTBEAT[2], bumped forever by babbler
    lw   s9, 0(s8)              # sample 1
    li   t2, 4000              # bounded settle so the babbler advances
1:  addi t2, t2, -1
    bnez t2, 1b
    lw   t3, 0(s8)              # sample 2
    beq  t3, s9, shfault_fail   # unchanged => it HALTED, not an active wedge

    # ---- our private TCM canary must be intact ---------------------------
    li   t0, 0x9000
    lw   t1, 0(t0)
    li   t2, 0xCA11AB1E
    bne  t1, t2, shfault_fail

    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin (the run's gate)

# --------------------------------------------------------------------------
# tiles enter here (loader ABI: only sp defined). Re-derive hartid.
tile_entry:
    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    li   sp, 0xBFF0
    li   s2, 0x10440
    li   s3, (0x10440 + 4*NHARTS)   # DONE base (after NHARTS-sized HEARTBEAT)
    li   s6, 0xD09E0000

    li   t0, FAULT_HART
    beq  s10, t0, wedge         # the faulted channel babbles forever

    # ---- healthy tile: run channel work, publish DONE, then hold it ------
    mv   a1, s10
    li   a2, WORK_ITERS
    jal  ra, channel_work
    slli t0, s10, 2
    add  t0, s3, t0             # DONE[h]
    add  t1, s6, s10           # 0xD09E0000 + h
    sw   t1, 0(t0)             # publish completion
    li   a0, 0xCAFEBABE         # tb latches a0_h (this channel is reporting)
hold:
    lw   t2, 0(t0)             # DONE must survive the babbler's bus traffic
    bne  t2, t1, shfault_fail
    j    hold

    # ---- the wedged channel: alive but hung, hammering the shared bus ----
wedge:
    slli s8, s10, 2
    add  s8, s2, s8            # HEARTBEAT[FAULT_HART] (proof-of-life counter)
    li   s9, (0x10440 + 8*NHARTS)  # BABBLE_SCRATCH: a dead word to READ
babble:
    lw   t0, 0(s8)
    addi t0, t0, 1
    sw   t0, 0(s8)            # bump my heartbeat ...
    lw   t1, 0(s9)            # ... and keep pounding the shared bus, forever
    j    babble               # never DONE, never a0 (tb: silent/parked)

# --------------------------------------------------------------------------
# channel_work(a1=hartid, a2=iters): private-TCM busywork + one shared
# heartbeat bump per pass. Models a per-channel CV measurement; the shared
# bump both advances the heartbeat and creates real arbiter contention.
# Clobbers t0-t2, a2. Preserves s-registers and ra.
channel_work:
    slli t0, a1, 2
    add  t0, s2, t0            # HEARTBEAT[hartid]
cw_pass:
    li   t1, 8                 # private "feature extraction" (stays in TCM)
cw_inner:
    addi t1, t1, -1
    bnez t1, cw_inner
    lw   t2, 0(t0)             # shared touch through the arbiter
    addi t2, t2, 1
    sw   t2, 0(t0)
    addi a2, a2, -1
    bnez a2, cw_pass
    ret

# --------------------------------------------------------------------------
# wait_done(s7=hartid): bounded-wait DONE[s7] == 0xD09E0000+s7, else FAIL.
# Budget 30000 stays inside the 100ms tb watchdog even under babbler
# contention (each poll iter is a light shared read; cf. the shspin budgets).
# Clobbers t0-t3. Preserves s-registers.
wait_done:
    slli t0, s7, 2
    add  t0, s3, t0           # DONE[s7]
    add  t1, s6, s7           # expected 0xD09E0000+s7
    li   t2, 30000
wd_loop:
    lw   t3, 0(t0)
    beq  t3, t1, wd_ok
    addi t2, t2, -1
    bnez t2, wd_loop
    j    shfault_fail
wd_ok:
    ret

shfault_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
