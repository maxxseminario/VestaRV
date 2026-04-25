/*
 * gpiotoggle - Manually toggle P3.0 (GPIO2 pin 0, same physical pad as
 * T0CMP0) from a tight CPU loop. No timer, no interrupts. Use a logic
 * analyzer to confirm the chip is actually executing RAM code that the
 * Forth ROM uploaded via `forth-run gpiotoggle`.
 *
 * GPIO2 base = 0x4800 (8-bit GPIO peripheral, registers spaced 4 bytes):
 *   OUT  @ 0x4804  - data output register
 *   OUTT @ 0x4810  - "toggle" strobe: writing 1-bits flips the matching
 *                    OUT bits in one cycle
 *   DIR  @ 0x4814  - direction (1 = output)
 *   SEL  @ 0x4824  - 0 = plain GPIO, 1 = peripheral function (T0CMP0)
 *
 * Pin 0 of GPIO2 is P3.0 / T0CMP0 (see hdl/MCU/MemoryMap.vhd:
 * pnum_gpio2_t0_cmp0 := 00).
 */

#define REG8(addr) (*(volatile unsigned char *)(addr))

#define P3SEL  REG8(0x4824)
#define P3DIR  REG8(0x4814)
#define P3OUTT REG8(0x4810)

int main(void) {
    P3SEL = 0x00;   /* P3.0 -> plain GPIO (not T0CMP0 peripheral) */
    P3DIR = 0x01;   /* P3.0 -> output                              */
    for (;;) {
        P3OUTT = 0x01;   /* toggle P3.0 every iteration */
    }
    return 0;
}
