#!/usr/bin/env bash
# VHDL -> Verilog conversion for the sky130/LibreLane flow.
# Run from this directory: ./synth.sh   (needs GHDL >= 5.x on PATH, or run it
# inside any container that has one). Output: src/vesta.v — a generated build
# artifact, never committed.
#
# This script owns the analysis order and the top entity. The file list is
# hand-curated on purpose:
#   - the tree has THREE entities named `regfile`; only regfile_sbirq.vhd
#     matches what datapath.vhd instantiates (sp_in/sp_out/sp_write).
#   - ClkGate comes from hdl/common/sim/ (behavioral latch+AND). For hardening
#     it is swapped below for a real sky130 integrated-clock-gate cell: the
#     latch+AND form simulates fine but generic CTS mis-times the gated clock
#     branch by half a period for hold checks (measured -38 ns WNS).
# --latches: the ClkGate body and a latched result net in div.vhd are
# intentional; GHDL refuses inferred latches without the flag.
set -euo pipefail
cd "$(dirname "$0")"

TOP=vesta
COMMON=../hdl/common
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

FILES=(
    "${COMMON}/constants.vhd"
    "${COMMON}/MemoryMap.vhd"
    "${COMMON}/vesta/extend.vhd"
    "${COMMON}/vesta/loadext.vhd"
    "${COMMON}/vesta/store_ext.vhd"
    "${COMMON}/vesta/branch_valid.vhd"
    "${COMMON}/vesta/pulse_extender.vhd"
    "${COMMON}/vesta/aludec.vhd"
    "${COMMON}/vesta/maindec.vhd"
    "${COMMON}/vesta/div.vhd"
    "${COMMON}/vesta/alu.vhd"
    "${COMMON}/vesta/regfile_sbirq.vhd"
    "${COMMON}/vesta/c_dec.vhd"
    "${COMMON}/vesta/csr_unit.vhd"
    "${COMMON}/vesta/irq_handler.vhd"
    "${COMMON}/vesta/controller.vhd"
    "${COMMON}/vesta/datapath.vhd"
    "${COMMON}/sim/ClkGate.vhd"
    "${COMMON}/vesta/vesta.vhd"
)

for f in "${FILES[@]}"; do
    echo "== ghdl analyze: ${f} =="
    ghdl -a --std=08 -fsynopsys --workdir="${WORKDIR}" "${f}"
done

mkdir -p src

echo "== ghdl synth: ${TOP} -> src/${TOP}.v =="
ghdl --synth --std=08 -fsynopsys --latches --workdir="${WORKDIR}" \
     --out=verilog "${TOP}" > "src/${TOP}.v"

echo "== swap behavioral clkgate for the sky130 ICG cell =="
# GHDL 5 emitted "module clkgate"; GHDL 6 uniquifies every module as
# <entity>_B<architecture> ("module clkgate_Bbehavioral"). The match accepts
# both plus a one-line "(...);" header, and the replacement KEEPS the emitted
# name — the parent instantiates the module by exactly that name. Port names
# are lowercase under both writers (same lowering as the module name itself).
awk '
/^module \\?clkgate(_[A-Za-z0-9_]*)?([[:space:](;].*)?$/ { inswap=1
  name=$2
  sub(/[(;].*/, "", name)
  print "module " name
  print "  (input  clkin,"
  print "   input  en,"
  print "   output clkout);"
  print "  sky130_fd_sc_hd__dlclkp_1 icg (.CLK(clkin), .GATE(en), .GCLK(clkout));"
  print "endmodule"
  next }
inswap && /^endmodule([[:space:]].*)?$/ { inswap=0; next }
!inswap { print }
' "src/${TOP}.v" > "src/${TOP}.icg.v" && mv "src/${TOP}.icg.v" "src/${TOP}.v"

# The suffixing also hits the top entity, but LibreLane's DESIGN_NAME must be
# plain ${TOP}. Nothing inside the file references the top module, so renaming
# its header is safe. No-op under a GHDL that already emits the plain name.
sed -i -E "s/^module ${TOP}_B[A-Za-z0-9_]*/module ${TOP}/" "src/${TOP}.v"

grep -q "sky130_fd_sc_hd__dlclkp_1" "src/${TOP}.v" || {
    echo "error: ICG substitution did not land in src/${TOP}.v" >&2
    # Diagnostic for the annotation channel: what DID the writer emit? Every
    # module header, and every line naming the clock gate under any casing.
    grep -n "^module" "src/${TOP}.v" | head -6 >&2
    grep -in "clkgate" "src/${TOP}.v" | head -3 >&2
    exit 1
}
grep -qE "^module ${TOP}([[:space:](;].*)?$" "src/${TOP}.v" || {
    echo "error: src/${TOP}.v does not contain 'module ${TOP}' (exact name)" >&2
    grep -n "^module" "src/${TOP}.v" | tail -4 >&2
    exit 1
}

echo "== done: src/${TOP}.v ($(wc -l < "src/${TOP}.v") lines) =="
