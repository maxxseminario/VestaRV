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
# CQ8b PER-RUN ISOLATION: every invocation gets its OWN work dir
#     calibre/<lib>/<cell>/run_<rule>_<pgid>_<epoch>/
# so two concurrent sessions on the same lib/cell can never clobber each
# other's layout.gds / calibre.runset / results DB mid-run (the CQ6
# stale-readback hazard, devlog war story 6). The final report + db + the
# flattened layout.gds are then published ATOMICALLY back to the legacy paths
#     calibre/<lib>/<cell>/{layout.gds, results/<rule>.rpt, results/<rule>.db}
# so accept_*.sh, classify_drc.py, minarea_sites.sh and humans keep working
# unchanged. Cleanup is SCOPED BY PROCESS GROUP: this script re-execs under
# setsid (so $$ == PGID) and advertises that PGID -- external cleanup does
# `kill -TERM -<PGID>` and hits exactly this run's children (calibre + turbo),
# NEVER a `pkill -f <pattern>` that could match a neighbouring session (the
# CQ6 cross-session-kill trap) or the killer's own command line.
#
# usage: ./drc.sh library cell rule    (rule: celldrc chipdrc ant mim wb)

set -u

# Re-exec once under setsid so this run owns a fresh session / process group;
# `setsid -w` waits and forwards the child's exit status, so the CLI/rc
# contract is unchanged for callers (accept_*.sh do `./drc.sh ...; rc=$?`).
if [ -z "${_DRC_ISOLATED:-}" ]; then
    export _DRC_ISOLATED=1
    exec setsid -w "$0" "$@"
fi

cd "$(dirname "$0")"

lib=$1
cell=$2
rule=$3

DECK_DIR=/home/mseminario2/chips/myshkin/ic/calibre
PUB_DIR=calibre/$lib/$cell                       # legacy shared path (consumers)
RUN_DIR=$PUB_DIR/run_${rule}_$$_$(date +%s)      # per-run isolated work dir

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

# Advertise the process group so any external cleanup is scoped to THIS run
# (kill -TERM -<PGID>) -- never a pattern match.
echo "$$" > "$RUN_DIR/run.pgid"
echo "=== drc.sh isolated run ==================================================="
echo "    lib/cell/rule : $lib / $cell / $rule"
echo "    RUN_DIR       : $RUN_DIR"
echo "    PGID          : $$   (scoped kill:  kill -TERM -$$ )"
echo "=========================================================================="
# 'latest' convenience pointer for humans; per-run dirs are kept for inspection.
ln -sfn "$(basename "$RUN_DIR")" "$PUB_DIR/latest"

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

# Publish the flattened layout to the legacy path NOW (before calibre). Calibre
# then runs for its full wall-time, so the published results/<rule>.rpt (below)
# is always seconds/minutes newer than this layout.gds -- keeping accept_mcu's
# `[ rpt -nt layout.gds ]` staleness check meaningful and false-alarm-free.
mkdir -p "$PUB_DIR"
cp -f "$RUN_DIR/layout.gds" "$PUB_DIR/.layout.gds.$$" \
    && mv -f "$PUB_DIR/.layout.gds.$$" "$PUB_DIR/layout.gds"

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
# Run calibre as a tracked child: a lone TERM to this script still reaps it via
# the trap; an external group kill (kill -TERM -$$) reaps it + its turbo procs
# through the shared process group set up by setsid.
calibre -gui -drc -runset "$RUN_DIR/calibre.runset" -batch > "$RUN_DIR/$rule.log" 2>&1 &
CAL_PID=$!
trap 'kill -TERM "$CAL_PID" 2>/dev/null; exit 143' TERM INT
wait "$CAL_PID"
rc=$?
trap - TERM INT
if [ $rc -ne 0 ]; then
    echo "Calibre exited rc=$rc -- tail of log:"; tail -20 "$RUN_DIR/$rule.log"; exit 1
fi

# Publish results atomically to the legacy paths for accept_*.sh / classify_drc.py
# (temp name in the SAME dir + mv = atomic rename; even a same-rule concurrent
# publish yields a whole file, last-writer-wins, never a torn read).
mkdir -p "$PUB_DIR/results"
for ext in rpt db; do
    src="$RUN_DIR/results/$rule.$ext"
    if [ -f "$src" ]; then
        cp -f "$src" "$PUB_DIR/results/.$rule.$ext.$$" \
            && mv -f "$PUB_DIR/results/.$rule.$ext.$$" "$PUB_DIR/results/$rule.$ext"
    fi
done

echo "Results (isolated) : $RUN_DIR/results/$rule.rpt"
echo "Results (published): $PUB_DIR/results/$rule.rpt"
sed -n -e '/STATISTICS (BY CELL)/,$p' "$RUN_DIR/results/$rule.rpt" | head -60
