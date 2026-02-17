# VestaRV Firmware

This directory contains firmware projects for the VestaRV processor. These are embedded software applications designed to run directly on the VestaRV core, either in ROM (bootloader/system firmware) or loaded into RAM (user applications).

## Directory Structure

### **`bootrom/`** — Boot ROM Firmware
System boot code and Forth interpreter embedded in ROM. This firmware runs on reset and provides:
- Hardware initialization
- Boot sequence management
- Interactive Forth interpreter for development and testing
- SPI flash memory access
- UART communication for host interaction

**Memory Location**: ROM (typically at address 0x0000)  
**Purpose**: System initialization and interactive programming environment

### **`common/`** — Shared Libraries and Headers
Common code shared across firmware projects:
- **`include/`** — Header files for peripherals, register definitions, system macros
- **`src/`** — Reusable library code

**Note**: This directory is excluded from the repository (see `.gitignore`) as it may contain chip-specific generated code.

## Adding New Firmware Projects

To create a new firmware project:

1. **Create project directory**:
   ```bash
   mkdir firmware/my-project
   cd firmware/my-project
   ```

2. **Set up standard structure**:
   ```
   my-project/
   ├── makefile          # Build configuration
   ├── src/              # Source files (.c, .S)
   ├── include/          # Project-specific headers
   ├── obj/              # Build artifacts (auto-generated)
   └── bin/              # Output binaries (auto-generated)
   ```

3. **Configure makefile**:
   - Set `TARGET` name
   - List source files in `SRC_SOURCES` and `LIB_SOURCES`
   - Specify RISC-V extensions in `EXTENSIONS` (e.g., `i`, `im`, `imac`)
   - Choose linker script: `MCU-bootrom.ld` (ROM) or `MCU.ld` (RAM)
   - Reference common libraries: `LIB_DIR = ../common`

4. **Build**:
   ```bash
   make all
   ```

## Build System

### Makefile Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `TARGET` | Output binary name | `flashboot` |
| `SRC_SOURCES` | Project source files | `main.c uart.c start.S` |
| `LIB_SOURCES` | Library source files from common/ | `gpio.c spi.c` |
| `EXTENSIONS` | RISC-V ISA extensions | `imac` (I+M+A+C) |
| `LD_SCRIPT` | Linker script path | `MCU-bootrom.ld` or `MCU.ld` |

### Build Targets

```bash
make all          # Build all outputs (.elf, .bin, .hex, .dump, .rcf)
make clean        # Remove build artifacts
make <target>.elf # Build specific target
```

### Output Files

| File Type | Description | Use Case |
|-----------|-------------|----------|
| `.elf` | Executable with debug symbols | Debugging, GDB |
| `.bin` | Raw binary | Programming flash |
| `.hex` | Intel HEX format | Programming tools |
| `.dump` | Disassembly listing | Code inspection |
| `.rcf` | ROM Configuration File | VHDL simulation |

## Memory Layout

Firmware uses linker scripts to define memory organization:

Memory sizes are configurable per implementation. See linker scripts in [`build-system/linker-scripts/`](../build-system/linker-scripts/).

## Peripheral Access

Firmware accesses peripherals through memory-mapped registers. Common peripherals:

- **GPIO** — General-purpose I/O pins
- **UART** — Serial communication
- **SPI** — Serial Peripheral Interface
- **I2C** — Inter-Integrated Circuit
- **Timer** — Hardware timers with PWM
- **NPU** — Neural processing unit (if available)
- **ADC/DAC** — Analog interfaces (if available)

Peripheral base addresses and register definitions are in `common/include/` (generated per chip configuration).

## Programming Languages

### C
Primary language for firmware development:
- Standard C library subset (no malloc, limited stdio)
- Direct hardware register access
- Interrupt service routines
- Efficient code generation with RISC-V GCC

### Assembly
Used for:
- Startup code (`start.S`)
- Low-level initialization
- Critical timing sections
- Direct CSR (Control and Status Register) access

## Development Workflow

1. **Write code** in `src/` directory
2. **Build firmware**:
   ```bash
   cd firmware/<project>/
   make all
   ```
3. **Test in simulation**:
   - Use `.rcf` file with VHDL testbench
   - See `hdl/MCU/tb/` for testbench examples
4. **Program hardware**:
   - Use `.bin` or `.hex` file
   - Flash via SPI programmer or JTAG
5. **Debug**:
   - Use `.elf` file with GDB
   - UART console output for printf-style debugging
   - See [`debug/`](../debug/) for debugging tools

## Requirements

- **RISC-V Toolchain**: `riscv-none-elf-gcc` (see [`build-system/README.md`](../build-system/README.md))
- **Python 3**: For build utilities and RCF generation
- **Make**: GNU Make for build automation

## Typical Applications

- **System bootloader** — Initialize hardware, load applications
- **Sensor interface** — Read sensors, process data
- **Communication gateway** — UART, SPI, I2C bridging
- **Control systems** — Motor control, PWM generation
- **Data logging** — Collect and store sensor data
- **ML inference** — Edge computing with NPU acceleration

## Related Documentation

- [`build-system/README.md`](../build-system/README.md) — Toolchain setup and build utilities
- [`build-system/linker-scripts/`](../build-system/linker-scripts/) — Memory layout configuration
- [`verification/isa/README.md`](../verification/isa/README.md) — Test programs as code examples
- [`implementations/`](../implementations/) — Chip-specific configurations and memory maps
- [`hdl/MCU/tb/`](../hdl/MCU/tb/) — VHDL testbench examples for simulation


