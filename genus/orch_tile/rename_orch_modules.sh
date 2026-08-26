#!/bin/bash
# =============================================================================
# rename_orch_modules.sh -- CP1 D6 MODULE-NAMESPACE RENAME for the soft
# orchestrator, plus the disjointness ASSERTION that makes the rename provable.
#
# WHY
# ---
# genus/orch_tile and genus/hart_tile synthesize THE SAME RTL from THE SAME
# source files. Genus therefore emits the same module names in both netlists
# (hart_tile, vesta, adddec, alu, ClkGate*, RC_CG_MOD_*, ...). At the MCU level
# those two netlists are read side by side, and the collision is load-bearing in
# two independent places:
#
#   (a) innovus/common/*/prep_top_netlist_*.sh strips the flat P&R netlist of
#       "every module defined in hart_tile.genus.v". With colliding names that
#       list matches the ORCHESTRATOR's subtree too, and the strip deletes the
#       orchestrator out of the chip.
#   (b) A gate simulation would see two different definitions of one module
#       name and resolve the xcelium last-compile race with mangled ports
#       (the M14 adddec p1/p2 CUVPOM failure).
#
# So: every module in the orchestrator netlist EXCEPT the top gets the `orch_`
# prefix. The top stays `orch_tile` -- MCU.vhd binds `entity work.orch_tile` by
# that name and it is already disjoint from the tile's set.
#
# WHAT IT TOUCHES
# ---------------
#   out/orch_tile.genus.v    -> out/orch_tile.renamed.v      (module defs + instantiations)
#   out/orch_tile.genus.sdc  -> out/orch_tile.renamed.sdc    (get_designs / current_design only)
#   out/orch_tile.genus.sdf  -> out/orch_tile.renamed.sdf    (CELLTYPE strings)
#
# SDC NOTE: an SDC names INSTANCES (get_pins/get_nets/get_cells paths), and
# instance paths do not change when a module is renamed -- the only module-scoped
# SDC objects are `current_design` and `[get_designs ...]`. Both are handled.
# Everything else in the file is passed through byte-for-byte, on purpose.
#
# THE ASSERTION (the point of this script)
# ---------------------------------------
# After renaming, the module set of the produced netlist is intersected with the
# module set of ../hart_tile/out/hart_tile.genus.v. The intersection MUST be
# empty. Non-empty => FATAL, exit 1, output deleted. Run it again on every
# re-synthesis of either block: it is the regression guard for D6, not a
# one-time transform.
#
# Usage:  ./rename_orch_modules.sh [PREFIX]        (default PREFIX=orch_)
#         run from anywhere; it cd's to its own directory (genus/orch_tile).
# NOTE: pure awk/sed (this machine's python3 is the quote-stripping aoj_cal
# wrapper -- never use python3 -c here).
# =============================================================================
set -e
cd "$(dirname "$0")"

PREFIX=${1:-orch_}
TOP=orch_tile

SRC_V=out/orch_tile.genus.v
SRC_SDC=out/orch_tile.genus.sdc
SRC_SDF=out/orch_tile.genus.sdf
DST_V=out/orch_tile.renamed.v
DST_SDC=out/orch_tile.renamed.sdc
DST_SDF=out/orch_tile.renamed.sdf
TILE=../hart_tile/out/hart_tile.genus.v

[ -f "$SRC_V" ] || { echo "ERROR: $SRC_V not found -- run 'make orch_tile.genus' in ../ first"; exit 1; }
[ -f "$TILE" ]  || { echo "ERROR: $TILE not found (the frozen tile netlist is the disjointness reference)"; exit 1; }

# --- module lists -----------------------------------------------------------
ORCH_MODS=$(mktemp); TILE_MODS=$(mktemp); RENAME_MAP=$(mktemp)
NEW_MODS=$(mktemp); ISECT=$(mktemp)
trap 'rm -f "$ORCH_MODS" "$TILE_MODS" "$RENAME_MAP" "$NEW_MODS" "$ISECT"' EXIT

grep -oE "^module [A-Za-z0-9_]+" "$SRC_V" | awk '{print $2}' | sort -u > "$ORCH_MODS"
grep -oE "^module [A-Za-z0-9_]+" "$TILE"  | awk '{print $2}' | sort -u > "$TILE_MODS"
echo "orch netlist (raw): $(wc -l < "$ORCH_MODS") modules"
echo "tile netlist      : $(wc -l < "$TILE_MODS") modules"
echo "raw collision     : $(comm -12 "$ORCH_MODS" "$TILE_MODS" | wc -l) shared names (this is WHY the rename exists)"

grep -qx "$TOP" "$ORCH_MODS" || { echo "FATAL: top module '$TOP' is not defined in $SRC_V"; exit 1; }

# rename map: every module except the top
awk -v top="$TOP" -v p="$PREFIX" '$0 != top { print $0, p $0 }' "$ORCH_MODS" > "$RENAME_MAP"
echo "renaming          : $(wc -l < "$RENAME_MAP") modules with prefix '$PREFIX' (top '$TOP' kept)"

# --- the verilog transform --------------------------------------------------
# Genus writes exactly two forms that carry a MODULE name at line scope:
#     ^module <name>(...)              definition
#     ^<ws><name> <instname>(...)      instantiation
# Nothing else in the emitted netlist may be rewritten -- net/pin names are not
# in the module namespace and a loose global s/// would corrupt them.
awk -v mapf="$RENAME_MAP" '
	BEGIN { while ((getline l < mapf) > 0) { split(l, a, " "); ren[a[1]] = a[2] } }
	{
		if (match($0, /^module [A-Za-z0-9_]+/)) {
			m = substr($0, 8, RLENGTH - 7)
			if (m in ren) { $0 = "module " ren[m] substr($0, 8 + length(m)) }
		} else if (match($0, /^[ \t]+[A-Za-z0-9_]+[ \t]/)) {
			# INSTANTIATION. Do NOT try to parse the INSTANCE name: genus emits
			# escaped identifiers for generate-loop instances, e.g.
			#     ClkGate_1_8384 \gen_cg_periph[14].cg_periph (.ClkIn (clk), ...
			# and any character class you write for that will eventually miss a
			# form (the first cut of this script used
			# [A-Za-z0-9_\\\[\]]+ , which has no '.', silently skipped all 16
			# gen_cg_periph instances, and produced a netlist whose ClkGate
			# references elaborated as BLACKBOXES at the MCU level). The only
			# thing that has to be recognised is the FIRST token, and the rename
			# map itself is the authority on whether that token is a module.
			ws = $0; sub(/[^ \t].*/, "", ws)
			rest = substr($0, length(ws) + 1)
			m = rest; sub(/[ \t].*/, "", m)
			if (m in ren) { $0 = ws ren[m] substr(rest, length(m) + 1) }
		}
		print
	}
' "$SRC_V" > "$DST_V"

# --- the SDC transform (module-scoped objects only) -------------------------
if [ -f "$SRC_SDC" ]; then
	cp "$SRC_SDC" "$DST_SDC"
	while read -r old new; do
		sed -i -e "s/\bget_designs $old\b/get_designs $new/g" \
		       -e "s/^current_design $old\$/current_design $new/" "$DST_SDC"
	done < "$RENAME_MAP"
	echo "sdc               : $DST_SDC ($(grep -c '' "$DST_SDC") lines, $(grep -c 'get_designs' "$DST_SDC" || true) get_designs)"
else
	echo "sdc               : $SRC_SDC absent -- skipped"
fi

# --- the SDF transform (CELLTYPE strings name MODULES) ----------------------
if [ -f "$SRC_SDF" ]; then
	awk -v mapf="$RENAME_MAP" '
		BEGIN { while ((getline l < mapf) > 0) { split(l, a, " "); ren[a[1]] = a[2] } }
		/\(CELLTYPE *"/ {
			s = $0; i = index(s, "\""); j = index(substr(s, i + 1), "\"")
			m = substr(s, i + 1, j - 1)
			if (m in ren) { $0 = substr(s, 1, i) ren[m] substr(s, i + j) }
		}
		{ print }
	' "$SRC_SDF" > "$DST_SDF"
	echo "sdf               : $DST_SDF ($(grep -c 'CELLTYPE' "$DST_SDF" || true) CELLTYPE entries)"
else
	echo "sdf               : $SRC_SDF absent -- skipped"
fi

# =============================================================================
# THE ASSERTIONS. Every one of them fails LOUD and deletes the product.
# =============================================================================
fail=0
grep -oE "^module [A-Za-z0-9_]+" "$DST_V" | awk '{print $2}' | sort -u > "$NEW_MODS"
comm -12 "$NEW_MODS" "$TILE_MODS" > "$ISECT"

n_new=$(wc -l < "$NEW_MODS"); n_old=$(wc -l < "$ORCH_MODS"); n_isect=$(wc -l < "$ISECT")

# A1 -- DISJOINTNESS. The invariant of CP1 D6.
if [ "$n_isect" -ne 0 ]; then
	echo "FATAL A1: $n_isect module name(s) shared between $DST_V and $TILE:"
	head -20 "$ISECT"
	fail=1
fi
# A2 -- no module was lost or duplicated by the rename.
if [ "$n_new" -ne "$n_old" ]; then
	echo "FATAL A2: module count changed by the rename ($n_old -> $n_new): a name collided into an existing one"
	fail=1
fi
# A3 -- the top survived under its contract name (MCU.vhd binds it).
if ! grep -qx "$TOP" "$NEW_MODS"; then
	echo "FATAL A3: top module '$TOP' is missing from $DST_V"
	fail=1
fi
# A4 -- every non-top module carries the prefix (catches a form the awk missed).
n_unpref=$(grep -vx "$TOP" "$NEW_MODS" | grep -cv "^$PREFIX" || true)
if [ "$n_unpref" -ne 0 ]; then
	echo "FATAL A4: $n_unpref non-top module(s) did not get the '$PREFIX' prefix:"
	grep -vx "$TOP" "$NEW_MODS" | grep -v "^$PREFIX" | head -20
	fail=1
fi
# A5 -- THE UNRESOLVED-REFERENCE INVARIANT. The strongest check here, and the
#       one that does NOT share a code path with the transform above.
#
#       Define U(f) = the set of names that appear in INSTANCE-TYPE position in
#       f but are not defined as a module in f. In a correct netlist that set is
#       exactly the LIBRARY CELLS (std cells + the sram macro). Renaming module
#       definitions and their instantiations cannot change which references are
#       unresolved, so:
#
#              U(renamed)  MUST EQUAL  U(raw)
#
#       This is what catches a missed instantiation FORM. The first cut of this
#       script parsed the INSTANCE name with a character class that had no '.',
#       so it silently skipped genus's escaped generate-loop instances
#       (`ClkGate_1_8384 \gen_cg_periph[14].cg_periph (...`): the definitions
#       were renamed, those 16 instantiations were not, and the netlist
#       elaborated 16 BLACKBOXES at the MCU level. The old assertion used the
#       same broken regex and passed. This one would have printed all 16.
utab() {  # $1 = netlist -> stdout: sorted unique undefined instance types
	awk '
		/^module [A-Za-z0-9_]+/ { m=$2; sub(/\(.*/,"",m); def[m]=1; next }
		match($0, /^[ \t]+[A-Za-z0-9_]+[ \t]/) { t=$1; use[t]=1 }
		END { for (t in use) if (!(t in def)) print t }
	' "$1" | sort -u
}
U_OLD=$(mktemp); U_NEW=$(mktemp)
utab "$SRC_V" > "$U_OLD"; utab "$DST_V" > "$U_NEW"
if ! diff -q "$U_OLD" "$U_NEW" > /dev/null; then
	echo "FATAL A5: the set of UNRESOLVED module references changed across the rename."
	echo "          Introduced by the rename (a missed instantiation form):"
	comm -13 "$U_OLD" "$U_NEW" | head -20
	echo "          Lost by the rename:"
	comm -23 "$U_OLD" "$U_NEW" | head -20
	fail=1
fi
n_libcell=$(grep -c '' "$U_NEW")
rm -f "$U_OLD" "$U_NEW"
# A6 -- the instance COUNT is conserved (the rename must not eat a line).
#       Same first-token rule as the transform, so it is a conservation check,
#       not an independent one -- A5 is the independent one.
i_old=$(grep -cE "^[ \t]+[A-Za-z0-9_]+[ \t]" "$SRC_V" || true)
i_new=$(grep -cE "^[ \t]+[A-Za-z0-9_]+[ \t]" "$DST_V" || true)
if [ "$i_old" != "$i_new" ]; then
	echo "FATAL A6: instantiation-line count changed ($i_old -> $i_new)"
	fail=1
fi
# A6b -- every module in the rename map is instantiated somewhere OR is the
#        top; and no instantiation names a pre-rename module (the direct form
#        of the old A5, now using the first-token rule the transform uses).
n_stale=$(awk -v mapf="$RENAME_MAP" '
	BEGIN { while ((getline l < mapf) > 0) { split(l, a, " "); ren[a[1]]=1 } }
	match($0, /^[ \t]+[A-Za-z0-9_]+[ \t]/) { if ($1 in ren) c++ }
	END { print c+0 }' "$DST_V")
if [ "$n_stale" != "0" ]; then
	echo "FATAL A6b: $n_stale instantiation line(s) still name a pre-rename module"
	fail=1
fi
# A7 -- line count conserved (nothing dropped or duplicated wholesale).
l_old=$(grep -c '' "$SRC_V"); l_new=$(grep -c '' "$DST_V")
if [ "$l_old" != "$l_new" ]; then
	echo "FATAL A7: line count changed ($l_old -> $l_new)"
	fail=1
fi

if [ $fail -ne 0 ]; then
	rm -f "$DST_V" "$DST_SDC" "$DST_SDF"
	echo "RENAME FAILED -- products deleted."
	exit 1
fi

echo "----------------------------------------------------------------------"
echo "PASS  D6 module-namespace rename"
echo "  netlist         : $DST_V"
echo "  modules         : $n_new (top '$TOP' + $((n_new-1)) '$PREFIX'-prefixed)"
echo "  tile modules    : $(wc -l < "$TILE_MODS")"
echo "  INTERSECTION    : $n_isect   <-- the CP1 D6 invariant (must be 0)"
echo "  lib refs        : $n_libcell undefined instance types, IDENTICAL to the raw netlist  [A5]"
echo "  instantiations  : $i_new (conserved, 0 stale references)"
echo "  lines           : $l_new (conserved)"
echo "----------------------------------------------------------------------"
