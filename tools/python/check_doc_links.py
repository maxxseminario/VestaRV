#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
check_doc_links.py -- relative-link checker for VestaRV documentation.

Scans every tracked Markdown file (git ls-files '*.md') plus docs/*.html for
relative links (Markdown `](target)`, and HTML href=/src=/iframe src= targets),
and verifies that each target path exists on disk.

- Missing relative targets -> reported and cause a non-zero exit.
- http(s):// (and protocol-relative //) targets -> reported as INFO only; no
  network access is performed and they never fail the run.
- In-page anchors (#...), mailto:/tel:/javascript:/data: URIs, and empty targets
  are skipped.
- Files under .claude/worktrees/ are skipped.

Two ways to name the files to scan:

    check_doc_links.py                       git ls-files '*.md' + docs/*.html
    check_doc_links.py --files-from LIST     one repo-relative path per line

--files-from exists for callers that already know the file set and must not
shell out to git (the bazel sandbox has no .git).  --root overrides the repo
root the paths are resolved against; it defaults to three levels above this
file, which is what it always was.

NEITHER MODE MAY FAIL OPEN.  An unreadable file list, an unreadable listed
file, or a git that will not run is exit 2, never an empty scan reported as
"OK: no missing relative targets".

Python 3.6 compatible (no f-strings with '=', no walrus operator).
"""

from __future__ import print_function

import argparse
import os
import re
import subprocess
import sys


REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class InputError(Exception):
    """An input could not be read. Always fatal: see the header."""

# Markdown inline link / image target:  ](target)   or   ](target "title")
MD_LINK_RE = re.compile(r"\]\(\s*([^)]+?)\s*\)")
# HTML href= / src= attribute (covers <a>, <img>, <iframe>, <link>, <script>).
HTML_ATTR_RE = re.compile(r"""(?:href|src)\s*=\s*["']([^"']+)["']""", re.IGNORECASE)

SKIP_PREFIXES = ("mailto:", "tel:", "javascript:", "data:", "#")


def is_external(target):
    low = target.lower()
    return low.startswith("http://") or low.startswith("https://") or low.startswith("//")


def clean_md_target(raw):
    """Extract the URL from a Markdown link target, dropping any "title" and <>."""
    t = raw.strip()
    if t.startswith("<") and ">" in t:
        t = t[1:t.index(">")]
        return t.strip()
    # Drop an optional title:  path "Title"   or   path 'Title'
    for q in ('"', "'"):
        if q in t:
            t = t[:t.index(q)]
            break
    return t.strip()


def strip_fragment(target):
    """Remove #fragment and ?query from a relative target."""
    for sep in ("#", "?"):
        if sep in target:
            target = target[:target.index(sep)]
    return target


def files_from_list(list_path, root):
    """Read a newline-separated list of repo-relative paths.

    A read failure here is FATAL, not an empty list: an empty scan exits 0 and
    would be quoted as evidence that the links are fine.
    """
    try:
        with open(list_path, "r") as fh:
            raw = fh.read()
    except Exception as exc:
        raise InputError("cannot read --files-from list " + list_path
                         + ": " + str(exc))
    files = []
    for line in raw.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if ".claude/worktrees/" in line:
            continue
        abspath = os.path.join(root, line)
        if not os.path.isfile(abspath):
            raise InputError("listed file does not exist: " + line
                             + " (resolved to " + abspath + ")")
        files.append(line)
    if not files:
        raise InputError("--files-from list " + list_path + " named no files")
    return files


def tracked_md_files(root):
    try:
        out = subprocess.check_output(
            ["git", "ls-files", "*.md"], cwd=root
        ).decode("utf-8", "replace")
    except Exception as exc:
        raise InputError("git ls-files failed: " + str(exc))
    files = []
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        if ".claude/worktrees/" in line:
            continue
        files.append(line)
    return files


def docs_html_files(root):
    docs_dir = os.path.join(root, "docs")
    files = []
    if not os.path.isdir(docs_dir):
        return files
    for name in sorted(os.listdir(docs_dir)):
        if name.lower().endswith(".html"):
            files.append(os.path.join("docs", name))
    return files


def extract_targets(relpath, root, strict):
    """Yield (target, kind) for one file. kind is 'md' or 'html'."""
    abspath = os.path.join(root, relpath)
    try:
        with open(abspath, "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except Exception as exc:
        if strict:
            raise InputError("could not read " + relpath + ": " + str(exc))
        print("WARN: could not read " + relpath + ": " + str(exc), file=sys.stderr)
        return

    is_md = relpath.lower().endswith(".md")
    if is_md:
        in_fence = False
        for line in text.splitlines():
            stripped = line.lstrip()
            if stripped.startswith("```") or stripped.startswith("~~~"):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            for m in MD_LINK_RE.finditer(line):
                yield clean_md_target(m.group(1)), "md"
            # Markdown files may also embed raw HTML (badges, logo tables).
            for m in HTML_ATTR_RE.finditer(line):
                yield m.group(1).strip(), "html"
    else:
        for m in HTML_ATTR_RE.finditer(text):
            yield m.group(1).strip(), "html"


def parse_args(argv):
    ap = argparse.ArgumentParser(
        description="relative-link checker for VestaRV documentation")
    ap.add_argument("--files-from", default=None, metavar="LIST",
                    help="scan exactly the repo-relative paths named in LIST, "
                         "one per line, instead of asking git")
    ap.add_argument("--root", default=REPO_ROOT,
                    help="repo root the relative paths resolve against")
    return ap.parse_args(argv)


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    root = os.path.abspath(args.root)

    # --files-from is the STRICT mode: every named file must be readable, and
    # an unreadable one is exit 2 rather than a quietly shorter scan.
    strict = args.files_from is not None
    try:
        if strict:
            files = files_from_list(args.files_from, root)
        else:
            files = tracked_md_files(root) + docs_html_files(root)
    except InputError as exc:
        print("check_doc_links: FATAL -- " + str(exc), file=sys.stderr)
        return 2

    missing = []      # list of (source, target)
    info_external = []  # list of (source, target)
    checked = 0

    for relpath in files:
        src_dir = os.path.dirname(os.path.join(root, relpath))
        try:
            targets = list(extract_targets(relpath, root, strict))
        except InputError as exc:
            print("check_doc_links: FATAL -- " + str(exc), file=sys.stderr)
            return 2
        for target, _kind in targets:
            if not target:
                continue
            low = target.lower()
            if low.startswith(SKIP_PREFIXES):
                continue
            if is_external(target):
                info_external.append((relpath, target))
                continue
            clean = strip_fragment(target)
            if not clean:
                continue
            checked += 1
            resolved = os.path.normpath(os.path.join(src_dir, clean))
            if not os.path.exists(resolved):
                missing.append((relpath, target))

    print("check_doc_links: scanned %d file(s), checked %d relative target(s)"
          % (len(files), checked))

    if info_external:
        print("")
        print("INFO: %d external http(s) link(s) (not verified):" % len(info_external))
        for src, target in info_external:
            print("  [INFO] %s -> %s" % (src, target))

    if missing:
        print("")
        print("FAIL: %d missing relative target(s):" % len(missing))
        for src, target in missing:
            print("  [MISSING] %s -> %s" % (src, target))
        return 1

    print("")
    print("OK: no missing relative targets.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
