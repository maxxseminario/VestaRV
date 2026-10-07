# Myshkin chip generator

Single-core Myshkin generator. `python/generate.py` is the single source of truth for the
memory map, peripheral registers and TRM; peripheral prose is in
`latex/PeripheralIntroductions/*.tex`. Python 3 stdlib; `pdflatex` for the PDF. New work
belongs in [`platform/common`](../common/README.md).

**Not Bazel-managed:** it overwrites tracked files in place, inside and outside this
directory. Review `git status` after every run. Never hand-edit the outputs.

Run from `platform/myshkin/` (`make help` lists all targets):

```sh
make             # regenerate (same as ./regenerate.sh)
make show        # print the configuration
make pdf         # build latex/TRM/TRM.pdf
```

| Output | Content |
|---|---|
| `../../software/commune/include/MemoryMap.h`, `periph.S` | C and assembly register definitions |
| `../../tools/build/linker-scripts/memory.x`, `periph.x`, `*.txt` | Linker regions and sizes |
| `../../hdl/myshkin/MemoryMap.vhd`, `MCU.vhd` | RTL constants; `MCU.vhd` generated sections edited in place |
| `config/MemoryMap.json`, `latex/TRM/` | Memory map JSON, TRM LaTeX project |

`gcc/lib/` holds tracked snapshots of the headers and linker fragments (not written by the
generator), exposed as `//platform/myshkin/gcc/lib:platform_headers` and
`:linker_fragments`.

RAM `0x0C000–0x0FFFF` is the NPU DMA buffer, and the stack starts at `0x10000` inside it:
applications using the NPU must move the stack pointer to `0x0C000`.
