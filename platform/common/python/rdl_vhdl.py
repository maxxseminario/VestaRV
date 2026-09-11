#!/usr/bin/env python3
"""rdl_vhdl.py -- a VHDL package of one .rdl block's offsets, field ranges and
reset constants.

The package a peripheral could `use` WITHOUT CHANGING BEHAVIOUR. AFE2.vhd and
BIASG.vhd today declare their word offsets, their implemented-bit masks and their
reset tables as file-local constants, deliberately, so each keeps a single-file
closure for its bench. This package emits exactly those constants under exactly
those meanings, so adopting it is a one-line `use work.AFEx_reg_pkg.all;` plus
deleting the local copies -- and the constants it emits are checked against the
local ones by //platform/common:rdl_vs_vhdl_afe2_test, so the swap is provably
inert.

Level 2 (2026-09-10): the two packages the RTL actually `use`s are TRACKED, at
hdl/common/periph/afe2_regs_pkg.vhd and hdl/common/periph/biasg_regs_pkg.vhd,
and AFE2.vhd / BIASG.vhd have deleted their local copies. Those two carry an
extra AGGREGATE section -- the array type, the word-offset constants and the
IMPL / RSTVAL tables under the identifiers the decode already used -- so the
migration is a context clause plus a deletion and the bodies are untouched.
RTL_PACKAGES below is the table that drives it; //platform/common:rdl_vhdl_pkg_test
regenerates both and fails if the tracked file differs by one byte, and
//platform/common:rdl_pkg_vs_legacy_test compares every emitted value against the
hand-written constants as they stood before the migration.

What is emitted per register:
    <REG>_WORD    natural, the word offset inside the peripheral's sub-slot
    <REG>_ADDR    natural, the byte offset
    <REG>_RESET   std_logic_vector, the reset word
    <REG>_IMPL    std_logic_vector, the software-writable storage mask
and per field:
    <FIELD>_MSB / <FIELD>_LSB   natural
    <FIELD>_RESET               std_logic_vector of the field's own width

`_IMPL` is the mask of bits that hold a software-written flop: a field counts
when software may write it (`sw` includes w), hardware does not drive it
(`hw = r`), and it is not a single-pulse strobe. That is the definition AFE2.vhd
and BIASG.vhd use for their IMPL tables, which is why the two agree bit for bit.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# The generator access codes whose bits are software-written storage.
_STORED_ACCESS = ('rw', 'rw0', 'rw1', 'w', 'w0')
# ... minus the ones hardware owns. A write-1-to-clear flag is set by hardware,
# so its bit is not a software register bit even though software writes it.
_HW_OWNED_ACCESS = ('rw0', 'rw1')


def storageMask(rt):
    """The mask of bits that hold a software-written flop in this register."""
    mask = 0
    for bf in rt.BitFields:
        if bf.Unused:
            continue
        if bf.Accessibility not in _STORED_ACCESS:
            continue
        if bf.Accessibility in _HW_OWNED_ACCESS:
            continue
        if bf.Accessibility in ('w', 'w0') and _isSinglePulse(bf):
            continue
        mask |= bf.BitMask
    return mask


def _isSinglePulse(bf):
    """A `w1` field is the generator's spelling of a self-clearing strobe."""
    return bf.Accessibility == 'w1'


# ---------------------------------------------------------------------------
# The TRACKED packages, and the aggregate section that lets the RTL adopt them
# without touching its body.
#
# AFE2.vhd and BIASG.vhd used to declare, file-locally, a word-offset constant
# per register, an array type over those words and two tables indexed by it
# (IMPL, the software-writable storage mask, and RSTVAL, the reset word). The
# scalar constants above already carry every value in those tables; what the
# aggregate section adds is the SHAPE -- the same type under the same name, and
# the same table under the same name -- so the migration is a `use` clause and a
# deletion, with no edit to a single assignment.
#
# Two spellings, because the two decodes index differently and neither was going
# to be bent to suit a generator:
#   keyed      AFE2: `IMPL(W_MUX)`, a named-association aggregate over absolute
#              word offsets, which is what a nine-register file with a sparse
#              reset table reads best as.
#   positional BIASG: `IMPL(sel)` where `sel = idx - WORD_BASE`, so the table is
#              five entries in slot order and the index is RELATIVE. Its word
#              constants are therefore emitted as IDX_* (relative, what indexes
#              the array) and never as W_* (absolute, what the bus decodes) --
#              one identifier per meaning, so the two cannot be confused.
# ---------------------------------------------------------------------------

RTL_PACKAGES = (
    {
        'package': 'afe2_regs_pkg',
        'file': 'hdl/common/periph/afe2_regs_pkg.vhd',
        'source': 'afe2.rdl',
        'top': 'afe2_site',
        'rtl': 'hdl/common/periph/AFE2.vhd',
    },
    {
        'package': 'biasg_regs_pkg',
        'file': 'hdl/common/periph/biasg_regs_pkg.vhd',
        'source': 'biasg.rdl',
        'top': 'biasg',
        'rtl': 'hdl/common/periph/BIASG.vhd',
    },
)

# Keyed by the .rdl addrmap (block.Name). A block with no entry gets the scalar
# constants only, which is what every out/rdl/ emission has always been.
_AGGREGATE = {
    'afe2_site': {
        'shortPrefix': 'AFEx',
        'indexPrefix': 'W_',
        'countName': 'NSTORED',
        'arrayType': 'reg_arr_t',
        'keyed': True,
        'wordBaseName': None,
        'rtl': 'AFE2.vhd',
    },
    'biasg': {
        'shortPrefix': 'AFEx',
        'indexPrefix': 'IDX_',
        'countName': 'N_WORDS',
        'arrayType': 'reg_array',
        'keyed': False,
        'wordBaseName': 'WORD_BASE_DEFAULT',
        'rtl': 'BIASG.vhd',
    },
}


def singlePulseMask(rt):
    """The mask of bits that are write-1 strobes: written by software, stored by
       nothing, and therefore absent from the storage mask above."""
    mask = 0
    for bf in rt.BitFields:
        if bf.Unused:
            continue
        if _isSinglePulse(bf):
            mask |= bf.BitMask
    return mask


def _hex32(value, width):
    return 'x"' + format(value & ((1 << width) - 1), '0' + str((width + 3) // 4) + 'X') + '"'


def _shortName(rt, prefix):
    n = rt.NameTemplate
    return n[len(prefix):] if prefix and n.startswith(prefix) else n


def _aggregateLines(block):
    """The array type, index constants and IMPL / RSTVAL tables, under the
       identifiers the peripheral's decode already uses."""
    spec = _AGGREGATE.get(block.Name)
    if spec is None:
        return []
    regs = list(block.RegisterTemplates)
    words = [rt.Offset // 4 for rt in regs]
    base = min(words)
    if words != list(range(base, base + len(regs))):
        raise Exception('rdl_vhdl: %s does not occupy a contiguous run of words (%s); the '
                        'aggregate tables index a dense array and cannot describe a hole.'
                        % (block.Name, words))
    width = regs[0].Size
    for rt in regs:
        if rt.Size != width:
            raise Exception('rdl_vhdl: %s mixes register widths (%d and %d); the aggregate '
                            'tables are one array of one width.' % (block.Name, width, rt.Size))
    names = [_shortName(rt, spec['shortPrefix']) for rt in regs]
    idx = [w if spec['keyed'] else w - base for w in words]
    keyName = [spec['indexPrefix'] + n for n in names]

    L = []
    L.append('    -- ' + spec['rtl'] + "'s own decode identifiers. The index constants, the")
    L.append('    -- array type over them and the two tables indexed by it, so the entity')
    L.append('    -- declares none of them itself and no assignment in its body changes.')
    for k, i in zip(keyName, idx):
        L.append('    constant %-24s : natural := %d;' % (k, i))
    L.append('    constant %-24s : natural := %d;' % (spec['countName'], len(regs)))
    if spec['wordBaseName']:
        L.append('    constant %-24s : natural := %d;   -- first word inside the host sub-slot'
                 % (spec['wordBaseName'], base))
    L.append('')
    L.append('    type %s is array(0 to %s-1) of std_logic_vector(%d downto 0);'
             % (spec['arrayType'], spec['countName'], width - 1))
    L.append('')
    for constName, valueOf, note in (
            ('IMPL', storageMask,
             'bits that hold a software-written flop; everything else reads 0 and drops writes'),
            ('RSTVAL', lambda rt: rt.ResetValue or 0, 'reset word')):
        L.append('    -- ' + note)
        L.append('    constant %-8s : %s := (' % (constName, spec['arrayType']))
        rows = []
        for rt, k in zip(regs, keyName):
            v = _hex32(valueOf(rt), width)
            rows.append(('        %-14s => %s' % (k, v)) if spec['keyed'] else ('        ' + v))
        L.append((',' + chr(10)).join(rows) + ');')
        L.append('')
    sp = [(rt, singlePulseMask(rt)) for rt in regs]
    if any(m for _, m in sp):
        L.append('    -- Write-1 strobes: software writes them, nothing stores them, so they are')
        L.append('    -- absent from IMPL. <FIELD>_LSB above is the bit each one occupies.')
        for rt, m in sp:
            if not m:
                continue
            L.append('    constant %-24s : %s := %s;'
                     % (rt.NameTemplate + '_SINGLEPULSE',
                        'std_logic_vector(%d downto 0)' % (width - 1), _hex32(m, width)))
        L.append('')
    return L


def _firstSentence(text):
    """The leading sentence of a description. Splitting on '.' alone cuts
       `610.35 uV per code` in half, so a period between two digits does not end
       a sentence here."""
    m = re.split(r'(?<!\d)\.(?!\d)', text, 1)
    return m[0].strip()


def _slv(value, width):
    return '"' + format(value & ((1 << width) - 1), '0' + str(width) + 'b') + '"'


def emitString(block, packageName=None):
    pkg = packageName or (block.Name + '_reg_pkg')
    L = []
    L.append('-- =============================================================================')
    L.append('-- ' + pkg + '.vhd: GENERATED from hdl/common/periph/rdl/ by')
    L.append('-- platform/common/python/rdl_vhdl.py. DO NOT EDIT THIS FILE.')
    L.append('--')
    L.append('--   regenerate:  tools/bin/bazel run //platform/common/python:rdl_vhdl_pkgs')
    L.append('--   gates:       //platform/common:rdl_vhdl_pkg_test    tracked == regenerated')
    L.append('--                //platform/common:rdl_pkg_vs_legacy_test  == the hand-written')
    L.append('--                                                       constants it replaced')
    L.append('--                //platform/common:rdl_vs_vhdl_afe2_test / _biasg_test')
    L.append('--')
    L.append('-- ' + (block.Description or block.Name))
    L.append('--')
    L.append('-- <REG>_WORD is the word offset inside the peripheral sub-slot, <REG>_ADDR the')
    L.append('-- byte offset, <REG>_RESET the reset word and <REG>_IMPL the mask of bits that')
    L.append('-- hold a software-written flop (hardware-owned status and single-pulse strobes')
    L.append('-- are excluded, which is the same rule the hand-written IMPL tables use).')
    L.append('-- =============================================================================')
    L.append('')
    L.append('library ieee;')
    L.append('use ieee.std_logic_1164.all;')
    L.append('')
    L.append('package ' + pkg + ' is')
    L.append('')
    for rt in block.RegisterTemplates:
        n = rt.NameTemplate
        w = rt.Size
        L.append('    -- ' + n + (': ' + _firstSentence(rt.Description) if rt.Description else ''))
        L.append('    constant %-24s : natural := %d;' % (n + '_WORD', rt.Offset // 4))
        L.append('    constant %-24s : natural := %d;' % (n + '_ADDR', rt.Offset))
        L.append('    constant %-24s : std_logic_vector(%d downto 0) := %s;'
                 % (n + '_RESET', w - 1, _slv(rt.ResetValue or 0, w)))
        L.append('    constant %-24s : std_logic_vector(%d downto 0) := %s;'
                 % (n + '_IMPL', w - 1, _slv(storageMask(rt), w)))
        for bf in rt.BitFields:
            if bf.Unused:
                continue
            L.append('    constant %-24s : natural := %d;' % (bf.Name + '_MSB', bf.MSB))
            L.append('    constant %-24s : natural := %d;' % (bf.Name + '_LSB', bf.LSB))
            L.append('    constant %-24s : std_logic_vector(%d downto 0) := %s;'
                     % (bf.Name + '_RESET', bf.Size - 1, _slv(bf.ResetValue, bf.Size)))
        L.append('')
    L.extend(_aggregateLines(block))
    L.append('end package ' + pkg + ';')
    L.append('')
    return '\n'.join(L)


def emit(block, outPath, packageName=None):
    with open(outPath, 'w') as f:
        f.write(emitString(block, packageName))
    return outPath
