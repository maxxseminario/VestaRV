#!/usr/bin/env python3
"""rdl_legacy_snapshot.py -- write the frozen constant table
//platform/common:rdl_pkg_vs_legacy_test grades the generated packages against.

RUN THIS ONCE, BEFORE A PERIPHERAL MIGRATES, AND NEVER AS PART OF A GATE. The
whole value of rdl_legacy_constants.json is that it was written down at a moment
when the RTL still held its own copy of the numbers; a gate that regenerated it
would grade the emitter against itself and prove nothing. It is checked in, it
is edited by hand when a register deliberately changes, and the change is
reviewed like any other register change.

Two kinds of entry, and the difference matters when reading a failure:

  decodeConstants   READ OUT OF THE RTL TEXT. The word-offset constants the
                    peripheral's decode names -- a local `SLOT_CR`, the memory
                    map package's `RegSlotUARTxCR`, NPU's `MmrAddrNPUCR`,
                    irq_router's `W_CLAIM` -- with the md5 of the file each was
                    read from. This half is an INDEPENDENT copy: it does not run
                    through SystemRDL at any point.

  registers/fields  FROZEN FROM THE EMISSION at the timestamp below, after
                    reports R2/R3 had graded every .rdl against its decode and
                    //platform/common:rdl_vs_vhdl_<block>_test had been green on
                    all twenty-two. This half is independent in TIME, not in
                    source: it catches an .rdl edit that was not meant to change
                    a register, which is the failure mode a regenerate-and-diff
                    gate cannot see.

    usage:  rdl_legacy_snapshot.py [--out <path>]
"""

import argparse
import collections
import hashlib
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import rdl_model
import rdl_vhdl

REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
DEFAULT_OUT = os.path.join(HERE, 'rdl_legacy_constants.json')
MEMORY_MAP = os.path.join(REPO, 'hdl', 'common', 'MemoryMap.vhd')


def _read(path):
    with open(path) as f:
        return f.read()


def _md5(path):
    return hashlib.md5(open(path, 'rb').read()).hexdigest()


def _naturalConstants(src):
    return dict((m.group(1), int(m.group(2)))
                for m in re.finditer(
                    r'constant\s+(\w+)\s*:\s*(?:natural|integer)\s*:=\s*(\d+);', src))


def _decodeConstants(spec, block):
    """{identifier: [value, sourceFile]} for the word constants this block's
       decode names today, read from wherever the RTL reads them."""
    decode = rdl_vhdl._DECODE.get(block.Name)
    if decode is None:
        return {}, []
    rtlPath = os.path.join(REPO, spec['rtl'])
    local = _naturalConstants(_read(rtlPath))
    mm = _naturalConstants(_read(MEMORY_MAP))
    out = {}
    sources = set()
    for rt in block.RegisterTemplates:
        ident = rdl_vhdl._decodeIdent(decode, rt.NameTemplate)
        if ident is None:
            continue
        if ident in local:
            out[ident] = [local[ident], os.path.relpath(rtlPath, REPO)]
            sources.add(os.path.relpath(rtlPath, REPO))
        elif ident in mm:
            out[ident] = [mm[ident], 'hdl/common/MemoryMap.vhd']
            sources.add('hdl/common/MemoryMap.vhd')
        else:
            raise Exception('rdl_legacy_snapshot: %s names no constant %s in %s or the '
                            'memory-map package; the _DECODE table is wrong about it.'
                            % (block.Name, ident, spec['rtl']))
    return out, sorted(sources)


def _emitted(spec):
    """The register and field constants the emitter produces for one block today,
       read back out of the emitted text so what is frozen is what ships."""
    block = rdl_model.loadBlock(spec['source'], spec['top'])
    text = rdl_vhdl.emitString(block, spec['package'], spec)
    nat = dict((m.group(1), int(m.group(2)))
               for m in re.finditer(r'constant\s+(\w+)\s*:\s*natural\s*:=\s*(\d+);', text))
    vec = {}
    for m in re.finditer(r'constant\s+(\w+)\s*:\s*std_logic_vector\([^)]*\)\s*:=\s*'
                         r'(?:x"([0-9A-Fa-f]+)"|"([01]+)");', text):
        vec[m.group(1)] = int(m.group(2), 16) if m.group(2) else int(m.group(3), 2)
    regs = collections.OrderedDict()
    fields = collections.OrderedDict()
    regNames = set(rt.NameTemplate for rt in block.RegisterTemplates)
    for rt in block.RegisterTemplates:
        n = rt.NameTemplate
        row = collections.OrderedDict()
        for key, table in (('word', nat), ('addr', nat), ('reset', vec), ('impl', vec)):
            row[key] = table.get(n + '_' + key.upper())
        if any(v is not None for v in row.values()):
            regs[n] = row
        for bf in rt.BitFields:
            if bf.Unused or bf.Name + '_MSB' not in nat:
                continue
            fields[bf.Name] = collections.OrderedDict(
                (('msb', nat[bf.Name + '_MSB']),
                 ('lsb', nat[bf.Name + '_LSB']),
                 ('reset', None if bf.Name in regNames else vec.get(bf.Name + '_RESET'))))
    return block, regs, fields


def snapshot():
    out = collections.OrderedDict()
    out['_comment'] = (
        'FROZEN. Written by rdl_legacy_snapshot.py and never regenerated by a gate; '
        'see that file for why the two halves of each entry mean different things. '
        '//platform/common:rdl_pkg_vs_legacy_test grades hdl/common/regs/vhdl/*_regs_pkg.vhd '
        'against this. A deliberate register change edits this file in the same commit as '
        'the .rdl, and nothing else may.')
    out['_frozen'] = time.strftime('%Y-%m-%d', time.gmtime(1757548800))
    blocks = collections.OrderedDict()
    for spec in rdl_vhdl.RTL_PACKAGES:
        block, regs, fields = _emitted(spec)
        decode, sources = _decodeConstants(spec, block)
        entry = collections.OrderedDict()
        entry['package'] = spec['package']
        entry['rtl'] = spec['rtl']
        entry['rtlMd5'] = _md5(os.path.join(REPO, spec['rtl']))
        entry['decodeSources'] = sources
        entry['decodeSourceMd5'] = dict((s, _md5(os.path.join(REPO, s))) for s in sources)
        entry['decodeConstants'] = decode
        entry['registers'] = regs
        entry['fields'] = fields
        blocks[spec['package']] = entry
    out['blocks'] = blocks
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--out', default=DEFAULT_OUT)
    args = ap.parse_args(argv)
    data = snapshot()
    with open(args.out, 'w') as f:
        json.dump(data, f, indent=1, sort_keys=False)
        f.write('\n')
    n = sum(len(b['registers']) for b in data['blocks'].values())
    m = sum(len(b['fields']) for b in data['blocks'].values())
    d = sum(len(b['decodeConstants']) for b in data['blocks'].values())
    print('[rdl_legacy_snapshot] %s: %d blocks, %d decode constants, %d registers, %d fields'
          % (os.path.relpath(args.out, REPO), len(data['blocks']), d, n, m))
    return 0


if __name__ == '__main__':
    sys.exit(main())
