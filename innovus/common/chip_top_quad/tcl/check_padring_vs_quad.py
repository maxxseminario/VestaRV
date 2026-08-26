#!/usr/bin/env python3
# =============================================================================
# check_padring_vs_quad.py -- CQ3b three-way pad-ring consistency gate.
#
# Adapts C0's check_padring_vs_castalia.tcl (a two-way die-vs-generated diff)
# into a THREE-way check across the CQ3b deliverables:
#     doc       ~/vesta_docs/castalia_quad/cq3b_pin_map.md  (the <!--PINMAP--> block)
#     padlists  tcl/chip_top_quad_padlists.tcl               (BOTTOM/TOP/LEFT/RIGHT)
#     netlist   in/chip_top_quad.v                           (pad instances)
#
# LANGUAGE NOTE (per the CQ3b GATE clause): written in PYTHON, not tcl. The C0
# check is pure-tcl because it diffs two tcl files; this check must also parse a
# markdown doc and a structural Verilog netlist, which is awkward/error-prone in
# bare tclsh. Python keeps the parsing robust. Run with the SYSTEM python3
# (/usr/bin/python3), NOT the aoj_cal wrapper -- it takes a file, no `-c`.
#
# Cross-checks:  per-edge count (16) + total (64); instance-set equality across
# all three; side membership doc<->padlists; cell type doc<->netlist; signal net
# doc<->netlist (GPIO/electrode); supply pads netlist-UNCONNECTED; 4 PCORNER_G;
# dropped prt3[0]/[4] absent + tied at mcu0; analog cell totals.
#
# CQ8c CONVERGENCE GATE (check H): the PAD RING now has ONE source of truth --
# the platform/common generator package model 'castalia-quad-qfn64'. Its canonical
# emission (out/pnr/chip_top_padring.tcl built with config/cq.json) is committed
# here byte-identical as chip_top_padring_quad.gen.tcl (GEN). The hand-maintained
# padlists (what the innovus flow actually consumes -- they carry the RTL instance
# names the netlist needs) are gated to MIRROR the generator ring exactly: same
# per-edge order, same pin->function assignment, under the deterministic name
# translation PAD_prt{k}_{b} <-> PAD_P{k-1}_{b} (+ supply/analog case+side). So the
# padlists are a checked NAME-BINDING of the generator ring, not a 2nd source.
#   --regen : re-derive GEN from the live generator (make -C platform/common
#             generate CONFIG=config/cq.json), byte-compare to the committed GEN,
#             then restore the default generation. Proves GEN is fresh vs the
#             package model. (Off by default: keeps the gate offline + non-invasive
#             so a concurrent platform/common session is never disturbed.)
#
# Usage:  /usr/bin/python3 tcl/check_padring_vs_quad.py [--regen]   (from innovus/common)
#         exit 0 = consistent, 1 = FAIL.
# =============================================================================
import os, re, sys, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))            # innovus/common/tcl
ROOT = os.path.dirname(HERE)                                 # innovus/common
REPO = os.path.dirname(os.path.dirname(ROOT))                # repo root
DOC  = os.path.expanduser("~/vesta_docs/castalia_quad/cq3b_pin_map.md")
PADL = os.path.join(HERE, "chip_top_quad_padlists.tcl")
NETL = os.path.join(ROOT, "in", "chip_top_quad.v")
GEN  = os.path.join(HERE, "chip_top_padring_quad.gen.tcl")   # committed generator emission
PLAT = os.path.join(REPO, "platform", "common")
GENOUT = os.path.join(PLAT, "out", "pnr", "chip_top_padring.tcl")
REGEN = ("--regen" in sys.argv)

SIDE_OF_LIST = {"BOTTOM": "S", "TOP": "N", "LEFT": "W", "RIGHT": "E"}
SUPPLY_CELLS = {"PVDD1DGZ_G","PVSS1DGZ_G","PVDD2DGZ_G","PVSS2DGZ_G",
                "PVDD2ANA_G","PVSS2ANA_G","PVDD2POC_G"}

fails = []
def fail(m): fails.append(m)

# ---- 1. doc ----------------------------------------------------------------
def parse_doc(path):
    txt = open(path).read()
    m = re.search(r"<!--PINMAP-START-->(.*?)<!--PINMAP-END-->", txt, re.S)
    if not m: sys.exit("FATAL: no <!--PINMAP--> block in %s" % path)
    rows = {}
    for ln in m.group(1).splitlines():
        ln = ln.strip()
        if not ln or ln.startswith("```"): continue
        f = ln.split("|")
        if len(f) != 5: sys.exit("FATAL: bad doc row: %r" % ln)
        pin, side, inst, cell, net = (x.strip() for x in f)
        rows[inst] = {"pin": int(pin), "side": side, "cell": cell, "net": net}
    return rows

# ---- 2. padlists -----------------------------------------------------------
def parse_padlists(path):
    txt = open(path).read()
    # strip line comments so a '#'-commented instance never counts
    txt = "\n".join(re.sub(r"#.*$", "", ln) for ln in txt.splitlines())
    lists = {}
    for name in SIDE_OF_LIST:
        m = re.search(r"set\s+%s\s+\[list(.*?)\]" % name, txt, re.S)
        if not m: sys.exit("FATAL: no `set %s [list ...]` in padlists" % name)
        lists[name] = re.findall(r"PAD_[A-Za-z0-9_]+", m.group(1))
    return lists

# ---- 3. netlist ------------------------------------------------------------
def parse_netlist(path):
    txt = open(path).read()
    txt = re.sub(r"//.*", "", txt)          # strip line comments
    insts = {}
    # CELL  PAD_inst ( .PIN(net), ... );
    for m in re.finditer(r"\b([A-Z][A-Za-z0-9_]*)\s+(PAD_[A-Za-z0-9_]+)\s*\((.*?)\)\s*;",
                         txt, re.S):
        cell, inst, body = m.group(1), m.group(2), m.group(3)
        nets = re.findall(r"\b(?:aio|prt[1-4]|resetn)\s*\[?\s*\d*\s*\]?", body)
        insts[inst] = {"cell": cell, "body": body,
                       "nets": [re.sub(r"\s+", "", n) for n in nets]}
    return insts, txt

# ---- 4. generator padring (single source of truth) -------------------------
def parse_gen(path):
    """Generator emission: `lappend PADRING_<SIDE> PAD_<func>` per pad, in
       geometric order. Returns {SIDE: [PAD_func, ...]} keyed by TOP/BOTTOM/
       LEFT/RIGHT and the model name from the header (or '')."""
    txt = open(path).read()
    mm = re.search(r'model\s+"([^"]+)"', txt)
    model = mm.group(1) if mm else ""
    lists = {}
    for side in ("LEFT", "BOTTOM", "RIGHT", "TOP"):
        lists[side] = re.findall(r'lappend\s+PADRING_%s\s+(PAD_\w+)' % side, txt)
    return lists, model

def hand_to_funckey(inst):
    """Translate a hand-padlist RTL instance name to the generator function key.
       PAD_prt{k}_{b} -> PAD_P{k-1}_{b}; supplies/analog upper-case, side suffix
       dropped (the generator distinguishes L/R + T/B pads by position only)."""
    m = re.match(r'PAD_prt(\d)_(\d)$', inst)
    if m: return "PAD_P%d_%s" % (int(m.group(1)) - 1, m.group(2))
    m = re.match(r'PAD_(vdd|vss|vddpst|vsspst)_[a-z]+$', inst)
    if m: return "PAD_" + m.group(1).upper()
    if inst == "PAD_resetn": return "PAD_RESETN"
    if inst == "PAD_poc":    return "PAD_POC"
    m = re.match(r'PAD_(avdd|avss|we|re2|re|ce)_(\d)$', inst)
    if m: return "PAD_%s_%s" % (m.group(1).upper(), m.group(2))
    return "??" + inst          # unknown -> guaranteed mismatch

doc   = parse_doc(DOC)
padl  = parse_padlists(PADL)
netl, netraw = parse_netlist(NETL)

print("PADCHECK (CQ3b three-way)  doc=%s" % os.path.basename(DOC))
print("  padlists=%s  netlist=%s" % (os.path.basename(PADL), os.path.basename(NETL)))

# ---- A. counts -------------------------------------------------------------
for name, items in padl.items():
    if len(items) != 16:
        fail("edge %s has %d pads (want 16)" % (name, len(items)))
tot_pad = sum(len(v) for v in padl.values())
if tot_pad != 64: fail("padlists total %d (want 64)" % tot_pad)
if len(doc) != 64: fail("doc pin table has %d rows (want 64)" % len(doc))

corners = [i for i in netl if i.startswith("PAD_CORNER")]
if len(corners) != 4: fail("netlist has %d PCORNER (want 4): %s" % (len(corners), corners))
for c in corners:
    if netl[c]["cell"] != "PCORNER_G": fail("%s is %s (want PCORNER_G)" % (c, netl[c]["cell"]))
net_pads = {i: v for i, v in netl.items() if not i.startswith("PAD_CORNER")}
if len(net_pads) != 64: fail("netlist has %d package pads (want 64)" % len(net_pads))

# ---- B. instance-set equality ---------------------------------------------
doc_set  = set(doc)
padl_set = set(i for v in padl.values() for i in v)
net_set  = set(net_pads)
if doc_set != padl_set:
    fail("doc vs padlists differ: doc-only=%s padl-only=%s"
         % (sorted(doc_set - padl_set), sorted(padl_set - doc_set)))
if doc_set != net_set:
    fail("doc vs netlist differ: doc-only=%s net-only=%s"
         % (sorted(doc_set - net_set), sorted(net_set - doc_set)))

# ---- C. side membership doc<->padlists ------------------------------------
for name, items in padl.items():
    side = SIDE_OF_LIST[name]
    for inst in items:
        if inst in doc and doc[inst]["side"] != side:
            fail("%s: padlists side %s, doc side %s" % (inst, side, doc[inst]["side"]))
doc_side_count = {}
for r in doc.values(): doc_side_count[r["side"]] = doc_side_count.get(r["side"], 0) + 1
for s in "WSEN":
    if doc_side_count.get(s) != 16:
        fail("doc side %s count %s (want 16)" % (s, doc_side_count.get(s)))

# ---- D. cell type doc<->netlist -------------------------------------------
for inst, r in doc.items():
    if inst in net_pads and net_pads[inst]["cell"] != r["cell"]:
        fail("%s: doc cell %s, netlist cell %s" % (inst, r["cell"], net_pads[inst]["cell"]))

# ---- E. nets: signal pads match doc; supply pads unconnected ---------------
for inst, r in doc.items():
    if inst not in net_pads: continue
    nv = net_pads[inst]
    if r["cell"] in SUPPLY_CELLS:
        if nv["nets"]:
            fail("%s (%s) should be netlist-UNCONNECTED, found %s"
                 % (inst, r["cell"], nv["nets"]))
    else:
        want = re.sub(r"\s+", "", r["net"])
        if want not in nv["nets"]:
            fail("%s: doc net %s not in netlist pins %s" % (inst, want, nv["nets"]))

# ---- F. analog cell totals -------------------------------------------------
from collections import Counter
cc = Counter(net_pads[i]["cell"] for i in net_pads)
for cell, want in (("PDB3A_G",16),("PVDD2ANA_G",4),("PVSS2ANA_G",4),
                   ("PDUW16SDGZ_G",31),("PVDD1DGZ_G",2),("PVSS1DGZ_G",2),
                   ("PVDD2DGZ_G",2),("PVSS2DGZ_G",2),("PVDD2POC_G",1)):
    if cc.get(cell,0) != want:
        fail("netlist %s count %d (want %d)" % (cell, cc.get(cell,0), want))

# ---- G. dropped bits absent + tied at mcu0 --------------------------------
for d in ("prt3[0]", "prt3[4]"):
    if any(d.replace(" ","") in v["nets"] for v in net_pads.values()):
        fail("dropped %s is padded (should have NO pad)" % d)
    if d in {doc[i]["net"] for i in doc}:
        fail("dropped %s appears in doc pin table" % d)
m = re.search(r"\.prt3_in\s*\((.*?)\)", netraw, re.S)
if not m or m.group(1).count("1'b0") < 2:
    fail("mcu0.prt3_in does not tie the 2 dropped bits to 1'b0")
for want in ("PAD_prt3_0", "PAD_prt3_4"):
    if want in netl or any(want in v for v in padl.values()):
        fail("%s should not exist (dropped)" % want)

# ---- H. CONVERGENCE: generator ring (source of truth) <-> hand padlists -----
# Optional --regen: re-derive the committed GEN from the live generator and prove
# it is byte-fresh, then restore the default generation (try/finally).
if REGEN:
    if not os.path.isdir(PLAT):
        fail("--regen: platform/common not found at %s" % PLAT)
    else:
        try:
            r = subprocess.run(["make", "-C", PLAT, "generate", "CONFIG=config/cq.json"],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            if r.returncode != 0:
                fail("--regen: `make generate CONFIG=config/cq.json` exit %d" % r.returncode)
            elif not os.path.exists(GENOUT):
                fail("--regen: generator did not emit %s" % GENOUT)
            elif open(GENOUT).read() != open(GEN).read():
                fail("--regen: committed GEN is STALE vs live generator -- "
                     "refresh: cp %s %s" % (GENOUT, GEN))
            else:
                print("  --regen: committed GEN is BYTE-FRESH vs the live generator")
        finally:
            subprocess.run(["make", "-C", PLAT, "generate"],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)  # restore default

gen, gen_model = parse_gen(GEN)
if gen_model != "castalia-quad-qfn64":
    fail("GEN model is %r (want castalia-quad-qfn64) -- %s is not the CQ ring"
         % (gen_model, os.path.basename(GEN)))
for name in SIDE_OF_LIST:                          # BOTTOM/TOP/LEFT/RIGHT
    gl = gen.get(name, [])
    hl = [hand_to_funckey(x) for x in padl[name]]
    if gl != hl:
        fail("edge %s: generator ring != hand padlists (order/function)" % name)
        for i, (a, b) in enumerate(zip(gl, hl)):
            if a != b:
                fail("  %s pos %d: gen=%s hand=%s->%s" % (name, i, a, padl[name][i], b))
        if len(gl) != len(hl):
            fail("  %s length gen=%d hand=%d" % (name, len(gl), len(hl)))

# ---- verdict ---------------------------------------------------------------
print("  edges: " + ", ".join("%s=%d(%s)" % (n, len(padl[n]), SIDE_OF_LIST[n]) for n in padl))
print("  total package pads: doc=%d padlists=%d netlist=%d ; corners=%d"
      % (len(doc), tot_pad, len(net_pads), len(corners)))
print("  cells: " + ", ".join("%s=%d" % (c, cc[c]) for c in sorted(cc)))
print("  dropped GPIO (no pad): prt3[0]=P2.0/T0CMP0, prt3[4]=P2.4/T1CMP0 -- tied 1'b0 at mcu0")
if fails:
    print("PADCHECK: %d FAIL" % len(fails))
    for f in fails: print("  FAIL: " + f)
    sys.exit(1)
print("  convergence: generator ring '%s' == hand padlists (all 4 edges, order+function)"
      % gen_model)
print("PADCHECK: 0 FAIL -- generator <-> doc <-> padlists <-> netlist CONSISTENT (64 pins, 16/side)")
sys.exit(0)
