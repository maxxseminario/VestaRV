# tools/ci - pre-merge checks

Four standalone checks, runnable from the workspace root with the host
`python3` (3.6) or CI's (3.11). Each exits 0 on pass, 1 on a real finding, and
2 when the instrument could not run - an exit 2 is never a pass.

## check_line_endings.py - CRLF preservation (CI-only)

Proves every file that is CRLF today is still CRLF. Much of this repo's VHDL
is CRLF on purpose, and a text-mode edit that strips the CR bytes turns a
one-line change into a whole-file diff. Also fails on unallowlisted files that
mix both endings.

    python3 tools/ci/check_line_endings.py

Backed by `crlf_manifest.txt` and `mixed_endings_allowlist.txt`. Regenerate
both with `--update`, and commit the result in the **same commit** as the
change it blesses - a lone regeneration is how the protection gets quietly
dropped. Git-based, so a bazel sandbox has nothing to grade.

## check_vhdl_style.py - VHDL is ASCII only (bazel test)

Proves no VHDL source carries an em-dash, en-dash, smart quote, unicode arrow
or non-breaking space, reporting `path:line:col` with the codepoint and name.

    python3 tools/ci/check_vhdl_style.py              # every tracked .vhd/.vhdl
    python3 tools/ci/check_vhdl_style.py path/to/x.vhd
    python3 tools/ci/check_vhdl_style.py --all        # ignore the exclusions

Bazel target `//tools/ci:check_vhdl_style_test`, over `//hdl:vhdl_sources`.
**Out of scope**, by `EXCLUDED_TREES` at the top of the script:
`hdl/myshkin/` and `hdl/argus/` (frozen per CONTRIBUTING.md's frozen-trees
table) and `tools/cosim/gate/` (vendored and generated netlists). All three
carry banned characters today and none is editable, so grading them would be a
permanent red with no legal repair. Live `hdl/common/` and `hdl/castalia/` are
graded and clean.

Un-freezing one of those trees means **deleting its line from
`EXCLUDED_TREES` in the same commit**, and fixing what the gate then reports.
The OK line always states how many files were excluded, and the script exits 2
rather than OK if the exclusions ever consume the whole file set.

## check_bazelignore.py - the 450 GB guard (bazel test)

Proves `.bazelignore` still names every EDA output tree; dropping one line
makes every bazel invocation crawl them. Also fails if an ignored directory
carries tracked files, which would mean output leaked into git.

    python3 tools/ci/check_bazelignore.py

The required set is a commented constant in the script, so a deliberate
removal has to be edited in here too. `//tools/ci:check_bazelignore_test`
stages `//:.bazelignore` and passes `--no-git`; the tracked-content half needs
a real `.git`, so CI gets it by running the script bare.

## check_repo_hygiene.py - no output in the tree (CI-only)

Proves no stray `*.rcf` is tracked, nothing tracked exceeds the 16 MiB
ceiling, and nothing tracked sits under a `.bazelignore`'d tree.

    python3 tools/ci/check_repo_hygiene.py              # whole tree
    python3 tools/ci/check_repo_hygiene.py --base main  # only a branch's adds
