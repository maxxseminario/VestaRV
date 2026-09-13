#!/usr/bin/python3.6
# coding: utf-8
"""VestaRV: the config-gated lockstep comparator amendments.

Each rule reconciles one architectural event the RTL tracer and the reference model record
differently; none changes what an instruction may do. The enabled set comes from
oracle_isa.derive_amendments() on the resolved config, never global, and every application is
counted and printed, zero included. Python 3.6 syntax, stdlib only.
"""

from __future__ import print_function

from records import Rec


class AmendError(Exception):
    """An amendment name the comparator does not implement."""


# name -> (config predicate as text, one-line description).  ORDER IS THE
# CANONICAL ORDER: it is what `oracle_isa --shell` emits and what the summary
# prints, so two runs of one config produce the same line.
AMENDMENTS = (
    ("zfinx-fflags", "isa.zfinx",
     "drop the RTL's unconditional FPU_DONE `C 001` when it asserts no change "
     "and the reference does not present it"),
    ("cboz-stores", "isa.zicboz",
     "drop the 16 `M S` records of a `cbo.zero` retire, count- and "
     "geometry-checked against the block the RTL actually wrote"),
    ("cmjt-load", "isa.zcmt",
     "drop the single `M L` table load of a `cm.jt`/`cm.jalt` retire, bounded "
     "by addr == jvt + 4*index"),
    ("mret-csr", "priv.trapCsr",
     "drop the reference-only `C 310` (mstatush) and `C 7a5` (tcontrol) records "
     "of an `mret` retire"),
    ("mtrap-t", "priv.trapCsr",
     "drop the RTL `T` of a STANDARD-delivery trap, bounded by "
     "pc(next retire) == mtvec tracked from the stream's own `C 305`"),
    ("fcsr-split", "isa.zfinx",
     "rewrite the RTL's single `C 003` fcsr write into the reference's "
     "`C 001` + `C 002` decomposition"),
    ("hpm-warl", "isa.zihpm",
     "the HPM WARL allowlist: named HPM CSR WRITE records leave the compared "
     "stream on BOTH sides, and the CONFIGURATION registers' read-backs stop "
     "comparing rdval -- the COUNTERS' do not"),
    ("zacas-failwrite", "isa.zacas",
     "drop the SECOND `M L` of a FAILED `amocas` retire -- the lane-less "
     "AMO_WRITE transaction -- bounded by exactly two loads at ONE address, no "
     "store, and rd carrying the first load's data"),
    ("zcmp-frame-order", "isa.zcmp",
     "canonicalise the memory records of ONE Zcmp frame retire into ascending "
     "address order, INDEPENDENTLY on each side -- nothing is dropped; a "
     "positional compare becomes a set compare"),
)

AMENDMENT_NAMES = tuple(n for (n, _p, _d) in AMENDMENTS)
AMENDMENT_KNOB = dict((n, p) for (n, p, _d) in AMENDMENTS)
AMENDMENT_DESC = dict((n, d) for (n, _p, d) in AMENDMENTS)


def parse_names(values):
    """['a,b', 'c'] -> ('a','b','c') in canonical order; an unknown name raises. Refusing is the
    fail-safe direction: a typo in a derived flag must stop the run, never silently disable an
    amendment whose absence looks exactly like a passing comparison.
    """
    got = []
    for v in values or ():
        for tok in v.split(","):
            tok = tok.strip()
            if not tok:
                continue
            if tok not in AMENDMENT_NAMES:
                raise AmendError(
                    "unknown amendment %r; implemented: %s"
                    % (tok, ", ".join(AMENDMENT_NAMES)))
            if tok not in got:
                got.append(tok)
    return tuple(n for n in AMENDMENT_NAMES if n in got)


# instruction predicates.  Field-decoded from the wire `insn` string, never
# matched by suffix: `cbo.zero a1` ends a00f, not 200f.

def _word(insn):
    """The insn field as an int, or None if it is x-tainted / malformed."""
    try:
        return int(insn, 16)
    except (ValueError, TypeError):
        return None


# OP-FP (0x53) plus the four FMA opcodes.  Under Zfinx these all read and write
# x-registers, and every multi-cycle one passes through FPU_DONE -- the state
# whose unconditional `C 001` emission this amendment reconciles
# (`vesta_tracer.vhd`'s retire flush: `if state = ST_FPU_DONE then emit("C "
# ... "001 " ...)`).  Requiring an FP OPCODE is what keeps an explicit
# `csrrw fflags` out of the candidate set; see zfinx_should_skip.
FP_OPCODES = (0x53, 0x43, 0x47, 0x4b, 0x4f)


def is_fp_op(insn):
    w = _word(insn)
    return w is not None and len(insn) == 8 and (w & 0x7f) in FP_OPCODES


# `cbo.zero rs1` = MISC-MEM (0x0f) funct3=010, rd=00000, imm12=0x004; rs1 free.
# FIELD-DECODED, never matched by suffix: an "ends
# 200f" shorthand is wrong as a detector, because it holds only for
# rs1 in {x0,x1} -- `cbo.zero a1` ends `a00f`.  Measured this wave: gas 2.41
# assembles `cbo.zero (a1)` to 0x0045a00f.
CBOZ_MASK, CBOZ_MATCH = 0xfff07fff, 0x0040200f

# constants.vhd:158-159 fixes CBOZ_BLOCK_SIZE=64 / CBOZ_WORDS=16 as PACKAGE
# CONSTANTS -- there is no per-config override and no generic, so 16 is a hard
# number rather than something to derive.  Writing it here is the FAIL-SAFE
# direction: if the RTL's constant ever changed, this rule would REFUSE to drop
# (the count test below fails) and the stores would stay in the compared stream,
# i.e. the divergence becomes the report.  The dangerous direction would be to
# derive the expected count from the trace itself, which would bless any count.
CBOZ_WORDS = 16
CBOZ_BLOCK_SIZE = 64


def is_cbo_zero(insn):
    w = _word(insn)
    return w is not None and len(insn) == 8 and (w & CBOZ_MASK) == CBOZ_MATCH


# `cm.jt`/`cm.jalt`: 16-bit, funct3=101, bits[12:10]=000, index in bits[9:2],
# op=10.  Measured: `cm.jt 5` = 0xa016.
CMJT_MASK, CMJT_MATCH = 0xfc03, 0xa002


def cm_jt_index(insn):
    """The table index of a `cm.jt`/`cm.jalt`, or None if this is not one."""
    w = _word(insn)
    if w is None or len(insn) != 4:
        return None
    if (w & CMJT_MASK) != CMJT_MATCH:
        return None
    return (w >> 2) & 0xff


# SYSTEM opcode (0x73) with a nonzero funct3 is a CSR instruction.
def csr_access(insn):
    """(csr_addr, writes) for a 32-bit CSR instruction, else None. `writes` follows the architecture:
    csrrw and csrrwi always write; csrrs and csrrc write only when rs1 or uimm is nonzero, which
    is the rule csr_unit.vhd's csr_write_en implements.
    """
    w = _word(insn)
    if w is None or len(insn) != 8:
        return None
    if (w & 0x7f) != 0x73:
        return None
    f3 = (w >> 12) & 7
    if f3 == 0:
        return None                      # ecall/ebreak/mret/wfi/sfence
    rs1 = (w >> 15) & 0x1f
    writes = (f3 & 3) == 1 or rs1 != 0
    return ((w >> 20) & 0xfff, writes)


def is_mret(insn):
    """`mret` = 0x30200073 exactly (funct3=0 SYSTEM, funct12=0x302)."""
    return _word(insn) == 0x30200073


# `amocas.w/.b/.h` = AMO_OPCODE ("0101111" = 0x2f) with funct5 = CAS_FN5
# ("00101", `hdl/common/constants.vhd:138`).  FIELD-DECODED from the two fields
# the RTL's own `cas_op` term reads (`vesta.vhd:2010-2011`:
# `instr_curr(6 downto 0) = AMO_OPCODE and instr_curr(31 downto 27) = CAS_FN5`),
# so the predicate here IS the decode predicate rather than a re-derivation of
# it.  aq/rl (bits 26:25) and funct3 (the .w/.b/.h width) are deliberately
# OUTSIDE the mask: the width does not change the record shape this rule is
# about, and the size equality below covers it.
AMOCAS_MASK, AMOCAS_MATCH = 0xf800007f, 0x2800002f


def is_amocas(insn):
    w = _word(insn)
    return w is not None and len(insn) == 8 and (w & AMOCAS_MASK) == AMOCAS_MATCH


def amocas_failwrite_ok(retire, mem):
    """The bound on a zacas-failwrite drop, returning (ok, why-not): exactly two M records in the
    retire's group, both L, same address and size, the second's data all-zero, neither x-tainted,
    and rdval equal to the first load's data unless rd is x0. A failing CAS that wrote fails it.
    """
    if len(mem) != 2:
        return False, ("expected exactly 2 memory records in the retire group, "
                       "saw %d (%s)"
                       % (len(mem), " ".join(m.f[0] + m.f[1] for m in mem)
                          if mem else "none"))
    a, b = mem
    # THE DIRECTION BOUND -- the test that keeps a COMMITTED STORE out of the
    # candidate set.  It is one of TWO redundant guards on the L,S success shape
    # (the other is the caller's `success` short-circuit), and the redundancy was
    # MEASURED rather than assumed: wrong-version controls W2 and W2b removed
    # each guard on its own and NEITHER changed a verdict.  Only W2c -- both gone
    # at once -- is detectable, and it is detectable on exactly one stream: a
    # SUCCESSFUL CAS THAT SWAPS IN ZERO, whose store satisfies every other bound
    # here (same address, same size, data 00000000).  Keep both guards.
    if a.f[0] != "L" or b.f[0] != "L":
        return False, ("the group is %s,%s -- a FAILED CAS emits L,L; L,S is the "
                       "SUCCESS shape and is never a candidate"
                       % (a.f[0], b.f[0]))
    # A5.  NOT redundant with the field bounds below, and the discriminating case
    # is the one a wrong-version control (W7) had to be rewritten to find: `x` in
    # a record's HART or CYCLE field sets `has_x` while every field this rule
    # bounds stays well-formed (`records.py`: an x on the tracer's own counter
    # means the trace is not trustworthy, even though neither field is compared).
    # An x inside addr/size/data is caught twice over -- by this and by the
    # equality bounds -- and that overlap is deliberate, not accidental.
    if a.has_x or b.has_x:
        return False, "an x-tainted record is never dropped (Amendment A5)"
    if a.f[1] != b.f[1]:
        return False, ("the two loads are at DIFFERENT addresses %s and %s"
                       % (a.f[1], b.f[1]))
    if a.f[2] != b.f[2]:
        return False, ("the two loads have DIFFERENT sizes %s and %s"
                       % (a.f[2], b.f[2]))
    if b.f[3] != "00000000":
        return False, ("the second load carries data %s, expected 00000000 (the "
                       "fill-lost signature)" % b.f[3])
    if retire.f[2] != "00" and retire.f[3] != a.f[3]:
        return False, ("rd=%s retired %s but the first load returned %s -- rd "
                       "does not carry the old memory word"
                       % (retire.f[2], retire.f[3], a.f[3]))
    return True, ""


# The A8 legacy trap sentinel.  `mtrap-t` NEVER touches it: it is the ISR
# bracket delimiter (`mk_inject.py`'s opener) and it means "the legacy vectored
# path", which the reference cannot model at all and which the bracket channel
# already owns.  This amendment is only about the STANDARD delivery a TRAPCSR
# build in `std_mode` uses, where BOTH sides take the architectural exception.
LEGACY_TRAP_CAUSE = "8000007f"


# The Zcmp PUSH/POP FRAME family: `cm.push` / `cm.pop` / `cm.popretz` /
# `cm.popret`.  Field-decoded from EXACTLY the terms `c_dec.vhd:761-769` tests
# before it synthesises the sentinel -- quadrant bits(1:0)="10", funct3
# bits(15:13)="101", bit12='1' (the push/pop half of the slot), bit11='1',
# bit8='0', and rlist = bits(7:4) >= 4 (0-3 are reserved and c_dec emits
# illegal).  bits(10:9) select push/pop/popretz/popret and are deliberately
# OUTSIDE the mask: all four move a contiguous register frame and all four have
# the record shape this rule canonicalises.
#
# `cm.jt`/`cm.jalt` (Zcmt) live in the SAME funct3 slot with bit12='0', so they
# cannot collide -- and they are `cmjt-load`'s business, not this rule's.
# `cm.mvsa01`/`cm.mva01s` also have bit12='0' and touch no memory at all.
ZCMFRAME_MASK, ZCMFRAME_MATCH = 0xf903, 0xb802


def is_zcm_frame(insn):
    w = _word(insn)
    if w is None or len(insn) != 4:
        return False
    if (w & ZCMFRAME_MASK) != ZCMFRAME_MATCH:
        return False
    return ((w >> 4) & 0xf) >= 4          # rlist 0-3 are reserved


def zcm_frame_ok(mem):
    """The bound on canonicalising one Zcmp frame's memory group, returning (ok, why-not): every
    record the same direction and size, addresses a contiguous ascending XLEN-spaced run with no
    repeat. Contiguity keeps it count-aware: a short group is caught by the walk, a repeat here.
    """
    if len(mem) < 2:
        return False, "fewer than two records -- nothing to canonicalise"
    d = mem[0].f[0]
    if any(m.f[0] != d for m in mem):
        return False, ("mixed directions %s -- a Zcmp frame is all loads or all "
                       "stores" % "".join(m.f[0] for m in mem))
    sz = mem[0].f[2]
    if any(m.f[2] != sz for m in mem):
        return False, ("mixed sizes %s"
                       % " ".join(str(m.f[2]) for m in mem))
    if any(m.has_x for m in mem):
        return False, "an x-tainted record is never reordered (Amendment A5)"
    addrs = [_word(m.f[1]) for m in mem]
    if any(a is None for a in addrs):
        return False, "an address is x-tainted or malformed"
    if len(set(addrs)) != len(addrs):
        return False, ("repeated address in the frame (%s) -- there is no "
                       "canonical order for two records at one address"
                       % " ".join(m.f[1] for m in mem))
    want = sorted(addrs)
    if any(want[k] != want[0] + 4 * k for k in range(len(want))):
        return False, ("the frame addresses are not a contiguous 4-byte run "
                       "(%s)" % " ".join("%08x" % a for a in want))
    return True, ""


def zcm_frame_canon(recs, am, side):
    """Canonicalise one Zcmp frame's memory records to ascending address; returns a new list. It
    suppresses nothing: every record keeps every field, and each side is sorted from its own
    contents, which is a set compare of the two groups with no compared field given up.
    """
    if not am.enabled("zcmp-frame-order"):
        return recs
    out = []
    i, n = 0, len(recs)
    while i < n:
        r = recs[i]
        out.append(r)
        if r.kind == "R" and is_zcm_frame(r.f[1]):
            j, mem = i + 1, []
            while j < n and recs[j].kind == "M":
                mem.append(recs[j])
                j += 1
            # A one-record frame (`rlist`=4 saves ra alone) is legitimate and
            # common; there is nothing to canonicalise and a refusal line for
            # every one of them would be noise, not a finding.
            if len(mem) >= 2:
                ok, why = zcm_frame_ok(mem)
                if ok:
                    # ASCENDING, and the direction is NOT arbitrary even though
                    # any total order would do when BOTH sides canonicalise.
                    # They do not always: a side whose group is x-tainted or
                    # non-contiguous REFUSES and keeps its emitted order, and the
                    # tracer's emitted order is ascending (measured, every frame
                    # on `rv32ua-p-extzcmp`). Ascending therefore leaves a
                    # refused RTL group still aligned against a canonicalised
                    # reference; descending would manufacture a divergence there.
                    # Found by a wrong-version control (V7), which was predicted
                    # to be undetectable and was not.
                    srt = sorted(mem, key=lambda m: m.f[1])
                    if [id(x) for x in srt] != [id(x) for x in mem]:
                        am.bump("zcmp-frame-order",
                                "%s %s %s%s" % (side, r.f[0], mem[0].f[0],
                                                srt[0].f[1]))
                    out.extend(srt)
                    i = j
                    continue
                am.refuse("zcmp-frame-order", r.lineno,
                          "Zcmp frame at pc %s: %s -- NOTHING was reordered, so "
                          "the group is compared exactly as emitted and the "
                          "divergence is the report" % (r.f[0], why))
        i += 1
    return out


def cboz_shape_ok(stores):
    """The geometry bound on a cbo.zero drop, returning (ok, why-not): exactly CBOZ_WORDS records,
    each size 4 and data zero, at base, base+4 ... base+60 with base 64-byte aligned. Stated over
    the store addresses and never over rs1, which the RTL rounds down and the trace omits.
    """
    if len(stores) != CBOZ_WORDS:
        return False, ("expected exactly %d store records, saw %d"
                       % (CBOZ_WORDS, len(stores)))
    base = _word(stores[0].f[1])
    if base is None:
        return False, "the first store's address is x-tainted"
    if base % CBOZ_BLOCK_SIZE:
        return False, ("the first store's address %s is not %d-byte aligned"
                       % (stores[0].f[1], CBOZ_BLOCK_SIZE))
    for k, s in enumerate(stores):
        if s.f[2] != "4":
            return False, ("store %d has size %s, expected 4" % (k, s.f[2]))
        if s.f[3] != "00000000":
            return False, ("store %d writes %s, expected 00000000"
                           % (k, s.f[3]))
        want = "%08x" % (base + 4 * k)
        if s.f[1] != want:
            return False, ("store %d is at %s, expected %s (base+4*%d)"
                           % (k, s.f[1], want, k))
    return True, ""


# the HPM WARL allowlist -- NAMED addresses, two tiers, and the second tier is
# deliberately SMALLER than the first.
#
# TIER 1 (`HPM_C_DROP`): the CSR-WRITE record leaves the compared stream on BOTH
# sides.  The two models disagree about whether such a write is loggable at all,
# and they disagree DIFFERENTLY per address -- measured on the reference this
# wave:
#     csrw 0x323 / 0x324  ->  `C 323/324 00000000`   (WARL-masked to zero)
#     csrw 0xb03/b83/b04/b84 -> NOTHING logged
#     csrw 0x320          ->  `C 320 fffffffd`       (its own WARL mask)
# while the RTL with ENABLE_ZIHPM stores and logs the value for every one of
# them (`csr_unit.vhd:386-388` lists exactly this group under ENABLE_ZIHPM).  So
# the disagreement is a VALUE mismatch on some addresses and a record-KIND
# mismatch on others, and dropping BOTH sides is the only rule that covers the
# class without pretending to know which shape a given address takes.
#
# THE SET IS EXACTLY `csr_addr_stores`'s ZIHPM GROUP, and two addresses the
# handoff draft included are deliberately ABSENT: `0xb05`/`0xb85`
# (mhpmcounter5/5h) are NOT in that group, so the RTL emits no `C` for them, and
# the reference logs none either -- a rule arm that cannot fire is decoration,
# which is worse than absent.
HPM_C_DROP = frozenset((
    0x320,                        # mcountinhibit
    0x323, 0x324,                 # mhpmevent3 / mhpmevent4
    0xb03, 0xb83, 0xb04, 0xb84,   # mhpmcounter3/3h/4/4h
))

# TIER 2 (`HPM_RDVAL_RELAX`): the READ-BACK stops comparing `rdval`.  This is the
# CONFIGURATION registers ONLY.
#
# `mhpmcounter*` IS DELIBERATELY ABSENT, AND THAT ABSENCE IS THE POINT OF THE
# WHOLE AMENDMENT.  The extzihpm disposition records that the
# predicted F1 divergence -- hpm counter VALUES under the gated clock -- lies
# further down that test's stream and is MASKED by the first mismatch.  Tier 1
# unmasks it.  Relaxing the counter read-backs here would re-mask it with the
# very instrument written to expose it.  So the
# counters' read values stay COMPARED, the row is EXPECTED to end in a divergence
# there, and that divergence is the amendment's deliverable rather than its
# failure.
HPM_RDVAL_RELAX = frozenset((0x320, 0x323, 0x324))


class Amend(object):
    """The enabled set plus every census the summary has to print."""

    def __init__(self, names):
        self.names = tuple(names)
        self.on = set(names)
        # per-amendment census dicts; a name is present iff it is enabled, so
        # an absent block in the summary means "not enabled", never "nothing
        # to say" (the A15 discipline).
        self.census = dict((n, {}) for n in names)
        self.counts = dict((n, 0) for n in names)
        self.refused = dict((n, []) for n in names)
        self.zfinx_cand = set()          # id(rec) of marked C 001 candidates
        self.zfinx_kept = 0              # candidates the reference DID present

    def enabled(self, name):
        return name in self.on

    def bump(self, name, ident, n=1):
        self.counts[name] += n
        c = self.census[name]
        c[ident] = c.get(ident, 0) + n

    def refuse(self, name, lineno, why):
        self.refused[name].append((lineno, why))


# the RTL-side pre-pass

def rtl_prepass(recs, am):
    """Apply every RTL-side amendment to an already-compared stream; returns a new list. Nothing
    here reads the reference, so a drop cannot be talked into existence by the thing it is
    checked against. zfinx-fflags only marks here and decides in the walk.
    """
    if not am.names:
        return recs

    # `zcmp-frame-order` runs FIRST and as its own pass, on both sides, because
    # it is a canonicalisation rather than a rule about this stream's contents:
    # every later rule should see one order.  It touches only `M` records inside
    # a Zcmp frame retire, which no other rule here looks at, so the two passes
    # cannot interfere.
    recs = zcm_frame_canon(recs, am, "rtl")

    out = []
    n = len(recs)
    i = 0
    fflags = 0                 # the RTL's fflags state, tracked from the stream
    jvt = 0                    # the RTL's jvt, likewise (its own `C 017`)
    mtvec = 0                  # ... and its mtvec, from its own `C 305`
    while i < n:
        r = recs[i]
        # `fflags` must hold the state BEFORE this record for the candidate
        # test below to mean "asserts no change"; the state update happens
        # after it, never before.  (Updating first made every `C 001` trivially
        # equal to the running state -- a self-fulfilling candidate test, and
        # the first defect this file's own review found.)
        fflags_before = fflags
        if r.kind == "C":
            v = _word(r.f[1])
            if v is not None and r.f[0] in ("001", "003"):
                # 0x001 fflags is the low 5 bits of the RTL's `fp_csr`; 0x003
                # fcsr is {frm, fflags} and its low 5 bits are the same field
                # (csr_unit.vhd's CSR_FFLAGS / CSR_FCSR write arms).
                fflags = v & 0x1f
            elif v is not None and r.f[0] == "017":
                # jvt, from the RTL's OWN record -- the A3 discipline: the bound
                # a drop is checked against is tracked from the stream being
                # amended, never from the reference and never from a literal.
                jvt = v
            elif v is not None and r.f[0] == "305":
                mtvec = v

        # -- mtrap-t: the `T` of a STANDARD-delivery trap [R-K2b-2 (2)]
        # A TRAPCSR build in std_mode takes an ARCHITECTURAL exception that the
        # reference takes too, at the same pc, and both then execute the same
        # handler out of the same memory.  The only misalignment is the RTL `T`
        # itself, which the reference's commit log has no counterpart for
        # (RECORD_FORMAT §4).  So the `T` is dropped -- and ONLY when the RTL
        # really did vector to mtvec, which is the bound.
        #
        # WHAT THE BOUND PROTECTS AGAINST, both directions:
        #   * the LEGACY sentinel is excluded by cause, above: that path is the
        #     bracket channel's and must keep its meaning;
        #   * a TERMINAL trap (`vesta_tracer.vhd`: `next_state = ST_TRAP_STATE`)
        #     also emits a non-legacy `T`, and TRAP_STATE self-loops, so there is
        #     NO next retire at all -- the bound fails and the `T` is reported.
        #     That case matters: a terminal trap is a wedged hart, and an
        #     amendment that swallowed it would hide the loudest failure the
        #     tracer has.
        # WHAT IT DOES NOT GIVE AWAY (and it belongs in the record): mcause,
        # mepc and mtval stay COMPARED -- through the handler's own `csrr`
        # retires' rdval, which is a stronger check than the uncompared `T`
        # fields.  And an RTL-only spurious trap still surfaces ONE RECORD LATER
        # as a pc mismatch, because the reference did not go to the handler.
        if r.kind == "T" and am.enabled("mtrap-t"):
            if r.f[0] != LEGACY_TRAP_CAUSE:
                nxt = None
                for k in range(i + 1, n):
                    if recs[k].kind == "R":
                        nxt = recs[k]
                        break
                land = nxt.f[0] if nxt is not None else None
                # `MTRAP_JUMP` loads mtvec.BASE&"00" (the RTL pins MODE to 00),
                # and the trace's `C 305` carries the value the write REQUESTED
                # (csr_unit.vhd:1189-1193's documented approximation), so the
                # comparison is against the BASE, not the raw word.
                want = "%08x" % (mtvec & 0xfffffffc)
                if land is not None and land == want:
                    am.bump("mtrap-t", r.f[0])
                    i += 1
                    continue
                am.refuse("mtrap-t", r.lineno,
                          "trap cause=%s epc=%s: the next retire is at pc=%s "
                          "but mtvec.BASE (from this stream's own `C 305`) is "
                          "%s -- the T is KEPT and reported"
                          % (r.f[0], r.f[1], land or "<none: no retire "
                             "follows, i.e. a TERMINAL trap>", want))

        # -- hpm-warl tier 1, RTL side: the HPM write records leave the stream --
        if r.kind == "C" and am.enabled("hpm-warl"):
            a = _word(r.f[0])
            if a is not None and a in HPM_C_DROP:
                am.bump("hpm-warl", "rtl C %s" % r.f[0])
                i += 1
                continue

        # -- fcsr-split: one RTL `C 003` becomes the reference's two records ---
        # Measured: `csrw fcsr,t0` with t0=7 logs
        # `c1_fflags 0x00000007 c2_frm 0x00000000` on the reference and a single
        # `C 003 00000007` on the RTL side, whose csr_unit write arm is one
        # assignment (`fp_csr <= csr_new_val(7 downto 0)`).  Architectural state
        # AGREES; only the record shape differs, so this rule REWRITES rather
        # than drops -- both halves stay compared, at their reference values.
        # Bounded by the owning retire being an explicit CSR WRITE to 0x003, so
        # a `C 003` arriving from anywhere else is left alone and reported.
        if (r.kind == "C" and r.f[0] == "003" and am.enabled("fcsr-split")
                and "x" not in r.f[1]):
            owner = _owning_retire(recs, i)
            acc = csr_access(owner.f[1]) if owner is not None else None
            v = _word(r.f[1])
            if acc is not None and acc[0] == 0x003 and acc[1] and v is not None:
                out.append(Rec("C", r.hart, r.cycle,
                               ("001", "%08x" % (v & 0x1f)), r.lineno,
                               r.source, r.has_x))
                out.append(Rec("C", r.hart, r.cycle,
                               ("002", "%08x" % ((v >> 5) & 0x7)), r.lineno,
                               r.source, r.has_x))
                am.bump("fcsr-split", "%08x" % v)
                i += 1
                continue
            am.refuse("fcsr-split", r.lineno,
                      "a `C 003` whose owning retire is %s is not an explicit "
                      "fcsr write -- left alone"
                      % (owner.f[1] if owner is not None else "<none>"))

        if (r.kind == "C" and r.f[0] == "001" and am.enabled("zfinx-fflags")
                and "x" not in r.f[1]):
            owner = _owning_retire(recs, i)
            if owner is not None and is_fp_op(owner.f[1]):
                v = _word(r.f[1])
                if v is not None and (v & 0x1f) == fflags_before:
                    am.zfinx_cand.add(id(r))

        out.append(r)

        # -- cboz-stores: the 16 stores that belong to a `cbo.zero` retire
        # RECORD_FORMAT §0 fixes the per-retire emission order (R, then every
        # `M L`, then every `M S`, then every `C`), and the tracer flushes the
        # `cbo.zero` group in one go -- one `R` with rd=0 plus 16 `M S`
        # (`vesta_tracer.vhd`'s retire flush).  So the stores are exactly the
        # run of `M S` records immediately after this retire.
        if (r.kind == "R" and am.enabled("cboz-stores")
                and is_cbo_zero(r.f[1])):
            j, stores = i + 1, []
            while j < n and recs[j].kind == "M" and recs[j].f[0] == "S":
                stores.append(recs[j])
                j += 1
            ok, why = cboz_shape_ok(stores)
            if ok:
                am.bump("cboz-stores", "%s@%s" % (r.f[0], stores[0].f[1]),
                        len(stores))
                i = j
                continue
            am.refuse("cboz-stores", r.lineno,
                      "cbo.zero at pc %s: %s -- NOTHING was dropped, so the "
                      "stores stay in the compared stream and the divergence "
                      "is the report" % (r.f[0], why))

        # -- cmjt-load: the one table load that belongs to a `cm.jt` retire ---
        if r.kind == "R" and am.enabled("cmjt-load"):
            idx = cm_jt_index(r.f[1])
            if idx is not None:
                j, loads = i + 1, []
                while j < n and recs[j].kind == "M" and recs[j].f[0] == "L":
                    loads.append(recs[j])
                    j += 1
                want = "%08x" % ((jvt + 4 * idx) & 0xffffffff)
                if len(loads) == 1 and loads[0].f[1] == want:
                    am.bump("cmjt-load", "%s->%s" % (r.f[0], want))
                    i = j
                    continue
                # The equality is the whole bound: a table fetch from anywhere
                # other than `jvt + 4*index` is precisely what a broken ZCM_JT_LD
                # would produce, and it must reach the comparison.  Note this
                # also fails loudly on a `jvt` the RTL never announced -- jvt
                # starts at 0 here and only a `C 017` moves it.
                am.refuse("cmjt-load", r.lineno,
                          "cm.jt index %d at pc %s: expected exactly one `M L` "
                          "at jvt+4*index = %s, saw %d load(s)%s -- NOTHING was "
                          "dropped"
                          % (idx, r.f[0], want, len(loads),
                             (" at " + " ".join(x.f[1] for x in loads))
                             if loads else ""))

        # -- zacas-failwrite: the lane-less AMO_WRITE record of a FAILED CAS --
        # RECORD_FORMAT §0 fixes the per-retire order (R, then every `M L`, then
        # every `M S`), so an `amocas` retire's memory group is the run of `M`
        # records immediately after it.  THE SUCCESS SHAPE IS EXACTLY [L, S] and
        # is skipped here WITHOUT a refusal line -- it already matches the
        # reference, and a refusal printed at every successful CAS would bury the
        # real ones.  IT IS ALSO ONE OF TWO REDUNDANT GUARDS on that shape -- the
        # other is the direction test inside `amocas_failwrite_ok` -- and neither
        # is detectable alone (wrong-version controls W2/W2b); only removing both
        # is, and only on a CAS that swaps in ZERO.  Keep both.
        # Every other shape is JUDGED, including the empty one: an `amocas` with
        # no memory group at all is not something this rule should pass over in
        # silence.
        if (r.kind == "R" and am.enabled("zacas-failwrite")
                and is_amocas(r.f[1])):
            j, mem = i + 1, []
            while j < n and recs[j].kind == "M":
                mem.append(recs[j])
                j += 1
            success = (len(mem) == 2 and mem[0].f[0] == "L"
                       and mem[1].f[0] == "S")
            if not success:
                ok, why = amocas_failwrite_ok(r, mem)
                if ok:
                    am.bump("zacas-failwrite", "%s@%s" % (r.f[0], mem[0].f[1]))
                    out.append(mem[0])
                    i = j
                    continue
                am.refuse("zacas-failwrite", r.lineno,
                          "amocas at pc %s: %s -- NOTHING was dropped, so the "
                          "record stays in the compared stream and the "
                          "divergence is the report" % (r.f[0], why))
        i += 1
    return out


def _owning_retire(recs, i):
    """The R record whose retire group record i belongs to. The per-retire emission order is R, then
    every M L, then every M S, then every C, so the owner is the nearest preceding R with no
    intervening R. A T terminates the search: a trap entry is not a retire and owns nothing.
    """
    k = i - 1
    while k >= 0:
        if recs[k].kind == "R":
            return recs[k]
        if recs[k].kind == "T":
            return None
        k -= 1
    return None


# the REFERENCE-side pre-pass

def spike_prepass(recs, am):
    """Apply every reference-side amendment; returns a new list. The only place any amendment
    touches the reference stream, and a rule here can only make the reference smaller, never
    invent a record. It never reads the RTL stream, for the reason rtl_prepass never reads this.
    """
    if not am.names:
        return recs
    # The ONE rule here that removes nothing (see `zcm_frame_canon`): it puts the
    # reference's Zcmp frame group into the same canonical order the RTL side was
    # put into, computed from THIS stream alone.  Applied before the drops below
    # for the same reason it is applied first on the RTL side.
    recs = zcm_frame_canon(recs, am, "spike")
    if not (am.enabled("mret-csr") or am.enabled("hpm-warl")):
        return recs
    out = []
    for i, r in enumerate(recs):
        # -- hpm-warl tier 1, reference side (see HPM_C_DROP)
        if r.kind == "C" and am.enabled("hpm-warl"):
            a = _word(r.f[0])
            if a is not None and a in HPM_C_DROP:
                am.bump("hpm-warl", "spike C %s" % r.f[0])
                continue

        if r.kind == "C" and am.enabled("mret-csr") and r.f[0] in ("310", "7a5"):
            # THE ADDRESS IS 0x7a5, AND THE FROZEN SPEC SAYS 0x7a1.  The spec
            # inherited "{0x310 mstatush, 0x7a1 tcontrol}" from the K0 oracle
            # probe §1.3i's PROSE, which contradicts the MEASUREMENT printed two
            # lines above it in the same section: `c1957_tcontrol`, and
            # 1957 = 0x7a5 (0x7a1 is tdata1, a different debug CSR).  Re-measured
            # on the reference this wave -- an `mret` from reset logs
            #   c768_mstatus 0x00001880  c784_mstatush 0x0  c1957_tcontrol 0x0
            # -- and the unit fixture built from that verbatim line is what
            # caught it.  The datum beats the prose; the spec is corrected by
            # this measurement, not worked around.
            #
            # BOUNDED TO THE `mret` RETIRE, not to the address.  0x310 mstatush
            # and 0x7a5 tcontrol simply do not exist in the VestaRV CSR map, so
            # the reference logging them at an `mret` is the measured shape
            # (k0 §1.3i) -- but a reference `C 310` owned by anything else would
            # be a record about an instruction the RTL executed too, and it stays
            # in the comparison where it can be seen.
            owner = _owning_retire(recs, i)
            if owner is not None and is_mret(owner.f[1]):
                am.bump("mret-csr", "C %s" % r.f[0])
                continue
            am.refuse("mret-csr", r.lineno,
                      "a reference `C %s` whose owning retire is %s is NOT an "
                      "mret -- kept, because the allowlist is bounded to the "
                      "mret retire and nothing else"
                      % (r.f[0], owner.f[1] if owner is not None else "<none>"))
        out.append(r)
    return out


# the walk-level rule

def zfinx_should_skip(am, a, b):
    """True when RTL record `a` is a marked C 001 the reference did not emit. A value-only rule is
    too wide, so the drop also requires the reference not to be presenting that record, the owning
    retire to be an FP opcode, and the record not to be x-tainted. It can only refuse to drop.
    """
    if not am.enabled("zfinx-fflags") or id(a) not in am.zfinx_cand:
        return False
    if b is not None and a.key() == b.key():
        am.zfinx_kept += 1
        return False
    am.bump("zfinx-fflags", a.f[1])
    return True


def hpm_keys_match(am, a, b):
    """rdval relaxation on a read-back of a tier-2 HPM CSR. Called only after the keys already
    differ, so it can only rescue a disagreeing pair, and only on the one field the two models may
    legally disagree about; pc, insn and rd must still be equal, and the record count is untouched.
    """
    if not am.enabled("hpm-warl"):
        return False
    if a.kind != "R" or b.kind != "R":
        return False
    if a.f[0] != b.f[0] or a.f[1] != b.f[1] or a.f[2] != b.f[2]:
        return False
    acc = csr_access(a.f[1])
    if acc is None or acc[0] not in HPM_RDVAL_RELAX:
        return False
    am.bump("hpm-warl", "rdval %03x" % acc[0])
    return True


# reporting

def summarise(err, am):
    """The `--amend` block.  Printed whenever ANY amendment is enabled,
    including its zero form: an amendment that never fires on its own config
    is VACUOUS, and the only way that can be seen is if the zero is printed."""
    if not am.names:
        return
    err.write("  --- config amendments [--amend] ---\n")
    for name in am.names:
        n = am.counts[name]
        err.write("  %-22s %d application(s)   (gate: %s)%s\n"
                  % (name, n, AMENDMENT_KNOB[name],
                     "" if n else "   <-- VACUOUS on this run"))
        for ident in sorted(am.census[name]):
            err.write("      %-24s x%d\n" % (ident, am.census[name][ident]))
        for lineno, why in am.refused[name]:
            err.write("      REFUSED at trace line %d: %s\n" % (lineno, why))
    if am.enabled("zfinx-fflags"):
        err.write("  %-22s %d marked `C 001` record(s) were COMPARED because "
                  "the reference\n                         presented them too "
                  "(the narrowing at work, not a suppression)\n"
                  % ("zfinx-fflags kept", am.zfinx_kept))
