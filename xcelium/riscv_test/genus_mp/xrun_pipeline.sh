#!/bin/bash
# PIPELINED test runner — POST-SYNTHESIS (genus) MCU_MP gate-level sim with SDF.
#
# Variant of xrun_parallel.sh (this dir). Same generate→compile front end, but
# the back end FUSES elaboration and simulation into one MAX_PARALLEL worker
# pool: each worker elaborates ONE snapshot then immediately simulates it, so
# elaborations of later tests overlap simulations of earlier ones instead of the
# original "elaborate all sequentially, THEN simulate in parallel". Gate-level
# SDF elaboration is the wall-time hog here, and each test elaborates into its
# own snapshot, so this is where the speedup comes from. Everything else — the
# wrapper/preload generation and the DUT/SDF gate-flow details below — is
# identical to xrun_parallel.sh.
#
# Same 4-step strategy as behavioral_mp/xrun_parallel.sh (wrapper-per-test →
# compile once → elaborate each → simulate in parallel), with the gate-flow
# deltas of riscv_test/genus/xrun_parallel.sh:
#   * DUT = ../../../genus/out/MCU_MP.genus.v, SDF back-annotated at xmelab
#     (MCU_MP.sdfcmd rescoped :dut → :uut:dut for the wrapper level).
#   * The netlist MCU has no generics: the behavioral tile-preload generics are
#     replaced by per-test xmsim DEPOSIT scripts into the tile SRAM macro
#     models (make_ram_deposit.py; harts 1-3 TCM + zeroed shared macros; deposits at t=1ns and
#     re-asserted at t=300ns inside the second reset pulse). The sh-protocol
#     tests preload their own image; everything else gets shmem_mp contention
#     tiles — same binding rule as every other flow.
#   * xmelab needs -ACCESS +rwc (deposits write into the models).
#
# Usage:
#   ./xrun_parallel.sh                              # full suite
#   TESTS_FILE=rv32ui.txt MAX_PARALLEL=6 ./xrun_parallel.sh   # subset
#
# GATE SIMS ARE SLOW — the behavioral 1-minute rule does NOT apply here.

source ~/vestarv/cdspaths.sh

RUN_DIR="$(cd "$(dirname "$0")" && pwd)"
WRAPPERS_DIR="$RUN_DIR/wrappers"
LOG_PATH="$RUN_DIR/log"
LIB_PATH="$RUN_DIR/xcelium.d"
CELL_LIST="$RUN_DIR/cell_list_genus_mp.txt"
SDF_CMD="$RUN_DIR/MCU_MP.sdfcmd"
SDF_CMD_PAR="$RUN_DIR/MCU_MP.parallel.sdfcmd"
IMG_DIR="/home/mseminario2/vestarv/xcelium/riscv_test/ram_images"
MAX_PARALLEL=${MAX_PARALLEL:-8}

TEST_FILES=(
    "../rcf/xxxrv32ui-p-simple.rcf"
    "../rcf/xxxxrv32ui-p-shmem.rcf"
    "../rcf/xrv32ui-p-shmem_mp.rcf"
    "../rcf/xxxrv32ui-p-shboot.rcf"
    "../rcf/xxxxrv32ui-p-shwfi.rcf"
    "../rcf/xxrv32ui-p-shclint.rcf"
    "../rcf/xxxrv32ui-p-shuart.rcf"
    "../rcf/xxxxrv32ui-p-shirq.rcf"
    "../rcf/xxrv32ui-p-shtimer.rcf"
    "../rcf/xrv32ui-p-shperiph.rcf"
    "../rcf/xxxxrv32ui-p-shi2c.rcf"
    "../rcf/xxxxrv32ui-p-shnpu.rcf"
    "../rcf/xxrv32ui-p-shmutex.rcf"
    "../rcf/xxxrv32ua-p-shspin.rcf"
    "../rcf/xxxrv32ua-p-shlock.rcf"
    "../rcf/xxxxrv32ua-p-shamo.rcf"
    "../rcf/xrv32ua-p-amoadd_w.rcf"
    "../rcf/xrv32ua-p-amoand_w.rcf"
    "../rcf/xrv32ua-p-amomax_w.rcf"
    "../rcf/xxrv32ua-p-shcount.rcf"
    "../rcf/rv32ua-p-amomaxu_w.rcf"
    "../rcf/xrv32ua-p-amomin_w.rcf"
    "../rcf/rv32ua-p-amominu_w.rcf"
    "../rcf/rv32ua-p-amoswap_w.rcf"
    "../rcf/xrv32ua-p-amoxor_w.rcf"
    "../rcf/xxrv32ua-p-amoor_w.rcf"
    "../rcf/xxxrv32ua-p-shlrsc.rcf"
    "../rcf/xxxxxrv32ua-p-lrsc.rcf"
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
    # rv32um — multiplication/division
    "../rcf/xxxrv32um-p-mulhsu.rcf"
    "../rcf/xxxxrv32um-p-mulhu.rcf"
    "../rcf/xxxxxrv32um-p-divu.rcf"
    "../rcf/xxxxxrv32um-p-mulh.rcf"
    "../rcf/xxxxxrv32um-p-remu.rcf"
    "../rcf/xxxxxxrv32um-p-div.rcf"
    "../rcf/xxxxxxrv32um-p-mul.rcf"
    "../rcf/xxxxxxrv32um-p-rem.rcf"
    # rv32uc — compressed (C extension)
    "../rcf/xxxxxxrv32uc-p-rvc.rcf"
    # rv32uzba — bitmanip address generation (Zba)
    "../rcf/xrv32uzba-p-sh1add.rcf"
    "../rcf/xrv32uzba-p-sh2add.rcf"
    "../rcf/xrv32uzba-p-sh3add.rcf"
    # rv32uzbb — bitmanip basic (Zbb)
    "../rcf/xrv32uzbb-p-sext_b.rcf"
    "../rcf/xrv32uzbb-p-sext_h.rcf"
    "../rcf/xrv32uzbb-p-zext_h.rcf"
    "../rcf/xxrv32uzbb-p-orc_b.rcf"
    "../rcf/xxxrv32uzbb-p-andn.rcf"
    "../rcf/xxxrv32uzbb-p-cpop.rcf"
    "../rcf/xxxrv32uzbb-p-maxu.rcf"
    "../rcf/xxxrv32uzbb-p-minu.rcf"
    "../rcf/xxxrv32uzbb-p-rev8.rcf"
    "../rcf/xxxrv32uzbb-p-rori.rcf"
    "../rcf/xxxrv32uzbb-p-xnor.rcf"
    "../rcf/xxxxrv32uzbb-p-clz.rcf"
    "../rcf/xxxxrv32uzbb-p-ctz.rcf"
    "../rcf/xxxxrv32uzbb-p-max.rcf"
    "../rcf/xxxxrv32uzbb-p-min.rcf"
    "../rcf/xxxxrv32uzbb-p-orn.rcf"
    "../rcf/xxxxrv32uzbb-p-rol.rcf"
    "../rcf/xxxxrv32uzbb-p-ror.rcf"
    # rv32uzbc — carry-less multiply (Zbc)
    "../rcf/xrv32uzbc-p-clmulh.rcf"
    "../rcf/xrv32uzbc-p-clmulr.rcf"
    "../rcf/xxrv32uzbc-p-clmul.rcf"
    # rv32uzbs — single-bit (Zbs)
    "../rcf/xxrv32uzbs-p-bclri.rcf"
    "../rcf/xxrv32uzbs-p-bexti.rcf"
    "../rcf/xxrv32uzbs-p-binvi.rcf"
    "../rcf/xxrv32uzbs-p-bseti.rcf"
    "../rcf/xxxrv32uzbs-p-bclr.rcf"
    "../rcf/xxxrv32uzbs-p-bext.rcf"
    "../rcf/xxxrv32uzbs-p-binv.rcf"
    "../rcf/xxxrv32uzbs-p-bset.rcf"
)

# Optional subset override, e.g. TESTS_FILE=rv32ui.txt (stage-2 pure-ISA set).
if [ -n "${TESTS_FILE:-}" ] && [ -f "$TESTS_FILE" ]; then
    mapfile -t TEST_FILES < <(grep -vE '^\s*(#|$)' "$TESTS_FILE")
    echo "TESTS_FILE=$TESTS_FILE → running ${#TEST_FILES[@]} test(s)"
fi

snap_name() {
    basename "$1" .rcf | sed 's/^x*//' | tr '-' '_' | sed 's/^/tb_/'
}

# ── 1. Generate wrappers + per-test preload/driver tcl ───────────────────────
echo "=== [1/4] Generating per-test wrappers + preload scripts ==="
mkdir -p "$WRAPPERS_DIR" "$LOG_PATH"
WRAPPER_FILES=()
ENTITIES=()
declare -A PRELOAD_DONE
for rcf in "${TEST_FILES[@]}"; do
    entity=$(snap_name "$rcf")
    ENTITIES+=("$entity")
    wf="$WRAPPERS_DIR/${entity}.vhd"
    WRAPPER_FILES+=("$wf")
    cat > "$wf" <<VHDL
entity ${entity} is end ${entity};
architecture behavioral of ${entity} is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "${rcf}");
end architecture;
VHDL
    # Tile preload image: sh-protocol tests use their own image, the rest the
    # shmem_mp contention tiles (same rule as behavioral_mp + xrun.sh here).
    base="$(basename "$rcf" .rcf | sed 's/^x*//')"
    case "$base" in
        *-shboot|*-shspin|*-shlock|*-shmutex|*-shamo|*-shwfi|*-shuart|*-shirq|*-shtimer|*-shperiph|*-shi2c|*-shnpu)
            img="$base" ;;
        *)  img="rv32ui-p-shmem_mp" ;;
    esac
    if [ -z "${PRELOAD_DONE[$img]:-}" ]; then
        python3 "$RUN_DIR/make_ram_deposit.py" \
            "$IMG_DIR/$img.ram0.rcf" ":uut:dut" \
            > "$LOG_PATH/preload_$img.tcl" || { echo "preload gen failed: $img"; exit 1; }
        PRELOAD_DONE[$img]=1
    fi
    cat > "$LOG_PATH/driver_${entity}.tcl" <<EOF
run 1 ns
source $LOG_PATH/preload_$img.tcl
run 299 ns
source $LOG_PATH/preload_$img.tcl
run
exit
EOF
done
echo "  ${#ENTITIES[@]} wrappers written to wrappers/ (+${#PRELOAD_DONE[@]} preload images)"

# ── 2. Compile all HDL + wrappers ────────────────────────────────────────────
echo ""
echo "=== [2/4] Compiling HDL ==="
[ -d "$LIB_PATH" ] && rm -r "$LIB_PATH"

cd "$RUN_DIR"

mkdir -p "$LIB_PATH/work"
cat > "$RUN_DIR/cds.lib" <<LIB
SOFTINCLUDE ${XCELIUM_HOME}/tools/xcelium/files/cds.lib
DEFINE work ./xcelium.d/work
LIB

# Rescope the SDF command file for the wrapper level (:dut → :uut:dut).
sed -E 's/(SCOPE[[:space:]]*=[[:space:]]*):dut/\1:uut:dut/' "$SDF_CMD" > "$SDF_CMD_PAR"

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

# ── 3. Elaborate + simulate, PIPELINED ───────────────────────────────────────
# Each worker does elaborate-then-simulate for one test, and up to MAX_PARALLEL
# workers run at once. Because every test elaborates into its OWN snapshot
# (work.tb_xxx:behavioral), the xmelab calls are independent — so while test A
# is simulating, test B is already elaborating. Total wall-time collapses toward
# the slowest single (elab+sim) chain instead of sum(all elabs)+parallel(sims).
#
# Deltas vs the sequential xrun_parallel.sh:
#   * per-entity elab log (elab_<entity>.log) — concurrent elabs must not share
#     one file, and -sdfstats is dropped for the same shared-write reason.
#   * -licqueue on xmelab too, so elaborations queue on a busy license pool
#     instead of erroring out (license is shared/seat-limited — keep
#     MAX_PARALLEL modest; every worker slot can hold an elab OR a sim license).
#   * an elaboration failure marks the test ELABFAIL (points at its elab log)
#     and does NOT abort the whole run — the other tests keep going.
echo ""
echo "=== [3/3] Pipelined elaborate+simulate (MAX_PARALLEL=$MAX_PARALLEL, ${#ENTITIES[@]} tests) ==="
TOTAL=${#ENTITIES[@]}
# Own status dir (NOT the original xrun_parallel.sh's .status) so the two
# scripts' progress counters never collide if both run / leftovers linger.
STATUS_DIR="$LOG_PATH/.status_pipe"
rm -rf "$STATUS_DIR"; mkdir -p "$STATUS_DIR"

run_one() {
    local entity="$1"
    # --- elaborate (SDF annotated) ---
    # -nonotifier (M9b, same as xrun.sh): timing-check violations still print
    # but no longer X the violating flop — the tb's reset release trips
    # reset-time $hold(SN/R) checks whose notifier-X kills the chip.
    xmelab -ACCESS +rwc -nonotifier -licqueue \
        -sdf_cmd_file "$SDF_CMD_PAR" \
        "work.${entity}:behavioral" \
        > "$LOG_PATH/elab_${entity}.log" 2>&1
    if [ $? -ne 0 ]; then
        echo "ELABFAIL" > "$STATUS_DIR/$entity"
        local done; done=$(ls "$STATUS_DIR" | wc -l)
        printf "  [%3d/%3d]  %-8s  %s\n" "$done" "$TOTAL" "ELABFAIL" "$entity"
        return
    fi
    # --- simulate ---
    xmsim "work.${entity}:behavioral" \
        -input ../../disable_x_warnings.tcl \
        -input "$LOG_PATH/driver_${entity}.tcl" \
        -licqueue \
        -LOGFILE "$LOG_PATH/${entity}.log" \
        > /dev/null 2>&1
    local result=FAIL
    grep -q "TEST PASSED" "$LOG_PATH/${entity}.log" 2>/dev/null && result=PASS
    echo "$result" > "$STATUS_DIR/$entity"
    local done; done=$(ls "$STATUS_DIR" | wc -l)
    printf "  [%3d/%3d]  %-8s  %s\n" "$done" "$TOTAL" "$result" "$entity"
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
        if [ "$(cat "$STATUS_DIR/$t" 2>/dev/null)" = ELABFAIL ]; then
            echo "    $t  →  (elaboration) $LOG_PATH/elab_${t}.log"
        else
            echo "    $t  →  $LOG_PATH/${t}.log"
        fi
    done
    exit 1
fi
echo "  ALL TESTS PASSED"
