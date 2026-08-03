# `tools/cosim/` — VestaRV ↔ Spike lockstep tooling

Phase **V2** deliverable (Agent A). Home per kickoff decision **D4**: this
directory is *tracked*; generated traces, Spike logs and runner scratch live
under `xcelium/` (gitignored).

| file | what |
|---|---|
| `RECORD_FORMAT.md` | **THE spec** — the frozen wire format, V0 deliverable, incl. Amendments A1–A5. Everything here implements it. |
| `compare.py` | the comparator. CLI + exit codes below are the contract with `xrun_cosim.sh`. |
| `spike_log.py` | Spike `--log-commits` parser (one commit line → 1×`R` + n×`M` + n×`C`). |
| `records.py` | the wire-format record object + the RTL-trace parser. |
| `disasm.py` | compact `rv32imac_zba_zbb_zbs_zbc` disassembler, used only to annotate context output. |
| `test_compare.py` | standalone self-tests. Every exit code exercised. |
| `check_gate_files.py` | **the gate-infrastructure drift checker** — see below. |
| `gate/` | **canonical, tracked copies of the gate infrastructure** — see below. |

---

## `gate/` + `check_gate_files.py` — the gate infrastructure is tracked HERE

**The problem, measured not assumed.** The two standing lockstep gates and the
136-test behavioural suite are driven by scripts and lists under `xcelium/`, and
`.gitignore`'s bare `xcelium/` rule (a deliberate 2026-07-18 decision) means git
tracks **none** of them. A `git clean -xdf` deletes the whole gate apparatus.
At W5 (2026-07-31) that cost was already being paid twice over:

* amendment **A10**'s correction to the boot x-wildcard substitution
  (`00004000:000000b0` → `…b1` — a value that had been silently overwriting a
  bit the RTL *does* drive, ever since V3) existed **only on disk**; and
* the V4 **missing-plant negative control** lived only in a session scratchpad
  outside the repo, still carried the pre-A10 value, and had therefore **stopped
  executing entirely** (`mk_inject … EXIT_REFUSED`, rc=5). A negative control
  that cannot run is not a control.

**The fix (user ruling, W5)** is the same canonical-copy-plus-verifier idiom the
project already uses for the generated `MCU.vhd` via
`platform/common/python/check_mcu_vhd.py`: `tools/cosim/gate/` holds the tracked
record, `xcelium/…` holds what actually runs, and the checker makes any
divergence loud. **`.gitignore` is deliberately untouched** — a plain negation
cannot work anyway, because git will not re-include a file whose parent
directory is excluded.

| canonical (tracked) | live (gitignored) |
|---|---|
| `gate/xrun_cosim.sh` | `xcelium/riscv_test/behavioral_mp/xrun_cosim.sh` |
| `gate/xrun_parallel.sh` | `xcelium/riscv_test/behavioral_mp/xrun_parallel.sh` |
| `gate/cosim_tests.txt` | `xcelium/riscv_test/behavioral_mp/cosim_tests.txt` |
| `gate/cosim_sh_tests.txt` | `xcelium/riscv_test/behavioral_mp/cosim_sh_tests.txt` |
| `gate/cosim_xallow.txt` | `xcelium/riscv_test/behavioral_mp/cosim_xallow.txt` |
| `gate/negctrl_RERUN.sh` | *(canonical only — run it in place)* |

```bash
/usr/bin/python3.6 tools/cosim/check_gate_files.py            # check   rc 0/1/2
/usr/bin/python3.6 tools/cosim/check_gate_files.py --update   # live -> canonical
/usr/bin/python3.6 tools/cosim/check_gate_files.py --restore  # canonical -> live
```

* `rc 0` match · `rc 1` **DRIFT** (unified diff printed) · `rc 2` a file is
  missing on one side.
* **`--update` is the only sanctioned way to move the record.** Run it when you
  change a gate deliberately, then commit `tools/cosim/gate/` **in the same
  commit** as the change that motivated it.
* **`--restore` is what a fresh clone or a post-`git clean` tree needs.** It
  **refuses** to overwrite a live file that differs unless `--force` is also
  given, so it cannot silently discard an uncommitted fix — precisely the
  accident the checker exists to catch.

Both polarities of the checker were proven at W5 before it was believed: a
one-line perturbation of a live list → `rc=1` with the diff; a deleted live file
→ `rc=2` with the recovery hint; `--restore` refusing a differing live copy;
and the tree byte-identical afterwards.

### Running the negative control

```bash
source ~/vestarv/cdspaths.sh
bash tools/cosim/gate/negctrl_RERUN.sh        # ~2 min; regenerates its trace if absent
```

Artifacts go to `$NEGCTRL_WORKDIR` (default
`xcelium/riscv_test/behavioral_mp/cosim_work/negctrl_plant/`), never beside the
tracked script and never over the sweep's own `cosim_work/traces` or
`cosim_work/inject`. Expected: **GOLD exit=0 plants=9281/9281**, **PERTURBED
exit=1 plants=9280/9280, divergence at compared record #50154**.

---

## Invocation — always `/usr/bin/python3.6`

```bash
/usr/bin/python3.6 tools/cosim/compare.py --rtl <trace> --spike <log> --entry <hexpc> \
                                          [--context N] [--max-records M] \
                                          [--hart HH] [--count] [--quiet]
```

**Never `python3`** (kickoff invariant 6): `python3` on this host may be
Calibre's `aoj_cal` wrapper, which re-evals its arguments and strips quotes.
Every script here carries a `#!/usr/bin/python3.6` shebang, and every
invocation in a runner must name the interpreter explicitly.

Stdlib only — no external dependencies, no network, no Xcelium, no Cadence env.

### Options

| option | meaning |
|---|---|
| `--rtl <trace>` | **required.** RTL commit trace written by `vesta_tracer.vhd` (`<TRACE_FILE>_h<xx>.trace`). |
| `--spike <log>` | **required.** Spike `--log-commits` log. |
| `--entry <hexpc>` | **required.** The entry PC both streams are aligned at (decision D3). `0x8200` or `8200`, any case. |
| `--context N` | records of context printed either side of a divergence, from **both** streams. Default **8**. |
| `--max-records M` | stop after M RTL records of the entry-aligned window have been **consumed** — compared, or dropped by a config-gated `--amend` rule — and report a match. `0` (default) = compare to the end of both streams. The reported figure is still the **compared** count, which is smaller by exactly the drops. (Before K2b the two were the same number; a walk-level amendment parted them, and bounding on window position is what keeps `--count`'s number reachable — see *The exit-2 question*.) |
| `--hart HH` | 2-hex-digit hart id to select from both streams. Required only if a stream carries more than one hart (per-hart streams are compared independently — `RECORD_FORMAT.md` §6). V2 is single-hart. |
| `--count` | informational: print the **size of the entry-aligned RTL window** to stdout and exit 0 **without comparing**. Feeds `--max-records`; see the runner recipe. It is a window size, **not** a prediction of the compared count: an `--amend` rule that consults the reference can only be resolved in the walk, and `--count` never walks. |
| `--quiet` | suppress the stderr summary. Divergence output and exit codes are unaffected. |

### Output streams

* **stdout** — the divergence / exhaustion / x-corruption report, and nothing
  else on a clean run (except the single number under `--count`).
* **stderr** — the always-on summary block (`--- compare.py summary ---`):
  stream sizes, records compared, pre-entry skips, the Amendment-A5 x-record
  census, the RTL `#` diagnostic-tag census, and the exit verdict. Plus
  warnings (see *Provenance header* below).

---

## Exit codes — the contract

| code | meaning | runner action |
|---:|---|---|
| **0** | **match.** Either both streams ended together, or the `--max-records` bound was reached with no divergence. | PASS |
| **1** | **divergence.** A compared field differs; **or** an RTL `T` record (trap entry) was reached — in V2 that is a control-flow divergence, because Spike's commit log carries no trap information at all (`RECORD_FORMAT.md` §4); **or** the entry PC is never reached on one side. | DIVERGE — triage per D5, log in `~/vesta_docs/lockstep/divergences.md` |
| **2** | **RTL stream exhausted early** — every record matched, then the RTL trace ended while Spike continued. | see *The exit-2 question* below |
| **3** | **Spike stream exhausted while the RTL continues.** **NEVER success.** A trapping instruction makes Spike print *no* line and then terminate with `rc=0` and no diagnostic (`RECORD_FORMAT.md` §4, `v0_report.md` §10.3), so a truncated log is the *normal shape* of an illegal-instruction or unmapped-access divergence. | DIVERGE / INVESTIGATE |
| **4** | **an Amendment-A5 x-corrupted record was reached** inside the compared window. A literal `x` nibble means the tracer sampled a non-0/1 `std_logic` rather than inventing a value. Never a match, never silently skipped. | INVESTIGATE |
| **5** | **parse or usage error** — a malformed record, an unrecognised Spike line shape, a missing/invalid option, an unreadable file, or a multi-hart stream with no `--hart`. | tooling bug / changed reference model — stop, do not report a verdict |

`argparse`'s own usage errors are remapped to **5** (its default is 2, which
would collide with `EXIT_RTL_SHORT`).

### The exit-2 question — read this before wiring the runner

A V2 test does not *terminate*: both sides spin forever in `RVTEST_PASS`'s
self-loop. The RTL trace stops because `riscv_tb` sees `a0 == 0xCAFEBABE` and
kills the sim; the Spike log stops because `--instructions=<n>` ran out. So the
default unbounded comparison of a *perfectly healthy* test yields **exit 2**,
not 0 — as measured on the real `rv32ui-p-add` artifacts (462 RTL records, 4000
Spike records).

`--entry` is the ELF entry point — the same value the Spike run must be given as
`--pc`, so that the RTL alignment target and the Spike log's first line are the
same PC by construction:

```bash
EP=$(riscv-none-elf-readelf -h "$ELF" | awk '/Entry point/{print $NF}')   # e.g. 0x8200
```

Two supported ways to get an unambiguous verdict:

1. **Bound the comparison at the end of the RTL window (recommended).**
   ```bash
   N=$(/usr/bin/python3.6 tools/cosim/compare.py --rtl "$T" --spike "$L" \
                                                 --entry "$EP" --count --quiet)
   /usr/bin/python3.6 tools/cosim/compare.py --rtl "$T" --spike "$L" \
                                             --entry "$EP" --max-records "$N"
   ```
   Then exit 0 means "every architectural state change the RTL committed in the
   window matched Spike", exit 3 means the RTL out-ran Spike (raise
   `--instructions`), and exit 2 cannot occur. Give Spike a generous
   `--instructions` so it is never the shorter stream.

   **"exit 2 cannot occur" is a claim about the BOUND being reachable, and it
   stopped being true for one wave.** `--count` reports the window SIZE; before
   K2b nothing could remove a record after that point, so the size and the
   compared count were the same number and the bound was trivially reachable. A
   config-gated `--amend` rule drops records *in the walk* — the drop consults
   the reference, which `--count` cannot — so the compared count fell below the
   window size and a bound expressed in compared pairs became unreachable.
   Measured on the K2b Zfinx row: **13 of 17 cells exited 2 with
   `compared == window − drops` to the record**, and the only four that passed
   were the four with zero drops. Not one had a divergence. `--max-records`
   therefore bounds **window position**, not compared pairs, and the claim above
   holds again — with amendments and without. If you add a mechanism that can
   remove an RTL record after `--count` has run, re-read this paragraph first.
2. **Accept exit 2 and correlate with the testbench verdict.** Exit 2 + `TEST
   PASSED` is benign; exit 2 + a `riscv_tb` FAIL/watchdog means the RTL died or
   hung early, which is exactly the failure exit 2 exists to surface. This is
   strictly weaker than (1) and should not be the primary gate.

### Provenance header — the runner must assert it

The tracer's first output line is
`# vesta_tracer TRACE_ENABLE=true vesta_trace hart=00` (`v1_report.md` §5). A
warning-free elaboration is **not** proof the `-generic` override took: an OFF
snapshot emits **no trace file at all**, and a stale one emits a header-less or
old file. `compare.py` **warns** on stderr when the header is absent but does
not fail — asserting it is the runner's job, before it trusts a trace.

---

## What is compared

Exactly `RECORD_FORMAT.md` §8, no more:

| record | compared | not compared |
|---|---|---|
| `R` | `pc` `insn` `rd` `rdval` | `cycle` |
| `M L` | `addr` | `cycle` `size` `data` — Spike emits a load's **address only** (§2); the load's architectural effect is still checked through the same retire's `R.rdval` |
| `M S` | `addr` `size` `data` | `cycle` |
| `C` | `csr` `val` | `cycle` |
| `T` | *(nothing to compare — reaching one exits 1)* | all |
| `X` | *(nothing — dropped from the compared stream)* | all |

`hart` selects the stream rather than being compared inside one. `cycle` is
never compared on any record: on the RTL side it is the tracer's free-running
count, on the Spike side the 0-based retire ordinal (§0).

### Normalisations applied

* **Entry alignment (D3)** — RTL records are skipped until the first `R` whose
  `pc` equals `--entry`. The Spike side is aligned the same way; with the frozen
  recipe (`--disable-dtb --pc=<entry>`) it needs no skip, and a non-zero skip is
  reported on stderr (a DTB-on log carries a 5-instruction prologue at 0x1000 —
  §7).
* **Amendment A2** — a maximal run of *consecutive* `R` records with identical
  `pc` is sorted on `rd` on **both** sides before comparison. This is what makes
  a multi-`rd` retire (Zcmp `cm.pop*`/`cm.mv*`, knobs-on only) comparable
  against Spike's single line. A run of length 1 — every retire in the default
  Castalia config — is untouched, and a one-instruction self-loop is unaffected
  because every member of that run carries the same `rd`.
* **Amendment A1** — `#` lines are never compared, but the diagnostic tags
  (`CSRLEAK`, `SCFAILRD`, `TRAPSTORE`, `ADDRMISMATCH`, `LANEMISMATCH`, `INIT`,
  `IRETPHANTOM`, `SLEEPEXIT`, plus any tag added later) are **counted and
  summarised on stderr at exit**. They are findings-surface (F2/F3/F7/F8/F9/R5/
  R6) and are never silently dropped.
* **Amendment A5** — `x` policy: an x-tainted record inside the compared window
  exits **4**. Records skipped during entry alignment are *not* fatal — the
  known-benign instances (X reads of undriven MMIO during the bootrom: GPIO0
  pads @0x4000, empty SPI0 RX @0x420c) live outside the D3 window, and treating
  them as fatal would make every sweep exit 4. They are **counted and reported**
  in the stderr summary instead (`x-tainted records N total (P pre-entry, Q in
  the compared window)`), so nothing is silently skipped. **A pre-entry count
  other than the known 2 is worth a look.**
* **Spike-side explosion** — one commit line becomes `1×R` (or `n×R` for a
  multi-`rd` retire) + every `M L` + every `M S` + every `C`, in that order
  (§0). Fields are classified **by prefix, never by position**: the write map is
  keyed `(number << 4) | type`, so `c1_fflags` (key 20) prints *before* `x20`
  (key 320). Tokenisation is on whitespace **runs** — Spike pads single-digit
  register numbers with two spaces.

### Deliberately strict

`compare.py` exits **5** rather than skipping anything it does not understand:
a malformed RTL field width, an uppercase hex digit, an unknown record kind, an
unrecognised Spike trailing field, a non-commit line in the Spike log, or an
`x0` write in the Spike log (which would break the invariant that `rd=00` means
"no register write" — §1). Silently dropping any of these would let a broken
tracer or a changed reference model masquerade as a match.

---

## Self-tests

```bash
/usr/bin/python3.6 tools/cosim/test_compare.py
```

58 cases, every exit code (0,1,2,3,4,5) exercised, exits 0 on success. No
Xcelium, no Spike run, no network required.

Fixture provenance is documented at the top of the file: the clean-match
fixture is the **real** V1 tracer output (`rv32ui-p-add`, hart 0, entry-aligned)
against a **real** Spike log from the frozen v0 recipe; shapes the `add` window
lacks (loads, stores, CSR writes, AMOs, multi-`rd` retires, traps) are
hand-written from the verbatim Spike lines in `RECORD_FORMAT.md` §2/§3, each
with a mutation-based negative control so no "exit 0" is vacuous.

Setting `COSIM_REAL_SPIKE_LOG=<a Spike log for rv32ui-p-add at 0x8200>` adds two
whole-window cases against `xcelium/riscv_test/behavioral_mp/vesta_trace_h00.trace`
(462 compared records, bounded → exit 0 and unbounded → exit 2). They are
skipped with a `SKIP` line when the artifacts are absent.

---

## Known limitations (V2 scope)

* **`T` has no Spike counterpart.** Reaching one exits 1 by design; giving it a
  comparable Spike side is V3 work.
* **`M L` `size`/`data` are unchecked** — a real coverage limit of the reference
  model, not a comparator shortcut. The RTL's returned `rdata` is precisely the
  quantity V3's MMIO injection must *tell* Spike.
* **FPR (`f<n>`) write fields are ignored** — the frozen format has no `F`
  record, and Zfinx is off in the V2 config (Zfinx writes GPRs anyway). They are
  counted and reported on stderr, never silently dropped.
* **The disassembler is presentation-only.** It covers
  `rv32imac_zba_zbb_zbs_zbc` plus the three VestaRV custom encodings on opcode
  `0x0b`; anything else renders as `unknown …`. It never participates in a
  comparison decision. Cross-checked against
  `riscv-none-elf-objdump -d` over 2824 instructions from 10 ELFs: every
  residual difference is an objdump pseudo-instruction alias (`add` for `addi`,
  `sw` for `c.swsp`, `li`/`mv`/`j`/`ret`, `unimp`) or a `.word` data slot that
  objdump declines to decode and this decoder does (correctly — e.g. the Zba
  `sh1add` that objdump's default `-march` rejects).
* **Interrupts, MMIO and multi-hart are out of scope** (V3/V4). The V2 test set
  is `~/vesta_docs/lockstep/v2_test_set.md` — 104 ELIGIBLE, 1 TRIAGE-EXPECTED.
