# VestaRV Software Development Workflow

Complete guide for developing, building, and simulating C applications for the VestaRV RISC-V processor.

## Overview

This workflow covers:
1. Creating new C projects
2. Compiling with the RISC-V toolchain
3. Generating RCF files for simulation
4. Running in Xcelium testbench

## Prerequisites

### 1. RISC-V Toolchain

Install the xPack RISC-V GCC toolchain:

```bash
# Download and extract
cd ~/riscv-toolchain
wget https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v13.2.0-2/xpack-riscv-none-elf-gcc-13.2.0-2-linux-x64.tar.gz
tar -xf xpack-riscv-none-elf-gcc-13.2.0-2-linux-x64.tar.gz

# Set environment variable
export RISCV_TOOLCHAIN_DIR=~/riscv-toolchain/xpack-riscv-none-elf-gcc-13.2.0-2

# Add to PATH
fish_add_path ~/riscv-toolchain/xpack-riscv-none-elf-gcc-13.2.0-2/bin
```

For bash/zsh:
```bash
echo 'export RISCV_TOOLCHAIN_DIR=~/riscv-toolchain/xpack-riscv-none-elf-gcc-13.2.0-2' >> ~/.bashrc
echo 'export PATH="$RISCV_TOOLCHAIN_DIR/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

See [tools/build/README.md](../../tools/build/README.md) for detailed installation instructions.

### 2. Platform Files

Ensure platform files are generated:

```bash
cd platform/python
python3 generate.py
```

This creates:
- Linker scripts in `platform/gcc/lib/linker/`
- Header files in `platform/gcc/lib/include/`
- Memory map definitions

## Creating a New Project

### Quick Create

```bash
cd software
make new PROJECT=myapp
```

This creates:
```
software/myapp/
├── src/
│   ├── main.c       # Application entry point
│   └── start.S      # Startup assembly
├── include/         # Project headers
├── obj/            # Build artifacts
├── bin/            # Output binaries
├── rcf/            # RCF files for simulation
└── makefile        # Build configuration
```

### Project Types

**RAM Application** (default):
```bash
make new PROJECT=myapp TYPE=ram
```
- Runs from RAM (0x8000+)
- Standard applications

**ROM Application** (bootloader):
```bash
make new PROJECT=bootloader TYPE=rom
```
- Runs from ROM (0x0000+)
- Bootloaders and firmware

## Building Your Application

### 1. Edit Source Code

```bash
cd software/myapp
# Edit src/main.c with your application logic
```

### 2. Build All Outputs

```bash
make all
```

**Outputs:**
- `bin/myapp.elf` - Executable with debug symbols
- `bin/myapp.bin` - Raw binary
- `bin/myapp.hex` - Intel HEX format
- `bin/myapp.dump` - Disassembly listing
- `rcf/myapp.rcf` - RCF format (raw)

### 3. Add Flash Headers

```bash
make flash
```

This runs `flash_prepend.sh` to add SPI flash protocol headers needed for the serial flash model in Xcelium.

**RCF Format After Flashing:**
```
00010000101011011011111011101111  # 0x10ADBEEF - Command word
00000000000000001000000000000000  # 0x00008000 - Start address
00000000000000001000000101001100  # End address
<program data...>
11001010111111101011101010111110  # 0xCAFEBABE - Execute command
```

### 4. Copy to Testbench

```bash
make sim
```

Copies the flashed RCF file to `verification/isa/rcf/` for use in Xcelium simulations.

## Complete Workflow Example

```bash
# 1. Create project
cd software
make new PROJECT=blinky

# 2. Write code
cd blinky
vim src/main.c

# 3. Build
make all

# 4. Add flash headers and copy to testbench
make flash
make sim

# 5. Run in Xcelium
cd ../../hdl/MCU/tb
# Update riscv_tb.vhd to load: "../../../verification/isa/rcf/xxxxxxxblinky.rcf"
# Run your Xcelium compilation and simulation scripts
```

## One-Command Workflow

The `sim` target automatically runs `flash`, so you can do:

```bash
make all       # Build everything
make sim       # Flash and copy to testbench (includes 'make flash')
```

## Memory Configuration

All projects use the platform-generated memory map:

| Region | Address Range | Size | Usage |
|--------|--------------|------|-------|
| ROM | 0x0000 - 0x3FFF | 16KB | Bootloader/firmware |
| Peripherals | 0x4000 - 0x4FFF | 4KB | Memory-mapped I/O |
| RAM | 0x8000 - 0xFFFF | 32KB | Program + data + stack |

See `platform/config/MemoryMap.json` for full memory map.

## Using Platform Headers

Projects automatically include platform-generated headers:

```c
#include "MemoryMap.h"   // Peripheral addresses and registers
#include "periph.h"      // Peripheral definitions (auto-generated)
```

Example:
```c
#include <stdint.h>
#include "MemoryMap.h"

int main(void) {
    // Access GPIO0 at address from MemoryMap.h
    volatile uint32_t *gpio = (uint32_t*)ADDR_GPIO0_SLOT;
    *gpio = 0xFF;  // Set all pins high
    
    while(1) {
        // Application loop
    }
}
```

## Advanced Usage

### Custom Compiler Flags

Edit your project's `makefile`:

```makefile
CFLAGS += -O3 -ffunction-sections
LDFLAGS += -Wl,--gc-sections
```

### Adding Library Code

```makefile
LIB_SOURCES = uart.c gpio.c timer.c
```

Library files go in `commune/src/` with headers in `commune/include/`.

### Custom Linker Script

Override the default linker script:

```makefile
LD_SCRIPT = ./custom.ld
```

## Troubleshooting

### RISC-V Toolchain Not Found

```
Error: RISCV_TOOLCHAIN_DIR is not set
```

**Solution:**
```bash
export RISCV_TOOLCHAIN_DIR=~/riscv-toolchain/xpack-riscv-none-elf-gcc-13.2.0-2
```

### Platform Files Missing

```
Error: Cannot find platform/gcc/lib/linker/MCU.ld
```

**Solution:**
```bash
cd platform/python
python3 generate.py
```

### RCF File Wrong Size

```
Error: myapp.rcf has wrong number of lines
```

**Solution:** Check `MEM_SIZE` in makefile matches your memory configuration (default: 0x14000 = 80KB).

### Flash Headers Not Added

If simulation doesn't execute, ensure you ran `make flash`:

```bash
# Check first line of RCF file
head -1 rcf/*myapp.rcf
# Should be: 00010000101011011011111011101111
```

## See Also

- [tools/build/README.md](../../tools/build/README.md) - Toolchain setup
- [platform/README.md](../../platform/README.md) - Platform generator
- [verification/isa/README.md](../../verification/isa/README.md) - ISA tests
- [hdl/README.md](../../hdl/README.md) - RTL testbenches
