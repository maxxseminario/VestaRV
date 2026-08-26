#!/bin/bash
# CQ6 chip-top (chip_top_quad) signoff acceptance driver -- SERIALIZED. Quad
# analogue of accept_chip.sh (C0), differences called out inline. Lives in
# signoff_mp/. Netlist -> pad-patch -> full CDL -> labels -> strmin (guarded)
# -> LVS -> blockdrc -> ant25. Reproducible gate commands for the orchestrator.
#
# Prereqs:
#   * dbs/chip_top_quad.signoff.innovus.dat (CQ5 routed+signoff DB; its .mode
#     already carries `setCheckMode -tapeOut false` -- NO patch needed, unlike C0)
#   * out/chip_top_quad.gds2 (streamOut'd via tcl/chip_top_quad_strmout.tcl)
#   * pvs/hart_tile.lvs.v = M19c 233-pin tile netlist (shared with C0/CQ; the
#     tile is orientation-only for CQ)
#   * guarded OA from strmin_gds.sh (chip_top_quad_signoff) -- NEVER a raw strmin
#
# DELIBERATE DEVIATION FROM C0's accept_chip.sh: DRC deck is `blockdrc`
# (decks/blockdrc.rul, v2.6_2a, FULL_CHIP off) per the CQ6 brief + classify_drc.py
# core/ring split, NOT C0's `chipdrc` FULL_CHIP. Run chipdrc too if a seal/pad
# FULL_CHIP signoff is wanted; the CQ6 gate is blockdrc-core-waived-only + ant25 0.
#
# usage: ./accept_chip_quad.sh [skip_netlist]

set -u
cd "$(dirname "$0")"
CELL=chip_top_quad
LIB=${CELL}_signoff
GDS=../innovus/common/$CELL/out/$CELL.gds2
DB=../innovus/common/$CELL/dbs/$CELL.signoff.innovus.dat

die() { echo "ACCEPT_CHIP_QUAD FATAL: $*"; exit 1; }
[ -f "$GDS" ] || die "no $GDS (run tcl/chip_top_quad_strmout.tcl first)"

if [ "${1:-}" != "skip_netlist" ]; then
    echo "==== stage 1: chip LVS netlist (innovus batch) ===="
    grep -q -- "-tapeOut false" "$DB/$CELL.mode" || die "$DB/$CELL.mode not -tapeOut false"
    innovus -no_gui -batch -files tcl/chip_top_quad_lvs_netlist.tcl \
        -log pvs/chip_top_quad_lvs_netlist -overwrite > /dev/null 2>&1
    [ -s pvs/$CELL.lvs.v ] || die "pvs/$CELL.lvs.v missing/empty"
fi

echo "==== stage 2: pad-net patch + full CDL ===="
python3 patch_chip_pads_quad.py pvs/$CELL.lvs.v || die "pad patch"
cat pvs/$CELL.lvs.v pvs/hart_tile.lvs.v > pvs/${CELL}_full.lvs.v

echo "==== stage 3: labels (VDD_SW_H0..3, 4-corner mirrored) ===="
python3 gen_quad_lvslabels.py pvs/hart_tile.lvslabels pvs/$CELL.lvslabels || die "labels"

echo "==== stage 4: strmin (guarded, XSTRM-287 myshkin gate) ===="
./strmin_gds.sh $LIB $CELL "$GDS" || die "strmin (gate fired or error)"

echo "==== stage 5: LVS (full CDL) ===="
./lvs.sh $LIB $CELL pvs/${CELL}_full.lvs.v lvs_include_chip pvs/lvs_chip_quad_ctl || die "lvs.sh rc"

echo "==== stage 6: blockdrc (v2.6_2a) ===="
rm -rf calibre/$LIB/$CELL/results
./drc.sh $LIB $CELL blockdrc || die "blockdrc"

echo "==== stage 7: antenna (ant25) ===="
./drc.sh $LIB $CELL ant25 || die "ant25"

echo "==== summary ===="
for r in blockdrc ant25; do
    db=calibre/$LIB/$CELL/results/$r.db
    echo "-- $r classify (core box 0 0 2690 2690) --"
    [ -f "$db" ] && python3 classify_drc.py "$db" 0 0 2690 2690 || echo "  (no $db)"
done
rep=$(ls -t pvs/$LIB/$CELL/*.rep 2>/dev/null | head -1)
echo "-- LVS: $rep"; grep -E "Run Result" pvs/$LIB/$CELL/*.cls 2>/dev/null | head -1
echo "ACCEPT_CHIP_QUAD: inspect the totals above."
