# VestaRV Implementations

Per-chip documentation for VestaRV instantiations. Castalia, Argus and the default
configurations are produced by the `platform/common/` generator
([targets and gates](../platform/common/README.md)); Myshkin uses the frozen
`platform/myshkin/` generator.

| Directory | Chip |
|---|---|
| [`asic/castalia/`](asic/castalia/README.md) | Five-hart reference MCU, TSMC 65 nm: soft orchestrator hart 0, four hardened `hart_tile` harts |
| [`asic/argus/`](asic/argus/README.md) | 18-hart teaching chip, 3 × 3 tile array |
| [`asic/myshkin-2025-11/`](asic/myshkin-2025-11/README.md) | Single-core tape-out, TSMC 65 nm, November 2025; silicon validated |
| [`asic/example-chip/`](asic/example-chip/README.md) | Template for a new ASIC |
| [`fpga/synth/`](fpga/synth/README.md) | Out-of-context Vivado synthesis and constraints |
| [`fpga/bringup/`](fpga/bringup/README.md) | FPGA boot from SPI flash |
| [`fpga/example-board/`](fpga/example-board/README.md) | Template for an FPGA board |

## Build

From the repo root:

```sh
sh tools/get_bazel.sh                                             # bazelisk -> tools/bin/bazel
tools/bin/bazel run   //:generate                                 # writes platform/common/out/
tools/bin/bazel build //platform/common:chip_artifacts_castalia   # hermetic; also chip_artifacts_argus
tools/bin/bazel test  //platform/...                              # generator gates
```

`//:generate` takes `-- --config <file> --out <dir>` to select a configuration and
output root. The `chip_artifacts_*` targets run the same generator in a sandbox and
are what the gates grade. Cadence flows (Genus, Innovus, Pegasus, Xcelium) run outside
Bazel after `source cdspaths.sh`. Full map: [`BAZEL.md`](../BAZEL.md).

## Adding an implementation

- Naming: ASIC `<chip>` or `<chip>-<year>-<month>` (e.g. `myshkin-2025-11`); FPGA
  `<board>-<variant>` (e.g. `arty-a7-100t`).
- Contents: a `README.md` (target, peripherals, memory, constraints, build notes) plus
  whichever of `docs/`, `config/`, `images/`, `specifications/` (ASIC) or
  `bitstreams/` (FPGA) apply.
- A new ASIC is a new generator configuration; see
  [`asic/example-chip/`](asic/example-chip/README.md).
