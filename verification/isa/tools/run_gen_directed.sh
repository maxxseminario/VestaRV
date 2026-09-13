#!/bin/bash
# VestaRV: regenerate the rv32uzf directed FP vectors from the glibc/ctypes
# single-precision reference oracle.
# Deterministic: re-running overwrites the committed .S files byte for byte.
# gen_directed.py carries the C4 reference discipline (glibc fmaf/sqrtf via
# ctypes plus libm fenv; x87 unused; no host C compiler required).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
python3 "$HERE/gen_directed.py" "$@"
echo "run_gen_directed: directed vectors regenerated"
