################################################################################
#
# Basic Genus TCL script
#
################################################################################

# Project names and paths. These are relative to the Genus run directory.
set INPUT_DIR        in
set IP_DIR           ../ip
set IC_DIR           ../ic
set OUTPUT_DIR       out
set REPORT_DIR       rpt
set HDL_DIR          ../hdl
set SCRIPTS_DIR      tcl

# Top-level entity name and the prefix used for output files.
set TOP_MODULE       MCU		
set BASENAME         ${TOP_MODULE}.genus

# Target CPU frequency in MHz
# set CLKDCO_FREQ		120
# set CLKHFXT_FREQ	100
# set CLKLFXT_FREQ	0.032768
# set I2CSCL_FREQ		5
# set SPISCK_FREQ		50
# set FASTEST_FREQ	120
# set CLKCPU_FREQ		100


# # Target CPU frequency in MHz
# set CLKHFXT_FREQ	35
# set CLKLFXT_FREQ	0.032768
# set I2CSCL_FREQ		5
# set SPISCK_FREQ		35
# set FASTEST_FREQ	35
# set CLKCPU_FREQ		35

# Target CPU frequency in MHz
set base_freq 		25
set freq_mult 		1
set CLKHFXT_FREQ	[expr $base_freq * $freq_mult]
set CLKLFXT_FREQ	0.032768
set I2CSCL_FREQ		5
set SPISCK_FREQ		$CLKHFXT_FREQ
set FASTEST_FREQ	$CLKHFXT_FREQ
set CLKCPU_FREQ		$CLKHFXT_FREQ


# puts "Target CLKDCO frequency in MHz: $CLKDCO_FREQ"
puts "Target CLKHFXT frequency in MHz: $CLKHFXT_FREQ"
puts "Target CLKLFXT frequency in MHz: $CLKLFXT_FREQ"
puts "Target I2CSCL frequency in MHz: $I2CSCL_FREQ"
puts "Target SPISCK frequency in MHz: $SPISCK_FREQ"
puts "Target maximum frequency in MHz: $FASTEST_FREQ"
puts "Target CLKCPU frequency in MHz: $CLKCPU_FREQ"

# Find clock period, which has units of ps.
# set CLKDCO_PERIOD	[expr 1 / [expr $CLKDCO_FREQ * 0.001]]
set CLKHFXT_PERIOD	[expr 1 / [expr $CLKHFXT_FREQ * 0.001]]
set CLKLFXT_PERIOD	[expr 1 / [expr $CLKLFXT_FREQ * 0.001]]
set I2CSCL_PERIOD	[expr 1 / [expr $I2CSCL_FREQ * 0.001]]
set SPISCK_PERIOD	[expr 1 / [expr $SPISCK_FREQ * 0.001]]
set FASTEST_PERIOD	[expr 1 / [expr $FASTEST_FREQ * 0.001]]
#set CLKCPU_PERIOD	[expr 1 / [expr $CLKCPU_FREQ * 0.001]]

# puts "Target CLKDCO period in ns: $CLKDCO_PERIOD"
puts "Target CLKHFXT period in ns: $CLKHFXT_PERIOD"
puts "Target CLKLFXT period in ns: $CLKLFXT_PERIOD"
puts "Target I2CSCL period in ns: $I2CSCL_PERIOD"
puts "Target SPISCK period in ns: $SPISCK_PERIOD"
puts "Target minimum period in ns: $FASTEST_PERIOD"
#puts "Target CLKCPU period in ns: $CLKCPU_PERIOD"

################################################################################
# Procedures
################################################################################
proc getHMS {start stop} {
	# Constants for the conversion
	set s_per_m 60
	set m_per_h 60
	set s_per_h [expr $s_per_m * $m_per_h]
	# Find the number of seconds remaining to be divided into H:M:S
	set s_rem [expr [expr $stop - $start] / 1000]
	# Find the number of hours, minutes, seconds. Remove this time from the
	# remaining seconds at each stage.
	set h [expr $s_rem / $s_per_h]
	set s_rem [expr $s_rem - [expr $h * $s_per_h]]
	set m [expr $s_rem / $s_per_m]
	set s_rem [expr $s_rem - [expr $m * $s_per_m]]
	set s $s_rem
	set hms [format "%02d:%02d:%02d" $h $m $s]
	return $hms
}

proc printRuntime {start stop} {
	set hms [getHMS $start $stop]
	puts "### UNL RUNTIME ### : $hms"
}

proc tic {} {
	global START_TIME
	set START_TIME [clock clicks -milliseconds]
}

proc toc {} {
	global START_TIME
	global STOP_TIME
	set STOP_TIME [clock clicks -milliseconds]
	printRuntime $START_TIME $STOP_TIME
}

################################################################################
# Root Attributes
################################################################################

# Start timer
tic


# Set information level
set_db information_level 3
#set_db optimize_constant_0_flops false
#set_db optimize_constant_1_flops false

# 65 nm has both CCS and ECSM timing libraries--unclear if one is better.
# CCS: Current-based, Synopsys
# ECSM: Voltage-based, Cadence
# init_lib_search_paths is telling genus where to look for timimg files to use during elaboration
set_db init_lib_search_path [list \
	$IP_DIR/rom_hvt_pg \
	$IP_DIR/sram1p16k_hvt_pg \
	$INPUT_DIR/ \
	/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10/ecsm-timing/ ]	

#Specify the location of your RTL files to elaborate 
set_db init_hdl_search_path [list \
	$HDL_DIR ]

set_db library [list \
	rom_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib \
	sram1p16k_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib \
	scadv10_cln65gp_hvt_tt_1p0v_25c.lib]


# Set max leakage power, set max dynamic power, optimize tns, prevent ungrouping if debugging
#lp_insert_clock_gating add clock gates that will not clock circuit until specific section is needed. Saves power, but increases clock latency, therefore decreasing maximum clock frequency
set_db tns_opto true	
set_db auto_ungroup none
#set_db leakage_power_effort high
set_db lp_insert_clock_gating true
set_db lp_clock_gating_register_aware true

# Replace constant ties to '0' or '1' with tiehi/tielo cells for improved ESD
# robustness. These are marked as don't use in the lib, so manually override
# this setting
set_dont_use TIEHIX1MA10TH false
set_dont_use TIELOX1MA10TH false
set_db use_tiehilo_for_const duplicate


# Read the VHDL files. The order must follow dependencies.
puts "Reading HDL"

# Note it is not necessary to import any functional model for the ROM since
# Genus only needs to know timing information, which it gets from the .lib
# file.

read_hdl -vhdl -library work $HDL_DIR/MCU/commune/fixed_float_types_c.vhdl
read_hdl -vhdl -library work $HDL_DIR/MCU/commune/fixed_pkg_c.vhdl
read_hdl -vhdl -library work $HDL_DIR/MCU/commune/FPMac.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/commune/FPSigmoid.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/commune/TieLow.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/constants.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/macros/macros.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/MemoryMap.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/commune/TieLow.vhd 
read_hdl -vhdl -library work $HDL_DIR/MCU/commune/ClkGate_cmn65gp_ARM.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/commune/ClockMuxGlitchFree_cmn65gp_ARM.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/commune/CRC16.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/commune/ClkDivPower2.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/periph/GPIO.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/periph/SPI.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/periph/UART.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/periph/I2C.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/periph/TIMER.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/periph/SYSTEM.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/periph/NPU.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/periph/SARADC.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/periph/AFE_FSM.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/periph/AFE.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/vesta/div.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/vesta/alu.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/vesta/extend.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/vesta/regfile_sbirq.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/vesta/irq_handler.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/vesta/loadext.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/vesta/store_ext.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/vesta/branch_valid.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/vesta/csr_unit.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/vesta/datapath.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/vesta/maindec.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/vesta/controller.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/vesta/c_dec.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/vesta/vesta.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/adddec.vhd
read_hdl -vhdl -library work $HDL_DIR/MCU/$TOP_MODULE.vhd


################################################################################
# Elaboration
################################################################################

# Elaborate the top-level module into an intermediate format common to both
puts "Elaborating"
elaborate $TOP_MODULE


################################################################################
# Constraints 
################################################################################

#Assign signals within RTL to clock domains
# create_clock -name mclk	-period $FASTEST_PERIOD	port:$TOP_MODULE/system0/mclk_out
# create_clock -name SRAMclk	-period $FASTEST_PERIOD	hpin:$TOP_MODULE/system0/smclk_out

create_clock -name mclk			-domain mclk_domain			-period $FASTEST_PERIOD	hpin:$TOP_MODULE/system0/mclk_out
create_clock -name smclk		-domain smclk_domain		-period $FASTEST_PERIOD	hpin:$TOP_MODULE/system0/smclk_out
create_clock -name clk_cpu		-domain clk_cpu_domain		-period $FASTEST_PERIOD	hpin:$TOP_MODULE/core/clk_cpu
create_clock -name clk_lfxt		-domain clk_lfxt_domain		-period $CLKLFXT_PERIOD	hpin:$TOP_MODULE/system0/clk_lfxt_out
create_clock -name clk_hfxt		-domain clk_hfxt_domain		-period $CLKHFXT_PERIOD	hpin:$TOP_MODULE/system0/clk_hfxt_out
# create_clock -name clk_dco0		-domain clk_dco0_domain		-period $CLKDCO_PERIOD	hpin:$TOP_MODULE/system0/clk_dco0_out
# create_clock -name clk_dco1		-domain clk_dco1_domain		-period $CLKDCO_PERIOD	hpin:$TOP_MODULE/system0/clk_dco1_out
create_clock -name clk_scl0		-domain clk_scl0_domain		-period $I2CSCL_PERIOD	hpin:$TOP_MODULE/i2c0/SCL_IN
create_clock -name clk_scl1		-domain clk_scl1_domain		-period $I2CSCL_PERIOD	hpin:$TOP_MODULE/i2c1/SCL_IN
create_clock -name clk_sck0		-domain clk_sck0_domain		-period $SPISCK_PERIOD	hpin:$TOP_MODULE/spi0/sck_in
create_clock -name clk_sck1		-domain clk_sck1_domain		-period $SPISCK_PERIOD	hpin:$TOP_MODULE/spi1/sck_in

#Optmize which clock takes priority 

define_cost_group -name mclk_group			-weight 1
define_cost_group -name smclk_group			-weight 1
define_cost_group -name clk_cpu_group		-weight 1
define_cost_group -name clk_lfxt_group		-weight 1
define_cost_group -name clk_hfxt_group		-weight 1
# define_cost_group -name ClkDCO0Group		-weight 1
# define_cost_group -name clk_dco1_group	-weight 1
define_cost_group -name clk_scl0_group		-weight 1
define_cost_group -name clk_scl1_group		-weight 1
define_cost_group -name clk_sck0_group		-weight 1
define_cost_group -name clk_sck1_group		-weight 1

#Define which clocks to to which groups. Each of these clocks do not have same freq / phase, genus needs to take each into account to create accurate timing characterization

path_group -from mclk			-group mclk_group
path_group -from smclk			-group smclk_group
path_group -from clk_cpu		-group clk_cpu_group
path_group -from clk_lfxt		-group clk_lfxt_group
path_group -from clk_hfxt		-group clk_hfxt_group
# path_group -from ClkDCO0		-group ClkDCO0Group
# path_group -from clk_dco1		-group clk_dco1_group
path_group -from clk_scl0		-group clk_scl0_group
path_group -from clk_scl1		-group clk_scl1_group
path_group -from clk_sck0		-group clk_sck0_group
path_group -from clk_sck1		-group clk_sck1_group


# In some cases, it is impossible to have timing closure. Open the clock loop by setting false path, therefore stating that these no longer need to meet timing constraints.
# Some cases may include if there are two clocks to the same component that are not synchronized. Or if clocks are multiplexed, we can assume two are never active at once.

# If PGEN is set to SRAM, then the device is powered off, meaning that there is no longer a need to satisfy timimg. 
# If SRAM is powered back on, it may not be ready for operation until next clock cycle. 
# If these paths are not set false, max clock rate will be greatly limited, or genus will fail. Genus will uneccesarily insert many delay cells to other signal paths in order to meet timing of SRAM block.
set_false_path -to pin:$TOP_MODULE/rom0/PGEN
set_false_path -to pin:$TOP_MODULE/ram0/PGEN
set_false_path -to pin:$TOP_MODULE/ram1/PGEN
# set_false_path -to pin:$TOP_MODULE/ram2/PGEN


 
################################################################################
# Top Design Attributes 
################################################################################

# Set the maximum rise and fall times (in ns) for all signals in the design. 
# (This determines strength of core devices). If set lower, higher power gates will be needed. 
set_max_transition 0.5
 
# Set reasonable output pin capacitances (pF), which determine the drive strength of the output buffers. (Was 0.6)
# Can define these on an indivual port basis if desired.
# Set to 0.6 with the assumption that all of the ports will only be fed into other digital logic gates.
set_load 0.600 [get_ports -filter "direction==out"]

# Set the expected drive strength of the buffers driving the inputs, which is assumed to be very low to be conservative. A small inverter is used.
set_driving_cell -lib_cell INVX1MA10TH [get_ports -filter "direction==in"]

# Prevent Genus from significantly changing custom blocks. Allow resizing of the individual standard cells in order to optimize timing.


# set_db [get_db nets net:MCU/WEN[*]] .preserve true
set_db net:MCU/npu0/Decision[15] .dont_touch true



################################################################################
# Synthesis
################################################################################

# Synthesize the design and use the technology-mapped version, not the generic.
puts "Synthesizing top design"

# # Set max leakage power, set max dynamic power, optimize tns, prevent ungrouping if debugging, 
set_db auto_ungroup none
# #set_db leakage_power_effort high
set_db lp_insert_clock_gating true
set_db lp_clock_gating_register_aware true

# Replace constant ties to '0' or '1' with tiehi/tielo cells for improved ESD robustness.
# add_tieoffs -all -verbose -high TIEHIX1MA10TH -low TIELOX1MA10TH
# set_db use_tiehilo_for_const duplicate --this was copied from gen45
add_tieoffs -all -verbose -high TIEHIX1MA10TH -low TIELOX1MA10TH



#Generic: maps rtl to generic gates
#Mapping: Maps generic cells to cells within standard cell library provided 
#Optimization: Save on power, number of gates, delays, by altering netlist

syn_generic
syn_map
syn_opt

################################################################################
# Genus and Encounter Design Files
################################################################################

# Save individual report files.
puts "Generating reports"
report_area           > $REPORT_DIR/$BASENAME.area.rpt
report_gates          > $REPORT_DIR/$BASENAME.gates.rpt
report_timing         > $REPORT_DIR/$BASENAME.timing.rpt
report_power -by_hierarchy -levels 4 > $REPORT_DIR/$BASENAME.power.rpt
report_clock_gating   > $REPORT_DIR/$BASENAME.clk.rpt
report_design_rules   > $REPORT_DIR/$BASENAME.rules.rpt

################################################################################
# Output Files
#
# All of these except .sdf are redundant copies of the output of write_design.
#
# script            Design constraints
# hdl               Gate-level netlist in Verlilog (VHDL is not supported)
# sdc               Design constraints for later flows, such as Encounter
# sdf               Timing information for backannotating HDL for simulation
#
################################################################################
#.g is genus database file 
#.v is verilog netlist of design

# Switch to this command once Innovus is used instead of EDI.
#write_design -innovus -base_name $OUTPUT_DIR/$BASENAME

write_script > $OUTPUT_DIR/$BASENAME.g
write_hdl    > $OUTPUT_DIR/$BASENAME.v
write_sdc    > $OUTPUT_DIR/$BASENAME.sdc
write_sdf    > $OUTPUT_DIR/$BASENAME.sdf

################################################################################
# End of Script
################################################################################

# End timer
toc
set total_run_time [getHMS $START_TIME $STOP_TIME]
exec echo "Genus run is complete." | \
	# mail -s "Genus run is complete. Run time $total_run_time" mseminario2@huskers.unl.edu

exit
