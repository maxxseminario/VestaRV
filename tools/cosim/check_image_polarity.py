#!/usr/bin/env python3
"""check_image_polarity.py -- the F-K7-3 TRIPWIRE (K7, 2026-08-04; R-K7-1(2)).

WHAT IT GUARDS, AND WHY THAT STOPPED BEING OBVIOUS AT K7.

Until R-DK3 the shipped default configuration had no `-DCORE_ENABLE_*` flags at
all, so `rcf_mapping()` aimed it at the canonical `verification/isa/rcf/`
(`.imgset = "NHARTS=4 DEFINES=(none)"`) -- the very directory the three standing
gates read through `../rcf/`. Gate images and shipped images were the same
files, and nothing had to say so.

R-DK3 turned `priv.trapCsr` on by default. `image_defines()` therefore emits
`-DCORE_ENABLE_TRAPCSR`, and `rcf_mapping()` sends the shipped default to
`k17`/`rcf_k17` -- NEVER to `rcf/`, which is by definition the no-defines set.
So the standing gates now read an image set that no shipped configuration
selects. That is survivable ONLY as long as every image they actually consume is
byte-identical across the two polarities, which was measured true at K7:
136/136 suite, 107/107 single-hart cosim, 17/17 multi-hart, 115/115 Argus.

The day someone adds a test with a live `#if defined(CORE_ENABLE_TRAPCSR)` arm
to a standing list, that stops being true SILENTLY: the gate compiles the OFF
arm and compares it against RTL that ships the ON one. No existing check sees
it. The suite runner has no polarity interlock at all (only the cosim runner
does, and it refuses on the `.imgset` STAMP, which cannot see a per-image
divergence inside an otherwise-matching set).

This script is that missing check. For each standing gate list it compares every
image byte-for-byte between the canonical set and the SHIPPED default's set, and
FAILS naming any test whose two builds differ.

METHOD NOTE (method_rules rule 4). A comparison validated only against equality
has not been validated, so this script REQUIRES its own known-nonzero control:
it asserts that `rocsrw` and `shapeq` -- the two ON-polarity-only tests, whose
`#else` arm is a deliberate FAIL and whose images therefore MUST differ between
the two sets -- do in fact differ. If they do not, the comparison is not
working, and the script FATALs rather than reporting a clean sweep.

Usage:
    /usr/bin/python3.6 tools/cosim/check_image_polarity.py          # rc 0 / 1 / 2
    /usr/bin/python3.6 tools/cosim/check_image_polarity.py --list   # per-list detail

Python 3.6 compatible. Reads only; changes nothing.
"""

import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
ISA = os.path.join(ROOT, 'verification', 'isa')
MP = os.path.join(ROOT, 'xcelium', 'riscv_test', 'behavioral_mp')
ARGUS = os.path.join(ROOT, 'xcelium', 'riscv_test', 'behavioral_mp_argus')
PC_PY = os.path.join(ROOT, 'platform', 'common', 'python')

# The known-nonzero control: (test image basename, why it must differ)
CONTROLS = [
    ('xxxrv32ua-p-rocsrw.rcf', 'ON-polarity-only; its #else arm is li a1,0x5E10BAD0 + fail'),
    ('xxxrv32ua-p-shapeq.rcf', 'ON-polarity-only; same construction'),
]


def md5(path):
    try:
        with open(path, 'rb') as f:
            return hashlib.md5(f.read()).hexdigest()
    except IOError:
        return None


def shipped_dirs():
    """(castalia_dir, argus_dir) -- the image dirs the SHIPPED configs select."""
    sys.path.insert(0, PC_PY)
    import json
    import verify_stage as V  # import-safe: main() is guarded (R-K2-4)
    out = []
    for cfgfile, nharts in (('ChipConfig.resolved.json', None), ('argus.json', 18)):
        path = os.path.join(ROOT, 'platform', 'common', 'config', cfgfile)
        with open(path) as f:
            cfg = json.load(f)
        if cfgfile == 'argus.json':
            # argus.json is a partial config; resolve the knobs that matter here
            # the same way generate.py's defaults do.
            cfg.setdefault('priv', {})
            for k, d in (('trapCsr', None), ('umode', False), ('pmp', False)):
                if k not in cfg['priv']:
                    cfg['priv'][k] = _schema_default('priv.' + k) if d is None else d
            cfg['numHarts'] = nharts
        _, dest = V.rcf_mapping(int(cfg['numHarts']), V.image_defines(cfg),
                                V.image_march(cfg))
        out.append(os.path.join(ISA, dest))
    return out


def _schema_default(key):
    """Read one schema default straight out of generate.py's source (that file
    is IMPORT-UNSAFE -- importing it runs a generation, R-K1-3)."""
    src = open(os.path.join(PC_PY, 'generate.py')).read()
    m = re.search(r"^\t'%s':\s*\{[^}]*'default':\s*([^,}]+)" % re.escape(key),
                  src, re.M)
    if not m:
        raise SystemExit('check_image_polarity: FATAL -- no schema default for %s' % key)
    return m.group(1).strip() == 'True'


def suite_list():
    names = []
    with open(os.path.join(MP, 'xrun_parallel.sh')) as f:
        for line in f:
            m = re.match(r'\s*"(\.\./rcf/[^"]+)"', line)
            if m:
                names.append(m.group(1).split('/')[-1])
            elif line.startswith(')') and names:
                break
    return names


def argus_list():
    names = []
    with open(os.path.join(ARGUS, 'xrun_parallel.sh')) as f:
        for line in f:
            m = re.match(r'\s*"(\.\./rca/[^"]+)"', line)
            if m:
                names.append(m.group(1).split('/')[-1])
    return names


def txt_list(path):
    out = []
    with open(path) as f:
        for line in f:
            s = line.strip()
            if s and not s.startswith('#'):
                out.append(s)
    return out


def compare(label, names, a_dir, b_dir, detail):
    same = diff = missing = 0
    bad = []
    for n in names:
        x, y = md5(os.path.join(a_dir, n)), md5(os.path.join(b_dir, n))
        if x is None or y is None:
            missing += 1
            bad.append('    MISSING %s (%s%s)' % (
                n, 'not in ' + os.path.basename(a_dir) if x is None else '',
                ' not in ' + os.path.basename(b_dir) if y is None else ''))
        elif x == y:
            same += 1
        else:
            diff += 1
            bad.append('    POLARITY-SENSITIVE %s  %s != %s' % (n, x[:8], y[:8]))
    status = 'OK' if (diff == 0 and missing == 0) else 'FAIL'
    if detail or status == 'FAIL':
        print('  %-26s %3d image(s): identical %d, differ %d, missing %d   [%s]'
              % (label, len(names), same, diff, missing, status))
        for b in bad:
            print(b)
    return diff + missing


def main(argv):
    detail = '--list' in argv
    cast, arg = shipped_dirs()
    canon_c, canon_a = os.path.join(ISA, 'rcf'), os.path.join(ISA, 'rcf_argus')

    print('  canonical (gates read this): %s' % os.path.basename(canon_c))
    print('  shipped default selects    : %s' % os.path.basename(cast))
    if os.path.abspath(cast) == os.path.abspath(canon_c):
        print('  they are the SAME directory -- nothing to compare, tripwire vacuous.')
        return 0

    # --- the known-nonzero control, BEFORE any verdict is believed ----------
    for name, why in CONTROLS:
        x, y = md5(os.path.join(canon_c, name)), md5(os.path.join(cast, name))
        if x is None or y is None or x == y:
            print('  CONTROL FAILED: %s should DIFFER between the two sets (%s)' % (name, why))
            print('  The comparison cannot be trusted; not reporting a verdict.')
            return 2
    print('  control: %d ON-polarity-only image(s) correctly DIFFER across the sets'
          % len(CONTROLS))

    problems = 0
    problems += compare('suite (behavioral_mp)', suite_list(), canon_c, cast, detail)
    problems += compare('cosim single-hart', txt_list(os.path.join(MP, 'cosim_tests.txt')),
                        canon_c, cast, detail)
    problems += compare('cosim multi-hart', txt_list(os.path.join(MP, 'cosim_sh_tests.txt')),
                        canon_c, cast, detail)
    if os.path.isdir(canon_a) and os.path.isdir(arg) and os.path.abspath(arg) != os.path.abspath(canon_a):
        problems += compare('Argus (historical ref)', argus_list(), canon_a, arg, detail)

    if problems:
        print('  %d polarity problem(s). A standing gate is now compiling one arm of an'
              ' #ifdef against RTL that ships the other. Fix the list or move the gate'
              ' to the shipped image set -- do NOT ignore this.' % problems)
        return 1
    print('  image polarity: OK -- every standing-gate image is byte-identical across'
          ' the two polarities, so the gates measure the shipped RTL.')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
