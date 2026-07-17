# A7-3 Stage 3, regen ATTEMPT 2: the attempt-1 fresh-init used the flow INPUT
# verilog (pre-P&R) -> 4510 IMPDF-138 dropped pins, netlist had 0 FE_OFN/CTS nets
# (sanity gate FAIL, see a7/regen_work/). Fix: init from the A7 cut's OWN
# post-route netlist out/chip_top_argus.xsim.v (04:38, same save as the DEF), so
# defIn finds every component. Still fresh-init (no restoreDesign -> no tapeOut
# FATAL, no DB touched, nothing saved back). Run from a7/regen_work:
#   innovus -no_gui -batch -log a7_regen_lvs2 -files ../regen_lvs_netlist2.tcl
# Output: signoff_mp/pvs/chip_top_argus_a7.lvs.v (overwrites the failed attempt-1
# file; A6's chip_top_argus.lvs.v untouched).
source tcl/constants.tcl
source $SCRIPT_DIR/procedures.tcl

# ---- fresh init: A7 POST-ROUTE netlist + the flow's exact LEF/mmmc ----
set init_verilog   "$OUTPUT_DIR/chip_top_argus.xsim.v"
set init_top_cell  chip_top
set init_pwr_net   VDD
set init_gnd_net   VSS
set init_mmmc_file "$SCRIPT_DIR/viewdefinition_chip_argus.tcl"
set IO_PAD_LEF "/opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/lef/tphn65gpgv2od3_sl_210a/mt_2/8lm/lef/tphn65gpgv2od3_sl_8lm.lef"
set init_lef_file "$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
                   $STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
                   $IP_DIR/rom_hvt_pg/rom_hvt_pg.lef \
                   $IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef \
                   $IC_DIR/abstracts/myshkin_abs/GlitchFilter/GlitchFilter.lef \
                   $IC_DIR/abstracts/myshkin_abs/PowerOnResetCheng/PowerOnResetCheng.lef \
                   $IC_DIR/abstracts/myshkin_abs/OscillatorCurrentStarved/OscillatorCurrentStarved.lef \
                   $OUTPUT_DIR/hart_tile_argus.lef \
                   $IO_PAD_LEF"
set init_design_uniquify 1
init_design
setDesignMode -process 65 -flowEffort standard -powerEffort low
setMultiCpuUsage -localCpu 4
# physical-only cells (welltap/endcap/decap) + placement come from the signoff DEF;
# the netlist now matches it, so component pins resolve (attempt-1 failure mode gone)
defIn $DATABASE_DIR/chip_top_argus.signoff.innovus.dat/chip_top.def.gz
clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst * -module {} -autoTie -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -module {} -autoTie -verbose
puts "A7REGEN2: init+defIn+gnc done; instCount=[llength [dbGet top.insts.name]]"

# ---- A6 saveNetlist step (signoff_mp/tcl/chip_argus_lvs_netlist.tcl) ----
saveNetlist \
    -excludeLeafCell \
    -includePowerGround \
    -phys \
    -excludeCellInst "FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH FILLBIASA10TH FILLTIE128A10TH FILLTIE64A10TH FILLTIE32A10TH FILLTIE16A10TH FILLTIE8A10TH FILLTIE4A10TH FILLTIE2A10TH" \
    /home/mseminario2/vestarv/signoff_mp/pvs/chip_top_argus_a7.lvs.v
puts "A7REGEN2: saveNetlist done -> signoff_mp/pvs/chip_top_argus_a7.lvs.v"
exit
