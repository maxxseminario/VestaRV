---
name: post-genus-debug
description: Debug MCU_MP gate-level (post-genus, SDF-annotated) simulation failures in xcelium/riscv_test/genus_mp — triage dead-vs-live chips, X-cascade root-causing with the first-X VCD toolkit, preload/deposit mechanics, and the license/flow gotchas. Use when a gate sim fails, hangs, or mass-fails after a resynth.
---

# Post-genus gate-sim debugging (MCU_MP)

You are debugging the SYNTHESIZED netlist (`genus/out/`), SDF-annotated, in
`~/vestarv/xcelium/riscv_test/genus_mp/`. `source ~/vestarv/cdspaths.sh` first.

## Ownership contract (two-agent workflow)

Treat `hdl/` as **READ-ONLY**. Your deliverable is a ROOT CAUSE (signal, mechanism,
first-X time, proposed fix direction) written to a findings note for the RTL-owning
agent/user — RTL fixes land via the other session, and `hdl/common/MCU.vhd` only ever
changes through `platform/common` `make chip` (template + `check_mcu_vhd.py`). You MAY
edit the gate-flow files (genus_mp scripts, probe tcl, genus tcl) — mark temp edits
`TEMP ... REVERT`.

## Timing rules (INVERTED vs behavioral)

- A DEAD chip races to the tb's 100 ms watchdog in **13–15 s wall** (nothing toggles).
- A LIVE pure-ISA gate test is **~4 min wall** (6.43 ms sim); sh-protocol tests longer.
- So: fast timeout = dead chip (X-collapse or reset pathology); slow = actually running.
- Behavioral 1-minute rule does NOT apply here. Sim-time frozen + 100% CPU = comb loop.

## Flow facts (each cost a session — do not re-derive)

- Runners: `./xrun_batch.sh <full-x-padded-basename>` (single), `TESTS_FILE=rv32ui.txt|
  rv32_mp.txt MAX_PARALLEL=6 ./xrun_parallel.sh` (sets). Pass gate: hart0 a0=0xCAFEBABE,
  harts 1-3 via a0_1/2/3; watchdog 100 ms (`riscv_tb_gate.vhd:490`).
- **`-nonotifier` must be on BOTH xrun.sh and xrun_parallel.sh xmelab calls** (reset-time
  $hold(SN/R) notifier-X kills the chip; the flag does not propagate between scripts).
- Preloads: xrun.sh generates `log/preload.tcl` (scope `:dut`), parallel runner per-image
  `log/preload_<img>.tcl` (scope `:uut:dut`), both via `make_ram_deposit.py` — which ALSO
  deposits 32'h0 into all 256 `\shram[w]` nets (escaped-name syntax `{:uut:dut:\shram[85] }`,
  trailing space required). The netlist shram has NO reset; sh-protocol tests read
  unwritten words — without the zero-deposits they X-collapse (M9b round 3).
  Deposits land at t=1 ns and t=300 ns. Per-image tests (*-shboot|...|*-shexec globs in
  both runners) preload tile RAMs from `ram_images/<base>.ram{0,1}.rcf`.
- Reset offset: chip-internal resetn releases ~44 ns after the tb pin (POR + sync) —
  tb 40 ns → internal ~83.9 ns when reading waves.
- MTM MAXIMUM sdfcmd; ~35.7% tcheck annotation is expected noise.
- LICENSES: never run genus and the 6-way parallel regression simultaneously (xmelab
  starves → mass NOSNAP). Never two xruns in genus_mp at once (xcelium.d clobber).
  Parallel-flow cds.lib contaminates later single xruns (MULVLG multiple-binding) —
  `rm -rf cds.lib xcelium.d` before a manual xrun there. Never pipe runners through
  head/tail. xrun.log is overwritten per run — save evidence before relaunching.
- **innovus/common (post-P&R) runs: MAX_PARALLEL ≤ 2.** At 5-wide, xmsims got externally
  SIGKILLed mid-sim (PG1 fix session 2026-07-10): logs truncate at "xcelium> run" or
  mid-timing-warnings with NO tb verdict — mimics a mass gate failure. Check the
  RUNNER STDOUT for "NNNNN Killed" lines before diagnosing the netlist.

## X-cascade root-causing (fastest path, proven M9b)

1. Reproduce with a bracketing probe: chunked tcl (`run 5us` + `puts`/`flush` per chunk)
   sampling tile PCs + a0s (`log/diag25.tcl`/`diag28.tcl` patterns) to bound the death
   window. xmsim tcl `value` returns bit-strings WITH quote chars — compare against
   quoted literals (`shspin_diag2.tcl` is the trigger-trace template). Do NOT probe
   integer/natural/enum signals into SHM (SST2ER flood).
2. Root SHM probe over the window: `probe -create : -all -depth all -shm`, then
   `simvisdbutil <shm> -vcd`, then first-X-per-signal sorted by fs (SDF spreads events
   into causal order). Session scripts to rewrite if scratchpad is gone (recipes in
   `multicore_plan.md` M9b entries): first_x.py, x_timeline.py, sig_trace.py.
3. `drivers <net>` in xmsim walks an X back one gate at a time.
4. Ignore the two benign pad-input X's (prt1_in[2]/[3]) at the bootrom's boot-end P1DIR
   flip — present in PASSING tests too.

## Solved pathologies (recognize, don't re-solve)

- **Boundary-opto floaters**: genus 19.15 silently ignores root `set_db boundary_opto
  false`; the working form is `set_db [get_db modules] .boundary_opto false` AFTER
  `elaborate` (in MCU_MP.genus.tcl; proof line "boundary_opto disabled on 592 modules").
  UNCONNECTED count is the metric: ~166 good, ~3900 bad.
- **Unreset adddec staging** corrupted RAM macro models at the first mclk edge →
  fixed by staging resets-to-INACTIVE. `-xminitialize 0` died identically — blanket
  resets are DISPROVEN; don't resurrect.
- **Fetch-priming contract**: core_rst_stretch releases the core 2 free-running-mclk
  edges late + nop-force on core_read_data + `and resetn_core` on sh_req/arb_req(0).
  These interlock — never remove one alone.
- **Wake-from-extinguish red herring** (M9b): "all tile PCs frozen at the extinguish
  park" looked like a CLINT/ISR failure but was uninitialized shram. Check the WHOLE
  chip for X-collapse (including hart0's a0) before believing a protocol-level story.

## After any RTL change lands

Re-run at least: `simple` + `shexec` (execute-from-shared) + one per-image sh-protocol
test (e.g. shwfi) at gate level. Full MP set = `TESTS_FILE=rv32_mp.txt`.
