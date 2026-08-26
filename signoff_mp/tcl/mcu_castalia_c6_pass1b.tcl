# C6 endgame PASS 1b (2026-07-29) — MCU_castalia chipdrc 1966 -> density-only.
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
#   - Count guards; trial streamOut out/MCU_castalia.c6e1b.gds2; NO saveDesign.
#
# Run: cd ~/vestarv/innovus/common/MCU_castalia && innovus -no_gui -batch \
#        -log log/mcu_castalia_c6e1b \
#        -files /home/mseminario2/vestarv/signoff_mp/tcl/mcu_castalia_c6_pass1b.tcl

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
proc __fatal {msg} { puts "C6E1 FATAL: $msg"; exit 1 }
foreach {__ni0 __ns0 __nw0} [__counts] {}
puts "C6E1 COUNTS baseline: insts=$__ni0 sWires=$__ns0 wires=$__nw0"
if {$__ni0 < 500000} { __fatal "instCount $__ni0 implausibly low — defIn broken" }
if {$__ns0 == 0 || $__nw0 == 0} { __fatal "sWires/wires zero at baseline" }
set __rblk0 [llength [dbGet -e top.fPlan.rBlkgs]]
puts "C6E1 route blockages carried by DEF: $__rblk0 (expect seal-ring only)"

# Per-(net,layer) sWire area snapshot — the classify-don't-count guard.
proc __swire_snapshot {} {
	set d [dict create]
	foreach s [dbGet -e top.nets.sWires] {
		set net [lindex [dbGet -e $s.net.name] 0]
		set lay [dbGet -e $s.layer.name]
		set box [lindex [dbGet -e $s.box] 0]
		if {$net eq "" || $lay eq "" || [llength $box] != 4} { continue }
		foreach {x0 y0 x1 y1} $box {}
		set a [expr {($x1 - $x0) * ($y1 - $y0)}]
		set k "$net|$lay"
		if {[dict exists $d $k]} {
			lassign [dict get $d $k] c aa
			dict set d $k [list [expr {$c + 1}] [expr {$aa + $a}]]
		} else {
			dict set d $k [list 1 $a]
		}
	}
	return $d
}

# ---------------- hold PRE (defIn view = authority) -------------------------
catch { setAnalysisMode -analysisType onChipVariation -cppr both }
timeDesign -postRoute -hold -outDir $REPORT_DIR/MCU_castalia.c6e1b.hold_pre
set __sw_pre [__swire_snapshot]
puts "C6E1 sWire snapshot PRE: [dict size $__sw_pre] (net,layer) pairs"

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
puts "C6E1: routing-era blockades re-declared (M7/M8 blankets + 4 windows)"

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
puts "C6E1: cut route blockages created (M3 x2, M5 x1)"

if {[catch {ecoRoute -fix_drc} r]} { puts "C6E1 WARN: ecoRoute -fix_drc: $r" }
puts "C6E1: ecoRoute -fix_drc done"

# Remove the three cut blockages + the window blocks (flow parity before any
# verify/streamOut); keep the M7/M8 blankets until after streamOut — they were
# design-frame keep-outs during routing and affect nothing downstream here.
foreach b {c6_m3_1 c6_m3_2 c6_m5_1 c6_win_rt0 c6_win_rt1 c6_win_rt2 c6_win_rt3} {
	catch {deleteRouteBlk -name $b}
}

# ---------------- hold POST + count guards ----------------------------------
timeDesign -postRoute -hold -outDir $REPORT_DIR/MCU_castalia.c6e1b.hold_post

foreach {__ni1 __ns1 __nw1} [__counts] {}
puts "C6E1 COUNTS post-eco: insts=$__ni1 sWires=$__ns1 wires=$__nw1 (base $__ni0/$__ns0/$__nw0)"
if {$__ni1 != $__ni0} { __fatal "inst count changed ($__ni0 -> $__ni1) — diode/cell insertion happened" }
if {abs($__nw1 - $__nw0) > 5000} { __fatal "wire delta implausible ($__nw0 -> $__nw1)" }

# sWire classifier (replaces the count guard — see 1b header).
set __sw_post [__swire_snapshot]
puts "C6E1 sWire snapshot POST: [dict size $__sw_post] pairs (was [dict size $__sw_pre])"
set __pgpre 0.0; set __pgpost 0.0
dict for {k v} $__sw_pre {
	lassign [split $k |] n l
	if {$n eq "VDD" || $n eq "VSS"} { set __pgpre [expr {$__pgpre + [lindex $v 1]}] }
}
dict for {k v} $__sw_post {
	lassign [split $k |] n l
	if {$n eq "VDD" || $n eq "VSS"} { set __pgpost [expr {$__pgpost + [lindex $v 1]}] }
}
puts [format "C6E1 PG (VDD+VSS) sWire area: pre=%.1f post=%.1f um^2 (drift %.4f%%)" \
	$__pgpre $__pgpost [expr {$__pgpre > 0 ? 100.0*($__pgpost-$__pgpre)/$__pgpre : 999}]]
if {$__pgpre <= 0} { __fatal "PG sWire area pre-snapshot is zero — snapshot broken" }
if {abs($__pgpost - $__pgpre) > 0.005 * $__pgpre} { __fatal "VDD/VSS total sWire area drifted >0.5%" }
set __nshr 0
dict for {k v} $__sw_pre {
	lassign $v c0 a0
	if {[dict exists $__sw_post $k]} { lassign [dict get $__sw_post $k] c1 a1 } else { set c1 0; set a1 0.0 }
	set __shr [expr {$a0 - $a1}]
	if {$__shr > 5.0 && $__shr > 0.01 * $a0} {
		puts [format "C6E1 SHRINK %s: area %.2f -> %.2f (count %d -> %d)" $k $a0 $a1 $c0 $c1]
		incr __nshr
	}
}
dict for {k v} $__sw_post {
	if {[dict exists $__sw_pre $k]} { continue }
	lassign [split $k |] n l
	lassign $v c1 a1
	puts [format "C6E1 NEWPAIR %s: count=%d area=%.2f" $k $c1 $a1]
	if {($l eq "M7" || $l eq "M8") && $a1 > 5.0} { incr __nshr }
}
if {$__nshr > 0} { __fatal "$__nshr sWire classifier violations (shrink / new M7-M8 pair) — see SHRINK/NEWPAIR lines" }
puts "C6E1: sWire classifier PASS (area-conserving; count fragmentation logged only)"

# ---------------- inspection dumps (pass-2 inputs) --------------------------
proc __dump {tag win} {
	puts "C6E1 DUMP $tag win=$win"
	foreach kind {wire sWire via} {
		foreach o [dbQuery -area $win -objType $kind] {
			set lay ""
			if {$kind eq "via"} {
				set lay "[dbGet -e $o.via.botLayer.name]->[dbGet -e $o.via.topLayer.name] via=[dbGet -e $o.via.name]"
			} else {
				set lay [dbGet -e $o.layer.name]
			}
			puts "C6E1 DUMP $tag $kind lay=$lay net=[dbGet -e $o.net.name] status=[dbGet -e $o.status] box=[dbGet -e $o.box]"
		}
	}
	puts "C6E1 DUMP $tag END"
}
# M7.S.3/S.4 ROM-band slivers (x 158-215, y 1244-1259)
__dump "M7@158"      {157.3 1243.0 160.5 1251.0}
__dump "M7@164"      {162.9 1243.0 166.5 1251.0}
__dump "M7@167"      {165.7 1252.0 169.5 1260.0}
__dump "M7@173"      {171.5 1252.0 174.9 1260.0}
__dump "M7@208"      {206.6 1243.0 210.5 1251.0}
__dump "M7@214"      {212.5 1243.0 215.8 1251.0}
# M6.S.3 / M5.S.3 (west edge + ROM band)
__dump "M56@4"       {2.5 1547.0 15.5 1550.5}
__dump "M6@165"      {164.0 1254.0 167.2 1260.0}
# M4.S.1 tile seams
__dump "M4S1@679"    {678.6 1638.0 680.9 1640.1}
__dump "M4S1@2010a"  {2009.1 1049.9 2011.4 1052.0}
__dump "M4S1@2010b"  {2009.1 1638.0 2011.4 1640.1}
# M2.S.* onesies
__dump "M2S1@633"    {632.9 784.8 633.9 786.2}
__dump "M2S2@708"    {707.5 1023.4 708.6 1026.2}
__dump "M2S2@1297"   {1297.0 1725.0 1298.1 1726.6}
__dump "M2S2@1320"   {1319.5 936.6 1320.6 938.6}
__dump "M2S2@1645"   {1644.5 1680.6 1645.6 1682.6}
__dump "M2S21@1148"  {1148.2 851.4 1149.4 852.8}
# VIA7 weld classes
__dump "VIA7W1@621"  {620.0 1642.2 622.5 1644.7}
__dump "VIA7W1@2214" {2213.0 1045.3 2215.4 1047.8}
__dump "VIA7S@221"   {220.0 1045.3 223.0 1048.0}
__dump "VIA7S@613"   {612.6 1646.0 615.2 1649.8}
# VIA4.R.4:M5 MINCUT pair (shbank1 left edge)
__dump "VIA4R4@845"  {844.6 1395.5 846.7 1398.4}
# DM2.S.2 (report-only class — record geometry)
__dump "DM2@942"     {942.0 1076.3 943.7 1077.5}
__dump "DM2@1084"    {1084.2 1076.3 1085.8 1077.5}

# ---------------- trial streamOut -------------------------------------------
streamOut \
	$OUTPUT_DIR/MCU_castalia.c6e1b.gds2 \
	-libName WorkLib \
	-structureName MCU_castalia \
	-stripes 1 \
	-units 1000 \
	-mode ALL \
	-merge [list ../hart_tile/out/hart_tile.gds2 $IO_PAD_GDS] \
	-mapFile ../shared/innovus2gds.map
puts "C6E1: COMPLETE (trial GDS out/MCU_castalia.c6e1b.gds2, no saveDesign)"
exit
