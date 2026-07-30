#!/usr/bin/python3.6
# -*- coding: utf-8 -*-
"""mk_inject.py — build the ORDERED MMIO replay list for `vesta_ref cosim`.

Phase V3 (kickoff §4 "MMIO load injection"). Reads an RTL trace produced by
`hdl/common/vesta/vesta_tracer.vhd` and emits one record per unmodelled-region
load, IN EMISSION ORDER:

    <addr8> <size1> <value8>          lowercase hex, no 0x

WHY ORDER AND NOT ADDRESS (the load-bearing design point, v3_design.md §2.1):
the boot window reads SPI0's status register at 0x4204 **6,140 times with four
different values**, and the control flow depends on which value comes back. An
address-keyed table cannot express that. An order-keyed list reproduces the
RTL's loop trip counts exactly, so the two instruction streams stay aligned
through a data-dependent poll loop with no model of the peripheral at all.

THE VALUE IS THE RAW BUS WORD (amendment A6). Before A6 the trace's `M L` data
field was a hardcoded zero (`vesta_tracer.vhd:449/456/458/479`); it now carries
the 32-bit word the memory interface returned. `vesta_ref` takes the addressed
lane itself (`word >> 8*(addr mod 4)`, masked to `size`), so this script passes
the word through untouched — it never pre-extracts, because the raw word is
what the RTL saw and the lane arithmetic belongs in one place.

REFUSALS — this script never fabricates a value (Fable rulings, 2026-07-30):
  * an `x` nibble anywhere in the value (amendment A5) is REFUSED by default.
    `--allow-x <ordinal>:<addr>:<value>` (repeatable) or `--allow-x-file <f>`
    overrides ONE specific record, and the substitution is PRINTED to stderr and
    to a `# allow-x` provenance line in the output. Ruling A2: refuse by
    default, allowlist only with the substitution recorded in the run log.
  * a load the tracer marked `# NODATA` (emitted outside a retire group, so its
    data could not be back-filled) is REFUSED — A6 requires the injector to
    refuse rather than inject a fabricated 0.

SECOND PRODUCT — `--bracket-out FILE` (V3 ISR-BRACKET mechanism)

Spike cannot model VestaRV's legacy vectored trap (custom `iret`, IVT dispatch,
hardware PC push), so the reference is never interrupted.  Instead the RTL's ISR
window is BRACKETED OUT of the comparison and the reference is REALIGNED across
it.  In the same single pass this script already makes over the trace it can
therefore also emit the realignment script the reference needs:

    B <retire_index> <resume_pc8>              set the reference pc here
    S <retire_index> <addr8> <size1> <data8>   write this into reference RAM here

A bracket runs from a `T` record to the `X iret` that matches it (a STACK, so a
nested trap does not close the outer bracket).  The resume PC is determined
TRACE-INTERNALLY: if the ISR stored to the very address the `# IRETPOP`
diagnostic names — the stacked-PC slot — the LAST such store is the resume PC
(REDIRECTED); otherwise it is the `T` record's `epc` (SEQUENTIAL).  That is what
keeps "`iret` reads the stacked PC back from RAM" a VERIFIED property rather
than an assumed one: `compare.py --bracket-isr` checks the same value against
the first post-`iret` retire's pc, with no help from the reference.

THE `<retire_index>` IS THE **REFERENCE** MODEL'S RETIRE COUNT, i.e. post-entry
`R` records with previously-bracketed ISR retires EXCLUDED — because that is the
counter `vesta_ref` maintains (minstret delta) and the reference never executes
an ISR.  The raw post-entry RTL retire number is carried alongside on every line
and in the provenance (`rtl_retires=`), and the two coincide for the first
bracket.  Getting this wrong is silent: the reference would realign N retires
late, where N is the number of instructions the earlier ISRs retired.

MMIO stores are NOT replayed (`--mmio`, default `0x4000:0x4000`): the device is
not modelled, and writing e.g. the CLINT `msip` clear at 0x5000 into the
reference's RAM array would fabricate memory the RTL does not have.  Every
exclusion is logged, in the file and on stderr.

The trap-entry return-PC push (the A7 `# IRQPUSH` diagnostic) IS replayed, as an
`S` at the bracket point: it is a genuine committed store whose value the
program can read back (`rv32ui-p-irqctx` does exactly that — it pre-seeds the
slot with `55aa55aa` and later loads it expecting the pushed `0000831e`), and
without it the reference's RAM diverges from the RTL's on a COMPARED `rdval`.
It is counted separately (`push=`) so the ISR store census stays exact, it never
participates in the REDIRECTED determination (the push address is by
construction the pop address, which would make every bracket look redirected),
and `--no-replay-push` turns it off for a negative control.

EXIT CODES
    0  list written
    1  usage / unreadable trace
    5  refused (x-tainted or NODATA record without an allowlist entry)

===============================================================================
V4 (multi-hart) ADDITIONS -- the four mechanisms of v4_design.md §4.1
===============================================================================

They all ride the ONE realignment script (`--bracket-out`, consumed by
`vesta_ref --bracket`), because they are all "do this to the reference state
immediately before reference retire N":

    P <retire_index> <addr8> <size1> <data8>   PLANT   (M1, amendment A13)
    G <retire_index> <rd2> <val8>              register replay (M3, A12)
    F <retire_index>                           force the next sc.w to FAIL (M4, A14)

* PLANT (`--plant BASE:SIZE|auto`).  A load whose address lies in the
  SHARED-AND-WRITABLE window is served by POKING the reference's RAM before the
  consuming retire, NOT by an MMIO callback.  Forced by spike's own semantics:
  `simif_t::reservable()` defaults to `addr_to_mem()`, so `lr.w`/`sc.w` into a
  callback hole THROWS (measured -- probe_a13_a14 P4: mcause=5, no commit), and
  LR/SC is the entire point of the multi-hart phase.  The window is DERIVED from
  the RTL (`--plant auto`, see derive_plant_window) and never hardcoded twice.
  A plant does NOT disturb an in-flight reservation (probe P3), so P and F are
  orthogonal and a plant may safely land inside an LR/SC window.

* SLEEP BRACKET.  A bracket now opens on `X <hart> <cycle> wfi_enter` as well as
  on a `T`, and the `T` the wake delivers is ABSORBED into that same bracket
  rather than nesting inside it -- because the park window has ONE exit event
  (the wake ISR's `X iret`) and therefore needs exactly one realignment point.
  This is what carries harts 1-3 across
  [EXTINGUISH .. legacy trap .. loader ISR .. IGNITE .. iret], none of which the
  reference can execute.  A bracket that never closes (a hart parked FOREVER)
  truncates the reference at the park, which is the correct behaviour, and says so.

* `G` (register replay).  The ROM loader ISR is NOT register-transparent -- the
  tile entry ABI is "sp valid, everything else undefined" -- so an S-only bracket
  lands the reference holding park-loop register values while the RTL holds
  loader leftovers.  Every committed `rd` inside the window is replayed.  Only
  the LAST write to each register is emitted (they are all applied at one point,
  so the last wins); the RAW count is kept in the census so the collapse is
  auditable.  THE CONCESSION IS EXPLICIT: the ISR's register writes become
  ASSERTED, exactly as its stores already are.

* `F` (forced SC failure).  An isolated reference's reservation is cleared only
  by its own `sc.w`, so its SC ALWAYS succeeds; the RTL's failures must be forced
  with `mmu_t::yield_load_reservation()`.
  HOW FAILURE IS DETECTED: from the retire's `rd`, and ONLY from `rd`.  See
  `_resolve_sc()` for the measurement that forces this.  An earlier draft of this
  file derived it from the PRESENCE OR ABSENCE OF AN `M … S` RECORD, on the theory
  that this would leave `rd` a compared field.  THAT ORACLE IS WRONG ON THIS RTL
  and the correction is amendment A15: a globally-failed `sc.w` STILL EMITS AN
  `M … S` record, because the core's local check passes and drives `wen` while the
  suppression happens downstream in `resv_unit` (`s_we_gated`,
  resv_unit.vhd:120-123).  Since EVERY cross-hart kill takes that path, a
  store-presence oracle would emit no `F` at all for the entire A14 population.
  CONSEQUENCE, per Fable's A14 restatement (2026-07-30): the SC's `rd` is
  ASSERTED, not compared -- comparing a value you forced is not comparison.  The
  compared set for an SC is its ADDRESS, the CONSISTENCY of store-presence with
  the asserted outcome, and its DOWNSTREAM effects (what later loads read back).
  Still NOT checked either way: whether the RTL's SC *should* have failed
  (`resv_unit`'s adjudication is taken as true).

* THE INJECT PARTITION (A13, the V3-declared V4 prerequisite).  A load inside a
  bracketed window is DROPPED from the mainline replay list instead of being
  emitted into it: the reference never executes the interior, so it never asks
  for those values, and the interior's memory effects reach it through the S/G
  replay instead.  V3 emitted them and warned (`vesta_ref` then exited 7
  INJECT-MISMATCH).  Every drop is counted and annotated (`# BRACKET n DROPPED …`
  plus a per-bracket census), so A5's "never silently skipped" survives.
"""

import argparse
import os
import re
import sys

EXIT_OK, EXIT_USAGE, EXIT_REFUSED = 0, 1, 5

# How many `# BRACKET n DROPPED …` lines to write verbatim per bracket before
# summarising the rest. The loader ISR drops 4,096 image words; listing every one
# would bury the census that carries the actual information. The census counts
# stay EXACT and the truncation says so on its own line.
DROP_LIST_CAP = 16

# sc.w: funct5=00011, funct3=010, opcode=0101111. aq/rl (bits 26:25) are
# deliberately OUTSIDE the mask -- sc.w.aq/.rl are the same instruction.
SC_W_MASK, SC_W_MATCH = 0xf800707f, 0x1800202f


def parse_window(text):
    """'0x4000:0x4000' -> (base, size)."""
    try:
        b, s = text.split(":")
        return int(b, 16), int(s, 16)
    except Exception:
        raise ValueError("window %r is not <basehex>:<sizehex>" % text)


def _vhdl_natural(path, name, decl="constant"):
    """`<decl> <name> : natural := <n>;` -> int, or None.

    `decl` is "constant" for a package/architecture constant and "" for a
    GENERIC default (the declaration syntax is otherwise identical). Accepts a
    decimal or a 16#..# literal, which is how the generator writes some of them.
    """
    lead = (re.escape(decl) + r'\s+') if decl else r'^\s*'
    pat = re.compile(lead + re.escape(name) +
                     r'\s*:\s*natural\s*:=\s*([0-9_]+|16#[0-9a-fA-F_]+#)\s*[;)]')
    try:
        with open(path) as fh:
            for line in fh:
                m = pat.search(line)
                if m:
                    tok = m.group(1).replace("_", "")
                    if tok.startswith("16#"):
                        return int(tok[3:-1], 16)
                    return int(tok, 10)
    except IOError:
        return None
    return None


def derive_plant_window(root):
    """(base, size) of the SHARED-AND-WRITABLE window, DERIVED from the RTL.

    v4_design.md §4.3 requires this to be computed from the same constants the
    images are built from, never hardcoded twice -- the Argus (N=18) shape moves
    the addresses, and a stale literal here would silently plant nothing.

      base = RamStartAddress + RamSize        (MemoryMap.vhd) -- the top of the
             PRIVATE TCM. The shared window resumes immediately above it: the
             master-side decode excludes exactly the TCM slice
             (`addr(16:14) /= "010"`, CLAUDE.md / hart_tile.vhd:59).
      top  = 2 ** (SH_AW + 2)                 (MCU.vhd's `constant SH_AW`, the
             AUTHORITATIVE value -- it is what MCU passes down to every
             hart_tile and to mp_arbiter). `sh_sel` qualifies on
             `addr(31:SH_AW+2) = 0` (hart_tile.vhd:654) and adddec.vhd:418
             states the flash boundary is its strict complement, so the shared
             address space is exactly [0, 2**(SH_AW+2)).
             hart_tile.vhd's GENERIC DEFAULT is read as a cross-check and a
             disagreement is fatal: a silently-diverged default is exactly how a
             mis-derived window would go unnoticed.

    Everything below `base` is either the shared boot ROM (read-only, identical
    for every hart, already modelled via --rom) or the shared peripheral window
    (already served by the --mmio callback replay), so the complement is exactly
    "shared and writable" = NPU staging RAM + shared bulk RAM.
    """
    mm = os.path.join(root, "MemoryMap.vhd")
    mcu = os.path.join(root, "MCU.vhd")
    ht = os.path.join(root, "hart_tile.vhd")
    ram_start = _vhdl_natural(mm, "RamStartAddress")
    ram_size = _vhdl_natural(mm, "RamSize")
    sh_aw = _vhdl_natural(mcu, "SH_AW")
    sh_aw_tile = _vhdl_natural(ht, "SH_AW", decl="")
    missing = [n for n, v in (("RamStartAddress", ram_start), ("RamSize", ram_size),
                              ("SH_AW (MCU.vhd)", sh_aw)) if v is None]
    if missing:
        raise ValueError("--plant auto: cannot derive %s from %s / %s"
                         % (", ".join(missing), mm, mcu))
    if sh_aw_tile is not None and sh_aw_tile != sh_aw:
        raise ValueError("--plant auto: SH_AW disagrees between MCU.vhd (%d) and "
                         "hart_tile.vhd's generic default (%d) -- refusing to "
                         "guess which one the build used"
                         % (sh_aw, sh_aw_tile))
    base = ram_start + ram_size
    top = 1 << (sh_aw + 2)
    if top <= base:
        raise ValueError("--plant auto: derived window is empty "
                         "(base=0x%x top=0x%x from RamStartAddress=%d RamSize=%d "
                         "SH_AW=%d)" % (base, top, ram_start, ram_size, sh_aw))
    return base, top - base, ("derived: RamStartAddress=%d RamSize=%d SH_AW=%d" %
                              (ram_start, ram_size, sh_aw))


def load_allow(items, path, budget=None):
    """-> {(ordinal, addr_lower): value_str}; fills `budget[addr]` with the
    BOUNDED number of wildcard applications permitted at that address."""
    out = {}
    if budget is None:
        budget = {}
    raw = list(items or [])
    if path:
        with open(path) as fh:
            for line in fh:
                line = line.split("#", 1)[0].strip()
                if line:
                    raw.append(line)
    used = set()
    for spec in raw:
        parts = spec.split(":")
        if len(parts) != 3:
            raise ValueError("--allow-x %r is not <ordinal>:<addr>:<value>" % spec)
        # Ordinal forms:
        #   <n>   exactly the n-th MMIO load (pins one occurrence)
        #   *     the FIRST x-tainted record at this address
        #   *<N>  the first N x-tainted records at this address
        # The bare ordinal is a derived artifact of how many MMIO loads precede
        # it (it shifts if the boot ROM changes), whereas (address, occurrence
        # count) is the semantically meaningful identity. The COUNT IS ALWAYS
        # BOUNDED AND EXPLICIT -- there is deliberately no "unbounded" form, so
        # occurrence N+1 is still refused and the allowlist stays an auditable
        # claim about a known number of undriven reads (ruling A2). Every
        # resolved ordinal is printed and stamped into the output provenance.
        tok = parts[0].strip()
        if tok == "*":
            ordn, wild_n = None, 1
        elif tok.startswith("*"):
            ordn, wild_n = None, int(tok[1:], 0)
            if wild_n < 1:
                raise ValueError("--allow-x %r: count must be >= 1" % spec)
        else:
            ordn, wild_n = int(tok, 0), 0
        addr = parts[1].lower().lstrip("0x").rjust(8, "0")
        val = parts[2].lower().lstrip("0x").rjust(8, "0")
        if len(val) != 8 or any(c not in "0123456789abcdef" for c in val):
            raise ValueError("--allow-x %r substitution is not 8 hex digits" % spec)
        out[(ordn, addr)] = val
        if ordn is None:
            budget[addr] = budget.get(addr, 0) + wild_n
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Build the ordered MMIO replay list for vesta_ref cosim.")
    ap.add_argument("--rtl", required=True, metavar="TRACE",
                    help="RTL trace from vesta_tracer (…_h00.trace)")
    ap.add_argument("-o", "--out", required=True, metavar="FILE")
    ap.add_argument("--mmio", default="0x4000:0x4000", metavar="BASE:SIZE",
                    help="unmodelled window, hex (default 0x4000:0x4000)")
    ap.add_argument("--entry", metavar="HEXPC", default=None,
                    help="entry-aligned mode: skip everything before the first "
                         "R record at this pc (mirrors compare.py align_entry). "
                         "Omit for a bootrom-inclusive run.")
    ap.add_argument("--allow-x", action="append", metavar="ORD:ADDR:VAL",
                    help="permit one x-tainted record, substituting VAL (A2)")
    ap.add_argument("--allow-x-file", metavar="FILE")
    ap.add_argument("--bracket-out", metavar="FILE", default=None,
                    help="also write the ISR-bracket realignment script for "
                         "`vesta_ref --bracket` (V3 ISR-BRACKET mechanism)")
    ap.add_argument("--no-replay-push", action="store_true",
                    help="do NOT replay the A7 trap-entry return-PC push into "
                         "reference RAM (negative control; the default replays "
                         "it, see the module docstring)")
    # ---- V4 ---------------------------------------------------------------
    ap.add_argument("--plant", metavar="BASE:SIZE|auto", default=None,
                    help="V4/A13: serve loads in this SHARED-AND-WRITABLE window "
                         "by POKING reference RAM (P records in --bracket-out) "
                         "instead of by MMIO callback. 'auto' DERIVES it from "
                         "MemoryMap.vhd + adddec.vhd (see --hdl-root). Requires "
                         "--bracket-out. Omit to disable (V3 behaviour).")
    ap.add_argument("--hdl-root", metavar="DIR",
                    default=os.path.expanduser("~/vestarv/hdl/common"),
                    help="where MemoryMap.vhd / adddec.vhd live, for --plant auto")
    ap.add_argument("--no-sleep-bracket", action="store_true",
                    help="V4 negative control: do NOT let 'X <hart> <cyc> "
                         "wfi_enter' open a bracket (V3 behaviour: only T does)")
    ap.add_argument("--no-reg-replay", action="store_true",
                    help="V4/A12 negative control: emit no G records, so the "
                         "bracket replays stores but not the ISR's register writes")
    ap.add_argument("--no-force-sc", action="store_true",
                    help="V4/A14 negative control: emit no F records, so the "
                         "reference's sc.w always succeeds")
    ap.add_argument("--drop-plant", metavar="N", type=int, default=None,
                    help="V4 NEGATIVE CONTROL (mandatory Stage-2 gate): omit the "
                         "Nth (0-based) emitted P record. A missing plant lets "
                         "the reference read STALE RAM, which is the phase's "
                         "central soundness risk -- this is how it is proven "
                         "detectable. Loudly stamped into the output and stderr.")
    a = ap.parse_args(argv)

    try:
        base, size = parse_window(a.mmio)
        budget = {}
        allow = load_allow(a.allow_x, a.allow_x_file, budget)
    except ValueError as e:
        sys.stderr.write("mk_inject: %s\n" % e)
        return EXIT_USAGE

    # ---- V4: the plant window --------------------------------------------
    pbase = psize = None
    pderiv = "-"
    if a.plant is not None:
        try:
            if a.plant == "auto":
                pbase, psize, pderiv = derive_plant_window(a.hdl_root)
            else:
                pbase, psize = parse_window(a.plant)
                pderiv = "explicit"
        except ValueError as e:
            sys.stderr.write("mk_inject: %s\n" % e)
            return EXIT_USAGE
        if a.bracket_out is None:
            sys.stderr.write("mk_inject: --plant requires --bracket-out (the P "
                             "records are carried by the realignment script)\n")
            return EXIT_USAGE
        # The two windows must be DISJOINT or a load has two possible services
        # and which one wins would be an accident of code order.
        if not (pbase >= base + size or pbase + psize <= base):
            sys.stderr.write("mk_inject: --plant %08x:%08x OVERLAPS --mmio "
                             "%08x:%08x; a load cannot be both callback-served "
                             "and planted\n" % (pbase, psize, base, size))
            return EXIT_USAGE
        sys.stderr.write("mk_inject: plant window %08x..%08x (%s)\n"
                         % (pbase, pbase + psize - 1, pderiv))
    entry = int(a.entry, 16) if a.entry else None

    try:
        lines = open(a.rtl).read().splitlines()
    except IOError as e:
        sys.stderr.write("mk_inject: cannot read %s: %s\n" % (a.rtl, e))
        return EXIT_USAGE

    recs = []           # (addr, size, value) in emission order
    notes = []          # provenance lines for the output header
    applied = {}        # (addr, observed, substituted) -> [first_ordinal, count]
    started = entry is None
    wild_used = {}         # addr -> how many wildcard applications were spent
    pending = None      # index into recs of the L emitted on the previous line
    pending_plant = None   # index into `plants` of the P emitted on the previous line
    n_seen = n_skipped_pre = 0

    # -- ISR-BRACKET state (only used when --bracket-out is given) ----------
    # `n_retire`     = raw post-entry R records seen (the RTL retire number).
    # `n_ref_retire` = the same count with bracketed ISR retires EXCLUDED, i.e.
    #                  the REFERENCE model's retire count, which is what the
    #                  emitted <retire_index> must be (see the docstring).
    brackets = []       # finalised outermost brackets, in order
    n_retire = n_ref_retire = 0
    depth = 0           # bracket nesting depth (a STACK, not a flag)
    cur = None          # the OUTERMOST bracket in flight
    last_push = None    # (addr, size, data) from an immediately preceding IRQPUSH
    last_pop = None     # addr from an immediately preceding IRETPOP
    diag_bad = []       # IRQPUSHBAD / IRETPOPBAD sightings, surfaced verbatim

    # -- V4 state -----------------------------------------------------------
    plants = []         # (ref_index, addr, size, val, rtl_retire) at depth 0
    plant_pre = 0       # plant-window loads skipped before --entry
    sc_fails = []       # ref_index of every sc.w the RTL FAILED
    sc_pend = None      # {"ref","rtl","ln","rd","rdval","depth","store","scfailrd"}
    n_sc = 0
    n_sc_interior = 0   # sc.w retires INSIDE a bracket (no F: not compared)
    n_sc_ghost = 0      # interior ghost stores withheld from the S replay
    sc_inconsistent = []   # (ln, why) -- rd vs store / `# SCFAILRD` disagreements
    sc_indeterminate = []  # (ln, why) -- rd unusable as the oracle (x / x0)
    sc_shape = {"ext": 0, "local": 0}   # counted failure shapes, not warnings
    last_scfailrd = 0   # `# SCFAILRD` lines seen since the last record line

    def _new_bracket(ln_, kind, push_, tfields=None):
        """A bracket opened either by a legacy `T` (V3) or by `X … wfi_enter`
        (V4/A11). A SLEEP bracket has no T fields yet -- the wake trap fills
        them in when it is ABSORBED (see the `T` arm)."""
        b = {
            "line": ln_, "kind": kind,
            "cause": "-", "epc": "-", "ivt": "-", "priv": "-",
            "rtl_start": n_retire, "ref_index": n_ref_retire,
            "push": push_, "pop": None, "stores": [],
            "regs": {}, "nreg_raw": 0,          # V4/A12 -- G
            "nested": 0, "mmio_loads": 0, "plant_loads": 0,
            "dropped": [],                      # verbatim `DROPPED` annotations
            "absorbed": False,                   # a SLEEP that has taken its trap
            "rtl_end": None, "wake": 0,
        }
        if tfields is not None:
            b["cause"], b["epc"], b["ivt"], b["priv"] = tfields
        return b

    def _resolve_sc():
        """Decide the pending sc.w's verdict FROM `rd`, and cross-check it.

        THE ORACLE IS `rd` (0 = success, 1 = failure -- the architectural result
        the instruction writes), NOT the presence of an `M … S` record. MEASURED,
        on all six sc.w retires of `shlrsc` hart 0, and it is decisive:

          a GLOBALLY-failed SC STILL EMITS AN `M … S` RECORD.

        The core's LOCAL check (`reservation_valid` + address match) passes, so it
        drives `wen` and the tracer -- which samples the core's PORT, per
        invariant 7 -- records the presentation. The write is then suppressed
        DOWNSTREAM, by `resv_unit`'s `s_we_gated` (resv_unit.vhd:120-123), and
        only `sc_fail_ext` comes back to the core, which reports `rd`=1. Proof
        that nothing committed: shlrsc case 5's readback two retires later reads
        the OLD word (`M L 0001000c 4 0000115c` right after
        `M S 0001000c 4 000015b3`).
        Every CROSS-HART kill is on that path (a foreign write clears
        `resv_unit`'s table entry, never the core's own copy), so a
        store-presence oracle would emit NO `F` for the entire A14 population --
        ~29,000 per hart in `shcount` -- and the reference's SC would succeed
        against an RTL failure at every one of them.

        `# SCFAILRD` (A3) is a witness for the LOCALLY-failed SUBSET only: it is
        a read issued in `SC_CHECK`, which happens only when the core itself
        declines to write. So its ABSENCE is not evidence of success and is not
        reported; its PRESENCE on an `rd`=0 SC is a genuine disagreement and is.
        """
        if sc_pend is None:
            return
        s = sc_pend
        if s["depth"] > 0:
            # An interior sc.w is not in the compared stream (the reference does
            # not execute the bracket), so it gets no F. Its ghost store is
            # handled where stores are collected.
            return
        if "x" in s["rdval"] or s["rd"] == "00":
            # rd is the oracle and it is unreadable here: either x-tainted (A5 --
            # the record is already an INVESTIGATE for the comparator) or written
            # to x0, which both sides suppress (§1), leaving no result at all.
            # `# SCFAILRD` is the only remaining witness, and it only sees LOCAL
            # failures -- so fall back to it and say the coverage is partial
            # rather than guess. Never fabricate a verdict.
            if s["scfailrd"]:
                if not a.no_force_sc:
                    sc_fails.append(s["ref"])
                sc_indeterminate.append(
                    (s["ln"], "rd=%s rdval=%s is unusable as the SC oracle; "
                              "FORCED FAIL on the '# SCFAILRD' witness alone"
                              % (s["rd"], s["rdval"])))
            else:
                sc_indeterminate.append(
                    (s["ln"], "rd=%s rdval=%s is unusable as the SC oracle and "
                              "there is no '# SCFAILRD' witness: NO F emitted. "
                              "If this SC failed, the reference will succeed and "
                              "diverge on rd -- which is the loud outcome, not a "
                              "silent one" % (s["rd"], s["rdval"])))
            return
        failed = (s["rdval"] != "00000000")
        if failed and not a.no_force_sc:
            sc_fails.append(s["ref"])
        # ---- cross-checks. Reported; NEVER used to override `rd`. ----------
        if (not failed) and s["scfailrd"]:
            sc_inconsistent.append(
                (s["ln"], "sc.w reports SUCCESS (rd=00000000) but the tracer "
                          "emitted %d '# SCFAILRD' diagnostic(s) -- the core "
                          "declined to write yet claims success. This is the M4b "
                          "'premature/absent write' bug SHAPE" % s["scfailrd"]))
        if (not failed) and not s["store"]:
            sc_inconsistent.append(
                (s["ln"], "sc.w reports SUCCESS (rd=00000000) but emitted NO "
                          "store -- the M4b 'success without a write' bug SHAPE"))
        if failed and s["store"]:
            # The sc_fail_ext signature, and the COMMON case (every cross-hart
            # kill). Counted, not warned: at ~29,000 per hart a line each would
            # bury the log, and the write's suppression is downstream of the port
            # the tracer samples, so this is the expected shape, not a finding.
            sc_shape["ext"] += 1
        if failed and s["scfailrd"]:
            sc_shape["local"] += 1

    for ln, raw in enumerate(lines, 1):
        f = raw.split()
        if not f:
            continue

        # A NODATA diagnostic refers to the L record on the PREVIOUS line.
        if raw[0] == "#":
            if len(f) >= 3 and f[1] == "NODATA" and pending is not None:
                addr, sz, val = recs[pending]
                sys.stderr.write(
                    "mk_inject: REFUSED ordinal %d addr=%s: tracer marked it "
                    "# NODATA (load outside a retire group -- its data could "
                    "not be back-filled; A6 forbids injecting a fabricated 0)\n"
                    % (pending, addr))
                return EXIT_REFUSED
            if len(f) >= 3 and f[1] == "NODATA" and pending_plant is not None:
                # Same rule for a PLANT: A6 forbids handing the reference a
                # fabricated 0, and a plant is a load service like any other.
                sys.stderr.write(
                    "mk_inject: REFUSED plant %d addr=%s: tracer marked it "
                    "# NODATA -- A6 forbids planting a fabricated 0\n"
                    % (pending_plant, plants[pending_plant][1]))
                return EXIT_REFUSED
            # Amendment A7: the two trap-path memory events are diagnostics, not
            # records.  They are read from the RAW TEXT and bound to the record
            # that FOLLOWS them (only comment lines ever intervene), which is
            # why `last_push`/`last_pop` are cleared at every record line below.
            if len(f) >= 3 and f[1] == "IRQPUSH" and len(f) == 7:
                last_push = (f[4].lower(), f[5].lower(), f[6].lower())
            elif len(f) >= 3 and f[1] == "IRETPOP" and len(f) == 5:
                last_pop = f[4].lower()
            elif len(f) >= 2 and f[1] in ("IRQPUSHBAD", "IRETPOPBAD"):
                diag_bad.append((ln, raw.strip()))
            elif len(f) >= 2 and f[1] == "SCFAILRD":
                # A3: the failed-SC bus re-presentation. It BINDS FORWARD, like
                # IRQPUSH/IRETPOP: `emit` writes it at the SC_CHECK edge, i.e.
                # BEFORE the retire group is flushed, so in the file it PRECEDES
                # the sc.w's own `R` line (measured, shlrsc hart 0:
                # `# SCFAILRD 00 0003cd6a 0001000c` on the line above
                # `R 00 0003cd6a 000082f8 19c2aeaf 1d 00000001`). Binding it
                # backwards -- to the sc.w it follows -- never sees a witness at
                # all and reports a false absence on every locally-failed SC.
                last_scfailrd += 1
            continue
        # A diagnostic binds only to the record on the very next record line.
        push_here, pop_here = last_push, last_pop
        scfailrd_here = last_scfailrd
        last_push = last_pop = None
        last_scfailrd = 0
        pending = None
        pending_plant = None

        if f[0] == "R":
            if not started:
                if entry is not None and int(f[3], 16) == entry:
                    started = True
                else:
                    continue
            # An sc.w's fate is decided by whether an `M … S` followed it, so
            # the verdict is taken at the NEXT record-bearing line.
            _resolve_sc(); sc_pend = None
            n_retire += 1
            # ---- V4/A14: is this retire an sc.w? ------------------------------
            # Decoded PROPERLY -- opcode/funct3/funct5, never a string pattern:
            # `sc.w` is funct5=00011 funct3=010 opcode=0101111, with aq/rl
            # (bits 26:25) masked OUT because sc.w.aq/.rl are the same
            # instruction. This is also decoded for a BRACKET-INTERIOR sc.w,
            # which gets no F (it is not in the compared stream) but whose ghost
            # store must be kept out of the S replay.
            try:
                insn = int(f[4], 16)
            except (ValueError, IndexError):
                insn = None
            is_scw = (insn is not None and len(f[4]) == 8
                      and (insn & SC_W_MASK) == SC_W_MATCH)
            if depth == 0:
                n_ref_retire += 1
                if is_scw:
                    n_sc += 1
            elif is_scw:
                n_sc_interior += 1
            if is_scw and len(f) >= 7:
                sc_pend = {"ref": n_ref_retire - 1, "rtl": n_retire,
                           "ln": ln, "rd": f[5].lower(), "depth": depth,
                           "rdval": f[6].lower(), "store": False,
                           "scfailrd": scfailrd_here}
            if depth > 0:
                # ---- V4/A12: the ISR's committed register writes ---------
                # rd == "00" is x0, i.e. no architectural write.
                if len(f) >= 7 and f[5].lower() != "00":
                    if "x" in f[6].lower():
                        sys.stderr.write(
                            "mk_inject: REFUSED line %d: x-tainted rdval %s "
                            "inside a bracket (amendment A5). The reference's "
                            "register file must not be handed an invented "
                            "value.\n" % (ln, f[6]))
                        return EXIT_REFUSED
                    cur["nreg_raw"] += 1
                    # LAST write per register wins: every G at one bracket point
                    # is applied together, so only the final value is visible.
                    cur["regs"][f[5].lower()] = f[6].lower()
            continue

        if not started:
            # Pre-entry T/X records cannot open a bracket in the compared
            # window; pre-entry loads keep their existing skip accounting below.
            if f[0] in ("T", "X"):
                continue

        if f[0] == "T":
            _resolve_sc(); sc_pend = None
            tf = (f[3].lower(), f[4].lower(), f[5].lower(), f[6].lower())
            if depth == 0:
                cur = _new_bracket(ln, "TRAP", push_here, tf)
                depth += 1
            elif cur["kind"] == "SLEEP" and not cur["absorbed"]:
                # V4/A11: the wake trap of a park window is ABSORBED, not nested.
                # The park has ONE exit event (the wake ISR's `X iret`), so it
                # needs exactly ONE realignment point; pushing depth here would
                # leave the sleep bracket permanently open once that iret fired.
                cur["absorbed"] = True
                cur["cause"], cur["epc"], cur["ivt"], cur["priv"] = tf
                if cur["push"] is None:
                    cur["push"] = push_here
            else:
                cur["nested"] += 1
                depth += 1
            continue

        if f[0] == "X":
            kind = f[3] if len(f) >= 4 else ""
            if kind == "wfi_enter" and not a.no_sleep_bracket:
                _resolve_sc(); sc_pend = None
                if depth == 0:
                    # A11: the park window opens HERE, one retire before the
                    # EXTINGUISH the reference cannot execute.
                    cur = _new_bracket(ln, "SLEEP", None)
                    depth += 1
                else:
                    cur["nested"] += 1
                    depth += 1
                continue
            if kind == "wfi_wake" and depth > 0:
                cur["wake"] += 1
                continue
            if kind == "iret" and depth > 0:
                _resolve_sc(); sc_pend = None
                depth -= 1
                if depth == 0:
                    cur["pop"] = pop_here
                    cur["rtl_end"] = n_retire
                    brackets.append(cur)
                    cur = None
            continue

        if f[0] != "M" or len(f) < 7:
            continue
        if f[3] == "S":
            if sc_pend is not None:
                sc_pend["store"] = True
            # Every committed store inside the ISR window is a candidate for
            # replay into the reference's RAM.  Stores OUTSIDE a window are the
            # reference's own business -- it executes those instructions itself.
            if depth > 0 and started:
                if (sc_pend is not None and sc_pend["depth"] > 0
                        and "x" not in sc_pend["rdval"]
                        and sc_pend["rdval"] != "00000000"):
                    # A GHOST STORE: a globally-failed sc.w presents `wen` at the
                    # core port but `resv_unit`'s `s_we_gated` suppresses the
                    # write, so this word NEVER reached memory (see _resolve_sc).
                    # Replaying it would poke the reference's RAM with a value the
                    # RTL does not hold -- the one thing the S replay must never
                    # do. Withheld and counted.
                    n_sc_ghost += 1
                else:
                    cur["stores"].append((f[4].lower(), f[5].lower(),
                                          f[6].lower()))
            continue
        if f[3] != "L":
            continue

        addr_s, size_s, val_s = f[4].lower(), f[5].lower(), f[6].lower()
        try:
            addr = int(addr_s, 16)
        except ValueError:
            # an x in the ADDRESS is unrecoverable, full stop
            sys.stderr.write("mk_inject: REFUSED line %d: x-tainted load "
                             "ADDRESS %s\n" % (ln, addr_s))
            return EXIT_REFUSED

        # ---- V4/A13: the PLANT window ------------------------------------
        if pbase is not None and pbase <= addr < pbase + psize:
            if not started:
                plant_pre += 1
                continue
            if depth > 0:
                # THE INJECT PARTITION: the reference never executes the
                # interior, so it never asks for this value -- and the
                # interior's memory effects reach it through the S replay
                # instead. Dropped, counted, and annotated.
                cur["plant_loads"] += 1
                if len(cur["dropped"]) < DROP_LIST_CAP:
                    cur["dropped"].append("L %s %s %s   (plant window)"
                                          % (addr_s, size_s, val_s))
                continue
            if "x" in val_s:
                sys.stderr.write(
                    "mk_inject: REFUSED plant at line %d addr=%s value=%s: "
                    "x-tainted (amendment A5). A plant is a load service; the "
                    "reference must not be handed an invented bit.\n"
                    % (ln, addr_s, val_s))
                return EXIT_REFUSED
            # The plant lands immediately BEFORE the retire that consumes it.
            # That retire is the R this M belongs to (RECORD_FORMAT §0: R then
            # its M), i.e. reference retire n_ref_retire-1.
            pending_plant = len(plants)
            plants.append((n_ref_retire - 1, addr_s, size_s, val_s, n_retire))
            continue

        if not (base <= addr < base + size):
            continue
        if not started:
            n_skipped_pre += 1
            continue
        if depth > 0:
            # V4/A13, THE INJECT PARTITION -- this is V3's structural hole, and
            # the fix is a DROP, not a deferral. V3 emitted the record and warned
            # (the reference then died with exit 7 INJECT-MISMATCH, because it
            # never executes the ISR and so never pops the entry). The interior's
            # effects arrive via the S/G replay; an interior load has no consumer
            # and must not occupy an ordinal in the mainline stream.
            cur["mmio_loads"] += 1
            if len(cur["dropped"]) < DROP_LIST_CAP:
                cur["dropped"].append("L %s %s %s   (mmio window)"
                                      % (addr_s, size_s, val_s))
            continue

        ordn = len(recs)
        if "x" in val_s:
            sub = allow.get((ordn, addr_s))
            if sub is None and (None, addr_s) in allow and budget.get(addr_s, 0) > 0:
                sub = allow[(None, addr_s)]
                budget[addr_s] -= 1
                wild_used[addr_s] = wild_used.get(addr_s, 0) + 1
            if sub is None:
                sys.stderr.write(
                    "mk_inject: REFUSED ordinal %d addr=%s value=%s: x-tainted "
                    "(amendment A5). The reference model must not be handed an "
                    "invented bit.\n  To override THIS record explicitly:\n"
                    "    --allow-x %d:%s:<8hex>\n"
                    % (ordn, addr_s, val_s, ordn, addr_s))
                return EXIT_REFUSED
            # One line per (addr, observed, substituted) TRIPLE, not per record:
            # a 514-iteration poll loop would otherwise bury the log in
            # identical lines. The COUNT is what makes drift visible, and it is
            # printed once at the end (and stamped into the output provenance).
            k = (addr_s, val_s, sub)
            if k not in applied:
                applied[k] = [ordn, 0]
            applied[k][1] += 1
            val_s = sub
        recs.append((addr_s, size_s, val_s))
        pending = ordn
        n_seen += 1

    # The last retire of a truncated tile stream can BE the sc.w, so the pending
    # verdict must also be taken at end-of-file.
    _resolve_sc(); sc_pend = None

    # The A2 census: one line per distinct substitution, with its COUNT, both
    # to stderr (the run log) and stamped into the output's provenance header.
    for (addr_s, obs, sub) in sorted(applied):
        first, cnt = applied[(addr_s, obs, sub)]
        line = ("# allow-x addr=%s observed=%s substituted=%s applied=%d "
                "first_ordinal=%d" % (addr_s, obs, sub, cnt, first))
        notes.append(line)
        sys.stderr.write("mk_inject: ALLOW-X addr=%s observed=%s substituted=%s "
                         "applied=%d (first ordinal %d) (A2 allowlist)\n"
                         % (addr_s, obs, sub, cnt, first))

    n_drop_mmio = sum(b["mmio_loads"] for b in brackets) + \
        (cur["mmio_loads"] if cur is not None else 0)
    n_drop_plant = sum(b["plant_loads"] for b in brackets) + \
        (cur["plant_loads"] if cur is not None else 0)

    with open(a.out, "w") as fh:
        fh.write("# mk_inject.py ordered MMIO replay list (V3, amendment A6)\n")
        fh.write("# rtl=%s mmio=%s entry=%s records=%d\n"
                 % (a.rtl, a.mmio, a.entry or "none", len(recs)))
        if n_drop_mmio:
            # A13's partition, visible from the INJECT side too: an operator
            # reading only this file must still see that entries were withheld.
            fh.write("# V4/A13 inject partition: %d bracket-interior MMIO load(s) "
                     "DROPPED, not listed here. Per-bracket census in the "
                     "--bracket-out file.\n" % n_drop_mmio)
        for n in notes:
            fh.write(n + "\n")
        for addr_s, size_s, val_s in recs:
            fh.write("%s %s %s\n" % (addr_s, size_s, val_s))

    sys.stderr.write("mk_inject: %d record(s) -> %s%s\n"
                     % (len(recs), a.out,
                        "" if entry is None else
                        " (%d pre-entry MMIO load(s) skipped)" % n_skipped_pre))
    # THE REFERENCE-SIDE RETIRE BUDGET. The runner needs this to bound
    # --instructions: the reference executes n_ref_retire retires, NOT the RTL's
    # raw retire count (which includes every bracketed ISR retire). Printed in a
    # single machine-greppable form on purpose.
    sys.stderr.write("mk_inject: ref_retires=%d rtl_retires=%d brackets=%d "
                     "plants=%d scfail=%d/%d dropped_mmio=%d dropped_plant=%d\n"
                     % (n_ref_retire, n_retire, len(brackets), len(plants),
                        len(sc_fails), n_sc, n_drop_mmio, n_drop_plant))
    # The A14 census. `ext`/`local` are the two FAILURE SHAPES, counted rather
    # than warned (a cross-hart test produces tens of thousands of the `ext`
    # kind): `ext` = rd says fail AND a store was presented = the write was
    # suppressed downstream in resv_unit; `local` = rd says fail AND a
    # `# SCFAILRD` witness = the core itself declined to write. They are the two
    # halves of the RTL's SC failure path and their sum should equal `scfail`
    # unless an SC failed with neither witness, which is itself worth seeing.
    if n_sc or n_sc_interior:
        sys.stderr.write("mk_inject: sc.w census: %d compared, %d interior "
                         "(no F), forced=%d [ext-shape=%d local-shape=%d], "
                         "ghost store(s) withheld from the S replay=%d\n"
                         % (n_sc, n_sc_interior, len(sc_fails),
                            sc_shape["ext"], sc_shape["local"], n_sc_ghost))
    for lnn, why in sc_inconsistent:
        sys.stderr.write("mk_inject: WARNING sc.w at trace line %d: %s\n" % (lnn, why))
    for lnn, why in sc_indeterminate:
        sys.stderr.write("mk_inject: WARNING sc.w at trace line %d: %s\n" % (lnn, why))

    if a.bracket_out is not None:
        rc = write_brackets(a, brackets, depth, cur, diag_bad, base, size,
                            plants, sc_fails, n_sc, n_ref_retire, n_retire,
                            pbase, psize, pderiv, plant_pre,
                            sc_inconsistent + sc_indeterminate)
        if rc != EXIT_OK:
            return rc
    elif plants or sc_fails:
        sys.stderr.write("mk_inject: WARNING %d plant(s) and %d forced-SC "
                         "record(s) were computed but DISCARDED: no "
                         "--bracket-out was given\n" % (len(plants), len(sc_fails)))
    return EXIT_OK


def _tainted(*toks):
    """True if any token carries an amendment-A5 `x` nibble."""
    return any(t is not None and "x" in t for t in toks)


def write_brackets(a, brackets, depth, cur, diag_bad, base, size,
                   plants=(), sc_fails=(), n_sc=0, n_ref_retire=0, n_retire=0,
                   pbase=None, psize=None, pderiv="-", plant_pre=0,
                   sc_inconsistent=()):
    """Emit the `vesta_ref --bracket` realignment script.

    V3: one `B` per bracket carrying the TRACE-INTERNALLY determined resume PC,
    and one `S` per replayed store.  V4 adds, into the same script because they
    are all "do this immediately before reference retire N":

        P  the shared-window plants        (A13, --plant)
        G  the ISR's register writes       (A12, one per register, last-write)
        F  forced sc.w failure             (A14)

    Every decision is stamped into a `# bracket N` provenance line and echoed to
    stderr: the point of the mechanism is that the realignment is auditable, not
    that it is invisible.

    THE FILE MUST BE SORTED BY RETIRE INDEX, ASCENDING.  `vesta_ref`'s
    `load_bracket_list` REJECTS the whole script otherwise ("retire indices are
    not in ascending order") because its applier is single-pass -- so the
    brackets, the plants and the forced-SC records cannot be written as three
    separate blocks: a `B`/`S`/`G` set at retire 11 and an `F` at retire 171320
    interleave with plants at every index in between.  Every line is therefore
    emitted through `_emit(index, prio, text)` and the whole file is sorted at the
    end on `(index, prio)` with a STABLE sort, so records keep their trace order
    within one bucket.  `prio` mirrors the normative A11-A14 application order
    (`S`+`P` -> `G` -> `F` -> `B`); within one index vesta_ref buckets by tag and
    applies that order itself, so the priority is for the human reader, while the
    ASCENDING INDEX is a hard requirement of the consumer.
    """
    P_COMMENT, P_STORE, P_PLANT, P_REG, P_SCFAIL, P_PC = -1, 0, 1, 2, 3, 4
    entries = []                      # (index, prio, seq, text)

    def _emit(idx, prio, text):
        entries.append((idx, prio, len(entries), text))

    n_S = 0
    for i, b in enumerate(brackets):
        pop = b["pop"]
        hits = [s for s in b["stores"] if pop is not None and s[0] == pop]
        if hits:
            # The LAST store to the stacked-PC slot before the pop wins: the ISR
            # overwrote the return address, so `iret` resumes somewhere else.
            expected, case = hits[-1][2], "REDIRECTED"
        else:
            expected, case = b["epc"], "SEQUENTIAL"

        if _tainted(expected):
            sys.stderr.write(
                "mk_inject: REFUSED bracket %d: the resume PC is x-tainted "
                "(%s, amendment A5). The reference must not be handed an "
                "invented pc.\n" % (i, expected))
            return EXIT_REFUSED

        replay, excluded = [], []
        # The trap-entry return-PC push goes FIRST: it happened first, and a
        # REDIRECTED ISR store to the same slot must overwrite it.
        if b["push"] is not None and not a.no_replay_push:
            replay.append(("push",) + b["push"])
        for s in b["stores"]:
            try:
                sa = int(s[0], 16)
            except ValueError:
                sys.stderr.write("mk_inject: REFUSED bracket %d: x-tainted "
                                 "store ADDRESS %s\n" % (i, s[0]))
                return EXIT_REFUSED
            if base <= sa < base + size:
                excluded.append(s[0])
            else:
                replay.append(("isr",) + s)
        for kind, sa, ss, sd in replay:
            if _tainted(ss, sd):
                sys.stderr.write(
                    "mk_inject: REFUSED bracket %d: x-tainted store %s %s %s "
                    "(amendment A5). The reference RAM must not be handed an "
                    "invented byte.\n" % (i, sa, ss, sd))
                return EXIT_REFUSED

        try:
            src = (int(b["ivt"], 16) - 0x8000) // 4
        except ValueError:
            src = -1
        prov = ("# bracket %d kind=%s rtl_retires=%d..%s ref_retire=%d epc=%s ivt=%s "
                "src=%d case=%s expected_resume=%s isr_retires=%s "
                "isr_stores=%d replayed=%d replayed_isr=%d excluded=%d "
                "push=%d nested=%d wake=%d absorbed=%d regs=%d/%d "
                "dropped_mmio=%d dropped_plant=%d pop=%s"
                % (i, b["kind"], b["rtl_start"], b["rtl_end"], b["ref_index"],
                   b["epc"], b["ivt"], src, case, expected,
                   b["rtl_end"] - b["rtl_start"], len(b["stores"]),
                   len(replay), len(b["stores"]) - len(excluded),
                   len(excluded),
                   1 if (b["push"] is not None and not a.no_replay_push) else 0,
                   b["nested"], b["wake"], 1 if b["absorbed"] else 0,
                   len(b["regs"]), b["nreg_raw"],
                   b["mmio_loads"], b["plant_loads"],
                   pop if pop is not None else "none"))
        _emit(b["ref_index"], P_COMMENT, prov)
        sys.stderr.write("mk_inject: %s\n" % prov[2:])
        # V4/A13: the DROPPED interior loads, verbatim up to the cap, then the
        # EXACT census. A5's "never silently skipped" applies to a drop as much
        # as to a substitution.
        for d in b["dropped"]:
            _emit(b["ref_index"], P_COMMENT, "# BRACKET %d DROPPED %s" % (i, d))
        n_dropped_tot = b["mmio_loads"] + b["plant_loads"]
        if n_dropped_tot > len(b["dropped"]):
            _emit(b["ref_index"], P_COMMENT,
                  "# BRACKET %d DROPPED-TRUNCATED %d more not listed "
                  "(the census below is EXACT)"
                  % (i, n_dropped_tot - len(b["dropped"])))
        if n_dropped_tot or b["stores"]:
            cen = ("# BRACKET %d census: %d dropped load(s) (%d mmio + %d plant), "
                   "%d replayed store(s), %d dropped MMIO store(s), "
                   "%d register(s) replayed from %d write(s)"
                   % (i, n_dropped_tot, b["mmio_loads"], b["plant_loads"],
                      len(replay), len(excluded), len(b["regs"]), b["nreg_raw"]))
            _emit(b["ref_index"], P_COMMENT, cen)
            sys.stderr.write("mk_inject: %s\n" % cen[2:])
        if excluded:
            # RULING: every MMIO exclusion is visible in BOTH places.
            ex = "# bracket %d excluded-mmio %s" % (i, " ".join(excluded))
            _emit(b["ref_index"], P_COMMENT, ex)
            sys.stderr.write("mk_inject: %s  (not replayed: the device is not "
                             "modelled)\n" % ex[2:])
        if pop is None:
            sys.stderr.write(
                "mk_inject: WARNING bracket %d has no '# IRETPOP' diagnostic; "
                "the REDIRECTED case cannot be detected and the resume PC "
                "falls back to epc=%s. compare.py's landing check is the "
                "backstop.\n" % (i, b["epc"]))
        for kind, sa, ss, sd in replay:
            _emit(b["ref_index"], P_STORE, "S %d %s %s %s%s"
                  % (b["ref_index"], sa, ss, sd,
                     "   # A7 trap-entry return-PC push"
                     if kind == "push" else ""))
            n_S += 1
        # V4/A12: the ISR's register writes, in register order for readability
        # (they are all applied together, so order is cosmetic).
        if not a.no_reg_replay:
            for rd in sorted(b["regs"]):
                _emit(b["ref_index"], P_REG,
                      "G %d %s %s" % (b["ref_index"], rd, b["regs"][rd]))
        _emit(b["ref_index"], P_PC, "B %d %s   # rtl_retire=%d"
              % (b["ref_index"], expected, b["rtl_start"]))

    # ---- V4: the PLANTS (A13) -------------------------------------------
    # Emitted at their own retire index, NOT in a trailing block: the file has to
    # be ascending by index (see the docstring), and plants interleave with the
    # brackets and the F records.
    n_P = 0
    dropped_ctl = None
    for j, (ridx, pa, ps, pd, rtlr) in enumerate(plants):
        if a.drop_plant is not None and j == a.drop_plant:
            dropped_ctl = (j, ridx, pa, ps, pd)
            _emit(ridx, P_PLANT,
                  "# NEGATIVE CONTROL --drop-plant %d: the P record for retire %d "
                  "addr=%s size=%s data=%s IS DELIBERATELY OMITTED. The reference "
                  "will read STALE RAM at that load." % (j, ridx, pa, ps, pd))
            continue
        _emit(ridx, P_PLANT,
              "P %d %s %s %s   # rtl_retire=%d" % (ridx, pa, ps, pd, rtlr))
        n_P += 1

    # ---- V4: the FORCED SC FAILURES (A14) -------------------------------
    for r in sc_fails:
        _emit(r, P_SCFAIL, "F %d" % r)

    # ONE ascending stream. The sort is STABLE and `seq` is only a tiebreaker of
    # last resort, so records keep their trace order inside one (index, prio).
    entries.sort(key=lambda e: (e[0], e[1], e[2]))
    out_lines = [e[3] for e in entries]
    for k in range(1, len(entries)):
        if entries[k][0] < entries[k - 1][0]:      # cannot happen; assert anyway
            sys.stderr.write("mk_inject: INTERNAL ERROR descending retire index "
                             "%d after %d\n" % (entries[k][0], entries[k - 1][0]))
            return EXIT_USAGE

    if depth > 0:
        # For a SLEEP bracket this is the NORMAL shape of a hart that parked and
        # was never woken: the park window has no exit, so there is nothing to
        # realign TO and the reference correctly stops at the park point.
        kindtxt = cur["kind"] if cur else "?"
        sys.stderr.write(
            "mk_inject: %s the trace ends inside an UNTERMINATED %s bracket "
            "(depth=%d, opened at line %s): no matching 'X iret'. No B/S/G "
            "records were emitted for it, so the reference stops at "
            "ref_retire=%s.%s\n"
            % ("NOTE" if kindtxt == "SLEEP" else "WARNING", kindtxt, depth,
               cur["line"] if cur else "?",
               cur["ref_index"] if cur else "?",
               "  This is the EXPECTED shape of a hart that parked forever "
               "(PARKED-ONLY participation)." if kindtxt == "SLEEP" else ""))
    for ln, text in diag_bad:
        sys.stderr.write("mk_inject: WARNING amendment-A7 equality FAILED at "
                         "line %d: %s\n" % (ln, text))

    n_G = sum(0 if a.no_reg_replay else len(b["regs"]) for b in brackets)
    try:
        with open(a.bracket_out, "w") as fh:
            fh.write("# mk_inject.py reference REALIGNMENT script "
                     "(V3 ISR-BRACKET + V4 P/G/F)\n")
            fh.write("# rtl=%s mmio=%s entry=%s brackets=%d stores=%d regs=%d "
                     "plants=%d forced_sc=%d/%d\n"
                     % (a.rtl, a.mmio, a.entry or "none", len(brackets), n_S,
                        n_G, n_P, len(sc_fails), n_sc))
            fh.write("# ref_retires=%d rtl_retires=%d   <- the reference's OWN "
                     "retire budget; the runner\n"
                     "#   must bound --instructions with ref_retires, never with "
                     "the RTL count.\n" % (n_ref_retire, n_retire))
            if pbase is not None:
                fh.write("# plant window=%08x..%08x (%s)%s\n"
                         % (pbase, pbase + psize - 1, pderiv,
                            "  pre-entry plant loads skipped=%d" % plant_pre
                            if plant_pre else ""))
            fh.write("# <retire_index> is the REFERENCE model's retire count "
                     "(post-entry R records with\n"
                     "# bracketed ISR retires EXCLUDED) -- the reference never "
                     "executes an ISR. The raw\n"
                     "# RTL retire number is carried as rtl_retire= on each B "
                     "line; the two coincide\n"
                     "# only for the first bracket.\n")
            fh.write("# TAGS: B pc-realign | S bracket store replay | "
                     "G register replay (A12) |\n"
                     "#       P shared-window plant (A13) | "
                     "F force the next sc.w to FAIL (A14)\n")
            if a.no_replay_push:
                fh.write("# --no-replay-push: the A7 trap-entry return-PC push "
                         "is NOT replayed (negative control)\n")
            if a.no_sleep_bracket:
                fh.write("# --no-sleep-bracket: 'X … wfi_enter' does NOT open a "
                         "bracket (negative control)\n")
            if a.no_reg_replay:
                fh.write("# --no-reg-replay: NO G records (negative control)\n")
            if a.no_force_sc:
                fh.write("# --no-force-sc: NO F records, the reference's sc.w "
                         "always succeeds (negative control)\n")
            if dropped_ctl is not None:
                fh.write("# --drop-plant %d: ONE plant record deliberately "
                         "OMITTED (negative control)\n" % a.drop_plant)
            for ln_, why in sc_inconsistent:
                fh.write("# SC-INCONSISTENT trace line %d: %s\n" % (ln_, why))
            fh.write("# RECORDS BELOW ARE SORTED BY <retire_index>, ASCENDING "
                     "(vesta_ref requires it).\n")
            for line in out_lines:
                fh.write(line + "\n")
    except IOError as e:
        sys.stderr.write("mk_inject: cannot write --bracket-out %s: %s\n"
                         % (a.bracket_out, e))
        return EXIT_USAGE

    if a.drop_plant is not None and dropped_ctl is None:
        sys.stderr.write("mk_inject: ERROR --drop-plant %d has NO EFFECT: only "
                         "%d plant(s) were emitted. An unlanded perturbation is "
                         "a spec violation -- refusing.\n"
                         % (a.drop_plant, len(plants)))
        return EXIT_USAGE
    if dropped_ctl is not None:
        j, ridx, pa, ps, pd = dropped_ctl
        sys.stderr.write("mk_inject: *** NEGATIVE CONTROL LANDED *** --drop-plant "
                         "%d omitted P retire=%d addr=%s size=%s data=%s\n"
                         % (j, ridx, pa, ps, pd))

    sys.stderr.write("mk_inject: %d bracket(s), %d replayed store(s), %d G, "
                     "%d P, %d F -> %s\n"
                     % (len(brackets), n_S, n_G, n_P, len(sc_fails),
                        a.bracket_out))
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
