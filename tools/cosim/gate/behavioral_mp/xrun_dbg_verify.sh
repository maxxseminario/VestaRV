#!/bin/bash
# =============================================================================
# xrun_dbg_verify.sh -- run ONE tcl debug harness against a GENERATOR-STAGED
# knob-ON tree (verify_castaliadebug at N=4, verify_argusdebug at N=18).
#
#   ./xrun_dbg_verify.sh <verifydir> <rcf-path-relative-to-it> <harness.tcl>
#   ./xrun_dbg_verify.sh verify_castaliadebug ../kba/xxxxxxrv32ui-p-add.rcf dbg_tapconf.tcl
#   ./xrun_dbg_verify.sh verify_argusdebug    ../kf0/xrv32ua-p-dbgdmimp.rcf dbg_taphalt.tcl
#
# WHY THIS EXISTS -- AND IT IS A GAP, NOT A CONVENIENCE
#   xrun_dbg.sh compiles behavioral_mp/cell_list_behavioral.txt, which is the
#   DEFAULT (debug-OFF) configuration, and hard-refuses when ../rcf/.nharts is
#   not 4.  So it can run a debug harness only against a tree that has been
#   overlaid by hand (the D2 d2mut/ mkarm.sh pattern), and it can never run one
#   at N=18 at all.
#
#   MEASURED at D3 authoring time (2026-08-06), and stated because it is a
#   finding rather than an inconvenience: there is NO runner anywhere in the
#   tree that runs a tcl debug harness against verify_argusdebug.  That
#   directory holds no dbg_*.tcl, no xrun_dbg.sh, and its own xrun_parallel.sh
#   elaborates with `-access +r`, which cannot force.  d3_spec 6 requires the
#   whole-stack proof at N=4 AND N=18, so the runner is authored here.
#
#   The generator's staged cell list already names the knob-ON MCU.vhd,
#   MemoryMap.vhd and riscv_tb.vhd it emitted, so pointing xrun at that list
#   from inside the verify directory is the whole mechanism.  Nothing is
#   copied and nothing is overlaid -- which is why this is preferable to the
#   d2arm_* pattern for anything that is not a mutant.
#
# NHARTS is DERIVED from the staged image set's own stamp and EXPORTED to the
# harness as D2_NHARTS.  It is never guessed: the harnesses use it to compute
# hartsel widths and the expected IDCODE, and a wrong value would silently
# grade the wrong chip.
#
# OUTPUT: <verifydir>/xrun_dbg.log
# NEVER pipe this through `head` (SIGPIPE kills the sim, leaving a stale log).
# =============================================================================
cd "$(dirname "$0")"
source ~/vestarv/cdspaths.sh

VDIR="${1:?usage: xrun_dbg_verify.sh <verifydir> <rcf-path> <harness.tcl>}"
RCF="${2:?usage: xrun_dbg_verify.sh <verifydir> <rcf-path> <harness.tcl>}"
TCL="${3:?usage: xrun_dbg_verify.sh <verifydir> <rcf-path> <harness.tcl>}"

HARNESS_ABS="$(cd "$(dirname "$0")" && pwd)/$TCL"
if [ ! -f "$HARNESS_ABS" ]; then
    echo "No such harness tcl: $HARNESS_ABS"; exit 1
fi

VABS="../$VDIR"
if [ ! -d "$VABS" ]; then
    echo "No such staged verify dir: $VABS"
    echo "Build it first, e.g.:"
    echo "  cd ~/vestarv/platform/common && SUITE=full make verify CONFIG=config/argus_debug.json"
    echo "  ... then RESTORE THE DEFAULT: make chip"
    exit 1
fi
if [ ! -f "$VABS/cell_list_behavioral.txt" ]; then
    echo "FATAL: $VABS has no cell_list_behavioral.txt -- it is not a staged verify tree."
    exit 2
fi

cd "$VABS"

if [ ${#RCF} -ne 29 ]; then
    echo "ERROR: '$RCF' is ${#RCF} chars; TEST_FILE must be exactly 29."
    exit 1
fi
if [ ! -f "$RCF" ]; then
    echo "ERROR: no such image (relative to $VABS): $RCF"
    exit 1
fi

# Derive NHARTS from the image set the staged tree actually points at.  The
# .nharts stamp lives beside the images.
RCFDIR="$(dirname "$RCF")"
NH="$(cat "$RCFDIR/.nharts" 2>/dev/null)"
if [ -z "$NH" ]; then
    echo "FATAL: no .nharts stamp beside $RCF -- refusing to guess the hart count."
    echo "       A harness graded at the wrong N silently checks the wrong chip."
    exit 2
fi
export D2_NHARTS="$NH"

echo "Starting: verify=$VDIR  image=$RCF  NHARTS=$NH  harness=$TCL"

LIB_PATH="xcelium.d_dbg"
[ -d $LIB_PATH ] && rm -r $LIB_PATH
mkdir -p log

hdlFiles="$(< cell_list_behavioral.txt)"

xrun \
    $hdlFiles \
    -top riscv_tb \
    -generic "TEST_FILE=>\"$RCF\"" \
    -v200x \
    -work work \
    -xmlibdirname "$LIB_PATH" \
    -access +rwc \
    -controlrelax nlstex \
    -relax \
    -input ../../disable_x_warnings.tcl \
    -input "$HARNESS_ABS" \
    2>&1 | tee xrun_dbg.log
