# See LICENSE for license details.

#*****************************************************************************
# shexec.S  (M10; M12 single-ROM boot rework)
#-----------------------------------------------------------------------------
# EXECUTE-FROM-SHARED proof — instruction fetch THROUGH the mp_arbiter.
#
# M12: tiles are NO LONGER preloaded. Hart 0 stages this TCM image once and
# launches all three tiles into tile_entry through the bootrom loader
# (mp_boot.h); each tile then parks on TOKEN just as before. Hart 0 copies the
# payload into shared RAM BEFORE releasing any tile (order unchanged), so the
# tiles only ever execute a fully-written payload.
#
# The M12 boot rework (single shared boot ROM, all harts reset-fetch through
# the arbiter) is only buildable if a core can EXECUTE from the shared window
# at all — never proven before M10 (the window was DATA-only by design). This
# test makes every hart run a small loop IN SHARED RAM that itself LOADS from
# shared while fetching from shared (the M12 bootrom shape: code + mailbox
# reads through the same arbiter port):
#
#     payload @0x103C0 (5 words, copied there by hart 0):
#         lw   t2, 0(s0)        # shared DATA load amid shared FETCHES
#         add  t1, t1, t2       # sequential fetch
#         addi a1, a1, -1       # sequential fetch
#         bnez a1, payload      # backward branch WITHIN shared
#         jalr x0, ra, 0        # return to private code
#
# Per-hart iteration counts differ (4+hartid), so each hart proves its OWN
# loop really ran: t1 must equal iters*0x00010001 (CHK holds 0x00010001).
#
# Shared words (ledger: next-free was 0x103C0, 16 words to the 0x103FF end):
#     CODE    = 0x103C0..0x103D0  5 payload words (0x103D0 holds 0x00008067 —
#                                 shamo's probe constraint 0x22222222 is safe)
#     CHK     = 0x103D4           0x00010001, written by hart 0
#     TOKEN   = 0x103D8           turn word, hart-0 owned: h = hart h's turn
#     DONE[h] = 0x103D8 + 4*h     0xE0EC0000+h, h=1..NHARTS-1
# Argus A3: CODE/CHK/TOKEN sit below the DONE base; the NHARTS-sized DONE array
# runs 0x103DC..(0x103D8+4*(NHARTS-1)). N=18 top = 0x1041C, clear of the loader
# rows (0x10500+) and below the bootrom zero-range end (0x10800). Every tile
# runs the SAME payload (no role dispatch) — parameterizes cleanly.
#     next free: 0x103E8 (N=4)
#
# Harts 1-3 (launched by hart 0 at tile_entry): PARK polling TOKEN (reads only), then
# run the payload, check t1, write DONE[h], set a0 = PASS inline, verify DONE
# forever (shboot pattern).
# Hart 0 (SPI boot, arrives late): copy payload + CHK into shared RAM
# (read-back verified), prove DONE[1..3]==0 (tiles parked cleanly), run the
# payload ITSELF (the gate hart fails fast if fetch-from-shared is broken),
# then release tiles one at a time via TOKEN with a bounded DONE budget.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_CODE   0x103C0
#define SH_CHK    0x103D4
#define SH_TOKEN  0x103D8
#define CHK_VAL   0x00010001
#define DONE_MAG  0xE0EC0000

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..3
    .option pop
    bnez s10, tile_entry        # M12: only hart 0 runs the launcher

    # M12 single-ROM boot: stage this TCM image once, launch all three tiles
    # into tile_entry (mp_boot.h). They park on TOKEN just as the old
    # preloaded tiles did; hart 0 falls through to the orchestrator.
    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_ALL(tile_entry, 4096)

tile_entry:                     # tiles enter here (loader ABI: only sp defined)
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # re-derive (undefined for tiles until now)
    .option pop
    li   sp, 0xBFF0             # convention (loader left 0xBFFC)

    li   s2, SH_CODE            # payload entry
    li   s3, SH_TOKEN           # turn word (DONE base: TOKEN + 4*h)
    li   s4, SH_CHK

    beqz s10, orchestrator

    # ---- harts 1-3: park on TOKEN (reads only), then take our turn -------
park_loop:
    lw   t1, 0(s3)
    bne  t1, s10, park_loop

    li   a1, 4
    add  a1, a1, s10            # iters = 4 + hartid
    slli t5, a1, 16
    add  t5, t5, a1             # expected t1 = iters * 0x00010001
    mv   s0, s4                 # payload reads CHK through s0
    li   t1, 0
    jalr ra, s2, 0              # EXECUTE FROM SHARED (returns via ra)
    bne  t1, t5, shexec_fail

    slli t0, s10, 2
    add  s5, s3, t0             # my DONE word
    li   t3, DONE_MAG
    add  t3, t3, s10
    sw   t3, 0(s5)              # report in
    li   a0, 0xCAFEBABE         # inline PASS (tb latches a0_1/2/3)
payload_verify:                 # forever: DONE must survive other traffic
    lw   t4, 0(s5)
    bne  t4, t3, shexec_fail
    j    payload_verify

    # ---- hart 0: copy payload out, prove it runs, then release tiles ------
orchestrator:
    # copy the 5 payload words into shared RAM, read-back verified
    la   t0, payload_src
    mv   t2, s2
    li   t3, 5
copy_loop:
    lw   t4, 0(t0)
    sw   t4, 0(t2)
    lw   t6, 0(t2)              # read-back (shared write really landed)
    bne  t6, t4, shexec_fail
    addi t0, t0, 4
    addi t2, t2, 4
    addi t3, t3, -1
    bnez t3, copy_loop
    li   t4, CHK_VAL
    sw   t4, 0(s4)              # CHK constant

    # tiles must still be parked: DONE[1..3] all zero (reads-only proof)
    li   t0, 1
parked_chk:
    slli t1, t0, 2
    add  t1, s3, t1
    lw   t2, 0(t1)
    bnez t2, shexec_fail
    addi t0, t0, 1
    li   t1, NHARTS
    bne  t0, t1, parked_chk

    # the gate hart executes from shared FIRST (fail fast, easy triage)
    li   a1, 4                  # iters = 4
    slli t5, a1, 16
    add  t5, t5, a1             # expected 0x00040004
    mv   s0, s4
    li   t1, 0
    jalr ra, s2, 0              # EXECUTE FROM SHARED
    bne  t1, t5, shexec_fail

    # release tiles one at a time; bounded wake budget each (shboot pattern)
    li   s6, 1
release_loop:
    sw   s6, 0(s3)              # TOKEN = h: hart h's turn
    slli t0, s6, 2
    add  s7, s3, t0             # DONE[h]
    li   t5, DONE_MAG
    add  t5, t5, s6
    li   t6, 100000             # bounded: broken tile -> FAIL, not watchdog
wake_wait:
    lw   t2, 0(s7)
    beq  t2, t5, released
    addi t6, t6, -1
    bnez t6, wake_wait
    j    shexec_fail
released:
    addi s6, s6, 1
    li   t0, NHARTS
    bne  s6, t0, release_loop

    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin

shexec_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # ---- payload source image (copied to SH_CODE; never executed here) ----
    # Position-independent by construction: the branch is PC-relative, data
    # goes through s0, the return through ra. Forced non-compressed so the
    # copied block is exactly 5 words and every fetch is a full word.
    .align 2
    .option push
    .option norvc
payload_src:
    lw   t2, 0(s0)
    add  t1, t1, t2
    addi a1, a1, -1
    bnez a1, payload_src
    jalr x0, ra, 0
    .option pop

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
