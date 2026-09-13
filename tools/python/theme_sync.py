#!/usr/bin/env python3
# coding: utf-8
"""VestaRV: splice docs/vesta_theme.css into the pages that adopt it.

Replaces only the lines strictly between a page's two marker lines, so splicing twice gives
the identical file; markers, surrounding text and line endings survive byte for byte. A
marker is a line whose stripped text is exactly the marker, never a substring, and a page
with no markers is not discovered. Exit 0 in sync, 1 stale, 2 an input or marker is missing.
"""

from __future__ import print_function

import argparse
import io
import os
import sys

BEGIN = "/* VESTA_THEME_BEGIN */"
END = "/* VESTA_THEME_END */"

_HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(_HERE))
DEF_CSS = os.path.join(REPO_ROOT, "docs", "vesta_theme.css")
DEF_DOCS = os.path.join(REPO_ROOT, "docs")


class ThemeError(Exception):
    """An input is missing or its markers are unusable. Always exit 2."""


def read_lines(path):
    """Return the file as a list of lines with their own endings intact."""
    try:
        with io.open(path, "r", encoding="utf-8", newline="") as fh:
            return fh.read().splitlines(True)
    except Exception as exc:
        raise ThemeError("cannot read " + path + ": " + str(exc))


def marker_span(lines, path):
    """Return (begin_index, end_index) of the two marker lines."""
    begins = [i for i, ln in enumerate(lines) if ln.strip() == BEGIN]
    ends = [i for i, ln in enumerate(lines) if ln.strip() == END]
    if len(begins) != 1:
        raise ThemeError("%s has %d '%s' marker line(s), need exactly 1"
                         % (path, len(begins), BEGIN))
    if len(ends) != 1:
        raise ThemeError("%s has %d '%s' marker line(s), need exactly 1"
                         % (path, len(ends), END))
    if ends[0] <= begins[0]:
        raise ThemeError("%s has its END marker at or before its BEGIN marker"
                         % path)
    return begins[0], ends[0]


def canonical_block(css_path):
    """The lines strictly between the markers in vesta_theme.css."""
    lines = read_lines(css_path)
    b, e = marker_span(lines, css_path)
    return lines[b + 1:e]


def discover(docs_dir):
    """Every docs/*.html carrying both marker lines, sorted."""
    if not os.path.isdir(docs_dir):
        raise ThemeError("no docs directory at " + docs_dir)
    found = []
    for name in sorted(os.listdir(docs_dir)):
        if not name.lower().endswith(".html"):
            continue
        path = os.path.join(docs_dir, name)
        lines = read_lines(path)
        has_begin = any(ln.strip() == BEGIN for ln in lines)
        has_end = any(ln.strip() == END for ln in lines)
        if has_begin and has_end:
            found.append(path)
    return found


def normalise(block):
    """Compare content without being tripped by CRLF vs LF alone."""
    return [ln.replace("\r\n", "\n").replace("\r", "\n") for ln in block]


def splice(page_path, block, check_only):
    """Return (status, detail). status is 'ok', 'stale' or 'written'."""
    lines = read_lines(page_path)
    b, e = marker_span(lines, page_path)
    current = lines[b + 1:e]

    # The page keeps its own line endings, so the canonical block is re-ended
    # to match the page's BEGIN marker line rather than the css file's.
    eol = "\r\n" if lines[b].endswith("\r\n") else "\n"
    want = []
    for ln in block:
        want.append(ln.rstrip("\r\n") + eol)

    if normalise(current) == normalise(want):
        return "ok", "%d line(s)" % len(current)
    if check_only:
        return "stale", ("page has %d line(s) between the markers, "
                         "vesta_theme.css has %d" % (len(current), len(want)))

    out = lines[:b + 1] + want + lines[e:]
    try:
        with io.open(page_path, "w", encoding="utf-8", newline="") as fh:
            fh.write("".join(out))
    except Exception as exc:
        raise ThemeError("cannot write " + page_path + ": " + str(exc))
    return "written", "%d line(s) replaced by %d" % (len(current), len(want))


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="splice docs/vesta_theme.css into the pages that adopt it")
    ap.add_argument("pages", nargs="*",
                    help="pages to process (default: every marked docs/*.html)")
    ap.add_argument("--css", default=DEF_CSS,
                    help="the theme source (default docs/vesta_theme.css)")
    ap.add_argument("--docs-dir", default=DEF_DOCS,
                    help="directory scanned when no pages are named")
    ap.add_argument("--check", action="store_true",
                    help="report staleness and change nothing")
    args = ap.parse_args(sys.argv[1:] if argv is None else argv)

    try:
        block = canonical_block(args.css)
        pages = args.pages or discover(args.docs_dir)
        if not pages:
            raise ThemeError("no page carries the theme markers; either the "
                             "docs directory is wrong or the markers are gone")

        print("theme_sync: source %s (%d line(s) between the markers)"
              % (args.css, len(block)))
        stale = []
        for page in pages:
            status, detail = splice(page, block, args.check)
            print("  %-8s %s  (%s)" % (status.upper(), page, detail))
            if status == "stale":
                stale.append(page)
    except ThemeError as exc:
        print("theme_sync: FATAL -- " + str(exc), file=sys.stderr)
        return 2

    print("")
    if stale:
        print("STALE: %d of %d page(s) do not carry the canonical block: %s"
              % (len(stale), len(pages), ", ".join(os.path.basename(p)
                                                   for p in stale)))
        print("  Re-splice them with: python3 tools/python/theme_sync.py")
        return 1
    print("OK: %d page(s) carry the canonical theme block." % len(pages))
    return 0


if __name__ == "__main__":
    sys.exit(main())
