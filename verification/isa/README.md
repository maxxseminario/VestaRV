# verification/isa — ISA test images

riscv-tests-derived instruction tests plus peripheral, boot and SPI-flash suites,
built into `.elf`/`.dump`/`.bin`/`.rcf` images. Tests write `a0`: `0xCAFEBABE` pass,
`0xDEADBEEF` fail. Simulation: [`opensource_sim`](../../opensource_sim/README.md).

```sh
tools/bin/bazel build //verification/isa:all_images        # from the repo root
tools/bin/bazel test  //verification/isa:image_contract_test
```

| Target (`//verification/isa`) | Purpose |
|---|---|
| `:ci_images`, `:ci_rcfs` | exactly what `./build_mp_images.sh 4 rcf_ci` stages |
| `:rv32ui_rcfs`, `:rv32ui_flashed` | one suite at CI polarity (no `-DCORE_ENABLE_*`); same for each suite |
| `:os_rv32ui_rcfs`, `:os_rv32ui_flashed` | same suites at open-source-sim ON polarity (`CORE_ENABLE_*` from `run_isa.sh`) |
| `:n5_crosscheck` | `NHARTS`-dependent tests at `NHARTS=5`, for comparison with `rcf/` |

Make (host `riscv-none-elf-gcc`, [`tools/build/README.md`](../../tools/build/README.md)):
`make <suite>` builds into `build/<suite>/` and copies `.rcf`s to `rcf/`;
`make list-suites`, `make clean-all`.

- Make keys each `.elf` on its `.S` alone: after changing `-DCORE_ENABLE_*`,
  `rm -rf build/` first or stale images are reused.
- `.rcf` names are left-padded with `x` to a fixed length, e.g. `rcf/xxxxrv32ui-p-add.rcf`.

Full Bazel map: [`BAZEL.md`](../../BAZEL.md).
