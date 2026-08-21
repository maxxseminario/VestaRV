# VestaRV Chip Generator

The `generator/` directory contains the automated toolchain for generating all chip-specific configuration artifacts from a single Python description. When you add a peripheral, change the memory map, or create a new chip variant, you run one script and all downstream files are regenerated automatically.

---

## Quick Start

**Using Make (recommended):**

```bash
cd generator
make              # Regenerate all toolchain files
make show         # View current configuration
make pdf          # Compile documentation PDF
make help         # Show all available commands
```

**Using shell scripts:**

```bash
cd generator
./regenerate.sh   # Regenerate all toolchain files
./show_config.sh  # View current configuration
```

---

## Building with Bazel

**This generator is deliberately NOT Bazel-managed.** It overwrites tracked
files in place (`config/`, `gcc/lib/`, `latex/`), which is exactly what a
hermetic, sandboxed build must never do, so no Bazel target runs it. Run it the
old way, as documented below, and expect it to modify your working tree.

The only Bazel targets in this directory are two filegroups that hand the
already-generated, tracked outputs to the firmware builds:

| Target | What it is |
|--------|------------|
| `//platform/myshkin/gcc/lib:platform_headers` | The generated `MemoryMap.h` / `periph.S` headers, as build inputs |
| `//platform/myshkin/gcc/lib:linker_fragments` | The generated `memory.x` / `periph.x` linker fragments |

**The Bazel-managed generator is `platform/common` (Castalia / Argus).** For new
work use that one - it generates into a sandbox, never into the tree, and it
carries the full gate set. From the repo root:

```sh
sh tools/get_bazel.sh            # fetches bazelisk into tools/bin/bazel
tools/bin/bazel test //...       # first run downloads all toolchains
```

```sh
tools/bin/bazel build //platform/common:chip_artifacts_castalia   # the hermetic generation
tools/bin/bazel build //platform/common:chip_artifacts_argus      # the 18-hart course chip
tools/bin/bazel test  //platform/...                              # the generator gate tests
```

See [`platform/common/README.md`](../common/README.md) for that flow, and
[`BAZEL.md`](../../BAZEL.md) for the full map of the Bazel build.

## Directory Structure

```
generator/
├── python/
│   ├── generate.py          — Entry point: defines the full memory map and peripheral set
│   ├── ChipGenerator.py     — Core generator class
│   ├── Peripheral.py        — PeripheralTemplate and Peripheral classes
│   ├── Register.py          — RegisterTemplate and Register classes
│   ├── BitField.py          — BitField class (defines register bit descriptions)
│   ├── LatexUserGuide.py    — LaTeX user guide generation engine
│   ├── GpioConfigurator.py  — GPIO alternate-function table generator
│   ├── Package.py           — Package pin and power-domain definitions
│   ├── TabbedTable.py       — LaTeX tabular formatting utilities
│   └── CRC.py               — CRC utility used during generation
│
├── config/                  — Generated output configuration files (do not hand-edit)
│   ├── MemoryMap.json        — Full memory map in JSON (generated)
│   ├── ChipConfig.json       — Chip-level parameters (generated)
│   └── BoardConfig.json      — Board-level configuration (generated)
│
├── gcc/lib/                 — Generated software headers and linker scripts
│   ├── include/MemoryMap.h   — C header with all peripheral base addresses and bit-field macros
│   ├── include/periph.S      — Assembly header with peripheral addresses
│   ├── linker/memory.x       — Linker memory region definitions
│   └── linker/periph.x       — Linker peripheral address symbols
│
└── latex/
    ├── TRM.template.tex                   — Master LaTeX template (edit this, not the output)
    ├── packages-commands.template.tex     — LaTeX packages and custom commands
    ├── PeripheralIntroductions/           — Hand-written peripheral description tex files
    │   └── <PERIPH>-intro-<chip>.tex      — One file per peripheral per chip variant
    ├── TRM/                               — Generated LaTeX project (do not hand-edit)
    │   ├── TRM.tex
    │   ├── include/                       — Generated register tables and bitbox diagrams
    │   └── figures/                       — Figures copied from PeripheralIntroductions
    └── figures/                           — Source figures referenced by intro tex files
```

---

## What the Generator Produces

Running `python3 generate.py` regenerates all of the following from the single source-of-truth in `generate.py`:

| Output File | Purpose |
|-------------|---------|
| `generator/gcc/lib/include/MemoryMap.h` | C header for firmware — peripheral base addresses, register offsets, bit-field masks and LSB positions |
| `generator/gcc/lib/include/periph.S` | Assembly `.equ` definitions for all the same values |
| `generator/gcc/lib/linker/memory.x` | Linker script memory region map (ROM, RAM, peripheral space) |
| `generator/gcc/lib/linker/periph.x` | Linker peripheral address symbols |
| `generator/config/MemoryMap.json` | Machine-readable full memory map |
| `hdl/myshkin/MemoryMap.vhd` | VHDL package with `RegSlot*` constants used by all peripheral VHDL entities |
| `generator/latex/TRM/` | Complete LaTeX project for the Technical Reference Manual (TRM) PDF |

All outputs are derived from `generate.py`. Never edit them by hand — changes will be lost on the next run.

---

## Running the Generator

### Requirements

- Python 3.8 or later (no additional packages required)
- For PDF generation: a LaTeX distribution with `pdflatex` (e.g., TeX Live)

### Generate all artifacts

Using Make:
```bash
cd generator
make
```

Or using shell scripts:
```bash
cd generator
./regenerate.sh
```

Or manually:

```bash
cd generator/python
python3 generate.py
```

### View current configuration

```bash
cd generator
make show
# or
./show_config.sh
```

### Compile the Technical Reference Manual (TRM) PDF
Using Make:
```bash
cd generator
make pdf
```

Or manually:
```bash
cd generator/latex/TRM
pdflatex -interaction=nonstopmode TRM.tex
pdflatex -interaction=nonstopmode TRM.tex   # second pass for cross-references
```

---

## Defining the Memory Map

`generate.py` is the single source of truth for the chip configuration. It creates a `ChipGenerator` instance with chip-level parameters (ROM/RAM sizes, clock, ISA feature flags) and then defines every peripheral using the `PeripheralTemplate` / `RegisterTemplate` / `BitField` API.

### Example: Adding a peripheral

```python
from Peripheral import PeripheralTemplate
from Register import RegisterTemplate
from BitField import BitField

# 1. Define the peripheral template
p = PeripheralTemplate(
    nameTemplate='MYPERIPHx',
    bitFieldPrefix='MYPERIPH_',
    latexIntroFileName='MYPERIPH-intro-myshkin-2025-11.tex'
)
m.AddPeripheralTemplate(p)

# 2. Add registers
r = RegisterTemplate(nameTemplate='MYPERIPH_CR', registerMemorySlot=0, size=8,
                     description='Control register.')
p.AddRegisterTemplate(r)
r.AddBitField(BitField(msb=7, lsb=1, unused=True))
r.AddBitField(BitField(name='EN', msb=0,
                       description='Enable the peripheral.',
                       accessibility='rw',
                       valueDescriptions=[(0, 'Disabled'), (1, 'Enabled')]))

# 3. Instantiate at a memory slot
m.CreatePeripheral(nameTemplate='MYPERIPHx', nameIndex=0,
                   peripheralMemorySlot=13, interruptPriority=30)
```

### Example: Adding the peripheral's intro text

Create `generator/latex/PeripheralIntroductions/MYPERIPH-intro-myshkin-2025-11.tex` with a LaTeX description of the peripheral's architecture, operation, and usage. This file is included verbatim in the Technical Reference Manual before the auto-generated register tables.

---

## Chip Configuration Parameters (`generate.py`)

The `ChipGenerator()` constructor accepts the following key parameters:

| Parameter | Current Value | Description |
|-----------|--------------|-------------|
| `asicName` | `'Myshkin'` | Chip name used in all output headers |
| `romStartAddress` | `0x0000` | ROM base address |
| `romSize` | `16384` | ROM size in bytes (16 KiB) |
| `ramStartAddress` | `0x8000` | RAM base address |
| `ramMemorySlotsUsed` | `[3, 4]` | Which 16 KiB RAM slots are populated (total 32 KiB) |
| `stackPointerInit` | `0x10000` | Initial stack pointer value |
| `vectorsCount` | `83` | Number of interrupt vectors |
| `COMPRESSED_ISA` | `True` | Emit RVC support in linker/header flags |
| `ENABLE_MUL` / `ENABLE_DIV` | `True` | Emit M-extension flags |

To create a different chip variant (e.g., a smaller or FPGA-targeted version), duplicate `generate.py` under a new name, adjust the parameters, and run it. The generator will produce a separate set of output files.

---

## Using the Generated Files

### In C/C++ Firmware

Include the generated header:

```c
#include <MemoryMap.h>

// Access peripheral registers
MMR_32_BIT_MACRO(PERIPH_GPIO0_BASE + GPIO_PxOUT) = 0xFF;

// Or use the pointer macro
MMR_32_PTR(PERIPH_UART0_BASE, UART_TX) = 'A';

// Define interrupt service routines
RVISR(5, my_timer_isr) {
    // Handle timer interrupt
}
```

### In Assembly

Include the generated assembly definitions:

```asm
.include "periph.S"

li a0, PERIPH_GPIO0_BASE
sw t0, GPIO_PxOUT(a0)
```

### In Makefiles

The linker scripts are automatically included by `MCU.ld`:

```makefile
LDFLAGS += -T $(BUILD_DIR)/linker-scripts/MCU.ld
```

---

## Memory Map Overview

The current Myshkin implementation has:

```
0x00000 - 0x03FFF   ROM (16 KiB)          - Boot code and constants
0x04000 - 0x04FFF   Peripherals (4 KiB)   - Memory-mapped registers
0x08000 - 0x0814B   Interrupt Vectors     - 83 vectors × 4 bytes
0x0814C - 0x0BFFF   RAM Block 0 (14 KiB)  - Stack and data
0x0C000 - 0x0FFFF   RAM Block 1 (16 KiB)  - DMA to NPU
```

**Stack Pointer:** Initialized to `0x10000` (top of RAM)

⚠️ **Important:** The final RAM block (0x0C000 - 0x0FFFF) is used for DMA transfers to the Neural Processing Unit (NPU). If your application uses the NPU, you must relocate the stack pointer to avoid conflicts with DMA operations. Consider setting the stack pointer to `0x0C000` (top of RAM Block 0) when using NPU features.

---

## Architecture Notes

VestaRV CPU features:
- **Base ISA**: RV32I (32-bit integer)
- **Extensions**: C (compressed), M (multiply/divide)
- **Custom**: SMRV32 core with sleep/wake/retirq instructions
- **Interrupt model**: Vectored interrupts with priority levels and **recursive interrupt handling**

---

## Important Notes

⚠️ **Never manually edit generated files!** They will be overwritten on the next generation.

Files that are **auto-generated** (do not edit):
- `../software/commune/include/MemoryMap.h`
- `../software/commune/include/periph.S`
- `../tools/build/linker-scripts/memory.x`
- `../tools/build/linker-scripts/periph.x`
- `../tools/build/linker-scripts/*.txt`
- `config/MemoryMap.json`
- `latex/TRM/` (entire directory)

Files that are **manual** (can edit):
- `python/generate.py` - **The single source of truth**
- Any firmware application code
- `latex/PeripheralIntroductions/*.tex` - Peripheral descriptions

---

## Professional Workflow

1. **Make changes** to `python/generate.py`
2. **Regenerate** all files: `make` (or `./regenerate.sh`)
3. **Rebuild** firmware: `cd ../software && make clean && make`
4. **Test** in simulation or on hardware
5. **Commit** changes to git

**Why use Make?**
- ✅ Standard build system interface familiar to all developers
- ✅ Single command: `make` instead of `./regenerate.sh`
- ✅ Multiple useful targets: `make show`, `make pdf`, `make help`
- ✅ Easy integration with CI/CD pipelines
- ✅ Can be called from parent makefiles: `cd generator && make`

---

## Troubleshooting

**Q: Generator fails with "module not found"**  
A: Make sure you're running from `generator/` directory: `./regenerate.sh`

**Q: Linker errors about missing sections**  
A: Regenerate linker scripts and rebuild: `./regenerate.sh && cd ../software && make clean && make`

**Q: Want to create a new chip variant**  
A: Copy `python/generate.py` to `python/generate_<variant>.py`, modify parameters, and update `ChipGenerator()` to output to different paths or use a different chip name.
