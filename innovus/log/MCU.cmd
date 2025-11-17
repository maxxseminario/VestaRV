#######################################################
#                                                     
#  Innovus Command Logging File                     
#  Created on Sat Nov 15 15:37:09 2025                
#                                                     
#######################################################

#@(#)CDS: Innovus v20.12-s088_1 (64bit) 11/06/2020 10:29 (Linux 2.6.32-431.11.2.el6.x86_64)
#@(#)CDS: NanoRoute 20.12-s088_1 NR201104-1900/20_12-UB (database version 18.20.530) {superthreading v2.11}
#@(#)CDS: AAE 20.12-s034 (64bit) 11/06/2020 (Linux 2.6.32-431.11.2.el6.x86_64)
#@(#)CDS: CTE 20.12-s038_1 () Nov  5 2020 21:44:51 ( )
#@(#)CDS: SYNTECH 20.12-s015_1 () Oct  9 2020 06:18:19 ( )
#@(#)CDS: CPE v20.12-s080
#@(#)CDS: IQuantus/TQuantus 20.1.1-s391 (64bit) Tue Sep 8 11:07:25 PDT 2020 (Linux 2.6.32-431.11.2.el6.x86_64)

set_global _enable_mmmc_by_default_flow      $CTE::mmmc_default
suppressMessage ENCEXT-2799
getVersion
fit
redraw
set init_verilog ../genus/out/MCU.genus.v
set init_top_cell MCU
set init_pwr_net VDD
set init_gnd_net VSS
set init_mmmc_file tcl/viewdefinition.tcl
set init_lef_file {/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10/lef/tsmc_cln65_a10_6X1Z_tech.lef   /opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10/lef/tsmc65_hvt_sc_adv10_macro.lef  ../ip/rom_hvt_pg/rom_hvt_pg.lef  ../ip/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef  ../ic/abstracts/myshkin_abs/GlitchFilter/GlitchFilter.lef  ../ic/abstracts/myshkin_abs/PowerOnResetCheng/PowerOnResetCheng.lef  ../ic/abstracts/myshkin_abs/OscillatorCurrentStarved/OscillatorCurrentStarved.lef}
set init_design_uniquify 1
init_design
setDesignMode -process 65 -flowEffort standard -powerEffort low
setMultiCpuUsage -acquireLicense 8 -localCpu 8
setFillerMode -corePrefix FILLER -core {FILLTIE128A10TH FILLTIE64A10TH FILLTIE32A10TH FILLTIE16A10TH FILLTIE8A10TH FILLTIE4A10TH FILLTIE2A10TH FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH}
setAnalysisMode -analysisType onChipVariation -cppr both
clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst * -module {} -autoTie -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -module {} -autoTie -verbose
floorPlan -site TSMC65ADV10TSITE -s 1184 683 1 2 1 1
setPreference EnableRectilinearDesign 1
setObjFPlanPolygon cell MCU 0 686 0 0 1186 0 1186 686 1139 686 1139 446 739 446 739 506 389 506 389 656 670 656 670 686
placeInstance rom0 10 519.475 R90
addHaloToBlock 9 2.0 2.0 9 rom0
cutRow
placeInstance ram1 29.975 10 MX
addHaloToBlock 30.975 2.0 2.0 2.0 ram1
cutRow
placeInstance ram0 30.975 135.47 MX
addHaloToBlock 29.975 2.0 2.0 2.0 ram0
cutRow
placeInstance por 37.675 350.0 MX
addHaloToBlock 2.0 2.0 2.0 2.0 por
cutRow
placeInstance irq_gf0 435.4 300 R0
addHaloToBlock 2.0 2.0 2.0 2.0 irq_gf0
cutRow
placeInstance irq_gf1 435.4 350.0 R0
addHaloToBlock 2.0 2.0 2.0 2.0 irq_gf1
cutRow
placeInstance irq_gf2 435.4 400.0 R0
addHaloToBlock 2.0 2.0 2.0 2.0 irq_gf2
cutRow
placeInstance dco0 121.795 403 R0
addHaloToBlock 2.0 2.0 0.9 2.0 dco0
cutRow
placeInstance dco1 221.795 403 R0
addHaloToBlock 0.9 2.0 2.0 2.0 dco1
cutRow
fit
redraw
loadIoFile in/MCU.io
fit
redraw
addRing -nets {VDD VSS} -type core_rings -follow io -layer {top M8 bottom M8 left M7 right M7} -width 10.0 -spacing 4.0 -offset 4.0 -center 0 -extend_corner {} -threshold 0 -jog_distance 0 -snap_wire_center_to_grid None
add_text -label VDD -layer M8 -pt {9.0 9.0}
add_text -label VSS -layer M8 -pt {23.0 23.0}
setAddStripeMode -remove_floating_stripe_over_block true -trim_antenna_back_to_shape core_ring -stacked_via_top_layer M8 -extend_to_closest_target ring
addStripe -layer M8 -nets {VDD VSS} -direction horizontal -start_from left -set_to_set_distance 50.0 -spacing 4.0 -width 5.0 -block_ring_bottom_layer_limit M1 -start_offset 50.0 -stop_offset 4.0 -area_blockage {{121.795 407 180.205 440.39} {221.795 407 280.205 440.39}}
addStripe -layer M7 -nets {VDD VSS} -direction vertical -extend_to design_boundary -start_from bottom -set_to_set_distance 50.0 -spacing 4.0 -width 5.0 -block_ring_bottom_layer_limit M1 -start_offset 50.0 -stop_offset 4.0 -area_blockage {{121.795 407 180.205 440.39} {221.795 407 280.205 440.39}}
editTrim -all
setCheckMode -globalNet true -io true -route true -tapeOut true
sroute -nets { VSS VDD } -allowLayerChange 0 -allowJogging 0 -connect corePin -corePinWidth 0.3
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpsu2kCd/qthread_src.drc
clearDrc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpsu2kCd/qthread_4.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpsu2kCd/qthread_0.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpsu2kCd/qthread_3.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpsu2kCd/qthread_2.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpsu2kCd/qthread_1.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpsu2kCd/qthread_7.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpsu2kCd/qthread_5.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpsu2kCd/qthread_6.drc
loadDrc -incremental /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpsu2kCd/qthread_src.drc
fixVia -short
fixVia -minCut
fixVia -minStep
fit
redraw
createRouteBlk -box 0 0 1186 686 -layer 8
createRouteBlk -box 435.4 300 466.6 318.87 -layer 1
createRouteBlk -box 435.4 350.0 466.6 368.87 -layer 1
createRouteBlk -box 435.4 400.0 466.6 418.87 -layer 1
createRouteBlk -box 37.675 350.0 64.325 361.79 -layer {1 2}
createRouteBlk -box 121.795 407 180.205 440.39 -layer all
createRouteBlk -box 221.795 407 280.205 440.39 -layer all
addWellTap -cell FILLTIE2A10TH -cellInterval 24 -fixedGap -checkerBoard -prefix WELLTAP
place_opt_design
fit
redraw
add_ndr -name CTS_2W2S -width {M2:M6 0.4} -generate_via -spacing {M2:M6 0.42}
add_ndr -name CTS_2W1S -width {M2:M6 0.4} -generate_via -spacing {M2:M6 0.21}
create_route_type -name top_rule -non_default_rule CTS_2W2S -top_preferred_layer M6 -bottom_preferred_layer M5 -shield_net VSS -bottom_shield_layer M5
create_route_type -name trunk_rule -non_default_rule CTS_2W2S -top_preferred_layer M4 -bottom_preferred_layer M3 -shield_net VSS -bottom_shield_layer M3
create_route_type -name leaf_rule -non_default_rule CTS_2W1S -top_preferred_layer M3 -bottom_preferred_layer M2
set_ccopt_property -net_type top route_type top_rule
set_ccopt_property -net_type trunk route_type trunk_rule
set_ccopt_property -net_type leaf route_type leaf_rule
set_ccopt_property routing_top_min_fanout 10000
set_ccopt_property buffer_cells {BUFX0P7BA10TH BUFX0P8BA10TH BUFX11BA10TH BUFX13BA10TH BUFX16BA10TH BUFX1BA10TH BUFX1P2BA10TH BUFX1P4BA10TH BUFX1P7BA10TH BUFX2BA10TH BUFX2P5BA10TH BUFX3BA10TH BUFX3P5BA10TH BUFX4BA10TH BUFX5BA10TH BUFX6BA10TH BUFX7P5BA10TH BUFX9BA10TH}
set_ccopt_property inverter_cells {INVX0P5BA10TH INVX0P6BA10TH INVX0P7BA10TH INVX0P8BA10TH INVX11BA10TH INVX13BA10TH INVX16BA10TH INVX1BA10TH INVX1P2BA10TH INVX1P4BA10TH INVX1P7BA10TH INVX2BA10TH INVX2P5BA10TH INVX3BA10TH INVX3P5BA10TH INVX4BA10TH INVX5BA10TH INVX6BA10TH INVX7P5BA10TH INVX9BA10TH}
set_ccopt_property delay_cells {DLY2X0P5MA10TH DLY4X0P5MA10TH}
set_ccopt_property use_inverters true
set_ccopt_property target_max_trans 400ps
create_ccopt_clock_tree_spec
ccopt_design
fit
redraw
optDesign -postCTS -hold
fit
redraw
timeDesign -postCTS -expandedViews -outDir rpt/MCU.timeDesign.postcts
report_ccopt_clock_trees -file rpt/MCU.report_ccopt_clock_trees.postcts
report_ccopt_skew_groups -file rpt/MCU.report_ccopt_skew_groups.postcts
setNanoRouteMode -routeTopRoutingLayer 7 -envNumberFailLimit 10 -droutePostRouteSwapVia multiCut -drouteUseMultiCutViaEffort medium -routeAllowPowerGroundPin true -drouteFixAntenna true -routeAntennaCellName ANTENNA2A10TH -routeInsertAntennaDiode true -routeInsertDiodeForClockNets true -routeIgnoreAntennaTopCellPin false -routeFixTopLayerAntenna false -drouteAntennaEcoListFile rpt/MCU.routeDesign.diodes.txt -dbSkipAnalog true -drouteEndIteration default
routeDesign
fit
redraw
optDesign -postRoute -setup -hold
fit
redraw
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpj0rBcG/qthread_src.drc
clearDrc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpj0rBcG/qthread_5.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpj0rBcG/qthread_6.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpj0rBcG/qthread_4.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpj0rBcG/qthread_7.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpj0rBcG/qthread_2.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpj0rBcG/qthread_3.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpj0rBcG/qthread_0.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpj0rBcG/qthread_1.drc
loadDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpj0rBcG/qthread.drc
ecoRoute -fix_drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmp1PRJJ0/qthread_src.drc
clearDrc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmp1PRJJ0/qthread_5.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmp1PRJJ0/qthread_6.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmp1PRJJ0/qthread_4.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmp1PRJJ0/qthread_7.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmp1PRJJ0/qthread_2.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmp1PRJJ0/qthread_3.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmp1PRJJ0/qthread_0.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmp1PRJJ0/qthread_1.drc
loadDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmp1PRJJ0/qthread.drc
ecoRoute -fix_drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpr6tW9N/qthread_src.drc
clearDrc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpr6tW9N/qthread_5.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpr6tW9N/qthread_6.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpr6tW9N/qthread_4.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpr6tW9N/qthread_7.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpr6tW9N/qthread_2.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpr6tW9N/qthread_3.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpr6tW9N/qthread_0.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpr6tW9N/qthread_1.drc
loadDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpr6tW9N/qthread.drc
routeDesign
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpBvLk5R/qthread_src.drc
clearDrc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpBvLk5R/qthread_5.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpBvLk5R/qthread_6.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpBvLk5R/qthread_4.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpBvLk5R/qthread_7.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpBvLk5R/qthread_2.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpBvLk5R/qthread_3.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpBvLk5R/qthread_0.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpBvLk5R/qthread_1.drc
loadDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpBvLk5R/qthread.drc
streamOut out/MCU.gds2 -libName WorkLib -structureName MCU -stripes 1 -units 1000 -mode ALL -mapFile in/innovus2gds.map
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpHcUe49/qthread_src.drc
clearDrc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpHcUe49/qthread_5.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpHcUe49/qthread_6.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpHcUe49/qthread_4.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpHcUe49/qthread_7.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpHcUe49/qthread_2.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpHcUe49/qthread_3.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpHcUe49/qthread_0.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpHcUe49/qthread_1.drc
loadDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpHcUe49/qthread.drc
addFiller
verifyConnectivity -error 100000 -connectPadSpecialPorts -report rpt/MCU.verifyConnectivity.signoff.rpt
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpR199sN/qthread_src.drc
clearDrc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpR199sN/qthread_5.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpR199sN/qthread_6.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpR199sN/qthread_4.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpR199sN/qthread_7.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpR199sN/qthread_2.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpR199sN/qthread_3.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpR199sN/qthread_0.drc
saveDrc /tmp/innovus_temp_89100_atlas_mseminario2_L60O3d/vergQTmpR199sN/qthread_1.drc
verifyProcessAntenna -report rpt/MCU.verifyProcessAntenna.signoff.rpt
fit
redraw
setDelayCalMode -SIAware false
setAnalysisMode -analysisType onChipVariation -cppr both
timeDesign -si -signoff -outdir rpt/MCU.timeDesign.signoff.rpt
setAnalysisMode -cppr both
report_clock_timing \
    -type skew \
    -nworst 10 > $REPORT_DIR/$DESIGN_NAME.report_clock_timing.skew.signoff.rpt
report_timing -net > $REPORT_DIR/$DESIGN_NAME.report_timing.signoff.rpt
setAnalysisMode -checkType hold -skew true
report_timing > $REPORT_DIR/$DESIGN_NAME.report_timing.hold.signoff.rpt
report_timing -machine_readable -max_paths 10000 -max_slack 0.75 -path_exceptions all -early > $REPORT_DIR/$DESIGN_NAME.report_timing.hold.signoff.mtarpt
setAnalysisMode -checkType setup -skew true
report_timing > $REPORT_DIR/$DESIGN_NAME.report_timing.setup.signoff.rpt
report_timing -machine_readable -max_paths 10000 -max_slack 0.75 -path_exceptions all -late > $REPORT_DIR/$DESIGN_NAME.report_timing.setup.signoff.mtarpt
all_hold_analysis_views
all_setup_analysis_views
getPlaceMode -doneQuickCTS -quiet
checkPlace -ignoreOutOfCore -noPreplaced rpt/MCU.checkPlace.signoff.rpt
reportGateCount -level 2 -outfile rpt/MCU.reportGateCount.signoff.rpt
summaryReport -noHtml -outfile rpt/MCU.summaryReport.signoff.rpt
checkDesign -all -noHtml -outfile rpt/MCU.checkDesign.signoff.rpt
saveDesign dbs/MCU.signoff.innovus -def -netlist -rc -tcon
createRouteBlk -box 0 0 1186 686 -spacing 0.0 -layer 1
createRouteBlk -box 0 0 1186 686 -spacing 0.0 -layer 2
createRouteBlk -box 0 0 1186 686 -spacing 0.0 -layer 3
createRouteBlk -box 0 0 1186 686 -spacing 0.0 -layer 4
createRouteBlk -box 0 0 1186 686 -spacing 0.0 -layer 5
createRouteBlk -box 0 0 1186 686 -spacing 0.0 -layer 6
createRouteBlk -box 0 0 1186 686 -spacing 0.0 -layer 7
createRouteBlk -box 0 0 1186 686 -spacing 0.0 -layer 8
streamOut out/MCU.gds2 -libName WorkLib -structureName MCU -stripes 1 -units 1000 -mode ALL -mapFile in/innovus2gds.map
write_sdf $OUTPUT_DIR/$DESIGN_NAME.sdf
write_sdf $OUTPUT_DIR/$DESIGN_NAME.explicit.sdf -recompute_delay_calc
saveNetlist out/MCU.xsim.v -excludeCellInst ANTENNA2A10TH
saveNetlist -excludeLeafCell out/MCU.lvs.v -excludeCellInst {FILLTIE128A10TH FILLTIE64A10TH FILLTIE32A10TH FILLTIE16A10TH FILLTIE8A10TH FILLTIE4A10TH FILLTIE2A10TH FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH} -flat -phys
createInterfaceLogic -hold -dir out/MCU.ilm
saveDesign dbs/MCU.final.innovus -def -netlist -rc -tcon
win
win off
