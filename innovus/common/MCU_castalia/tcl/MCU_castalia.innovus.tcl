################################################################################
# Innovus script -- MCU_castalia: the CONNECTED 3x3mm WOUND-PATCH SoC on
# the QUADRANT-SYMMETRIC Castalia-Quad floorplan, in the LQFP-100 pad ring.
#
# CONSTRUCTION RULE (read this before editing anything below):
#   GEOMETRY / FLOORPLAN / PG RECIPE  <=  tcl/chip_top_quad.innovus.tcl  (CQ3a+CQ5)
#   RING / NETLIST / NAMES / GUARDS   <=  tcl/chip_top_wound.innovus.tcl (Stage I)
# Neither source file was modified. Every deliberate delta is flagged in place
# with "WQ-DELTA <n>" and enumerated in the block at the bottom of this header.
#
# WHAT THIS IS: the wound SoC (QSPI / I3C / NFC / OneWire / I2C-target / TRNG /
# EVFAB / 4-ch DMA / PWRCTRL harvested-boot) re-cut on the proven symmetric
# quad die instead of the Stage-I rectangular-in-square die. FLAT chip run:
# MCU_castalia instantiates the tphn pads and `MCU mcu0`, and the whole
# MCU_WOUND hierarchy is placed and routed IN this design (the four hart tiles
# stay hardened LEF macros + per-corner ETMs). There is NO block P&R in this
# path -- the wound control plane places directly into the quad CENTER BAND.
#
# FRAME: the QUAD frame verbatim -- DESIGN 2690 x 2690, symmetric die
# (-155,-155)-(2845,2845) = exactly 3000 x 3000, interior span 2690, margins 0.
# NOT the Stage-I wound chip's asymmetric (-155.5,-650)-(2844.5,2350) frame:
# that one exists only because the MCU_WOUND *block* cut is 2689 x 1700 and had
# to be centred in the square interior. Here the assembly IS the interior.
#
# FLOORPLAN FIT: the wound control plane is ~61.6k non-tile instances /
# ~234.8k um2 of std cell (2.4x / 2.1x the DP block -- nfc0 alone is ~87.5k
# um2). Placeable area on this floorplan = the center band (2690 x 588 minus
# the SRAM row / ROM / analog macros, ~0.95 mm2) PLUS both tile-row channels
# (x in [680,2010] x 1050, twice = 2.79 mm2) = ~3.7 mm2 -> ~6% utilisation.
# Roomy; congestion, not area, is the thing to watch on the first cut.
#
# PREREQUISITES (all present on disk as of 2026-07-27 except this run's own
# products):
#   1. genus/out/MCU_WOUND_hier.genus.{v,sdc}      (Jul 26 17:57)
#   2. ./prep_top_netlist_wound.sh -> in/MCU_WOUND_hier.pnr.v (Jul 26 19:09)
#      -- consumed UNCHANGED; this chip does not need its own block prep.
#      ./prep_top_netlist_MCU_castalia.sh does the POST-run xsim strip.
#   3. ./gen_MCU_castalia_sdc.sh -> in/MCU_castalia.sdc
#   4. ../hart_tile/out/hart_tile.{lef,gds2,etm_ss.lib,etm_ff.lib}  (Jul 21/22 M19c cut)
#
# NAME-COLLISION: mcu0's cell is named MCU == the Myshkin tape-out cell. That is
# handled ONLY at signoff strmin (signoff_mp/strmin_gds.sh, topcell != MCU
# branch: it pins the internal MCU cell and the P*_G tphn pad family) -- NEVER
# stream this chip with a raw strmin.
#
# --------------------------- WQ-DELTA LIST ----------------------------------
#  1. Header / provenance / prerequisites (this block).
#  2. DESIGN_NAME + BASENAME = MCU_castalia; init_verilog =
#     in/MCU_castalia.v + in/MCU_WOUND_hier.pnr.v; init_mmmc_file =
#     tcl/viewdefinition_MCU_castalia.tcl.
#  3. PADLISTS: the EXISTING tcl/chip_top_wound_padlists.tcl is SOURCED, not
#     forked -- the LQFP-100 pinout is identical (same 72 pads, same order,
#     same PDDW16SDGZ_G on PAD_P5_6/PAD_P5_7). chip-top-flow rule: share the
#     padlist unless the pinout differs.
#  4. irq_gf3 added to the center-band analog row at (1070,1070) N, continuing
#     the 50 um pitch (the wound/DP netlists have 4 GlitchFilters; the C0-era
#     MCU_MP netlist the quad flow was written against had 3).
#  5. cq8a fix (a): vertical M7 stripe start_offset shifted +9.0 um.
#  6. cq8a fix (b): the two under-window M8 closure-rail spans and the
#     [STRIPE_Y0,STRIPE_Y1] mesh band snapped to the 0.9 um VIA7 array pitch.
#  7. cq8a fix (c): irq_gf halo 4 -> 20 um on ALL FOUR glitch filters.
#  8. cq8a note (d): the M3.S.2/M5.S.2 ECO coordinates recorded, NOT re-applied.
#  14. PRCUT_G ring-break bracket at x=1195/1470 isolating the north analog
#      band (Stage J LVS forensics: PDB3A_G guard strap = real metal1 VDD-VSS
#      short at the ARSV0/AVSS abutment; see the WQ-DELTA 14 block).
#  15. VSS_1 strap-to-stripe M7 weld (padPin sroute missed the stripe by
#      1.6 um; see the WQ-DELTA 15 block).
#  9. TRNG0 ring-oscillator preserve gate (dbSet dontTouch) before placement --
#     from the wound flow, with `mcu0/u_ro/*` added as the FIRST pattern (the
#     hier netlist puts TrngRoEnsemble u_ro at MCU level, a SIBLING of trng0,
#     not inside it -- the wound chip flow's own open risk).
# 10. PG-fabric baseline + global count guards before EVERY saveDesign
#     (CLAUDE.md bare-`editDelete` class). The quad flow writes three DBs, so
#     the wound flow's two-guard pattern is generalised into a proc.
# 11. Explicit ${BASENAME}_post{CTS,Route}_full.power pair (dashboard).
# 12. streamOut added (the quad flow deliberately had none -- CQ6 owned GDS).
#     Merge list = ../hart_tile/out/hart_tile.gds2 + the tphn 8lm pad GDS ONLY. NEVER add a
#     block/assembly GDS: this is a FLAT run, the MCU geometry is native to the
#     chip struct, and merging one injects a duplicate `MCU` struct plus a
#     second differently-seeded MCU_VIA* family = the PG4 struct-hijack class.
# 13. timer ClockMuxGlitchFree gating-check disables annotated (see the site).
################################################################################

source ../shared/constants.tcl
source ../shared/procedures.tcl

# WQ-DELTA 2
set DESIGN_NAME MCU_castalia
set BASENAME    MCU_castalia

# WQ-DELTA 3: SHARED padlist file (not a fork). The wound LQFP-100 emission is
# the pinout authority for both wound chips; PAD_P5_6/PAD_P5_7 are the
# PDDW16SDGZ_G pull-DOWN pads (DP-S3 strap/PGOOD contract, BINDING).
set PADLISTS chip_top_wound_padlists.tcl

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
# margin 0: assembly == interior (square-in-square, Argus-style). With
# DESIGN == INT_SPAN the per-axis centering offsets collapse to 0, so the
# rectangular-in-square per-edge math of the Stage-I wound chip degenerates to
# the single PAD_NEAR/PAD_FAR pair used here.
set MARGIN_X  [expr {($INT_SPAN - $DESIGN_WIDTH)  / 2.0}] ;# 0
set MARGIN_Y  [expr {($INT_SPAN - $DESIGN_HEIGHT) / 2.0}] ;# 0
set IN_LLX [expr {-$MARGIN_X}]                            ;# 0
set IN_LLY [expr {-$MARGIN_Y}]                            ;# 0
set IN_URX [expr {$DESIGN_WIDTH  + $MARGIN_X}]            ;# 2690
set IN_URY [expr {$DESIGN_HEIGHT + $MARGIN_Y}]            ;# 2690
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

# ---- 0.9 um VIA7 stacked-via array pitch snap helpers (A6 VIA-PHASE-RULE) ---
# Every deliberate PG-geometry offset in this script is a multiple of 0.9 um,
# and every PG band edge is snapped INBOARD onto that grid, so the assembly PG
# via arrays and the tiles' own arrays stay in phase (A6 manufactured
# VIA7.S.1/S.2 x 75,768 by shifting a tile row 0.5 um -- a non-multiple).
set VIA7_PITCH 0.9
proc wq_snap09_up {v} { global VIA7_PITCH ; return [expr {ceil($v / $VIA7_PITCH) * $VIA7_PITCH}] }
proc wq_snap09_dn {v} { global VIA7_PITCH ; return [expr {floor($v / $VIA7_PITCH) * $VIA7_PITCH}] }

tic

################################################################################
# Design import: chip wrapper (pads + mcu0) FIRST, then the MCU_WOUND hier
# netlist it instantiates (WQ-DELTA 2).
################################################################################
set init_verilog             "$INPUT_DIR/MCU_castalia.v ../MCU_WOUND/in/MCU_WOUND_hier.pnr.v"
set init_top_cell            "$DESIGN_NAME"
set init_pwr_net             "VDD"
set init_gnd_net             "VSS"
set init_mmmc_file           "$SCRIPT_DIR/viewdefinition_MCU_castalia.tcl"

# tphn pad LEF (M15): 8lm variant matches the M1-M8 tech LEF (9lm adds M9/VIA8
# -> unknown-layer spam on streamOut); tpfn is the WRONG family.
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

# Tile timing enters via the ETM .lib (viewdefinition_MCU_castalia.tcl:
# ../hart_tile/out/hart_tile.etm_{ss,ff}.lib) -- the tile is a timed macro exactly like the
# SRAMs/ROM. The pad cells + the 3 analog abstracts enter LEF-only
# (timing-less; IMPVL-366 rule -- no dummy libs).

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

# WQ-DELTA 14 -- PRCUT_G ring-break bracket around the north analog band.
# ROOT CAUSE (Stage J LVS forensics, 2026-07-27): PDB3A_G's internal guard-ring
# strap (GDS HBG527_PREPDB3A_GR, cell-local x=0 edge) hard-bridges the pad
# ring's n-well guard band (tied to core VDD by the PVDD1DGZ pads) to the
# p-sub guard band (tied to core VSS) -- a REAL metal1 VDD-VSS short at the
# PAD_ARSV0/PAD_AVSS abutment (x=1420, north row), proven by a Pegasus
# dual-injected-text FIND_SHORTS path (2,478 shapes, all hard CONNECT-rule
# hops, articulation shape SN915). Innovus verifyGeometry/Connectivity and
# Calibre DRC are all structurally blind to it (the G0 class).
# The proven Myshkin/C0/quad rings use the AVSS..PDB3A..AVDD BRACKET motif so
# their electrode pads never abut the live digital bands; the G2 LQFP-100
# model's band order (AVDD,AVSS,ARSV0-7) violates that -- chip_top_dp and the
# Stage-I chip_top_wound INHERIT this short (reported separately, not fixed
# here). Fix on this chip: bracket the whole analog band [1220,1470] with
# PRCUT_G cells (25x135, geometrically EMPTY = every abutment bus and both
# guard bands break by absence). Placed in the flanking PFILLER space so NO
# bonded pad moves (pins 76-85 keep their positions); orientation matches the
# top row (R180/S). Placed BEFORE addIoFiller so the filler pass fills around
# them. North row has no digital signal pads and all VDDPST/VSSPST pairs are
# on W/S/E, so the digital ring's C-loop keeps every segment supplied; the
# analog island keeps its own TAVDD/TAVSS via PAD_AVDD/PAD_AVSS.
placeInstance RING_CUT_W 1195.0 $PAD_FAR_Y R180 -fixed
placeInstance RING_CUT_E 1470.0 $PAD_FAR_Y R180 -fixed
puts "### UNL STATUS ### : PRCUT_G ring-break bracket placed at x=1195/1470 (north analog island isolated)"

# WQ-DELTA 3: the SHARED wound padlist file (LEFT 22 / BOTTOM 20 / RIGHT 20 /
# TOP 10 = 72 pads, LQFP-100 emission order).
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
#   mcu0/hart0 top-left  R0   @(20,1639)   notch faces TOP edge
#   mcu0/hart1 top-right MY   @(2010,1639) notch faces TOP edge
#   mcu0/hart2 bot-left  MX   @(20,1)      notch faces BOTTOM edge
#   mcu0/hart3 bot-right R180 @(2010,1)    notch faces BOTTOM edge
# x_right = 2690-20-660 = 2010; y_top = 2690-1-1050 = 1639 (both odd -> ON the
# y=1,3,5 row grid; bottom origin 1 also odd -> both rows on-grid). 10um halos.
# Verbatim from tcl/chip_top_quad.innovus.tcl and confirmed against the CQ3a
# as-built DEF (out/chip_top_quad.floorplan_pg.def, 2000 dbu/um:
#   hart0 (40000,3278000) N / hart1 (4020000,3278000) FN /
#   hart2 (40000,2000) FS  / hart3 (4020000,2000) S).
################################################################################
set TILE_W        660
set TILE_H        1050
set TILE_NOTCH_X0 80
set TILE_NOTCH_X1 580
set TILE_NOTCH_Y0 600   ;# tile-local notch-floor height (from the tile base)
set TILE_X0       20
set TILE_XR       [expr {$DESIGN_WIDTH - $TILE_X0 - $TILE_W}]        ;# 2010
set TILE_YT       [expr {$DESIGN_HEIGHT - $CORE_SPACING - $TILE_H}]  ;# 1639
set TILE_YB       $CORE_SPACING                                      ;# 1

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
# invariant in x; the face flips the y extent.
#
# WOUND NOTE: the wound SoC carries NO analog IP -- these four 500x451 windows
# are RESERVED-EMPTY here. They are kept, verbatim and unconditional, because
# the whole PG recipe below (ring skip top+bottom, center-band M8 closure,
# under-window rails, sroute area caps) is characterised against exactly this
# window set on the CQ6/CQ8a baseline. Removing them would invalidate that
# baseline and every DRC/PG number carried over from it; the empty windows cost
# 4 x 0.225 mm2 of placeable area that this ~6%-utilised floorplan does not
# need. Any future wound analog (or the CA re-cut) drops straight in. ---
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

# ---- WQ-DELTA 6 (cq8a fix b, part 1): mesh band snapped to the VIA7 pitch ----
# Quad baseline: STRIPE_Y0 = BOT_NF+39 = 490.0 , STRIPE_Y1 = TOP_NF-39 = 2200.0
# (39 um inboard of the notch-floor lines, the C0 idiom -- clear of the tiles'
# notch-floor PG-pin ring band, still inboard of the windows).
# Snapped INBOARD onto the 0.9 um VIA7 stacked-via array grid so no PG band
# edge -- and therefore no generated via array or weld -- starts at a sub-pitch
# phase:
#   490.0 -> ceil(490.0/0.9)=545  -> 490.5   (+0.5, inboard)
#   2200.0 -> floor(2200.0/0.9)=2444 -> 2199.6 (-0.4, inboard)
# Both moves are INBOARD, so the "never crosses a window" invariant is
# strengthened, not weakened.
set STRIPE_Y0_RAW [expr {$BOT_NF + 39}]
set STRIPE_Y1_RAW [expr {$TOP_NF - 39}]
set STRIPE_Y0 [wq_snap09_up $STRIPE_Y0_RAW]
set STRIPE_Y1 [wq_snap09_dn $STRIPE_Y1_RAW]
puts "### UNL STATUS ### : 4 analog windows -- top notch-floor=$TOP_NF bottom notch-floor=$BOT_NF"
puts "### UNL STATUS ### : stripe band raw=[list $STRIPE_Y0_RAW $STRIPE_Y1_RAW] -> 0.9um-snapped=[list $STRIPE_Y0 $STRIPE_Y1]"
printStatus "Reserved 4 analog notch windows (500x451; two top-edge, two bottom-edge; RESERVED-EMPTY on wound)"

# NB: unlike C0/the Stage-I wound chip there is NO full-width top_band blockage
# -- the ~1330um vertical channels between the left/right tiles (x in
# [680,2010]) in BOTH tile rows and the full center band are placeable
# shared-fabric area. That is where the wound control plane lands.

################################################################################
# Center band macros (y in [1051,1639], between the tile rows).
#   Shared RAM row: shbank0-3 + npuram0 (five 319.65x383.085 sram), centered.
#   ROM (R90/W) + POR + 2x DCO + 4x IRQ glitch filter in the band flanks /
#   lower strip. Coordinates verbatim from the quad flow and confirmed against
#   out/chip_top_quad.floorplan_pg.def (SRAM row y=1153.455, rom0 (40,1266.735)
#   W, por (700,1070), dco0 (760,1070), dco1 (840,1070), irq_gf0/1/2
#   (920/970/1020, 1070)).
################################################################################
set BAND_Y0 [expr {$TILE_YB + $TILE_H}]            ;# 1051
set BAND_Y1 $TILE_YT                               ;# 1639
set BAND_MID [expr {($BAND_Y0 + $BAND_Y1) / 2.0}]  ;# 1345

set SRAM16K_WIDTH  319.650
set SRAM16K_HEIGHT 383.085
set SH_GAP   20
set SH_SPAN  [expr {5 * $SRAM16K_WIDTH + 4 * $SH_GAP}]      ;# 1678.25
set SH_X0    [expr {($DESIGN_WIDTH - $SH_SPAN) / 2.0}]      ;# 505.875
set SH_Y     [expr {$BAND_MID - $SRAM16K_HEIGHT / 2.0}]     ;# 1153.4575 (band-centered)
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

# ROM (R90/W -> 325.055 wide x 156.525 tall) in the left band flank (x < SRAM x0).
set ROM_X 40
set ROM_Y [expr {$BAND_MID - 156.525 / 2.0}]     ;# 1266.7375 (band-centered)
placeInstance mcu0/rom0 $ROM_X $ROM_Y R90
addHaloToBlock 9 4 4 9 mcu0/rom0

# POR / DCO / IRQ-glitch-filter abstracts: small; in the lower band strip
# (y in [1070,1089], below the SRAM row) across the roomy channel x-range.
#
# ---- WQ-DELTA 7 (cq8a fix c): irq_gf halo 4 -> 20 um on ALL FOUR ------------
# CQ8a class DM2.S.2 x2 ("Space to M2 >= 0.3 um"), measured from the CQ8a
# chipdrc results db (signoff_mp/calibre/cq8a_iso/chip_top_quad/chipdrc/
# results/chipdrc.db):
#     p1  x[935.414,935.986]  y[1076.790,1076.975]
#     p2  x[1035.414,1035.986] y[1076.790,1076.975]
# GlitchFilter LEF SIZE = 31.195 x 18.87, so irq_gf0 occupies x[920,951.195]
# and irq_gf2 x[1020,1051.195], both y[1070,1088.870]: BOTH results sit at the
# IDENTICAL macro-local offset (15.414..15.986 , 6.790..6.975) -- i.e. the same
# GlitchFilter-INTERNAL dummy-M2 feature vs adjacent center-band M2. There is
# no chip-level fill step that can regenerate macro-internal geometry (CQ8a),
# so the only floorplan-stage lever is to keep band metal away from the macro.
# Halo 4 -> 20 um on all four filters (max(20, quad 4 + 10) = 20). At the 50 um
# placement pitch the 18.805 um inter-macro gaps are fully blocked -- they were
# never usable for placement anyway -- and band routing is pushed >= 20 um out,
# 66x the 0.3 um rule. irq_gf1 (970) shows no violation today; it gets the same
# halo so the row is uniform and a re-route cannot move the class onto it.
set GF_HALO 20
set AMY 1070
placeInstance mcu0/por     700 $AMY R0 ; addHaloToBlock 4 4 4 4 mcu0/por
placeInstance mcu0/dco0    760 $AMY R0 ; addHaloToBlock 4 4 4 4 mcu0/dco0
placeInstance mcu0/dco1    840 $AMY R0 ; addHaloToBlock 4 4 4 4 mcu0/dco1
placeInstance mcu0/irq_gf0 920 $AMY R0 ; addHaloToBlock $GF_HALO $GF_HALO $GF_HALO $GF_HALO mcu0/irq_gf0
placeInstance mcu0/irq_gf1 970 $AMY R0 ; addHaloToBlock $GF_HALO $GF_HALO $GF_HALO $GF_HALO mcu0/irq_gf1
placeInstance mcu0/irq_gf2 1020 $AMY R0 ; addHaloToBlock $GF_HALO $GF_HALO $GF_HALO $GF_HALO mcu0/irq_gf2
# ---- WQ-DELTA 4: irq_gf3 --------------------------------------------------
# The wound (and DP) netlists instantiate FOUR GlitchFilters at MCU level --
# verified in genus/out/MCU_WOUND_hier.genus.v and in the P&R input
# in/MCU_WOUND_hier.pnr.v (`GlitchFilter irq_gf0..irq_gf3`, module MCU) -> the
# chip-level paths are mcu0/irq_gf0..3. tcl/chip_top_quad.innovus.tcl places
# only three because it was written against the older C0 MCU_MP netlist. 1070
# continues the 50 um pitch; the macro then occupies x[1070,1101.195], entirely
# inside the jogging block-pin sroute area below (that pass is FULL-WIDTH here,
# [0, BOT_NF, DESIGN_WIDTH, TOP_NF] -- unlike the Stage-I wound chip, whose
# narrow {440 460 1085 515} backstop had to be widened by hand for irq_gf3).
placeInstance mcu0/irq_gf3 1070 $AMY R0 ; addHaloToBlock $GF_HALO $GF_HALO $GF_HALO $GF_HALO mcu0/irq_gf3
cutRow
printStatus "Placed shared RAM row + ROM + POR/DCO/4x glitch-filter in the center band"

puts "### UNL STATUS ### : no top-level pin shapes (ports ride pad PAD terminals)"

################################################################################
# Power. Analog windows on BOTH horizontal edges -> the core ring skips BOTH
# top and bottom die segments; left/right M7 verticals carry the loop. The
# hart_tile OBS blocks BOTH M7 and M8, so a full-width M8 rail CANNOT cross the
# tile rows at the notch-floor lines: the loop CLOSES through the tile-free
# CENTER BAND (y in [1051,1639]), where every full-width horizontal M8 mesh
# stripe welds both M7 side legs (a ladder of rungs = a robustly closed grid).
# The horizontal M8 mesh is confined to the window-free y-band
# [STRIPE_Y0,STRIPE_Y1]; vertical M7 is confined to the same band (capped by
# the closure rungs, no floating stubs in the tile rows). Two dedicated M8
# rails just inboard of the windows add partial under-window closure.
# All verbatim from the quad flow except the two WQ-DELTA sites below.
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

################################################################################
# WQ-DELTA 5 -- cq8a fix (a): vertical M7 stripe x-PHASE SHIFT (+9.0 um)
#
# CLASS: M7.S.3 x1 + the x=355 member of M7.S.4 (the A6 VIA-PHASE-RULE extended
# to stripe-vs-macro-pin phase, CQ8a war story 1). Numbers, all measured:
#
# 1) rom0 geometry. LEF SIZE 156.525 BY 325.055; placed (40, 1266.7375) R90/W
#    -> oriented bbox 325.055 x 156.525 = x[40, 365.055], y[1266.7375,1423.2625]
#    (DEF-confirmed: `- mcu0/rom0 rom_hvt_pg + FIXED (80000 2533470) W`,
#    2000 dbu/um).
#    IMPORTANT: rom_hvt_pg.lef contains ZERO M7 geometry (grep M7 -> 0 hits).
#    Its PG pins are FULL-WIDTH M4 bands `RECT 0.0 y0 156.525 y1`. Under W the
#    local-y band maps to a chip-x band:  x = 40 + (325.055 - y_local).
#    The seven bands nearest the ROM's right edge:
#        VSS local[12.965,13.765] -> chip x[351.290,352.090]
#        VDD local[11.565,12.365] -> chip x[352.690,353.490]
#        VSS local[10.165,10.965] -> chip x[354.090,354.890]
#        VDD local[ 8.765, 9.565] -> chip x[355.490,356.290]
#        VSS local[ 7.365, 8.165] -> chip x[356.890,357.690]
#        VSS local[ 4.565, 5.365] -> chip x[359.690,360.490]
#        VDD local[ 3.165, 3.965] -> chip x[361.090,361.890]
#    => the ROM PG comb occupies chip x 351.290 .. 361.890 (0.8 um bands on a
#    1.4 um pitch). The "ROM M7 pin" of the CQ8a note is the router-generated
#    M7 riser that follows these x positions.
#
# 2) Measured violations (signoff_mp/calibre/cq8a_iso/chip_top_quad/chipdrc/
#    results/chipdrc.db; the reported rectangle is the SPACE region):
#        M7.S.3 (space >= 0.5)  x[355.000,355.490] y[1244.000,1249.000] = 0.490
#        M7.S.4 (space >= 1.5)  same rect  (p7)
#        M7.S.4 (space >= 1.5)  x[357.690,359.000] y[1253.000,1258.000] = 1.310
#    Each gap is bounded on one side by a ROM comb-band edge (355.490 = the VDD
#    band's left edge; 357.690 = the VSS band's right edge) and on the other by
#    a mesh M7 edge at x = 355.000 / 359.000. The two y spans are exactly the
#    horizontal M8 stripe pair rows, so the mesh side is a stripe-grid-phased
#    shape: shifting the vertical M7 grid moves it.
#
# 3) Required clearance. The 5 um-wide PG stripes are "wide metal" for
#    M7.S.4 (line width > 4.5 um, parallel run > 4.5 um) => 1.5 um. Forbidden
#    mesh-edge window = comb +/- 1.5 = x[349.790, 363.390].
#
# 4) Chosen shift: +9.0 um = 10 x 0.9 um (the VIA7 stacked-via array pitch, so
#    the A6 via-phase invariant holds).
#        355.000 -> 364.000 : clearance to comb right edge 361.890 = 2.110 um
#                             (>= 1.5, margin 0.610 ; >= 0.5, margin 1.610)
#        359.000 -> 368.000 : clearance = 6.110 um
#    Both are OUTSIDE [349.790,363.390]. A smaller shift cannot work: the
#    forbidden window (13.6 um) is wider than the 4.0 um separation of the two
#    offending edges, so the pair must clear the comb together.
#
# RESIDUAL RISK (be honest on the first cut): the x=355.000/359.000 edges could
# not be attributed to a specific generator without a GDS window scan, because
# the ROM abstract has no M7 to reason from. If the first chipdrc still shows
# M7.S.3/M7.S.4 near x 351..363, run
#   signoff_mp/gds_via_window.py on out/MCU_castalia.gds2 around
#   (355,1246) and (359,1255)
# BEFORE touching this number again -- and rule out a translation phantom
# first (the PG4 discipline).
################################################################################
set M7_PHASE_SHIFT 9.0    ;# 10 x VIA7_PITCH (0.9 um) -- see the block above
set M7_START_OFFSET [expr {$POWER_STRIPE_SET_TO_SET + $M7_PHASE_SHIFT}]
puts "### UNL STATUS ### : vertical M7 start_offset $POWER_STRIPE_SET_TO_SET -> $M7_START_OFFSET (cq8a fix a, +$M7_PHASE_SHIFT = [expr {int($M7_PHASE_SHIFT/$VIA7_PITCH)}] x $VIA7_PITCH um VIA7 pitch)"

# Vertical M7 mesh: confined to the SAME [STRIPE_Y0,STRIPE_Y1] band so the
# verticals are capped by the closure rails. bottom back to M1 -> owns
# macro-pin (M4) + follow-pin (M1) stacks on its centerlines.
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
    -start_offset $M7_START_OFFSET \
    -stop_offset $POWER_STRIPE_PATH_SPACING

################################################################################
# --- Partial under-window M8 rails at the two notch-floor lines ---
# Extra strapping in the tile-free CHANNEL + margins just inboard of the
# top/bottom windows (they break over the tiles, which block M8 -- the loop
# closure itself runs through the center band). remove_floating=FALSE so the
# surviving segments stay; extend_to_closest_target ring welds them to the side
# legs where they reach.
#
# WQ-DELTA 6 -- cq8a fix (b), part 2: WELD-STUB GUARD.
# CLASS: VIA7.W.1 x2 ("Width (maximum = minimum) = 0.36"). Measured cuts
# (same chipdrc.db): 0.36 x 0.51 at
#     x[2164.070,2164.430]  y[1046.320,1046.830]
#     x[2164.070,2164.430]  y[1643.170,1643.680]
# i.e. legal 0.36 in x, MALFORMED 0.51 in y -- a stacked-via generation stub.
#
# HONEST LOCATION FINDING (differs from the staging brief's premise): those two
# cuts do NOT lie in these under-window rails. x = 2164.25 is inside the RIGHT
# tile column (hart1/hart3 span x[2010,2670]); y = 1046.575 is 4.425 um BELOW
# the bottom tiles' top edge (1051) and y = 1643.425 is 4.425 um ABOVE the top
# tiles' bottom edge (1639) -- the exact mirror pair, i.e. the TILE PG-pin weld
# band at the two center-band-facing tile edges. The under-window rails live at
# y ~[457,481] and ~[2199,2237], hundreds of um away.
#
# WHAT IS DONE HERE: every band edge that drives a weld/via generation in this
# script is snapped INBOARD onto the 0.9 um VIA7 array grid, so no PG span can
# start or stop at a sub-pitch phase and leave a 0.4 um weld stub:
#     top rail    raw y[2199.000,2237.000] -> [2199.600,2236.500]
#     bottom rail raw y[ 453.000, 491.000] -> [ 453.600, 490.500]
#     mesh band   raw y[ 490.000,2200.000] -> [ 490.500,2199.600]  (above)
# All four moves are inboard, so no rail creeps toward a window.
#
# WHAT IS **NOT** CLAIMED: this snap is a hygiene guard; it is NOT proven to
# remove the two measured VIA7.W.1 cuts, which sit at the tile PG weld band.
# FIRST-CUT ACTION: if chipdrc still reports VIA7.W.1, dump the source GDS
# around (2164.25,1046.575) with signoff_mp/gds_via_window.py and histogram the
# cuts with signoff_mp/via7_map.py -- verifyGeometry does NOT check same-net
# cut spacing/shape across two via structs, so "vG GREEN" says nothing here.
################################################################################
set UWR_TOP_Y0 [wq_snap09_up [expr {$TOP_NF - 40}]]   ;# 2199.000 -> 2199.600
set UWR_TOP_Y1 [wq_snap09_dn [expr {$TOP_NF -  2}]]   ;# 2237.000 -> 2236.500
set UWR_BOT_Y0 [wq_snap09_up [expr {$BOT_NF +  2}]]   ;#  453.000 ->  453.600
set UWR_BOT_Y1 [wq_snap09_dn [expr {$BOT_NF + 40}]]   ;#  491.000 ->  490.500
puts "### UNL STATUS ### : under-window rails 0.9um-snapped -- top=[list $UWR_TOP_Y0 $UWR_TOP_Y1] bottom=[list $UWR_BOT_Y0 $UWR_BOT_Y1]"

setAddStripeMode \
    -remove_floating_stripe_over_block false \
    -trim_antenna_back_to_shape core_ring \
    -stacked_via_top_layer M8 \
    -stacked_via_bottom_layer M7 \
    -extend_to_closest_target ring
# top closure rail (VDD+VSS pair) just below the top windows
addStripe \
    -layer M8 -nets {VDD VSS} -direction horizontal -start_from top \
    -area [list 0 $UWR_TOP_Y0 $DESIGN_WIDTH $UWR_TOP_Y1] \
    -set_to_set_distance 800 -spacing $POWER_STRIPE_PATH_SPACING \
    -width $POWER_RING_PATH_WIDTH \
    -start_offset $POWER_STRIPE_PATH_SPACING -stop_offset $POWER_STRIPE_PATH_SPACING
# bottom closure rail (VDD+VSS pair) just above the bottom windows
addStripe \
    -layer M8 -nets {VDD VSS} -direction horizontal -start_from bottom \
    -area [list 0 $UWR_BOT_Y0 $DESIGN_WIDTH $UWR_BOT_Y1] \
    -set_to_set_distance 800 -spacing $POWER_STRIPE_PATH_SPACING \
    -width $POWER_RING_PATH_WIDTH \
    -start_offset $POWER_STRIPE_PATH_SPACING -stop_offset $POWER_STRIPE_PATH_SPACING
puts "### UNL STATUS ### : added top+bottom M8 closure detours under the windows"

################################################################################
# WQ-DELTA 8 -- cq8a note (d): the M3.S.2 / M5.S.2 cut-blockage redo is
# DELIBERATELY NOT re-applied.
#
# CQ8a's sanctioned ECO (cut blockage + `ecoRoute -fix_drc` on the CQ6 signoff
# DB) closed exactly two center-band classes with zero collateral:
#     M3.S.2 x2  at (1012, 895)
#     M5.S.2 x1  at (1012, 935)
# Those were ROUTER artifacts at coordinates specific to the quad's C0-era
# std-cell route. This chip has a DIFFERENT netlist (the wound control plane,
# 2.4x the instances), a different placement and a fresh route, so re-applying
# a blockage at (1012,89x) would be cargo-culting a coordinate. NB those two
# classes are ALREADY absent from the cq8a chipdrc.db read above -- that db is
# the POST-ECO cut (1946 -> 1943), which is why the numbers quoted in the fix
# blocks above cover only the four classes the ECO could not fix.
# FIRST-CUT ACTION: grep the first chipdrc for M3.S.2 / M5.S.2. If the class
# recurs anywhere, the CQ8a v2 recipe (cut blockage + ecoRoute -fix_drc, and
# NO filler churn -- deleteFiller/addFiller on a routed DB manufactured ~400
# min-area results in CQ8a v1) is the proven fix.
################################################################################

editTrim -all
setCheckMode -globalNet true -io true -route true -tapeOut true

printStatus "Routing power rails (followpin + block-pin)"
setSrouteMode -corePinMaxViaScale "100 10"
# blockPin+corePin, capped to the window-free band [BOT_NF,TOP_NF]: connects
# every std-cell follow-pin in the band AND every macro/tile BASE PG pin (both
# tile rows' bases are inside [451,2239]; useLef = orientation-aware, so the
# MX/R180 flipped-tile pins strap correctly).
sroute \
    -nets { VSS VDD } \
    -allowLayerChange 0 \
    -allowJogging 0 \
    -connect {blockPin corePin} \
    -blockPin useLef \
    -area [list 0 $BOT_NF $DESIGN_WIDTH $TOP_NF] \
    -corePinWidth 0.3

# JOGGING block-pin pass over the whole window-free band -- the tile + analog
# macro PG strap workhorse. FULL WIDTH, so it covers the entire analog row
# including irq_gf3 at x[1070,1101.195] (no hand-widened x-window is needed
# here, unlike the Stage-I wound chip's {440 460 1085 515} backstop).
printStatus "Routing tile + macro PG pins (jogging block-pin workhorse pass)"
sroute \
    -nets { VSS VDD } \
    -connect { blockPin } \
    -blockPin useLef \
    -allowLayerChange 1 \
    -allowJogging 1 \
    -layerChangeRange { M1(1) M8(8) } \
    -area [list 0 $BOT_NF $DESIGN_WIDTH $TOP_NF]

# Pad-supply hookup: the core-domain supply pads (PVDD1DGZ_G.VDD /
# PVSS1DGZ_G.VSS, bound to VDD/VSS by the globalNetConnect -inst * above) tie
# to the core ring. ACCEPTANCE = the "sroute ... created N wires" log line
# (trust the COUNT, not the absence of an error -- PG2-F1) + the signoff
# verifyConnectivity -connectPadSpecialPorts gate.
sroute \
    -nets { VSS VDD } \
    -connect { padPin } \
    -allowJogging 1 \
    -allowLayerChange 1 \
    -layerChangeRange { M1(1) M8(8) } \
    -area [list $DIE_LLX $DIE_LLY $DIE_URX $DIE_URY]
puts "### UNL STATUS ### : pad-supply sroute (padPin) done"

# WQ-DELTA 15 -- VSS_1 strap-to-stripe weld. Stage J forensics: the padPin
# sroute's PAD_VSS_1 strap (M2 riser at x=1324.6, bottom edge -> y 508.5 with
# a via stack to M7 at the top) MISSES the VSS vertical M7 stripe (x-span
# 1318..1323) by 1.6 um -- a pad-hookup OPEN that LVS cannot see (VSS binds
# via substrate regardless) and Innovus connectivity never names (pad
# terminals are absent from the report realm). Same-net M7 patch welding the
# strap's via6 landing to the stripe; overlaps both deterministically
# (addStripe and the pad-pin x are floorplan-fixed). Nearest opposite-net M7
# (VDD stripe edge x=1314) is 4.9 um away, > the 1.5 um wide-metal rule.
add_shape -net VSS -layer M7 -rect {1318.9 503.8 1326.1 509.2} -shape STRIPE -status ROUTED
puts "### UNL STATUS ### : VSS_1 strap-to-stripe M7 weld added (x 1318.9-1326.1, y 503.8-509.2)"

################################################################################
# WQ-DELTA 10: PG-fabric baseline + reusable global count guard.
# CLAUDE.md's editDelete class: a bare `editDelete` wipes EVERY wire and special
# wire in the design, and dbDeleteObj returns rc=0 while cutting via structs.
# Record the size of the PG fabric now -- complete, and before any signal
# routing exists -- and gate on it before EVERY saveDesign (this flow writes
# three DBs plus the final one, vs the Stage-I wound chip's two).
# NB `dbGet ... -e` returns the literal 0x0 on an empty result; llength of that
# is 1, so it is normalized here.
################################################################################
proc __wq_count {path} {
	set r [dbGet $path -e]
	if {$r eq "0x0" || $r eq ""} { return 0 }
	return [llength $r]
}
set PG_SWIRES_BASE [__wq_count top.nets.sWires]
set PG_INSTS_BASE  [__wq_count top.insts.name]
puts "### UNL STATUS ### : PG baseline -- $PG_INSTS_BASE insts, $PG_SWIRES_BASE special wires"
if {$PG_SWIRES_BASE == 0 || $PG_INSTS_BASE == 0} {
	puts "FATAL (count guard): PG fabric or instance list is EMPTY after power build."
	exit 1
}

# $tag is printed with the census. `top.wires` is NOT a dbGet path -- signal
# wires live under top.nets.wires (same for sWires); getting that wrong is how a
# corpse passes for a design. `want_wires` is 0 before routing exists.
proc __wq_guard {tag {want_wires 1}} {
	global PG_SWIRES_BASE PG_INSTS_BASE
	set gi [__wq_count top.insts.name]
	set gs [__wq_count top.nets.sWires]
	set gw [__wq_count top.nets.wires]
	# TRNG rings, re-censused BY NAME (not by saved pointers: dbGet on a pointer
	# whose object was deleted can error rather than return 0x0).
	set gr 0
	foreach __pat {mcu0/u_ro/* mcu0/trng0/u_ro/* mcu0/*u_ro/* mcu0/*u_ro*} {
		set __r [dbGet top.insts.name $__pat -e]
		if {$__r eq "0x0" || $__r eq ""} { continue }
		set __n [llength $__r]
		if {$__n > $gr} { set gr $__n }
	}
	puts "### UNL STATUS ### : census \[$tag\] -- insts $gi (base $PG_INSTS_BASE), sWires $gs (base $PG_SWIRES_BASE), wires $gw, TRNG ring cells $gr"
	if {$gi == 0 || $gs == 0} {
		puts "FATAL (count guard) \[$tag\]: insts/sWires collapsed -- refusing to saveDesign a gutted database."
		exit 1
	}
	if {$want_wires && $gw == 0} {
		puts "FATAL (count guard) \[$tag\]: signal-wire count is ZERO after routing."
		exit 1
	}
	if {$gs < [expr {$PG_SWIRES_BASE / 2}]} {
		puts "FATAL (count guard) \[$tag\]: special-wire count $gs is less than half the post-power baseline $PG_SWIRES_BASE -- PG fabric was destroyed."
		exit 1
	}
	if {$gr > 0 && $gr < 210} {
		puts "WARNING (TRNG RO) \[$tag\]: census $gr ring cells (< 210) -- entropy path may have been optimized."
	}
}

verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$BASENAME.verifyGeometry.preplace.rpt
fixVia -short
fixVia -minCut
fixVia -minStep

################################################################################
# DB-level PG verification (PG2-F1 rule: prove hookup from the DB, not the log).
# Written to rpt/MCU_castalia.pgcheck.rpt and echoed to the log.
################################################################################
set fh [open $REPORT_DIR/$BASENAME.pgcheck.rpt w]
proc pgputs {fh s} { puts $fh $s; puts "### PGCHK ### $s" }

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

pgputs $fh "== MCU_castalia PG verification (CQ3a method) =="
pgputs $fh "DESIGN box: 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT   TOP_NF=$TOP_NF BOT_NF=$BOT_NF  stripe band=[list $STRIPE_Y0 $STRIPE_Y1]"
pgputs $fh "cq8a fixes: M7 start_offset=$M7_START_OFFSET (+$M7_PHASE_SHIFT) ; under-window rails top=[list $UWR_TOP_Y0 $UWR_TOP_Y1] bot=[list $UWR_BOT_Y0 $UWR_BOT_Y1] ; irq_gf halo=$GF_HALO"

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

# Flipped-tile + macro physical PG straps. The MX/R180 (bottom, Y-mirrored)
# tiles are the physical problem class -- if their PG pins strap, VDD>0 AND
# VSS>0 here.
foreach t $QTILES {
    lassign $t inst tx ty orient face
    set bb [inst_bbox $inst]
    if {$bb eq {}} { pgputs $fh "tile $inst : INSTANCE NOT FOUND"; continue }
    pgputs $fh "tile $inst ($orient,$face) bbox=$bb : VDD sWires=[swires_over VDD $bb]  VSS sWires=[swires_over VSS $bb]"
}
foreach inst {mcu0/shbank0 mcu0/shbank1 mcu0/shbank2 mcu0/shbank3 mcu0/npuram0 mcu0/rom0 mcu0/por mcu0/dco0 mcu0/dco1 mcu0/irq_gf0 mcu0/irq_gf1 mcu0/irq_gf2 mcu0/irq_gf3} {
    set bb [inst_bbox $inst]
    if {$bb eq {}} { pgputs $fh "macro $inst : NOT FOUND"; continue }
    pgputs $fh "macro $inst bbox=$bb : VDD sWires=[swires_over VDD $bb] VSS sWires=[swires_over VSS $bb]"
}
close $fh
puts "### UNL STATUS ### : PG verification written to $REPORT_DIR/$BASENAME.pgcheck.rpt"

verifyConnectivity \
    -nets {VDD VSS} \
    -type special \
    -error 100000 \
    -report $REPORT_DIR/$BASENAME.verifyConnectivity.pg.rpt

# Parse the special-net opens and test whether any lie inside the FLIPPED
# bottom-tile bboxes (hart2/hart3) or the macro bboxes -> authoritative
# "the PG pin is physically connected" evidence.
set fh2 [open $REPORT_DIR/$BASENAME.pgcheck.rpt a]
set checkboxes {}
foreach t $QTILES { lassign $t inst tx ty orient face; lappend checkboxes [list $inst [inst_bbox $inst]] }
foreach inst {mcu0/shbank0 mcu0/npuram0 mcu0/rom0 mcu0/irq_gf3} { lappend checkboxes [list $inst [inst_bbox $inst]] }
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
# isolate REAL shorts from the transient tile-finger-pin-vs-window-blk class.
# PLACE blockages stay. Re-created after.
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
# Reserve M7/M8 for power during signal routing -- FULL DIE frame (keeps signal
# routing off M7/M8 over the pad band too).
createRouteBlk -box $DIE_LLX $DIE_LLY $DIE_URX $DIE_URY -layer 7
createRouteBlk -box $DIE_LLX $DIE_LLY $DIE_URX $DIE_URY -layer 8

################################################################################
# Save the floorplan+PG DB + a DEF for external PG inspection.
################################################################################
__wq_guard "floorplan_pg" 0
saveDesign $DATABASE_DIR/$BASENAME.floorplan_pg.innovus -def -netlist
defOut -floorplan -routing $OUTPUT_DIR/$BASENAME.floorplan_pg.def
puts "### UNL STATUS ### : saved DB + DEF (floorplan+PG stage)"

################################################################################
# ======================= PLACE / CTS / ROUTE / SIGNOFF ======================
# One continuous session (a saved-DB restore FATALs in tapeOut check mode
# against the timing-less pad cells -- CQ4/A7 finding). Gated by RUN_PNR so a
# floorplan-only reproduction is still possible (innovus ... -files <this> with
# RUN_PNR pre-set to 0). Entering here the route blockages present = seal band
# + 4 analog windows + die-frame M7 + die-frame M8.
################################################################################
if {![info exists RUN_PNR]} { set RUN_PNR 1 }
if {$RUN_PNR} {
    printStatus "entering placement"

    # WQ-DELTA 13: spurious clock-gating checks on the TIMER ClockMuxGlitchFree
    # select legs. Gate names are genus-mapped and netlist-dependent, so the
    # catch-skip keeps the flow alive (the disable only suppresses a false
    # gating-check; it never gates route/verify/sim).
    # WOUND NOTE: `g11710` DOES exist in genus/out/MCU_WOUND_hier.genus.v (3
    # hits), one of them inside module TIMER_1 -- so ONE of the two entries
    # below should resolve on this netlist and the other will print SKIPPED.
    # (The Stage-I chip_top_wound header says "0 hits"; that was measured on
    # the FLAT genus/out/MCU_WOUND.genus.v, a different mapping.) After the
    # first postRoute hold signoff, read the real violating endpoint out of
    # $BASENAME.report_timing.hold.signoff.rpt and replace this list.
    set_interactive_constraint_modes [all_constraint_modes -active]
    foreach g {mcu0/timer0/g11710 mcu0/timer1/g11710} {
        if {[catch {set_disable_clock_gating_check $g} r]} {
            puts "### UNL WARN ### : gating-check disable SKIPPED for $g: $r"
        } else {
            puts "### UNL STATUS ### : gating-check disabled on $g"
        }
    }
    set_interactive_constraint_modes {}

    ############################################################################
    # WQ-DELTA 9: TRNG0 ring-oscillator ensemble preserve gate.
    #
    # The wound SoC carries a REAL ring-oscillator ensemble (TrngRoEnsemble
    # `u_ro`): 8 rings of prime stage counts {13,17,19,23,29,31,37,41} = 202
    # preserved inverters + 8 NAND enables = 210 cells that are DELIBERATE
    # COMBINATIONAL LOOPS. The SDC carries set_dont_touch, but that is a
    # TIMING-side attribute; the DB attribute is what stops place_opt / ccopt /
    # optDesign resizing, cloning or deleting a ring stage -- and THIS IS A FLAT
    # RUN, so every one of those engines sees the rings. Set it the
    # hart_tile.innovus.tcl way: `dbSet <inst>.dontTouch true`, NOT setAttribute
    # (-dont_touch is not an option in 20.12, IMPTCM-48).
    #
    # PATTERN NOTE (delta vs the Stage-I chip_top_wound flow): in
    # genus/out/MCU_WOUND_hier.genus.v the ensemble is instantiated at MCU level
    # as a SIBLING of trng0 (`TrngRoEnsemble u_ro`, inside `module MCU`), NOT
    # inside trng0 -- so the correct chip path is mcu0/u_ro/*. That pattern is
    # tried FIRST here; the Stage-I patterns are kept after it as a union so a
    # genus regroup cannot break the gate. FATAL only on a ZERO total.
    ############################################################################
    set RO_SEEN [list]
    set RO_N 0
    foreach __pat {mcu0/u_ro/* mcu0/trng0/u_ro/* mcu0/*u_ro/* mcu0/*u_ro*} {
        foreach __ri [dbGet -p top.insts.name $__pat -e] {
            if {$__ri eq "0x0" || $__ri eq ""} { continue }
            if {[lsearch -exact $RO_SEEN $__ri] >= 0} { continue }
            lappend RO_SEEN $__ri
            dbSet $__ri.dontTouch true
            incr RO_N
        }
    }
    puts "### UNL STATUS ### : TRNG RO preserve -- dontTouch set on $RO_N u_ro instances (want >= 210)"
    if {$RO_N == 0} {
        puts "FATAL (TRNG RO): no u_ro instances found under mcu0 -- the ring ensemble is absent or renamed."
        exit 1
    }
    if {$RO_N < 210} {
        puts "WARNING (TRNG RO): only $RO_N ring cells found (expect 202 inverters + 8 NAND enables = 210) -- verify against the genus post-map census before trusting entropy."
    }

    addWellTap \
        -cell FILLTIE2A10TH \
        -cellInterval 24 \
        -fixedGap \
        -checkerBoard \
        -prefix WELLTAP

    place_opt_design
    printStatus "placement done"
    __wq_guard "place" 0
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
    # WQ-DELTA 11: full report_power (leakage + dynamic, statistical activity)
    # beside the leakage-only report optDesign writes implicitly. BASENAME-
    # prefixed so no other chip_top* flow can clobber it.
    # Consumed by tools/python/gen_power_dashboard.py.
    catch {report_power -outfile $REPORT_DIR/${BASENAME}_postCTS_full.power}
    timeDesign -postCTS -expandedViews -outDir $REPORT_DIR/$BASENAME.timeDesign.postcts
    report_ccopt_clock_trees -file $REPORT_DIR/$BASENAME.report_ccopt_clock_trees.postcts
    report_ccopt_skew_groups -file $REPORT_DIR/$BASENAME.report_ccopt_skew_groups.postcts
    printStatus "CTS done"

    ############################################################################
    # Signal routing
    ############################################################################
    printStatus "running nanoroute"
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
    # WQ-DELTA 11: full post-route power (see the postCTS note)
    catch {report_power -outfile $REPORT_DIR/${BASENAME}_postRoute_full.power}

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
    # seal band (C0/CQ5 precedent). Do NOT restore the analog-window ROUTE
    # blocks: the tiles' redundant PG finger pins sit under the notch windows by
    # construction, so a restored window route-block makes verifyGeometry report
    # them as "SHORT: Pin vs Routing Blockage" (the ~244 transient class). The
    # window HARD PLACE blockages survive deleteAllRouteBlks (only route blks are
    # removed) so the notch stays cell-free, and nothing was ever routed into the
    # window (the route block was present through nanoroute).
    seal_keepouts
    addFiller

    ############################################################################
    # Signoff checks + reports
    ############################################################################
    printStatus "verifyConnectivity (signoff)"
    verifyConnectivity \
        -error 100000 \
        -connectPadSpecialPorts \
        -report $REPORT_DIR/$BASENAME.verifyConnectivity.signoff.rpt

    printStatus "verifyGeometry (signoff)"
    verifyGeometry \
        -antenna \
        -report $REPORT_DIR/$BASENAME.verifyGeometry.signoff.rpt

    setDelayCalMode -SIAware false
    setAnalysisMode -analysisType onChipVariation -cppr both
    printStatus "timeDesign signoff"
    # NB the flow's `timeDesign -si -signoff` Quantus extraction is BROKEN
    # install-wide (EXTGRMP-341 + qrc segfault, silently continued) -- the
    # numbers it prints are postRoute-TQuantus state. Compare within one view,
    # never across cuts. Replicated as-is, deliberately not "fixed" (G1/G2).
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

    reportGateCount -level 2 -outfile $REPORT_DIR/$BASENAME.reportGateCount.signoff.rpt
    summaryReport   -noHtml   -outfile $REPORT_DIR/$BASENAME.summaryReport.signoff.rpt

    # Reset tapeOut check mode BEFORE saving so the routed DB restores cleanly
    # (the floorplan_pg DB carried -tapeOut true and FATALed on restore -- CQ4).
    setCheckMode -tapeOut false
    __wq_guard "signoff" 1
    saveDesign $DATABASE_DIR/$BASENAME.signoff.innovus -def -netlist -rc -tcon

    ############################################################################
    # WQ-DELTA 12: output files.
    #
    # MERGE LIST -- DO NOT ADD out/MCU_WOUND.gds2 (or any assembly GDS) HERE.
    # This is a FLAT run: the whole MCU_WOUND hierarchy is placed and routed IN
    # this design, so its geometry is native to the MCU_castalia struct.
    # The only foreign geometry is the hardened tile (a LEF macro here) and the
    # tphn pads (LEF-only cells). Merging a block GDS would inject a duplicate
    # `MCU` struct plus a second, differently-seeded MCU_VIA* family -- exactly
    # the PG4 same-name struct-hijack class the signoff strmin cellMap exists to
    # prevent. Identical to the DP / C0 / Argus / quad / wound chip flows, all
    # of which merge tile + pads only.
    ############################################################################
    streamOut \
        $OUTPUT_DIR/$BASENAME.gds2 \
        -libName WorkLib \
        -structureName $DESIGN_NAME \
        -stripes 1 \
        -units 1000 \
        -mode ALL \
        -merge [list ../hart_tile/out/hart_tile.gds2 \
                     /opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/gds/tphn65gpgv2od3_sl_210a/mt_2/8lm/tphn65gpgv2od3_sl.gds] \
        -mapFile ../shared/innovus2gds.map

    printStatus "writing SDF (top level)"
    write_sdf $OUTPUT_DIR/$BASENAME.sdf

    printStatus "writing verilog for Xcelium (top level; hart_tile as leaf refs)"
    saveNetlist \
        $OUTPUT_DIR/$BASENAME.xsim.v \
        -excludeCellInst ANTENNA2A10TH

    # Second guard: addFiller / streamOut / saveNetlist ran since the last one.
    __wq_guard "final" 1
    saveDesign $DATABASE_DIR/$BASENAME.final.innovus -def -netlist -rc -tcon

    puts "### UNL STATUS ### : P&R complete -- routed DB + GDS + SDF + xsim netlist saved"
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
printStatus "MCU_castalia (wound-patch SoC on the quad floorplan, LQFP-100) complete"
exit
