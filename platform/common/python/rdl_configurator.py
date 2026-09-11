#!/usr/bin/env python3
"""rdl_configurator.py -- the configurator / register-browser JSON fragment of an
.rdl block.

Shape is the `Peripherals[].Registers[]` sub-tree of config/MemoryMap.json, which
is what docs/chip_configurator.html's register browser and web_export.py already
consume; it is produced by the SAME Register.ToDict / BitField.ToDict methods, so
a fragment splices in without a schema of its own. What the fragment adds on top
is the block metadata SystemRDL carries and the Python model does not: the source
.rdl file, the addrmap name and the word base of an overlaid block.

Keys are sorted and the separators are fixed, so two emissions of one description
are byte-identical -- the generation determinism gate applies to this file too.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def _registerDict(rt):
    """Register.ToDict's shape, for a TEMPLATE (no instance address)."""
    d = {
        'RegisterName': rt.NameTemplate,
        'Offset': rt.Offset,
        'RegisterMemorySlot': rt.RegisterMemorySlot,
        'Size': rt.Size,
        'ResetValue': rt.ResetValue,
        'Description': rt.Description,
        'BitFields': [bf.ToDict() for bf in rt.BitFields],
    }
    for bf in d['BitFields']:
        bf['ValueDescriptions'] = [list(v) for v in bf['ValueDescriptions']]
    return d


def emitObject(block, sourceFile):
    return {
        'PeripheralTemplateName': block.PeripheralTemplateName,
        'Source': 'hdl/common/periph/rdl/' + sourceFile,
        'AddrMap': block.Name,
        'WordBase': block.WordBase,
        'InterruptVector': block.Vector,
        'Description': block.Description,
        'Registers': [_registerDict(rt) for rt in block.RegisterTemplates],
    }


def emitString(block, sourceFile):
    return json.dumps(emitObject(block, sourceFile), indent=2, sort_keys=True) + '\n'


def emit(block, outPath, sourceFile):
    with open(outPath, 'w') as f:
        f.write(emitString(block, sourceFile))
    return outPath
