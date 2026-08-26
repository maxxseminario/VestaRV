#!/usr/bin/env python3
"""CP5 LVS NEGATIVE CONTROL: doctor a copy of the penta chip LVS netlist by
deleting ONE device from the orchestrator core, so the compare has a known
fault to catch. A clean LVS run without a caught-fault control is not evidence.

The chip netlist is HIERARCHICAL: the orchestrator enters as
`orch_tile hart4 (...)`, and its whole subtree carries the CP1-D6 `orch_`
module-name prefix (disjoint from the four hardened tiles' modules by
construction). Deleting a std-cell instance inside module `orch_vesta` -- which
is instantiated EXACTLY ONCE -- therefore removes exactly one device from
exactly one hart (hart4) on the schematic side, while the layout still has it.

The doctored file is written next to the original; the original is never
modified.

Usage: cp5_lvs_negctrl.py [full.lvs.v] [out.lvs.v] [module]
Then:  LVS_ALLOW_STALE_LABELS=1 make lvs BLOCK=mcu_castalia_penta \\
           NETLIST=pvs/MCU_castalia_penta_full.NEGCTRL.lvs.v
(the doctored netlist is newer than the labels by construction -- that is the
one legitimate use of the staleness override.)
"""
import re
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else 'pvs/MCU_castalia_penta_full.lvs.v'
DST = sys.argv[2] if len(sys.argv) > 2 else 'pvs/MCU_castalia_penta_full.NEGCTRL.lvs.v'
MOD = sys.argv[3] if len(sys.argv) > 3 else 'orch_vesta'

INST = re.compile(r'^\s*([A-Z][A-Z0-9_]*)\s+(\S+)\s*\(\s*$')
SKIP = ('FILL', 'ANTENNA', 'WELLTAP')


def main():
    lines = open(SRC).read().split('\n')
    # locate the module body
    start = None
    for i, l in enumerate(lines):
        if l.startswith('module %s ' % MOD) or l.startswith('module %s(' % MOD):
            start = i
            break
    if start is None:
        print('NEGCTRL FATAL: module %s not found in %s' % (MOD, SRC))
        return 1
    end = None
    for i in range(start, len(lines)):
        if lines[i].startswith('endmodule'):
            end = i
            break
    if end is None:
        print('NEGCTRL FATAL: no endmodule after %s' % MOD)
        return 1

    # how many times is this module instantiated?  (must be exactly 1, or the
    # control injects N faults and the "one caught fault" claim is wrong)
    ninst = sum(1 for l in lines if re.match(r'^\s*%s\s+\S+\s*\(' % re.escape(MOD), l))
    if ninst != 1:
        print('NEGCTRL FATAL: module %s is instantiated %d times (want 1)' % (MOD, ninst))
        return 1

    kill_from = kill_to = None
    cell = inst = None
    for i in range(start, end):
        m = INST.match(lines[i])
        if not m or m.group(1).startswith(SKIP):
            continue
        # find the closing ");" of this instance
        for j in range(i + 1, end):
            if lines[j].rstrip().endswith(');'):
                kill_from, kill_to = i, j
                cell, inst = m.group(1), m.group(2)
                break
        if kill_from is not None:
            break
    if kill_from is None:
        print('NEGCTRL FATAL: no deletable std-cell instance inside %s' % MOD)
        return 1

    out = (lines[:kill_from]
           + ['// CP5 NEGATIVE CONTROL: deleted %s %s (%d lines) from module %s'
              % (cell, inst, kill_to - kill_from + 1, MOD)]
           + lines[kill_to + 1:])
    open(DST, 'w').write('\n'.join(out))
    print('NEGCTRL: module %s instantiated %d time(s)' % (MOD, ninst))
    print('NEGCTRL: deleted %s %s  (source lines %d-%d)'
          % (cell, inst, kill_from + 1, kill_to + 1))
    print('NEGCTRL: wrote %s' % DST)
    return 0


if __name__ == '__main__':
    sys.exit(main())
