################################################################################
# MCU_ARGUS_eco4.tcl -- one-shot incremental DRC eco on the v4.5 final db.
#
# ABANDONED (kept as a war story): a restoreDesign session runs
# riCheckTimingLibrary on the first routing command and FATALs on the 3
# timing-less analog abstracts (POR/DCO/GlitchFilter) -- neither
# setCheckMode -tapeOut false nor -dbSkipAnalog true bypasses it, and the
# MAIN flow never runs that check (fresh init_design session). The 4 residual
# shorts were fixed by re-running the corrected main script instead (v4.6:
# DRC loop does deleteAllRouteBlks first + routeTopRoutingLayer 6).
# The v4.5 signoff left exactly 4 signal-signal shorts (M4/M6, B2/channel
# edges) because the in-flow eco loop's passes were poisoned by 919 phantom
# pin-vs-routeblk "shorts" (fixed in MCU_ARGUS.innovus.tcl for future runs).
# This session: restore final db -> ecoRoute (ceiling M6; the M7/M8 blks are
# gone in the db, power lives there) -> re-verify -> refresh ALL outputs.
################################################################################
source tcl/constants.tcl
source $SCRIPT_DIR/procedures.tcl
proc plog {msg} { puts $msg; flush stdout }
set BASENAME MCU_ARGUS
set DESIGN_NAME MCU

restoreDesign $DATABASE_DIR/$BASENAME.final.innovus.dat $DESIGN_NAME
plog "### UNL STATUS ### : final db restored"
setMultiCpuUsage -acquireLicense 8 -localCpu 8

# the restored db carries setCheckMode -tapeOut true, which promotes the
# 3 timing-less analog abstracts (POR/DCO/GlitchFilter -- benign IMPSYC-2
# warns in the main flow) to a riCheckTimingLibrary FATAL on nanoroute init.
setCheckMode -tapeOut false
# -dbSkipAnalog is the knob that lets nanoroute pass riCheckTimingLibrary
# with the 3 timing-less analog abstracts (it is what the main flow uses).
setNanoRouteMode -routeTopRoutingLayer 6 -routeWithTimingDriven false -routeWithSiDriven false -dbSkipAnalog true
ecoRoute -fix_drc
verifyGeometry \
    -antenna \
    -error 100000 \
    -report $REPORT_DIR/$BASENAME.verifyGeometry.signoff.rpt
set NSHORT -1
catch { set NSHORT [exec sh -c "grep -m1 -E '^  Short' $REPORT_DIR/$BASENAME.verifyGeometry.signoff.rpt | grep -oE '\[0-9\]+'"] }
plog "### UNL STATUS ### : post-eco signoff shorts=$NSHORT"

verifyConnectivity \
    -error 100000 \
    -connectPadSpecialPorts \
    -report $REPORT_DIR/$BASENAME.verifyConnectivity.signoff.rpt

setDelayCalMode -SIAware false
setAnalysisMode -analysisType onChipVariation -cppr both
timeDesign \
    -si \
    -signoff \
    -outdir $REPORT_DIR/$BASENAME.timeDesign.signoff.rpt

saveDesign $DATABASE_DIR/$BASENAME.final.innovus -def -netlist -rc -tcon

streamOut \
    $OUTPUT_DIR/$BASENAME.gds2 \
    -libName WorkLib \
    -structureName $DESIGN_NAME \
    -stripes 1 \
    -units 1000 \
    -mode ALL \
    -merge [list $OUTPUT_DIR/hart_tile_argus.gds2] \
    -mapFile $INPUT_DIR/innovus2gds.map

write_sdf $OUTPUT_DIR/$BASENAME.sdf
saveNetlist \
    $OUTPUT_DIR/$BASENAME.xsim.v \
    -excludeCellInst ANTENNA2A10TH
plog "### UNL STATUS ### : eco4 complete, outputs refreshed"
exit
