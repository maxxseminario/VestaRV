################################################################################
# Innnovus Script
################################################################################
 
################################################################################
# Design constants
################################################################################
 
# Load design constants and helpful tcl procedures.
source tcl/constants.tcl
source $SCRIPT_DIR/procedures.tcl

# Name of module, used for saving output reports and databases.
set DESIGN_NAME MCU

# Size of the entire design.
# 3 mm x 3 mm chip, pad ring is 155 um cut into each side, give 2 um of space on each side of the MCU so it does not bush up against the pads and cause DRC errors, working interior is 2690 um x 2690 um
# Size of general digital area, make strips extending up for routing to pads
set DESIGN_WIDTH 1186
set DESIGN_HEIGHT 686

# Power ring size
set POWER_RING_PATH_WIDTH	10.0
set POWER_RING_PATH_SPACING	4.0
set POWER_RING_OFFSET		0
set POWER_RING_WIDTH		[expr {($POWER_RING_PATH_WIDTH * 2) + ($POWER_RING_PATH_SPACING * 3)}]

# Power stripe size
set POWER_STRIPE_PATH_WIDTH		5.0
set POWER_STRIPE_PATH_SPACING	4.0
set POWER_STRIPE_SET_TO_SET		[expr {$STD_CELL_HEIGHT * 25}]
set POWER_STRIPE_WIDTH			[expr {($POWER_STRIPE_PATH_WIDTH * 2) + ($POWER_STRIPE_PATH_SPACING)}]

# Standard cell core area.
# CORE_SPACING is the distance from the edge of the design to the core of standard cells
set CORE_SPACING	1
set CORE_WIDTH		[expr {$DESIGN_WIDTH - ($CORE_SPACING * 2)}]
set CORE_HEIGHT		[expr {$DESIGN_HEIGHT - ($CORE_SPACING * 2)}]

# Potentiostat AFE Size 
set AFE_HEIGHT_SM  150
set AFE_HEIGHT_LG  210
set AFE_HEIGHT_TOT  [expr {$AFE_HEIGHT_SM + $AFE_HEIGHT_LG}]
set AFE_WIDTH_LG    400
set AFE_WIDTH_SM    350
set AFE_WIDTH_TOT   [expr {$AFE_WIDTH_LG + $AFE_WIDTH_SM}]
set PAD_ROUTE_W     47  
set PAD_ROUTE_H     30
set DPAD_NORTH_WIDTH      670
# Pad ROUTE W 91 for two vertical power stripes, 40 for one vertical power stripe


# Refresh the EDI window to make it look pretty while the script runs.
fit; redraw; update
tic

################################################################################
# Design import and setup
################################################################################
 
# Specify inital design files.
set init_verilog             "$GENUS_DIR/out/$DESIGN_NAME.genus.v"
set init_top_cell            "$DESIGN_NAME"
set init_pwr_net             "VDD"
set init_gnd_net             "VSS"
set init_mmmc_file           "$SCRIPT_DIR/viewdefinition.tcl"

# $INPUT_DIR/tsmc_cln65_a10_6X1Z_tech.new.lef \
# set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
# "$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef 
# TODO: need to find true 9M 6X1Z1U file for this kit...possibly not needed if
# Innovus doesn't use UTM or nearby metals for routing.
set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					$IP_DIR/rom_hvt_pg/rom_hvt_pg.lef \
					$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef \
                    $IC_DIR/abstracts/myshkin_abs/GlitchFilter/GlitchFilter.lef \
                    $IC_DIR/abstracts/myshkin_abs/PowerOnResetCheng/PowerOnResetCheng.lef \
                    $IC_DIR/abstracts/myshkin_abs/OscillatorCurrentStarved/OscillatorCurrentStarved.lef"

# User guide recommends uniquifying netlist
set init_design_uniquify 1
init_design

# Low power effort based on previous chips, but we might want to use multi-vt
# now since 65 nm supports it.  For low-power designs, anything but HVT (and
# maybe RVT) will be a disaster for leakage.
setDesignMode -process 65 -flowEffort standard -powerEffort low

# Use multiple CPUs.  Note that this makes the output non-deterministic, which
# becomes problematic on designs that are congested and may fail to converge
# to a valid layout.
#setMultiCpuUsage -acquireLicense 32 -localCpu max
# printStatus "Preparing 8 CPU cores..."
# setMultiCpuUsage -acquireLicense 8 -localCpu 8
printStatus "Preparing 8 CPU cores..."
setMultiCpuUsage -acquireLicense 8 -localCpu 8

# Define fill cells to allow optDesign and others to work around them.  Order
# of filler cells matters when using curly brace syntax.  This adds as many
# substrate contacts as possible, then fills in the rest with standard fill
# cells.  Note that cap cells are MOS gate-based and have leakage associated
# with them.
setFillerMode \
    -corePrefix FILLER \
    -core {FILLTIE128A10TH FILLTIE64A10TH FILLTIE32A10TH FILLTIE16A10TH FILLTIE8A10TH FILLTIE4A10TH FILLTIE2A10TH FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH}


# Solves IMPOPT-6080: OCV is required by optimization commands later on 
setAnalysisMode -analysisType onChipVariation -cppr both

# Connect power pins to global nets.  These nets, such as VDD/GND, are not
# explicitly in the netlist and must be connected here.
clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst * -module {} -autoTie -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -module {} -autoTie -verbose




################################################################################
# Die, I/O Pads and Core Layout
################################################################################

# Create the floorplan and specify outer dimensions. This overrides the .conf file.
# set BOTTOM_SPACING 18
set BOTTOM_SPACING 2
floorPlan \
    -site TSMC65ADV10TSITE \
    -s $CORE_WIDTH [expr {$CORE_HEIGHT - $BOTTOM_SPACING + $CORE_SPACING}] $CORE_SPACING $BOTTOM_SPACING $CORE_SPACING $CORE_SPACING


setPreference EnableRectilinearDesign 1
setObjFPlanPolygon cell {MCU} \
    0                                                       $DESIGN_HEIGHT \
    0                                                       0 \
    $DESIGN_WIDTH                                           0 \
    $DESIGN_WIDTH                                           $DESIGN_HEIGHT \
    [expr {$DESIGN_WIDTH - $PAD_ROUTE_W}]                   $DESIGN_HEIGHT \
    [expr {$DESIGN_WIDTH - $PAD_ROUTE_W}]                   [expr {$DESIGN_HEIGHT - $AFE_HEIGHT_LG - $PAD_ROUTE_H}] \
    [expr {$DESIGN_WIDTH - $PAD_ROUTE_W - $AFE_WIDTH_LG}]   [expr {$DESIGN_HEIGHT - $AFE_HEIGHT_LG - $PAD_ROUTE_H}] \
    [expr {$DESIGN_WIDTH - $PAD_ROUTE_W - $AFE_WIDTH_LG}]   [expr {$DESIGN_HEIGHT - $AFE_HEIGHT_SM - $PAD_ROUTE_H}] \
    [expr {$DESIGN_WIDTH - $PAD_ROUTE_W - $AFE_WIDTH_TOT}]  [expr {$DESIGN_HEIGHT - $AFE_HEIGHT_SM - $PAD_ROUTE_H}] \
    [expr {$DESIGN_WIDTH - $PAD_ROUTE_W - $AFE_WIDTH_TOT}]  [expr {$DESIGN_HEIGHT - $PAD_ROUTE_H}] \
    $DPAD_NORTH_WIDTH                                       [expr {$DESIGN_HEIGHT - $PAD_ROUTE_H}] \
    $DPAD_NORTH_WIDTH                                        $DESIGN_HEIGHT \



# # Create a hard placement blockage in a specific area
# createPlaceBlockage -type hard -box {[expr {$DESIGN_WIDTH - $PAD_ROUTE_W - $AFE_WIDTH_LG}]   [expr {$DESIGN_HEIGHT - $AFE_HEIGHT_LG - $PAD_ROUTE_H}] [expr {$DESIGN_WIDTH - $PAD_ROUTE_W - $AFE_WIDTH_TOT}]  [expr {$DESIGN_HEIGHT - $AFE_HEIGHT_SM - $PAD_ROUTE_H}]}

# # # Or with a name for easier management
# # createPlaceBlockage -type hard -box {100 200 300 400} -name "my_blockage_area"

# # # For soft blockage (discourages but allows placement if needed)
# # createPlaceBlockage -type soft -box {x1 y1 x2 y2}


# fit; redraw; update

# Set IP sizes (find width and height in the spec PDFs, *_RING_WIDTH is the width around the IP that should not have cells placed inside on all sides)
# set MEM_EDGE_SPACING	[expr {2 * $BOTTOM_SPACING}]
set MEM_EDGE_SPACING	10
set MEM_TO_MEM_SPACING	4

set ROM_WIDTH			156.525
set ROM_HEIGHT			325.055
set ROM_RING_WIDTH		9



# From Sam's, tall skinny compiiled ram
# set SRAM16K_WIDTH		319.650
# set SRAM16K_HEIGHT		383.085
# set SRAM16K_RING_WIDTH	0
# set SRAM8K_WIDTH		179.72
# set SRAM8K_HEIGHT		418.46
# set SRAM8K_RING_WIDTH	0

set SRAM16K_WIDTH		1126.050
set SRAM16K_HEIGHT		121.470
set SRAM16K_RING_WIDTH	0

# Short and plump 8KSRAM
set SRAM8K_WIDTH		319.650
set SRAM8K_HEIGHT		208.675
set SRAM8K_RING_WIDTH	0

set SRAM1K_WIDTH		179.72
set SRAM1K_HEIGHT		96.37
set SRAM1K_RING_WIDTH	0


# Place memory blocks

set BootROM_X	[expr {$MEM_EDGE_SPACING}] 
set BootROM_Y	[expr {$DESIGN_HEIGHT - $ROM_WIDTH - $MEM_EDGE_SPACING}]
placeInstance rom0 $BootROM_X $BootROM_Y R90
addHaloToBlock \
    [expr {$ROM_RING_WIDTH}] \
    [expr {0 + ($STD_CELL_HEIGHT * 1)}] \
    [expr {0 + ($STD_CELL_HEIGHT * 1)}] \
    [expr {$ROM_RING_WIDTH}] \
    rom0
cutRow


set SRAM01_X	[expr {$DESIGN_WIDTH/2 - $SRAM16K_WIDTH/2}] 
set SRAM01_Y	[expr {$MEM_EDGE_SPACING}]
placeInstance ram1 $SRAM01_X $SRAM01_Y MX
addHaloToBlock \
    [expr {$SRAM01_X + $CORE_SPACING}] \
    [expr {$SRAM16K_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] \
    [expr {$SRAM16K_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] \
    [expr {$SRAM16K_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] \
    ram1
cutRow
# Replace the existing addHaloToBlock for ram1 with:
# addHaloToBlock \
#     [expr {$SRAM16K_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] \
#     [expr {$SRAM16K_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] \
#     [expr {$MEM_EDGE_SPACING}] \
#     [expr {$SRAM16K_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] \
#     ram1
# cutRow

set SRAM00_X	[expr {$SRAM01_X + $CORE_SPACING}]
set SRAM00_Y	[expr {$SRAM01_Y + $SRAM16K_HEIGHT + $MEM_TO_MEM_SPACING}]
placeInstance ram0 $SRAM00_X $SRAM00_Y MX
addHaloToBlock \
    [expr {$SRAM01_X}] \
    [expr {$SRAM16K_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] \
    [expr {$SRAM16K_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] \
    [expr {$SRAM16K_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] \
    ram0
cutRow


# Place POR Circuit 

set POR_WIDTH		026.650
set POR_HEIGHT		011.790
set POR_RING_WIDTH	0

# WARNING: Make sure this is placed where the VDD and VSS pins will be connected by sroute!
set POR_X	[expr {$CORE_SPACING + ($POWER_STRIPE_SET_TO_SET * 1) - ($POR_WIDTH * 0.5)}]
set POR_Y	[expr {400} - $POWER_STRIPE_SET_TO_SET]
placeInstance por $POR_X $POR_Y MX 
addHaloToBlock [expr {$POR_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] [expr {$POR_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] [expr {$POR_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] [expr {$POR_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] por
cutRow


# Place IRQ Deglitchers 
set IRQ_WIDTH		031.200
set IRQ_HEIGHT		018.870
set IRQ_RING_WIDTH	0

set IRQ_Y 300


# WARNING: Make sure this is placed where the VDD and VSS pins will be connected by sroute!
set IRQ0_X	[expr {$CORE_SPACING + ($POWER_STRIPE_SET_TO_SET * 9) - ($IRQ_WIDTH * 0.5)}]
set IRQ0_Y	[expr {$IRQ_Y}]
placeInstance irq_gf0 $IRQ0_X $IRQ0_Y R0
addHaloToBlock [expr {$IRQ_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] [expr {$IRQ_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] [expr {$IRQ_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] [expr {$IRQ_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] irq_gf0
cutRow

# TODO: Place these
set IRQ1_X	[expr {$IRQ0_X}]
set IRQ1_Y	[expr {$IRQ_Y + $POWER_STRIPE_SET_TO_SET}]
placeInstance irq_gf1 $IRQ1_X $IRQ1_Y R0
addHaloToBlock [expr {$IRQ_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] [expr {$IRQ_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] [expr {$IRQ_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] [expr {$IRQ_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] irq_gf1
cutRow

set IRQ2_X	[expr {$IRQ0_X}]
set IRQ2_Y	[expr {$IRQ_Y + $POWER_STRIPE_SET_TO_SET*2}]
placeInstance irq_gf2 $IRQ2_X $IRQ2_Y R0
addHaloToBlock [expr {$IRQ_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] [expr {$IRQ_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] [expr {$IRQ_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] [expr {$IRQ_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] irq_gf2
cutRow


# Place current starved oscillators (DCOs)
set DCO_WIDTH		058.410
set DCO_HEIGHT		037.390
set DCO_NOBLOCK_HEIGHT	4 
set DCO_RING_WIDTH	0

set DCO_Y 410


# WARNING: Make sure this is placed where the VDD and VSS pins will be connected by sroute!
set DCO0_X		[expr {$CORE_SPACING + ($POWER_STRIPE_SET_TO_SET * 3) - ($DCO_WIDTH * 0.5)}]
set DCO0_Y		[expr {$DCO_Y}]
placeInstance dco0 $DCO0_X $DCO0_Y R0
addHaloToBlock [expr {$DCO_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] [expr {$DCO_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] [expr {$DCO_RING_WIDTH + ($STD_CELL_HEIGHT * 0.45)}] [expr {$DCO_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] dco0
cutRow

set DCO1_X		[expr {$CORE_SPACING + ($POWER_STRIPE_SET_TO_SET * 5) - ($DCO_WIDTH * 0.5)}]
set DCO1_Y		[expr {$DCO_Y}]
placeInstance dco1 $DCO1_X $DCO1_Y R0
addHaloToBlock [expr {$DCO_RING_WIDTH + ($STD_CELL_HEIGHT * 0.45)}] [expr {$DCO_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] [expr {$DCO_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] [expr {$DCO_RING_WIDTH + ($STD_CELL_HEIGHT * 1)}] dco1
cutRow


printStatus "Placed memory and abstract blocks"

fit; redraw; update;
# suspend

# Add IO pins.
loadIoFile $INPUT_DIR/$DESIGN_NAME.io
fit; redraw; update;

printStatus "Placed I/O pins"
suspend
################################################################################
# Power supply rings and stripes
################################################################################


printStatus "Adding power rings"

# Add power ring.
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

# Add VDD and VSS labels
add_text -label VDD -layer M8 -pt [list [expr {$POWER_RING_PATH_SPACING + ($POWER_RING_PATH_WIDTH * 0.5)}] [expr {$POWER_RING_PATH_SPACING + ($POWER_RING_PATH_WIDTH * 0.5)}]]
add_text -label VSS -layer M8 -pt [list [expr {($POWER_RING_PATH_SPACING * 2) + ($POWER_RING_PATH_WIDTH * 1.5)}] [expr {($POWER_RING_PATH_SPACING * 2) + ($POWER_RING_PATH_WIDTH * 1.5)}]]

# Add power stripes
setAddStripeMode \
    -remove_floating_stripe_over_block true \
    -trim_antenna_back_to_shape core_ring \
	-stacked_via_top_layer M8 \
    -extend_to_closest_target ring
	#-optimize_stripe_for_routing_track shift
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
	-stop_offset $POWER_STRIPE_PATH_SPACING \
	-area_blockage [list \
		[list [expr $DCO0_X] [expr {$DCO0_Y + $DCO_NOBLOCK_HEIGHT}] [expr {$DCO0_X + $DCO_WIDTH}] [expr {$DCO0_Y + $DCO_HEIGHT}]] \
		[list [expr $DCO1_X] [expr {$DCO1_Y + $DCO_NOBLOCK_HEIGHT}] [expr {$DCO1_X + $DCO_WIDTH}] [expr {$DCO1_Y + $DCO_HEIGHT}]] \
		]

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
	-stop_offset $POWER_STRIPE_PATH_SPACING \
	-area_blockage [list \
		[list [expr $DCO0_X] [expr {$DCO0_Y + $DCO_NOBLOCK_HEIGHT}] [expr {$DCO0_X + $DCO_WIDTH}] [expr {$DCO0_Y + $DCO_HEIGHT}]] \
		[list [expr $DCO1_X] [expr {$DCO1_Y + $DCO_NOBLOCK_HEIGHT}] [expr {$DCO1_X + $DCO_WIDTH}] [expr {$DCO1_Y + $DCO_HEIGHT}]] \
		]

# Fix the antenna violations created by creating blockages in the power stripes
editTrim -all

setCheckMode -globalNet true -io true -route true -tapeOut true



# Route power signals to the standard cells.
printStatus "Routing power rings"
# The corePinMaxViaScale parameter can help fix Innovus DRC errors generated by the vias on the power nets
#setSrouteMode \
#	-corePinMaxViaScale "50 10"
sroute \
	-nets { VSS VDD } \
	-allowLayerChange 0 \
	-allowJogging 0 \
	-connect corePin \
    -corePinWidth 0.3
#	-corePinMaxViaWidth 80 

# Fix any power routing DRC issues.
verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.preplace.rpt
fixVia -short
fixVia -minCut
fixVia -minStep

fit; redraw; update
# suspend

# This is a good place to #suspend and check for violations.
# Violations from power rails terminating ("open" violations) seem to be benign
# Other geometry violations need to be resolved. Options: modify the placement of the ROM, RAM, and other instances; change the spacing of the power stripes
printStatus "Routed power rings. Please check that VDD and VSS connections are good on ROMs, RAMs, and other abstract instances."
suspend

################################################################################
# Routing blockages
################################################################################
 
# printStatus "Placing routing blockages"

# # Prevent routing on layers used for power stripes
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -layer 8

# # Prevent routing on lower levels of the instantiated blocks
createRouteBlk -box $IRQ0_X $IRQ0_Y [expr {$IRQ0_X + $IRQ_WIDTH}] [expr {$IRQ0_Y + $IRQ_HEIGHT}] -layer 1
createRouteBlk -box $IRQ1_X $IRQ1_Y [expr {$IRQ1_X + $IRQ_WIDTH}] [expr {$IRQ1_Y + $IRQ_HEIGHT}] -layer 1
createRouteBlk -box $IRQ2_X $IRQ2_Y [expr {$IRQ2_X + $IRQ_WIDTH}] [expr {$IRQ2_Y + $IRQ_HEIGHT}] -layer 1
createRouteBlk -box $POR_X $POR_Y   [expr {$POR_X + $POR_WIDTH}] [expr {$POR_Y + $POR_HEIGHT}] -layer {1 2}

# Prevent routing on layers 7 and 8 in the DCOs
createRouteBlk -box $DCO0_X [expr {$DCO0_Y + $DCO_NOBLOCK_HEIGHT}] [expr {$DCO0_X + $DCO_WIDTH}] [expr {$DCO0_Y + $DCO_HEIGHT}] -layer all
createRouteBlk -box $DCO1_X [expr {$DCO1_Y + $DCO_NOBLOCK_HEIGHT}] [expr {$DCO1_X + $DCO_WIDTH}] [expr {$DCO1_Y + $DCO_HEIGHT}] -layer all


## At this point the design is ready for standard cell placement.
#saveDesign $DATABASE_DIR/$DESIGN_NAME.preplace.innovus -def -netlist -rc -tcon
#suspend

################################################################################
# Standard cell placement
################################################################################

# ARM standard cells do not include well taps, so these need to be placed and
# fixed before P&R.  Use the smallest cell available.  Rule OD.L.2 specifies 25
# um max spacing between cells, so add a little margin to this value.

addWellTap \
    -cell FILLTIE2A10TH \
    -cellInterval 24 \
    -fixedGap \
    -checkerBoard \
    -prefix WELLTAP

place_opt_design; fit; redraw; update

################################################################################
# Clock tree synthesis
################################################################################

add_ndr -name CTS_2W2S -width {M2:M6 0.4} -generate_via -spacing {M2:M6 0.42}
add_ndr -name CTS_2W1S -width {M2:M6 0.4} -generate_via -spacing {M2:M6 0.21}

create_route_type -name top_rule   -non_default_rule CTS_2W2S -top_preferred_layer M6 -bottom_preferred_layer M5 -shield_net VSS -bottom_shield_layer M5
create_route_type -name trunk_rule -non_default_rule CTS_2W2S -top_preferred_layer M4 -bottom_preferred_layer M3 -shield_net VSS -bottom_shield_layer M3
create_route_type -name leaf_rule  -non_default_rule CTS_2W1S -top_preferred_layer M3 -bottom_preferred_layer M2

set_ccopt_property -net_type top   route_type top_rule
set_ccopt_property -net_type trunk route_type trunk_rule
set_ccopt_property -net_type leaf  route_type leaf_rule

# Use top rules for portions of tree serving this amount of downstream gates.
set_ccopt_property routing_top_min_fanout 10000

set_ccopt_property buffer_cells   {BUFX0P7BA10TH BUFX0P8BA10TH BUFX11BA10TH BUFX13BA10TH BUFX16BA10TH BUFX1BA10TH BUFX1P2BA10TH BUFX1P4BA10TH BUFX1P7BA10TH BUFX2BA10TH BUFX2P5BA10TH BUFX3BA10TH BUFX3P5BA10TH BUFX4BA10TH BUFX5BA10TH BUFX6BA10TH BUFX7P5BA10TH BUFX9BA10TH}
set_ccopt_property inverter_cells {INVX0P5BA10TH INVX0P6BA10TH INVX0P7BA10TH INVX0P8BA10TH INVX11BA10TH INVX13BA10TH INVX16BA10TH INVX1BA10TH INVX1P2BA10TH INVX1P4BA10TH INVX1P7BA10TH INVX2BA10TH INVX2P5BA10TH INVX3BA10TH INVX3P5BA10TH INVX4BA10TH INVX5BA10TH INVX6BA10TH INVX7P5BA10TH INVX9BA10TH}
set_ccopt_property delay_cells {DLY2X0P5MA10TH DLY4X0P5MA10TH}
set_ccopt_property use_inverters true
set_ccopt_property target_max_trans 400ps

create_ccopt_clock_tree_spec

ccopt_design; fit; redraw; update
optDesign -postCTS -hold; 
fit; redraw; update

timeDesign -postCTS -expandedViews -outDir $REPORT_DIR/$DESIGN_NAME.timeDesign.postcts
report_ccopt_clock_trees -file $REPORT_DIR/$DESIGN_NAME.report_ccopt_clock_trees.postcts
report_ccopt_skew_groups -file $REPORT_DIR/$DESIGN_NAME.report_ccopt_skew_groups.postcts

# suspend



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
fit; redraw; update

optDesign -postRoute -setup -hold
fit; redraw; update

# Fix DRC violations
verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.postroute.rpt
ecoRoute -fix_drc

verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.postroute.rpt
ecoRoute -fix_drc

# If DRC errors are not fixed by now, rip them up and re-route them
verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.postroute.rpt
editDeleteViolations
routeDesign
verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.postroute.rpt

# Signoff DRC check
streamOut \
    $OUTPUT_DIR/$DESIGN_NAME.gds2 \
    -libName WorkLib \
    -structureName $DESIGN_NAME \
    -stripes 1 \
    -units 1000 \
    -mode ALL \
    -mapFile $INPUT_DIR/innovus2gds.map

#puts "Running signoff DRC with Calibre..."
#exec tcl/signoff_drc.sh


verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.postroute.rpt

# Finish up
deleteAllRouteBlks
addFiller



################################################################################
# Signoff Reports
################################################################################

#setMultiCpuUsage -localCpu 8

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

#printStatus "verifyMetalDensity"
#verifyMetalDensity \
#    -layers { M1 M2 M3 M4 M5 M6 M7 M8 } \
#    -detailed \
#    -report $REPORT_DIR/$DESIGN_NAME.verifyMetalDensity.signoff.rpt
fit; redraw; update                  

# And finally generate sign-off timing information
# Switch to proper analysis mode for timing signoff.
setDelayCalMode \
    -SIAware false
setAnalysisMode \
    -analysisType onChipVariation \
    -cppr both 
printStatus "timeDesign"
timeDesign \
    -si \
    -signoff \
    -outdir $REPORT_DIR/$DESIGN_NAME.timeDesign.signoff.rpt

printStatus "report_clock_timing"
setAnalysisMode \
    -cppr both
report_clock_timing \
    -type skew \
    -nworst 10 > $REPORT_DIR/$DESIGN_NAME.report_clock_timing.skew.signoff.rpt

printStatus "report_timing"
report_timing -net > $REPORT_DIR/$DESIGN_NAME.report_timing.signoff.rpt
  
printStatus "report_timing (hold)"
setAnalysisMode \
    -checkType hold \
    -skew true
report_timing > $REPORT_DIR/$DESIGN_NAME.report_timing.hold.signoff.rpt
report_timing -machine_readable -max_paths 10000 -max_slack 0.75 -path_exceptions all -early > $REPORT_DIR/$DESIGN_NAME.report_timing.hold.signoff.mtarpt

printStatus "report_timing (setup)"
setAnalysisMode \
    -checkType setup \
    -skew true
report_timing > $REPORT_DIR/$DESIGN_NAME.report_timing.setup.signoff.rpt
report_timing -machine_readable -max_paths 10000 -max_slack 0.75 -path_exceptions all -late > $REPORT_DIR/$DESIGN_NAME.report_timing.setup.signoff.mtarpt

printStatus "reportClockTree"
reportClockTree \
    -postRoute \
    -num 3 \
    -localSkew \
    -report $REPORT_DIR/$DESIGN_NAME.reportClockTree.signoff.rpt

printStatus "checkPlace"
checkPlace \
    -ignoreOutOfCore \
    -noPreplaced \
    $REPORT_DIR/$DESIGN_NAME.checkPlace.signoff.rpt

printStatus "reportGateCount"
reportGateCount \
    -level 2 \
    -outfile $REPORT_DIR/$DESIGN_NAME.reportGateCount.signoff.rpt

printStatus "summaryReport"
summaryReport \
    -noHtml \
    -outfile $REPORT_DIR/$DESIGN_NAME.summaryReport.signoff.rpt

# This command executes checkNetlist and checkPlacement, leaving 
# checknetlist.rpt and checkPlacement.rpt in the run directory.
printStatus "checkDesign"
checkDesign \
    -all \
    -noHtml \
    -outfile $REPORT_DIR/$DESIGN_NAME.checkDesign.signoff.rpt

saveDesign $DATABASE_DIR/$DESIGN_NAME.signoff.innovus -def -netlist -rc -tcon

################################################################################
# Output files
################################################################################

# Perform design prep for P&R in Virtuoso
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -spacing 0.0 -layer 1
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -spacing 0.0 -layer 2
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -spacing 0.0 -layer 3
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -spacing 0.0 -layer 4
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -spacing 0.0 -layer 5
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -spacing 0.0 -layer 6
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -spacing 0.0 -layer 7
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -spacing 0.0 -layer 8

# Save the GDSII geometry for Virtuoso.
streamOut \
    $OUTPUT_DIR/$DESIGN_NAME.gds2 \
    -libName WorkLib \
    -structureName $DESIGN_NAME \
    -stripes 1 \
    -units 1000 \
    -mode ALL \
    -mapFile $INPUT_DIR/innovus2gds.map
 
# Save the SDF timing for the post-layout simulation.
printStatus "Writing SDF file"
write_sdf $OUTPUT_DIR/$DESIGN_NAME.sdf
write_sdf $OUTPUT_DIR/$DESIGN_NAME.explicit.sdf -recompute_delay_calc

# Save a verilog file for post-layout simulation.  To speed this up, leave it
# hierarchical and don't include any power/ground nets or physical instances.
# Also remove the antenna cells, which are not classified as physical cells by
# the command.
printStatus "Writing verilog file for Xcelium"
saveNetlist \
    $OUTPUT_DIR/$DESIGN_NAME.xsim.v \
    -excludeCellInst ANTENNA2A10TH
 
# Save a verilog file for LVS.  To this end, include power/ground nets.
printStatus "Writing verilog file for LVS"
saveNetlist \
    -excludeLeafCell $OUTPUT_DIR/$DESIGN_NAME.lvs.v \
    -excludeCellInst "FILLTIE128A10TH FILLTIE64A10TH FILLTIE32A10TH FILLTIE16A10TH FILLTIE8A10TH FILLTIE4A10TH FILLTIE2A10TH FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH" \
    -flat \
    -phys

# Save an interface logic model for use during top-level timing.  This contains
# accurate timing information for the design.
createInterfaceLogic \
    -hold \
    -dir $OUTPUT_DIR/$DESIGN_NAME.ilm

# Save an LEF abstract for top-level routing.  This includes pins and blockages.
# If extraction is up-to-date, it also includes antenna geometries.
lefOut \
    -StripePin \
    -PGpinLayers 2 3 \
    -specifyTopLayer 3 \
    $OUTPUT_DIR/$DESIGN_NAME.lef
   
################################################################################
# End of Encounter Digital Implementation Script
################################################################################
 
saveDesign $DATABASE_DIR/$DESIGN_NAME.final.innovus -def -netlist -rc -tcon 
toc
set total_run_time [getHMS $START_TIME $STOP_TIME]
printStatus "Script complete"
exec echo "Innovus run is complete. Please check atlas." | \
	# mail -s "Innovus run is complete. Run time: $total_run_time" mseminario2@huskers.unl.edu
#exit
