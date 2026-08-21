#!/bin/sh
# check_tracer_independence.sh -- the R-DS5 mechanical guard.
#
# W3's binding ruling: vesta_tracer.vhd implements v1_retire_enumeration §3-R0
# with its OWN logic, and vesta.vhd's retire_now implements it separately. Two
# independent implementations agreeing over 4,668,509 records is EVIDENCE; one
# implementation observed twice is a TAUTOLOGY. R-DS5 therefore forbids the
# tracer from consuming retire_now / inst_retired, and notes that the port-list
# absence is a stronger guard than the comment that asserts it (method rule 16:
# prefer an edit that satisfies a simple check).
#
# This is that check. rc 0 = independent, rc 1 = the independence has been lost.
#
# Placement rationale (S3): NOT a git hook -- hooks are untracked, and the
# gate-drift saga (tools/cosim/gate/ + check_gate_files.py) is the precedent for
# what happens when a guard lives only on one disk. NOT folded into
# check_gate_files.py either: that script's rc means "the gate files match the
# tracked record", and overloading it would blur what a failure means.

set -u
# CHECK_TRACER_ROOT lets a caller that does not keep this script one level
# below the repo root say where the tree is; the bazel sh_test stages the
# script and the tracer in separate runfiles subtrees and sets it.
# Unset, the derivation from $0 is exactly what it always was.
ROOT="${CHECK_TRACER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
TRACER="$ROOT/hdl/common/vesta/vesta_tracer.vhd"

if [ ! -f "$TRACER" ]; then
    echo "check_tracer_independence: FATAL -- tracer not found at $TRACER"
    exit 2
fi

# POSITIVE CONTROL FIRST. An expected-zero needs independent proof the
# instrument was live (method rule 5): a typo'd path, a renamed file or a
# broken grep all report a clean zero otherwise. `current_state` is a symbol
# the tracer certainly does contain.
control=$(grep -c "current_state" "$TRACER")
if [ "$control" -eq 0 ]; then
    echo "check_tracer_independence: FATAL -- positive control found 0"
    echo "  the grep or the file is wrong; a zero below would be meaningless"
    exit 2
fi

rc=0
for sym in retire_now inst_retired; do
    # word-boundary match, comments excluded, so a mention in prose does not
    # trip the guard -- what is forbidden is CONSUMING the signal.
    hits=$(sed 's/--.*//' "$TRACER" | grep -cE "(^|[^A-Za-z0-9_])${sym}([^A-Za-z0-9_]|$)")
    if [ "$hits" -ne 0 ]; then
        echo "check_tracer_independence: FAIL -- '${sym}' appears in $hits code line(s) of vesta_tracer.vhd"
        sed 's/--.*//' "$TRACER" | grep -nE "(^|[^A-Za-z0-9_])${sym}([^A-Za-z0-9_]|$)"
        rc=1
    fi
done

if [ "$rc" -eq 0 ]; then
    echo "check_tracer_independence: OK -- retire_now and inst_retired appear in no code line of vesta_tracer.vhd"
    echo "  (positive control: 'current_state' found on $control line(s), so the grep is live)"
fi
exit $rc
