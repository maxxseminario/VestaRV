<table border="0" cellspacing="0" cellpadding="0">
  <tr>
    <td>
      <img src="assets/vesta_logo_light.png#gh-light-mode-only" alt="VestaRV32 logo" height="80" />
      <img src="assets/vesta_logo_dark.png#gh-dark-mode-only" alt="VestaRV32 logo" height="80" />
    </td>
    <td style="padding-left:12px;">
      <h1 style="margin:0;">VestaRV - A Custom RISC-V Core &amp; SoC</h1>
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

### Implementations
- **`implementations/`** — ASIC and FPGA instantiations of VestaRV
  - `asic/` — ASIC tape-out documentation and configurations
  - `fpga/` — FPGA board implementations
  - See [`implementations/README.md`](implementations/README.md) for structure details

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

## Quick Start

1. **Clone the repository:**
   ```bash
   git clone https://github.com/maxxseminario/VestaRV.git
   cd VestaRV
   ```

2. **Install RISC-V toolchain and dependencies:**

   See [`build-system/README.md`](build-system/README.md) for complete toolchain setup.

3. **Build firmware:**
   ```bash
   cd firmware/bootrom
   make all
   ```

4. **Run verification tests:**
   ```bash
   cd verification/isa
   make rv32ui
   ```
   See [`verification/isa/README.md`](verification/isa/README.md) for test details.

5. **VHDL Simulation:**
   - Test programs (RCF format): `verification/isa/rcf/`
   - Example testbenches: `hdl/MCU/tb/`

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
