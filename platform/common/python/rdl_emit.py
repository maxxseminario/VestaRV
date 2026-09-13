#!/usr/bin/env python3
"""VestaRV: emit every artifact of every peripheral flagged `rdl: true` in config/rdl.json.

Four files per block into <out>/: <TAG>-registers-rdl.tex, MemoryMap_<TAG>_rdl.h,
<TAG>_reg_pkg.vhd and <TAG>_rdl.json. This path is deliberately separate from the hermetic
generation action, which carries no SystemRDL toolchain in its runfiles, so a configuration
generates byte-identically without it; what ties the two together is rdl_vs_generator_test.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rdl_cheader
import rdl_configurator
import rdl_latex
import rdl_model

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CONFIG = os.path.join(os.path.dirname(HERE), 'config', 'rdl.json')


def _defaultOut():
    """`bazel run` puts the process in a runfiles tree, so the source location has
       to come from BUILD_WORKSPACE_DIRECTORY; outside bazel, from this file."""
    ws = os.environ.get('BUILD_WORKSPACE_DIRECTORY')
    root = os.path.join(ws, 'platform', 'common') if ws else os.path.dirname(HERE)
    return os.path.join(root, 'out', 'rdl')


def loadFlags(path):
    # rdl_model.loadConfig is THE reader of the registry (it merges an overlay's
    # rows); this used to open the file itself, which made an overlay's blocks
    # visible to one consumer and invisible to the other.
    cfg = rdl_model.loadConfig(path)
    out = []
    for name, entry in sorted(cfg.get('peripherals', {}).items()):
        if not entry.get('rdl', False):
            continue
        out.append({
            'name': name,
            'source': entry['source'],
            'top': entry['top'],
            # `peripheral` is the generate.py PeripheralTemplate the block's
            # registers belong to, and it is None for a block that is not a
            # memory-mapped peripheral at all (DEBUG, whose registers live in the
            # DMI address space). Such a block still compiles, still exports and
            # still gets a TRM table; it has no header, no package and no
            # register-index row, because it has no address in the memory map.
            'peripheral': entry.get('peripheral', name),
            'registerPrefix': entry.get('registerPrefix'),
            'bitFieldPrefix': entry.get('bitFieldPrefix'),
            # Where generate.py's register templates for this peripheral come
            # from: "rdl" (built from the description), "generator" (still
            # hand-written, because the register set is a function of the
            # configuration) or "none". See config/rdl.json's _comment.
            'registerSource': entry.get('registerSource', 'generator'),
        })
    return out


def memoryMapped(flags):
    """The flags whose block IS a generate.py peripheral, i.e. has an address."""
    return [f for f in flags if f['peripheral'] is not None]


def emitBlock(flag, outDir):
    block = rdl_model.loadBlock(flag['source'], flag['top'])
    if flag['peripheral'] is None:
        # Not memory-mapped: the TRM table is the only artifact that means
        # anything (a C header of DMI offsets would invite a load/store).
        tag = flag['name'].replace('_', '')
        return block, [rdl_latex.emit(block, os.path.join(outDir, tag + '-registers-rdl.tex'),
                                      registerPrefix=flag['registerPrefix'],
                                      bitFieldPrefix=flag['bitFieldPrefix'])]
    if block.PeripheralTemplateName != flag['peripheral']:
        raise Exception('rdl_emit: %s declares vesta_peripheral "%s" but rdl.json says "%s"'
                        % (flag['source'], block.PeripheralTemplateName, flag['peripheral']))
    tag = flag['name'].replace('_', '')
    written = []
    written.append(rdl_latex.emit(block, os.path.join(outDir, tag + '-registers-rdl.tex'),
                                  registerPrefix=flag['registerPrefix'],
                                  bitFieldPrefix=flag['bitFieldPrefix']))
    written.append(rdl_cheader.emit(block, os.path.join(outDir, 'MemoryMap_' + tag + '_rdl.h'),
                                    peripheralName=flag['peripheral']))
    from rdl_vhdl import emit as emitVhdl
    written.append(emitVhdl(block, os.path.join(outDir, tag + '_reg_pkg.vhd'),
                            packageName=tag + '_reg_pkg'))
    written.append(rdl_configurator.emit(block, os.path.join(outDir, tag + '_rdl.json'),
                                         flag['source']))
    return block, written


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--out', default=None,
                    help='output directory (default <chip root>/out/rdl; created if absent)')
    ap.add_argument('--config', default=DEFAULT_CONFIG, help='path to rdl.json')
    ap.add_argument('--peripheral', action='append', default=None,
                    help='emit only this rdl.json key (repeatable)')
    ap.add_argument('--trm-include', default=None,
                    help='also copy the register tables into this TRM include directory')
    args = ap.parse_args(argv)
    if args.out is None:
        args.out = _defaultOut()
    if args.config == DEFAULT_CONFIG and os.environ.get('BUILD_WORKSPACE_DIRECTORY'):
        ws = os.path.join(os.environ['BUILD_WORKSPACE_DIRECTORY'],
                          'platform', 'common', 'config', 'rdl.json')
        if os.path.isfile(ws):
            args.config = ws

    flags = loadFlags(args.config)
    if args.peripheral:
        want = set(args.peripheral)
        flags = [f for f in flags if f['name'] in want]
        missing = want - set(f['name'] for f in flags)
        if missing:
            raise SystemExit('rdl_emit: not flagged rdl:true in %s: %s'
                             % (args.config, ', '.join(sorted(missing))))
    if not flags:
        print('[rdl_emit] no peripheral is flagged rdl:true; nothing to emit')
        return 0

    os.makedirs(args.out, exist_ok=True)
    for flag in flags:
        block, written = emitBlock(flag, args.out)
        print('[rdl_emit] %-10s %s -> %d files, %d registers'
              % (flag['name'], flag['source'], len(written), len(block.RegisterTemplates)))
        for w in written:
            print('             ' + os.path.basename(w))
        if args.trm_include and os.path.isdir(args.trm_include):
            tag = flag['name'].replace('_', '')
            name = tag + '-registers-rdl.tex'
            with open(os.path.join(args.out, name)) as f:
                tex = f.read()
            with open(os.path.join(args.trm_include, name), 'w') as f:
                f.write(tex)
            print('             -> ' + os.path.join(args.trm_include, name))
    print('[rdl_emit] output directory: ' + args.out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
