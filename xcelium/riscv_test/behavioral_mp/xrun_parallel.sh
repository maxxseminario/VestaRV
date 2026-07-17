#!/bin/bash
# Parallel rv32ui test runner — 4-step Xcelium flow:
#   1. Generate a tiny VHDL wrapper entity per test (unique top-level name = unique snapshot)
#   2. Compile all HDL + wrappers with xmvhdl/xmvlog (once)
#   3. Elaborate each wrapper with xmelab (sequential, fast)
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

BEHAVIORAL_DIR="$(cd "$(dirname "$0")" && pwd)"
WRAPPERS_DIR="$BEHAVIORAL_DIR/wrappers"
LOG_PATH="$BEHAVIORAL_DIR/log"
LIB_PATH="$BEHAVIORAL_DIR/xcelium.d"
MAX_PARALLEL=${MAX_PARALLEL:-8}

TEST_FILES=(
    "../rcf/xxxrv32ui-p-simple.rcf"
    "../rcf/xxxxrv32ui-p-shmem.rcf"
    "../rcf/xrv32ui-p-shmem_mp.rcf"
    "../rcf/xxxrv32ui-p-shboot.rcf"
    "../rcf/xxxxrv32ui-p-shwfi.rcf"
    "../rcf/xxrv32ui-p-shclint.rcf"
    "../rcf/xxxrv32ui-p-irqctx.rcf"
    "../rcf/xxxrv32ui-p-shuart.rcf"
    "../rcf/xxxxrv32ui-p-shirq.rcf"
    "../rcf/xxrv32ui-p-shtimer.rcf"
    "../rcf/xrv32ui-p-shperiph.rcf"
    "../rcf/xxxxrv32ui-p-shi2c.rcf"
    "../rcf/xxxxrv32ui-p-shnpu.rcf"
    "../rcf/xxrv32ui-p-shmutex.rcf"
    "../rcf/xxxrv32ui-p-shexec.rcf"
    "../rcf/xxxxrv32ui-p-shpwr.rcf"
    "../rcf/xxxxrv32ui-p-shafe.rcf"
    "../rcf/xxxxrv32ui-p-afsel.rcf"
    "../rcf/xxrv32ui-p-afselv2.rcf"
    "../rcf/xxxrv32ua-p-shspin.rcf"
    "../rcf/xxxrv32ua-p-shlock.rcf"
    "../rcf/xxxxrv32ua-p-shamo.rcf"
    "../rcf/xxrv32ua-p-shpause.rcf"
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
    # core-features (ENABLE_* generics): misa + per-extension adaptive probes.
    # On this full build every one PASSES; the same images double as the
    # stripped-build trap controls (behavioral_mp_stripped/run_extoff.sh).
    "../rcf/xrv32ua-p-extprobe.rcf"
    "../rcf/xxxrv32ua-p-extmul.rcf"
    "../rcf/xxxrv32ua-p-extdiv.rcf"
    "../rcf/xxxrv32ua-p-extamo.rcf"
    "../rcf/xxxrv32ua-p-extrvc.rcf"
    "../rcf/xxxxrv32ua-p-extzb.rcf"
    "../rcf/xrv32ua-p-extzihpm.rcf"
    "../rcf/rv32ua-p-extzicond.rcf"
    # X1 Zcb: build-time-dispatch probe. Default (Zcb-off) build compiles the
    # OFF arm (base-ISA sanity + PASS); the ON arm + trap proof run on staged
    # builds (see the X1-zcb self-report).
    "../rcf/xxxrv32ua-p-extzcb.rcf"

    "../rcf/rv32ua-p-extzihint.rcf"
)

# Optional subset override: `TESTS_FILE=smoke.txt ./xrun_parallel.sh` runs only the
# rcf paths listed (one per line) in that file instead of the full array above.
# Used for quick smoke runs; unset → full regression.
if [ -n "${TESTS_FILE:-}" ] && [ -f "$TESTS_FILE" ]; then
    mapfile -t TEST_FILES < <(grep -vE '^\s*(#|$)' "$TESTS_FILE")
    echo "TESTS_FILE=$TESTS_FILE → running ${#TEST_FILES[@]} test(s)"
fi

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
    # No ports (riscv_tb is a testbench), no signal declarations needed.
    # M12: the tile-TCM preload (HART_RAM0_INIT) is RETIRED — every hart boots
    # from the shared ROM like silicon, so the wrapper carries ONLY TEST_FILE.
    # sh-protocol tests load their tiles at runtime through the bootrom's msip
    # loader mailboxes; the old sh-glob case + ram_images/*.ram0.rcf are gone.
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

cd "$BEHAVIORAL_DIR"

# The single-step `xrun` manages the library mapping internally. The standalone
# xmvlog/xmvhdl/xmelab/xmsim flow does not, so provide a cds.lib that pulls in
# the installed IEEE/std/synopsys libraries and defines the local `work` library.
mkdir -p "$LIB_PATH/work"
cat > "$BEHAVIORAL_DIR/cds.lib" <<LIB
SOFTINCLUDE ${XCELIUM_HOME}/tools/xcelium/files/cds.lib
DEFINE work ./xcelium.d/work
LIB

# Split cell_list_behavioral.txt into Verilog (.v) and VHDL (.vhd/.vhdl).
# Use unquoted word-splitting (like xrun_batch.sh) so trailing spaces and a
# missing final newline don't silently drop files — a per-line `read` loop
# mis-classifies "...AFE_FSM.vhd " (trailing space) and skips the last line.
VLOG_FILES=()
VHDL_FILES=()
for f in $(< "$BEHAVIORAL_DIR/cell_list_behavioral.txt"); do
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

# ── 3. Elaborate each snapshot (sequential, fast) ────────────────────────────
echo ""
echo "=== [3/4] Elaborating snapshots ==="
> "$LOG_PATH/elab.log"
for entity in "${ENTITIES[@]}"; do
    echo "  elab: $entity"
    xmelab -ACCESS +r "work.${entity}:behavioral" \
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
