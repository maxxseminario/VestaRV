# verification/npu — NPU golden model

Integer-only, bit-exact Python model of the NPU fixed-point datapath
(`hdl/common/periph/NPU.vhd`, `hdl/common/commune/FPMac.vhd`,
`hdl/common/commune/FPSigmoid.vhd`), replicating the `fixed_pkg` fork in
`hdl/common/commune/fixed_pkg_c.vhdl`: round-half-to-even, saturate on overflow.
Python 3.6 compatible.

## Bazel

```sh
tools/bin/bazel test //verification/npu/...     # from the repo root
```

| Target | Purpose |
|---|---|
| `:validate_mlp_test` | reproduces the chip-config MLP golden set (`verification/isa/tests/periph/NPU_data`) bit-exactly, 201/201 |
| `:regen_{actf,conv,gemm,xnor}_vectors_test` | tracked `*_vectors/` equal what the generators produce now (regenerated in a scratch tree) |
| `:gen_{wactf,wgemm,wnpuconv,wxnpu}_golden_test` | firmware-smoke golden generators agree with `npu_fixed` |
| `:validate_mlp` | runner binary; `bazel run` with an absolute `--data-dir` for the mismatch trace |
| `:npu_fixed`, `:xnor_gen_lib` | libraries: fixed-point arithmetic, XNOR encoders |

All labels are in `//verification/npu`. Full map: [`BAZEL.md`](../../BAZEL.md).

## Files

| File | Role |
|---|---|
| `npu_fixed.py` | `resize_sfixed`, `int_to_sfixed`, `mac_step`, `sigmoid`, `think_layer` (one NPU THINK, bias first) |
| `validate_mlp.py` | checks the 2-layer `y = 2x^2 + 1` MLP from `hdl/common/tb/NPU_tb.vhd` against golden files |
| `gen_{actf,gemm,conv,xnor}_vectors.py` | vector generators feeding `*_vectors/` |
| `gen_w*_golden.py` | firmware-smoke golden generators |

`validate_mlp.py` knows two configurations:

| Config | X_M, W_M, Y_M, N, RHO | Golden files |
|---|---|---|
| `bench` | 0, 3, 3, 15, 2 (`NPU_tb.vhd` defaults) | `xcelium/NPU/{behavioral,genus}`, `xcelium/periph_test/behavioral` |
| `chip` | 0, 7, 7, 24, 2 (`hdl/common/MCU.vhd`) | `verification/isa/tests/periph/NPU_data` |

```sh
cd verification/npu
/usr/bin/python3 validate_mlp.py                       # all four, hard-coded under ~/vestarv
/usr/bin/python3 validate_mlp.py --data-dir ../isa/tests/periph/NPU_data --config chip
```

Exit 0 iff 100 % bit-exact; mismatches print a per-neuron hex trace (first five).

## Caveats

- Run scripts as files, never `python3 -c`: this host's default `python3` is a
  Calibre wrapper that strips quotes. `/usr/bin/python3` is plain CPython.
- `int_to_sfixed` reproduces `fixed_pkg`'s saturating integer constants:
  `to_sfixed(1, 0, -N)` gives `2^N - 1`, not `2^N`.
- `gen_conv_vectors.py` has no RTL counterpart; its layout and format are provisional.
  `gen_xnor_vectors.py`'s `_cfg.txt` header order (`CFG_FIELDS`) is provisional.
- `verification/isa/tests/periph/NPU.S` masks results to 19 bits (bench width) while
  reading chip-config (32-bit) golden data.
