################################################################################
#
# Genus TCL script -- DMA (configurable multi-channel single-shot DMA with
# peripheral pacing + CRC16-CDMA2000 ride-along) standalone synthesis
# (digital-peripherals program, gate-closure ritual step 2 -- peripheral #7).
#
# Cloned from tcl/OneWire.genus.tcl (same procs, lib-setup idiom, M9b per-module
# boundary_opto discipline, and the two-clock-same-family PERIOD DECISION).
# STANDALONE block run: no power intent / CPF, no SRAM/pmk libs.
#
# TWO SHAPES from ONE tcl (D6 / A6 dual-shape precedent, the arb_lat N=4/N=18
# idiom): the entity generic NCH in {2,4} is overridden by the env var DMA_NCH
# (default 4). The Makefile targets DMA_nch4.genus / DMA_nch2.genus set it; the
# netlist module name stays plain "DMA" (hdl_parameter_naming_style ""), so each
# shape's netlist (out/DMA_nch4.genus.v / out/DMA_nch2.genus.v) is a self-
# contained module named DMA -- distinguished by FILE, bound one-at-a-time in the
# two mixed-binding gate runs (xcelium/DMA/genus/). AW stays the default 15
# (SH_AW; the Castalia shared-window word address width, D19).
#
# DMA.vhd instantiates ONE component: work.CRC16 (the SYSTEM0-proven CRC16-
# CDMA2000 cell, poly 0xC857, D14) -- four chained combinational instances fed
# b0->b3. NO ClkGate/ClkDivPower2/ClockMuxGlitchFree: the engine is a plain FSM +
# SRC/DST/LEN counters + a small RR/PRIO picker on `clk`; there is NO baud
# divider, NO generated clock, NO clock gate (contrast QSPI/I3C). Expected to
# synthesize clean like QSPI/RTC/PWM/OneWire did (dma_design.md "Gate closure").
#
# ---------------------------------------------------------------------------
# CLOCK TREE OF THE BLOCK (the HONEST SDC -- see the report-back for rationale)
# ---------------------------------------------------------------------------
# DMA is a TWO-clock block (a single MCLK family, D1 -- SIMPLER than the RTC: no
# third LFXT domain, no metastability CDC to a truly-async crystal; the ONLY true
# CDC is the three pacing trigger inputs, which are DATA, see below). There are
# NO generated (ICG) clocks. Both clocks are primary input pins driving real leaf
# flops:
#
#   clk     free-running MCLK at integration (D1/D2). Hosts the ENTIRE transfer
#           engine, ALL on rising_edge(clk):
#             B4 master-port FSM (process engine) -- the verbatim WAIT-FOR-RELEASE
#                handshake (M_IDLE/M_RD_REQ/M_RD_CAP/M_RD_GAP/M_WR_REQ/M_WR_CAP/
#                M_WR_GAP/M_CLR, acked-flop m_req drop, >=1 observed-low gap), the
#                round-robin + 2-level strict-PRIO channel picker, the 17-bit
#                SRC/DST byte working counters (+4 SINC/DINC), the 32-bit LEN
#                remaining down-counter, the deny-guard comparators (mutex window
#                0x6000-0x60FF / router CLAIM 0x7800, D12/A5), the reject-at-GO
#                error setter (LEN0/misalign/out-of-window/TCM-hole, D13/A18), and
#                the per-source M_CLR SR-W1C address derivation (R3);
#             B5 CRC datapath -- four chained work.CRC16 combinational cells fed
#                b0->b3, crc_acc registered on the M_RD_REQ->M_RD_CAP (done) edge
#                for CRCEN channels (D14);
#             B2/B3 CDC (process clk_cdc) -- the go_tgl/abort_tgl/clr_done_tgl/
#                clr_err_tgl/crc_wr_tgl 2-FF+edge-detect toggles AND the three
#                pacing trigger 2-FF synchronizers (tu/tq/tn -> rising-edge
#                events, D9);
#             B6 status/IRQ -- the sticky CHnDONE/CHnERR (SET-wins-over-CLEAR),
#                BUSY/ACTIVECH, the combinational irq_done/irq_err (D16/D17).
#           `clk` MUST free-run so the engine/counters/flags advance while the bus
#           is idle -- the transfer engine is a fifth mp_arbiter master and moves
#           words autonomously (the QSPI/I3C/NFC/RTC/PWM/OW `clk` role). Reset via
#           resetn directly (D1: single clock family, no always-on domain -- NO
#           reset synchronizer).
#
#   ClkMem  register-bus clock (gated in the SoC; an input clock at this
#           boundary). Clocks the B1 register file (reg_write / reg_read) on
#           rising ClkMem: DMA0CR/DMA0SR, per-channel SRC/DST/LEN/CFG stores, the
#           DMA0CRC seed store, the D8 go_tgl/abort_tgl launch/abort toggles
#           (launch suppressed on DMAEN=0 / busy_sync), the D16 W1C clr_*_tgl
#           toggles, the crc_wr_tgl seed-commit toggle, the busy_sync 2-FF (B8,
#           the launch-suppress qualifier), and the synchronous read register
#           rdata_out.
#
#   NO EnMemPeriph CLOCK (the same structural point RTC/PWM/OW make, D4): DMA
#   NEVER edges on EnMemPeriph. There is NO falling_edge of anything anywhere in
#   DMA.vhd -- EnMemPeriph is consumed ONLY as an active-low LEVEL qualifier
#   sampled on rising ClkMem (slot decode + write enable + read-mux gate). So
#   EnMemPeriph stays PURE DATA, budgeted vs ClkMem -- it gets no create_clock.
#   DMA is (like RTC/PWM/OW) a library slave that is neither combinationalRead nor
#   in the CAPTURE_CLOCK shim set.
#
#   THE THREE TRIGGER INPUTS ARE PURE DATA, *NOT* CLOCKS (D9 + the deliberate OW
#   OW_DQ_IN / I3C SDA_IN contrast). trig_uart0_rc / trig_qspi0_rxf / trig_nfc0_rxf
#   are the IE-gated data-ready LEVELS of UART0/QSPI0/NFC0 (A8); each is 2-FF
#   synchronized in `clk` (tu1/tu2, tq1/tq2, tn1/tn2) and rising-edge detected to
#   a one-clk pacing event. NO flop is clocked off a trigger, and no synced
#   trigger feeds a clock-gate enable (ROOT-3 discipline). So NONE of the three
#   gets a create_clock (no degenerate single-flop clock group, no Genus 19.15
#   single-flop-clock power-engine corner -- the I3C SDA_IN lesson). They are
#   instead DATA inputs budgeted vs `clk` (the clk-domain clk_cdc process samples
#   them), exactly like OW_DQ_IN.
#
#   NO GENERATED CLOCKS: the engine is a plain FSM + counters. There is no divider
#   at all (contrast the OW0DIV / PWM prescaler tick ENABLE, and the QSPI/I3C
#   create_generated_clock baud dividers). Nothing to declare.
#
#   NO lfxt: DMA is a single MCLK family (D1) -- no wall-clock domain. Both clocks
#   are the SAME physical mclk net at integration (clk and ClkMem bound to mclk),
#   so the master port m_* <-> arb_*(4) handshake is mclk<->mclk (NOT a CDC),
#   exactly like the harts.
#
#   PERIOD DECISION (20 ns for BOTH clk and ClkMem -- the BENCH-DRIVEN rate;
#   orchestrator honest-SDC precedent, RTC A6 / NFC rf_clk / PWM / OneWire):
#     The design MCLK is ~40 ns / 24-25 MHz (the NFC/I3C/QSPI/RTC/PWM/OW class).
#     But the standalone bench (DMA_tb.vhd) drives clk with PERIOD = 20 ns
#     (DMA_tb.vhd:388 `constant PERIOD : time := 20 ns`) and ClkMem gated from
#     that SAME net (ClkMem <= clk when en_mem='0' else '0', DMA_tb.vhd:497), so
#     the SDF gate sim is driven at 20 ns. We constrain BOTH clocks AT 20 ns --
#     the BENCH RATE is what the netlist must actually meet, and 20 ns is the
#     HARDER of the two (2x tighter than the 40 ns real MCLK), so constraining at
#     20 ns BOUNDS the real-silicon 40 ns MCLK-class case too. Like PWM/OW, DMA's
#     `clk` cone is DEEP -- the 17-bit address adders, the 32-bit LEN
#     down-counter, the four-stage 8-bit CRC16 combinational chain, the RR/PRIO
#     picker, and the deny-guard comparators -- so we honestly target the 20 ns
#     rate the SDF gate sim runs at rather than relying on slack margin. An honest
#     gate closure targets the harder of the two rates the bench and silicon
#     present.
#
# CLOCK GROUPS / CDC (two asynchronous groups -- follows the RTC/PWM/OW house
# pattern, which declared clk vs ClkMem -asynchronous even though they are the
# SAME mclk net at integration):
#   clk and ClkMem are the SAME physical mclk net at integration (D1); there is NO
#   metastability CDC between them (contrast the RTC's genuine LFXT<->clk
#   crossings). Every inter-"domain" hand-off is a REGISTERED level or a
#   single-clock toggle edge-detect, kept standalone-honest (DMA.vhd CDC
#   inventory #4-#8):
#     (1) ClkMem -> clk: the D8 go_tgl / D15 abort_tgl toggles 2-FF+edge-detected
#         in clk_cdc co-sampling the quasi-static SRC/DST/LEN/CFG stores
#         (data-before-flag); the D16 clr_done_tgl/clr_err_tgl W1C toggles
#         2-FF+edge-detected, applied SET-WINS in the engine process that owns each
#         sticky flag; the crc_wr_tgl seed-commit toggle (RTC write-commit idiom,
#         crc_acc single owner); and the quasi-static dmaen/doneie/errie levels.
#     (2) clk -> ClkMem: the D8 busy 2-FF into ClkMem (busy_sync, the ONE real
#         2-FF here) for launch-suppress; and the sticky levels
#         busy_any/activech/done_flag/err_flag/len_work/crc_acc read DIRECTLY by
#         the ClkMem read mux (held/quasi-static levels, coincident nets at
#         integration -- the RTC/OW SR.BUSY raw-read registered by reg_read).
#     (3) fabric -> clk: the three pacing trigger inputs, 2-FF synchronized
#         (tu/tq/tn) into rising-edge events (D9). Pure data, single-edge, NEVER a
#         clock (the ONLY true metastability CDC in the block).
#   These are declared -asynchronous (belt-and-suspenders: the two clocks are the
#   same net at integration, and every hand-off is a toggle or a held/quasi-static
#   level, never an async clear crossing a domain -- the ROOT-2 discipline). The
#   toggle/level structure makes them false-path/quasi-static, so no extra
#   set_false_path beyond the grouping is fabricated (RTC/NFC/I3C/PWM/OW
#   discipline: do NOT invent false paths the grouping already covers).
#   CRITICAL (the RTC lfxt2lfxt / PWM/OW clk2clk non-mistake): the REAL
#   single-cycle paths stay INSIDE their group and ARE timed -- clk<->clk (the
#   WHOLE transfer engine: the master-port FSM, the SRC/DST/LEN counter carry
#   chains, the four-stage CRC16 chain, the RR/PRIO picker, and the deny-guard
#   comparators) at 20 ns, ClkMem<->ClkMem (the register file + read mux) at 20 ns.
#   rpt/<basename>.clk2clk.rpt is the MANDATORY negative control proving the
#   engine datapath is TIMED, not cut (an empty report = the FSM/counter/CRC/deny
#   engine wrongly false-pathed). It MUST be NON-EMPTY.
#
################################################################################

set INPUT_DIR        ../common/in
set OUTPUT_DIR       out
set REPORT_DIR       rpt
set HDL_DIR          ../../hdl

set TOP_MODULE       DMA

# --- TWO SHAPES: NCH from env DMA_NCH (default 4), {2,4} only. BASENAME encodes
#     the shape so the two netlists never collide in out/. ---
if {[info exists env(DMA_NCH)]} {
	set NCH_VAL $env(DMA_NCH)
} else {
	set NCH_VAL 4
}
if {$NCH_VAL != 2 && $NCH_VAL != 4} {
	puts "FATAL: DMA_NCH must be 2 or 4 (got '$NCH_VAL')"
	exit 1
}
set BASENAME         DMA_nch${NCH_VAL}.genus
puts "### UNL STATUS ### : DMA synthesis shape NCH=$NCH_VAL  (basename $BASENAME)"

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
# Procedures (verbatim from the tile flow / QSPI / I3C / NFC / RTC / PWM / OW)
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

# Keep the netlist module named plain "DMA" for BOTH shapes (suppress the
# generic-value suffix) -- each shape's netlist FILE is the discriminator, one
# compiled per gate run.
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
# Read HDL -- DMA's RTL dependency set. DMA.vhd instantiates work.CRC16 (the
# SYSTEM0-proven CRC16-CDMA2000 cell, D14) -- read it FIRST (order-sensitive,
# behavioral cell_list order). DMA.vhd references NO constants/MemoryMap package,
# so those are not read (contrast PWM/OW which read them for template fidelity;
# DMA needs only CRC16).
################################################################################
puts "Reading HDL (DMA subset: CRC16 -> DMA)"
set MP $HDL_DIR/common

# VHDL sources use 2008 delimited comments
set_db hdl_vhdl_read_version 2008
read_hdl -vhdl -library work $MP/commune/CRC16.vhd
read_hdl -vhdl -library work $MP/periph/DMA.vhd

################################################################################
# Elaboration -- NCH overridden by-name (hart_tile_argus -parameters idiom: a
# nested {{NCH n}} list is read BY NAME; a flat {NCH n} is positional -> CDFG-601).
################################################################################
puts "Elaborating $TOP_MODULE at NCH=$NCH_VAL"
elaborate $TOP_MODULE -parameters [list [list NCH $NCH_VAL]]

set DESIGN_NAME [get_db [get_db designs] .name]
puts "Elaborated design name: $DESIGN_NAME"
if {$DESIGN_NAME ne "DMA"} {
	puts "WARNING: design name is '$DESIGN_NAME', not 'DMA' -- fix naming (the gate-sim binding contract is a module named DMA)"
}

# HARD GUARD: the NCH override must have taken. NCH does not size any PORT (the
# superset register map is fixed 4ch, D6), so we cannot count ports; instead the
# BASENAME/DESIGN_NAME + the flop count in the reports document the shape. The
# module MUST be named DMA (naming-suppression contract).
if {$DESIGN_NAME ne "DMA"} {
	puts "FATAL: design module name is not DMA -- gate binding would break"
	exit 1
}

# M9b GATE-SIM FIX: per-MODULE boundary_opto disable (root attr ignored).
set_db [get_db modules] .boundary_opto false
puts "boundary_opto disabled on [llength [get_db modules]] modules"

# NO power intent / CPF for this standalone block run.

################################################################################
# Constraints
################################################################################

# --- Primary clocks: clk/ClkMem BOTH at 20 ns (the bench rate). Both are primary
#     input pins. NO EnMemPeriph clock (D4 -- never an edge), NO generated clocks
#     (no baud divider / ClkGate; the engine is a plain FSM + counters), NO
#     trigger clocks (D9 -- the three trig_* are 2-FF synced pure data, never
#     clock a flop), NO lfxt (single MCLK family, D1). See the header. ---
create_clock -name clk    -period $MCLK_PERIOD [get_ports clk]
create_clock -name ClkMem -period $MCLK_PERIOD [get_ports ClkMem]

# --- CDC: two asynchronous groups (RTC/PWM/OW house pattern -- clk vs ClkMem
#     declared -asynchronous even though they are the SAME mclk net at
#     integration; every hand-off is a toggle or a held/quasi-static level,
#     D8/D16). Real single-cycle paths stay INSIDE a group and are timed. ---
set_clock_groups -asynchronous \
	-group {clk} \
	-group {ClkMem}

# --- Cost/path groups: clk hosts the transfer engine (master FSM + SRC/DST/LEN
#     counters + CRC chain + RR/PRIO picker + deny guard); ClkMem the register
#     file + read mux. ---
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

# Master-port inputs: m_done / m_rdata (and m_gnt, observed only) come back from
# the arbiter and are sampled by the clk-domain engine FSM (mclk<->mclk, NOT a
# CDC, D2). Budget vs `clk`.
set MASTER_IN [get_db ports {m_gnt m_done m_rdata[*]}]
set_input_delay  -clock [get_db clocks clk] $IO_BUDGET_HALF $MASTER_IN

# Pacing trigger inputs: PURE DATA (D9/A8), sampled by the clk-domain 2-FF
# synchronizers (clk_cdc: tu1 <= trig_uart0_rc, etc.). They are NOT clocks (the
# deliberate OW OW_DQ_IN / I3C SDA_IN contrast; see header). Budget vs `clk`.
set_input_delay  -clock [get_db clocks clk] $IO_BUDGET_HALF \
	[get_db ports {trig_uart0_rc trig_qspi0_rxf trig_nfc0_rxf}]

# Register-bus output: rdata_out is a ClkMem flop -> half-period vs ClkMem.
set_output_delay -clock [get_db clocks ClkMem] $IO_BUDGET_HALF [get_db ports {rdata_out[*]}]

# Master-port outputs: m_req/m_we/m_addr/m_wdata are registered clk FSM outputs
# (m_req_r/m_we_r/m_addr_r/m_wdata_r) driving arb_*(4) at depth 0 (D2). Sampled
# by the free-running mclk arbiter. Budget vs `clk`.
set_output_delay -clock [get_db clocks clk] $IO_BUDGET_HALF \
	[get_db ports {m_req m_we[*] m_addr[*] m_wdata[*]}]

# IRQ outputs: irq_done/irq_err are combinational (status and enable) off
# clk-domain sticky flags + quasi-static IE bits (D17). Sampled downstream on the
# FREE-RUNNING mclk (the on-chip interrupt router) -- ClkMem is GATED and stops,
# so it cannot sample them. Budget vs `clk` (the honest sampling clock; the
# NFC/RTC/PWM/OW irq-vs-clk treatment, forced by clk being a real leaf mclk
# domain).
set_output_delay -clock [get_db clocks clk] $IO_BUDGET_HALF [get_db ports {irq_done irq_err}]

# Async reset: applied DIRECTLY to both the clk engine and the ClkMem register
# file (D1 -- single clock family, no reset synchronizer), huge recovery margin
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
puts "Synthesizing $TOP_MODULE (NCH=$NCH_VAL)"
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
#   clk2clk is the CRITICAL one -- the entire transfer engine datapath (the
#   master-port FSM, the 17-bit SRC/DST address adders, the 32-bit LEN
#   down-counter, the four-stage CRC16 combinational chain, the RR/PRIO picker,
#   and the deny-guard comparators) MUST be timed at 20 ns. This proves the clk
#   domain is TIMED, not cut. It MUST be NON-EMPTY.
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
puts "Genus DMA run (NCH=$NCH_VAL) is complete. Run time $total_run_time"

exit
