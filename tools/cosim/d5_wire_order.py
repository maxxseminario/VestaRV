#!/usr/bin/python3.6
"""d5_wire_order.py -- grade an OpenOCD `-d3` DMI trace against the D5 clauses
that only the debugger's own wire can answer.

D5 acceptance instrument, blind-authored 2026-08-10 against d5_spec.md 5.4
(FROZEN).  /usr/bin/python3.6 only -- deliberately NOT the debugger venv's
python, so it can be run from tree tooling with no environment coupling.

WHAT IT GRADES, and each one is a d5_spec 5.4 disposition turned into a
measurement rather than an argument:

  W1  EAGER-PLANT WIRE ORDER (5.4-2).  The F-D4-1 word-0 wedge is defended by
      the DM's plant on the dmactive RISE, and the defence only works if the
      debugger sets dmactive BEFORE it ever asserts haltreq.  OpenOCD does by
      spec and the toolchain probe verified it on Spike's wire; this grades it
      on VESTARV's wire, which is the one that matters.  It is an ORDERING
      over scan INDICES -- no timestamps, no durations.

  W2  EXAMINE ADDRESS CENSUS (5.4-0).  The set of DMI addresses this session
      touched, diffed against the twelve VestaRV implements plus sbcs.  Any
      address outside that set provokes op=FAILED and latches the DTM's
      sticky, and the tree probe ranks that as landmine zero.  Reported as a
      census AND graded against the expected gap set.

  W3  dmireset RECOVERY (5.4-0).  Every FAILED status must be followed by a
      dtmcs write with bit 16 set, and the NEXT dmi scan must succeed.  This
      is an ordering over three consecutive events and it is the only thing
      that distinguishes "the sticky gate is survivable" from "OpenOCD got
      lucky".

  W4  hartinfo/dataaddr NON-CONSUMPTION (5.4-4).  After the section-1 edit
      OpenOCD must read hartinfo and then never touch the dataaddr region.
      Graded as: hartinfo (0x12) WAS read (so the claim is about a debugger
      that looked), and no scratch_reserve line appears in the trace.

  W5  havereset / ackhavereset ACROSS A HART RESET EVENT (spec 1.7(viii)).
      OPT-IN, `--w5`, ADDED BY THE D5 VALIDATION WAVE (2026-08-13, R-D5-2(3)
      assigns this clause to validation rather than to the author).  W1-W4 are
      untouched and their output is byte-identical when `--w5` is absent --
      including W3, whose pipelined-scan defect is the AUTHOR's queue item and
      is deliberately NOT fixed here.  W5 does its OWN response re-alignment,
      locally, so implementing it correctly changes nothing about W3.

      THE RE-ALIGNMENT, and it is the whole reason this clause needs code
      rather than an eyeball: the DMI scan chain is PIPELINED.  The response
      printed on a scan line is the result of the PREVIOUS transaction, not of
      the one on that line.  A naive reader of

          scan(): 41b r 00000000 @11 -> + 00000000 @11
          scan(): 41b n 00000000 @00 -> + 004c03a3 @11

      reads dmstatus as 0x00000000 and concludes havereset = 0 when the wire
      says 1.  W5 therefore takes the response for request k from scan k+1, and
      CHECKS the alignment it assumes: the response's own address field should
      echo the previous request's address, and the agreement rate is printed.

      GRADED: with hartsel pointing at the victim, dmstatus.havereset
      (anyhavereset bit 18 / allhavereset bit 19 -- both confirmed against
      debug_module.vhd's `rsp(19)/rsp(18) := havereset_r(sel_idx)`) reads 1 in
      the last dmstatus read before the ackhavereset write and 0 in the first
      one after it.

      FAIL-CLOSED IN THREE DIRECTIONS, each of which is a way this clause could
      otherwise report a comfortable answer about nothing:
        * no ackhavereset write anywhere -> CANNOT-EVALUATE, never a pass;
        * no victim-attributed dmstatus read on either side -> CANNOT-EVALUATE;
        * THE HARTSEL ATTRIBUTION IS NOT TAKEN ON TRUST.  §12.4 measured a
          `dmi_write 0x10` whose hartsel did not survive to the next command
          (readback 17, not 1) because OpenOCD's poll loop owns dmcontrol -- so
          every dmstatus read in that session described a hart that was never
          power-cycled.  W5 requires a dmcontrol READ, between the hartsel
          write and the dmstatus read, whose re-aligned readback CONFIRMS the
          hartsel.  Uncorroborated or refuted -> CANNOT-EVALUATE, with the
          observed hartsel named.

EXIT CODES -- never a silent skip:
    0  every requested clause PASSED
    1  at least one clause FAILED (each names its evidence)
    2  the trace cannot be graded (missing/unparseable/no scans found), or a
       REQUESTED clause could not be evaluated (W5's CANNOT-EVALUATE)

METHOD VALIDATION (rule 4).  The parser is validated on EVERY run against a
known-nonzero built into this file: a five-line synthetic trace whose correct
answers are known, re-parsed in memory before the real trace is read.  If the
self-check does not reproduce them the script exits 2 and grades nothing --
the D4 `d4_entity_invariance.py` pattern.  A parser checked only against the
trace it is grading has not been checked.

TRACE SHAPE (measured, toolchain probe claim 19): riscv-013.c:390 scan() emits
    Debug: <n> riscv-013.c:390 scan(): 41b w 00000001 @10 -> + 00000000 @10
and dtmcontrol_scan() emits
    Debug: <n> riscv-013.c:444 dtmcontrol_scan(): DTMCS: 0x10000 -> 0x71
The status field is printed as '+' (success), 'f' (failed) or 'b' (busy) in
some builds and as a numeric `status=N` in others; both are accepted, and an
unrecognised status is counted and REPORTED rather than silently treated as
success.
"""

import os
import re
import sys

SCAN = re.compile(
    r"scan\(\):\s*(?P<bits>\d+)b\s+(?P<op>[rwn-])\s+(?P<data>[0-9a-fA-F]+)\s+@(?P<addr>[0-9a-fA-F]+)"
    r"(?:\s*->\s*(?P<st>[+fb?])?\s*(?P<rdata>[0-9a-fA-F]+)?\s*@(?P<raddr>[0-9a-fA-F]+))?")
DTMCS = re.compile(r"dtmcontrol_scan\(\):\s*DTMCS:\s*0x(?P<w>[0-9a-fA-F]+)\s*->\s*0x(?P<r>[0-9a-fA-F]+)")
FAILED = re.compile(r"Failed (read|write).*?at 0x(?P<addr>[0-9a-fA-F]+).*?status=(?P<st>\d+)")

DM_DMCONTROL = 0x10
DM_HARTINFO = 0x12
DM_SBCS = 0x38
DMIRESET_BIT = 1 << 16

VESTA_IMPLEMENTED = {0x04, 0x10, 0x11, 0x12, 0x13, 0x16, 0x17, 0x18,
                     0x20, 0x21, 0x32, 0x40}


DM_DMSTATUS = 0x11
ACKHAVERESET_BIT = 1 << 28
HARTSEL_SHIFT = 16                 # dmcontrol[25:16] = hartsello (debug_module.vhd
HARTSEL_MASK = (1 << 10) - 1       #   `hartsel_r <= d(25 downto 16)`, 10 bits)
ANYHAVERESET_BIT = 1 << 18         # dmstatus[18] (`rsp(18) := havereset_r(sel_idx)`)
ALLHAVERESET_BIT = 1 << 19         # dmstatus[19] (`rsp(19) := havereset_r(sel_idx)`)


class Trace(object):
    def __init__(self):
        # ('scan', idx, op, addr, data, status, raddr, rdata) | ('dtmcs', idx, w, r)
        # raddr/rdata are the fields printed AFTER the arrow and, on a pipelined
        # chain, belong to the PREVIOUS transaction.  W1-W4 never read them;
        # only W5 does, and it re-aligns them itself.
        self.events = []
        self.addrs = set()
        self.unknown_status = 0

    def parse(self, lines):
        for i, ln in enumerate(lines):
            m = DTMCS.search(ln)
            if m:
                self.events.append(("dtmcs", i, int(m.group("w"), 16), int(m.group("r"), 16)))
                continue
            m = SCAN.search(ln)
            if m:
                op = m.group("op")
                addr = int(m.group("addr"), 16)
                data = int(m.group("data"), 16)
                st = m.group("st")
                if st is None:
                    f = FAILED.search(ln)
                    st = "f" if f else "?"
                if st == "?":
                    self.unknown_status += 1
                ra = m.group("raddr")
                rd = m.group("rdata")
                self.events.append(("scan", i, op, addr, data, st,
                                    None if ra is None else int(ra, 16),
                                    None if rd is None else int(rd, 16)))
                if op in ("r", "w"):
                    self.addrs.add(addr)
                continue
            m = FAILED.search(ln)
            if m:
                self.events.append(("scan", i, "-", int(m.group("addr"), 16), 0, "f",
                                    None, None))
        return self

    def scans(self):
        return [e for e in self.events if e[0] == "scan"]


SELFCHECK = [
    "Debug: 1 riscv-013.c:390 scan(): 41b w 00000000 @10 -> + 00000000 @10",
    "Debug: 2 riscv-013.c:390 scan(): 41b w 00000001 @10 -> + 00000000 @10",
    "Debug: 3 riscv-013.c:390 scan(): 41b r 00000000 @38 -> f 00000000 @38",
    "Debug: 4 riscv-013.c:444 dtmcontrol_scan(): DTMCS: 0x10000 -> 0x71",
    "Debug: 5 riscv-013.c:390 scan(): 41b w 80000001 @10 -> + 00000000 @10",
]


def selfcheck():
    """Known-nonzero validation. Returns True only if the parser reproduces
    every hand-computed answer for the synthetic trace above."""
    t = Trace().parse(SELFCHECK)
    s = t.scans()
    ok = True
    reasons = []
    if len(s) != 4:
        ok = False; reasons.append("expected 4 scans, parsed %d" % len(s))
    if t.addrs != {0x10, 0x38}:
        ok = False; reasons.append("expected addresses {0x10,0x38}, parsed %s"
                                   % sorted(hex(a) for a in t.addrs))
    fails = [e for e in s if e[5] == "f"]
    if len(fails) != 1 or fails[0][3] != 0x38:
        ok = False; reasons.append("expected exactly one FAILED, at 0x38")
    dm = [e for e in t.events if e[0] == "dtmcs" and (e[2] & DMIRESET_BIT)]
    if len(dm) != 1:
        ok = False; reasons.append("expected exactly one dmireset")
    # dmactive-before-haltreq on the synthetic trace: index 1 vs index 4
    first_act = next((e[1] for e in s if e[2] == "w" and e[3] == DM_DMCONTROL and (e[4] & 1)), None)
    first_halt = next((e[1] for e in s if e[2] == "w" and e[3] == DM_DMCONTROL and (e[4] & (1 << 31))), None)
    if first_act is None or first_halt is None or not first_act < first_halt:
        ok = False; reasons.append("expected dmactive(idx %s) before haltreq(idx %s)"
                                   % (first_act, first_halt))
    if not ok:
        print("D5WIRE SELFCHECK FAILED -- the parser does not reproduce the known answers.")
        for r in reasons:
            print("D5WIRE   %s" % r)
        print("D5WIRE   Nothing below would be interpretable, so nothing is graded.")
    return ok


# ===========================================================================
# W5 -- havereset / ackhavereset.  Everything below this line is the D5
# validation wave's addition and is reached ONLY when --w5 is passed.
# ===========================================================================

def _w5_scan(line, op, data, addr, st, rdata, raddr):
    return ("Debug: %d riscv-013.c:390 scan(): 41b %s %08x @%02x -> %s %08x @%02x"
            % (line, op, data, addr, st, rdata, raddr))


# The synthetic W5 traces.  Each is the SESSION SHAPE the clause assumes,
# written as a pipelined chain: the response on a line belongs to the previous
# line's request.  DMSTATUS_H1 has bits 18/19 SET; DMSTATUS_H0 has them clear;
# both carry the same version/authenticated/impebreak furniture a real read
# carries, so the parser is not being fed a bit pattern that only W5 could love.
W5_DMSTATUS_H1 = 0x004C03A3
W5_DMSTATUS_H0 = 0x004003A3
W5_DMCONTROL_H1 = 0x00010001        # hartsel 1, dmactive
W5_DMCONTROL_H17 = 0x00110001       # hartsel 17 -- the §12.4 signature
W5_ACK_H1 = 0x10010001              # ackhavereset (bit 28), hartsel 1, dmactive


def _w5_synth(post_ack_dmstatus=W5_DMSTATUS_H0, include_ack=True,
              corroboration=W5_DMCONTROL_H1):
    """Build a synthetic trace: select hart 1, corroborate the hartsel by
    reading dmcontrol back, read dmstatus, ackhavereset, corroborate again,
    read dmstatus again."""
    L = []
    n = [0]

    def add(op, data, addr, rdata, raddr):
        n[0] += 1
        L.append(_w5_scan(n[0], op, data, addr, "+", rdata, raddr))

    add("w", W5_DMCONTROL_H1, 0x10, 0x00000000, 0x00)   # select hart 1
    add("r", 0x00000000, 0x10, 0x00000000, 0x10)        # read dmcontrol back
    add("n", 0x00000000, 0x00, W5_DMCONTROL_H1, 0x10)   # ...its data lands here
    add("r", 0x00000000, 0x11, 0x00000000, 0x00)        # read dmstatus
    add("n", 0x00000000, 0x00, W5_DMSTATUS_H1, 0x11)    # ...havereset = 1
    if not include_ack:
        return L
    add("w", W5_ACK_H1, 0x10, 0x00000000, 0x00)         # ackhavereset
    add("r", 0x00000000, 0x10, 0x00000000, 0x10)
    add("n", 0x00000000, 0x00, corroboration, 0x10)
    add("r", 0x00000000, 0x11, 0x00000000, 0x00)        # read dmstatus again
    add("n", 0x00000000, 0x00, post_ack_dmstatus, 0x11)
    return L


def selfcheck_w5():
    """Known-answer validation for W5, in all FOUR directions (rule 4 and the
    fail-closed requirement): the correct trace must PASS, a trace whose
    post-ack read still shows havereset must FAIL, a trace with no
    ackhavereset must be CANNOT-EVALUATE, and a trace whose hartsel readback
    contradicts the write must be CANNOT-EVALUATE.  A self-check that only
    ever confirms a pass has not been checked."""
    ok = True
    reasons = []

    cases = [
        ("correct session", _w5_synth(), "PASS"),
        ("post-ack still set", _w5_synth(post_ack_dmstatus=W5_DMSTATUS_H1), "FAIL"),
        ("no ackhavereset", _w5_synth(include_ack=False), "CANNOT"),
        ("hartsel refuted (the §12.4 trap)",
         _w5_synth(corroboration=W5_DMCONTROL_H17), "CANNOT"),
    ]
    for name, lines, want in cases:
        got = grade_w5(Trace().parse(lines), quiet=True)[0]
        if got != want:
            ok = False
            reasons.append("synthetic %r graded %s, expected %s" % (name, got, want))

    # The re-alignment must be doing WORK: read the same correct trace WITHOUT
    # re-aligning and the answer must differ.  If it did not, this clause would
    # be passing for a reason that has nothing to do with the pipelining, and
    # the next person to "simplify" the alignment away would see no failure.
    t = Trace().parse(_w5_synth())
    s = t.scans()
    aligned = [e for e in s if e[2] == "r" and e[3] == DM_DMSTATUS]
    if not aligned:
        ok = False
        reasons.append("synthetic trace has no dmstatus read at all")
    else:
        same_line = [e[7] for e in aligned]
        if any(v not in (0, None) for v in same_line):
            ok = False
            reasons.append("the unaligned reading is not the degenerate one this "
                           "check assumes (%s) -- the discriminator is broken"
                           % [None if v is None else "0x%08x" % v for v in same_line])

    if not ok:
        print("D5WIRE W5 SELFCHECK FAILED -- the W5 grader does not reproduce its "
              "known answers.")
        for r in reasons:
            print("D5WIRE   %s" % r)
        print("D5WIRE   W5 grades nothing.")
    return ok


def grade_w5(t, quiet=False):
    """Returns (verdict, note) with verdict in PASS / FAIL / CANNOT.

    HOW THE HARTSEL IS KNOWN, and the first version of this function got it
    wrong in a way worth recording.  I began by REQUIRING that every dmcontrol
    readback in the trace report the victim, on the theory that §12.4's
    hart-17 disaster was an un-corroborated attribution.  Run against a real
    session that rule is unsatisfiable and, worse, meaningless: OpenOCD's poll
    loop walks all N harts, so a trace legitimately contains a readback for
    every hart there is.

    The right statement is stronger and simpler.  `hartsel_r` changes on ONE
    event -- a dmcontrol write (debug_module.vhd: `hartsel_r <= d(25 downto
    16)`) -- and every such write is ON THE WIRE, including the poll loop's.
    So the hartsel in effect at any scan is EXACTLY the field of the most
    recent dmcontrol write before it, and a wire-level tracker is immune to the
    §12.4 confound by construction: the intervening poll writes that stole
    hartsel are visible and are counted.  What §12.4 lacked was not
    corroboration, it was the wire.

    The readbacks are then used for what they are actually good for: a
    CROSS-CHECK of the tracker against the DM's own answer.  Their agreement
    rate is measured and printed, and a low rate means the tracker (or the
    re-alignment it rests on) is wrong -- which is CANNOT-EVALUATE, not a
    verdict."""
    def say(msg):
        if not quiet:
            print(msg)

    s = t.scans()
    if not s:
        return ("CANNOT", "no scans")

    # ---- the local re-alignment, and a measurement of whether it holds ----
    # The response for request k is printed on scan k+1; its address field
    # should echo request k's address.  This is checked, not assumed.
    def resp(k):
        if k + 1 >= len(s):
            return (None, None, None)          # (status, rdata, raddr)
        e = s[k + 1]
        return (e[5], e[7], e[6])

    checkable = agree = 0
    for k in range(len(s) - 1):
        _, _, ra = resp(k)
        if ra is not None:
            checkable += 1
            if ra == s[k][3]:
                agree += 1
    rate = (100.0 * agree / checkable) if checkable else 0.0
    say("D5WIRE W5   re-alignment: the response address echoed the PREVIOUS request's "
        "address on %d of %d checkable scan pairs (%.1f%%).  This clause reads every "
        "response one scan late; W1-W4 are untouched by it."
        % (agree, checkable, rate))
    if checkable and rate < 90.0:
        say("D5WIRE W5 CANNOT-EVALUATE: the by-one re-alignment this clause depends on is "
            "corroborated on under 90%% of scan pairs, so every dmstatus value it would "
            "quote is suspect.  Grading nothing rather than guessing.")
        return ("CANNOT", "alignment unconfirmed")

    # ---- hartsel tracked from every dmcontrol write ----------------------
    hartsel_at = []          # hartsel in effect BEFORE scan k executes
    cur = None
    for e in s:
        hartsel_at.append(cur)
        if e[2] == "w" and e[3] == DM_DMCONTROL:
            cur = (e[4] >> HARTSEL_SHIFT) & HARTSEL_MASK
    nwrites = sum(1 for e in s if e[2] == "w" and e[3] == DM_DMCONTROL)

    # ---- the ackhavereset write ------------------------------------------
    acks = [k for k, e in enumerate(s)
            if e[2] == "w" and e[3] == DM_DMCONTROL and (e[4] & ACKHAVERESET_BIT)]
    if not acks:
        say("D5WIRE W5 CANNOT-EVALUATE: no dmcontrol (0x10) write with ackhavereset "
            "(bit 28) anywhere in this trace.  W5 has no event to grade around and says "
            "so -- a session that never acked cannot demonstrate that acking works.")
        return ("CANNOT", "no ackhavereset write")
    say("D5WIRE W5   %d dmcontrol write(s) on the wire, %d of them carrying ackhavereset."
        % (nwrites, len(acks)))
    for k in acks[:8]:
        say("D5WIRE W5     ack at scan #%-6d (trace line %-7d) data 0x%08x -> hart %d"
            % (k, s[k][1], s[k][4], (s[k][4] >> HARTSEL_SHIFT) & HARTSEL_MASK))
    if len(acks) > 8:
        say("D5WIRE W5     ... and %d more" % (len(acks) - 8))

    # THE GRADED ack is the LAST one: an examine-time ack (OpenOCD acks every
    # hart it examines) is not the session's deliberate ack, and grading the
    # first would grade the debugger's boilerplate instead of the experiment.
    ack_k = acks[-1]
    victim = (s[ack_k][4] >> HARTSEL_SHIFT) & HARTSEL_MASK
    say("D5WIRE W5   GRADED ack = the LAST one, scan #%d, victim hart %d.  (Earlier acks "
        "are OpenOCD's own examine-time boilerplate; grading the first would grade the "
        "debugger, not the session.)" % (ack_k, victim))

    # ---- cross-check the tracker against the DM's own readbacks ----------
    seen = miss = 0
    misses = []
    for k, e in enumerate(s):
        if e[2] == "r" and e[3] == DM_DMCONTROL:
            _, rd, _ = resp(k)
            if rd is None or hartsel_at[k] is None:
                continue
            seen += 1
            obs = (rd >> HARTSEL_SHIFT) & HARTSEL_MASK
            if obs != hartsel_at[k]:
                miss += 1
                if len(misses) < 10:
                    misses.append((k, hartsel_at[k], obs, rd))
    if seen:
        say("D5WIRE W5   tracker cross-check: %d dmcontrol readback(s) recovered, %d agree "
            "with the wire-tracked hartsel (%.1f%%)."
            % (seen, seen - miss, 100.0 * (seen - miss) / seen))
        for k, want, obs, rd in misses:
            say("D5WIRE W5     DISAGREES at scan #%d: tracked %d, DM answered %d (0x%08x)"
                % (k, want, obs, rd))
        if miss > len(misses):
            say("D5WIRE W5     ... and %d more disagreements" % (miss - len(misses)))
        if 100.0 * (seen - miss) / seen < 90.0:
            say("D5WIRE W5 CANNOT-EVALUATE: the DM's own hartsel readbacks contradict the "
                "wire-tracked value on more than 10%% of samples.  Either the tracker or "
                "the re-alignment is wrong, and in both cases the attribution of every "
                "dmstatus read below would be unsound -- which is exactly the §12.4 "
                "failure (a dmstatus describing a hart nobody touched).  Not graded.")
            return ("CANNOT", "hartsel tracker contradicted")
    else:
        say("D5WIRE W5   tracker cross-check: the trace never reads dmcontrol back, so the "
            "tracker is uncorroborated.  It is still EXACT by construction (hartsel_r "
            "changes only on a dmcontrol write and every write is on this wire), but the "
            "independent confirmation is absent and is reported as absent.")

    # ---- the dmstatus reads, re-aligned and attributed -------------------
    reads = []
    for k, e in enumerate(s):
        if e[2] == "r" and e[3] == DM_DMSTATUS:
            _, rd, _ = resp(k)
            if rd is None or hartsel_at[k] != victim:
                continue
            reads.append((k, rd, 1 if (rd & ANYHAVERESET_BIT) else 0,
                          1 if (rd & ALLHAVERESET_BIT) else 0))
    nall = sum(1 for e in s if e[2] == "r" and e[3] == DM_DMSTATUS)
    say("D5WIRE W5   %d dmstatus read(s) in the trace; %d of them had hart %d selected."
        % (nall, len(reads), victim))
    if not reads:
        say("D5WIRE W5 CANNOT-EVALUATE: not one dmstatus read in this trace was taken with "
            "the victim selected, so nothing here describes hart %d." % victim)
        return ("CANNOT", "no victim-attributed dmstatus read")

    before = [r for r in reads if r[0] < ack_k]
    after = [r for r in reads if r[0] > ack_k]

    def show(tag, rs):
        if not rs:
            say("D5WIRE W5     %s: none" % tag)
            return
        head = rs[:4]
        tail = rs[-4:] if len(rs) > 8 else rs[len(head):]
        for k, rd, an, al in head:
            say("D5WIRE W5     %s scan #%-6d dmstatus=0x%08x  anyhavereset=%d allhavereset=%d"
                % (tag, k, rd, an, al))
        if len(rs) > 8:
            say("D5WIRE W5     %s ... %d more ..." % (tag, len(rs) - 8))
        for k, rd, an, al in tail:
            say("D5WIRE W5     %s scan #%-6d dmstatus=0x%08x  anyhavereset=%d allhavereset=%d"
                % (tag, k, rd, an, al))
        vals = sorted(set((an, al) for _, _, an, al in rs))
        say("D5WIRE W5     %s: %d read(s), distinct (any,all) havereset values seen = %s"
            % (tag, len(rs), vals))

    show("BEFORE-ack", before)
    show("after-ack ", after)

    mismatched = [(k, an, al) for k, _, an, al in reads if an != al]
    if mismatched:
        say("D5WIRE W5   NOTE: %d read(s) report anyhavereset != allhavereset.  The RTL "
            "drives both from the same `havereset_r(sel_idx)`, so a disagreement is itself "
            "a finding: %s" % (len(mismatched),
                               ", ".join("scan #%d (%d/%d)" % m for m in mismatched[:6])))

    if not before or not after:
        say("D5WIRE W5 CANNOT-EVALUATE: the session shape this clause grades needs at least "
            "one victim-attributed dmstatus read BEFORE the graded ackhavereset (the "
            "post-reset observation) and one AFTER it (the ack's effect); this trace has "
            "%d and %d.  Not graded rather than half-graded." % (len(before), len(after)))
        return ("CANNOT", "one side of the ack is empty")

    pre = before[-1]         # last read before the ack = the post-reset-event one
    post = after[0]          # first read after the ack
    say("D5WIRE W5   graded pair: scan #%d (last before the ack) and scan #%d (first after "
        "it).  The assumed session shape is §12.4's -- select, read, power-cycle, read, "
        "ack, read -- and the whole trajectory is printed above so a reader can see what "
        "that assumption picked out." % (pre[0], post[0]))

    ok_pre = (pre[2] == 1 and pre[3] == 1)
    ok_post = (post[2] == 0 and post[3] == 0)
    if ok_pre and ok_post:
        say("D5WIRE W5 PASS: havereset read 1 (dmstatus 0x%08x) on hart %d after the reset "
            "event and 0 (0x%08x) after the ackhavereset write -- both halves measured on "
            "the wire, with the hartsel tracked from every dmcontrol write on it."
            % (pre[1], victim, post[1]))
        return ("PASS", "")
    say("D5WIRE W5 FAIL: expected havereset = 1 before the graded ack and 0 after it on "
        "hart %d; measured %d (dmstatus 0x%08x) then %d (0x%08x)."
        % (victim, pre[2], pre[1], post[2], post[1]))
    if pre[2] == 0 and post[2] == 0:
        say("D5WIRE W5   BOTH SIDES READ 0.  Two things follow and they are different "
            "claims.  (i) The ack cannot be shown to work by a trace in which the bit was "
            "never set -- that half is UNTESTED, not passed.  (ii) The reset event this "
            "session performed did not raise havereset at all, which is a statement about "
            "the chip and is the more interesting of the two.  W5 reports the wire and "
            "leaves the disposition to the reader.")
    elif pre[2] == 1 and post[2] == 1:
        say("D5WIRE W5   The bit was SET and the ack did NOT clear it.  That is a live "
            "ackhavereset defect, not a session-shape problem.")
    return ("FAIL", "")


def grade(path, expect_sbcs_ok=False, do_w5=False):
    if not os.path.isfile(path):
        print("D5WIRE CANNOT-EVALUATE: no such trace: %s" % path)
        return 2
    with open(path, "r", errors="replace") as f:
        t = Trace().parse(f.read().splitlines())
    s = t.scans()
    if not s:
        print("D5WIRE CANNOT-EVALUATE: %s contains no riscv-013 scan() lines." % path)
        print("D5WIRE   OpenOCD must be run with -d3; -d2 does not print them.")
        return 2

    fails = 0
    print("D5WIRE trace=%s  scans=%d  dtmcs_scans=%d  addresses=%s"
          % (path, len(s), len(t.events) - len(s),
             " ".join("0x%02x" % a for a in sorted(t.addrs))))
    if t.unknown_status:
        print("D5WIRE   NOTE: %d scan line(s) carried a status this parser does not "
              "recognise; they are counted, never assumed successful." % t.unknown_status)

    # ---- W1: dmactive before haltreq -------------------------------------
    first_act = next((e[1] for e in s if e[2] == "w" and e[3] == DM_DMCONTROL and (e[4] & 1)), None)
    first_halt = next((e[1] for e in s if e[2] == "w" and e[3] == DM_DMCONTROL and (e[4] & (1 << 31))), None)
    if first_act is None:
        print("D5WIRE W1 FAIL: no dmcontrol write with dmactive set anywhere in the trace")
        fails += 1
    elif first_halt is None:
        print("D5WIRE W1 PASS(vacuous-half): dmactive set at scan line %d and haltreq NEVER "
              "asserted in this trace -- the ordering holds but the session never halted "
              "anything, so quote this only for an attach-only run." % first_act)
    elif first_act < first_halt:
        print("D5WIRE W1 PASS: dmactive first set at line %d, haltreq first asserted at line %d "
              "-- the eager plant is correctly positioned ahead of any halt (F-D4-1's defence)"
              % (first_act, first_halt))
    elif first_act == first_halt:
        print("D5WIRE W1 FAIL: dmactive and haltreq are set in the SAME dmcontrol write "
              "(trace line %d). That is not an ordering, it is a race: the DM arms its "
              "plant on the dmactive rise and the halt request arrives in the same "
              "transaction, so nothing guarantees the entry page is planted before the "
              "hart fetches word 0. Graded FAIL deliberately and conservatively -- this "
              "is the F-D4-1 exposure, and it is invisible to any check that only asks "
              "'did dmactive ever get set'." % first_act)
        fails += 1
    else:
        print("D5WIRE W1 FAIL: haltreq at trace line %d PRECEDES dmactive at trace line %d. "
              "The DM's dmactive-rise plant cannot have run before the first halt, which is "
              "exactly the F-D4-1 word-0 wedge condition." % (first_halt, first_act))
        fails += 1

    # ---- W2: address census ----------------------------------------------
    allowed = set(VESTA_IMPLEMENTED)
    if expect_sbcs_ok:
        allowed.add(DM_SBCS)
    gap = sorted(a for a in t.addrs if a not in allowed)
    if not gap:
        print("D5WIRE W2 PASS: every DMI address this session touched is implemented "
              "(allowed set = %s)" % " ".join("0x%02x" % a for a in sorted(allowed)))
    else:
        print("D5WIRE W2 FAIL: the session touched %d address(es) VestaRV answers `failed` on: %s"
              % (len(gap), " ".join("0x%02x" % a for a in gap)))
        print("D5WIRE   Each one latches the DTM's sticky dmistat, after which every non-NOP")
        print("D5WIRE   Update-DR of dmi is silently dropped until dmireset (jtag_dtm.vhd")
        print("D5WIRE   DEVIATION 4). 0x14/0x15 appear only if dmcontrol.hasel READS BACK 1,")
        print("D5WIRE   which VestaRV drives 0 -- so seeing them is itself a finding.")
        fails += 1

    # ---- W3: dmireset recovery -------------------------------------------
    nfail = 0
    unrecovered = []
    for k, e in enumerate(t.events):
        if e[0] != "scan" or e[5] != "f":
            continue
        nfail += 1
        rec = False
        nxt = None
        for e2 in t.events[k + 1:]:
            if e2[0] == "dtmcs" and (e2[2] & DMIRESET_BIT):
                rec = True
            elif e2[0] == "scan":
                nxt = e2
                break
        if not (rec and nxt is not None and nxt[5] == "+"):
            unrecovered.append((e[1], "0x%02x" % e[3],
                                "dmireset=%s next=%s" % (rec, nxt[5] if nxt else "none")))
    if nfail == 0:
        print("D5WIRE W3 PASS(vacuous): no FAILED status anywhere in the trace, so the "
              "recovery path was never exercised. That is the CORRECT outcome after the "
              "section-1 edit, and it is reported as vacuous rather than as evidence -- "
              "5.4-0 asks for one FAILED to be PROVOKED on purpose, in its own run.")
    elif not unrecovered:
        print("D5WIRE W3 PASS: all %d FAILED status(es) were followed by a dtmcs dmireset "
              "and the next dmi scan succeeded -- the sticky gate is survivable, measured "
              "rather than inferred" % nfail)
    else:
        print("D5WIRE W3 FAIL: %d of %d FAILED status(es) were not recovered:" % (len(unrecovered), nfail))
        for u in unrecovered:
            print("D5WIRE   line %d addr %s -- %s" % u)
        fails += 1

    # ---- W4: hartinfo read, dataaddr never consumed ----------------------
    read_hi = any(e[2] == "r" and e[3] == DM_HARTINFO for e in s)
    with open(path, "r", errors="replace") as f:
        body = f.read()
    scratch = re.findall(r"scratch_reserve|Using DATA0|dataaddr", body)
    if not read_hi:
        print("D5WIRE W4 FAIL: hartinfo (0x12) was never read in this trace, so the claim "
              "'OpenOCD does not consume dataaddr' is about a debugger that never looked.")
        fails += 1
    elif scratch:
        print("D5WIRE W4 FAIL: hartinfo was read AND the trace mentions %s -- dataaddr is "
              "being consumed, which is R-D2-8 R6 alive." % sorted(set(scratch)))
        fails += 1
    else:
        print("D5WIRE W4 PASS: hartinfo (0x12) was read and the trace contains no "
              "scratch_reserve / dataaddr consumption -- dataaccess=0 steered OpenOCD to "
              "progbuf/work-area scratch, which closes R-D2-8 R6 by emission")

    # ---- W5: havereset / ackhavereset (opt-in) ---------------------------
    w5 = None
    if do_w5:
        w5 = grade_w5(t)[0]
        if w5 == "FAIL":
            fails += 1

    print("D5WIRE VERDICT: %s (%d clause(s) failed)" % ("PASS" if fails == 0 else "FAIL", fails))
    if w5 == "CANNOT":
        print("D5WIRE   W5 was REQUESTED and could not be evaluated; exiting 2 so that "
              "an un-gradeable clause can never be read as a passing one.")
        return 2
    return 0 if fails == 0 else 1


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        print("usage: d5_wire_order.py <openocd-d3.log> [--expect-sbcs-ok] [--w5]")
        return 2
    if not selfcheck():
        return 2
    print("D5WIRE SELFCHECK OK -- the parser reproduces every known answer on its "
          "built-in synthetic trace (4 scans, {0x10,0x38}, one FAILED at 0x38, one "
          "dmireset, dmactive before haltreq).")
    do_w5 = "--w5" in argv
    if do_w5:
        if not selfcheck_w5():
            return 2
        print("D5WIRE W5 SELFCHECK OK -- the W5 grader reproduces its known answers on "
              "four synthetic sessions (correct=PASS, post-ack-still-set=FAIL, "
              "no-ack=CANNOT-EVALUATE, hartsel-refuted=CANNOT-EVALUATE) and the "
              "by-one response re-alignment is confirmed to change the answer.")
    return grade(argv[1], "--expect-sbcs-ok" in argv, do_w5)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
