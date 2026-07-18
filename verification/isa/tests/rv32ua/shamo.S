# See LICENSE for license details.

#*****************************************************************************
# shamo.S  (M8 — the grant-locking signature test; M12 single-ROM boot rework)
#-----------------------------------------------------------------------------
# CROSS-HART AMO ATOMICITY: all four harts run this image. M12: tiles are NO
# LONGER preloaded — hart 0 stages this TCM image once, launches all three
# tiles into tile_entry through the bootrom loader (mp_boot.h), then falls
# through and runs the same body itself. Harts 1-3 hammer 64 amoadd.w
# increments EACH into one shared counter once launched — a full 3-way AMO
# contention storm — and hart 0 adds its own 64 under whatever traffic remains
# and requires the counter to equal EXACTLY 4*64 = 256.
#
# An AMO is a read+write TRANSACTION PAIR on the mp_arbiter; without M8
# grant-locking another master can slip a write between a pair's read and
# write and the increment is LOST (counter < 256 -> bounded poll expires ->
# FAIL). Overshoot (> 256) fails explicitly. Hart 0 also runs a deterministic
# amoswap.w old-value chain on a word nobody else touches, plus a DIRECTED
# PROBE for the M8 EXECUTE-phase garbage-address bug: an amoadd whose rs1+rs2
# lands in REGION 4 at a DIFFERENT word (pre-fix, the dispatch-cycle access
# read THAT word into sh_rdata_reg and AMO_READ consumed it — old value
# corrupt). NEGATIVE-CONTROL PROVEN both ways: with the vesta.vhd fix disabled
# the probe FAILS and with it enabled it PASSES. (The swap chain alone CANNOT
# catch it: amoswap's dispatch ALU is pass-B = the swap DATA, off-region; and
# small-rs2 amoadds alias into the SAME word.)
#
# NO retry loops here — an AMO always completes (that is the point) — so no
# backoff/livelock machinery is needed, unlike every LR/SC test.
#
# Shared-window map (next free was 0x103A0; RAM ends 0x103FF):
#     CTR     = 0x103A0   (must end EXACTLY NHARTS*64)
#     SWP     = 0x103A4   (hart 0's private amoswap chain)
#     PROBE   = 0x103B0   (garbage-address probe; DONE's h=0 slot, unused)
#     DONE[h] = 0x103B0 + 4*h, h=1..NHARTS-1  (0xA30D0000+h)
# The probe also READS 0x103D0 (= PROBE + 0x20, the garbage address): that
# word must never hold 0x22222222 (it is only read, never written, by the
# probe). At N=18 DONE[8] == 0x103D0 (0xA30D0008 != 0x22222222, so the probe
# stays valid both fix-present and fix-absent); the array ends at DONE[17] =
# 0x103F4 (< the 0x103FF window end). CTR/SWP sit below the DONE base.
# Next free: 0x103C0 (N=4) — but at N=18 the DONE array itself reaches 0x103F4.
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
    # into tile_entry (mp_boot.h), then fall through and run the same body.
    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_ALL(tile_entry, 4096)

tile_entry:                     # tiles enter here (loader ABI: only sp defined)
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # re-derive (undefined for tiles until now)
    .option pop
    li   sp, 0xBFF0             # convention (loader left 0xBFFC)

    li   s7, 0x103A0            # CTR
    li   s8, 0x103A4            # SWP
    li   s9, 0x103B0            # DONE base

    .option push
    .option arch, +a

    # ---- ALL harts: 64 atomic increments (harts 1-3 contend from t=0) ----
    li   s6, 64
add_loop:
    li   t1, 1
    amoadd.w t2, t1, (s7)
    addi s6, s6, -1
    bnez s6, add_loop

    beqz s10, hart0_verify

    # ---- harts 1-3: report DONE, pass inline, verify forever ----
    slli t0, s10, 2
    add  t3, s9, t0             # my DONE word
    li   t4, 0xA30D0000
    add  t4, t4, s10
    sw   t4, 0(t3)
    li   a0, 0xCAFEBABE         # inline PASS (no terminal spin — keep verifying)
forever_verify:
    lw   t5, 0(t3)
    bne  t5, t4, shamo_fail     # DONE word corrupted post-PASS
    j    forever_verify

    # ---- hart 0: swap-chain data check, then exact-count + DONE checks ----
hart0_verify:
    # deterministic amoswap old-value chain on SWP (zero-init, single writer):
    # proves the AMO read returns the ADDRESSED word (the pre-M8 EXECUTE-phase
    # access rode rs1+rs2 and returned the wrong word through sh_rdata_reg)
    li   t1, 0x0000BEEF
    amoswap.w t2, t1, (s8)
    bnez t2, shamo_fail         # old value must be the zero-init
    li   t3, 0x600DF00D
    amoswap.w t2, t3, (s8)
    bne  t2, t1, shamo_fail     # old value must be the first swap's data
    lw   t2, 0(s8)
    bne  t2, t3, shamo_fail     # plain load sees the last swap

    # DIRECTED PROBE (the M8 garbage-address bug): rs1=0x103B0, rs2=0x20 →
    # dispatch-cycle ALU result 0x103D0 = region 4, DIFFERENT word (zero).
    # Pre-fix the old value came back as M[0x103D0]=0, not the preload.
    li   t0, 0x103B0            # PROBE
    li   t1, 0x22222222
    sw   t1, 0(t0)
    li   t2, 0x20
    amoadd.w t3, t2, (t0)
    bne  t3, t1, shamo_fail     # old value must be the preload, not M[0x103D0]
    lw   t3, 0(t0)
    li   t4, 0x22222242
    bne  t3, t4, shamo_fail     # +0x20 written back to PROBE itself

    # counter must reach EXACTLY 256; bounded poll (budget rule — a lost
    # update must FAIL inside the 100ms tb watchdog, not ride it)
    li   t5, NHARTS*64
    li   t6, 100000             # M12: covers the serialized tile ROM-copies + the
                                # tiles' 64 increments each after launch
ctr_poll:
    lw   t3, 0(s7)
    beq  t3, t5, ctr_full
    bgt  t3, t5, shamo_fail     # overshoot: double-counted increment
    addi t6, t6, -1
    bnez t6, ctr_poll
    j    shamo_fail             # poll budget expired: lost update(s)
ctr_full:

    # all three tile harts must have reported DONE. Bounded poll (M12: the tile
    # that commits the 256th increment writes DONE a few cycles behind hart 0
    # seeing CTR==256 — the old preload had the tiles finished ms earlier).
    li   s6, 1
done_chk:
    slli t0, s6, 2
    add  t3, s9, t0
    li   t5, 0xA30D0000
    add  t5, t5, s6
    li   t6, 100000
dchk_poll:
    lw   t4, 0(t3)
    beq  t4, t5, dchk_ok
    addi t6, t6, -1
    bnez t6, dchk_poll
    j    shamo_fail
dchk_ok:
    addi s6, s6, 1
    li   t0, NHARTS
    bne  s6, t0, done_chk

    .option pop

    RVTEST_PASS                 # a0 = 0xCAFEBABE

shamo_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
