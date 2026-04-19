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

### **`commune/`** — Shared Libraries and Headers
Communal code shared across firmware projects:
- **`include/`** — Header files for peripherals, register definitions, system macros
- **`src/`** — Reusable library code

**Note**: This directory is excluded from the repository (see `.gitignore`) as it may contain chip-specific generated code.

## Adding New Firmware Projects

### Quick Start with Project Generator

The easiest way to create a new firmware project is using the provided Makefile:

```bash
cd firmware/
make new PROJECT=my-app          # Create RAM-based application
make new PROJECT=my-boot TYPE=rom # Create ROM-based bootloader
```

This automatically creates:
- Complete directory structure (src/, include/, obj/, bin/)
- Configured makefile with all build targets
- Template source files (main.c, start.S)

**Available Commands:**
```bash
make help          # Show all available commands
make new PROJECT=<name> [TYPE=ram|rom]  # Create new project
make list          # List all firmware projects
make build-all     # Build all projects
make clean-all     # Clean all projects
```

## Build System

### Top-Level Makefile Commands

The `firmware/Makefile` provides project management:

| Command | Description |
|---------|-------------|
| `make help` | Show all available commands |
| `make new PROJECT=<name>` | Create new project (default: RAM-based) |
| `make new PROJECT=<name> TYPE=rom` | Create ROM-based project |
| `make list` | List all firmware projects |
| `make build-all` | Build all projects |
| `make clean-all` | Clean all projects |

### Project Makefile Variables

Each project has its own makefile with these key variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `TARGET` | Output binary name | `flashboot` |
| `SRC_SOURCES` | Project source files | `main.c uart.c start.S` |
| `LIB_SOURCES` | Library source files from common/ | `gpio.c spi.c` |
| `EXTENSIONS` | RISC-V ISA extensions | `imac` (I+M+A+C) |
| `LD_SCRIPT` | Linker script path | `MCU-bootrom.ld` or `MCU.ld` |

### Build Targets

Within each project directory:

```bash
make all          # Build all outputs (.elf, .bin, .hex, .dump, .rcf)
make clean        # Remove build artifacts
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

Peripheral base addresses and register definitions are in `commune/include/` (generated per chip configuration).

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

1. **Create project** (if new):
   ```bash
   cd firmware/
   make new PROJECT=my-app
   cd my-app/
   ```

2. **Write code** in `src/` directory:
   - Edit `src/main.c` with your application logic
   - Add peripheral headers as needed
   - Modify `src/start.S` if custom startup required

3. **Update makefile** (if needed):
   - Add source files to `SRC_SOURCES`
   - Add library dependencies to `LIB_SOURCES`
   - Adjust `EXTENSIONS` for required ISA features

4. **Build firmware**:
   ```bash
   make all
   ```

5. **Test in simulation**:
   - Use `.rcf` file with VHDL testbench
   - See `hdl/MCU/tb/` for testbench examples

6. **Program hardware**:
   - Use `.bin` or `.hex` file
   - Flash via SPI programmer or JTAG

7. **Debug**:
   - Use `.elf` file with GDB
   - UART console output for printf-style debugging
   - See [`debug/`](../debug/) for debugging tools

## Requirements

- **RISC-V Toolchain**: `riscv-none-elf-gcc` (see [`build-system/README.md`](../build-system/README.md))
- **Python 3**: For build utilities and RCF generation
- **Make**: GNU Make for build automation

## Example: Creating a Blink Project

```bash
# Create new project
cd firmware/
make new PROJECT=blinky

# Navigate to project
cd blinky/

# Edit main.c with blinky code
cat > src/main.c << 'EOF'
#include <stdint.h>

// Simple GPIO register definitions
#define GPIO_BASE 0x4000
#define GPIO_OUT  (*(volatile uint32_t*)(GPIO_BASE + 0x00))
#define GPIO_DIR  (*(volatile uint32_t*)(GPIO_BASE + 0x04))

int main(void) {
    // Set GPIO pin 0 as output
    GPIO_DIR = 0x01;
    
    // Blink loop
    while(1) {
        GPIO_OUT = 0x01;  // LED on
        for(volatile int i=0; i<500000; i++);
        GPIO_OUT = 0x00;  // LED off
        for(volatile int i=0; i<500000; i++);
    }
    
    return 0;
}
EOF

# Build
make all

# Output files created in bin/
ls bin/
# blinky.elf  blinky.bin  blinky.hex  blinky.dump  blinky.rcf  blinky.map
```

## Related Documentation

- [`build-system/README.md`](../build-system/README.md) — Toolchain setup and build utilities
- [`build-system/linker-scripts/`](../build-system/linker-scripts/) — Memory layout configuration
- [`verification/isa/README.md`](../verification/isa/README.md) — Test programs as code examples
- [`implementations/`](../implementations/) — Chip-specific configurations and memory maps
- [`hdl/MCU/tb/`](../hdl/MCU/tb/) — VHDL testbench examples for simulation


