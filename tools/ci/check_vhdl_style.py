#!/usr/bin/env python3
"""check_vhdl_style.py -- the house VHDL prose style gate.

WHY THIS EXISTS.
---------------------------------------------------------------------------
This repo's VHDL comment style is binding, and its first rule is ASCII only.
Em-dashes, unicode arrows, smart quotes and non-breaking spaces get pasted in
from notes and web pages without anyone noticing, and they survive review
because they render as something plausible.
Downstream they are not harmless: the vendor VHDL readers, the LaTeX TRM
pipeline and the diff tooling all treat a stray multi-byte character
differently, and a non-breaking space that looks exactly like a space is a
genuinely nasty thing to debug.

So this check is deliberately blunt.
Any byte in a VHDL file that is not printable 7-bit ASCII, tab, CR or LF is a
failure, reported with its path, line, column, codepoint and unicode name so
the offending character can be found and typed out in words instead.

WHAT IS OUT OF SCOPE, AND WHY.
---------------------------------------------------------------------------
The rule binds on the trees the owner actually edits. Frozen tape-out
snapshots and vendored gate netlists are not editable by the people this gate
catches, so grading them would only produce a red that nobody is allowed to
fix. EXCLUDED_TREES below names each one with its reason; --all scans them
anyway when someone wants the full picture.

Exit codes:  0 = pass.  1 = a banned character was found.  2 = the instrument
is not live (git missing, unreadable file, or an empty scan).
"""

import argparse
import os
import subprocess
import sys
import unicodedata

# Printable 7-bit ASCII, plus the three whitespace bytes VHDL sources may
# legitimately carry.
# CR is allowed because much of this repo's VHDL is stored CRLF on purpose;
# see tools/ci/check_line_endings.py.
ALLOWED_CONTROL = ("\t", "\n", "\r")

# ---------------------------------------------------------------------------
# TREES THIS GATE DOES NOT GRADE.
#
# Each entry is an ADJUDICATED exclusion, not a swept-under-the-rug one: the
# files in it carry banned characters today AND nobody working in this repo is
# permitted to edit them, so grading them would produce a permanent red with
# no legal repair. The reason is on the line, so a future reader can tell the
# two cases apart.
#
# Un-freezing a tree means DELETING its line here, in the same commit that
# un-freezes it, and fixing whatever the gate then reports.
#
# NOT excluded, deliberately:
#   hdl/common/    the live shared RTL, where the ASCII rule is binding, and
#                  which is clean today - this is the tree the gate is for.
#   hdl/castalia/  absent from the frozen-trees table in CONTRIBUTING.md, so
#                  it is live and stays graded. It is clean today.
# ---------------------------------------------------------------------------
EXCLUDED_TREES = (
    # FROZEN - do not touch, per the frozen-trees table in CONTRIBUTING.md.
    # Single-core Myshkin tape-out RTL.
    "hdl/myshkin/",
    # Frozen snapshot, per the same table. 18-hart Argus RTL, regenerable
    # from config/argus.json rather than hand-edited.
    "hdl/argus/",
    # Vendored and generated gate netlists. Synthesis and P&R write these;
    # they are tool output checked in as a record, not hand-written source.
    "tools/cosim/gate/",
)


class ToolError(Exception):
    """The instrument could not run - exit 2, never a quiet pass."""


def default_root():
    """The repo root, inferred from this script living at tools/ci/."""
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(here))


def discover(root):
    """Every tracked VHDL source, workspace-relative."""
    try:
        raw = subprocess.check_output(
            ["git", "ls-files", "-z", "*.vhd", "*.vhdl"], cwd=root)
    except OSError as exc:
        raise ToolError("cannot run git: %s" % exc)
    except subprocess.CalledProcessError as exc:
        raise ToolError("git ls-files failed with status %d" % exc.returncode)
    out = []
    for chunk in raw.split(b"\0"):
        if chunk:
            out.append(os.path.join(root, chunk.decode("utf-8", "surrogateescape")))
    return out


def is_excluded(path):
    """True if a path falls inside a tree this gate does not grade.

    Matches on the workspace-relative tail, so the same rule holds whether the
    caller passed a repo-relative path, an absolute worktree path, or a
    runfiles path from inside a bazel sandbox.
    """
    norm = path.replace(os.sep, "/")
    for tree in EXCLUDED_TREES:
        if norm.startswith(tree) or ("/" + tree) in norm:
            return True
    return False


def describe(char):
    """Codepoint and unicode name for one offending character."""
    point = ord(char)
    if 0xDC80 <= point <= 0xDCFF:
        # surrogateescape's stand-in for a byte that is not valid UTF-8.
        return "raw byte 0x%02X (not valid UTF-8)" % (point - 0xDC00)
    try:
        name = unicodedata.name(char)
    except ValueError:
        name = "no unicode name"
    return "U+%04X %s" % (point, name)


def read_manifest(path):
    """The file list a --files-from manifest names, one path per line."""
    try:
        handle = open(path, "r")
    except (IOError, OSError) as exc:
        raise ToolError("cannot read manifest %s: %s" % (path, exc))
    try:
        lines = handle.read().splitlines()
    finally:
        handle.close()
    out = []
    for line in lines:
        text = line.strip()
        if text and not text.startswith("#"):
            out.append(text)
    return out


def scan_file(path):
    """Every banned character in one file, as (line, col, char) triples."""
    try:
        handle = open(path, "rb")
    except (IOError, OSError) as exc:
        raise ToolError("cannot read %s: %s" % (path, exc))
    try:
        data = handle.read()
    finally:
        handle.close()

    # surrogateescape keeps invalid bytes addressable instead of replacing
    # them, so a latin-1 em-dash is reported as the byte it really is.
    text = data.decode("utf-8", "surrogateescape")

    findings = []
    line_no = 1
    col_no = 1
    for char in text:
        if char == "\n":
            line_no += 1
            col_no = 1
            continue
        if char in ALLOWED_CONTROL or " " <= char <= "~":
            col_no += 1
            continue
        findings.append((line_no, col_no, char))
        col_no += 1
    return findings


def main(argv):
    parser = argparse.ArgumentParser(
        description="Fail on any non-ASCII character in a VHDL source.")
    parser.add_argument("files", nargs="*",
                        help="VHDL files to scan (default: every tracked one)")
    parser.add_argument("--root", default=None,
                        help="repo root for discovery (default: inferred)")
    parser.add_argument("--files-from", default=None, dest="files_from",
                        help="read the file list from this manifest, one path "
                             "per line. This is the STRICT mode: an unreadable "
                             "manifest is exit 2, never a quietly empty scan.")
    parser.add_argument("--all", action="store_true", dest="scan_all",
                        help="also scan the frozen and vendored trees listed "
                             "in EXCLUDED_TREES, for the full picture")
    args = parser.parse_args(argv)

    try:
        if args.files_from:
            paths = read_manifest(args.files_from)
            discovered = False
        elif args.files:
            paths = list(args.files)
            discovered = False
        else:
            paths = discover(args.root or default_root())
            discovered = True

        if not paths:
            sys.stderr.write(
                "ERROR: nothing to scan. An empty file set is an instrument\n"
                "failure, not a pass - check the tree is staged correctly.\n")
            return 2

        if args.scan_all:
            excluded = 0
        else:
            kept = [p for p in paths if not is_excluded(p)]
            excluded = len(paths) - len(kept)
            paths = kept

        # A gate that has excluded its way down to nothing is not a passing
        # gate, it is a dead one. Say so rather than printing OK.
        if not paths:
            sys.stderr.write(
                "ERROR: every one of the %d candidate file(s) was excluded.\n"
                "The gate has shrunk to nothing - check EXCLUDED_TREES.\n"
                % excluded)
            return 2

        total = 0
        bad_files = 0
        for path in paths:
            findings = scan_file(path)
            total += len(findings)
            if findings:
                bad_files += 1
                for line_no, col_no, char in findings:
                    print("%s:%d:%d: banned non-ASCII character %s"
                          % (path, line_no, col_no, describe(char)))
    except ToolError as exc:
        sys.stderr.write("ERROR: %s\n" % exc)
        return 2

    if total:
        print("")
        print("FAIL: %d banned character(s) in %d of %d VHDL file(s) scanned"
              " (%d excluded)."
              % (total, bad_files, len(paths), excluded))
        print("This repo's VHDL is ASCII only. Write \" - \" instead of an")
        print("em-dash, \"->\" instead of an arrow, and plain quotes.")
        return 1

    if args.scan_all:
        scope = "nothing excluded (--all)"
    else:
        scope = ("%d excluded as frozen snapshot or vendored netlist"
                 % excluded)
    print("OK: %d VHDL file(s) scanned, all pure ASCII; %s%s."
          % (len(paths), scope,
             "; discovered via git" if discovered else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
