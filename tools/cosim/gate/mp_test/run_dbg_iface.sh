#!/bin/bash
# =============================================================================
# run_dbg_iface.sh -- D1 acceptance instrument I2: the port-conformance bench.
#
# Compiles + elaborates + simulates hdl/common/tb/dbg_iface_tb.vhd against the
# real hart_tile (two instances: debug ports connected / omitted).  See the
# bench header for what each check means.
#
# PASS iff the log prints "ALL CHECKS PASSED" and contains no "CHECK FAILED".
#
# AT UNIMPLEMENTED HEAD THIS IS EXPECTED TO FAIL TO ELABORATE -- that is the
# instrument's part-1 seen-to-FAIL demonstration (d1_spec.md 5).  The error
# names the missing generics/ports; do not "fix" it by deleting them.
#
# This dir is under xcelium/ (gitignored); the BENCH is tracked
# (hdl/common/tb/dbg_iface_tb.vhd).  Precedent: run_pmp_unit.sh.
# =============================================================================
source ~/vestarv/cdspaths.sh

# D1MUT_HDL lets the D1 validation pass point this bench at the mutation
# scratch RTL (xcelium/riscv_test/d1mut/rtl) instead of the working tree.
# Unset = the working tree, which is what an ordinary run means.
HDL=${D1MUT_HDL:-~/vestarv/hdl/common}
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$BASE_DIR/dbg_iface_work${D1MUT_TAG:+_$D1MUT_TAG}"
LOG="$BASE_DIR/dbg_iface${D1MUT_TAG:+_$D1MUT_TAG}.log"

rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

xrun -V200X -q \
    -top dbg_iface_tb \
    -access +r \
    -controlrelax nlstex \
    "$HDL/commune/fixed_float_types_c.vhdl" \
    "$HDL/commune/fixed_pkg_c.vhdl" \
    "$HDL/commune/FPMac.vhd" \
    "$HDL/commune/FPSigmoid.vhd" \
    "$HDL/constants.vhd" \
    "$HDL/macros/macros.vhd" \
    "$HDL/MemoryMap.vhd" \
    "$HDL/sim/ClkGate.vhd" \
    "$HDL/vesta/div.vhd" \
    "$HDL/vesta/alu.vhd" \
    "$HDL/vesta/extend.vhd" \
    "$HDL/vesta/regfile_sbirq.vhd" \
    "$HDL/vesta/irq_handler.vhd" \
    "$HDL/vesta/loadext.vhd" \
    "$HDL/vesta/store_ext.vhd" \
    "$HDL/vesta/branch_valid.vhd" \
    "$HDL/vesta/fpu.vhd" \
    "$HDL/vesta/fpu_simple.vhd" \
    "$HDL/vesta/datapath.vhd" \
    "$HDL/vesta/maindec.vhd" \
    "$HDL/vesta/controller.vhd" \
    "$HDL/vesta/c_dec.vhd" \
    "$HDL/vesta/csr_unit.vhd" \
    "$HDL/vesta/pmp_unit.vhd" \
    "$HDL/vesta/vesta_tracer.vhd" \
    "$HDL/vesta/vesta.vhd" \
    "$HDL/sim/ARM_IP_RAM.vhd" \
    "$HDL/adddec.vhd" \
    "$HDL/hart_tile.vhd" \
    "$HDL/tb/dbg_iface_tb.vhd" \
    > "$LOG" 2>&1
rc=$?

cat "$LOG"

if [ $rc -ne 0 ]; then
    echo "dbg_iface: FAIL (xrun exited rc=$rc) -- see $LOG"
    exit 1
fi

if grep -q "ALL CHECKS PASSED" "$LOG" && ! grep -q "CHECK FAILED" "$LOG"; then
    echo "dbg_iface: PASS"
    exit 0
else
    echo "dbg_iface: FAIL -- see $LOG"
    exit 1
fi
