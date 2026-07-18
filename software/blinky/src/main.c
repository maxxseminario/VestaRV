/*
 * blinky - Drive P3.0 (T0CMP0 pad) with TIMER0 hardware for a visible
 * ~1 Hz blink (2 Hz toggle). Uses the auto-generated header
 * platform/myshkin/gcc/lib/include/MemoryMap.h.
 *
 * The chip pads externally labelled "P3.x" are driven by the HDL entity
 * named GPIO2 (slot 8, base 0x4800) -- see hdl/myshkin/MCU.vhd line ~855.
 * Pin 0 of that port is T0CMP0.
 *
 * Timing (assuming SMCLK ~= 10 MHz):
 *   timer_clock = SMCLK / 32768 ~= 305 Hz
 *   CMP2RST resets the 32-bit counter at CMP2 -> period = (CMP2+1)/305
 *   CMP0IH toggles cmp0_out on each CMP0 match -> one toggle per period
 *   CMP2 = 152 -> period ~= 0.50 s -> 2 Hz toggle -> ~1 Hz blink
 *   CMP0 = 76  -> mid-cycle (value not critical with CMP0IH; just must
 *                 be <= CMP2 so it fires once per period)
 *
 * Header values were cross-checked against hdl/myshkin/periph/TIMER.vhd:
 *   control_reg(6)       = timer_enable        -> TEN_BIT     = 0x40
 *   control_reg(7)       = compare2_reset_en   -> CMP2RST_BIT = 0x80
 *   control_reg(14)      = compare0_init_level -> CMP0IH_BIT  = 0x4000
 *   control_reg(9:8)     = clock_source_select -> SSEL_SMCLK  = 0
 *   control_reg(19:16)   = clock_divider       -> DIV_32768   = 0xF<<16
 */

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
