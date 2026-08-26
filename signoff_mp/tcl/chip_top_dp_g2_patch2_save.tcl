# ARCHIVED ONE-SHOT (2026-07-23): inputs (g2/g2b DB slots) were promoted into
# dbs/chip_top_dp.signoff.innovus and deleted at G3 cleanup — re-derive from the
# signoff slot if this pass ever needs to re-run.
# G2 chip patch pass 2 (2026-07-23): the ONE antenna site (A.R.6__A.R.8 M3/M4/M5
# @ 880.7, 627.3-628.8) — rip + antenna-aware ecoRoute, DIODES OFF.
# RUNS ON THE PATCHED DB (dbs/chip_top_dp.g2.innovus DEF — carries the pass-1 merges).
# chipdrc core residual (fresh interior cut — the G1 assembly fixes do NOT
# propagate): G.4:M2i x4 @ (798.55, 484.61-484.79) = the assembly's 1049
# jog pattern shifted; M2.S.1 @ (1013.805,482.465-482.5) = the assembly's
# exact pair-gap site recreated; M2.S.1 x3 @ y 486.50-486.525 (x 1049.5 /
# 1056.7 / 1063.8) = collinear stub gaps. ALL additive same-net merges (no
# rips, no ecoRoute -> timing/netlist/SDF untouched). Nets resolved at
# runtime; __mrg FATALs on any foreign-net blocker (then this pass iterates).
# NO saveDesign; streamOut trial out/chip_top_dp.g2p1.gds2.
#
# Run: cd ~/vestarv/innovus/common/chip_top_dp && innovus -no_gui -batch \
#        -log log/chip_top_dp_g2p1 -files ../../../signoff_mp/tcl/chip_top_dp_g2_patch2_save.tcl

source ../shared/constants.tcl
source ../shared/procedures.tcl

set IO_PAD_LEF /opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/lef/tphn65gpgv2od3_sl_210a/mt_2/8lm/lef/tphn65gpgv2od3_sl_8lm.lef
set init_verilog   "$OUTPUT_DIR/chip_top_dp.xsim.v"
set init_top_cell  chip_top_dp
set init_pwr_net   VDD
set init_gnd_net   VSS
set init_mmmc_file "$SCRIPT_DIR/viewdefinition_chip_dp.tcl"
set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					$IP_DIR/rom_hvt_pg/rom_hvt_pg.lef \
					$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef \
					$IC_DIR/abstracts/myshkin_abs/GlitchFilter/GlitchFilter.lef \
					$IC_DIR/abstracts/myshkin_abs/PowerOnResetCheng/PowerOnResetCheng.lef \
					$IC_DIR/abstracts/myshkin_abs/OscillatorCurrentStarved/OscillatorCurrentStarved.lef \
					$OUTPUT_DIR/hart_tile.lef \
					$IO_PAD_LEF"
set init_design_uniquify 1
init_design
setDesignMode -process 65 -flowEffort standard -powerEffort low
setMultiCpuUsage -localCpu 4

defIn $DATABASE_DIR/chip_top_dp.g2.innovus.dat/chip_top_dp.def.gz
clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst * -module {} -autoTie -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -module {} -autoTie -verbose

proc __counts {} {
	set ni [llength [dbGet -e top.insts]]
	set ns [llength [dbGet -e top.nets.sWires]]
	set nw [llength [dbGet -e top.nets.wires]]
	return [list $ni $ns $nw]
}
proc __fatal {msg} { puts "G2P2 FATAL: $msg"; exit 1 }
foreach {__ni0 __ns0 __nw0} [__counts] {}
puts "G2P2 COUNTS baseline: insts=$__ni0 sWires=$__ns0 wires=$__nw0"
set __fatals 0

proc __fatal2 {msg} { puts "G2P2 FATAL: $msg"; exit 1 }

# ---- identify the antenna net at (880.7, 627.3-628.8) ---------------------
set __win {880.4 626.9 881.1 629.1}
set __net ""
foreach __lay {M3 M4 M5} {
	foreach __o [dbQuery -area $__win -objType wire] {
		if {[dbGet -e $__o.layer.name] ne $__lay} { continue }
		set __n [lindex [dbGet -e $__o.net.name] 0]
		if {$__n ne "" && $__n ne "VDD" && $__n ne "VSS"} { set __net $__n; break }
	}
	if {$__net ne ""} { break }
}
if {$__net eq ""} { __fatal2 "no signal net found at the antenna site" }
puts "G2P2 ANT NET: $__net"

deselectAll
set __netEsc [string map {\[ \\\[ \] \\\]} $__net]
editSelect -net $__netEsc
set __nsel [llength [dbGet -e selected]]
if {$__nsel == 0} { __fatal2 "editSelect selected nothing for $__net" }
puts "G2P2 RIP: $__net ($__nsel objects)"
editDelete -selected
deselectAll
foreach {__ni1 __ns1 __nw1} [__counts] {}
puts "G2P2 COUNTS post-rip: insts=$__ni1 sWires=$__ns1 wires=$__nw1"
if {$__ni1 != $__ni0} { __fatal2 "inst count changed on rip" }

# flow-parity layer fences over the DIE frame + antenna-aware ecoRoute with
# DIODE INSERTION OFF (no new insts — layer-hop repair only)
createRouteBlk -name g2p2_m7blk -box {-155.5 -650.0 2844.5 2350.0} -layer 7
createRouteBlk -name g2p2_m8blk -box {-155.5 -650.0 2844.5 2350.0} -layer 8
setNanoRouteMode \
	-routeTopRoutingLayer 7 \
	-droutePostRouteSwapVia multiCut \
	-drouteUseMultiCutViaEffort medium \
	-routeAllowPowerGroundPin true \
	-drouteFixAntenna true \
	-routeInsertAntennaDiode false
ecoRoute
deleteRouteBlk -name g2p2_m7blk
deleteRouteBlk -name g2p2_m8blk

foreach {__ni2 __ns2 __nw2} [__counts] {}
puts "G2P2 COUNTS post-ecoRoute: insts=$__ni2 sWires=$__ns2 wires=$__nw2"
if {$__ni2 != $__ni0} { __fatal2 "inst count changed on ecoRoute (diode insertion leaked?)" }
if {[expr {abs($__nw2 - $__nw0)}] > 2000} { __fatal2 "wire count diverged" }

# hold re-check (chip signoff-recipe baseline: +0.007)
setDelayCalMode -SIAware false
setAnalysisMode -analysisType onChipVariation -cppr both
timeDesign -postRoute -hold -outdir rpt/chip_top_dp.g2p2.timeDesign.hold_post

streamOut \
	$OUTPUT_DIR/chip_top_dp.g2p2b.gds2 \
	-libName WorkLib \
	-structureName chip_top_dp \
	-stripes 1 \
	-units 1000 \
	-mode ALL \
	-merge [list $OUTPUT_DIR/hart_tile.gds2 /opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/gds/tphn65gpgv2od3_sl_210a/mt_2/8lm/tphn65gpgv2od3_sl.gds] \
	-mapFile ../shared/innovus2gds.map
saveDesign $DATABASE_DIR/chip_top_dp.g2b.innovus -def -netlist -rc -tcon
write_sdf $OUTPUT_DIR/chip_top_dp.g2b.sdf
puts "G2P2: COMPLETE (g2p2b GDS + DB chip_top_dp.g2b.innovus + SDF chip_top_dp.g2b.sdf)"
exit
