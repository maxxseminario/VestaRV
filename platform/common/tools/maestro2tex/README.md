# maestro2tex

Turns a Cadence Maestro run into TikZ/pgfplots figures and booktabs tables for the TRM.
Extraction runs OCEAN (Virtuoso licence) into `data/raw/*.csv`; rendering reads only the
CSVs. Testbench configs live in the gitignored
`private/analog/platform/common/tools/maestro2tex/configs/`; only `configs/guards.json` is
here. Output goes to `implementations/asic/castalia/analog/`, which the generator copies into
the TRM as `include/analog/`. Options: `python3 maestro2tex.py --help`.

```sh
python3 maestro2tex.py --results <run>/Interactive.<N> --config <configs>/<bench>.json \
    --outdir ../../../../implementations/asic/castalia/analog   # --no-extract: no licence
python3 check_fragments.py --configs <private configs dir>      # read-only drift check
```

The config schema is the worked examples in the private configs directory.

Caveats:

- Commit `data/raw/` (CSVs and `corners_<Block>.json`): Maestro rotates runs away.
- To replace a generated fragment by hand, list it in `superseded`, otherwise the next run
  overwrites it. `configs/guards.json` blocks withdrawn numbers from returning.
- Monte Carlo reads `mcdata`/`mcparam` without OCEAN. `-1.11111e+36` is a failed-evaluation
  sentinel and is held out of the statistics. State the variation type on every MC table.
- The process corner is whatever `cor_std_mos.scs` selects, not a vote over `.modelFiles`.
- If any expression in a test uses `getData(… ?result …)`, give every expression in that
  test an explicit `?result`.
- Heatmaps above ~5000 cells overflow TeX memory inside the full TRM.
- Adding content makes `make check-publish` report the TRM stale until `make publish`.
