# G2 (2026-07-23): chip_top_dp LVS netlist WITH power/ground — A7 FRESH-INIT +
# defIn pattern (never restoreDesign a tapeout-mode chip DB, never patch .mode:
# the standing G0/A7 rule; proven again this session on MCU_DP). init_verilog
# MUST be the cut's own post-route netlist (out/chip_top_dp.xsim.v) — the flow
# INPUT verilog lacks the chip-level opt/CTS instances in the DEF.
#
# Physical cells KEPT (-phys): the tphn signal/supply pad-ring instances
# (PDUW16SDGZ_G / PDB3A_G / PVDD*/PVSS*/PVDD2POC_G) — subckt defs come from the
# tphn spice in lvs_include_chip. std-cell FILL family excluded (C0 list).
# Sanity gate (A7): IMPDF-138 ~0 and distinct FE_OFN/CTS_ counts must match
# out/chip_top_dp.xsim.v.
#
# Run: cd ~/vestarv/innovus/common/chip_top_dp && innovus -no_gui -batch \
#        -log log/chip_top_dp_lvs_regen -files ../../../signoff_mp/tcl/chip_top_dp_lvs_netlist.tcl

source ../shared/constants.tcl
source ../shared/procedures.tcl

set IO_PAD_LEF /opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/lef/tphn65gpgv2od3_sl_210a/mt_2/8lm/lef/tphn65gpgv2od3_sl_8lm.lef

set init_verilog   "$OUTPUT_DIR/chip_top_dp.xsim.v"
set init_top_cell  chip_top_dp
set init_pwr_net   VDD
set init_gnd_net   VSS
set init_mmmc_file "$SCRIPT_DIR/viewdefinition_chip_dp.tcl"
set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					$IP_DIR/rom_hvt_pg/rom_hvt_pg.lef \
					$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef \
					$IC_DIR/abstracts/myshkin_abs/GlitchFilter/GlitchFilter.lef \
					$IC_DIR/abstracts/myshkin_abs/PowerOnResetCheng/PowerOnResetCheng.lef \
					$IC_DIR/abstracts/myshkin_abs/OscillatorCurrentStarved/OscillatorCurrentStarved.lef \
					$OUTPUT_DIR/hart_tile.lef \
					$IO_PAD_LEF"
set init_design_uniquify 1
init_design
setDesignMode -process 65 -flowEffort standard -powerEffort low
setMultiCpuUsage -localCpu 4

defIn $DATABASE_DIR/chip_top_dp.signoff.innovus.dat/chip_top_dp.def.gz
clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst * -module {} -autoTie -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -module {} -autoTie -verbose
puts "DPCHIPREGEN: init+defIn+gnc done; instCount=[llength [dbGet top.insts.name]]"

saveNetlist \
    -excludeLeafCell \
    -includePowerGround \
    -phys \
    -excludeCellInst "FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH FILLBIASA10TH FILLTIE128A10TH FILLTIE64A10TH FILLTIE32A10TH FILLTIE16A10TH FILLTIE8A10TH FILLTIE4A10TH FILLTIE2A10TH" \
    /home/mseminario2/vestarv/signoff_mp/pvs/chip_top_dp_full.lvs.v
puts "DPCHIPREGEN: saveNetlist done -> signoff_mp/pvs/chip_top_dp_full.lvs.v"
exit
