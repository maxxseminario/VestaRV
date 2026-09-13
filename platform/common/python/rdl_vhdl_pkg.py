#!/usr/bin/env python3
"""VestaRV: emit the tracked VHDL register packages, one per block in rdl_vhdl.RTL_PACKAGES.

They are tracked generated sources under hdl/common/regs/vhdl/, not build outputs: Genus,
Xcelium and GHDL read the RTL tree directly. rdl_vhdl_pkg_test regenerates and diffs each.
The aggregate section re-declares an adopting entity's array type and IMPL/RSTVAL tables under
the same identifiers, so adoption moves no assignment. Usage: [--out <root>] [--check].
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rdl_model
import rdl_vhdl

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))


def emitAll():
    """{relative path: file text} for every tracked package."""
    out = {}
    for spec in rdl_vhdl.RTL_PACKAGES:
        block = rdl_model.loadBlock(spec['source'], spec['top'])
        out[spec['file']] = rdl_vhdl.emitString(block, spec['package'], spec)
    return out


def writeAll(root):
    written = []
    for rel, text in sorted(emitAll().items()):
        path = os.path.join(root, rel)
        d = os.path.dirname(path)
        if not os.path.isdir(d):
            os.makedirs(d)
        with open(path, 'w') as f:
            f.write(text)
        written.append(path)
    return written


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--out', default=None, help='repository root to write into')
    ap.add_argument('--check', action='store_true',
                    help='do not write; exit 1 if a tracked file differs')
    args = ap.parse_args(argv)
    root = args.out or os.environ.get('BUILD_WORKSPACE_DIRECTORY') or REPO

    if args.check:
        bad = 0
        for rel, text in sorted(emitAll().items()):
            path = os.path.join(root, rel)
            have = open(path).read() if os.path.isfile(path) else None
            if have != text:
                sys.stderr.write('rdl_vhdl_pkg: OUT OF DATE: ' + rel + '\n')
                bad += 1
        return 1 if bad else 0

    for path in writeAll(root):
        print('[rdl_vhdl_pkg] ' + os.path.relpath(path, root))
    return 0


if __name__ == '__main__':
    sys.exit(main())
