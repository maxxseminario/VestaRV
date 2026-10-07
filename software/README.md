# software — VestaRV firmware

Firmware for the VestaRV core: the mask boot ROM, the debug trampoline, and small
RAM applications. Bazel provisions the pinned RISC-V compiler and gates every image
against a tracked golden. Run from the repo root.

```sh
sh tools/get_bazel.sh                                  # bazelisk -> tools/bin/bazel
tools/bin/bazel build //software/blinky:blinky_flashed_rcf
tools/bin/bazel test  //software/...
```

## Applications

`blinky`, `gpiotoggle`, `looptest`, `slowblink` and `traptest` are `myshkin_app`
packages (`//software/<app>`), each with the same targets:

| Target | Artifact |
|---|---|
| `<app>_elf`, `_bin`, `_hex`, `_dump` | ELF with debug symbols, raw binary, Intel HEX, disassembly |
| `<app>_rcf` | RCF for the VHDL testbench |
| `<app>_flashed_rcf` | RCF with SPI-flash protocol headers prepended |
| `<app>_flashed_rcf_test` | byte-identical to `<app>/testdata/<app>_flashed_rcf_golden.txt` |

These images do not currently boot from flash: they link at `0x814C` and the flash
tool loads them at `0x8000`, while the boot ROM jumps to `PROG_BASE_ADDR` `0x8200`.
The golden tests check image bytes only.

## Boot ROM and debug trampoline

| Target | Purpose |
|---|---|
| `//software/bootrom_mp:rom_rcf` | mask-ROM image (the built `flashboot` RCF) |
| `//software/bootrom_mp:flashboot_{elf,bin,hex,dump,rcf}` | boot ROM intermediates |
| `//software/bootrom_mp:rom_rcf_reproducibility_test` | rebuilt ROM is byte-identical to its golden |
| `//software/dbg_trampoline:dbg_trampoline_words_test` | trampoline word table matches its golden |
| `//tools/cosim:check_dbg_trampoline_test` | word table matches the copy in `hdl/common/debug_module.vhd` |

## Goldens

Images are locked by `testdata/*_golden.txt` (`.txt` because `*.rcf` is gitignored).
A firmware change must regenerate its golden in the same commit, or the gate fails.

## New application

```sh
make -C software new PROJECT=my-app          # scaffold src/, include/, main.c, start.S
make -C software new PROJECT=my-boot TYPE=rom
```

Then copy [`blinky/BUILD.bazel`](blinky/BUILD.bazel) (a `myshkin_app` from
[`//toolchains/riscv:defs.bzl`](../toolchains/riscv/defs.bzl)) and add a
`firmware_image_test` with a tracked golden.

## Layout

| Path | Contents |
|---|---|
| `bootrom_mp/` | mask boot ROM (`rom_rcf`) |
| `bootrom/` | boot ROM with Forth interpreter |
| `dbg_trampoline/` | debug-module trampoline |
| `commune/` | shared headers (`include/`) and library code (`src/`) |

A host `riscv-none-elf-` toolchain is needed only outside Bazel (bench tools,
Cadence simulation): [`tools/build/README.md`](../tools/build/README.md). Full Bazel
map: [`BAZEL.md`](../BAZEL.md). Testbenches: [`hdl/myshkin/tb/`](../hdl/myshkin/tb/).
