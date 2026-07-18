# lab05_uart -- REFERENCE SOLUTION

**PRIVATE -- do not commit.** This completed solution moves to the course's
private repo before any vestarv commit. Only `../skeleton/` ships publicly.

Build/run: `make sim` (instructor). Expected: `run_sim: PASS (a0=0xCAFEBABE)`.
The UART0 console (SDK) prints the progress trace: the UART1 config line, the
pre-TX status, and `bytes transmitted OK: N of N`, then `PASS`. UART1 is the
device under test -- its TX-complete flag (TCIF) is polled 0 -> 1 -> 0 for every
byte of a known string, all with bounded polls. Nothing relies on an external
wire; TCIF is asserted by the UART1 core when each frame finishes.

Teachable SMCLK gotcha baked in: `uart1_init` writes `SYS_CLK_CR = 0` FIRST
(the bootrom parks SMCLK on the 32 kHz LFXT, so without it every frame takes
~10 ms and the polls expire).

The shipped skeleton leaves `uart1_init` empty (UART1 stays disabled) and
`uart1_putc` returning 0, so the first byte times out and it FAILS
(`run_sim: FAIL`, a0=0xDEADBEEF) -- the console still shows the trace and the
timeout line (the negative control). No shared words, no interrupts -- TCM only.
