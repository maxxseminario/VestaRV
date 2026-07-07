################################################################################
# Innovus script -- M15 chip_top PAD-RING FLOORPLAN PROTOTYPE (Flavor A).
#
# GEOMETRY ONLY. Builds the real tphn65gpgv2od3_sl pad ring around a reserved
# core area on a 3x3 mm die (Myshkin reference), proving the pinout and that the
# analog domain (12 electrode pads + AVDD/AVSS, 4x 3-electrode) physically fits.
# There is NO core netlist, NO CTS, NO routing, NO signoff -- the deliverable is
# the placed ring (GDS/DEF + a pad-placement report). The functional, connected
# chip_top + gate sim is the deferred "Flavor B".
#
# Input netlist is the STUB in/chip_top.v (pads only; core-facing pins dangle).
# Pad cells come from the tphn LEF (macros carry the _G names the gate tb uses);
# constants.tcl's IO_PAD_DIR (tpfn twin) is OVERRIDDEN below.
#
# Ring geometry (die 3000, pad depth 135, pad width 25 along the row):
#   BOTTOM (analog, isolated): AVSS, aio[0..11], AVDD
#   TOP  : VSSIO, resetn, prt1[7:0], VDD, prt2[7:0], VDDIO
#   LEFT : VSS,  prt3[7:0], VDDIO, POC
#   RIGHT: VSS,  prt4[7:0], VSSIO, VDD
################################################################################

source tcl/constants.tcl
source $SCRIPT_DIR/procedures.tcl

set DESIGN_NAME chip_top
set BASENAME    chip_top

# tphn pad LEF (matches the gate-tb verilog _G cells + carries SITE pad/corner).
# NOTE: constants.tcl IO_PAD_DIR points at the tpfn twin, whose macros lack the
# _G suffix and the SD signal pad -- override to the tphn 9lm LEF here.
# 8lm variant matches the M1-M8 stack in the std-cell tech LEF (the 9lm twin
# adds M9/VIA8 the tech LEF doesn't define -> "unknown layer" on streamOut).
set IO_PAD_LEF "/opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/lef/tphn65gpgv2od3_sl_210a/mt_2/8lm/lef/tphn65gpgv2od3_sl_8lm.lef"

# --- Ring / die parameters (microns) ---
set DIE   3000.0   ;# square die edge (Myshkin 3x3 mm reference)
set RING  135.0    ;# pad depth (pad-cell height, from LEF)
set PADW   25.0    ;# signal/supply pad width along the row (from LEF)
set SPAN  [expr {$DIE - 2*$RING}]   ;# usable pad span per side (between corners)

# --- Reserved core area (M14 assembly is 1400 x 2160), centered ---
set CORE_W 1400.0
set CORE_H 2160.0

tic

################################################################################
# Design import (LEF + stub netlist; trivial MMMC just to satisfy init_design)
################################################################################
set init_verilog    "$INPUT_DIR/chip_top.v"
set init_top_cell   "$DESIGN_NAME"
set init_pwr_net    "vdd"
set init_gnd_net    "vss"
set init_mmmc_file  "$SCRIPT_DIR/viewdefinition_chip.tcl"

# std-cell macro LEF is loaded only for its SITE def (TSMC65ADV10TSITE, needed
# by floorPlan to create core rows) -- the std cells themselves are unused here.
set init_lef_file "$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef \
                   $STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
                   $IO_PAD_LEF"

set init_design_uniquify 1
init_design

setDesignMode -process 65

################################################################################
# Floorplan: 3x3 mm die, 135 um IO margin -> core box (135,135)-(2865,2865)
################################################################################
floorPlan \
    -site TSMC65ADV10TSITE \
    -s $SPAN $SPAN $RING $RING $RING $RING

printStatus "Die [expr {$DIE/1000.0}] x [expr {$DIE/1000.0}] mm, pad ring depth $RING um"

################################################################################
# Pad placement
#
# Innovus placeInstance <x> <y> <orient> lands the ORIENTED bounding box's
# lower-left corner at (x,y) (the bbox always grows +x/+y, regardless of
# orient). So origin = bbox lower-left for every side. Standard CCW ring
# orientations: bottom R0, right R90, top R180, left R270 (rails abut at
# corners). Oriented dims: R0/R180 = PADW x RING; R90/R270 = RING x PADW.
################################################################################

# Place one pad instance in slot i of n on a given side (block centered on side).
proc place_pad {inst side i n} {
    global DIE RING PADW SPAN
    set block [expr {$n * $PADW}]
    set start [expr {$RING + ($SPAN - $block) / 2.0}]
    set lo    [expr {$start + $i * $PADW}]
    set far   [expr {$DIE - $RING}]
    switch -- $side {
        bottom { placeInstance $inst $lo  0.0  R0   -fixed }
        top    { placeInstance $inst $lo  $far R180 -fixed }
        left   { placeInstance $inst 0.0  $lo  R270 -fixed }
        right  { placeInstance $inst $far $lo  R90  -fixed }
        default { error "bad side $side" }
    }
}

# Place a whole ordered side list.
proc place_side {side padlist} {
    set n [llength $padlist]
    set i 0
    foreach inst $padlist {
        place_pad $inst $side $i $n
        incr i
    }
    printStatus "Placed $n pads on $side edge"
}

# --- Corners (PCORNER_G is 135x135; bbox LL at origin) ---
set far [expr {$DIE - $RING}]
placeInstance PAD_CORNER_BL 0.0   0.0   R0   -fixed
placeInstance PAD_CORNER_BR $far  0.0   R90  -fixed
placeInstance PAD_CORNER_TR $far  $far  R180 -fixed
placeInstance PAD_CORNER_TL 0.0   $far  R270 -fixed

# --- Ordered pad lists per side (analog isolated on the bottom edge) ---
set BOTTOM [list PAD_avss \
    PAD_aio_0 PAD_aio_1 PAD_aio_2 PAD_aio_3 PAD_aio_4 PAD_aio_5 \
    PAD_aio_6 PAD_aio_7 PAD_aio_8 PAD_aio_9 PAD_aio_10 PAD_aio_11 \
    PAD_avdd]

set TOP [list PAD_vssio_0 PAD_resetn \
    PAD_prt1_0 PAD_prt1_1 PAD_prt1_2 PAD_prt1_3 PAD_prt1_4 PAD_prt1_5 PAD_prt1_6 PAD_prt1_7 \
    PAD_vdd_0 \
    PAD_prt2_0 PAD_prt2_1 PAD_prt2_2 PAD_prt2_3 PAD_prt2_4 PAD_prt2_5 PAD_prt2_6 PAD_prt2_7 \
    PAD_vddio_0]

set LEFT [list PAD_vss_0 \
    PAD_prt3_0 PAD_prt3_1 PAD_prt3_2 PAD_prt3_3 PAD_prt3_4 PAD_prt3_5 PAD_prt3_6 PAD_prt3_7 \
    PAD_vddio_1 PAD_poc]

set RIGHT [list PAD_vss_1 \
    PAD_prt4_0 PAD_prt4_1 PAD_prt4_2 PAD_prt4_3 PAD_prt4_4 PAD_prt4_5 PAD_prt4_6 PAD_prt4_7 \
    PAD_vssio_1 PAD_vdd_1]

place_side bottom $BOTTOM
place_side top    $TOP
place_side left   $LEFT
place_side right  $RIGHT

printStatus "All pads + corners placed"

################################################################################
# IO fillers -- complete the ring bus between placed pads
################################################################################
if {[catch {
    addIoFiller -cell {PFILLER20_G PFILLER10_G PFILLER5_G PFILLER1_G PFILLER05_G PFILLER0005_G} -prefix IOFILL
} r]} {
    printWarning "addIoFiller failed ($r) -- retrying after addIoRow"
    if {[catch {addIoRow} r2]} { printWarning "addIoRow also failed: $r2" }
    catch {addIoFiller -cell {PFILLER20_G PFILLER10_G PFILLER5_G PFILLER1_G PFILLER05_G PFILLER0005_G} -prefix IOFILL}
}
printStatus "IO fillers added"

################################################################################
# Reserve the core area (M14 assembly footprint), centered
################################################################################
set cx0 [expr {$DIE/2.0 - $CORE_W/2.0}]
set cy0 [expr {$DIE/2.0 - $CORE_H/2.0}]
set cx1 [expr {$DIE/2.0 + $CORE_W/2.0}]
set cy1 [expr {$DIE/2.0 + $CORE_H/2.0}]
catch {createPlaceBlockage -box $cx0 $cy0 $cx1 $cy1 -name CORE_RESERVE}
printStatus "Core area reserved: ($cx0 $cy0) - ($cx1 $cy1)  [expr {$CORE_W/1000.0}]x[expr {$CORE_H/1000.0}] mm"

# NOTE: supply-pad injection pins (VDD/VSS/VDDPST/VSSPST/AVDD/AVSS) are regular
# signal PINs in this LEF, not PG pins, and the stub netlist already connects
# them to the vdd/vss/vddio/vssio/avdd/avss nets -- no globalNetConnect needed.
# The physical ring bus is formed by pad/filler abutment. Signoff-grade PG
# routing is a Flavor-B concern.

################################################################################
# Checks + outputs (geometry-only)
################################################################################
verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$BASENAME.verifyGeometry.rpt

# Pad-placement report: every instance, cell, orient, bbox -- the ring proof.
set fh [open $REPORT_DIR/$BASENAME.padring.rpt w]
puts $fh "# M15 chip_top pad-ring placement (die ${DIE}x${DIE} um, ring ${RING} um)"
puts $fh [format "%-18s %-16s %-6s %s" INSTANCE CELL ORIENT BBOX_um]
foreach ip [lsort [dbGet top.insts.name]] {
    set p    [dbGetInstByName $ip]
    set cell [dbGet $p.cell.name]
    set ori  [dbGet $p.orient]
    set box  [dbGet $p.box]
    puts $fh [format "%-18s %-16s %-6s %s" $ip $cell $ori $box]
}
close $fh
printStatus "Pad-ring report written: $REPORT_DIR/$BASENAME.padring.rpt"

defOut  -floorplan -netlist $OUTPUT_DIR/$BASENAME.def
saveDesign $DATABASE_DIR/$BASENAME.innovus -def

# No -mapFile: the Myshkin innovus2gds.map is a 6-metal map (its CELL-type line
# trips IMPOGDS-395 and it lacks the pad layers). Default layer-number mapping
# is fine for a geometry prototype GDS.
catch {streamOut \
    $OUTPUT_DIR/$BASENAME.gds2 \
    -libName WorkLib \
    -structureName $DESIGN_NAME \
    -units 1000 \
    -mode ALL} soerr
printStatus "streamOut: $soerr"

summaryReport -noHtml -outfile $REPORT_DIR/$BASENAME.summaryReport.rpt

toc
printStatus "chip_top pad-ring prototype complete"
exit
