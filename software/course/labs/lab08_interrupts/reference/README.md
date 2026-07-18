# lab08_interrupts -- REFERENCE SOLUTION

**PRIVATE -- do not commit.** This completed solution moves to the course's
private repo before any vestarv commit. Only `../skeleton/` ships publicly.

Build/run: `make sim` (instructor). Expected: `run_sim: PASS (a0=0xCAFEBABE)`.
The UART0 console (SDK) prints the ISR entry counts for BOTH interrupt paths as
the pass evidence:

```
lab08_interrupts: CLINT timer (mtip) + routed TIMER0 (meip)
part A: mtip ISR entries = 5 (want 5)
part B: meip ISR entries = 5 (want 5)
PASS
```

Two interrupts, in C, on hart 0 (TRM ch. 6 / 19 / 21), on the course SDK's
interrupt support (`sdk/course_lib/irq.h`):
- **Part A -- CLINT timer (mtip, vector 84):** `arm_timer_tick` programs
  `MTIMECMP[0]` ahead of `MTIME` (lo first, then hi=0); `timer_isr` counts each
  tick and re-arms (clearing the level), then disables after 5.
- **Part B -- routed peripheral (meip, vector 85, claim/complete):**
  `setup_ext_timer` writes `SYS_CLK_CR = 0` first, routes TIMER0 compare-0
  (source id 19) to hart 0's router row, and runs TIMER0 as a periodic PWM with
  `CMP0IE`; the SDK meip trampoline CLAIMs (0x7800), calls `ext_isr(19)`, then
  COMPLETEs. `ext_isr` clears the peripheral LEVEL (`CMP0IF`) before returning,
  and stops the timer after 5.

The shipped skeleton leaves all four functions empty (nothing armed -> both
counts stay 0), so it FAILS (`run_sim: FAIL`, a0=0xDEADBEEF) with the two
`ISR entries = 0` lines (the negative control). No shared words, hart-0 only.
