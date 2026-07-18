#!/bin/bash
# =============================================================================
# gen_fpu_vectors.sh  (X4 Zfinx, Stage 2a)
# Builds fpu_vec_gen.c with the native x86 SSE reference toolchain and emits the
# reference vector file for fpu_tb.vhd (correction C4: SSE single precision +
# glibc fmaf, x87 forbidden). Usage: ./gen_fpu_vectors.sh <out_vector_file>
# =============================================================================
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-fpu_vectors.txt}"

# native x86_64 gcc bundled with Xcelium; force the system linker (-B/usr/bin)
# because the bundled ld cannot read the newer glibc archive.
GCC="${FPU_GCC:-/opt/cadence/XCELIUM2009/tools.lnx86/cdsgcc/gcc/6.3/install/bin/gcc}"
BIN="$(mktemp -d)/fpu_vec_gen"

"$GCC" -O2 -std=c99 -msse2 -mfpmath=sse -frounding-math -B/usr/bin \
    "$HERE/fpu_vec_gen.c" -lm -o "$BIN"

"$BIN" "$OUT"
echo "gen_fpu_vectors.sh: reference = x86 SSE single precision + glibc fmaf"
