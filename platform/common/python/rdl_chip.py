#!/usr/bin/env python3
"""rdl_chip.py -- the WHOLE-CHIP artifacts, emitted from the top addrmap.

rdl_emit.py works one peripheral TEMPLATE at a time, which is the right unit for
a chapter's register tables and for a header fragment. Two artifacts are not
per-template: the TRM's flat register index (the appendix) and MemoryMap.h's
per-INSTANCE address defines. Both need the instance names and base addresses,
and the only place those are written down in SystemRDL is
hdl/common/regs/rdl/castalia_penta_wound_afe.rdl.

So this walks that addrmap, binds each instance to the .rdl block its
vesta_peripheral names, and emits:

    PeripheralAndRegistersList-rdl.tex   the register index, through rdl_latex's
                                         borrowed LatexUserGuide methods, so the
                                         table is the same shape as the one
                                         GeneratePeripheralAndRegistersList emits
    MemoryMap_rdl.h                      one <REG>_ADDRESS per instance register
                                         in the tracked header's convention, plus
                                         rdl_cheader's per-template fragment

    rdl_chip.py --top <file.rdl> --out <dir> [--config <rdl.json>]
"""

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import rdl_cheader
import rdl_emit
import rdl_latex
import rdl_model

from LatexUserGuide import fmthex, fmttex

DEFAULT_TOP = os.path.join(rdl_model.RDL_DIR, 'castalia_penta_wound_afe.rdl')


class _InstanceBlock(object):
    """An RdlBlock for ONE elaborated instance, so the register templates carry
       that instance's reset values. The .rdl block a peripheral is described by
       is per TEMPLATE and resets everything the way the RTL's generic defaults
       do; the per-instance values (GPIO's RstValPx*, I2C's default_SAD) are
       dynamic assignments in the top addrmap and only exist after elaboration."""

    def __init__(self, node, template):
        self.Node = node
        self.Name = node.inst_name
        self.PeripheralTemplateName = template.PeripheralTemplateName
        self.Vector = node.get_property('vesta_vector')
        self.WordBase = node.get_property('vesta_word_base') or 0
        self.Description = template.Description
        self.RegisterTemplates = rdl_model.registerTemplatesFromNode(node, self.WordBase)


def instances(topPath, topName=None):
    """[(instanceName, baseAddress, vestaPeripheral, node)] from the top addrmap."""
    from systemrdl import RDLCompiler
    rdlc = RDLCompiler()
    rdlc.compile_file(topPath, incl_search_paths=[rdl_model.RDL_DIR, os.path.dirname(topPath)])
    name = topName or os.path.splitext(os.path.basename(topPath))[0]
    root = rdlc.elaborate(top_def_name=name).top
    out = []
    for n in root.children(unroll=True):
        out.append((n.get_path().split('.')[-1].replace('[', '').replace(']', ''),
                    n.absolute_address, n.get_property('vesta_peripheral'), n))
    return out


def instanceRegisterName(templateName, registerPrefix, idx):
    """PxIN + prefix Px + index 0 -> P0IN. Without a prefix carrying an `x`, or
       without an index, the template name IS the instance name."""
    if not registerPrefix or 'x' not in registerPrefix or idx == '':
        return templateName
    if not templateName.startswith(registerPrefix):
        return templateName
    return registerPrefix.replace('x', idx) + templateName[len(registerPrefix):]


def _index(binding):
    """The register index table, in GeneratePeripheralAndRegistersList's shape."""
    s = '{\\small\n'
    s += '\\begin{tabularx}{\\textwidth}{ l l l l l X }\n'
    s += '\\caption{Register index} \\label{t:register-index} \\\\\n'
    head = ('\\hline \\textbf{Register} & \\textbf{Address} & \\textbf{Offset} & \\textbf{Size} '
            '& \\textbf{Access} & \\textbf{Reset} \\\\ \\hline')
    s += head + ' \\endfirsthead\n' + head + ' \\endhead\n'
    s += '\\hline \\endfoot\n\\hline \\endlastfoot\n'
    for (instName, base, flag, block, idx) in binding:
        tex = rdl_latex.RdlLatex(block, flag.get('registerPrefix'), flag.get('bitFieldPrefix'),
                                 [(instName, base)])
        label = 'peripheral' + block.PeripheralTemplateName.replace('_', '')
        s += ('\\multicolumn{6}{l}{\\textbf{\\hyperref[' + label + ']{\\peripheral{'
              + fmttex(instName) + '}}} base \\texttt{' + fmthex(base) + '} (shared window)} \\\\ \\hline\n')
        row = 0
        for blk in tex._RegisterBlocks(tex.PT):
            first = blk['members'][0]
            size = tex._BlockSize(tex.PT, blk)
            if blk['indices'] is None:
                name = instanceRegisterName(first.NameTemplate, flag.get('registerPrefix'), idx)
                addr = fmthex(base + first.Offset)
                off = fmthex(first.Offset, minDigits=2)
            else:
                # A collapsed register array (CLINT's MSIPn, MTIMECMPnL/H), shown
                # as one row with the stride, exactly as the generated index does.
                name = instanceRegisterName(blk['name'], flag.get('registerPrefix'), idx)
                name += ' (n = %d..%d)' % (blk['indices'][0], blk['indices'][-1])
                start = first.Offset - blk['indices'][0] * blk['stride']
                addr = fmthex(base + start) + ' + ' + str(blk['stride']) + 'n'
                off = fmthex(start, minDigits=2) + ' + ' + str(blk['stride']) + 'n'
            if row % 2 == 1:
                s += '\\rowcolor{tablehighlightcolor} '
            s += ('\\hyperref[' + tex._BlockLabel(tex.PT, blk) + ']{\\texttt{' + fmttex(name)
                  + '}} & \\texttt{' + addr + '} & \\texttt{' + off
                  + '} & ' + str(size // 8) + ' & \\texttt{'
                  + tex._AccessSummary([f[0] for f in blk['fields']]) + '} & \\texttt{'
                  + tex._RegisterResetString(first, size) + '} \\\\\n')
            row += 1
        s += '\\hline\n'
    s += '\\end{tabularx}\n}\n'
    return s


def _header(binding):
    """MemoryMap.h, from the addrmap: bases, per-instance register addresses, and
       rdl_cheader's per-template offset/field fragment for each template used."""
    lines = ['/* MemoryMap_rdl.h -- generated from hdl/common/regs/rdl/, not from generate.py.',
             '   Addresses come from the top addrmap; the field defines come from rdl_cheader. */',
             '']
    lines.append('/**** Peripheral base addresses ****/')
    for (instName, base, flag, block, idx) in binding:
        lines.append('#define %-24s (%s)' % (instName + '_BASE', fmthex(base)))
    lines.append('')
    lines.append('/**** Register addresses ****/')
    for (instName, base, flag, block, idx) in binding:
        lines.append('/* ' + instName + ' */')
        for rt in block.RegisterTemplates:
            name = instanceRegisterName(rt.NameTemplate, flag.get('registerPrefix'), idx)
            lines.append('#define %-24s (%s)' % (name + '_ADDRESS', fmthex(base + rt.Offset)))
        lines.append('')
    lines.append('/**** Register offsets, pointers and bit fields, per template ****/')
    seen = set()
    for (instName, base, flag, block, idx) in binding:
        if flag['name'] in seen:
            continue
        seen.add(flag['name'])
        lines.append(rdl_cheader.emitString(block, peripheralName=flag['peripheral']))
    return '\n'.join(lines) + '\n'


def bind(topPath, configPath, topName=None):
    # Two rdl.json entries may name the same peripheral (AFEx is described by
    # afe2.rdl and, on a per-tile chip, ALSO by biasg.rdl overlaying words 9-13).
    # The PRIMARY block is the one whose rdl.json key IS the peripheral name;
    # an overlay would need its own instantiation and is not one here.
    flags = {}
    for f in rdl_emit.loadFlags(configPath):
        if f['peripheral'] not in flags or f['name'] == f['peripheral']:
            flags[f['peripheral']] = f
    blocks = {}
    out = []
    for (instName, base, periph, node) in instances(topPath, topName):
        if periph is None or periph not in flags:
            continue
        flag = flags[periph]
        if periph not in blocks:
            blocks[periph] = rdl_model.loadBlock(flag['source'], flag['top'])
        block = _InstanceBlock(node, blocks[periph])
        idx = instName[len(periph) - 1:] if periph.endswith('x') and instName.startswith(periph[:-1]) else ''
        out.append((instName, base, flag, block, idx))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--top', default=DEFAULT_TOP)
    ap.add_argument('--top-name', default=None)
    ap.add_argument('--config', default=rdl_emit.DEFAULT_CONFIG)
    ap.add_argument('--out', required=True)
    args = ap.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)
    binding = bind(args.top, args.config, args.top_name)
    idxPath = os.path.join(args.out, 'PeripheralAndRegistersList-rdl.tex')
    with open(idxPath, 'w') as f:
        f.write(rdl_latex.RdlLatex(binding[0][3])._TablePreamble() + _index(binding))
    hdrPath = os.path.join(args.out, 'MemoryMap_rdl.h')
    with open(hdrPath, 'w') as f:
        f.write(_header(binding))
    print('[rdl_chip] %d instances -> %s' % (len(binding), idxPath))
    print('[rdl_chip] %d instances -> %s' % (len(binding), hdrPath))
    return 0


if __name__ == '__main__':
    sys.exit(main())
