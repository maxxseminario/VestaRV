# VestaRV Implementations

This directory contains documentation and configuration for specific VestaRV instantiations across different target platforms.

## Building through Bazel

Every chip in this directory is produced by the Bazel-managed `platform/common/`
generator. Run all commands below **from the repo root**.

One-time bootstrap:

```sh
sh tools/get_bazel.sh            # fetches bazelisk into tools/bin/bazel
tools/bin/bazel test //...       # first run downloads all toolchains
```

### Generation targets

| Target | What it produces |
|--------|------------------|
| `//platform/common:chip_artifacts_castalia` | The whole Castalia artifact tree: drop-in RTL (`MCU.vhd`, `MemoryMap.vhd`, `riscv_tb.vhd`), `MemoryMap.h`, `periph.S`, linker scripts, pad-ring JSON/TCL, the web data bundle, and the TRM LaTeX project. |
| `//platform/common:chip_artifacts_argus` | The same tree for the 18-hart Argus configuration (`platform/common/config/argus.json`). |
| `//platform/common:chip_artifacts_castalia_repro` | A second, independent Castalia generation; it exists only so the determinism gate has something to byte-compare against. |

Individual outputs have named handles, for example
`//platform/common:castalia_mcu_vhd`, `//platform/common:castalia_memorymap_h`,
`//platform/common:castalia_padring_tcl` and
`//platform/common:castalia_linker_scripts`.

Never run `bazel run //:generate` - that is the raw generator and it writes
wherever it happens to be invoked. The hermetic path is
`//platform/common:chip_artifacts_castalia`.

### Gates attached to generation

`tools/bin/bazel test //platform/...` runs all of these:

| Target | What it proves |
|--------|----------------|
| `//platform/common:check_mcu_vhd_test` | The regenerated `MCU.vhd` is a byte-for-byte drop-in for the tracked `hdl/common/MCU.vhd`. |
| `//platform/common:check_memorymap_vhd_test` | Constant-by-constant equivalence with the tracked `hdl/common/MemoryMap.vhd`. |
| `//platform/common:check_riscv_tb_vhd_test` | The generated `riscv_tb.vhd` still matches the tracked testbench at this hart count. |
| `//platform/common:check_memorymap_h_test` | The emitted C header still compiles, under the hermetic RISC-V gcc. |
| `//platform/common:check_intro_names_test` | Every register named in a hand-written peripheral intro is something the generator actually emits. |
| `//platform/common:check_configurator_sync_test` | `docs/chip_configurator.html` is in sync with the generator, at the strict bar. |
| `//platform/common:splice_web_data_check_test` | The `VESTA_DATA` block spliced into the configurator page is not stale. |
| `//platform/common:generation_determinism_test` | Two independent generations are byte-identical - no wall-clock or ordering nondeterminism. |
| `//platform/common:argus_generation_test` | The Argus configuration still generates and all of its machine-readable outputs are present and parse. |
| `//platform/common:trm_latex_tree_test` | The generated TRM LaTeX tree is complete: master document, includes, figures. |
| `//platform/common:castalia_analog_chapter_test` | The analog chapter is present in the generated TRM tree. |
| `//platform/common/python:check_config_defaults_test` | Each knob's two default literals in `generate.py` agree with each other. |

### Outside Bazel

Cadence flows (Genus, Innovus, Pegasus, Xcelium, `make verify`) are permanently
outside Bazel - they are licensed binaries behind a license server, so no
hermetic target can wrap them. Run them via `source cdspaths.sh`.

Full map of the Bazel build: [`BAZEL.md`](../BAZEL.md).

## Directory Structure

### ASIC Implementations (`asic/`)
Each ASIC implementation directory contains:
- **`docs/`** — User guides, datasheets, application notes
- **`config/`** — ChipConfig.json, MemoryMap.json, BoardConfig.json
- **`images/`** — Block diagrams, floorplans, layout screenshots
- **`specifications/`** — Electrical specs, timing reports, silicon validation data

### FPGA Implementations (`fpga/`)
Each FPGA implementation directory contains:
- **`docs/`** — User guides, getting started documents
- **`config/`** — Configuration files for the specific FPGA target
- **`images/`** — Block diagrams, pinout diagrams
- **`bitstreams/`** — Pre-built bitstream files

## Naming Convention

Use descriptive names that include key identifiers:
- **ASIC**: `<chip-name>-<year>-<month>` (e.g. `myshkin-2025-11`)
- **FPGA**: `<board-name>-<variant>` (e.g., `arty-a7-100t`, `nexys-a7`)

## Current Implementations

### ASIC
- **[myshkin-2025-11](asic/myshkin-2025-11/)** — single-core TSMC 65nm tape-out with NPU accelerator and analog front-end (November 2025). Silicon validated; potentiostat design won a best paper award at IEEE ISCAS 2026.
- **[castalia](asic/castalia/)** — 5-hart wound-monitoring MCU derived from the same VestaRV core: hart 0 is a soft always-on orchestrator, harts 1-4 are four instances of one hardened rv32iac channel tile; signoff-closed tile and MCU.
- **[argus](asic/argus/)** — 18-hart teaching chip built from the identical hart tile as a 3×3 tile array; generated from `config/argus.json`.

All three chips are produced from one config-driven generator (`platform/common/`); see
each chip's README and TRM for specifics.

### FPGA
- (No FPGA implementations yet — see example template in `fpga/example-board/`)

## Adding a New Implementation

1. Create a new directory under `asic/` or `fpga/`
2. Populate the standard subdirectories (docs, config, images, etc.)
3. Add a README.md in the implementation directory describing:
   - Target platform details
   - Peripheral configuration
   - Memory organization
   - Special features or constraints
   - Build/synthesis notes

## Example Structure

```
implementations/
├── asic/
│   ├── myshkin-2022-03/
│   │   ├── README.md
│   │   ├── docs/
│   │   │   ├── user-guide.pdf
│   │   │   └── datasheet.pdf
│   │   ├── config/
│   │   │   ├── ChipConfig.json
│   │   │   └── MemoryMap.json
│   │   ├── images/
│   │   │   ├── block-diagram.png
│   │   │   └── floorplan.png
│   │   └── specifications/
│   │       ├── electrical-specs.pdf
│   │       └── timing-report.txt
│   └── myshkin-2024-11/
│       └── ...
└── fpga/
    ├── arty-a7-100t/
    │   ├── README.md
    │   ├── docs/
    │   ├── config/
    │   ├── images/
    │   └── bitstreams/
    │       └── vestarv_top.bit
    └── nexys-a7/
        └── ...
```
