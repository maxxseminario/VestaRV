#!/usr/bin/env python3
"""VestaRV: the tracked VHDL register packages are what the emitter produces today, byte for byte.

The packages under hdl/common/regs/vhdl/ are tracked generated sources, since Genus, Xcelium
and GHDL all read the RTL tree directly. This keeps one from being hand-edited or left behind
by an .rdl change. On failure: tools/bin/bazel run //platform/common/python:rdl_vhdl_pkgs
"""

import difflib
import os
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import rdl_vhdl
import rdl_vhdl_pkg

REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))


class TestTrackedPackagesAreCurrent(unittest.TestCase):

    def test_every_tracked_package_matches_a_fresh_emission(self):
        fresh = rdl_vhdl_pkg.emitAll()
        self.assertEqual(sorted(fresh), sorted(s['file'] for s in rdl_vhdl.RTL_PACKAGES))
        for rel in sorted(fresh):
            path = os.path.join(REPO, rel)
            self.assertTrue(os.path.isfile(path), rel + ' is not in the tree')
            with open(path) as f:
                have = f.read()
            if have == fresh[rel]:
                continue
            diff = '\n'.join(difflib.unified_diff(
                have.splitlines(), fresh[rel].splitlines(),
                fromfile=rel + ' (tracked)', tofile=rel + ' (generated)', lineterm=''))
            self.fail('%s is out of date. Regenerate with\n'
                      '    tools/bin/bazel run //platform/common/python:rdl_vhdl_pkgs\n\n%s'
                      % (rel, diff))

    def test_the_rtl_each_package_belongs_to_is_present(self):
        """The table names the entity each package exists for, so that claim is checked rather than told.
        A package whose `migrated` flag is set must carry the context clause; one not yet adopted must
        still name an entity really in the tree, or it is dead generated code.
        """
        for spec in rdl_vhdl.RTL_PACKAGES:
            rtl = os.path.join(REPO, spec['rtl'])
            self.assertTrue(os.path.isfile(rtl), spec['rtl'] + ' is not in the tree')
            with open(rtl) as f:
                src = f.read()
            uses = 'use work.%s.all;' % spec['package'] in src
            if spec.get('migrated', True):
                self.assertTrue(uses, '%s is flagged migrated but does not use %s'
                                % (spec['rtl'], spec['package']))
            else:
                self.assertFalse(uses,
                                 '%s uses %s but RTL_PACKAGES still says migrated=False. Flip '
                                 'the flag in rdl_vhdl.py so the gates grade the adoption.'
                                 % (spec['rtl'], spec['package']))

    def test_an_adopted_package_replaced_the_memory_map(self):
        """An entity that has adopted its register package must not also `use work.MemoryMap.all` where
        the two declare the same name: two directly visible declarations of one name are homographs
        and VHDL makes neither visible. Adoption is a swap, and the overlap is computed, not asserted.
        """
        with open(os.path.join(REPO, 'hdl', 'common', 'MemoryMap.vhd')) as f:
            mmNames = set(m.group(1).lower() for m in
                          re.finditer(r'constant\s+(\w+)\s*:', f.read()))
        for spec in rdl_vhdl.RTL_PACKAGES:
            if not spec.get('migrated', True):
                continue
            with open(os.path.join(REPO, spec['file'])) as f:
                pkgNames = set(m.group(1).lower() for m in
                               re.finditer(r'constant\s+(\w+)\s*:', f.read()))
            shared = sorted(pkgNames & mmNames)
            if not shared:
                continue
            with open(os.path.join(REPO, spec['rtl'])) as f:
                src = f.read()
            self.assertNotIn('use work.MemoryMap.all;', src,
                             '%s uses both work.MemoryMap and %s, which declare %d name(s) in '
                             'common (%s ...). Drop the memory-map clause.'
                             % (spec['rtl'], spec['package'], len(shared), ', '.join(shared[:4])))


if __name__ == '__main__':
    unittest.main()
