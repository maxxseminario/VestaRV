#!/usr/bin/env python3
"""CP5: class-by-class DRC comparison of two Calibre chipdrc .rpt files.

Reads the "RULECHECK <name> ... TOTAL Result Count = N (M)" lines (the summary
statistics block Calibre writes at the end of every run) from a reference and a
candidate report, and prints every rule whose count differs, plus the totals.

Usage: cp5_drc_compare.py <reference.rpt> <candidate.rpt>
"""
import re
import sys

RE = re.compile(r'RULECHECK\s+(\S+?)\s*\.*\s+TOTAL Result Count\s*=\s*(\d+)\s*\((\d+)\)')


def read(path):
    out = {}
    with open(path, errors='replace') as fh:
        for line in fh:
            m = RE.search(line)
            if m:
                out[m.group(1)] = (int(m.group(2)), int(m.group(3)))
    return out


def total(path):
    with open(path, errors='replace') as fh:
        for line in fh:
            m = re.search(r'TOTAL DRC Results Generated:\s+(\d+)\s+\((\d+)\)', line)
            if m:
                return int(m.group(1)), int(m.group(2))
    return None


def main():
    ref, cand = sys.argv[1], sys.argv[2]
    a, b = read(ref), read(cand)
    ta, tb = total(ref), total(cand)
    print('reference : %s  TOTAL %s' % (ref, ta))
    print('candidate : %s  TOTAL %s' % (cand, tb))
    print('')
    keys = sorted(set(a) | set(b))
    same = 0
    print('%-28s %10s %10s %8s' % ('RULECHECK', 'reference', 'candidate', 'delta'))
    for k in keys:
        va = a.get(k, (0, 0))[0]
        vb = b.get(k, (0, 0))[0]
        if va == vb:
            same += 1
            continue
        print('%-28s %10d %10d %+8d' % (k, va, vb, vb - va))
    print('')
    print('%d rules identical, %d rules differ' % (same, len(keys) - same))
    nz_a = {k: v[0] for k, v in a.items() if v[0]}
    nz_b = {k: v[0] for k, v in b.items() if v[0]}
    print('non-zero rules: reference %d (%d results) / candidate %d (%d results)'
          % (len(nz_a), sum(nz_a.values()), len(nz_b), sum(nz_b.values())))


if __name__ == '__main__':
    main()
