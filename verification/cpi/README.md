# verification/cpi — CPI measurement harness

Measures the `vesta` core's cycles per instruction on the RTL under GHDL and gates
each image's counters against `expected.json`. The results populate the TRM's CPI
chapter (`\label{s:cpi}` in `platform/common/latex/TRM.template.tex`): tables
`t:cpi-timing` (micro-kernels), `t:cpi-align` (RV32IMAC vs RV32IMA `_noc` twins) and
`t:cpi-bench` (benchmarks).

## Targets

```sh
tools/bin/bazel test //verification/cpi/...        # default set, fast
tools/bin/bazel test //verification/cpi:cpi_full   # adds the long benchmarks (minutes)
```

| Target | Set | Coverage |
|---|---|---|
| `:micro` | default | all 40 micro-kernels |
| `:median`, `:towers`, `:vvadd` (+ `_noc`) | default | short benchmarks, RV32IMAC and RV32IMA |
| `:derived_tables_test` | default | recomputes the three TRM tables from every recorded count, manual images included |
| `:cpi_default` | default | the above as one suite |
| `:dhrystone`, `:memcpy`, `:multiply`, `:qsort`, `:rsort`, `:spmv` (+ `_noc`, no `spmv_noc`) | manual | long benchmarks |
| `:cpi_full` | manual | everything |

All labels are in `//verification/cpi`. Images build on the pinned
`@xpack_riscv_gcc`; the simulator is `@ghdl//:ghdl`.

## Method

| File | Role |
|---|---|
| `vesta_cpi_tb.vhd` | `opensource_sim/isa/vesta_isa_tb.vhd` plus a cycle counter (free-running `clk`, so gated stalls count) and a retired-instruction counter (`dut.inst_retired`, i.e. `minstret`) |
| `gen_micro.py` | per-class kernel pairs: 64 copies vs none; the difference is the marginal cost |
| `bmark_stubs.c`, `crt_bmark.S`, `link_bmark.ld` | bare-hart runtime; `setStats()` stores to `0x00004000` (1 opens, 2 closes the window), so only the benchmark kernel is timed |
| `expected.json` | recorded counters, asserted exactly |

## Rules

- `ENABLE_IF_AHEAD => true` in the testbench generic map mirrors the shipped
  `core.fetchAhead` setting by hand. Nothing checks it; a mismatch silently
  publishes CPI for a different core.
- Every micro-kernel loop body starts with `.p2align 2`. Removing it puts each 32-bit
  instruction on the split-fetch path and doubles its measured cost. Only
  `micro_straddleseq_*` and `micro_straddlebr_*` straddle, on purpose.
- The empty `.ivt` section in `crt_bmark.S` is required; without it the image loads
  `0x200` bytes low.
- A red target is either a regression (fix the RTL) or a deliberate core change:
  re-record `expected.json` and update the TRM tables in the same commit as the
  RTL. Failures print expected, measured and delta per counter; then rerun
  `:derived_tables_test`. A new image without an entry fails.

## Limits

Single hart, one-cycle memory, no bus back-pressure or arbiter contention; multi-hart
CPI is unmeasured. AMO timing is not measured here (the TRM cites 5 cycles). `mm` is
excluded (multicore `thread_entry`, no `main()`).
