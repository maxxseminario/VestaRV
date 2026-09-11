#!/usr/bin/env python3
"""rdl_pkg_vs_legacy_test.py -- the generated register packages carry exactly the
constants AFE2.vhd and BIASG.vhd declared by hand before the SystemRDL level-2
move (2026-09-10, report R6).

WHY THIS TEST EXISTS AND WHY IT IS NOT REDUNDANT. After the move, three things
claim the two entities decode the same registers they always did:

  rdl_vs_vhdl_afe2_test / _biasg_test   the .rdl equals the decode
  rdl_vhdl_pkg_test                     the tracked package equals a fresh emission
  AFE2_tb, the elaboration gates         the design still behaves and still binds

The first two now share a source: the package IS the .rdl, compiled. Together
they cannot catch a value that was wrong in the .rdl from the start, because the
decode no longer holds an independent copy to disagree with.

This test is that independent copy, frozen. Every number below was transcribed
from the working tree as it stood at
    AFE2.vhd   md5 e0d5ede146964e772d5cf9f04371c99f
    BIASG.vhd  md5 50728802b41e4f0fdbb4235331a9b857
i.e. the last revision in which the entities declared their own W_* / IMPL /
RSTVAL tables and wrote their field slices as bit literals. It reads the TRACKED
package files -- the artifact the RTL actually compiles -- and grades them
constant by constant.

If this test ever fails, the question is not which side to edit. The frozen
column is what silicon was specified against; a deliberate register change moves
it, with the change written down here, and nothing else may.
"""

import json
import os
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
PERIPH = os.path.join(REPO, 'hdl', 'common', 'periph')
REGS_VHDL = os.path.join(REPO, 'hdl', 'common', 'regs', 'vhdl')

# ---------------------------------------------------------------------------
# The frozen tables. AFE2.vhd, pre-migration:
#
#   constant W_CR ... W_SWAP, NSTORED = 9
#   constant IMPL   : reg_arr_t := (W_CR => x"0000FFF3", ... W_SWAP => x"FFFF0FFF");
#   constant RSTVAL : reg_arr_t := (W_CR => x"00000700", W_MUX => x"000000F0",
#                                   others => (others => '0'));
#
# and the bit literals its body used, register by register.
# ---------------------------------------------------------------------------

AFE2_WORDS = {
    'W_CR': 0, 'W_SR': 1, 'W_DATA': 2, 'W_TIA': 3, 'W_DACVP': 4,
    'W_DACVCM': 5, 'W_BIAS': 6, 'W_MUX': 7, 'W_SWAP': 8,
}
AFE2_NSTORED = 9
AFE2_IMPL = {
    'W_CR': 0x0000FFF3, 'W_SR': 0x00000000, 'W_DATA': 0x00000000,
    'W_TIA': 0x000003FF, 'W_DACVP': 0x00001FFF, 'W_DACVCM': 0x00001FFF,
    'W_BIAS': 0x0000003F, 'W_MUX': 0x000000FF, 'W_SWAP': 0xFFFF0FFF,
}
AFE2_RSTVAL = {
    'W_CR': 0x00000700, 'W_SR': 0, 'W_DATA': 0, 'W_TIA': 0, 'W_DACVP': 0,
    'W_DACVCM': 0, 'W_BIAS': 0, 'W_MUX': 0x000000F0, 'W_SWAP': 0,
}
# field -> (msb, lsb, reset). The slices AFE2.vhd's body wrote as literals; the
# read-only SR/DATA fields are the bit indices its read mux drove.
AFE2_FIELDS = {
    'AFEEN':         (0, 0, 0),
    'AFECONT':       (1, 1, 0),
    'AFESTART':      (2, 2, 0),
    'AFESYNC':       (3, 3, 0),
    'AFESYNCEN':     (4, 4, 0),
    'AFEDRDYIE':     (5, 5, 0),
    'AFEERRIE':      (6, 6, 0),
    'AFESWAPEN':     (7, 7, 0),
    'AFESAMPLESTEP': (11, 8, 7),
    'AFECLKDIV':     (15, 12, 0),
    'AFEBUSY':       (0, 0, 0),
    'AFEDRDY':       (1, 1, 0),
    'AFEOVF':        (2, 2, 0),
    'AFEREL':        (3, 3, 0),
    'AFETO':         (4, 4, 0),
    'AFECNT':        (11, 8, 0),
    'AFECODE':       (9, 0, 0),
    'AFESELTAG':     (13, 10, 0),
    'AFEPHTAG':      (14, 14, 0),
    'AFEVALID':      (15, 15, 0),
    'AFERESEN':      (5, 0, 0),
    'AFETHEN':       (9, 6, 0),
    'AFEVP':         (11, 0, 0),
    'AFEVPEN':       (12, 12, 0),
    'AFEVCM':        (11, 0, 0),
    'AFEVCMEN':      (12, 12, 0),
    'AFEBIASADJ':    (5, 0, 0),
    'AFEADCSEL':     (3, 0, 0),
    'AFEATPSEL':     (7, 4, 0xF),
    'AFEVP2':        (11, 0, 0),
    'AFEPERIOD':     (31, 16, 0),
}
# CR bits 2 and 3 (START, SYNC) are the pulses AFE2.vhd's comment named and its
# IMPL mask cleared.
AFE2_SINGLEPULSE = {'AFExCR_SINGLEPULSE': 0x0000000C}

# BIASG.vhd, pre-migration: N_WORDS = 5, the generic default WORD_BASE = 9, the
# two positional five-entry tables, and the slices of its output assignments.
BIASG_N_WORDS = 5
BIASG_WORD_BASE = 9
BIASG_IMPL = [0x00003FFF, 0x00003FFF, 0x00003FFF, 0x00003FFF, 0x00003F0F]
BIASG_RSTVAL = [0, 0, 0, 0, 0]
BIASG_IDX = {'IDX_BIASG0': 0, 'IDX_BIASG1': 1, 'IDX_BIASG2': 2,
             'IDX_BIASG3': 3, 'IDX_BIASGCR': 4}
BIASG_FIELDS = {
    'AFEBGCODE0':    (13, 0, 0),
    'AFEBGCODE1':    (13, 0, 0),
    'AFEBGCODE2':    (13, 0, 0),
    'AFEBGCODE3':    (13, 0, 0),
    'AFEBGUSEDAC':   (0, 0, 0),
    'AFEBGENGEN':    (1, 1, 0),
    'AFEBGENBUFINT': (2, 2, 0),
    'AFEBGEN':       (3, 3, 0),
    'AFEBGADJ':      (13, 8, 0),
}


# ---------------------------------------------------------------------------
# Reading the package. The TRACKED text is parsed, not the emitter re-run: the
# file the RTL compiles is the thing under test.
# ---------------------------------------------------------------------------

def _read(path):
    with open(path) as f:
        return f.read()


def _naturals(src):
    return dict((m.group(1), int(m.group(2)))
                for m in re.finditer(r'constant\s+(\w+)\s*:\s*natural\s*:=\s*(\d+);', src))


def _vectors(src):
    """{name: int} for every `constant NAME : std_logic_vector(...) := "..."|x"...";`"""
    out = {}
    for m in re.finditer(r'constant\s+(\w+)\s*:\s*std_logic_vector\([^)]*\)\s*:=\s*'
                         r'(?:x"([0-9A-Fa-f]+)"|"([01]+)");', src):
        out[m.group(1)] = int(m.group(2), 16) if m.group(2) else int(m.group(3), 2)
    return out


def _table(src, constName, arrayType, keyed):
    m = re.search(r'constant\s+' + constName + r'\s*:\s*' + arrayType + r'\s*:=\s*\((.*?)\);',
                  src, re.S)
    if m is None:
        raise Exception('no `constant %s : %s` aggregate' % (constName, arrayType))
    body = m.group(1)
    if keyed:
        return dict((k, int(v, 16)) for k, v in
                    re.findall(r'(\w+)\s*=>\s*x"([0-9A-Fa-f]+)"', body))
    return [int(v, 16) for v in re.findall(r'x"([0-9A-Fa-f]+)"', body)]


class TestAfe2Package(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.src = _read(os.path.join(REGS_VHDL, 'afe2_regs_pkg.vhd'))
        cls.nat = _naturals(cls.src)
        cls.vec = _vectors(cls.src)

    def test_word_offsets(self):
        for name, want in sorted(AFE2_WORDS.items()):
            self.assertIn(name, self.nat, name + ' is absent from afe2_regs_pkg')
            self.assertEqual(self.nat[name], want, name)
        self.assertEqual(self.nat.get('NSTORED'), AFE2_NSTORED, 'NSTORED')

    def test_impl_table(self):
        self.assertEqual(_table(self.src, 'IMPL', 'reg_arr_t', True), AFE2_IMPL)

    def test_reset_table(self):
        self.assertEqual(_table(self.src, 'RSTVAL', 'reg_arr_t', True), AFE2_RSTVAL)

    def test_per_register_scalars_agree_with_the_tables(self):
        """<REG>_WORD/_IMPL/_RESET are the same numbers as the aggregates."""
        short = dict((w[2:], w) for w in AFE2_WORDS)   # CR -> W_CR
        for name in AFE2_WORDS:
            reg = 'AFEx' + name[2:]
            self.assertEqual(self.nat[reg + '_WORD'], AFE2_WORDS[name], reg + '_WORD')
            self.assertEqual(self.nat[reg + '_ADDR'], 4 * AFE2_WORDS[name], reg + '_ADDR')
            self.assertEqual(self.vec[reg + '_IMPL'], AFE2_IMPL[name], reg + '_IMPL')
            self.assertEqual(self.vec[reg + '_RESET'], AFE2_RSTVAL[name], reg + '_RESET')
        self.assertEqual(len(short), AFE2_NSTORED)

    def test_field_ranges_and_resets(self):
        for field, (msb, lsb, reset) in sorted(AFE2_FIELDS.items()):
            self.assertIn(field + '_MSB', self.nat, field + ' is absent from afe2_regs_pkg')
            self.assertEqual(self.nat[field + '_MSB'], msb, field + '_MSB')
            self.assertEqual(self.nat[field + '_LSB'], lsb, field + '_LSB')
            self.assertEqual(self.vec[field + '_RESET'], reset, field + '_RESET')

    def test_singlepulse_bits(self):
        for name, want in sorted(AFE2_SINGLEPULSE.items()):
            self.assertEqual(self.vec.get(name), want, name)
        # and every singlepulse bit is absent from the storage mask it sits in
        self.assertEqual(AFE2_IMPL['W_CR'] & AFE2_SINGLEPULSE['AFExCR_SINGLEPULSE'], 0)

    def test_no_field_is_missing(self):
        """Every <FIELD>_MSB the package emits is in the frozen table: a field the
           .rdl grew that the decode never had would show up here."""
        emitted = set(k[:-4] for k in self.nat if k.endswith('_MSB'))
        self.assertEqual(sorted(emitted), sorted(AFE2_FIELDS))


class TestBiasgPackage(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.src = _read(os.path.join(REGS_VHDL, 'biasg_regs_pkg.vhd'))
        cls.nat = _naturals(cls.src)
        cls.vec = _vectors(cls.src)

    def test_shape(self):
        self.assertEqual(self.nat.get('N_WORDS'), BIASG_N_WORDS, 'N_WORDS')
        self.assertEqual(self.nat.get('WORD_BASE_DEFAULT'), BIASG_WORD_BASE, 'WORD_BASE_DEFAULT')
        for name, want in sorted(BIASG_IDX.items()):
            self.assertEqual(self.nat.get(name), want, name)

    def test_impl_and_reset_tables(self):
        self.assertEqual(_table(self.src, 'IMPL', 'reg_array', False), BIASG_IMPL)
        self.assertEqual(_table(self.src, 'RSTVAL', 'reg_array', False), BIASG_RSTVAL)

    def test_absolute_words_follow_the_base(self):
        names = ['AFExBIASG0', 'AFExBIASG1', 'AFExBIASG2', 'AFExBIASG3', 'AFExBIASGCR']
        for i, reg in enumerate(names):
            self.assertEqual(self.nat[reg + '_WORD'], BIASG_WORD_BASE + i, reg + '_WORD')
            self.assertEqual(self.vec[reg + '_IMPL'], BIASG_IMPL[i], reg + '_IMPL')
            self.assertEqual(self.vec[reg + '_RESET'], BIASG_RSTVAL[i], reg + '_RESET')

    def test_field_ranges_and_resets(self):
        for field, (msb, lsb, reset) in sorted(BIASG_FIELDS.items()):
            self.assertIn(field + '_MSB', self.nat, field + ' is absent from biasg_regs_pkg')
            self.assertEqual(self.nat[field + '_MSB'], msb, field + '_MSB')
            self.assertEqual(self.nat[field + '_LSB'], lsb, field + '_LSB')
            self.assertEqual(self.vec[field + '_RESET'], reset, field + '_RESET')

    def test_no_field_is_missing(self):
        emitted = set(k[:-4] for k in self.nat if k.endswith('_MSB'))
        self.assertEqual(sorted(emitted), sorted(BIASG_FIELDS))

    def test_no_singlepulse(self):
        """BIASG has no write-1 strobe, so the emitter must produce no mask."""
        self.assertEqual([k for k in self.vec if k.endswith('_SINGLEPULSE')], [])


class TestRtlAdoptedThePackages(unittest.TestCase):
    """The entities `use` the packages and no longer declare the constants: the
       whole point of the frozen table is that exactly one copy is left."""

    def test_afe2(self):
        src = _read(os.path.join(PERIPH, 'AFE2.vhd'))
        self.assertIn('use work.afe2_regs_pkg.all;', src)
        for gone in (r'constant\s+W_CR\s*:', r'constant\s+IMPL\s*:', r'constant\s+RSTVAL\s*:',
                     r'type\s+reg_arr_t\s+is'):
            self.assertIsNone(re.search(gone, src),
                              'AFE2.vhd still declares ' + gone + ' locally')

    def test_biasg(self):
        src = _read(os.path.join(PERIPH, 'BIASG.vhd'))
        self.assertIn('use work.biasg_regs_pkg.all;', src)
        for gone in (r'constant\s+N_WORDS\s*:', r'constant\s+IMPL\s*:',
                     r'constant\s+RSTVAL\s*:', r'type\s+reg_array\s+is'):
            self.assertIsNone(re.search(gone, src),
                              'BIASG.vhd still declares ' + gone + ' locally')


# ---------------------------------------------------------------------------
# THE OTHER TWENTY-TWO (report R8a, 2026-09-11).
#
# AFE2 and BIASG are transcribed above, by hand, because they migrated first and
# their frozen column had to be read out of a revision that no longer exists in
# the working tree. Twenty-two hand-transcribed tables would not have been read
# by anyone, so the rest are in rdl_legacy_constants.json, written ONCE by
# platform/common/python/rdl_legacy_snapshot.py before any of them migrated.
#
# READ A FAILURE ACCORDING TO WHICH HALF FAILED. `decodeConstants` was read out
# of the RTL text (a local SLOT_*, the memory-map package's RegSlot*, NPU's
# MmrAddr*, irq_router's W_*) and is an independent copy in the same sense the
# AFE2 table above is. `registers` and `fields` were frozen from the emission at
# that date, after reports R2/R3 graded every .rdl against its decode: they are
# independent in TIME rather than in source, and what they catch is an .rdl edit
# that moved a register nobody meant to move.
#
# The snapshot is NEVER regenerated by a gate. A deliberate register change edits
# it in the same commit as the .rdl, and nothing else may.
# ---------------------------------------------------------------------------

LEGACY_JSON = os.path.join(HERE, 'rdl_legacy_constants.json')


def _legacy():
    with open(LEGACY_JSON) as f:
        return json.load(f)


class TestFrozenSnapshotIsPresent(unittest.TestCase):

    def test_every_block_has_a_tracked_package(self):
        blocks = _legacy()['blocks']
        self.assertEqual(len(blocks), 22,
                         'the snapshot must carry all twenty-two peripherals')
        for name, entry in sorted(blocks.items()):
            self.assertTrue(os.path.isfile(os.path.join(REGS_VHDL, name + '.vhd')),
                            name + '.vhd is not in hdl/common/regs/vhdl')
            self.assertTrue(os.path.isfile(os.path.join(REPO, entry['rtl'])),
                            entry['rtl'] + ' is not in the tree')


class LegacyBlockTest(unittest.TestCase):
    """Base class; one subclass per block is generated below so a failure names
       the peripheral instead of a dictionary key."""

    PACKAGE = None

    @classmethod
    def setUpClass(cls):
        if cls.PACKAGE is None:
            raise unittest.SkipTest('base class')
        cls.entry = _legacy()['blocks'][cls.PACKAGE]
        cls.src = _read(os.path.join(REGS_VHDL, cls.PACKAGE + '.vhd'))
        cls.nat = _naturals(cls.src)
        cls.vec = _vectors(cls.src)

    def test_decode_constants(self):
        """The word constants the decode names, as the RTL declared them before
           the migration. This is the leg that does not run through SystemRDL."""
        for ident, (want, where) in sorted(self.entry['decodeConstants'].items()):
            self.assertIn(ident, self.nat,
                          '%s does not emit %s, which %s decodes with'
                          % (self.PACKAGE, ident, self.entry['rtl']))
            self.assertEqual(self.nat[ident], want,
                             '%s: %s is %d, frozen at %d from %s'
                             % (self.PACKAGE, ident, self.nat[ident], want, where))

    def test_register_words_resets_and_masks(self):
        for name, row in sorted(self.entry['registers'].items()):
            for key, table in (('word', self.nat), ('addr', self.nat),
                               ('reset', self.vec), ('impl', self.vec)):
                want = row[key]
                const = name + '_' + key.upper()
                if want is None:
                    self.assertNotIn(const, table,
                                     '%s emits %s, which the frozen table does not carry; a '
                                     'configuration-dependent constant has become '
                                     'configuration-independent, or the reverse.'
                                     % (self.PACKAGE, const))
                    continue
                self.assertIn(const, table, '%s does not emit %s' % (self.PACKAGE, const))
                self.assertEqual(table[const], want,
                                 '%s: %s is 0x%X, frozen at 0x%X'
                                 % (self.PACKAGE, const, table[const], want))

    def test_field_ranges_and_resets(self):
        for name, row in sorted(self.entry['fields'].items()):
            self.assertIn(name + '_MSB', self.nat,
                          '%s does not emit %s' % (self.PACKAGE, name))
            self.assertEqual(self.nat[name + '_MSB'], row['msb'], name + '_MSB')
            self.assertEqual(self.nat[name + '_LSB'], row['lsb'], name + '_LSB')
            if row['reset'] is None:
                # The field carries its register's name, so the register's own
                # _RESET is the only one emitted; see rdl_vhdl._registerGroups.
                continue
            self.assertEqual(self.vec.get(name + '_RESET'), row['reset'], name + '_RESET')

    def test_no_field_appeared_or_vanished(self):
        emitted = set(k[:-4] for k in self.nat if k.endswith('_MSB'))
        self.assertEqual(sorted(emitted), sorted(self.entry['fields']),
                         '%s emits a different field set than was frozen' % self.PACKAGE)

    def test_no_register_appeared(self):
        emitted = set(k[:-5] for k in self.nat if k.endswith('_WORD'))
        frozen = set(n for n, row in self.entry['registers'].items() if row['word'] is not None)
        self.assertEqual(sorted(emitted), sorted(frozen),
                         '%s emits a different set of word offsets than was frozen'
                         % self.PACKAGE)


def _makeLegacyTests():
    for package in sorted(_legacy()['blocks']):
        name = 'Test' + ''.join(p.capitalize() for p in package.split('_')[:-2])
        globals()[name] = type(name, (LegacyBlockTest,), {'PACKAGE': package})


_makeLegacyTests()



if __name__ == '__main__':
    unittest.main()
