#!/usr/bin/python3.6
# -*- coding: utf-8 -*-
"""VestaRV <-> Spike lockstep comparator (phase V2, Agent A).

Normalises an RTL commit trace (`vesta_tracer.vhd`, the frozen wire format in
`tools/cosim/RECORD_FORMAT.md`) and a Spike `--log-commits` log into one flat
ordered record stream each, aligns them at the entry PC (kickoff decision D3),
and compares the COMPARED projection of every record in order.  On the first
divergence it prints both sides with N records of context, every `R` annotated
with a decoded mnemonic.

Exit codes are the contract with `xrun_cosim.sh`; they are documented in
`tools/cosim/README.md` and must not be changed without changing that file.

    0  match
    1  divergence (includes: entry PC never reached; a T record, which is a
       control-flow divergence in V2 -- and, with `--bracket-isr`, an ISR
       bracket whose trace-internally determined resume PC does not match the
       pc of the first post-`iret` retire)
    2  RTL stream exhausted early (Spike continues)
    3  Spike stream exhausted while RTL continues  -- NEVER success: a
       trapping instruction makes Spike print nothing and exit rc=0 silently
       (RECORD_FORMAT §4, v0_report §10.3)
    4  an Amendment-A5 x-corrupted record was reached -- INVESTIGATE
    5  parse or usage error (includes, since V4: `--stop-before-sleep` whose
       truncation point leaves ZERO compared records -- an operator-supplied
       flag combination that cannot produce a comparison, never a vacuous 0)

Stdlib only.  Python 3.6 syntax only.  Invoke as /usr/bin/python3.6 explicitly:
this host's `python3` may be Calibre's `aoj_cal` wrapper, which re-evals its
arguments and strips quotes (kickoff invariant 6).
"""

from __future__ import print_function

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import amend                                                    # noqa: E402
from disasm import disasm                                       # noqa: E402
from records import (ParseError, parse_rtl_trace, parse_rtl_diags,  # noqa: E402
                     keys_match_x)
from spike_log import parse_spike_log                           # noqa: E402

EXIT_MATCH = 0
EXIT_DIVERGE = 1
EXIT_RTL_SHORT = 2
EXIT_SPIKE_SHORT = 3
EXIT_XCORRUPT = 4
EXIT_USAGE = 5

# The v1 tracer's non-compared diagnostic tags (v1_report §8).  They are
# findings-surface: counted and summarised, never silently dropped.
FINDING_TAGS = (
    "CSRLEAK",        # A1 / findings F3, F7 -- CSR commit on a non-retire edge
    "SCFAILRD",       # A3 / finding F2      -- failed sc.w still reads at rs1
    "TRAPSTORE",      # finding F8           -- TRAP_STATE can store forever
    "ADDRMISMATCH",   # A3 suppression whose address equality failed
    "LANEMISMATCH",   # data_addr(1:0) vs the lowest active wen lane
    "INIT",           # R6 -- INITIALIZE actually executed
    "IRETPHANTOM",    # finding F9           -- every iret reads address 0
    "SLEEPEXIT",      # R5 -- a SLEEPING exit with no WFI dispatch
    "SCGHOST",        # A16 / finding T2     -- resv_unit suppressed an sc.w write
    "SCGHOSTX",       # A16                  -- the SC verdict itself was x
)
# `XBITS` (A10) is deliberately NOT here. It is METADATA, not a finding: it says
# which bits of an already-`x`-marked field were undriven. Naming it in the
# findings surface would read as a defect signal on every trace that carries any
# taint at all. It still surfaces, with its count, on the "other '#' comment
# tags" line -- visible without being alarming.

# Compared field names per record kind, RECORD_FORMAT §8.  `None` marks a field
# that exists on the wire but is debug-only (an `M L` size/data: Spike emits a
# load's address only, so the load's architectural effect is checked through
# the R record's rdval instead).
FIELD_NAMES = {
    "R": ("pc", "insn", "rd", "rdval"),
    "M": ("dir", "addr", "size", "data"),
    "C": ("csr", "val"),
}
COMPARED_FIELDS = {
    "R": (0, 1, 2, 3),
    "ML": (0, 1),
    "MS": (0, 1, 2, 3),
    "C": (0, 1),
}


# --------------------------------------------------------------------------
# presentation
# --------------------------------------------------------------------------

def annotate(rec):
    """One display line for a record: the wire form plus, for R, a mnemonic."""
    text = rec.wire()
    if rec.kind == "R":
        return "%-44s ; %s" % (text, disasm(rec.f[1]))
    return text


def emit_context(out, label, recs, idx, n):
    """Print up to `n` records either side of `recs[idx]`, marking it."""
    lo = max(0, idx - n)
    hi = min(len(recs), idx + n + 1)
    out.write("--- %s context (records %d..%d of %d) ---\n"
              % (label, lo, hi - 1, len(recs)))
    if hi == lo:
        out.write("    (stream empty)\n")
    for k in range(lo, hi):
        out.write("%s %6d %s\n" % (">>" if k == idx else "  ", k,
                                   annotate(recs[k])))


def mismatch_detail(a, b):
    """Human-readable list of which compared fields differ between a and b."""
    if a is None or b is None:
        return ["one side has no record here"]
    if a.kind != b.kind:
        return ["record KIND differs: rtl=%s spike=%s" % (a.kind, b.kind)]
    if a.kind == "M" and a.f[0] != b.f[0]:
        return ["memory DIRECTION differs: rtl=%s spike=%s"
                % (a.f[0], b.f[0])]
    if a.kind == "M":
        which = "ML" if a.f[0] == "L" else "MS"
    else:
        which = a.kind
    names = FIELD_NAMES[a.kind]
    out = []
    for i in COMPARED_FIELDS[which]:
        if a.f[i] != b.f[i]:
            out.append("%s: rtl=%s spike=%s" % (names[i], a.f[i], b.f[i]))
    return out or ["(no compared field differs -- comparator bug)"]


# --------------------------------------------------------------------------
# stream preparation
# --------------------------------------------------------------------------

def canonicalise_a2(recs):
    """Amendment A2: sort same-`pc` runs of consecutive R records by `rd`.

    A multi-`rd` retire (Zcmp `cm.pop*`/`cm.mv*`, knobs-on only) is n
    consecutive R records with identical pc/insn, one per committed register
    write.  Spike prints the same writes on one line in numeric-key order and
    the parser splits them the same way, but the two sides are not obliged to
    agree on order, so any run is canonicalised before comparison.

    A run of length 1 -- the overwhelmingly common case, and the only case in
    the default Castalia config since ENABLE_ZCMP/ZCMT are false -- is
    untouched.

    A same-pc run also forms when ONE instruction executes repeatedly, i.e. a
    self-loop such as `RVTEST_PASS`'s `c.j`, where both sides emit in execution
    order and reordering could in principle mask a real ordering divergence.
    The two cases are distinguished structurally: a multi-`rd` retire writes n
    DISTINCT registers, a repeated execution repeats the same `rd`.  So the sort
    is applied only when every `rd` in the run is distinct.  Returns a NEW list.
    """
    out = []
    i = 0
    n = len(recs)
    while i < n:
        r = recs[i]
        if r.kind != "R":
            out.append(r)
            i += 1
            continue
        j = i + 1
        while j < n and recs[j].kind == "R" and recs[j].f[0] == r.f[0]:
            j += 1
        run = recs[i:j]
        if len(run) > 1 and len(set(x.f[2] for x in run)) == len(run):
            run = sorted(run, key=lambda x: (x.f[2], x.f[1], x.f[3]))
        out.extend(run)
        i = j
    return out


def align_entry(recs, entry):
    """Index of the first R record whose pc == entry, or -1 (decision D3)."""
    for i, r in enumerate(recs):
        if r.kind == "R" and r.f[0] == entry:
            return i
    return -1


def compared_stream(recs):
    """Drop X records (never compared, §5); keep R/M/C and T.

    T is retained IN POSITION so the walk can report it as a control-flow
    divergence at the point it occurs (§4: Spike's commit log carries no trap
    information, and in the D3 window no trap is expected, so a T record is a
    signal).

    THE NON-BRACKET PATH.  `--bracket-isr` deliberately does NOT change this
    function: with the option off, behaviour must stay bit-identical to V2.
    """
    return [r for r in recs if r.is_compared() or r.kind == "T"]


# --------------------------------------------------------------------------
# Amendment A15 (V4): the spurious failed-SC `M … S` record
#   STATUS SINCE A16 (WT, finding T2): COMPATIBILITY SHIM + x-FALLBACK.
# --------------------------------------------------------------------------
#
# A16 fixed this AT SOURCE: `vesta_tracer.vhd` now samples `sc_fail_ext` in
# SC_CHECK and emits `# SCGHOST` instead of an `M … S` for a write resv_unit
# suppressed. On a post-A16 trace this pass therefore finds NOTHING TO DROP,
# and that is the intended end state -- `dropped=0` is the healthy reading.
#
# It is NOT dead code, for two distinct reasons, and only the first is the
# obvious one:
#   1. traces and comparators are versioned independently. An archived or
#      quarantined pre-A16 trace (there are 218 legacy artifacts in
#      cosim_work/legacy_v3_logs.quarantine/ alone) meeting a current
#      compare.py is a real combination, and it must still compare correctly.
#   2. A16 REFUSES to classify when `sc_fail_ext` is itself x: it emits
#      `# SCGHOSTX` and KEEPS the store, deliberately, because a wrongly
#      dropped real store is invisible while a kept ghost is not. A15 is the
#      thing that then catches it, from `rd` -- the effect -- when A16 could
#      not read the cause. The two are a division of labour, not duplicates.
# So: a NONZERO census on a trace whose header declares A16 means either an
# `# SCGHOSTX` occurred or the tracer's `sc_fail_ext` is unwired. Both are
# findings, and neither is silent -- the census below prints either way.
#
# A globally-failed `sc.w` STILL EMITS AN `M … S` RECORD on the RTL side. The
# core's LOCAL reservation check (`reservation_valid` + address match) passes, so
# it drives `wen`, and the tracer samples the core's PORT (invariant 7). The write
# is suppressed DOWNSTREAM by `resv_unit`'s `s_we_gated` (resv_unit.vhd:120-123)
# and only `sc_fail_ext` returns, so the retire reports `rd`=1 while a store
# record sits in the trace for a write that never committed.
#
# Independently proven by both V4 lineages, and settled by in-trace readback:
# `rv32ua-p-shlrsc` hart 0 line 216504-6 stores `000015b3` to `0001000c`, and two
# retires later `M … L 0001000c 4 0000115c` reads the OLD word back. Corroborated
# at the other site: the `0000dead` "store" to `00010044` is never observed by
# anyone, and hart 1 later writes `01c0ffee` there and reads back `01c0ffee`.
#
# That record VIOLATES §2's own contract ("M -- committed memory transaction"), so
# it is dropped from the COMPARED stream rather than being allowed to manufacture a
# divergence against a reference whose failed `sc.w` correctly writes nothing.
# The drop is BOUNDED and LOUD, never silent:
#   * only an `M … S` that IMMEDIATELY FOLLOWS a failed `sc.w` retire is eligible
#     (a retire owns at most one memory operation, so "immediately follows" is the
#     whole of the association);
#   * the decision comes from the SAME oracle mk_inject uses for `F` (`rd`), so the
#     two sides cannot disagree about which SCs failed;
#   * if `rd` is unusable -- A5 x-tainted, or written to x0 so no result exists --
#     NOTHING is dropped and the case is reported. Refuse, never guess;
#   * every application is counted per (pc, addr) identity and printed.
# THIS IS NOT A "SKIP FAILED SC" SWITCH. A failed SC's ADDRESS is still compared
# (via the reference's own store... which it does not make -- so what remains is
# the CONSISTENCY check below), and per Fable's A14 restatement the `rd` itself is
# ASSERTED, not compared. What A15 buys is that the store-presence CONSISTENCY
# becomes checkable at all: an `M … S` after an rd=0 (SUCCESS) SC is left in place
# and compared normally, and its ABSENCE there is still a divergence.

# sc.w: funct5=00011, funct3=010, opcode=0101111. aq/rl (bits 26:25) are outside
# the mask -- sc.w.aq/.rl are the same instruction. Same constant as mk_inject.py.
SC_W_MASK, SC_W_MATCH = 0xf800707f, 0x1800202f


def _is_sc_w(insn_hex):
    try:
        return (int(insn_hex, 16) & SC_W_MASK) == SC_W_MATCH
    except (ValueError, TypeError):
        return False          # an x-tainted insn is A5's business, not A15's


def drop_scfail_ghost_stores(recs):
    """A15: remove the `M … S` that a FAILED `sc.w` emitted but never committed.

    `recs` is an already-compared stream (R/M/C, X dropped). Returns
    (kept, info) where `info` carries the census the summary must print.
    """
    keep = [True] * len(recs)
    census = {}            # (pc, addr) -> count
    indet = []             # (lineno, pc, why) -- rd unusable, nothing dropped
    n_sc = n_fail = 0
    for i, r in enumerate(recs):
        if r.kind != "R" or not _is_sc_w(r.f[1]):
            continue
        n_sc += 1
        rd, rdval = r.f[2], r.f[3]
        nxt = recs[i + 1] if i + 1 < len(recs) else None
        has_store = (nxt is not None and nxt.kind == "M" and nxt.f[0] == "S")
        if "x" in rdval or rd == "00":
            # The oracle is unreadable. Drop nothing and say so: an x-tainted
            # record is already an A5 INVESTIGATE, and an sc.w into x0 discards
            # its own result on both sides.
            if has_store:
                indet.append((r.lineno, r.f[0],
                              "rd=%s rdval=%s is unusable as the SC oracle, so "
                              "the following store was NOT dropped" % (rd, rdval)))
            continue
        if rdval == "00000000":
            continue                      # SUCCESS: its store is real, compare it
        n_fail += 1
        if has_store:
            keep[i + 1] = False
            k = (r.f[0], nxt.f[1])
            census[k] = census.get(k, 0) + 1
    return ([r for r, k in zip(recs, keep) if k],
            {"sc": n_sc, "fail": n_fail, "dropped": sum(census.values()),
             "census": census, "indeterminate": indet})


# --------------------------------------------------------------------------
# sleep truncation (V4, --stop-before-sleep)
# --------------------------------------------------------------------------
#
# In the multi-hart phase a tile hart (1..N-1) boots the shared ROM, runs its
# handful of comparable retires and then executes `EXTINGUISH` -- a VestaRV
# CUSTOM instruction (`.insn r 0x0b,1,0`, encoding 0x0000100b) that the
# reference model cannot execute AT ALL.  The RTL was observed to emit
# `X <hart> <cycle> wfi_enter` immediately followed by the EXTINGUISH retire,
# so the comparison has to stop cleanly just before that pair.
#
# This is NOT a licence to skip the hard part: the cut point, the trigger that
# produced it, and the kept-record count are all printed in the summary, a
# stream with no trigger says so instead of pretending, and a cut that would
# leave nothing to compare is an error (EXIT_USAGE) rather than a match.

SLEEP_X_KIND = "wfi_enter"
EXTINGUISH_INSN = "0000100b"


def find_sleep_cut(recs):
    """Locate the `--stop-before-sleep` cut in an entry-aligned RTL window.

    `recs` must already be BOTH hart-filtered and entry-aligned (index 0 is the
    entry retire), so the answer composes with `--hart` and `--entry` by
    construction.  Nothing is removed here -- the caller slices.

    Returns a dict:
        wfi   window index of the first `X ... wfi_enter`, or None
        ext   window index of the first `R` whose insn is EXTINGUISH, or None
        cut   the earlier of the two in FILE ORDER, or None if neither exists
        why   "wfi_enter" / "EXTINGUISH" / None -- which trigger won
        rec   the trigger Rec (for the line/cycle report), or None
        wfi_rec / ext_rec   the two trigger Recs, for the adjacency warning
        adj   True/False if both exist (ext == wfi + 1), else None
        total number of records in the untruncated window
    """
    wfi = ext = None
    for i, r in enumerate(recs):
        if wfi is None and r.kind == "X" and r.f[0] == SLEEP_X_KIND:
            wfi = i
        if ext is None and r.kind == "R" and r.f[1] == EXTINGUISH_INSN:
            ext = i
        if wfi is not None and ext is not None:
            break
    got = {"wfi": wfi, "ext": ext, "total": len(recs),
           "wfi_rec": recs[wfi] if wfi is not None else None,
           "ext_rec": recs[ext] if ext is not None else None,
           "adj": None, "cut": None, "why": None, "rec": None,
           "kept": None, "dropped": 0}
    cands = [(i, why) for i, why in ((wfi, SLEEP_X_KIND), (ext, "EXTINGUISH"))
             if i is not None]
    if cands:
        cands.sort()
        got["cut"], got["why"] = cands[0]
        got["rec"] = recs[got["cut"]]
        got["dropped"] = len(recs) - got["cut"]
    if wfi is not None and ext is not None:
        got["adj"] = (ext == wfi + 1)
    return got


# --------------------------------------------------------------------------
# the ISR bracket (V3, --bracket-isr)
# --------------------------------------------------------------------------
#
# Spike/the reference CANNOT model VestaRV's legacy vectored trap (custom
# `iret`, IVT dispatch, hardware return-PC push), so the reference is never
# interrupted.  Instead the RTL's ISR window is BRACKETED OUT of the comparison
# and the reference is REALIGNED across it (`vesta_ref --bracket`, from
# `mk_inject.py --bracket-out`).  Per bracket, in this order:
#
#   1. the expected resume PC is determined TRACE-INTERNALLY -- if the ISR stored
#      to the very address the `# IRETPOP` diagnostic names (the stacked-PC
#      slot), the LAST such store is it (REDIRECTED); otherwise it is the `T`
#      record's `epc` (SEQUENTIAL);
#   2. that value is VERIFIED against the pc of the first post-`X iret` RTL
#      retire.  This is a COMPARED VERDICT: a mismatch is EXIT_DIVERGE.  It is
#      what keeps "`iret` reads the stacked PC back from RAM" a VERIFIED
#      property, and it is verified WITHOUT the reference's help -- exactly
#      because the reference cannot model the path;
#   3. only then is the reference realigned (elsewhere: vesta_ref).
#
# Nesting is a STACK, not a flag: a `T` inside a window does not close it.  The
# whole outermost window -- IVT jump retire, ISR retires, its memory and CSR
# records, any nested trap -- leaves the compared stream.
#
# --- Amendment A11 (V4): the SLEEP bracket ---------------------------------
#
# A window may ALSO open on `X <hart> <cycle> wfi_enter`, because VestaRV's park
# instruction is `EXTINGUISH` (0x0000100b), a custom opcode the reference cannot
# execute at all.  Every tile hart on every test enters that window, so without
# it the multi-hart phase cannot start.  Two shapes, both measured (A11), both
# handled here:
#
#   parked forever   `X wfi_enter` is the LAST record: no EXTINGUISH retire, no
#                    `T`, no `iret`.  The window NEVER CLOSES and that is
#                    CORRECT -- there is nothing after it to realign to, and
#                    `--stop-before-sleep` is the mechanism for such a stream.
#                    So it is NOT an error, it does NOT report UNTERMINATED, and
#                    it does not swallow whatever follows: a PARKED window's
#                    interior is handed BACK to the compared stream (see
#                    `bracket_partition`).
#   woken            `X wfi_enter`, the EXTINGUISH retire, `# IRQPUSH`, the
#                    legacy sentinel `T`, the ISR body, `# IRETPOP`, `X iret`.
#                    ONE window spanning all of it -- so the `T` must NOT
#                    double-open: the already-open SLEEP window ADOPTS it (and
#                    with it the epc/cause/ivt/push the landing check needs).
#                    The single `iret` closes the single window.
#
# The landing check is UNCHANGED for both kinds: the stacked-PC slot still
# decides REDIRECTED vs SEQUENTIAL, and a wrong landing is still EXIT_DIVERGE.
# (For the woken tile the loader ISR overwrites the stacked PC with the image
# ENTRY, so a woken sleep bracket is normally REDIRECTED.)

# IVT slot -> interrupt source, MemoryMap.vhd:1144-1145,1182 (NUM_IRQS=86).
BRACKET_SRC_NAMES = {83: "CLINT msip", 84: "CLINT mtip", 85: "meip"}

DASH = "--------"


def _or_dash(v):
    return DASH if v is None else v


class Bracket(object):
    """One RTL ISR window plus its verdict.

    Opened either by a `T` record (kind "TRAP", V3) or by an
    `X <hart> <cycle> wfi_enter` (kind "SLEEP", Amendment A11); closed by the
    matching `X ... iret` in both cases.
    """

    __slots__ = ("n", "index", "kind", "opener", "t", "x", "epc", "ivt",
                 "cause", "src", "adopted", "parked",
                 "pop_addr", "push", "stores", "loads", "csrs", "nested",
                 "nested_sleep", "x_other", "x_tainted", "rtl_start", "rtl_end",
                 "expected", "case", "landing", "landing_pc", "landing_via",
                 "checked", "n_skipped", "swallowed", "given_back")

    def __init__(self, n, index, opener, rtl_start, push, kind="TRAP"):
        self.n = n                  # bracket ordinal
        self.index = index          # compared records emitted before the opener
        self.kind = kind            # "TRAP" (a T) or "SLEEP" (an X wfi_enter)
        self.opener = opener        # the record that opened the window
        self.t = None
        self.x = None
        self.cause = self.epc = self.ivt = None
        self.src = None
        self.adopted = False        # A11: a T joined an already-open SLEEP window
        self.parked = False         # A11: a SLEEP window that never closes
        self.push = push            # the A7 # IRQPUSH Diag, or None
        self.pop_addr = None
        self.stores, self.loads, self.csrs = [], [], []
        self.nested = 0
        self.nested_sleep = 0       # nested `X wfi_enter` levels inside
        self.x_other = 0            # non-terminator X records inside the window
        self.x_tainted = 0          # A5-tainted records swallowed by the window
        self.rtl_start = rtl_start  # raw post-entry RTL retires before the opener
        self.rtl_end = None
        self.expected = None
        self.case = None
        self.landing = None         # the Rec whose pc must equal `expected`
        self.landing_pc = None
        self.landing_via = None     # "R" or "T-epc"
        self.checked = False
        self.n_skipped = 0          # RTL records removed from the comparison
        self.swallowed = []         # those records, in order (A11 PARKED giveback)
        self.given_back = 0         # A11 PARKED: records handed back to the walk
        if kind == "TRAP":
            self._set_trap(opener)

    def _set_trap(self, t):
        self.t = t
        self.cause, self.epc, self.ivt = t.f[0], t.f[1], t.f[2]
        try:
            self.src = (int(self.ivt, 16) - 0x8000) // 4
        except ValueError:
            self.src = None

    def adopt_trap(self, t, push):
        """A11 (woken): the legacy sentinel `T` inside a SLEEP window JOINS it.

        It does not open a window of its own -- that would double-open the one
        span A11 describes -- but it does supply the epc/cause/ivt/push that the
        landing check and the summary read, exactly as a TRAP bracket's own `T`
        does.
        """
        self._set_trap(t)
        self.adopted = True
        if self.push is None:
            self.push = push

    def kind_text(self):
        if self.kind != "SLEEP":
            return "TRAP"
        return "SLEEP+T" if self.adopted else "SLEEP"

    # -- step 1 ----------------------------------------------------------
    def resolve_expected(self):
        """The stacked-PC slot decides: an ISR store to it REDIRECTS the iret."""
        hits = [s for s in self.stores
                if self.pop_addr is not None and s.f[1] == self.pop_addr]
        if hits:
            self.expected = hits[-1].f[3]
            self.case = "REDIRECTED"
        elif self.epc is not None:
            self.expected = self.epc
            self.case = "SEQUENTIAL"
        else:
            # A closed SLEEP window with neither a stacked-PC store nor an
            # adopted `T`: there is no value the resume PC could be verified
            # against.  Named, not papered over -- the structural gate refuses
            # it below.
            self.expected = None
            self.case = "UNDETERMINED"

    @property
    def isr_retires(self):
        if self.rtl_end is None:
            return None
        return self.rtl_end - self.rtl_start

    @property
    def is_noop(self):
        """A SEQUENTIAL bracket where epc == expected == actual: the mechanism
        provably did nothing beyond what the RTL itself did.  A free built-in
        check, and it must be VISIBLE."""
        return (self.case == "SEQUENTIAL" and self.landing_pc is not None
                and self.epc == self.expected == self.landing_pc)

    def src_text(self):
        if self.src is None:
            return "?"
        name = BRACKET_SRC_NAMES.get(self.src)
        return "%d (%s)" % (self.src, name) if name else "%d" % self.src


class _DiagIndex(object):
    """A7 diagnostics by tag, searchable by the line range they must fall in.

    An `# IRQPUSH` / `# IRETPOP` is a COMMENT, so it has no position in the
    record stream: the only sound association is "the last one of this tag
    between the previous record's line and this record's line".
    """

    def __init__(self, diags):
        self.by_tag = {}
        for d in diags:
            self.by_tag.setdefault(d.tag, []).append(d)

    def last_between(self, tag, lo, hi):
        best = None
        for d in self.by_tag.get(tag, ()):
            if lo < d.lineno < hi:
                best = d
            elif d.lineno >= hi:
                break
        return best

    def count(self, tag):
        return len(self.by_tag.get(tag, ()))


def bracket_partition(recs, diags):
    """Split an entry-aligned RTL stream into (compared, brackets, notes).

    `compared` is the stream the walk consumes: R/M/C outside every ISR window,
    in order, with `X` records dropped and `T` records consumed as bracket
    openers.  Nothing inside a window survives -- and every removal is counted,
    so the summary can account for the whole input stream.

    Amendment A11: a window also opens on `X ... wfi_enter`.  Nesting is a STACK
    (`levels` below), never a flag: each level is either "T" (a trap level, or a
    sleep level that has ADOPTED its `T`) or "S" (a sleep level still able to
    adopt one), and every level is popped by one `X ... iret`.  A SLEEP window
    that reaches end-of-stream without adopting a `T` is PARKED: correct, not an
    error, and its interior goes BACK into `compared` rather than being
    swallowed.
    """
    dix = _DiagIndex(diags)
    out, brackets, notes = [], [], []
    awaiting = []          # brackets whose landing retire has not been seen yet
    levels = []            # the nesting STACK: "S" = sleep, open to adoption
    cur = None
    n_retire = 0           # raw post-entry R records (the RTL retire number)
    n_x_dropped = 0

    for i, r in enumerate(recs):
        k = r.kind
        prev_ln = recs[i - 1].lineno if i else 0
        if k == "R":
            n_retire += 1

        if not levels:
            if k == "X" and r.f[0] == SLEEP_X_KIND:
                # A11 OPEN: the park.  No `T`, no epc, no push yet -- a woken
                # hart supplies all three later, from inside the window.
                cur = Bracket(len(brackets), len(out), r, n_retire, None,
                              kind="SLEEP")
                cur.n_skipped = 1
                levels = ["S"]
                continue
            if k == "T":
                # A trap taken BEFORE the previous bracket's landing retire (a
                # level interrupt that was not cleared) still pins that
                # bracket's resume PC: an asynchronous trap's `epc` IS the pc
                # that would have executed next.
                for b in awaiting:
                    b.landing_pc = r.f[1]
                    b.landing_via = "T-epc"
                    notes.append("bracket %d: the landing retire never happened "
                                 "-- a further trap was taken first; its epc "
                                 "(%s) is the pc that would have executed"
                                 % (b.n, r.f[1]))
                awaiting = []
                push = dix.last_between("IRQPUSH", prev_ln, r.lineno)
                cur = Bracket(len(brackets), len(out), r, n_retire, push,
                              kind="TRAP")
                cur.n_skipped = 1
                levels = ["T"]
                continue
            if k == "X":
                # Outside a bracket an X is not a terminator: advance the RTL
                # index only -- never the reference index, never a compared
                # record.
                n_x_dropped += 1
                continue
            out.append(r)
            if k == "R" and awaiting:
                for b in awaiting:
                    b.landing = r
                    b.landing_pc = r.f[0]
                    b.landing_via = "R"
                awaiting = []
            continue

        # ---- inside a window -------------------------------------------
        cur.n_skipped += 1
        cur.swallowed.append(r)
        if r.has_x:
            cur.x_tainted += 1
        if k == "T":
            if levels[-1] == "S":
                # A11 (woken): the sentinel `T` joins the open SLEEP window
                # instead of double-opening.  The level becomes a "T" level, so
                # the ONE `iret` that follows closes the ONE window.
                levels[-1] = "T"
                cur.adopt_trap(r, dix.last_between("IRQPUSH", prev_ln,
                                                   r.lineno))
            else:
                levels.append("T")
                cur.nested += 1
        elif k == "X" and r.f[0] == SLEEP_X_KIND:
            # A nested park: its own level, so it needs its own `iret`.
            levels.append("S")
            cur.nested_sleep += 1
        elif k == "X" and r.f[0] == "iret":
            levels.pop()
            if not levels:
                cur.x = r
                cur.rtl_end = n_retire
                pop = dix.last_between("IRETPOP", prev_ln, r.lineno)
                cur.pop_addr = pop.addr if pop is not None else None
                cur.resolve_expected()
                brackets.append(cur)
                awaiting.append(cur)
                cur = None
        elif k == "X":
            cur.x_other += 1
        elif k == "M":
            (cur.stores if r.f[0] == "S" else cur.loads).append(r)
        elif k == "C":
            cur.csrs.append(r)

    if levels:
        # A11, C2 REFINEMENT. An unterminated SLEEP window has TWO readings, and
        # the discriminator is whether the window contains an EXTINGUISH retire
        # (`0x0000100b`) -- i.e. whether the reference could cross the park AT ALL:
        #
        #  (a) EXTINGUISH INSIDE  -> the park is VestaRV's custom opcode. The
        #      reference CANNOT execute it, so it necessarily stopped at the park
        #      and there is nothing after it to compare. The interior is swallowed
        #      and the verdict is taken on the PRE-PARK prefix -- exactly what
        #      `--stop-before-sleep` would give, reached through the bracket. This
        #      is CORRECT, not a divergence, in both of its sub-cases:
        #        * never woken: `X wfi_enter` is the last record;
        #        * WOKEN, sim ended inside the loader ISR -- the T1 shape. Measured
        #          on rv32ui-p-shmem_mp (launch margin 1,011 cycles against the
        #          ~32,768 the 4,096-word copy needs): all three tiles are still in
        #          the bootrom copy loop when hart 0's a0 stops the sim -- 229 RTL
        #          retires, 293 records inside the window, no `X iret`.
        #      The first implementation keyed this on `not cur.adopted`, so the
        #      woken-then-truncated case fell through to the UNTERMINATED arm and
        #      reported EXIT_DIVERGE on all three shmem_mp tiles for doing exactly
        #      what T1 says they do.
        #
        #  (b) NO EXTINGUISH -> the park was a REAL `wfi`, which Spike executes as
        #      an ordinary retire (§5), so the reference did NOT stop: it walked
        #      through the wfi and kept going. The tail is therefore genuinely
        #      comparable (give it back, unadopted case) and an unterminated
        #      ADOPTED window is a real loss of alignment (UNTERMINATED, exit 1).
        #      This is the pre-existing behaviour and its tests are unchanged.
        #
        # A TRAP window is untouched by all of this: unterminated there means the
        # sim was cut inside an ISR, which stays a divergence.
        ext_inside = any(s.kind == "R" and s.f[1] == EXTINGUISH_INSN
                         for s in cur.swallowed)
        if cur.kind == "SLEEP" and ext_inside:
            cur.parked = True
            n_x_dropped += 1          # the opening `X wfi_enter` itself
            cur.given_back = 0
            notes.append("bracket %d: SLEEP window never closes and contains the "
                         "EXTINGUISH retire, so the reference stopped at the park "
                         "by construction -- the verdict is taken on the "
                         "%d-record PRE-PARK prefix and %d record(s) after the "
                         "park are OUT of the comparison%s"
                         % (cur.n, len(out), cur.n_skipped,
                            " (the hart WAS woken and the sim ended inside its "
                            "ISR -- see rtl_findings.md T1)" if cur.adopted
                            else " (the hart was never woken)"))
            brackets.append(cur)      # reported, never silent
        elif cur.kind == "SLEEP" and not cur.adopted:
            # A11 PARKED via a real `wfi`: the reference executes it, so the
            # interior is GIVEN BACK to the compared stream rather than swallowed.
            cur.parked = True
            n_x_dropped += 1          # the opening `X wfi_enter` itself
            kept = []
            for s in cur.swallowed:
                if s.kind == "X":     # X is never compared (§5), as outside
                    n_x_dropped += 1
                else:
                    kept.append(s)
            out.extend(kept)
            for s in kept:            # a pending landing may live in the tail
                if s.kind == "R" and awaiting:
                    for b in awaiting:
                        b.landing = s
                        b.landing_pc = s.f[0]
                        b.landing_via = "R"
                    awaiting = []
                    break
            cur.given_back = len(kept)
            cur.n_skipped = 0
            cur.swallowed = []
            brackets.append(cur)      # reported, never silent
        else:
            notes.append("UNTERMINATED: the stream ends inside a %s bracket "
                         "(depth %d, opened at line %d) -- no matching "
                         "'X iret'"
                         % (cur.kind_text(), len(levels), cur.opener.lineno))
            brackets.append(cur)      # so it is reported, not lost
    return out, brackets, notes, n_x_dropped


def parse_window(text):
    """'0x4000:0x4000' -> (base, size)."""
    b, s = text.split(":")
    return int(b, 16), int(s, 16)


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

class _Parser(argparse.ArgumentParser):
    """argparse exits 2 on a usage error, which collides with EXIT_RTL_SHORT."""

    def error(self, message):
        sys.stderr.write("compare.py: usage error: %s\n" % message)
        sys.stderr.write("compare.py: run with --help for the CLI contract\n")
        sys.exit(EXIT_USAGE)


def build_parser():
    p = _Parser(
        prog="compare.py",
        description="VestaRV <-> Spike lockstep comparator (V2). "
                    "Exit: 0 match, 1 divergence, 2 RTL short, "
                    "3 Spike short, 4 x-corrupted record, 5 parse/usage.")
    p.add_argument("--rtl", required=True, metavar="TRACE",
                   help="RTL commit trace from vesta_tracer.vhd")
    p.add_argument("--spike", required=True, metavar="LOG",
                   help="Spike --log-commits log")
    p.add_argument("--entry", required=True, metavar="HEXPC",
                   help="entry PC to align both streams at, e.g. 0x8200")
    p.add_argument("--context", type=int, default=8, metavar="N",
                   help="records of context printed either side of a "
                        "divergence (default 8)")
    p.add_argument("--max-records", type=int, default=0, metavar="M",
                   help="stop after M successfully compared records and "
                        "report a match (0 = compare to the end of both "
                        "streams)")
    p.add_argument("--hart", default=None, metavar="HH",
                   help="2-hex-digit hart id to select from BOTH streams; "
                        "required only if a stream carries more than one hart "
                        "(per-hart streams are compared independently, §6)")
    p.add_argument("--count", action="store_true",
                   help="informational: print the number of compared records "
                        "in the entry-aligned RTL window and exit 0 without "
                        "comparing (feeds --max-records; see README)")
    p.add_argument("--stop-before-sleep", action="store_true",
                   help="V4 MULTI-HART: truncate the RTL-side compared stream "
                        "immediately before the earliest of (a) the first "
                        "'X <hart> <cycle> wfi_enter' and (b) the first R "
                        "retiring EXTINGUISH (insn %s), a VestaRV custom "
                        "instruction the reference cannot execute. Computed "
                        "AFTER --hart and --entry. The cut, its trigger and "
                        "the kept-record count are always printed; a stream "
                        "with neither trigger is a reported NO-OP; a cut that "
                        "would leave zero compared records is exit %d."
                        % (EXTINGUISH_INSN, EXIT_USAGE))
    p.add_argument("--x-allow", default=None, metavar="FILE",
                   help="Amendment A9: x-wildcard allowlist. One "
                        "'<pc> <addr>' pair per line (lowercase 8-hex, "
                        "#-comments ignored). For a record whose pc/addr is "
                        "named there, an 'x' nibble in an RTL field compares "
                        "as a WILDCARD; defined nibbles are still exact. "
                        "Every application is counted and printed. Records "
                        "NOT named keep the A5 exit-4 behaviour unchanged.")
    p.add_argument("--bracket-isr", action="store_true",
                   help="V3 ISR-BRACKET: instead of reporting a T record as a "
                        "control-flow divergence, bracket the RTL's ISR window "
                        "(T .. matching X iret) OUT of the comparison and "
                        "VERIFY the resume PC trace-internally against the "
                        "first post-iret retire. Amendment A11 (V4): a window "
                        "also opens on 'X <hart> <cycle> wfi_enter' (the park "
                        "the reference cannot execute); a woken hart's sentinel "
                        "T JOINS that window rather than opening a second one, "
                        "and a hart parked forever leaves a window that never "
                        "closes -- which is CORRECT, not an error. Off by "
                        "default, and with it off behaviour is unchanged.")
    p.add_argument("--no-a15", action="store_true",
                   help="Amendment A15 NEGATIVE CONTROL: do NOT drop the "
                        "never-committed 'M ... S' record that a FAILED sc.w "
                        "emits (the core drives wen on its local check; the "
                        "write is suppressed downstream in resv_unit). A15 is ON "
                        "by default because with it off every failed SC "
                        "manufactures a divergence against a reference that "
                        "correctly writes nothing -- which is exactly what this "
                        "flag is for proving.")
    p.add_argument("--bracket-mmio", default="0x4000:0x4000", metavar="BASE:SIZE",
                   help="unmodelled window, hex (default 0x4000:0x4000). Used "
                        "ONLY to classify an ISR window's stores as "
                        "replayed-into-reference-RAM vs excluded in the "
                        "--bracket-isr summary; it must match mk_inject.py's "
                        "--mmio.")
    p.add_argument("--amend", action="append", default=[], metavar="NAME[,..]",
                   help="K2b CONFIG-GATED comparator amendment(s). Repeatable "
                        "and comma-separable; an unknown name is a usage "
                        "error, never a silently-disabled amendment. Each one "
                        "reconciles a MEASURED record-shape difference between "
                        "a knobs-on VestaRV build and the reference, is "
                        "bounded by an equality rather than by a state, and is "
                        "counted and printed (including its zero form -- an "
                        "amendment that never fires on its own config is "
                        "VACUOUS). The enabled set is DERIVED from the "
                        "resolved chip config by tools/cosim/oracle_isa.py; "
                        "the default Castalia config enables none. "
                        "Implemented: " + ", ".join(amend.AMENDMENT_NAMES))
    p.add_argument("--quiet", action="store_true",
                   help="suppress the stderr summary (divergence output and "
                        "exit codes are unaffected)")
    return p


def norm_entry(text):
    t = text.strip().lower()
    if t.startswith("0x"):
        t = t[2:]
    if not t or any(c not in "0123456789abcdef" for c in t):
        raise ValueError("--entry %r is not hex" % text)
    return t.rjust(8, "0")


def load_x_allow(path):
    """Amendment A9 -> (set_of_idents, list_of_pairs).  A record is eligible
    for wildcard comparison if its `ident()` (an R's pc, an M's addr) appears
    in ANY entry.  The pairs are kept for the printed census."""
    idents, pairs = set(), []
    with open(path) as fh:
        for ln, raw in enumerate(fh, 1):
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            f = line.split()
            if len(f) != 2:
                raise ValueError("%s:%d: expected '<pc> <addr>', got %r"
                                 % (path, ln, line))
            pc, addr = f[0].lower(), f[1].lower()
            for t in (pc, addr):
                if len(t) != 8 or any(c not in "0123456789abcdef" for c in t):
                    raise ValueError("%s:%d: %r is not 8 lowercase hex digits"
                                     % (path, ln, t))
            pairs.append((pc, addr))
            idents.add(pc)
            idents.add(addr)
    return idents, pairs


def summarise_brackets(err, info):
    """The per-bracket summary block (V3 ISR-BRACKET).

    Everything the mechanism decided is printed: the window, the interrupt
    source, the case, the expected-vs-actual resume PC and its verdict, the
    store census with the MMIO exclusions named, and -- for a SEQUENTIAL bracket
    that landed on its own `epc` -- the explicit `no-op (epc==resume)`
    annotation.  That last one is a free built-in check: it says the bracket did
    nothing beyond what the RTL itself did, and it has to be VISIBLE for the
    reader to know when the mechanism is and is not carrying weight.
    """
    brs = info["brackets"]
    base, size = info["bracket_mmio"]
    err.write("  --- ISR brackets [--bracket-isr] ---\n")
    err.write("  %-22s %d bracket(s); %d RTL record(s) bracketed out, %d X "
              "record(s) skipped\n"
              % ("bracket census", len(brs), info["bracket_skipped"],
                 info["bracket_x_dropped"]))
    if not brs:
        err.write("      (no T record and no 'X wfi_enter' in the compared "
                  "window -- the mechanism was armed but never fired)\n")
    for b in brs:
        excl = [s.f[1] for s in b.stores if _in_window(s.f[1], base, size)]
        repl = len(b.stores) - len(excl)
        err.write("    bracket %d  kind=%-7s opened by %s\n"
                  % (b.n, b.kind_text(), annotate(b.opener)))
        err.write("    bracket %d  rtl retires %d..%s (%s in ISR)  epc=%s "
                  "cause=%s\n"
                  % (b.n, b.rtl_start,
                     "?" if b.rtl_end is None else b.rtl_end,
                     "?" if b.isr_retires is None else b.isr_retires,
                     _or_dash(b.epc), _or_dash(b.cause)))
        err.write("               ivt=%s src=%s  pop=%s  push=%s\n"
                  % (_or_dash(b.ivt), b.src_text(),
                     b.pop_addr if b.pop_addr else "NONE",
                     b.push.f[2] if b.push is not None else "NONE"))
        if b.parked:
            # Amendment A11, sub-case 1.  Not a diagnostic: a hart that parks
            # and is never woken has nothing after the park to realign to, so a
            # window that never closes is the CORRECT outcome.
            err.write("               case=PARKED       the hart never woke "
                      "(Amendment A11): no EXTINGUISH retire, no T, no iret.\n"
                      "                                 The window never "
                      "closes and that is CORRECT -- nothing follows it to "
                      "realign to.\n"
                      "                                 %d compared record(s) "
                      "after the park were LEFT IN the comparison, not "
                      "swallowed; use\n"
                      "                                 --stop-before-sleep to "
                      "truncate such a stream instead.\n" % b.given_back)
        elif b.expected is None:
            if b.x is None:
                err.write("               case=UNTERMINATED  no matching 'X "
                          "iret' -- resume PC undetermined\n")
            else:
                err.write("               case=UNDETERMINED  the window closed "
                          "but neither a stacked-PC store nor an adopted T "
                          "gives a resume PC\n")
        else:
            verdict = ("OK" if (b.landing_pc is not None
                                and b.landing_pc == b.expected)
                       else ("MISMATCH" if b.landing_pc is not None
                             else "NOT REACHED"))
            line = ("               case=%-11s expected=%s actual=%s  %s"
                    % (b.case, b.expected,
                       b.landing_pc if b.landing_pc else "--------", verdict))
            if b.is_noop and verdict == "OK":
                line += "  -- no-op (epc==resume)"
            if b.landing_via == "T-epc":
                line += "  [actual taken from the next trap's epc]"
            err.write(line + "\n")
        err.write("               isr_stores=%d replayed=%d excluded-mmio=%d%s "
                  " isr_loads=%d isr_csr=%d nested=%d nested_sleep=%d\n"
                  % (len(b.stores), repl, len(excl),
                     (" (" + " ".join(excl) + ")") if excl else "",
                     len(b.loads), len(b.csrs), b.nested, b.nested_sleep))
        if b.x_tainted:
            err.write("               WARNING %d Amendment-A5 x-tainted "
                      "record(s) were inside this window and left the "
                      "comparison with it\n" % b.x_tainted)
        if b.pop_addr is None and b.expected is not None:
            err.write("               WARNING no '# IRETPOP' diagnostic for "
                      "this bracket: the REDIRECTED case could not be detected "
                      "and the resume PC fell back to epc\n")
    for n in info["bracket_notes"]:
        err.write("    note: %s\n" % n)
    err.write("  %-22s the A7 return-PC push is replayed into reference RAM by "
              "mk_inject.py,\n                         not counted in "
              "`replayed` above\n" % "bracket replay")


def _in_window(addr_hex, base, size):
    try:
        a = int(addr_hex, 16)
    except ValueError:
        return False
    return base <= a < base + size


def summarise_sleep_cut(err, info):
    """The `--stop-before-sleep` block (V4).

    The comparator's whole ethos is that nothing is silently skipped, and a
    truncating option is the easiest place to break that: silence here would be
    indistinguishable from a comparator that was told to skip the hard part.
    So the trigger, its file line and cycle, the kept count and the dropped
    count are always printed -- and so is the case where nothing was cut.
    """
    sbs = info["sleep_cut"]
    err.write("  --- sleep truncation [--stop-before-sleep] ---\n")
    if sbs["cut"] is None:
        err.write("  %-22s NO-OP: the entry-aligned window (%d record(s)) "
                  "contains neither an\n"
                  "                         'X <hart> <cycle> %s' event nor a "
                  "retire of EXTINGUISH (insn %s).\n"
                  "                         A hart that never sleeps is "
                  "legitimate: the WHOLE window was compared.\n"
                  % ("sleep trigger", sbs["total"], SLEEP_X_KIND,
                     EXTINGUISH_INSN))
        return
    r = sbs["rec"]
    err.write("  %-22s the first %s\n" % ("sleep trigger", sbs["why"]))
    err.write("  %-22s %s\n" % ("trigger record", annotate(r)))
    err.write("  %-22s %s:%d  cycle %s  window index %d\n"
              % ("trigger position", info["rtl"], r.lineno, r.cycle,
                 sbs["cut"]))
    err.write("  %-22s %s compared record(s) kept; %d of the %d RTL record(s) "
              "in the entry-aligned\n                         window were "
              "dropped at and after the trigger\n"
              % ("truncation", sbs["kept"], sbs["dropped"], sbs["total"]))
    if sbs["adj"] is True:
        err.write("  %-22s wfi_enter immediately precedes the EXTINGUISH "
                  "retire, as observed\n" % "sleep-entry shape")
    elif sbs["adj"] is False:
        err.write("  WARNING [--stop-before-sleep]: THE SLEEP-ENTRY SEQUENCE "
                  "IS NOT THE OBSERVED SHAPE.\n")
        err.write("           'X %s' and the EXTINGUISH retire are BOTH "
                  "present but NOT ADJACENT:\n" % SLEEP_X_KIND)
        err.write("             %-10s window index %d, %s:%d  cycle %s\n"
                  % (SLEEP_X_KIND, sbs["wfi"], info["rtl"],
                     sbs["wfi_rec"].lineno, sbs["wfi_rec"].cycle))
        err.write("             %-10s window index %d, %s:%d  cycle %s\n"
                  % ("EXTINGUISH", sbs["ext"], info["rtl"],
                     sbs["ext_rec"].lineno, sbs["ext_rec"].cycle))
        err.write("           The RTL was observed to emit the wfi_enter "
                  "IMMEDIATELY before the EXTINGUISH retire; %d record(s)\n"
                  "           separate them here, so the sleep-entry sequence "
                  "differs and ANY downstream assumption about it\n"
                  "           (including which of the two this truncation "
                  "used) is unsafe -- INVESTIGATE.\n"
                  % (abs(sbs["ext"] - sbs["wfi"]) - 1))


def summarise_a15(err, info):
    """The Amendment-A15 block.  Printed whenever the pass ran, INCLUDING its
    no-op form: "0 dropped" is evidence that the stream had no failed SC, which
    is a different statement from the block being absent because A15 was off."""
    a = info["a15"]
    if a is None:
        err.write("  %-22s DISABLED by --no-a15 -- a failed sc.w's "
                  "never-committed store is left in the compared stream "
                  "(negative control)\n" % "A15 scfail ghost")
        return
    if not a["sc"]:
        return                    # no sc.w at all: silence is not a claim here
    err.write("  %-22s %d sc.w retire(s), %d failed (from rd, the A14 oracle), "
              "%d ghost store(s) dropped  [Amendment A15]\n"
              % ("A15 scfail ghost", a["sc"], a["fail"], a["dropped"]))
    for (pc, addr) in sorted(a["census"]):
        err.write("      pc %s -> addr %s  x%d\n"
                  % (pc, addr, a["census"][(pc, addr)]))
    if a["fail"] and not a["dropped"]:
        # WHY the reason is read off `# SCGHOST` and not assumed: pre-A16 there
        # was exactly one way for a failed sc.w to carry no store -- the core
        # declined the write LOCALLY -- so that sentence was safe. A16 created a
        # SECOND way, and printing the old reason on a post-A16 trace would
        # assert a local decline for every cross-hart kill in the run. The
        # tracer tells us which: `# SCGHOST` is emitted only on the external
        # path, `# SCFAILRD` only on the local one.
        n_ghost = info["comments"].get("SCGHOST", 0)
        if n_ghost:
            err.write("      note: nothing needed dropping because the TRACER "
                      "already withheld %d never-committed store(s) "
                      "[# SCGHOST, Amendment A16]. This is the healthy "
                      "post-A16 reading, not an absence of failed SCs\n"
                      % n_ghost)
        else:
            err.write("      note: every failed sc.w emitted NO store record -- "
                      "the core declined the write LOCALLY at each one, so "
                      "nothing needed dropping\n")
    for lineno, pc, why in a["indeterminate"]:
        err.write("      INDETERMINATE at %s:%d (pc %s): %s\n"
                  % (info["rtl"], lineno, pc, why))


def summarise(err, info):
    """The stderr summary.  Always printed unless --quiet."""
    err.write("--- compare.py summary ---\n")
    for k in ("rtl", "spike", "entry"):
        err.write("  %-22s %s\n" % (k, info[k]))
    err.write("  %-22s %d records (%d pre-entry skipped)\n"
              % ("rtl stream", info["rtl_total"], info["rtl_skipped"]))
    err.write("  %-22s %d records from %d commit lines (%d pre-entry "
              "skipped)\n" % ("spike stream", info["spike_total"],
                              info["spike_lines"], info["spike_skipped"]))
    err.write("  %-22s %d\n" % ("compared records", info["compared"]))
    if info["spike_fpr"]:
        err.write("  %-22s %d FPR write fields ignored (no F record in the "
                  "frozen format)\n" % ("spike f<n> fields", info["spike_fpr"]))
    if not info["rtl_header"]:
        err.write("  WARNING: the RTL trace has no '# vesta_tracer ...' "
                  "provenance header (v1_report §5).\n"
                  "           An OFF or stale snapshot produces no trace at "
                  "all; a header-less file is not a trusted trace.\n")
    xs = info["x_pre"] + info["x_post"]
    if xs:
        err.write("  %-22s %d total (%d pre-entry, %d in the compared "
                  "window)  [Amendment A5]\n"
                  % ("x-tainted records", xs, info["x_pre"], info["x_post"]))
    # Amendment A9: the allowlist is NEVER silent -- every application is
    # counted here, so a wildcard that starts firing more often than its
    # rationale predicts is visible in the run log.
    if info["x_allow_file"]:
        err.write("  %-22s %s (%d entry/-ies)  [Amendment A9]\n"
                  % ("x-wildcard allowlist", info["x_allow_file"],
                     len(info["x_allow_pairs"])))
        wild = info["x_wild"]
        if wild:
            tot = sum(wild.values())
            err.write("  %-22s %d application(s) across %d record ident(s):\n"
                      % ("x-wildcard applied", tot, len(wild)))
            for ident in sorted(wild):
                err.write("      %s  x%d\n" % (ident, wild[ident]))
        else:
            err.write("  %-22s none fired\n" % "x-wildcard applied")
    summarise_a15(err, info)
    if info.get("amend") is not None:
        amend.summarise(err, info["amend"])
    if info["bracket_isr"]:
        summarise_brackets(err, info)
    if info["sleep_cut"] is not None:
        summarise_sleep_cut(err, info)
    diags = info["comments"]
    named = [(t, diags[t]) for t in FINDING_TAGS if t in diags]
    other = sorted(t for t in diags
                   if t not in FINDING_TAGS and t != "vesta_tracer")
    if named:
        err.write("  RTL diagnostic comment lines (findings-surface, not "
                  "compared):\n")
        for tag, n in named:
            err.write("    # %-14s %d\n" % (tag, n))
    if other:
        err.write("  other '#' comment tags: %s\n"
                  % ", ".join("%s=%d" % (t, diags[t]) for t in other))
    err.write("  %-22s %d (%s)\n" % ("exit", info["exit"], info["verdict"]))


def main(argv):
    args = build_parser().parse_args(argv)
    out, err = sys.stdout, sys.stderr

    try:
        entry = norm_entry(args.entry)
    except ValueError as exc:
        err.write("compare.py: usage error: %s\n" % exc)
        return EXIT_USAGE
    if args.context < 0:
        err.write("compare.py: usage error: --context must be >= 0\n")
        return EXIT_USAGE
    if args.max_records < 0:
        err.write("compare.py: usage error: --max-records must be >= 0\n")
        return EXIT_USAGE
    try:
        bracket_mmio = parse_window(args.bracket_mmio)
    except Exception:
        err.write("compare.py: usage error: --bracket-mmio %r is not "
                  "<basehex>:<sizehex>\n" % args.bracket_mmio)
        return EXIT_USAGE
    try:
        am = amend.Amend(amend.parse_names(args.amend))
    except amend.AmendError as exc:
        err.write("compare.py: usage error: --amend: %s\n" % exc)
        return EXIT_USAGE
    hart = args.hart.lower() if args.hart else None
    if hart is not None and (len(hart) != 2 or
                             any(c not in "0123456789abcdef" for c in hart)):
        err.write("compare.py: usage error: --hart must be 2 hex digits\n")
        return EXIT_USAGE

    try:
        rtl_all, comments, header = parse_rtl_trace(args.rtl)
        # Amendment A7's two trap-path memory events are COMMENTS, so they are
        # not in `rtl_all`; the bracket mechanism needs the `# IRETPOP` address
        # to know which word is the stacked-PC slot.  Read only when armed.
        rtl_diags = parse_rtl_diags(args.rtl) if args.bracket_isr else []
    except ParseError as exc:
        err.write("compare.py: RTL trace parse error\n  %s\n" % exc)
        return EXIT_USAGE
    except (IOError, OSError) as exc:
        err.write("compare.py: cannot read --rtl: %s\n" % exc)
        return EXIT_USAGE
    try:
        spk_all, sstats = parse_spike_log(args.spike, hart)
    except ParseError as exc:
        err.write("compare.py: Spike log parse error\n  %s\n" % exc)
        return EXIT_USAGE
    except (IOError, OSError) as exc:
        err.write("compare.py: cannot read --spike: %s\n" % exc)
        return EXIT_USAGE

    if hart is not None:
        rtl_all = [r for r in rtl_all if r.hart == hart]
        # The A7 diagnostics are an INPUT to the bracket mechanism (they name
        # the stacked-PC slot), and `_DiagIndex.last_between` picks the LAST
        # matching tag in a line range -- so another hart's `# IRETPOP`
        # interleaved into the same file silently retargets THIS hart's
        # bracket.  `--hart` therefore has to filter the diagnostics exactly
        # as it filters the record stream.
        rtl_diags = [d for d in rtl_diags if d.hart == hart]
    else:
        rharts = set(r.hart for r in rtl_all)
        if len(rharts) > 1:
            err.write("compare.py: the RTL trace carries %d harts (%s); pass "
                      "--hart to select one\n"
                      % (len(rharts), ",".join(sorted(rharts))))
            return EXIT_USAGE
        if len(sstats["harts"]) > 1:
            err.write("compare.py: the Spike log carries %d harts (%s); pass "
                      "--hart to select one\n"
                      % (len(sstats["harts"]), ",".join(sorted(
                          sstats["harts"]))))
            return EXIT_USAGE

    info = {
        "rtl": args.rtl, "spike": args.spike, "entry": entry,
        "rtl_total": len(rtl_all), "spike_total": len(spk_all),
        "spike_lines": sstats["lines"], "spike_fpr": sstats["fpr"],
        "rtl_skipped": 0, "spike_skipped": 0, "compared": 0,
        "rtl_header": header, "comments": comments,
        "x_pre": 0, "x_post": 0, "exit": EXIT_USAGE, "verdict": "?",
        "x_allow_file": args.x_allow, "x_allow_pairs": [], "x_wild": {},
        "bracket_isr": args.bracket_isr, "bracket_mmio": bracket_mmio,
        "brackets": [], "bracket_notes": [], "bracket_skipped": 0,
        "bracket_x_dropped": 0,
        # V4: None when --stop-before-sleep is off, so the summary block --
        # including its NO-OP form -- appears if and only if the option is on.
        "sleep_cut": None,
        # V4/A15: None only when --no-a15 disabled the pass, so an absent block
        # means "deliberately off", never "there was nothing to say".
        "a15": None,
        # K2b: the config-gated amendment set (empty on the default config).
        "amend": am,
    }

    x_allow_idents = set()
    if args.x_allow:
        try:
            x_allow_idents, _pairs = load_x_allow(args.x_allow)
        except (IOError, ValueError) as e:
            err.write("compare.py: --x-allow: %s\n" % e)
            return EXIT_USAGE
        info["x_allow_pairs"] = _pairs

    def finish(code, verdict):
        info["exit"] = code
        info["verdict"] = verdict
        if not args.quiet:
            summarise(err, info)
        return code

    # --- entry alignment (D3) ------------------------------------------
    ri = align_entry(rtl_all, entry)
    if ri < 0:
        out.write("DIVERGENCE: the RTL stream never reaches the entry PC "
                  "%s.\n" % entry)
        out.write("  %d RTL records were read from %s.\n"
                  % (len(rtl_all), args.rtl))
        if rtl_all:
            first = next((r for r in rtl_all if r.kind == "R"), None)
            last = next((r for r in reversed(rtl_all) if r.kind == "R"), None)
            if first is not None:
                out.write("  first R pc=%s, last R pc=%s\n"
                          % (first.f[0], last.f[0]))
        out.write("  Check --entry against the ELF entry point, and that the "
                  "trace is the ON build's.\n")
        return finish(EXIT_DIVERGE, "entry PC never reached on the RTL side")
    info["rtl_skipped"] = ri
    info["x_pre"] = sum(1 for r in rtl_all[:ri] if r.has_x)

    si = align_entry(spk_all, entry)
    if si < 0:
        out.write("DIVERGENCE: the Spike stream never reaches the entry PC "
                  "%s.\n" % entry)
        out.write("  %d Spike records were read from %s.\n"
                  % (len(spk_all), args.spike))
        out.write("  The frozen recipe is `--disable-dtb --pc=<entry>`, which "
                  "starts the log AT the entry PC (v0_report §8).\n")
        return finish(EXIT_DIVERGE, "entry PC never reached on the Spike side")
    info["spike_skipped"] = si
    if si and not args.quiet:
        err.write("compare.py: note: skipped %d Spike records before the "
                  "entry PC.\n           With `--disable-dtb --pc=<entry>` "
                  "this should be 0; a DTB-on log has a 5-instruction "
                  "prologue at 0x1000 (RECORD_FORMAT §7).\n" % si)

    # --- sleep truncation (V4, --stop-before-sleep) ----------------------
    # Applied to the hart-filtered, ENTRY-ALIGNED window -- i.e. after both of
    # those -- and BEFORE the bracket/compared projection, so the count printed
    # in the summary is the count the walk actually consumes.  A trigger that
    # sits BEFORE the entry PC (a tile hart's ROM park, which every tile hart
    # has) is not in the compared window at all and is correctly invisible
    # here; a trigger AT the alignment point cuts the window to nothing and is
    # caught below.
    rtl_window = rtl_all[ri:]
    if args.stop_before_sleep:
        sleep_cut = find_sleep_cut(rtl_window)
        info["sleep_cut"] = sleep_cut
        if sleep_cut["cut"] is not None:
            rtl_window = rtl_window[:sleep_cut["cut"]]

    brackets = []
    if args.bracket_isr:
        rtl_cmp, brackets, bnotes, n_x = bracket_partition(rtl_window,
                                                           rtl_diags)
        info["brackets"] = brackets
        info["bracket_notes"] = bnotes
        info["bracket_skipped"] = sum(b.n_skipped for b in brackets)
        info["bracket_x_dropped"] = n_x
        rtl = canonicalise_a2(rtl_cmp)
    else:
        rtl = canonicalise_a2(compared_stream(rtl_window))
    # Amendment A15, applied to the RTL side ONLY and on BOTH paths above: the
    # reference's failed `sc.w` correctly writes nothing, so the RTL's
    # never-committed store record has no counterpart and would manufacture a
    # divergence at every failed SC (4 of 6 on shlrsc hart 0; ~29,000 on
    # shcount). Placed AFTER canonicalise_a2, which is safe in both directions:
    # A2 only reorders a run of CONSECUTIVE R records sharing one pc, so it can
    # never separate a retire from the M that follows it. After is chosen so the
    # census counts the stream exactly as it was compared.
    if not args.no_a15:
        rtl, a15 = drop_scfail_ghost_stores(rtl)
        info["a15"] = a15
    spk = canonicalise_a2(compared_stream(spk_all[si:]))
    # K2b: the config-gated amendments, applied LAST so that every census above
    # counts the stream as the earlier mechanisms saw it. The RTL side decides
    # from its own contents only; the ONE rule that consults the reference
    # (zfinx-fflags) only MARKS here and decides in the walk.
    if am.names:
        rtl = amend.rtl_prepass(rtl, am)
    info["amend"] = am
    info["x_post"] = sum(1 for r in rtl if r.has_x)

    if info["sleep_cut"] is not None:
        info["sleep_cut"]["kept"] = len(rtl)
        if info["sleep_cut"]["cut"] is not None and not rtl:
            r = info["sleep_cut"]["rec"]
            out.write("--stop-before-sleep WOULD LEAVE NOTHING TO COMPARE.\n")
            out.write("  The truncation trigger (the first %s) is at or before "
                      "the --entry alignment point %s:\n"
                      "    %s   (%s:%d, window index %d)\n"
                      % (info["sleep_cut"]["why"], entry, annotate(r),
                         args.rtl, r.lineno, info["sleep_cut"]["cut"]))
            out.write("  Zero compared records would remain, so a 'match' here "
                      "would be VACUOUS: it would assert nothing about the\n"
                      "  RTL at all.  This is a flag/trace mismatch, not a "
                      "verdict about the DUT -- pick an --entry inside the\n"
                      "  hart's comparable window, or drop "
                      "--stop-before-sleep.\n")
            return finish(EXIT_USAGE,
                          "--stop-before-sleep truncation at window index %d "
                          "(first %s) leaves 0 compared records"
                          % (info["sleep_cut"]["cut"],
                             info["sleep_cut"]["why"]))

    if args.count:
        out.write("%d\n" % len(rtl))
        return finish(EXIT_MATCH, "--count: %d compared RTL records in the "
                                  "entry-aligned window" % len(rtl))

    # --- ISR-bracket structural gate (before the walk) -------------------
    # These two shapes make a bracket UNVERIFIABLE, so they are refused rather
    # than passed over: the whole point of the mechanism is that the landing is
    # a compared verdict, and a bracket with no landing has no verdict.
    landing_map = {}
    for b in brackets:
        if b.parked:
            # Amendment A11 sub-case 1: a never-closing SLEEP window is CORRECT.
            # It has no resume PC to verify and nothing to realign to, so it is
            # reported in the summary and skipped here -- never a divergence.
            continue
        if b.x is None:
            out.write("BRACKET %d IS UNTERMINATED: the RTL stream ends inside "
                      "the %s window opened at %s.\n"
                      % (b.n, b.kind_text(), annotate(b.opener)))
            out.write("  A bracket must close on the 'X iret' matching its T "
                      "record (nesting is a stack).  With no close there is\n"
                      "  no resume PC to verify and no point at which to "
                      "realign the reference, so this is reported, never\n"
                      "  skipped.  Check the RTL sim was not cut short inside "
                      "an ISR.\n")
            return finish(EXIT_DIVERGE,
                          "unterminated ISR bracket %d (no matching X iret)"
                          % b.n)
        if b.expected is None:
            # A11: a SLEEP window that CLOSED on an `iret` but carries neither a
            # stacked-PC store nor an adopted `T`.  The measured woken shape has
            # both, so this is a shape nobody has seen -- refuse it loudly
            # rather than realign the reference onto a guess.
            out.write("BRACKET %d HAS NO DETERMINABLE RESUME PC: the %s window "
                      "opened at %s\n"
                      "  closed on %s, but no '# IRETPOP'-named store and no "
                      "trap `epc` say where it resumes.\n"
                      % (b.n, b.kind_text(), annotate(b.opener),
                         annotate(b.x)))
            out.write("  Amendment A11's woken shape carries the legacy "
                      "sentinel T (hence an epc) INSIDE the sleep window; this "
                      "stream\n"
                      "  does not, so the landing cannot be verified and the "
                      "reference cannot be realigned.  INVESTIGATE.\n")
            return finish(EXIT_DIVERGE,
                          "ISR bracket %d (%s) closed with no determinable "
                          "resume PC" % (b.n, b.kind_text()))
        if b.landing_pc is None:
            out.write("BRACKET %d HAS NO LANDING RETIRE: nothing retires after "
                      "%s.\n" % (b.n, annotate(b.x)))
            out.write("  The resume PC (%s, %s) can only be verified against "
                      "the first post-iret retire's pc.  Without one the\n"
                      "  'iret reads the stacked PC back from RAM' property is "
                      "UNPROVEN, so this is a divergence and not a pass.\n"
                      % (b.expected, b.case))
            return finish(EXIT_DIVERGE,
                          "ISR bracket %d has no post-iret retire to verify "
                          "the resume PC against" % b.n)
        if "x" in b.expected:
            out.write("BRACKET %d HAS AN X-TAINTED RESUME PC (%s) [Amendment "
                      "A5] -- INVESTIGATE.\n" % (b.n, b.expected))
            out.write("  case=%s; it came from %s.  The mechanism must never "
                      "realign the reference onto an invented pc.\n"
                      % (b.case,
                         "the ISR's store to the stacked-PC slot"
                         if b.case == "REDIRECTED" else "the T record's epc"))
            return finish(EXIT_XCORRUPT,
                          "x-tainted resume PC on ISR bracket %d" % b.n)
        if b.landing_via == "R":
            landing_map.setdefault(id(b.landing), []).append(b)
        else:
            # Resolved from a following trap's epc: both sides are already known,
            # so the verdict is settled here rather than in the walk.
            if b.landing_pc != b.expected:
                out.write("ISR BRACKET %d: RESUME PC MISMATCH.\n" % b.n)
                out.write("  expected resume (%s) : %s\n" % (b.case, b.expected))
                out.write("  actual              : %s (from the epc of the "
                          "trap taken before the landing retire)\n"
                          % b.landing_pc)
                if rtl:
                    emit_context(out, "RTL", rtl,
                                 min(b.index, len(rtl) - 1), args.context)
                return finish(EXIT_DIVERGE,
                              "ISR bracket %d resume PC mismatch (expected %s, "
                              "got %s)" % (b.n, b.expected, b.landing_pc))
            b.checked = True

    # --- the walk -------------------------------------------------------
    i = j = 0
    n = 0
    while True:
        info["compared"] = n
        if args.max_records and n >= args.max_records:
            return finish(EXIT_MATCH,
                          "match: %d records compared (--max-records bound "
                          "reached)" % n)
        rtl_done = i >= len(rtl)
        spk_done = j >= len(spk)
        # K2b amendment `zfinx-fflags`: a MARKED `C 001` is dropped only when
        # the reference does not present that exact record here (amend.py
        # explains why the value test alone is too wide). Checked before the
        # exhaustion reports so that a marked record at the very end of the RTL
        # stream is not reported as "Spike exhausted while RTL continues".
        if not rtl_done and amend.zfinx_should_skip(
                am, rtl[i], None if spk_done else spk[j]):
            i += 1
            continue
        if rtl_done and spk_done:
            return finish(EXIT_MATCH,
                          "match: %d records compared, both streams ended "
                          "together" % n)
        if rtl_done:
            out.write("RTL STREAM EXHAUSTED after %d matching records; the "
                      "Spike stream continues (%d records remain).\n"
                      % (n, len(spk) - j))
            out.write("  next Spike record: %s\n" % annotate(spk[j]))
            out.write("  This is EXPECTED when the RTL sim was terminated by "
                      "riscv_tb's a0 watch while Spike was still spinning in\n"
                      "  RVTEST_PASS: bound the comparison with "
                      "--max-records (see README, `--count`).  It is a REAL\n"
                      "  failure when the RTL hung or died early -- correlate "
                      "with the testbench verdict.\n")
            emit_context(out, "SPIKE", spk, j, args.context)
            return finish(EXIT_RTL_SHORT,
                          "RTL stream exhausted early after %d matching "
                          "records" % n)
        if spk_done:
            out.write("SPIKE STREAM EXHAUSTED after %d matching records; the "
                      "RTL stream continues (%d records remain).\n"
                      % (n, len(rtl) - i))
            out.write("  next RTL record: %s\n" % annotate(rtl[i]))
            out.write("  THIS IS NEVER SUCCESS.  Spike prints no line for a "
                      "trapping instruction and then terminates with rc=0 and\n"
                      "  no diagnostic (RECORD_FORMAT §4, v0_report §10.3), so "
                      "a truncated log is the normal shape of an\n"
                      "  illegal-instruction / unmapped-access divergence.  "
                      "Check the last Spike record below against the RTL\n"
                      "  record after it, and check --instructions was not the "
                      "bound.\n")
            emit_context(out, "RTL", rtl, i, args.context)
            emit_context(out, "SPIKE", spk, len(spk) - 1, args.context)
            return finish(EXIT_SPIKE_SHORT,
                          "Spike stream exhausted while RTL continues after "
                          "%d matching records" % n)

        a, b = rtl[i], spk[j]

        # --- ISR-bracket step 2: VERIFY THE LANDING (a compared verdict) ---
        # Done AT the first post-`X iret` retire, before that record is itself
        # compared, so the bracket's own claim is checked before anything that
        # depends on it.  Nothing else about the walk changes: the resume really
        # resumes, both streams keep advancing exactly as before.
        if landing_map:
            for bk in landing_map.get(id(a), ()):
                if bk.checked:
                    continue
                bk.checked = True
                if bk.landing_pc != bk.expected:
                    out.write("ISR BRACKET %d: RESUME PC MISMATCH after %d "
                              "matching records.\n" % (bk.n, n))
                    if bk.kind == "SLEEP":
                        out.write("  sleep entry         : %s  [Amendment "
                                  "A11]\n" % annotate(bk.opener))
                    if bk.t is not None:
                        out.write("  trap entry          : %s\n"
                                  % annotate(bk.t))
                    out.write("  iret                : %s\n" % annotate(bk.x))
                    out.write("  case                : %s\n" % bk.case)
                    out.write("  stacked-PC slot     : %s (from the A7 "
                              "'# IRETPOP' diagnostic)\n"
                              % (bk.pop_addr or "NONE"))
                    if bk.case == "REDIRECTED":
                        out.write("  expected resume     : %s -- the ISR's LAST "
                                  "store to the stacked-PC slot\n" % bk.expected)
                    else:
                        out.write("  expected resume     : %s -- the T record's "
                                  "epc (no ISR store hit the slot)\n"
                                  % bk.expected)
                    out.write("  actual resume       : %s -- pc of the first "
                              "retire after the iret\n" % bk.landing_pc)
                    out.write("  This is the check that keeps 'iret reads the "
                              "stacked PC back from RAM' VERIFIED, and it is\n"
                              "  verified TRACE-INTERNALLY -- the reference "
                              "cannot model the legacy vectored trap at all.\n"
                              "  A mismatch means the RTL resumed somewhere the "
                              "ISR's own stores do not justify.\n")
                    out.write("  ISR window: rtl retires %d..%s, %d store(s), "
                              "%d load(s), %d nested trap(s)\n"
                              % (bk.rtl_start, bk.rtl_end, len(bk.stores),
                                 len(bk.loads), bk.nested))
                    for s in bk.stores:
                        out.write("      isr store %s\n" % annotate(s))
                    emit_context(out, "RTL", rtl, i, args.context)
                    emit_context(out, "SPIKE", spk, j, args.context)
                    return finish(EXIT_DIVERGE,
                                  "ISR bracket %d resume PC mismatch (expected "
                                  "%s, got %s)"
                                  % (bk.n, bk.expected, bk.landing_pc))

        if a.kind == "T":
            out.write("CONTROL-FLOW DIVERGENCE: the RTL took a TRAP after %d "
                      "matching records.\n" % n)
            out.write("  rtl   : %s\n" % annotate(a))
            out.write("    cause=%s epc=%s tval=%s priv=%s\n" % tuple(a.f))
            out.write("  Spike's commit log carries NO trap information "
                      "(RECORD_FORMAT §4), and in the D3 window (single-hart,\n"
                      "  TCM-resident, entry-aligned) no trap is expected, so "
                      "a T record is itself the signal.  Giving T a\n"
                      "  comparable Spike side is V3 work.\n")
            out.write("  next Spike record: %s\n" % annotate(b))
            emit_context(out, "RTL", rtl, i, args.context)
            emit_context(out, "SPIKE", spk, j, args.context)
            return finish(EXIT_DIVERGE,
                          "RTL trap (T record) after %d matching records" % n)

        # Amendment A9 (ruling A2): a record whose pc/addr is on the
        # x-wildcard allowlist compares with `x` acting as a wildcard in the
        # RTL field -- defined nibbles still exact, width still exact. Anything
        # NOT on the list keeps A5's exit-4 behaviour untouched.
        if a.has_x and a.ident() in x_allow_idents:
            if keys_match_x(a.key(), b.key()):
                info["x_wild"][a.ident()] = info["x_wild"].get(a.ident(), 0) + 1
                i += 1; j += 1; n += 1
                continue
            out.write("DIVERGENCE at compared record #%d, on an X-WILDCARD "
                      "ALLOWLISTED record whose DEFINED nibbles still "
                      "disagree [Amendment A9].\n" % n)
            out.write("  rtl   : %s\n" % annotate(a))
            out.write("  spike : %s\n" % annotate(b))
            out.write("  The allowlist only makes the 'x' POSITIONS wildcards; "
                      "every defined nibble is compared exactly, so this is a\n"
                      "  real divergence and not an allowlist gap.\n")
            emit_context(out, "RTL", rtl, i, args.context)
            emit_context(out, "SPIKE", spk, j, args.context)
            return finish(EXIT_DIVERGE,
                          "defined-nibble divergence on an A9-allowlisted "
                          "record after %d matching records" % n)

        if a.has_x:
            out.write("X-CORRUPTED RECORD after %d matching records "
                      "[Amendment A5] -- INVESTIGATE.\n" % n)
            out.write("  rtl   : %s\n" % annotate(a))
            out.write("  An 'x' nibble means the tracer sampled a non-0/1 "
                      "std_logic at that position rather than inventing a\n"
                      "  value.  Such a record is NEVER a match and is never "
                      "silently skipped.  Known benign instances (X reads of\n"
                      "  undriven MMIO during boot) live OUTSIDE the D3 "
                      "window; one inside it is a real finding.\n")
            out.write("  aligned Spike record: %s\n" % annotate(b))
            emit_context(out, "RTL", rtl, i, args.context)
            emit_context(out, "SPIKE", spk, j, args.context)
            return finish(EXIT_XCORRUPT,
                          "x-corrupted RTL record after %d matching records"
                          % n)

        if a.key() != b.key():
            out.write("DIVERGENCE at compared record #%d "
                      "(rtl %s:%d, spike %s:%d).\n"
                      % (n, args.rtl, a.lineno, args.spike, b.lineno))
            out.write("  rtl   : %s\n" % annotate(a))
            out.write("  spike : %s\n" % annotate(b))
            for line in mismatch_detail(a, b):
                out.write("  differs: %s\n" % line)
            out.write("  (`cycle` is never compared; an `M L` compares on "
                      "`addr` only -- RECORD_FORMAT §8.)\n")
            emit_context(out, "RTL", rtl, i, args.context)
            emit_context(out, "SPIKE", spk, j, args.context)
            return finish(EXIT_DIVERGE,
                          "divergence at compared record #%d" % n)

        i += 1
        j += 1
        n += 1
        info["compared"] = n


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
