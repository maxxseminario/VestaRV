#!/bin/bash
# Chip-top (chip_top / chip_top_argus) acceptance driver -- SERIALIZED, adapts
# accept_mcu.sh up to the connected pad-ring wrapper. Netlist -> pad-patch ->
# full CDL -> strmin (guarded) -> LVS -> chip DRC. Lives in signoff_mp/.
#
# STATUS (2026-07-14): DRC clean (chip-integration); LVS pad-ring/power NOT yet
# converged -- see .devlog/2026-07-14-chip-top-drc-lvs.md for the single-variable
# resume plan. This driver captures the reproducible flow so far.
#
# Prereqs:
#   * fresh out/chip_top.gds2 + dbs/chip_top.final.innovus.dat from the P&R flow
#   * dbs/.../chip_top.mode patched "-tapeOut false" (else the 3 analog abstracts
#     inherited via mcu0 fatal at restore; .mode wins over setCheckMode)
#   * current pvs/hart_tile.lvs.v (M19c 233-pin -- regen via
#     tcl/hart_tile_lvs_netlist.tcl if stale; the on-disk copy was pre-M19)
#   * guarded OA from strmin_gds.sh (chip_top_signoff) -- NEVER a raw strmin
#
# usage: ./accept_chip.sh <cell>            (cell = chip_top_argus)
# The chip_top branch died with the flat-era innovus/common/dbs (deleted 2026-07-27);
# its tcl/chip_lvs_netlist.tcl moved to attic/ 2026-07-29 -- stage 1 below still names
# it, so run with skip_netlist (or point -files at tcl/chip_argus_lvs_netlist.tcl).
#        ./accept_chip.sh <cell> skip_netlist

set -u
cd "$(dirname "$0")"
CELL=${1:-chip_top_argus}   # chip_top (C0 row layout) deleted 2026-07-27
GDS=../innovus/common/$CELL/out/$CELL.gds2
DB=../innovus/common/$CELL/dbs/$CELL.final.innovus.dat

die() { echo "ACCEPT_CHIP FATAL: $*"; exit 1; }
[ -f "$GDS" ] || die "no $GDS"

if [ "${2:-}" != "skip_netlist" ]; then
    echo "==== stage 1: chip LVS netlist (innovus batch) ===="
    grep -q -- "-tapeOut false" "$DB/$CELL.mode" || die "$DB/$CELL.mode not patched (-tapeOut still true)"
    innovus -no_gui -batch -files tcl/chip_lvs_netlist.tcl -log pvs/chip_lvs_netlist \
        -overwrite > /dev/null 2>&1
    [ -s pvs/$CELL.lvs.v ] || die "pvs/$CELL.lvs.v missing/empty"
fi

echo "==== stage 2: pad-net patch + full CDL ===="
# bind the pinless IO-domain supply pads to their power globals (Myshkin
# vesta_chip precedent). idempotent.
python3 patch_chip_pads.py pvs/$CELL.lvs.v || die "pad patch"
[ pvs/hart_tile.lvs.v -nt ../innovus/common/hart_tile/out/hart_tile.lef ] || \
    echo "WARN: pvs/hart_tile.lvs.v predates the tile LEF -- confirm it is the M19c 233-pin netlist"
cat pvs/$CELL.lvs.v pvs/hart_tile.lvs.v > pvs/${CELL}_full.lvs.v

echo "==== stage 3: labels ===="
# VDD_SW_H0..3 per-tile switched-rail texts (mcu0 at 0,0 -> MCU coords == chip
# coords) + power-rail labels are pre-generated in pvs/$CELL.lvslabels; lvs.sh
# injects them into the $CELL struct at strmout time. (Regenerate the VDD_SW part
# with gen_mcu_lvslabels.py pvs/hart_tile.lvslabels pvs/$CELL.lvslabels, then
# append the power-rail lines -- see the devlog.)
[ -f pvs/$CELL.lvslabels ] || echo "WARN: pvs/$CELL.lvslabels missing (VDD_SW + power labels)"

echo "==== stage 4: strmin (guarded) ===="
[ -d "$CELL"_signoff ] || ./strmin_gds.sh ${CELL}_signoff $CELL "$GDS" || die "strmin"

echo "==== stage 5: LVS (full CDL) ===="
./lvs.sh ${CELL}_signoff $CELL pvs/${CELL}_full.lvs.v lvs_include_chip pvs/lvs_chip_ctl || die "lvs.sh rc"

echo "==== stage 6: chip DRC (chipdrc FULL_CHIP) ===="
rm -rf calibre/${CELL}_signoff/$CELL/results
./drc.sh ${CELL}_signoff $CELL chipdrc || die "chipdrc"

echo "==== stage 7: antenna ===="
./drc.sh ${CELL}_signoff $CELL ant25 || die "ant25"

echo "==== summary ===="
for r in chipdrc ant25; do
    rpt=calibre/${CELL}_signoff/$CELL/results/$r.rpt
    echo "-- $r nonzero RULECHECK totals:"
    grep "TOTAL Result Count" "$rpt" 2>/dev/null | awk -F'= ' '($2+0)>0' | grep RULECHECK | head -60 || true
done
rep=$(ls -t pvs/${CELL}_signoff/$CELL/*.rep 2>/dev/null | head -1)
echo "-- LVS: $rep"; grep -E "Run Result|MISMATCH|MATCH" "$rep" 2>/dev/null | head -3
echo "ACCEPT_CHIP: inspect the totals above."
