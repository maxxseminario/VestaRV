# See LICENSE for license details.

#*****************************************************************************
# shafe.S  (CQ2b — Castalia-Quad AFE / EIS digital-stub test)
#-----------------------------------------------------------------------------
# HART-GENERIC test of the four per-hart AFE register stubs (0x4C00/40/80/C0)
# + the shared EIS engine stub (0x7C00), and the hart-0-relay IRQ scheme that
# aggregates their level interrupts onto irq_router sources 55 (AFE_SHARED =
# OR of the four AFE IF lines) and 56 (EIS).
#
# AFE stub = a shared arbiter slave with an s_master OWNERSHIP GATE: AFE h
# answers only when s_master==h OR s_master==0 (hart 0 = management hart,
# reaches every site); EIS answers only when s_master==0. A DENIED read
# returns 0, a DENIED write is dropped. Register map (word offset in the 64 B
# sub-slot): +0 CTRL (write bit0=1 SOFT-SETS IF(0) — the test hook), +1..6
# config placeholders, +7 IF (W1C, drives the level irq), +8..F scratch.
#
# M12: tiles are NOT preloaded. Hart 0 stages this TCM image once and launches
# all tiles into tile_entry through the bootrom loader (mp_boot.h). Every hart
# runs the SAME image at the SAME addresses; the source-55/56 handlers and the
# EIS self-fire only ever run on hart 0 (the only master that can read all four
# AFE IF words to demux a shared source), the slot-83 CLINT msip ISR only on a
# woken owner tile.
#
# PHASE A (gating), barriered by hart 0 through PHASE:
#   A1 populate: every hart writes its OWN AFE (hart h -> AFE h) config words
#      (+1..6) + scratch words (+8..F) with a DISTINCT per-hart pattern
#      (PAT_BASE | h<<8 | reg) and reads each back. Hart 0 also seeds EIS +8.
#      A gating LEAK cannot alias — every (hart,reg) value is unique. Tiles
#      then mark DONE[h]=A1; hart 0 gathers, opens PHASE=1.
#   A2 probe/deny: each tile probes a NEIGHBOUR AFE (n = h+1 wrapped into
#      1..N-1, so n!=h and n!=0 -> the tile is neither owner nor hart 0):
#        * read neighbour +8  -> MUST read 0 (denied; neighbour populated it
#          nonzero at A1, so 0 proves the gate, not an empty register)
#        * write POISON to neighbour +8 -> dropped
#      then the same denial against EIS (+8, hart-0-only), then RE-READS its
#      OWN +8 and proves it still holds its pattern (no neighbour's poison
#      landed). Tiles mark DONE[h]=A2. Hart 0 gathers, then WALKS all four
#      AFEs (read +8 == owner pattern, write +15 read-back — proving hart 0's
#      read AND write reach every site) + EIS read/write, then opens PHASE=2.
#
# PHASE B (hart-0 IRQ relay), one owner round per tile through TURN:
#   Hart 0 unmasks sources 55+56 in ITS routing row only (H0ENM bits 23/24 =
#   sources 55/56 in irq_en[63:32]) and arms the env MEIP_DISPATCHER (IVT slot
#   85) + the slot-83 CLINT ISR. Per owner tile h: hart 0 sets TURN=h; the tile
#   soft-fires AFE h IF via CTRL bit0 (raising afe_eis_irq(h) -> source 55) and
#   SLEEPS on the very next instruction (extinguish). Hart 0's source-55 handler
#   (plain-ret under the dispatcher) reads the four AFE IF words to demux, W1C-
#   clears the fired AFE's IF (drops the LEVEL BEFORE the dispatcher COMPLETEs —
#   a still-high level would re-pend), and msips the owner via CLINT. The owner's
#   slot-83 CLINT ISR clears its msip level, ignites (so iret resumes MAINLINE
#   on the sleeping hart) and irets; the owner records DONE[h]=B. Finally hart 0
#   self-fires EIS via source 56; its source-56 handler W1C-clears EIS IF and
#   sets a private flag.
#   RACE (same guarantee as shwfi): the owner extinguishes 1 private instruction
#   after its IF store, while hart 0's msip needs the whole handler path (claim +
#   four AFE reads + msip write = many arbiter txns) after that store lands — so
#   the owner is always asleep before its msip arrives.
#
# Shared-word ledger (CQ2b; shpwr ends 0x10474, next free block 0x10480; all
# < 0x10500; arrays 4*NHARTS so control words can't be overrun at N=18):
#     GO        = 0x10480                which harts may start phase A
#     DONE[h]   = 0x10484 + 4*h          per-hart phase progress (A1/A2/B magic)
#     PHASE     = 0x10484 + 4*NHARTS     hart-0 phase barrier (N=4 0x10494)
#     TURN      = PHASE + 4              phase-B owner round     (N=4 0x10498)
#   (next free shared word: 0x1049C at N=4; N=18 TURN=0x104D0, all < 0x10500)
#
# No smclk-domain peripheral is touched (AFE/EIS/CLINT/irq_router are all mclk),
# so the bootrom SMCLK->LFXT trap does not apply — no SYS_CLK_CR write needed.
# Bounded waits 20000 (100000 for the first gather, covering the tile ROM copy)
# all trip inside the 100 ms tb watchdog.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define AFE0        0x4C00          /* AFE h base = AFE0 + 0x40*h */
#define EIS         0x7C00
#define SH_IRTR     0x7000          /* HhENL/M/U at +0x10*h + 0/4/8 */
#define CLINT_MSIP  0x5000
#define GO          0x10480
#define DONE_BASE   0x10484
#define PHASE       (DONE_BASE + 4*NHARTS)
#define TURN        (PHASE + 4)
#define GO_MAGIC    0x600DAFE0
#define A1_MAGIC    0xA1E00000
#define A2_MAGIC    0xA2E00000
#define B_MAGIC     0xBEE00000
#define PAT_BASE    0x5AFE0000
#define POISON      0xBAD00000
#define EIS_SEED    0xE15E0000
#define WALK_MAGIC  0xC0DE0000
#define H0ENM_5556  0x01800000      /* sources 55,56 in irq_en[63:32] = bits 23,24 */
#define IF_OFF      0x1C            /* +7  interrupt-flag word (W1C) */
#define SC8_OFF     0x20           /* +8  first scratch word */
#define SC15_OFF    0x3C           /* +15 last scratch word (hart-0 write reach) */

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..N-1 (the ISRs read it too — never clobber)
    .option pop
    bnez s10, tile_entry        # M12: only hart 0 runs the launcher

    # M12 single-ROM boot: stage this TCM image once, launch all tiles into
    # tile_entry (mp_boot.h). They park on GO; hart 0 falls through to setup.
    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_ALL(tile_entry, 4096)

tile_entry:                     # tiles enter here (loader ABI: only sp defined)
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # re-derive (undefined for tiles until now)
    .option pop

    li   sp, 0xBFF0             # private TCM top; IRQ_SV pushes PC at sp-4
    li   s2, GO
    li   s3, DONE_BASE
    li   s4, PHASE
    li   s5, TURN
    slli t0, s10, 6             # 0x40*h
    li   t1, AFE0
    add  s6, t0, t1             # s6 = my own AFE base (AFE0 + 0x40*h)
    li   t0, PAT_BASE
    slli t1, s10, 8
    or   s8, t0, t1             # s8 = my AFE pattern (PAT_BASE | h<<8)

    beqz s10, hart0

    # ================= tiles (harts 1..N-1) =================================
    # ---- A1 populate: wait GO, write own AFE, mark DONE[h]=A1 --------------
tile_go_wait:
    lw   t0, 0(s2)
    li   t1, GO_MAGIC
    bne  t0, t1, tile_go_wait

    jal  ra, populate_afe       # write+verify AFE h regs 1..6, 8..15

    slli t0, s10, 2
    add  t0, t0, s3             # DONE[h]
    li   t1, A1_MAGIC
    add  t1, t1, s10
    sw   t1, 0(t0)              # DONE[h] = A1

    # ---- wait PHASE==1, then A2 probe/deny --------------------------------
    li   t1, 1
tile_ph1_wait:
    lw   t0, 0(s4)
    bne  t0, t1, tile_ph1_wait

    # neighbour n = h+1, wrapped into 1..N-1 (n != h and n != 0)
    addi t5, s10, 1
    li   t3, NHARTS
    bne  t5, t3, nb_have
    li   t5, 1
nb_have:
    slli t0, t5, 6
    li   t1, AFE0
    add  t6, t0, t1            # t6 = neighbour AFE base

    lw   t0, SC8_OFF(t6)       # neighbour +8 : DENIED -> must read 0
    bnez t0, shafe_fail
    li   t0, POISON
    add  t0, t0, s10
    sw   t0, SC8_OFF(t6)       # write poison -> dropped (denied)

    li   t6, EIS
    lw   t0, SC8_OFF(t6)       # EIS +8 : DENIED for a tile -> must read 0
    bnez t0, shafe_fail
    li   t0, POISON
    add  t0, t0, s10
    sw   t0, SC8_OFF(t6)       # write poison -> dropped (denied)

    add  t1, s8, 8            # my own +8 pattern
    lw   t0, SC8_OFF(s6)      # re-read OWN +8 : no neighbour poison landed
    bne  t0, t1, shafe_fail

    slli t0, s10, 2
    add  t0, t0, s3           # DONE[h]
    li   t1, A2_MAGIC
    add  t1, t1, s10
    sw   t1, 0(t0)            # DONE[h] = A2

    # ---- wait PHASE==2, then one phase-B relay round ----------------------
    li   t1, 2
tile_ph2_wait:
    lw   t0, 0(s4)
    bne  t0, t1, tile_ph2_wait

tile_turn_wait:
    lw   t0, 0(s5)            # TURN
    bne  t0, s10, tile_turn_wait

    li   t0, 1
    sw   t0, 0(s6)           # AFE h CTRL bit0=1 -> soft-set IF(0): raise src 55
    extinguish               # ...sleep on the NEXT instruction (see RACE note)

    # ---- here only after hart 0's msip -> slot-83 ISR ignited + iret'd ----
    li   t1, B_MAGIC
    add  t1, t1, s10
    slli t0, s10, 2
    add  t0, t0, s3          # DONE[h]
    sw   t1, 0(t0)           # DONE[h] = B (real wake proof)
    li   a0, 0xCAFEBABE      # inline PASS (tb latches a0_1/2/3)
tile_verify:                 # forever: DONE must survive other traffic
    lw   t2, 0(t0)
    bne  t2, t1, shafe_fail
    j    tile_verify

    # ================= hart 0 ===============================================
hart0:
    # unmask sources 55+56 to hart 0's OWN routing row only (H0ENM = irq_en
    # [63:32]; source 55 -> bit 23, source 56 -> bit 24)
    li   t0, SH_IRTR
    li   t1, H0ENM_5556
    sw   t1, 4(t0)           # H0ENM
    lw   t2, 4(t0)
    bne  t2, t1, shafe_fail

    jal  ra, populate_afe    # populate AFE0 (s6=AFE0, s8=PAT_BASE for h=0)

    li   t0, EIS             # seed EIS +8 (nonzero) so a tile's later read-0
    li   t1, EIS_SEED        # denial is unambiguous, and the walk can prove no
    ori  t1, t1, 8           # tile poison landed
    sw   t1, SC8_OFF(t0)
    lw   t2, SC8_OFF(t0)
    bne  t2, t1, shafe_fail

    li   t0, GO_MAGIC
    sw   t0, 0(s2)           # open GO: every tile may start phase A

    # ---- A1 gather (first wait covers the tiles' ROM copy after launch) ----
    li   s7, 1
h0_a1:
    li   t6, 100000
    slli t0, s7, 2
    add  t0, t0, s3          # DONE[s7]
    li   t1, A1_MAGIC
    add  t1, t1, s7
h0_a1w:
    lw   t2, 0(t0)
    beq  t2, t1, h0_a1n
    addi t6, t6, -1
    bnez t6, h0_a1w
    j    shafe_fail
h0_a1n:
    addi s7, s7, 1
    li   t0, NHARTS
    bltu s7, t0, h0_a1

    li   t0, 1
    sw   t0, 0(s4)           # PHASE = 1: release tiles into A2 probe/deny

    # ---- A2 gather --------------------------------------------------------
    li   s7, 1
h0_a2:
    li   t6, 20000
    slli t0, s7, 2
    add  t0, t0, s3          # DONE[s7]
    li   t1, A2_MAGIC
    add  t1, t1, s7
h0_a2w:
    lw   t2, 0(t0)
    beq  t2, t1, h0_a2n
    addi t6, t6, -1
    bnez t6, h0_a2w
    j    shafe_fail
h0_a2n:
    addi s7, s7, 1
    li   t0, NHARTS
    bltu s7, t0, h0_a2

    # ---- hart 0 WALK: read every AFE +8 (owner pattern SURVIVED, no tile
    # ---- poison landed) + write every AFE +15 with read-back (write reach),
    # ---- then EIS read/write (hart-0-allowed) ------------------------------
    li   s7, 0               # n = 0
h0_walk:
    slli t0, s7, 6
    li   t1, AFE0
    add  t6, t0, t1          # AFE n base
    li   t1, PAT_BASE
    slli t0, s7, 8
    or   t1, t1, t0
    ori  t2, t1, 8           # expected AFE n +8 = pattern | 8
    lw   t0, SC8_OFF(t6)
    bne  t0, t2, shafe_fail
    li   t0, WALK_MAGIC
    add  t0, t0, s7
    sw   t0, SC15_OFF(t6)    # hart-0 write reach: AFE n +15
    lw   t3, SC15_OFF(t6)
    bne  t3, t0, shafe_fail
    addi s7, s7, 1
    li   t0, NHARTS
    bltu s7, t0, h0_walk

    li   t6, EIS
    li   t0, EIS_SEED
    ori  t0, t0, 8
    lw   t1, SC8_OFF(t6)     # EIS +8 == seed (no tile poison landed)
    bne  t1, t0, shafe_fail
    li   t0, WALK_MAGIC
    sw   t0, 0x24(t6)        # EIS +9 write + read-back (hart-0 EIS write)
    lw   t1, 0x24(t6)
    bne  t1, t0, shafe_fail

    li   t0, 2
    sw   t0, 0(s4)           # PHASE = 2: release tiles into phase B

    # ---- PHASE B: one owner round per tile through TURN --------------------
    li   s7, 1
h0_b:
    sw   s7, 0(s5)           # TURN = h -> release owner h to fire + sleep
    li   t2, B_MAGIC
    add  t2, t2, s7          # expected DONE[h]
    slli t0, s7, 2
    add  t1, t0, s3          # DONE[h]
    li   t6, 20000
h0_bw:
    lw   t3, 0(t1)           # (the source-55 meip + relay happen in between)
    beq  t3, t2, h0_bn
    addi t6, t6, -1
    bnez t6, h0_bw
    j    shafe_fail
h0_bn:
    slli t0, s7, 6           # verify the handler W1C-cleared AFE h IF
    li   t1, AFE0
    add  t1, t0, t1
    lw   t3, IF_OFF(t1)
    andi t3, t3, 1
    bnez t3, shafe_fail
    addi s7, s7, 1
    li   t0, NHARTS
    bltu s7, t0, h0_b

    # ---- EIS self-fire (source 56, hart 0) --------------------------------
    la   t0, eis_flag
    sw   x0, 0(t0)
    li   t1, EIS
    li   t2, 1
    sw   t2, 0(t1)           # EIS CTRL bit0=1 -> soft-set IF(0): raise src 56
    li   t6, 20000
h0_eisw:
    la   t0, eis_flag
    lw   t3, 0(t0)
    bnez t3, h0_eisn
    addi t6, t6, -1
    bnez t6, h0_eisw
    j    shafe_fail
h0_eisn:
    li   t1, EIS             # handler W1C-cleared EIS IF
    lw   t3, IF_OFF(t1)
    andi t3, t3, 1
    bnez t3, shafe_fail

    RVTEST_PASS              # a0 = 0xCAFEBABE, spin

shafe_fail:
    RVTEST_FAIL             # a0 = 0xDEADBEEF, spin

    # ---- populate_afe: write AFE (s6 base) regs 1..6 + 8..15 = (s8 | reg),
    # ---- read each back. Skips +0 CTRL (soft-set side effect) and +7 IF
    # ---- (W1C). Clobbers t0-t4; s6/s8 preserved; returns via ra. ----------
populate_afe:
    li   t0, 1
pa_loop:
    li   t3, 7
    beq  t0, t3, pa_skip     # skip +7 IF (W1C)
    add  t1, s8, t0          # value = pattern | reg
    slli t2, t0, 2
    add  t2, t2, s6          # &AFE[reg]
    sw   t1, 0(t2)
    lw   t4, 0(t2)
    bne  t4, t1, shafe_fail
pa_skip:
    addi t0, t0, 1
    li   t3, 16
    bltu t0, t3, pa_loop
    ret

    # ---- source-55 handler: AFE_SHARED (hart 0; plain-ret under the meip
    # ---- dispatcher, reached via IVT slot 55 -> 0xBC00). Reads the four AFE
    # ---- IF words to demux, W1C-clears the fired AFE's IF (drops the LEVEL
    # ---- before the dispatcher COMPLETEs), and msips the owner via CLINT.
    # ---- t0/t1/t2 = dispatcher-saved scratch; ra preserved (jal-zero slot).
    .section .isr_afe_shared, "ax"
afe_shared_isr:
    li   t0, 1               # owner harts start at 1 (AFE0 is hart 0's own)
ai_loop:
    slli t1, t0, 6
    li   t2, AFE0
    add  t1, t1, t2          # AFE t0 base
    lw   t2, IF_OFF(t1)      # AFE t0 IF
    andi t2, t2, 1
    beqz t2, ai_next
    li   t2, 1
    sw   t2, IF_OFF(t1)      # W1C: clear AFE t0 IF(0) -> drop source 55
    li   t1, CLINT_MSIP
    slli t2, t0, 2
    add  t1, t1, t2
    li   t2, 1
    sw   t2, 0(t1)           # CLINT MSIP[t0] = 1 -> wake owner hart
ai_next:
    addi t0, t0, 1
    li   t1, NHARTS
    bltu t0, t1, ai_loop
    ret
    .previous

    # ---- source-56 handler: EIS (hart 0; plain-ret under the dispatcher,
    # ---- reached via IVT slot 56 -> 0xBD00). W1C-clears EIS IF and sets the
    # ---- private wake flag. Clears the LEVEL before COMPLETE. --------------
    .section .isr_eis, "ax"
eis_isr:
    li   t0, EIS
    li   t1, 1
    sw   t1, IF_OFF(t0)      # W1C: clear EIS IF(0) -> drop source 56
    la   t0, eis_flag
    li   t1, 1
    sw   t1, 0(t0)
    ret
    .previous

    # ---- slot-83 CLINT msip ISR (runs on the woken owner tile; classic
    # ---- hardware-vectored iret ISR). Clears MY msip level, ignites so iret
    # ---- resumes MAINLINE, not sleep. s10 = my hartid. --------------------
msip_isr:
    addi sp, sp, -8
    sw   t0, 0(sp)
    sw   t1, 4(sp)
    slli t0, s10, 2
    li   t1, CLINT_MSIP
    add  t1, t1, t0
    sw   x0, 0(t1)           # clear MY msip level (or the IRQ re-fires)
    ignite                   # clear sleep_cpu: iret must resume MAINLINE
    lw   t0, 0(sp)
    lw   t1, 4(sp)
    addi sp, sp, 8
    iret

    # ---- env meip dispatcher (.isr_meip @0xB100) --------------------------
    MEIP_DISPATCHER()

    # ---- extend the env IVT: DEFINE_IVT emitted slots 0-82 (slots 55/56 now
    # ---- point at .isr_afe_shared/.isr_eis via the env retarget). Add the
    # ---- CLINT slot 83 (owner msip ISR), 84 (mtip: never fires), and 85
    # ---- (meip -> dispatcher, for hart 0's source-55/56 delivery). --------
    .section .ivt, "ax"
    .org 0x14C
    jal  zero, msip_isr      # slot 83 = IRQB_CLINT_MSIP
    jal  zero, shafe_fail    # slot 84 = IRQB_CLINT_MTIP (must never fire)
    jal  zero, 0x0B100       # slot 85 = IRQB_EXT_MEIP -> dispatcher (.isr_meip)
    .previous

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
eis_flag: .word 0
  TEST_DATA
RVTEST_DATA_END
