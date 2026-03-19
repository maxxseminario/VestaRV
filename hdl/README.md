# HDL Sources

This directory contains all VHDL source files for VestaRV, organized into the MCU top-level and its sub-modules.

---

## Directory Structure

```
hdl/
└── MCU/
    ├── MCU.vhd            — Top-level MCU entity (connects core, memory, peripherals)
    ├── MemoryMap.vhd      — Generated peripheral address constants 
    ├── constants.vhd      — Global type and constant definitions
    ├── adddec.vhd         — Address decoder
    ├── vesta/             — VestaRV processor core
    ├── periph/            — Peripheral modules
    ├── commune/           — Shared components (memories, clock gates, synchronizers)
    ├── macros/            — Synthesis macros and wrappers
    ├── sim/               — Simulation-only behavioural models (RAM, ROM, clocks)
    └── tb/                — Testbenches
```

See [`MCU/README.md`](MCU/README.md) for a detailed breakdown of the core architecture and peripheral list.

---

## Simulation

### Prerequisites

Any **VHDL-2008-compatible** simulator works. Recommended free options:

| Simulator | Install |
|-----------|---------|
| [GHDL](https://github.com/ghdl/ghdl) | Clone and build from source: `git clone https://github.com/ghdl/ghdl` — see repo for build instructions |
| [NVC](https://github.com/nickg/nvc) | Clone and build from source: `git clone https://github.com/nickg/nvc` — see repo for build instructions |
| ModelSim / Questa | Available free via Intel FPGA Lite edition |
| Xcelium | Commercial (Cadence) |

GHDL is the recommended open-source option.

