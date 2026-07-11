#!/bin/bash
# run_extoff.sh — STRIPPED-BUILD negative controls for the core-features work
# (configurable ENABLE_MUL/DIV/ATOMICS/COMPRESSED/BITMANIP generics).
#
# ./stripped_hdl/{MCU.vhd,MemoryMap.vhd} are a `make chip` product generated
# with EVERY extension disabled (CORE_ENABLE_* all false). To refresh them:
#   cd platform_castalia/python
#   sed -e 's/COMPRESSED_ISA=True/COMPRESSED_ISA=False/' \
#       -e 's/ENABLE_\(FAST_\)\?MUL=True/ENABLE_\1MUL=False/' \
#       -e 's/ENABLE_DIV=True/ENABLE_DIV=False/' \
#       -e 's/ENABLE_ATOMICS=True/ENABLE_ATOMICS=False/' \
#       -e 's/ENABLE_BITMANIP=True/ENABLE_BITMANIP=False/' \
#       generate.py > generate_stripped.py && python3 generate_stripped.py
#   cp ../out/hdl/{MCU,MemoryMap}.vhd <here>/stripped_hdl/
#   rm generate_stripped.py && cd .. && make generate   # restore all-on out/
#
# Expected verdicts on the stripped build:
#   extprobe                          -> PASS      (base RV32I + misa work;
#                                                   also proves the rv32i
#                                                   bootrom boots this chip)
#   extmul/extdiv/extamo/extrvc/extzb -> TRAP_OK   (the disabled instruction
#                                                   took the illegal-instr
#                                                   trap; watched via
#                                                   trap_watch.tcl instead of
#                                                   the 100 ms tb watchdog)
# Anything else (SURVIVED / UNEXPECTED_PASS / TIMEOUT / FAIL) is a broken
# gating path. Compile/elab mechanics mirror behavioral_mp/xrun_parallel.sh.

source ~/vestarv/cdspaths.sh
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_PATH="$DIR/log"
LIB_PATH="$DIR/xcelium.d"
cd "$DIR"

PROBE_RCF="../rcf/xrv32ua-p-extprobe.rcf"
POISON_RCFS=(
    "../rcf/xxxrv32ua-p-extmul.rcf"
    "../rcf/xxxrv32ua-p-extdiv.rcf"
    "../rcf/xxxrv32ua-p-extamo.rcf"
    "../rcf/xxxrv32ua-p-extrvc.rcf"
    "../rcf/xxxxrv32ua-p-extzb.rcf"
)

snap_name() { basename "$1" .rcf | sed 's/^x*//' | tr '-' '_' | sed 's/^/tb_/'; }

echo "=== [1/4] wrappers ==="
mkdir -p wrappers "$LOG_PATH"
ENTITIES=()
WRAPPER_FILES=()
for rcf in "$PROBE_RCF" "${POISON_RCFS[@]}"; do
    entity=$(snap_name "$rcf")
    ENTITIES+=("$entity")
    wf="wrappers/${entity}.vhd"
    WRAPPER_FILES+=("$wf")
    cat > "$wf" <<VHDL
entity ${entity} is end ${entity};
architecture behavioral of ${entity} is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "${rcf}");
end architecture;
VHDL
done

echo "=== [2/4] compile (stripped MCU + MemoryMap) ==="
[ -d "$LIB_PATH" ] && rm -r "$LIB_PATH"
mkdir -p "$LIB_PATH/work"
cat > cds.lib <<LIB
SOFTINCLUDE ${XCELIUM_HOME}/tools/xcelium/files/cds.lib
DEFINE work ./xcelium.d/work
LIB

VLOG_FILES=()
VHDL_FILES=()
for f in $(< cell_list_stripped.txt); do
    case "$f" in \#*) continue ;; esac
    case "${f##*.}" in
        v)        VLOG_FILES+=("$f") ;;
        vhd|vhdl) VHDL_FILES+=("$f") ;;
    esac
done
[ ${#VLOG_FILES[@]} -gt 0 ] && { xmvlog -WORK work "${VLOG_FILES[@]}" > "$LOG_PATH/compile_vlog.log" 2>&1 || { echo "vlog FAILED"; exit 1; }; }
xmvhdl -V200X -WORK work -CONTROLRELAX nlstex -RELAX "${VHDL_FILES[@]}" > "$LOG_PATH/compile_vhdl.log" 2>&1 || { echo "vhdl FAILED — see $LOG_PATH/compile_vhdl.log"; exit 1; }
xmvhdl -V200X -WORK work -CONTROLRELAX nlstex -RELAX "${WRAPPER_FILES[@]}" > "$LOG_PATH/compile_wrappers.log" 2>&1 || { echo "wrapper vhdl FAILED"; exit 1; }

echo "=== [3/4] elaborate ==="
> "$LOG_PATH/elab.log"
for entity in "${ENTITIES[@]}"; do
    echo "  elab: $entity"
    xmelab -ACCESS +r "work.${entity}:behavioral" >> "$LOG_PATH/elab.log" 2>&1 || { echo "elab FAILED for $entity"; exit 1; }
done

echo "=== [4/4] simulate ==="
FAILS=0

# Positive control: extprobe must PASS through the normal harness.
entity=$(snap_name "$PROBE_RCF")
xmsim "work.${entity}:behavioral" -input ../../disable_x_warnings.tcl -input batch_run.tcl \
    -licqueue -LOGFILE "$LOG_PATH/${entity}.log" > /dev/null 2>&1
if grep -q "TEST PASSED" "$LOG_PATH/${entity}.log"; then
    echo "  PASS      $entity  (positive control: base ISA + misa on stripped build)"
else
    echo "  FAIL      $entity  — see $LOG_PATH/${entity}.log"
    FAILS=$((FAILS+1))
fi

# Negative controls: each poison must be seen trapping.
for rcf in "${POISON_RCFS[@]}"; do
    entity=$(snap_name "$rcf")
    xmsim "work.${entity}:behavioral" -input trap_watch.tcl \
        -licqueue -LOGFILE "$LOG_PATH/${entity}.log" > /dev/null 2>&1
    verdict=$(grep -o "EXTOFF_VERDICT=[A-Z_]*" "$LOG_PATH/${entity}.log" | tail -1 | cut -d= -f2)
    if [ "$verdict" = "TRAP_OK" ]; then
        echo "  TRAP_OK   $entity"
    else
        echo "  BAD:${verdict:-NONE}  $entity  — see $LOG_PATH/${entity}.log"
        FAILS=$((FAILS+1))
    fi
done

echo ""
if [ "$FAILS" -eq 0 ]; then
    echo "ALL STRIPPED-BUILD CONTROLS PASSED (1 positive + ${#POISON_RCFS[@]} trap)"
else
    echo "$FAILS control(s) FAILED"
    exit 1
fi
