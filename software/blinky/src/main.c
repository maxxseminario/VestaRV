/*
 * blinky - Timer-based LED Blink Application
 * VestaRV Firmware
 * 
 * Uses TIMER0 CMP0 output to toggle P2.0 (T0CMP0 pin) as fast as possible
 */

#include <stdint.h>

/*
 * NOTE: We bypass software/commune/include/MemoryMap.h because that header
 * is wrong for this chip:
 *   - it labels Port 2 (base 0x4800) as "GPIO2" but P3.0/T0CMP0 is on the
 *     chip's Port 3, base 0x4D00 (per platform/gcc/lib/linker/periph.x);
 *   - its GPIOx_8bit_t struct puts SEL at offset 0x24, but the real chip
 *     layout has SEL at offset 0x1C.
 * Until the header is regenerated from the HDL/linker script, write the
 * actual chip addresses directly.
 */
#define REG8(addr)  (*(volatile unsigned char *)(addr))
#define REG32(addr) (*(volatile unsigned int  *)(addr))

/* Port 3 (T0CMP0 pad is P3.0) */
#define P3DIR   REG8(0x4D14)
#define P3SEL   REG8(0x4D1C)

/* TIMER0 */
#define TIM0CR   REG32(0x4600)
#define TIM0CMP0 REG32(0x460C)
#define TIM0CMP2 REG32(0x4614)

/* TIM0CR bit fields (from MemoryMap.h - these match the HDL) */
#define TEN_BIT     (0x00000040)  /* bit 6  - timer enable             */
#define CMP2RST_BIT (0x00000080)  /* bit 7  - counter reset at CMP2     */
#define CMP0IH_BIT  (0x00004000)  /* bit 14 - toggle T0CMP0 on match    */
#define SSEL_SMCLK  (0x00000000)  /* SSEL field = 0 -> clock from SMCLK */
#define DIV_1       (0x00000000)  /* no prescaler                       */

int main(void) {
    /* P3.0 -> T0CMP0 peripheral function (SEL=1), output (DIR=1). */
    P3SEL = 0x01;
    P3DIR = 0x01;

    /* Fastest possible toggle: CMP0=1, CMP2=2 -> counter goes 0,1,0,1,... */
    TIM0CMP0 = 1;
    TIM0CMP2 = 2;
    
    // Configure timer control register:
    // - CMP0IH: CMP0 output toggles on each match
    // - CMP2RST: Counter resets at 2, creating continuous 0→1→0 count
    // - TEN: Enable timer
    // - DIV_1: No clock division (maximum speed)
    // - SSEL_SMCLK: Use system master clock
    // Write CR atomically. Doing per-bitfield writes does read-modify-write
    // on the whole 32-bit CR, which (a) briefly enables the timer with the
    // wrong source and (b) made it easy to ship the bug below: SSEL_SMCLK
    // is value 0, NOT 2 (value 2 is SSEL_LFXT, which has no crystal on the
    // dev board and is gated off by SYSCLKCR.LFXTOFF=1 at reset, so the
    // timer counted at 0 Hz on silicon even though it ran in simulation).
    TIM0CR = TEN_BIT       /* enable timer                       */
           | CMP0IH_BIT    /* toggle T0CMP0 output on each match */
           | CMP2RST_BIT   /* reset counter at CMP2              */
           | SSEL_SMCLK    /* clock source = SMCLK               */
           | DIV_1;        /* no prescaler                       */
    
    // Timer now toggles T0CMP0 output in hardware automatically
    while(1) {
        // Infinite loop - hardware handles everything
    }
    
    return 0;
}
