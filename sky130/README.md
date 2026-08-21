# VestaRV → SkyWater sky130: open-source RTL-to-GDSII flow

A complete, self-contained flow that takes the `vesta` core (RV32IMAC+Zb\*,
multicycle) from this repo's VHDL to a signoff-clean sky130 GDSII — synthesis,
place & route, CTS, routing, magic + KLayout DRC, netgen LVS — using only
open-source tools. Every tool here is FOSS (GHDL, Yosys, OpenROAD via
LibreLane, magic, KLayout, netgen, cocotb) and the sky130 PDK is Apache-2.0.

Verified result (2026-07-19): **magic DRC 0 · KLayout DRC 0 · LVS 0 · setup and
hold clean at all 9 corners** at a 125 ns (8 MHz) clock — 304k instances,
1.38 mm², sky130_fd_sc_hd. See "Timing honesty" below for why 8 MHz.

## Bazel: which half of this flow is managed, and which is not

**The RTL-to-GDSII flow on this page is NOT Bazel-managed.** `synth.sh`,
LibreLane/OpenROAD, magic, KLayout, netgen and the cocotb smoke test in `sim/`
are run exactly as documented under "Run it" below - they are external tool
installs (and a Docker image) with their own PDK pinning, and nothing here goes
through `//...`.

**What IS Bazel-managed is the verification of the same RTL** - the GHDL ISA
regression that proves the `vesta` core before it is hardened, plus the GHDL
toolchain itself, which Bazel builds from source rather than expecting on the
host. Run all commands below **from the repo root** (not from `sky130/`).

One-time bootstrap:

```sh
sh tools/get_bazel.sh            # fetches bazelisk into tools/bin/bazel
tools/bin/bazel test //...       # first run downloads all toolchains
```

### The Bazel half

| Target | What it proves / provides |
|--------|---------------------------|
| `//opensource_sim:isa_regression` | The whole license-free ISA regression: nine GHDL suites over the same RTL this flow hardens. This is the gate that says the RTL is worth 4-5 hours of LibreLane. |
| `//opensource_sim:isa_rv32ui`, `:isa_rv32um`, `:isa_rv32ua`, `:isa_rv32uc`, `:isa_rv32uzba`, `:isa_rv32uzbb`, `:isa_rv32uzbc`, `:isa_rv32uzbs`, `:isa_rv32uzf` | The individual suites, one `sh_test` each. |
| `//opensource_sim/isa:rv32ui` | The finer-grained port: one Bazel test per image, e.g. `//opensource_sim/isa:rv32ui-p-add`. Currently piloting `rv32ui`. |
| `//opensource_sim/isa:source_list_sync_test` | The per-test port's source list still matches the RTL file set. |
| `//hdl/common/tb:mp_arbiter_tb`, `//hdl/common/tb:pmp_unit_tb` | Unit benches under the same GHDL. |
| `//toolchains/ghdl:ghdl` | The GHDL simulator itself, built from source (mcode) by Bazel - no `apt install ghdl` needed for this half. |
| `//toolchains/ghdl:vhdl_libs_v08` | The pre-analyzed VHDL-2008 libraries that toolchain uses. |
| `//hdl:vhdl_sources` | Every tracked VHDL source as one filegroup - the same files `synth.sh` reads, though `synth.sh` applies its own curated 19-file analysis order. |
| `//verification/isa:os_rv32ui_rcfs` and siblings | The ON-polarity test images the suites execute; `//verification/isa:image_contract_test` proves the image set matches its contract. |

Typical use before starting a harden run:

```sh
tools/bin/bazel test //opensource_sim:isa_regression
```

Note that the GHDL version Bazel builds is independent of the `GHDL_VERSION`
pinned in `.github/workflows/physical.yml` for `synth.sh`; the two are
separate installs on purpose, and only the latter feeds the LibreLane bridge.

Full map of the Bazel build: [`BAZEL.md`](../BAZEL.md).

## Prerequisites

- **GHDL ≥ 5.x** (Debian trixie: `apt install ghdl`) — the VHDL→Verilog bridge
  and the simulator. LibreLane's own image has no VHDL frontend, hence the
  bridge.
- **LibreLane 3.0.5** (the OpenLane 2 successor) + the sky130 PDK at the
  **open_pdks revision pinned by that LibreLane version** (`8afc8346…`; install
  with `ciel`). Image tag and PDK revision must move in lockstep.
- For simulation: **cocotb 2.x** + gcc/make.

## Layout

- `synth.sh` — VHDL→Verilog conversion. Owns the curated 19-file analysis
  order (the tree has three conflicting `regfile` entities and a sim-only
  `ClkGate` — see the comments) and swaps the emitted clock-gate module for a
  real `sky130_fd_sc_hd__dlclkp_1` ICG cell. Output: `src/vesta.v`
  (generated, gitignored).
- `config.yaml` — LibreLane design config. The comments record the timing
  recipe and the failed-run provenance of every value.
- `pin_order.cfg`, `src/impl.sdc`, `src/signoff.sdc` — pins and constraints
  (async `resetn` is false-pathed; without it OpenSTA times reset arcs as
  setup paths and repair grinds).
- `sim/` — cocotb-on-GHDL smoke test: `vesta_harness.vhd` wires the core to a
  behavioral in-domain RAM preloaded with a 3-instruction program; the test
  asserts the core fetches and executes it (magic value lands in `a0`, the
  gated clock runs, no trap).

## Run it

```sh
cd sky130

# 1. VHDL -> src/vesta.v (any machine with ghdl)
./synth.sh

# 2. Verilog -> GDSII + DRC + LVS (LibreLane; ~4-5 h on one fast core)
python3 -m librelane --pdk-root <PDK_ROOT> config.yaml
#   -> runs/<tag>/final/gds/vesta.gds
#   -> runs/<tag>/final/metrics.json   <- verify signoff HERE, not in logs:
#      magic__drc_error__count, klayout__drc_error__count,
#      design__lvs_error__count, route__antenna_violation__count,
#      timing__setup_vio__count, timing__hold_vio__count

# 3. Simulation smoke (any machine with ghdl + cocotb)
cd sim && make            # results.xml + vesta_smoke.vcd
```

## CI (`.github/workflows/physical.yml`)

The flow is tier 3 of the repo's CI, entirely on GitHub-hosted runners:

- **Every PR / push / merge-group:** `verilog-bridge` (synth.sh under GHDL
  6.0.0) and `sim-smoke` (the cocotb test above). Minutes each; both are safe
  to require in the merge queue.
- **Weekly, `workflow_dispatch`, the `run-physical` PR label, and every
  release tag:** `harden` — the full LibreLane run, gated by
  `check_metrics.py` on `final/metrics.json` (the six signoff counts above
  must be present and zero; a missing count fails). GDS + netlists + metrics
  + reports upload as the `vesta-sky130-signoff` artifact.
- **Releases:** pushing a tag `vX.Y.Z` runs `release.yml`, which calls this
  workflow and publishes the signoff bundle, the bridge netlist, and the TRM
  on the GitHub release — after the CHANGELOG section for that version is
  found and the signoff gate passes.

The workflow pins `ubuntu-24.04` (the GHDL release tarball is built per-OS)
and `librelane==3.0.5` via `--dockerized`, which keeps the tool image and the
open_pdks revision in the lockstep this README already requires. Bump
`GHDL_VERSION` / `LIBRELANE_VERSION` there together with this file.

## Notes for anyone modifying the flow

- **`--latches` is required**: the `ClkGate` body and a latched result net in
  `div.vhd` are intentional (both are in the silicon-proven TSMC netlist).
- **The ICG swap is not optional.** The behavioral latch+AND clock gate
  simulates correctly but generic CTS mis-times the gated `clk_cpu` branch by
  half a period for hold checks (measured: hold WNS −38 ns across 1,526
  endpoints). The netlist-level substitution keeps the VHDL fully portable.
- **Yosys check waivers**: the post-ABC `check` reports ~66 "logic loop"
  problems through the register-file `sp_in` mux trees. All verified false
  positives (`check -force-detailed-loop-check` reports 0), hence
  `ERROR_ON_SYNTH_CHECKS: false` in the config.
- **Timing honesty**: 125 ns closes all 9 corners. The wall is not the core —
  reg-to-reg it is ~13 ns deep (~75 MHz) — but the combinational unified-bus
  interface: the FF→`write_data`/`data_addr` store cone measures 107.5 ns at
  ss_100C_1v60 with extracted parasitics. A registered memory interface (TCM
  macro) is the Fmax lever, not synthesis knobs. 40 ns is unclosable as-is;
  `FP_CORE_UTIL` must stay ≤ 28 or global routing congests.
- Two mechanical patches on this branch make the tree GHDL-clean (an overload
  ambiguity in `alu.vhd`, a subtype-range underflow in `vesta.vhd`'s Zcmp
  lookup); neither changes logic.
