#!/bin/bash
# =============================================================================
# xrun_dbg.sh -- D1 acceptance runner: ONE MCU_MP test, headless, with WRITE
# access so a tcl harness can FORCE the core-side debug request ports.
#
#   ./xrun_dbg.sh <test-pattern> <harness.tcl>
#   ./xrun_dbg.sh xxxrv32ua-p-dbghaltmp dbg_halt.tcl
#
# WHY THIS EXISTS AND WHY IT IS NOT xrun_batch.sh
#   `xrun.sh` elaborates with `-access +r`.  Read access cannot FORCE, and the
#   D1 debug request ports (`dbg_haltreq` / `dbg_resethaltreq`) have NO driver
#   anywhere in the design at D1: the DM is D2's, so hdl/common/MCU.vhd leaves
#   them unconnected and they sit at their entity defaults.  The only way to
#   raise a halt request in the MCU-level behavioral flow is therefore a
#   hierarchical force, and that needs `-access +rwc`.
#
#   This is a DELIBERATE SEPARATE RUNNER, not an edit to xrun.sh: the standing
#   suite (142/142) and both lockstep gates run through xrun.sh, and widening
#   their elaboration access would change their optimisation and their
#   run-to-run identity for no benefit.  Nothing in tools/cosim/gate/ refers to
#   this file.
#
# OUTPUT: xrun_dbg.log (NOT xrun.log -- the suite runner owns that name; a
#   shared log is how a stale file gets quoted as a fresh result).
#
# NEVER pipe this through `head` (SIGPIPE kills the sim and leaves a stale log).
# =============================================================================
cd "$(dirname "$0")"
source ~/vestarv/cdspaths.sh

PAT="${1:?usage: xrun_dbg.sh <test-pattern> <harness.tcl>}"
TCL="${2:?usage: xrun_dbg.sh <test-pattern> <harness.tcl>}"

if [ ! -f "$TCL" ]; then echo "No such harness tcl: $TCL"; exit 1; fi

mapfile -t MATCHES < <(cd ../rcf && ls *"$PAT"*.rcf 2>/dev/null)
case ${#MATCHES[@]} in
    0) echo "No ../rcf/*${PAT}*.rcf found."; exit 1 ;;
    1) RCF="../rcf/${MATCHES[0]}" ;;
    *) echo "Ambiguous '$PAT':"; printf '  %s\n' "${MATCHES[@]}"; exit 1 ;;
esac
if [ ${#RCF} -ne 29 ]; then
    echo "ERROR: '$RCF' is ${#RCF} chars; TEST_FILE must be exactly 29."
    exit 1
fi

# NHARTS interlock, same shape as the other MCU_MP runners (M19c/K1): an
# out-of-tree N=18 build transiting through ../rcf must never be simulated
# against the N=4 MCU.
NH="$(cat ../rcf/.nharts 2>/dev/null)"
if [ "$NH" != "4" ]; then
    echo "FATAL: ../rcf/.nharts = '${NH}' (expected 4). Rebuild with"
    echo "  verification/isa/build_mp_images.sh 4 ../../xcelium/riscv_test/rcf"
    exit 2
fi

echo "Starting test: $RCF   harness: $TCL"

# Same library plumbing as xrun.sh (cds.lib defines only `work`): this runner
# rebuilds xcelium.d exactly as xrun.sh does, so the two never disagree about
# what was compiled.  The LOG name is what differs -- xrun.log belongs to the
# suite runner, and a shared log is how a stale file gets quoted as fresh.
LIB_PATH="xcelium.d"
[ -d $LIB_PATH ] && rm -r $LIB_PATH
mkdir -p log

hdlFiles="$(< cell_list_behavioral.txt)"

xrun \
    $hdlFiles \
    -top riscv_tb \
    -generic "TEST_FILE=>\"$RCF\"" \
    -v200x \
    -work work \
    -access +rwc \
    -controlrelax nlstex \
    -relax \
    -input ../../disable_x_warnings.tcl \
    -input "$TCL" \
    2>&1 | tee xrun_dbg.log
