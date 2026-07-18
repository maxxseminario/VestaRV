################################################################################
# Innovus script -- ARGUS hart_tile COMPACT-TILE HARDEN (A4 physical flow)
#
# ARGUS variant of tcl/hart_tile.innovus.tcl. The Argus tile is a PLAIN
# RECTANGLE -- no analog potentiostat notch, no U-shape, no fingers (Argus is
# digital-only; the Castalia 500x450 analog reserve dies here).
#
# A8 GEOMETRY (2026-07-17): 520 x 522 NEAR-SQUARE (aspect ~1.0), SUPERSEDES the
# 405 x 685 A-series compact form. The A8 program re-centers the whole Argus
# fabric on the die (RAM row at y=1345 exactly) with hart tiles mirrored across
# the top and bottom; that forces a 4-row {5,4}||{4,5} tile array whose 5-wide
# rows are ring-leg-limited to W~518-520 and whose exact-center stack needs
# H=522 (see ~/vesta_docs/argus/a8/a8_center_symmetry_plan.md 4.5 + a8_geometry.md).
# Validated by the A8-P1 probe (util ~43%, 0.00% H/V overflow, WNS +0.010 pre-CTS).
#
# Floorplan: one sram1p16k TCM (R0, the near-square area-optimized mux-8 macro
# 319.65 x 383.085) in the LOWER-LEFT CORNER (A8 -- the wide 520 tile can no
# longer afford a full-width bottom band: it would waste ~79k um^2 and starve
# the std region at ~90% density). A hard blockage + cutRow cover ONLY the
# macro+halo corner box; std-cell rows fill the L around it (full-width rows
# above the macro + the right strip beside it); the M17 MTCMOS header fabric +
# tap overhead sits in those rows. All tile pins on the BOTTOM edge (M4), same
# as the Castalia tile -- the arbiter/control plane lives below the tile grid at
# assembly, and each tile's shared-bus + IRQ pins drop down through the channels.
# HISTORICAL (405x685 A-series war stories preserved below): the compact tile
# packed a 6-col x 3-row grid on the 2690x2690 M15 interior with a full-width
# bottom RAM/control band; A8's 4-row centered array replaces that layout.
#
# INPUTS: ../../genus/out/hart_tile_argus.genus.{v,sdc} (SH_AW=16, 16-bit
# sh_addr). OUTPUTS carry the _argus basename so the Castalia tile artifacts
# (out/hart_tile.*, SH_AW=15, U-shape) stay pristine. The MODULE/MACRO name is
# plain "hart_tile" (the Argus assembly instantiates it 18x).
#
# LOAD-BEARING M17b/PG1 lessons carried forward from the Castalia tile:
#   * checkerBoard power switch is mandatory (full-density = ~1000 pmk M1
#     pin-frame shorts). It leaves a FEW rows switchless (dead VDD_SW rail).
#   * dead switchless rows must be hard-blocked BEFORE place_opt (after
#     addPowerSwitch phase-shifts if blocked earlier; after sroute strands
#     well-tap frames if blocked later) so place_opt parks no live cell on a
#     dead rail. THE COMPACT-TILE DEAD-ROW SET IS RE-DERIVED PROGRAMMATICALLY
#     here (detect switchless rows from actual switch placement) instead of
#     the U-shape's hardcoded 2 rows -- the rectangle's casualties differ.
#   * addPowerSwitch/addRing/sroute FAIL SOFT -- hard NSW/PG1 guards abort.
#   * sViaInst objects have pt, NOT box -- filter vias on pt_y, wires on box.
#   * PG1: GPGBUF AO repeaters into long SLEEP-chain links over the TCM;
#     dont_touch the chain; a hard acceptance gate before signoff.
#
# Outputs (out/): hart_tile_argus.{gds2,sdf,xsim.v,lef} + .ilm + per-corner
# .etm_{ss,ff}.lib -- feed the Argus assembly (viewdefinition_top_argus).
################################################################################

source tcl/constants.tcl
source $SCRIPT_DIR/procedures.tcl

# Flushing logger -- Innovus buffers bare `puts`, so an abort (or exit 1) can
# SWALLOW the last instrumentation/FATAL lines (they never reach the log). Use
# plog for every status/guard message so what happened is always visible.
proc plog {msg} { puts $msg; flush stdout }

set DESIGN_NAME hart_tile
set OUT_NAME    hart_tile_argus

# --- A8 near-square geometry (520 x 522 = 0.271 mm^2; supersedes 405 x 685) ---
# The A8 4-row centered array (a8_center_symmetry_plan.md) fixes these dims:
#  * W=520: the assembly's L/R M7 ring legs (inner edges x=29/2661) cap a
#    ring-clearing 5-wide tile row at W~518-520; 520 with gap 7.5 fills [30,2660].
#  * H=522: puts the RAM row centered on y=1345 EXACTLY (top 2656.54 <= the
#    2657.5 top-ring cap), the geometry that literally satisfies "RAM in the
#    center of the die" (fallback 520x528 -> midline 1333.96 is an ORCHESTRATOR
#    call, not this flow's).
# The corner TCM (below) keeps the wide tile's std region routable: A8-P1 probed
# 43.3% L-region std density, 0.00% H/V trial-route overflow, WNS +0.010 pre-CTS.
#
# HISTORICAL (A4, 405x685): the compact tile put the R0 TCM in a FULL-WIDTH
# bottom band, cutRow'd so no std rows lived there (all logic in the full-width
# rows ABOVE the TCM), sidestepping the side-strip dead-rail trap (a macro splits
# rows beside it into short segments; the checkerboard leaves ALTERNATING such
# segments switchless). The wide A8 tile cannot spend a full band, so the TCM
# moves to a CORNER and the L's right strip DOES carry short row segments -- but
# the pitch-80 checkerboard columns (x=350/430/510) still switch them (A8-P1: 1
# dead row total). Routing channels beside the TCM stay OPEN (cutRow removes
# rows, not routing).
set DESIGN_WIDTH  520
set DESIGN_HEIGHT 522

# Power ring / stripe geometry (Myshkin/M17 values -- proven; keep on cut 1).
set POWER_RING_PATH_WIDTH	10.0
set POWER_RING_PATH_SPACING	4.0
set POWER_STRIPE_PATH_WIDTH		5.0
set POWER_STRIPE_PATH_SPACING	4.0
set POWER_STRIPE_SET_TO_SET		[expr {$STD_CELL_HEIGHT * 25}]

set CORE_SPACING	1
set CORE_WIDTH		[expr {$DESIGN_WIDTH - ($CORE_SPACING * 2)}]
set CORE_HEIGHT		[expr {$DESIGN_HEIGHT - ($CORE_SPACING * 2)}]

tic

################################################################################
# Design import and setup
################################################################################
set init_verilog             "$GENUS_DIR/out/$OUT_NAME.genus.v"
set init_top_cell            "$DESIGN_NAME"
set init_pwr_net             "VDD"
set init_gnd_net             "VSS"
set init_mmmc_file           "$SCRIPT_DIR/viewdefinition_tile_argus.tcl"

set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					../../std_cells/lef/tsmc65hvt_adv10pmk_macro.USEfix.lef \
					$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef"

set init_design_uniquify 1
init_design

################################################################################
# M17 power intent -- identical CPF to the Castalia tile (same ports/domains:
# PD_GATED default/shutoff=pd_sleep + PD_AO for ports/iso; VDD always-on,
# VDD_SW the switched follow-pin net). SH_AW does not touch power intent.
################################################################################
read_power_intent -cpf ../../cpf/hart_tile.cpf
commit_power_intent
printStatus "Power intent committed (PD_GATED/PD_AO, switched net VDD_SW)"

setDesignMode -process 65 -flowEffort standard -powerEffort low
printStatus "Preparing 8 CPU cores..."
setMultiCpuUsage -acquireLicense 8 -localCpu 8

# M17: plain (tapless) FILL cells only; well-tap duty = the FILLBIAS addWellTap
# pass (a rail-tied tap in a gated row back-feeds the dead VDD_SW rail).
setFillerMode \
    -corePrefix FILLER \
    -core {FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH}

setAnalysisMode -analysisType onChipVariation -cppr both

# M17 domain-aware global nets. PD_GATED rows = switched net VDD_SW; ram0
# ties AO VDD (self-gates via native PGEN mirrored on tcm_pgen at MCU level);
# secondary pmk pins (VDDG/VNW/VPW) connected AFTER the switch/tap cells exist.
clearGlobalNets
globalNetConnect VDD_SW -type pgpin -pin VDD  -powerDomain PD_GATED -autoTie -verbose
globalNetConnect VDD    -type pgpin -pin VDD  -powerDomain PD_AO    -verbose
globalNetConnect VDD    -type pgpin -pin VDD  -singleInstance ram0 -override -verbose
globalNetConnect VSS    -type pgpin -pin VSS  -inst * -module {} -autoTie -verbose

################################################################################
# Floorplan: a PLAIN RECTANGLE (no polygon, no notch). TCM R0 bottom-center.
################################################################################
floorPlan \
    -site TSMC65ADV10TSITE \
    -s $CORE_WIDTH $CORE_HEIGHT $CORE_SPACING $CORE_SPACING $CORE_SPACING $CORE_SPACING
initCoreRow
printStatus "Floorplanned plain rectangle ($DESIGN_WIDTH x $DESIGN_HEIGHT)"

set SRAM16K_WIDTH		319.650
set SRAM16K_HEIGHT		383.085
set TCM_HALO		[expr {$STD_CELL_HEIGHT * 1}]

# A8 CORNER TCM (supersedes the A-series full-width bottom band): the sram1p16k
# goes in the LOWER-LEFT corner (R0). TCM_X=12 mirrors the proven bottom
# clearance (TCM_Y=12) to the left edge; both clear the M7/M8 ring band and the
# M4 bottom pin strip (383-tall macro tops out ~y=395). The hard place-blockage
# + cutRow cover ONLY the macro+halo corner box, so std-cell rows survive as the
# L around it (full-width rows above the macro top + the right-strip rows beside
# it). A8-P1 validated: 62 full-width rows above + 198 right-strip rows, 0
# leftover in the corner.
set TCM_X	12
set TCM_Y	12
placeInstance ram0 $TCM_X $TCM_Y R0
addHaloToBlock $TCM_HALO $TCM_HALO $TCM_HALO $TCM_HALO ram0

# corner box: die corner (0,0) up to the macro+halo extent.
set TCM_BLK_X1 [expr {$TCM_X + $SRAM16K_WIDTH  + $TCM_HALO}]
set TCM_BLK_Y1 [expr {$TCM_Y + $SRAM16K_HEIGHT + $TCM_HALO}]
plog "### UNL STATUS ### : corner TCM ram0 @($TCM_X,$TCM_Y) R0 -> macro+halo corner box 0 0 [format %.3f $TCM_BLK_X1] [format %.3f $TCM_BLK_Y1]"

# CRITICAL (A4 cutRow lesson, carried forward): `cutRow -area` only cuts rows
# that sit UNDER AN OBSTACLE, so a bare `cutRow -area` over the corner would
# leave the sub-macro strip rows ALIVE. Create a hard PLACEMENT BLOCKAGE over
# the corner box first (the MCU_MP.innovus createPlaceBlockage->cutRow pattern),
# THEN cutRow removes the rows under it. Only the corner is cut -- the L's two
# arms keep their rows; routing channels beside the TCM stay OPEN.
cutRow
createPlaceBlockage -type hard -name tcm_corner -box [list 0 0 $TCM_BLK_X1 $TCM_BLK_Y1]
cutRow -area [list 0 0 $TCM_BLK_X1 $TCM_BLK_Y1]

# Diagnostic: rows must survive OUTSIDE the corner box (the L). Count the two
# arms + any leftover inside the corner box (want 0).
set rows_above 0
set rows_right_strip 0
set rows_in_corner 0
foreach r [dbGet top.fplan.rows -e] {
	set b [lindex [dbGet $r.box] 0]
	foreach {bx0 by0 bx1 by1} $b {}
	if {$by0 < [expr {$TCM_BLK_Y1 - 0.5}]} {
		if {$bx0 < [expr {$TCM_BLK_X1 - 0.5}]} { incr rows_in_corner } else { incr rows_right_strip }
	} else {
		incr rows_above
	}
}
plog "### UNL STATUS ### : corner box 0 0 $TCM_BLK_X1 $TCM_BLK_Y1 blocked+cut -- rows above-macro=$rows_above right-strip=$rows_right_strip leftover-in-corner=$rows_in_corner (want 0)"
if {$rows_in_corner > 0} {
	plog "FATAL (A8): $rows_in_corner rows survived inside the TCM corner box -- cutRow did not clear it"
	exit 1
}
printStatus "Placed corner TCM (R0, lower-left) + cleared corner box"

# All tile pins on the BOTTOM edge (M4, vertical-preferred): at assembly the
# arbiter/control plane is below the tile grid.
set ALL_PINS [dbGet top.terms.name]
puts "Assigning [llength $ALL_PINS] pins to the bottom edge"
editPin -pin $ALL_PINS -side Bottom -layer 4 -spreadType side -spacing 1 -fixOverlap 1
printStatus "Placed tile pins"

################################################################################
# Power: full rectangular ring (all 4 sides) + M7/M8 stripe grid
################################################################################
printStatus "Adding power ring/stripes"
addRing \
    -nets {VDD VSS} \
    -type core_rings \
    -follow io \
    -layer {top M8 bottom M8 left M7 right M7} \
    -width $POWER_RING_PATH_WIDTH \
    -spacing $POWER_RING_PATH_SPACING \
    -offset $POWER_RING_PATH_SPACING \
    -center 0 -extend_corner {} -threshold 0 -jog_distance 0 \
    -snap_wire_center_to_grid None

setAddStripeMode \
    -remove_floating_stripe_over_block true \
    -trim_antenna_back_to_shape core_ring \
	-stacked_via_top_layer M8 \
    -extend_to_closest_target ring
addStripe \
	-layer M8 \
	-nets {VDD VSS} \
	-direction horizontal \
	-start_from left \
	-set_to_set_distance $POWER_STRIPE_SET_TO_SET \
	-spacing $POWER_STRIPE_PATH_SPACING \
	-width $POWER_STRIPE_PATH_WIDTH \
	-block_ring_bottom_layer_limit M1 \
	-start_offset $POWER_STRIPE_SET_TO_SET \
	-stop_offset $POWER_STRIPE_PATH_SPACING
addStripe \
	-layer M7 \
	-nets {VDD VSS} \
	-direction vertical \
	-extend_to design_boundary \
	-start_from bottom \
	-set_to_set_distance $POWER_STRIPE_SET_TO_SET \
	-spacing $POWER_STRIPE_PATH_SPACING \
	-width $POWER_STRIPE_PATH_WIDTH \
	-block_ring_bottom_layer_limit M1 \
	-start_offset $POWER_STRIPE_SET_TO_SET \
	-stop_offset $POWER_STRIPE_PATH_SPACING

editTrim -all
setCheckMode -globalNet true -io true -route true -tapeOut true

# A8 PG LANE SANITY (from the A8-P1 probe): every M7 vertical PG lane x must stay
# inside the die -- the parametric stripe grid must extend cleanly to W=520, not
# spill past the right edge. Probe read at 520: VDD/VSS pairs 53.5/62.5 + 50k
# (k=0..8) + L/R ring legs -> 22 lanes, x 9.00..511.0 < 520. Diagnostic (WARN,
# no abort); the exported lane x-list is the LEF delta A8-2 consumes.
set m7_lane_xs {}
foreach __net {VDD VSS} {
	foreach __sw [dbGet [dbGet -p top.nets.name $__net].sWires -e] {
		if {[dbGet -e $__sw.layer.name] ne "M7"} { continue }
		set __b [lindex [dbGet $__sw.box] 0]
		foreach {__x0 __y0 __x1 __y1} $__b {}
		if {[expr {$__y1 - $__y0}] < [expr {$__x1 - $__x0}]} { continue }
		lappend m7_lane_xs [format %.2f [expr {($__x0 + $__x1) / 2.0}]]
	}
}
set m7_lane_xs [lsort -real -unique $m7_lane_xs]
set m7_lane_max [expr {[llength $m7_lane_xs] ? [lindex $m7_lane_xs end] : -1}]
plog "### UNL STATUS ### : [llength $m7_lane_xs] M7 vertical PG lanes, x range [lindex $m7_lane_xs 0]..$m7_lane_max (die W=$DESIGN_WIDTH)"
plog "### UNL STATUS ### : M7 lane xs = $m7_lane_xs"
if {$m7_lane_max >= $DESIGN_WIDTH} {
	plog "FATAL (A8): an M7 PG lane x ($m7_lane_max) reached/exceeded the die width $DESIGN_WIDTH"
	exit 1
}

################################################################################
# M17 MTCMOS header fabric. HEADBUF16M columns every 80 um, switch in every
# row (-skipRows 0), -checkerBoard true (LOAD-BEARING: full-density = ~1000
# pmk M1 pin-frame shorts). The checkerboard stagger leaves a FEW boundary
# rows switchless -- detected + blocked below (re-derived for this shape).
# A8: -area is the WHOLE core (only the lower-left corner box was cut, so live
# rows exist across the die minus that corner); no switches land in the cut
# corner. The wide tile's right-strip rows DO get switched by the pitch-80
# checkerboard columns (A8-P1: 1 dead row total).
################################################################################
printStatus "Inserting MTCMOS header switch columns (HEADBUF16MA10TH)"
addPowerSwitch -column -powerDomain PD_GATED \
	-globalSwitchCellName {HEADBUF16MA10TH} \
	-area [list $CORE_SPACING $CORE_SPACING [expr {$DESIGN_WIDTH - $CORE_SPACING}] [expr {$DESIGN_HEIGHT - $CORE_SPACING}]] \
	-leftOffset 30 \
	-horizontalPitch 80 \
	-skipRows 0 \
	-checkerBoard true \
	-enableNetIn pd_sleep \
	-enableNetOut pd_sleep_chain_out

# addPowerSwitch FAILS SOFT (IMPPSO-109) -- a zero-switch tile sails to signoff
# with an unpowered VDD_SW net and only dies at the assembly gate sim. Iterate
# ACTUAL switch instances (NOT `dbGet -p top.insts.cell.name` -- that -p form
# returns the shared libCell, on which .box_lly is invalid).
set sw_insts {}
foreach inst [dbGet top.insts -e] {
	if {[dbGet $inst.cell.name] eq "HEADBUF16MA10TH"} { lappend sw_insts $inst }
}
set NSW [llength $sw_insts]
plog "### UNL STATUS ### : $NSW HEADBUF16MA10TH power switches inserted"
if {$NSW == 0} {
	plog "FATAL (A4): addPowerSwitch inserted ZERO switches -- aborting"
	exit 1
}

################################################################################
# RE-DERIVE THE DEAD-ROW CONTRACT (compact rectangle). Detect every core row
# with NO switch on it -- its VDD_SW follow-pin rail is dead. Store the boxes
# now (switch placement is final); the BLOCKAGES are created just before
# place_opt (position is load-bearing -- see there). This replaces the U-tile's
# hardcoded 2 rows: the rectangle's checkerboard casualties differ and must be
# measured, not assumed.
################################################################################
set ROW_H $STD_CELL_HEIGHT
# switch row y-origins (from the real instances collected above; snap 0.001 um)
set sw_ys {}
foreach c $sw_insts {
	lappend sw_ys [format %.3f [dbGet $c.box_lly]]
}
set sw_ys [lsort -unique $sw_ys]
# all core-row y-origins
set all_row_ys {}
foreach r [dbGet top.fplan.rows -e] {
	set ry [format %.3f [dbGet $r.box_lly]]
	if {[lsearch -exact $all_row_ys $ry] >= 0} { continue }
	lappend all_row_ys $ry
}
set all_row_ys [lsort -unique $all_row_ys]
plog "### UNL STATUS ### : [llength $all_row_ys] distinct core rows, [llength $sw_ys] rows carry a switch"
# Guard the row accessor: an empty set means dbGet top.fplan.rows is the wrong
# path in this build (would silently yield NDEAD=0 and route on dead rails).
if {[llength $all_row_ys] == 0} {
	plog "FATAL (A4): zero core rows from 'dbGet top.fplan.rows' -- wrong accessor, fix before routing"
	exit 1
}
# CORNER-TCM MODEL (A8): there is no full-width bottom band to partition -- the
# only cut region is the lower-left corner box (row-free). Every switchless row
# detected here is therefore a REAL casualty in the L placeable region and must
# be blocked so place_opt parks nothing live on its dead VDD_SW rail. A8-P1
# measured just 1 such row at 520x522 (the pitch-80 checkerboard covers even the
# short right-strip rows via the columns at x=350/430/510).
set dead_row_boxes {}
foreach ry $all_row_ys {
	set covered 0
	foreach sy $sw_ys { if {abs($ry - $sy) < 0.01} { set covered 1; break } }
	if {$covered} { continue }
	set bx [list 0 $ry $DESIGN_WIDTH [expr {$ry + $ROW_H}]]
	lappend dead_row_boxes $bx
	plog "DEAD-ROW: switchless row at y=$ry (VDD_SW rail dead) -> will block"
}
set NDEAD [llength $dead_row_boxes]
plog "### UNL STATUS ### : $NDEAD switchless dead rows detected (block); A8-P1 probe measured 1 at 520x522"
# Sanity: the checkerboard should leave only a HANDFUL of rows dead. A large
# count means the stagger/pitch is wrong -- refuse to route blind. Re-baselined
# from the A8 corner geometry (probe=1); kept generous at 8.
if {$NDEAD > 8} {
	plog "FATAL (A8): $NDEAD switchless rows -- checkerboard/detection anomaly, inspect before routing"
	exit 1
}

# M17: well taps (FILLBIAS, not FILLTIE -- a rail-tied tap back-feeds the dead
# VDD_SW rail through the well). Bias pins must exist before the secondary
# sroute below.
addWellTap \
    -cell FILLBIASA10TH \
    -cellInterval 24 \
    -fixedGap \
    -checkerBoard \
    -prefix WELLTAP

# pmk secondary pins, now that the switch + tap instances exist.
# PG4/PG2-F1 LESSON (M19c port from hart_tile.innovus.tcl — this exact spot
# shipped a dead chip three times on the Castalia tile):
#  * `-type net` here was the M17 "lesson 6" workaround for IMPDB-1221 --
#    but -type net re-parents a NET and NEVER binds pins: it printed
#    IMPDB-1223 in every run while `catch` saw rc=0 (Innovus errors are
#    not tcl errors) and the flow sailed on with every header VDDG,
#    GPGBUF and FILLBIAS well-bias pin bound to NO net (PG2-F1).
#  * `-type pgpin` is the correct verb and works now BECAUSE the local
#    USEfix pmk LEF (see init_lef_file) gives these pins their USE class.
globalNetConnect VDD -type pgpin -pin VDDG -inst * -module {} -verbose
globalNetConnect VDD -type pgpin -pin VNW  -inst * -module {} -verbose
globalNetConnect VSS -type pgpin -pin VPW  -inst * -module {} -verbose

printStatus "Routing power rails"
setSrouteMode -corePinMaxViaScale "100 10"
sroute \
	-nets { VSS VDD VDD_SW } \
	-allowLayerChange 0 \
	-allowJogging 0 \
	-connect corePin \
    -corePinWidth 0.3

# PG4/PG2-F1: `-powerDomains PD_GATED` is REQUIRED — without a domain scope
# this pass exits IMPSR-503 in 0.2 s having routed NOTHING (trigger = the
# CPF power domains + switch cells). Same form as the PG1 repeater pass
# below, which always carried the option.
printStatus "Routing secondary power pins (VDDG / VNW / VPW)"
sroute \
	-nets { VDD VSS } \
	-connect { secondaryPowerPin } \
	-secondaryPinNet { VDD VSS } \
	-allowLayerChange 1 \
	-allowJogging 1 \
	-layerChangeRange { M1(1) M4(4) } \
	-powerDomains PD_GATED

################################################################################
# PG4 FABRIC COMPLETION + F1 acceptance gates (M19c port from
# tcl/hart_tile.innovus.tcl :455-887, adapted to the Argus compact-tile
# geometry). The secondary sroute above only draws a tiny M1 finger ON each
# secondary pin and stacks vias opportunistically where PG metal crosses
# overhead: most FILLBIAS taps + headers end as FLOATING M1 fingers. This
# campaign builds the real strap fabric (M2 VDD columns over the VNW/VDDG bars
# + VPW->VSS M1 jumpers), ladders sick columns to the M8 grid, scrubs the
# litter, and gates the result. ARGUS DELTAS vs the Castalia U-tile:
#  * NO hardcoded M8-row literals: Castalia's 51/53.5/60 come from its PG3
#    half-pitch shift; the Argus grid has NONE (base 50.0). The M8 VDD/VSS row
#    llys are PROBED from the DB (pg4_probe_m8_rows) and every downstream row
#    center/target is derived.
#  * pg4_dead_row is REDEFINED off the programmatic dead_row_boxes + the TCM
#    band (no FINGER_W/BASE_H; the Argus tile is a plain rect, no U-notch).
#  * puts -> plog. The U-shape M7.S.4(b) notch-bend patch is NOT ported.
################################################################################

# PG4/M19c: DERIVE the M8 VDD/VSS power-row llys from the DB instead of the
# Castalia hardcoded 51/53.5/60 literals (its half-pitch-shifted grid). Probe
# the real HORIZONTAL M8 special-wire llys per net once; the ladder remedy and
# the repeater straps (block c) consume these globals.
proc pg4_probe_m8_rows {} {
	global pg4_m8_vdd_llys pg4_m8_vss_llys
	foreach {net var} {VDD pg4_m8_vdd_llys VSS pg4_m8_vss_llys} {
		set llys {}
		foreach __sw [dbGet [dbGet -p top.nets.name $net].sWires -e] {
			if {[dbGet -e $__sw.layer.name] ne "M8"} { continue }
			set __b [lindex [dbGet $__sw.box] 0]
			foreach {__x0 __y0 __x1 __y1} $__b {}
			# horizontal stripe/ring only: much wider than tall
			if {[expr {$__x1 - $__x0}] < [expr {$__y1 - $__y0}]} { continue }
			lappend llys [format %.3f $__y0]
		}
		set $var [lsort -real -unique $llys]
	}
}
proc pg4_m8_row_above {net y} {
	global pg4_m8_vdd_llys pg4_m8_vss_llys
	set llys [expr {$net eq "VDD" ? $pg4_m8_vdd_llys : $pg4_m8_vss_llys}]
	foreach l $llys { if {$l > $y} { return $l } }
	return ""
}
proc pg4_m8_row_below {net y} {
	global pg4_m8_vdd_llys pg4_m8_vss_llys
	set llys [expr {$net eq "VDD" ? $pg4_m8_vdd_llys : $pg4_m8_vss_llys}]
	set best ""
	foreach l $llys { if {$l < $y} { set best $l } else { break } }
	return $best
}
pg4_probe_m8_rows
plog "### UNL STATUS ### : PG4/M19c probed [llength $pg4_m8_vdd_llys] M8 VDD rows, [llength $pg4_m8_vss_llys] M8 VSS rows (derived, NOT hardcoded 51/53.5/60)"
if {[llength $pg4_m8_vdd_llys] == 0} {
	plog "FATAL (PG4/M19c): probed ZERO horizontal M8 VDD rows -- cannot derive the strap grid. Aborting."
	exit 1
}

# PG4 F1 acceptance gate a (PHYSICAL -- catches the IMPDB-1221/1223 rule no-ops
# AND the IMPSR-503/1253 sroute no-ops: both end the same way, no metal on the
# secondary pins). Net VDD must hold >> the broken baseline (ring + stripes
# only, nothing below M6 = the PG2-F1 signature).
# M19c: re-baseline from first Argus run -- Castalia's 500 was on a 660x1050
# U-tile; Argus is a 405x685 PLAIN rect with the bottom ~407 um band row-free,
# so the stripe/ring/strap sWire count scales down. Conservatively 200; RESET
# from the first real Argus harden's reported VDD sWire count.
set PG4_F1A_VDD_SW_MIN 1900  ;# A8 re-baselined: 520x522 corner-TCM run measured 3493 (was 405x685=2805); floor ~54%
set __f1_vdd_sw [llength [dbGet [dbGet -p top.nets.name VDD].sWires -e]]
set __f1_vss_sw [llength [dbGet [dbGet -p top.nets.name VSS].sWires -e]]
plog "### UNL STATUS ### : PG4 F1 gate a -- VDD sWires=$__f1_vdd_sw VSS sWires=$__f1_vss_sw post-secondary-sroute (min $PG4_F1A_VDD_SW_MIN)"
if {$__f1_vdd_sw < $PG4_F1A_VDD_SW_MIN} {
	plog "FATAL (PG4/F1): only $__f1_vdd_sw VDD sWires after the secondary sroute -- the VDDG/VNW strap pass did nothing (IMPSR-503/1253 class). Aborting."
	exit 1
}

################################################################################
# PG4 FABRIC COMPLETION (Castalia :472-887). What completes the fabric:
#  1. one narrow vertical M2 VDD strap per TAP column (x0+0.10, over the VNW
#     pin bars) and per HEADER column (x0+2.325, over a VDDG comb bar), with
#     -stacked_via_bottom_layer M1 so a VIA1 lands on every pin and full stacks
#     at each M8-grid crossing;
#  2. a short M1 jumper per FILLBIAS VPW pin to the VSS rail (VNW can NOT use
#     the same trick -- the rail on its side is VDD_SW -- hence the M2 strap).
# addStripe -start_offset is AREA-relative here. Self-checks gate every step;
# dead-row / band cells are SKIPPED so the end-of-flow scrub deletes them clean.
################################################################################
printStatus "PG4: completing the pmk secondary strap fabric (M2 columns + VPW jumpers)"
# minimal stripe mode: -reset clears the main grid's antenna trim (trim=
# core_ring SHREDS any strap that cannot reach the M8 grid into per-pin frags).
setAddStripeMode -reset
setAddStripeMode \
    -stacked_via_top_layer M8 \
    -stacked_via_bottom_layer M1 \
    -extend_to_closest_target none

set __ram0_box [lindex [dbGet [dbGet -p top.insts.name ram0].box] 0]
foreach {__rmx0 __rmy0 __rmx1 __rmy1} $__ram0_box {}

proc pg4_has_svia {box wantnet} {
	foreach {bx0 by0 bx1 by1} $box {}
	foreach o [dbQuery -area [list [expr {$bx0 - 0.5}] [expr {$by0 - 0.5}] [expr {$bx1 + 0.5}] [expr {$by1 + 0.5}]] -objType sVia] {
		if {[dbGet -e $o.net.name] eq $wantnet} { return 1 }
	}
	return 0
}
# PG4/A8: pg4_dead_row REDEFINED for the corner-TCM L. A cell is on a dead rail
# iff its row-origin sits inside a programmatic dead_row_box (a checkerboard
# casualty, detected earlier) OR inside the lower-left CORNER BOX (x < TCM_BLK_X1
# AND y < TCM_BLK_Y1, which is row-free/cutRow'd). CRITICAL: unlike the A-series
# full-width band, the corner test is 2-D -- it must NOT flag the LIVE right-strip
# L-arm at x >= TCM_BLK_X1. No FINGER_W/BASE_H -- there is no U-notch here.
proc pg4_dead_row {bx} {
	global dead_row_boxes TCM_BLK_X1 TCM_BLK_Y1
	foreach {x0 y0 x1 y1} $bx {}
	if {$x0 < [expr {$TCM_BLK_X1 - 0.5}] && $y0 < [expr {$TCM_BLK_Y1 - 0.5}]} { return 1 }
	foreach __db $dead_row_boxes {
		if {abs($y0 - [lindex $__db 1]) < 0.5} { return 1 }
	}
	return 0
}

# collect strap columns: tap columns keyed by inst x (pins at x0+0.10..0.40),
# header columns (pins at x0+2.325..2.625)
array unset __colys
foreach __i [dbGet -p2 top.insts.cell.name FILLBIASA10TH] {
	set __bx [lindex [dbGet $__i.box] 0]
	if {[pg4_dead_row $__bx]} { continue }
	set __x [format %.2f [lindex $__bx 0]]
	lappend __colys(T$__x) [lindex $__bx 1]
}
foreach __i [dbGet -p2 top.insts.cell.name HEADBUF16MA10TH] {
	set __bx [lindex [dbGet $__i.box] 0]
	if {[pg4_dead_row $__bx]} { continue }
	set __x [format %.2f [lindex $__bx 0]]
	lappend __colys(H$__x) [lindex $__bx 1]
}
set __nstrap 0
set __nstrap_skip 0
set __skipped_runs {}
set __placed_runs {}
foreach __key [array names __colys] {
	set __x0 [string range $__key 1 end]
	if {[string index $__key 0] eq "T"} {
		set __sx [expr {$__x0 + 0.10}]
	} else {
		set __sx [expr {$__x0 + 2.325}]
	}
	# cluster the cell y's into runs (gap > 40 um starts a new run)
	set __ys [lsort -real $__colys($__key)]
	set __runs {}
	set __rs [lindex $__ys 0]; set __re $__rs
	foreach __y $__ys {
		if {[expr {$__y - $__re}] > 40.0} { lappend __runs [list $__rs $__re]; set __rs $__y }
		set __re $__y
	}
	lappend __runs [list $__rs $__re]
	foreach __run $__runs {
		foreach {__ry0 __ry1} $__run {}
		set __ay0 [expr {$__ry0 - 1.0}]
		set __ay1 [expr {$__ry1 + 3.0}]
		# never let a strap cross ram0 (M1-only cells are safe; the MACRO is not)
		if {$__sx > [expr {$__rmx0 - 1.0}] && $__sx < [expr {$__rmx1 + 1.0}]} {
			if {$__ay0 < $__rmy1 && $__ay1 > $__rmy0} {
				if {$__ry1 < $__rmy0} { set __ay1 [expr {$__rmy0 - 0.5}] } else { set __ay0 [expr {$__rmy1 + 0.5}] }
			}
		}
		addStripe -layer M2 -nets {VDD} -direction vertical -width 0.3 \
			-set_to_set_distance 1000 -start_offset 0.2 -stop_offset 0.1 \
			-area [list [expr {$__sx - 0.2}] $__ay0 [expr {$__sx + 0.5}] $__ay1]
		# PER-CELL coverage check. The engine places PARTIAL straps: with
		# top=M8 it keeps only the pieces it can upstack. Any member cell
		# without a VDD via gets a top=M2 RETRY over just its subrange; cells
		# still naked after the retry are waived (taps, recorded) or FATAL
		# (headers). NO lateral fixups (a bring-up variant "fixed" naked pins
		# with 12-um M1 corewires across the row -- a short factory).
		set __cw [expr {[string index $__key 0] eq "H" ? 4.0 : 0.4}]
		set __uncov {}
		foreach __y $__ys {
			if {$__y < $__ry0 || $__y > $__ry1} { continue }
			if {![pg4_has_svia [list $__x0 $__y [expr {$__x0 + $__cw}] [expr {$__y + 2.0}]] VDD]} { lappend __uncov $__y }
		}
		if {[llength $__uncov] > 0} {
			# cluster uncovered cells into subranges and retry with top=M2
			set __srs {}
			set __us [lindex $__uncov 0]; set __ue $__us
			foreach __y $__uncov {
				if {[expr {$__y - $__ue}] > 12.0} { lappend __srs [list $__us $__ue]; set __us $__y }
				set __ue $__y
			}
			lappend __srs [list $__us $__ue]
			setAddStripeMode -stacked_via_top_layer M2
			foreach __sr $__srs {
				foreach {__u0 __u1} $__sr {}
				addStripe -layer M2 -nets {VDD} -direction vertical -width 0.3 \
					-set_to_set_distance 1000 -start_offset 0.2 -stop_offset 0.1 \
					-area [list [expr {$__sx - 0.2}] [expr {$__u0 - 1.0}] [expr {$__sx + 0.5}] [expr {$__u1 + 3.0}]]
			}
			setAddStripeMode -stacked_via_top_layer M8
			set __still {}
			foreach __y $__uncov {
				if {![pg4_has_svia [list $__x0 $__y [expr {$__x0 + $__cw}] [expr {$__y + 2.0}]] VDD]} { lappend __still $__y }
			}
			if {[llength $__still] > 0} {
				if {[string index $__key 0] eq "H"} {
					plog "FATAL (PG4/F1): [llength $__still] header cells in $__key still naked after the top=M2 retry (y: [lrange $__still 0 5]). Aborting."
					saveDesign dbs/pg4gateb_fail.innovus
					exit 1
				}
				foreach __y $__still {
					incr __nstrap_skip
					lappend __skipped_runs [list $__sx $__y $__y]
				}
				plog "PG4: waiving [llength $__still] naked taps in $__key after retry (y: [lrange $__still 0 5])"
			}
		}
		# unconditional continuity rect: partial attempt-1 pieces + retry
		# fragments merge into ONE conductor (no-op when already continuous)
		add_shape -net VDD -layer M2 -rect [list $__sx [expr {$__ry0 - 0.5}] [expr {$__sx + 0.3}] [expr {$__ry1 + 2.5}]] -shape STRIPE -status ROUTED
		incr __nstrap
		lappend __placed_runs [list $__key $__sx $__ay0 $__ay1]
	}
}

# --- PG4 phase 2: columns whose strap band lies under FOREIGN M7 (the VSS ring
# legs / VSS stripes) can never stack up to the M8 grid. Ladder the sick strap
# to the NEAREST healthy column with horizontal SAME-LAYER M2 links -- touching
# same-net same-layer metal connects with NO vias (editPowerVia -add_vias was
# proven a no-op for this). Links land at M8-VDD-row centers so column current
# spreads across the neighbour's stacks. A run is healthy iff it has >= 1 real
# upward stack (via4..7) in band.
proc pg4_upstacks {sx y0 y1} {
	set n 0
	foreach o [dbQuery -area [list [expr {$sx - 0.1}] $y0 [expr {$sx + 0.4}] $y1] -objType sVia] {
		if {[dbGet -e $o.net.name] ne "VDD"} { continue }
		set vn [dbGet -e $o.via.name]
		if {[string match -nocase via4* $vn] || [string match -nocase via5* $vn] || [string match -nocase via6* $vn] || [string match -nocase via7* $vn]} { incr n }
	}
	return $n
}
set __healthy {}
set __sick {}
set __link_rects {}
foreach __pr $__placed_runs {
	foreach {__key __sx __ay0 __ay1} $__pr {}
	if {[pg4_upstacks $__sx $__ay0 $__ay1] > 0} { lappend __healthy $__pr } else { lappend __sick $__pr }
}
plog "### UNL STATUS ### : PG4 strap columns: [llength $__healthy] healthy / [llength $__sick] need the M8 ladder remedy"
set __nlink 0
foreach __pr $__sick {
	foreach {__key __sx __ay0 __ay1} $__pr {}
	# nearest healthy neighbour with y overlap
	set __best ""
	set __bestd 1e9
	foreach __hr $__healthy {
		foreach {__hk __hx __hy0 __hy1} $__hr {}
		set __ov [expr {min($__ay1, $__hy1) - max($__ay0, $__hy0)}]
		if {$__ov < 2.0} { continue }
		set __d [expr {abs($__hx - $__sx)}]
		if {$__d < $__bestd} { set __bestd $__d; set __best $__hr }
	}
	if {$__best eq "" || $__bestd > 30.0} {
		plog "FATAL (PG4/F1): no healthy strap column within 30 um of sick run $__key ($__sx) -- cannot ladder. Aborting."
		saveDesign dbs/pg4gateb_fail.innovus
		exit 1
	}
	foreach {__hk __hx __hy0 __hy1} $__best {}
	set __lx0 [expr {min($__sx, $__hx)}]
	set __lx1 [expr {max($__sx, $__hx) + 0.3}]
	set __oy0 [expr {max($__ay0, $__hy0)}]
	set __oy1 [expr {min($__ay1, $__hy1)}]
	# PG4/M19c: link at each PROBED M8 VDD row center (lly + width/2) inside the
	# overlap -- Castalia's 53.5+100k centers are the shifted grid. A short run
	# with no probed center in band gets a single mid-overlap link.
	set __nl 0
	foreach __lly $pg4_m8_vdd_llys {
		set __yc [expr {$__lly + $POWER_STRIPE_PATH_WIDTH / 2.0}]
		if {$__yc < $__oy0 || $__yc >= $__oy1} { continue }
		add_shape -net VDD -layer M2 -rect [list $__lx0 [expr {$__yc - 0.15}] $__lx1 [expr {$__yc + 0.15}]] -shape STRIPE -status ROUTED
		lappend __link_rects [list $__lx0 [expr {$__yc - 0.15}] $__lx1 [expr {$__yc + 0.15}]]
		incr __nl
		incr __nlink
	}
	if {$__nl == 0} {
		set __yc [expr {($__oy0 + $__oy1) / 2.0}]
		add_shape -net VDD -layer M2 -rect [list $__lx0 [expr {$__yc - 0.15}] $__lx1 [expr {$__yc + 0.15}]] -shape STRIPE -status ROUTED
		lappend __link_rects [list $__lx0 [expr {$__yc - 0.15}] $__lx1 [expr {$__yc + 0.15}]]
		set __nl 1
		incr __nlink
	}
	plog "PG4: laddered $__key ($__sx) -> [lindex $__best 0] ([format %.2f $__hx]) with $__nl M2 links"
}
plog "### UNL STATUS ### : PG4 ladder remedy -- [llength $__sick] columns linked with $__nlink M2 links"
# NB deliberately NO global secondary-sroute rerun here (a bring-up variant
# "fixed" naked pins by routing 12-um lateral M1 corewires across still-empty
# rows -- guaranteed shorts once placement fills them).
plog "### UNL STATUS ### : PG4 placed $__nstrap M2 secondary strap segments over [llength [array names __colys]] columns ($__nstrap_skip short tap runs waived)"
if {$__nstrap_skip > 100} {
	plog "FATAL (PG4/F1): $__nstrap_skip skipped strap runs -- far more than the documented sub-ram0 sliver class. Aborting."
	exit 1
}

# VPW jumpers: R0 rows have the VSS rail at the cell bottom, MX at the top.
set __njump 0
foreach __i [dbGet -p2 top.insts.cell.name FILLBIASA10TH] {
	set __bx [lindex [dbGet $__i.box] 0]
	if {[pg4_dead_row $__bx]} { continue }
	foreach {__x0 __y0 __x1 __y1} $__bx {}
	if {[dbGet $__i.orient] eq "R0"} {
		add_shape -net VSS -layer M1 -rect [list [expr {$__x0 + 0.15}] [expr {$__y0 + 0.10}] [expr {$__x0 + 0.25}] [expr {$__y0 + 0.35}]] -shape STRIPE -status ROUTED
	} else {
		add_shape -net VSS -layer M1 -rect [list [expr {$__x0 + 0.15}] [expr {$__y0 + 1.65}] [expr {$__x0 + 0.25}] [expr {$__y0 + 1.90}]] -shape STRIPE -status ROUTED
	}
	incr __njump
}
plog "### UNL STATUS ### : PG4 added $__njump VPW->VSS-rail M1 jumpers"

# --- PG4 F1 gate b (VIA-based): a dead finger has no via; a real strap does.
# Every live HEADBUF and FILLBIAS-VNW footprint must carry a VDD sVia; every
# live FILLBIAS-VPW footprint a VSS non-followpin wire or sVia.
proc pg4_has_wire {box wantnet skipfollow} {
	foreach {bx0 by0 bx1 by1} $box {}
	foreach o [dbQuery -area [list [expr {$bx0 - 0.5}] [expr {$by0 - 0.5}] [expr {$bx1 + 0.5}] [expr {$by1 + 0.5}]] -objType sWire] {
		if {[dbGet -e $o.net.name] ne $wantnet} { continue }
		if {$skipfollow && [dbGet -e $o.shape] eq "followpin"} { continue }
		return 1
	}
	return 0
}
set __f1_untouched 0
foreach __i [dbGet -p2 top.insts.cell.name HEADBUF16MA10TH] {
	set __bx [lindex [dbGet $__i.box] 0]
	if {[pg4_dead_row $__bx]} { continue }
	if {![pg4_has_svia $__bx VDD]} {
		incr __f1_untouched
		if {$__f1_untouched <= 5} { plog "PG4 F1: header [dbGet $__i.name] @$__bx has NO VDD via (VDDG unsupplied)" }
	}
}
foreach __i [dbGet -p2 top.insts.cell.name FILLBIASA10TH] {
	set __bx [lindex [dbGet $__i.box] 0]
	if {[pg4_dead_row $__bx]} { continue }
	set __exempt 0
	foreach __sk $__skipped_runs {
		foreach {__skx __sky0 __sky1} $__sk {}
		if {abs([lindex $__bx 0] + 0.10 - $__skx) < 0.35 && [lindex $__bx 1] >= [expr {$__sky0 - 0.5}] && [lindex $__bx 1] <= [expr {$__sky1 + 0.5}]} { set __exempt 1; break }
	}
	if {!$__exempt && ![pg4_has_svia $__bx VDD]} {
		incr __f1_untouched
		if {$__f1_untouched <= 5} { plog "PG4 F1: welltap [dbGet $__i.name] @$__bx has NO VDD via (VNW unstrapped)" }
	}
	if {![pg4_has_wire $__bx VSS 1] && ![pg4_has_svia $__bx VSS]} {
		incr __f1_untouched
		if {$__f1_untouched <= 5} { plog "PG4 F1: welltap [dbGet $__i.name] @$__bx has NO VPW jumper" }
	}
}
plog "### UNL STATUS ### : PG4 F1 gate b -- $__f1_untouched unsupplied pmk secondary-pin footprints (must be 0)"
if {$__f1_untouched > 0} {
	plog "FATAL (PG4/F1): $__f1_untouched pmk cells have no real secondary supply. Saving dbs/pg4gateb_fail.innovus; aborting."
	saveDesign dbs/pg4gateb_fail.innovus
	exit 1
}

# PG4 dangling-stack scrub: at VPW pins under the VSS M7 legs/stripes the FIRST
# secondary sroute leaves floating VIA3..VIA6 stacks (top merged into the M7
# leg, bottom DANGLING at M3 -- no via1/via2 ever placed). The pins themselves
# are supplied by the VPW M1 jumpers, so the stacks are pure litter. Delete
# exactly the {via3..6, no via1/via2/via7} VSS point-groups.
array unset __vgrp
foreach __o [dbGet [dbGet -p top.nets.name VSS].sVias -e] {
	set __vn [dbGet -e $__o.via.name]
	set __k "[format %.2f [dbGet $__o.pt_x]]_[format %.2f [dbGet $__o.pt_y]]"
	lappend __vgrp($__k) [list $__o $__vn]
}
set __nscrub 0
foreach __k [array names __vgrp] {
	set __has12 0; set __has7 0; set __has36 0
	foreach __e $__vgrp($__k) {
		set __vn [lindex $__e 1]
		if {[string match -nocase via1* $__vn] || [string match -nocase via2* $__vn]} { set __has12 1 }
		if {[string match -nocase via7* $__vn]} { set __has7 1 }
		if {[string match -nocase via3* $__vn] || [string match -nocase via4* $__vn] || [string match -nocase via5* $__vn] || [string match -nocase via6* $__vn]} { set __has36 1 }
	}
	if {$__has36 && !$__has12 && !$__has7} {
		foreach __e $__vgrp($__k) { dbDeleteObj [lindex $__e 0]; incr __nscrub }
	}
}
plog "### UNL STATUS ### : PG4 scrubbed $__nscrub dangling VSS stack vias"

# PG4 route blockages over every M2 strap band + ladder link: nanoroute may
# drop a signal VIA2 pad inside a strap band (special wires alone do not fence
# via landing pads). deleteAllRouteBlks after routing removes these too.
set __nblk 0
foreach __pr $__placed_runs {
	foreach {__key __sx __ay0 __ay1} $__pr {}
	createRouteBlk -box [list [expr {$__sx - 0.1}] $__ay0 [expr {$__sx + 0.4}] $__ay1] -layer 2
	incr __nblk
}
foreach __lr $__link_rects {
	foreach {__lx0 __ly0 __lx1 __ly1} $__lr {}
	createRouteBlk -box [list [expr {$__lx0 - 0.1}] [expr {$__ly0 - 0.1}] [expr {$__lx1 + 0.1}] [expr {$__ly1 + 0.1}]] -layer 2
	incr __nblk
}
plog "### UNL STATUS ### : PG4 created $__nblk M2 route blockages over the strap fabric"

# PG4 M7 pad-bridge pass: a strap upstack's M7 landing pads reach to sx+0.41;
# where a SAME-NET M7 stripe/ring edge sits 0.05..1.5 um away the net-blind
# wide-metal union rule fires. One full-run-height M7 rect bridges pad and
# stripe into a single union shape -- additive, same net, M7 is power-only here.
# (Geometry-driven; necessity is floorplan-dependent -- an Argus trial-GDS
# Calibre run decides whether any bridges are actually needed.)
set __nbridge 0
foreach __pr $__placed_runs {
	foreach {__key __sx __ay0 __ay1} $__pr {}
	set __padr [expr {$__sx + 0.41}]
	set __padl [expr {$__sx - 0.11}]
	foreach __o [dbGet [dbGet -p top.nets.name VDD].sWires -e] {
		if {[dbGet -e $__o.layer.name] ne "M7"} { continue }
		set __b [lindex [dbGet $__o.box] 0]
		foreach {__bx0 __by0 __bx1 __by1} $__b {}
		if {[expr {$__by1 - $__by0}] < 100} { continue }
		if {[expr {min($__by1, $__ay1) - max($__by0, $__ay0)}] < 10} { continue }
		set __gapr [expr {$__bx0 - $__padr}]
		set __gapl [expr {$__padl - $__bx1}]
		if {$__gapr > 0.02 && $__gapr < 1.6} {
			add_shape -net VDD -layer M7 -rect [list [expr {$__sx + 0.25}] [expr {max($__ay0, $__by0)}] [expr {$__bx0 + 0.2}] [expr {min($__ay1, $__by1)}]] -shape STRIPE -status ROUTED
			incr __nbridge
		} elseif {$__gapl > 0.02 && $__gapl < 1.6} {
			add_shape -net VDD -layer M7 -rect [list [expr {$__bx1 - 0.2}] [expr {max($__ay0, $__by0)}] [expr {$__sx + 0.05}] [expr {min($__ay1, $__by1)}]] -shape STRIPE -status ROUTED
			incr __nbridge
		}
	}
}
plog "### UNL STATUS ### : PG4 added $__nbridge M7 pad-union bridges"

# PG4 duplicate-VIA1 dedupe: under same-net M7 stripes the FIRST sroute already
# stacked some pins; my strap adds a second VIA1 ~0.1 um away = VIA1 array-
# spacing violations. Keep the strap-centered via of each close pair, delete
# the other.
set __ndd 0
foreach __pr $__placed_runs {
	foreach {__key __sx __ay0 __ay1} $__pr {}
	set __c [expr {$__sx + 0.15}]
	array unset __v1g
	foreach __o [dbQuery -area [list [expr {$__sx - 0.4}] $__ay0 [expr {$__sx + 0.7}] $__ay1] -objType sVia] {
		if {[dbGet -e $__o.net.name] ne "VDD"} { continue }
		if {![string match -nocase via1* [dbGet -e $__o.via.name]]} { continue }
		set __gy [expr {round([dbGet $__o.pt_y] * 2.0) / 2.0}]
		lappend __v1g($__gy) [list $__o [dbGet $__o.pt_x]]
	}
	foreach __gy [array names __v1g] {
		if {[llength $__v1g($__gy)] < 2} { continue }
		set __keep ""
		set __kd 1e9
		foreach __e $__v1g($__gy) {
			set __d [expr {abs([lindex $__e 1] - $__c)}]
			if {$__d < $__kd} { set __kd $__d; set __keep [lindex $__e 0] }
		}
		foreach __e $__v1g($__gy) {
			if {[lindex $__e 0] ne $__keep} { dbDeleteObj [lindex $__e 0]; incr __ndd }
		}
	}
}
plog "### UNL STATUS ### : PG4 deduped $__ndd doubled VIA1s under same-net stripes"
# (Castalia's M7.S.4(b) notch-bend pad-merge patch is NOT ported -- the Argus
# tile is a plain rectangle with no U-notch bend.)

################################################################################
# PG1 F1: ALWAYS-ON GPGBUF repeaters for long SLEEP-chain links (the chains
# that jump over the ram0 macro). An ordinary inverter pair on VDD_SW dies with
# the rail it gates. Splice a GPGBUFX4 (VDDG-powered AO buffer) into every link
# longer than PG1_LINK_THRESH. Runs AFTER the main secondary sroute (a GPGBUF
# present during it trips IMPSR-503 and the whole pass silently does nothing).
################################################################################
printStatus "PG1: splicing GPGBUF AO repeaters into long SLEEP-chain links"
set PG1_LINK_THRESH 150.0
set PG1_NREP 0
foreach np [dbGet -p top.nets.name psoPSI_* -e] {
	set netname [dbGet $np.name]
	set drv ""
	set lds {}
	foreach t [dbGet $np.instTerms.name -e] {
		if {[string match {*/SLEEPOUT} $t]} { set drv $t } \
		elseif {[string match {*/SLEEP} $t]} { lappend lds $t }
	}
	if {$drv eq "" || [llength $lds] != 1} { continue }
	set drvinst [string range $drv 0 [expr {[string last "/" $drv] - 1}]]
	set ldinst  [string range [lindex $lds 0] 0 [expr {[string last "/" [lindex $lds 0]] - 1}]]
	set p1 [lindex [dbGet [dbGet -p top.insts.name $drvinst].pt] 0]
	set p2 [lindex [dbGet [dbGet -p top.insts.name $ldinst].pt]  0]
	set dist [expr {abs([lindex $p1 0] - [lindex $p2 0]) + abs([lindex $p1 1] - [lindex $p2 1])}]
	if {$dist <= $PG1_LINK_THRESH} { continue }
	set repname pgaorep_$PG1_NREP
	set repnet  ${netname}_pg1rep
	puts "PG1: link $netname ($drvinst -> $ldinst) is ${dist}um -- splicing $repname"
	addNet $repnet
	addInst -cell GPGBUFX4MA10TH -inst $repname
	attachTerm $repname A $netname
	attachTerm $repname Y $repnet
	detachTerm $ldinst SLEEP
	attachTerm $ldinst SLEEP $repnet
	dbSet [dbGet -p top.nets.name $repnet].dontTouch true
	incr PG1_NREP
}
puts "### UNL STATUS ### : PG1 spliced $PG1_NREP GPGBUF AO repeaters into the SLEEP chain"
if {$PG1_NREP == 0} {
	puts "WARNING (PG1): no long SLEEP-chain links found -- floorplan changed? Verify the chain."
}
# Freeze the enable chain + macro PG-control nets against opt (dbSet, not
# setAttribute -- -dont_touch is not an option in 20.12; verify it took).
foreach np [dbGet -p top.nets.name psoPSI_* -e] {
	dbSet $np.dontTouch true
}
foreach nn {pd_sleep tcm_pgen tcm_retn} {
	set np [dbGet -p top.nets.name $nn -e]
	if {$np ne ""} { dbSet $np.dontTouch true }
}
set PG1_DT [llength [dbGet -p top.nets.dontTouch true -e]]
puts "### UNL STATUS ### : PG1 dont_touch set on $PG1_DT nets"
if {$PG1_DT == 0} {
	puts "FATAL (PG1): dont_touch did not take on any chain net"
	exit 1
}
if {$PG1_NREP > 0} {
	# PG2-F1: -type pgpin (see the main secondary-pin GNC above).
	globalNetConnect VDD -type pgpin -pin VDDG -inst pgaorep_* -module {} -verbose
	globalNetConnect VSS -type pgpin -pin VSSG -inst pgaorep_* -module {} -verbose
}

verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$OUT_NAME.verifyGeometry.preplace.rpt
fixVia -short
fixVia -minCut
fixVia -minStep

# Reserve M7/M8 for power during signal routing.
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -layer 7
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -layer 8

################################################################################
# Placement
################################################################################
# DEAD-ROW BLOCKAGES -- created HERE (after everything upstream, just before
# place_opt): before addPowerSwitch they shift its checkerboard phase (the
# uncovered rows MOVE); before sroute they suppress the blocked rows' follow-
# pin rails and strand the dead-row well-tap VDD frames. The boxes were
# DETECTED above from the actual switch placement (compact-tile re-derivation).
foreach {b} $dead_row_boxes {
	set nm dead_row_[format %.0f [expr {[lindex $b 1] * 10}]]
	createPlaceBlockage -type hard -name $nm -box $b
}
printStatus "Blocked $NDEAD switchless dead-rail rows (detected)"

place_opt_design
printStatus "Placement done"

# ACCEPTANCE (post-place): no live cell may sit on a dead switchless row.
set park_bad 0
foreach {b} $dead_row_boxes {
	foreach __i [dbQuery -area $b -objType inst -e] {
		set c [dbGet $__i.cell.name]
		# fillers/taps/switches are allowed on a dead row; live logic is not
		if {[string match FILL* $c] || [string match WELLTAP* $c] || [string match HEADBUF* $c] || [string match FILLBIAS* $c]} { continue }
		incr park_bad
		plog "DEAD-ROW VIOLATION: live cell [dbGet $__i.name] ($c) parked on blocked row [lindex $b 1]"
	}
}
if {$park_bad > 0} {
	plog "FATAL (A4): $park_bad live cells on dead switchless rows -- blockage set is wrong"
	exit 1
}
plog "### UNL STATUS ### : dead-row placement acceptance PASSED ($NDEAD rows clean)"

# PG1 F1 / PG4 (M19c port from tcl/hart_tile.innovus.tcl :1050-1321): the
# GPGBUF repeaters were UNPLACED when the secondary-pin sroute ran (it must run
# pre-place for the fixed switches/taps; the repeaters are ordinary movable
# cells that place_opt just legalized) -- hook their AO supply pins now.
# PG4 REPLACES the old per-inst secondaryPowerPin sroute here: on the Castalia
# tile that sroute landed a VSS via pad on pgaorep_2's own Y OUTPUT pin (M1
# short marker; electrically the SLEEP chain pinned low = every switch forced
# awake). The M2 strap recipe below is the whole hookup; the via gate verifies
# it.
if {[info exists PG1_NREP] && $PG1_NREP > 0} {
	printStatus "PG1: strapping the GPGBUF repeaters' secondary AO pins (PG4 M2 straps)"
	# PIN THE REPEATERS FIRST: this stage runs right after place_opt, but the
	# repeaters are ordinary MOVABLE cells -- CTS/optDesign/postRoute-ECO would
	# relocate them AFTER the hand-drawn supply metal exists, stranding it.
	dbSet [dbGet -p top.insts.name pgaorep_*].pStatus fixed
	# addStripe only vias onto special-wire shapes, never onto PIN geometry, so
	# draw the fingers OURSELVES: M1 rects inset 0.01 inside the VDDG/VSSG pin
	# bar outlines -- zero geometry beyond the pin, no short possible. Bars per
	# orient (cell 1.4 x 2.0, LEF R0 coords).
	proc pg4_rep_finger {net inst bar} {
		set bx [lindex [dbGet $inst.box] 0]
		foreach {x0 y0 x1 y1} $bx {}
		set or [dbGet $inst.orient]
		foreach {bx0 by0 bx1 by1} $bar {}
		set w 1.4; set h 2.0
		if {$or eq "MY" || $or eq "R180"} {
			set tx0 [expr {$w - $bx1}]; set tx1 [expr {$w - $bx0}]
		} else { set tx0 $bx0; set tx1 $bx1 }
		if {$or eq "MX" || $or eq "R180"} {
			set ty0 [expr {$h - $by1}]; set ty1 [expr {$h - $by0}]
		} else { set ty0 $by0; set ty1 $by1 }
		add_shape -net $net -layer M1 -rect [list \
			[expr {$x0 + $tx0 + 0.01}] [expr {$y0 + $ty0 + 0.01}] \
			[expr {$x0 + $tx1 - 0.01}] [expr {$y0 + $ty1 - 0.01}]] \
			-shape STRIPE -status ROUTED
	}
	foreach __i [dbGet -p top.insts.name pgaorep_*] {
		pg4_rep_finger VDD $__i {0.37 1.40 0.55 1.74}
		pg4_rep_finger VDD $__i {0.93 1.45 1.10 1.74}
		pg4_rep_finger VSS $__i {0.36 0.265 0.53 0.555}
		pg4_rep_finger VSS $__i {0.93 0.265 1.10 0.59}
	}
	# PG4 F1 repeater supply straps + gate. Give each pgaorep a real M2 mini-
	# strap per supply pin, engine-via'd like the column straps (VIA1 on the pin
	# + stacked vias at the M8-grid crossing). GPGBUFX4 pin bars (LEF): VDDG bar
	# x0+0.37..0.55, VSSG bar x0+0.93..1.10. The strap extends to just past the
	# nearest same-net M8 stripe.
	# PG4/M19c: the nearest M8 stripe lly is DERIVED (pg4_m8_row_above/below off
	# the probe), NOT Castalia's hardcoded base 51.0/60.0 + 50-um pitch, and the
	# FINGER_W/BASE_H U-notch clause is STRIPPED (no notch on the Argus rect).
	proc pg4_rep_strap {net sx y0 y1} {
		global DESIGN_HEIGHT DESIGN_WIDTH pg4_m8_vdd_llys pg4_m8_vss_llys
		set __llyup [pg4_m8_row_above $net [expr {$y1 + 2}]]
		set __llydn [pg4_m8_row_below $net [expr {$y0 - 8}]]
		set yup [expr {$__llyup eq "" ? 1e9 : $__llyup + 6.0}]
		set ydn [expr {$__llydn eq "" ? -1e9 : $__llydn - 1.0}]
		set ram [lindex [dbGet [dbGet -p top.insts.name ram0].box] 0]
		foreach {rx0 ry0 rx1 ry1} $ram {}
		set upok 1
		if {$__llyup eq "" || $yup > [expr {$DESIGN_HEIGHT - 2}]} { set upok 0 }
		if {$sx > [expr {$rx0 - 1}] && $sx < [expr {$rx1 + 1}] && $y1 < $ry1 && $yup > $ry0} { set upok 0 }
		# (Castalia's FINGER_W/BASE_H notch clause STRIPPED -- Argus has no notch.)
		if {$upok} {
			set ay0 [expr {$y0 - 0.2}]
			set ay1 $yup
		} else {
			if {$__llydn eq ""} {
				plog "FATAL (PG4/F1): repeater strap at x=$sx net $net has no same-net M8 row above OR below. Aborting."
				exit 1
			}
			set ay0 $ydn
			set ay1 [expr {$y1 + 0.2}]
			if {$sx > [expr {$rx0 - 1}] && $sx < [expr {$rx1 + 1}] && $y0 > $ry0 && $ay0 < $ry1} {
				plog "FATAL (PG4/F1): repeater strap at x=$sx has no clean path to an M8 $net stripe. Aborting."
				exit 1
			}
		}
		# a different-net M2 strap (tap/header column) in this band = short:
		# report failure so the caller can try the pin's OTHER bar. window =
		# band + the 0.1 um M2 min spacing EXACTLY (a 0.15 margin false-flags a
		# legal 0.13 gap).
		foreach __o [dbQuery -area [list [expr {$sx - 0.099}] $ay0 [expr {$sx + 0.399}] $ay1] -objType sWire] {
			if {[dbGet -e $__o.layer.name] eq "M2" && [dbGet -e $__o.net.name] ne $net} {
				plog "PG4: repeater $net strap band at x=$sx collides with an M2 [dbGet -e $__o.net.name] strap -- trying the alternate bar"
				return 0
			}
		}
		addStripe -layer M2 -nets [list $net] -direction vertical -width 0.3 \
			-set_to_set_distance 1000 -start_offset 0.2 -stop_offset 0.05 \
			-area [list [expr {$sx - 0.2}] $ay0 [expr {$sx + 0.5}] $ay1]
		return 1
	}
	setAddStripeMode -reset
	setAddStripeMode \
		-stacked_via_top_layer M8 \
		-stacked_via_bottom_layer M1 \
		-extend_to_closest_target none
	set __rep_vdd_band [dict create]
	set __rep_railjump {}
	foreach __i [dbGet -p top.insts.name pgaorep_*] {
		set __bx [lindex [dbGet $__i.box] 0]
		foreach {__x0 __y0 __x1 __y1} $__bx {}
		set __or [dbGet $__i.orient]
		# GPGBUFX4 has TWO mirrored vertical bars per supply pin. Try each
		# candidate bar; skip any whose band would touch a column strap of the
		# other net or the band already claimed for this repeater's other supply.
		if {$__or eq "R0" || $__or eq "MX"} {
			set __vddc {0.37 0.80}
			set __vssc {0.80 0.30}
		} elseif {$__or eq "MY" || $__or eq "R180"} {
			set __vddc {0.73 0.30}
			set __vssc {0.30 0.77}
		} else {
			plog "FATAL (PG4/F1): repeater [dbGet $__i.name] orient $__or unsupported by the strap recipe. Aborting."
			exit 1
		}
		set __vdd_band ""
		foreach __c $__vddc {
			if {[pg4_rep_strap VDD [expr {$__x0 + $__c}] $__y0 $__y1]} { set __vdd_band $__c; break }
		}
		dict set __rep_vdd_band [dbGet $__i.name] $__vdd_band
		if {$__vdd_band eq ""} {
			plog "FATAL (PG4/F1): no collision-free VDD bar for repeater [dbGet $__i.name]. Aborting."
			saveDesign dbs/pg4rep_fail.innovus
			exit 1
		}
		set __vss_done 0
		foreach __c $__vssc {
			if {abs($__c - $__vdd_band) < 0.4} { continue }
			if {[pg4_rep_strap VSS [expr {$__x0 + $__c}] $__y0 $__y1]} { set __vss_done 1; break }
		}
		if {!$__vss_done} {
			# M19c FALLBACK (ported from hart_tile.innovus.tcl — see the
			# rationale there): VSSG via in-cell M1 rail jumper when both
			# M2 bands collide (ground is unswitched; the cell's own VSS
			# rail pin sits 0.115 um below the VSSG bar, no foreign M1
			# between, per the USEfix LEF). VDD collision stays FATAL
			# (row rails are VDD_SW — must never touch VDDG).
			if {$__or eq "MY" || $__or eq "R180"} {
				set __jx0 [expr {$__x0 + 1.4 - 0.53}]
				set __jx1 [expr {$__x0 + 1.4 - 0.36}]
			} else {
				set __jx0 [expr {$__x0 + 0.36}]
				set __jx1 [expr {$__x0 + 0.53}]
			}
			if {$__or eq "MX" || $__or eq "R180"} {
				set __jy0 [expr {$__y1 - 0.45}]
				set __jy1 [expr {$__y1 + 0.10}]
			} else {
				set __jy0 [expr {$__y0 - 0.10}]
				set __jy1 [expr {$__y0 + 0.45}]
			}
			add_shape -net VSS -layer M1 -rect [list $__jx0 $__jy0 $__jx1 $__jy1] -shape STRIPE -status ROUTED
			plog "PG4/M19c: repeater [dbGet $__i.name] VSSG hooked via RAIL JUMPER at x=$__jx0 (both M2 bands collide)"
			lappend __rep_railjump [dbGet $__i.name]
			set __vss_done 1
		}
	}
	# VDDG via: the finger (M1, in-pin) and the strap (M2) OVERLAP in plan on
	# the chosen band, so the ENGINE can via them: per-repeater editPowerVia
	# M1->M2, tightly windowed to the cell bbox +0.5. VSSG needs nothing extra
	# (the VSS strap crosses the VSS rails and the engine already vias those).
	# -orthogonal_only 0: finger and strap are both VERTICAL.
	foreach __i [dbGet -p top.insts.name pgaorep_*] {
		set __bx [lindex [dbGet $__i.box] 0]
		foreach {__rx0 __ry0 __rx1 __ry1} $__bx {}
		editPowerVia -add_vias 1 -nets VDD -bottom_layer M1 -top_layer M2 -orthogonal_only 0 \
			-area [list [expr {$__rx0 - 0.5}] [expr {$__ry0 - 0.5}] [expr {$__rx1 + 0.5}] [expr {$__ry1 + 0.5}]]
	}
	set __rep_bad 0
	foreach __i [dbGet -p top.insts.name pgaorep_*] {
		set __bx [lindex [dbGet $__i.box] 0]
		if {![pg4_has_svia $__bx VDD]} {
			incr __rep_bad
			plog "PG4 F1: repeater [dbGet $__i.name] @$__bx has NO VDD via (VDDG unsupplied)"
		}
		if {[lsearch -exact $__rep_railjump [dbGet $__i.name]] >= 0} {
			# M19c: VSSG hooked by the M1 rail jumper — no via exists by
			# design; verify the jumper WIRE instead (non-followpin M1).
			if {![pg4_has_wire $__bx VSS 1]} {
				incr __rep_bad
				plog "PG4 F1: repeater [dbGet $__i.name] @$__bx rail jumper MISSING (VSSG unsupplied)"
			}
		} elseif {![pg4_has_svia $__bx VSS]} {
			incr __rep_bad
			plog "PG4 F1: repeater [dbGet $__i.name] @$__bx has NO VSS via (VSSG unsupplied)"
		}
	}
	if {$__rep_bad > 0} {
		plog "FATAL (PG4/F1): $__rep_bad GPGBUF repeater supply pins unsupplied -- dead AO repeaters re-break the SLEEP chain. Saving dbs/pg4rep_fail.innovus; aborting."
		saveDesign dbs/pg4rep_fail.innovus
		exit 1
	}
	plog "### UNL STATUS ### : PG4 F1 repeater gate -- all GPGBUF AO supplies via'd"
	# PG4/F2b: the repeater VDDG strap is an ISLAND unless it happens to catch
	# an engine stack. Deterministic grid hop: one horizontal SAME-LAYER M2 link
	# from each repeater strap to the nearest main strap column with y-overlap
	# (touching same-net metal, no vias -- the proven ladder mechanism; the main
	# columns are grid-connected by the post-route strap-grid repair).
	foreach __i [dbGet -p top.insts.name pgaorep_*] {
		set __bx [lindex [dbGet $__i.box] 0]
		foreach {__rx0 __ry0 __rx1 __ry1} $__bx {}
		# the repeater's OWN strap piece: M2 VDD that x-OVERLAPS the cell bbox,
		# 4-60 um tall (x-overlap + the height ceiling exclude main columns).
		set __sp ""
		foreach __o [dbQuery -area [list [expr {$__rx0 - 2.0}] [expr {$__ry0 - 60.0}] [expr {$__rx1 + 2.0}] [expr {$__ry1 + 60.0}]] -objType sWire] {
			if {[dbGet -e $__o.layer.name] ne "M2" || [dbGet -e $__o.net.name] ne "VDD"} { continue }
			set __b2 [lindex [dbGet $__o.box] 0]
			foreach {__px0 __py0 __px1 __py1} $__b2 {}
			set __h [expr {$__py1 - $__py0}]
			if {$__h < 4.0 || $__h > 60.0} { continue }
			if {$__px1 < $__rx0 || $__px0 > $__rx1} { continue }
			set __sp $__b2
			break
		}
		if {$__sp eq ""} {
			plog "FATAL (PG4/F2b): repeater [dbGet $__i.name] has no VDDG M2 strap piece to link. Saving dbs/pg4rep_fail.innovus; aborting."
			saveDesign dbs/pg4rep_fail.innovus
			exit 1
		}
		foreach {__px0 __py0 __px1 __py1} $__sp {}
		# nearest main strap column whose ACTUAL METAL y-overlaps the repeater
		# strap -- try EVERY overlapping column in distance order until one
		# yields a clear link y.
		set __cands {}
		foreach __pr $__placed_runs {
			foreach {__key __msx __may0 __may1} $__pr {}
			if {$__may0 > [expr {$__py1 - 1.0}] || $__may1 < [expr {$__py0 + 1.0}]} { continue }
			set __d [expr {abs($__msx - $__px0)}]
			if {$__d < 0.5 || $__d > 30.0} { continue }
			foreach __o [dbQuery -area [list [expr {$__msx + 0.05}] $__may0 [expr {$__msx + 0.25}] $__may1] -objType sWire] {
				if {[dbGet -e $__o.layer.name] ne "M2" || [dbGet -e $__o.net.name] ne "VDD"} { continue }
				set __b3 [lindex [dbGet $__o.box] 0]
				foreach {__qx0 __qy0 __qx1 __qy1} $__b3 {}
				if {[expr {$__qy1 - $__qy0}] < 4.0} { continue }
				set __ov [expr {min($__py1, $__qy1) - max($__py0, $__qy0)}]
				if {$__ov < 1.5} { continue }
				lappend __cands [list $__d $__msx $__qy0 $__qy1]
				break
			}
		}
		set __cands [lsort -real -index 0 $__cands]
		set __ly ""; set __best ""
		foreach __cand $__cands {
			foreach {__d __msx __qy0 __qy1} $__cand {}
			set __clx0 [expr {min($__px0, $__msx)}]
			set __clx1 [expr {max($__px1, $__msx + 0.3)}]
			# clearance margin = M2 narrow min-space 0.10 exactly (the VSS twin
			# sits at a LEGAL 0.13 gap; a fat margin blocks every candidate y).
			set __sc0 [expr {max($__py0, $__qy0) + 0.5}]
			set __sc1 [expr {min($__py1, $__qy1) - 0.8}]
			for {set __cy $__sc0} {$__cy < $__sc1} {set __cy [expr {$__cy + 1.0}]} {
				set __ok 1
				foreach __o [concat [dbQuery -area [list [expr {$__clx0 - 0.10}] [expr {$__cy - 0.10}] [expr {$__clx1 + 0.10}] [expr {$__cy + 0.40}]] -objType sWire] [dbQuery -area [list [expr {$__clx0 - 0.10}] [expr {$__cy - 0.10}] [expr {$__clx1 + 0.10}] [expr {$__cy + 0.40}]] -objType wire]] {
					if {[dbGet -e $__o.layer.name] ne "M2"} { continue }
					if {[dbGet -e $__o.net.name] eq "VDD"} { continue }
					set __ok 0; break
				}
				if {$__ok} { set __ly $__cy; break }
			}
			if {$__ly ne ""} { set __best $__msx; set __lx0 $__clx0; set __lx1 $__clx1; break }
		}
		if {$__ly eq ""} {
			plog "FATAL (PG4/F2b): no clear link y to any main strap column for repeater [dbGet $__i.name] ([llength $__cands] candidates tried). Saving dbs/pg4rep_fail.innovus; aborting."
			saveDesign dbs/pg4rep_fail.innovus
			exit 1
		}
		add_shape -net VDD -layer M2 -rect [list $__lx0 $__ly $__lx1 [expr {$__ly + 0.3}]] -shape STRIPE -status ROUTED
		createRouteBlk -box [list [expr {$__lx0 - 0.1}] [expr {$__ly - 0.1}] [expr {$__lx1 + 0.1}] [expr {$__ly + 0.4}]] -layer 2
		plog "PG4/F2b: linked repeater [dbGet $__i.name] strap to main column x=$__best (link y=$__ly, span $__lx0-$__lx1)"
	}
	# fence the repeater straps from the router like the column straps
	foreach __i [dbGet -p top.insts.name pgaorep_*] {
		set __bx [lindex [dbGet $__i.box] 0]
		foreach {__x0 __y0 __x1 __y1} $__bx {}
		createRouteBlk -box [list [expr {$__x0 - 0.1}] [expr {$__y0 - 60.0}] [expr {$__x1 + 0.1}] [expr {$__y1 + 60.0}]] -layer 2
	}
}

################################################################################
# Clock tree synthesis (mclk from clk; clk_cpu a generated clock through
# vesta's ClkGate -- ccopt traces it)
################################################################################
add_ndr -name CTS_2W2S -width {M2:M6 0.4} -generate_via -spacing {M2:M6 0.42}
add_ndr -name CTS_2W1S -width {M2:M6 0.4} -generate_via -spacing {M2:M6 0.21}

create_route_type -name top_rule   -non_default_rule CTS_2W2S -top_preferred_layer M6 -bottom_preferred_layer M5 -shield_net VSS -bottom_shield_layer M5
create_route_type -name trunk_rule -non_default_rule CTS_2W2S -top_preferred_layer M4 -bottom_preferred_layer M3 -shield_net VSS -bottom_shield_layer M3
create_route_type -name leaf_rule  -non_default_rule CTS_2W1S -top_preferred_layer M3 -bottom_preferred_layer M2

set_ccopt_property -net_type top   route_type top_rule
set_ccopt_property -net_type trunk route_type trunk_rule
set_ccopt_property -net_type leaf  route_type leaf_rule
set_ccopt_property routing_top_min_fanout 10000

set_ccopt_property buffer_cells   {BUFX0P7BA10TH BUFX0P8BA10TH BUFX11BA10TH BUFX13BA10TH BUFX16BA10TH BUFX1BA10TH BUFX1P2BA10TH BUFX1P4BA10TH BUFX1P7BA10TH BUFX2BA10TH BUFX2P5BA10TH BUFX3BA10TH BUFX3P5BA10TH BUFX4BA10TH BUFX5BA10TH BUFX6BA10TH BUFX7P5BA10TH BUFX9BA10TH}
set_ccopt_property inverter_cells {INVX0P5BA10TH INVX0P6BA10TH INVX0P7BA10TH INVX0P8BA10TH INVX11BA10TH INVX13BA10TH INVX16BA10TH INVX1BA10TH INVX1P2BA10TH INVX1P4BA10TH INVX1P7BA10TH INVX2BA10TH INVX2P5BA10TH INVX3BA10TH INVX3P5BA10TH INVX4BA10TH INVX5BA10TH INVX6BA10TH INVX7P5BA10TH INVX9BA10TH}
set_ccopt_property delay_cells    {DLY2X0P5MA10TH DLY4X0P5MA10TH}
set_ccopt_property use_inverters true
set_ccopt_property target_max_trans 400ps

create_ccopt_clock_tree_spec
ccopt_design
optDesign -postCTS -hold
# Full report_power (leakage + dynamic, statistical activity) beside the
# leakage-only report optDesign writes implicitly; OUT_NAME-prefixed so the
# Castalia tile flow's files are not clobbered (both designs are hart_tile).
# Consumed by tools/python/gen_power_dashboard.py.
catch {report_power -outfile $REPORT_DIR/${OUT_NAME}_postCTS_full.power}
timeDesign -postCTS -expandedViews -outDir $REPORT_DIR/$OUT_NAME.timeDesign.postcts
report_ccopt_clock_trees -file $REPORT_DIR/$OUT_NAME.report_ccopt_clock_trees.postcts
report_ccopt_skew_groups -file $REPORT_DIR/$OUT_NAME.report_ccopt_skew_groups.postcts
printStatus "CTS done"

################################################################################
# Signal routing
################################################################################
printStatus "Running nanoroute"
setNanoRouteMode \
    -routeTopRoutingLayer 7 \
    -envNumberFailLimit 10 \
    -droutePostRouteSwapVia multiCut \
    -drouteUseMultiCutViaEffort medium \
    -routeAllowPowerGroundPin true \
    -drouteFixAntenna true \
    -routeAntennaCellName "ANTENNA2A10TH" \
    -routeInsertAntennaDiode true \
    -routeInsertDiodeForClockNets true \
    -routeIgnoreAntennaTopCellPin false \
    -routeFixTopLayerAntenna false \
    -drouteAntennaEcoListFile $REPORT_DIR/$OUT_NAME.routeDesign.diodes.txt \
    -dbSkipAnalog true \
    -drouteEndIteration default
routeDesign

optDesign -postRoute -setup -hold
# Full post-route power (see postCTS note)
catch {report_power -outfile $REPORT_DIR/${OUT_NAME}_postRoute_full.power}

verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$OUT_NAME.verifyGeometry.postroute.rpt
ecoRoute -fix_drc
verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$OUT_NAME.verifyGeometry.postroute.rpt

deleteAllRouteBlks
addFiller

# M17b: scrub the detected dead-rail rows BARE before signoff. Blockages kept
# logic out, but addWellTap left FILLBIAS taps on them and the dead VDD_SW rail
# stubs flag as zero-area antenna markers + dangling wires once nothing abuts.
# Delete leftover insts on each dead row first, then the rail stub (deleting
# the rail out from under a FILLBIAS re-strands its net-tied VDD frame).
foreach {b} $dead_row_boxes {
	set ry [lindex $b 1]
	set y0 [expr {$ry + 0.2}]
	set y1 [expr {$ry + $ROW_H - 0.2}]
	foreach __i [dbQuery -area [list 0 $y0 $DESIGN_WIDTH $y1] -objType inst -e] {
		set iy [dbGet $__i.pt_y]
		if {$iy >= $ry - 0.1 && $iy <= $ry + 0.1} { deleteInst [dbGet $__i.name] }
	}
	editDelete -net VDD_SW -area [list 0 [expr {$ry + 0.1}] $DESIGN_WIDTH [expr {$ry + $ROW_H - 0.1}]]
}
# Scrub the CORNER BOX bare too (A8): it holds no live logic (tcm_corner blockage
# + cutRow) so any VDD_SW follow-pin rails there are dead stubs, plus any stray
# FILL/tap addStripe/sroute re-fractured into the cut rows. CRITICAL: limit the
# scrub to x < TCM_BLK_X1 so the LIVE right-strip L-arm (x >= TCM_BLK_X1) is
# untouched. Delete corner insts (except the TCM macro) then the dead VDD_SW
# rails; VDD (ram0) + signal routes in the channels beside the TCM are untouched.
foreach __i [dbQuery -area [list 0 1 $TCM_BLK_X1 [expr {$TCM_BLK_Y1 - 0.1}]] -objType inst -e] {
	set c [dbGet $__i.cell.name]
	if {$c eq "sram1p16k_hvt_pg"} { continue }
	if {[string match FILL* $c] || [string match WELLTAP* $c] || [string match FILLBIAS* $c]} {
		deleteInst [dbGet $__i.name]
	}
}
editDelete -net VDD_SW -area [list 0 1 $TCM_BLK_X1 [expr {$TCM_BLK_Y1 - 0.1}]]
printStatus "Scrubbed $NDEAD dead rows + the corner box bare"

################################################################################
# PG4 STRAP->GRID LINK REPAIR (M19c port from tcl/hart_tile.innovus.tcl
# :1428-1500). Runs post-route (the M8-crossing via3..7 stacks are only fully
# populated late in the flow). The engine's M8-crossing stacks START AT M3
# (via3..7 -- no via1/2 at the crossings), so every M2 strap column is an
# ISLAND: pin-connected below, never grid-connected above. VDD has NO rails
# (rows carry VSS/VDD_SW only) -- the crossing stack is a VDD column's ONLY
# feed. Lay a small REAL M3 rect at each isolated via3 point on a strap, then
# ONE global editPowerVia M2->M3 -- the engine vias every strap/M3-rect
# overlap. (`add_via` specials are GDS-phantoms on this install -- engine vias
# stream, add_via does not.) ADDITIVE ONLY; clearance-checked against non-VDD
# M3; a skipped crossing is fine -- a column needs only ONE live crossing.
################################################################################
# M19c: re-baseline from first Argus run -- Castalia expected ~2000 VIA2s on a
# 660x1050 U-tile; the Argus rect has fewer strap columns + the row-free band,
# so scale the floor to 300. RESET from the first real Argus harden's count.
set PG4_STRAPGRID_VIA2_MIN 200  ;# A8 re-baselined: 520x522 corner-TCM run measured 357 (was 405x685=537); floor ~56%
set __ngshape 0
set __ngblock 0
set __ngskip 0
array unset __v12pt
array unset __v3pt
foreach __o [dbGet [dbGet -p top.nets.name VDD].sVias -e] {
	set __vn [string tolower [dbGet -e $__o.via.name]]
	set __k "[format %.2f [dbGet $__o.pt_x]]_[format %.2f [dbGet $__o.pt_y]]"
	if {[string match via1* $__vn] || [string match via2* $__vn]} { set __v12pt($__k) 1 }
	if {[string match via3* $__vn]} { set __v3pt($__k) 1 }
}
set __npre2 0
foreach __o [dbGet [dbGet -p top.nets.name VDD].sVias -e] {
	if {[dbGet -e $__o.via.cutLayer.name] eq "VIA2"} { incr __npre2 }
}
foreach __k [array names __v3pt] {
	if {[info exists __v12pt($__k)]} { continue }
	foreach {__gvx __gvy} [split $__k _] {}
	set __onstrap 0
	foreach __o [dbQuery -area [list [expr {$__gvx - 0.05}] [expr {$__gvy - 0.05}] [expr {$__gvx + 0.05}] [expr {$__gvy + 0.05}]] -objType sWire] {
		if {[dbGet -e $__o.layer.name] eq "M2" && [dbGet -e $__o.net.name] eq "VDD"} { set __onstrap 1; break }
	}
	if {!$__onstrap} { incr __ngskip; continue }
	set __r [list [expr {$__gvx - 0.10}] [expr {$__gvy - 0.04}] [expr {$__gvx + 0.10}] [expr {$__gvy + 0.04}]]
	set __chk [list [expr {$__gvx - 0.201}] [expr {$__gvy - 0.141}] [expr {$__gvx + 0.201}] [expr {$__gvy + 0.141}]]
	set __clear 1
	foreach __o [concat [dbQuery -area $__chk -objType wire] [dbQuery -area $__chk -objType sWire]] {
		if {[dbGet -e $__o.layer.name] ne "M3"} { continue }
		if {[dbGet -e $__o.net.name] eq "VDD"} { continue }
		set __clear 0; break
	}
	if {!$__clear} { incr __ngblock; continue }
	add_shape -net VDD -layer M3 -rect $__r -shape STRIPE -status ROUTED
	incr __ngshape
}
editPowerVia -add_vias 1 -nets VDD -bottom_layer M2 -top_layer M3 -orthogonal_only 0
set __npost2 0
foreach __o [dbGet [dbGet -p top.nets.name VDD].sVias -e] {
	if {[dbGet -e $__o.via.cutLayer.name] eq "VIA2"} { incr __npost2 }
}
set __nglink [expr {$__npost2 - $__npre2}]
plog "### UNL STATUS ### : PG4 strap-grid link repair -- $__ngshape M3 pads laid ($__ngblock blocked by foreign M3, $__ngskip off-strap), engine created $__nglink VIA2s (min $PG4_STRAPGRID_VIA2_MIN)"
if {$__nglink < $PG4_STRAPGRID_VIA2_MIN} {
	plog "FATAL (PG4/F1): strap-grid link repair created only $__nglink VIA2s (min $PG4_STRAPGRID_VIA2_MIN) -- the crossing-stack population or the editPowerVia mechanism changed. Saving dbs/pg4link_fail.innovus; aborting."
	saveDesign dbs/pg4link_fail.innovus
	exit 1
}

################################################################################
# PG4/F2 (M19c port from tcl/hart_tile.innovus.tcl :1502-1686) -- strap-PIN
# link repair: the missing LAST HOP of the F1 fabric. The strap-grid repair
# above connects every strap UP to the M8 grid, but nothing connected the
# straps DOWN to the pins (the fabric-stage addStripe VIA1s do not survive to
# the final DB/GDS). Per-column windowed editPowerVia M1->M2: the engine vias
# every sroute FINGER (M1 sWire on the pin) x strap (M2) overlap. Tap columns
# need a REAL M1 pad on each FILLBIAS VNW pin bar first (pin geometry is
# invisible to editPowerVia); orientation-aware (R0/MY vs MX/R180 -- a full-
# height pad would short the VPW bar at the same x). Runs HERE (post-route,
# after the dead-row scrub) so no later stage can orphan the vias. ADDITIVE.
################################################################################
proc pg4_count_via1 {x0 y0 x1 y1} {
	set n 0
	foreach o [dbQuery -area [list $x0 $y0 $x1 $y1] -objType sVia] {
		if {[dbGet -e $o.net.name] ne "VDD"} { continue }
		if {[string match -nocase via1* [dbGet -e $o.via.name]]} { incr n }
	}
	return $n
}
# M19c: re-baseline from first Argus run -- Castalia expected ~977 headers +
# ~700 taps = 1400 covered cells on the U-tile; the Argus rect has fewer of
# each, so scale the floor to 400. RESET from the first real Argus harden.
set PG4_F2_COVERED_MIN 1900  ;# A8 re-baselined: 520x522 corner-TCM run measured 3471 (was 405x685=2782); floor ~55%
set __f2vias 0
set __f2covered 0
set __f2waived {}
foreach __pr $__placed_runs {
	foreach {__key __sx __ay0 __ay1} $__pr {}
	set __x0 [string range $__key 1 end]
	set __isH [expr {[string index $__key 0] eq "H"}]
	set __cells {}
	foreach __y $__colys($__key) {
		if {$__y >= [expr {$__ay0 - 1.5}] && $__y <= $__ay1} { lappend __cells $__y }
	}
	set __ncell [llength $__cells]
	if {$__ncell == 0} { continue }
	if {!$__isH} {
		foreach __i [dbGet -p2 top.insts.cell.name FILLBIASA10TH] {
			set __bx [lindex [dbGet $__i.box] 0]
			foreach {__ix0 __iy0 __ix1 __iy1} $__bx {}
			if {abs($__ix0 - $__x0) > 0.01} { continue }
			if {$__iy0 < [expr {$__ay0 - 1.5}] || $__iy0 > $__ay1} { continue }
			if {[pg4_dead_row $__bx]} { continue }
			set __or [dbGet $__i.orient]
			if {$__or eq "R0" || $__or eq "MY"} {
				set __py0 [expr {$__iy0 + 1.21}]; set __py1 [expr {$__iy0 + 1.73}]
			} else {
				set __py0 [expr {$__iy0 + 0.27}]; set __py1 [expr {$__iy0 + 0.79}]
			}
			add_shape -net VDD -layer M1 -shape STRIPE -status ROUTED \
				-rect [list [expr {$__ix0 + 0.15}] $__py0 [expr {$__ix0 + 0.25}] $__py1]
		}
	}
	set __w0 [expr {$__sx - 0.5}]
	set __w1 [expr {$__sx + 0.9}]
	set __b [pg4_count_via1 $__w0 $__ay0 $__w1 $__ay1]
	editPowerVia -add_vias 1 -nets VDD -bottom_layer M1 -top_layer M2 \
		-orthogonal_only 0 -area [list $__w0 $__ay0 $__w1 $__ay1]
	set __a [pg4_count_via1 $__w0 $__ay0 $__w1 $__ay1]
	incr __f2vias [expr {$__a - $__b}]
	# Gate = ABSOLUTE per-cell coverage in the STRAP x-sliver, not the pass
	# delta (fabric-stage via1s survive at seed-dependent spots).
	set __cellh [expr {$__isH ? 4.1 : 2.1}]
	foreach __y $__cells {
		set __nc [pg4_count_via1 [expr {$__sx - 0.1}] [expr {$__y - 0.1}] [expr {$__sx + 0.4}] [expr {$__y + $__cellh}]]
		if {$__nc >= 1} { incr __f2covered; continue }
		if {$__isH} {
			plog "FATAL (PG4/F2): header $__key y=$__y has no strap-pin via1 in the strap sliver. Saving dbs/pg4f2_fail.innovus; aborting."
			saveDesign dbs/pg4f2_fail.innovus
			exit 1
		}
		lappend __f2waived [list $__key $__sx $__y]
	}
}
# --- PG4/F2g: DRC cleanup on the F2 metal.
# (b) DOUBLE-column zones (a tap strap TOUCHING a header strap): the two pieces
#     start/end at different y, so the first/last finger reaches only ONE of
#     them = a single-via connection beside the merged plate -> VIA1.R.4. Align
#     both pieces to the pair's y-envelope and re-run the via pass there.
set __npairfix 0
for {set __ii 0} {$__ii < [llength $__placed_runs]} {incr __ii} {
	for {set __jj [expr {$__ii + 1}]} {$__jj < [llength $__placed_runs]} {incr __jj} {
		foreach {__ka __sxa __ay0a __ay1a} [lindex $__placed_runs $__ii] {}
		foreach {__kb __sxb __ay0b __ay1b} [lindex $__placed_runs $__jj] {}
		if {[expr {abs($__sxa - $__sxb)}] > 0.35} { continue }
		set __oy0 [expr {max($__ay0a, $__ay0b)}]
		set __oy1 [expr {min($__ay1a, $__ay1b)}]
		if {[expr {$__oy1 - $__oy0}] < 4.0} { continue }
		# each strap's OWN piece: must CONTAIN its strap centerline (a thin
		# window partial-overlaps the PARTNER's piece too and dbQuery order is
		# arbitrary).
		set __pa ""; set __pb ""
		foreach __pp [list a b] {
			set __psx [expr {$__pp eq "a" ? $__sxa : $__sxb}]
			set __ctr [expr {$__psx + 0.15}]
			foreach __o [dbQuery -area [list [expr {$__psx + 0.05}] $__oy0 [expr {$__psx + 0.25}] $__oy1] -objType sWire] {
				if {[dbGet -e $__o.layer.name] ne "M2" || [dbGet -e $__o.net.name] ne "VDD"} { continue }
				set __b [lindex [dbGet $__o.box] 0]
				if {[expr {[lindex $__b 3] - [lindex $__b 1]}] < 4.0} { continue }
				if {[lindex $__b 0] > $__ctr || [lindex $__b 2] < $__ctr} { continue }
				if {$__pp eq "a"} { set __pa $__b } else { set __pb $__b }
				break
			}
		}
		if {$__pa eq "" || $__pb eq ""} { continue }
		set __ey0 [expr {min([lindex $__pa 1], [lindex $__pb 1])}]
		set __ey1 [expr {max([lindex $__pa 3], [lindex $__pb 3])}]
		foreach __pp [list [list $__sxa $__pa] [list $__sxb $__pb]] {
			foreach {__psx __pbx} $__pp {}
			if {[lindex $__pbx 1] > [expr {$__ey0 + 0.01}]} {
				add_shape -net VDD -layer M2 -shape STRIPE -status ROUTED \
					-rect [list $__psx $__ey0 [expr {$__psx + 0.3}] [expr {[lindex $__pbx 1] + 0.1}]]
			}
			if {[lindex $__pbx 3] < [expr {$__ey1 - 0.01}]} {
				add_shape -net VDD -layer M2 -shape STRIPE -status ROUTED \
					-rect [list $__psx [expr {[lindex $__pbx 3] - 0.1}] [expr {$__psx + 0.3}] $__ey1]
			}
		}
		editPowerVia -add_vias 1 -nets VDD -bottom_layer M1 -top_layer M2 \
			-orthogonal_only 0 -area [list [expr {min($__sxa, $__sxb) - 0.5}] $__ey0 [expr {max($__sxa, $__sxb) + 0.9}] $__ey1]
		incr __npairfix
	}
}
# CAP POST-MORTEM (F2i): never patch DRC classes with blind per-object
# decorations -- 304 per-via "pad-overhang caps" here once made 600 G.4 markers.
# Prove each patch shape on a trial GDS (restore -> add_shape -> streamOut ->
# strmin -> blockdrc).
#
# (c) Castalia's PROVEN hardcoded patch set (trial-GDS Calibre iterations, the
# x=193.1/433.1 add_shapes + the 433.x stub via1 delete/regenerate) is
# CASTALIA-ONLY and is OMITTED on the first Argus cut -- those coordinates are
# specific to the U-tile's two double-column bottom stubs. An Argus trial-GDS
# Calibre run (restore -> streamOut -> strmin -> blockdrc) must decide whether
# equivalent per-coordinate patches are needed here; regenerate from that run.
plog "### UNL STATUS ### : PG4/F2g DRC cleanup -- $__npairfix double-column zones aligned+re-via'd (Castalia hardcoded x=193.1/433.1 patch set OMITTED -- Argus trial-GDS Calibre decides)"
plog "### UNL STATUS ### : PG4/F2 strap-pin link repair -- $__f2vias via1s created this pass, $__f2covered cells strap-covered, [llength $__f2waived] taps naked (first 10: [lrange $__f2waived 0 9])"
if {$__f2covered < $PG4_F2_COVERED_MIN} {
	plog "FATAL (PG4/F2): only $__f2covered strap-covered cells (min $PG4_F2_COVERED_MIN). Saving dbs/pg4f2_fail.innovus; aborting."
	saveDesign dbs/pg4f2_fail.innovus
	exit 1
}

################################################################################
# PG1 acceptance gate -- the hard check behind the dont_touch:
# 1. every SLEEP-chain net carries ONLY HEADBUF switch pins + GPGBUF AO-repeater
#    pins (one PD_GATED core cell silently un-gates a column tail);
# 2. ram0 PGEN/RETN driven straight from the tcm_pgen/tcm_retn AO ports.
# FAILS THE RUN on violation.
################################################################################
printStatus "PG1 acceptance gate"
set pg1_bad 0
foreach np [concat [dbGet -p top.nets.name psoPSI_* -e] [dbGet -p top.nets.name *_pg1rep -e] [dbGet -p top.nets.name pd_sleep -e]] {
	foreach it [dbGet $np.instTerms -e] {
		set c [dbGet $it.inst.cell.name]
		if {![string match HEADBUF* $c] && ![string match GPGBUF* $c]} {
			incr pg1_bad
			puts "PG1 VIOLATION: foreign cell [dbGet $it.name] ($c) on chain net [dbGet $np.name]"
		}
	}
}
foreach {pin port} {PGEN tcm_pgen RETN tcm_retn} {
	set np [dbGet -p top.insts.name ram0]
	set it [dbGet -p $np.instTerms.name ram0/$pin]
	set nn [dbGet $it.net.name]
	if {$nn ne $port} {
		incr pg1_bad
		puts "PG1 VIOLATION: ram0/$pin is driven by net '$nn', expected the AO port net '$port'"
	}
}
if {$pg1_bad > 0} {
	puts "FATAL (PG1): $pg1_bad power-gating acceptance violations -- aborting before signoff"
	exit 1
}
puts "### UNL STATUS ### : PG1 acceptance gate PASSED (chain pure, ram0 PG pins port-driven)"

################################################################################
# Signoff checks + reports
################################################################################
printStatus "verifyConnectivity"
verifyConnectivity \
    -error 100000 \
    -connectPadSpecialPorts \
    -report $REPORT_DIR/$OUT_NAME.verifyConnectivity.signoff.rpt

printStatus "verifyGeometry"
verifyGeometry \
    -antenna \
    -report $REPORT_DIR/$OUT_NAME.verifyGeometry.signoff.rpt

printStatus "verifyProcessAntenna"
verifyProcessAntenna \
    -report $REPORT_DIR/$OUT_NAME.verifyProcessAntenna.signoff.rpt

setDelayCalMode -SIAware false
setAnalysisMode -analysisType onChipVariation -cppr both
printStatus "timeDesign signoff"
timeDesign \
    -si \
    -signoff \
    -outdir $REPORT_DIR/$OUT_NAME.timeDesign.signoff.rpt

report_clock_timing \
    -type skew \
    -nworst 10 > $REPORT_DIR/$OUT_NAME.report_clock_timing.skew.signoff.rpt

setAnalysisMode -checkType hold -skew true
report_timing > $REPORT_DIR/$OUT_NAME.report_timing.hold.signoff.rpt
setAnalysisMode -checkType setup -skew true
report_timing > $REPORT_DIR/$OUT_NAME.report_timing.setup.signoff.rpt

reportGateCount \
    -level 2 \
    -outfile $REPORT_DIR/$OUT_NAME.reportGateCount.signoff.rpt
summaryReport \
    -noHtml \
    -outfile $REPORT_DIR/$OUT_NAME.summaryReport.signoff.rpt

saveDesign $DATABASE_DIR/$OUT_NAME.signoff.innovus -def -netlist -rc -tcon

################################################################################
# Output files: GDS, SDF, sim netlist, ILM, LEF abstract, per-corner ETMs
################################################################################
streamOut \
    $OUTPUT_DIR/$OUT_NAME.gds2 \
    -libName WorkLib \
    -structureName $DESIGN_NAME \
    -stripes 1 \
    -units 1000 \
    -mode ALL \
    -mapFile $INPUT_DIR/innovus2gds.map

printStatus "Writing SDF file"
write_sdf $OUTPUT_DIR/$OUT_NAME.sdf

printStatus "Writing verilog for Xcelium"
saveNetlist \
    $OUTPUT_DIR/$OUT_NAME.xsim.v \
    -excludeCellInst ANTENNA2A10TH

printStatus "Writing ILM"
createInterfaceLogic \
    -hold \
    -dir $OUTPUT_DIR/$OUT_NAME.ilm

printStatus "Writing LEF abstract"
lefOut \
    -StripePin \
    -PGpinLayers 7 8 \
    -specifyTopLayer 8 \
    $OUTPUT_DIR/$OUT_NAME.lef

# Per-corner ETMs (.lib) -- do_extract_model characterizes only the corner
# whose view is active for BOTH setup and hold, so force each in turn.
printStatus "Extracting per-corner ETMs (both-views-active recipe)"
set_analysis_view -setup [list setup_analysis_view] -hold [list setup_analysis_view]
if {[catch {do_extract_model -view setup_analysis_view $OUTPUT_DIR/$OUT_NAME.etm_ss.lib} etm_err]} {
	puts "ETM ss extraction FAILED: $etm_err"
} else {
	puts "ETM written to $OUTPUT_DIR/$OUT_NAME.etm_ss.lib"
}
set_analysis_view -setup [list hold_analysis_view] -hold [list hold_analysis_view]
if {[catch {do_extract_model -view hold_analysis_view $OUTPUT_DIR/$OUT_NAME.etm_ff.lib} etm_err]} {
	puts "ETM ff extraction FAILED: $etm_err"
} else {
	puts "ETM written to $OUTPUT_DIR/$OUT_NAME.etm_ff.lib"
}
set_analysis_view -setup [list setup_analysis_view] -hold [list hold_analysis_view]

saveDesign $DATABASE_DIR/$OUT_NAME.final.innovus -def -netlist -rc -tcon
toc
printStatus "hart_tile ARGUS compact-tile harden complete"
exit
