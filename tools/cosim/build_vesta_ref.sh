#!/bin/bash
# ---------------------------------------------------------------------------
# build_vesta_ref.sh -- reproducible build of the VestaRV lockstep reference
# model (tools/cosim/vesta_ref.cc) against the pinned Spike libriscv.
# ---------------------------------------------------------------------------
#
# THE PROVEN COMPILE LINE, verbatim:
#
#   ~/local/mamba/envs/spike13/bin/x86_64-conda-linux-gnu-g++ \
#     -std=c++20 -O2 -I$HOME/local/include \
#     -o <out>/vesta_ref vesta_ref.cc -L$HOME/local/lib -lriscv
#
# Load-bearing facts, each one cost a debugging cycle:
#
#   * COMPILER.  There is NO plain `g++` on this host.  Use the conda-forge
#     gcc 13 in ~/local/mamba/envs/spike13 -- the same toolchain libriscv.so
#     itself was built with.  Override with $VESTA_REF_CXX if you must.
#
#   * -std=c++20 IS REQUIRED FOR A CLEAN BUILD.  At -std=c++17 the result still
#     compiles, links and runs correctly, but riscv/mmu.h emits 5 warnings:
#       riscv/mmu.h:69:30: warning: default member initializers for bit-fields
#       only available with '-std=c++20' or '-std=gnu++20' [-Wc++20-extensions]
#     from mmu.h lines 69-73 (forced_virt / hlvx / lr / ss_access /
#     clean_inval).  c++20 is silent.
#
#   * -lriscv ALONE SUFFICES.  Do NOT add -lsoftfloat, -ldisasm or -lfesvr.
#     libriscv.so carries RPATH=[.../spike13/lib:$HOME/local/lib], and its only
#     softfloat references are two *weak* TLS-init symbols
#     (_ZTH22softfloat_roundingMode, _ZTH24softfloat_exceptionFlags), which is
#     why an rv32imac_zb* build needs nothing else.  This script verifies the
#     property with `ldd -r` (0 undefined symbols) instead of trusting it.
#     Keeping this to one library is also what lets vesta_ref.cc use its own
#     minimal ELF loader rather than fesvr's load_elf()/memif_t.
#
#   * RUNTIME needs `source ~/local/spike_env.sh` (LD_LIBRARY_PATH for the
#     conda libstdc++.so.6 that libriscv is linked against).  This script
#     sources it before the smoke test; CALLERS MUST SOURCE IT TOO.
#
#   * THE BINARY MUST NEVER BE COMMITTED.  Default output is the gitignored
#     xcelium/riscv_test/behavioral_mp/cosim_work/ (.gitignore:312 `xcelium/`).
#     Pass an alternate output dir as $1, e.g. ~/local/bin.
#
#   * NEVER PATCH SPIKE.  `git status --porcelain` in ~/local/src/spike-src must
#     stay empty -- the whole D1 argument is that this reference model needs
#     zero modifications to upstream.  This script asserts it.
#
# Usage:  ./build_vesta_ref.sh [outdir]
# ---------------------------------------------------------------------------
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/vesta_ref.cc"

OUTDIR="${1:-$HOME/vestarv/xcelium/riscv_test/behavioral_mp/cosim_work}"
OUT="$OUTDIR/vesta_ref"

CXX="${VESTA_REF_CXX:-$HOME/local/mamba/envs/spike13/bin/x86_64-conda-linux-gnu-g++}"
SPIKE_PREFIX="${SPIKE_ENV_PREFIX:-$HOME/local}"
SPIKE_SRC="$HOME/local/src/spike-src"
SPIKE_PIN="3d8eb089bd289c59dcb506f197a172e02beb7b5b"

CXXFLAGS="-std=c++20 -O2"
INCS="-I$SPIKE_PREFIX/include"
LIBS="-L$SPIKE_PREFIX/lib -lriscv"

die() { echo "build_vesta_ref: ERROR: $*" >&2; exit 1; }

[ -f "$SRC" ]  || die "missing source $SRC"
[ -x "$CXX" ]  || die "compiler not found: $CXX (set VESTA_REF_CXX)"
[ -f "$SPIKE_PREFIX/include/riscv/simif.h" ] || die "no riscv headers under $SPIKE_PREFIX/include"
[ -f "$SPIKE_PREFIX/lib/libriscv.so" ]       || die "no libriscv.so under $SPIKE_PREFIX/lib"

# --- assert the pinned Spike is untouched (D1) -----------------------------
if [ -d "$SPIKE_SRC/.git" ]; then
    got="$(cd "$SPIKE_SRC" && git rev-parse HEAD 2>/dev/null)"
    [ "$got" = "$SPIKE_PIN" ] || die "spike-src HEAD is $got, expected pin $SPIKE_PIN"
    dirty="$(cd "$SPIKE_SRC" && git status --porcelain 2>/dev/null | head -20)"
    if [ -n "$dirty" ]; then
        echo "build_vesta_ref: ERROR: ~/local/src/spike-src is MODIFIED." >&2
        echo "  The reference model must need zero Spike patches (D1). Offending:" >&2
        echo "$dirty" >&2
        exit 1
    fi
    echo "build_vesta_ref: spike-src clean at pin ${SPIKE_PIN:0:8}"
fi

mkdir -p "$OUTDIR" || die "cannot create $OUTDIR"

# --- refuse to write a binary into the tracked tree ------------------------
if command -v git >/dev/null 2>&1 && git -C "$OUTDIR" rev-parse --show-toplevel >/dev/null 2>&1; then
    if ! git -C "$OUTDIR" check-ignore -q "$OUT" 2>/dev/null; then
        die "$OUT is NOT gitignored -- the binary must never enter the repo.
       Use the default cosim_work/ output, or \$1 = \$HOME/local/bin."
    fi
    echo "build_vesta_ref: output path is gitignored, good"
fi

echo "build_vesta_ref: $CXX $CXXFLAGS $INCS -o $OUT $SRC $LIBS"
# shellcheck disable=SC2086
"$CXX" $CXXFLAGS $INCS -o "$OUT" "$SRC" $LIBS || die "compile/link failed"

# --- verify the "-lriscv alone" property -----------------------------------
# shellcheck disable=SC1090
[ -f "$HOME/local/spike_env.sh" ] && . "$HOME/local/spike_env.sh"

undef="$(ldd -r "$OUT" 2>&1 | grep -c 'undefined symbol' || true)"
[ "$undef" = "0" ] || die "$undef undefined symbols after link (ldd -r)"
echo "build_vesta_ref: ldd -r: 0 undefined symbols"

# --- smoke test: RAM at 0x0 executes + MMIO injection works ---------------
if ! "$OUT" selftest >/dev/null 2>"$OUTDIR/.vesta_ref_selftest.err"; then
    echo "build_vesta_ref: ERROR: selftest FAILED:" >&2
    cat "$OUTDIR/.vesta_ref_selftest.err" >&2
    exit 1
fi
grep -h 'selftest' "$OUTDIR/.vesta_ref_selftest.err" >&2 || true
rm -f "$OUTDIR/.vesta_ref_selftest.err"

echo "build_vesta_ref: OK -> $OUT"
echo "build_vesta_ref: remember to \`source ~/local/spike_env.sh\` before running it"
