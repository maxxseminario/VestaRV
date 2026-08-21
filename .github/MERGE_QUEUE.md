# Merge queue setup (GitHub native)

The queue is GitHub's own, not a third-party app: no bot account, no install, no
extra token. Everything it runs is already in `.github/workflows/`, and the only
thing outside the repo is a branch ruleset you set once in the GUI.

## What it buys this repo

CI's `push:` trigger only watches `main` and `multicore-mp`, so work on a topic
branch is unproven until it lands. The queue closes that: before a PR merges,
GitHub builds a throwaway `gh-readonly-queue/main/...` branch holding the PR
**rebased onto current main plus every PR ahead of it in the queue**, runs the
required checks against that, and only merges if they pass. A PR that is green
on its own head but breaks against a main that moved underneath it gets kicked
out of the queue instead of breaking `main`.

That rebase-and-test is the whole point. It is not the same as "CI passed on the
PR" — that only ever proved the PR against the main it branched from.

## Consequence to accept before switching it on

Requiring a merge queue on `main` also requires pull requests on `main`. The
local fast-forward habit (`git merge` a finished series straight into `main`,
then push) stops working — pushes to `main` get rejected. If that is not what
you want, do not enable the ruleset; the `merge_group:` triggers already in the
workflows are inert until a queue exists.

## 1. Required status checks

These are the three tier-1 jobs in `ci.yml`. The check name GitHub matches on is
the job's `name:`, verbatim:

```
Chip generator gates
Docs link + generator syntax gates
Bootrom + ISA image builds
```

All three run on GitHub-hosted runners in a few minutes and need no licenses, so
a queued PR is never waiting on the bench machine.

Two more hosted, fast, `merge_group`-triggered candidates from `physical.yml`
(tier 3) are safe to add if you also want the queue to prove GHDL still
elaborates the tree and the core still executes:

```
Verilog bridge (GHDL synth)
Core smoke sim (cocotb on GHDL)
```

Do **not** add `physical.yml`'s harden job: it is skipped on merge-group events
by design (a 4–5 h GDSII run has no business in a merge path), so requiring it
stalls the queue exactly like a `sim.yml` job would.

**Do not add any `sim.yml` job.** That file has no `merge_group:` trigger (see
its header for why), so a required check pointing at it would have nothing to
satisfy it and the queue would sit until it times out.

## 2. Repo settings

Settings -> Rules -> Rulesets -> New branch ruleset:

* Target: `main` (add `multicore-mp` too if you want the same discipline there).
* Enforcement status: **Active**.
* Rules:
  * **Require a pull request before merging** — 0 approvals is fine for a
    solo repo; the queue is here for correctness, not review ceremony.
  * **Require status checks to pass** — add the three names above.
  * **Require merge queue**.
  * **Block force pushes** (default on, keep it).

Then open the merge-queue rule's settings:

| Setting | Value | Why |
| --- | --- | --- |
| Merge method | Squash | Matches the one-commit-per-idea history already in the log. Rebase also works; Merge adds commits this repo does not otherwise carry. |
| Build concurrency (max PRs to build) | 5 | Cheap here — the checks are hosted-runner only. |
| Minimum / maximum PRs to merge | 1 / 5 | Batches when the queue is busy, merges immediately when it is not. |
| Wait time to merge | 5 min | How long to hold a partial batch before merging it anyway. |
| Only merge non-failing PRs | on | Kick a candidate out rather than merging it red. |

## 3. What still runs where

| Trigger | Runs | Notes |
| --- | --- | --- |
| PR opened / pushed | `ci.yml` tier 1 | Fast feedback on the PR head. Duplicated by the queue run later; that is expected and cheap. |
| PR labelled `run-sim` | `sim.yml` smoke suite | Still opt-in, still one Cadence seat at a time. Unchanged. |
| Queued for merge | `ci.yml` tier 1 on the rebased candidate | The gate that actually protects `main`. |
| Queue merges to `main` | `sim.yml` full regression + `pages.yml` deploy | Both key off `push: branches: [main]`, and the queue's merge is such a push. Post-merge safety net, unchanged. |

## 4. Verifying it works

Open a throwaway PR, let tier 1 go green, and merge it through the queue. In the
PR timeline you should see a "queued" entry and a second set of the three checks
attributed to a `merge_group` event on a `gh-readonly-queue/main/...` ref. If the
PR sits in the queue with no checks starting, the `merge_group:` trigger is
missing from `ci.yml` or a `sim.yml` job got added to the required list.
