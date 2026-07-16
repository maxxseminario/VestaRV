################################################################################
# CQ8a: on the v2 ECO DB, run postRoute HOLD timing (gate 4) and emit the LVS
# netlist (gate 3 prereq). Read/restore only; no design change.
# usage (from innovus/common):
#   innovus -no_gui -batch -files tcl/chip_top_quad_cq8a_hold_netlist.innovus.tcl
################################################################################
source tcl/constants.tcl
set restore_db_file_check 0
setCheckMode -tapeOut false
restoreDesign $DATABASE_DIR/chip_top_quad.cq8a.innovus.dat chip_top_quad
setMultiCpuUsage -localCpu 8
setAnalysisMode -analysisType onChipVariation -cppr both
setDelayCalMode -SIAware true
catch {
    timeDesign -postRoute -hold -expandedViews \
        -outDir $REPORT_DIR/chip_top_quad.cq8a.timeDesign.hold
}
setDelayCalMode -SIAware false
# LVS netlist (PG-aware) for gate 3
saveNetlist \
    -excludeLeafCell -includePowerGround -phys \
    -excludeCellInst "FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH FILLBIASA10TH FILLTIE128A10TH FILLTIE64A10TH FILLTIE32A10TH FILLTIE16A10TH FILLTIE8A10TH FILLTIE4A10TH FILLTIE2A10TH" \
    /home/mseminario2/vestarv/signoff_mp/pvs/chip_top_quad.cq8a.lvs.v
puts "### CQ8a ### : hold timing + LVS netlist done"
exit
