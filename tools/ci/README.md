# tools/ci — pre-merge checks

Run from the repo root with host `python3` (3.6) or CI's 3.11. Exit 0 = pass, 1 = finding,
2 = could not run (never a pass).

| Script | Checks | Bazel target |
|---|---|---|
| `check_line_endings.py` | Every CRLF file stays CRLF; no unallowlisted mixed endings | CI only (git-based) |
| `check_vhdl_style.py [path…] [--all]` | VHDL is ASCII only (no smart quotes, dashes, arrows, NBSP) | `//tools/ci:check_vhdl_style_test` |
| `check_bazelignore.py` | `.bazelignore` names every EDA output tree; no tracked files under them | `//tools/ci:check_bazelignore_test` (`--no-git` half) |
| `check_repo_hygiene.py [--base main]` | No tracked `*.rcf`, nothing over 16 MiB, nothing under an ignored tree | CI only |

Rules:

- `check_line_endings.py --update` regenerates `crlf_manifest.txt` and
  `mixed_endings_allowlist.txt`; commit the result in the same commit as the change it blesses.
- `check_vhdl_style.py` skips `EXCLUDED_TREES` (`hdl/myshkin/`, `hdl/argus/`, `tools/cosim/gate/`:
  frozen or vendored). Un-freezing a tree means deleting its line in the same commit.
- `check_bazelignore.py`: the required set is a constant in the script; the tracked-content
  half needs a real `.git`, so CI also runs the script bare.

## Synthesis census (related gates, `toolchains/ghdl/`)

```sh
tools/bin/bazel test //hdl/common/synth:synth //toolchains/ghdl:synth_census_test \
                     //toolchains/ghdl:synth_coverage_test
tools/bin/bazel run  //toolchains/ghdl:synth_census_update   # bless a deliberate count change
```

| Target | Checks |
|---|---|
| `//hdl/common/synth:synth` | `ghdl --synth` on every `hdl/common/` block; rejects process `wait`, inferred latches, out-of-range constant indices |
| `//toolchains/ghdl:synth_census_test` | Flop/latch/cell counts against `toolchains/ghdl/synth_census.json` |
| `//toolchains/ghdl:synth_coverage_test` | Every `hdl/common/` entity is a synth top or inside one; exclusions in `EXCLUSIONS` of `toolchains/ghdl/synth_coverage.py` |

Regenerate the census in the same commit as the RTL change. Documented skips (`SYSTEM`,
`periph_regs`) and the black-box stubs for `hart_tile`, `orch_tile` and `MCU` are described in
`hdl/common/synth/BUILD.bazel`.
