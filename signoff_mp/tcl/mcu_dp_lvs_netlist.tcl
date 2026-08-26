# Stage F2a (2026-07-21): regenerate the MCU_DP (CastaliaDP respin assembly,
# top cell "MCU") LVS netlist WITH power/ground from the FRESH Jul-21 cut,
# per the A7 re-P&R-invalidates-netlists rule.
#
# A7 FRESH-INIT pattern (regen_lvs_netlist2.tcl), NOT the older mcu recipe's
# restoreDesign + .mode patch: init from the cut's OWN post-route netlist
# (out/MCU_DP.xsim.v, same save as the DEF) + the flow's exact LEF set, then
# defIn the signoff DEF -- no DB touched, no tapeOut-mode interaction at all.
# Sanity gate (A7): IMPDF-138 dropped-pin count must be ~0 and distinct
# FE_OFN/CTS_ counts in the output must match out/MCU_DP.xsim.v.
#
# Run: cd ~/vestarv/innovus/common/MCU_DP && innovus -no_gui -batch \
#        -log log/mcu_dp_lvs_regen -files ../../../signoff_mp/tcl/mcu_dp_lvs_netlist.tcl
# (run dir = the BLOCK dir since the 2026-07-27 reorg, so dbs/ out/ log/ and
#  ../shared/constants.tcl resolve as in the flow)

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
puts "DPREGEN: init+defIn+gnc done; instCount=[llength [dbGet top.insts.name]]"

# saveNetlist options per hart_tile_lvs_netlist.tcl rationale + the mcu
# recipe's FILLTIE additions (assembly-level fill set).
saveNetlist \
    -excludeLeafCell \
    -includePowerGround \
    -phys \
    -excludeCellInst "FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH FILLBIASA10TH FILLTIE128A10TH FILLTIE64A10TH FILLTIE32A10TH FILLTIE16A10TH FILLTIE8A10TH FILLTIE4A10TH FILLTIE2A10TH" \
    /home/mseminario2/vestarv/signoff_mp/pvs/MCU_DP_full.lvs.v
puts "DPREGEN: saveNetlist done -> signoff_mp/pvs/MCU_DP_full.lvs.v"
exit
