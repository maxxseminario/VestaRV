/* VestaRV port of CoreMark. Timer: mcycle, free-running on mclk. seed_* follow barebones/core_portme.c. */
#include "coremark.h"
#include "core_portme.h"

extern unsigned rd_mcycle(void);
extern unsigned rd_minstret(void);
extern void perf_report(unsigned tag, unsigned a, unsigned b);
extern void perf_stats_dump(void);

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

ee_u32 default_num_contexts = 1;

static CORE_TICKS start_c, stop_c;
static unsigned start_i, stop_i;

void start_time(void)
{
#ifdef CPI_TB   /* run_flat.py: the one-cycle-memory harness's kernel-window port */
    *(volatile unsigned *)0x00004000u = 1u;
#else
    perf_stats_dump();
#endif
    start_i = rd_minstret();
    start_c = rd_mcycle();
}

void stop_time(void)
{
    stop_c = rd_mcycle();
    stop_i = rd_minstret();
#ifdef CPI_TB
    *(volatile unsigned *)0x00004000u = 2u;
#else
    perf_stats_dump();
    perf_report(0xC0DE, stop_c - start_c, stop_i - start_i);
#endif
}

CORE_TICKS get_time(void) { return stop_c - start_c; }

secs_ret time_in_secs(CORE_TICKS ticks) { return ticks / EE_TICKS_PER_SEC; }

void portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc; (void)argv;
    p->portable_id = 1;
}

void portable_fini(core_portable *p)
{
    p->portable_id = 0;
#ifdef STACK_FILL
    /* crt_mp.S painted [__tcm_end, sp-64); the first overwritten word bounds the stack's reach. */
    extern unsigned __tcm_end[];
    unsigned *q = __tcm_end;
    while (*q == 0x5AFE5AFEu) q++;
    perf_report(0x57AC, (unsigned)q, (unsigned)__tcm_end);
#endif
}
