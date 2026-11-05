#!/usr/bin/python3.6
"""Copy arch_test.h with the trap handlers moved to a section of their own.

Why: vesta_stub.S and vesta/env/link.ld put .vesta_tcm_text in the running hart's
TCM. A CSR read-modify-write whose following fetch stalls on the arbiter returns
the post-write value (see the riscof report), and the handler's first instruction
is `csrrw sp, mscratch, sp`, so a handler in shared RAM can never run. This is the
one change to the test environment; test sources are untouched and the reference
models build against the official header.
Usage: patch_arch_test.py <arch_test.h> <out.h>
"""
import sys

MACRO = '.macro RVTEST_TRAP_HANDLER __MODE__\n'
END = '.endm                                   // end of HANDLER\n'


def main():
    t = open(sys.argv[1]).read()
    if t.count(MACRO) != 1 or t.count(END) != 1:
        sys.exit('patch_arch_test: handler macro not found exactly once')
    t = t.replace(MACRO, MACRO + '.pushsection .vesta_tcm_text,"ax",@progbits\n')
    t = t.replace(END, '.popsection\n' + END)
    open(sys.argv[2], 'w').write(t)


if __name__ == '__main__':
    main()
