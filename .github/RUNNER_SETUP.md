# Self-hosted runner setup (Tier-2 simulation CI)

`sim.yml` needs a GitHub Actions runner **on the bench machine** (the one with
Xcelium 20.09 and the `5280@poseidon` licenses). Hosted runners can never run
this tier: the EDA tools are licensed/on-prem, and the sim flow state
(`xcelium/`, ARM vendor memory models) is deliberately untracked.

## 1. Register the runner

Repo → Settings → Actions → Runners → "New self-hosted runner", then on this
machine (pick a dedicated directory, **not** `~/vestarv` — the runner must never
share a working tree with interactive sessions):

```bash
mkdir -p ~/actions-runner && cd ~/actions-runner
# download + extract per the GitHub instructions page, then:
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1   # SUSE ICU sonames aren't .NET-probeable
./config.sh --url https://github.com/maxxseminario/VestaRV \
            --token <registration-token> \
            --labels cadence \
            --unattended
```

The `cadence` label is what `runs-on: [self-hosted, cadence]` selects.

STATE 2026-07-18: runner v2.335.1 is already downloaded/extracted at
`~/actions-runner` with `.env` (LANG + the DOTNET invariant-globalization flag —
this box's libicu ships SUSE-suffixed sonames .NET cannot probe) and `.path`
(riscv-none-elf toolchain first) pre-written; only `config.sh` (needs a fresh
registration token from the GUI) and the service install remain.

**DEFECT FOUND 2026-08-21 — the `cadence` label was never applied.** The
2026-07-18 `config.sh` run was interactive and Enter was pressed at the
"additional labels" prompt (`_diag/Runner_20260718-183620-utc.log`: `Read
value: ''`), so runner `atlas` carries only `self-hosted, Linux, X64`.
`runs-on: [self-hosted, cadence]` therefore NEVER matches: the listener sits
healthy and idle while every `sim.yml` job queues until the next push's
concurrency-group entry cancels it — which is why every sim run since July
shows "cancelled" and `_diag` contains zero `Worker_*.log`. A runner that has
never taken a job + all-cancelled history = label mismatch, not a runner
crash. Fix (either one):

* Repo → Settings → Actions → Runners → `atlas` → edit labels → add
  `cadence`. Takes effect immediately, no re-registration.
* Or re-run `./config.sh remove` + `./config.sh --labels cadence …` with
  fresh tokens from that same page.

The queued job backlog does not drain retroactively — cancel any stuck
`sim.yml` runs in the Actions tab after applying the label, then dispatch
one manually to verify a `Worker_*.log` finally appears in `_diag/`.

## 2. Seed the runner workspace (one-time)

The first `sim.yml` run creates the workspace clone at
`~/actions-runner/_work/VestaRV/VestaRV`. Its guard step will fail until the
untracked sim state is seeded from the canonical tree. Trigger one run (it
fails at the guard), then:

```bash
WS=~/actions-runner/_work/VestaRV/VestaRV

# Sim flow trees (scripts, cell lists, wrappers, tcl, periph images) — exclude
# heavy rebuildable state:
rsync -a --exclude 'xcelium.d' --exclude '*.shm' --exclude 'waves*' \
         --exclude 'xrun.history' \
         ~/vestarv/xcelium/ "$WS/xcelium/"

# ARM vendor memory models (gitignored via *ARM*):
rsync -a ~/vestarv/hdl/common/sim/ "$WS/hdl/common/sim/"
```

Notes:
- `sim.yml` checks out with `clean: false`, so the seed survives every run.
  **Never** run `git clean -dfx` in this workspace.
- Bootrom `bin/rom.rcf` and the ISA rcf images do **not** need seeding — the
  workflow rebuilds both at the commit under test (the bootrom build is proven
  byte-identical to the bench build with the pinned xpack 13.2.0-2 toolchain).
- The workspace's `xcelium/riscv_test/rcf` must end up NHARTS=4-stamped; the
  workflow's `build_mp_images.sh 4` step guarantees that on every run.
- `riscv-none-elf-` must be on the runner's PATH (it is sourced from the
  login profile if the runner is installed as a service below; otherwise add
  `~/riscv-toolchain/xpack-riscv-none-elf-gcc-13.2.0-2/bin` to the runner's
  `.env` file).

## 3. Keep it running (no sudo on this box — no systemd service)

DONE 2026-07-18: the runner ("atlas") runs as a detached user process plus a
user-crontab `@reboot` entry:

```bash
cd ~/actions-runner && setsid nohup ./run.sh >> runner.log 2>&1 < /dev/null &
crontab -l   # @reboot line relaunches it after a server reboot
```

`setsid` gives it its own session (survives logout AND sidesteps the
session-reaper problem noted for long interactive jobs). Health check:
`tail ~/actions-runner/runner.log` should end with "Listening for Jobs";
restart with the same setsid line if not.

## 4. License etiquette (encoded in sim.yml — do not weaken)

- `concurrency: cadence-license` serializes all sim jobs; it cannot see your
  interactive sessions, so expect CI to queue behind you, not vice versa.
- Every sim job ends with `pkill -9 xmsim` on `always()` — a hung run must not
  hold seats overnight.
- `MAX_PARALLEL` is 6 (ISA) / 5 (periph); raise only if the license pool grows.

## 5. What runs when

| Job | Trigger | Duration |
|---|---|---|
| `sim-smoke` (27 tests) | PR labeled `run-sim` | ~10 min |
| `sim-full` (117 ISA + periph) | push to `main`, nightly 08:30 UTC, manual | ~1–2 h |

Tier-1 checks (`ci.yml`) and the Pages deploy (`pages.yml`) run on GitHub-hosted
runners and need nothing from this machine.
