# maestro2tex

Turns a Cadence Maestro (ADE Assembler) run into a directory of TikZ/pgfplots figures
and booktabs tables that the LaTeX TRM `\input`s directly. No screenshots, no manual
transcription of numbers — the characterisation in the manual is regenerated from the
simulation results.

```
python3 maestro2tex.py \
    --results ~/chips/castalia/ic/.simulation/castalia/BiasGenCascWideSwing_tb/maestro/results/maestro/Interactive.32 \
    --config  configs/BiasGenCascWideSwing_tb.json \
    --outdir  ../../latex/analog
```

## How it works

Two stages, deliberately separated:

1. **Extract** — shells out to OCEAN (`/opt/cadence/IC618/tools.lnx86/dfII/bin/ocean
   -nograph`) and dumps every requested signal to a two-column CSV under
   `<outdir>/data/raw/`. OCEAN is used because it is the only reader on this machine
   that handles **both** binary PSF and **PSFXL** (the transient results are PSFXL, so
   the pure-Python PSF readers would not help). This stage checks out a Virtuoso
   licence.
2. **Render** — pure Python 3.6 stdlib. Reads only the CSVs and writes the LaTeX. Run
   it with `--no-extract` to iterate on captions, tables and plot styling without
   taking a licence again.

The generated `extract_<Block>.ocn` and the full OCEAN log are left in `<outdir>/data/`
so a failed extraction is debuggable. Everything a block writes is named after that
block, because all of a chip's blocks render into one `outdir` and share `data/`.

## Output layout

```
<outdir>/
  <Block>.tex                    master — the one file the TRM inputs
  fig_*.tex                      one pgfplots figure each
  tab_*.tex                      one booktabs table each
  preview_<Block>.tex/.pdf       standalone proof sheet (pdflatex preview_<Block>.tex)
  data/*.dat                     plot data, one file per curve
  data/raw/*.csv                 raw OCEAN dumps (input to the render stage)
  data/extract_<Block>.ocn/.log  what was run, and what it said
```

## Including it in the TRM

The TRM builds with `cwd = platform/common/latex/TRM/`, so with the default
`--outdir ../../latex/analog` the include is one line:

```latex
\input{../analog/BiasGenCascWideSwing.tex}
```

Every path inside the generated files goes through `\MaestroRoot`, which defaults to
the `tex_root` in the config (`../analog/`). To include the same fragments from a
document at a different depth, `\def\MaestroRoot{...}` before the `\input` — that is
exactly what `preview_<Block>.tex` does (it sets it empty and compiles from inside
`outdir`).

Required packages — `pgfplots`, `booktabs`, `siunitx`, `xcolor`, `placeins` — are all
already in the TRM's `packages-commands.tex`. The master file wraps the block in
`\FloatBarrier` at both ends: a block is a dozen-odd floats in a row, so without it
LaTeX's float queue runs pages behind the text and one block's figures surface inside
the next block's prose. The figures set `compat=1.18` inside a TeX group so
they cannot disturb the document's other pgfplots pictures, which set no compat level.

Two things to know about the TRM pipeline:

- `latex/TRM/` is **generated** by `make chip`, but nothing there is wiped: the
  generator only writes named files and `make clean` only removes build artifacts. It
  is still cleaner to keep this output in `latex/analog/` (a source sibling, like
  `latex/PeripheralIntroductions/`) rather than inside the generated tree.
- Adding content changes `TRM.pdf`, so `make check-publish` will report the published
  copy as stale until you `make publish`. That is the drift gate working as intended,
  not a fault.

## Writing a config

One JSON file per testbench; `configs/BiasGenCascWideSwing_tb.json` is the worked
example. Keys:

| Key | Meaning |
|---|---|
| `block` | names the master `.tex` and the corner table |
| `tex_root` | default `\MaestroRoot` (path from the TRM to `outdir`) |
| `nominal_corner` | corner used when a figure/table does not name one |
| `supply_var` | design variable reported in the corner table |
| `intro_tex` | prose emitted at the top of the master file |
| `signals` | logical name → `expr` (any OCEAN expression), `label`, `unit_tex`, `scale`, `digits` |
| `tests` | per test: `result` (`dc`/`tran`/`dcOp`/`ac`/`stb`/`noise`/…), `dir`, `xlabel`, `xunit_tex`, `xscale`, `nominal_x`, and `signals` overrides |
| `figures` | `id`, `test`, `signals`, `corners` (list or `"all"`), `caption`, `legendpos`, `yprec`, `xlog`, `ylog`, `axis_extra`, `width`, `height`; or `kind: "heatmap"` / `"sweepline"` / `"histogram"` (see below) |
| `tables` | `id`, `type` `matrix` (signals × corners), `bycorner` (corners × signals), `stats` (signals × statistics), or `mcstats` (Monte Carlo, see below) |
| `order` | explicit order of fragments in the master file |
| `emit_master` | `false` for a companion config that only contributes fragments |
| `emit_corner_table` | `false` to suppress the point/process/temp/supply legend table |
| `points` | `["1-130", "136"]` — which numeric point directories this config claims |
| `monte_carlo` | `true` to read a Monte Carlo run instead of corner points (see below) |

`id` is mandatory on every figure and table: it names the fragment (`fig_<id>.tex`,
`tab_<id>.tex`), the `\label`, and the entry you list in `order`.

`signals` is per-test overridable because the same quantity is often a different node
in a different testbench — in the bias generator the supply current is
`i("/POWER/SRC_VDD25/PLUS")` in the DC benches but `i("/V0/PLUS")` in the startup
bench.

A config `test` is a *logical* test: one analysis, with its own signals, x-axis and
figures. One Maestro test directory usually holds several (`ac`, `dc`, `stb`,
`stb_margin`, `noise`, `dcOp`, `tran` all live in `TypOpenLoopWBiasTB/psf`), so give
each logical test a name of its own and point it at the directory with `dir`. `dir`
defaults to the test name, which is what a bench with a single analysis wants:

```json
"ol_ac":  { "dir": "TypOpenLoopWBiasTB", "result": "ac", ... },
"ol_dc":  { "dir": "TypOpenLoopWBiasTB", "result": "dc", ... }
```

A signal expression does not have to be a waveform. Anything OCEAN can reduce to a
number — `unityGainFreq(...)`, `getData("phaseMargin")`, `ymax(deriv(...))`,
`sqrt(integ(...))` — is dumped as a scalar and can be a table row, which is how the
derived figures of merit (margins, slew rate, integrated noise) get into the manual
without being transcribed.

Set `xlog`/`ylog` on a figure for decade axes; they also drop the fixed-point tick
format from that axis, which on a log axis would label every tick `0.0`.

## Two-dimensional sweeps (`kind: "heatmap"`)

When a bench sweeps a design variable *and* an analysis parameter, Maestro writes one
point directory per design-variable value. `discover_corners` already treats those as
corners (de-duplicating the repeated process label into `ff1`, `ff2`, …) and already
parses each point's design variables, so **extraction needs no special case** — the
per-corner CSVs *are* the grid.

A `heatmap` figure assembles them: `xvar` names the design variable that orders the
corners onto x, the analysis sweep becomes y, and `signal` becomes colour.

```json
{ "id": "...", "kind": "heatmap", "test": "drive_map", "signal": "verr",
  "xvar": "V_map", "corners": "all",
  "yscale": 1e6, "zscale": 1e3, "ylimit": [-8e-6, 8e-6], "ystep": 2,
  "zmin": -50, "zmax": 50,
  "overlay": [ {"signal": "i_sink", "legend": "sinking edge", "scale": 1e6} ] }
```

- `zmin`/`zmax` clip the colour scale. Clip it to whatever the *criterion* is, so the
  colour boundary and the engineering boundary are the same line.
- `overlay` draws scalar-per-corner signals as curves on the map — an envelope plotted
  on the data it was derived from. Because the scalars come from `cross()` on the full
  sweep and the raster from the extracted grid, the two agreeing is a real check.
- `ylimit`/`ystep` crop and decimate the raster. The y-axis is pinned to the raster, so
  overlay curves that shoot off outside the interesting region are clipped instead of
  dragging the axis out until the map is a sliver.
- Colour uses the documented diverging pair (blue↔red, neutral gray midpoint). The red
  arm is not eyeballed: each step is the blue step of the same OKLab lightness re-hued
  to the categorical red, so the arms are perceptually symmetric.

`bycorner` is the matching table: corners become rows and signals columns, ordered by
`sortvar`. A 26-point sweep as a `matrix` table would be 26 columns wide.

**Watch the cell count.** pgfplots builds one TeX path per cell. 26×321 compiled fine as
a standalone proof sheet and then blew `TeX capacity exceeded, main memory size` inside
the 200-page TRM; 26×161 builds. The tool warns above 5000 cells — raise `ystep` or
narrow `ylimit`, and let the overlay curves carry the exact edges, which they do at full
sweep resolution regardless of how coarse the raster is.

Available statistics: `value`, `nominal` (interpolated at `nominal_x`), `min`, `max`,
`mean`, `spread`, `first`, `last`, `settle` (last exit from a ±1 % band around the
final value), `sens_pct_per_x` (%/unit) and `ppm_per_x` (ppm/unit).

## Monte Carlo (`"monte_carlo": true`)

A Monte Carlo run does **not** fit the corner-point model and is read by a separate
path. Maestro runs MC in chunks, so the numeric directories are chunks rather than
corners (`numruns=17`, 200 samples → `1, 18, 35, … 188`) and none of them holds the
per-sample results. Spectre appends every sample's scalars to one aggregate pair of
files under the *non-numeric* sibling `psf/`:

```
<run>/psf/<test>/monteCarlo/mcdata    one tab-separated row per sample, no header
<run>/psf/<test>/monteCarlo/mcparam   one row per output, in mcdata column order:
                                      name <TAB> spec_lo <TAB> spec_hi <TAB> "expr"
```

`mcparam` is self-describing, so the column mapping *and* the spec limits come from the
run itself. `±1e+36` means unbounded. Because the data is already reduced to scalars,
**this path needs no OCEAN and no Virtuoso licence** — it is a parse and a copy. It
still writes `data/raw/<test>__mc.csv` carrying the seed, sample count, sampling mode
and limits, so the fragments regenerate after the run is rotated away.

`kind: "histogram"` takes `signals` (one, or two for a back-to-back sink/source pair),
`bins`, `spec_lo`/`spec_hi` with optional `spec_lo_label`/`spec_hi_label`, and
`spec_span`. A limit further than `spec_span` times the data width is annotated at the
axis edge instead of drawn, so a spec that is nowhere near the data cannot squash the
distribution into a single bar and hide the tail it exists to show.

`type: "mcstats"` is the matching table. `stats` picks the columns from `n`, `seed`,
`sampling`, `mean`, `sigma`, `min`, `max`, `median`, `p1`, `p99`, `mean_3s`, `spec`,
`yield`, `yield_chip`, `margin`, `cpk`, `worst`; `channels` sets the exponent for
`yield_chip`. Per-signal `spec_lo`/`spec_hi` override whatever was typed into Assembler,
which is what you want when the entered limit and the documented specification differ.

A signal can also carry `"derive": "a - b"`, naming two mcparam outputs to subtract
**per sample**. It publishes a quantity the run determines but did not measure — load
regulation with the zero-current error removed sample by sample, which is a different
distribution from the offset-inclusive error the test graded, not a shifted one. A
derived signal has no mcparam row, so its limits come from the config's
`spec_lo`/`spec_hi`; a sample is held out if either operand is a sentinel. It is one
subtraction and not an expression engine on purpose — anything richer belongs in the
Assembler outputs, where the corner run measures it too.

Three things this path gets right that a naive reader would not:

- **`-1.11111e+36` is a "could not evaluate" sentinel, not a number.** A `cross()` that
  never crossed writes it. It is held out of every statistic and surfaced in the `N`
  column as `197 / 200`, because "3 of 200 samples had no value" is itself a result.
  Averaged in, it turns a microamp mean into 1e34.
- **`worst` is only printed when a limit exists** — without one there is no telling
  which end of the distribution is the bad end.
- Tables of nine or more columns are set `\small`, eleven or more `\footnotesize`; a
  statistics row is much wider than a corner row and otherwise runs into the margin.

Do not quote `mean_3s` for a distribution that is not normal, and state the variation
type (mismatch-only vs process+mismatch) on every table — two runs with different model
sections produce σ values that are not comparable.

## Plot styling

Curves use slots 1–5 of the validated categorical palette in their documented order
(blue, orange, aqua, yellow, magenta), each with its own dash pattern so the figures
survive greyscale printing. Do not re-order or re-step the colours — the colourblind
-safety validation is against that specific order. Every figure is paired with a table
carrying the same numbers, which is what licenses the two lower-contrast slots.

Transients are decimated to `--max-points` (default 400) keeping the endpoints and the
global min/max, so overshoot is never decimated away.

## Gotchas found the hard way

- **The process corner is not a majority vote over `.modelFiles`.** Maestro always
  includes the PDK master `.scs` (all `tt_*` sections) and then overrides it with
  `cor_*.scs`; a naive vote answers `tt` for every corner. The corner is whatever
  `cor_std_mos.scs` selects. Getting this wrong also made every corner's CSV land on
  the same filename, so four of the five were silently overwritten.
- **`t` is a protected SKILL variable** — never use it as a loop variable in a
  generated `.ocn`.
- **`errset` returns a list**: read the value with `car(errset(...))`, not `cadr`.
- **`let` with no locals is `let(() ...)`**, not `let() ...`. Getting it wrong
  unbalances the parens, and an unbalanced `.ocn` leaves OCEAN waiting on stdin until
  it is killed rather than failing.
- **Maestro rotates its run directories away.** The CSVs under `data/raw/` outlive the
  run they came from, which is why they are committed; the corner list is cached beside
  them (`corners_<Block>.json`) at extract time so `--no-extract` still works once the
  run is gone.
- **`getData(... ?result "x")` leaves the selected result switched to `x`.** Signals are
  dumped in sorted order, so one expression reaching into a sibling analysis silently
  broke every *later* bare `getData` in the same test — `phaseMargin` and
  `phaseMarginFreq` came out `nil` while `gainMargin`, which sorts earlier, was fine. If
  any expression in a test names `?result`, give them all an explicit `?result`.
- **`legend pos` only accepts** `south west`, `south east`, `north west`,
  `north east`, `outer north east`. Anything else is a fatal pgfplots error, so the
  renderer validates it and falls back rather than emitting a broken document.
