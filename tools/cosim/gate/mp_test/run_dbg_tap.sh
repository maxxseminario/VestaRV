#!/bin/bash
# =============================================================================
# run_dbg_tap.sh -- D3 acceptance instrument J3: the JTAG PORT bench
# (hdl/common/tb/dbg_tap_tb.vhd).
#
#   ./run_dbg_tap.sh [<rcf-basename>]
#   NHARTS_G=18 ./run_dbg_tap.sh          # the N=18 shape of the same file
#
# PASS iff the log prints "ALL CHECKS PASSED" and contains no "CHECK FAILED".
#
# AT UNIMPLEMENTED HEAD THIS IS EXPECTED TO FAIL TO ELABORATE -- that is the
# instrument's part-1 seen-to-FAIL demonstration (d3_spec.md section 6).  The
# errors name the FIVE missing jtag formals (tck/tms/tdi/tdo/trstn) on entity
# MCU; do not "fix" it by deleting them.  Note the bench also names the eight
# dmi_* formals, so on a debug-OFF build you get thirteen missing formals and
# on a D2 debug-ON build you get exactly five -- the count itself tells you
# which tree you are on, which is worth reading before diagnosing anything.
#
# WHY IT USES THE behavioral_mp CELL LIST (the run_dbg_dmi.sh argument,
# inherited): the bench instantiates the WHOLE MCU, so it needs the same
# ordered file list the suite compiles, with riscv_tb.vhd swapped for this
# bench.  Taking the list rather than copying it means a new RTL file added
# there cannot be forgotten here.
#
# D3_LIST points the compile at another list -- the generator's knob-ON staged
# list (xcelium/riscv_test/verify_castaliadebug/cell_list_behavioral.txt or
# verify_argusdebug/...), or a mutation scratch list.  That is the D1MUT/D2MUT
# pattern and it is how the sealed mutants run without touching the tree.
#
# This dir is under xcelium/ (gitignored); the BENCH is tracked
# (hdl/common/tb/dbg_tap_tb.vhd).  Precedent: run_dbg_dmi.sh, run_dbg_iface.sh.
#
# NEVER pipe this through `head` (SIGPIPE kills the sim, leaving a stale log).
# =============================================================================
source ~/vestarv/cdspaths.sh

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
RT="$BASE_DIR/../riscv_test"
RCF="${1:-xxxrv32ui-p-simple.rcf}"
NH="${NHARTS_G:-4}"

LIST="${D3_LIST:-$RT/behavioral_mp/cell_list_behavioral.txt}"
LISTDIR="$(dirname "$LIST")"
WORK="$BASE_DIR/dbg_tap_work${D3_TAG:+_$D3_TAG}"
LOG="$BASE_DIR/dbg_tap${D3_TAG:+_$D3_TAG}.log"

# The TEST_FILE generic is a FIXED 29-char string in every bench in this tree.
TESTFILE="${D3_TESTFILE:-../rcf/$RCF}"
if [ ${#TESTFILE} -ne 29 ]; then
    echo "ERROR: TEST_FILE '$TESTFILE' is ${#TESTFILE} chars; this bench's"
    echo "       generic is a FIXED 29-char string."
    exit 1
fi

rm -rf "$WORK"
mkdir -p "$WORK"

# A PRIVATE cds.lib, and it is NOT tidiness -- it is a measured fix.
# behavioral_mp/cds.lib contains `DEFINE work ./xcelium.d/work`, a RELATIVE
# path that OVERRIDES -xmlibdirname, so a run launched from that directory
# writes into the library the whole 143-test suite shares.  That library
# accumulates repeat compiles of the vendor pad Verilog, and the next bench to
# instantiate a pad gets `*E,MULVLG ... Multiple Options for Binding Specified
# Verilog Unit (work.PDUW16SDGZ_G)` -- an error about the LIBRARY that reads
# exactly like an error about the BENCH.  Measured at D3 authoring time
# (2026-08-06): J1 (run_dbg_dmi.sh) reproduces it identically at HEAD, while
# the D2-era log of J1's successful 47-check run (dbg_dmi_dbgON.log) contains
# ZERO MULVLG because it went through a d2arm_* scratch directory with its own
# cds.lib.  So the working invocation always had a private library and the
# default one never did.  This makes that explicit instead of accidental.
cat > "$WORK/cds.lib" <<EOF
SOFTINCLUDE \$CDS_INST_DIR/tools/xcelium/files/cds.lib
DEFINE work $WORK/xcelium.d/work
EOF

# The list is relative to its own directory, and the TEST_FILE generic is
# relative to the RUN directory -- so the run happens where the list expects it.
cd "$LISTDIR"

if [ ! -f "$TESTFILE" ]; then
    echo "ERROR: no such image relative to $LISTDIR: $TESTFILE"
    exit 1
fi

FILES="$(grep -v 'riscv_tb\.vhd' "$LIST") $HOME/vestarv/hdl/common/tb/dbg_tap_tb.vhd"

# WALL-CLOCK TIMEOUT.  The J1 runner needed one because the MCU-level bench
# environment was MEASURED not to free-run at D2 (sim time freezes ~0.7 ms with
# xmsim at 100% CPU, root cause never found, reported to Fable).  This bench
# shares that environment, so it inherits the hazard and the arm: a timeout
# with the check sequence COMPLETE and clean is reported differently from a
# timeout mid-sequence, and neither is silently upgraded to PASS.
TMO="${DBG_TAP_TIMEOUT:-2400}"
timeout "$TMO" xrun \
    $FILES \
    -top dbg_tap_tb \
    -generic "TEST_FILE=>\"$TESTFILE\"" \
    -generic "NHARTS_G=>$NH" \
    -v200x \
    -work work \
    -cdslib "$WORK/cds.lib" \
    -xmlibdirname "$WORK/xcelium.d" \
    -access +r \
    -controlrelax nlstex \
    -relax \
    > "$LOG" 2>&1
rc=$?

cat "$LOG"

if [ $rc -eq 124 ]; then
    if grep -q "ALL CHECKS PASSED" "$LOG" && ! grep -q "CHECK FAILED" "$LOG"; then
        echo "dbg_tap: CHECKS PASSED ($(grep -c '^CHECK' "$LOG") checks, NHARTS_G=$NH)"
        echo "dbg_tap: but the run did NOT reach a clean exit inside ${TMO}s --"
        echo "         raise DBG_TAP_TIMEOUT if you need the clean exit on record."
        exit 3
    fi
    echo "dbg_tap: FAIL (WALL-CLOCK TIMEOUT after ${TMO}s, check sequence INCOMPLETE:"
    echo "         $(grep -c '^CHECK' "$LOG") checks reached, $(grep -c '^CHECK FAILED' "$LOG") failed) -- see $LOG"
    exit 2
fi
if [ $rc -ne 0 ]; then
    echo "dbg_tap: FAIL (xrun exited rc=$rc) -- see $LOG"
    echo "dbg_tap: missing-formal errors, if any:"
    grep -c 'FMLUNK' "$LOG" 2>/dev/null | sed 's/^/         FMLUNK count: /'
    exit 1
fi
if grep -q "ALL CHECKS PASSED" "$LOG" && ! grep -q "CHECK FAILED" "$LOG"; then
    echo "dbg_tap: PASS (NHARTS_G=$NH)"
    exit 0
else
    echo "dbg_tap: FAIL -- see $LOG"
    exit 1
fi
