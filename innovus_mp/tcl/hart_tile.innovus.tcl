################################################################################
# Innovus script -- hart_tile TILE HARDEN (M14 physical flow; M16 U-shape rework)
#
# Derived from the frozen Myshkin ~/vestarv/innovus/tcl/MCU.innovus.tcl, cut
# down to a single-tile block harden and made BATCH-SAFE (no suspend, no GUI
# refresh calls). One hart_tile = vesta core + adddec + one sram1p16k TCM,
# with the M13 depth-1 registered boundary. All four MCU_MP hart instances
# place THIS one hardened block 4x at top level.
#
# Floorplan: 'U'-SHAPED rectilinear die (setObjFPlanPolygon). The base of the
# U holds the near-square AREA-OPTIMIZED mux-8 sram1p16k TCM (319.65 x
# 383.085, bottom-left corner) plus all the tile logic; the top-center NOTCH
# is a keep-out reserved for a per-tile analog potentiostat signal chain,
# dropped in at Virtuoso chip assembly. Notch budget (educated guess, 65nm):
#   potentiostat control amp + electrode drivers   ~100 x 150
#   TIA + multi-decade current-mirror gain ranging ~200 x 150
#   bias generators + DAC arrays (BIAS_DB*/ADJ)    ~150 x 150
#   SAR ADC (10b) + dsADC front half               ~250 x 250
#   guard rings / decap / analog routing margin    remainder
#   => 500 x 450 um = 0.225 mm^2 cutout (M17: deepened +100 um for a roomier
#      potentiostat drop-in; SARADC/AFE shared peripherals are gone entirely,
#      so NO digital signal ever leaves for this window -- it is pure analog
#      reserve, wired only at Virtuoso chip assembly).
# The two fingers of the U (80 um wide each) exist to close the tile power
# ring around the notch -- ring band = offset 4 + 2x(width 10) + spacing 4 =
# 28 um per boundary, leaving a ~24 um tap/decap column per finger. They are
# deliberately no wider: their only other job is abutting the analog block.
#
# Tile outline (die coords, 660 x 1050 bbox):
#   (0,0)-(660,0)-(660,1050)-(580,1050)-(580,600)-(80,600)-(80,1050)-(0,1050)
#
# All tile pins on the BOTTOM edge (M4): at Castalia top level the four
# tiles sit in a row at the TOP of the chip (notches opening onto the
# analog pad edge), control plane below them.
#
# Outputs (out/): hart_tile.{gds2,sdf,xsim.v,lef} + hart_tile.ilm/ (ILM) and
# hart_tile.etm_{ss,ff}.lib (per-corner ETM, both-views-active recipe --
# these feed viewdefinition_top.tcl at the assembly level).
################################################################################

source tcl/constants.tcl
source $SCRIPT_DIR/procedures.tcl

set DESIGN_NAME hart_tile

# U-shape geometry (M17: tile grown taller). BASE_H sizes the row budget:
# base = 660x600 = 396k um2 minus the halo'd TCM (~125k) = ~271k um2 of rows
# for ~66k um2 of std cells -- the base was only ~25% utilised at 500 tall, so
# the +100 um digital extension is pure breathing room (easier place/route).
set DESIGN_WIDTH  660
set DESIGN_HEIGHT 1050
set NOTCH_W       500
set NOTCH_D       450
set FINGER_W      80
set BASE_H        [expr {$DESIGN_HEIGHT - $NOTCH_D}]

# Power ring / stripe geometry (Myshkin values).
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
# Design import and setup
################################################################################
set init_verilog             "$GENUS_DIR/out/$DESIGN_NAME.genus.v"
set init_top_cell            "$DESIGN_NAME"
set init_pwr_net             "VDD"
set init_gnd_net             "VSS"
set init_mmmc_file           "$SCRIPT_DIR/viewdefinition_tile.tcl"

set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10-pmk/lef/tsmc65hvt_adv10pmk_macro.lef \
					$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef"

set init_design_uniquify 1
init_design

################################################################################
# M17 power intent: the tile CPF (PD_GATED default/shutoff=pd_sleep + PD_AO
# for the ports/iso cells; VDD = always-on, VDD_SW = the switched follow-pin
# net produced by the HEADBUF header fabric). Genus already INSERTED the
# A2ISO clamps (iso_* instances) — Innovus re-reads the same intent for the
# domain/net/switch data and must RECOGNIZE the existing cells, not
# re-insert.
################################################################################
read_power_intent -cpf ../cpf/hart_tile.cpf
commit_power_intent
printStatus "Power intent committed (PD_GATED/PD_AO, switched net VDD_SW)"

setDesignMode -process 65 -flowEffort standard -powerEffort low
printStatus "Preparing 8 CPU cores..."
setMultiCpuUsage -acquireLicense 8 -localCpu 8

# M17: NO FILLTIE fillers — a rail-tied well tap inside a gated row
# back-feeds the dead VDD_SW rail through the n-well (see the addWellTap
# note). Well-tap duty is carried entirely by the FILLBIAS addWellTap pass;
# fillers are the plain (tapless) FILL cells only.
setFillerMode \
    -corePrefix FILLER \
    -core {FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH}

setAnalysisMode -analysisType onChipVariation -cppr both

# M17 domain-aware global nets. Follow-pin rails: PD_GATED rows carry the
# SWITCHED net VDD_SW; the PD_AO band carries always-on VDD. ram0 (the TCM)
# stays in PD_GATED logically but its VDD pin ties to the ALWAYS-ON net —
# it self-gates through its native PGEN (pd_sleep is mirrored onto tcm_pgen
# at MCU level), so it needs no share of the switch fabric. Secondary pins:
# every pmk VDDG (HEADBUF supply-in, GPG always-on buffers) ties to VDD;
# the FILLBIAS well taps bias the gated region's wells from the AO rails
# (VNW->VDD, VPW->VSS) so a sleeping row's n-well never back-feeds the dead
# VDD_SW rail through a rail-tied tap (the FILLTIE hazard).
clearGlobalNets
# NOTE -powerDomain is a SCOPE and cannot combine with -inst (IMPSYC-957)
globalNetConnect VDD_SW -type pgpin -pin VDD  -powerDomain PD_GATED -autoTie -verbose
globalNetConnect VDD    -type pgpin -pin VDD  -powerDomain PD_AO    -verbose
globalNetConnect VDD    -type pgpin -pin VDD  -singleInstance ram0 -override -verbose
globalNetConnect VSS    -type pgpin -pin VSS  -inst * -module {} -autoTie -verbose
# (the pmk secondary pins — VDDG/VNW/VPW — are connected AFTER the switch
# and well-tap cells exist; a rule with zero matching pins is IMPDB-1221)

################################################################################
# Floorplan: U-shaped rectilinear die -- rect first, then carve the notch.
# TCM macro in the bottom-left of the base, pins on the bottom edge.
################################################################################
floorPlan \
    -site TSMC65ADV10TSITE \
    -s $CORE_WIDTH $CORE_HEIGHT $CORE_SPACING $CORE_SPACING $CORE_SPACING $CORE_SPACING

# Carve the top-center analog notch: 8-vertex U polygon (die coords).
# Without EnableRectilinearDesign, setObjFPlanPolygon on the top cell is
# REJECTED (IMPSYT-40516) and the die silently stays rectangular.
setPreference EnableRectilinearDesign 1
set NOTCH_X0 $FINGER_W
set NOTCH_X1 [expr {$DESIGN_WIDTH - $FINGER_W}]
set U_POLY "0 0 $DESIGN_WIDTH 0 $DESIGN_WIDTH $DESIGN_HEIGHT $NOTCH_X1 $DESIGN_HEIGHT $NOTCH_X1 $BASE_H $NOTCH_X0 $BASE_H $NOTCH_X0 $DESIGN_HEIGHT 0 $DESIGN_HEIGHT"
eval "setObjFPlanPolygon Cell $DESIGN_NAME $U_POLY"
initCoreRow
# Defensive: no rows may survive inside the notch (analog keep-out).
cutRow -area [list $NOTCH_X0 $BASE_H $NOTCH_X1 $DESIGN_HEIGHT]
printStatus "Carved U-shape notch ($NOTCH_W x $NOTCH_D) at top center"

set SRAM16K_WIDTH		319.650
set SRAM16K_HEIGHT		383.085

# M17: TCM centered in the tile's X (was jammed at x=10). Sits at the base
# bottom (y=10, MX); the notch floor is at BASE_H=600 so there is no overlap.
set TCM_X	[expr {($DESIGN_WIDTH - $SRAM16K_WIDTH) / 2.0}]
set TCM_Y	10
placeInstance ram0 $TCM_X $TCM_Y MX
addHaloToBlock \
    [expr {$STD_CELL_HEIGHT * 1}] \
    [expr {$STD_CELL_HEIGHT * 1}] \
    [expr {$STD_CELL_HEIGHT * 1}] \
    [expr {$STD_CELL_HEIGHT * 1}] \
    ram0
cutRow
printStatus "Placed TCM macro"

# All tile pins spread along the BOTTOM edge on M4 (vertical-preferred):
# the Castalia floorplan puts the tile row at the chip top, control plane
# below, so every digital connection leaves through the base of the U.
set ALL_PINS [dbGet top.terms.name]
puts "Assigning [llength $ALL_PINS] pins to the bottom edge"
editPin -pin $ALL_PINS -side Bottom -layer 4 -spreadType side -spacing 1 -fixOverlap 1
printStatus "Placed tile pins"

# M17: NO PD_AO fence — PD_AO holds only the boundary PORTS (isolation is
# explicit RTL AND-clamps on the MCU side of the boundary, and the TCM
# macro is AO by pin connection). Every row in the tile is PD_GATED =
# VDD_SW rails; the always-on presence inside the tile is just the VDD
# ring/stripe grid, the switches' VDDG pins, and the FILLBIAS well bias.

################################################################################
# Power: rectilinear ring following the U boundary (incl. both fingers) +
# stripes on M7/M8 (reserved for power via route blockages)
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

# No keep-out blockage needed for the notch: it is OUTSIDE the rectilinear
# die boundary, so place/route/stripe engines cannot touch it (a routeBlk
# there is even rejected -- IMPFP-184, "cut against design boundary").

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

################################################################################
# M17: the MTCMOS header fabric. HEADBUF16M columns inside PD_GATED — only
# the HEADBUF cells have SLEEPOUT and can daisy-chain (plain HEADs cannot,
# M17 recon), and the chain IS the rush-current stagger (~60-90 ps/stage;
# the databook has no explicit inrush rule — pwr_ctrl's T_RAIL=256 mclk
# wake settle covers the whole chain with orders of magnitude to spare).
# VDDG pin (always-on IN) strapped to the VDD grid by the secondary sroute
# below; VDD pin (switched OUT) abuts the row rails = VDD_SW.
################################################################################
printStatus "Inserting MTCMOS header switch columns (HEADBUF16MA10TH)"
# -area is REQUIRED here: PD_GATED is the DEFAULT domain (no fence box), and
# without an explicit area the column engine dies on the empty domain box
# ("can't use non-numeric string as operand of *" — M17 lesson). Columns
# every 80 um with a switch in EVERY row: VDD_SW is a follow-pin-only net
# (no stripe grid), so a row with no switch has a FLOATING rail — IMPPSO-306
# flagged exactly that under -skipRows (the M16 floating-rail lesson, power-
# switch edition). ~1000 HEADBUF16 ≈ 8.5k um² in a 271k um² row budget.
# -skipRows is REQUIRED (omitting it is the "non-numeric operand" abort —
# the option has no sane default in this build); 0 = a switch in every row.
addPowerSwitch -column -powerDomain PD_GATED \
	-globalSwitchCellName {HEADBUF16MA10TH} \
	-area [list $CORE_SPACING $CORE_SPACING [expr {$DESIGN_WIDTH - $CORE_SPACING}] [expr {$DESIGN_HEIGHT - $CORE_SPACING}]] \
	-leftOffset 30 \
	-horizontalPitch 80 \
	-skipRows 0 \
	-checkerBoard true \
	-enableNetIn pd_sleep \
	-enableNetOut pd_sleep_chain_out

# addPowerSwitch FAILS SOFT (IMPPSO-109 and the script rolls on) — a
# zero-switch tile would sail to signoff with an unpowered VDD_SW net and
# only die at the assembly gate sim. Refuse to continue without a fabric.
set NSW [llength [dbGet -p top.insts.cell.name HEADBUF16MA10TH]]
puts "### UNL STATUS ### : $NSW HEADBUF16MA10TH power switches inserted"
if {$NSW == 0} {
	puts "FATAL (M17): addPowerSwitch inserted ZERO switches — aborting"
	exit 1
}

# M17: well taps move UP here (they lived in the placement section as
# FILLTIE) so their bias pins exist before the secondary sroute. FILLBIAS
# instead of FILLTIE: a rail-tied tap in a gated row ties the n-well — held
# at VDD by the header cells' body ties — to the dead VDD_SW rail and
# back-feeds it through the well, defeating the shutoff.
addWellTap \
    -cell FILLBIASA10TH \
    -cellInterval 24 \
    -fixedGap \
    -checkerBoard \
    -prefix WELLTAP

# pmk secondary pins, now that the switch + tap instances exist. NOTE
# -type net, NOT pgpin: the pmk LEF gives VDDG/VNW/VPW no USE power/ground
# class (plain INOUT signal pins), so a pgpin rule matches nothing
# (IMPDB-1221 — M17 lesson).
globalNetConnect VDD -type net -pin VDDG -inst * -module {} -verbose
globalNetConnect VDD -type net -pin VNW  -inst * -module {} -verbose
globalNetConnect VSS -type net -pin VPW  -inst * -module {} -verbose

printStatus "Routing power rails"
setSrouteMode -corePinMaxViaScale "100 10"
# M17: three follow-pin nets now — VDD_SW rails in PD_GATED rows, VDD rails
# in the PD_AO band, VSS everywhere. The M7/M8 stripe grid stays VDD/VSS
# (always-on): VDD stripes drop onto VDD rails and the switches' VDDG pins
# ONLY — the VDD_SW rails are fed exclusively by the switch outputs.
sroute \
	-nets { VSS VDD VDD_SW } \
	-allowLayerChange 0 \
	-allowJogging 0 \
	-connect corePin \
    -corePinWidth 0.3

# M17: secondary PG pins — HEADBUF/GPG VDDG and the FILLBIAS well-bias pins
# (VNW->VDD, VPW->VSS; the taps come from addWellTap below).
printStatus "Routing secondary power pins (VDDG / VNW / VPW)"
sroute \
	-nets { VDD VSS } \
	-connect { secondaryPowerPin } \
	-secondaryPinNet { VDD VSS } \
	-allowLayerChange 1 \
	-allowJogging 1 \
	-layerChangeRange { M1(1) M4(4) }

verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.preplace.rpt
fixVia -short
fixVia -minCut
fixVia -minStep

# Reserve M7/M8 for power during signal routing.
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -layer 7
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -layer 8

################################################################################
# Placement
################################################################################
# (M17: the addWellTap pass moved UP before the power routing — FILLBIAS
# taps must exist when the secondary sroute runs. See the power section.)

place_opt_design
printStatus "Placement done"

################################################################################
# Clock tree synthesis (mclk from the clk port; clk_cpu is a generated clock
# through vesta's ClkGate -- ccopt traces it)
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
timeDesign -postCTS -expandedViews -outDir $REPORT_DIR/$DESIGN_NAME.timeDesign.postcts
report_ccopt_clock_trees -file $REPORT_DIR/$DESIGN_NAME.report_ccopt_clock_trees.postcts
report_ccopt_skew_groups -file $REPORT_DIR/$DESIGN_NAME.report_ccopt_skew_groups.postcts
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
    -drouteAntennaEcoListFile $REPORT_DIR/$DESIGN_NAME.routeDesign.diodes.txt \
    -dbSkipAnalog true \
    -drouteEndIteration default
routeDesign

optDesign -postRoute -setup -hold

verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.postroute.rpt
ecoRoute -fix_drc
verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.postroute.rpt

deleteAllRouteBlks
addFiller

################################################################################
# Signoff checks + reports
################################################################################
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

setDelayCalMode -SIAware false
setAnalysisMode -analysisType onChipVariation -cppr both
printStatus "timeDesign signoff"
timeDesign \
    -si \
    -signoff \
    -outdir $REPORT_DIR/$DESIGN_NAME.timeDesign.signoff.rpt

report_clock_timing \
    -type skew \
    -nworst 10 > $REPORT_DIR/$DESIGN_NAME.report_clock_timing.skew.signoff.rpt

setAnalysisMode -checkType hold -skew true
report_timing > $REPORT_DIR/$DESIGN_NAME.report_timing.hold.signoff.rpt
setAnalysisMode -checkType setup -skew true
report_timing > $REPORT_DIR/$DESIGN_NAME.report_timing.setup.signoff.rpt

reportGateCount \
    -level 2 \
    -outfile $REPORT_DIR/$DESIGN_NAME.reportGateCount.signoff.rpt
summaryReport \
    -noHtml \
    -outfile $REPORT_DIR/$DESIGN_NAME.summaryReport.signoff.rpt

saveDesign $DATABASE_DIR/$DESIGN_NAME.signoff.innovus -def -netlist -rc -tcon

################################################################################
# Output files: GDS, SDF, sim netlist, ILM, LEF abstract, per-corner ETMs
################################################################################
streamOut \
    $OUTPUT_DIR/$DESIGN_NAME.gds2 \
    -libName WorkLib \
    -structureName $DESIGN_NAME \
    -stripes 1 \
    -units 1000 \
    -mode ALL \
    -mapFile $INPUT_DIR/innovus2gds.map

printStatus "Writing SDF file"
write_sdf $OUTPUT_DIR/$DESIGN_NAME.sdf

printStatus "Writing verilog for Xcelium"
saveNetlist \
    $OUTPUT_DIR/$DESIGN_NAME.xsim.v \
    -excludeCellInst ANTENNA2A10TH

# ILM -- interface logic + clock interface with real post-route timing
# (secondary abstraction; the assembly flow of record is ETM+LEF).
printStatus "Writing ILM"
createInterfaceLogic \
    -hold \
    -dir $OUTPUT_DIR/$DESIGN_NAME.ilm

# LEF abstract -- pins + blockages for top-level placement/routing. The tile
# uses M7/M8 for its own power ring/stripes, so the abstract exposes them as
# PG pins (top-level stripes via down onto the tile ring).
printStatus "Writing LEF abstract"
lefOut \
    -StripePin \
    -PGpinLayers 7 8 \
    -specifyTopLayer 8 \
    $OUTPUT_DIR/$DESIGN_NAME.lef

# Per-corner ETMs (.lib) -- THE M14 recipe: do_extract_model characterizes
# only the corner whose view is active for BOTH setup and hold, so force
# each corner in turn. These feed viewdefinition_top.tcl (etm_ss in the
# max+typ library sets, etm_ff in min).
printStatus "Extracting per-corner ETMs (both-views-active recipe)"
set_analysis_view -setup [list setup_analysis_view] -hold [list setup_analysis_view]
# NOTE: -view is REQUIRED in MMMC (TAMODEL-313 otherwise -- and innovus only
# PRINTS the error without throwing, so a missing -view fails SILENTLY).
if {[catch {do_extract_model -view setup_analysis_view $OUTPUT_DIR/$DESIGN_NAME.etm_ss.lib} etm_err]} {
	puts "ETM ss extraction FAILED: $etm_err"
} else {
	puts "ETM written to $OUTPUT_DIR/$DESIGN_NAME.etm_ss.lib"
}
set_analysis_view -setup [list hold_analysis_view] -hold [list hold_analysis_view]
if {[catch {do_extract_model -view hold_analysis_view $OUTPUT_DIR/$DESIGN_NAME.etm_ff.lib} etm_err]} {
	puts "ETM ff extraction FAILED: $etm_err"
} else {
	puts "ETM written to $OUTPUT_DIR/$DESIGN_NAME.etm_ff.lib"
}
set_analysis_view -setup [list setup_analysis_view] -hold [list hold_analysis_view]

saveDesign $DATABASE_DIR/$DESIGN_NAME.final.innovus -def -netlist -rc -tcon
toc
printStatus "hart_tile harden complete"
exit
