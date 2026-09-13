// VestaRV: slowblink demo application
// Toggles P3.0 (the T0CMP0 pad) at a human-visible rate from a CPU delay loop, with no timer, to confirm the chip is executing RAM code.
// The pads labelled P3.x are driven by the HDL entity GPIO2 (slot 8, base 0x4800); pin 0 is T0CMP0.
// The inner loop is about 2 cycles per iteration, so at SMCLK 10 MHz DELAY = 1500000 gives a 0.3 s half period.

#include "MemoryMap.h"

#define DELAY 1500000u

static void delay(unsigned n) {
    /* `volatile` asm to keep GCC from optimising the loop away. */
    while (n--) {
        __asm__ volatile ("");
    }
}

int main(void) {
    GPIO2->SEL.value = 0x00;   /* P3.0 -> plain GPIO */
    GPIO2->DIR.value = 0x01;   /* P3.0 -> output     */
    for (;;) {
        GPIO2->OUTT.value = 0x01;   /* toggle */
        delay(DELAY);
    }
    return 0;
}
