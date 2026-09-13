#!/bin/sh
# VestaRV: run the core-level PMP suppression property set. The DUT is the whole
# core in the real testbench, so the stimulus is one staged `make verify`
# configuration's compile list plus one test wrapper.
#   CHIP=verify_castaliapmp TEST=rv32ua-p-pmpfq MODE=props ./run_core_pmp_props.sh
# MODE=props expects zero fires; MODE=witness expects every witness to fire, a
# silent one being a finding against the stimulus. rc 0 pass, 1 property or
# witness failure, 2 infrastructure. The staged config must have been built with
# ENABLE_PMP true: an ENABLE_PMP=false build compiles the properties and they are
# vacuous, which is what the witness file catches. `set -u` is absent because
# cdspaths.sh references a never-defined assuraPath and would kill the shell
# before xrun runs.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/cdspaths.sh" >/dev/null 2>&1
F="$ROOT/verification/formal"
CHIP=${CHIP:-verify_castaliapmp}
TEST=${TEST:-rv32ua-p-pmpfq}
MODE=${MODE:-props}
STAGE="$ROOT/xcelium/riscv_test/$CHIP"
WORK=${WORK:-/tmp/k4_corepmp_$$}

case "$MODE" in
  props)   PF="$F/core_pmp_props.psl" ;;
  witness) PF="$F/core_pmp_witness.psl" ;;
  *) echo "FATAL: MODE must be props|witness"; exit 2 ;;
esac

[ -d "$STAGE" ] || { echo "FATAL: no staged config at $STAGE"; exit 2; }
ENT="tb_$(echo "$TEST" | tr '-' '_')"
WRAP="$STAGE/wrappers/$ENT.vhd"
[ -f "$WRAP" ] || { echo "FATAL: no wrapper $WRAP (was $TEST selected by this config?)"; exit 2; }

# The polarity of the staged RTL is printed rather than assumed: an
# ENABLE_PMP=false stage runs green and proves nothing.
echo "stage : $STAGE"
grep -E "CORE_ENABLE_(PMP|UMODE|TRAPCSR|COMPRESSED)\s*:" "$STAGE/hdl/MemoryMap.vhd" | tr -s ' '

# Run in a scratch directory, never in the stage. The stage carries its own
# cds.lib pointing `work` at ./xcelium.d/work, which collides with xrun's
# library handling: every package body comes back "Intermediate file for package
# 'X' could not be loaded" and nothing elaborates. A run here would also clobber
# the compiled library the `make verify` flow owns. The wrapper's TEST_FILE
# generic is relative ("../<link>/<test>.rcf"), so the scratch dir gets a symlink
# of the same name one level up from CWD.
LINK=$(sed -n 's|.*"\.\./\([a-z0-9][a-z0-9][a-z0-9]\)/.*|\1|p' "$WRAP" | sed -n 1p)
[ -n "$LINK" ] || { echo "FATAL: cannot read the rcf link out of $WRAP"; exit 2; }
RCFDIR="$ROOT/verification/isa/rcf_$LINK"
[ -d "$RCFDIR" ] || RCFDIR="$ROOT/xcelium/riscv_test/$LINK"
[ -d "$RCFDIR" ] || { echo "FATAL: no image dir for link '$LINK'"; exit 2; }
rm -rf "$WORK"; mkdir -p "$WORK/run"
ln -s "$RCFDIR" "$WORK/$LINK"
cat > "$WORK/run/cds.lib" <<LIB
SOFTINCLUDE ${XCELIUM_HOME}/tools/xcelium/files/cds.lib
DEFINE work ./xcelium.d/work
LIB
# The x-warning settings are inline rather than sourced. The staged flow sources
# ../../disable_x_warnings.tcl relative to its own directory, and a wrong path
# there fails quietly: the range constraint stays an error and the run dies at
# time 0 having elaborated perfectly. Same four settings, no path to get wrong.
cat > "$WORK/run/go.tcl" <<'TCL'
set severity_pack_assert_off {warning}
set pack_assert_off {std_logic_arith numeric_std}
set rangecnst_severity_level {warning}
set intovf_severity_level {warning}
run
exit
TCL
echo "link  : $LINK -> $RCFDIR"

# The compile list is the staged one, in order. Its paths are relative to the
# stage, so they are absolutised here: CWD is the scratch dir, not the stage.
cd "$STAGE" || { echo "FATAL: cannot enter $STAGE"; exit 2; }
# VESTA_SRC is the fail-first hook, so a mutant never has to be made in the tree.
# Point it at a scratch copy of hdl/common/vesta/vesta.vhd and that copy is
# compiled in place of the tracked one; the rest of the list is unchanged. A
# property never seen to fail proves nothing, and with this hook `git diff hdl/`
# stays empty by construction.
FILES=""
for f in $(grep -vE '^\s*(#|$)' cell_list_behavioral.txt); do
    case "$f" in
        /*) FILES="$FILES $f" ;;
        *)  FILES="$FILES $STAGE/$f" ;;
    esac
done
FILES="$FILES $STAGE/wrappers/$ENT.vhd"
if [ -n "${VESTA_SRC:-}" ]; then
    [ -f "$VESTA_SRC" ] || { echo "FATAL: VESTA_SRC=$VESTA_SRC does not exist"; exit 2; }
    NEW=""
    for f in $FILES; do
        case "$f" in
            */vesta/vesta.vhd) NEW="$NEW $VESTA_SRC" ;;
            *)                 NEW="$NEW $f" ;;
        esac
    done
    FILES="$NEW"
    echo "MUTANT: vesta.vhd replaced by $VESTA_SRC"
    case " $FILES " in *" $VESTA_SRC "*) ;; *) echo "FATAL: substitution did not take"; exit 2 ;; esac
fi

cd "$WORK/run" || { echo "FATAL: cannot enter $WORK/run"; exit 2; }
xrun -64bit -V200X -licqueue -RELAX -CONTROLRELAX nlstex \
     -assert_vhdl -top "$ENT" \
     $FILES \
     -propfile_vhdl "$PF" \
     -input go.tcl > "$WORK/run.log" 2>&1

# The elaboration check greps the property-file echo, not "Assertions:": that
# string also appears in xrun's Verilog hierarchy summary, where the pad models
# carry 8 of their own, so it is present even when the property file was never
# read.
if ! grep -q "Property file: $PF" "$WORK/run.log"; then
    echo "FATAL: the run did not elaborate -- the property file was never read"
    echo "  see $WORK/run.log"; exit 2
fi
if ! grep -qE "TEST (PASSED|FAILED)|SIMULATION TIMEOUT" "$WORK/run.log"; then
    echo "FATAL: the simulation did not reach a verdict -- a green property set"
    echo "       from a run that stopped at time 0 proves nothing."
    echo "  see $WORK/run.log"; exit 2
fi
fires=$(grep -c ASRTST "$WORK/run.log")
pass=$(grep -c "TEST PASSED" "$WORK/run.log")
echo "MODE=$MODE  test=$TEST  a0=$( [ "$pass" -gt 0 ] && echo PASSED || echo 'NOT-PASSED' )  fires=$fires  $(grep -E 'Assertions:' "$WORK/run.log" | tr -s ' ')"
echo "work: $WORK"
grep -E "ASRTST" "$WORK/run.log" | sed 's/^/  /'

if [ "$MODE" = witness ]; then
    rc=0
    for w in $(grep -oE "^\s+W_[A-Z_0-9]+" "$PF" | tr -d ' '); do
        n=$(grep -c ":$w has failed" "$WORK/run.log")
        printf "  %-16s %s\n" "$w" "$n"
        [ "$n" -eq 0 ] && rc=1
    done
    [ "$rc" -ne 0 ] && echo "FAIL: a witness stayed silent -- the stimulus never reached it"
    exit $rc
fi
[ "$fires" -eq 0 ] && exit 0
echo "FAIL: $fires property fire(s)"; exit 1
