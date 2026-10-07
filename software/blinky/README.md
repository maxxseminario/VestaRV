# blinky — toolchain and simulation smoke application

Minimal VestaRV application and the template the other app packages were cloned
from. Shared targets and conventions: [`software/README.md`](../README.md).

```sh
tools/bin/bazel build //software/blinky:blinky_flashed_rcf       # from the repo root
tools/bin/bazel test  //software/blinky:blinky_flashed_rcf_test
```

| Target | Artifact |
|---|---|
| `//software/blinky:blinky_elf`, `_bin`, `_hex`, `_dump` | ELF (debug symbols), raw binary, Intel HEX, disassembly |
| `//software/blinky:blinky_rcf` | RCF without flash headers |
| `//software/blinky:blinky_flashed_rcf` | RCF with SPI-flash protocol headers |
| `//software/blinky:blinky_flashed_rcf_test` | byte-identical to `testdata/blinky_flashed_rcf_golden.txt` |

- A firmware change regenerates `testdata/blinky_flashed_rcf_golden.txt` in the same commit.
- The image does not currently boot from flash: it links at `0x814C`, the flash tool
  loads it at `0x8000`, and the boot ROM jumps to `0x8200`. The golden test checks bytes only.
- Linker memory definitions: `platform/myshkin/gcc/lib/linker/`.

Xcelium (outside Bazel): copy the flashed RCF into `verification/isa/rcf/` under its
22-character `x`-padded name and point the testbench at it:

```vhdl
constant RCF_FILE : string := "../../../verification/isa/rcf/xxxxxxxblinky.rcf";
```
