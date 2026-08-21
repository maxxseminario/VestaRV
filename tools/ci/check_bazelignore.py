#!/usr/bin/env python3
"""check_bazelignore.py -- keep the EDA output trees out of the bazel graph.

WHY THIS EXISTS.
---------------------------------------------------------------------------
The EDA working trees at the repo root hold roughly 450 GB of generated
output.
.bazelignore is the only thing that stops bazel walking all of it looking for
BUILD files, so deleting a single line there turns every "bazel build //..."
into a multi-minute crawl over signoff and place-and-route dumps, and the
person who deletes it usually sees nothing wrong on their own machine.

So the required set lives HERE, in a constant, rather than being inferred
from whatever .bazelignore happens to say today.
Dropping a guarded directory then means editing this file too, which is a
visible, reviewable act instead of a one-line deletion nobody reads.

Exit codes:  0 = pass.  1 = an entry is missing or output leaked into git.
             2 = the instrument is not live (.bazelignore unreadable).
"""

import argparse
import os
import subprocess
import sys

# ---------------------------------------------------------------------------
# THE REQUIRED SET. Every entry below must be present in .bazelignore.
#
# Block one is the root-level EDA working trees - the ~450 GB the header
# comment in .bazelignore is talking about. Block two is the generated trees
# that sit inside otherwise-bazelified areas.
#
# Removing a name from this list is how the guard gets weakened, so treat any
# diff that shortens it as a change to the build's cost model, not as
# cleanup.
#
# The per-campaign verification/isa/rcf_k?? directories are deliberately NOT
# individually required: they are created and retired as campaigns come and
# go. They are still covered by the tracked-content check below, which walks
# whatever .bazelignore actually lists.
# ---------------------------------------------------------------------------
REQUIRED_ENTRIES = (
    # Root-level EDA working trees.
    "signoff_mp",
    "xcelium",
    "xcelium.d",
    "innovus",
    "genus",
    "std_cells",
    "cpf",
    "hardware",
    "ic_bad",
    "logo",
    ".cadence",
    ".devlog",
    # Generated trees inside bazelified areas.
    "docs/publications",
    "verification/isa/build",
    "verification/isa/build_oneoff",
    "verification/isa/negctrl",
    "verification/isa/rcf",
    "opensource_sim/.venv",
)

# ---------------------------------------------------------------------------
# Ignored directories that legitimately DO carry tracked files.
#
# verification/isa/negctrl holds the negative-control seed patches. They are
# hand-written inputs that happen to live next to generated output, so they
# are tracked on purpose and must not be reported as an EDA leak.
# ---------------------------------------------------------------------------
TRACKED_CONTENT_EXPECTED = frozenset([
    "verification/isa/negctrl",
])


class ToolError(Exception):
    """The instrument could not run - exit 2, never a quiet pass."""


def default_root():
    """The repo root, inferred from this script living at tools/ci/."""
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(here))


def read_bazelignore(root):
    """The directory entries .bazelignore currently lists, in file order."""
    path = os.path.join(root, ".bazelignore")
    try:
        handle = open(path, "r")
    except (IOError, OSError) as exc:
        raise ToolError("cannot read %s: %s" % (path, exc))
    try:
        lines = handle.read().splitlines()
    finally:
        handle.close()
    entries = []
    for line in lines:
        text = line.strip()
        if not text or text.startswith("#"):
            continue
        entries.append(text.rstrip("/"))
    return entries


def git_available(root):
    """True if git can answer questions about this tree."""
    try:
        with open(os.devnull, "wb") as sink:
            subprocess.check_call(["git", "rev-parse", "--git-dir"],
                                  cwd=root, stdout=sink, stderr=sink)
    except (OSError, subprocess.CalledProcessError):
        return False
    return True


def tracked_under(root, entry):
    """How many files git tracks beneath one ignored directory."""
    try:
        raw = subprocess.check_output(
            ["git", "ls-files", "-z", "--", entry], cwd=root)
    except (OSError, subprocess.CalledProcessError):
        return 0
    return len([c for c in raw.split(b"\0") if c])


def main(argv):
    parser = argparse.ArgumentParser(
        description="Assert .bazelignore still guards the EDA output trees.")
    parser.add_argument("--root", default=None,
                        help="repo root (default: inferred from this script)")
    parser.add_argument("--no-git", action="store_true", dest="no_git",
                        help="skip the tracked-content check outright. The "
                             "bazel test passes this: its sandbox stages "
                             ".bazelignore but no .git, and an ambient git "
                             "answering about some other tree would be worse "
                             "than not asking.")
    args = parser.parse_args(argv)

    root = args.root or default_root()
    try:
        entries = read_bazelignore(root)
    except ToolError as exc:
        sys.stderr.write("ERROR: %s\n" % exc)
        return 2

    if not entries:
        sys.stderr.write(
            "ERROR: .bazelignore parsed to zero entries. That is an\n"
            "instrument failure, not a pass.\n")
        return 2

    present = set(entries)
    failed = False

    missing = [e for e in REQUIRED_ENTRIES if e not in present]
    if missing:
        failed = True
        print("FAIL: %d required .bazelignore entry(s) are gone:" % len(missing))
        for entry in missing:
            print("  %s" % entry)
        print("  Without them bazel crawls the EDA output trees on every")
        print("  invocation. Restore the lines, or - if the removal really is")
        print("  intended - remove the name from REQUIRED_ENTRIES in")
        print("  tools/ci/check_bazelignore.py in the same commit.")

    if args.no_git:
        print("NOTE: --no-git, skipping the tracked-content check.")
        checked = "tracked-content check skipped (--no-git)"
    elif git_available(root):
        leaks = []
        for entry in entries:
            if entry in TRACKED_CONTENT_EXPECTED:
                continue
            if not os.path.exists(os.path.join(root, entry)):
                continue
            count = tracked_under(root, entry)
            if count:
                leaks.append((entry, count))
        if leaks:
            failed = True
            print("FAIL: %d ignored tree(s) carry tracked files:" % len(leaks))
            for entry, count in leaks:
                print("  %s (%d tracked file(s))" % (entry, count))
            print("  Generated EDA output has leaked into version control.")
            print("  git rm --cached the files, or add the directory to")
            print("  TRACKED_CONTENT_EXPECTED with a reason if it is genuine")
            print("  hand-written input.")
        checked = "%d entry(s) checked for tracked content" % len(entries)
    else:
        print("NOTE: git is unavailable, skipping the tracked-content check.")
        checked = "tracked-content check skipped (no git)"

    if failed:
        return 1

    print("OK: .bazelignore carries all %d required entries; %s."
          % (len(REQUIRED_ENTRIES), checked))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
