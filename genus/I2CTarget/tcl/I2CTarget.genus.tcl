################################################################################
#
# Genus TCL script -- I2CTarget (I2CT0, hardware-autonomous I2C TARGET/slave)
# standalone synthesis (digital-peripherals program, gate-closure ritual step 3).
#
# Cloned from tcl/OneWire.genus.tcl (same procs, lib-setup idiom, M9b per-module
# boundary_opto discipline, and the two-clock-same-family PERIOD DECISION).
# STANDALONE block run: no power intent / CPF, no SRAM/pmk libs. I2CTarget.vhd
# instantiates NO components (no ClkGate/ClkDivPower2/ClockMuxGlitchFree): the
# whole target FSM, the SDA/SCL 2-FF synchronizers, the sticky W1C flags, and the
# SCL-low watchdog are all counter-compare / edge-reactive logic on rising_edge(clk)
# -- there is NO gated/generated clock anywhere. Expected to synthesize clean first
# try like QSPI/RTC/PWM/OneWire did (i2ct_design.md "Gate closure").
#
# ---------------------------------------------------------------------------
# CLOCK TREE OF THE BLOCK (the HONEST SDC -- see the report-back for rationale)
# ---------------------------------------------------------------------------
# I2CTarget is a TWO-clock block (a single MCLK family, D1 -- like OneWire: no
# third LFXT domain, no metastability CDC to a truly-async crystal). There are NO
# generated (ICG) clocks -- I2CTarget.vhd has ZERO component instantiations. Both
# clocks are primary input pins driving real leaf flops:
#
#   clk     free-running MCLK at integration (D1/D2). Hosts the ENTIRE target
#           engine, ALL on rising_edge(clk):
#             B2 sync/CDC -- the two independent SDA_IN/SCL_IN 2-FF synchronizers
#                (sda_s1/sda_s2 -> sda_sync, scl_s1/scl_s2 -> scl_sync), the
#                one-clk prev registers, the four edge detectors, and START/STOP/
#                repeated-START detection (D6); the tx_load_tgl 2-FF+edge-detect
#                descriptor capture (D10) and the clr_*_tgl W1C 2-FF+edge-detect
#                (D17);
#             B3 target FSM (T_IDLE..T_TX_ACK/T_IGNORE) -- the 3-bit bit counter,
#                the MSB-first shift registers, the address matcher (match+mask+GC,
#                D7), the RX/TX byte engines, the registered SDA_DIR/SCL_DIR pad
#                outputs (D8/D11), BUSY/TM tracking (D12), the sticky W1C flags
#                (AMF/GCF/RXF/OVF/NACKF/STOPF/RSTARTF/ERRF, set-wins), and the
#                SCL-low watchdog counter-compare (D13);
#             the combinational IRQ combiners irq_ae / irq_data (D16).
#           `clk` MUST free-run so the sync/edge/FSM/watchdog advance while the bus
#           is idle (the QSPI/I3C/NFC/RTC/PWM/OneWire `clk` role). Reset via resetn
#           directly (D18: single clock family, no always-on domain -- NO reset
#           synchronizer).
#
#   ClkMem  register-bus clock (gated in the SoC; an input clock at this
#           boundary). Clocks the B1 register file on rising ClkMem: the CR/TX(+
#           tx_load_tgl)/WDG stores, the D17 W1C clr_*_tgl toggles, the D10-cover
#           tx_load_pending, and the registered read mux (rdata_out) over CR, the
#           assembled SR (raw clk flags + BUSY/TM/TXE), TX, RX, WDG, and 0.
#
#   NO EnMemPeriph CLOCK (the same structural point RTC/PWM/OneWire make, D4):
#   I2CTarget NEVER edges on EnMemPeriph. There is NO falling_edge of anything
#   anywhere in I2CTarget.vhd -- EnMemPeriph is consumed ONLY as an active-low
#   LEVEL qualifier sampled on rising ClkMem (slot decode + write enable + read-mux
#   gate). So EnMemPeriph stays PURE DATA, budgeted vs ClkMem -- it gets no
#   create_clock. I2CTarget is (like RTC/PWM/OneWire) a library slave that is
#   neither combinationalRead nor in the CAPTURE_CLOCK shim set (D4: registered
#   read mux, no MCU-side bridge).
#
#   NO GENERATED CLOCKS: the SCL-low watchdog is a plain clk-domain counter-compare
#   (8-bit prescale feeding a 16-bit compare, D13) producing an ERRF level -- never
#   a ClkGate baud divider (contrast QSPI/I3C's create_generated_clock), never a
#   ClockMuxGlitchFree divided clock (contrast TIMER). There is nothing to declare.
#
#   SDA_IN and SCL_IN ARE PURE DATA, *NOT* CLOCKS (the deliberate design
#   consequence of D6, and the whole reason for this block's shape). Both are 2-FF
#   synchronized in `clk` (sda_s1/s2 -> sda_sync, scl_s1/s2 -> scl_sync) and sampled
#   at scl_rise/scl_fall edge events; NO flop is clocked off either, and neither
#   sync output feeds a clock-gate enable. This is the deliberate contrast with
#   I2C.vhd (the semantic precedent), whose slave FSM was clocked by rising_edge/
#   falling_edge(SCL_IN) with START/STOP detectors on RAW SDA_IN edges and ZERO
#   synchronizers -- the X-collapse anti-pattern D4/D6 ban. It is also the I3C
#   SDA_IN contrast: there SDA_IN clocked ibi_req DIRECTLY and had to be declared a
#   real SDC clock in its own async group, which ALSO exposed the Genus 19.15
#   single-flop-clock power-engine defect (internal/switching power zeroed for the
#   whole design). I2CTarget avoids BOTH: no SDA_IN/SCL_IN create_clock, no
#   degenerate single-flop clock group. SDA_IN/SCL_IN are DATA inputs budgeted vs
#   `clk` -- the raw pads the clk-domain sync process actually samples (contrast the
#   bus ports, which only the ClkMem domain reads).
#
#   NO lfxt: I2CTarget is a single MCLK family (D1/D2) -- no 32.768 kHz wall-clock
#   domain (contrast the RTC's real rtc_lfxt). Both clocks are the SAME physical
#   mclk net at integration.
#
#   PERIOD DECISION (40 ns for BOTH clk and ClkMem -- the BENCH-DRIVEN rate;
#   orchestrator honest-SDC precedent, RTC A6 / OneWire / PWM):
#     The design MCLK is ~40 ns / 24-25 MHz, the NFC/I3C/QSPI/RTC/PWM class value.
#     The standalone bench (I2CTarget_tb.vhd) drives clk with PERIOD = 40 ns
#     (`clk <= not clk after PERIOD/2`, ~25 MHz) and ClkMem gated from that SAME net
#     (ClkMem <= clk when en_mem='0' else '0'), so the SDF gate sim is driven at
#     40 ns. We constrain BOTH clocks AT 40 ns -- the BENCH RATE the netlist must
#     actually meet, which also matches the ~41.67 ns (24 MHz) real silicon MCLK
#     (40 ns is the tighter of the two, so it bounds silicon). An honest gate
#     closure targets the rate the SDF gate sim runs at.
#
# CLOCK GROUPS / CDC (two asynchronous groups -- follows the RTC/PWM/OneWire house
# pattern, which declared clk vs ClkMem -asynchronous even though they are the SAME
# mclk net at integration):
#   clk and ClkMem are the SAME physical mclk net at integration (D1/D2); there is
#   NO metastability CDC in this block (contrast the RTC's genuine LFXT<->clk
#   crossings). Every inter-"domain" hand-off is a REGISTERED level or a
#   single-clock toggle edge-detect, kept standalone-honest:
#     (1) ClkMem -> clk: the D10 tx_load_tgl toggle 2-FF+edge-detected in clk
#         co-sampling the quasi-static tx_byte (data-before-flag); the D17 clr_*_tgl
#         W1C toggles 2-FF+edge-detected, applied SET-WINS in the FSM process that
#         owns each flag; and the quasi-static CR/WDG levels read directly by the
#         clk engine.
#     (2) clk -> ClkMem: the D17 sticky flags (AMF/GCF/RXF/OVF/NACKF/STOPF/RSTARTF/
#         ERRF) + BUSY/TM/TXE + rx_data read DIRECTLY (raw) by the ClkMem read mux
#         (held/quasi-static levels, coincident nets at integration -- the OneWire
#         busy-raw-read fix; the ClkMem registration IS the synchronization, D17).
#     (3) pad -> clk: SDA_IN and SCL_IN each 2-FF synchronized (D6). Pure data,
#         single-edge, NEVER a clock.
#   These are declared -asynchronous (belt-and-suspenders: same net at integration,
#   every hand-off a toggle or a held/quasi-static level, never an async clear
#   crossing a domain). The toggle/level structure makes them false-path/
#   quasi-static, so no extra set_false_path beyond the grouping is fabricated
#   (RTC/NFC/I3C/PWM/OneWire discipline: do NOT invent false paths the grouping
#   already covers).
#   CRITICAL (the RTC lfxt2lfxt / PWM clk2clk / OneWire non-mistake): the REAL
#   single-cycle paths stay INSIDE their group and ARE timed -- clk<->clk (the whole
#   sync/edge engine, the FSM/shift/matcher datapath, and the watchdog counter) at
#   40 ns, ClkMem<->ClkMem (the register file + read mux) at 40 ns.
#   rpt/I2CTarget.genus.clk2clk.rpt is the MANDATORY negative control proving the
#   target engine datapath is TIMED, not cut (an empty report = the sync/FSM/
#   watchdog core wrongly false-pathed).
#
################################################################################

set INPUT_DIR        ../common/in
set OUTPUT_DIR       out
set REPORT_DIR       rpt
set HDL_DIR          ../../hdl

set TOP_MODULE       I2CTarget
set BASENAME         I2CTarget.genus

# BOTH clocks at the 40 ns bench-driven rate (25 MHz) -- the SDF gate sim runs
# here, and 40 ns matches/bounds the ~41.67 ns real MCLK (see PERIOD DECISION).
set base_freq        25
set freq_mult        1
set MCLK_FREQ        [expr $base_freq * $freq_mult]
set MCLK_PERIOD      [expr 1 / [expr $MCLK_FREQ * 0.001]]
puts "Target clk/ClkMem frequency: $MCLK_FREQ MHz (period $MCLK_PERIOD ns, the bench rate)"

# I/O budget: half-period default on all registered interfaces.
set IO_BUDGET_HALF   [expr $MCLK_PERIOD / 2.0]  ;# 20 ns

################################################################################
# Procedures (verbatim from the tile flow / QSPI / I3C / NFC / RTC / PWM / OneWire)
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

# Keep the netlist module named plain "I2CTarget" (suppress generic-value suffix).
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
# Read HDL -- I2CTarget's RTL dependency set (behavioral cell_list order).
# I2CTarget.vhd has NO component instantiations (no ClkGate/ClkDivPower2) and does
# not reference constants/MemoryMap in its architecture; constants.vhd +
# MemoryMap.vhd are read for work-lib completeness / template fidelity (proven to
# compile in the NFC/I3C/RTC/PWM/OneWire flows) and are not pulled by elaborate.
################################################################################
puts "Reading HDL (I2CTarget subset)"
set MP $HDL_DIR/common

# VHDL sources use 2008 delimited comments
set_db hdl_vhdl_read_version 2008
read_hdl -vhdl -library work $MP/constants.vhd
read_hdl -vhdl -library work $MP/MemoryMap.vhd
read_hdl -vhdl -library work $MP/periph/I2CTarget.vhd

################################################################################
# Elaboration
################################################################################
puts "Elaborating $TOP_MODULE"
elaborate $TOP_MODULE

set DESIGN_NAME [get_db [get_db designs] .name]
puts "Elaborated design name: $DESIGN_NAME"
if {$DESIGN_NAME ne "I2CTarget"} {
	puts "WARNING: design name is '$DESIGN_NAME', not 'I2CTarget' -- fix naming"
}

# M9b GATE-SIM FIX: per-MODULE boundary_opto disable (root attr ignored).
set_db [get_db modules] .boundary_opto false
puts "boundary_opto disabled on [llength [get_db modules]] modules"

# NO power intent / CPF for this standalone block run.

################################################################################
# Constraints
################################################################################

# --- Primary clocks: clk/ClkMem BOTH at 40 ns (the bench rate). Both are
#     primary input pins. NO EnMemPeriph clock (D4 -- never an edge), NO
#     generated clocks (the watchdog is a plain counter-compare, D13), NO
#     SDA_IN/SCL_IN clock (D6 -- 2-FF synced pure data, never clocks a flop),
#     NO lfxt (single MCLK family, D1/D2). See the header. ---
create_clock -name clk    -period $MCLK_PERIOD [get_ports clk]
create_clock -name ClkMem -period $MCLK_PERIOD [get_ports ClkMem]

# --- CDC: two asynchronous groups (RTC/PWM/OneWire house pattern -- clk vs ClkMem
#     declared -asynchronous even though they are the SAME mclk net at
#     integration; every hand-off is a toggle or a held/quasi-static level, D10/
#     D17). Real single-cycle paths stay INSIDE a group and are timed. ---
set_clock_groups -asynchronous \
	-group {clk} \
	-group {ClkMem}

# --- Cost/path groups: clk hosts the sync/edge/FSM/matcher/watchdog engine;
#     ClkMem the register file + read mux. ---
define_cost_group -name clk_group    -weight 1
define_cost_group -name clkmem_group -weight 1
path_group -from clk    -group clk_group
path_group -from ClkMem -group clkmem_group

# --- I/O budgets ---------------------------------------------------------------
# Register-bus inputs: software-written registers + the write decode, registered
# by the register file on the ClkMem edge -> half-period (20 ns). EnMemPeriph
# carries a DATA role ONLY (active-low slot decode / write qualify, D4 -- NEVER a
# clock), budgeted here; it is quasi-static (stable for the whole selected access)
# so 20 ns is generous.
set MEM_IN  [get_db ports {WEn[*] MABPart[*] wdata[*] EnMemPeriph}]
set_input_delay  -clock [get_db clocks ClkMem] $IO_BUDGET_HALF $MEM_IN

# Pad inputs: SDA_IN and SCL_IN are PURE DATA (D6), sampled by the clk-domain 2-FF
# synchronizers (sda_s1 <= SDA_IN, scl_s1 <= SCL_IN). They are NOT clocks (the
# deliberate I2C.vhd SCL-clocked / I3C SDA_IN contrast; see header). Budget vs
# `clk` -- the raw pads the clk domain reads, unlike the ClkMem-only bus ports.
set_input_delay  -clock [get_db clocks clk] $IO_BUDGET_HALF [get_db ports {SDA_IN SCL_IN}]

# Register-bus output: rdata_out is a ClkMem flop -> half-period vs ClkMem.
set_output_delay -clock [get_db clocks ClkMem] $IO_BUDGET_HALF [get_db ports {rdata_out[*]}]

# Engine outputs: SDA_DIR/SCL_DIR are registered clk FSM outputs (D8/D11); the
# open-drain *_OUT planes are tied '0' at MCU level, not block ports (D19);
# irq_ae/irq_data are combinational (status and enable) off clk-domain sticky flags
# + quasi-static CR enable bits (D16). All are sampled downstream on the
# FREE-RUNNING mclk (the interrupt router / the AF-spread pad path) -- ClkMem is
# GATED and stops, so it cannot sample them. Budget vs `clk` (the honest sampling
# clock; the NFC/RTC/PWM/OneWire irq-vs-clk treatment, forced by clk being a real
# leaf mclk domain).
set_output_delay -clock [get_db clocks clk] $IO_BUDGET_HALF [get_db ports {SDA_DIR SCL_DIR irq_ae irq_data}]

# Async reset: applied DIRECTLY to both the clk engine and the ClkMem register
# file (D18 -- single clock family, no reset synchronizer), huge recovery margin
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
#   clk2clk is the CRITICAL one -- the entire target engine datapath (the two
#   SDA/SCL 2-FF synchronizers + edge detectors, the START/STOP/Sr framing logic,
#   the address matcher, the RX/TX byte engines, the registered SDA_DIR/SCL_DIR
#   outputs, the sticky-flag engine, and the SCL-low watchdog counter-compare)
#   MUST be timed at 40 ns. This proves the clk domain is TIMED, not cut.
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
puts "Genus I2CTarget run is complete. Run time $total_run_time"

exit
