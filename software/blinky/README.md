# Blinky - VestaRV Test Application

Simple test application for verifying the RISC-V toolchain and Xcelium simulation workflow.

## Quick Start

### 1. Build the Application
```bash
make all
```

This will:
- Compile C and assembly source files
- Link with platform-generated headers and linker scripts
- Generate ELF, binary, hex, dump, and RCF files

### 2. Prepare for Simulation
```bash
make flash
```

This adds SPI flash protocol headers to the RCF file, required for Xcelium simulation.

### 3. Copy to Testbench
```bash
make sim
```

This copies the flashed RCF file to `verification/isa/rcf/` for use in the testbench.

## Build Outputs

- `bin/blinky.elf` - Executable and Linkable Format (with debug symbols)
- `bin/blinky.bin` - Raw binary
- `bin/blinky.hex` - Intel HEX format
- `bin/blinky.dump` - Disassembly listing
- `bin/blinky_padded.bin` - Binary padded to full memory size
- `rcf/blinky.rcf` - RCF format (without flash headers)
- `rcf/*blinky.rcf` - RCF with flash headers (after `make flash`)

## Memory Map

The application uses the platform-generated memory configuration:

- **ROM**: 0x0000 - 0x3FFF (16KB)
- **Peripherals**: 0x4000 - 0x4FFF (4KB)  
- **RAM**: 0x8000 - 0xFFFF (32KB)

See `platform/gcc/lib/linker/` for generated linker scripts and memory definitions.

## Xcelium Simulation

After running `make sim`, update your VHDL testbench to load the RCF file:

```vhdl
constant RCF_FILE : string := "../../../verification/isa/rcf/xxxxxxxblinky.rcf";
```

The filename will be padded to 22 characters with leading 'x' characters.

## Clean Build

```bash
make clean
```

Removes all build artifacts (obj/, bin/, rcf/ directories).
