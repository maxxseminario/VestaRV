<table border="0" cellspacing="0" cellpadding="0">
  <tr>
    <td>
      <img src="assets/vesta_logo_light.png#gh-light-mode-only" alt="VestaRV32 logo" height="80" />
      <img src="assets/vesta_logo_dark.png#gh-dark-mode-only" alt="VestaRV32 logo" height="80" />
    </td>
    <td style="padding-left:12px;">
      <h1 style="margin:0;">VestaRV32 - A Custom RISC-V Core &amp; SoC</h1>
    </td>
  </tr>
</table>

VestaRV is a custom 32-bit RISC-V processor core designed as an independent personal project, built from the ground up using the official RISC-V instruction set specification without deriving from any existing core implementations. This repository not only provides the VestaRV core but also a full MCU System on Chip (SoC) that surrounds the core, enabling rapid integration into embedded and SoC designs. 

**Namesake:**  
VestaRV is named after **Vesta**, the Roman goddess of hearth, home, and the eternal flame. As Vesta’s fire symbolized the heart of the household, VestaRV is designed to be the heart of your embedded system—providing reliability and a strong foundation for your MCU and SoC projects.


## MCU Block Diagram

Below is the MCU-level block diagram showing VestaRV instantiated within the MCU and the major peripherals highlighted:

![MCU Block Diagram](assets/ASIC_block_diagram.png)


## Table of Contents

- [Features and Typical Applications](#features-and-typical-applications)
- [Repository Structure](#repository-structure)
- [Core Specifications](#core-specifications)
- [MCU Peripherals](#mcu-peripherals-configurable)
- [Memory Architecture](#mcu-memory-architecture-configurable)
- [Interrupt Handling](#interrupt-handling)
- [Building and Toolchain](#building-and-toolchain)
- [Getting Started](#getting-started)
- [Author and Support](#author-and-support)

---

## Features and Typical Applications

- **Custom RISC-V Core** supporting:
  - RV32I Base ISA
  - 'M' Extension (Integer multiplication & division)
  - 'C' Extension (Compressed instructions)
  - 'A' Extension (Atomic Memory Operations)
  - 'ZBA', 'ZBB', 'ZBC', 'ZBS' (Advanced Bit Manipulation)
  - 'ZICNTR' (Partial, e.g., RDCYCLE and RDINSTRET)
- **Stack-based interrupt handling** 
- **Post Innovus verification**
- **Full MCU System on Chip Implementation** 
- Designed for easy integration into ASICs

Typical applications include:
- Custom embedded MCU development
- Mixed signal and sensor interfacing

---

## Repository Structure

This repository is organized into the following directories:

### Core Hardware
- **`hdl/`** — VestaRV core and MCU peripheral VHDL sources
  - `MCU/vesta/` — RISC-V processor core implementation
  - `MCU/periph/` — Peripheral modules (GPIO, UART, SPI, Timer, etc.)
  - `MCU/tb/` — Testbenches for simulation

### Firmware & Software
- **`firmware/`** — Embedded firmware projects
  - `bootrom/` — Boot ROM code and Forth interpreter
  - `rv4th/` — Standalone Forth interpreter
  
### Verification
- **`verification/`** — Test suites and verification infrastructure
  - `isa/` — RISC-V instruction-level tests (adapted from [riscv-tests](https://github.com/riscv-software-src/riscv-tests))
    - Organized into `tests/` (source) and `build/` (artifacts)
    - Central `rcf/` directory for VHDL simulation files
  - `benchmarks/` — Performance benchmarking tests
  - `env/` — Test environment and linker scripts

### Build System
- **`build-system/`** — Build infrastructure for all projects
  - `linker-scripts/` — Memory layout configurations
  - `scripts/` — Build and conversion utilities (Python, shell)
  - `templates/` — Project templates for C/C++ development
  - See [`build-system/README.md`](build-system/README.md) for toolchain setup

### Debug Tools
- **`debug/`** — GDB server and debugging utilities

### Assets
- **`assets/`** — Logos, diagrams, and documentation images


---

## Core Specifications

- **ISA:** RV32I Base + M, C, A, ZBA, ZBB, ZBC, ZBS, ZICNTR (partial)
- **Interrupts:** Stack-based - recursive
- **Verification:** Post-physical verified
- **Extensions:** Bit manipulation, atomic ops, compressed, and multiply/divide instructions

---

## MCU Peripherals - Configurable

- **System**
  - Clock Multiplexing/Dividing
  - 2 × Digitally Controlled Oscillator (DCO)
  - Watchdog Timer (WDT)
  - CRC engine
  - ROM/RAM power gating
- **Compute**  
  - 1 × HW-NN 
- **I/O**
  - 4 × GPIO
  - 1 × SPI
  - 1 × SPI Flash Extended Memory 
  - 2 × UART
  - 2 × Timer

---

## MCU Memory Architecture - Configurable

- **16 KiB ROM**
- **2 × 16 KiB SRAM**

---

## Interrupt Handling

- **Stack-based mechanism** enables recursive interrupt handling
- **Caution:** Recursive interrupts may lead to stack overflow if not managed

---

## Building and Toolchain

### Toolchain Requirements

VestaRV requires a RISC-V GCC cross-compiler:
- **Toolchain**: `riscv-none-elf-gcc` (version 13.2.0 or later recommended)
- **Architecture**: RV32I with M, C extensions

### Installation

Detailed toolchain setup instructions are available in [`build-system/README.md`](build-system/README.md).

**Quick Start:**
```bash
# Linux (using xPack)
wget https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v13.2.0-2/xpack-riscv-none-elf-gcc-13.2.0-2-linux-x64.tar.gz
tar -xf xpack-riscv-none-elf-gcc-13.2.0-2-linux-x64.tar.gz -C ~/riscv-toolchain/

# Set environment variable
export RISCV_TOOLCHAIN_DIR=~/riscv-toolchain/xpack-riscv-none-elf-gcc-13.2.0-2
```

### Building Firmware

```bash
# Build bootrom
cd firmware/bootrom
make all

# Build Forth interpreter
cd ../rv4th
make all
```

### Running Verification Tests

```bash
# Build and run ISA tests
cd verification/isa
make rv32ui        # Build RV32I user-level tests
make rv32um        # Build multiply/divide tests
make periph        # Build peripheral tests

# All RCF files for VHDL simulation are collected in rcf/
ls rcf/*.rcf
```

For more details, see:
- [`firmware/bootrom/makefile`](firmware/bootrom/makefile) - Bootrom build configuration
- [`verification/isa/README.md`](verification/isa/README.md) - ISA test documentation
- [`build-system/README.md`](build-system/README.md) - Complete toolchain guide

---

## Getting Started

1. **Clone the repository:**
   ```bash
   git clone https://github.com/maxxseminario/VestaRV.git
   cd VestaRV
   ```

2. **Install the RISC-V toolchain** (see [Building and Toolchain](#building-and-toolchain))

3. **Install Python dependencies:**
   ```bash
   pip install intelhex
   ```

4. **Build a firmware project:**
   ```bash
   cd firmware/bootrom
   make all
   ```

5. **Run verification tests:**
   ```bash
   cd verification/isa
   make rv32ui
   ```

6. **Simulate with VHDL** (requires simulator like Xcelium, ModelSim, or GHDL):
   - Point your testbench to `verification/isa/rcf/` for test programs
   - See `hdl/MCU/tb/` for example testbenches

---

## Author and Support

**Author:**  
_Maxx Seminario_    
PhD Student, Integrated Circuit Design  
Analog, Mixed-Signal, and System-on-Chip Design  
University of Nebraska-Lincoln    
Email: mseminario2@huskers.unl.edu  

If you need access, support, or have questions about VestaRV or its MCU subsystem, please reach out directly to the author via email. 

---

## License

VestaRV is released as open hardware under a permissive license (similar to MIT/ISC/BSD). See `LICENSE` for full details.
