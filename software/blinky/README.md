# Blinky - VestaRV Test Application

Simple test application for verifying the RISC-V toolchain and Xcelium simulation workflow.

## Building with Bazel

Bazel builds this application: it provisions the pinned RISC-V toolchain
itself and gates the image against a tracked golden.

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
| `//software/blinky:blinky_rcf` | RCF image, no flash headers |
| `//software/blinky:blinky_flashed_rcf` | RCF with the SPI-flash protocol headers prepended |
| `//software/blinky:blinky_flashed_rcf_test` | Golden gate: proves the flashed image is byte-identical to `testdata/blinky_flashed_rcf_golden.txt` |

```sh
tools/bin/bazel build //software/blinky:blinky_flashed_rcf
tools/bin/bazel test  //software/blinky:blinky_flashed_rcf_test
```

Changing this firmware means regenerating
`testdata/blinky_flashed_rcf_golden.txt` in the same commit.

Full map of the Bazel build: [`BAZEL.md`](../../BAZEL.md).
Firmware conventions: [`software/README.md`](../README.md).

## Memory Map

The application uses the platform-generated memory configuration:

- **ROM**: 0x0000 - 0x1FFF (8KB)
- **Peripherals**: 0x4000 - 0x4FFF (4KB)  
- **RAM**: 0x8000 - 0xFFFF (32KB)

See `platform/myshkin/gcc/lib/linker/` for generated linker scripts and memory definitions.

## Xcelium Simulation

The Xcelium testbench is outside Bazel - it needs the licensed Cadence tools.
Copy the built flashed RCF image into `verification/isa/rcf/`, then point the
testbench at it:

```vhdl
constant RCF_FILE : string := "../../../verification/isa/rcf/xxxxxxxblinky.rcf";
```

The filename will be padded to 22 characters with leading 'x' characters.
