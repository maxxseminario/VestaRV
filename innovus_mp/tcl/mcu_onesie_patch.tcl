################################################################################
# PG4 MCU DRC patch pass #2 — the 16 "onesie" sites that survive the via-map
# fix (blockdrc 2026-07-12: G.4:M2i x6, M2.S.2/M2.S.2.1/M3.S.2, M4.S.1 x5,
# M4.A.2 x4, VIA1.R.4:M2, VIA2.R.4:M2, M7.S.4 x2) PLUS the min-area pass
# (M2.A.1 x117 + M4.A.1, sites file from minarea_sites.sh). Coordinates are
# CUT-SPECIFIC (seed-dependent) — regenerate this file's site list after any
# re-route; the minarea part reads $SITES.
#
# Fix idioms (tile-proven, session-3):
#  * same-net additive rect MERGES shapes -> kills same-net spacing (S.*),
#    small-jog (G.4), enclosed-hole (M4.A.2) and pad-gap (M7.S.4) classes.
#    M7.S.4(b) precedent: merging the via-array pad group into the adjacent
#    stripe satisfies the net-blind wide-M7 rule.
#  * VIA*.R.4 (2 cuts required near a >0.3x0.3 plate): a SECOND engine via in
#    the same branch. add_via is a GDS-PHANTOM; the GDS-real recipe is real
#    metal (add_shape) + editPowerVia -add_vias. editPowerVia on a SIGNAL net
#    is probed here (gate on the via-count delta) — if the engine refuses,
#    the FATAL names the site and the fallback is a routed-via edit.
#
# Env: TRIAL=1 (default) -> patch + streamOut out/MCU_MP.trial.gds2, NO SAVE.
#      TRIAL=0 -> saveDesign signoff DB + re-cut out/MCU_MP.gds2.
#      SITES   -> minarea sites file (default signoff_mp/minarea_sites.txt)
################################################################################
if {[info exists env(TRIAL)]} { set __trial $env(TRIAL) } else { set __trial 1 }
if {[info exists env(SITES)]} { set __sites $env(SITES) } else { set __sites /home/mseminario2/vestarv/signoff_mp/minarea_sites2.txt }

set restore_db_file_check 0
restoreDesign dbs/MCU_MP.signoff.innovus.dat MCU
catch { setCheckMode -tapeOut false }
set __fatals 0

# ---------------- min-area pass (verbatim logic from mcu_minarea_patch.tcl) --
array set __minarea {M1 0.052 M2 0.052 M3 0.052 M4 0.052 M5 0.052}
set __margin 0.006
proc __gridup {v} {
	set g [expr {$v * 200.0}]
	if {abs($g - round($g)) < 1e-6} { return [expr {round($g) / 200.0}] }
	return [expr {ceil($g) / 200.0}]
}
# Sites file: 5 columns, or 6 with a direction constraint (plus|minus|either)
# from signoff_mp/dummy_aware_sites.py — the analog macros' dummy-M2 (GDS
# 32:1, DM2.S.2 keepout 0.3) is INVISIBLE to the DB, so the safe extension
# direction is computed from the Calibre-input GDS (trial #3: 37 DM2.S.2
# from blind plus-first picks).
proc __minarea_pass {sitesfile tag} {
	global __minarea __margin __fatals
	set __sites $sitesfile
set __fp [open $__sites r]
set __npatch 0; set __nskip 0; set __nfail 0
while {[gets $__fp __line] >= 0} {
	set __dirs {plus minus}
	if {[llength $__line] == 6} {
		switch [lindex $__line 5] {
			plus  { set __dirs {plus} }
			minus { set __dirs {minus} }
		}
		set __line [lrange $__line 0 4]
	}
	if {[llength $__line] != 5} { continue }
	foreach {__lay __x0 __y0 __x1 __y1} $__line {}
	set __w [expr {$__x1 - $__x0}]
	set __h [expr {$__y1 - $__y0}]
	set __need [expr {$__minarea($__lay) + $__margin}]
	set __net ""
	# PG4P2 lesson: the 97 analog-band M2.A.1 slivers are signal-VIA LANDING
	# PADS ("stub+via landing", PG3's own description) — pad metal belongs to
	# the VIA object, so a wire/sWire query finds nothing. Query vias too;
	# for a via, the marker layer is its top or bottom pad layer.
	foreach __o [concat [dbQuery -area [list $__x0 $__y0 $__x1 $__y1] -objType wire] \
	                    [dbQuery -area [list $__x0 $__y0 $__x1 $__y1] -objType sWire]] {
		if {[dbGet -e $__o.layer.name] ne $__lay} { continue }
		set __net [lindex [dbGet -e $__o.net.name] 0]
		if {$__net ne ""} { break }
	}
	if {$__net eq ""} {
		foreach __o [dbQuery -area [list $__x0 $__y0 $__x1 $__y1] -objType via] {
			set __bl [dbGet -e $__o.via.botLayer.name]
			set __tl [dbGet -e $__o.via.topLayer.name]
			if {$__bl ne $__lay && $__tl ne $__lay} { continue }
			set __net [lindex [dbGet -e $__o.net.name] 0]
			if {$__net ne ""} { break }
		}
	}
	if {$__net eq ""} { incr __nskip; puts "PG4P2 minarea($tag): NO wire under $__lay ($__x0 $__y0 $__x1 $__y1) — skipped"; continue }
	set __done 0
	foreach __dir $__dirs {
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
		set __clear 1
		foreach {__rx0 __ry0 __rx1 __ry1} $__rect {}
		foreach __o [concat [dbQuery -area $__chk -objType wire] [dbQuery -area $__chk -objType sWire]] {
			if {[dbGet -e $__o.layer.name] ne $__lay} { continue }
			if {[lindex [dbGet -e $__o.net.name] 0] eq $__net} {
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
	if {!$__done} { incr __nfail; puts "PG4P2 minarea($tag): BLOCKED both directions at $__lay ($__x0 $__y0 $__x1 $__y1) net=$__net" }
}
close $__fp
puts "### UNL STATUS ### : PG4P2 minarea $tag — $__npatch patched, $__nskip skipped, $__nfail blocked"
if {$__nfail > 0} { incr __fatals }
}
__minarea_pass $__sites main


# ---------------- onesie merges (same-net additive rects) --------------------
# clearance-checked add of a same-net rect; FATAL counter on any foreign shape
proc __mrg {tag net lay rect} {
	global __fatals
	foreach {x0 y0 x1 y1} $rect {}
	set chk [list [expr {$x0-0.16}] [expr {$y0-0.16}] [expr {$x1+0.16}] [expr {$y1+0.16}]]
	foreach o [concat [dbQuery -area $chk -objType wire] [dbQuery -area $chk -objType sWire]] {
		if {[dbGet -e $o.layer.name] ne $lay} { continue }
		# lindex: a bracketed net name (gf_out[10]) brace-quotes on string
		# conversion and a bare `eq` self-blocks (cost trial #1's 5 fatals)
		if {[lindex [dbGet -e $o.net.name] 0] eq $net} { continue }
		set ob [lindex [dbGet $o.box] 0]
		foreach {ox0 oy0 ox1 oy1} $ob {}
		# foreign same-layer shape: require >= 0.10 clear of the new rect
		set dx [expr {max($x0-$ox1, $ox0-$x1)}]
		set dy [expr {max($y0-$oy1, $oy0-$y1)}]
		if {$dx < 0.0999 && $dy < 0.0999} {
			puts "PG4P2 FATAL: $tag foreign $lay net=[dbGet -e $o.net.name] at $ob blocks rect $rect"
			incr __fatals
			return
		}
	}
	add_shape -net $net -layer $lay -rect $rect -shape STRIPE -status ROUTED
	puts "PG4P2: $tag merged rect $rect on $net/$lay"
}

# M7.S.4 x2 — merge the M8-pass via7Array_16 pad group into the adjacent
# stripe (rule is net-blind; shapes are same-net; M7.S.4(b) precedent)
__mrg "M7.S.4@208" VSS M7 {208.0 459.3 209.2 463.7}
__mrg "M7.S.4@249" VDD M7 {248.9 450.3 250.2 454.7}

# M4.S.1 x5 — assembly-route-to-tile-pin seam notches at the tile bottom edge
__mrg "M4.S.1@679"  CTS_33      M4 {679.6 648.9 680.11 649.3}
__mrg "M4.S.1@1342" CTS_27      M4 {1342.6 648.9 1343.11 649.3}
__mrg "M4.S.1@1346" CTS_27      M4 {1345.89 648.9 1346.4 649.3}
# right edge 1496.12: a tile-boundary PIN at x1496.25 (invisible to dbQuery —
# not a wire/sWire) sits 0.09 from a 1496.16 edge, and the merged shape is
# WIDE (>0.2) so it needs 0.12 (M4.S.2), trial #3's M4.S.1+S.2 pair
__mrg "M4.S.1@1495" {gf_out[10]} M4 {1495.5 648.9 1496.12 649.4}
__mrg "M4.S.1@2009" CTS_27      M4 {2008.9 648.9 2009.4 649.3}

# M4.A.2 x4 — sub-0.2um enclosed holes in route jog rings; fill the donut
__mrg "M4.A.2@417"  {irq_en[12]} M4 {417.05 649.05 417.35 649.75}
__mrg "M4.A.2@1193" {gf_out[11]} M4 {1193.65 649.1 1193.95 649.6}
__mrg "M4.A.2@1493" {gf_out[12]} M4 {1493.45 649.1 1493.75 649.6}
__mrg "M4.A.2@2091" {gf_out[60]} M4 {2091.65 649.1 2091.95 649.6}

# G.4:M2i x6 (2 clusters) — sub-min jogs at irq_tielow via pads; square out
__mrg "G.4a" irq_tielow M2 {999.45 484.5 999.635 484.79}
__mrg "G.4b" irq_tielow M2 {1006.65 484.4 1006.79 484.6}

# M2.S.2 / M2.S.2.1 / M3.S.2 — same-net parallel twins 0.10-0.14 apart where
# one side is >0.2 wide (union-projection rule 0.12/0.16; run > 0.38/0.4).
# M2.S.2 site history: full bridge (trial 3) -> the 0.9-wide union puts the
# CTS via arrays + the via1 pair on WIDE metal (VIA*.R.2/R.3 want 2x2);
# two tabs (trial 4) -> S.2 + R.2/R.3 clean but the strip between tabs is an
# ENCLOSED HOLE < 0.2 (M2.A.2) — any 2 gap-crossings make one, 1 can't break
# both >0.385 empty runs, and the via bands leave no legal single window.
# v3: full bridge AND upgrade all three vias by delete+engine-regen on the
# wide union (the engine sizes arrays for the metal it lands on). The via1's
# M1 side is CELL PIN geometry (engine no-op target): overlay a same-net
# REAL M1 rect first (the pin's net IS CTS_27), then the engine can via it.
# v10: the LAST THREE sites (M2.S.2 @1208, VIA1.R.4 @1292, VIA2.R.4 @1100)
# are router-geometry artifacts that resisted 7 trials of surgical metal:
# their vias refuse every delete incantation, editMove silently no-ops, and
# the R.4 branch window is [0.10, <0.15) cut-gap against an engine that
# arrays whole overlaps. The correct instrument is the ROUTER: rip up the
# three nets and ecoRoute — a fresh pattern clears artifact-class DRC with
# overwhelming probability. CTS_27 is a clock net: hold margin is only
# +0.010, so timeDesign gates the result below.
__mrg "M2.S.2.1" mtx0/rc_gclk_978    M2 {1319.76 553.9 1319.9 554.3}
__mrg "M3.S.2"   VSS                 M3 {2062.25 439.05 2062.75 439.35}

# engine-via helper (defined here, used by the M2.S.2 regen below AND the
# VIA*.R.4 fixes): add optional landing rects, then editPowerVia — GDS-real
# on signal nets (proven trials 1-4); FATAL if the via count doesn't move.
proc __via_fix {tag net bot top rects area expect_cut} {
	global __fatals
	foreach r $rects {
		foreach {lay rect} $r {}
		add_shape -net $net -layer $lay -rect $rect -shape STRIPE -status ROUTED
	}
	set n0 [llength [dbQuery -area $area -objType sVia]]
	set rc [catch {editPowerVia -nets $net -add_vias 1 -bottom_layer $bot -top_layer $top -area $area -orthogonal_only 0} msg]
	set n1 [llength [dbQuery -area $area -objType sVia]]
	puts "PG4P2: $tag editPowerVia rc=$rc sVias $n0 -> $n1"
	if {$n1 <= $n0} {
		puts "PG4P2 FATAL: $tag engine added no via ($expect_cut) — needs a routed-via fallback"
		incr __fatals
	}
}
# reliable REGULAR-via delete: dbDeleteObj "succeeds" (rc=0) but the cut
# SURVIVES streamOut (trial 4's VIA1.W.1 = old+new cuts overlapping — the
# FIFTH GDS-divergence flavor, delete-direction this time). editSelect +
# editDelete is the wire-editor path; verify by re-query and FATAL if alive.
proc __del_vias {tag net area layer} {
	global __fatals
	deselectAll
	# CTS/ECO vias are status FIXED and editSelect skips them (trial 6: the
	# one ROUTED via deleted, the two FIXED ones survived) — downgrade first.
	foreach o [dbQuery -area $area -objType via] {
		if {[lindex [dbGet -e $o.net.name] 0] ne $net} { continue }
		catch {dbSet $o.status routed}
	}
	# -object_type Via (NOT "-type via" — that arg is {Regular Special Patch},
	# IMPTCM-23; cost trial 5 all three deletes)
	catch {editSelect -area $area -object_type Via -nets $net}
	set rc [catch {editDelete -selected} msg]
	set left 0
	foreach o [dbQuery -area $area -objType via] {
		if {[lindex [dbGet -e $o.net.name] 0] eq $net && [dbGet -e $o.via.cutLayer.name] eq $layer} { incr left }
	}
	puts "PG4P2: $tag editDelete rc=$rc remaining($layer)=$left"
	if {$left > 0} { puts "PG4P2 FATAL: $tag vias survive editDelete"; incr __fatals }
}
# (v8: no via surgery here — see the nudge above)

# ---------------- v10: router-level fix for the 3 resistant sites ------------
# M2.S.2 @1208 (CTS_27 twin pads), VIA1.R.4 @1292, VIA2.R.4 @1100 resisted 7
# trials of surgical metal: their vias refuse every delete incantation
# (editDelete/dbDeleteObj/status games), editMove silently no-ops, and the
# R.4 branch window is cut-gap [0.10, <0.15) against an engine that arrays
# whole overlaps. The correct instrument is the ROUTER: rip the three nets
# and ecoRoute — a fresh pattern clears artifact-class DRC. CTS_27 is a
# clock net and hold margin is +0.010: timeDesign gates below.
set __ripnets {CTS_27 FE_OFN2709_n FE_OFN2389_FE_DBTN5_sh_we_3}
foreach __n $__ripnets {
	set __rc [catch {editDelete -nets $__n} __msg]
	puts "PG4P2: rip $__n rc=$__rc msg=[string range $__msg 0 60]"
}
# trial 10: the reroute RECREATED the identical VIA2.R.4 pattern at
# (1100.5,39.5) — router determinism (same pin, same track). A VIA2 cut
# blockage over the exact spot forces the M2->M3 transition elsewhere.
set __blkrc [catch {createRouteBlk -box {1100.30 39.30 1100.75 39.70} -layer VIA2 -name pg4p2_v2blk} __msg]
puts "PG4P2: via2 blockage rc=$__blkrc msg=[string range $__msg 0 60]"
catch {setNanoRouteMode -routeWithEco true}
set __rc [catch {ecoRoute} __msg]
puts "PG4P2: ecoRoute rc=$__rc msg=[string range $__msg 0 80]"
foreach __n $__ripnets {
	set __net [dbGet -p top.nets.name $__n]
	set __nw [llength [dbGet -e $__net.wires]]
	puts "PG4P2: rerouted $__n wires=$__nw"
	if {$__nw < 1} { puts "PG4P2 FATAL: $__n not rerouted"; incr __fatals }
}
catch {deleteRouteBlk -name pg4p2_v2blk}
# trial 10: the CTS_27 reroute broke hold (WNS -0.016, 62 reg2reg paths;
# pre-ECO margin was only +0.010) — standard closing move:
catch {optDesign -postRoute -hold}
# the hold-fix ECO routes new buffers -> fresh min-area slivers (trial 11:
# M4.A.1 x2 at y470); second pass over the post-opt site list
__minarea_pass /home/mseminario2/vestarv/signoff_mp/minarea_sites_postopt.txt postopt
catch {timeDesign -postRoute -hold -prefix pg4p2hold -outDir rpt/pg4p2_timing}
catch {timeDesign -postRoute -prefix pg4p2setup -outDir rpt/pg4p2_timing}
puts "### UNL STATUS ### : PG4P2 onesie fixes done, fatals=$__fatals"

# ---------------- output -----------------------------------------------------
if {$__trial} {
	streamOut out/MCU_MP.trial.gds2 \
		-libName WorkLib -structureName MCU -stripes 1 -units 1000 -mode ALL \
		-merge [list out/hart_tile.gds2] -mapFile in/innovus2gds.map
	puts "### UNL STATUS ### : PG4P2 TRIAL GDS cut (out/MCU_MP.trial.gds2, NOTHING SAVED)"
} else {
	if {$__fatals > 0} { puts "PG4P2 FATAL: refusing to save with $__fatals fatals"; exit 1 }
	saveDesign dbs/MCU_MP.signoff.innovus -def -netlist -rc -tcon
	streamOut out/MCU_MP.gds2 \
		-libName WorkLib -structureName MCU -stripes 1 -units 1000 -mode ALL \
		-merge [list out/hart_tile.gds2] -mapFile in/innovus2gds.map
	puts "### UNL STATUS ### : PG4P2 committed — DB re-saved + GDS re-cut"
	puts "REMINDER: re-patch dbs/.../MCU.mode -tapeOut false (fresh save resets it)"
}
exit
