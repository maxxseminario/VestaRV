#!/usr/bin/python3.6
# coding: utf-8
"""VestaRV: build the ordered MMIO replay list and the ISR-bracket realignment script for cosim.

Reads a vesta_tracer.vhd trace and emits one `<addr8> <size1> <value8>` record per
unmodelled-region load in emission order, not keyed by address: a repeated read of one
register returns different values and the control flow depends on which. Retire indices are
the reference model's count. Never fabricates: an x-tainted or NODATA record exits 5.
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
    """`<decl> <name> : natural := <n>;` to int, or None. `decl` is "constant" for a package or
    architecture constant and "" for a generic default, the syntax being otherwise identical.
    Accepts a decimal or a 16#..# literal.
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


def _hart_tile_sh_aw_binding(mcu_path):
    """(instances, bound): how many hart_tile and orch_tile instances MCU.vhd has, and how many bind
    SH_AW explicitly. No entity default can equal both shipped values, so this proves the binding
    and demands equality with the default only where an instance leaves it unbound.
    """
    inst = re.compile(r'entity\s+work\.(?:hart_tile|orch_tile)\b', re.I)
    bind = re.compile(r'\bSH_AW\s*=>')
    endg = re.compile(r'\bport\s+map\b', re.I)
    instances = 0
    bound = 0
    try:
        with open(mcu_path) as fh:
            lines = fh.readlines()
    except IOError:
        return 0, 0
    for i, line in enumerate(lines):
        if not inst.search(line):
            continue
        instances += 1
        # the generic map runs from here to this instance's `port map`
        for j in range(i + 1, min(i + 200, len(lines))):
            if bind.search(lines[j]):
                bound += 1
                break
            if endg.search(lines[j]):
                break
    return instances, bound


def derive_plant_window(root):
    """(base, size) of the shared-and-writable window, derived from the RTL rather than hardcoded:
    base is RamStartAddress + RamSize, the top of the private TCM, and top is 2**(SH_AW+2).
    Everything below base is the shared ROM or the peripheral window, both already modelled.
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
    # CPR8/R7: the MCU constant is authoritative WHEN every hart instance binds
    # the generic. Prove that; only an unbound instance can let the entity
    # default reach the RTL, and only then does it have to agree.
    _inst, _bound = _hart_tile_sh_aw_binding(mcu)
    if _inst == 0:
        raise ValueError("--plant auto: no hart_tile/orch_tile instance found in %s "
                         "-- refusing to guess how SH_AW reaches the tiles" % mcu)
    if _bound != _inst and sh_aw_tile is not None and sh_aw_tile != sh_aw:
        raise ValueError("--plant auto: %d of %d hart instances in MCU.vhd leave the "
                         "SH_AW generic UNBOUND, and SH_AW disagrees between MCU.vhd "
                         "(%d) and hart_tile.vhd's generic default (%d) -- refusing to "
                         "guess which one the build used"
                         % (_inst - _bound, _inst, sh_aw, sh_aw_tile))
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
    # V4
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

    # V4: the plant window
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

    # -- ISR-BRACKET state (only used when --bracket-out is given)
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

    # -- V4 state
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
    last_scghost = 0    # A16: `# SCGHOST` lines seen since the last record line

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
        """Decide the pending sc.w's verdict from `rd`, 0 success and 1 failure, and cross-check it. A
        globally failed SC still emits an `M ... S` record, the write being suppressed downstream in
        resv_unit, so a store-presence oracle would emit no F for any cross-hart kill.
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
        # cross-checks. Reported; NEVER used to override `rd`.
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
        if (not failed) and s["scghost"]:
            # A16: `# SCGHOST` says resv_unit SUPPRESSED the write, yet rd says
            # the SC succeeded. The two disagree about the same event, and the
            # core computes rd FROM sc_fail_ext (vesta.vhd:1930-1933), so they
            # cannot legitimately differ. Reported for exactly the reason its
            # mirror image above is (`rd`=0 with a `# SCFAILRD`): a
            # "success" the memory system did not perform is the M4b shape.
            sc_inconsistent.append(
                (s["ln"], "sc.w reports SUCCESS (rd=00000000) but the tracer "
                          "emitted %d '# SCGHOST' diagnostic(s) -- resv_unit "
                          "suppressed the write yet the core claims success"
                          % s["scghost"]))
        if failed and (s["scghost"] or s["store"]):
            # The sc_fail_ext signature, and the COMMON case (every cross-hart
            # kill). Counted, not warned: at ~29,000 per hart a line each would
            # bury the log, and the write's suppression is downstream of the port
            # the tracer samples, so this is the expected shape, not a finding.
            #
            # A16 changed WHICH witness proves it, and that is an improvement,
            # not a rename. Pre-A16 the only evidence of an external kill was
            # that a store record HAPPENED TO FOLLOW -- i.e. the very record
            # A15 exists to delete, so the shape census was reading the defect
            # as its own instrument. `# SCGHOST` is a dedicated witness emitted
            # by the RTL observer that saw `sc_fail_ext` itself, which makes
            # `ext` and `local` symmetric: one diagnostic each.
            # `s["store"]` is kept so a PRE-A16 trace still censuses correctly.
            sc_shape["ext"] += 1
        if failed and s["scfailrd"]:
            sc_shape["local"] += 1

    # A10 pre-pass: index the bit-granular x masks
    # `# XBITS <hart> <cycle> <field> <mask> <defined>` BINDS BACKWARD -- it
    # describes the record on the line ABOVE it. The main loop decides what to
    # do with a record when it reaches that record's line, i.e. BEFORE the mask
    # line has been read, so the index is built in one cheap pre-pass rather
    # than by look-ahead inside the main loop. A pre-A10 trace simply yields an
    # empty index and every consumer below behaves exactly as it did.
    xbits = {}          # record lineno -> {field: (mask_int, defined_int)}
    n_xbits = 0
    n_x_verified = 0    # --allow-x substitutions checked against a mask
    n_x_bits_filled = 0 # undriven bits those substitutions were allowed to fill
    for _n, _raw in enumerate(lines, 1):
        _f = _raw.split()
        if len(_f) == 7 and _f[0] == "#" and _f[1] == "XBITS":
            try:
                xbits.setdefault(_n - 1, {})[_f[4]] = (int(_f[5], 16),
                                                       int(_f[6], 16))
                n_xbits += 1
            except ValueError:
                pass    # malformed: leave it to the findings-surface census

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
            elif len(f) >= 2 and f[1] == "SCGHOST":
                # A16 (finding T2): the tracer's witness that resv_unit
                # SUPPRESSED this sc.w's write. It replaces the store-presence
                # accident the `ext` shape used to be counted from: pre-A16 the
                # only sign of an external kill was that an `M ... S` happened
                # to follow, which is exactly the record A15/A16 exist to
                # retire. Binds FORWARD like `# SCFAILRD` and for the same
                # reason -- both are emitted at the SC_CHECK edge, before the
                # retire group is flushed, so both PRECEDE the sc.w's own `R`.
                last_scghost += 1
            elif len(f) >= 2 and f[1] == "SCGHOSTX":
                # A16 refused to classify: the verdict itself was x. The store
                # was KEPT, so this behaves as a pre-A16 trace at that SC and
                # A15 is what will (or will not) catch it downstream.
                diag_bad.append((ln, raw.strip()))
            continue
        # A diagnostic binds only to the record on the very next record line.
        push_here, pop_here = last_push, last_pop
        scfailrd_here = last_scfailrd
        scghost_here = last_scghost
        last_push = last_pop = None
        last_scfailrd = 0
        last_scghost = 0
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
            # V4/A14: is this retire an sc.w?
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
                           "scfailrd": scfailrd_here,
                           "scghost": scghost_here}
            if depth > 0:
                # V4/A12: the ISR's committed register writes
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

        # V4/A13: the PLANT window
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
            # A10: VERIFY the substitution instead of trusting it
            # Before A10 this was an unchecked hand-off: the operator supplied
            # 8 hex digits and mk_inject wrote them into the reference's mouth.
            # `x` was NIBBLE-granular, so nothing could tell whether those
            # digits preserved the bits the RTL had actually DRIVEN -- an
            # allowlist entry could silently overwrite a defined bit and the
            # only symptom would be a divergence somewhere downstream, blamed
            # on the DUT.
            #
            # With the mask the check is exact and cheap: every bit the RTL
            # DROVE must survive the substitution, and the entry may only fill
            # bits the RTL left UNDRIVEN. Ruling A2 permits fabrication; it
            # does not permit contradiction.
            xb = xbits.get(ln, {}).get("data")
            if xb is not None:
                mask, defined = xb
                try:
                    subv = int(sub, 16)
                except ValueError:
                    subv = None
                if subv is not None and (subv & ~mask & 0xffffffff) != defined:
                    sys.stderr.write(
                        "mk_inject: REFUSED ordinal %d addr=%s: the --allow-x "
                        "substitution %s CONTRADICTS a bit the RTL actually "
                        "drove [amendment A10].\n"
                        "  observed=%s  undriven-mask=%08x  driven-bits=%08x\n"
                        "  substituted=%08x  driven-bits-after=%08x\n"
                        "  A2 permits filling UNDRIVEN bits; it does not permit "
                        "overwriting DRIVEN ones.\n"
                        % (ordn, addr_s, sub, val_s, mask, defined, subv,
                           subv & ~mask & 0xffffffff))
                    return EXIT_REFUSED
                if subv is not None:
                    n_x_verified += 1
                    n_x_bits_filled += bin(mask).count("1")
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
    # A10: the mask census. Printed whenever the trace carried masks, INCLUDING
    # the zero-substitution case -- "the trace is bit-granular and no allowlist
    # entry needed checking" is a different statement from "this trace predates
    # A10", and only the count distinguishes them.
    if n_xbits:
        sys.stderr.write("mk_inject: A10 bit-granular x: %d '# XBITS' mask(s) "
                         "indexed; %d --allow-x substitution(s) VERIFIED "
                         "against a mask (%d undriven bit(s) filled, 0 driven "
                         "bit(s) overwritten -- a contradiction is EXIT_REFUSED)"
                         "\n" % (n_xbits, n_x_verified, n_x_bits_filled))
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
    # halves of the RTL's SC failure path. THEIR SUM IS LESS THAN `scfail`
    # WHENEVER A LOCAL FAILURE OCCURS, and at this commit that means always --
    # so `unwitnessed` is printed rather than left to the reader's arithmetic.
    # (The pre-A16 wording here said the two "should equal `scfail`". That was
    # true when it was written and is false now; it is corrected rather than
    # annotated, because the person it would mislead is precisely the one
    # debugging a census that no longer balances.)
    # Measured on `shlrsc` h00 at this commit:
    # 4 forced, ext-shape 2, local-shape 0. The missing two are the LOCALLY
    # failed SCs, and their witness is gone because fix-pass W1-F2 deleted the
    # thing that produced it -- `# SCFAILRD` fires on the side-effecting bus
    # READ a failed sc.w used to issue in SC_CHECK, and F2's whole point was
    # that this read should never have existed. The diagnostic was correct, the
    # RTL it observed was the bug, and removing the bug removed the observation.
    # `# SCFAILRD` is now extinct in every trace.
    #
    # The census's two halves are audited whenever a defect is removed, and a gap
    # is left VISIBLE rather than
    # papered over: an unwitnessed failure is not wrong -- `rd` is still the
    # oracle and the F is still emitted -- but a census whose halves silently
    # stop summing is how a real gap gets normalised.
    if n_sc or n_sc_interior:
        sys.stderr.write("mk_inject: sc.w census: %d compared, %d interior "
                         "(no F), forced=%d [ext-shape=%d local-shape=%d "
                         "unwitnessed=%d], ghost store(s) withheld from the "
                         "S replay=%d\n"
                         % (n_sc, n_sc_interior, len(sc_fails),
                            sc_shape["ext"], sc_shape["local"],
                            max(0, len(sc_fails)
                                   - sc_shape["ext"] - sc_shape["local"]),
                            n_sc_ghost))
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
    """Emit the reference's bracket realignment script: B per bracket with the resume PC, S per
    replayed store, P for plants, G for the ISR's register writes, F for a forced sc.w failure.
    The consumer's applier is single-pass, so the whole file is stably sorted into ascending index.
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

    # V4: the PLANTS (A13)
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

    # V4: the FORCED SC FAILURES (A14)
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
