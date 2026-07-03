# See LICENSE for license details.

#*****************************************************************************
# shspin.S  (M5a — the multi-core signature test)
#-----------------------------------------------------------------------------
# 4-HART SPINLOCK: park/release (soft-CLINT mailboxes, as shboot.S) and then
# ALL FOUR harts contend on one LR/SC spinlock, doing a NON-ATOMIC
# read-modify-write of a shared counter inside the critical section. Any
# mutual-exclusion violation loses an update (final count wrong) or trips the
# owner-word check. Hart 0 releases harts 1-3 BACK-TO-BACK (max contention;
# shboot covers the staggered/park-verified flow) and takes part itself.
#
# Shared-window map (clear of shmem 0x10000-8, shlrsc 0x1000C/0x10010,
# shmem_mp 0x10040+4*h, counter 0x10080; shboot mailboxes reused here):
#     GO[h]/ENTRY[h]/DONE[h] = 0x10100/0x10110/0x10120 + 4*h
#     LOCK  = 0x10140   (0 free, 1 held)
#     CTR   = 0x10144   (must end EXACTLY 4*32 = 128)
#     OWNER = 0x10148   (holder writes hartid+1, re-checks before release)
#
# LR/SC RULES (M4c post-mortem): hartid-scaled backoff after a failed acquire
# (identical harts on the fair round-robin arbiter LIVELOCK without it) and a
# BOUNDED acquire budget so a broken lock FAILS instead of riding the 100ms
# watchdog.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..3
    .option pop

    li   s2, 0x10100            # GO base
    li   s3, 0x10110            # ENTRY base
    li   s4, 0x10120            # DONE base
    li   s5, 0x600DB007         # GO release magic
    li   s7, 0x10140            # LOCK
    li   s8, 0x10144            # CTR
    li   s9, 0x10148            # OWNER

    beqz s10, releaser

    # ---- harts 1-3: park until released, then jump to ENTRY ----
    slli t0, s10, 2
    add  t1, s2, t0             # my GO word
park_loop:
    lw   t2, 0(t1)
    bne  t2, s5, park_loop
    add  t1, s3, t0
    lw   t2, 0(t1)              # entry PC
    jalr x0, t2, 0

    # ---- hart 0: release ALL three back-to-back, then contend itself ----
releaser:
    li   s6, 1
rel_loop:
    slli t0, s6, 2
    la   t3, lock_payload
    add  t4, s3, t0             # ENTRY[h] first...
    sw   t3, 0(t4)
    add  t4, s2, t0             # ...then GO[h]
    sw   s5, 0(t4)
    addi s6, s6, 1
    li   t0, 4
    bne  s6, t0, rel_loop
    # fall through — hart 0 runs the same payload

lock_payload:
    .option push
    .option arch, +a
    li   s6, 32                 # committed critical sections per hart
    addi s11, s10, 1            # my owner marker (nonzero)
iter_loop:
    li   t6, 4096               # bounded acquire budget (broken lock -> FAIL);
                                # sized to trip well inside the tb's 100ms
                                # watchdog at 24MHz (65536 would ride past it)
acquire:
    lr.w t0, (s7)
    bnez t0, acq_backoff        # held by someone
    li   t1, 1
    sc.w t0, t1, (s7)
    beqz t0, got_lock           # committed the 0->1 transition
acq_backoff:
    addi t6, t6, -1
    beqz t6, shspin_fail
    slli t1, s10, 3             # backoff = hartid*8 + 8 spins (M4c rule)
    addi t1, t1, 8
1:  addi t1, t1, -1
    bnez t1, 1b
    j    acquire
got_lock:
    sw   s11, 0(s9)             # OWNER = me
    lw   t2, 0(s8)              # NON-atomic RMW — only the lock protects it
    addi t2, t2, 1
    sw   t2, 0(s8)
    lw   t3, 0(s9)              # still me? (direct mutual-exclusion check)
    bne  t3, s11, shspin_fail
    sw   x0, 0(s7)              # release (plain store)
    addi s6, s6, -1
    bnez s6, iter_loop
    .option pop

    beqz s10, check_total

    # ---- harts 1-3: report DONE, inline PASS, park quietly ----
    slli t0, s10, 2
    add  t1, s4, t0
    li   t2, 0xD00E0000
    add  t2, t2, s10
    sw   t2, 0(t1)              # DONE[h]
    li   a0, 0xCAFEBABE         # inline PASS (tb latches a0_1/2/3)
quiet_spin:
    j    quiet_spin

    # ---- hart 0: wait for all DONEs (bounded), require CTR == 128 EXACTLY ----
check_total:
    li   s6, 1
done_wait_loop:
    slli t0, s6, 2
    add  t1, s4, t0             # DONE[h]
    li   t2, 0xD00E0000
    add  t2, t2, s6
    li   t6, 20000              # bounded wait budget (fits the 100ms watchdog)
done_wait:
    lw   t3, 0(t1)
    beq  t3, t2, done_ok
    addi t6, t6, -1
    bnez t6, done_wait
    j    shspin_fail
done_ok:
    addi s6, s6, 1
    li   t0, 4
    bne  s6, t0, done_wait_loop
    lw   t3, 0(s8)
    li   t4, 128                # 4 harts * 32 — lost update = wrong count
    bne  t3, t4, shspin_fail

    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin

shspin_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
