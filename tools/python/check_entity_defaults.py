#!/usr/bin/env python3.6
# -*- coding: utf-8 -*-
"""check_entity_defaults.py -- the ENTITY-DEFAULT AXIS checker (D1 acceptance).

WHY THIS EXISTS (DD7's five-sites finding, d0_fsm_probe.md 2.5).
---------------------------------------------------------------------------
A core feature knob's default is stated in FIVE independent places, not the
two that ``check_config_defaults.py`` polices:

    1. ``platform/common/python/generate.py``  ``_CONFIG_SCHEMA`` entry
    2. ``platform/common/python/generate.py``  the ``_cfg(...)`` CALL SITE
    3. ``hdl/common/vesta/vesta.vhd``          entity generic default
    4. ``hdl/common/hart_tile.vhd``            entity generic default
    5. ``hdl/common/MemoryMap.vhd``            the generated CORE_ENABLE_* constant

and there are two more that behave like defaults because an OMITTED generic
in a ``generic map`` silently inherits the entity's:

    6. ``hdl/common/hart_tile.vhd``            the ``component vesta`` declaration
    7. ``hdl/argus/MCU.vhd`` / ``hdl/common/MCU.vhd`` / the generator templates
       -- every ``hart_tile`` instantiation, whose OMISSION is a decision

Two of those already DISAGREE today for ``ENABLE_TRAPCSR`` (``vesta.vhd``
says ``false``, ``hart_tile.vhd`` says ``true``), and the frozen
``hdl/argus/MCU.vhd`` inherits the ``hart_tile`` value for all 18 tiles --
which is exactly how the Argus suite ran TRAPCSR-ON for two days with no way
to say so (F-K7-4).  D1's whole inertness claim rests on ``ENABLE_DEBUG``
being ``false`` everywhere it is DECLARED, so the claim rests on a class of
drift that has already happened once.  This is the instrument for it.

WHAT IT REPORTS
---------------------------------------------------------------------------
For a named generic, every site in the tree, classified:

    DECL      an entity / component generic DECLARATION with a default
    MAP       a ``generic map`` association giving it an explicit value
    OMIT      a ``hart_tile`` or ``vesta`` instantiation that does NOT name
              it -- i.e. it INHERITS the DECL default (a real decision, and
              the one that is invisible in review)
    CONST     a ``MemoryMap.vhd`` / template constant
    PY        a ``generate.py`` schema entry or ``_cfg`` call site

Exit codes:  0 = every requirement met.  1 = a requirement violated.
             2 = the instrument itself is not live (see the control below).

THE BUILT-IN LIVENESS CONTROL (method rule 4: validate against a known
NONZERO value, not only against zero).  ``--require-absent`` on a generic
that does not exist yet is an EXPECTED-ZERO answer, and a stale/broken
scanner returns the same zero.  So every run ALSO scans a control generic
(default ``ENABLE_TRAPCSR``) and requires at least ``--control-min`` sites.
If the control comes back short the script exits 2 -- "the scanner is dead"
-- instead of blessing the zero.

Deliberately NOT keyed on the trapCsr DISAGREEMENT (method rule 11: an
instrument keyed on a defect reports success the day the defect is fixed).
The disagreement is REPORTED, loudly, and never graded.

USAGE
    /usr/bin/python3.6 tools/python/check_entity_defaults.py               # ENABLE_DEBUG, D1 contract
    /usr/bin/python3.6 tools/python/check_entity_defaults.py -g ENABLE_UMODE --require-default false
    /usr/bin/python3.6 tools/python/check_entity_defaults.py -g ENABLE_TRAPCSR --report-only
"""

from __future__ import print_function

import argparse
import os
import re
import sys

# ---------------------------------------------------------------------------
# The site map.  Paths are repo-relative; a MISSING file is reported, never
# silently skipped (a renamed file must not read as "no violations here").
# ---------------------------------------------------------------------------
VHDL_DECL_FILES = [
    "hdl/common/vesta/vesta.vhd",
    "hdl/common/hart_tile.vhd",
    # D2: the Debug Module is a THIRD entity carrying ENABLE_DEBUG.  It is
    # knob-gated so the generator only ever instantiates it with the knob on,
    # but rule 15 is about the DECLARATION: a default justified by "nothing
    # instantiates it otherwise" silently becomes a behaviour the day someone
    # does, and gates get removed.
    "hdl/common/debug_module.vhd",
    # D3: the JTAG DTM is a FOURTH entity carrying ENABLE_DEBUG, and it is the
    # one whose OFF value has an external consequence -- with the knob off the
    # whole transport must fold, TDO included.  Same rule-15 argument as the
    # Debug Module: the DECLARATION is what a hand instantiation inherits.
    "hdl/common/jtag_dtm.vhd",
]

VHDL_INST_FILES = [
    "hdl/common/hart_tile.vhd",          # the inner `vesta` instantiation
    "hdl/common/MCU.vhd",                # hart0..hart3
    "hdl/argus/MCU.vhd",                 # the FROZEN 18-tile snapshot
    "platform/common/hdl_templates/MCU.template.vhd",
]

CONST_FILES = [
    "hdl/common/MemoryMap.vhd",
    "hdl/argus/MemoryMap.vhd",
    "platform/common/out/hdl/MemoryMap.vhd",
]

PY_FILES = [
    "platform/common/python/generate.py",
]

# The tile instantiations in the GENERATED MCU.vhd do not exist in
# MCU.template.vhd -- they are emitted by mcu_vhd.py (measured: the template
# mentions hart_tile only in comments).  So the "MCU template" site for a core
# generic is really the EMITTER, and it must be scanned as text.
EMIT_FILES = [
    "platform/common/python/mcu_vhd.py",
    "platform/common/hdl_templates/MCU.template.vhd",
]

# `entity <name> is` ... `end entity;`  and  `component <name>` ... `end component;`
RE_DECL_BLOCK = re.compile(
    r"^\s*(entity|component)\s+(\w+)\s*(is)?\s*$", re.IGNORECASE)
RE_INST = re.compile(
    r"^\s*(\w+)\s*:\s*(?:entity\s+work\.)?(\w+)\s*$", re.IGNORECASE)


def _read(path):
    """Read a file whatever its line endings.  hdl/common is MIXED CRLF/LF."""
    with open(path, "rb") as handle:
        raw = handle.read()
    return raw.decode("utf-8", "replace").replace("\r\n", "\n").split("\n")


def scan_decls(root, generic, files):
    """Entity/component generic DECLARATIONS carrying a default."""
    pat = re.compile(r"^\s*" + re.escape(generic) +
                     r"\s*:\s*(\w+)\s*:=\s*([^;)\s]+)", re.IGNORECASE)
    bare = re.compile(r"^\s*" + re.escape(generic) + r"\s*:\s*(\w+)\s*[;)]",
                      re.IGNORECASE)
    out = []
    for rel in files:
        path = os.path.join(root, rel)
        if not os.path.isfile(path):
            out.append(("MISSING", rel, 0, None, None))
            continue
        unit = "?"
        for num, line in enumerate(_read(path), 1):
            head = RE_DECL_BLOCK.match(line)
            if head:
                unit = "%s %s" % (head.group(1).lower(), head.group(2))
            hit = pat.match(line)
            if hit:
                out.append(("DECL", rel, num, unit, hit.group(2).strip()))
                continue
            hit = bare.match(line)
            if hit:
                # declared with NO default -- also a finding: every caller
                # must then name it, and an omission is an elaboration error
                # rather than a silent inheritance.
                out.append(("DECL", rel, num, unit, "<no-default>"))
    return out


def scan_insts(root, generic, files, targets=("vesta", "hart_tile", "debug_module")):
    """Instantiations of the target entities: MAP (explicit) or OMIT."""
    pat = re.compile(r"^\s*" + re.escape(generic) + r"\s*=>\s*([^,\s]+)",
                     re.IGNORECASE)
    out = []
    for rel in files:
        path = os.path.join(root, rel)
        if not os.path.isfile(path):
            out.append(("MISSING", rel, 0, None, None))
            continue
        lines = _read(path)
        idx = 0
        while idx < len(lines):
            hit = RE_INST.match(lines[idx])
            if not hit or hit.group(2).lower() not in targets:
                idx += 1
                continue
            label, ent = hit.group(1), hit.group(2)
            # walk the instantiation body to its `);` at map depth 0
            depth = 0
            value = None
            end = idx + 1
            started = False
            while end < len(lines):
                body = lines[end]
                stripped = body.split("--")[0]
                depth += stripped.count("(") - stripped.count(")")
                if "generic map" in body.lower() or "port map" in body.lower():
                    started = True
                got = pat.match(body)
                if got:
                    value = got.group(1).strip()
                if started and depth <= 0 and re.search(r"\)\s*;", stripped):
                    break
                end += 1
            kind = "MAP" if value is not None else "OMIT"
            out.append((kind, rel, idx + 1, "%s : %s" % (label, ent), value))
            idx = end + 1
    return out


def scan_consts(root, generic, files):
    """MemoryMap-style generated constants (CORE_<GENERIC>)."""
    name = "CORE_" + generic if not generic.startswith("CORE_") else generic
    pat = re.compile(r"^\s*constant\s+" + re.escape(name) +
                     r"\s*:\s*\w+\s*:=\s*([^;]+);", re.IGNORECASE)
    out = []
    for rel in files:
        path = os.path.join(root, rel)
        if not os.path.isfile(path):
            continue                       # generated/optional trees
        found = False
        for num, line in enumerate(_read(path), 1):
            hit = pat.match(line)
            if hit:
                out.append(("CONST", rel, num, name, hit.group(1).strip()))
                found = True
        if not found:
            # The file EXISTS and does not declare the constant.  That is the
            # F-K7-4 shape (hdl/argus/MemoryMap.vhd has no CORE_ENABLE_TRAPCSR,
            # so its 18 tiles inherit the hart_tile entity default with no way
            # to say so).  Never silent.
            out.append(("ABSENT", rel, 0, name, "<constant not declared>"))
    return out


def scan_emitters(root, generic, files):
    """The GENERATOR-side tile-instantiation emitters (text scan)."""
    name = "CORE_" + generic if not generic.startswith("CORE_") else generic
    out = []
    for rel in files:
        path = os.path.join(root, rel)
        if not os.path.isfile(path):
            out.append(("MISSING", rel, 0, None, None))
            continue
        for num, line in enumerate(_read(path), 1):
            if generic in line or name in line:
                out.append(("EMIT", rel, num, name, line.strip()[:88]))
    return out


def scan_py(root, generic, files):
    """generate.py: the _CONFIG_SCHEMA entry and the _cfg() call site.

    The knob key is the generic minus ENABLE_, lower-cased -- the generator's
    own convention (ENABLE_TRAPCSR <-> "trapCsr", ENABLE_DEBUG <-> "debug"/
    "enable").  Both spellings are searched; this scan is ADVISORY (it does
    not grade) because check_config_defaults.py already owns that pair.
    """
    stem = re.sub(r"^ENABLE_", "", generic).lower()
    out = []
    for rel in files:
        path = os.path.join(root, rel)
        if not os.path.isfile(path):
            out.append(("MISSING", rel, 0, None, None))
            continue
        key = re.compile(r"""['"]%s['"]""" % re.escape(stem), re.IGNORECASE)
        for num, line in enumerate(_read(path), 1):
            if not key.search(line):
                continue
            low = line.lower()
            if "_cfg(" in low or "schema" in low or "default" in low:
                out.append(("PY", rel, num, stem, line.strip()[:96]))
    return out


def collect(root, generic):
    rows = []
    rows += scan_decls(root, generic, VHDL_DECL_FILES)
    rows += scan_insts(root, generic, VHDL_INST_FILES)
    rows += scan_consts(root, generic, CONST_FILES)
    rows += scan_emitters(root, generic, EMIT_FILES)
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-g", "--generic", default="ENABLE_DEBUG",
                    help="the generic to audit (default ENABLE_DEBUG)")
    # The DEFAULTS ARE THE D1 CONTRACT.  A bare invocation must be the gate,
    # not a vacuous survey: at HEAD (no ENABLE_DEBUG anywhere) it MUST fail.
    ap.add_argument("--require-default", default="false",
                    help="every DECL site must carry this default (default: false)")
    ap.add_argument("--require-min-decls", type=int, default=5,
                    help="fail if fewer than N DECL sites are found (default 5 -- "
                         "the ENABLE_TRAPCSR-measured declaration-site count: the "
                         "two entities plus the three component declarations)")
    ap.add_argument("--require-min-consts", type=int, default=1,
                    help="fail if fewer than N generated CORE_<G> constants exist")
    ap.add_argument("--report-only", action="store_true",
                    help="print the census and always exit 0 (unless dead)")
    ap.add_argument("--control", default="ENABLE_TRAPCSR",
                    help="liveness-control generic (must be present)")
    ap.add_argument("--control-min", type=int, default=6,
                    help="minimum control sites for the scanner to be live")
    ap.add_argument("--root", default=os.environ.get("VESTA_ROOT"),
                    help="repo root (default: two levels above this file)")
    args = ap.parse_args()

    root = args.root or os.path.dirname(os.path.dirname(
        os.path.dirname(os.path.abspath(__file__))))

    # ---- liveness control FIRST (method rule 4) --------------------------
    ctl = collect(root, args.control)
    ctl_live = [r for r in ctl if r[0] in ("DECL", "MAP", "CONST")]
    print("== liveness control: %s ==" % args.control)
    for kind, rel, num, unit, val in ctl:
        print("   %-7s %-46s:%-5s %-28s %s" %
              (kind, rel, num or "-", unit or "", val if val is not None else ""))
    print("   control sites (DECL/MAP/CONST): %d (min %d)"
          % (len(ctl_live), args.control_min))
    if len(ctl_live) < args.control_min:
        print("FATAL: the scanner found only %d %s sites -- it is NOT LIVE, "
              "so any answer it gives about %s is worthless."
              % (len(ctl_live), args.control, args.generic))
        return 2
    ctl_decls = {(r[1], r[4]) for r in ctl if r[0] == "DECL"}
    ctl_vals = {v for _, v in ctl_decls}
    if len(ctl_vals) > 1:
        print("   NOTE (reported, never graded -- method rule 11): the %s "
              "entity defaults DISAGREE across sites: %s"
              % (args.control, sorted(ctl_vals)))

    # ---- the audit -------------------------------------------------------
    rows = collect(root, args.generic)
    print()
    print("== %s ==" % args.generic)
    if not rows:
        print("   (no sites at all)")
    for kind, rel, num, unit, val in rows:
        print("   %-7s %-46s:%-5s %-28s %s" %
              (kind, rel, num or "-", unit or "", val if val is not None else ""))

    advis = scan_py(root, args.generic, PY_FILES)
    if advis:
        print("   -- generator (advisory; check_config_defaults.py owns this pair)")
        for kind, rel, num, unit, val in advis:
            print("   %-7s %-46s:%-5s %s" % (kind, rel, num or "-", val or ""))

    decls = [r for r in rows if r[0] == "DECL"]
    maps = [r for r in rows if r[0] == "MAP"]
    omits = [r for r in rows if r[0] == "OMIT"]
    missing = [r for r in rows if r[0] == "MISSING"]
    print()
    print("   DECL=%d  MAP=%d  OMIT=%d  MISSING-FILE=%d"
          % (len(decls), len(maps), len(omits), len(missing)))
    for _, rel, _, _, _ in missing:
        print("   MISSING FILE: %s (renamed or moved -- the audit is INCOMPLETE)" % rel)

    if args.report_only:
        return 0

    consts = [r for r in rows if r[0] == "CONST"]
    absent = [r for r in rows if r[0] == "ABSENT"]

    rc = 0
    if not decls:
        # method rule 9: never print a well-formed verdict about an empty set.
        print("FAIL: %s is DECLARED NOWHERE -- there is nothing to audit. "
              "(The scanner is live: the %s control found %d sites above.)"
              % (args.generic, args.control, len(ctl_live)))
        rc = 1
    if args.require_min_decls is not None and len(decls) < args.require_min_decls:
        print("FAIL: %d DECL sites, require >= %d"
              % (len(decls), args.require_min_decls))
        rc = 1
    if args.require_min_consts is not None and len(consts) < args.require_min_consts:
        print("FAIL: %d generated CORE_%s constants, require >= %d"
              % (len(consts), args.generic, args.require_min_consts))
        rc = 1
    for _, rel, _, _, _ in absent:
        print("NOTE: %s exists but declares no CORE_%s -- every hart_tile "
              "instantiation in that tree inherits the ENTITY default "
              "(the F-K7-4 shape)." % (rel, args.generic))
    if args.require_default is not None:
        want = args.require_default.strip().lower()
        for _, rel, num, unit, val in decls:
            if (val or "").strip().lower() != want:
                print("FAIL: %s:%s (%s) declares %s := %s, require %s"
                      % (rel, num, unit, args.generic, val, want))
                rc = 1
    if missing:
        rc = 1
    if rc == 0:
        print("PASS: every %s declaration site carries the required default."
              % args.generic)
    return rc


if __name__ == "__main__":
    sys.exit(main())
