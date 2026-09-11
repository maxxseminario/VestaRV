#!/usr/bin/env python3
"""rdl_cheader.py -- the MemoryMap.h fragment of an .rdl block.

Byte-identical to the "Register Offsets and Bit Fields" section
ChipGenerator.generateCHeader emits for a peripheral today, because it is the
same loop over the same objects with the same TabbedTable: `<REG>_OFFSET`,
`<REG>_PTR(_<PERIPH>_BASE)`, then `<FIELD>_BIT`/`<FIELD>_MASK` plus `<FIELD>_LSB`
and one `#define` per NAMED value description. Hex width follows the register
size (2 / 4 / 8 digits), and a field whose name equals the register's is skipped,
as it is there -- the struct member covers it.

Reset values are NOT in the tracked header today. They are emitted here as a
separate, clearly delimited `<REG>_RESET` block, because a firmware writer who
has to restore a register after a soft re-init currently has to read the TRM for
values the generator already knows (AFExCR resets to 0x00000700, AFExMUX to
0x000000F0, and getting either wrong parks a site on the shared test pads).
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from TabbedTable import TabbedTable


def _fmthex(num, minDigits=4):
    return '0x' + ('{:0' + str(minDigits) + 'x}').format(num).upper()


def _fmtint(num, minDigits=2):
    return ('{:0' + str(minDigits) + 'd}').format(num)


def _hexDigits(size):
    return {8: 2, 16: 4}.get(size, 8)


def registerTex(rt, peripheralName):
    """The header lines for one register template."""
    t = TabbedTable()
    t.AddLine('// ' + rt.NameTemplate)
    t.AddRow(['#define ' + rt.NameTemplate + '_OFFSET', '(' + str(rt.Offset) + ')'])
    t.AddRow(['#define ' + rt.NameTemplate + '_PTR(_' + peripheralName + '_BASE)',
              'MMR_{:02}_PTR(_'.format(rt.Size) + peripheralName + '_BASE, '
              + rt.NameTemplate + '_OFFSET)'])
    t.AddBlankLine()
    s = t.ToString()

    t = TabbedTable()
    hexDigits = _hexDigits(rt.Size)
    bfDefines = 0
    for bf in rt.BitFields:
        if bf.Unused is True:
            continue
        if bf.Size == 1:
            if bf.SameNameAsRegister:
                continue
            t.AddRow(['#define ' + bf.Name + '_BIT', '(' + _fmthex(bf.BitMask, minDigits=hexDigits) + ')',
                      '// bit ' + str(bf.MSB)])
            t.AddRow(['#define ' + bf.Name + '_LSB', '(' + _fmtint(bf.LSB, minDigits=1) + ')'])
            bfDefines += 1
        else:
            if not bf.SameNameAsRegister:
                t.AddRow(['#define ' + bf.Name + '_MASK', '(' + _fmthex(bf.BitMask, minDigits=hexDigits) + ')',
                          '// bits ' + str(bf.MSB) + ' downto ' + str(bf.LSB)])
                t.AddRow(['#define ' + bf.Name + '_LSB', '(' + _fmtint(bf.LSB, minDigits=1) + ')'])
                bfDefines += 1
            for vd in bf.ValueDescriptions:
                if len(vd) == 3 and len(vd[2]) > 0:
                    t.AddRow(['#define ' + vd[2], '(' + _fmthex(vd[0] << bf.LSB, minDigits=hexDigits) + ')'])
    if bfDefines > 0:
        t.AddBlankLine()
    return s + t.ToString()


def emitString(block, peripheralName=None):
    name = peripheralName or block.PeripheralTemplateName
    s = ''
    t = TabbedTable()
    t.AddLine('/** ' + name + ' (generated from hdl/common/periph/rdl/, not from generate.py) **/')
    s += t.ToString()
    for rt in block.RegisterTemplates:
        s += registerTex(rt, name)

    t = TabbedTable()
    t.AddLine('// Reset values. The RTL is the authority; see the .rdl description.')
    for rt in block.RegisterTemplates:
        t.AddRow(['#define ' + rt.NameTemplate + '_RESET',
                  '(' + _fmthex(rt.ResetValue or 0, minDigits=_hexDigits(rt.Size)) + ')'])
    t.AddBlankLines(2)
    return s + t.ToString()


def emit(block, outPath, peripheralName=None):
    with open(outPath, 'w') as f:
        f.write(emitString(block, peripheralName))
    return outPath
