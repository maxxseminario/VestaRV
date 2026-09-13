#!/usr/bin/env python3
"""VestaRV: the SystemRDL gates fail when the register description stops matching the RTL.

Copies the tracked .rdl descriptions, changes one thing in each copy, and asserts the
corresponding comparison now reports a mismatch while the unchanged copy still passes, so the
failure is attributable to the mutation. Three mutations, one per class the gates check, all
on uart.rdl: a reset value, a storage mask and a word offset.
"""

import os
import re
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import rdl_model
import rdl_vhdl
import rdl_vs_vhdl_test as gate

REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))


def _mutate(tmp, fileName, old, new):
    """Copy every tracked .rdl into `tmp` and replace `old` with `new` in one."""
    for f in os.listdir(rdl_model.RDL_DIR):
        if f.endswith('.rdl'):
            shutil.copy(os.path.join(rdl_model.RDL_DIR, f), os.path.join(tmp, f))
    path = os.path.join(tmp, fileName)
    with open(path) as f:
        src = f.read()
    count = src.count(old)
    if count != 1:
        raise Exception('negative control: the anchor %r occurs %d times in %s; the mutation '
                        'must be unambiguous' % (old, count, fileName))
    with open(path, 'w') as f:
        f.write(src.replace(old, new, 1))
    return path


def _compile(path, top, tmp):
    return rdl_model.compileFiles([path], top=top, incdirs=[tmp])[0]


class NegativeControlTest(unittest.TestCase):

    def _run(self, fileName, top, old, new, check):
        """check(block) -> list of mismatches, run on the clean and the mutated copy."""
        with tempfile.TemporaryDirectory() as tmp:
            clean = _mutate(tmp, fileName, old, old)
            self.assertEqual(check(_compile(clean, top, tmp)), [],
                             'the UNMUTATED copy of ' + fileName + ' already disagrees with the '
                             'VHDL, so this control proves nothing')
        with tempfile.TemporaryDirectory() as tmp:
            bad = _mutate(tmp, fileName, old, new)
            try:
                mismatches = check(_compile(bad, top, tmp))
            except Exception as e:
                # Refusing to compile is the gate failing too, and earlier: a
                # width change makes the field's own reset literal the wrong
                # width. Record which way it was caught.
                sys.stderr.write('  caught at COMPILE: %s -> %s in %s (%s)\n'
                                 % (old, new, fileName, type(e).__name__))
                return
            sys.stderr.write('  caught at COMPARE: %s -> %s in %s (%s)\n'
                             % (old, new, fileName, ', '.join(mismatches) or 'none'))
            self.assertNotEqual(mismatches, [],
                                'the gate did NOT notice ' + repr(old) + ' -> ' + repr(new)
                                + ' in ' + fileName)

    def _uart(self):
        """The UART decode as the gate reads it today, which is the periph_regs reader: UART.vhd's bus
        side is an instance decoding with uart_regs_pkg's tables. The mutation is still caught,
        because the mutated description compiles in a temp directory while the tracked package does not.
        """
        return gate.READERS['uart']['read'](
            os.path.join(REPO, 'hdl', 'common', 'periph', 'UART.vhd'),
            os.path.join(REPO, 'hdl', 'common', 'MemoryMap.vhd'))

    def test_reset_value_mutation_is_caught(self):
        vhdl = self._uart()

        def check(block):
            return [rt.NameTemplate for rt in block.RegisterTemplates
                    if vhdl[rt.NameTemplate]['reset'] is not None
                    and rt.ResetValue != vhdl[rt.NameTemplate]['reset']]

        self._run('uart.rdl', 'uart', "reset = 12'h0;", "reset = 12'h1;", check)

    def test_field_width_mutation_is_caught(self):
        vhdl = self._uart()

        def check(block):
            return [rt.NameTemplate for rt in block.RegisterTemplates
                    if vhdl[rt.NameTemplate]['impl'] is not None
                    and rdl_vhdl.storageMask(rt) != vhdl[rt.NameTemplate]['impl']]

        self._run('uart.rdl', 'uart', '} BR[11:0];', '} BR[10:0];', check)

    def test_offset_mutation_is_caught(self):
        vhdl = self._uart()

        def check(block):
            return [rt.NameTemplate for rt in block.RegisterTemplates
                    if rt.RegisterMemorySlot != vhdl[rt.NameTemplate]['word']]

        self._run('uart.rdl', 'uart', 'UARTxBR_t UARTxBR @0x08;', 'UARTxBR_t UARTxBR @0x0C;', check)


if __name__ == '__main__':
    unittest.main()
