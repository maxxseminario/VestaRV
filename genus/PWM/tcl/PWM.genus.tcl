################################################################################
#
# Genus TCL script -- PWM standalone peripheral synthesis
# (digital-peripherals program, gate-closure ritual step 2 -- peripheral #5).
#
# Cloned from tcl/RTC.genus.tcl (same procs, lib-setup idiom, M9b per-module
# boundary_opto discipline). STANDALONE block run: no power intent / CPF, no
# SRAM/pmk libs. PWM.vhd instantiates NO components (no ClkGate/ClkDivPower2/
# ClockMuxGlitchFree): the prescaler is a counter-compare producing a 1-clk
# ENABLE (psc_tick, D6), never a gated/generated clock. Expected to synthesize
# clean first try like QSPI/RTC did (pwm_design.md "Gate closure").
#
# ---------------------------------------------------------------------------
# CLOCK TREE OF THE BLOCK (the HONEST SDC -- see the report-back for rationale)
# ---------------------------------------------------------------------------
# PWM is a TWO-clock block (SIMPLER than the RTC -- no third LFXT domain, no
# metastability CDC). There are NO generated (ICG) clocks -- PWM.vhd has ZERO
# component instantiations. Both clocks are primary input pins driving real leaf
# flops:
#
#   clk     free-running MCLK at integration (D1). Hosts the ENTIRE engine:
#           B2 15-bit prescaler counter-compare (process prescaler, PWM.vhd),
#           B3 16-bit main up-counter + shadow->active commit (counter_commit),
#           B4 registered 16-bit magnitude compare + output mux (compare_stage
#           + the pwm_out combinational mux), B5 fault trip + sticky FLTF and
#           B6 sticky PEVF + UPDF + the IRQ combiner (process flags). It MUST
#           free-run so the counter / PEVF / FLTF advance while the bus is idle
#           (the QSPI/I3C/NFC/RTC `clk` role). Reset via resetn directly (D15:
#           single clock family, no always-on domain -- NO reset synchronizer).
#
#   ClkMem  register-bus clock (gated in the SoC; an input clock at this
#           boundary). Clocks the B1 register file (reg_write / reg_read): CR,
#           POL (immediate, D11), the PER/DTY0/DTY1 staging regs, the D2
#           request/clear toggles (upd_req_tgl / flt_req_tgl / clr_flt_tgl /
#           clr_pev_tgl), and the synchronous read register rdata_out.
#
#   NO EnMemPeriph CLOCK (the same structural point RTC makes, D4): PWM NEVER
#   edges on EnMemPeriph. There is NO falling_edge of anything anywhere in
#   PWM.vhd -- EnMemPeriph is consumed ONLY as an active-low LEVEL qualifier
#   sampled on rising ClkMem (slot decode + write enable + read-mux gate). So
#   EnMemPeriph stays PURE DATA, budgeted vs ClkMem -- it gets no create_clock.
#   PWM is (like RTC) the library slave that is neither combinationalRead nor in
#   the CAPTURE_CLOCK shim set.
#
#   NO GENERATED CLOCKS: the prescaler is a counter-compare producing a 1-clk
#   tick ENABLE (psc_tick), gated only as an enable TERM in the D-input logic --
#   never a ClkGate baud divider (contrast QSPI/I3C's create_generated_clock on
#   cg_clk_baud*), never a ClockMuxGlitchFree divided clock (contrast TIMER).
#   There is nothing to declare.
#
#   NO lfxt: PWM is a single MCLK family (D1) -- no 32.768 kHz wall-clock domain
#   (contrast the RTC's real rtc_lfxt). Both clocks are the SAME physical mclk
#   net at integration.
#
#   PERIOD DECISION (20 ns for BOTH clk and ClkMem -- the BENCH-DRIVEN rate;
#   orchestrator honest-SDC precedent, RTC A6 / NFC rf_clk):
#     The design MCLK is ~40 ns / 24-25 MHz, the NFC/I3C/QSPI/RTC class value.
#     But the standalone bench (PWM_tb.vhd) drives clk with PERIOD = 20 ns and
#     ClkMem gated from that SAME net (ClkMem <= clk when en_mem='0' else '0'),
#     so the SDF gate sim is driven at 20 ns. We constrain BOTH clocks AT 20 ns
#     -- the BENCH RATE is what the netlist must actually meet, and 20 ns is the
#     HARDER of the two (2x tighter than the 40 ns real MCLK), so constraining
#     at 20 ns BOUNDS the real-silicon 40 ns MCLK-class case too. This differs
#     from the RTC tcl, which constrained clk/ClkMem at 40 ns because its
#     clk/ClkMem cones were shallow synchronizer + register-file logic; PWM's
#     `clk` cone is DEEPER (a 16-bit up-counter add + two 16-bit magnitude
#     comparators + the shadow-commit datapath), so we honestly target the
#     20 ns rate the SDF gate sim runs at rather than relying on slack margin.
#     An honest gate closure targets the harder of the two rates the bench and
#     silicon present.
#
# CLOCK GROUPS / CDC (two asynchronous groups -- follows the RTC house pattern,
# which declared clk vs ClkMem -asynchronous even though they are the SAME mclk
# net at integration):
#   clk and ClkMem are the SAME physical mclk net at integration (D1); there is
#   NO metastability CDC in this block (contrast the RTC's genuine LFXT<->clk
#   crossings, which needed 2-FF synchronizers). The only inter-"domain" paths
#   are the D2 hand-offs, and every one is a REGISTERED level or a single-clock
#   toggle edge-detect, kept standalone-honest:
#     (1) ClkMem -> clk: the quasi-static stage_per/stage_dty0/stage_dty1 (D9,
#         sampled only at the period boundary), the held CR/POL config levels
#         (pwmen_r/ch*en_r/psc_r/flten_r/fltie_r/pevie_r/pol*_r/safe*_r feeding
#         the engine + output mux), and the request/clear toggles
#         (upd_req_tgl/flt_req_tgl/clr_flt_tgl/clr_pev_tgl) single-clock
#         edge-detected in the process that owns each flag (SET wins over CLEAR).
#     (2) clk -> ClkMem: the sticky levels fltf_flag/pevf_flag/upd_pending read
#         directly by the ClkMem read mux. Held levels.
#   These are declared -asynchronous (belt-and-suspenders: the two are the same
#   net at integration, and every hand-off is a toggle or a held/quasi-static
#   level, never an async clear crossing a domain -- the ROOT-2 discipline). The
#   toggle/level structure makes them false-path/quasi-static, so no extra
#   set_false_path beyond the grouping is fabricated (RTC/NFC/I3C discipline: do
#   NOT invent false paths the grouping already covers).
#   CRITICAL (the RTC lfxt2lfxt non-mistake): the REAL single-cycle paths stay
#   INSIDE their group and ARE timed -- clk<->clk (the whole prescaler /
#   16-bit counter / 16-bit compare / shadow-commit / fault / flag engine) at
#   20 ns, ClkMem<->ClkMem (the register file + read mux) at 20 ns.
#   rpt/PWM.genus.clk2clk.rpt is the mandatory negative control proving the
#   engine datapath is TIMED, not cut (an empty report = the counter/compare
#   core wrongly false-pathed).
#
################################################################################

set INPUT_DIR        ../common/in
set OUTPUT_DIR       out
set REPORT_DIR       rpt
set HDL_DIR          ../../hdl

set TOP_MODULE       PWM
set BASENAME         PWM.genus

# BOTH clocks at the 20 ns bench-driven rate (50 MHz) -- the SDF gate sim runs
# here, and 20 ns bounds the 40 ns real MCLK (see the PERIOD DECISION header).
set base_freq        50
set freq_mult        1
set MCLK_FREQ        [expr $base_freq * $freq_mult]
set MCLK_PERIOD      [expr 1 / [expr $MCLK_FREQ * 0.001]]
puts "Target clk/ClkMem frequency: $MCLK_FREQ MHz (period $MCLK_PERIOD ns, the bench rate)"

# I/O budget: half-period default on all registered interfaces.
set IO_BUDGET_HALF   [expr $MCLK_PERIOD / 2.0]  ;# 10 ns

################################################################################
# Procedures (verbatim from the tile flow / QSPI / I3C / NFC / RTC)
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

# Keep the netlist module named plain "PWM" (suppress the generic-value suffix).
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
# post-elaborate (M9b).
set_db lp_insert_clock_gating true
set_db lp_clock_gating_register_aware true

set_dont_use TIEHIX1MA10TH false
set_dont_use TIELOX1MA10TH false
set_db use_tiehilo_for_const duplicate

################################################################################
# Read HDL -- PWM's RTL dependency set (behavioral cell_list order). PWM.vhd has
# NO component instantiations (no ClkGate/ClkDivPower2) and does not reference
# constants/MemoryMap in its architecture; constants.vhd + MemoryMap.vhd are read
# for work-lib completeness / template fidelity (proven to compile in the
# NFC/I3C/RTC flows) and are not pulled by elaborate.
################################################################################
puts "Reading HDL (PWM subset)"
set MP $HDL_DIR/common

# VHDL sources use 2008 delimited comments
set_db hdl_vhdl_read_version 2008
read_hdl -vhdl -library work $MP/constants.vhd
read_hdl -vhdl -library work $MP/MemoryMap.vhd
read_hdl -vhdl -library work $MP/periph/PWM.vhd

################################################################################
# Elaboration
################################################################################
puts "Elaborating $TOP_MODULE"
elaborate $TOP_MODULE

set DESIGN_NAME [get_db [get_db designs] .name]
puts "Elaborated design name: $DESIGN_NAME"
if {$DESIGN_NAME ne "PWM"} {
	puts "WARNING: design name is '$DESIGN_NAME', not 'PWM' -- fix naming"
}

# M9b GATE-SIM FIX: per-MODULE boundary_opto disable (root attr ignored).
set_db [get_db modules] .boundary_opto false
puts "boundary_opto disabled on [llength [get_db modules]] modules"

# NO power intent / CPF for this standalone block run.

################################################################################
# Constraints
################################################################################

# --- Primary clocks: clk/ClkMem BOTH at 20 ns (the bench rate). Both are
#     primary input pins. NO EnMemPeriph clock (D4 -- never an edge), NO
#     generated clocks (no ClkGate baud divider; the prescaler is a tick ENABLE,
#     D6), NO lfxt (single MCLK family, D1). See the header. ---
create_clock -name clk    -period $MCLK_PERIOD [get_ports clk]
create_clock -name ClkMem -period $MCLK_PERIOD [get_ports ClkMem]

# --- CDC: two asynchronous groups (RTC house pattern -- clk vs ClkMem declared
#     -asynchronous even though they are the SAME mclk net at integration; every
#     hand-off is a toggle or a held/quasi-static level, D2). Real single-cycle
#     paths stay INSIDE a group and are timed. ---
set_clock_groups -asynchronous \
	-group {clk} \
	-group {ClkMem}

# --- Cost/path groups: clk hosts the prescaler/counter/compare/output/fault/
#     flag engine; ClkMem the register file + read mux. ---
define_cost_group -name clk_group    -weight 1
define_cost_group -name clkmem_group -weight 1
path_group -from clk    -group clk_group
path_group -from ClkMem -group clkmem_group

# --- I/O budgets ---------------------------------------------------------------
# Register-bus inputs: software-written registers + the write decode, registered
# by reg_write on the ClkMem edge -> half-period (10 ns). EnMemPeriph carries a
# DATA role ONLY (active-low slot decode / write qualify, D4 -- NEVER a clock),
# budgeted here; it is quasi-static (stable for the whole selected access) so
# 10 ns is generous. No clk-domain process reads the raw bus ports (they are
# consumed only by the ClkMem-domain reg_write/reg_read), so no second `clk`
# input budget is needed (the RTC treatment exactly).
set MEM_IN  [get_db ports {WEn[*] MABPart[*] wdata[*] EnMemPeriph}]
set_input_delay  -clock [get_db clocks ClkMem] $IO_BUDGET_HALF $MEM_IN

# Register-bus output: rdata_out is a ClkMem flop -> half-period vs ClkMem.
set_output_delay -clock [get_db clocks ClkMem] $IO_BUDGET_HALF [get_db ports {rdata_out[*]}]

# Engine outputs: pwm_out is the combinational output mux over clk-domain
# registered levels (raw0/raw1) + quasi-static POL/safe/enable/fault levels
# (D8); irq_fault/irq_evt are combinational (status and enable) off clk-domain
# sticky flags (D18). All three are sampled downstream on the FREE-RUNNING mclk
# (the on-chip interrupt router / the AF-spread pad path) -- ClkMem is GATED and
# stops, so it cannot sample them. Budget vs `clk` (the honest sampling clock;
# the NFC/RTC irq-vs-clk treatment, forced by clk being a real leaf mclk domain).
set_output_delay -clock [get_db clocks clk] $IO_BUDGET_HALF [get_db ports {pwm_out[*] irq_fault irq_evt}]

# Async reset: applied DIRECTLY to both the clk engine and the ClkMem register
# file (D15 -- single clock family, no reset synchronizer), huge recovery margin
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

# Honesty negative controls (an empty report = a domain was wrongly cut):
#   clk2clk is the CRITICAL one -- the entire engine datapath (the 15-bit
#   prescaler counter, the 16-bit main-counter add, the two 16-bit magnitude
#   comparators, the shadow-commit + fault/flag logic) MUST be timed at 20 ns.
#   This proves the clk domain is TIMED, not cut.
report_timing -from [get_db clocks clk] -to [get_db clocks clk] -max_paths 15 \
	> $REPORT_DIR/$BASENAME.clk2clk.rpt
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
puts "Genus PWM run is complete. Run time $total_run_time"

exit
