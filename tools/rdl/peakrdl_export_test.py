#!/usr/bin/env python3
"""peakrdl_export_test.py -- the tracked .rdl descriptions are valid SystemRDL
that STOCK tools consume, not just input to this repo's own emitters.

That is the whole argument for using SystemRDL rather than another table format,
so it is asserted rather than assumed: each description is exported by
peakrdl-markdown and by peakrdl-cheader, and the output must be non-empty and
must name the block's registers. If a description ever compiles only under
rdl_model.py, this test is what says so.
"""

import os
import sys
import tempfile
import unittest

REPO = os.environ.get('TEST_SRCDIR')
RDL_DIR = None
for base in filter(None, [os.path.join(REPO, '_main') if REPO else None, os.getcwd()]):
    cand = os.path.join(base, 'hdl', 'common', 'regs', 'rdl')
    if os.path.isdir(cand):
        RDL_DIR = cand
        break

BLOCKS = (
    ('uart.rdl', 'uart', ['UARTxCR', 'UARTxSR', 'UARTxBR', 'UARTxRX', 'UARTxTX']),
    ('afe2.rdl', 'afe2_site', ['AFExCR', 'AFExSR', 'AFExDATA', 'AFExSWAP']),
    ('biasg.rdl', 'biasg', ['AFExBIASG0', 'AFExBIASGCR']),
)


def _compile(fileName, top):
    from systemrdl import RDLCompiler
    rdlc = RDLCompiler()
    rdlc.compile_file(os.path.join(RDL_DIR, fileName), incl_search_paths=[RDL_DIR])
    return rdlc.elaborate(top_def_name=top)


class PeakRdlExportTest(unittest.TestCase):

    def setUp(self):
        self.assertIsNotNone(RDL_DIR, 'could not locate hdl/common/regs/rdl in the runfiles')

    def test_markdown_export(self):
        from peakrdl_markdown.exporter import MarkdownExporter
        for fileName, top, names in BLOCKS:
            root = _compile(fileName, top)
            with tempfile.TemporaryDirectory() as tmp:
                out = os.path.join(tmp, top + '.md')
                MarkdownExporter().export(root, out)
                with open(out) as f:
                    text = f.read()
            self.assertGreater(len(text), 500, fileName + ': markdown export is suspiciously short')
            for n in names:
                self.assertIn(n, text, fileName + ': ' + n + ' missing from the markdown export')

    def test_cheader_export(self):
        from peakrdl_cheader.exporter import CHeaderExporter
        for fileName, top, names in BLOCKS:
            root = _compile(fileName, top)
            with tempfile.TemporaryDirectory() as tmp:
                out = os.path.join(tmp, top + '.h')
                CHeaderExporter().export(root, out)
                with open(out) as f:
                    text = f.read()
            self.assertGreater(len(text), 500, fileName + ': C header export is suspiciously short')
            for n in names:
                self.assertIn(n, text, fileName + ': ' + n + ' missing from the C header export')


if __name__ == '__main__':
    unittest.main()
