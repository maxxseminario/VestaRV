# See LICENSE for license details.

# VestaRV: fault-injection and graceful-degradation demonstrator
# Four harts model four sensing channels. Harts 0, 1 and 3 run WORK_ITERS measurement passes (private-TCM busywork plus one shared-bus heartbeat bump per pass) and publish DONE; hart FAULT_HART = 2 models an electrode-fouling HANG, running briefly and then hammering the shared bus forever. It never writes DONE[2] and never sets a0, so the tb reporting it silent is expected, not a failure.
# What it proves: FORWARD PROGRESS under a babbling master, since the round-robin arbiter is fair and harts 0, 1 and 3 still complete inside the 100 ms tb watchdog; PRIVATE-TCM ISOLATION, checked by a canary hart 0 plants at 0x9000, which the babbler cannot address; and that the wedge is a genuine active fault, checked by sampling HEARTBEAT[2] twice and requiring it to advance.
# NOT claimed: protection against a wild-pointer store into a shared mailbox. With no MMU or PMP that is by convention. The modelled fault is well-behaved-but-hung, which is the realistic control-loop hang.
# Shared words: HEARTBEAT[h] = 0x10440 + 4*h, DONE[h] = 0x10440 + 4*NHARTS + 4*h (0xD09E0000 + h), BABBLE_SCRATCH = 0x10440 + 8*NHARTS, a dead word the babbler reads. The arrays are placed one after another so nothing overruns at N=18, where BABBLE lands at 0x104D0, still below the loader rows at 0x10500.
# No interrupts: pure polling and mailboxes, so the env DEFINE_IVT is left untouched and nothing extends the .ivt section.

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
