#!/bin/bash
# =============================================================================
# run_irq_sys.sh -- standalone self-checking sim for the MP interrupt system.
#
# Compiles + elaborates + simulates clint.vhd (M5b) and irq_router.vhd (M7a)
# against the combined self-checking testbench hdl/MCU_MP/tb/irq_sys_tb.vhd
# (msip IPIs, 64-bit mtime/mtimecmp mtip levels, router rows/fan-out, ENU
# contiguous-packing guard, hart_tile gating-equation integration checks).
# PASS iff the log contains the scoreboard banner "ALL CHECKS PASSED".
#
# This dir lives under xcelium/ (gitignored), like behavioral_mp/ and
# ram_images/. The RTL and TB ARE tracked.
#
# Usage:  ./run_irq_sys.sh
# =============================================================================
set -e
source ~/vestarv/cdspaths.sh

HDL=~/vestarv/hdl/MCU_MP
RUN_DIR="$(cd "$(dirname "$0")" && pwd)/work_irq_sys"
rm -rf "$RUN_DIR"; mkdir -p "$RUN_DIR"; cd "$RUN_DIR"

# dependency order: constants -> MemoryMap (tb uses its IRQB_*/NUM_IRQS),
# then the two DUTs, then the TB that binds them
xrun -64bit -V200X -licqueue -top irq_sys_tb \
    "$HDL/constants.vhd" \
    "$HDL/MemoryMap.vhd" \
    "$HDL/clint.vhd" \
    "$HDL/irq_router.vhd" \
    "$HDL/tb/irq_sys_tb.vhd" 2>&1 | tee run.log

echo "=================================================="
if grep -q "ALL CHECKS PASSED" run.log; then
    echo "  irq_sys (clint + irq_router): PASS"
    exit 0
else
    echo "  irq_sys (clint + irq_router): FAIL (banner not found)"
    exit 1
fi
