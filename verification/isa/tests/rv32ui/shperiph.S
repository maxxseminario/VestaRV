# See LICENSE for license details.

#*****************************************************************************
# shperiph.S  (M7c; M12 single-ROM boot rework)
#-----------------------------------------------------------------------------
# HART-GENERIC shared SPI1 + UART1 test — the M7c signature test.
#
# M12: tiles are NO LONGER preloaded. Hart 0 stages this TCM image once and
# launches harts 1-3 into tile_entry through the bootrom loader (mp_boot.h);
# each tile then parks on the token. The token ring (0x101E0) is unchanged.
#
# M7c moved the two remaining session peripherals with clean buses onto the
# mp_arbiter, at their mirror slots in the 0x6000 page:
#     SPI1 = 0x4300 (slot 3)      UART1 = 0x4500 (slot 5)   (M11: the
#     shared window slots ARE the legacy addresses again)
# Register offsets unchanged; old windows read zeros. SPI1's flash FSM is
# compiled out (ENABLE_EXTENDED_MEM=false). SPI0 stays private FOREVER (the
# ROM bootrom's boot path), as do SYSTEM0 and GPIO0.
#
# Token ring (shtimer pattern): hart 0 checks the old 0x4300/0x4500 windows
# are dead, then runs a full UART1 byte transmit (BR=1 + CR=EN with
# readbacks + the UTCIF flag dance — same contract as shared UART0/M6) and a
# full SPI1 master transmit (CR = EN|BR=1 8-bit master with readback, TX
# write auto-starts the transfer, poll SR.TCIF, clear via SR write-1-to-
# -clear, poll clear). Hart 1: SPI1 again — CR must still read hart 0's
# config (cross-hart config visibility), transmit a different byte, TCIF
# dance, TX readback. Hart 2: UART1 again — BR readback + transmit. Hart 3:
# both, back to back (one hart driving TWO shared session periphs).
#
# Both cores are SMCLK-domain (UART baud gen, SPI baud gen) => hart 0 writes
# SYS_CLK_CR=0 FIRST (M6 rule; bootrom parks SMCLK on LFXT). BR=1: UART
# frame ~13.3us, SPI 8-bit transfer = 8 bits * 2*(1+1) smclk = ~1.3us. All
# polls bounded 20000 (inside the 100ms tb watchdog).
#
# MISO1 is an undriven pad in the tb, so RX contents are undefined — the
# test never reads SPIxRX (an RX access also auto-clears TCIF; we clear via
# the SR write path instead, which this test exercises deliberately).
# Interrupt enables stay 0 everywhere (routed-IRQ wake is shirq's job; note
# UART1's IVT slots 52-54 DO have linker sections if ever needed).
#
# Shared words (>= 0x101E0, clear of all earlier tests' words):
#     TOKEN    = 0x101E0          whose turn (shram zero-init => hart 0)
#     DONE[h]  = 0x101F0 + 4*h    0x5E550000+h after hart h's dance
# (next free shared word: 0x10200)
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_SPI1    0x4300
#define SH_UART1   0x4500
#define TOKEN      0x101E0
#define DONE_BASE  0x101F0
#define UART_BR    1
#define UART_CR_EN 0x20
#define SPI_CR_CFG 0x180        /* en(7) | br=1(15:8); master, 8-bit, LSB */

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

    li   s2, SH_UART1           # +0 CR, +4 SR, +8 BR, +16 TX
    li   s3, TOKEN
    li   s4, DONE_BASE
    li   s5, SH_SPI1            # +0 CR, +4 SR, +8 TX, +12 RX
    li   s6, 0x5E550000         # DONE magic base

    beqz s10, hart0

    # ---- harts 1-3: park on the token (reads only), then one dance --------
token_wait:
    lw   t0, 0(s3)
    bne  t0, s10, token_wait

    li   t0, 2
    beq  s10, t0, hart2
    li   t0, 3
    beq  s10, t0, hart3

    # ---- hart 1: SPI1 (a TILE hart owns a shared SPI master) ---------------
    lw   t0, 0(s5)              # CR: hart 0's config must be visible
    li   t1, SPI_CR_CFG
    bne  t0, t1, shperiph_fail
    li   t2, 0x3C
    jal  ra, spi_send
    j    report

    # ---- hart 2: UART1 ------------------------------------------------------
hart2:
    lw   t0, 8(s2)              # BR: hart 0's config must be visible
    li   t1, UART_BR
    bne  t0, t1, shperiph_fail
    li   t2, 0x55               # 'U'
    jal  ra, uart_send
    j    report

    # ---- hart 3: BOTH session periphs back to back --------------------------
hart3:
    li   t2, 0xC3
    jal  ra, spi_send
    li   t2, 0x33               # '3'
    jal  ra, uart_send

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
    bne  t2, t1, shperiph_fail
    j    tile_verify

    # ---- hart 0 -------------------------------------------------------------
hart0:
    li   t0, 0x4900             # SYSTEM0: SYS_CLK_CR at +0
    sw   zero, 0(t0)            # SMCLK -> HFXT (both cores are smclk-domain)

    # M11: live shared windows — reset-value proofs through the arbiter:
    li   t0, 0x4300             # SPI1 CR resets 0
    lw   t1, 0(t0)
    bnez t1, shperiph_fail
    li   t0, 0x4500             # UART1 CR resets 0
    lw   t1, 8(t0)
    bnez t1, shperiph_fail

    li   t0, UART_BR            # UART1 config with readback via 0x4500
    sw   t0, 8(s2)
    lw   t1, 8(s2)
    bne  t1, t0, shperiph_fail
    li   t0, UART_CR_EN
    sw   t0, 0(s2)
    lw   t1, 0(s2)
    bne  t1, t0, shperiph_fail
    li   t2, 0x42               # 'B'
    jal  ra, uart_send

    li   t0, SPI_CR_CFG         # SPI1 config with readback via 0x4300
    sw   t0, 0(s5)
    lw   t1, 0(s5)
    bne  t1, t0, shperiph_fail
    li   t2, 0xA5
    jal  ra, spi_send

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
    j    shperiph_fail
ring_home:
    li   t3, 1                  # verify DONE[1..3]
done_check:
    slli t0, t3, 2
    add  t0, t0, s4
    lw   t1, 0(t0)
    add  t2, s6, t3
    bne  t1, t2, shperiph_fail
    addi t3, t3, 1
    li   t0, 4
    bne  t3, t0, done_check

    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin

shperiph_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # ---- uart_send: TX t2 on UART1 + full UTCIF flag dance (shuart pattern;
    # ---- clobbers t3/t6). SR reads are per-access snapshots. ---------------
uart_send:
    sw   t2, 16(s2)             # TX = byte (starts the smclk-domain core)
    li   t6, 20000
utc_wait:
    lw   t3, 4(s2)              # SR
    andi t3, t3, 1              # UTCIF
    bnez t3, utc_set
    addi t6, t6, -1
    bnez t6, utc_wait
    j    shperiph_fail
utc_set:
    li   t3, 1
    sw   t3, 4(s2)              # SR write bit0 -> clr_UTCIF pulse
    li   t6, 20000
utc_clr_wait:
    lw   t3, 4(s2)
    andi t3, t3, 1
    beqz t3, utc_clear
    addi t6, t6, -1
    bnez t6, utc_clr_wait
    j    shperiph_fail
utc_clear:
    jalr zero, 0(ra)

    # ---- spi_send: TX t2 on SPI1 (write auto-starts the master transfer) +
    # ---- TCIF dance via SR (never touches RX — MISO floats in the tb and an
    # ---- RX access would also auto-clear TCIF). TX readback == written.
    # ---- Clobbers t3/t6. SPI SR: bit2 busy, bit1 TCIF, bit0 TEIF. ----------
spi_send:
    sw   t2, 8(s5)              # TX = byte -> start_tx
    lw   t3, 8(s5)              # TX register reads back the written byte
    bne  t3, t2, shperiph_fail
    li   t6, 20000
stc_wait:
    lw   t3, 4(s5)              # SR
    andi t3, t3, 2              # TCIF
    bnez t3, stc_set
    addi t6, t6, -1
    bnez t6, stc_wait
    j    shperiph_fail
stc_set:
    li   t3, 2
    sw   t3, 4(s5)              # SR write bit1 -> clr_spi_tcif pulse
    li   t6, 20000
stc_clr_wait:
    lw   t3, 4(s5)
    andi t3, t3, 2
    beqz t3, stc_clear
    addi t6, t6, -1
    bnez t6, stc_clr_wait
    j    shperiph_fail
stc_clear:
    jalr zero, 0(ra)

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
