# Building VestaRV with Bazel

The repo is Bazel-managed. A fresh clone needs **no locally installed
toolchains**: Bazel itself provisions Python 3.11, a C/C++ toolchain (zig),
the exact RISC-V cross-compiler the mask ROM was pinned to, a from-source
GHDL simulator, and a hermetic TeX Live, all downloaded, versioned, and
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
one) and builds GHDL from source (~10-20 min cold); everything after that is
cached, including across output-base wipes via the disk cache in `.bazelrc`.

Old-glibc hosts (the bench machine is glibc 2.26): the workspace carries
automatic shims, the xPack toolchain's `ld` is wrapped at fetch time when
`~/local-glibc` exists, and GHDL links with `-B/usr/bin`. On modern hosts
(CI's ubuntu-latest) both are inert. You never configure any of this.

## The map: what lives where

337 automatic test targets over 36 packages, plus 14 tagged `manual`. Counts
below are `bazel query` output, not estimates.

| Area | Build | Test |
|---|---|---|
| Chip generation | `//platform/common:chip_artifacts_castalia` (also ``, `_argus`, `_asic_default`, `_fpga_default`, `_castalia_repro`) | `bazel test //platform/...` (42 automatic tests, 2 more tagged `manual`): MCU.vhd / MemoryMap / riscv_tb identity, header syntax and identity (hermetic riscv-gcc), configurator sync, intro names, determinism, per-configuration generation |
| FPGA bring-up cut | `//platform/common:chip_artifacts_fpga_default` (`config/fpga_default.json`: one hart, `rv32ima`, no NPU, NFC, AFE stubs or second peripheral instances) | `//platform/common:fpga_default_generation_test` (the configuration still generates and its outputs parse) and `//opensource_sim/fpga_default:fpga_default_elaborate` (the generated `MCU.vhd` bound against `hdl/fpga/`'s synthesizable stand-ins instead of `hdl/common/sim/`, run 1 ns for the ROM and TCM size asserts). No determinism gate for this configuration. Vendor synthesis stays outside Bazel; see [`hdl/fpga/README.md`](hdl/fpga/README.md) |
| Register descriptions | `//:regs` regenerates the chain (writer) | `//platform/common:rdl_vhdl_pkg_test`, `:rdl_pkg_vs_legacy_test`, `:rdl_vs_generator_test`, `:rdl_negative_control_test`, 21 `:rdl_vs_vhdl_<block>_test`, 3 `:regs_headers_*_test`; toolchain smoke in `//tools/rdl` (2) |
| Boot ROM (mask-ROM image) | `//software/bootrom_mp:rom_rcf` | `:rom_rcf_reproducibility_test`, byte-identity vs the tracked golden |
| Firmware apps | `//software/blinky` (+gpiotoggle, looptest, slowblink, traptest), each `:NAME_elf/_bin/_rcf/_flashed_rcf` | per-app `_flashed_rcf_test` golden gates, plus `//software/commune:myshkin_h_coexist_test` |
| Debug trampoline | `//software/dbg_trampoline:dbg_trampoline_words` | `:dbg_trampoline_words_test`, `//tools/cosim:check_dbg_trampoline_test` |
| ISA test images | `//verification/isa:all_images` (518 files: 259 programs, plain and flashed), per-suite `:rv32ui_rcfs` / `:rv32ui_flashed` ... plus ON-polarity `os_*` variants | `:image_contract_test` |
| Open-source simulation (GHDL, no licenses) | toolchain: `//toolchains/ghdl:ghdl` (`@ghdl//:ghdl_mcode`, built from source) | `//opensource_sim:isa_rv32ui` ... `:isa_rv32uzf` (9 suites, `:isa_regression` aggregate), 43 per-test `//opensource_sim/isa:rv32ui-p-*`, 22 `//opensource_sim/pmp:*` (`:pmp` aggregate, both fetch-ahead polarities), MCU-level `//opensource_sim/mcu:mcu_elaborate` / `:tcm_port_tb`, `//opensource_sim/asic_default:*` (2), `//opensource_sim/fpga_default:fpga_default_elaborate` and `//opensource_sim/rv4th:rv4th_forth` (boot ROM Forth monitor over UART0; `:rv4th_forth_full` is the `manual` whole-bench variant) |
| Unit benches | RTL source sets per block | `//hdl/common/tb:all`: 26 `ghdl_test` benches, one per peripheral plus `mp_arbiter_tb`, `pmp_unit_tb`, `dbg_module_tb`, `jtag_dtm_tb`, `periph_regs_tb`, `sync_tb`, `arb_lat_tb`, `irq_sys_tb`; plus `:fpu_vectors_format_test` |
| Synthesizability | - | `//hdl/common/synth:synth`, 39 `ghdl --synth` targets; `//toolchains/ghdl:synth_census_test` freezes their flop, latch and cell counts (39 entities, 2 recorded as skipped), `:synth_coverage_test` fails when an entity under `hdl/common/` is synthesized by nothing |
| Performance | - | `//verification/cpi:cpi_default` / `:cpi_full` / `:micro` (58 tests: recorded cycle and instruction counts per benchmark) |
| Python tooling | `//tools/cosim`, `//tools/randgen`, `//tools/python`, `//tools/build`, `//tools/ci`, `//verification/npu` | comparator, oracle, randgen, tracer-independence, entity-defaults, knob classes, doc-links, image maps, bazelignore and VHDL style, NPU golden regen + validate_mlp (9) |
| Docs provenance | - | `//docs:theme_sync_test`, `//tools/python:check_doc_links_test`, register-browser and web-data gates under `//platform/common` |
| TRM PDF | `//platform/common/latex/bazel:trm_pdf_local` (manual; host TeX) | `:check_publish_test`, `:trm_lint_test` (manual) |

Everyday flows:

```sh
tools/bin/bazel test //...                        # the whole gate set
tools/bin/bazel test //opensource_sim:isa_regression   # full ISA sim, license-free
tools/bin/bazel build //software/bootrom_mp:rom_rcf    # the mask-ROM image
tools/bin/bazel build //platform/common:chip_artifacts_castalia
tools/bin/bazel run //:regs                            # .rdl -> VHDL packages -> C headers -> generator (writes)
tools/bin/bazel run //tools/python:theme_sync          # re-splice the theme block (writes docs/)
tools/bin/bazel run //platform/common/python:splice_register_browser -- --data <MemoryMap.json> docs/register_browser.html
```

Writers (`bazel run` targets that edit the source tree) are deliberate and
enumerated: `//:regs` and the three emitters it chains
(`//platform/common/python:rdl_vhdl_pkgs`, `:rdl_regs_headers`, `:generate`),
`//platform/common/python:splice_register_browser` and `:splice_web_data`,
`//tools/python:theme_sync`, and `//toolchains/ghdl:synth_census_update`.
Everything under `bazel build`/`bazel test` is sandboxed and never touches the
tree. Never run `bazel run //:generate` on its own casually, it is the raw
generator and writes wherever it runs; the hermetic path is
`chip_artifacts_castalia` and the deliberate path is `//:regs`.

## What is NOT Bazel, and why

- **Cadence flows**: Xcelium regressions (`xcelium/*/xrun_parallel.sh`),
  Genus/Innovus/Pegasus, `make verify`, the PSL runs: licensed binaries
  under `/opt/cadence` behind a license server. Run them exactly as before
  (`source cdspaths.sh; ...`). They are permanently out of `//...`; any
  future wrapper must be tagged `manual`+`local`+`no-sandbox`.
- **In-tree regeneration of tracked artifacts**: Bazel generation is
  sandboxed and never writes into the source tree, so the one thing it
  cannot do is UPDATE a tracked generator product such as
  `hdl/common/MCU.vhd` or a package under `hdl/common/regs/vhdl/`. The writers
  named above do that (`bazel run //:regs` for the whole register chain,
  `cd platform/common && make chip` for the generator half alone); `bazel test
  //platform/...` is what proves the result. That is the only remaining role of
  the in-tree `make` targets: they are no longer a documented alternative route
  for building anything, and the READMEs describe the Bazel path only. The TRM
  `pdf` half is Bazel-wrapped host TeX (`trm_pdf_local`); fully hermetic LaTeX
  is blocked upstream
  (bazel_latex is lualatex-only and lacks 21 of the TRM's 45 package
  wrappers).
- **Bench / hardware tools**: the Forth dashboard, `rv4th_terminal.py`,
  flash/chip programmers, PyEmanate: they talk to physical boards over
  serial. Runtime tools, not builds; unmanaged by Bazel (their pip deps are
  also unpinned; lock them first if they ever move in).
- **Myshkin generator** (`platform/myshkin`) overwrites tracked files
  in-place, so it cannot be sandboxed. It is the only documentation for
  regenerating the Myshkin platform files; run it directly.
- **Spike lockstep cosim build** (`tools/cosim/build_vesta_ref.sh`): pinned
  out-of-repo Spike + conda gcc; a future `http_archive` port is scoped in
  the devlog.

## Conventions and sharp edges

- **Goldens**: firmware images are locked by tracked
  `testdata/*_golden.txt` files (`*.rcf` is globally gitignored, hence the
  extension). Changing firmware means regenerating the golden in the same
  commit; the test diff shows exactly what moved.
- **Known red**: NO TARGET CARRIES THE TAG TODAY. The last two uses were
  `//tools/build:verification_image_map_test` (the image-map overlap,
  adjudicated 2026-09-12: all 595 `//verification/isa` and `//verification/cpi`
  images fit the regions the generated map declares; the 47 red images were the
  ISR bank and `.npu0_yhat` landing in the 8 KiB TCM's own upper mirror after the
  2026-08-16 halving, moved down 0x2000 onto the same physical words, and nine
  CPI working sets running past the end of the TCM, re-based at 0x10000 with all
  58 recorded cycle and instruction counts unchanged) and
  `//tools/randgen:test_randgen`'s k3s01 campaign-pin drift (adjudicated
  2026-08-23 as benign config drift, `priv.trapCsr` and `numHarts` 4->5 moving
  the resolved-config identity every stream header carries; the evidence is in
  `tools/randgen/BUILD.bazel`). The tag and CI's `--test_tag_filters=-known_red`
  stay as the standing mechanism for a red that is understood but not yet
  adjudicated; the rule is that the tag comes off in the same commit that
  adjudicates the failure, which is the only way such a carve-out ends.
  `check_publish_test` (manual) is red whenever TRM-affecting commits have
  landed since the last publish; that is the point of the gate.
- **`private/` is out of the graph**: the analog interfacing collateral removed
  from the public tree on 2026-09-11 lives in the gitignored `private/`, whose
  BUILD files name chip artifacts the public tree no longer defines. It is a
  `.bazelignore` entry; the Genus and Xcelium flows read it directly.
- **Repo hygiene checks** live in `tools/ci/` and run in CI's `Repo hygiene gates`
  job: the CRLF manifest guard, the VHDL ASCII style gate, the
  `.bazelignore` integrity check and the tracked-output check. The two that
  need no git are also `//tools/ci` bazel tests, so `bazel test //...` runs
  them too. See `tools/ci/README.md`.
- **Untracked-file skew**: local `bazel test //...` sees your untracked
  files; CI's clean checkout does not. Before pushing BUILD-graph changes:
  `git stash -u && tools/bin/bazel build //... ; git stash pop` (or use a
  clean worktree).
- **CRLF is load-bearing** in much of the VHDL; never let a tool rewrite
  line endings.
- New BUILD files inside `hdl/` create packages that hide files from
  `//hdl:vhdl_sources`'s glob; re-export via a filegroup like
  `//hdl/common/tb:tb_vhdl_sources` does.
- The huge EDA output trees (`signoff_mp/`, `xcelium/`, `innovus/`,
  `genus/`, ~450 GB) are listed in `.bazelignore`; never remove entries.

## CI

Bazel carries two CI jobs, one in `ci.yml` and one in `sim.yml`, split on one
line: whether the job needs GHDL. The other four `ci.yml` jobs (`Chip generator
gates`, `Docs link + generator syntax gates`, `Bootrom + ISA image builds`,
`Repo hygiene gates`) run their scripts directly.

`ci.yml`'s **`Bazel hermetic gates`** runs the everything-else half from a
bare checkout with no locally installed toolchain:

```sh
tools/bin/bazel mod deps --lockfile_mode=error          # the lock is current
tools/bin/bazel build --nobuild -- //... -//opensource_sim/... -//hdl/common/tb/... -//toolchains/...
tools/bin/bazel test --build_tests_only --test_tag_filters=-known_red \
  -- //... -//opensource_sim/... -//hdl/common/tb/... -//toolchains/... \
     -//hdl/common/synth/... -//verification/cpi/...
```

Note the `--` before the negative patterns; bazel rejects a bare leading
`-//...` as a malformed option. The analysis step excludes three package
trees, the test step five: `//hdl/common/synth` and `//verification/cpi` run
GHDL, so they are tested in `sim.yml` but still ANALYZED here, which is what
catches a broken BUILD file there in seconds. That set is 82 tests today and
finishes in minutes on a warm cache, which is what makes it safe to require in
the merge queue. The job then asserts `git status --porcelain` is empty,
BAZEL.md's claim that build and test never write into the source tree,
enforced.

`sim.yml`'s **`GHDL ISA regression (bazel)`** runs the GHDL half:
`//opensource_sim:isa_regression`, the `//hdl/common/tb:all` unit benches,
`//hdl/common/synth:synth`, `//toolchains/ghdl:synth_census_test` and
`:synth_coverage_test`, `//verification/cpi:cpi_default`,
`//opensource_sim/pmp:pmp`, `//opensource_sim/mcu:mcu_elaborate`,
`//opensource_sim/castalia_b:castalia_b_elaborate`,
`//opensource_sim/fpga_default:fpga_default_elaborate`, `//opensource_sim/tile_isa:tile_rv32ui`
and `//opensource_sim/rv4th:rv4th_forth`. First cold run builds GHDL from source
(~20-30 min), warm runs are fast.
That job takes **explicit targets, never `//opensource_sim/...` by wildcard**,
and `ci.yml` excludes `//opensource_sim/...` wholesale so it never builds GHDL
from source. A new GHDL target therefore runs in `bazel test //...` locally
and in **neither** workflow until it is named in `sim.yml`.

`ci.yml`'s **`Repo hygiene gates`** runs the `tools/ci/` scripts directly
(they need git history, which a bazel sandbox does not have).

Required-check names are matched verbatim by the merge-queue ruleset: do not
rename jobs without updating the ruleset in the same breath. See
`.github/MERGE_QUEUE.md` for which of these are safe to require.
