# See LICENSE for license details.

# VestaRV: multi-hart atomic counter, the cross-hart LR/SC proof
# Hart 0 stages this TCM image once, launches every tile into a payload that mirrors the shared-RAM contention test, then commits its own 64 LR/SC increments under the tiles' live hammer traffic and requires the counter at 0x10080 to equal EXACTLY NHARTS*64. A lost update leaves the counter short forever, so the wait spin never exits and the testbench watchdog fails the run; a double commit overshoots and fails explicitly.
# A hart whose store-conditional fails 64 times consecutively declares livelock and fails: the serialising round-robin arbiter guarantees forward progress, but identical tiles need hartid-scaled backoff to de-synchronise.
# THE TILE PAYLOAD COMMITS EXACTLY 64 INCREMENTS AND THEN NEVER RE-TOUCHES THE COUNTER, hammering its own disjoint word forever instead, so hart 0's exact count check is never disturbed while contention stays live.
# The disjoint hammer word is 0x10090 + 4*hartid. The base must stay clear of the atomic counter at 0x10080, which a 0x10040 base collides with at hart 16; the N=18 span is 0x10090..0x100D4, inside the bootrom-zeroed 0x10000-0x107FF range.

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # M12 dispatch: only hart 0 launches; tiles enter tile_payload directly.
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..3
    .option pop
    bnez s10, tile_payload

    # hart 0: stage this TCM image once, launch all three tiles into the LR/SC
    # hammer, then commit its own 64 increments and require 256 total.
    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_ALL(tile_payload, 4096)

    li   s7, 0x10080            # common atomic counter (word 32 of the window)
    li   s8, 64                 # increments to commit
    li   s9, 64                 # consecutive-failure budget (livelock detector)

count_loop:
    lr.w t3, (s7)
    addi t3, t3, 1
    sc.w t4, t3, (s7)
    beqz t4, count_ok           # committed
    addi s9, s9, -1
    beqz s9, shcount_fail
    li   t3, 4                  # backoff (symmetry breaker; hart 0 arrives late
1:  addi t3, t3, -1             # via its own start after launching the tiles)
    bnez t3, 1b
    j    count_loop
count_ok:
    li   s9, 64
    addi s8, s8, -1
    bnez s8, count_loop

    # ---- all NHARTS harts contributed: counter must reach EXACTLY NHARTS*64 ----
    li   t5, NHARTS*64
wait_full:
    lw   t3, 0(s7)
    blt  t3, t5, wait_full      # lost update -> spins forever -> watchdog
    bne  t3, t5, shcount_fail   # overshoot -> double commit

    RVTEST_PASS                 # a0 = 0xCAFEBABE

    # ---- tile payload (harts 1-3, entered from the bootrom loader; loader ABI
    # ---- gives only sp): 64 LR/SC increments on the SAME 0x10080 counter
    # ---- (mirrors shmem_mp phase 2), then a0 = PASS and a harmless forever-
    # ---- hammer on the hart's OWN disjoint word (shmem_mp phase 3). ---------
tile_payload:
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # re-derive
    .option pop
    li   sp, 0xBFF0
    li   s7, 0x10080            # common atomic counter
    li   s8, 64                 # increments to commit
    li   s9, 64                 # consecutive-failure budget
tcount_loop:
    lr.w t3, (s7)
    addi t3, t3, 1
    sc.w t4, t3, (s7)
    beqz t4, tcount_ok          # committed
    addi s9, s9, -1
    beqz s9, shcount_fail
    slli t3, s10, 3             # hartid-scaled backoff = hartid*8 + 8 spins
    addi t3, t3, 8              # (M4c: identical tiles livelock without it)
1:  addi t3, t3, -1
    bnez t3, 1b
    j    tcount_loop
tcount_ok:
    li   s9, 64
    addi s8, s8, -1
    bnez s8, tcount_loop

    # committed 64 -> declare PASS, then hammer own disjoint word FOREVER
    # (keeps three live masters contending, exactly as the old preload did).
    li   a0, 0xCAFEBABE         # inline PASS (tb latches a0_1/2/3)
    slli t1, s10, 2
    li   t2, 0x10090
    add  s2, t2, t1             # my disjoint word 0x10090 + 4*hartid (rebased
    slli s3, s10, 24
    li   t2, 0x00C0FFEE
    xor  s3, s3, t2             # per-hart pattern base
    li   s6, 0
thammer:
    add  t3, s3, s6
    sw   t3, 0(s2)
    lw   t4, 0(s2)
    bne  t3, t4, shcount_fail
    addi s6, s6, 1              # wraps eventually — patterns just repeat
    j    thammer

shcount_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
