# Myshkin ASIC Implementation

VestaRV32 implementation taped out to TSMC 65nm process in November 2025.

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

- **`docs/`** — MCU user guide and documentation
  - `MCU-User-Guide.pdf` — Complete peripheral and system documentation
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
- [ ] Silicon Received
- [ ] Silicon Validated

## Key Features

This implementation demonstrates VestaRV's capabilities in a mixed-signal application, combining digital processing with analog front-end circuitry for sensor interfacing. The NPU accelerator enables edge ML inference for sensor data processing.

## Publications

- IEEE ISCAS Conference paper in submission/review
- Citation and link to be added upon publication

## Contact

For detailed specifications or collaboration opportunities, contact the Maxx Seminario (mseminario2@huskers.unl.edu).
