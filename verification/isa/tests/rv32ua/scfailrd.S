# See LICENSE for license details.

#*****************************************************************************
# scfailrd.S   (F-series fix pass, wave W1 — DETECTOR for finding F2)
#-----------------------------------------------------------------------------
# F2: a FAILED `sc.w` still issues a real bus READ at rs1.
#
#   vesta.vhd SC_CHECK asserts `mem_access_instr <= '1'` UNCONDITIONALLY and
#   only the byte lanes are conditional (`wen <= (others=>'1')` on the failing
#   arm).  data_addr takes `rs1_value` in SC_CHECK unconditionally, and
#   hart_tile's `sh_sel` is a PURE DECODE of data_addr — `mem_access_instr`
#   appears nowhere in it.  So a failed SC whose rs1 lands anywhere in
#   0x4000-0x7FFF performs a real, side-effecting shared-window READ.
#
# WHY A MUTEX ADDRESS, DELIBERATELY:
#   CLAUDE.md and mutex_bank.vhd's own header both say "NEVER LR/SC a mutex
#   address".  mutex_bank.vhd:20-22 states the reason exactly:
#       "a reservation-failed SC arrives here with its lanes suppressed by
#        resv_unit and would be indistinguishable from a claim-read."
#   THIS TEST DELIBERATELY DOES THE FORBIDDEN THING.  Its whole purpose is to
#   demonstrate, in silicon-accurate RTL, why that rule exists — the stray read
#   is an ATOMIC CLAIM of a lock the program never asked for.  Do not "fix" the
#   test by moving the SC off the mutex; that would delete the detector.
#
# MECHANISM OF THE FAILURE (deterministic, not probabilistic):
#   `lr.w` at LRWORD arms the reservation at LRWORD.  The `sc.w` is then aimed
#   at MUTEX0.  SC_CHECK's success predicate is
#       reservation_valid = '1' and reservation_addr = rs1_value
#   so reservation_addr (LRWORD) /= rs1 (MUTEX0) => the SC MUST fail, every
#   run, with no race.  The test PROVES it failed by checking rd /= 0 before
#   looking at the side effect (a passing SC would invalidate the whole probe).
#
# OBSERVABLE — THE SIDE EFFECT, NOT THE READ:
#   mutex_bank read = atomic return-old-and-claim, attributed to the arbiter's
#   granted master.  The verification `lw` is ITSELF a claim, so it returns the
#   PRE-EXISTING owner:
#       0 -> the mutex was still free: nobody read it. Correct.  (post-fix)
#       1 -> owner = hart 0 + 1: something on hart 0 already claimed it, and
#            the only candidate is the failed SC's stray read.  F2 FIRED.
#   The mutex is explicitly RELEASED first, so the starting state is known-free
#   rather than assumed-free.
#
# SECOND OBSERVABLE (traced runs): the tracer emits `# SCFAILRD <hdr> <addr>`
#   for exactly this event (vesta_tracer.vhd:496).  Pre-fix this test must emit
#   SCFAILRD at address 00006000; post-fix it must emit none.
#
# VERDICT
#   pre-fix : a0 = 0xDEADBEEF  (a1 = 0xF2F2F2F2, "F2 fired")
#   post-fix: a0 = 0xCAFEBABE
#   Any other a1 code on a FAIL is a setup break, not the finding:
#       a1 = 0x5E100001  shared LRWORD store/read-back broke
#       a1 = 0x5E100002  lr.w did not return the value we stored
#       a1 = 0x5E100003  the sc.w SUCCEEDED (rd == 0) — probe invalid
#
# Single hart.  Tiles 1-3 are never launched; they park in the boot ROM and the
# tb reports "tile hart(s) silent/parked", which is expected.
#
# Shared words claimed (both < 0x10500 and inside the bootrom zero range):
#     LRWORD = 0x10430   the reservation target (written before read)
#   Free band 0x10420-0x1043C sits between shexec's N=18 DONE top (0x1041C)
#   and shfault's HEARTBEAT base (0x10440) — unclaimed at N=4 and N=18.
#   MUTEX0 @0x6000 is hardware, not scratch; released on every exit path.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

#define MUTEX0   0x6000
#define LRWORD   0x10430
#define LRVAL    0x5C5C5C5C

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   s0, MUTEX0
    li   s1, LRWORD

    # ---- 0: make LRWORD a real, written shared word (read-back verified) ----
    li   t0, LRVAL
    sw   t0, 0(s1)
    lw   t1, 0(s1)
    li   a1, 0x5E100001
    bne  t1, t0, scfailrd_fail

    # ---- 1: start from a KNOWN-FREE mutex (write 0 = release) ---------------
    sw   x0, 0(s0)

    # ---- 2: arm the reservation at LRWORD -- NOT at the mutex ---------------
    lr.w t2, (s1)
    li   a1, 0x5E100002
    bne  t2, t0, scfailrd_fail

    # ---- 3: the forbidden thing: sc.w aimed at the mutex bank ---------------
    # reservation_addr (LRWORD) /= rs1 (MUTEX0) => guaranteed failure.
    li   t3, 0x11111111
    sc.w t4, t3, (s0)
    li   a1, 0x5E100003
    beqz t4, scfailrd_fail      # rd == 0 would mean the SC SUCCEEDED

    # ---- 4: did the failed SC's stray read claim the mutex? -----------------
    lw   t5, 0(s0)              # this read is itself a claim; returns OLD owner
    li   a1, 0xF2F2F2F2
    bnez t5, scfailrd_fired

    sw   x0, 0(s0)              # release what our own probe read just claimed
    RVTEST_PASS                 # a0 = 0xCAFEBABE

scfailrd_fired:
    # DELIBERATELY does NOT release: mtx0's `owner(0)` must still read "001"
    # (hart 0 + 1) when the sim stops, so the hardware itself corroborates
    # the a0 verdict.  t4 = the sc.w rd (must be nonzero = failed) and
    # t5 = the pre-existing owner the probe read (1 = F2 fired) also survive.
scfailrd_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
