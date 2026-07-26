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

The generated `extract.ocn` and the full OCEAN log are left in `<outdir>/data/` so a
failed extraction is debuggable.

## Output layout

```
<outdir>/
  <Block>.tex             master — the one file the TRM inputs
  fig_*.tex               one pgfplots figure each
  tab_*.tex               one booktabs table each
  preview.tex/.pdf        standalone proof sheet (pdflatex preview.tex)
  data/*.dat              plot data, one file per curve
  data/raw/*.csv          raw OCEAN dumps (input to the render stage)
  data/extract.ocn/.log   what was run, and what it said
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
exactly what `preview.tex` does (it sets it empty and compiles from inside `outdir`).

Required packages — `pgfplots`, `booktabs`, `siunitx`, `xcolor` — are all already in
the TRM's `packages-commands.tex`. The figures set `compat=1.18` inside a TeX group so
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
| `tests` | per test: `result` (`dc`/`tran`/`dcOp`), `xlabel`, `xunit_tex`, `xscale`, `nominal_x`, and `signals` overrides |
| `figures` | `test`, `signals`, `corners` (list or `"all"`), `caption`, `legendpos`, `yprec` |
| `tables` | `type` `matrix` (signals × corners) or `stats` (signals × statistics) |
| `order` | explicit order of fragments in the master file |

`signals` is per-test overridable because the same quantity is often a different node
in a different testbench — in the bias generator the supply current is
`i("/POWER/SRC_VDD25/PLUS")` in the DC benches but `i("/V0/PLUS")` in the startup
bench.

Available statistics: `value`, `nominal` (interpolated at `nominal_x`), `min`, `max`,
`mean`, `spread`, `first`, `last`, `settle` (last exit from a ±1 % band around the
final value), `sens_pct_per_x` (%/unit) and `ppm_per_x` (ppm/unit).

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
- **`legend pos` only accepts** `south west`, `south east`, `north west`,
  `north east`, `outer north east`. Anything else is a fatal pgfplots error, so the
  renderer validates it and falls back rather than emitting a broken document.
