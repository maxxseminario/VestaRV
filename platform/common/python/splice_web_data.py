#!/usr/bin/env python3
"""VestaRV: inject out/web/chip_data.js into an HTML file between its splice markers.

    python3 python/splice_web_data.py [--data out/web/chip_data.js] TARGET.html
    python3 python/splice_web_data.py --check TARGET.html

Markers are matched anywhere in the file and preserved; splicing twice gives the same file.
"""

import io
import os
import sys

BEGIN = '/*VESTA_DATA_BEGIN*/'
END = '/*VESTA_DATA_END*/'

HERE = os.path.abspath(os.path.dirname(__file__))
PC_ROOT = os.path.dirname(HERE)
DEFAULT_DATA = os.path.join(PC_ROOT, 'out', 'web', 'chip_data.js')


def _read(path):
    with io.open(path, 'r', encoding='utf-8') as f:
        return f.read()


def _write(path, text):
    with io.open(path, 'w', encoding='utf-8') as f:
        f.write(text)


def _region(html):
    """Return (before, between, after) around the FIRST marker pair, or raise."""
    i = html.find(BEGIN)
    if i < 0:
        raise SystemExit('splice error: begin marker %s not found in target' % BEGIN)
    j = html.find(END, i + len(BEGIN))
    if j < 0:
        raise SystemExit('splice error: end marker %s not found after begin' % END)
    if html.find(BEGIN, i + len(BEGIN)) != -1:
        raise SystemExit('splice error: more than one %s marker in target' % BEGIN)
    before = html[:i + len(BEGIN)]
    between = html[i + len(BEGIN):j]
    after = html[j:]
    return before, between, after


def _rendered(data_text):
    """The canonical between-markers payload for a given chip_data.js content."""
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
        print('usage: splice_web_data.py [--data chip_data.js] [--check] TARGET.html', file=sys.stderr)
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
