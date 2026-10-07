# verification — VestaRV verification suite

ISA test images, NPU golden model, CPI harness, benchmarks and the shared
riscv-tests environment. Run from the repo root:

```sh
sh tools/get_bazel.sh                    # bazelisk -> tools/bin/bazel
tools/bin/bazel test //verification/...
```

| Directory | Contents |
|---|---|
| [`isa/`](isa/README.md) | instruction, peripheral and boot test images |
| [`npu/`](npu/README.md) | bit-exact Python model of the NPU datapath |
| [`cpi/`](cpi/README.md) | cycles-per-instruction harness behind the TRM CPI tables |
| `formal/` | PSL property benches for the fabric and PMP |
| `env/` | riscv-tests environment (`encoding.h`, `p/`, `pm/`, `pt/`, `v/`) |
| `benchmarks/`, `mt/` | UCB riscv-bmarks and multi-threaded tests; not in Bazel |

`benchmarks/` and `mt/` build with `make -C verification/benchmarks` /
`make -C verification/mt` and a host `riscv-none-elf-gcc`
([`tools/build/README.md`](../tools/build/README.md)).

Tests write `a0`: `0xCAFEBABE` pass, `0xDEADBEEF` fail; a hang is a fail. RTL
simulation of the images: [`opensource_sim`](../opensource_sim/README.md). Full
Bazel map: [`BAZEL.md`](../BAZEL.md).
