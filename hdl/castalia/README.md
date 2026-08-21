# Castalia — 5-hart wound-monitoring MCU

Chip-specific RTL for **Castalia**, the five-core wound-monitoring chip:
hart 0 is the always-on orchestrator (`orch_tile`) and harts 1-4 are the
channel tiles (`hart_tile`), on the shared-bus MCU_MP fabric with the NPU.
`config` = the default Castalia configuration in `platform/common/`.

```
castalia/
├── MCU.vhd        — Castalia top-level (5 harts) — make-chip product
├── MemoryMap.vhd  — Castalia peripheral/address constants — make-chip product
└── tb/
    └── riscv_tb.vhd — 5-hart ISA-regression testbench (a0 + a0_1/2/3/4 monitors)
```

## Building and testing with Bazel

`MCU.vhd` and `MemoryMap.vhd` in this directory are generated products. Bazel
runs that generation hermetically, in a sandbox, with the identity checks
attached; it is the recommended path and the legacy `make chip` still works.
Every command is run from the repo root.

One-time bootstrap:

```sh
sh tools/get_bazel.sh            # fetches bazelisk into tools/bin/bazel
tools/bin/bazel test //...       # first run downloads all toolchains
```

| Target | Verb | What it proves |
|---|---|---|
| `//platform/common:chip_artifacts_castalia` | build | the whole Castalia artifact set is regenerated hermetically - the sandboxed equivalent of `make chip` |
| `//platform/common:castalia_mcu_vhd` | build | just the generated `MCU.vhd` |
| `//platform/common:castalia_memorymap_vhd` | build | just the generated `MemoryMap.vhd` |
| `//platform/common:castalia_riscv_tb_vhd` | build | just the generated `tb/riscv_tb.vhd` |
| `//platform/common:check_mcu_vhd_test` | test | the tracked `MCU.vhd` is identical to what the generator emits today |
| `//platform/common:check_memorymap_vhd_test` | test | the same for `MemoryMap.vhd` |
| `//platform/common:check_riscv_tb_vhd_test` | test | the same for the 5-hart `tb/riscv_tb.vhd` |
| `//platform/common:generation_determinism_test` | test | two generations of the same config are byte-identical |
| `//hdl:vhdl_sources` | build | this directory's VHDL is a declared build input of the graph |

Never run `bazel run //:generate`: that is the raw generator and writes wherever
it happens to run. `chip_artifacts_castalia` is the hermetic path.

The full target map is in [`BAZEL.md`](../../BAZEL.md).

## ⚠ Source of truth

Castalia is the **default configuration of the shared multi-core tree
`hdl/common/`** — all sub-modules (`vesta/`, `periph/`, `commune/`,
`hart_tile.vhd`, `mp_arbiter.vhd`, …) live there and are shared with Argus.
The files in this directory are the Castalia instantiation of that tree.

- `MCU.vhd` / `MemoryMap.vhd` are **generated** by `platform/common`
  (`make chip`) — NEVER hand-edit them, here or in `hdl/common/`.
  Change `hdl_templates/MCU.template.vhd` or `generate.py`/`mcu_vhd.py`,
  re-run `make chip`, and verify with `check_mcu_vhd.py` / `check_memorymap_vhd.py`.
- The simulation/synthesis flows (`xcelium/riscv_test/*/cell_list_*.txt`,
  genus/innovus flows) currently compile **`hdl/common/`**, not this
  directory. If the copies here and in `hdl/common/` diverge, `hdl/common/`
  is what the flows build — re-sync from `hdl/common/` (or from
  `platform/common/out/hdl/`) rather than editing here.

Sibling layout: `hdl/myshkin/` = frozen single-core tape-out (do not touch),
`hdl/argus/` = frozen 18-hart teaching-chip snapshot, `hdl/common/` = shared
multi-core RTL where all RTL changes go.
