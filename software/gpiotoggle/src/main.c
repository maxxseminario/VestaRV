/*
 * gpiotoggle - Manually toggle P3.0 (T0CMP0 pad) from a tight CPU loop.
 *
 * Uses the auto-generated platform header (platform/myshkin/gcc/lib/include/
 * MemoryMap.h, produced by platform/myshkin/python/generate.py). Note that what
 * the chip exposes externally as "P3.x" is driven by the HDL entity
 * named GPIO2 (slot 8, base 0x4800) -- see hdl/myshkin/MCU.vhd line ~855.
 * So GPIO2->* in this file refers to the P3 pads, and pin 0 is T0CMP0.
 */

#include "MemoryMap.h"

int main(void) {
    GPIO2->SEL.value = 0x00;   /* P3.0 -> plain GPIO (not T0CMP0) */
    GPIO2->DIR.value = 0x01;   /* P3.0 -> output                  */
    for (;;) {
        GPIO2->OUTT.value = 0x01;   /* toggle P3.0 every iteration */
    }
    return 0;
}
