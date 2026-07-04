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
# DUT = ../../../genus/out/MCU_MP.genus.v back-annotated via MCU_MP.sdfcmd
# (MAXIMUM). The netlist's MCU has no generics, so the behavioral tile-preload
# generics are replaced by xmsim deposits into the tile SRAM macro models
# (make_ram_deposit.py; harts 1-3 ram0/ram1). Deposits are applied at t=1ns
# (before the first fetch — tiles never execute X) and re-applied at t=300ns
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

# Same tile-image binding rule as the behavioral flow (xrun.sh there): the
# sh-protocol tests preload harts 1-3 with their own image; everything else
# uses the shmem_mp contention tiles. HART_IMG=<basename> overrides.
IMG_DIR="/home/mseminario2/vestarv/xcelium/riscv_test/ram_images"
BASE="$(basename "$RCF" .rcf | sed 's/^x*//')"
case "${HART_IMG:-$BASE}" in
    *-shboot|*-shspin|*-shlock|*-shmutex|*-shamo|*-shwfi|*-shuart|*-shirq|*-shtimer|*-shperiph|*-shi2c|*-shnpu)
        IMG="${HART_IMG:-$BASE}" ;;
    *)  IMG="${HART_IMG:-rv32ui-p-shmem_mp}" ;;
esac

mkdir -p log
echo "Tile preload image: $IMG"
python3 make_ram_deposit.py "$IMG_DIR/$IMG.ram0.rcf" "$IMG_DIR/$IMG.ram1.rcf" ":dut" \
    > log/preload.tcl || { echo "preload generation failed"; exit 1; }

# Driver tcl: preload before the first fetch, re-assert during the second
# reset pulse (tb: resetn 0..40ns, second pulse 280-380ns), then free-run.
if [ "$XRUN_MODE" = "batch" ]; then
cat > log/gate_run.tcl <<EOF
run 1 ns
source log/preload.tcl
run 299 ns
source log/preload.tcl
value :dut:hart1:ram0:mem[4]
run
exit
EOF
else
cat > log/gate_run.tcl <<EOF
run 1 ns
source log/preload.tcl
run 299 ns
source log/preload.tcl
puts "tiles preloaded; 'run' to continue"
EOF
fi

LIB_PATH="xcelium.d"
[ -d $LIB_PATH ] && rm -r $LIB_PATH

hdlFiles="$(< cell_list_genus_mp.txt)"

xrun \
    $hdlFiles \
    -top riscv_tb \
    -generic "TEST_FILE=>\"$RCF\"" \
    -sdf_cmd_file MCU_MP.sdfcmd \
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
