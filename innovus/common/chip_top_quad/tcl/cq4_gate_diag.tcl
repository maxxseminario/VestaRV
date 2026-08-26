# CQ4 gate diagnostic (NON-flow helper; sourced manually, never by the CQ3a
# flow script). Reproduces the CQ3a flow's constraint-apply stage: it runs the
# SAME design import (chip_top_quad.v + MCU_MP_hier.pnr.v + the tile ETM/LEF +
# pad LEF) and the SAME MMMC (viewdefinition_chip_quad.tcl -> in/chip_top_quad.sdc)
# via init_design, which is where the SDC is read and any TCLCMD-917 (object not
# found) fire -- then STOPS before floorplan/PG. This avoids the saved-DB
# tapeOut-mode timing-library FATAL (LEF-only pads are timing-less by design)
# and is strictly more faithful to "how the SDC is applied" than a DB restore.
#
# Usage:
#   source ../../../cdspaths.sh && innovus -no_gui -overwrite \
#       -log log/cq4_gate_<tag> -files tcl/cq4_gate_diag.tcl
source ../shared/constants.tcl
source ../shared/procedures.tcl

set DESIGN_NAME chip_top_quad

set init_verilog   "$INPUT_DIR/chip_top_quad.v ../MCU_MP/in/MCU_MP_hier.pnr.v"
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
					../hart_tile/out/hart_tile.lef \
					$IO_PAD_LEF"

set init_design_uniquify 1

puts "### CQ4-SDC-APPLY-START ###"
init_design
puts "### CQ4-SDC-APPLY-END ###"

setAnalysisMode -analysisType onChipVariation -cppr both

# Pre-place constraint sanity. Std cells are UNPLACED and there is no route, so
# path timing is meaningless; check_timing's CONSTRAINT-consistency section
# (unconstrained endpoints, unclocked regs, generated-clock source resolution)
# is the meaningful pre-place signal and is what we read.
puts "### CQ4-CHECKTIMING-START ###"
if {[catch { check_timing -verbose } ct]} { puts "check_timing rc=err: $ct" } else { puts $ct }
puts "### CQ4-CHECKTIMING-END ###"

# Prove the clock structure Innovus actually built (mclk/smclk/xtals/i2c/spi +
# the flash_clk_mem GENERATED clock). clk_cpu is INSIDE the tile ETM (all 4
# tiles share the one ETM) so it is not a chip-level clock object -- verified
# separately from the ETM lib.
puts "### CQ4-CLOCKS-START ###"
if {[catch { report_clock -generated } rc]} {
    if {[catch { report_clocks } rc2]} { puts "report_clocks rc=err: $rc2" } else { puts $rc2 }
} else { puts $rc }
puts "### CQ4-CLOCKS-END ###"

# TIE-cell existence probe (dispositions the two set_dont_use lines): does the
# assembly's loaded lib set actually contain TIEHIX1MA10TH / TIELOX1MA10TH?
puts "### CQ4-TIE-PROBE-START ###"
foreach c {TIEHIX1MA10TH TIELOX1MA10TH} {
    set q [get_lib_cells -quiet */$c]
    puts "tiecell $c : count=[llength $q]  -> $q"
}
puts "### CQ4-TIE-PROBE-END ###"

# Macro PGEN probe (dispositions the set_false_path -to list): do the top-level
# macros rom0/npuram0 expose a PGEN pin, and do the tile ram0 pins resolve?
puts "### CQ4-PGEN-PROBE-START ###"
foreach p {mcu0/rom0/PGEN mcu0/npuram0/PGEN mcu0/hart0/ram0/PGEN mcu0/hart1/ram0/PGEN mcu0/hart2/ram0/PGEN mcu0/hart3/ram0/PGEN} {
    puts "pin $p : count=[llength [get_pins -quiet $p]]"
}
puts "### CQ4-PGEN-PROBE-END ###"

# hart_tile design/instance probe (dispositions set_dont_touch hart_tile)
puts "### CQ4-HART-PROBE-START ###"
puts "designs hart_tile : [llength [get_designs -quiet hart_tile]]"
puts "cells mcu0/hart* : [get_cells -quiet mcu0/hart*]"
puts "### CQ4-HART-PROBE-END ###"

exit
