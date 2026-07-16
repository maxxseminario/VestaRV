#!/usr/bin/env python3
"""Argus A6: classify Calibre DRC results (chipdrc.db / ant25.db ASCII RVE) into
core vs pad-ring by polygon centroid, so chip-integration violations (pad ring,
core density) are separated from anything genuinely new in the core.

Calibre ASCII results DB format:
  <topcell> <precision>            # precision = DB units per micron
  <RULENAME>
  <count> <origcount> <?> <date>
  <RULENAME> { ... rule text ... }
  p <id> <nverts>                  # one polygon result
  <x> <y>                          # nverts vertex lines (DB units)
  ...
  (next rule / next polygon)

Coords are in DB units (divide by precision for microns). The Argus core box is
(1,1)-(2689,2689) um in the design frame; the pad ring is outside it (die
-155..2845). We compute each result's centroid (mean of its vertices) and bin
core-vs-ring against the core box, per rule.

Usage: classify_drc.py <results.db> [core_llx core_lly core_urx core_ury]
       (defaults to the Argus core box 1 1 2689 2689 um)
"""
import sys, re

def main():
    path = sys.argv[1]
    core = (1.0, 1.0, 2689.0, 2689.0)
    if len(sys.argv) >= 6:
        core = tuple(map(float, sys.argv[2:6]))
    clx, cly, cux, cuy = core

    lines = open(path).read().splitlines()
    # header
    m = lines[0].split()
    topcell, precision = m[0], float(m[1])
    i = 1
    rule = None
    # per-rule: [core_count, ring_count, total, sample_centroid]
    stats = {}
    n = len(lines)
    while i < n:
        ln = lines[i].strip()
        if not ln:
            i += 1; continue
        # a polygon header?
        pm = re.match(r'^([pe])\s+(\d+)\s+(\d+)$', ln)
        if pm and rule is not None:
            nv = int(pm.group(3))
            xs = []; ys = []
            for k in range(nv):
                i += 1
                if i >= n: break
                parts = lines[i].split()
                if len(parts) >= 2:
                    try:
                        xs.append(float(parts[0])); ys.append(float(parts[1]))
                    except ValueError:
                        pass
            if xs:
                cx = sum(xs)/len(xs)/precision
                cy = sum(ys)/len(ys)/precision
                s = stats.setdefault(rule, [0, 0, 0, None])
                s[2] += 1
                if clx <= cx <= cux and cly <= cy <= cuy:
                    s[0] += 1
                else:
                    s[1] += 1
                if s[3] is None:
                    s[3] = (round(cx, 1), round(cy, 1))
            i += 1
            continue
        # a rule summary line "<count> <count> <n> <date...>"?
        sm = re.match(r'^\d+\s+\d+\s+\d+\s+\w', ln)
        if sm and rule is not None:
            i += 1; continue
        # a rule body line "{ ... " or "}" -> skip
        if ln.startswith('{') or ln.endswith('{') or ln == '}' or ln.startswith('  '):
            i += 1; continue
        # otherwise: a rule name (token, may contain . and letters)
        if re.match(r'^[A-Za-z0-9_.]+$', ln) and '{' not in ln:
            rule = ln
            i += 1; continue
        i += 1

    print(f"# topcell={topcell} precision={precision} core box=({clx},{cly})-({cux},{cuy}) um")
    print(f"# {'RULE':<22} {'TOTAL':>7} {'CORE':>7} {'RING':>7}   sample_centroid_um")
    tc = tr = tt = 0
    for rule in sorted(stats, key=lambda r: -stats[r][2]):
        ccore, cring, tot, samp = stats[rule]
        if tot == 0:
            continue
        tc += ccore; tr += cring; tt += tot
        print(f"  {rule:<22} {tot:>7} {ccore:>7} {cring:>7}   {samp}")
    print(f"  {'TOTAL':<22} {tt:>7} {tc:>7} {tr:>7}")

if __name__ == "__main__":
    main()
