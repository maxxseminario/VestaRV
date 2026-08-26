#!/usr/bin/env python3
"""CP5: locate Calibre DRC results by centroid and bin them against the
CASTALIA-PENTA orchestrator flank (CP1 D9: x [2188.8, 2679.3], y [1051.2,
1638.9] -- the ONLY area of the die the penta cut changed).

Any DRC result whose centroid lands inside that box is a candidate
orchestrator-caused violation and must be root-caused to a named object;
everything outside is pre-existing chip/pad-ring population, and is compared
count-by-count against the reference cut instead.

Usage: cp5_drc_locate.py <results.db> [rule ...]
       (no rule list = every rule with results)
"""
import re
import sys

FLANK = (2188.8, 1051.2, 2679.3, 1638.9)


def parse(path):
    """-> {rule: [(cx, cy), ...]} centroids in um"""
    lines = open(path, errors='replace').read().splitlines()
    topcell, precision = lines[0].split()[0], float(lines[0].split()[1])
    out = {}
    rule = None
    i, n = 1, len(lines)
    while i < n:
        ln = lines[i].strip()
        if not ln:
            i += 1
            continue
        pm = re.match(r'^([pe])\s+(\d+)\s+(\d+)$', ln)
        if pm and rule is not None:
            nv = int(pm.group(3))
            xs, ys = [], []
            for _ in range(nv):
                i += 1
                if i >= n:
                    break
                p = lines[i].split()
                if len(p) >= 2:
                    try:
                        xs.append(float(p[0]))
                        ys.append(float(p[1]))
                    except ValueError:
                        pass
            if xs:
                out.setdefault(rule, []).append(
                    (sum(xs) / len(xs) / precision, sum(ys) / len(ys) / precision))
            i += 1
            continue
        if re.match(r'^\d+\s+\d+\s+\d+\s+\w', ln):
            i += 1
            continue
        if ln.startswith('{') or ln.endswith('{') or ln == '}' or lines[i].startswith('  '):
            i += 1
            continue
        if re.match(r'^[A-Za-z][A-Za-z0-9_.:]*$', ln):
            rule = ln
        i += 1
    return topcell, out


def main():
    path = sys.argv[1]
    want = set(sys.argv[2:])
    top, res = parse(path)
    fx0, fy0, fx1, fy1 = FLANK
    print('layout %s   flank box (%.1f,%.1f)-(%.1f,%.1f)' % (top, fx0, fy0, fx1, fy1))
    tot_in = tot = 0
    for rule in sorted(res):
        if want and rule not in want:
            continue
        pts = res[rule]
        inside = [p for p in pts if fx0 <= p[0] <= fx1 and fy0 <= p[1] <= fy1]
        tot += len(pts)
        tot_in += len(inside)
        flag = '  <== IN FLANK' if inside else ''
        print('%-26s %5d results, %3d in flank%s' % (rule, len(pts), len(inside), flag))
        for p in inside[:12]:
            print('        (%.3f, %.3f)' % p)
    print('')
    print('TOTAL %d results, %d inside the orchestrator flank' % (tot, tot_in))


if __name__ == '__main__':
    main()
