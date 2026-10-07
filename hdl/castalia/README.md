# Castalia testbench

Castalia's RTL is the default configuration of [`hdl/common/`](../common/README.md).
This directory holds only `tb/riscv_tb.vhd`, the five-hart ISA-regression testbench,
byte-identical to `hdl/common/tb/riscv_tb.vhd` (graded by
`//platform/common:check_riscv_tb_vhd_test`). Regenerate with
`tools/bin/bazel build //platform/common:chip_artifacts_castalia`.
