#!/usr/bin/env python3.6
# =============================================================================
# d4_entity_invariance.py -- the D4 FAIL-SAFE clause, mechanised.
#
# BLIND-AUTHORED 2026-08-07 against d4_spec.md 1.6 (FROZEN) by an agent that
# has not seen and will never see the D4 implementation.
#
#   /usr/bin/python3.6 tools/cosim/d4_entity_invariance.py
#
#   rc 0  the debug_module entity's generic and port name lists are EXACTLY
#         the D3 baseline (pinned below at d-series 286921d)
#   rc 1  a name was added, removed or renamed -- each one quoted
#   rc 2  the entity block could not be parsed at all
#
# THE CLAUSE.  d4_spec 1.6: "the plant adds NO new entity ports and NO generics
# (the table is internal).  If the implementer finds a generator/emission touch
# necessary after all: STOP-AND-REPORT."  That is a STOP condition, and a stop
# condition that is only checked by reading a diff gets missed exactly once.
#
# WHY A NAME LIST AND NOT AN md5 OF THE BLOCK.  The implementer is expected to
# edit debug_module.vhd extensively -- a 40-word constant table, a new
# sequencer state, a plant-done latch, and per d4_spec 4 a rewritten comment
# block.  An md5 of the whole entity would fire on a comment and would then be
# ignored, which is worse than not checking.  What d4_spec 1.6 actually freezes
# is the INTERFACE: generic names, port names, and each port's direction.  A
# widened vector or a changed default is deliberately NOT policed here -- it
# would be caught by the knob-OFF bit-identity pins, and I1
# (check_entity_defaults.py) already owns the fail-safe-default question.
#
# Method note (rule 4): this script's own parse is validated against a KNOWN
# NONZERO on every run -- it re-parses a deliberately mutated copy of the
# entity in memory and requires itself to notice.  A parser that silently
# matched nothing would otherwise report "0 differences" forever.
# =============================================================================
from __future__ import print_function
import os
import re
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
VHDL = os.path.join(REPO, 'hdl', 'common', 'debug_module.vhd')

# `--vhdl <path>` exists so this instrument's own FAIL leg can be DEMONSTRATED
# on a scratch copy without editing tracked RTL.  An acceptance instrument that
# can only be shown to fail by damaging the tree cannot be shown to fail at all.
for _i, _a in enumerate(sys.argv):
    if _a == '--vhdl' and _i + 1 < len(sys.argv):
        VHDL = os.path.abspath(sys.argv[_i + 1])

BASE_GENERICS = [
    'ENABLE_DEBUG', 'NHARTS', 'SH_AW', 'DATA0_ADDR', 'FLAGS_ADDR', 'ENTRY_ADDR',
]
BASE_PORTS = [
    ('clk', 'in'), ('resetn', 'in'),
    ('dmi_req_valid', 'in'), ('dmi_req_op', 'in'), ('dmi_req_addr', 'in'),
    ('dmi_req_data', 'in'), ('dmi_req_ready', 'out'), ('dmi_rsp_valid', 'out'),
    ('dmi_rsp_data', 'out'), ('dmi_rsp_op', 'out'),
    ('dbg_haltreq', 'out'), ('dbg_resethaltreq', 'out'), ('dbg_halted', 'in'),
    ('hart_unavail', 'in'),
    ('m_req', 'out'), ('m_we', 'out'), ('m_addr', 'out'), ('m_wdata', 'out'),
    ('m_gnt', 'in'), ('m_done', 'in'), ('m_rdata', 'in'),
]


def strip_comments(text):
    return '\n'.join(re.sub(r'--.*$', '', ln) for ln in text.split('\n'))


def parse(text):
    """Return (generic_names, [(port_name, direction)]) or None."""
    m = re.search(r'\bentity\s+debug_module\s+is\b(.*?)\bend\s+entity\b',
                  strip_comments(text), re.S | re.I)
    if not m:
        return None
    body = m.group(1)
    g = re.search(r'\bgeneric\s*\((.*?)\)\s*;\s*\bport\b', body, re.S | re.I)
    p = re.search(r'\bport\s*\((.*)\)\s*;\s*$', body.strip(), re.S | re.I)
    if g is None or p is None:
        return None
    gens = []
    for decl in g.group(1).split(';'):
        mm = re.match(r'\s*([A-Za-z]\w*)\s*:', decl)
        if mm:
            gens.append(mm.group(1))
    ports = []
    for decl in p.group(1).split(';'):
        mm = re.match(r'\s*([A-Za-z]\w*)\s*:\s*(in|out|inout|buffer)\b', decl, re.I)
        if mm:
            ports.append((mm.group(1), mm.group(2).lower()))
    if not gens or not ports:
        return None
    return gens, ports


def selftest():
    """Known-nonzero: the parser must notice an added port in a mutated copy."""
    text = open(VHDL).read()
    mutated = text.replace('        m_req   : out std_logic;',
                           '        d4_selftest_port : out std_logic;\n'
                           '        m_req   : out std_logic;', 1)
    if mutated == text:
        print('SELFTEST INCONCLUSIVE: the anchor line for the mutation was not'
              ' found, so this run cannot show its own parser is live.'
              '  Treating that as a failure (method rule 5).')
        return False
    r = parse(mutated)
    if r is None:
        print('SELFTEST FAILED: the mutated entity did not parse at all.')
        return False
    names = [n for (n, _) in r[1]]
    if 'd4_selftest_port' not in names:
        print('SELFTEST FAILED: the parser did NOT see an added port.'
              '  Every "no change" verdict from this script would be vacuous.')
        return False
    print('selftest ok: the parser sees an injected port (known nonzero)')
    return True


def main():
    if not os.path.exists(VHDL):
        print('rc2: no %s' % VHDL)
        return 2
    if not selftest():
        return 2
    r = parse(open(VHDL).read())
    if r is None:
        print('rc2: could not parse the debug_module entity block')
        return 2
    gens, ports = r
    bad = []
    if gens != BASE_GENERICS:
        bad.append('generics: got %r\n           want %r' % (gens, BASE_GENERICS))
        for n in sorted(set(gens) - set(BASE_GENERICS)):
            bad.append('  ADDED generic   %s' % n)
        for n in sorted(set(BASE_GENERICS) - set(gens)):
            bad.append('  REMOVED generic %s' % n)
    if ports != BASE_PORTS:
        gn = dict(ports)
        bn = dict(BASE_PORTS)
        for n in sorted(set(gn) - set(bn)):
            bad.append('  ADDED port      %s : %s' % (n, gn[n]))
        for n in sorted(set(bn) - set(gn)):
            bad.append('  REMOVED port    %s : %s' % (n, bn[n]))
        for n in sorted(set(gn) & set(bn)):
            if gn[n] != bn[n]:
                bad.append('  DIRECTION       %s : %s (was %s)' % (n, gn[n], bn[n]))
        if not bad:
            bad.append('  ORDER changed: got %r' % [n for (n, _) in ports])
    if bad:
        print('D4 ENTITY INVARIANCE FAILED -- d4_spec 1.6 says the plant adds'
              ' NO new ports and NO generics, and calls a generator/emission'
              ' touch a STOP-AND-REPORT:')
        for b in bad:
            print(b)
        return 1
    print('ok: %d generics, %d ports, identical to the D3 baseline'
          % (len(gens), len(ports)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
