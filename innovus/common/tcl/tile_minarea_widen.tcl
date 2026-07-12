################################################################################
# PG4 tile min-area patch, pass 2: WIDEN the slivers the lengthwise pass
# could not extend (other-net metal within the halo at BOTH ends — dense
# fabric). Perpendicular extension: a 0.48x0.10 sliver +0.06 width unions
# to 0.077 um^2 > 0.052. The added rect alone is sub-min-width but DRC
# checks the UNION with the sliver it abuts. Clearance halo on the widened
# side only. Runs on the ALREADY-PATCHED signoff DB (pass 1 re-saved it)
# and re-saves + re-cuts.
# Env: SITES (blocked-sites file), TILE_DB.
################################################################################
if {[info exists env(SITES)]} { set __sites $env(SITES) } else { set __sites tile_minarea_blocked.txt }
if {[info exists env(TILE_DB)]} { set __db $env(TILE_DB) } else { set __db dbs/hart_tile.signoff.innovus.dat }

restoreDesign $__db hart_tile

array set __minarea {M1 0.052 M2 0.052 M3 0.052 M4 0.052 M5 0.052 M6 0.052}
set __margin 0.006

set __fp [open $__sites r]
set __npatch 0
set __nfail 0
while {[gets $__fp __line] >= 0} {
	if {[llength $__line] != 5} { continue }
	foreach {__lay __x0 __y0 __x1 __y1} $__line {}
	set __w [expr {$__x1 - $__x0}]
	set __h [expr {$__y1 - $__y0}]
	set __need [expr {$__minarea($__lay) + $__margin}]
	set __net ""
	foreach __o [concat [dbQuery -area [list $__x0 $__y0 $__x1 $__y1] -objType wire] \
	                    [dbQuery -area [list $__x0 $__y0 $__x1 $__y1] -objType sWire]] {
		if {[dbGet -e $__o.layer.name] ne $__lay} { continue }
		set __net [dbGet -e $__o.net.name]
		if {$__net ne ""} { break }
	}
	if {$__net eq ""} { incr __nfail; puts "PG4 widen: NO wire at $__line"; continue }
	set __done 0
	foreach __dir {plus minus} {
		if {$__w >= $__h} {
			# horizontal sliver: widen in y
			set __ext [expr {$__need / $__w - $__h}]
			if {$__ext <= 0} { set __ext 0.06 }
			if {$__dir eq "plus"} {
				set __rect [list $__x0 $__y1 $__x1 [expr {$__y1 + $__ext}]]
				set __chk  [list [expr {$__x0 - 0.11}] [expr {$__y1 + 0.005}] [expr {$__x1 + 0.11}] [expr {$__y1 + $__ext + 0.11}]]
			} else {
				set __rect [list $__x0 [expr {$__y0 - $__ext}] $__x1 $__y0]
				set __chk  [list [expr {$__x0 - 0.11}] [expr {$__y0 - $__ext - 0.11}] [expr {$__x1 + 0.11}] [expr {$__y0 - 0.005}]]
			}
		} else {
			# vertical sliver: widen in x
			set __ext [expr {$__need / $__h - $__w}]
			if {$__ext <= 0} { set __ext 0.06 }
			if {$__dir eq "plus"} {
				set __rect [list $__x1 $__y0 [expr {$__x1 + $__ext}] $__y1]
				set __chk  [list [expr {$__x1 + 0.005}] [expr {$__y0 - 0.11}] [expr {$__x1 + $__ext + 0.11}] [expr {$__y1 + 0.11}]]
			} else {
				set __rect [list [expr {$__x0 - $__ext}] $__y0 $__x0 $__y1]
				set __chk  [list [expr {$__x0 - $__ext - 0.11}] [expr {$__y0 - 0.11}] [expr {$__x0 - 0.005}] [expr {$__y1 + 0.11}]]
			}
		}
		set __clear 1
		foreach __o [concat [dbQuery -area $__chk -objType wire] [dbQuery -area $__chk -objType sWire]] {
			if {[dbGet -e $__o.layer.name] ne $__lay} { continue }
			if {[dbGet -e $__o.net.name] eq $__net} { continue }
			set __clear 0; break
		}
		if {!$__clear} { continue }
		add_shape -net $__net -layer $__lay -rect $__rect -shape STRIPE -status ROUTED
		incr __npatch
		set __done 1
		break
	}
	if {!$__done} { incr __nfail; puts "PG4 widen: BLOCKED all directions at $__line net=$__net" }
}
close $__fp
puts "### UNL STATUS ### : PG4 tile minarea widen — $__npatch patched, $__nfail blocked"
if {$__npatch > 0} {
	saveDesign dbs/hart_tile.signoff.innovus -def -netlist -rc -tcon
	streamOut \
	    out/hart_tile.gds2 \
	    -libName WorkLib \
	    -structureName hart_tile \
	    -stripes 1 \
	    -units 1000 \
	    -mode ALL \
	    -mapFile in/innovus2gds.map
	puts "### UNL STATUS ### : PG4 tile minarea widen — signoff DB re-saved + GDS re-cut"
}
exit
