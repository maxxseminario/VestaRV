# See LICENSE for license details.

#*****************************************************************************
# shspin.S  (M5a — the multi-core signature test; M12 single-ROM boot rework)
#-----------------------------------------------------------------------------
# 4-HART SPINLOCK: ALL FOUR harts contend on one LR/SC spinlock, doing a
# NON-ATOMIC read-modify-write of a shared counter inside the critical
# section. Any mutual-exclusion violation loses an update (final count wrong)
# or trips the owner-word check.
#
# M12: the retired GO/ENTRY mailboxes (0x10100/0x10110) are gone. Hart 0
# stages this TCM image once and launches all three tiles into tile_entry
# through the bootrom loader (mp_boot.h); each tile falls straight into
# lock_payload, and hart 0 falls through and contends too — all four hit the
# lock together (max contention).
#
# Shared-window map (clear of shmem 0x10000-8, shlrsc 0x1000C/0x10010,
# shmem_mp 0x10040+4*h, counter 0x10080):
#     DONE[h] = 0x10120 + 4*h            (h = 1..NHARTS-1)
#     LOCK    = 0x10120 + 4*NHARTS        (0 free, 1 held)
#     CTR     = 0x10120 + 4*NHARTS + 4    (must end EXACTLY NHARTS*32)
#     OWNER   = 0x10120 + 4*NHARTS + 8    (holder writes hartid+1, re-checks)
# Argus A3: control words placed AFTER the NHARTS-sized DONE array so it can't
# overrun them at N=18. N=4: LOCK/CTR/OWNER=0x10130/34/38; N=18: 0x10168/6C/70.
#
# LR/SC RULES (M4c post-mortem): hartid-scaled backoff after a failed acquire
# (identical harts on the fair round-robin arbiter LIVELOCK without it) and a
# BOUNDED acquire budget so a broken lock FAILS instead of riding the 100ms
# watchdog.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..3
    .option pop
    bnez s10, tile_entry        # M12: only hart 0 runs the launcher

    # M12 single-ROM boot: stage this TCM image once, launch all NHARTS-1 tiles
    # into tile_entry (mp_boot.h), then fall through and run the same payload.
    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_ALL(tile_entry, 4096)

tile_entry:                     # tiles enter here (loader ABI: only sp defined)
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # re-derive (undefined for tiles until now)
    .option pop
    li   sp, 0xBFF0             # convention (loader left 0xBFFC)

    li   s4, 0x10120                    # DONE base (DONE[h] = 0x10120 + 4*h, h=1..NHARTS-1)
    li   s7, (0x10120 + 4*NHARTS)       # LOCK   (control words placed AFTER the
    li   s8, (0x10120 + 4*NHARTS + 4)   # CTR     NHARTS-sized DONE array so the
    li   s9, (0x10120 + 4*NHARTS + 8)   # OWNER   array can't overrun them at N=18)
    # fall through — every hart runs the same payload

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
    li   t6, 100000             # bounded wait budget (M12: first wait covers 3
                                # serialized tile ROM-copies; fits 100ms watchdog)
done_wait:
    lw   t3, 0(t1)
    beq  t3, t2, done_ok
    addi t6, t6, -1
    bnez t6, done_wait
    j    shspin_fail
done_ok:
    addi s6, s6, 1
    li   t0, NHARTS
    bne  s6, t0, done_wait_loop
    lw   t3, 0(s8)
    li   t4, NHARTS*32          # NHARTS harts * 32 — lost update = wrong count
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
