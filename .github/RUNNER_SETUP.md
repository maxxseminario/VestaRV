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

## 3. Install as a service

```bash
cd ~/actions-runner
sudo ./svc.sh install mseminario2
sudo ./svc.sh start
```

Running as a service (its own session) also sidesteps the session-reaper
problem noted for long interactive jobs.

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
