################################################################################
# G0 IN-FLOW REPAIR -- the router-vs-cell-OBS M1 merge, DERIVED PER CUT.
#
# WHAT THIS REPLACES.  Three hand-authored post-harden ECOs repaired this class
# once each and then refused to run on any other cut:
#     tcl/cpr5b_eco.tcl   2026-08-15   tie_0_cell7  TIELOX1MA10TH   R180
#     tcl/tcm11_eco.tcl   2026-08-25   tie_0_cell6  TIELOX1MA10TH   R180
#     tcl/g0_eco.tcl      2026-08-25   g11129__6161 OR2X1MA10TH     R180
#                                      registers_reg[30][17] DFFRPQX1MA10TH MY
# Their refusal was correct as far as it went: a frozen coordinate list lands on
# clean geometry after any re-harden.  But the premise underneath all four --
# that the class is a placement consequence needing a surgical, per-site,
# OBS-shaped repair -- is WRONG, and this file is in two stages because of it.
#
# STAGE 1, and it is the one that almost always does the work: a BARE ecoRoute.
# G0 is a NanoRoute CONVERGENCE RESIDUAL.  routeDesign's detail router makes the
# shape, sees it, counts it in its own end-of-detail-route Short column, and
# runs out of iteration budget with the M1 count still oscillating 1..3.  A
# fresh ecoRoute invocation converges where more iterations of the same one did
# not: measured on two independent cuts, 19 s and 25 s, one of them with
# dontTouch set on the offending net.  No rip, no blockage, no mode change.
#
# STAGE 2, for whatever survives: the derived per-site repair the hand ECOs
# were doing, generalised.  Read the sites out of THIS cut's own verifyGeometry
# report, transform the offending cell's own LEF M1 OBS rects by THIS cut's
# placement, prove the transform by marker containment, rip, fence, ecoRoute,
# and re-verify.  This path exists because a residual class is known that
# ecoRoute cannot fix and can make worse -- see the driver's own comment.
#
# WHY IT CAN BE DERIVED AT ALL.  Every one of the four archived repairs is the
# same four steps with different numbers, and every number in them is a
# function of two things the run already knows: the marker line in
# rpt/hart_tile.verifyGeometry.signoff.rpt, and the cell master's OBS section in
# the LEF the run was initialised with.  Nothing else was ever design judgement.
#
# THE STAGE 2 BLOCKAGE RULE, and the evidence for it.  Per site:
#   * the ONE OBS M1 rect that CONTAINS the reported marker, grown by the
#     M1.S.1 spacing (0.090), and
#   * every other OBS M1 rect of the same instance whose transformed box is
#     within G0R_HALO (0.300) of the marker on BOTH axes, at its own size.
# g0r_selftest below replays the three archived sites through this rule from
# the LEF alone and checks the result against what the hand ECOs actually
# created.  Measured:
#     TIELOX1MA10TH  R180  4 blockages  IDENTICAL to tcm11_eco.tcl's four
#     OR2X1MA10TH    R180  2 blockages  IDENTICAL to g0_eco.tcl's site s1
#     DFFRPQX1MA10TH MY    4 blockages  IDENTICAL to g0_eco.tcl's site s2
# Box for box, to the micron, on all three -- so the halo is not a tuning knob
# that happens to work, it is the rule those repairs were already following by
# hand.  The rule deliberately does NOT use the cell bbox: CPR5b attempt #1 did,
# that also covers the rails and the cell's own pins, and ecoRoute answered with
# Short 23 / Overlap 16.
#
# ANTI-SILENCE.  Everything a human is meant to act on goes through logPuts.
# A pass that finds no sites logs how many report lines it EXAMINED and how
# many marker lines it matched, so "0 sites" can never be confused with "the
# parser never opened the file"; and g0r_selftest proves, on every run, that
# the LEF reader, the orientation transform and the containment test are all
# live even when this cut happens to have no G0 site at all.
################################################################################

# tuning, in one place
set G0R_GROW     0.090
set G0R_HALO     0.300
set G0R_CONVPASS 3
set G0R_MAXPASS  3

proc g0r_note {msg} { logPuts "### G0REPAIR ### $msg" }
proc g0r_warn {msg} { logPuts "G0REPAIR WARNING: $msg" }

################################################################################
# LEF OBS reader.  Returns the cell master's OBS rects on $layer in LEF R0
# coordinates, as a list of {x0 y0 x1 y1}.  Empty list means "not found", and
# the caller must treat that as a failure, not as "no obstruction".
################################################################################
proc g0r_lef_obs {cellname layer} {
	global G0R_LEF_FILES G0R_OBS_CACHE
	set key "$cellname|$layer"
	if {[info exists G0R_OBS_CACHE($key)]} { return $G0R_OBS_CACHE($key) }
	set rects {}
	set fromfile ""
	foreach f $G0R_LEF_FILES {
		if {![file readable $f]} { continue }
		set fh [open $f r]
		set inmac 0
		set inobs 0
		set curlay ""
		while {[gets $fh line] >= 0} {
			set t [string trim $line]
			if {!$inmac} {
				if {[string match "MACRO *" $t] && [lindex $t 1] eq $cellname} { set inmac 1 }
				continue
			}
			if {$t eq "END $cellname"} { break }
			if {$t eq "OBS"} { set inobs 1 ; set curlay "" ; continue }
			if {!$inobs} { continue }
			if {$t eq "END"} { set inobs 0 ; continue }
			if {[regexp {^LAYER\s+(\S+)\s*;} $t -> l]} { set curlay $l ; continue }
			if {$curlay ne $layer} { continue }
			if {[regexp {^RECT\s+(-?[0-9.]+)\s+(-?[0-9.]+)\s+(-?[0-9.]+)\s+(-?[0-9.]+)\s*;} $t -> a b c d]} {
				lappend rects [list $a $b $c $d]
			}
		}
		close $fh
		if {$inmac} { set fromfile $f ; break }
	}
	if {$fromfile eq ""} {
		g0r_warn "cell master '$cellname' is in none of the LEF files this run was given"
	} else {
		g0r_note "LEF: $cellname has [llength $rects] $layer OBS rect(s), read from $fromfile"
	}
	set G0R_OBS_CACHE($key) $rects
	return $rects
}

################################################################################
# geometry helpers
################################################################################
# transform a LEF-R0 rect into absolute coords for a cell whose placed box has
# lower-left ($x0,$y0) and size $W x $H, at orientation $orient.
proc g0r_abs {orient x0 y0 W H r} {
	foreach {lx0 ly0 lx1 ly1} $r {}
	switch -- $orient {
		R0   { set ax0 [expr {$x0+$lx0}]    ; set ax1 [expr {$x0+$lx1}]
		       set ay0 [expr {$y0+$ly0}]    ; set ay1 [expr {$y0+$ly1}] }
		MY   { set ax0 [expr {$x0+$W-$lx1}] ; set ax1 [expr {$x0+$W-$lx0}]
		       set ay0 [expr {$y0+$ly0}]    ; set ay1 [expr {$y0+$ly1}] }
		MX   { set ax0 [expr {$x0+$lx0}]    ; set ax1 [expr {$x0+$lx1}]
		       set ay0 [expr {$y0+$H-$ly1}] ; set ay1 [expr {$y0+$H-$ly0}] }
		R180 { set ax0 [expr {$x0+$W-$lx1}] ; set ax1 [expr {$x0+$W-$lx0}]
		       set ay0 [expr {$y0+$H-$ly1}] ; set ay1 [expr {$y0+$H-$ly0}] }
		default { return "" }
	}
	return [list $ax0 $ay0 $ax1 $ay1]
}
proc g0r_contains {outer inner} {
	foreach {ox0 oy0 ox1 oy1} $outer {}
	foreach {ix0 iy0 ix1 iy1} $inner {}
	return [expr {$ox0 <= $ix0+1e-6 && $oy0 <= $iy0+1e-6 && $ix1 <= $ox1+1e-6 && $iy1 <= $oy1+1e-6}]
}
# per-axis (box) gap between two rects; 0 on an axis means they overlap there.
proc g0r_axis_gap {a b} {
	foreach {ax0 ay0 ax1 ay1} $a {}
	foreach {bx0 by0 bx1 by1} $b {}
	set dx [expr {max($ax0 - $bx1, $bx0 - $ax1, 0.0)}]
	set dy [expr {max($ay0 - $by1, $by0 - $ay1, 0.0)}]
	return [list $dx $dy]
}

################################################################################
# THE RULE.  Given a cell master, its placed box/orientation and the reported
# marker, return {violated_abs blockage_list} or {} when the marker cannot be
# attributed to a single OBS rect.  Pure geometry -- no DB, no side effects --
# which is exactly what lets g0r_selftest exercise it.
################################################################################
proc g0r_blockages {cellname orient x0 y0 W H marker} {
	global G0R_GROW G0R_HALO
	set obs [g0r_lef_obs $cellname M1]
	if {[llength $obs] == 0} { return {} }
	set abs {}
	foreach r $obs {
		set a [g0r_abs $orient $x0 $y0 $W $H $r]
		if {$a eq ""} { return {} }
		lappend abs $a
	}
	set vio {}
	set nhit 0
	foreach a $abs {
		if {[g0r_contains $a $marker]} { set vio $a ; incr nhit }
	}
	g0r_note "  $nhit of [llength $abs] M1 OBS rect(s) contain the marker $marker"
	if {$nhit != 1} { return {} }
	set blks [list [list [expr {[lindex $vio 0]-$G0R_GROW}] [expr {[lindex $vio 1]-$G0R_GROW}] \
	                     [expr {[lindex $vio 2]+$G0R_GROW}] [expr {[lindex $vio 3]+$G0R_GROW}]]]
	foreach a $abs {
		if {$a eq $vio} { continue }
		foreach {dx dy} [g0r_axis_gap $a $marker] {}
		if {$dx > $G0R_HALO || $dy > $G0R_HALO} { continue }
		lappend blks $a
	}
	return [list $vio $blks]
}

################################################################################
# SELF-TEST / POSITIVE CONTROL.  Replays the three archived hand-repaired sites
# through g0r_blockages using nothing but the LEF, and compares the result with
# the blockages those ECOs actually created.  This runs on EVERY cut, including
# cuts with no G0 site, so a quiet repair pass is never mistaken for a dead one.
# Returns 1 on success.
################################################################################
proc g0r_selftest {} {
	# {tag cell orient x0 y0 W H marker expected_violated_abs expected_nblk}
	set cases {
		{tcm11 TIELOX1MA10TH R180 576.2 65.0 0.8 2.0
		 {576.820 65.950 576.905 66.050}
		 {576.815 65.510 576.905 66.400} 4}
		{g0eco_s1 OR2X1MA10TH R180 623.8 97.0 1.2 2.0
		 {624.810 97.450 624.865 97.550}
		 {624.775 97.255 624.865 97.700} 2}
		{g0eco_s2 DFFRPQX1MA10TH MY 476.2 175.0 4.8 2.0
		 {480.750 176.410 480.825 176.590}
		 {480.735 176.185 480.825 176.590} 4}
	}
	set ok 1
	foreach c $cases {
		foreach {tag cell orient x0 y0 W H marker expvio expn} $c {}
		set r [g0r_blockages $cell $orient $x0 $y0 $W $H $marker]
		if {[llength $r] != 2} {
			logPuts "FATAL (G0REPAIR SELFTEST/$tag): the rule could not attribute the archived marker to one OBS rect."
			set ok 0 ; continue
		}
		set vio  [lindex $r 0]
		set blks [lindex $r 1]
		set bad 0
		foreach a $vio b $expvio { if {abs($a - $b) > 0.0005} { set bad 1 } }
		if {$bad} {
			logPuts "FATAL (G0REPAIR SELFTEST/$tag): violated OBS rect derived as $vio, archived repair used $expvio."
			set ok 0
		}
		if {[llength $blks] != $expn} {
			logPuts "FATAL (G0REPAIR SELFTEST/$tag): [llength $blks] blockage(s) derived, expected $expn -- the LEF or the halo has changed under this rule."
			set ok 0
		}
		g0r_note "SELFTEST/$tag: violated $vio, [llength $blks] blockage(s) (expected $expn)"
	}
	if {$ok} {
		logPuts "### UNL STATUS ### : G0REPAIR selftest PASSED -- LEF reader, orientation transform and containment test all live on 3 archived sites"
	} else {
		logPuts "### UNL STATUS ### : G0REPAIR selftest FAILED -- the derivation is broken; do not trust a quiet repair pass on this run"
	}
	return $ok
}

################################################################################
# REPORT READER.  Pulls the G0 marker list out of a verifyGeometry report.
# Returns a list of {net inst x0 y0 x1 y1}.  ALWAYS reports how much of the
# file it looked at, because "parsed nothing" and "read nothing" have to be
# distinguishable -- that confusion is how the 2026-08-17 short shipped.
################################################################################
proc g0r_parse_markers {rptfile} {
	if {![file exists $rptfile]} {
		g0r_warn "verifyGeometry report $rptfile does not exist -- the G0 class was NOT checked on this cut"
		return {}
	}
	set fh [open $rptfile r]
	set lines [split [read $fh] "\n"]
	close $fh
	set sites {}
	set nmark 0
	set n [llength $lines]
	for {set i 0} {$i < $n} {incr i} {
		set ln [lindex $lines $i]
		if {![regexp {^SHORT: Regular (?:Wire|Via) of Net (.+?) *& Blockage of Cell (.+?) *\( *M1 *\)} $ln -> net inst]} { continue }
		incr nmark
		set bounds ""
		for {set j [expr {$i+1}]} {$j < $i+5 && $j < $n} {incr j} {
			if {[regexp {Bounds *: *\( *([-0-9.]+), *([-0-9.]+) *\) *\( *([-0-9.]+), *([-0-9.]+) *\)} [lindex $lines $j] -> a b c d]} {
				set bounds [list $a $b $c $d] ; break
			}
		}
		if {$bounds eq ""} {
			g0r_warn "marker at report line [expr {$i+1}] has no Bounds line within 4 lines -- cannot repair it: $ln"
			continue
		}
		lappend sites [concat [list [string trim $net] [string trim $inst]] $bounds]
	}
	g0r_note "read $n line(s) of $rptfile; $nmark G0 M1 marker line(s) matched, [llength $sites] with usable bounds"
	return $sites
}

################################################################################
# instance lookup that does not depend on dbGet's glob semantics.  Instance
# names in this design contain '[' and ']' (registers_reg[30][17]), which are
# character-class metacharacters to a glob matcher.
################################################################################
proc g0r_inst {name} {
	if {![catch {set p [dbGetInstByName $name]}]} {
		if {$p ne "" && $p ne "0x0" && $p != 0} { return $p }
	}
	set p [dbGet -p top.insts.name $name -e]
	if {$p eq "" || $p eq "0x0" || $p eq "0"} { return "" }
	if {[llength $p] != 1} { return "" }
	if {[dbGet $p.name] ne $name} { return "" }
	return $p
}

################################################################################
# ONE REPAIR PASS.  Reads $rptfile, repairs every site it can derive, and
# returns a 3-element list {nmarkers nrepaired nrefused}.  Nothing is ripped
# until every site in the pass has passed its own containment check.
################################################################################
proc g0r_pass {rptfile tag} {
	set sites [g0r_parse_markers $rptfile]
	if {[llength $sites] == 0} { return [list 0 0 0] }

	# ---- PHASE 1: derive everything, touch nothing -------------------------
	set plan {}
	set refused 0
	foreach s $sites {
		foreach {net inst mx0 my0 mx1 my1} $s {}
		set marker [list $mx0 $my0 $mx1 $my1]
		g0r_note "site: net '$net' vs cell '$inst' marker $marker"
		if {[lsearch -exact {VDD VSS VDD_SW VNW VPW} $net] >= 0} {
			g0r_warn "  net '$net' is a supply -- this repair rips signal routing only; REFUSED"
			incr refused ; continue
		}
		set ip [g0r_inst $inst]
		if {$ip eq ""} {
			g0r_warn "  instance '$inst' not found in this design; REFUSED"
			incr refused ; continue
		}
		set ib [lindex [dbGet $ip.box] 0]
		set io [dbGet $ip.orient]
		set ic [dbGet $ip.cell.name]
		foreach {bx0 by0 bx1 by1} $ib {}
		set W [expr {$bx1 - $bx0}]
		set H [expr {$by1 - $by0}]
		g0r_note "  $inst is $ic at ($bx0,$by0) ${W}x${H} $io"
		if {[lsearch -exact {R0 R180 MX MY} $io] < 0} {
			g0r_warn "  orientation '$io' is not one of R0/R180/MX/MY -- the OBS transform is not defined for it; REFUSED"
			incr refused ; continue
		}
		set r [g0r_blockages $ic $io $bx0 $by0 $W $H $marker]
		if {[llength $r] != 2} {
			g0r_warn "  cannot attribute the marker to exactly one M1 OBS rect of $ic -- a blockage here would land on geometry this rule was not derived for; REFUSED"
			incr refused ; continue
		}
		set np [dbGetNetByName $net]
		if {$np eq "" || $np == 0x0} {
			g0r_warn "  net '$net' not found; REFUSED"
			incr refused ; continue
		}
		lappend plan [list $net $np $inst $ic [lindex $r 0] [lindex $r 1]]
	}
	if {[llength $plan] == 0} {
		g0r_note "pass $tag: nothing repairable ([llength $sites] site(s), $refused refused)"
		return [list [llength $sites] 0 $refused]
	}

	# ---- PHASE 2: rip, fence -----------------------------------------------
	set blknames {}
	set dtsaved {}
	set ripped {}
	foreach p $plan {
		foreach {net np inst ic vio blks} $p {}
		if {[lsearch -exact $ripped $net] < 0} {
			if {[dbGet $np.dontTouch]} { dbSet $np.dontTouch false ; lappend dtsaved $net ; g0r_note "  $net dontTouch cleared" }
			set before [llength [dbGet -e $np.wires]]
			deselectAll
			editSelect -net $net
			editDelete -selected
			deselectAll
			set after [llength [dbGet -e $np.wires]]
			g0r_note "  RIP $net wires $before -> $after"
			if {$after >= $before} {
				logPuts "FATAL (G0REPAIR): rip of $net removed no wires ($before -> $after) -- editSelect/editDelete did not do what this pass assumes."
				return [list [llength $sites] -1 $refused]
			}
			lappend ripped $net
		}
		set i 0
		foreach b $blks {
			set nm g0r_${tag}_[llength $blknames]_$i
			if {[catch {createRouteBlk -name $nm -layer M1 -cutLayer VIA1 -box $b} err]} {
				logPuts "FATAL (G0REPAIR): createRouteBlk $nm on $b failed: $err"
				return [list [llength $sites] -1 $refused]
			}
			lappend blknames $nm
			incr i
		}
		g0r_note "  fenced $inst ($ic) with [llength $blks] M1+VIA1 blockage(s); violated OBS rect $vio"
	}
	g0r_note "pass $tag: [llength $ripped] net(s) ripped, [llength $blknames] blockage(s) created"

	# ---- PHASE 3: re-route, unfence ----------------------------------------
	# THE -fix_drc RUNS WHILE THE FENCE IS STILL UP.  Measured on the 2026-08-25
	# pre-repair database, same cut, same two sites, only the ordering different:
	#
	#   rip, fence, ecoRoute, UNFENCE, then ecoRoute -fix_drc
	#       Short 0 -> 1.  The fixer routed back into the SAME flop's OBS, one
	#       rect below the one it had just been routed out of (new marker at
	#       480.905,175.440).  Wiring 5 -> 4.
	#   rip, fence, ecoRoute, ecoRoute -fix_drc, then UNFENCE
	#       Short 0 and Wiring 5 -> 4.  Both.
	#
	# NARROW THE CLAIM, because a separate investigation measured the opposite
	# on the RAW defect: `ecoRoute -fix_drc` run on the unrepaired signoff DB
	# took Short 2 -> 0 and created nothing.  So -fix_drc is not a generator of
	# this class in general.  What is measured is only this: once the net has
	# been ripped and re-routed, dropping the fence BEFORE the DRC fixer lets it
	# walk straight back into the obstruction it was just steered out of.  Keep
	# the fence up until both routers have run.
	ecoRoute
	ecoRoute -fix_drc
	foreach nm $blknames { catch { deleteRouteBlk -name $nm } }
	g0r_note "pass $tag: [llength $blknames] blockage(s) removed"
	foreach net $dtsaved {
		set np [dbGetNetByName $net]
		if {$np ne "" && $np != 0x0} { dbSet $np.dontTouch true ; g0r_note "  dontTouch restored on $net" }
	}
	# EVERY RIPPED NET MUST HAVE COME BACK.  A rip that is never re-routed
	# DELETES the shorting wire, so the G0 marker disappears and the acceptance
	# gate goes green over an OPEN net -- a repair that looks exactly like a
	# success and is worse than the defect.  Ask each net directly.
	set dead {}
	foreach net $ripped {
		set np [dbGetNetByName $net]
		set w [llength [dbGet -e $np.wires]]
		g0r_note "  post-route wires on $net = $w"
		if {$w == 0} { lappend dead $net }
	}
	if {[llength $dead] > 0} {
		logPuts "FATAL (G0REPAIR): [llength $dead] ripped net(s) carry NO wires after the re-route: $dead"
		logPuts "                  The merge is gone because the net is gone. Nothing may be emitted from this state."
		return [list [llength $sites] -1 $refused]
	}
	return [list [llength $sites] [llength $plan] $refused]
}

################################################################################
# NON-ANTENNA TOTAL, from a verifyGeometry report's own summary block.
# Used to detect a TRADE: a re-route that closes a merge by opening something
# else is not a repair, and the count is the only thing that says so.
################################################################################
proc g0r_nonantenna_total {rptfile} {
	set tot 0
	if {![file exists $rptfile]} { return -1 }
	set fh [open $rptfile r]
	while {[gets $fh ln] >= 0} {
		if {[regexp {^\s*(Cells|SameNet|Wiring|Short|Overlap)\s*:\s*(\d+)} $ln -> k v]} { incr tot $v }
	}
	close $fh
	return $tot
}

################################################################################
# THE DRIVER.  Two stages, cheapest first.
#
# STAGE 1 -- BARE ecoRoute, NOTHING RIPPED, NO BLOCKAGE.
#
# This is the finding that shrank the whole problem, and it is worth stating
# plainly because four hand ECOs were written on the opposite assumption.  G0 is
# not a placement consequence and it is not the router failing to see the cell's
# OBS.  It is a NanoRoute CONVERGENCE RESIDUAL: routeDesign's detail router
# creates the shape, SEES it, counts it in its own end-of-globalDetailRoute
# table, and runs out of iteration budget before clearing it.  From
# log/hart_tile.log after 22 detail-route optimisation iterations:
#
#     #    By Layer and Type :
#     #          MetSpc    Short   MinStp   Totals
#     #   M1          0        2        0        2
#     #   M2          3        2        2        7
#     #   Totals      3        4        2        9
#     #Complete Detail Routing.
#
# The M1 count oscillates 1..3 from iteration 15 to 22 and never clears.  A
# FRESH ecoRoute invocation converges where more iterations of the same one did
# not.  Measured on two INDEPENDENT cuts:
#     2026-08-25 VSS-fix cut   Short 2 -> 0 in 19 s, second call idempotent
#     2026-08-15 CPR5a cut     both markers -> 0 in 25 s, EVEN THOUGH the
#                              offending net carried dontTouch=true
# So the rip, the dontTouch dance and the OBS-shaped blockages are not needed
# for the common case.  They are kept below as STAGE 2 because a residual class
# exists that ecoRoute cannot fix.
#
# STAGE 1 IS GATED, NEVER TRUSTED.  On the 2026-08-15 placement the same bare
# ecoRoute TRADED one site for a NEW hard short against a VDD stripe at
# (505.25,420.31) -- the PG-stripe-squeezed sibling class, whose verdict is a
# PLACEMENT NUDGE and which is genuinely not route-fixable.  So every pass
# re-measures BOTH the merge count and the non-antenna total, and a total that
# goes up is reported as a trade rather than counted as progress.
#
# STAGE 2 -- the derived per-site rip + OBS fence, for whatever survives.
#
# Returns {before after passes}; after < 0 means the run must be abandoned.
################################################################################
proc g0r_repair_loop {rptdir design pre_rpt} {
	global G0R_CONVPASS G0R_MAXPASS
	set before [llength [g0r_parse_markers $pre_rpt]]
	set base   [g0r_nonantenna_total $pre_rpt]
	logPuts "### UNL STATUS ### : G0REPAIR -- $before router-vs-cell-OBS M1 merge(s), $base non-antenna marker(s) BEFORE repair"
	if {$before == 0} { return [list 0 0 0] }

	set cur   $pre_rpt
	set left  $before
	set conv  0
	while {$left > 0 && $conv < $G0R_CONVPASS} {
		incr conv
		g0r_note "STAGE 1 pass $conv: bare ecoRoute -- nothing ripped, no blockage"
		ecoRoute
		set cur $rptdir/$design.verifyGeometry.g0converge.p$conv.rpt
		verifyGeometry -error 100000 -warning 100000 -report $cur
		set left [llength [g0r_parse_markers $cur]]
		set tot  [g0r_nonantenna_total $cur]
		logPuts "### UNL STATUS ### : G0REPAIR STAGE 1 pass $conv -- merges $left, non-antenna total $tot (before repair: $base)"
		if {$tot > $base} {
			logPuts "G0REPAIR WARNING: the re-route TRADED geometry -- non-antenna markers $base -> $tot."
			logPuts "                  On the 2026-08-15 cut this class was a Regular-Wire-vs-VDD-stripe"
			logPuts "                  short that ecoRoute cannot fix; its verdict is a PLACEMENT NUDGE."
			logPuts "                  See the class census at the signoff gate for what is actually there."
		}
	}
	if {$left == 0} {
		logPuts "### UNL STATUS ### : G0REPAIR -- closed by $conv bare ecoRoute pass(es); the derived site repair was not needed"
		return [list $before 0 $conv]
	}

	logPuts "### UNL STATUS ### : G0REPAIR -- $left merge(s) survive $conv bare ecoRoute pass(es); falling back to the derived per-site repair"
	set pass 0
	while {$pass < $G0R_MAXPASS} {
		incr pass
		set r [g0r_pass $cur s2p$pass]
		foreach {nm nrep nref} $r {}
		if {$nrep < 0} {
			logPuts "FATAL (G0REPAIR): STAGE 2 pass $pass aborted mid-repair -- the design now holds ripped routing."
			return [list $before -1 [expr {$conv + $pass}]]
		}
		if {$nrep == 0} {
			logPuts "### UNL STATUS ### : G0REPAIR -- STAGE 2 pass $pass repaired nothing ($nm site(s), $nref refused); stopping"
			break
		}
		set cur $rptdir/$design.verifyGeometry.g0repair.p$pass.rpt
		verifyGeometry -error 100000 -warning 100000 -report $cur
		set left [llength [g0r_parse_markers $cur]]
		logPuts "### UNL STATUS ### : G0REPAIR -- STAGE 2 pass $pass repaired $nrep site(s), $left merge(s) remain"
		if {$left == 0} { return [list $before 0 [expr {$conv + $pass}]] }
	}
	return [list $before $left [expr {$conv + $pass}]]
}
