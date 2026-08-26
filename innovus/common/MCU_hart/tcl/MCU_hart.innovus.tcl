################################################################################
# Innovus script -- MCU_hart, SINGLE-HART BLOCK ASSEMBLY (2026-08-24)
#
# WHAT THIS IS
#   The MCU block assembly (NO pad ring) with ONE hardened hart_tile macro.
#   It exists to take a small vehicle all the way to a MATCHing LVS: the
#   2026-08-18 penta verdict is a TOP-CELL PORT mismatch (layout 60 pins,
#   schematic 54 initial / 61 compare), which is a top-level assembly defect,
#   and this is the cheapest layout that still has the same top-level shape.
#
# MODELLED ON tcl/../../MCU_MP/tcl/MCU_MP.innovus.tcl, which is NOT touched.
#   Carried verbatim from it: the ring/stripe recipe (no top ring segment, M8
#   horizontal with -stacked_via_bottom_layer M7, M7 vertical with bottom M1),
#   the two sroute passes (straight blockPin+corePin, then the jogging analog
#   backstop), the M7/M8 route blockages, CTS route types and cell lists, the
#   nanoroute settings, and the signoff report set.
#
# WHAT IS DIFFERENT, deliberately
#   1. ONE tile, so there is no mirror-symmetric row and no inter-tile gap
#      geometry.  The tile keeps its analog notch, so the notch window is
#      still a hard placement + full-stack route keep-out to the die top and
#      the stripe grid still stops below the tile's notch-floor ring band.
#   2. THE FLOORPLAN IS DERIVED, NOT HARD CODED.  The staged single-hart config
#      is produced by a parallel effort and its macro inventory (how many
#      shared RAM banks, whether the NPU staging RAM exists, how many glitch
#      filters) is not known when this file is written.  So the script reads
#      the macro inventory out of the imported netlist and sizes the die from
#      it, then prints every derived number as a ### UNL STATUS ### line.  A
#      hard-coded die that does not fit is a P&R failure hours in; a derived
#      one is a number you can read in the log before the run gets expensive.
#   3. rom2k_hvt_pg (2048x32, SIZE 156.525 BY 181.41) joins the LEF list beside
#      rom_hvt_pg.  Both are loaded because the staged config decides which
#      entity rom0 binds to; the INSTANCE is rom0 either way.
#   4. The 8 KiB TCM split rails VDDPE/VDDCE/VSSE are declared even though the
#      tile is hardened and its TCM is sealed in the LEF abstract.  It costs
#      nothing and it is the exact omission that silently took the whole penta
#      power network down on 2026-08-17 (IMPSR-2403, all three sroute passes
#      aborted, zero macro straps, and a FLATTERINGLY LOW DRC count).
#
# NETLIST: in/MCU_hart_hier.pnr.v = the genus product with the hart_tile module
# definitions STRIPPED (prep_top_netlist_hart.sh) so Innovus binds hart_tile to
# the LEF macro rather than to a duplicate definition.
#
# PREREQUISITES, in order:
#   1. cd genus && make MCU_hart_hier.genus
#   2. innovus/common/MCU_hart/prep_top_netlist_hart.sh
# Then: cd innovus/common && make MCU_hart.innovus
################################################################################

source ../shared/constants.tcl
source ../shared/procedures.tcl

set DESIGN_NAME MCU
set BASENAME    MCU_hart

# POWER GEOMETRY, RE-DERIVED FROM THE RULE DECK 2026-08-24.
# Every number here is set by two rules pulling in opposite directions, and the
# inherited values (ring 10.0, stripe 5.0, set-to-set 50) sat on the wrong side
# of one of them.  All values below are read from signoff_mp/decks/blockdrc.rul
# with HALF_NODE UNDEFINED, i.e. the N65 arm (line 58 of the deck comments the
# #DEFINE out); the N55 arm alongside it carries different numbers and does not
# apply to this process.
#
# RULE 1, WIDE-METAL SPACING.  Both checks are triggered by WIDTH, and the
# trigger is what matters, not the spacing:
#     M7.S.3  one line wider than 1.50 um, parallel run > 1.50 um -> space 0.50
#     M7.S.4  one line wider than 4.50 um, parallel run > 4.50 um -> space 1.50
#     M8.S.2  one line wider than 1.50 um                         -> space 0.50
#     M8.S.3  one line wider than 4.50 um                         -> space 1.50
# The derived layers say the same thing structurally: M73 = M7Wide_4.5, and
# M7Wide_4.5 is an UNDEROVER that keeps only regions at least 4.5 um wide.
# So a shape NARROWER than 4.5 um can never be the wide party in M7.S.4.
#
# RULE 2, MINIMUM METAL DENSITY, and this is the one that forced the old width:
#     M7.DN.1  M7 local density >= 0.1   (10%)
#     M8.DN.1  M8 local density >= 0.2   (20%)
# For a two-stripe set of width W on a set-to-set pitch P the density is 2W/P.
# The inherited 5.0 um on a 50 um pitch is 2*5/50 = 20.0%, i.e. EXACTLY the M8
# floor with zero margin -- which is why the width was 5.0 and why it could not
# simply be reduced.  But 5.0 > 4.5, so every stripe was also a WIDE line and
# every stripe needed 1.5 um of clearance from any other M7/M8 geometry.
#
# THE RESOLUTION IS TO MOVE THE PITCH, NOT THE WIDTH.  At 4.0 um on a 36 um
# pitch the density is 2*4/36 = 22.2%, ABOVE the 20% M8 floor with real margin,
# while 4.0 um is BELOW the 4.5 um threshold, so M7.S.4 and M8.S.3 cannot be
# triggered by a top-level stripe or ring at all.  M7 lands at the same 22.2%
# against a 10% floor.  4.0 um is still above 1.5 um, so M7.S.3 / M8.S.2 do
# apply and ask for 0.50 um; the 4.0 um spacing below clears that eightfold.
#
# WHAT THIS DOES NOT FIX, stated plainly so it is not mistaken for a cure: the
# hart_tile macro's OWN PG pins are up to 10 um wide (measured from
# ../hart_tile/out/hart_tile.lef: 93 M7 pin shapes and 75 M8 pin shapes wider
# than 4.5 um).  M7.S.4 fires when EITHER line is wide, so near the tile the
# 1.5 um clearance is required no matter how narrow this mesh is.  That is a
# CLEARANCE problem, handled by the tile halo and the stripe -area ceiling
# below, not a width problem, and no choice of stripe width can address it.
set POWER_RING_PATH_WIDTH	4.0
set POWER_RING_PATH_SPACING	4.0
set POWER_STRIPE_PATH_WIDTH		4.0
set POWER_STRIPE_PATH_SPACING	4.0
set POWER_STRIPE_SET_TO_SET		36.0

set CORE_SPACING	1

# --- Tile geometry.  MUST match tcl/../../hart_tile/tcl/hart_tile.innovus.tcl
# and is re-derived from the LEF below as a cross-check (a silent tile re-cut
# that changes the bbox is the SNAPSHOT-ROT class of failure). ---
set TILE_W        660
set TILE_H        880
set TILE_NOTCH_X0 75
set TILE_NOTCH_X1 585
set TILE_NOTCH_Y0 340

# --- Macro footprints, from the LEFs ---
set SRAM16K_WIDTH  319.650
set SRAM16K_HEIGHT 383.085
# rom2k_hvt_pg SIZE 156.525 BY 181.410.  Placed R90 like every other ROM in
# this family, so it occupies 181.410 in X and 156.525 in Y.
set ROM2K_LEF_X    156.525
set ROM2K_LEF_Y    181.410
# rom_hvt_pg SIZE 156.525 BY 325.055 (the 16 KiB plate, kept for a pre-flip config)
set ROM16K_LEF_X   156.525
set ROM16K_LEF_Y   325.055

set DIE_MARGIN     20
set MACRO_GAP      20

tic

################################################################################
# Design import
################################################################################
set init_verilog             "$INPUT_DIR/MCU_hart_hier.pnr.v"
set init_top_cell            "$DESIGN_NAME"
set init_pwr_net             "VDD"
set init_gnd_net             "VSS"
set init_mmmc_file           "$SCRIPT_DIR/viewdefinition_MCU_hart.tcl"

set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					$IP_DIR/rom2k_hvt_pg/rom2k_hvt_pg.lef \
					$IP_DIR/rom_hvt_pg/rom_hvt_pg.lef \
					$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef \
					$IP_DIR/sram1p8k_hvt_pg/sram1p8k_hvt_pg.vclef \
					$IC_DIR/abstracts/myshkin_abs/GlitchFilter/GlitchFilter.lef \
					$IC_DIR/abstracts/myshkin_abs/PowerOnResetCheng/PowerOnResetCheng.lef \
					$IC_DIR/abstracts/myshkin_abs/OscillatorCurrentStarved/OscillatorCurrentStarved.lef \
					../hart_tile/out/hart_tile.lef"

set init_design_uniquify 1
init_design

# Tile timing enters via the ETM .lib (see tcl/viewdefinition_MCU_hart.tcl).
# The ILM route was tried on MCU_MP and ABANDONED: after specifyIlm the
# rebuilt session comes up with no clocks when the clocks are defined on
# hierarchical pins, and create_ccopt_clock_tree_spec then finds no clock roots
# (IMPCCOPT-4082).  ETM + hpin clocks is the Myshkin-proven configuration.

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
# The 8 KiB TCM's split rails.  Declared unconditionally: see the header.
globalNetConnect VDD -type pgpin -pin VDDPE -inst * -module {} -autoTie -verbose
globalNetConnect VDD -type pgpin -pin VDDCE -inst * -module {} -autoTie -verbose
globalNetConnect VSS -type pgpin -pin VSSE  -inst * -module {} -autoTie -verbose

################################################################################
# Macro inventory + floorplan derivation
#
# Everything below reads the design rather than assuming it, and prints what it
# found.  Read the ### UNL STATUS ### block in the log before letting the run
# proceed into place_opt_design.
################################################################################
# ONE pass over the instance list, C-side, then bucket in tcl.  A per-instance
# dbGet loop over a post-synthesis netlist is minutes of wall time; two whole-
# list fetches are seconds.  Note also that `dbGet -p top.insts.cell.name X`
# returns the CELL, not the inst (the -p level counts from the attribute), so
# the zip below is the unambiguous form as well as the fast one.
set __INV_NAMES [dbGet top.insts.name]
set __INV_CELLS [dbGet top.insts.cell.name]
if {[llength $__INV_NAMES] != [llength $__INV_CELLS]} {
	puts "FATAL: instance name/cell lists disagree ([llength $__INV_NAMES] vs [llength $__INV_CELLS])"
	exit 1
}
array set INV {}
foreach __n $__INV_NAMES __c $__INV_CELLS { lappend INV($__c) $__n }
puts "### UNL STATUS ### : imported [llength $__INV_NAMES] instances, [llength [array names INV]] distinct cells"

# Instances of a given cell, name-sorted so the placement is deterministic.
proc insts_of_cell {cellname} {
	global INV
	if {![info exists INV($cellname)]} { return {} }
	return [lsort $INV($cellname)]
}

set TILE_INSTS   [insts_of_cell hart_tile]
set SH16K_INSTS  [insts_of_cell sram1p16k_hvt_pg]
set SH8K_INSTS   [insts_of_cell sram1p8k_hvt_pg]
set ROM2K_INSTS  [insts_of_cell rom2k_hvt_pg]
set ROM16K_INSTS [insts_of_cell rom_hvt_pg]
set POR_INSTS    [insts_of_cell PowerOnResetCheng]
set DCO_INSTS    [insts_of_cell OscillatorCurrentStarved]
set GF_INSTS     [insts_of_cell GlitchFilter]

printStatus "MACRO INVENTORY"
puts "### UNL STATUS ### :   hart_tile          : [llength $TILE_INSTS]  $TILE_INSTS"
puts "### UNL STATUS ### :   sram1p16k_hvt_pg   : [llength $SH16K_INSTS]  $SH16K_INSTS"
puts "### UNL STATUS ### :   sram1p8k_hvt_pg    : [llength $SH8K_INSTS]  $SH8K_INSTS"
puts "### UNL STATUS ### :   rom2k_hvt_pg       : [llength $ROM2K_INSTS]  $ROM2K_INSTS"
puts "### UNL STATUS ### :   rom_hvt_pg         : [llength $ROM16K_INSTS]  $ROM16K_INSTS"
puts "### UNL STATUS ### :   PowerOnResetCheng  : [llength $POR_INSTS]  $POR_INSTS"
puts "### UNL STATUS ### :   OscillatorCurrent* : [llength $DCO_INSTS]  $DCO_INSTS"
puts "### UNL STATUS ### :   GlitchFilter       : [llength $GF_INSTS]  $GF_INSTS"

if {[llength $TILE_INSTS] != 1} {
	puts "FATAL: MCU_hart expects EXACTLY ONE hart_tile instance, found [llength $TILE_INSTS]."
	puts "       Either the staged config is not single-hart, or prep_top_netlist_hart.sh"
	puts "       left the hart_tile module DEFINITION in place so Innovus bound a module"
	puts "       instead of the LEF macro."
	exit 1
}
set TILE_INST [lindex $TILE_INSTS 0]

if {[llength $ROM2K_INSTS] + [llength $ROM16K_INSTS] != 1} {
	puts "FATAL: expected exactly one boot ROM macro instance, found"
	puts "       [llength $ROM2K_INSTS] rom2k_hvt_pg + [llength $ROM16K_INSTS] rom_hvt_pg."
	exit 1
}
if {[llength $ROM2K_INSTS] == 1} {
	set ROM_INST  [lindex $ROM2K_INSTS 0]
	set ROM_LEF_X $ROM2K_LEF_X
	set ROM_LEF_Y $ROM2K_LEF_Y
	set ROM_CELL  rom2k_hvt_pg
} else {
	set ROM_INST  [lindex $ROM16K_INSTS 0]
	set ROM_LEF_X $ROM16K_LEF_X
	set ROM_LEF_Y $ROM16K_LEF_Y
	set ROM_CELL  rom_hvt_pg
}
# Placed R90, so the LEF's X becomes chip Y and vice versa.
set ROM_W $ROM_LEF_Y
set ROM_H $ROM_LEF_X
puts "### UNL STATUS ### : boot ROM = $ROM_CELL as $ROM_INST, R90 footprint ${ROM_W} x ${ROM_H} um"

# --- Cross-check the tile bbox against the LEF actually loaded.  A tile re-cut
# that changes the bbox without this file changing is the SNAPSHOT-ROT class:
# every derived coordinate below silently moves. ---
set __tc [dbGet -p top.insts.name $TILE_INST]
set __tw [dbGet $__tc.cell.size_x]
set __th [dbGet $__tc.cell.size_y]
puts "### UNL STATUS ### : hart_tile LEF bbox = ${__tw} x ${__th} um (script assumes ${TILE_W} x ${TILE_H})"
if {abs($__tw - $TILE_W) > 0.001 || abs($__th - $TILE_H) > 0.001} {
	puts "FATAL: the hart_tile LEF bbox does not match this script's TILE_W/TILE_H."
	puts "       ../hart_tile/out/hart_tile.lef says ${__tw} x ${__th}."
	puts "       Update TILE_W/TILE_H/TILE_NOTCH_* here from the tile harden script"
	puts "       and re-derive the floorplan; do not run with stale geometry."
	exit 1
}

# --- Band heights ---
set SH_N     [llength $SH16K_INSTS]
set SH_SPAN  [expr {$SH_N > 0 ? $SH_N * $SRAM16K_WIDTH + ($SH_N - 1) * $MACRO_GAP : 0}]
set SH_BAND_H [expr {$SH_N > 0 ? $SRAM16K_HEIGHT + 2 * $MACRO_GAP : 0}]

# Control band: the ROM plus the analog macros in one row, with room above and
# below for standard cells.  CTRL_BAND_H has a floor of 400 um so the band is
# never a bare macro row with no placeable silicon (the M17 orphaned-rail
# lesson: slivers beside macros hold rows on floating follow-pin rails).
set ANALOG_N   [expr {[llength $POR_INSTS] + [llength $DCO_INSTS] + [llength $GF_INSTS]}]
set ANALOG_SPAN [expr {$ANALOG_N * 60 + $ANALOG_N * $MACRO_GAP}]
set CTRL_ROW_W [expr {$ROM_W + $MACRO_GAP + $ANALOG_SPAN}]
set CTRL_BAND_H 400

# --- Area-driven sanity: let Innovus size a first-cut core from the REAL cell
# area, then take the larger of that and the macro-driven minimum.  This is the
# number that decides whether place_opt_design has anywhere to put the control
# plane, and it is measured, not guessed. ---
# 0.35, down from 0.55.  This first cut is ADVISORY ON WIDTH ONLY (the band
# stack fixes the height), so a lower target simply widens the die and drops
# gate density.  There is no area pressure on this vehicle whatsoever and a
# roomy control band is worth more than a small die: the 5-hart cut runs at
# 7.861% gate density with ~4.14 mm2 spare and still had placement-adjacent
# DRC.  Lower is strictly safer here.
floorPlan -site TSMC65ADV10TSITE -r 1.0 0.35 \
	$DIE_MARGIN $DIE_MARGIN $DIE_MARGIN $DIE_MARGIN
set __cb [dbGet top.fPlan.coreBox]
if {[llength $__cb] == 1} { set __cb [lindex $__cb 0] }
lassign $__cb __cx0 __cy0 __cx1 __cy1
set AUTO_W [expr {$__cx1 - $__cx0}]
set AUTO_H [expr {$__cy1 - $__cy0}]
puts "### UNL STATUS ### : area-driven first cut (r=1.0, util 0.35) core = [format %.1f $AUTO_W] x [format %.1f $AUTO_H] um"

set MACRO_MIN_W [expr {max($TILE_W, $SH_SPAN, $CTRL_ROW_W) + 2 * $DIE_MARGIN}]
set MACRO_MIN_H [expr {$TILE_H + $CTRL_BAND_H + $SH_BAND_H + 2 * $DIE_MARGIN}]
puts "### UNL STATUS ### : macro-driven minimum die = [format %.1f $MACRO_MIN_W] x [format %.1f $MACRO_MIN_H] um"
puts "### UNL STATUS ### :   tile band  $TILE_H   ctrl band $CTRL_BAND_H   sram band $SH_BAND_H"
puts "### UNL STATUS ### :   sram row span [format %.1f $SH_SPAN] ($SH_N x $SRAM16K_WIDTH + gaps)"
puts "### UNL STATUS ### :   ctrl row span [format %.1f $CTRL_ROW_W] (ROM $ROM_W + $ANALOG_N analog)"

# The area-driven cut is advisory on WIDTH only: the band stack fixes the
# height, so any extra area demand is absorbed by widening.  If the auto cut
# wants more total area than the macro-driven box provides, widen until it does.
set DESIGN_HEIGHT [expr {ceil($MACRO_MIN_H)}]
set NEED_W        [expr {double($AUTO_W) * double($AUTO_H) / double($DESIGN_HEIGHT)}]
set DESIGN_WIDTH  [expr {ceil(max($MACRO_MIN_W, $NEED_W))}]
# Snap both to the 0.9 um M8 band pitch multiple used family-wide, then to 1 um.
set DESIGN_WIDTH  [expr {int($DESIGN_WIDTH)}]
set DESIGN_HEIGHT [expr {int($DESIGN_HEIGHT)}]
printStatus "DERIVED DIE = ${DESIGN_WIDTH} x ${DESIGN_HEIGHT} um"

set CORE_WIDTH  [expr {$DESIGN_WIDTH  - ($CORE_SPACING * 2)}]
set CORE_HEIGHT [expr {$DESIGN_HEIGHT - ($CORE_SPACING * 2)}]

################################################################################
# Floorplan (final)
################################################################################
floorPlan \
    -site TSMC65ADV10TSITE \
    -s $CORE_WIDTH $CORE_HEIGHT $CORE_SPACING $CORE_SPACING $CORE_SPACING $CORE_SPACING

# --- The tile, flush with the die top, horizontally centered so the notch
# window sits on the die centerline. ---
set TILE_X [expr {($DESIGN_WIDTH - $TILE_W) / 2.0}]
set TILE_Y [expr {$DESIGN_HEIGHT - $CORE_SPACING - $TILE_H}]
placeInstance $TILE_INST $TILE_X $TILE_Y R0
# 15 um, up from 10.  The halo is sized by the WIDE-METAL CLEARANCE, not by
# placement comfort: the tile's own PG pins reach 10 um wide on M7 and M8, and
# M7.S.4 / M8.S.3 demand 1.5 um from any other M7/M8 once either line is wider
# than 4.5 um.  15 um keeps top-level cells, their routing and the mesh an
# order of magnitude outside that band instead of a few tenths.
addHaloToBlock 15 15 15 15 $TILE_INST
printStatus "Placed hart_tile at ($TILE_X, $TILE_Y) R0"

# --- The analog notch window: keep-out from the notch floor to the die top.
# Hard placement blockage + all-layer route blockage; rows cut. ---
set WX0 [expr {$TILE_X + $TILE_NOTCH_X0}]
set WX1 [expr {$TILE_X + $TILE_NOTCH_X1}]
set WY0 [expr {$TILE_Y + $TILE_NOTCH_Y0}]
set WY1 $DESIGN_HEIGHT
createPlaceBlockage -type hard -name analog_win0 -box [list $WX0 $WY0 $WX1 $WY1]
createRouteBlk -name analog_win_rt0 -box [list $WX0 $WY0 $WX1 $WY1] -layer {1 2 3 4 5 6 7 8}
cutRow -area [list $WX0 $WY0 $WX1 $WY1]

# --- Above the notch-floor line the die holds only the notch window, the tile
# fingers and the die margins, none of them placeable.  Keep the whole strip
# cell-free so no stray row survives beside the window and orphans a follow-pin
# rail (the M17 v3 lesson: 1276 orphaned PG pieces). ---
set NOTCH_FLOOR_Y [expr {$TILE_Y + $TILE_NOTCH_Y0}]
createPlaceBlockage -type hard -name top_band \
	-box [list 0 $NOTCH_FLOOR_Y $DESIGN_WIDTH $DESIGN_HEIGHT]
cutRow -area [list 0 $NOTCH_FLOOR_Y $DESIGN_WIDTH $DESIGN_HEIGHT]
cutRow

# --- Shared RAM row at the bottom, centered ---
if {$SH_N > 0} {
	set SH_Y  [expr {$DIE_MARGIN}]
	set SH_X0 [expr {($DESIGN_WIDTH - $SH_SPAN) / 2.0}]
	set i 0
	# 8 um, up from 4: same minimum-area reasoning as the ROM comb above.
	# NAMED, because the ram-gap blockage below has to reach past it.
	set SH_HALO 8
	foreach m $SH16K_INSTS {
		placeInstance $m [expr {$SH_X0 + $i * ($SRAM16K_WIDTH + $MACRO_GAP)}] $SH_Y R0
		addHaloToBlock $SH_HALO $SH_HALO $SH_HALO $SH_HALO $m
		incr i
	}
	cutRow
	# The placeable slivers between adjacent RAM macros meet a vertical M7
	# stripe only by pitch luck; rows there otherwise carry FLOATING follow-pin
	# rails (the M17 v4 lesson: 481 orphaned PG pieces with live buffers on
	# dead rails).  Wire-only, like the tile channels.
	#
	# THE BLOCKAGE SPANS THE WHOLE GAP COLUMN, from the die floor to past the
	# top of the SRAM HALO, and that is the LUP.6 fix.  It used to run
	# SH_Y - 4 .. SH_Y + SRAM16K_HEIGHT + 4, i.e. 16 .. 407.085, and BOTH ENDS
	# LEAKED.  Each leak is a placeable ISLAND in the gap column: 20 um wide
	# less the two 8 um SRAM halos leaves FOUR MICRONS of usable width, walled
	# in on both sides.  Standard cells land in it, addWellTap cannot fit a
	# FILLTIE2A10TH into a 4 um sliver, and the nearest well strap is on the far
	# side of a 319.65 um SRAM macro -- an order of magnitude past the 30 um
	# LUP.6 allows ("any point inside NMOS source/drain space to the nearest PW
	# STRAP <= 30 um").  MEASURED, both ends, one iteration apart:
	#
	#   bottom leak, y < 16     17 LUP.6 at y = 13.2 .. 13.9,
	#                           x = 748.1 .. 751.9 and 1087.9 .. 1089.3
	#   top leak, 407.085 ..    6 LUP.6 at y = 409.2 .. 409.9,
	#     the halo top 411.085  x = 748.1 .. 749.5
	#
	# both inside gap 1 (740.0 .. 760.0) and gap 2 (1079.65 .. 1099.65).
	# A gap that cannot hold a well tap must not hold a transistor, so the
	# blockage now covers the column outright.  It costs 2 extra PO.DN.2
	# minimum-density windows, which is the right trade: LUP.6 is a latch-up
	# rule with a real failure mode, PO.DN.2 is what dummy fill exists for.
	for {set g 0} {$g < $SH_N - 1} {incr g} {
		set gx0 [expr {$SH_X0 + ($g + 1) * $SRAM16K_WIDTH + $g * $MACRO_GAP}]
		set gbox [list $gx0 0 [expr {$gx0 + $MACRO_GAP}] \
		               [expr {$SH_Y + $SRAM16K_HEIGHT + $SH_HALO + 4}]]
		createPlaceBlockage -type hard -name ramgap$g -box $gbox
		cutRow -area $gbox
	}
	printStatus "Placed $SH_N shared RAM macros in a centered bottom row at y=$SH_Y"
}

# --- Control band: the boot ROM at the left margin, then the analog macros.
# The band centre is the vertical midpoint between the RAM row top and the tile
# bottom, so std cells get symmetric room above and below the macro row. ---
set BAND_Y0 [expr {$SH_N > 0 ? $DIE_MARGIN + $SRAM16K_HEIGHT + $MACRO_GAP : $DIE_MARGIN}]
set BAND_Y1 $TILE_Y
set BAND_MID [expr {($BAND_Y0 + $BAND_Y1) / 2.0}]
puts "### UNL STATUS ### : control band y = [format %.1f $BAND_Y0] .. [format %.1f $BAND_Y1] , mid [format %.1f $BAND_MID]"

set ROM_X $DIE_MARGIN
set ROM_Y [expr {$BAND_MID - $ROM_H / 2.0}]
placeInstance $ROM_INST $ROM_X $ROM_Y R90
# 12 um all round, up from 9/4/4/9.  The boot ROM's PG pins are a DENSE COMB:
# 41 M4 strips 0.800 um wide on a 1.400 um pitch, so 0.600 um gaps, 33 of them
# (measured from rom2k_hvt_pg.lef).  That comb is the densest pin field on the
# die and it is where the M2 minimum-area cluster (M2.A.1, area < 0.052 um2)
# congregates on the penta cut.  A symmetric halo keeps standard cells and
# their M2 stubs off all four sides of it rather than only two.
addHaloToBlock 12 12 12 12 $ROM_INST
puts "### UNL STATUS ### : $ROM_INST ($ROM_CELL) at ($ROM_X, [format %.3f $ROM_Y]) R90 -> x\[$ROM_X,[expr {$ROM_X + $ROM_W}]\]"

# Analog macros in a row to the right of the ROM.  GlitchFilter PG pins are
# full-width M3 strips, so a GF connects only where a vertical M7 stripe pair
# crosses it -- the jogging block-pin sroute below is the backstop that stops a
# nudge from silently stranding a PG terminal (the M17b irq_gf2 lesson: an
# unconnected VSS terminal sailed to signoff because it missed a pair by 8 um).
set GF_HALO 20
set AMX [expr {$ROM_X + $ROM_W + 60}]
set AMY [expr {$BAND_MID - 20}]
set ANALOG_X0 $AMX
foreach m [concat $POR_INSTS $DCO_INSTS] {
	placeInstance $m $AMX $AMY R0
	# 8 um, up from 4, for the same minimum-area reason as the memory macros.
	addHaloToBlock 8 8 8 8 $m
	puts "### UNL STATUS ### : analog $m at ($AMX, [format %.1f $AMY])"
	set AMX [expr {$AMX + 80}]
}
foreach m $GF_INSTS {
	placeInstance $m $AMX $AMY R0
	addHaloToBlock $GF_HALO $GF_HALO $GF_HALO $GF_HALO $m
	puts "### UNL STATUS ### : glitch filter $m at ($AMX, [format %.1f $AMY])"
	set AMX [expr {$AMX + 50}]
}
set ANALOG_X1 $AMX
cutRow

# --- Any macro this script did not place would be left at the origin and
# nanoroute would NRIG-92 on it hours later.  Assert instead. ---
# WHICH INSTANCES ARE MACROS is decided by CELL NAME, not by a db attribute.
# The first version of this check asked `dbGet top.insts.cell.isBlock`, and this
# Innovus does not have that attribute: IMPDBTCL-206 `'isBlock' is not a
# recognized object/attribute`, which aborted the script AFTER the whole
# floorplan was built.  A guard that dies on the tool version is worse than no
# guard, and the cell names are already known here -- they are the same list the
# MACRO INVENTORY above enumerates and the LEF list at the top loads.
# pStatus IS a valid attribute (it fetched cleanly in that same run), so it
# still supplies the placed/fixed/cover verdict.
set __MACRO_CELLS {hart_tile sram1p16k_hvt_pg sram1p8k_hvt_pg rom2k_hvt_pg \
                   rom_hvt_pg PowerOnResetCheng OscillatorCurrentStarved \
                   GlitchFilter}
set __unplaced {}
set __sts [dbGet top.insts.pStatus]
foreach __n $__INV_NAMES __c $__INV_CELLS __s $__sts {
	if {[lsearch -exact $__MACRO_CELLS $__c] < 0} { continue }
	if {$__s ne "placed" && $__s ne "fixed" && $__s ne "cover"} {
		lappend __unplaced "$__n ($__c, $__s)"
	}
}
if {[llength $__unplaced] > 0} {
	puts "FATAL: [llength $__unplaced] macro instance(s) were never placed by this script:"
	foreach u $__unplaced { puts "         $u" }
	puts "       An unplaced macro sits at the origin and detonates in nanoroute"
	puts "       (NRIG-92) hours from now.  Add it to the floorplan above."
	exit 1
}
printStatus "All macros placed"

# --- Block pins.  This is a BLOCK assembly, so every port is a real pin shape.
# All on the BOTTOM edge: the north face is the tile plus its analog notch and
# has no room for a pin channel. ---
set ALL_PINS [dbGet top.terms.name]
puts "### UNL STATUS ### : assigning [llength $ALL_PINS] block pins to the bottom edge"
editPin -pin $ALL_PINS -side Bottom -layer 4 -spreadType side -spacing 2 -fixOverlap 1
printStatus "Placed block pins (all bottom; north face signal-free)"

################################################################################
# Power.  NO top ring segment -- it would cross the analog window; the
# left/right M7 + bottom M8 segments and the stripe grid carry the current.
################################################################################
# ==============================================================================
# ANALOG M7/M8 KEEPOUT -- added 2026-08-24 after a parallel effort measured a
# REAL VDD-VSS SHORT of exactly this shape on the 5-hart cut.
#
# THE BACKGROUND THAT MAKES THIS NECESSARY NOW.  GlitchFilter and
# OscillatorCurrentStarved streamed into signoff as EMPTY OUTLINES for this
# project's entire life: the Myshkin tapeout GDS carried BOTH twins of each, the
# collision rule renamed the real layout to <cell>_0 / <cell>_1, and the base
# name -- the only name strmin resolves against -- kept the SHELL.  A new
# myshkin_analog reference library republishes the real layouts on their correct
# base names, so from now on this block is DRC'd and LVS'd over REAL ANALOG
# GEOMETRY, probably for the first time.  With that geometry present,
# MCU_castalia_penta's shorts file went from 0 bytes to 9,309:
#
#     SHORT 1. VSS: - VDD:
#       "VSS:" at (1345.000, 1111.000) metal1_text
#       "VDD:" at (1345.000, 1113.000) metal1_text
#
#   bottoming out at y = 1069.880, the analog row origin, on four metal7
#   polygons 4-5 um wide spanning DCO#0's full height -- TOP-LEVEL PG STRIPES
#   crossing the macro site, not the macro's own metal.
#
# THE RULE THIS APPLIES, and it is a rule rather than a special case: HONOUR THE
# OBSTRUCTIONS EACH MACRO ACTUALLY DECLARES.  Measured from the three abstracts:
#
#   OscillatorCurrentStarved  pins M5 only;  OBS 12 x M7, 20 x M8, 102 x VIA7
#   GlitchFilter              pins M3 only;  OBS stops at M3/VIA2
#   PowerOnResetCheng         pins M3 only;  OBS stops at M3/VIA2
#
# So the DCO EXPLICITLY BLOCKS M7 AND M8 across its site and the other two do
# not.  The mesh is kept off the DCOs and left crossing the GlitchFilters and
# the POR, which is not an inconsistency: those two have no top-metal
# obstruction and the script's own comment records that a GF "connects only
# where a vertical M7 stripe pair crosses it", so the crossing is how they are
# powered at all.  The DCO takes its power on M5 from the jogging analog sroute
# pass instead, whose target-layer range (bottom 3, top 7) already covers M5.
#
# WHY A CROSSING SHORTS.  The M7 addStripe pass below runs with
# -stacked_via_bottom_layer M1 and -block_ring_bottom_layer_limit M1, so where a
# stripe crosses a macro it punches a via stack toward M1.  Over an EMPTY
# OUTLINE that stack hit nothing and the flow looked clean for years.  Over the
# REAL DCO layout the same stack lands in the macro's guts and bridges its
# internal nets, which is how a VDD stripe and a VSS stripe end up on one net.
#
# BELT AND BRACES, because these are two different mechanisms: the route
# blockage stops addStripe from generating the shapes, and the sweep after the
# stripes are added deletes anything that got through anyway.  The sweep follows
# the RING_NUKE lesson already learned in this file -- sWires filter on their
# box, but sViaInst objects have NO box and must be filtered on pt_x/pt_y, and a
# box filter on them SILENTLY MATCHES NOTHING.
set ANALOG_PG_KEEPOUT 3.0
set DCO_BOXES {}
foreach m $DCO_INSTS {
	set ip [dbGet -p top.insts.name $m -e]
	if {$ip eq "" || $ip eq "0x0"} {
		puts "FATAL: DCO instance $m not found when building the M7/M8 keepout"
		exit 1
	}
	set bb [dbGet $ip.box]
	if {[llength $bb] == 1} { set bb [lindex $bb 0] }
	if {[llength $bb] != 4} {
		puts "FATAL: could not read a bbox for DCO instance $m"
		exit 1
	}
	lassign $bb bx0 by0 bx1 by1
	set kx0 [expr {$bx0 - $ANALOG_PG_KEEPOUT}]
	set ky0 [expr {$by0 - $ANALOG_PG_KEEPOUT}]
	set kx1 [expr {$bx1 + $ANALOG_PG_KEEPOUT}]
	set ky1 [expr {$by1 + $ANALOG_PG_KEEPOUT}]
	lappend DCO_BOXES [list $kx0 $ky0 $kx1 $ky1]
	createRouteBlk -name pgkeep_$m -box [list $kx0 $ky0 $kx1 $ky1] -layer {7 8}
	puts "### UNL STATUS ### : M7/M8 PG keepout over $m = ($kx0,$ky0) .. ($kx1,$ky1)  (macro bbox + $ANALOG_PG_KEEPOUT um)"
}
puts "### UNL STATUS ### : [llength $DCO_BOXES] DCO M7/M8 keepout(s) armed before addStripe"

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

# -skip_side {top} skips only the DIE-top segments; the ring engine still
# CLOSES the loop by detouring under the analog window, 0.5 um from the tile's
# M7/M8 LEF blockage, which is the long-standing "SameNet" signoff class.
# Delete every VDD/VSS special shape lying ENTIRELY above the delete line.
# NB sViaInst objects have NO box_lly, only a placement point: a box_lly filter
# on them SILENTLY matches nothing and leaves every detour via array behind
# (the M17b first attempt: 8 wires deleted, 104 via arrays kept, 96 fresh
# M8-via-vs-blockage violations).  Wires filter on box_lly, vias on pt_y.
set RING_NUKE_Y [expr {$NOTCH_FLOOR_Y - 36}]
set __nuked 0
foreach __n {VDD VSS} {
	set __net [dbGet -p top.nets.name $__n]
	foreach __w [dbGet $__net.sWires] {
		if {[dbGet $__w.box_lly] >= $RING_NUKE_Y} { dbDeleteObj $__w; incr __nuked }
	}
	foreach __v [dbGet $__net.sVias] {
		if {[dbGet $__v.pt_y] >= $RING_NUKE_Y} { dbDeleteObj $__v; incr __nuked }
	}
}
puts "### UNL STATUS ### : deleted $__nuked ring-detour shapes above y=$RING_NUKE_Y"

# The stripe grid stops below the tile's notch-floor ring band.  Two halves of
# ONE fix, learned the hard way on MCU_MP across three runs:
#   * X stays 0..W.  Trimming x to kill die-edge stub fragments detaches EVERY
#     horizontal stripe from the rings instead, because
#     -extend_to_closest_target respects the -area bound.
#   * The Y ceiling must clear the tile's own notch-floor ring band, or the
#     last M8 stripe pair lands inside it and produces SameNet ParallelRun
#     spacing violations against the tile M7/M8 blockage.  The blockPin sroute
#     below hits the same band from the other side and its -area cap is the
#     other half; both are needed and they mask each other.
set STRIPE_TOP_Y [expr {$NOTCH_FLOOR_Y - 39}]
# -stacked_via_bottom_layer M7 on the M8 pass.  The M8 pass runs FIRST, before
# any M7 stripe exists; with bottom=M1 it punches full M8-to-M4 stacks onto the
# sram/ROM M4 PG pin strips at the PIN rows, and the later M7 pass punches its
# own arrays at the stripe crossings -- two interleaved same-net VIA7 arrays
# 0.34 um apart at every crossing (VIA7.W.1 + VIA7.S.2, 930 results each on
# MCU_MP) plus floating M8/M7 landing pads at off-stripe pin rows (M8.S.3).
# With bottom=M7 the M8 pass ties only to real M7 and every macro-pin stack
# comes from the M7 pass, centered on its own stripes.
setAddStripeMode \
    -remove_floating_stripe_over_block true \
    -trim_antenna_back_to_shape core_ring \
	-stacked_via_top_layer M8 \
	-stacked_via_bottom_layer M7 \
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
# M7 pass: bottom back to M1 -- this pass owns the macro-pin (M4) and
# follow-pin rail (M1) stacks, all landing on its own stripe centerlines.
#
# THE VIA7 CLASS.  Its mechanism is NOT the two-addStripe-pass interleaving the
# comment above describes, and it is not fixable by any pass option.  MEASURED
# on the 2026-08-24 cut, the whole design carries 2476 top-level VIA7 arrays and
# EXACTLY 13 of them lie inside the hart_tile footprint, all at x = 974.0 and
# x = 982.0.  Those are the M7 stripes that happen to fall on the tile's own M7
# PG pins (LEF-local x 551..556 and 560..565, i.e. 971..976 and 980..985
# absolute), and the stripe stacks UP from there to the tile's M8 PG pin --
# landing a VIA7 array exactly where THE TILE ALREADY HAS ONE.
# The two arrays are offset by 0.05 um (the tile's internal routing grid against
# the top-level stripe centerline), so every cut pair merges into a 0.41 um
# polygon instead of a 0.36 um one:
#     VIA7.W.1   465 results   (NOT RECTANGLE VIA7 == 0.36 BY == 0.36)
#     VIA7.S.2   308 results   (merged-to-merged gap 0.49 um, needs 0.54)
# and the arithmetic closes exactly: via7Array_12 (11x5 = 55 cuts) x 2
# placements + via7Array_13 (5x5 = 25 cuts) x 11 placements = 385 cuts, which
# is both the top-level count (55 + 25 reported against the two M8_M7_CDNS via
# masters) and the hart_tile count (385) in the Calibre by-cell breakdown.
# 465 = 55 + 25 + 385.
#
# THE VIAS ARE PURE REDUNDANCY.  The stripe already touches the tile's M7 pin
# on its own layer, and the tile ties that M7 pin to its M8 pin internally --
# with its own via array, the very one being collided with.
#
# WHY NO PASS OPTION CAN FIX IT, and this is the part to keep: THE TILE'S
# INTERNAL VIAS ARE NOT IN ITS LEF.  An abstract carries pins and obstructions,
# not the macro's own via arrays, so Innovus cannot see what it is landing on
# and cannot align to it.  Two options were tried against that and MEASURED:
#   * -block_ring_top_layer_limit M7 on this pass.  A REAL option (checked in
#     `help addStripe` before use) and a MEASURED NO-OP: with and without it the
#     post-addStripe census is 2448 arrays and 12 inside the tile, identical to
#     the digit.  These stacks are stripe-to-target, not block-ring, so the
#     block-ring limit never governs them.  NOT LEFT IN THE SCRIPT -- a flag that
#     does nothing under a comment claiming it is the fix is worse than no flag.
#   * -stacked_via_top_layer M7 on this pass.  Would remove them, and would also
#     remove the 2432 M7 x M8 MESH CROSSINGS this pass makes (the M8 pass runs
#     FIRST, before any M7 stripe exists, so it cannot make them).  That trades
#     a DRC class for a disconnected power mesh.  Rejected.
# What is left is to delete the duplicates, which is what the sweep below does.
setAddStripeMode \
    -remove_floating_stripe_over_block true \
    -trim_antenna_back_to_shape core_ring \
	-stacked_via_top_layer M8 \
	-stacked_via_bottom_layer M1 \
    -extend_to_closest_target ring
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

# --- Sweep: delete any VDD/VSS M7/M8 special shape that still overlaps a DCO
# keepout box.  The route blockage above should have prevented every one of
# these; this is the second, independent mechanism, because a silent VDD-VSS
# short over an analog macro is precisely the defect that hid behind empty
# outlines for years and it is worth two guards.
# NB the sWire/sVia asymmetry, already learned once in this file at RING_NUKE:
# wires carry a box and filter on it, but sViaInst objects have NO box_* fields
# at all, only a placement point, so a box filter on them matches NOTHING
# SILENTLY and leaves every via array behind.  Vias filter on pt_x / pt_y.
proc __in_any_box {x y boxes} {
	foreach b $boxes {
		lassign $b bx0 by0 bx1 by1
		if {$x >= $bx0 && $x <= $bx1 && $y >= $by0 && $y <= $by1} { return 1 }
	}
	return 0
}
set __pgswept 0
foreach __n {VDD VSS} {
	set __net [dbGet -p top.nets.name $__n -e]
	if {$__net eq "" || $__net eq "0x0"} { continue }
	foreach __w [dbGet $__net.sWires] {
		set __lay ""
		catch { set __lay [dbGet $__w.layer.name] }
		if {$__lay ne "M7" && $__lay ne "M8"} { continue }
		set __b {}
		catch { set __b [dbGet $__w.box] }
		if {[llength $__b] == 1} { set __b [lindex $__b 0] }
		if {[llength $__b] != 4} { continue }
		lassign $__b __x0 __y0 __x1 __y1
		# Overlap, not containment: a stripe crossing the site only clips it.
		set __hit 0
		foreach __bx $DCO_BOXES {
			lassign $__bx __kx0 __ky0 __kx1 __ky1
			if {$__x1 > $__kx0 && $__x0 < $__kx1 && $__y1 > $__ky0 && $__y0 < $__ky1} {
				set __hit 1
				break
			}
		}
		if {$__hit} { dbDeleteObj $__w; incr __pgswept }
	}
	foreach __v [dbGet $__net.sVias] {
		set __px 0 ; set __py 0
		catch { set __px [dbGet $__v.pt_x] }
		catch { set __py [dbGet $__v.pt_y] }
		if {[__in_any_box $__px $__py $DCO_BOXES]} { dbDeleteObj $__v; incr __pgswept }
	}
}
puts "### UNL STATUS ### : DCO keepout sweep removed $__pgswept M7/M8 PG shape(s)/via(s)"

# --- VIA7 CENSUS + TILE SWEEP.  This is THE fix for the VIA7 class analysed at
# the M7 addStripe pass above, not a backstop to one.
#
# WHAT IT REMOVES.  Any top-level VDD/VSS VIA7 array whose placement point lies
# inside the hart_tile footprint.  Such an array can only be a duplicate of one
# the tile already carries: the tile's M7 and M8 PG pins are tied to each other
# INSIDE the macro, so the only thing a top-level M7-to-M8 via over the tile can
# add is a second cut array 0.05 um from the tile's own.  The mesh keeps its
# connection to the tile the same way it always had it -- the M7 stripe lies on
# the tile's M7 PG pin, same net, same layer, no via involved.
#
# THE CENSUS IS PRINTED WHETHER OR NOT ANYTHING IS SWEPT, because a count is the
# only way to tell "there was nothing to sweep" from "the attribute path is wrong
# and this loop matched nothing silently".  The via master names seen are printed
# for the same reason -- dbGet returning "" on a bad path is this file's
# recurring trap (RING_NUKE, the DCO sweep, the instTerms PG census).
#
# IT IS A PROC AND IT IS CALLED THREE TIMES, and that is MEASURED rather than
# defensive.  A control run (option removed, floorplan stage only) prints:
#     VIA7 census [post-addStripe]       2448 arrays, 12 inside the tile
#     VIA7 census [post-sroute-fixVia]   2476 arrays, 13 inside the tile
# i.e. after the post-addStripe sweep has deleted all 12, SROUTE PUTS THEM BACK
# and adds one more.  The blockPin sroute pass straps the tile's LEF PG pins and
# is a second, independent VIA7 source over exactly the same geometry.  A sweep
# called once here would have cleaned nothing that survived to the GDS.
# 2476 and 13 are also, to the digit, what the finished 2026-08-24 database
# carried, which is what says the two sources between them are all of it.
set TILE_BBOX [list $TILE_X $TILE_Y \
                    [expr {$TILE_X + $TILE_W}] [expr {$TILE_Y + $TILE_H}]]
proc sweep_tile_via7 {tag bbox} {
	lassign $bbox tx0 ty0 tx1 ty1
	set total 0 ; set swept 0
	array set names {}
	foreach n {VDD VSS} {
		set net [dbGet -p top.nets.name $n -e]
		if {$net eq "" || $net eq "0x0"} { continue }
		foreach v [dbGet $net.sVias] {
			set vn ""
			catch { set vn [dbGet $v.via.name] }
			if {![string match -nocase "*via7*" $vn]} { continue }
			incr total
			if {[info exists names($vn)]} { incr names($vn) } else { set names($vn) 1 }
			set px 0 ; set py 0
			catch { set px [dbGet $v.pt_x] }
			catch { set py [dbGet $v.pt_y] }
			if {$px >= $tx0 && $px <= $tx1 && $py >= $ty0 && $py <= $ty1} {
				dbDeleteObj $v
				incr swept
			}
		}
	}
	puts "### UNL STATUS ### : VIA7 census \[$tag\] -- $total top-level VDD/VSS VIA7 array(s), masters [lsort [array names names]]"
	puts "### UNL STATUS ### : VIA7 tile sweep \[$tag\] -- $swept deleted inside hart_tile bbox ($tx0,$ty0)..($tx1,$ty1)"
	if {$total == 0} {
		puts "### UNL STATUS ### : WARNING \[$tag\] -- VIA7 census found ZERO arrays.  Either"
		puts "### UNL STATUS ### :   the mesh has no M7-to-M8 vias at all (a real defect) or"
		puts "### UNL STATUS ### :   dbGet <sVia>.via.name returned nothing (a script defect)."
	}
	return $swept
}
sweep_tile_via7 post-addStripe $TILE_BBOX

editTrim -all
setCheckMode -globalNet true -io true -route true -tapeOut true

printStatus "Routing power rails"
setSrouteMode -corePinMaxViaScale "100 10"
# -area caps the strapping BELOW the tile's notch-floor ring band.  Without it,
# blockPin sroute straps the tile's notch-floor-ring PG pins and its M8 jumpers
# and M7 stack vias run 0.5 um from the tile LEF blockage.  The tile's U-ring is
# a closed loop, so the straps onto the tile base's pins power all of it; the
# skipped top-leg pins are redundancy only.
sroute \
	-nets { VSS VDD } \
	-allowLayerChange 0 \
	-allowJogging 0 \
	-connect {blockPin corePin} \
	-blockPin useLef \
	-area [list 0 0 $DESIGN_WIDTH [expr {$NOTCH_FLOOR_Y - 20}]] \
    -corePinWidth 0.3

# Second, JOGGING block-pin pass over the control-band analog macros only.  The
# straight-line pass above connects a macro's full-width M3 PG strips only where
# an M7 stripe happens to cross it; this pass exists so a macro nudge can never
# silently strand a PG pin again.
if {$ANALOG_N > 0} {
	printStatus "Routing analog-macro PG pins (jogging backstop pass)"
	sroute \
		-nets { VSS VDD } \
		-connect { blockPin } \
		-blockPin useLef \
		-allowLayerChange 1 \
		-allowJogging 1 \
		-layerChangeRange { M3(3) M7(7) } \
		-area [list [expr {$ANALOG_X0 - 20}] [expr {$AMY - 20}] [expr {$ANALOG_X1 + 20}] [expr {$AMY + 60}]]
}

# --- PG VERIFICATION, before anything expensive.  The PG2-F1 failure class is
# a sourceless VDD_SW / an unrouted macro: Innovus prints the message, returns
# rc=0, and tcl catch never fires.  Count the special wires per macro now and
# print them; zero on a macro means the PG was never routed to it. ---
printStatus "PG hookup census"
foreach m [concat $TILE_INSTS $SH16K_INSTS [list $ROM_INST] $POR_INSTS $DCO_INSTS $GF_INSTS] {
	set ip [dbGet -p top.insts.name $m -e]
	if {$ip eq "" || $ip eq "0x0"} { continue }
	set nvdd 0 ; set nvss 0
	catch {
		foreach t [dbGet $ip.instTerms] {
			set nn ""
			catch { set nn [dbGet $t.net.name] }
			if {$nn eq "VDD"} { incr nvdd }
			if {$nn eq "VSS"} { incr nvss }
		}
	}
	puts "### UNL STATUS ### : PG $m -- VDD terms $nvdd , VSS terms $nvss"
}

verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$BASENAME.verifyGeometry.preplace.rpt
fixVia -short
fixVia -minCut
fixVia -minStep

# Second call.  sroute, editTrim and the three fixVia passes all create special
# vias, and the 2026-08-24 database proves at least one duplicate VIA7 array over
# the tile arrives after addStripe has finished.
sweep_tile_via7 post-sroute-fixVia $TILE_BBOX

# Reserve M7/M8 for power during signal routing.
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -layer 7
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -layer 8

saveDesign $DATABASE_DIR/$BASENAME.fplan.innovus -def -netlist -rc -tcon

# CHECKPOINT HOOK.  The floorplan and the power plan are cheap; place_opt_design
# onwards is the expensive stage (the comparable TCM swap burned ~25.5 hours
# across two failed P&R attempts).  With MCU_HART_STOP_AFTER_FPLAN=1 the script
# stops here, after the pre-place verifyGeometry and the saved fplan database,
# so the floorplan and power plan can be REVIEWED AGAINST MEASURED NUMBERS
# before any of that time is committed.  Unset, the flow runs straight through
# and this is a no-op.
if {[info exists ::env(MCU_HART_STOP_AFTER_FPLAN)]
    && $::env(MCU_HART_STOP_AFTER_FPLAN) == 1} {
	puts "### UNL STATUS ### : MCU_HART_STOP_AFTER_FPLAN=1 -- stopping after floorplan + power plan"
	puts "### UNL STATUS ### : database saved at $DATABASE_DIR/$BASENAME.fplan.innovus"
	toc
	exit 0
}
printStatus "Saved floorplan+PG checkpoint DB"

################################################################################
# Placement
################################################################################
# Spurious clock-gating checks on the TIMER ClockMuxGlitchFree select legs:
# Innovus infers an AND-gate gating check (enable stable until mclk's falling
# edge) that is unmeetable and irrelevant -- the mux is glitch-free by
# construction (each leg's select is double-synced onto its own clock).  Without
# the disable, hold fixing burns delay cells chasing a check that cannot be met.
# Gate names are genus-mapped: if a resynth renames them, find the violating
# gating endpoint in the hold signoff report and update this list.
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
set_ccopt_property routing_top_min_fanout 10000

set_ccopt_property buffer_cells   {BUFX0P7BA10TH BUFX0P8BA10TH BUFX11BA10TH BUFX13BA10TH BUFX16BA10TH BUFX1BA10TH BUFX1P2BA10TH BUFX1P4BA10TH BUFX1P7BA10TH BUFX2BA10TH BUFX2P5BA10TH BUFX3BA10TH BUFX3P5BA10TH BUFX4BA10TH BUFX5BA10TH BUFX6BA10TH BUFX7P5BA10TH BUFX9BA10TH}
set_ccopt_property inverter_cells {INVX0P5BA10TH INVX0P6BA10TH INVX0P7BA10TH INVX0P8BA10TH INVX11BA10TH INVX13BA10TH INVX16BA10TH INVX1BA10TH INVX1P2BA10TH INVX1P4BA10TH INVX1P7BA10TH INVX2BA10TH INVX2P5BA10TH INVX3BA10TH INVX3P5BA10TH INVX4BA10TH INVX5BA10TH INVX6BA10TH INVX7P5BA10TH INVX9BA10TH}
set_ccopt_property delay_cells    {DLY2X0P5MA10TH DLY4X0P5MA10TH}
set_ccopt_property use_inverters true
set_ccopt_property target_max_trans 400ps

create_ccopt_clock_tree_spec
ccopt_design
optDesign -postCTS -hold
catch {report_power -outfile $REPORT_DIR/${BASENAME}_postCTS_full.power}
timeDesign -postCTS -expandedViews -outDir $REPORT_DIR/$BASENAME.timeDesign.postcts
report_ccopt_clock_trees -file $REPORT_DIR/$BASENAME.report_ccopt_clock_trees.postcts
report_ccopt_skew_groups -file $REPORT_DIR/$BASENAME.report_ccopt_skew_groups.postcts
saveDesign $DATABASE_DIR/$BASENAME.postcts.innovus -def -netlist -rc -tcon
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
# SI-aware hold cleanup.  'optDesign -postRoute -si -hold' is OBSOLETE in 20.12
# (IMPOPT-7016 aborts the script); the ECO form is SIAware delaycal plus a
# plain hold opt.  The +10 ps hold target stops the ECO converging to -0.000
# (a sub-ps VIOLATED at a tile clk pin) instead of inserting the last delay cell.
setDelayCalMode -SIAware true
setOptMode -holdTargetSlack 0.01
optDesign -postRoute -hold
setOptMode -holdTargetSlack 0
catch {report_power -outfile $REPORT_DIR/${BASENAME}_postRoute_full.power}

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

# Third and last call, after every routing and ECO stage that could re-create a
# duplicate.  This one is also the CHECK: by here it should sweep ZERO, and a
# non-zero count means a post-route stage is still putting VIA7 over the tile.
sweep_tile_via7 post-route $TILE_BBOX

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
# Output files (top-only netlist/SDF; the tile interior comes from the tile
# harden's ../hart_tile/out/hart_tile.{xsim.v,sdf} at gate-sim time)
################################################################################
streamOut \
    $OUTPUT_DIR/$BASENAME.gds2 \
    -libName WorkLib \
    -structureName $DESIGN_NAME \
    -stripes 1 \
    -units 1000 \
    -mode ALL \
    -merge [list ../hart_tile/out/hart_tile.gds2] \
    -mapFile ../shared/innovus2gds.map

printStatus "Writing SDF (top level)"
write_sdf $OUTPUT_DIR/$BASENAME.sdf

printStatus "Writing verilog for Xcelium (top level; hart_tile as a leaf ref)"
saveNetlist \
    $OUTPUT_DIR/$BASENAME.xsim.v \
    -excludeCellInst ANTENNA2A10TH

saveDesign $DATABASE_DIR/$BASENAME.final.innovus -def -netlist -rc -tcon
toc
printStatus "MCU_hart block assembly complete"
exit
