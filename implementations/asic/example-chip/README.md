# Example ASIC Chip Implementation

This is a template directory for documenting an ASIC implementation of VestaRV.

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
