# G1 trial-1d (2026-07-23): defIn timing-fidelity (TQuantus postRoute) + shield-aware guard probe.
# Trial-1b proved: init+defIn (182,364 insts exact), editSelect/editDelete
# -selected rip clean, ecoRoute runs. Open questions this pass answers:
#   A. Does timeDesign -si -signoff under defIn REPRODUCE the flow's signoff
#      numbers (hold +0.010 / setup +4.966)? (1b's plain extractRC+report_timing
#      read hold -0.006 / setup +4.777 — extraction-engine delta, not signal.)
#   B. Are ecoRoute's +52 sWires ALL shield re-creations (G0 precedent), i.e.
#      status==Shield (or shape SHIELD) on VSS/VDD? FATAL otherwise.
#   C. What does ecoRoute touch globally (violations before/after)?
# NO saveDesign, NO streamOut (streamOut proven by the G0 A7 re-stream).
#
# Run: cd ~/vestarv/innovus/common/MCU_DP && innovus -no_gui -batch \
#        -log log/mcu_dp_g1trial1d -files ../../../signoff_mp/tcl/mcu_dp_g1_trial1d.tcl

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

# ---- probe A: flow-class postRoute timing (default TQuantus; the flow's own
# "signoff" Quantus run NEVER worked -- EXTGRMP-341 qrc segfault on Jul 21 too,
# so the flow numbers ARE post-optDesign TQuantus state; this matches it) -----
setDelayCalMode -SIAware false
setAnalysisMode -analysisType onChipVariation -cppr both
timeDesign -postRoute -hold -outdir rpt/MCU_DP.g1trial1d.timeDesign.hold_pre
timeDesign -postRoute -outdir rpt/MCU_DP.g1trial1d.timeDesign.setup_pre
setAnalysisMode -checkType hold -skew true
report_timing > rpt/MCU_DP.g1trial1d.hold_pre.rpt
setAnalysisMode -checkType setup -skew true
report_timing > rpt/MCU_DP.g1trial1d.setup_pre.rpt
puts "G1TRIAL TIMING: postRoute-recipe pre-edit reports written"

# ---- probe C baseline: violation state before edits -----------------------
set __drc0 [catch {verify_drc -limit 100000} __drc0msg]
puts "G1TRIAL DRC-PRE: $__drc0msg"

# ---- baseline sWire pointer set (for shield-aware delta) -------------------
set __sw0 [dict create]
foreach __p [dbGet -e top.nets.sWires] { dict set __sw0 $__p 1 }

# ---- rip the same M2.S.2 p1 net + ecoRoute --------------------------------
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
set __netEsc [string map {\[ \\\[ \] \\\]} $__net]
editSelect -net $__netEsc
set __nsel [llength [dbGet -e selected]]
if {$__nsel == 0} { __fatal "editSelect selected nothing for net $__net" }
editDelete -selected
deselectAll
foreach {__ni1 __ns1 __nw1} [__counts] {}
puts "G1TRIAL COUNTS post-rip: insts=$__ni1 sWires=$__ns1 wires=$__nw1"
if {$__ni1 != $__ni0} { __fatal "inst count changed on rip" }
if {$__ns1 != $__ns0} { __fatal "sWire count changed on rip — THE editDelete trap" }
if {$__nw1 >= $__nw0} { __fatal "wire count did not decrease on rip" }

ecoRoute

foreach {__ni2 __ns2 __nw2} [__counts] {}
puts "G1TRIAL COUNTS post-ecoRoute: insts=$__ni2 sWires=$__ns2 wires=$__nw2"
if {$__ni2 != $__ni0} { __fatal "inst count changed on ecoRoute" }
# shield-aware sWire delta: every ADDED sWire must be a shield on VDD/VSS
set __nbad 0; set __nnew 0
foreach __p [dbGet -e top.nets.sWires] {
	if {[dict exists $__sw0 $__p]} { continue }
	incr __nnew
	set __st  [dbGet -e $__p.status]
	set __sh  [dbGet -e $__p.shape]
	set __nn  [lindex [dbGet -e $__p.net.name] 0]
	if {!(($__nn eq "VSS" || $__nn eq "VDD") && \
	      ([string tolower $__st] eq "shield" || [string tolower $__sh] eq "shield"))} {
		incr __nbad
		puts "G1TRIAL SWIRE-NEW NON-SHIELD: net=$__nn status=$__st shape=$__sh box=[dbGet -e $__p.box]"
	}
}
puts "G1TRIAL SWIRE DELTA: new=$__nnew non-shield=$__nbad"
if {$__nbad > 0} { __fatal "ecoRoute added non-shield sWires" }

# ---- probe C post: violation state after ----------------------------------
set __drc1 [catch {verify_drc -limit 100000} __drc1msg]
puts "G1TRIAL DRC-POST: $__drc1msg"

# ---- post-edit hold (fresh TQuantus after reroute) -------------------------
timeDesign -postRoute -hold -outdir rpt/MCU_DP.g1trial1d.timeDesign.hold_post
setAnalysisMode -checkType hold -skew true
report_timing > rpt/MCU_DP.g1trial1d.hold_post.rpt
puts "G1TRIAL TIMING: post-ecoRoute hold report written"
puts "G1TRIAL: COMPLETE (no saveDesign, no streamOut)"
exit
