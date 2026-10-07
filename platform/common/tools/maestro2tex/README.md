# maestro2tex

Turns a Cadence Maestro (ADE Assembler) run into TikZ/pgfplots figures and booktabs tables
for the TRM, so published characterisation is regenerated from simulation, never
transcribed. Testbench configs live in the gitignored
`private/analog/platform/common/tools/maestro2tex/configs/`; only `configs/guards.json` is
here. Output goes to `implementations/asic/castalia/analog/`, which the generator copies into
the TRM as `include/analog/`.

```sh
python3 maestro2tex.py \
    --results <cell>/maestro/results/maestro/Interactive.<N> \
    --config  <configs>/<bench>.json \
    --outdir  ../../../../implementations/asic/castalia/analog
python3 maestro2tex.py --help        # all options
```

Two stages: **extract** runs `ocean -nograph` (Virtuoso licence; reads PSF and PSFXL) into
`data/raw/*.csv`; **render** is stdlib Python reading only the CSVs. `--no-extract`
re-renders without OCEAN or a licence.

| Output in `<outdir>/` | Content |
|---|---|
| `<Block>.tex` | Master fragment the TRM inputs |
| `fig_<id>.tex`, `tab_<id>.tex` | One figure / table each |
| `preview_<Block>.tex` | Standalone proof sheet |
| `data/*.dat`, `data/raw/` | Plot data; raw CSVs and `corners_<Block>.json` (commit these: Maestro rotates runs away) |
| `data/extract_<Block>.ocn/.log` | Extraction script and OCEAN log |

A config declares `signals` (any OCEAN expression, waveform or scalar), logical `tests`
(several may share one Maestro test via `dir`), `figures` (plain, `heatmap`, `sweepline`,
`histogram`), `tables` (`matrix`, `bycorner`, `stats`, `mcstats`) and the fragment `order`.
The private configs are the worked examples. Every figure and table needs an `id`.

## Checking the chapter

```sh
python3 check_fragments.py --configs <private configs dir> [--outdir DIR] [--quiet]
```

Read-only; exit 1 on error. Flags `order` vs master drift, live superseded fragments,
missing or unreferenced fragments, and any value listed in `configs/guards.json`. The
default `--configs` is this directory, which holds only `guards.json`.

## Caveats

- To replace a generated fragment by hand, keep its name and `\label` and list it in
  `superseded`; otherwise the next run overwrites it.
- Monte Carlo (`"monte_carlo": true`) reads `psf/<test>/monteCarlo/mcdata`/`mcparam`
  without OCEAN. `-1.11111e+36` is a failed-evaluation sentinel, held out of statistics and
  reported in `N`. State the variation type on every MC table; do not quote `mean_3s` for a
  non-normal distribution.
- The process corner is whatever `cor_std_mos.scs` selects, not a vote over `.modelFiles`.
- If any expression in a test uses `getData(… ?result …)`, give every expression in that
  test an explicit `?result`.
- Heatmaps above ~5000 cells overflow TeX memory inside the full TRM.
- In generated `.ocn`, `t` is protected and an unbalanced paren hangs OCEAN on stdin.
- Adding content makes `make check-publish` report the TRM stale until `make publish`.
