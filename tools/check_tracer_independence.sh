#!/bin/sh
# VestaRV: R-DS5 guard. vesta_tracer.vhd must not consume retire_now or
# inst_retired.
# The tracer implements v1_retire_enumeration 3-R0 with its own logic and
# vesta.vhd's retire_now implements it separately; two independent
# implementations agreeing is evidence, one observed twice is a tautology.
# rc 0 = independent, rc 1 = the independence is gone, rc 2 = the check is dead.

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

# Positive control first. An expected zero needs proof the instrument was live:
# a typo'd path, a renamed file or a broken grep all report a clean zero
# otherwise. `current_state` is a symbol the tracer certainly contains.
control=$(grep -c "current_state" "$TRACER")
if [ "$control" -eq 0 ]; then
    echo "check_tracer_independence: FATAL -- positive control found 0"
    echo "  the grep or the file is wrong; a zero below would be meaningless"
    exit 2
fi

rc=0
for sym in retire_now inst_retired; do
    # Word-boundary match with comments stripped: a mention in prose does not
    # trip the guard. What is forbidden is consuming the signal.
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
