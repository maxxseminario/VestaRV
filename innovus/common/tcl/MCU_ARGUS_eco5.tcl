################################################################################
# MCU_ARGUS_eco5.tcl -- kill the 4 deterministic residual shorts of the v4.5/
# v4.6 assembly (same nets + coords both runs; ecoRoute -fix_drc refuses to
# touch them). Strategy: delete the 8 involved nets' routing outright and let
# nanoroute route them as opens.
#
# restoreDesign-session gotcha (the eco4 war story): nanoroute runs
# riCheckTimingLibrary in restored sessions and FATALs on the 3 timing-less
# analog abstracts. Fix: patch the restored MMMC library sets in-session with
# in/analog_abstracts_dummy.lib (pins, no arcs) BEFORE any routing command.
# (viewdefinition_top_argus.tcl now carries the dummy lib for future fresh
# runs, but this db was saved before that edit.)
################################################################################
source tcl/constants.tcl
source $SCRIPT_DIR/procedures.tcl
proc plog {msg} { puts $msg; flush stdout }
set BASENAME MCU_ARGUS
set DESIGN_NAME MCU

# the .dat's viewDefinition.tcl + libs/mmmc were patched on disk (dummy analog
# lib); innovus checksums the .dat and refuses modified files unless:
set restore_db_file_check 0
restoreDesign $DATABASE_DIR/$BASENAME.final.innovus.dat $DESIGN_NAME
plog "### UNL STATUS ### : final db restored"
setMultiCpuUsage -acquireLicense 8 -localCpu 8

# (library sets patched ON DISK inside the .dat instead: libs/mmmc/ got
# analog_abstracts_dummy.lib and viewDefinition.tcl lists it -- the FATAL
# fires DURING restoreDesign, before any in-session command can run.)

setCheckMode -tapeOut false
setNanoRouteMode \
    -routeTopRoutingLayer 6 \
    -routeWithTimingDriven false \
    -routeWithSiDriven false \
    -dbSkipAnalog true

# The 8 nets of the 4 shorts (identical in v4.5 and v4.6):
set BAD_NETS [list \
    {a0_16_raw[8]} \
    {a0_10_raw[8]} \
    {a0_16_raw[5]} \
    {resv0/FE_OFN10537_arb_lrsc_20} \
    {FE_OFN20591_FE_OFN1346_gf_out_27} \
    {mp_arb0/FE_OFN20920_FE_OFN18328_FE_OFN13153_n_1141} \
    {a0_15_raw[26]} \
    {FE_OFN2644_arb_rdata_3} ]
foreach n $BAD_NETS {
    if {[catch {editDeleteRoute -net $n} r]} {
        plog "### UNL WARN ### : editDeleteRoute failed for $n: $r"
    } else {
        plog "### UNL STATUS ### : routing deleted for $n"
    }
}
ecoRoute
plog "### UNL STATUS ### : ecoRoute (open nets) done"

verifyGeometry \
    -antenna \
    -error 100000 \
    -report $REPORT_DIR/$BASENAME.verifyGeometry.signoff.rpt
set NSHORT -1
catch { set NSHORT [exec sh -c "grep -m1 -E '^  Short' $REPORT_DIR/$BASENAME.verifyGeometry.signoff.rpt | grep -oE '\[0-9\]+'"] }
plog "### UNL STATUS ### : post-eco5 signoff shorts=$NSHORT"

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
plog "### UNL STATUS ### : eco5 complete, outputs refreshed"
exit
