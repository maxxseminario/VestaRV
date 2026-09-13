// VestaRV: blinky demo application
// Drives P3.0 (the T0CMP0 pad) from TIMER0 hardware for a ~1 Hz blink (2 Hz toggle), through the generated MemoryMap.h.
// The pads labelled P3.x are driven by the HDL entity GPIO2 (slot 8, base 0x4800); pin 0 of that port is T0CMP0.
// At SMCLK 10 MHz the timer clock is SMCLK/32768 = 305 Hz. CMP2RST resets the 32-bit counter at CMP2, so the period is (CMP2+1)/305 and CMP2 = 152 gives 0.50 s; CMP0IH toggles cmp0_out once per period, so CMP0 only has to be <= CMP2.

#include "MemoryMap.h"

int main(void) {
    /* P3.0 -> T0CMP0 peripheral function (SEL=1), output (DIR=1). */
    GPIO2->SEL.value = 0x01;
    GPIO2->DIR.value = 0x01;

    /* Period = CMP2+1 timer ticks; toggle once per period via CMP0IH. */
    TIMER0->CMP0.value = 76;
    TIMER0->CMP2.value = 152;

    /* Atomic CR write: SMCLK / 32768, toggle CMP0 on match, reset at
     * CMP2, then enable. */
    TIMER0->CR.value = TEN_BIT
                     | CMP0IH_BIT
                     | CMP2RST_BIT
                     | SSEL_SMCLK
                     | DIV_32768;

    /* Hardware drives the pad from now on. */
    while (1) { }
    return 0;
}
