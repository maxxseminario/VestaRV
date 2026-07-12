################################################################################
# PG4 post-route min-AREA patch pass — TILE variant of mcu_minarea_patch.tcl.
#
# WHY: the PG4 final dangling-stack scrub deletes floating via3-6 stacks;
# wherever a small sroute jog/pad of a KEPT (connected) stack had cleared
# min-area only through a deleted neighbor's pad metal, a sub-min sliver
# remains: v20 tile blockdrc = M3.A.1 x24 + M4.A.1 x17 + M5.A.1 x2 (=43,
# matching the Innovus uncapped AREA count exactly). All 43 are SPECIAL
# wires of net VSS attached to live stacks — the fix is ADDITIVE lengthwise
# extension (same-net metal on an already-connected net: LVS-neutral,
# timing-neutral), with an other-net clearance halo before every extension.
#
# Differences vs the MCU script: net lookup accepts sWIRE hits (the MCU
# sites are router pin-stubs = regular wires; the tile sites are sroute
# fabric = special wires), and the re-cut streams the TILE GDS.
#
# Usage (coordinates from the foundry results, marker box = the sliver):
#   cd ~/vestarv/signoff_mp && ./minarea_sites.sh \
#       calibre/hart_tile_mp/hart_tile/results/blockdrc.db > tile_minarea_sites.txt
#   cd ~/vestarv/innovus/common && SITES=... innovus -no_gui -batch \
#       -log log/tile_minarea_patch -files tcl/tile_minarea_patch.tcl
# then strmin + drc.sh to prove the class is gone.
# Env overrides: SITES (sites file), TILE_DB (signoff DB dir).
################################################################################
if {[info exists env(SITES)]} { set __sites $env(SITES) } else { set __sites /home/mseminario2/vestarv/signoff_mp/tile_minarea_sites.txt }
if {[info exists env(TILE_DB)]} { set __db $env(TILE_DB) } else { set __db dbs/hart_tile.signoff.innovus.dat }

restoreDesign $__db hart_tile

array set __minarea {M1 0.052 M2 0.052 M3 0.052 M4 0.052 M5 0.052 M6 0.052}
set __margin 0.006

set __fp [open $__sites r]
set __npatch 0
set __nskip 0
set __nfail 0
while {[gets $__fp __line] >= 0} {
	if {[llength $__line] != 5} { continue }
	foreach {__lay __x0 __y0 __x1 __y1} $__line {}
	set __w [expr {$__x1 - $__x0}]
	set __h [expr {$__y1 - $__y0}]
	set __need [expr {$__minarea($__lay) + $__margin}]
	# find the net: regular OR special wire at the marker box on this layer
	set __net ""
	foreach __o [concat [dbQuery -area [list $__x0 $__y0 $__x1 $__y1] -objType wire] \
	                    [dbQuery -area [list $__x0 $__y0 $__x1 $__y1] -objType sWire]] {
		if {[dbGet -e $__o.layer.name] ne $__lay} { continue }
		set __net [dbGet -e $__o.net.name]
		if {$__net ne ""} { break }
	}
	if {$__net eq ""} {
		incr __nskip
		puts "PG4 minarea: NO wire under $__lay ($__x0 $__y0 $__x1 $__y1) — skipped"
		continue
	}
	set __done 0
	foreach __dir {plus minus} {
		if {$__w >= $__h} {
			set __ext [expr {$__need / $__h - $__w}]
			if {$__ext <= 0} { set __ext 0.06 }
			if {$__dir eq "plus"} {
				set __rect [list $__x1 $__y0 [expr {$__x1 + $__ext}] $__y1]
				set __chk  [list [expr {$__x1 + 0.005}] [expr {$__y0 - 0.11}] [expr {$__x1 + $__ext + 0.12}] [expr {$__y1 + 0.11}]]
			} else {
				set __rect [list [expr {$__x0 - $__ext}] $__y0 $__x0 $__y1]
				set __chk  [list [expr {$__x0 - $__ext - 0.12}] [expr {$__y0 - 0.11}] [expr {$__x0 - 0.005}] [expr {$__y1 + 0.11}]]
			}
		} else {
			set __ext [expr {$__need / $__w - $__h}]
			if {$__ext <= 0} { set __ext 0.06 }
			if {$__dir eq "plus"} {
				set __rect [list $__x0 $__y1 $__x1 [expr {$__y1 + $__ext}]]
				set __chk  [list [expr {$__x0 - 0.11}] [expr {$__y1 + 0.005}] [expr {$__x1 + 0.11}] [expr {$__y1 + $__ext + 0.12}]]
			} else {
				set __rect [list $__x0 [expr {$__y0 - $__ext}] $__x1 $__y0]
				set __chk  [list [expr {$__x0 - 0.11}] [expr {$__y0 - $__ext - 0.12}] [expr {$__x1 + 0.11}] [expr {$__y0 - 0.005}]]
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
	if {!$__done} {
		incr __nfail
		puts "PG4 minarea: BLOCKED both directions at $__lay ($__x0 $__y0 $__x1 $__y1) net=$__net — patch by hand"
	}
}
close $__fp
puts "### UNL STATUS ### : PG4 tile minarea patch — $__npatch patched, $__nskip skipped(no wire), $__nfail blocked"
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
	puts "### UNL STATUS ### : PG4 tile minarea patch — signoff DB re-saved + GDS re-cut"
}
exit
