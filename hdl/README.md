# HDL Sources

VHDL-2008 RTL for VestaRV. All RTL changes go to `common/`.

| Directory | Contents |
|---|---|
| [`common/`](common/README.md) | Live shared RTL, generated top level, unit benches |
| [`castalia/`](castalia/README.md) | Castalia ISA-regression testbench |
| `argus/`, [`myshkin/`](myshkin/README.md) | Frozen chip snapshots; do not edit |
| [`fpga/`](fpga/README.md) | Synthesizable FPGA stand-ins for ASIC cells |

```sh
tools/bin/bazel test //hdl/common/tb:all               # GHDL unit benches
tools/bin/bazel test //opensource_sim:isa_regression   # ISA suites, no licenses
```

Interactive simulation (waveforms) is outside Bazel: any VHDL-2008 simulator.
Full target map: [`BAZEL.md`](../BAZEL.md).
