################################################################################
# G0 ECO -- the 2026-08-25 VSS-fix cut.
#
# THIS FILE REPLACES tcl/tcm11_eco.tcl FOR THIS CUT AND ONLY THIS CUT.
# tcm11_eco.tcl is keyed to `core/irq_handler_inst/tie_0_cell6` at
# {576.2 65.0 577.0 67.0}/R180 and its own guard refuses anything else -- which
# is correct behaviour, not a defect.  The CPR5 banner in hart_tile.innovus.tcl
# states the rule: the G0 class is a PLACEMENT-DEPENDENT router-vs-cell-OBS M1
# merge, and "ANY re-harden moves the placement and re-manufactures the class
# SOMEWHERE ELSE".  The VSS-fix harden moved it to TWO new sites, in two
# different cell masters at two different orientations, so the site list is
# authored fresh from this cut.
#
# THE SITES, from rpt/hart_tile.verifyGeometry.signoff.rpt (2026-08-25 15:08):
#
#   SHORT: Regular Wire of Net core/csr_unit_inst/n_421
#          & Blockage of Cell core/csr_unit_inst/g11129__6161  ( M1 )
#   Bounds : ( 624.810, 97.450 ) ( 624.865, 97.550 )
#
#   SHORT: Regular Via of Net core/datapath_inst/rf/n_1532
#          & Blockage of Cell core/datapath_inst/rf/registers_reg[30][17]  ( M1 )
#   Bounds : ( 480.750, 176.410 ) ( 480.825, 176.590 )
#
# and Pegasus agrees on both, which is what makes them worth a run -- these are
# not cosmetic markers, they are two signal nets MERGED IN THE LAYOUT:
#
#   Layout Net: X4/4163 | Schematic Net: Xcore/Xcsr_unit_inst/n_421
#            SHORT      | Schematic Net: Xcore/Xcsr_unit_inst/Xg11129__6161/INT
#   Layout Net: X5/2972 | Schematic Net: Xcore/Xdatapath_inst/Xrf/n_1532
#            SHORT      | Schematic Net: .../Xregisters_reg<30><17>/NCLK
#
# They are the ONLY thing between this cut and an LVS MATCH: the same run
# reports 0:0 unmatched devices, 0:0 unmatched pins, 0 unmatched layout nets
# and NO OPENS, with the 2 unmatched SCHEMATIC nets being exactly the two
# halves of these two merges.
#
# GEOMETRY.  Each site is repaired the way tcm11_eco repaired its own: rip the
# offending net, fence the cell's OWN M1 OBS rects with M1+VIA1 route blockages
# (the violated rect grown by the 0.090 M1.S.1 spacing, plus the OBS rects that
# touch it), ecoRoute, drop the blockages.  NOT A BBOX BLOCKAGE -- CPR5b
# attempt #1 used the cell bbox, which also covers the rails and the cell's own
# pins, and ecoRoute answered with Short 23 / Overlap 16.
#
# The OBS rects are transformed from the kit LEF by this cut's own placement,
# and each translation is CHECKED by the marker-containment arithmetic that
# tcm11_eco used -- the violated rect must contain the reported bounds:
#
#  site 1  OR2X1MA10TH    at (623.8, 97.0)  1.2 x 2.0  R180
#          LEF OBS M1 RECT 0.1350 1.3000 0.2250 1.7450
#          -> {624.775 97.255 624.865 97.700}
#             624.775 <= 624.810 and 624.865 <= 624.865
#              97.255 <=  97.450 and  97.550 <=  97.700   OK
#
#  site 2  DFFRPQX1MA10TH at (476.2, 175.0) 4.8 x 2.0  MY
#          LEF OBS M1 RECT 0.1750 1.1850 0.2650 1.5900
#          -> {480.735 176.185 480.825 176.590}
#             480.735 <= 480.750 and 480.825 <= 480.825
#            176.185 <= 176.410 and 176.590 <= 176.590   OK
#
# Exactly ONE OBS rect per cell contains its marker; the other 4 (OR2) and 47
# (DFF) do not.  That is the check that the orientation maths is right, and it
# is re-run in tcl below against the live DB before anything is ripped.
#
# FIX B is drc_eco.tcl's FIX 4 carried over verbatim: the M6.S.4 + M7.S.4 x2
# wide-metal object at the top-right corner is UNCHANGED by the VSS work and
# still needs the same same-net merge.  Its code is self-deriving, so it finds
# the object in this cut rather than at a remembered address.
#
# NOT ADDRESSED HERE, deliberately: VIA1.R.2__VIA1.R.3 x4.  Those are NEW and
# they are the price of the LUP.6 flow fix -- see the devlog.  They sit on the
# VDDG jogs of the pgaorep_0 and pgaorep_3 n-well taps, where a 0.30-wide M2
# jog meets the repeater's own 0.30-wide VDDG strap and promotes a single-cut
# VIA1 to the MINIMUMCUT-2 class.  Narrowing the jog cannot fix it (the strap
# is the wide party), so the repair belongs in the flow, not in an ECO.
#
# IO: same env overrides as drc_eco.tcl.
#     `-batch` IS MANDATORY -- without it a tcl error parks at an interactive
#     prompt and the run hangs instead of failing.
################################################################################
set DESIGN_NAME hart_tile
set TAG         g0eco

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
	logPuts "FATAL (G0ECO): $msg"
	logPuts "FATAL (G0ECO): nothing was saved; the input DB is untouched."
	exit 1
}
proc note {msg} { logPuts "### G0ECO ### $msg" }

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
	logPuts "### G0ECO COUNTS ($tag) ### insts=$i nets=$n"
}
counts baseline

################################################################################
# FIX A -- the two G0 router-vs-OBS M1 merges
################################################################################
note "FIX A: G0 M1 merges -- fence the cell OBS, rip, ecoRoute"

# site = {tag inst cell orient x0 y0 W H net {violated OBS local} {touching OBS local ...}}
set G0SITES {
	{s1 core/csr_unit_inst/g11129__6161 OR2X1MA10TH R180 623.8 97.0 1.2 2.0
	    {core/csr_unit_inst/n_421}
	    {0.1350 1.3000 0.2250 1.7450}
	    {{0.2250 1.3000 0.8000 1.3900}}
	    {624.810 97.450 624.865 97.550}}
	{s2 core/datapath_inst/rf/registers_reg[30][17] DFFRPQX1MA10TH MY 476.2 175.0 4.8 2.0
	    {core/datapath_inst/rf/n_1532}
	    {0.1750 1.1850 0.2650 1.5900}
	    {{0.2650 1.5000 1.5550 1.5900} {0.1450 1.1850 0.1750 1.2750} {0.0550 0.4400 0.1450 1.2750}}
	    {480.750 176.410 480.825 176.590}}
}
set G0GROW 0.090

# transform a LEF-R0 rect into absolute coords for a cell at ($x0,$y0) $orient
proc g0_abs {orient x0 y0 W H r} {
	foreach {lx0 ly0 lx1 ly1} $r {}
	switch -- $orient {
		R0   { set ax0 [expr {$x0+$lx0}]      ; set ax1 [expr {$x0+$lx1}]
		       set ay0 [expr {$y0+$ly0}]      ; set ay1 [expr {$y0+$ly1}] }
		MY   { set ax0 [expr {$x0+$W-$lx1}]   ; set ax1 [expr {$x0+$W-$lx0}]
		       set ay0 [expr {$y0+$ly0}]      ; set ay1 [expr {$y0+$ly1}] }
		MX   { set ax0 [expr {$x0+$lx0}]      ; set ax1 [expr {$x0+$lx1}]
		       set ay0 [expr {$y0+$H-$ly1}]   ; set ay1 [expr {$y0+$H-$ly0}] }
		R180 { set ax0 [expr {$x0+$W-$lx1}]   ; set ax1 [expr {$x0+$W-$lx0}]
		       set ay0 [expr {$y0+$H-$ly1}]   ; set ay1 [expr {$y0+$H-$ly0}] }
		default { fatal "FIX A: orientation '$orient' is not one of R0/MX/MY/R180" }
	}
	return [list $ax0 $ay0 $ax1 $ay1]
}
proc g0_contains {outer inner} {
	foreach {ox0 oy0 ox1 oy1} $outer {}
	foreach {ix0 iy0 ix1 iy1} $inner {}
	return [expr {$ox0 <= $ix0+1e-6 && $oy0 <= $iy0+1e-6 && $ix1 <= $ox1+1e-6 && $iy1 <= $oy1+1e-6}]
}

# how many G0 markers are there BEFORE?
verifyGeometry -error 100000 -warning 100000 \
	-report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.$TAG.pre.rpt
proc g0_marker_count {f} {
	set n 0
	set fh [open $f r]
	foreach ln [split [read $fh] "\n"] {
		if {[regexp {^SHORT: Regular (Wire|Via) of Net .* & Blockage of Cell .*\( M1 \)} $ln]} { incr n }
	}
	close $fh
	return $n
}
set G0_BEFORE [g0_marker_count $REPORT_DIR/$DESIGN_NAME.verifyGeometry.$TAG.pre.rpt]
note "FIX A: [llength $G0SITES] site(s) authored, $G0_BEFORE G0 M1 marker(s) in this DB"
if {$G0_BEFORE != [llength $G0SITES]} {
	fatal "FIX A: this DB has $G0_BEFORE G0 M1 marker(s) but the site list has [llength $G0SITES].\
	       The class has moved again -- RE-DERIVE the site list from\
	       $REPORT_DIR/$DESIGN_NAME.verifyGeometry.$TAG.pre.rpt.  Nothing ripped."
}

set G0BLKS {}
foreach site $G0SITES {
	foreach {tag inst cellname orient x0 y0 W H net vio touch marker} $site {}
	set ip [dbGet -p top.insts.name $inst -e]
	if {$ip eq "0x0" || $ip eq "" || $ip eq "0"} { fatal "FIX A/$tag: instance $inst not found -- wrong cut" }
	set ib [lindex [dbGet $ip.box] 0]
	set io [dbGet $ip.orient]
	set ic [dbGet $ip.cell.name]
	note "FIX A/$tag: $inst $ic box=$ib orient=$io"
	if {$ic ne $cellname || $io ne $orient} {
		fatal "FIX A/$tag: $inst is a $ic/$io, not $cellname/$orient -- the OBS translation\
		       below was derived for that master and orientation.  RE-DERIVE."
	}
	if {abs([lindex $ib 0] - $x0) > 0.001 || abs([lindex $ib 1] - $y0) > 0.001} {
		fatal "FIX A/$tag: $inst is at [lrange $ib 0 1], not ($x0,$y0) -- the placement moved.\
		       RE-DERIVE the OBS translation; do not adjust blindly."
	}
	# THE ARITHMETIC CHECK: the violated OBS rect must contain the reported marker
	set vabs [g0_abs $orient $x0 $y0 $W $H $vio]
	note "FIX A/$tag: violated OBS $vio -> $vabs, marker $marker"
	if {![g0_contains $vabs $marker]} {
		fatal "FIX A/$tag: the transformed OBS rect $vabs does NOT contain the marker $marker --\
		       the orientation maths is wrong and the blockage would land on clean geometry."
	}
	# rip the net
	set np [dbGetNetByName $net]
	if {$np eq "" || $np == 0x0} { fatal "FIX A/$tag: net $net not found" }
	if {[dbGet $np.dontTouch]} { dbSet $np.dontTouch false ; note "FIX A/$tag: $net dontTouch cleared" }
	set before [llength [dbGet -e $np.wires]]
	deselectAll
	editSelect -net $net
	editDelete -selected
	deselectAll
	set after [llength [dbGet -e $np.wires]]
	note "FIX A/$tag: RIP $net wires $before -> $after"
	if {$after >= $before} { fatal "FIX A/$tag: rip of $net removed no wires ($before -> $after)" }
	# blockades: the violated rect grown by the M1.S.1 spacing, plus what touches it
	set i 0
	set gv [list [expr {[lindex $vabs 0]-$G0GROW}] [expr {[lindex $vabs 1]-$G0GROW}] \
	             [expr {[lindex $vabs 2]+$G0GROW}] [expr {[lindex $vabs 3]+$G0GROW}]]
	# NB no lmap here -- it is Tcl 8.6 only and this recipe must not depend on the
	# interpreter version shipped with a particular Innovus build.
	set blist [list $gv]
	foreach t $touch { lappend blist [g0_abs $orient $x0 $y0 $W $H $t] }
	foreach b $blist {
		set nm g0_${tag}_obs$i
		if {[catch {createRouteBlk -name ${nm}_M1 -layer M1 -cutLayer VIA1 -box $b} err]} {
			fatal "FIX A/$tag: createRouteBlk $nm failed: $err"
		}
		note "FIX A/$tag: BLK $nm M1+VIA1 $b"
		lappend G0BLKS ${nm}_M1
		incr i
	}
}
if {[llength $G0BLKS] < 2} { fatal "FIX A: only [llength $G0BLKS] blockage(s) created" }

ecoRoute
counts after_ecoRoute
foreach nm $G0BLKS { catch { deleteRouteBlk -name $nm } }
note "FIX A: [llength $G0BLKS] blockage(s) removed"

verifyGeometry -error 100000 -warning 100000 \
	-report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.$TAG.a.rpt
set G0_AFTER [g0_marker_count $REPORT_DIR/$DESIGN_NAME.verifyGeometry.$TAG.a.rpt]
note "FIX A: G0 M1 markers $G0_BEFORE -> $G0_AFTER"
if {$G0_AFTER > 0} {
	fatal "FIX A did not close: $G0_AFTER G0 M1 marker(s) survive the re-route.  See\
	       $REPORT_DIR/$DESIGN_NAME.verifyGeometry.$TAG.a.rpt.  These are REAL LAYOUT SHORTS\
	       between two signal nets -- no collateral is emitted while one stands."
}

################################################################################
# FIX B -- M6.S.4 x1 + M7.S.4 x2.  ONE object, three markers.
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
note "FIX B: M6.S.4/M7.S.4 -- merge the wide VDD PG shapes across the riser channel"
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
if {[llength $rings] != 1} { fatal "FIX B: expected ONE wide VDD M8 ring in $WMWIN, found [llength $rings]: $rings" }
foreach {mx0 my0 mx1 my1} [lindex $rings 0] {}
note "FIX B: top band from the VDD M8 ring = y $my0 .. $my1"

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
note "FIX B: [llength $risers] narrow VDD M2 riser(s) crossing the band: $risers"

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
		note "FIX B: riser $r has no wide VDD flank on both sides -- not the wide-metal object, skipped"
		continue
	}
	set gapL [expr {$rx0 - [lindex $L7 2]}]
	set gapR [expr {[lindex $R6 0] - $rx1}]
	note "FIX B: riser $r  left M7 flank $L7 (gap $gapL)  right M6 flank $R6 (gap $gapR)"
	if {$gapL <= 0.0 || $gapL >= $WMSPC || $gapR <= 0.0 || $gapR >= $WMSPC} {
		note "FIX B: riser $r channel gaps $gapL / $gapR are outside (0, $WMSPC) -- the rule does\
		      not fire on it, skipped"
		continue
	}
	# M7: bridge the whole channel over the band, overlapping both flanks by 0.1
	set f7 [list [expr {[lindex $L7 2] - 0.1}] $my0 [expr {[lindex $R6 0] + 0.1}] $my1]
	eco_no_foreign $f7 M7 VDD "FIX B M7 merge fill"
	set d7 [eco_min_foreign_gap $f7 M7 VDD 2.0]
	note "FIX B: M7 fill $f7, nearest foreign M7 $d7 um (rule $WMSPC)"
	if {$d7 < $WMSPC} { fatal "FIX B: the merged M7 plate would sit $d7 um from foreign M7" }
	add_shape -net VDD -layer M7 -rect $f7 -shape STRIPE -status ROUTED
	# M6: same channel, but only as high as the M6 flank actually runs
	set y6 [expr {min($my1, [lindex $R6 3])}]
	set f6 [list [expr {$rx1 - 0.1}] $my0 [expr {[lindex $R6 0] + 0.1}] $y6]
	eco_no_foreign $f6 M6 VDD "FIX B M6 merge fill"
	set d6 [eco_min_foreign_gap $f6 M6 VDD 2.0]
	note "FIX B: M6 fill $f6, nearest foreign M6 $d6 um (rule $WMSPC)"
	if {$d6 < $WMSPC} { fatal "FIX B: the merged M6 plate would sit $d6 um from foreign M6" }
	add_shape -net VDD -layer M6 -rect $f6 -shape STRIPE -status ROUTED
	incr wm_done
}
if {$wm_done != 1} {
	fatal "FIX B: merged $wm_done channels, expected exactly 1.  Zero means the M6.S.4/M7.S.4\
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

set left [g0_marker_count $REPORT_DIR/$DESIGN_NAME.verifyGeometry.$TAG.rpt]
note "acceptance: G0 M1 short markers $G0_BEFORE before, $left after"
if {$left > 0} {
	fatal "acceptance: $left G0 M1 short(s) survive after FIX B.  No collateral emitted."
}
set fh [open $REPORT_DIR/$DESIGN_NAME.verifyGeometry.$TAG.rpt r]
foreach ln [split [read $fh] "\n"] {
	if {[regexp {^ *(Cells|SameNet|Wiring|Short|Overlap|Antenna) *: *([0-9]+)} $ln -> k n]} {
		note "acceptance: verifyGeometry $k = $n"
	}
}
close $fh
set fh [open $REPORT_DIR/$DESIGN_NAME.verifyConnectivity.$TAG.rpt r]
foreach ln [split [read $fh] "\n"] {
	if {[regexp {Problem\(s\) \(IMPVFC-[0-9]+\)} $ln]} { note "acceptance:[string trimright $ln]" }
	if {[regexp {total info\(s\) created} $ln]} { note "acceptance:[string trimright $ln]" }
	if {[string match "*ram0/VSSE*unconnected terminal*" $ln]} { incr r0v }
}
close $fh
if {![info exists r0v]} { set r0v 0 }
note "acceptance: ram0/VSSE unconnected terminals = $r0v (must stay 0)"
if {$r0v > 0} { fatal "acceptance: the ECO re-opened $r0v ram0/VSSE terminal(s)" }

# M19c: one cut, every file.  A GDS repaired by an out-of-flow ECO whose LEF and
# xsim.v came from the unrepaired state is exactly what M19c shipped.
saveDesign $DATABASE_DIR/$DESIGN_NAME.signoff.innovus -def -netlist -rc -tcon
streamOut $OUTPUT_DIR/$DESIGN_NAME.gds2 -libName WorkLib -structureName $DESIGN_NAME \
	-stripes 1 -units 1000 -mode ALL -mapFile ../shared/innovus2gds.map
write_sdf $OUTPUT_DIR/$DESIGN_NAME.sdf
saveNetlist $OUTPUT_DIR/$DESIGN_NAME.xsim.v -excludeCellInst ANTENNA2A10TH
# ANTENNA DATA BEFORE lefOut, 2026-08-25.  MEASURED DEFECT IN THE ECO PATTERN:
# the P&R flow runs verifyProcessAntenna before its lefOut, so its abstract
# carries ANTENNAGATEAREA / ANTENNAMAXAREACAR / ANTENNAPARTIALMETALAREA on every
# signal pin -- 127 pins' worth.  tcm11_eco.tcl and drc_eco.tcl both call lefOut
# with no antenna pass in front of it, so EVERY post-harden ECO in this flow has
# silently re-emitted the tile abstract WITHOUT its antenna model:
#     out.pre_tcm11/hart_tile.lef   (P&R)  ANTENNAGATEAREA x130
#     out.pre_g0eco/hart_tile.lef   (P&R)  ANTENNAGATEAREA x127
#     out.zerodrc_FALLBACK/...lef   (ECO)  ANTENNAGATEAREA x0
# The tile is bound as a macro by MCU_hart, which is exactly the consumer that
# needs it.  One line fixes it and it costs seconds.
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
