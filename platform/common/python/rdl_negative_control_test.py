#!/usr/bin/env python3
"""rdl_negative_control_test.py -- the SystemRDL gates fail when the register
description stops matching the RTL.

A gate nobody has watched fail is a gate nobody should trust. This one takes the
tracked .rdl descriptions, copies them, changes ONE thing in each copy, and
asserts that the comparison rdl_vs_vhdl_test performs on that thing now reports
a mismatch -- and that the same comparison on the UNCHANGED copy passes, so the
failure is attributable to the mutation and not to the copying.

Three mutations, one per class of thing the gates check. All three are on
uart.rdl, the pilot block, because it is the one whose reader states a word
offset, a reset AND a storage mask:

    reset value    uart.rdl UARTxBR.BR reset 0 -> 1, against UART.vhd's reset
                   branch, which clears UART_BR
    storage mask   uart.rdl UARTxBR.BR [11:0] -> [10:0], against UART.vhd's
                   signal UART_BR : std_logic_vector(11 downto 0)
    word offset    uart.rdl UARTxBR 0x08 -> 0x0C, against RegSlotUARTxBR
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
        return gate.readUart(os.path.join(REPO, 'hdl', 'common', 'periph', 'UART.vhd'),
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
        vhdl = gate.readUart(os.path.join(REPO, 'hdl', 'common', 'periph', 'UART.vhd'),
                             os.path.join(REPO, 'hdl', 'common', 'MemoryMap.vhd'))

        def check(block):
            return [rt.NameTemplate for rt in block.RegisterTemplates
                    if rt.RegisterMemorySlot != vhdl[rt.NameTemplate]['word']]

        self._run('uart.rdl', 'uart', 'UARTxBR_t UARTxBR @0x08;', 'UARTxBR_t UARTxBR @0x0C;', check)


if __name__ == '__main__':
    unittest.main()
