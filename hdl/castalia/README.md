# Castalia testbench

Castalia's RTL is the default configuration of [`hdl/common/`](../common/README.md);
`hdl/common/MCU.vhd` and `MemoryMap.vhd` are the only copies the flows compile.
This directory holds only `tb/riscv_tb.vhd`, the five-hart ISA-regression testbench,
byte-identical to `hdl/common/tb/riscv_tb.vhd` (graded by
`//platform/common:check_riscv_tb_vhd_test`). Regenerate with
`tools/bin/bazel run //:generate` or, hermetically,
`tools/bin/bazel build //platform/common:chip_artifacts_castalia`.
