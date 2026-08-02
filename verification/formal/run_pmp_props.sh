#!/bin/sh
# verification/formal/run_pmp_props.sh  (R-S4-3 item 6)
# TRACKED runner for the pmp grant-function set.  Every pmp result before
# this ran on a reconstructed command line, which is not reproducible.
# NOTE: `set -e`/`set -u` are deliberately NOT used -- cdspaths.sh
# references a never-defined assuraPath, so `set -u` kills the shell
# before xrun ever runs (measured; it is what made run_fabric_props.sh
# die silently on a clean shell).
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/cdspaths.sh" >/dev/null 2>&1
HDL="$ROOT/hdl/common"; F="$ROOT/verification/formal"
MODE=${MODE:-props}          # props | witness
WORK=${WORK:-/tmp/s4_pmp_$$}
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK" || { echo "FATAL: no work dir"; exit 2; }
case "$MODE" in
  props)   PF="$F/pmp_grant_props.psl" ;;
  witness) PF="$F/pmp_grant_witness.psl" ;;
  *) echo "FATAL: MODE must be props|witness"; exit 2 ;;
esac
xrun -V200X -assert_vhdl -top pmp_formal_tb \
     "$HDL/constants.vhd" "$HDL/vesta/pmp_unit.vhd" "$F/pmp_formal_tb.vhd" \
     -propfile_vhdl "$PF" > run.log 2>&1
if ! grep -q "Assertions:" run.log; then
    echo "FATAL: the run did not elaborate -- no assertions were compiled"
    echo "  see $WORK/run.log"; exit 2      # rc 2 = INFRASTRUCTURE, not a property failure
fi
fires=$(grep -c ASRTST run.log)
echo "MODE=$MODE  fires=$fires  $(grep -E 'Assertions:' run.log | tr -s ' ')"
echo "work: $WORK"
if [ "$MODE" = witness ]; then
    for w in $(grep -oE "^\s+W_[A-Z_0-9]+" "$PF" | tr -d ' '); do
        printf "  %-18s %s\n" "$w" "$(grep -c ":$w has failed" run.log)"
    done
    [ "$fires" -gt 0 ] && exit 0            # witnesses are SUPPOSED to fire
    echo "FAIL: no witness fired -- the stimulus never reached any property"; exit 1
fi
[ "$fires" -eq 0 ] && exit 0
echo "FAIL: $fires property fire(s)"; exit 1
