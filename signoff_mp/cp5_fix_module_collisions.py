#!/usr/bin/env python3
"""CP5: resolve MODULE-NAME COLLISIONS between a chip LVS netlist and the
appended hart_tile LVS netlist, writing the concatenated _full file.

WHY (CP5 finding, 2026-08-13): CP1 D6 guarantees the ORCHESTRATOR's modules are
disjoint from the TILE's (the `orch_` prefix rename). It says NOTHING about the
CHIP FABRIC's modules. Genus uniquifies clock-gate wrappers per run, and the
penta chip synthesis emitted `ClkGate_2` (3-pin, VDD/VSS) while the FROZEN tile
LVS collateral -- cut from the tile harden, a different genus run -- also
defines `ClkGate_2`, there with the switched rail VDD_SW. Concatenating them
gives Pegasus two definitions of one name; it binds the first and then FATALs
on the tile instances that pass VDD_SW:

    ERROR (NVN-13300): Pin 'VDD_SW' ... cannot be found in instance master
    'ClkGate_2'.

The 4-hart MCU_castalia collateral happens to have zero collisions, so this
never surfaced before -- it is luck, not design.

FIX: rename the colliding modules in the TILE COPY ONLY (definition + its
instantiation lines), inside the generated _full file. pvs/hart_tile.lvs.v is
shared collateral and is NEVER modified. Module names below the hcell boundary
are compare-internal (only `hart_tile` is an hcell), so the rename is invisible
to the verdict.

usage: cp5_fix_module_collisions.py <chip.lvs.v> <tile.lvs.v> <out_full.lvs.v>
"""
import re
import sys

SUF = '__tile'


def modules(text):
    return set(re.findall(r'^module\s+([A-Za-z_][A-Za-z0-9_]*)\s*[( ]', text, re.M))


def main():
    chip_p, tile_p, out_p = sys.argv[1], sys.argv[2], sys.argv[3]
    chip = open(chip_p).read()
    tile = open(tile_p).read()

    cm, tm = modules(chip), modules(tile)
    clash = sorted(cm & tm)
    print('COLLISION: chip modules %d, tile modules %d, colliding %d'
          % (len(cm), len(tm), len(clash)))
    for m in clash:
        print('COLLISION:   %s' % m)

    ndef = ninst = 0
    for m in clash:
        new = m + SUF
        if new in cm or new in tm:
            print('COLLISION FATAL: rename target %s already exists' % new)
            return 1
        tile, k = re.subn(r'^module\s+%s(\s*[( ])' % re.escape(m),
                          'module %s\\1' % new, tile, flags=re.M)
        ndef += k
        # instantiation lines: leading whitespace, module name, instance name
        tile, k = re.subn(r'^(\s+)%s(\s+)' % re.escape(m),
                          '\\g<1>%s\\g<2>' % new, tile, flags=re.M)
        ninst += k
    print('COLLISION: renamed %d definition(s), %d instantiation line(s) in the TILE copy'
          % (ndef, ninst))
    if clash and (ndef != len(clash) or ninst == 0):
        print('COLLISION FATAL: rename did not touch what it must (defs %d/%d, insts %d)'
              % (ndef, len(clash), ninst))
        return 1

    full = chip + tile
    left = sorted(n for n in modules(full)
                  if full.count('\nmodule %s ' % n) + full.count('\nmodule %s(' % n) > 1)
    if left:
        print('COLLISION FATAL: duplicate module names survive: %s' % left[:10])
        return 1
    open(out_p, 'w').write(full)
    print('COLLISION: wrote %s (%d bytes)' % (out_p, len(full)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
