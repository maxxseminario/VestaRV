################################################################################
#
# Genus TCL script -- RTC standalone peripheral synthesis
# (digital-peripherals program, gate-closure ritual step 2 -- peripheral #4).
#
# Cloned from tcl/NFC.genus.tcl (same procs, lib-setup idiom, M9b per-module
# boundary_opto discipline). STANDALONE block run: no power intent / CPF, no
# SRAM/pmk libs. The RTC is the pin-free warm-up: a plain counter datapath with
# NO combinational-explosion cone (unlike NFC ACT_COMPOSE) and NO dual-edge
# process (unlike I3C bus_sensor) -- it is expected to synthesize clean first try
# like QSPI did (rtc_design.md "Gate closure").
#
# ---------------------------------------------------------------------------
# CLOCK TREE OF THE BLOCK (the HONEST SDC -- see the report-back for rationale)
# ---------------------------------------------------------------------------
# RTC is a THREE-clock block. There are NO generated (ICG) clocks -- RTC.vhd has
# ZERO component instantiations (no ClkGate/ClkDivPower2): the LFXT engines count
# lfxt_in DIRECTLY (the NFC rf_clk pattern, not the QSPI/I3C two-ClkGate baud
# scheme). Every clock is a primary input pin driving real leaf flops:
#
#   clk         free-running fast reference, WIRED TO MCLK at integration
#               (orchestrator adj. A2 -- NOT smclk). It hosts the ENTIRE B2 CDC
#               block (process clk_cdc, RTC.vhd L302): the D7 cap_tgl 2-FF
#               synchronizer + snap_lfxt->snap_sync sampler, the D8 wr_ack 2-FF
#               sync + SR.SYNC busy level, the D10 alm_tgl/tick_tgl event 2-FF
#               syncs + edge-detect -> sticky ALMF/TICKF, and the D10 W1C clear
#               toggles. ClkMem is GATED and cannot host synchronizers, so `clk`
#               does -- exactly the role NFC/I3C/QSPI give their free-running clk
#               (D2). Constrained 40 ns (see the PERIOD DECISION below).
#
#   ClkMem      register-bus clock (gated in the SoC; an input clock at this
#               boundary). Clocks the B1 register file (reg_write RTC.vhd L215,
#               reg_read L275): all 6 live slots (CR/SEC/SUB/ALM/PER/SR), the D8
#               staging regs + commit_mask + wr_req_tgl toggle, the D10 W1C
#               clr_*_tgl toggles, and the synchronous read register rdata_out.
#               Constrained 40 ns.
#
#   rtc_lfxt    = lfxt_in, the UNGATED 32.768 kHz always-on wall-clock crystal
#               (D1). Clocks the whole LFXT domain: the B3 47-bit {sec_cnt,
#               sub_cnt} single binary counter + atomic set-time load, the D7
#               snap_lfxt/cap_tgl read double-buffer, the B4 32-bit alarm equality
#               compare + rising-edge detect -> alm_tgl, the B5 periodic
#               down-counter -> tick_tgl, the D9 RTCEN/ALMEN/TICKEN enable
#               synchronizers, the D8 wr_req apply + wr_ack toggle, and the D14
#               reset synchronizer (rtc_lfxt_rstn). Constrained 100 ns (see below).
#
#   NO EnMemPeriph CLOCK (the KEY structural difference from QSPI/I3C/NFC): the
#   RTC is xcollapse-clean by construction (D4). Unlike QSPI/I3C/NFC -- which
#   declare EnMemPeriph a negedge clock for a falling_edge(EnMemPeriph) read
#   pre-latch -- RTC NEVER edges on EnMemPeriph. It is consumed ONLY as an
#   active-low LEVEL qualifier sampled on rising ClkMem (slot decode + write
#   enable + read-mux gate, RTC.vhd L206/L228). There is NO falling_edge of
#   anything anywhere in RTC.vhd. So EnMemPeriph stays PURE DATA, budgeted vs
#   ClkMem -- it gets no create_clock. This is the whole point of the block being
#   the first library slave that is neither combinationalRead nor in the
#   CAPTURE_CLOCK shim set.
#
#   NO GENERATED CLOCKS: there is no ClkGate baud divider to declare (contrast
#   QSPI/I3C's create_generated_clock on cg_clk_baud*). The LFXT engines count
#   lfxt_in directly, gated only by synchronized enable LEVELS inside the D-input
#   logic (never by gating a clock).
#
#   LFXT PERIOD DECISION (100 ns, NOT the real ~30518 ns 32.768 kHz crystal --
#   orchestrator adjudication, 2026-07-20):
#     The real crystal is 32.768 kHz => 30517.6 ns. We constrain rtc_lfxt at
#     **100 ns** instead, on purpose -- the SAME honest-SDC logic the NFC header
#     applies to rf_clk (its RF_CLK PERIOD DECISION, 50 ns not 73.75 ns):
#       - The standalone bench (RTC_tb.vhd) drives lfxt_in with LFXT_HALF = 50 ns
#         => a 100 ns period (a COMPRESSED crystal, so a few seconds of wall clock
#         = ~100k lfxt edges fits well under the sim watchdog). The SDF gate sim is
#         driven at exactly this 100 ns, so 100 ns is what the netlist must meet.
#       - 100 ns is 305x FASTER (more conservative) than the real 30518 ns
#         crystal, so constraining at 100 ns bounds the real-silicon case too.
#       - Constraining at the real 30518 ns would UNDER-constrain relative to what
#         the bench drives -- an honest gate closure targets the harder of the two.
#     The 32768 prescaler modulus is FIXED (exact 1 Hz, D6) -- the compression is
#     a bench clock rate, not an RTL divisor change.
#
#   clk / ClkMem PERIOD NOTE (40 ns per the orchestrator deliverable spec): the
#   design MCLK is ~40 ns / 24-25 MHz (A2), and 40 ns is the NFC/I3C/QSPI class
#   value. The RTC bench happens to drive clk/ClkMem 2x faster (PERIOD = 20 ns in
#   RTC_tb.vhd) purely to give the LFXT->clk 2-FF CDC a real fast/slow ratio; the
#   clk/ClkMem cones here are shallow synchronizer + register-file + read-mux
#   logic (no deep combinational cone), so the netlist synthesized at 40 ns meets
#   the 20 ns bench rate with margin -- proven by the SDF gate sim running at
#   20 ns. (Contrast lfxt, whose deep-ish 47-bit add / 32-bit compare is
#   constrained AT the 100 ns bench rate above.)
#
# CLOCK GROUPS / CDC (three asynchronous groups -- verified crossing by crossing
# against the RTC.vhd header's CDC CROSSING INVENTORY):
#   Every inter-domain path crosses through a DESIGNED single-edge synchronizer
#   (2-FF) or a toggle / held-level / quasi-static handshake, so the three domains
#   are declared -asynchronous. The crossings, each checked in the RTL:
#     (1) rtc_lfxt -> clk: D7 cap_tgl 2-FF into clk, edge-detect, sample the
#         quasi-static snap_lfxt (data settled ~1 lfxt period before its flag
#         crossed -- data-before-flag); D10 alm_tgl/tick_tgl 2-FF into clk,
#         edge-detect -> sticky flags (one clk edge per event); D8 wr_ack_tgl 2-FF
#         into clk (sync_busy compares it vs the raw request toggle).
#     (2) ClkMem -> rtc_lfxt: D8 wr_req_tgl 2-FF into lfxt, edge-detect -> apply
#         the quasi-static stage_*/commit_mask (false-path buses by construction);
#         D9 RTCEN/ALMEN/TICKEN held levels 2-FF into lfxt.
#     (3) ClkMem -> clk: D10 W1C clr_*_tgl 2-FF into clk, edge-detect -> clear the
#         sticky flag in the SAME process that owns it (no clear-pulse re-crosses
#         to LFXT). clk<->ClkMem are the SAME mclk net at integration (A2); kept
#         standalone-honest as separate async groups here -- every hand-off is a
#         toggle or a held/quasi-static level, never an async clear crossing a
#         domain.
#   The multi-bit buses (snap_lfxt/snap_sync, stage_*/commit_mask) are
#   false-path/quasi-static by the toggle + data-before-flag structure, so they
#   need no extra set_false_path beyond the -asynchronous grouping (NFC/I3C
#   template discipline: do NOT fabricate false paths the grouping already covers).
#   CRITICAL (the NFC rf2rf / I3C baud2baud non-mistake): the REAL single-cycle
#   paths stay INSIDE their group and ARE timed -- rtc_lfxt<->rtc_lfxt (the whole
#   wall-clock counter + alarm compare + tick down-counter) at 100 ns,
#   clk<->clk and ClkMem<->ClkMem at 40 ns. rpt/RTC.genus.lfxt2lfxt.rpt is the
#   mandatory negative control proving the LFXT domain is TIMED, not cut (an empty
#   report = the counter/compare/tick core wrongly false-pathed).
#
################################################################################

set INPUT_DIR        ../common/in
set OUTPUT_DIR       out
set REPORT_DIR       rpt
set HDL_DIR          ../../hdl

set TOP_MODULE       RTC
set BASENAME         RTC.genus

# 25 MHz smclk/MCLK class for clk/ClkMem, same as the proven flows (40 ns).
set base_freq        25
set freq_mult        1
set MCLK_FREQ        [expr $base_freq * $freq_mult]
set MCLK_PERIOD      [expr 1 / [expr $MCLK_FREQ * 0.001]]
puts "Target clk/ClkMem frequency: $MCLK_FREQ MHz (period $MCLK_PERIOD ns)"

# I/O budget: half-period default on all registered interfaces.
set IO_BUDGET_HALF   [expr $MCLK_PERIOD / 2.0]  ;# 20 ns

# rtc_lfxt: the ungated 32.768 kHz wall-clock crystal, constrained at 100 ns
# (the compressed-crystal bench rate; 305x conservative vs the real 30518 ns AND
# matching what the SDF gate sim is driven at -- see the header LFXT PERIOD
# DECISION).
set LFXT_PERIOD      100.0
set LFXT_BUDGET_HALF [expr $LFXT_PERIOD / 2.0]   ;# 50 ns (unused: no LFXT I/O ports)
puts "Target rtc_lfxt frequency: 10 MHz (period $LFXT_PERIOD ns, compressed crystal)"

################################################################################
# Procedures (verbatim from the tile flow / QSPI / I3C / NFC)
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

# Keep the netlist module named plain "RTC" (suppress the generic-value suffix).
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
# Read HDL -- RTC's RTL dependency set (behavioral cell_list order). RTC.vhd has
# NO component instantiations (no ClkGate/ClkDivPower2) and does not reference
# constants/MemoryMap in its architecture; constants.vhd + MemoryMap.vhd are read
# for work-lib completeness / template fidelity (proven to compile in the
# NFC/I3C flows) and are not pulled by elaborate.
################################################################################
puts "Reading HDL (RTC subset)"
set MP $HDL_DIR/common

# VHDL sources use 2008 delimited comments
set_db hdl_vhdl_read_version 2008
read_hdl -vhdl -library work $MP/constants.vhd
read_hdl -vhdl -library work $MP/MemoryMap.vhd
read_hdl -vhdl -library work $MP/periph/RTC.vhd

################################################################################
# Elaboration
################################################################################
puts "Elaborating $TOP_MODULE"
elaborate $TOP_MODULE

set DESIGN_NAME [get_db [get_db designs] .name]
puts "Elaborated design name: $DESIGN_NAME"
if {$DESIGN_NAME ne "RTC"} {
	puts "WARNING: design name is '$DESIGN_NAME', not 'RTC' -- fix naming"
}

# M9b GATE-SIM FIX: per-MODULE boundary_opto disable (root attr ignored).
set_db [get_db modules] .boundary_opto false
puts "boundary_opto disabled on [llength [get_db modules]] modules"

# NO power intent / CPF for this standalone block run.

################################################################################
# Constraints
################################################################################

# --- Primary clocks: clk/ClkMem at 40 ns; rtc_lfxt(=lfxt_in) at 100 ns. All
#     three are primary input pins. NO EnMemPeriph clock (D4 -- never an edge),
#     NO generated clocks (no ClkGate baud divider). See the header. ---
create_clock -name clk      -period $MCLK_PERIOD [get_ports clk]
create_clock -name ClkMem   -period $MCLK_PERIOD [get_ports ClkMem]
# rtc_lfxt is the ungated 32.768 kHz wall-clock crystal (100 ns; see header).
create_clock -name rtc_lfxt -period $LFXT_PERIOD [get_ports lfxt_in]

# --- CDC: three asynchronous groups (see header -- each crossing verified in the
#     RTL to go through a 2-FF synchronizer or a toggle/held-level handshake).
#     Real single-cycle paths stay INSIDE a group and are timed. ---
set_clock_groups -asynchronous \
	-group {clk} \
	-group {ClkMem} \
	-group {rtc_lfxt}

# --- Cost/path groups: rtc_lfxt hosts the counter/compare/tick datapath; ClkMem
#     the register file. ---
define_cost_group -name lfxt_group   -weight 1
define_cost_group -name clkmem_group -weight 1
path_group -from rtc_lfxt -group lfxt_group
path_group -from ClkMem   -group clkmem_group

# --- I/O budgets ---------------------------------------------------------------
# Register-bus inputs: software-written registers + the write decode, registered
# by reg_write on the ClkMem edge -> half-period (20 ns). EnMemPeriph carries a
# DATA role ONLY (active-low slot decode / write qualify, D4 -- NEVER a clock),
# budgeted here; it is quasi-static (stable for the whole selected access) so
# 20 ns is generous. No second `clk` budget is needed -- unlike I3C's dat_proc,
# NO clk- or lfxt-domain process reads the raw bus ports (they are consumed only
# by the ClkMem-domain reg_write/reg_read).
set MEM_IN  [get_db ports {WEn[*] MABPart[*] wdata[*] EnMemPeriph}]
set_input_delay  -clock [get_db clocks ClkMem] $IO_BUDGET_HALF $MEM_IN

# Register-bus output: rdata_out is a ClkMem flop -> half-period vs ClkMem.
set_output_delay -clock [get_db clocks ClkMem] $IO_BUDGET_HALF [get_db ports {rdata_out[*]}]

# IRQ output: irq_rtc = (ALMF and ALMIE) or (TICKF and TICKIE), combinational
# (D13). The sticky flags live in the `clk` (mclk ref) domain (clk_cdc) and the
# enables in ClkMem (RTC0CR). The on-chip interrupt router samples irq_rtc on the
# FREE-RUNNING mclk -- ClkMem is GATED and stops, so it cannot sample it. Budget
# vs `clk` (the honest sampling clock; the NFC irq-vs-clk treatment exactly,
# forced by clk being a real leaf mclk domain rather than source-only).
set_output_delay -clock [get_db clocks clk] $IO_BUDGET_HALF [get_db ports {irq_rtc}]

# No lfxt_in-domain primary I/O ports exist: lfxt_in is a clock input only, and
# every bus input/output is sampled/driven in the ClkMem/clk domains. So there is
# no rtc_lfxt set_input_delay / set_output_delay (LFXT_BUDGET_HALF is unused).

# Async reset: POR-synchronized deassertion (D14 -- the LFXT domain gets a 2-FF
# reset synchronizer, the mclk/ClkMem domains use resetn directly), huge recovery
# margin (same treatment the proven flows give resetn).
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
#   lfxt2lfxt is the CRITICAL one -- the entire wall-clock datapath (the 47-bit
#   {sec_cnt,sub_cnt} counter carry chain, the 32-bit alarm equality comparator,
#   the periodic down-counter) MUST be timed at 100 ns. This proves the LFXT
#   domain is TIMED, not cut.
report_timing -from [get_db clocks rtc_lfxt] -to [get_db clocks rtc_lfxt] -max_paths 15 \
	> $REPORT_DIR/$BASENAME.lfxt2lfxt.rpt
report_timing -from [get_db clocks clk] -to [get_db clocks clk] -max_paths 10 \
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
puts "Genus RTC run is complete. Run time $total_run_time"

exit
