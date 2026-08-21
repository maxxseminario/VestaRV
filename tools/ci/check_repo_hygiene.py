#!/usr/bin/env python3
"""check_repo_hygiene.py -- catch EDA and build output leaking into git.

WHY THIS EXISTS.
---------------------------------------------------------------------------
The generated trees in this repo are enormous and the tooling writes into the
source tree, so a wide "git add" is all it takes to commit a place-and-route
dump or a firmware image.
Once such a file is in history it is there for good, and the clone gets
slower for everyone forever.

Three things are policed:

  1. *.rcf firmware images. They are globally gitignored on purpose; what
     pins the firmware for review is the tracked testdata/*_golden.txt, not
     the binary. .gitignore carries exactly one documented negation of that
     rule, and this check carries the same one - see RCF_BLESSED_DIR below.
  2. Oversized files. The ceiling is not a style rule - it is the line past
     which a file is almost certainly generated output rather than source.
  3. Files under a .bazelignore'd EDA tree. Those directories are ignored by
     bazel precisely because nothing in them is an input, so nothing in them
     should be tracked either.

With --base the check looks only at what the branch added or modified, which
is what a pull request wants. With no --base it grades the whole tree.

Exit codes:  0 = pass.  1 = something unwanted is tracked.  2 = the
instrument is not live (git missing or failing).
"""

import argparse
import os
import subprocess
import sys

# ---------------------------------------------------------------------------
# THE SIZE CEILING.
#
# 16 MiB, chosen by measurement rather than taste: the largest tracked file at
# the time this check was written is platform/.../myshkin_layout.png at
# 11.9 MiB (three copies of it), with implementations/asic/myshkin-2025-11/
# docs/TRM.pdf next at 10.0 MiB.
#
# The ceiling sits above those so HEAD passes honestly, and well below the
# size of anything the EDA flows emit, which is what it is really aimed at.
# Lowering it is a decision about those existing files and belongs in a
# commit that deals with them.
# ---------------------------------------------------------------------------
DEFAULT_MAX_BYTES = 16 * 1024 * 1024

# ---------------------------------------------------------------------------
# THE ONE BLESSED *.rcf LOCATION.
#
# .gitignore excludes *.rcf globally and then negates it for exactly one
# directory, with the reason written out at the negation:
#
#     !tools/cosim/gate/*.rcf
#
# That file is the canonical boot ROM image both sides of the COSIM_BOOT
# lockstep execute, so a silent change to it is a silent change to the pinned
# gate numbers, and tracking it is the point.
#
# This constant must stay in step with that negation. Widening it is how the
# .rcf rule gets hollowed out, so a diff that adds a directory here needs the
# matching .gitignore negation and a reason next to it.
# ---------------------------------------------------------------------------
RCF_BLESSED_DIR = "tools/cosim/gate"

# Ignored directories that legitimately carry tracked files. Kept in step
# with TRACKED_CONTENT_EXPECTED in tools/ci/check_bazelignore.py; the
# negative-control seed patches under verification/isa/negctrl are
# hand-written inputs sitting next to generated output.
TRACKED_CONTENT_EXPECTED = frozenset([
    "verification/isa/negctrl",
])


class ToolError(Exception):
    """The instrument could not run - exit 2, never a quiet pass."""


def default_root():
    """The repo root, inferred from this script living at tools/ci/."""
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(here))


def run_git(root, argv):
    """One git call, NUL-separated output, decoded to a list of paths."""
    try:
        raw = subprocess.check_output(["git"] + argv, cwd=root)
    except OSError as exc:
        raise ToolError("cannot run git: %s" % exc)
    except subprocess.CalledProcessError as exc:
        raise ToolError("git %s failed with status %d"
                        % (" ".join(argv), exc.returncode))
    return [c.decode("utf-8", "surrogateescape")
            for c in raw.split(b"\0") if c]


def inspected_paths(root, base):
    """The tracked paths this run grades."""
    if base is None:
        return run_git(root, ["ls-files", "-z"])
    changed = run_git(root, ["diff", "--name-only", "-z",
                             "--diff-filter=AM", "%s...HEAD" % base])
    # A path can be added on the branch and removed again by a later commit
    # in a merge, so intersect with what is actually tracked now.
    tracked = set(run_git(root, ["ls-files", "-z"]))
    return [p for p in changed if p in tracked]


def ignored_trees(root):
    """The .bazelignore directories that must hold nothing tracked."""
    path = os.path.join(root, ".bazelignore")
    try:
        handle = open(path, "r")
    except (IOError, OSError) as exc:
        raise ToolError("cannot read %s: %s" % (path, exc))
    try:
        lines = handle.read().splitlines()
    finally:
        handle.close()
    trees = []
    for line in lines:
        text = line.strip().rstrip("/")
        if not text or text.startswith("#"):
            continue
        if text in TRACKED_CONTENT_EXPECTED:
            continue
        trees.append(text)
    return trees


def under(path, tree):
    """True if a workspace-relative path sits inside an ignored tree."""
    return path == tree or path.startswith(tree + "/")


def main(argv):
    parser = argparse.ArgumentParser(
        description="Fail if EDA or build output is tracked by git.")
    parser.add_argument("--root", default=None,
                        help="repo root (default: inferred from this script)")
    parser.add_argument("--base", default=None,
                        help="grade only what changed since this revision")
    parser.add_argument("--max-bytes", type=int, default=DEFAULT_MAX_BYTES,
                        help="size ceiling in bytes (default: %d)"
                             % DEFAULT_MAX_BYTES)
    args = parser.parse_args(argv)

    root = args.root or default_root()
    try:
        paths = inspected_paths(root, args.base)
        trees = ignored_trees(root)
    except ToolError as exc:
        sys.stderr.write("ERROR: %s\n" % exc)
        return 2

    if args.base is None and not paths:
        sys.stderr.write(
            "ERROR: git tracks zero files. That is an instrument failure,\n"
            "not a pass.\n")
        return 2

    rcf = []
    oversize = []
    in_ignored = []

    for rel in paths:
        if rel.endswith(".rcf") and os.path.dirname(rel) != RCF_BLESSED_DIR:
            rcf.append(rel)
        for tree in trees:
            if under(rel, tree):
                in_ignored.append((rel, tree))
                break
        abspath = os.path.join(root, rel)
        try:
            size = os.path.getsize(abspath)
        except (IOError, OSError):
            # Not in the worktree (sparse checkout); nothing to weigh.
            continue
        if size > args.max_bytes:
            oversize.append((rel, size))

    failed = False

    if rcf:
        failed = True
        print("FAIL: %d *.rcf firmware image(s) are tracked:" % len(rcf))
        for rel in rcf:
            print("  %s" % rel)
        print("  .rcf files are globally gitignored on purpose. The firmware")
        print("  is pinned for review by the tracked testdata/*_golden.txt")
        print("  instead, and %s/ is the only blessed" % RCF_BLESSED_DIR)
        print("  exception. git rm --cached them.")

    if oversize:
        failed = True
        print("FAIL: %d tracked file(s) exceed the %d byte ceiling:"
              % (len(oversize), args.max_bytes))
        for rel, size in sorted(oversize, key=lambda pair: -pair[1]):
            print("  %s (%.2f MiB)" % (rel, size / (1024.0 * 1024.0)))
        print("  A file this large is almost always generated output. If it")
        print("  really is source, raise DEFAULT_MAX_BYTES in")
        print("  tools/ci/check_repo_hygiene.py and say why.")

    if in_ignored:
        failed = True
        print("FAIL: %d tracked file(s) live under a .bazelignore'd tree:"
              % len(in_ignored))
        for rel, tree in in_ignored:
            print("  %s (ignored tree: %s)" % (rel, tree))
        print("  Those directories are ignored because nothing in them is a")
        print("  build input, so nothing in them should be tracked.")

    if failed:
        return 1

    scope = "whole tree" if args.base is None else "changes since %s" % args.base
    print("OK: %d tracked file(s) inspected (%s) - no stray .rcf, none over "
          "%d bytes, none under an ignored EDA tree."
          % (len(paths), scope, args.max_bytes))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
