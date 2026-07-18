# VestaRV course SDK

Student-facing SDK + labs for the **Argus course chip** (`config/argus_course.json`
= the 18-hart Argus configuration with the NPU restored). Students write C, build
a flash image with `course.mk`, and run on physical chips; instructors validate
firmware in simulation with `sdk/run_sim.sh`.

## Layout

```
software/course/
  sdk/
    generated/        snapshots of the chip-generator output (see PROVENANCE.md)
      MemoryMap.h  periph.S  memory.x  periph.x  ChipConfig.resolved.json
      bits.h  custom_ops.S            (deps of MemoryMap.h; travel with it)
    course_lib/
      course.h        student API: console_init, printf, puts, pass, fail,
                      read_mhartid, uart_putc/uart_puts
      chip.h          C-includable register map (addresses + MMR macros)
      irq.h           interrupt API: irq_on_timer/soft/external, irq_return,
                      CLINT/IRQ-ROUTER register + source-id macros (lab08)
      mp.h            multi-core layer: mp_stage_image/mp_launch_hart/mp_msip +
                      the tile crt0 shim; a lab defines mp_tile_main (lab09/10)
      course.c        console + tiny printf + pass/fail + IRQ trampolines
    crt0.S            runtime entry (IVT, sp, bss zero, call main)
    course.ld         linker script (IVT @0x8000, _start @0x8200, stack 0xBFF0)
    course.mk         include-style build template (ELF->bin->rcf->flash headers)
    run_sim.sh        INSTRUCTOR simulator wrapper (one image, course config)
  labs/
    lab01_hello/        M1: console bring-up + printf demo
    lab02_assembly/     M2: RV32 assembly routines under a C harness
    lab03_c_baremetal/  M3: bare-metal MMIO UART + memory-map explorer
      skeleton/       student starting point (BUILDS, FAILS the check -- TODOs)
      reference/      completed solution   *** PRIVATE -- do not commit ***
```

## Building a lab

Each lab's `makefile` sets `TARGET` + `SRC_SOURCES` and includes `sdk/course.mk`:

```bash
cd software/course/labs/lab01_hello/skeleton
make            # -> rcf/xxxxxxx<target>.rcf  (SPI-flash image, 22-char name)
make sim        # instructor: build + run in the course-config simulator
make deploy     # hardware platform TBD (students flash the SPI boot flash)
make clean
```

Toolchain: `riscv-none-elf-` on PATH, `-march=rv32ima -mabi=ilp32`.

## The pass/fail contract

`pass()` / `fail()` write `0xCAFEBABE` / `0xDEADBEEF` to `a0` and spin. In
simulation `riscv_tb` latches hart 0's `a0` (PASS/FAIL); on silicon they are a
distinctive marker + halt. A single-hart lab leaves the other 17 tiles parked
(the tb reports them "silent/parked" -- expected).

## `lab01_hello`

`skeleton/` prints a banner + `mhartid`, then calls `fail()` at the TODO -- it
**builds but FAILS** as shipped (the negative control). Completing the TODOs
(print a line, swap `fail()` for `pass()`) makes it PASS. `reference/` is the
finished solution and PASSES.

> **`reference/` is PRIVATE -- do not commit.** It moves to the course's private
> repo before any vestarv commit. Only `skeleton/` ships publicly.

Instructor sim (both ~8 s wall):

```
reference: run_sim: PASS (a0=0xCAFEBABE)   -- console prints the full banner + printf demo
skeleton : run_sim: FAIL (a0=0xDEADBEEF)   -- console prints the banner, then fail()
```

## `lab02_assembly`

Pure-assembly lab (module M2). A fixed C harness (`src/main.c`) calls three
routines the student implements in RV32 assembly (`src/routines.S`) and checks
each result against a known answer over the UART0 console:

- `unsigned my_strlen(const char *s)` -- byte length of a NUL-terminated string
- `int my_array_max(const int *a, unsigned n)` -- max of `n` signed ints
- `unsigned my_bit_reverse(unsigned x)` -- 32-bit reversal (no bit-manip ISA)

`skeleton/routines.S` returns 0 from every routine, so it **builds but FAILS**
(the negative control); `reference/routines.S` completes them and PASSES. No
shared words, no interrupts, TCM only. (The harness deliberately uses only the
tiny printf subset -- `%s %d %u %x` with no width/flags.)

Instructor sim (both ~14 s wall):

```
reference: run_sim: PASS (a0=0xCAFEBABE)   -- per-check report, ALL CHECKS PASSED
skeleton : run_sim: FAIL (a0=0xDEADBEEF)   -- MISMATCH lines, SOME CHECKS FAILED
```

## `lab03_c_baremetal`

Bare-metal C + MMIO lab (module M3). The student writes UART0 bring-up and byte
TX **at the register level** (`uart_init`, `put_char` polling the TCIF flag) plus
a `load_word` memory-map explorer primitive -- the SDK console API
(`console_init`/`uart_putc`/`printf`) is off-limits here; only `pass()`/`fail()`
are used. The explorer prints the ROM/TCM boundary words and the pass gate is an
XOR signature over four `.rodata` marker words read back through `load_word`.

`skeleton/` leaves the three primitives as TODO stubs (`load_word` returns 0,
`put_char` empty), so it **builds but FAILS** with no console output; `reference/`
completes them, PASSES, and prints the full bare-MMIO table. Teachable MMIO
gotchas baked into the handout: write `SYS_CLK_CR = 0` first (bootrom parks SMCLK
on the 32 kHz LFXT) and use 32-bit accesses (word-oriented peripheral bus). No
shared words, no interrupts, TCM only.

Instructor sim (reference ~10 s, skeleton ~5 s wall):

```
reference: run_sim: PASS (a0=0xCAFEBABE)   -- banner, memory-map probe, 4 markers ok, PASS
skeleton : run_sim: FAIL (a0=0xDEADBEEF)   -- no output (put_char empty), fail()
```

> **Every `reference/` is PRIVATE -- do not commit.** They move to the course's
> private repo before any vestarv commit. Only `skeleton/` ships publicly.

## `lab04_gpio`

Register-level **GPIO** lab (module M4). The student drives GPIO1 the same way
lab03 drove UART0 -- at the register level -- with three primitives:
`gpio_set_dir` (pin direction via `PxDIR`), `gpio_drive` (output through the
set/clear/toggle convenience registers `PxOUTS`/`PxOUTC`/`PxOUTT`, read back on
`PxOUT`), and `gpio_pin_to_af` (re-route a pin from ordinary GPIO to a peripheral
alternate function through the pin-mux registers `PxSEL`/`PxAFS`). A provided
harness runs three self-checks -- directions, output set/clear/toggle, and the
`PxSEL`/`PxAFS` pinmux flip -- each reading back through GPIO1's own registers.

`skeleton/` leaves the three primitives empty, so every register readback
mismatches and it **builds but FAILS** (`run_sim: FAIL`, a0=0xDEADBEEF) with
`[FAIL]` lines on the console -- the negative control; `reference/` completes them
and PASSES (`run_sim: PASS`, a0=0xCAFEBABE), printing `[ ok ]` per check and
`ALL CHECKS PASSED`. Every check is self-contained (no external pin loopback). No
shared words, no interrupts -- TCM only.

```
reference: run_sim: PASS (a0=0xCAFEBABE)   -- three GPIO checks [ ok ], ALL CHECKS PASSED
skeleton : run_sim: FAIL (a0=0xDEADBEEF)   -- register readbacks mismatch, [FAIL] lines
```

## `lab05_uart`

Register-level **UART1 driver** lab (module M5). Having used UART0 as the console
since lab01, the student now writes a *second* UART driver -- for UART1 --
entirely from the registers: `uart1_init` (clock source, baud divisor, enable)
and `uart1_putc`, a byte transmit that follows the correct transmit-complete
status-flag discipline. A provided self-check transmits a known string over UART1,
polling its `TCIF` flag 0 -> 1 -> 0 for every byte with bounded polls, and reports
`bytes transmitted OK: N of N`. Teachable SMCLK gotcha baked in: `uart1_init`
writes `SYS_CLK_CR = 0` **first** (the bootrom parks SMCLK on the 32 kHz LFXT, so
without it every frame takes ~10 ms and the bounded polls expire).

`skeleton/` leaves `uart1_init` empty (UART1 stays disabled) and `uart1_putc`
returning 0, so the first byte times out and it **builds but FAILS**
(`run_sim: FAIL`, a0=0xDEADBEEF) -- the console still shows the trace and the
timeout line, the negative control; `reference/` completes both and PASSES
(`run_sim: PASS`, a0=0xCAFEBABE). No shared words, no interrupts -- TCM only.

```
reference: run_sim: PASS (a0=0xCAFEBABE)   -- config + pre-TX trace, bytes transmitted OK: N of N, PASS
skeleton : run_sim: FAIL (a0=0xDEADBEEF)   -- UART1 disabled, first byte times out, FAIL
```

> **Every `reference/` is PRIVATE -- do not commit.** They move to the course's
> private repo before any vestarv commit. Only `skeleton/` ships publicly.

## `lab07_timer`

Register-level **TIMER0** lab (module M6). The student writes `timer0_init`
(clock source + divider + a PWM-style compare pattern: CMP0 = duty, CMP2 = period
with auto-reset) and `timer0_wait_counting`, then a provided harness reads the
timer back through its own registers -- the count (`TIM0VAL`), the compare flag
(`CMP0IF`), and the PWM output level (`CMP0OUT`) -- with six bounded self-checks.
Two traps baked in and taught: **(a)** write `SYS_CLK_CR = 0` FIRST (SMCLK-domain
timer; the bootrom parks SMCLK on the 32 kHz LFXT) and **(b)** after enable
**poll** `TIM0VAL` until it is actually counting (the glitch-free clock mux needs
old-source edges to release) -- never assume, never compare two back-to-back VAL
samples right after enable.

`skeleton/` leaves both functions stubbed (timer stays disabled, never counts),
so it **builds but FAILS** (`2 of 6`, the negative control); `reference/`
completes them and PASSES (`6 of 6`). No shared words, no interrupts, TCM + the
shared TIMER0 registers only.

Instructor sim (reference ~16 s, skeleton ~19 s wall):

```
reference: run_sim: PASS (a0=0xCAFEBABE)   -- checks passed: 6 of 6, PASS
skeleton : run_sim: FAIL (a0=0xDEADBEEF)   -- TIM0VAL never advanced, 2 of 6
```

## `lab08_interrupts`

Interrupts in C on hart 0 (module M7), on the SDK's interrupt support
(`course_lib/irq.h`): register a plain C handler and the SDK's assembly
trampoline saves/restores all caller-saved context and issues the `retirq` for
you. Two paths:

- **Part A -- CLINT timer (mtip, IVT vector 84):** program `MTIMECMP[0]` ahead of
  the free-running `MTIME`; the handler counts each tick and re-arms (clearing
  the level) for a few ticks, then disables.
- **Part B -- routed peripheral (meip, IVT vector 85, claim/complete):** route
  TIMER0's compare-0 source (id 19) to hart 0's IRQ-router row and run TIMER0 as
  a periodic PWM with its compare interrupt enabled; the SDK meip trampoline
  CLAIMs (0x7800), calls the handler, then COMPLETEs. The handler clears the
  peripheral LEVEL (`CMP0IF`) before returning.

The console prints the ISR entry counts for BOTH paths as the pass evidence.
`skeleton/` leaves the four functions stubbed (nothing armed -> both counts stay
0), so it **builds but FAILS** (`0`/`0`, the negative control); `reference/`
PASSES with nonzero counts on both paths. No shared words, hart-0 only.

Instructor sim (both ~12 s wall):

```
reference: run_sim: PASS (a0=0xCAFEBABE)   -- mtip entries = 5, meip entries = 5, PASS
skeleton : run_sim: FAIL (a0=0xDEADBEEF)   -- mtip entries = 0, meip entries = 0, FAIL
```

> **Every `reference/` is PRIVATE -- do not commit.** They move to the course's
> private repo before any vestarv commit. Only `skeleton/` ships publicly.

## `lab09_multicore_boot`

Multi-core bring-up (module M8, TRM ch. 4.3), on the SDK's new multi-core layer
(`course_lib/mp.h`). Hart 0 stages its TCM image into shared RAM and launches a
modest subset of tile harts (harts 1..`NTILES`, `NTILES = 5` by default -- a
`#define`; the handout discusses all 17) through the M12 bootrom loader:
`mp_stage_image` snapshots the image to `0x18000`, `mp_launch_hart(h)` writes the
loader row {SRC,LEN,ENTRY} then sets `msip[h]`. The bootrom copies the image into
tile `h`'s TCM and enters the SDK tile shim, which calls the lab's
`mp_tile_main(hartid)`. Each tile writes a DONE word; hart 0 gathers with bounded
waits, checks each tile's `msip` self-cleared, and prints a per-hart status line.

`skeleton/` leaves `mp_tile_main` empty and the launch/gather loop stubbed
(no tile launched -> every DONE stays 0), so it **builds but FAILS**; `reference/`
PASSES with all tiles reporting. Course-band words: `DONE[h]=0x102A0+4*h`.

Instructor sim: reference ~21 s (5 tiles), skeleton ~10 s.

```
reference: run_sim: PASS   -- hart 1..5: DONE=0xd09e000h, msip cleared -- OK; PASS
skeleton : run_sim: FAIL   -- hart 1..5: FAIL (no DONE; got 0x0); FAIL
```

## `lab10_sync`

Synchronization (module M9, TRM ch. 4.4 / 7.9 / 20) -- the flagship multi-core
lab. Six harts (hart 0 + tiles 1..5) each do 32 non-atomic RMW increments of a
shared counter, under **(a)** an LR/SC spinlock with hartid-scaled backoff and
**(b)** the HW mutex bank. Correct mutual exclusion -> each counter ends EXACTLY
`NTOTAL*SECTIONS` = 192. The student implements four lock primitives
(`spin_acquire`/`spin_release`, `mtx_acquire`/`mtx_release`).

Three builds:
- `reference/` -- complete; PASSES with exact 192/192.
- `skeleton/` -- the four primitives stubbed ("succeed" without excluding
  anyone) -> updates lost -> **FAILS** with a low count (measured 118/192).
- `nobackoff/` -- builds the reference source with `-DNO_BACKOFF` (removes ONLY
  the Phase-1 LR/SC backoff). Intended as the sim-gated livelock negative control.

Course-band words (isolation -> may reuse other labs' band; itemized below):
`SLOCK=0x102C0 SCTR=0x102C4 SOWNER=0x102C8 MCTR=0x102CC MOWNER=0x102D0
DONE[h]=0x102E0+4*h`. HW mutex = `MUTEX0 @0x6000`.

Instructor sim: reference ~16 s (192/192, PASS), skeleton ~13 s (118/192, FAIL).

> **FINDING -- the `nobackoff` negative control does NOT livelock in the
> behavioral course simulator (it PASSES, 192/192).** The disassembly confirms a
> genuine tight LR/SC spinlock with the backoff removed, and the `skeleton`
> losing updates (118/192) proves the six harts really do contend concurrently.
> A follow-up experiment that added a HW-mutex barrier to force all six harts
> into the spinlock in perfect lockstep STILL reached exactly 192 -- no livelock,
> no lost updates. The behavioral core's LR/SC reservation + fair round-robin
> arbiter make forward progress without backoff; the starvation-livelock that
> CLAUDE.md/`shspin.S` document is a gate-level/silicon timing property this
> cycle-approximate behavioral model does not reproduce. Per the WP brief this
> was NOT tuned into failing artificially. Consequence: `nobackoff` currently
> PASSES rather than FAILing by retry exhaustion -- reported to the orchestrator.
> `reference/` and `skeleton/` meet their PASS/FAIL gates.

## `lab11_npu`

The NPU (module M11, TRM ch. 16), hart-0 only. A fixed-point multiply-accumulate:
stage a 2-element input vector (`X = Q0.24`) and weight vector (`W = Q7.24`) into
the NPU staging RAM at `0xC000`, point `IVSAR/WVSAR/OVSAR` (WORD indices) at them,
run a THINK (`NPUCR = THINK | NI(2) | NN(1)`), poll `NPUCR` bit 16 back to 0, and
check the output against a host-precomputed constant. The student implements
`npu_configure` + `npu_think`.

`OUT = X0*W0 + X1*W1 = 0.5*2.0 + 0.25*3.0 = 1.75 = 0x01C00000` (all expected
values are compile-time constants -- no `/` or `%` on variables, per the divider
erratum). `skeleton/` stubs the two functions (NPU never started -> output slot
stays 0), so it **builds but FAILS**; `reference/` PASSES. No shared course-band
words (the staging RAM at `0xC000` is not the course band). Never touch
`0xC000-0xFFFF` while THINK may be active (poll bit 16 first).

Instructor sim: reference ~9 s (`OUT=0x1c00000`, PASS), skeleton ~9 s
(`OUT=0x0`, FAIL).

> **Every `reference/` (and lab10 `nobackoff/`) is PRIVATE -- do not commit.**
> They move to the course's private repo before any vestarv commit. Only
> `skeleton/` ships publicly.

> **SDK interrupt extension (backward compatible).** `course_lib/irq.h` +
> additions to `course.c` add the interrupt API used by lab08; `crt0.S`,
> `course.ld`, and `course.mk` are unchanged. The IVT in `crt0.S` stays all
> zeros -- `irq_on_*` arm the three used slots (83/84/85) at runtime in TCM, and
> `--gc-sections` drops the trampolines + registration from labs that install no
> handler, so lab01-lab05 are unaffected (still build byte-for-byte the same way).
> Neither lab07 nor lab08 needs any shared RAM word (hart-0 only). The
> multi-core labs (lab09/lab10) are the first users of the course band -- see
> the ledger below.

## Known issues (chip / toolchain findings)

These are **pre-existing** issues uncovered while building the SDK. They are NOT
fixed here (the chip generator / RTL are out of this SDK's scope) -- the SDK
works around them and they are reported to the chip team.

1. **Hardware divide (`divu`/`remu`) result hazard.** The M-extension divide
   unit returns wrong results (often `0`/stale) when the quotient is consumed
   too soon after the instruction -- e.g. direct `divu 42,10 -> 4` but a
   following `remu 42,10 -> 0` and `divu 100,7 -> 0`. GCC's magic-multiply
   lowering of *constant* division (at `-O2`) avoids the instruction and is
   correct; runtime `x / y` still emits `divu` and is unreliable. Consequences
   for the SDK:
   - `course.mk` builds at **`-O2`** (not `-Os`), and printf's integer
     conversion is written **divu/remu-free** (explicit reciprocal multiply for
     `/10`, shifts for hex). Do not lower this to `-O0`/`-Os` without
     re-checking `objdump -d | grep -E 'divu|remu'` is empty.
   - **Student guidance:** avoid dividing/moduloing by a *runtime* value; divide
     by constants so the compiler uses the multiply path. (The smoke suite does
     not exercise `divu` -- it is not in the smoke tag set -- so `make verify`
     stays green despite this.)

2. **Generated `MemoryMap.h` does not compile as a C include.** The chip
   generator emits every padding member of the absolute-base peripheral structs
   (`CLINT_t` / `MUTEX_t` / `IRQROUTER_t`) named `__unused0`, which C rejects as
   duplicate struct members. This affects the N=4 Castalia header too (it is not
   N=18/NPU-specific). The faithful header still ships in `sdk/generated/` for
   reference; the SDK builds against the small hand-curated `sdk/course_lib/chip.h`
   (addresses + access macros) until the generator numbers padding members
   uniquely.

3. **Word-oriented peripheral bus.** UART registers must be accessed 32-bit
   (`lw`/`sw`, as in shuart.S); byte (`lbu`) reads of the status register return
   garbage. `course.c` uses 32-bit accesses throughout.

## Course shared-RAM band ledger (`0x102A0`-`0x1037F`)

The course labs claim shared words ONLY inside the reserved **course band
`0x102A0`-`0x1037F`** (56 words) recorded in the CLAUDE.md shared-window ledger:
it sits between shlock `DONE[17]=0x10294` (N=18) and shmutex `CTR=0x10380`, and
both ends are `< 0x10500` (loader rows) and inside the bootrom-zeroed range
(`< 0x10800`), so a counter/DONE word that starts at 0 is genuinely zero on
entry (write-before-read). Course labs run in ISOLATION (one image per sim,
never alongside the sh-tests or each other), so labs may reuse the same
addresses; the words each lab actually uses are itemized here:

| Lab                    | Word     | Address   | Meaning                                  |
|------------------------|----------|-----------|------------------------------------------|
| lab09_multicore_boot   | DONE[h]  | 0x102A0+4h| tile h reported-in (h = 1..NTILES)       |
| lab10_sync             | SLOCK    | 0x102C0   | LR/SC spinlock word (0 free, 1 held)     |
| lab10_sync             | SCTR     | 0x102C4   | spinlock-protected counter               |
| lab10_sync             | SOWNER   | 0x102C8   | spinlock owner marker (teaching)         |
| lab10_sync             | MCTR     | 0x102CC   | HW-mutex-protected counter               |
| lab10_sync             | MOWNER   | 0x102D0   | mutex owner marker (teaching)            |
| lab10_sync             | DONE[h]  | 0x102E0+4h| tile h reported-in (h = 1..NTILES)       |
| lab11_npu              | (none)   | --        | hart-0 only; NPU staging RAM 0xC000 is not the band |

Highest course-band word in use: `lab10 DONE[5] = 0x102F4` (`< 0x1037F`).
lab09's tile hammer and lab10's counters live below `0x102F8`; the rest of the
band (`0x102F8`-`0x1037F`) is free for future labs. The HW mutex bank
(`MUTEX0 @0x6000`) and the NPU staging RAM (`0xC000`) are chip resources, not
band words -- never LR/SC or AMO a mutex-bank address (the claim-read side
effect fires).

(The brief's suggested `0x10280` start nominally overlaps shlock `DONE[12..17]`
at N=18 -- benign under isolation, but the band above starts at `0x102A0` to be
strictly clear.)
