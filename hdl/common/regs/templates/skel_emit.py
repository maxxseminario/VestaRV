#!/usr/bin/env python3
"""VestaRV: emit the skeleton block's VHDL register package into a scratch directory.

The skeleton is deliberately absent from platform/common/config/rdl.json and from
rdl_vhdl.RTL_PACKAGES, so a copy of it never ships as a phantom peripheral. This driver
supplies the two registrations a real block makes there (the periph_regs table set and the
decode spelling) for one emission only, in memory, and writes the package where the caller
asks. //hdl/common/regs/templates:skel_smoke then analyses SKEL.vhd against the result.
"""

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(HERE))))
sys.path.insert(0, os.path.join(REPO, 'platform', 'common', 'python'))

import rdl_model
import rdl_vhdl

# The two rows a registered block owns in rdl_vhdl: membership of _REGFILE, which
# is what emits NWORDS, reg_arr_t and the eight periph_regs tables, and a _DECODE
# entry naming the word-offset spelling SKEL.vhd's ports and assignments use.
_SPEC = {'source': 'skel.rdl', 'top': 'skel',
         'rtl': 'hdl/common/regs/templates/SKEL.vhd'}
_DECODE = {'rtl': 'SKEL.vhd', 'style': 'strip', 'strip': 'SKELx', 'prefix': 'SLOT_'}


def emit(rdlPath):
    rdl_vhdl._REGFILE = tuple(rdl_vhdl._REGFILE) + ('skel',)
    rdl_vhdl._DECODE['skel'] = _DECODE
    block = rdl_model.compileFiles([os.path.abspath(rdlPath)], top='skel')[0]
    return rdl_vhdl.emitString(block, 'skel_regs_pkg', _SPEC)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--rdl', default=os.path.join(HERE, 'skel.rdl'))
    ap.add_argument('--out', required=True, help='path of the package file to write')
    args = ap.parse_args(argv)
    text = emit(args.rdl)
    d = os.path.dirname(os.path.abspath(args.out))
    if d and not os.path.isdir(d):
        os.makedirs(d)
    with open(args.out, 'w') as f:
        f.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
