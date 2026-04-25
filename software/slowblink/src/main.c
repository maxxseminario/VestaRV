/*
 * slowblink - Toggle P3.0 (T0CMP0 pad) at a human-visible rate using a
 * pure CPU delay loop (no timer). Use this to confirm with a logic
 * analyzer OR a slow-decay LED that the chip is executing RAM code.
 *
 * The "P3" pads are the GPIO peripheral at HDL slot 8 / base 0x4800
 * (despite the name "GPIO2" inside MCU.vhd). See gpiotoggle for details.
 *
 * DELAY tuning: at SMCLK = 10 MHz, the inner loop runs at ~3 cycles per
 * iteration, so DELAY=1500000 -> ~0.45 s half-period -> ~1.1 Hz toggle.
 * If the rate looks wrong on the analyzer, change DELAY here and rerun:
 *   - too slow -> halve DELAY
 *   - too fast -> double DELAY
 */

#define REG8(addr) (*(volatile unsigned char *)(addr))

#define P3OUTT REG8(0x4810)
#define P3DIR  REG8(0x4814)
#define P3SEL  REG8(0x4824)

#define DELAY 1500000u

static void delay(unsigned n) {
    /* `volatile` so GCC doesn't optimise the loop away. */
    while (n--) {
        __asm__ volatile ("");
    }
}

int main(void) {
    P3SEL = 0x00;     /* P3.0 -> plain GPIO */
    P3DIR = 0x01;     /* P3.0 -> output     */
    for (;;) {
        P3OUTT = 0x01;     /* toggle */
        delay(DELAY);
    }
    return 0;
}
