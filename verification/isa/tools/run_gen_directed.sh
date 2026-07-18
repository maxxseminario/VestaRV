#!/bin/bash
# run_gen_directed.sh -- (re)generate the rv32uzf directed FP vectors using the
# glibc/ctypes single-precision reference oracle. Deterministic: re-running
# overwrites the committed .S files byte-for-byte. See gen_directed.py for the
# C4 reference discipline (glibc fmaf/sqrtf via ctypes + libm fenv; x87 not
# used; no host C compiler required).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
python3 "$HERE/gen_directed.py" "$@"
echo "run_gen_directed: directed vectors regenerated"
