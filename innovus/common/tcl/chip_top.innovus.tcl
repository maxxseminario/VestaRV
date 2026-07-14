################################################################################
# Innovus script -- chip_top: the CONNECTED 3x3mm Castalia C0 chip (M15
# "Flavor B"). FLAT chip run = the M16 4-tile MCU_MP assembly + the M15 tphn
# pad ring in ONE design (chip_top instantiates the pads and the MCU; the MCU
# hierarchy is placed/routed directly, tiles stay hardened LEF macros).
#
# WHY FLAT, NOT ASSEMBLY-AS-MACRO: the pad machinery (padlists, place procs,
# fillers, seal keep-outs, supply hookup) is shared basename-parameterized
# data/procs and the flow is already proven (Argus A5). The MCU's ~33 real
# pad-to-core nets are ordinary nets. See the chip-top-flow skill +
# .devlog/2026-07-14-castalia-c0-chip-top.md.
#
# FRAME (RECTANGULAR-in-SQUARE, the C0 delta from Argus): the fixed 3x3mm ring
# has a 2690x2690 interior (3000 - 2*(20 seal + 135 pad)). The MCU_MP assembly
# is 2689 (W) x 1700 (H) -- razor-fit in width (~0.5 um/side), CENTERED
# vertically in the square interior (~495 um reserved-for-analog slack ABOVE
# and BELOW the assembly). The assembly's native (0,0)-(2689,1700) coordinates
# are UNTOUCHED (every MCU_MP geometry line below is byte-identical to
# MCU_MP.innovus.tcl); the die box is chosen so native (0,0) lands centered:
# die (-155.5,-650)-(2844.5,2350). Pad rows are re-derived PER EDGE from the
# die frame (Argus's single PAD_NEAR/PAD_FAR only worked because its assembly
# was square-and-interior-sized). The ~990 um vertical slack (2 bands) is
# where the future 4xAFE global shared analog (bias gen, EIS engine) lands --
# a C5 re-cut, not a redesign (see the devlog "regions reserved for analog").
#
# resetn/prt1-4 quartets are WIRED to the pads (chip_top.v); a0/a0_1..a0_3 are
# OPEN on the mcu0 instance (Myshkin vesta_chip tape-out precedent) and the
# chip SDC dont_touches their nets so the driver clamps survive for the gate
# tb (trim-proof fallback: the tiles' own a0 ports, probed as mcu0/hart<h>/a0).
#
# NAME-COLLISION: mcu0's cell is named MCU == the Myshkin tape-out cell. That
# is handled ONLY at signoff strmin (signoff_mp/strmin_gds.sh cellMap/topcell
# pin/hard-gate) -- NEVER stream this chip with a raw strmin.
#
# The four hart instances (mcu0/hart0-3) are the HARDENED M19c 233-pin
# hart_tile block; timing from the per-corner ETMs out/hart_tile.etm_{ss,ff}.
################################################################################

source tcl/constants.tcl
source $SCRIPT_DIR/procedures.tcl

set DESIGN_NAME chip_top
set BASENAME    chip_top

# Interior frame (the MCU_MP assembly coordinates, UNTOUCHED)
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

# ---- Chip frame: fixed 3x3mm ring, 2690x2690 interior; assembly CENTERED ----
set PAD_RING  135.0   ;# tphn pad depth
set SEAL_OFF   20.0   ;# die edge -> pad outer edge (seal-ring band, M15)
set PADW       25.0   ;# signal/supply pad width along the row
set RING_BAND [expr {$PAD_RING + $SEAL_OFF}]              ;# 155
set INT_SPAN  2690.0                                      ;# ring interior (3000 - 2*155)
# center the assembly (native origin 0,0) in the square interior:
set MARGIN_X  [expr {($INT_SPAN - $DESIGN_WIDTH)  / 2.0}] ;# 0.5
set MARGIN_Y  [expr {($INT_SPAN - $DESIGN_HEIGHT) / 2.0}] ;# 495.0
# interior box (native-referenced -> assembly sits centered):
set IN_LLX [expr {-$MARGIN_X}]                            ;# -0.5
set IN_LLY [expr {-$MARGIN_Y}]                            ;# -495.0
set IN_URX [expr {$DESIGN_WIDTH  + $MARGIN_X}]            ;# 2689.5
set IN_URY [expr {$DESIGN_HEIGHT + $MARGIN_Y}]            ;# 2195.0
# die box = interior grown by the ring band on every side -> exactly 3000x3000:
set DIE_LLX [expr {$IN_LLX - $RING_BAND}]                 ;# -155.5
set DIE_LLY [expr {$IN_LLY - $RING_BAND}]                 ;# -650.0
set DIE_URX [expr {$IN_URX + $RING_BAND}]                 ;# 2844.5
set DIE_URY [expr {$IN_URY + $RING_BAND}]                 ;# 2350.0
# pad-row placement lines (bbox LL point per edge), re-derived PER EDGE:
set PAD_NEAR_X [expr {$IN_LLX - $PAD_RING}]               ;# left  row LL-x = -135.5
set PAD_FAR_X  $IN_URX                                    ;# right row LL-x = 2689.5
set PAD_NEAR_Y [expr {$IN_LLY - $PAD_RING}]               ;# bottom row LL-y = -630.0
set PAD_FAR_Y  $IN_URY                                    ;# top   row LL-y = 2195.0

tic

################################################################################
# Design import: chip wrapper (pads + mcu0) FIRST, then the MCU_MP hier netlist
# it instantiates.
################################################################################
set init_verilog             "$INPUT_DIR/chip_top.v $INPUT_DIR/MCU_MP_hier.pnr.v"
set init_top_cell            "$DESIGN_NAME"
set init_pwr_net             "VDD"
set init_gnd_net             "VSS"
set init_mmmc_file           "$SCRIPT_DIR/viewdefinition_chip.tcl"

# tphn pad LEF (M15): 8lm variant matches the M1-M8 tech LEF (9lm adds M9/
# VIA8 -> unknown-layer spam on streamOut); tpfn is the WRONG family. The 8lm
# supply macros PVDD1DGZ_G/PVSS1DGZ_G already carry USE POWER/GROUND (verified
# 2026-07-12 -- no USEfix needed; the M15 "signal PINs" note was wrong here).
set IO_PAD_LEF "/opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/lef/tphn65gpgv2od3_sl_210a/mt_2/8lm/lef/tphn65gpgv2od3_sl_8lm.lef"

set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					$IP_DIR/rom_hvt_pg/rom_hvt_pg.lef \
					$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef \
					$IC_DIR/abstracts/myshkin_abs/GlitchFilter/GlitchFilter.lef \
					$IC_DIR/abstracts/myshkin_abs/PowerOnResetCheng/PowerOnResetCheng.lef \
					$IC_DIR/abstracts/myshkin_abs/OscillatorCurrentStarved/OscillatorCurrentStarved.lef \
					$OUTPUT_DIR/hart_tile.lef \
					$IO_PAD_LEF"

set init_design_uniquify 1
init_design

# Tile timing enters via the ETM .lib (viewdefinition_chip library sets:
# out/hart_tile.etm_{ss,ff}.lib) -- the tile is a timed macro exactly like
# the SRAMs/ROM. The pad cells enter LEF-only (timing-less, like the analog
# abstracts -- same IMPVL-366 rule: no dummy libs).

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
# Floorplan: die (-155.5,-650)-(2844.5,2350) = 3000x3000, core box = the
# MCU_MP core box UNCHANGED at (1,1)-(2688,1699) -> identical core rows,
# identical native interior coordinates. Assembly ends up CENTERED in the
# 2690x2690 ring interior.
################################################################################
floorPlan \
    -site TSMC65ADV10TSITE \
    -b $DIE_LLX $DIE_LLY $DIE_URX $DIE_URY \
       $DIE_LLX $DIE_LLY $DIE_URX $DIE_URY \
       $CORE_SPACING $CORE_SPACING [expr {$DESIGN_WIDTH - $CORE_SPACING}] [expr {$DESIGN_HEIGHT - $CORE_SPACING}]

################################################################################
# Pad ring (M15 Flavor A geometry re-derived in the rectangular-in-square frame)
#
# placeInstance x y orient lands the ORIENTED bbox LOWER-LEFT at (x,y). CCW
# ring: bottom R0 / right R90 / top R180 / left R270; corners BL R0 / BR R90 /
# TR R180 / TL R270. Pads inset SEAL_OFF from the die edge; pad INNER edges
# land exactly on the interior boundary. Unlike Argus (square assembly == square
# interior, one PAD_NEAR/PAD_FAR), Castalia is rectangular so each edge has its
# own near/far and the along-row centering references the interior LL per axis.
################################################################################

# Place one pad in slot i of n on a side (block centered along the interior span)
proc place_pad {inst side i n} {
    global PAD_NEAR_X PAD_FAR_X PAD_NEAR_Y PAD_FAR_Y IN_LLX IN_LLY INT_SPAN PADW
    set block [expr {$n * $PADW}]
    set off   [expr {($INT_SPAN - $block) / 2.0}]   ;# centering offset within the span
    switch -- $side {
        bottom { placeInstance $inst [expr {$IN_LLX + $off + $i*$PADW}] $PAD_NEAR_Y R0   -fixed }
        top    { placeInstance $inst [expr {$IN_LLX + $off + $i*$PADW}] $PAD_FAR_Y  R180 -fixed }
        left   { placeInstance $inst $PAD_NEAR_X [expr {$IN_LLY + $off + $i*$PADW}] R270 -fixed }
        right  { placeInstance $inst $PAD_FAR_X  [expr {$IN_LLY + $off + $i*$PADW}] R90  -fixed }
        default { error "bad side $side" }
    }
}
proc place_side {side padlist} {
    set n [llength $padlist]
    set i 0
    foreach inst $padlist {
        place_pad $inst $side $i $n
        incr i
    }
    puts "### UNL STATUS ### : placed $n pads on $side edge"
}

placeInstance PAD_CORNER_BL $PAD_NEAR_X $PAD_NEAR_Y R0   -fixed
placeInstance PAD_CORNER_BR $PAD_FAR_X  $PAD_NEAR_Y R90  -fixed
placeInstance PAD_CORNER_TR $PAD_FAR_X  $PAD_FAR_Y  R180 -fixed
placeInstance PAD_CORNER_TL $PAD_NEAR_X $PAD_FAR_Y  R270 -fixed

# Ordered side lists (shared data file; same lists as the Flavor A prototype)
source $SCRIPT_DIR/chip_top_padlists.tcl
place_side bottom $BOTTOM
place_side top    $TOP
place_side left   $LEFT
place_side right  $RIGHT

# IO fillers complete the ring bus between pads (M15 fallback ladder kept)
if {[catch {
    addIoFiller -cell {PFILLER20_G PFILLER10_G PFILLER5_G PFILLER1_G PFILLER05_G PFILLER0005_G} -prefix IOFILL
} r]} {
    puts "### UNL WARN ### : addIoFiller failed ($r) -- retrying after addIoRow"
    if {[catch {addIoRow} r2]} { puts "### UNL WARN ### : addIoRow also failed: $r2" }
    catch {addIoFiller -cell {PFILLER20_G PFILLER10_G PFILLER5_G PFILLER1_G PFILLER05_G PFILLER0005_G} -prefix IOFILL}
}
puts "### UNL STATUS ### : pad ring + IO fillers placed"

# Seal-ring band: outer SEAL_OFF-wide frame reserved (place + route keep-out;
# the real SEALRING_3mm OA cell is GDS-merged at chip assembly -- M15).
proc seal_keepouts {} {
    global DIE_LLX DIE_LLY DIE_URX DIE_URY SEAL_OFF
    set frames [list \
        [list $DIE_LLX $DIE_LLY $DIE_URX [expr {$DIE_LLY + $SEAL_OFF}]] \
        [list $DIE_LLX [expr {$DIE_URY - $SEAL_OFF}] $DIE_URX $DIE_URY] \
        [list $DIE_LLX $DIE_LLY [expr {$DIE_LLX + $SEAL_OFF}] $DIE_URY] \
        [list [expr {$DIE_URX - $SEAL_OFF}] $DIE_LLY $DIE_URX $DIE_URY]]
    set i 0
    foreach f $frames {
        lassign $f x0 y0 x1 y1
        catch {createPlaceBlockage -box $x0 $y0 $x1 $y1 -name SEALRING_$i}
        catch {createRouteBlk -box $x0 $y0 $x1 $y1 -layer {1 2 3 4 5 6 7 8} -name SEALRINGRB_$i}
        incr i
    }
}
seal_keepouts
puts "### UNL STATUS ### : seal-ring band reserved"

# --- Tile geometry (must match tcl/hart_tile.innovus.tcl) ---
set TILE_W        660
set TILE_H        1050
set TILE_NOTCH_X0 80
set TILE_NOTCH_X1 580
set TILE_NOTCH_Y0 600

# --- The tile row: 4x U-shaped hart_tile flush with the assembly top, mirror-
# symmetric about x = DESIGN_W/2 (hart0/1 R0, hart2/3 MY). M17: 3 um inter-tile
# gaps. 20 um die margins clear the left/right M7 power ring. ---
set TILE_GAP     3
set TILE_X0      20
set TILE_PITCH   [expr {$TILE_W + $TILE_GAP}]
set TILE_Y       [expr {$DESIGN_HEIGHT - $CORE_SPACING - $TILE_H}]
for {set h 0} {$h < 4} {incr h} {
	set TILE_X [expr {$TILE_X0 + $h * $TILE_PITCH}]
	set ORIENT [expr {$h < 2 ? "R0" : "MY"}]
	placeInstance mcu0/hart$h $TILE_X $TILE_Y $ORIENT
	addHaloToBlock 10 10 10 10 mcu0/hart$h
}
printStatus "Placed tile row (tops flush with assembly top)"

# --- Analog notch windows: per tile, keep-out from the notch floor to the
# assembly top edge. Hard placement blockage + all-layer route blockage. ---
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
printStatus "Reserved 4 analog notch windows (500 x 451 to the assembly top)"

# --- Above the notch-floor line the assembly holds only the 4 notch windows,
# the tile fingers and the 3 um inter-tile gaps -- none placeable. ---
set NOTCH_FLOOR_Y [expr {$TILE_Y + $TILE_NOTCH_Y0}]
createPlaceBlockage -type hard -name top_band \
	-box [list 0 $NOTCH_FLOOR_Y $DESIGN_WIDTH $DESIGN_HEIGHT]
cutRow -area [list 0 $NOTCH_FLOOR_Y $DESIGN_WIDTH $DESIGN_HEIGHT]

# --- Shared RAM: shbank0-3 + npuram0, five square sram1p16k in a centered
# row at the very bottom of the assembly ---
set SRAM16K_WIDTH		319.650
set SRAM16K_HEIGHT		383.085
set SH_GAP   20
set SH_Y     40
set SH_SPAN  [expr {5 * $SRAM16K_WIDTH + 4 * $SH_GAP}]
set SH_X0    [expr {($DESIGN_WIDTH - $SH_SPAN) / 2.0}]
set i 0
foreach m {mcu0/shbank0 mcu0/shbank1 mcu0/shbank2 mcu0/shbank3 mcu0/npuram0} {
	placeInstance $m [expr {$SH_X0 + $i * ($SRAM16K_WIDTH + $SH_GAP)}] $SH_Y R0
	addHaloToBlock 4 4 4 4 $m
	incr i
}
cutRow
# shared RAM row top = 40 + 383.085 = ~423
for {set g 0} {$g < 4} {incr g} {
	set gx0 [expr {$SH_X0 + ($g + 1) * $SRAM16K_WIDTH + $g * $SH_GAP}]
	createPlaceBlockage -type hard -name ramgap$g \
		-box [list $gx0 [expr {$SH_Y - 4}] [expr {$gx0 + $SH_GAP}] [expr {$SH_Y + $SRAM16K_HEIGHT + 4}]]
	cutRow -area [list $gx0 [expr {$SH_Y - 4}] [expr {$gx0 + $SH_GAP}] [expr {$SH_Y + $SRAM16K_HEIGHT + 4}]]
}

# --- Control-plane band: boot ROM (R90) + POR, 2x DCO, 3x IRQ glitch filter ---
set ROM_X 60
set ROM_Y 470
placeInstance mcu0/rom0 $ROM_X $ROM_Y R90
addHaloToBlock 9 4 4 9 mcu0/rom0
placeInstance mcu0/por     450 470 R0
addHaloToBlock 4 4 4 4 mcu0/por
placeInstance mcu0/dco0    550 470 R0
addHaloToBlock 4 4 4 4 mcu0/dco0
placeInstance mcu0/dco1    670 470 R0
addHaloToBlock 4 4 4 4 mcu0/dco1
placeInstance mcu0/irq_gf0 790 470 R0
addHaloToBlock 4 4 4 4 mcu0/irq_gf0
placeInstance mcu0/irq_gf1 880 470 R0
addHaloToBlock 4 4 4 4 mcu0/irq_gf1
placeInstance mcu0/irq_gf2 991 470 R0
addHaloToBlock 4 4 4 4 mcu0/irq_gf2
cutRow

printStatus "Placed tiles + shared RAM row + ROM + analog blocks"

# --- Chip pins: NONE placed. chip_top's ports (resetn/prt*/aio) ride their
# pad instances' PAD terminals; physically each port's net has exactly one pin
# (the pad's PAD pin) = single-pin nets, skipped by the tracer. The MCU_MP
# editPin-to-bottom-edge block is gone WITH the MCU port pins themselves --
# the ~708 ex-top-level terms are internal mcu0 nets now (a0* dangle by
# design, Myshkin precedent). ---
puts "### UNL STATUS ### : no top-level pin shapes (ports ride pad PAD terminals)"

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

# M17b: -skip_side {top} skips the DIE-top segments; the ring engine still
# CLOSES the loop by detouring under each analog window at native y ~1227/1241.
# Delete every VDD/VSS special shape lying ENTIRELY above y=1213 (native): the
# 8 detour segments + their via stacks + the window-side legs. Main side legs
# (boxes start at y 4/18) are spared. NB sViaInst objects have NO box_lly --
# vias filter on pt_y, wires on box_lly (a box_lly filter on vias SILENTLY
# matches nothing).  These are native-y filters -- unchanged by the die frame.
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

# Stripe grid stops at the notch-floor line (native). See MCU_MP.innovus.tcl
# for the M17b war stories (X stays 0..W; Y ceiling = NOTCH_FLOOR_Y - 39).
set STRIPE_TOP_Y [expr {$NOTCH_FLOOR_Y - 39}]
# PG4: the M8 pass gets -stacked_via_bottom_layer M7 (fixes the PG3 MCU-DRC
# headline classes -- VIA7.W.1/S.2, M8.S.3 -- in ONE knob; see MCU_MP.innovus.tcl).
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
# M7 pass: bottom back to M1 -- owns the macro-pin (M4) and follow-pin (M1)
# stacks, all landing on its own stripe centerlines.
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

editTrim -all
setCheckMode -globalNet true -io true -route true -tapeOut true

printStatus "Routing power rails"
setSrouteMode -corePinMaxViaScale "100 10"
# M17b: -area caps the strapping BELOW the tiles' notch-floor ring band (native
# y 1221..1249). See MCU_MP.innovus.tcl for the SameNet war story.
sroute \
	-nets { VSS VDD } \
	-allowLayerChange 0 \
	-allowJogging 0 \
	-connect {blockPin corePin} \
	-blockPin useLef \
	-area [list 0 0 $DESIGN_WIDTH 1220] \
    -corePinWidth 0.3

# M17b: jogging block-pin pass over the control-band analog macros only
# (por / dco0/1 / irq_gf0-2). Area = the analog band, nothing else.
printStatus "Routing analog-macro PG pins (jogging backstop pass)"
sroute \
	-nets { VSS VDD } \
	-connect { blockPin } \
	-blockPin useLef \
	-allowLayerChange 1 \
	-allowJogging 1 \
	-layerChangeRange { M3(3) M7(7) } \
	-area { 440 460 1035 515 }

# --- Pad-supply hookup (C0): the four core-domain supply pads carry real
# USE POWER/GROUND pins (PVDD1DGZ_G.VDD / PVSS1DGZ_G.VSS), already bound to
# VDD/VSS by the globalNetConnect -inst * above. Tie their core-side fingers to
# the core ring, which hugs the (centered) assembly ~495 um in from the top/
# bottom pad rows -- padPin sroute jogs across that slack.
#
# PLACEMENT NOTE (differs from Argus, which sroute'd padPin right after
# addRing): here it MUST come AFTER the ring-detour deletion above (else its
# top-pad wires -- box_lly well above 1213 -- get nuked by that y>=1213 filter)
# AND after the stripes exist (richer VDD/VSS tie targets for the distant top
# pads). It runs before the verifyGeometry preplace + fixVia so those clean up
# any padPin vias, and before the M7/M8 route blockage so M7/M8 stay available
# to reach the ring. ACCEPTANCE = the "sroute ... created N wires" log line
# (trust the COUNT, not the absence of an error -- PG2-F1 lesson) + the
# signoff verifyConnectivity -connectPadSpecialPorts gate (0 infos). ---
sroute \
	-nets { VSS VDD } \
	-connect { padPin } \
	-allowJogging 1 \
	-allowLayerChange 1 \
	-layerChangeRange { M1(1) M8(8) } \
	-area [list $DIE_LLX $DIE_LLY $DIE_URX $DIE_URY]
puts "### UNL STATUS ### : pad-supply sroute (padPin) done"

verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$BASENAME.verifyGeometry.preplace.rpt
fixVia -short
fixVia -minCut
fixVia -minStep

# Reserve M7/M8 for power during signal routing -- FULL DIE frame (keeps signal
# routing off M7/M8 over the pad band too).
createRouteBlk -box $DIE_LLX $DIE_LLY $DIE_URX $DIE_URY -layer 7
createRouteBlk -box $DIE_LLX $DIE_LLY $DIE_URX $DIE_URY -layer 8

################################################################################
# Placement
################################################################################
# Spurious clock-gating checks on the TIMER ClockMuxGlitchFree select legs
# (see MCU_MP.innovus.tcl). Gate names are netlist-dependent (genus-mapped);
# prefix mcu0/ here. If a resynth renames them, re-derive from the hold
# signoff report.
set_interactive_constraint_modes [all_constraint_modes -active]
foreach g {mcu0/timer0/g11710 mcu0/timer1/g11710} {
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
# Clock tree synthesis -- balances into the four tile clk pins
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
# SI-aware hold cleanup (M14-proven; 'optDesign -postRoute -si -hold' is
# OBSOLETE in 20.12 -- IMPOPT-7016 -- so use SIAware delaycal + plain hold opt).
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
# deleteAllRouteBlks just removed the seal-band keep-outs too -- restore them
# so loop ecos can't stray into the reserved outer 20um band (the SEALRING_*
# PLACE blockages survive; only the route blks are re-made).
seal_keepouts
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
# harden's out/hart_tile.{xsim.v,sdf} at gate-sim time). The 8lm tphn pad GDS
# is merged so the streamed chip carries the pad geometry.
################################################################################
streamOut \
    $OUTPUT_DIR/$BASENAME.gds2 \
    -libName WorkLib \
    -structureName $DESIGN_NAME \
    -stripes 1 \
    -units 1000 \
    -mode ALL \
    -merge [list $OUTPUT_DIR/hart_tile.gds2 \
                 /opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/gds/tphn65gpgv2od3_sl_210a/mt_2/8lm/tphn65gpgv2od3_sl.gds] \
    -mapFile $INPUT_DIR/innovus2gds.map

printStatus "Writing SDF (top level)"
write_sdf $OUTPUT_DIR/$BASENAME.sdf

printStatus "Writing verilog for Xcelium (top level; hart_tile as leaf refs)"
saveNetlist \
    $OUTPUT_DIR/$BASENAME.xsim.v \
    -excludeCellInst ANTENNA2A10TH

saveDesign $DATABASE_DIR/$BASENAME.final.innovus -def -netlist -rc -tcon
toc
printStatus "chip_top (Castalia C0) connected chip-top complete"
exit
