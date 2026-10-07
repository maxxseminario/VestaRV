# CDC gates and waivers

Two gates cover clock-domain crossings; they see different things.

| Gate | Run | Checks |
|---|---|---|
| `//hdl/common/cdc:cdc_manifest_test` | `tools/bin/bazel test //hdl/common/cdc:all` | Every `entity work.sync` instance keeps its generics and actuals, is named `u_sync_<signal>`, and `cdc_waivers.tcl` is a well-formed list of justified pairs. Text-based: blind to hand-rolled chains |
| Genus CDC census | `genus/common/tcl/cdc_census.tcl`, every chip cut | Every register whose data cone reaches another clock domain lands on `stage_reg[0]` of a sync chain or on a waiver |

Counts are frozen in `cdc_manifest.json`. Bless an intended change in the same commit
as the RTL change:

    tools/bin/bazel run //hdl/common/cdc:cdc_manifest_update

`GENUS_CDC_STRICT` defaults to 1: an unwaived crossing fails the flow and writes no
output. `GENUS_CDC_STRICT=0` disarms it for debug: the census still writes
`rpt/<base>.cdc.rpt`, the log prints `CDC census NOT ARMED`, and the cut is not
promotable. Procedure: `genus/RUNBOOK.md` §4.1.

## Waiver rules (`cdc_waivers.tcl`)

A waiver is `{<instance glob> "<justification>"}`, one per capturing register group,
and a last resort after `entity work.sync` (`hdl/common/sync.vhd`).

- Name registers, never a block: `*`, `*/*` and globs ending in `/*` are refused.
- Escape brackets as `\[*\]`; a bare `[*]` is a Tcl character class and matches nothing.
- The justification cites the RTL or constraint, with file and line; under 24
  characters is refused.
- No comments inside the `return {...}` list: each word of a `#` line becomes a list
  element, and the first becomes a live waiver glob. Comments go above the proc.
- Check each run's `waiver '<glob>' matched N endpoint(s)` line; N = 0 means a dead
  waiver.
