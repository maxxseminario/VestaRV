# VENDORED — riscv-tests `debug/` suite

This directory is a **vendored copy of somebody else's code**, plus a small,
enumerated set of VestaRV-local deltas. It is not upstream and it is not
ours; read this file before changing anything in it.

* **Upstream project:** <https://github.com/riscv-software-src/riscv-tests>
  (historically `https://github.com/riscv/riscv-tests`)
* **Upstream subdirectory:** `debug/`
* **Vendored into this repo:** commit `7aeeb7d` ("Restructure repository for
  GitHub publication"), **2026-04-19**. That is the *only* commit that has
  ever touched these files before the D5 relocation.
* **Relocated into `tools/debug/riscv-tests-debug/`:** D5, 2026-08-10
  (R-DD6(3)) — a pure `git mv` of 64 files, no content change in that commit.
  The suite had been unpacked **flat** into `tools/debug/`, interleaved with
  the Myshkin bench tooling it must never clobber.

## Provenance: the honest version

**No upstream commit hash was recorded when this suite was vendored, and one
cannot be recovered from the tree.** There is no `.git`, no submodule, no
subtree marker, no SPDX or copyright header, and no version file. Saying
otherwise would be a fabricated pin, so this file does not offer one.

What *does* exist, and what each thing is worth:

* `hifive1_excludes.yaml` carries a comment block naming
  `riscv-openocd a45589d6…` / `riscv-tests 7b52ba3b…` and "Tested on
  Jun-26-2023". **This is NOT the vendoring pin.** It is a site-specific
  exclusion list for somebody else's HiFive1 board that travelled with the
  upstream file. It bounds the vintage from below (the copy is no older than
  those commits) and nothing more.
* All 64 files carry the bulk checkout mtime `2026-04-19 13:48`, and the repo
  commit above is dated the same day — consistent with one unpack, one add,
  no subsequent upstream sync.
* The suite has never been run in this checkout before D5: no `logs/`
  directory was ever created.

**If this suite is ever re-synced, record the upstream commit in this file at
that moment.** The gap above is the cost of not having done so once.

## Local deltas — the complete list

Everything below lives inside this directory and is marked in place with a
`VESTARV LOCAL DELTA` comment. Nothing outside this directory was changed to
make the suite work.

### 1. `testlib.py` — three hard-coded Spike flags become target-controllable

Pristine md5 (`git show 7aeeb7d:tools/debug/testlib.py`):
`95c267a4ca992bb8a072171978e7c767`.

`Spike.__init__` gains `dm_auth=True`, `sba_bits=64`, `priv=None`, and
`Spike.command()` consumes them. **All three defaults reproduce the upstream
command line byte-for-byte**, verified by building the command line from this
file and from `git show HEAD:tools/debug/testlib.py` with the same target:

```
UPSTREAM : spike -p4 --isa RV32IMAC --dm-auth --dm-progsize 2 --dm-sba 64 \
           --dm-no-abstract-fpr -m0x10100000:0x10000000 --rbb-port 0
DEFAULTS : (identical)
VESTARV  : spike -p4 --isa RV32IMAC --dm-progsize 2 --dm-sba 0 --priv m \
           --dm-no-abstract-fpr -m0x10100000:0x10000000 --rbb-port 0
```

Why each one had to move — these are not preferences, they are the three
places the harness could not describe VestaRV at all:

* **`--dm-auth` was unconditional.** Every harness-launched Spike therefore
  demanded authentication, which is the only reason the vendored `.cfg` files
  carry an `authdata_read`/`authdata_write` handshake. VestaRV implements no
  `authdata` register (0x30 is not one of its twelve DMI addresses) and drives
  `dmstatus.authenticated = 1`, so a VestaRV `.cfg` must not perform the
  handshake — and a VestaRV-shaped *baseline* must be launchable without it.
* **`--dm-sba 64` was welded to `--dm-progsize`.** There was no target knob of
  any kind for a no-SBA machine, so the harness could not express DD5's core
  decision (VestaRV has no system bus access; memory goes through the program
  buffer). `sba_bits=0` emits `--dm-sba 0` explicitly rather than dropping the
  flag, so the baseline states its shape instead of relying on a default.
* **`--priv` was never passed**, so a harness-launched Spike always reported
  `misa` with S and U set (`0x40141105`). VestaRV's default build is M-only
  (`0x40001105`). Without this, `CheckMisa` fails against a correct debugger
  for a reason that has nothing to do with debugging.

### 2. `targets.py` — `encoding.h` resolved, not re-vendored

Pristine md5 (`git show 7aeeb7d:tools/debug/targets.py`):
`1a0dcc96764386bc17120c9a1d2ce89c`.

`do_compile()` passed a literal `-I ../env`, because upstream's `debug/` sits
beside `riscv-tests`' own `env/`. Here it does not, and **`encoding.h` was
never vendored**, so every compile the harness attempted died with

```
programs/entry.S:1:10: fatal error: encoding.h: No such file or directory
```

The file already exists in this repo at `verification/env/encoding.h`, so the
include now **points at it** (module-level `VESTA_ENV_DIR`, derived from
`__file__` rather than the cwd so it survives being invoked by absolute path).
Per R-DD6(3) there is deliberately **no second copy of `encoding.h`** — one
header with two spellings is exactly the divergence this repo has been burned
by elsewhere.

`programs/` and `bin/` paths remain **cwd-relative upstream behaviour** and
were not touched: run the harness from this directory.

### 3. `targets/VestaRV/` — the VestaRV target family

Every file here is **LOCAL**: none of it came from upstream and none of it
should be reconciled against upstream on a re-sync. Each carries the same
`LOCAL FILE (not vendored upstream)` marker in its own header.

| file | what it is |
|---|---|
| `vesta_castalia.cfg` | Castalia (N=4) OpenOCD config, `-rtos hwthread` + `target smp` — the THREAD-VIEW configuration |
| `vesta_castalia_nosmp.cfg` | Castalia, INDEPENDENT TARGETS — the halt-one-while-others-run configuration, and the one to use for anything touching a tile's PRIVATE TCM |
| `vesta_argus.cfg` | Argus (N=18) thread-view config, **generated from `vesta_castalia.cfg` by substitution** |
| `vesta_argus_nosmp.cfg` | Argus independent-targets config, **generated from `vesta_castalia_nosmp.cfg` by substitution** |
| `vesta_castalia.py` | harness target: starts the Xcelium bridge, declares the chip's structural facts (no triggers, no SBA, no hasel, `timeout_sec = 120`) |
| `vesta_argus.py` | the N=18 sibling |
| `vesta_castalia.lds` | link script for the harness-downloaded test programs |
| `vesta_excludes.yaml` | the STRUCTURAL exclusion list, used for BOTH the VestaRV run and the stock-Spike baseline so the two are scored over one denominator |

**Neither `.cfg` in a pair is a fallback for the other**, and the reason is a
measurement rather than taste: `target smp` halts the whole group on any halt,
and under `-rtos hwthread` gdb's MEMORY accesses go to the connection's target
(hart 0) while REGISTER accesses follow the selected thread — so a software
breakpoint asked for on hart 2 is planted in hart 0's private TCM. Both files'
headers carry the evidence.

**Generated pairs must be RE-DERIVED, not hand-edited.** Edit the Castalia
file and re-derive the Argus one (`NHARTS`, IDCODE, chip name in the prose);
otherwise the hundred-odd shared lines drift apart.

### 4. `.gitignore` — harness build artefacts

The suite compiles its test programs *into this directory*, naming them
`<target>_<program>-<misa>` with no extension (`vesta_castalia_debug-40101107`,
`vestaspike4_checksum-40001105`, …), so a scored run leaves several
unrelated-looking ELFs beside the vendored sources. The `.gitignore` lists
them **by shape**, because the misa suffix varies with the target and the
program list grows. It also covers `logs/` and `__pycache__/`.

### 5. `testlib.py` — TCL-RPC `command()` honors the server timeout

(Same file as delta 1; separate delta, added post-D5-close per R-D5-12.)

Upstream's `Openocd.command()` calls `self.openocd_cli.expect(...)` with no
`timeout` argument, so every TCL-RPC exchange — including the spawn-time
`Hello TCL-RPC!` handshake — runs on **pexpect's hard 30 s spawn default**,
ignoring the target's `server_timeout_sec` entirely. At N=18 OpenOCD is still
examining harts past 30 s, so the handshake dies deterministically (measured
twice at 88.81 s wall, D5 validation wave, agent D). The delta is one line:
`expect(..., timeout=self.timeout)`, where `self.timeout` is already the
target's `server_timeout_sec` (`targets.py:205`). At the upstream default
(`timeout=60`) behaviour is *more* patient than pristine, never less correct.

## Known-broken upstream files, left as-is

Neither is used by anything VestaRV runs, and neither is ours to fix:

* **`openocd.py`** calls `parsed.target(...)` as if `target` were a callable,
  but `add_target_options()` defines it as a plain string path and the real
  loader is the module-level `targets.target(parsed)` that `gdbserver.py`
  uses. It raises `TypeError: 'str' object is not callable`. **Do not use it,
  do not "fix" it.**
* **`targets/RISC-V/spike64-2-rtos.py`** names
  `openocd_config_path = "spike-rtos.cfg"`, and `spike-rtos.cfg` does not
  exist in `targets/RISC-V/`. That row cannot be scheduled.

## Housekeeping

* `__pycache__/` and `*.pyc` are already covered by the repo `.gitignore`
  (lines 132-133) — importing the harness leaves nothing to clean up and no
  new ignore rule was needed.
* The harness needs `pexpect` and `PyYAML` under a **python3 that is not
  Calibre's wrapper**; this host uses `/usr/bin/python3.6` (pexpect 4.8.0,
  PyYAML 6.0.1 installed `--user`). Never run it under a shell that has
  sourced `cdspaths.sh`.
* This tree's toolchain prefix is `riscv-none-elf-`, not upstream's
  `riscv64-unknown-elf-`: set `--gcc`/`--gdb` or the
  `RISCV_TESTS_DEBUG_GCC`/`RISCV_TESTS_DEBUG_GDB` environment variables, or
  nothing compiles.

## What is NOT in here

`tools/debug/` also holds the **Myshkin bench tooling**, which is VestaRV's
own and is unrelated to this suite: `forth_dashboard/`, `forth_dashboard_v2/`,
`fast_dsadc/`, `fast_saradc/`, `module_dash/`, `rv4th_terminal.py`,
`plot_saradc_log.py`, `test_flash_spi.py`, `RPI_SETUP.md`,
`requirements-rpi.txt`. Before D5 those files sat in the *same directory* as
this suite, so an `rsync --delete` or `rm -rf` re-vendor would have destroyed
them. That hazard is what this directory exists to remove — **keep the two
families separate.**
