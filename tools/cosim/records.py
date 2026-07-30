#!/usr/bin/python3.6
# -*- coding: utf-8 -*-
"""The frozen lockstep wire format: record object + RTL-trace parser.

Phase V2 (Agent A).  Implements `tools/cosim/RECORD_FORMAT.md` (frozen
2026-07-29) including Amendments A1-A5.  Stdlib only, Python 3.6 syntax only.

    R <hart> <cycle> <pc> <insn> <rd> <rdval>
    M <hart> <cycle> <L|S> <addr> <size> <data>
    C <hart> <cycle> <csr> <val>
    T <hart> <cycle> <cause> <epc> <tval> <priv>
    X <hart> <cycle> <kind>

Field widths (RECORD_FORMAT §0): hart 2, cycle 8, pc/addr/epc/tval/rdval/val/
data 8, insn 4 **or** 8, rd 2, size 1, csr 3, cause 8, priv 1, kind a keyword.
All numeric fields are lowercase hex with no `0x` prefix.

Amendment A5: a literal `x` nibble in a hex field means the tracer sampled a
non-0/1 std_logic there.  Such a field is a legal *parse* (the record is
well-formed) but is never a match — that policy lives in compare.py.  This
parser therefore accepts `x` inside hex fields and sets `Rec.has_x`.
"""

from __future__ import print_function

HEXCHARS = set("0123456789abcdef")
HEXCHARS_X = set("0123456789abcdefx")


class ParseError(Exception):
    """A stream line that does not conform to RECORD_FORMAT §0.

    Raised rather than skipped: silently dropping a malformed record would let
    a broken tracer or a truncated file masquerade as a match.
    """

    def __init__(self, source, lineno, message, line=None):
        self.source = source
        self.lineno = lineno
        self.message = message
        self.line = line
        text = "%s:%d: %s" % (source, lineno, message)
        if line is not None:
            text += "\n    line: %r" % (line,)
        Exception.__init__(self, text)


def _hexfield(source, lineno, line, name, tok, widths, allow_x):
    """Validate one hex field; return it verbatim (already lowercase on the wire)."""
    chars = HEXCHARS_X if allow_x else HEXCHARS
    if len(tok) not in widths:
        raise ParseError(source, lineno, "field %s: width %d, expected %s"
                         % (name, len(tok),
                            "/".join(str(w) for w in sorted(widths))), line)
    for ch in tok:
        if ch not in chars:
            raise ParseError(source, lineno,
                             "field %s: %r is not lowercase hex%s"
                             % (name, tok, " (or 'x')" if allow_x else ""),
                             line)
    return tok


class Rec(object):
    """One wire-format event.

    `f` holds the record-specific fields as *strings*, in wire order:
        R : (pc, insn, rd, rdval)
        M : (dir, addr, size, data)      dir in {'L','S'}; size/data may be
                                         None on the Spike side of an `L`
                                         (Spike emits address only, §2)
        C : (csr, val)
        T : (cause, epc, tval, priv)
        X : (kind,)
    """

    __slots__ = ("kind", "hart", "cycle", "f", "lineno", "source", "has_x")

    def __init__(self, kind, hart, cycle, f, lineno=0, source="?", has_x=False):
        self.kind = kind
        self.hart = hart
        self.cycle = cycle
        self.f = f
        self.lineno = lineno
        self.source = source
        self.has_x = has_x

    # -- comparison ------------------------------------------------------
    def key(self):
        """The COMPARED projection, RECORD_FORMAT §8.

        `cycle` and `hart` are never part of it (hart selects the stream);
        an `M L` compares on `addr` only (Spike produces no size/data for a
        load); `T` and `X` have no compared projection at all in V2.
        """
        k = self.kind
        if k == "R":
            return ("R",) + tuple(self.f)
        if k == "M":
            if self.f[0] == "L":
                return ("M", "L", self.f[1])
            return ("M", "S", self.f[1], self.f[2], self.f[3])
        if k == "C":
            return ("C",) + tuple(self.f)
        return (k,)

    def is_compared(self):
        """T and X are RTL-side only and are never compared in V2 (§4/§5)."""
        return self.kind in ("R", "M", "C")

    def ident(self):
        """The A9 allowlist identity of this record: an `R` is named by its
        `pc`, an `M` by its `addr`, a `C` by its `csr`.  Used ONLY to look a
        record up in the x-wildcard allowlist -- never in a comparison."""
        if self.kind == "R":
            return self.f[0]
        if self.kind == "M":
            return self.f[1]
        if self.kind == "C":
            return self.f[0]
        return None

    # -- rendering -------------------------------------------------------
    def wire(self):
        """Render back to the wire format.

        Used for BOTH sides of the context dump so a human sees one shape.
        A field Spike cannot produce prints as `-` padded to its width, which
        is deliberately NOT valid wire syntax: it must be impossible to mistake
        comparator display output for a real trace line.
        """
        k = self.kind
        if k == "R":
            return "R %s %s %s %-8s %s %s" % (
                self.hart, self.cycle, self.f[0], self.f[1], self.f[2],
                self.f[3])
        if k == "M":
            size = self.f[2] if self.f[2] is not None else "-"
            data = self.f[3] if self.f[3] is not None else "--------"
            return "M %s %s %s %s %s %s" % (
                self.hart, self.cycle, self.f[0], self.f[1], size, data)
        if k == "C":
            return "C %s %s %s %s" % (self.hart, self.cycle, self.f[0],
                                      self.f[1])
        if k == "T":
            return "T %s %s %s %s %s %s" % (
                (self.hart, self.cycle) + tuple(self.f))
        return "X %s %s %s" % (self.hart, self.cycle, self.f[0])

    def __repr__(self):
        return "<Rec %s>" % self.wire()


def _mk(kind, source, lineno, line, toks, allow_x=True):
    """Build a Rec from a split wire line, validating every field width."""
    hart = _hexfield(source, lineno, line, "hart", toks[1], (2,), allow_x)
    cycle = _hexfield(source, lineno, line, "cycle", toks[2], (8,), allow_x)
    if kind == "R":
        if len(toks) != 7:
            raise ParseError(source, lineno,
                             "R needs 7 fields, got %d" % len(toks), line)
        pc = _hexfield(source, lineno, line, "pc", toks[3], (8,), allow_x)
        insn = _hexfield(source, lineno, line, "insn", toks[4], (4, 8), allow_x)
        rd = _hexfield(source, lineno, line, "rd", toks[5], (2,), allow_x)
        rdv = _hexfield(source, lineno, line, "rdval", toks[6], (8,), allow_x)
        f = (pc, insn, rd, rdv)
    elif kind == "M":
        if len(toks) != 7:
            raise ParseError(source, lineno,
                             "M needs 7 fields, got %d" % len(toks), line)
        if toks[3] not in ("L", "S"):
            raise ParseError(source, lineno,
                             "M direction must be L or S, got %r" % toks[3],
                             line)
        addr = _hexfield(source, lineno, line, "addr", toks[4], (8,), allow_x)
        size = _hexfield(source, lineno, line, "size", toks[5], (1,), allow_x)
        data = _hexfield(source, lineno, line, "data", toks[6], (8,), allow_x)
        f = (toks[3], addr, size, data)
    elif kind == "C":
        if len(toks) != 5:
            raise ParseError(source, lineno,
                             "C needs 5 fields, got %d" % len(toks), line)
        csr = _hexfield(source, lineno, line, "csr", toks[3], (3,), allow_x)
        val = _hexfield(source, lineno, line, "val", toks[4], (8,), allow_x)
        f = (csr, val)
    elif kind == "X":
        if len(toks) != 4:
            raise ParseError(source, lineno,
                             "X needs 4 fields, got %d" % len(toks), line)
        f = (toks[3],)
    else:
        raise ParseError(source, lineno, "unknown record kind %r" % kind, line)
    # Amendment A5 is about ANY hex field, so hart and cycle count too: an X on
    # hart_id or on the tracer's own counter means the trace is not trustworthy,
    # even though neither field is compared.
    has_x = any(t is not None and "x" in t for t in tuple(f) + (hart, cycle))
    return Rec(kind, hart, cycle, f, lineno, source, has_x)


def parse_rtl_line(line, source="rtl", lineno=0):
    """Parse one RTL trace line into a Rec, or None for a comment/blank line."""
    if not line or line[0] == "#":
        return None
    stripped = line.rstrip("\n").rstrip("\r")
    if stripped.strip() == "":
        return None
    if stripped != stripped.rstrip():
        raise ParseError(source, lineno, "trailing whitespace (§0)", stripped)
    toks = stripped.split(" ")
    if "" in toks:
        raise ParseError(source, lineno,
                         "records are single-space separated (§0)", stripped)
    kind = toks[0]
    if kind == "T":
        if len(toks) != 7:
            raise ParseError(source, lineno,
                             "T needs 7 fields, got %d" % len(toks), stripped)
        hart = _hexfield(source, lineno, stripped, "hart", toks[1], (2,), True)
        cycle = _hexfield(source, lineno, stripped, "cycle", toks[2], (8,), True)
        f = (
            _hexfield(source, lineno, stripped, "cause", toks[3], (8,), True),
            _hexfield(source, lineno, stripped, "epc", toks[4], (8,), True),
            _hexfield(source, lineno, stripped, "tval", toks[5], (8,), True),
            _hexfield(source, lineno, stripped, "priv", toks[6], (1,), True),
        )
        return Rec("T", hart, cycle, f, lineno, source,
                   any("x" in t for t in f + (hart, cycle)))
    if kind not in ("R", "M", "C", "X"):
        raise ParseError(source, lineno, "unknown record kind %r" % kind,
                         stripped)
    if len(toks) < 4:
        raise ParseError(source, lineno, "too few fields", stripped)
    return _mk(kind, source, lineno, stripped, toks)


def parse_rtl_trace(path):
    """Parse an RTL trace file.

    Returns `(records, comments, header_seen)` where

      * `records`  — list of Rec in file order (T/X included; the comparator
                     decides what to do with them).
      * `comments` — dict tag -> count over every `#` line, keyed by the token
                     after `#`.  `# CSRLEAK`/`# SCFAILRD`/`# TRAPSTORE`/
                     `# ADDRMISMATCH`/`# LANEMISMATCH`/`# INIT` (and the other
                     v1 diagnostics) are findings-surface, never silently
                     dropped: the comparator summarises this dict on stderr.
      * `header_seen` — True if the tracer provenance header line
                     (`# vesta_tracer TRACE_ENABLE=true ...`, v1_report §5) is
                     present.  Its absence means an OFF/stale snapshot ran.
    """
    recs = []
    comments = {}
    header = False
    with open(path, "r") as fh:
        for n, line in enumerate(fh, 1):
            if line.startswith("#"):
                toks = line.split()
                tag = toks[1] if len(toks) > 1 else "(empty)"
                comments[tag] = comments.get(tag, 0) + 1
                if tag == "vesta_tracer":
                    header = True
                continue
            r = parse_rtl_line(line, path, n)
            if r is not None:
                recs.append(r)
    return recs, comments, header


# --------------------------------------------------------------------------
# Amendment A7 diagnostics — the two trap-path memory events
# --------------------------------------------------------------------------

A7_TAGS = ("IRQPUSH", "IRETPOP", "IRQPUSHBAD", "IRETPOPBAD")

# token count AFTER the leading '#', i.e. len(line.split()) for a well-formed
# line: '#', tag, hart, cycle, then the tag's own fields.
_A7_WIDTHS = {
    "IRQPUSH":    6,   # tag <hart> <cycle> <addr> <size> <data>
    "IRETPOP":    4,   # tag <hart> <cycle> <addr>
    "IRQPUSHBAD": 7,   # tag <hart> <cycle> <addr> <sp_write_data> <size> <data> …
    "IRETPOPBAD": 5,   # tag <hart> <cycle> <addr> <stack_pointer>
}

# The two *BAD* diagnostics are failure-path only and carry trailing context that
# is deliberately free-form (the tracer appends `spwe '<std_logic>'` to
# IRQPUSHBAD, so it really emits 9). Their widths are therefore a MINIMUM, not an
# equality: a diagnostic must never be able to fail the parse of a trace whose
# compared stream is fine.
_A7_MIN_ONLY = ("IRQPUSHBAD", "IRETPOPBAD")


class Diag(object):
    """One `#`-comment diagnostic that carries fields (amendment A7).

    These lines are COMMENTS, so they have no position in the record stream —
    `lineno` is the only thing that ties a diagnostic to the records around it,
    and that is exactly how the comparator associates an `# IRETPOP` with the
    `X iret` it precedes.
    """

    __slots__ = ("tag", "lineno", "hart", "cycle", "f")

    def __init__(self, tag, lineno, hart, cycle, f):
        self.tag = tag
        self.lineno = lineno
        self.hart = hart
        self.cycle = cycle
        self.f = f          # tuple of the tag's own trailing fields, verbatim

    @property
    def addr(self):
        return self.f[0] if self.f else None

    def __repr__(self):
        return "<Diag %s:%d %s %s %s>" % (self.tag, self.lineno, self.hart,
                                          self.cycle, " ".join(self.f))


def parse_rtl_diags(path):
    """Parse the A7 trap-path diagnostics out of an RTL trace, in file order.

        # IRQPUSH <hart> <cycle> <addr> <size> <data>   legacy IRQ_SV push
        # IRETPOP <hart> <cycle> <addr>                 the `iret` stack pop
        # IRQPUSHBAD / IRETPOPBAD                       the A7 equality failures

    Everything else (including every other `#` tag) is ignored here —
    `parse_rtl_trace` already counts every comment tag for the findings
    surface.  A MALFORMED A7 line RAISES rather than being skipped: these
    diagnostics are load-bearing inputs to the ISR-bracket mechanism, so a
    tracer that emits a short one must not be able to degrade the bracket
    silently into its `SEQUENTIAL` default.
    """
    out = []
    with open(path, "r") as fh:
        for n, line in enumerate(fh, 1):
            if not line.startswith("#"):
                continue
            toks = line.split()
            if len(toks) < 2 or toks[1] not in A7_TAGS:
                continue
            tag = toks[1]
            # `toks` INCLUDES the leading '#', so the width to compare against is
            # len(toks) - 1 (the table counts tokens after the '#').
            want = _A7_WIDTHS[tag]
            got = len(toks) - 1
            if (got < want) if tag in _A7_MIN_ONLY else (got != want):
                raise ParseError(path, n, "# %s needs %s%d fields after '#', "
                                          "got %d"
                                 % (tag,
                                    ">=" if tag in _A7_MIN_ONLY else "",
                                    want, got),
                                 line.rstrip("\n"))
            out.append(Diag(tag, n, toks[2], toks[3], tuple(toks[4:])))
    return out


def field_matches_x(rtl_tok, spk_tok):
    """Amendment A9: compare one field with `x` nibbles in the RTL token acting
    as WILDCARDS.  Defined nibbles are still compared EXACTLY, and the widths
    must still match, so this is strictly weaker than equality only at the
    positions the RTL itself reported as undriven."""
    if rtl_tok == spk_tok:
        return True
    if rtl_tok is None or spk_tok is None:
        return False
    if len(rtl_tok) != len(spk_tok):
        return False
    for cr, cs in zip(rtl_tok, spk_tok):
        if cr == "x":
            continue
        if cr != cs:
            return False
    return True


def keys_match_x(ka, kb):
    """Tuple-wise `field_matches_x` (amendment A9)."""
    if len(ka) != len(kb):
        return False
    for ta, tb in zip(ka, kb):
        if not field_matches_x(ta, tb):
            return False
    return True
