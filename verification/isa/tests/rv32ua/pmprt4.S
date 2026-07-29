# See LICENSE for license details.

#*****************************************************************************
# pmprt4.S   (P3 RED TEAM — EXHAUSTIVE NAPOT / NA4 / TOR BOUNDARY + PRIORITY)
#-----------------------------------------------------------------------------
# ON-ONLY DIRECTED TEST (needs a trapCsr+umode+pmp build).  privpmp probes ONE
# NAPOT size (16 byte) from two sides; this file walks the whole decode of
# pmp_unit.vhd's `pmp_match` / `pmp_check` (hdl/common/vesta/pmp_unit.vhd:
# 137-223) with a two-sided probe at EVERY boundary it owns:
#
#   A  NA4 exactness                       (a = pmpaddr, 4 bytes, both sides)
#   B  entry 8 and entry 15                (pmpcfg2/pmpcfg3 packing + the
#                                           30-bit pmp_addr_flat slicing at
#                                           the TOP index — an off-by-one in
#                                           the flattening shifts the bank)
#   C  NAPOT 8 byte    (pmpaddr low bit 0 clear)
#   D  NAPOT 4 KiB     (nine low ones then a zero)
#   E  NAPOT pmpaddr = 0    THE DEGENERATE CASE: `P xor (P+1)` = 1, so this is
#                           an 8-BYTE region at address 0, not NA4-at-0 and not
#                           the whole space.  Probed on both sides.
#   F  NAPOT all-ones       the full-span rule (P+1 wraps to 0, mask = all
#                           ones), with a lower NA4 hole punched through it
#   G  TOR entry 0's implicit base 0, and the exclusive/inclusive boundary
#      pair: a == pmpaddr[i-1] is IN, a == pmpaddr[i] is OUT
#   H  TOR NULL REGION      pmpaddr[i-1] > pmpaddr[i] must match NOTHING
#   I  TOR predecessor OFF  the predecessor's VALUE is still the base (the
#                           discriminator is an address BELOW the base, which
#                           a "base = 0 when the predecessor is OFF" reading
#                           would wrongly cover)
#   J  PRIORITY, 3+ deep, both polarities: lowest-numbered match decides ALONE
#   K  LOCKED HIGH MUST NOT RESCUE A LOWER DENY, in M-mode.  LAST in the file
#      (a lock releases only at reset).
#
# METHOD.  Every probe is the same subroutine: a load performed with
# mstatus.MPRV=1 / MPP=U, i.e. the DATA privilege is U while the instruction
# fetch stays M (the privpmpmx trick — no U code region, no fetch fence, and
# the unlocked entries never constrain M so the test's own machinery is
# untouched).  The subroutine returns a1 = 0 GRANTED / 1 DENIED.  PHASE K
# additionally uses an M-view probe (MPRV=0) because a LOCK is the only thing
# that constrains M.
#
# All probe addresses are in the shared bulk RAM (0x10000-0x1FFFF) or the boot
# ROM (0x0-0x3FFF) — never >= 0x20000, which is the XIP flash window.
#
# BOUNDEDNESS: no loop anywhere; every probe returns through `ret`, from the
# fault path as well as the clean path.
#
# REGISTER CONTRACT:
#   a0 probe address   a1 probe verdict   ra probe return
#   s3 trap counter    s4/s5/s6 cause/mepc/mtval    s7 handler resume PC
#   t4 CHECK ID
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, rt4_fail

#if defined(CORE_ENABLE_TRAPCSR) && defined(CORE_ENABLE_UMODE) && defined(CORE_ENABLE_PMP)

    .option push
    .option arch, +zicsr

    li   sp, 0xBFF0
    li   s3, 0

    li   t4, 1
    la   t0, rt4_handler
    csrw 0x305, t0
    csrr t1, 0x305
    bne  t1, t0, rt4_fail
    li   t4, 2
    csrw 0x7C0, x0
    csrr t1, 0x7C0
    bne  t1, x0, rt4_fail
    csrw 0x300, x0
    csrw 0x304, x0

    # ---- clear the whole bank (all four cfg words) ----------------------
    csrw 0x3A0, x0
    csrw 0x3A1, x0
    csrw 0x3A2, x0
    csrw 0x3A3, x0

    # =====================================================================
    # PHASE A — NA4 exactness.  entry0 NA4 @0x11000 (no perms);
    # entry1 OFF (entry2's TOR base 0); entry2 TOR [0,0x20000) R|W|X.
    # =====================================================================
    li   t4, 10
    li   t0, 0x00011000
    srli t0, t0, 2
    csrw 0x3B0, t0
    csrw 0x3B1, x0
    li   t0, 0x00020000
    srli t0, t0, 2
    csrw 0x3B2, t0
    li   t0, 0x000F0010             # cfg2=TOR RWX, cfg1=OFF, cfg0=NA4 no-perms
    csrw 0x3A0, t0
    csrr t1, 0x3A0
    bne  t1, t0, rt4_fail

    li   t4, 11
    li   a0, 0x00011000
    jal  ra, rt4_probe
    beq  a1, x0, rt4_fail           # expect DENIED
    li   t4, 12
    li   a0, 0x00010FFC
    jal  ra, rt4_probe
    bne  a1, x0, rt4_fail           # expect GRANTED
    li   t4, 13
    li   a0, 0x00011004
    jal  ra, rt4_probe
    bne  a1, x0, rt4_fail           # expect GRANTED

    # =====================================================================
    # PHASE B — entries 8 and 15 (pmpcfg2 byte 0 / pmpcfg3 byte 3, and the
    # top of the 30-bit pmp_addr_flat slicing).  ONLY those two entries are
    # live, so a no-match denies and a wrong index grants/denies the wrong
    # address.
    # =====================================================================
    li   t4, 20
    csrw 0x3A0, x0                  # drop PHASE A's map
    li   t0, 0x00011000
    srli t0, t0, 2
    csrw 0x3B8, t0                  # pmpaddr8  = 0x11000 >> 2
    li   t0, 0x00011008
    srli t0, t0, 2
    csrw 0x3BF, t0                  # pmpaddr15 = 0x11008 >> 2
    li   t0, 0x00000011             # cfg8  = R | NA4
    csrw 0x3A2, t0
    csrr t1, 0x3A2
    bne  t1, t0, rt4_fail
    li   t4, 21
    li   t0, 0x11000000             # cfg15 = R | NA4  (top byte of pmpcfg3)
    csrw 0x3A3, t0
    csrr t1, 0x3A3
    bne  t1, t0, rt4_fail

    li   t4, 22
    li   a0, 0x00011000
    jal  ra, rt4_probe
    bne  a1, x0, rt4_fail           # entry 8 grants
    li   t4, 23
    li   a0, 0x00011008
    jal  ra, rt4_probe
    bne  a1, x0, rt4_fail           # entry 15 grants
    li   t4, 24
    li   a0, 0x00011004
    jal  ra, rt4_probe
    beq  a1, x0, rt4_fail           # between them: no match => U denied

    csrw 0x3A2, x0
    csrw 0x3A3, x0

    # =====================================================================
    # PHASE C — NAPOT 8 byte at 0x11000.  pmpaddr = base>>2 with bit0 CLEAR.
    # =====================================================================
    li   t4, 30
    li   t0, 0x00011000
    srli t0, t0, 2                  # 0x4400: bit0 already 0 => 8-byte NAPOT
    csrw 0x3B0, t0
    csrw 0x3B1, x0
    li   t0, 0x00020000
    srli t0, t0, 2
    csrw 0x3B2, t0
    li   t0, 0x000F0018             # cfg0 = NAPOT, no perms
    csrw 0x3A0, t0

    li   t4, 31
    li   a0, 0x00011000
    jal  ra, rt4_probe
    beq  a1, x0, rt4_fail           # DENIED (word 0 of the region)
    li   t4, 32
    li   a0, 0x00011004
    jal  ra, rt4_probe
    beq  a1, x0, rt4_fail           # DENIED (word 1 — the LAST word inside)
    li   t4, 33
    li   a0, 0x00011008
    jal  ra, rt4_probe
    bne  a1, x0, rt4_fail           # GRANTED (first word AFTER)
    li   t4, 34
    li   a0, 0x00010FFC
    jal  ra, rt4_probe
    bne  a1, x0, rt4_fail           # GRANTED (last word BEFORE)

    # =====================================================================
    # PHASE D — NAPOT 4 KiB at 0x12000.  pmpaddr = (base>>2) | 0x1FF, and
    # bit 9 of that value must be 0 (0x12000>>2 = 0x4800).
    # =====================================================================
    li   t4, 40
    li   t0, 0x000049FF             # (0x12000>>2) | 0x1FF
    csrw 0x3B0, t0
    csrr t1, 0x3B0
    bne  t1, t0, rt4_fail

    li   t4, 41
    li   a0, 0x00012000
    jal  ra, rt4_probe
    beq  a1, x0, rt4_fail           # DENIED (first word inside)
    li   t4, 42
    li   a0, 0x00012FFC
    jal  ra, rt4_probe
    beq  a1, x0, rt4_fail           # DENIED (last word inside)
    li   t4, 43
    li   a0, 0x00013000
    jal  ra, rt4_probe
    bne  a1, x0, rt4_fail           # GRANTED (first word after)
    li   t4, 44
    li   a0, 0x00011FFC
    jal  ra, rt4_probe
    bne  a1, x0, rt4_fail           # GRANTED (last word before)

    # =====================================================================
    # PHASE E — THE DEGENERATE NAPOT: pmpaddr = 0.  `P xor (P+1)` = 1, so the
    # region is 8 BYTES at address 0 (0x0 and 0x4), NOT NA4-at-0 and NOT the
    # whole address space.  Probed on both sides.
    # =====================================================================
    li   t4, 50
    csrw 0x3B0, x0                  # pmpaddr0 = 0, still A = NAPOT
    li   a0, 0x00000000
    jal  ra, rt4_probe
    beq  a1, x0, rt4_fail           # DENIED
    li   t4, 51
    li   a0, 0x00000004
    jal  ra, rt4_probe
    beq  a1, x0, rt4_fail           # DENIED  (8-byte region, so word 1 is IN)
    li   t4, 52
    li   a0, 0x00000008
    jal  ra, rt4_probe
    bne  a1, x0, rt4_fail           # GRANTED (a whole-space or bigger region
                                    #          would deny this)
    li   t4, 53
    li   a0, 0x00011000
    jal  ra, rt4_probe
    bne  a1, x0, rt4_fail           # GRANTED (definitely not the whole space)

    # =====================================================================
    # PHASE F — NAPOT ALL-ONES = the FULL SPAN, with a lower NA4 hole.
    #   entry0 NA4 @0x11000, R=1  (the hole)
    #   entry1 NAPOT pmpaddr = 0x3FFFFFFF, no perms (everything else)
    # =====================================================================
    li   t4, 60
    csrw 0x3A0, x0
    li   t0, 0x00011000
    srli t0, t0, 2
    csrw 0x3B0, t0
    li   t0, 0x3FFFFFFF
    csrw 0x3B1, t0
    csrr t1, 0x3B1
    bne  t1, t0, rt4_fail
    li   t0, 0x00001811             # cfg1 = NAPOT no-perms, cfg0 = R | NA4
    csrw 0x3A0, t0
    csrr t1, 0x3A0
    bne  t1, t0, rt4_fail

    li   t4, 61
    li   a0, 0x00011000
    jal  ra, rt4_probe
    bne  a1, x0, rt4_fail           # GRANTED through the hole
    li   t4, 62
    li   a0, 0x00011004
    jal  ra, rt4_probe
    beq  a1, x0, rt4_fail           # DENIED by the full-span entry
    li   t4, 63
    li   a0, 0x00000000
    jal  ra, rt4_probe
    beq  a1, x0, rt4_fail           # DENIED — the span really is everything
    li   t4, 64
    li   a0, 0x0001FFFC
    jal  ra, rt4_probe
    beq  a1, x0, rt4_fail           # DENIED at the top of the shared window

    # =====================================================================
    # PHASE G — TOR entry 0's implicit base 0, and the boundary PAIR.
    #   entry0 TOR pmpaddr0 = 0x11000>>2, no perms  => [0x00000, 0x11000)
    #   entry1 TOR pmpaddr1 = 0x12000>>2, R|W|X     => [0x11000, 0x12000)
    #   entry2 NAPOT all-ones, no perms             => everything else
    # =====================================================================
    li   t4, 70
    csrw 0x3A0, x0
    li   t0, 0x00011000
    srli t0, t0, 2
    csrw 0x3B0, t0
    li   t0, 0x00012000
    srli t0, t0, 2
    csrw 0x3B1, t0
    li   t0, 0x3FFFFFFF
    csrw 0x3B2, t0
    li   t0, 0x00180F08             # cfg2=NAPOT deny, cfg1=TOR RWX, cfg0=TOR deny
    csrw 0x3A0, t0
    csrr t1, 0x3A0
    bne  t1, t0, rt4_fail

    li   t4, 71
    li   a0, 0x00000000
    jal  ra, rt4_probe
    beq  a1, x0, rt4_fail           # DENIED: entry 0's base really is 0
    li   t4, 72
    li   a0, 0x00010FFC
    jal  ra, rt4_probe
    beq  a1, x0, rt4_fail           # DENIED: last word below the top
    li   t4, 73
    li   a0, 0x00011000
    jal  ra, rt4_probe
    bne  a1, x0, rt4_fail           # GRANTED: top is EXCLUSIVE, base INCLUSIVE
    li   t4, 74
    li   a0, 0x00011FFC
    jal  ra, rt4_probe
    bne  a1, x0, rt4_fail           # GRANTED: last word inside entry 1
    li   t4, 75
    li   a0, 0x00012000
    jal  ra, rt4_probe
    beq  a1, x0, rt4_fail           # DENIED: entry 1's top is EXCLUSIVE

    # =====================================================================
    # PHASE H — TOR NULL REGION.  entry1 is TOR with pmpaddr1 < pmpaddr0, so
    # hi <= lo and it must match NOTHING.  entry2 then grants the range the
    # inverted region nominally spans, so a "min/max" or "swap" reading of
    # the bounds shows up as a DENIAL.
    #   entry0 OFF   pmpaddr0 = 0x11800>>2   (the inverted region's `lo`)
    #   entry1 TOR   pmpaddr1 = 0x11000>>2, no perms  => EMPTY
    #   entry2 TOR   pmpaddr2 = 0x12000>>2, R|W|X     => [0x11000, 0x12000)
    # =====================================================================
    li   t4, 80
    csrw 0x3A0, x0
    li   t0, 0x00011800
    srli t0, t0, 2
    csrw 0x3B0, t0
    li   t0, 0x00011000
    srli t0, t0, 2
    csrw 0x3B1, t0
    li   t0, 0x00012000
    srli t0, t0, 2
    csrw 0x3B2, t0
    li   t0, 0x000F0800             # cfg2=TOR RWX, cfg1=TOR deny, cfg0=OFF
    csrw 0x3A0, t0
    csrr t1, 0x3A0
    bne  t1, t0, rt4_fail

    li   t4, 81
    li   a0, 0x00011400
    jal  ra, rt4_probe
    bne  a1, x0, rt4_fail           # GRANTED: the null region matched nothing
    li   t4, 82
    li   a0, 0x000117FC
    jal  ra, rt4_probe
    bne  a1, x0, rt4_fail           # GRANTED
    li   t4, 83
    li   a0, 0x00011000
    jal  ra, rt4_probe
    bne  a1, x0, rt4_fail           # GRANTED
    li   t4, 84
    li   a0, 0x00010FFC
    jal  ra, rt4_probe
    beq  a1, x0, rt4_fail           # DENIED: below entry 2's base, no match

    # =====================================================================
    # PHASE I — TOR whose PREDECESSOR IS OFF: the predecessor's VALUE is
    # still the base.  entry1 is the ONLY live entry, so everything outside
    # its range is a no-match (U denies) — which makes an address BELOW the
    # base the discriminator against a "base = 0 when predecessor is OFF"
    # reading.
    #   entry0 OFF   pmpaddr0 = 0x11000>>2
    #   entry1 TOR   pmpaddr1 = 0x12000>>2, R=1   => [0x11000, 0x12000)
    # =====================================================================
    li   t4, 90
    csrw 0x3A0, x0
    li   t0, 0x00011000
    srli t0, t0, 2
    csrw 0x3B0, t0
    li   t0, 0x00012000
    srli t0, t0, 2
    csrw 0x3B1, t0
    li   t0, 0x00000900             # cfg1 = R | TOR, cfg0 = OFF
    csrw 0x3A0, t0
    csrr t1, 0x3A0
    bne  t1, t0, rt4_fail

    li   t4, 91
    li   a0, 0x00011800
    jal  ra, rt4_probe
    bne  a1, x0, rt4_fail           # GRANTED: inside [base, top)
    li   t4, 92
    li   a0, 0x00011000
    jal  ra, rt4_probe
    bne  a1, x0, rt4_fail           # GRANTED: the base itself is IN
    li   t4, 93
    li   a0, 0x00010800
    jal  ra, rt4_probe
    beq  a1, x0, rt4_fail           # DENIED: THE DISCRIMINATOR (a base of 0
                                    #         would have covered this)
    li   t4, 94
    li   a0, 0x00012000
    jal  ra, rt4_probe
    beq  a1, x0, rt4_fail           # DENIED: top is exclusive

    # =====================================================================
    # PHASE J — PRIORITY, three overlapping entries, BOTH polarities.
    #   run 1: entry0 NA4 deny, entry1 NA4 grant, entry2 NAPOT-8 grant
    #   run 2: entry0 NA4 grant, entry1 NA4 deny, entry2 NAPOT-8 deny
    # All three cover 0x11000; entry2 also covers 0x11004.  entry3 TOR
    # [0x11000, 0x20000) keeps the rest of the window reachable.
    # =====================================================================
    li   t4, 100
    csrw 0x3A0, x0
    li   t0, 0x00011000
    srli t0, t0, 2
    csrw 0x3B0, t0                  # NA4 @0x11000
    csrw 0x3B1, t0                  # NA4 @0x11000
    csrw 0x3B2, t0                  # NAPOT 8 byte @0x11000 (bit0 clear)
    li   t0, 0x00020000
    srli t0, t0, 2
    csrw 0x3B3, t0
    li   t0, 0x0F191110             # cfg3=TOR RWX cfg2=NAPOT R cfg1=NA4 R cfg0=NA4 deny
    csrw 0x3A0, t0
    csrr t1, 0x3A0
    bne  t1, t0, rt4_fail

    li   t4, 101
    li   a0, 0x00011000
    jal  ra, rt4_probe
    beq  a1, x0, rt4_fail           # DENIED: entry 0 decides ALONE
    li   t4, 102
    li   a0, 0x00011004
    jal  ra, rt4_probe
    bne  a1, x0, rt4_fail           # GRANTED by entry 2 (entries 0/1 miss it)

    li   t4, 103
    li   t0, 0x0F181011             # cfg2=NAPOT deny cfg1=NA4 deny cfg0=NA4 R
    csrw 0x3A0, t0
    csrr t1, 0x3A0
    bne  t1, t0, rt4_fail
    li   t4, 104
    li   a0, 0x00011000
    jal  ra, rt4_probe
    bne  a1, x0, rt4_fail           # GRANTED: entry 0 decides ALONE
    li   t4, 105
    li   a0, 0x00011004
    jal  ra, rt4_probe
    beq  a1, x0, rt4_fail           # DENIED by entry 2

    # =====================================================================
    # PHASE K — A LOCKED HIGH ENTRY MUST NOT RESCUE A LOWER DENY, IN M.
    # LAST in the file: a lock releases only at reset.
    #   entry0 NA4 @0x13000  L=1, no perms   (the deny that must stand)
    #   entry1 NA4 @0x13000  L=1, R|W|X      (the rescue that must not happen)
    # Probed in the M VIEW (MPRV=0) — a lock is the only thing that
    # constrains M, so this is the sharp form of "lowest match decides alone".
    # =====================================================================
    li   t4, 110
    csrw 0x3A0, x0
    csrw 0x3A1, x0
    li   t0, 0x00013000
    srli t0, t0, 2
    csrw 0x3B0, t0
    csrw 0x3B1, t0
    li   t0, 0x00008F90             # cfg1 = L|NA4|RWX , cfg0 = L|NA4|no-perms
    csrw 0x3A0, t0
    csrr t1, 0x3A0
    bne  t1, t0, rt4_fail

    li   t4, 111
    li   a0, 0x00013000
    jal  ra, rt4_mprobe
    beq  a1, x0, rt4_fail           # DENIED in M: the locked LOW entry stands
    li   t4, 112
    li   a0, 0x00013004
    jal  ra, rt4_mprobe
    bne  a1, x0, rt4_fail           # GRANTED in M: no match, M is unrestricted
    li   t4, 113
    li   a0, 0x00013000
    jal  ra, rt4_probe
    beq  a1, x0, rt4_fail           # DENIED in the U view too

    li   t4, 114                    # the lock holds against a rewrite
    csrw 0x3A0, x0
    csrr t1, 0x3A0
    li   t0, 0x00008F90
    bne  t1, t0, rt4_fail

    # ---- restore what CAN be restored, then LEGACY delivery -------------
    csrw 0x3A2, x0
    csrw 0x3A3, x0
    li   t1, 0x00000001
    csrw 0x7C0, t1
    csrw 0x300, x0

    RVTEST_PASS

    # =====================================================================
    # THE PROBES.  rt4_probe uses the U DATA view (MPRV=1, MPP=U);
    # rt4_mprobe uses the plain M view.  Both return a1 = 0 GRANTED /
    # 1 DENIED and clobber only t0/t1/s7/a1 (+ the handler's s4/s5/s6).
    # Placed after the PASS spin loop like every other helper in the suite.
    # =====================================================================
    .align 2
rt4_probe:
    la   s7, rt4_probe_flt
    li   t0, 0x00020000             # MPRV=1, MPP=00 (U)
    csrw 0x300, t0
    lw   t1, 0(a0)
    csrw 0x300, x0
    li   a1, 0
    ret
rt4_probe_flt:
    csrw 0x300, x0
    li   a1, 1
    ret

    .align 2
rt4_mprobe:
    la   s7, rt4_mprobe_flt
    csrw 0x300, x0                  # MPRV=0: the plain M view
    lw   t1, 0(a0)
    li   a1, 0
    ret
rt4_mprobe_flt:
    li   a1, 1
    ret

    .align 2
rt4_handler:
    csrr t0, 0x342
    addi s3, s3, 1
    mv   s4, t0
    csrr s5, 0x341
    csrr s6, 0x343
    csrw 0x341, s7
    mret

    .option pop

#else
    li   t4, 0
    j    rt4_fail
#endif

rt4_fail:
    RVTEST_FAIL

    # NOTE: RVTEST_CODE_END is 'unimp' (traps!) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
