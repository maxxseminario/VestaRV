################################################################################
#
# Genus TCL -- COMPARATIVE (A/B) standalone synthesis of the vesta core.
#
# Skeleton copied from ../QSPI/tcl/QSPI.genus.tcl (same procs, lib-setup idiom,
# per-module boundary_opto discipline, generated-clock-of-source rule).
# STANDALONE block run: no power intent / CPF, no SRAM or pmk libs.
#
# The two (three) arms differ in EXACTLY ONE input: the vesta.vhd file selected
# by $env(VESTA_FILE). Every other source file, every attribute, every
# constraint and every effort level below is shared verbatim.
#
#   ARM_NAME       report/basename prefix          (env)
#   VESTA_FILE     absolute path to vesta.vhd      (env)
#   IF_AHEAD_PARAM optional: "false" to add [list ENABLE_IF_AHEAD false] to the
#                  elaborate -parameters list (control arm only; unset = omit)
#
################################################################################

set OUTPUT_DIR       out
set REPORT_DIR       rpt

set TOP_MODULE       vesta

if {![info exists env(ARM_NAME)]}   { puts "FATAL: ARM_NAME not set";   exit 1 }
if {![info exists env(VESTA_FILE)]} { puts "FATAL: VESTA_FILE not set"; exit 1 }
set ARM        $env(ARM_NAME)
set VESTA_FILE $env(VESTA_FILE)
set BASENAME   $ARM

if {![file exists $VESTA_FILE]} { puts "FATAL: VESTA_FILE $VESTA_FILE missing"; exit 1 }

puts "### ARM ### name=$ARM"
puts "### ARM ### vesta.vhd=$VESTA_FILE"

# 25 MHz smclk class, same as the proven flows.
set base_freq        25
set freq_mult        1
set MCLK_FREQ        [expr $base_freq * $freq_mult]
set MCLK_PERIOD      [expr 1 / [expr $MCLK_FREQ * 0.001]]
puts "Target clk frequency: $MCLK_FREQ MHz (period $MCLK_PERIOD ns)"

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

# Keep the netlist module named plain "vesta" (suppress the generic-value suffix).
set_db hdl_parameter_naming_style ""

# Std-cell HVT ECSM only. No SRAM IP dir, no pmk (no power intent in this run).
set_db init_lib_search_path [list \
	/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10/ecsm-timing/ ]

set_db library [list \
	scadv10_cln65gp_hvt_tt_1p0v_25c.lib]

set_db tns_opto true
set_db auto_ungroup none
set_db lp_insert_clock_gating true
set_db lp_clock_gating_register_aware true

set_dont_use TIEHIX1MA10TH false
set_dont_use TIELOX1MA10TH false
set_db use_tiehilo_for_const duplicate

################################################################################
# Read HDL
################################################################################
# The shared source tree. IDENTICAL for every arm.
set MP /home/mseminario2/vestarv/.claude/worktrees/agent-a5e4251a43b6ada7a/hdl/common

# The real ARM ICG wrapper is ARM IP and therefore gitignored, so it exists only
# in the primary checkout (hdl/common/commune/) and not in the worktree copy.
# Read-only use; byte-identical for every arm.
set ICG /home/mseminario2/vestarv/hdl/common/commune/ClkGate_cmn65gp_ARM.vhd

puts "Reading HDL (vesta subset)"
set_db hdl_vhdl_read_version 2008

read_hdl -vhdl -library work $MP/constants.vhd
read_hdl -vhdl -library work $MP/MemoryMap.vhd
# The REAL ARM ICG cell, NOT sim/ClkGate.vhd (both declare entity ClkGate; the
# sim one wrecks the generated clock).
read_hdl -vhdl -library work $ICG
read_hdl -vhdl -library work $MP/vesta/div.vhd
read_hdl -vhdl -library work $MP/vesta/alu.vhd
read_hdl -vhdl -library work $MP/vesta/extend.vhd
# regfile_sbirq.vhd ONLY: regfile.vhd and regfile_firq.vhd declare the same entity.
read_hdl -vhdl -library work $MP/vesta/regfile_sbirq.vhd
read_hdl -vhdl -library work $MP/vesta/irq_handler.vhd
read_hdl -vhdl -library work $MP/vesta/loadext.vhd
read_hdl -vhdl -library work $MP/vesta/store_ext.vhd
read_hdl -vhdl -library work $MP/vesta/branch_valid.vhd
read_hdl -vhdl -library work $MP/vesta/csr_unit.vhd
read_hdl -vhdl -library work $MP/vesta/fpu_simple.vhd
read_hdl -vhdl -library work $MP/vesta/fpu.vhd
read_hdl -vhdl -library work $MP/vesta/datapath.vhd
read_hdl -vhdl -library work $MP/vesta/maindec.vhd
read_hdl -vhdl -library work $MP/vesta/controller.vhd
read_hdl -vhdl -library work $MP/vesta/c_dec.vhd
read_hdl -vhdl -library work $MP/vesta/pmp_unit.vhd
# LAST, and the ONLY file that differs between arms.
read_hdl -vhdl -library work $VESTA_FILE

################################################################################
# Elaboration
################################################################################
# Explicit, nested-list parameter form. A flat {NAME value} list is read
# POSITIONALLY and errors CDFG-601.
set PARAMS [list \
	[list NUM_IRQS          16   ] \
	[list ENABLE_MUL        true ] \
	[list ENABLE_DIV        true ] \
	[list ENABLE_ATOMICS    true ] \
	[list ENABLE_COMPRESSED true ] \
	[list ENABLE_BITMANIP   true ] \
	[list ENABLE_ZICOND     false] \
	[list ENABLE_ZCB        false] \
	[list ENABLE_ZIMOP      false] \
	[list ENABLE_ZIHINT     false] \
	[list ENABLE_ZIHPM      false] \
	[list ENABLE_ZAWRS      false] \
	[list ENABLE_ZABHA      false] \
	[list ENABLE_ZACAS      false] \
	[list ENABLE_ZICBOZ     false] \
	[list ENABLE_ZCMP       false] \
	[list ENABLE_ZCMT       false] \
	[list ENABLE_ZBKB       false] \
	[list ENABLE_ZBKC       false] \
	[list ENABLE_ZBKX       false] \
	[list ENABLE_ZKN        false] \
	[list ENABLE_ZFINX      false] \
	[list ENABLE_TRAPCSR    false] \
	[list ENABLE_UMODE      false] \
	[list ENABLE_PMP        false] \
	[list PMP_ENTRIES       16   ] \
	[list ENABLE_DEBUG      false] \
	[list TRACE_ENABLE      false] ]

# Control arm only: force the fetch-ahead OFF on the modified RTL.
if {[info exists env(IF_AHEAD_PARAM)] && $env(IF_AHEAD_PARAM) ne ""} {
	lappend PARAMS [list ENABLE_IF_AHEAD $env(IF_AHEAD_PARAM)]
}

puts "### ARM ### elaborate parameters: $PARAMS"
puts "Elaborating $TOP_MODULE"
elaborate $TOP_MODULE -parameters $PARAMS

set DESIGN_NAME [get_db [get_db designs] .name]
puts "Elaborated design name: $DESIGN_NAME"
if {$DESIGN_NAME ne "vesta"} {
	puts "WARNING: design name is '$DESIGN_NAME', not 'vesta' -- fix naming"
}

################################################################################
# POST-ELABORATE SANITY CENSUS (the flow's institutional lesson: Genus exits 0
# on a TCL abort and leaves stale reports, so assert the design is the one we
# think it is and die loudly otherwise).
################################################################################
set n_daddr [llength [get_db ports data_addr*]]
puts "### CENSUS ### data_addr port bits: $n_daddr"
if {$n_daddr != 32} {
	puts "FATAL CENSUS: data_addr has $n_daddr bits, expected 32"
	exit 1
}

set icg_insts [get_db insts *cg_clk_cpu*]
puts "### CENSUS ### cg_clk_cpu instances: [llength $icg_insts] -> $icg_insts"
if {[llength $icg_insts] != 1} {
	puts "FATAL CENSUS: expected exactly 1 *cg_clk_cpu* instance, found [llength $icg_insts]"
	exit 1
}

set n_seq -1
if {[catch {set n_seq [llength [get_db insts -if {.is_sequential == true}]]} emsg]} {
	puts "### CENSUS ### sequential-inst query failed: $emsg"
} else {
	puts "### CENSUS ### elaborated sequential instances: $n_seq"
}
puts "### CENSUS ### total elaborated instances: [llength [get_db insts]]"

# Gate-sim fix: per-MODULE boundary_opto disable (root attr ignored in 19.15).
set_db [get_db modules] .boundary_opto false
puts "boundary_opto disabled on [llength [get_db modules]] modules"

################################################################################
# Constraints
################################################################################

# --- Primary clock -------------------------------------------------------------
create_clock -name mclk -period $MCLK_PERIOD port:$TOP_MODULE/clk

# --- The ICG-gated core clock. divide_by 1: an ICG masks pulses, it does NOT
#     stretch the period. clk_cpu is a PORT of vesta (driven by cg_clk_cpu).
#     NO set_clock_groups: putting clk_cpu in an asynchronous group would
#     silently false-path every core path and report meaningless slack.
create_generated_clock -name clk_cpu -divide_by 1 \
	-source port:$TOP_MODULE/clk port:$TOP_MODULE/clk_cpu

# --- Cost/path groups (as the tile flow) ---
define_cost_group -name mclk_group    -weight 1
define_cost_group -name clk_cpu_group -weight 1
path_group -from mclk    -group mclk_group
path_group -from clk_cpu -group clk_cpu_group

# --- I/O budgets: half-period, identical in every arm ---
set DATA_IN [get_db ports { \
	sleep hart_id[*] read_data[*] mask[*] mem_ready sc_fail_ext resv_valid_ext \
	irq_vector[*] irq_priority[*] irq_en[*] irq_recursion_en \
	dbg_haltreq dbg_resethaltreq resetn }]
set DATA_OUT [get_db ports { \
	data_addr[*] wen[*] write_data[*] lr_sc_bus[*] amo_lock isr_ret \
	dbg_halted trap_flag a0[*] }]
puts "### CENSUS ### timed input ports: [llength $DATA_IN]  output ports: [llength $DATA_OUT]"

set_input_delay  -clock [get_db clocks clk_cpu] $IO_BUDGET_HALF $DATA_IN
set_output_delay -clock [get_db clocks clk_cpu] $IO_BUDGET_HALF $DATA_OUT

# Async reset: POR-synchronized deassertion, huge recovery margin at 25 MHz.
set_false_path -from [get_db ports resetn]
# hart_id is a per-instance strap, quasi-static for the life of the chip.
set_false_path -from [get_db ports hart_id[*]]

################################################################################
# Top Design Attributes
################################################################################
set_max_transition 0.5
set_load 0.600 [get_ports -filter "direction==out"]
set_driving_cell -lib_cell INVX1MA10TH [get_ports -filter "direction==in"]

################################################################################
# Synthesis -- high effort
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
report_area   > $REPORT_DIR/$BASENAME.area.rpt
report_gates  > $REPORT_DIR/$BASENAME.gates.rpt
report_timing > $REPORT_DIR/$BASENAME.timing.rpt

# The point of the exercise: a regression must show in MORE THAN ONE endpoint.
report_timing -max_paths 20 -nworst 5 > $REPORT_DIR/$BASENAME.timing20.rpt

# Per-cost-group worst paths.
report_timing -group clk_cpu_group -max_paths 5 > $REPORT_DIR/$BASENAME.clk_cpu_group.rpt
report_timing -group mclk_group    -max_paths 5 > $REPORT_DIR/$BASENAME.mclk_group.rpt

# No write_hdl / write_sdf: not needed here, and they cost minutes.

################################################################################
# v2 ADDITIONS -- the reports the v1 script lacked.
#
# WHY: with set_input_delay 20000 + set_output_delay 20000 on a 40000 ps period,
# a pure port-to-port COMBINATIONAL feed-through gets a budget of exactly ZERO
# (Required 20000 - Input Delay 20000 = 0), so every such path reports a large
# negative slack in EVERY arm. That is a constraint artefact, not a timing
# verdict. The numbers below are the ones that actually compare.
################################################################################

# (a) The core's own worst REGISTER-TO-REGISTER paths, which the I/O budget hides.
if {[catch {
	report_timing -from [all_registers] -to [all_registers] -max_paths 10 \
		> $REPORT_DIR/$BASENAME.reg2reg.rpt
} err]} {
	puts "### ARM ### reg2reg via all_registers failed: $err -- retrying via get_db"
	catch {
		set SEQS [get_db insts -if {.is_sequential == true}]
		report_timing -from $SEQS -to $SEQS -max_paths 10 > $REPORT_DIR/$BASENAME.reg2reg.rpt
	}
}

# (b) The landing site of the change: the fetch_addr mux drives data_addr.
#     This report exists in BOTH arms and is directly comparable.
catch {
	report_timing -to [get_db ports data_addr[*]] -max_paths 10 \
		> $REPORT_DIR/$BASENAME.to_data_addr.rpt
}

# (c) Anything named after the new signals. On the base arm these do not exist,
#     so the file says so rather than the run aborting.
set IFA [list]
foreach pat {*if_ahead* *fetch_addr* *split_ready* *pc_plus_6* *if_ahead_addr*} {
	catch {
		foreach o [get_db insts $pat] { lappend IFA $o }
	}
}
set IFA [lsort -unique $IFA]
puts "### ARM ### if_ahead-named instances: [llength $IFA] -> $IFA"
if {[llength $IFA] > 0} {
	catch { report_timing -from $IFA -max_paths 10 > $REPORT_DIR/$BASENAME.ifahead_from.rpt }
	catch { report_timing -to   $IFA -max_paths 10 > $REPORT_DIR/$BASENAME.ifahead_to.rpt }
} else {
	set fh [open $REPORT_DIR/$BASENAME.ifahead_from.rpt w]
	puts $fh "no instance named *if_ahead*/*fetch_addr*/*split_ready*/*pc_plus_6* in arm $BASENAME"
	close $fh
	set fh [open $REPORT_DIR/$BASENAME.ifahead_to.rpt w]
	puts $fh "no instance named *if_ahead*/*fetch_addr*/*split_ready*/*pc_plus_6* in arm $BASENAME"
	close $fh
}


toc
set total_run_time [getHMS $START_TIME $STOP_TIME]
puts "Genus vesta_ab arm '$ARM' run is complete. Run time $total_run_time"

exit
