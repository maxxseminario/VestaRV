# verification — VestaRV verification suite

ISA test images, NPU golden model, CPI harness, benchmarks and the shared
riscv-tests environment. Bazel fetches the pinned RISC-V compiler and GHDL; run
from the repo root.

```sh
sh tools/get_bazel.sh                    # bazelisk -> tools/bin/bazel
tools/bin/bazel test //verification/...
```

| Target | Verb | Purpose |
|---|---|---|
| `//verification/isa:all_images` | build | every ISA image, flashed and unflashed |
| `//verification/isa:ci_rcfs`, `:ci_images` | build | the set `./build_mp_images.sh 4 rcf_ci` stages |
| `//verification/isa:image_contract_test` | test | image word count, flash header, execute word, name length |
| `//verification:env_headers`, `:env_p_linker_scripts` | build | p-mode environment every image builds against |
| `//verification/npu/...` | test | NPU golden model and vector regeneration |
| `//verification/cpi/...` | test | CPI against recorded values |
| `//opensource_sim:isa_regression` | test | all nine ISA suites on the RTL under GHDL |

Full map: [`BAZEL.md`](../BAZEL.md).

| Directory | Contents |
|---|---|
| [`isa/`](isa/README.md) | riscv-tests-derived instruction tests plus peripheral/boot suites |
| [`npu/`](npu/README.md) | bit-exact Python model of the NPU datapath |
| [`cpi/`](cpi/README.md) | cycles-per-instruction harness behind the TRM CPI tables |
| `benchmarks/` | UCB riscv-bmarks (dhrystone, qsort, spmv, `mt-*`, `vec-*`, …) |
| `mt/` | multi-threaded matmul/vvadd variants |
| `env/` | riscv-tests environment (`encoding.h`, `p/`, `pm/`, `pt/`, `v/`) |
| `formal/` | PSL property benches for the fabric and PMP |

## Outside Bazel

`benchmarks/` and `mt/` are not in the Bazel graph; build with `make` and a host
`riscv-none-elf-gcc` ([`tools/build/README.md`](../tools/build/README.md)):

```sh
make -C verification/benchmarks
make -C verification/mt
```

## Pass/fail convention

Tests write `a0`: `0xCAFEBABE` pass, `0xDEADBEEF` fail (`RVTEST_PASS`/`RVTEST_FAIL`
in `env/p/riscv_test.h`). A hang is a fail.

## Adding an ISA test

Add the source under `isa/tests/<suite>/`; for a new suite also update
`isa/BUILD.bazel` and `isa/Makefile`. Build with
`tools/bin/bazel build //verification/isa:<suite>_rcfs`.
