/* setStats() is dhrystone_main.c's own window hook: it brackets exactly the Number_Of_Runs loop. */
extern unsigned rd_mcycle(void);
extern unsigned rd_minstret(void);
extern void perf_report(unsigned tag, unsigned a, unsigned b);
extern void perf_stats_dump(void);

static unsigned c0, i0;

void setStats(int enable)
{
    if (enable) {
        perf_stats_dump();
        i0 = rd_minstret();
        c0 = rd_mcycle();
    } else {
        unsigned c1 = rd_mcycle(), i1 = rd_minstret();
        perf_stats_dump();
        perf_report(0xD401, c1 - c0, i1 - i0);
    }
}
