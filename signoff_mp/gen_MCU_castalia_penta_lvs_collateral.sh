#!/bin/bash
# CASTALIA-PENTA chip (CPR7, 2026-08-15): build the LVS collateral for the
# mcu_castalia_penta signoff block. CHIP-ONLY clone of
# gen_MCU_castalia_lvs_collateral.sh -- MCU_castalia_penta is a FLAT chip run
# (the MCU_PENTA hierarchy is placed and routed inside the chip), so there is
# no assembly cut and no block leg.
#
# WHAT IT PRODUCES (exactly what signoff_mp/Makefile's mcu_castalia_penta
# NETLIST/LABELS point at):
#   pvs/MCU_castalia_penta.lvs.v        (chip only, from the CPR7 cut's own DB)
#   pvs/MCU_castalia_penta.lvslabels    (same session, VDD_SW_H0..3 + 2
#                                        short sentinels; 4 corner tiles only --
#                                        hart4 is SOFT and has no switched rail)
#   pvs/MCU_castalia_penta_full.lvs.v   = patched chip + pvs/hart_tile.lvs.v
#
# CUT OF RECORD (CPR7 retarget): the tcl reads
# dbs/MCU_castalia_penta.cpr7eco.innovus.dat (the CPR6 5-core re-cut + its
# closure antenna ECO) and checks the saved netlist against
# out/MCU_castalia_penta.cpr7.xsim.v -- the ECO products, NOT the CPR6 signoff
# DB/GDS and NOT any CP-era product. Re-run this whole script after ANY further
# P&R or ECO on this block (the A7 re-P&R-invalidates-LVS-netlists rule).
#
# CPR3 RENUMBER: the four HARDENED corner tiles are mcu0/hart1..hart4; hart0 is
# the SOFT orchestrator. The lvslabels texts are VDD_SW_H1..H4 and
# pvs/lvs_MCU_castalia_penta_ctl carries the matching four cpoints.
#
# WHY THE CONCATENATION (F2a devlog): a netlist that BOXES hart_tile against a
# FLAT layout hits the 1M-net matcher threshold and aborts; an empty tile stub
# reproduces the same NVN-7090. The proven recipe appends the FULL tile
# netlist, no stub, and `module hart_tile` must be the LAST module in the file.
#
# PAD PATCHER: patch_chip_pads_wound.py is REUSED VERBATIM (binds by INSTANCE
# name only; the penta chip carries the same 72-pad pre-D3 LQFP-100 ring and
# the same PAD_* instance names, verified against in/MCU_castalia_penta.v).
#
# ORDERING NOTE (lvs.sh G0 staleness gate): lvs.sh FATALs when the labels file
# is older than the netlist it is given (= the _full file). The innovus step
# writes the labels, then this script appends the tile netlist, so the labels
# would end up older by seconds. The final `touch` restamps them; the
# pre-check refuses to restamp anything older than the netlist the SAME innovus
# run just wrote, so real cross-cut staleness still trips the gate.
#
# usage: ./gen_MCU_castalia_penta_lvs_collateral.sh [skip_netlist]
#
# Prereqs: source ~/vestarv/cdspaths.sh; the CPR7 ECO must have run
# (dbs/MCU_castalia_penta.cpr7eco.innovus.dat + out/MCU_castalia_penta.cpr7.xsim.v);
# pvs/hart_tile.lvs.v + pvs/hart_tile.lvslabels from the SAME tile cut the flow
# consumed. BATCH ONLY -- one heavy run at a time.

set -u
cd "$(dirname "$0")"

SKIP=${1:-}
INN=../innovus/common/MCU_castalia_penta
PVS=pvs
# TILE_NETLIST is an OVERRIDE (2026-08-26).
#
# pvs/hart_tile.lvs.v is SHARED collateral owned by the tile lineage, and it
# moves on the tile's schedule, not this chip's. The penta layout of record is
# a frozen cut: cpr8's GDS embeds the hart_tile GDS that existed on 2026-08-25
# 02:09, and its chip netlist was elaborated against the hart_tile LEF of that
# same moment. Appending whatever tile netlist happens to be on disk today is
# a cross-cut compare, and it is NOT caught by any of the gates below -- they
# check the tile netlist against the tile's OWN lef/labels, never against the
# chip cut.
#
# MEASURED INSTANCE, 2026-08-26: the chip netlist binds a TWELVE-element
# concatenation to hart_tile's .tcm_ext_addr (FE_OFN964_tcm_ext_addr_11 down
# to _0). The tile netlist embedded in the _full file of record declares
# "input [11:0] tcm_ext_addr" and agrees. The CURRENT pvs/hart_tile.lvs.v --
# from the post-re-LEF tile cut -- declares "input [10:0] tcm_ext_addr". A
# 12-wide expression onto an 11-wide port truncates and shifts every bit of
# that bus, silently, in Verilog. Innovus only WARNS about the same skew
# (IMPVL-361) and continues.
#
# So until penta is re-hardened onto the current tile, point this at the tile
# netlist that matches the frozen cut:
#   TILE_NETLIST=pvs/hart_tile.lvs.v.pre_tcm11 ./gen_MCU_castalia_penta_lvs_collateral.sh
# The width gate in stage 2b refuses the pairing if it is wrong either way.
TILE_NETLIST=${TILE_NETLIST:-$PVS/hart_tile.lvs.v}
BASE=MCU_castalia_penta
TCL=tcl/${BASE}_lvs_netlist.tcl
PATCHER=patch_chip_pads_wound.py

die() { echo "PENTA_LVS FATAL: $*"; exit 1; }

case "$SKIP" in
    ""|skip_netlist) ;;
    *) die "usage: $0 [skip_netlist]" ;;
esac

# ---- shared tile-cut gates (A7 / G0) ----------------------------------------
[ -f "$TILE_NETLIST" ] || die "$TILE_NETLIST missing -- regen via tcl/hart_tile_lvs_netlist.tcl"
[ -f "$PVS/hart_tile.lvslabels" ] || die "$PVS/hart_tile.lvslabels missing (same tcl dumps it)"
if [ "$TILE_NETLIST" = "$PVS/hart_tile.lvs.v" ]; then
    # DEFAULT PATH: the tile netlist must be the CURRENT tile cut.
    [ "$TILE_NETLIST" -nt "$INN/../hart_tile/out/hart_tile.lef" ] || \
        die "$TILE_NETLIST predates $INN/../hart_tile/out/hart_tile.lef -- not this tile cut"
    [ ! "$PVS/hart_tile.lvslabels" -ot "$TILE_NETLIST" ] || \
        die "$PVS/hart_tile.lvslabels is older than $TILE_NETLIST -- re-dump both from one cut"
else
    # PINNED PATH: TILE_NETLIST was overridden to match a FROZEN chip cut, so
    # "newer than the tile LEF" is the wrong question and would reject exactly
    # the file that is correct. The invariant that still has to hold is
    # port-width agreement with the chip netlist, and stage 2b checks it.
    echo "==== $BASE : TILE_NETLIST PINNED to $TILE_NETLIST (tile-recency gates skipped) ===="
    echo "     the port-width gate in stage 2b is what proves this pairing."
fi
# The label coordinates are cut-independent in this lineage (every
# hart_tile.lvslabels sidecar from 2026-08-24 through 2026-08-26 carries
# byte-identical layer-stripped coordinates; only the VDD_SW text LAYER moved
# 131 -> 231), so the labels are read from the current file on both paths.

netlist=$PVS/$BASE.lvs.v
labels=$PVS/$BASE.lvslabels
full=$PVS/${BASE}_full.lvs.v

# ---- CPR7 cut of record (same selection rule as the tcl) --------------------
# RETARGETED TO THE cpr6 SIGNOFF CUT, 2026-08-17.
# This script required ${BASE}.cpr7eco because the CPR7 closure ECO existed to
# repair one thing -- a hanging M4 VSS riser antenna -- and the signoff_mp
# Makefile therefore banned cpr6 with the words "that one still carries the
# unrepaired VSS M4 antenna".
# THAT CONDITION NO LONGER HOLDS FOR THIS LINEAGE. The 8 KiB-TCM re-implementation
# moved the geometry the old antenna lived in, and the current cpr6 signoff cut
# measures Antenna : 0 and IMPVFC-94 dangling : 0 (rpt/*.cpr6.verifyGeometry.
# signoff.rpt and *.cpr6.verifyConnectivity.signoff.rpt). The old cut, by
# contrast, still shows a dangling VSS M4 wire at (2354.900, 1155.160) -- the
# CPR7 ECO relocated that defect rather than removing it.
# So a "cpr7" here would be a rename of an already-clean cut, and signing off a
# no-op ECO product is worse bookkeeping than signing off the cut that was
# actually measured. If a future cut needs a closure ECO again, point CUTSEL back
# at it -- the selection is a variable now, not a literal, for exactly that reason.
# 2026-08-26: DEFAULT MOVED cpr6 -> cpr8. The collateral of record in pvs/ was
# built on 2026-08-25 02:11 from dbs/MCU_castalia_penta.cpr8.signoff.innovus.dat
# and the signoff OA lib was streamed from out/MCU_castalia_penta.cpr8.gds2, so
# the cpr6 default here was a cross-cut trap: an argument-free re-run rebuilds
# the netlist from the PREVIOUS cut while the layout stays cpr8. Keep this in
# step with PENTA_CUT in Makefile and CUTSEL/XSIMSEL in the netlist tcl.
CUTSEL="${CUTSEL:-cpr8.signoff}"
XSIMSEL="${XSIMSEL:-cpr8}"
CUTDB=""
for c in ${BASE}.${CUTSEL}; do
    [ -d "$INN/dbs/$c.innovus.dat" ] && { CUTDB=$c; break; }
done
[ -n "$CUTDB" ] || die "no $INN/dbs/${BASE}.${CUTSEL}.innovus.dat -- re-run P&R (or set CUTSEL)"
echo "==== $BASE : cut of record = $CUTDB ===="

echo "==== $BASE : stage 1 -- netlist + same-cut labels (innovus batch) ===="
[ -f "$INN/out/$BASE.$XSIMSEL.xsim.v" ] || die "no $INN/out/$BASE.$XSIMSEL.xsim.v"
[ -f "$TCL" ] || die "no $TCL"
if [ "$SKIP" != "skip_netlist" ]; then
    command -v innovus > /dev/null || die "innovus not on PATH -- source ~/vestarv/cdspaths.sh"
    ( cd "$INN" && innovus -no_gui -batch \
        -log "log/${BASE}_lvs_regen" -overwrite \
        -files "../../../signoff_mp/$TCL" ) || die "$TCL rc"
fi
[ -s "$netlist" ] || die "$netlist missing/empty (the A7 sanity gate deletes a bad netlist)"
[ -s "$labels" ]  || die "$labels missing/empty -- lvs.sh would SILENTLY skip the VDD_SW injection"
[ ! "$labels" -ot "$netlist" ] || die "$labels older than $netlist -- not one session"
# 2026-08-25 SENTINEL CARRY: the tile dump ends in its own VDD:/VSS: short
# sentinels.  The top-level dump no longer aliases those per hart (they made
# spurious VSS_H1-vs-VSS shorts), so they are not counted as carried pieces.
tile_pieces=$(awk 'NF>=4 && $4!="VDD:" && $4!="VSS:"' "$PVS/hart_tile.lvslabels" | wc -l)
want=$(( 4 * tile_pieces + 2 ))
got=$(wc -l < "$labels")
[ "$got" -eq "$want" ] || die "$labels has $got labels, expected $want (4 x $tile_pieces tile pieces + 2 sentinels)"
echo "     $labels  $got labels (4 corner tiles hart1..hart4 x $tile_pieces pieces + 2 VDD/VSS sentinels)"

echo "==== $BASE : stage 2a -- pad-net patch (REUSED $PATCHER) ===="
[ -f "$PATCHER" ] || die "no $PATCHER"
python3 "$PATCHER" "$netlist" || die "pad patch"

echo "==== $BASE : stage 2b -- append the full tile netlist (collision-safe) ===="
# CP5 FINDING: the CHIP FABRIC and the FROZEN tile collateral can define the
# same module name (genus uniquifies per run) -- the penta chip's ClkGate_2
# (VDD/VSS) vs the tile's ClkGate_2 (VDD_SW) FATALed Pegasus with NVN-13300.
# CP1 D6 only covers tile-vs-ORCHESTRATOR names. cp5_fix_module_collisions.py
# does the concat and renames any collider in the TILE COPY only (never in the
# shared pvs/hart_tile.lvs.v), with its own before/after guards.
python3 cp5_fix_module_collisions.py "$netlist" "$TILE_NETLIST" "$full" || die "module-collision concat"
grep -q "^module hart_tile" "$full" || die "$full has no hart_tile module -- concat failed"
[ "$(grep -c '^module hart_tile' "$full")" -eq 1 ] || \
    die "$full has more than one hart_tile module (a stub survived -- the F2a attempt-3 trap)"
# PENTA-SPECIFIC: the orchestrator subtree must be IN the chip netlist (the
# prep script's D6 strip deletes the TILE modules and keeps the orch_ ones --
# if that ever inverts, LVS would compare a chip with no fifth hart).
n_orch=$(grep -c '^module orch_' "$full" || true)
[ "$n_orch" -gt 0 ] || die "$full contains NO orch_* modules -- the orchestrator subtree is missing"
echo "     $full  $(wc -c < "$full") bytes, $(grep -c '^module ' "$full") modules, $n_orch orch_* modules"

echo "==== $BASE : stage 2c -- hart_tile PORT-WIDTH AGREEMENT gate ===="
# WHY THIS GATE EXISTS (2026-08-26). The chip netlist and the appended tile
# netlist come from two different P&R runs on two different schedules. Every
# other gate in this script checks the tile collateral against the TILE's own
# products; none of them checks it against the CHIP cut it is about to be
# concatenated into. Verilog does not complain when the two disagree: a
# 12-element concatenation bound to an 11-bit port is truncated and every bit
# of the bus shifts, silently. Innovus, elaborating the same skew, emits only
# a warning (IMPVL-361) and continues.
#
# MEASURED: cpr8's chip netlist binds twelve terms to .tcm_ext_addr; the tile
# netlist of the matching vintage declares [11:0]; the post-re-LEF tile cut
# declares [10:0]. Pairing cpr8 with the newer tile would have handed LVS a
# quietly wrong address bus on all four hardened harts.
#
# The check is structural, not tcm-specific: for every bussed port of
# hart_tile it compares the width the tile module DECLARES against the number
# of terms the chip netlist BINDS at each hart_tile instantiation.
python3 - "$full" <<'PY' || die "hart_tile port-width disagreement (see above)"
import re, sys
txt = open(sys.argv[1]).read()

m = re.search(r'^module hart_tile\s*\((.*?)\);(.*?)^endmodule', txt, re.S | re.M)
if not m:
    print("PORTGATE FATAL: no 'module hart_tile' found in", sys.argv[1]); sys.exit(1)
body = m.group(2)
declared = {}
for d in re.finditer(r'^\s*(?:input|output|inout)\s*\[\s*(\d+)\s*:\s*(\d+)\s*\]\s*([A-Za-z_][\w$]*)\s*;', body, re.M):
    hi, lo, name = int(d.group(1)), int(d.group(2)), d.group(3)
    declared[name] = abs(hi - lo) + 1
print("PORTGATE: hart_tile declares %d bussed ports" % len(declared))

insts = [mm for mm in re.finditer(r'^\s{2,}hart_tile\s+(\S+)\s*\(', txt, re.M)]
if not insts:
    print("PORTGATE FATAL: no hart_tile INSTANTIATION found"); sys.exit(1)
print("PORTGATE: %d hart_tile instantiations to check" % len(insts))

bad = 0
for mm in insts:
    inst = mm.group(1)
    # slice the instantiation: from '(' to the matching ');' at depth 0
    i = txt.index('(', mm.end() - 1)
    depth = 0
    for j in range(i, len(txt)):
        if txt[j] == '(':
            depth += 1
        elif txt[j] == ')':
            depth -= 1
            if depth == 0:
                break
    blob = txt[i + 1:j]
    for pm in re.finditer(r'\.([A-Za-z_][\w$]*)\s*\(', blob):
        port = pm.group(1)
        if port not in declared:
            continue
        k = pm.end() - 1
        d = 0
        for t in range(k, len(blob)):
            if blob[t] == '(':
                d += 1
            elif blob[t] == ')':
                d -= 1
                if d == 0:
                    break
        expr = blob[k + 1:t].strip()
        if expr.startswith('{'):
            inner = expr[1:expr.rindex('}')]
            # top-level comma count inside the concatenation
            d2 = 0
            n = 1
            for c in inner:
                if c in '{[(':
                    d2 += 1
                elif c in '}])':
                    d2 -= 1
                elif c == ',' and d2 == 0:
                    n += 1
            bound = n
        else:
            # a bare identifier binds the whole port; nothing to compare
            continue
        if bound != declared[port]:
            print("PORTGATE MISMATCH: %s .%s -- chip binds %d bits, tile declares %d"
                  % (inst, port, bound, declared[port]))
            bad += 1
if bad:
    print("PORTGATE FATAL: %d port-width disagreements between the chip netlist and the" % bad)
    print("                appended tile netlist. These are SILENT in Verilog: the extra")
    print("                bits are dropped and the bus shifts. Pair the chip cut with the")
    print("                tile netlist of its own vintage (TILE_NETLIST=<file>), or")
    print("                re-harden the chip onto the current tile.")
    sys.exit(1)
print("PORTGATE: all bussed hart_tile ports agree -- OK")
PY

echo "==== $BASE : stage 3 -- restamp labels after the concat ===="
touch "$labels"
echo "==== $BASE : collateral ready ===="

echo
echo "Next (one heavy run at a time, shared licenses):"
echo "  cd ~/vestarv/signoff_mp && source ~/vestarv/cdspaths.sh"
echo "  make drc BLOCK=mcu_castalia_penta"
echo "  make ant BLOCK=mcu_castalia_penta"
echo "  make lvs BLOCK=mcu_castalia_penta"
