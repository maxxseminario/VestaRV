#!/bin/bash
# =============================================================================
# xrun_gui.sh  -- open SimVision on ONE already-elaborated MCU_MP test snapshot.
#
# xrun_parallel.sh (compile + elaborate) must have run first for the test you
# want to open -- e.g. to debug the shared-window (0x10000) hang:
#
#     TESTS_FILE=shmem.txt MAX_PARALLEL=1 ./xrun_parallel.sh   # SPI-boot repro
#   or (faster hang, needs the 2 direct-preload edits in MCU.vhd -- see
#     SHMEM_DEBUG_NOTES.txt):
#     TESTS_FILE=shdbg.txt MAX_PARALLEL=1 ./xrun_parallel.sh
#
# The batch sim will HANG (that is the bug); Ctrl-C it once elaboration is done
# (you'll have seen "=== [4/4] Simulating"). Then run this to open the waveform:
#
#     ./xrun_gui.sh                 # numbered menu of elaborated snapshots
#     ./xrun_gui.sh shmem           # partial match -> tb_rv32ui_p_shmem
#     ./xrun_gui.sh tb_rv32ui_p_simple
#
# In SimVision, add the signals listed in SHMEM_DEBUG_NOTES.txt (they live under
# :uut:dut:  for the MCU, and :uut:dut:core:  for the vesta FSM) and Run.
# =============================================================================

source ~/vestarv/cdspaths.sh

BEHAVIORAL_DIR="$(cd "$(dirname "$0")" && pwd)"

# Candidate snapshot names = the per-test wrapper entities (wrappers/tb_*.vhd).
# Whether a given one is actually ELABORATED can't be checked on the filesystem
# (snapshots live inside the packed library xcelium.d/work/xm.work, NOT as tb_*
# directories) — so pick from the wrapper list and let xmsim error out if that
# snapshot wasn't elaborated by the most recent xrun_parallel.sh run.
mapfile -t SNAPS < <(cd "$BEHAVIORAL_DIR/wrappers" 2>/dev/null && ls tb_*.vhd 2>/dev/null | sed 's#\.vhd$##')
if [ ${#SNAPS[@]} -eq 0 ]; then
    echo "ERROR: no wrappers/tb_*.vhd found — run xrun_parallel.sh first (see header)." >&2
    exit 1
fi

# ── choose a snapshot ─────────────────────────────────────────────────────────
if [ $# -ge 1 ]; then
    PAT="$1"
    MATCHES=()
    for s in "${SNAPS[@]}"; do
        [[ "$s" == *"$PAT"* ]] && MATCHES+=("$s")
    done
    case ${#MATCHES[@]} in
        0) echo "No snapshot matches '$PAT'. Available:"; printf '  %s\n' "${SNAPS[@]}"; exit 1 ;;
        1) ENTITY="${MATCHES[0]}" ;;
        *) echo "Ambiguous '$PAT':"; printf '  %s\n' "${MATCHES[@]}"; exit 1 ;;
    esac
else
    echo "Elaborated snapshots:"
    for i in "${!SNAPS[@]}"; do printf "  [%d] %s\n" "$i" "${SNAPS[$i]}"; done
    read -rp "Pick #: " n
    ENTITY="${SNAPS[$n]}"
    [ -z "$ENTITY" ] && { echo "no choice"; exit 1; }
fi

echo "Opening SimVision on work.${ENTITY}:behavioral ..."
cd "$BEHAVIORAL_DIR"
# -gui launches SimVision; -licqueue waits for a seat rather than failing.
exec xmsim -64bit -licqueue -gui "work.${ENTITY}:behavioral"
