#!/usr/bin/env python3
"""rdl_vhdl_pkg_test.py -- the tracked VHDL register packages are what the
emitter produces today, byte for byte.

hdl/common/periph/afe2_regs_pkg.vhd and biasg_regs_pkg.vhd are TRACKED generated
sources: Genus, Xcelium and GHDL all read the RTL tree, so a package the RTL
`use`s cannot be a build output. This is the gate that keeps a tracked generated
file from being hand-edited or left behind by an .rdl change, the same role
check_memorymap_vhd_test plays for hdl/common/MemoryMap.vhd.

On failure:  tools/bin/bazel run //platform/common/python:rdl_vhdl_pkgs
"""

import difflib
import os
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

    def test_the_rtl_that_uses_each_package_is_present(self):
        """A package with no consumer is dead generated code; the table names the
           entity each one exists for, so that claim is checked rather than told."""
        for spec in rdl_vhdl.RTL_PACKAGES:
            rtl = os.path.join(REPO, spec['rtl'])
            self.assertTrue(os.path.isfile(rtl), spec['rtl'] + ' is not in the tree')
            with open(rtl) as f:
                src = f.read()
            self.assertIn('use work.%s.all;' % spec['package'], src,
                          '%s does not use %s' % (spec['rtl'], spec['package']))


if __name__ == '__main__':
    unittest.main()
