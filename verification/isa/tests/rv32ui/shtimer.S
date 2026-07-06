# See LICENSE for license details.

#*****************************************************************************
# shtimer.S  (M7b; M12 single-ROM boot rework)
#-----------------------------------------------------------------------------
# HART-GENERIC shared TIMER0/1 + GPIO1/2/3 test — the M7b signature test.
#
# M12: tiles are NO LONGER preloaded. Hart 0 stages this TCM image once and
# launches harts 1-3 into tile_entry through the bootrom loader (mp_boot.h);
# each tile then parks on the token. The token ring (0x101C0) is unchanged.
#
# M7b moved TIMER0/TIMER1/GPIO1/GPIO2/GPIO3 off hart 0's private peripheral
# bus and onto the mp_arbiter in the 0x6000 page, whose 16 x 256B slots
# M11 map rework: the shared window slots ARE the legacy addresses now:
#     GPIO1 0x4100   TIMER0 0x4600   TIMER1 0x4700   GPIO2 0x4800
#     GPIO3 0x4D00   (irq_router @0x7000, window page 3)
# Register offsets unchanged. The old private windows read zeros. GPIO0
# (0x4000) is SHARED since M11 like everything else; the ROM bootrom still
# PxOUTS/PxOUTC and programs its DIR/SEL on every SPI boot (same class as
# SPI0/SYSTEM0).
#
# Token ring (deterministic, shuart pattern): hart 0 checks the old windows
# are dead + GPIO0 old window is ALIVE + GPIO1's reset config reads back at
# 0x4100 (read-only: its PxSEL routes the UART0/UART1 pads — do not write),
# then runs the full timer dance on TIMER1; hart 1 runs it on TIMER0 (a TILE
# hart owning a shared timer) and checks TIMER1's CMP0 still holds hart 0's
# value (cross-hart config visibility); harts 2/3 run the GPIO register
# dance (OUT/OUTS/OUTC/OUTT/IES semantics) on GPIO2/GPIO3 with PxDIR left 0
# (ports stay inputs — nothing drives the pads).
#
# Timer dance (per timer, clock source = MCLK, no divider): CR reads 0 at
# reset; CMP0 write/readback; enable; bounded-poll VAL until it counts past
# the first sample (the glitch-free clock mux DEFAULTS to the smclk slice and
# needs 3 smclk edges to release it before mclk engages — hence also the
# SYS_CLK_CR=0 write below, or that handoff takes ~92us of LFXT); CMP0 match
# sets SR bit0; SR write-1 clears it; disable freezes VAL. All polls bounded
# 20000 (inside the 100ms watchdog).
# Timer IRQ enables stay 0 (their fixed IVT slot targets 0x7A00-0x9000
# collide with the IVT/_start — routed-IRQ wake is proven by shirq/M7a).
#
# Shared words (>= 0x101C0, clear of all earlier tests' words):
#     TOKEN    = 0x101C0          whose turn (shram zero-init => hart 0)
#     DONE[h]  = 0x101D0 + 4*h    0x71E40000+h after hart h's dance
# (next free shared word: 0x101E0)
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_TIMER0  0x4600
#define SH_TIMER1  0x4700
#define SH_GPIO1   0x4100
#define SH_GPIO2   0x4800
#define SH_GPIO3   0x4D00
#define TOKEN      0x101C0
#define DONE_BASE  0x101D0
#define TIM_CR_EN_MCLK 0x140     /* clock source 01 = mclk, timer enable */
#define TIM_CMP0_VAL   0x300

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..3
    .option pop
    bnez s10, tile_entry        # M12: only hart 0 runs the launcher

    # M12 single-ROM boot: stage this TCM image once, then launch all three
    # tiles into tile_entry through the bootrom loader (mp_boot.h). They park
    # on the token just as the old preloaded tiles did.
    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_HART(1, tile_entry, 4096)
    MP_LAUNCH_HART(2, tile_entry, 4096)
    MP_LAUNCH_HART(3, tile_entry, 4096)

tile_entry:                     # tiles enter here (loader ABI: only sp defined)
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # re-derive (undefined for tiles until now)
    .option pop

    li   sp, 0xBFF0             # private TCM top (IRQ_SV contract)

    li   s3, TOKEN
    li   s4, DONE_BASE
    li   s6, 0x71E40000         # DONE magic base

    beqz s10, hart0

    # ---- harts 1-3: park on the token (reads only), then one dance --------
token_wait:
    lw   t0, 0(s3)
    bne  t0, s10, token_wait

    li   t0, 2
    beq  s10, t0, hart2
    li   t0, 3
    beq  s10, t0, hart3

    # ---- hart 1: TIMER0 full dance + TIMER1 cross-hart visibility ---------
    li   s2, SH_TIMER1
    lw   t0, 12(s2)             # TIMER1 CMP0: hart 0's value must be visible
    li   t1, TIM_CMP0_VAL
    bne  t0, t1, shtimer_fail
    li   s2, SH_TIMER0
    jal  ra, timer_dance        # a TILE hart owns a shared timer
    j    report

    # ---- hart 2: GPIO2 register dance --------------------------------------
hart2:
    li   s2, SH_GPIO2
    jal  ra, gpio_dance
    j    report

    # ---- hart 3: GPIO3 register dance --------------------------------------
hart3:
    li   s2, SH_GPIO3
    jal  ra, gpio_dance

report:
    slli t0, s10, 2
    add  t0, t0, s4
    add  t1, s6, s10
    sw   t1, 0(t0)              # DONE[h]
    addi t0, s10, 1
    sw   t0, 0(s3)              # pass the token on
    li   a0, 0xCAFEBABE         # inline PASS (tb latches a0_1/2/3)
    slli t0, s10, 2
    add  t0, t0, s4
    add  t1, s6, s10
tile_verify:                    # forever: DONE must survive other traffic
    lw   t2, 0(t0)
    bne  t2, t1, shtimer_fail
    j    tile_verify

    # ---- hart 0 -------------------------------------------------------------
hart0:
    # The TIMER's glitch-free clock mux DEFAULTS to the smclk slice; switching
    # to mclk first needs 3 smclk edges to release that slice — and the ROM
    # bootrom parks SMCLK on LFXT (32.768 kHz => ~92us handoff). Route SMCLK
    # to HFXT first (M6 rule: never trust boot clock state).
    li   t0, 0x4900             # SYSTEM0: SYS_CLK_CR at +0
    sw   zero, 0(t0)

    # M11: these are the LIVE shared windows (peripherals back at their
    # original addresses) — reset-value proofs through the arbiter:
    li   t0, 0x4600             # TIMER0 CR resets 0
    lw   t1, 0(t0)
    bnez t1, shtimer_fail
    li   t0, 0x4700             # TIMER1 CMP0 resets 0
    lw   t1, 12(t0)
    bnez t1, shtimer_fail
    li   t0, 0x4800             # GPIO2 P3DIR resets 0
    lw   t1, 20(t0)
    bnez t1, shtimer_fail
    li   t0, 0x4D00             # GPIO3 P4OUT resets 0
    lw   t1, 4(t0)
    bnez t1, shtimer_fail

    li   t0, 0x4000             # GPIO0 (shared since M11; bootrom's port):
    lw   t1, 20(t0)             # P1DIR = 0x41 (bootrom writes it every boot)
    li   t2, 0x41
    bne  t1, t2, shtimer_fail

    li   t0, SH_GPIO1           # GPIO1 moved: reset config via NEW window
    lw   t1, 20(t0)             # P2DIR resets 0x10 (tx0 output)
    li   t2, 0x10
    bne  t1, t2, shtimer_fail
    lw   t1, 36(t0)             # P2SEL resets 0x30 (uart0 alt fn)
    li   t2, 0x30
    bne  t1, t2, shtimer_fail   # (read-only: writing SEL would unhook UART0)

    li   s2, SH_TIMER1
    jal  ra, timer_dance        # hart 0 owns TIMER1 through the arbiter

    li   t0, 1
    sw   t0, 0(s3)              # TOKEN = 1: release the ring

    li   t6, 100000             # bounded-wait for the ring to come home (M12:
                                # covers 3 serialized tile ROM-copies at launch)
ring_wait:
    lw   t0, 0(s3)
    li   t1, 4
    beq  t0, t1, ring_home
    addi t6, t6, -1
    bnez t6, ring_wait
    j    shtimer_fail
ring_home:
    li   t3, 1                  # verify DONE[1..3]
done_check:
    slli t0, t3, 2
    add  t0, t0, s4
    lw   t1, 0(t0)
    add  t2, s6, t3
    bne  t1, t2, shtimer_fail
    addi t3, t3, 1
    li   t0, 4
    bne  t3, t0, done_check

    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin

shtimer_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # ---- timer_dance: full register/count/flag exercise of the TIMER at s2.
    # ---- Clobbers t0-t6. CR+0 SR+4 VAL+8 CMP0+12. ---------------------------
timer_dance:
    lw   t0, 0(s2)              # CR resets 0
    bnez t0, shtimer_fail
    li   t0, TIM_CMP0_VAL
    sw   t0, 12(s2)             # CMP0 write...
    lw   t1, 12(s2)
    bne  t1, t0, shtimer_fail   # ...and readback
    li   t0, TIM_CR_EN_MCLK
    sw   t0, 0(s2)              # enable, source = mclk, div = 1
    lw   t2, 8(s2)              # VAL sample (may still be 0: the glitch-free
    li   t6, 20000              # mux takes cycles of BOTH clocks to hand off)
val_wait:
    lw   t3, 8(s2)
    bltu t2, t3, val_counting   # counting = strictly past the first sample
    addi t6, t6, -1
    bnez t6, val_wait
    j    shtimer_fail
val_counting:
    li   t6, 20000
cmp_wait:                       # CMP0 match (VAL reaches 0x300) sets SR bit0
    lw   t3, 4(s2)
    andi t3, t3, 1
    bnez t3, cmp_set
    addi t6, t6, -1
    bnez t6, cmp_wait
    j    shtimer_fail
cmp_set:
    li   t3, 1
    sw   t3, 4(s2)              # SR write bit0 -> clear pulse
    li   t6, 20000
cmp_clr_wait:
    lw   t3, 4(s2)
    andi t3, t3, 1
    beqz t3, cmp_clear
    addi t6, t6, -1
    bnez t6, cmp_clr_wait
    j    shtimer_fail
cmp_clear:
    sw   zero, 0(s2)            # disable...
    lw   t2, 8(s2)
    lw   t3, 8(s2)
    bne  t2, t3, shtimer_fail   # ...freezes VAL
    jalr zero, 0(ra)

    # ---- gpio_dance: OUT/OUTS/OUTC/OUTT/IES register semantics on the GPIO
    # ---- at s2 (8-bit port). PxDIR stays 0 = all inputs, pads never driven.
    # ---- IN+0 OUT+4 OUTS+8 OUTC+12 OUTT+16 DIR+20 IES+28. Clobbers t0-t1. --
gpio_dance:
    lw   t0, 4(s2)              # PxOUT resets 0
    bnez t0, shtimer_fail
    lw   t0, 20(s2)             # PxDIR resets 0 (inputs)
    bnez t0, shtimer_fail
    li   t0, 0x5A
    sw   t0, 4(s2)              # OUT = 0x5A
    lw   t1, 4(s2)
    bne  t1, t0, shtimer_fail
    li   t0, 0x21
    sw   t0, 8(s2)              # OUTS: set bits -> 0x7B
    lw   t1, 4(s2)
    li   t0, 0x7B
    bne  t1, t0, shtimer_fail
    li   t0, 0x0A
    sw   t0, 12(s2)             # OUTC: clear bits -> 0x71
    lw   t1, 4(s2)
    li   t0, 0x71
    bne  t1, t0, shtimer_fail
    li   t0, 0xFF
    sw   t0, 16(s2)             # OUTT: toggle all -> 0x8E
    lw   t1, 4(s2)
    li   t0, 0x8E
    bne  t1, t0, shtimer_fail
    sw   zero, 4(s2)            # restore OUT = 0
    li   t0, 0x33
    sw   t0, 28(s2)             # IES write/readback (edge select, no clocks)
    lw   t1, 28(s2)
    bne  t1, t0, shtimer_fail
    sw   zero, 28(s2)           # restore
    jalr zero, 0(ra)

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
