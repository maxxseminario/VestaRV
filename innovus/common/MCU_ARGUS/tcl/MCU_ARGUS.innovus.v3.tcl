################################################################################
# Innovus script -- MCU_ARGUS TOP-LEVEL ASSEMBLY (A4; 18-tile teaching chip)
#
# Hierarchical assembly of the 18-hart Argus MCU on the 2690x2690 M15 pad-ring
# interior. The 18 hart instances (hart0-17) are the HARDENED compact tile
# (405x730 plain rectangle -- NO analog notch; Argus is digital-only):
# footprint from ../hart_tile_argus/out/hart_tile_argus.lef, timing from the per-corner ETMs
# ../hart_tile_argus/out/hart_tile_argus.etm_{ss,ff}.lib. This run places + routes the control
# plane (18-master arbiter / CLINT / IRQ router / mutex bank / pwr_ctrl / resv +
# the shared peripherals + rom0 + POR/DCO/GlitchFilter analog blocks) + the 8
# shared-RAM banks, and balances top-level CTS into the 18 tile clk pins.
#
# FLOORPLAN (the 730-tall tile makes the vertical budget tight: 3 rows = 2190 of
# 2690, so the control plane cannot take a full bottom band):
#   BOTTOM  : the 8 shared-RAM banks (shbank0-7, square sram1p16k 319.65x383.085)
#             in one centered full-width row (8*319.65 + 7*10 = 2627 fits 2690).
#   LEFT STRIP (x 0..CTRL_STRIP): rom0 (R0 156.5x325) + POR/DCO0/1/GlitchFilter
#             x3 macros + ALL the control-plane std cells (place_opt fills the
#             strip rows). The arbiter fan-in (18 tiles x ~55 wires) converges
#             here -- the A2-flagged congestion watch; timing has +33.8 ns slack.
#   TILES   : 6 cols x 3 rows of the hardened tile, filling the area right of the
#             strip and above the RAM band. All tile pins are on the tile BOTTOM
#             edge, so each tile drops its shared-bus/IRQ wires down into the
#             inter-tile channels toward the control plane + RAM.
# All chip pins on the die BOTTOM edge (digital-only; north face signal-free).
#
# hw_clint_en: the Argus MCU.vhd drives it EXPLICITLY per tile (hart0='0',
# harts 1-17='1') -- the netlist carries the straps, so the M14 "VHDL default
# lost at the netlist boundary" silicon bug does NOT apply here (verified).
#
# Netlist: in/MCU_ARGUS_hier.pnr.v = MCU_ARGUS_hier.genus.v with the hart_tile
# subtree stripped (prep_top_netlist_argus.sh) so innovus binds hart_tile to the
# LEF macro. Output: top-only netlist/SDF (tile interiors come from the tile
# harden's ../hart_tile_argus/out/hart_tile_argus.{xsim.v,sdf} at gate-sim time).
################################################################################

source ../shared/constants.tcl
source ../shared/procedures.tcl
proc plog {msg} { puts $msg; flush stdout }

set DESIGN_NAME MCU
set BASENAME    MCU_ARGUS

set DESIGN_WIDTH  2690
set DESIGN_HEIGHT 2690

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
set init_verilog             "$INPUT_DIR/MCU_ARGUS_hier.pnr.v"
set init_top_cell            "$DESIGN_NAME"
set init_pwr_net             "VDD"
set init_gnd_net             "VSS"
set init_mmmc_file           "$SCRIPT_DIR/viewdefinition_top_argus.tcl"

set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					$IP_DIR/rom_hvt_pg/rom_hvt_pg.lef \
					$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef \
					$IC_DIR/abstracts/myshkin_abs/GlitchFilter/GlitchFilter.lef \
					$IC_DIR/abstracts/myshkin_abs/PowerOnResetCheng/PowerOnResetCheng.lef \
					$IC_DIR/abstracts/myshkin_abs/OscillatorCurrentStarved/OscillatorCurrentStarved.lef \
					../hart_tile_argus/out/hart_tile_argus.lef"

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
# Floorplan
################################################################################
floorPlan \
    -site TSMC65ADV10TSITE \
    -s $CORE_WIDTH $CORE_HEIGHT $CORE_SPACING $CORE_SPACING $CORE_SPACING $CORE_SPACING

# --- Geometry parameters (must match the hardened tile / macro LEFs) ---
set TILE_W        405
set TILE_H        685
set NCOLS         6
set NROWS         3
set SRAM16K_WIDTH  319.650
set SRAM16K_HEIGHT 383.085

# === v3 FLOORPLAN (shorter tile -> full-width tiles + a full-width control BAND) ===
# The 685-tall tile frees the vertical room for the winning topology: 6
# FULL-WIDTH tile columns with ~40 um inter-column gaps that form CONTINUOUS
# vertical fan-in channels top-row-to-band (the 730-tile v2 was stuck with a left
# strip + 10 um gaps -> ~48% V overflow, router gave up), and a full-width
# CONTROL BAND below the tiles holding ROM (R90) + all fabric + peripherals. The
# band is the ONLY std-cell region (tiles = macros, RAM cut), so place_opt puts
# the whole control plane there; the fabric is additionally FENCED to the band so
# the 18-column arbiter fan-in spreads horizontally. Vertical budget:
# RAM(~390) + control band(170) + 3*685(2055) = 2615 of the ~2632 ring interior.
set SH_GAP   10
set SH_Y     25
set SH_SPAN  [expr {8 * $SRAM16K_WIDTH + 7 * $SH_GAP}]
set SH_X0    [expr {($DESIGN_WIDTH - $SH_SPAN) / 2.0}]
set RAM_BAND_TOP [expr {$SH_Y + $SRAM16K_HEIGHT + 6}]   ;# ~414
plog "### UNL STATUS ### : shared-RAM row span $SH_SPAN um (x0=$SH_X0), band top $RAM_BAND_TOP"

set i 0
foreach m {shbank0 shbank1 shbank2 shbank3 shbank4 shbank5 shbank6 shbank7} {
	placeInstance $m [expr {$SH_X0 + $i * ($SRAM16K_WIDTH + $SH_GAP)}] $SH_Y R0
	addHaloToBlock 2 2 2 2 $m
	incr i
}
cutRow

# --- Control band: full width, below the tiles (the ONLY std-cell region). ---
set CTRL_BAND_Y0 [expr {$RAM_BAND_TOP + 4}]        ;# ~418
set CTRL_BAND_Y1 [expr {$CTRL_BAND_Y0 + 170}]      ;# ~588
set TILE_Y0      [expr {$CTRL_BAND_Y1 + 4}]         ;# ~592
# alias for the fabric-fence block (before place_opt)
set FAB_BAND_Y0  $CTRL_BAND_Y0
set FAB_BAND_Y1  $CTRL_BAND_Y1
plog "### UNL STATUS ### : control band y $CTRL_BAND_Y0..$CTRL_BAND_Y1, tiles from y $TILE_Y0"

# ROM R90 (325 wide x 156 tall) + analog macros placed ALONG the control band;
# std cells (fabric + peripherals) fill the rows around them.
placeInstance rom0 40 [expr {$CTRL_BAND_Y0 + 6}] R90
addHaloToBlock 6 6 6 6 rom0
placeInstance por     420 [expr {$CTRL_BAND_Y0 + 6}] R0
addHaloToBlock 4 4 4 4 por
placeInstance dco0    560 [expr {$CTRL_BAND_Y0 + 6}] R0
addHaloToBlock 4 4 4 4 dco0
placeInstance dco1    700 [expr {$CTRL_BAND_Y0 + 6}] R0
addHaloToBlock 4 4 4 4 dco1
placeInstance irq_gf0 840  [expr {$CTRL_BAND_Y0 + 6}] R0
addHaloToBlock 4 4 4 4 irq_gf0
placeInstance irq_gf1 940  [expr {$CTRL_BAND_Y0 + 6}] R0
addHaloToBlock 4 4 4 4 irq_gf1
placeInstance irq_gf2 1040 [expr {$CTRL_BAND_Y0 + 6}] R0
addHaloToBlock 4 4 4 4 irq_gf2
cutRow

# --- 18-tile grid: 6 FULL-WIDTH cols x 3 rows. Column gap solved from the die
# width (~40 um) -> aligned columns => continuous vertical fan-in channels.
# 0 vertical row-gap (tile halos handle spacing). ---
set TILE_SIDE_MARGIN 30
set TILE_GRID_GAP [expr {($DESIGN_WIDTH - 2*$TILE_SIDE_MARGIN - $NCOLS*$TILE_W) / double($NCOLS - 1)}]
set TILE_X0 $TILE_SIDE_MARGIN
for {set row 0} {$row < $NROWS} {incr row} {
	for {set col 0} {$col < $NCOLS} {incr col} {
		set h [expr {$row * $NCOLS + $col}]
		set tx [expr {$TILE_X0 + $col * ($TILE_W + $TILE_GRID_GAP)}]
		set ty [expr {$TILE_Y0 + $row * $TILE_H}]
		placeInstance hart$h $tx $ty R0
		addHaloToBlock 4 4 4 4 hart$h
	}
}
cutRow
set GRID_TOP [expr {$TILE_Y0 + $NROWS * $TILE_H}]
plog "### UNL STATUS ### : placed 18 tiles (6x3 full-width, col gap [format %.1f $TILE_GRID_GAP]), grid top y=$GRID_TOP (ring ~2661)"
printStatus "Placed all macros"

# --- Chip pins: all on the BOTTOM edge (digital-only, north face empty) ---
set ALL_PINS [dbGet top.terms.name]
puts "Assigning [llength $ALL_PINS] pins to the bottom edge"
editPin -pin $ALL_PINS -side Bottom -layer 4 -spreadType side -spacing 2 -fixOverlap 1
printStatus "Placed chip pins (all bottom)"

################################################################################
# Power: full rectangular ring (all 4 sides -- no analog notch) + M7/M8 stripes
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
# Strap the macro PG pins (tiles expose M7/M8 PG pins in their LEF; banks/ROM/
# analog have their own PG pins) + the core-row follow pins.
sroute \
	-nets { VSS VDD } \
	-allowLayerChange 0 \
	-allowJogging 0 \
	-connect {blockPin corePin} \
	-blockPin useLef \
    -corePinWidth 0.3
# Jogging backstop for any macro PG pin the straight pass missed.
printStatus "Routing macro PG pins (jogging backstop)"
sroute \
	-nets { VSS VDD } \
	-connect { blockPin } \
	-blockPin useLef \
	-allowLayerChange 1 \
	-allowJogging 1 \
	-layerChangeRange { M3(3) M7(7) }

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
# Spurious clock-gating checks on the TIMER ClockMuxGlitchFree select legs
# (glitch-free by construction; gate names are genus-mapped -- catch-guarded so
# a resynth rename can't abort the run).
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

################################################################################
# v3: NO fabric fence. The full-width control band is the ONLY std-cell region
# (tiles = macros, RAM cut), so an EXCLUSIVE createFence on the fabric would
# leave the peripherals nowhere to place. place_opt spreads the arbiter / CLINT /
# router naturally across the band width -- their per-hart logic is wirelength-
# pulled toward each of the 18 tile columns above -- which is exactly the
# horizontal spread the v2 fence forced, but here for free and without starving
# the peripherals. The continuous ~40 um column channels carry the vertical drop.
################################################################################

place_opt_design
printStatus "Placement done"
# place_opt's trial route prints [NR-eGR] overflow -- that is the congestion
# signal to grep (v1 was 71% H; v2 must be far lower or the fence didn't help).

################################################################################
# Clock tree synthesis -- balances into the 18 tile clk pins (identical hardened
# tiles => identical internal insertion delay)
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
setDelayCalMode -SIAware true
setOptMode -holdTargetSlack 0.01
optDesign -postRoute -hold
setOptMode -holdTargetSlack 0

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
# Output files (top-only netlist/SDF: tile interiors come from the tile harden's
# ../hart_tile_argus/out/hart_tile_argus.{xsim.v,sdf} at gate-sim time)
################################################################################
streamOut \
    $OUTPUT_DIR/$BASENAME.gds2 \
    -libName WorkLib \
    -structureName $DESIGN_NAME \
    -stripes 1 \
    -units 1000 \
    -mode ALL \
    -merge [list ../hart_tile_argus/out/hart_tile_argus.gds2] \
    -mapFile ../shared/innovus2gds.map

printStatus "Writing SDF (top level)"
write_sdf $OUTPUT_DIR/$BASENAME.sdf

printStatus "Writing verilog for Xcelium (top level; hart_tile as leaf refs)"
saveNetlist \
    $OUTPUT_DIR/$BASENAME.xsim.v \
    -excludeCellInst ANTENNA2A10TH

saveDesign $DATABASE_DIR/$BASENAME.final.innovus -def -netlist -rc -tcon
toc
printStatus "MCU_ARGUS top assembly complete"
exit
