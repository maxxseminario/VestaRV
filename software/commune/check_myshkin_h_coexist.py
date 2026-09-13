#!/usr/bin/env python3
"""VestaRV: myshkin.h and the generated register headers share a translation unit.

myshkin.h publishes eight SYSTEM registers as object-like macros whose names the regs headers
use as struct members, so unguarded they expand inside the struct and system_t stops parsing.
VESTA_LEGACY_SYSTEM_MMR is the mutual exclusion, and this compiles the four cases that pin it
down at -Wall -Wextra -Werror: legacy, flag, regs-first, and a control that must fail.
"""

import argparse
import os
import subprocess
import sys
import tempfile

CFLAGS = ['-march=rv32ima', '-mabi=ilp32', '-ffreestanding', '-std=c11',
          '-Wall', '-Wextra', '-Werror', '-fsyntax-only']

LEGACY_BODY = """
void vesta_legacy(void);
void vesta_legacy(void)
{
    SYSCLKCR = 0x0001;
    CLKDIVCR = 0x01;
    CRCSTATE = 0xFFFF;
    CRCDATA  = 0x5A;
    WDTPASS  = 0x0000ABCDu;
    WDTCR    = 0x01;
    WDTSR    = 0x01;
    (void)WDTVAL;
}
"""

STRUCT_BODY = """
void vesta_structs(void);
void vesta_structs(void)
{
    SYSTEM_REGS->SYSCLKCR = 0x0001;
    SYSTEM_REGS->CLKDIVCR = 0x01;
    SYSTEM_REGS->CRCSTATE = 0xFFFF;
    SYSTEM_REGS->WDTPASS  = 0x0000ABCDu;
    /* The addresses stay available to the call sites not moved yet. */
    (void)SYSCLKCR_ADDRESS;
    (void)WDTVAL_ADDRESS;
    (void)MEMPWRCR;
}
"""


def _compile(cc, incDirs, source, name):
    tmp = tempfile.mkdtemp()
    src = os.path.join(tmp, name + '.c')
    with open(src, 'w') as f:
        f.write(source)
    cmd = [cc] + CFLAGS
    for d in incDirs:
        cmd += ['-I', d]
    cmd.append(src)
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out = proc.communicate()[0].decode('utf-8', 'replace')
    return proc.returncode, out


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument('--cc', required=True)
    parser.add_argument('--commune', required=True, help='software/commune/include')
    parser.add_argument('--regs', required=True, help='software/include/regs')
    args = parser.parse_args(argv[1:])

    cc = os.path.abspath(args.cc)
    if not os.path.exists(cc):
        sys.stderr.write('check_myshkin_h_coexist: no compiler at %s\n' % cc)
        return 2
    commune = os.path.abspath(args.commune)
    regs = os.path.abspath(args.regs)
    for d in (commune, regs):
        if not os.path.isdir(d):
            sys.stderr.write('check_myshkin_h_coexist: not a directory: %s\n' % d)
            return 2
    incs = [commune, regs]

    cases = [
        ('legacy', True,
         '#include <myshkin.h>\n' + LEGACY_BODY),
        ('flag', True,
         '#define VESTA_REGS_STRUCTS 1\n'
         '#include <myshkin.h>\n#include <castalia_regs.h>\n' + STRUCT_BODY),
        ('regs-first', True,
         '#include <castalia_regs.h>\n#include <myshkin.h>\n' + STRUCT_BODY),
        ('control', False,
         '#include <myshkin.h>\n#include <castalia_regs.h>\n' + STRUCT_BODY),
    ]

    failures = 0
    for name, expectOk, source in cases:
        rc, out = _compile(cc, incs, source, name.replace('-', '_'))
        ok = (rc == 0) if expectOk else (rc != 0)
        print('  %-11s %s' % (name, 'OK' if ok else 'FAIL'))
        if not ok:
            failures += 1
            if expectOk:
                sys.stdout.write(out)
            else:
                sys.stderr.write('check_myshkin_h_coexist: the unguarded case '
                                 'compiled; the collision this test gates is gone '
                                 'or the test no longer reaches it\n')
    if failures:
        sys.stderr.write('check_myshkin_h_coexist: %d of %d cases wrong\n'
                         % (failures, len(cases)))
        return 1
    print('check_myshkin_h_coexist: %d of %d cases as expected' % (len(cases), len(cases)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
