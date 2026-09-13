#!/bin/bash
# VestaRV: reproducible build of the lockstep reference model
# (tools/cosim/vesta_ref.cc) against the pinned Spike libriscv.
# Usage: ./build_vesta_ref.sh [outdir]
#
# Four constraints hold the build line where it is.
#   Compiler: this host has no plain g++. The conda-forge gcc 13 in
#     ~/local/mamba/envs/spike13 is the toolchain libriscv.so itself was built
#     with; $VESTA_REF_CXX overrides it.
#   -std=c++20: at c++17 the result still compiles, links and runs, but
#     riscv/mmu.h emits five -Wc++20-extensions warnings for its bit-field
#     member initialisers.
#   -lriscv alone: no -lsoftfloat, -ldisasm or -lfesvr. libriscv.so carries an
#     RPATH covering both library directories and its only softfloat references
#     are two weak TLS-init symbols, so an rv32imac_zb* build needs nothing more.
#     `ldd -r` below verifies that rather than assuming it. Staying at one
#     library is what lets vesta_ref.cc use its own minimal ELF loader instead of
#     fesvr's load_elf()/memif_t.
#   Spike stays unpatched: the reference model's whole claim is that it needs no
#     upstream modification, so a dirty ~/local/src/spike-src is an error here.
#
# Running the binary needs `source ~/local/spike_env.sh` for the conda
# libstdc++.so.6 libriscv links against; this script sources it before the smoke
# test and callers must source it too. The binary is never committed: the default
# output directory is gitignored and an alternate $1 is checked against
# git check-ignore.
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

# Assert the pinned Spike is untouched.
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

# Refuse to write a binary into the tracked tree.
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

# Verify the "-lriscv alone" property.
# shellcheck disable=SC1090
[ -f "$HOME/local/spike_env.sh" ] && . "$HOME/local/spike_env.sh"

undef="$(ldd -r "$OUT" 2>&1 | grep -c 'undefined symbol' || true)"
[ "$undef" = "0" ] || die "$undef undefined symbols after link (ldd -r)"
echo "build_vesta_ref: ldd -r: 0 undefined symbols"

# Smoke test: RAM at 0x0 executes and MMIO injection works.
if ! "$OUT" selftest >/dev/null 2>"$OUTDIR/.vesta_ref_selftest.err"; then
    echo "build_vesta_ref: ERROR: selftest FAILED:" >&2
    cat "$OUTDIR/.vesta_ref_selftest.err" >&2
    exit 1
fi
grep -h 'selftest' "$OUTDIR/.vesta_ref_selftest.err" >&2 || true
rm -f "$OUTDIR/.vesta_ref_selftest.err"

echo "build_vesta_ref: OK -> $OUT"
echo "build_vesta_ref: remember to \`source ~/local/spike_env.sh\` before running it"
