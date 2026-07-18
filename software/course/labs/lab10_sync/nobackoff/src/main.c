/* lab10_sync -- NEGATIVE CONTROL (nobackoff).  PRIVATE -- do not commit.
 *
 * Builds the reference solution with -DNO_BACKOFF (set in this dir's makefile),
 * which removes ONLY the Phase-1 LR/SC spinlock backoff. Identical harts then
 * livelock on the spinlock: their bounded retry budgets exhaust and the run
 * FAILS by retry exhaustion with a distinct "LIVELOCK ..." console message.
 * A PASS here would contradict a documented chip property -- do NOT tune it. */
#include "../../reference/src/main.c"
