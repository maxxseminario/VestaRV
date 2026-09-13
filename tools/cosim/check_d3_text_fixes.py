#!/usr/bin/python3.6
"""VestaRV: the instrument for the frozen debug-transport text fixes.

Four frozen clauses are comment and generated-string corrections, so their instrument is a
text check. It searches for the wrong text rather than asserting a line number, and reports
where it found it. A staged MCU.vhd is checked as well as the emitter, since only one of the
two is regenerated. Exit 0 all fixed, 1 a stale string survives, 2 a file is missing.
"""

import os
import re
import sys

ROOT = os.environ.get('VESTA_ROOT',
                      os.path.join(os.path.expanduser('~'), 'vestarv'))

# (file, regex that must NOT appear, short name, why)
STALE = [
    ('hdl/common/debug_module.vhd', r'req_busy', 'T1',
     'the nonexistent req_busy signal / observed-low claim (the guard is a '
     '9-mclk timer: rsp_hold = 0 and rsp_arm = 0)'),
    ('hdl/common/debug_module.vhd', r'it is combinational from', 'T2',
     'ready described as combinational; it is registered (ready_r)'),
    ('platform/common/python/mcu_vhd.py', r'11=busy', 'T3',
     'the emitted MCU comment promises a response op the RTL cannot produce'),
]

# Generated products that must not carry the T3 string either.  Absent
# products are SKIPPED with a note, never counted as a pass.
PRODUCTS = [
    'xcelium/riscv_test/verify_castaliadebug/hdl/MCU.vhd',
    'xcelium/riscv_test/verify_argusdebug/hdl/MCU.vhd',
    'hdl/common/MCU.vhd',
]

# Positive obligations: after the fix, the corrected description must be
# PRESENT, not merely the wrong one absent.  A deletion is not a fix -- the
# rule-12 obligation is to describe the real mechanism.  Each entry is
# (file, list-of-alternatives, name, what it should say).
REQUIRED = [
    ('hdl/common/debug_module.vhd',
     [r'rsp_hold', r'rsp_arm'], 'T1b',
     'the accept guard must be described in terms of the signals that '
     'actually implement it'),
]


def readfile(path):
    with open(path, 'r', errors='replace') as fh:
        return fh.read().split('\n')


def main():
    problems = []
    notes = []

    for rel, pat, name, why in STALE:
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            print('check_d3_text_fixes: FATAL missing file: ' + rel)
            return 2
        rx = re.compile(pat)
        hits = [(i + 1, ln) for i, ln in enumerate(readfile(path))
                if rx.search(ln)]
        if hits:
            problems.append((name, rel, why, hits))

    for rel in PRODUCTS:
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            notes.append('SKIPPED (not staged): ' + rel)
            continue
        hits = [(i + 1, ln) for i, ln in enumerate(readfile(path))
                if '11=busy' in ln]
        if hits:
            problems.append(('T4', rel,
                             'a generated product still carries the "11=busy" '
                             'promise -- the emitter was fixed but this file '
                             'was not regenerated, or vice versa', hits))

    for rel, pats, name, why in REQUIRED:
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            print('check_d3_text_fixes: FATAL missing file: ' + rel)
            return 2
        body = '\n'.join(readfile(path))
        if not any(re.search(p, body) for p in pats):
            problems.append((name, rel, why, []))

    for n in notes:
        print('check_d3_text_fixes: ' + n)

    if problems:
        print('check_d3_text_fixes: FAIL -- %d rule-12 obligation(s) unmet'
              % len(problems))
        for name, rel, why, hits in problems:
            print('  [%s] %s' % (name, rel))
            print('        %s' % why)
            for ln, txt in hits[:4]:
                print('        :%d  %s' % (ln, txt.strip()[:100]))
        print('  These are d3_spec section 3 clauses.  A frozen clause with no')
        print('  instrument is how D1 shipped three of them unimplemented.')
        return 1

    print('check_d3_text_fixes: OK -- all d3_spec section 3 text fixes are in '
          'place (%d stale patterns absent, %d positive obligations met)'
          % (len(STALE) + len(PRODUCTS), len(REQUIRED)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
