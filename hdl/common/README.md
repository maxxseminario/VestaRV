# hdl/common: shared multi-core RTL

Live RTL for every `platform/common/` configuration: core, peripherals, multi-hart
fabric and top level. All RTL changes go here.

- `MCU.vhd` and `MemoryMap.vhd` are generated; never hand-edit. Regenerate with
  `tools/bin/bazel build //platform/common:chip_artifacts_castalia`;
  `tools/bin/bazel test //platform/...` fails on any difference.
- `regs/vhdl/` is generated from SystemRDL ([`regs/README.md`](regs/README.md)).
- Clock-domain crossings use `entity work.sync` (`sync.vhd`), named `u_sync_<signal>`
  ([`cdc/README.md`](cdc/README.md)).

| Path | Contents |
|---|---|
| `orch_tile.vhd`, `hart_tile.vhd` | Hart 0 orchestrator; hardened tile |
| `mp_arbiter.vhd`, `resv_unit.vhd` | Shared-window arbiter; LR/SC reservations |
| `clint.vhd`, `mutex_bank.vhd`, `irq_router.vhd`, `pwr_ctrl.vhd` | Shared system blocks |
| `debug_module.vhd`, `jtag_dtm.vhd` | Debug transport |
| `vesta/`, `periph/`, `commune/`, `sim/` | Core, peripherals, shared cells, behavioural models |
| `tb/`, `synth/`, `power/`, `cdc/` | Benches, synthesizability, isolation audit, CDC gate |

```sh
tools/bin/bazel test //hdl/common/tb:all //hdl/common/synth:synth
tools/bin/bazel test //opensource_sim:isa_regression
```
