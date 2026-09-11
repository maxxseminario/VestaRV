#!/usr/bin/env python3
"""The SystemRDL toolchain is importable at the pinned versions.

Run this first when anything under tools/rdl or platform/common/python/rdl_*.py
misbehaves: it separates "the hermetic wheels are not there" from "our code is
wrong". The versions are asserted, not merely printed, so a lock-file bump that
was never meant to happen fails here rather than in a downstream emitter.
"""

import sys
import unittest

EXPECTED = {
    'systemrdl': '1.32.2',
    'peakrdl_cheader': '1.1.0',
    'peakrdl_markdown': '1.0.3',
}


class ToolchainSmokeTest(unittest.TestCase):

    def test_compiler_imports_and_compiles(self):
        from systemrdl import RDLCompiler
        rdlc = RDLCompiler()
        self.assertTrue(hasattr(rdlc, 'compile_file'))

    def test_exporters_import(self):
        import peakrdl_cheader.exporter  # noqa: F401
        import peakrdl_markdown.exporter  # noqa: F401

    def test_versions_are_the_pinned_ones(self):
        from importlib.metadata import version
        for dist, want in (('systemrdl-compiler', EXPECTED['systemrdl']),
                           ('peakrdl-cheader', EXPECTED['peakrdl_cheader']),
                           ('peakrdl-markdown', EXPECTED['peakrdl_markdown'])):
            self.assertEqual(version(dist), want, dist + ' is not the pinned version')

    def test_interpreter_is_hermetic_311(self):
        self.assertEqual(sys.version_info[:2], (3, 11))


if __name__ == '__main__':
    unittest.main()
