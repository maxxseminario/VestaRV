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
# Seal-ring zone: Myshkin's pad band is 155 um and PDUW16SDGZ_G is 135 um deep,
# so the pad outer edge sits 20 um inside the die edge -- that band holds the
# chip seal ring (SEALRING_3mm, csr_cmn65gp; CORNER_B is in Myshkin's tapeout
# GDS). Here it is RESERVED (place+route keep-out) + drawn; the real seal-ring
# metal is GDS-merged from the OA cell at chip assembly (Virtuoso), not placeable
# as a LEF macro in Innovus.
set OFF    20.0    ;# die edge -> pad outer edge (Myshkin: 155 - 135)
set SEALW  10.0    ;# drawn seal-ring band width (representative; inside OFF)
set SPAN  [expr {$DIE - 2*($OFF + $RING)}]   ;# pad span between inset corners

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
# Pads are inset by OFF from the die edge (seal-ring zone lives in that band).
proc place_pad {inst side i n} {
    global DIE RING PADW SPAN OFF
    set block [expr {$n * $PADW}]
    set start [expr {$OFF + $RING + ($SPAN - $block) / 2.0}]
    set lo    [expr {$start + $i * $PADW}]
    set near  $OFF                          ;# outer edge of the pad row
    set far   [expr {$DIE - $OFF - $RING}]   ;# inner origin for top/right rows
    switch -- $side {
        bottom { placeInstance $inst $lo   $near R0   -fixed }
        top    { placeInstance $inst $lo   $far  R180 -fixed }
        left   { placeInstance $inst $near $lo   R270 -fixed }
        right  { placeInstance $inst $far  $lo   R90  -fixed }
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

# --- Corners (PCORNER_G is 135x135; bbox LL at origin; inset by OFF) ---
set near $OFF
set far  [expr {$DIE - $OFF - $RING}]
placeInstance PAD_CORNER_BL $near $near R0   -fixed
placeInstance PAD_CORNER_BR $far  $near R90  -fixed
placeInstance PAD_CORNER_TR $far  $far  R180 -fixed
placeInstance PAD_CORNER_TL $near $far  R270 -fixed

# --- Ordered pad lists per side (analog isolated on the bottom edge) ---
# Factored into a data-only file so the C0 diff-check can source them too.
source $SCRIPT_DIR/chip_top_padlists.tcl

# C0 diff-check against the generated platform/common package ring (pad
# EXISTENCE drift = FAIL lines; side/order deltas are expected WARNs -- the
# die-ring-vs-package-order question is unreconciled, Flavor A stays
# authoritative for placement). Non-fatal: report and continue.
if {[catch {
    source $SCRIPT_DIR/check_padring_vs_castalia.tcl
    check_padring_vs_castalia
} pcerr]} {
    printWarning "padring diff-check failed to run: $pcerr"
}

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
# Chip seal ring (representation)
#
# The real seal ring is the SEALRING_3mm OA cell (csr_cmn65gp) -- corner +
# edge-segment structures on every metal + via, GDS-merged at chip assembly
# (Myshkin's tapeout GDS carries its CORNER_B). It is not a placeable Innovus
# LEF macro, so here the OFF-wide die-edge band is RESERVED with place + route
# keep-outs (the correct P&R-side representation: nothing places or routes in
# the seal-ring zone) and the seal metal itself is drawn in the visualization.
################################################################################
set frames [list \
    [list 0.0            0.0            $DIE           $OFF] \
    [list 0.0            [expr {$DIE-$OFF}] $DIE        $DIE] \
    [list 0.0            0.0            $OFF           $DIE] \
    [list [expr {$DIE-$OFF}] 0.0        $DIE           $DIE]]
set i 0
foreach f $frames {
    lassign $f x0 y0 x1 y1
    catch {createPlaceBlockage -box $x0 $y0 $x1 $y1 -name SEALRING_$i}
    catch {createRouteBlk -box $x0 $y0 $x1 $y1 -layer {1 2 3 4 5 6 7 8}}
    incr i
}
printStatus "Seal-ring zone reserved: outer $OFF um band (real cell = SEALRING_3mm, GDS-merge)"

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
