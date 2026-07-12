################################################################################
# Innovus script -- ARGUS hart_tile COMPACT-TILE HARDEN (A4 physical flow)
#
# ARGUS variant of tcl/hart_tile.innovus.tcl. The Argus tile is a PLAIN
# RECTANGLE -- no analog potentiostat notch, no U-shape, no fingers (Argus is
# digital-only; the Castalia 500x450 analog reserve dies here). The die packs
# a 6-col x 3-row grid of these tiles on the 2690x2690 M15 interior, so the
# tile is sized WIDTH-bound (<=~440 to fit 6 columns) and HEIGHT-bound
# (<=~735 to fit 3 rows + a bottom RAM/control band).
#
# Floorplan: one sram1p16k TCM (R0, the near-square area-optimized mux-8 macro
# 319.65 x 383.085) jammed at the bottom-center; std-cell rows fill the space
# ABOVE it; the M17 MTCMOS header fabric + tap overhead sits in those rows.
# All tile pins on the BOTTOM edge (M4), same as the Castalia tile -- the
# arbiter/control plane lives below the tile grid at assembly, and each tile's
# shared-bus + IRQ pins drop down through the inter-tile channels.
#
# INPUTS: ../../genus/out/hart_tile_argus.genus.{v,sdc} (SH_AW=16, 16-bit
# sh_addr). OUTPUTS carry the _argus basename so the Castalia tile artifacts
# (out/hart_tile.*, SH_AW=15, U-shape) stay pristine. The MODULE/MACRO name is
# plain "hart_tile" (the Argus assembly instantiates it 18x).
#
# LOAD-BEARING M17b/PG1 lessons carried forward from the Castalia tile:
#   * checkerBoard power switch is mandatory (full-density = ~1000 pmk M1
#     pin-frame shorts). It leaves a FEW rows switchless (dead VDD_SW rail).
#   * dead switchless rows must be hard-blocked BEFORE place_opt (after
#     addPowerSwitch phase-shifts if blocked earlier; after sroute strands
#     well-tap frames if blocked later) so place_opt parks no live cell on a
#     dead rail. THE COMPACT-TILE DEAD-ROW SET IS RE-DERIVED PROGRAMMATICALLY
#     here (detect switchless rows from actual switch placement) instead of
#     the U-shape's hardcoded 2 rows -- the rectangle's casualties differ.
#   * addPowerSwitch/addRing/sroute FAIL SOFT -- hard NSW/PG1 guards abort.
#   * sViaInst objects have pt, NOT box -- filter vias on pt_y, wires on box.
#   * PG1: GPGBUF AO repeaters into long SLEEP-chain links over the TCM;
#     dont_touch the chain; a hard acceptance gate before signoff.
#
# Outputs (out/): hart_tile_argus.{gds2,sdf,xsim.v,lef} + .ilm + per-corner
# .etm_{ss,ff}.lib -- feed the Argus assembly (viewdefinition_top_argus).
################################################################################

source tcl/constants.tcl
source $SCRIPT_DIR/procedures.tcl

# Flushing logger -- Innovus buffers bare `puts`, so an abort (or exit 1) can
# SWALLOW the last instrumentation/FATAL lines (they never reach the log). Use
# plog for every status/guard message so what happened is always visible.
proc plog {msg} { puts $msg; flush stdout }

set DESIGN_NAME hart_tile
set OUT_NAME    hart_tile_argus

# --- Compact rectangular geometry (A4; shortened for the assembly) ---
# 405 x 685 = 0.277 mm^2 (was 730). SHORTENED so the 18-tile assembly can afford
# a full-width control BAND below the tiles + 40 um inter-tile column gaps (the
# 730 tile forced a congesting left strip + 10 um gaps -> ~48% V overflow). At
# 685 the upper rows run ~78% density (66k cells / ~90k um^2) -- higher than the
# 730 tile's 67% but still routable for this small core+adddec block.
# The R0 TCM (319.65 wide) sits in the bottom band; the
# ENTIRE bottom band (TCM + the thin side strips beside it) is cutRow'd so NO
# std-cell rows live there -- all logic goes in the FULL-WIDTH rows ABOVE the
# TCM. This sidesteps the side-strip dead-rail trap: a macro splits the rows
# beside it into short separate segments, and the checkerboard switch fabric
# leaves ALTERNATING such segments switchless (dead VDD_SW rail) no matter how
# wide the tile -- their rails are NOT continuous with the main row. Above the
# TCM every row spans the full width, its rail is one continuous net powered by
# any switch in the row, and only the checkerboard's ~2 boundary rows go dead
# (detected + blocked below). Routing channels beside the TCM stay OPEN (cutRow
# removes rows, not routing). ~66k um^2 of cells in ~133k um^2 of upper rows =
# ~50% density -- comfortable. Width fits 6 columns with wide margins; height
# fits 3 rows + a ~450 bottom band. Measure the ACTUAL density and shrink toward
# the 20-core decision (A4 stretch; 20 also needs a SHORTER tile -- 4 rows cap
# height ~640, out of reach for this 730-tall R0 layout).
set DESIGN_WIDTH  405
set DESIGN_HEIGHT 685

# Power ring / stripe geometry (Myshkin/M17 values -- proven; keep on cut 1).
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
set init_verilog             "$GENUS_DIR/out/$OUT_NAME.genus.v"
set init_top_cell            "$DESIGN_NAME"
set init_pwr_net             "VDD"
set init_gnd_net             "VSS"
set init_mmmc_file           "$SCRIPT_DIR/viewdefinition_tile_argus.tcl"

set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10-pmk/lef/tsmc65hvt_adv10pmk_macro.lef \
					$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef"

set init_design_uniquify 1
init_design

################################################################################
# M17 power intent -- identical CPF to the Castalia tile (same ports/domains:
# PD_GATED default/shutoff=pd_sleep + PD_AO for ports/iso; VDD always-on,
# VDD_SW the switched follow-pin net). SH_AW does not touch power intent.
################################################################################
read_power_intent -cpf ../../cpf/hart_tile.cpf
commit_power_intent
printStatus "Power intent committed (PD_GATED/PD_AO, switched net VDD_SW)"

setDesignMode -process 65 -flowEffort standard -powerEffort low
printStatus "Preparing 8 CPU cores..."
setMultiCpuUsage -acquireLicense 8 -localCpu 8

# M17: plain (tapless) FILL cells only; well-tap duty = the FILLBIAS addWellTap
# pass (a rail-tied tap in a gated row back-feeds the dead VDD_SW rail).
setFillerMode \
    -corePrefix FILLER \
    -core {FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH}

setAnalysisMode -analysisType onChipVariation -cppr both

# M17 domain-aware global nets. PD_GATED rows = switched net VDD_SW; ram0
# ties AO VDD (self-gates via native PGEN mirrored on tcm_pgen at MCU level);
# secondary pmk pins (VDDG/VNW/VPW) connected AFTER the switch/tap cells exist.
clearGlobalNets
globalNetConnect VDD_SW -type pgpin -pin VDD  -powerDomain PD_GATED -autoTie -verbose
globalNetConnect VDD    -type pgpin -pin VDD  -powerDomain PD_AO    -verbose
globalNetConnect VDD    -type pgpin -pin VDD  -singleInstance ram0 -override -verbose
globalNetConnect VSS    -type pgpin -pin VSS  -inst * -module {} -autoTie -verbose

################################################################################
# Floorplan: a PLAIN RECTANGLE (no polygon, no notch). TCM R0 bottom-center.
################################################################################
floorPlan \
    -site TSMC65ADV10TSITE \
    -s $CORE_WIDTH $CORE_HEIGHT $CORE_SPACING $CORE_SPACING $CORE_SPACING $CORE_SPACING
initCoreRow
printStatus "Floorplanned plain rectangle ($DESIGN_WIDTH x $DESIGN_HEIGHT)"

set SRAM16K_WIDTH		319.650
set SRAM16K_HEIGHT		383.085

# TCM centered in X, at the bottom (R0, pins on its native edge). y=12 clears
# the bottom ring band; the 383-tall macro tops out ~y=395, leaving rows above.
set TCM_X	[expr {($DESIGN_WIDTH - $SRAM16K_WIDTH) / 2.0}]
set TCM_Y	12
placeInstance ram0 $TCM_X $TCM_Y R0
addHaloToBlock \
    [expr {$STD_CELL_HEIGHT * 1}] \
    [expr {$STD_CELL_HEIGHT * 1}] \
    [expr {$STD_CELL_HEIGHT * 1}] \
    [expr {$STD_CELL_HEIGHT * 1}] \
    ram0
cutRow
# Remove the ENTIRE bottom band (TCM + the thin side strips beside it) so no
# std-cell rows survive there -- see the geometry note. CRITICAL: `cutRow -area`
# only cuts rows that sit UNDER AN OBSTACLE (macro/blockage) inside the area, so
# a bare `cutRow -area` over the band leaves the side-strip rows (nothing above
# them) ALIVE -- their segments then get uneven checkerboard coverage (98 dead
# segments, first cut). Create a hard PLACEMENT BLOCKAGE over the band first
# (the MCU_MP.innovus createPlaceBlockage->cutRow pattern), THEN cutRow removes
# the rows under it. Band top = TCM top + halo, clear of the row grid.
set TCM_BAND_TOP [expr {$TCM_Y + $SRAM16K_HEIGHT + ($STD_CELL_HEIGHT * 2)}]
createPlaceBlockage -type hard -name tcm_band -box [list 0 0 $DESIGN_WIDTH $TCM_BAND_TOP]
cutRow -area [list 0 0 $DESIGN_WIDTH $TCM_BAND_TOP]
# Diagnostic: confirm the band is now row-free (rows only above TCM_BAND_TOP).
set band_rows 0
foreach r [dbGet top.fplan.rows -e] {
	if {[dbGet $r.box_lly] < [expr {$TCM_BAND_TOP - 0.5}]} { incr band_rows }
}
plog "### UNL STATUS ### : bottom band 0..$TCM_BAND_TOP blocked+cut -- $band_rows rows remain in band (want 0)"
if {$band_rows > 0} {
	plog "FATAL (A4): $band_rows rows survived in the TCM band -- cutRow did not clear it"
	exit 1
}
printStatus "Placed TCM macro (R0, bottom-center) + cleared bottom band"

# All tile pins on the BOTTOM edge (M4, vertical-preferred): at assembly the
# arbiter/control plane is below the tile grid.
set ALL_PINS [dbGet top.terms.name]
puts "Assigning [llength $ALL_PINS] pins to the bottom edge"
editPin -pin $ALL_PINS -side Bottom -layer 4 -spreadType side -spacing 1 -fixOverlap 1
printStatus "Placed tile pins"

################################################################################
# Power: full rectangular ring (all 4 sides) + M7/M8 stripe grid
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
# M17 MTCMOS header fabric. HEADBUF16M columns every 80 um, switch in every
# row (-skipRows 0), -checkerBoard true (LOAD-BEARING: full-density = ~1000
# pmk M1 pin-frame shorts). The checkerboard stagger leaves a FEW boundary
# rows switchless -- detected + blocked below (re-derived for this shape).
# -area is the UPPER placeable region ONLY (above TCM_BAND_TOP): the bottom
# band is blocked+cut (no live logic), so it needs no switch fabric, and
# addStripe/etc. re-fracture the band rows after our cutRow anyway -- switching
# only the upper block keeps the fabric where the logic actually is.
################################################################################
printStatus "Inserting MTCMOS header switch columns (HEADBUF16MA10TH)"
addPowerSwitch -column -powerDomain PD_GATED \
	-globalSwitchCellName {HEADBUF16MA10TH} \
	-area [list $CORE_SPACING $TCM_BAND_TOP [expr {$DESIGN_WIDTH - $CORE_SPACING}] [expr {$DESIGN_HEIGHT - $CORE_SPACING}]] \
	-leftOffset 30 \
	-horizontalPitch 80 \
	-skipRows 0 \
	-checkerBoard true \
	-enableNetIn pd_sleep \
	-enableNetOut pd_sleep_chain_out

# addPowerSwitch FAILS SOFT (IMPPSO-109) -- a zero-switch tile sails to signoff
# with an unpowered VDD_SW net and only dies at the assembly gate sim. Iterate
# ACTUAL switch instances (NOT `dbGet -p top.insts.cell.name` -- that -p form
# returns the shared libCell, on which .box_lly is invalid).
set sw_insts {}
foreach inst [dbGet top.insts -e] {
	if {[dbGet $inst.cell.name] eq "HEADBUF16MA10TH"} { lappend sw_insts $inst }
}
set NSW [llength $sw_insts]
plog "### UNL STATUS ### : $NSW HEADBUF16MA10TH power switches inserted"
if {$NSW == 0} {
	plog "FATAL (A4): addPowerSwitch inserted ZERO switches -- aborting"
	exit 1
}

################################################################################
# RE-DERIVE THE DEAD-ROW CONTRACT (compact rectangle). Detect every core row
# with NO switch on it -- its VDD_SW follow-pin rail is dead. Store the boxes
# now (switch placement is final); the BLOCKAGES are created just before
# place_opt (position is load-bearing -- see there). This replaces the U-tile's
# hardcoded 2 rows: the rectangle's checkerboard casualties differ and must be
# measured, not assumed.
################################################################################
set ROW_H $STD_CELL_HEIGHT
# switch row y-origins (from the real instances collected above; snap 0.001 um)
set sw_ys {}
foreach c $sw_insts {
	lappend sw_ys [format %.3f [dbGet $c.box_lly]]
}
set sw_ys [lsort -unique $sw_ys]
# all core-row y-origins
set all_row_ys {}
foreach r [dbGet top.fplan.rows -e] {
	set ry [format %.3f [dbGet $r.box_lly]]
	if {[lsearch -exact $all_row_ys $ry] >= 0} { continue }
	lappend all_row_ys $ry
}
set all_row_ys [lsort -unique $all_row_ys]
plog "### UNL STATUS ### : [llength $all_row_ys] distinct core rows, [llength $sw_ys] rows carry a switch"
# Guard the row accessor: an empty set means dbGet top.fplan.rows is the wrong
# path in this build (would silently yield NDEAD=0 and route on dead rails).
if {[llength $all_row_ys] == 0} {
	plog "FATAL (A4): zero core rows from 'dbGet top.fplan.rows' -- wrong accessor, fix before routing"
	exit 1
}
# Partition switchless rows: rows in the BOTTOM BAND (< TCM_BAND_TOP) are
# already inside the tcm_band placement blockage -- NO live logic can sit there,
# so their dead VDD_SW rails are harmless (scrubbed at signoff, not blocked
# again). Rows in the UPPER placeable block are the real casualties: the
# checkerboard leaves ~2 boundary rows dead there, and those MUST be blocked so
# place_opt parks nothing live on them. Only the UPPER count feeds the FATAL.
set dead_row_boxes {}
set band_dead_boxes {}
foreach ry $all_row_ys {
	set covered 0
	foreach sy $sw_ys { if {abs($ry - $sy) < 0.01} { set covered 1; break } }
	if {$covered} { continue }
	set bx [list 0 $ry $DESIGN_WIDTH [expr {$ry + $ROW_H}]]
	if {$ry < [expr {$TCM_BAND_TOP - 0.5}]} {
		lappend band_dead_boxes $bx
	} else {
		lappend dead_row_boxes $bx
		plog "DEAD-ROW: switchless UPPER row at y=$ry (VDD_SW rail dead) -> will block"
	}
}
set NDEAD [llength $dead_row_boxes]
set NBAND [llength $band_dead_boxes]
plog "### UNL STATUS ### : $NDEAD switchless UPPER dead rows (block), $NBAND band dead rows (blocked by tcm_band, scrub only)"
# Sanity: the checkerboard should leave only a HANDFUL of upper rows dead. A
# large count means the stagger/pitch is wrong -- refuse to route blind.
if {$NDEAD > 8} {
	plog "FATAL (A4): $NDEAD switchless UPPER rows -- checkerboard/detection anomaly, inspect before routing"
	exit 1
}

# M17: well taps (FILLBIAS, not FILLTIE -- a rail-tied tap back-feeds the dead
# VDD_SW rail through the well). Bias pins must exist before the secondary
# sroute below.
addWellTap \
    -cell FILLBIASA10TH \
    -cellInterval 24 \
    -fixedGap \
    -checkerBoard \
    -prefix WELLTAP

# pmk secondary pins -- now that switch + tap instances exist. -type net (NOT
# pgpin): the pmk LEF gives VDDG/VNW/VPW no USE power/ground class, so a pgpin
# rule matches nothing (IMPDB-1221).
globalNetConnect VDD -type net -pin VDDG -inst * -module {} -verbose
globalNetConnect VDD -type net -pin VNW  -inst * -module {} -verbose
globalNetConnect VSS -type net -pin VPW  -inst * -module {} -verbose

printStatus "Routing power rails"
setSrouteMode -corePinMaxViaScale "100 10"
sroute \
	-nets { VSS VDD VDD_SW } \
	-allowLayerChange 0 \
	-allowJogging 0 \
	-connect corePin \
    -corePinWidth 0.3

printStatus "Routing secondary power pins (VDDG / VNW / VPW)"
sroute \
	-nets { VDD VSS } \
	-connect { secondaryPowerPin } \
	-secondaryPinNet { VDD VSS } \
	-allowLayerChange 1 \
	-allowJogging 1 \
	-layerChangeRange { M1(1) M4(4) }

################################################################################
# PG1 F1: ALWAYS-ON GPGBUF repeaters for long SLEEP-chain links (the chains
# that jump over the ram0 macro). An ordinary inverter pair on VDD_SW dies with
# the rail it gates. Splice a GPGBUFX4 (VDDG-powered AO buffer) into every link
# longer than PG1_LINK_THRESH. Runs AFTER the main secondary sroute (a GPGBUF
# present during it trips IMPSR-503 and the whole pass silently does nothing).
################################################################################
printStatus "PG1: splicing GPGBUF AO repeaters into long SLEEP-chain links"
set PG1_LINK_THRESH 150.0
set PG1_NREP 0
foreach np [dbGet -p top.nets.name psoPSI_* -e] {
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
	puts "PG1: link $netname ($drvinst -> $ldinst) is ${dist}um -- splicing $repname"
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
	puts "WARNING (PG1): no long SLEEP-chain links found -- floorplan changed? Verify the chain."
}
# Freeze the enable chain + macro PG-control nets against opt (dbSet, not
# setAttribute -- -dont_touch is not an option in 20.12; verify it took).
foreach np [dbGet -p top.nets.name psoPSI_* -e] {
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
if {$PG1_NREP > 0} {
	globalNetConnect VDD -type net -pin VDDG -inst pgaorep_* -module {} -verbose
	globalNetConnect VSS -type net -pin VSSG -inst pgaorep_* -module {} -verbose
}

verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$OUT_NAME.verifyGeometry.preplace.rpt
fixVia -short
fixVia -minCut
fixVia -minStep

# Reserve M7/M8 for power during signal routing.
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -layer 7
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -layer 8

################################################################################
# Placement
################################################################################
# DEAD-ROW BLOCKAGES -- created HERE (after everything upstream, just before
# place_opt): before addPowerSwitch they shift its checkerboard phase (the
# uncovered rows MOVE); before sroute they suppress the blocked rows' follow-
# pin rails and strand the dead-row well-tap VDD frames. The boxes were
# DETECTED above from the actual switch placement (compact-tile re-derivation).
foreach {b} $dead_row_boxes {
	set nm dead_row_[format %.0f [expr {[lindex $b 1] * 10}]]
	createPlaceBlockage -type hard -name $nm -box $b
}
printStatus "Blocked $NDEAD switchless dead-rail rows (detected)"

place_opt_design
printStatus "Placement done"

# ACCEPTANCE (post-place): no live cell may sit on a dead switchless row.
set park_bad 0
foreach {b} $dead_row_boxes {
	foreach __i [dbQuery -area $b -objType inst -e] {
		set c [dbGet $__i.cell.name]
		# fillers/taps/switches are allowed on a dead row; live logic is not
		if {[string match FILL* $c] || [string match WELLTAP* $c] || [string match HEADBUF* $c] || [string match FILLBIAS* $c]} { continue }
		incr park_bad
		plog "DEAD-ROW VIOLATION: live cell [dbGet $__i.name] ($c) parked on blocked row [lindex $b 1]"
	}
}
if {$park_bad > 0} {
	plog "FATAL (A4): $park_bad live cells on dead switchless rows -- blockage set is wrong"
	exit 1
}
plog "### UNL STATUS ### : dead-row placement acceptance PASSED ($NDEAD rows clean)"

# PG1 F1: hook the GPGBUF repeaters' AO supply pins now that place_opt has
# legalized them.
if {[info exists PG1_NREP] && $PG1_NREP > 0} {
	printStatus "PG1: routing the GPGBUF repeaters' secondary AO pins"
	sroute \
		-nets { VDD VSS } \
		-connect { secondaryPowerPin } \
		-secondaryPinNet { VDD VSS } \
		-allowLayerChange 1 \
		-allowJogging 1 \
		-layerChangeRange { M1(1) M4(4) } \
		-powerDomains PD_GATED \
		-inst [dbGet [dbGet -p top.insts.name pgaorep_*].name]
}

################################################################################
# Clock tree synthesis (mclk from clk; clk_cpu a generated clock through
# vesta's ClkGate -- ccopt traces it)
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
timeDesign -postCTS -expandedViews -outDir $REPORT_DIR/$OUT_NAME.timeDesign.postcts
report_ccopt_clock_trees -file $REPORT_DIR/$OUT_NAME.report_ccopt_clock_trees.postcts
report_ccopt_skew_groups -file $REPORT_DIR/$OUT_NAME.report_ccopt_skew_groups.postcts
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
    -drouteAntennaEcoListFile $REPORT_DIR/$OUT_NAME.routeDesign.diodes.txt \
    -dbSkipAnalog true \
    -drouteEndIteration default
routeDesign

optDesign -postRoute -setup -hold

verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$OUT_NAME.verifyGeometry.postroute.rpt
ecoRoute -fix_drc
verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$OUT_NAME.verifyGeometry.postroute.rpt

deleteAllRouteBlks
addFiller

# M17b: scrub the detected dead-rail rows BARE before signoff. Blockages kept
# logic out, but addWellTap left FILLBIAS taps on them and the dead VDD_SW rail
# stubs flag as zero-area antenna markers + dangling wires once nothing abuts.
# Delete leftover insts on each dead row first, then the rail stub (deleting
# the rail out from under a FILLBIAS re-strands its net-tied VDD frame).
foreach {b} $dead_row_boxes {
	set ry [lindex $b 1]
	set y0 [expr {$ry + 0.2}]
	set y1 [expr {$ry + $ROW_H - 0.2}]
	foreach __i [dbQuery -area [list 0 $y0 $DESIGN_WIDTH $y1] -objType inst -e] {
		set iy [dbGet $__i.pt_y]
		if {$iy >= $ry - 0.1 && $iy <= $ry + 0.1} { deleteInst [dbGet $__i.name] }
	}
	editDelete -net VDD_SW -area [list 0 [expr {$ry + 0.1}] $DESIGN_WIDTH [expr {$ry + $ROW_H - 0.1}]]
}
# Scrub the BOTTOM BAND bare too: it holds no live logic (tcm_band blockage) and
# the switch fabric never reached it (-area above TCM_BAND_TOP), so any VDD_SW
# follow-pin rails there are dead stubs, plus any stray FILL/tap the flow left
# in the blocked rows. Delete band insts (except the TCM macro + its abutting
# VDD frames) then the dead VDD_SW rails in one shot; VDD (ram0) + signal routes
# in the channels beside the TCM are untouched.
foreach __i [dbQuery -area [list 0 1 $DESIGN_WIDTH [expr {$TCM_BAND_TOP - 0.1}]] -objType inst -e] {
	set c [dbGet $__i.cell.name]
	if {$c eq "sram1p16k_hvt_pg"} { continue }
	if {[string match FILL* $c] || [string match WELLTAP* $c] || [string match FILLBIAS* $c]} {
		deleteInst [dbGet $__i.name]
	}
}
editDelete -net VDD_SW -area [list 0 1 $DESIGN_WIDTH [expr {$TCM_BAND_TOP - 0.1}]]
printStatus "Scrubbed $NDEAD upper dead rows + the bottom band bare"

################################################################################
# PG1 acceptance gate -- the hard check behind the dont_touch:
# 1. every SLEEP-chain net carries ONLY HEADBUF switch pins + GPGBUF AO-repeater
#    pins (one PD_GATED core cell silently un-gates a column tail);
# 2. ram0 PGEN/RETN driven straight from the tcm_pgen/tcm_retn AO ports.
# FAILS THE RUN on violation.
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
	puts "FATAL (PG1): $pg1_bad power-gating acceptance violations -- aborting before signoff"
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
    -report $REPORT_DIR/$OUT_NAME.verifyConnectivity.signoff.rpt

printStatus "verifyGeometry"
verifyGeometry \
    -antenna \
    -report $REPORT_DIR/$OUT_NAME.verifyGeometry.signoff.rpt

printStatus "verifyProcessAntenna"
verifyProcessAntenna \
    -report $REPORT_DIR/$OUT_NAME.verifyProcessAntenna.signoff.rpt

setDelayCalMode -SIAware false
setAnalysisMode -analysisType onChipVariation -cppr both
printStatus "timeDesign signoff"
timeDesign \
    -si \
    -signoff \
    -outdir $REPORT_DIR/$OUT_NAME.timeDesign.signoff.rpt

report_clock_timing \
    -type skew \
    -nworst 10 > $REPORT_DIR/$OUT_NAME.report_clock_timing.skew.signoff.rpt

setAnalysisMode -checkType hold -skew true
report_timing > $REPORT_DIR/$OUT_NAME.report_timing.hold.signoff.rpt
setAnalysisMode -checkType setup -skew true
report_timing > $REPORT_DIR/$OUT_NAME.report_timing.setup.signoff.rpt

reportGateCount \
    -level 2 \
    -outfile $REPORT_DIR/$OUT_NAME.reportGateCount.signoff.rpt
summaryReport \
    -noHtml \
    -outfile $REPORT_DIR/$OUT_NAME.summaryReport.signoff.rpt

saveDesign $DATABASE_DIR/$OUT_NAME.signoff.innovus -def -netlist -rc -tcon

################################################################################
# Output files: GDS, SDF, sim netlist, ILM, LEF abstract, per-corner ETMs
################################################################################
streamOut \
    $OUTPUT_DIR/$OUT_NAME.gds2 \
    -libName WorkLib \
    -structureName $DESIGN_NAME \
    -stripes 1 \
    -units 1000 \
    -mode ALL \
    -mapFile $INPUT_DIR/innovus2gds.map

printStatus "Writing SDF file"
write_sdf $OUTPUT_DIR/$OUT_NAME.sdf

printStatus "Writing verilog for Xcelium"
saveNetlist \
    $OUTPUT_DIR/$OUT_NAME.xsim.v \
    -excludeCellInst ANTENNA2A10TH

printStatus "Writing ILM"
createInterfaceLogic \
    -hold \
    -dir $OUTPUT_DIR/$OUT_NAME.ilm

printStatus "Writing LEF abstract"
lefOut \
    -StripePin \
    -PGpinLayers 7 8 \
    -specifyTopLayer 8 \
    $OUTPUT_DIR/$OUT_NAME.lef

# Per-corner ETMs (.lib) -- do_extract_model characterizes only the corner
# whose view is active for BOTH setup and hold, so force each in turn.
printStatus "Extracting per-corner ETMs (both-views-active recipe)"
set_analysis_view -setup [list setup_analysis_view] -hold [list setup_analysis_view]
if {[catch {do_extract_model -view setup_analysis_view $OUTPUT_DIR/$OUT_NAME.etm_ss.lib} etm_err]} {
	puts "ETM ss extraction FAILED: $etm_err"
} else {
	puts "ETM written to $OUTPUT_DIR/$OUT_NAME.etm_ss.lib"
}
set_analysis_view -setup [list hold_analysis_view] -hold [list hold_analysis_view]
if {[catch {do_extract_model -view hold_analysis_view $OUTPUT_DIR/$OUT_NAME.etm_ff.lib} etm_err]} {
	puts "ETM ff extraction FAILED: $etm_err"
} else {
	puts "ETM written to $OUTPUT_DIR/$OUT_NAME.etm_ff.lib"
}
set_analysis_view -setup [list setup_analysis_view] -hold [list hold_analysis_view]

saveDesign $DATABASE_DIR/$OUT_NAME.final.innovus -def -netlist -rc -tcon
toc
printStatus "hart_tile ARGUS compact-tile harden complete"
exit
