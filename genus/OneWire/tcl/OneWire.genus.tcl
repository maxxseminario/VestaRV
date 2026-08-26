################################################################################
#
# Genus TCL script -- OneWire (Dallas/Maxim 1-Wire MASTER) standalone synthesis
# (digital-peripherals program, gate-closure ritual step 2 -- peripheral #5).
#
# Cloned from tcl/PWM.genus.tcl (same procs, lib-setup idiom, M9b per-module
# boundary_opto discipline, and the two-clock-same-family PERIOD DECISION).
# STANDALONE block run: no power intent / CPF, no SRAM/pmk libs. OneWire.vhd
# instantiates NO components (no ClkGate/ClkDivPower2/ClockMuxGlitchFree): the
# OW0DIV time base is a counter-compare producing a 1-clk ENABLE (`tick`, D6),
# never a gated/generated clock. Expected to synthesize clean first try like
# QSPI/RTC/PWM did (onewire_design.md "Gate closure").
#
# ---------------------------------------------------------------------------
# CLOCK TREE OF THE BLOCK (the HONEST SDC -- see the report-back for rationale)
# ---------------------------------------------------------------------------
# OneWire is a TWO-clock block (a single MCLK family, D1 -- SIMPLER than the RTC:
# no third LFXT domain, no metastability CDC to a truly-async crystal). There are
# NO generated (ICG) clocks -- OneWire.vhd has ZERO component instantiations.
# Both clocks are primary input pins driving real leaf flops:
#
#   clk     free-running MCLK at integration (D1/D2). Hosts the ENTIRE protocol
#           engine, ALL on rising_edge(clk):
#             B3 time base (process timebase)  -- the 16-bit OW0DIV reload
#                down-counter -> one-cycle `tick` (counter-compare, NO clock
#                gate, D6);
#             B4 slot / protocol FSM (process fsm) -- the tick-counted slot
#                sequencer: the 12-bit phase_cnt counter, the phase-target mux
#                selected by latched_ods (STD/OD tables up to 960 ticks), the
#                bit_idx/bit_total shift bookkeeping, the LSB-first rx_shift
#                assembly, the registered dq_drive_low pad output (D11), BUSY,
#                the PRES/NOPRES/SHORT decisions (A5 SHORT-wins), and TCIF-set;
#             B2 CDC (process clk_cdc) -- the launch_tgl 2-FF+edge-detect, the
#                three clr_*_tgl W1C 2-FF+edge-detect, and the OW_DQ_IN 2-FF
#                synchronizer dq_s1/dq_s2 -> dq_sync (D8/D10/D12).
#           `clk` MUST free-run so the divider/FSM/flags advance while the bus is
#           idle (the QSPI/I3C/NFC/RTC/PWM `clk` role). Reset via resetn directly
#           (D14: single clock family, no always-on domain -- NO reset synchronizer).
#
#   ClkMem  register-bus clock (gated in the SoC; an input clock at this
#           boundary). Clocks the B1 register file (reg_write / reg_read) on
#           rising ClkMem: CR/TX/DIV stores, the D8 launch descriptor capture
#           (desc_op/bitval/ods/tx + launch_tgl, suppressed on OWEN=0/busy_sync=1),
#           the D12 W1C toggles (clr_tcif_tgl / clr_nopres_tgl / clr_short_tgl),
#           the busy_sync 2-FF (busy_c1/c2, D8), and the synchronous read register
#           rdata_out.
#
#   NO EnMemPeriph CLOCK (the same structural point RTC/PWM make, D4): OneWire
#   NEVER edges on EnMemPeriph. There is NO falling_edge of anything anywhere in
#   OneWire.vhd -- EnMemPeriph is consumed ONLY as an active-low LEVEL qualifier
#   sampled on rising ClkMem (slot decode + write enable + read-mux gate). So
#   EnMemPeriph stays PURE DATA, budgeted vs ClkMem -- it gets no create_clock.
#   OneWire is (like RTC/PWM) a library slave that is neither combinationalRead
#   nor in the CAPTURE_CLOCK shim set.
#
#   NO GENERATED CLOCKS: the OW0DIV divider is a counter-compare producing a
#   1-clk `tick` ENABLE, consumed only as an enable TERM in the FSM D-input logic
#   -- never a ClkGate baud divider (contrast QSPI/I3C's create_generated_clock
#   on cg_clk_baud*), never a ClockMuxGlitchFree divided clock (contrast TIMER).
#   There is nothing to declare.
#
#   OW_DQ_IN IS PURE DATA, *NOT* A CLOCK (the deliberate design consequence of
#   D10, and the whole reason for this block's shape). OW_DQ_IN is 2-FF
#   synchronized in `clk` (dq_s1/dq_s2 -> dq_sync) and sampled at the frozen tick
#   counts; NO flop is clocked off it, and dq_sync never feeds a clock-gate
#   enable. This is the deliberate contrast with I3C, where SDA_IN clocked
#   ibi_req DIRECTLY and therefore had to be declared a real SDC clock in its own
#   async group -- which ALSO exposed the Genus 19.15 single-flop-clock
#   power-engine defect (internal/switching power zeroed for the whole design).
#   OneWire avoids BOTH: no OW_DQ_IN create_clock, no degenerate single-flop
#   clock group, so neither the false-path-vs-DQ bookkeeping nor the power-report
#   workaround is needed. OW_DQ_IN is instead a DATA input budgeted vs `clk` --
#   it is the one raw pad the clk-domain clk_cdc process actually samples
#   (contrast the bus ports, which only the ClkMem domain reads).
#
#   NO lfxt: OneWire is a single MCLK family (D1) -- no 32.768 kHz wall-clock
#   domain (contrast the RTC's real rtc_lfxt). Both clocks are the SAME physical
#   mclk net at integration.
#
#   PERIOD DECISION (20 ns for BOTH clk and ClkMem -- the BENCH-DRIVEN rate;
#   orchestrator honest-SDC precedent, RTC A6 / NFC rf_clk / PWM):
#     The design MCLK is ~40 ns / 24-25 MHz, the NFC/I3C/QSPI/RTC/PWM class value.
#     But the standalone bench (OneWire_tb.vhd) drives clk with PERIOD = 20 ns and
#     ClkMem gated from that SAME net (ClkMem <= clk when en_mem='0' else '0'),
#     so the SDF gate sim is driven at 20 ns. We constrain BOTH clocks AT 20 ns
#     -- the BENCH RATE is what the netlist must actually meet, and 20 ns is the
#     HARDER of the two (2x tighter than the 40 ns real MCLK), so constraining
#     at 20 ns BOUNDS the real-silicon 40 ns MCLK-class case too. Like PWM (and
#     unlike the RTC, whose clk/ClkMem cones were shallow synchronizer +
#     register-file logic), OneWire's `clk` cone is DEEPER -- the 12-bit phase
#     counter, the STD/OD phase-target mux against counts up to 960, and the
#     FSM/shift datapath -- so we honestly target the 20 ns rate the SDF gate sim
#     runs at rather than relying on slack margin. An honest gate closure targets
#     the harder of the two rates the bench and silicon present.
#
# CLOCK GROUPS / CDC (two asynchronous groups -- follows the RTC/PWM house
# pattern, which declared clk vs ClkMem -asynchronous even though they are the
# SAME mclk net at integration):
#   clk and ClkMem are the SAME physical mclk net at integration (D1); there is
#   NO metastability CDC in this block (contrast the RTC's genuine LFXT<->clk
#   crossings, which needed 2-FF synchronizers to a truly-async crystal). Every
#   inter-"domain" hand-off is a REGISTERED level or a single-clock toggle
#   edge-detect, kept standalone-honest (the OneWire.vhd CDC CROSSING INVENTORY):
#     (1) ClkMem -> clk: the D8 launch_tgl toggle 2-FF+edge-detected in clk_cdc
#         co-sampling the quasi-static desc_* descriptor (data-before-flag); the
#         three D12 clr_*_tgl W1C toggles 2-FF+edge-detected, applied SET-WINS in
#         the fsm process that owns each flag; and the quasi-static ow_div /
#         latched CR levels read directly by the clk engine.
#     (2) clk -> ClkMem: the D8 busy 2-FF into ClkMem (busy_sync, the ONE real
#         2-FF here) for launch-suppress; and the D12 sticky levels
#         tcif_flag/pres_flag/nopres_flag/short_flag/rx_shift + the raw `busy`
#         read DIRECTLY by the ClkMem read mux (held/quasi-static levels,
#         coincident nets at integration -- the RTC almf/tickf precedent; the
#         orchestrator RTC-A5-class SR.BUSY raw-read is registered by reg_read
#         itself).
#     (3) pad -> clk: OW_DQ_IN 2-FF synchronized (dq_s1/dq_s2) into dq_sync
#         (D10). Pure data, single-edge, NEVER a clock.
#   These are declared -asynchronous (belt-and-suspenders: the two are the same
#   net at integration, and every hand-off is a toggle or a held/quasi-static
#   level, never an async clear crossing a domain -- the ROOT-2 discipline). The
#   toggle/level structure makes them false-path/quasi-static, so no extra
#   set_false_path beyond the grouping is fabricated (RTC/NFC/I3C/PWM discipline:
#   do NOT invent false paths the grouping already covers).
#   CRITICAL (the RTC lfxt2lfxt / PWM clk2clk non-mistake): the REAL single-cycle
#   paths stay INSIDE their group and ARE timed -- clk<->clk (the whole OW0DIV
#   divider, the 12-bit phase counter, the STD/OD phase-target compare, the FSM /
#   rx_shift / flag engine, and the DQ synchronizer) at 20 ns, ClkMem<->ClkMem
#   (the register file + read mux) at 20 ns.
#   rpt/OneWire.genus.clk2clk.rpt is the MANDATORY negative control proving the
#   protocol engine datapath is TIMED, not cut (an empty report = the
#   divider/FSM/phase-counter core wrongly false-pathed).
#
################################################################################

set INPUT_DIR        ../common/in
set OUTPUT_DIR       out
set REPORT_DIR       rpt
set HDL_DIR          ../../hdl

set TOP_MODULE       OneWire
set BASENAME         OneWire.genus

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
# Procedures (verbatim from the tile flow / QSPI / I3C / NFC / RTC / PWM)
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

# Keep the netlist module named plain "OneWire" (suppress the generic-value suffix).
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
# Read HDL -- OneWire's RTL dependency set (behavioral cell_list order).
# OneWire.vhd has NO component instantiations (no ClkGate/ClkDivPower2) and does
# not reference constants/MemoryMap in its architecture; constants.vhd +
# MemoryMap.vhd are read for work-lib completeness / template fidelity (proven to
# compile in the NFC/I3C/RTC/PWM flows) and are not pulled by elaborate.
################################################################################
puts "Reading HDL (OneWire subset)"
set MP $HDL_DIR/common

# VHDL sources use 2008 delimited comments
set_db hdl_vhdl_read_version 2008
read_hdl -vhdl -library work $MP/constants.vhd
read_hdl -vhdl -library work $MP/MemoryMap.vhd
read_hdl -vhdl -library work $MP/periph/OneWire.vhd

################################################################################
# Elaboration
################################################################################
puts "Elaborating $TOP_MODULE"
elaborate $TOP_MODULE

set DESIGN_NAME [get_db [get_db designs] .name]
puts "Elaborated design name: $DESIGN_NAME"
if {$DESIGN_NAME ne "OneWire"} {
	puts "WARNING: design name is '$DESIGN_NAME', not 'OneWire' -- fix naming"
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
#     generated clocks (no ClkGate baud divider; OW0DIV is a tick ENABLE, D6),
#     NO OW_DQ_IN clock (D10 -- 2-FF synced pure data, never clocks a flop),
#     NO lfxt (single MCLK family, D1). See the header. ---
create_clock -name clk    -period $MCLK_PERIOD [get_ports clk]
create_clock -name ClkMem -period $MCLK_PERIOD [get_ports ClkMem]

# --- CDC: two asynchronous groups (RTC/PWM house pattern -- clk vs ClkMem
#     declared -asynchronous even though they are the SAME mclk net at
#     integration; every hand-off is a toggle or a held/quasi-static level, D8/
#     D12). Real single-cycle paths stay INSIDE a group and are timed. ---
set_clock_groups -asynchronous \
	-group {clk} \
	-group {ClkMem}

# --- Cost/path groups: clk hosts the divider/FSM/phase-counter/flag engine +
#     DQ synchronizer; ClkMem the register file + read mux. ---
define_cost_group -name clk_group    -weight 1
define_cost_group -name clkmem_group -weight 1
path_group -from clk    -group clk_group
path_group -from ClkMem -group clkmem_group

# --- I/O budgets ---------------------------------------------------------------
# Register-bus inputs: software-written registers + the write decode, registered
# by reg_write on the ClkMem edge -> half-period (10 ns). EnMemPeriph carries a
# DATA role ONLY (active-low slot decode / write qualify, D4 -- NEVER a clock),
# budgeted here; it is quasi-static (stable for the whole selected access) so
# 10 ns is generous.
set MEM_IN  [get_db ports {WEn[*] MABPart[*] wdata[*] EnMemPeriph}]
set_input_delay  -clock [get_db clocks ClkMem] $IO_BUDGET_HALF $MEM_IN

# DQ pad input: OW_DQ_IN is PURE DATA (D10), sampled by the clk-domain 2-FF
# synchronizer (clk_cdc: dq_s1 <= OW_DQ_IN). It is NOT a clock (the deliberate
# I3C SDA_IN contrast; see header). Budget vs `clk` -- the one raw pad the clk
# domain reads, unlike the ClkMem-only bus ports above.
set_input_delay  -clock [get_db clocks clk] $IO_BUDGET_HALF [get_db ports {OW_DQ_IN}]

# Register-bus output: rdata_out is a ClkMem flop -> half-period vs ClkMem.
set_output_delay -clock [get_db clocks ClkMem] $IO_BUDGET_HALF [get_db ports {rdata_out[*]}]

# Engine outputs: OW_DQ_DIR = dq_drive_low is a registered clk FSM output (D11);
# OW_DQ_OUT is fixed '0' (open-drain, D11); irq_ow is combinational (status and
# enable) off clk-domain sticky flags + quasi-static CR bits (D13). All three are
# sampled downstream on the FREE-RUNNING mclk (the on-chip interrupt router / the
# AF-spread pad path) -- ClkMem is GATED and stops, so it cannot sample them.
# Budget vs `clk` (the honest sampling clock; the NFC/RTC/PWM irq-vs-clk
# treatment, forced by clk being a real leaf mclk domain).
set_output_delay -clock [get_db clocks clk] $IO_BUDGET_HALF [get_db ports {OW_DQ_OUT OW_DQ_DIR irq_ow}]

# Async reset: applied DIRECTLY to both the clk engine and the ClkMem register
# file (D14 -- single clock family, no reset synchronizer), huge recovery margin
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
#   clk2clk is the CRITICAL one -- the entire protocol engine datapath (the
#   16-bit OW0DIV reload down-counter, the 12-bit phase counter, the STD/OD
#   phase-target comparator, the FSM / rx_shift / PRES/NOPRES/SHORT flag logic,
#   and the DQ synchronizer) MUST be timed at 20 ns. This proves the clk domain
#   is TIMED, not cut.
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
puts "Genus OneWire run is complete. Run time $total_run_time"

exit
