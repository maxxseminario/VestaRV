################################################################################
# PG4 post-route min-AREA patch pass (MCU assembly, foundry-deck classes
# M2.A.1 / M4.A.1 / M4.A.2 and friends).
#
# WHY THIS EXISTS: the router leaves pin-access stubs at the analog-macro
# pin bands (e.g. a 0.1 x 0.18 um M2 stub under a via at an irq_gf pin).
# Innovus' own LEF minArea check WAIVES via-covered stubs, so verifyGeometry
# is 0 and ecoRoute -fix_drc has nothing to fix — only the foundry deck
# (which does not waive) flags them (PG3: M2.A.1 x117 + onesies). The fix is
# ADDITIVE: extend each sliver lengthwise along its own track until its area
# clears the rule, with a clearance check before every extension. Same-net
# metal only — LVS-neutral, timing-neutral (a fraction of a um of side-wall
# cap on an already-routed net).
#
# Driven by COORDINATES from the Calibre results (the marker box for an
# area rule IS the violating shape):
#   cd ~/vestarv/signoff_mp && ./minarea_sites.sh \
#       calibre/MCU_MP_signoff/MCU/results/blockdrc.db > minarea_sites.txt
#   cd ~/vestarv/innovus_mp && innovus -no_gui -batch \
#       -log log/mcu_minarea_patch -files tcl/mcu_minarea_patch.tcl
# then RE-CUT the GDS (this script re-saves the signoff DB and re-streams),
# strmin + drc.sh to prove the class is gone.
#
# Env overrides: SITES (sites file), MCU_DB (signoff DB dir).
################################################################################
if {[info exists env(SITES)]} { set __sites $env(SITES) } else { set __sites /home/mseminario2/vestarv/signoff_mp/minarea_sites.txt }
if {[info exists env(MCU_DB)]} { set __db $env(MCU_DB) } else { set __db dbs/MCU_MP.signoff.innovus.dat }

set restore_db_file_check 0
restoreDesign $__db MCU
catch { setCheckMode -tapeOut false }

# min areas (um^2) from the foundry deck (M2.A.1: 0.052; M4: 0.052)
array set __minarea {M1 0.052 M2 0.052 M3 0.052 M4 0.052 M5 0.052}
set __margin 0.006
# TILE-PASS LESSONS (PG4, exercised to DRC-clean on hart_tile — keep both):
# 1. GRID: extension lengths computed as need/len are OFF the 0.005
#    manufacturing grid (Innovus never checks; foundry G.1 flags every
#    corner). __gridup ceils to grid WITH an fp epsilon — naive floor/ceil
#    shifts already-on-grid coords by one grid step (fp representation)
#    and leaves 0.005 nubs = G.4 steps + M*.W.1 width viols.
# 2. SAME-NET GAP: a patch that lands 0.005-0.099 from OTHER same-net metal
#    creates a SameNetGap notch (min 0.1). Same-net shapes in the halo that
#    do NOT touch the new rect are blockers too. And do NOT bridge/merge
#    into neighbors in 0.1-pitch signal channels: the merged blob enters
#    the wide-metal ParallelRun tier (0.12) against signals at 0.10 —
#    extend LENGTHWISE in the narrow tier instead.
proc __gridup {v} {
	set g [expr {$v * 200.0}]
	if {abs($g - round($g)) < 1e-6} { return [expr {round($g) / 200.0}] }
	return [expr {ceil($g) / 200.0}]
}

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
	# find the net: regular wire at the marker box on this layer
	set __net ""
	foreach __o [dbQuery -area [list $__x0 $__y0 $__x1 $__y1] -objType wire] {
		if {[dbGet -e $__o.layer.name] ne $__lay} { continue }
		set __net [dbGet -e $__o.net.name]
		if {$__net ne ""} { break }
	}
	if {$__net eq ""} {
		# marker may sit on an sWire artifact or a stale site — count + skip
		incr __nskip
		puts "PG4 minarea: NO regular wire under $__lay ($__x0 $__y0 $__x1 $__y1) — skipped"
		continue
	}
	# extend lengthwise along the sliver's long axis; try both directions
	set __done 0
	foreach __dir {plus minus} {
		if {$__w >= $__h} {
			set __ext [__gridup [expr {$__need / $__h - $__w}]]
			if {$__ext <= 0} { set __ext 0.06 }
			if {$__dir eq "plus"} {
				set __rect [list $__x1 $__y0 [expr {$__x1 + $__ext}] $__y1]
				set __chk  [list [expr {$__x1 + 0.005}] [expr {$__y0 - 0.11}] [expr {$__x1 + $__ext + 0.12}] [expr {$__y1 + 0.11}]]
			} else {
				set __rect [list [expr {$__x0 - $__ext}] $__y0 $__x0 $__y1]
				set __chk  [list [expr {$__x0 - $__ext - 0.12}] [expr {$__y0 - 0.11}] [expr {$__x0 - 0.005}] [expr {$__y1 + 0.11}]]
			}
		} else {
			set __ext [__gridup [expr {$__need / $__w - $__h}]]
			if {$__ext <= 0} { set __ext 0.06 }
			if {$__dir eq "plus"} {
				set __rect [list $__x0 $__y1 $__x1 [expr {$__y1 + $__ext}]]
				set __chk  [list [expr {$__x0 - 0.11}] [expr {$__y1 + 0.005}] [expr {$__x1 + 0.11}] [expr {$__y1 + $__ext + 0.12}]]
			} else {
				set __rect [list $__x0 [expr {$__y0 - $__ext}] $__x1 $__y0]
				set __chk  [list [expr {$__x0 - 0.11}] [expr {$__y0 - $__ext - 0.12}] [expr {$__x1 + 0.11}] [expr {$__y0 - 0.005}]]
			}
		}
		# clearance: no OTHER-net shape of the same layer in the check halo
		set __clear 1
		foreach {__rx0 __ry0 __rx1 __ry1} $__rect {}
		foreach __o [concat [dbQuery -area $__chk -objType wire] [dbQuery -area $__chk -objType sWire]] {
			if {[dbGet -e $__o.layer.name] ne $__lay} { continue }
			if {[dbGet -e $__o.net.name] eq $__net} {
				# same net: only a SameNetGap risk if inside the halo but
				# NOT touching the new rect (lesson 2 above)
				set __ob [lindex [dbGet $__o.box] 0]
				foreach {__ox0 __oy0 __ox1 __oy1} $__ob {}
				if {$__ox0 <= $__rx1 && $__ox1 >= $__rx0 && $__oy0 <= $__ry1 && $__oy1 >= $__ry0} { continue }
				set __clear 0; break
			}
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
puts "### UNL STATUS ### : PG4 minarea patch — $__npatch patched, $__nskip skipped(no wire), $__nfail blocked"
if {$__npatch > 0} {
	saveDesign dbs/MCU_MP.signoff.innovus -def -netlist -rc -tcon
	streamOut out/MCU_MP.gds2 \
		-libName WorkLib \
		-structureName MCU \
		-stripes 1 \
		-units 1000 \
		-mode ALL \
		-merge [list out/hart_tile.gds2] \
		-mapFile in/innovus2gds.map
	puts "### UNL STATUS ### : PG4 minarea patch — signoff DB re-saved + GDS re-cut"
	puts "REMINDER: re-apply the .dat/MCU.mode -tapeOut patch check (setCheckMode -tapeOut false was set in-session before save)"
}
exit
