#!/usr/bin/python3.6
"""Split an arch test too big for the chip's RAM into slices that fit.

The branch and jal tests pad every case with nops up to the tested offset: bltu-01
is 164 KB and jal-01 887 KB, against 54 KB of usable shared RAM. Each case is one
macro line with its signature offset spelled out, so a slice is the source with the
case lines of the other slices deleted. Signature layout is unchanged and slots of
deleted cases keep their 0xdeadbeef fill on the DUT and on the reference alike, so a
slice is judged the same way as a whole test: signature equal to the reference's.
Slices partition the cases. A case that alone exceeds the budget goes in no slice
and is printed: it jumps further than the chip has memory.
Usage: split_big.py <test.S> <outdir> [<budget-bytes>]
"""
import os
import re
import sys

CASE = re.compile(r'^\s*TEST_(BRANCH|JAL)_OP\((.*)\)\s*$')


def case_bytes(line):
    m = CASE.match(line)
    args = [a.strip() for a in m.group(2).split(',')]
    k = 6 if m.group(1) == 'BRANCH' else 2
    imm = abs(int(args[k], 0))
    # Padding is imm/2 nops for a backward target and imm/4 for a forward one.
    return 64 + 4 * (imm // 2 if args[k + 1].startswith('1') else imm // 4)


def main():
    src, outdir = sys.argv[1:3]
    budget = int(sys.argv[3]) if len(sys.argv) > 3 else 36000
    lines = open(src).read().split('\n')
    cases = [i for i, l in enumerate(lines) if CASE.match(l)]
    slices, cur, used, dropped = [], [], 0, []
    for i in cases:
        b = case_bytes(lines[i])
        if b > budget:
            dropped.append(lines[i].strip())
            continue
        if used + b > budget:
            slices.append(cur)
            cur, used = [], 0
        cur.append(i)
        used += b
    if cur:
        slices.append(cur)
    base = os.path.basename(src)[:-2]
    os.makedirs(outdir, exist_ok=True)
    for n, keep in enumerate(slices):
        keep = set(keep)
        with open(os.path.join(outdir, '%s.p%d.S' % (base, n)), 'w') as f:
            f.write('\n'.join(l for i, l in enumerate(lines) if i not in cases or i in keep))
            f.write('\n')
    print('%s: %d cases, %d slices, %d beyond budget' % (base, len(cases), len(slices), len(dropped)))
    for d in dropped:
        print('  beyond budget: ' + d)


if __name__ == '__main__':
    main()
