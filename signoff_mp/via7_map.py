#!/usr/bin/env python3
"""Histogram VIA7.S.1 result centroids from a Calibre ASCII DRC db."""
import sys, re
path = sys.argv[1]
want = sys.argv[2]
lines = open(path).read().splitlines()
precision = float(lines[0].split()[1])
i, rule, pts = 1, None, []
n = len(lines)
while i < n:
    ln = lines[i].strip()
    pm = re.match(r'^([pe])\s+(\d+)\s+(\d+)$', ln)
    if pm and rule == want:
        nv = int(pm.group(3)); xs = []; ys = []
        for k in range(nv):
            i += 1
            parts = lines[i].split()
            if len(parts) >= 2:
                try: xs.append(float(parts[0])); ys.append(float(parts[1]))
                except ValueError: pass
        if xs: pts.append((sum(xs)/len(xs)/precision, sum(ys)/len(ys)/precision))
        i += 1; continue
    if re.match(r'^[A-Za-z0-9_.]+$', ln) and '{' not in ln:
        rule = ln
    i += 1
print(f"{want}: {len(pts)} results")
# 2D histogram, 250um bins
from collections import Counter
h = Counter((int(x//250)*250, int(y//250)*250) for x, y in pts)
for (bx, by), c in sorted(h.items(), key=lambda kv: -kv[1])[:25]:
    print(f"  bin ({bx:5d},{by:5d}) : {c}")
# x and y marginal ranges
xs = sorted(p[0] for p in pts); ys = sorted(p[1] for p in pts)
print(f"  x range {xs[0]:.1f}..{xs[-1]:.1f}  y range {ys[0]:.1f}..{ys[-1]:.1f}")
