################################################################################
#
# Genus TCL script -- WOUND-CONFIG MULTI-CORE VestaRV (4 harts + digperiphs)
#
# Cloned VERBATIM from tcl/MCU_MP.genus.tcl (the proven 4-hart chip flow).
# ONLY three classes of delta vs. MCU_MP (digperiphs Stage 2 Mission A(b)):
#   1. HDL read-list: MemoryMap.vhd + MCU.vhd come from the STAGED WOUND tree
#      (../xcelium/riscv_test/genus_mp_wound/hdl, generated from config/wound.json),
#      and the three new peripheral RTL files QSPI.vhd / I3C.vhd / NFC.vhd are
#      added to the peripherals section (deps ClkGate / ClkDivPower2 / CRC16 are
#      already read earlier). The wound MCU instantiates qspi0 (page-0 slot 12
#      @0x4C00), i3c0 (mutex-page sub-slot 1 @0x6100) and nfc0 (mutex-page
#      sub-slot 2 @0x6200) as arbiter slaves; it also has a 4th GlitchFilter
#      (irq_gf3) -- an analog macro resolved as a lib/blackbox cell exactly like
#      the existing three (never read in HDL, same as the MCU_MP flow).
#   2. Constraints: the block-level per-peripheral SDCs
#      (tcl/{QSPI,I3C,NFC}.genus.tcl) are RESCOPED to instance hpins. Each
#      block's clk/ClkMem are the chip's existing smclk/mclk (clk=>smclk,
#      ClkMem=>mclk in the MCU port maps) -- NOT re-declared and NOT made async
#      to each other (the block benches' 3-way set_clock_groups was a standalone
#      artifact; MCU_MP already separates smclk_domain/mclk_domain via -domain).
#      The genuinely-new domains added here are: the qspi0/i3c0 ICG-gated baud
#      generated clocks (divide_by 1 of smclk, M9c rule), the per-instance
#      EnMemPeriph negedge pre-latch clocks, i3c0's SDA_IN (B7 IBI sensor, 1
#      flop) and nfc0's rf_clk (50 ns compressed carrier). Each async new domain
#      gets its OWN -domain (the MCU_MP async idiom -- no set_clock_groups in the
#      chip flow); the baud generated clocks inherit smclk's domain (so the
#      serial-core single-cycle paths ARE timed, M9c non-mistake). The honest
#      SCL_IN->SDA_IN false path is carried over.
#   3. GENUS 19.15 DEGENERATE-CLOCK POWER DEFECT: SDA_IN fans out to exactly ONE
#      leaf flop (i3c0 ibi_req); the 19.15 Joules/vectorless engine then silently
#      zeroes internal+switching power for the WHOLE design in report_power AND
#      report_clock_gating (leakage survives, "Completed successfully", no
#      warning -- see I3C.genus.tcl ~L354 + the degenerate-clock memory note).
#      Fix: those two reports run LAST, after all honest-SDC outputs (timing,
#      write_sdc/sdf/script) are emitted with SDA_IN intact, with
#      `reset_clock -clock [get_clocks SDA_IN]` immediately before them.
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

# STAGED WOUND HDL: MemoryMap.vhd + MCU.vhd generated from config/wound.json and
# staged here (platform/common/out is back to DEFAULT -- never read out/). These
# two files come from THIS tree; every other RTL file is the shared hdl/common
# tree via $MP below. Absolute path (consistent with IP_DIR's style) so the read
# is unambiguous regardless of the run dir / init_hdl_search_path.
set WOUND_HDL        /home/mseminario2/vestarv/xcelium/riscv_test/genus_mp_wound/hdl

# Top-level entity name (unchanged) and the output-file prefix. BASENAME is
# distinct so the WOUND outputs never clobber the MCU_MP or single-core runs.
set TOP_MODULE       MCU
set BASENAME         MCU_WOUND.genus

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
# WOUND delta: MemoryMap carries the new digperiph IRQ vectors + MMR addresses.
read_hdl -vhdl -library work $WOUND_HDL/MemoryMap.vhd
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
# WOUND delta: the three digital peripherals (deps ClkGate/ClkDivPower2/CRC16
# already read above). NFC has NO component instances (pure behavioral, rf_clk
# counted directly); QSPI/I3C each instantiate two chained ClkGate ICGs
# (cg_clk_baud_src / cg_clk_baud) constrained as generated clocks below.
read_hdl -vhdl -library work $MP/periph/QSPI.vhd
read_hdl -vhdl -library work $MP/periph/I3C.vhd
read_hdl -vhdl -library work $MP/periph/NFC.vhd
# WOUND delta (Stage E, 2026-07-21): the four library blocks of the RTC->DMA
# program, all wound-config in-fabric since Phase 1-3. Deps (CRC16 for DMA,
# ClkDivPower2) are already read above. RTC counts the ungated lfxt_in pad
# clock directly (no ClkGate, no generated clocks); PWM/OneWire/DMA are pure
# mclk-family engines (clk => mclk, ClkMem => mclk at the instances). DMA0 is
# ALSO the 5th arbiter master (mp_arbiter N=5/MW=3 in this wound MCU.vhd) --
# its master-port FSM/counters/CRC join the existing timed mclk cone.
read_hdl -vhdl -library work $MP/periph/RTC.vhd
read_hdl -vhdl -library work $MP/periph/PWM.vhd
read_hdl -vhdl -library work $MP/periph/OneWire.vhd
read_hdl -vhdl -library work $MP/periph/DMA.vhd
# WOUND delta (P4.4 combined run, 2026-07-23): I2CTarget landed in
# wound.json at b239f54 but its wound synthesis rode this combined run --
# without this read genus silently BLACKBOXES i2ct0 (found the hard way:
# the gate sim's xmelab CUVMUR unresolved-instance error is the only loud
# failure; the synth itself completes "clean" with a hole in the chip).
read_hdl -vhdl -library work $MP/periph/I2CTarget.vhd
# WOUND delta (P4.4 combined run, 2026-07-23): the TRNG0 rider. The REAL
# ring-oscillator ensemble (TrngRoEnsemble architecture rtl) is GENUS/GATE
# FLOW ONLY -- the behavioral flows compile the deterministic _sim arch
# instead (the D6 sim/real split; the real rings delta-loop a zero-delay
# sim). trng0 + u_ro are SIBLING instances in this wound MCU. The rings are
# DELIBERATE combinational loops: dont_touch attributes are applied at the
# instance level after elaboration (see the TRNG RO preserve block below);
# genus's timing engine auto-breaks the loops (async jitter source, never a
# timed path -- ro_raw is 2-FF synchronized inside trng0 before any use).
read_hdl -vhdl -library work $MP/periph/TrngRoEnsemble.vhd
read_hdl -vhdl -library work $MP/periph/TRNG.vhd
# WOUND delta (Stage H, 2026-07-26): EVFAB0, the event/trigger fabric
# (PPI-style crossbar), page-2 MUTEX-page sub-slot 0x6B00, vectorless v1
# (irq_evfab is a constant '0' in the block and is left open at the
# instance). IEEE-only deps -- EVFAB.vhd has NO component instances, so it
# can be read anywhere after the packages; it is placed last in the wound
# peripheral group because every one of its EV/task wires comes FROM the
# blocks above (RTC/PWM/TIMER/UART/NFC/DMA/TRNG/I2CTarget/GPIO/NPU/PWRCTRL).
# THE I2CT0 LESSON APPLIES VERBATIM: without this read genus silently
# BLACKBOXES evfab0 -- the synth still completes "clean" with a hole in the
# chip and only the gate sim's xmelab CUVMUR unresolved-instance error is
# loud. The blackbox census at the end of a run must stay EXACTLY
# dco0 / irq_gf0 / por.
#
# NO NEW CLOCKS (the Stage E PWM0/OW0/DMA0 form -- see the clock section):
# evfab0 port maps clk => mclk AND ClkMem => mclk, a free-running always-on
# single-edge mclk engine. Every event/task matrix net is pure DATA (design
# doc ROOT-3: the fabric NEVER clocks anything off an event wire), and each
# toggle/level producer input is 2-FF synchronized inside the fabric before
# use -- so there is no EnMemPeriph negedge pre-latch clock, no generated/
# baud clock and no clock on any ev_in/gpio0_evin bit. Nothing to
# create_clock, no new path group.
read_hdl -vhdl -library work $MP/periph/EVFAB.vhd
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

# --- Top level (WOUND: staged MCU.vhd with qspi0/i3c0/nfc0 + 4th GlitchFilter) ---
read_hdl -vhdl -library work $WOUND_HDL/MCU.vhd

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
# --- WOUND digperiph constraints (rescoped from tcl/{QSPI,I3C,NFC}.genus.tcl) --
#
# The blocks are arbiter slaves: qspi0/i3c0/nfc0 port map clk=>smclk,
# ClkMem=>mclk -- those two clocks ALREADY exist (system0 tree, separate
# smclk_domain/mclk_domain), so they are NOT re-declared here and NOT made async
# to each other (the block benches' 3-way set_clock_groups was a standalone
# artifact). The i2c0/SCL_IN create_clock above is the precedent for an
# instance-hpin clock. The genuinely-new domains at chip level:
#
#   * qspi0/i3c0 baud clocks: two chained ICGs per block (cg_clk_baud_src,
#     cg_clk_baud), each a divide_by-1 generated clock of the block's clk
#     (=smclk). An ICG only masks pulses -- period preserved (M9c rule) -- so the
#     serial-core reg-to-reg paths ARE timed at one smclk period. The generated
#     clock inherits its master smclk's domain, so smclk<->baud and baud<->baud
#     stay synchronous+timed (the M9c non-mistake) while baud vs mclk is async by
#     domain, exactly as the block benches intended. Source is the instance clk
#     pin (on smclk's network); ClkOut hpins verified in QSPI.vhd / I3C.vhd.
create_generated_clock -name qspi0_baud_src -divide_by 1 \
	-source hpin:$TOP_MODULE/qspi0/clk hpin:$TOP_MODULE/qspi0/cg_clk_baud_src/ClkOut
create_generated_clock -name qspi0_baud     -divide_by 1 \
	-source hpin:$TOP_MODULE/qspi0/clk hpin:$TOP_MODULE/qspi0/cg_clk_baud/ClkOut
create_generated_clock -name i3c0_baud_src  -divide_by 1 \
	-source hpin:$TOP_MODULE/i3c0/clk hpin:$TOP_MODULE/i3c0/cg_clk_baud_src/ClkOut
create_generated_clock -name i3c0_baud      -divide_by 1 \
	-source hpin:$TOP_MODULE/i3c0/clk hpin:$TOP_MODULE/i3c0/cg_clk_baud/ClkOut

#   * EnMemPeriph negedge pre-latch clock (one per block): the reg_sync process
#     latches the inverted volatile registers on falling_edge(EnMemPeriph). At
#     chip level EnMemPeriph is the internal select net (not shslv_*_en); it is a
#     genuine async domain (its own -domain) so those negedge flops are
#     constrained and its data role stays async-sampled from mclk, matching the
#     block benches. 40 ns (smclk class).
create_clock -name qspi0_enmem	-domain qspi0_enmem_domain	-period $FASTEST_PERIOD	hpin:$TOP_MODULE/qspi0/EnMemPeriph
create_clock -name i3c0_enmem	-domain i3c0_enmem_domain	-period $FASTEST_PERIOD	hpin:$TOP_MODULE/i3c0/EnMemPeriph
create_clock -name nfc0_enmem	-domain nfc0_enmem_domain	-period $FASTEST_PERIOD	hpin:$TOP_MODULE/nfc0/EnMemPeriph

#   * i3c0 SDA_IN: the B7 IBI sensor's real edge-trigger clock (exactly ONE leaf
#     flop, ibi_req). Its own async domain. Tied '1' in this placeholder wiring;
#     boundary_opto-false keeps the pin, so the clock is defined on it. 40 ns.
#     (This single-flop clock triggers the 19.15 power-zeroing defect -- handled
#     by reset_clock at the reports, see the bottom of the script.)
create_clock -name i3c0_sda		-domain i3c0_sda_domain		-period $FASTEST_PERIOD	hpin:$TOP_MODULE/i3c0/SDA_IN

#   * nfc0 rf_clk: the genuine AFE carrier-derived protocol domain, unrelated to
#     smclk. 50 ns (compressed carrier = what the SDF gate sim drives, and
#     conservative vs the real 73.75 ns). Its own async domain. Tied '0' here.
create_clock -name nfc0_rf		-domain nfc0_rf_domain		-period 50.0		hpin:$TOP_MODULE/nfc0/rf_clk

#   * rtc0 lfxt_in (Stage E): the always-on 32.768 kHz wall-clock domain,
#     tapped from the UNGATED lfxt_in pad net (prt1_in(pnum_gpio0_lfxt) --
#     UPSTREAM of system0's clk_lfxt_out mux, so this is a DIFFERENT clock
#     from clk_lfxt above; only the RTC counter/prescaler cone sees it).
#     Constrained at the BENCH-DRIVEN 100 ns rate per the RTC block-closure
#     A6 adjudication (the honest constraint is the harder rate the SDF gate
#     sim actually drives; 305x conservative vs the real 30518 ns crystal).
#     Its own async domain (the nfc0_rf idiom). NEGATIVE CONTROL at exit: the
#     rtc0_lfxt intra-group report must be NON-EMPTY with the 47-bit counter
#     carry chain timed -- an unconstrained/cut always-on domain passing
#     timing is the RTC negative control FAILING at chip level.
create_clock -name rtc0_lfxt	-domain rtc0_lfxt_domain	-period 100.0		hpin:$TOP_MODULE/rtc0/lfxt_in

#   * PWM0 / OW0 / DMA0 (Stage E): NO new clocks by construction. All three
#     are single-edge mclk-family engines (clk => mclk, ClkMem => mclk): no
#     EnMemPeriph pre-latch clock (D4 xcollapse-clean read), no generated/baud
#     clocks, no clock on OW_DQ_IN (2-FF synchronized DATA -- the deliberate
#     contrast with i3c0/SDA_IN), and the DMA trigger taps are internal fabric
#     DATA on the mclk budget. DMA0's master port (arb_req(4)/arb_addr slice 4)
#     joins the 5-master mp_arbiter pick logic inside the existing timed mclk
#     group -- evidence report at the bottom (dma0_mclk).

#   * EVFAB0 (Stage H): NO new clocks by construction, the same form. evfab0
#     port maps clk => mclk AND ClkMem => mclk -- one free-running, always-on,
#     single-edge mclk engine (EVFAB.vhd header: "ONE clock; no latch, no clock
#     gate, no falling_edge of anything, least of all EnMemPeriph"). So: no
#     EnMemPeriph pre-latch clock (it is consumed ONLY as an active-low LEVEL
#     sampled on rising ClkMem -- the D4 contrast with qspi0/i3c0/nfc0 above),
#     no generated/baud clocks, and NO clock on any event wire: every ev_in /
#     gpio0_evin / task_busy net is pure DATA (design-doc ROOT-3 -- the fabric
#     never clocks anything off an event), with toggle/level producer inputs
#     2-FF synchronized inside the fabric (the OW_DQ_IN idiom, the deliberate
#     contrast with i3c0/SDA_IN). Its register bus and crossbar therefore live
#     entirely in the existing timed mclk_group -- no new -domain, no new
#     define_cost_group/path_group.

# --- Cost/path groups for the timed digperiph hotspot domains (baud serial
#     cores + the NFC rf protocol core -- the parse/compose combinational cone).
#     The register-bus (ClkMem=mclk) paths are already in mclk_group; the
#     EnMemPeriph/SDA_IN single-cycle paths land in the default group. ---
define_cost_group -name qspi0_baud_group	-weight 1
define_cost_group -name i3c0_baud_group		-weight 1
define_cost_group -name nfc0_rf_group		-weight 1
define_cost_group -name rtc0_lfxt_group		-weight 1
path_group -from qspi0_baud	-group qspi0_baud_group
path_group -from i3c0_baud	-group i3c0_baud_group
path_group -from nfc0_rf	-group nfc0_rf_group
path_group -from rtc0_lfxt	-group rtc0_lfxt_group

# --- Honest false path: i3c0 SCL_IN is the level qualifier of the START sensed
#     in the SDA_IN clock domain (ibi_sensor). SCL_IN and SDA_IN are two
#     independent external open-drain wires -- no closeable synchronous setup/
#     hold between an async input and an async external clock; the crossing is a
#     held-level handshake retired downstream. (SCL_IN is tied '1' here so the
#     arc is likely constant already; kept for parity with I3C.genus.tcl.) ---
set_false_path -from hpin:$TOP_MODULE/i3c0/SCL_IN -to [get_clocks i3c0_sda]
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

# TRNG0 RO ensemble preserve (P4.4 rider; TrngRoEnsemble.vhd header contract):
# dont_touch the u_ro hierarchy + EVERY trng_inv/trng_nand wrapper instance
# so the inverter chains cannot be collapsed. Census: at NRO=8 with stages
# {13,17,19,23,29,31,37,41} expect sum(stages-1)=202 preserved inverters +
# 8 NAND enables; FATAL if the count is off (a collapsed ring = no entropy,
# silently -- the exact bug class the header warns about).
# MECHANISM (probed standalone on this Genus 19.15, 2026-07-23): every
# preserve/dont_touch form is REJECTED on unmapped instances (TUI-209/211/
# 214/67), and without protection syn_generic COLLAPSES the inverter chains
# 210 -> 8 (one per ring -- the silent no-entropy bug). The combination that
# PROVABLY holds all 210 wrappers through syn_generic AND syn_map is:
# auto_ungroup none (already set in this flow) + ungroup_ok false on the
# u_ro hinsts + boundary_opto false on the trng_inv/trng_nand modules.
# preserve true is then applied POST-MAP (where it is legal) before syn_opt
# runs no further restructuring, and the post-synthesis census below FATALs
# if the final netlist lost a single ring stage.
set ro_hinsts [get_db hinsts *u_ro*]
set_db $ro_hinsts .ungroup_ok false
set ro_mods [get_db modules *trng_*]
set_db $ro_mods .boundary_opto false
set n_ring 0
foreach h $ro_hinsts {
    if { [string match *inv* $h] || [string match *nand* $h] } { incr n_ring }
}
puts "TRNG RO census (pre-syn): [llength $ro_hinsts] hinsts under u_ro, $n_ring inverter/nand wrappers"
if { $n_ring < 210 } {
    puts "FATAL: TRNG RO pre-syn census $n_ring < 210 (202 inv + 8 nand)"
    exit 1
}

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
# TRNG RO rider: now that the design is mapped, preserve is legal -- pin the
# surviving ring wrappers hard for syn_opt, then re-census (FATAL if any
# ring stage was lost between elaboration and the mapped netlist).
set ro_hinsts_postmap [get_db hinsts *u_ro*]
set n_ring_postmap 0
foreach h $ro_hinsts_postmap {
    if { [string match *inv* $h] || [string match *nand* $h] } { incr n_ring_postmap }
}
puts "TRNG RO census (post-map): $n_ring_postmap inverter/nand wrappers"
if { $n_ring_postmap < 210 } {
    puts "FATAL: TRNG RO post-map census $n_ring_postmap < 210 -- ring collapse"
    exit 1
}
set_db $ro_hinsts_postmap .preserve true
syn_opt

################################################################################
# Reports
################################################################################
puts "Generating reports"
report_area           > $REPORT_DIR/$BASENAME.area.rpt
report_gates          > $REPORT_DIR/$BASENAME.gates.rpt
report_timing         > $REPORT_DIR/$BASENAME.timing.rpt
report_design_rules   > $REPORT_DIR/$BASENAME.rules.rpt
# NOTE: report_power + report_clock_gating are DEFERRED to the very end of the
# script (after write_sdf), preceded by `reset_clock SDA_IN` -- see the GENUS
# 19.15 degenerate-single-flop-clock power-zeroing defect note in the header.
# Per-cost-group WNS negative controls: the timed digperiph serial/protocol
# cores MUST be real (an empty report = a domain was wrongly cut, the M9c mode).
report_timing -group qspi0_baud_group -max_paths 10 > $REPORT_DIR/$BASENAME.qspi0_baud.rpt
report_timing -group i3c0_baud_group  -max_paths 10 > $REPORT_DIR/$BASENAME.i3c0_baud.rpt
report_timing -group nfc0_rf_group    -max_paths 15 > $REPORT_DIR/$BASENAME.nfc0_rf.rpt
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
# GENUS 19.15 DEGENERATE-CLOCK POWER WORKAROUND (see header + I3C.genus.tcl L354
# + the degenerate-clock power-bug memory note): SDA_IN drives exactly ONE leaf
# flop (i3c0/ibi_req), and 19.15 then silently zeroes internal+switching power
# for the WHOLE design in report_power AND report_clock_gating (leakage
# survives; PWRA-0007 "Completed successfully", no warning). Every honest-SDC-
# dependent output above (timing + the per-group negative controls +
# write_sdc/sdf/script) is already emitted with the real SDA_IN clock/domain/
# false_path intact, so retiring SDA_IN for these two reports only is safe.
################################################################################
reset_clock -clock [get_clocks i3c0_sda]
report_power -by_hierarchy -levels 4 > $REPORT_DIR/$BASENAME.power.rpt
report_clock_gating   > $REPORT_DIR/$BASENAME.clk.rpt

################################################################################
# End of Script
################################################################################
toc
set total_run_time [getHMS $START_TIME $STOP_TIME]
puts "Genus MCU_WOUND run is complete. Run time $total_run_time"

exit
