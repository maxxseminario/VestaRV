# See LICENSE for license details.

# VestaRV: tile IRQ fan-out through the shared IRQ router
# Deglitched peripheral levels reach every tile, gated per hart by the IRQ ROUTER at 0x7000 in the shared window: per hart h, HhENL/HhENM/HhENU at 0x7000 + 0x10*h + 0/4/8 are irq_en[31:0], [63:32] and [84:64], contiguously packed in both directions (deliberately NOT SYSTEM0's ENU write quirk). Reset is all-masked.
# Harts 1..N-1 in turn route the shared UART0's TX-complete source (IRQB_UART0_TC = 15, HhENL bit 15) to themselves through the arbiter, then sleep on extinguish with clk_cpu off. Hart 0 transmits a byte; the UTCIF level raises the routed hart's meip (IVT slot 85), waking it into the env MEIP_DISPATCHER, which claims 15 and jalrs through IVT slot 15 into the plain-ret .isr_uart0_tc handler; that handler clears the UART level through the arbiter, un-routes itself, ignites and rets, the dispatcher completes source 15 and irets, and the woken mainline reports DONE. Hart 0 then requires UTCIF == 0 and the router row == 0 before the next hart's round.
# Shared words: TURN = 0x10190 (zero-init), READY[h] = 0x101A0 + 4*h (0x4EAD0000 + h, written before hart h sleeps), DONE[h] = 0x101A0 + 4*NHARTS + 4*h (0xD01E0000 + h). DONE is placed after the NHARTS-sized READY array so it cannot overrun at N=18, where it tops at 0x1022C, below the loader rows at 0x10500.
# RACES, and each is closed by construction: hart h writes its ENL BEFORE READY[h], and the arbiter serialises, so hart 0 seeing READY[h] implies the route is up; hart 0 needs at least two more shared transactions after seeing READY while hart h extinguishes on its very next private instruction; and each ISR clears its own row before the next round, so a later transmit cannot interrupt an earlier, awake hart. Hart 0's own router row resets all-masked and is never written here, so hart 0 never takes the UART IRQ, and claim guarantees exactly-once delivery in any case.
# SMCLK RULE: the ROM boot parks SMCLK on LFXT mid-boot, so hart 0 writes SYS_CLK_CR = 0 for HFXT before any UART use. BR = 1 gives about 13.3 us frames, and every poll is bounded at 20000 iterations, inside the 100 ms tb watchdog.

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
    # ---- dispatcher jalr through IVT slot 15 -> 0x9700). Clears the UART
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

    # ---- env meip dispatcher (.isr_meip @0x9100) + IVT slot 85 -------------
    MEIP_DISPATCHER()
    IVT_ARM_MEIP()

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
