# Castalia - 5-hart wound-monitoring MCU

Castalia is the **default configuration of the shared multi-core tree
`hdl/common/`**: hart 0 is the always-on orchestrator (`orch_tile`), harts 1-4
are the channel tiles (`hart_tile`), and every sub-module (`vesta/`, `periph/`,
`commune/`, `mp_arbiter.vhd`, the NPU) lives in `hdl/common/` and is shared with
Argus. The generated top level and memory map therefore live at
`hdl/common/MCU.vhd` and `hdl/common/MemoryMap.vhd` - that is the single copy
the simulation, synthesis and place-and-route flows compile, and the copy the
identity gates `//platform/common:check_mcu_vhd_test` and
`:check_memorymap_vhd_test` hold against a fresh run of the generator. A second,
ungated copy of both files used to sit in this directory; it had gone stale by
one generator revision (emitted 2026-08-16, `NUM_IRQ_SRCS` 121 against
`hdl/common`'s 124) while no BUILD file, flow script or filelist named it, so it
was removed rather than re-synced. Regenerate through
`//platform/common:chip_artifacts_castalia`, never `bazel run //:generate`.

What remains here is `tb/riscv_tb.vhd`, the 5-hart ISA-regression testbench
(`a0` plus the `a0_1`..`a0_4` monitors). It is byte-identical to
`hdl/common/tb/riscv_tb.vhd`, which is what `//platform/common:check_riscv_tb_vhd_test`
grades. Sibling trees: `hdl/myshkin/` = frozen single-core tape-out (do not
touch), `hdl/argus/` = frozen 18-hart teaching-chip snapshot, `hdl/common/` =
the live shared RTL where all RTL changes go. The full target map is in
[`BAZEL.md`](../../BAZEL.md).
