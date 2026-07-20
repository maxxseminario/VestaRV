# See LICENSE for license details.

#*****************************************************************************
# wgpio.S  (wound-config firmware smoke — FW-2)
#-----------------------------------------------------------------------------
# GPIO4 @0x6300 / GPIO5 @0x6400 firmware-synthesized-edge IRQ delivery for the
# HIGHEST source IDs, proving the 4th per-hart enable word (HhENX). Single-hart
# directed (hart 0; tiles parked).
#
# No external stimulus: pads idle LOW (prt5_in/prt6_in = tb '0', riscv_tb:291-2).
# The IES-flip idiom (GPIO.vhd:159,176-185): with prt_in=0, write PxIE=1 FIRST
# (glitch-free ICG latches En while ClkIn=0), then write PxIES=1 ->
# clk_if_comb = prt_in xor PxIES goes 0->1 -> rising edge -> PxIF set (PxIE=1)
# -> irq <= PxIF (level). Clear via PxIF W1C (clr_if pulse, GPIO.vhd:281,304).
#
# Vectors proven:  98 = GPIO4 B0 (P5.0)  ·  113 = GPIO5 B7 (P6.7)  — the
# corners of HhENX (source 98 -> bit 2, source 113 -> bit 17). PEND/INSVC RO
# words cover 0-95 only, so delivery is proven by handler DONE flags ONLY.
#
# Idiom is validated behaviorally FIRST on an unrouted pin (GPIO4 B1) before the
# routed IRQ arms rely on it.  GPIO is pure-mclk (no SYS_CLK_CR needed).
#
# GPIO reg offsets (RegSlotPx*): PxIF +24(0x18) PxIES +28(0x1C) PxIE +32(0x20).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

#define G4_IF       0x6318
#define G4_IES      0x631C
#define G4_IE       0x6320
#define G5_IF       0x6418
#define G5_IES      0x641C
#define G5_IE       0x6420
#define IRTR_ENX    0x700C
#define ENX_GPIO    0x00020004    /* bit2 (98) + bit17 (113) */

#define DONE_98     0xA000
#define DONE_113    0xA004

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   sp, 0xBFF0

    li   s0, DONE_98
    li   s1, DONE_113
    sw   x0, 0(s0)
    sw   x0, 0(s1)

    # -----------------------------------------------------------------------
    # Idiom validation (throwaway): GPIO4 B1, UNROUTED (HhENX still 0 -> no
    # delivery). Prove PxIE-then-PxIES synthesizes a rising edge that sets PxIF.
    # -----------------------------------------------------------------------
    li   t2, G4_IE
    li   t0, 0x2
    sw   t0, 0(t2)               # PxIE bit1 = 1 (latch En while ClkIn=0)
    li   t2, G4_IES
    sw   t0, 0(t2)               # PxIES bit1 = 1 -> synth edge on bit1
    li   t2, G4_IF
    li   s2, 20000
idiom_poll:
    lw   t0, 0(t2)
    andi t0, t0, 0x2
    bnez t0, idiom_ok            # PxIF bit1 set -> idiom works
    addi s2, s2, -1
    bnez s2, idiom_poll
    j    wgpio_fail
idiom_ok:
    li   t0, 0x2
    sw   t0, 0(t2)               # tidy: W1C clear PxIF bit1

    # -----------------------------------------------------------------------
    # Enable HhENX for sources 98 (bit2) and 113 (bit17) + readback
    # -----------------------------------------------------------------------
    li   s2, IRTR_ENX
    li   t1, ENX_GPIO
    sw   t1, 0(s2)
    lw   t0, 0(s2)
    bne  t0, t1, wgpio_fail

    # -----------------------------------------------------------------------
    # Arm GPIO4 B0 (vec 98): PxIE first, then PxIES -> edge -> irq -> meip
    # -----------------------------------------------------------------------
    li   t2, G4_IE
    li   t0, 0x1
    sw   t0, 0(t2)               # PxIE bit0 = 1 (bit1 enable cleared)
    li   t2, G4_IES
    sw   t0, 0(t2)               # PxIES bit0 = 1 -> synth edge on bit0

    # -----------------------------------------------------------------------
    # Arm GPIO5 B7 (vec 113): PxIE first, then PxIES
    # -----------------------------------------------------------------------
    li   t2, G5_IE
    li   t0, 0x80
    sw   t0, 0(t2)               # PxIE bit7 = 1
    li   t2, G5_IES
    sw   t0, 0(t2)               # PxIES bit7 = 1 -> synth edge on bit7

    # wait for BOTH IRQs delivered (order-independent DONE flags), bounded
    li   s3, 20000
wgpio_poll:
    lw   t0, 0(s0)               # DONE_98
    beqz t0, wgpio_dec
    lw   t1, 0(s1)               # DONE_113
    beqz t1, wgpio_dec
    j    wgpio_pass
wgpio_dec:
    addi s3, s3, -1
    bnez s3, wgpio_poll
    j    wgpio_fail

wgpio_pass:
    RVTEST_PASS

wgpio_fail:
    RVTEST_FAIL

    # ---- GPIO4 B0 handler (vec 98, plain-ret) — clear PxIF bit0 (W1C) ------
    .section .text.init
gpio4_b0_h:
    li   t0, G4_IF
    li   t1, 0x1
    sw   t1, 0(t0)               # W1C -> drop the level
    li   t0, DONE_98
    li   t1, 0x00000098
    sw   t1, 0(t0)
    ret

    # ---- GPIO5 B7 handler (vec 113, plain-ret) — clear PxIF bit7 (W1C) -----
gpio5_b7_h:
    li   t0, G5_IF
    li   t1, 0x80
    sw   t1, 0(t0)               # W1C -> drop the level
    li   t0, DONE_113
    li   t1, 0x00000113
    sw   t1, 0(t0)
    ret

    # ---- per-test IVT tail: arm 83/84/85 then slots 98 & 113 --------------
    .section .ivt, "ax"
    .org 0x14C
    jal  zero, 0x0BB00           # 83 msip  -> park
    jal  zero, 0x0BB00           # 84 mtip  -> park
    jal  zero, 0x0B100           # 85 meip  -> env dispatcher (.isr_meip)
    .org 0x188
    jal  zero, gpio4_b0_h        # 98  (0x8188)
    .org 0x1C4
    jal  zero, gpio5_b7_h        # 113 (0x81C4)
    .previous

    # ---- env meip dispatcher (.isr_meip @0xB100) --------------------------
    MEIP_DISPATCHER()

    RVTEST_CODE_END              # unimp (traps) — never reached

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
