# Blinky - VestaRV Test Application

Simple test application for verifying the RISC-V toolchain and Xcelium simulation workflow.

## Quick Start

*Legacy path.* The make flow in this section still works. The recommended
path is [Building with Bazel](#building-with-bazel) below.

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

## Building with Bazel

Bazel is the recommended path - it provisions the pinned RISC-V toolchain
itself and gates the image against a tracked golden. The `make` flow above
still works and is kept as the legacy path.

Run from the repo root:

```sh
sh tools/get_bazel.sh            # fetches bazelisk into tools/bin/bazel
tools/bin/bazel test //...       # first run downloads all toolchains
```

| Target | What it is / what it proves |
|--------|-----------------------------|
| `//software/blinky:blinky_elf` | Linked ELF with debug symbols (GDB) |
| `//software/blinky:blinky_bin` | Raw binary |
| `//software/blinky:blinky_hex` | Intel HEX image |
| `//software/blinky:blinky_dump` | Disassembly listing |
| `//software/blinky:blinky_rcf` | RCF image, no flash headers (the `make all` output) |
| `//software/blinky:blinky_flashed_rcf` | RCF with the SPI-flash protocol headers (the `make flash` output) |
| `//software/blinky:blinky_flashed_rcf_test` | Golden gate: proves the flashed image is byte-identical to `testdata/blinky_flashed_rcf_golden.txt` |

```sh
tools/bin/bazel build //software/blinky:blinky_flashed_rcf
tools/bin/bazel test  //software/blinky:blinky_flashed_rcf_test
```

Changing this firmware means regenerating
`testdata/blinky_flashed_rcf_golden.txt` in the same commit.

Full map of the Bazel build: [`BAZEL.md`](../../BAZEL.md).
Firmware conventions: [`software/README.md`](../README.md).

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

See `platform/myshkin/gcc/lib/linker/` for generated linker scripts and memory definitions.

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
