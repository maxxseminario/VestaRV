// VestaRV: gpiotoggle demo application
// Toggles P3.0 (the T0CMP0 pad) from a tight CPU loop, through the generated MemoryMap.h.
// The pads labelled P3.x are driven by the HDL entity GPIO2 (slot 8, base 0x4800), so GPIO2 here means the P3 pads and pin 0 is T0CMP0.

#include "MemoryMap.h"

int main(void) {
    GPIO2->SEL.value = 0x00;   /* P3.0 -> plain GPIO (not T0CMP0) */
    GPIO2->DIR.value = 0x01;   /* P3.0 -> output                  */
    for (;;) {
        GPIO2->OUTT.value = 0x01;   /* toggle P3.0 every iteration */
    }
    return 0;
}
