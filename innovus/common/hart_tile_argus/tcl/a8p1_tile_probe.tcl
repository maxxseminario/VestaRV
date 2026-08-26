################################################################################
# A8-P1 -- ARGUS hart_tile RESHAPE FEASIBILITY PROBE (placement-only).
#
# Clone of tcl/hart_tile_argus.innovus.tcl, reshaped 405x685 -> 526x528
# (near-square, aspect ~1.0) per ~/vesta_docs/argus/a8/a8_center_symmetry_plan.md
# section 1 + section 4 (A8-P1). This is a PROBE: it stops right after
# place_opt_design + its trial route and dumps the density / congestion / rough
# timing picture. It runs NO CTS, NO detail route, NO signoff, NO output
# (GDS/LEF/ETM). It is the GO/NO-GO gate that decides the real tile dims before
# A8-1 re-hardens for real.
#
# DIFFERENCES vs the as-built tile flow (deliberate, all placement-relevant):
#   * DESIGN_WIDTH/HEIGHT = 526/528 (env-overridable A8P1_W / A8P1_H for the
#     single 524x530 / 528x526 fallback the brief allows).
#   * OUT_NAME = hart_tile_argus_a8p1 for EVERY output/report/db so NOTHING with
#     the real hart_tile_argus.* name under out/ dbs/ rpt/ is touched. Inputs
#     (genus v/sdc, cpf, mmmc) still read the real hart_tile_argus source.
#   * CORNER TCM: the sram1p16k goes in the LOWER-LEFT corner (not a full-width
#     bottom band). The hard place-blockage + cutRow cover ONLY the macro+halo
#     corner box; std rows survive as the L around it (full-width rows above the
#     macro top + the right-strip rows beside it). The 489-pin M4 bottom-edge
#     strip (open y<2.02) survives across the full 526 width.
#   * PG recipe untouched/parametric: the M7 vertical lanes at 50um pitch just
#     extend to the wider tile; a diagnostic asserts every lane x stays < W.
#   * FATAL abort thresholds tuned to the 405x685 tile (dead-row count, switch
#     count, PG-fabric sWire floors) are RELAXED to reported warnings here -- a
#     probe must reach place_opt to answer the density/congestion question, not
#     abort on a threshold that legitimately shifts with the new geometry. The
#     numbers are REPORTED for A8-1 to re-baseline.
#   * The whole PG4 pmk secondary-strap completion campaign + PG1 GPGBUF
#     repeaters are OMITTED: they are post-detection power-connectivity fabric,
#     irrelevant to placement density/congestion, and heavy/fragile. A8-1 (the
#     real re-harden) restores them.
################################################################################

source ../shared/constants.tcl
source ../shared/procedures.tcl

proc plog {msg} { puts $msg; flush stdout }

set DESIGN_NAME hart_tile
set SRC_NAME    hart_tile_argus         ;# genus input basename (real source)

# --- Reshaped near-square geometry (A8-P1). Env-overridable per run. ---
set DESIGN_WIDTH  [expr {[info exists ::env(A8P1_W)] ? $::env(A8P1_W) : 520}]
set DESIGN_HEIGHT [expr {[info exists ::env(A8P1_H)] ? $::env(A8P1_H) : 522}]

# Dim-suffixed basename so each geometry's outputs/reports/db are DISTINCT and
# NOTHING with the real hart_tile_argus.* name is ever written.
set OUT_NAME    hart_tile_argus_a8p1_${DESIGN_WIDTH}x${DESIGN_HEIGHT}
plog "### A8P1 ### : reshape probe DESIGN_WIDTH=$DESIGN_WIDTH DESIGN_HEIGHT=$DESIGN_HEIGHT (area [expr {$DESIGN_WIDTH*$DESIGN_HEIGHT}] um^2)"

# Power ring / stripe geometry (Myshkin/M17 values -- proven; unchanged).
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
# Design import and setup (identical to the as-built tile; inputs = real source)
################################################################################
set init_verilog             "$GENUS_DIR/out/$SRC_NAME.genus.v"
set init_top_cell            "$DESIGN_NAME"
set init_pwr_net             "VDD"
set init_gnd_net             "VSS"
set init_mmmc_file           "$SCRIPT_DIR/viewdefinition_tile_argus.tcl"

set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					../../../std_cells/lef/tsmc65hvt_adv10pmk_macro.USEfix.lef \
					$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef"

set init_design_uniquify 1
init_design

read_power_intent -cpf ../../../cpf/hart_tile.cpf
commit_power_intent
printStatus "Power intent committed (PD_GATED/PD_AO, switched net VDD_SW)"

setDesignMode -process 65 -flowEffort standard -powerEffort low
printStatus "Preparing 8 CPU cores..."
setMultiCpuUsage -acquireLicense 8 -localCpu 8

setFillerMode \
    -corePrefix FILLER \
    -core {FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH}

setAnalysisMode -analysisType onChipVariation -cppr both

clearGlobalNets
globalNetConnect VDD_SW -type pgpin -pin VDD  -powerDomain PD_GATED -autoTie -verbose
globalNetConnect VDD    -type pgpin -pin VDD  -powerDomain PD_AO    -verbose
globalNetConnect VDD    -type pgpin -pin VDD  -singleInstance ram0 -override -verbose
globalNetConnect VSS    -type pgpin -pin VSS  -inst * -module {} -autoTie -verbose

################################################################################
# Floorplan: plain rectangle 526x528.
################################################################################
floorPlan \
    -site TSMC65ADV10TSITE \
    -s $CORE_WIDTH $CORE_HEIGHT $CORE_SPACING $CORE_SPACING $CORE_SPACING $CORE_SPACING
initCoreRow
printStatus "Floorplanned plain rectangle ($DESIGN_WIDTH x $DESIGN_HEIGHT)"

set SRAM16K_WIDTH		319.650
set SRAM16K_HEIGHT		383.085
set TCM_HALO            [expr {$STD_CELL_HEIGHT * 1}]

################################################################################
# CORNER TCM: sram1p16k in the LOWER-LEFT corner (R0). TCM_X=12 mirrors the
# proven bottom clearance (TCM_Y=12) to the left edge; both clear the M7/M8
# ring band and the M4 bottom pin strip. The hard blockage + cutRow cover ONLY
# the macro+halo corner box, so std rows survive as the L (right strip + rows
# above the macro).
################################################################################
set TCM_X	12
set TCM_Y	12
placeInstance ram0 $TCM_X $TCM_Y R0
addHaloToBlock $TCM_HALO $TCM_HALO $TCM_HALO $TCM_HALO ram0

# corner box: die corner (0,0) up to macro+halo extent
set TCM_BLK_X1 [expr {$TCM_X + $SRAM16K_WIDTH  + $TCM_HALO}]
set TCM_BLK_Y1 [expr {$TCM_Y + $SRAM16K_HEIGHT + $TCM_HALO}]
plog "### A8P1 ### : corner TCM ram0 @($TCM_X,$TCM_Y) R0 -> macro+halo corner box 0 0 [format %.3f $TCM_BLK_X1] [format %.3f $TCM_BLK_Y1]"

cutRow
createPlaceBlockage -type hard -name tcm_corner -box [list 0 0 $TCM_BLK_X1 $TCM_BLK_Y1]
cutRow -area [list 0 0 $TCM_BLK_X1 $TCM_BLK_Y1]

# Diagnostic: rows must survive OUTSIDE the corner box (the L). Count rows whose
# lly < macro top but which start to the RIGHT of the corner box (the vertical
# arm of the L) and rows fully above the macro (the horizontal arm).
set rows_in_corner 0
set rows_right_strip 0
set rows_above 0
foreach r [dbGet top.fplan.rows -e] {
	set b [lindex [dbGet $r.box] 0]
	foreach {bx0 by0 bx1 by1} $b {}
	if {$by0 < [expr {$TCM_BLK_Y1 - 0.5}]} {
		if {$bx0 < [expr {$TCM_BLK_X1 - 0.5}]} { incr rows_in_corner } else { incr rows_right_strip }
	} else {
		incr rows_above
	}
}
plog "### A8P1 ### : rows -- above-macro(full-width)=$rows_above right-strip(L arm)=$rows_right_strip leftover-in-corner=$rows_in_corner (want 0)"
if {$rows_in_corner > 0} {
	plog "### A8P1 WARN ### : $rows_in_corner rows survived inside the corner box -- cutRow did not fully clear it (report, do not abort in probe)"
}
printStatus "Placed corner TCM (R0, lower-left) + cleared corner box"

# All tile pins on the BOTTOM edge (M4). 489 pins now spread over the wider 526.
set ALL_PINS [dbGet top.terms.name]
plog "### A8P1 ### : assigning [llength $ALL_PINS] pins to the bottom edge over width $DESIGN_WIDTH"
editPin -pin $ALL_PINS -side Bottom -layer 4 -spreadType side -spacing 1 -fixOverlap 1
printStatus "Placed tile pins"

################################################################################
# Power: full rectangular ring + M7/M8 stripe grid (parametric -- extends to W).
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

# A8P1 PG LANE SANITY: every M7 vertical PG lane x must stay inside the die.
set m7_lane_xs {}
foreach __net {VDD VSS} {
	foreach __sw [dbGet [dbGet -p top.nets.name $__net].sWires -e] {
		if {[dbGet -e $__sw.layer.name] ne "M7"} { continue }
		set __b [lindex [dbGet $__sw.box] 0]
		foreach {__x0 __y0 __x1 __y1} $__b {}
		if {[expr {$__y1 - $__y0}] < [expr {$__x1 - $__x0}]} { continue } ;# vertical only
		lappend m7_lane_xs [format %.2f [expr {($__x0 + $__x1) / 2.0}]]
	}
}
set m7_lane_xs [lsort -real -unique $m7_lane_xs]
set m7_lane_max [expr {[llength $m7_lane_xs] ? [lindex $m7_lane_xs end] : -1}]
plog "### A8P1 ### : [llength $m7_lane_xs] M7 vertical PG lanes, x range [lindex $m7_lane_xs 0]..$m7_lane_max (die W=$DESIGN_WIDTH)"
plog "### A8P1 ### : M7 lane xs = $m7_lane_xs"
if {$m7_lane_max >= $DESIGN_WIDTH} {
	plog "### A8P1 WARN ### : an M7 PG lane x ($m7_lane_max) reached/exceeded the die width $DESIGN_WIDTH"
}

################################################################################
# M17 MTCMOS header fabric. Same recipe; -area is the WHOLE core now (only the
# corner box was cut, so live rows exist across the die minus that corner).
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

set sw_insts {}
foreach inst [dbGet top.insts -e] {
	if {[dbGet $inst.cell.name] eq "HEADBUF16MA10TH"} { lappend sw_insts $inst }
}
set NSW [llength $sw_insts]
plog "### A8P1 ### : $NSW HEADBUF16MA10TH power switches inserted"
if {$NSW == 0} {
	plog "### A8P1 FATAL ### : addPowerSwitch inserted ZERO switches -- power intent/area wrong, cannot probe placement"
	exit 1
}

################################################################################
# DEAD-ROW DETECTION (corner-TCM re-derivation). Detect switchless rows; block
# them so place_opt parks nothing live on a dead VDD_SW rail (affects the real
# placeable area -> the density number). The 405x685 tile FATAL'd at NDEAD>8;
# the corner TCM legitimately shifts this (short right-strip rows), so the probe
# REPORTS the count instead of aborting -- it is a finding for A8-1.
################################################################################
set ROW_H $STD_CELL_HEIGHT
set sw_ys {}
foreach c $sw_insts { lappend sw_ys [format %.3f [dbGet $c.box_lly]] }
set sw_ys [lsort -unique $sw_ys]
set all_row_ys {}
foreach r [dbGet top.fplan.rows -e] {
	set ry [format %.3f [dbGet $r.box_lly]]
	if {[lsearch -exact $all_row_ys $ry] >= 0} { continue }
	lappend all_row_ys $ry
}
set all_row_ys [lsort -unique $all_row_ys]
plog "### A8P1 ### : [llength $all_row_ys] distinct core rows, [llength $sw_ys] rows carry a switch"
if {[llength $all_row_ys] == 0} {
	plog "### A8P1 FATAL ### : zero core rows from dbGet top.fplan.rows -- wrong accessor"
	exit 1
}
set dead_row_boxes {}
foreach ry $all_row_ys {
	set covered 0
	foreach sy $sw_ys { if {abs($ry - $sy) < 0.01} { set covered 1; break } }
	if {$covered} { continue }
	lappend dead_row_boxes [list 0 $ry $DESIGN_WIDTH [expr {$ry + $ROW_H}]]
}
set NDEAD [llength $dead_row_boxes]
plog "### A8P1 ### : $NDEAD switchless (dead VDD_SW) rows detected -- will block (405x685 tile FATAL'd at >8; probe reports instead)"

# M17 well taps
addWellTap \
    -cell FILLBIASA10TH \
    -cellInterval 24 \
    -fixedGap \
    -checkerBoard \
    -prefix WELLTAP

# secondary pmk pins connected (logical GNC only; the physical strap fabric that
# the real flow builds here is OMITTED -- irrelevant to placement).
globalNetConnect VDD -type pgpin -pin VDDG -inst * -module {} -verbose
globalNetConnect VDD -type pgpin -pin VNW  -inst * -module {} -verbose
globalNetConnect VSS -type pgpin -pin VPW  -inst * -module {} -verbose

printStatus "Routing power rails (corePin only -- secondary strap fabric omitted for the probe)"
setSrouteMode -corePinMaxViaScale "100 10"
sroute \
	-nets { VSS VDD VDD_SW } \
	-allowLayerChange 0 \
	-allowJogging 0 \
	-connect corePin \
    -corePinWidth 0.3

# Reserve M7/M8 for power during (trial) signal routing -> realistic 6-layer
# congestion picture, exactly as the real flow.
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -layer 7
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -layer 8

################################################################################
# DEAD-ROW BLOCKAGES + placement.
################################################################################
foreach {b} $dead_row_boxes {
	set nm dead_row_[format %.0f [expr {[lindex $b 1] * 10}]]
	createPlaceBlockage -type hard -name $nm -box $b
}
printStatus "Blocked $NDEAD switchless dead-rail rows (detected)"

place_opt_design
printStatus "Placement done -- place_opt trial route complete (see NR-eGR lines in the log)"

################################################################################
# A8-P1 GATE READOUT: density, congestion, rough timing. NO CTS/route/signoff.
################################################################################
plog "=================== A8P1 GATE READOUT ==================="

# --- (b) DENSITY. summaryReport gives the standard Pure/Gross gate density.
summaryReport -noHtml -outfile $REPORT_DIR/$OUT_NAME.summaryReport.place.rpt
catch {reportDensity} rd
plog "### A8P1 density(reportDensity) ### : $rd"

# Placeable-area utilization computed directly: std LOGIC cell area vs total row
# area, and vs (row area - blocked dead-row area). Excludes fillers/taps/
# switches/macro. This is the true L-region utilization the gate cares about.
proc a8p1_is_phys {c} {
	return [expr {[string match FILL* $c] || [string match WELLTAP* $c] || [string match HEADBUF* $c] || [string match FILLBIAS* $c] || [string match ANTENNA* $c] || $c eq "sram1p16k_hvt_pg"}]
}
set logic_area 0.0
set phys_area  0.0
foreach i [dbGet top.insts -e] {
	set c [dbGet $i.cell.name]
	set b [lindex [dbGet $i.box] 0]
	foreach {bx0 by0 bx1 by1} $b {}
	set a [expr {($bx1 - $bx0) * ($by1 - $by0)}]
	if {[a8p1_is_phys $c]} { set phys_area [expr {$phys_area + $a}] } else { set logic_area [expr {$logic_area + $a}] }
}
# L-region placeable area, GEOMETRIC (robust; dbGet top.fplan.rows over-counts
# after cutRow, so we bound the two arms of the L directly). The authoritative
# L-region density is summaryReport "Pure Gate Density #5 (Subtracting MACROS
# and BLOCKAGES)" -- this is a corroborating cross-check.
set MRG $CORE_SPACING
set L_horiz_arm [expr {($DESIGN_WIDTH - 2*$MRG) * ($DESIGN_HEIGHT - $TCM_BLK_Y1 - $MRG)}]
set L_vert_arm  [expr {($DESIGN_WIDTH - $TCM_BLK_X1 - $MRG) * ($TCM_BLK_Y1 - 2*$MRG)}]
set L_placeable [expr {$L_horiz_arm + $L_vert_arm}]
set dead_area 0.0
foreach b $dead_row_boxes {
	foreach {bx0 by0 bx1 by1} $b {}
	set dead_area [expr {$dead_area + ($bx1 - $bx0) * ($by1 - $by0)}]
}
set L_live [expr {$L_placeable - $dead_area}]
set util_L [expr {$L_live > 0 ? 100.0 * $logic_area / $L_live : -1}]
plog "### A8P1 density ### : logic-cell area = [format %.0f $logic_area] um^2, phys-cell(switch/tap/macro) area = [format %.0f $phys_area] um^2"
plog "### A8P1 density ### : L-region placeable = [format %.0f $L_placeable] um^2 (horiz arm [format %.0f $L_horiz_arm] + vert arm [format %.0f $L_vert_arm]), dead-row = [format %.0f $dead_area], L-live = [format %.0f $L_live]"
plog "### A8P1 density ### : L-REGION STD-LOGIC DENSITY (geometric) = [format %.1f $util_L] % (authoritative = summaryReport Pure Gate Density #5; want << 75)"

# --- (c) CONGESTION. place_opt's trial route already logged [NR-eGR]; also emit
# an explicit congestion report (map/hotspots), several syntaxes tried.
set __cong_ok 0
foreach __cmd [list \
	"report_congestion -overflow -outfile $REPORT_DIR/$OUT_NAME.congestion.rpt" \
	"report_congestion -hotSpot -outfile $REPORT_DIR/$OUT_NAME.congestion.rpt" \
	"report_congestion > $REPORT_DIR/$OUT_NAME.congestion.rpt" ] {
	if {![catch { eval $__cmd } __e]} { set __cong_ok 1; plog "### A8P1 congestion ### : wrote report via: $__cmd"; break } \
	else { plog "### A8P1 congestion ### : '$__cmd' failed ($__e)" }
}
if {!$__cong_ok} { plog "### A8P1 congestion ### : no report_congestion variant worked -- rely on the NR-eGR lines in the log" }
# GCell overflow markers straight from the DB (H/V), a map-independent count.
catch {
	set __ov [dbGet top.markers.subType -e]
	plog "### A8P1 congestion ### : DB marker subtypes present: [lsort -unique $__ov]"
}

# --- (d) ROUGH TIMING (pre-CTS, ideal clock). The real tile closed +14.5 ns;
# a probe WNS within a few ns of zero is fine at this stage.
setAnalysisMode -checkType setup
report_timing > $REPORT_DIR/$OUT_NAME.report_timing.setup.place.rpt
plog "### A8P1 timing ### : setup report -> $REPORT_DIR/$OUT_NAME.report_timing.setup.place.rpt (grep 'Slack' for WNS)"

# --- save the probe DB and stop. NO CTS / route / signoff / output.
saveDesign $DATABASE_DIR/$OUT_NAME.probe.innovus
plog "### A8P1 ### : saved dbs/$OUT_NAME.probe.innovus"
toc
plog "### A8P1 ### : PLACEMENT PROBE COMPLETE ($DESIGN_WIDTH x $DESIGN_HEIGHT) -- readout above, no CTS/route/signoff run"
exit
