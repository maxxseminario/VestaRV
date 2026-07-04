#!/bin/bash
# Parallel MCU-peripheral testbench runner.
#
# Each test is a standalone, self-checking peripheral bench and its own
# top-level entity (unlike xcelium/riscv_test, which parameterizes ONE testbench
# per program). Flow:
#   1. Compile the union of all peripheral HDL + TBs once into `work`.
#   2. Elaborate each TB top into its own snapshot (sequential, fast).
#   3. Simulate all snapshots in parallel (throttled to MAX_PARALLEL licenses).
# A test PASSES iff its log contains "ALL CHECKS PASSED" (the scoreboard banner).
#
# Usage:
#   ./xrun_parallel.sh
#   MAX_PARALLEL=5 ./xrun_parallel.sh
#
# NOTE: NPU_tb is SLOW (David Bishop fixed_pkg, 402 inference points ~ minutes of
# wall time) and dominates the total runtime; the rest finish in ~seconds.
#
# Licenses: each running xmsim/xmelab checks out one Xcelium_Single_Core seat
# (pool 5280@poseidon, 40 shared). Sims use -licqueue so they wait, not fail.

source ~/vestarv/cdspaths.sh

BEHAVIORAL_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_PATH="$BEHAVIORAL_DIR/log"
LIB_PATH="$BEHAVIORAL_DIR/xcelium.d"
MAX_PARALLEL=${MAX_PARALLEL:-5}

# One entry per test: "entity:architecture". read_data/pass all via the banner.
TESTS=(
    "system_tb:sim"
    "i2c_tb:sim"
    "spi_tb:sim"
    "uart_tb:sim"
    "npu_tb:testbench"
)

cd "$BEHAVIORAL_DIR"

# ── 1. Compile the union once ─────────────────────────────────────────────────
echo "=== [1/3] Compiling HDL ==="
[ -d "$LIB_PATH" ] && rm -r "$LIB_PATH"
mkdir -p "$LOG_PATH" "$LIB_PATH/work"

# The standalone xm* flow (unlike single-step xrun) needs a cds.lib mapping the
# installed IEEE/std libraries and the local `work` library.
cat > "$BEHAVIORAL_DIR/cds.lib" <<LIB
SOFTINCLUDE ${XCELIUM_HOME}/tools/xcelium/files/cds.lib
DEFINE work ./xcelium.d/work
LIB

# Unquoted word-splitting (not a `while read` loop) so a trailing space / missing
# final newline never silently drops a file. Skip comment lines.
# Filter on extension (not just a leading-# check): with word-splitting, the
# words of a multi-word comment line would otherwise leak in as bogus "files".
VHDL_FILES=()
for f in $(< "$BEHAVIORAL_DIR/cell_list_behavioral.txt"); do
    case "$f" in \#*) continue ;; esac
    case "${f##*.}" in
        vhd|vhdl) VHDL_FILES+=("$f") ;;
    esac
done

echo "  xmvhdl: ${#VHDL_FILES[@]} file(s)"
xmvhdl -V200X -WORK work -CONTROLRELAX nlstex -RELAX "${VHDL_FILES[@]}" \
    2>&1 | tee "$LOG_PATH/compile_vhdl.log"
[ "${PIPESTATUS[0]}" -ne 0 ] && { echo "VHDL compile failed — see $LOG_PATH/compile_vhdl.log"; exit 1; }

# ── 2. Elaborate each snapshot ────────────────────────────────────────────────
echo ""
echo "=== [2/3] Elaborating snapshots ==="
> "$LOG_PATH/elab.log"
for t in "${TESTS[@]}"; do
    echo "  elab: $t"
    xmelab -ACCESS +r "work.${t}" >> "$LOG_PATH/elab.log" 2>&1
    if [ $? -ne 0 ]; then
        echo "  ERROR: elaboration failed for $t — see $LOG_PATH/elab.log"
        exit 1
    fi
done

# ── 3. Simulate in parallel ───────────────────────────────────────────────────
echo ""
echo "=== [3/3] Simulating (MAX_PARALLEL=$MAX_PARALLEL, ${#TESTS[@]} tests) ==="
TOTAL=${#TESTS[@]}
STATUS_DIR="$LOG_PATH/.status"
rm -rf "$STATUS_DIR"; mkdir -p "$STATUS_DIR"

run_one() {
    local t="$1"
    local entity="${t%%:*}"
    xmsim "work.${t}" \
        -input batch_run.tcl \
        -licqueue \
        -LOGFILE "$LOG_PATH/${entity}.log" \
        > /dev/null 2>&1
    local result=FAIL
    grep -q "ALL CHECKS PASSED" "$LOG_PATH/${entity}.log" 2>/dev/null && result=PASS
    echo "$result" > "$STATUS_DIR/$entity"
    local done; done=$(ls "$STATUS_DIR" | wc -l)
    printf "  [%d/%d]  %-4s  %s\n" "$done" "$TOTAL" "$result" "$entity"
}

for t in "${TESTS[@]}"; do
    while [ "$(jobs -r -p | wc -l)" -ge "$MAX_PARALLEL" ]; do sleep 0.2; done
    run_one "$t" &
done
wait

# ── Collect results ───────────────────────────────────────────────────────────
echo ""
echo "=== Results ==="
PASS=0
FAIL=0
FAILED_TESTS=()
for t in "${TESTS[@]}"; do
    entity="${t%%:*}"
    if [ "$(cat "$STATUS_DIR/$entity" 2>/dev/null)" = PASS ]; then
        (( PASS++ ))
    else
        (( FAIL++ ))
        FAILED_TESTS+=("$entity")
    fi
done

echo ""
echo "  Passed: $PASS / $((PASS + FAIL))"
if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo "  Failed:"
    for t in "${FAILED_TESTS[@]}"; do
        echo "    $t  →  $LOG_PATH/${t}.log"
    done
    exit 1
fi
echo "  ALL PERIPHERAL TESTS PASSED"
