#!/bin/bash
# PG3 signoff DRC: strmout an OA layout to flat GDS, run batch Calibre with a
# TSMC65 SVRF deck. Adapted from the frozen Myshkin harness
# (chips/myshkin/ic/calibre/silent_drc) -- same runset shape, but:
#   * decks referenced by ABSOLUTE path into the frozen Myshkin calibre dir
#     (read-only; celldrc.rul = CLN65S_9M_6X1Z1U.25a block deck, FULL_CHIP off)
#   * run dirs live under signoff_mp/calibre/<lib>/<cell>/ -- never inside
#     Myshkin's result tree
# Run from ~/vestarv/signoff_mp. BATCH ONLY (license 5280@poseidon is shared;
# never park a GUI).
#
# usage: ./drc.sh library cell rule    (rule: celldrc chipdrc ant mim wb)

set -u
cd "$(dirname "$0")/.."   # cq6/ -> signoff_mp (relative decks/, calibre/ resolve here)

lib=$1
cell=$2
rule=$3

DECK_DIR=/home/mseminario2/chips/myshkin/ic/calibre
RUN_DIR=calibre/cq8a_iso/$cell/$rule

# Local decks (signoff_mp/decks) take precedence over the frozen Myshkin set.
# blockdrc = main.rul v2.6_2a with FULL_CHIP off (see comment in the deck for
# why celldrc.rul v2.5a cannot be used on blocks containing sram1p16k_hvt_pg).
if [ -f "decks/$rule.rul" ]; then
    DECK_DIR=$(pwd)/decks
fi
if [ ! -f "$DECK_DIR/$rule.rul" ]; then
    echo "Error: no deck $DECK_DIR/$rule.rul"; exit 1
fi

mkdir -p "$RUN_DIR"

# Flatten OA -> GDS for Calibre (ref-lib cell layouts get merged here; this is
# what fills in std-cell/macro internals the Innovus GDS doesn't carry).
strmout -library "$lib" -topCell "$cell" -view layout \
    -strmFile "$RUN_DIR/layout.gds" \
    -techlib tsmcN65 \
    -layerMap /opt/design_kits/TSMC65-PDK/tsmcN65/tsmcN65.layermap \
    -logFile "$RUN_DIR/strmout.log" > /dev/null
if grep -qi "ERROR" "$RUN_DIR/strmout.log"; then
    echo "strmout reported errors:"; grep -i "ERROR" "$RUN_DIR/strmout.log" | head
fi

cat << EOF > "$RUN_DIR/calibre.runset"
*drcRulesFile: $DECK_DIR/$rule.rul
*drcRunDir: $RUN_DIR
*drcLayoutPaths: layout.gds
*drcLayoutPrimary: $cell
*drcResultsFile: results/${rule}.db
*drcCellName: 0
*drcDRCMaxResultsAll: 1
*drcSummaryFile: results/$rule.rpt
*cmnWarnLayoutOverwrite: 0
*cmnResolution: 5
*cmnNumTurbo: 2
*cmnRunMT: 1
EOF

echo "Running Calibre DRC ($rule) on $lib/$cell ..."
calibre -gui -drc -runset "$RUN_DIR/calibre.runset" -batch > "$RUN_DIR/$rule.log" 2>&1
rc=$?
if [ $rc -ne 0 ]; then
    echo "Calibre exited rc=$rc -- tail of log:"; tail -20 "$RUN_DIR/$rule.log"; exit 1
fi

echo "Results: $RUN_DIR/results/$rule.rpt"
sed -n -e '/STATISTICS (BY CELL)/,$p' "$RUN_DIR/results/$rule.rpt" | head -60
