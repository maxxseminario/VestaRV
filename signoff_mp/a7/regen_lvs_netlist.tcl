# A7-3 Stage 3: regenerate the PG-aware chip LVS netlist from the A7 (04:38)
# signoff cut, via the FRESH-INIT path (NO restoreDesign -> no tapeOut FATAL),
# exactly per the ERA template tcl/a7_era.tcl. Then run the A6 saveNetlist step
# (signoff_mp/tcl/chip_argus_lvs_netlist.tcl). Run from innovus/common:
#   cd innovus/common && innovus -no_gui -batch -log log/a7_regen_lvs \
#       -files /home/mseminario2/vestarv/signoff_mp/a7/regen_lvs_netlist.tcl
# Output: signoff_mp/pvs/chip_top_argus_a7.lvs.v  (A6's chip_top_argus.lvs.v kept).
# NOTHING is saved back to any DB; signoff DB untouched.
source tcl/constants.tcl
source $SCRIPT_DIR/procedures.tcl

# ---- fresh init from the flow's exact inputs (byte-identical vars, a7_era) ----
set init_verilog   "$INPUT_DIR/chip_top_argus.v $INPUT_DIR/MCU_ARGUS_hier.pnr.v"
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
# NB: fresh init_design starts a NEW session with tapeOut mode OFF by default
# (the riCheckTimingLibrary FATAL only fires on restoreDesign of a DB that has
# tapeOut=true; a7_era.tcl documents that a fresh session never runs the check).
# We therefore do NOT set tapeOut here -- we neither enable nor disable any
# fabrication safety guard; the check simply does not run in fresh-init.
init_design
setDesignMode -process 65 -flowEffort standard -powerEffort low
setMultiCpuUsage -localCpu 4
setAnalysisMode -analysisType onChipVariation -cppr both
# routed physical from the signoff DEF (placement + signal + PG special routing +
# ALL post-route instances incl CTS buffers + ANTENNA diodes, and the post-CTS
# net connectivity in the DEF NETS section)
defIn $DATABASE_DIR/chip_top_argus.signoff.innovus.dat/chip_top.def.gz
clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst * -module {} -autoTie -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -module {} -autoTie -verbose
puts "A7REGEN: init+defIn+gnc done; instCount=[llength [dbGet top.insts.name]]"

# ---- A6 saveNetlist step (signoff_mp/tcl/chip_argus_lvs_netlist.tcl) ----
saveNetlist \
    -excludeLeafCell \
    -includePowerGround \
    -phys \
    -excludeCellInst "FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH FILLBIASA10TH FILLTIE128A10TH FILLTIE64A10TH FILLTIE32A10TH FILLTIE16A10TH FILLTIE8A10TH FILLTIE4A10TH FILLTIE2A10TH" \
    /home/mseminario2/vestarv/signoff_mp/pvs/chip_top_argus_a7.lvs.v
puts "A7REGEN: saveNetlist done -> signoff_mp/pvs/chip_top_argus_a7.lvs.v"
exit
