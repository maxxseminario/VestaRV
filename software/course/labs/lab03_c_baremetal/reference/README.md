# lab03_c_baremetal -- REFERENCE SOLUTION

**PRIVATE -- do not commit.** This completed solution moves to the course's
private repo before any vestarv commit. Only `../skeleton/` ships publicly.

Build/run: `make sim` (instructor). Expected: `run_sim: PASS (a0=0xCAFEBABE)`
with the bare-metal UART0 output -- a banner, the memory-map probe table
(ROM base/top, TCM base, a code word from main), the four marker reads (`ok`),
the signature line, and `PASS`.

The shipped skeleton leaves `uart_init`/`put_char` empty and `load_word`
returning 0, so it builds but FAILS (`run_sim: FAIL`, a0=0xDEADBEEF) with no
console output -- the negative control.
