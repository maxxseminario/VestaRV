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
import re
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
    # Agent worktrees, each a full second checkout of this repo. Dropping this
    # one does not cost a slow crawl so much as a WRONG graph: every BUILD file
    # is found twice, "//..." doubles, and targets resolve against a tree that
    # is not the one being edited.
    ".claude",
    # Generated trees inside bazelified areas.
    "docs/publications",
    "verification/isa/build",
    "verification/isa/build_oneoff",
    "verification/isa/negctrl",
    "verification/isa/rcf",
    "opensource_sim/.venv",
)

# ---------------------------------------------------------------------------
# WHAT MAY BE TRACKED UNDER AN IGNORED TREE.
#
# The EDA trees above are ignored by bazel because ~374 GB of what is in them
# is generated output and none of it is a build input. That is still true.
#
# But those same directories are where every hand-written flow script in the
# project lives - the Genus and Innovus run scripts, the signoff Makefile,
# lvs.sh and its lvs_include_* files, the LVS netlist derivations, the OA
# reference-library builders - and until 2026-08-25 none of it was in version
# control at all. .gitignore now tracks that source (222 files, 2.4 MB, out of
# 70,657 files and 374 GB on disk).
#
# So the rule here is NOT "this tree may carry tracked files". It is "this
# tree may carry tracked files THAT MATCH THESE PATTERNS". A blanket
# exemption would retire the leak detector for the tree; a pattern list keeps
# it, and keeps it aimed at exactly the thing it was built to catch - a GDS,
# a report, a database or a netlist arriving under signoff_mp/ or innovus/ by
# way of a wide "git add -f".
#
# Widening a list here is how that protection gets hollowed out, so a diff
# that adds a pattern needs the matching .gitignore negation and a reason.
# "**" means the whole tree is exempt and should be used only where the
# directory is hand-written input throughout.
#
# Patterns are shell globs matched against the workspace-relative path. "*"
# does NOT cross a "/"; "**" does.
# ---------------------------------------------------------------------------
TRACKED_CONTENT_ALLOWED = {
    # The negative-control seed patches: hand-written inputs that happen to
    # live next to generated output. Exempt throughout, as they always were -
    # "**" is the whole-tree form and crosses directory separators.
    "verification/isa/negctrl": ("**",),

    # Synthesis: the top Makefile and the per-block run scripts.
    "genus": (
        "genus/Makefile",
        "genus/*/tcl/*.tcl",
        "genus/*/tcl/*.py",
        "genus/*/*.sh",
        "genus/*/*.py",
    ),

    # Place and route: the common Makefile, the per-block run scripts and
    # netlist-prep shells, and the shared proc library.
    "innovus": (
        "innovus/common/Makefile",
        "innovus/common/*/tcl/*.tcl",
        "innovus/common/*/tcl/*.py",
        "innovus/common/*/*.sh",
        "innovus/common/*/*.py",
        "innovus/common/shared/*.tcl",
        "innovus/myshkin/tcl/*.tcl",
        "innovus/myshkin/tcl/*.sh",
    ),

    # Pegasus DRC/LVS signoff. pvs/ and strmin/ are otherwise pure output;
    # only the hand-written Pegasus control files and the strmin reference
    # library list come out of them. signoff_mp/.gitignore is the second
    # layer of the ignore policy and is tracked for that reason.
    "signoff_mp": (
        "signoff_mp/.gitignore",
        "signoff_mp/Makefile",
        "signoff_mp/*.sh",
        "signoff_mp/*.py",
        "signoff_mp/lvs_include_*",
        "signoff_mp/tcl/*.tcl",
        "signoff_mp/pvs/*_ctl",
        "signoff_mp/pvs/*lvsctl",
        "signoff_mp/strmin/reflib.list",
    ),

    # Common Power Format: one hand-written file, no output at all.
    "cpf": ("cpf/*.cpf",),
}


def _glob_to_regex(pattern):
    """A shell glob where '*' never crosses a '/' but '**' may."""
    out = ["^"]
    i = 0
    while i < len(pattern):
        ch = pattern[i]
        if ch == "*" and pattern[i:i + 2] == "**":
            out.append(".*")
            i += 2
            continue
        if ch == "*":
            out.append("[^/]*")
        elif ch == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(ch))
        i += 1
    out.append("$")
    return re.compile("".join(out))


def allowed_under(tree, rel):
    """True if this tracked path is one the ignored tree may legitimately hold."""
    for pattern in TRACKED_CONTENT_ALLOWED.get(tree, ()):
        if _glob_to_regex(pattern).match(rel):
            return True
    return False


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
    """The paths git tracks beneath one ignored directory."""
    try:
        raw = subprocess.check_output(
            ["git", "ls-files", "-z", "--", entry], cwd=root)
    except (OSError, subprocess.CalledProcessError):
        return []
    return [c.decode("utf-8", "surrogateescape")
            for c in raw.split(b"\0") if c]


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
        allowed_total = 0
        for entry in entries:
            if not os.path.exists(os.path.join(root, entry)):
                continue
            for rel in tracked_under(root, entry):
                if allowed_under(entry, rel):
                    allowed_total += 1
                else:
                    leaks.append((entry, rel))
        if leaks:
            failed = True
            print("FAIL: %d tracked file(s) under an ignored tree are not on"
                  " its allow-list:" % len(leaks))
            for entry, rel in leaks:
                print("  %s (ignored tree: %s)" % (rel, entry))
            print("  Generated EDA output has leaked into version control.")
            print("  git rm --cached the files, or add a pattern to")
            print("  TRACKED_CONTENT_ALLOWED with a reason if this really is")
            print("  hand-written flow source, together with the matching")
            print("  .gitignore negation.")
        checked = ("%d entry(s) checked for tracked content, %d allow-listed "
                   "file(s) accepted" % (len(entries), allowed_total))
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
