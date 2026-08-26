################################################################################
# TCM11 ECO -- the G0-class M1 merge on the 2026-08-25 hart_tile cut.
#
# THIS IS THE STEP THAT WAS SKIPPED ON 2026-08-17, and skipping it is the direct
# cause of the LVS short that shipped in that cut.  The CPR5 banner in
# hart_tile.innovus.tcl states the rule plainly: the G0 class is a PLACEMENT-
# DEPENDENT route/OBS merge, "ANY re-harden moves the placement and
# re-manufactures the class SOMEWHERE ELSE", so after every re-harden the sites
# must be RE-DERIVED from that cut's own verifyGeometry report and repaired.
#
# cpr5b_eco.tcl is NOT re-pointable here.  It is dated 2026-08-15 and its SITE B
# and SITE C are keyed to genus instance names from a synthesis with 233 fewer
# cells; its own FATAL guards would refuse rather than mis-repair.  This is a
# NEW site list authored from THIS cut.
#
# THE SITE, from rpt/hart_tile.verifyGeometry.signoff.rpt (2026-08-25 05:48):
#
#   SHORT: Regular Via of Net core/csr_rdata[9]
#          & Blockage of Cell core/irq_handler_inst/tie_0_cell6  ( M1 )
#   Bounds : ( 576.820, 65.950 ) ( 576.905, 66.050 )
#
# and Pegasus agrees, which is the point -- this is not a cosmetic marker:
#
#   Layout Net: 2463  | Schematic Net: Xcore/csr_rdata<9>
#            SHORT    | Schematic Net: Xcore/Xirq_handler_inst/Xtie_0_cell6/LO
#
# GEOMETRY.  tie_0_cell6 is TIELOX1MA10TH at box {576.2 65.0 577.0 67.0} R180 --
# the SAME cell at the SAME orientation as the 2026-08-15 site (tie_0_cell7,
# box {351.8 397.0 352.6 399.0} R180).  So the four OBS-shaped blockages that
# repaired that site translate EXACTLY, by (+224.4, -332.0):
#
#   obs4 (the violated rect, already grown by the 0.09 M1.S.1 spacing)
#        351.8-cut {352.325 397.420 352.595 398.490} -> {576.725 65.420 576.995 66.490}
#   obs1 {352.050 397.670 352.140 398.100} -> {576.450 65.670 576.540 66.100}
#   obs2 {352.140 397.670 352.155 397.760} -> {576.540 65.670 576.555 65.760}
#   obs3 {352.155 397.250 352.245 397.760} -> {576.555 65.250 576.645 65.760}
#
# obs4 contains the reported SHORT bounds, which is the arithmetic check that
# the translation is right: 576.725 <= 576.820 and 576.905 <= 576.995;
# 65.420 <= 65.950 and 66.050 <= 66.490.
#
# NOT A BBOX BLOCKAGE.  CPR5b attempt #1 used the cell bbox, which also covers
# the VDD/VSS rails and the tie's own Y pin, and ecoRoute answered with
# Short 23 / Overlap 16.  OBS-shaped only.
################################################################################
set DESIGN_NAME  hart_tile
set REPORT_DIR   rpt
set DATABASE_DIR dbs
set OUTPUT_DIR   out
set TAG          tcm11eco
set NET_A        {core/csr_rdata[9]}

source ../shared/procedures.tcl
proc logPuts {text} { global PUTS_STRING ; $PUTS_STRING $text }

restoreDesign dbs/hart_tile.signoff.innovus.dat $DESIGN_NAME

proc counts {tag} {
	set i [llength [dbGet -e top.insts]]
	set n [llength [dbGet -e top.nets]]
	set w [llength [dbGet -e top.nets.wires]]
	logPuts "### TCM11ECO COUNTS ($tag) ### insts=$i nets=$n wires=$w"
	return [list $i $n $w]
}
set C0 [counts baseline]

# --- GUARD: the site must be what this script was written against -----------
set tp [dbGet -p top.insts.name core/irq_handler_inst/tie_0_cell6 -e]
if {$tp eq "0x0" || $tp eq ""} {
	logPuts "FATAL (TCM11ECO): core/irq_handler_inst/tie_0_cell6 not found -- wrong cut."
	exit 1
}
set tb [lindex [dbGet $tp.box] 0]
set to [dbGet $tp.orient]
logPuts "### TCM11ECO ### tie_0_cell6 box=$tb orient=$to cell=[dbGet $tp.cell.name]"
if {abs([lindex $tb 0] - 576.2) > 0.001 || abs([lindex $tb 1] - 65.0) > 0.001 || $to ne "R180"} {
	logPuts "FATAL (TCM11ECO): tie_0_cell6 is at $tb/$to, not {576.2 65.0 577.0 67.0}/R180 -- the"
	logPuts "                  hardcoded OBS translation would land on the wrong geometry."
	logPuts "                  RE-DERIVE from this cut's verifyGeometry report; do not adjust blindly."
	exit 1
}

# --- RIP the offending net --------------------------------------------------
set np [dbGetNetByName $NET_A]
if {$np eq "" || $np == 0x0} { logPuts "FATAL (TCM11ECO): net $NET_A not found"; exit 1 }
if {[dbGet $np.dontTouch]} { dbSet $np.dontTouch false ; logPuts "### TCM11ECO ### $NET_A dontTouch cleared" }
set before [llength [dbGet -e $np.wires]]
deselectAll
editSelect -net $NET_A
editDelete -selected
deselectAll
set after [llength [dbGet -e $np.wires]]
logPuts "### TCM11ECO RIP ### $NET_A wires $before -> $after"
if {$after >= $before} {
	logPuts "FATAL (TCM11ECO): rip of $NET_A removed no wires ($before -> $after) -- wrong API."
	exit 1
}

# --- OBS-shaped M1+VIA1 blockages ------------------------------------------
set BLKS {
	{tcm11_tie6_obs4 576.725 65.420 576.995 66.490}
	{tcm11_tie6_obs1 576.450 65.670 576.540 66.100}
	{tcm11_tie6_obs2 576.540 65.670 576.555 65.760}
	{tcm11_tie6_obs3 576.555 65.250 576.645 65.760}
}
set nblk 0
foreach b $BLKS {
	foreach {nm x1 y1 x2 y2} $b {break}
	if {[catch {createRouteBlk -name ${nm}_M1 -layer M1 -cutLayer VIA1 -box [list $x1 $y1 $x2 $y2]} err]} {
		logPuts "### TCM11ECO ### createRouteBlk $nm FAILED: $err"
	} else { logPuts "### TCM11ECO BLK ### $nm M1+VIA1 {$x1 $y1 $x2 $y2}" ; incr nblk }
}
if {$nblk != 4} { logPuts "FATAL (TCM11ECO): only $nblk/4 blockages created"; exit 1 }

# --- ecoRoute, BARE ---------------------------------------------------------
ecoRoute
set C1 [counts after_ecoRoute]

foreach b $BLKS {
	foreach {nm x1 y1 x2 y2} $b {break}
	catch { deleteRouteBlk -name ${nm}_M1 }
}
logPuts "### TCM11ECO ### blockages removed"

# --- did it close? ----------------------------------------------------------
verifyGeometry -error 100000 -warning 100000 \
	-report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.$TAG.rpt
verifyConnectivity -error 100000 -connectPadSpecialPorts \
	-report $REPORT_DIR/$DESIGN_NAME.verifyConnectivity.$TAG.rpt

# --- re-emit ALL collateral from THIS cut (the M19c rule) -------------------
# M19c shipped a GDS repaired by an out-of-flow ECO while its LEF and xsim.v
# came from the unrepaired state.  Never again: one cut, every file.
saveDesign $DATABASE_DIR/$DESIGN_NAME.signoff.innovus -def -netlist -rc -tcon
streamOut $OUTPUT_DIR/$DESIGN_NAME.gds2 -libName WorkLib -structureName $DESIGN_NAME \
	-stripes 1 -units 1000 -mode ALL -mapFile ../shared/innovus2gds.map
write_sdf $OUTPUT_DIR/$DESIGN_NAME.sdf
saveNetlist $OUTPUT_DIR/$DESIGN_NAME.xsim.v -excludeCellInst ANTENNA2A10TH
# ANTENNA DATA BEFORE lefOut (2026-08-25).  This ECO used to call lefOut with no
# antenna pass in front of it, so it re-emitted the tile abstract WITHOUT the
# per-pin antenna model the P&R flow's own lefOut carries (ANTENNAGATEAREA 127
# -> 0, same PIN and RECT counts, file 84 KB smaller -- nothing looked wrong).
# The tile is bound as a macro by MCU_hart, which is exactly the consumer that
# needs it.  NB this whole script is SUPERSEDED by the in-flow tcl/g0_repair.tcl
# and tcl/wm_merge.tcl; the line below is here so that running it for forensics
# cannot silently damage out/hart_tile.lef.
verifyProcessAntenna
lefOut -StripePin -PGpinLayers 7 8 -specifyTopLayer 8 $OUTPUT_DIR/$DESIGN_NAME.lef
set_analysis_view -setup [list setup_analysis_view] -hold [list setup_analysis_view]
if {[catch {do_extract_model -view setup_analysis_view $OUTPUT_DIR/$DESIGN_NAME.etm_ss.lib} e]} {
	logPuts "ETM ss FAILED: $e" } else { logPuts "ETM ss written" }
set_analysis_view -setup [list hold_analysis_view] -hold [list hold_analysis_view]
if {[catch {do_extract_model -view hold_analysis_view $OUTPUT_DIR/$DESIGN_NAME.etm_ff.lib} e]} {
	logPuts "ETM ff FAILED: $e" } else { logPuts "ETM ff written" }
set_analysis_view -setup [list setup_analysis_view] -hold [list hold_analysis_view]
saveDesign $DATABASE_DIR/$DESIGN_NAME.final.innovus -def -netlist -rc -tcon
logPuts "### TCM11ECO ### complete"
exit
