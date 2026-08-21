# Example ASIC Chip Implementation

This is a template directory for documenting an ASIC implementation of VestaRV.

## Building through Bazel

A new chip is a new configuration of the Bazel-managed `platform/common/`
generator, not a new generator. Run all commands below **from the repo root**.

One-time bootstrap:

```sh
sh tools/get_bazel.sh            # fetches bazelisk into tools/bin/bazel
tools/bin/bazel test //...       # first run downloads all toolchains
```

### Model your chip on an existing configuration

| Target | What it produces |
|--------|------------------|
| `//platform/common:chip_artifacts_castalia` | The default (golden-master) configuration: drop-in RTL (`MCU.vhd`, `MemoryMap.vhd`, `riscv_tb.vhd`), `MemoryMap.h`, `periph.S`, linker scripts, pad-ring JSON/TCL, the web data bundle, and the TRM LaTeX project. |
| `//platform/common:chip_artifacts_argus` | The same tree driven from an alternate config file (`platform/common/config/argus.json`) - copy this rule when you add a chip. |

To add a chip: put its JSON under `platform/common/config/`, add a
`chip_artifacts` rule in `platform/common/BUILD.bazel` modeled on
`//platform/common:chip_artifacts_argus` with `config =` pointing at your file,
and add a generation assertion modeled on
`//platform/common:argus_generation_test`.

Never run `bazel run //:generate` - that is the raw generator and it writes
wherever it happens to be invoked. The hermetic path is the
`chip_artifacts_*` target.

### Gates your chip inherits

`tools/bin/bazel test //platform/...` runs the standing generator gates:

| Target | What it proves |
|--------|----------------|
| `//platform/common:check_mcu_vhd_test` | The regenerated `MCU.vhd` is a byte-for-byte drop-in for the tracked `hdl/common/MCU.vhd`. |
| `//platform/common:check_memorymap_vhd_test` | Constant-by-constant equivalence with the tracked `hdl/common/MemoryMap.vhd`. |
| `//platform/common:check_riscv_tb_vhd_test` | The generated `riscv_tb.vhd` still matches the tracked testbench. |
| `//platform/common:check_memorymap_h_test` | The emitted C header still compiles, under the hermetic RISC-V gcc. |
| `//platform/common:check_intro_names_test` | Every register named in a hand-written peripheral intro is something the generator actually emits. |
| `//platform/common:generation_determinism_test` | Two independent generations are byte-identical. |
| `//platform/common:argus_generation_test` | An alternate configuration still generates and its outputs parse - the template your chip's gate should copy. |
| `//platform/common:trm_latex_tree_test` | The generated TRM LaTeX tree is complete. |
| `//platform/common/python:check_config_defaults_test` | Each knob's two default literals in `generate.py` agree with each other. |

Simulate the RTL license-free with
`tools/bin/bazel test //opensource_sim:isa_regression`.

### Outside Bazel

Cadence flows (Genus, Innovus, Pegasus, Xcelium, `make verify`) are permanently
outside Bazel - they are licensed binaries behind a license server, so no
hermetic target can wrap them. Run them via `source cdspaths.sh`.

Full map of the Bazel build: [`BAZEL.md`](../../../BAZEL.md).

## Overview

- **Chip Name**: Example Chip
- **Tape-out Date**: YYYY-MM
- **Process Node**: [e.g., 65nm, 28nm]
- **Target Application**: [e.g., IoT sensor hub, mixed-signal MCU]

## Configuration

- **Core**: VestaRV32 (RV32IMAC + Zb*)
- **ROM Size**: [e.g., 16 KiB]
- **RAM Size**: [e.g., 32 KiB]
- **Clock Frequency**: [e.g., 100 MHz max]
- **Peripherals**:
  - GPIO: X ports
  - UART: X channels
  - SPI: X interfaces
  - Timer: X modules
  - [List other peripherals]

## Directory Contents

- **`docs/`** — User guide, datasheet, application notes
- **`config/`** — JSON configuration files used for generation
- **`images/`** — Block diagrams, floorplan, layout screenshots
- **`specifications/`** — Electrical specs, timing analysis, validation data

## Build Notes

[Add any specific notes about synthesis, place & route, or post-silicon validation]

## Silicon Status

- [ ] RTL Complete
- [ ] Synthesis Complete
- [ ] Place & Route Complete
- [ ] Tape-out Submitted
- [ ] Silicon Received
- [ ] Silicon Validated
