# HDL Sources

This directory contains all VHDL source files for VestaRV, organized into the MCU top-level and its sub-modules.

---

## Building and testing with Bazel

Bazel is the recommended way to build and exercise this RTL. It provisions
GHDL, the RISC-V cross compiler and Python itself, so nothing below needs a
local install. Every command is run from the repo root.

One-time bootstrap:

```sh
sh tools/get_bazel.sh            # fetches bazelisk into tools/bin/bazel
tools/bin/bazel test //...       # first run downloads all toolchains
```

Targets that cover this directory:

| Target | Verb | What it proves |
|---|---|---|
| `//hdl:vhdl_sources` | build | every tracked `*.vhd` / `*.vhdl` under `hdl/` is a declared build input; `hdl/common/tb` is its own package and re-exports through `//hdl/common/tb:tb_vhdl_sources` |
| `//hdl:npu_vhd` | build | the single-file handle for `common/periph/NPU.vhd` that the TRM diagram scraper reads |
| `//hdl/common/tb:mp_arbiter_tb` | test | four synthetic masters contending for one shared single-port RAM, under GHDL |
| `//hdl/common/tb:pmp_unit_tb` | test | all three `pmp_unit` generic shapes (PMP on with 16 and 8 entries, PMP off) in one run |
| `//hdl/common/tb:fpu_vectors_format_test` | test | the FPU reference-vector generator is deterministic and emits the fixed-width record format `fpu_tb.vhd` parses |
| `//opensource_sim:isa_regression` | test | this RTL passes all nine GHDL ISA suites, with no licensed tool anywhere |
| `//tools/python:check_entity_defaults_test` | test | the entity-generic defaults in the core RTL still agree with the generator and `MemoryMap.vhd` |
| `//tools:check_tracer_independence_test` | test | `vesta_tracer.vhd` still derives retire from its own logic |

`//hdl/common/tb:fpu_vec_gen` and `//hdl/common/tb:fpu_vectors_generated` build
the host-side FPU vector generator, but they are a convenience only:
`gen_fpu_vectors.sh` under a native gcc stays authoritative. Read the loud
comment in `hdl/common/tb/BUILD.bazel` before using their output.

The full target map is in [`BAZEL.md`](../BAZEL.md).

---

## Directory Structure

```
hdl/
└── MCU/
    ├── MCU.vhd            — Top-level MCU entity (connects core, memory, peripherals)
    ├── MemoryMap.vhd      — Generated peripheral address constants 
    ├── constants.vhd      — Global type and constant definitions
    ├── adddec.vhd         — Address decoder
    ├── vesta/             — VestaRV processor core
    ├── periph/            — Peripheral modules
    ├── commune/           — Shared components (memories, clock gates, synchronizers)
    ├── macros/            — Synthesis macros and wrappers
    ├── sim/               — Simulation-only behavioural models (RAM, ROM, clocks)
    └── tb/                — Testbenches
```

See the [Castalia TRM](../implementations/asic/castalia/docs/TRM.pdf) for a detailed breakdown of the core architecture and peripheral list.

---

## Simulation

Legacy / manual path. This is the by-hand simulator setup; it still works and
is what you want for waveform debugging in a specific simulator. The Bazel
section above runs the same RTL under a GHDL that the build provisions for you.

### Prerequisites

Any **VHDL-2008-compatible** simulator works. Recommended free options:

| Simulator | Install |
|-----------|---------|
| [GHDL](https://github.com/ghdl/ghdl) | Clone and build from source: `git clone https://github.com/ghdl/ghdl` — see repo for build instructions |
| [NVC](https://github.com/nickg/nvc) | Clone and build from source: `git clone https://github.com/nickg/nvc` — see repo for build instructions |
| ModelSim / Questa | Available free via Intel FPGA Lite edition |
| Xcelium | Commercial (Cadence) |

GHDL is the recommended open-source option.

