/* lab01_hello -- REFERENCE SOLUTION.
 *
 * PRIVATE -- do not commit. This completed solution moves to the course's
 * private repo before any vestarv commit.
 *
 * Brings up the UART0 console, prints a banner and this hart's id, exercises
 * the tiny printf, and signals PASS. In the instructor sim riscv_tb latches
 * a0 == 0xCAFEBABE.
 */
#include "course.h"

int main(void) {
    console_init();

    printf("Hello from VestaRV Argus (course chip)!\n");
    printf("Running on hart %u\n", (unsigned)read_mhartid());

    /* exercise every printf conversion the SDK supports */
    printf("printf check: dec=%d  uns=%u  hex=0x%x  char=%c  str=%s\n",
           -42, 42u, 0xC0FFEE, '!', "ok");

    pass();          /* a0 = 0xCAFEBABE, spin */
    return 0;        /* unreachable */
}
