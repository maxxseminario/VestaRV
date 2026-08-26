#!/bin/bash
# =============================================================================
# prep_top_netlist_hart.sh -- netlist hygiene for the MCU_hart block assembly.
#
# Simplified clone of ../MCU_castalia_penta/prep_top_netlist_penta.sh.  There is
# NO orchestrator in this vehicle, so there is no second subtree to protect and
# no D6 disjointness question: the whole hart_tile module set is stripped and
# nothing is kept.
#
# WHY THE STRIP EXISTS AT ALL: the genus hier flow reads the hardened tile's
# GATE NETLIST as source (it has to -- MCU.vhd instantiates the tile by direct
# entity instantiation, which genus cannot blackbox from a port map alone), so
# the emitted top netlist CONTAINS the tile's module definitions.  Innovus would
# then bind hart_tile to a module rather than to the LEF macro, and a duplicate
# definition also wins the xcelium last-compile race with mangled ports.
#
# Step 1 (pre-innovus):  strip every module DEFINED IN the tile netlist from the
#                        genus MCU_hart netlist
#                        -> in/MCU_hart_hier.pnr.v   (init_verilog)
# Step 2 (post-innovus): the same strip on the emitted sim netlist, if present
#                        -> out/MCU_hart.xsim.clean.v
#
# Usage: ./prep_top_netlist_hart.sh
#   run before `make MCU_hart.innovus`, and again after it to refresh .clean.v
#
# NOTE: pure awk.  This machine's python3 is the quote-stripping aoj_cal
# wrapper, so never use `python3 -c` here.
# =============================================================================
set -e
cd "$(dirname "$0")"

SRC=../../../genus/MCU_hart/out/MCU_hart_hier.genus.v
TILE=../../../genus/hart_tile/out/hart_tile.genus.v
DST=in/MCU_hart_hier.pnr.v

[ -f "$SRC" ]  || { echo "ERROR: $SRC not found -- run 'make MCU_hart_hier.genus' in ../../../genus first"; exit 1; }
[ -f "$TILE" ] || { echo "ERROR: $TILE not found (the FROZEN tile netlist -- never re-run genus/hart_tile)"; exit 1; }

mkdir -p in out

TILE_MODS=$(mktemp)
trap 'rm -f "$TILE_MODS"' EXIT
grep -oE "^module [A-Za-z0-9_]+" "$TILE" | awk '{print $2}' | sort -u > "$TILE_MODS"
echo "tile subtree      : $(wc -l < "$TILE_MODS") module names (to be stripped)"

strip_mods() {  # $1=in  $2=out
	awk -v modf="$TILE_MODS" '
		BEGIN { while ((getline l < modf) > 0) drop[l]=1 }
		/^module /       { m=$2; sub(/\(.*/,"",m); if (m in drop) skip=1 }
		skip             { if (/^endmodule/) skip=0; next }
		{ print }
	' "$1" > "$2"
}

strip_mods "$SRC" "$DST"

# ---- POST-ASSERTIONS --------------------------------------------------------
fail=0
n_tile_inst=$(grep -cE "^ +hart_tile +hart0\(" "$DST" || true)
n_tile_def=$(grep -cE "^module (hart_tile|adddec|vesta)\(" "$DST" || true)
n_any_tile_inst=$(grep -cE "^ +hart_tile +[A-Za-z0-9_]+\(" "$DST" || true)

# A1 -- exactly ONE hart_tile instantiation survives, and it is hart0.
if [ "$n_tile_inst" != "1" ]; then
	echo "FATAL A1: $n_tile_inst 'hart_tile hart0' instantiations in $DST (want exactly 1)"; fail=1
fi
# A1b -- and there is no SECOND hart under another name.  MCU_hart is a
#        single-hart vehicle by definition; a 2-hart config staged by mistake
#        would otherwise sail through and cost a P&R run to discover.
if [ "$n_any_tile_inst" != "1" ]; then
	echo "FATAL A1b: $n_any_tile_inst hart_tile instantiations total in $DST (want exactly 1)"
	grep -nE "^ +hart_tile +[A-Za-z0-9_]+\(" "$DST" | head -10
	fail=1
fi
# A3 -- zero tile module DEFINITIONS survive (Innovus must bind the LEF/ETM).
if [ "$n_tile_def" != "0" ]; then
	echo "FATAL A3: $n_tile_def tile module definitions remain in $DST (want 0)"; fail=1
fi
# A4 -- exactly one boot ROM macro instance, and it is named rom0.  Which
#       ENTITY it is decides which CDL the LVS include must carry, so report it
#       rather than assume it: a missing .include_cdl is the NVN-13010 abort
#       that killed the 2026-08-16 TCM swap.
n_rom2k=$(grep -cE "^ +rom2k_hvt_pg +rom0" "$DST" || true)
n_rom16k=$(grep -cE "^ +rom_hvt_pg +rom0" "$DST" || true)
if [ "$(( n_rom2k + n_rom16k ))" != "1" ]; then
	echo "FATAL A4: $n_rom2k rom2k_hvt_pg + $n_rom16k rom_hvt_pg 'rom0' instances in $DST (want exactly 1)"; fail=1
fi

if [ $fail -ne 0 ]; then rm -f "$DST"; echo "PREP FAILED -- $DST deleted."; exit 1; fi

echo "wrote $DST"
echo "  modules kept    : $(grep -c '^module ' "$DST")"
echo "  hart_tile insts : $n_tile_inst (hart0)   [A1/A1b PASS]"
echo "  tile module defs: $n_tile_def            [A3 PASS]"
if [ "$n_rom2k" = "1" ]; then
	echo "  boot ROM        : rom2k_hvt_pg rom0    [A4 PASS]"
	echo "  -> the LVS include MUST carry rom2k_hvt_pg.cdl"
else
	echo "  boot ROM        : rom_hvt_pg rom0      [A4 PASS]"
	echo "  -> the LVS include MUST carry rom_hvt_pg.cdl"
fi
echo "  macro census    :"
grep -oE "^ +(rom2k_hvt_pg|rom_hvt_pg|sram1p16k_hvt_pg|sram1p8k_hvt_pg|hart_tile|GlitchFilter|PowerOnResetCheng|OscillatorCurrentStarved) +[A-Za-z0-9_]+" "$DST" \
	| awk '{print $1}' | sort | uniq -c | sed 's/^/      /'
echo "  EVERY cell listed above needs a .include_cdl line in signoff_mp/lvs_include_hart."

# ---- Step 2: the emitted sim netlist, once the P&R run has produced one -----
# SAME-CUT GUARD: only ever strip a sim netlist produced by the same cut as the
# $DST step 1 just wrote.  The comparison is against $SRC (the genus product),
# NOT against $DST: step 1 rewrites $DST every run, so a $DST comparison marks
# a perfectly current sim netlist stale the moment you re-run the prep.
XSIM=${XSIM_IN:-out/MCU_hart.xsim.v}
CLEAN=${CLEAN_OUT:-out/MCU_hart.xsim.clean.v}
if [ -f "$XSIM" ] && [ "$XSIM" -ot "$SRC" ]; then
	echo "NOTE: $XSIM is OLDER than $SRC -- it is a PREVIOUS cut's sim netlist."
	echo "      Step 2 SKIPPED (one-cut collateral rule)."
	exit 0
fi
if [ -f "$XSIM" ]; then
	strip_mods "$XSIM" "$CLEAN"
	echo "sim netlist: $(grep -c '^module' "$CLEAN") modules kept," \
	     "$(grep -cE '^ +hart_tile hart' "$CLEAN" || true) tile refs -> $CLEAN"
else
	echo "NOTE: $XSIM not present yet -- run 'make MCU_hart.innovus' first,"
	echo "      then re-run this script to produce $CLEAN."
fi
