#!/usr/bin/env bash
# run_isa.sh — build the riscv-tests ISA suites for the `vesta` core and run
# each test through the pure-GHDL testbench (vesta_isa_tb.vhd), reporting
# PASS/FAIL/TIMEOUT per test and a final summary.
#
#   Usage:  run_isa.sh [suite ...]
#   Default suites: the 8 real vesta regression suites (see DEFAULT_SUITES).
#
#   Env:
#     RISCV_PREFIX  gcc/objcopy prefix (default riscv-none-elf-)
#     GHDL          ghdl binary       (default ghdl)
#     TIMEOUT_S     per-test wall-clock timeout in seconds (default 120)
#
# All GHDL artifacts land in opensource_sim/isa/work/ (gitignored by another
# agent) via --workdir, so the repo tree stays clean.
set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
ISA_DIR="$REPO_ROOT/verification/isa"
COMMON="$REPO_ROOT/hdl/common"
WORK="$HERE/work"
TB="$HERE/vesta_isa_tb.vhd"

GHDL="${GHDL:-ghdl}"
RISCV_PREFIX="${RISCV_PREFIX:-riscv-none-elf-}"
TIMEOUT_S="${TIMEOUT_S:-90}"

# ---------------------------------------------------------------------------
# Curated analysis order. THIS LIST MUST STAY IN SYNC with
# sky130/synth.sh and sky130/sim/Makefile (there are three conflicting
# `regfile` entities in the tree — only regfile_sbirq.vhd is correct — and
# ClkGate must come from hdl/common/sim/, not a synthesis stub).
# ---------------------------------------------------------------------------
SOURCES=(
    "$COMMON/constants.vhd"
    "$COMMON/MemoryMap.vhd"
    "$COMMON/vesta/extend.vhd"
    "$COMMON/vesta/loadext.vhd"
    "$COMMON/vesta/store_ext.vhd"
    "$COMMON/vesta/branch_valid.vhd"
    "$COMMON/vesta/pulse_extender.vhd"
    "$COMMON/vesta/aludec.vhd"
    "$COMMON/vesta/maindec.vhd"
    "$COMMON/vesta/div.vhd"
    "$COMMON/vesta/alu.vhd"
    "$COMMON/vesta/regfile_sbirq.vhd"
    "$COMMON/vesta/c_dec.vhd"
    "$COMMON/vesta/csr_unit.vhd"
    "$COMMON/vesta/irq_handler.vhd"
    # X4 Zfinx single-precision FPU (behind datapath's gen_fpu:if ENABLE_ZFINX).
    # These MUST be analyzed whenever the TB sets ENABLE_ZFINX=true — otherwise
    # the fpu/fpu_simple component instances are UNBOUND, fpu_done floats, and
    # every FP op hangs the multicycle FSM (that omission, not any RTL bug, is
    # what made an earlier bring-up wrongly conclude "the FPU never completes").
    "$COMMON/vesta/fpu_simple.vhd"
    "$COMMON/vesta/fpu.vhd"
    "$COMMON/vesta/controller.vhd"
    "$COMMON/vesta/datapath.vhd"
    "$COMMON/sim/ClkGate.vhd"
    "$COMMON/vesta/vesta.vhd"
    "$TB"
)

# The 9 real regression suites for this core: base (ui/um/ua/uc), the Zb*
# bit-manip quartet (uzba/uzbb/uzbc/uzbs), and rv32uzf — the Zfinx single-
# precision FP suite (converted rv32uf + directed FP vectors, built with
# -march=rv32imc_zfinx; runs against the FPU that the TB now enables). The
# others in verification/isa (rv32uf/ud/si/mi/ziscr, the dedicated X-series
# crypto suites, periph, boot, spifem) are inherited scaffolding or need the
# full MCU (peripherals / boot ROM) or an alternate encoding path — out of
# scope for this bare-core a0-sentinel harness (the enabled extensions are
# already exercised by the rv32ua ext-probes + rv32uzf).
DEFAULT_SUITES=(rv32ui rv32um rv32ua rv32uc rv32uzba rv32uzbb rv32uzbc rv32uzbs rv32uzf)

# ---------------------------------------------------------------------------
# X-series extension enablement.
#
# The vesta core (this tree) implements a stack of RISC-V Z-extensions behind
# ENABLE_* generics that all DEFAULT TO FALSE (a minimal chip prunes them). The
# ISA testbench (vesta_isa_tb.vhd) turns ON every extension that is functionally
# verifiable on a single bare core, so this run checks the WHOLE implemented
# decode/sequencer — NOT a stripped subset.
#
# The rv32ua ext-probe tests dispatch their ON (real-encoding, result-checking)
# arm on a build-time `-DCORE_ENABLE_<EXT>` (the X1 convention — Z-extensions
# have no misa bit, so #ifdef is the only on/off signal; see
# tests/rv32ua/extprobe_template.S). CORE_ENABLE_DEFS below MUST match, one for
# one, the TRUE generics in vesta_isa_tb.vhd's generic map — that keeps probe
# polarity == RTL. Deliberately ABSENT — ONLY two, both genuine single-bare-core
# limits confirmed under this harness (NOT missing-source artifacts): ZAWRS
# (wrs.nto/sto BLOCK until another master clears the reservation — with one hart
# they never retire) and ZIHPM (the extzihpm perf-counter probe asserts a counter
# advances; on the bare core it does not, so the honest polarity is OFF). Zfinx
# IS enabled here (the FPU works once fpu.vhd/fpu_simple.vhd are analyzed — see
# the SOURCES note; extzfinx's ON arm and the whole rv32uzf suite pass).
CORE_ENABLE_DEFS=(
    -DCORE_ENABLE_COMPRESSED
    -DCORE_ENABLE_ZICOND -DCORE_ENABLE_ZCB -DCORE_ENABLE_ZIMOP -DCORE_ENABLE_ZIHINT
    -DCORE_ENABLE_ZICBOZ -DCORE_ENABLE_ZABHA -DCORE_ENABLE_ZACAS
    -DCORE_ENABLE_ZCMP  -DCORE_ENABLE_ZCMT
    -DCORE_ENABLE_ZBKB  -DCORE_ENABLE_ZBKC -DCORE_ENABLE_ZBKX -DCORE_ENABLE_ZKN
    -DCORE_ENABLE_ZFINX
)
# The isa Makefile's default RISCV_GCC_OPTS, which we must reproduce verbatim
# and extend (overriding RISCV_GCC_OPTS REPLACES it) so the CORE_ENABLE defines
# reach the compiler for every suite (harmless for the non-rv32ua suites, whose
# sources contain no CORE_ENABLE_* #ifdef).
BASE_GCC_OPTS="-static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles"

# ---------------------------------------------------------------------------
# SKIP list: <suite>/<plain-test-name>  =>  reason
#
# TWO families of justified skips (every entry verified on THIS harness:
# observed to FAIL/TIMEOUT, never PASS — and the reason confirmed in the .S):
#
# (1) MCU / MULTI-CORE SYSTEM-INTEGRATION tests that live inside the rv32ui/
#     rv32ua trees but are NOT bare-core ISA tests: they drive peripheral MMIO
#     (0x4xxx slots, the 0x6000 HW-mutex bank, the 0x7xxx IRQ/CLINT window,
#     0x5010 CLINT mtime) and/or launch harts 1..NHARTS-1 through the mp_boot
#     ROM. This harness is ONE hart on a single flat RAM at 0x8000 with no
#     peripherals, so each self-checks FAIL (device reads zero -> a0=DEADBEEF)
#     or spins on a hart/IRQ that never comes (-> sim-timeout). NON-entries:
#     shmem/shmem_mp are KEPT (they degrade cleanly to the hart-0 path and PASS).
#
# (2) X-series NEGATIVE-CONTROL "poison" probes. The X1-X4 ext-probe idiom
#     (tests/rv32ua/extprobe_template.S) proves the OFF/illegal polarity of an
#     extension by executing an encoding that MUST take the illegal-instruction
#     trap; the repo verifies these under an EXTERNAL trap-watching harness
#     (behavioral_mp_stripped/run_extoff.sh + trap_watch.tcl watching trap_flag).
#     This bare TB is an a0-SENTINEL harness with NO software trap recovery
#     (vesta TRAP_STATE is terminal: pc frozen, trap_flag latched — mtvec is
#     never programmed by env/p, so a trap dead-ends and spins). Such a probe can
#     therefore NEVER report a0=CAFEBABE here: it either traps->spins (timeout)
#     or, if the encoding is legal on THIS (fully-enabled) build, executes past
#     the trap into RVTEST_FAIL. The probes' own headers say "Wired into
#     POISON_RCFS, not the a0-watch suite". The POSITIVE (ON, result-checking)
#     arm of every dispatchable extension IS run and PASSES — see CORE_ENABLE_DEFS
#     above and the extz* / extjvt tests that are NOT skipped.
#
# The plain key is the test name with the "rvXX-p-" prefix and x-padding
# stripped (see the `plain=` extraction in the run loop).
# ---------------------------------------------------------------------------
declare -A SKIP=(
    # rv32ui — peripheral MMIO / IRQ-routing / multi-hart system tests
    [rv32ui/shperiph]="shared SPI1(0x4300)+UART1(0x4500) via HW mutex bank(0x6000) — MCU peripherals, not bare-core"
    [rv32ui/shuart]="shared UART1 peripheral (0x4500) — MCU peripheral absent on bare core"
    [rv32ui/shi2c]="shared I2C peripheral MMIO — MCU peripheral absent on bare core"
    [rv32ui/shtimer]="shared timer peripheral MMIO — MCU peripheral absent on bare core"
    [rv32ui/shclint]="CLINT / timer-IRQ window (0x4000/0x71c0) — MCU CLINT absent on bare core"
    [rv32ui/shirq]="inter-hart IRQ + routing table (0x7xxx) — needs MCU IRQ controller + >1 hart"
    [rv32ui/irqctx]="IRQ context save/restore driven by the 0x7xxx routing window — MCU IRQ controller absent"
    [rv32ui/shmutex]="HW mutex bank (0x6000) 1-insn acquire — MCU mutex block absent on bare core"
    [rv32ui/shboot]="launches harts 1..N via the mp_boot ROM — needs the boot ROM and >1 hart"
    [rv32ui/shexec]="multi-hart execution/GO-gate coordination — needs >1 hart"
    [rv32ui/shwfi]="WFI parked on inter-hart wakeup — needs another hart/IRQ to wake it"
    [rv32ui/shfault]="fault-injection/trap handshake over MMIO — MCU fault facilities absent"
    [rv32ui/shpwr]="power-gate / sleep-control peripheral — MCU power controller absent"
    [rv32ui/shnpu]="NPU accelerator peripheral + staging RAM (0xC000) — MCU NPU absent"
    [rv32ui/shafe]="AFE analog-front-end peripheral — MCU analog block absent"
    [rv32ui/afsel]="AFE peripheral select + IRQ routing (0x7000) — MCU peripheral absent"
    [rv32ui/afselv2]="AFE peripheral slot (0x4100) + IRQ routing (0x7000/0x7201) — MCU peripheral absent"
    # rv32ua — cross-hart atomic/coordination signature tests (all need >1 hart)
    [rv32ua/shamo]="cross-hart AMO grant-locking (M8) via the mp_arbiter — needs >1 hart"
    [rv32ua/shlrsc]="cross-hart LR/SC (M4b) via the global resv_unit — needs >1 hart"
    [rv32ua/shlock]="advisory-lock signature (M7c) HW mutex — needs >1 hart"
    [rv32ua/shspin]="multi-core spinlock signature (M5a) — needs >1 hart"
    [rv32ua/shcount]="multi-hart shared-counter coordination — needs >1 hart"
    [rv32ua/shpause]="Zihintpause arbiter-yield timed via CLINT mtime(0x5010) + mp_boot harts 1..3 — needs the MCU CLINT and >1 hart"
    # These sh* tests DISPATCH on an ON extension we now enable; the ON arm is a
    # genuine cross-hart / CLINT-IRQ scenario (in the default OFF build the ext
    # encoding trapped and the test degraded to a trivial single-hart pass — that
    # masking is gone once the generic is TRUE). Verified to hang/FAIL here.
    [rv32ua/shzabha]="Zabha ON -> real MP_LAUNCH_ALL byte/halfword-AMO coordination; hart 0 spins on tiles that never boot — needs >1 hart"
    [rv32ua/shmixw]="Zabha ON -> mixed-width shared-word AMO race across MP_LAUNCH_ALL tiles — needs >1 hart"
    [rv32ua/shzacas]="Zacas ON -> real MP_LAUNCH_ALL amocas coordination across tiles — needs >1 hart"
    [rv32ua/shcaslr]="Zacas ON -> cross-hart CAS-vs-LR/SC reservation interplay (hart0 reserver, hart1 CAS-doer) via the global resv_unit — needs >1 hart"
    [rv32ua/shcmppush]="Zcmp ON -> proves push/pop uninterruptibility using a CLINT mtimecmp/mtip timer IRQ + IVT slot 84 — needs the MCU CLINT + IRQ delivery"
    # rv32ua — X-series NEGATIVE-CONTROL poisons (always-illegal or OFF-polarity
    # encodings that MUST trap; trap-watch tests, NOT a0-sentinel tests — see (2))
    [rv32ua/extbadcsr]="poison: unknown CSR 0x5C0 read MUST trap illegal on EVERY build — terminal trap, no a0 sentinel"
    [rv32ua/casill]="poison: amocas.d is illegal on RV32 even with Zacas ON (D5) — terminal trap, no a0 sentinel"
    [rv32ua/cbozill]="poison: cbo.clean/flush/inval are illegal on EVERY build even with Zicboz ON (D4) — terminal trap"
    [rv32ua/extzbkrsv]="poison: reserved BINVI-form (f3=001,imm=0x698) — a Zbs encoding, so on THIS Zbs-ON core it executes past the trap into RVTEST_FAIL; it is a BITMANIP-OFF neg-control (trap-watch only)"
    [rv32ua/extzawrsx]="poison: wrs.nto (SYSTEM f12=0x00D) illegal-when-Zawrs-off neg-control — Zawrs is OFF here (wrs blocks on a bare core), so it traps -> spin"
    # rv32ua — Zfinx negative-control poisons: each UNCONDITIONALLY executes an FP
    # encoding then RVTEST_FAIL, to prove (under the trap-watch harness) that a
    # Zfinx-OFF build takes the illegal-instruction trap. They are NOT a0-sentinel
    # tests: on THIS Zfinx-ON core the legal FP forms simply EXECUTE and fall into
    # the poison's own RVTEST_FAIL (a0=DEADBEEF), and the fmv.w.x/fmv.x.w forms —
    # which do not exist in Zfinx — stay illegal and trap -> spin. Either way,
    # never a CAFEBABE. Positive Zfinx coverage is the extzfinx ON-arm probe (run
    # above) + the full rv32uzf functional suite (in DEFAULT_SUITES) — both pass.
    [rv32ua/zffcsr]="Zfinx neg-control (csrr fcsr 0x003): Zfinx-ON -> reads fcsr then RVTEST_FAIL; a Zfinx-OFF-trap probe, trap-watch only"
    [rv32ua/zffflags]="Zfinx neg-control (csrr fflags 0x001): Zfinx-ON -> executes then RVTEST_FAIL; trap-watch only"
    [rv32ua/zfflw]="Zfinx neg-control (flw, LOAD-FP 0x07): Zfinx-ON -> executes then RVTEST_FAIL; trap-watch only"
    [rv32ua/zffma]="Zfinx neg-control (fmadd.s, FMADD 0x43): Zfinx-ON -> executes then RVTEST_FAIL; trap-watch only"
    [rv32ua/zffms]="Zfinx neg-control (fmsub.s, FMSUB 0x47): Zfinx-ON -> executes then RVTEST_FAIL; trap-watch only"
    [rv32ua/zffrm]="Zfinx neg-control (frm/fcsr rounding-mode CSR): Zfinx-ON -> executes then RVTEST_FAIL; trap-watch only"
    [rv32ua/zffsw]="Zfinx neg-control (fsw, STORE-FP 0x27): Zfinx-ON -> executes then RVTEST_FAIL; trap-watch only"
    [rv32ua/zfmvwx]="Zfinx neg-control (fmv.w.x — absent from Zfinx, always illegal): traps -> spin; trap-watch only"
    [rv32ua/zfmvxw]="Zfinx neg-control (fmv.x.w — absent from Zfinx, always illegal): traps -> spin; trap-watch only"
    [rv32ua/zfnma]="Zfinx neg-control (fnmadd.s, FNMADD 0x4f): Zfinx-ON -> executes then RVTEST_FAIL; trap-watch only"
    [rv32ua/zfnms]="Zfinx neg-control (fnmsub.s, FNMSUB 0x4b): Zfinx-ON -> executes then RVTEST_FAIL; trap-watch only"
    [rv32ua/zfopfp]="Zfinx neg-control (fadd.s, OP-FP 0x53): Zfinx-ON -> executes then RVTEST_FAIL; trap-watch only"
)

GHDL_FLAGS=(--std=08 -fsynopsys --workdir="$WORK")

# ---------------------------------------------------------------------------
# Tool checks
# ---------------------------------------------------------------------------
need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERROR: '$1' not found on PATH." >&2
        echo "       $2" >&2
        exit 127
    }
}
need "$GHDL"                "Install GHDL (>=5.0) — e.g. 'apt-get install ghdl'."
need "${RISCV_PREFIX}gcc"   "Install the RISC-V toolchain and/or source ../setup_env.sh (sets RISCV_PREFIX and PATH)."
need "${RISCV_PREFIX}objcopy" "Install the RISC-V toolchain and/or source ../setup_env.sh."
need make                   "Install make."
need timeout                "Install coreutils (provides 'timeout')."

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
if [ "$#" -gt 0 ]; then
    SUITES=("$@")
else
    SUITES=("${DEFAULT_SUITES[@]}")
fi

echo "=== vesta ISA regression ==="
echo "    suites : ${SUITES[*]}"
echo "    ghdl   : $($GHDL --version | head -1)"
echo "    prefix : $RISCV_PREFIX"
echo

# ---------------------------------------------------------------------------
# 1. Build the test images
# ---------------------------------------------------------------------------
echo "--- building ISA images (make -C verification/isa ${SUITES[*]}) ---"
# Clean the build dirs for the suites we are about to (re)build. The rv32ua
# ext-probes are built with the CORE_ENABLE_DEFS (ON polarity); make keys the
# .elf on the .S alone, so a build/ left over from an earlier OFF-polarity run
# would be silently reused with the wrong arm compiled in (the build-order trap
# documented in extprobe_template.S). A clean rebuild makes the polarity
# deterministic.
for s in "${SUITES[@]}"; do rm -rf "$ISA_DIR/build/$s"; done
make -C "$ISA_DIR" RISCV_PREFIX="$RISCV_PREFIX" \
     RISCV_GCC_OPTS="$BASE_GCC_OPTS ${CORE_ENABLE_DEFS[*]}" "${SUITES[@]}"
echo

# ---------------------------------------------------------------------------
# 2. Analyze RTL + TB into work/
# ---------------------------------------------------------------------------
mkdir -p "$WORK"
echo "--- analyzing ${#SOURCES[@]} VHDL files into work/ ---"
for f in "${SOURCES[@]}"; do
    [ -f "$f" ] || { echo "ERROR: missing source $f" >&2; exit 1; }
    "$GHDL" -a "${GHDL_FLAGS[@]}" "$f"
done
# NOTE: no standalone `ghdl -e` — the RAM image is a signal initializer that
# calls the textio loader at elaboration, so elaboration needs a real
# -gTEST_FILE. GHDL's mcode backend elaborates+runs in a single `ghdl -r`
# below, which is where each image is loaded; a bad/missing file therefore
# surfaces as a clear assertion on that test's run.
echo "    analyze OK"
echo

# ---------------------------------------------------------------------------
# 3. Run every built .rcf
# ---------------------------------------------------------------------------
npass=0; ntotal=0; nskip=0
declare -a FAILURES=()

# entry sanity: rcf word 0 must map to 0x8000, _start at 0x8200 (word 128).
sanity_checked=0

for suite in "${SUITES[@]}"; do
    build="$ISA_DIR/build/$suite"
    [ -d "$build" ] || { echo "WARN: no build dir for $suite (no tests built?)"; continue; }
    shopt -s nullglob
    rcfs=("$build"/*.rcf)
    shopt -u nullglob
    if [ "${#rcfs[@]}" -eq 0 ]; then
        echo "WARN: no .rcf files in $build"
        continue
    fi

    for rcf in "${rcfs[@]}"; do
        base="$(basename "$rcf" .rcf)"
        # Strip the leading x-padding and the "rvXX-p-" prefix that the isa
        # Makefile bakes into the filename, leaving the plain test name that the
        # SKIP table is keyed on (e.g. "xxrv32ua-p-shlock" -> "shlock").
        plain="${base##*-p-}"
        key="$suite/$plain"

        if [ -n "${SKIP[$key]:-}" ]; then
            echo "SKIP  $key  (${SKIP[$key]})"
            nskip=$((nskip+1))
            continue
        fi

        # One-time sanity check on the first image: entry word (0x8200) offset
        # 128 from base 0x8000 must be non-zero (the _start jump lives there).
        if [ "$sanity_checked" -eq 0 ]; then
            w128="$(sed -n '129p' "$rcf" 2>/dev/null || true)"
            if [ -z "$w128" ] || ! grep -q '1' <<<"$w128"; then
                echo "WARN: sanity check — word 128 (addr 0x8200 / _start) of $key is empty/all-zero;"
                echo "      the rcf->address mapping may be off (expected _start code there)."
            fi
            sanity_checked=1
        fi

        ntotal=$((ntotal+1))
        log="$WORK/${suite}__${base}.log"
        set +e
        timeout "$TIMEOUT_S" "$GHDL" -r "${GHDL_FLAGS[@]}" vesta_isa_tb \
            -gTEST_FILE="$rcf" >"$log" 2>&1
        rc=$?
        set -e

        if [ "$rc" -eq 0 ]; then
            echo "PASS  $key"
            npass=$((npass+1))
        elif [ "$rc" -eq 124 ]; then
            echo "TIMEOUT $key  (wall-clock ${TIMEOUT_S}s; see ${log#$REPO_ROOT/})"
            FAILURES+=("$key (wall-timeout)")
        else
            reason="FAIL"
            if grep -q "TEST TIMED OUT" "$log"; then reason="sim-timeout"; fi
            echo "FAIL  $key  ($reason; see ${log#$REPO_ROOT/})"
            FAILURES+=("$key ($reason)")
        fi
    done
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "ISA RESULTS: $npass/$ntotal passed (skipped: $nskip)"
if [ "${#FAILURES[@]}" -gt 0 ]; then
    echo "Failures:"
    for f in "${FAILURES[@]}"; do echo "  - $f"; done
fi

[ "$npass" -eq "$ntotal" ] && [ "$ntotal" -gt 0 ]
