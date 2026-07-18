#!/bin/bash
# =========================================================================
# X4 Zfinx negative-control repro (all three seeds)            Stage 3 (final)
# =========================================================================
# FINALIZED at integration: the three seed patches now apply cleanly to the
# merged 2a/2b RTL (fpu.vhd / csr_unit.vhd / vesta.vhd). Each seed injects the
# spec-frozen bug and is caught by its detecting rv32uzf test as a BOUNDED
# compare-and-branch FAIL (a0=0xDEADBEEF), never a watchdog hang.
#
#   SEED (patch)                     TARGET          DETECTING TEST   MECHANISM
#   x4_rmignored_seed.patch   hdl/common/vesta/fpu.vhd       dround   rm_lat -> RNE: RUP/RMM/RDN tie mismatch
#   x4_stickyflag_seed.patch  hdl/common/vesta/csr_unit.vhd  daccum   OR -> assign: fflags 0x1f -> last-op only
#   x4_rdx0flags_seed.patch   hdl/common/vesta/vesta.vhd     drdx0    fp_flags_we gated on rd/=x0: NX/NV lost
#
# PRECONDITION: the ON hardware must be staged (ENABLE_ZFINX=true) and the ON
# rv32uzf images built, because the detecting tests are ON-only:
#   sed -i 's/\(CORE_ENABLE_ZFINX[[:space:]]*: boolean := \)false/\1true/' hdl/common/MemoryMap.vhd
#   cd verification/isa && rm -rf build/ && \
#     make rv32uzf-flash RISCV_GCC_OPTS="-static -mcmodel=medany -fvisibility=hidden \
#        -nostdlib -nostartfiles -DNHARTS=4 -DCORE_ENABLE_ZFINX"
#
# USAGE (from anywhere), one command per seed:
#   verification/isa/negctrl/x4_seeds_repro.sh rmignored   # seeded FAIL then reverted PASS on dround
#   verification/isa/negctrl/x4_seeds_repro.sh stickyflag  # daccum
#   verification/isa/negctrl/x4_seeds_repro.sh rdx0flags   # drdx0
#   verification/isa/negctrl/x4_seeds_repro.sh all         # all three, in order
#
# Each run: clean PASS (precondition) -> apply seed -> seeded FAIL -> revert ->
# reverted PASS.  NEVER leaves a seed applied (reverts even on error).
# =========================================================================
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
RUN="$ROOT/xcelium/riscv_test/behavioral_mp"

declare -A TEST=( [rmignored]=dround [stickyflag]=daccum [rdx0flags]=drdx0 )

run_one() {
    local seed="$1" test="${TEST[$1]}" patch="$ROOT/verification/isa/negctrl/x4_${1}_seed.patch"
    echo "========== SEED $seed  (detecting test: $test) =========="
    ( cd "$RUN" && ./xrun_batch.sh "$test" >/tmp/x4_${seed}_clean.log 2>&1 )
    echo -n "  clean    : "; grep -oE "TEST (PASSED|FAILED)" /tmp/x4_${seed}_clean.log | head -1
    git -C "$ROOT" apply "$patch" || { echo "  apply FAILED"; return 1; }
    ( cd "$RUN" && ./xrun_batch.sh "$test" >/tmp/x4_${seed}_seeded.log 2>&1 )
    echo -n "  seeded   : "; grep -oE "TEST (PASSED|FAILED)" /tmp/x4_${seed}_seeded.log | head -1
    git -C "$ROOT" apply -R "$patch" || echo "  WARNING: revert FAILED — check $patch"
    ( cd "$RUN" && ./xrun_batch.sh "$test" >/tmp/x4_${seed}_revert.log 2>&1 )
    echo -n "  reverted : "; grep -oE "TEST (PASSED|FAILED)" /tmp/x4_${seed}_revert.log | head -1
    echo "  EXPECT: clean PASSED / seeded FAILED / reverted PASSED"
}

case "${1:-all}" in
    rmignored|stickyflag|rdx0flags) run_one "$1" ;;
    all) for s in rmignored stickyflag rdx0flags; do run_one "$s"; done ;;
    *) echo "usage: $0 {rmignored|stickyflag|rdx0flags|all}"; exit 2 ;;
esac
