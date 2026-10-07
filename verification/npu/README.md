# verification/npu — NPU golden model

Integer-only, bit-exact Python model (`npu_fixed.py`) of the NPU fixed-point datapath
(`hdl/common/periph/NPU.vhd`, `FPMac.vhd`, `FPSigmoid.vhd`), matching
`hdl/common/commune/fixed_pkg_c.vhdl`: round-half-to-even, saturate on overflow.

```sh
tools/bin/bazel test //verification/npu/...     # from the repo root
```

| Target (`//verification/npu`) | Purpose |
|---|---|
| `:validate_mlp_test` | chip-config MLP golden set (`verification/isa/tests/periph/NPU_data`) bit-exact, 201/201 |
| `:regen_{actf,conv,gemm,xnor}_vectors_test` | tracked `*_vectors/` equal current generator output |
| `:gen_{wactf,wgemm,wnpuconv,wxnpu}_golden_test` | firmware golden generators agree with `npu_fixed` |

Outside Bazel:

```sh
cd verification/npu
/usr/bin/python3 validate_mlp.py --data-dir ../isa/tests/periph/NPU_data --config chip
```

- Without `--data-dir`, `validate_mlp.py` scans directories hard-coded under `~/vestarv`.
- Never use `python3 -c` on this host: the default `python3` is a Calibre wrapper that
  strips quotes. Use `/usr/bin/python3`.
- `gen_conv_vectors.py` has no RTL counterpart; its format, and the
  `gen_xnor_vectors.py` `_cfg.txt` header order, are provisional.
- `verification/isa/tests/periph/NPU.S` masks to 19 bits while reading 32-bit chip-config golden data.
