#!/bin/bash
# =============================================================================
# run_irq_router.sh -- M19 irq_router PLIC-lite unit proof.
#
# Compiles + elaborates + simulates hdl/common/irq_router.vhd against
# hdl/common/tb/irq_router_tb.vhd (no other DUT dependencies). PASS iff the
# log prints "ALL CHECKS PASSED" for EVERY configuration in the sweep:
#   - Castalia shape: NHARTS=4,  MW=2 (defaults)
#   - Argus shape:    NHARTS=18, MW=5
#
# Usage:
#   ./run_irq_router.sh          # both shapes
#
# This dir lives under xcelium/ (gitignored); the RTL and TB ARE tracked.
# =============================================================================
source ~/vestarv/cdspaths.sh

HDL=~/vestarv/hdl/common
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$BASE_DIR/irq_router_work"
LOG="$BASE_DIR/irq_router.log"

rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

overall=0
: > "$LOG"

for CFG in "4 2" "18 5"; do
    set -- $CFG
    NH=$1; MW=$2
    CLOG="$WORK/run_n${NH}.log"
    echo "=== irq_router_tb NHARTS=$NH MW=$MW ===" | tee -a "$LOG"
    xrun -V200X -q \
        -top irq_router_tb \
        -generic "irq_router_tb.NHARTS=>$NH" \
        -generic "irq_router_tb.MW=>$MW" \
        "$HDL/irq_router.vhd" \
        "$HDL/tb/irq_router_tb.vhd" \
        > "$CLOG" 2>&1
    rc=$?
    cat "$CLOG" >> "$LOG"
    if [ $rc -ne 0 ]; then
        echo "  xrun exited rc=$rc -- see $LOG"
        overall=1
        continue
    fi
    if grep -q "ALL CHECKS PASSED" "$CLOG" && ! grep -q "CHECK FAILED" "$CLOG"; then
        echo "  PASS"
    else
        echo "  FAIL -- see $LOG"; overall=1
    fi
done

if [ $overall -eq 0 ]; then
    echo "irq_router unit proof: PASS (both shapes)"
else
    echo "irq_router unit proof: FAIL -- see $LOG"
fi
exit $overall
