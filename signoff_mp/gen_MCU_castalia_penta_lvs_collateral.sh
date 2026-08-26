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
TILE_NETLIST=$PVS/hart_tile.lvs.v
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
[ "$TILE_NETLIST" -nt "$INN/../hart_tile/out/hart_tile.lef" ] || \
    die "$TILE_NETLIST predates $INN/../hart_tile/out/hart_tile.lef -- not this tile cut"
[ ! "$PVS/hart_tile.lvslabels" -ot "$TILE_NETLIST" ] || \
    die "$PVS/hart_tile.lvslabels is older than $TILE_NETLIST -- re-dump both from one cut"

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
CUTSEL="${CUTSEL:-cpr6.signoff}"
XSIMSEL="${XSIMSEL:-cpr6}"
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

echo "==== $BASE : stage 3 -- restamp labels after the concat ===="
touch "$labels"
echo "==== $BASE : collateral ready ===="

echo
echo "Next (one heavy run at a time, shared licenses):"
echo "  cd ~/vestarv/signoff_mp && source ~/vestarv/cdspaths.sh"
echo "  make drc BLOCK=mcu_castalia_penta"
echo "  make ant BLOCK=mcu_castalia_penta"
echo "  make lvs BLOCK=mcu_castalia_penta"
