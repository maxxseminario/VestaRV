# `tools/cosim/` — VestaRV ↔ Spike lockstep tooling

Compares the RTL commit trace (`vesta_tracer.vhd`) against a Spike `--log-commits` log,
record by record. The wire format is specified in [`RECORD_FORMAT.md`](RECORD_FORMAT.md);
generated traces, logs and runner scratch live under the gitignored `xcelium/`. Run every
script with `/usr/bin/python3.6`, never `python3` (on this host it may be Calibre's wrapper,
which strips quotes). Stdlib only.

| File | Role |
|---|---|
| `compare.py` | Comparator; CLI and exit codes are the contract with `gate/xrun_cosim.sh` |
| `records.py`, `spike_log.py` | Record object + RTL-trace parser; Spike log parser |
| `amend.py`, `oracle_isa.py` | Config-gated comparator amendments and their derivation from the resolved config |
| `disasm.py` | Disassembler for context output only; never affects a verdict |
| `test_compare.py` | Self-tests; every exit code exercised |
| `check_gate_files.py`, `gate/` | Tracked copies of the gitignored gate infrastructure + drift checker |

Self-tests: `/usr/bin/python3.6 tools/cosim/test_compare.py`. Setting
`COSIM_REAL_SPIKE_LOG=<Spike log for rv32ui-p-add at 0x8200>` adds whole-window cases against
`xcelium/riscv_test/behavioral_mp/vesta_trace_h00.trace`; skipped when absent.

## Bazel (comparator tests only)

```sh
sh tools/get_bazel.sh
tools/bin/bazel test //tools/cosim/...
```

| Target | Proves |
|---|---|
| `//tools/cosim:compare` | Comparator as a tool (`bazel run //tools/cosim:compare -- --rtl … --spike … --entry …`) |
| `//tools/cosim:test_compare` | Self-tests; cases needing `xcelium/` artifacts or `vesta_ref` self-skip |
| `//tools/cosim:test_oracle_isa` | Amendment derivation against the RTL constants in `hdl/common/` |
| `//tools/cosim:check_dbg_trampoline_test` | Trampoline table in `hdl/common/debug_module.vhd` matches `//software/dbg_trampoline:dbg_trampoline_words` |
| `//tools/cosim:check_knob_classes_test` | Knob classification matches what tests dispatch on |

The Xcelium lockstep gates and `check_gate_files.py` stay outside Bazel (licensed tools;
gitignored inputs). Build map: [`BAZEL.md`](../../BAZEL.md).

## Gate infrastructure (`gate/`)

`.gitignore` excludes `xcelium/`, so `gate/` is the tracked record of the runners and test
lists that execute there (mainly `xcelium/riscv_test/behavioral_mp/`). `GATE_FILES` in
`check_gate_files.py` is the authoritative mapping; some entries are canonical-only.

```sh
/usr/bin/python3.6 tools/cosim/check_gate_files.py            # rc 0 match, 1 drift (diff), 2 missing
/usr/bin/python3.6 tools/cosim/check_gate_files.py --update   # live -> canonical
/usr/bin/python3.6 tools/cosim/check_gate_files.py --restore  # canonical -> live (fresh clone)
```

- `--update` is the only way to move the record; commit `gate/` with the change that motivated it.
- `--restore` refuses to overwrite a differing live file unless `--force` is given.

Negative control (~2 min; artifacts in `$NEGCTRL_WORKDIR`, default
`xcelium/riscv_test/behavioral_mp/cosim_work/negctrl_plant/`):

```sh
source ~/vestarv/cdspaths.sh
bash tools/cosim/gate/negctrl_RERUN.sh
```

Expected: GOLD `exit=0 plants=9281/9281`; PERTURBED `exit=1`, divergence at compared record #50154.

## `compare.py`

```sh
/usr/bin/python3.6 tools/cosim/compare.py --rtl <trace> --spike <log> --entry <hexpc> \
    [--context N] [--max-records M] [--hart HH] [--count] [--amend NAME] [--quiet]
```

| Option | Meaning |
|---|---|
| `--entry` | ELF entry PC; both streams align at the first `R` with this PC. Give Spike the same value as `--pc`. |
| `--count` | Print the entry-aligned RTL window size and exit 0 without comparing |
| `--max-records M` | Stop after M window records consumed (compared or amend-dropped); 0 = to the end |
| `--hart HH` | Required when a stream carries more than one hart |
| `--amend` | `zfinx-fflags`, `cboz-stores`, `cmjt-load`; derived from the config, none for the default. Unknown name → exit 5; zero applications reported as VACUOUS |
| `--context N` | Records shown either side of a divergence (default 8) |

Further options: `--help`. stdout carries only the verdict report; stderr carries the summary
(stream sizes, x-record census, `#` diagnostic-tag census).

| Exit | Meaning |
|---:|---|
| 0 | Match (both streams ended, or `--max-records` reached) |
| 1 | Divergence, an RTL `T` (trap) record reached, or entry PC never reached |
| 2 | RTL ended early with all records matching |
| 3 | Spike ended while RTL continues — never success; a trapping instruction ends Spike's log silently |
| 4 | x-corrupted record inside the compared window |
| 5 | Parse/usage error, unknown record shape, multi-hart stream without `--hart` — no verdict |

A healthy test never terminates (both sides spin in `RVTEST_PASS`), so an unbounded compare
returns 2. Bound it at the RTL window, and give Spike a generous `--instructions`:

```sh
EP=$(riscv-none-elf-readelf -h "$ELF" | awk '/Entry point/{print $NF}')
N=$(/usr/bin/python3.6 tools/cosim/compare.py --rtl "$T" --spike "$L" --entry "$EP" --count --quiet)
/usr/bin/python3.6 tools/cosim/compare.py --rtl "$T" --spike "$L" --entry "$EP" --max-records "$N"
```

- The runner must assert the trace header `# vesta_tracer TRACE_ENABLE=true …`; `compare.py`
  only warns when it is missing, and a stale or OFF build yields no or old traces.
- Compared fields follow `RECORD_FORMAT.md` §8. `cycle` is never compared; loads compare
  address only (Spike logs no load data); FPR writes are counted, not compared.
- x-tainted records before entry are counted, not fatal; a pre-entry count other than 2 needs a look.
- Anything unrecognised exits 5 rather than being skipped.
