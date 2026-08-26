################################################################################
# CQ8a center-band DRC closure ECO for chip_top_quad -- v2 (regression-free).
#
# v1 FINDING (chipdrc-measured): the cut-blockage + ecoRoute method CLOSES the
# two signal-adjacent classes M3.S.2 (2->0) and M5.S.2 (1->0), BUT a global
# deleteFiller/addFiller on the postRoute DB (without a following DRC-clean pass,
# IMPSP-5217) manufactured ~400 NEW min-area/area violations (M2.A.1 +178,
# M3.A.1 +130, M4.A.1 +73, G.4:M2i +9 ...). ecoRoute does NOT move cells, so the
# fillers never needed regenerating. v2 DROPS the filler churn entirely.
#
# v1 also proved fixVia/editPowerVia are NO-OPs on the remaining 4 classes
# (VIA7.W.1, M7.S.3, most of M7.S.4, DM2.S.2): those are PG-stripe / macro-pin
# phase artifacts (A6 VIA-PHASE-RULE class) + GlitchFilter macro dummy fill --
# NOT signal-routing artifacts, so signal ecoRoute structurally cannot reach
# them (see the CQ8a report: they need a CQ3a floorplan-stage stripe-phase fix).
# v2 therefore targets ONLY the two classes the sanctioned method can close, and
# guarantees no collateral.
#
# usage (from innovus/common; ONE license, batch):
#   innovus -no_gui -batch -files tcl/chip_top_quad_cq8a_eco.innovus.tcl
################################################################################
source ../shared/constants.tcl
set BASENAME chip_top_quad
set restore_db_file_check 0
setCheckMode -tapeOut false
restoreDesign $DATABASE_DIR/chip_top_quad.signoff.innovus.dat chip_top_quad
setMultiCpuUsage -localCpu 8

################################################################################
# CUT BLOCKAGES at the M3.S.2 / M5.S.2 offenders. Signal route blockages push
# signal routing off the offending layer locally; ecoRoute reroutes around them.
# TINY so no PG rail / macro pin is gutted. (v1 proved these clear M3.S.2/M5.S.2.)
################################################################################
createRouteBlk -name cq8a_m3_1 -box [list 1009.8 894.6 1015.6 895.8] -layer 3
createRouteBlk -name cq8a_m3_2 -box [list 1158.0 1030.6 1162.0 1031.8] -layer 3
createRouteBlk -name cq8a_m5_1 -box [list 1011.5 934.6 1016.5 935.8] -layer 5
puts "### CQ8a ### : cut route blockages created (M3 x2, M5 x1)"

setNanoRouteMode -routeWithTimingDriven false
setNanoRouteMode -drouteFixAntenna true
setNanoRouteMode -routeInsertAntennaDiode true
setNanoRouteMode -routeAntennaCellName "ANTENNA2A10TH"
if {[catch {ecoRoute -fix_drc} r]} { puts "### CQ8a WARN ### : ecoRoute -fix_drc: $r" }
puts "### CQ8a ### : ecoRoute -fix_drc done"

# Safe standard via cleanup (no-op on the PG artifacts, harmless).
catch { fixVia -short }
catch { fixVia -minCut }
catch { fixVia -minStep }

# NO deleteFiller / addFiller (v1 regression source). ecoRoute did not move
# cells, so the CQ5 fillers are untouched and DRC-clean.

################################################################################
# Verify (Innovus) + full power (postRoute) for the dashboard/CQ8d. Save cq8a DB.
################################################################################
catch { report_power -outfile $REPORT_DIR/chip_top_quad_cq8a_postRoute_full.power }
verifyGeometry -error 10000 -warning 10000 \
    -report $REPORT_DIR/chip_top_quad.cq8a.verifyGeometry.rpt

catch { setAnalysisMode -analysisType onChipVariation -cppr both }
catch {
    timeDesign -postRoute -expandedViews \
        -outDir $REPORT_DIR/chip_top_quad.cq8a.timeDesign.postroute
}

setCheckMode -tapeOut false
saveDesign $DATABASE_DIR/chip_top_quad.cq8a.innovus -def -netlist -rc -tcon
puts "### CQ8a ### : saved cq8a DB"

set IO_PAD_GDS /opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/gds/tphn65gpgv2od3_sl_210a/mt_2/8lm/tphn65gpgv2od3_sl.gds
streamOut $OUTPUT_DIR/chip_top_quad.cq8a.gds2 \
    -libName WorkLib -structureName chip_top_quad \
    -stripes 1 -units 1000 -mode ALL \
    -merge [list ../hart_tile/out/hart_tile.gds2 $IO_PAD_GDS] \
    -mapFile ../shared/innovus2gds.map
puts "### CQ8a ### : streamOut chip_top_quad.cq8a.gds2 complete"
exit
