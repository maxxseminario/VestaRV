#!/bin/bash
# VestaRV: build fpu_vec_gen.c with the native x86 reference toolchain and emit
# the reference vector file fpu_tb.vhd reads.
# Usage: ./gen_fpu_vectors.sh <out_vector_file>
# The C4 reference discipline is SSE single precision plus glibc fmaf; x87 is
# forbidden, which is what -msse2 -mfpmath=sse enforces below.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-fpu_vectors.txt}"

# The native x86_64 gcc bundled with Xcelium. -B/usr/bin forces the system
# linker: the bundled ld cannot read the newer glibc archive.
GCC="${FPU_GCC:-/opt/cadence/XCELIUM2009/tools.lnx86/cdsgcc/gcc/6.3/install/bin/gcc}"
BIN="$(mktemp -d)/fpu_vec_gen"

"$GCC" -O2 -std=c99 -msse2 -mfpmath=sse -frounding-math -B/usr/bin \
    "$HERE/fpu_vec_gen.c" -lm -o "$BIN"

"$BIN" "$OUT"
echo "gen_fpu_vectors.sh: reference = x86 SSE single precision + glibc fmaf"
