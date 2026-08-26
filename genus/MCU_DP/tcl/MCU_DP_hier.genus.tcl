################################################################################
#
# Genus TCL script (DP variant, Stage F2a: staged CastaliaDP fabric + QSPI/RTC/PWM/DMA; derived from MCU_MP_hier) -- MCU_MP HIERARCHICAL TOP (M14 physical flow)
#
# Derived from tcl/MCU_MP.genus.tcl (the flat 4-hart flow). This synthesizes
# the top level ONLY: the four hart instances resolve to the HARDENED tile --
# hart_tile is NOT read as HDL, so it elaborates as a BLACKBOX (exactly how
# the flat flow already treats GlitchFilter/POR/OscillatorCurrentStarved).
# Real tile timing enters the flow in Innovus via the tile ILM/LEF
# (innovus_mp/out/hart_tile.{ilm,lef}); Genus maps the top logic with DRC
# constraints (max_transition, loads) and the top clocks.
#
# Consequences vs. the flat script:
#   * no vesta/adddec/hart_tile read_hdl -- tile is a blackbox
#   * no clk_cpu<h> clocks (those hpins are INSIDE the hardened tile; the
#     tile SDC constrains them via the generated-clock fix -- M9c bug dead)
#   * no hart<h>/ram0/PGEN false paths (tile-internal, in the tile SDC)
#   * hart0's flash_clk_mem output (gated mclk, XIP) gets an explicit
#     generated clock at the tile pin so spi0's flash-side logic stays
#     constrained (the flat flow got this by propagation through the tile)
#   * the emitted netlist may contain an EMPTY `module hart_tile` stub --
#     the top Innovus run and the gate sim must bind the REAL tile netlist
#     (stub is stripped by the Innovus wrapper / compile order in sim)
#
################################################################################

set INPUT_DIR        ../common/in
set IP_DIR           /home/mseminario2/chips/myshkin/ip
set OUTPUT_DIR       out
set REPORT_DIR       rpt
set HDL_DIR          ../../hdl

# STAGED DP HDL (Stage F2a): MemoryMap.vhd + MCU.vhd generated from
# config/castalia_dp.json (QSPI+RTC+PWM+DMA-2ch curated respin) and staged
# in the genus_mp_dp gate-flow tree; proven by make verify 31/31.
set DP_HDL        /home/mseminario2/vestarv/xcelium/riscv_test/genus_mp_dp/hdl

set TOP_MODULE       MCU
set BASENAME         MCU_DP_hier.genus
set NUM_HARTS        4

set base_freq 		25
set freq_mult 		1
set CLKHFXT_FREQ	[expr $base_freq * $freq_mult]
set CLKLFXT_FREQ	0.032768
set I2CSCL_FREQ		5
set SPISCK_FREQ		$CLKHFXT_FREQ
set FASTEST_FREQ	$CLKHFXT_FREQ

set CLKHFXT_PERIOD	[expr 1 / [expr $CLKHFXT_FREQ * 0.001]]
set CLKLFXT_PERIOD	[expr 1 / [expr $CLKLFXT_FREQ * 0.001]]
set I2CSCL_PERIOD	[expr 1 / [expr $I2CSCL_FREQ * 0.001]]
set SPISCK_PERIOD	[expr 1 / [expr $SPISCK_FREQ * 0.001]]
set FASTEST_PERIOD	[expr 1 / [expr $FASTEST_FREQ * 0.001]]
puts "Target mclk/hfxt period in ns: $FASTEST_PERIOD"

################################################################################
# Procedures
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

# hart_tile (and the analog blocks) elaborate as blackboxes -- that is the
# point of this script.
set_db hdl_error_on_blackbox false

# Keep the blackbox module named plain "hart_tile" (default naming appends
# the generic values; the tile netlist/LEF/ILM all carry the plain name).
set_db hdl_parameter_naming_style ""

set_db init_lib_search_path [list \
	$IP_DIR/rom_hvt_pg \
	$IP_DIR/sram1p16k_hvt_pg \
	$INPUT_DIR/ \
	/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10/ecsm-timing/ \
	/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10-pmk/synopsys/ ]

set_db init_hdl_search_path [list \
	$HDL_DIR ]

# M17: the pmk NLDM joins the list — the tile gate netlist read as source
# below now contains HEADBUF16MA10TH power switches, which must resolve
# against a library like every other tile cell.
set_db library [list \
	rom_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib \
	sram1p16k_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib \
	scadv10_cln65gp_hvt_tt_1p0v_25c.lib \
	scadv10pmk_tsmc65gp_hvt_tt_1p0v_25c.lib]

set_db tns_opto true
set_db auto_ungroup none
# boundary_opto: per-module post-elaborate form (root attr obsoleted, M9b).
set_db lp_insert_clock_gating true
set_db lp_clock_gating_register_aware true

set_dont_use TIEHIX1MA10TH false
set_dont_use TIELOX1MA10TH false
set_db use_tiehilo_for_const duplicate

################################################################################
# Read HDL (MCU_MP tree MINUS the tile: no vesta/, no adddec, no hart_tile)
################################################################################
puts "Reading HDL (MCU_MP top, hart_tile as blackbox)"
set MP $HDL_DIR/common

# --- Commune / shared packages and cells ---
# VHDL sources use 2008 delimited comments
set_db hdl_vhdl_read_version 2008
read_hdl -vhdl -library work $MP/commune/fixed_float_types_c.vhdl
read_hdl -vhdl -library work $MP/commune/fixed_pkg_c.vhdl
read_hdl -vhdl -library work $MP/commune/FPMac.vhd
read_hdl -vhdl -library work $MP/commune/FPSigmoid.vhd
read_hdl -vhdl -library work $MP/commune/TieLow.vhd
read_hdl -vhdl -library work $MP/constants.vhd
read_hdl -vhdl -library work $MP/macros/macros.vhd
# DP delta: MemoryMap carries the QSPI/RTC/PWM/DMA IRQ vectors + MMR addresses.
read_hdl -vhdl -library work $DP_HDL/MemoryMap.vhd
read_hdl -vhdl -library work $MP/commune/ClkGate_cmn65gp_ARM.vhd
read_hdl -vhdl -library work $MP/commune/ClockMuxGlitchFree_cmn65gp_ARM.vhd
read_hdl -vhdl -library work $MP/commune/CRC16.vhd
read_hdl -vhdl -library work $MP/commune/ClkDivPower2.vhd

# --- Peripherals ---
read_hdl -vhdl -library work $MP/periph/GPIO.vhd
read_hdl -vhdl -library work $MP/periph/SPI.vhd
read_hdl -vhdl -library work $MP/periph/UART.vhd
read_hdl -vhdl -library work $MP/periph/I2C.vhd
read_hdl -vhdl -library work $MP/periph/TIMER.vhd
read_hdl -vhdl -library work $MP/periph/SYSTEM.vhd
read_hdl -vhdl -library work $MP/periph/NPU.vhd
# DP delta: QSPI0 (chained ClkGate ICG baud pair constrained below) plus the
# RTC/PWM/DMA library blocks (RTC counts the ungated lfxt_in pad clock; PWM/
# DMA are mclk-family engines, no new clocks; DMA0 2-channel is the 5th
# arbiter master in this MCU.vhd -- deps ClkGate/ClkDivPower2/CRC16 already read).
read_hdl -vhdl -library work $MP/periph/QSPI.vhd
read_hdl -vhdl -library work $MP/periph/RTC.vhd
read_hdl -vhdl -library work $MP/periph/PWM.vhd
read_hdl -vhdl -library work $MP/periph/DMA.vhd

# --- Multi-core infrastructure (control plane only -- NO vesta, NO adddec,
# NO hart_tile: the tile is the hardened block) ---
read_hdl -vhdl -library work $MP/clint.vhd
read_hdl -vhdl -library work $MP/irq_router.vhd
read_hdl -vhdl -library work $MP/mp_arbiter.vhd
read_hdl -vhdl -library work $MP/mutex_bank.vhd
read_hdl -vhdl -library work $MP/pwr_ctrl.vhd
read_hdl -vhdl -library work $MP/resv_unit.vhd
# CQ2b: AFE / EIS digital register stub (5 instances in MCU.vhd: AFE0-3 @0x4C00
# sub-slots + EIS @0x7C00). Plain arbiter-slave register file, depends only on
# IEEE (no MP package deps) — placed with the other control-plane slaves.
read_hdl -vhdl -library work $MP/afe_stub.vhd

# --- The tile: its HARDENED GATE NETLIST as verilog source ---
# MCU.vhd instantiates the tile by DIRECT ENTITY INSTANTIATION
# (entity work.hart_tile), which genus cannot blackbox from a port map alone
# (CDFG-254: literal-bound ports have no inferable type) and cannot bind to
# an entity without an architecture (CDFG-321). So the tile-only run's gate
# netlist is read as SOURCE: elaboration binds the four hart instances to the
# real mapped module (std cells + the TCM sram resolve from the loaded libs),
# and dont_touch/preserve below keeps genus's hands off it -- ONE hart_tile
# module, four references, no uniquify. Bonus vs a bare blackbox: the top
# logic is timed against the REAL tile interface paths, in the mclk domain --
# which is the M9c-fixed interpretation (clk_cpu IS gated mclk; it propagates
# as mclk through the tile's clock gates).
# MCU.vhd's instantiation passes generic map (PC_RST_VAL, SH_AW); the gate
# netlist module has no parameters, and genus errors on the mismatch
# (CDFG-214). Inject matching dummy verilog parameters into the module header
# (generated copy -- the tile-only outputs stay pristine). Values = the one
# real configuration; all four instances bind identically.
# (M17 note: the post-M14 core ISA-extension generics ENABLE_* must be
# injected too — the generated MCU.vhd passes them in every hart generic
# map, and elaboration dies with CDFG-200 on the first missing one.)
exec bash -c "mkdir -p $INPUT_DIR && awk '
	/^module hart_tile\\(/ { inhdr=1 }
	{ print }
	inhdr && /\\);\$/ { print \"  parameter PC_RST_VAL = 32'\\''h00000000;\"; print \"  parameter SH_AW = 15;\"; print \"  parameter ENABLE_MUL = 1;\"; print \"  parameter ENABLE_DIV = 1;\"; print \"  parameter ENABLE_ATOMICS = 1;\"; print \"  parameter ENABLE_COMPRESSED = 1;\"; print \"  parameter ENABLE_BITMANIP = 1;\"; inhdr=0 }
' ../hart_tile/out/hart_tile.genus.v > $INPUT_DIR/hart_tile_top.gen.v"
read_hdl $INPUT_DIR/hart_tile_top.gen.v

# --- Top level ---
# M17: genus 19 CANNOT bind a VHDL BOOLEAN generic to a verilog parameter
# (CDFG-200 on 'CORE_ENABLE_MUL'), so the hier flow reads a GENERATED copy
# of MCU.vhd with the five ENABLE_* associations stripped from every hart
# generic map (they pass the entity defaults = the one real configuration;
# the tile netlist was synthesized with exactly those values). The SH_AW
# line loses its now-trailing comma. MCU.vhd itself stays pristine (it is
# the make-chip product).
exec bash -c "sed -e '/=> CORE_ENABLE_/d' \
	-e 's/SH_AW          => SH_AW,/SH_AW          => SH_AW/' \
	$DP_HDL/MCU.vhd > $INPUT_DIR/MCU_top.gen.vhd"
read_hdl -vhdl -library work $INPUT_DIR/MCU_top.gen.vhd

################################################################################
# Elaboration
################################################################################
puts "Elaborating $TOP_MODULE"
elaborate $TOP_MODULE

# M9b GATE-SIM FIX: per-MODULE boundary_opto disable (root attr ignored).
set_db [get_db modules] .boundary_opto false
puts "boundary_opto disabled on [llength [get_db modules]] modules"

# The hardened tile is UNTOUCHABLE: one module, four instances, zero genus
# edits (the physical block is already final -- Innovus binds its ILM/LEF).
foreach tm [get_db modules -if {.name == hart_tile}] {
	catch { set_db $tm .dont_touch true }
	catch { set_db $tm .preserve true }
	puts "tile module preserved: [get_db $tm .name]"
}
foreach h {0 1 2 3} {
	catch { set_db inst:$TOP_MODULE/hart$h .preserve true }
}

################################################################################
# Constraints
################################################################################

# --- Clocks generated inside system0 (control plane) ---
create_clock -name mclk			-domain mclk_domain			-period $FASTEST_PERIOD	hpin:$TOP_MODULE/system0/mclk_out
create_clock -name smclk		-domain smclk_domain		-period $FASTEST_PERIOD	hpin:$TOP_MODULE/system0/smclk_out
create_clock -name clk_lfxt		-domain clk_lfxt_domain		-period $CLKLFXT_PERIOD	hpin:$TOP_MODULE/system0/clk_lfxt_out
create_clock -name clk_hfxt		-domain clk_hfxt_domain		-period $CLKHFXT_PERIOD	hpin:$TOP_MODULE/system0/clk_hfxt_out

# --- NO clk_cpu<h> clocks: those hpins live inside the hardened tile. ---

# --- hart 0's XIP flash memory clock: a gated mclk that EXITS the tile at
# flash_clk_mem and clocks spi0's flash-side logic. Same waveform as mclk,
# same domain (it IS mclk, gated -- the M9c lesson applied at top level). ---
create_generated_clock -name flash_clk_mem -divide_by 1 \
	-source hpin:$TOP_MODULE/system0/mclk_out -domain mclk_domain \
	hpin:$TOP_MODULE/hart0/flash_clk_mem

# --- Peripheral source clocks ---
create_clock -name clk_scl0		-domain clk_scl0_domain		-period $I2CSCL_PERIOD	hpin:$TOP_MODULE/i2c0/SCL_IN
create_clock -name clk_scl1		-domain clk_scl1_domain		-period $I2CSCL_PERIOD	hpin:$TOP_MODULE/i2c1/SCL_IN
create_clock -name clk_sck0		-domain clk_sck0_domain		-period $SPISCK_PERIOD	hpin:$TOP_MODULE/spi0/sck_in
create_clock -name clk_sck1		-domain clk_sck1_domain		-period $SPISCK_PERIOD	hpin:$TOP_MODULE/spi1/sck_in

################################################################################
# --- DP digperiph constraints (Stage F2a; identical to MCU_DP.genus.tcl --
#     see its header for the full rationale/provenance) ---
create_generated_clock -name qspi0_baud_src -divide_by 1 \
	-source hpin:$TOP_MODULE/qspi0/clk hpin:$TOP_MODULE/qspi0/cg_clk_baud_src/ClkOut
create_generated_clock -name qspi0_baud     -divide_by 1 \
	-source hpin:$TOP_MODULE/qspi0/clk hpin:$TOP_MODULE/qspi0/cg_clk_baud/ClkOut
create_clock -name qspi0_enmem	-domain qspi0_enmem_domain	-period $FASTEST_PERIOD	hpin:$TOP_MODULE/qspi0/EnMemPeriph
create_clock -name rtc0_lfxt	-domain rtc0_lfxt_domain	-period 100.0		hpin:$TOP_MODULE/rtc0/lfxt_in
define_cost_group -name qspi0_baud_group	-weight 1
define_cost_group -name rtc0_lfxt_group		-weight 1
path_group -from qspi0_baud	-group qspi0_baud_group
path_group -from rtc0_lfxt	-group rtc0_lfxt_group
################################################################################

# --- Cost groups / path groups ---
define_cost_group -name mclk_group			-weight 1
define_cost_group -name smclk_group			-weight 1
define_cost_group -name clk_lfxt_group		-weight 1
define_cost_group -name clk_hfxt_group		-weight 1
define_cost_group -name clk_scl0_group		-weight 1
define_cost_group -name clk_scl1_group		-weight 1
define_cost_group -name clk_sck0_group		-weight 1
define_cost_group -name clk_sck1_group		-weight 1
path_group -from mclk			-group mclk_group
path_group -from smclk			-group smclk_group
path_group -from clk_lfxt		-group clk_lfxt_group
path_group -from clk_hfxt		-group clk_hfxt_group
path_group -from clk_scl0		-group clk_scl0_group
path_group -from clk_scl1		-group clk_scl1_group
path_group -from clk_sck0		-group clk_sck0_group
path_group -from clk_sck1		-group clk_sck1_group

# PGEN powered-down-macro exceptions. The tile netlist is loaded as source
# here (see the read stage), so the four TCM PGEN pins are visible and need
# the same exception as the flat flow gave them; the tile-only SDC repeats it
# for the standalone harden.
set_false_path -to pin:$TOP_MODULE/rom0/PGEN
set_false_path -to pin:$TOP_MODULE/npuram0/PGEN
for {set h 0} {$h < $NUM_HARTS} {incr h} {
	set_false_path -to pin:$TOP_MODULE/hart$h/ram0/PGEN
}

################################################################################
# Top Design Attributes
################################################################################
set_max_transition 0.5
set_load 0.600 [get_ports -filter "direction==out"]
set_driving_cell -lib_cell INVX1MA10TH [get_ports -filter "direction==in"]
set_db net:$TOP_MODULE/npu0/Decision[15] .dont_touch true

################################################################################
# Synthesis -- TIME-OPTIMIZED, AREA-RELAXED
################################################################################
puts "Synthesizing top design (MCU_MP hierarchical)"
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

################################################################################
# Output Files
################################################################################
# DP negative controls (non-empty = domain really timed; M9c/A6 discipline).
report_timing -group qspi0_baud_group -max_paths 10 > $REPORT_DIR/$BASENAME.qspi0_baud.rpt
report_timing -group rtc0_lfxt_group  -max_paths 10 > $REPORT_DIR/$BASENAME.rtc0_lfxt.rpt
catch { report_timing -through hpin:$TOP_MODULE/dma0/m_req -max_paths 10 > $REPORT_DIR/$BASENAME.dma0_mclk.rpt }
write_script > $OUTPUT_DIR/$BASENAME.g
write_hdl    > $OUTPUT_DIR/$BASENAME.v
write_sdc    > $OUTPUT_DIR/$BASENAME.sdc
write_sdf    > $OUTPUT_DIR/$BASENAME.sdf

toc
set total_run_time [getHMS $START_TIME $STOP_TIME]
puts "Genus MCU_DP_hier run is complete. Run time $total_run_time"

exit
