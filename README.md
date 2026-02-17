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

VestaRV is a custom 32-bit RISC-V processor core designed as an independent personal project, built from the ground up using the official RISC-V instruction set specification without deriving from any existing core implementations. The core supports **RV32I base ISA** with **M** (multiply/divide), **C** (compressed), **A** (atomic), and **Zb*** (bit manipulation) extensions, features **stack-based recursive interrupt handling**, and has been **post-Innovus verified**. This repository provides both the VestaRV core and a configurable MCU System on Chip (SoC) implementation, enabling rapid integration into embedded systems and ASIC designs.

**Namesake:**  
VestaRV is named after **Vesta**, the Roman goddess of hearth, home, and the eternal flame. As Vesta's fire symbolized the heart of the household, VestaRV is designed to be the heart of your embedded system—providing reliability and a strong foundation for your MCU and SoC projects.

**Typical Applications:**
- Custom embedded MCU development
- Mixed-signal and sensor interfacing
- Low-power IoT devices
- ASIC/SoC integration

---

## Example MCU Configuration

Below is an example MCU-level block diagram showing one possible instantiation of VestaRV with various peripherals:

![MCU Block Diagram](assets/ASIC_block_diagram.png)

*Note: VestaRV is designed to be highly configurable. The peripheral set, memory architecture, and system features can be customized to match your specific application requirements.*

---

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

## Example Peripheral Configuration

The following peripherals are included in the example configuration shown above. VestaRV's modular design allows you to select and configure peripherals based on your application needs:

- **System Control**
  - Clock multiplexing and dividing
  - Digitally Controlled Oscillators (DCO)
  - Watchdog Timer (WDT)
  - CRC calculation engine
  - Power gating for ROM/RAM blocks
- **Compute Accelerators**  
  - Hardware Neural Network (HW-NN) accelerator
- **Communication & I/O**
  - GPIO ports (configurable count)
  - SPI interfaces
  - SPI Flash extended memory interface
  - UART modules
  - Timer/Counter modules

---

## Memory Architecture (Example)

The example configuration includes:
- **16 KiB ROM** — Boot code and firmware
- **32 KiB SRAM** (2 × 16 KiB blocks) — Main system memory

*Memory sizes and organization are fully configurable to meet your design requirements.*

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
