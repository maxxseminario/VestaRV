#!/bin/bash
# =============================================================================
# prep_top_netlist_argus.sh -- netlist hygiene for the ARGUS A4 assembly flow.
#
# ARGUS variant of prep_top_netlist.sh. The Argus hier genus run
# (MCU_ARGUS_hier) reads the ARGUS tile gate netlist as source, so
# out/MCU_ARGUS_hier.genus.v contains hart_tile AND its whole submodule tree
# (adddec, vesta, alu, ClkGate_*, ...) duplicated from the tile-only run.
# Innovus must see NONE of them (tile = LEF macro + ETM lib), and the gate sim
# must resolve every tile module from hart_tile_argus.xsim.v alone.
#
# Step 1 (pre-innovus):  strip hart_tile + every tile-subtree module from the
#                        hier netlist -> in/MCU_ARGUS_hier.pnr.v (init_verilog)
# Step 2 (post-innovus): same strip on the emitted sim netlist, if present
#                        -> out/MCU_ARGUS.xsim.clean.v (gate-sim cell list)
#
# Usage: ./prep_top_netlist_argus.sh  (run before make MCU_ARGUS.innovus; run
#                                       again after it to refresh the .clean.v)
# NOTE: pure awk (this machine's python3 is the quote-stripping aoj_cal wrapper).
# =============================================================================
set -e
cd "$(dirname "$0")"
SRC=../genus/out/MCU_ARGUS_hier.genus.v
TILE=../genus/out/hart_tile_argus.genus.v
DST=in/MCU_ARGUS_hier.pnr.v

[ -f "$SRC" ]  || { echo "ERROR: $SRC not found (run 'make MCU_ARGUS_hier.genus' in ../genus first)"; exit 1; }
[ -f "$TILE" ] || { echo "ERROR: $TILE not found (run 'make hart_tile_argus.genus' in ../genus first)"; exit 1; }

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
echo "instance check: $(grep -c "hart_tile hart" "$DST" || true) hart_tile instantiations (want 18)"
echo "wrote $DST"

XSIM=out/MCU_ARGUS.xsim.v
if [ -f "$XSIM" ]; then
	strip_mods "$XSIM" out/MCU_ARGUS.xsim.clean.v
	echo "sim netlist: $(grep -c "^module" out/MCU_ARGUS.xsim.clean.v) modules kept, $(grep -cE "hart_tile hart" out/MCU_ARGUS.xsim.clean.v) tile refs -> out/MCU_ARGUS.xsim.clean.v"
fi
rm -f "$TILE_MODS"
