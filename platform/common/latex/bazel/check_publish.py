#!/usr/bin/env python3
"""Byte-compare a freshly built TRM.pdf against the published copy.

This is the Bazel port of the `check-publish` target in
platform/common/Makefile.  It answers one question: is the TRM committed
under implementations/asic/<chip>/docs/ the PDF that the current sources
produce, or is it stale?

The comparison is a byte-diff and not a page count or a text diff, and
that is only meaningful because build_trm_pdf.py pins SOURCE_DATE_EPOCH.
Without that pin every rebuild differs in its PDF metadata and the check
degenerates into "was this built today".

Exit 0 means the published TRM is current.  Exit 1 means it is stale and
someone has to rebuild and republish it.
"""

import argparse
import os
import sys
from pathlib import Path


def find_workspace_root():
    """Locate the source workspace, from a test as well as from `bazel run`.

    `bazel run` names it outright.  A test does not, and the published TRM
    lives in a directory that has no BUILD file, so it cannot be a data
    dependency and has to be reached as a source path instead.  This file
    is itself a runfiles symlink back into the source tree, so resolving
    it and walking up to MODULE.bazel finds that tree.
    """
    named = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if named:
        return Path(named)
    for candidate in [Path(__file__).resolve()] + [Path.cwd().resolve()]:
        for parent in candidate.parents:
            if (parent / "MODULE.bazel").is_file():
                return parent
    return None


def resolve(path_text):
    """Resolve a path that may be absolute, cwd-relative, or workspace-relative."""
    path = Path(path_text)
    if path.is_absolute() or path.exists():
        return path
    root = find_workspace_root()
    if root is None:
        return path
    return root / path


def describe(path):
    if not path.is_file():
        return "missing"
    return "%d bytes" % path.stat().st_size


def first_difference(left, right):
    """Return the 1-based offset of the first differing byte, or None."""
    a = left.read_bytes()
    b = right.read_bytes()
    for index, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return index + 1
    if len(a) != len(b):
        return min(len(a), len(b)) + 1
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--built", required=True, help="The freshly built PDF.")
    parser.add_argument("--published", required=True, help="The committed PDF.")
    args = parser.parse_args()

    built = resolve(args.built)
    published = resolve(args.published)

    if not built.is_file():
        print("FAIL: no built TRM at %s." % built, file=sys.stderr)
        return 1
    if not published.is_file():
        print("FAIL: no published TRM at %s." % published, file=sys.stderr)
        print("      Copy the built PDF there to create it.", file=sys.stderr)
        return 1

    offset = first_difference(built, published)
    if offset is None:
        print("OK: the published TRM matches the build (%s)." % describe(built))
        return 0

    print("FAIL: the published TRM is STALE.", file=sys.stderr)
    print("      built     %s  %s" % (built, describe(built)), file=sys.stderr)
    print("      published %s  %s" % (published, describe(published)), file=sys.stderr)
    print("      first differing byte: %d" % offset, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
