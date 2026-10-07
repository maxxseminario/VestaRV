# software — VestaRV firmware

Boot ROM (`bootrom_mp/`), debug trampoline (`dbg_trampoline/`), shared code
(`commune/`) and small RAM applications. Bazel provisions the compiler and gates every
image against a tracked golden. Run from the repo root:

```sh
sh tools/get_bazel.sh                                  # bazelisk -> tools/bin/bazel
tools/bin/bazel build //software/blinky:blinky_flashed_rcf
tools/bin/bazel test  //software/...
```

| Target | Purpose |
|---|---|
| `//software/<app>:<app>_{elf,bin,hex,dump,rcf}` | app images; apps: `blinky`, `gpiotoggle`, `looptest`, `slowblink`, `traptest` |
| `//software/<app>:<app>_flashed_rcf` / `_flashed_rcf_test` | RCF with SPI-flash headers / byte-identical to `testdata/<app>_flashed_rcf_golden.txt` |
| `//software/bootrom_mp:rom_rcf`, `:rom_rcf_reproducibility_test` | mask-ROM image / matches its golden |
| `//software/dbg_trampoline:dbg_trampoline_words_test` | trampoline table matches its golden |
| `//tools/cosim:check_dbg_trampoline_test` | table matches `hdl/common/debug_module.vhd` |

- Apps do not currently boot from flash: they link at `0x814C`, the flash tool loads
  at `0x8000`, and the boot ROM jumps to `PROG_BASE_ADDR` `0x8200`. Goldens check bytes only.
- A firmware change regenerates its `testdata/*_golden.txt` in the same commit.

New app: `make -C software new PROJECT=my-app` scaffolds sources; then copy
[`blinky/BUILD.bazel`](blinky/BUILD.bazel) (`myshkin_app` + `firmware_image_test`).
Host-toolchain work outside Bazel: [`tools/build/README.md`](../tools/build/README.md).
Full Bazel map: [`BAZEL.md`](../BAZEL.md).
