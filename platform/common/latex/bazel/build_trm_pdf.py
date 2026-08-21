#!/usr/bin/env python3
"""Build the TRM PDF from a generated latex/TRM tree, reproducibly.

This is the Bazel port of the `pdf` target in platform/common/Makefile.
It copies the (read-only) input tree into a writable scratch directory,
removes every stale auxiliary file, and runs pdflatex three times with
SOURCE_DATE_EPOCH and FORCE_SOURCE_DATE pinned.

Three passes is not superstition: pass 1 writes the .aux/.toc, pass 2
resolves the cross-references those files feed, and pass 3 settles the
page numbers that lastpage and the tables of contents moved in pass 2.
Fewer passes give a converged-looking PDF that still differs byte for
byte from the next build of the same sources.

SOURCE_DATE_EPOCH is an arbitrary fixed instant, not the build time.
With it set, pdfTeX pins /CreationDate, /ModDate and the trailer /ID, so
identical sources give a byte-identical PDF.  That is what makes the
publish check a meaningful byte-diff.  Do not derive it from HEAD or from
the wall clock, or rebuilds stop being reproducible.

The TRM's VISIBLE revision date is a separate thing entirely.  It is baked
into include/defines.tex at GENERATION time from VESTA_TRM_DATE_EPOCH, so
it is not this script's business and cannot be corrected here.
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

# The arbitrary fixed instant, 2025-01-01 UTC.
# Keep this equal to SOURCE_DATE_EPOCH in platform/common/Makefile.
SOURCE_DATE_EPOCH = "1735689600"

# Auxiliary files that must not survive from a previous build.
AUX_SUFFIXES = (".aux", ".toc", ".out", ".lof", ".lot", ".idx")

PASSES = 3


def find_pdflatex(explicit):
    """Resolve pdflatex the way the Makefile does: PATH first, then ~/texlive."""
    if explicit:
        return explicit
    found = shutil.which("pdflatex")
    if found:
        return found
    candidates = sorted(Path.home().glob("texlive/*/bin/*/pdflatex"))
    if candidates:
        return str(candidates[0])
    return None


def _force_remove(func, path, _exc_info):
    """rmtree handler: a leftover scratch tree may still carry read-only modes."""
    os.chmod(os.path.dirname(path), 0o700)
    os.chmod(path, 0o700)
    func(path)


def stage(tree, workdir):
    """Copy the input tree into a writable scratch directory."""
    if workdir.exists():
        shutil.rmtree(workdir, onerror=_force_remove)
    # symlinks=False so the Bazel output tree's symlinks become real files.
    shutil.copytree(tree, workdir, symlinks=False)
    # copytree carries the source modes over, and a Bazel output tree is
    # read-only.  pdflatex has to write its auxiliary files, its log and the
    # PDF into this directory, so every directory needs the write and search
    # bits and every file needs the write bit.
    workdir.chmod(workdir.stat().st_mode | 0o700)
    for path in workdir.rglob("*"):
        extra = 0o700 if path.is_dir() else 0o600
        path.chmod(path.stat().st_mode | extra)


def clean_aux(workdir, jobname):
    for suffix in AUX_SUFFIXES:
        (workdir / (jobname + suffix)).unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tree", required=True,
                        help="Directory holding TRM.tex, include/ and figures/.")
    parser.add_argument("--out", required=True, help="Path to write the PDF to.")
    parser.add_argument("--log", help="Path to write the last pass's build log to.")
    parser.add_argument("--jobname", default="TRM", help="LaTeX job name (default TRM).")
    parser.add_argument("--pdflatex", help="pdflatex to use; default is the Makefile's discovery.")
    parser.add_argument("--workdir", help="Scratch build directory; default is <out>.build.")
    args = parser.parse_args()

    # A `bazel run` lands in a runfiles directory, so relative paths the caller
    # typed on the command line are relative to the workspace, not to here.
    workspace = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if workspace:
        os.chdir(workspace)

    pdflatex = find_pdflatex(args.pdflatex)
    if not pdflatex:
        print("FAIL: pdflatex not found on PATH or in ~/texlive.", file=sys.stderr)
        print("      Try: export PATH=$HOME/texlive/2026/bin/x86_64-linux:$PATH",
              file=sys.stderr)
        return 1

    tree = Path(args.tree).resolve()
    main_tex = tree / (args.jobname + ".tex")
    if not main_tex.is_file():
        print("FAIL: no %s in %s." % (main_tex.name, tree), file=sys.stderr)
        print("      The chip artifacts have not been generated yet.", file=sys.stderr)
        return 1

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    workdir = Path(args.workdir) if args.workdir else Path(str(out) + ".build")
    workdir = workdir.resolve()

    stage(tree, workdir)
    clean_aux(workdir, args.jobname)

    env = dict(os.environ)
    env["SOURCE_DATE_EPOCH"] = SOURCE_DATE_EPOCH
    env["FORCE_SOURCE_DATE"] = "1"

    log_path = workdir / "build.log"
    for index in range(1, PASSES + 1):
        with open(log_path, "wb") as log:
            result = subprocess.run(
                [pdflatex, "-interaction=nonstopmode", main_tex.name],
                cwd=str(workdir), env=env, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode != 0:
            print("FAIL: pdflatex pass %d exited %d. Last lines of the log:"
                  % (index, result.returncode), file=sys.stderr)
            tail = log_path.read_text(errors="replace").splitlines()[-25:]
            for line in tail:
                print("    " + line, file=sys.stderr)
            return 1

    built = workdir / (args.jobname + ".pdf")
    if not built.is_file():
        print("FAIL: pdflatex reported success but wrote no %s." % built.name,
              file=sys.stderr)
        return 1

    shutil.copyfile(built, out)
    if args.log:
        Path(args.log).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(log_path, args.log)

    for line in log_path.read_text(errors="replace").splitlines():
        if line.startswith("Output written"):
            print(line)
            break
    print("OK: %s (SOURCE_DATE_EPOCH=%s, %d passes)" % (out, SOURCE_DATE_EPOCH, PASSES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
