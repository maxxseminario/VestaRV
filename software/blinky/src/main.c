/*
 * blinky - Timer-based LED Blink Application
 * VestaRV Firmware
 * 
 * Uses TIMER0 CMP0 output to toggle P2.0 (T0CMP0 pin) as fast as possible
 */

#include <stdint.h>

/*
 * NOTE on naming: the chip pads labelled "P3.x" externally are driven by
 * the HDL entity named "GPIO2" (slot 8) which lives at base 0x4800. See
 * hdl/MCU/MCU.vhd line ~855: "-- GPIO2 Signals (Port 3)". The peripheral
 * at 0x4D00 (HDL "GPIO3", slot 13) is a different, unrelated port.
 * Pin 0 of the 0x4800 port is T0CMP0 (the timer's CMP0 output pad).
 *
 * We bypass software/commune/include/MemoryMap.h's TIMER0->CR.value path
 * because the per-bitfield-then-OR pattern was easy to mis-use; we write
 * the chip addresses directly.
 */
#define REG8(addr)  (*(volatile unsigned char *)(addr))
#define REG32(addr) (*(volatile unsigned int  *)(addr))

/* Port labelled P3 externally / GPIO2 in HDL (base 0x4800).
 * 8-bit GPIO peripheral register offsets: OUT=0x04, OUTT=0x10,
 * DIR=0x14, SEL=0x24 (matches C MemoryMap.h GPIOx_8bit_t). */
#define P3DIR   REG8(0x4814)
#define P3SEL   REG8(0x4824)

/* TIMER0 (base 0x4600) */
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
