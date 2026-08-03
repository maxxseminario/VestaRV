#!/usr/bin/python3.6
# -*- coding: utf-8 -*-
"""K2b -- the CONFIG-GATED comparator amendments.

Each amendment exists because the K0 oracle probe MEASURED that a knobs-on
VestaRV configuration and the reference model describe the same architectural
event with DIFFERENT RECORD STREAMS.  None of them changes what an instruction
is allowed to do; every one of them changes only which records are compared,
and only on a configuration whose resolved config turns the owning knob on.

    knob            amendment name            what it reconciles
    --------------  ------------------------  ------------------------------
    isa.zfinx       zfinx-fflags              the RTL tracer emits `C 001`
                                              on EVERY FPU_DONE; Spike emits
                                              it only when the op RAISED a
                                              flag (k0 oracle probe §1.3m)
    isa.zicboz      cboz-stores               one `cbo.zero` is 1 `R` + SIXTEEN
                                              `M S` on the RTL side and 1 `R` +
                                              ZERO on the reference's: Spike
                                              zeroes the block architecturally
                                              and logs no `mem` field at all
                                              (k0 oracle probe §1.3d)
    isa.zcmt        cmjt-load                 `cm.jt` fetches its table entry on
                                              the DATA port (state ZCM_JT_LD) --
                                              one `M L` the reference never logs
                                              (k0 oracle probe §1.3e)
    priv.trapCsr    mret-csr                  `mret` is THREE reference `C`
                                              records (300 mstatus, 310
                                              mstatush, 7a5 tcontrol) and ONE
                                              RTL one: the latter two CSRs do
                                              not exist in the VestaRV map
                                              (k0 oracle probe §1.3i)
    priv.trapCsr    mtrap-t                   a STANDARD-delivery trap emits an
                                              RTL `T`; the reference's commit
                                              log carries no trap information at
                                              all (RECORD_FORMAT §4), so both
                                              sides execute the handler and only
                                              the `T` itself misaligns
                                              [R-K2b-2 (2)]
    isa.zfinx       fcsr-split                one RTL `C 003` fcsr write is TWO
                                              reference records, `C 001` fflags
                                              + `C 002` frm (k0 oracle probe
                                              §1.3h)

(The K2b spec's amendment 4 -- the ZIHPM WARL allowlist -- lands in its own
commit and extends the table above.  One amendment, one commit, one set of
default-config pins.)

WHERE A NEW RULE BELONGS, AND WHY IT MATTERS (the A17 acceptance lesson).
`--count` measures the RTL window AFTER `rtl_prepass` and its number is fed
back as `--max-records`, which bounds WINDOW POSITION.  So a rule that decides
from the RTL stream alone costs nothing: its drops are already inside the
count.  **Only a rule that CONSULTS THE REFERENCE (today, only `zfinx-fflags`)
can part the window size from the compared count** -- which is exactly what
made every Zfinx cell with a nonzero drop count exit `2-rtlshort` before the
bound was fixed.  Prefer the prepass for every new rule; when a rule genuinely
needs the reference, the window-position bound is what makes it safe.

**THESE ARE SUPPRESSIONS, THE HIGHEST-RISK INSTRUMENT CLASS** (method rule 11:
an instrument keyed on what it observes reports zero, which reads as success).
Three disciplines are therefore applied to every one of them, taken from the
A9/A15/A16 precedents that already govern this comparator:

  1. **BOUNDED BY AN EQUALITY OR A DECODED FIELD, NEVER BY AN FSM STATE OR A
     NAME.**  When the bound FAILS the amendment DECLINES to drop and says so,
     which makes the ensuing divergence the report -- exactly as A3 requires.
  2. **COUNTED AND PRINTED, ALWAYS.**  Every application is counted per
     identity and printed in the stderr summary, including the zero case, so
     an amendment that starts firing beyond its written rationale is visible in
     the run log.  An amendment that fires ZERO times on its own config is
     VACUOUS and must be reported as such.
  3. **NEVER GLOBAL.**  The enabled set is DERIVED from the resolved chip
     config by `oracle_isa.derive_amendments()`; the default Castalia config
     enables NONE of them and its four gate pins are unmoved.

Stdlib only.  Python 3.6 syntax only.
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
)

AMENDMENT_NAMES = tuple(n for (n, _p, _d) in AMENDMENTS)
AMENDMENT_KNOB = dict((n, p) for (n, p, _d) in AMENDMENTS)
AMENDMENT_DESC = dict((n, d) for (n, _p, d) in AMENDMENTS)


def parse_names(values):
    """['a,b', 'c'] -> ('a','b','c') in CANONICAL order, unknown names raise.

    Refusing an unknown name is the fail-safe direction (method rule 15): a
    typo in a derived flag must stop the run, never silently disable an
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


# --------------------------------------------------------------------------
# instruction predicates.  Field-decoded from the wire `insn` string, never
# matched by suffix -- R-K2-5's `200f` lesson ("`cbo.zero a1` ends a00f").
# --------------------------------------------------------------------------

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
# FIELD-DECODED, never matched by suffix: R-K2-5 ruled the s5_ledger's "ends
# 200f" census shorthand WRONG as a detector because it holds only for
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
# op=10.  Measured (k0 oracle probe §1.3e): `cm.jt 5` = 0xa016.
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
    """(csr_addr:int, writes:bool) for a 32-bit CSR instruction, else None.

    `writes` follows the architecture: csrrw/csrrwi always write; csrrs/csrrc
    (and their immediate forms) write only when rs1/uimm is nonzero -- the same
    rule `csr_unit.vhd`'s `csr_write_en` implements since P3-entry.
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


# The A8 legacy trap sentinel.  `mtrap-t` NEVER touches it: it is the ISR
# bracket delimiter (`mk_inject.py`'s opener) and it means "the legacy vectored
# path", which the reference cannot model at all and which the bracket channel
# already owns.  This amendment is only about the STANDARD delivery a TRAPCSR
# build in `std_mode` uses, where BOTH sides take the architectural exception.
LEGACY_TRAP_CAUSE = "8000007f"


def cboz_shape_ok(stores):
    """The GEOMETRY bound on a `cbo.zero` drop.  (ok, why-not) -- ALL of:

        exactly CBOZ_WORDS records, every one `size 4` / `data 00000000`,
        addresses base, base+4, ... base+60 in that order, base 64-B aligned.

    THE BOUND IS STATED OVER THE SIXTEEN STORE ADDRESSES, NEVER OVER `rs1`, and
    that is not a stylistic choice.  `vesta.vhd` computes
    `cboz_base <= rs1_value and not (CBOZ_BLOCK_SIZE-1)` -- it ROUNDS DOWN -- and
    `shcboz.S` deliberately issues `cbo.zero` from `rs1 = block+20` and
    `rs1 = block+44` to prove exactly that.  A bound written as "the first store
    is at rs1" would pass `extzicboz` (whose only `cbo.zero` is aligned) and
    REFUSE two legitimate `shcboz` cases -- a test calibrated on the one shape
    it was developed against, which is method rule 7 arrived at from the other
    direction.  `rs1` is not consulted here at all; the trace does not carry it.

    What the bound buys: the K2b spec requires the suppression to stay
    COUNT-AWARE -- "a sequencer that stores 15 words instead of 16 must still be
    caught" (`verification/isa/negctrl/x3_zicboz_partial.patch` is that mutant).
    A 15-store burst fails the FIRST test here, nothing is dropped, and the
    stores meet the reference's next record and diverge.  The amendment DECLINES
    and says so; it never converts a wrong burst into a pass.
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


# --------------------------------------------------------------------------
# the RTL-side pre-pass
# --------------------------------------------------------------------------

def rtl_prepass(recs, am):
    """Apply every RTL-side amendment to an already-compared stream.

    `recs` is the R/M/C(+T) projection, AFTER canonicalise_a2.  Returns a NEW
    list.  Nothing here reads the reference: every rule is decided from the RTL
    stream's own contents, so a drop cannot be talked into existence by the
    thing it is supposed to be checked against.  (The ONE rule that does need
    the reference -- `zfinx-fflags` -- only MARKS here and decides in the walk;
    see `zfinx_should_skip`.)
    """
    if not am.names:
        return recs

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

        # -- mtrap-t: the `T` of a STANDARD-delivery trap [R-K2b-2 (2)] --------
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

        # -- fcsr-split: one RTL `C 003` becomes the reference's two records ---
        # Measured (k0 oracle probe §1.3h): `csrw fcsr,t0` with t0=7 logs
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

        # -- cboz-stores: the 16 stores that belong to a `cbo.zero` retire ----
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
        i += 1
    return out


def _owning_retire(recs, i):
    """The `R` record whose retire group record `i` belongs to.

    RECORD_FORMAT §0 fixes the per-retire emission order as R, then every
    `M L`, then every `M S`, then every `C` -- so the owning retire is the
    nearest preceding `R` with no intervening `R`.  A `T` terminates the
    search: a trap entry is not a retire and owns nothing.
    """
    k = i - 1
    while k >= 0:
        if recs[k].kind == "R":
            return recs[k]
        if recs[k].kind == "T":
            return None
        k -= 1
    return None


# --------------------------------------------------------------------------
# the REFERENCE-side pre-pass
# --------------------------------------------------------------------------

def spike_prepass(recs, am):
    """Apply every reference-side amendment.  Returns a NEW list.

    THIS IS THE ONLY PLACE ANY AMENDMENT TOUCHES THE REFERENCE STREAM, and the
    asymmetry is deliberate: a rule here removes records the RTL is not
    expected to have, so it can only ever make the reference SMALLER, never
    invent one.  It runs after the RTL prepass and never reads the RTL stream,
    for the same reason `rtl_prepass` never reads this one -- a drop must not be
    talked into existence by the thing it is checked against.

    Note for `--count`/`--max-records`: the bound is on RTL WINDOW POSITION, so
    a reference-side drop cannot part the two numbers the way a walk-level rule
    can (the A17 acceptance defect).  Nothing here needs that machinery.
    """
    if not am.names or not am.enabled("mret-csr"):
        return recs
    out = []
    for i, r in enumerate(recs):
        if r.kind == "C" and r.f[0] in ("310", "7a5"):
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


# --------------------------------------------------------------------------
# the walk-level rule
# --------------------------------------------------------------------------

def zfinx_should_skip(am, a, b):
    """True when RTL record `a` is a marked `C 001` the reference did not emit.

    THE NARROWING, AND WHY IT IS NOT OPTIONAL.  The frozen K2b spec says
    "suppress an RTL `C 001 fflags` record ONLY when its value equals the
    running fflags state".  Measured on the pinned reference
    (`vesta_ref identity --isa rv32imac_zicsr_zfinx --priv m`), that rule alone
    is too wide:

        fdiv.s a0,a1,a2   ->  c1_fflags 0x00000010 x10 0x7fc00000
        fdiv.s a3,a1,a2   ->  c1_fflags 0x00000010 x13 0x7fc00000

    The second op raises NV again, which is ALREADY set, so the VALUE is
    unchanged and Spike logs it anyway -- its `set_fp_exceptions` writes
    whenever softfloat raised anything, not when the value moved.  A value-only
    rule would drop an RTL record the reference DOES present, manufacturing a
    divergence out of the amendment itself.  So the drop additionally requires
    that the reference is not presenting that exact record here.

    Two further narrowings, both structural rather than value-based:
      * the candidate's OWNING RETIRE must be an FP opcode.  An explicit
        `csrrw fflags` is logged by BOTH sides even when it changes nothing
        (measured: two `fsflags zero` in a row both print `c1_fflags
        0x00000000`), so keying on the value alone would suppress a record the
        reference emits;
      * an x-tainted `C 001` is never a candidate -- A5 keeps its meaning.

    This is the ONLY place any amendment consults the reference, and it can
    only ever REFUSE to drop: when the two agree the record is compared
    normally and counted in `zfinx_kept`, so the narrowing's own workload is
    visible in the summary.

    WHAT IT DOES NOT WEAKEN.  An RTL that asserts a fflags value the reference
    does not have is still caught: the drop happens, and the reference's own
    `C 001` then meets the RTL's NEXT record and diverges one record later.
    What stops being compared is exactly "the fflags value at an FP retire that
    claims no change".
    """
    if not am.enabled("zfinx-fflags") or id(a) not in am.zfinx_cand:
        return False
    if b is not None and a.key() == b.key():
        am.zfinx_kept += 1
        return False
    am.bump("zfinx-fflags", a.f[1])
    return True


# --------------------------------------------------------------------------
# reporting
# --------------------------------------------------------------------------

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
