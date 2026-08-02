#!/bin/sh
# verification/formal/run_fabric_formal.sh
# S4 (R-S4-3): the DIRECTED fabric bench -- mutex_bank claim/steal,
# resv_unit foreign-write kill, and the M8 grant-locked RMW window.
#
# MODE=props   (default) bind fabric_formal_props.psl   -- expect 0 fires
# MODE=witness           bind fabric_formal_witness.psl -- expect EVERY
#                        witness to fire at least once (non-vacuity).  A
#                        witness is `assert never {trigger}`, so a "failure"
#                        here is the SUCCESS signal; PSL `cover` was measured
#                        decorative in this flow and is deliberately not used.
#
# NOT `set -u`: cdspaths.sh references a never-defined assuraPath and would
# kill the shell before xrun runs, which is indistinguishable at the exit
# code from a real property failure.  rc: 0 pass, 1 property failure,
# 2 INFRASTRUCTURE (nothing compiled / nothing ran).
. ~/vestarv/cdspaths.sh >/dev/null 2>&1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HDL="$ROOT/hdl/common"
FORMAL="$ROOT/verification/formal"
MODE=${MODE:-props}
case "$MODE" in
    props)   PROPS="$FORMAL/fabric_formal_props.psl" ;;
    witness) PROPS="$FORMAL/fabric_formal_witness.psl" ;;
    *) echo "FATAL: MODE must be props or witness (got '$MODE')"; exit 2 ;;
esac
WORK=${WORK:-/tmp/s4_fabric_formal_$$}
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK" || exit 2

xrun -64bit -V200X -licqueue -assert_vhdl -top fabric_formal_tb \
    "$HDL/mp_arbiter.vhd" "$HDL/resv_unit.vhd" "$HDL/mutex_bank.vhd" \
    "$FORMAL/fabric_formal_tb.vhd" \
    -propfile_vhdl "$PROPS" > run.log 2>&1

if ! grep -q "Assertions:" run.log; then
    echo "FATAL: no assertions compiled -- see $WORK/run.log"; exit 2
fi
if ! grep -q "stimulus complete" run.log; then
    echo "FATAL: stimulus did not run to completion -- see $WORK/run.log"; exit 2
fi
fires=$(grep -c "ASRTST" run.log)
printf "==================================================\n"
printf "S4 directed fabric bench  MODE=%s  fires=%s\n" "$MODE" "$fires"
grep -oE "Assertion :[A-Z_0-9]+" run.log | sort | uniq -c
printf "work dir: %s\n" "$WORK"
printf "==================================================\n"

if [ "$MODE" = props ]; then
    [ "$fires" -eq 0 ] && exit 0
    echo "FAIL: $fires property fire(s)"; exit 1
else
    # every witness in the file must appear at least once
    want=$(grep -cE "^\s*W_[A-Z_0-9]+\s*:" "$PROPS")
    got=$(grep -oE "Assertion :W_[A-Z_0-9]+" run.log | sort -u | wc -l)
    [ "$got" -eq "$want" ] && exit 0
    echo "FAIL: only $got of $want witnesses fired -- stimulus gap"; exit 1
fi
