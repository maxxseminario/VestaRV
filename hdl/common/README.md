# hdl/common: shared multi-core RTL

Live RTL for every `platform/common/` configuration (Castalia, Argus, the ASIC and
FPGA defaults): core, peripherals, multi-hart fabric and top level. All RTL changes
go here; `hdl/argus/` and `hdl/myshkin/` are frozen snapshots.

## Rules

- `MCU.vhd` and `MemoryMap.vhd` are generated; never hand-edit them. Regenerate with
  `tools/bin/bazel run //:generate` (writes `platform/common/out/hdl/`) or hermetically
  with `tools/bin/bazel build //platform/common:chip_artifacts_castalia`.
  `//platform/common:check_mcu_vhd_test` and `:check_memorymap_vhd_test` fail on any
  difference between the tracked files and a fresh generation.
- Register packages in `regs/vhdl/` are generated from SystemRDL in `regs/rdl/`;
  regenerate with `tools/bin/bazel run //:regs` ([`regs/README.md`](regs/README.md)).
- Every clock-domain crossing uses `entity work.sync` (`sync.vhd`), instance named
  `u_sync_<signal>`. The manifest gate and Genus census enforce it
  ([`cdc/README.md`](cdc/README.md)).
- Gate clocks with `ClkGate` (`commune/`), never with combinational enables.

## Layout

| Path | Contents |
|---|---|
| `MCU.vhd`, `MemoryMap.vhd` | Generated top level (port list = chip pads) and address constants |
| `orch_tile.vhd` | Hart 0 orchestrator tile, full chip ISA |
| `hart_tile.vhd` | Hardened tile; every hart when `orchestrator = false` |
| `mp_arbiter.vhd`, `resv_unit.vhd` | Round-robin shared-window arbiter; global LR/SC reservation table |
| `clint.vhd`, `mutex_bank.vhd`, `irq_router.vhd` | Timer/software interrupts, hardware mutexes, per-hart interrupt routing |
| `pwr_ctrl.vhd` | MTCMOS gate/wake sequencing of tile power domains |
| `debug_module.vhd`, `jtag_dtm.vhd` | Debug transport (`debug.enable`) |
| `adddec.vhd`, `constants.vhd`, `afe_stub.vhd` | Address decoder, global types, analog front-end stub |
| `periph_regs.vhd`, `regs/` | Shared register-file module; SystemRDL sources and generated packages |
| `vesta/` | Core: multicycle FSM (`controller.vhd`), decoders, ALU, divider, CSRs, PMP, FPU, IRQ handler, tracer |
| `periph/` | GPIO, SPI, QSPI, UART, I2C, I2CTarget, I3C, TIMER, PWM, RTC, OneWire, DMA, EVFAB, TRNG, NFC, NPU, SYSTEM |
| `commune/` | Clock gate, divider, glitch-free clock mux, CRC16, NPU floating-point units, memory wrappers |
| `sim/` | Behavioural models: RAM, ROM, clock cells, oscillator, POR |
| `tb/`, `synth/`, `power/`, `cdc/` | Unit benches, synthesizability, isolation-clamp audit, CDC gate |

The core executes fetch→decode→execute→writeback under one FSM with stack-based
re-entrant interrupts (vector count `NUM_IRQS` in `MemoryMap.vhd`). ISA knobs and the
per-hart-class table are in the [root README](../../README.md) and the
[Castalia TRM](../../implementations/asic/castalia/docs/TRM.pdf).

## How the tree is consumed

- GHDL simulation and unit benches through `//hdl:vhdl_sources` and
  `//hdl/common/tb:tb_vhdl_sources`.
- Genus synthesis and Xcelium simulation compile this tree directly (outside Bazel,
  after `source cdspaths.sh`).
- FPGA builds swap ASIC cells for the stand-ins in [`hdl/fpga/`](../fpga/README.md).

## Test

| Target | Covers |
|---|---|
| `//hdl/common/tb:all` | GHDL unit benches (core blocks and peripherals) |
| `//hdl/common/synth:synth` | Synthesizability of every block |
| `//opensource_sim:isa_regression` | Nine GHDL ISA suites; one image: `//opensource_sim/isa:rv32ui-p-add` |
| `//hdl/common/cdc:cdc_manifest_test` | Sync instances and waiver list unchanged |
| `//tools/python:check_entity_defaults_test` | Generic defaults in `vesta.vhd`, `hart_tile.vhd` agree with the generator |
