#!/bin/bash
# =============================================================================
# prep_top_netlist_wound_quad.sh -- POST-run netlist hygiene for the
# chip_top_wound_quad CONNECTED chip cut.
#
# SCOPE, deliberately narrow. The chip_top_wound_quad flow is a FLAT chip run
# whose P&R INPUT is `in/MCU_WOUND_hier.pnr.v`, and that file is produced by
# the EXISTING ./prep_top_netlist_wound.sh (step 1, pre-innovus) and consumed
# here UNCHANGED -- the quad re-cut changes the floorplan, not the netlist. So
# this script does NOT duplicate step 1; running it is not a substitute for
# running prep_top_netlist_wound.sh first, and it says so if the file is
# missing.
#
# What IS flow-specific is step 2: stripping the hart_tile subtree out of the
# emitted SIM netlist, which is named after the flow
# (out/chip_top_wound_quad.xsim.v). Innovus must see none of the tile modules
# (tile = LEF macro + ETM lib) and the gate sim must resolve every tile module
# from hart_tile.xsim.v ALONE -- a duplicate definition in the top file wins
# the xcelium last-compile race with MANGLED ports (proven: adddec 'p1/p2'
# CUVPOM elab failure, M14).
#
#   -> out/chip_top_wound_quad.xsim.clean.v   (pads-in-DUT gate-sim cell list)
#
# Usage: ./prep_top_netlist_wound_quad.sh
#        (run AFTER `make chip_top_wound_quad.innovus`)
# NOTE: pure awk (this machine's python3 is the quote-stripping aoj_cal
# wrapper -- never use python3 -c here).
# =============================================================================
set -e
cd "$(dirname "$0")"

TILE=../../../genus/hart_tile/out/hart_tile.genus.v
PNR=in/MCU_WOUND_hier.pnr.v
WXSIM=out/chip_top_wound_quad.xsim.v
WCLEAN=out/chip_top_wound_quad.xsim.clean.v

[ -f "$TILE" ] || { echo "ERROR: $TILE not found (run 'make hart_tile.genus' in ../../../genus first)"; exit 1; }

if [ ! -f "$PNR" ]; then
	echo "ERROR: $PNR not found -- the chip_top_wound_quad flow consumes it as its"
	echo "       MCU netlist and does NOT build it. Run ./prep_top_netlist_wound.sh first"
	echo "       (it strips the tile subtree out of genus/out/MCU_WOUND_hier.genus.v)."
	exit 1
fi
echo "P&R input present: $PNR  ($(grep -c 'hart_tile hart' "$PNR") hart_tile instantiations, want 4;" \
     "$(grep -cE '^module (hart_tile|adddec|vesta)' "$PNR") tile module defs, want 0)"

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

if [ -f "$WXSIM" ]; then
	strip_mods "$WXSIM" "$WCLEAN"
	echo "wound-quad chip sim netlist: $(grep -c '^module' "$WCLEAN") modules kept," \
	     "$(grep -cE 'hart_tile hart' "$WCLEAN") tile refs -> $WCLEAN"
else
	echo "NOTE: $WXSIM not present yet -- run 'make chip_top_wound_quad.innovus' first,"
	echo "      then re-run this script to produce $WCLEAN."
fi
rm -f "$TILE_MODS"
