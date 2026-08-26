################################################################################
#
# Genus TCL script -- NFC standalone peripheral synthesis
# (digital-peripherals program, Stage (a)+(b) gate-closure).
#
# Cloned from tcl/I3C.genus.tcl (same procs, lib-setup idiom, M9b per-module
# boundary_opto discipline). STANDALONE block run: no power intent / CPF, no
# SRAM/pmk libs. NFC is the HARDEST of the three peripherals: a GENUINE
# three-clock-domain design (D3/D18) and NOT the QSPI/I3C two-ClkGate baud
# scheme -- there are NO ICG-generated clocks here at all (verified: NFC.vhd has
# ZERO component instantiations; the protocol core counts rf_clk directly, D18).
#
# ---------------------------------------------------------------------------
# CLOCK TREE OF THE BLOCK (the HONEST SDC -- see the report-back for rationale)
# ---------------------------------------------------------------------------
# NFC is a genuine FOUR-clock block. There are no generated (ICG) clocks; every
# clock is a primary input pin driving real leaf flops:
#
#   clk         smclk-domain FREE-RUNNING reference, 25 MHz / 40 ns. UNLIKE
#               QSPI's source-only clk, here `clk` is a REAL leaf clock: it hosts
#               the ENTIRE B-CDC block (process `bcdc`, NFC.vhd L380) -- the
#               field_detect 2-FF synchronizer + FIELD_LIVE/FIELDF edge-detect,
#               the four rf-domain event-level 2-FF synchronizers
#               (rxframe/txdone/crcerr/parerr -> sticky W1C flags), and the
#               BUSY/HALTED/STATE readback synchronizers. ClkMem is GATED and
#               cannot host synchronizers, so `clk` (smclk) does -- exactly the
#               role QSPI/I3C give their free-running clk (D18).
#
#   ClkMem      register-bus clock (gated in the SoC; an input clock at this
#               boundary), 25 MHz / 40 ns. Clocks the B1 register file
#               (reg_write NFC.vhd L277, reg_read L352): all 10 slots, the W1C
#               clr-pulse set, the payload-window CPU write port, and the
#               synchronous read register rdata_out.
#
#   EnMemPeriph active-low peripheral select, 25 MHz / 40 ns class. Same dual
#               role as QSPI/I3C: (1) REAL negedge CLOCK of the reg_sync read
#               pre-latch (NFC.vhd L256: NFCxSR_ltch/rxst_ltch/data_ltch/dbg_ltch
#               captured INVERTED on falling_edge(EnMemPeriph)); (2) DATA -- slot
#               decode / write qualify -- consumed by the ClkMem-domain reg_write/
#               reg_read. Declared a real clock so those negedge flops are
#               constrained; its data role is budgeted against ClkMem. (No
#               dat_proc-on-clk second capture like I3C: no clk- or rf_clk-domain
#               process reads the raw bus ports, so the bus inputs need only the
#               ClkMem budget.)
#
#   rf_clk      **THE GENUINE THIRD PROTOCOL DOMAIN (D3)** -- the AFE
#               carrier-derived clock, UNRELATED to smclk. Clocks the whole
#               protocol core: rfsync (config/field/HALTCLR into rf, L431),
#               rx_decode (Miller decoder + ETU grid + bit assembler, L458),
#               tx_encode (Manchester/subcarrier encoder, L564), and bfsm (the
#               ISO 14443-3 tag FSM: ACT_PARSE parity loop, ACT_CRC LFSR,
#               ACT_DECIDE, ACT_FDT down-counter, ACT_COMPOSE, ACT_TX, L636).
#               This is where the ETU/Miller/parse/compose hotspot logic lives;
#               it MUST be timed (see the rf2rf negative control).
#
#   RF_CLK PERIOD DECISION (the load-bearing constraint -- 50 ns, NOT 73.75 ns):
#   The nominal AFE carrier is fc = 13.56 MHz => 73.75 ns. We constrain rf_clk at
#   **50 ns (20 MHz)** instead, on purpose:
#     - The standalone bench's reader model generates rf_clk with RF_HALF = 25 ns
#       => a 50 ns period (a COMPRESSED carrier, so a full REQA->...->READ
#       transaction fits the 1-minute sim rule). The SDF gate sim will be driven
#       at exactly this 50 ns, so 50 ns is what the netlist must actually meet.
#     - 50 ns is FASTER (more conservative) than the real 73.75 ns carrier, so
#       constraining at 50 ns bounds the real-silicon 13.56 MHz case too.
#     - Constraining at the real 73.75 ns would UNDER-constrain relative to what
#       the bench drives -- an honest gate closure targets the harder of the two.
#   All protocol times (ETU, SUBCDIV, FDT) are register-programmed divisors of
#   rf_clk (D3/D16), so the compression is a bench constant, not an RTL change.
#
# CLOCK GROUPS / CDC (four asynchronous groups -- verified crossing by crossing):
#   Every inter-domain path in NFC crosses through a DESIGNED synchronizer or a
#   protocol-disjoint held handshake (D18), so the four domains are declared
#   -asynchronous. The crossings, each checked in the RTL:
#     (1) clk <-> rf_clk: rfsync 2-FF's nfcen/listen/field/halt_tgl INTO rf_clk;
#         bcdc 2-FF's the rf event/status levels INTO clk. Genuine 2-FF CDC.
#     (2) ClkMem <-> rf_clk: payload_mem written by ClkMem, read by rf in a
#         protocol-disjoint window (poll BUSY/STATE, D19); rxbuf_mem written by
#         rf, read by ClkMem AFTER RXFRAMEF crosses (data-before-flag handshake);
#         rx_cmd/len/parok/crcok/frame_count exported to the EnMemPeriph pre-latch
#         held after RXFRAMEF; t_uid/atqa/sak/fdt latched transaction-locally in
#         rf at rx_soc (latch-at-launch). All async by construction.
#     (3) clk <-> ClkMem: the sticky W1C flags (clk domain) feed the SR read mux
#         (ClkMem) + pre-latch; clr_* pulses set by ClkMem retire the flags in clk
#         via level-sensitive async clears. Held-level, no single-cycle relation.
#     (4) EnMemPeriph pre-latch captures clk-domain flags + rf-domain exports on
#         its negedge -- async sampled levels.
#   CRITICAL (the M9c non-mistake): the REAL single-cycle paths stay INSIDE their
#   group and ARE timed -- rf_clk<->rf_clk (the entire protocol core, incl. the
#   parse/compose combinational hotspot) at 50 ns, ClkMem<->ClkMem and
#   clk<->clk at 40 ns. rpt/NFC.genus.rf2rf.rpt is the mandatory negative control
#   proving the rf domain is TIMED, not cut (an empty report = the whole protocol
#   core wrongly false-pathed).
#
################################################################################

set INPUT_DIR        ../common/in
set OUTPUT_DIR       out
set REPORT_DIR       rpt
set HDL_DIR          ../../hdl

set TOP_MODULE       NFC
set BASENAME         NFC.genus

# 25 MHz smclk class for clk/ClkMem/EnMemPeriph, same as the proven flows.
set base_freq        25
set freq_mult        1
set MCLK_FREQ        [expr $base_freq * $freq_mult]
set MCLK_PERIOD      [expr 1 / [expr $MCLK_FREQ * 0.001]]
puts "Target clk/ClkMem frequency: $MCLK_FREQ MHz (period $MCLK_PERIOD ns)"

# I/O budget: half-period default on all registered interfaces.
set IO_BUDGET_HALF   [expr $MCLK_PERIOD / 2.0]  ;# 20 ns

# rf_clk: the AFE carrier-derived protocol domain, constrained at 50 ns / 20 MHz
# (the compressed-carrier bench rate; conservative vs the real 73.75 ns carrier
# AND matching what the SDF gate sim is driven at -- see the header rationale).
set RF_PERIOD        50.0
set RF_BUDGET_HALF   [expr $RF_PERIOD / 2.0]    ;# 25 ns
puts "Target rf_clk frequency: 20 MHz (period $RF_PERIOD ns, compressed carrier)"

################################################################################
# Procedures (verbatim from the tile flow / QSPI / I3C)
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

# Keep the netlist module named plain "NFC" (suppress the generic-value suffix).
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
# Read HDL -- NFC's RTL dependency set (cell_list_behavioral.txt order, with the
# SYNTHESIZABLE ClkGate wrapper substituted for the sim ClkGate). NOTE: NFC.vhd
# instantiates NEITHER ClkGate NOR ClkDivPower2 (it has no components at all --
# pure behavioral, rf_clk counted directly); the two commune files are read only
# for template fidelity / work-lib completeness and are not pulled by elaborate.
################################################################################
puts "Reading HDL (NFC subset)"
set MP $HDL_DIR/common

# VHDL sources use 2008 delimited comments
set_db hdl_vhdl_read_version 2008
read_hdl -vhdl -library work $MP/constants.vhd
read_hdl -vhdl -library work $MP/MemoryMap.vhd
read_hdl -vhdl -library work $MP/commune/ClkGate_cmn65gp_ARM.vhd
read_hdl -vhdl -library work $MP/commune/ClkDivPower2.vhd
read_hdl -vhdl -library work $MP/periph/NFC.vhd

################################################################################
# Elaboration
################################################################################
puts "Elaborating $TOP_MODULE"
elaborate $TOP_MODULE

set DESIGN_NAME [get_db [get_db designs] .name]
puts "Elaborated design name: $DESIGN_NAME"
if {$DESIGN_NAME ne "NFC"} {
	puts "WARNING: design name is '$DESIGN_NAME', not 'NFC' -- fix naming"
}

# M9b GATE-SIM FIX: per-MODULE boundary_opto disable (root attr ignored).
set_db [get_db modules] .boundary_opto false
puts "boundary_opto disabled on [llength [get_db modules]] modules"

# NO power intent / CPF for this standalone block run.

################################################################################
# Constraints
################################################################################

# --- Primary clocks: clk/ClkMem/EnMemPeriph at 40 ns; rf_clk at 50 ns. All four
#     are primary input pins (no generated clocks in this block). ---
create_clock -name clk         -period $MCLK_PERIOD [get_ports clk]
create_clock -name ClkMem      -period $MCLK_PERIOD [get_ports ClkMem]
# EnMemPeriph is the negedge clock of the reg_sync read pre-latch flops.
create_clock -name EnMemPeriph -period $MCLK_PERIOD [get_ports EnMemPeriph]
# rf_clk is the genuine AFE carrier-derived protocol clock (50 ns; see header).
create_clock -name rf_clk      -period $RF_PERIOD   [get_ports rf_clk]

# --- CDC: four asynchronous groups (see header -- each crossing verified in the
#     RTL to go through a 2-FF synchronizer or a protocol-disjoint held
#     handshake). Real single-cycle paths stay INSIDE a group and are timed. ---
set_clock_groups -asynchronous \
	-group {clk} \
	-group {ClkMem} \
	-group {EnMemPeriph} \
	-group {rf_clk}

# --- Cost/path groups: rf_clk is the hotspot (parse/compose combinational
#     cones); clkmem for the register file. ---
define_cost_group -name rf_group     -weight 1
define_cost_group -name clkmem_group -weight 1
path_group -from rf_clk -group rf_group
path_group -from ClkMem -group clkmem_group

# --- I/O budgets ---------------------------------------------------------------
# Register-bus inputs: software-written registers + the write decode, registered
# by reg_write on the ClkMem edge -> half-period (20 ns). EnMemPeriph carries a
# data role (slot decode / write qualify) budgeted here; it is quasi-static
# (stable for the whole selected access) so 20 ns is generous. (No second `clk`
# budget needed -- unlike I3C's dat_proc, no clk/rf process reads the raw bus.)
set MEM_IN  [get_db ports {WEn[*] MABPart[*] wdata[*] EnMemPeriph}]
set_input_delay  -clock [get_db clocks ClkMem] $IO_BUDGET_HALF $MEM_IN

# Register-bus output: rdata_out is a ClkMem flop -> half-period vs ClkMem.
set_output_delay -clock [get_db clocks ClkMem] $IO_BUDGET_HALF [get_db ports {rdata_out[*]}]

# IRQ outputs: irq_* = (sticky flag AND enable), combinational. The flags live in
# the `clk` (smclk) domain (bcdc) and the enables in ClkMem (NFCxCR). The on-chip
# interrupt router samples these on the FREE-RUNNING smclk -- ClkMem is GATED and
# stops, so it cannot sample them. Budget vs `clk` (the honest sampling clock;
# this is the one deliberate deviation from QSPI's irq-vs-ClkMem, forced by NFC's
# clk being a real leaf smclk domain rather than source-only).
set_output_delay -clock [get_db clocks clk] $IO_BUDGET_HALF \
	[get_db ports {irq_field irq_rxf irq_txdone irq_crcerr}]

# afe_en = NFCxCR.NFCEN and NFCxCR.LISTEN -- a ClkMem-domain combinational output
# (quasi-static arm level). Budget vs ClkMem.
set_output_delay -clock [get_db clocks ClkMem] $IO_BUDGET_HALF [get_db ports {afe_en}]

# rf_clk (protocol) side:
#   Inputs -- rf_rx is the demodulated pause envelope sampled by rx_decode
#   (rx_s1 <= rf_rx) on rf_clk. Point-to-point tb/AFE-driven input -> half rf
#   period (25 ns). field_detect is sampled by the `clk`-domain bcdc synchronizer
#   (field_s1 <= field_detect on clk), NOT rf_clk -- so it is budgeted vs `clk`.
set_input_delay  -clock [get_db clocks rf_clk] $RF_BUDGET_HALF [get_db ports {rf_rx}]
set_input_delay  -clock [get_db clocks clk]    $IO_BUDGET_HALF [get_db ports {field_detect}]

#   Outputs -- rf_txmod/rf_tx_en are driven combinationally off rf_clk-domain
#   state (subc_lvl/tx_modnow, txph). Half rf period (25 ns) each. The AFE load
#   switch is slow (fc/16 subcarrier), so these carry large real margin.
set_output_delay -clock [get_db clocks rf_clk] $RF_BUDGET_HALF \
	[get_db ports {rf_txmod rf_tx_en}]

# Async reset: POR-synchronized deassertion, huge recovery margin (same treatment
# the proven flows give resetn).
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
#   rf2rf is the CRITICAL one -- the entire protocol core, incl. the ACT_PARSE
#   parity loop and the ACT_COMPOSE ~162-bit + CRC single-cycle combinational
#   cone, MUST be timed at 50 ns. This is the hotspot judged in the report-back.
report_timing -from [get_db clocks rf_clk] -to [get_db clocks rf_clk] -max_paths 15 \
	> $REPORT_DIR/$BASENAME.rf2rf.rpt
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
puts "Genus NFC run is complete. Run time $total_run_time"

exit
