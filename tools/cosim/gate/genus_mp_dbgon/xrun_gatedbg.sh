#!/bin/bash
# =============================================================================
# xrun_gatedbg.sh -- THE D5 SECTION-6 BOUNDED GATE LEG runner (DD16).
#
#   ./xrun_gatedbg.sh <harness.tcl> [test-pattern]
#   ./xrun_gatedbg.sh gate_m7probe.tcl
#   D5_GATE=1 ./xrun_gatedbg.sh ../behavioral_mp/dbg_gateidc.tcl
#
# WHAT THIS IS
#   A genus_mp SIBLING: same standard cells, same macros, same VHDL testbench,
#   but the DUT is the DEBUG-ON assembly netlist
#       genus/MCU_MP/out/MCU_MP.genus.dbgon.v
#   back-annotated from ITS OWN SDF (MCU_MP_dbgon.sdfcmd, MTM MAXIMUM), and the
#   elaboration carries `-access +rwc` so a tcl harness can force the TAP pins.
#   genus_mp/ compiles the debug-OFF cut and has no TAP in it at all; it is kept
#   as the SDF-liveness CONTROL for tools/cosim/d5_sdf_live.py and is never
#   edited by this flow.
#
# WHY A NEW DIRECTORY RATHER THAN A FLAG ON genus_mp/xrun.sh
#   Same reason xrun_dbg.sh is not a flag on xrun.sh: the standing gate flow's
#   elaboration access and its xcelium.d must not move for a leg that is run
#   once.  Nothing in tools/cosim/gate/ refers to genus_mp/xrun.sh, and nothing
#   refers to this file either.
#
# THE M7 QUESTION IS ASKED FIRST, BY gate_m7probe.tcl, AND IT IS NOT OPTIONAL.
#   riscv_tb_gate.vhd declares MCU as a COMPONENT ending at a0_3, so the dbgon
#   netlist's tck/tms/tdi/tdo/trstn ports are UNASSOCIATED.  Every force in
#   dbg_tap.tcl is catch-wrapped, so a wrong path spelling is SILENT and shows
#   up as IDCODE = 0x00000000 -- a harness failure that reads as a chip failure.
#   Run gate_m7probe.tcl before dbg_gateidc.tcl, always.
#
# TAP_PFX: exported into the harness as a tcl variable via gate_pfx.tcl, which
#   is generated here from $TAP_PFX so the spelling the probe MEASURED is the
#   spelling the leg USES.  dbg_tap.tcl honours a pre-set ::TAP_PFX.
#
# THE SDF GUARD is the same shape as genus_mp/xrun.sh's (the 2026-07-29
# silently-optional-annotation lesson) AND the run emits -sdfstats, which is
# what tools/cosim/d5_sdf_live.py reads as its positive evidence:
#     /usr/bin/python3.6 tools/cosim/d5_sdf_live.py \
#         xcelium/riscv_test/genus_mp_dbgon/log \
#         --expect-sdf MCU_MP.genus.dbgon.sdf \
#         --control xcelium/riscv_test/genus_mp/log
#
# GATE SIMS ARE SLOW -- THE 1-MINUTE RULE DOES NOT APPLY.  d5_spec section 6
# bounds this leg at ~2 h wall; past that, record the measured slowdown and stop.
#
# OUTPUT: xrun_gatedbg.log.  NEVER pipe this through `head` (SIGPIPE kills the
# sim and leaves a stale log that parses perfectly).
# =============================================================================
cd "$(dirname "$0")"
source ~/vestarv/cdspaths.sh

TCL="${1:?usage: xrun_gatedbg.sh <harness.tcl> [test-pattern]}"
PAT="${2:-simple}"

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

# NHARTS interlock, same shape as every other MCU_MP runner (M19c/K1): the
# dbgon netlist is a 4-hart assembly and an N=18 image set transiting through
# ../rcf must never be simulated against it.
NH="$(cat ../rcf/.nharts 2>/dev/null)"
if [ "$NH" != "4" ]; then
    echo "FATAL: ../rcf/.nharts = '${NH}' (expected 4). Rebuild with"
    echo "  verification/isa/build_mp_images.sh 4 ../../xcelium/riscv_test/rcf"
    exit 2
fi
export D2_NHARTS=4

# --- SDF back-annotation guard (2026-07-29): the .sdfcmd must exist AND every
#     SDF_FILE inside it must resolve, or xmelab silently anneals NOTHING and
#     the gate sim "passes" un-annotated.
SDFCMD="MCU_MP_dbgon.sdfcmd"
[ -f "$SDFCMD" ] || { echo "FATAL: $SDFCMD missing (SDF back-annotation)"; exit 1; }
__sdf=$(sed -n 's/.*SDF_FILE[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$SDFCMD")
[ -n "$__sdf" ] || { echo "FATAL: no SDF_FILE in $SDFCMD"; exit 1; }
for __f in $__sdf; do
    [ -f "$__f" ] || { echo "FATAL: SDF_FILE unresolvable in $SDFCMD: '$__f'"; exit 1; }
done
# ...and the netlist the cell list names must be the SAME CUT as that SDF.  The
# two are written by one genus run; a mismatch here is the failure d5_sdf_live's
# --expect-sdf exists to catch, caught one step earlier and for free.
__nl=$(grep -m1 'MCU_MP\.genus.*\.v$' cell_list_genus_mp_dbgon.txt)
case "$__nl" in
    *dbgon*) : ;;
    *) echo "FATAL: cell list names '$__nl' but the sdfcmd names a dbgon SDF."; exit 1 ;;
esac

mkdir -p log
: "${TAP_PFX:=:dut.}"
printf 'set ::TAP_PFX "%s"\nputs "M7LOG TAP_PFX preset to %s by xrun_gatedbg.sh"\n' \
    "$TAP_PFX" "$TAP_PFX" > log/gate_pfx.tcl

echo "Starting GATE debug leg: netlist=$__nl"
echo "  sdf=$__sdf  (MAXIMUM)   image=$RCF   harness=$TCL   TAP_PFX=$TAP_PFX"

LIB_PATH="xcelium.d"
[ -d $LIB_PATH ] && rm -r $LIB_PATH

hdlFiles="$(< cell_list_genus_mp_dbgon.txt)"

# -nonotifier: same reason as genus_mp/xrun.sh -- the tb's async reset release
# trips reset-time hold checks whose notifier-X poisons state the chip needs.
# SDF delays themselves stay annotated and enforced.
xrun \
    $hdlFiles \
    -top riscv_tb \
    -generic "TEST_FILE=>\"$RCF\"" \
    -sdf_cmd_file "$SDFCMD" \
    -sdfstats log/sdf_stats.log \
    -v200x \
    -work work \
    -access +rwc \
    -controlrelax nlstex \
    -relax \
    -nonotifier \
    -input ../../disable_x_warnings.tcl \
    -input log/gate_pfx.tcl \
    -input "$TCL" \
    2>&1 | tee xrun_gatedbg.log
