# G1 endgame PASS 1 (2026-07-23) — MCU_DP DRC endgame, additive-only stage.
# Re-baseline (Jul-23, re-streamed GDS): blockdrc 251 = 70 density/DRM (waived
# set) + tile M2.S.1 (user-waived) + real work: M2.A.1 x159 + M4.A.1 x3
# (minarea pass here), M7.S.4 x2 (merged here, marker-derived rects),
# M2.S.1@1013.8 + M2.S.2 x3 + M2.S.2.1 + M4.S.1 x4 + G.4:M2i x6 + DM2.S.2
# (INSPECTION DUMPS here -> hand-authored pass-2 fixes).
# ADDITIVE ONLY: no rips, no ecoRoute -> timing/netlist untouched.
# TRIAL=1 (default): streamOut out/MCU_DP.g1e1.gds2, NO saveDesign.
#
# Run: cd ~/vestarv/innovus/common/MCU_DP && innovus -no_gui -batch \
#        -log log/mcu_dp_g1e1 -files ../../../signoff_mp/tcl/mcu_dp_g1_endgame1.tcl

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
proc __fatal {msg} { puts "G1E1 FATAL: $msg"; exit 1 }
foreach {__ni0 __ns0 __nw0} [__counts] {}
puts "G1E1 COUNTS baseline: insts=$__ni0 sWires=$__ns0 wires=$__nw0"
if {$__ni0 != 182364} { __fatal "instCount != 182364 canonical" }
set __fatals 0

# ---------------- min-area pass (PG4 mcu_onesie_patch.tcl logic) ------------
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
		if {$__net eq ""} { incr __nskip; puts "G1E1 minarea($tag): NO wire under $__lay ($__x0 $__y0 $__x1 $__y1) — skipped"; continue }
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
		if {!$__done} { incr __nfail; puts "G1E1 minarea($tag): BLOCKED both directions at $__lay ($__x0 $__y0 $__x1 $__y1) net=$__net" }
	}
	close $__fp
	puts "### G1E1 ### minarea $tag — $__npatch patched, $__nskip skipped, $__nfail blocked"
	if {$__nfail > 0} { incr __fatals }
}
__minarea_pass /home/mseminario2/vestarv/signoff_mp/minarea_sites_dp2.txt main

# ---------------- clearance-checked same-net merge (PG4 __mrg) --------------
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
			puts "G1E1 FATAL: $tag foreign $lay net=[dbGet -e $o.net.name] at $ob blocks rect $rect"
			incr __fatals
			return
		}
	}
	add_shape -net $net -layer $lay -rect $rect -shape STRIPE -status ROUTED
	puts "G1E1: $tag merged rect $rect on $net/$lay"
}
# net resolver: majority same-layer net in a window (wires + sWires)
proc __netat {lay win} {
	foreach o [concat [dbQuery -area $win -objType sWire] [dbQuery -area $win -objType wire]] {
		if {[dbGet -e $o.layer.name] ne $lay} { continue }
		set n [lindex [dbGet -e $o.net.name] 0]
		if {$n ne ""} { return $n }
	}
	return ""
}

# M7.S.4 x2 — same sites as PG4 MCU_MP (pad-group-to-stripe gaps at ROM);
# marker-derived rects, net resolved at runtime, clearance-checked.
set __n7a [__netat M7 {208.0 459.0 209.2 464.0}]
if {$__n7a eq ""} { __fatal "M7.S.4@208: no M7 net found" }
__mrg "M7.S.4@208" $__n7a M7 {208.0 459.0 209.2 464.0}
set __n7b [__netat M7 {248.85 450.0 250.2 455.0}]
if {$__n7b eq ""} { __fatal "M7.S.4@249: no M7 net found" }
__mrg "M7.S.4@249" $__n7b M7 {248.85 450.0 250.2 455.0}

# ---------------- inspection dumps for pass-2 sites -------------------------
proc __dump {tag win} {
	puts "G1E1 DUMP $tag win=$win"
	foreach kind {wire sWire via} {
		foreach o [dbQuery -area $win -objType $kind] {
			set lay ""
			if {$kind eq "via"} {
				set lay "[dbGet -e $o.via.botLayer.name]->[dbGet -e $o.via.topLayer.name] via=[dbGet -e $o.via.name]"
			} else {
				set lay [dbGet -e $o.layer.name]
			}
			puts "G1E1 DUMP $tag $kind lay=$lay net=[dbGet -e $o.net.name] status=[dbGet -e $o.status] box=[dbGet -e $o.box]"
		}
	}
	puts "G1E1 DUMP $tag END"
}
__dump "M2.S.1@1013"   {1013.3 482.0 1014.4 483.0}
__dump "M2.S.2@1168"   {1168.2 13.4 1169.3 15.4}
__dump "M2.S.2@1392"   {1391.9 495.4 1393.0 496.8}
__dump "M2.S.2@2192"   {2191.7 53.4 2192.8 54.8}
__dump "M2.S.2.1@1386" {1386.4 545.5 1387.6 547.0}
__dump "M4.S.1@679"    {679.0 648.4 680.5 649.7}
__dump "M4.S.1@1342"   {1342.0 648.4 1343.5 649.7}
__dump "M4.S.1@1346"   {1345.5 648.4 1347.0 649.7}
__dump "M4.S.1@2009"   {2008.5 648.4 2010.0 649.7}
__dump "G.4@1006"      {1006.3 484.1 1007.2 485.0}
__dump "G.4@1049"      {1049.1 484.2 1050.0 485.2}
__dump "DM2.S.2@881"   {880.9 480.3 882.4 481.5}

# ---------------- guards + trial streamOut ----------------------------------
if {$__fatals > 0} { __fatal "$__fatals merge/minarea fatals — NO streamOut" }
foreach {__ni1 __ns1 __nw1} [__counts] {}
puts "G1E1 COUNTS post-patch: insts=$__ni1 sWires=$__ns1 wires=$__nw1"
if {$__ni1 != $__ni0} { __fatal "inst count changed" }
if {$__nw1 != $__nw0} { __fatal "regular wire count changed (additive pass must not)" }
# add_shape STRIPE creates sWires — expect +patched count, bounded
if {[expr {$__ns1 - $__ns0}] > 200} { __fatal "sWire growth implausible ($__ns0 -> $__ns1)" }

streamOut \
	$OUTPUT_DIR/MCU_DP.g1e1.gds2 \
	-libName WorkLib \
	-structureName MCU \
	-stripes 1 \
	-units 1000 \
	-mode ALL \
	-merge [list $OUTPUT_DIR/hart_tile.gds2] \
	-mapFile ../shared/innovus2gds.map
puts "G1E1: COMPLETE (trial GDS out/MCU_DP.g1e1.gds2, no saveDesign)"
exit
