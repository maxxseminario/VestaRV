################################################################################
#
# Genus TCL script -- NPU (P4.1 architecture family: MLP + CONV1D sequencer)
# standalone block synthesis (npu_conv_design.md S5, gate-closure ritual).
#
# Cloned from tcl/I2CTarget.genus.tcl (procs, lib-setup idiom, M9b per-module
# boundary_opto discipline). Elaborated AT THE CHIP GENERICS via the DMA
# -parameters precedent: X_M_BITS=0, W_M_BITS=7, Y_M_BITS=7, N_BITS=24, RHO=2
# (Q0.24 inputs, Q7.24 weights/acc, +-128 saturate) -- the MCU npu0 numbers,
# NOT the entity defaults (Q0.15, the standalone-bench shape; npu_conv_design
# G7). The P4.4 combined wound re-synth remains the chip-level proof; this run
# is the per-block closure evidence for the P4.1 sequencer (the 4-input conv
# address adder, the run-shadow latches, the widened 4-bit MMR decode).
#
# ---------------------------------------------------------------------------
# CLOCK TREE OF THE BLOCK (the HONEST SDC)
# ---------------------------------------------------------------------------
# THREE input clock pins, ONE physical clock: Clk, MabMmrCLK and SramCLK_in are
# ALL the same free-running mclk net at integration (MCU_MP wires all three to
# mclk; the DP-SG spec pins "MabMmrCLK and Clk must be the SAME clock" as a
# block CONSTRAINT -- the NPUSR W1C decode is sampled on Clk).
#
#   Clk        free-running mclk. Hosts NpuMuxSel (the staging-RAM port-mux
#              select flop) and the THINKDONE/ThinkDoneIrq pair, and PARENTS
#              the three ClkGate ICGs:
#                NpuClk     gated FSM clock (NpuClkEn = NpuThink or NpuDone).
#                           RISING edge: NPU_FSM_SEQ (the whole MLP+conv
#                           sequencer, run shadows, conv walkers, CurrX/W
#                           captures). FALLING edge: NPU_RAM_SEQ (the
#                           NpuSramCEN half-cycle discipline) -- a real
#                           negedge process on the gated clock, as-built.
#                MacClk     gated accumulator clock (MAC state only): the
#                           FPMac Q7.24 accumulator register.
#                NpuSramCLK gated clock OUT to the staging RAM (port-mux leg).
#              No create_generated_clock is declared: the ICGs are the ARM
#              integrated cells and Genus propagates Clk through them.
#   MabMmrCLK  register-bus clock: the MMR_WRITE process (NPUCR incl. MODE/
#              ACTF, NPUCFG1/2, SARs, NPUTHINK).
#   SramCLK_in the CPU-side staging-RAM clock, a PURE MUX PASSTHROUGH to
#              NpuSramCLK_out when the NPU is idle -- clocks NO NPU flop.
#              Declared a clock so the passthrough is timed as a clock path.
#
# CLOCK GROUPS: NONE -- deliberately SYNCHRONOUS (a deliberate deviation from
# the RTC/PWM/OneWire -asynchronous house pattern, and the honest choice
# here). Those blocks' cross-"domain" hand-offs are toggles/quasi-static
# levels; the NPU has REAL same-cycle cross-clock function: NPUCR.THINK
# (MabMmrCLK flop) -> NpuMuxSel/NpuClkEn (Clk); NPUCR/NPUCFG -> the NPU_BEGIN
# run-shadow latches (NpuClk); NpuDone (NpuClk) -> THINKDONE (Clk) -> the
# NPUTHINK clear (MabMmrCLK process). All three pins are the same mclk, so
# every one of those paths is a single-cycle 40 ns path at integration and
# MUST BE TIMED, not false-pathed. Zero skew, zero invented false paths;
# resetn recovery is the only exception (house treatment).
#
# PERIOD DECISION: 40 ns (25 MHz) for all three -- the MCU_WOUND SDC mclk
# rate, which also bounds the ~41.67 ns (24 MHz) behavioral-sim rate.
#
################################################################################

set INPUT_DIR        ../common/in
set OUTPUT_DIR       out
set REPORT_DIR       rpt
set HDL_DIR          ../../hdl

set TOP_MODULE       NPU
set BASENAME         NPU.genus

set base_freq        25
set freq_mult        1
set MCLK_FREQ        [expr $base_freq * $freq_mult]
set MCLK_PERIOD      [expr 1 / [expr $MCLK_FREQ * 0.001]]
puts "Target Clk/MabMmrCLK/SramCLK_in frequency: $MCLK_FREQ MHz (period $MCLK_PERIOD ns)"

set IO_BUDGET_HALF   [expr $MCLK_PERIOD / 2.0]  ;# 20 ns

################################################################################
# Procedures (verbatim from the tile flow / QSPI / I3C / NFC / RTC / I2CT)
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

# Keep the netlist module named plain "NPU" (suppress generic-value suffix).
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
# Read HDL -- the NPU dependency closure (cell_list_npu order; the REAL ARM ICG
# wrapper, NOT the behavioral sim ClkGate -- the MCU_DP read-list discipline).
################################################################################
puts "Reading HDL (NPU subset)"
set MP $HDL_DIR/common

# VHDL sources use 2008 delimited comments
set_db hdl_vhdl_read_version 2008
read_hdl -vhdl -library work $MP/commune/fixed_float_types_c.vhdl
read_hdl -vhdl -library work $MP/commune/fixed_pkg_c.vhdl
read_hdl -vhdl -library work $MP/constants.vhd
read_hdl -vhdl -library work $MP/MemoryMap.vhd
read_hdl -vhdl -library work $MP/commune/ClkGate_cmn65gp_ARM.vhd
read_hdl -vhdl -library work $MP/commune/FPMac.vhd
read_hdl -vhdl -library work $MP/commune/FPSigmoid.vhd
read_hdl -vhdl -library work $MP/periph/NPU.vhd

################################################################################
# Elaboration -- AT THE CHIP GENERICS (DMA -parameters precedent)
################################################################################
puts "Elaborating $TOP_MODULE at the chip generics (0/7/7/24/2)"
elaborate $TOP_MODULE -parameters [list \
	[list X_M_BITS 0] \
	[list W_M_BITS 7] \
	[list Y_M_BITS 7] \
	[list N_BITS 24] \
	[list RHO 2] ]

set DESIGN_NAME [get_db [get_db designs] .name]
puts "Elaborated design name: $DESIGN_NAME"
if {$DESIGN_NAME ne "NPU"} {
	puts "WARNING: design name is '$DESIGN_NAME', not 'NPU' -- fix naming"
}

# HARD GUARD: the generic override must have taken. At N_BITS=24 the FPMac A
# operand is 25 bits (Q0.24); at the entity DEFAULTS it would be 16 (Q0.15).
# Hierarchical instance pins are hpin objects in this Genus (a bare `pins`
# query returns empty -- burned once); if the query still comes back empty,
# WARN and rely on the post-run netlist grep (the definitive check: the
# emitted FPMac module port declaration).
set MAC_A_WIDTH [llength [get_db hpins NPU_FPMAC/A*]]
puts "FPMac A-port width: $MAC_A_WIDTH (expect 25 at the chip generics)"
if {$MAC_A_WIDTH == 0} {
	puts "WARNING: hpin query empty -- verify the FPMac A width in out/NPU.genus.v (expect \[24:0\])"
} elseif {$MAC_A_WIDTH != 25} {
	puts "FATAL: FPMac A width $MAC_A_WIDTH != 25 -- the -parameters override did NOT take (default Q0.15 elaboration)"
	exit 1
}

# M9b GATE-SIM FIX: per-MODULE boundary_opto disable (root attr ignored).
set_db [get_db modules] .boundary_opto false
puts "boundary_opto disabled on [llength [get_db modules]] modules"

################################################################################
# Constraints
################################################################################

# --- Primary clocks: all three pins at 40 ns, ONE synchronous mclk family
#     (see header -- real same-cycle cross-clock function, nothing may be cut).
#     No generated clocks declared: Clk propagates through the ARM ICGs. ---
create_clock -name Clk        -period $MCLK_PERIOD [get_ports Clk]
create_clock -name MabMmrCLK  -period $MCLK_PERIOD [get_ports MabMmrCLK]
create_clock -name SramCLK_in -period $MCLK_PERIOD [get_ports SramCLK_in]

# --- NO set_clock_groups: synchronous by design (the honest SDC, header). ---

# --- Cost/path groups ---
define_cost_group -name clk_group -weight 1
define_cost_group -name mmr_group -weight 1
path_group -from [get_db clocks Clk]       -group clk_group
path_group -from [get_db clocks MabMmrCLK] -group mmr_group

# --- I/O budgets ---------------------------------------------------------------
# Register-bus inputs (MMR write decode, sampled on MabMmrCLK). QUARTER-period
# budget, not half: MabMmrQ is a COMBINATIONAL read (the M7d bridge contract),
# so the MabMmrA/CEN -> readback-mux -> MabMmrQ path is a port-to-port
# feedthrough; a half-period input budget plus the half-period MabMmrQ output
# budget would leave the mux ZERO internal time (double-counted pessimism --
# it cost -378 ps on first close). The real path is arbiter-flop-launched
# sh_addr (arrives a few ns after the mclk edge) through the decode into the
# MCU-side bridge flop, one 40 ns cycle end-to-end; 10 ns in + 20 ns out
# bounds it with honest margin.
set IO_BUDGET_QTR [expr $MCLK_PERIOD / 4.0]  ;# 10 ns
set MEM_IN  [get_db ports {MabMmrA[*] MabMmrD[*] MabMmrCEN MabMmrWEN[*]}]
set_input_delay  -clock [get_db clocks MabMmrCLK] $IO_BUDGET_QTR $MEM_IN

# Staging-RAM read data: sampled by the NpuClk (gated Clk) FSM captures.
set_input_delay  -clock [get_db clocks Clk] $IO_BUDGET_HALF [get_db ports {SramQ_in[*]}]

# CPU-side RAM passthrough inputs: pure mux feedthrough to the *_out ports
# (timed as port-to-port paths against the same family). QUARTER-period, same
# double-count reasoning as the MMR inputs: these pins are launched by the
# arbiter/adddec mclk flops early in the cycle and the port mux is the only
# logic between them and the RAM macro -- half-in + half-out left the mux
# ZERO time (-198 ps on NpuSramA/D_out, second instance of the class).
set_input_delay  -clock [get_db clocks Clk] $IO_BUDGET_QTR \
	[get_db ports {SramA_in[*] SramD_in[*] SramCEN_in SramGWEN_in SramWEN_in[*]}]

# Register-bus read mux: COMBINATIONAL MabMmrQ (registered by the MCU-side
# bridge -- the M7d combinationalRead contract), budgeted vs MabMmrCLK.
set_output_delay -clock [get_db clocks MabMmrCLK] $IO_BUDGET_HALF [get_db ports {MabMmrQ[*]}]

# Staging-RAM drive + status/IRQ outputs: sampled downstream on free-running
# mclk (the RAM macro / the arbiter sleep logic / the irq_router).
set SRAM_OUT [get_db ports {NpuSramA_out[*] NpuSramD_out[*] NpuSramGWEN_out NpuSramWEN_out[*] NpuActive ThinkDoneIrq}]
set_output_delay -clock [get_db clocks Clk] $IO_BUDGET_HALF $SRAM_OUT

# NpuSramCEN_out: the block's ONLY falling-edge flop (NPU_RAM_SEQ asserts CEN
# on falling NpuClk BY DESIGN -- the as-built half-cycle discipline). A
# half-period output budget on a negedge-launched pin double-books the launch
# half-period (it cost -293 ps on first close). The real consumer is the RAM
# macro's CEN setup at the NEXT NpuSramCLK rising edge -- a designed
# half-cycle path whose downstream is one macro pin; quarter-period bounds it
# honestly (20 ns launch + 10 ns external < 40 ns leaves 10 ns internal for
# one flop CQ + routing).
set_output_delay -clock [get_db clocks Clk] $IO_BUDGET_QTR [get_db ports NpuSramCEN_out]

# NpuSramCLK_out is a CLOCK output (the muxed RAM clock) -- no data budget.

# Async reset: direct async clear everywhere (house treatment).
set_false_path -from [get_db ports ResetN]

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
#   mac.rpt -- paths THROUGH the FPMac (the Q7.48 resize round+saturate adder,
#   the block's fat datapath) MUST be timed at 40 ns. This proves the gated
#   NpuClk/MacClk engine is TIMED, not cut.
# (-through takes PINS, not hinsts -- TIM-233, burned twice: insts/hinsts
#  are both invalid. The MAC's Y output bus works: every path through Y
#  crosses the Q7.48 resize round+saturate adder.)
report_timing -through [get_db hpins NPU_FPMAC/Y*] -max_paths 15 \
	> $REPORT_DIR/$BASENAME.mac.rpt
#   conv address generator: paths into the SRAM address outputs (the P4.1
#   4-input IVSAR+cL+jS+kD adder feeds NpuSramA_out via the state mux).
report_timing -to [get_db ports NpuSramA_out*] -max_paths 10 \
	> $REPORT_DIR/$BASENAME.convaddr.rpt
report_timing -group mmr_group -max_paths 10 \
	> $REPORT_DIR/$BASENAME.mmr.rpt
#   XNOR mode (P4.2): the masked-XNOR -> popcount32 compressor -> 2*pop-K ->
#   signed-vs-THRESH compare cloud terminating at the xnor_outword flop.
#   The mode's fat combinational path; an empty report = wrongly cut.
report_timing -to [get_db insts xnor_outword_reg*] -max_paths 10 \
	> $REPORT_DIR/$BASENAME.xnor.rpt
#   GEMM mode (P4.3): the 3-input IVSAR+mK+CurrXIndex address add terminates
#   at NpuSramA_out and so rides convaddr.rpt above; the mode's OWN new
#   arithmetic is the SET_OUTPUT walker cloud (mK += NPUNI+1, gemm_yptr +1,
#   gemm_m +1 and their row-boundary muxing) terminating at the GEMM walker
#   flops. An empty report = the mode was wrongly cut.
report_timing -to [get_db insts {mK_reg* gemm_yptr_reg* gemm_m_reg*}] -max_paths 10 \
	> $REPORT_DIR/$BASENAME.gemm.rpt
#   ACTF activation path (P4.4): AccOutLtchd -> (tanh saturating pre-shift
#   mux) -> FPSigmoid quadratic -> post-maps (2y-1 / clamp / relu / 2y) ->
#   act_out select -> NpuSramD_out. The whole activation decision cone on
#   the SET_OUTPUT write path; an empty report = wrongly cut.
report_timing -from [get_db insts AccOutLtchd_reg*] -to [get_db ports NpuSramD_out*] -max_paths 10 \
	> $REPORT_DIR/$BASENAME.actf.rpt

################################################################################
# Output Files
################################################################################
write_script > $OUTPUT_DIR/$BASENAME.g
write_hdl    > $OUTPUT_DIR/$BASENAME.v
write_sdc    > $OUTPUT_DIR/$BASENAME.sdc
write_sdf    > $OUTPUT_DIR/$BASENAME.sdf

toc
set total_run_time [getHMS $START_TIME $STOP_TIME]
puts "Genus NPU run is complete. Run time $total_run_time"

exit
