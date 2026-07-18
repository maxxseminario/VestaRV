/* lab01_hello -- STUDENT STARTING POINT.
 *
 * Goal: bring up the console, print a hello banner with your hart id, then
 * signal PASS so the checker latches a0 == 0xCAFEBABE.
 *
 * As shipped this program BUILDS but FAILS the check (it calls fail() at the
 * TODO). Complete the TODOs to make it pass.
 */
#include "course.h"

int main(void) {
    console_init();

    printf("Hello from VestaRV Argus (course chip)!\n");
    printf("Running on hart %u\n", (unsigned)read_mhartid());

    /* TODO(lab01):
     *   1. Print one more banner line of your own with printf(...).
     *      Try the conversions: %d %u %x %c %s.
     *   2. Replace the fail() below with pass() once your banner prints,
     *      so the checker sees a0 == 0xCAFEBABE instead of 0xDEADBEEF.
     */
    fail();          /* <-- remove me: as shipped this FAILS (a0 = 0xDEADBEEF) */

    return 0;        /* unreachable */
}
