#!/usr/bin/env python3
"""VestaRV: tripwire on the shipped image's trap-delivery polarity.

The standing gates read verification/isa/rcf/, the no-defines image set, while the shipped
default now emits -DCORE_ENABLE_TRAPCSR and selects rcf_k17. That is survivable only while
every image both sets share is byte-identical, so this compares them and names any that
differ. Its control requires rocsrw and shapeq, the two ON-only tests, to differ.
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
    import verify_stage as V  # import-safe: main() is guarded
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
    """Read one schema default straight out of generate.py's source; that file is import-unsafe,
    because importing it runs a generation.
    """
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

    # the known-nonzero control, BEFORE any verdict is believed
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
