#!/usr/bin/env python3
# check_memorymap_vhd.py — Phase-1 acceptance checker for the generated MemoryMap.vhd
#
# Parses two VHDL packages (the hand-written RTL one in hdl/MCU_MP/ and the
# generated one in out/hdl/) and compares them constant-by-constant:
#   * every RTL constant must exist in the generated package (missing = FAIL)
#   * overlapping names must have identical values (mismatch = FAIL: there is
#     only ONE package in the design, a silent value change would corrupt RTL)
#   * types must be equivalent (slv == std_logic_vector, sl == std_logic;
#     natural/integer/positive are distinct-but-compatible -> warning only)
#   * extra generated constants are fine (informational)
#
# Expressions (e.g. "2 ** PeriphSlotGPIO0", "(NUM_IRQS + 31) / 32") are
# evaluated in file order against previously defined constants; VHDL integer
# '/' is mapped to Python '//'.
#
# Python 3.6 compatible. Usage:
#   python3 check_memorymap_vhd.py [<rtl.vhd> <generated.vhd>]
# Exit code 0 = drop-in compatible (names/values), 1 = not.

import os
import re
import sys

CONST_RE = re.compile(
    r'^\s*constant\s+(\w+)\s*:\s*([^:=]+?)\s*:=\s*(.+?)\s*;', re.IGNORECASE)

TYPE_ALIASES = {
    'slv': 'std_logic_vector',
    'sl': 'std_logic',
}


def normalize_type(typestr):
    t = ' '.join(typestr.split()).lower()
    m = re.match(r'^(\w+)(\s*\(.*\))?$', t)
    if m:
        base = TYPE_ALIASES.get(m.group(1), m.group(1))
        rng = m.group(2) or ''
        rng = re.sub(r'\s+', ' ', rng).replace('( ', '(').replace(' )', ')')
        return base + rng
    return t


def parse_value(valstr, env):
    """Return a canonical python value for a VHDL constant expression."""
    v = valstr.strip()
    # std_logic literal '0' / '1'
    m = re.match(r"^'([01])'$", v)
    if m:
        return ('sl', m.group(1))
    # hex bit-string X"...."
    m = re.match(r'^[xX]"([0-9a-fA-F_]+)"$', v)
    if m:
        return ('slv', int(m.group(1).replace('_', ''), 16))
    # binary bit-string "0101"
    m = re.match(r'^"([01_]+)"$', v)
    if m:
        return ('slv', int(m.group(1).replace('_', ''), 2))
    # boolean
    if v.lower() in ('true', 'false'):
        return ('bool', v.lower() == 'true')
    # plain integer literal (may have leading zeros, which eval() rejects)
    m = re.match(r'^\d+$', v)
    if m:
        return ('int', int(v, 10))
    # based literal 16#8000#
    v = re.sub(r'(\d+)#([0-9a-fA-F]+)#',
               lambda m: str(int(m.group(2), int(m.group(1)))), v)
    # leading-zero literals inside expressions would be a Python syntax error
    expr_pre = re.sub(r'\b0+(\d)', r'\1', v)
    v = expr_pre
    # integer expression over previously defined constants
    expr = v.replace('/', '//').replace('**//', '**/')  # '/' -> '//', keep '**'
    # the replace above would corrupt '**' -> '**' is safe ('**' has no '/'),
    # but '//' from a real '/' is what we want.
    names = set(re.findall(r'[A-Za-z_]\w+', expr))
    scope = {}
    for n in names:
        key = n.lower()
        if key not in env:
            return ('unresolved', valstr.strip())
        kind, val = env[key]
        if kind != 'int':
            return ('unresolved', valstr.strip())
        scope[n] = val
    try:
        return ('int', int(eval(expr, {'__builtins__': {}}, scope)))
    except Exception:
        return ('unresolved', valstr.strip())


def parse_package(path):
    """Return ordered list of (name, normtype, (kind, value), raw_line_no)."""
    consts = []
    env = {}  # lower-name -> (kind, value)
    with open(path) as f:
        for lineno, line in enumerate(f, 1):
            code = line.split('--', 1)[0]  # strip comments (also skips
            # commented-out constants)
            m = CONST_RE.match(code)
            if not m:
                continue
            name, typestr, valstr = m.group(1), m.group(2), m.group(3)
            val = parse_value(valstr, env)
            env[name.lower()] = val
            consts.append((name, normalize_type(typestr), val, lineno))
    return consts


def value_eq(a, b):
    ka, va = a
    kb, vb = b
    if 'unresolved' in (ka, kb):
        return None  # can't tell
    # compare numerics across slv/int kinds by numeric value
    if ka in ('slv', 'int') and kb in ('slv', 'int'):
        return va == vb
    return a == b


def main():
    home = os.path.expanduser('~')
    rtl_path = sys.argv[1] if len(sys.argv) > 2 else \
        os.path.join(home, 'vestarv/hdl/MCU_MP/MemoryMap.vhd')
    gen_path = sys.argv[2] if len(sys.argv) > 2 else \
        os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     '..', 'out', 'hdl', 'MemoryMap.vhd')

    rtl = parse_package(rtl_path)
    gen = parse_package(gen_path)
    gen_by_name = {}
    for name, t, v, ln in gen:
        gen_by_name[name.lower()] = (name, t, v, ln)

    missing = []
    value_mismatch = []
    type_mismatch = []
    type_warn = []
    unresolved = []

    for name, t, v, ln in rtl:
        g = gen_by_name.get(name.lower())
        if g is None:
            missing.append((name, t, v))
            continue
        gname, gt, gv, gln = g
        eq = value_eq(v, gv)
        if eq is None:
            unresolved.append((name, v, gv))
        elif not eq:
            value_mismatch.append((name, v, gv))
        if gt != t:
            # natural/integer/positive are compatible subtypes: warn only
            ints = ('natural', 'integer', 'positive')
            if gt in ints and t in ints:
                type_warn.append((name, t, gt))
            else:
                type_mismatch.append((name, t, gt))

    rtl_names = set(n.lower() for n, _, _, _ in rtl)
    extra = [n for n, _, _, _ in gen if n.lower() not in rtl_names]

    print('RTL constants:       %d  (%s)' % (len(rtl), rtl_path))
    print('Generated constants: %d  (%s)' % (len(gen), gen_path))
    print('Missing from generated: %d' % len(missing))
    for name, t, v in missing:
        print('  MISSING  %-24s : %-28s := %s' % (name, t, v[1]))
    print('Value mismatches (FATAL): %d' % len(value_mismatch))
    for name, v, gv in value_mismatch:
        print('  MISMATCH %-24s rtl=%s gen=%s' % (name, v[1], gv[1]))
    print('Type mismatches (FATAL): %d' % len(type_mismatch))
    for name, t, gt in type_mismatch:
        print('  TYPE     %-24s rtl=%s gen=%s' % (name, t, gt))
    if type_warn:
        print('Integer-subtype differences (warning only): %d' % len(type_warn))
        for name, t, gt in type_warn:
            print('  warn     %-24s rtl=%s gen=%s' % (name, t, gt))
    if unresolved:
        print('Unresolved value comparisons (check by hand): %d' % len(unresolved))
        for name, v, gv in unresolved:
            print('  ???      %-24s rtl=%r gen=%r' % (name, v, gv))
    print('Extra generated-only constants (OK): %d' % len(extra))

    ok = not missing and not value_mismatch and not type_mismatch \
        and not unresolved
    print('RESULT: %s' % ('DROP-IN COMPATIBLE' if ok else 'NOT COMPATIBLE'))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
