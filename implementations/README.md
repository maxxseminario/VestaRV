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
- **ASIC**: `<chip-name>-<year>-<month>` (e.g., `washakie-2022-03`, `myshkin-2024-11`)
- **FPGA**: `<board-name>-<variant>` (e.g., `arty-a7-100t`, `nexys-a7`)

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
│   ├── washakie-2022-03/
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
