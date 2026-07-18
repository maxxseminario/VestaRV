/* lab10_sync -- REFERENCE SOLUTION (also the source of the nobackoff variant).
 *
 * PRIVATE -- do not commit. This completed solution (and the nobackoff build
 * that #includes it with -DNO_BACKOFF) move to the course's private repo before
 * any vestarv commit. Only skeleton/ ships publicly.
 *
 * SYNCHRONIZATION (TRM ch. 4.4, ch. 7.9 atomics, ch. 20 mutex bank). Six harts
 * (hart 0 + tiles 1..NTILES) each perform SECTIONS non-atomic read-modify-write
 * increments of a SHARED counter inside a critical section, under two different
 * mutual-exclusion mechanisms:
 *
 *   Phase 1 -- an LR/SC SPINLOCK (a shared lock word, lr.w/sc.w), with a
 *              HARTID-SCALED BACKOFF after every failed acquire. On the fair
 *              round-robin arbiter, identical harts that retry in lockstep
 *              LIVELOCK -- every SC keeps failing because a peer's LR clears the
 *              reservation. The backoff de-synchronizes them so one wins. This
 *              is a REAL measured property of the chip (see the SDK README and
 *              CLAUDE.md); the negative-control build below removes the backoff
 *              and MUST livelock (bounded retries exhaust -> FAIL).
 *
 *   Phase 2 -- the HW MUTEX BANK (0x6000): a 1-instruction atomic claim (a plain
 *              lw returns 0 if the mutex was free and claims it; sw 0 releases).
 *              Still spins, so it also uses backoff for fairness.
 *
 * If the mutual exclusion is correct, each counter ends EXACTLY NTOTAL*SECTIONS.
 * A missing/incorrect lock loses updates and the total comes out low.
 *
 * NEGATIVE CONTROL (nobackoff/): the same source built with -DNO_BACKOFF drops
 * ONLY the Phase-1 spinlock backoff. The tile harts then livelock on the
 * spinlock, their bounded retry budgets exhaust, and the run FAILS by retry
 * exhaustion with a distinct console message. A PASS there would contradict a
 * documented chip property.
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

#define NTILES      (5)                 /* launch harts 1..NTILES */
#define NTOTAL      (NTILES + 1)        /* + hart 0 = contending harts */
#define SECTIONS    (32)                /* critical sections per hart per phase */
#define LOCK_BUDGET (4096)              /* bounded retries: succeeds WITH backoff,
                                           trips well inside the 100 ms watchdog
                                           WITHOUT it (65536 would ride past it) */
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

/* Hartid-scaled busy-wait: peers back off by DIFFERENT amounts, breaking the
 * lockstep that livelocks the fair round-robin arbiter (M4c rule). */
static void backoff(unsigned hartid)
{
    volatile unsigned d = hartid * 8u + 8u;
    while (d--) { __asm__ volatile("" ::: "memory"); }
}

/* ======================================================================= */
/* PART 1 -- the four lock primitives you implement. (Reference: complete.)  */
/* ======================================================================= */

/* LR/SC spinlock acquire. Reserve with lr.w; if free, try to commit 0->1 with
 * sc.w (fails if a peer touched the word since our lr.w -> retry). Bounded;
 * returns 0 on success, 1 if the retry budget is exhausted (a livelock). */
static int spin_acquire(unsigned hartid)
{
    int budget = LOCK_BUDGET;
    for (;;) {
        uint32_t held, scfail;
        __asm__ volatile("lr.w %0, (%1)" : "=r"(held) : "r"(SLOCK) : "memory");
        if (held == 0) {
            __asm__ volatile("sc.w %0, %2, (%1)"
                             : "=&r"(scfail) : "r"(SLOCK), "r"(1u) : "memory");
            if (scfail == 0) return 0;      /* committed the 0->1: lock is ours */
        }
        if (--budget == 0) return 1;        /* retry budget exhausted: livelock */
#ifndef NO_BACKOFF
        backoff(hartid);                    /* REQUIRED: de-synchronize peers   */
#else
        (void)hartid;                       /* negative control: no backoff     */
#endif
    }
}
static void spin_release(void) { W(SLOCK) = 0u; }   /* plain store releases */

/* HW mutex bank acquire (1-instruction atomic claim): a plain lw returns 0 if
 * the mutex was free (and claims it for this hart), else the holder's hartid+1.
 * Bounded + backoff for fairness. Returns 0 on success, 1 on exhaustion. */
static int mtx_acquire(unsigned hartid)
{
    int budget = LOCK_BUDGET;
    for (;;) {
        uint32_t old = W(MUTEX0);           /* atomic claim-read */
        if (old == 0) return 0;             /* was free -> now mine */
        if (--budget == 0) return 1;
        backoff(hartid);                    /* backoff ALWAYS for the mutex spin */
    }
}
static void mtx_release(void) { W(MUTEX0) = 0u; }   /* sw 0 releases */

/* ======================================================================= */
/* PART 2 -- the contended work + gather harness (provided).                 */
/* ======================================================================= */

/* SECTIONS critical sections: each does a NON-ATOMIC lw/addi/sw of the shared
 * counter -- only the lock makes it safe. Returns 1 if an acquire exhausted. */
static int run_sections(unsigned hartid, uint32_t ctr, uint32_t owner, int use_mutex)
{
    unsigned marker = hartid + 1u;
    int s;
    for (s = 0; s < SECTIONS; s++) {
        uint32_t v;
        if (use_mutex ? mtx_acquire(hartid) : spin_acquire(hartid))
            return 1;                       /* retry budget exhausted */
        W(owner) = marker;                  /* mark ownership (teaching)  */
        v = W(ctr); v = v + 1u; W(ctr) = v; /* the protected RMW           */
        if (use_mutex) mtx_release(); else spin_release();
    }
    return 0;
}

/* Both phases. Returns 0 = ok, 1 = Phase-1 spinlock livelock, 2 = Phase-2. */
static int work_body(unsigned hartid)
{
    if (run_sections(hartid, SCTR, SOWNER, 0)) return 1;   /* LR/SC spinlock */
    if (run_sections(hartid, MCTR, MOWNER, 1)) return 2;   /* HW mutex bank  */
    return 0;
}

/* Tile body: contend, then report in. A livelock -> fail() (a0 = 0xDEADBEEF,
 * which riscv_tb latches for harts 1-3 -> the run fails). */
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

    /* Stage once, launch the tiles, then hart 0 contends too (max contention
     * right after launch). */
    mp_stage_image(MP_IMAGE_WORDS);
    for (h = 1; h <= NTILES; h++) mp_launch_hart(h, MP_IMAGE_WORDS);

    rc = work_body(0);
    if (rc == 1) { printf("LIVELOCK: hart 0 spinlock retry budget exhausted (backoff removed)\n"); fail(); }
    if (rc == 2) { printf("FAIL: hart 0 mutex retry budget exhausted\n"); fail(); }

    /* Gather: every tile must report in (a livelocked tile never does). */
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
