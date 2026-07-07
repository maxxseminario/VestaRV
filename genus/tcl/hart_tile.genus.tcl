################################################################################
#
# Genus TCL script -- hart_tile TILE-ONLY synthesis (M14 physical flow)
#
# Derived from tcl/MCU_MP.genus.tcl (the flat 4-hart flow). This synthesizes
# ONE hart_tile standalone: the M13 tile extraction made all four hart
# instances structurally identical, so M14 hardens a single tile netlist and
# the top-level flow places it 4x (the flat flow uniquified the tile into
# hart_tile_PC_RST_VAL0_SH_AW15{,_1,_2,_3} -- this run is what delivers the
# one-netlist goal).
#
# THE SDC BUG FIX (M9c note in ~/vesta_docs/multicore_plan.md): the flat flow
# put clk_cpu<h> in its OWN clock domain, which false-paths every
# clk_cpu<->mclk path BY CONSTRUCTION. But clk_cpu IS mclk -- the same
# physical clock, gated by ClkGate inside vesta (en_clk_cpu). Core->adddec->
# boundary-register paths are real single-cycle mclk paths and were silently
# unconstrained in every flat run. Here clk_cpu is a GENERATED clock of mclk
# (divide_by 1, same domain), so those paths are timed. Verification reports
# rpt/hart_tile.genus.{cpu2mclk,mclk2cpu}.rpt must show REAL PATHS (the flat
# flow's equivalent cross-domain query returns none -- that is the
# constraint-level negative control).
#
# Registered tile boundary (M13, depth 1 on mclk): every shared-bus + IRQ
# port is flop->pin or pin->flop inside the tile, so I/O budgets are a clean
# half-period split. UNREGISTERED pins get explicit budgets/exceptions:
#   sleep         input, gates clk_cpu (SPI0 XIP stall). External side gets
#                 the larger share (25 ns): at top it travels SPI0->hart0 pin
#                 after placement; inside the tile it is a short hop into the
#                 ClkGate enable. A LATE sleep = core eats garbage flash_dout
#                 mid-XIP (M13 header) -- this budget is the contract that
#                 makes the top-level path checkable.
#   flash_mab/flash_mem_en  combinational core->adddec->pin (XIP address):
#                 tile keeps 30 ns (real logic depth), external 10 ns.
#   flash_dout    input into the core's read-data path (deep): external
#                 10 ns, tile keeps 30 ns.
#   flash_clk_mem GATED CLOCK OUTPUT (adddec cg_flash) -- declared as a
#                 generated clock at the port, never given a data budget.
#   hart_id/hw_clint_en/tcm_pgen  static straps -> false path.
#   trap_flag/a0  quasi-static observation -> false path.
#
################################################################################

set INPUT_DIR        in
set IP_DIR           /home/mseminario2/chips/myshkin/ip
set OUTPUT_DIR       out
set REPORT_DIR       rpt
set HDL_DIR          ../hdl

set TOP_MODULE       hart_tile
set BASENAME         hart_tile.genus

# 25 MHz, same as the proven flat flow.
set base_freq        25
set freq_mult        1
set MCLK_FREQ        [expr $base_freq * $freq_mult]
set MCLK_PERIOD      [expr 1 / [expr $MCLK_FREQ * 0.001]]
puts "Target mclk frequency: $MCLK_FREQ MHz (period $MCLK_PERIOD ns)"

# I/O budget split (ns) at the registered boundary + the unregistered pins.
set IO_BUDGET_HALF   [expr $MCLK_PERIOD / 2.0]  ;# 20 ns each side, reg boundary
set SLEEP_EXT        25.0                       ;# sleep: external side is long
set FLASH_OUT_EXT    10.0                       ;# flash_mab/mem_en: tile keeps 30
set FLASH_IN_EXT     10.0                       ;# flash_dout: tile keeps 30

################################################################################
# Procedures (as in the flat flow)
################################################################################
proc getHMS {start stop} {
	set s_per_m 60
	set m_per_h 60
	set s_per_h [expr $s_per_m * $m_per_h]
	set s_rem [expr [expr $stop - $start] / 1000]
	set h [expr $s_rem / $s_per_h]
	set s_rem [expr $s_rem - [expr $h * $s_per_h]]
	set m [expr $s_rem / $s_per_m]
	set s_rem [expr $s_rem - [expr $m * $s_per_m]]
	set hms [format "%02d:%02d:%02d" $h $m $s_rem]
	return $hms
}
proc printRuntime {start stop} { puts "### UNL RUNTIME ### : [getHMS $start $stop]" }
proc tic {} { global START_TIME; set START_TIME [clock clicks -milliseconds] }
proc toc {} { global START_TIME STOP_TIME; set STOP_TIME [clock clicks -milliseconds]; printRuntime $START_TIME $STOP_TIME }

################################################################################
# Root Attributes
################################################################################
tic
set_db information_level 3

# Keep the netlist module named plain "hart_tile" (default naming appends the
# generic values: hart_tile_PC_RST_VAL0_SH_AW15). The tile netlist/LEF/LIB/SDF
# must all carry ONE name so the hierarchical top and the gate sim resolve the
# 4 instances against it.
set_db hdl_parameter_naming_style ""

set_db init_lib_search_path [list \
	$IP_DIR/sram1p16k_hvt_pg \
	$INPUT_DIR/ \
	/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10/ecsm-timing/ ]

set_db init_hdl_search_path [list \
	$HDL_DIR ]

# Tile macros: only the TCM SRAM (no ROM in a tile).
set_db library [list \
	sram1p16k_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib \
	scadv10_cln65gp_hvt_tt_1p0v_25c.lib]

set_db tns_opto true
set_db auto_ungroup none
# boundary_opto: root attr is OBSOLETED in Genus 19.15 -- the effective
# per-module form is applied post-elaborate below (M9b lesson).
set_db lp_insert_clock_gating true
set_db lp_clock_gating_register_aware true

set_dont_use TIEHIX1MA10TH false
set_dont_use TIELOX1MA10TH false
set_db use_tiehilo_for_const duplicate

################################################################################
# Read HDL -- the hart_tile subset of the MCU_MP tree
################################################################################
puts "Reading HDL (hart_tile subset)"
set MP $HDL_DIR/MCU_MP

# Packages + the synthesizable clock-gate wrapper
read_hdl -vhdl -library work $MP/constants.vhd
read_hdl -vhdl -library work $MP/macros/macros.vhd
read_hdl -vhdl -library work $MP/MemoryMap.vhd
read_hdl -vhdl -library work $MP/commune/ClkGate_cmn65gp_ARM.vhd

# Vesta core
read_hdl -vhdl -library work $MP/vesta/div.vhd
read_hdl -vhdl -library work $MP/vesta/alu.vhd
read_hdl -vhdl -library work $MP/vesta/extend.vhd
read_hdl -vhdl -library work $MP/vesta/regfile_sbirq.vhd
read_hdl -vhdl -library work $MP/vesta/irq_handler.vhd
read_hdl -vhdl -library work $MP/vesta/loadext.vhd
read_hdl -vhdl -library work $MP/vesta/store_ext.vhd
read_hdl -vhdl -library work $MP/vesta/branch_valid.vhd
read_hdl -vhdl -library work $MP/vesta/csr_unit.vhd
read_hdl -vhdl -library work $MP/vesta/datapath.vhd
read_hdl -vhdl -library work $MP/vesta/maindec.vhd
read_hdl -vhdl -library work $MP/vesta/controller.vhd
read_hdl -vhdl -library work $MP/vesta/c_dec.vhd
read_hdl -vhdl -library work $MP/vesta/vesta.vhd

# Tile = core + decoder + TCM (sram1p16k resolves from the .lib)
read_hdl -vhdl -library work $MP/adddec.vhd
read_hdl -vhdl -library work $MP/hart_tile.vhd

################################################################################
# Elaboration
################################################################################
puts "Elaborating $TOP_MODULE"
elaborate $TOP_MODULE

# Verify the parameter-naming suppression took (the netlist module name is the
# contract with the hierarchical top + gate sim).
set DESIGN_NAME [get_db [get_db designs] .name]
puts "Elaborated design name: $DESIGN_NAME"
if {$DESIGN_NAME ne "hart_tile"} {
	puts "WARNING: design name is '$DESIGN_NAME', not 'hart_tile' -- fix naming before the hierarchical top run"
}

# M9b GATE-SIM FIX: per-MODULE boundary_opto disable (root attr ignored).
set_db [get_db modules] .boundary_opto false
puts "boundary_opto disabled on [llength [get_db modules]] modules"

################################################################################
# Constraints
################################################################################

# --- Clocks: mclk at the tile clk port; clk_cpu as a GENERATED clock of mclk
# (SAME domain -- the M9c SDC bug fix; see header). ---
create_clock -name mclk -period $MCLK_PERIOD port:$TOP_MODULE/clk
create_generated_clock -name clk_cpu -divide_by 1 \
	-source port:$TOP_MODULE/clk hpin:$TOP_MODULE/core/clk_cpu

# The XIP flash memory clock is a gated-clock OUTPUT (adddec cg_flash). Declare
# it so downstream consumers (SPI0 at top level) see a clock source, and so no
# data-style output budget is ever applied to it.
create_generated_clock -name flash_clk_mem -divide_by 1 \
	-source port:$TOP_MODULE/clk port:$TOP_MODULE/flash_clk_mem

# --- Cost/path groups ---
define_cost_group -name mclk_group    -weight 1
define_cost_group -name clk_cpu_group -weight 1
path_group -from mclk    -group mclk_group
path_group -from clk_cpu -group clk_cpu_group

# --- TCM PGEN: powered-down-macro timing exception (as in the flat flow) ---
set_false_path -to pin:$TOP_MODULE/ram0/PGEN

# --- I/O budgets ---
# Registered boundary (M13 depth-1 flops at both ends): half-period split.
set REG_IN  [get_db ports {msip_in mtip_in irq_ext[*] irq_en_ext[*] irq_prio_ext[*] irq_recursion_en sh_gnt sh_done sh_rdata[*] sh_scfail}]
set REG_OUT [get_db ports {isr_ret sh_req sh_we[*] sh_addr[*] sh_wdata[*] sh_lrsc[*] sh_lock}]
set_input_delay  -clock [get_db clocks mclk] $IO_BUDGET_HALF $REG_IN
set_output_delay -clock [get_db clocks mclk] $IO_BUDGET_HALF $REG_OUT

# Unregistered pins (explicit budgets -- the M13 carry-forward list).
set_input_delay  -clock [get_db clocks mclk] $SLEEP_EXT     [get_db ports sleep]
set_input_delay  -clock [get_db clocks mclk] $FLASH_IN_EXT  [get_db ports {flash_dout[*]}]
set_output_delay -clock [get_db clocks mclk] $FLASH_OUT_EXT [get_db ports {flash_mem_en flash_mab[*]}]

# Static straps and quasi-static observation pins.
set_false_path -from [get_db ports {hart_id[*] hw_clint_en tcm_pgen}]
set_false_path -to   [get_db ports {trap_flag a0[*]}]
# Async reset: deassertion is synchronized externally by the POR/reset fabric;
# recovery has huge margin at 25 MHz (same treatment the flat flow gave it by
# never constraining the POR-driven resetn).
set_false_path -from [get_db ports resetn]

################################################################################
# Top Design Attributes
################################################################################
set_max_transition 0.5
set_load 0.600 [get_ports -filter "direction==out"]
set_driving_cell -lib_cell INVX1MA10TH [get_ports -filter "direction==in"]

################################################################################
# Synthesis -- TIME-OPTIMIZED, AREA-RELAXED (as the flat flow)
################################################################################
puts "Synthesizing $TOP_MODULE"
set_db auto_ungroup none
set_db [get_db modules] .boundary_opto false
set_db lp_insert_clock_gating true
set_db lp_clock_gating_register_aware true
set_db syn_generic_effort high
set_db syn_map_effort     high
set_db syn_opt_effort     high
set_db tns_opto           true

add_tieoffs -all -verbose -high TIEHIX1MA10TH -low TIELOX1MA10TH

syn_generic
syn_map
syn_opt

################################################################################
# Reports
################################################################################
puts "Generating reports"
report_area           > $REPORT_DIR/$BASENAME.area.rpt
report_gates          > $REPORT_DIR/$BASENAME.gates.rpt
report_timing         > $REPORT_DIR/$BASENAME.timing.rpt
report_power -by_hierarchy -levels 4 > $REPORT_DIR/$BASENAME.power.rpt
report_clock_gating   > $REPORT_DIR/$BASENAME.clk.rpt
report_design_rules   > $REPORT_DIR/$BASENAME.rules.rpt

# SDC-fix verification: these crossings were FALSE (empty) in every flat run.
# They must now show real timed paths (core clk_cpu regs -> mclk boundary/TCM
# side and back). An empty report here = the bug is back.
report_timing -from [get_db clocks clk_cpu] -to [get_db clocks mclk] -max_paths 10 \
	> $REPORT_DIR/$BASENAME.cpu2mclk.rpt
report_timing -from [get_db clocks mclk] -to [get_db clocks clk_cpu] -max_paths 10 \
	> $REPORT_DIR/$BASENAME.mclk2cpu.rpt

################################################################################
# Output Files
################################################################################
write_script > $OUTPUT_DIR/$BASENAME.g
write_hdl    > $OUTPUT_DIR/$BASENAME.v
write_sdc    > $OUTPUT_DIR/$BASENAME.sdc
write_sdf    > $OUTPUT_DIR/$BASENAME.sdf

toc
set total_run_time [getHMS $START_TIME $STOP_TIME]
puts "Genus hart_tile run is complete. Run time $total_run_time"

exit
