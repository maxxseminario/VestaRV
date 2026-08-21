# Castalia ASIC Implementation

Castalia is a **4-hart (four-core) multiprocessor** built from four identical VestaRV CPU
cores. It is derived from the same core as the single-core Myshkin tape-out, and is
generated from one configuration by the `platform/common/` chip generator.

## Building through Bazel

Castalia is the default (golden-master) configuration of the Bazel-managed
`platform/common/` generator. Run all commands below **from the repo root**.

One-time bootstrap:

```sh
sh tools/get_bazel.sh            # fetches bazelisk into tools/bin/bazel
tools/bin/bazel test //...       # first run downloads all toolchains
```

### Generating the chip

```sh
tools/bin/bazel build //platform/common:chip_artifacts_castalia
```

| Target | What it produces |
|--------|------------------|
| `//platform/common:chip_artifacts_castalia` | The whole Castalia artifact tree: drop-in RTL (`MCU.vhd`, `MemoryMap.vhd`, `riscv_tb.vhd`), `MemoryMap.h`, `periph.S`, linker scripts, pad-ring JSON/TCL, the web data bundle, and the TRM LaTeX project. |
| `//platform/common:chip_artifacts_castalia_repro` | A second, independent generation of the same configuration, for the determinism gate to byte-compare against. |
| `//platform/common:castalia_mcu_vhd`, `:castalia_memorymap_vhd`, `:castalia_riscv_tb_vhd` | Named handles on the individual drop-in RTL files. |
| `//platform/common:castalia_memorymap_h`, `:castalia_periph_s`, `:castalia_linker_scripts`, `:castalia_software_include` | The firmware-facing half of the same tree. |
| `//platform/common:castalia_padring_json`, `:castalia_padring_tcl` | The pad-ring description consumed by the physical flow. |
| `//platform/common:trm_latex_tree` | The generated TRM LaTeX project, as one directory artifact. |

Never run `bazel run //:generate` - that is the raw generator and it writes
wherever it happens to be invoked. The hermetic path is
`//platform/common:chip_artifacts_castalia`.

### Gates attached to those artifacts

`tools/bin/bazel test //platform/...` runs all of these:

| Target | What it proves |
|--------|----------------|
| `//platform/common:check_mcu_vhd_test` | The regenerated `MCU.vhd` is a byte-for-byte drop-in for the tracked `hdl/common/MCU.vhd`. |
| `//platform/common:check_memorymap_vhd_test` | Constant-by-constant equivalence with the tracked `hdl/common/MemoryMap.vhd`. |
| `//platform/common:check_riscv_tb_vhd_test` | The generated `riscv_tb.vhd` still matches the tracked testbench at 4 harts. |
| `//platform/common:check_memorymap_h_test` | The emitted `MemoryMap.h` still compiles, under the hermetic RISC-V gcc. |
| `//platform/common:check_intro_names_test` | Every register named in a hand-written peripheral intro is something the generator actually emits. |
| `//platform/common:check_configurator_sync_test` | `docs/chip_configurator.html` is in sync with the generator, at the strict bar. |
| `//platform/common:splice_web_data_check_test` | The `VESTA_DATA` block spliced into the configurator page is not stale. |
| `//platform/common:generation_determinism_test` | Two independent generations are byte-identical. |
| `//platform/common:trm_latex_tree_test` | The generated TRM tree is complete: master document, includes, figures. |
| `//platform/common:castalia_analog_chapter_test` | The analog chapter is present in the generated TRM tree. |
| `//platform/common/python:check_config_defaults_test` | Each knob's two default literals in `generate.py` agree with each other. |

### TRM PDF

The PDF half is a Bazel-wrapped host TeX build, tagged manual:

```sh
tools/bin/bazel build //platform/common/latex/bazel:trm_pdf_local
tools/bin/bazel test //platform/common/latex/bazel:check_publish_test \
                     //platform/common/latex/bazel:trm_lint_test
```

`:check_publish_test` is red whenever TRM-affecting commits have landed since
the last publish - that is the point of the gate. `:trm_lint_test` lints the
generated LaTeX.

### License-free simulation of this RTL

```sh
tools/bin/bazel test //opensource_sim:isa_regression
```

Nine GHDL ISA suites (`//opensource_sim:isa_rv32ui` and siblings) plus the unit
benches `//hdl/common/tb:mp_arbiter_tb` and `//hdl/common/tb:pmp_unit_tb`. No
licensed tools involved.

### Outside Bazel

Cadence flows (Genus, Innovus, Pegasus, Xcelium, `make verify`) are permanently
outside Bazel - they are licensed binaries behind a license server, so no
hermetic target can wrap them. Run them via `source cdspaths.sh`.

Full map of the Bazel build: [`BAZEL.md`](../../../BAZEL.md).

## Overview

- **Chip Name**: Castalia
- **Configuration**: 4-hart multiprocessor, digital-only (D0) configuration
- **Process Node**: TSMC 65nm
- **Package**: QFN-44, 7 × 7 mm, 0.5 mm pitch *(preliminary — inherited from Myshkin, not yet finalized for Castalia)*

## Configuration

- **Core**: 4× VestaRV32 (RV32IMAC + Zb*, ISA string `rv32imac_zba_zbb_zbc_zbs`), each with private RAM; hart ID via the `mhartid` CSR
- **Boot ROM**: 16 KiB shared boot ROM (all four harts reset to PC 0x0)
- **Private memory**: 16 KiB TCM per hart
- **Shared memory window** (arbitrated, serializing round-robin): 80 KiB of shared RAM — a 64 KiB shared bulk region (4× 16 KiB banks) plus a 16 KiB NPU staging RAM
- **Synchronization**: CLINT (inter-processor + per-hart timer interrupts), 16 hardware mutexes, and a per-hart PLIC-style peripheral interrupt router (claim/complete, any-vector-to-any-hart routing)
- **Interrupt vectors**: 85 (vectors 83/84 are the CLINT software/timer interrupts)

### Peripherals

- **GPIO**: 4× 8-pin ports with edge-triggered interrupts and per-pin alternate-function mux (up to 8 AFs per pin)
- **Communication**:
  - 2× SPI (SPI0 provides memory-mapped access to external flash)
  - 2× UART with hardware parity
  - 2× I²C (master and slave mode)
- **Timers**: 2× 32-bit timers with PWM outputs and input capture
- **Compute**: 1× Neural Processing Unit (NPU) co-processor
- **System Control**: CRC16 engine, 2× digitally controllable oscillators, windowed watchdog timer, power controller (PWRCTRL), per-tile MTCMOS power gating with hardware gate/wake sequencing

## Directory Contents

- **`docs/`** — Technical documentation
  - `TRM.pdf` — Technical Reference Manual (config-driven, built by
    `//platform/common/latex/bazel:trm_pdf_local`)
- **`config/`** — Configuration files used for code generation (as available)

## Configuration Provenance

Castalia is the **default (golden-master) configuration** of the `platform/common/`
generator. The entire chip — memory-map headers, linker scripts, drop-in RTL, and the TRM
— is regenerated from one JSON configuration by
`//platform/common:chip_artifacts_castalia`; the Cadence `make verify` run proves the
configuration boots. Key knobs for this build: `numHarts = 4`, `numMutexes = 16`,
`memory.sharedBulkRamSize = 64 KiB`, `memory.npuStagingRamSize = 16 KiB`,
`peripherals.npu = true`.

## Silicon Status

- [x] RTL Complete (multi-core `hdl/common/` tree)
- [x] Behavioral verification (multi-core boot/ISA + shared-window suite)
- [x] Gate-level (post-genus, SDF-annotated) verification
- [x] Tile hardened and 4× assembly placed & routed
- [x] Signoff DRC/LVS closure (tile + committed MCU cut)
- [x] Connected pad-ring chip-top (C0)

## Publications

- Multi-core VestaRV derivative of the Myshkin single-core platform.

## Contact

For detailed specifications or collaboration opportunities, contact Maxx Seminario (mseminario2@huskers.unl.edu).
