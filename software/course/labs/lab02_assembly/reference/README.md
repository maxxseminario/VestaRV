# lab02_assembly -- REFERENCE SOLUTION

**PRIVATE -- do not commit.** This completed solution moves to the course's
private repo before any vestarv commit. Only `../skeleton/` ships publicly.

Build/run: `make sim` (instructor). Expected: `run_sim: PASS (a0=0xCAFEBABE)`
with the per-check report (`strlen`, `array_max`, `bit_reverse` all `ok`) and
`ALL CHECKS PASSED` on the UART0 console.

The shipped skeleton returns 0 from every routine, so it builds but FAILS
(`run_sim: FAIL`, a0=0xDEADBEEF) -- the negative control.
