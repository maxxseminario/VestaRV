---
name: chip-top-flow
description: Build a CONNECTED pad-ring chip-top (M15 "Flavor B") — wiring a hardened core assembly into the tphn pad ring as one signed-off, gate-simulatable chip. Use when starting Castalia C0 (MCU_MP chip-top) or an Argus A6 re-cut of chip_top_argus. Encodes the FLAT-vs-macro decision rule, the script-diff checklist against the golden example, the pad LEF/netlist facts, and the pads-in-DUT gate-sim recipe.
---

# Connected pad-ring chip-top (M15 Flavor B)

Golden example, proven 2026-07-12 (Argus A5): `innovus_mp/tcl/chip_top_argus.
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
design name today). If the new assembly's core box is ≪ the ring interior
(true for Castalia), it can keep its own `floorPlan -s` core box — only the
die box and pad frame change; re-derive `PAD_NEAR`/`PAD_FAR` relative to
**that** assembly's DESIGN_WIDTH/HEIGHT, not Argus's 2690.

## Never

- Hand-edit the golden example files to test a new chip — copy the pattern
  into a new script named for the target.
- Route a0/tb-visibility buses to real pads.
- Trust an `sroute`/connectivity step without checking its logged count —
  see the PG2-F1 precedent in `[[vestarv-pg4-signoff-closure]]`.
