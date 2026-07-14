# See LICENSE for license details.

#*****************************************************************************
# shirq.S  (M7a; M12 single-ROM boot rework)
#-----------------------------------------------------------------------------
# HART-GENERIC tile-IRQ-fan-out test — the M7a signature test.
#
# M12: tiles are NO LONGER preloaded. Hart 0 stages this TCM image once and
# launches all three tiles into tile_entry through the bootrom loader
# (mp_boot.h); each tile then parks on TURN just as before. The launch's msip
# is the ROM loader's; the routed UART IRQ that later wakes each tile is taken
# by the tile's OWN slot-15 ISR (copied into its TCM). TURN, the router
# protocol, and the sleep/wake dance are all unchanged.
#
# Before M7a, peripheral IRQs terminated ONLY in hart 0's SYSTEM; tiles had
# just the hardwired CLINT slots 83/84. M7a fans the deglitched peripheral
# levels out to every tile, gated per hart by the shared-window IRQ ROUTER at
# 0x7000 (page-0x6000 slot 9): per hart h, HhENL/HhENM/HhENU at
# 0x7000 + 0x10*h + 0/4/8 = irq_en[31:0]/[63:32]/[84:64], contiguous packing
# both directions (deliberately NOT SYSTEM0's ENU write quirk). Reset = all
# masked.
#
# THIS TEST (M19 claim/complete rework — the delivery path changed, the
# protocol did not): harts 1-3 IN TURN route the shared UART0's TX-complete
# IRQ (source IRQB_UART0_TC = 15 -> HhENL bit 15) to THEMSELVES through the
# arbiter, then SLEEP (extinguish, clk_cpu off). Hart 0 transmits a byte on
# the shared UART0; the UTCIF level raises the routed hart's meip (IVT slot
# 85), which wakes it into the env MEIP_DISPATCHER: CLAIM returns 15, the
# dispatcher jalr's through IVT slot 15 into the .isr_uart0_tc HANDLER
# (plain-ret ABI) which clears the UART level THROUGH THE ARBITER, un-routes
# itself, ignites, and rets; the dispatcher COMPLETEs source 15 and irets;
# the woken mainline reports DONE. Hart 0 then verifies UTCIF==0 and the
# router row ==0 (the handler really ran on the other hart), and moves to
# the next hart. So each round proves: router row write by tile hart ->
# meip delivery -> wake from sleep -> claim -> IVT-table dispatch ->
# handler shared-window accesses -> complete -> route teardown.
#
# Shared words (>= 0x10190, clear of all earlier tests' words):
#     TURN     = 0x10190                  which hart's round it is (zero-init)
#     READY[h] = 0x101A0 + 4*h            0x4EAD0000+h before hart h sleeps
#     DONE[h]  = 0x101A0 + 4*NHARTS + 4*h 0xD01E0000+h after hart h wakes
# Argus A3: DONE base = READY_BASE + 4*NHARTS (placed after the NHARTS-sized
# READY array so it can't overrun at N=18). N=4: DONE base 0x101B0 (unchanged);
# N=18: READY 0x101A4..0x101E4, DONE 0x101EC..0x1022C, all < 0x10500.
# (next free shared word: 0x101C0 at N=4)
#
# RACE NOTES:
#  * router-write-before-transmit: hart h writes its ENL BEFORE READY[h]; the
#    arbiter serializes, so hart 0 observing READY[h] implies the route is up.
#  * sleep-before-IRQ: as in shwfi — hart 0 needs >= 2 more shared txns
#    (DONE==0 check, TX write) after observing READY, while hart h
#    extinguishes on its very next private instruction.
#  * one-route-at-a-time: each ISR clears ITS OWN row before the next round,
#    so a later transmit's UTCIF can never IRQ an earlier (awake) hart.
#
# Hart 0 never takes UART IRQs itself: its router row (row 0 — LIVE since
# M19) resets all-masked and this test never writes it (CR.TCIE is set,
# which feeds the level into irq_comb — masked at hart 0, ROUTED at the
# tiles). Claim also guarantees exactly-once: even a multi-hart route could
# not double-deliver.
#
# SMCLK RULE (M6 war story): the ROM bootrom parks SMCLK on LFXT mid-boot;
# hart 0 writes SYS_CLK_CR=0 (HFXT) before any UART use. BR=1 -> ~13.3us
# frames; all polls bounded 20000 (trip inside the 100ms tb watchdog).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_UART    0x4400
#define SH_IRTR    0x7000
#define TURN       0x10190
#define READY_BASE 0x101A0
#define DONE_BASE  (READY_BASE + 4*NHARTS)   /* after the NHARTS-sized READY array */
#define BR_VAL     1
#define CR_EN_TCIE 0x21          /* UART enable + TX-complete IRQ enable */
#define ENL_UART0_TC (1 << 15)   /* IRQB_UART0_TC in irq_en[31:0] */

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..3 (the ISR reads it too — never clobber)
    .option pop
    bnez s10, tile_entry        # M12: only hart 0 runs the launcher

    # M12 single-ROM boot: stage this TCM image once, launch all three tiles
    # into tile_entry (mp_boot.h). They park on TURN just as the old preloaded
    # tiles did; hart 0 falls through to its UART setup + round loop.
    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_ALL(tile_entry, 4096)

tile_entry:                     # tiles enter here (loader ABI: only sp defined)
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # re-derive (the ISR reads it too — never clobber)
    .option pop

    li   sp, 0xBFF0             # private TCM top; IRQ_SV pushes PC at sp-4

    li   s2, SH_UART            # +0 CR, +4 SR, +8 BR, +16 TX
    li   s3, TURN
    li   s4, READY_BASE
    li   s5, DONE_BASE
    li   s6, SH_IRTR

    beqz s10, hart0

    # ---- harts 1-3: park on TURN (reads only, unbounded — hart 0 is still
    # ---- SPI-booting), then one supervised routed-IRQ sleep/wake ----------
turn_wait:
    lw   t0, 0(s3)
    bne  t0, s10, turn_wait

    slli t1, s10, 4
    add  t1, t1, s6             # my router row: HhENL @ 0x7000 + 0x10*h
    li   t0, ENL_UART0_TC
    sw   t0, 0(t1)              # route UART0_TC to ME...
    lw   t2, 0(t1)              # ...and prove the write landed (readback)
    bne  t2, t0, shirq_fail

    slli t0, s10, 2
    add  t0, t0, s4             # my READY word
    li   t1, 0x4EAD0000
    add  t1, t1, s10
    sw   t1, 0(t0)              # READY...
    extinguish                  # ...and clk_cpu OFF (see race notes)

    # ---- here only after the routed UART ISR ignited + iret'd -------------
    slli t0, s10, 2
    add  t0, t0, s5             # my DONE word
    li   t1, 0xD01E0000
    add  t1, t1, s10
    sw   t1, 0(t0)              # report DONE (real wake proof)
    li   a0, 0xCAFEBABE         # inline PASS (tb latches a0_1/2/3)
tile_verify:                    # forever: DONE must survive other traffic
    lw   t2, 0(t0)
    bne  t2, t1, shirq_fail
    j    tile_verify

    # ---- hart 0: UART setup, then one routed wake per hart in turn --------
hart0:
    li   t0, 0x4900             # SYSTEM0: SYS_CLK_CR at +0
    sw   zero, 0(t0)            # SMCLK -> HFXT (bootrom left it on LFXT)

    li   t0, BR_VAL
    sw   t0, 8(s2)              # BR = 1 (baud = smclk/32)
    lw   t1, 8(s2)
    bne  t1, t0, shirq_fail

    li   t0, CR_EN_TCIE
    sw   t0, 0(s2)              # CR = enable + TCIE (level into irq_comb)
    lw   t1, 0(s2)
    bne  t1, t0, shirq_fail

    li   s7, 1                  # current hart
round_loop:
    sw   s7, 0(s3)              # TURN = h: release hart h to route + sleep

    slli t0, s7, 2
    add  t1, t0, s4             # READY[h]
    li   t2, 0x4EAD0000
    add  t2, t2, s7
    li   t6, 100000             # M12: first round covers the tile's ROM copy
                                # after launch (fits the 100ms watchdog)
ready_wait:
    lw   t3, 0(t1)
    beq  t3, t2, is_ready
    addi t6, t6, -1
    bnez t6, ready_wait
    j    shirq_fail
is_ready:
    add  t1, t0, s5             # DONE[h]: must still be 0 — hart is asleep
    lw   t3, 0(t1)
    bnez t3, shirq_fail

    li   t3, 0x41               # 'A' + h
    add  t3, t3, s7
    sw   t3, 16(s2)             # TX: ~13.3us later UTCIF wakes hart h

    li   t2, 0xD01E0000
    add  t2, t2, s7
    li   t6, 20000
wake_wait:
    lw   t3, 0(t1)
    beq  t3, t2, woke
    addi t6, t6, -1
    bnez t6, wake_wait
    j    shirq_fail
woke:
    lw   t3, 4(s2)              # its ISR must have cleared UTCIF...
    andi t3, t3, 1
    bnez t3, shirq_fail
    slli t3, s7, 4
    add  t3, t3, s6
    lw   t4, 0(t3)              # ...and un-routed itself (HhENL == 0)
    bnez t4, shirq_fail

    addi s7, s7, 1
    li   t0, NHARTS
    bne  s7, t0, round_loop

    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin

shirq_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # ---- UART0_TC HANDLER (M19 plain-ret ABI; reached via CLAIM=15 ->
    # ---- dispatcher jalr through IVT slot 15 -> 0xB700). Clears the UART
    # ---- LEVEL through the arbiter BEFORE returning (complete follows in
    # ---- the dispatcher), un-routes itself, ignites (the dispatcher's iret
    # ---- must resume MAINLINE, not sleep). t0/t1 are dispatcher-saved
    # ---- scratch; ra untouched; s10 = my hartid from mainline. -------------
    .section .isr_uart0_tc, "ax"
uart0_tc_isr:
    li   t0, SH_UART
    li   t1, 1
    sw   t1, 4(t0)              # SR bit0 -> clr_UTCIF: drop the level
    slli t0, s10, 4
    li   t1, SH_IRTR
    add  t1, t1, t0
    sw   x0, 0(t1)              # un-route MYSELF (HhENL = 0)
    ignite                      # clear sleep_cpu: the dispatcher's iret
                                # then resumes mainline
    ret
    .previous

    # ---- env meip dispatcher (.isr_meip @0xB100) + IVT slot 85 -------------
    MEIP_DISPATCHER()
    IVT_ARM_MEIP()

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
