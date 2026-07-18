# lab07_timer -- REFERENCE SOLUTION

**PRIVATE -- do not commit.** This completed solution moves to the course's
private repo before any vestarv commit. Only `../skeleton/` ships publicly.

Build/run: `make sim` (instructor). Expected: `run_sim: PASS (a0=0xCAFEBABE)`.
The UART0 console (SDK) prints the trace: the config line, then one `[ok]` line
per check, then `checks passed: 6 of 6` and `PASS`. TIMER0 is driven purely at
the register level (TRM ch. 14): clock source + divider, a PWM-style compare
pattern (CMP0 = duty, CMP2 = period with auto-reset), read back through TIM0VAL,
the CMP0IF flag, and the CMP0OUT PWM output level. No interrupts, no external
wire, no shared words -- TCM + the shared TIMER0 registers only.

Two teachable traps baked in:
- **(a) Clock first.** `timer0_init` writes `SYS_CLK_CR = 0` FIRST (SMCLK -> HFXT).
  The bootrom parks SMCLK on the 32 kHz LFXT; without this the timer counts
  ~750x too slowly and the bounded compare/period polls time out (TRM 14, 15.1).
- **(b) Poll until counting.** The timer's glitch-free clock mux defaults to the
  smclk slice and needs old-source edges to release. `timer0_wait_counting`
  samples VAL once then polls a FRESH read until it advances -- it never assumes
  the timer is counting and never compares two back-to-back samples taken right
  after enable (both can read the pre-handoff value).

The shipped skeleton leaves `timer0_init` empty (TIMER0 stays disabled) and
`timer0_wait_counting` returning 0, so the "counting" check times out and it
FAILS (`run_sim: FAIL`, a0=0xDEADBEEF) -- the console still shows the trace and
which checks fail (the negative control).
