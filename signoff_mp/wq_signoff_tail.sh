#!/bin/bash
# Stage J: serialized signoff tail for chip_top_wound_quad (run AFTER make drc).
# One heavy Cadence job at a time, each gated on the previous rc.
# Progress/rc files: wq_ant.rc, wq_lvsregen.rc, wq_collat.rc, wq_lvs.rc
cd "$(dirname "$0")"
source ~/vestarv/cdspaths.sh   # NB: not set -u-safe (LD_LIBRARY_PATH unbound on first source)
set -u

echo "=== [1/4] ant25 ==="
make ant BLOCK=chip_top_wound_quad > wq_ant.console.log 2>&1
rc=$?; echo $rc > wq_ant.rc
[ $rc -ne 0 ] && { echo "ANT FAILED rc=$rc"; exit 1; }

echo "=== [2/4] LVS netlist + labels regen (innovus fresh-init + defIn) ==="
( cd ../innovus/common/chip_top_wound_quad && innovus -no_gui -overwrite -log log/wq_lvs_netlist \
    -files ../../../signoff_mp/tcl/chip_top_wound_quad_lvs_netlist.tcl ) > wq_lvsregen.console.log 2>&1
rc=$?; echo $rc > wq_lvsregen.rc
[ $rc -ne 0 ] && { echo "LVS NETLIST REGEN FAILED rc=$rc"; exit 1; }
# hard gates: products exist + same-session labels
[ -s pvs/chip_top_wound_quad.lvs.v ] || { echo "FATAL: chip netlist missing"; echo 3 > wq_lvsregen.rc; exit 1; }
[ -s pvs/chip_top_wound_quad.lvslabels ] || { echo "FATAL: labels missing"; echo 3 > wq_lvsregen.rc; exit 1; }

echo "=== [3/4] pad patch + tile concat -> _full ==="
./gen_wound_quad_lvs_collateral.sh > wq_collat.console.log 2>&1
rc=$?; echo $rc > wq_collat.rc
[ $rc -ne 0 ] && { echo "COLLATERAL FAILED rc=$rc"; exit 1; }
[ -s pvs/chip_top_wound_quad_full.lvs.v ] || { echo "FATAL: _full missing"; echo 3 > wq_collat.rc; exit 1; }

echo "=== [4/4] Pegasus LVS ==="
make lvs BLOCK=chip_top_wound_quad > wq_lvs.console.log 2>&1
rc=$?; echo $rc > wq_lvs.rc
echo "TAIL-DONE lvs_rc=$rc"
