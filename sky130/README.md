# VestaRV → SkyWater sky130: open-source RTL-to-GDSII flow

Takes the `vesta` core (RV32IMAC+Zb\*, multicycle) from VHDL to signoff-clean sky130 GDSII
with FOSS tools only: GHDL, Yosys, OpenROAD via LibreLane, magic, KLayout, netgen, cocotb.
Result: magic DRC 0, KLayout DRC 0, LVS 0, setup and hold clean at all 9 corners at 125 ns
(8 MHz); 304k instances, 1.38 mm², `sky130_fd_sc_hd`.

## Prerequisites

- GHDL ≥ 5.x (VHDL→Verilog bridge; LibreLane has no VHDL frontend).
- LibreLane 3.0.5 + sky130 PDK at the open_pdks revision pinned by that LibreLane version
  (`8afc8346…`; install with `ciel`). Image tag and PDK revision move together.
- cocotb 2.x + gcc/make for simulation.

## Run

```sh
cd sky130
./synth.sh                                               # VHDL -> src/vesta.v (generated)
python3 -m librelane --pdk-root <PDK_ROOT> config.yaml   # ~4-5 h -> runs/<tag>/final/
cd sim && make                                           # cocotb smoke: results.xml + vesta_smoke.vcd
```

Verify signoff from `runs/<tag>/final/metrics.json`, not the logs: `magic__drc_error__count`,
`klayout__drc_error__count`, `design__lvs_error__count`, `route__antenna_violation__count`,
`timing__setup_vio__count`, `timing__hold_vio__count` must all be present and zero
(`check_metrics.py` enforces this in CI).

| File | Role |
|---|---|
| `synth.sh` | Curated VHDL analysis order; swaps the behavioural clock gate for `sky130_fd_sc_hd__dlclkp_1` |
| `config.yaml` | LibreLane config; comments record the timing recipe |
| `pin_order.cfg`, `src/impl.sdc`, `src/signoff.sdc` | Pins and constraints (async `resetn` false-pathed) |
| `sim/` | cocotb-on-GHDL smoke test: core fetches and executes a 3-instruction program |
| `check_metrics.py` | Signoff gate on `final/metrics.json` |

## Bazel (verification only)

The flow above is not Bazel-managed. Bazel runs the GHDL ISA regression over the same RTL,
with GHDL built from source. From the repo root (build map: [`BAZEL.md`](../BAZEL.md)):

```sh
sh tools/get_bazel.sh
tools/bin/bazel test //opensource_sim:isa_regression     # run before a harden
```

| Target | Role |
|---|---|
| `//opensource_sim:isa_regression` | All nine ISA suites |
| `//opensource_sim:isa_rv32ui` … `:isa_rv32uzf` | One suite each (`ui um ua uc uzba uzbb uzbc uzbs uzf`) |
| `//opensource_sim/isa:rv32ui` | Per-image tests, e.g. `//opensource_sim/isa:rv32ui-p-add` |
| `//toolchains/ghdl:ghdl` | GHDL built by Bazel; independent of `GHDL_VERSION` in `physical.yml` |
| `//hdl:vhdl_sources` | All tracked VHDL (`synth.sh` uses its own subset and order) |

## CI (`.github/workflows/physical.yml`)

| Job | When |
|---|---|
| `verilog-bridge`, `sim-smoke` | Every PR / push / merge group |
| `harden` (full LibreLane + `check_metrics.py`) | Weekly, `workflow_dispatch`, `run-physical` PR label, release tags |

A tag `vX.Y.Z` runs `release.yml`: it requires a `## [X.Y.Z]` section in `CHANGELOG.md`
(used as release notes), reruns this workflow with the signoff gate, and publishes the GHDL
bridge netlist, the LibreLane signoff bundle (GDSII, netlists, `metrics.json`, reports) and
the TRM. `GHDL_VERSION` and `LIBRELANE_VERSION` in the workflow move together with this file.

## Rules for modifying the flow

- `--latches` is required: the `ClkGate` body and a latched net in `div.vhd` are intentional.
- The ICG swap is mandatory: with the behavioural clock gate, CTS mis-times the gated
  `clk_cpu` branch by half a period (hold WNS −38 ns).
- `ERROR_ON_SYNTH_CHECKS: false` waives ~66 false-positive Yosys logic loops through the
  register-file `sp_in` muxes (`check -force-detailed-loop-check` reports 0).
- Fmax is limited by the combinational memory-bus store cone (107.5 ns at ss_100C_1v60), not
  the core (~13 ns reg-to-reg). 40 ns does not close; keep `FP_CORE_UTIL` ≤ 28.
