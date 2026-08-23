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

Two of those DISAGREE for ``ENABLE_TRAPCSR`` (``vesta.vhd`` says ``false``,
``hart_tile.vhd`` says ``true``), and the frozen ``hdl/argus/MCU.vhd``
inherits the ``hart_tile`` value for all 18 tiles -- which is exactly how the
Argus suite ran TRAPCSR-ON for two days with no way to say so (F-K7-4).  This
is the instrument for that class of drift.

THE REQUIREMENT IS PER CLASS, NOT ONE VALUE FOR THE WHOLE TREE.
---------------------------------------------------------------------------
The original D1 contract was "``ENABLE_DEBUG`` is ``false`` at every DECL
site".  That was the correct requirement while debug was an opt-in knob, and
it is the WRONG one now: ``debug.enable`` became a SHIPPED default on
2026-08-16, ``hdl/common/MemoryMap.vhd`` says ``CORE_ENABLE_DEBUG := true``,
and ``hart_tile``/``orch_tile`` were flipped to match in the same change.
The declaration sites are two different kinds of object and they answer to two
different rules:

  CORE class    ``vesta`` and the component declarations that stand for it,
                plus ``debug_module`` and ``jtag_dtm``.  These must carry
                ``--require-default`` (``false``).  A top that instantiates
                the core, the DM or the DTM and names no debug generic gets an
                inert unit: enabling debug is always a NAMED association,
                never an inherited one.  That is the surviving half of the old
                rationale, and it is what keeps a hand-written bench or a
                third-party top from acquiring a debug port by omission.

  WRAPPER class ``entity hart_tile`` and ``entity orch_tile``, the units a
                ``genus elaborate`` hardening run instantiates BARE.  Their
                default must equal the SHIPPED value, measured from
                ``CORE_<G>`` in ``hdl/common/MemoryMap.vhd`` rather than
                written here as a literal.  The hazard is M14's, not the
                attack-surface one: ``MCU.vhd`` passes
                ``ENABLE_DEBUG => CORE_ENABLE_DEBUG`` while a bare elaborate
                takes the entity default, so a wrapper default that disagrees
                with the shipped constant hardens a macro the assembly then
                wires the other way, silently.

Deriving the wrapper requirement from the generated constant is what stops
this checker going stale a second time: flip the knob back and the required
wrapper default flips with it, in the same commit, with no edit here.

THE CONTRACT IS PER GENERIC, AND THERE ARE NOW TWO OF THEM.
---------------------------------------------------------------------------
``ENABLE_IF_AHEAD`` (the C-extension fetch-ahead, shipped ON 2026-08-23) is
the second core knob to take this shape, and it needed NO new code here: the
site map, the two classes and the shipped-value oracle are all keyed on the
generic name, so it is selected with ``-g ENABLE_IF_AHEAD`` and graded by the
same rule.  Both generics are run as separate graded targets in
``tools/python/BUILD.bazel``.

The ONE parameter that is per-generic is the DECL-site floor.  It exists so a
scanner that stopped matching cannot pass as clean, so it must be the MEASURED
count for the generic under audit, not a shared guess:

    ENABLE_DEBUG      5   entity vesta, two component declarations inside
                          vesta.vhd (csr_unit and maindec carry it), entity
                          hart_tile, the component vesta inside hart_tile.vhd,
                          entity orch_tile, plus debug_module and jtag_dtm
    ENABLE_IF_AHEAD   4   entity vesta, entity hart_tile, the component vesta
                          inside hart_tile.vhd, entity orch_tile.  It is
                          consumed WHOLLY INSIDE vesta.vhd (if_ahead_req), so
                          no sub-block declaration carries it and neither the
                          Debug Module nor the JTAG DTM has ever heard of it.

A generic added to a sub-block later RAISES its floor; lowering one is how
this instrument goes blind, so a drop in the count is a finding.

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

THE SECOND AXIS: MGMT_HART -- REBASED AT CPR3, AND THE INVARIANT INVERTED.
---------------------------------------------------------------------------
Everything above is about a DECLARATION drifting.  CP3 found the other half of
the same class, and this instrument was blind to it: an INSTANTIATION that
OMITS a generic whose entity default is silently WRONG for the configuration
being built.  ``afe_stub.vhd`` declares

    OWNER_HART : natural := 0;
    MGMT_HART  : natural := 0;      -- CP1 D4

and its access gate is ``master = OWNER_HART or master = MGMT_HART``.  The CP2
emitter (``mcu_vhd.py`` ``afeStubsWithMgmt``) rewrote the EIS engine's
association to ``OWNER_HART => 4`` and left ``MGMT_HART`` OMITTED, so the gate
elaborated as ``{4, 0}`` and **hart 0 silently kept the EIS access D4 had moved
to the orchestrator**.  Every gate stayed green; only ``shorch``'s negative
control found it.

**CPR3/R1 RETIRED THE MOVE ITSELF, so this axis now grades the OPPOSITE
POLARITY.**  The orchestrator was renumbered to hart 0, which means the
management hart is hart 0 in BOTH shapes -- the historical four-tile chip and
the penta chip alike.  There is therefore no configuration in which
``MGMT_HART`` should be anything but its entity default, and the generator has
no business ever emitting the association.  A named MGMT_HART in 2026-08+ RTL
does not merely differ from the default; it is evidence that something is
re-deriving the CP2 index arithmetic that R1 deleted.

The generic STAYS on the entity: it is the documented seam (CPR1 R1 says so in
as many words), and a future chip that really does move the privilege off hart 0
needs it there.  What is graded is that nobody uses it.

    DECL   ``afe_stub.vhd`` declares MGMT_HART, and its default must be 0.
           This is now load-bearing on EVERY configuration, not just the
           default one -- there is no override anywhere to correct it.
    OMIT   an ``afe_stub`` instantiation that does NOT name MGMT_HART.  This
           is the required state, everywhere.
    MAP    one that DOES -- a VIOLATION now, on any path, in any file.
    EMIT   the generator-side emission sites, split into the VERBATIM class
           (module-scope golden-master text) and the ORCHESTRATOR class (a
           function whose body knows about the orchestrator).  BOTH must omit
           MGMT_HART; the orchestrator class is still counted separately so a
           restructured emitter that stops producing orchestrator text at all
           cannot pass as clean.

USAGE
    /usr/bin/python3.6 tools/python/check_entity_defaults.py               # ENABLE_DEBUG two-class contract + the MGMT_HART axis
    /usr/bin/python3.6 tools/python/check_entity_defaults.py -g ENABLE_IF_AHEAD --require-min-decls 4 --skip-mgmt-hart
    /usr/bin/python3.6 tools/python/check_entity_defaults.py -g ENABLE_UMODE --tile-default same
    /usr/bin/python3.6 tools/python/check_entity_defaults.py -g ENABLE_TRAPCSR --report-only
    /usr/bin/python3.6 tools/python/check_entity_defaults.py --skip-mgmt-hart
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
    # CP2: orch_tile is a FIFTH entity carrying the core generics -- a bare
    # wrapper around hart_tile, so its declaration defaults are inherited by
    # any instantiation that omits them (the genus `elaborate orch_tile`
    # hardening run does exactly that). Same rule-15 argument as debug_module:
    # a default justified by "the generator always names it" becomes a
    # behaviour the day something else instantiates it.
    "hdl/common/orch_tile.vhd",
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

# THE WRAPPER CLASS.  Keyed on (file, unit) rather than file, because
# hart_tile.vhd carries BOTH classes: `entity hart_tile` is a wrapper, while
# the `component vesta` a few hundred lines below it stands for the core and
# stays in the core class.  A site not listed here is core-class.
TILE_DECL_SITES = frozenset([
    ("hdl/common/hart_tile.vhd", "entity hart_tile"),
    ("hdl/common/orch_tile.vhd", "entity orch_tile"),
])

# Where the SHIPPED value of a core knob is recorded: the generated constant
# the default build's MCU.vhd actually passes to every tile.  This is the
# oracle for the wrapper class, so the requirement cannot go stale behind a
# knob flip the way a literal `false` in this file did.
SHIPPED_CONST_FILE = "hdl/common/MemoryMap.vhd"

VHDL_INST_FILES = [
    "hdl/common/hart_tile.vhd",          # the inner `vesta` instantiation
    "hdl/common/orch_tile.vhd",          # CP2: the inner `hart_tile` pass-through
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

# ---------------------------------------------------------------------------
# THE MGMT_HART AXIS (CP6).  A separate site map, because the sites are not the
# core-generic sites: the generic lives on `afe_stub`, is instantiated five
# times inside MCU.vhd, and is EMITTED by mcu_vhd.py rather than templated.
# ---------------------------------------------------------------------------
AFE_DECL_FILES = [
    "hdl/common/afe_stub.vhd",
]

# MCU-class VHDL carrying `afe_stub` instantiations.  This one is a TRACKED
# file; its absence is graded, never skipped, because the golden master going
# missing is itself the finding.
AFE_INST_FILES = [
    "hdl/common/MCU.vhd",                       # the N=4 golden master
]

# Generated MCU.vhd copies under gitignored output trees: whatever `make chip`
# last emitted, and the staged xcelium/ builds.  The xcelium pair are the ONLY
# on-disk artifacts of a NON-DEFAULT (orchestrator) build, so they are where the
# eis0 defect actually manifested.  All of them are TRANSIENT -- absent in a
# clean checkout and in a bazel sandbox, present in a working tree -- so their
# absence is REPORTED as reduced coverage rather than graded as a violation.
# Every one that IS on disk is graded exactly as the tracked file above.
AFE_INST_OPTIONAL = [
    "platform/common/out/hdl/MCU.vhd",          # whatever `make chip` last emitted
    "xcelium/riscv_test/verify_castaliapenta/hdl/MCU.vhd",
    "xcelium/riscv_test/verify_pentawound/hdl/MCU.vhd",
]

AFE_EMIT_FILES = [
    "platform/common/python/mcu_vhd.py",
]

# Measured floors, so a restructured emitter cannot pass by emitting NOTHING.
# VERBATIM = the five golden-master `generic map (OWNER_HART => n)` lines in the
# module-scope AFE_SLOT12_INSTANCES table.  ORCHESTRATOR = the emission sites
# (branches, NOT instances) inside `afeStubsOrchOwners`: one for the EIS engine,
# one for the four AFE sites.  REBASED at CPR3 and DELIBERATELY UNCHANGED in
# value: the CP2 emitter had the same two branches, and the eis0 branch survived
# the rewrite precisely so this floor keeps its teeth (its OWNER_HART => 0 line
# could have been left to fall through unchanged, which would have dropped the
# count to 1 and quietly halved the audit).
MGMT_MIN_VERBATIM_EMITS = 5
MGMT_MIN_ORCH_EMITS = 2

RE_AFE_INST = re.compile(
    r"^\s*(\w+)\s*:\s*entity\s+work\.afe_stub\s*$", re.IGNORECASE)
RE_GENERIC_OWNER = re.compile(r"generic\s+map\s*\(\s*OWNER_HART\s*=>", re.IGNORECASE)
RE_PYDEF = re.compile(r"^(\s*)def\s+(\w+)\s*\(")


def scan_afe_insts(root, files, optional=False):
    """`afe_stub` instantiations: does each name MGMT_HART, or inherit it?

    Returns (kind, rel, lineno, label, detail) with kind in MAP / OMIT /
    MISSING / SKIPPED.  The OWNER_HART value is carried in `detail` because the
    eis0 shape is precisely "OWNER_HART moved, MGMT_HART did not".
    """
    out = []
    for rel in files:
        path = os.path.join(root, rel)
        if not os.path.isfile(path):
            out.append(("SKIPPED" if optional else "MISSING", rel, 0, None,
                        "<not on disk>"))
            continue
        lines = _read(path)
        for num, line in enumerate(lines, 1):
            hit = RE_AFE_INST.match(line)
            if not hit:
                continue
            label = hit.group(1)
            # the association list is the next few lines, up to the `port map`
            owner, mgmt = None, None
            probe = num                      # 0-based index of the NEXT line
            while probe < len(lines) and probe < num + 6:
                body = lines[probe]
                if re.search(r"port\s+map", body, re.IGNORECASE):
                    break
                got = re.search(r"OWNER_HART\s*=>\s*([^,\s)]+)", body, re.IGNORECASE)
                if got:
                    owner = got.group(1)
                got = re.search(r"MGMT_HART\s*=>\s*([^,\s)]+)", body, re.IGNORECASE)
                if got:
                    mgmt = got.group(1)
                probe += 1
            detail = "OWNER_HART => %s, MGMT_HART %s" % (
                owner if owner is not None else "<inherited>",
                ("=> " + mgmt) if mgmt is not None else "<inherited := entity default>")
            out.append(("MAP" if mgmt is not None else "OMIT",
                        rel, num, "%s : afe_stub" % label, detail))
    return out


def scan_mgmt_emitters(root, files):
    """The generator-side emission sites, classified by EMITTING SCOPE.

    A site is a source line that EMITS a `generic map (OWNER_HART => ...)`
    string -- an `.append(...)` call or a bare string element of a module-scope
    table.  Matcher lines (`if s.startswith('generic map (OWNER_HART =>')`) and
    comments are NOT sites; they describe the text, they do not produce it.

    Scope decides the rule:
      <module>      the VERBATIM golden-master table -- must NOT name MGMT_HART
      <function>    orchestrator-aware iff its own body mentions MGMT_HART or
                    mgmtHart -- then it MUST name MGMT_HART on every site
    """
    out = []
    for rel in files:
        path = os.path.join(root, rel)
        if not os.path.isfile(path):
            out.append(("MISSING", rel, 0, None, None, None))
            continue
        lines = _read(path)
        # pass 1: scope per line
        scopes = []
        scope = "<module>"
        indents = []              # (indent, name) stack of open defs
        for line in lines:
            if line.strip() and not line[0].isspace():
                scope = "<module>"
                indents = []
            hit = RE_PYDEF.match(line)
            if hit:
                ind = len(hit.group(1).expandtabs(4))
                while indents and indents[-1][0] >= ind:
                    indents.pop()
                indents.append((ind, hit.group(2)))
                scope = hit.group(2)
            elif indents and line.strip():
                cur = len(line[:len(line) - len(line.lstrip())].expandtabs(4))
                while indents and cur <= indents[-1][0]:
                    indents.pop()
                scope = indents[-1][1] if indents else "<module>"
            scopes.append(scope)
        # pass 2: which scopes know about the management hart
        bodies = {}
        for line, sc in zip(lines, scopes):
            bodies[sc] = bodies.get(sc, "") + line + "\n"
        # pass 3: the sites
        for num, (line, sc) in enumerate(zip(lines, scopes), 1):
            if not RE_GENERIC_OWNER.search(line):
                continue
            stripped = line.strip()
            emits = (".append(" in line
                     or stripped.startswith("'") or stripped.startswith('"'))
            if not emits:
                continue
            if sc == "<module>":
                cls = "VERBATIM"
            else:
                body = bodies.get(sc, "")
                # CPR3: orchestrator-awareness can no longer be detected by
                # "does this function mention MGMT_HART" -- the correct
                # orchestrator emitter mentions it only to say it does not use
                # it.  Key on the orchestrator vocabulary instead.
                cls = ("ORCH" if ("MGMT_HART" in body or "mgmtHart" in body
                                  or "OrchOwners" in body or "self.orch" in body)
                       else "PLAIN")
            named = "MGMT_HART" in line
            out.append(("EMIT", rel, num, sc, cls,
                        ("names MGMT_HART" if named else "OMITS MGMT_HART")
                        + " | " + stripped[:76]))
    return out

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


def audit_mgmt_hart(root, report_only=False):
    """The MGMT_HART axis (CP6).  Returns an exit code contribution.

    0 = the pairing holds everywhere.  1 = a violation.  2 = the scanner found
    too few sites to be believed (method rule 4 again: a restructured emitter
    that produces no matches must not read as "clean").
    """
    print()
    print("== MGMT_HART (afe_stub ownership gate; CPR3/R1: never overridden) ==")

    rc = 0

    # ---- 1. the DECLARATION, which is the hinge of the whole scheme --------
    decls = scan_decls(root, "MGMT_HART", AFE_DECL_FILES)
    owner_decls = scan_decls(root, "OWNER_HART", AFE_DECL_FILES)
    for kind, rel, num, unit, val in owner_decls + decls:
        print("   %-8s %-52s:%-5s %-22s %s" %
              (kind, rel, num or "-", unit or "", val if val is not None else ""))
    real_decls = [r for r in decls if r[0] == "DECL"]
    if not real_decls:
        print("FAIL: MGMT_HART is DECLARED NOWHERE in %s -- the OMIT sites below "
              "inherit nothing and this audit is meaningless."
              % ", ".join(AFE_DECL_FILES))
        rc = 1
    for _, rel, num, unit, val in real_decls:
        if (val or "").strip() != "0":
            print("FAIL: %s:%s (%s) declares MGMT_HART := %s, require 0 -- the "
                  "default build OMITS the association, so a non-zero default "
                  "would silently move the management privilege on EVERY chip."
                  % (rel, num, unit, val))
            rc = 1
    if [r for r in decls if r[0] == "MISSING"]:
        rc = 1

    # ---- 2. the VHDL instantiations: MGMT_HART MUST NEVER BE NAMED ---------
    print("   -- afe_stub instantiations (CPR3: every one must INHERIT MGMT_HART)")
    rows = (scan_afe_insts(root, AFE_INST_FILES)
            + scan_afe_insts(root, AFE_INST_OPTIONAL, optional=True))
    for kind, rel, num, unit, val in rows:
        print("   %-8s %-52s:%-5s %-22s %s" %
              (kind, rel, num or "-", unit or "", val or ""))
        if kind == "SKIPPED":
            print("   NOT ON DISK: %s -- a generated tree that was never built "
                  "here, so this run grades fewer instantiations than a working "
                  "tree would.  Not a violation; not a clean bill either." % rel)
        if kind == "MAP":
            print("FAIL: %s:%s (%s) NAMES MGMT_HART.  CPR3/R1 made hart 0 the "
                  "management hart on EVERY configuration, so the association "
                  "has no correct value to carry and no emitter should produce "
                  "it -- this is CP2 index arithmetic that R1 deleted, coming "
                  "back.  %s" % (rel, num, unit, val))
            rc = 1
        elif kind == "MISSING":
            print("   MISSING FILE: %s -- the audit is INCOMPLETE" % rel)
            rc = 1

    # ---- 3. the GENERATOR emission sites ----------------------------------
    print("   -- generator emission sites (mcu_vhd.py), by emitting scope")
    emits = scan_mgmt_emitters(root, AFE_EMIT_FILES)
    nverb = norch = 0
    for row in emits:
        if row[0] == "MISSING":
            print("   MISSING FILE: %s -- the audit is INCOMPLETE" % row[1])
            rc = 1
            continue
        _kind, rel, num, scope, cls, val = row
        print("   %-8s %-52s:%-5s %-22s %s" % (cls, rel, num, scope, val))
        if cls == "VERBATIM":
            nverb += 1
            if "names MGMT_HART" in val:
                print("FAIL: %s:%s emits MGMT_HART from the VERBATIM golden-master "
                      "table -- the default build would stop being byte-identical "
                      "to hdl/common/MCU.vhd." % (rel, num))
                rc = 1
        elif cls == "ORCH":
            norch += 1
            if "names MGMT_HART" in val:
                print("FAIL: %s:%s (in %s) emits an MGMT_HART association from the "
                      "orchestrator emitter.  CPR3/R1 put the orchestrator ON hart "
                      "0, so the management hart is hart 0 everywhere and the "
                      "entity default is correct in every configuration -- naming "
                      "it means someone re-derived the retired CP2 index."
                      % (rel, num, scope))
                rc = 1

    print()
    print("   MGMT_HART: DECL=%d  MAP=%d  OMIT=%d  EMIT(verbatim)=%d  EMIT(orch)=%d"
          % (len(real_decls),
             len([r for r in rows if r[0] == "MAP"]),
             len([r for r in rows if r[0] == "OMIT"]),
             nverb, norch))

    if nverb < MGMT_MIN_VERBATIM_EMITS or norch < MGMT_MIN_ORCH_EMITS:
        print("FATAL: only %d verbatim / %d orchestrator emission sites found "
              "(require >= %d / >= %d).  The emitter has been restructured and "
              "this audit no longer reaches it -- re-derive the site map instead "
              "of reading the silence as clean."
              % (nverb, norch, MGMT_MIN_VERBATIM_EMITS, MGMT_MIN_ORCH_EMITS))
        return 2

    if report_only:
        return 0
    if rc == 0:
        print("PASS: MGMT_HART is declared with default 0, no afe_stub "
              "instantiation names it, and no emission site -- verbatim or "
              "orchestrator -- produces it.  The management hart is hart 0 in "
              "every shape (CPR3/R1), which is what makes the default correct.")
    return rc


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
    # The DEFAULTS ARE THE CONTRACT.  A bare invocation must be the gate, not
    # a vacuous survey, so both requirements below are on unless overridden.
    ap.add_argument("--require-default", default="false",
                    help="every CORE-class DECL site (the core, its component "
                         "declarations, debug_module, jtag_dtm) must carry this "
                         "default (default: false)")
    ap.add_argument("--tile-default", default="shipped",
                    help="what the WRAPPER-class DECL sites (entity hart_tile, "
                         "entity orch_tile) must carry: a literal, or 'shipped' "
                         "(the default) to require the value of CORE_<G> in "
                         "%s, or 'same' to hold them to --require-default"
                         % SHIPPED_CONST_FILE)
    ap.add_argument("--require-min-decls", type=int, default=5,
                    help="fail if fewer than N DECL sites are found (default 5 -- "
                         "the ENABLE_TRAPCSR-measured declaration-site count: the "
                         "two entities plus the three component declarations). This "
                         "floor is PER GENERIC and must be the measured count for "
                         "the one under audit: ENABLE_IF_AHEAD has 4, being consumed "
                         "wholly inside vesta.vhd (see the header)")
    ap.add_argument("--require-min-consts", type=int, default=1,
                    help="fail if fewer than N generated CORE_<G> constants exist")
    ap.add_argument("--report-only", action="store_true",
                    help="print the census and always exit 0 (unless dead)")
    ap.add_argument("--control", default="ENABLE_TRAPCSR",
                    help="liveness-control generic (must be present)")
    ap.add_argument("--control-min", type=int, default=6,
                    help="minimum control sites for the scanner to be live")
    ap.add_argument("--skip-mgmt-hart", action="store_true",
                    help="skip the MGMT_HART axis (afe_stub ownership gate). It "
                         "runs by DEFAULT: it is the second half of this "
                         "checker's contract, not an option (see the header).")
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

    mgmt_rc = 0
    if not args.skip_mgmt_hart:
        mgmt_rc = audit_mgmt_hart(root, report_only=args.report_only)
        if mgmt_rc == 2:
            return 2

    if args.report_only:
        return 0

    consts = [r for r in rows if r[0] == "CONST"]
    absent = [r for r in rows if r[0] == "ABSENT"]

    rc = 0
    want = tile_want = None          # bound below; named here for the verdict
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

        # The wrapper requirement is MEASURED, not written down here: it is
        # whatever the generated constant says the chip ships.
        tile_want = (args.tile_default or "shipped").strip().lower()
        if tile_want == "same":
            tile_want = want
        elif tile_want == "shipped":
            shipped = [r for r in consts if r[1] == SHIPPED_CONST_FILE]
            if not shipped:
                print("FAIL: %s declares no CORE_%s, so the SHIPPED value of "
                      "%s cannot be measured and the wrapper defaults cannot "
                      "be graded against it.  Pass --tile-default explicitly "
                      "or restore the constant."
                      % (SHIPPED_CONST_FILE, args.generic, args.generic))
                rc = 1
                tile_want = None
            else:
                tile_want = (shipped[0][4] or "").strip().lower()
                print("   SHIPPED %s = %s (%s:%s).  The wrapper entities must "
                      "carry that value; the core class must carry %s."
                      % (args.generic, tile_want, shipped[0][1], shipped[0][2],
                         want))

        for _, rel, num, unit, val in decls:
            got = (val or "").strip().lower()
            if (rel, unit) in TILE_DECL_SITES:
                if tile_want is None or got == tile_want:
                    continue
                print("FAIL: %s:%s (%s) declares %s := %s, require %s -- this "
                      "is a WRAPPER entity, and a hardening run elaborates it "
                      "BARE while the generated MCU.vhd wires the same tile as "
                      "CORE_%s (%s).  A wrapper default that disagrees with the "
                      "shipped constant hardens the macro one way and wires it "
                      "the other, which is the M14 shape."
                      % (rel, num, unit, args.generic, val, tile_want,
                         args.generic, tile_want))
                rc = 1
            elif got != want:
                print("FAIL: %s:%s (%s) declares %s := %s, require %s -- this "
                      "is a CORE-class declaration, and an instantiation that "
                      "names no %s association INHERITS it.  Enabling the "
                      "feature must be a named act, never an inherited one."
                      % (rel, num, unit, args.generic, val, want, args.generic))
                rc = 1
    if missing:
        rc = 1
    if rc == 0 and want is not None:
        print("PASS: every CORE-class %s declaration carries %s, and every "
              "WRAPPER entity carries %s -- the value %s ships."
              % (args.generic, want, tile_want, SHIPPED_CONST_FILE))
    if mgmt_rc:
        rc = mgmt_rc
    return rc


if __name__ == "__main__":
    sys.exit(main())
