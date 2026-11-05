# CSR read-modify-write executed from flash extended memory, setup as in the tape-out
# periph/SPIEM.S. The RAM part wakes the flash and jumps to 0x10000; the flash part is
# linked there and placed at flash word 0x800 by chip.sh.
#include "myshkin_s.h"
#define P1_DIR_BOOT     (GPIO0_CS_MASK)
#define P1_SEL_BOOT     (GPIO0_MISO_MASK | GPIO0_MOSI_MASK | GPIO0_SCK_MASK | GPIO0_TRAP_MASK)
#define SPI_CR_INIT     0x304C8
#define SPI_CR_FLASH    (SPI_FEN_MASK | SPI_BR(SPI_BR_DIV2) | SPI_EN_MASK | SPI_MSB_MASK | SPI_DL_32BIT | SPI_RXSB_MASK)
    .option norvc
    .section .text.init
    .globl _start
_start:
    li   t0, PERIPH_SYSTEM0_BASE
    li   t1, SYS_MCLKSEL_HFXT | SYS_SMCLKSEL_LFXT
    sw   t1, SYS_CLK_CR(t0)
    li   t0, PERIPH_SPI0_BASE
    li   a0, PERIPH_GPIO0_BASE
    sw   zero, SPI_CR(t0)
    li   a2, P1_DIR_BOOT
    sb   a2, GPIO_PxDIR(a0)
    li   a2, P1_SEL_BOOT
    sb   a2, GPIO_PxSEL(a0)
    li   a6, SPI_CR_INIT
    sw   a6, SPI_CR(t0)
    li   a4, GPIO0_CS_MASK
    sw   a4, GPIO_PxOUTC(a0)
    li   a6, 0xAB            # flash power up
    sw   a6, SPI_TX(t0)
    li   a6, 200000
1:  addi a6, a6, -1
    bnez a6, 1b
    li   t1, 0xFFF2000       # flash offset
    sw   t1, SPI_FOS(t0)
    li   t1, SPI_CR_FLASH
    li   t2, 0x0F
    sw   t2, GPIO_PxSEL(a0)
    sw   t1, SPI_CR(t0)
    li   a0, 0xA5A50001      # reached the jump
    li   t0, 0x10000
    jr   t0

    .section .flash, "ax"
    li   a0, 0xA5A50002      # running from flash
    li   t1, 0x00ABCD00
    csrw mcycle, zero
    nop
    nop
    csrrw t2, mcycle, t1
    nop
    mv   a0, t2              # expect a count, never 00abcd00
    nop
    nop
    li   a0, 0xA5A50003
    csrrs t2, mcycle, zero   # control: a read-only access
    nop
    mv   a0, t2
    nop
    nop
    li   a0, 0x600D0001
1:  j    1b
