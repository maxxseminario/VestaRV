# opensource_sim — open-source simulation of the `vesta` core

License-free functional verification of the bare `vesta` core under GHDL: the
riscv-tests-derived ISA suite (Bazel) and a cocotb smoke test. Synthesis to GDSII
is in [`sky130/`](../sky130/README.md).

```sh
sh tools/get_bazel.sh                                 # bazelisk -> tools/bin/bazel
tools/bin/bazel test //opensource_sim:isa_regression  # all nine suites, the CI gate
```

| Target | Purpose |
|---|---|
| `//opensource_sim:isa_rv32ui` | one suite; likewise `isa_rv32um`, `_rv32ua`, `_rv32uc`, `_rv32uzba`, `_rv32uzbb`, `_rv32uzbc`, `_rv32uzbs`, `_rv32uzf` |
| `//opensource_sim/isa:rv32ui-p-add` | a single image |
| `//opensource_sim/isa:source_list_sync_test` | RTL order matches `run_isa.sh`, `sky130/synth.sh`, `sky130/sim/Makefile` |

Tests write `a0`: `0xCAFEBABE` pass, `0xDEADBEEF` fail. Skips are listed with reasons
in the `SKIP` table of `isa/run_isa.sh`; a new failure goes there with a reason, never dropped.

Smoke test (outside Bazel; needs GHDL ≥ 5, e.g. Debian trixie / Ubuntu 24.04+):

```sh
./opensource_sim/setup_env.sh && source opensource_sim/env.sh
./opensource_sim/run_sim.sh --smoke-only        # --isa-only, or no flag for both
```

Rerun one test after any `run_isa.sh` run:

```sh
cd opensource_sim/isa
ghdl -r --std=08 -fsynopsys --workdir=work vesta_isa_tb \
    -gTEST_FILE=../../verification/isa/build/rv32ui/xxxxxxrv32ui-p-add.rcf
```

Hand-built images (`make -C verification/isa`) must use `CORE_ENABLE_DEFS` from
`run_isa.sh` and start from `rm -rf verification/isa/build`, or stale images are reused.
Full Bazel map: [`BAZEL.md`](../BAZEL.md).
