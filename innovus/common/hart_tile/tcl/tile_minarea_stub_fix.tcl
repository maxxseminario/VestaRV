################################################################################
# PG4 tile min-area pass 3: the 4 sites blocked in BOTH patch passes.
# Forensics (v20 dump): these slivers sit in signal-routing channels (the
# patch halos hit REGULAR wires) and are rail->via1/2->M3(/M4) stubs whose
# upward continuation was removed by the dangling-stack scrub — dead metal.
# Action per site:
#   - classify vias centered on the sliver: below-layer AND above-layer
#     present -> THROUGH-LINK: retry extension with the min-legal 0.101
#     halo; if still blocked, report for waiver.
#   - one side only (or none) -> DEAD STUB: delete the sliver pieces + the
#     in-box vias, then a LOCAL floating-stub sweep (site box +0.35, layers
#     M1-M6, non-followpin, both dims <= 0.5, touching no remaining same-net
#     sVia) so the via1/M2 tail cannot become a new min-area/dangle class.
# Then uncapped verifyGeometry AREA recount in-session, save + re-cut.
# Env: SITES (blocked-sites file), TILE_DB.
################################################################################
if {[info exists env(SITES)]} { set __sites $env(SITES) } else { set __sites tile_minarea_blocked4.txt }
if {[info exists env(TILE_DB)]} { set __db $env(TILE_DB) } else { set __db dbs/hart_tile.signoff.innovus.dat }

restoreDesign $__db hart_tile

array set __below {M3 via2 M4 via3 M5 via4}
array set __above {M3 via3 M4 via4 M5 via5}
array set __minarea {M1 0.052 M2 0.052 M3 0.052 M4 0.052 M5 0.052 M6 0.052}

set __fp [open $__sites r]
set __ndel 0
set __next 0
set __nwaive 0
while {[gets $__fp __line] >= 0} {
	if {[llength $__line] != 5} { continue }
	foreach {__lay __x0 __y0 __x1 __y1} $__line {}
	set __bx [list [expr {$__x0 - 0.05}] [expr {$__y0 - 0.05}] [expr {$__x1 + 0.05}] [expr {$__y1 + 0.05}]]
	# ---- forensics: what lives here ----
	puts "PG4 stubfix SITE: $__lay ($__x0 $__y0 $__x1 $__y1)"
	set __invias {}
	foreach __o [dbQuery -area $__bx -objType sVia] {
		set __vn [dbGet -e $__o.via.name]
		puts "  via: $__vn @([dbGet $__o.pt_x],[dbGet $__o.pt_y]) net=[dbGet -e $__o.net.name]"
		lappend __invias [list $__o $__vn]
	}
	set __hasbelow 0; set __hasabove 0
	foreach __e $__invias {
		set __vn [string tolower [lindex $__e 1]]
		if {[string match "$__below($__lay)*" $__vn]} { set __hasbelow 1 }
		if {[string match "$__above($__lay)*" $__vn]} { set __hasabove 1 }
	}
	if {$__hasbelow && $__hasabove} {
		# THROUGH-LINK: min-halo extension attempt (0.101 = min spacing + eps)
		puts "  -> through-link; trying 0.101-halo extension"
		set __w [expr {$__x1 - $__x0}]; set __h [expr {$__y1 - $__y0}]
		set __need [expr {$__minarea($__lay) + 0.006}]
		set __net VSS
		set __done 0
		foreach __dir {plus minus wplus wminus} {
			if {$__w >= $__h} {
				set __ext [expr {$__need / $__h - $__w}]
				if {$__ext <= 0} { set __ext 0.06 }
				switch $__dir {
					plus   { set __rect [list $__x1 $__y0 [expr {$__x1 + $__ext}] $__y1] }
					minus  { set __rect [list [expr {$__x0 - $__ext}] $__y0 $__x0 $__y1] }
					wplus  { set __rect [list $__x0 $__y1 $__x1 [expr {$__y1 + 0.06}]] }
					wminus { set __rect [list $__x0 [expr {$__y0 - 0.06}] $__x1 $__y0] }
				}
			} else {
				set __ext [expr {$__need / $__w - $__h}]
				if {$__ext <= 0} { set __ext 0.06 }
				switch $__dir {
					plus   { set __rect [list $__x0 $__y1 $__x1 [expr {$__y1 + $__ext}]] }
					minus  { set __rect [list $__x0 [expr {$__y0 - $__ext}] $__x1 $__y0] }
					wplus  { set __rect [list $__x1 $__y0 [expr {$__x1 + 0.06}] $__y1] }
					wminus { set __rect [list [expr {$__x0 - 0.06}] $__y0 $__x0 $__y1] }
				}
			}
			foreach {__rx0 __ry0 __rx1 __ry1} $__rect {}
			set __chk [list [expr {$__rx0 - 0.101}] [expr {$__ry0 - 0.101}] [expr {$__rx1 + 0.101}] [expr {$__ry1 + 0.101}]]
			set __clear 1
			foreach __o [concat [dbQuery -area $__chk -objType wire] [dbQuery -area $__chk -objType sWire]] {
				if {[dbGet -e $__o.layer.name] ne $__lay} { continue }
				if {[dbGet -e $__o.net.name] eq $__net} { continue }
				set __clear 0; break
			}
			if {!$__clear} { continue }
			add_shape -net $__net -layer $__lay -rect $__rect -shape STRIPE -status ROUTED
			incr __next; set __done 1
			puts "  -> extended $__dir"
			break
		}
		if {!$__done} { incr __nwaive; puts "  -> WAIVER CANDIDATE (through-link, unpatchable)" }
		continue
	}
	# DEAD STUB: delete sliver pieces + in-box vias
	puts "  -> dead stub; deleting"
	foreach __o [dbQuery -area $__bx -objType sWire] {
		if {[dbGet -e $__o.layer.name] ne $__lay} { continue }
		if {[dbGet -e $__o.net.name] ne "VSS"} { continue }
		set __ob [lindex [dbGet $__o.box] 0]
		foreach {__ox0 __oy0 __ox1 __oy1} $__ob {}
		if {$__ox0 >= [lindex $__bx 0] && $__oy0 >= [lindex $__bx 1] \
			&& $__ox1 <= [lindex $__bx 2] && $__oy1 <= [lindex $__bx 3]} {
			puts "  del wire: $__lay ($__ob)"
			dbDeleteObj $__o; incr __ndel
		}
	}
	foreach __e $__invias { dbDeleteObj [lindex $__e 0]; incr __ndel }
	# LOCAL cleanup sweep around the site
	set __cx [list [expr {$__x0 - 0.35}] [expr {$__y0 - 0.35}] [expr {$__x1 + 0.35}] [expr {$__y1 + 0.35}]]
	set __again 1
	while {$__again} {
		set __again 0
		foreach __o [dbQuery -area $__cx -objType sWire] {
			set __l [dbGet -e $__o.layer.name]
			if {[lsearch {M1 M2 M3 M4 M5 M6} $__l] < 0} { continue }
			if {[dbGet -e $__o.net.name] ne "VSS"} { continue }
			if {[dbGet -e $__o.shape] eq "FOLLOWPIN" || [dbGet -e $__o.shape] eq "followpin"} { continue }
			set __ob [lindex [dbGet $__o.box] 0]
			foreach {__ox0 __oy0 __ox1 __oy1} $__ob {}
			if {[expr {$__ox1 - $__ox0}] > 0.5 || [expr {$__oy1 - $__oy0}] > 0.5} { continue }
			set __alive 0
			foreach __q [dbQuery -area $__ob -objType sVia] {
				if {[dbGet -e $__q.net.name] eq "VSS"} { set __alive 1; break }
			}
			if {!$__alive} {
				puts "  del cleanup: $__l ($__ob)"
				dbDeleteObj $__o; incr __ndel
				set __again 1
			}
		}
	}
}
close $__fp
puts "### UNL STATUS ### : PG4 stubfix — $__ndel objects deleted, $__next extended, $__nwaive waiver candidates"

verifyGeometry -antenna -error 100000 -warning 100000 \
    -report rpt/hart_tile.verifyGeometry.stubfix.rpt

saveDesign dbs/hart_tile.signoff.innovus -def -netlist -rc -tcon
streamOut \
    out/hart_tile.gds2 \
    -libName WorkLib \
    -structureName hart_tile \
    -stripes 1 \
    -units 1000 \
    -mode ALL \
    -mapFile ../shared/innovus2gds.map
puts "### UNL STATUS ### : PG4 stubfix — signoff DB re-saved + GDS re-cut"
exit
