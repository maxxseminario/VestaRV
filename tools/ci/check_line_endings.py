#!/usr/bin/env python3
"""check_line_endings.py -- the CRLF preservation gate.

WHY THIS EXISTS.
---------------------------------------------------------------------------
Much of this repo's VHDL is stored with CRLF line endings, and that is
load-bearing rather than accidental.
A script that rewrites such a file in text mode silently strips every CR,
which turns a one-line change into a whole-file diff and has burned this
project before.
Review does not catch it, because the diff looks like a reformat and the
build still passes.

This gate makes the regression unmergeable.
tools/ci/crlf_manifest.txt names every file that is CRLF today, and any
listed file that stops being CRLF-only - or that disappears without the
manifest being regenerated in the same commit - fails the check.

THE THREE GATES.
---------------------------------------------------------------------------
  A  Every manifest entry still classifies as crlf-only, and still exists.
  B  No file classifies as MIXED unless it is in the mixed allowlist.
  C  Advisory only: how many crlf-only files are NOT in the manifest, so the
     manifest can be kept current without this gate blocking on it.

Exit codes:  0 = pass.  1 = a gate failed.  2 = the instrument is not live
(git missing, manifest unreadable, tree unreadable).
"""

import argparse
import os
import subprocess
import sys

CRLF_MANIFEST = "tools/ci/crlf_manifest.txt"
MIXED_ALLOWLIST = "tools/ci/mixed_endings_allowlist.txt"

# A file whose first this-many bytes contain a NUL is treated as binary and
# never classified.
BINARY_SNIFF_BYTES = 8192

CRLF = "crlf-only"
LF = "lf-only"
MIXED = "mixed"

CRLF_MANIFEST_HEADER = """\
# tools/ci/crlf_manifest.txt -- the files that MUST stay CRLF.
#
# Every path below is stored with CRLF line endings and is required to stay
# that way.
# tools/ci/check_line_endings.py fails if any of them becomes LF-only or
# mixed, or if any of them vanishes while this list still names it.
#
# Regenerating this file is a DELIBERATE ACT.
# Run "python3 tools/ci/check_line_endings.py --update" and commit the result
# in the SAME commit as the change it blesses, so the review sees the
# blessing next to the thing being blessed.
# A regeneration on its own, in its own commit, is how the protection gets
# quietly dropped.
"""

MIXED_ALLOWLIST_HEADER = """\
# tools/ci/mixed_endings_allowlist.txt -- files allowed to mix CRLF and LF.
#
# A file that mixes both endings is normally a mistake, so
# tools/ci/check_line_endings.py fails on any mixed file that is not listed
# here.
# The entries below are the ones that are mixed on purpose (generated
# patches and vendored sources whose bytes must not be touched).
#
# Regenerating this file is a DELIBERATE ACT.
# Run "python3 tools/ci/check_line_endings.py --update" and commit the result
# in the SAME commit as the change it blesses.
"""


class ToolError(Exception):
    """The instrument could not run - exit 2, never a quiet pass."""


def default_root():
    """The repo root, inferred from this script living at tools/ci/."""
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(here))


def tracked_files(root):
    """Every path git tracks, workspace-relative, in git's own order."""
    try:
        raw = subprocess.check_output(["git", "ls-files", "-z"], cwd=root)
    except OSError as exc:
        raise ToolError("cannot run git: %s" % exc)
    except subprocess.CalledProcessError as exc:
        raise ToolError("git ls-files failed with status %d" % exc.returncode)
    out = []
    for chunk in raw.split(b"\0"):
        if chunk:
            out.append(chunk.decode("utf-8", "surrogateescape"))
    return out


def classify(abspath):
    """crlf-only / lf-only / mixed, or None for binary or newline-free."""
    try:
        handle = open(abspath, "rb")
    except (IOError, OSError):
        return None
    try:
        data = handle.read()
    finally:
        handle.close()
    if b"\0" in data[:BINARY_SNIFF_BYTES]:
        return None
    total_lf = data.count(b"\n")
    if total_lf == 0:
        return None
    crlf_pairs = data.count(b"\r\n")
    if crlf_pairs == 0:
        return LF
    if crlf_pairs == total_lf:
        return CRLF
    return MIXED


def scan(root):
    """Map every classifiable tracked path to its newline style."""
    styles = {}
    present = set()
    for rel in tracked_files(root):
        abspath = os.path.join(root, rel)
        if not os.path.isfile(abspath):
            # Absent from the worktree (sparse checkout, unmerged path).
            continue
        present.add(rel)
        style = classify(abspath)
        if style is not None:
            styles[rel] = style
    return styles, present


def read_list(root, rel, what):
    """The non-comment entries of a manifest, in file order."""
    path = os.path.join(root, rel)
    try:
        handle = open(path, "r")
    except (IOError, OSError) as exc:
        raise ToolError(
            "cannot read %s (%s): %s\n"
            "Run: python3 tools/ci/check_line_endings.py --update"
            % (what, rel, exc))
    try:
        lines = handle.read().splitlines()
    finally:
        handle.close()
    entries = []
    for line in lines:
        text = line.strip()
        if not text or text.startswith("#"):
            continue
        entries.append(text)
    return entries


def write_list(root, rel, header, entries):
    """Write a manifest: header comment, then sorted paths, LF-terminated."""
    path = os.path.join(root, rel)
    directory = os.path.dirname(path)
    if directory and not os.path.isdir(directory):
        os.makedirs(directory)
    handle = open(path, "wb")
    try:
        handle.write(header.encode("utf-8"))
        for entry in entries:
            handle.write(entry.encode("utf-8", "surrogateescape"))
            handle.write(b"\n")
    finally:
        handle.close()


def report_delta(rel, old, new):
    """Print what an --update moved, so the diff is never a surprise."""
    old_set = set(old)
    new_set = set(new)
    added = sorted(new_set - old_set)
    removed = sorted(old_set - new_set)
    print("%s: %d entries (was %d)" % (rel, len(new), len(old)))
    for entry in added:
        print("  + %s" % entry)
    for entry in removed:
        print("  - %s" % entry)
    if not added and not removed:
        print("  (unchanged)")


def do_update(root, styles):
    crlf_now = sorted(p for p in styles if styles[p] == CRLF)
    mixed_now = sorted(p for p in styles if styles[p] == MIXED)

    try:
        old_crlf = read_list(root, CRLF_MANIFEST, "CRLF manifest")
    except ToolError:
        old_crlf = []
    try:
        old_mixed = read_list(root, MIXED_ALLOWLIST, "mixed allowlist")
    except ToolError:
        old_mixed = []

    write_list(root, CRLF_MANIFEST, CRLF_MANIFEST_HEADER, crlf_now)
    write_list(root, MIXED_ALLOWLIST, MIXED_ALLOWLIST_HEADER, mixed_now)

    report_delta(CRLF_MANIFEST, old_crlf, crlf_now)
    report_delta(MIXED_ALLOWLIST, old_mixed, mixed_now)
    print("")
    print("Both manifests regenerated. Commit them WITH the change they bless.")
    return 0


def do_check(root, styles, present):
    manifest = read_list(root, CRLF_MANIFEST, "CRLF manifest")
    allowlist = set(read_list(root, MIXED_ALLOWLIST, "mixed allowlist"))

    failures = []

    # Gate A: the manifest is still true.
    gone = []
    demoted = []
    for entry in manifest:
        if entry not in present:
            gone.append(entry)
        elif styles.get(entry) != CRLF:
            demoted.append((entry, styles.get(entry) or "unclassified (binary or no newlines)"))

    if demoted:
        failures.append(True)
        print("FAIL: %d manifest file(s) are no longer CRLF-only:" % len(demoted))
        for entry, style in demoted:
            print("  %s is now %s" % (entry, style))
        print("  A text-mode edit most likely stripped the CR bytes.")
        print("  Restore the CRLF endings; do NOT regenerate the manifest to hide this.")

    if gone:
        failures.append(True)
        print("FAIL: %d manifest file(s) no longer exist:" % len(gone))
        for entry in gone:
            print("  %s" % entry)
        print("  If the deletion or rename is intended, regenerate the manifest")
        print("  in the SAME commit: python3 tools/ci/check_line_endings.py --update")

    # Gate B: no unblessed mixed-ending file.
    stray_mixed = sorted(p for p in styles
                         if styles[p] == MIXED and p not in allowlist)
    if stray_mixed:
        failures.append(True)
        print("FAIL: %d file(s) mix CRLF and LF and are not allowlisted:"
              % len(stray_mixed))
        for entry in stray_mixed:
            print("  %s" % entry)
        print("  Normalise the file, or add it to %s via --update." % MIXED_ALLOWLIST)

    # Gate C: advisory drift count, never a failure.
    unlisted = sorted(p for p in styles
                      if styles[p] == CRLF and p not in set(manifest))
    if unlisted:
        print("NOTE: %d crlf-only file(s) are not in the manifest (advisory)."
              % len(unlisted))
        for entry in unlisted[:20]:
            print("  %s" % entry)
        if len(unlisted) > 20:
            print("  ... and %d more" % (len(unlisted) - 20))
        print("  Run --update to bring the manifest current when convenient.")

    if failures:
        return 1

    counts = {CRLF: 0, LF: 0, MIXED: 0}
    for style in styles.values():
        counts[style] += 1
    print("OK: line endings intact - %d crlf-only (%d pinned by manifest), "
          "%d lf-only, %d mixed (all allowlisted)."
          % (counts[CRLF], len(manifest), counts[LF], counts[MIXED]))
    return 0


def main(argv):
    parser = argparse.ArgumentParser(
        description="Guard the CRLF line endings this repo depends on.")
    parser.add_argument("--root", default=None,
                        help="repo root (default: inferred from this script)")
    parser.add_argument("--update", action="store_true",
                        help="regenerate both manifests from the current tree")
    args = parser.parse_args(argv)

    root = args.root or default_root()
    if not os.path.isdir(root):
        sys.stderr.write("ERROR: --root %s is not a directory\n" % root)
        return 2

    try:
        styles, present = scan(root)
        if args.update:
            return do_update(root, styles)
        return do_check(root, styles, present)
    except ToolError as exc:
        sys.stderr.write("ERROR: %s\n" % exc)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
