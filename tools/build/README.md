# Build system — shared build infrastructure for VestaRV firmware

| Directory | Contents |
|---|---|
| `linker-scripts/` | `MCU.ld`, `MCU-bootrom.ld` (hand-written) + `memory.x`, `periph.x`, `*_START.txt`, `*_SIZE.txt` |
| `makefiles/` | Common makefiles |
| `scripts/` | Hex/RCF conversion and image checks |
| `templates/` | C, C++ and testbench project templates |

The `memory.x` / `periph.x` / `*_START` / `*_SIZE` files are the frozen link environment of
the taped-out `rom2k_hvt_pg` boot-ROM plate, not the generator's current output. Refreshing
them relinks the boot image and invalidates the plate; `software/bootrom_mp` does not link
against the current output.

## Bazel

Bazel fetches its own pinned RISC-V toolchain and Python; nothing needs installing.

```sh
sh tools/get_bazel.sh
tools/bin/bazel build //tools/build:bin2rcf //tools/build:rcf_flash
tools/bin/bazel test  //software/...        # firmware goldens exercise both converters
```

| Target | Role |
|---|---|
| `//tools/build:bin2rcf` | Canonical bin → RCF converter |
| `//tools/build:rcf_flash` | Prepends SPI-flash protocol headers to an RCF |
| `//tools/build:linker_scripts` | `.ld` files plus the fragments they `INCLUDE`; must travel together |
| `//tools/build:rom_plate_link_env_test` | Fails if the frozen link environment's difference from `//platform/common:castalia_linker_scripts` changes from `testdata/rom_plate_link_env.diff` |
| `//tools/build:firmware_image_map_test` | Product images' sections stay inside the memory map |
| `//tools/build:verification_image_map_test` | Same check over the ISA and CPI verification images |

Build map: [`BAZEL.md`](../../BAZEL.md). Firmware targets: [`software/README.md`](../../software/README.md).

## Outside Bazel

Cadence simulations (`make verify` in `platform/common`, Xcelium and lockstep gates) and
bench tools need a host `riscv-none-elf-gcc` (13.2.0 or later, e.g. the
[xPack release](https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases)).
Bazel ignores it.

```sh
export RISCV_TOOLCHAIN_DIR=~/riscv-toolchain/xpack-riscv-none-elf-gcc-13.2.0-2
pip install intelhex      # bench/programmer tools only
```

The bench and programmer tools (`tools/chip_programmer/`, `tools/flash_programmer/`,
`tools/PyEmanate/`) are untracked and live only on the bench machine.
