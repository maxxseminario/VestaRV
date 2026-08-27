# VestaRV Firmware

This directory contains firmware projects for the VestaRV processor. These are embedded software applications designed to run directly on the VestaRV core, either in ROM (bootloader/system firmware) or loaded into RAM (user applications).

## Quick Start

**Try the blinky example**, from the repo root:
```bash
sh tools/get_bazel.sh
tools/bin/bazel build //software/blinky:blinky_flashed_rcf
```

## Building with Bazel

Bazel builds every firmware image here. It provisions the pinned RISC-V
cross-compiler itself, so a fresh clone needs no locally installed toolchain,
and every image is built in a sandbox and checked against a tracked golden.

Run everything from the repo root:

```sh
sh tools/get_bazel.sh            # fetches bazelisk into tools/bin/bazel
tools/bin/bazel test //...       # first run downloads all toolchains
```

### Per-app targets

Every firmware app builds the same artifact set. Substitute the app's package
for `PKG` and its target name for `NAME` (the two app rows below give both):

| Target | What it is / what it proves |
|--------|-----------------------------|
| `PKG:NAME_elf` | Linked ELF with debug symbols |
| `PKG:NAME_bin` | Raw binary |
| `PKG:NAME_hex` | Intel HEX image |
| `PKG:NAME_dump` | Disassembly listing |
| `PKG:NAME_rcf` | RCF image for the VHDL testbench |
| `PKG:NAME_flashed_rcf` | RCF with the SPI-flash protocol headers prepended |
| `PKG:NAME_flashed_rcf_test` | Golden gate: proves the flashed image is byte-identical to the tracked `PKG/testdata/NAME_flashed_rcf_golden.txt` |

The six apps, package and target name:

| Package | `NAME` | Example build / test |
|---------|--------|----------------------|
| `//software/blinky` | `blinky` | `tools/bin/bazel build //software/blinky:blinky_flashed_rcf` / `tools/bin/bazel test //software/blinky:blinky_flashed_rcf_test` |
| `//software/gpiotoggle` | `gpiotoggle` | `//software/gpiotoggle:gpiotoggle_flashed_rcf`, `//software/gpiotoggle:gpiotoggle_flashed_rcf_test` |
| `//software/looptest` | `looptest` | `//software/looptest:looptest_flashed_rcf`, `//software/looptest:looptest_flashed_rcf_test` |
| `//software/slowblink` | `slowblink` | `//software/slowblink:slowblink_flashed_rcf`, `//software/slowblink:slowblink_flashed_rcf_test` |
| `//software/traptest` | `traptest` | `//software/traptest:traptest_flashed_rcf`, `//software/traptest:traptest_flashed_rcf_test` |
| `//software/afetest` | `afetest` | `//software/afetest:afetest_flashed_rcf`, `//software/afetest:afetest_flashed_rcf_test` |

### Boot ROM and debug trampoline

| Target | What it is / what it proves |
|--------|-----------------------------|
| `//software/bootrom_mp:rom_rcf` | The mask-ROM image (alias for the built `flashboot` RCF) |
| `//software/bootrom_mp:flashboot_elf` `:flashboot_bin` `:flashboot_hex` `:flashboot_dump` `:flashboot_rcf` | The boot ROM's intermediate artifacts |
| `//software/bootrom_mp:rom_rcf_reproducibility_test` | Proves the freshly built ROM image is byte-identical to the tracked golden - the mask ROM cannot drift silently |
| `//software/dbg_trampoline:dbg_trampoline_elf` `:dbg_trampoline_bin` `:dbg_trampoline_dump` `:dbg_trampoline_words` | The debug-module trampoline and its 40-word table |
| `//software/dbg_trampoline:dbg_trampoline_words_test` | Proves the assembled word table matches its tracked golden |
| `//tools/cosim:check_dbg_trampoline_test` | Dual-truth gate: proves the word table matches the table hard-coded in `hdl/common/debug_module.vhd` |

### Firmware goldens

Firmware images are locked by tracked `testdata/*_golden.txt` files (`*.rcf` is
globally gitignored, hence the `.txt` extension). **Changing firmware means
regenerating the affected golden in the same commit** - the test diff then shows
exactly which bytes moved. A firmware change committed without its golden update
lands as a red gate.

Full map of the Bazel build: [`BAZEL.md`](../BAZEL.md).

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

### Scaffolding a project (not managed by Bazel)

Bazel has no scaffolding rule, so a new project directory is still created by
the `software/Makefile` generator:

```bash
cd software/
make new PROJECT=my-app          # Create RAM-based application
make new PROJECT=my-boot TYPE=rom # Create ROM-based bootloader
make list                        # List all firmware projects
make help                        # Show all available commands
```

This creates the directory structure (src/, include/, obj/, bin/) and the
template source files (main.c, start.S).

### Wiring it into the build

Add a `BUILD.bazel` next to the new sources with a `myshkin_app` target from
[`//toolchains/riscv:defs.bzl`](../toolchains/riscv/defs.bzl) - copy
[`software/blinky/BUILD.bazel`](blinky/BUILD.bazel), which is the template the
other app packages were cloned from. Pair it with a `firmware_image_test` and a
tracked golden so the image cannot drift.

## Memory Layout

Firmware uses linker scripts to define memory organization:

Memory sizes are configurable per implementation. See linker scripts in [`tools/build/linker-scripts/`](../tools/build/linker-scripts/).

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
   cd software/
   make new PROJECT=my-app
   cd my-app/
   ```
   then add a `BUILD.bazel` as described above.

2. **Write code** in `src/` directory:
   - Edit `src/main.c` with your application logic
   - Add peripheral headers as needed
   - Modify `src/start.S` if custom startup required

3. **Update `BUILD.bazel`** (if needed):
   - Add source files and headers to the `myshkin_app` target
   - Adjust the ISA extensions for the features you need

4. **Build firmware**:
   ```bash
   tools/bin/bazel build //software/my-app:my-app_flashed_rcf
   ```

5. **Test in simulation**:
   - Use `.rcf` file with VHDL testbench
   - See `hdl/myshkin/tb/` for testbench examples

6. **Program hardware**:
   - Use `.bin` or `.hex` file
   - Flash via SPI programmer or JTAG

7. **Debug**:
   - Use `.elf` file with GDB
   - UART console output for printf-style debugging
   - See [`tools/debug/`](../tools/debug/) for debugging tools

## Requirements

Bazel provisions the RISC-V cross-compiler and the Python it needs, so building
firmware requires nothing installed locally beyond `tools/bin/bazel` (fetched by
`tools/get_bazel.sh`). A host `riscv-none-elf-` toolchain is needed only for the
work that sits outside Bazel - the bench and programmer tools and the Cadence
simulations; see [`tools/build/README.md`](../tools/build/README.md).

## Example: Creating a Blink Project

```bash
# Create new project
cd software/
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

# Build (from the repo root, once BUILD.bazel is in place)
tools/bin/bazel build //software/blinky:blinky_elf \
                      //software/blinky:blinky_bin \
                      //software/blinky:blinky_hex \
                      //software/blinky:blinky_dump \
                      //software/blinky:blinky_flashed_rcf
```

## Related Documentation

- [`tools/build/README.md`](../tools/build/README.md) — Toolchain setup and build utilities
- [`tools/build/linker-scripts/`](../tools/build/linker-scripts/) — Memory layout configuration
- [`verification/isa/README.md`](../verification/isa/README.md) — Test programs as code examples
- [`implementations/`](../implementations/) — Chip-specific configurations and memory maps
- [`hdl/myshkin/tb/`](../hdl/myshkin/tb/) — VHDL testbench examples for simulation


