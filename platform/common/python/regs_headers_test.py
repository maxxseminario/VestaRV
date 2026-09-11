#!/usr/bin/env python3
"""regs_headers_test.py -- the tracked firmware register headers are current, and
they describe the same addresses MemoryMap.h does.

Two gates in one file, because they grade the same artifact from two directions:

  identity      software/include/regs/*.h is byte-identical to a fresh emission
                of platform/common/python/rdl_cheader_regs.py. Tracked generated
                files need this or they rot; it is the role
                check_memorymap_vhd_test plays for the memory-map package.

  consistency   every peripheral base and every register address the headers
                imply equals the one MemoryMap.h publishes. The two headers are
                emitted by different code from different sources -- MemoryMap.h
                from generate.py's PeripheralTemplate, these from the .rdl
                descriptions -- so agreement is evidence, not tautology. This is
                also the gate that catches a base address moving under firmware
                that has adopted the new headers while the rest still uses the
                old ones.

    regs_headers_test.py --memorymap-h <MemoryMap.h> [--regs <dir>]

The MemoryMap.h handed in is the PER-TILE AFE configuration's: it is the only
one that publishes AFE0BIASG0..CR, and the bases are identical in the
topology-A AFE configuration.
"""

import os
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import rdl_cheader_regs
import rdl_chip
import rdl_emit
import rdl_model

REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))


def _arg(name, default=None):
    """Read and REMOVE one --flag from argv, so what is left is unittest's own
       argument list and a bazel target can still name the class it wants."""
    flag = '--' + name
    for i, a in enumerate(sys.argv):
        if a == flag and i + 1 < len(sys.argv):
            value = sys.argv[i + 1]
            del sys.argv[i:i + 2]
            return value
        if a.startswith(flag + '='):
            value = a.split('=', 1)[1]
            del sys.argv[i]
            return value
    return default


MEMORYMAP_H = _arg('memorymap-h')
REGS_DIR = _arg('regs', os.path.join(REPO, 'software', 'include', 'regs'))


def _read(path):
    with open(path) as f:
        return f.read()


def _defines(text):
    """{name: int} for every object-like #define with an integer-literal body."""
    out = {}
    for m in re.finditer(r'^\s*#\s*define\s+([A-Za-z_]\w*)\s+\(?\s*'
                         r'(0[xX][0-9a-fA-F]+|\d+)\s*[uU]?\s*\)?\s*(?://.*|/\*.*)?$',
                         text, re.M):
        out[m.group(1)] = int(m.group(2), 0)
    return out


class TestHeadersAreCurrent(unittest.TestCase):

    def test_tracked_equals_generated(self):
        fresh = rdl_cheader_regs.emitAll()
        for rel in sorted(fresh):
            path = os.path.join(REPO, rel)
            self.assertTrue(os.path.isfile(path), rel + ' is not in the tree')
            self.assertEqual(_read(path), fresh[rel],
                             rel + ' is out of date. Regenerate with\n'
                             '    tools/bin/bazel run '
                             '//platform/common/python:rdl_regs_headers')

    def test_no_stale_header_is_left_behind(self):
        want = set(os.path.basename(r) for r in rdl_cheader_regs.emitAll())
        have = set(f for f in os.listdir(REGS_DIR) if f.endswith('.h'))
        self.assertEqual(sorted(have), sorted(want),
                         'software/include/regs holds a header the emitter does not '
                         'produce (or is missing one it does)')


class TestHeadersAgreeWithMemoryMapH(unittest.TestCase):
    """MemoryMap.h is the authority on addresses here: R5 owns its emission and
       this gate never edits it. A disagreement is reported against the .rdl
       side."""

    @classmethod
    def setUpClass(cls):
        cls.mm = _defines(_read(MEMORYMAP_H))
        cls.umbrella = _defines(_read(os.path.join(REGS_DIR, 'castalia_regs.h')))
        cls.binding = rdl_chip.bind(rdl_chip.DEFAULT_TOP, rdl_emit.DEFAULT_CONFIG)

    def test_every_base_matches(self):
        bad = []
        n = 0
        for (instName, base, flag, block, idx) in self.binding:
            have = self.umbrella.get(instName + '_BASE_ADDR')
            want = self.mm.get(instName + '_BASE')
            self.assertIsNotNone(have, instName + '_BASE_ADDR missing from castalia_regs.h')
            self.assertIsNotNone(want, instName + '_BASE missing from MemoryMap.h')
            n += 1
            if have != want:
                bad.append('%s: regs 0x%X, MemoryMap.h 0x%X' % (instName, have, want))
        self.assertEqual(bad, [], '\n'.join(bad))
        self.assertGreaterEqual(n, 34, 'only %d instances graded' % n)
        sys.stderr.write('  bases graded: %d\n' % n)

    def test_every_register_address_matches(self):
        """base + the .rdl offset equals MemoryMap.h's <INST><REG>_ADDRESS."""
        bad = []
        n = 0
        for (instName, base, flag, block, idx) in self.binding:
            for rt in block.RegisterTemplates:
                name = rdl_chip.instanceRegisterName(rt.NameTemplate,
                                                     flag.get('registerPrefix'), idx)
                want = self.mm.get(name + '_ADDRESS')
                if want is None:
                    bad.append('%s: %s_ADDRESS is not in MemoryMap.h' % (instName, name))
                    continue
                n += 1
                if base + rt.Offset != want:
                    bad.append('%s.%s: addrmap 0x%X, MemoryMap.h 0x%X'
                               % (instName, name, base + rt.Offset, want))
        self.assertEqual(bad, [], '%d of %d register addresses differ:\n%s'
                                  % (len(bad), n + len(bad), '\n'.join(bad[:40])))
        self.assertGreaterEqual(n, 350, 'only %d register addresses graded' % n)
        sys.stderr.write('  register addresses graded: %d\n' % n)

    def test_overlay_blocks_match(self):
        """BIASG is not in the top addrmap (SystemRDL cannot overlay one addrmap on
           another), so its registers are graded against the host's base here."""
        bad = []
        for (entry, flag, block) in rdl_cheader_regs.overlays(rdl_emit.DEFAULT_CONFIG):
            base = self.mm[entry['host'] + '_BASE']
            self.assertEqual(self.umbrella.get(entry['inst'] + '_BASE_ADDR'), base,
                             entry['inst'] + '_BASE_ADDR')
            for rt in block.RegisterTemplates:
                name = rdl_chip.instanceRegisterName(
                    rt.NameTemplate, flag.get('registerPrefix'),
                    entry['host'][len(flag['peripheral']) - 1:])
                want = self.mm.get(name + '_ADDRESS')
                if want is None or want != base + rt.Offset:
                    bad.append('%s: addrmap 0x%X, MemoryMap.h %s'
                               % (name, base + rt.Offset,
                                  ('0x%X' % want) if want is not None else 'absent'))
        self.assertEqual(bad, [], '\n'.join(bad))


if __name__ == '__main__':
    unittest.main()
