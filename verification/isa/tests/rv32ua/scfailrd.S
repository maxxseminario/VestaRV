# See LICENSE for license details.

# VestaRV: detector for a failed `sc.w` still issuing a real bus read
# THE DEFECT: SC_CHECK asserts mem_access_instr UNCONDITIONALLY and only the byte lanes are conditional, data_addr takes rs1_value in SC_CHECK unconditionally, and hart_tile's sh_sel is a PURE DECODE of data_addr in which mem_access_instr appears nowhere. So a failed store-conditional whose rs1 lands anywhere in 0x4000-0x7FFF performs a real, side-effecting shared-window READ.
# THE SC IS AIMED AT A MUTEX ADDRESS DELIBERATELY. The house rule is never to LR/SC a mutex address, precisely because a reservation-failed SC arrives with its lanes suppressed and is indistinguishable from a claim-read. THIS TEST DOES THE FORBIDDEN THING ON PURPOSE, to demonstrate why the rule exists: the stray read is an atomic claim of a lock the program never asked for. DO NOT "FIX" THE TEST BY MOVING THE SC OFF THE MUTEX; that deletes the detector.
# The failure is deterministic, not probabilistic: `lr.w` arms the reservation at LRWORD and the `sc.w` is aimed at MUTEX0, and SC_CHECK's success predicate requires reservation_addr to equal rs1_value, so the SC must fail every run with no race. The test proves it failed by checking rd is nonzero BEFORE looking at the side effect, since a passing SC would invalidate the whole probe.
# THE OBSERVABLE IS THE SIDE EFFECT, NOT THE READ: a mutex read is an atomic return-old-and-claim attributed to the granted master, and the verification load is itself a claim, so it returns the PRE-EXISTING owner. Reading 0 means the mutex was still free and nobody read it; reading hart 0 + 1 means something on hart 0 already claimed it and the only candidate is the failed SC's stray read. The mutex is explicitly RELEASED first, so the starting state is known-free rather than assumed-free. In traced runs the tracer emits an SCFAILRD record at address 00006000 for exactly this event.
# Verdicts: a0 = 0xCAFEBABE passes; a0 = 0xDEADBEEF with a1 = 0xF2F2F2F2 means the stray read fired. Other a1 codes are setup breaks: 0x5E100001 the shared LRWORD store or read-back broke, 0x5E100002 the lr.w did not return the value stored, 0x5E100003 the sc.w succeeded so the probe is invalid.
# Single hart: tiles are never launched and park in the boot ROM, which the tb reports as silent or parked. Shared words, both below 0x10500 and inside the bootrom zero range: LRWORD = 0x10430, the reservation target, written before read. MUTEX0 at 0x6000 is hardware rather than scratch and is released on every exit path.

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
