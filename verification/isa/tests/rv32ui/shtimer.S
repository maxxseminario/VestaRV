# See LICENSE for license details.

#*****************************************************************************
# shtimer.S  (M7b; M12 single-ROM boot rework; Argus A3 claim-based rework)
#-----------------------------------------------------------------------------
# HART-GENERIC shared TIMER0/1 + GPIO2/3 test — the M7b signature test.
#
# M12: tiles are NO LONGER preloaded. Hart 0 stages this TCM image once and
# launches all tiles 1..NHARTS-1 into tile_entry through the bootrom loader
# (mp_boot.h); each tile then parks on the GO gate.
#
# M7b moved TIMER0/TIMER1/GPIO2/GPIO3 off hart 0's private peripheral bus and
# onto the mp_arbiter in the 0x4x00 page (M11 map: peripherals at their legacy
# addresses — GPIO1 0x4100, TIMER0 0x4600, TIMER1 0x4700, GPIO2 0x4800,
# GPIO3 0x4D00). The old private windows read zeros.
#
# ARGUS A3 CLAIM-BASED OWNERSHIP (user decision 2026-07-10): instead of a fixed
# hartid->role dispatch (which stranded harts >= 4 at N=18), the four peripheral
# "dances" are a POOL of claimable roles. Any hart may atomically CLAIM a free
# role through the HW mutex bank (0x6000, 1-insn acquire); the winner owns that
# peripheral EXCLUSIVELY for the whole test (the mutex is never released), runs
# its dance once, and records ROLEDONE[i]. Harts that find every role taken just
# park. With NHARTS >= NROLES claimers the mutex bank guarantees all four roles
# run EXACTLY once regardless of which hart wins what — a deterministic,
# N-agnostic pass condition. (Teaches: 1-insn mutex claim = exclusive
# peripheral ownership.) Verified passing at N=4 AND N=18.
#
#   Role 0 = TIMER0 dance   Role 1 = TIMER1 dance
#   Role 2 = GPIO2  dance   Role 3 = GPIO3  dance   (mutex i guards role i)
#
# Hart 0 (always-on supervisor) first does the reset-value proofs + SMCLK/GPIO
# config that MUST precede any dance, opens GO, then JOINS the claiming (it may
# or may not win a role — at N=4 it wins the one the 3 tiles leave; at N=18 the
# fast tiles usually take all four and hart 0 just adjudicates). Finally it
# waits every tile's DONE and verifies all four ROLEDONE words.
#
# Timer dance (clock source = MCLK, no divider): CR reads 0 at reset; CMP0
# write/readback; enable; bounded-poll VAL until it counts past the first
# sample (glitch-free mux needs a few edges — hence SYS_CLK_CR=0 first); CMP0
# match sets SR bit0; SR write-1 clears it; disable freezes VAL. Polls bounded
# 20000 (inside the 100ms watchdog). GPIO dance: OUT/OUTS/OUTC/OUTT/IES
# semantics with PxDIR left 0 (inputs; pads never driven).
#
# Shared words (>= 0x101C0, clear of earlier tests' words, all < 0x10500):
#     GO            = 0x101C0            0x71600000 after hart 0 opens the gate
#     DONE[h]       = 0x101C4 + 4*h      0x71E40000+h after hart h finishes
#                                        (h = 0..NHARTS-1; hart 0 writes DONE[0])
#     ROLEDONE[i]   = 0x101C4 + 4*NHARTS + 4*i   0x71D00000+i after role i runs
#   (mutex bank 0x6000+4*i provides the atomic claim; nothing in shared RAM)
# The ROLEDONE array sits at DONE_BASE + 4*NHARTS so the NHARTS-sized DONE array
# can't overrun it (N=18: DONE 0x101C4..0x10208, ROLEDONE 0x1020C..0x10218).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_TIMER0  0x4600
#define SH_TIMER1  0x4700
#define SH_GPIO1   0x4100
#define SH_GPIO2   0x4800
#define SH_GPIO3   0x4D00
#define MUTEX_BASE 0x6000              /* HW mutex bank: mutex i guards role i */
#define NROLES     4
#define GO            0x101C0
#define DONE_BASE     0x101C4
#define ROLEDONE_BASE (DONE_BASE + 4*NHARTS)
#define GO_MAGIC      0x71600000
#define DONE_MAGIC    0x71E40000
#define ROLE_MAGIC    0x71D00000
#define TIM_CR_EN_MCLK 0x140     /* clock source 01 = mclk, timer enable */
#define TIM_CMP0_VAL   0x300

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry        # M12: only hart 0 runs the launcher

    # M12 single-ROM boot: stage this TCM image once, launch all tiles into
    # tile_entry through the bootrom loader (mp_boot.h). They park on GO.
    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_ALL(tile_entry, 4096)

tile_entry:                     # tiles enter here (loader ABI: only sp defined)
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # re-derive (undefined for tiles until now)
    .option pop

    li   sp, 0xBFF0             # private TCM top (IRQ_SV contract)

    li   s3, GO
    li   s4, DONE_BASE

    beqz s10, hart0

    # ---- tiles: wait for GO, then claim-and-run one role -------------------
tile_go_wait:
    lw   t0, 0(s3)
    li   t1, GO_MAGIC
    bne  t0, t1, tile_go_wait
    jal  ra, claim_and_run
    j    report

    # ---- hart 0: reset-value proofs + config, open GO, then claim + judge --
hart0:
    # The TIMER glitch-free clock mux DEFAULTS to the smclk slice; the ROM
    # bootrom parks SMCLK on LFXT (~92us handoff). Route SMCLK to HFXT first
    # (M6 rule: never trust boot clock state).
    li   t0, 0x4900             # SYSTEM0: SYS_CLK_CR at +0
    sw   zero, 0(t0)

    # reset-value proofs (must precede any dance — GO gates all claiming):
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

    li   t0, GO_MAGIC
    sw   t0, 0(s3)              # open GO: every hart may claim from here
    jal  ra, claim_and_run     # hart 0 also competes for a role

    # adjudicate: wait every tile's DONE, then verify all four ROLEDONE ------
    li   s6, 1
done_gather:
    li   t6, 100000            # bounded per-hart (M12: covers serialized launch)
1:  slli t0, s6, 2
    add  t0, t0, s4
    lw   t1, 0(t0)             # DONE[s6]
    li   t2, DONE_MAGIC
    add  t2, t2, s6
    beq  t1, t2, 2f
    addi t6, t6, -1
    bnez t6, 1b
    j    shtimer_fail
2:  addi s6, s6, 1
    li   t0, NHARTS
    bltu s6, t0, done_gather

    li   s6, 0                 # verify each role ran EXACTLY once
role_check:
    li   t0, ROLEDONE_BASE
    slli t1, s6, 2
    add  t0, t0, t1
    lw   t1, 0(t0)
    li   t2, ROLE_MAGIC
    add  t2, t2, s6
    bne  t1, t2, shtimer_fail
    addi s6, s6, 1
    li   t0, NROLES
    bltu s6, t0, role_check

    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin

    # ---- every hart ends here: record DONE, PASS, verify DONE forever ------
report:
    slli t0, s10, 2
    add  t0, t0, s4
    li   t1, DONE_MAGIC
    add  t1, t1, s10
    sw   t1, 0(t0)             # DONE[h]
    li   a0, 0xCAFEBABE        # inline PASS (tb latches a0_1..a0_(N-1))
tile_verify:                   # forever: DONE must survive other traffic
    lw   t2, 0(t0)
    bne  t2, t1, shtimer_fail
    j    tile_verify

shtimer_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # ---- claim_and_run: atomically claim the first FREE role via the mutex
    # ---- bank, run its dance once, mark ROLEDONE[i]. Returns without claiming
    # ---- if every role is taken. Saves ra in s0, role index in s1, periph
    # ---- addr in s2 (dances use s2 + t0-t6; they preserve s0/s1/s3/s4/s10). --
claim_and_run:
    mv   s0, ra                # save return (dances clobber ra)
    li   s1, 0                 # role index
cr_try:
    li   t0, MUTEX_BASE
    slli t1, s1, 2
    add  t0, t0, t1
    lw   t2, 0(t0)             # 1-insn atomic claim: 0 = I now own role s1
    beqz t2, cr_won
    addi s1, s1, 1
    li   t3, NROLES
    bltu s1, t3, cr_try
    mv   ra, s0                # every role taken — no role for me
    jalr zero, 0(ra)
cr_won:
    li   t3, 2
    bltu s1, t3, cr_timer      # roles 0,1 = timers; 2,3 = gpios
    li   t3, 3
    beq  s1, t3, cr_gpio3
    li   s2, SH_GPIO2          # role 2
    j    cr_run_gpio
cr_gpio3:
    li   s2, SH_GPIO3          # role 3
cr_run_gpio:
    jal  ra, gpio_dance
    j    cr_mark
cr_timer:
    li   t3, 1
    beq  s1, t3, cr_timer1
    li   s2, SH_TIMER0         # role 0
    j    cr_run_timer
cr_timer1:
    li   s2, SH_TIMER1         # role 1
cr_run_timer:
    jal  ra, timer_dance
cr_mark:
    li   t0, ROLEDONE_BASE
    slli t1, s1, 2
    add  t0, t0, t1
    li   t2, ROLE_MAGIC
    add  t2, t2, s1
    sw   t2, 0(t0)             # ROLEDONE[i] = magic+i (exactly one writer)
    mv   ra, s0
    jalr zero, 0(ra)

    # ---- timer_dance: full register/count/flag exercise of the TIMER at s2.
    # ---- Clobbers t0-t6. CR+0 SR+4 VAL+8 CMP0+12. ---------------------------
timer_dance:
    lw   t0, 0(s2)             # CR resets 0
    bnez t0, shtimer_fail
    li   t0, TIM_CMP0_VAL
    sw   t0, 12(s2)            # CMP0 write...
    lw   t1, 12(s2)
    bne  t1, t0, shtimer_fail  # ...and readback
    li   t0, TIM_CR_EN_MCLK
    sw   t0, 0(s2)             # enable, source = mclk, div = 1
    lw   t2, 8(s2)             # VAL sample (may still be 0: glitch-free mux
    li   t6, 20000             # takes cycles of BOTH clocks to hand off)
val_wait:
    lw   t3, 8(s2)
    bltu t2, t3, val_counting  # counting = strictly past the first sample
    addi t6, t6, -1
    bnez t6, val_wait
    j    shtimer_fail
val_counting:
    li   t6, 20000
cmp_wait:                      # CMP0 match (VAL reaches 0x300) sets SR bit0
    lw   t3, 4(s2)
    andi t3, t3, 1
    bnez t3, cmp_set
    addi t6, t6, -1
    bnez t6, cmp_wait
    j    shtimer_fail
cmp_set:
    li   t3, 1
    sw   t3, 4(s2)             # SR write bit0 -> clear pulse
    li   t6, 20000
cmp_clr_wait:
    lw   t3, 4(s2)
    andi t3, t3, 1
    beqz t3, cmp_clear
    addi t6, t6, -1
    bnez t6, cmp_clr_wait
    j    shtimer_fail
cmp_clear:
    sw   zero, 0(s2)           # disable...
    lw   t2, 8(s2)
    lw   t3, 8(s2)
    bne  t2, t3, shtimer_fail  # ...freezes VAL
    jalr zero, 0(ra)

    # ---- gpio_dance: OUT/OUTS/OUTC/OUTT/IES register semantics on the GPIO
    # ---- at s2 (8-bit port). PxDIR stays 0 = all inputs, pads never driven.
    # ---- IN+0 OUT+4 OUTS+8 OUTC+12 OUTT+16 DIR+20 IES+28. Clobbers t0-t1. --
gpio_dance:
    lw   t0, 4(s2)             # PxOUT resets 0
    bnez t0, shtimer_fail
    lw   t0, 20(s2)            # PxDIR resets 0 (inputs)
    bnez t0, shtimer_fail
    li   t0, 0x5A
    sw   t0, 4(s2)             # OUT = 0x5A
    lw   t1, 4(s2)
    bne  t1, t0, shtimer_fail
    li   t0, 0x21
    sw   t0, 8(s2)             # OUTS: set bits -> 0x7B
    lw   t1, 4(s2)
    li   t0, 0x7B
    bne  t1, t0, shtimer_fail
    li   t0, 0x0A
    sw   t0, 12(s2)            # OUTC: clear bits -> 0x71
    lw   t1, 4(s2)
    li   t0, 0x71
    bne  t1, t0, shtimer_fail
    li   t0, 0xFF
    sw   t0, 16(s2)            # OUTT: toggle all -> 0x8E
    lw   t1, 4(s2)
    li   t0, 0x8E
    bne  t1, t0, shtimer_fail
    sw   zero, 4(s2)           # restore OUT = 0
    li   t0, 0x33
    sw   t0, 28(s2)            # IES write/readback (edge select, no clocks)
    lw   t1, 28(s2)
    bne  t1, t0, shtimer_fail
    sw   zero, 28(s2)          # restore
    jalr zero, 0(ra)

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
