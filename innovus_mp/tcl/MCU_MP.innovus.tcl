################################################################################
# Innovus script -- MCU_MP TOP-LEVEL ASSEMBLY (M14 physical flow)
#
# Hierarchical assembly: the four hart instances (hart0-3) are the HARDENED
# hart_tile block -- physical footprint from out/hart_tile.lef, timing from
# the ILM out/hart_tile.ilm (specifyIlm; super-commands flatten it
# internally). Control plane (arbiter/CLINT/router/mutex/periph/system0 +
# rom0 + npuram0 + shbank0-3 + analog blocks) is placed and routed here, and
# top-level CTS balances the clock into the four tile clk pins.
#
# Netlist: in/MCU_MP_hier.pnr.v = out-of-genus MCU_MP_hier.genus.v with any
# empty `module hart_tile` blackbox stub STRIPPED (prep_top_netlist.sh) so
# innovus binds hart_tile to the LEF macro + ILM, not to an empty module.
#
# Floorplan (die 1400 x 2160): a column of 4 tiles (1146x280, pins on each
# tile's top edge) with 50 um escape channels between them and a ~250 um
# vertical routing channel on the right; control plane above the column
# (5 shared sram1p16k strips, then the boot ROM + analog + logic strip).
################################################################################

source tcl/constants.tcl
source $SCRIPT_DIR/procedures.tcl

set DESIGN_NAME MCU
set BASENAME    MCU_MP

set DESIGN_WIDTH  1400
set DESIGN_HEIGHT 2160

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
# Design import
################################################################################
set init_verilog             "$INPUT_DIR/MCU_MP_hier.pnr.v"
set init_top_cell            "$DESIGN_NAME"
set init_pwr_net             "VDD"
set init_gnd_net             "VSS"
set init_mmmc_file           "$SCRIPT_DIR/viewdefinition_top.tcl"

set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					$IP_DIR/rom_hvt_pg/rom_hvt_pg.lef \
					$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef \
					$IC_DIR/abstracts/myshkin_abs/GlitchFilter/GlitchFilter.lef \
					$IC_DIR/abstracts/myshkin_abs/PowerOnResetCheng/PowerOnResetCheng.lef \
					$IC_DIR/abstracts/myshkin_abs/OscillatorCurrentStarved/OscillatorCurrentStarved.lef \
					$OUTPUT_DIR/hart_tile.lef"

set init_design_uniquify 1
init_design

# Tile timing enters via the ETM .lib (viewdefinition_top library sets:
# out/hart_tile.etm_{ss,ff}.lib) -- the tile is a timed macro exactly like
# the SRAMs/ROM. The ILM route was tried first and ABANDONED: after
# specifyIlm, the rebuilt (flattened-ILM) timing session comes up with NO
# clocks when the clocks are defined on hierarchical pins (system0/mclk_out
# et al., the house style since Myshkin) -- create_ccopt_clock_tree_spec
# then finds no clock roots (IMPCCOPT-4082). ETM + hpin clocks is exactly
# the Myshkin-proven configuration. The ILM stays on disk as a second
# abstraction artifact.

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
# Floorplan
################################################################################
floorPlan \
    -site TSMC65ADV10TSITE \
    -s $CORE_WIDTH $CORE_HEIGHT $CORE_SPACING $CORE_SPACING $CORE_SPACING $CORE_SPACING

# --- The tile column: 4x hart_tile, 50 um escape channel between tiles ---
set TILE_W       1146
set TILE_H       280
set TILE_X       10
set TILE_GAP     50
for {set h 0} {$h < 4} {incr h} {
	set TILE_Y [expr {10 + $h * ($TILE_H + $TILE_GAP)}]
	placeInstance hart$h $TILE_X $TILE_Y R0
	addHaloToBlock 10 10 10 10 hart$h
}
cutRow
# column top = 10 + 3*330 + 280 = 1280

# --- Shared memories: 5 sram1p16k strips (shbank0-3 + npuram0) ---
set SRAM16K_WIDTH		1126.050
set SRAM16K_HEIGHT		121.470
set SH_X 10
set SH_Y0 1340
set SH_PITCH [expr {$SRAM16K_HEIGHT + 10}]
set i 0
foreach m {shbank0 shbank1 shbank2 shbank3 npuram0} {
	placeInstance $m $SH_X [expr {$SH_Y0 + $i * $SH_PITCH}] MX
	addHaloToBlock 4 4 4 4 $m
	incr i
}
cutRow
# memory stack top = 1340 + 5*131.47 = ~1998

# --- Boot ROM (R90: 325.055 wide x 156.525 tall) ---
set ROM_X 10
set ROM_Y 2010
placeInstance rom0 $ROM_X $ROM_Y R90
addHaloToBlock 9 4 4 9 rom0
cutRow

# --- Analog blocks (POR, 2x DCO, 3x IRQ glitch filter) in the top strip ---
placeInstance por     420 2010 R0
addHaloToBlock 4 4 4 4 por
placeInstance dco0    520 2010 R0
addHaloToBlock 4 4 4 4 dco0
placeInstance dco1    640 2010 R0
addHaloToBlock 4 4 4 4 dco1
placeInstance irq_gf0 760 2010 R0
addHaloToBlock 4 4 4 4 irq_gf0
placeInstance irq_gf1 850 2010 R0
addHaloToBlock 4 4 4 4 irq_gf1
placeInstance irq_gf2 940 2010 R0
addHaloToBlock 4 4 4 4 irq_gf2
cutRow

printStatus "Placed tiles + memories + ROM + analog blocks"

# --- Chip pins: spread along the TOP edge (control-plane side), M4 ---
set ALL_PINS [dbGet top.terms.name]
puts "Assigning [llength $ALL_PINS] pins to the top edge"
editPin -pin $ALL_PINS -side Top -layer 4 -spreadType side -spacing 2 -fixOverlap 1
printStatus "Placed chip pins"

################################################################################
# Power
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
	-connect {blockPin corePin} \
	-blockPin useLef \
    -corePinWidth 0.3

verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$BASENAME.verifyGeometry.preplace.rpt
fixVia -short
fixVia -minCut
fixVia -minStep

# Reserve M7/M8 for power during signal routing.
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -layer 7
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -layer 8

################################################################################
# Placement
################################################################################
# Spurious clock-gating checks on the TIMER ClockMuxGlitchFree select legs:
# innovus infers an AND-gate gating check (enable stable until mclk's falling
# edge) on the mux's clock-AND gates -- unmeetable (select launches at the
# rising edge) and IRRELEVANT: the mux is glitch-free by construction (each
# leg's select is double-synced onto its own clock; M7b). Without the disable,
# hold fixing burned ~11 ns of delay cells chasing -8.5 ns on
# timer1/control_reg_reg[16] -> g11710 and still failed signoff. Gate names
# are netlist-dependent (genus-mapped): if a resynth renames them, find the
# violating gating endpoint in the hold signoff report and update this list.
set_interactive_constraint_modes [all_constraint_modes -active]
foreach g {timer0/g11710 timer1/g11710} {
	if {[catch {set_disable_clock_gating_check $g} r]} {
		puts "gating-check disable SKIPPED for $g: $r"
	} else {
		puts "gating-check disabled on $g"
	}
}
set_interactive_constraint_modes {}

addWellTap \
    -cell FILLTIE2A10TH \
    -cellInterval 24 \
    -fixedGap \
    -checkerBoard \
    -prefix WELLTAP

place_opt_design
printStatus "Placement done"

################################################################################
# Clock tree synthesis -- balances into the four tile clk pins (identical
# hardened tiles => identical internal insertion delay; the ILM carries the
# tile clock interface)
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
timeDesign -postCTS -expandedViews -outDir $REPORT_DIR/$BASENAME.timeDesign.postcts
report_ccopt_clock_trees -file $REPORT_DIR/$BASENAME.report_ccopt_clock_trees.postcts
report_ccopt_skew_groups -file $REPORT_DIR/$BASENAME.report_ccopt_skew_groups.postcts
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
    -drouteAntennaEcoListFile $REPORT_DIR/$BASENAME.routeDesign.diodes.txt \
    -dbSkipAnalog true \
    -drouteEndIteration default
routeDesign

optDesign -postRoute -setup -hold

verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$BASENAME.verifyGeometry.postroute.rpt
ecoRoute -fix_drc
verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$BASENAME.verifyGeometry.postroute.rpt

deleteAllRouteBlks
addFiller

################################################################################
# Signoff checks + reports
################################################################################
printStatus "verifyConnectivity"
verifyConnectivity \
    -error 100000 \
    -connectPadSpecialPorts \
    -report $REPORT_DIR/$BASENAME.verifyConnectivity.signoff.rpt

printStatus "verifyGeometry"
verifyGeometry \
    -antenna \
    -report $REPORT_DIR/$BASENAME.verifyGeometry.signoff.rpt

setDelayCalMode -SIAware false
setAnalysisMode -analysisType onChipVariation -cppr both
printStatus "timeDesign signoff"
timeDesign \
    -si \
    -signoff \
    -outdir $REPORT_DIR/$BASENAME.timeDesign.signoff.rpt

report_clock_timing \
    -type skew \
    -nworst 10 > $REPORT_DIR/$BASENAME.report_clock_timing.skew.signoff.rpt

setAnalysisMode -checkType hold -skew true
report_timing > $REPORT_DIR/$BASENAME.report_timing.hold.signoff.rpt
setAnalysisMode -checkType setup -skew true
report_timing > $REPORT_DIR/$BASENAME.report_timing.setup.signoff.rpt

reportGateCount \
    -level 2 \
    -outfile $REPORT_DIR/$BASENAME.reportGateCount.signoff.rpt
summaryReport \
    -noHtml \
    -outfile $REPORT_DIR/$BASENAME.summaryReport.signoff.rpt

saveDesign $DATABASE_DIR/$BASENAME.signoff.innovus -def -netlist -rc -tcon

################################################################################
# Output files (top-only netlist/SDF: the tile interiors come from the tile
# harden's out/hart_tile.{xsim.v,sdf} at gate-sim time)
################################################################################
streamOut \
    $OUTPUT_DIR/$BASENAME.gds2 \
    -libName WorkLib \
    -structureName $DESIGN_NAME \
    -stripes 1 \
    -units 1000 \
    -mode ALL \
    -merge [list $OUTPUT_DIR/hart_tile.gds2] \
    -mapFile $INPUT_DIR/innovus2gds.map

printStatus "Writing SDF (top level)"
write_sdf $OUTPUT_DIR/$BASENAME.sdf

printStatus "Writing verilog for Xcelium (top level; hart_tile as leaf refs)"
saveNetlist \
    $OUTPUT_DIR/$BASENAME.xsim.v \
    -excludeCellInst ANTENNA2A10TH

saveDesign $DATABASE_DIR/$BASENAME.final.innovus -def -netlist -rc -tcon
toc
printStatus "MCU_MP top assembly complete"
exit
