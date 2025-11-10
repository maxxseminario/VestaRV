#######################################################
#                                                     
#  Innovus Command Logging File                     
#  Created on Sun Nov  9 23:28:41 2025                
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
saveDrc /tmp/innovus_temp_7758_atlas_mseminario2_Y7nX0E/vergQTmphHBZOs/qthread_src.drc
clearDrc
saveDrc /tmp/innovus_temp_7758_atlas_mseminario2_Y7nX0E/vergQTmphHBZOs/qthread_1.drc
saveDrc /tmp/innovus_temp_7758_atlas_mseminario2_Y7nX0E/vergQTmphHBZOs/qthread_0.drc
saveDrc /tmp/innovus_temp_7758_atlas_mseminario2_Y7nX0E/vergQTmphHBZOs/qthread_2.drc
saveDrc /tmp/innovus_temp_7758_atlas_mseminario2_Y7nX0E/vergQTmphHBZOs/qthread_4.drc
saveDrc /tmp/innovus_temp_7758_atlas_mseminario2_Y7nX0E/vergQTmphHBZOs/qthread_3.drc
saveDrc /tmp/innovus_temp_7758_atlas_mseminario2_Y7nX0E/vergQTmphHBZOs/qthread_7.drc
saveDrc /tmp/innovus_temp_7758_atlas_mseminario2_Y7nX0E/vergQTmphHBZOs/qthread_5.drc
saveDrc /tmp/innovus_temp_7758_atlas_mseminario2_Y7nX0E/vergQTmphHBZOs/qthread_6.drc
loadDrc /tmp/innovus_temp_7758_atlas_mseminario2_Y7nX0E/vergQTmphHBZOs/qthread.drc
loadDrc -incremental /tmp/innovus_temp_7758_atlas_mseminario2_Y7nX0E/vergQTmphHBZOs/qthread_src.drc
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
