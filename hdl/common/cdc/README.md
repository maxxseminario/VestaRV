# CDC gates and waivers

- `//hdl/common/cdc:cdc_manifest_test`: every `entity work.sync` instance keeps its
  generics and actuals and is named `u_sync_<signal>`; `cdc_waivers.tcl` is well formed.
  Text-based, blind to hand-rolled chains. Bless intended changes in the same commit:
  `tools/bin/bazel run //hdl/common/cdc:cdc_manifest_update`.
- Genus census (`genus/common/tcl/cdc_census.tcl`): every cross-domain register lands on
  a sync `stage_reg[0]` or a waiver. `GENUS_CDC_STRICT=1` (default) fails on an unwaived
  crossing; `=0` makes the cut unpromotable. See `genus/RUNBOOK.md` §4.1.

Waivers (`{<glob> "<justification>"}`) are a last resort after `hdl/common/sync.vhd`:

- Name registers, never a block (`*`, `*/*`, trailing `/*` are refused).
- Escape brackets as `\[*\]`; a bare `[*]` matches nothing.
- Justify with RTL or constraint file and line (≥ 24 characters).
- No comments inside `return {...}`: words of a `#` line become live waiver globs.
- A run line `waiver '<glob>' matched 0 endpoint(s)` means a dead waiver.
