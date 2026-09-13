#!/usr/bin/python3.6
"""VestaRV: grade an OpenOCD -d3 DMI trace against the clauses only the debugger's wire answers.

Clauses W1 eager-plant ordering, W2 examine address census, W3 dmireset recovery, W4
hartinfo/dataaddr non-consumption, W5 havereset/ackhavereset (opt-in, --w5). The DMI scan
chain is pipelined: the response on a scan line belongs to the previous request, so W5
re-aligns by one and checks the alignment. Exit 0 pass, 1 fail, 2 ungradable. python3.6 only.
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


# W5 -- havereset / ackhavereset.  Everything below this line is the D5
# validation wave's addition and is reached ONLY when --w5 is passed.

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
    """Known-answer validation for W5 in all four directions: the correct trace must pass, one whose
    post-ack read still shows havereset must fail, and one with no ackhavereset or a contradicted
    hartsel readback must be CANNOT-EVALUATE. A self-check that only confirms a pass is no check.
    """
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
    """Returns (verdict, note) with verdict PASS, FAIL or CANNOT. hartsel_r changes only on a
    dmcontrol write and every such write is on the wire, so the hartsel at any scan is the field
    of the most recent one before it; the readbacks cross-check that tracker against the DM.
    """
    def say(msg):
        if not quiet:
            print(msg)

    s = t.scans()
    if not s:
        return ("CANNOT", "no scans")

    # the local re-alignment, and a measurement of whether it holds
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

    # hartsel tracked from every dmcontrol write
    hartsel_at = []          # hartsel in effect BEFORE scan k executes
    cur = None
    for e in s:
        hartsel_at.append(cur)
        if e[2] == "w" and e[3] == DM_DMCONTROL:
            cur = (e[4] >> HARTSEL_SHIFT) & HARTSEL_MASK
    nwrites = sum(1 for e in s if e[2] == "w" and e[3] == DM_DMCONTROL)

    # the ackhavereset write
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

    # cross-check the tracker against the DM's own readbacks
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

    # the dmstatus reads, re-aligned and attributed
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

    # W1: dmactive before haltreq
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

    # W2: address census
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

    # W3: dmireset recovery
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

    # W4: hartinfo read, dataaddr never consumed
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

    # W5: havereset / ackhavereset (opt-in)
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
