# G1 endgame PASS 2 (2026-07-23) — MCU_DP full endgame on the defIn vehicle.
# Pass-1 dumps dispositioned (all sites; nets are DP-cut facts, not PG4 copies):
#   MERGES (same-net additive, clearance-checked):
#     M2.S.1@1013 + G.4:M2i x2  -> irq_tielow M2 square-outs
#     M4.S.1 x4                 -> CTS_26/CTS_28 tile-seam notches (PG4 rects)
#     M7.S.4 x2                 -> VSS/VDD pad-group merges (pass-1 proven)
#   RIPS (+ ecoRoute; PG4 "router is the tool" class — same-net gclk twins):
#     gpio4/rc_gclk_2964, CTS_30, npu0/rc_gclk_3700, timer0/rc_gclk_3513
#     FE_OFN713_irq_comb_48 (DM2.S.2 — M2 routeBlk over the dummy keepout
#     band {881.3 480.35 882.0 481.15} during ecoRoute, deleted after)
#   MINAREA runs LAST (post-reroute), skipping sites whose net was ripped.
# Hold bar: post timeDesign -postRoute -hold WNS >= -0.006 / TNS >= -0.014
# (the defIn-view no-degradation bar; 4 marginal paths are fabric->tile-ETM
# boundary hops, disjoint from the ripped cones). streamOut out/MCU_DP.g1e4.gds2.
# NO saveDesign (finalize happens only after Calibre + hold adjudication).
#
# Run: cd ~/vestarv/innovus/common/MCU_DP && innovus -no_gui -batch \
#        -log log/mcu_dp_g1e3 -files ../../../signoff_mp/tcl/mcu_dp_g1_endgame3.tcl

source ../shared/constants.tcl
source ../shared/procedures.tcl

set init_verilog   "$OUTPUT_DIR/MCU_DP.xsim.v"
set init_top_cell  MCU
set init_pwr_net   VDD
set init_gnd_net   VSS
set init_mmmc_file "$SCRIPT_DIR/viewdefinition_top_dp.tcl"
set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					$IP_DIR/rom_hvt_pg/rom_hvt_pg.lef \
					$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef \
					$IC_DIR/abstracts/myshkin_abs/GlitchFilter/GlitchFilter.lef \
					$IC_DIR/abstracts/myshkin_abs/PowerOnResetCheng/PowerOnResetCheng.lef \
					$IC_DIR/abstracts/myshkin_abs/OscillatorCurrentStarved/OscillatorCurrentStarved.lef \
					$OUTPUT_DIR/hart_tile.lef"
set init_design_uniquify 1
init_design
setDesignMode -process 65 -flowEffort standard -powerEffort low
setMultiCpuUsage -localCpu 4

defIn $DATABASE_DIR/MCU_DP.signoff.innovus.dat/MCU.def.gz
clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst * -module {} -autoTie -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -module {} -autoTie -verbose

proc __counts {} {
	set ni [llength [dbGet -e top.insts]]
	set ns [llength [dbGet -e top.nets.sWires]]
	set nw [llength [dbGet -e top.nets.wires]]
	return [list $ni $ns $nw]
}
proc __fatal {msg} { puts "G1E3 FATAL: $msg"; exit 1 }
foreach {__ni0 __ns0 __nw0} [__counts] {}
puts "G1E3 COUNTS baseline: insts=$__ni0 sWires=$__ns0 wires=$__nw0"
if {$__ni0 != 182364} { __fatal "instCount != 182364 canonical" }
set __fatals 0
set __sw0 [dict create]
foreach __p [dbGet -e top.nets.sWires] { dict set __sw0 $__p 1 }

# pre-edit timing reference (same session, apples-to-apples)
setDelayCalMode -SIAware false
setAnalysisMode -analysisType onChipVariation -cppr both
timeDesign -postRoute -hold -outdir rpt/MCU_DP.g1e3.timeDesign.hold_pre

# ---------------- merges --------------------------------------------------
proc __mrg {tag net lay rect} {
	global __fatals
	foreach {x0 y0 x1 y1} $rect {}
	set chk [list [expr {$x0-0.16}] [expr {$y0-0.16}] [expr {$x1+0.16}] [expr {$y1+0.16}]]
	foreach o [concat [dbQuery -area $chk -objType wire] [dbQuery -area $chk -objType sWire]] {
		if {[dbGet -e $o.layer.name] ne $lay} { continue }
		if {[lindex [dbGet -e $o.net.name] 0] eq $net} { continue }
		set ob [lindex [dbGet $o.box] 0]
		foreach {ox0 oy0 ox1 oy1} $ob {}
		set dx [expr {max($x0-$ox1, $ox0-$x1)}]
		set dy [expr {max($y0-$oy1, $oy0-$y1)}]
		if {$dx < 0.0999 && $dy < 0.0999} {
			puts "G1E3 FATAL: $tag foreign $lay net=[dbGet -e $o.net.name] at $ob blocks rect $rect"
			incr __fatals
			return
		}
	}
	add_shape -net $net -layer $lay -rect $rect -shape STRIPE -status ROUTED
	puts "G1E3: $tag merged rect $rect on $net/$lay"
}
proc __netat {lay win} {
	foreach o [concat [dbQuery -area $win -objType sWire] [dbQuery -area $win -objType wire]] {
		if {[dbGet -e $o.layer.name] ne $lay} { continue }
		set n [lindex [dbGet -e $o.net.name] 0]
		if {$n ne ""} { return $n }
	}
	return ""
}

# M7.S.4 x2 (pass-1 proven)
set __n7a [__netat M7 {208.0 459.0 209.2 464.0}]
if {$__n7a eq ""} { __fatal "M7.S.4@208: no M7 net" }
__mrg "M7.S.4@208" $__n7a M7 {208.0 459.0 209.2 464.0}
set __n7b [__netat M7 {248.85 450.0 250.2 455.0}]
if {$__n7b eq ""} { __fatal "M7.S.4@249: no M7 net" }
# pass-1 residual: a SECOND pad gap at x 247.685-248.285 (same group) — one
# rect spans both gaps; __mrg clearance-checks the widened span
__mrg "M7.S.4@249" $__n7b M7 {247.6 450.0 250.2 455.0}

# irq_tielow set (M2.S.1 gap-fill + G.4 square-outs top AND bottom of the
# 1006 wire; 1049 rect TOP CAPPED at 484.79 — the 485.04 top of the first cut
# reached into the analog-macro dummy-M2 keepout = the pass-3 DM2.S.2)
__mrg "M2.S.1@1013"  irq_tielow M2 {1013.805 482.36 1013.905 482.6}
__mrg "G.4@1006t"    irq_tielow M2 {1006.65 484.4 1006.79 484.6}
__mrg "G.4@1006b"    irq_tielow M2 {1006.65 482.36 1006.79 482.6}
__mrg "G.4@1049"     irq_tielow M2 {1049.45 484.5 1049.635 484.79}

# M4.S.1 x4 tile-seam notches (dump nets CTS_26 / CTS_28)
__mrg "M4.S.1@679"  CTS_26 M4 {679.6 648.9 680.11 649.3}
__mrg "M4.S.1@1342" CTS_28 M4 {1342.6 648.9 1343.11 649.3}
__mrg "M4.S.1@1346" CTS_28 M4 {1345.89 648.9 1346.4 649.3}
__mrg "M4.S.1@2009" CTS_28 M4 {2008.9 648.9 2009.4 649.3}

if {$__fatals > 0} { __fatal "$__fatals merge fatals — stopping before rips" }
# post-merge reference counts (merges add STRIPE sWires; rip guard compares here)
foreach {__niM __nsM __nwM} [__counts] {}
puts "G1E3 COUNTS post-merge: insts=$__niM sWires=$__nsM wires=$__nwM"
if {$__niM != $__ni0} { __fatal "inst count changed on merges" }
if {$__nwM != $__nw0} { __fatal "regular wire count changed on merges" }

# ---------------- rips + blockage + ecoRoute ------------------------------
set __ripnets [list gpio4/rc_gclk_2964 CTS_30 npu0/rc_gclk_3700 timer0/rc_gclk_3513 FE_OFN713_irq_comb_48]
foreach __net $__ripnets {
	deselectAll
	set __netEsc [string map {\[ \\\[ \] \\\]} $__net]
	editSelect -net $__netEsc
	set __nsel [llength [dbGet -e selected]]
	if {$__nsel == 0} { __fatal "editSelect selected nothing for $__net" }
	puts "G1E3 RIP: $__net ($__nsel objects)"
	editDelete -selected
	deselectAll
}
foreach {__ni1 __ns1 __nw1} [__counts] {}
puts "G1E3 COUNTS post-rip: insts=$__ni1 sWires=$__ns1 wires=$__nw1"
if {$__ni1 != $__ni0} { __fatal "inst count changed on rip" }
if {[expr {$__nsM - $__ns1}] > 40 || $__ns1 > $__nsM} { __fatal "sWire delta on rip out of bounds ($__nsM -> $__ns1)" }
if {$__nw1 >= $__nwM || [expr {$__nwM - $__nw1}] > 3000} { __fatal "wire rip delta implausible ($__nwM -> $__nw1)" }

# flow parity (MCU_DP.innovus.tcl 420-422/495-500): M7/M8 are PG-only for
# signal routing — the DEF does NOT carry these, and the first pass-2 cut
# proved ecoRoute climbs to M7/M8 without them (8 new VIA6/VIA7 structs in
# the census). Antenna-diode options deliberately OMITTED (would add insts).
createRouteBlk -name g1e2_m7blk -box {0 0 2689 1700} -layer 7
createRouteBlk -name g1e2_m8blk -box {0 0 2689 1700} -layer 8
setNanoRouteMode \
	-routeTopRoutingLayer 7 \
	-droutePostRouteSwapVia multiCut \
	-drouteUseMultiCutViaEffort medium \
	-routeAllowPowerGroundPin true
createRouteBlk -name g1e2_dm2blk -layer M2 -box {881.3 480.35 882.0 481.15}
ecoRoute
deleteRouteBlk -name g1e2_dm2blk
deleteRouteBlk -name g1e2_m7blk
deleteRouteBlk -name g1e2_m8blk

foreach {__ni2 __ns2 __nw2} [__counts] {}
puts "G1E3 COUNTS post-ecoRoute: insts=$__ni2 sWires=$__ns2 wires=$__nw2"
if {$__ni2 != $__ni0} { __fatal "inst count changed on ecoRoute" }
if {[expr {abs($__nw2 - $__nw0)}] > 4000} { __fatal "wire count diverged ($__nw0 -> $__nw2)" }
set __nbad 0; set __nnew 0
foreach __p [dbGet -e top.nets.sWires] {
	if {[dict exists $__sw0 $__p]} { continue }
	incr __nnew
	set __st [dbGet -e $__p.status]
	set __sh [dbGet -e $__p.shape]
	set __nn [lindex [dbGet -e $__p.net.name] 0]
	# allowed: VDD/VSS shields, and our own STRIPE patches (status routed, shape stripe)
	if {($__nn eq "VSS" || $__nn eq "VDD") && ([string tolower $__st] eq "shield" || [string tolower $__sh] eq "shield")} { continue }
	if {[string tolower $__sh] eq "stripe"} { continue }
	incr __nbad
	puts "G1E3 SWIRE-NEW UNEXPECTED: net=$__nn status=$__st shape=$__sh box=[dbGet -e $__p.box]"
}
puts "G1E3 SWIRE DELTA: checked-new=$__nnew unexpected=$__nbad"
if {$__nbad > 0} { __fatal "unexpected new sWires after ecoRoute" }

# ---------------- minarea LAST (post-reroute), skip ripped nets ------------
array set __minarea {M1 0.052 M2 0.052 M3 0.052 M4 0.052 M5 0.052}
set __margin 0.006
proc __gridup {v} {
	set g [expr {$v * 200.0}]
	if {abs($g - round($g)) < 1e-6} { return [expr {round($g) / 200.0}] }
	return [expr {ceil($g) / 200.0}]
}
proc __minarea_pass {sitesfile tag} {
	global __minarea __margin __fatals __ripnets
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
		if {$__net eq ""} { incr __nskip; puts "G1E3 minarea($tag): NO wire under $__lay ($__x0 $__y0 $__x1 $__y1) — skipped"; continue }
		if {[lsearch -exact $__ripnets $__net] >= 0} { incr __nskip; puts "G1E3 minarea($tag): net $__net was ripped/rerouted — skipped"; continue }
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
		if {!$__done} { incr __nfail; puts "G1E3 minarea($tag): BLOCKED both directions at $__lay ($__x0 $__y0 $__x1 $__y1) net=$__net" }
	}
	close $__fp
	puts "### G1E3 ### minarea $tag — $__npatch patched, $__nskip skipped, $__nfail blocked"
	if {$__nfail > 0} { incr __fatals }
}
__minarea_pass /home/mseminario2/vestarv/signoff_mp/minarea_sites_dp2.txt main
if {$__fatals > 0} { __fatal "$__fatals fatals after minarea — NO streamOut" }

# ---------------- post hold + streamOut ------------------------------------
timeDesign -postRoute -hold -outdir rpt/MCU_DP.g1e3.timeDesign.hold_post
puts "G1E3 TIMING: post hold report written (adjudicate vs pre: WNS>=-0.006 TNS>=-0.014)"

streamOut \
	$OUTPUT_DIR/MCU_DP.g1e4.gds2 \
	-libName WorkLib \
	-structureName MCU \
	-stripes 1 \
	-units 1000 \
	-mode ALL \
	-merge [list $OUTPUT_DIR/hart_tile.gds2] \
	-mapFile ../shared/innovus2gds.map
puts "G1E3: COMPLETE (trial GDS out/MCU_DP.g1e4.gds2, no saveDesign)"
exit
