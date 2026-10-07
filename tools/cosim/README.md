# `tools/cosim/` — VestaRV ↔ Spike lockstep tooling

`compare.py` compares the RTL commit trace (`vesta_tracer.vhd`) against a Spike
`--log-commits` log, record by record; format in [`RECORD_FORMAT.md`](RECORD_FORMAT.md).
Options: `--help`; exit codes: `EXIT_*` at the top of `compare.py`. Run every script with
`/usr/bin/python3.6`, never `python3` (on this host it may be Calibre's quote-stripping wrapper).

```sh
tools/bin/bazel test //tools/cosim/...              # comparator self-tests (hermetic)
/usr/bin/python3.6 tools/cosim/test_compare.py      # same, plus xcelium/-dependent cases
```

## Bounded compare

A healthy test never terminates, so an unbounded compare exits 2. Bound it at the RTL window
and give Spike (`--pc=$EP`) a generous `--instructions`:

```sh
EP=$(riscv-none-elf-readelf -h "$ELF" | awk '/Entry point/{print $NF}')
N=$(/usr/bin/python3.6 tools/cosim/compare.py --rtl "$T" --spike "$L" --entry "$EP" --count --quiet)
/usr/bin/python3.6 tools/cosim/compare.py --rtl "$T" --spike "$L" --entry "$EP" --max-records "$N"
```

- Exit 0 = match. Exit 3 (Spike ended first) is never success: a trapping instruction ends
  Spike's log silently. Exit 5 = tooling error, no verdict.
- The runner must assert the trace header `# vesta_tracer TRACE_ENABLE=true …`; `compare.py`
  only warns when it is missing.
- Loads compare address only; `cycle` is never compared.

## Gate infrastructure (`gate/`)

`xcelium/` is gitignored; `gate/` is the tracked copy of the runners and lists that execute
there. `GATE_FILES` in `check_gate_files.py` is the mapping.

```sh
/usr/bin/python3.6 tools/cosim/check_gate_files.py            # rc 0 match, 1 drift, 2 missing
/usr/bin/python3.6 tools/cosim/check_gate_files.py --update   # live -> canonical; commit with the change
/usr/bin/python3.6 tools/cosim/check_gate_files.py --restore  # canonical -> live; --force to overwrite
```

Negative control (expects GOLD `exit=0`, PERTURBED `exit=1` at compared record #50154):

```sh
source ~/vestarv/cdspaths.sh && bash tools/cosim/gate/negctrl_RERUN.sh
```

Build map: [`BAZEL.md`](../../BAZEL.md).
