################################################################################
#
# Genus TCL script -- I3C standalone peripheral synthesis
# (digital-peripherals program, Stage (a)+(b) gate-closure).
#
# Cloned from tcl/QSPI.genus.tcl (same procs, lib-setup idiom, M9b per-module
# boundary_opto discipline, M9c generated-clock-of-source rule). STANDALONE
# block run: no power intent / CPF, no SRAM/pmk libs.
#
# ---------------------------------------------------------------------------
# CLOCK TREE OF THE BLOCK (the HONEST SDC -- see the report-back for rationale)
# ---------------------------------------------------------------------------
# I3C shares QSPI's house style (registered read, two-chained-ClkGate baud
# divider, W1C clear-pulse retirement, transaction-local launch latching) --
# see I3C.vhd's header. The clock tree is a SUPERSET of QSPI's:
#
#   clk         smclk-class serial-core source, 25 MHz / 40 ns. Feeds the two
#               ClkGate instances (cg_clk_baud_src, cg_clk_baud -- SAME instance
#               names as QSPI, verified in the RTL) through an inverter
#               (ClkIn => not clk). UNLIKE QSPI, `clk` ALSO directly clocks a
#               real leaf process: dat_proc (the DAT register-file storage,
#               see below) -- so `clk` is not purely a source-only net here.
#
#   ClkMem      register-bus clock (25 MHz / 40 ns), as QSPI. Clocks the
#               software registers (I3CxCR/CMD/TX), the launch/tx_arm/W1C
#               clear-pulse flops, and the synchronous read register rdata_out
#               (reg_write / reg_read, both `rising_edge(ClkMem)`).
#
#   EnMemPeriph active-low peripheral select, 25 MHz / 40 ns class, same
#               dual role as QSPI: (1) REAL negedge CLOCK for the reg_sync
#               pre-latch (I3CxRX_ltch/I3CxSR_ltch <= not I3CxRX/I3CxSR on
#               falling_edge(EnMemPeriph)); (2) DATA -- slot decode / write
#               qualify -- consumed by BOTH the ClkMem-domain reg_write/
#               reg_read AND (I3C-specific, see below) the clk-domain dat_proc.
#
#   clk_baud_src / clk_baud   GENERATED clocks = ICG(not clk, en_*). divide_by 1
#               each (an ICG only masks pulses, never stretches the period --
#               the M9c/QSPI precedent). clk_baud clocks the entire bit-engine +
#               framer FSM (fsm_proc: ph/sub/bitno/shift/rx_acc/tx_byte, the
#               status flags, the DAA/IBI sub-sequencers, the pad-drive
#               intents) exactly like QSPI's serial core.
#
#   AS-BUILT STRUCTURAL DIFFERENCE #1 -- dat_proc on the FREE-RUNNING clk:
#   I3C.vhd's B5 DAT register file (dat_evalid/dynaddr/dynvalid/stataddr/
#   statvalid/pid/bcr/dcr/dat_idx, slots 5-7) is owned by ONE process
#   (dat_proc, line ~445) clocked by `rising_edge(clk)` -- NOT ClkMem. The RTL
#   comment states this is "equivalent to reg_write's rising_edge(ClkMem)+
#   EnMemPeriph='0' since ClkMem=clk while selected" (an as-built SoC-level
#   assumption -- see the report-back open question). Firmware writes to
#   slots 5/6/7 are captured on `clk` under EnMemPeriph='0'/WEn(0)='0', reading
#   the SAME wdata/WEn/MABPart/EnMemPeriph ports reg_write/reg_read consume on
#   ClkMem. Since this run keeps ClkMem and clk in SEPARATE (asynchronous)
#   clock groups -- an honest simplification, not a proof that they're the
#   same net -- the register-bus ports need a SECOND budget vs `clk` (in
#   addition to the existing ClkMem budget) so dat_proc's capture path is
#   actually timed, not silently exempted by the async grouping. See the I/O
#   budget section below.
#
#   AS-BUILT STRUCTURAL DIFFERENCE #2 -- dat_proc DAA-capture handshake:
#   dat_cap_req/dat_dv_req are held levels driven by fsm_proc (clk_baud
#   domain) and edge-detected inside dat_proc (clk domain) so a multi-cycle
#   level commits exactly once. clk_baud is generated FROM clk (ICG on
#   `not clk`), so this crossing stays INSIDE the single serial cost group
#   {clk clk_baud_src clk_baud} -- it is a real, timeable same-source path
#   (just phase-shifted by the inversion), not a genuine async CDC. No extra
#   clock-group declaration needed.
#
#   AS-BUILT STRUCTURAL DIFFERENCE #3 -- B7 async target-START / IBI sensor:
#   ibi_sensor (line ~1230) is directly EDGE-TRIGGERED by SDA_IN
#   (a single falling_edge(SDA_IN) -- the I2C.vhd L261-273 / I2CSTR precedent;
#   the dual-edge bus_busy/bus_start levels were retired, see the RTL), NOT
#   a synchronous process on any of the above clocks. This makes SDA_IN a REAL
#   clock pin for 1 flop (ibi_req), exactly the same structural situation that
#   made EnMemPeriph need create_clock in QSPI. No
#   prior standalone Genus run in this repo has synthesized this SDA_IN-as-
#   clock pattern (I2C.vhd is not yet in genus/tcl); the nearest precedent is
#   MCU.genus.tcl's `create_clock ... hpin:.../i2c0/SCL_IN` for the Myshkin
#   I2C macro (a real, if slow, external-bus clock). I3C's SCL_IN, by
#   contrast, is used ONLY as DATA (level-checked, never edge-triggered) in
#   this design -- it is budgeted as an input relative to SDA_IN's clock.
#   ibi_req is a held-level wake request retired by the FSM's clr_ibi_req --
#   a genuine level-handshake CDC from the external SDA_IN clock domain into
#   clk_baud, so SDA_IN gets ITS OWN async clock group (a 4th group, alongside
#   the serial/ClkMem/EnMemPeriph groups QSPI already has).
#
# SERIAL-SIDE RATE DECISION (per QSPI's kickoff -- do NOT fabricate false
# paths): the FSM registers sit on clk_baud, an ENABLE-gated (period-
# preserving) version of clk. With BR=0 the baud counter is permanently 0, so
# clk_baud pulses on consecutive `not clk` edges -- worst-case reg-to-reg
# separation in the serial core is one 40 ns clk period. The HONEST
# constraint is same-period 25 MHz (divide_by 1), and clk_baud->clk_baud paths
# are timed at 40 ns, NOT relaxed to the average SCL rate.
# (rpt/I3C.genus.baud2baud.rpt is the negative control proving these paths are
# real and timed, not cut -- the M9c failure mode.)
#
# CLOCK GROUPS / CDC:
#   The crossings between the serial core (clk / clk_baud*) and the register
#   bus (ClkMem / EnMemPeriph) are ASYNCHRONOUS BY DESIGN, mirroring QSPI:
#   held-level handshakes with no single-cycle relationship (i3c_launch is a
#   held level sampled by the FSM; the W1C clr_* pulses cross as async
#   resets; I3CxRX/SR are snapshot-latched on the EnMemPeriph select edge).
#   SDA_IN (the B7 bus sensor's real clock) is a genuinely independent
#   external-pad clock and is its OWN 4th async group -- ibi_req is exactly
#   the same held-level-request/FSM-retire CDC shape as i3c_launch/tx_arm,
#   just originating from an external edge instead of the register bus.
#   Real single-cycle paths (clk_baud<->clk_baud, ClkMem<->ClkMem) stay inside
#   one group and ARE timed -- not the M9c false-pathing mistake.
#
################################################################################

set INPUT_DIR        ../common/in
set OUTPUT_DIR       out
set REPORT_DIR       rpt
set HDL_DIR          ../../hdl

set TOP_MODULE       I3C
set BASENAME         I3C.genus

# 25 MHz smclk class, same as the proven flows.
set base_freq        25
set freq_mult        1
set MCLK_FREQ        [expr $base_freq * $freq_mult]
set MCLK_PERIOD      [expr 1 / [expr $MCLK_FREQ * 0.001]]
puts "Target clk/ClkMem frequency: $MCLK_FREQ MHz (period $MCLK_PERIOD ns)"

# I/O budget: half-period default on all registered interfaces.
set IO_BUDGET_HALF   [expr $MCLK_PERIOD / 2.0]  ;# 20 ns

# SDA_IN's own clock (B7 bus sensor, structural difference #3 above). This is
# a genuinely external, asynchronous pad signal -- declared its own group
# (never checked against clk/ClkMem/EnMemPeriph) so the period value has no
# bearing on cross-domain timing; kept at the same 40 ns class purely so
# SDA_IN's own leaf flop (ibi_req) gets a defined, non-degenerate
# setup/hold check rather than an unconstrained clock pin.
set SDA_PERIOD        $MCLK_PERIOD

################################################################################
# Procedures (verbatim from the tile flow / QSPI)
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

# Keep the netlist module named plain "I3C" (suppress the generic-value suffix).
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
# Read HDL -- I3C's RTL dependency set (cell_list_behavioral.txt order, with
# the SYNTHESIZABLE ClkGate wrapper substituted for the sim ClkGate).
################################################################################
puts "Reading HDL (I3C subset)"
set MP $HDL_DIR/common

# VHDL sources use 2008 delimited comments
set_db hdl_vhdl_read_version 2008
read_hdl -vhdl -library work $MP/constants.vhd
read_hdl -vhdl -library work $MP/MemoryMap.vhd
read_hdl -vhdl -library work $MP/commune/ClkGate_cmn65gp_ARM.vhd
read_hdl -vhdl -library work $MP/commune/ClkDivPower2.vhd
read_hdl -vhdl -library work $MP/periph/I3C.vhd

################################################################################
# Elaboration
################################################################################
puts "Elaborating $TOP_MODULE"
elaborate $TOP_MODULE

set DESIGN_NAME [get_db [get_db designs] .name]
puts "Elaborated design name: $DESIGN_NAME"
if {$DESIGN_NAME ne "I3C"} {
	puts "WARNING: design name is '$DESIGN_NAME', not 'I3C' -- fix naming"
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
# SDA_IN is the real edge-triggered clock of the B7 sensor's ibi_req flop
# -- structural difference #3, see header.
create_clock -name SDA_IN -period $SDA_PERIOD [get_ports SDA_IN]

# --- Generated (ICG-gated) serial clocks: divide_by 1 of clk (M9c rule). Both
#     ICGs take `not clk`; Genus traces the inverter -- the intra-serial paths
#     are common-mode w.r.t. that inversion so timing is unaffected. Instance
#     names verified in I3C.vhd (identical to QSPI's). ---
create_generated_clock -name clk_baud_src -divide_by 1 \
	-source port:$TOP_MODULE/clk hpin:$TOP_MODULE/cg_clk_baud_src/ClkOut
create_generated_clock -name clk_baud -divide_by 1 \
	-source port:$TOP_MODULE/clk hpin:$TOP_MODULE/cg_clk_baud/ClkOut

# --- CDC: serial core vs register bus vs select vs external SDA_IN clock are
#     asynchronous (see header). Real single-cycle paths stay INSIDE a group
#     and are timed. ---
set_clock_groups -asynchronous \
	-group {clk clk_baud_src clk_baud} \
	-group {ClkMem} \
	-group {EnMemPeriph} \
	-group {SDA_IN}

# --- Cost/path groups ---
define_cost_group -name clk_baud_group -weight 1
define_cost_group -name clkmem_group   -weight 1
path_group -from clk_baud -group clk_baud_group
path_group -from ClkMem   -group clkmem_group

# --- I/O budgets ---------------------------------------------------------------
# Register-bus inputs: software-written registers + the write decode. Registered
# at the ClkMem edge -> half-period. Also budgeted vs `clk` (structural
# difference #1: dat_proc captures the SAME ports -- wdata/WEn/MABPart/
# EnMemPeriph -- on rising_edge(clk), not ClkMem; with clk and ClkMem in
# separate async groups this second budget is what actually times dat_proc's
# capture path instead of silently exempting it).
set MEM_IN  [get_db ports {WEn[*] MABPart[*] wdata[*] EnMemPeriph}]
set_input_delay  -clock [get_db clocks ClkMem] $IO_BUDGET_HALF $MEM_IN
set_input_delay  -clock [get_db clocks clk]    $IO_BUDGET_HALF $MEM_IN

# Register-bus outputs: rdata_out is a ClkMem flop; irq_* are (flag AND
# enable) observed by the smclk-domain interrupt router -> budget against
# ClkMem, mirroring QSPI's irq_tc/irq_rxf treatment exactly (even though the
# source flags live in the clk_baud domain, same as QSPI's txeif/rxfull/tcif).
set_output_delay -clock [get_db clocks ClkMem] $IO_BUDGET_HALF [get_db ports {rdata_out[*]}]
set_output_delay -clock [get_db clocks ClkMem] $IO_BUDGET_HALF \
	[get_db ports {irq_tc irq_rxf irq_txe irq_nack irq_eod irq_arb irq_daa irq_ibi}]

# Serial (clk_baud) side: SDA_IN/SCL_IN are sampled by the FSM on clk_baud
# (address/data/ACK/T/DAA/IBI phases); SDA_OUT/SDA_DIR/SCL_OUT/SCL_DIR are
# driven from clk_baud flops (scl_r) or combinational off clk_baud-domain
# state (sda_drv/sda_release/sda_pp). Half-period each way. The external I3C/
# I2C bus runs at the slow average SCL rate, so these budgets carry large real
# margin. SCL_IN is DATA only in this design (never edge-triggered here).
set_input_delay  -clock [get_db clocks clk_baud] $IO_BUDGET_HALF [get_db ports {SDA_IN SCL_IN}]
set_output_delay -clock [get_db clocks clk_baud] $IO_BUDGET_HALF \
	[get_db ports {SDA_OUT SDA_DIR SCL_OUT SCL_DIR}]

# SCL_IN is the level qualifier of the START condition sensed in the SDA_IN
# domain (ibi_sensor: SDA falls while SCL_IN='1' -> ibi_req; structural
# difference #3). SCL_IN and SDA_IN are two INDEPENDENT external open-drain bus
# wires: a START/STOP is an off-chip protocol event (the bus master holds SCL
# stable-high while moving SDA), so SCL_IN is guaranteed stable around the
# SDA_IN edge by the BUS PROTOCOL, not by on-chip STA -- and ibi_req is
# resynchronized downstream as a held-level handshake into clk_baud (retired by
# clr_ibi_req). There is no closeable synchronous setup/hold between an async
# input pad and an async external clock pad; the honest constraint is a FALSE
# PATH. (A half-period input_delay here manufactured a phantom ~66 ps setup
# violation on the tiny SCL_IN->ibi_req arc -- the ONLY sub-zero path in the
# block; SCL_IN's REAL synchronous budget is its clk_baud sampling above.)
set_false_path -from [get_db ports SCL_IN] -to [get_db clocks SDA_IN]

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

# GENUS 19.15 POWER-REPORT WORKAROUND: `create_clock -name SDA_IN` (structural
# difference #3 above -- SDA_IN is the edge-trigger clock pin of exactly ONE
# leaf flop, ibi_req, with nothing else in its async clock group) silently
# zeroes internal+switching power for the WHOLE design in report_power AND
# report_clock_gating (leakage survives; PWRA-0007 still says "Completed
# successfully", no warning/error anywhere -- confirmed by A/B isolation,
# independent of the SCL_IN->SDA_IN false_path; lp_default_toggle_percentage
# and lp_asserted_toggle_rate seeded on the clock/port did not help either --
# this looks like a genuine Joules/vectorless engine defect on a degenerate
# single-flop async clock group, not a missing constraint). Every honest-SDC-
# dependent output above (timing, the negative controls, write_sdc/write_sdf/
# write_script) is already emitted with the real SDA_IN clock/group/
# false_path intact, so nothing below this point needs it -- safe to retire
# it for these two reports only (verified byte-identical netlist/SDC vs. the
# pre-fix run in a scratch A/B; see the report-back).
reset_clock -clock [get_clocks SDA_IN]
report_power -by_hierarchy -levels 4 > $REPORT_DIR/$BASENAME.power.rpt
report_clock_gating   > $REPORT_DIR/$BASENAME.clk.rpt

toc
set total_run_time [getHMS $START_TIME $STOP_TIME]
puts "Genus I3C run is complete. Run time $total_run_time"

exit
