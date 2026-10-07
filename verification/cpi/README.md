# verification/cpi — CPI measurement harness

Measures the `vesta` core's cycles per instruction under GHDL and gates each image's
counters exactly against `expected.json`. Results populate the TRM CPI chapter
(`\label{s:cpi}`, `platform/common/latex/TRM.template.tex`).

```sh
tools/bin/bazel test //verification/cpi/...        # default: micro-kernels + short benchmarks
tools/bin/bazel test //verification/cpi:cpi_full   # adds the long benchmarks (minutes)
```

| Target (`//verification/cpi`) | Coverage |
|---|---|
| `:micro` | 40 micro-kernels (per-class cost) |
| `:median`, `:towers`, `:vvadd` (+ `_noc`) | short benchmarks, RV32IMAC / RV32IMA |
| `:derived_tables_test` | recomputes the TRM tables from every recorded count |
| `:cpi_full` | everything, including manual `:dhrystone`, `:memcpy`, `:multiply`, `:qsort`, `:rsort`, `:spmv` |

- `ENABLE_IF_AHEAD => true` in `vesta_cpi_tb.vhd` mirrors the shipped `core.fetchAhead`
  by hand; nothing checks it, and a mismatch silently publishes CPI for another core.
- Keep `.p2align 2` on every loop body in `gen_micro.py`; without it 32-bit instructions
  straddle words and their cost doubles. Only `micro_straddle*` straddle on purpose.
- Keep the empty `.ivt` section in `crt_bmark.S`; without it the image loads `0x200` low.
- A deliberate core change re-records `expected.json` and the TRM tables in the same
  commit as the RTL; any other red target is a regression.
- Single hart, one-cycle memory, no contention; multi-hart and AMO timing are not measured.
