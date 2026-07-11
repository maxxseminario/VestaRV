#!/bin/bash
# Standalone runner for the SPI-flash (XIP extended-memory) testbench.
#   compile -> elaborate -> simulate the single top SPI_flash_tb:sim.
# PASS iff the log contains the scoreboard banner "ALL CHECKS PASSED".
#
# Usage:  ./xrun.sh
source ~/vestarv/cdspaths.sh

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_PATH="$DIR/log"
LIB_PATH="$DIR/xcelium.d"
TOP="SPI_flash_tb:sim"

cd "$DIR"
echo "=== [1/3] Compiling HDL ==="
[ -d "$LIB_PATH" ] && rm -r "$LIB_PATH"
mkdir -p "$LOG_PATH" "$LIB_PATH/work"

cat > "$DIR/cds.lib" <<LIB
SOFTINCLUDE ${XCELIUM_HOME}/tools/xcelium/files/cds.lib
DEFINE work ./xcelium.d/work
LIB

VHDL_FILES=()
for f in $(< "$DIR/cell_list_behavioral.txt"); do
    case "$f" in \#*) continue ;; esac
    case "${f##*.}" in
        vhd|vhdl) VHDL_FILES+=("$f") ;;
    esac
done

echo "  xmvhdl: ${#VHDL_FILES[@]} file(s)"
xmvhdl -V200X -WORK work -CONTROLRELAX nlstex -RELAX "${VHDL_FILES[@]}" \
    2>&1 | tee "$LOG_PATH/compile_vhdl.log"
[ "${PIPESTATUS[0]}" -ne 0 ] && { echo "VHDL compile failed — see $LOG_PATH/compile_vhdl.log"; exit 1; }

echo ""
echo "=== [2/3] Elaborating $TOP ==="
xmelab -ACCESS +r "work.${TOP}" 2>&1 | tee "$LOG_PATH/elab.log"
[ "${PIPESTATUS[0]}" -ne 0 ] && { echo "Elaboration failed — see $LOG_PATH/elab.log"; exit 1; }

echo ""
echo "=== [3/3] Simulating $TOP ==="
entity="${TOP%%:*}"
xmsim "work.${TOP}" -input batch_run.tcl -licqueue -LOGFILE "$LOG_PATH/${entity}.log" 2>&1 \
    | tee "$LOG_PATH/${entity}.sim.stdout"

echo ""
if grep -q "ALL CHECKS PASSED" "$LOG_PATH/${entity}.log" 2>/dev/null; then
    echo "  RESULT: PASS  ($LOG_PATH/${entity}.log)"
    exit 0
else
    echo "  RESULT: FAIL  — see $LOG_PATH/${entity}.log"
    exit 1
fi
