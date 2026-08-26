# C6 endgame PASS 1 (2026-07-29) — MCU_castalia chipdrc 1966 -> density-only.
# ECOROUTE-FIRST pass (G1 pass-4 lesson: additive merges must come AFTER any
# ecoRoute, so the rip/reroute stage runs FIRST, additive patches in pass 2).
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
#   - Count guards; trial streamOut out/MCU_castalia.c6e1.gds2; NO saveDesign.
#
# Run: cd ~/vestarv/innovus/common/MCU_castalia && innovus -no_gui -batch \
#        -log log/mcu_castalia_c6e1 \
#        -files /home/mseminario2/vestarv/signoff_mp/tcl/mcu_castalia_c6_pass1.tcl

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

# ---------------- hold PRE (defIn view = authority) -------------------------
catch { setAnalysisMode -analysisType onChipVariation -cppr both }
timeDesign -postRoute -hold -outDir $REPORT_DIR/MCU_castalia.c6e1.hold_pre

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
timeDesign -postRoute -hold -outDir $REPORT_DIR/MCU_castalia.c6e1.hold_post

foreach {__ni1 __ns1 __nw1} [__counts] {}
puts "C6E1 COUNTS post-eco: insts=$__ni1 sWires=$__ns1 wires=$__nw1 (base $__ni0/$__ns0/$__nw0)"
if {$__ni1 != $__ni0} { __fatal "inst count changed ($__ni0 -> $__ni1) — diode/cell insertion happened" }
if {$__ns1 != $__ns0} { __fatal "sWire count changed ($__ns0 -> $__ns1) — ecoRoute touched PG" }
if {abs($__nw1 - $__nw0) > 5000} { __fatal "wire delta implausible ($__nw0 -> $__nw1)" }

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
	$OUTPUT_DIR/MCU_castalia.c6e1.gds2 \
	-libName WorkLib \
	-structureName MCU_castalia \
	-stripes 1 \
	-units 1000 \
	-mode ALL \
	-merge [list ../hart_tile/out/hart_tile.gds2 $IO_PAD_GDS] \
	-mapFile ../shared/innovus2gds.map
puts "C6E1: COMPLETE (trial GDS out/MCU_castalia.c6e1.gds2, no saveDesign)"
exit
