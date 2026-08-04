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

VestaRV is a custom 32-bit RISC-V processor core designed as an independent personal project, built from the ground up using the official RISC-V instruction set specification without deriving from any existing core implementations. The core implements **RV32IMAC** with the **Zba/Zbb/Zbc/Zbs** bit-manipulation extensions and the standard **M-mode trap architecture**, and features **stack-based recursive interrupt handling**.

Beyond the single core, this repository is a **chip generator**: a family of SoCs emitted from one configuration source. A config file selects the hart count, the ISA extensions, and which peripherals exist; `make chip` then produces the RTL, the C headers, the linker scripts and the Technical Reference Manual together, and `make verify` proves that configuration boots.

Three chips have been built from it:

| Chip | Harts | Status |
|------|-------|--------|
| **Myshkin** | 1 | **Taped out** — TSMC 65nm, November 2025; silicon validated |
| **Castalia** | 4 | Tape-out-ready — shared-memory multiprocessor |
| **Argus** | 18 | Tape-out-ready — teaching chip |

> 📄 **[Technical Reference Manual — Castalia (revised August 4, 2026)](implementations/asic/castalia/docs/TRM.pdf)**  
> Complete peripheral register reference, system architecture, and programming guide for the Castalia SoC — the 4-hart multi-core VestaRV MCU (TSMC 65nm, tape-out-ready). This is the current manual, generated from the chip configuration by `platform/common`.  
> Also available: the [Myshkin TRM v1.0.0](implementations/asic/myshkin-2025-11/docs/TRM.pdf), documenting the first VestaRV tape-out (TSMC 65nm, November 2025).

> 🏷️ **Current version: v2.10.1** — the multi-core Castalia line, tape-out-ready.  
> Silicon to date is **v1.0.0** (Myshkin, TSMC 65nm, November 2025); the `2.x` line has not been fabricated. Full history in the [changelog](CHANGELOG.md).

**Namesake:**  
VestaRV is named after **Vesta**, the Roman goddess of hearth, home, and the eternal flame. As Vesta's fire symbolized the heart of the household, VestaRV is designed to be the heart of your embedded system—providing reliability and a strong foundation for your MCU and SoC projects.

**Typical Applications:**
- Custom embedded MCU development
- Mixed-signal and sensor interfacing
- ASIC/SoC integration
- Low-power IoT devices


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
- **`software/`** — Embedded firmware projects
  - `bootrom/` — Boot ROM code and Forth interpreter
  - `rv4th/` — Standalone Forth interpreter

### Platform Definition
- **`platform/`** — Automated toolchain generation system
  - Generates C headers, linker scripts, documentation from single source
  - Run `cd platform && make` or see [`platform/myshkin/README.md`](platform/myshkin/README.md)
  - Single Python script defines entire memory map and peripherals
  
### Verification
- **`verification/`** — Test suites and verification infrastructure
  - `isa/` — RISC-V instruction-level tests (adapted from [riscv-tests](https://github.com/riscv-software-src/riscv-tests))
    - Organized into `tests/` (source) and `build/` (artifacts)
    - Central `rcf/` directory for VHDL simulation files
  - `benchmarks/` — Performance benchmarking tests
  - `env/` — Test environment and linker scripts

### Tools & Build System
- **`tools/`** — Development tools and build infrastructure
  - `build/` — Build system and linker scripts
  - `debug/` — GDB server and debugging utilities
  - See [`tools/build/README.md`](tools/build/README.md) for toolchain setup

### Implementations
- **`implementations/`** — ASIC and FPGA instantiations of VestaRV
  - `asic/` — ASIC tape-out documentation and configurations
  - `fpga/` — FPGA board implementations
  - See [`implementations/README.md`](implementations/README.md) for structure details

### Assets
- **`assets/`** — Logos, diagrams, and documentation images


---

## Core Specifications

**Always built** (the default configuration of every chip):

- **ISA:** RV32I base + **M** (multiply/divide, fast multiplier) + **A** (atomics, incl. LR/SC) + **C** (compressed) + **Zba/Zbb/Zbc/Zbs** (bit manipulation)
- **Privilege:** M-mode trap architecture — `mstatus`/`mtvec`/`mie`/`mip`/`mscratch`/`mepc`/`mcause`/`mtval`, MRET/ECALL/EBREAK, vectored exceptions and interrupts
- **Interrupts:** Stack-based recursive interrupt handling

**Selectable per configuration** (each generates its hardware away when off, and traps as an illegal instruction; a read-only `misa` advertises the built set):

- **Compute:** `Zfinx` single-precision FPU in the x-registers · `Zicond` conditional ops
- **Crypto:** `Zkn` (AES + SHA) · `Zbkb` · `Zbkc` · `Zbkx`
- **Code size:** `Zcmp` · `Zcmt` · `Zcb`
- **Memory / atomics:** `Zicboz` cache-block zero · `Zabha` · `Zacas` · `Zawrs`
- **Privilege:** **U-mode** · **PMP** (Smpmp, configurable entry count)
- **Counters:** `Zicntr` · `Zihpm` · 64-bit counters · `Zihint` · `Zimop`

**Verification:** post-physical (gate-level, SDF-annotated) verified; a per-instruction **Spike lockstep co-simulation**; a 28-row configuration matrix that builds and simulates every shipped knob combination; and formal PSL properties on the core's leaf units. See the [changelog](CHANGELOG.md) for what each programme added.

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

2. **Generate toolchain files:**
   ```bash
   cd platform
   make
   ```
   This creates headers, linker scripts, and documentation. See [`platform/myshkin/README.md`](platform/myshkin/README.md) for details.

3. **Install RISC-V toolchain and dependencies:**

   See [`tools/build/README.md`](tools/build/README.md) for complete toolchain setup.

4. **Build firmware:**
   ```bash
   cd software/bootrom
   make all
   ```

5. **Run verification tests:**
   ```bash
   cd verification/isa
   make rv32ui
   ```
   See [`verification/isa/README.md`](verification/isa/README.md) for test details.

6. **VHDL Simulation:**
   See [`hdl/README.md`](hdl/README.md) for complete GHDL/ModelSim setup, compile order, and step-by-step instructions to run a simulation against the ISA test suite.

---

## Open-source simulation & verification

A fully open-source path — GHDL + cocotb + the riscv-tests-derived ISA suite, no
proprietary EDA licenses required — verifies the `vesta` core RTL end-to-end:

```bash
git clone https://github.com/maxxseminario/VestaRV.git && cd VestaRV
./opensource_sim/setup_env.sh && source opensource_sim/env.sh
./opensource_sim/run_sim.sh
```

See [`opensource_sim/README.md`](opensource_sim/README.md) for the full flow (cocotb
smoke test + ISA regression) and [`sky130/README.md`](sky130/README.md) for the
companion open-source flow that takes the same RTL to a signed-off sky130 GDSII.

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

VestaRV is released under the **MIT License**. See [`LICENSE`](LICENSE) for full details.
