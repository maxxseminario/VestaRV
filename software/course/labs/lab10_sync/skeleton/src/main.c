/* lab10_sync -- STUDENT STARTING POINT.
 *
 * SYNCHRONIZATION (TRM ch. 4.4, ch. 7.9 atomics, ch. 20 mutex bank). Six harts
 * (hart 0 + tiles 1..NTILES) each perform SECTIONS non-atomic read-modify-write
 * increments of a SHARED counter inside a critical section, under two different
 * mutual-exclusion mechanisms:
 *
 *   Phase 1 -- an LR/SC SPINLOCK (a shared lock word, lr.w/sc.w) with a
 *              HARTID-SCALED BACKOFF after every failed acquire. Identical harts
 *              that retry in lockstep LIVELOCK on the fair round-robin arbiter
 *              (every SC keeps failing because a peer's LR clears the
 *              reservation); the backoff de-synchronizes them so one wins.
 *
 *   Phase 2 -- the HW MUTEX BANK (0x6000): a 1-instruction atomic claim (a plain
 *              lw returns 0 if the mutex was free and claims it; sw 0 releases).
 *
 * If the mutual exclusion is correct each counter ends EXACTLY NTOTAL*SECTIONS.
 *
 * As shipped this BUILDS but FAILS: the four lock primitives below are stubbed
 * (spin_acquire/mtx_acquire "succeed" instantly without ever excluding anyone),
 * so the critical sections run concurrently, updates are LOST, and the counters
 * come out low. Hart 0 reports the mismatch and calls fail() (a0 = 0xDEADBEEF).
 * Implement the four primitives to make the totals exact and the run PASS.
 *
 * NOTE: the LR/SC acquire MUST include the hartid-scaled backoff -- without it
 * the harts livelock (a hang, not a wrong count). Bound every retry loop.
 *
 * Shared words (course band 0x102A0-0x1037F, bootrom-zeroed at boot):
 *     SLOCK  = 0x102C0     LR/SC spinlock word (0 free, 1 held)
 *     SCTR   = 0x102C4     spinlock-protected counter (ends NTOTAL*SECTIONS)
 *     SOWNER = 0x102C8     spinlock owner marker (teaching)
 *     MCTR   = 0x102CC     mutex-protected counter   (ends NTOTAL*SECTIONS)
 *     MOWNER = 0x102D0     mutex owner marker (teaching)
 *     DONE[h]= 0x102E0+4*h  tile h reported-in (h = 1..NTILES)
 * The HW mutex itself is MUTEX0 @0x6000 (never LR/SC or AMO a mutex address).
 */
#include "course.h"

/* Stage/copy the whole small image (code + data + this file's statics). */
#define MP_IMAGE_WORDS  (1024u)
#include "mp.h"

#define NTILES      (5)
#define NTOTAL      (NTILES + 1)
#define SECTIONS    (32)
#define LOCK_BUDGET (4096)
#define GATHER_BUDGET (200000)

#define SLOCK       (0x102C0u)
#define SCTR        (0x102C4u)
#define SOWNER      (0x102C8u)
#define MCTR        (0x102CCu)
#define MOWNER      (0x102D0u)
#define DONE_BASE   (0x102E0u)
#define DONE_MAGIC  (0x5A5C0000u)
#define MUTEX0      (0x6000u)

#define W(a)        MMR_32_BIT_MACRO(a)
#define DONE(h)     MMR_32_BIT_MACRO(DONE_BASE + 4u*(h))

static void backoff(unsigned hartid)
{
    volatile unsigned d = hartid * 8u + 8u;
    while (d--) { __asm__ volatile("" ::: "memory"); }
}

/* ======================================================================= */
/* PART 1 -- the four lock primitives you implement.  IMPLEMENT THESE.        */
/* ======================================================================= */

/* LR/SC spinlock acquire: lr.w the lock; if 0 (free), sc.w a 1 to commit; retry
 * on sc failure. Bounded; return 0 on success, 1 if the budget is exhausted.
 * MUST include the hartid-scaled backoff after a failed attempt. */
static int spin_acquire(unsigned hartid)
{
    /* TODO(lab10):
     *   int budget = LOCK_BUDGET;
     *   for (;;) {
     *       uint32_t held, scfail;
     *       __asm__ volatile("lr.w %0, (%1)" : "=r"(held) : "r"(SLOCK) : "memory");
     *       if (held == 0) {
     *           __asm__ volatile("sc.w %0, %2, (%1)"
     *                            : "=&r"(scfail) : "r"(SLOCK), "r"(1u) : "memory");
     *           if (scfail == 0) return 0;
     *       }
     *       if (--budget == 0) return 1;
     *       backoff(hartid);          -- REQUIRED (or the harts livelock)
     *   }
     */
    (void)hartid;
    return 0;                          /* stub: pretends to acquire (no exclusion) */
}
static void spin_release(void)
{
    /* TODO(lab10): W(SLOCK) = 0u; */
}

/* HW mutex acquire (1-instruction atomic claim): a plain lw returns 0 if the
 * mutex was free (and claims it), else the holder's hartid+1. Bounded + backoff.
 * Return 0 on success, 1 on exhaustion. */
static int mtx_acquire(unsigned hartid)
{
    /* TODO(lab10):
     *   int budget = LOCK_BUDGET;
     *   for (;;) {
     *       uint32_t old = W(MUTEX0);
     *       if (old == 0) return 0;
     *       if (--budget == 0) return 1;
     *       backoff(hartid);
     *   }
     */
    (void)hartid;
    return 0;                          /* stub: pretends to acquire (no exclusion) */
}
static void mtx_release(void)
{
    /* TODO(lab10): W(MUTEX0) = 0u; */
}

/* ======================================================================= */
/* PART 2 -- the contended work + gather harness (provided).                 */
/* ======================================================================= */

static int run_sections(unsigned hartid, uint32_t ctr, uint32_t owner, int use_mutex)
{
    unsigned marker = hartid + 1u;
    int s;
    for (s = 0; s < SECTIONS; s++) {
        uint32_t v;
        if (use_mutex ? mtx_acquire(hartid) : spin_acquire(hartid))
            return 1;
        W(owner) = marker;
        v = W(ctr); v = v + 1u; W(ctr) = v;
        if (use_mutex) mtx_release(); else spin_release();
    }
    return 0;
}

static int work_body(unsigned hartid)
{
    if (run_sections(hartid, SCTR, SOWNER, 0)) return 1;
    if (run_sections(hartid, MCTR, MOWNER, 1)) return 2;
    return 0;
}

void mp_tile_main(unsigned hartid)
{
    if (work_body(hartid)) fail();
    DONE(hartid) = DONE_MAGIC + hartid;
}

int main(void)
{
    unsigned h;
    int rc;

    console_init();
    printf("lab10_sync: %d harts x %d increments, spinlock + HW mutex\n",
           NTOTAL, SECTIONS);

    mp_stage_image(MP_IMAGE_WORDS);
    for (h = 1; h <= NTILES; h++) mp_launch_hart(h, MP_IMAGE_WORDS);

    rc = work_body(0);
    if (rc == 1) { printf("LIVELOCK: hart 0 spinlock retry budget exhausted (backoff removed)\n"); fail(); }
    if (rc == 2) { printf("FAIL: hart 0 mutex retry budget exhausted\n"); fail(); }

    for (h = 1; h <= NTILES; h++) {
        int budget;
        for (budget = GATHER_BUDGET;
             budget && (DONE(h) != DONE_MAGIC + h);
             budget--) { }
        if (DONE(h) != DONE_MAGIC + h) {
            printf("LIVELOCK: hart %u never finished (retry budget exhausted)\n", h);
            fail();
        }
    }

    printf("spinlock counter = %u (want %u)\n", W(SCTR), NTOTAL * SECTIONS);
    printf("mutex    counter = %u (want %u)\n", W(MCTR), NTOTAL * SECTIONS);

    if (W(SCTR) == (uint32_t)(NTOTAL * SECTIONS) &&
        W(MCTR) == (uint32_t)(NTOTAL * SECTIONS)) {
        printf("PASS\n"); pass();
    } else {
        printf("FAIL (lost updates)\n"); fail();
    }
    return 0; /* unreachable */
}
