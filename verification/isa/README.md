# verification/isa — ISA test images

riscv-tests-derived instruction tests plus VestaRV peripheral, boot and SPI-flash
suites, built into `.elf`/`.dump`/`.bin`/`.rcf` images for the VHDL testbenches.
Each test self-checks and writes `a0`: `0xCAFEBABE` pass, `0xDEADBEEF` fail.

## Bazel

Images build with the pinned compiler; polarity defines are part of each action key,
so no manual clean is needed. Run from the repo root.

```sh
sh tools/get_bazel.sh                          # bazelisk -> tools/bin/bazel
tools/bin/bazel build //verification/isa:all_images
```

| Target | Verb | Purpose |
|---|---|---|
| `:all_images` | build | every image: the eight CI suites plus `rv32uzf`, flashed and unflashed |
| `:ci_images`, `:ci_rcfs` | build | exactly what `./build_mp_images.sh 4 rcf_ci` stages |
| `:rv32ui_rcfs`, `:rv32ui_flashed` | build | one suite at CI polarity (`NHARTS=4`, no `-DCORE_ENABLE_*`); same for `rv32um`, `rv32ua`, `rv32uc`, `rv32uzba`, `rv32uzbb`, `rv32uzbc`, `rv32uzbs`, `rv32uzf` |
| `:os_rv32ui_rcfs`, `:os_rv32ui_flashed` | build | the same suites at open-source-sim ON polarity (`CORE_ENABLE_*` from `run_isa.sh`) |
| `:n5_crosscheck` | build | the five `NHARTS`-dependent tests at `NHARTS=5`, for comparison with `rcf/` |
| `:image_contract_test` | test | unflashed: 20480 words of 32 bits; flashed: `0x10adbeef` header, `0xcafebabe` execute word, one header; 22-character name |
| `:scalar_macros`, `:npu_data` | filegroup | `macros/scalar` headers; NPU golden set for [`../npu`](../npu/README.md) |

All labels are in `//verification/isa`. Simulation targets are in
[`opensource_sim`](../../opensource_sim/README.md); full map in [`BAZEL.md`](../../BAZEL.md).

## Make (host toolchain)

Requires `riscv-none-elf-gcc` ([`tools/build/README.md`](../../tools/build/README.md)).

| Command | Effect |
|---|---|
| `make <suite>` | build into `build/<suite>/` and copy `.rcf`s to `rcf/` |
| `make list-suites`, `make list-tests-<suite>` | list suites / tests |
| `make collect-all-rcf` | recollect every built `.rcf` into `rcf/` |
| `make clean-<suite>` | remove `build/<suite>/` (keeps `rcf/`) |
| `make clean-all` | remove all of `build/` and `rcf/` |

- `.rcf` files hold one 32-bit binary word per line. Names are left-padded with `x` to
  a fixed length so VHDL can iterate them, e.g. `rcf/xxxxrv32ui-p-add.rcf`.
- Make keys each `.elf` on its `.S` alone: after changing `-DCORE_ENABLE_*` flags,
  `rm -rf build/` first or stale images are reused.

## Layout

| Path | Contents |
|---|---|
| `tests/<suite>/` | assembly sources (`rv32ui`, `rv32um`, `rv32ua`, `rv32uc`, `rv32uz*`, `periph`, `boot`, `spifem`, …) |
| `macros/` | test macros |
| `rcf/` | collected images for the VHDL testbench |
| `../env/p/` | environment and linker scripts |
