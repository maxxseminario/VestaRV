#!/usr/bin/env python3
"""VestaRV: assert a file's md5 matches a pinned md5sum-format record.

Plain runner, no test framework: exit 0 passes, non zero fails.

Usage: check_md5.py FILE PIN [--label NAME]
PIN holds one md5sum line, "<32 hex>  <name>"; only the hash is compared.
"""

import argparse
import hashlib
import sys


def main():
    p = argparse.ArgumentParser()
    p.add_argument("file")
    p.add_argument("pin")
    p.add_argument("--label", default=None)
    args = p.parse_args()

    label = args.label or args.file
    with open(args.pin) as f:
        expected = f.read().split()[0].lower()
    with open(args.file, "rb") as f:
        actual = hashlib.md5(f.read()).hexdigest()

    if actual == expected:
        print("PASS: %s md5 %s matches %s" % (label, actual, args.pin))
        return 0
    print("FAIL: %s md5 %s, pinned %s in %s" % (label, actual, expected, args.pin))
    return 1


if __name__ == "__main__":
    sys.exit(main())
