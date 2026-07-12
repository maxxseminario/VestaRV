#!/bin/bash
# =============================================================================
# run_arbiter.sh  (M3c) -- standalone self-checking sim for mp_arbiter.
#
# Compiles + elaborates + simulates hdl/common/mp_arbiter.vhd against its
# self-checking testbench hdl/common/tb/mp_arbiter_tb.vhd (4 synthetic masters
# contending for one shared single-port RAM). PASS iff the log contains the
# scoreboard banner "ALL CHECKS PASSED".
#
# This dir lives under xcelium/ (gitignored), like behavioral_mp/ and
# ram_images/. The RTL (mp_arbiter.vhd) and TB (mp_arbiter_tb.vhd) ARE tracked.
#
# Usage:  ./run_arbiter.sh
# =============================================================================
set -e
source ~/vestarv/cdspaths.sh

HDL=~/vestarv/hdl/common
RUN_DIR="$(cd "$(dirname "$0")" && pwd)/work"
rm -rf "$RUN_DIR"; mkdir -p "$RUN_DIR"; cd "$RUN_DIR"

# dependency order: entity/arch (mp_arbiter) before the TB that binds it
xrun -64bit -V200X -licqueue -top mp_arbiter_tb \
    "$HDL/mp_arbiter.vhd" \
    "$HDL/tb/mp_arbiter_tb.vhd" 2>&1 | tee run.log

echo "=================================================="
if grep -q "ALL CHECKS PASSED" run.log; then
    echo "  mp_arbiter: PASS"
    exit 0
else
    echo "  mp_arbiter: FAIL (banner not found)"
    exit 1
fi
