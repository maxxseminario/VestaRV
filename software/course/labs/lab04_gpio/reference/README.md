# lab04_gpio -- REFERENCE SOLUTION

**PRIVATE -- do not commit.** This completed solution moves to the course's
private repo before any vestarv commit. Only `../skeleton/` ships publicly.

Build/run: `make sim` (instructor). Expected: `run_sim: PASS (a0=0xCAFEBABE)`
with the UART0 console showing the three GPIO checks (directions, output
set/clear/toggle, PxSEL/PxAFS pinmux flip) each printing `[ ok ]` and
`ALL CHECKS PASSED`.

The shipped skeleton leaves `gpio_set_dir`, `gpio_drive`, and `gpio_pin_to_af`
empty, so the register readbacks mismatch and it FAILS (`run_sim: FAIL`,
a0=0xDEADBEEF) with `[FAIL]` lines on the console -- the negative control.

Every check is self-contained: it reads back what it wrote through GPIO1's own
registers (PxDIR/PxOUT/PxOUTS/PxOUTC/PxOUTT/PxSEL/PxAFS). No external pin
loopback, no shared words, no interrupts -- TCM only.
