#!/usr/bin/env python3
"""VestaRV: inline a PSL vunit file into a copy of the bench architecture it binds.

GHDL 6.0.0 accepts a standalone .psl vunit and then never elaborates it, so a target that
analyzed one and ran the bench would be green and vacuous; the same property as a `-- psl`
comment inside the architecture does fire. Directives are emitted flattened to one line,
since repeating the psl keyword on a continuation line is a syntax error.
"""

import argparse
import os
import re
import sys

KINDS = ("assert", "assume", "cover", "restrict")


def strip_comments(text):
    """Drop -- line comments and /* */ blocks, respecting string literals."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = text.find('"', i + 1)
            if j < 0:
                out.append(text[i:])
                break
            out.append(text[i:j + 1])
            i = j + 1
        elif text.startswith("--", i):
            j = text.find("\n", i)
            if j < 0:
                break
            out.append("\n")
            i = j + 1
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            if j < 0:
                break
            out.append(" ")
            i = j + 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def split_statements(body):
    """Split a vunit body on top-level semicolons."""
    stmts = []
    depth = 0
    cur = []
    i = 0
    while i < len(body):
        c = body[i]
        if c == '"':
            j = body.find('"', i + 1)
            j = len(body) - 1 if j < 0 else j
            cur.append(body[i:j + 1])
            i = j + 1
            continue
        if c in "({[":
            depth += 1
        elif c in ")}]":
            depth -= 1
        if c == ";" and depth == 0:
            stmts.append("".join(cur).strip())
            cur = []
        else:
            cur.append(c)
        i += 1
    tail = "".join(cur).strip()
    if tail:
        stmts.append(tail)
    return [s for s in stmts if s]


VUNIT_RE = re.compile(
    r"\bvunit\s+([A-Za-z_]\w*)\s*\(\s*([A-Za-z_]\w*)\s*\(\s*([A-Za-z_]\w*)\s*\)\s*\)\s*\{",
    re.IGNORECASE)


def parse_psl(path):
    """Return (binding, [(vunit, name, kind, text)], default_clock_expr)."""
    raw = strip_comments(open(path, encoding="utf-8").read())
    vunits = []
    binding = None
    clock = None
    directives = []
    for m in VUNIT_RE.finditer(raw):
        vname, ent, arch = m.group(1), m.group(2), m.group(3)
        # Walk to the matching close brace.
        depth = 0
        i = m.end() - 1
        while i < len(raw):
            if raw[i] == "{":
                depth += 1
            elif raw[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        if depth != 0:
            sys.exit("%s: vunit %s is not closed" % (path, vname))
        body = raw[m.end():i]
        vunits.append(vname)
        b = (ent.lower(), arch.lower())
        if binding is None:
            binding = b
        elif binding != b:
            sys.exit("%s: vunit %s binds %s(%s) but an earlier vunit binds %s(%s)"
                     % (path, vname, ent, arch, binding[0], binding[1]))
        for st in split_statements(body):
            flat = " ".join(st.split())
            low = flat.lower()
            if low.startswith("default clock is"):
                expr = flat[len("default clock is"):].strip()
                if clock is None:
                    clock = expr
                elif clock != expr:
                    sys.exit("%s: conflicting default clock '%s' vs '%s'"
                             % (path, clock, expr))
                continue
            lm = re.match(r"([A-Za-z_]\w*)\s*:\s*(\w+)\s+(.*)$", flat, re.DOTALL)
            if not lm:
                sys.exit("%s: cannot parse directive %r" % (path, flat[:80]))
            name, kind, rest = lm.group(1), lm.group(2).lower(), lm.group(3)
            if kind not in KINDS:
                sys.exit("%s: %s has unsupported directive kind %r"
                         % (path, name, kind))
            directives.append((vname, name, kind, rest))
    if binding is None:
        sys.exit("%s: no vunit found" % path)
    if clock is None:
        sys.exit("%s: no `default clock is` declaration" % path)
    return binding, directives, clock


ARCH_RE_T = r"^\s*architecture\s+%s\s+of\s+%s\s+is\b"


def find_insertion(lines, ent, arch):
    """Line index of the `end` that closes architecture arch of ent."""
    head = re.compile(ARCH_RE_T % (re.escape(arch), re.escape(ent)), re.IGNORECASE)
    start = None
    for i, ln in enumerate(lines):
        if head.match(ln):
            start = i
            break
    if start is None:
        sys.exit("cannot find `architecture %s of %s is`" % (arch, ent))
    end = re.compile(r"^\s*end\s+(architecture\b|%s\s*;)" % re.escape(arch),
                     re.IGNORECASE)
    for i in range(start + 1, len(lines)):
        if end.match(lines[i]):
            return i
    sys.exit("cannot find the end of architecture %s of %s" % (arch, ent))


NEVER_RE = re.compile(r"^never\s*\{(.*)\}\s*$", re.IGNORECASE | re.DOTALL)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vhdl", required=True, help="the bench source to copy")
    ap.add_argument("--psl", required=True, action="append",
                    help="a PSL vunit file, repeatable")
    ap.add_argument("--out", required=True)
    ap.add_argument("--tally", action="store_true",
                    help="also emit the VHDL all-witnesses-hit monitor")
    ap.add_argument("--report", help="write a directive inventory here")
    args = ap.parse_args()

    binding = None
    clock = None
    directives = []
    for p in args.psl:
        b, d, c = parse_psl(p)
        if binding is None:
            binding, clock = b, c
        else:
            if b != binding:
                sys.exit("%s binds %s(%s), earlier files bind %s(%s)"
                         % (p, b[0], b[1], binding[0], binding[1]))
            if c != clock:
                sys.exit("%s declares default clock %r, earlier files %r"
                         % (p, c, clock))
        directives.extend((os.path.basename(p),) + t for t in d)
    if not directives:
        sys.exit("no PSL directives found -- refusing to write a vacuous bench")

    ent, arch = binding
    lines = open(args.vhdl, encoding="utf-8").read().split("\n")
    at = find_insertion(lines, ent, arch)
    indent = "    "

    block = [
        "",
        indent + "-- ================= GENERATED, DO NOT EDIT =================",
        indent + "-- verification/formal/psl_inline.py moved these directives out of",
        indent + "-- %s" % ", ".join(sorted(set(d[0] for d in directives))),
        indent + "-- and into the one form GHDL's simulator evaluates.  Edit the .psl.",
        indent + "-- psl default clock is %s;" % clock,
    ]
    for _src, vname, name, kind, rest in directives:
        block.append("%s-- psl %s : %s %s report \"PSL %s %s\";"
                     % (indent, name, kind, rest, kind.upper(), name))

    if args.tally:
        bools = []
        for _src, _vn, name, kind, rest in directives:
            m = NEVER_RE.match(rest.strip())
            if not m:
                sys.exit("--tally needs every directive to be `assert never {bool}`; "
                         "%s is %r" % (name, rest[:60]))
            bools.append((name, " ".join(m.group(1).split())))
        cm = re.match(r"rising_edge\s*\(\s*([A-Za-z_]\w*)\s*\)\s*$", clock,
                      re.IGNORECASE)
        if not cm:
            sys.exit("--tally needs a `rising_edge(<signal>)` default clock, got %r"
                     % clock)
        clk = cm.group(1)
        n = len(bools)
        block += [
            "",
            indent + "-- The gradeable half.  ghdl_test decides on ONE fixed string, and",
            indent + "-- \"every witness fired\" is not a string GHDL prints, so the same",
            indent + "-- booleans are sampled here and the banner is reported the first",
            indent + "-- time all of them have been seen.  The PSL directives above are",
            indent + "-- evaluated independently; their fires are in the run log.",
            indent + "psl_witness_tally : process (%s)" % clk,
            indent + "    variable hit  : std_logic_vector(%d downto 0) := (others => '0');" % (n - 1),
            indent + "    variable said : boolean := false;",
            indent + "begin",
            indent + "    if rising_edge(%s) then" % clk,
        ]
        for i, (name, expr) in enumerate(bools):
            block += [
                indent + "        if %s then" % expr,
                indent + "            if hit(%d) = '0' then" % i,
                indent + "                report \"PSL WITNESS HIT: %s\" severity note;" % name,
                indent + "            end if;",
                indent + "            hit(%d) := '1';" % i,
                indent + "        end if;",
            ]
        block += [
            indent + "        if (not said) and (hit = (hit'range => '1')) then",
            indent + "            report \"ALL %d WITNESSES HIT\" severity note;" % n,
            indent + "            said := true;",
            indent + "        end if;",
            indent + "    end if;",
            indent + "end process;",
        ]

    block.append(indent + "-- =============== END GENERATED BLOCK =====================")
    block.append("")

    out = lines[:at] + block + lines[at:]
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out))

    if args.report:
        with open(args.report, "w", encoding="utf-8") as fh:
            fh.write("binding: %s(%s)\ndefault clock: %s\n" % (ent, arch, clock))
            for src, vname, name, kind, _rest in directives:
                fh.write("%-28s %-26s %-8s %s\n" % (src, vname, kind, name))
            fh.write("total: %d directives\n" % len(directives))


if __name__ == "__main__":
    main()
