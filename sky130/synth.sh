#!/usr/bin/env bash
# VestaRV: VHDL to Verilog conversion for the sky130 and LibreLane flow.
# Run `./synth.sh` from this directory; it needs GHDL 5.x or newer on PATH, or a
# container that has one. The output src/vesta.v is a build artifact, never
# committed. This script owns the analysis order and the top entity, and the file
# list is hand curated: the tree holds three entities named `regfile` and only
# regfile_sbirq.vhd matches what datapath.vhd instantiates, while ClkGate comes
# from hdl/common/sim/ and is swapped below for a real sky130 integrated clock
# gate, because the behavioural latch-and-AND form simulates fine but generic CTS
# mis-times the gated clock branch by half a period on hold checks. --latches is
# required: the ClkGate body and a latched result net in div.vhd are intentional.
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
# GHDL 5 emits "module clkgate"; GHDL 6 uniquifies every module as
# <entity>_B<architecture>. The match accepts both, plus a one-line "(...);"
# header, and the replacement keeps whichever name was emitted, because the
# parent instantiates the module by exactly that name. Port names are lowercase
# under both writers, the same lowering the module name gets.
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

# The suffixing also hits the top entity, and LibreLane's DESIGN_NAME must be
# plain ${TOP}. Nothing in the file references the top module, so renaming its
# header is safe, and it is a no-op under a GHDL that emits the plain name.
sed -i -E "s/^module ${TOP}_B[A-Za-z0-9_]*/module ${TOP}/" "src/${TOP}.v"

grep -q "sky130_fd_sc_hd__dlclkp_1" "src/${TOP}.v" || {
    echo "error: ICG substitution did not land in src/${TOP}.v" >&2
    # Diagnostic: every module header, and every line naming the clock gate under
    # any casing, so the failure says what the writer actually emitted.
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
