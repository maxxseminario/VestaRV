/* lab07_timer -- STUDENT STARTING POINT.
 *
 * Register-level TIMER0 driver (TRM ch. 14). You configure the timer's clock
 * source + divider and a PWM-style compare pattern (CMP0 = duty, CMP2 = period
 * with auto-reset), then read it back purely through TIMER0's own registers:
 * the count (TIM0VAL), the compare flag (CMP0IF), and the PWM output level
 * (CMP0OUT). No interrupts here (that is lab08); everything is polled, bounded,
 * and self-checked. UART0 stays the console (SDK printf) so you can watch the
 * trace. The pass gate is pass()/fail().
 *
 * As shipped this BUILDS but FAILS: timer0_init() is empty (TIMER0 stays
 * disabled and never counts) and timer0_wait_counting() returns 0, so the
 * "counting" check times out and main() calls fail() (a0 = 0xDEADBEEF). The
 * UART0 console still prints the trace, showing which checks fail -- the
 * negative control. Implement the two functions to make it PASS.
 *
 * TWO TRAPS THIS LAB EXISTS TO TEACH (TRM ch. 14 + 15):
 *   (a) TIMER0 is clocked from the SMCLK domain, and the boot ROM parks SMCLK
 *       on the 32 kHz LFXT mid-boot. Write SYS_CLK_CR = 0 (SMCLK -> HFXT) FIRST,
 *       before anything else -- otherwise the timer counts ~750x too slowly and
 *       the bounded compare/period polls below time out.
 *   (b) The timer's clock mux is glitch-free: it DEFAULTS to the smclk slice and
 *       needs edges from the OLD source to release before the newly selected
 *       source drives the counter. So after enabling you must POLL until TIM0VAL
 *       is actually advancing -- never assume it is counting, and never take two
 *       back-to-back VAL samples right after enable and compare them (both can
 *       still read the pre-handoff value).
 */
#include "course.h"

/* ---- TIMER0 registers (base from chip.h; offsets from MemoryMap.h) --------
 * All accesses are 32-bit (the peripheral bus is word-oriented, as shtimer.S). */
#define T0CR    (TIMER0_BASE + 0)    /* control       (TRM 14) */
#define T0SR    (TIMER0_BASE + 4)    /* status/flags  (TRM 14) */
#define T0VAL   (TIMER0_BASE + 8)    /* live counter  (TRM 14) */
#define T0CMP0  (TIMER0_BASE + 12)   /* compare 0 = duty   */
#define T0CMP1  (TIMER0_BASE + 16)   /* compare 1          */
#define T0CMP2  (TIMER0_BASE + 20)   /* compare 2 = period */

/* TIM0CR fields (TRM 14): */
#define TEN_BIT     (0x00000040u)    /* bit 6:  timer enable          */
#define CMP2RST_BIT (0x00000080u)    /* bit 7:  reset counter at CMP2 */
#define SSEL_SMCLK  (0x00000000u)    /* bits 9:8 = 00 -> SMCLK source */
#define DIV_4       (0x00020000u)    /* bits 19:16 = 2 -> divide by 4 */

/* TIM0SR flags (TRM 14): */
#define CMP0IF_BIT  (0x01u)          /* bit 0: compare-0 match flag (write 1 = clear) */
#define CMP0OUT_BIT (0x40u)          /* bit 6: compare-0 (PWM) output level           */

/* PWM shape: period 0x200, duty 0x080 (25%). Modest values so the whole run
   fits well inside the tb's 100 ms watchdog. */
#define PWM_PERIOD  (0x200)
#define PWM_DUTY    (0x080)

#define POLL_BUDGET (20000)          /* bounded -> a stuck timer trips the watchdog */

/* ======================================================================= */
/* PART 1 -- the two functions you implement.  IMPLEMENT THESE TWO.          */
/* ======================================================================= */

/* Configure TIMER0 as a free-running PWM generator, register by register.
 * ORDER MATTERS -- SYS_CLK_CR = 0 is FIRST (trap a). Then program the compare
 * points, then one CR write that selects source + divider and enables the
 * timer with CMP2 auto-reset. */
static void timer0_init(void)
{
    /* TODO(lab07): four word writes, in order.
     *   1. MMR_32_BIT_MACRO(SYSCLKCR_ADDRESS) = 0;    -- SMCLK -> HFXT (do FIRST)
     *   2. MMR_32_BIT_MACRO(T0CMP0) = PWM_DUTY;       -- duty compare
     *   3. MMR_32_BIT_MACRO(T0CMP2) = PWM_PERIOD;     -- period compare
     *   4. MMR_32_BIT_MACRO(T0CR)   = TEN_BIT | CMP2RST_BIT | SSEL_SMCLK | DIV_4;
     */
}

/* Wait (bounded) until TIMER0 is actually counting after enable (trap b): the
 * glitch-free clock mux needs OLD-source edges to release. Sample VAL once, then
 * poll a FRESH read until it has advanced past that first sample. Returns the
 * poll count on success (>= 1), or 0 if it never started counting. */
static int timer0_wait_counting(void)
{
    /* TODO(lab07):
     *   uint32_t first = MMR_32_BIT_MACRO(T0VAL);      -- ONE baseline sample
     *   for (b = POLL_BUDGET; b; b--)
     *       if (MMR_32_BIT_MACRO(T0VAL) != first) return (POLL_BUDGET - b) + 1;
     *   return 0;
     * (Do NOT take two back-to-back samples right after enable and compare them:
     *  before the mux hands off, both read the same pre-handoff value.)
     */
    return 0;
}

/* ======================================================================= */
/* PART 2 -- self-checking harness (provided).                              */
/* ======================================================================= */

/* poll TIM0SR until CMP0IF sets (a compare-0 match happened), bounded. */
static int wait_cmp0if(void)
{
    int budget;
    for (budget = POLL_BUDGET; budget; budget--)
        if (MMR_32_BIT_MACRO(T0SR) & CMP0IF_BIT) return 1;
    return 0;
}

int main(void)
{
    int checks_ok = 0;
    const int want = 6;
    uint32_t sr, val;

    console_init();
    printf("lab07_timer: register-level TIMER0 PWM driver\n");
    printf("TIMER0 @ 0x%x, period=0x%x duty=0x%x, src=SMCLK/4\n",
           (unsigned)TIMER0_BASE, (unsigned)PWM_PERIOD, (unsigned)PWM_DUTY);

    /* check 1: CR resets to 0 (before we touch it). */
    if (MMR_32_BIT_MACRO(T0CR) == 0) { checks_ok++; printf("[ok] CR resets 0\n"); }
    else printf("[FAIL] CR reset != 0\n");

    timer0_init();
    printf("TIMER0 configured (SYS_CLK_CR=0 first, CMP0/CMP2 set, enabled)\n");

    /* check 2: it is actually counting (trap b -- poll, do not assume). */
    { int polls = timer0_wait_counting();
      if (polls > 0) { checks_ok++; printf("[ok] counting after %d polls\n", polls); }
      else           { printf("[FAIL] TIM0VAL never advanced (clock mux?)\n"); } }

    /* check 3: a compare-0 match sets CMP0IF; clearing it (write 1) works. */
    if (wait_cmp0if()) {
        MMR_32_BIT_MACRO(T0SR) = CMP0IF_BIT;             /* write-1-clear */
        if (!(MMR_32_BIT_MACRO(T0SR) & CMP0IF_BIT)) {
            checks_ok++; printf("[ok] CMP0IF set then cleared\n");
        } else printf("[FAIL] CMP0IF did not clear\n");
    } else printf("[FAIL] CMP0IF never set\n");

    /* checks 4 + 5: read the PWM back through VAL + the CMP0OUT level, and
     * confirm the counter auto-resets at CMP2 (period generation). Sample many
     * (VAL, SR) pairs across several periods. */
    { int saw_out_lo = 0, saw_out_hi = 0, saw_wrap = 0, over = 0;
      uint32_t prev = MMR_32_BIT_MACRO(T0VAL);
      int i;
      for (i = 0; i < 3000; i++) {
          val = MMR_32_BIT_MACRO(T0VAL);
          sr  = MMR_32_BIT_MACRO(T0SR);
          if (sr & CMP0OUT_BIT) saw_out_hi = 1; else saw_out_lo = 1;
          if (val < prev)                saw_wrap = 1;      /* counter reset (period) */
          if (val > PWM_PERIOD + 4)      over = 1;          /* must never exceed CMP2 */
          prev = val;
      }
      if (saw_out_lo && saw_out_hi) { checks_ok++; printf("[ok] CMP0OUT toggles (PWM)\n"); }
      else printf("[FAIL] CMP0OUT stuck (lo=%d hi=%d)\n", saw_out_lo, saw_out_hi);

      if (saw_wrap && !over) { checks_ok++; printf("[ok] counter auto-resets at CMP2 (period)\n"); }
      else printf("[FAIL] no clean period wrap (wrap=%d over=%d)\n", saw_wrap, over);
    }

    /* check 6: disabling the timer freezes VAL. */
    MMR_32_BIT_MACRO(T0CR) = 0;
    { uint32_t a = MMR_32_BIT_MACRO(T0VAL);
      uint32_t b = MMR_32_BIT_MACRO(T0VAL);
      if (a == b) { checks_ok++; printf("[ok] disable freezes VAL (0x%x)\n", (unsigned)a); }
      else printf("[FAIL] VAL still moving after disable\n"); }

    printf("checks passed: %d of %d\n", checks_ok, want);
    if (checks_ok == want) { printf("PASS\n"); pass(); }
    else                   { printf("FAIL\n"); fail(); }
    return 0; /* unreachable */
}
