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

# PG4/PG2-F1 (2026-07-10): the pmk LEF is a patched LOCAL copy. The 2007 kit
# LEF gives the 58 secondary pins (VDDG/VSSG/VNW/VPW) no USE POWER/GROUND
# class, so `globalNetConnect -type pgpin` matches nothing (IMPDB-1221),
# the M17 `-type net` workaround never connected a pin in ANY run
# (IMPDB-1223 -- wrong verb), and `sroute -connect secondaryPowerPin`
# routed nothing (IMPSR-503): VDD_SW shipped SOURCELESS in every harden
# M17..PG3 (dead chip as-built). dbSet term.pgType is rejected
# (IMPDBTCL-216) -- the LEF itself must carry the class. The copy is
# byte-identical to the kit except the 58 added USE lines (+ header).
set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					../std_cells/lef/tsmc65hvt_adv10pmk_macro.USEfix.lef \
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
# VDD_SW rail through a rail-tied tap (the FILLTIE hazard). PG4 NOTE: the
# FILLBIAS network IS the only well bias — HEADBUF16's CDL bulks tie to
# VNW/VPW (not VDDG), and headers expose no VNW/VPW LEF pin; the old claim
# that "the header cells' body ties hold the well at VDD" was wrong.
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
# (M17b: the two switchless-row placement blockages live AFTER the power-
# switch/well-tap passes, NOT here — a blockage visible to addPowerSwitch
# shifts its checkerboard phase and the uncovered rows MOVE. See below.)
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
# PG3 M7.S.4 fix, part 1 of 2: FIRST vertical stripe pair only, one pitch
# left-shifted by 0.5 um (VDD 50.5-55.5, VSS 59.5-64.5; the VSS stripe then
# clears the U-notch inner VDD ring leg at x=66 by the required 1.5 um).
# -start_offset semantics flip between core-relative and area-relative
# depending on -area, so the block is SELF-CHECKING: place, probe the DB,
# retry the other convention, and hard-exit unless column 1 sits exactly at
# 50.5/59.5 (acceptance-gate style -- a silently mis-placed stripe is worse
# than an aborted run). See the M7.S.4 lesson block below for the history.
proc pg3_col1_count {lo hi} {
    set n 0
    foreach sw [dbGet -p2 top.nets.sWires.layer.name M7] {
        set llx [dbGet $sw.box_llx]
        if {$llx >= $lo && $llx <= $hi} { incr n }
    }
    return $n
}
addStripe \
	-layer M7 \
	-nets {VDD VSS} \
	-direction vertical \
	-start_from bottom \
	-set_to_set_distance $POWER_STRIPE_SET_TO_SET \
	-spacing $POWER_STRIPE_PATH_SPACING \
	-width $POWER_STRIPE_PATH_WIDTH \
	-block_ring_bottom_layer_limit M1 \
	-start_offset 5.5 \
	-stop_offset $POWER_STRIPE_PATH_SPACING \
	-area [list 45.0 0.0 70.0 569.75]
# NB probe window must EXCLUDE the notch ring legs (llx 52 and 66) -- only
# the new stripe pair's own positions count as success.
if {[pg3_col1_count 50.0 51.2] == 0} {
    printStatus "PG3 M7.S.4: area-relative start_offset placed nothing; retrying core-relative (49.5)"
    addStripe \
	-layer M7 \
	-nets {VDD VSS} \
	-direction vertical \
	-start_from bottom \
	-set_to_set_distance $POWER_STRIPE_SET_TO_SET \
	-spacing $POWER_STRIPE_PATH_SPACING \
	-width $POWER_STRIPE_PATH_WIDTH \
	-block_ring_bottom_layer_limit M1 \
	-start_offset [expr {$POWER_STRIPE_SET_TO_SET - 0.5}] \
	-stop_offset $POWER_STRIPE_PATH_SPACING \
	-area [list 45.0 0.0 70.0 569.75]
}
# NB >=1 not ==1: a stripe may come back SEGMENTED as several sWires at the
# same llx (the pair above returned 5 wires) -- ABSENCE is the failure mode.
if {[pg3_col1_count 50.4 50.6] < 1 || [pg3_col1_count 59.4 59.6] < 1} {
    puts "### UNL STATUS #### : PG3 M7.S.4 GATE FAILED -- column-1 stripes not at 50.5/59.5"
    exit 99
}

# PG3 M7.S.4 fix, part 2 of 2: the ORIGINAL full-grid pass, starting one
# pitch later so column 1 comes only from the shifted pass above.
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
	-start_offset [expr {$POWER_STRIPE_SET_TO_SET + 50.0}] \
	-stop_offset $POWER_STRIPE_PATH_SPACING

editTrim -all

# PG3 signoff-DRC fix (foundry deck M7.S.4, wide-metal union-projection
# spacing >= 1.5): the FIRST vertical VSS stripe (x 60-65) ends up only
# 1.0 um left of the U-notch ring's inner VDD leg (x 66-76, the left-finger
# band = 80 - offset 4 - width 10). The deck's SIZE-UNDEROVER derivation
# merges that stripe with the notch VSS leg (52-62, 2.25 um away) into ONE
# effective wide shape whose edge faces the VDD leg over its whole run ->
# spacing 1.0 < 1.5 fires. Innovus verifyGeometry can NEVER see this (the
# tech LEF has no union-projection rule) -- found by Calibre blockdrc (PG3).
# LESSONS (each variant tried and thrown out):
#  * shifting the WHOLE stripe grid is not safe: the right-finger mirror
#    (VSS ring leg 598-608 vs full-height VSS stripe 610-615, gap 2.0)
#    fails the same rule if the grid moves left by more than 0.5;
#  * manual surgery (editDelete + add_shape a narrower stripe) LOSES the
#    engine's stacked vias and cannot get them back -- editPowerVia no-ops
#    here (IMPSR-554: the tile's top ROUTING layer is M4, so its -top_layer
#    clamps below the PG layers) -> whole-die VSS opens + dangling wire at
#    the re-added stripe. Caught by the acceptance verifyConnectivity.
# Working form: let addStripe place the first column itself, 0.5 um left
# (VDD 50.5-55.5, VSS 59.5-64.5 -> 1.5 to the ring leg), by splitting the
# one addStripe into an -area pass for column 1 (start_offset 49.5) and the
# original pass starting one pitch later (start_offset +50). Engine-placed
# shapes keep engine-placed stacked vias -- nothing manual to re-stitch.

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
# switch edition). ~2000 HEADBUF16 ≈ 17k um² in a 271k um² row budget.
# -skipRows is REQUIRED (omitting it is the "non-numeric operand" abort —
# the option has no sane default in this build); 0 = a switch in every row.
# -checkerBoard true is LOAD-BEARING (M17b post-mortem, both directions):
#  * WITH it, the stagger leaves exactly two rows switchless — the bottom
#    row (1,1) and the right U-leg top row (581,1047). IMPPSO-306 warns, the
#    run rolls on, and place_opt parked 52 live cells (bnd_irq_* boundary
#    flops, hart_id inverters) on the dead VDD_SW rail. Those two rows are
#    now hard-blocked at floorplan time (see dead_row blockages above) so
#    they stay EMPTY — dead rail, nothing on it.
#  * WITHOUT it (full-density, switch in every row), the DRC drowns: ~1000
#    M1 pin-frame abutment shorts (FILLER/WELLTAP/HEADBUF pmk frames overlap
#    different-net M1 when vertically stacked in consecutive rows) + ~4500
#    IMPVFC-92/94 connectivity problems. Proven by three runs; the stagger
#    is exactly what keeps the pmk frames apart. NB the option is a bare
#    FLAG in this build: `-checkerBoard false` is the same non-numeric-
#    operand abort as a missing -skipRows.
# Acceptance for any future rerun: every IMPPSO-306 row must lie inside a
# dead_row blockage box.
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

# (M17b: the two switchless-row placement blockages live IMMEDIATELY BEFORE
# place_opt_design — see there. Not here: visible to sroute they suppress
# the blocked rows' follow-pin rails and strand the well-tap VDD frames.)

# pmk secondary pins, now that the switch + tap instances exist.
# PG4/PG2-F1 LESSON (this exact spot shipped a dead chip three times):
#  * `-type net` here was the M17 "lesson 6" workaround for IMPDB-1221 --
#    but -type net re-parents a NET and NEVER binds pins: it printed
#    IMPDB-1223 in every run while `catch` saw rc=0 (Innovus errors are
#    not tcl errors) and the flow sailed on with all 1027 header VDDG,
#    4 GPGBUF and 7072 FILLBIAS well-bias pins bound to NO net (PG2-F1).
#  * `-type pgpin` is the correct verb and works now BECAUSE the local
#    USEfix pmk LEF (see init_lef_file) gives these pins their USE class.
# The F1 acceptance gate right below fails the run if the binding ever
# silently regresses -- do NOT weaken it.
globalNetConnect VDD -type pgpin -pin VDDG -inst * -module {} -verbose
globalNetConnect VDD -type pgpin -pin VNW  -inst * -module {} -verbose
globalNetConnect VSS -type pgpin -pin VPW  -inst * -module {} -verbose

# PG4 NOTE on gating the LOGICAL binding: it CANNOT be checked here. GNC
# pin bindings live as rules until much later — instTerms/pgNets for PG
# pins are empty even across a save/restore at this point (bring-up
# proven: the rules had just connected 7078 VNW pins while every query
# form read empty). The VDDG rule reporting "0 new" is EXPECTED: the
# switch VDDG pins are claimed by addPowerSwitch itself (CPF
# create_power_switch_rule -external_power_net VDD, per-inst GNC calls in
# the log). The F1 gate is therefore GEOMETRIC, after the secondary
# sroute below — metal is the only truth available in-flow, and metal is
# what PG2-F1 was actually missing.

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
# PG4/PG2-F1: `-powerDomains PD_GATED` is REQUIRED — without a domain scope
# this pass exits IMPSR-503 in 0.2 s having routed NOTHING (trigger = the
# CPF power domains + switch cells; the run-9 "GPGBUF triggers 503"
# diagnosis was a misread — it fires with zero GPGBUFs present). Same form
# as the PG1 repeater pass below, which always carried the option.
printStatus "Routing secondary power pins (VDDG / VNW / VPW)"
sroute \
	-nets { VDD VSS } \
	-connect { secondaryPowerPin } \
	-secondaryPinNet { VDD VSS } \
	-allowLayerChange 1 \
	-allowJogging 1 \
	-layerChangeRange { M1(1) M4(4) } \
	-powerDomains PD_GATED

# PG4 F1 acceptance gate (PHYSICAL — catches the IMPDB-1221/1223 rule
# no-ops AND the IMPSR-503/1253 sroute no-ops in one place, because both
# end the same way: no metal on the secondary pins):
#  a) net VDD must hold >> the broken baseline of 50 sWires (ring +
#     stripes only, nothing below M6 = the PG2-F1 signature);
#  b) EVERY HEADBUF footprint must be touched by net-VDD geometry (the
#     VDDG supply-in strap), and EVERY FILLBIAS by net-VDD (VNW) plus
#     non-followpin net-VSS (VPW; followpin rails touch every cell
#     trivially and prove nothing). tile_audit.py --pgdump repeats this
#     check independently on the saved signoff DB.
set __f1_vdd_sw [llength [dbGet [dbGet -p top.nets.name VDD].sWires -e]]
set __f1_vss_sw [llength [dbGet [dbGet -p top.nets.name VSS].sWires -e]]
puts "### UNL STATUS ### : PG4 F1 gate a — VDD sWires=$__f1_vdd_sw VSS sWires=$__f1_vss_sw post-secondary-sroute (broken baseline: 50)"
if {$__f1_vdd_sw < 500} {
	puts "FATAL (PG4/F1): only $__f1_vdd_sw VDD sWires after the secondary sroute — the VDDG/VNW strap pass did nothing (IMPSR-503/1253 class). Aborting."
	exit 1
}
################################################################################
# PG4 FABRIC COMPLETION: the secondary sroute above only draws a tiny M1
# finger ON each secondary pin and stacks vias opportunistically where PG
# metal happens to cross overhead (bring-up finding on the gate-b fail DB:
# 4754 of 7078 FILLBIAS taps — and most headers — ended as FLOATING M1
# fingers; only cells under a stripe/ring got real stacks). The header
# columns (x=31+80k) were never aligned with the stripe grid (x=50.5+50k),
# so "sroute + stripes" alone can NEVER supply this fabric. Also: HEADBUF's
# CDL bulks tie to VNW/VPW (NOT VDDG — the M17 "headers' body ties hold the
# well" comment was wrong), and headers expose no VNW/VPW LEF pin, so ALL
# well bias flows through the FILLBIAS strap network. What completes it:
#  1. one narrow vertical M2 VDD strap per TAP column (x0+0.10..0.40, over
#     the VNW pin bars) and per HEADER column (x0+2.325..2.625, over a VDDG
#     comb bar) — addStripe with -stacked_via_bottom_layer M1 puts a VIA1
#     on EVERY pin under the strap and full VIA2..7 stacks at every M8-grid
#     crossing (probe-proven: 32/32 pins via'd in the test column).
#     PG4/F2 WARNING: those VIA1s DO NOT SURVIVE to the final DB/GDS (the
#     v22c signoff DB had none under 7 of 8 header columns; mechanism
#     unknown — CTS/opt/ECO era). The pin hookup of record is the PG4/F2
#     strap-PIN link repair at the post-route repair stage; this stage's
#     via coverage check only gates the STRAP placement itself. M2 is
#     legal here: both LEFs are M1-only inside cells, straps go in
#     pre-place, and 0.3 um per 24 um is ~1% of M2 tracks.
#  2. a 0.25-um M1 jumper per FILLBIAS VPW pin to the VSS rail 0.15 um away
#     (the pin reaches toward the rail by cell design; the "VDD" rail on the
#     other side is VDD_SW, so VNW can NOT use the same trick — hence M2).
# addStripe -start_offset is AREA-relative here: strap_llx = area_llx +
# start_offset (probe-proven twice). Self-checks gate every step; dead-row
# cells (bottom row y<3, right-leg top row) are SKIPPED so the M17b
# end-of-flow scrub still deletes them cleanly.
################################################################################
printStatus "PG4: completing the pmk secondary strap fabric (M2 columns + VPW jumpers)"
# minimal stripe mode: -reset clears the main grid's antenna trim (proven:
# trim=core_ring SHREDS any strap that cannot reach the M8 grid into
# per-pin fragments — the covered-column pathology of bring-up v4/v5).
setAddStripeMode -reset
setAddStripeMode \
    -stacked_via_top_layer M8 \
    -stacked_via_bottom_layer M1 \
    -extend_to_closest_target none

set __ram0_box [lindex [dbGet [dbGet -p top.insts.name ram0].box] 0]
foreach {__rmx0 __rmy0 __rmx1 __rmy1} $__ram0_box {}

proc pg4_has_svia {box wantnet} {
	foreach {bx0 by0 bx1 by1} $box {}
	foreach o [dbQuery -area [list [expr {$bx0 - 0.5}] [expr {$by0 - 0.5}] [expr {$bx1 + 0.5}] [expr {$by1 + 0.5}]] -objType sVia] {
		if {[dbGet -e $o.net.name] eq $wantnet} { return 1 }
	}
	return 0
}
proc pg4_dead_row {bx} {
	global DESIGN_WIDTH DESIGN_HEIGHT FINGER_W
	foreach {x0 y0 x1 y1} $bx {}
	if {$y0 < 3.0} { return 1 }
	if {$y1 > [expr {$DESIGN_HEIGHT - 3.0}] && $x0 >= [expr {$DESIGN_WIDTH - $FINGER_W}]} { return 1 }
	return 0
}

# collect strap columns: tap columns keyed by inst x (pins at x0+0.10..0.40),
# header columns (pins at x0+2.325..2.625)
array unset __colys
foreach __i [dbGet -p2 top.insts.cell.name FILLBIASA10TH] {
	set __bx [lindex [dbGet $__i.box] 0]
	if {[pg4_dead_row $__bx]} { continue }
	set __x [format %.2f [lindex $__bx 0]]
	lappend __colys(T$__x) [lindex $__bx 1]
}
foreach __i [dbGet -p2 top.insts.cell.name HEADBUF16MA10TH] {
	set __bx [lindex [dbGet $__i.box] 0]
	if {[pg4_dead_row $__bx]} { continue }
	set __x [format %.2f [lindex $__bx 0]]
	lappend __colys(H$__x) [lindex $__bx 1]
}
set __nstrap 0
set __nstrap_skip 0
set __skipped_runs {}
set __placed_runs {}
foreach __key [array names __colys] {
	set __x0 [string range $__key 1 end]
	if {[string index $__key 0] eq "T"} {
		set __sx [expr {$__x0 + 0.10}]
	} else {
		set __sx [expr {$__x0 + 2.325}]
	}
	# cluster the cell y's into runs (gap > 40 um starts a new run)
	set __ys [lsort -real $__colys($__key)]
	set __runs {}
	set __rs [lindex $__ys 0]; set __re $__rs
	foreach __y $__ys {
		if {[expr {$__y - $__re}] > 40.0} { lappend __runs [list $__rs $__re]; set __rs $__y }
		set __re $__y
	}
	lappend __runs [list $__rs $__re]
	foreach __run $__runs {
		foreach {__ry0 __ry1} $__run {}
		set __ay0 [expr {$__ry0 - 1.0}]
		set __ay1 [expr {$__ry1 + 3.0}]
		# never let a strap cross ram0 (M1-only cells are safe; the MACRO is not)
		if {$__sx > [expr {$__rmx0 - 1.0}] && $__sx < [expr {$__rmx1 + 1.0}]} {
			if {$__ay0 < $__rmy1 && $__ay1 > $__rmy0} {
				if {$__ry1 < $__rmy0} { set __ay1 [expr {$__rmy0 - 0.5}] } else { set __ay0 [expr {$__rmy1 + 0.5}] }
			}
		}
		addStripe -layer M2 -nets {VDD} -direction vertical -width 0.3 \
			-set_to_set_distance 1000 -start_offset 0.2 -stop_offset 0.1 \
			-area [list [expr {$__sx - 0.2}] $__ay0 [expr {$__sx + 0.5}] $__ay1]
		# PER-CELL coverage check. The engine places PARTIAL straps: with
		# top=M8 it keeps only the pieces it can upstack (bring-up v7: T25
		# kept just the y 4-14 piece over the ring band and 258 cells went
		# naked while the run looked "placed" and "healthy"). Any member
		# cell without a VDD via gets a top=M2 RETRY over just its
		# subrange (engine then places + VIA1s unconditionally); cells
		# still naked after the retry are waived (taps, recorded) or FATAL
		# (headers). NO lateral fixups: a bring-up sroute-rerun variant
		# "fixed" naked pins with 12-um M1 corewires across the row — a
		# short factory once placement fills the rows. Deleted.
		set __cw [expr {[string index $__key 0] eq "H" ? 4.0 : 0.4}]
		set __uncov {}
		foreach __y $__ys {
			if {$__y < $__ry0 || $__y > $__ry1} { continue }
			if {![pg4_has_svia [list $__x0 $__y [expr {$__x0 + $__cw}] [expr {$__y + 2.0}]] VDD]} { lappend __uncov $__y }
		}
		if {[llength $__uncov] > 0} {
			# cluster uncovered cells into subranges and retry with top=M2
			set __srs {}
			set __us [lindex $__uncov 0]; set __ue $__us
			foreach __y $__uncov {
				if {[expr {$__y - $__ue}] > 12.0} { lappend __srs [list $__us $__ue]; set __us $__y }
				set __ue $__y
			}
			lappend __srs [list $__us $__ue]
			setAddStripeMode -stacked_via_top_layer M2
			foreach __sr $__srs {
				foreach {__u0 __u1} $__sr {}
				addStripe -layer M2 -nets {VDD} -direction vertical -width 0.3 \
					-set_to_set_distance 1000 -start_offset 0.2 -stop_offset 0.1 \
					-area [list [expr {$__sx - 0.2}] [expr {$__u0 - 1.0}] [expr {$__sx + 0.5}] [expr {$__u1 + 3.0}]]
			}
			setAddStripeMode -stacked_via_top_layer M8
			set __still {}
			foreach __y $__uncov {
				if {![pg4_has_svia [list $__x0 $__y [expr {$__x0 + $__cw}] [expr {$__y + 2.0}]] VDD]} { lappend __still $__y }
			}
			if {[llength $__still] > 0} {
				if {[string index $__key 0] eq "H"} {
					puts "FATAL (PG4/F1): [llength $__still] header cells in $__key still naked after the top=M2 retry (y: [lrange $__still 0 5]). Aborting."
					saveDesign dbs/pg4gateb_fail.innovus
					exit 1
				}
				foreach __y $__still {
					incr __nstrap_skip
					lappend __skipped_runs [list $__sx $__y $__y]
				}
				puts "PG4: waiving [llength $__still] naked taps in $__key after retry (y: [lrange $__still 0 5])"
			}
		}
		# unconditional continuity rect: partial attempt-1 pieces + retry
		# fragments merge into ONE conductor (raw same-net metal, no-op when
		# already continuous)
		add_shape -net VDD -layer M2 -rect [list $__sx [expr {$__ry0 - 0.5}] [expr {$__sx + 0.3}] [expr {$__ry1 + 2.5}]] -shape STRIPE -status ROUTED
		incr __nstrap
		lappend __placed_runs [list $__key $__sx $__ay0 $__ay1]
	}
}

# --- PG4 phase 2: columns whose strap band lies under FOREIGN M7 (the VSS
# ring legs at x 18-28 / 632-642, the VSS stripes at 59.5+50k, the notch
# legs) can never stack up to the M8 grid — the engine's antenna trim even
# shreds their strap into per-pin fragments (bring-up v4: T25/T637 whole
# columns, H511/H111/T61/T313/T361/T613 partials — VIA1-on-fragment looked
# "supplied" to a naive via check). Remedy, probe-proven piecewise:
# Remedy: ladder the sick strap to the NEAREST healthy column with
# horizontal SAME-LAYER M2 links — touching same-net same-layer metal
# connects with NO vias (editPowerVia -add_vias was proven a no-op for
# this, and only addStripe itself makes pin VIA1s). Links land at
# M8-VDD-row centers every ~100 um so column current spreads across the
# neighbour's existing stacks. A run is healthy iff it has >= 1 real
# upward stack (via4..7) in band.
proc pg4_upstacks {sx y0 y1} {
	set n 0
	foreach o [dbQuery -area [list [expr {$sx - 0.1}] $y0 [expr {$sx + 0.4}] $y1] -objType sVia] {
		if {[dbGet -e $o.net.name] ne "VDD"} { continue }
		set vn [dbGet -e $o.via.name]
		if {[string match -nocase via4* $vn] || [string match -nocase via5* $vn] || [string match -nocase via6* $vn] || [string match -nocase via7* $vn]} { incr n }
	}
	return $n
}
set __healthy {}
set __sick {}
set __link_rects {}
foreach __pr $__placed_runs {
	foreach {__key __sx __ay0 __ay1} $__pr {}
	if {[pg4_upstacks $__sx $__ay0 $__ay1] > 0} { lappend __healthy $__pr } else { lappend __sick $__pr }
}
puts "### UNL STATUS ### : PG4 strap columns: [llength $__healthy] healthy / [llength $__sick] need the M3 ladder remedy"
set __nlink 0
foreach __pr $__sick {
	foreach {__key __sx __ay0 __ay1} $__pr {}
	# nearest healthy neighbour with y overlap
	set __best ""
	set __bestd 1e9
	foreach __hr $__healthy {
		foreach {__hk __hx __hy0 __hy1} $__hr {}
		set __ov [expr {min($__ay1, $__hy1) - max($__ay0, $__hy0)}]
		if {$__ov < 2.0} { continue }
		set __d [expr {abs($__hx - $__sx)}]
		if {$__d < $__bestd} { set __bestd $__d; set __best $__hr }
	}
	if {$__best eq "" || $__bestd > 30.0} {
		puts "FATAL (PG4/F1): no healthy strap column within 30 um of sick run $__key ($__sx) — cannot ladder. Aborting."
		saveDesign dbs/pg4gateb_fail.innovus
		exit 1
	}
	foreach {__hk __hx __hy0 __hy1} $__best {}
	set __lx0 [expr {min($__sx, $__hx)}]
	set __lx1 [expr {max($__sx, $__hx) + 0.3}]
	set __oy0 [expr {max($__ay0, $__hy0)}]
	set __oy1 [expr {min($__ay1, $__hy1)}]
	# M8 VDD rows: lly = 51 + 50k -> centers 53.5 + 50k; one link per 100 um;
	# a short run gets a single mid-overlap link.
	set __k [expr {int(ceil(($__oy0 - 53.5) / 100.0))}]
	set __nl 0
	for {set __yc [expr {53.5 + 100.0 * $__k}]} {$__yc < $__oy1} {set __yc [expr {$__yc + 100.0}]} {
		if {$__yc < $__oy0} { continue }
		add_shape -net VDD -layer M2 -rect [list $__lx0 [expr {$__yc - 0.15}] $__lx1 [expr {$__yc + 0.15}]] -shape STRIPE -status ROUTED
		lappend __link_rects [list $__lx0 [expr {$__yc - 0.15}] $__lx1 [expr {$__yc + 0.15}]]
		incr __nl
		incr __nlink
	}
	if {$__nl == 0} {
		set __yc [expr {($__oy0 + $__oy1) / 2.0}]
		add_shape -net VDD -layer M2 -rect [list $__lx0 [expr {$__yc - 0.15}] $__lx1 [expr {$__yc + 0.15}]] -shape STRIPE -status ROUTED
		lappend __link_rects [list $__lx0 [expr {$__yc - 0.15}] $__lx1 [expr {$__yc + 0.15}]]
		set __nl 1
		incr __nlink
	}
	puts "PG4: laddered $__key ($__sx) -> [lindex $__best 0] ([format %.2f $__hx]) with $__nl M2 links"
}
puts "### UNL STATUS ### : PG4 ladder remedy — [llength $__sick] columns linked with $__nlink M2 links"
# NB deliberately NO global secondary-sroute rerun here: a bring-up
# variant used one and it "fixed" naked pins by routing 12-um lateral M1
# corewires across the (still empty) rows — guaranteed shorts once
# placement fills them. The per-cell top=M2 retry above is the whole
# mechanism.
puts "### UNL STATUS ### : PG4 placed $__nstrap M2 secondary strap segments over [llength [array names __colys]] columns ($__nstrap_skip short tap runs waived)"
if {$__nstrap_skip > 100} {
	puts "FATAL (PG4/F1): $__nstrap_skip skipped strap runs — far more than the documented sub-ram0 sliver class. Aborting."
	exit 1
}

# VPW jumpers: R0 rows have the VSS rail at the cell bottom, MX at the top.
set __njump 0
foreach __i [dbGet -p2 top.insts.cell.name FILLBIASA10TH] {
	set __bx [lindex [dbGet $__i.box] 0]
	if {[pg4_dead_row $__bx]} { continue }
	foreach {__x0 __y0 __x1 __y1} $__bx {}
	if {[dbGet $__i.orient] eq "R0"} {
		add_shape -net VSS -layer M1 -rect [list [expr {$__x0 + 0.15}] [expr {$__y0 + 0.10}] [expr {$__x0 + 0.25}] [expr {$__y0 + 0.35}]] -shape STRIPE -status ROUTED
	} else {
		add_shape -net VSS -layer M1 -rect [list [expr {$__x0 + 0.15}] [expr {$__y0 + 1.65}] [expr {$__x0 + 0.25}] [expr {$__y0 + 1.90}]] -shape STRIPE -status ROUTED
	}
	incr __njump
}
puts "### UNL STATUS ### : PG4 added $__njump VPW->VSS-rail M1 jumpers"

# --- PG4 F1 gate b (v2, VIA-based): a dead finger has no via; a real strap
# does. Every live HEADBUF and FILLBIAS-VNW footprint must carry a VDD sVia;
# every live FILLBIAS-VPW footprint a VSS non-followpin wire or sVia.
proc pg4_has_wire {box wantnet skipfollow} {
	foreach {bx0 by0 bx1 by1} $box {}
	foreach o [dbQuery -area [list [expr {$bx0 - 0.5}] [expr {$by0 - 0.5}] [expr {$bx1 + 0.5}] [expr {$by1 + 0.5}]] -objType sWire] {
		if {[dbGet -e $o.net.name] ne $wantnet} { continue }
		if {$skipfollow && [dbGet -e $o.shape] eq "followpin"} { continue }
		return 1
	}
	return 0
}
set __f1_untouched 0
foreach __i [dbGet -p2 top.insts.cell.name HEADBUF16MA10TH] {
	set __bx [lindex [dbGet $__i.box] 0]
	if {[pg4_dead_row $__bx]} { continue }
	if {![pg4_has_svia $__bx VDD]} {
		incr __f1_untouched
		if {$__f1_untouched <= 5} { puts "PG4 F1: header [dbGet $__i.name] @$__bx has NO VDD via (VDDG unsupplied)" }
	}
}
foreach __i [dbGet -p2 top.insts.cell.name FILLBIASA10TH] {
	set __bx [lindex [dbGet $__i.box] 0]
	if {[pg4_dead_row $__bx]} { continue }
	set __exempt 0
	foreach __sk $__skipped_runs {
		foreach {__skx __sky0 __sky1} $__sk {}
		if {abs([lindex $__bx 0] + 0.10 - $__skx) < 0.35 && [lindex $__bx 1] >= [expr {$__sky0 - 0.5}] && [lindex $__bx 1] <= [expr {$__sky1 + 0.5}]} { set __exempt 1; break }
	}
	if {!$__exempt && ![pg4_has_svia $__bx VDD]} {
		incr __f1_untouched
		if {$__f1_untouched <= 5} { puts "PG4 F1: welltap [dbGet $__i.name] @$__bx has NO VDD via (VNW unstrapped)" }
	}
	if {![pg4_has_wire $__bx VSS 1] && ![pg4_has_svia $__bx VSS]} {
		incr __f1_untouched
		if {$__f1_untouched <= 5} { puts "PG4 F1: welltap [dbGet $__i.name] @$__bx has NO VPW jumper" }
	}
}
puts "### UNL STATUS ### : PG4 F1 gate b — $__f1_untouched unsupplied pmk secondary-pin footprints (must be 0)"
if {$__f1_untouched > 0} {
	puts "FATAL (PG4/F1): $__f1_untouched pmk cells have no real secondary supply. Saving dbs/pg4gateb_fail.innovus; aborting."
	saveDesign dbs/pg4gateb_fail.innovus
	exit 1
}

# PG4 dangling-stack scrub: at VPW pins under the VSS M7 legs/stripes the
# FIRST secondary sroute leaves floating VIA3..VIA6 stacks (top merged into
# the M7 leg, bottom DANGLING at M3 — no via1/via2 ever placed): 946
# zero-area ANTENNA markers at signoff (bring-up v11). The pins themselves
# are supplied by the VPW M1 jumpers, so the stacks are pure litter. Delete
# exactly the {via3..6, no via1/via2/via7} VSS point-groups — a legit stack
# always includes via1 or via2 (pin/strap bottom) or is via7-only (ring
# crossings).
array unset __vgrp
foreach __o [dbGet [dbGet -p top.nets.name VSS].sVias -e] {
	set __vn [dbGet -e $__o.via.name]
	set __k "[format %.2f [dbGet $__o.pt_x]]_[format %.2f [dbGet $__o.pt_y]]"
	lappend __vgrp($__k) [list $__o $__vn]
}
set __nscrub 0
foreach __k [array names __vgrp] {
	set __has12 0; set __has7 0; set __has36 0
	foreach __e $__vgrp($__k) {
		set __vn [lindex $__e 1]
		if {[string match -nocase via1* $__vn] || [string match -nocase via2* $__vn]} { set __has12 1 }
		if {[string match -nocase via7* $__vn]} { set __has7 1 }
		if {[string match -nocase via3* $__vn] || [string match -nocase via4* $__vn] || [string match -nocase via5* $__vn] || [string match -nocase via6* $__vn]} { set __has36 1 }
	}
	if {$__has36 && !$__has12 && !$__has7} {
		foreach __e $__vgrp($__k) { dbDeleteObj [lindex $__e 0]; incr __nscrub }
	}
}
puts "### UNL STATUS ### : PG4 scrubbed $__nscrub dangling VSS stack vias (v11 baseline: ~946 antenna markers)"

# PG4 route blockages over every M2 strap band + ladder link: nanoroute
# dropped one signal VIA2 pad inside the T121 strap band at v11 (1 M2
# short) — special wires alone evidently do not fence via landing pads.
# deleteAllRouteBlks after routing removes these along with the M7/M8 ones.
set __nblk 0
foreach __pr $__placed_runs {
	foreach {__key __sx __ay0 __ay1} $__pr {}
	createRouteBlk -box [list [expr {$__sx - 0.1}] $__ay0 [expr {$__sx + 0.4}] $__ay1] -layer 2
	incr __nblk
}
foreach __lr $__link_rects {
	foreach {__lx0 __ly0 __lx1 __ly1} $__lr {}
	createRouteBlk -box [list [expr {$__lx0 - 0.1}] [expr {$__ly0 - 0.1}] [expr {$__lx1 + 0.1}] [expr {$__ly1 + 0.1}]] -layer 2
	incr __nblk
}
puts "### UNL STATUS ### : PG4 created $__nblk M2 route blockages over the strap fabric"

# PG4 M7 pad-bridge pass: a strap upstack's M7 landing pads reach to
# sx+0.41; where a SAME-NET M7 stripe/ring edge sits 0.05..1.5 um away the
# net-blind wide-metal union rule fires (v11 Calibre: 36 = T49/T349/T649 x
# 12 M8-rows, pads at 49.51 vs stripe llx 50.5). One full-run-height M7
# rect bridges pad and stripe into a single union shape — additive, same
# net, M7 is power-only here.
set __nbridge 0
foreach __pr $__placed_runs {
	foreach {__key __sx __ay0 __ay1} $__pr {}
	set __padr [expr {$__sx + 0.41}]
	set __padl [expr {$__sx - 0.11}]
	foreach __o [dbGet [dbGet -p top.nets.name VDD].sWires -e] {
		if {[dbGet -e $__o.layer.name] ne "M7"} { continue }
		set __b [lindex [dbGet $__o.box] 0]
		foreach {__bx0 __by0 __bx1 __by1} $__b {}
		if {[expr {$__by1 - $__by0}] < 100} { continue }
		if {[expr {min($__by1, $__ay1) - max($__by0, $__ay0)}] < 10} { continue }
		set __gapr [expr {$__bx0 - $__padr}]
		set __gapl [expr {$__padl - $__bx1}]
		if {$__gapr > 0.02 && $__gapr < 1.6} {
			add_shape -net VDD -layer M7 -rect [list [expr {$__sx + 0.25}] [expr {max($__ay0, $__by0)}] [expr {$__bx0 + 0.2}] [expr {min($__ay1, $__by1)}]] -shape STRIPE -status ROUTED
			incr __nbridge
		} elseif {$__gapl > 0.02 && $__gapl < 1.6} {
			add_shape -net VDD -layer M7 -rect [list [expr {$__bx1 - 0.2}] [expr {max($__ay0, $__by0)}] [expr {$__sx + 0.05}] [expr {min($__ay1, $__by1)}]] -shape STRIPE -status ROUTED
			incr __nbridge
		}
	}
}
puts "### UNL STATUS ### : PG4 added $__nbridge M7 pad-union bridges"

# PG4 duplicate-VIA1 dedupe: under same-net M7 stripes the FIRST sroute
# already stacked some pins; my strap adds a second VIA1 ~0.1 um away =
# VIA1 array-spacing violations (v11: 6 on T553). Keep the strap-centered
# via of each close pair, delete the other.
set __ndd 0
foreach __pr $__placed_runs {
	foreach {__key __sx __ay0 __ay1} $__pr {}
	set __c [expr {$__sx + 0.15}]
	array unset __v1g
	foreach __o [dbQuery -area [list [expr {$__sx - 0.4}] $__ay0 [expr {$__sx + 0.7}] $__ay1] -objType sVia] {
		if {[dbGet -e $__o.net.name] ne "VDD"} { continue }
		if {![string match -nocase via1* [dbGet -e $__o.via.name]]} { continue }
		set __gy [expr {round([dbGet $__o.pt_y] * 2.0) / 2.0}]
		lappend __v1g($__gy) [list $__o [dbGet $__o.pt_x]]
	}
	foreach __gy [array names __v1g] {
		if {[llength $__v1g($__gy)] < 2} { continue }
		set __keep ""
		set __kd 1e9
		foreach __e $__v1g($__gy) {
			set __d [expr {abs([lindex $__e 1] - $__c)}]
			if {$__d < $__kd} { set __kd $__d; set __keep [lindex $__e 0] }
		}
		foreach __e $__v1g($__gy) {
			if {[lindex $__e 0] ne $__keep} { dbDeleteObj [lindex $__e 0]; incr __ndd }
		}
	}
}
puts "### UNL STATUS ### : PG4 deduped $__ndd doubled VIA1s under same-net stripes"

# PG4 fix for the LAST tile foundry-DRC violation — M7.S.4 pair (b), the
# notch-ring-bend VSS via-stack landing pads (PG3 finding). Under the M8
# finger-rail-to-ring strap at x 63.5-68.5 two same-net VSS pad groups face
# each other 1.02 um apart: the via7Array_6 stripe-via M7 pad (top edge
# y=569.75) vs the follow-pin VIA1-7 rail-stack pads at (66, 571+) (bottom
# ~570.77). Same net, but the deck's union-projection wide-metal rule is
# net-blind. Fix = ADD one merging VSS M7 rect over the gap so the union
# becomes a single shape (no facing edges). ADDITIVE ONLY — the PG3 lesson
# stands: deleting/redrawing engine shapes loses their stacked vias
# irrecoverably (editPowerVia can't rebuild them, IMPSR-554). Nearest
# foreign M7 is the VDD ring leg at y>=586 (14.5 um) and the VDD stripe
# column at x<=55.5 (8 um) — the merged shape clears both by miles.
# Validated on the PG3 signoff DB + Calibre blockdrc: M7.S.4 1 -> 0.
add_shape -net VSS -layer M7 -rect {63.5 569.0 68.5 572.0} -shape STRIPE -status ROUTED
set __ps4 0
foreach __sw [dbGet [dbGet -p top.nets.name VSS].sWires -e] {
	if {[dbGet $__sw.layer.name] ne "M7"} { continue }
	set __bx [lindex [dbGet $__sw.box] 0]
	if {[lindex $__bx 0] > 63.0 && [lindex $__bx 0] < 64.0 && [lindex $__bx 1] > 568.5 && [lindex $__bx 1] < 569.5} { incr __ps4 }
}
if {$__ps4 == 0} {
	puts "FATAL (PG4): the M7.S.4(b) merge patch did not land — add_shape silently failed. Aborting."
	exit 1
}
puts "### UNL STATUS ### : PG4 M7.S.4(b) pad-merge patch placed"

################################################################################
# PG1 F1 (2026-07-10): ALWAYS-ON repeaters for the long SLEEP-chain links.
# The four columns whose chains jump ~400 um over the ram0 macro got their
# enable link repeated by place_opt with ORDINARY INVERTER PAIRS on VDD_SW —
# cells that die with the rail they are supposed to keep off: 202/1027
# switches' SLEEP then drifts mid-rail on always-on VDDG receivers and the
# column-tails re-enable/oscillate/crowbar (PG1 audit finding F1; the pmk
# sim model is buf(SLEEPOUT,SLEEP), so no gate sim can ever see this).
# Fix: splice a GPGBUFX4 (VDDG-powered always-on buffer — the pmk cell that
# exists for exactly this, already define_always_on_cell in the CPF) into
# every chain link longer than PG1_LINK_THRESH. This block runs AFTER the
# main secondary-pin sroute: a GPGBUF present during that pass trips
# IMPSR-503 ("level shifter secondary pins need a power domain") and the
# pass silently does NOTHING — the whole switch fabric loses its VDDG
# straps (proven, run 9). The repeaters' own AO hookup is a dedicated
# -powerDomains pass after place_opt (they are unplaced until then). The
# nets are then marked dont_touch so opt can never splice core cells into
# the chain again; the PG1 acceptance gate before signoff is the backstop.
################################################################################
printStatus "PG1: splicing GPGBUF AO repeaters into long SLEEP-chain links"
set PG1_LINK_THRESH 150.0
set PG1_NREP 0
foreach np [dbGet -p top.nets.name psoPSI_*] {
	set netname [dbGet $np.name]
	set drv ""
	set lds {}
	foreach t [dbGet $np.instTerms.name -e] {
		if {[string match {*/SLEEPOUT} $t]} { set drv $t } \
		elseif {[string match {*/SLEEP} $t]} { lappend lds $t }
	}
	if {$drv eq "" || [llength $lds] != 1} { continue }
	set drvinst [string range $drv 0 [expr {[string last "/" $drv] - 1}]]
	set ldinst  [string range [lindex $lds 0] 0 [expr {[string last "/" [lindex $lds 0]] - 1}]]
	set p1 [lindex [dbGet [dbGet -p top.insts.name $drvinst].pt] 0]
	set p2 [lindex [dbGet [dbGet -p top.insts.name $ldinst].pt]  0]
	set dist [expr {abs([lindex $p1 0] - [lindex $p2 0]) + abs([lindex $p1 1] - [lindex $p2 1])}]
	if {$dist <= $PG1_LINK_THRESH} { continue }
	set repname pgaorep_$PG1_NREP
	set repnet  ${netname}_pg1rep
	puts "PG1: link $netname ($drvinst -> $ldinst) is ${dist}um — splicing $repname"
	addNet $repnet
	addInst -cell GPGBUFX4MA10TH -inst $repname
	attachTerm $repname A $netname
	attachTerm $repname Y $repnet
	detachTerm $ldinst SLEEP
	attachTerm $ldinst SLEEP $repnet
	dbSet [dbGet -p top.nets.name $repnet].dontTouch true
	incr PG1_NREP
}
puts "### UNL STATUS ### : PG1 spliced $PG1_NREP GPGBUF AO repeaters into the SLEEP chain"
if {$PG1_NREP == 0} {
	puts "WARNING (PG1): no long SLEEP-chain links found — floorplan changed? Verify the chain."
}
# Freeze the whole enable chain + the macro PG-control nets against opt.
# NOT setAttribute (-dont_touch is not an option in 20.12 — IMPTCM-48,
# proven by run 9's re-buffered chain): dbSet the net attribute, and verify
# it took. The acceptance gate before signoff remains the hard backstop.
foreach np [dbGet -p top.nets.name psoPSI_*] {
	dbSet $np.dontTouch true
}
foreach nn {pd_sleep tcm_pgen tcm_retn} {
	set np [dbGet -p top.nets.name $nn -e]
	if {$np ne ""} { dbSet $np.dontTouch true }
}
set PG1_DT [llength [dbGet -p top.nets.dontTouch true -e]]
puts "### UNL STATUS ### : PG1 dont_touch set on $PG1_DT nets"
if {$PG1_DT == 0} {
	puts "FATAL (PG1): dont_touch did not take on any chain net"
	exit 1
}
# The repeaters were created AFTER the -inst * globalNetConnect lines ran —
# re-apply the AO secondary-pin rules to them (VSSG exists only on GPG cells).
# PG4/PG2-F1: -type pgpin (the -type net form never bound anything — the
# PG1-F1 repeaters shipped UNPOWERED, fix physically void as built), and
# gate the binding: 4 dead repeaters silently re-break the SLEEP chain.
if {$PG1_NREP > 0} {
	globalNetConnect VDD -type pgpin -pin VDDG -inst pgaorep_* -module {} -verbose
	globalNetConnect VSS -type pgpin -pin VSSG -inst pgaorep_* -module {} -verbose
	# (binding not checkable here — see the PG4 NOTE above; the geometric
	# repeater gate runs after their post-place sroute below)
}


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

# M17b: hard-block the two rows the switch checkerboard leaves uncovered —
# the BOTTOM row (1,1) and the right U-leg TOP row (581,1047). Their VDD_SW
# rails are permanently dead (IMPPSO-306 warns and the run rolls on) and
# place_opt parked 52 live cells (bnd_irq_* boundary flops, hart_id
# inverters) on the bottom one; blocked, they stay EMPTY — a dead floating
# rail with nothing live on it. Well taps already placed there are fine
# (FILLBIAS biases the wells from VNW/VPW = the AO nets; its VDD frame pin
# merely abuts the dead stub). POSITION IS LOAD-BEARING — the blockages must
# be created HERE, after everything upstream and just before place_opt:
#  * before addPowerSwitch they shift its checkerboard phase and the
#    uncovered rows MOVE ((1,1047)/(581,1045) went dark instead);
#  * before sroute they suppress the blocked rows' follow-pin rails and the
#    dead-row well-tap VDD frames go "unconnected" at signoff (6 IMPVFC-96).
# Do NOT cutRow the bottom row instead (re-flips every row's orientation
# parity above it — ~1000 M1 abutment shorts, proven) and do NOT drop the
# checkerboard (M1 pin-frame shorts wherever pmk cells stack vertically,
# also proven). Acceptance for any rerun: every IMPPSO-306 row lies inside
# one of these boxes, and no live cell places at row-origin y=1 or in the
# right-leg top row.
createPlaceBlockage -type hard -name dead_row_bottom \
	-box [list 0 0 $DESIGN_WIDTH 3]
createPlaceBlockage -type hard -name dead_row_rleg_top \
	-box [list [expr {$DESIGN_WIDTH - $FINGER_W}] [expr {$DESIGN_HEIGHT - 3}] $DESIGN_WIDTH $DESIGN_HEIGHT]
printStatus "Blocked the 2 switchless dead-rail rows"

place_opt_design
printStatus "Placement done"

# PG1 F1: the GPGBUF repeaters were UNPLACED when the secondary-pin sroute
# ran (it must run pre-place for the fixed switches/taps; the repeaters are
# ordinary movable cells that place_opt just legalized) — hook their AO
# supply pins (VDDG/VSSG, globalNetConnect'd above) up now, instance-
# targeted so nothing else is re-routed. verifyConnectivity at signoff is
# the backstop if this pass ever strands a pin.
if {[info exists PG1_NREP] && $PG1_NREP > 0} {
	printStatus "PG1: strapping the GPGBUF repeaters' secondary AO pins (PG4 M2 straps)"
	# PG4 v19: PIN THE REPEATERS FIRST. The v18 signoff DB had all four
	# pgaorep hookups stranded 1.1-1.2 um from their cells: this stage runs
	# right after place_opt, but the repeaters are ordinary MOVABLE cells —
	# CTS/optDesign/postRoute-ECO relocated them AFTER the metal was drawn.
	# The in-flow via gate passed against the pre-CTS positions; the tell
	# was signoff verifyConnectivity IMPVFC-96 on every pgaorep VDDG+VSSG.
	# Headers/taps/FILLBIAS are preplaced fixed; the repeaters must be too
	# the moment their hand-drawn supply metal exists.
	dbSet [dbGet -p top.insts.name pgaorep_*].pStatus fixed
	# PG4: the old per-inst secondaryPowerPin sroute here is DELETED — at
	# v11 it landed a VSS via pad on pgaorep_2's own Y OUTPUT pin (M1
	# short marker; electrically the SLEEP chain pinned low = every
	# switch forced awake, invisible to any netlist check). The M2 strap
	# recipe below is the whole hookup; the via gate verifies it.
	# BUT addStripe only vias onto special-wire shapes, never onto PIN
	# geometry (v13: 4 repeaters unsupplied once the sroute fingers were
	# gone — the column fabric always via'd onto the first sroute's M1
	# fingers). So draw the fingers OURSELVES: M1 rects inset 0.01 inside
	# the VDDG/VSSG pin bar outlines — zero geometry beyond the pin, no
	# short possible. Bars per orient (cell 1.4 x 2.0, LEF R0 coords):
	#   VDDG: (0.37-0.55, 1.40-1.74) and (0.93-1.10, 1.45-1.74)
	#   VSSG: (0.36-0.53, 0.265-0.555) and (0.93-1.10, 0.265-0.59)
	proc pg4_rep_finger {net inst bar} {
		set bx [lindex [dbGet $inst.box] 0]
		foreach {x0 y0 x1 y1} $bx {}
		set or [dbGet $inst.orient]
		foreach {bx0 by0 bx1 by1} $bar {}
		set w 1.4; set h 2.0
		if {$or eq "MY" || $or eq "R180"} {
			set tx0 [expr {$w - $bx1}]; set tx1 [expr {$w - $bx0}]
		} else { set tx0 $bx0; set tx1 $bx1 }
		if {$or eq "MX" || $or eq "R180"} {
			set ty0 [expr {$h - $by1}]; set ty1 [expr {$h - $by0}]
		} else { set ty0 $by0; set ty1 $by1 }
		add_shape -net $net -layer M1 -rect [list 			[expr {$x0 + $tx0 + 0.01}] [expr {$y0 + $ty0 + 0.01}] 			[expr {$x0 + $tx1 - 0.01}] [expr {$y0 + $ty1 - 0.01}]] 			-shape STRIPE -status ROUTED
	}
	foreach __i [dbGet -p top.insts.name pgaorep_*] {
		pg4_rep_finger VDD $__i {0.37 1.40 0.55 1.74}
		pg4_rep_finger VDD $__i {0.93 1.45 1.10 1.74}
		pg4_rep_finger VSS $__i {0.36 0.265 0.53 0.555}
		pg4_rep_finger VSS $__i {0.93 0.265 1.10 0.59}
	}
	# PG4 F1 repeater supply straps + gate. The sroute above only fingers
	# the pins (PG2 found the run-10 repeaters UNPOWERED — the devlog's "AO
	# straps drawn" probe claim was never reproducible); give each pgaorep
	# a real M2 mini-strap per supply pin, engine-via'd like the column
	# straps (VIA1 on the pin + stacked vias at the M8-grid crossing).
	# GPGBUFX4 pin bars (LEF, x-disjoint on purpose): VDDG bar x0+0.37..0.55,
	# VSSG bar x0+0.93..1.10. The strap extends to just past the nearest
	# same-net M8 stripe (grid: VDD lly=51+50k, VSS lly=60+50k), direction
	# picked to stay inside the core and out of ram0/the notch.
	proc pg4_rep_strap {net sx y0 y1} {
		# find nearest same-net M8 stripe lly above y1 and below y0
		global DESIGN_HEIGHT DESIGN_WIDTH FINGER_W BASE_H
		set base [expr {$net eq "VDD" ? 51.0 : 60.0}]
		set kup [expr {int(ceil(($y1 + 2 - $base) / 50.0))}]
		set yup [expr {$base + 50.0 * $kup + 6.0}]
		set kdn [expr {int(floor(($y0 - 8 - $base) / 50.0))}]
		set ydn [expr {$base + 50.0 * $kdn - 1.0}]
		set ram [lindex [dbGet [dbGet -p top.insts.name ram0].box] 0]
		foreach {rx0 ry0 rx1 ry1} $ram {}
		set upok 1
		if {$yup > [expr {$DESIGN_HEIGHT - 2}]} { set upok 0 }
		if {$sx > [expr {$rx0 - 1}] && $sx < [expr {$rx1 + 1}] && $y1 < $ry1 && $yup > $ry0} { set upok 0 }
		if {$sx > [expr {$FINGER_W - 1}] && $sx < [expr {$DESIGN_WIDTH - $FINGER_W + 1}] && $yup > [expr {$BASE_H - 2}]} { set upok 0 }
		if {$upok} {
			set ay0 [expr {$y0 - 0.2}]
			set ay1 $yup
		} else {
			set ay0 $ydn
			set ay1 [expr {$y1 + 0.2}]
			if {$sx > [expr {$rx0 - 1}] && $sx < [expr {$rx1 + 1}] && $y0 > $ry0 && $ay0 < $ry1} {
				puts "FATAL (PG4/F1): repeater strap at x=$sx has no clean path to an M8 $net stripe. Aborting."
				exit 1
			}
		}
		# a different-net M2 strap (tap/header column) in this band = short:
		# report failure so the caller can try the pin's OTHER bar.
		# window = band + the 0.1 um M2 min spacing, EXACTLY — a 0.15
		# margin false-flagged a legal 0.13 gap (pgaorep_3, bring-up v10)
		foreach __o [dbQuery -area [list [expr {$sx - 0.099}] $ay0 [expr {$sx + 0.399}] $ay1] -objType sWire] {
			if {[dbGet -e $__o.layer.name] eq "M2" && [dbGet -e $__o.net.name] ne $net} {
				puts "PG4: repeater $net strap band at x=$sx collides with an M2 [dbGet -e $__o.net.name] strap — trying the alternate bar"
				return 0
			}
		}
		addStripe -layer M2 -nets [list $net] -direction vertical -width 0.3 \
			-set_to_set_distance 1000 -start_offset 0.2 -stop_offset 0.05 \
			-area [list [expr {$sx - 0.2}] $ay0 [expr {$sx + 0.5}] $ay1]
		return 1
	}
	setAddStripeMode -reset
	setAddStripeMode \
		-stacked_via_top_layer M8 \
		-stacked_via_bottom_layer M1 \
		-extend_to_closest_target none
	set __rep_vdd_band [dict create]
	foreach __i [dbGet -p top.insts.name pgaorep_*] {
		set __bx [lindex [dbGet $__i.box] 0]
		foreach {__x0 __y0 __x1 __y1} $__bx {}
		set __or [dbGet $__i.orient]
		# GPGBUFX4 has TWO mirrored vertical bars per supply pin: R0/MX
		# VDDG at 0.37-0.55 and 0.93-1.10, VSSG at 0.93-1.10 and 0.36-0.53
		# (MY/R180 mirror in x: llx' = 1.4 - llx - 0.3). Try each candidate
		# bar; skip any whose 0.3-um band would touch a column strap of the
		# other net (pg4_rep_strap collision check) or the band already
		# claimed for this repeater's other supply.
		if {$__or eq "R0" || $__or eq "MX"} {
			set __vddc {0.37 0.80}
			set __vssc {0.80 0.30}
		} elseif {$__or eq "MY" || $__or eq "R180"} {
			set __vddc {0.73 0.30}
			set __vssc {0.30 0.77}
		} else {
			puts "FATAL (PG4/F1): repeater [dbGet $__i.name] orient $__or unsupported by the strap recipe. Aborting."
			exit 1
		}
		set __vdd_band ""
		foreach __c $__vddc {
			if {[pg4_rep_strap VDD [expr {$__x0 + $__c}] $__y0 $__y1]} { set __vdd_band $__c; break }
		}
		dict set __rep_vdd_band [dbGet $__i.name] $__vdd_band
		if {$__vdd_band eq ""} {
			puts "FATAL (PG4/F1): no collision-free VDD bar for repeater [dbGet $__i.name]. Aborting."
			saveDesign dbs/pg4rep_fail.innovus
			exit 1
		}
		set __vss_done 0
		foreach __c $__vssc {
			if {abs($__c - $__vdd_band) < 0.4} { continue }
			if {[pg4_rep_strap VSS [expr {$__x0 + $__c}] $__y0 $__y1]} { set __vss_done 1; break }
		}
		if {!$__vss_done} {
			puts "FATAL (PG4/F1): no collision-free VSS bar for repeater [dbGet $__i.name]. Aborting."
			saveDesign dbs/pg4rep_fail.innovus
			exit 1
		}
	}
	# VDDG via (PG4 v22, GDS-real form): the v18-v21 `add_via VIA1_V` here
	# was a GDS-PHANTOM — add_via specials pass every in-DB gate but
	# streamOut silently drops them (single-via A/B proof; same mechanism as
	# the strap-grid repair above). The finger (M1, in-pin) and the strap
	# (M2) OVERLAP in plan on the chosen band, so the ENGINE can via them:
	# per-repeater editPowerVia M1->M2, tightly windowed to the cell bbox
	# +0.5 so nothing else is touched. VSSG needs nothing extra: the VSS
	# strap crosses the VSS rails and the engine already vias those (real
	# via1Arrays, GDS-verified).
	foreach __i [dbGet -p top.insts.name pgaorep_*] {
		set __bx [lindex [dbGet $__i.box] 0]
		foreach {__rx0 __ry0 __rx1 __ry1} $__bx {}
		# -orthogonal_only 0: finger and strap are both VERTICAL — the
		# default only vias orthogonal crossings (v22b FATAL; probe-proven
		# 0 -> 1 via with the flag).
		editPowerVia -add_vias 1 -nets VDD -bottom_layer M1 -top_layer M2 -orthogonal_only 0 \
			-area [list [expr {$__rx0 - 0.5}] [expr {$__ry0 - 0.5}] [expr {$__rx1 + 0.5}] [expr {$__ry1 + 0.5}]]
	}
	set __rep_bad 0
	foreach __i [dbGet -p top.insts.name pgaorep_*] {
		set __bx [lindex [dbGet $__i.box] 0]
		if {![pg4_has_svia $__bx VDD]} {
			incr __rep_bad
			puts "PG4 F1: repeater [dbGet $__i.name] @$__bx has NO VDD via (VDDG unsupplied)"
		}
		if {![pg4_has_svia $__bx VSS]} {
			incr __rep_bad
			puts "PG4 F1: repeater [dbGet $__i.name] @$__bx has NO VSS via (VSSG unsupplied)"
		}
	}
	if {$__rep_bad > 0} {
		puts "FATAL (PG4/F1): $__rep_bad GPGBUF repeater supply pins unsupplied — dead AO repeaters re-break the SLEEP chain. Saving dbs/pg4rep_fail.innovus; aborting."
		saveDesign dbs/pg4rep_fail.innovus
		exit 1
	}
	puts "### UNL STATUS ### : PG4 F1 repeater gate — all GPGBUF AO supplies via'd"
	# fence the repeater straps from the router like the column straps
	foreach __i [dbGet -p top.insts.name pgaorep_*] {
		set __bx [lindex [dbGet $__i.box] 0]
		foreach {__x0 __y0 __x1 __y1} $__bx {}
		createRouteBlk -box [list [expr {$__x0 - 0.1}] [expr {$__y0 - 60.0}] [expr {$__x1 + 0.1}] [expr {$__y1 + 60.0}]] -layer 2
	}
}

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
# PG4: +25 ps setup margin pass, SI-aware (M14/M16 ECO form) — the signoff
# SI corner shows a razor-thin reg2cgate WNS (-0.031 at PG3, -0.018 at the
# v11 re-harden; seed noise on a razor-thin baseline). Target-slack opt
# with SI delaycal pads exactly those paths.
setDelayCalMode -SIAware true
setOptMode -setupTargetSlack 0.025
optDesign -postRoute -setup
setOptMode -setupTargetSlack 0
setDelayCalMode -SIAware false

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

# M17b: scrub the two dead-rail rows BARE before signoff. The blockages
# (see the placement section) kept logic out, but addWellTap ran earlier
# and left FILLBIAS taps in the right-leg top row, and the dead VDD_SW rail
# stubs themselves flag as zero-area ANTENNA markers + dangling wires once
# nothing abuts them. Delete the leftover insts, then the two rail stubs —
# dry-run proven on the signoff DB: DRC 0, no IMPVFC-94/-96, conn drops to
# the 476 expected VDD_SW/VSS piece infos. (Deleting the rail out from
# under a FILLBIAS would re-strand its net-tied VDD frame — hence insts
# first, rails second.)
foreach __i [dbQuery -area [list [expr {$DESIGN_WIDTH - $FINGER_W}] [expr {$DESIGN_HEIGHT - 2.8}] $DESIGN_WIDTH [expr {$DESIGN_HEIGHT - 0.2}]] -objType inst] {
	if {[dbGet $__i.pt_y] > [expr {$DESIGN_HEIGHT - 3.5}]} { deleteInst [dbGet $__i.name] }
}
foreach __i [dbQuery -area [list 0 0.5 $DESIGN_WIDTH 2.9] -objType inst] {
	if {[dbGet $__i.pt_y] < 2.5} { deleteInst [dbGet $__i.name] }
}
editDelete -net VDD_SW -area [list 0 0.4 $DESIGN_WIDTH 1.9]
editDelete -net VDD_SW -area [list [expr {$DESIGN_WIDTH - $FINGER_W}] [expr {$DESIGN_HEIGHT - 1.6}] $DESIGN_WIDTH [expr {$DESIGN_HEIGHT - 0.1}]]
# PG4 v19: the PG4 secondary sroute (new since this scrub was written) drew
# M1 pin fingers on the dead-row FILLBIAS too; deleting the insts above
# leaves those fingers floating — v18 signoff flagged 16 of them as REAL
# M1 min-area viols (0.2x0.18 = 0.036 < 0.042) plus antenna litter in the
# right-leg top row. Delete the M1 VDD/VSS pieces inside the two dead-row
# bands; editDelete is whole-shape-contained, so the shared boundary rails
# (y outside the band) and anything crossing survive.
foreach __dnet {VDD VSS} {
	editDelete -net $__dnet -layer M1 -area [list 0 0.3 $DESIGN_WIDTH 2.6]
	editDelete -net $__dnet -layer M1 -area [list [expr {$DESIGN_WIDTH - $FINGER_W}] [expr {$DESIGN_HEIGHT - 3.0}] $DESIGN_WIDTH [expr {$DESIGN_HEIGHT - 0.1}]]
}
printStatus "Scrubbed the 2 dead-rail rows bare"

# (v22b: this stage MOVED here from the fabric section — the M8-crossing
# via3..7 stacks are only fully populated late in the flow: the fabric
# stage sees 371 via3 objects, the signoff DB holds ~2150. Post-route is
# also where the clearance check can see the routed signals.)
# PG4 v22: STRAP->GRID LINK REPAIR (the missing piece of the F1 fix).
# The engine's M8-crossing stacks START AT M3 (via3..7 — no via1/2 was
# ever placed at the crossings), so every M2 strap column was an ISLAND:
# pin-connected below, never grid-connected above. VDD has NO rails (rows
# carry VSS/VDD_SW only) — the crossing stack is a VDD column's ONLY feed,
# so the wells and switch supplies all hung on this. Found by pad-aware
# union-find over the PG dump (v21: 162/256 M2 pieces islanded; 2039 of
# 2154 via3-points had no via1/2 within 0.45; LVS softchk nxwell 6596 and
# ~2100 unmatched layout nets — the verifyConnectivity IMPVFC-200 "pieces
# not connected" class was RIGHT, not tracer noise).
# MECHANISM (probe-proven): `add_via` special vias are GDS-PHANTOMS on
# this install — they live in the DB and pass every dbQuery gate but
# streamOut silently drops them (single-via A/B: layer-52 count unchanged;
# the v18-v21 repeater VIA1_Vs never reached a GDS either). Engine vias
# stream. So: lay a small REAL M3 rect (0.2x0.08, inside the stack pad
# footprint) at each isolated via3 point on a strap, then ONE global
# `editPowerVia -add_vias 1 -nets VDD -bottom_layer M2 -top_layer M3` —
# the engine vias every strap/M3-rect overlap (probe: direct pad targeting
# finds nothing; with the rect it generates; +2 layer-52 records in the
# A/B GDS). ADDITIVE ONLY. Clearance-checked against non-VDD M3; a skipped
# crossing is fine — a column needs only ONE live crossing.
set __ngshape 0
set __ngblock 0
set __ngskip 0
array unset __v12pt
array unset __v3pt
array unset __v3ptr
foreach __o [dbGet [dbGet -p top.nets.name VDD].sVias -e] {
	set __vn [string tolower [dbGet -e $__o.via.name]]
	set __k "[format %.2f [dbGet $__o.pt_x]]_[format %.2f [dbGet $__o.pt_y]]"
	if {[string match via1* $__vn] || [string match via2* $__vn]} { set __v12pt($__k) 1 }
	if {[string match via3* $__vn]} { set __v3pt($__k) 1 }
}
set __npre2 0
foreach __o [dbGet [dbGet -p top.nets.name VDD].sVias -e] {
	if {[dbGet -e $__o.via.cutLayer.name] eq "VIA2"} { incr __npre2 }
}
foreach __k [array names __v3pt] {
	if {[info exists __v12pt($__k)]} { continue }
	foreach {__gvx __gvy} [split $__k _] {}
	set __onstrap 0
	foreach __o [dbQuery -area [list [expr {$__gvx - 0.05}] [expr {$__gvy - 0.05}] [expr {$__gvx + 0.05}] [expr {$__gvy + 0.05}]] -objType sWire] {
		if {[dbGet -e $__o.layer.name] eq "M2" && [dbGet -e $__o.net.name] eq "VDD"} { set __onstrap 1; break }
	}
	if {!$__onstrap} { incr __ngskip; continue }
	set __r [list [expr {$__gvx - 0.10}] [expr {$__gvy - 0.04}] [expr {$__gvx + 0.10}] [expr {$__gvy + 0.04}]]
	set __chk [list [expr {$__gvx - 0.201}] [expr {$__gvy - 0.141}] [expr {$__gvx + 0.201}] [expr {$__gvy + 0.141}]]
	set __clear 1
	foreach __o [concat [dbQuery -area $__chk -objType wire] [dbQuery -area $__chk -objType sWire]] {
		if {[dbGet -e $__o.layer.name] ne "M3"} { continue }
		if {[dbGet -e $__o.net.name] eq "VDD"} { continue }
		set __clear 0; break
	}
	if {!$__clear} { incr __ngblock; continue }
	add_shape -net VDD -layer M3 -rect $__r -shape STRIPE -status ROUTED
	incr __ngshape
}
editPowerVia -add_vias 1 -nets VDD -bottom_layer M2 -top_layer M3 -orthogonal_only 0
set __npost2 0
foreach __o [dbGet [dbGet -p top.nets.name VDD].sVias -e] {
	if {[dbGet -e $__o.via.cutLayer.name] eq "VIA2"} { incr __npost2 }
}
set __nglink [expr {$__npost2 - $__npre2}]
puts "### UNL STATUS ### : PG4 strap-grid link repair — $__ngshape M3 pads laid ($__ngblock blocked by foreign M3, $__ngskip off-strap), engine created $__nglink VIA2s"
if {$__nglink < 1000} {
	puts "FATAL (PG4/F1): strap-grid link repair created only $__nglink VIA2s (expect ~2000) — the crossing-stack population or the editPowerVia mechanism changed. Saving dbs/pg4link_fail.innovus; aborting."
	saveDesign dbs/pg4link_fail.innovus
	exit 1
}

################################################################################
# PG4/F2 (2026-07-11, session 3) — strap-PIN link repair: the missing LAST
# HOP of the F1 fabric. The strap-grid repair above connects every strap UP
# to the M8 grid, but nothing ever connected the straps DOWN to the pins:
# the fabric-stage addStripe VIA1s do not survive to the final DB/GDS (the
# signoff DB has ZERO via1 sVias under 7 of 8 header-column straps; the
# GDS has zero layer-51 cuts under ANY strap — headers' VDDG hung on
# nwell diffusion only, LVS softchk nxwell 6596 and ~1631 unmatched layout
# nets were exactly this). Probe-proven fix (2026-07-11, restored signoff
# DB): per-column windowed `editPowerVia -add_vias 1 -nets VDD M1->M2
# -orthogonal_only 0` — the engine vias every sroute FINGER (M1 sWire,
# drawn ON the pin) x strap (M2) overlap: 52/52 header via1s in the test
# column, GDS-real (+60 layer-51 cuts), and the labeled LVS compare
# absorbed exactly the two probed columns' worth of unmatched nets (-103).
# Tap columns need a REAL M1 pad on each FILLBIAS VNW pin bar first
# (pin geometry is invisible to editPowerVia — the repeater lesson);
# orientation-aware (R0/MY bar y0+1.21..1.73, MX/R180 y0+0.27..0.79 —
# a full-height pad would short the VPW bar at the same x).
# Runs HERE (post-route, after the dead-row scrub) so no later stage can
# orphan or delete the vias. ADDITIVE ONLY.
################################################################################
proc pg4_count_via1 {x0 y0 x1 y1} {
	set n 0
	foreach o [dbQuery -area [list $x0 $y0 $x1 $y1] -objType sVia] {
		if {[dbGet -e $o.net.name] ne "VDD"} { continue }
		if {[string match -nocase via1* [dbGet -e $o.via.name]]} { incr n }
	}
	return $n
}
set __f2vias 0
set __f2covered 0
set __f2waived {}
foreach __pr $__placed_runs {
	foreach {__key __sx __ay0 __ay1} $__pr {}
	set __x0 [string range $__key 1 end]
	set __isH [expr {[string index $__key 0] eq "H"}]
	set __cells {}
	foreach __y $__colys($__key) {
		if {$__y >= [expr {$__ay0 - 1.5}] && $__y <= $__ay1} { lappend __cells $__y }
	}
	set __ncell [llength $__cells]
	if {$__ncell == 0} { continue }
	if {!$__isH} {
		foreach __i [dbGet -p2 top.insts.cell.name FILLBIASA10TH] {
			set __bx [lindex [dbGet $__i.box] 0]
			foreach {__ix0 __iy0 __ix1 __iy1} $__bx {}
			if {abs($__ix0 - $__x0) > 0.01} { continue }
			if {$__iy0 < [expr {$__ay0 - 1.5}] || $__iy0 > $__ay1} { continue }
			if {[pg4_dead_row $__bx]} { continue }
			set __or [dbGet $__i.orient]
			if {$__or eq "R0" || $__or eq "MY"} {
				set __py0 [expr {$__iy0 + 1.21}]; set __py1 [expr {$__iy0 + 1.73}]
			} else {
				set __py0 [expr {$__iy0 + 0.27}]; set __py1 [expr {$__iy0 + 0.79}]
			}
			add_shape -net VDD -layer M1 -shape STRIPE -status ROUTED \
				-rect [list [expr {$__ix0 + 0.15}] $__py0 [expr {$__ix0 + 0.25}] $__py1]
		}
	}
	set __w0 [expr {$__sx - 0.5}]
	set __w1 [expr {$__sx + 0.9}]
	set __b [pg4_count_via1 $__w0 $__ay0 $__w1 $__ay1]
	editPowerVia -add_vias 1 -nets VDD -bottom_layer M1 -top_layer M2 \
		-orthogonal_only 0 -area [list $__w0 $__ay0 $__w1 $__ay1]
	set __a [pg4_count_via1 $__w0 $__ay0 $__w1 $__ay1]
	incr __f2vias [expr {$__a - $__b}]
	# Gate = ABSOLUTE per-cell coverage in the STRAP x-sliver, not the pass
	# delta: fabric-stage via1s survive at seed-dependent spots (first F2
	# run: a pre-existing via on the H431 bottom-stub finger made delta 0
	# for a covered header and false-FATALed). The sliver [sx-0.1,sx+0.4]
	# also refuses credit to off-strap strays like v22c's col-351 x+1.235
	# via1 column (finger vias to nowhere — not strap connections).
	set __cellh [expr {$__isH ? 4.1 : 2.1}]
	foreach __y $__cells {
		set __nc [pg4_count_via1 [expr {$__sx - 0.1}] [expr {$__y - 0.1}] [expr {$__sx + 0.4}] [expr {$__y + $__cellh}]]
		if {$__nc >= 1} { incr __f2covered; continue }
		if {$__isH} {
			puts "FATAL (PG4/F2): header $__key y=$__y has no strap-pin via1 in the strap sliver. Saving dbs/pg4f2_fail.innovus; aborting."
			saveDesign dbs/pg4f2_fail.innovus
			exit 1
		}
		lappend __f2waived [list $__key $__sx $__y]
	}
}
puts "### UNL STATUS ### : PG4/F2 strap-pin link repair — $__f2vias via1s created this pass, $__f2covered cells strap-covered, [llength $__f2waived] taps naked (first 10: [lrange $__f2waived 0 9])"
if {$__f2covered < 1400} {
	puts "FATAL (PG4/F2): only $__f2covered strap-covered cells (expect ~977 headers + ~700 taps). Saving dbs/pg4f2_fail.innovus; aborting."
	saveDesign dbs/pg4f2_fail.innovus
	exit 1
}

# PG4 v21 POST-MORTEM — the v19/v20 "final both-net dangling-stack scrub"
# and "floating-stub sweep" that lived here are DELETED, and must never
# come back in point-group form: the exact-(x,y) grouping rule (via3..6
# present, no via1/2/7 at the same point) called ~5000 groups dangling
# while Innovus' own antenna markers flagged only ~2200 — the excess were
# CONNECTED staircase stacks whose via1/2 sit at OFFSET centers (sroute
# builds them pad-overlapping, not co-centered). Deleting them cut the
# VNW/VPW well-bias feeds: tile LVS lit up with softchk nxwell 6597
# (v11-with-fabric baseline: 0) and ~500 unmatched bulk-sensitive devices,
# and the deleted pads left 43 REAL Calibre min-area slivers. The in-flow
# VSS-only 698-group scrub ABOVE is kept — it predates v12 and the v11 LVS
# (nxwell 0) proves it harmless. The leftover ~950-marker verifyGeometry
# ANTENNA class is DOCUMENTED NOISE: foundry ant25 = 0 on every cut.
# If litter must ever be scrubbed again, drive it from the verifyGeometry
# MARKERS (or a pad-overlap-aware union walk), never from point groups.
################################################################################
# PG1 acceptance gate (2026-07-10) — the hard check behind the dont_touch:
# 1. every SLEEP-chain net (psoPSI_*, *_pg1rep, pd_sleep) carries ONLY
#    HEADBUF switch pins and GPGBUF AO-repeater pins — one PD_GATED core
#    cell here silently un-gates a column-tail (PG1 finding F1);
# 2. ram0's PGEN and RETN are driven straight from the tcm_pgen/tcm_retn
#    ports — their receivers are on the macro's ALWAYS-ON rail, so any
#    in-tile driver is a dying-rail driver (PG1 finding F2).
# Runs after every optimization step is done; FAILS THE RUN on violation.
################################################################################
printStatus "PG1 acceptance gate"
set pg1_bad 0
foreach np [concat [dbGet -p top.nets.name psoPSI_* -e] [dbGet -p top.nets.name *_pg1rep -e] [dbGet -p top.nets.name pd_sleep -e]] {
	foreach it [dbGet $np.instTerms -e] {
		set c [dbGet $it.inst.cell.name]
		if {![string match HEADBUF* $c] && ![string match GPGBUF* $c]} {
			incr pg1_bad
			puts "PG1 VIOLATION: foreign cell [dbGet $it.name] ($c) on chain net [dbGet $np.name]"
		}
	}
}
foreach {pin port} {PGEN tcm_pgen RETN tcm_retn} {
	set np [dbGet -p top.insts.name ram0]
	set it [dbGet -p $np.instTerms.name ram0/$pin]
	set nn [dbGet $it.net.name]
	if {$nn ne $port} {
		incr pg1_bad
		puts "PG1 VIOLATION: ram0/$pin is driven by net '$nn', expected the AO port net '$port'"
	}
}
if {$pg1_bad > 0} {
	puts "FATAL (PG1): $pg1_bad power-gating acceptance violations — aborting before signoff"
	exit 1
}
puts "### UNL STATUS ### : PG1 acceptance gate PASSED (chain pure, ram0 PG pins port-driven)"

################################################################################
# Signoff checks + reports
################################################################################
printStatus "verifyConnectivity"
verifyConnectivity \
    -error 100000 \
    -connectPadSpecialPorts \
    -report $REPORT_DIR/$DESIGN_NAME.verifyConnectivity.signoff.rpt

printStatus "verifyGeometry"
# PG4 v20: -error — the default 1000 cap TRUNCATED the v18/v19 signoff
# summaries (both reports stopped at exactly 1000; class counts under the
# cap are meaningless). The signoff numbers must be uncapped to be a
# baseline.
verifyGeometry \
    -antenna \
    -error 100000 \
    -warning 100000 \
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
