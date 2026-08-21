#!/usr/bin/env python3
"""Read the rendered TRM text back and look for LaTeX that leaked through.

This is the Bazel port of the `trm-lint` target in platform/common/Makefile.

pdflatex exits 0 on the two defects this catches.  A mangled command such
as a line break landing between the backslash and the name compiles
cleanly and ships the letters "texttt" as body text; an unresolved cross
reference renders as "??".  Neither appears in the build log, so the
built PDF is the only place either can be seen.

Unlike the Makefile, a missing pdftotext is a FAILURE here rather than a
skip.  The Makefile has to degrade gracefully on a developer box that has
TeX but no poppler; a Bazel test that silently passes when its tool is
absent is a test that reports green for having done nothing.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# Literal strings that must never appear in the rendered text.
# Everything before the last entry is a LaTeX command that leaked; "??" is
# how LaTeX renders a cross-reference it could not resolve.
BAD_PATTERNS = (
    "texttt",
    "SI{",
    "ref{",
    "begin{",
    "end{",
    "mathrm{",
    "emph{",
    "??",
)

MAX_HITS_SHOWN = 3


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pdf", required=True, help="The built TRM.pdf.")
    parser.add_argument("--pdftotext", default="/usr/bin/pdftotext",
                        help="pdftotext to use (default /usr/bin/pdftotext).")
    args = parser.parse_args()

    workspace = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if workspace:
        os.chdir(workspace)

    pdf = Path(args.pdf)
    if not pdf.is_file():
        print("FAIL: no PDF at %s." % pdf, file=sys.stderr)
        return 1

    pdftotext = args.pdftotext
    if not Path(pdftotext).is_file():
        pdftotext = shutil.which("pdftotext")
    if not pdftotext:
        print("FAIL: pdftotext not found, so the rendered text cannot be read back.",
              file=sys.stderr)
        print("      This test is tagged local for exactly that reason: it needs "
              "the host's poppler.", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory() as scratch:
        text_path = Path(scratch) / "trm.txt"
        result = subprocess.run(
            [pdftotext, "-layout", str(pdf), str(text_path)],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if result.returncode != 0:
            print("FAIL: pdftotext exited %d." % result.returncode, file=sys.stderr)
            print(result.stdout.decode(errors="replace"), file=sys.stderr)
            return 1
        lines = text_path.read_text(errors="replace").splitlines()

    bad = False
    for pattern in BAD_PATTERNS:
        hits = [(number, line) for number, line in enumerate(lines, 1)
                if pattern in line]
        if not hits:
            continue
        bad = True
        print("FAIL: literal %r rendered in the PDF:" % pattern, file=sys.stderr)
        for number, line in hits[:MAX_HITS_SHOWN]:
            print("    %d: %s" % (number, line.strip()[:160]), file=sys.stderr)
        if len(hits) > MAX_HITS_SHOWN:
            print("    ... and %d more" % (len(hits) - MAX_HITS_SHOWN), file=sys.stderr)

    if bad:
        print("      A LaTeX command leaked through as text, or a cross-reference "
              "is unresolved.", file=sys.stderr)
        return 1

    print("OK: TRM text lint clean over %d lines (no leaked LaTeX, no unresolved "
          "references)." % len(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
