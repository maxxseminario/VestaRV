# Quick Start Guide - VestaRV Software Development

## For First-Time Users

### 1. Setup Toolchain (One Time)

```bash
# Download and install RISC-V GCC
cd ~/riscv-toolchain
wget https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v13.2.0-2/xpack-riscv-none-elf-gcc-13.2.0-2-linux-x64.tar.gz
tar -xf xpack-riscv-none-elf-gcc-13.2.0-2-linux-x64.tar.gz

# Set environment (add to ~/.bashrc or ~/.config/fish/config.fish)
export RISCV_TOOLCHAIN_DIR=~/riscv-toolchain/xpack-riscv-none-elf-gcc-13.2.0-2
fish_add_path ~/riscv-toolchain/xpack-riscv-none-elf-gcc-13.2.0-2/bin
```

### 2. Test the Example

```bash
cd software/blinky
make all      # Build everything
make flash    # Add SPI flash headers
make sim      # Copy to testbench directory
```

### 3. Create Your Own Project

```bash
cd software
make new PROJECT=myapp
cd myapp
# Edit src/main.c with your code
make sim
```

## Make Targets

| Command | What It Does |
|---------|-------------|
| `make all` | Compile and generate all output files |
| `make flash` | Add SPI flash protocol headers to RCF |
| `make sim` | Flash + copy RCF to testbench (runs `make flash` automatically) |
| `make clean` | Remove all build artifacts |
| `make help` | Show available targets |

## Output Files

After `make all`:
- **bin/myapp.elf** - Executable with debug symbols (9.9KB)
- **bin/myapp.bin** - Raw binary (60 bytes for minimal app)
- **bin/myapp.hex** - Intel HEX format
- **bin/myapp.dump** - Disassembly listing
- **rcf/myapp.rcf** - RCF format (no headers yet)

After `make flash`:
- **rcf/xxxxxxxxxxxxmyapp.rcf** - RCF with SPI flash headers, ready for simulation

## Example C Code

```c
#include <stdint.h>
#include "MemoryMap.h"  // Platform-generated peripheral addresses

int main(void) {
    // Access GPIO peripheral
    volatile uint32_t *gpio = (uint32_t*)ADDR_GPIO0_SLOT;
    
    while(1) {
        *gpio = 0xFF;  // Turn on all pins
        for(volatile int i = 0; i < 100000; i++);  // Delay
        *gpio = 0x00;  // Turn off all pins
        for(volatile int i = 0; i < 100000; i++);  // Delay
    }
    
    return 0;
}
```

## Xcelium Simulation

After `make sim`, your RCF file is in `verification/isa/rcf/`.

Update your VHDL testbench (e.g., `hdl/MCU/tb/tb_defs.vhd`):

```vhdl
constant test_files : file_array := (
    "../../../verification/isa/rcf/xxxxxxxxxxxxmyapp.rcf",
    -- other tests...
);
```

Then run your Xcelium simulation scripts.

## Common Issues

**"RISCV_TOOLCHAIN_DIR is not set"**
```bash
export RISCV_TOOLCHAIN_DIR=~/riscv-toolchain/xpack-riscv-none-elf-gcc-13.2.0-2
```

**"cannot find riscv-none-elf-gcc"**
```bash
fish_add_path ~/riscv-toolchain/xpack-riscv-none-elf-gcc-13.2.0-2/bin
```

**"Linker script not found"**
- Linker scripts are in `tools/build/linker-scripts/`
- Makefile automatically uses them

**"RCF file doesn't execute in simulation"**
- Did you run `make flash`?
- Check first line should be: `00010000101011011011111011101111`

## More Information

- **Complete Workflow**: See [WORKFLOW.md](WORKFLOW.md)
- **Build System Details**: See [BUILD_SYSTEM_SUMMARY.md](BUILD_SYSTEM_SUMMARY.md)
- **Toolchain Setup**: See [../tools/build/README.md](../tools/build/README.md)
- **Project-Specific Help**: Run `make help` in any project directory
