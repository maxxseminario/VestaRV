# See LICENSE for license details.

#*****************************************************************************
# shuart.S  (M6)
#-----------------------------------------------------------------------------
# HART-GENERIC shared-UART0 test — the M6 signature test.
#
# M6 moved UART0 (the console UART) off hart 0's private peripheral bus
# (0x4400, now reads zeros) and onto the mp_arbiter as the THIRD region-4
# slave: all 4 harts reach its registers at 0x12000 (CR/SR/BR/RX/TX at
# +0x0/4/8/C/10, same offsets as ever). The arbiter's whole-transaction grant
# serializes register accesses; MESSAGE-level ownership is software's job —
# here a token ring (deterministic order 0->1->2->3).
#
# Shared words (>= 0x10170, clear of all earlier tests' words):
#     TOKEN    = 0x10170          whose turn it is (shram zero-init => hart 0)
#     DONE[h]  = 0x10180 + 4*h    0xC0DE0000+h after hart h transmitted
#
# Hart 0 (SPI boot):  verify the OLD 0x4400 window reads 0, program BR=1 +
#   CR=EN through 0x12000, read both back, transmit 'A' + full UTCIF flag
#   dance, TOKEN=1. Then bounded-wait TOKEN==4 and verify DONE[1..3].
# Harts 1-3 (preloaded, parked on TOKEN reads): on TOKEN==h verify BR still
#   reads the hart-0 value (shared config really is shared), transmit 'A'+h,
#   UTCIF flag dance, DONE[h], TOKEN=h+1, inline PASS + forever-verify.
#
# Flag dance per byte (proves the smclk-domain UART core really ran, and the
# read/write/clear paths all work through the arbiter): write TX, poll SR
# bit0 (UTCIF) ==1, write SR=1 (clear pulse), poll UTCIF ==0. BR=1 => baud =
# 24MHz/32, one 10-bit frame = 320 mclk ~ 13.3us. All polls bounded at 20000
# (must trip inside the 100ms tb watchdog).
#
# No IRQs anywhere: CR interrupt enables stay 0, SYS_IRQ_EN resets masked,
# and nothing writes the CLINT. sp is set anyway (IRQ_SV contract).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

#define SH_UART   0x12000
#define TOKEN     0x10170
#define DONE_BASE 0x10180
#define BR_VAL    1
#define CR_EN     0x20

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..3
    .option pop

    li   sp, 0xFFF0             # private RAM1 top (IRQ_SV contract)

    li   s2, SH_UART            # shared UART0: +0 CR, +4 SR, +8 BR, +16 TX
    li   s3, TOKEN
    li   s4, DONE_BASE
    li   s6, 0xC0DE0000         # DONE magic base

    beqz s10, hart0

    # ---- harts 1-3: park on the token (reads only, unbounded — hart 0 is
    # ---- still SPI-booting), then one supervised transmission ------------
token_wait:
    lw   t0, 0(s3)
    bne  t0, s10, token_wait

    lw   t0, 8(s2)              # BR: hart 0's config must be visible here
    li   t1, BR_VAL
    bne  t0, t1, shuart_fail

    li   t2, 0x41               # 'A' + hartid
    add  t2, t2, s10
    jal  ra, send_byte

    slli t0, s10, 2
    add  t0, t0, s4
    add  t1, s6, s10
    sw   t1, 0(t0)              # DONE[h] = 0xC0DE0000+h
    addi t0, s10, 1
    sw   t0, 0(s3)              # pass the token on

    li   a0, 0xCAFEBABE         # inline PASS (tb latches a0_1/2/3)
    slli t0, s10, 2
    add  t0, t0, s4
    add  t1, s6, s10
tile_verify:                    # forever: DONE must survive other traffic
    lw   t2, 0(t0)
    bne  t2, t1, shuart_fail
    j    tile_verify

    # ---- hart 0 ----------------------------------------------------------
hart0:
    # SPI boot leaves SMCLK sourced from LFXT (32.768 kHz -> 9.8 ms/frame,
    # found the hard way: hart 1's UTCIF poll budget expired mid-frame).
    # Route SMCLK (the UART core clock) to HFXT explicitly, same as the
    # single-core periph UART.S does: SYS_CLK_CR = 0 (all clocks on, HFXT).
    li   t0, 0x4900             # SYSTEM0: SYS_CLK_CR at +0
    sw   zero, 0(t0)

    li   t0, 0x4400             # OLD private UART0 window: M6 tied it to 0
    lw   t1, 0(t0)              # (was CR)
    bnez t1, shuart_fail
    lw   t1, 16(t0)             # (was TX)
    bnez t1, shuart_fail

    li   t0, BR_VAL
    sw   t0, 8(s2)              # BR = 1 (baud = smclk/32)
    lw   t1, 8(s2)
    bne  t1, t0, shuart_fail    # shared-register write/readback path

    li   t0, CR_EN
    sw   t0, 0(s2)              # CR = enable, no IRQ enables
    lw   t1, 0(s2)
    bne  t1, t0, shuart_fail

    li   t2, 0x41               # 'A'
    jal  ra, send_byte

    li   t0, 1
    sw   t0, 0(s3)              # TOKEN = 1: release the ring

    li   t6, 20000              # bounded-wait for the ring to come home
ring_wait:
    lw   t0, 0(s3)
    li   t1, 4
    beq  t0, t1, ring_home
    addi t6, t6, -1
    bnez t6, ring_wait
    j    shuart_fail
ring_home:
    li   t3, 1                  # verify DONE[1..3]
done_check:
    slli t0, t3, 2
    add  t0, t0, s4
    lw   t1, 0(t0)
    add  t2, s6, t3
    bne  t1, t2, shuart_fail
    addi t3, t3, 1
    li   t0, 4
    bne  t3, t0, done_check

    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin

shuart_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # ---- send_byte: TX t2, then the full UTCIF flag dance (clobbers t3/t6).
    # ---- SR reads are per-access snapshots (falling-edge en_mem latch), so
    # ---- every poll sees fresh flags. --------------------------------------
send_byte:
    sw   t2, 16(s2)             # TX = byte (starts the smclk-domain core)
    li   t6, 20000
tc_wait:
    lw   t3, 4(s2)              # SR
    andi t3, t3, 1              # UTCIF = transmission complete
    bnez t3, tc_set
    addi t6, t6, -1
    bnez t6, tc_wait
    j    shuart_fail
tc_set:
    li   t3, 1
    sw   t3, 4(s2)              # SR write bit0 -> clr_UTCIF pulse
    li   t6, 20000
tc_clr_wait:
    lw   t3, 4(s2)
    andi t3, t3, 1
    beqz t3, tc_clear
    addi t6, t6, -1
    bnez t6, tc_clr_wait
    j    shuart_fail
tc_clear:
    jalr zero, 0(ra)

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
