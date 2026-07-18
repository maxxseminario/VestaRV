---
name: chip-top-flow
description: Build a CONNECTED pad-ring chip-top (M15 "Flavor B") — wiring a hardened core assembly into the tphn pad ring as one signed-off, gate-simulatable chip. Use when starting Castalia C0 (MCU_MP chip-top) or an Argus A6 re-cut of chip_top_argus. Encodes the FLAT-vs-macro decision rule, the script-diff checklist against the golden example, the pad LEF/netlist facts, and the pads-in-DUT gate-sim recipe.
---

# Connected pad-ring chip-top (M15 Flavor B)

Golden example, proven 2026-07-12 (Argus A5): `innovus/common/tcl/chip_top_argus.
innovus.tcl` + `in/chip_top_argus.{v,sdc}` + `xcelium/riscv_test/
innovus_chip_argus/`. Full narrative + status log: `.devlog/2026-07-12-argus-
a5-chip-top.md` — read it for the "why" behind any item below; if this skill
and the devlog disagree, the devlog wins.

**`diff tcl/MCU_ARGUS.innovus.tcl tcl/chip_top_argus.innovus.tcl` IS the
executable recipe.** This skill is a checklist for applying that same diff to
a new assembly script (MCU_MP.innovus.tcl for C0, or a re-harden of
MCU_ARGUS.innovus.tcl for A6) — read the golden files, don't copy them.

## 1. Decision rule: FLAT, not assembly-as-macro

`chip_top` = pad instances + the MCU instance, in ONE Innovus run over the
**untouched** assembly script; the MCU hierarchy places/routes directly
(tiles stay hardened LEF macros). Do not LEF/ETM the assembly into a macro
and route it inside chip-top P&R.

Why: for Argus, the M15 ring interior is exactly 2690×2690 = MCU_ARGUS's
DESIGN_WIDTH/HEIGHT — a macro would abut the ring with zero routing margin on
all four edges, and its ~708 pins all sit on one edge (bottom, analog side).
Macro-in-ring is only even worth considering when the assembly is ≪ the
interior (e.g. Castalia's 1400×2160) — but flat still wins there too: the
flow is already proven and the pad machinery (padlists, place procs, fillers,
seal keep-outs, supply hookup) is shared, basename-parameterized data/procs,
not per-chip code.

## 2. Script-diff checklist

Each item is one diff region; the trap it encodes is in parens.

- **Negative-origin die box**: `floorPlan -b $DIE_LLX $DIE_LLY $DIE_URX
  $DIE_URY ...` with the **core box unchanged** from the assembly script.
  Frame math: `FR_ORG = -(PAD_RING + SEAL_OFF)` (Argus: −155), so every
  assembly coordinate stays byte-identical and pad inner edges land exactly
  on the interior boundary (`PAD_NEAR = FR_ORG + SEAL_OFF`, `PAD_FAR =
  DESIGN_WIDTH`). Innovus 20.12 accepts a negative die origin.
- **Pad placement** via the M15 `place_pad`/`place_side` procs + a shared
  `chip_top_padlists.tcl` (ordered per-side instance lists) — source the same
  file for a new chip rather than forking it, unless the pinout differs.
- **IO fillers**: `addIoFiller` with an `addIoRow` fallback if it fails dry.
- **Seal keep-outs, created TWICE**: once at floorplan time, and **again
  after the DRC loop's `deleteAllRouteBlks`** (that call also strips the
  seal-band place/route blockages — re-run `seal_keepouts` right after it).
- **Supply hookup**: `sroute -nets {VSS VDD} -connect padPin ...` ties the
  core-domain supply pads to the fresh core ring. Acceptance check = the
  "sroute created N wires" log line **and** the PG-only connectivity gate (0
  infos with pad pins in the special realm) — a silent no-op here is exactly
  the PG2-F1 lesson (see `[[vestarv-pg4-signoff-closure]]`): don't trust the
  command not erroring, trust the count.
- **M7/M8 route blockages extended to the full DIE frame** (not just the
  core box) — keeps signal routing off power layers over the pad band too.
- **Every assembly instance reference gets the MCU instance prefix**
  (`mcu0/`) — placeInstance, addHaloToBlock, dbGet, createRegion, any
  gating-check disables. Grep the diff for the full site list (24 in the
  Argus case); missing one is a silent stale-reference bug, not an error.
- **Pad GDS added to `streamOut -merge`.**
- **`editPin` block DELETED.** Chip top-level ports ride the pads' PAD
  terminals; the assembly's ex-top-level ports become internal `mcu0/` nets.
  A leftover `editPin -pin [dbGet top.terms.name] ...` will silently no-op or
  misplace shapes for ports that no longer exist at this level — single-pin
  nets are tracer-silent, so this fails quiet, not loud.

## 3. SDC transform

Sed the assembly's genus SDC, don't hand-edit:
- `current_design chip_top`
- `get_pins X` → `get_pins mcu0/X`
- **Drop** the `set_load`/`set_driving_cell` `get_ports` lines — real pads
  are the loads/drivers now, not synthesis stand-ins.
- Append the a0 `set_dont_touch` pair (see §4).

## 4. a0 / tb-visibility buses: dangle, don't pad

Per the Myshkin tape-out precedent (`vesta_chip` CDL: `a<31:0>` lands on
internal nets that appear nowhere else) — **do not route tb-visibility buses
to pads.** Leave them OPEN on the MCU instance and `set_dont_touch` their
nets in the chip SDC addendum, so optDesign can't trim the driver cone. Gate
tb observability then comes from the tiles' own ports (`mcu0/hart<h>/a0` —
trim-proof by construction), not the MCU-level net.

## 5. LEF/netlist facts (corrections to older M15 notes — state as such if citing them)

- 8lm tphn `PVDD1DGZ_G`/`PVSS1DGZ_G` **already carry `USE POWER`/`USE
  GROUND`** — no USEfix LEF needed; the plain `globalNetConnect -type pgpin
  -inst *` binds them.
- `VDDPST`/`VSSPST`/`AVDD`/`AVSS`/`POC` have **no USE class** and must stay
  netlist-UNCONNECTED — wiring them in the netlist creates multi-pin signal
  nets the tracer reports as opens (filler-ring metal is OBS, not pins).
- `PDUW16SDGZ_G` = exactly `I`/`OEN`/`REN`/`PAD`/`C` (no `SD` pin), `bufif0`
  semantics, `OEN` active-low — wire `I←prt_out`, `OEN←prt_dir`, `REN←prt_ren`,
  `C→prt_in` per the taped-out Myshkin pad_ring.
- Use the **8lm** pad LEF variant, matching the M1–M8 tech LEF (9lm adds
  M9/VIA8 → unknown-layer spam on streamOut); tpfn is the wrong pad family
  entirely (no `_G` macros, no SD pad).

## 6. Pads-in-DUT gate-sim recipe

Template: `xcelium/riscv_test/innovus_chip_argus/`.

- **All-Verilog XMR wrapper** (`chip_top_sim.v`) — a VHDL tb cannot XMR into
  the DUT, so this wrapper sits between them and is Verilog-only end to end.
- Probe a0 at the **tiles' own ports** (`chip.mcu0.hart<h>.a0`) — trim-proof.
  Probe `prtN_dir` at the **pad OEN leaf pins**, not internal bus nets
  (internal buses may bit-blast; leaf instance ports don't).
- `PCORNER_G` has no Verilog model — needs a stub module (`pad_sim_stubs.v`).
- sdfcmd scopes both `:dut:chip` (top) and each `:dut:chip:mcu0:hart<h>`
  (tiles). Shbank deposits land at `:dut:chip:mcu0:...`.

## 7. Gate-driver traps (apply to every gate dir, not just this one)

- **`report severity failure` only PAUSES batch xmsim back to the tcl
  driver — it RESUMES.** The chunked driver must probe
  `:a0_reached_pass`/`:a0_reached_fail` after every chunk and early-exit.
  Without this, "clean" exits are a buffered-report-flush illusion and the
  trailing bare `run` never ends (cost A4's shboot a 6h+ run before a
  SIGTERM). `xrun.sh` in the golden dir has the working probe-and-break loop.
- `value -hex` is not a 20.09 xmsim option — plain `value` returns `256'h...`
  rows for shbank probes; compares still need quoted-literal matching
  (`[[vestarv-xmsim-tcl-value-quoting]]`).
- A `pgrep -f <dirname>` wait-guard matches its own cmdline and self-deadlocks
  — guard on `comm==xmsim` + `/proc` cwd instead.

## 8. Known residual classes (don't misread these as new regressions)

- `IMPESI-2221` "no driver PAD_*" — benign delay-calc noise (pads are
  timing-less by the `IMPVL-366` no-dummy-lib rule).
- `IMPFP-10009` ×4 — seal boxes outside the core, expected.
- `IMPLF-40` / `TECHLIB-1214` / `IMPFP-3961` — init noise (analog abstracts,
  tile ETMs, pad/corner sites).
- The B2-channel-mouth 0.1 µm short class + ~84 SameNet flags are the
  documented A4 erratum classes (PG-track re-harden scope), **not** chip-top
  regressions — don't re-roll the DRC-loop lottery chasing them here.

## Instantiating for a new chip (Castalia C0 / any future target)

Same padlists file, same golden-example diff, applied to `<TARGET>.
innovus.tcl` instead of `MCU_ARGUS.innovus.tcl`. Extra step: extend the
Makefile PG4 wrapper grep case-list to the new chip target (it's scoped by
design name today).

### RECTANGULAR-in-square assembly (proven by Castalia C0, 2026-07-14)

When the assembly is NOT square-and-interior-sized (Argus WAS: 2690² ==
interior, so its single `PAD_NEAR`/`PAD_FAR` + symmetric −155 die origin
worked), re-derive the frame PER EDGE. Castalia MCU_MP is 2689×1700 in the
2690² interior:

- **Center the assembly with an ASYMMETRIC negative die origin**, keeping the
  core box UNCHANGED (native coords byte-identical, so the assembly's power-
  closure ladder — ring-detour deletion, y-capped sroute, stripe ceiling — all
  stay valid). `IN = (−MARGIN_X, −MARGIN_Y)…(W+MARGIN_X, H+MARGIN_Y)` where
  `MARGIN = (INT_SPAN−DESIGN)/2`; `DIE = IN ± (SEAL_OFF+PAD_RING)`. For C0:
  die `(−155.5,−650)–(2844.5,2350)` = exactly 3000². `floorPlan -b` core box =
  `(1,1)-(W−1,H−1)` (identical to the assembly's `-s` core box).
- **`place_pad` gets per-edge `PAD_NEAR_X/FAR_X/NEAR_Y/FAR_Y`** and a per-axis
  interior-LL centering offset (`IN_LLX/IN_LLY + (INT_SPAN−block)/2`), not one
  pair. Corners at the per-axis near/far.
- **`addRing -follow io` then lands the core ring at the pad/interior boundary**,
  ~(interior−assembly)/2 OUT from the short edges (the log says it: "power
  planner will calculate offsets from I/O rows"). Upside: padPin supply hookup
  is trivial (pads abut the ring — C0 = 9 wires). Downside: the ring sits in the
  slack, so expect EXTRA cosmetic VDD/VSS floating-power-stub viols
  (IMPVFC-200) vs the assembly baseline — but 0 signal opens and the CORE grid
  over the logic stays byte-identical (preplace verifyGeometry matches the
  assembly EXACTLY; that's the tell it's sound). `-follow core` would hug the
  assembly (cleaner connectivity) at the cost of a long top-pad padPin hop —
  a real tradeoff, decide per target.

### verifyConnectivity: compare to the ASSEMBLY's baseline, not to 0

Argus's assembly signed off at 0, so its chip did too. Castalia's assembly
ships with ~577 VDD/VSS redundant-pin + floating-stub viols (IMPVFC-96/200,
the "tile U-ring is closed, top-leg pins are redundancy only" class). The chip
INHERITS that + adds ring/slack stubs. Categorize the report (grep the
IMPVFC-* summary + check for `Use: SIGNAL` opens) and diff vs the assembly's
own signoff rpt — accept the same-class delta, STOP on any NEW class (esp.
signal-net opens on resetn/prt = pad-to-core routing failure).

### SDC transform: prefix `get_nets` too (not just `get_pins`)

If the assembly has an NPU (Castalia does, Argus doesn't) the genus SDC carries
`set_dont_touch [get_nets …]` lines — prefix those with `mcu0/` as well
(`s/\[get_nets {npu0\//.../`), or they silently fail (TCLCMD-917) and the
dont_touch the assembly applies is dropped. Prefix `get_pins`+`get_nets`, drop
`get_ports`, leave `get_designs`/`get_lib_cells`/`[current_design]` bare.

### strmin guard: pin the internal MCU cell AND the pad family (C0)

`signoff_mp/strmin_gds.sh` is already extended (guarded `topcell≠MCU`): it pins
the internal `MCU` cell (a `chip_top` wrapper doesn't exempt it — mcu0 is still
`MCU`, name-hijackable like the PG4 `MCU_VIA*` phantom) AND the tphn pad family
`P*_G` (the `streamOut -merge` puts the pads in the GDS, but they also live in
`myshkin_tapeout` as the SAME shared IP → make them TRANSLATE for a self-
contained OA). After a clean run, XSTRM-287 must resolve from `myshkin_tapeout`
ONLY the 3 analog abstracts — never a raw strmin.

### Post-signoff extraction from a chip DB: fresh-init + defIn (A7, 2026-07-16)

`restoreDesign` of a chip signoff/final DB FATALs in tapeout mode over the 13
timing-less cells (tphn pads + 3 analog abstracts have no timing `.lib`s) —
this blocked both the A7-2 placements dump and the Stage-3 netlist regen. The
standing workaround is a FRESH Innovus session (never sets tapeout mode, runs
no timing-library check, writes no DB):

- **ERA / physical-only work** (rail analysis, placement dumps): `init_design`
  from the flow's input verilog + LEF/mmmc, then `defIn` the DB's
  `<cell>.def.gz` + `globalNetConnect` (`tcl/a7_era.tcl` pattern).
- **LVS netlist extraction**: SAME pattern but `init_verilog` MUST be the
  cut's own POST-ROUTE netlist (`out/<design>.xsim.v`) — the flow INPUT
  verilog lacks the chip-level opt/CTS instances in the DEF (attempt 1 died:
  4,510 IMPDF-138 dropped pins, 0 FE_OFN/CTS in the output). Then the A6
  `saveNetlist -excludeLeafCell -includePowerGround -phys -excludeCellInst
  FILL*` step. Template: `signoff_mp/a7/regen_lvs_netlist2.tcl`. Sanity gate:
  distinct FE_OFN/CTS_ counts must match the post-route netlist exactly.

### Re-P&R invalidates saved LVS netlists (named invariant, A7)

Any re-P&R invalidates every saved LVS netlist for that design — placement,
CTS, and optimization change the gate-level instances/nets even when the input
RTL is untouched (A7: FE_OFN 5,293→4,408, and the stale-netlist compare
ballooned unmatched 41k→1.04M with rc=0 and shorts EMPTY — a perfectly
plausible-looking bogus result). Regenerate LVS collateral from EACH cut's own
DB; never reuse a prior cut's `.lvs.v`.

### Hour-scale signoff runs: detach with setsid

The harness background-task reaper SIGTERMs its task group at 60 min — it
killed a 66-min chip Pegasus run mid-report-write (compare complete, reports
torn). Launch hour-scale pegasus/calibre runs detached (`setsid`, own session;
`signoff_mp/a7/run_lvs_rerun.sh` is the template) and gate every readback on
the runner's own rc file + report-mtime > run-start.

## Never

- Hand-edit the golden example files to test a new chip — copy the pattern
  into a new script named for the target.
- Route a0/tb-visibility buses to real pads.
- Trust an `sroute`/connectivity step without checking its logged count —
  see the PG2-F1 precedent in `[[vestarv-pg4-signoff-closure]]`.
- `restoreDesign` a tapeout-mode chip DB for extraction work — fresh-init +
  `defIn` instead (above); and never patch the DB's `.mode` to get past it.
