#!/bin/bash
# =============================================================================
# xrun.sh — compile + elaborate + simulate ONE test against the ARGUS post-P&R
# gate netlist (18-tile MCU_ARGUS assembly + hardened hart_tile_argus) with
# hierarchical SDF timing, in SimVision (GUI).
#
#   ./xrun.sh                  # default test: simple
#   ./xrun.sh shboot           # partial match on ../rca/*.rcf
#
# Headless twin: ./xrun_batch.sh [test]  (-> xrun.log)
#
# DUT = innovus_mp/out/{MCU_ARGUS.xsim.clean.v + hart_tile_argus.xsim.v}, SDF
# via MCU_ARGUS_hier.sdfcmd (top + 18 tile scopes, MAXIMUM). Argus images live
# in ../rca (A3: 29-char TEST_FILE, x-padded basenames). Tiles boot from the
# shared ROM like silicon — the local rom_hvt_pg_verilog.rcf is the CURRENT
# software/bootrom_mp/bin/rom.rcf (the ROM verilog model $readmemb's it from
# cwd; re-copy after any bootrom rebuild). The only deposit is the shared-bank
# zero-init (make_ram_deposit.py, shbank0-7; no NPU in Argus).
#
# -nonotifier (M9b): timing-check VIOLATIONS still print but no longer X the
# violating flop via the cell's notifier reg (async reset release trips
# reset-time $hold checks whose notifier-X poisons boot state). SDF delays
# stay annotated and enforced.
# Gate sims are MUCH slower than behavioral — the 1-MINUTE RULE DOES NOT APPLY.
# =============================================================================

source ~/vestarv/cdspaths.sh
cd "$(dirname "$0")"

PAT="${1:-simple}"
if [ "$XRUN_MODE" = "batch" ]; then MODE=""; else MODE="-gui"; fi

mapfile -t MATCHES < <(cd ../rca && ls *"$PAT"*.rcf 2>/dev/null)
case ${#MATCHES[@]} in
    0) echo "No ../rca/*${PAT}*.rcf found."; exit 1 ;;
    1) RCF="../rca/${MATCHES[0]}" ;;
    *) echo "Ambiguous '$PAT':"; printf '  %s\n' "${MATCHES[@]}"; exit 1 ;;
esac
if [ ${#RCF} -ne 29 ]; then
    echo "ERROR: '$RCF' is ${#RCF} chars; TEST_FILE must be exactly 29."
    exit 1
fi
echo "Running Argus gate-level test: $RCF  (mode: ${MODE:-batch})"

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

hdlFiles="$(< cell_list_innovus_mp_argus.txt)"

xrun \
    $hdlFiles \
    -top riscv_tb \
    -generic "TEST_FILE=>\"$RCF\"" \
    -sdf_cmd_file MCU_ARGUS_hier.sdfcmd \
    -sdfstats log/sdf_stats.log \
    -v200x \
    -work work \
    -ALLOWREDEFINITION \
    $MODE \
    -access +rwc \
    -controlrelax nlstex \
    -relax \
    -nonotifier \
    -input ../../disable_x_warnings.tcl \
    -input log/gate_run.tcl
