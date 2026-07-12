# See LICENSE for license details.

#*****************************************************************************
# afselv2.S  (GPIO multi-AF v2: relocatable peripheral INPUTS)
#-----------------------------------------------------------------------------
# System-level proof of the pin-mux v2 input relocations (afsel.S proved the
# v1 machinery: PxAFS semantics, output planes, the 2-way T0CAP0 input mux).
# v2 adds io slots to the spread planes and extends the input muxes to fixed
# priority chains (v2 pad > AF1 pad > home). This test drives the two NEW mux
# shapes end-to-end with the software-loopback pattern (input routing keys on
# PxAFS alone, so the candidate pad can stay in GPIO output mode):
#
#   gp=2      SPI1 master setup (8-bit, SCK=SMCLK/8)
#   gp=3      NEGATIVE CONTROL: P4AFS field6=0 -> MISO1 still observes its
#             driven-low home pad P2.1: transfer receives 0x00
#   gp=4      P4AFS field6=7 -> MISO1 observes P4.6 (v2 spread io slot,
#             AF7): with the pad GPIO-driven high, transfer receives 0xFF
#   gp=5      ...and with P4.6 driven low, 0x00 (really tracking the pad)
#   gp=6      UART0 setup (57.6k @ 24 MHz: BR=25) + TIMER0 free-run on MCLK
#             as the bit-clock (poll-until-counting, clock-mux handoff)
#   gp=7      NEGATIVE CONTROL: a full bit-banged frame on P4.5 with
#             P4AFS=0 must NOT be received (RX0 watches home P2.5, held 1)
#   gp=8      P4AFS field5=2 -> RX0 observes P4.5 (v2 spread io slot, AF2):
#             a timer-paced 0xA5 frame is received clean (RCIF, no FEF/OVF)
#   gp=9      second frame 0x3C received (not a one-shot fluke)
#
# Port bases are RTL numbering: GPIO1=P2 @0x4100, GPIO3=P4 @0x4D00.
# Hart 0 only (tiles stay parked). Bounded polls only (inside the 100ms
# tb watchdog). Requires SPI1 (verify_stage tags this test 'spi1').
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

#define GPIO1_BASE   0x4100
#define GPIO3_BASE   0x4D00
#define SPI1_BASE    0x4300
#define UART0_BASE   0x4400
#define TIMER0_BASE  0x4600
#define SYSTEM0_BASE 0x4900

#define GPIO_IN   0
#define GPIO_OUT  4
#define GPIO_DIR  20
#define GPIO_SEL  36
#define GPIO_AFS  44

#undef SPI_CR
#undef SPI_SR
#undef SPI_TX
#undef SPI_RX
#define SPI_CR    0
#define SPI_SR    4
#define SPI_TX    8
#define SPI_RX    12

#undef UART_CR
#undef UART_SR
#undef UART_BR
#undef UART_RX
#define UART_CR   0
#define UART_SR   4
#define UART_BR   8
#define UART_RX   12

#define TIM_CR    0
#define TIM_VAL   8

#define BIT_TICKS 416               /* 16 * (BR=25 + 1) mclk ticks per UART bit */

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, park              # single-hart test: tiles must never get here

    li   sp, 0xBFF0             # private TCM top; IRQ_SV pushes PC at sp-4

    # SMCLK -> HFXT right away (bootrom parks it on LFXT; both the SPI core
    # and the UART are smclk-domain)
    li   s0, SYSTEM0_BASE
    sw   zero, 0(s0)            # SYS_CLK_CR = 0

    li   s1, GPIO1_BASE         # RTL P2
    li   s3, GPIO3_BASE         # RTL P4
    li   s4, TIMER0_BASE
    li   s5, SPI1_BASE
    li   s6, UART0_BASE

    #------------------------------------------------------------------
    # MISO1 relocated to P4.6 (v2 spread io slot, AF7)
    #------------------------------------------------------------------
    li   gp, 2                  # SPI1 master, 8-bit, SCK = SMCLK/8
    li   t0, 0x380              # SPIEN | SPIBR=3, SPISM=0, SPIDL=8-bit
    sw   t0, SPI_CR(s5)
    li   t0, 3
    sw   t0, SPI_SR(s5)         # W1C any stale TCIF/TEIF

    li   t0, 2                  # home pad P2.1: GPIO output-low so the
    sw   t0, GPIO_DIR(s1)       # un-relocated MISO1 is a driven 0
    sw   zero, GPIO_OUT(s1)     # (never a floating X)
    sw   zero, GPIO_SEL(s1)

    li   t0, 0x60               # alt pad P4.6 output-HIGH; P4.5 output-HIGH
    sw   t0, GPIO_DIR(s3)       # already now (UART idle for the phases below)
    sw   t0, GPIO_OUT(s3)
    sw   zero, GPIO_SEL(s3)

    li   gp, 3                  # NEGATIVE CONTROL: P4AFS=0 -> home pad (0x00)
    li   a0, 0xFF
    jal  ra, spi1_xfer
    bnez a0, fail               # anything nonzero leaked from the alt pad

    li   gp, 4                  # engage AF7 on P4.6 -> pad is high -> 0xFF
    li   t0, 0x07000000         # P4AFS field6 = 7
    sw   t0, GPIO_AFS(s3)
    li   a0, 0xFF
    jal  ra, spi1_xfer
    addi a0, a0, -0xFF
    bnez a0, fail

    li   gp, 5                  # drive P4.6 low -> 0x00 (tracks the pad)
    li   t0, 0x20
    sw   t0, GPIO_OUT(s3)       # P4.6=0, P4.5 stays 1
    li   a0, 0xFF
    jal  ra, spi1_xfer
    bnez a0, fail

    sw   zero, GPIO_AFS(s3)     # restore: AFS=0, P4.6 back high
    li   t0, 0x60
    sw   t0, GPIO_OUT(s3)
    sw   zero, SPI_CR(s5)

    #------------------------------------------------------------------
    # RX0 relocated to P4.5 (v2 spread io slot, AF2)
    #------------------------------------------------------------------
    li   gp, 6                  # UART0 57.6k (BR=25); home pad P2.5 idle-high
    li   t0, 0x22               # P2.1 stays output-low, P2.5 output...
    sw   t0, GPIO_DIR(s1)
    li   t0, 0x20
    sw   t0, GPIO_OUT(s1)       # ...high (UART idle level)
    lw   t5, GPIO_SEL(s1)       # take P2.5 from the UART plane to GPIO
    andi t5, t5, ~0x20
    sw   t5, GPIO_SEL(s1)

    li   t0, 25
    sw   t0, UART_BR(s6)
    li   t0, 0x20               # UEN
    sw   t0, UART_CR(s6)
    lw   t0, UART_RX(s6)        # scrub any stale RX state/flags

    li   t0, 0x140              # TIMER0 free-run on MCLK (TEN | SSEL_MCLK),
    sw   t0, TIM_CR(s4)         # the bit-clock for the frames below
    li   t3, 4096               # bounded poll until VAL is really counting
1:  lw   t0, TIM_VAL(s4)
    lw   t1, TIM_VAL(s4)
    bne  t0, t1, 2f
    addi t3, t3, -1
    bnez t3, 1b
    j    fail
2:

    li   gp, 7                  # NEGATIVE CONTROL: frame on P4.5, P4AFS=0
    li   a0, 0x34A              # 0xA5 framed: start(0), LSB-first, stop(1)
    jal  ra, bitbang_frame
    li   t3, 512                # RX0 is watching quiet home P2.5: RCIF must
1:  lw   t0, UART_SR(s6)        # stay 0 the whole time
    andi t0, t0, 0x04
    bnez t0, fail
    addi t3, t3, -1
    bnez t3, 1b

    li   gp, 8                  # engage AF2 on P4.5 and send 0xA5
    li   t0, 0x00200000         # P4AFS field5 = 2
    sw   t0, GPIO_AFS(s3)
    li   a0, 0x34A
    jal  ra, bitbang_frame
    li   t3, 8192               # RCIF within bound
1:  lw   t0, UART_SR(s6)
    andi t1, t0, 0x04
    bnez t1, 2f
    addi t3, t3, -1
    bnez t3, 1b
    j    fail
2:  andi t1, t0, 0x38           # FEF|PEF|OVF must be clean (sampled BEFORE
    bnez t1, fail               # the RX read clears them)
    lw   t1, UART_RX(s6)
    addi t1, t1, -0xA5
    bnez t1, fail

    li   gp, 9                  # second frame: 0x3C (not a one-shot fluke)
    li   a0, 0x278              # (0x3C << 1) | stop bit9
    jal  ra, bitbang_frame
    li   t3, 8192
1:  lw   t0, UART_SR(s6)
    andi t1, t0, 0x04
    bnez t1, 2f
    addi t3, t3, -1
    bnez t3, 1b
    j    fail
2:  andi t1, t0, 0x38
    bnez t1, fail
    lw   t1, UART_RX(s6)
    addi t1, t1, -0x3C
    bnez t1, fail

    sw   zero, GPIO_AFS(s3)     # tidy up
    sw   zero, TIM_CR(s4)
    sw   zero, UART_CR(s6)

    RVTEST_PASS

    #------------------------------------------------------------------
    # spi1_xfer: one 8-bit SPI1 master transfer of a0; returns RX in a0
    #------------------------------------------------------------------
spi1_xfer:
    li   t0, 3
    sw   t0, SPI_SR(s5)         # W1C TCIF/TEIF
    sw   a0, SPI_TX(s5)
    li   t3, 4096
1:  lw   t0, SPI_SR(s5)
    andi t0, t0, 0x02           # TCIF
    bnez t0, 2f
    addi t3, t3, -1
    bnez t3, 1b
    j    fail
2:  lw   a0, SPI_RX(s5)         # read clears TCIF
    andi a0, a0, 0xFF
    ret

    #------------------------------------------------------------------
    # bitbang_frame: shift a0 out on P4.5 LSB-first, one BIT_TICKS-tick
    # slot per bit, 10 slots (timer-paced absolute schedule -- jitter on
    # each edge does not accumulate). P4.6 level is preserved. Ends with
    # the pad at the stop/idle level (a0 bit 9 = 1).
    #------------------------------------------------------------------
bitbang_frame:
    lw   t6, GPIO_OUT(s3)       # current P4 OUT (keep the P4.6 level)
    lw   t0, TIM_VAL(s4)        # slot-0 start tick
    li   t4, 10                 # start + 8 data + stop
1:  andi t1, a0, 1
    andi t6, t6, ~0x20
    beqz t1, 2f
    ori  t6, t6, 0x20
2:  sw   t6, GPIO_OUT(s3)       # pad = this slot's level
    srli a0, a0, 1
3:  lw   t2, TIM_VAL(s4)        # wait out the slot (absolute schedule)
    sub  t2, t2, t0
    li   t5, BIT_TICKS
    bltu t2, t5, 3b
    addi t0, t0, BIT_TICKS
    addi t4, t4, -1
    bnez t4, 1b
    ret

park:
    j    park

fail:
    RVTEST_FAIL

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
