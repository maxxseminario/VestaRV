# Build system

Shared firmware build infrastructure: `linker-scripts/`, `makefiles/`, `scripts/`
(hex/RCF conversion), `templates/`. Bazel fetches its own pinned toolchain.

```sh
tools/bin/bazel build //tools/build:bin2rcf //tools/build:rcf_flash
tools/bin/bazel test  //software/... //tools/build/...
```

| Target | Role |
|---|---|
| `//tools/build:bin2rcf` | bin → RCF converter |
| `//tools/build:rcf_flash` | Prepends SPI-flash headers to an RCF |
| `//tools/build:linker_scripts` | `.ld` files plus the fragments they `INCLUDE` |
| `//tools/build:rom_plate_link_env_test` | Pins the frozen link environment's diff to `testdata/rom_plate_link_env.diff` |

`memory.x`, `periph.x` and the `*_START`/`*_SIZE` files are the frozen link environment of
the taped-out boot-ROM plate, not the generator's current output; refreshing them
invalidates the plate.

Cadence simulations and bench tools need a host `riscv-none-elf-gcc` ≥ 13.2.0 via
`RISCV_TOOLCHAIN_DIR`; Bazel ignores it.

See [`BAZEL.md`](../../BAZEL.md) and [`software/README.md`](../../software/README.md).
