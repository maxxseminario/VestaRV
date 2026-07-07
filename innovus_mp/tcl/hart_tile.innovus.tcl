################################################################################
# Innovus script -- hart_tile TILE HARDEN (M14 physical flow)
#
# Derived from the frozen Myshkin ~/vestarv/innovus/tcl/MCU.innovus.tcl, cut
# down to a single-tile block harden and made BATCH-SAFE (no suspend, no GUI
# refresh calls). One hart_tile = vesta core + adddec + one sram1p16k TCM,
# with the M13 depth-1 registered boundary. All four MCU_MP hart instances
# place THIS one hardened block 4x at top level.
#
# Floorplan: the sram1p16k compiled macro is 1126.05 x 121.47 (wide strip) --
# it sits at the bottom of the tile, logic strip above it (~63k um2 of std
# cells in ~163k um2 of rows, ~40% util). All tile pins on the TOP edge (M4,
# vertical-preferred) so a column of 4 tiles faces the control plane.
#
# Outputs (out/): hart_tile.{gds2,sdf,xsim.v,lef} + hart_tile.ilm/ (ILM) and
# hart_tile.etm.lib (ETM, best-effort catch -- ILM is the primary abstraction).
################################################################################

source tcl/constants.tcl
source $SCRIPT_DIR/procedures.tcl

set DESIGN_NAME hart_tile

# Tile die. SRAM strip 1126.05 wide + 10 um margins each side.
set DESIGN_WIDTH  1146
set DESIGN_HEIGHT 280

# Power ring / stripe geometry (Myshkin values).
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
set init_verilog             "$GENUS_DIR/out/$DESIGN_NAME.genus.v"
set init_top_cell            "$DESIGN_NAME"
set init_pwr_net             "VDD"
set init_gnd_net             "VSS"
set init_mmmc_file           "$SCRIPT_DIR/viewdefinition_tile.tcl"

set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef"

set init_design_uniquify 1
init_design

setDesignMode -process 65 -flowEffort standard -powerEffort low
printStatus "Preparing 8 CPU cores..."
setMultiCpuUsage -acquireLicense 8 -localCpu 8

setFillerMode \
    -corePrefix FILLER \
    -core {FILLTIE128A10TH FILLTIE64A10TH FILLTIE32A10TH FILLTIE16A10TH FILLTIE8A10TH FILLTIE4A10TH FILLTIE2A10TH FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH}

setAnalysisMode -analysisType onChipVariation -cppr both

clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst * -module {} -autoTie -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -module {} -autoTie -verbose

################################################################################
# Floorplan: rectangle, TCM strip at the bottom, pins on the top edge
################################################################################
floorPlan \
    -site TSMC65ADV10TSITE \
    -s $CORE_WIDTH $CORE_HEIGHT $CORE_SPACING $CORE_SPACING $CORE_SPACING $CORE_SPACING

set SRAM16K_WIDTH		1126.050
set SRAM16K_HEIGHT		121.470

set TCM_X	10
set TCM_Y	10
placeInstance ram0 $TCM_X $TCM_Y MX
addHaloToBlock \
    [expr {$STD_CELL_HEIGHT * 1}] \
    [expr {$STD_CELL_HEIGHT * 1}] \
    [expr {$STD_CELL_HEIGHT * 1}] \
    [expr {$STD_CELL_HEIGHT * 1}] \
    ram0
cutRow
printStatus "Placed TCM macro"

# All tile pins spread along the TOP edge on M4 (vertical-preferred). The
# top-level floorplan stacks tiles in a column below the control plane.
set ALL_PINS [dbGet top.terms.name]
puts "Assigning [llength $ALL_PINS] pins to the top edge"
editPin -pin $ALL_PINS -side Top -layer 4 -spreadType side -spacing 2 -fixOverlap 1
printStatus "Placed tile pins"

################################################################################
# Power: ring + stripes on M7/M8 (reserved for power via route blockages)
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

printStatus "Routing power rails"
setSrouteMode -corePinMaxViaScale "100 10"
sroute \
	-nets { VSS VDD } \
	-allowLayerChange 0 \
	-allowJogging 0 \
	-connect corePin \
    -corePinWidth 0.3

verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.preplace.rpt
fixVia -short
fixVia -minCut
fixVia -minStep

# Reserve M7/M8 for power during signal routing.
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -layer 7
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -layer 8

################################################################################
# Placement
################################################################################
addWellTap \
    -cell FILLTIE2A10TH \
    -cellInterval 24 \
    -fixedGap \
    -checkerBoard \
    -prefix WELLTAP

place_opt_design
printStatus "Placement done"

################################################################################
# Clock tree synthesis (mclk from the clk port; clk_cpu is a generated clock
# through vesta's ClkGate -- ccopt traces it)
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
timeDesign -postCTS -expandedViews -outDir $REPORT_DIR/$DESIGN_NAME.timeDesign.postcts
report_ccopt_clock_trees -file $REPORT_DIR/$DESIGN_NAME.report_ccopt_clock_trees.postcts
report_ccopt_skew_groups -file $REPORT_DIR/$DESIGN_NAME.report_ccopt_skew_groups.postcts
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
    -drouteAntennaEcoListFile $REPORT_DIR/$DESIGN_NAME.routeDesign.diodes.txt \
    -dbSkipAnalog true \
    -drouteEndIteration default
routeDesign

optDesign -postRoute -setup -hold

verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.postroute.rpt
ecoRoute -fix_drc
verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.postroute.rpt

deleteAllRouteBlks
addFiller

################################################################################
# Signoff checks + reports
################################################################################
printStatus "verifyConnectivity"
verifyConnectivity \
    -error 100000 \
    -connectPadSpecialPorts \
    -report $REPORT_DIR/$DESIGN_NAME.verifyConnectivity.signoff.rpt

printStatus "verifyGeometry"
verifyGeometry \
    -antenna \
    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt

printStatus "verifyProcessAntenna"
verifyProcessAntenna \
    -report $REPORT_DIR/$DESIGN_NAME.verifyProcessAntenna.signoff.rpt

setDelayCalMode -SIAware false
setAnalysisMode -analysisType onChipVariation -cppr both
printStatus "timeDesign signoff"
timeDesign \
    -si \
    -signoff \
    -outdir $REPORT_DIR/$DESIGN_NAME.timeDesign.signoff.rpt

report_clock_timing \
    -type skew \
    -nworst 10 > $REPORT_DIR/$DESIGN_NAME.report_clock_timing.skew.signoff.rpt

setAnalysisMode -checkType hold -skew true
report_timing > $REPORT_DIR/$DESIGN_NAME.report_timing.hold.signoff.rpt
setAnalysisMode -checkType setup -skew true
report_timing > $REPORT_DIR/$DESIGN_NAME.report_timing.setup.signoff.rpt

reportGateCount \
    -level 2 \
    -outfile $REPORT_DIR/$DESIGN_NAME.reportGateCount.signoff.rpt
summaryReport \
    -noHtml \
    -outfile $REPORT_DIR/$DESIGN_NAME.summaryReport.signoff.rpt

saveDesign $DATABASE_DIR/$DESIGN_NAME.signoff.innovus -def -netlist -rc -tcon

################################################################################
# Output files: GDS, SDF, sim netlist, ILM, LEF abstract, ETM (best-effort)
################################################################################
streamOut \
    $OUTPUT_DIR/$DESIGN_NAME.gds2 \
    -libName WorkLib \
    -structureName $DESIGN_NAME \
    -stripes 1 \
    -units 1000 \
    -mode ALL \
    -mapFile $INPUT_DIR/innovus2gds.map

printStatus "Writing SDF file"
write_sdf $OUTPUT_DIR/$DESIGN_NAME.sdf

printStatus "Writing verilog for Xcelium"
saveNetlist \
    $OUTPUT_DIR/$DESIGN_NAME.xsim.v \
    -excludeCellInst ANTENNA2A10TH

# ILM -- the primary tile abstraction for the top-level flow (interface logic
# + clock interface with real post-route timing).
printStatus "Writing ILM"
createInterfaceLogic \
    -hold \
    -dir $OUTPUT_DIR/$DESIGN_NAME.ilm

# LEF abstract -- pins + blockages for top-level placement/routing. The tile
# uses M7/M8 for its own power ring/stripes, so the abstract exposes them as
# PG pins (top-level stripes via down onto the tile ring).
printStatus "Writing LEF abstract"
lefOut \
    -StripePin \
    -PGpinLayers 7 8 \
    -specifyTopLayer 8 \
    $OUTPUT_DIR/$DESIGN_NAME.lef

# ETM (.lib) -- best-effort extra; ILM is the flow of record. If the command
# is unavailable/fails in this Innovus build, the flow proceeds.
printStatus "Attempting ETM extraction (best-effort)"
if {[catch {do_extract_model -view setup_analysis_view $OUTPUT_DIR/$DESIGN_NAME.etm.lib} etm_err]} {
	puts "ETM extraction FAILED (non-fatal): $etm_err"
} else {
	puts "ETM written to $OUTPUT_DIR/$DESIGN_NAME.etm.lib"
}

saveDesign $DATABASE_DIR/$DESIGN_NAME.final.innovus -def -netlist -rc -tcon
toc
printStatus "hart_tile harden complete"
exit
