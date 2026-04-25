/*
 * slowblink - Toggle P3.0 (T0CMP0 pad) at a human-visible rate using a
 * pure CPU delay loop (no timer). Use this to confirm with a logic
 * analyzer OR a slow-decay LED that the chip is executing RAM code.
 *
 * P3.x externally = HDL entity GPIO2 (slot 8, base 0x4800), pin 0 is
 * the T0CMP0 pad. Uses the auto-generated MemoryMap.h header.
 *
 * DELAY tuning: at SMCLK = 10 MHz the inner loop runs at ~2 cycles per
 * iteration, so DELAY=1500000 -> ~0.3 s half-period -> ~1.6 Hz toggle.
 * Halve DELAY if too slow; double if too fast.
 */

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
