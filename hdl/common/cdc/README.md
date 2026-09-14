# CDC: the two gates and the waiver list

Two gates cover clock-domain crossings, and they see different things.

| gate | where | what it proves |
|---|---|---|
| `//hdl/common/cdc:cdc_manifest_test` | hermetic, `tools/bin/bazel test //hdl/common/cdc:all` | every `entity work.sync` instance the RTL had is still there with the same generics and actuals, every instance is named `u_sync_<signal>`, and the waiver file below is a well-formed Tcl list of justified pairs. It reads text, so it cannot see a hand-rolled chain |
| the Genus CDC census | `genus/common/tcl/cdc_census.tcl`, every chip cut | structurally, that every register whose data cone reaches another clock domain lands on `stage_reg[0]` of a sync chain or on an itemised waiver |

Counts are frozen in `cdc_manifest.json`. A change that is intended is blessed in
the same commit as the RTL change:

    tools/bin/bazel run //hdl/common/cdc:cdc_manifest_update

## The gate is armed

`GENUS_CDC_STRICT` defaults to **1**. An unwaived crossing fails the flow gate
and no output is written.

**Armed 2026-09-14 (W11a)** on `genus/MCU_PENTA_pt/out/MCU_PENTA_pt_hier.genus.v`,
W2's promoted topology-B cut, netlist md5 `2355f2f3`. Census on that netlist:
1476 cross-domain data endpoints, 90 on sync `stage_reg[0]`, 1386 waived,
**0 NOT waived**. Topology A's promoted cut
(`genus/MCU_PENTA/out/MCU_PENTA_hier.genus.v`) carries the same endpoint set and
the same 0.

`GENUS_CDC_STRICT=0` disarms it for a debug run: the census still measures and
writes `rpt/<base>.cdc.rpt`, the log prints `CDC census NOT ARMED`, and the cut
is not promotable. The procedure and the gate lines are in `genus/RUNBOOK.md`
section 4.1.

## Adding a waiver to cdc_waivers.tcl

A waiver is `{<instance glob> "<justification>"}`, one per capturing register
group, and it is the last resort: the first answer to a crossing is
`entity work.sync` (`hdl/common/sync.vhd`).

- **Name the registers, never a block.** The lint refuses `*`, `*/*` and any
  glob ending in `/*`.
- **Escape brackets as `\[*\]`.** Tcl reads a bare `[*]` as a character class and
  matches nothing, so an unescaped waiver is a silently dead one.
- **The justification names the RTL or the constraint** that makes the crossing
  safe, with file and line. Under 24 characters is refused.
- **No comments inside the `return {...}` list.** The braced word is a LIST, so
  every whitespace-separated word of a `#` line becomes an element and its first
  word becomes a live waiver glob. That is how W5b waived the two endpoints its
  own sentence declared unwaivable. Commentary goes above the proc; the lint now
  fails any element that is not a brace-grouped pair.
- **Check the entry is not dead.** Each run prints
  `### UNL STATUS ### :   waiver '<glob>' matched N endpoint(s)`. A waiver at 0
  either names nothing or has stale brackets.

The per-entry evidence, failure scenarios and hit counts are in the W5a, W5b,
W10 and W11a reports under the tapeout review campaign record.
