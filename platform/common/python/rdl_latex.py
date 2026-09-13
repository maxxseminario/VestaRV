#!/usr/bin/env python3
"""VestaRV: the TRM register tables of an .rdl block, in LatexUserGuide.py's own format.

Format identity is by construction: the RegisterTemplate objects are handed to
LatexUserGuide's _RegisterBlocks, _RegisterBlockTex and _FieldRows through a shim supplying
the attributes those methods read off self, so array detection, reserved-run collapsing, row
striping and labels are the same code. Output is a subsection per register block.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import LatexUserGuide
from LatexUserGuide import fmthex, fmttex


class _PeripheralShim(object):
    """The PeripheralTemplate attributes the LaTeX methods read."""

    def __init__(self, name, registerTemplates, registerPrefix=None, bitFieldPrefix=None):
        self.NameTemplate = name
        self.RegisterTemplates = registerTemplates
        self.RegisterPrefix = registerPrefix
        self.BitFieldPrefix = bitFieldPrefix


class _GenShim(object):
    def __init__(self):
        self.Peripherals = []


class _RegisterShim(object):
    """The two attributes _RegisterBlockTex reads off an instance's registers."""

    def __init__(self, template, address):
        self.Template = template
        self.Address = address


class _InstanceShim(object):
    """A peripheral INSTANCE, for the `Address` cell of a register's offset line.
       The .rdl description is per-TEMPLATE and knows no base addresses, so the
       caller supplies them; with none, the offset line simply omits the cell."""

    def __init__(self, name, baseAddress, registerTemplates):
        self.Name = name
        self.BaseAddress = baseAddress
        self.Registers = [_RegisterShim(rt, baseAddress + rt.Offset) for rt in registerTemplates]

    def IsGPIO(self):
        return False


class RdlLatex(object):
    """LatexUserGuide's register-table methods, bound to an .rdl block."""

    # The methods are borrowed wholesale. Anything they reach for on `self` is
    # provided below; anything they reach for on `self.Gen` is provided by _GenShim.
    for _name in ('_RegisterBlocks', '_RegisterBlockTex', '_FieldRows', '_ReservedRow',
                  '_BlockLabel', '_BlockHeadingName', '_BlockOffsetString', '_BlockSize',
                  '_TryRegisterArray', '_Templatize', '_FieldSignature', '_EnumerationLines',
                  '_CodedListFromProse', '_NoteEmptyDescription', '_ShortTitle',
                  '_SentenceCount', '_FieldValueString', '_FieldResetString',
                  '_RegisterResetString', '_AccessSummary', '_BitFieldDisplayName',
                  '_TablePreamble'):
        locals()[_name] = getattr(LatexUserGuide.LatexUserGuide, _name)
    del _name

    EMPTY_FIELD_DESCRIPTION_IS_ERROR = False

    def __init__(self, block, registerPrefix=None, bitFieldPrefix=None, instanceBases=None):
        self.Block = block
        self.Gen = _GenShim()
        self.EmptyFieldDescriptions = []
        self.LongFieldDescriptions = []
        self.LongRegisterDescriptions = []
        self.PT = _PeripheralShim(block.PeripheralTemplateName, block.RegisterTemplates,
                                  registerPrefix, bitFieldPrefix)
        self.Instances = [_InstanceShim(n, b, block.RegisterTemplates)
                          for (n, b) in (instanceBases or [])]

    def RegistersTex(self, shortLabelOk=True):
        """The register subsections, plus the summary table that heads them."""
        pt = self.PT
        tag = pt.NameTemplate.replace('_', '')
        blocks = self._RegisterBlocks(pt)
        s = '\\begin{tabularx}{\\textwidth}{ l l l l X }\n'
        s += ('\\caption{\\peripheral{' + fmttex(pt.NameTemplate) + '} register summary} \\label{t:'
              + tag + '-regsummary} \\\\\n')
        head = ('\\hline \\textbf{Offset} & \\textbf{Name} & \\textbf{Access} & \\textbf{Reset} & '
                '\\textbf{Description} \\\\ \\hline')
        s += head + ' \\endfirsthead\n' + head + ' \\endhead\n'
        s += '\\hline \\endfoot\n\\hline \\endlastfoot\n'
        row = 0
        nextOffset = None
        for block in blocks:
            first = block['members'][0]
            last = block['members'][-1]
            if nextOffset is not None and first.Offset > nextOffset:
                if row % 2 == 1:
                    s += '\\rowcolor{tablehighlightcolor} '
                s += ('\\texttt{' + fmthex(nextOffset, minDigits=2) + '} to \\texttt{'
                      + fmthex(first.Offset - 1, minDigits=2) + '} & - & - & - & Reserved \\\\\n')
                row += 1
            size = self._BlockSize(pt, block)
            title = self._ShortTitle(block['description']) or ''
            if row % 2 == 1:
                s += '\\rowcolor{tablehighlightcolor} '
            s += ('\\texttt{' + self._BlockOffsetString(block) + '} & \\hyperref['
                  + self._BlockLabel(pt, block) + ']{\\texttt{'
                  + fmttex(self._BlockHeadingName(block)) + '}} & \\texttt{'
                  + self._AccessSummary([f[0] for f in block['fields']])
                  + '} & \\texttt{' + self._RegisterResetString(first, size) + '} & '
                  + fmttex(title) + ' \\\\\n')
            row += 1
            nextOffset = last.Offset + 4
        s += '\\end{tabularx}\n\n'
        for block in blocks:
            s += self._RegisterBlockTex(pt, block, self.Instances, shortLabelOk)
        return s

    def FileTex(self, shortLabelOk=True):
        """A standalone include file: the guarded preamble plus the tables."""
        return self._TablePreamble() + self.RegistersTex(shortLabelOk)


def emit(block, outPath, registerPrefix=None, bitFieldPrefix=None, instanceBases=None,
         shortLabelOk=True):
    tex = RdlLatex(block, registerPrefix, bitFieldPrefix, instanceBases).FileTex(shortLabelOk)
    with open(outPath, 'w') as f:
        f.write(tex)
    return outPath
