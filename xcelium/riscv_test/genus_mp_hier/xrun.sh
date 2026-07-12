#!/bin/bash
# =============================================================================
# xrun.sh — compile + elaborate + simulate ONE test against the POST-SYNTHESIS
# (genus) MCU_MP gate netlist with SDF timing, in SimVision (GUI).
#
#   ./xrun.sh                  # default test: simple
#   ./xrun.sh add              # partial match on ../rcf/*.rcf -> rv32ui-p-add
#
# Headless twin: ./xrun_batch.sh [test]  (-> xrun.log)
#
# DUT = innovus/common post-P&R netlists (top + 4x hardened hart_tile), SDF via MCU_MP_hier.sdfcmd
# (MAXIMUM). The netlist's MCU has no generics. M12: the tile-TCM preload is
# RETIRED — every hart boots from the shared ROM like silicon (the gate ROM
# macro holds the real M12 bootrom), so no per-hart TCM deposits. All that
# remains is xmsim zero-deposits into the shared SRAM macro models
# (make_ram_deposit.py; shbank0-3 + npuram0). Deposits at t=1ns (before the
# first fetch — masters never read X shared words) and re-applied at t=300ns
# (inside the second reset pulse, in case a settle-window X access nuked a
# model's mem via its failedWrite task). Hart 0 SPI-boots like the real chip.
# Gate sims are MUCH slower than behavioral — the 1-MINUTE RULE DOES NOT APPLY;
# see log/… and xrun.log for progress.
#
# -nonotifier (M9b): timing-check VIOLATIONS still print but no longer X the
# violating flop via the cell's notifier reg. Needed because the tb's async
# reset release trips reset-time $hold(SN/R) checks (system0.unlock_timer at
# 178ps, spi0 regs at both reset pulses) whose notifier-X poisons state the
# chip needs to boot. SDF delays themselves stay annotated and enforced.
# =============================================================================

source ~/vestarv/cdspaths.sh
cd "$(dirname "$0")"

PAT="${1:-simple}"
if [ "$XRUN_MODE" = "batch" ]; then MODE=""; else MODE="-gui"; fi

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
echo "Running gate-level test: $RCF  (mode: ${MODE:-batch})"

# M12: no tile-image binding — tiles boot from the shared ROM. The only preload
# left is the shared-macro zero-deposit (shbank0-3 + npuram0).
mkdir -p log
python3 make_ram_deposit.py ":dut" \
    > log/preload.tcl || { echo "preload generation failed"; exit 1; }

# Driver tcl: preload before the first fetch, re-assert during the second
# reset pulse (tb: resetn 0..40ns, second pulse 280-380ns), then free-run.
if [ "$XRUN_MODE" = "batch" ]; then
cat > log/gate_run.tcl <<EOF
run 1 ns
source log/preload.tcl
run 299 ns
source log/preload.tcl
run
exit
EOF
else
cat > log/gate_run.tcl <<EOF
run 1 ns
source log/preload.tcl
run 299 ns
source log/preload.tcl
puts "shared macros zeroed; 'run' to continue"
EOF
fi

LIB_PATH="xcelium.d"
[ -d $LIB_PATH ] && rm -r $LIB_PATH

hdlFiles="$(< cell_list_innovus_mp.txt)"

xrun \
    $hdlFiles \
    -top riscv_tb \
    -generic "TEST_FILE=>\"$RCF\"" \
    -sdf_cmd_file MCU_MP_hier.sdfcmd \
    -sdfstats log/sdf_stats.log \
    -v200x \
    -work work \
    $MODE \
    -access +rwc \
    -controlrelax nlstex \
    -relax \
    -nonotifier \
    -input ../../disable_x_warnings.tcl \
    -input log/gate_run.tcl
