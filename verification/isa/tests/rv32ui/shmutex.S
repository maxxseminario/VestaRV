# See LICENSE for license details.

# VestaRV: hardware mutex bank test
# THE MUTEX BANK AT 0x6000 IS A ONE-INSTRUCTION ACQUIRE, NO LR/SC: a READ atomically returns the old value and claims (0 means it was free and is now yours, anything else is the holder's hartid + 1), a WRITE of 0 releases, and a nonzero write is ignored. Atomicity comes from the arbiter serialising whole transactions, which is why this test lives in rv32ui and touches no 'a' extension instruction.
# Phase 1, every hart on a disjoint mutex (hart h takes MUTEX[1+h], hart 0 takes MUTEX1), proves s_master attribution: a first read returns 0 and claims, a re-read returns h+1 so a held claim-read does not disturb, a nonzero write is ignored so ownership cannot be forged, a write of 0 releases, and the cycle repeats.
# Phase 2 runs 32 critical sections per hart on MUTEX0: one-instruction acquire with hartid-scaled backoff and a bounded retry, since the livelock rule applies to any spin on the fair arbiter, then a held-readback check and a NON-atomic lw/addi/sw of the shared counter with an owner re-check inside. Hart 0 requires CTR to end at exactly NHARTS*32.
# Shared words: CTR = 0x10380 (exactly NHARTS*32), OWNER = 0x10384 (holder writes hartid + 1 and re-checks), DONE[h] = 0x10390 + 4*h (0x40BE0000 + h). CTR and OWNER sit below the DONE base so the NHARTS-sized array cannot overrun them; N=18 tops at 0x103D4.
# THE BANK HAS ONLY 16 MUTEXES, so at N=18 phase 1's MUTEX[1+hartid] indexes past MUTEX15 for harts 15 and above.

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define MUTEX_BASE 0x6000      /* mutex i at +4*i; MUTEX0 = the contended one */
#define CTR        0x10380
#define OWNER      0x10384
#define DONE_BASE  0x10390

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..3
    .option pop
    bnez s10, tile_entry        # M12: only hart 0 runs the launcher

    # M12 single-ROM boot: stage this TCM image once, launch all NHARTS-1 tiles
    # into tile_entry (mp_boot.h), then fall through and run the same body.
    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_ALL(tile_entry, 4096)

tile_entry:                     # tiles enter here (loader ABI: only sp defined)
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # re-derive (undefined for tiles until now)
    .option pop

    li   sp, 0xBFF0             # private TCM top (IRQ_SV contract)

    li   s7, MUTEX_BASE         # MUTEX0 (the contended mutex)
    li   s8, CTR
    li   s9, OWNER
    li   s4, DONE_BASE
    addi s11, s10, 1            # my owner marker (hartid+1)

    # ---- phase 1: private-mutex dance on MUTEX[1+hartid] --------------------
    addi t0, s10, 1
    slli t0, t0, 2
    add  t0, t0, s7             # &MUTEX[1+hartid] — disjoint per hart
    lw   t1, 0(t0)              # was free -> returns 0, claims for me
    bnez t1, shmutex_fail
    lw   t1, 0(t0)              # held by ME -> returns hartid+1, undisturbed
    bne  t1, s11, shmutex_fail
    li   t2, 0xDEADBEEF
    sw   t2, 0(t0)              # nonzero write: IGNORED (no ownership forging)
    lw   t1, 0(t0)              # still mine
    bne  t1, s11, shmutex_fail
    sw   zero, 0(t0)            # release
    lw   t1, 0(t0)              # free again -> 0 (and reclaims)
    bnez t1, shmutex_fail
    lw   t1, 0(t0)              # mine again
    bne  t1, s11, shmutex_fail
    sw   zero, 0(t0)            # final release

    # ---- phase 2: all four harts contend on MUTEX0 ---------------------------
    li   s6, 32                 # committed critical sections per hart
iter_loop:
    li   t6, 8192               # bounded acquire budget (broken mutex -> FAIL
                                # inside the tb's 100ms watchdog)
acquire:
    lw   t0, 0(s7)              # 1-INSN ACQUIRE: 0 = mine (claimed atomically)
    beqz t0, got_mutex
    addi t6, t6, -1
    beqz t6, shmutex_fail
    slli t1, s10, 3             # backoff = hartid*8 + 8 spins (M4c rule —
    addi t1, t1, 8              # identical spinners on the fair round-robin
1:  addi t1, t1, -1             # arbiter livelock without de-synchronization)
    bnez t1, 1b
    j    acquire
got_mutex:
    lw   t0, 0(s7)              # held-readback: MUTEX0 now reads MY marker
    bne  t0, s11, shmutex_fail
    sw   s11, 0(s9)             # OWNER = me
    lw   t2, 0(s8)              # NON-atomic RMW — only the mutex protects it
    addi t2, t2, 1
    sw   t2, 0(s8)
    lw   t3, 0(s9)              # still me? (direct mutual-exclusion check)
    bne  t3, s11, shmutex_fail
    sw   zero, 0(s7)            # release
    addi s6, s6, -1
    bnez s6, iter_loop

    beqz s10, check_total

    # ---- harts 1-3: report DONE, inline PASS, verify forever ----------------
    slli t0, s10, 2
    add  t0, t0, s4
    li   t1, 0x40BE0000
    add  t1, t1, s10
    sw   t1, 0(t0)              # DONE[h]
    li   a0, 0xCAFEBABE         # inline PASS (tb latches a0_1/2/3)
tile_verify:                    # forever: DONE must survive other traffic
    lw   t2, 0(t0)
    bne  t2, t1, shmutex_fail
    j    tile_verify

    # ---- hart 0: bounded-wait all DONEs, require CTR == 128 EXACTLY ---------
check_total:
    li   s6, 1
dw_loop:
    slli t0, s6, 2
    add  t1, t0, s4             # DONE[h]
    li   t2, 0x40BE0000
    add  t2, t2, s6
    li   t6, 100000             # bounded (M12: first wait covers 3 serialized
                                # tile ROM-copies at launch; fits 100ms watchdog)
dw_poll:
    lw   t3, 0(t1)
    beq  t3, t2, dw_ok
    addi t6, t6, -1
    bnez t6, dw_poll
    j    shmutex_fail
dw_ok:
    addi s6, s6, 1
    li   t0, NHARTS
    bne  s6, t0, dw_loop

    lw   t3, 0(s8)
    li   t4, NHARTS*32          # NHARTS harts * 32 — lost update = wrong count
    bne  t3, t4, shmutex_fail

    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin

shmutex_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
