#!/bin/bash
# Parallel rv32ui test runner — POST-PLACE-&-ROUTE (innovus) gate-level sim with SDF.
#
# Same wrapper-per-test strategy as behavioral/xrun_parallel.sh, but the design
# under test is the placed-and-routed gate netlist (../../../innovus/out/MCU.xsim.v) and
# each snapshot is back-annotated with SDF timing at elaboration.
#
#   1. Generate a tiny VHDL wrapper entity per test (unique top = unique snapshot)
#   2. Compile all HDL (gate netlist + sim models + tb) + wrappers, once
#   3. Elaborate each wrapper with xmelab + SDF annotation (sequential)
#   4. Simulate all xmsim snapshots in parallel (throttled to MAX_PARALLEL licenses)
#
# Usage:
#   ./xrun_parallel.sh
#   MAX_PARALLEL=8 ./xrun_parallel.sh
#
# MAX_PARALLEL = number of simultaneous simulations. Each running xmsim checks
# out one Xcelium_Single_Core license. The pool on poseidon has 40 such seats,
# shared with all other users, so 40 is the hard ceiling; leave headroom if
# others are simulating. Sims use -licqueue, so any that can't grab a seat wait
# rather than fail. (Host has 128 cores / 251 GB, so licenses are the limit.)

source ~/vestarv/cdspaths.sh

RUN_DIR="$(cd "$(dirname "$0")" && pwd)"
WRAPPERS_DIR="$RUN_DIR/wrappers"
LOG_PATH="$RUN_DIR/log"
LIB_PATH="$RUN_DIR/xcelium.d"
CELL_LIST="$RUN_DIR/cell_list_innovus.txt"
SDF_CMD="$RUN_DIR/MCU.sdfcmd"               # original (top-level scope :dut)
SDF_CMD_PAR="$RUN_DIR/MCU.parallel.sdfcmd"  # generated below (scope :uut:dut)
MAX_PARALLEL=${MAX_PARALLEL:-8}

TEST_FILES=(
    "../rcf/xxxrv32ui-p-simple.rcf"
    "../rcf/xxxxxxrv32ui-p-add.rcf"
    "../rcf/xxxxxxxrv32ui-p-lb.rcf"
    "../rcf/xxxxxxxrv32ui-p-lh.rcf"
    "../rcf/xxxxxxxrv32ui-p-lw.rcf"
    "../rcf/xxxxxxrv32ui-p-lbu.rcf"
    "../rcf/xxxxxxrv32ui-p-lhu.rcf"
    "../rcf/xxxxxrv32ui-p-addi.rcf"
    "../rcf/xxxxxrv32ui-p-slli.rcf"
    "../rcf/xxxxxrv32ui-p-slti.rcf"
    "../rcf/xxxxrv32ui-p-sltiu.rcf"
    "../rcf/xxxxxrv32ui-p-srli.rcf"
    "../rcf/xxxxxrv32ui-p-srai.rcf"
    "../rcf/xxxxxxrv32ui-p-ori.rcf"
    "../rcf/xxxxxrv32ui-p-andi.rcf"
    "../rcf/xxxxrv32ui-p-auipc.rcf"
    "../rcf/xxxxxxxrv32ui-p-sb.rcf"
    "../rcf/xxxxxxxrv32ui-p-sh.rcf"
    "../rcf/xxxxxxxrv32ui-p-sw.rcf"
    "../rcf/xxxxxxrv32ui-p-sub.rcf"
    "../rcf/xxxxxxrv32ui-p-sll.rcf"
    "../rcf/xxxxxxrv32ui-p-slt.rcf"
    "../rcf/xxxxxrv32ui-p-sltu.rcf"
    "../rcf/xxxxxxrv32ui-p-xor.rcf"
    "../rcf/xxxxxxrv32ui-p-srl.rcf"
    "../rcf/xxxxxxrv32ui-p-sra.rcf"
    "../rcf/xxxxxxxrv32ui-p-or.rcf"
    "../rcf/xxxxxxrv32ui-p-and.rcf"
    "../rcf/xxxxxxrv32ui-p-lui.rcf"
    "../rcf/xxxxxxrv32ui-p-beq.rcf"
    "../rcf/xxxxxxrv32ui-p-bne.rcf"
    "../rcf/xxxxxxrv32ui-p-blt.rcf"
    "../rcf/xxxxxxrv32ui-p-bge.rcf"
    "../rcf/xxxxxrv32ui-p-bltu.rcf"
    "../rcf/xxxxxrv32ui-p-bgeu.rcf"
    "../rcf/xxxxxrv32ui-p-jalr.rcf"
    "../rcf/xxxxxxrv32ui-p-jal.rcf"
)

# Derive a valid VHDL entity name from a test file path.
# "../rcf/xxxxxxxrv32ui-p-lb.rcf" → "tb_rv32ui_p_lb"
snap_name() {
    basename "$1" .rcf | sed 's/^x*//' | tr '-' '_' | sed 's/^/tb_/'
}

# ── 1. Generate wrapper VHDL files ────────────────────────────────────────────
echo "=== [1/4] Generating per-test wrapper entities ==="
mkdir -p "$WRAPPERS_DIR"
WRAPPER_FILES=()
ENTITIES=()
for rcf in "${TEST_FILES[@]}"; do
    entity=$(snap_name "$rcf")
    ENTITIES+=("$entity")
    wf="$WRAPPERS_DIR/${entity}.vhd"
    WRAPPER_FILES+=("$wf")
    # Minimal wrapper: unique top-level entity that binds the test file generic.
    # Instance is named `uut`, so the DUT inside is reachable at :uut:dut (see SDF).
    cat > "$wf" <<VHDL
entity ${entity} is end ${entity};
architecture behavioral of ${entity} is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "${rcf}");
end architecture;
VHDL
done
echo "  ${#ENTITIES[@]} wrappers written to wrappers/"

# ── 2. Compile all HDL + wrappers ────────────────────────────────────────────
echo ""
echo "=== [2/4] Compiling HDL ==="
[ -d "$LIB_PATH" ] && rm -r "$LIB_PATH"
mkdir -p "$LOG_PATH"

cd "$RUN_DIR"

# The single-step `xrun` manages the library mapping internally. The standalone
# xmvlog/xmvhdl/xmelab/xmsim flow does not, so provide a cds.lib that pulls in
# the installed IEEE/std/synopsys libraries and defines the local `work` library.
mkdir -p "$LIB_PATH/work"
cat > "$RUN_DIR/cds.lib" <<LIB
SOFTINCLUDE ${XCELIUM_HOME}/tools/xcelium/files/cds.lib
DEFINE work ./xcelium.d/work
LIB

# Derive the parallel SDF command file from the single-test one. The original
# scopes SDF at :dut (DUT directly under top riscv_tb). The wrapper inserts one
# level (top → uut → dut), so the scope must become :uut:dut.
if [ ! -f "$SDF_CMD" ]; then
    echo "ERROR: $SDF_CMD not found (needed for SDF back-annotation)."; exit 1
fi
sed -E 's/(SCOPE[[:space:]]*=[[:space:]]*):dut/\1:uut:dut/' "$SDF_CMD" > "$SDF_CMD_PAR"

# Split the cell list into Verilog (.v) and VHDL (.vhd/.vhdl), preserving order.
# Unquoted word-splitting (like xrun.sh) tolerates trailing spaces / missing
# final newline that a per-line `read` loop would mis-handle.
VLOG_FILES=()
VHDL_FILES=()
for f in $(< "$CELL_LIST"); do
    case "$f" in \#*) continue ;; esac
    case "${f##*.}" in
        v)        VLOG_FILES+=("$f") ;;
        vhd|vhdl) VHDL_FILES+=("$f") ;;
    esac
done

if [ ${#VLOG_FILES[@]} -gt 0 ]; then
    echo "  xmvlog: ${#VLOG_FILES[@]} file(s)"
    xmvlog -WORK work "${VLOG_FILES[@]}" \
        2>&1 | tee "$LOG_PATH/compile_vlog.log"
    [ "${PIPESTATUS[0]}" -ne 0 ] && { echo "Verilog compile failed."; exit 1; }
fi

echo "  xmvhdl: ${#VHDL_FILES[@]} shared VHDL file(s)"
xmvhdl -V200X -WORK work -CONTROLRELAX nlstex -RELAX \
    "${VHDL_FILES[@]}" \
    2>&1 | tee "$LOG_PATH/compile_vhdl.log"
[ "${PIPESTATUS[0]}" -ne 0 ] && { echo "VHDL compile failed."; exit 1; }

echo "  xmvhdl: ${#WRAPPER_FILES[@]} wrapper file(s)"
xmvhdl -V200X -WORK work -CONTROLRELAX nlstex -RELAX \
    "${WRAPPER_FILES[@]}" \
    2>&1 | tee "$LOG_PATH/compile_wrappers.log"
[ "${PIPESTATUS[0]}" -ne 0 ] && { echo "Wrapper compile failed."; exit 1; }

# ── 3. Elaborate each snapshot with SDF (sequential, fast) ────────────────────
echo ""
echo "=== [3/4] Elaborating snapshots (SDF annotated) ==="
> "$LOG_PATH/elab.log"
for entity in "${ENTITIES[@]}"; do
    echo "  elab: $entity"
    xmelab -ACCESS +r \
        -sdf_cmd_file "$SDF_CMD_PAR" \
        -sdfstats "$LOG_PATH/sdf_stats.log" \
        "work.${entity}:behavioral" \
        >> "$LOG_PATH/elab.log" 2>&1
    if [ $? -ne 0 ]; then
        echo "  ERROR: elaboration failed for $entity — see $LOG_PATH/elab.log"
        exit 1
    fi
done

# ── 4. Simulate in parallel ───────────────────────────────────────────────────
echo ""
echo "=== [4/4] Simulating (MAX_PARALLEL=$MAX_PARALLEL, ${#ENTITIES[@]} tests) ==="
TOTAL=${#ENTITIES[@]}
STATUS_DIR="$LOG_PATH/.status"
rm -rf "$STATUS_DIR"; mkdir -p "$STATUS_DIR"

# Simulate one snapshot, then immediately classify and report its result, so
# PASS/FAIL lines stream to the terminal as each test finishes (in completion
# order, not submission order). The per-test status file lets the parent tally
# accurately afterward.
run_one() {
    local entity="$1"
    xmsim "work.${entity}:behavioral" \
        -input ../../disable_x_warnings.tcl \
        -input batch_run.tcl \
        -licqueue \
        -LOGFILE "$LOG_PATH/${entity}.log" \
        > /dev/null 2>&1
    local result=FAIL
    grep -q "TEST PASSED" "$LOG_PATH/${entity}.log" 2>/dev/null && result=PASS
    echo "$result" > "$STATUS_DIR/$entity"
    # Completion index = number of status files written so far.
    local done; done=$(ls "$STATUS_DIR" | wc -l)
    printf "  [%2d/%2d]  %-4s  %s\n" "$done" "$TOTAL" "$result" "$entity"
}

for entity in "${ENTITIES[@]}"; do
    while [ "$(jobs -r -p | wc -l)" -ge "$MAX_PARALLEL" ]; do
        sleep 0.2
    done
    run_one "$entity" &
done
wait

# ── Collect results ───────────────────────────────────────────────────────────
echo ""
echo "=== Results ==="
PASS=0
FAIL=0
FAILED_TESTS=()

for entity in "${ENTITIES[@]}"; do
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
echo "  ALL TESTS PASSED"
