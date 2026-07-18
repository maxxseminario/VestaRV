# See LICENSE for license details.

#*****************************************************************************
# shlrsc.S  (M4b; M12 single-ROM boot rework)
#-----------------------------------------------------------------------------
# Directed LR/SC test against the SHARED-RAM window (0x10000, region 4, behind
# mp_arbiter + resv_unit). Runs on hart 0 while harts 1-3 hammer their disjoint
# words (0x10040+4*h) — hart 1's continuous traffic on 0x10044 is the REAL
# foreign-write source that kills a reservation in step 4.
#
# M12: the default tile preload (harts 1-3 running shmem_mp) is retired, so
# this test now LAUNCHES the tiles itself: hart 0 stages this TCM image once
# and launches all NHARTS-1 tiles into tile_hammer through the bootrom loader
# (mp_boot.h). tile_hammer mirrors shmem_mp phase 3 — write an incrementing
# per-hart pattern to the hart's own word, read it back, compare (so a wrongly
# committed foreign SC of 0xDEAD to 0x10044 is caught by hart 1's own
# readback, exactly as the old shmem_mp tiles policed it). Before step 4 hart 0
# waits (bounded) until it OBSERVES 0x10044 CHANGING — proof hart 1 is live —
# so the foreign write is guaranteed during the step-4 window (no new shared
# word needed for the handshake).
#
# Covers, in order:
#   1. LR/SC success on an idle shared word (+ memory updated)
#   2. SC without LR -> fail, memory NOT written (would have written before
#      the M4b core fix: SC used to store unconditionally in EXECUTE)
#   3. LR word A, SC word B -> fail (address mismatch), B untouched
#   4. LR on hart 1's hammer word, delay, SC -> fail (foreign write killed the
#      global reservation; a wrongly-committed 0xDEAD is policed by hart 1's
#      own write/readback in tile_hammer)
#   5. LR A, own plain store to A, SC A -> fail (own write kills reservation —
#      conservative resv_unit policy), memory holds the plain store's value
#   6. LR/SC success on PRIVATE memory (tohost-adjacent scratch) — local path
#      keeps working with the global unit in place
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # M12 dispatch: only hart 0 runs the directed sequence; tiles hammer.
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..3
    .option pop
    bnez s10, tile_hammer

    # hart 0: stage this TCM image once, launch all three tiles into the
    # forever-hammer (hart 1 becomes the foreign-write source for step 4).
    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_ALL(tile_hammer, 4096)

    # Wait until hart 1 is actively hammering 0x10044 (its writes change the
    # word every iteration). Bounded (M12: covers the tile ROM copy at launch).
    li   s0, 0x10044
    lw   s1, 0(s0)              # first sample
    li   t6, 100000
h1_live:
    lw   t0, 0(s0)
    bne  t0, s1, h1_ready       # value changed -> hart 1 is live
    addi t6, t6, -1
    bnez t6, h1_live
    j    shlrsc_fail
h1_ready:

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
    li   t5, 0x10044            # hart 1's hammer word (confirmed live above)
    lr.w t2, (t5)               # reserve it
    li   t6, 32                 # delay: hart 1 writes it every few mclk cycles
1:  addi t6, t6, -1
    bnez t6, 1b
    li   t3, 0xDEAD
    sc.w t4, t3, (t5)
    beqz t4, shlrsc_fail        # must FAIL (reservation killed by hart 1)
                                # (a wrongly-committed 0xDEAD is caught by
                                #  hart 1's own readback in tile_hammer)

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

    # ---- tile hammer (harts 1-3, entered from the bootrom loader; loader ABI
    # ---- gives only sp): forever write/readback a per-hart pattern to the
    # ---- hart's OWN disjoint word 0x10040+4*hartid (mirrors shmem_mp phase 3).
    # ---- hart 1's writes are the foreign-write source for hart 0's step 4;
    # ---- the readback policies against any stray foreign commit. ------------
tile_hammer:
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # re-derive
    .option pop
    li   sp, 0xBFF0
    slli t0, s10, 2
    li   t1, 0x10040
    add  s2, t1, t0             # my word 0x10040 + 4*hartid
    slli s3, s10, 24
    li   t1, 0x00C0FFEE
    xor  s3, s3, t1             # per-hart pattern base (hartid in top byte)
    li   a0, 0xCAFEBABE         # inline PASS (tb latches a0_1/2/3)
    li   s6, 0
th_loop:
    add  t3, s3, s6
    sw   t3, 0(s2)
    lw   t4, 0(s2)
    bne  t3, t4, shlrsc_fail    # a stray foreign write (e.g. 0xDEAD) mismatches
    addi s6, s6, 1              # wraps eventually — patterns just repeat
    j    th_loop

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
