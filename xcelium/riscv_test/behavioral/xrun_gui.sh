#!/bin/bash
# Open SimVision for one test from the rv32ui parallel suite.
# xrun_parallel.sh (compile + elaborate) must have been run first.
#
# Usage:
#   ./xrun_gui.sh              # numbered menu
#   ./xrun_gui.sh add          # partial match  →  tb_rv32ui_p_add
#   ./xrun_gui.sh tb_rv32ui_p_lw   # full entity name also works

source ~/vestarv/cdspaths.sh

BEHAVIORAL_DIR="$(cd "$(dirname "$0")" && pwd)"

# Single source of truth: derive the test list from xrun_parallel.sh's active
# (uncommented) TEST_FILES entries, so the two scripts can never drift. These are
# exactly the snapshots xrun_parallel.sh compiled+elaborated, which is what the
# GUI needs to open. Strip comment lines first so disabled suites are excluded.
PARALLEL_SH="$BEHAVIORAL_DIR/xrun_parallel.sh"
mapfile -t TEST_FILES < <(grep -vE '^[[:space:]]*#' "$PARALLEL_SH" \
    | grep -oP '(?<=")\.\./rcf/[^"]+\.rcf(?=")')
if [ ${#TEST_FILES[@]} -eq 0 ]; then
    echo "ERROR: could not parse any test files from $PARALLEL_SH" >&2
    exit 1
fi

# "../rcf/xxxxxxxrv32ui-p-lb.rcf" → "tb_rv32ui_p_lb"
snap_name() {
    basename "$1" .rcf | sed 's/^x*//' | tr '-' '_' | sed 's/^/tb_/'
}

ENTITIES=()
for rcf in "${TEST_FILES[@]}"; do
    ENTITIES+=("$(snap_name "$rcf")")
done

# ── Pick which entity to open ─────────────────────────────────────────────────
if [ $# -ge 1 ]; then
    PAT="$1"
    MATCHES=()
    for e in "${ENTITIES[@]}"; do
        [[ "$e" == *"$PAT"* ]] && MATCHES+=("$e")
    done
    case ${#MATCHES[@]} in
        0)
            echo "No test matches '$PAT'." >&2
            echo "Run with no arguments to see the full list." >&2
            exit 1
            ;;
        1)
            ENTITY="${MATCHES[0]}"
            ;;
        *)
            echo "Ambiguous — '$PAT' matches ${#MATCHES[@]} tests:" >&2
            printf '  %s\n' "${MATCHES[@]}" >&2
            echo "Be more specific." >&2
            exit 1
            ;;
    esac
else
    echo "Available tests:"
    for i in "${!ENTITIES[@]}"; do
        printf "  %2d)  %s\n" "$((i+1))" "${ENTITIES[$i]}"
    done
    echo ""
    read -r -p "Select [1-${#ENTITIES[@]}]: " SEL
    if ! [[ "$SEL" =~ ^[0-9]+$ ]] || (( SEL < 1 || SEL > ${#ENTITIES[@]} )); then
        echo "Invalid selection." >&2
        exit 1
    fi
    ENTITY="${ENTITIES[$((SEL-1))]}"
fi

# ── Sanity-check that compile+elab has been run ───────────────────────────────
if [ ! -d "$BEHAVIORAL_DIR/xcelium.d/work" ]; then
    echo "ERROR: xcelium.d/work not found." >&2
    echo "Run ./xrun_parallel.sh first to compile and elaborate all snapshots." >&2
    exit 1
fi

echo "Opening SimVision for: $ENTITY"
cd "$BEHAVIORAL_DIR"

# Run this snapshot in GUI mode.  restore.tcl opens waves.shm, installs
# probes, then hands control to SimVision (restore.tcl.svcf wave layout).
# -access +r lets SimVision probe any signal not already listed in restore.tcl.
xmsim "work.${ENTITY}:behavioral" \
    -gui \
    -input ../../disable_x_warnings.tcl \
    -input restore.tcl
