# VestaRV → SkyWater sky130: open-source RTL-to-GDSII flow

Hardens the `vesta` core from VHDL to signoff-clean sky130 GDSII with GHDL, Yosys,
LibreLane (OpenROAD), magic, KLayout and netgen. Closes all 9 corners at 125 ns (8 MHz).
Needs GHDL ≥ 5.x, LibreLane 3.0.5 with the sky130 PDK revision it pins (`ciel`), and
cocotb 2.x for `sim/`.

```sh
tools/bin/bazel test //opensource_sim:isa_regression     # repo root: GHDL ISA regression first
cd sky130
./synth.sh                                               # VHDL -> src/vesta.v
python3 -m librelane --pdk-root <PDK_ROOT> config.yaml   # ~4-5 h -> runs/<tag>/final/
cd sim && make                                           # cocotb smoke test
```

Verify signoff from `runs/<tag>/final/metrics.json`, not the logs: the DRC (magic, KLayout),
LVS, antenna, setup and hold violation counts must be present and zero; `check_metrics.py`
enforces this in `.github/workflows/physical.yml`.

| File | Role |
|---|---|
| `synth.sh` | Curated VHDL analysis order; swaps in the `sky130_fd_sc_hd__dlclkp_1` ICG |
| `config.yaml` | LibreLane config; comments record the timing recipe |
| `pin_order.cfg`, `src/*.sdc` | Pins and constraints (async `resetn` false-pathed) |

Rules:

- `--latches` and the ICG swap are required; a behavioural clock gate mis-times CTS hold.
- Fmax is limited by the combinational memory-bus store cone; keep `FP_CORE_UTIL` ≤ 28.
- Bump `GHDL_VERSION` / `LIBRELANE_VERSION` in `physical.yml` together with this file.

Build map: [`BAZEL.md`](../BAZEL.md).
