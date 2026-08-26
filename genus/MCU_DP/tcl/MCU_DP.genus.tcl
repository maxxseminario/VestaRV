################################################################################
#
# Genus TCL script -- CASTALIA-DP CURATED-RESPIN MULTI-CORE VestaRV (4 harts)
#
# Stage F2a (2026-07-21): the CURATED respin configuration chosen at the F1
# fork -- config/castalia_dp.json = Castalia defaults + QSPI0 (page-0 slot 12
# @0x4C00, ex-AFE-stubs), RTC0 (mutex-page sub-slot 5 @0x6500), PWM0 (sub-slot
# 6 @0x6600), DMA0 2-CHANNEL (sub-slot 8 @0x6800, the 5th arbiter master).
# I3C/NFC/OneWire are NOT in this config.
#
# Derived from tcl/MCU_WOUND.genus.tcl (the Stage-E-proven all-7-blocks flow)
# by REMOVING the I3C/NFC/OneWire pieces; everything kept is verbatim wound:
#   1. HDL read-list: MemoryMap.vhd + MCU.vhd come from the STAGED DP tree
#      ($DP_HDL below, generated from config/castalia_dp.json and proven by
#      `make verify` 31/31); peripheral RTL adds are QSPI/RTC/PWM/DMA only
#      (deps ClkGate / ClkDivPower2 / CRC16 already read earlier).
#   2. Constraints kept from wound: qspi0 chained-ICG baud generated clocks
#      (divide_by 1 of smclk, M9c rule -- serial core timed at one smclk
#      period), qspi0 EnMemPeriph negedge pre-latch clock (own async domain),
#      rtc0 lfxt_in @100 ns bench-driven own async domain (A6 adjudication;
#      intra-group report is the non-empty negative control), PWM/DMA no new
#      clocks by construction (mclk-family engines; DMA joins the timed mclk
#      cone as arbiter master 4).
#   3. Constraints REMOVED with their blocks: i3c0 baud/enmem/SDA_IN clocks,
#      nfc0 enmem/rf_clk clocks, their cost/path groups and reports, the
#      SCL_IN->SDA_IN false path, and the GENUS 19.15 degenerate-single-flop-
#      clock power workaround (reset_clock i3c0_sda) -- the trigger clock
#      (SDA_IN, one leaf flop) does not exist in this config. If a future edit
#      reintroduces a single-leaf-flop clock, re-read the wound tcl's header
#      note before trusting report_power.
#
# Everything else (efforts, tns_opto, boundary_opto-false discipline,
# clk_cpu/mclk/smclk/scl/sck clocks, PGEN false paths, tie-offs) is IDENTICAL to
# MCU_MP. Top entity is still "MCU"; TIME-OPTIMIZED, AREA-RELAXED, 25 MHz.
#
################################################################################

# Project names and paths. These are relative to the Genus run directory.
set INPUT_DIR        ../common/in
# ROM/SRAM hard-IP timing libs. The old ../ip tree (~/vestarv/ip) is gone; the
# Myshkin IP now lives here (same libs the single-core tape-out used).
set IP_DIR           /home/mseminario2/chips/myshkin/ip
set IC_DIR           ../../ic
set OUTPUT_DIR       out
set REPORT_DIR       rpt
set HDL_DIR          ../../hdl
set SCRIPTS_DIR      tcl

# STAGED DP HDL: MemoryMap.vhd + MCU.vhd generated from config/castalia_dp.json
# and staged here (platform/common/out is back to DEFAULT -- never read out/). These
# two files come from THIS tree; every other RTL file is the shared hdl/common
# tree via $MP below. Absolute path (consistent with IP_DIR's style) so the read
# is unambiguous regardless of the run dir / init_hdl_search_path.
set DP_HDL        /home/mseminario2/vestarv/xcelium/riscv_test/genus_mp_dp/hdl

# Top-level entity name (unchanged) and the output-file prefix. BASENAME is
# distinct so the DP outputs never clobber the MCU_MP, wound, or single-core runs.
set TOP_MODULE       MCU
set BASENAME         MCU_DP.genus

# Number of harts (hart 0 = top-level core; harts 1..3 = hart_tile instances).
set NUM_HARTS        4

# Target CPU frequency in MHz. Kept identical to the proven single-core target
# (25 MHz) so the multi-core RTL is compared apples-to-apples; bump freq_mult to
# push the corner once the flow is trusted.
set base_freq 		25
set freq_mult 		1
set CLKHFXT_FREQ	[expr $base_freq * $freq_mult]
set CLKLFXT_FREQ	0.032768
set I2CSCL_FREQ		5
set SPISCK_FREQ		$CLKHFXT_FREQ
set FASTEST_FREQ	$CLKHFXT_FREQ
set CLKCPU_FREQ		$CLKHFXT_FREQ

puts "Target CLKHFXT frequency in MHz: $CLKHFXT_FREQ"
puts "Target CLKLFXT frequency in MHz: $CLKLFXT_FREQ"
puts "Target I2CSCL frequency in MHz: $I2CSCL_FREQ"
puts "Target SPISCK frequency in MHz: $SPISCK_FREQ"
puts "Target maximum frequency in MHz: $FASTEST_FREQ"
puts "Target CLKCPU frequency in MHz: $CLKCPU_FREQ"

# Find clock period, which has units of ns.
set CLKHFXT_PERIOD	[expr 1 / [expr $CLKHFXT_FREQ * 0.001]]
set CLKLFXT_PERIOD	[expr 1 / [expr $CLKLFXT_FREQ * 0.001]]
set I2CSCL_PERIOD	[expr 1 / [expr $I2CSCL_FREQ * 0.001]]
set SPISCK_PERIOD	[expr 1 / [expr $SPISCK_FREQ * 0.001]]
set FASTEST_PERIOD	[expr 1 / [expr $FASTEST_FREQ * 0.001]]

puts "Target CLKHFXT period in ns: $CLKHFXT_PERIOD"
puts "Target CLKLFXT period in ns: $CLKLFXT_PERIOD"
puts "Target I2CSCL period in ns: $I2CSCL_PERIOD"
puts "Target SPISCK period in ns: $SPISCK_PERIOD"
puts "Target minimum period in ns: $FASTEST_PERIOD"

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

# 65 nm has both CCS and ECSM timing libraries--unclear if one is better.
# CCS: Current-based, Synopsys
# ECSM: Voltage-based, Cadence
# init_lib_search_paths tells genus where to look for timing files to use during elaboration
set_db init_lib_search_path [list \
	$IP_DIR/rom_hvt_pg \
	$IP_DIR/sram1p16k_hvt_pg \
	$INPUT_DIR/ \
	/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10/ecsm-timing/ ]

# Specify the location of your RTL files to elaborate
set_db init_hdl_search_path [list \
	$HDL_DIR ]

set_db library [list \
	rom_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib \
	sram1p16k_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib \
	scadv10_cln65gp_hvt_tt_1p0v_25c.lib]

# Optimize tns, keep hierarchy (the four tiles are replicated -- preserve their
# boundaries so the report is readable and the later physical flow can reuse
# them), register-aware clock gating.
set_db tns_opto true
set_db auto_ungroup none
# M9b GATE-SIM FIX: default boundary optimization disconnects hierarchical
# ports it proves redundant (controller resetn/jump/csr_*, c_dec is_compressed,
# GlitchFilter->system0 irq, ...). The logic is re-implemented flat so silicon
# is fine, but the written netlist has thousands of floating (Z) port nets and
# every leftover consumer reads Z->X in xmsim -- the MP gate sim X-collapsed at
# hart 0's first SYSTEM0 store. Keep boundaries intact for a sim-faithful
# netlist; timing has huge margin at 25 MHz.
# NOTE (2026-07-04): in this Genus (19.15) the ROOT-level boundary_opto attr is
# OBSOLETED and silently ignored ("use the attribute boundary_opto on
# subdesign") -- the first re-synth still boundary-optimized. The effective
# setting is the per-MODULE one applied right after elaborate below; verified
# on a toy 2-module design (UNCONNECTED_HIER_* nets gone with the fix).
set_db lp_insert_clock_gating true
set_db lp_clock_gating_register_aware true

# Replace constant ties to '0' or '1' with tiehi/tielo cells for improved ESD
# robustness. These are marked as don't use in the lib, so manually override
# this setting.
set_dont_use TIEHIX1MA10TH false
set_dont_use TIELOX1MA10TH false
set_db use_tiehilo_for_const duplicate

################################################################################
# Read HDL (MCU_MP tree)
################################################################################
# Order follows dependencies. Synthesizable clock cells are the *_cmn65gp_ARM
# wrappers (NOT the sim/ ClkGate / ClockMuxGlitchFree behavioral models), and
# the ROM/SRAM functional models are NOT read -- Genus only needs their timing,
# which comes from the .lib files above (same as the single-core flow).
puts "Reading HDL (MCU_MP)"

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
# DP delta: QSPI0 (deps ClkGate/ClkDivPower2/CRC16 already read above); it
# instantiates two chained ClkGate ICGs (cg_clk_baud_src / cg_clk_baud)
# constrained as generated clocks below.
read_hdl -vhdl -library work $MP/periph/QSPI.vhd
# DP delta: the RTC/PWM/DMA library blocks (deps CRC16 for DMA, ClkDivPower2
# already read above). RTC counts the ungated lfxt_in pad clock directly (no
# ClkGate, no generated clocks); PWM/DMA are pure mclk-family engines
# (clk => mclk, ClkMem => mclk at the instances). DMA0 (2-channel in this
# config) is ALSO the 5th arbiter master (mp_arbiter N=5/MW=3 in this DP
# MCU.vhd) -- its master-port FSM/counters/CRC join the existing timed mclk
# cone.
read_hdl -vhdl -library work $MP/periph/RTC.vhd
read_hdl -vhdl -library work $MP/periph/PWM.vhd
read_hdl -vhdl -library work $MP/periph/DMA.vhd
# SARADC/AFE removed (digital-only Castalia, M16+): the entity no longer
# instantiates them, so these files are not read. Kept on disk only for the
# standalone SARADC_tb/AFE_tb; the frozen single-core hdl/MCU flow still uses
# its own copies.

# --- Vesta core ---
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

# --- Multi-core infrastructure (new vs. single-core) ---
# (M13: mp_wait_injector RETIRED — hart 0 is a plain hart_tile now.)
read_hdl -vhdl -library work $MP/adddec.vhd
read_hdl -vhdl -library work $MP/clint.vhd
read_hdl -vhdl -library work $MP/irq_router.vhd
read_hdl -vhdl -library work $MP/mp_arbiter.vhd
read_hdl -vhdl -library work $MP/mutex_bank.vhd
read_hdl -vhdl -library work $MP/pwr_ctrl.vhd
read_hdl -vhdl -library work $MP/resv_unit.vhd
# CQ2b: AFE / EIS digital register stub (5 instances in MCU.vhd). IEEE-only deps.
read_hdl -vhdl -library work $MP/afe_stub.vhd
read_hdl -vhdl -library work $MP/hart_tile.vhd

# --- Top level (DP: staged MCU.vhd with qspi0/rtc0/pwm0/dma0, 3 GlitchFilters) ---
read_hdl -vhdl -library work $DP_HDL/MCU.vhd

################################################################################
# Elaboration
################################################################################
puts "Elaborating $TOP_MODULE"
elaborate $TOP_MODULE

# M9b GATE-SIM FIX (the effective one -- see the boundary-opto comment block in
# the settings section): boundary optimization must be disabled per MODULE, and
# modules only exist after elaborate. Root-level set_db is obsoleted/ignored.
set_db [get_db modules] .boundary_opto false
puts "boundary_opto disabled on [llength [get_db modules]] modules"

################################################################################
# Constraints
################################################################################

# --- Clocks generated inside system0 (shared by every hart) ---
create_clock -name mclk			-domain mclk_domain			-period $FASTEST_PERIOD	hpin:$TOP_MODULE/system0/mclk_out
create_clock -name smclk		-domain smclk_domain		-period $FASTEST_PERIOD	hpin:$TOP_MODULE/system0/smclk_out
create_clock -name clk_lfxt		-domain clk_lfxt_domain		-period $CLKLFXT_PERIOD	hpin:$TOP_MODULE/system0/clk_lfxt_out
create_clock -name clk_hfxt		-domain clk_hfxt_domain		-period $CLKHFXT_PERIOD	hpin:$TOP_MODULE/system0/clk_hfxt_out

# --- Per-hart gated CPU clock (clk_cpu output of each hart's vesta core) ---
# M13 tile extraction: hart 0 is hart0 (hart_tile) like the rest — all four
# cores live at $TOP_MODULE/hart<h>/core.
for {set h 0} {$h < $NUM_HARTS} {incr h} {
	create_clock -name clk_cpu$h	-domain clk_cpu${h}_domain	-period $FASTEST_PERIOD	hpin:$TOP_MODULE/hart$h/core/clk_cpu
}

# --- Peripheral source clocks ---
create_clock -name clk_scl0		-domain clk_scl0_domain		-period $I2CSCL_PERIOD	hpin:$TOP_MODULE/i2c0/SCL_IN
create_clock -name clk_scl1		-domain clk_scl1_domain		-period $I2CSCL_PERIOD	hpin:$TOP_MODULE/i2c1/SCL_IN
create_clock -name clk_sck0		-domain clk_sck0_domain		-period $SPISCK_PERIOD	hpin:$TOP_MODULE/spi0/sck_in
create_clock -name clk_sck1		-domain clk_sck1_domain		-period $SPISCK_PERIOD	hpin:$TOP_MODULE/spi1/sck_in

################################################################################
# --- DP digperiph constraints (rescoped from tcl/{QSPI,RTC}.genus.tcl; the
#     wound flow's I3C/NFC/OneWire constraint set is REMOVED with its blocks) --
#
# The blocks are arbiter slaves: qspi0 port map clk=>smclk, ClkMem=>mclk --
# those two clocks ALREADY exist (system0 tree, separate smclk_domain/
# mclk_domain), so they are NOT re-declared here and NOT made async to each
# other (the block benches' 3-way set_clock_groups was a standalone artifact).
# The i2c0/SCL_IN create_clock above is the precedent for an instance-hpin
# clock. The genuinely-new domains at chip level:
#
#   * qspi0 baud clocks: two chained ICGs (cg_clk_baud_src, cg_clk_baud), each
#     a divide_by-1 generated clock of the block's clk (=smclk). An ICG only
#     masks pulses -- period preserved (M9c rule) -- so the serial-core
#     reg-to-reg paths ARE timed at one smclk period. The generated clock
#     inherits its master smclk's domain, so smclk<->baud and baud<->baud
#     stay synchronous+timed (the M9c non-mistake) while baud vs mclk is async by
#     domain, exactly as the block benches intended. Source is the instance clk
#     pin (on smclk's network); ClkOut hpins verified in QSPI.vhd.
create_generated_clock -name qspi0_baud_src -divide_by 1 \
	-source hpin:$TOP_MODULE/qspi0/clk hpin:$TOP_MODULE/qspi0/cg_clk_baud_src/ClkOut
create_generated_clock -name qspi0_baud     -divide_by 1 \
	-source hpin:$TOP_MODULE/qspi0/clk hpin:$TOP_MODULE/qspi0/cg_clk_baud/ClkOut

#   * EnMemPeriph negedge pre-latch clock (one per block): the reg_sync process
#     latches the inverted volatile registers on falling_edge(EnMemPeriph). At
#     chip level EnMemPeriph is the internal select net (not shslv_*_en); it is a
#     genuine async domain (its own -domain) so those negedge flops are
#     constrained and its data role stays async-sampled from mclk, matching the
#     block benches. 40 ns (smclk class).
create_clock -name qspi0_enmem	-domain qspi0_enmem_domain	-period $FASTEST_PERIOD	hpin:$TOP_MODULE/qspi0/EnMemPeriph

#   * rtc0 lfxt_in (Stage E): the always-on 32.768 kHz wall-clock domain,
#     tapped from the UNGATED lfxt_in pad net (prt1_in(pnum_gpio0_lfxt) --
#     UPSTREAM of system0's clk_lfxt_out mux, so this is a DIFFERENT clock
#     from clk_lfxt above; only the RTC counter/prescaler cone sees it).
#     Constrained at the BENCH-DRIVEN 100 ns rate per the RTC block-closure
#     A6 adjudication (the honest constraint is the harder rate the SDF gate
#     sim actually drives; 305x conservative vs the real 30518 ns crystal).
#     Its own async domain (the wound flow's nfc0_rf idiom). NEGATIVE CONTROL at exit: the
#     rtc0_lfxt intra-group report must be NON-EMPTY with the 47-bit counter
#     carry chain timed -- an unconstrained/cut always-on domain passing
#     timing is the RTC negative control FAILING at chip level.
create_clock -name rtc0_lfxt	-domain rtc0_lfxt_domain	-period 100.0		hpin:$TOP_MODULE/rtc0/lfxt_in

#   * PWM0 / DMA0 (Stage E rule): NO new clocks by construction. Both are
#     single-edge mclk-family engines (clk => mclk, ClkMem => mclk): no
#     EnMemPeriph pre-latch clock (D4 xcollapse-clean read), no generated/baud
#     clocks, and the DMA trigger taps are internal fabric DATA on the mclk
#     budget. DMA0's master port (arb_req(4)/arb_addr slice 4) joins the
#     5-master mp_arbiter pick logic inside the existing timed mclk group --
#     evidence report at the bottom (dma0_mclk).

# --- Cost/path groups for the timed digperiph hotspot domains (the qspi0 baud
#     serial core + the rtc0 always-on counter cone).
#     The register-bus (ClkMem=mclk) paths are already in mclk_group; the
#     EnMemPeriph single-cycle paths land in the default group. ---
define_cost_group -name qspi0_baud_group	-weight 1
define_cost_group -name rtc0_lfxt_group		-weight 1
path_group -from qspi0_baud	-group qspi0_baud_group
path_group -from rtc0_lfxt	-group rtc0_lfxt_group

################################################################################

# --- Cost groups: each clock domain optimized independently ---
define_cost_group -name mclk_group			-weight 1
define_cost_group -name smclk_group			-weight 1
define_cost_group -name clk_lfxt_group		-weight 1
define_cost_group -name clk_hfxt_group		-weight 1
define_cost_group -name clk_scl0_group		-weight 1
define_cost_group -name clk_scl1_group		-weight 1
define_cost_group -name clk_sck0_group		-weight 1
define_cost_group -name clk_sck1_group		-weight 1
for {set h 0} {$h < $NUM_HARTS} {incr h} {
	define_cost_group -name clk_cpu${h}_group	-weight 1
}

# --- Path groups (map each clock's launch paths to its cost group) ---
path_group -from mclk			-group mclk_group
path_group -from smclk			-group smclk_group
path_group -from clk_lfxt		-group clk_lfxt_group
path_group -from clk_hfxt		-group clk_hfxt_group
path_group -from clk_scl0		-group clk_scl0_group
path_group -from clk_scl1		-group clk_scl1_group
path_group -from clk_sck0		-group clk_sck0_group
path_group -from clk_sck1		-group clk_sck1_group
for {set h 0} {$h < $NUM_HARTS} {incr h} {
	path_group -from clk_cpu$h	-group clk_cpu${h}_group
}

# When PGEN gates a ROM/SRAM power, that macro is off and its timing need not be
# met; without these false paths Genus wastes delay cells trying to close timing
# into a powered-down macro (or fails outright). M11 memory-map rework: the
# tiles' dead ROMs and RAM1s are RETIRED (tiles have a single TCM, ram0), and
# hart 0's old ram1 macro is now the shared NPU staging RAM 'npuram0' (still
# gated by BLOCKPWR via pgen_mem(2)). The bulk-RAM banks' PGEN is tied '0'
# (no timing path), so they need no exception. M13: hart 0's TCM lives at
# hart0/ram0 like every other tile (its PGEN still comes from BLOCKPWR via
# the tile's tcm_pgen port; tiles 1-3 tie it low).
set_false_path -to pin:$TOP_MODULE/rom0/PGEN
set_false_path -to pin:$TOP_MODULE/npuram0/PGEN
for {set h 0} {$h < $NUM_HARTS} {incr h} {
	set_false_path -to pin:$TOP_MODULE/hart$h/ram0/PGEN
}

################################################################################
# Top Design Attributes
################################################################################

# Max rise/fall times (ns) for all signals (sets core-device strength).
set_max_transition 0.5

# Reasonable output pin capacitances (pF) -> output-buffer drive strength.
set_load 0.600 [get_ports -filter "direction==out"]

# Expected drive strength of buffers driving the inputs (conservative: small inverter).
set_driving_cell -lib_cell INVX1MA10TH [get_ports -filter "direction==in"]

# NPU decision bit preserved as in the single-core flow (hart-0 private NPU).
set_db net:$TOP_MODULE/npu0/Decision[15] .dont_touch true

################################################################################
# Synthesis -- TIME-OPTIMIZED, AREA-RELAXED
################################################################################
puts "Synthesizing top design (MCU_MP)"

# Keep hierarchy + register-aware clock gating (same as read stage).
set_db auto_ungroup none
# boundary_opto: per-module form (root attr is obsoleted/ignored in Genus 19.15)
set_db [get_db modules] .boundary_opto false
set_db lp_insert_clock_gating true
set_db lp_clock_gating_register_aware true

# ---- Timing-first efforts: trade area for speed ----
# High effort at every stage, total-negative-slack optimization on, and NO area
# constraint (no set_db max_area) so Genus is free to grow area to close and
# then further optimize timing. This is the "larger area, time optimized" knob
# set the user asked for; tighten area later once timing is trusted.
set_db syn_generic_effort high
set_db syn_map_effort     high
set_db syn_opt_effort     high
set_db tns_opto           true

# Replace constant ties with tiehi/tielo cells (ESD robustness).
add_tieoffs -all -verbose -high TIEHIX1MA10TH -low TIELOX1MA10TH

# Generic:  RTL -> generic gates
# Mapping:  generic cells -> standard-cell library cells
# Optimize: refine netlist for the timing-first cost above
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
report_design_rules   > $REPORT_DIR/$BASENAME.rules.rpt
# NOTE: report_power + report_clock_gating stay at the very end of the script
# (position inherited from the wound flow; harmless here). The wound flow's
# reset_clock workaround is NOT needed -- no single-leaf-flop clock (SDA_IN)
# exists in this config; see the header note before adding one.
# Per-cost-group WNS negative controls: the timed digperiph serial/protocol
# cores MUST be real (an empty report = a domain was wrongly cut, the M9c mode).
report_timing -group qspi0_baud_group -max_paths 10 > $REPORT_DIR/$BASENAME.qspi0_baud.rpt
# Stage E negative controls: the RTC lfxt group must be NON-EMPTY (47-bit
# counter carry chain timed -- the A6/chip-level always-on-domain check), and
# the DMA engine/master-port paths must appear timed inside the mclk cone
# (catch-wrapped: a report syntax miss must never abort the run this late).
report_timing -group rtc0_lfxt_group  -max_paths 10 > $REPORT_DIR/$BASENAME.rtc0_lfxt.rpt
# (hinst: is not a valid -through object in this Genus — TIM-233 on the Stage-E
# run; the master-port req pin is. The Stage-E verdict instead used: no SDC
# exception touches dma0 + mclk-group WNS >= 0 => the DMA/arbiter cone is timed.)
catch { report_timing -through hpin:$TOP_MODULE/dma0/m_req -max_paths 10 > $REPORT_DIR/$BASENAME.dma0_mclk.rpt }

################################################################################
# Output Files
#
# script  Design constraints (.g Genus database)
# hdl     Gate-level Verilog netlist
# sdc     Design constraints for later flows (Innovus)
# sdf     Timing for backannotated gate-level simulation
################################################################################
write_script > $OUTPUT_DIR/$BASENAME.g
write_hdl    > $OUTPUT_DIR/$BASENAME.v
write_sdc    > $OUTPUT_DIR/$BASENAME.sdc
write_sdf    > $OUTPUT_DIR/$BASENAME.sdf

################################################################################
# Power reports (end-of-script position inherited from the wound flow; its
# GENUS 19.15 reset_clock workaround is NOT carried -- no single-leaf-flop
# clock exists in this config. See the wound tcl before reintroducing one.)
################################################################################
report_power -by_hierarchy -levels 4 > $REPORT_DIR/$BASENAME.power.rpt
report_clock_gating   > $REPORT_DIR/$BASENAME.clk.rpt

################################################################################
# End of Script
################################################################################
toc
set total_run_time [getHMS $START_TIME $STOP_TIME]
puts "Genus MCU_DP run is complete. Run time $total_run_time"

exit
