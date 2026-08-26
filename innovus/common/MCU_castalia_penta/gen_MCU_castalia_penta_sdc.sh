#!/bin/bash
# =============================================================================
# gen_MCU_castalia_penta_sdc.sh -- build in/MCU_castalia_penta.sdc from the
# CASTALIA-PENTA hierarchical assembly SDC.
#
# MINIMAL CLONE of ../MCU_castalia/gen_MCU_castalia_sdc.sh. The SDC transform
# itself is UNCHANGED and its provenance is that file's header (it was
# extracted by diffing the G2 golden pair genus MCU_DP_hier.genus.sdc vs
# in/chip_top_dp.sdc and reproduces the committed DP chip SDC with zero diff).
# Four rules, verbatim:
#
#   1. DROP every `set_load .. [get_ports ..]` / `set_driving_cell .. [get_ports ..]`
#      (the assembly's port loads/drivers are the physical pad cells now).
#   2. current_design MCU -> current_design MCU_castalia_penta
#   3. Re-root get_pins / get_nets / get_cells at mcu0/. The prefix goes INSIDE
#      a brace-quoted path.
#   4. NEVER prefix get_clocks / get_designs / get_lib_cells / current_design.
#   5. Append the a0 dangling-bus dont_touch pair -- HERE INCLUDING a0_4, the
#      orchestrator's (CP1 D8: a0_4 is emitted and monitored only).
#
# THE ONE PENTA ADDITION (CP1 D6): the ORCHESTRATOR'S CHIP-LEVEL GENERATED
# CLOCK. The four corner harts are hardened macros whose clk_cpu lives behind
# an ETM and is never a chip-level object. hart0 is SOFT (CPR6 renumber) -- Innovus places its
# std cells in the centre band and CTS must build a real clock tree for its
# gated core clock. The genus penta flow declares that clock at MCU scope
# (`clk_cpu0` on hart0/tile/core/clk_cpu), so write_sdc ALREADY emits it and
# rule 3 re-roots it at mcu0/ like every other instance path -- i.e. it needs
# no hand-written line here. This script therefore ASSERTS its presence rather
# than appending it: a missing orchestrator clock is the M9c bug class at chip
# level, and it must fail loudly at staging, not silently at CTS.
#
# Usage: ./gen_MCU_castalia_penta_sdc.sh [SRC_SDC] [DST_SDC]
#   defaults: ../../../genus/MCU_PENTA/out/MCU_PENTA_hier.genus.sdc
#             -> in/MCU_castalia_penta.sdc
# NOTE: pure sed/awk (this machine's python3 is the quote-stripping aoj_cal
# wrapper -- never use python3 -c here).
# =============================================================================
set -e
cd "$(dirname "$0")"

SRC=${1:-../../../genus/MCU_PENTA/out/MCU_PENTA_hier.genus.sdc}
DST=${2:-in/MCU_castalia_penta.sdc}
TOP=MCU_castalia_penta
ORCH_CLK=clk_cpu0

if [ ! -f "$SRC" ]; then
	echo "ERROR: $SRC not found -- the PENTA hierarchical synthesis does not exist yet."
	echo "       Run 'make MCU_PENTA_hier.genus' in ../../../genus first"
	echo "       (it needs genus/orch_tile/out/orch_tile.renamed.v and the staged"
	echo "        penta-wound MCU.vhd in genus/common/in/penta_wound_hdl/)."
	exit 1
fi

# RULE 6 (PENTA-ONLY) -- DROP the `set_dont_touch [get_designs orch_*]` block.
#
# genus/MCU_PENTA preserves the whole orchestrator subtree during the MCU run
# for ONE reason: to stop genus re-optimizing or RE-NAMING its modules, which
# would destroy the CP1 D6 disjoint namespace. That job is finished the moment
# the netlist is written -- the names are baked into the file.
#
# At P&R the orchestrator is the OPPOSITE of the tiles. The four corner harts
# are hardened macros and `set_dont_touch [get_designs hart_tile]` is exactly
# right for them. hart0 is SOFT LOGIC that Innovus must place, clock-tree and
# optimize: carrying 120 dont_touch'd designs into the chip SDC would freeze
# every cell inside it -- no CTS buffer insertion, no resizing, no hold fixing
# in the one block that is being physically implemented for the first time.
# The tile's line is KEPT; the orchestrator's 120 are dropped, and the check
# below asserts the result is exactly one get_designs line.
#
# RULE 6b (CPR6) -- AND DROP THE ORCHESTRATOR **INSTANCE** dont_touch, for the
# same reason and with a sharper edge. This line did not exist before CPR6, and
# the reason it did not is a trap worth naming: genus/MCU_PENTA's per-hart
# preserve loop used the form `set_db inst:MCU/hart<h> .preserve true` inside a
# `catch`, and `inst:` is NOT a recognized genus object type for a HIERARCHICAL
# instance (TUI-182) -- so for the whole CP era it silently did nothing, and
# write_sdc emitted no `set_dont_touch [get_cells hart<h>]` at all. CPR6
# corrected the form to `hinst:`, all five preserves took, and genus duly wrote
# five instance dont_touch lines. The orchestrator's froze it solid at P&R.
#
# MEASURED (second CPR6 P&R, run aborted on the evidence): with
# `set_dont_touch [get_cells mcu0/hart0]` in force, ccopt could not buffer
# `mcu0/hart0/tile/clk_cpu` -- report_ccopt_clock_trees names it explicitly,
# "Dont touch net? Y", fanout 206 off a single PREICGX1BA10TH, slew 6.407 ns
# against a 400 ps target, ICG CK->ECK delay 3.608 ns -- giving clk_cpu0 a
# 3.43 ns skew (CP5 reference: 0.053 ns) and 74 setup violations at -13.031 ns
# whose worst path is ram0/Q -> adddec staging, i.e. the core's own critical
# path drowning in clock insertion delay.
#
# The four TILE lines are KEPT: they are hardened macros bound to a LEF and an
# ETM, and freezing them is exactly right. Only hart0 is dropped, by exact
# instance name, and P1e below asserts both halves of that split.
	sed \
	-e '/^set_dont_touch \[get_cells hart0\]$/d' \
	-e '/^set_dont_touch \[get_designs orch_/d' \
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
# (C0 chip_top.sdc precedent -- mcu0 leaves a0/a0_1..4 OPEN; optDesign would
# trim the unloaded driver cone; gate tb probes the tile/orchestrator ports).
# CP1 D8: a0_4 is the ORCHESTRATOR's, emitted and monitored only -- hart 0 is
# still the pass/fail gate.
set_dont_touch [get_nets -quiet {mcu0/a0[*]}]
set_dont_touch [get_nets -quiet {mcu0/a0_*}]

EOF

#
# CPR6 TOMBSTONE -- THE ORCHESTRATOR RESET FALSE PATH THAT TURNED OUT NOT TO BE
# NEEDED. The first CPR6 P&R showed 74 setup violations (WNS -14.151 ns) whose
# every top path launched from mcu0/pwr0/boot_hold_r_reg/QN (pgood_rstn) and
# landed on mcu0/hart0/tile/adddec0 staging flops, and the obvious reading was
# that the SOFT orchestrator lacks the `set_false_path -from [get_ports resetn]`
# that hart_tile's own SDC gives all four hardened tiles. An exception was
# written, and it DID take (those beginpoints vanished from the next run's
# reports) -- but the violation count did not move, because the real cause was
# rule 6b's instance dont_touch freezing the whole orchestrator: unresizable
# cells were showing 1.5 ns INVX1 delays and a 3.6 ns ICG. With the freeze
# lifted the exception is unnecessary and was REMOVED rather than left in as a
# constraint nobody could later justify. Re-add it only against fresh evidence
# from a cut whose clk_cpu0 skew is healthy -- and if you do, note that
# `set_false_path -through [get_pins mcu0/hart0/resetn]` resolves without a
# TCLCMD-917 but reaches nothing on its own once the reset buffers are cloned
# to the top level; the working form was -from the launch flop.
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
stray=$(grep -oE '\[get_(pins|nets|cells) (-quiet )?\{?[^]} ]*' "$DST" \
        | grep -vE '\[get_(pins|nets|cells) (-quiet )?\{?mcu0/' || true)
if [ -n "$stray" ]; then
	echo "FATAL: instance-scoped collections not re-rooted at mcu0/:"
	echo "$stray" | sort -u | head; fail=1
fi
if grep -q '\[get_designs mcu0/' "$DST"; then
	echo "FATAL: get_designs was prefixed -- it names a MODULE, not an instance."; fail=1
fi

# ---- THE PENTA ASSERTIONS (CP1 D6) ----------------------------------------
# P1: the orchestrator's generated core clock must be in the chip SDC, and its
#     target pin must be inside mcu0/hart0.
n_orch=$(grep -c "create_generated_clock .*\"$ORCH_CLK\"" "$DST" || true)
if [ "$n_orch" != "1" ]; then
	echo "FATAL P1: $n_orch create_generated_clock line(s) for '$ORCH_CLK' in $DST (want 1)."
	echo "          The orchestrator is SOFT logic -- without this, CTS builds no clock tree"
	echo "          for hart0's gated core clock and every register in it is unconstrained."
	fail=1
elif ! grep "create_generated_clock .*\"$ORCH_CLK\"" "$DST" | grep -q 'mcu0/hart0/'; then
	echo "FATAL P1b: '$ORCH_CLK' is not targeted inside mcu0/hart0/ :"
	grep "create_generated_clock .*\"$ORCH_CLK\"" "$DST"; fail=1
fi
# P1c: the SOFT/HARD split. Exactly ONE get_designs dont_touch must survive --
#      hart_tile's. A surviving orch_* one would freeze the orchestrator at P&R
#      (rule 6); a MISSING hart_tile one would let Innovus optimize inside a
#      hardened macro it only has a LEF and an ETM for.
n_designs=$(grep -c '^set_dont_touch \[get_designs ' "$DST" || true)
n_orchdt=$(grep -c '^set_dont_touch \[get_designs orch_' "$DST" || true)
if [ "$n_orchdt" != "0" ]; then
	echo "FATAL P1c: $n_orchdt 'set_dont_touch [get_designs orch_*]' line(s) survived -- the"
	echo "           orchestrator is SOFT logic and must stay optimizable at P&R."; fail=1
fi
if [ "$(grep -c '^set_dont_touch \[get_designs hart_tile\]$' "$DST" || true)" != "1" ]; then
	echo "FATAL P1d: the hart_tile dont_touch is missing -- the hardened macro would be optimized."; fail=1
fi
# P2: the clock NAME must never have been prefixed (rule 4).
if grep -q 'get_clocks mcu0/' "$DST"; then
	echo "FATAL P2: get_clocks was prefixed with mcu0/ -- clocks are not instances."; fail=1
fi
# P3: the four hardened tiles must contribute NO chip-level clk_cpu (they are
#     behind an ETM). CPR6 INVERSION: the tiles are harts 1..4 now, so the
#     forbidden set is clk_cpu1..clk_cpu4 -- and clk_cpu0, which used to be
#     forbidden, is the one clock that MUST be here (P1 above). Getting this
#     index range wrong in either direction is silent: the old clk_cpu[0-3]
#     pattern would have flagged the orchestrator's own clock as the
#     flat-vs-hier mixup and deleted a correct SDC.
n_tileclk=$(grep -cE 'create_(generated_)?clock .*"clk_cpu[1-4]"' "$DST" || true)
if [ "$n_tileclk" != "0" ]; then
	echo "FATAL P3: $n_tileclk chip-level clk_cpu1..4 clock(s) -- those pins are inside the"
	echo "          hardened tile and do not exist behind the ETM (the flat-vs-hier mixup)."; fail=1
fi

[ $fail -eq 0 ] || { rm -f "$DST"; exit 1; }

echo "wrote $DST"
echo "  from        : $SRC"
echo "  port lines  : $(grep -cE '^(set_load|set_driving_cell) .*\[get_ports ' "$SRC" || true) dropped"
echo "  get_pins    : $(grep -c '\[get_pins ' "$DST" || true) (all mcu0/-rooted)"
echo "  get_nets    : $(grep -c '\[get_nets ' "$DST" || true)"
echo "  get_cells   : $(grep -c '\[get_cells ' "$DST" || true)  (TRNG ring dont_touch block)"
echo "  get_designs : $n_designs dont_touch -- hart_tile ONLY (rule 6 dropped the orch_* ones;" \
     "the orchestrator is SOFT and must stay optimizable)   [P1c/P1d PASS]"
echo "  clocks      : $(grep -c '^create_clock' "$DST" || true) create_clock," \
     "$(grep -c '^create_generated_clock' "$DST" || true) create_generated_clock" \
     "(incl. $ORCH_CLK)   [P1/P2/P3 PASS]"
