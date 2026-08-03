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

(The K2b spec's amendments 2-4 -- `cbo.zero`/`cm.jt` M-record suppression, the
TRAPCSR C-record allowlist and the ZIHPM WARL allowlist -- land in their own
commits and extend the table above.  One amendment, one commit, one set of
default-config pins.)

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


class AmendError(Exception):
    """An amendment name the comparator does not implement."""


# name -> (config predicate as text, one-line description).  ORDER IS THE
# CANONICAL ORDER: it is what `oracle_isa --shell` emits and what the summary
# prints, so two runs of one config produce the same line.
AMENDMENTS = (
    ("zfinx-fflags", "isa.zfinx",
     "drop the RTL's unconditional FPU_DONE `C 001` when it asserts no change "
     "and the reference does not present it"),
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
    fflags = 0                 # the RTL's fflags state, tracked from the stream
    for i, r in enumerate(recs):
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

        if (r.kind == "C" and r.f[0] == "001" and am.enabled("zfinx-fflags")
                and "x" not in r.f[1]):
            owner = _owning_retire(recs, i)
            if owner is not None and is_fp_op(owner.f[1]):
                v = _word(r.f[1])
                if v is not None and (v & 0x1f) == fflags_before:
                    am.zfinx_cand.add(id(r))

        out.append(r)
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
