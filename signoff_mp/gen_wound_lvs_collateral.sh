#!/bin/bash
# Wound respin (staged 2026-07-26): build the LVS collateral for the two wound
# signoff blocks -- mcu_wound (assembly, cell MCU) and chip_top_wound (LQFP-100
# pad-ring chip). This is the accept_chip.sh stage-1/2 pattern, promoted from a
# hand-typed recipe to a script because the wound cut needs it twice.
#
# WHAT IT PRODUCES (exactly what signoff_mp/Makefile's NETLIST/LABELS point at):
#   block:  pvs/MCU_WOUND.lvs.v            (assembly only, from the cut's DB)
#           pvs/MCU_WOUND.lvslabels        (same session, VDD_SW_H0..3)
#           pvs/MCU_WOUND_full.lvs.v       = MCU_WOUND.lvs.v + hart_tile.lvs.v
#   chip:   pvs/chip_top_wound.lvs.v       (chip only, from the cut's DB)
#           pvs/chip_top_wound.lvslabels   (same session, VDD_SW_H0..3)
#           pvs/chip_top_wound_full.lvs.v  = patched chip + hart_tile.lvs.v
#
# WHY THE CONCATENATION (F2a devlog, mcu_dp attempts 2-4): a netlist that BOXES
# hart_tile against a FLAT layout hits the 1M-net matcher threshold and aborts;
# an empty tile stub keeps the schematic side small and reproduces the same
# NVN-7090. The proven recipe (accept_mcu.sh / accept_chip.sh stage 2) appends
# the FULL tile netlist, no stub -- 8.8M-device flat compare. `module hart_tile`
# must be the LAST module in the _full file.
#
# ORDERING NOTE (lvs.sh G0 staleness gate): lvs.sh FATALs when the labels file
# is older than the netlist it is given (= the _full file). The innovus step
# writes the labels, then this script appends the tile netlist, so the labels
# would end up older by seconds. The final `touch` restamps them. That is NOT a
# provenance override: the pre-check below refuses to restamp anything that is
# older than the netlist the SAME innovus run just wrote. Real cross-cut
# staleness still trips the gate.
#
# usage: ./gen_wound_lvs_collateral.sh block|chip|both [skip_netlist]
#   skip_netlist = reuse the existing pvs/<X>.lvs.v + labels, redo patch+concat.
#
# Prereqs: source ~/vestarv/cdspaths.sh (innovus on PATH); the wound cut's
# dbs/<X>.signoff.innovus.dat + out/<X>.xsim.v present; pvs/hart_tile.lvs.v and
# pvs/hart_tile.lvslabels from the SAME tile cut the wound flows consumed
# (out/hart_tile.lef / .gds2). BATCH ONLY -- one heavy run at a time.

set -u
cd "$(dirname "$0")"

MODE=${1:-both}
SKIP=${2:-}
INN_ROOT=../innovus/common   # per-block layout: block dir = $INN_ROOT/<base>
PVS=pvs
TILE_NETLIST=$PVS/hart_tile.lvs.v

die() { echo "WOUND_LVS FATAL: $*"; exit 1; }

case "$MODE" in
    block|chip|both) ;;
    *) die "usage: $0 block|chip|both [skip_netlist]" ;;
esac

# ---- shared tile-cut gates (A7 / G0) ----------------------------------------
[ -f "$TILE_NETLIST" ] || die "$TILE_NETLIST missing -- regen via tcl/hart_tile_lvs_netlist.tcl"
[ -f "$PVS/hart_tile.lvslabels" ] || die "$PVS/hart_tile.lvslabels missing (same tcl dumps it)"
[ "$TILE_NETLIST" -nt "$INN_ROOT/hart_tile/out/hart_tile.lef" ] || \
    die "$TILE_NETLIST predates $INN_ROOT/hart_tile/out/hart_tile.lef -- the tile netlist is not this tile cut"
[ "$PVS/hart_tile.lvslabels" -nt "$TILE_NETLIST" ] || \
  [ ! "$PVS/hart_tile.lvslabels" -ot "$TILE_NETLIST" ] || \
    die "$PVS/hart_tile.lvslabels is older than $TILE_NETLIST -- re-dump both from one cut"

# ---- one block -------------------------------------------------------------
# $1 = basename (MCU_WOUND | chip_top_wound), $2 = tcl, $3 = pad patcher ("" = none)
do_block() {
    local base=$1 tcl=$2 patcher=$3
    local netlist=$PVS/$base.lvs.v
    local labels=$PVS/$base.lvslabels
    local full=$PVS/${base}_full.lvs.v

    echo "==== $base : stage 1 -- netlist + same-cut labels (innovus batch) ===="
    [ -d "$INN_ROOT/$base/dbs/$base.signoff.innovus.dat" ] || die "no $INN_ROOT/$base/dbs/$base.signoff.innovus.dat"
    [ -f "$INN_ROOT/$base/out/$base.xsim.v" ] || die "no $INN_ROOT/$base/out/$base.xsim.v"
    if [ "$SKIP" != "skip_netlist" ]; then
        command -v innovus > /dev/null || die "innovus not on PATH -- source ~/vestarv/cdspaths.sh"
        ( cd "$INN_ROOT/$base" && innovus -no_gui -batch \
            -log "log/${base}_lvs_regen" -overwrite \
            -files "../../../signoff_mp/$tcl" ) || die "$tcl rc"
    fi
    [ -s "$netlist" ] || die "$netlist missing/empty (the A7 sanity gate deletes a bad netlist)"
    [ -s "$labels" ]  || die "$labels missing/empty -- lvs.sh would SILENTLY skip the VDD_SW injection"
    # the labels must not predate the netlist the same run just wrote
    [ ! "$labels" -ot "$netlist" ] || die "$labels older than $netlist -- not one session"

    if [ -n "$patcher" ]; then
        echo "==== $base : stage 2a -- pad-net patch ===="
        python3 "$patcher" "$netlist" || die "pad patch"
    fi

    echo "==== $base : stage 2b -- append the full tile netlist ===="
    cat "$netlist" "$TILE_NETLIST" > "$full" || die "concat"
    grep -q '^module hart_tile' "$full" || die "$full has no hart_tile module -- concat failed"
    [ "$(grep -c '^module hart_tile' "$full")" -eq 1 ] || \
        die "$full has more than one hart_tile module (a stub survived -- the F2a attempt-3 trap)"
    echo "     $full  $(wc -c < "$full") bytes, $(grep -c '^module ' "$full") modules"

    echo "==== $base : stage 3 -- restamp labels after the concat ===="
    touch "$labels"
    echo "     $labels  $(wc -l < "$labels") labels"
    echo "==== $base : collateral ready ===="
}

case "$MODE" in
    block) do_block MCU_WOUND      tcl/mcu_wound_lvs_netlist.tcl      "" ;;
    chip)  do_block chip_top_wound tcl/chip_top_wound_lvs_netlist.tcl patch_chip_pads_wound.py ;;
    both)  do_block MCU_WOUND      tcl/mcu_wound_lvs_netlist.tcl      ""
           do_block chip_top_wound tcl/chip_top_wound_lvs_netlist.tcl patch_chip_pads_wound.py ;;
esac

echo
echo "Next (one heavy run at a time, shared licenses):"
echo "  cd ~/vestarv/signoff_mp && source ~/vestarv/cdspaths.sh"
echo "  make lvs BLOCK=mcu_wound        # LABELS=pvs/MCU_WOUND.lvslabels (explicit)"
echo "  make lvs BLOCK=chip_top_wound   # LABELS default pvs/chip_top_wound.lvslabels"
echo "                                  # + pvs/hart_tile_vddsw.lvslabels via the chip_top* case"
