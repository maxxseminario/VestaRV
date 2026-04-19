# Build System

This directory contains the build infrastructure for the Vestarv RISC-V processor.

## Contents

- **linker-scripts/** - Linker scripts for different memory configurations (bootrom, main MCU)
- **makefiles/** - Common makefiles and build configuration
- **scripts/** - Build and conversion utilities (Python scripts for hex conversion, RCF generation, etc.)
- **templates/** - Project templates for C, C++, and testbench code

## Toolchain Setup

### Required Toolchain

Vestarv requires the RISC-V GCC cross-compiler:
- **Toolchain**: `riscv-none-elf-gcc`
- **Version**: 13.2.0 or later recommended
- **Architecture**: RV32I (base integer instruction set)

### Installation

#### Linux
Download and install the xPack RISC-V toolchain:
```bash
# Download xPack releases from:
# https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases

# Extract to your preferred location (e.g., ~/riscv-toolchain/)
tar -xf xpack-riscv-none-elf-gcc-*.tar.gz -C ~/riscv-toolchain/
```

#### macOS
Install via Homebrew or xPack:
```bash
# Using Homebrew
brew tap riscv/riscv
brew install riscv-tools

# Or download xPack release (same as Linux)
```

#### Windows
Use Windows Subsystem for Linux (WSL) or download xPack release:
```bash
# In WSL, follow Linux instructions
# Or use xPack on Windows directly
```

### Configuration

Set the toolchain path in makefiles or environment variable:
```bash
export RISCV_TOOLCHAIN_DIR=~/riscv-toolchain/xpack-riscv-none-elf-gcc-13.2.0-2
```

Or edit the `RISCV_DIR` variable in project makefiles (e.g., `firmware/bootrom/makefile`).

### Python Dependencies

Some build scripts require Python packages:
```bash
pip install intelhex
```

## Building Firmware

Navigate to the firmware project you want to build:
```bash
cd ../firmware/bootrom
make all
```

See individual firmware project directories for specific build instructions.
