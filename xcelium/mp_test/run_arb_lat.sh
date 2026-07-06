#!/bin/bash
# =============================================================================
# run_arb_lat.sh -- M10 arbiter latency-insensitivity proof.
#
# Compiles + elaborates + simulates mp_arbiter.vhd + resv_unit.vhd +
# mutex_bank.vhd against hdl/MCU_MP/tb/arb_lat_tb.vhd, which wraps the
# master<->arbiter boundary in N_DELAY pipeline-register stages (both
# directions) emulating the M13 registered tile boundary. PASS iff EVERY
# N_DELAY in the sweep prints "ALL CHECKS PASSED".
#
# Usage:
#   ./run_arb_lat.sh                     # sweep N_DELAY = 0 1 2 (the M10 gate)
#   DELAYS="2" ./run_arb_lat.sh          # single depth
#   BREAK_MODE=1 DELAYS="2" ./run_arb_lat.sh   # negative control: early lock
#                                        # drop -- MUST FAIL
#   BREAK_MODE=2 DELAYS="2" ./run_arb_lat.sh   # negative control: req piped
#                                        # one stage shallower than addr/wdata
#                                        # (only meaningful N_DELAY>0) --
#                                        # MUST FAIL
#
# This dir lives under xcelium/ (gitignored); the RTL and TB ARE tracked.
# =============================================================================
source ~/vestarv/cdspaths.sh

HDL=~/vestarv/hdl/MCU_MP
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
DELAYS=${DELAYS:-"0 1 2"}
BREAK_MODE=${BREAK_MODE:-0}

overall=0
summary=""

for d in $DELAYS; do
    RUN_DIR="$BASE_DIR/work_arb_lat_d${d}"
    rm -rf "$RUN_DIR"; mkdir -p "$RUN_DIR"; cd "$RUN_DIR"

    xrun -64bit -V200X -licqueue -top arb_lat_tb \
        -generic "N_DELAY => $d" \
        -generic "BREAK_MODE => $BREAK_MODE" \
        "$HDL/mp_arbiter.vhd" \
        "$HDL/resv_unit.vhd" \
        "$HDL/mutex_bank.vhd" \
        "$HDL/tb/arb_lat_tb.vhd" > run.log 2>&1

    if grep -q "ALL CHECKS PASSED" run.log; then
        summary="$summary
  N_DELAY=$d (BREAK_MODE=$BREAK_MODE): PASS"
    else
        summary="$summary
  N_DELAY=$d (BREAK_MODE=$BREAK_MODE): FAIL   (see $RUN_DIR/run.log)"
        overall=1
    fi
done

echo "=================================================="
echo "arb_lat_tb sweep:$summary"
echo "=================================================="
exit $overall
