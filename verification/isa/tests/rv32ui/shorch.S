# See LICENSE for license details.

#*****************************************************************************
# shorch.S  (CPR4 REWRITE — Castalia-Penta ORCHESTRATOR test, hart-0 shape)
#-----------------------------------------------------------------------------
# ORCHESTRATOR-ONLY test (verify_stage tags `tiles cqAfeStubs orch`). shafe.S is
# its N<=4 ancestor and is deselected on this config by the `harts_le4`
# structural tag (its per-hart stub addressing has no site for a fifth hart).
# This file is NOT the tape-out-config orchestrator test: the AFE/EIS stub bank
# is dropped on penta_wound, so `shtcm` — which keys on the TCM apertures, and
# those exist wherever the orchestrator does — carries that duty.
#
# WHAT CPR3/R2 INVERTED, AND WHY THE CP3 VERSION HAD TO BE REWRITTEN RATHER
# THAN RE-TAGGED. The CP2/CP3 shape put the orchestrator at hart NHARTS-1, made
# hart 0 a plain CHANNEL that had LOST the fabric privilege, and carried the
# privilege in afe_stub's MGMT_HART generic. Every one of those is now false:
#   * THE MANAGEMENT HART IS HART 0, in both chip shapes, so `MGMT_HART` is
#     never overridden again (the entity default 0 is correct everywhere) and
#     the privilege is once more the literal `s_master = 0`.
#   * The four AFE sites belong to the four TILES: hart h owns
#     AFE0 + 0x40*(h-1), h = 1..4. The orchestrator has NO site of its own —
#     it has REACH INTO ALL OF THEM.
#   * EIS (OWNER_HART => 0) is hart-0's own engine and is denied to every tile.
#   * The IRQ relay comes home: sources 55 (OR of the four AFE IFs) and 56
#     (EIS) route to HART 0's own irq_router row, and hart 0 demuxes by reading
#     all four AFE IF words — the management privilege exercised in the IRQ
#     path — then msips the owner.
#   * THE NEGATIVE CONTROL THEREFORE INVERTS. In the CP3 file hart 0 was the
#     denied prober; here a TILE is, and hart 0 is the one master that can look
#     at what the tiles could not touch. Running this file against MGMT_HART=4
#     RTL fails at CHECK A2-h, which is the point.
#
# HART 0 IS THREE ROLES IN ONE HART NOW (CPR3/R2): the launcher (it is the boot
# master), the manager (the only master the AFE bank and EIS answer in full),
# and the testbench a0 gate. The tiles report through a0_1..a0_4 (emitted and
# monitored). It is deliberately NOT a channel — a hart cannot be both the
# subject and the sole judge of a privilege test.
#
# NEGATIVE CONTROL (a test that cannot fail its negative control is not a
# test). Two halves, and the second is what makes the first load-bearing:
#   (a) DENIAL: every TILE reads a FOREIGN tile's stub +8 and MUST read 0, then
#       writes POISON there. The victim populated that word with a distinct
#       nonzero pattern at A1, so a 0 read proves the GATE, not an empty
#       register. Victims rotate n = h+1 wrapped into 1..4 — never the tile
#       itself. Each tile also probes EIS +8 (seeded nonzero by hart 0, and
#       hart-0-only) and poisons it, then re-reads its OWN +8 to prove no
#       foreign poison landed on it.
#   (b) MANAGEMENT READ-BACK: hart 0 — the only master that can see all five
#       blocks — walks AFE0..3 +8 and EIS +8 and asserts every word still holds
#       its OWNER's pattern. A dropped write is only proven by someone who can
#       look. Hart 0 additionally reads NEGRPT (published by TILE 1 with the
#       poison it attempted) and FAILs if it is zero: a vacuous negative
#       control — one where no poison was ever written — cannot pass this file.
#
# PHASES (barriers: PHASE and TURN are both hart-0-owned now — the manager and
# the relay are the same hart)
#   A1  populate. Hart 0 seeds EIS +8 and opens GO. Tiles 1-4 populate their
#       own AFE (config +1..6 and scratch +8..F = PAT_BASE|h<<8|reg, each read
#       back — no two (hart,reg) values alias, so a leak cannot hide) and mark
#       DONE[h]=A1. Hart 0 gathers, then PHASE=1.
#   A2  deny (negative control half (a)). Every tile probes as above; tile 1
#       also publishes NEGRPT. Tiles mark DONE[h]=A2; hart 0 gathers.
#   A3  management walk (hart 0, negative control half (b) + privilege proof).
#       Read AFE n +8 == owner pattern for n=0..3, write AFE n +15 and read
#       back (management WRITE reach), EIS +8 == seed, EIS +9 write/read-back,
#       NEGRPT nonzero. Then program H0ENM (0x7000 + 4) with sources 55/56 and
#       open PHASE=2.
#   B   msip relay (hart 0 = the relay; one owner round per TILE, h=1..4).
#       Hart 0 sets TURN=h; owner h soft-fires its AFE IF via CTRL bit 0
#       (raising afe_eis_irq(h-1) -> source 55) and SLEEPS on the very next
#       instruction. Hart 0 takes meip -> CLAIM -> IVT slot 55 -> the source-55
#       handler, which reads the four AFE IF words to demux, W1C-clears the
#       fired IF (drops the LEVEL before the dispatcher COMPLETEs — a still-high
#       level would re-pend) and msips the owner. The owner's slot-83 CLINT ISR
#       clears its msip level, ignites (so iret resumes MAINLINE on a sleeping
#       hart) and irets; the owner records DONE[h]=B. Hart 0 waits for it and
#       verifies that AFE's IF really cleared. Finally hart 0 self-fires EIS
#       (source 56) and its handler W1C-clears EIS IF + sets a private flag.
#       RACE (same guarantee as shwfi/shafe): the owner extinguishes ONE
#       private instruction after its IF store, while hart 0's msip needs the
#       whole meip+claim+four-reads path AFTER that store lands — the owner is
#       always asleep before its msip arrives.
#
# CLINT ADDRESSES ARE DERIVED FROM NHARTS (K5 precedent, CP1 D7): the msip
# array is 4*NHARTS bytes and mtime starts at 0x5000 + roundup16(4*NHARTS), so
# at NHARTS=5 mtime is 0x5020, NOT 0x5010. This file only touches MSIP[h] =
# 0x5000 + 4h (N-agnostic), but never hardcodes a 0x5010-class constant.
#
# Shared-word ledger (CP3 band, UNCHANGED at CPR4 — only the OWNERS of two of
# the words move; all < 0x10500, arrays 4*NHARTS so a bigger N cannot overrun
# the control words):
#     GO      = 0x104A0                  tiles may start A1
#     DONE[h] = 0x104A4 + 4*h            per-tile phase progress (N=5: ..0x104B4)
#     PHASE   = 0x104A4 + 4*NHARTS       hart-0 phase barrier    (N=5: 0x104B8)
#     TURN    = PHASE + 4                hart-0 owner round      (N=5: 0x104BC)
#     NEGRPT  = PHASE + 8                poison a TILE attempted (N=5: 0x104C0)
#   (next free shared word 0x104C4 at N=5; the block is shared with shafe's
#    N=18 tail, which is benign and unreachable — shorch selects only on an
#    orchestrator config and shafe only at numHarts <= 4, so they can never
#    coexist, and tests run one image per sim anyway.)
#
# No smclk-domain peripheral is touched (AFE/EIS/CLINT/irq_router are all
# mclk), so the bootrom SMCLK->LFXT trap does not apply. Bounded waits 20000
# (100000 for the first gather, which covers the tiles' ROM copy) all trip
# inside the 100 ms tb watchdog.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"                /* NHARTS (5 on a penta build) */

#define AFE0        0x4C00          /* hart h's site = AFE0 + 0x40*(h-1)      */
#define EIS         0x7C00
#define SH_IRTR     0x7000          /* HhENL/M/U at +0x10*h + 0/4/8 */
#define CLINT_MSIP  0x5000          /* MSIP[h] = +4h (N-agnostic) */
#define NCHAN       4               /* AFE sites: FOUR at any NHARTS (D4) */
#define MGMT        0               /* CPR3/R2: the orchestrator IS hart 0 */

#define GO          0x104A0
#define DONE_BASE   0x104A4
#define PHASE       (DONE_BASE + 4*NHARTS)
#define TURN        (PHASE + 4)
#define NEGRPT      (PHASE + 8)

#define GO_MAGIC    0x600D0C40      /* "GOOD ORC" — distinct from shafe's */
#define A1_MAGIC    0xA1E00000
#define A2_MAGIC    0xA2E00000
#define B_MAGIC     0xBEE00000
#define TURN_MAGIC  0x70C50000
#define PAT_BASE    0x5AFE0000
#define POISON      0xBAD00000
#define EIS_SEED    0xE15E0000
#define WALK_MAGIC  0xC0DE0000
#define HENM_5556   0x01800000      /* sources 55,56 in irq_en[63:32] = bits 23,24 */
#define IF_OFF      0x1C            /* +7  interrupt-flag word (W1C) */
#define SC8_OFF     0x20            /* +8  first scratch word */
#define SC9_OFF     0x24            /* +9  second scratch word */
#define SC15_OFF    0x3C            /* +15 last scratch word (mgmt write reach) */

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..N-1 (the ISRs read it too — never clobber)
    .option pop
    bnez s10, tile_entry        # only hart 0 runs the launcher

    # single-ROM boot: stage this TCM image once, launch harts 1..NHARTS-1
    # (the four channel TILES) into tile_entry. They park on GO; hart 0 falls
    # through to its own setup.
    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_ALL(tile_entry, 4096)

tile_entry:                     # launched harts enter here (loader ABI: sp only)
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # re-derive (undefined until now)
    .option pop

    li   sp, 0xBFF0             # private TCM top; IRQ_SV pushes PC at sp-4
    li   s2, GO
    li   s3, DONE_BASE
    li   s4, PHASE
    li   s5, TURN

    beqz s10, orch_hart         # hart 0: NO AFE site — never compute one

    # ---- channel tiles 1..4: my own AFE base + my own pattern -------------
    addi t0, s10, -1            # site index = h - 1
    slli t0, t0, 6              # 0x40 per site
    li   t1, AFE0
    add  s6, t0, t1             # s6 = my AFE base
    li   t0, PAT_BASE
    slli t1, s10, 8
    or   s8, t0, t1             # s8 = my AFE pattern (PAT_BASE | h<<8)

    # neighbour victim n = h+1 wrapped into 1..NCHAN : never me, never hart 0
    addi t5, s10, 1
    li   t3, NCHAN + 1
    bne  t5, t3, orch_nb_have
    li   t5, 1
orch_nb_have:
    addi t0, t5, -1
    slli t0, t0, 6
    li   t1, AFE0
    add  s9, t0, t1             # s9 = victim AFE base (preserved across A2)

    # ---- A1 populate: wait GO, write own AFE, mark DONE[h]=A1 --------------
ch_go_wait:
    lw   t0, 0(s2)
    li   t1, GO_MAGIC
    bne  t0, t1, ch_go_wait

    jal  ra, populate_afe       # write+verify AFE h regs 1..6, 8..15

    slli t0, s10, 2
    add  t0, t0, s3             # DONE[h]
    li   t1, A1_MAGIC
    add  t1, t1, s10
    sw   t1, 0(t0)              # DONE[h] = A1

    # ---- wait PHASE==1, then A2 deny (negative control half (a)) ----------
    li   t1, 1
ch_ph1_wait:
    lw   t0, 0(s4)
    bne  t0, t1, ch_ph1_wait

    jal  ra, deny_probe         # CHECK A2-h: foreign AFE + EIS both denied

    li   t1, 1                  # tile 1 publishes what it ATTEMPTED, so the
    bne  s10, t1, ch_no_rpt     # management walk can prove the control was
    li   t0, POISON             # not vacuous
    add  t0, t0, s10
    li   t1, NEGRPT
    sw   t0, 0(t1)
ch_no_rpt:

    slli t0, s10, 2
    add  t0, t0, s3             # DONE[h]
    li   t1, A2_MAGIC
    add  t1, t1, s10
    sw   t1, 0(t0)              # DONE[h] = A2

    # ---- wait PHASE==2 (phase 2 is opened after hart 0's management walk) --
    li   t1, 2
ch_ph2_wait:
    lw   t0, 0(s4)
    bne  t0, t1, ch_ph2_wait

    # ---- phase B: my owner round, released by hart 0's TURN ---------------
    li   t2, TURN_MAGIC
    add  t2, t2, s10            # TURN value for me
ch_turn_wait:
    lw   t0, 0(s5)
    bne  t0, t2, ch_turn_wait

    li   t0, 1
    sw   t0, 0(s6)              # AFE CTRL bit0=1 -> soft-set IF(0): src 55
    extinguish                  # ...sleep on the NEXT instruction (RACE note)

    # ---- here only after hart 0's msip -> slot-83 ISR ignited + iret'd ----
    li   t1, B_MAGIC
    add  t1, t1, s10
    slli t0, s10, 2
    add  t0, t0, s3             # DONE[h]
    sw   t1, 0(t0)              # DONE[h] = B (real wake proof)
    li   a0, 0xCAFEBABE         # inline PASS (tb latches a0_1..a0_4)
ch_verify:                      # forever: DONE must survive other traffic
    lw   t2, 0(t0)
    bne  t2, t1, shorch_fail
    j    ch_verify

    # ================= hart 0 — THE ORCHESTRATOR ==========================
    # launcher + manager + the a0 gate. It owns no AFE site; it owns the reach
    # into all of them, and the EIS engine outright.
orch_hart:
    li   t0, EIS                # CHECK O-1: the manager OWNS the EIS engine
    li   t1, EIS_SEED
    ori  t1, t1, 8
    sw   t1, SC8_OFF(t0)
    lw   t2, SC8_OFF(t0)
    bne  t2, t1, shorch_fail

    li   t0, GO_MAGIC
    sw   t0, 0(s2)              # open GO: the four tiles may start A1

    # ---- A1 gather (first wait covers the launched harts' ROM copy) -------
    li   s7, 1
h0_a1:
    li   t6, 100000
    slli t0, s7, 2
    add  t0, t0, s3             # DONE[s7]
    li   t1, A1_MAGIC
    add  t1, t1, s7
h0_a1w:
    lw   t2, 0(t0)
    beq  t2, t1, h0_a1n
    addi t6, t6, -1
    bnez t6, h0_a1w
    j    shorch_fail
h0_a1n:
    addi s7, s7, 1
    li   t0, NHARTS
    bltu s7, t0, h0_a1

    li   t0, 1
    sw   t0, 0(s4)              # PHASE = 1: release the tiles into A2

    # ---- A2 gather over the four tiles ------------------------------------
    li   s7, 1
h0_a2:
    li   t6, 20000
    slli t0, s7, 2
    add  t0, t0, s3             # DONE[s7]
    li   t1, A2_MAGIC
    add  t1, t1, s7
h0_a2w:
    lw   t2, 0(t0)
    beq  t2, t1, h0_a2n
    addi t6, t6, -1
    bnez t6, h0_a2w
    j    shorch_fail
h0_a2n:
    addi s7, s7, 1
    li   t0, NHARTS
    bltu s7, t0, h0_a2

    # ---- A3: THE MANAGEMENT WALK (negative control half (b)) --------------
    # CHECK O-2: read reach to ALL FOUR tile sites, each still holding its
    # OWNER's pattern -> no tile poison landed anywhere. The drops are proven
    # by the one master that can look.
    li   s7, 0                  # site index 0..3 (owner hart = site + 1)
o_walk:
    slli t0, s7, 6
    li   t1, AFE0
    add  t6, t0, t1             # AFE site base
    li   t1, PAT_BASE
    addi t0, s7, 1              # owner hart
    slli t0, t0, 8
    or   t1, t1, t0
    ori  t2, t1, 8              # expected site +8 = owner pattern | 8
    lw   t0, SC8_OFF(t6)
    bne  t0, t2, shorch_fail
    li   t0, WALK_MAGIC         # CHECK O-3: management WRITE reach
    add  t0, t0, s7
    sw   t0, SC15_OFF(t6)
    lw   t3, SC15_OFF(t6)
    bne  t3, t0, shorch_fail
    addi s7, s7, 1
    li   t0, NCHAN
    bltu s7, t0, o_walk

    li   t6, EIS                # CHECK O-4: EIS +8 == seed (no tile poison)
    li   t0, EIS_SEED
    ori  t0, t0, 8
    lw   t1, SC8_OFF(t6)
    bne  t1, t0, shorch_fail
    li   t0, WALK_MAGIC
    sw   t0, SC9_OFF(t6)        # EIS +9 write + read-back
    lw   t1, SC9_OFF(t6)
    bne  t1, t0, shorch_fail

    li   t0, NEGRPT             # CHECK O-5: the negative control was NOT
    lw   t1, 0(t0)              # vacuous — tile 1 really did attempt a poison
    beqz t1, shorch_fail

    # ---- program MY OWN router row for sources 55/56 (the relay comes home).
    # ---- Row h is at SH_IRTR + 0x10*h; HhENM = irq_en[63:32] (+4).
    li   t0, SH_IRTR + 0x10*MGMT
    li   t1, HENM_5556
    sw   t1, 4(t0)              # H0ENM = sources 55,56
    lw   t2, 4(t0)
    bne  t2, t1, shorch_fail    # CHECK O-6

    li   t0, 2
    sw   t0, 0(s4)              # PHASE = 2: release the tiles into phase B

    # ---- RELAY one round per TILE h = 1..NCHAN ----------------------------
    li   s7, 1
o_b:
    li   t0, TURN_MAGIC
    add  t0, t0, s7
    sw   t0, 0(s5)              # TURN = h -> release owner h to fire + sleep
    li   t2, B_MAGIC
    add  t2, t2, s7             # expected DONE[h]
    slli t0, s7, 2
    add  t1, t0, s3             # DONE[h]
    li   t6, 20000
o_bw:
    lw   t3, 0(t1)              # (my meip + source-55 relay happen in between)
    beq  t3, t2, o_bn
    addi t6, t6, -1
    bnez t6, o_bw
    j    shorch_fail
o_bn:
    addi t0, s7, -1             # CHECK O-7: the handler W1C-cleared that IF
    slli t0, t0, 6
    li   t1, AFE0
    add  t1, t0, t1
    lw   t3, IF_OFF(t1)
    andi t3, t3, 1
    bnez t3, shorch_fail
    addi s7, s7, 1
    li   t0, NCHAN + 1
    bltu s7, t0, o_b

    # ---- EIS self-fire (source 56, the management-owned engine) -----------
    la   t0, eis_flag
    sw   x0, 0(t0)
    li   t1, EIS
    li   t2, 1
    sw   t2, 0(t1)              # EIS CTRL bit0=1 -> soft-set IF(0): src 56
    li   t6, 20000
o_eisw:
    la   t0, eis_flag
    lw   t3, 0(t0)
    bnez t3, o_eisn
    addi t6, t6, -1
    bnez t6, o_eisw
    j    shorch_fail
o_eisn:
    li   t1, EIS                # CHECK O-8: handler W1C-cleared EIS IF
    lw   t3, IF_OFF(t1)
    andi t3, t3, 1
    bnez t3, shorch_fail

    # ---- final: every AFE IF is clear and the EIS seed survived ------------
    li   s7, 0
h0_iw:
    slli t0, s7, 6
    li   t1, AFE0
    add  t1, t0, t1
    lw   t3, IF_OFF(t1)
    andi t3, t3, 1
    bnez t3, shorch_fail        # a still-set IF = the relay never cleared it
    addi s7, s7, 1
    li   t0, NCHAN
    bltu s7, t0, h0_iw

    li   t6, EIS
    li   t0, EIS_SEED
    ori  t0, t0, 8
    lw   t1, SC8_OFF(t6)
    bne  t1, t0, shorch_fail

    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin

shorch_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # ---- populate_afe: write AFE (s6 base) regs 1..6 + 8..15 = (s8 | reg),
    # ---- read each back. Skips +0 CTRL (soft-set side effect) and +7 IF
    # ---- (W1C). Clobbers t0-t4; s6/s8 preserved; returns via ra. ----------
populate_afe:
    li   t0, 1
pa_loop:
    li   t3, 7
    beq  t0, t3, pa_skip        # skip +7 IF (W1C)
    add  t1, s8, t0             # value = pattern | reg
    slli t2, t0, 2
    add  t2, t2, s6             # &AFE[reg]
    sw   t1, 0(t2)
    lw   t4, 0(t2)
    bne  t4, t1, shorch_fail
pa_skip:
    addi t0, t0, 1
    li   t3, 16
    bltu t0, t3, pa_loop
    ret

    # ---- deny_probe (THE NEGATIVE CONTROL, half (a)) — runs on every TILE,
    # ---- and on NO other hart: hart 0 is the manager, not a subject.
    # ---- s9 = victim AFE base, s6/s8 = mine.
    # ---- Clobbers t0-t2/t6; returns via ra (never traps, never loops).
deny_probe:
    lw   t0, SC8_OFF(s9)        # victim +8 : DENIED -> must read 0 (the owner
    bnez t0, shorch_fail        # populated it nonzero at A1)
    li   t0, POISON
    add  t0, t0, s10
    sw   t0, SC8_OFF(s9)        # write poison -> dropped (denied)

    li   t6, EIS
    lw   t0, SC8_OFF(t6)        # EIS +8 : hart-0-only -> must read 0
    bnez t0, shorch_fail
    li   t0, POISON
    add  t0, t0, s10
    sw   t0, SC8_OFF(t6)        # write poison -> dropped (denied)

    add  t1, s8, 8              # my own +8 pattern
    lw   t0, SC8_OFF(s6)        # re-read OWN +8 : no foreign poison landed
    bne  t0, t1, shorch_fail
    ret

    # ---- source-55 handler: AFE_SHARED. Runs ONLY on hart 0 (the only hart
    # ---- whose router row enables 55/56) — plain-ret under the meip
    # ---- dispatcher, reached via IVT slot 55 -> 0xBC00. Reads ALL FOUR AFE
    # ---- IF words to demux — THE management privilege in the IRQ path —
    # ---- W1C-clears the fired AFE's IF (drops the LEVEL before the
    # ---- dispatcher COMPLETEs), and msips the OWNER (hart = site + 1).
    # ---- t0/t1/t2 = dispatcher-saved scratch; ra preserved (jal-zero slot).
    .section .isr_afe_shared, "ax"
afe_shared_isr:
    li   t0, 0                  # site index 0..3
ai_loop:
    slli t1, t0, 6
    li   t2, AFE0
    add  t1, t1, t2             # AFE site base
    lw   t2, IF_OFF(t1)         # its IF (management read)
    andi t2, t2, 1
    beqz t2, ai_next
    li   t2, 1
    sw   t2, IF_OFF(t1)         # W1C: clear IF(0) -> drop source 55
    li   t1, CLINT_MSIP + 4     # MSIP[site + 1] = the OWNER tile
    slli t2, t0, 2
    add  t1, t1, t2
    li   t2, 1
    sw   t2, 0(t1)              # -> wake the owner hart
ai_next:
    addi t0, t0, 1
    li   t1, NCHAN
    bltu t0, t1, ai_loop
    ret
    .previous

    # ---- source-56 handler: EIS (hart 0; plain-ret under the dispatcher,
    # ---- IVT slot 56 -> 0xBD00). W1C-clears EIS IF and sets the private wake
    # ---- flag. Clears the LEVEL before COMPLETE. --------------------------
    .section .isr_eis, "ax"
eis_isr:
    li   t0, EIS
    li   t1, 1
    sw   t1, IF_OFF(t0)         # W1C: clear EIS IF(0) -> drop source 56
    la   t0, eis_flag
    li   t1, 1
    sw   t1, 0(t0)
    ret
    .previous

    # ---- slot-83 CLINT msip ISR (runs on the woken OWNER tile, 1..4;
    # ---- classic hardware-vectored iret ISR). Clears MY msip level, ignites
    # ---- so iret resumes MAINLINE, not sleep. s10 = my hartid. ------------
msip_isr:
    addi sp, sp, -8
    sw   t0, 0(sp)
    sw   t1, 4(sp)
    slli t0, s10, 2
    li   t1, CLINT_MSIP
    add  t1, t1, t0
    sw   x0, 0(t1)              # clear MY msip level (or the IRQ re-fires)
    ignite                      # clear sleep_cpu: iret must resume MAINLINE
    lw   t0, 0(sp)
    lw   t1, 4(sp)
    addi sp, sp, 8
    iret

    # ---- env meip dispatcher (.isr_meip @0xB100) --------------------------
    MEIP_DISPATCHER()

    # ---- extend the env IVT: DEFINE_IVT emitted slots 0-82 (slots 55/56
    # ---- already point at .isr_afe_shared/.isr_eis). Add the CLINT slot 83
    # ---- (owner msip ISR), 84 (mtip: never fires — nothing arms mtimecmp,
    # ---- whose N=5 address would be 0x5030, NOT the N=4 0x5020), and 85
    # ---- (meip -> dispatcher, for hart 0's source-55/56 delivery). --------
    .section .ivt, "ax"
    .org 0x14C
    jal  zero, msip_isr         # slot 83 = IRQB_CLINT_MSIP
    jal  zero, shorch_fail      # slot 84 = IRQB_CLINT_MTIP (must never fire)
    jal  zero, 0x0B100          # slot 85 = IRQB_EXT_MEIP -> dispatcher
    .previous

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
eis_flag: .word 0
  TEST_DATA
RVTEST_DATA_END
