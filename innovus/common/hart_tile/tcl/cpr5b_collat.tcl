################################################################################
# CPR5b -- SIGNOFF + FULL COLLATERAL from the REPAIRED cut (ONE CUT RULE).
#
# Restores dbs/hart_tile.cpr5b.eco.innovus.dat (the G0-class repair, see
# tcl/cpr5b_eco.tcl) and re-emits EVERY downstream artefact from that one state:
# reports, DBs (signoff + final), GDS, SDF, xsim.v, ILM, LEF, both ETMs.
# This is the M19c failure mode's antidote: M19c's out/ carried a Jul-21
# LEF/xsim.v beside a Jul-22 repaired GDS/SDF.
#
# The pre-repair CPR5a artefacts are archived OUTSIDE this script (dbs/*.cpr5a.*
# and out.cpr5a/) before it runs.
################################################################################
source ../shared/constants.tcl
source ../shared/procedures.tcl
set DESIGN_NAME hart_tile

tic
restoreDesign dbs/hart_tile.cpr5b.eco.innovus.dat $DESIGN_NAME

################################################################################
# Count guards against the ECO run's own measured numbers
################################################################################
set N_I [llength [dbGet -e top.insts]]
set N_N [llength [dbGet -e top.nets]]
set N_W [llength [dbGet -e top.nets.wires]]
set N_S [llength [dbGet -e top.sNets.sWires]]
puts "### CPR5B COLLAT COUNTS ### insts=$N_I nets=$N_N wires=$N_W sWires=$N_S"
if {$N_I != 74887 || $N_N != 20796 || $N_W != 253837 || $N_S != 36109} {
	puts "FATAL (CPR5b collat): restored DB is not the ECO cut (expected 74887/20796/253837/36109)"
	exit 1
}

################################################################################
# PG1 acceptance gate (the ECO touched a SLEEP-chain net)
################################################################################
printStatus "PG1 acceptance gate"
set pg1_bad 0
foreach np [concat [dbGet -p top.nets.name psoPSI_* -e] [dbGet -p top.nets.name *_pg1rep -e] [dbGet -p top.nets.name pd_sleep -e]] {
	foreach it [dbGet $np.instTerms -e] {
		set c [dbGet $it.inst.cell.name]
		if {![string match HEADBUF* $c] && ![string match GPGBUF* $c]} {
			incr pg1_bad
			puts "PG1 VIOLATION: foreign cell [dbGet $it.name] ($c) on chain net [dbGet $np.name]"
		}
	}
	if {![dbGet $np.dontTouch]} {
		incr pg1_bad
		puts "PG1 VIOLATION: chain net [dbGet $np.name] lost its dontTouch"
	}
}
foreach {pin port} {PGEN tcm_pgen RETN tcm_retn} {
	set np [dbGet -p top.insts.name ram0]
	set it [dbGet -p $np.instTerms.name ram0/$pin]
	set nn [dbGet $it.net.name]
	if {$nn ne $port} {
		incr pg1_bad
		puts "PG1 VIOLATION: ram0/$pin is driven by net '$nn', expected the AO port net '$port'"
	}
}
if {$pg1_bad > 0} {
	puts "FATAL (PG1): $pg1_bad power-gating acceptance violations — aborting before signoff"
	exit 1
}
puts "### UNL STATUS ### : PG1 acceptance gate PASSED (chain pure, ram0 PG pins port-driven)"

################################################################################
# Signoff checks + reports (the flow's own block, verbatim)
################################################################################
printStatus "verifyConnectivity"
verifyConnectivity \
    -error 100000 \
    -connectPadSpecialPorts \
    -report $REPORT_DIR/$DESIGN_NAME.verifyConnectivity.signoff.rpt

printStatus "verifyGeometry"
verifyGeometry \
    -antenna \
    -error 100000 \
    -warning 100000 \
    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt

proc cpr5_vg_acceptance {rptfile} {
	set cells 0; set samenet 0; set wiring 0; set short 0; set overlap 0
	if {![file exists $rptfile]} {
		puts "### UNL STATUS ### : G0 ACCEPTANCE — report $rptfile missing, cannot judge"
		return
	}
	set fh [open $rptfile r]
	while {[gets $fh line] >= 0} {
		if {[regexp {^\s*Cells\s*:\s*(\d+)}   $line -> v]} { set cells   $v }
		if {[regexp {^\s*SameNet\s*:\s*(\d+)} $line -> v]} { set samenet $v }
		if {[regexp {^\s*Wiring\s*:\s*(\d+)}  $line -> v]} { set wiring  $v }
		if {[regexp {^\s*Short\s*:\s*(\d+)}   $line -> v]} { set short   $v }
		if {[regexp {^\s*Overlap\s*:\s*(\d+)} $line -> v]} { set overlap $v }
	}
	close $fh
	set tot [expr {$cells + $samenet + $wiring + $short + $overlap}]
	puts "### UNL STATUS ### : G0 ACCEPTANCE — verifyGeometry NON-ANTENNA: Cells=$cells SameNet=$samenet Wiring=$wiring Short=$short Overlap=$overlap (total $tot)"
	if {$tot > 0} {
		puts "### G0-CLASS RESIDUAL PRESENT: $tot non-antenna verifyGeometry violations. ###"
	} else {
		puts "### G0 ACCEPTANCE GREEN: 0 non-antenna verifyGeometry violations. ###"
	}
}
cpr5_vg_acceptance $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt

printStatus "verifyProcessAntenna"
verifyProcessAntenna \
    -report $REPORT_DIR/$DESIGN_NAME.verifyProcessAntenna.signoff.rpt

setDelayCalMode -SIAware false
setAnalysisMode -analysisType onChipVariation -cppr both
printStatus "timeDesign signoff"
timeDesign \
    -si \
    -signoff \
    -outdir $REPORT_DIR/$DESIGN_NAME.timeDesign.signoff.rpt

report_clock_timing \
    -type skew \
    -nworst 10 > $REPORT_DIR/$DESIGN_NAME.report_clock_timing.skew.signoff.rpt

setAnalysisMode -checkType hold -skew true
report_timing > $REPORT_DIR/$DESIGN_NAME.report_timing.hold.signoff.rpt
setAnalysisMode -checkType setup -skew true
report_timing > $REPORT_DIR/$DESIGN_NAME.report_timing.setup.signoff.rpt

reportGateCount \
    -level 2 \
    -outfile $REPORT_DIR/$DESIGN_NAME.reportGateCount.signoff.rpt
summaryReport \
    -noHtml \
    -outfile $REPORT_DIR/$DESIGN_NAME.summaryReport.signoff.rpt

saveDesign $DATABASE_DIR/$DESIGN_NAME.signoff.innovus -def -netlist -rc -tcon

################################################################################
# Output files: GDS, SDF, sim netlist, ILM, LEF abstract, per-corner ETMs
################################################################################
streamOut \
    $OUTPUT_DIR/$DESIGN_NAME.gds2 \
    -libName WorkLib \
    -structureName $DESIGN_NAME \
    -stripes 1 \
    -units 1000 \
    -mode ALL \
    -mapFile ../shared/innovus2gds.map

printStatus "Writing SDF file"
write_sdf $OUTPUT_DIR/$DESIGN_NAME.sdf

printStatus "Writing verilog for Xcelium"
saveNetlist \
    $OUTPUT_DIR/$DESIGN_NAME.xsim.v \
    -excludeCellInst ANTENNA2A10TH

printStatus "Writing ILM"
createInterfaceLogic \
    -hold \
    -dir $OUTPUT_DIR/$DESIGN_NAME.ilm

printStatus "Writing LEF abstract"
lefOut \
    -StripePin \
    -PGpinLayers 7 8 \
    -specifyTopLayer 8 \
    $OUTPUT_DIR/$DESIGN_NAME.lef

printStatus "Extracting per-corner ETMs (both-views-active recipe)"
set_analysis_view -setup [list setup_analysis_view] -hold [list setup_analysis_view]
# -view is REQUIRED in MMMC (TAMODEL-313 otherwise, and innovus only PRINTS the
# error without throwing, so a missing -view fails SILENTLY).
if {[catch {do_extract_model -view setup_analysis_view $OUTPUT_DIR/$DESIGN_NAME.etm_ss.lib} etm_err]} {
	puts "ETM ss extraction FAILED: $etm_err"
} else {
	puts "ETM written to $OUTPUT_DIR/$DESIGN_NAME.etm_ss.lib"
}
set_analysis_view -setup [list hold_analysis_view] -hold [list hold_analysis_view]
if {[catch {do_extract_model -view hold_analysis_view $OUTPUT_DIR/$DESIGN_NAME.etm_ff.lib} etm_err]} {
	puts "ETM ff extraction FAILED: $etm_err"
} else {
	puts "ETM written to $OUTPUT_DIR/$DESIGN_NAME.etm_ff.lib"
}
set_analysis_view -setup [list setup_analysis_view] -hold [list hold_analysis_view]

saveDesign $DATABASE_DIR/$DESIGN_NAME.final.innovus -def -netlist -rc -tcon
toc
printStatus "CPR5b collateral complete"
exit
