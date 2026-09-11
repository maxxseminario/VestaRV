#!/usr/bin/env python3
"""rdl_vhdl_pkg.py -- emit the TRACKED VHDL register packages, level 2.

Two files, listed in rdl_vhdl.RTL_PACKAGES:

    hdl/common/periph/afe2_regs_pkg.vhd     from afe2.rdl  (addrmap afe2_site)
    hdl/common/periph/biasg_regs_pkg.vhd    from biasg.rdl (addrmap biasg)

They are TRACKED generated sources, not build outputs: Genus, Xcelium and GHDL
all read the RTL tree directly, so a package the RTL `use`s has to be a file in
that tree. The gate that keeps a tracked generated file honest is
//platform/common:rdl_vhdl_pkg_test, which regenerates both in a temp directory
and diffs; regenerate with

    tools/bin/bazel run //platform/common:rdl_vhdl_pkgs

What makes adopting them inert, and how that is proved:

  * the scalar constants are the .rdl's own offsets, field ranges and resets,
    and //platform/common:rdl_vs_vhdl_afe2_test / _biasg_test grade the .rdl
    against the decode;
  * the aggregate section (rdl_vhdl._aggregateLines) re-declares AFE2.vhd's
    W_* / NSTORED / reg_arr_t / IMPL / RSTVAL and BIASG.vhd's N_WORDS /
    reg_array / IMPL / RSTVAL under those exact identifiers, so the entities
    delete a declaration block and gain a context clause, and not one
    assignment in either body moves;
  * //platform/common:rdl_pkg_vs_legacy_test holds every emitted value against
    the hand-written constants as they stood before the migration, transcribed
    verbatim. That is the leg of the argument that is NOT circular: the other
    two both run through the .rdl.

Usage:
    rdl_vhdl_pkg.py [--out <repo root>] [--check]
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
        out[spec['file']] = rdl_vhdl.emitString(block, spec['package'])
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
