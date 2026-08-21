# Building VestaRV with Bazel

The repo is Bazel-managed. A fresh clone needs **no locally installed
toolchains**: Bazel itself provisions Python 3.11, a C/C++ toolchain (zig),
the exact RISC-V cross-compiler the mask ROM was pinned to, a from-source
GHDL simulator, and a hermetic TeX Live — all downloaded, versioned, and
sandboxed by the build. The only tools that stay outside Bazel are the
licensed Cadence installs and physical bench hardware (see the last section).

## Bootstrap (one step)

```sh
sh tools/get_bazel.sh        # fetches bazelisk into tools/bin/bazel
tools/bin/bazel build //...  # first run downloads all toolchains
tools/bin/bazel test //...
```

`tools/bin/bazel` is bazelisk: it reads `.bazelversion` (pinned 9.2.0) and
runs that exact Bazel. Add `<repo>/tools/bin` to `PATH` if you want plain
`bazel`. The first build fetches ~1 GB of toolchains (RISC-V GCC is the big
one) and builds GHDL from source (~10–20 min cold); everything after that is
cached, including across output-base wipes via the disk cache in `.bazelrc`.

Old-glibc hosts (the bench machine is glibc 2.26): the workspace carries
automatic shims — the xPack toolchain's `ld` is wrapped at fetch time when
`~/local-glibc` exists, and GHDL links with `-B/usr/bin`. On modern hosts
(CI's ubuntu-latest) both are inert. You never configure any of this.

## The map: what lives where

| Area | Build | Test |
|---|---|---|
| Chip generation (Castalia) | `//platform/common:chip_artifacts_castalia` (also `_argus`) | `bazel test //platform/...` — MCU.vhd/MemoryMap/riscv_tb identity, header syntax (hermetic riscv-gcc), configurator sync, intro names, determinism |
| Boot ROM (mask-ROM image) | `//software/bootrom_mp:rom_rcf` | `:rom_rcf_reproducibility_test` — byte-identity vs the tracked golden |
| Firmware apps | `//software/blinky` (+gpiotoggle, looptest, slowblink, traptest, afetest) — each `:NAME_elf/_bin/_rcf/_flashed_rcf` | per-app `_flashed_rcf_test` golden gates |
| Course labs (all 21, incl. skeletons) | `//software/course/labs/...` | per-lab golden tests |
| Debug trampoline | `//software/dbg_trampoline:dbg_trampoline_words` | `:dbg_trampoline_words_test`, `//tools/cosim:check_dbg_trampoline_test` |
| ISA test images (259, polarity in the action key) | `//verification/isa:all_images`, per-suite `:rv32ui_rcfs` / `:rv32ui_flashed` ... plus ON-polarity `os_*` variants | `:image_contract_test` |
| Open-source simulation (GHDL, no licenses) | toolchain: `//toolchains/ghdl:ghdl` (`@ghdl//:ghdl_mcode`, built from source) | `//opensource_sim:isa_rv32ui` ... `:isa_rv32uzf` (9 suites, `:isa_regression` aggregate), per-test `//opensource_sim/isa:rv32ui-p-*`, unit benches `//hdl/common/tb:mp_arbiter_tb`, `:pmp_unit_tb` |
| Python tooling | `//tools/cosim`, `//tools/randgen`, `//tools/python`, `//verification/npu` | comparator, oracle, randgen, tracer-independence, entity-defaults, doc-links, NPU golden regen + validate_mlp |
| Docs provenance | — | `//docs:theme_sync_test`, register-browser gate under `//platform/common` |
| TRM PDF | `//platform/common/latex/bazel:trm_pdf_local` (manual; host TeX) | `:check_publish_test`, `:trm_lint_test` (manual) |

Everyday flows:

```sh
tools/bin/bazel test //...                        # the whole gate set
tools/bin/bazel test //opensource_sim:isa_regression   # full ISA sim, license-free
tools/bin/bazel build //software/bootrom_mp:rom_rcf    # the mask-ROM image
tools/bin/bazel build //platform/common:chip_artifacts_castalia
tools/bin/bazel run //tools/python:theme_sync          # re-splice the theme block (writes docs/)
tools/bin/bazel run //platform/common/python:splice_register_browser -- --data <MemoryMap.json> docs/register_browser.html
```

Writers (`bazel run` targets that edit the source tree) are deliberate and
few: `theme_sync`, `splice_register_browser`, `splice_web_data`. Everything
under `bazel build`/`bazel test` is sandboxed and never touches the tree.
Never run `bazel run //:generate` casually — it is the raw generator and
writes wherever it runs; the hermetic path is `chip_artifacts_castalia`.

## What is NOT Bazel, and why

- **Cadence flows** — Xcelium regressions (`xcelium/*/xrun_parallel.sh`),
  Genus/Innovus/Pegasus, `make verify`, the PSL runs: licensed binaries
  under `/opt/cadence` behind a license server. Run them exactly as before
  (`source cdspaths.sh; ...`). They are permanently out of `//...`; any
  future wrapper must be tagged `manual`+`local`+`no-sandbox`.
- **`make chip` / `make generate`** — still work unchanged, but they are the
  legacy in-tree path. The Bazel generation is the verified equivalent with
  the gates attached; prefer it. The `pdf` half is Bazel-wrapped host TeX
  (`trm_pdf_local`); fully hermetic LaTeX is blocked upstream (bazel_latex
  is lualatex-only and lacks 21 of the TRM's 45 package wrappers).
- **Bench / hardware tools** — the Forth dashboard, `rv4th_terminal.py`,
  flash/chip programmers, PyEmanate: they talk to physical boards over
  serial. Runtime tools, not builds; unmanaged by Bazel (their pip deps are
  also unpinned — lock them first if they ever move in).
- **Myshkin legacy generator** (`platform/myshkin`) — overwrites tracked
  files in-place; untouched, run it the old way if you must.
- **Spike lockstep cosim build** (`tools/cosim/build_vesta_ref.sh`) — pinned
  out-of-repo Spike + conda gcc; a future `http_archive` port is scoped in
  the devlog.

## Conventions and sharp edges

- **Goldens**: firmware images are locked by tracked
  `testdata/*_golden.txt` files (`*.rcf` is globally gitignored, hence the
  extension). Changing firmware means regenerating the golden in the same
  commit — the test diff shows exactly what moved.
- **Known red**: `//tools/randgen:test_randgen`'s k3s01 case — a
  pre-existing campaign-pin drift (CPR8 re-pin), kept red until adjudicated.
  `check_publish_test` (manual) is red whenever TRM-affecting commits have
  landed since the last publish; that is the point of the gate.
- **Untracked-file skew**: local `bazel test //...` sees your untracked
  files; CI's clean checkout does not. Before pushing BUILD-graph changes:
  `git stash -u && tools/bin/bazel build //... ; git stash pop` (or use a
  clean worktree).
- **CRLF is load-bearing** in much of the VHDL; never let a tool rewrite
  line endings.
- New BUILD files inside `hdl/` create packages that hide files from
  `//hdl:vhdl_sources`'s glob — re-export via a filegroup like
  `//hdl/common/tb:tb_vhdl_sources` does.
- The huge EDA output trees (`signoff_mp/`, `xcelium/`, `innovus/`,
  `genus/`, ~450 GB) are listed in `.bazelignore`; never remove entries.

## CI

`ci.yml` runs the tier-1 gates and `sim.yml` runs
`bazel test //opensource_sim:isa_regression` on GitHub-hosted runners —
first cold run builds GHDL from source (~20–30 min), warm runs are fast.
Required-check names are matched verbatim by the merge-queue ruleset: do not
rename jobs without updating the ruleset in the same breath.
