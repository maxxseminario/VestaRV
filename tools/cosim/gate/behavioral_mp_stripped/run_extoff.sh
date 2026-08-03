#!/bin/bash
# run_extoff.sh — STRIPPED-BUILD negative controls for the core-features work
# (configurable ENABLE_MUL/DIV/ATOMICS/COMPRESSED/BITMANIP generics).
#
# ./stripped_hdl/{MCU.vhd,MemoryMap.vhd} are a `make chip` product generated
# with EVERY extension disabled (CORE_ENABLE_* all false). To refresh them,
# generate against an all-false config (the isa.* knobs live in _CONFIG_SCHEMA;
# the old sed-the-generator recipe is obsolete since the _isa[...] rework):
#   cd platform/common
#   cat > /tmp/stripped_cfg.json <<'EOF'
#   {"isa": {"mul": false, "div": false, "atomics": false,
#            "compressed": false, "bitmanip": false}}
#   EOF
#   CHIP_CONFIG=/tmp/stripped_cfg.json make chip
#   cp out/hdl/{MCU,MemoryMap}.vhd <here>/stripped_hdl/
#   make chip   # restore the default all-on out/ + resolved config
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
    "../rcf/rv32ua-p-extbadcsr.rcf"
    "../rcf/xrv32ua-p-extzimop.rcf"
    "../rcf/rv32ua-p-extzawrsx.rcf"   # X1 Zawrs OFF poison: wrs.nto must trap illegal
    "../rcf/xrv32ua-p-extzabha.rcf"   # X2 Zabha OFF poison: amoadd.b must trap illegal
    "../rcf/xrv32ua-p-extzacas.rcf"   # X2 Zacas OFF poison: amocas.w must trap illegal
    "../rcf/xxrv32ua-p-extzbkb.rcf"   # X3 Zbkb OFF poison: packh must trap illegal
    "../rcf/xxrv32ua-p-extzbkx.rcf"   # X3 Zbkx OFF poison: xperm8 must trap illegal
    "../rcf/rv32ua-p-extzbkrsv.rcf"   # X3 reserved 001/0x698 (BINVI-shamt24) must trap w/o Zbs
    "../rcf/xxxrv32ua-p-casill.rcf"   # X2 Zacas: amocas.d is illegal on EVERY build
                                      # (P0 2026-07-28: was "xrv32ua-p-casill.rcf",
                                      #  20 chars -- no such file and it broke the
                                      #  fixed 29-char TEST_FILE contract)
    "../rcf/rv32ua-p-extzicboz.rcf"   # X3 Zicboz OFF poison: cbo.zero must trap illegal
    "../rcf/xxrv32ua-p-cbozill.rcf"   # X3 Zicboz: cbo.clean is illegal on EVERY build
    "../rcf/xxrv32ua-p-extzcmp.rcf"   # X3 Zcmp OFF poison: cm.push must trap illegal
    "../rcf/xxrv32ua-p-extzcmt.rcf"   # X3 Zcmt OFF poison: cm.jt must trap illegal
    "../rcf/xxxrv32ua-p-extjvt.rcf"   # X3 Zcmt OFF poison: jvt CSR access must trap illegal
    "../rcf/xxrv32ua-p-extzkne.rcf"   # X3 Zkne OFF poison: aes32esmi must trap illegal
    "../rcf/xxrv32ua-p-extzknd.rcf"   # X3 Zknd OFF poison: aes32dsmi must trap illegal
    "../rcf/xxrv32ua-p-extzknh.rcf"   # X3 Zknh OFF poison: sha256sig0 must trap illegal
    # X4 Zfinx OFF poisons: every FP encoding class must trap illegal when
    # ENABLE_ZFINX is off (the core dead-ends the first illegal insn, so each
    # encoding class needs its own image). flw/fsw/fmv.w.x/fmv.x.w have NO Zfinx
    # form and must trap on EVERY build.
    "../rcf/xxxrv32ua-p-zfopfp.rcf"   # X4 OP-FP 0x53 (fadd.s) must trap illegal
    "../rcf/xxxxrv32ua-p-zffma.rcf"   # X4 FMADD 0x43 must trap illegal
    "../rcf/xxxxrv32ua-p-zffms.rcf"   # X4 FMSUB 0x47 must trap illegal
    "../rcf/xxxxrv32ua-p-zfnms.rcf"   # X4 FNMSUB 0x4b must trap illegal
    "../rcf/xxxxrv32ua-p-zfnma.rcf"   # X4 FNMADD 0x4f must trap illegal
    "../rcf/xxxxrv32ua-p-zfflw.rcf"   # X4 LOAD-FP 0x07 (flw) must trap on EVERY build
    "../rcf/xxxxrv32ua-p-zffsw.rcf"   # X4 STORE-FP 0x27 (fsw) must trap on EVERY build
    "../rcf/xxxrv32ua-p-zfmvwx.rcf"   # X4 fmv.w.x (no Zfinx form) must trap on EVERY build
    "../rcf/xxxrv32ua-p-zfmvxw.rcf"   # X4 fmv.x.w (no Zfinx form) must trap on EVERY build
    "../rcf/xrv32ua-p-zffflags.rcf"   # X4 fflags CSR (0x001) must trap illegal
    "../rcf/xxxxrv32ua-p-zffrm.rcf"   # X4 frm CSR (0x002) must trap illegal
    "../rcf/xxxrv32ua-p-zffcsr.rcf"   # X4 fcsr CSR (0x003) must trap illegal
    # P0 privprobe OFF poisons (2026-07-28): every p0_specs.md 2.1 trap CSR
    # address plus MRET/ECALL/EBREAK/WFI must trap illegal while ENABLE_TRAPCSR
    # is off (= every build today). One trap per image -- TRAP_STATE is
    # terminal, so a single image can only ever prove ONE encoding illegal.
    "../rcf/xxrv32ua-p-privmst.rcf"   # P1 mstatus  (0x300) must trap illegal
    "../rcf/xrv32ua-p-privmsth.rcf"   # P1 mstatush (0x310) must trap illegal
    "../rcf/xrv32ua-p-privmtvc.rcf"   # P1 mtvec    (0x305) must trap illegal
    "../rcf/xxrv32ua-p-privmie.rcf"   # P1 mie      (0x304) must trap illegal
    "../rcf/xxrv32ua-p-privmip.rcf"   # P1 mip      (0x344) must trap illegal
    "../rcf/xrv32ua-p-privmscr.rcf"   # P1 mscratch (0x340) must trap illegal
    "../rcf/xrv32ua-p-privmepc.rcf"   # P1 mepc     (0x341) must trap illegal
    "../rcf/xrv32ua-p-privmcau.rcf"   # P1 mcause   (0x342) must trap illegal
    "../rcf/xrv32ua-p-privmtvl.rcf"   # P1 mtval    (0x343) must trap illegal
    "../rcf/xrv32ua-p-privmtrc.rcf"   # P1 mtrapctl (0x7C0) must trap illegal
    "../rcf/xrv32ua-p-privmret.rcf"   # P1 MRET   0x30200073 must trap illegal
    "../rcf/xrv32ua-p-privecal.rcf"   # P1 ECALL  0x00000073 must trap illegal
    "../rcf/xrv32ua-p-privebrk.rcf"   # P1 EBREAK 0x00100073 must trap illegal
    "../rcf/xxrv32ua-p-privwfi.rcf"   # P2 WFI    0x10500073 must trap illegal
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
