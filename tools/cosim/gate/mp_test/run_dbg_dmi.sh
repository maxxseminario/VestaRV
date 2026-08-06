#!/bin/bash
# =============================================================================
# run_dbg_dmi.sh -- D2 acceptance instrument J1: the DM register-map
# conformance bench (hdl/common/tb/dbg_dmi_tb.vhd).
#
#   ./run_dbg_dmi.sh [<rcf-basename>]
#   NHARTS_G=18 ./run_dbg_dmi.sh          # the N=18 shape of the same file
#
# PASS iff the log prints "ALL CHECKS PASSED" and contains no "CHECK FAILED".
#
# AT UNIMPLEMENTED HEAD THIS IS EXPECTED TO FAIL TO ELABORATE -- that is the
# instrument's part-1 seen-to-FAIL demonstration (d2_spec.md section 8).  The
# errors name the missing dmi_* formals on entity MCU; do not "fix" it by
# deleting them.
#
# WHY IT USES THE behavioral_mp CELL LIST
#   The bench instantiates the WHOLE MCU (see the bench header for why it has
#   to), so it needs the same ordered file list the suite compiles, with
#   riscv_tb.vhd swapped for this bench.  Taking the list from
#   behavioral_mp/cell_list_behavioral.txt rather than copying it means a DM
#   file added to that list (d2_spec section 6 makes it BASE_CELL_LIST) is
#   picked up here automatically and cannot be forgotten in one place only.
#
# D2MUT_LIST points the compile at the mutation scratch list
# (xcelium/riscv_test/d2mut/cell_list_d2mut.txt), the D1MUT_HDL/D1MUT_TAG
# pattern that let the D1 validation pass run sealed mutants without touching
# the working tree.  Build it that way from the start, deliberately.
#
# This dir is under xcelium/ (gitignored); the BENCH is tracked
# (hdl/common/tb/dbg_dmi_tb.vhd).  Precedent: run_dbg_iface.sh.
#
# NEVER pipe this through `head` (SIGPIPE kills the sim, leaving a stale log).
# =============================================================================
source ~/vestarv/cdspaths.sh

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
RT="$BASE_DIR/../riscv_test"
RCF="${1:-xxxrv32ui-p-simple.rcf}"
NH="${NHARTS_G:-4}"

LIST="${D2MUT_LIST:-$RT/behavioral_mp/cell_list_behavioral.txt}"
LISTDIR="$(dirname "$LIST")"
WORK="$BASE_DIR/dbg_dmi_work${D2MUT_TAG:+_$D2MUT_TAG}"
LOG="$BASE_DIR/dbg_dmi${D2MUT_TAG:+_$D2MUT_TAG}.log"

TESTFILE="../rcf/$RCF"
if [ ${#TESTFILE} -ne 29 ]; then
    echo "ERROR: TEST_FILE '$TESTFILE' is ${#TESTFILE} chars; riscv_tb's generic"
    echo "       and this bench's are a FIXED 29-char string."
    exit 1
fi
if [ ! -f "$RT/rcf/$RCF" ]; then
    echo "ERROR: no such image: $RT/rcf/$RCF"
    exit 1
fi

rm -rf "$WORK"
mkdir -p "$WORK"

# The list is relative to its own directory, and the TEST_FILE generic is
# relative to the RUN directory -- so the run happens where the list expects,
# and the work library is redirected out of the way.
cd "$LISTDIR"

FILES="$(grep -v 'riscv_tb\.vhd' "$LIST") $HOME/vestarv/hdl/common/tb/dbg_dmi_tb.vhd"

# WALL-CLOCK TIMEOUT, and it is not decoration.  MEASURED at authoring time
# (2026-08-05): the MCU-level bench environment in this file does NOT free-run
# at HEAD -- simulation time freezes around 0.7 ms with xmsim at 100% CPU,
# which is CLAUDE.md's combinational-loop signature, and it happens with the
# stimulus process idle (a variant that only waits proves it is not the check
# sequence).  Root cause NOT found in the D2 acceptance wave; reported to
# Fable.  A VHDL `wait for` watchdog cannot fire when simulation time itself
# stops advancing, so the bound has to be in WALL clock.  The bench also
# carries a 60 ms sim-time watchdog for the ordinary case.
TMO="${DBG_DMI_TIMEOUT:-2400}"   # 900 was short of the knob-ON tree; see the rc=124 arm
timeout "$TMO" xrun \
    $FILES \
    -top dbg_dmi_tb \
    -generic "TEST_FILE=>\"$TESTFILE\"" \
    -generic "NHARTS_G=>$NH" \
    -v200x \
    -work work \
    -xmlibdirname "$WORK/xcelium.d" \
    -access +r \
    -controlrelax nlstex \
    -relax \
    > "$LOG" 2>&1
rc=$?

cat "$LOG"

if [ $rc -eq 124 ]; then
    # A wall-clock timeout is NOT automatically a check failure, and reporting
    # it as one is a false FAIL (validation wave, 2026-08-06).  Measured on the
    # knob-ON tree: the bench completed all 47 checks and printed ALL CHECKS
    # PASSED, and the timeout then fired during its POST-CHECK free-run -- the
    # SS5.1 slowness, which R-D2-6(4) refuted as a hang but which is still
    # slower than this default on a build that actually has a Debug Module.
    # So: distinguish "timed out with the check sequence complete and clean"
    # from "timed out mid-sequence".  Neither is silently upgraded to PASS.
    if grep -q "ALL CHECKS PASSED" "$LOG" && ! grep -q "CHECK FAILED" "$LOG"; then
        echo "dbg_dmi: CHECKS PASSED ($(grep -c '^CHECK' "$LOG") checks, NHARTS_G=$NH)"
        echo "dbg_dmi: but the run did NOT reach a clean exit inside ${TMO}s --"
        echo "         the post-check free-run was still going.  Raise"
        echo "         DBG_DMI_TIMEOUT if you need the clean exit on record."
        exit 3
    fi
    echo "dbg_dmi: FAIL (WALL-CLOCK TIMEOUT after ${TMO}s, check sequence INCOMPLETE:"
    echo "         $(grep -c '^CHECK' "$LOG") checks reached, $(grep -c '^CHECK FAILED' "$LOG") failed) -- see $LOG"
    exit 2
fi
if [ $rc -ne 0 ]; then
    echo "dbg_dmi: FAIL (xrun exited rc=$rc) -- see $LOG"
    exit 1
fi
if grep -q "ALL CHECKS PASSED" "$LOG" && ! grep -q "CHECK FAILED" "$LOG"; then
    echo "dbg_dmi: PASS (NHARTS_G=$NH)"
    exit 0
else
    echo "dbg_dmi: FAIL -- see $LOG"
    exit 1
fi
