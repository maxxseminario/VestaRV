################################################################################
# Innovus script -- MCU_ARGUS TOP-LEVEL ASSEMBLY (A4; 18-tile teaching chip)
#
# Hierarchical assembly of the 18-hart Argus MCU on the 2690x2690 M15 pad-ring
# interior. The 18 hart instances (hart0-17) are the HARDENED compact tile
# (405x685 plain rectangle -- NO analog notch; Argus is digital-only):
# footprint from out/hart_tile_argus.lef, timing from the per-corner ETMs
# out/hart_tile_argus.etm_{ss,ff}.lib.
#
# === v4 FLOORPLAN (v3 was topologically dead -- read this before touching) ===
# The tile's 489 signal pins are ALL on M4 at its local BOTTOM edge (y 0..0.5),
# and its OBS covers 100% of M1-M6. v3 stacked the 3 rows FLUSH, which sealed
# the 12 upper tiles' pins against the OBS of the tile below (preplace: exactly
# 489x12 = 5868 pin-vs-blockage shorts) and forced ALL their nets through the
# 5x40um inter-column channels: the row-0 horizontal cut needed ~2x the
# corridor's track supply. The detail router "finished" by tunnelling through
# row-0 tile OBS: 303k violations, 97.8% of them inside row 0's y-band. The
# 5-7% eGR overflow that made v3 look solved is a DIE-WIDE AVERAGE -- the
# corridor-local overflow was ~150%. No ecoRoute iteration fixes topology.
#
# v4 fixes both problems structurally, with the same 6-column x-geometry:
#   BOTTOM  : 8 shared-RAM banks (unchanged x layout, y=11).
#   B1 band : 166um control band (arbiter, peripherals, ROM R90, analog
#             macros, CLINT) -- the main std-cell region, as v3.
#   row 0   : R0  (pins DOWN into B1)                y  568..1253
#   row 1   : MX  (pins UP -- flipped!)              y 1253..1938
#   B2 band : 30um std-cell band BETWEEN rows 1 and 2, y 1938..1968.
#             Row 1's pins face its bottom edge, row 2's pins face its top
#             edge. B2 is a pin-escape + tie/buffer band (irtr0 itself is
#             region'd into B1 -- the v4.5 note below). M19c: the 18x85
#             tile_irq_en fan-out and the 85-wide gf vector to tiles are
#             GONE -- irtr0 sends ONE meip wire per tile (the deglitched
#             vector terminates inside the router); per-tile TIELO/TIEHI
#             constant pins drop ~155 -> ~64 (hart_id/flash_dout;
#             irq_prio_ext retired with the M19 ports).
#   row 2   : R0  (pins DOWN into B2)                y 1968..2653
# Cut math after the move: rows 1+2 send only their ~135 real fabric nets per
# tile (sh bus ~95, a0/trap 33, pd/misc) through the channels: ~1730 tracks
# vs ~2700 usable (5 channels x M2/M4/M6 + margins) = ~64%. Row-2 cut ~0.
# No pin faces an OBS anywhere: zero abutment shorts by construction.
#
# === v4 POWER GRID (v3's full-die stripes were chopped by the tile LEFs) ===
# The tile LEF blocks M7 (60%) / M8 (66%) and exposes its PG as FULL-HEIGHT
# M7 stripe pins at fixed x offsets (VDD 51+50k, VSS 60+50k, k=0..6, 5um wide,
# y 0..685, tips explicit at both edges) -- and MX preserves x. So the top
# grid is drawn as M7 "lanes" EXACTLY on those pin x-positions per column:
#   pass A: y 0..row0+4 (RAM band + B1), stacked vias M1..M8 -- ties bottom
#           ring, M8 rails, sram/ROM M4 PG pins, B1 follow-pins, and overlaps
#           the row-0 tile pin tips by 4um (tip lanes are OBS-free in the LEF).
#   pass B: y row0..GRID_TOP, NO vias (top=bottom=M7) -- same-net overlay on
#           the tile pin stripes through all 3 rows and B2: stitches the
#           row-boundary abutments into explicit special wires.
#   B2 M8 pair: one VDD/VSS pair across the full-width B2 band (no tiles at
#           that y), stacked_via_bottom M7 -> drops VIA7 onto every lane.
# M8 horizontal grid only in y<566 (RAM+B1), PG4 knob -stacked_via_bottom M7.
# Analog macros that sit between lane groups get a dedicated rescue pair at
# their center (por/gf risk class -- the MCU_MP irq_gf2 stranded-pin lesson).
# sroute is -area capped to B1/RAM + a corePin-only pass for B2 rails + the
# MCU_MP-style jogging blockPin backstop over the analog band only.
# NOTE (PG-track): the pmk VDDG/VNW/VPW hookup stays the pre-PG4 form = the
# documented PG2-F1 phantom; the fix is the PG-track re-harden, NOT A4's.
#
# meip_in (M19c; replaces the retired hw_clint_en strap): the router's
# per-hart claim/complete output -- ONE wire per tile from irtr0, wired
# EXPLICITLY per hart in the Argus MCU.vhd, so the M14 "VHDL default lost at
# the netlist boundary" class does not apply. msip/mtip wiring unchanged.
# Tile pin total drops ~255 vs the M17 netlist (irq_ext/irq_en_ext/
# irq_prio_ext/irq_recursion_en/hw_clint_en/isr_ret retired).
#
# Netlist: in/MCU_ARGUS_hier.pnr.v = MCU_ARGUS_hier.genus.v with the hart_tile
# subtree stripped (prep_top_netlist_argus.sh) so innovus binds hart_tile to
# the LEF macro. Output: top-only netlist/SDF (tile interiors come from the
# tile harden's out/hart_tile_argus.{xsim.v,sdf} at gate-sim time).
################################################################################
#
# === v5 (A7) SUPERSEDES v4 -- 2-axis interior symmetry (2026-07-16) ===========
# FROZEN geometry: ~/vesta_docs/argus/a7/a7_architecture.md (Option A + B1 rule).
# The v4 MX-flip + single-B2 topology described above is HISTORY. v5 layout:
#   banks 8..391.085 / B1 395.085..561.085 (unchanged)
#   row0 R0 @565.085    (pins DOWN into B1, as v4)
#   bandA    1250.085..1268.085  (18um std-cell escape band; row1 pins face it)
#   row1 R0  @1268.085  (pins DOWN into bandA -- the MX flip is GONE)
#   bandB    1953.085..1971.085  (18um; row2 pins face it)
#   row2 R0  @1971.085  (pins DOWN into bandB)
#   GRID_TOP 2656.085   ROW_ORIENT {R0 R0 R0}  ROW_XOFF {0 0 0}
# Every row's pins face DOWN into its own band => no two pin edges ever face
# each other => the MX twin-pin M4 short class is dead by construction, so
# ROW_XOFF is 0 on all rows (via arrays coincident on all three rows ->
# VIA7.S.1/S.2 retired by construction, not just rows 0/1). Interior symmetric
# about the x=1345 die axis (columns already symmetric; B1 analog macros now
# balanced -- dco0<->dco1, irq_gf0<->irq_gf2 EXACT mirror pairs, por+irq_gf1
# approx) AND about the array centerline y=1610.585 (middle row centered, two
# equal bands). Everything the single B2 band owned is now done PER BAND (kill
# zones, channel/margin blockages, relief screens, M8 pair, corePin sroute).
# PG lane pass A/B formulas unchanged (the y vars flow through).
# ==============================================================================

source tcl/constants.tcl
source $SCRIPT_DIR/procedures.tcl
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
					$OUTPUT_DIR/hart_tile_argus.lef"

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

# --- v5 (A7) vertical budget: two equal 18um escape bands, uniform R0 rows.
# SH_Y=8 kept from v4 (funded the band budget when SH_Y went 11->8; see the v4
# war story). v5 has TWO 18um bands (bandA, bandB) instead of the single 37um
# B2: BAND_H*2 = 36um total inter-row gap vs v4's 37, grid top 2656.085 leaves
# 1.415um to the FATAL cap 2657.5 (M8-M8 spacing at these widths needs ~2, and
# the top-of-grid M8 pair sits inside bandB not at GRID_TOP). Bands even-um
# (2.0 row-grid parity, CQ lesson). ~/vesta_docs/argus/a7/a7_architecture.md. ---
set SH_Y     8
set SH_GAP   10
set SH_SPAN  [expr {8 * $SRAM16K_WIDTH + 7 * $SH_GAP}]
set SH_X0    [expr {($DESIGN_WIDTH - $SH_SPAN) / 2.0}]
set BANK_TOP     [expr {$SH_Y + $SRAM16K_HEIGHT}]        ;# 391.085
set B1_Y0        [expr {$BANK_TOP + 4}]                  ;# 395.085
set B1_H         166
set B1_Y1        [expr {$B1_Y0 + $B1_H}]                 ;# 561.085
set BAND_H       18
set Y_R0         [expr {$B1_Y1 + 4}]                     ;# 565.085 (row0 pins face B1)
set Y_R1         [expr {$Y_R0 + $TILE_H + $BAND_H}]      ;# 1268.085 (row1 pins face bandA)
set Y_R2         [expr {$Y_R1 + $TILE_H + $BAND_H}]      ;# 1971.085 (row2 pins face bandB)
set GRID_TOP     [expr {$Y_R2 + $TILE_H}]               ;# 2656.085
set BANDA_Y0     [expr {$Y_R1 - $BAND_H}]               ;# 1250.085 (row0 top .. row1 bottom)
set BANDA_Y1     $Y_R1                                  ;# 1268.085
set BANDB_Y0     [expr {$Y_R2 - $BAND_H}]               ;# 1953.085 (row1 top .. row2 bottom)
set BANDB_Y1     $Y_R2                                  ;# 1971.085
plog "### UNL STATUS ### : v5(A7) y-map  banks $SH_Y..[format %.1f $BANK_TOP]  B1 [format %.1f $B1_Y0]..[format %.1f $B1_Y1]  row0 [format %.1f $Y_R0]  bandA [format %.1f $BANDA_Y0]..[format %.1f $BANDA_Y1]  row1 [format %.1f $Y_R1]  bandB [format %.1f $BANDB_Y0]..[format %.1f $BANDB_Y1]  row2 [format %.1f $Y_R2]  grid top [format %.1f $GRID_TOP] (ring ~2661)"
if {$GRID_TOP > 2657.5} { plog "### UNL FATAL ### : grid top $GRID_TOP crowds the top ring (~2661)"; exit 1 }

# --- Shared-RAM row ---
set i 0
foreach m {shbank0 shbank1 shbank2 shbank3 shbank4 shbank5 shbank6 shbank7} {
	placeInstance $m [expr {$SH_X0 + $i * ($SRAM16K_WIDTH + $SH_GAP)}] $SH_Y R0
	addHaloToBlock 2 2 2 2 $m
	incr i
}
cutRow

# --- B1 control band: ROM R90 + analog macros; std cells fill around them.
# v5/A7: analog macros balanced about the x=1345 die axis (rom0 is unique --
# no mirror partner exists -- so it stays at its v4 left slot). Identical-macro
# pairs at EXACT mirror x (x_R = 2690 - x_L - w): dco0<->dco1 (w=58.17),
# irq_gf0<->irq_gf2 (w=31.195). por (w=26.41) + irq_gf1 (w=31.195) at
# approximately mirrored slots (different widths -- visual balance, not exact
# footprint mirror). All within B1, clear of the rom0 R90 span (x 40..365) and
# of each other's halos. ~/vesta_docs/argus/a7/a7_architecture.md. ---
set MACRO_Y [expr {$B1_Y0 + 6}]
placeInstance rom0 40 $MACRO_Y R90
addHaloToBlock 6 6 6 6 rom0
placeInstance por     420 $MACRO_Y R0
addHaloToBlock 4 4 4 4 por
placeInstance dco0    560 $MACRO_Y R0
addHaloToBlock 4 4 4 4 dco0
placeInstance irq_gf0 840 $MACRO_Y R0
addHaloToBlock 4 4 4 4 irq_gf0
placeInstance irq_gf2 1818.805 $MACRO_Y R0
addHaloToBlock 4 4 4 4 irq_gf2
placeInstance dco1    2071.83 $MACRO_Y R0
addHaloToBlock 4 4 4 4 dco1
placeInstance irq_gf1 2238.805 $MACRO_Y R0
addHaloToBlock 4 4 4 4 irq_gf1
cutRow

# --- 18-tile grid (v5/A7): 6 full-width cols; ALL rows R0 (pins DOWN). Two
# equal 18um escape bands (bandA between rows 0/1, bandB between rows 1/2) each
# host ONE row's pin escapes -- row0's pins face B1, row1's face bandA, row2's
# face bandB. No two pin edges ever face each other (the point of the design),
# so the MX twin-pin M4 short class is dead by construction. Symmetric about
# x=1345 (columns) and about the array centerline y=1610.585. Column x-geometry
# unchanged: TILE_X0=30, gap 40. ---
set TILE_SIDE_MARGIN 30
set TILE_GRID_GAP [expr {($DESIGN_WIDTH - 2*$TILE_SIDE_MARGIN - $NCOLS*$TILE_W) / double($NCOLS - 1)}]
set TILE_X0 $TILE_SIDE_MARGIN
set ROW_Y      [list $Y_R0 $Y_R1 $Y_R2]
set ROW_ORIENT [list R0 R0 R0]
# v5/A7: ROW_XOFF = {0 0 0}. The v4 MX flip is GONE (uniform R0), so the
# row-1/row-2 twin-pin M4 short that the v4.10 0.5um / v4.11 0.9um row-2 offset
# fought no longer exists structurally -- every row's pins face DOWN into its
# own band. VIA-PHASE RULE (A6 chip-signoff DRC post-mortem): every deliberate
# offset must be a MULTIPLE OF THE 0.9um VIA7 stacked-via array pitch; 0 is the
# trivial multiple, so on ALL THREE rows the assembly-grid VIA7 arrays and the
# tile's own M7->M8 PG via arrays land COINCIDENT (legal merged cuts) -- the
# zero-violation rows-0/1 property now extends to row 2 => VIA7.S.1/S.2 retired
# by construction (verdict still proven at signoff, per the a7 plan).
set ROW_XOFF   [list 0 0 0]
for {set row 0} {$row < $NROWS} {incr row} {
	for {set col 0} {$col < $NCOLS} {incr col} {
		set h [expr {$row * $NCOLS + $col}]
		set tx [expr {$TILE_X0 + $col * ($TILE_W + $TILE_GRID_GAP) + [lindex $ROW_XOFF $row]}]
		placeInstance hart$h $tx [lindex $ROW_Y $row] [lindex $ROW_ORIENT $row]
		addHaloToBlock 4 4 4 4 hart$h
	}
}
cutRow
plog "### UNL STATUS ### : placed 18 tiles (6 cols, all rows R0, col gap [format %.1f $TILE_GRID_GAP]), bandA [format %.1f $BANDA_Y0]..[format %.1f $BANDA_Y1] bandB [format %.1f $BANDB_Y0]..[format %.1f $BANDB_Y1]"
printStatus "Placed all macros"

# --- Kill every row outside B1/bandA/bandB (v5/A7): FOUR kill zones -- below
# B1, the row0 tile span, the row1 tile span, and the row2 span + top sliver.
# Rows surviving in the channels, margins, RAM-band gaps or the top sliver
# would carry FLOATING follow-pin rails (the MCU_MP orphaned-PG war stories).
# cutRow -area only cuts under an obstacle, so blockage first (M17 lesson); the
# blockages also stop placement/welltaps from re-entering when later steps
# re-fracture rows. v4.1 fringe lesson preserved: the low block starts at B1_Y1
# (not Y_R0), and each band's channel x-ranges + side margins are blocked/cut
# (tile halos fracture the band's edge rows into floating fragments). ---
createPlaceBlockage -type hard -name below_b1 -box [list 0 0 $DESIGN_WIDTH $B1_Y0]
cutRow -area [list 0 0 $DESIGN_WIDTH $B1_Y0]
createPlaceBlockage -type hard -name row0span -box [list 0 $B1_Y1 $DESIGN_WIDTH $BANDA_Y0]
cutRow -area [list 0 $B1_Y1 $DESIGN_WIDTH $BANDA_Y0]
createPlaceBlockage -type hard -name row1span -box [list 0 $BANDA_Y1 $DESIGN_WIDTH $BANDB_Y0]
cutRow -area [list 0 $BANDA_Y1 $DESIGN_WIDTH $BANDB_Y0]
createPlaceBlockage -type hard -name row2span -box [list 0 $BANDB_Y1 $DESIGN_WIDTH $DESIGN_HEIGHT]
cutRow -area [list 0 $BANDB_Y1 $DESIGN_WIDTH $DESIGN_HEIGHT]
# per-band channel-gap + side-margin kills: bandA and bandB EACH get what the
# single v4 B2 band had (b2chan/b2marL/b2marR pattern, per band).
foreach {band by0 by1} [list A $BANDA_Y0 $BANDA_Y1 B $BANDB_Y0 $BANDB_Y1] {
	for {set g 0} {$g < [expr {$NCOLS - 1}]} {incr g} {
		set gx0 [expr {$TILE_X0 + $TILE_W + $g * ($TILE_W + $TILE_GRID_GAP)}]
		createPlaceBlockage -type hard -name band${band}chan$g \
			-box [list $gx0 $by0 [expr {$gx0 + $TILE_GRID_GAP}] $by1]
		cutRow -area [list $gx0 $by0 [expr {$gx0 + $TILE_GRID_GAP}] $by1]
	}
	createPlaceBlockage -type hard -name band${band}marL -box [list 0 $by0 $TILE_X0 $by1]
	cutRow -area [list 0 $by0 $TILE_X0 $by1]
	createPlaceBlockage -type hard -name band${band}marR -box [list [expr {$DESIGN_WIDTH - $TILE_SIDE_MARGIN}] $by0 $DESIGN_WIDTH $by1]
	cutRow -area [list [expr {$DESIGN_WIDTH - $TILE_SIDE_MARGIN}] $by0 $DESIGN_WIDTH $by1]
}
# v4.15/v4.16 relief preserved, PER BAND: the residual channel-mouth short
# migrates to whichever of the 5 mouths is unscreened; 50% soft-density screen
# +/-70um around each mouth = fewer pins, more routing slack. Each band now
# hosts ONE row's escapes (half the v4 single-B2 load), same screen recipe.
foreach {band by0 by1} [list A $BANDA_Y0 $BANDA_Y1 B $BANDB_Y0 $BANDB_Y1] {
	for {set g 0} {$g < [expr {$NCOLS - 1}]} {incr g} {
		set chx [expr {$TILE_X0 + $TILE_W + $g * ($TILE_W + $TILE_GRID_GAP)}]
		createPlaceBlockage -type partial -density 50 -name band${band}relief$g \
			-box [list [expr {$chx - 70}] $by0 [expr {$chx + $TILE_GRID_GAP + 70}] $by1]
	}
}
plog "### UNL STATUS ### : rows restricted to B1 + bandA + bandB (channel/margin/fringe rails killed)"

# --- Chip pins: all on the BOTTOM edge (digital-only, north face empty) ---
set ALL_PINS [dbGet top.terms.name]
puts "Assigning [llength $ALL_PINS] pins to the bottom edge"
editPin -pin $ALL_PINS -side Bottom -layer 4 -spreadType side -spacing 2 -fixOverlap 1
printStatus "Placed chip pins (all bottom)"

################################################################################
# Power: full rectangular ring + tile-pin-aligned M7 lanes (see header)
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

# --- M8 horizontal grid: RAM band + B1 only (y<566: 2um below the row-0 tile
# M8 OBS at 568). PG4 knob: bottom M7 so this pass never punches macro-pin
# stacks of its own (the M7 lane pass owns those; interleaved same-net VIA7
# arrays were the PG3 headline DRC). ---
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
	-area [list 0 0 $DESIGN_WIDTH 566] \
	-set_to_set_distance $POWER_STRIPE_SET_TO_SET \
	-spacing $POWER_STRIPE_PATH_SPACING \
	-width $POWER_STRIPE_PATH_WIDTH \
	-block_ring_bottom_layer_limit M1 \
	-start_offset $POWER_STRIPE_SET_TO_SET \
	-stop_offset $POWER_STRIPE_PATH_SPACING

# --- M7 lanes on the tile PG pin x-offsets. Per column c (x0 = 30+445c):
# VDD lanes at x0+51+50k, VSS at x0+60+50k (k=0..6) -- from the tile LEF. ---
set LANE_SPECS {}
for {set col 0} {$col < $NCOLS} {incr col} {
	set cx [expr {$TILE_X0 + $col * ($TILE_W + $TILE_GRID_GAP)}]
	for {set k 0} {$k < 7} {incr k} {
		lappend LANE_SPECS [list VDD [expr {$cx + 51 + 50*$k}]]
		lappend LANE_SPECS [list VSS [expr {$cx + 60 + 50*$k}]]
	}
}
# ext: 'ring' extends the stripe ENDS to the closest ring -- REGARDLESS of the
# -area bound (v4.2: the gf rescue pairs' top ends extended from Y_R0 through
# the tile columns to the TOP ring at non-lane x = 20 M7 shorts vs tile OBS;
# the ROM minis extended rightward through the DCOs' M8 OBS = 18 more). The
# lanes keep 'ring' (bottom-ring tie; their top ends merge into pass B / the
# top ring over clear margin). Rescue/gap/mini passes use 'none' -- they are
# tied by their M8-grid / lane crossings and must not leave their area.
proc lane_stripe {net x y0 y1 viatop viabot {ext ring}} {
	setAddStripeMode \
		-remove_floating_stripe_over_block true \
		-trim_antenna_back_to_shape core_ring \
		-stacked_via_top_layer $viatop \
		-stacked_via_bottom_layer $viabot \
		-extend_to_closest_target $ext
	addStripe \
		-layer M7 \
		-nets [list $net] \
		-direction vertical \
		-start_from left \
		-area [list $x $y0 [expr {$x + 5}] $y1] \
		-set_to_set_distance 1000 \
		-width 5 \
		-block_ring_bottom_layer_limit M1 \
		-start_offset 0 \
		-stop_offset 0
}
# pass A: bottom grid segment (full via stacks; overlaps the row-0 pin tips)
foreach spec $LANE_SPECS {
	lane_stripe [lindex $spec 0] [lindex $spec 1] 0 [expr {$Y_R0 + 4}] M8 M1
}
plog "### UNL STATUS ### : pass A drew [llength $LANE_SPECS] bottom-grid lanes"
# pass B: via-less overlay across the 3 tile rows + B2 (stitches abutments)
foreach spec $LANE_SPECS {
	lane_stripe [lindex $spec 0] [lindex $spec 1] $Y_R0 $GRID_TOP M7 M7
}
plog "### UNL STATUS ### : pass B drew [llength $LANE_SPECS] tile-overlay lanes"

# --- Analog-macro rescue pairs. v4.1 trigger fix: what connects a macro's
# full-width HORIZONTAL pin strips (gf/por M3, per M17b) is a lane pair
# CROSSING the macro body -- center DISTANCE is meaningless (v4.0 skipped
# gf0/gf1 at "18um from a lane" whose lanes never entered the macro; their
# M3 strips floated). Trigger on per-net lane containment in the macro span. ---
set LANE_VDD {}
set LANE_VSS {}
foreach spec $LANE_SPECS {
	if {[lindex $spec 0] eq "VDD"} { lappend LANE_VDD [lindex $spec 1] } else { lappend LANE_VSS [lindex $spec 1] }
}
foreach m {por dco0 irq_gf0 irq_gf2 dco1 irq_gf1} {
	set ip [dbGet -p top.insts.name $m]
	if {$ip eq "" || $ip eq "0x0"} { plog "### UNL WARN ### : rescue-pair skip, inst $m not found"; continue }
	set x0 [expr {[dbGet $ip.box_llx] + 1}]
	set x1 [expr {[dbGet $ip.box_urx] - 1}]
	set cx [expr {($x0 + $x1) / 2.0}]
	set haveV 0
	set haveS 0
	foreach lx $LANE_VDD { if {$lx >= $x0 && $lx + 5 <= $x1} { set haveV 1 } }
	foreach lx $LANE_VSS { if {$lx >= $x0 && $lx + 5 <= $x1} { set haveS 1 } }
	if {$haveV && $haveS} {
		plog "### UNL STATUS ### : $m crossed by VDD+VSS lanes, no rescue pair"
	} else {
		lane_stripe VDD [expr {$cx - 9.5}] 0 [expr {$Y_R0 - 2}] M8 M1 none
		lane_stripe VSS [expr {$cx + 4.5}] 0 [expr {$Y_R0 - 2}] M8 M1 none
		plog "### UNL STATUS ### : rescue PG pair at x=[format %.1f $cx] for $m (lane coverage VDD=$haveV VSS=$haveS)"
	}
}

# --- Analog-macro GAP pairs (v4.2): a row sliver BETWEEN two adjacent analog
# macros is fractured by their halos; if no lane crosses the gap its rails
# float (v4.1: 10 fragments in the 61um gf0-gf1 gap -- both neighbors had
# center-pairs, the gap itself had nothing). One pair per uncovered gap.
# v5/A7: this loop AND the rescue loop above iterate the macro list in ASCENDING
# FINAL X (por dco0 irq_gf0 irq_gf2 dco1 irq_gf1) -- the prev_urx running
# variable assumes monotonic x, so the balanced (full-width) placement must be
# walked left-to-right or the gap detection sees negative spans. ---
set prev_urx -1
set prev_name {}
foreach m {por dco0 irq_gf0 irq_gf2 dco1 irq_gf1} {
	set ip [dbGet -p top.insts.name $m]
	if {$ip eq "" || $ip eq "0x0"} { continue }
	set llx [dbGet $ip.box_llx]
	set urx [dbGet $ip.box_urx]
	if {$prev_urx > 0} {
		set g0 [expr {$prev_urx + 1}]
		set g1 [expr {$llx - 1}]
		if {$g1 - $g0 >= 15} {
			set covered 0
			foreach lx [concat $LANE_VDD $LANE_VSS] {
				if {$lx >= $g0 && $lx + 5 <= $g1} { set covered 1 }
			}
			# rescue pairs sit at macro centers, never in gaps -- but check
			# anyway so future placements can't double-draw
			if {!$covered} {
				set gc [expr {($g0 + $g1) / 2.0}]
				lane_stripe VDD [expr {$gc - 9.5}] 0 [expr {$Y_R0 - 2}] M8 M1 none
				lane_stripe VSS [expr {$gc + 4.5}] 0 [expr {$Y_R0 - 2}] M8 M1 none
				plog "### UNL STATUS ### : gap PG pair at x=[format %.1f $gc] ($prev_name<->$m sliver)"
			}
		}
	}
	set prev_urx $urx
	set prev_name $m
}

# --- ROM PG strap (v4.1): the ROM's PG pins are 64 full-width M4 strips in
# its LOCAL frame; under R90 they become VERTICAL strips -- PARALLEL to the
# M7 lanes, so lanes never CROSS them and the over-block float check removed
# the lane segments (v4.0: all 60 rom0 PG terminals unconnected). Strap with
# horizontal M8 mini-stripes over the ROM body, -stacked_via_bottom M4 ->
# real perpendicular crossings with every strip. Their y (425/475/525-ish,
# offset by 25 from the 50-pitch main M8 grid whose pairs sit at ~400/450/
# 500/550) keeps them clear of the main pass = no PG4-style interleaved
# same-net via arrays at shared crossings. ---
set rp [dbGet -p top.insts.name rom0]
set RX0 [expr {[dbGet $rp.box_llx] - 2}]
set RX1 [expr {[dbGet $rp.box_urx] + 2}]
set RY0 [dbGet $rp.box_lly]
set RY1 [dbGet $rp.box_ury]
# remove_floating FALSE is load-bearing: the float check counts same-layer
# touches, not via connections -- with it on, these minis vanish like the
# v4.0 over-ROM lane segments did. extend NONE is equally load-bearing: with
# the sticky 'ring', the v4.2 VDD mini extended rightward to the ring THROUGH
# the DCOs' scattered M8 OBS (18 shorts). The minis are tied by the 6+ col-0
# lanes crossing them (VIA7 arrays), no ring tie needed.
setAddStripeMode \
    -remove_floating_stripe_over_block false \
	-stacked_via_top_layer M8 \
	-stacked_via_bottom_layer M4 \
	-extend_to_closest_target none
foreach my [list [expr {$RY0 + 21}] [expr {$RY0 + 71}] [expr {$RY0 + 121}]] {
	addStripe \
		-layer M8 \
		-nets {VDD VSS} \
		-direction horizontal \
		-start_from bottom \
		-area [list $RX0 $my $RX1 [expr {$my + 15}]] \
		-set_to_set_distance 1000 \
		-spacing $POWER_STRIPE_PATH_SPACING \
		-width $POWER_STRIPE_PATH_WIDTH \
		-start_offset 0 \
		-stop_offset 0
}
plog "### UNL STATUS ### : ROM M8 mini-straps drawn over x [format %.1f $RX0]..[format %.1f $RX1]"

# --- band M8 pairs (v5/A7): one VDD/VSS pair across EACH 18um escape band (no
# tiles at these y), bottom M7 -> VIA7 onto every crossing lane; extends to the
# M7 ring legs. v4's single B2 pair -> one per band (bandA, bandB). ---
setAddStripeMode \
    -remove_floating_stripe_over_block true \
    -trim_antenna_back_to_shape core_ring \
	-stacked_via_top_layer M8 \
	-stacked_via_bottom_layer M7 \
    -extend_to_closest_target ring
foreach {by0 by1} [list $BANDA_Y0 $BANDA_Y1 $BANDB_Y0 $BANDB_Y1] {
	addStripe \
		-layer M8 \
		-nets {VDD VSS} \
		-direction horizontal \
		-start_from bottom \
		-area [list 0 $by0 $DESIGN_WIDTH $by1] \
		-set_to_set_distance 1000 \
		-spacing $POWER_STRIPE_PATH_SPACING \
		-width $POWER_STRIPE_PATH_WIDTH \
		-block_ring_bottom_layer_limit M1 \
		-start_offset 8 \
		-stop_offset 0
}
plog "### UNL STATUS ### : band M8 pairs drawn (bandA + bandB)"

editTrim -all
setCheckMode -globalNet true -io true -route true -tapeOut true

printStatus "Routing power rails"
setSrouteMode -corePinMaxViaScale "100 10"
# Straight pass, capped to RAM+B1: bank/ROM/analog block pins + B1 follow-pins.
sroute \
	-nets { VSS VDD } \
	-allowLayerChange 0 \
	-allowJogging 0 \
	-connect {blockPin corePin} \
	-blockPin useLef \
	-area [list 0 0 $DESIGN_WIDTH $Y_R0] \
    -corePinWidth 0.3
# band follow-pins (corePin only -- the tiles' PG is owned by the lanes). One
# corePin pass per escape band (v4's single B2 pass -> bandA + bandB).
foreach {by0 by1} [list $BANDA_Y0 $BANDA_Y1 $BANDB_Y0 $BANDB_Y1] {
	sroute \
		-nets { VSS VDD } \
		-allowLayerChange 0 \
		-allowJogging 0 \
		-connect {corePin} \
		-area [list 0 [expr {$by0 - 2}] $DESIGN_WIDTH [expr {$by1 + 2}]] \
	    -corePinWidth 0.3
}
# Jogging block-pin backstop over the ROM + analog band (MCU_MP M17b pattern:
# a macro nudge must never silently strand an M3/M4 PG strip). v4.1: x starts
# at 30 to include rom0, range up to M8 to reach the lanes/minis.
# v5/A7: the analog macros are now BALANCED across the full width (irq_gf1 ends
# ~x2274), so the backstop x bound extends 1200 -> 2280 to still cover the
# right-half macros -- exactly the "macro nudge must not strand a PG strip"
# case this backstop exists for.
printStatus "Routing ROM + analog-macro PG pins (jogging backstop)"
sroute \
	-nets { VSS VDD } \
	-connect { blockPin } \
	-blockPin useLef \
	-allowLayerChange 1 \
	-allowJogging 1 \
	-layerChangeRange { M3(3) M8(8) } \
	-area [list 30 $B1_Y0 2280 $Y_R0]

# --- EARLY PG SANITY GATE: verify the special grid BEFORE spending an hour on
# place/route. v3 sailed to signoff with 3057 PG opens; never again. ---
verifyConnectivity \
	-type special \
	-error 5000 \
	-report $REPORT_DIR/$BASENAME.verifyConnectivity.pgonly.rpt
set PG_INFOS 0
catch { set PG_INFOS [exec sh -c "grep -cE 'opens at|unconnected terminal' $REPORT_DIR/$BASENAME.verifyConnectivity.pgonly.rpt"] }
plog "### UNL STATUS ### : PG-only connectivity infos = $PG_INFOS"
if {$PG_INFOS > 200} {
	plog "### UNL FATAL ### : power grid broken ($PG_INFOS infos) -- fix the lanes before routing"
	exit 1
}

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
# a resynth rename can't abort the run). WITHOUT the disable, hold-fixing burns
# ~11 ns of DLY cells chasing the unmeetable -8.3 ns hold and the over-inserted
# delay line then overshoots one mclk period into a setup miss (M14 precedent).
# NETLIST-DEPENDENT names: after any MCU_ARGUS_hier re-synth, re-derive with
#   grep -nE '\.AN \(control_reg\[16\]\), \.B \(clock_source\)' \
#        innovus/common/in/MCU_ARGUS_hier.pnr.v
# and update the list (the NAND2B in module TIMER -> timer0, TIMER_1 -> timer1).
# M19 re-emit (Stage 4) renamed g11710 -> g3282 (timer0) / g3281 (timer1).
set_interactive_constraint_modes [all_constraint_modes -active]
foreach g {timer0/g3282 timer1/g3281} {
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

# --- irtr0 -> B1 (v4.5). B2 CANNOT host it: placement fits (v4.2+ legalized
# clean at 37um) but ROUTING does not -- v4.4's post-route shorts were 8325/
# 8325 INSIDE B2, signal-signal, irtr0-internal x irq_en/gf_out: a 21k um2
# module smeared into a 2690x29 um ribbon exceeds the band's M2/M4/M6
# vertical track supply outright (ecoRoute fixed 0 of them). B2 stays a
# pin-escape + tie/buffer band only; irtr0 is region'd into B1 and its
# 12x85 tile_irq_en fan-out rides the channels (+~1020 vertical crossings;
# corridors measured ~0.1% V overflow before this, so the post-place eGR is
# the verdict of record). Region (hard, NON-exclusive) not fence: the rest
# of the fabric shares B1.  ---
set B1_BOX [list 2 $B1_Y0 [expr {$DESIGN_WIDTH - 2}] $B1_Y1]
if {[catch {createRegion irtr0 {*}$B1_BOX} r]} {
	plog "### UNL WARN ### : createRegion failed ($r), falling back to createGuide"
	createGuide irtr0 {*}$B1_BOX
}
plog "### UNL STATUS ### : irtr0 constrained to B1 $B1_BOX"

place_opt_design
printStatus "Placement done"
# place_opt's trial route prints [NR-eGR] overflow. NOTE (v3 post-mortem):
# that number is a DIE-WIDE AVERAGE -- check the congestion MAP around the
# channels/B2, not just the headline percentage.

################################################################################
# Clock tree synthesis -- balances into the 18 tile clk pins (identical hardened
# tiles => identical internal insertion delay)
################################################################################
add_ndr -name CTS_2W2S -width {M2:M6 0.4} -generate_via -spacing {M2:M6 0.42}
add_ndr -name CTS_2W1S -width {M2:M6 0.4} -generate_via -spacing {M2:M6 0.21}

# v4.4: NO clock shielding. Both post-route explosions (v4.2 "timing driven
# prevention iteration" -> 267k, v4.3 optDesign -postRoute -hold -> 252k)
# printed NRDR-307 "turning off incremental shielding eco because too many
# nets will be routed": any mass eco rips the ~500k VSS shield segments of
# 477 clock nets and re-lays them non-incrementally into the packed channel/
# band routing = MetSpc/Short storm. The Castalia 4x assembly tolerated
# shields only because it had no packed channels. At 24 MHz with +14.7 ns
# setup margin, shields buy nothing; the NDR width/spacing rules stay.
create_route_type -name top_rule   -non_default_rule CTS_2W2S -top_preferred_layer M6 -bottom_preferred_layer M5
create_route_type -name trunk_rule -non_default_rule CTS_2W2S -top_preferred_layer M4 -bottom_preferred_layer M3
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
# leakage-only MCU_postCTS.power optDesign writes implicitly; BASENAME-prefixed
# so the Castalia assembly flow (also design MCU) cannot clobber it.
# Consumed by tools/python/gen_power_dashboard.py.
catch {report_power -outfile $REPORT_DIR/${BASENAME}_postCTS_full.power}
timeDesign -postCTS -expandedViews -outDir $REPORT_DIR/$BASENAME.timeDesign.postcts
report_ccopt_clock_trees -file $REPORT_DIR/$BASENAME.report_ccopt_clock_trees.postcts
report_ccopt_skew_groups -file $REPORT_DIR/$BASENAME.report_ccopt_skew_groups.postcts
printStatus "CTS done"

################################################################################
# Signal routing
################################################################################
printStatus "Running nanoroute"
# v4.3: timing/SI-driven routing OFF. The main DR converges to ~1 violation,
# then routeDesign's "timing driven prevention iteration" (SI spreading of the
# massively parallel channel buses) rips it to 267k -- the v3 explosion had
# the same signature. Post-CTS timing: setup WNS +14.7 ns / hold -0.104: there
# is nothing for timing-driven routing to earn; hold is fixed by the hold-only
# optDesign below.
setNanoRouteMode \
    -routeWithTimingDriven false \
    -routeWithSiDriven false \
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
    -drouteEndIteration 40
routeDesign

# v4.3: hold-only post-route opt. Setup has +14.7 ns -- the -setup pass only
# invites the timing-driven reroute storm; hold (-0.104 / 575 paths post-CTS)
# is fixed with delay cells + bounded incremental eco.
setDelayCalMode -SIAware true
setOptMode -holdTargetSlack 0.01
optDesign -postRoute -hold
setOptMode -holdTargetSlack 0
# Full post-route power (see postCTS note)
catch {report_power -outfile $REPORT_DIR/${BASENAME}_postRoute_full.power}

# --- DRC convergence loop: verify -> ecoRoute -fix_drc until clean (max 3).
# v3's single blind ecoRoute pass masked a 300k-violation rout behind the
# capped signoff report; here every iteration logs its own count.
# v4.5 lesson: delete the M7/M8 route blks BEFORE verifying -- verifyGeometry
# counts every tile PG pin overlapping a routing blockage as a SHORT (919
# phantoms + 1576 Overlaps in the v4.5 loop), which poisons the loop's count
# and burns eco passes on unfixable artifacts. ecoRoute after the deletion
# must NOT touch M7/M8: pin the route ceiling to M6 instead. ---
setNanoRouteMode -routeTopRoutingLayer 6
deleteAllRouteBlks
set PREV_NSHORT -1
for {set eco 1} {$eco <= 12} {incr eco} {
	verifyGeometry \
	    -error 10000 \
	    -warning 10000 \
	    -report $REPORT_DIR/$BASENAME.verifyGeometry.postroute.rpt
	set NSHORT -1
	catch { set NSHORT [exec sh -c "grep -m1 -E '^  Short' $REPORT_DIR/$BASENAME.verifyGeometry.postroute.rpt | grep -oE '\[0-9\]+'"] }
	plog "### UNL STATUS ### : postroute DRC pass $eco: shorts=$NSHORT"
	if {$NSHORT == 0} { break }
	# connectivity tripwire (v4.15 lesson: an escalation can trade shorts for
	# OPENS and the shorts-only loop sails to signoff with broken nets)
	verifyConnectivity -type regular -error 2000 -noAntenna \
	    -report $REPORT_DIR/$BASENAME.verifyConnectivity.loop.rpt
	set NOPEN 0
	catch { set NOPEN [exec sh -c "grep -cE 'IMPVFC-(92|96|98)' $REPORT_DIR/$BASENAME.verifyConnectivity.loop.rpt"] }
	if {$NOPEN > 2} {
		plog "### UNL FATAL ### : $NOPEN regular-net connectivity problems mid-loop -- escalation broke nets"
		saveDesign $DATABASE_DIR/$BASENAME.diag.innovus -def
		exit 1
	}
	# Bail out on structural failure: v4.4 proved ecoRoute fixes exactly 0 of
	# a capacity-class short storm (8325 -> 8325 -> 8325). Save a diagnostic
	# db and stop instead of burning an hour of futile ecos + garbage signoff.
	if {$NSHORT > 5000} {
		plog "### UNL FATAL ### : $NSHORT postroute shorts = structural, not eco-fixable; saving diag db"
		saveDesign $DATABASE_DIR/$BASENAME.diag.innovus -def
		exit 1
	}
	# Stall escalation (v4.6: 4 deterministic shorts survived every plain
	# -fix_drc pass at identical coords): force a from-scratch REROUTE of the
	# shorted nets via selectNet + -routeSelectedNetOnly (the canonical eco
	# recipe; v4.7's editDeleteViolatedNetWire is not a 20.12 command and
	# v4.8's editDeleteRoute -net silently no-ops).
	if {$NSHORT == $PREV_NSHORT} {
		set fh [open $REPORT_DIR/$BASENAME.verifyGeometry.postroute.rpt r]
		set rpt [read $fh]
		close $fh
		set badnets {}
		foreach {full net} [regexp -all -inline {of Net ([A-Za-z0-9_\[\]/]+)} $rpt] {
			if {$net ne "VDD" && $net ne "VSS" && [lsearch -exact $badnets $net] < 0} {
				lappend badnets $net
			}
		}
		# v4.18 neighborhood harvest: editSelect -area around each SHORT marker
		# to COLLECT net names (v4.13-15's mistake was editDelete -- orphaned
		# pieces; v4.15 signed off with 185 broken nets). The harvested nets
		# join the selected-net REROUTE below, which rips and reroutes each
		# net COMPLETELY -- the connectivity-safe joint re-solve.
		foreach {full lay bx1 by1 bx2 by2} [regexp -all -inline \
				{SHORT:[^\n]*\( (M\d) \)\s*\nBounds : \( ([\d.]+), ([\d.]+) \) \( ([\d.]+), ([\d.]+) \)} $rpt] {
			catch {editDeselect}
			if {![catch {editSelect -area [list [expr {$bx1 - 8}] [expr {$by1 - 8}] [expr {$bx2 + 8}] [expr {$by2 + 8}]]}]} {
				catch {
					foreach w [dbGet -p selected] {
						set nn ""
						catch { set nn [dbGet $w.net.name] }
						if {$nn ne "" && $nn ne "VDD" && $nn ne "VSS" && [lsearch -exact $badnets $nn] < 0} {
							lappend badnets $nn
						}
					}
				}
			}
			catch {editDeselect}
		}
		plog "### UNL STATUS ### : stall escalation, rerouting [llength $badnets] shorted nets"
		deselectAll
		foreach n $badnets {
			if {[catch {selectNet $n} r]} {
				plog "### UNL WARN ### : selectNet failed for $n: $r"
			}
		}
		setNanoRouteMode -routeSelectedNetOnly true
		if {[catch {routeDesign} r]} {
			plog "### UNL WARN ### : selected-net reroute failed: $r"
		}
		setNanoRouteMode -routeSelectedNetOnly false
		deselectAll
	}
	set PREV_NSHORT $NSHORT
	if {[catch {ecoRoute -fix_drc} r]} { plog "### UNL WARN ### : ecoRoute -fix_drc failed: $r" }
}

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
    -error 100000 \
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
# out/hart_tile_argus.{xsim.v,sdf} at gate-sim time)
################################################################################
streamOut \
    $OUTPUT_DIR/$BASENAME.gds2 \
    -libName WorkLib \
    -structureName $DESIGN_NAME \
    -stripes 1 \
    -units 1000 \
    -mode ALL \
    -merge [list $OUTPUT_DIR/hart_tile_argus.gds2] \
    -mapFile $INPUT_DIR/innovus2gds.map

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
