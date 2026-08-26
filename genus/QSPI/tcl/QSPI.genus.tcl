################################################################################
#
# Genus TCL script -- QSPI standalone peripheral synthesis
# (digital-peripherals program, Stage (a)+(b) gate-closure).
#
# Derived from tcl/hart_tile.genus.tcl (same procs, lib-setup idiom, M9b
# per-module boundary_opto discipline, M9c generated-clock-of-source rule).
# This is a STANDALONE block run: no power intent / CPF, no SRAM/pmk libs.
#
# ---------------------------------------------------------------------------
# CLOCK TREE OF THE BLOCK (the HONEST SDC -- see the report-back for rationale)
# ---------------------------------------------------------------------------
# QSPI is a genuine multi-clock block. There are THREE clock inputs at the
# boundary plus TWO internally-generated (ICG-gated) clocks:
#
#   clk         smclk-class serial-core source, 25 MHz / 40 ns. NO leaf flop
#               is clocked directly by clk -- it only feeds the two ClkGate
#               (PREICGX1BA10TH) instances through an inverter (ClkIn => not clk).
#
#   ClkMem      register-bus clock (adddec clock-gates clk_periph by
#               EnMemPeriph in the SoC; at this block boundary it is an input
#               clock). 25 MHz / 40 ns. Clocks the software registers
#               (QSPIxCR/CMD/ADR/TX), the clear-pulse / launch flops, and the
#               synchronous read register rdata_out.
#
#   EnMemPeriph active-low peripheral select. Used as a CLOCK by the registered-
#               read pre-latch (reg_sync: falling_edge(EnMemPeriph) latches the
#               inverted volatile registers QSPIxRX/QSPIxSR into *_ltch). It is
#               ALSO combinational data (slot decode, write qualify). Declared
#               as a real clock so those two negedge flops are constrained; its
#               data fan-out is budgeted against ClkMem.
#
#   clk_baud_src  GENERATED clock = ICG(not clk, en_clk_baud_src). divide_by 1
#               (an ICG only masks pulses, it does NOT stretch the period -- the
#               M9c clk_cpu precedent). Clocks the baud down-counter.
#
#   clk_baud    GENERATED clock = ICG(not clk, en_clk_baud). divide_by 1. Clocks
#               the entire serial-core FSM (state, sck, edge_cnt, t_sreg,
#               rx_sreg, the transaction-local latched fields, and the status
#               flags txeif/rxfull/tcif + QSPIxRX).
#
# SERIAL-SIDE RATE DECISION (per the kickoff -- do NOT fabricate false paths):
#   The FSM registers are NOT on a divide-by-N flop chain; they sit on clk_baud,
#   which is an ENABLE-gated version of clk (period preserved). With BR=0 the
#   baud counter is permanently 0 so en_clk_baud is high every cycle and
#   clk_baud pulses on consecutive `not clk` edges -- i.e. the worst-case
#   register-to-register separation in the serial core is one 40 ns clk period.
#   Therefore the HONEST constraint for the serial domain is same-period 25 MHz
#   (divide_by 1), and clk_baud->clk_baud paths are timed at 40 ns, NOT relaxed
#   to the few-MHz average SCK rate. (rpt/QSPI.genus.baud2baud.rpt is the
#   negative control proving these paths are real and timed, not cut.)
#
# CLOCK GROUPS / CDC:
#   The crossings between the serial core (clk / clk_baud*) and the register bus
#   (ClkMem / EnMemPeriph) are ASYNCHRONOUS BY DESIGN -- level-held handshakes
#   with no single-cycle relationship (RTL header + fsm_proc CDC note in
#   QSPI.vhd: qspi_launch is a held level sampled by the FSM, the W1C clr_*
#   pulses cross as async resets, QSPIxRX/flags are snapshot-latched on the
#   EnMemPeriph select edge). These are true CDC handshakes, so the three
#   groups are declared -asynchronous. This is NOT the M9c mistake (which
#   false-pathed a SINGLE physical gated clock's own single-cycle paths):
#   clk_baud is a genuinely distinct gated+inverted clock and every crossing
#   here is a designed async handshake, while the real single-cycle paths
#   (clk_baud<->clk_baud, ClkMem<->ClkMem) stay inside one group and ARE timed.
#
################################################################################

set INPUT_DIR        ../common/in
set OUTPUT_DIR       out
set REPORT_DIR       rpt
set HDL_DIR          ../../hdl

set TOP_MODULE       QSPI
set BASENAME         QSPI.genus

# 25 MHz smclk class, same as the proven flows.
set base_freq        25
set freq_mult        1
set MCLK_FREQ        [expr $base_freq * $freq_mult]
set MCLK_PERIOD      [expr 1 / [expr $MCLK_FREQ * 0.001]]
puts "Target clk/ClkMem frequency: $MCLK_FREQ MHz (period $MCLK_PERIOD ns)"

# I/O budget: half-period default on all registered interfaces.
set IO_BUDGET_HALF   [expr $MCLK_PERIOD / 2.0]  ;# 20 ns

################################################################################
# Procedures (verbatim from the tile flow)
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

# Keep the netlist module named plain "QSPI" (suppress the generic-value suffix).
set_db hdl_parameter_naming_style ""

# Std-cell HVT ECSM only. No SRAM IP dir, no pmk (no power intent in this run).
set_db init_lib_search_path [list \
	$INPUT_DIR/ \
	/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10/ecsm-timing/ ]

set_db init_hdl_search_path [list \
	$HDL_DIR ]

set_db library [list \
	scadv10_cln65gp_hvt_tt_1p0v_25c.lib]

set_db tns_opto true
set_db auto_ungroup none
# boundary_opto: root attr is a no-op in Genus 19.15 -- applied per-module
# post-elaborate (M9b). auto_ungroup none also preserves the ClkGate wrappers
# so the generated-clock master pins survive to synthesis.
set_db lp_insert_clock_gating true
set_db lp_clock_gating_register_aware true

set_dont_use TIEHIX1MA10TH false
set_dont_use TIELOX1MA10TH false
set_db use_tiehilo_for_const duplicate

################################################################################
# Read HDL -- QSPI's RTL dependency set (cell_list_behavioral.txt order, with
# the SYNTHESIZABLE ClkGate wrapper substituted for the sim ClkGate).
################################################################################
puts "Reading HDL (QSPI subset)"
set MP $HDL_DIR/common

# VHDL sources use 2008 delimited comments
set_db hdl_vhdl_read_version 2008
read_hdl -vhdl -library work $MP/constants.vhd
read_hdl -vhdl -library work $MP/MemoryMap.vhd
read_hdl -vhdl -library work $MP/commune/ClkGate_cmn65gp_ARM.vhd
read_hdl -vhdl -library work $MP/commune/ClkDivPower2.vhd
read_hdl -vhdl -library work $MP/periph/QSPI.vhd

################################################################################
# Elaboration
################################################################################
puts "Elaborating $TOP_MODULE"
elaborate $TOP_MODULE

set DESIGN_NAME [get_db [get_db designs] .name]
puts "Elaborated design name: $DESIGN_NAME"
if {$DESIGN_NAME ne "QSPI"} {
	puts "WARNING: design name is '$DESIGN_NAME', not 'QSPI' -- fix naming"
}

# M9b GATE-SIM FIX: per-MODULE boundary_opto disable (root attr ignored).
set_db [get_db modules] .boundary_opto false
puts "boundary_opto disabled on [llength [get_db modules]] modules"

# NO power intent / CPF for this standalone block run.

################################################################################
# Constraints
################################################################################

# --- Primary clocks (all 40 ns; see header for the domain map) ---
create_clock -name clk    -period $MCLK_PERIOD [get_ports clk]
create_clock -name ClkMem -period $MCLK_PERIOD [get_ports ClkMem]
# EnMemPeriph is the negedge clock of the reg_sync read pre-latch flops.
create_clock -name EnMemPeriph -period $MCLK_PERIOD [get_ports EnMemPeriph]

# --- Generated (ICG-gated) serial clocks: divide_by 1 of clk (M9c rule). Both
#     ICGs take `not clk`; Genus traces the inverter -- the intra-serial paths
#     are common-mode w.r.t. that inversion so timing is unaffected. ---
create_generated_clock -name clk_baud_src -divide_by 1 \
	-source port:$TOP_MODULE/clk hpin:$TOP_MODULE/cg_clk_baud_src/ClkOut
create_generated_clock -name clk_baud -divide_by 1 \
	-source port:$TOP_MODULE/clk hpin:$TOP_MODULE/cg_clk_baud/ClkOut

# --- CDC: serial core vs register bus vs select are asynchronous (see header).
#     Real single-cycle paths stay INSIDE a group and are timed. ---
set_clock_groups -asynchronous \
	-group {clk clk_baud_src clk_baud} \
	-group {ClkMem} \
	-group {EnMemPeriph}

# --- Cost/path groups ---
define_cost_group -name clk_baud_group -weight 1
define_cost_group -name clkmem_group   -weight 1
path_group -from clk_baud -group clk_baud_group
path_group -from ClkMem   -group clkmem_group

# --- I/O budgets ---------------------------------------------------------------
# Register-bus inputs: software-written registers + the write decode. Registered
# at the ClkMem edge -> half-period. EnMemPeriph carries a data role (slot decode
# / write qualify) budgeted here too; it is quasi-static (stable for the whole
# selected access) so 20 ns is generous.
set MEM_IN  [get_db ports {WEn[*] MABPart[*] wdata[*] EnMemPeriph}]
set_input_delay  -clock [get_db clocks ClkMem] $IO_BUDGET_HALF $MEM_IN

# Register-bus outputs: rdata_out is a ClkMem flop; irq_* are (flag AND enable)
# observed by the smclk-domain interrupt router -> budget against ClkMem.
set_output_delay -clock [get_db clocks ClkMem] $IO_BUDGET_HALF [get_db ports {rdata_out[*]}]
set_output_delay -clock [get_db clocks ClkMem] $IO_BUDGET_HALF [get_db ports {irq_tc irq_rxf}]

# Serial (clk_baud) side: io_in is sampled by the FSM on clk_baud; sck/cs/io
# outputs are driven from clk_baud flops (io_out/io_dir combinational off the
# clk_baud-domain state + t_sreg). Half-period each way. The external SPI flash
# runs at the slow average SCK rate, so these budgets carry large real margin.
set_input_delay  -clock [get_db clocks clk_baud] $IO_BUDGET_HALF [get_db ports {io_in[*]}]
set_output_delay -clock [get_db clocks clk_baud] $IO_BUDGET_HALF \
	[get_db ports {sck_out cs_out io_out[*] io_dir[*]}]

# Static direction straps: sck_dir/cs_dir are hardwired '1' (frozen entity
# note) -- constant outputs, no timed path.
set_false_path -to [get_db ports {sck_dir cs_dir}]

# Async reset: POR-synchronized deassertion, huge recovery margin at 25 MHz
# (same treatment the proven flows give resetn).
set_false_path -from [get_db ports resetn]

################################################################################
# Top Design Attributes
################################################################################
set_max_transition 0.5
set_load 0.600 [get_ports -filter "direction==out"]
set_driving_cell -lib_cell INVX1MA10TH [get_ports -filter "direction==in"]

################################################################################
# Synthesis -- high effort (as the proven flows)
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

# Honesty negative control: the serial-core single-cycle paths must be REAL and
# timed at 40 ns (an empty report here would mean the serial domain was wrongly
# cut -- the M9c failure mode).
report_timing -from [get_db clocks clk_baud] -to [get_db clocks clk_baud] -max_paths 10 \
	> $REPORT_DIR/$BASENAME.baud2baud.rpt
report_timing -group clkmem_group -max_paths 10 \
	> $REPORT_DIR/$BASENAME.clkmem.rpt

################################################################################
# Output Files
################################################################################
write_script > $OUTPUT_DIR/$BASENAME.g
write_hdl    > $OUTPUT_DIR/$BASENAME.v
write_sdc    > $OUTPUT_DIR/$BASENAME.sdc
write_sdf    > $OUTPUT_DIR/$BASENAME.sdf

toc
set total_run_time [getHMS $START_TIME $STOP_TIME]
puts "Genus QSPI run is complete. Run time $total_run_time"

exit
