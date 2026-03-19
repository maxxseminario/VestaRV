# HDL Sources

This directory contains all VHDL source files for VestaRV, organized into the MCU top-level and its sub-modules.

---

## Directory Structure

```
hdl/
└── MCU/
    ├── MCU.vhd            — Top-level MCU entity (connects core, memory, peripherals)
    ├── MemoryMap.vhd      — Generated peripheral address constants (do not hand-edit)
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
| [GHDL](https://github.com/ghdl/ghdl) | `sudo apt install ghdl` (Ubuntu/Debian) or build from source |
| [NVC](https://github.com/nicowillis/nvc) | `sudo apt install nvc` |
| ModelSim / Questa | Available free via Intel FPGA Lite edition |
| Xcelium | Commercial (Cadence) |

GHDL is the recommended open-source option.

### Compiling with GHDL

All source files must be analysed in dependency order. From the repo root:

```bash
# 1. Analyse shared packages first
ghdl -a --std=08 --work=work hdl/MCU/constants.vhd
ghdl -a --std=08 --work=work hdl/MCU/MemoryMap.vhd

# 2. Analyse commune (shared components)
ghdl -a --std=08 --work=work hdl/MCU/commune/*.vhd
ghdl -a --std=08 --work=work hdl/MCU/macros/macros.vhd

# 3. Analyse the core
ghdl -a --std=08 --work=work hdl/MCU/vesta/*.vhd

# 4. Analyse peripherals
ghdl -a --std=08 --work=work hdl/MCU/periph/*.vhd

# 5. Analyse top-level MCU
ghdl -a --std=08 --work=work hdl/MCU/adddec.vhd
ghdl -a --std=08 --work=work hdl/MCU/MCU.vhd

# 6. Analyse simulation models and testbench
ghdl -a --std=08 --work=work hdl/MCU/sim/*.vhd
ghdl -a --std=08 --work=work hdl/MCU/tb/tb_defs.vhd
ghdl -a --std=08 --work=work hdl/MCU/tb/riscv_tb.vhd
```

### Running a Simulation

The primary testbench is `riscv_tb` in `hdl/MCU/tb/riscv_tb.vhd`. It instantiates the full MCU with behavioural RAM and ROM models and loads a program from an RCF (RAM Configuration File) located in `verification/isa/rcf/`.

```bash
# Elaborate
ghdl -e --std=08 --work=work riscv_tb

# Run a specific ISA test (e.g., add instruction test)
ghdl -r --std=08 --work=work riscv_tb \
  --generic=RCF_FILE="verification/isa/rcf/rv32ui-p-add.rcf" \
  --stop-time=100us

# Dump a waveform for inspection
ghdl -r --std=08 --work=work riscv_tb \
  --generic=RCF_FILE="verification/isa/rcf/rv32ui-p-add.rcf" \
  --vcd=sim_out.vcd --stop-time=100us

# Open waveform in GTKWave
gtkwave sim_out.vcd
```

### Running the Full ISA Test Suite

Build the RCF files first, then simulate each one:

```bash
# Build all ISA test RCFs
cd verification/isa
make all
cd ../..

# Run all rv32ui tests through the testbench
for rcf in verification/isa/rcf/rv32ui-p-*.rcf; do
    echo "Testing: $rcf"
    ghdl -r --std=08 --work=work riscv_tb \
      --generic=RCF_FILE="$rcf" \
      --stop-time=500us
done
```

A test passes when it writes `0x00000001` to `0xABCDEF00` (the standard riscv-tests pass signature).

### Available Testbenches

| File | Purpose |
|------|---------|
| `riscv_tb.vhd` | Full MCU simulation with memory and all peripherals |
| `testbench.vhd` | Simple smoke-test testbench |
| `NPU_tb.vhd` | Neural Processing Unit standalone test |
| `SARADC_tb.vhd` | SAR ADC peripheral test |
| `rv4th_tb.vhd` | Forth interpreter firmware test |
| `FPSigmoid_tb.vhd` | Floating-point sigmoid unit test |

---

## Synthesising for FPGA

VestaRV targets **VHDL-2008** and has been tested on Xilinx (Vivado) and Cadence (Genus) flows. For FPGA synthesis:

1. Add all files under `hdl/MCU/` to your project, **excluding** the `sim/` and `tb/` directories.
2. Replace `sim/ARM_IP_RAM.vhd` and `sim/ARM_IP_ROM.vhd` with your target FPGA BRAM primitives.
3. Set the top-level entity to `MCU`.
4. See `implementations/fpga/` for board-specific constraint files and pin assignments.

---

## Source File Overview

### `hdl/MCU/commune/` — Shared Components

| File | Description |
|------|-------------|
| `ARM_IP_RAM.vhd` | Behavioural model of the ARM Artisan SRAM (simulation only) |
| `ARM_IP_ROM.vhd` | Behavioural model of the ARM Artisan ROM (simulation only) |
| `ClkGate.vhd` | Clock-gate cell wrapper |
| `ClkDivPower2.vhd` | Power-of-two clock divider |
| `ClockMuxGlitchFree.vhd` | Glitch-free clock multiplexer |
| `CRC16.vhd` | CRC-16 computation engine |
| `Synchronizer.vhd` | Single-bit CDC synchronizer |
| `SynchronizerSLV.vhd` | Multi-bit CDC synchronizer |
| `GlitchFilter_behav.vhd` | Digital glitch filter |
| `FPMac.vhd` | Floating-point multiply-accumulate unit |
| `FPSigmoid.vhd` | Floating-point sigmoid approximation |
| `macros.vhd` | Package of common utility functions |

### `hdl/MCU/sim/` — Simulation Models

These files are **not** for synthesis. They provide behavioural stand-ins for process-specific IP cells (memories, clock gates, PLLs) that cannot be distributed.

| File | Replaces |
|------|---------|
| `ARM_IP_RAM.vhd` | TSMC 65nm SRAM IP |
| `ARM_IP_ROM.vhd` | TSMC 65nm ROM IP |
| `ClkGate.vhd` | TSMC 65nm clock-gate cell |
| `ClockMuxGlitchFree.vhd` | TSMC 65nm glitch-free mux cell |
| `OscillatorCurrentStarved_simulation.vhd` | On-chip DCO |
| `PowerOnResetCheng_behav.vhd` | Power-on-reset circuit |
| `GlitchFilter_behav.vhd` | Pad glitch filter |
