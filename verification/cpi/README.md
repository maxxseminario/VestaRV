# CPI measurement harness

This package measures the VestaRV core's cycles-per-instruction on the RTL and
gates the result against recorded values. The numbers it produces are the ones
published in **TRM Section 12, "Core Performance and Instruction Timing"**
(`\label{s:cpi}` in `platform/common/latex/TRM.template.tex`), which covers:

| TRM table | What it holds | Produced here by |
| --- | --- | --- |
| `t:cpi-timing` | cycle cost per instruction class | the `micro_*` kernel pairs |
| `t:cpi-align`  | RV32IMAC versus RV32IMA, the straddling-fetch cost that remains with the fetch-ahead on | each benchmark and its `_noc` twin |
| `t:cpi-bench`  | CPI per benchmark, timed kernel | the nine benchmark images |

If you change either side, change both: the TRM section and `expected.json`
belong in the same commit.

## What is measured, and how

`vesta_cpi_tb.vhd` is `opensource_sim/isa/vesta_isa_tb.vhd` with two counters
added. It keeps that harness's bus contract exactly, which is what makes the
result a property of the core rather than of a new memory model:

* a flat RAM at `0x8000`, `mem_ready` tied high, one cycle of read latency,
  `wen` active LOW per lane;
* the same extension switches, so CPI is measured on the same core
  configuration the ISA regression proves.

One generic does **not** come from that harness. `ENABLE_IF_AHEAD => true` is
set from what Castalia **ships**: the `core.fetchAhead` knob reaches the chip
as `CORE_ENABLE_IF_AHEAD` in `MemoryMap.vhd` and through `MCU.vhd`, and this
bench instantiates `work.vesta` directly, so it inherits none of that and the
entity default is `false`. **That generic map has to be kept in step with the
shipped configuration by hand.** Nothing checks it, and getting it wrong does
not fail: it silently publishes CPI for a core that is not the one being
taped out.

Two things are deliberate:

* **Cycles are counted on the free-running `clk`, not on the gated `clk_cpu`.**
  A cycle the core spends stalled with its clock gated is still charged to CPI.
* **Instructions are counted from `dut.inst_retired`,** reached by a VHDL-2008
  external name so no RTL port is added. That signal is the exact predicate
  `csr_unit` increments `minstret` on, so the instruction count is
  architectural and equals what a `rdinstret` would read.

A store to `0x00004000` is decoded as the kernel-window marker: value 1 opens
the window, value 2 closes it. `bmark_stubs.c` defines `setStats()` as that
store, which turns the benchmarks' OWN existing `setStats(1)`/`setStats(0)`
calls into the measurement window with **no edit to any benchmark source**.
The kernel window is what the TRM reports, so startup, the `PREALLOCATE`
warm-up pass and result verification are all excluded.

### Micro-kernels

`gen_micro.py` emits one pair of kernels per instruction class: a loop with 64
copies of the instruction under test, and an otherwise identical loop with
none. Subtracting removes the loop's own decrement and backward branch, so
delta-cycles over delta-instructions is the marginal cost of that class alone.

**Every loop body starts with `.p2align 2`, and that is not cosmetic.** The
core fetches one 32-bit word per bus cycle, so a 32-bit instruction that
straddles a word boundary takes the split-fetch path at one extra cycle. An
unaligned body puts *every* 32-bit instruction in it on that path and silently
doubles the measured cost of whatever is under test: the first cut of the
control-transfer kernels read 2.0 cycles for a taken branch entirely because
of this. The straddling-fetch cost is measured separately, by the
RV32IMAC/RV32IMA benchmark pairs and by the two kernels below, and must never
be charged to an instruction class here. Do not remove the directive.

`micro_straddleseq_*` and `micro_straddlebr_*` are the two kernels that
straddle **on purpose**, and the only ones. Castalia ships `ENABLE_IF_AHEAD`
on, so the straddling penalty is no longer a single number: a straddling
32-bit instruction reached by a sequential advance is absorbed by the
fetch-ahead, while one reached by a taken branch or jump is not, because the
fetch-ahead arms only on a sequential advance and a redirect leaves the core
holding nothing. `straddleseq` is a 12-byte block of four instructions, two of
them straddling 32-bit ones, all reached sequentially; it measures 1.000
cycles per instruction, so those straddles are free. `straddlebr` is a taken
`beq` over a compressed instruction onto a straddling `add`, plus a compressed
pad to return the next block to a word boundary; its three instructions each
cost one cycle on their own (`brtaken`, `alu32`, `alu16`), and the block
measures 4 cycles, so the redirect into a straddling target costs +1. Those
two measurements are the two straddling rows of TRM Table `t:cpi-timing`.

`micro_alu32lin_16` and `micro_alu32lin_32` are the linearity control: the same
one-cycle body at two lengths, whose difference must be exactly
`(32 - 16) * ITERS` cycles. It is what proves the residual left in a 64/0 pair
is per-iteration loop overhead rather than a per-op cost the subtraction
failed to remove.

### Benchmarks

Nine benchmarks from `verification/benchmarks/`, compiled `-O2` for
`rv32imac_zicsr_zba_zbb_zbc_zbs` against this package's own `crt_bmark.S`,
`bmark_stubs.c` and `link_bmark.ld`. `mm` is absent on purpose: it has no
`main()`, it is a multicore `thread_entry` benchmark and there is nothing for
one bare hart to run.

The `_noc` images are the same sources at `rv32ima_zicsr_zba_zbb_zbc_zbs`. gcc
emits the identical instruction sequence in both builds, so the retired-
instruction counts match benchmark for benchmark and the entire cycle
difference is the straddling-fetch penalty --- with `ENABLE_IF_AHEAD` shipped,
specifically the part of it the fetch-ahead does not absorb. `spmv` has no `_noc` twin, which is
why TRM Table `t:cpi-align` aggregates eight benchmarks and Table
`t:cpi-bench` aggregates nine.

One trap worth knowing about `crt_bmark.S`: the empty `.ivt` section is load
bearing. Without an allocated section at `0x8000`, `objcopy -O binary` starts
the file at `.text.init` and the whole image loads `0x200` bytes low.

## Hermeticity

Images are built by bazel genrules on the pinned `@xpack_riscv_gcc` 13.2.0-2
toolchain, never from a host toolchain: the `-march`, `-mabi`, option list and
linker script are all arguments of the compile action, so they are part of the
action key. The simulator is `@ghdl//:ghdl` with `@ghdl//:vhdl_libs_v08`, the
same as `//opensource_sim/isa`, and the RTL comes from `//hdl:vhdl_sources`
through a `vhdl_source_set` in the analysis order
`//opensource_sim/isa:defs.bzl` publishes. The host contributes bash,
coreutils and the bazel Python interpreter.

## Targets

Default coverage, run by `bazel test //verification/cpi/...` and therefore by
`bazel test //...`:

| Target | Coverage |
| --- | --- |
| `//verification/cpi:micro` | all 40 micro-kernels, the whole per-class table |
| `//verification/cpi:median`, `:towers`, `:vvadd` | the three short benchmarks, RV32IMAC |
| `//verification/cpi:median_noc`, `:towers_noc`, `:vvadd_noc` | the same three, RV32IMA |
| `//verification/cpi:derived_tables_test` | the three TRM tables, recomputed from the recorded counts |
| `//verification/cpi:cpi_default` | all of the above as one suite |

Opt-in coverage, `tags = ["manual"]` and `size = "enormous"`:

| Target | Coverage |
| --- | --- |
| `//verification/cpi:dhrystone`, `:memcpy`, `:multiply`, `:qsort`, `:rsort`, `:spmv` | the six long benchmarks, RV32IMAC |
| `//verification/cpi:dhrystone_noc`, `:memcpy_noc`, `:multiply_noc`, `:qsort_noc`, `:rsort_noc` | the same, less spmv, at RV32IMA |
| `//verification/cpi:cpi_full` | everything, default and manual |

```sh
tools/bin/bazel test //verification/cpi/...        # default set, fast
tools/bin/bazel test //verification/cpi:cpi_full   # everything, minutes
```

The split is about runtime, not coverage. `spmv` alone is about 2.3M simulated
cycles and GHDL's mcode backend runs at roughly 40k cycles a second, so the
long benchmarks would add minutes to every `bazel test //...`. Nothing is
dropped: every image in `expected.json` has a target, `cpi_full` runs all of
them, and `derived_tables_test` -- which is in the default set -- recomputes
the published tables from the recorded counts of **every** image, manual ones
included. So a hand edit to `expected.json` that no longer adds up is caught
by the default set even though the simulation that would confirm it is opt-in.

## expected.json, and what re-recording means

`expected.json` is a tracked recorded-value gate, the same idiom as
`tools/randgen/campaign/campaign.json`. Each image's four counters are
asserted **exactly**, not within a tolerance: the simulation is deterministic,
so any difference is a real change in what the core does and a tolerance would
only hide small ones.

A red target here is one of two things:

1. **A regression.** Some change made the core slower (or faster) without
   anyone intending it. Fix the RTL.
2. **A deliberate core change.** Then re-record `expected.json` **in the same
   commit as the RTL change**, and update the affected tables of TRM
   Section 12 in that same commit. That is the whole discipline: the counts,
   the RTL and the document move together, so a CPI change is always visible
   in the diff and never drifts silently.

To re-record, build the images, run each under the testbench and transcribe
the `CPIRESULT` lines:

```sh
tools/bin/bazel build //verification/cpi:all
tools/bin/bazel test //verification/cpi:cpi_full   # read the reported deltas
```

Each failure prints `expected`, `measured` and the signed delta on every
counter, plus the kernel CPI both ways, which is enough to fill in the new
values by hand. Then re-run `:derived_tables_test`, which will reject a
`benchmark_cpi` or `straddling_fetch` entry that no longer follows from the
raw counts.

Adding a new image is the same motion: a name with no `expected.json` entry
fails loudly rather than passing vacuously.

## Known limits

* Single hart, no arbiter contention. An access that crosses into the shared
  window costs more, and multi-hart CPI is unmeasured.
* AMO timing is not re-measured here; the bare-core bench has no second
  master, so the TRM cites the existing 5-cycle figure instead.
* The harness measures the core with a one-cycle-latency memory and no bus
  back-pressure, which is the timing a single hart sees executing from its own
  TCM. It is not a model of the full MCU memory system.
