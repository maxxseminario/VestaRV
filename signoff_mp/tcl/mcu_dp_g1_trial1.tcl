# G1 trial-1 (2026-07-23): VEHICLE PROBE for the MCU_DP DRC endgame.
# Question (stage_g1_kickoff.md §4.2): does the A7 fresh-init+defIn context
# support the PG4 endgame edit set (editSelect/editDelete -selected/ecoRoute)
# AND timing (hold re-close check), identically to an in-flow session?
#
# Probes, in order (NO saveDesign — trial GDS only):
#   1. baseline count guards (insts/sWires/wires) after init+defIn+gnc
#   2. extractRC + report_timing hold/setup (flow signoff baselines:
#      hold +0.010 / setup +4.966 from rpt/MCU_DP.report_timing.*.signoff.rpt)
#   3. rip ONE net: the M2.S.2 site @ (1168.70,13.91)-(1168.80,14.90) —
#      editSelect + editDelete -selected ONLY (G0: bare editDelete = the world)
#   4. count guards: sWires/insts EXACT, wires strictly decreased
#   5. ecoRoute; count guards again (wires within +/-2000 of baseline)
#   6. re-time hold; streamOut out/MCU_DP.g1trial1.gds2 (flow args, -merge tile)
# Shell-side after: grep IMPSYT-6692 + the COMPLETE marker; GDS struct census
# vs canonical; make drc LAYOUT=trial GDS -> M2.S.2 p1 must be GONE, no new
# real classes.
#
# Run: cd ~/vestarv/innovus/common/MCU_DP && innovus -no_gui -batch \
#        -log log/mcu_dp_g1trial1 -files ../../../signoff_mp/tcl/mcu_dp_g1_trial1.tcl

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
proc __fatal {msg} {
	puts "G1TRIAL FATAL: $msg"
	exit 1
}

foreach {__ni0 __ns0 __nw0} [__counts] {}
puts "G1TRIAL COUNTS baseline: insts=$__ni0 sWires=$__ns0 wires=$__nw0"
if {$__nw0 == 0} { __fatal "wire count query returned 0 at baseline — guard basis invalid" }
if {$__ns0 == 0} { __fatal "sWire count query returned 0 at baseline — guard basis invalid" }

# ---- probe 2: timing under defIn ------------------------------------------
setExtractRCMode -engine postRoute
if {[catch {extractRC} __err]} { puts "G1TRIAL TIMING: extractRC ERROR: $__err" }
setDelayCalMode -SIAware false
setAnalysisMode -analysisType onChipVariation -cppr both
setAnalysisMode -checkType hold -skew true
report_timing > rpt/MCU_DP.g1trial1.hold_pre.rpt
setAnalysisMode -checkType setup -skew true
report_timing > rpt/MCU_DP.g1trial1.setup_pre.rpt
puts "G1TRIAL TIMING: pre-edit hold/setup reports written"

# ---- probe 3: rip the M2.S.2 p1 net ---------------------------------------
set __win {1168.5 13.7 1169.0 15.1}
set __net ""
foreach __o [dbQuery -area $__win -objType wire] {
	if {[dbGet -e $__o.layer.name] ne "M2"} { continue }
	set __n [lindex [dbGet -e $__o.net.name] 0]
	if {$__n ne "" && $__n ne "VDD" && $__n ne "VSS"} { set __net $__n; break }
}
if {$__net eq ""} { __fatal "no M2 signal wire found in M2.S.2 p1 window" }
puts "G1TRIAL RIP: net = $__net"
deselectAll
# escaped-glob select (G0 idiom — bracket names glob otherwise)
set __netEsc [string map {\[ \\\[ \] \\\]} $__net]
editSelect -net $__netEsc
set __nsel [llength [dbGet -e selected]]
puts "G1TRIAL RIP: selected objects = $__nsel"
if {$__nsel == 0} { __fatal "editSelect selected nothing for net $__net" }
editDelete -selected
deselectAll

foreach {__ni1 __ns1 __nw1} [__counts] {}
puts "G1TRIAL COUNTS post-rip: insts=$__ni1 sWires=$__ns1 wires=$__nw1"
if {$__ni1 != $__ni0} { __fatal "inst count changed on rip ($__ni0 -> $__ni1)" }
if {$__ns1 != $__ns0} { __fatal "sWire count changed on rip ($__ns0 -> $__ns1) — THE editDelete trap" }
if {$__nw1 >= $__nw0} { __fatal "wire count did not decrease on rip ($__nw0 -> $__nw1)" }
if {[expr {$__nw0 - $__nw1}] > 2000} { __fatal "rip deleted too much ($__nw0 -> $__nw1)" }

# ---- probe 5: ecoRoute ----------------------------------------------------
ecoRoute
foreach {__ni2 __ns2 __nw2} [__counts] {}
puts "G1TRIAL COUNTS post-ecoRoute: insts=$__ni2 sWires=$__ns2 wires=$__nw2"
if {$__ni2 != $__ni0} { __fatal "inst count changed on ecoRoute ($__ni0 -> $__ni2)" }
if {$__ns2 != $__ns0} { __fatal "sWire count changed on ecoRoute ($__ns0 -> $__ns2)" }
if {[expr {abs($__nw2 - $__nw0)}] > 2000} { __fatal "wire count diverged after ecoRoute ($__nw0 -> $__nw2)" }

# ---- probe 6: re-time + streamOut -----------------------------------------
setAnalysisMode -checkType hold -skew true
report_timing > rpt/MCU_DP.g1trial1.hold_post.rpt
puts "G1TRIAL TIMING: post-ecoRoute hold report written"

streamOut \
	$OUTPUT_DIR/MCU_DP.g1trial1.gds2 \
	-libName WorkLib \
	-structureName MCU \
	-stripes 1 \
	-units 1000 \
	-mode ALL \
	-merge [list $OUTPUT_DIR/hart_tile.gds2] \
	-mapFile ../shared/innovus2gds.map

puts "G1TRIAL: COMPLETE (no saveDesign — trial GDS out/MCU_DP.g1trial1.gds2)"
exit
