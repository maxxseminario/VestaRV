################################################################################
# Innovus script -- chip_top_quad: the CONNECTED 3x3mm Castalia-QUAD (CQ) chip.
# QUADRANT-SYMMETRIC respin of the C0 chip_top (tcl/chip_top.innovus.tcl): the
# 4-tile MCU_MP assembly is spread to the FOUR die corners (2-axis mirror
# symmetry), each tile's analog notch facing its nearest horizontal die edge,
# the shared digital fabric (5 SRAMs + ROM + POR/DCOs + arbiter/CLINT/mutex/
# irq_router std cells) in a horizontal CENTER BAND between the two tile rows.
# See ~/vesta_docs/castalia_quad/cq_architecture.md (SS2 = this floorplan spec).
#
# WP = CQ3a (floorplan + power geometry). This script runs floorplan + pad
# placement + power (ring/detour/stripe/followpin + block-pin jog) + DB-level PG
# verification + saveDesign, then EXITS before placement (the CQ3a gate is the
# floorplan+PG stage; CQ5 continues to place/route/signoff on the saved DB).
#
# FRAME (SQUARE-in-SQUARE, the CQ delta from C0's rectangular-in-square): the
# assembly is now the FULL 2690x2690 ring interior. DESIGN 2690x2690 (was C0
# 2689x1700). This differs from cq_architecture.md SS2's 2689x2689 BY DESIGN:
# an ODD design height cannot land BOTH mirrored tile rows on the 2.0um std-cell
# row grid (bottom origin and top origin differ by an odd number of um), which
# would put one row 1um off-grid and break followpin abutment. 2690 (even,
# margin 0, Argus-style symmetric +/-155 die) lands both rows on-grid and keeps
# perfect 2-axis symmetry about (1345,1345). See the CQ3a report / devlog.
#
# NAME-COLLISION: mcu0's cell is named MCU == the Myshkin tape-out cell. Handled
# ONLY at signoff strmin (signoff_mp/strmin_gds.sh, topcell != MCU branch) --
# NEVER stream this chip with a raw strmin.
#
# NETLIST/PADS: CQ3b's consistent 64-pad QFN64 pair -- in/chip_top_quad.v (24
# per-quadrant analog + split IO/core supplies + resetn + POC + 30 GPIO, a0*
# open, 2 dropped GPIO tied/dangled) + tcl/chip_top_quad_padlists.tcl -- both
# on disk and verified consistent (all 64 list pads exist in the netlist; only
# the 4 corners are flow-placed). + in/MCU_MP_hier.pnr.v (the MCU hierarchy).
# Fallback for a C0-prototype-only geometry run: PADLISTS =
# chip_top_quad_padlists_geom.tcl (C0 pad names; needs the C0-prototype netlist).
################################################################################

source ../shared/constants.tcl
source ../shared/procedures.tcl

set DESIGN_NAME chip_top_quad
set BASENAME    chip_top_quad

# Pad side lists: CQ3b's real QFN64 ring (matches the 64-pad in/chip_top_quad.v).
set PADLISTS chip_top_quad_padlists.tcl

# Full square interior (the quadrant assembly fills the whole ring interior)
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

# ---- Chip frame: fixed 3x3mm ring, 2690x2690 interior; assembly fills it ----
set PAD_RING  135.0   ;# tphn pad depth
set SEAL_OFF   20.0   ;# die edge -> pad outer edge (seal-ring band, M15)
set PADW       25.0   ;# signal/supply pad width along the row
set RING_BAND [expr {$PAD_RING + $SEAL_OFF}]              ;# 155
set INT_SPAN  2690.0                                      ;# ring interior (3000 - 2*155)
# margin 0: assembly == interior (square-in-square, Argus-style)
set MARGIN_X  [expr {($INT_SPAN - $DESIGN_WIDTH)  / 2.0}] ;# 0
set MARGIN_Y  [expr {($INT_SPAN - $DESIGN_HEIGHT) / 2.0}] ;# 0
set IN_LLX [expr {-$MARGIN_X}]                            ;# 0
set IN_LLY [expr {-$MARGIN_Y}]                            ;# 0
set IN_URX [expr {$DESIGN_WIDTH  + $MARGIN_X}]           ;# 2690
set IN_URY [expr {$DESIGN_HEIGHT + $MARGIN_Y}]           ;# 2690
# die box = interior grown by the ring band -> exactly 3000x3000, symmetric:
set DIE_LLX [expr {$IN_LLX - $RING_BAND}]                 ;# -155
set DIE_LLY [expr {$IN_LLY - $RING_BAND}]                 ;# -155
set DIE_URX [expr {$IN_URX + $RING_BAND}]                 ;# 2845
set DIE_URY [expr {$IN_URY + $RING_BAND}]                 ;# 2845
# pad-row placement lines (bbox LL point per edge); square -> per-axis symmetric:
set PAD_NEAR_X [expr {$IN_LLX - $PAD_RING}]               ;# -135
set PAD_FAR_X  $IN_URX                                    ;# 2690
set PAD_NEAR_Y [expr {$IN_LLY - $PAD_RING}]               ;# -135
set PAD_FAR_Y  $IN_URY                                    ;# 2690

tic

################################################################################
# Design import: chip wrapper (pads + mcu0) FIRST, then the MCU_MP hier netlist.
################################################################################
set init_verilog             "$INPUT_DIR/chip_top_quad.v ../MCU_MP/in/MCU_MP_hier.pnr.v"
set init_top_cell            "$DESIGN_NAME"
set init_pwr_net             "VDD"
set init_gnd_net             "VSS"
set init_mmmc_file           "$SCRIPT_DIR/viewdefinition_chip_quad.tcl"

set IO_PAD_LEF "/opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/lef/tphn65gpgv2od3_sl_210a/mt_2/8lm/lef/tphn65gpgv2od3_sl_8lm.lef"

set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					$IP_DIR/rom_hvt_pg/rom_hvt_pg.lef \
					$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef \
					$IC_DIR/abstracts/myshkin_abs/GlitchFilter/GlitchFilter.lef \
					$IC_DIR/abstracts/myshkin_abs/PowerOnResetCheng/PowerOnResetCheng.lef \
					$IC_DIR/abstracts/myshkin_abs/OscillatorCurrentStarved/OscillatorCurrentStarved.lef \
					../hart_tile/out/hart_tile.lef \
					$IO_PAD_LEF"

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
# Floorplan: die (-155,-155)-(2845,2845) = 3000x3000, core box (1,1)-(2689,2689).
################################################################################
floorPlan \
    -site TSMC65ADV10TSITE \
    -b $DIE_LLX $DIE_LLY $DIE_URX $DIE_URY \
       $DIE_LLX $DIE_LLY $DIE_URX $DIE_URY \
       $CORE_SPACING $CORE_SPACING [expr {$DESIGN_WIDTH - $CORE_SPACING}] [expr {$DESIGN_HEIGHT - $CORE_SPACING}]

################################################################################
# Pad ring (square frame; one PAD_NEAR/PAD_FAR per axis via the square symmetry)
################################################################################
proc place_pad {inst side i n} {
    global PAD_NEAR_X PAD_FAR_X PAD_NEAR_Y PAD_FAR_Y IN_LLX IN_LLY INT_SPAN PADW
    set block [expr {$n * $PADW}]
    set off   [expr {($INT_SPAN - $block) / 2.0}]
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

source $SCRIPT_DIR/$PADLISTS
place_side bottom $BOTTOM
place_side top    $TOP
place_side left   $LEFT
place_side right  $RIGHT

if {[catch {
    addIoFiller -cell {PFILLER20_G PFILLER10_G PFILLER5_G PFILLER1_G PFILLER05_G PFILLER0005_G} -prefix IOFILL
} r]} {
    puts "### UNL WARN ### : addIoFiller failed ($r) -- retrying after addIoRow"
    if {[catch {addIoRow} r2]} { puts "### UNL WARN ### : addIoRow also failed: $r2" }
    catch {addIoFiller -cell {PFILLER20_G PFILLER10_G PFILLER5_G PFILLER1_G PFILLER05_G PFILLER0005_G} -prefix IOFILL}
}
puts "### UNL STATUS ### : pad ring + IO fillers placed"

# Seal-ring band keep-out (place + route)
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

################################################################################
# Quadrant tile row: 4x U-shaped hart_tile, one per corner, 2-axis symmetric.
#   hart0 top-left  R0   @(20,1639)   notch faces TOP edge
#   hart1 top-right MY   @(2010,1639) notch faces TOP edge
#   hart2 bot-left  MX   @(20,1)      notch faces BOTTOM edge
#   hart3 bot-right R180 @(2010,1)    notch faces BOTTOM edge
# x_right = 2690-20-660 = 2010; y_top = 2690-1-1050 = 1639 (both odd -> ON the
# y=1,3,5 row grid; bottom origin 1 also odd -> both rows on-grid). 10um halos.
# The MX/R180 (Y-mirror) flips are the CQ delta vs C0's MY-only row; PG hookup
# to the flipped tiles' PG pins is verified from the DB below.
################################################################################
set TILE_W        660
set TILE_H        1050
set TILE_NOTCH_X0 80
set TILE_NOTCH_X1 580
set TILE_NOTCH_Y0 600   ;# tile-local notch-floor height (from the tile base)
set TILE_X0       20
set TILE_XR       [expr {$DESIGN_WIDTH - $TILE_X0 - $TILE_W}]   ;# 2010
set TILE_YT       [expr {$DESIGN_HEIGHT - $CORE_SPACING - $TILE_H}] ;# 1639
set TILE_YB       $CORE_SPACING                                 ;# 1

# {inst x y orient face}
set QTILES [list \
    [list mcu0/hart0 $TILE_X0 $TILE_YT R0   top] \
    [list mcu0/hart1 $TILE_XR $TILE_YT MY   top] \
    [list mcu0/hart2 $TILE_X0 $TILE_YB MX   bottom] \
    [list mcu0/hart3 $TILE_XR $TILE_YB R180 bottom]]

foreach t $QTILES {
    lassign $t inst tx ty orient face
    placeInstance $inst $tx $ty $orient
    addHaloToBlock 10 10 10 10 $inst
}
printStatus "Placed 4 quadrant tiles (2-axis symmetric; hart2/3 Y-mirrored)"

# --- Analog notch windows: per tile, keep-out from the notch floor to the
# nearest horizontal die edge. Hard placement blockage + all-layer route
# blockage + row cut. Notch x is centered (80 == 660-580) so orientation-
# invariant in x; the face flips the y extent. ---
set WINDOW_BOXES {}
set TOP_NF  0      ;# min notch-floor y of the TOP tiles (top windows' lower edge)
set BOT_NF  0      ;# max notch-floor y of the BOTTOM tiles (bottom windows' upper edge)
set h 0
foreach t $QTILES {
    lassign $t inst tx ty orient face
    set WX0 [expr {$tx + $TILE_NOTCH_X0}]
    set WX1 [expr {$tx + $TILE_NOTCH_X1}]
    if {$face eq "top"} {
        set WY0 [expr {$ty + $TILE_NOTCH_Y0}]        ;# notch floor
        set WY1 $DESIGN_HEIGHT
        set TOP_NF $WY0
    } else {
        set WY0 0
        set WY1 [expr {$ty + ($TILE_H - $TILE_NOTCH_Y0)}] ;# notch floor (flipped)
        set BOT_NF $WY1
    }
    lappend WINDOW_BOXES [list $WX0 $WY0 $WX1 $WY1]
    createPlaceBlockage -type hard -name analog_win$h -box [list $WX0 $WY0 $WX1 $WY1]
    createRouteBlk -name analog_win_rt$h -box [list $WX0 $WY0 $WX1 $WY1] -layer {1 2 3 4 5 6 7 8}
    cutRow -area [list $WX0 $WY0 $WX1 $WY1]
    incr h
}
cutRow
# Stripe band = 39um inboard of the notch-floor lines (C0's STRIPE_TOP_Y-39
# idiom): keeps the mesh clear of the tiles' notch-floor PG-pin ring band AND
# still inboard of the windows, so the extreme M8 stripes close the ring under
# both window edges without stubbing into the tile-row regions.
set STRIPE_Y0 [expr {$BOT_NF + 39}]
set STRIPE_Y1 [expr {$TOP_NF - 39}]
puts "### UNL STATUS ### : 4 analog windows -- top notch-floor=$TOP_NF bottom notch-floor=$BOT_NF ; stripe band=[list $STRIPE_Y0 $STRIPE_Y1]"
printStatus "Reserved 4 analog notch windows (500x451; two top-edge, two bottom-edge)"

# NB: unlike C0 there is NO full-width top_band blockage -- the ~1329um vertical
# channels between the left/right tiles (x in [680,2010]) in BOTH tile rows and
# the full center band are placeable shared-fabric area (cq_architecture SS2).

################################################################################
# Center band macros (y in [1051,1639], between the tile rows).
#   Shared RAM row: shbank0-3 + npuram0 (five 319.65x383.085 sram), centered.
#   ROM (R90) + POR + 2x DCO + 3x IRQ glitch filter in the band flanks / lower
#   strip (there is ample area -- packing only).
################################################################################
set BAND_Y0 [expr {$TILE_YB + $TILE_H}]     ;# 1051
set BAND_Y1 $TILE_YT                          ;# 1639
set BAND_MID [expr {($BAND_Y0 + $BAND_Y1) / 2.0}]  ;# 1345

set SRAM16K_WIDTH  319.650
set SRAM16K_HEIGHT 383.085
set SH_GAP   20
set SH_SPAN  [expr {5 * $SRAM16K_WIDTH + 4 * $SH_GAP}]      ;# 1678.25
set SH_X0    [expr {($DESIGN_WIDTH - $SH_SPAN) / 2.0}]      ;# 505.875
set SH_Y     [expr {$BAND_MID - $SRAM16K_HEIGHT / 2.0}]     ;# ~1153.46 (band-centered)
set i 0
foreach m {mcu0/shbank0 mcu0/shbank1 mcu0/shbank2 mcu0/shbank3 mcu0/npuram0} {
    placeInstance $m [expr {$SH_X0 + $i * ($SRAM16K_WIDTH + $SH_GAP)}] $SH_Y R0
    addHaloToBlock 4 4 4 4 $m
    incr i
}
cutRow
# inter-RAM gap keep-outs (wire-only slivers, C0 idiom)
for {set g 0} {$g < 4} {incr g} {
    set gx0 [expr {$SH_X0 + ($g + 1) * $SRAM16K_WIDTH + $g * $SH_GAP}]
    createPlaceBlockage -type hard -name ramgap$g \
        -box [list $gx0 [expr {$SH_Y - 4}] [expr {$gx0 + $SH_GAP}] [expr {$SH_Y + $SRAM16K_HEIGHT + 4}]]
    cutRow -area [list $gx0 [expr {$SH_Y - 4}] [expr {$gx0 + $SH_GAP}] [expr {$SH_Y + $SRAM16K_HEIGHT + 4}]]
}

# ROM (R90 -> 325.055 wide x 156.525 tall) in the left band flank (x < SRAM x0).
set ROM_X 40
set ROM_Y [expr {$BAND_MID - 156.525 / 2.0}]     ;# ~1266 (band-centered)
placeInstance mcu0/rom0 $ROM_X $ROM_Y R90
addHaloToBlock 9 4 4 9 mcu0/rom0

# POR / DCO / IRQ-glitch-filter abstracts: small; in the lower band strip
# (y in [1055,1150], below the SRAM row) across the roomy channel x-range.
set AMY 1070
placeInstance mcu0/por     700 $AMY R0 ; addHaloToBlock 4 4 4 4 mcu0/por
placeInstance mcu0/dco0    760 $AMY R0 ; addHaloToBlock 4 4 4 4 mcu0/dco0
placeInstance mcu0/dco1    840 $AMY R0 ; addHaloToBlock 4 4 4 4 mcu0/dco1
placeInstance mcu0/irq_gf0 920 $AMY R0 ; addHaloToBlock 4 4 4 4 mcu0/irq_gf0
placeInstance mcu0/irq_gf1 970 $AMY R0 ; addHaloToBlock 4 4 4 4 mcu0/irq_gf1
placeInstance mcu0/irq_gf2 1020 $AMY R0 ; addHaloToBlock 4 4 4 4 mcu0/irq_gf2
cutRow
printStatus "Placed shared RAM row + ROM + POR/DCO/glitch-filter in the center band"

puts "### UNL STATUS ### : no top-level pin shapes (ports ride pad PAD terminals)"

################################################################################
# Power. Analog windows on BOTH horizontal edges -> the core ring skips BOTH
# top and bottom die segments; left/right M7 verticals carry the loop. CQ3a
# FINDING: the hart_tile OBS blocks BOTH M7 and M8 (verified from out/
# hart_tile.lef), so -- unlike C0's assumption -- a full-width M8 rail CANNOT
# cross the tile rows at the notch-floor lines. The loop therefore CLOSES
# through the tile-free CENTER BAND (y in [1051,1639]): every full-width
# horizontal M8 mesh stripe there welds both M7 side legs (a ladder of rungs =
# a robustly closed grid). The horizontal M8 mesh is confined to the window-free
# y-band [BOT_NF,TOP_NF] (a horizontal M8 there never crosses a window -- windows
# are y<BOT_NF or y>TOP_NF at ANY x) and its center-band portion is the closure.
# Vertical M7 is confined to [STRIPE_Y0,STRIPE_Y1] (capped by the closure rungs,
# no floating stubs in the tile rows). Two dedicated M8 rails just inboard of the
# windows (below) add partial under-window closure in the tile-free channel +
# margins (broken over the tiles, which block M8 -- that is expected).
################################################################################
printStatus "Adding power ring (left/right M7; top+bottom skipped for analog windows)"
addRing \
    -nets {VDD VSS} \
    -type core_rings \
    -follow io \
    -skip_side {top bottom} \
    -layer {top M8 bottom M8 left M7 right M7} \
    -width $POWER_RING_PATH_WIDTH \
    -spacing $POWER_RING_PATH_SPACING \
    -offset $POWER_RING_PATH_SPACING \
    -center 0 -extend_corner {} -threshold 0 -jog_distance 0 \
    -snap_wire_center_to_grid None

# Horizontal M8 mesh + closure detours, confined to the window-free band.
# start/stop offset = spacing so the extreme stripes land near BOT_NF / TOP_NF
# (the closure rails). extend_to_closest_target ring welds them to the M7 legs.
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
    -start_from bottom \
    -area [list 0 $STRIPE_Y0 $DESIGN_WIDTH $STRIPE_Y1] \
    -set_to_set_distance $POWER_STRIPE_SET_TO_SET \
    -spacing $POWER_STRIPE_PATH_SPACING \
    -width $POWER_STRIPE_PATH_WIDTH \
    -block_ring_bottom_layer_limit M1 \
    -start_offset $POWER_STRIPE_PATH_SPACING \
    -stop_offset $POWER_STRIPE_PATH_SPACING

# Vertical M7 mesh: confined to the SAME [STRIPE_Y0,STRIPE_Y1] band so the
# verticals are capped by the closure rails (no floating stubs in the tile-row
# regions beyond the closures). Clean full-band straps in the two tile-row
# channels (x in [680,2010], no window/tile there); trimmed over tiles. bottom
# back to M1 -> owns macro-pin (M4) + follow-pin (M1) stacks on its centerlines.
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
    -area [list 0 $STRIPE_Y0 $DESIGN_WIDTH $STRIPE_Y1] \
    -set_to_set_distance $POWER_STRIPE_SET_TO_SET \
    -spacing $POWER_STRIPE_PATH_SPACING \
    -width $POWER_STRIPE_PATH_WIDTH \
    -block_ring_bottom_layer_limit M1 \
    -start_offset $POWER_STRIPE_SET_TO_SET \
    -stop_offset $POWER_STRIPE_PATH_SPACING

# --- Partial under-window M8 rails at the two notch-floor lines ---
# These add extra strapping in the tile-free CHANNEL + margins just inboard of
# the top/bottom windows (they break over the tiles, which block M8 -- the loop
# closure itself runs through the center band, above). remove_floating=FALSE so
# the surviving segments stay; extend_to_closest_target ring welds them to the
# side legs where they reach. Bands are 39um inboard of the notch floors so they
# never cross a window (windows are y>=TOP_NF / y<=BOT_NF at any x).
setAddStripeMode \
    -remove_floating_stripe_over_block false \
    -trim_antenna_back_to_shape core_ring \
    -stacked_via_top_layer M8 \
    -stacked_via_bottom_layer M7 \
    -extend_to_closest_target ring
# top closure rail (VDD+VSS pair) just below the top windows
addStripe \
    -layer M8 -nets {VDD VSS} -direction horizontal -start_from top \
    -area [list 0 [expr {$TOP_NF - 40}] $DESIGN_WIDTH [expr {$TOP_NF - 2}]] \
    -set_to_set_distance 800 -spacing $POWER_STRIPE_PATH_SPACING \
    -width $POWER_RING_PATH_WIDTH \
    -start_offset $POWER_STRIPE_PATH_SPACING -stop_offset $POWER_STRIPE_PATH_SPACING
# bottom closure rail (VDD+VSS pair) just above the bottom windows
addStripe \
    -layer M8 -nets {VDD VSS} -direction horizontal -start_from bottom \
    -area [list 0 [expr {$BOT_NF + 2}] $DESIGN_WIDTH [expr {$BOT_NF + 40}]] \
    -set_to_set_distance 800 -spacing $POWER_STRIPE_PATH_SPACING \
    -width $POWER_RING_PATH_WIDTH \
    -start_offset $POWER_STRIPE_PATH_SPACING -stop_offset $POWER_STRIPE_PATH_SPACING
puts "### UNL STATUS ### : added top+bottom M8 closure detours under the windows"

editTrim -all
setCheckMode -globalNet true -io true -route true -tapeOut true

printStatus "Routing power rails (followpin + block-pin)"
setSrouteMode -corePinMaxViaScale "100 10"
# blockPin+corePin, capped to the window-free band [BOT_NF,TOP_NF] (C0 cap
# idiom): connects every std-cell follow-pin in the band AND every macro/tile
# BASE PG pin (both tile rows' bases are inside [451,2239]; useLef =
# orientation-aware, so the MX/R180 flipped-tile pins strap correctly). The
# tiles' redundant FINGER pins (under the windows, y>TOP_NF / y<BOT_NF) are left
# alone -- the tile U-ring is closed internally (C0 precedent).
sroute \
    -nets { VSS VDD } \
    -allowLayerChange 0 \
    -allowJogging 0 \
    -connect {blockPin corePin} \
    -blockPin useLef \
    -area [list 0 $BOT_NF $DESIGN_WIDTH $TOP_NF] \
    -corePinWidth 0.3

# JOGGING block-pin pass over the whole window-free band -- the tile PG strap
# workhorse. The tiles are hardened MX/R180/MY/R0 macros with M7 PG pins on a
# 50um pitch at their base edges/notch-floor/finger bands; the straight pass
# above only lands where a stripe is coincident, so it strapped hart2 fully but
# missed the top tiles and hart3's VDD (orientation-dependent). Jogging +
# layerChange lets the router reach every flipped-tile M7 pin from the band mesh
# regardless of stripe phase -- this is the M16 backstop idiom applied to the
# tiles. Area = the window-free band (tile bases live entirely inside it).
printStatus "Routing tile + macro PG pins (jogging block-pin workhorse pass)"
sroute \
    -nets { VSS VDD } \
    -connect { blockPin } \
    -blockPin useLef \
    -allowLayerChange 1 \
    -allowJogging 1 \
    -layerChangeRange { M1(1) M8(8) } \
    -area [list 0 $BOT_NF $DESIGN_WIDTH $TOP_NF]

# Pad-supply hookup: the core-domain supply pads (PVDD1DGZ_G.VDD / PVSS1DGZ_G.VSS
# bound to VDD/VSS by the globalNetConnect -inst * above) tie to the core ring.
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

################################################################################
# DB-level PG verification (PG2-F1 rule: prove hookup from the DB, not the log).
# Written to rpt/chip_top_quad.pgcheck.rpt and echoed to the log.
################################################################################
set fh [open $REPORT_DIR/$BASENAME.pgcheck.rpt w]
proc pgputs {fh s} { puts $fh $s; puts "### PGCHK ### $s" }

# Physical PG-pin evidence for an inst: count VDD/VSS special wires (any strap
# layer) whose box intersects the inst bbox -> straps physically land on it.
proc box_isect {a b} {
    lassign $a ax0 ay0 ax1 ay1
    lassign $b bx0 by0 bx1 by1
    return [expr {$ax0 <= $bx1 && $bx0 <= $ax1 && $ay0 <= $by1 && $by0 <= $ay1}]
}
proc swires_over {netname bbox} {
    set n 0
    set netp [dbGet -p top.nets.name $netname]
    foreach w [dbGet $netp.sWires] {
        set b {}; catch { set b [dbGet $w.box] }
        if {[llength $b] == 1} { set b [lindex $b 0] }
        if {[llength $b] != 4} { continue }
        if {[box_isect $b $bbox]} { incr n }
    }
    return $n
}
proc inst_bbox {inst} {
    set ip [dbGet -p top.insts.name $inst]
    if {$ip eq "0x0" || $ip eq ""} { return {} }
    set b [dbGet $ip.box]
    if {[llength $b] == 1} { set b [lindex $b 0] }
    return $b
}

pgputs $fh "== CQ3a PG verification =="
pgputs $fh "DESIGN box: 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT   TOP_NF=$TOP_NF BOT_NF=$BOT_NF  stripe band=[list $STRIPE_Y0 $STRIPE_Y1]"

# 1) Both-edge ring closure + 2) mesh presence. Scan M8/M7 special wires (box
#    via scalar attrs box_llx/lly/urx/ury). Report the widest-span M8 shape near
#    each closure line (STRIPE_Y1 top, STRIPE_Y0 bottom) = the closure detours.
# The tile OBS blocks M8, so a full-width M8 rail cannot cross the tile rows at
# the notch-floor lines -- the ring loop CLOSES through the tile-free CENTER
# BAND (y in [1051,1639]) where full-width M8 stripes weld both M7 side legs.
# Report: (a) widest M8 span in the center band (the real closure, target ~W),
# (b) widest M8 span near each notch-floor line (the partial under-window rails).
set BAND_LO $BAND_Y0 ; set BAND_HI $BAND_Y1
foreach net {VDD VSS} {
    set netp [dbGet -p top.nets.name $net]
    set best_band 0 ; set best_top 0 ; set best_bot 0
    set m8 0 ; set m7 0
    foreach w [dbGet $netp.sWires] {
        set l "?"; catch { set l [dbGet $w.layer.name] }
        if {$l eq "M8"} { incr m8 } elseif {$l eq "M7"} { incr m7 } else { continue }
        if {$l ne "M8"} { continue }
        set b {}; catch { set b [dbGet $w.box] }
        if {[llength $b] == 1} { set b [lindex $b 0] }
        if {[llength $b] != 4} { continue }
        lassign $b x0 y0 x1 y1
        if {![string is double -strict $x0] || ![string is double -strict $y0]} { continue }
        set span [expr {$x1 - $x0}]
        set yc   [expr {($y0 + $y1) / 2.0}]
        if {$yc >= $BAND_LO && $yc <= $BAND_HI && $span > $best_band} { set best_band $span }
        if {$yc >= [expr {$STRIPE_Y1 - 60}] && $span > $best_top} { set best_top $span }
        if {$yc <= [expr {$STRIPE_Y0 + 60}] && $span > $best_bot} { set best_bot $span }
    }
    pgputs $fh "ring-closure $net : CENTER-BAND full-width M8 span=[format %.1f $best_band]um (=the closure, target ~$DESIGN_WIDTH) ; under-window partials TOP=[format %.1f $best_top] BOT=[format %.1f $best_bot]"
    pgputs $fh "mesh $net : M8 sWires=$m8  M7 sWires=$m7"
}

# 3) Flipped-tile + macro physical PG straps: count VDD/VSS special wires
#    landing on each inst bbox. The MX/R180 (bottom, Y-mirrored) tiles are the
#    new physical problem -- if their PG pins strap, VDD>0 AND VSS>0 here.
foreach t $QTILES {
    lassign $t inst tx ty orient face
    set bb [inst_bbox $inst]
    if {$bb eq {}} { pgputs $fh "tile $inst : INSTANCE NOT FOUND"; continue }
    pgputs $fh "tile $inst ($orient,$face) bbox=$bb : VDD sWires=[swires_over VDD $bb]  VSS sWires=[swires_over VSS $bb]"
}
foreach inst {mcu0/shbank0 mcu0/shbank1 mcu0/shbank2 mcu0/shbank3 mcu0/npuram0 mcu0/rom0} {
    set bb [inst_bbox $inst]
    if {$bb eq {}} { pgputs $fh "macro $inst : NOT FOUND"; continue }
    pgputs $fh "macro $inst bbox=$bb : VDD sWires=[swires_over VDD $bb] VSS sWires=[swires_over VSS $bb]"
}
close $fh
puts "### UNL STATUS ### : PG verification written to $REPORT_DIR/$BASENAME.pgcheck.rpt"

# Signoff-grade special-net connectivity -- counts, not just 'ran' (PG2-F1).
verifyConnectivity \
    -nets {VDD VSS} \
    -type special \
    -error 100000 \
    -report $REPORT_DIR/$BASENAME.verifyConnectivity.pg.rpt

# Parse the special-net opens and test whether any lie inside the FLIPPED
# bottom-tile bboxes (hart2/hart3) or the macro bboxes -> authoritative
# "the PG pin is physically connected" evidence (an unstrapped pin = an open
# AT that pin). Cosmetic pad-ring/slack opens (C0's 703 class) are NOT inside
# these bboxes.
set fh2 [open $REPORT_DIR/$BASENAME.pgcheck.rpt a]
set checkboxes {}
foreach t $QTILES { lassign $t inst tx ty orient face; lappend checkboxes [list $inst [inst_bbox $inst]] }
foreach inst {mcu0/shbank0 mcu0/npuram0 mcu0/rom0} { lappend checkboxes [list $inst [inst_bbox $inst]] }
array set opencnt {}
foreach cb $checkboxes { set opencnt([lindex $cb 0]) 0 }
set total_opens 0
if {[catch {open $REPORT_DIR/$BASENAME.verifyConnectivity.pg.rpt r} vf] == 0} {
    foreach line [split [read $vf] "\n"] {
        if {[regexp {opens at \(([-0-9.]+), *([-0-9.]+)\) *\(([-0-9.]+), *([-0-9.]+)\)} $line -> ax ay bx by]} {
            incr total_opens
            set ob [list $ax $ay $bx $by]
            foreach cb $checkboxes {
                if {[lindex $cb 1] ne {} && [box_isect $ob [lindex $cb 1]]} {
                    incr opencnt([lindex $cb 0])
                }
            }
        }
    }
    close $vf
}
pgputs $fh2 "-- special-net opens: total=$total_opens (pad-ring/slack cosmetic class expected; C0 baseline 703)"
foreach cb $checkboxes {
    pgputs $fh2 "   opens inside [lindex $cb 0] bbox = $opencnt([lindex $cb 0])   (0 = PG pins strapped)"
}
close $fh2

# verifyGeometry with the analog-window + seal ROUTE blockages removed, to
# isolate REAL shorts from the transient tile-finger-pin-vs-window-blk class
# (those pins sit under the window keep-out by construction; the blk is deleted
# at CQ5 routing, C0 precedent). PLACE blockages stay. Re-created after.
deleteAllRouteBlks
verifyGeometry \
    -error 10000 -warning 10000 \
    -report $REPORT_DIR/$BASENAME.verifyGeometry.noblk.rpt
# restore the route keep-outs into the saved DB
seal_keepouts
set h 0
foreach t $QTILES {
    lassign $t inst tx ty orient face
    lassign [lindex $WINDOW_BOXES $h] WX0 WY0 WX1 WY1
    createRouteBlk -name analog_win_rt$h -box [list $WX0 $WY0 $WX1 $WY1] -layer {1 2 3 4 5 6 7 8}
    incr h
}
createRouteBlk -box $DIE_LLX $DIE_LLY $DIE_URX $DIE_URY -layer 7
createRouteBlk -box $DIE_LLX $DIE_LLY $DIE_URX $DIE_URY -layer 8

################################################################################
# Save the floorplan+PG DB + a DEF for external PG inspection, then STOP.
################################################################################
saveDesign $DATABASE_DIR/$BASENAME.floorplan_pg.innovus -def -netlist
defOut -floorplan -routing $OUTPUT_DIR/$BASENAME.floorplan_pg.def
puts "### UNL STATUS ### : saved DB + DEF (floorplan+PG stage)"

################################################################################
# ===================== CQ5: PLACE / CTS / ROUTE / VERIFY =====================
# APPENDED stage (CQ5). The geometry/PG sections above are the CQ3a-validated
# floorplan and are UNCHANGED. This continuation runs place_opt -> CTS -> route
# -> signoff verify on the SAME live session (a saved-DB restore FATALs in
# tapeOut check mode against the timing-less pad cells -- CQ4 finding -- so the
# flow stays one continuous session, exactly like C0 chip_top.innovus.tcl).
# Modeled byte-for-byte on C0 chip_top's place/CTS/route/verify (same MCU_MP
# hierarchy inside), MINUS streamOut (NO GDS at CQ5 -- signoff is CQ6). Gated by
# RUN_PNR so a CQ3a-only floorplan run is still reproducible (set RUN_PNR 0).
# Entering here the route blockages present = seal band + 4 analog windows +
# die-frame M7 + die-frame M8 (recreated in the tail above), the correct state.
################################################################################
if {![info exists RUN_PNR]} { set RUN_PNR 1 }
if {$RUN_PNR} {
    printStatus "CQ5: entering placement"

    # Spurious clock-gating checks on the TIMER ClockMuxGlitchFree select legs
    # (C0 precedent). Gate names are genus-mapped/netlist-dependent; a resynth
    # can rename them -> catch-skip keeps the flow alive (the disable only
    # suppresses a false gating-check, it never gates route/verify/sim).
    set_interactive_constraint_modes [all_constraint_modes -active]
    foreach g {mcu0/timer0/g11710 mcu0/timer1/g11710} {
        if {[catch {set_disable_clock_gating_check $g} r]} {
            puts "### UNL WARN ### : gating-check disable SKIPPED for $g: $r"
        } else {
            puts "### UNL STATUS ### : gating-check disabled on $g"
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
    printStatus "CQ5: placement done"
    saveDesign $DATABASE_DIR/$BASENAME.place.innovus -def -netlist

    ############################################################################
    # Clock tree synthesis -- balances into the four tile clk pins
    ############################################################################
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
    # leakage-only report optDesign writes implicitly.
    # Consumed by tools/python/gen_power_dashboard.py.
    catch {report_power -outfile $REPORT_DIR/${BASENAME}_postCTS_full.power}
    timeDesign -postCTS -expandedViews -outDir $REPORT_DIR/$BASENAME.timeDesign.postcts
    report_ccopt_clock_trees -file $REPORT_DIR/$BASENAME.report_ccopt_clock_trees.postcts
    report_ccopt_skew_groups -file $REPORT_DIR/$BASENAME.report_ccopt_skew_groups.postcts
    printStatus "CQ5: CTS done"

    ############################################################################
    # Signal routing
    ############################################################################
    printStatus "CQ5: running nanoroute"
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
    # OBSOLETE in 20.12 -- IMPOPT-7016 -- so use SIAware delaycal + plain hold).
    setDelayCalMode -SIAware true
    setOptMode -holdTargetSlack 0.01
    optDesign -postRoute -hold
    setOptMode -holdTargetSlack 0
    # Full post-route power (see postCTS note)
    catch {report_power -outfile $REPORT_DIR/${BASENAME}_postRoute_full.power}

    # Postroute verifyGeometry WITH route blockages present: the 244
    # tile-finger-pin-under-window-blk transient "shorts" (CQ3a noblk isolation)
    # must be CLEARED now that routing is done (C0 precedent) -- verified from
    # this report in the CQ5 writeup.
    verifyGeometry \
        -error 10000 \
        -warning 10000 \
        -report $REPORT_DIR/$BASENAME.verifyGeometry.postroute.rpt
    ecoRoute -fix_drc
    verifyGeometry \
        -error 10000 \
        -warning 10000 \
        -report $REPORT_DIR/$BASENAME.verifyGeometry.postroute2.rpt

    deleteAllRouteBlks
    # deleteAllRouteBlks stripped the seal-band keep-outs too; restore ONLY the
    # seal band (C0 precedent). Do NOT restore the analog-window ROUTE blocks:
    # the tiles' redundant PG finger pins sit under the notch windows by
    # construction, so a restored window route-block makes verifyGeometry report
    # them as "SHORT: Pin vs Routing Blockage" (the ~244 transient class). C0
    # deletes-and-does-not-restore them; the window HARD PLACE blockages survive
    # deleteAllRouteBlks (only route blks are removed) so the notch stays
    # cell-free, and nothing was ever routed into the window (route block was
    # present through nanoroute) -- so deleting the route block adds no metal and
    # the 244 shorts clear. Verified by the finalize verifyGeometry.
    seal_keepouts
    addFiller

    ############################################################################
    # Signoff checks + reports (NO streamOut -- CQ6 owns GDS)
    ############################################################################
    printStatus "CQ5: verifyConnectivity (signoff)"
    verifyConnectivity \
        -error 100000 \
        -connectPadSpecialPorts \
        -report $REPORT_DIR/$BASENAME.verifyConnectivity.signoff.rpt

    printStatus "CQ5: verifyGeometry (signoff)"
    verifyGeometry \
        -antenna \
        -report $REPORT_DIR/$BASENAME.verifyGeometry.signoff.rpt

    setDelayCalMode -SIAware false
    setAnalysisMode -analysisType onChipVariation -cppr both
    printStatus "CQ5: timeDesign signoff"
    timeDesign \
        -si \
        -signoff \
        -outdir $REPORT_DIR/$BASENAME.timeDesign.signoff.rpt

    reportGateCount -level 2 -outfile $REPORT_DIR/$BASENAME.reportGateCount.signoff.rpt
    summaryReport   -noHtml   -outfile $REPORT_DIR/$BASENAME.summaryReport.signoff.rpt

    # Reset tapeOut check mode BEFORE saving so the routed DB restores cleanly
    # (the floorplan_pg DB carried -tapeOut true and FATALed on restore -- CQ4).
    setCheckMode -tapeOut false
    saveDesign $DATABASE_DIR/$BASENAME.signoff.innovus -def -netlist -rc -tcon

    ############################################################################
    # Top-only sim netlist + SDF for the pads-in-DUT gate smoke (NOT GDS).
    ############################################################################
    printStatus "CQ5: writing SDF + Xcelium netlist (top level; tiles as leaf refs)"
    write_sdf $OUTPUT_DIR/$BASENAME.sdf
    saveNetlist $OUTPUT_DIR/$BASENAME.xsim.v -excludeCellInst ANTENNA2A10TH

    puts "### UNL STATUS ### : CQ5 P&R complete -- routed DB + SDF + xsim netlist saved (NO GDS)"
}

# Layout images for orchestrator eyeball -- only when a GUI/display is up (run
# the flow WITHOUT -no_gui under Xvfb). Guarded so the headless signoff run just
# skips them. No DB restore needed (design is live -> no tapeOut-mode replay).
if {![catch {fit}]} {
    catch { redraw ; dumpToGIF $OUTPUT_DIR/$BASENAME.full.gif }
    catch { zoomBox 1900 -50 2800 1150 ; redraw ; dumpToGIF $OUTPUT_DIR/$BASENAME.hart3_R180.gif }
    catch { zoomBox -50 1550 800 2750 ; redraw ; dumpToGIF $OUTPUT_DIR/$BASENAME.hart0_R0.gif }
    catch { zoomBox -50 950 2750 1750 ; redraw ; dumpToGIF $OUTPUT_DIR/$BASENAME.center_band.gif }
    catch { fit ; redraw }
    puts "### UNL STATUS ### : layout GIFs dumped"
}
toc
printStatus "chip_top_quad CQ3a floorplan+PG stage complete"
exit
