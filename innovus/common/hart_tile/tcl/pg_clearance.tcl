################################################################################
# PG CLEARANCE -- one spacing check for every post-route PG metal addition.
#
# THE CLASS THIS EXISTS FOR.  Everything below the post-route verifyGeometry in
# hart_tile.innovus.tcl adds M1/M2/M3 power metal and power vias into a design
# whose signal routing is already finished.
# Until now not one of those passes asked whether the metal it was about to lay
# had room beside the routed signals it was landing next to.
# The result is a spacing violation that no via parameter and no fabric
# parameter controls, that is ABSENT from the post-route verifyGeometry because
# it does not exist yet at that point, and that appears only at signoff.
# Measured on the 2026-08-26 via-split cut: M1.S.1 at (433.415,208.145),
# 0.076 um against a 0.090 um rule, between the M1 landing pad of a VDD VIA1
# that the PG4/F2 pass created and a routed M1 wire of core/.../n_551.
#
# WHY IT NEEDS ITS OWN FILE.  The check has to be the SAME check everywhere.
# A per-pass containment test written by hand is what the flow had, and it is
# how the class survived: the strap-grid pass tested for a foreign M3 shape
# INSIDE its own footprint, which is a short test, not a spacing test, and it
# reported "0 blocked" on a cut that shipped a spacing violation 200 um away.
#
# WHAT IT MEASURES, AND WHAT IT REFUSES TO GUESS.
#
# 1. The numbers come from the DECK, not from this file.
#    signoff_mp/decks/blockdrc.rul carries M1_S_1, M2_S_1 and the wide-metal
#    tiers beside them, and pgc_deck_load reads them at run time.
#    Where the deck defines a name twice (the HALF_NODE branches) the LARGER
#    value is kept, because this check may only ever be stricter than signoff.
#
# 2. The rule is NET-BLIND, and that is not the same as net-agnostic.
#    Calibre measures a SPACE between polygons, so two SAME-NET shapes 0.05 um
#    apart violate M2.S.1 exactly as two foreign ones do; that is the whole
#    reason the retired wm_merge pass fixed M6.S.4 by MERGING shapes rather
#    than moving them.
#    So this check refuses a placement whose gap to ANY neighbour falls in the
#    open interval (0, rule), and permits a same-net neighbour it TOUCHES,
#    which is what a PG fill is normally for.
#    Refusing same-net metal that abuts would break the fabric for no reason.
#
# 3. Via metal is not sWire metal, and this is the trap that makes a naive
#    version of this check report all clear on the very site it was written
#    for.  The VDD VIA1 above is stored as an sViaInst; the widest M1 it puts
#    on the layout is 433.085..433.415, and the sWire beside it is only
#    433.15..433.35.  A check that collects dbQuery -objType sWire and stops
#    there measures 0.105 um of clearance at a site Calibre calls 0.076.
#    pgc_collect therefore reads sViaInst.botRects/topRects and viaInst's own,
#    which are in DESIGN coordinates and are the real thing.
#
# POSITIVE CONTROL, WHICH IS THE POINT.  pgc_selftest replays fixed rectangles
# with known answers through the arithmetic, and the tile-wide census in
# pgc_census reproduces Calibre's verdict on a finished database.
# On the 2026-08-26 via-split cut the census names exactly the two sites that
# blockdrc named and nothing else, out of a 1592-rulecheck deck.
# A check that returns "all clear" because its query returned nothing is the
# failure this codebase keeps producing, so pgc_probe reports how many
# neighbours it EXAMINED and never reports a verdict it did not measure.
################################################################################

proc pgc_note {msg} { logPuts "### PGCLEAR ### $msg" }

################################################################################
# DECK
################################################################################
# Parse `VARIABLE <NAME> <value>` out of a Calibre rule deck.
#
# Conditional branches are not evaluated, so a name defined in both arms of an
# #IFDEF has two values and this reader has to choose.  IT CHOOSES DIFFERENTLY
# FOR A SPACING AND FOR A TRIGGER, and the first version of this file got that
# backwards on the triggers.
#
# For a spacing VALUE the larger is stricter, so the larger is kept.
# For a trigger THRESHOLD -- <tier>_W and <tier>_L -- the larger makes the tier
# fire LESS often, which is looser, so the SMALLER is kept.
# Taking the max of both shipped a real M2.S.2: the deck in use has
# M2_S_2_L = 0.38 in one arm and 0.42 in the other, the site at (539.795,
# 223.100) has a 0.40 um parallel run, and a 0.42 threshold does not fire on it.
# Calibre's does.  Measured 0.105 um against a rule of 0.12.
proc pgc_is_trigger {nm} {
	return [regexp {_S_[0-9_]*_(W|L)$} $nm]
}
proc pgc_deck_load {path} {
	global PGC_V PGC_DECK_N PGC_DECK_PATH
	catch {unset PGC_V}
	set PGC_DECK_N 0
	set PGC_DECK_PATH $path
	if {[catch {set fh [open $path r]} e]} {
		pgc_note "DECK UNREADABLE: $path ($e)"
		return 0
	}
	while {[gets $fh line] >= 0} {
		if {![regexp {^\s*VARIABLE\s+([A-Za-z0-9_]+)\s+([-+0-9.eE]+)} $line -> nm val]} { continue }
		if {![string is double -strict $val]} { continue }
		if {[info exists PGC_V($nm)]} {
			if {[pgc_is_trigger $nm]} {
				if {$val < $PGC_V($nm)} { set PGC_V($nm) $val }
			} elseif {$val > $PGC_V($nm)} {
				set PGC_V($nm) $val
			}
		} else {
			set PGC_V($nm) $val
			incr PGC_DECK_N
		}
	}
	close $fh
	pgc_note "deck $path parsed, $PGC_DECK_N distinct VARIABLE name(s)"
	return $PGC_DECK_N
}
proc pgc_v {nm} {
	global PGC_V
	if {[info exists PGC_V($nm)]} { return $PGC_V($nm) }
	return ""
}

# Rectangle helpers.
proc pgc_w {b} {
	foreach {x0 y0 x1 y1} $b {}
	set dx [expr {$x1 - $x0}] ; set dy [expr {$y1 - $y0}]
	return [expr {$dx < $dy ? $dx : $dy}]
}
# Edge to edge distance, 0.0 when the rectangles touch or overlap.
proc pgc_gap {a b} {
	foreach {ax0 ay0 ax1 ay1} $a {}
	foreach {bx0 by0 bx1 by1} $b {}
	set dx [expr {max($ax0 - $bx1, $bx0 - $ax1, 0.0)}]
	set dy [expr {max($ay0 - $by1, $by0 - $ay1, 0.0)}]
	return [expr {sqrt($dx*$dx + $dy*$dy)}]
}
# Parallel run length: the projection the two rectangles share on the axis they
# face each other across.  Two rectangles that only meet at a corner run 0.
proc pgc_prun {a b} {
	foreach {ax0 ay0 ax1 ay1} $a {}
	foreach {bx0 by0 bx1 by1} $b {}
	set dx [expr {max($ax0 - $bx1, $bx0 - $ax1, 0.0)}]
	set dy [expr {max($ay0 - $by1, $by0 - $ay1, 0.0)}]
	if {$dx > 0.0 && $dy > 0.0} { return 0.0 }
	if {$dx > 0.0} { return [expr {max(min($ay1,$by1) - max($ay0,$by0), 0.0)}] }
	return [expr {max(min($ax1,$bx1) - max($ax0,$bx0), 0.0)}]
}
# Required spacing between two rectangles on $layer, from the deck.
# The base tier is <L>_S_1; each wide-metal tier fires on its own two deck
# conditions, one metal line wider than <tier>_W and a parallel run longer than
# <tier>_L, exactly as the rulecheck states them.
proc pgc_req {layer a b} {
	set s [pgc_v ${layer}_S_1]
	if {$s eq ""} { return "" }
	set wmax [expr {max([pgc_w $a], [pgc_w $b])}]
	set pr   [pgc_prun $a $b]
	foreach t [list S_2 S_2_1 S_2_2 S_2_3 S_3 S_4] {
		set tv [pgc_v ${layer}_${t}]
		set tw [pgc_v ${layer}_${t}_W]
		set tl [pgc_v ${layer}_${t}_L]
		if {$tv eq "" || $tw eq "" || $tl eq ""} { continue }
		# STRICT, WITH A TOLERANCE.  The deck says "> W" and "> L", and a rail
		# chunk 0.300 um wide beside a 0.380 um via pad hits both thresholds
		# EXACTLY.  Comparing raw doubles made 0.38 > 0.38 true often enough to
		# manufacture thirteen findings on a database whose signoff DRC has none
		# of them; every one was an exact tie.  A rule that fires on equality is
		# not the rule the deck states.
		if {$wmax > $tw + 1.0e-6 && $pr > $tl + 1.0e-6 && $tv > $s} { set s $tv }
	}
	return $s
}

################################################################################
# COLLECTION
################################################################################
# dbGet wraps a list-valued attribute once per object and once per list, so
# `$sViaInst.botRects` comes back as {{{x0 y0 x1 y1}}} and a plain foreach over
# it yields ONE element of length 1, not a rectangle.
# The first version of this file filtered those out on [llength] != 4 and so
# collected no via metal at all, which is the same silent blindness the header
# warns about, arrived at from the other direction.
# pgc_rects descends until it finds four numbers and refuses to recurse on a
# scalar.
proc pgc_rects {v {depth 0}} {
	if {$depth > 4} { return {} }
	if {[llength $v] == 4 && [string is double -strict [lindex $v 0]] \
	    && [string is double -strict [lindex $v 3]]} { return [list $v] }
	set out {}
	foreach e $v {
		if {$e eq $v} { continue }
		foreach r [pgc_rects $e [expr {$depth + 1}]] { lappend out $r }
	}
	return $out
}
# CELL METAL, WHICH IS NOT IN THE NET DATABASE AT ALL.
#
# The second run with this file in place moved the placement and produced five
# markers of the SAME class as the M1.S.1 it was written for, at the same x, and
# the checker did not see one of them:
#   SPACING: Special Via of Net VDD & Pin of Cell ...RC_CGIC_INST ( M1 )
#            (433.415,220.360)  0.065 vs 0.09
# A standard cell's own M1 -- its pin ports and its OBS -- belongs to no net and
# appears in no dbQuery of wires, special wires or vias.  Calibre sees it,
# Innovus verifyGeometry sees it, and a checker built only on the net database
# reports all clear beside it.  That is this codebase's signature defect arriving
# from a direction the first version of this file did not cover.
#
# The rects come from the same LEF files and the same placement transform that
# tcl/g0_repair.tcl already proves on three archived sites every run.
#
# POWER AND GROUND PINS ARE EXCLUDED, and that is a deliberate under-report.
# A PG via is SUPPOSED to land on a cell's VDD/VSS/VNW/VPW bar; calling that a
# short would refuse every tap and header pad in the tile.  Their rects are
# dropped rather than mis-attributed, so this reader answers "is there SIGNAL or
# OBS metal too close", and nothing else.
#
# For the same reason a ZERO gap to cell metal is not reported as a SHORT here:
# that class is the router-versus-cell-OBS merge, tcl/g0_repair.tcl owns it, and
# it is measured on it.  This reader only ever adds the SPACING question.
proc pgc_lef_rects {cellname layer} {
	global G0R_LEF_FILES PGC_LEF_CACHE PGC_LEF_MISS
	set key "$cellname|$layer"
	if {[info exists PGC_LEF_CACHE($key)]} { return $PGC_LEF_CACHE($key) }
	set rects {}
	set found 0
	if {![info exists G0R_LEF_FILES]} {
		if {![info exists PGC_LEF_MISS(nolef)]} {
			pgc_note "G0R_LEF_FILES is not set, so NO cell pin or OBS metal is being checked"
			set PGC_LEF_MISS(nolef) 1
		}
		set PGC_LEF_CACHE($key) {}
		return {}
	}
	foreach f $G0R_LEF_FILES {
		if {![file readable $f]} { continue }
		set fh [open $f r]
		set inmac 0 ; set mode none ; set pinname "" ; set pinuse SIGNAL ; set curlay ""
		while {[gets $fh line] >= 0} {
			set t [string trim $line]
			if {!$inmac} {
				if {[string match "MACRO *" $t] && [lindex $t 1] eq $cellname} { set inmac 1 }
				continue
			}
			if {$t eq "END $cellname"} { break }
			if {[regexp {^PIN\s+(\S+)} $t -> nm]} {
				set mode pin ; set pinname $nm ; set pinuse SIGNAL ; set curlay "" ; continue
			}
			if {$mode eq "pin" && $t eq "END $pinname"} { set mode none ; set curlay "" ; continue }
			if {$t eq "OBS"} { set mode obs ; set curlay "" ; continue }
			if {$t eq "END"} { if {$mode eq "obs"} { set mode none } ; set curlay "" ; continue }
			if {$t eq "PORT"} { set curlay "" ; continue }
			if {[regexp {^USE\s+(\S+)} $t -> u]} { set pinuse [string toupper $u] ; continue }
			if {[regexp {^LAYER\s+(\S+)} $t -> l]} { set curlay $l ; continue }
			if {$curlay ne $layer} { continue }
			if {$mode eq "pin" && ($pinuse eq "POWER" || $pinuse eq "GROUND")} { continue }
			if {$mode ne "pin" && $mode ne "obs"} { continue }
			if {[regexp {^RECT\s+(-?[0-9.]+)\s+(-?[0-9.]+)\s+(-?[0-9.]+)\s+(-?[0-9.]+)\s*;} $t -> a b c d]} {
				lappend rects [list $a $b $c $d]
			}
		}
		close $fh
		if {$inmac} { set found 1 ; break }
	}
	if {!$found && ![info exists PGC_LEF_MISS($cellname)]} {
		pgc_note "cell master '$cellname' is in none of the LEF files this run was given, so its own metal is NOT being checked"
		set PGC_LEF_MISS($cellname) 1
	}
	set PGC_LEF_CACHE($key) $rects
	return $rects
}
# Every piece of metal on $layer whose rectangle meets $area, as
# {net kind x0 y0 x1 y1}.
# Vias are queried over a bloated window because a via's landing pad reaches
# outside the box that finds it, and their rectangles are read from
# botRects/topRects, which are the only place the true pad extent exists.
proc pgc_collect {area layer} {
	set out {}
	foreach {qx0 qy0 qx1 qy1} $area {}
	set varea [list [expr {$qx0 - 0.6}] [expr {$qy0 - 0.6}] [expr {$qx1 + 0.6}] [expr {$qy1 + 0.6}]]
	foreach t {sWire wire} {
		if {[catch {set objs [dbQuery -area $area -objType $t]}]} { continue }
		foreach o $objs {
			if {[dbGet -e $o.layer.name] ne $layer} { continue }
			set b [lindex [dbGet -e $o.box] 0]
			if {[llength $b] != 4} { continue }
			lappend out [concat [list [dbGet -e $o.net.name] $t] $b]
		}
	}
	if {[info procs g0r_abs] ne ""} {
		if {[catch {set insts [dbQuery -area $varea -objType inst]}]} { set insts {} }
		foreach o $insts {
			set cn [dbGet -e $o.cell.name]
			if {$cn eq ""} { continue }
			set rl [pgc_lef_rects $cn $layer]
			if {[llength $rl] == 0} { continue }
			set ib [lindex [dbGet -e $o.box] 0]
			if {[llength $ib] != 4} { continue }
			foreach {ix0 iy0 ix1 iy1} $ib {}
			set iw [expr {$ix1 - $ix0}] ; set ih [expr {$iy1 - $iy0}]
			# HARD MACROS ARE EXCLUDED, and the reason is what LEF OBS IS.
			# For a standard cell the OBS tracks the drawn M1 closely enough to
			# measure against.  For a macro it is a ROUTING OBSTRUCTION: ram0's
			# is one 319 x 208 um cover rectangle, and treating it as metal put
			# eleven VSS rails in breach of M1.S.4 at 0.475 um against a rule of
			# 1.50 on a database whose signoff DRC has none of them.
			# A std cell row is 2 or 4 um tall, so the height test separates the
			# two cleanly and says which side of it a cell fell on.
			if {$ih > 10.0} {
				global PGC_MACRO_SKIP
				if {![info exists PGC_MACRO_SKIP($cn)]} {
					pgc_note "instance of '$cn' is [format %.1f $iw] x [format %.1f $ih] um, so it is a macro and its LEF OBS is a routing obstruction rather than metal; its own geometry is NOT being checked"
					set PGC_MACRO_SKIP($cn) 1
				}
				continue
			}
			set ior [dbGet -e $o.orient]
			foreach r $rl {
				set a [g0r_abs $ior $ix0 $iy0 $iw $ih $r]
				if {$a eq ""} {
					global PGC_ORIENT_MISS
					if {![info exists PGC_ORIENT_MISS($ior)]} {
						pgc_note "orientation '$ior' has no transform, so the cell metal of instances at that orientation is NOT being checked"
						set PGC_ORIENT_MISS($ior) 1
					}
					continue
				}
				lappend out [concat [list "<cell>" cell] $a]
			}
		}
	}
	foreach t {sVia via} {
		if {[catch {set objs [dbQuery -area $varea -objType $t]}]} { continue }
		foreach o $objs {
			set vm [dbGet -e $o.via]
			if {$vm eq "" || $vm eq "0x0"} { continue }
			set nm [dbGet -e $o.net.name]
			foreach {side lay} [list botRects [dbGet -e $vm.botLayer.name] \
			                         topRects [dbGet -e $vm.topLayer.name]] {
				if {$lay ne $layer} { continue }
				foreach r [pgc_rects [dbGet -e $o.$side]] {
					lappend out [concat [list $nm $t/$side] $r]
				}
			}
		}
	}
	return $out
}

################################################################################
# THE CHECK
################################################################################
# Measure $box on $layer belonging to $net against everything within $halo.
#
# CALIBRE MEASURES POLYGONS, NOT RECTANGLES, and skipping that is how the first
# version of this proc produced 200 findings on a database whose signoff DRC has
# two.  `EXT M2 < M2_S_1` runs on the MERGED M2 layer, so two rectangles 0.07 um
# apart that a third rectangle overlaps are one polygon with no space in it.
# Every one of those 200 was a pair bridged by the strap they both sit on.
#
# So the neighbourhood is unioned first: any two rectangles that touch or
# overlap are one object, and only rectangles in a DIFFERENT object than $box
# are measured against it.
# A foreign net that lands in the same object is not a spacing question at all,
# it is a SHORT, and is reported as one.
#
# The union is built only when the cheap pass finds a candidate, because the
# all-clear case is the common one and it is O(n) instead of O(n squared).
#
# Returns {verdict gap req othernet otherkind otherbox examined}, verdict one of
#   CLEAR    nothing outside this polygon is within the applicable rule
#   MERGED   the only contact is same-net metal it touches, which is legal
#   SPACING  a separate polygon sits in the open interval (0, rule)
#   SHORT    a FOREIGN net is part of this polygon
#   NODECK   the deck did not yield a rule for this layer, so NOTHING was judged
# NODECK is deliberately not CLEAR.  A check that cannot measure must not report
# a pass, which is the failure mode this whole file is written against.
proc pgc_probe {box layer net {halo 0.6}} {
	if {[pgc_v ${layer}_S_1] eq ""} { return [list NODECK "" "" "" "" "" 0] }
	foreach {x0 y0 x1 y1} $box {}
	set area [list [expr {$x0 - $halo}] [expr {$y0 - $halo}] \
	               [expr {$x1 + $halo}] [expr {$y1 + $halo}]]
	set recs [pgc_collect $area $layer]
	set n [llength $recs]
	# cheap pass: gap from $box to every rectangle, and the rule for that pair
	set cand {}
	set touch {}
	set merged 0
	for {set i 0} {$i < $n} {incr i} {
		foreach {onet okind ox0 oy0 ox1 oy1} [lindex $recs $i] {}
		set ob [list $ox0 $oy0 $ox1 $oy1]
		set g [pgc_gap $box $ob]
		if {$g <= 0.0} {
			# cell metal that this box already overlaps is the G0 class, and
			# tcl/g0_repair.tcl owns it.  See the reader above.
			if {$okind eq "cell"} { continue }
			lappend touch $i
			if {$onet eq $net} { set merged 1 }
			continue
		}
		if {$g > $halo} { continue }
		set r [pgc_req $layer $box $ob]
		if {$r eq ""} { return [list NODECK "" "" "" "" "" $n] }
		if {$g < $r - 1.0e-9} { lappend cand [list $i $g $r] }
	}
	# anything FOREIGN that touches this box is already a merge
	foreach i $touch {
		foreach {onet okind ox0 oy0 ox1 oy1} [lindex $recs $i] {}
		if {$onet eq $net} { continue }
		return [list SHORT 0.0 [pgc_v ${layer}_S_1] $onet $okind [list $ox0 $oy0 $ox1 $oy1] $n]
	}
	if {[llength $cand] == 0} {
		if {$merged} { return [list MERGED 0.0 [pgc_v ${layer}_S_1] $net same-net "" $n] }
		return [list CLEAR "" [pgc_v ${layer}_S_1] "" "" "" $n]
	}
	# union pass: grow the polygon $box belongs to, then drop every candidate
	# that turns out to be part of it
	set inpoly {}
	for {set i 0} {$i < $n} {incr i} { lappend inpoly 0 }
	set frontier [list $box]
	foreach i $touch { lset inpoly $i 1 ; lappend frontier [lrange [lindex $recs $i] 2 5] }
	set grew 1
	while {$grew} {
		set grew 0
		set next {}
		foreach fb $frontier {
			for {set i 0} {$i < $n} {incr i} {
				if {[lindex $inpoly $i]} { continue }
				set ob [lrange [lindex $recs $i] 2 5]
				if {[pgc_gap $fb $ob] > 0.0} { continue }
				lset inpoly $i 1
				lappend next $ob
				set grew 1
			}
		}
		set frontier $next
	}
	set worst CLEAR ; set wgap 1e9 ; set wreq "" ; set wnet "" ; set wkind "" ; set wbox ""
	foreach c $cand {
		foreach {i g r} $c {}
		if {[lindex $inpoly $i]} { continue }
		foreach {onet okind ox0 oy0 ox1 oy1} [lindex $recs $i] {}
		if {$g < $wgap} {
			set worst SPACING ; set wgap $g ; set wreq $r
			set wnet $onet ; set wkind $okind ; set wbox [list $ox0 $oy0 $ox1 $oy1]
		}
	}
	# a foreign net that joined this polygon on the way out is a merge
	for {set i 0} {$i < $n} {incr i} {
		if {![lindex $inpoly $i]} { continue }
		foreach {onet okind ox0 oy0 ox1 oy1} [lindex $recs $i] {}
		if {$onet eq $net} { continue }
		return [list SHORT 0.0 [pgc_v ${layer}_S_1] $onet $okind [list $ox0 $oy0 $ox1 $oy1] $n]
	}
	if {$worst eq "CLEAR"} {
		if {$merged} { return [list MERGED 0.0 [pgc_v ${layer}_S_1] $net same-net "" $n] }
		return [list CLEAR "" [pgc_v ${layer}_S_1] "" "" "" $n]
	}
	return [list $worst $wgap $wreq $wnet $wkind $wbox $n]
}
# 1 only when the probe MEASURED neighbours and none of them is too close.
proc pgc_ok {box layer net {halo 0.6}} {
	set p [pgc_probe $box $layer $net $halo]
	set v [lindex $p 0]
	return [expr {$v eq "CLEAR" || $v eq "MERGED"}]
}
proc pgc_fmt {box} {
	foreach {x0 y0 x1 y1} $box {}
	return [format "(%.3f,%.3f)-(%.3f,%.3f)" $x0 $y0 $x1 $y1]
}
proc pgc_say {tag box layer net p} {
	foreach {v g r onet okind obox n} $p {}
	if {$v eq "CLEAR" || $v eq "MERGED"} {
		return "$tag $layer $net [pgc_fmt $box] $v (rule $r, $n neighbour(s) examined)"
	}
	if {$v eq "NODECK"} {
		return "$tag $layer $net [pgc_fmt $box] NODECK -- no ${layer}_S_1 in the deck, nothing was judged"
	}
	return [format "%s %s %s %s %s gap %.4f < rule %s against %s %s %s (%d neighbour(s) examined)" \
		$tag $layer $net [pgc_fmt $box] $v $g $r $onet $okind [pgc_fmt $obox] $n]
}

################################################################################
# GUARDED PLACEMENT
################################################################################
# add_shape with the check in front of it, and a relocation ladder behind it.
# $alts is a list of alternative rectangles to try in order when the intended
# one is blocked; they must all be electrically equivalent, which only the
# caller can know.
# Counters live in the global array PGC_N, keyed by pass tag, so a pass reports
# placed/moved/declined rather than a single number that cannot be read.
proc pgc_add_shape {tag net layer rect {alts {}} {halo 0.6}} {
	global PGC_N
	foreach k {try place move decline} {
		if {![info exists PGC_N($tag,$k)]} { set PGC_N($tag,$k) 0 }
	}
	incr PGC_N($tag,try)
	set p [pgc_probe $rect $layer $net $halo]
	set v [lindex $p 0]
	if {$v eq "CLEAR" || $v eq "MERGED"} {
		add_shape -net $net -layer $layer -rect $rect -shape STRIPE -status ROUTED
		incr PGC_N($tag,place)
		return 1
	}
	pgc_note [pgc_say "$tag BLOCKED" $rect $layer $net $p]
	set i 0
	foreach a $alts {
		incr i
		set q [pgc_probe $a $layer $net $halo]
		set w [lindex $q 0]
		if {$w eq "CLEAR" || $w eq "MERGED"} {
			add_shape -net $net -layer $layer -rect $a -shape STRIPE -status ROUTED
			incr PGC_N($tag,move)
			pgc_note "$tag RELOCATED to [pgc_fmt $a] (alternative $i of [llength $alts])"
			return 1
		}
		pgc_note [pgc_say "$tag alt$i REFUSED" $a $layer $net $q]
	}
	incr PGC_N($tag,decline)
	pgc_note "$tag DECLINED -- no clear position for $net $layer [pgc_fmt $rect] after [llength $alts] alternative(s)"
	return 0
}
# Report and reset a tag's counters.  A tag that never ran says so, which is not
# the same statement as a tag that placed nothing.
proc pgc_report {tag} {
	global PGC_N
	if {![info exists PGC_N($tag,try)]} {
		logPuts "### UNL STATUS ### : PGCLEAR $tag -- pass did NOT run (no sites offered)"
		return
	}
	logPuts [format "### UNL STATUS ### : PGCLEAR %s -- %d offered, %d placed as intended, %d relocated, %d DECLINED" \
		$tag $PGC_N($tag,try) $PGC_N($tag,place) $PGC_N($tag,move) $PGC_N($tag,decline)]
}
proc pgc_declined {tag} {
	global PGC_N
	if {![info exists PGC_N($tag,decline)]} { return 0 }
	return $PGC_N($tag,decline)
}

################################################################################
# VIA SCRUB
################################################################################
# editPowerVia hands the ENGINE the choice of via master and position, so no
# check in front of it can decide what metal it is about to draw.
# The 2026-08-26 M1.S.1 is exactly that: the engine answered a 0.10 um wide tap
# pad with a TWO CUT array whose M1 pad is 0.33 um wide, and the extra 0.115 um
# on the right hand side is the violation.
# So this pass measures what the engine actually built, which is the only form
# of the question that has an answer.
#
# pgc_via_census records the vias of $net whose cut layer is $cut inside $area.
# pgc_via_scrub takes a before census, looks at every via that appeared since,
# and for each one whose real landing pad is too close to foreign metal deletes
# it and lets the caller decide whether to retry somewhere else.
# $area may be the word ALL, which walks the net's own special via list instead
# of asking dbQuery for every via in the tile.  A whole-design dbQuery here is
# a six figure object walk done twice, and the net list is the same answer.
proc pgc_via_objs {net area} {
	if {$area eq "ALL"} {
		set np [dbGet -p top.nets.name $net -e]
		if {$np eq "" || $np eq "0x0"} { return {} }
		return [dbGet -e $np.sVias]
	}
	if {[catch {set objs [dbQuery -area $area -objType sVia]}]} { return {} }
	return $objs
}
proc pgc_via_census {net cut area} {
	set out {}
	set byname [expr {$area eq "ALL"}]
	foreach o [pgc_via_objs $net $area] {
		if {!$byname && [dbGet -e $o.net.name] ne $net} { continue }
		set vm [dbGet -e $o.via]
		if {$vm eq "" || $vm eq "0x0"} { continue }
		if {[dbGet -e $vm.cutLayer.name] ne $cut} { continue }
		lappend out [format "%.4f_%.4f" [dbGet $o.pt_x] [dbGet $o.pt_y]]
	}
	return $out
}
# The bounding box of everything a special via draws, bloated by a hair.
#
# THIS IS THE DELETE AREA, AND GETTING IT WRONG IS A SILENT NO-OP.  Measured on
# the shipped 2026-08-26 database: `editPowerVia -delete_vias 1 -nets VDD
# -bottom_layer M1 -top_layer M2 -area {433.20 208.25 433.30 208.35}` returns
# quietly and leaves the via in place, because the area does not CONTAIN it.
# The same command over {433.0 208.1 433.5 208.5} removes it.  A two-cut
# via1Array is 0.33 um wide about its own point, so a box built from the point
# alone never contains one.
#
# The flow's own frozen stub-via regenerate at x=433, y=4.3 uses
# {433.15 4.20 433.35 4.40} and is therefore ALSO a no-op; its "1 -> 1" reading
# has always meant "nothing happened", not "regenerated".  It is left alone
# because the cut it produces is DRC clean as it stands, and widening it would
# change a state nobody has measured.
proc pgc_via_extent {o vm {bloat 0.02}} {
	set x0 1e9 ; set y0 1e9 ; set x1 -1e9 ; set y1 -1e9
	foreach side {botRects topRects cutRects} {
		foreach r [pgc_rects [dbGet -e $o.$side]] {
			foreach {ax0 ay0 ax1 ay1} $r {}
			if {$ax0 < $x0} { set x0 $ax0 }
			if {$ay0 < $y0} { set y0 $ay0 }
			if {$ax1 > $x1} { set x1 $ax1 }
			if {$ay1 > $y1} { set y1 $ay1 }
		}
	}
	if {$x1 < $x0} {
		# no rectangles readable: fall back to the point, and say so, because a
		# delete over this box will not work and the caller must see why
		pgc_note "via extent unreadable at [dbGet -e $o.pt_x],[dbGet -e $o.pt_y]; falling back to a point box, which will NOT delete"
		set px [dbGet $o.pt_x] ; set py [dbGet $o.pt_y]
		return [list [expr {$px - 0.3}] [expr {$py - 0.3}] [expr {$px + 0.3}] [expr {$py + 0.3}]]
	}
	return [list [expr {$x0 - $bloat}] [expr {$y0 - $bloat}] [expr {$x1 + $bloat}] [expr {$y1 + $bloat}]]
}
# Look at every via of $net/$cut inside $area that was NOT in the $before
# census, measure its real landing pads, delete the ones that are too close and
# PROVE they went.
# Returns the kill list, each entry {x y bottomLayer topLayer}, so the caller
# can decide whether to try again somewhere else.
# A delete that did not delete is reported loudly rather than counted as a
# repair, because editPowerVia -delete_vias returning quietly on a via it did
# not remove would turn this whole pass into a decoration.
proc pgc_via_scrub {tag net cut area before {halo 0.6}} {
	set kill {}
	foreach o [pgc_via_objs $net $area] {
		if {[dbGet -e $o.net.name] ne $net} { continue }
		set vm [dbGet -e $o.via]
		if {$vm eq "" || $vm eq "0x0"} { continue }
		if {[dbGet -e $vm.cutLayer.name] ne $cut} { continue }
		set px [dbGet $o.pt_x] ; set py [dbGet $o.pt_y]
		set k [format "%.4f_%.4f" $px $py]
		if {[lsearch -exact $before $k] >= 0} { continue }
		set bad ""
		foreach {side lay} [list botRects [dbGet -e $vm.botLayer.name] \
		                         topRects [dbGet -e $vm.topLayer.name]] {
			foreach r [pgc_rects [dbGet -e $o.$side]] {
				set p [pgc_probe $r $lay $net $halo]
				set v [lindex $p 0]
				if {$v eq "CLEAR" || $v eq "MERGED"} { continue }
				set bad [pgc_say "$tag VIA at $px,$py" $r $lay $net $p]
				break
			}
			if {$bad ne ""} { break }
		}
		if {$bad eq ""} { continue }
		pgc_note $bad
		set ext [pgc_via_extent $o $vm]
		lappend kill [list $px $py [dbGet -e $vm.botLayer.name] [dbGet -e $vm.topLayer.name] $ext $k]
	}
	foreach kk $kill {
		foreach {px py bl tl ext k} $kk {}
		editPowerVia -delete_vias 1 -nets $net -bottom_layer $bl -top_layer $tl -area $ext
		if {[lsearch -exact [pgc_via_census $net $cut $ext] $k] >= 0} {
			logPuts "### UNL STATUS ### : PGCLEAR/$tag DELETE FAILED -- the $net $cut at $px,$py survived editPowerVia -delete_vias over [pgc_fmt $ext], so this site WILL reach signoff"
		}
	}
	return $kill
}

# GUARDED POWER VIA.
# Census, generate, measure what the ENGINE actually built, delete what is too
# close, then try to put it back somewhere else inside the same electrical
# footprint.
#
# A check in FRONT of editPowerVia cannot work, and that is the whole reason
# this proc has the shape it has.  The engine picks the via master and the
# position from the metal overlap it finds, and on 2026-08-26 it answered a
# 0.10 um wide tap pad with a TWO CUT array whose M1 landing pad is 0.33 um
# wide; the 0.115 um of pad hanging off the right hand side of the pad it was
# asked for is the M1.S.1.  Nothing the caller knows predicts that.
#
# The retry lever is the WINDOW, not the via.  editPowerVia looks only inside
# -area, so restricting it to the far side of the offending position is the only
# way to make the engine choose a different one.  The retry windows are LOCAL to
# the deleted via, one row tall, so a retry cannot quietly re-via a whole column.
#
# $retry 0 is for the passes where a site is genuinely optional, such as the
# strap-to-grid crossings where a column needs only ONE live crossing.
# Returns {added kept relocated declined}.
proc pgc_epv {tag net bl tl cut area {retry 1} {halo 0.6}} {
	global PGC_N
	foreach k {try place move decline} {
		if {![info exists PGC_N($tag,$k)]} { set PGC_N($tag,$k) 0 }
	}
	set before [pgc_via_census $net $cut $area]
	if {$area eq "ALL"} {
		editPowerVia -add_vias 1 -nets $net -bottom_layer $bl -top_layer $tl -orthogonal_only 0
	} else {
		editPowerVia -add_vias 1 -nets $net -bottom_layer $bl -top_layer $tl \
			-orthogonal_only 0 -area $area
	}
	set mid [pgc_via_census $net $cut $area]
	set added [expr {[llength $mid] - [llength $before]}]
	if {$added < 0} { set added 0 }
	incr PGC_N($tag,try) $added
	set kill [pgc_via_scrub $tag $net $cut $area $before $halo]
	set kept [expr {$added - [llength $kill]}]
	if {$kept < 0} { set kept 0 }
	incr PGC_N($tag,place) $kept
	if {[llength $kill] == 0} { return [list $added $kept 0 0] }
	if {$area eq "ALL"} {
		set ax0 -1e6 ; set ay0 -1e6 ; set ax1 1e6 ; set ay1 1e6
	} else {
		foreach {ax0 ay0 ax1 ay1} $area {}
	}
	set moved 0
	set gone  0
	foreach kk $kill {
		foreach {px py bl2 tl2 ext2 key2} $kk {}
		set done 0
		if {$retry} {
			foreach sub [list [list [expr {$px - 0.5}] [expr {$py + 0.12}] [expr {$px + 0.9}] [expr {$py + 1.0}]] \
			                  [list [expr {$px - 0.5}] [expr {$py - 1.0}] [expr {$px + 0.9}] [expr {$py - 0.12}]]] {
				foreach {sx0 sy0 sx1 sy1} $sub {}
				set sy0 [expr {max($sy0, $ay0)}] ; set sy1 [expr {min($sy1, $ay1)}]
				set sx0 [expr {max($sx0, $ax0)}] ; set sx1 [expr {min($sx1, $ax1)}]
				if {$sx1 - $sx0 <= 0.0 || $sy1 - $sy0 <= 0.0} { continue }
				set sub2 [list $sx0 $sy0 $sx1 $sy1]
				set b2 [pgc_via_census $net $cut $sub2]
				editPowerVia -add_vias 1 -nets $net -bottom_layer $bl -top_layer $tl \
					-orthogonal_only 0 -area $sub2
				set m2 [pgc_via_census $net $cut $sub2]
				set new2 [expr {[llength $m2] - [llength $b2]}]
				if {$new2 <= 0} { continue }
				set k2 [pgc_via_scrub "$tag/retry" $net $cut $sub2 $b2 $halo]
				if {[llength $k2] < $new2} {
					pgc_note "$tag RELOCATED the $net $cut deleted at $px,$py into [pgc_fmt $sub2]"
					incr moved ; incr PGC_N($tag,move) ; set done 1 ; break
				}
			}
		}
		if {!$done} {
			incr gone ; incr PGC_N($tag,decline)
			if {$retry} {
				pgc_note "$tag DECLINED -- the $net $cut at $px,$py had no clear alternative position"
			} else {
				pgc_note "$tag DECLINED -- the $net $cut at $px,$py was too close and this pass does not relocate"
			}
		}
	}
	return [list $added $kept $moved $gone]
}

################################################################################
# ROUTER RESIDUAL
################################################################################
# The OTHER half of this class, and it is not a PG pass at all.
#
# On the 2026-08-26 via-split cut the M2.S.1 at (553.400,176.410) was made by
# NANOROUTE, not by any pass below the post-route verifyGeometry.  The detail
# router ended with "Total number of DRC violations = 4", all on M2, and the
# post-route verifyGeometry named all four:  two vias sitting 0.045 and 0.050 um
# from a PG route BLOCKAGE edge, which is harmless because the blockage stands
# 0.1 um outside the strap it covers, and two pieces of regular routing INSIDE a
# blockage, one of which is 0.05 um from the strap itself.
# deleteAllRouteBlks then removed the blockage and the survivor became M2.S.1.
#
# So the marker was visible ten minutes into the run, in Innovus' own report,
# and it was invisible in practice because it was one line among 808 expected
# "Special Wire of Net VDD & Routing Blockage" entries.
#
# pgc_blockage_residuals separates the two cases the only way that is not a
# guess: it measures each regular rectangle against the real SPECIAL metal with
# the deck rule and keeps the ones that will still be violations once the
# blockages are gone.
proc pgc_blockage_residuals {rptfile} {
	set out {}
	if {[catch {set fh [open $rptfile r]}]} {
		pgc_note "post-route report $rptfile unreadable; the router residual scan did NOT run"
		return "ERROR"
	}
	set pend ""
	set nmark 0
	while {[gets $fh ln] >= 0} {
		if {[regexp {^(SHORT|SPACING): Regular (Via|Wire) of Net ([^&]+) & Routing Blockage\s+\(\s*(\S+)\s*\)} \
		     $ln -> cls kind net lay]} {
			set pend [list $cls $kind [string trim $net] $lay]
			incr nmark
			continue
		}
		if {$pend eq ""} { continue }
		if {[regexp {^Bounds : \(\s*([-0-9.]+),\s*([-0-9.]+)\s*\)\s*\(\s*([-0-9.]+),\s*([-0-9.]+)\s*\)} \
		     $ln -> x0 y0 x1 y1]} {
			lappend out [concat $pend [list $x0 $y0 $x1 $y1]]
		}
		set pend ""
	}
	close $fh
	pgc_note "post-route report: $nmark regular-metal-versus-PG-blockage marker(s), [llength $out] with usable bounds"
	return $out
}
# The fence that has to go up before a net is re-routed away from PG metal.
# It is the offending SPECIAL rectangle, clipped along its long axis to the
# marker plus 4 um so a 336 um strap does not fence a whole column, and grown by
# the deck's own spacing rule.
proc pgc_fence_box {marker special rule} {
	foreach {x0 y0 x1 y1} $marker {}
	foreach {ox0 oy0 ox1 oy1} $special {}
	set pad [expr {$rule + 0.02}]
	if {[expr {$ox1 - $ox0}] >= [expr {$oy1 - $oy0}]} {
		set fx0 [expr {max($ox0, $x0 - 4.0)}] ; set fx1 [expr {min($ox1, $x1 + 4.0)}]
		set fy0 $oy0 ; set fy1 $oy1
	} else {
		set fy0 [expr {max($oy0, $y0 - 4.0)}] ; set fy1 [expr {min($oy1, $y1 + 4.0)}]
		set fx0 $ox0 ; set fx1 $ox1
	}
	return [list [expr {$fx0 - $pad}] [expr {$fy0 - $pad}] [expr {$fx1 + $pad}] [expr {$fy1 + $pad}]]
}
# THE SAME CLASS, READ OUT OF THE SIGNOFF REPORT INSTEAD OF THE POST-ROUTE ONE.
#
# The post-route scan sees this class while the PG route blockages are still up,
# as regular metal inside a blockage.  At signoff the blockages are gone and
# Innovus names it directly:
#   SPACING: Regular Wire of Net core/n_1239 & Special Wire of Net VDD  ( M2 )
# Both orders are accepted, because which side Innovus prints first is not
# something to depend on.
# Returns a list of {net layer fx0 fy0 fx1 fy1}, one per marker, where net is
# the REGULAR side, which is the only side that can still be moved at signoff.
proc pgc_spacing_residuals {rptfile} {
	set out {}
	if {[catch {set fh [open $rptfile r]}]} {
		pgc_note "signoff report $rptfile unreadable; the PG spacing scan did NOT run"
		return "ERROR"
	}
	set pend ""
	set nmark 0
	set pat {^SPACING: (Regular|Special) (?:Wire|Via) of Net (.+) & (Regular|Special) (?:Wire|Via) of Net (.+)\s+\(\s*(\S+)\s*\)}
	while {[gets $fh ln] >= 0} {
		if {[regexp $pat $ln -> k1 n1 k2 n2 lay]} {
			set pend ""
			if {$k1 eq "Regular" && $k2 eq "Special"} { set pend [list [string trim $n1] $lay] }
			if {$k1 eq "Special" && $k2 eq "Regular"} { set pend [list [string trim $n2] $lay] }
			if {$pend ne ""} { incr nmark }
			continue
		}
		if {$pend eq ""} { continue }
		if {[regexp {^Bounds : \(\s*([-0-9.]+),\s*([-0-9.]+)\s*\)\s*\(\s*([-0-9.]+),\s*([-0-9.]+)\s*\)} \
		     $ln -> x0 y0 x1 y1]} {
			foreach {rnet lay} $pend {}
			set b [list $x0 $y0 $x1 $y1]
			set worst "" ; set wg 1e9 ; set wr [pgc_v ${lay}_S_1]
			if {$wr eq ""} { set wr 0.1 }
			foreach sp [pgc_collect [list [expr {$x0-0.6}] [expr {$y0-0.6}] [expr {$x1+0.6}] [expr {$y1+0.6}]] $lay] {
				foreach {onet okind ox0 oy0 ox1 oy1} $sp {}
				if {$okind ne "sWire" && ![string match sVia* $okind]} { continue }
				if {$onet eq $rnet} { continue }
				set ob [list $ox0 $oy0 $ox1 $oy1]
				set g [pgc_gap $b $ob]
				if {$g < $wg} { set wg $g ; set worst $ob }
			}
			if {$worst eq ""} {
				pgc_note "PG spacing marker on $rnet at [pgc_fmt $b] names no special metal within 0.6 um; not fenceable"
			} else {
				set fence [pgc_fence_box $b $worst $wr]
				pgc_note "PG spacing marker on $rnet $lay [pgc_fmt $b], nearest special metal [pgc_fmt $worst]; fence [pgc_fmt $fence]"
				lappend out [concat [list $rnet $lay] $fence]
			}
		}
		set pend ""
	}
	close $fh
	pgc_note "signoff report: $nmark regular-versus-special SPACING marker(s), [llength $out] fenceable"
	return $out
}
# Of those markers, the ones that are REAL once the blockages go, each with the
# FENCE that has to go up before the net is re-routed.
#
# THE FENCE IS THE WHOLE REPAIR, and three rehearsals on the shipped 2026-08-26
# database say so:
#   bare ecoRoute then ecoRoute -fix_drc      site unchanged, 0.050 um
#   rip core/n_1239, ecoRoute, -fix_drc       site unchanged, 0.050 um,
#                                             5 wires out, 5 wires back, same via
#   rip, FENCE the strap on M2 + VIA1, then   site CLEAR, 6 wires back, the M2
#   ecoRoute, -fix_drc, unfence               metal moved to x = 553.85
# NanoRoute does not believe this is a violation.  It will not fix it, it will
# not fix it after being made to route the net again, and the only thing that
# moves it is being told the space is unavailable.  That is exactly the shape
# g0_repair.tcl measured for the router-versus-cell-OBS class, one class over.
#
# The fence is DERIVED: it is the special rectangle that convicted the marker,
# clipped along its long axis to the marker plus 4 um so a 336 um strap does not
# fence a whole column, and grown by the deck's own spacing rule.
# Returns a list of {net x0 y0 x1 y1}.
proc pgc_real_residuals {markers} {
	set out {}
	foreach m $markers {
		foreach {cls kind net lay x0 y0 x1 y1} $m {}
		set b [list $x0 $y0 $x1 $y1]
		set worst ""
		set wg 1e9
		set wr 0
		foreach s [pgc_collect [list [expr {$x0-0.6}] [expr {$y0-0.6}] [expr {$x1+0.6}] [expr {$y1+0.6}]] $lay] {
			foreach {onet okind ox0 oy0 ox1 oy1} $s {}
			if {$okind ne "sWire" && ![string match sVia* $okind]} { continue }
			if {$onet eq $net} { continue }
			set ob [list $ox0 $oy0 $ox1 $oy1]
			set g [pgc_gap $b $ob]
			set r [pgc_req $lay $b $ob]
			if {$r eq ""} { continue }
			if {$g >= $r - 1.0e-9} { continue }
			if {$g < $wg} { set wg $g ; set wr $r ; set worst [list $onet $ob] }
		}
		if {$worst eq ""} {
			pgc_note [format "residual %s %s %s on %s %s is clear of every special wire, it dies with the blockage" \
				$cls $kind $net $lay [pgc_fmt $b]]
			continue
		}
		set fence [pgc_fence_box $b [lindex $worst 1] $wr]
		pgc_note [format "residual %s %s %s on %s %s sits %.4f um from %s %s, rule %s -- REAL once the blockage goes; fence %s" \
			$cls $kind $net $lay [pgc_fmt $b] $wg [lindex $worst 0] [pgc_fmt [lindex $worst 1]] $wr [pgc_fmt $fence]]
		lappend out [concat [list $net $lay] $fence]
	}
	return $out
}
# The distinct net names in a residual list.
proc pgc_residual_nets {res} {
	set out {}
	foreach r $res {
		set n [lindex $r 0]
		if {[lsearch -exact $out $n] < 0} { lappend out $n }
	}
	return $out
}

################################################################################
# SELFTEST
################################################################################
# Fixed rectangles with answers derived by hand, plus the two deck values the
# whole check rests on.
# This is fatal at the caller because a broken derivation would otherwise
# present as "0 sites blocked" forty minutes later, which reads exactly like
# success.
proc pgc_selftest {} {
	set ok 1
	set m1 [pgc_v M1_S_1]
	set m2 [pgc_v M2_S_1]
	if {$m1 ne "0.09"} { pgc_note "SELFTEST: M1_S_1 read as '$m1', expected 0.09" ; set ok 0 }
	if {$m2 ne "0.10"} { pgc_note "SELFTEST: M2_S_1 read as '$m2', expected 0.10" ; set ok 0 }
	# The M1.S.1 site of 2026-08-26, as two rectangles.
	set via  {433.085 208.210 433.415 208.390}
	set sig  {433.455 208.015 433.545 208.145}
	set g [pgc_gap $via $sig]
	if {abs($g - 0.0763) > 0.0005} { pgc_note [format "SELFTEST: corner gap %.4f, Calibre measured 0.076" $g] ; set ok 0 }
	if {[pgc_prun $via $sig] != 0.0} { pgc_note "SELFTEST: two rectangles meeting at a corner must have parallel run 0" ; set ok 0 }
	set r [pgc_req M1 $via $sig]
	if {$r ne "0.09"} { pgc_note "SELFTEST: required M1 spacing derived as '$r', expected 0.09" ; set ok 0 }
	# The M2.S.1 site of 2026-08-26: a 0.30 um strap beside a 0.10 x 0.18 via pad.
	set strap {553.100   4.000 553.400 340.000}
	set pad   {553.450 176.410 553.550 176.590}
	set g2 [pgc_gap $strap $pad]
	if {abs($g2 - 0.05) > 0.0005} { pgc_note [format "SELFTEST: strap gap %.4f, Calibre measured 0.050" $g2] ; set ok 0 }
	set p2 [pgc_prun $strap $pad]
	if {abs($p2 - 0.18) > 0.0005} { pgc_note [format "SELFTEST: strap parallel run %.4f, expected 0.180" $p2] ; set ok 0 }
	# The strap is wider than M2_S_2_W but the run is far shorter than M2_S_2_L,
	# so the wide-metal tier must NOT fire and the answer must stay M2.S.1.
	# Calibre agreed: it named this site M2.S.1 with Min 0.1 and named no other
	# M2 rulecheck on it.
	set r2 [pgc_req M2 $strap $pad]
	if {$r2 ne "0.10"} { pgc_note "SELFTEST: required M2 spacing derived as '$r2', expected 0.10" ; set ok 0 }
	# THE WIDE-METAL TIER MUST FIRE ON A 0.40 um RUN.  The deck defines
	# M2_S_2_L twice, 0.38 and 0.42, and keeping the larger let a real M2.S.2 at
	# (539.795,223.100) through on the 2026-08-26 05:08 cut.
	if {[pgc_v M2_S_2_L] ne "0.38"} { pgc_note "SELFTEST: M2_S_2_L read as '[pgc_v M2_S_2_L]', expected the SMALLER 0.38" ; set ok 0 }
	if {[pgc_v M2_S_2_W] ne "0.20"} { pgc_note "SELFTEST: M2_S_2_W read as '[pgc_v M2_S_2_W]', expected the SMALLER 0.20" ; set ok 0 }
	set wideA {539.500 223.000 539.795 223.600}
	set wideB {539.900 223.100 540.200 223.500}
	set rw [pgc_req M2 $wideA $wideB]
	if {$rw ne "0.12"} { pgc_note "SELFTEST: a 0.30 um line with a 0.40 um run must escalate to M2_S_2 = 0.12, got '$rw'" ; set ok 0 }
	# Touching same-net metal is legal and must read as a zero gap.
	if {[pgc_gap {0 0 1 1} {1 0 2 1}] != 0.0} { pgc_note "SELFTEST: abutting rectangles must gap 0" ; set ok 0 }
	# A gap comfortably past the rule must not be reported.
	if {[pgc_gap {0 0 1 1} {1.5 0 2 1}] < 0.4999} { pgc_note "SELFTEST: 0.5 gap mis-measured" ; set ok 0 }
	if {$ok} { pgc_note "SELFTEST PASSED -- deck values, corner gap, parallel run and both 2026-08-26 sites reproduce" }
	return $ok
}

################################################################################
# CENSUS
################################################################################
# Sweep every special via and special wire of $nets on $layers and report every
# rectangle that is closer than its rule to anything.
# This is the acceptance instrument, not a repair: it is what proves the check
# sees what Calibre sees on a finished database.
# Split a long rectangle into pieces no longer than $maxlen along its long axis.
# A 336 um strap probed whole would ask dbQuery for every object in a 336 um
# window, which is minutes of work for an answer that is a minimum over pieces
# anyway.  A wide-metal tier whose parallel-run threshold straddles a piece
# boundary is the one thing this loses, and every such threshold in the deck is
# under 5 um against a 20 um piece.
proc pgc_chunks {box {maxlen 20.0}} {
	foreach {x0 y0 x1 y1} $box {}
	set dx [expr {$x1 - $x0}] ; set dy [expr {$y1 - $y0}]
	set out {}
	if {$dx >= $dy} {
		if {$dx <= $maxlen} { return [list $box] }
		for {set a $x0} {$a < $x1} {set a [expr {$a + $maxlen}]} {
			lappend out [list $a $y0 [expr {min($a + $maxlen, $x1)}] $y1]
		}
	} else {
		if {$dy <= $maxlen} { return [list $box] }
		for {set a $y0} {$a < $y1} {set a [expr {$a + $maxlen}]} {
			lappend out [list $x0 $a $x1 [expr {min($a + $maxlen, $y1)}]]
		}
	}
	return $out
}
proc pgc_census {nets layers {halo 0.6} {limit 200}} {
	set hits {}
	set nex 0
	foreach net $nets {
		set np [dbGet -p top.nets.name $net -e]
		if {$np eq "" || $np eq "0x0"} { continue }
		foreach o [dbGet -e $np.sWires] {
			set lay [dbGet -e $o.layer.name]
			if {[lsearch -exact $layers $lay] < 0} { continue }
			set b [lindex [dbGet -e $o.box] 0]
			if {[llength $b] != 4} { continue }
			foreach c [pgc_chunks $b] {
				incr nex
				set p [pgc_probe $c $lay $net $halo]
				if {[lindex $p 0] eq "CLEAR" || [lindex $p 0] eq "MERGED"} { continue }
				lappend hits [pgc_say "CENSUS sWire" $c $lay $net $p]
			}
			if {[llength $hits] >= $limit} { break }
		}
		foreach o [dbGet -e $np.sVias] {
			set vm [dbGet -e $o.via]
			if {$vm eq "" || $vm eq "0x0"} { continue }
			foreach {side lay} [list botRects [dbGet -e $vm.botLayer.name] \
			                         topRects [dbGet -e $vm.topLayer.name]] {
				if {[lsearch -exact $layers $lay] < 0} { continue }
				foreach r [pgc_rects [dbGet -e $o.$side]] {
					incr nex
					set p [pgc_probe $r $lay $net $halo]
					if {[lindex $p 0] eq "CLEAR" || [lindex $p 0] eq "MERGED"} { continue }
					lappend hits [pgc_say "CENSUS sVia" $r $lay $net $p]
				}
			}
			if {[llength $hits] >= $limit} { break }
		}
	}
	pgc_note "census examined $nex rectangle(s) on [join $layers ,] for [join $nets ,]; [llength $hits] too close"
	foreach h $hits { pgc_note $h }
	return [llength $hits]
}
