#!/bin/bash
# =============================================================================
# gen_chip_top_wound_quad_sdc.sh -- build in/chip_top_wound_quad.sdc from the WOUND
# hierarchical assembly SDC.
#
# MINIMAL CLONE of gen_chip_top_wound_sdc.sh: the ONLY changes are TOP,
# the default DST and the file names in these comments. The SDC transform is
# floorplan-agnostic -- the quad re-cut moves geometry, not netlist scope -- so
# in/chip_top_wound_quad.sdc must differ from in/chip_top_wound.sdc by exactly
# ONE line (`current_design`). That is checked at staging time by diffing the
# two products; if it ever differs by more, the two chips have drifted apart
# and one of them is stale.
#
# CONTROL RUN (2026-07-27): gen_chip_top_wound_sdc.sh re-run on
# genus/out/MCU_WOUND_hier.genus.sdc reproduces the committed
# in/chip_top_wound.sdc with `diff` rc=0 -- the recipe below is the proven one.
#
# The chip-top run is FLAT: chip_top_wound_quad instantiates the pads and `MCU mcu0`,
# so every MCU-scoped object path in the assembly SDC has to be re-rooted at
# mcu0/, and the assembly's top-level PORTS no longer exist (real pad cells are
# the loads/drivers now).
#
# THE RECIPE IS NOT INVENTED HERE. It was extracted by diffing the G2 golden
# pair -- genus/out/MCU_DP_hier.genus.sdc  vs  in/chip_top_dp.sdc -- and it
# reproduces in/chip_top_dp.sdc EXACTLY (verified 2026-07-26: the transform
# below applied to the DP genus SDC diffs ZERO lines against the committed DP
# chip SDC). Four rules:
#
#   1. DROP every  `set_load ... [get_ports ...]`  and
#      `set_driving_cell ... [get_ports ...]`  line (275 of them in DP): the
#      assembly's port loads/drivers are replaced by the physical pad cells.
#      These are the ONLY get_ports lines either SDC contains.
#   2. current_design MCU  ->  current_design chip_top_wound
#   3. Re-root instance-scoped collections at mcu0/:  get_pins, get_nets and
#      get_cells.  The prefix goes INSIDE a brace-quoted path, i.e.
#      `[get_nets {npu0/Decision[15]}]` -> `[get_nets {mcu0/npu0/Decision[15]}]`
#      (getting this wrong yields `[get_nets mcu0/{...}]`, which matches
#      nothing and silently drops the constraint).
#      get_cells is the WOUND-ONLY member of that list: the wound SDC carries
#      the TRNG ring-oscillator `set_dont_touch [get_cells ...]` block (~211
#      lines) which DP has no counterpart for. It is an INSTANCE path, so it
#      takes the same mcu0/ prefix as get_pins/get_nets.
#   4. NEVER prefix get_clocks / get_designs / get_lib_cells / current_design:
#      those name clocks, module designs and library cells, not instances
#      (`set_dont_touch [get_designs hart_tile]` must stay untouched).
#   5. Append the a0 dangling-bus dont_touch pair (C0/G2 chip precedent).
#
# WOUND WATCH ITEM (reported at staging, not fixed here): the 2026-07-26 FLAT
# wound SDC writes the ring block as `[get_cells u_ro]` / `[get_cells
# {u_ro/...}]`, but the netlist nests the ensemble as trng0/u_ro/... -- so
# those paths already match nothing at MCU level, and prefixing them with mcu0/
# preserves (does not create) that defect. The DB-side dontTouch gate in
# tcl/chip_top_wound_quad.innovus.tcl is what actually preserves the rings. If the
# hierarchical wound SDC emits the same shape, fix it in the genus flow.
#
# Usage: ./gen_chip_top_wound_quad_sdc.sh [SRC_SDC] [DST_SDC]
#   defaults: ../../../genus/MCU_WOUND/out/MCU_WOUND_hier.genus.sdc -> in/chip_top_wound_quad.sdc
# NOTE: pure sed/awk (this machine's python3 is the quote-stripping aoj_cal
# wrapper -- never use python3 -c here).
# =============================================================================
set -e
cd "$(dirname "$0")"

SRC=${1:-../../../genus/MCU_WOUND/out/MCU_WOUND_hier.genus.sdc}
DST=${2:-in/chip_top_wound_quad.sdc}
TOP=chip_top_wound_quad

if [ ! -f "$SRC" ]; then
	echo "ERROR: $SRC not found -- the HIERARCHICAL wound synthesis does not exist yet."
	echo "       genus/out/MCU_WOUND.genus.sdc is the FLAT run: it puts create_clock on"
	echo "       hart<h>/core/clk_cpu, tile-INTERNAL pins that do not exist behind an ETM."
	echo "       Create genus/tcl/MCU_WOUND_hier.genus.tcl from MCU_DP_hier.genus.tcl and"
	echo "       run 'make MCU_WOUND_hier.genus' in ../../../genus first."
	echo "       (Override the input explicitly: $0 <src.sdc> [dst.sdc])"
	exit 1
fi

sed \
	-e '/^set_load .*\[get_ports /d' \
	-e '/^set_driving_cell .*\[get_ports /d' \
	-e "s|^current_design MCU\$|current_design $TOP|" \
	-e 's|\[get_pins {|[get_pins {mcu0/|g' \
	-e 's|\[get_nets {|[get_nets {mcu0/|g' \
	-e 's|\[get_cells {|[get_cells {mcu0/|g' \
	-e 's|\[get_pins \([^{]\)|[get_pins mcu0/\1|g' \
	-e 's|\[get_nets \([^{]\)|[get_nets mcu0/\1|g' \
	-e 's|\[get_cells \([^{]\)|[get_cells mcu0/\1|g' \
	"$SRC" > "$DST"

cat >> "$DST" <<'EOF'

# Keep the dangling tb-visibility a0 buses + their iso-clamp drivers alive
# (C0 chip_top.sdc precedent -- mcu0 leaves a0/a0_1..3 OPEN; optDesign would
# trim the unloaded driver cone; gate tb probes the tile ports).
set_dont_touch [get_nets -quiet {mcu0/a0[*]}]
set_dont_touch [get_nets -quiet {mcu0/a0_*}]
EOF

# ---- self-checks: loud, cheap, and every one of them has a war story --------
fail=0
if [ "$(grep -c '^current_design '"$TOP"'$' "$DST")" != "1" ]; then
	echo "FATAL: current_design $TOP not set exactly once (source top cell was not 'MCU'?)"; fail=1
fi
if grep -q '\[get_ports ' "$DST"; then
	echo "FATAL: get_ports survived the transform -- the assembly ports do not exist at chip level:"
	grep -n '\[get_ports ' "$DST" | head; fail=1
fi
if grep -qE '\[get_(pins|nets|cells) mcu0/\{' "$DST"; then
	echo "FATAL: brace-path prefixing is wrong ('[get_x mcu0/{...}]' matches nothing):"
	grep -nE '\[get_(pins|nets|cells) mcu0/\{' "$DST" | head; fail=1
fi
# every get_pins/get_nets/get_cells occurrence must be immediately followed by
# an optional brace and then mcu0/ -- anything else is an un-rooted path.
stray=$(grep -oE '\[get_(pins|nets|cells) (-quiet )?\{?[^]} ]*' "$DST" \
        | grep -vE '\[get_(pins|nets|cells) (-quiet )?\{?mcu0/' || true)
if [ -n "$stray" ]; then
	echo "FATAL: instance-scoped collections not re-rooted at mcu0/:"
	echo "$stray" | sort -u | head; fail=1
fi
if grep -q '\[get_designs mcu0/' "$DST"; then
	echo "FATAL: get_designs was prefixed -- it names a MODULE, not an instance."; fail=1
fi
[ $fail -eq 0 ] || { rm -f "$DST"; exit 1; }

echo "wrote $DST"
echo "  from        : $SRC"
echo "  port lines  : $(grep -cE '^(set_load|set_driving_cell) .*\[get_ports ' "$SRC" || true) dropped"
echo "  get_pins    : $(grep -c '\[get_pins ' "$DST" || true) (all mcu0/-rooted)"
echo "  get_nets    : $(grep -c '\[get_nets ' "$DST" || true)"
echo "  get_cells   : $(grep -c '\[get_cells ' "$DST" || true)  (TRNG ring dont_touch block)"
echo "  get_designs : $(grep -c '\[get_designs ' "$DST" || true) (unprefixed, by design)"
