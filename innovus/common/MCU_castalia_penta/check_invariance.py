#!/usr/bin/env python3
"""CP4b deliverable 4 -- prove the CP1 D9 invariant from the ROUTED DEFs.

Compares the placement (x, y, orientation) of every instance that CP1 D9 says
must not move, between the MCU_castalia SIGNOFF cut and the MCU_castalia_penta
cut, reading each design's own saved DEF -- not the tcl, not the log.

CPR6 RENUMBER (2026-08-15): the penta cut's four hardened corner tiles are
mcu0/hart1..hart4 (the orchestrator took the name mcu0/hart0), while the
MCU_castalia reference DEF still calls the same four corners mcu0/hart0..hart3.
Comparison is therefore by MAPPED name for the tile class only -- reference
hart<h> is the penta cut's hart<h+1>, at the same corner, same orientation.
Every other class is compared by identical name as before. The map is applied
to the LOOKUP, never to the geometry: a tile that moved still fails.

Checked classes:
  * the 4 hardened corner tiles      ref mcu0/hart0..3 -> penta mcu0/hart1..4
  * the shared RAM row               mcu0/shbank0..3 + mcu0/npuram0
  * the boot ROM                     mcu0/rom0
  * the analog row                   mcu0/por, dco0, dco1, irq_gf0..3
  * the whole pad ring               every PAD_* + RING_CUT_* instance
                                     (IOFILL_* are Innovus-generated filler and
                                      are compared as a NAME SET, not by
                                      position -- they re-derive per run)

Allowed deltas: NEW instances only, and only under mcu0/hart0 (the orchestrator
subtree) -- anything else present in one DEF and absent from the other, or any
placement that moved, is a FAILURE.

Run with /usr/bin/python3.6 (this machine's `python3` is the aoj_cal wrapper).
"""
import gzip
import re
import sys

REF = ('../MCU_castalia/dbs/MCU_castalia.signoff.innovus.dat/'
       'MCU_castalia.def.gz')
NEW = ('dbs/MCU_castalia_penta.signoff.innovus.dat/'
       'MCU_castalia_penta.def.gz')

# CP5: allow the cut under test to be named on the command line, so the
# closure-ECO cuts (dbs/MCU_castalia_penta.cp5eco{,_a}.innovus.dat/...) can be
# re-checked against the SAME reference without editing this file.
#   ./check_invariance.py [new_def.gz] [ref_def.gz]
if len(sys.argv) > 1:
    NEW = sys.argv[1]
if len(sys.argv) > 2:
    REF = sys.argv[2]

COMP_RE = re.compile(
    r'^\s*-\s+(\S+)\s+(\S+)\s+.*?\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+(\w+)')


def read_def(path):
    """{inst: (cell, x_dbu, y_dbu, orient)} for the COMPONENTS section."""
    op = gzip.open if path.endswith('.gz') else open
    comps = {}
    inside = False
    buf = ''
    with op(path, 'rt') as fh:
        for line in fh:
            if line.startswith('COMPONENTS'):
                inside = True
                continue
            if line.startswith('END COMPONENTS'):
                break
            if not inside:
                continue
            buf += ' ' + line.rstrip('\n')
            if ';' not in buf:
                continue
            for stmt in buf.split(';'):
                stmt = stmt.strip()
                if not stmt.startswith('-'):
                    continue
                m = COMP_RE.match(stmt)
                if m:
                    comps[m.group(1)] = (m.group(2), int(m.group(3)),
                                         int(m.group(4)), m.group(5))
            buf = ''
    return comps


# CPR6: reference tile instance -> penta tile instance (same corner).
TILE_MAP = {'mcu0/hart%d' % h: 'mcu0/hart%d' % (h + 1) for h in range(4)}


def mapped(name):
    """The name this reference instance is expected to carry in the penta DEF."""
    return TILE_MAP.get(name, name)


def classify(name):
    # [0-4] and not [0-3]: the REFERENCE has hart0..3 and the penta cut has
    # hart1..4, and this one predicate is applied to both sides (it feeds the
    # 'extra' sweep on the penta side, where an unmapped tile-shaped instance
    # must not slip through unclassified).
    if re.match(r'^mcu0/hart[0-4]$', name):
        return 'tile'
    if re.match(r'^mcu0/(shbank[0-3]|npuram0)$', name):
        return 'sram'
    if name == 'mcu0/rom0':
        return 'rom'
    if re.match(r'^mcu0/(por|dco[01]|irq_gf[0-3])$', name):
        return 'analog'
    if name.startswith('PAD_') or name.startswith('RING_CUT'):
        return 'pad'
    return None


def main():
    ref = read_def(REF)
    new = read_def(NEW)
    print('reference DEF : %s  (%d components)' % (REF, len(ref)))
    print('penta DEF     : %s  (%d components)' % (NEW, len(new)))
    print('')

    classes = {}
    for name, val in ref.items():
        c = classify(name)
        if c:
            classes.setdefault(c, []).append(name)

    bad = 0
    for c in ('tile', 'sram', 'rom', 'analog', 'pad'):
        names = sorted(classes.get(c, []))
        moved, missing = [], []
        for n in names:
            nn = mapped(n)
            if nn not in new:
                missing.append('%s (looked up as %s)' % (n, nn)
                               if nn != n else n)
                continue
            if new[nn] != ref[n]:
                moved.append(('%s->%s' % (n, nn) if nn != n else n,
                              ref[n], new[nn]))
        status = 'IDENTICAL' if not moved and not missing else 'DIVERGENT'
        print('%-7s : %3d instances -> %s' % (c, len(names), status))
        for n, r, w in moved:
            print('    MOVED   %-24s ref %s  penta %s' % (n, r, w))
        for n in missing:
            print('    MISSING %-24s (present in the reference DEF only)' % n)
        bad += len(moved) + len(missing)

    # anything of a checked class that is NEW in penta and not in the reference
    mapped_ref = set(mapped(n) for n in ref)
    extra = [n for n in new
             if classify(n) and n not in mapped_ref]
    if extra:
        bad += len(extra)
        print('')
        for n in sorted(extra):
            print('    EXTRA   %-24s (in the penta DEF only)' % n)

    # IOFILL name-set comparison (positions re-derive per run; the SET must not
    # change or the ring geometry did)
    rf = set(n for n in ref if n.startswith('IOFILL'))
    nf = set(n for n in new if n.startswith('IOFILL'))
    print('')
    print('iofill  : %d reference / %d penta -- name set %s'
          % (len(rf), len(nf), 'IDENTICAL' if rf == nf else 'DIVERGENT'))
    if rf != nf:
        bad += 1
        print('    only in reference: %s' % sorted(rf - nf)[:10])
        print('    only in penta    : %s' % sorted(nf - rf)[:10])

    # the permitted new geometry
    orch = sorted(n for n in new if n.startswith('mcu0/hart0/')
                  and new[n][0].startswith('sram1p16k'))
    print('')
    print('permitted new macro(s) under mcu0/hart0:')
    for n in orch:
        cell, x, y, o = new[n]
        print('    %-28s %-18s (%.4f , %.4f) %s'
              % (n, cell, x / 2000.0, y / 2000.0, o))

    print('')
    if bad == 0:
        print('CP1 D9 INVARIANCE: PASS -- every tile, SRAM, ROM, analog macro '
              'and pad instance is placement-identical to the MCU_castalia '
              'signoff cut.')
        return 0
    print('CP1 D9 INVARIANCE: FAIL -- %d divergence(s) above.' % bad)
    return 1


if __name__ == '__main__':
    sys.exit(main())
