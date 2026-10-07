# Myshkin chip generator

Single-core Myshkin generator. `python/generate.py` is the single source of truth for the
memory map, peripheral registers and TRM. Python 3 stdlib only; `pdflatex` for the PDF.
New work belongs in the hermetic Castalia/Argus generator,
[`platform/common`](../common/README.md).

**Not Bazel-managed:** it overwrites tracked files in place, inside and outside this
directory. Review `git status` after every run. Never hand-edit the outputs.

## Commands

Run from `platform/myshkin/`:

| Command | Action |
|---|---|
| `make` / `make generate` / `./regenerate.sh` | Regenerate every output below |
| `make show` / `./show_config.sh` | Print the configuration from `config/MemoryMap.json` |
| `make pdf` | Compile `latex/TRM/TRM.pdf` (two `pdflatex` passes) |
| `make clean` | Delete the generated outputs (prompts first) |
| `make install-deps` | Check for Python 3 and `pdflatex` |

After regenerating, rebuild firmware from the repo root: `tools/bin/bazel build //software/...`.

## Outputs

| File | Content |
|---|---|
| `../../software/commune/include/MemoryMap.h`, `periph.S` | C and assembly register definitions |
| `../../tools/build/linker-scripts/memory.x`, `periph.x`, `*.txt` | Linker regions, peripheral symbols, ROM/RAM sizes |
| `../../hdl/myshkin/MemoryMap.vhd` | `RegSlot*` constants for the RTL |
| `../../hdl/myshkin/MCU.vhd` | Generated sections only, edited in place |
| `config/MemoryMap.json` | Machine-readable memory map |
| `latex/TRM/` | TRM LaTeX project |

Hand-edited sources: `python/generate.py`, `latex/TRM.template.tex`, and
`latex/PeripheralIntroductions/*.tex` (one intro per peripheral, placed before its
generated register tables). `gcc/lib/` holds tracked snapshots of the headers and linker
fragments, not written by the generator, exposed to Bazel as
`//platform/myshkin/gcc/lib:platform_headers` and `:linker_fragments`.

## Adding a peripheral

In `generate.py`: create a `PeripheralTemplate`, add `RegisterTemplate`s and `BitField`s
(unused bits as `BitField(msb=…, lsb=…, unused=True)`), then `m.CreatePeripheral(...,
peripheralMemorySlot=…, interruptPriority=…)`. Add the intro as
`latex/PeripheralIntroductions/<PERIPH>-intro-<chip>.tex` and name it in `latexIntroFileName`.

## Memory map

| Range | Region |
|---|---|
| `0x00000–0x03FFF` | ROM, 16 KiB |
| `0x04000–0x04FFF` | Peripherals |
| `0x08000–0x0814B` | Interrupt vectors (83 × 4 B) |
| `0x0814C–0x0BFFF` | RAM block 0 |
| `0x0C000–0x0FFFF` | RAM block 1, NPU DMA buffer |

The stack pointer initialises to `0x10000`, inside the NPU DMA block; applications using
the NPU must move it to `0x0C000`. `MemoryMap.h` provides `MMR_32_BIT_MACRO(addr)`,
`MMR_32_PTR(base, offset)` and `RVISR(vector, handler)`.
