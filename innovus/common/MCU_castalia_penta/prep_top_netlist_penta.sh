#!/bin/bash
# =============================================================================
# prep_top_netlist_penta.sh -- netlist hygiene for the CASTALIA-PENTA chip cut.
#
# CLONE of ../MCU_WOUND/prep_top_netlist_wound.sh + the step-2 half of
# ../MCU_castalia/prep_top_netlist_MCU_castalia.sh, with ONE structural change
# that is the whole point of CP1 D6:
#
#   THE STRIP MUST DELETE THE FOUR HARDENED TILES' SUBTREE AND KEEP THE
#   ORCHESTRATOR'S.
#
# CPR6 (2026-08-15): the assertions were re-written for the CPR3 RENUMBERED
# shape -- orch_tile is `hart0`, the hardened tiles are `hart1`..`hart4`. The
# strip itself is index-blind (it works off module NAMES) and was not touched.
#
# Both subtrees come from the SAME RTL, so before the D6 rename they had the
# same module names and this script could not have told them apart -- it would
# have deleted the orchestrator out of the chip, silently, and the first
# symptom would have been a gate sim or an LVS mismatch. genus/orch_tile/
# rename_orch_modules.sh prefixes every module below `orch_tile` with `orch_`
# and asserts the two module sets are disjoint; this script re-asserts the
# consequence on the actual netlists it is about to cut.
#
# Step 1 (pre-innovus):  strip every module DEFINED IN the tile netlist from
#                        the genus penta netlist
#                        -> in/MCU_PENTA_hier.pnr.v   (init_verilog)
# Step 2 (post-innovus): same strip on the emitted sim netlist, if present
#                        -> out/MCU_castalia_penta.xsim.clean.v
#
# Usage: ./prep_top_netlist_penta.sh   (run before make MCU_castalia_penta.innovus;
#                                       run again after it to refresh .clean.v)
# NOTE: pure awk (this machine's python3 is the quote-stripping aoj_cal
# wrapper -- never use python3 -c here).
# =============================================================================
set -e
cd "$(dirname "$0")"

SRC=../../../genus/MCU_PENTA/out/MCU_PENTA_hier.genus.v
TILE=../../../genus/hart_tile/out/hart_tile.genus.v
ORCH=../../../genus/orch_tile/out/orch_tile.renamed.v
DST=in/MCU_PENTA_hier.pnr.v

[ -f "$SRC" ]  || { echo "ERROR: $SRC not found -- run 'make MCU_PENTA_hier.genus' in ../../../genus first"; exit 1; }
[ -f "$TILE" ] || { echo "ERROR: $TILE not found (the FROZEN tile netlist -- never re-run genus/hart_tile)"; exit 1; }
[ -f "$ORCH" ] || { echo "ERROR: $ORCH not found -- run 'make orch_tile.genus' then genus/orch_tile/rename_orch_modules.sh"; exit 1; }

TILE_MODS=$(mktemp); ORCH_MODS=$(mktemp); ISECT=$(mktemp)
trap 'rm -f "$TILE_MODS" "$ORCH_MODS" "$ISECT"' EXIT

grep -oE "^module [A-Za-z0-9_]+" "$TILE" | awk '{print $2}' | sort -u > "$TILE_MODS"
grep -oE "^module [A-Za-z0-9_]+" "$ORCH" | awk '{print $2}' | sort -u > "$ORCH_MODS"
comm -12 "$TILE_MODS" "$ORCH_MODS" > "$ISECT"

echo "tile subtree      : $(wc -l < "$TILE_MODS") module names (to be stripped)"
echo "orch subtree      : $(wc -l < "$ORCH_MODS") module names (to be KEPT)"

# ---- PRE-ASSERTION P0: the D6 invariant, checked here too ------------------
# Belt and braces with rename_orch_modules.sh's A1: this script is the consumer
# that the invariant protects, so it re-proves it rather than trusting a file
# that may have been regenerated since.
if [ -s "$ISECT" ]; then
	echo "FATAL P0: the tile and orchestrator module sets INTERSECT ($(wc -l < "$ISECT") names):"
	head -20 "$ISECT"
	echo "          Stripping the tile subtree would delete the orchestrator. Re-run"
	echo "          genus/orch_tile/rename_orch_modules.sh (D6) before this script."
	exit 1
fi
echo "D6 disjointness   : 0 shared module names  [P0 PASS]"

strip_mods() {  # $1=in  $2=out
	awk -v modf="$TILE_MODS" '
		BEGIN { while ((getline l < modf) > 0) drop[l]=1 }
		/^module /       { m=$2; sub(/\(.*/,"",m); if (m in drop) skip=1 }
		skip             { if (/^endmodule/) skip=0; next }
		{ print }
	' "$1" > "$2"
}

strip_mods "$SRC" "$DST"

# CPR5 TOMBSTONE (2026-08-14): the CP4b "STEP 1b -- strip the three D-series debug pins off the four hardened tile instantiations" block (98 lines) was DELETED here -- the re-hardened penta tile HAS dbg_haltreq/dbg_resethaltreq/dbg_halted on its LEF, so the strip's D3/D5 assertions would FATAL against it (see cpr_architecture.md R5).

# ---- POST-ASSERTIONS -------------------------------------------------------
# CPR6 RENUMBER (2026-08-15): the CPR3 generator emits hart0 = orch_tile and
# hart1..hart4 = hart_tile -- the exact INVERSE of the CP-era shape these
# assertions used to encode (`hart_tile hart[0-3]` / `orch_tile hart4`). The
# inverted forms are below. This matters beyond bookkeeping: with the old
# patterns A1 counted 3 (hart1..hart3 matched `hart[0-3]`) and A2 counted 0,
# so the script would have FATALed -- but a laxer pattern would have passed a
# chip whose orchestrator sat in a hardened corner.
fail=0
n_tile_inst=$(grep -cE "^ +hart_tile +hart[1-4]\(" "$DST" || true)
n_orch_inst=$(grep -cE "^ +orch_tile +hart0\(" "$DST" || true)
n_tile_def=$(grep -cE "^module (hart_tile|adddec|vesta)\(" "$DST" || true)
n_orch_def=$(grep -c "^module orch_" "$DST" || true)
n_orch_top=$(grep -c "^module orch_tile(" "$DST" || true)
n_orch_want=$(grep -c "" "$ORCH_MODS")

# A1 -- exactly four hart_tile instantiations survive (the hardened corners),
#       and after CPR6 they are hart1..hart4.
if [ "$n_tile_inst" != "4" ]; then
	echo "FATAL A1: $n_tile_inst 'hart_tile hart1..4' instantiations in $DST (want 4)"; fail=1
fi
# A2 -- exactly one orchestrator-top instantiation survives, and it is hart0.
if [ "$n_orch_inst" != "1" ]; then
	echo "FATAL A2: $n_orch_inst 'orch_tile hart0' instantiations in $DST (want 1)"; fail=1
fi
# A2b -- NOTHING is instantiated at the CP-era positions. Belt and braces on
#        the renumber: this is the assertion that fails LOUD if a CP-era
#        MCU.vhd is ever restaged under the CPR6 scripts.
n_stale_shape=$(grep -cE "^ +(hart_tile +hart0|orch_tile +hart[1-4])\(" "$DST" || true)
if [ "$n_stale_shape" != "0" ]; then
	echo "FATAL A2b: $n_stale_shape CP-era-shaped instantiation(s) (hart_tile hart0 / orch_tile hart1..4)"
	echo "           in $DST -- the staged MCU.vhd predates the CPR3 renumber."; fail=1
fi
# A3 -- zero tile module DEFINITIONS survive (Innovus binds the tile LEF/ETM;
#       a duplicate definition also wins the xcelium last-compile race with
#       mangled ports -- the M14 adddec p1/p2 CUVPOM failure).
if [ "$n_tile_def" != "0" ]; then
	echo "FATAL A3: $n_tile_def tile module definitions remain in $DST (want 0)"; fail=1
fi
# A4 -- the WHOLE orchestrator subtree survives, definition for definition.
#       This is the assertion that would have caught the pre-D6 disaster.
if [ "$n_orch_def" != "$n_orch_want" ]; then
	echo "FATAL A4: $n_orch_def 'orch_*' module definitions in $DST, want $n_orch_want"
	echo "          (the orchestrator subtree was partially stripped or never emitted)"; fail=1
fi
# A5 -- and its top specifically.
if [ "$n_orch_top" != "1" ]; then
	echo "FATAL A5: $n_orch_top 'module orch_tile(' definitions in $DST (want 1)"; fail=1
fi
# A6 -- the orchestrator's TCM survived as a macro instance (soft logic, hard
#       macro: Innovus places mcu0/hart0/tile/ram0 in the centre band).
#       MACRO-SIZE-AGNOSTIC since 2026-08-17: this used to demand
#       `sram1p16k_hvt_pg ram0` by name, which turned the 8 KiB TCM swap into a
#       FATAL claiming "the orchestrator TCM is gone" when it was present and
#       merely a different macro. What the check is FOR is that ram0 survived
#       the tile-subtree strip as a hard macro instance, not which part number
#       it is -- so match the family and report what was found.
n_orch_sram=$(grep -cE "^ +sram1p(8|16)k_hvt_pg +ram0" "$DST" || true)
if [ "$n_orch_sram" -lt 1 ]; then
	echo "FATAL A6: no sram1p{8,16}k_hvt_pg ram0 instance in $DST -- the orchestrator TCM is gone"; fail=1
fi

if [ $fail -ne 0 ]; then rm -f "$DST"; echo "PREP FAILED -- $DST deleted."; exit 1; fi

echo "wrote $DST"
echo "  modules kept    : $(grep -c '^module ' "$DST")"
echo "  hart_tile insts : $n_tile_inst  (hart1..hart4)   [A1 PASS]"
echo "  orch_tile insts : $n_orch_inst  (hart0)          [A2 PASS]"
echo "  CP-era shapes   : $n_stale_shape   [A2b PASS]"
echo "  tile module defs: $n_tile_def   [A3 PASS]"
echo "  orch module defs: $n_orch_def / $n_orch_want   [A4 PASS]"
echo "  orch TCM insts  : $n_orch_sram (incl. the orchestrator's)   [A6 PASS]"

# ---- Step 2: the emitted sim netlist, once the chip run has produced one ----
# CP5: the step-2 pair is overridable so the closure-ECO cut
# (out/MCU_castalia_penta.cp5.xsim.v -> .cp5.xsim.clean.v) can be stripped with
# the SAME module list and the SAME A7 assertion, without touching the CP4b
# products. Defaults are unchanged.
#
# CPR6 SAME-CUT GUARD. Step 2 must only ever strip a sim netlist produced by
# the SAME P&R cut as the $DST step 1 just wrote. Run under the CPR6 scripts
# against a CP-era out/*.xsim.v, the module lists disagree by construction and
# A7 FATALs -- after deleting a perfectly good CP-era product on its way out.
# So: if the sim netlist predates the GENUS netlist the P&R was built from, it
# belongs to a previous cut; say so and stop, rather than "checking" it.
#
# The comparison is against $SRC (the genus product), NOT against $DST: step 1
# rewrites $DST every time this script runs, so a $DST comparison marks a
# perfectly current sim netlist stale the moment you re-run the prep — measured,
# first try.
XSIM=${XSIM_IN:-out/MCU_castalia_penta.cpr6.xsim.v}
CLEAN=${CLEAN_OUT:-out/MCU_castalia_penta.cpr6.xsim.clean.v}
if [ -f "$XSIM" ] && [ "$XSIM" -ot "$SRC" ]; then
	echo "NOTE: $XSIM is OLDER than $SRC -- it is a PREVIOUS cut's sim netlist."
	echo "      Step 2 SKIPPED (one-cut collateral rule). Re-run this script after"
	echo "      'make MCU_castalia_penta.innovus' has written the new $XSIM."
	exit 0
fi
if [ -f "$XSIM" ]; then
	strip_mods "$XSIM" "$CLEAN"
	echo "penta chip sim netlist: $(grep -c '^module' "$CLEAN") modules kept," \
	     "$(grep -cE '^ +hart_tile hart' "$CLEAN" || true) tile refs," \
	     "$(grep -c '^module orch_' "$CLEAN" || true) orch module defs -> $CLEAN"
	if [ "$(grep -c '^module orch_' "$CLEAN" || true)" != "$n_orch_want" ]; then
		echo "FATAL A7: the sim netlist lost orchestrator modules ($(grep -c '^module orch_' "$CLEAN") != $n_orch_want)"
		rm -f "$CLEAN"; exit 1
	fi
else
	echo "NOTE: $XSIM not present yet -- run 'make MCU_castalia_penta.innovus' first,"
	echo "      then re-run this script to produce $CLEAN."
fi
