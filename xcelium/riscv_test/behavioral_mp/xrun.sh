#!/bin/bash
# =============================================================================
# xrun.sh — compile + elaborate + simulate ONE MCU_MP test in SimVision (GUI).
#
#   ./xrun.sh                 # default test: shmem (the shared-window test)
#   ./xrun.sh add             # partial match on ../rcf/*.rcf  -> rv32ui-p-add
#   ./xrun.sh shmem
#
# Headless twin: ./xrun_batch.sh [test]   (-> xrun.log; ~1 min sim is healthy,
# longer means HUNG — Ctrl-C and investigate, see SHMEM_DEBUG_NOTES.txt)
#
# TEST_FILE is the riscv_tb generic: a FIXED 29-char string, "../rcf/" + a
# 22-char x-padded filename — the files in ../rcf/ are already padded, so the
# match below just picks one and passes its full path.
# =============================================================================

source ~/vestarv/cdspaths.sh

PAT="${1:-shmem}"
# XRUN_MODE=batch (set by xrun_batch.sh) -> no -gui flag; default = GUI
if [ "$XRUN_MODE" = "batch" ]; then MODE=""; else MODE="-gui"; fi

# pick the test rcf by partial match
mapfile -t MATCHES < <(cd ../rcf && ls *"$PAT"*.rcf 2>/dev/null)
case ${#MATCHES[@]} in
    0) echo "No ../rcf/*${PAT}*.rcf found."; exit 1 ;;
    1) RCF="../rcf/${MATCHES[0]}" ;;
    *) echo "Ambiguous '$PAT':"; printf '  %s\n' "${MATCHES[@]}"; exit 1 ;;
esac
if [ ${#RCF} -ne 29 ]; then
    echo "ERROR: '$RCF' is ${#RCF} chars; TEST_FILE must be exactly 29 (7 + 22-char padded name)."
    exit 1
fi
echo "Running test: $RCF  (mode: $MODE)"

# M12: the tile-TCM preload (HART_RAM0_INIT) is RETIRED — every hart boots
# from the shared ROM like silicon; sh tests load tiles through the bootrom's
# msip loader mailboxes (see verification/env/p/mp_boot.h). ram_images/ and
# the HART_IMG override are gone with it.
TILE_GEN=()

LIB_PATH="xcelium.d"
[ -d $LIB_PATH ] && rm -r $LIB_PATH
mkdir -p log

hdlFiles="$(< cell_list_behavioral.txt)"

xrun \
    $hdlFiles \
    -top riscv_tb \
    -generic "TEST_FILE=>\"$RCF\"" \
    "${TILE_GEN[@]}" \
    -v200x \
    -work work \
    $MODE \
    -access +r \
    -controlrelax nlstex \
    -relax \
    -input ../../disable_x_warnings.tcl \
    ${XRUN_EXTRA_INPUT:+-input "$XRUN_EXTRA_INPUT"}
