# C6 endgame PASS 3 (2026-07-29) — THE PROMOTION CANDIDATE: pass-2 replay
# (eco + additive, both proven) + the 6 special-via deletions (VIA7 weld
# interleave x4, VIA4.R.4:M5 single-cut pair x2 — targets from the signoff
# DEF SPECIALNETS probe, all VDD, all redundant: the 845.17 4-layer stack
# stays; the tile-GDS weld cuts stay) + hold check + FULL outputs
# (GDS/SDF/netlist) + saveDesign dbs/MCU_castalia.c6.innovus. Promotion over
# the canonical names happens ONLY after full signoff (chipdrc/ant25/LVS).
# PASS-2 lineage: eco REPLAY (proven deterministic x3) +
# ADDITIVE fixes, one session. Order per the G1 pass-4 lesson: ecoRoute first,
# add_shape merges after. Additive content: minarea x179 (direction-hinted
# sites, regenerated from the c6e1e chipdrc.db + fresh-ingest layout.gds),
# M7 same-net gap merges x6, M5/M6 pad-gap fills, M4.S.1 tile-seam notch
# fills x3, M2.S.2-family same-net sliver fills x6 (every site verified
# single-net from the c6e1e window dumps). Plus FORENSIC DUMPS ONLY (no
# edits): special-via geometry at the VIA7/VIA4.R.4 windows, insts at the
# M2.S.1 cell-internal site. Trial streamOut c6e3, NO saveDesign.
# (pass-1e lineage:
# 1e: classifier keyed on (net,layer,STATUS) — 1d box-level forensics proved
# the entire ecoRoute sWire delta is status=shield rip/regen (0 non-shield
# changed lines in the VSS/M2 diff; population 4449 shield + 3 routed). The
# G1-accepted class. Shrink in a status=shield pair is logged-accepted;
# any other shrink or new M7/M8 pair is FATAL.
# (originally PASS 1b (2026-07-29) — MCU_castalia chipdrc 1966 -> density-only.
# ECOROUTE-FIRST pass (G1 pass-4 lesson: additive merges must come AFTER any
# ecoRoute, so the rip/reroute stage runs FIRST, additive patches in pass 2).
#
# 1b REVISION: pass-1's exact sWire-COUNT guard fired on a benign delta
# (15,966 -> 19,837 objects across ecoRoute, insts EXACT, wires +28) — the G1
# devlog's own finding: "pointer identity is NOT stable across ecoRoute —
# classify, don't count" (shield/followpin fragmentation). The guard is now a
# per-(net,layer) AREA-conservation classifier: FATAL on any pair shrinking
# >1% (and >5 um^2), on VDD/VSS total area drifting >0.5%, or on any NEW
# M7/M8 pair >5 um^2 (PG-climb tell). Count deltas are logged, not fatal.
#
# This pass:
#   - A7 fresh-init + defIn (assembly restoreDesign FATALs in tape-out mode).
#   - Reconstructs the ROUTING-ERA blockade state the DEF does not carry
#     (G1 landmine): M7/M8 die-frame PG blankets + the 4 analog-window
#     layer-1-8 route blocks + full setNanoRouteMode set. The flow ran
#     deleteAllRouteBlks + seal-band-only restore before signoff, so the
#     signoff DEF carries ONLY seal-ring route blks (verified 2026-07-29:
#     BLOCKAGES 40 = 8 placement + 32 seal-ring layer rects).
#   - Cut blockages at the 3 Calibre sites the router can't see
#     (M3.S.2 x2, M5.S.2 x1 — cq8a v2 recipe) + ecoRoute -fix_drc.
#     DEVIATION from cq8a v2: -routeInsertAntennaDiode false (G2 antenna-pass
#     precedent) — inst-count invariance is a hard guard here.
#   - Hold pre/post (defIn view = the G1 hold authority; compare in-view only).
#   - Inspection dumps at every remaining surgery site (pass-2 inputs).
#   - Window route blocks deleted again before streamOut (flow parity — they
#     manufacture the ~244 phantom pin-vs-blockage class in verify if left).
#   - Count guards; trial streamOut out/MCU_castalia.c6e3.gds2; NO saveDesign.
#
# Run: cd ~/vestarv/innovus/common/MCU_castalia && innovus -no_gui -batch \
#        -log log/mcu_castalia_c6e3 \
#        -files /home/mseminario2/vestarv/signoff_mp/tcl/mcu_castalia_c6_pass3.tcl

source ../shared/constants.tcl
source ../shared/procedures.tcl

set IO_PAD_LEF /opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/lef/tphn65gpgv2od3_sl_210a/mt_2/8lm/lef/tphn65gpgv2od3_sl_8lm.lef
set IO_PAD_GDS /opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/gds/tphn65gpgv2od3_sl_210a/mt_2/8lm/tphn65gpgv2od3_sl.gds

set init_verilog   "$OUTPUT_DIR/MCU_castalia.xsim.v"
set init_top_cell  MCU_castalia
set init_pwr_net   VDD
set init_gnd_net   VSS
set init_mmmc_file "$SCRIPT_DIR/viewdefinition_MCU_castalia.tcl"
set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					$IP_DIR/rom_hvt_pg/rom_hvt_pg.lef \
					$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef \
					$IC_DIR/abstracts/myshkin_abs/GlitchFilter/GlitchFilter.lef \
					$IC_DIR/abstracts/myshkin_abs/PowerOnResetCheng/PowerOnResetCheng.lef \
					$IC_DIR/abstracts/myshkin_abs/OscillatorCurrentStarved/OscillatorCurrentStarved.lef \
					../hart_tile/out/hart_tile.lef \
					$IO_PAD_LEF"
set init_design_uniquify 1
init_design
setDesignMode -process 65 -flowEffort standard -powerEffort low
setMultiCpuUsage -localCpu 8

defIn $DATABASE_DIR/MCU_castalia.signoff.innovus.dat/MCU_castalia.def.gz
clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst * -module {} -autoTie -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -module {} -autoTie -verbose

proc __counts {} {
	set ni [llength [dbGet -e top.insts]]
	set ns [llength [dbGet -e top.nets.sWires]]
	set nw [llength [dbGet -e top.nets.wires]]
	return [list $ni $ns $nw]
}
proc __fatal {msg} { puts "C6E3 FATAL: $msg"; exit 1 }
foreach {__ni0 __ns0 __nw0} [__counts] {}
puts "C6E3 COUNTS baseline: insts=$__ni0 sWires=$__ns0 wires=$__nw0"
if {$__ni0 < 500000} { __fatal "instCount $__ni0 implausibly low — defIn broken" }
if {$__ns0 == 0 || $__nw0 == 0} { __fatal "sWires/wires zero at baseline" }
set __rblk0 [llength [dbGet -e top.fPlan.rBlkgs]]
puts "C6E3 route blockages carried by DEF: $__rblk0 (expect seal-ring only)"

# Per-(net,layer,shape) sWire area snapshot — the classify-don't-count guard.
# 1c: key includes the SHAPE attribute so the acceptance rule can be G1's
# actual finding: sWire deltas across ecoRoute are legitimate ONLY when they
# are shield rip/regen — shrink in a SHIELD-shaped pair is logged, shrink in
# any other shape (FOLLOWPIN/STRIPE/RING/...) is FATAL.
proc __swire_snapshot {} {
	set d [dict create]
	foreach s [dbGet -e top.nets.sWires] {
		set net [lindex [dbGet -e $s.net.name] 0]
		set lay [dbGet -e $s.layer.name]
		set shp [dbGet -e $s.status]
		set box [lindex [dbGet -e $s.box] 0]
		if {$net eq "" || $lay eq "" || [llength $box] != 4} { continue }
		if {$shp eq ""} { set shp NONE }
		foreach {x0 y0 x1 y1} $box {}
		set a [expr {($x1 - $x0) * ($y1 - $y0)}]
		set k "$net|$lay|$shp"
		if {[dict exists $d $k]} {
			lassign [dict get $d $k] c aa
			dict set d $k [list [expr {$c + 1}] [expr {$aa + $a}]]
		} else {
			dict set d $k [list 1 $a]
		}
	}
	return $d
}

# Box-level dump of one (net,layer) family to a file — forensic diff input.
proc __swire_boxdump {net lay fname} {
	set fp [open $fname w]
	foreach s [dbGet -e top.nets.sWires] {
		if {[lindex [dbGet -e $s.net.name] 0] ne $net} { continue }
		if {[dbGet -e $s.layer.name] ne $lay} { continue }
		set box [lindex [dbGet -e $s.box] 0]
		set shp [dbGet -e $s.status]
		set st  [dbGet -e $s.status]
		puts $fp "$box shape=$shp status=$st"
	}
	close $fp
}

# ---------------- hold PRE (defIn view = authority) -------------------------
# (1d: hold reports already captured bit-identical in e1/e1b — skip the two
#  timeDesigns this iteration, this run is pure sWire forensics.)
set __sw_pre [__swire_snapshot]
puts "C6E3 sWire snapshot PRE: [dict size $__sw_pre] (net,layer) pairs"
__swire_boxdump VSS M2 $REPORT_DIR/MCU_castalia.c6e3.vssm2_pre.txt
puts "C6E3: VSS/M2 box dump PRE written"

# ---------------- routing-era blockade state reconstruction -----------------
# M7/M8 PG-only die-frame blankets (flow lines 948-949; DIE = -155..2845).
createRouteBlk -name c6_pgblanket_m7 -box {-155 -155 2845 2845} -layer 7
createRouteBlk -name c6_pgblanket_m8 -box {-155 -155 2845 2845} -layer 8
# Analog-window layer-1-8 route blocks (as-built boxes from the floorplan DEF
# placement rects, um; deleted again before streamOut below).
createRouteBlk -name c6_win_rt0 -box {100 1 600 451}       -layer {1 2 3 4 5 6 7 8}
createRouteBlk -name c6_win_rt1 -box {2090 1 2590 451}     -layer {1 2 3 4 5 6 7 8}
createRouteBlk -name c6_win_rt2 -box {100 2239 600 2689}   -layer {1 2 3 4 5 6 7 8}
createRouteBlk -name c6_win_rt3 -box {2090 2239 2590 2689} -layer {1 2 3 4 5 6 7 8}
puts "C6E3: routing-era blockades re-declared (M7/M8 blankets + 4 windows)"

# Full nanoroute mode set (flow parity; DEF carries NO mode state).
setNanoRouteMode \
	-routeTopRoutingLayer 7 \
	-envNumberFailLimit 10 \
	-droutePostRouteSwapVia multiCut \
	-drouteUseMultiCutViaEffort medium \
	-routeAllowPowerGroundPin true \
	-drouteFixAntenna true \
	-routeAntennaCellName "ANTENNA2A10TH" \
	-routeInsertAntennaDiode false \
	-routeWithTimingDriven false

# ---------------- cut blockages at the Calibre-only sites -------------------
# Sites from chipdrc.db (this cut's own results, dumped 2026-07-29):
#   M3.S.2  (1418.000-1419.900, 1055.150-1055.250)
#   M3.S.2  (1519.650-1523.000, 1095.150-1095.250)
#   M5.S.2  ( 871.450- 873.000,  942.750- 942.850)
# cq8a v2 geometry: tiny boxes, ~2 um x-pad / ~0.6 um y-pad around the sliver.
createRouteBlk -name c6_m3_1 -box {1416.0 1054.5 1421.9 1055.9} -layer 3
createRouteBlk -name c6_m3_2 -box {1517.6 1094.5 1525.0 1095.9} -layer 3
createRouteBlk -name c6_m5_1 -box { 869.4  942.1  875.0  943.5} -layer 5
# v4: the M2.S.2-family CTS-array sites go to the G1 rip recipe (fills of any
# geometry promote the pad metal into the VIA1/VIA2 redundant-via wide-metal
# class — measured on c6e2 slivers x20 AND c6 full plates x23; the rule text
# demands >1 cut when M2/M3 width >0.3). Blockade the arrays, let ecoRoute
# re-land them legally (G1 precedent: CTS_30 was rip+ecoRoute'd for exactly
# this class on MCU_DP). @1297 is NOT blockaded — its sliver fill measured
# clean both rounds (no wide promotion, no enclosure fallout).
createRouteBlk -name c6_m2_1 -box {706.1 1023.3 710.0 1026.3} -layer 2
createRouteBlk -name c6_m2_2 -box {1318.1 936.5 1322.0 938.7} -layer 2
createRouteBlk -name c6_m2_3 -box {1643.1 1680.5 1647.0 1682.7} -layer 2
createRouteBlk -name c6_m2_4 -box {1146.8 851.3 1150.8 852.9} -layer 2
puts "C6E3: cut route blockages created (M3 x2, M5 x1, M2 x4)"

if {[catch {ecoRoute -fix_drc} r]} { puts "C6E3 WARN: ecoRoute -fix_drc: $r" }
puts "C6E3: ecoRoute -fix_drc done"

# Remove the three cut blockages + the window blocks (flow parity before any
# verify/streamOut); keep the M7/M8 blankets until after streamOut — they were
# design-frame keep-outs during routing and affect nothing downstream here.
foreach b {c6_m3_1 c6_m3_2 c6_m5_1 c6_m2_1 c6_m2_2 c6_m2_3 c6_m2_4 c6_win_rt0 c6_win_rt1 c6_win_rt2 c6_win_rt3} {
	catch {deleteRouteBlk -name $b}
}

# ---------------- count guards (hold skipped this forensic iteration) -------
__swire_boxdump VSS M2 $REPORT_DIR/MCU_castalia.c6e3.vssm2_post.txt
puts "C6E3: VSS/M2 box dump POST written"

foreach {__ni1 __ns1 __nw1} [__counts] {}
puts "C6E3 COUNTS post-eco: insts=$__ni1 sWires=$__ns1 wires=$__nw1 (base $__ni0/$__ns0/$__nw0)"
if {$__ni1 != $__ni0} { __fatal "inst count changed ($__ni0 -> $__ni1) — diode/cell insertion happened" }
if {abs($__nw1 - $__nw0) > 5000} { __fatal "wire delta implausible ($__nw0 -> $__nw1)" }

# sWire classifier (replaces the count guard — see 1b header).
set __sw_post [__swire_snapshot]
puts "C6E3 sWire snapshot POST: [dict size $__sw_post] pairs (was [dict size $__sw_pre])"
set __pgpre 0.0; set __pgpost 0.0
dict for {k v} $__sw_pre {
	lassign [split $k |] n l shp
	if {$n eq "VDD" || $n eq "VSS"} { set __pgpre [expr {$__pgpre + [lindex $v 1]}] }
}
dict for {k v} $__sw_post {
	lassign [split $k |] n l shp
	if {$n eq "VDD" || $n eq "VSS"} { set __pgpost [expr {$__pgpost + [lindex $v 1]}] }
}
puts [format "C6E3 PG (VDD+VSS) sWire area: pre=%.1f post=%.1f um^2 (drift %.4f%%)" \
	$__pgpre $__pgpost [expr {$__pgpre > 0 ? 100.0*($__pgpost-$__pgpre)/$__pgpre : 999}]]
if {$__pgpre <= 0} { __fatal "PG sWire area pre-snapshot is zero — snapshot broken" }
if {abs($__pgpost - $__pgpre) > 0.005 * $__pgpre} { __fatal "VDD/VSS total sWire area drifted >0.5%" }
set __nshr 0
dict for {k v} $__sw_pre {
	lassign $v c0 a0
	if {[dict exists $__sw_post $k]} { lassign [dict get $__sw_post $k] c1 a1 } else { set c1 0; set a1 0.0 }
	set __shr [expr {$a0 - $a1}]
	if {$__shr > 5.0 && $__shr > 0.01 * $a0} {
		lassign [split $k |] n l shp
		if {$shp eq "shield"} {
			puts [format "C6E3 SHIELD-SHRINK (accepted) %s: area %.2f -> %.2f (count %d -> %d)" $k $a0 $a1 $c0 $c1]
		} else {
			puts [format "C6E3 SHRINK %s: area %.2f -> %.2f (count %d -> %d)" $k $a0 $a1 $c0 $c1]
			incr __nshr
		}
	}
}
dict for {k v} $__sw_post {
	if {[dict exists $__sw_pre $k]} { continue }
	lassign [split $k |] n l shp
	lassign $v c1 a1
	puts [format "C6E3 NEWPAIR %s: count=%d area=%.2f" $k $c1 $a1]
	if {($l eq "M7" || $l eq "M8") && $a1 > 5.0} { incr __nshr }
}
if {$__nshr > 0} { __fatal "$__nshr sWire classifier violations (non-shield shrink / new M7-M8 pair) — see SHRINK/NEWPAIR lines" }
puts "C6E3: sWire classifier PASS (area-conserving; shield rip/regen + fragmentation logged only)"


# ================== ADDITIVE STAGE (after eco replay) =======================
set __fatals 0
foreach {__nie __nse __nwe} [__counts] {}
puts "C6E3 COUNTS post-eco: insts=$__nie sWires=$__nse wires=$__nwe"

# ---------------- min-area pass (G1E1 logic, direction-hint aware) ----------
array set __minarea {M1 0.052 M2 0.052 M3 0.052 M4 0.052 M5 0.052}
set __margin 0.006
proc __gridup {v} {
	set g [expr {$v * 200.0}]
	if {abs($g - round($g)) < 1e-6} { return [expr {round($g) / 200.0}] }
	return [expr {ceil($g) / 200.0}]
}
proc __minarea_pass {sitesfile tag} {
	global __minarea __margin __fatals
	set __fp [open $sitesfile r]
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
		if {$__net eq ""} { incr __nskip; puts "C6E3 minarea($tag): NO wire under $__lay ($__x0 $__y0 $__x1 $__y1) — skipped"; continue }
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
		if {!$__done} { incr __nfail; puts "C6E3 minarea($tag): BLOCKED both directions at $__lay ($__x0 $__y0 $__x1 $__y1) net=$__net" }
	}
	close $__fp
	puts "### C6E3 ### minarea $tag — $__npatch patched, $__nskip skipped, $__nfail blocked"
	if {$__nfail > 0} { incr __fatals }
}
__minarea_pass /home/mseminario2/vestarv/signoff_mp/minarea_sites_c6.txt main

# ---------------- clearance-checked same-net merges (PG4 __mrg) -------------
# clr = foreign-clearance window (0.16 for M2/M4/M5/M6; 2.0 for thick M7).
proc __mrg {tag net lay rect {clr 0.16}} {
	global __fatals
	foreach {x0 y0 x1 y1} $rect {}
	set thr [expr {$clr - 0.0001}]
	set chk [list [expr {$x0-$clr}] [expr {$y0-$clr}] [expr {$x1+$clr}] [expr {$y1+$clr}]]
	foreach o [concat [dbQuery -area $chk -objType wire] [dbQuery -area $chk -objType sWire]] {
		if {[dbGet -e $o.layer.name] ne $lay} { continue }
		if {[lindex [dbGet -e $o.net.name] 0] eq $net} { continue }
		set ob [lindex [dbGet $o.box] 0]
		foreach {ox0 oy0 ox1 oy1} $ob {}
		set dx [expr {max($x0-$ox1, $ox0-$x1)}]
		set dy [expr {max($y0-$oy1, $oy0-$y1)}]
		if {$dx < $thr && $dy < $thr} {
			puts "C6E3 FATAL: $tag foreign $lay net=[dbGet -e $o.net.name] at $ob blocks rect $rect"
			incr __fatals
			return
		}
	}
	add_shape -net $net -layer $lay -rect $rect -shape STRIPE -status ROUTED
	puts "C6E3: $tag merged rect $rect on $net/$lay"
}
proc __netat {lay win} {
	foreach o [concat [dbQuery -area $win -objType sWire] [dbQuery -area $win -objType wire]] {
		if {[dbGet -e $o.layer.name] ne $lay} { continue }
		set n [lindex [dbGet -e $o.net.name] 0]
		if {$n ne ""} { return $n }
	}
	return ""
}
proc __mrg_at {tag lay rect {clr 0.16}} {
	# resolve net at the rect's immediate vicinity, then merge
	foreach {x0 y0 x1 y1} $rect {}
	set win [list [expr {$x0-0.3}] [expr {$y0-0.3}] [expr {$x1+0.3}] [expr {$y1+0.3}]]
	set n [__netat $lay $win]
	if {$n eq ""} { global __fatals; puts "C6E3 FATAL: $tag no $lay net near $rect"; incr __fatals; return }
	__mrg $tag $n $lay $rect $clr
}

# M7.S.3/S.4 ROM-band same-net gaps (VDD rows y1244.5-1249.5, VSS rows
# y1253.5-1258.5; exact Calibre rects — nets resolved at runtime, 2.0 um
# foreign clearance for thick M7)
__mrg_at "M7@158" M7 {158.825 1244.5 159.0   1249.5} 2.0
# M7@164 + M6S3@4: partner shapes are special-via ENCLOSURE pads (invisible
# to the sWire/wire probe) — net is unambiguous VDD from the row context
# (c6e1e dumps: pure VDD PG stacks both sites). Explicit-net merges.
__mrg "M7@164" VDD M7 {164.425 1244.5 165.025 1249.5} 2.0
__mrg_at "M7@167" M7 {167.225 1253.5 168.0   1258.5} 2.0
__mrg_at "M7@173" M7 {173.0   1253.5 173.425 1258.5} 2.0
__mrg_at "M7@208" M7 {208.085 1244.5 209.0   1249.5} 2.0
__mrg_at "M7@214" M7 {214.0   1244.5 214.285 1249.5} 2.0
# c6e2 LESSON: filling @214 exposed the NEXT pad-pad gap in the same row
# (M7.S.4 x1 at 215.085-215.7) — fill it too (same VDD row context).
__mrg "M7@215" VDD M7 {215.085 1244.5 215.7 1249.5} 2.0

# M5.S.3 + M6.S.3 west-edge PG pad gap (both layers, same rect, VDD)
__mrg_at "M5S3@4"  M5 {4.0 1548.595 14.0 1548.91} 0.16
__mrg "M6S3@4"  VDD M6 {4.0 1548.595 14.0 1548.91} 0.16
# M6.S.3 ROM-band VSS pad gap
__mrg_at "M6S3@165" M6 {165.5 1255.6 165.7 1258.5} 0.16

# M4.S.1 tile-seam notch fills (fabric wire meets its own tile pin; exact rects)
__mrg "M4S1@679"   mcu0/CTS_30 M4 {679.613 1639.05 679.85  1639.1}
__mrg "M4S1@2010a" mcu0/CTS_35 M4 {2010.15 1050.9  2010.387 1050.95}
__mrg "M4S1@2010b" mcu0/CTS_35 M4 {2010.15 1639.05 2010.387 1639.1}

# M2.S.2-family fills. c6e2 LESSON: thin 0.1-um sliver bridges next to via
# cuts broke the cuts' enclosure classification (VIA2.R.2__R.3 x12 +
# VIA1.R.2__R.3 x8 sprouted at the @708/@1320/@1645/@1148 sliver sites) —
# v2 = FULL-WIDTH union plates over each via-array gap band so every cut is
# deep inside a fat rectangle. @1297 kept as the original sliver (it produced
# no enclosure fallout on c6e2). All same-net (single-net windows, c6e1e dumps).
__mrg "M2S2@1297"  mcu0/nfc0/CTS_6          M2 {1297.5  1725.5   1297.6 1726.135}

# ---------------- special-via deletions (6 targets, all VDD) ----------------
# editSelect/editDelete ONLY (dbDeleteObj = the G0 cuts-survive-streamOut
# trap). Tight boxes contain exactly one special via each (DEF probe: no other
# sVia within +-2 um except the kept 845.17 stack, excluded by the boxes).
# c6e3 first-run lesson: with the M7/M8 blanket route blockages still armed,
# editSelect returned 0 objects for every VIA7-layer target while the VIA4
# targets (unblanketed layers) selected fine. The blankets are done working
# (ecoRoute already ran; nothing routes after this) — drop them here.
catch {deleteRouteBlk -name c6_pgblanket_m7}
catch {deleteRouteBlk -name c6_pgblanket_m8}
set __svias0 [llength [dbGet -e top.nets.sVias]]
proc __delvia {tag box} {
	global __fatals
	deselectAll
	if {[catch {editSelect -area $box -net VDD -object_type Via} r]} {
		if {[catch {editSelectVia -area $box -net VDD} r2]} {
			puts "C6E3 FATAL: $tag no via-selection primitive worked: $r / $r2"
			incr __fatals
			return
		}
	}
	set n [llength [dbGet -e selected]]
	if {$n != 1} {
		puts "C6E3 FATAL: $tag selected $n objects (want exactly 1) in $box"
		foreach o [dbGet -e selected] { puts "C6E3   sel: [dbGet -e $o.objType] [dbGet -e $o.via.name]" }
		incr __fatals
		deselectAll
		return
	}
	puts "C6E3: $tag deleting via=[dbGet -e [dbGet -e selected].via.name]"
	editDelete -selected
	deselectAll
}
__delvia "SVDEL@621"   {618.9 1640.9 622.9 1644.9}
__delvia "SVDEL@2214"  {2211.7 1045.1 2215.7 1049.1}
__delvia "SVDEL@221"   {219.3 1045.3 223.3 1049.3}
__delvia "SVDEL@613"   {612.3 1645.9 616.3 1649.9}
__delvia "SVDEL@845a"  {845.485 1397.22 845.785 1397.52}
__delvia "SVDEL@845b"  {845.475 1396.41 845.775 1396.71}
set __svias1 [llength [dbGet -e top.nets.sVias]]
puts "C6E3 sVia count: $__svias0 -> $__svias1 (expect -6)"
if {$__fatals == 0 && [expr {$__svias0 - $__svias1}] != 6} {
	puts "C6E3 FATAL: sVia delta != 6"
	incr __fatals
}

# ---------------- forensic dumps (NO edits) ---------------------------------
# Special vias intersecting the VIA7 / VIA4.R.4 violation windows.
set __svwins {
	{VIA7W1@621  620.0  1642.2 622.5  1644.7}
	{VIA7W1@2214 2213.0 1045.3 2215.4 1047.8}
	{VIA7S@221   220.0  1045.3 223.0  1048.0}
	{VIA7S@613   612.6  1646.0 615.2  1649.8}
	{VIA4R4@845  844.6  1395.5 846.7  1398.4}
}
foreach n [dbGet -p top.nets.name VDD] { set __pgnets(VDD) $n }
foreach n [dbGet -p top.nets.name VSS] { set __pgnets(VSS) $n }
foreach pg {VDD VSS} {
	if {![info exists __pgnets($pg)]} { continue }
	foreach sv [dbGet -e $__pgnets($pg).sVias] {
		set b [lindex [dbGet -e $sv.box] 0]
		if {[llength $b] != 4} { continue }
		foreach {bx0 by0 bx1 by1} $b {}
		foreach w $__svwins {
			foreach {tag wx0 wy0 wx1 wy1} $w {}
			if {$bx0 <= $wx1 && $bx1 >= $wx0 && $by0 <= $wy1 && $by1 >= $wy0} {
				puts "C6E3 SVIA $tag net=$pg via=[dbGet -e $sv.via.name] box=$b status=[dbGet -e $sv.status]"
			}
		}
	}
}
puts "C6E3: sVia dumps done"
# Insts at the M2.S.1 cell-internal site
foreach o [dbQuery -area {632.4 784.3 634.4 786.7} -objType inst] {
	puts "C6E3 M2S1INST name=[dbGet -e $o.name] cell=[dbGet -e $o.cell.name] box=[dbGet -e $o.box] orient=[dbGet -e $o.orient]"
}
puts "C6E3: M2.S.1 inst dump done"

# ---------------- guards + trial streamOut ----------------------------------
if {$__fatals > 0} { __fatal "$__fatals merge/minarea fatals — NO streamOut" }
foreach {__ni1 __ns1 __nw1} [__counts] {}
puts "C6E3 COUNTS post-patch: insts=$__ni1 sWires=$__ns1 wires=$__nw1 (post-eco $__nie/$__nse/$__nwe)"
if {$__ni1 != $__nie} { __fatal "inst count changed in additive stage" }
if {$__nw1 != $__nwe} { __fatal "regular wire count changed (additive stage must not)" }
if {[expr {$__ns1 - $__nse}] > 250} { __fatal "sWire growth implausible ($__nse -> $__ns1)" }

# ---------------- hold post-all-edits + outputs + save ----------------------
catch { setAnalysisMode -analysisType onChipVariation -cppr both }
timeDesign -postRoute -hold -outDir $REPORT_DIR/MCU_castalia.c6e3.hold_post

streamOut \
	$OUTPUT_DIR/MCU_castalia.c6.gds2 \
	-libName WorkLib \
	-structureName MCU_castalia \
	-stripes 1 \
	-units 1000 \
	-mode ALL \
	-merge [list ../hart_tile/out/hart_tile.gds2 $IO_PAD_GDS] \
	-mapFile ../shared/innovus2gds.map
puts "C6E3: GDS out/MCU_castalia.c6.gds2 written"

write_sdf $OUTPUT_DIR/MCU_castalia.c6.sdf
puts "C6E3: SDF written"

saveNetlist $OUTPUT_DIR/MCU_castalia.c6.xsim.v -excludeCellInst ANTENNA2A10TH
puts "C6E3: xsim netlist written"

setCheckMode -tapeOut false
saveDesign $DATABASE_DIR/MCU_castalia.c6.innovus -def -netlist -rc -tcon
puts "C6E3: COMPLETE (c6 DB + GDS + SDF + netlist; promotion after signoff)"
exit
