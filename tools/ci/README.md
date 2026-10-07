# tools/ci — pre-merge checks

Run from the repo root with `python3`. Exit 0 = pass, 1 = finding, 2 = could not run (never a pass).

| Script | Checks | Bazel |
|---|---|---|
| `check_line_endings.py` | CRLF files stay CRLF; no unallowlisted mixed endings | CI only |
| `check_vhdl_style.py` | VHDL is ASCII only | `//tools/ci:check_vhdl_style_test` |
| `check_bazelignore.py` | `.bazelignore` names every EDA output tree | `//tools/ci:check_bazelignore_test` |
| `check_repo_hygiene.py` | No tracked `*.rcf`, nothing > 16 MiB, nothing under an ignored tree | CI only |

- Regenerate manifests (`check_line_endings.py --update`) and exclusions (`EXCLUDED_TREES` in
  `check_vhdl_style.py`) in the same commit as the change they bless.

Synthesis gates (GHDL `--synth`, flop/latch census, entity coverage):

```sh
tools/bin/bazel test //hdl/common/synth:synth //toolchains/ghdl:synth_census_test \
                     //toolchains/ghdl:synth_coverage_test
tools/bin/bazel run  //toolchains/ghdl:synth_census_update   # same commit as the RTL change
```
