# Build System

This directory contains the build infrastructure for the Vestarv RISC-V processor.

## Contents

- **linker-scripts/** - Linker scripts for different memory configurations (bootrom, main MCU).
  The two `.ld` files are hand written. The `memory.x` / `periph.x` / `*_START.txt` /
  `*_SIZE.txt` files are NOT a copy of the chip generator's current output: they are the
  frozen link environment the taped-out `rom2k_hvt_pg` mask plate was compiled from, and
  `software/bootrom_mp` will not link against the current output at all. Refreshing them
  relinks the boot image and invalidates the plate. See the comment in `BUILD.bazel` and
  `//tools/build:rom_plate_link_env_test`
- **makefiles/** - Common makefiles and build configuration
- **scripts/** - Build and conversion utilities (Python scripts for hex conversion, RCF generation, etc.)
- **templates/** - Project templates for C, C++, and testbench code

## Building with Bazel

Bazel builds the firmware, and it needs no toolchain installed on the host: it
fetches and pins the RISC-V cross-compiler itself, so a fresh clone compiles
firmware with nothing installed locally. The host toolchain install documented
under "Outside Bazel" below is needed only for the work Bazel does not cover.

Run everything from the repo root:

```sh
sh tools/get_bazel.sh            # fetches bazelisk into tools/bin/bazel
tools/bin/bazel test //...       # first run downloads all toolchains
```

### Targets in this directory

| Target | What it is / what it proves |
|--------|-----------------------------|
| `//tools/build:bin2rcf` | The single canonical bin -> RCF converter, runnable with `bazel run`. It replaces the five divergent `od`+`awk` copies that used to live in the makefiles, and is byte-verified against the pinned boot-ROM RCF artifact |
| `//tools/build:rcf_flash` | Out-of-place port of `verification/isa/flash_prepend.sh`: prepends the SPI-flash protocol headers to an RCF. Byte-verified against the bash original's output |
| `//tools/build:linker_scripts` | The shared linker scripts as one filegroup - the `.ld` files `INCLUDE` `memory.x` / `periph.x` and the `*_START`/`*_SIZE` fragments, so they must travel together |
| `//tools/build:rom_plate_link_env_test` | Pins how far the frozen link environment in `linker-scripts/` may drift from the live chip memory map (`//platform/common:castalia_linker_scripts`). The two are known to differ and the recorded difference is `testdata/rom_plate_link_env.diff`; the test fails when that difference changes |

Both scripts are exercised end to end by the firmware golden gates rather than
by unit tests: every firmware image in `//software/...` is produced through them
and compared byte-for-byte against a tracked golden.

```sh
tools/bin/bazel build //tools/build:bin2rcf //tools/build:rcf_flash
tools/bin/bazel test  //software/...        # proves both scripts against the goldens
```

Full map of the Bazel build: [`BAZEL.md`](../../BAZEL.md).

## Outside Bazel

Some work in this repo runs outside Bazel and needs a `riscv-none-elf-`
toolchain on the host: the Cadence simulations (`platform/common`'s
`make verify`, the Xcelium and lockstep gates) and the bench and programmer
tools. Those are the only reasons
to install one - the Bazel build fetches its own pinned copy and ignores
`RISCV_TOOLCHAIN_DIR`.

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

### Python Dependencies

The bench and programmer host tools (`tools/chip_programmer/`,
`tools/flash_programmer/`, `tools/PyEmanate/`) read Intel HEX images with a host
Python package:
```bash
pip install intelhex
```
Those three are untracked as of 2026-08-27 and live only on the bench machine;
a clone does not carry them.

Bazel supplies its own hermetic Python and needs none of this.

## Building Firmware

See [`software/README.md`](../../software/README.md) for the firmware targets
and the per-app conventions.
