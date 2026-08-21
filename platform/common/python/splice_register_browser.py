#!/usr/bin/env python3
"""splice_register_browser.py -- inject out/web/MemoryMap.json into the register
browser page between its splice markers. This is the repair tool for the
tools/python/check_register_browser.py provenance gate (the K7/F-K5-2 lesson:
a gate the project's own tooling cannot satisfy strands the first person to
move the schema -- see the `web` target in platform/common/Makefile).

The page declares an inline region inside <script id="regdata"
type="application/json">:

    /*VESTA_REGDATA_BEGIN*/ ... /*VESTA_REGDATA_END*/

and this tool replaces everything between those markers with the current
generator output, so the page never carries a hand-maintained second copy of
the memory map.

Usage:
    python3 python/splice_register_browser.py [--data out/web/MemoryMap.json] TARGET.html
    python3 python/splice_register_browser.py --check TARGET.html   # up to date?

Contract / guarantees:
  * Markers are matched ONLY at the start of a line. The page's loader JS
    contains both tokens again inside string literals (the strip step at parse
    time); those mid-line occurrences are data, not markers, and are ignored.
  * IDEMPOTENT: splicing the same data twice produces the identical file.
  * Exit 0 on success; non-zero if the markers are missing or (with --check)
    the region is stale.

Python 3.6 compatible; no external deps.
"""

import io
import os
import sys

BEGIN = '/*VESTA_REGDATA_BEGIN*/'
END = '/*VESTA_REGDATA_END*/'

HERE = os.path.abspath(os.path.dirname(__file__))
PC_ROOT = os.path.dirname(HERE)
DEFAULT_DATA = os.path.join(PC_ROOT, 'out', 'web', 'MemoryMap.json')


def _read(path):
    with io.open(path, 'r', encoding='utf-8') as f:
        return f.read()


def _write(path, text):
    with io.open(path, 'w', encoding='utf-8') as f:
        f.write(text)


def _find_line_anchored(html, token, start=0):
    """Index of the first occurrence of token at the start of a line, or -1."""
    i = html.find(token, start)
    while i != -1:
        if i == 0 or html[i - 1] == '\n':
            return i
        i = html.find(token, i + 1)
    return -1


def _region(html):
    """Return (before, between, after) around the line-anchored marker pair."""
    i = _find_line_anchored(html, BEGIN)
    if i < 0:
        raise SystemExit('splice error: line-anchored %s marker not found in target' % BEGIN)
    j = _find_line_anchored(html, END, i + len(BEGIN))
    if j < 0:
        raise SystemExit('splice error: line-anchored %s marker not found after begin' % END)
    if _find_line_anchored(html, BEGIN, i + len(BEGIN)) != -1:
        raise SystemExit('splice error: more than one line-anchored %s marker' % BEGIN)
    return html[:i + len(BEGIN)], html[i + len(BEGIN):j], html[j:]


def _rendered(data_text):
    """The canonical between-markers payload for a given MemoryMap.json content."""
    return '\n' + data_text.strip('\n') + '\n'


def splice(target_path, data_path):
    html = _read(target_path)
    data_text = _read(data_path)
    before, _between, after = _region(html)
    new_html = before + _rendered(data_text) + after
    changed = (new_html != html)
    if changed:
        _write(target_path, new_html)
    return changed


def check(target_path, data_path):
    """True if the target's region already matches the data (up to date)."""
    html = _read(target_path)
    data_text = _read(data_path)
    _before, between, _after = _region(html)
    return between == _rendered(data_text)


def main(argv):
    args = list(argv[1:])
    data_path = DEFAULT_DATA
    do_check = False
    rest = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == '--data':
            i += 1
            data_path = args[i]
        elif a.startswith('--data='):
            data_path = a[len('--data='):]
        elif a == '--check':
            do_check = True
        elif a in ('-h', '--help'):
            print(__doc__)
            return 0
        else:
            rest.append(a)
        i += 1
    if len(rest) != 1:
        print('usage: splice_register_browser.py [--data MemoryMap.json] [--check] TARGET.html', file=sys.stderr)
        return 2
    target_path = rest[0]
    if not os.path.isfile(target_path):
        print('splice error: target not found: %s' % target_path, file=sys.stderr)
        return 2
    if not os.path.isfile(data_path):
        print('splice error: data file not found: %s (run make web first)' % data_path, file=sys.stderr)
        return 2

    if do_check:
        if check(target_path, data_path):
            print('splice: %s is up to date' % target_path)
            return 0
        print('splice: %s is STALE vs %s (run without --check to update)' % (target_path, data_path))
        return 1

    changed = splice(target_path, data_path)
    if changed:
        print('splice: updated %s from %s' % (target_path, data_path))
    else:
        print('splice: %s already current (no change)' % target_path)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
