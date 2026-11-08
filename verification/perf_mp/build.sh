#!/bin/bash
# Compile the default Castalia RTL plus the perf monitor and elaborate one snapshot per STALL_D in $SNAP_D.
# $1 = run dir under xcelium/riscv_test (relative paths in cell_list.txt assume that depth).
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/tools/source_cdspaths.sh" >/dev/null 2>&1
# cell_list.txt names the pad library as $VESTA_TSMC65_IP; expanded below.
VESTA_TSMC65_IP="${VESTA_TSMC65_IP:-$HOME/lib/TSMC65-IP}"
cd "$1" || exit 1
mkdir -p xcelium.d/work log
cat > cds.lib <<LIB
SOFTINCLUDE ${XCELIUM_HOME}/tools/xcelium/files/cds.lib
DEFINE work $PWD/xcelium.d/work
LIB
V=(); H=()
for f in $(< cell_list.txt); do f="${f//\$VESTA_TSMC65_IP/$VESTA_TSMC65_IP}"; case "${f##*.}" in v) V+=("$f");; vhd|vhdl) H+=("$f");; esac; done
xmvlog -WORK work "${V[@]}" > log/vlog.log 2>&1 || { tail log/vlog.log; exit 1; }
xmvhdl -V200X -WORK work -CONTROLRELAX nlstex -RELAX "${H[@]}" > log/vhdl.log 2>&1 || { grep -n "\*E\|\*F" log/vhdl.log | head; exit 1; }
xmvhdl -V200X -WORK work -CONTROLRELAX nlstex -RELAX ../../../verification/perf_mp/perf_mon.vhd ../../../verification/perf_mp/perf_top.vhd > log/mon.log 2>&1 || { grep -n "\*E\|\*F" log/mon.log | head; exit 1; }
for d in ${SNAP_D:-0}; do
    xmelab -ACCESS +rw -GENERIC "perf_top:STALL_D=>$d" -SNAPSHOT work.perf_d$d work.perf_top:behavioral > log/elab$d.log 2>&1 || { grep -n "\*E\|\*F" log/elab$d.log | head; exit 1; }
done
echo BUILD OK
