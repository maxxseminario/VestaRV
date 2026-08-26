#!/bin/bash
# =============================================================================
# prep_top_netlist_wound.sh -- netlist hygiene for the WOUND block P&R cut.
#
# Cloned from prep_top_netlist_dp.sh (Stage F2a). Identical mechanism, wound
# file names. The chip-top tail is the wound analogue of the DP script's
# C0/G2/CQ5 blocks: it strips the tile subtree out of out/chip_top_wound.xsim.v
# when the CONNECTED chip run has produced one.
#
# The top genus run (MCU_WOUND_hier) reads the TILE GATE NETLIST as source (the
# only shape genus 19.15 accepts for a direct-entity-instantiated block), so
# out/MCU_WOUND_hier.genus.v contains hart_tile AND its whole submodule tree
# (adddec, vesta, alu, ClkGate_*, ...) duplicated from the tile-only run.
# Innovus must see NONE of them (tile = LEF macro + ETM lib), and the gate sim
# must resolve every tile module from hart_tile.xsim.v alone -- a duplicate
# definition in the top file wins the xcelium last-compile race with MANGLED
# ports (proven: adddec 'p1/p2' CUVPOM elab failure, M14).
#
# Step 1 (pre-innovus):  strip hart_tile + every module defined in the tile
#                        netlist from the genus hier netlist
#                        -> in/MCU_WOUND_hier.pnr.v  (init_verilog)
# Step 2 (post-innovus): same strip on the emitted sim netlist, if present
#                        -> out/MCU_WOUND.xsim.clean.v (gate-sim cell list)
#
# Usage: ./prep_top_netlist_wound.sh  (run before make MCU_WOUND.innovus; run
#                                      again after it to refresh the .clean.v)
# NOTE: pure awk (this machine's python3 is the quote-stripping aoj_cal
# wrapper -- never use python3 -c here).
# =============================================================================
set -e
cd "$(dirname "$0")"
SRC=../../../genus/MCU_WOUND/out/MCU_WOUND_hier.genus.v
TILE=../../../genus/hart_tile/out/hart_tile.genus.v
DST=in/MCU_WOUND_hier.pnr.v

[ -f "$SRC" ]  || { echo "ERROR: $SRC not found -- the HIERARCHICAL wound synthesis does not exist yet. genus/out/MCU_WOUND.genus.v is the FLAT run (no hart_tile). Create genus/tcl/MCU_WOUND_hier.genus.tcl from MCU_DP_hier.genus.tcl and run 'make MCU_WOUND_hier.genus' in ../../../genus first."; exit 1; }
[ -f "$TILE" ] || { echo "ERROR: $TILE not found (run 'make hart_tile.genus' in ../../../genus first)"; exit 1; }

# Tile-subtree module names (incl. hart_tile itself).
TILE_MODS=$(mktemp)
grep -oE "^module [A-Za-z0-9_]+" "$TILE" | awk '{print $2}' | sort -u > "$TILE_MODS"
echo "tile subtree: $(wc -l < "$TILE_MODS") module names"

strip_mods() {  # $1=in  $2=out
	awk -v modf="$TILE_MODS" '
		BEGIN { while ((getline l < modf) > 0) drop[l]=1 }
		/^module /       { m=$2; sub(/\(.*/,"",m); if (m in drop) skip=1 }
		skip             { if (/^endmodule/) skip=0; next }
		{ print }
	' "$1" > "$2"
}

strip_mods "$SRC" "$DST"
echo "stub check: $(grep -cE "^module (hart_tile|adddec|vesta)" "$DST" || true) tile module defs remain (want 0)"
echo "instance check: $(grep -c "hart_tile hart" "$DST" || true) hart_tile instantiations (want 4)"
echo "wrote $DST"

XSIM=out/MCU_WOUND.xsim.v
if [ -f "$XSIM" ]; then
	strip_mods "$XSIM" out/MCU_WOUND.xsim.clean.v
	echo "sim netlist: $(grep -c "^module" out/MCU_WOUND.xsim.clean.v) modules kept, $(grep -cE "hart_tile hart[0-3]" out/MCU_WOUND.xsim.clean.v) tile refs -> out/MCU_WOUND.xsim.clean.v"
fi

# Same strip for the CONNECTED wound chip netlist (chip_top_wound + pads +
# mcu0) -- the G2 chip_top_dp block, retargeted. Only fires once
# `make chip_top_wound.innovus` has emitted the sim netlist.
WXSIM=out/chip_top_wound.xsim.v
if [ -f "$WXSIM" ]; then
	strip_mods "$WXSIM" out/chip_top_wound.xsim.clean.v
	echo "wound chip sim netlist: $(grep -c "^module" out/chip_top_wound.xsim.clean.v) modules kept, $(grep -cE "hart_tile hart" out/chip_top_wound.xsim.clean.v) tile refs -> out/chip_top_wound.xsim.clean.v"
fi
rm -f "$TILE_MODS"
