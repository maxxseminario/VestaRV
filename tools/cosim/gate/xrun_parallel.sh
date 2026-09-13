#!/bin/bash
# VestaRV: parallel ISA test runner. One VHDL wrapper entity per test gives each
# test a unique top-level name and so a unique snapshot; the HDL and wrappers
# compile once, each snapshot elaborates in sequence, and the simulations run in
# parallel.
#   ./xrun_parallel.sh
#   MAX_PARALLEL=8 ./xrun_parallel.sh
# MAX_PARALLEL is the number of simultaneous simulations. Each xmsim holds one
# Xcelium_Single_Core license and the pool on poseidon has 40 seats shared with
# every other user, so 40 is the ceiling and headroom is polite. The sims pass
# -licqueue, so one that cannot get a seat waits instead of failing. The host has
# 128 cores and 251 GB, so licenses are the limit, not the machine.

source ~/vestarv/cdspaths.sh

BEHAVIORAL_DIR="$(cd "$(dirname "$0")" && pwd)"
WRAPPERS_DIR="$BEHAVIORAL_DIR/wrappers"
LOG_PATH="$BEHAVIORAL_DIR/log"
LIB_PATH="$BEHAVIORAL_DIR/xcelium.d"
MAX_PARALLEL=${MAX_PARALLEL:-8}

TEST_FILES=(
    # This array is generated, not hand-built: it is verify_stage.py's catalog
    # selection for the shipped default configuration (five harts, orchestrator
    # true), in the catalog's own order, minus three rows.
    #   rv32ua-p-rocsrw and rv32ua-p-shapeq are ON-polarity only. Their #else arms
    #     load 0x5E10BAD0 and jump to a fail label, so on the canonical ../rcf/
    #     set, which is the DEFINES=(none) polarity this runner reads, they fail by
    #     construction. They are also the two halves of check_image_polarity.py's
    #     known-nonzero control, which a standing listing would break.
    #   rv32ua-p-rocsrwmp is excluded on its own header's instruction
    #     (rv32ua/rocsrw.S:52): it is a `make verify` catalog row by design. It
    #     passes on this polarity.
    # To regenerate: run `SUITE=full make verify` in platform/common at the default
    # config, take verify_castalia/xrun_parallel.sh's TEST_FILES array, repoint
    # ../k33/ at ../rcf/, and drop those three rows.
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
    "../rcf/xxrv32ui-p-shexecc.rcf"
    "../rcf/xxxxrv32ui-p-shpwr.rcf"
    "../rcf/xxxrv32ui-p-shorch.rcf"
    "../rcf/xxxxrv32ui-p-shtcm.rcf"
    "../rcf/xrv32ui-p-wnpuconv.rcf"
    "../rcf/xxxxrv32ui-p-wxnpu.rcf"
    "../rcf/xxxxrv32ui-p-wgemm.rcf"
    "../rcf/xxxxrv32ui-p-wactf.rcf"
    "../rcf/xxxxrv32ui-p-afsel.rcf"
    "../rcf/xxrv32ui-p-afselv2.rcf"
    "../rcf/xxxrv32ua-p-shspin.rcf"
    "../rcf/xxxrv32ua-p-shlock.rcf"
    "../rcf/xxxxrv32ua-p-shamo.rcf"
    "../rcf/xxrv32ua-p-shzabha.rcf"
    "../rcf/xxrv32ua-p-shzacas.rcf"
    "../rcf/xxrv32ua-p-shcaslr.rcf"
    "../rcf/xxxrv32ua-p-shmixw.rcf"
    "../rcf/xxxrv32ua-p-shcboz.rcf"
    "../rcf/xxxxrv32ua-p-shcmp.rcf"
    "../rcf/rv32ua-p-shcmppush.rcf"
    "../rcf/xxxxrv32ua-p-shcmt.rcf"
    "../rcf/xxrv32ua-p-shpause.rcf"
    "../rcf/xrv32ua-p-amoadd_w.rcf"
    "../rcf/xrv32ua-p-amoalias.rcf"
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
    "../rcf/xxrv32ua-p-idcsrmp.rcf"
    "../rcf/xrv32ua-p-rdtimemp.rcf"
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
    "../rcf/xxxxxxrv32ui-p-zbk.rcf"
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
    "../rcf/xxxrv32um-p-mulhsu.rcf"
    "../rcf/xxxxrv32um-p-mulhu.rcf"
    "../rcf/xxxxxrv32um-p-divu.rcf"
    "../rcf/xxxxxrv32um-p-mulh.rcf"
    "../rcf/xxxxxrv32um-p-remu.rcf"
    "../rcf/xxxxxxrv32um-p-div.rcf"
    "../rcf/xxxxxxrv32um-p-mul.rcf"
    "../rcf/xxxxxxrv32um-p-rem.rcf"
    "../rcf/xxxxxxrv32uc-p-rvc.rcf"
    "../rcf/xrv32uzba-p-sh1add.rcf"
    "../rcf/xrv32uzba-p-sh2add.rcf"
    "../rcf/xrv32uzba-p-sh3add.rcf"
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
    "../rcf/xrv32uzbc-p-clmulh.rcf"
    "../rcf/xrv32uzbc-p-clmulr.rcf"
    "../rcf/xxrv32uzbc-p-clmul.rcf"
    "../rcf/xxrv32uzbs-p-bclri.rcf"
    "../rcf/xxrv32uzbs-p-bexti.rcf"
    "../rcf/xxrv32uzbs-p-binvi.rcf"
    "../rcf/xxrv32uzbs-p-bseti.rcf"
    "../rcf/xxxrv32uzbs-p-bclr.rcf"
    "../rcf/xxxrv32uzbs-p-bext.rcf"
    "../rcf/xxxrv32uzbs-p-binv.rcf"
    "../rcf/xxxrv32uzbs-p-bset.rcf"
    "../rcf/xrv32ua-p-extprobe.rcf"
    "../rcf/xxxrv32ua-p-extmul.rcf"
    "../rcf/xxxrv32ua-p-extdiv.rcf"
    "../rcf/xxxrv32ua-p-extamo.rcf"
    "../rcf/xxxrv32ua-p-extrvc.rcf"
    "../rcf/xxxxrv32ua-p-extzb.rcf"
    "../rcf/xrv32ua-p-extzihpm.rcf"
    "../rcf/rv32ua-p-extzicond.rcf"
    "../rcf/xxxrv32ua-p-extzcb.rcf"
    "../rcf/rv32ua-p-extzihint.rcf"
    "../rcf/xrv32ua-p-extzawrs.rcf"
    "../rcf/xxxxrv32ua-p-shwrs.rcf"
    "../rcf/xrv32ua-p-extzfinx.rcf"
    "../rcf/xrv32ua-p-trapstor.rcf"
    "../rcf/rv32ua-p-packalias.rcf"
    "../rcf/xxxrv32ua-p-fk51mp.rcf"
    "../rcf/xrv32um-p-dvintmin.rcf"
    "../rcf/xrv32um-p-dvbubble.rcf"
)

# Subset override: TESTS_FILE=smoke.txt runs only the rcf paths listed in that
# file, one per line, instead of the array above. Unset means full regression.
if [ -n "${TESTS_FILE:-}" ] && [ -f "$TESTS_FILE" ]; then
    mapfile -t TEST_FILES < <(grep -vE '^\s*(#|$)' "$TESTS_FILE")
    echo "TESTS_FILE=$TESTS_FILE → running ${#TEST_FILES[@]} test(s)"
fi

# A valid VHDL entity name from a test file path:
# "../rcf/xxxxxxxrv32ui-p-lb.rcf" becomes "tb_rv32ui_p_lb".
snap_name() {
    basename "$1" .rcf | sed 's/^x*//' | tr '-' '_' | sed 's/^/tb_/'
}

# 1. Generate the wrapper VHDL files.
echo "=== [1/4] Generating per-test wrapper entities ==="
mkdir -p "$WRAPPERS_DIR"
WRAPPER_FILES=()
ENTITIES=()
for rcf in "${TEST_FILES[@]}"; do
    entity=$(snap_name "$rcf")
    ENTITIES+=("$entity")
    wf="$WRAPPERS_DIR/${entity}.vhd"
    WRAPPER_FILES+=("$wf")
    # A unique top-level entity binding the test-file generic. riscv_tb is a
    # testbench, so the wrapper needs no ports and no signals. TEST_FILE is the
    # only generic: every hart boots from the shared ROM as in silicon, and the
    # sh-protocol tests load their tiles at runtime through the bootrom's msip
    # loader mailboxes rather than through a TCM preload.
    cat > "$wf" <<VHDL
entity ${entity} is end ${entity};
architecture behavioral of ${entity} is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "${rcf}");
end architecture;
VHDL
done
echo "  ${#ENTITIES[@]} wrappers written to wrappers/"

# 2. Compile the HDL and the wrappers.
echo ""
echo "=== [2/4] Compiling HDL ==="
[ -d "$LIB_PATH" ] && rm -r "$LIB_PATH"
mkdir -p "$LOG_PATH"

cd "$BEHAVIORAL_DIR"

# Single-step xrun manages the library mapping internally; the standalone
# xmvlog/xmvhdl/xmelab/xmsim flow does not, so this cds.lib pulls in the
# installed IEEE, std and synopsys libraries and defines the local work library.
mkdir -p "$LIB_PATH/work"
cat > "$BEHAVIORAL_DIR/cds.lib" <<LIB
SOFTINCLUDE ${XCELIUM_HOME}/tools/xcelium/files/cds.lib
DEFINE work ./xcelium.d/work
LIB

# Split cell_list_behavioral.txt into Verilog and VHDL. Unquoted word splitting,
# not a per-line `read` loop: the latter misclassifies a name with a trailing
# space and drops the last line when the file has no final newline.
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

# 3. Elaborate each snapshot, in sequence.
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

# 4. Simulate in parallel.
echo ""
echo "=== [4/4] Simulating (MAX_PARALLEL=$MAX_PARALLEL, ${#ENTITIES[@]} tests) ==="
TOTAL=${#ENTITIES[@]}
STATUS_DIR="$LOG_PATH/.status"
rm -rf "$STATUS_DIR"; mkdir -p "$STATUS_DIR"

# Simulate one snapshot, then classify and report it at once, so PASS and FAIL
# lines stream in completion order rather than submission order. The per-test
# status file is what the parent tallies afterwards.
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
    # The completion index is the number of status files written so far.
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

# Collect the results.
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
