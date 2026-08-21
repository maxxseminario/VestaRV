#!/usr/bin/env python3
"""Contract check on the fpu_vec_gen output consumed by fpu_tb.vhd.

This proves what can be proven without a native reference toolchain on this
host: the emitted file has the exact fixed-width record layout fpu_tb.vhd
parses, the kind and op fields stay inside the ranges its MNAMES / SNAMES
tables index, and both FPU flavours are actually exercised.

It does NOT check numerical correctness of any vector. The reference itself
(SSE single precision plus glibc fmaf) is a property of the compiler and libc
that produced the generator binary, so numerical trust belongs to
gen_fpu_vectors.sh, not here.

Plain runner: exit 0 means pass. No pytest.
"""

import re
import sys

# K OO R AAAAAAAA BBBBBBBB CCCCCCCC RRRRRRRR FF
LINE_RE = re.compile(
    r"^([01]) (\d{2}) (\d) "
    r"([0-9A-F]{8}) ([0-9A-F]{8}) ([0-9A-F]{8}) ([0-9A-F]{8}) ([0-9A-F]{2})$"
)

MULTI_OP_MAX = 12   # FCVT_S_WU, the last entry of fpu_tb.vhd's MNAMES
SIMPLE_OP_MAX = 8   # FCLASS, the last entry of fpu_tb.vhd's SNAMES
MIN_VECTORS = 1000  # A sane floor; the generator emits tens of thousands.


def main(argv):
    if len(argv) != 2:
        print("usage: fpu_vectors_format_test.py <vector-file>")
        return 2
    path = argv[1]

    errors = []
    n_multi = 0
    n_simple = 0
    rounding_modes = set()
    multi_ops = set()
    simple_ops = set()

    with open(path, "r") as fh:
        for lineno, raw in enumerate(fh, start=1):
            line = raw.rstrip("\n")
            m = LINE_RE.match(line)
            if not m:
                errors.append("line %d: does not match the record format: %r"
                              % (lineno, line))
                if len(errors) > 20:
                    break
                continue
            kind = int(m.group(1))
            op = int(m.group(2))
            rm = int(m.group(3))
            flags = int(m.group(8), 16)

            if kind == 0:
                n_multi += 1
                multi_ops.add(op)
                if op > MULTI_OP_MAX:
                    errors.append("line %d: multi op %d exceeds MNAMES range 0..%d"
                                  % (lineno, op, MULTI_OP_MAX))
            else:
                n_simple += 1
                simple_ops.add(op)
                if op > SIMPLE_OP_MAX:
                    errors.append("line %d: simple op %d exceeds SNAMES range 0..%d"
                                  % (lineno, op, SIMPLE_OP_MAX))

            rounding_modes.add(rm)
            if rm > 4:
                errors.append("line %d: rounding mode %d outside 0..4" % (lineno, rm))
            if flags & ~0x1F:
                errors.append("line %d: flag byte %02X sets a bit above NV"
                              % (lineno, flags))

    total = n_multi + n_simple
    if total < MIN_VECTORS:
        errors.append("only %d vectors, expected at least %d" % (total, MIN_VECTORS))
    if n_multi == 0:
        errors.append("no kind 0 (multi-cycle fpu) vectors emitted")
    if n_simple == 0:
        errors.append("no kind 1 (combinational fpu_simple) vectors emitted")
    if rounding_modes != {0, 1, 2, 3, 4}:
        errors.append("rounding modes exercised = %s, expected all of 0..4"
                      % sorted(rounding_modes))
    if multi_ops != set(range(MULTI_OP_MAX + 1)):
        errors.append("multi ops exercised = %s, expected all of 0..%d"
                      % (sorted(multi_ops), MULTI_OP_MAX))
    if simple_ops != set(range(SIMPLE_OP_MAX + 1)):
        errors.append("simple ops exercised = %s, expected all of 0..%d"
                      % (sorted(simple_ops), SIMPLE_OP_MAX))

    print("vectors: %d total (%d multi-cycle, %d combinational)"
          % (total, n_multi, n_simple))
    if errors:
        for e in errors:
            print("FAIL: %s" % e)
        return 1
    print("PASS: fpu vector record contract holds")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
