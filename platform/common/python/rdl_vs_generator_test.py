#!/usr/bin/env python3
"""VestaRV: the .rdl descriptions and the emitted register map describe the same registers.

For a peripheral flagged rdl:true this compares the compiled .rdl against a real generation's
config/MemoryMap.json: slot map, then register, field and prose, naming divergence in either
direction. Most peripherals are built from the .rdl, so for them this is self-consistency;
the four whose geometry depends on numHarts and friends stay hand-written and independent.
"""

import json
import os
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import rdl_chip
import rdl_emit
import rdl_latex
import rdl_model

_ARGS = [a for a in sys.argv[1:] if not a.startswith('-')]
MEMORYMAP = _ARGS[0] if len(_ARGS) > 0 else None
RDL_CONFIG = _ARGS[1] if len(_ARGS) > 1 else rdl_emit.DEFAULT_CONFIG
SECTIONS = _ARGS[2] if len(_ARGS) > 2 else None
GENERATE_PY = _ARGS[3] if len(_ARGS) > 3 else os.path.join(HERE, 'generate.py')
if SECTIONS is not None and os.path.isdir(SECTIONS):
    SECTIONS = os.path.join(SECTIONS, 'include', 'PeripheralSections.tex')
sys.argv = sys.argv[:1]


def _load(path):
    with open(path) as f:
        return json.load(f)


def _templateRegisters(mm, templateName, registerPrefix=None):
    """The generator's registers for one peripheral template, name-templatised. MemoryMap.json holds
    instances while the .rdl is per template, and the register prefix is not the peripheral name,
    so the index is stripped using rdl.json's registerPrefix.
    """
    out = None
    prefix = registerPrefix if registerPrefix else templateName
    for p in mm['Peripherals']:
        if p['PeripheralTemplateName'] != templateName:
            continue
        idx = p['PeripheralName'][len(templateName) - 1:] if templateName.endswith('x') else ''
        concrete = prefix.replace('x', idx) if ('x' in prefix and idx) else None
        regs = []
        for r in p['Registers']:
            name = r['RegisterName']
            if concrete and name.startswith(concrete):
                name = prefix + name[len(concrete):]
            if concrete:
                # BIT FIELD names carry the instance index too wherever the
                # generator names a field after its register (I2C0MTX, P0IN),
                # and the .rdl is per template, so they templatise identically.
                # A field whose name merely shares the prefix's letters is
                # untouched, because the match is against the CONCRETE prefix:
                # DMAC0SRC does not start with DMA0.
                r = dict(r)
                r['BitFields'] = [
                    dict(b, BitFieldName=(prefix + b['BitFieldName'][len(concrete):]
                                          if b['BitFieldName'].startswith(concrete)
                                          else b['BitFieldName']))
                    for b in r['BitFields']]
            regs.append((name, r))
        if out is None:
            out = (p['PeripheralName'], regs)
    return out


class RdlVsGeneratorTest(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.mm = _load(MEMORYMAP)
        # Only the blocks that ARE generate.py peripherals can be graded against
        # the generated register map. The Debug Module is described here too, but
        # its registers are DMI-space and have no memory-map row to compare with.
        cls.flags = rdl_emit.memoryMapped(rdl_emit.loadFlags(RDL_CONFIG))
        if not cls.flags:
            raise Exception('no peripheral is flagged rdl:true in ' + RDL_CONFIG)
        # PER-INSTANCE RESET VALUES. A .rdl BLOCK file describes the
        # peripheral the way its RTL generics default, and two peripherals reset a
        # register differently per instance because the value arrives as a generic:
        # GPIO's RstValPx{OUT,DIR,SEL,REN,AFS} and I2C's default_SAD. Those live as
        # dynamic assignments in the top addrmap and only exist after ELABORATION,
        # so grading a block template against an instance's registers compares two
        # different things. The elaborated per-instance blocks are loaded here and
        # used wherever the instance the generator side names is one of them.
        cls.instanceBlocks = {}
        for (instName, base, flag, block, idx) in rdl_chip.bind(rdl_chip.DEFAULT_TOP, RDL_CONFIG):
            cls.instanceBlocks[(flag['name'], instName)] = block

    def _blocksByPeripheral(self):
        by = {}
        for flag in self.flags:
            block = rdl_model.loadBlock(flag['source'], flag['top'])
            by.setdefault(flag['peripheral'], []).append((flag, block))
        return by

    def _elaborated(self, flag, block, instName):
        '''The .rdl side for the INSTANCE the generator side names: the elaborated
           block when the top addrmap instantiates it, else the block template.'''
        return self.instanceBlocks.get((flag['name'], instName), block)

    def _regs(self, periph, blocks):
        """The generator's registers for `periph`, templatised with the register
           prefix its .rdl flag declares (see _templateRegisters)."""
        prefix = None
        for (flag, _) in blocks:
            prefix = prefix or flag.get('registerPrefix')
        return _templateRegisters(self.mm, periph, prefix)

    def test_every_flagged_peripheral_exists_in_the_generated_map(self):
        names = set(p['PeripheralTemplateName'] for p in self.mm['Peripherals'])
        for periph in self._blocksByPeripheral():
            self.assertIn(periph, names,
                          periph + ' is flagged rdl:true but the configuration this gate '
                          'runs against does not instantiate it; point the test at a '
                          'configuration that does.')

    def test_slot_map_matches(self):
        """The bar the task sets: .rdl offsets equal the generator's slot map."""
        for periph, blocks in self._blocksByPeripheral().items():
            inst, regs = self._regs(periph, blocks)
            genSlots = dict((n, r['RegisterMemorySlot']) for (n, r) in regs)
            rdlSlots = {}
            for (flag, block) in blocks:
                for rt in block.RegisterTemplates:
                    rdlSlots[rt.NameTemplate] = rt.RegisterMemorySlot
            self.assertEqual(sorted(rdlSlots), sorted(genSlots),
                             periph + ': the .rdl and the generator name different registers')
            for name in sorted(rdlSlots):
                self.assertEqual(rdlSlots[name], genSlots[name],
                                 '%s.%s: .rdl word slot %d, generator word slot %d'
                                 % (periph, name, rdlSlots[name], genSlots[name]))

    def test_registers_and_fields_match_in_full(self):
        """Every divergence, not the first. This gate is the list of doc-side corrections a peripheral's
        .rdl implies, and a list that stops at its first entry is not one, so the comparison
        accumulates and the assertion is made once with the whole list in the message.
        """
        bad = []
        for periph, blocks in sorted(self._blocksByPeripheral().items()):
            inst, regs = self._regs(periph, blocks)
            genByName = dict(regs)
            for (flag, block) in blocks:
                for rt in self._elaborated(flag, block, inst).RegisterTemplates:
                    where = periph + '.' + rt.NameTemplate
                    if rt.NameTemplate not in genByName:
                        bad.append(where + ': in the .rdl, not in the generated map')
                        continue
                    g = genByName[rt.NameTemplate]
                    if rt.Offset != g['Offset']:
                        bad.append('%s: byte offset .rdl 0x%X, generator 0x%X'
                                   % (where, rt.Offset, g['Offset']))
                    if rt.Size != g['Size']:
                        bad.append('%s: width .rdl %d, generator %d' % (where, rt.Size, g['Size']))
                    if rt.ResetValue != g['ResetValue']:
                        bad.append('%s: reset .rdl 0x%X, generator 0x%X'
                                   % (where, rt.ResetValue, g['ResetValue']))
                    if rt.Description != g['Description']:
                        bad.append(where + ': description')
                    bad += self._fieldDiffs(where, rt.BitFields, g['BitFields'])
        self.assertEqual([], bad,
                         'the .rdl descriptions and the generator disagree in %d places. THE RTL '
                         'IS THE AUTHORITY and every .rdl here was read out of it, so each line is '
                         'a correction the generator (and therefore the TRM register table and '
                         'MemoryMap.h) needs:\n  ' % len(bad) + '\n  '.join(bad))

    def _fieldDiffs(self, where, rdlFields, genFields):
        rdlByBits = dict(((f.MSB, f.LSB), f) for f in rdlFields)
        genByBits = dict(((f['MSB'], f['LSB']), f) for f in genFields)
        if sorted(rdlByBits) != sorted(genByBits):
            return ['%s: bit ranges .rdl %s, generator %s'
                    % (where, sorted(rdlByBits), sorted(genByBits))]
        out = []
        for bits in sorted(rdlByBits):
            r, g = rdlByBits[bits], genByBits[bits]
            tag = '%s[%d:%d]' % (where, bits[0], bits[1])
            if bool(r.Unused) != bool(g['Unused']):
                out.append(tag + ': reserved-or-not')
            if r.Name != g['BitFieldName']:
                out.append('%s: field name .rdl %s, generator %s' % (tag, r.Name, g['BitFieldName']))
            if r.Accessibility != g['Accessibility']:
                out.append('%s: access .rdl %s, generator %s'
                           % (tag, r.Accessibility, g['Accessibility']))
            if r.ResetValue != g['ResetValue']:
                out.append('%s: reset .rdl 0x%X, generator 0x%X' % (tag, r.ResetValue, g['ResetValue']))
            if r.Description != g['Description']:
                out.append(tag + ': description')
            if [tuple(v) for v in r.ValueDescriptions] != [tuple(v) for v in g['ValueDescriptions']]:
                out.append(tag + ': value descriptions')
        return out

    def test_rdl_sourced_peripherals_carry_no_generator_table(self):
        """config/rdl.json's registerSource and generate.py agree, both ways: a peripheral flagged "rdl"
        must be loaded by a _rdlRegisters() call and keep no RegisterTemplate of its own, and one
        generate.py loads from SystemRDL must be flagged. Otherwise both halves describe the registers.
        """
        if not os.path.isfile(GENERATE_PY):
            self.skipTest('generate.py not given')
        with open(GENERATE_PY) as f:
            src = f.read()
        loaded = set(re.findall(r"_rdlRegisters\(\s*'([^']+)'", src))
        flagged = set(f['peripheral'] for f in self.flags
                      if f['registerSource'] == 'rdl' and f['peripheral'])
        self.assertEqual(sorted(flagged), sorted(loaded),
                         'config/rdl.json says registerSource "rdl" for %s but generate.py '
                         'loads %s. The flag and the code must name the same peripherals.'
                         % (sorted(flagged), sorted(loaded)))
        # And no hand-written table survives for any of them. The templates are
        # built in one block per peripheral, so a RegisterTemplate naming a
        # register of an rdl-sourced peripheral is a re-introduced duplicate.
        rdlRegisters = set()
        for periph, blocks in self._blocksByPeripheral().items():
            if periph not in flagged:
                continue
            for (flag, block) in blocks:
                for rt in block.RegisterTemplates:
                    rdlRegisters.add(rt.NameTemplate)
        duplicated = sorted(set(re.findall(r"RegisterTemplate\(nameTemplate='([^']+)'", src))
                            & rdlRegisters)
        self.assertEqual([], duplicated,
                         'generate.py still builds %s by hand, and the .rdl describes the '
                         'same registers. One of the two has to go.' % duplicated)

    def test_pilot_latex_is_byte_identical(self):
        """The pilot's RDL-derived TRM tables equal the ones the generation emitted."""
        if SECTIONS is None:
            self.skipTest('no PeripheralSections.tex given')
        flag = [f for f in self.flags if f['name'] == 'UARTx']
        self.assertTrue(flag, 'the UARTx pilot is not flagged rdl:true')
        flag = flag[0]
        block = rdl_model.loadBlock(flag['source'], flag['top'])
        inst = [(p['PeripheralName'], p['BaseAddress']) for p in self.mm['Peripherals']
                if p['PeripheralTemplateName'] == 'UARTx']
        tex = rdl_latex.RdlLatex(block, flag['registerPrefix'], flag['bitFieldPrefix'],
                                 inst).RegistersTex(shortLabelOk=True)
        with open(SECTIONS) as f:
            gen = f.read()
        start = gen.index('\\section{Registers} \\label{regs:UARTx}')
        end = gen.index('\\chapter{', start)
        section = gen[start:end]
        section = section[section.index('\\begin{tabularx}'):]
        self.assertEqual(section.rstrip('\n'), tex.rstrip('\n'),
                         'the UARTx register tables the .rdl produces are not the ones the '
                         'generator emitted; the TRM chapter would not build unchanged')


if __name__ == '__main__':
    unittest.main()
