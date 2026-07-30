#!/usr/bin/python3.6
# -*- coding: utf-8 -*-
"""Spike `--log-commits` parser: one commit line -> 1xR + nxM + nxC records.

Phase V2 (Agent A).  Implements `tools/cosim/RECORD_FORMAT.md` §1-§3 and §6
against the pinned Spike `3d8eb089bd289c59dcb506f197a172e02beb7b5b`
("Spike RISC-V ISA Simulator 1.1.1-dev", v0_report §5).  Stdlib only,
Python 3.6 syntax only.

Line grammar (`core%4d: %1d 0x<pc> (0x<insn>)` + trailing write fields):

    core   0: 3 0x00008200 (0xa011)
    core   0: 3 0x00008204 (0x4081) x1  0x00000000
    core   0: 3 0x00008264 (0x00110023) mem 0x00008690 0xaa
    core   0: 3 0x00008268 (0x00010703) x14 0xffffffaa mem 0x00008690
    core   0: 3 0x00008262 (0x00b6a72f) x14 0x80000000 mem 0x00008308 mem 0x00008308 0x7ffff800
    core   0: 3 0x0000827a (0xb0041a73) x20 0x00000029 c2816_mcycle 0x00000000

All six shapes above are VERBATIM from runs of that binary on this host
(rv32ui-p-add / -sb / -sw, rv32ua-p-amoadd_w, rv32ziscr-p-csr).

Load-bearing rules, each of them a documented trap:

* **Tokenize on whitespace RUNS, not columns** — Spike pads single-digit
  register numbers with two spaces (`x1  0x…`).
* **Classify every trailing field by its PREFIX, never by position** — the
  write map is keyed `(number << 4) | type`, so `c1_fflags` (key 20) prints
  BEFORE `x20` (key 320).  RECORD_FORMAT §3 "ORDERING TRAP".
* **` mem 0x<addr>` alone is a LOAD** (address only, no data, no size);
  ` mem 0x<addr> 0x<data>` is a STORE whose size is len(data)/2 bytes.  An AMO
  line carries both, and the load is emitted first.
* **Writes to x0 never appear** (Spike's map key for x0 is exactly 0 and is
  skipped), which is what makes `rd=00` unambiguously mean "no write".  An x0
  write would therefore be a *changed reference model* and is raised, not
  normalised away.
* **`cycle` on this side is the 0-based retire ordinal** (§0) — Spike's commit
  log has no cycle concept.  Never compared.

Not represented, by design: `f<n>` FPR writes (the frozen format has no F
record; Zfinx is off in the V2 config and Zfinx writes GPRs anyway) — they are
counted and reported, never silently dropped.  Trap information does not exist
in this log at all (§4): a trapping instruction prints NO line and the run can
end with `rc=0`, which is why "Spike exhausted while RTL continues" must never
be read as success.
"""

from __future__ import print_function

from records import ParseError, Rec


def _hexval(source, lineno, line, name, tok, width):
    """`0x<hex>` token -> lowercase hex string, zero-padded to `width`."""
    if not tok.startswith("0x") or len(tok) < 3:
        raise ParseError(source, lineno,
                         "%s: expected a 0x<hex> value, got %r" % (name, tok),
                         line)
    body = tok[2:].lower()
    for ch in body:
        if ch not in "0123456789abcdef":
            raise ParseError(source, lineno,
                             "%s: %r is not hex" % (name, tok), line)
    if len(body) > width:
        raise ParseError(source, lineno,
                         "%s: %r is wider than the %d-digit wire field"
                         % (name, tok, width), line)
    return body.rjust(width, "0")


def _is_gpr(tok):
    return len(tok) > 1 and tok[0] == "x" and tok[1:].isdigit()


def _is_fpr(tok):
    return len(tok) > 1 and tok[0] == "f" and tok[1:].isdigit()


def _csr_number(tok):
    """`c2816_mcycle` / `c2816` -> 2816, else None.  The `_<name>` suffix is
    Spike's disassembler name table and is discarded (§3)."""
    if len(tok) < 2 or tok[0] != "c":
        return None
    body = tok[1:]
    num = body.split("_", 1)[0]
    if not num.isdigit():
        return None
    return int(num)


def parse_spike_line(line, source="spike", lineno=0, ordinal=0):
    """Explode one commit line into the wire-format records it implies.

    Returns `(records, n_fpr)`.  Records are in the mandatory per-retire order
    (RECORD_FORMAT §0): all `R`, then every `M L`, then every `M S`, then
    every `C`.  Returns `([], 0)` for a blank line.
    Raises ParseError for anything that is not a commit line — deliberately
    strict, so a new Spike output shape is examined rather than swallowed.
    """
    stripped = line.rstrip("\n").rstrip("\r")
    if stripped.strip() == "":
        return [], 0
    toks = stripped.split()

    # --- header: core<pad>N: priv 0xPC (0xINSN) -------------------------
    if toks[0] == "core":
        hart_tok, i = (toks[1] if len(toks) > 1 else ""), 2
    elif toks[0].startswith("core"):
        hart_tok, i = toks[0][4:], 1          # hart >= 1000 loses the pad space
    else:
        raise ParseError(source, lineno,
                         "not a Spike commit line (expected 'core<n>: ...')",
                         stripped)
    if not hart_tok.endswith(":") or not hart_tok[:-1].isdigit():
        raise ParseError(source, lineno,
                         "malformed hart field %r" % hart_tok, stripped)
    hart = "%02x" % int(hart_tok[:-1])
    if len(toks) < i + 3:
        raise ParseError(source, lineno, "truncated commit line", stripped)
    priv = toks[i]
    if len(priv) != 1 or not priv.isdigit():
        raise ParseError(source, lineno,
                         "malformed privilege field %r" % priv, stripped)
    i += 1
    pc = _hexval(source, lineno, stripped, "pc", toks[i], 8)
    i += 1
    itok = toks[i]
    if not (itok.startswith("(0x") and itok.endswith(")")):
        raise ParseError(source, lineno,
                         "malformed instruction field %r" % itok, stripped)
    insn = itok[3:-1].lower()
    for ch in insn:
        if ch not in "0123456789abcdef":
            raise ParseError(source, lineno,
                             "instruction %r is not hex" % itok, stripped)
    if len(insn) not in (4, 8):
        # Spike prints at native width (insn.length()*8 bits), i.e. 4 or 8
        # hex digits on RV32.  Anything else means a changed reference model.
        raise ParseError(source, lineno,
                         "instruction width %d hex digits, expected 4 or 8"
                         % len(insn), stripped)
    i += 1

    # --- trailing write fields, classified by PREFIX --------------------
    gprs = []          # (rd_int, rdval_hex8)
    csrs = []          # (csr_int, val_hex8)
    loads = []         # addr_hex8
    stores = []        # (addr_hex8, size_int, data_hex8)
    n_fpr = 0
    cycle = "%08x" % ordinal
    while i < len(toks):
        tok = toks[i]
        if tok == "mem":
            if i + 1 >= len(toks):
                raise ParseError(source, lineno,
                                 "'mem' with no address", stripped)
            addr = _hexval(source, lineno, stripped, "mem addr", toks[i + 1], 8)
            i += 2
            # A data token (starts with 0x) makes it a store; no field-start
            # token can ever start with 0x, so this is unambiguous (§2).
            if i < len(toks) and toks[i].startswith("0x"):
                body = toks[i][2:].lower()
                for ch in body:
                    if ch not in "0123456789abcdef":
                        raise ParseError(source, lineno,
                                         "store data %r is not hex" % toks[i],
                                         stripped)
                if len(body) % 2 or not body:
                    raise ParseError(source, lineno,
                                     "store data %r: odd hex-digit count "
                                     "cannot encode a byte size" % toks[i],
                                     stripped)
                size = len(body) // 2
                if size > 8:
                    raise ParseError(source, lineno,
                                     "store size %d bytes exceeds the wire "
                                     "format" % size, stripped)
                if len(body) > 8:
                    raise ParseError(source, lineno,
                                     "store data %r wider than the 8-digit "
                                     "wire field" % toks[i], stripped)
                stores.append((addr, size, body.rjust(8, "0")))
                i += 1
            else:
                loads.append(addr)
            continue
        if _is_gpr(tok):
            if i + 1 >= len(toks):
                raise ParseError(source, lineno,
                                 "register field %r with no value" % tok,
                                 stripped)
            rd = int(tok[1:])
            if rd == 0:
                # RECORD_FORMAT §1: x0 writes are never logged by either side,
                # which is what makes rd=00 mean "no write".  If this fires the
                # reference model changed and the invariant must be re-derived.
                raise ParseError(source, lineno,
                                 "an x0 write appeared; RECORD_FORMAT §1 "
                                 "assumes Spike never logs one", stripped)
            if rd > 31:
                raise ParseError(source, lineno,
                                 "register index %d out of range" % rd,
                                 stripped)
            gprs.append((rd, _hexval(source, lineno, stripped, tok,
                                     toks[i + 1], 8)))
            i += 2
            continue
        if _is_fpr(tok):
            if i + 1 >= len(toks):
                raise ParseError(source, lineno,
                                 "FP register field %r with no value" % tok,
                                 stripped)
            n_fpr += 1
            i += 2
            continue
        num = _csr_number(tok)
        if num is not None:
            if i + 1 >= len(toks):
                raise ParseError(source, lineno,
                                 "CSR field %r with no value" % tok, stripped)
            if num > 0xfff:
                raise ParseError(source, lineno,
                                 "CSR address %d does not fit 12 bits" % num,
                                 stripped)
            csrs.append((num, _hexval(source, lineno, stripped, tok,
                                      toks[i + 1], 8)))
            i += 2
            continue
        raise ParseError(source, lineno,
                         "unrecognised trailing field %r (classification is "
                         "by prefix: mem / x<n> / f<n> / c<n>_<name>)" % tok,
                         stripped)

    # --- emit, in the mandatory order (§0) -----------------------------
    out = []
    if gprs:
        # Amendment A2: n consecutive R records with identical pc/insn, one per
        # committed register write.  Spike prints them on one line in numeric
        # key order (ascending rd for GPRs); the comparator canonicalises any
        # same-pc run by sorting on rd, so this order is not load-bearing.
        for rd, val in gprs:
            out.append(Rec("R", hart, cycle, (pc, insn, "%02x" % rd, val),
                           lineno, source))
    else:
        out.append(Rec("R", hart, cycle, (pc, insn, "00", "00000000"),
                       lineno, source))
    for addr in loads:
        # Spike emits address only for a load: size/data are None and are
        # never compared (§2/§8).  The load's architectural effect is checked
        # through the R record's rdval on the same retire.
        out.append(Rec("M", hart, cycle, ("L", addr, None, None), lineno,
                       source))
    for addr, size, data in stores:
        out.append(Rec("M", hart, cycle, ("S", addr, "%x" % size, data),
                       lineno, source))
    for num, val in csrs:
        out.append(Rec("C", hart, cycle, ("%03x" % num, val), lineno, source))
    return out, n_fpr


def parse_spike_log(path, hart=None):
    """Parse a whole Spike commit log.

    Returns `(records, stats)`.  `stats` is a dict with `lines` (commit lines
    consumed), `fpr` (FPR write fields ignored) and `harts` (set of hart ids
    seen).  When `hart` is given (2-hex-digit string) only that hart's records
    are returned — per-hart streams are compared independently (§6); V2 is
    single-hart so the filter is normally unnecessary.
    """
    recs = []
    stats = {"lines": 0, "fpr": 0, "harts": set()}
    with open(path, "r") as fh:
        ordinal = 0
        for n, line in enumerate(fh, 1):
            got, nf = parse_spike_line(line, path, n, ordinal)
            if not got:
                continue
            ordinal += 1
            stats["lines"] += 1
            stats["fpr"] += nf
            stats["harts"].add(got[0].hart)
            if hart is not None:
                got = [r for r in got if r.hart == hart]
            recs.extend(got)
    return recs, stats
