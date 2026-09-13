# See LICENSE for license details.

# VestaRV: orchestrator privilege test over the AFE and EIS stub bank
# Orchestrator-only (verify_stage tags `tiles cqAfeStubs orch`), so it is not the tape-out-configuration orchestrator test: the stub bank is dropped there, and shtcm carries that duty by keying on the TCM apertures instead.
# THE MANAGEMENT HART IS HART 0 in both chip shapes, so MGMT_HART is never overridden and the privilege is the literal s_master = 0. The four AFE sites belong to the four TILES, hart h owning AFE0 + 0x40*(h-1) for h = 1..4; the orchestrator has no site of its own, only reach into all of them. EIS is hart 0's own engine and is denied to every tile. Sources 55 (the OR of the four AFE IF lines) and 56 (EIS) route to hart 0's own router row, and hart 0 demuxes by reading all four AFE IF words, then msips the owner. Running this file against MGMT_HART = 4 RTL fails at check A2-h, which is the point.
# Hart 0 is three roles in one hart: boot master, management hart and the tb a0 gate. It is deliberately NOT a channel, because a hart cannot be both the subject and the sole judge of a privilege test; the tiles report through a0_1..a0_4.
# NEGATIVE CONTROL, in two halves, the second of which makes the first load-bearing. (a) Each tile reads a foreign tile's stub +8, which MUST read 0, then writes poison there; the victim populated that word with a distinct nonzero pattern at A1, so a 0 read proves the gate rather than an empty register. Victims rotate n = h+1 wrapped into 1..4, never the tile itself, and each tile also probes and poisons EIS +8 before re-reading its own +8. (b) Hart 0 then walks AFE0..3 +8 and EIS +8 and requires every word to still hold its owner's pattern, and requires NEGRPT, the poison tile 1 attempted, to be nonzero: a vacuous negative control in which no poison was ever written cannot pass this file.
# Phases: A1 populate (hart 0 seeds EIS +8 and opens GO, tiles fill their own AFE config +1..6 and scratch +8..F with PAT_BASE|h<<8|reg so no two (hart, reg) values alias); A2 deny; A3 management walk plus the write-reach check, then program H0ENM at 0x7004 with sources 55 and 56; B msip relay, one owner round per tile through TURN. In B the owner soft-fires its IF and sleeps on the very next instruction, while hart 0's handler needs the whole meip, claim and four-read path after that store lands, so the owner is always asleep before its msip arrives. The handler W1C-clears the fired IF BEFORE the dispatcher completes, since a still-high level would re-pend.
# CLINT addresses are derived from NHARTS: the msip array is 4*NHARTS bytes and mtime starts at 0x5000 + roundup16(4*NHARTS), so at NHARTS = 5 mtime is 0x5020 and a hardcoded 0x5010 would be wrong. Only MSIP[h] = 0x5000 + 4h is used here.
# Shared words, all below 0x10500, with the arrays sized 4*NHARTS so a bigger N cannot overrun the control words: GO = 0x104A0, DONE[h] = 0x104A4 + 4*h, PHASE = 0x104A4 + 4*NHARTS, TURN = PHASE + 4, NEGRPT = PHASE + 8. Nothing smclk-domain is touched, so the boot ROM's SMCLK-to-LFXT trap does not apply. Bounded waits are 20000, or 100000 for the first gather, which covers the tiles' ROM copy, and all trip inside the 100 ms tb watchdog.

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
    # ---- dispatcher, reached via IVT slot 55 -> 0x9C00. Reads ALL FOUR AFE
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
    # ---- IVT slot 56 -> 0x9D00). W1C-clears EIS IF and sets the private wake
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

    # ---- env meip dispatcher (.isr_meip @0x9100) --------------------------
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
    jal  zero, 0x09100          # slot 85 = IRQB_EXT_MEIP -> dispatcher
    .previous

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
eis_flag: .word 0
  TEST_DATA
RVTEST_DATA_END
