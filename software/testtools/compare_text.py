#!/usr/bin/env python3
"""Assert two text files are byte identical, printing the first difference.

Plain runner, no test framework: exit 0 passes, non zero fails. That is the
repository convention for python tests here.

Usage: compare_text.py ACTUAL EXPECTED [--label NAME]
"""

import argparse
import sys

MAX_REPORTED = 10


def main():
    p = argparse.ArgumentParser()
    p.add_argument("actual")
    p.add_argument("expected")
    p.add_argument("--label", default=None)
    args = p.parse_args()

    label = args.label or args.actual

    with open(args.actual, "rb") as f:
        actual = f.read()
    with open(args.expected, "rb") as f:
        expected = f.read()

    if actual == expected:
        print("PASS: %s is byte identical to %s" % (label, args.expected))
        return 0

    a_lines = actual.decode("utf-8", "replace").splitlines()
    e_lines = expected.decode("utf-8", "replace").splitlines()

    print("FAIL: %s differs from %s" % (label, args.expected))
    print("  actual   %d bytes, %d lines" % (len(actual), len(a_lines)))
    print("  expected %d bytes, %d lines" % (len(expected), len(e_lines)))

    shown = 0
    for i in range(max(len(a_lines), len(e_lines))):
        a = a_lines[i] if i < len(a_lines) else "<missing>"
        e = e_lines[i] if i < len(e_lines) else "<missing>"
        if a != e:
            print("  line %d:" % (i + 1))
            print("    actual   %s" % a)
            print("    expected %s" % e)
            shown += 1
            if shown >= MAX_REPORTED:
                print("  ... further differences suppressed")
                break
    return 1


if __name__ == "__main__":
    sys.exit(main())
