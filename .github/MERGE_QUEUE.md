# Merge queue setup (GitHub native)

The queue is GitHub's own, not a third-party app: no bot account, no install, no
extra token. Everything it runs is already in `.github/workflows/`, and the only
thing outside the repo is a branch ruleset you set once in the GUI.

## What it buys this repo

CI's `push:` trigger only watches `main`, so work on a topic branch is unproven
until it lands. The queue closes that: before a PR merges,
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

These are the five tier-1 jobs in `ci.yml`. The check name GitHub matches on is
the job's `name:`, verbatim:

```
Chip generator gates
Docs link + generator syntax gates
Bootrom + ISA image builds
Bazel hermetic gates
Repo hygiene gates
```

All five run on GitHub-hosted runners in a few minutes and need no licenses, so
a queued PR is never waiting on the bench machine.

`Bazel hermetic gates` is the broadest of them: it is `bazel test //...` minus
the GHDL half, so it proves chip generation, every firmware golden,
the ISA image contract, the python tooling and the docs gates from a
checkout with no toolchain installed at all. Its cost is bounded by the bazel
disk cache the job restores; a cold cache is the only slow case, and it does
not build GHDL. Requiring it is the single highest-value addition to the queue.

`Repo hygiene gates` is seconds: the `tools/ci/` guards (CRLF manifest, VHDL
ASCII style, `.bazelignore` integrity, no EDA output tracked). It checks out
with `fetch-depth: 0` because the hygiene scan is diff-scoped on pull requests.

Only `ci.yml` jobs are safe as required checks today. `physical.yml` runs on
pull requests only when `hdl/`, `sky130/` or its own files change, and `sim.yml`
skips changes confined to `docs/` and `*.md`. A required check whose workflow is
path-filtered out of a PR never reports, and GitHub blocks that PR. To require
`Verilog bridge (GHDL synth)`, `Core smoke sim (cocotb on GHDL)` or
`GHDL ISA regression (bazel)`, first delete that workflow's `pull_request` path
filter (`merge_group` is never path-filtered).

Do **not** add `physical.yml`'s harden job: it is skipped on merge-group events
by design (a 4–5 h GDSII run has no business in a merge path), so requiring it
stalls the queue.

`sim.yml` is the hosted GHDL regression; with its path filter removed it can be
required (budget ~20-35 min).

## 2. Repo settings

Settings -> Rules -> Rulesets -> New branch ruleset:

* Target: `main`.
* Enforcement status: **Active**.
* Rules:
  * **Require a pull request before merging** — 0 approvals is fine for a
    solo repo; the queue is here for correctness, not review ceremony.
  * **Require status checks to pass** — add the five names above.
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
| PR opened / pushed | `ci.yml` tier 1 + `sim.yml` ISA regression (unless docs-only) + `physical.yml` fast jobs (if `hdl/` or `sky130/` changed) | All hosted, license-free. Duplicated by the queue run later; that is expected and cheap. |
| PR labelled `run-physical` | `physical.yml` harden (full GDSII) | Opt-in, 4–5 h. |
| Queued for merge | `ci.yml` tier 1 (+ any of the hosted sim/physical jobs made required) on the rebased candidate | The gate that actually protects `main`. |
| Queue merges to `main` | `ci.yml`, `sim.yml`, `physical.yml` fast jobs, `pages.yml` deploy (each subject to its path filter) | All key off `push: branches: [main]`, and the queue's merge is such a push. Post-merge safety net. |

## 4. Verifying it works

Open a throwaway PR, let tier 1 go green, and merge it through the queue. In the
PR timeline you should see a "queued" entry and a second set of the required checks
attributed to a `merge_group` event on a `gh-readonly-queue/main/...` ref. If the
PR sits in the queue with no checks starting, the `merge_group:` trigger is
missing from `ci.yml` or a path-filtered job got added to the required list.
