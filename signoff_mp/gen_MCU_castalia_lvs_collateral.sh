#!/bin/bash
# Wound-QUAD chip (staged 2026-07-27): build the LVS collateral for the
# MCU_castalia signoff block. CHIP-ONLY clone of
# gen_wound_lvs_collateral.sh -- there is NO block leg here, because
# MCU_castalia is a FLAT chip run: the MCU_WOUND hierarchy is placed and
# routed inside the chip, there is no separate assembly P&R cut, and therefore
# no `mcu_wound_quad` signoff block to build collateral for.
#
# WHAT IT PRODUCES (exactly what signoff_mp/Makefile's MCU_castalia
# NETLIST/LABELS point at):
#   pvs/MCU_castalia.lvs.v        (chip only, from the cut's own DB)
#   pvs/MCU_castalia.lvslabels    (same session, VDD_SW_H0..3, 4-orient)
#   pvs/MCU_castalia_full.lvs.v   = patched chip + pvs/hart_tile.lvs.v
#
# WHY THE CONCATENATION (F2a devlog, mcu_dp attempts 2-4): a netlist that BOXES
# hart_tile against a FLAT layout hits the 1M-net matcher threshold and aborts;
# an empty tile stub keeps the schematic side small and reproduces the same
# NVN-7090. The proven recipe appends the FULL tile netlist, no stub.
# `module hart_tile` must be the LAST module in the _full file.
#
# PAD PATCHER: patch_chip_pads_wound.py is REUSED VERBATIM, not cloned. It
# binds by INSTANCE NAME only (the cell type is the anonymous `\b[A-Z0-9_]+`
# prefix of its regex and appears nowhere in BIND), it takes the netlist path
# as argv[1], and MCU_castalia shares the very same padlist file
# (tcl/chip_top_wound_padlists.tcl) and the same wrapper instance names as
# chip_top_wound -- so its 17-entry BIND table applies unchanged. Cloning it
# would only create a second copy to keep in sync.
#
# ORDERING NOTE (lvs.sh G0 staleness gate): lvs.sh FATALs when the labels file
# is older than the netlist it is given (= the _full file). The innovus step
# writes the labels, then this script appends the tile netlist, so the labels
# would end up older by seconds. The final `touch` restamps them. That is NOT a
# provenance override: the pre-check below refuses to restamp anything that is
# older than the netlist the SAME innovus run just wrote. Real cross-cut
# staleness still trips the gate.
#
# usage: ./gen_MCU_castalia_lvs_collateral.sh [skip_netlist]
#   skip_netlist = reuse the existing pvs/MCU_castalia.lvs.v + labels,
#                  redo the pad patch + concat only.
#
# Prereqs: source ~/vestarv/cdspaths.sh (innovus on PATH); the wound-quad cut's
# ../innovus/common/MCU_castalia/dbs/MCU_castalia.signoff.innovus.dat +
# out/MCU_castalia.xsim.v present; pvs/hart_tile.lvs.v and
# pvs/hart_tile.lvslabels from the SAME tile cut the flow consumed
# (out/hart_tile.lef / .gds2). BATCH ONLY -- one heavy run at a time.

set -u
cd "$(dirname "$0")"

SKIP=${1:-}
INN=../innovus/common/MCU_castalia   # per-block layout
PVS=pvs
TILE_NETLIST=$PVS/hart_tile.lvs.v
BASE=MCU_castalia
TCL=tcl/${BASE}_lvs_netlist.tcl
PATCHER=patch_chip_pads_wound.py

die() { echo "WOUND_QUAD_LVS FATAL: $*"; exit 1; }

case "$SKIP" in
    ""|skip_netlist) ;;
    *) die "usage: $0 [skip_netlist]" ;;
esac

# ---- shared tile-cut gates (A7 / G0) ----------------------------------------
[ -f "$TILE_NETLIST" ] || die "$TILE_NETLIST missing -- regen via tcl/hart_tile_lvs_netlist.tcl"
[ -f "$PVS/hart_tile.lvslabels" ] || die "$PVS/hart_tile.lvslabels missing (same tcl dumps it)"
[ "$TILE_NETLIST" -nt "$INN/../hart_tile/out/hart_tile.lef" ] || \
    die "$TILE_NETLIST predates $INN/../hart_tile/out/hart_tile.lef -- the tile netlist is not this tile cut"
[ "$PVS/hart_tile.lvslabels" -nt "$TILE_NETLIST" ] || \
  [ ! "$PVS/hart_tile.lvslabels" -ot "$TILE_NETLIST" ] || \
    die "$PVS/hart_tile.lvslabels is older than $TILE_NETLIST -- re-dump both from one cut"

netlist=$PVS/$BASE.lvs.v
labels=$PVS/$BASE.lvslabels
full=$PVS/${BASE}_full.lvs.v

echo "==== $BASE : stage 1 -- netlist + same-cut labels (innovus batch) ===="
[ -d "$INN/dbs/$BASE.signoff.innovus.dat" ] || die "no $INN/dbs/$BASE.signoff.innovus.dat"
[ -f "$INN/out/$BASE.xsim.v" ] || die "no $INN/out/$BASE.xsim.v"
[ -f "$TCL" ] || die "no $TCL"
if [ "$SKIP" != "skip_netlist" ]; then
    command -v innovus > /dev/null || die "innovus not on PATH -- source ~/vestarv/cdspaths.sh"
    ( cd "$INN" && innovus -no_gui -batch \
        -log "log/${BASE}_lvs_regen" -overwrite \
        -files "../../../signoff_mp/$TCL" ) || die "$TCL rc"
fi
[ -s "$netlist" ] || die "$netlist missing/empty (the A7 sanity gate deletes a bad netlist)"
[ -s "$labels" ]  || die "$labels missing/empty -- lvs.sh would SILENTLY skip the VDD_SW injection"
# the labels must not predate the netlist the same run just wrote
[ ! "$labels" -ot "$netlist" ] || die "$labels older than $netlist -- not one session"
# 4 corner tiles x the tile-local piece count, PLUS the 2 Stage-J VDD:/VSS:
# short-sentinel texts the lvs tcl appends (they make FIND_SHORTS
# short-sensitive; see the tcl); a short file means the xform bailed
# 2026-08-25 SENTINEL CARRY: the tile dump ends in its own VDD:/VSS: short
# sentinels.  The top-level dump no longer aliases those per hart (they made
# spurious VSS_H1-vs-VSS shorts), so they are not counted as carried pieces.
tile_pieces=$(awk 'NF>=4 && $4!="VDD:" && $4!="VSS:"' "$PVS/hart_tile.lvslabels" | wc -l)
want=$(( 4 * tile_pieces + 2 ))
got=$(wc -l < "$labels")
[ "$got" -eq "$want" ] || die "$labels has $got labels, expected $want (4 x $tile_pieces tile pieces + 2 sentinels)"
echo "     $labels  $got labels (4 corner tiles x $tile_pieces pieces + 2 VDD/VSS sentinels)"

echo "==== $BASE : stage 2a -- pad-net patch (REUSED $PATCHER) ===="
[ -f "$PATCHER" ] || die "no $PATCHER"
python3 "$PATCHER" "$netlist" || die "pad patch"

echo "==== $BASE : stage 2b -- append the full tile netlist ===="
cat "$netlist" "$TILE_NETLIST" > "$full" || die "concat"
grep -q '^module hart_tile' "$full" || die "$full has no hart_tile module -- concat failed"
[ "$(grep -c '^module hart_tile' "$full")" -eq 1 ] || \
    die "$full has more than one hart_tile module (a stub survived -- the F2a attempt-3 trap)"
echo "     $full  $(wc -c < "$full") bytes, $(grep -c '^module ' "$full") modules"

echo "==== $BASE : stage 3 -- restamp labels after the concat ===="
touch "$labels"
echo "==== $BASE : collateral ready ===="

echo
echo "Next (one heavy run at a time, shared licenses):"
echo "  cd ~/vestarv/signoff_mp && source ~/vestarv/cdspaths.sh"
echo "  make drc BLOCK=MCU_castalia"
echo "  make ant BLOCK=MCU_castalia"
echo "  make lvs BLOCK=MCU_castalia   # LABELS default pvs/MCU_castalia.lvslabels"
echo "                                       # + pvs/hart_tile_vddsw.lvslabels via the chip_top* case"
