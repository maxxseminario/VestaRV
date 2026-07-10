################################################################################
# Innovus script -- MCU_MP TOP-LEVEL ASSEMBLY (M14 physical flow; M16 rework)
#
# Hierarchical assembly: the four hart instances (hart0-3) are the HARDENED
# U-shaped hart_tile block (660 x 1050 bbox, top-center 500 x 450 analog
# notch) -- physical footprint from out/hart_tile.lef, timing from the
# per-corner ETMs out/hart_tile.etm_{ss,ff}.lib. Control plane (arbiter/
# CLINT/router/mutex/periph/system0 + rom0 + analog blocks) is placed and
# routed here, and top-level CTS balances the clock into the four tile clk
# pins.
#
# M17 rework: SARADC/AFE are gone from the design (digital-only), so NO analog
# signal pins exist -- EVERY chip pin lands on the BOTTOM edge and the north
# face is signal-free. That frees the tile row to pack tight: 3 um inter-tile
# gaps (was 40 um, only ever wide for the retired analog-pin channels) and
# 20 um die margins shrink the die to 2689 x 1700 (fits the M15 pad-ring
# interior of 2690). The 500 x 450 notch windows are kept as pure analog
# reserve (potentiostat drop-in at Virtuoso); taller tiles absorb the old
# dead band between the RAM row and the tile bottoms.
#
# Netlist: in/MCU_MP_hier.pnr.v = out-of-genus MCU_MP_hier.genus.v with any
# empty `module hart_tile` blackbox stub STRIPPED (prep_top_netlist.sh) so
# innovus binds hart_tile to the LEF macro, not to an empty module.
#
# Floorplan (die 2689 x 1700), the potentiostat-array arrangement:
#   TOP:    a row of 4 U-tiles, mirror-symmetric about the chip's vertical
#           centerline (hart0/1 R0, hart2/3 MY), tile tops flush with the
#           die top so each tile's analog notch opens onto the TOP edge --
#           the analog pads live there at Virtuoso chip assembly. The 4
#           notch windows are hard placement + full-stack routing keep-outs
#           up to the die edge. Analog-facing MCU pins (BIAS_*, dsadc_*,
#           saradc_*, atp_*, adc_*, dac/bias enables) are placed on the top
#           edge over the 3 inter-tile gaps + 2 die margins -- the only
#           vertical channels past the tile row -- and drop straight to the
#           control plane.
#   MIDDLE: control-plane band (rows) with the boot ROM + POR/DCO/glitch-
#           filter analog blocks; all digital chip pins on the BOTTOM edge.
#   BOTTOM: the shared RAM -- shbank0-3 + npuram0, five near-square
#           AREA-OPTIMIZED mux-8 sram1p16k macros (319.65 x 383.085) in a
#           centered row at the very bottom of the die.
# Top power ring side is SKIPPED (analog windows must stay metal-free);
# left/right M7 + bottom M8 ring segments + the M7/M8 stripe grid power the
# core, and the tile/SRAM PG pins are strapped by sroute as in M14.
################################################################################

source tcl/constants.tcl
source $SCRIPT_DIR/procedures.tcl

set DESIGN_NAME MCU
set BASENAME    MCU_MP

set DESIGN_WIDTH  2689
set DESIGN_HEIGHT 1700

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

# --- Tile geometry (must match tcl/hart_tile.innovus.tcl) ---
set TILE_W        660
set TILE_H        1050
set TILE_NOTCH_X0 80
set TILE_NOTCH_X1 580
set TILE_NOTCH_Y0 600

# --- The tile row: 4x U-shaped hart_tile flush with the die top, mirror-
# symmetric about x = DIE_W/2 (hart0/1 R0, hart2/3 MY; the notch is centered
# in the tile so the mirrored windows stay put). M17: 3 um inter-tile gaps
# (was 40 um). The 40 um only ever existed to route the analog pins down past
# the tile row; those pins are gone (SARADC/AFE removed, north face empty), so
# nothing needs a vertical channel here. 3 um just clears tile-to-tile spacing
# DRC -- the 10 um tile halos already overlap the gap, so no cells place in
# it. 20 um die margins clear the left/right M7 power ring. ---
set TILE_GAP     3
set TILE_X0      20
set TILE_PITCH   [expr {$TILE_W + $TILE_GAP}]
set TILE_Y       [expr {$DESIGN_HEIGHT - $CORE_SPACING - $TILE_H}]
for {set h 0} {$h < 4} {incr h} {
	set TILE_X [expr {$TILE_X0 + $h * $TILE_PITCH}]
	set ORIENT [expr {$h < 2 ? "R0" : "MY"}]
	placeInstance hart$h $TILE_X $TILE_Y $ORIENT
	addHaloToBlock 10 10 10 10 hart$h
}
printStatus "Placed tile row (tops flush with die top)"

# --- Analog notch windows: per tile, keep-out from the notch floor to the
# die top edge. Hard placement blockage + all-layer route blockage; rows cut
# below. The analog potentiostat chains drop in here at Virtuoso assembly. ---
set WINDOW_BOXES {}
for {set h 0} {$h < 4} {incr h} {
	set TILE_X [expr {$TILE_X0 + $h * $TILE_PITCH}]
	set WX0 [expr {$TILE_X + $TILE_NOTCH_X0}]
	set WX1 [expr {$TILE_X + $TILE_NOTCH_X1}]
	set WY0 [expr {$TILE_Y + $TILE_NOTCH_Y0}]
	set WY1 $DESIGN_HEIGHT
	lappend WINDOW_BOXES [list $WX0 $WY0 $WX1 $WY1]
	createPlaceBlockage -type hard -name analog_win$h \
		-box [list $WX0 $WY0 $WX1 $WY1]
	createRouteBlk -name analog_win_rt$h \
		-box [list $WX0 $WY0 $WX1 $WY1] \
		-layer {1 2 3 4 5 6 7 8}
	cutRow -area [list $WX0 $WY0 $WX1 $WY1]
}
cutRow
printStatus "Reserved 4 analog notch windows (500 x 451 to the die edge)"

# --- Above the notch-floor line the die holds only the 4 notch windows, the
# tile fingers (tile macro) and the 3 um inter-tile gaps -- none placeable.
# Keep it cell-free with a full-width blockage so no stray row survives beside
# a window and orphans a follow-pin rail. ---
set NOTCH_FLOOR_Y [expr {$TILE_Y + $TILE_NOTCH_Y0}]
createPlaceBlockage -type hard -name top_band \
	-box [list 0 $NOTCH_FLOOR_Y $DESIGN_WIDTH $DESIGN_HEIGHT]
cutRow -area [list 0 $NOTCH_FLOOR_Y $DESIGN_WIDTH $DESIGN_HEIGHT]

# M17: the per-channel row cuts BESIDE the tiles are retired. At 40 um the
# inter-tile gaps held rows on floating rails (v3: 1276 orphaned PG pieces);
# at 3 um the 10 um tile halos overlap the gap entirely and the 20 um margins
# are all power ring + halo -- there is no placeable silicon beside the tiles
# to cut. Nothing to route down here either (north face is signal-free).

# --- Shared RAM: shbank0-3 + npuram0, five square sram1p16k in a centered
# row at the very bottom of the die ---
set SRAM16K_WIDTH		319.650
set SRAM16K_HEIGHT		383.085
set SH_GAP   20
set SH_Y     40
set SH_SPAN  [expr {5 * $SRAM16K_WIDTH + 4 * $SH_GAP}]
set SH_X0    [expr {($DESIGN_WIDTH - $SH_SPAN) / 2.0}]
set i 0
foreach m {shbank0 shbank1 shbank2 shbank3 npuram0} {
	placeInstance $m [expr {$SH_X0 + $i * ($SRAM16K_WIDTH + $SH_GAP)}] $SH_Y R0
	addHaloToBlock 4 4 4 4 $m
	incr i
}
cutRow
# shared RAM row top = 40 + 383.085 = ~423
# The 12 um placeable slivers between adjacent RAM macros only meet a
# vertical M7 stripe by 50 um-pitch luck -- rows there otherwise carry
# FLOATING follow-pin rails (v4: 481 orphaned PG pieces, with live sh_wdata
# buffers on dead rails). Wire-only, like the tile channels.
for {set g 0} {$g < 4} {incr g} {
	set gx0 [expr {$SH_X0 + ($g + 1) * $SRAM16K_WIDTH + $g * $SH_GAP}]
	createPlaceBlockage -type hard -name ramgap$g \
		-box [list $gx0 [expr {$SH_Y - 4}] [expr {$gx0 + $SH_GAP}] [expr {$SH_Y + $SRAM16K_HEIGHT + 4}]]
	cutRow -area [list $gx0 [expr {$SH_Y - 4}] [expr {$gx0 + $SH_GAP}] [expr {$SH_Y + $SRAM16K_HEIGHT + 4}]]
}

# --- Control-plane band (rows y ~448..~848): boot ROM (R90: 325.055 wide x
# 156.525 tall) + POR, 2x DCO, 3x IRQ glitch filter ---
set ROM_X 60
set ROM_Y 470
placeInstance rom0 $ROM_X $ROM_Y R90
addHaloToBlock 9 4 4 9 rom0
placeInstance por     450 470 R0
addHaloToBlock 4 4 4 4 por
placeInstance dco0    550 470 R0
addHaloToBlock 4 4 4 4 dco0
placeInstance dco1    670 470 R0
addHaloToBlock 4 4 4 4 dco1
# GlitchFilter PG pins are full-width M3 strips (VSS y 1.23-2.23, VDD y
# 16.105-17.105) — they connect ONLY where a vertical M7 stripe pair crosses
# the macro (the Myshkin script carries the same warning and centers each
# irq_gf on a SET_TO_SET multiple). gf0/gf1 at 790/880 straddle the pairs at
# ~800/~900; gf2 at 970 (span 970-1001) missed the ~1000-1014 pair by 8 um —
# unconnected VSS terminal at signoff (M17b). 991 centers it on that pair.
# The jogging block-pin sroute pass below is the belt-and-braces backstop.
placeInstance irq_gf0 790 470 R0
addHaloToBlock 4 4 4 4 irq_gf0
placeInstance irq_gf1 880 470 R0
addHaloToBlock 4 4 4 4 irq_gf1
placeInstance irq_gf2 991 470 R0
addHaloToBlock 4 4 4 4 irq_gf2
cutRow

printStatus "Placed tiles + shared RAM row + ROM + analog blocks"

# --- Chip pins. M17: SARADC/AFE are gone, so there are NO analog-facing pins
# and nothing that must reach the top edge. EVERY pin lands on the BOTTOM
# edge -- the north face is signal-free, which is exactly what lets the tile
# row pack to 3 um gaps (no inter-tile routing channels needed). The only
# top-facing outputs left, DCO0/1_BIAS, are clock-oscillator bias words that
# drive the DCO blocks in the control band below -- they belong on the bottom
# edge with everything else. ---
set ALL_PINS [dbGet top.terms.name]
puts "Assigning [llength $ALL_PINS] pins to the bottom edge (north face empty)"
editPin -pin $ALL_PINS -side Bottom -layer 4 -spreadType side -spacing 2 -fixOverlap 1
printStatus "Placed chip pins (all bottom; north face signal-free)"

################################################################################
# Power. NO top ring segment -- it would cross the analog windows; the
# left/right M7 + bottom M8 segments and the stripe grid carry the current.
################################################################################
printStatus "Adding power ring/stripes"
addRing \
    -nets {VDD VSS} \
    -type core_rings \
    -follow io \
    -skip_side {top} \
    -layer {top M8 bottom M8 left M7 right M7} \
    -width $POWER_RING_PATH_WIDTH \
    -spacing $POWER_RING_PATH_SPACING \
    -offset $POWER_RING_PATH_SPACING \
    -center 0 -extend_corner {} -threshold 0 -jog_distance 0 \
    -snap_wire_center_to_grid None

# M17b: -skip_side {top} skips only the DIE-top segments -- the ring engine
# still CLOSES the loop by detouring under each analog window: four M8
# segments per net at y ~1227/1241 straight across the tiles, 0.5 um from
# the tile M7/M8 LEF blockage (= the long-standing "20 SameNet" signoff
# viols; their corner via7Arrays are the M7 ones). Neither the stripe area
# nor an sroute -area cap touches these -- they are RING shapes. Delete
# every VDD/VSS special shape lying ENTIRELY above y=1213: the 8 detour
# segments + their via stacks + the window-side legs. The main side legs
# (boxes start at y 4/18) are spared -- lly-based whole-shape criterion --
# and the ring stays powered via bottom + side legs + the full stripe grid.
# NB sViaInst objects have NO box_lly — only pt (placement point). A
# box_lly filter on them SILENTLY matches nothing (first attempt deleted
# the 8 wires but left all 104 detour via arrays: 96 fresh M8 via-vs-
# blockage viols). Wires filter on box_lly, vias on pt_y.
set __nuked 0
foreach __n {VDD VSS} {
	set __net [dbGet -p top.nets.name $__n]
	foreach __w [dbGet $__net.sWires] {
		if {[dbGet $__w.box_lly] >= 1213} { dbDeleteObj $__w; incr __nuked }
	}
	foreach __v [dbGet $__net.sVias] {
		if {[dbGet $__v.pt_y] >= 1213} { dbDeleteObj $__v; incr __nuked }
	}
}
puts "### UNL STATUS ### : deleted $__nuked ring-detour shapes above y=1213"

# Stripe grid stops at the notch-floor line: above it live only the analog
# windows, the tile fingers (powered by the tile's own closed U-ring) and
# the pin channels. Stripes crossing that strip get chopped against the
# window blockages into ORPHANED pieces (first run: 1248 disconnected VSS/
# VDD special-wire fragments + a VSS open over hart0) -- so don't draw them.
# M17b, learned the hard way across three runs:
#  * X stays 0..W. Trimming x to 30..W-30 to kill the die-edge stub
#    fragments detaches EVERY horizontal stripe from the rings instead
#    (-extend_to_closest_target respects the -area bound, so no extension
#    happens) -- VDD opens went 26 -> 313.
#  * Y ceiling is NOTCH_FLOOR_Y - 39 = below the tiles' notch-floor ring
#    band (tile-local y 572..600 = global 1221..1249). The last M8 stripe
#    pair otherwise lands at y ~1228..1246.5 inside that band = SameNet
#    ParallelRun spacing viols against the tile M7/M8 blockage. This is
#    HALF the fix -- the blockPin sroute straps hit the same band from the
#    other side (see the sroute -area cap below); both are needed, they
#    produce byte-identical violation bounds and masked each other.
set STRIPE_TOP_Y [expr {$NOTCH_FLOOR_Y - 39}]
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
	-area [list 0 0 $DESIGN_WIDTH $STRIPE_TOP_Y] \
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
	-start_from bottom \
	-area [list 0 0 $DESIGN_WIDTH $STRIPE_TOP_Y] \
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
# M17b: -area caps the strapping BELOW the tiles' notch-floor ring band
# (tile-local y 572..600 = global 1221..1249). Without it, blockPin sroute
# straps the tiles' notch-floor-ring PG pins and its M8 jumpers + M7 stack
# vias run 0.5 um from the tile LEF blockage = the 20 SameNet ParallelRun
# viols at signoff (5 per tile, identical bounds every run). The tile U-ring
# is a closed loop -- the dozens of straps onto the tile base's pins below
# 1220 power all of it; the skipped top-leg pins are redundancy only.
# (No rows exist above the tile bottoms either -- cutRow took them -- so
# the cap costs zero corePin rails.)
sroute \
	-nets { VSS VDD } \
	-allowLayerChange 0 \
	-allowJogging 0 \
	-connect {blockPin corePin} \
	-blockPin useLef \
	-area [list 0 0 $DESIGN_WIDTH 1220] \
    -corePinWidth 0.3

# M17b: second, JOGGING block-pin pass over the control-band analog macros
# only (por / dco0/1 / irq_gf0-2). The straight-line pass above connects a
# macro's full-width M3 PG strips only where an M7 stripe happens to cross
# it -- irq_gf2 missed by 8 um and sailed to signoff with an unconnected VSS
# terminal. The macros are placed on the stripe grid (straight vias remain
# the primary connection); this pass exists so a macro nudge can never
# silently strand a PG pin again. Area = the analog band, nothing else.
printStatus "Routing analog-macro PG pins (jogging backstop pass)"
sroute \
	-nets { VSS VDD } \
	-connect { blockPin } \
	-blockPin useLef \
	-allowLayerChange 1 \
	-allowJogging 1 \
	-layerChangeRange { M3(3) M7(7) } \
	-area { 440 460 1035 515 }

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
# hardened tiles => identical internal insertion delay)
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
# SI-aware hold cleanup -- the M14-proven remedy for the few-ps SI hold
# violations at the tile clk pins (first run here: -0.002 ns at hart3/clk).
# NB: 'optDesign -postRoute -si -hold' is OBSOLETE in 20.12 (IMPOPT-7016
# aborts the script); the M14 ECO form is SIAware delaycal + plain hold opt.
setDelayCalMode -SIAware true
# +10 ps hold target: without it the ECO converges to -0.000 (sub-ps
# VIOLATED at a tile clk pin) instead of inserting the final delay cell.
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
