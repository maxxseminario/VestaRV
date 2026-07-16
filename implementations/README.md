# VestaRV Implementations

This directory contains documentation and configuration for specific VestaRV instantiations across different target platforms.

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
- **[castalia](asic/castalia/)** — 4-hart multiprocessor derived from the same VestaRV core; digital-only configuration, signoff-closed tile and MCU.
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
