# HDL Sources

VHDL-2008 RTL for VestaRV. All RTL changes go to `common/`; the chip snapshots are
frozen.

| Directory | Contents |
|---|---|
| [`common/`](common/README.md) | Live shared multi-core RTL: core, peripherals, generated `MCU.vhd` / `MemoryMap.vhd`, unit benches |
| [`common/cdc/`](common/cdc/README.md) | CDC manifest gate and Genus waiver list |
| [`castalia/`](castalia/README.md) | Castalia ISA-regression testbench only |
| `argus/` | Frozen 18-hart Argus snapshot |
| [`myshkin/`](myshkin/README.md) | Frozen single-core tape-out snapshot |
| [`fpga/`](fpga/README.md) | Synthesizable FPGA stand-ins for ASIC cells |

## Build and test

From the repo root (`sh tools/get_bazel.sh` once):

| Target | Verb | Covers |
|---|---|---|
| `//hdl:vhdl_sources` | build | Every tracked `*.vhd`/`*.vhdl` under `hdl/` (`common/tb` re-exports via `//hdl/common/tb:tb_vhdl_sources`) |
| `//hdl/common/tb:all` | test | GHDL unit benches |
| `//hdl/common/synth:synth` | test | Synthesizability of every block |
| `//opensource_sim:isa_regression` | test | Nine GHDL ISA suites, no licensed tools |
| `//tools/python:check_entity_defaults_test` | test | Entity-generic defaults agree with the generator and `MemoryMap.vhd` |
| `//tools:check_tracer_independence_test` | test | `vesta_tracer.vhd` derives retire from its own logic |

`//hdl/common/tb:fpu_vectors_generated` is a convenience build; `gen_fpu_vectors.sh`
under a native gcc stays authoritative (see `common/tb/BUILD.bazel`). Full map:
[`BAZEL.md`](../BAZEL.md).

Interactive simulation (waveforms, single-stepping) is outside Bazel: use any
VHDL-2008 simulator (GHDL, NVC, Questa, Xcelium).
