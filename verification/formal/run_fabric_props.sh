#!/bin/sh
# verification/formal/run_fabric_props.sh
# S4: run arb_lat_tb's stimulus with the shared-fabric PSL properties bound.
# Runs FROM verification/formal/ with explicit paths -- measured to work, so
# no canonical-copy-in-xcelium dance is needed (the gate-drift pattern is only
# required for runners that MUST live under the gitignored xcelium/).
# NOT `set -u`: cdspaths.sh references a never-defined assuraPath, which
# kills the shell before xrun runs (measured -- this is what made the
# first version die on a clean shell with rc=1, indistinguishable from
# "a property failed").  rc is now disambiguated: 0 pass, 1 property
# failure, 2 INFRASTRUCTURE (nothing ran).
. ~/vestarv/cdspaths.sh >/dev/null 2>&1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HDL="$ROOT/hdl/common"
FORMAL="$ROOT/verification/formal"
DELAYS=${DELAYS:-"0 1 2"}
# MODE=props (default) -- expect 0 fires at every depth.
# MODE=witness -- bind the witness file instead; a witness is
# `assert never {trigger}`, so a "failure" is the SUCCESS signal and the
# run FAILS if any witness in the file never fired (PSL `cover` was
# measured decorative in this flow and is deliberately not used).
MODE=${MODE:-props}
case "$MODE" in
    props)   PROPS="$FORMAL/fabric_props.psl" ;;
    witness) PROPS="$FORMAL/fabric_witness.psl" ;;
    *) echo "FATAL: MODE must be props or witness (got '$MODE')"; exit 2 ;;
esac
WANT=$(grep -cE "^\s*W_[A-Z_0-9]+\s*:" "$PROPS")
WORK=${WORK:-/tmp/s4_formal_$$}
overall=0; summary=""
for d in $DELAYS; do
    RD="$WORK/d$d"; rm -rf "$RD"; mkdir -p "$RD"; cd "$RD"
    xrun -64bit -V200X -licqueue -assert_vhdl -top arb_lat_tb \
        -generic "N_DELAY => $d" -generic "BREAK_MODE => 0" -generic "N_MASTERS => 4" \
        "$HDL/mp_arbiter.vhd" "$HDL/resv_unit.vhd" "$HDL/mutex_bank.vhd" \
        "$HDL/tb/arb_lat_tb.vhd" \
        -propfile_vhdl "$PROPS" > run.log 2>&1
    if ! grep -q "Assertions:" run.log; then
        echo "FATAL: no assertions compiled at N_DELAY=$d -- see $RD/run.log"; exit 2
    fi
    fires=$(grep -c "ASRTST" run.log)
    bench=$(grep -c "ALL CHECKS PASSED" run.log)
    line=$(grep -E "^\s+Assertions:" run.log | tail -1)
    # The bench reaches a VERDICT (either line) or it never ran.  Only the
    # latter is infrastructure -- a failed bench check is a real finding.
    if ! grep -qE "ALL CHECKS PASSED|CHECKS FAILED" run.log; then
        echo "FATAL: bench reached no verdict at N_DELAY=$d -- see $RD/run.log"; exit 2
    fi
    if [ "$MODE" = props ]; then
        if [ "$fires" -eq 0 ] && [ "$bench" -ge 1 ]; then
            summary="$summary\n  N_DELAY=$d: PASS   bench=OK  property fires=0   [$line]"
        else
            summary="$summary\n  N_DELAY=$d: FAIL   bench_pass=$bench  fires=$fires   (see $RD/run.log)"
            overall=1
        fi
    else
        got=$(grep -oE "Assertion :W_[A-Z_0-9]+" run.log | sort -u | wc -l)
        if [ "$got" -eq "$WANT" ] && [ "$bench" -ge 1 ]; then
            summary="$summary\n  N_DELAY=$d: PASS   bench=OK  witnesses $got/$WANT fired  fires=$fires"
        else
            summary="$summary\n  N_DELAY=$d: FAIL   witnesses $got/$WANT fired -- stimulus gap   (see $RD/run.log)"
            overall=1
        fi
    fi
done
printf "==================================================\n"
printf "S4 fabric %s over arb_lat_tb:$summary\n" "$MODE"
printf "==================================================\n"
echo "work dir: $WORK"
exit $overall
