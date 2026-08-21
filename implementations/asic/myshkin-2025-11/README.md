# Myshkin ASIC Implementation

VestaRV32 implementation taped out to TSMC 65nm process in November 2025.

## Building through Bazel

Myshkin's own generator is **not** Bazel-managed (see "Legacy and out-of-Bazel
paths" below), but the tracked Myshkin platform snapshot is what every
Bazel-built firmware image in the repo compiles against. Run all commands below
**from the repo root**.

One-time bootstrap:

```sh
sh tools/get_bazel.sh            # fetches bazelisk into tools/bin/bazel
tools/bin/bazel test //...       # first run downloads all toolchains
```

### The Myshkin platform snapshot, as build inputs

| Target | What it is |
|--------|------------|
| `//platform/myshkin/gcc/lib:platform_headers` | The tracked `MemoryMap.h` + `periph.S` snapshot of this chip's register map. Every firmware and ISA-image build in the repo compiles with this on its include path. |
| `//platform/myshkin/gcc/lib:linker_fragments` | The tracked `memory.x` + `periph.x` the linker pulls in through `MCU.ld`. |

### Firmware and image targets that use them

| Target | What it proves |
|--------|----------------|
| `//software/bootrom_mp:rom_rcf` | Builds the mask-ROM image; `//software/bootrom_mp:rom_rcf_reproducibility_test` proves it is byte-identical to the tracked golden. |
| `//software/blinky:blinky_rcf` (also `gpiotoggle`, `looptest`, `slowblink`, `traptest`, `afetest`) | Builds an application image with the hermetic RISC-V cross-compiler; the per-app `//software/blinky:blinky_flashed_rcf_test` and siblings lock it against a tracked golden. |
| `//verification/isa:all_images` | Builds all 259 ISA test images; `//verification/isa:image_contract_test` proves the image set matches its contract. |

### License-free simulation of the core RTL

```sh
tools/bin/bazel test //opensource_sim:isa_regression
```

Nine GHDL ISA suites (`//opensource_sim:isa_rv32ui` and siblings) over
`//hdl:vhdl_sources`, which includes the frozen `hdl/myshkin/` tree. No
licensed tools involved.

### Legacy and out-of-Bazel paths

- The Myshkin generator (`platform/myshkin/`) overwrites tracked files in
  place and is deliberately left out of Bazel. It is a **frozen** tree; run it
  the old way if you must.
- Cadence flows (Genus, Innovus, Pegasus, Xcelium, `make verify`) are
  permanently outside Bazel - licensed binaries. Run them exactly as before,
  via `source cdspaths.sh`.
- Bench and silicon-validation tooling talks to physical boards over serial and
  is likewise unmanaged by Bazel.

Full map of the Bazel build: [`BAZEL.md`](../../../BAZEL.md).

## Overview

- **Chip Name**: Myshkin
- **Tape-out Date**: November 2025
- **Process Node**: TSMC 65nm
- **Target Application**: Mixed-Signal Electrochemical Sensing SoC for Autonomous Wound Monitoring
- **Die Size**: 1.0 mm × 1.5 mm
- **Package**: QFN-44

## Configuration

- **Core**: VestaRV32 (RV32IMAC + Zb*)
- **ROM Size**: 16 KiB
- **RAM Size**: 32 KiB
- **Clock Frequency**: 24 MHz 

### Peripherals

- **GPIO**: 4× 8-bit ports (32 pins total)
- **Communication**:
  - 1× SPI master interface
  - 1× SPI with flash memory extension
  - 2× UART modules
  - 2× I2C interfaces
- **Timers**: 2× 32-bit timer/counter modules
- **Compute**: 1× Neural Processing Unit (NPU) accelerator
- **Analog Front-End**: 1× Potentiostat for electrochemical sensing
- **ADC**: 1× Analog-to-Digital Converter
- **System Control**: Clock management, power gating, watchdog

## Directory Contents

- **`docs/`** — Technical documentation
  - `TRM.pdf` — Technical Reference Manual with complete peripheral and system documentation
- **`config/`** — Configuration files used for code generation
  - `MemoryMap.json` — Memory and peripheral address mapping
- **`images/`** — Block diagrams, layout screenshots, die photos
  - `myshkin_block_diagram.png` — System-level block diagram
  - `myshkin_layout.png` - ASIC Physcal Layout 
- **`specifications/`** — Electrical and timing specifications
  - (Post-silicon characterization data to be added)

## Silicon Status

- [x] RTL Complete
- [x] Synthesis Complete
- [x] Place & Route Complete
- [x] Tape-out Submitted (November 2025)
- [x] Silicon Received (March 2026)
- [x] Silicon Validated (March 2026)

## Key Features

This implementation demonstrates VestaRV's capabilities in a mixed-signal application, combining digital processing with analog front-end circuitry for sensor interfacing. The NPU accelerator enables edge ML inference for sensor data processing.

## Publications

- Best Student Paper Award Winner at IEEE ISCAS 2026
- IEEE ISCAS 2026 Conference paper in lecture


## Contact

For detailed specifications or collaboration opportunities, contact the Maxx Seminario (mseminario2@huskers.unl.edu).
