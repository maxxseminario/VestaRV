# opensource_sim — open-source simulation of the `vesta` core

License-free functional verification of the bare `vesta` core (RV32IMAC + Zb\*,
X-series Z-extensions, Zfinx FPU): GHDL simulator, a cocotb smoke test, and the
riscv-tests-derived ISA suite. Simulation only; [`sky130/`](../sky130/README.md)
takes the same RTL to GDSII.

## ISA regression (Bazel)

Hermetic: `@ghdl` is built from source and the RISC-V toolchain is pinned. Run
from the repo root.

```sh
sh tools/get_bazel.sh                              # bazelisk -> tools/bin/bazel
tools/bin/bazel test //opensource_sim:isa_regression
```

| Target | Verb | Purpose |
|---|---|---|
| `//opensource_sim:isa_regression` | test | all nine suites; the tier-2 CI gate (`.github/workflows/sim.yml`) |
| `//opensource_sim:isa_rv32ui` | test | one suite; likewise `isa_rv32um`, `_rv32ua`, `_rv32uc`, `_rv32uzba`, `_rv32uzbb`, `_rv32uzbc`, `_rv32uzbs`, `_rv32uzf` |
| `//opensource_sim/isa:rv32ui` | test | one target per rv32ui image |
| `//opensource_sim/isa:rv32ui-p-add` | test | a single image (debug loop) |
| `//opensource_sim/isa:source_list_sync_test` | test | curated RTL order matches `run_isa.sh`, `sky130/synth.sh`, `sky130/sim/Makefile` |
| `//verification/isa:os_rv32ui_rcfs` | build | ON-polarity images a suite consumes |
| `//toolchains/ghdl:ghdl` | build | the from-source GHDL |

Full map: [`BAZEL.md`](../BAZEL.md).

## Coverage and results

- Suites: `rv32ui`, `rv32um`, `rv32ua` (atomics plus X-series ext-probes), `rv32uc`,
  `rv32uzba/zbb/zbc/zbs`, `rv32uzf` (Zfinx). Sources: [`verification/isa`](../verification/isa/README.md).
- Each test writes `a0`: `0xCAFEBABE` pass, `0xDEADBEEF` fail. `run_isa.sh` prints one
  `PASS`/`FAIL`/`TIMEOUT`/`SKIP` line per test, then
  `ISA RESULTS: <npass>/<ntotal> passed (skipped: <nskip>)`.
- Skips, with reasons, live in the `SKIP` table of `isa/run_isa.sh`: MCU/multi-hart
  system tests, illegal-encoding "poison" probes, privileged/trap/debug suites, MCU
  peripheral exercisers, and the Zawrs/Zihpm probes. A new failure is triaged into
  that table with a reason, never dropped.

## cocotb smoke test (outside Bazel)

Runs the bare core through a 3-instruction program
([`sky130/sim/test_vesta_smoke.py`](../sky130/sim/test_vesta_smoke.py)). CI runs it as
the `sim-smoke` job of `.github/workflows/physical.yml`.

```sh
./opensource_sim/setup_env.sh && source opensource_sim/env.sh
./opensource_sim/run_sim.sh --smoke-only        # --isa-only, or no flag for both
gtkwave sky130/sim/vesta_smoke.vcd              # waveform
```

`setup_env.sh` installs GHDL/gcc/make, a cocotb venv, and an xPack
`riscv-none-elf-gcc` (x86_64/aarch64 only; elsewhere put your own on `PATH`).
It refuses GHDL < 5; use Debian trixie / Ubuntu 24.04+ or the container:

```sh
podman run --rm -it -v "$PWD":/work -w /work debian:trixie-slim bash -c '
  apt-get update && apt-get install -y ghdl gcc make python3-venv python3-pip curl xz-utils git &&
  ./opensource_sim/setup_env.sh && source opensource_sim/env.sh && ./opensource_sim/run_sim.sh'
```

## Rerunning one test by hand

After any `run_isa.sh` run, the GHDL work library and per-test logs are in
`opensource_sim/isa/work/`; images are in `verification/isa/build/<suite>/`.

```sh
cd opensource_sim/isa
ghdl -r --std=08 -fsynopsys --workdir=work vesta_isa_tb \
    -gTEST_FILE=../../verification/isa/build/rv32ui/xxxxxxrv32ui-p-add.rcf
```

Exit 0 = pass. `.rcf` names are `x`-padded; `ls` the build directory for exact names.
Images built by hand with `make -C verification/isa` must pass the `CORE_ENABLE_DEFS`
set from `run_isa.sh` and start from `rm -rf verification/isa/build`: make keys the
`.elf` on the `.S` alone and silently reuses opposite-polarity images.
