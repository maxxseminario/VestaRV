#!/usr/bin/python3.6
"""Merge the DUT signatures of a test's slices and compare with the whole test.

A slice passing against its own reference proves nothing about cases it dropped.
This overlays all slices of a test, taking each word from the slice that changed it
from the 0xdeadbeef fill, and diffs the result with the reference signature of the
UNSLICED test. A word still at the fill where the whole test wrote one is a case no
slice covered.
Usage: merge_slices.py <slice-workdir> <whole-workdir> <test> ...   e.g. beq-01
"""
import glob
import os
import sys

FILL = 'deadbeef'


def read(p):
    return open(p).read().split()


def main():
    sl, whole = sys.argv[1:3]
    for t in sys.argv[3:]:
        ref = read(os.path.join(whole, 'I/src/%s.S/ref/spike.signature' % t))
        parts = glob.glob(os.path.join(sl, 'I/src/%s.p*.S/dut/DUT-vesta.signature' % t))
        merged = [FILL] * len(ref)
        clash = 0
        for p in parts:
            for i, w in enumerate(read(p)):
                if w != FILL:
                    clash += merged[i] != FILL and merged[i] != w
                    merged[i] = w
        missing = [i for i, (m, r) in enumerate(zip(merged, ref)) if m != r and m == FILL]
        wrong = [i for i, (m, r) in enumerate(zip(merged, ref)) if m != r and m != FILL]
        print('%s: %d slices, %d words, %d equal, %d uncovered %s, %d wrong, %d clash' % (
            t, len(parts), len(ref), len(ref) - len(missing) - len(wrong),
            len(missing), missing[:6], len(wrong), clash))


if __name__ == '__main__':
    main()
