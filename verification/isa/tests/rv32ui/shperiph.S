# See LICENSE for license details.

# VestaRV: shared SPI1 and UART1 test
# SPI1 is at 0x4300 and UART1 at 0x4500, both on the mp_arbiter; the old private windows read zeros, and SPI1's flash FSM is compiled out.
# CLAIM-BASED OWNERSHIP: the two peripherals are a POOL of claimable roles rather than a fixed hartid-to-role map, which strands harts at large N. Any hart atomically claims a free one through the HW mutex bank at 0x6000 with a one-instruction acquire; the winner owns it exclusively, never releases the mutex, runs the full exercise once (reset proof, config with readback, transmit, flag dance) and records ROLEDONE[i]. Harts that find both taken park. With NHARTS >= NROLES claimers the bank guarantees both peripherals run exactly once whichever hart wins which. Role 0 is SPI1 and role 1 is UART1, with mutex i guarding role i.
# BOTH CORES ARE SMCLK-DOMAIN baud generators, so hart 0 writes SYS_CLK_CR = 0 FIRST, because the boot ROM parks SMCLK on LFXT, and proves the reset CRs before opening GO. At BR = 1 a UART frame is about 13.3 us and an 8-bit SPI transfer about 1.3 us; every poll is bounded at 20000.
# MISO1 FLOATS IN THE TB, so the test never reads SPIxRX: an RX access would auto-clear TCIF, and the flag is cleared through the SR write path deliberately.
# Shared words, all below 0x10500: GO = 0x101E0, DONE[h] = 0x101E4 + 4*h, ROLEDONE[i] = 0x101E4 + 4*NHARTS + 4*i. ROLEDONE follows the NHARTS-sized DONE array so it cannot be overrun; at N=18 DONE runs 0x101E4..0x10228 and ROLEDONE 0x1022C..0x10230.

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_SPI1    0x4300
#define SH_UART1   0x4500
#define MUTEX_BASE 0x6000              /* HW mutex bank: mutex i guards role i */
#define NROLES     2
#define GO            0x101E0
#define DONE_BASE     0x101E4
#define ROLEDONE_BASE (DONE_BASE + 4*NHARTS)
#define GO_MAGIC      0x5E560000
#define DONE_MAGIC    0x5E550000
#define ROLE_MAGIC    0x5E500000
#define UART_BR    1
#define UART_CR_EN 0x20
#define SPI_CR_CFG 0x180        /* en(7) | br=1(15:8); master, 8-bit, LSB */

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

    li   s2, SH_UART1          # +0 CR, +4 SR, +8 BR, +16 TX
    li   s3, GO
    li   s4, DONE_BASE
    li   s5, SH_SPI1           # +0 CR, +4 SR, +8 TX, +12 RX

    beqz s10, hart0

    # ---- tiles: wait for GO, then claim-and-run one role -------------------
tile_go_wait:
    lw   t0, 0(s3)
    li   t1, GO_MAGIC
    bne  t0, t1, tile_go_wait
    jal  ra, claim_and_run
    j    report

    # ---- hart 0: SMCLK + reset proofs, open GO, then claim + judge ---------
hart0:
    li   t0, 0x4900            # SYSTEM0: SYS_CLK_CR at +0
    sw   zero, 0(t0)           # SMCLK -> HFXT (both cores are smclk-domain)

    li   t0, 0x4300            # SPI1 CR resets 0 (reset proof before any dance)
    lw   t1, 0(t0)
    bnez t1, shperiph_fail
    li   t0, 0x4500            # UART1 CR resets 0
    lw   t1, 8(t0)
    bnez t1, shperiph_fail

    li   t0, GO_MAGIC
    sw   t0, 0(s3)             # open GO: every hart may claim from here
    jal  ra, claim_and_run    # hart 0 also competes for a peripheral

    # adjudicate: wait every tile's DONE, then verify both ROLEDONE ----------
    li   s6, 1
done_gather:
    li   t6, 100000
1:  slli t0, s6, 2
    add  t0, t0, s4
    lw   t1, 0(t0)            # DONE[s6]
    li   t2, DONE_MAGIC
    add  t2, t2, s6
    beq  t1, t2, 2f
    addi t6, t6, -1
    bnez t6, 1b
    j    shperiph_fail
2:  addi s6, s6, 1
    li   t0, NHARTS
    bltu s6, t0, done_gather

    li   s6, 0                # verify each peripheral was exercised EXACTLY once
role_check:
    li   t0, ROLEDONE_BASE
    slli t1, s6, 2
    add  t0, t0, t1
    lw   t1, 0(t0)
    li   t2, ROLE_MAGIC
    add  t2, t2, s6
    bne  t1, t2, shperiph_fail
    addi s6, s6, 1
    li   t0, NROLES
    bltu s6, t0, role_check

    RVTEST_PASS               # a0 = 0xCAFEBABE, spin

    # ---- every hart ends here: record DONE, PASS, verify DONE forever ------
report:
    slli t0, s10, 2
    add  t0, t0, s4
    li   t1, DONE_MAGIC
    add  t1, t1, s10
    sw   t1, 0(t0)            # DONE[h]
    li   a0, 0xCAFEBABE       # inline PASS (tb latches a0_1..a0_(N-1))
tile_verify:                  # forever: DONE must survive other traffic
    lw   t2, 0(t0)
    bne  t2, t1, shperiph_fail
    j    tile_verify

shperiph_fail:
    RVTEST_FAIL               # a0 = 0xDEADBEEF, spin

    # ---- claim_and_run: atomically claim the first FREE peripheral via the
    # ---- mutex bank, run its full exercise once, mark ROLEDONE[i]. Returns
    # ---- without claiming if both are taken. Saves ra in s0, role in s1.
    # ---- (send routines use s2/s5 + t2/t3/t6; preserve s0/s1/s3/s4/s10.) ----
claim_and_run:
    mv   s0, ra               # save return (sends clobber ra)
    li   s1, 0                # role index
cr_try:
    li   t0, MUTEX_BASE
    slli t1, s1, 2
    add  t0, t0, t1
    lw   t2, 0(t0)           # 1-insn atomic claim: 0 = I now own role s1
    beqz t2, cr_won
    addi s1, s1, 1
    li   t3, NROLES
    bltu s1, t3, cr_try
    mv   ra, s0              # both taken — no role for me
    jalr zero, 0(ra)
cr_won:
    bnez s1, cr_uart         # role 0 = SPI1; role 1 = UART1
    li   t0, SPI_CR_CFG      # SPI1 config with readback via s5
    sw   t0, 0(s5)
    lw   t1, 0(s5)
    bne  t1, t0, shperiph_fail
    li   t2, 0xA5
    jal  ra, spi_send
    j    cr_mark
cr_uart:
    li   t0, UART_BR         # UART1 config with readback via s2
    sw   t0, 8(s2)
    lw   t1, 8(s2)
    bne  t1, t0, shperiph_fail
    li   t0, UART_CR_EN
    sw   t0, 0(s2)
    lw   t1, 0(s2)
    bne  t1, t0, shperiph_fail
    li   t2, 0x42            # 'B'
    jal  ra, uart_send
cr_mark:
    li   t0, ROLEDONE_BASE
    slli t1, s1, 2
    add  t0, t0, t1
    li   t2, ROLE_MAGIC
    add  t2, t2, s1
    sw   t2, 0(t0)           # ROLEDONE[i] = magic+i (exactly one writer)
    mv   ra, s0
    jalr zero, 0(ra)

    # ---- uart_send: TX t2 on UART1 + full UTCIF flag dance (shuart pattern;
    # ---- clobbers t3/t6). SR reads are per-access snapshots. ---------------
uart_send:
    sw   t2, 16(s2)          # TX = byte (starts the smclk-domain core)
    li   t6, 20000
utc_wait:
    lw   t3, 4(s2)           # SR
    andi t3, t3, 1           # UTCIF
    bnez t3, utc_set
    addi t6, t6, -1
    bnez t6, utc_wait
    j    shperiph_fail
utc_set:
    li   t3, 1
    sw   t3, 4(s2)           # SR write bit0 -> clr_UTCIF pulse
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
    sw   t2, 8(s5)           # TX = byte -> start_tx
    lw   t3, 8(s5)           # TX register reads back the written byte
    bne  t3, t2, shperiph_fail
    li   t6, 20000
stc_wait:
    lw   t3, 4(s5)           # SR
    andi t3, t3, 2           # TCIF
    bnez t3, stc_set
    addi t6, t6, -1
    bnez t6, stc_wait
    j    shperiph_fail
stc_set:
    li   t3, 2
    sw   t3, 4(s5)           # SR write bit1 -> clr_spi_tcif pulse
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
