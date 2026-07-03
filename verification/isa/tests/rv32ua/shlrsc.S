# See LICENSE for license details.

#*****************************************************************************
# shlrsc.S  (M4b)
#-----------------------------------------------------------------------------
# Directed LR/SC test against the SHARED-RAM window (0x10000, region 4, behind
# mp_arbiter + resv_unit). Runs on hart 0 via SPI boot while harts 1-3 hammer
# their shmem_mp words (0x10044/48/4C) — hart 1's continuous traffic is used
# as a REAL foreign-write source to kill a reservation.
#
# Covers, in order:
#   1. LR/SC success on an idle shared word (+ memory updated)
#   2. SC without LR -> fail, memory NOT written (would have written before
#      the M4b core fix: SC used to store unconditionally in EXECUTE)
#   3. LR word A, SC word B -> fail (address mismatch), B untouched
#   4. LR on hart 1's hammer word, delay, SC -> fail (foreign write killed the
#      global reservation; the suppressed write is policed by hart 1's own
#      double-readback — if our 0xDEAD ever committed, hart 1 latches FAIL)
#   5. LR A, own plain store to A, SC A -> fail (own write kills reservation —
#      conservative resv_unit policy), memory holds the plain store's value
#   6. LR/SC success on PRIVATE memory (tohost-adjacent scratch) — local path
#      keeps working with the global unit in place
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   t0, 0x1000C            # idle shared word (shmem uses 0x10000/4/8;
                                # shmem_mp harts use 0x10040+)

    # ---- 1. LR/SC success path ----
    li   t1, 77
    sw   t1, 0(t0)
    lr.w t2, (t0)
    li   t1, 77
    bne  t2, t1, shlrsc_fail    # LR must read the stored value
    li   t3, 99
    sc.w t4, t3, (t0)
    bnez t4, shlrsc_fail        # SC must succeed (rd = 0)
    lw   t2, 0(t0)
    bne  t2, t3, shlrsc_fail    # memory must hold the SC value

    # ---- 2. SC without a reservation -> fail, no write ----
    li   t3, 55
    sc.w t4, t3, (t0)
    beqz t4, shlrsc_fail        # must FAIL (rd != 0)
    lw   t2, 0(t0)
    li   t1, 99
    bne  t2, t1, shlrsc_fail    # memory must be UNCHANGED

    # ---- 3. address-mismatch SC -> fail, target untouched ----
    li   t5, 0x10010            # word B (idle)
    li   t1, 1111
    sw   t1, 0(t5)
    lr.w t2, (t0)               # reserve word A
    li   t3, 2222
    sc.w t4, t3, (t5)           # SC to word B
    beqz t4, shlrsc_fail        # must FAIL
    lw   t2, 0(t5)
    li   t1, 1111
    bne  t2, t1, shlrsc_fail    # B untouched

    # ---- 4. foreign write kills the reservation (resv_unit) ----
    li   t5, 0x10044            # hart 1's shmem_mp hammer word
    lr.w t2, (t5)               # reserve it
    li   t6, 32                 # delay: hart 1 writes it every ~15 mclk cycles
1:  addi t6, t6, -1
    bnez t6, 1b
    li   t3, 0xDEAD
    sc.w t4, t3, (t5)
    beqz t4, shlrsc_fail        # must FAIL (reservation killed by hart 1)
                                # (suppression policed by hart 1's readbacks)

    # ---- 5. own plain store between LR and SC -> fail ----
    lr.w t2, (t0)
    li   t1, 4444
    sw   t1, 0(t0)              # own write kills own reservation (conservative)
    li   t3, 5555
    sc.w t4, t3, (t0)
    beqz t4, shlrsc_fail        # must FAIL
    lw   t2, 0(t0)
    li   t1, 4444
    bne  t2, t1, shlrsc_fail    # memory holds the plain store's value

    # ---- 6. private-memory LR/SC still works ----
    la   t0, private_scratch
    li   t1, 616
    sw   t1, 0(t0)
    lr.w t2, (t0)
    li   t1, 616
    bne  t2, t1, shlrsc_fail
    li   t3, 717
    sc.w t4, t3, (t0)
    bnez t4, shlrsc_fail        # success expected
    lw   t2, 0(t0)
    bne  t2, t3, shlrsc_fail

    RVTEST_PASS                 # a0 = 0xCAFEBABE

shlrsc_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
    .align 4
private_scratch:
    .word 0
RVTEST_DATA_END
