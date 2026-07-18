/* lab08_interrupts -- REFERENCE SOLUTION.
 *
 * PRIVATE -- do not commit. This completed solution moves to the course's
 * private repo before any vestarv commit.
 *
 * Two interrupts, in C, on hart 0 (TRM ch. 6 interrupts, ch. 19 CLINT,
 * ch. 21 IRQ ROUTER), using the course SDK's interrupt support (course_lib/
 * irq.h): register a C handler, and let the SDK trampoline save/restore context
 * and issue the interrupt-return for you. Your handler's one hard rule: clear
 * the source LEVEL before it returns, or the interrupt re-fires forever.
 *
 * PART A -- CLINT timer interrupt (mtip, IVT vector 84):
 *   Program MTIMECMP[0] a little ahead of the free-running MTIME. When
 *   MTIME >= MTIMECMP[0] the hart takes mtip; the handler counts the tick and
 *   RE-ARMS MTIMECMP[0] forward (which clears the level) for a few ticks, then
 *   DISABLES it (MTIMECMP hi = all-ones) so it goes quiet.
 *
 * PART B -- routed peripheral interrupt (meip, IVT vector 85, claim/complete):
 *   Route TIMER0's compare-0 source (id 19) to hart 0's router row, and run
 *   TIMER0 as a periodic PWM with its compare-0 interrupt enabled. Each compare
 *   match raises meip; the SDK meip trampoline CLAIMs the router (id 19), calls
 *   the handler, then COMPLETEs. The handler clears the peripheral LEVEL (the
 *   TIMER0 CMP0IF flag) before returning; after a few it disables the timer.
 *
 * The console prints the ISR counts for BOTH paths as the pass evidence.
 */
#include "course.h"
#include "irq.h"

/* ---- TIMER0 registers (base from chip.h; offsets from MemoryMap.h) -------- */
#define T0CR    (TIMER0_BASE + 0)
#define T0SR    (TIMER0_BASE + 4)
#define T0VAL   (TIMER0_BASE + 8)
#define T0CMP0  (TIMER0_BASE + 12)
#define T0CMP2  (TIMER0_BASE + 20)

#define TEN_BIT     (0x00000040u)    /* CR bit 6:  timer enable       */
#define CMP2RST_BIT (0x00000080u)    /* CR bit 7:  reset at CMP2       */
#define CMP0IE_BIT  (0x00000001u)    /* CR bit 0:  compare-0 IRQ enable (feeds the router) */
#define SSEL_SMCLK  (0x00000000u)    /* CR bits 9:8 = 00 -> SMCLK      */
#define CMP0IF_BIT  (0x01u)          /* SR bit 0:  compare-0 flag (write 1 = clear) */

#define PWM_PERIOD  (0x100)
#define PWM_DUTY    (0x040)

/* interrupt cadences + how many of each to take (small + bounded) */
#define MTIP_DELTA   (400)           /* MTIMECMP[0] steps, in MTIME ticks (1/mclk) */
#define MTIP_TARGET  (5)
#define EXT_TARGET   (5)
#define MAIN_BUDGET  (5000)          /* bounded main-loop wait (a few thousand polls) */

static volatile int mtip_count;      /* CLINT timer ISR entries  */
static volatile int ext_count;       /* routed TIMER0 ISR entries */

/* ======================================================================= */
/* PART 1 -- the four functions you implement.  (Reference: implemented.)     */
/* ======================================================================= */

/* Arm the CLINT timer: MTIMECMP[0] = MTIME + MTIP_DELTA. MTIMECMP resets
 * all-ones (quiet); write lo first (hi still all-ones = still quiet), then hi=0
 * to arm -- no spurious mtip in between. */
static void arm_timer_tick(void)
{
    uint32_t now = MMR_32_BIT_MACRO(CLINT_MTIME_LO);
    MMR_32_BIT_MACRO(CLINT_MTIMECMP_LO(0)) = now + MTIP_DELTA;
    MMR_32_BIT_MACRO(CLINT_MTIMECMP_HI(0)) = 0;              /* armed */
}

/* CLINT timer ISR (mtip). Count the tick, then clear the LEVEL by re-arming
 * MTIMECMP[0] forward (mtip = MTIME >= MTIMECMP[0], so pushing the compare past
 * MTIME drops it). After MTIP_TARGET ticks, disable by setting the compare hi
 * back to all-ones. Non-recursive; runs to completion, the SDK does retirq. */
static void timer_isr(void)
{
    mtip_count++;
    if (mtip_count < MTIP_TARGET) {
        uint32_t now = MMR_32_BIT_MACRO(CLINT_MTIME_LO);
        MMR_32_BIT_MACRO(CLINT_MTIMECMP_LO(0)) = now + MTIP_DELTA;   /* re-arm (clears level) */
    } else {
        MMR_32_BIT_MACRO(CLINT_MTIMECMP_HI(0)) = 0xFFFFFFFFu;        /* disable (level drops) */
    }
}

/* Route TIMER0 compare-0 (source id 19) to hart 0's router row, and start
 * TIMER0 as a periodic PWM with compare-0 interrupts enabled. SMCLK-domain, so
 * SYS_CLK_CR = 0 FIRST (see lab07). */
static void setup_ext_timer(void)
{
    MMR_32_BIT_MACRO(SYSCLKCR_ADDRESS) = 0;                 /* SMCLK -> HFXT, FIRST */
    MMR_32_BIT_MACRO(IRQR_ROW_ENL(0)) |= (1u << IRQ_SRC_TIM0_CMP0);  /* route 19 -> hart 0 */
    MMR_32_BIT_MACRO(T0CMP0) = PWM_DUTY;
    MMR_32_BIT_MACRO(T0CMP2) = PWM_PERIOD;
    MMR_32_BIT_MACRO(T0CR)   = TEN_BIT | CMP2RST_BIT | CMP0IE_BIT | SSEL_SMCLK;
}

/* Routed-peripheral ISR (meip). Called by the SDK meip trampoline with the
 * claimed source id AFTER the claim and BEFORE the complete. Clear the
 * peripheral LEVEL (TIMER0 CMP0IF) before returning, or the completed source
 * re-pends. After EXT_TARGET matches, stop the timer entirely. */
static void ext_isr(unsigned id)
{
    if (id != IRQ_SRC_TIM0_CMP0) return;                    /* not ours */
    ext_count++;
    MMR_32_BIT_MACRO(T0SR) = CMP0IF_BIT;                    /* clear the LEVEL (write-1) */
    if (ext_count >= EXT_TARGET)
        MMR_32_BIT_MACRO(T0CR) = 0;                         /* stop: no more matches */
}

/* ======================================================================= */
/* PART 2 -- self-checking harness (provided).                              */
/* ======================================================================= */

static int wait_count(volatile int *c, int target)
{
    int budget;
    for (budget = MAIN_BUDGET; budget && (*c < target); budget--) { }
    return *c;                                              /* whatever we reached */
}

int main(void)
{
    console_init();
    printf("lab08_interrupts: CLINT timer (mtip) + routed TIMER0 (meip)\n");

    /* ---- PART A: CLINT timer interrupt (mtip, vector 84) ---------------- */
    irq_on_timer(timer_isr);              /* arm IVT slot 84 -> handler       */
    arm_timer_tick();                     /* program MTIMECMP[0]              */
    wait_count(&mtip_count, MTIP_TARGET);
    printf("part A: mtip ISR entries = %d (want %d)\n", mtip_count, MTIP_TARGET);

    /* ---- PART B: routed TIMER0 compare interrupt (meip, vector 85) ------ */
    irq_on_external(ext_isr);             /* arm IVT slot 85 -> claim/complete */
    setup_ext_timer();                    /* route src 19 + run TIMER0        */
    wait_count(&ext_count, EXT_TARGET);
    printf("part B: meip ISR entries = %d (want %d)\n", ext_count, EXT_TARGET);

    if (mtip_count >= MTIP_TARGET && ext_count >= EXT_TARGET) {
        printf("PASS\n"); pass();
    } else {
        printf("FAIL\n"); fail();
    }
    return 0; /* unreachable */
}
