# =============================================================================
# CQ8c gate -- chip_top_quad SDC constraint-apply + coverage gate.
#
# Proves the two Task-2 gates after the CQ8c SDC cleanup (removal of the 855
# stale cg_enable_group_* group_path -through pins that missed after the
# 2026-07-16 AFE-stub re-synth renumbered every genus RC_CG_HIER_INST):
#   (2)  ZERO TCLCMD-917 in a full chip_top_quad elab-through-(floor)plan run.
#   (3)  no NEW unconstrained endpoints vs the CQ4/CQ5 baseline (4715).
#
# Methodology (identical to CQ4's accepted cq4_gate_diag.tcl): reproduce the
# CQ flow's EXACT import (chip_top_quad.v + MCU_MP_hier.pnr.v + tile ETM/LEF +
# pad LEF) and MMMC (viewdefinition_chip_quad.tcl -> in/chip_top_quad.sdc) via
# init_design -- the ONE stage that reads the SDC and where every TCLCMD-917
# fires. floorPlan/PG/place add NO further SDC read, so the 917 count and the
# unconstrained-endpoint coverage are fully determined here (CQ4 §0). This also
# sidesteps the saved-DB tapeOut-mode FATAL against the timing-less pad LEF.
#
# Usage (from innovus/common, license permitting -- a P&R seat, ~2-3 min):
#   source ~/vestarv/cdspaths.sh
#   innovus -no_gui -overwrite -log log/cq8c_gate -files tcl/cq8c_gate.tcl
# Then:
#   grep -c TCLCMD-917 log/cq8c_gate.log          # EXPECT 0  (was ~855 pre-fix)
#   grep uncons_endpoint log/cq8c_gate.console     # EXPECT 4715 (== CQ4 baseline)
#
# LITERAL through-floorplan alternative (same 917 result, adds geometry, no
# route license): run the flow itself with place/route skipped --
#   innovus -no_gui -overwrite -log log/cq8c_flowfp \
#       -files tcl/chip_top_quad.innovus.tcl -init "set RUN_PNR 0"
#   grep -c TCLCMD-917 log/cq8c_flowfp.log         # EXPECT 0
# =============================================================================
source tcl/constants.tcl
source $SCRIPT_DIR/procedures.tcl

set DESIGN_NAME chip_top_quad

set init_verilog   "$INPUT_DIR/chip_top_quad.v $INPUT_DIR/MCU_MP_hier.pnr.v"
set init_top_cell  "$DESIGN_NAME"
set init_pwr_net   "VDD"
set init_gnd_net   "VSS"
set init_mmmc_file "$SCRIPT_DIR/viewdefinition_chip_quad.tcl"

set IO_PAD_LEF "/opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/lef/tphn65gpgv2od3_sl_210a/mt_2/8lm/lef/tphn65gpgv2od3_sl_8lm.lef"

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

puts "### CQ8C-SDC-APPLY-START ###"
init_design
puts "### CQ8C-SDC-APPLY-END ###"

setAnalysisMode -analysisType onChipVariation -cppr both

# Coverage: unconstrained-endpoint count must be unchanged vs the CQ4 baseline
# (4715) -- group_path constrains NO endpoint, so removing the stale CG groups
# cannot create a new unconstrained endpoint. Std cells are UNPLACED here so
# PATH slack is meaningless; the CONSTRAINT-consistency section is the signal.
puts "### CQ8C-CHECKTIMING-START ###"
if {[catch { check_timing -verbose } ct]} { puts "check_timing rc=err: $ct" } else { puts $ct }
puts "### CQ8C-CHECKTIMING-END ###"

puts "### CQ8C-COVERAGE-START ###"
if {[catch { report_analysis_coverage } rac]} { puts "report_analysis_coverage rc=err: $rac" } else { puts $rac }
puts "### CQ8C-COVERAGE-END ###"

exit
