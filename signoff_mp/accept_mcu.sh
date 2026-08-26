#!/bin/bash
# PG4: MCU assembly acceptance driver -- SERIALIZED, from the session-3 recipe
# (netlist+labels -> strmin -> LVS -> blockdrc -> ant25). Lives in signoff_mp/
# because the session-scratchpad copy died with its session (session-3 trap).
#
# STALE-READBACK TRAP (session 3): a parallel blockdrc once raced strmout and
# served a 6-result rpt for a 604-result GDS. Every stage here runs to
# completion before the next starts, results/ is wiped first, and the final
# summary re-checks rpt-vs-gds mtimes.
#
# Prereqs (done by the session driver, checked here):
#   * fresh out/MCU_MP.gds2 + dbs/MCU_MP.signoff.innovus.dat from make
#   * dbs/.../MCU.mode re-patched to "-tapeOut false" (restore fatals on the
#     3 timing-less analog abstracts otherwise; the .mode wins over any
#     setCheckMode issued before restoreDesign)
#
# usage: ./accept_mcu.sh [skip_netlist]

set -u
cd "$(dirname "$0")"
GDS=../innovus/common/MCU_MP/out/MCU_MP.gds2
DB=../innovus/common/MCU_MP/dbs/MCU_MP.signoff.innovus.dat

die() { echo "ACCEPT_MCU FATAL: $*"; exit 1; }

[ -f "$GDS" ] || die "no $GDS"

if [ "${1:-}" != "skip_netlist" ]; then
    echo "==== stage 1: MCU LVS netlist (innovus batch) ===="
    grep -q -- "-tapeOut false" "$DB/MCU.mode" || die "$DB/MCU.mode not patched (-tapeOut still true)"
    innovus -no_gui -batch -files tcl/mcu_lvs_netlist.tcl -log pvs/mcu_lvs_netlist \
        -overwrite > /dev/null 2>&1
    [ -s pvs/MCU.lvs.v ] || die "pvs/MCU.lvs.v missing/empty"
    [ pvs/MCU.lvs.v -nt "$GDS" ] || die "pvs/MCU.lvs.v older than $GDS (netlist gen failed?)"
fi

echo "==== stage 2: labels + full CDL ===="
python3 gen_mcu_lvslabels.py pvs/hart_tile.lvslabels pvs/MCU.lvslabels || die "label gen"
[ pvs/hart_tile.lvs.v -nt ../innovus/common/hart_tile/out/hart_tile.lef ] || \
    echo "WARN: pvs/hart_tile.lvs.v predates the tile LEF -- confirm it is the F2j netlist"
cat pvs/MCU.lvs.v pvs/hart_tile.lvs.v > pvs/MCU_full.lvs.v

echo "==== stage 3: strmin ===="
./strmin_gds.sh MCU_MP_signoff MCU "$GDS" || die "strmin"

echo "==== stage 4: LVS (full CDL) ===="
# pvs/lvs_mcu_ctl: lvs_report_max -all (deck silently caps sections at 1000)
# + the four lvs_cpoint bindings VDD_SW_H<h> <-> Xhart<h>/VDD_SW (without
# them the matcher cannot anchor 4 identical switched-rail networks; the
# dead-wrapper class 504/tile + hart0's 1027 headers unmatch)
./lvs.sh MCU_MP_signoff MCU pvs/MCU_full.lvs.v lvs_include_mcu pvs/lvs_mcu_ctl || die "lvs.sh rc"

# NB: the staleness check runs PER STAGE, right after its drc.sh -- each
# drc.sh re-strmouts into the SAME layout.gds, so an end-of-run mtime compare
# false-alarms on every rule but the last (cost one bogus FATAL on 2026-07-12).
check_fresh() {
    rpt=calibre/MCU_MP_signoff/MCU/results/$1.rpt
    lay=calibre/MCU_MP_signoff/MCU/layout.gds
    [ "$rpt" -nt "$lay" ] || die "STALE READBACK: $rpt older than $lay"
}

echo "==== stage 5: blockdrc ===="
rm -rf calibre/MCU_MP_signoff/MCU/results
./drc.sh MCU_MP_signoff MCU blockdrc || die "blockdrc"
check_fresh blockdrc

echo "==== stage 6: ant25 ===="
./drc.sh MCU_MP_signoff MCU ant25 || die "ant25"
check_fresh ant25

echo "==== summary ===="
for r in blockdrc ant25; do
    rpt=calibre/MCU_MP_signoff/MCU/results/$r.rpt
    echo "-- $r RULECHECK totals (nonzero):"
    grep "TOTAL Result Count" "$rpt" | awk -F'= ' '$2+0>0' | head -40 || true
done
rep=$(ls -t pvs/MCU_MP_signoff/MCU/*.rep 2>/dev/null | head -1)
echo "-- LVS: $rep"
grep -E "Run Result|MISMATCH|^ *MATCH" "$rep" 2>/dev/null | head -5
echo "ACCEPT_MCU: all stages ran serialized; inspect the totals above."
