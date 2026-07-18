/* lab02_assembly -- C harness (DO NOT EDIT).
 *
 * This file is the test harness. It calls three routines that YOU implement in
 * pure RV32 assembly in src/routines.S, checks each result against a known
 * answer, prints a per-check report over the UART0 console, and then signals
 * PASS (a0 = 0xCAFEBABE) if every check matched or FAIL (a0 = 0xDEADBEEF)
 * otherwise. Edit ONLY src/routines.S.
 *
 * Routine contracts (RV32 calling convention, ilp32 ABI):
 *   unsigned my_strlen(const char *s);          // a0=s -> a0 = byte length (no NUL)
 *   int      my_array_max(const int *a, unsigned n); // a0=a, a1=n(>=1) -> a0 = max
 *   unsigned my_bit_reverse(unsigned x);         // a0=x -> a0 = bit-reversed x
 */
#include "course.h"

unsigned my_strlen(const char *s);
int      my_array_max(const int *a, unsigned n);
unsigned my_bit_reverse(unsigned x);

static int all_ok = 1;

/* NOTE: the SDK printf is a tiny subset -- %s %d %u %x %c %% only, with NO
   width/precision/flags. Keep the format specifiers plain (a "%-22s" would be
   mis-parsed and shift the argument list). */
static void check_u(const char *name, unsigned got, unsigned want) {
    int ok = (got == want);
    printf("  %s: got=0x%x want=0x%x  %s\n", name, got, want,
           ok ? "ok" : "MISMATCH");
    if (!ok) all_ok = 0;
}
static void check_i(const char *name, int got, int want) {
    int ok = (got == want);
    printf("  %s: got=%d want=%d  %s\n", name, got, want,
           ok ? "ok" : "MISMATCH");
    if (!ok) all_ok = 0;
}

int main(void) {
    console_init();
    printf("lab02_assembly: RV32 routine self-check\n");

    /* --- my_strlen -------------------------------------------------------- */
    check_u("strlen(\"\")",        my_strlen(""),        0u);
    check_u("strlen(\"hi\")",      my_strlen("hi"),      2u);
    check_u("strlen(\"VestaRV\")", my_strlen("VestaRV"), 7u);

    /* --- my_array_max ----------------------------------------------------- */
    static const int v1[] = { 3, 9, -4, 9, 2, 7 };
    static const int v2[] = { -100 };
    static const int v3[] = { -5, -2, -9, -1 };
    check_i("array_max{3,9,-4,9,2,7}", my_array_max(v1, 6),  9);
    check_i("array_max{-100}",         my_array_max(v2, 1), -100);
    check_i("array_max{-5,-2,-9,-1}",  my_array_max(v3, 4), -1);

    /* --- my_bit_reverse --------------------------------------------------- */
    check_u("bitrev(0x00000001)", my_bit_reverse(0x00000001u), 0x80000000u);
    check_u("bitrev(0x80000000)", my_bit_reverse(0x80000000u), 0x00000001u);
    check_u("bitrev(0x0000FFFF)", my_bit_reverse(0x0000FFFFu), 0xFFFF0000u);
    check_u("bitrev(0x12345678)", my_bit_reverse(0x12345678u), 0x1E6A2C48u);

    if (all_ok) { printf("ALL CHECKS PASSED\n"); pass(); }
    else        { printf("SOME CHECKS FAILED\n"); fail(); }
    return 0; /* unreachable */
}
