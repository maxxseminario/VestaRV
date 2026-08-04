# VestaRV → SkyWater sky130: open-source RTL-to-GDSII flow

A complete, self-contained flow that takes the `vesta` core (RV32IMAC+Zb\*,
multicycle) from this repo's VHDL to a signoff-clean sky130 GDSII — synthesis,
place & route, CTS, routing, magic + KLayout DRC, netgen LVS — using only
open-source tools. Every tool here is FOSS (GHDL, Yosys, OpenROAD via
LibreLane, magic, KLayout, netgen, cocotb) and the sky130 PDK is Apache-2.0.

Verified result (2026-07-19): **magic DRC 0 · KLayout DRC 0 · LVS 0 · setup and
hold clean at all 9 corners** at a 125 ns (8 MHz) clock — 304k instances,
1.38 mm², sky130_fd_sc_hd. See "Timing honesty" below for why 8 MHz.

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
