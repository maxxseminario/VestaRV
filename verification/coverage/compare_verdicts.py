#!/usr/bin/python3.6
"""VestaRV: does instrumentation change any test's result?

    compare_verdicts.py <results/base> <results/cov>

Compares verdict, end-of-simulation time in femtoseconds, and the number of tile
harts that reported pass. The time is the sharp check: the verdict is one bit, while
an instrumented run that moved a single clock edge would stop at a different time.
Exits nonzero on any difference, or if either side is missing a test.
"""

import glob
import os
import sys


def read(d):
    out = {}
    for f in glob.glob(os.path.join(d, '*.verdict')):
        p = open(f).read().split()
        out[p[0]] = (p[1], p[2], p[3])
    return out


def main():
    a, b = read(sys.argv[1]), read(sys.argv[2])
    bad = 0
    for t in sorted(set(a) | set(b)):
        if t not in a or t not in b:
            print('MISSING  %-28s base=%s cov=%s' % (t, a.get(t), b.get(t)))
            bad += 1
        elif a[t] != b[t]:
            print('DIFF     %-28s base=%s cov=%s' % (t, a[t], b[t]))
            bad += 1
    verdicts = {}
    for v in a.values():
        verdicts[v[0]] = verdicts.get(v[0], 0) + 1
    print('%d tests compared, base verdicts %s, %d differences' % (len(set(a) | set(b)), verdicts, bad))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
