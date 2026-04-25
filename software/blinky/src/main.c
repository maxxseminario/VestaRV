/*
 * blinky - Use TIMER0 CMP0 hardware to toggle P3.0 (T0CMP0 pad) as fast
 * as possible (square wave at SMCLK / 2). Uses the auto-generated header
 * platform/gcc/lib/include/MemoryMap.h.
 *
 * The chip pads externally labelled "P3.x" are driven by the HDL entity
 * named GPIO2 (slot 8, base 0x4800) -- see hdl/MCU/MCU.vhd line ~855.
 * Pin 0 of that port is T0CMP0.
 *
 * Note re. earlier bug: SSEL_SMCLK is value 0 (not 2 -- value 2 is
 * SSEL_LFXT which has no crystal on the dev board and is gated off by
 * SYSCLKCR.LFXTOFF=1 at reset, so the timer ran in sim but counted at
 * 0 Hz on silicon). We also write CR atomically so the timer is never
 * briefly enabled with the wrong source.
 */

#include "MemoryMap.h"

int main(void) {
    /* P3.0 -> T0CMP0 peripheral function (SEL=1), output (DIR=1). */
    GPIO2->SEL.value = 0x01;
    GPIO2->DIR.value = 0x01;

    /* Fastest possible toggle: CMP0=1, CMP2=2 -> counter is 0,1,0,1,... */
    TIMER0->CMP0.value = 1;
    TIMER0->CMP2.value = 2;

    /* Atomic CR write: enable + toggle CMP0 on match + reset at CMP2,
     * clocked from SMCLK with no prescaler. */
    TIMER0->CR.value = TEN_BIT
                     | CMP0IH_BIT
                     | CMP2RST_BIT
                     | SSEL_SMCLK
                     | DIV_1;

    /* Hardware drives the pad from now on. */
    while (1) { }
    return 0;
}
