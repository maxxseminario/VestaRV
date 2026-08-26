################################################################################
#
# Genus TCL script -- EVFAB (EVFAB0, the event/trigger fabric / PPI-style
# crossbar) standalone synthesis. Digital-peripherals program, peripheral #12,
# gate-closure ritual (design doc decision D25).
#
# Cloned from tcl/DMA.genus.tcl (same procs, lib-setup idiom, M9b per-module
# boundary_opto discipline, and the 20 ns bench-rate PERIOD DECISION).
# STANDALONE block run: no power intent / CPF, no SRAM/pmk libs. EVFAB.vhd
# instantiates NO components (no ClkGate/ClkDivPower2/ClockMuxGlitchFree): the
# whole fabric is one-hot equality decodes, AND-OR reductions, 2/3-flop input
# chains and sticky flags on rising_edge(clk), plus a register file on
# rising_edge(ClkMem). There is no gated/generated clock anywhere in the RTL.
#
# ---------------------------------------------------------------------------
# CLOCK TREE OF THE BLOCK (the HONEST SDC -- D25 is BINDING here)
# ---------------------------------------------------------------------------
# EVFAB is a TWO-clock block, and -- unlike every other library slave so far --
# the two clocks are declared in ONE TIMED GROUP, *NOT* -asynchronous. Both are
# primary input pins driving real leaf flops:
#
#   clk     FREE-RUNNING MCLK at integration (D1). Hosts the ENTIRE fabric, ALL
#           on rising_edge(clk):
#             B2 event front-end -- the uniform 3-flop chain per ev_in bit
#                (ev_s1/ev_s2/ev_prev) and the elaboration-static T/L/P mode
#                select (D9/D7);
#             B3 GPIO0 front-end -- 8x 2-FF (gp_s1/gp_s2/gp_prev), per-bit
#                rising edge, AND EVGPIOMASK, OR-reduce -> event 15 (D10);
#             B4 crossbar -- the per-channel one-hot EVSEL equality decode, the
#                ch_arm gate (CR.EN and CHEN), the per-task one-hot TASKSEL
#                reduce, the D15 OVR set term, and THE single task_pulse output
#                register (D11-D13, in-fabric latency exactly 1 mclk);
#             B5 ACTION path -- the D3 bus snapshot (bus_wdata_q/bus_slot_q) +
#                the wr_s1/wr_s2/wr_prev rising-edge detector giving EXACTLY ONE
#                action per select window, and its slot decode into
#                chtrig_pulse / ev_inject / clr_fired / clr_ovr / clr_evstat;
#             B6 stickies -- FIRED / OVR / EVSTAT, set-wins (D14/D15).
#           `clk` MUST free-run so chains fire with the bus idle -- the entire
#           point of the block (the bench's frozen-ClkMem G9-2 leg proves it).
#           Reset via resetn directly (D21: one clock family, no always-on
#           second domain -- NO reset synchronizer).
#
#   ClkMem  register-bus clock. Clocks ONLY the B1 register file on rising
#           ClkMem: the CR.EN / CHEN (+CHENSET/CHENCLR w1s/w1c) / EVGPIOMASK /
#           CHnCFG stores, and the registered read mux rdata_out over CR, the SR
#           reductions, CAP, CHEN, FIRED/OVR/EVSTAT, EVGPIOMASK, CHnCFG+ENR, 0.
#
#   NO EnMemPeriph CLOCK (D4 -- the RTC/PWM/OneWire/DMA/I2CTarget structural
#   point). EVFAB NEVER edges on EnMemPeriph; there is NO falling_edge of
#   anything anywhere in EVFAB.vhd. EnMemPeriph is consumed ONLY as an
#   active-low LEVEL -- on rising ClkMem (slot decode + write qualify + read
#   mux) AND on rising clk (the D3 action path's bus_wr_lvl). So it stays PURE
#   DATA and gets no create_clock. EVFAB is neither combinationalRead nor in the
#   CAPTURE_CLOCK shim set (registered read mux, no MCU-side bridge, D4).
#
#   NO GENERATED CLOCKS: there is no baud divider / ClkGate (contrast QSPI/I3C's
#   create_generated_clock) and no ClockMuxGlitchFree (contrast TIMER). Nothing
#   to declare.
#
#   ev_in / gpio0_evin / task_busy ARE PURE DATA, *NOT* CLOCKS. No flop in the
#   block is clocked off any of them and none of them reaches a clock-gate
#   enable in the RTL (ROOT-3: there is no RTL clock gate to reach). The T/L
#   producer taps are 2-FF synchronized (ev_s1/ev_s2) and the GPIO0 pads are
#   2-FF synchronized (gp_s1/gp_s2) before any use.
#
#   PERIOD DECISION (20 ns for BOTH clk and ClkMem -- the BENCH-DRIVEN rate; the
#   DMA precedent, and the house honest-SDC rule "constrain at the rate the SDF
#   gate sim is driven at"):
#     EVFAB_tb.vhd drives `clk <= not clk after PERIOD/2` with PERIOD = 20 ns
#     (50 MHz) and derives ClkMem from that SAME net
#     (ClkMem <= clk when pbus.en_mem = '0' else '0'), so the SDF gate sim runs
#     at 20 ns. 20 ns is also 2x TIGHTER than the ~41.67 ns (24 MHz) real MCLK,
#     so closing here bounds silicon with margin. (Contrast RTC/PWM/OneWire/
#     I2CTarget, whose benches drive 40 ns and which are therefore constrained
#     at 40 ns -- same rule, different bench rate.)
#
# CLOCK GROUPS / CDC -- THE ONE STRUCTURAL DEPARTURE FROM THE SIBLING SDCs
# (D25, and FABLE ADJUDICATION Q4 "CONFIRMED -- one SDC group; same net; no
# defensive syncs"):
#   RTC/PWM/OneWire/DMA/I2CTarget all declare `clk` and `ClkMem`
#   -asynchronous, which is safe THERE because every one of their clk<->ClkMem
#   hand-offs is a toggle + 2-FF + edge-detect or a quasi-static level. EVFAB
#   deliberately has NO such synchronizers: at integration ClkMem IS mclk
#   (MCU.vhd wires `ClkMem => mclk`, the select being the EnMemPeriph strobe),
#   so ClkMem's edges are a SUBSET of clk's at the SAME phase, and the block
#   crosses BARE in both directions:
#     (1) ClkMem -> clk : the quasi-static config (cr_en, chen, cfg_evsel,
#         cfg_tasksel, gpiomask) feeds the clk-domain crossbar COMBINATIONALLY.
#     (2) clk -> ClkMem : the clk-domain flags (fired, ovr, evstat and the SR
#         OR-reductions computed inside the read mux) are sampled BARE by the
#         ClkMem read register.
#   These are REAL single-cycle timed paths, not CDC hand-offs. Declaring them
#   -asynchronous would CUT the only paths that carry the block's configuration
#   into its datapath and its status back out -- a silent, self-inflicted
#   timing hole. So there is deliberately **NO set_clock_groups** in this SDC:
#   clk and ClkMem are timed against each other in both directions, at 20 ns.
#   rpt/EVFAB.genus.clk2clkmem.rpt and rpt/EVFAB.genus.clkmem2clk.rpt are the
#   MANDATORY negative controls -- BOTH must be NON-EMPTY (an empty report =
#   a cross-domain group was wrongly cut, i.e. the sibling SDC was copied
#   blindly). rpt/EVFAB.genus.clk2clk.rpt is the third: the whole crossbar /
#   front-end / action path / sticky engine MUST be timed at 20 ns.
#
#   ASYNCHRONOUS INPUTS (the ONLY thing false-pathed besides resetn, D25):
#   the producer taps whose EV_MODE mask bit marks them T (toggle) or L (level)
#   are, by construction, signals from OTHER clock domains (TIMER compare
#   outputs, the NFC RF domain, the TRNG ring-oscillator drdy) -- that is
#   exactly WHY they are given the 3-flop T/L chain instead of the P-mode
#   pass-through. Same for all 8 gpio0_evin bits (raw pre-mask pad levels,
#   clk_if_comb, D10). Their capture into the FIRST synchronizer flop
#   (ev_s1_reg[e] / gp_s1_reg[g]) is set_false_path -to, declared PER BIT and
#   DERIVED FROM THE MASK LITERALS below (D8/D25) -- never a blanket cut of the
#   whole ev_in bus, because the P-mode bits are same-domain one-mclk pulses
#   (D9 contract) that MUST stay timed: a P bit reaches ev_front COMBINATIONALLY
#   and is in the critical event->task_pulse path.
#     v1 masks: EV_MODE_TGL = 0x00000370 (EV 4,5,6 TIMER0 / EV 8,9 NFC0)
#               EV_MODE_LVL = 0x00002000 (EV 13 TRNG0 drdy)
#   Each false-pathed bit's ONLY fanout is its own first sync flop (for a T/L
#   bit, ev_in(e) is read solely by `ev_s1 <= ev_in`; gpio0_evin only by
#   `gp_s1 <= gpio0_evin`), so `-to <first sync flop>` and `-from <port bit>`
#   are structurally equivalent here -- the -to form is used, per D25, with a
#   -from port fallback if the elaborated register name is not found.
#
################################################################################

set INPUT_DIR        ../common/in
set OUTPUT_DIR       out
set REPORT_DIR       rpt
set HDL_DIR          ../../hdl

set TOP_MODULE       EVFAB
set BASENAME         EVFAB.genus

# BOTH clocks at the 20 ns bench-driven rate (50 MHz) -- the rate the SDF gate
# sim runs at, and 2x tighter than the ~41.67 ns real MCLK (see PERIOD DECISION).
set base_freq        50
set freq_mult        1
set MCLK_FREQ        [expr $base_freq * $freq_mult]
set MCLK_PERIOD      [expr 1 / [expr $MCLK_FREQ * 0.001]]
puts "Target clk/ClkMem frequency: $MCLK_FREQ MHz (period $MCLK_PERIOD ns, the bench rate)"

# I/O budget: half-period default on all registered interfaces.
set IO_BUDGET_HALF   [expr $MCLK_PERIOD / 2.0]  ;# 10 ns

# --- The EV_MODE mask literals (D7 v1 values, byte-identical to the EVFAB.vhd
#     generic defaults AND to the EVFAB_tb.vhd generic map). The async-input
#     false-path list below is DERIVED from these, so changing a mask here (and
#     in the RTL/bench) automatically re-cuts the constraint set. ---
set EV_MODE_TGL_HEX  0x00000370
set EV_MODE_LVL_HEX  0x00002000
set N_EV             16

################################################################################
# Procedures (verbatim from the tile flow / QSPI / I3C / NFC / RTC / PWM /
# OneWire / DMA / I2CTarget, plus two EVFAB-specific object lookups)
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

# Exact-name lookup over a db collection. Deliberately NOT a get_db glob: bus-bit
# brackets are pattern metacharacters in some matchers, and a SILENTLY EMPTY
# constraint object is exactly the class of mistake this SDC is guarding against.
proc evfab_by_name {objs want} {
	set out {}
	foreach o $objs {
		if {[get_db $o .name] eq $want} { lappend out $o }
	}
	return $out
}

# Bits set in a 32-bit hex mask, as a list of indices < $limit.
proc evfab_mask_bits {hexval limit} {
	set out {}
	for {set b 0} {$b < $limit} {incr b} {
		if {[expr ($hexval >> $b) & 1]} { lappend out $b }
	}
	return $out
}

################################################################################
# Root Attributes
################################################################################
tic
set_db information_level 3

# Keep the netlist module named plain "EVFAB" (suppress the generic-value
# suffix) -- the gate-sim binding contract is a module named EVFAB.
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
# Read HDL -- EVFAB's RTL dependency set (behavioral cell_list order). EVFAB.vhd
# has NO component instantiations and does not reference constants/MemoryMap in
# its architecture; constants.vhd + MemoryMap.vhd are read for work-lib
# completeness / template fidelity (proven to compile in the NFC/I3C/RTC/PWM/
# OneWire/DMA/I2CTarget flows) and are not pulled by elaborate.
################################################################################
puts "Reading HDL (EVFAB subset)"
set MP $HDL_DIR/common

# VHDL sources use 2008 delimited comments
set_db hdl_vhdl_read_version 2008
read_hdl -vhdl -library work $MP/constants.vhd
read_hdl -vhdl -library work $MP/MemoryMap.vhd
read_hdl -vhdl -library work $MP/periph/EVFAB.vhd

################################################################################
# Elaboration -- generics left at their v1 DEFAULTS (D6), which are exactly the
# EVFAB_tb.vhd generic map: N_CH=8, N_EV=16, N_TASK=10, EV_GPIO_IDX=15,
# EV_MODE_TGL=0x370, EV_MODE_LVL=0x2000, VER=1.
################################################################################
puts "Elaborating $TOP_MODULE"
elaborate $TOP_MODULE

set DESIGN_NAME [get_db [get_db designs] .name]
puts "Elaborated design name: $DESIGN_NAME"
if {$DESIGN_NAME ne "EVFAB"} {
	puts "FATAL: design module name is '$DESIGN_NAME', not 'EVFAB' -- the gate-sim binding contract (VHDL `component EVFAB` default-bound to the netlist module) would break"
	exit 1
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
#     generated clocks (no divider/ClkGate anywhere), NO ev_in/gpio0_evin/
#     task_busy clock (pure data, D8/D10), NO lfxt (single MCLK family, D1).
#     See the header. ---
create_clock -name clk    -period $MCLK_PERIOD [get_ports clk]
create_clock -name ClkMem -period $MCLK_PERIOD [get_ports ClkMem]

# --- CDC: *** DELIBERATELY NO set_clock_groups *** (D25 / FABLE Q4). clk and
#     ClkMem are the SAME mclk net at integration and EVFAB crosses between them
#     BARE in BOTH directions -- quasi-static config ClkMem->clk into the
#     crossbar, and clk-domain flags clk->ClkMem into the read mux. Those are
#     REAL timed paths, not CDC hand-offs; -asynchronous here would cut the only
#     paths carrying the block's configuration in and its status out. Every
#     other library slave (RTC/PWM/OneWire/DMA/I2CTarget) groups them
#     -asynchronous because ALL of their hand-offs are toggle+2FF+edge-detect;
#     EVFAB deliberately has no such synchronizers. Negative controls below. ---

# --- Cost/path groups: clk hosts the front-ends, crossbar, action path,
#     stickies and the output register; ClkMem the register file + read mux. ---
define_cost_group -name clk_group    -weight 1
define_cost_group -name clkmem_group -weight 1
path_group -from clk    -group clk_group
path_group -from ClkMem -group clkmem_group

# --- I/O budgets ---------------------------------------------------------------
# Register-bus inputs. TWO budgets, because -- uniquely among the library slaves
# -- BOTH domains read these raw ports (the I3C dat_proc situation, and the exact
# thing the RTC/I2CTarget headers noted they did NOT have):
#   * ClkMem: the B1 register file (slot decode, write qualify, read mux).
#   * clk   : the B5 ACTION path (bus_wr_lvl = EnMemPeriph and WEn(0); the
#             bus_wdata_q/bus_slot_q payload snapshot off wdata/MABPart, D3).
# Both at half-period (10 ns); the bus is quasi-static for the whole selected
# access, so this is generous.
set MEM_IN  [get_db ports {WEn[*] MABPart[*] wdata[*] EnMemPeriph}]
set_input_delay  -clock [get_db clocks ClkMem] $IO_BUDGET_HALF $MEM_IN
set_input_delay  -clock [get_db clocks clk]    $IO_BUDGET_HALF -add_delay $MEM_IN

# Producer taps and consumer busy levels: PURE DATA sampled in the `clk` domain.
#   ev_in      -- P-mode bits reach ev_front COMBINATIONALLY (D9, latency 1) and
#                 are contract-bound to be one-mclk pulses IN THE clk DOMAIN, so
#                 they are genuinely timed; T/L bits land in ev_s1 and are
#                 false-pathed per bit below.
#   gpio0_evin -- raw pad levels into gp_s1 (all 8 false-pathed below).
#   task_busy  -- a clk-domain level, sampled bare into the D15 OVR set term.
set_input_delay  -clock [get_db clocks clk] $IO_BUDGET_HALF \
	[get_db ports {ev_in[*] gpio0_evin[*] task_busy[*]}]

# Register-bus output: rdata_out is a ClkMem flop -> half-period vs ClkMem.
set_output_delay -clock [get_db clocks ClkMem] $IO_BUDGET_HALF [get_db ports {rdata_out[*]}]

# Fabric outputs: task_pulse is THE single registered clk output (D12), sampled
# by consumer peripherals on the FREE-RUNNING mclk. irq_evfab is a hard constant
# '0' in v1 (D20) but is still budgeted vs `clk` for form (the router samples it
# on mclk; ClkMem is the gated bus clock and cannot sample either). This is the
# NFC/RTC/PWM/OneWire/DMA/I2CTarget irq-vs-clk treatment.
set_output_delay -clock [get_db clocks clk] $IO_BUDGET_HALF \
	[get_db ports {task_pulse[*] irq_evfab}]

# --- Asynchronous producer inputs: false-path INTO the first synchronizer flop,
#     PER BIT, derived from the EV_MODE mask literals (D8/D25). NOT a blanket
#     ev_in cut -- the P-mode bits stay timed (see header). ---
set ASYNC_CAPTURE {}
foreach e [evfab_mask_bits $EV_MODE_TGL_HEX $N_EV] {
	lappend ASYNC_CAPTURE [list "ev_in\[$e\]" "ev_s1_reg\[$e\]" "T (EV_MODE_TGL)"]
}
foreach e [evfab_mask_bits $EV_MODE_LVL_HEX $N_EV] {
	lappend ASYNC_CAPTURE [list "ev_in\[$e\]" "ev_s1_reg\[$e\]" "L (EV_MODE_LVL)"]
}
for {set g 0} {$g < 8} {incr g} {
	lappend ASYNC_CAPTURE [list "gpio0_evin\[$g\]" "gp_s1_reg\[$g\]" "GPIO0 pad (D10)"]
}

set ALL_PORTS [get_db ports]
set ALL_INSTS [get_db insts]
set n_to 0
set n_from 0
foreach entry $ASYNC_CAPTURE {
	set pname [lindex $entry 0]
	set rname [lindex $entry 1]
	set why   [lindex $entry 2]
	set reg   [evfab_by_name $ALL_INSTS $rname]
	if {[llength $reg] == 1} {
		set_false_path -to $reg
		puts "  async-input false path: -to $rname   \[$pname, $why\]"
		incr n_to
	} else {
		set prt [evfab_by_name $ALL_PORTS $pname]
		if {[llength $prt] != 1} {
			puts "FATAL: neither register '$rname' nor port '$pname' resolved -- the async-input constraint set is incomplete"
			exit 1
		}
		set_false_path -from $prt
		puts "  async-input false path: -from $pname  (FALLBACK: '$rname' not found)   \[$why\]"
		incr n_from
	}
}
puts "EVFAB async-input false paths: [llength $ASYNC_CAPTURE] declared ($n_to via -to sync flop, $n_from via -from port fallback)"
if {[llength $ASYNC_CAPTURE] != 14} {
	puts "FATAL: expected 14 async-input false paths (5 T + 1 L + 8 GPIO0), got [llength $ASYNC_CAPTURE]"
	exit 1
}

# Async reset: applied DIRECTLY to both the clk fabric and the ClkMem register
# file (D21 -- single clock family, no reset synchronizer), huge recovery margin
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

# Honesty negative controls (an EMPTY report = a domain or a crossing was
# wrongly cut). EVFAB needs THREE, because its whole SDC departure is the
# refusal to declare clk/ClkMem asynchronous:
#   clk2clk     -- the crossbar / front-ends / action path / stickies / output
#                  register MUST be timed at 20 ns.
#   clk2clkmem  -- the clk-domain flags (fired/ovr/evstat + the SR reductions)
#                  reaching the ClkMem read register MUST be timed.
#   clkmem2clk  -- the quasi-static config (cr_en/chen/cfg_evsel/cfg_tasksel/
#                  gpiomask) reaching the clk-domain crossbar MUST be timed.
# The last two are EXACTLY the paths a copied `set_clock_groups -asynchronous`
# would have silently deleted.
report_timing -from [get_db clocks clk] -to [get_db clocks clk] -max_paths 15 \
	> $REPORT_DIR/$BASENAME.clk2clk.rpt
report_timing -from [get_db clocks clk] -to [get_db clocks ClkMem] -max_paths 10 \
	> $REPORT_DIR/$BASENAME.clk2clkmem.rpt
report_timing -from [get_db clocks ClkMem] -to [get_db clocks clk] -max_paths 10 \
	> $REPORT_DIR/$BASENAME.clkmem2clk.rpt
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
puts "Genus EVFAB run is complete. Run time $total_run_time"

exit
