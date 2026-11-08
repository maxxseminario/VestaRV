#!/bin/bash
# Compile the core plus the patched vesta_cpi_tb into its own library under $1. See run_flat.py.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/tools/source_cdspaths.sh" >/dev/null 2>&1
cd "$1" || exit 1
mkdir -p xcelium.d/work
cat > cds.lib <<LIB
SOFTINCLUDE ${XCELIUM_HOME}/tools/xcelium/files/cds.lib
DEFINE work $PWD/xcelium.d/work
LIB
H=($(< cells.txt))
xmvhdl -V200X -WORK work -CONTROLRELAX nlstex -RELAX "${H[@]}" > vhdl.log 2>&1 || { grep -n "\*E\|\*F" vhdl.log | head; exit 1; }
echo FLAT COMPILED
