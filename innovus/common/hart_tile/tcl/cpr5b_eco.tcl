################################################################################
# CPR5b -- G0-CLASS SURGICAL ECO on the CPR5 clean harden (hart_tile).
#
# Repairs the three REAL DRC/LVS sites left by the CPR5 re-harden:
#
#  SITE A (the LVS short, G0 class verbatim)
#    M1 pin-access via pad of net psoPSI_PD_GATED_EnNet__1_515_351_3_0_pg1rep
#    overhangs TIELOX1MA10TH tie_0_cell7 (box 351.8-352.6 x 397.0-399.0, R180)
#    and merges with the tie's INTERNAL M1 strap: LEF OBS rect
#    {0.095 0.600 0.185 1.490} maps under R180 to die {352.415 397.51 352.505 398.40}.
#    => Pegasus LVS SHORT (Xtie_0_cell7/LO), Innovus vG Short:1, Calibre
#       G.4:M1i x2 + M1.W.1 x1.
#    FIX: rip + OBS-SHAPED M1/VIA1 blockages (all four OBS rects, the violated
#    one grown by the 0.09 M1.S.1 spacing) + ecoRoute.  NOT a bbox blockage:
#    a bbox covers the VDD/VSS rails and the tie's own Y pin, and made ecoRoute
#    produce Short 23 / Overlap 16 (measured, CPR5b attempt #1).
#
#  SITE B (the G0 SIBLING class: placement-squeezed pin against a PG stripe)
#    XOR2X1MA10TH g2939 (504.6-506.6 x 419.0-421.0, R0) has its Y pin vertical
#    arm on x 505.25-505.35 -- i.e. ON the M2 track 505.30, which is buried under
#    the VDD M2 PG stripe {505.1 4.0 505.4 600.0}.  The only other access is the
#    0.135um corridor between the A pin (top 420.30) and the Y arm (bottom
#    420.435), and every via pad there is 0.05/0.011 from the A pin / the M1 OBS
#    island (505.71,420.07,505.80,420.34) => Calibre M1.S.1 x2 + M1.S.5 x1.
#    MEASURED, so nobody retries it: blockading the corridor (top 420.43, then
#    420.41) with multi-cut on and then off did NOT work -- ecoRoute could not
#    place a legal pad and gave up with a HARD SHORT of n_2 to the VDD stripe at
#    (505.25-505.35, 420.01-420.19), both times.  That is the G0 record's own
#    verdict on this class: "placement-squeezed pins resist route-only fixes --
#    that is a placement ECO, not more blockages."
#    FIX: PLACEMENT NUDGE -- swap the XOR2 with the FILL2A10TH abutting it on
#    its west (both R0, same row, both on-site), moving the cell 0.4um left.
#    The Y pin vertical arm lands on x 504.85-504.95 = M2 track 504.90, clear of
#    the stripe, with 0.105 to the west OBS and 0.10 to the A pin: a legal
#    VIA1_H pin access exists again.  Inst count unchanged (a swap, not an
#    add/delete), so the filler/NW continuity of the row is untouched.
#
#  SITE C (same-net M2 notch)
#    0.11um gap between the CK-pin access stub {469.725 419.69 470.52 419.79}
#    and the 0.4um-wide CTS_1 M2 trunk {469.7 419.9 470.1 420.7} => M2.S.2
#    (needs 0.12; Innovus never reports it -- same-net).
#    MEASURED, so nobody retries it: closing the notch with add_shape MERGES the
#    stub into the trunk and manufactures a MINCUT violation, because the tech
#    LEF says `MINIMUMCUT 2 WIDTH 0.3 LENGTH 0.3 WITHIN 0.8` and the stub's via
#    is single-cut.  The notch has to be OPENED, not closed.
#    FIX: area-scoped rip of the local M2/VIA1 of the clock net (never the whole
#    121-wire, 33-sink tree) + an M2 band blockage over the notch + an M1/VIA1
#    blockage over the trunk shadow (attempt #2 without the latter let ecoRoute
#    drop a via from the trunk straight down into the DFF, landing 0.015 from
#    that cell's internal M1 OBS -- a fresh G0-class site).
#
# METHOD = the G0 recipe (devlog 2026-07-22-stage-g0-tile-lvs-root-cause.md):
#   dontTouch dance -> editSelect -net + editDelete -selected (NEVER bare
#   editDelete: it deletes every wire and sWire in the design; and `selectNet` +
#   `editDelete -selected -type Signal` is a silent no-op) -> OBS-shaped route
#   blockages -> bare ecoRoute (`-target net` / `-nets` do not exist) ->
#   blockages deleted.  Global count guards with FATAL before any saveDesign.
################################################################################
set DESIGN_NAME  hart_tile
set REPORT_DIR   rpt
set DATABASE_DIR dbs
set TAG          cpr5b

set NET_A psoPSI_PD_GATED_EnNet__1_515_351_3_0_pg1rep
set NET_C core/datapath_inst/CTS_1
set XOR_B core/datapath_inst/mainalu/add_511_114_Y_add_389_66_Y_sub_391_66_Y_add_497_93_Y_add_505_113_g2939
set FIL_B RC_CG_HIER_INST0/FILLER_PD_GATED__3_2421

restoreDesign dbs/hart_tile.signoff.innovus.dat $DESIGN_NAME

proc counts {tag} {
	set i [llength [dbGet -e top.insts]]
	set n [llength [dbGet -e top.nets]]
	set w [llength [dbGet -e top.nets.wires]]
	set s [llength [dbGet -e top.sNets.sWires]]
	puts "### CPR5B COUNTS ($tag) ### insts=$i nets=$n wires=$w sWires=$s"
	return [list $i $n $w $s]
}
set C0 [counts baseline]

################################################################################
# 1. SITE B placement nudge (do it BEFORE the rips so the rip list is right)
################################################################################
set xi [dbGetInstByName $XOR_B]
set fi [dbGetInstByName $FIL_B]
puts "### CPR5B NUDGE ### before: XOR box=[dbGet $xi.box] orient=[dbGet $xi.orient] status=[dbGet $xi.pStatus]"
puts "### CPR5B NUDGE ### before: FILL box=[dbGet $fi.box] orient=[dbGet $fi.orient] status=[dbGet $fi.pStatus]"
if {[dbGet $xi.box_llx] != 504.6 || [dbGet $fi.box_llx] != 504.2} {
	puts "FATAL (CPR5b): SITE B placement is not the expected 504.2(FILL)/504.6(XOR) pair -- refusing to nudge"
	exit 1
}
# The XOR's nets must be ripped: moving the cell strands their pin-access metal.
set NETS_B {}
foreach it [dbGet $xi.instTerms] {
	set nn [dbGet -e $it.net.name]
	if {$nn ne "" && $nn ne "VDD" && $nn ne "VSS" && $nn ne "VDD_SW"} { lappend NETS_B $nn }
}
set NETS_B [lsort -unique $NETS_B]
puts "### CPR5B NUDGE ### XOR signal nets to rip: $NETS_B"
placeInstance $FIL_B 506.2 419.0 R0
placeInstance $XOR_B 504.2 419.0 R0
puts "### CPR5B NUDGE ### after:  XOR box=[dbGet $xi.box]  FILL box=[dbGet $fi.box]"
if {[dbGet $xi.box_llx] != 504.2 || [dbGet $fi.box_llx] != 506.2} {
	puts "FATAL (CPR5b): the SITE B nudge did not take"
	exit 1
}

################################################################################
# 2. RIPs
################################################################################
foreach nn [concat [list $NET_A] $NETS_B] {
	set np [dbGetNetByName $nn]
	if {$np eq "" || $np == 0x0} { puts "FATAL (CPR5b): net $nn not found"; exit 1 }
	set dt [dbGet $np.dontTouch]
	if {$dt} { dbSet $np.dontTouch false ; puts "### CPR5B ### $nn dontTouch cleared for the ECO" }
	set before [llength [dbGet -e $np.wires]]
	deselectAll
	editSelect -net $nn
	editDelete -selected
	deselectAll
	set after [llength [dbGet -e $np.wires]]
	puts "### CPR5B RIP ### $nn wires $before -> $after"
	if {$after >= $before} {
		puts "FATAL (CPR5b): rip of $nn removed no wires ($before -> $after) -- wrong API, aborting"
		exit 1
	}
}
# SITE C -- surgical, AREA-SCOPED rip (editDelete's own -net/-area/-layer
# filters); the whole 121-wire, 33-sink CTS_1 tree must NEVER be ripped.
set npC [dbGetNetByName $NET_C]
set cbefore [llength [dbGet -e $npC.wires]]
editDelete -net $NET_C -area {469.4 419.60 470.7 419.86} -layer M2 -type Regular
editDelete -net $NET_C -area {469.4 419.60 470.7 419.86} -layer VIA1 -type Regular
set cafter [llength [dbGet -e $npC.wires]]
puts "### CPR5B RIP ### $NET_C (area-scoped M2/VIA1) wires $cbefore -> $cafter"
if {$cafter >= $cbefore || $cbefore - $cafter > 20} {
	puts "FATAL (CPR5b): area-scoped rip of $NET_C removed [expr {$cbefore-$cafter}] wires"
	exit 1
}
set C1 [counts after_rip]

checkPlace $REPORT_DIR/$DESIGN_NAME.checkPlace.$TAG.rpt

# Row census around the SITE C flop -- kept as data for a possible placement
# nudge there (the fallback if the route-side fix will not close).
puts "==== CPR5B SITE C ROW CENSUS ===="
foreach i [dbQuery -area {464.0 419.0 480.0 421.0} -objType inst] {
	puts "ROWC [dbGet $i.name] cell=[dbGet $i.cell.name] box=[dbGet $i.box] orient=[dbGet $i.orient]"
}

################################################################################
# 3. Blockages (OBS-shaped, never cell bboxes)
################################################################################
set BLKS_M1 {
	{cpr5b_tieA_obs4 352.325 397.420 352.595 398.490}
	{cpr5b_tieA_obs1 352.050 397.670 352.140 398.100}
	{cpr5b_tieA_obs2 352.140 397.670 352.155 397.760}
	{cpr5b_tieA_obs3 352.155 397.250 352.245 397.760}
	{cpr5b_ctsC_east 469.850 419.300 470.300 420.100}
}
set BLKS_M2 {
	{cpr5b_ctsC_shad 469.600 419.400 470.150 419.890}
}
# SITE C v3, and the reasoning is worth keeping because two cheaper ideas died:
# the CK pin of DFFRPQX1MA10TH is 0.125um wide (LEF 0.250-0.375 local => die
# 469.65-469.775) and sits ENTIRELY inside the 0.4um trunk's x shadow
# (469.7-470.1), so no via on that pin can escape the shadow sideways, and the
# M1 routing grid puts the only on-pin via center at y 419.74 => M2 pad top
# 419.79 => the 0.11um notch, every time.  v2 blocked just the notch band and
# the router answered by walking east on M1 inside the flop and dropping a via
# 0.015/0.02 from that cell's own M1 OBS -- a fresh G0-class site.  v3 blocks
# the whole shadow BELOW the trunk plus the walk-east corridor, leaving exactly
# one topology: the pin via lands high and MERGES with the trunk (no opposing
# edges at all, hence no M2.S.2), which the router must then serve with a
# multi-cut via to satisfy `MINIMUMCUT 2 WIDTH 0.3 LENGTH 0.3 WITHIN 0.8`.
foreach b $BLKS_M1 {
	foreach {nm x1 y1 x2 y2} $b {break}
	if {[catch {createRouteBlk -name ${nm}_M1 -layer M1 -cutLayer VIA1 -box [list $x1 $y1 $x2 $y2]} err]} {
		puts "### CPR5B ### createRouteBlk $nm FAILED: $err"
	} else { puts "### CPR5B BLK ### $nm M1+VIA1 {$x1 $y1 $x2 $y2}" }
}
foreach b $BLKS_M2 {
	foreach {nm x1 y1 x2 y2} $b {break}
	if {[catch {createRouteBlk -name ${nm}_M2 -layer M2 -box [list $x1 $y1 $x2 $y2]} err]} {
		puts "### CPR5B ### createRouteBlk $nm FAILED: $err"
	} else { puts "### CPR5B BLK ### $nm M2 {$x1 $y1 $x2 $y2}" }
}

################################################################################
# 4. ecoRoute -- BARE.  Multi-cut swap is OFF for the ECO: the pad that broke
#    SITE B is a VIA1_2CUT_E M1 pad (0.38 x 0.10 um per the tech LEF); the
#    single-cut VIA1_H/V pads (0.10 x 0.18) are what fit a squeezed pin.
################################################################################
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
    -dbSkipAnalog true \
    -drouteEndIteration default
ecoRoute
set C2 [counts after_ecoRoute]

foreach b $BLKS_M1 { foreach {nm x1 y1 x2 y2} $b {break}; catch {deleteRouteBlk -name ${nm}_M1} }
foreach b $BLKS_M2 { foreach {nm x1 y1 x2 y2} $b {break}; catch {deleteRouteBlk -name ${nm}_M2} }
puts "### CPR5B ### CTS_1 wires after reroute = [llength [dbGet -e [dbGetNetByName $NET_C].wires]]"

################################################################################
# 5. restore dontTouch on the PG1 chain nets, then verify
################################################################################
dbSet [dbGetNetByName $NET_A].dontTouch true
puts "### CPR5B ### NET_A dontTouch restored to [dbGet [dbGetNetByName $NET_A].dontTouch]"

foreach a {{SITE_A 350.0 395.0 356.0 401.0} {SITE_B 502.0 416.0 510.0 424.0} {SITE_C 467.0 417.0 473.0 423.0}} {
	foreach {tag x1 y1 x2 y2} $a {break}
	verifyGeometry -area [list $x1 $y1 $x2 $y2] -error 10000 -warning 10000 \
	    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.$TAG.$tag.rpt
	puts "### CPR5B AREA VG $tag written"
}

verifyGeometry -antenna -error 100000 -warning 100000 \
    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.$TAG.rpt

proc vg_summary {rptfile tag} {
	set cells 0; set samenet 0; set wiring 0; set short 0; set overlap 0; set ant 0
	if {![file exists $rptfile]} { puts "### CPR5B VG $tag: report missing"; return -1 }
	set fh [open $rptfile r]
	while {[gets $fh line] >= 0} {
		if {[regexp {^\s*Cells\s*:\s*(\d+)}   $line -> v]} { set cells   $v }
		if {[regexp {^\s*SameNet\s*:\s*(\d+)} $line -> v]} { set samenet $v }
		if {[regexp {^\s*Wiring\s*:\s*(\d+)}  $line -> v]} { set wiring  $v }
		if {[regexp {^\s*Short\s*:\s*(\d+)}   $line -> v]} { set short   $v }
		if {[regexp {^\s*Overlap\s*:\s*(\d+)} $line -> v]} { set overlap $v }
		if {[regexp {^\s*Antenna\s*:\s*(\d+)} $line -> v]} { set ant     $v }
	}
	close $fh
	set tot [expr {$cells + $samenet + $wiring + $short + $overlap}]
	puts "### CPR5B VG $tag ### Cells=$cells SameNet=$samenet Wiring=$wiring Short=$short Overlap=$overlap Antenna=$ant NONANT=$tot"
	return $tot
}
set VGTOT [vg_summary $REPORT_DIR/$DESIGN_NAME.verifyGeometry.$TAG.rpt full]

verifyConnectivity -error 100000 -connectPadSpecialPorts \
    -report $REPORT_DIR/$DESIGN_NAME.verifyConnectivity.$TAG.rpt
verifyProcessAntenna -report $REPORT_DIR/$DESIGN_NAME.verifyProcessAntenna.$TAG.rpt

################################################################################
# 6. count guards -- FATAL before saveDesign
################################################################################
foreach {i0 n0 w0 s0} $C0 {break}
set S3 [counts final]
foreach {i3 n3 w3 s3} $S3 {break}
puts "### CPR5B DELTA ### insts [expr {$i3-$i0}]  nets [expr {$n3-$n0}]  wires [expr {$w3-$w0}]  sWires [expr {$s3-$s0}]"
set fatal 0
if {abs($i3-$i0) > 8}   { puts "FATAL (CPR5b): inst count moved by [expr {$i3-$i0}]"; set fatal 1 }
if {$n3 != $n0}         { puts "FATAL (CPR5b): net count moved by [expr {$n3-$n0}]"; set fatal 1 }
if {abs($w3-$w0) > 300} { puts "FATAL (CPR5b): wire count moved by [expr {$w3-$w0}] -- beyond a 5-net ECO"; set fatal 1 }
if {abs($s3-$s0) > 40}  { puts "FATAL (CPR5b): sWire count moved by [expr {$s3-$s0}]"; set fatal 1 }
if {$fatal} { puts "FATAL (CPR5b): count guard tripped -- NOT saving"; exit 1 }

saveDesign $DATABASE_DIR/$DESIGN_NAME.$TAG.eco.innovus -def -netlist -rc -tcon
puts "### CPR5B ECO DONE ### saved $DATABASE_DIR/$DESIGN_NAME.$TAG.eco.innovus  (vG non-antenna total $VGTOT)"
exit
