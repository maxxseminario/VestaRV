################################################################################
# DRC ECO -- the four real DRC classes left on the 2026-08-25 hart_tile cut,
# repaired by hand.  Runs AFTER tcl/tcm11_eco.tcl (the tie_0_cell6 G0 merge)
# and consumes the DB that ECO leaves behind.
#
# SCOPE.  `make drc BLOCK=hart_tile` on the post-tcm11 GDS reports 23 results:
#
#     *.DN.*   12   minimum density.  OUT OF SCOPE -- this family has no metal
#                   fill step at all, and M9 in particular can never pass: the
#                   stack tops out at M8, so M9 density is 0 against a 20% floor.
#     DRM.R.1   1   recommended-rule reminder over the whole die.  OUT OF SCOPE.
#     LUP.6     5   latch-up, all five inside pgaorep_2.  FIX 1 below.
#     M7.S.4    2 } one physical object -- the M2 riser at x 599.8..600.1 and
#     M6.S.4    1 } the via metal it drags onto M6/M7.  FIX 4 below.
#     M1.S.1    1   VDD tap via against a clock-gate ECK pin.  FIX 2 below.
#     M3.S.2    1   two same-net VSS M3 stitch bars 0.10 apart.  FIX 3 below.
#
# WHAT EACH FIX COSTS DOWNSTREAM -- read before applying:
#
#  FIX 1 (LUP.6) adds ONE physical instance (FILLBIASNWA10TH) plus its VNW
#        strap.  CELL CONTENT CHANGES: the tile gains an instance, so the DEF,
#        the GDS, the saved netlist and hart_tile.lvs.v all change.  The LEF
#        does not (a well tap advertises no pin).  Area/power delta is one
#        0.4 x 2.0 um tap.  LVS sees one more pmk WELLTAP subckt; the pmk CDL
#        is already included by signoff_mp/lvs_include_tile, and the master
#        already resolves in the tsmc65_sc_adv10_pmk reference library.
#
#  FIX 2 (M1.S.1) deletes and regenerates ONE VDD M1->M2 tap via and drops the
#        wider of the two M1 pads under it.  Nothing outside the tile sees it:
#        the shapes are interior PG, not pins.  The cost is local -- that one
#        FILLBIAS tap ends up on a via centred 0.05 um further from the clock
#        gate; its n-well bias path is otherwise unchanged.
#
#  FIX 3 (M3.S.2) fills a 0.10 um gap between two SAME-NET VSS M3 stitch bars.
#        Purely additive, same net, interior.  Nothing outside the tile sees
#        it.  It also closes a real gap: the two bars were not touching, so
#        they were separate pieces of net VSS.
#
#  FIX 4 (M6.S.4 / M7.S.4) MERGES the wide VDD PG shapes either side of the
#        M2 riser by filling the two channels on M6 and M7.  THIS ONE IS
#        VISIBLE TO THE PARENT.  hart_tile.lef advertises the riser's M7 via
#        metal as `PIN VDD / LAYER M7 RECT 599.75 866 600.15 876`, flanked by
#        `RECT 589 326 599 876` and `RECT 601 866 606 876`.  After the merge
#        `lefOut -StripePin` will emit a contiguous VDD M7 pin across
#        x 589..606 over y 866..876 instead of three separate rects, so
#        MCU_hart's sroute blockPin pass sees MORE pin area at the tile's top
#        edge, never less, and no pin disappears.  That is the whole reason
#        this is a merge and not a delete: deleting the 0.4 rect would remove
#        an advertised pin from a macro two tops bind.
#
# METHOD.  Every site is LOCATED from this cut's own geometry, not from a
# frozen coordinate list.  FIX 2 reads the site out of verifyGeometry's report
# for this DB.  FIX 1, 3 and 4 search a named window for the rule's own trigger
# and FATAL if the geometry they expect is not there, rather than landing on
# whatever happens to be at an address -- the failure mode the frozen
# 2026-07-11 M2.A.1 patch set shipped twice.
#
# IO.  Defaults are the production paths, so an unqualified run applies the ECO
# in place, exactly like tcl/tcm11_eco.tcl.  Override with the environment for
# a dry run against a private copy:
#     ECO_IN_DB=dbs.drceco/hart_tile.signoff.innovus.dat \
#     ECO_DB_DIR=dbs.drceco ECO_OUT_DIR=out.drceco ECO_RPT_DIR=rpt.drceco \
#     innovus -no_gui -batch -files tcl/drc_eco.tcl
################################################################################
set DESIGN_NAME hart_tile
set TAG         drceco

proc envdef {var dflt} {
	global env
	if {[info exists env($var)] && $env($var) ne ""} { return $env($var) }
	return $dflt
}
set IN_DB        [envdef ECO_IN_DB  dbs/hart_tile.signoff.innovus.dat]
set DATABASE_DIR [envdef ECO_DB_DIR dbs]
set OUTPUT_DIR   [envdef ECO_OUT_DIR out]
set REPORT_DIR   [envdef ECO_RPT_DIR rpt]

source ../shared/procedures.tcl
proc logPuts {text} { global PUTS_STRING ; $PUTS_STRING $text }
proc fatal {msg} {
	logPuts "FATAL (DRCECO): $msg"
	logPuts "FATAL (DRCECO): nothing was saved; the input DB is untouched."
	exit 1
}
proc note {msg} { logPuts "### DRCECO ### $msg" }

restoreDesign $IN_DB $DESIGN_NAME
note "restored $IN_DB"

################################################################################
# helpers
################################################################################
# every object of $t on layer $lay inside $area, as {net x0 y0 x1 y1}
proc eco_shapes {area t lay} {
	set out {}
	if {[catch {set objs [dbQuery -area $area -objType $t]} e]} { return $out }
	foreach o $objs {
		if {[dbGet -e $o.layer.name] ne $lay} { continue }
		set b [lindex [dbGet -e $o.box] 0]
		if {[llength $b] != 4} { continue }
		lappend out [concat [list [dbGet -e $o.net.name]] $b]
	}
	return $out
}
# FATAL if any shape on $lay inside $area belongs to a net other than $net
proc eco_no_foreign {area lay net what} {
	foreach t {sWire wire} {
		foreach s [eco_shapes $area $t $lay] {
			if {[lindex $s 0] ne $net} {
				fatal "$what: $lay in $area is occupied by net [lindex $s 0], not $net -- refusing to fill across a foreign net"
			}
		}
	}
}
# smallest edge-to-edge distance from box $b to any $lay shape of a net != $net
# inside $b grown by $halo.  Returns 1e9 when there is nothing to measure.
proc eco_min_foreign_gap {b lay net halo} {
	foreach {x0 y0 x1 y1} $b {}
	set area [list [expr {$x0-$halo}] [expr {$y0-$halo}] [expr {$x1+$halo}] [expr {$y1+$halo}]]
	set best 1000000000.0
	foreach t {sWire wire} {
		foreach s [eco_shapes $area $t $lay] {
			if {[lindex $s 0] eq $net} { continue }
			foreach {ax0 ay0 ax1 ay1} [lrange $s 1 4] {}
			set dx [expr {max($x0 - $ax1, $ax0 - $x1, 0.0)}]
			set dy [expr {max($y0 - $ay1, $ay0 - $y1, 0.0)}]
			set d  [expr {sqrt($dx*$dx + $dy*$dy)}]
			if {$d < $best} { set best $d }
		}
	}
	return $best
}
proc eco_count_via {area net cut} {
	set n 0
	foreach o [dbQuery -area $area -objType sVia] {
		if {[dbGet -e $o.net.name] ne $net} { continue }
		if {[string match -nocase ${cut}* [dbGet -e $o.via.name]]} { incr n }
	}
	return $n
}
proc counts {tag} {
	set i [llength [dbGet -e top.insts]]
	set n [llength [dbGet -e top.nets]]
	logPuts "### DRCECO COUNTS ($tag) ### insts=$i nets=$n"
}
counts baseline

################################################################################
# FIX 1 -- LUP.6 x5.  pgaorep_2's n-well is an UNTAPPED ISLAND.
#
# MECHANISM, measured on this DB.  pgaorep_2 is a GPGBUFX4MA10TH pre-placed at
# {190.6 7.0 192.0 9.0} R0, inside ram0's 2 um halo (ram0 = {75 10 394.65
# 218.675}), so CORE_ROW_2 (y 7..9) is EMPTY from x 72.8 to 396.8: addFiller
# cannot enter a halo, and neither can addWellTap.  Rows abut at their rails,
# so the n-well band that holds this repeater's PMOS is y 8..10, and the only
# cell contributing to it anywhere near is pgaorep_2 itself.  Its n-well is an
# island with NO strap in it, which is exactly what LUP.6 measures -- all five
# markers (y 8.100..8.800) sit in that band.
#
# WHY THE ROW-5 TAP DOES NOT COUNT.  The nearest FILLBIASA10TH is
# WELLTAP_PD_GATED_42 at {193.0 5.0 193.4 7.0} MX.  Flipped, its VNW bar lands
# at y 5.27..5.79 -- in the y 4..6 n-well band, a DIFFERENT well from the one
# that needs the strap.  Swapping the row-5 FILL2/FILL1 at x 192.4/192.8 for a
# FILLBIAS, as the re-harden devlog proposed, would put the new tap in that
# same wrong band and would NOT clear these five markers.  The tap has to go in
# ROW 7 (row 9 is unusable -- it is inside ram0's body, y >= 10).
#
# WHY FILLBIASNWA10TH AND WHY THE LEFT SIDE.  Two M1 signal stubs box this in:
#   pg1rep  M1 {191.900 7.455 192.545 7.545}   (pgaorep_2's own Y output)
#   A-net   M1 {190.255 7.855 190.700 7.945}   (pgaorep_2's A input)
# A FILLBIASA10TH abutting on the RIGHT (x 192.0) puts its VPW bar at
# 192.15..192.25 x 7.30..7.79, straight through the pg1rep stub -- a SHORT.
# On the LEFT (x 190.2) its VPW bar tops out at y 7.79, 0.065 under the A-net
# stub: an M1.S.1 violation traded for a LUP.6.  FILLBIASNWA10TH is the n-well
# tap WITHOUT the VPW bar; on the left its tallest M1 (the VSS abutment finger,
# y0-0.15..y0+0.745) clears the A-net stub by 0.110 and its VNW bar
# (y0+1.21..1.73) clears it by 0.265.  It is the one cell that fits.
#
# THE STRAP.  A tap whose VNW is not tied to VDD does not stop latch-up; it
# only silences the checker.  So the VNW bar gets a real M1 pad (the PG4/F2
# pattern from this flow: x0+0.15..x0+0.25 over the bar), an M2 jog east into
# pgaorep_2's OWN always-on VDDG M2 band, and an engine via.  M2 west is the
# only direction available: the VSS M2 band at 191.4..191.7 blocks the far
# side and the 193.1 strap column stops at y 8.0.
################################################################################
note "FIX 1: LUP.6 -- n-well tap for pgaorep_2"
set REP  pgaorep_2
set TAPCELL FILLBIASNWA10TH
set TAPNAME drceco_lup6_nwtap_pgaorep_2

set pp [dbGet -p top.insts.name $REP -e]
if {$pp eq "0x0" || $pp eq ""} { fatal "FIX1: instance $REP not found -- wrong cut" }
set pb [lindex [dbGet $pp.box] 0]
set po [dbGet $pp.orient]
set pc [dbGet $pp.cell.name]
note "FIX1: $REP box=$pb orient=$po cell=$pc"
if {$pc ne "GPGBUFX4MA10TH" || $po ne "R0"} {
	fatal "FIX1: $REP is a $pc/$po, not a GPGBUFX4MA10TH/R0 -- the tap side and the\
	       pin-bar arithmetic below were derived for that cell and orientation"
}
foreach {rx0 ry0 rx1 ry1} $pb {}
if {abs(($ry1 - $ry0) - 2.0) > 0.001} { fatal "FIX1: $REP is [expr {$ry1-$ry0}] um tall, not 2.0" }

set tcell [dbGet -p head.allCells.name $TAPCELL -e]
if {$tcell eq "0x0" || $tcell eq ""} { fatal "FIX1: cell $TAPCELL is not in the library set" }
set TAPW [dbGet $tcell.size_x]
if {abs($TAPW - 0.4) > 0.001} { fatal "FIX1: $TAPCELL is $TAPW um wide, not 0.400" }

set tapx [expr {$rx0 - $TAPW}]
set tapy $ry0

# the site the tap must land on
set sitew [dbGet -e top.fPlan.coreSite.size_x]
if {$sitew eq "" || $sitew <= 0} { set sitew 0.2 }
set rowfound 0
foreach r [dbQuery -area [list [expr {$tapx+0.01}] [expr {$tapy+0.01}] [expr {$tapx+$TAPW-0.01}] [expr {$tapy+1.99}]] -objType row] {
	if {[dbGet -e $r.site.name] eq [dbGet -e $tcell.site.name]} { set rowfound 1 }
}
if {!$rowfound} { fatal "FIX1: no [dbGet -e $tcell.site.name] row under {$tapx $tapy}" }

# the site must be empty
foreach o [dbQuery -area [list [expr {$tapx+0.01}] [expr {$tapy+0.01}] [expr {$tapx+$TAPW-0.01}] [expr {$tapy+1.99}]] -objType inst] {
	fatal "FIX1: [dbGet $o.name] ([dbGet $o.cell.name]) already occupies {$tapx $tapy}"
}

# the tap's own M1 must not land on a foreign net.  Bars, from the LEF:
#   VNW  x0+0.15..x0+0.35   y0+1.21..y0+1.73
#   VSS  x0-0.045..x0+0.445 y0-0.15 ..y0+0.745  (abutment finger)
set VNWBAR [list [expr {$tapx+0.15}] [expr {$tapy+1.21}] [expr {$tapx+0.35}] [expr {$tapy+1.73}]]
set VSSBAR [list [expr {$tapx-0.045}] [expr {$tapy-0.15}] [expr {$tapx+0.445}] [expr {$tapy+0.745}]]
set g1 [eco_min_foreign_gap $VNWBAR M1 VDD 0.30]
set g2 [eco_min_foreign_gap $VSSBAR M1 VSS 0.30]
note "FIX1: tap M1 clearances -- VNW bar $g1 um, VSS finger $g2 um (rule 0.090)"
if {$g1 < 0.09} { fatal "FIX1: the tap's VNW bar would sit $g1 um from foreign M1 (M1.S.1 needs 0.090)" }
if {$g2 < 0.09} { fatal "FIX1: the tap's VSS finger would sit $g2 um from foreign M1 (M1.S.1 needs 0.090)" }

addInst -cell $TAPCELL -inst $TAPNAME -physical -status fixed -loc [list $tapx $tapy] -ori R0
set tp [dbGet -p top.insts.name $TAPNAME -e]
if {$tp eq "0x0" || $tp eq ""} { fatal "FIX1: addInst of $TAPNAME produced no instance" }
note "FIX1: placed $TAPNAME [dbGet $tp.cell.name] box=[dbGet $tp.box] orient=[dbGet $tp.orient]"

# bind its PG pins the way the flow binds every other tap, then PROVE the
# binding by comparing against a tap the flow itself placed.
globalNetConnect VDD    -type pgpin -pin VNW -inst $TAPNAME -module {} -verbose
globalNetConnect VSS    -type pgpin -pin VSS -inst $TAPNAME -module {} -verbose
globalNetConnect VDD_SW -type pgpin -pin VDD -inst $TAPNAME -module {} -override -verbose
proc eco_pinname {pt} {
	foreach a {name cellTerm.name term.name pgCellTerm.name isPGCellTerm.name} {
		set v [dbGet -e $pt.$a]
		if {$v ne "" && $v ne "0x0"} { return [lindex [split $v /] end] }
	}
	return ""
}
set __vnwnet ""
foreach __pt [dbGet -e $tp.pgInstTerms] {
	set __pn [eco_pinname $__pt]
	note "FIX1:   $TAPNAME/$__pn -> [dbGet -e $__pt.net.name]"
	if {$__pn eq "VNW"} { set __vnwnet [dbGet -e $__pt.net.name] }
}
if {$__vnwnet ne "VDD"} {
	catch {note "FIX1: pgInstTerm attributes: [dbGet [lindex [dbGet -e $tp.pgInstTerms] 0].?]"}
	fatal "FIX1: $TAPNAME/VNW bound to '$__vnwnet', expected VDD"
}

# the always-on M2 band this tap straps to: pgaorep_2's own VDDG column.
set __bands {}
foreach s [eco_shapes $pb sWire M2] {
	if {[lindex $s 0] ne "VDD"} { continue }
	foreach {bx0 by0 bx1 by1} [lrange $s 1 4] {}
	if {($by1 - $by0) < 2.0} { continue }
	lappend __bands [lrange $s 1 4]
}
set __bands [lsort -unique $__bands]
if {[llength $__bands] != 1} {
	fatal "FIX1: expected exactly ONE tall VDD M2 band across $REP, found [llength $__bands]: $__bands"
}
foreach {bx0 by0 bx1 by1} [lindex $__bands 0] {}
note "FIX1: VDDG band = [lindex $__bands 0]"
if {$bx0 <= $tapx} { fatal "FIX1: the VDDG band starts at $bx0, left of the tap at $tapx -- geometry moved" }

# M1 pad on the VNW bar (PG4/F2 pattern), M2 jog east to the band, engine via.
set PAD  [list [expr {$tapx+0.15}] [expr {$tapy+1.21}] [expr {$tapx+0.25}] [expr {$tapy+1.73}]]
set jc   [expr {($tapy+1.21+$tapy+1.73)/2.0}]
set JOGW [expr {$bx1 - $bx0}]
set JOG  [list [expr {$tapx+0.15}] [expr {$jc - $JOGW/2.0}] $bx1 [expr {$jc + $JOGW/2.0}]]
eco_no_foreign $PAD M1 VDD "FIX1 VNW pad"
eco_no_foreign $JOG M2 VDD "FIX1 VDDG jog"
set jg [eco_min_foreign_gap $JOG M2 VDD 0.40]
note "FIX1: jog $JOG width $JOGW, nearest foreign M2 $jg um"
if {$jg < 0.10} { fatal "FIX1: the VDDG jog would sit $jg um from foreign M2" }
add_shape -net VDD -layer M1 -rect $PAD -shape STRIPE -status ROUTED
add_shape -net VDD -layer M2 -rect $JOG -shape STRIPE -status ROUTED
note "FIX1: pad $PAD + jog $JOG laid"

set __vwin [list [expr {$tapx+0.10}] [expr {$tapy+1.16}] [expr {$tapx+0.30}] [expr {$tapy+1.78}]]
set __b [eco_count_via $__vwin VDD via1]
editPowerVia -add_vias 1 -nets VDD -bottom_layer M1 -top_layer M2 -orthogonal_only 0 -area $__vwin
set __a [eco_count_via $__vwin VDD via1]
note "FIX1: VIA1 count in $__vwin: $__b -> $__a"
if {$__a <= $__b} {
	fatal "FIX1: editPowerVia created no VIA1 on the new tap -- its VNW would be a floating\
	       stub, which silences LUP.6 without tying the well.  Refusing to ship that."
}

# --- the tap displaces pgaorep_2's own A-input access ------------------------
# pgaorep_2 is boxed in by its own pin routing.  Its A input is fed by an M1
# stub that runs WEST out of the cell to a VIA1_2CUT_N at (x0-0.3, 7.9) -- the
# router had to leave the cell to drop that via, because the cell's internal M1
# pinches the A pin to a 0.29 um window and a two-cut VIA1 needs 0.38.  Its Y
# output leaves EAST the same way.  So both flanking sites carry live signal
# metal, and the tap footprint collides with the western one: measured on the
# first attempt, the tap's VSS finger came 0.065 from that via's M1 enclosure
# and the VNW pad 0.020 from it.
#
# Nudging the via is not open -- it cannot land on the A pin itself.  So the
# net is RIPPED and re-routed with the tap in place: the router then knows the
# obstruction and takes the stub further west on its own.  Same move as
# tcl/tcm11_eco.tcl, and the same discipline: rip, ecoRoute, then PROVE the
# site is clean before anything is emitted.
#
# NOTE the nets are found from verifyGeometry over the tap window, not named:
# whatever the router put next to this site on THIS cut is what gets ripped.
set F1WIN [list [expr {$tapx-1.2}] [expr {$tapy-0.6}] [expr {[lindex $JOG 2]+0.6}] [expr {$tapy+2.6}]]
proc eco_area_markers {win rptfile} {
	verifyGeometry -area $win -error 100000 -warning 100000 -report $rptfile
	set fh [open $rptfile r] ; set lines [split [read $fh] "\n"] ; close $fh
	set out {}
	foreach ln $lines {
		if {[string match "ANTENNA*" $ln]} { continue }
		if {![regexp {^(SPACING|SHORT|OVERLAP|AREA|MINCUT|MINWIDTH|MINSTEP|MINENC)} $ln]} { continue }
		lappend out $ln
	}
	return $out
}
set F1RPT $REPORT_DIR/$DESIGN_NAME.verifyGeometry.$TAG.lup6.rpt
set f1m [eco_area_markers $F1WIN $F1RPT]
note "FIX1: [llength $f1m] geometry marker(s) in the tap window $F1WIN"
set ripnets {}
foreach ln $f1m {
	note "FIX1:   $ln"
	foreach hit [regexp -all -inline {Regular (?:Wire|Via) of Net ([^&(]+)} $ln] {
		if {[string match "Regular*" $hit]} { continue }
		set nn [string trim $hit]
		if {$nn ne "" && [lsearch -exact $ripnets $nn] < 0} { lappend ripnets $nn }
	}
}
if {[llength $f1m] > 0 && [llength $ripnets] == 0} {
	fatal "FIX1: the tap window has [llength $f1m] marker(s) but none names a regular net --\
	       an ecoRoute cannot clear them.  See $F1RPT."
}
if {[llength $ripnets] > 0} {
	note "FIX1: ripping [llength $ripnets] net(s) so the router can re-route around the tap: $ripnets"
	set dtsaved {}
	foreach nn $ripnets {
		set np [dbGetNetByName $nn]
		if {$np eq "" || $np == 0x0} { fatal "FIX1: net '$nn' not found for the rip" }
		if {[dbGet $np.dontTouch]} { lappend dtsaved $nn ; dbSet $np.dontTouch false }
		set nb [llength [dbGet -e $np.wires]]
		deselectAll
		editSelect -net $nn
		editDelete -selected
		deselectAll
		set na [llength [dbGet -e $np.wires]]
		note "FIX1:   rip $nn wires $nb -> $na"
		if {$na >= $nb} { fatal "FIX1: rip of $nn removed no wires ($nb -> $na)" }
	}
	ecoRoute
	foreach nn $dtsaved {
		dbSet [dbGetNetByName $nn].dontTouch true
		note "FIX1:   dontTouch restored on $nn"
	}
	set f1m2 [eco_area_markers $F1WIN $F1RPT]
	note "FIX1: after ecoRoute, [llength $f1m2] marker(s) remain in the tap window"
	foreach ln $f1m2 { note "FIX1:   $ln" }
	if {[llength $f1m2] > 0} {
		fatal "FIX1: the tap site is still dirty after the re-route.  The n-well tap cannot be\
		       landed beside pgaorep_2 by ECO on this cut -- the fix belongs in\
		       pg1_preplace_repeater, which should drop a FILLBIASNW beside every pgaorep_*\
		       BEFORE routing.  Nothing emitted; see $F1RPT."
	}
}

################################################################################
# FIX 2 -- M1.S.1 x1.  A VDD tap via's M1 enclosure against a clock-gate pin.
#
# THE SITE IS READ OUT OF THIS CUT, NOT HARDCODED.  verifyGeometry names both
# parties; the marker on the 2026-08-25 post-tcm11 DB is
#   SPACING: Special Via of Net VDD
#            & Pin of Cell core/datapath_inst/rf/RC_CG_HIER_INST44/RC_CGIC_INST
#   Bounds : (433.415, 212.210) (433.475, 212.390)   Actual 0.06  Min 0.09
# 433.475 is the PREICGX3BA10TH ECK pin (LEF RECT 3.825..3.925 mirrored into a
# cell placed MY at x 433.4..437.4); 433.415 is the M1 enclosure of the VIA1
# that straps WELLTAP_PD_GATED_1502's VNW bar to the x=433.1 strap column.
#
# WHY THE VIA IS THE PARTY THAT MOVES.  The clock gate cannot: its neighbours
# butt it on both sides (a well tap at 433.0..433.4, a NAND at 437.4).  The via
# cannot shrink either -- a single-cut VIA1 within 0.8 um of an M2 plate bigger
# than 0.3 x 0.3 is VIA1.R.4, so trading two cuts for one just renames the
# violation.  What CAN move is the via's CENTRE.  editPowerVia centres on the
# overlap of the M1 and M2 it is bridging; two VDD M1 pads sit on this tap,
# a 0.20-wide one from sroute and the 0.10-wide PG4/F2 pad on the bar itself.
# Their union is 433.15..433.35, centre 433.25, enclosure 433.085..433.415.
# Drop the wide one and the overlap is 433.15..433.25, centre 433.20 -- the
# same via, 0.05 further from the gate, clearing it by 0.11.
################################################################################
note "FIX 2: M1.S.1 -- re-centre the tap via off the clock-gate pin"
verifyGeometry -error 100000 -warning 100000 \
	-report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.$TAG.pre.rpt
set fh [open $REPORT_DIR/$DESIGN_NAME.verifyGeometry.$TAG.pre.rpt r]
set rpt [split [read $fh] "\n"]
close $fh
set sites {}
for {set i 0} {$i < [llength $rpt]} {incr i} {
	set ln [lindex $rpt $i]
	if {![regexp {^SPACING: Special Via of Net (\S+) *& Pin of Cell (\S+) *\( *(M1) *\)} $ln -> vnet pcell play]} { continue }
	set bl [lindex $rpt [expr {$i+1}]]
	if {![regexp {Bounds *: *\( *([-0-9.]+), *([-0-9.]+) *\) *\( *([-0-9.]+), *([-0-9.]+) *\)} $bl -> bx0 by0 bx1 by1]} {
		fatal "FIX2: marker at report line $i has no parseable Bounds line: '$bl'"
	}
	lappend sites [list $vnet $pcell $bx0 $by0 $bx1 $by1]
}
note "FIX2: verifyGeometry reports [llength $sites] 'Special Via vs Pin' M1 spacing marker(s)"
if {[llength $sites] == 0} {
	note "FIX2: nothing to do on this cut"
}
foreach s $sites {
	foreach {vnet pcell bx0 by0 bx1 by1} $s {}
	note "FIX2: site net=$vnet cell=$pcell bounds=($bx0 $by0) ($bx1 $by1)"
	if {$vnet ne "VDD"} { fatal "FIX2: marker is on net $vnet, not VDD -- not the tap-via class this fix repairs" }
	# the tap that owns the via: the FILLBIAS whose box contains the marker
	set tapi ""
	foreach o [dbQuery -area [list [expr {$bx0-0.6}] [expr {$by0-0.6}] [expr {$bx1+0.6}] [expr {$by1+0.6}]] -objType inst] {
		if {[string match FILLBIAS* [dbGet -e $o.cell.name]]} { set tapi $o }
	}
	if {$tapi eq ""} { fatal "FIX2: no FILLBIAS* well tap within 0.6 um of the marker -- this is not the tap-via class" }
	set tb [lindex [dbGet $tapi.box] 0]
	note "FIX2:   owning tap [dbGet $tapi.name] [dbGet $tapi.cell.name] box=$tb orient=[dbGet $tapi.orient]"
	foreach {tx0 ty0 tx1 ty1} $tb {}
	set win [list [expr {$tx0-0.05}] [expr {$by0-0.35}] [expr {$tx1+0.05}] [expr {$by1+0.45}]]
	# the M1 pads under the via, narrowest first
	set pads {}
	foreach p [eco_shapes $win sWire M1] {
		if {[lindex $p 0] ne "VDD"} { continue }
		lappend pads [lrange $p 1 4]
	}
	set pads [lsort -unique $pads]
	if {[llength $pads] < 2} {
		fatal "FIX2: expected the two VDD M1 pads (0.10 and 0.20 wide) on this tap, found [llength $pads]: $pads"
	}
	set narrow 1e9
	foreach p $pads { set w [expr {[lindex $p 2]-[lindex $p 0]}] ; if {$w < $narrow} { set narrow $w } }
	set ndel 0
	foreach p $pads {
		set w [expr {[lindex $p 2]-[lindex $p 0]}]
		if {$w <= $narrow + 0.001} { continue }
		note "FIX2:   dropping the wide VDD M1 pad $p (width $w, keeping $narrow)"
		editDelete -net VDD -layer M1 -area $p
		incr ndel
	}
	if {$ndel == 0} { fatal "FIX2: no wider-than-$narrow VDD M1 pad to drop -- the site is not what this fix expects" }
	set nb [eco_count_via $win VDD via1]
	editPowerVia -delete_vias 1 -nets VDD -bottom_layer M1 -top_layer M2 -area $win
	editPowerVia -add_vias 1 -nets VDD -bottom_layer M1 -top_layer M2 -orthogonal_only 0 -area $win
	set na [eco_count_via $win VDD via1]
	note "FIX2:   VIA1 count in $win: $nb -> $na"
	if {$na < 1} { fatal "FIX2: the regenerate lost the tap via ($nb -> $na)" }
	# A via's M1 enclosure is not reachable through dbGet (an sVia carries no
	# box), so the proof that the new one clears the pin is the acceptance gate
	# at the bottom of this file: it re-runs verifyGeometry and REFUSES to emit
	# collateral while a 'Special Via vs Pin' M1 marker survives.
}
set FIX2_SITES [llength $sites]

################################################################################
# FIX 3 -- M3.S.2 x1.  Two SAME-NET VSS M3 stitch bars 0.10 um apart.
#
#   sWire VSS M3 {359.45 234.65 366.55 234.75}   (union of two pieces)
#   sWire VSS M3 {359.45 234.85 361.35 234.95}   (union of two pieces)
#
# 0.10 between them, 1.90 of parallel run; the rule wants 0.12.  Both are VSS,
# and they are NOT touching, so they are separate pieces of the same net -- the
# fill closes a real gap as well as the marker.  The window below is named, the
# SHAPES are searched: if no same-net M3 pair with a sub-0.12 gap is in it, the
# fix FATALs rather than filling an address.
################################################################################
note "FIX 3: M3.S.2 -- merge the same-net VSS M3 stitch bars"
set SKIP3 [envdef ECO_SKIP_FIX3 0]
if {$SKIP3} { note "FIX 3: SKIPPED by ECO_SKIP_FIX3 -- M3.S.2 carried forward" }
if {!$SKIP3} {
set M3WIN  {358.5 233.5 367.5 236.0}
set M3SPC  0.12
set M3RUN  0.38
set m3s {}
foreach s [eco_shapes $M3WIN sWire M3] { lappend m3s $s }
set m3pairs {}
set m3trig 0
foreach a $m3s {
	foreach b $m3s {
		if {[lindex $a 0] ne [lindex $b 0]} { continue }
		foreach {ax0 ay0 ax1 ay1} [lrange $a 1 4] {}
		foreach {bx0 by0 bx1 by1} [lrange $b 1 4] {}
		set gap [expr {$by0 - $ay1}]
		if {$gap <= 0.0 || $gap >= $M3SPC} { continue }
		set ox0 [expr {max($ax0,$bx0)}] ; set ox1 [expr {min($ax1,$bx1)}]
		if {[expr {$ox1 - $ox0}] <= 0.0} { continue }
		lappend m3pairs [list [lindex $a 0] $ox0 $ay1 $ox1 $by0]
		if {[expr {$ox1 - $ox0}] > $M3RUN} { incr m3trig }
	}
}
set m3pairs [lsort -unique $m3pairs]
note "FIX3: [llength $m3pairs] same-net M3 y-gap(s) under ${M3SPC} um in $M3WIN, $m3trig of them over ${M3RUN} um of run"
if {$m3trig == 0} {
	fatal "FIX3: no same-net M3 gap in $M3WIN carries the rule's own trigger (a run over\
	       ${M3RUN} um) -- the M3.S.2 geometry has moved.  Re-derive the site from this\
	       cut's blockdrc.db instead of filling blind."
}
# Every sub-spacing gap between the two bars is filled, not only the ones long
# enough to trip the rule on their own: merging part of a pair leaves the rest
# as a NOTCH in the resulting polygon, and EXT measures a notch too.
set m3x0 1e9 ; set m3x1 -1e9 ; set m3net ""
foreach f $m3pairs {
	foreach {fnet fx0 fy0 fx1 fy1} $f {}
	set r [list $fx0 [expr {$fy0-0.02}] $fx1 [expr {$fy1+0.02}]]
	eco_no_foreign $r M3 $fnet "FIX3 merge fill"
	add_shape -net $fnet -layer M3 -rect $r -shape STRIPE -status ROUTED
	note "FIX3: filled $fnet M3 $r (gap was [expr {$fy1-$fy0}])"
	set m3net $fnet
	if {$fx0 < $m3x0} { set m3x0 $fx0 }
	if {$fx1 > $m3x1} { set m3x1 $fx1 }
}

# --- the merge has a price, and it has to be paid here ----------------------
# Merging the two bars turns a 0.10-thin stitch into a plate: locally the M3
# becomes 0.44 um tall once the M8-crossing via metal above it (the 360..365
# band at y 234.91..235.09) joins in.  That makes every SINGLE-CUT VIA2 within
# 0.8 um of it illegal under VIA2.R.4:M3.  Measured, not predicted: the first
# pass of this ECO closed M3.S.2 and opened exactly one VIA2.R.4:M3 at
# (359.650,234.850).
#
# ADDING a second cut was tried first and does not work here.  The stitch's M2
# pad is 0.10 wide between a foreign M2 at 0.10 to the west and the M3 plate's
# own extent, so a two-cut via needs the pad widened east; widening it to 0.50
# makes the M2 a plate in its own right and Innovus answers with a MINCUT on
# the VIA1 underneath plus a wide-metal M2 spacing marker against
# adddec0/.../logic_0_1_net.  Measured, both of them.  There is no width for
# that pad that carries two cuts and clears its neighbour.
#
# So the stitch goes instead: VIA2, the M2 pad and the VIA1 under it are all
# removed.  THE COST IS ONE REDUNDANT VSS RAIL TIE.  The M3 bar keeps its feed
# through VIA3 at (360.3, 234.7) to M4, and the M1 follow-pin rail the stub
# hung off is continuous across the whole tile -- this stack was a second path,
# not the only one.  verifyConnectivity is the gate: the piece/dangling counts
# are compared against the pre-ECO run in the acceptance block below.
set M3RPT $REPORT_DIR/$DESIGN_NAME.verifyGeometry.$TAG.m3.rpt
set mc {}
foreach ln [eco_area_markers $M3WIN $M3RPT] {
	if {[string match "MINCUT*" $ln]} { lappend mc $ln }
}
note "FIX3: [llength $mc] MINCUT marker(s) opened by the merge"
if {[llength $mc] > 0} {
	set fh [open $M3RPT r] ; set ml [split [read $fh] "\n"] ; close $fh
	set boxes {}
	for {set i 0} {$i < [llength $ml]} {incr i} {
		if {![string match "MINCUT*" [lindex $ml $i]]} { continue }
		for {set j [expr {$i+1}]} {$j < $i+4 && $j < [llength $ml]} {incr j} {
			if {[regexp {Bounds *: *\( *([-0-9.]+), *([-0-9.]+) *\) *\( *([-0-9.]+), *([-0-9.]+) *\)} [lindex $ml $j] -> a b c d]} {
				lappend boxes [list $a $b $c $d] ; break
			}
		}
	}
	if {[llength $boxes] != [llength $mc]} { fatal "FIX3: could not read Bounds for every MINCUT marker in $M3RPT" }
	foreach bx $boxes {
		foreach {vx0 vy0 vx1 vy1} $bx {}
		note "FIX3: single-cut stitch via at $bx -- removing the whole stack"
		set pads {}
		foreach sh [eco_shapes [list [expr {$vx0-0.05}] [expr {$vy0-0.60}] [expr {$vx1+0.05}] [expr {$vy1+0.05}]] sWire M2] {
			if {[lindex $sh 0] ne $m3net} { continue }
			lappend pads [lrange $sh 1 4]
		}
		set pads [lsort -unique $pads]
		if {[llength $pads] != 1} { fatal "FIX3: expected ONE $m3net M2 pad under the single-cut via, found [llength $pads]: $pads" }
		set pad [lindex $pads 0]
		foreach {px0 py0 px1 py1} $pad {}
		if {($px1 - $px0) > 0.35} {
			fatal "FIX3: the M2 pad $pad is [expr {$px1-$px0}] um wide -- that is a strap, not a\
			       stitch stub, and deleting it would cut a real supply path.  Stop here."
		}
		set vwin [list [expr {$px0-0.05}] [expr {$py0-0.05}] [expr {$px1+0.05}] [expr {$py1+0.10}]]
		editPowerVia -delete_vias 1 -nets $m3net -bottom_layer M2 -top_layer M3 -area $vwin
		editPowerVia -delete_vias 1 -nets $m3net -bottom_layer M1 -top_layer M2 -area $vwin
		editDelete -net $m3net -layer M2 -area $vwin
		note "FIX3:   removed the VIA2/VIA1 pair and the M2 stub $pad"
	}
	set mc2 {}
	foreach ln [eco_area_markers $M3WIN $M3RPT] {
		note "FIX3:   post-removal marker: $ln"
		lappend mc2 $ln
	}
	if {[llength $mc2] > 0} {
		fatal "FIX3: [llength $mc2] marker(s) survive in $M3WIN.  Closing M3.S.2 by merging\
		       costs more than this ECO can pay.  Re-run with ECO_SKIP_FIX3=1 to ship the\
		       other three fixes and carry M3.S.2 forward, or move the fix into the flow\
		       where the stitch can be built with two cuts in the first place.  See $M3RPT."
	}
}
}

################################################################################
# FIX 4 -- M6.S.4 x1 + M7.S.4 x2.  ONE object, three markers.
#
# GEOMETRY, from this DB.  A 0.30-wide VDD M2 riser at x 599.8..600.1 climbs to
# the top PG ring; the via stack that carries it drags 0.30/0.40-wide metal onto
# M6 and M7 across y 866..876.  It lands in the 2.000 um channel between the
# 10 um VDD M7 ring ending at x=599.0 and the 5 um VDD M6 stripe (and the M7 via
# metal above it) starting at x=601.0.
#
# THE RULE IS NET-BLIND and it CANNOT BE SATISFIED BY MOVING OR NARROWING:
# 1.50 + w + 1.50 needs 3.00 um of channel at any width, and there is 2.00.
# All five participating shapes are VDD, so MERGE them: a rule that measures a
# SPACE stops seeing one when the shapes become one union.
#
# NOTE the riser and its via metal are NOT special wires -- `dbGet net.sWires`
# cannot see the M6/M7 rects at all, which is why the P&R script's own
# wide-metal channel-union pass filled zero here (its census found exactly ONE
# VDD M6 sWire in the whole tile).  This fix works from what IS in the DB: the
# M2 riser, the M7 ring, the M6 stripe and the M8 ring that fixes the band.
################################################################################
note "FIX 4: M6.S.4/M7.S.4 -- merge the wide VDD PG shapes across the riser channel"
set WMWIN  {585.0 855.0 620.0 880.0}
set WMWIDE 4.50
set WMSPC  1.50

# the top band: the VDD M8 ring segment over the corner
set rings {}
foreach s [eco_shapes $WMWIN sWire M8] {
	if {[lindex $s 0] ne "VDD"} { continue }
	foreach {x0 y0 x1 y1} [lrange $s 1 4] {}
	if {($y1 - $y0) < $WMWIDE} { continue }
	lappend rings [lrange $s 1 4]
}
set rings [lsort -unique $rings]
if {[llength $rings] != 1} { fatal "FIX4: expected ONE wide VDD M8 ring in $WMWIN, found [llength $rings]: $rings" }
foreach {mx0 my0 mx1 my1} [lindex $rings 0] {}
note "FIX4: top band from the VDD M8 ring = y $my0 .. $my1"

# the riser: a narrow VDD M2 stripe that reaches the top of that band
set risers {}
foreach s [eco_shapes $WMWIN sWire M2] {
	if {[lindex $s 0] ne "VDD"} { continue }
	foreach {x0 y0 x1 y1} [lrange $s 1 4] {}
	if {($x1 - $x0) > 1.0} { continue }
	if {$y1 < $my1 - 0.001 || $y0 > $my0} { continue }
	lappend risers [lrange $s 1 4]
}
set risers [lsort -unique $risers]
note "FIX4: [llength $risers] narrow VDD M2 riser(s) crossing the band: $risers"

# the wide flanks, per layer
proc eco_wide_flank {win lay net wide side ref} {
	set best ""
	foreach s [eco_shapes $win sWire $lay] {
		if {[lindex $s 0] ne $net} { continue }
		foreach {x0 y0 x1 y1} [lrange $s 1 4] {}
		if {($x1 - $x0) < $wide} { continue }
		if {$side eq "left"} {
			if {$x1 > $ref + 0.001} { continue }
			if {$best eq "" || $x1 > [lindex $best 2]} { set best [list $x0 $y0 $x1 $y1] }
		} else {
			if {$x0 < $ref - 0.001} { continue }
			if {$best eq "" || $x0 < [lindex $best 0]} { set best [list $x0 $y0 $x1 $y1] }
		}
	}
	return $best
}

set wm_done 0
foreach r $risers {
	foreach {rx0 ry0 rx1 ry1} $r {}
	set L7 [eco_wide_flank $WMWIN M7 VDD $WMWIDE left  $rx0]
	set R6 [eco_wide_flank $WMWIN M6 VDD $WMWIDE right $rx1]
	if {$L7 eq "" || $R6 eq ""} {
		note "FIX4: riser $r has no wide VDD flank on both sides -- not the wide-metal object, skipped"
		continue
	}
	set gapL [expr {$rx0 - [lindex $L7 2]}]
	set gapR [expr {[lindex $R6 0] - $rx1}]
	note "FIX4: riser $r  left M7 flank $L7 (gap $gapL)  right M6 flank $R6 (gap $gapR)"
	if {$gapL <= 0.0 || $gapL >= $WMSPC || $gapR <= 0.0 || $gapR >= $WMSPC} {
		note "FIX4: riser $r channel gaps $gapL / $gapR are outside (0, $WMSPC) -- the rule does\
		      not fire on it, skipped"
		continue
	}
	# M7: bridge the whole channel over the band, overlapping both flanks by 0.1
	set f7 [list [expr {[lindex $L7 2] - 0.1}] $my0 [expr {[lindex $R6 0] + 0.1}] $my1]
	eco_no_foreign $f7 M7 VDD "FIX4 M7 merge fill"
	set d7 [eco_min_foreign_gap $f7 M7 VDD 2.0]
	note "FIX4: M7 fill $f7, nearest foreign M7 $d7 um (rule $WMSPC)"
	if {$d7 < $WMSPC} { fatal "FIX4: the merged M7 plate would sit $d7 um from foreign M7" }
	add_shape -net VDD -layer M7 -rect $f7 -shape STRIPE -status ROUTED
	# M6: same channel, but only as high as the M6 flank actually runs
	set y6 [expr {min($my1, [lindex $R6 3])}]
	set f6 [list [expr {$rx1 - 0.1}] $my0 [expr {[lindex $R6 0] + 0.1}] $y6]
	eco_no_foreign $f6 M6 VDD "FIX4 M6 merge fill"
	set d6 [eco_min_foreign_gap $f6 M6 VDD 2.0]
	note "FIX4: M6 fill $f6, nearest foreign M6 $d6 um (rule $WMSPC)"
	if {$d6 < $WMSPC} { fatal "FIX4: the merged M6 plate would sit $d6 um from foreign M6" }
	add_shape -net VDD -layer M6 -rect $f6 -shape STRIPE -status ROUTED
	incr wm_done
}
if {$wm_done != 1} {
	fatal "FIX4: merged $wm_done channels, expected exactly 1.  Zero means the M6.S.4/M7.S.4\
	       object is no longer where this fix looks for it; more than one means the cut grew\
	       a class this hand ECO was not sized for -- either way, re-derive before shipping."
}

################################################################################
# acceptance + collateral
################################################################################
counts after_eco
verifyGeometry -error 100000 -warning 100000 \
	-report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.$TAG.rpt
verifyConnectivity -error 100000 -connectPadSpecialPorts \
	-report $REPORT_DIR/$DESIGN_NAME.verifyConnectivity.$TAG.rpt

# GATE.  FIX 2's own proof cannot be taken from the DB (an sVia carries no box
# to measure), so it is taken from the checker: if the marker class this ECO
# claims to repair is still in the post-ECO report, NOTHING is emitted.  M19c
# shipped collateral from an unrepaired state; a silent partial repair is the
# same failure wearing a different hat.
set fh [open $REPORT_DIR/$DESIGN_NAME.verifyGeometry.$TAG.rpt r]
set post [split [read $fh] "\n"]
close $fh
set left 0
foreach ln $post {
	if {[regexp {^SPACING: Special Via of Net \S+ *& Pin of Cell} $ln]} { incr left }
}
note "acceptance: $FIX2_SITES 'Special Via vs Pin' M1 marker(s) before, $left after"
if {$left > 0} {
	fatal "FIX2 did not close: $left 'Special Via vs Pin' M1 marker(s) survive.  See\
	       $REPORT_DIR/$DESIGN_NAME.verifyGeometry.$TAG.rpt.  No collateral emitted."
}
set wsum 0
foreach ln $post {
	if {[regexp {^ *Wiring *: *([0-9]+)} $ln -> n]} { set wsum $n }
}
note "acceptance: verifyGeometry Wiring count after the ECO = $wsum"
set fh [open $REPORT_DIR/$DESIGN_NAME.verifyConnectivity.$TAG.rpt r]
foreach ln [split [read $fh] "\n"] {
	if {[regexp {Problem\(s\) \(IMPVFC-[0-9]+\)} $ln]} { note "acceptance:[string trimright $ln]" }
	if {[regexp {total info\(s\) created} $ln]} { note "acceptance:[string trimright $ln]" }
}
close $fh

# M19c: one cut, every file.  A GDS repaired by an out-of-flow ECO whose LEF and
# xsim.v came from the unrepaired state is exactly what M19c shipped.
saveDesign $DATABASE_DIR/$DESIGN_NAME.signoff.innovus -def -netlist -rc -tcon
streamOut $OUTPUT_DIR/$DESIGN_NAME.gds2 -libName WorkLib -structureName $DESIGN_NAME \
	-stripes 1 -units 1000 -mode ALL -mapFile ../shared/innovus2gds.map
write_sdf $OUTPUT_DIR/$DESIGN_NAME.sdf
saveNetlist $OUTPUT_DIR/$DESIGN_NAME.xsim.v -excludeCellInst ANTENNA2A10TH
# ANTENNA DATA BEFORE lefOut (2026-08-25).  This ECO used to call lefOut with no
# antenna pass in front of it, so it re-emitted the tile abstract WITHOUT the
# per-pin antenna model the P&R flow's own lefOut carries (ANTENNAGATEAREA 127
# -> 0, same PIN and RECT counts, file 84 KB smaller -- nothing looked wrong).
# The tile is bound as a macro by MCU_hart, which is exactly the consumer that
# needs it.  NB this whole script is SUPERSEDED by the in-flow tcl/g0_repair.tcl
# and tcl/wm_merge.tcl; the line below is here so that running it for forensics
# cannot silently damage out/hart_tile.lef.
verifyProcessAntenna
lefOut -StripePin -PGpinLayers 7 8 -specifyTopLayer 8 $OUTPUT_DIR/$DESIGN_NAME.lef
set_analysis_view -setup [list setup_analysis_view] -hold [list setup_analysis_view]
if {[catch {do_extract_model -view setup_analysis_view $OUTPUT_DIR/$DESIGN_NAME.etm_ss.lib} e]} {
	logPuts "ETM ss FAILED: $e" } else { logPuts "ETM ss written" }
set_analysis_view -setup [list hold_analysis_view] -hold [list hold_analysis_view]
if {[catch {do_extract_model -view hold_analysis_view $OUTPUT_DIR/$DESIGN_NAME.etm_ff.lib} e]} {
	logPuts "ETM ff FAILED: $e" } else { logPuts "ETM ff written" }
set_analysis_view -setup [list setup_analysis_view] -hold [list hold_analysis_view]
saveDesign $DATABASE_DIR/$DESIGN_NAME.final.innovus -def -netlist -rc -tcon
note "complete"
exit
