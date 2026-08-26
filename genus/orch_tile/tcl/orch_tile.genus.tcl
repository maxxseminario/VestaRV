################################################################################
#
# Genus TCL script -- orch_tile SOFT-ORCHESTRATOR synthesis (CP4a, Castalia-Penta)
#
# CLONE of ../hart_tile/tcl/hart_tile.genus.tcl. Same RTL, same libraries, same
# constraint SHAPE. Three deliberate deltas, each traceable to a CP1 decision:
#
#  1. TOP = orch_tile (D6). hdl/common/orch_tile.vhd is a bare wrapper whose
#     whole architecture is `tile : entity work.hart_tile` -- so the elaborated
#     tree is IDENTICAL to the tile's with exactly one extra hierarchy level
#     (orch_tile/tile/...). Every hpin path below is therefore the tile script's
#     path with `tile/` inserted after the top.
#
#  2. NO POWER INTENT (D2). The tile run reads ../../cpf/hart_tile.cpf and
#     commits PD_GATED/PD_AO (MTCMOS headers + A2ISO clamps). The orchestrator
#     is ALWAYS-ON: there is no chip-level power intent in the centre band, so
#     gating it in the netlist would be a hardware lie of the hw_clint_en class.
#     Reading the tile CPF here would insert isolation clamps and mark a shutoff
#     domain that no physical switch fabric backs. The pd_sleep/pd_iso_en ports
#     survive (boundary_opto false) and are strapped '0' by MCU.vhd; the run is
#     a plain always-on synthesis.
#
#  3. THE MODULE-NAMESPACE RENAME (D6) happens AFTER this script, in
#     ../rename_orch_modules.sh: this run emits out/orch_tile.genus.{v,sdc,sdf}
#     with genus's own module names (vesta, adddec, RC_CG_MOD_*, ...) -- which
#     COLLIDE with ../hart_tile/out/hart_tile.genus.v by construction (same
#     RTL). The rename script prefixes every non-top module with `orch_` and
#     FATALs unless the two module sets are disjoint. The MCU-level flow reads
#     the RENAMED netlist, never this raw one. Top stays `orch_tile` because
#     MCU.vhd binds `entity work.orch_tile` by that name.
#
# THE SDC BUG FIX (M9c) is carried verbatim: clk_cpu is a GENERATED clock of
# mclk (divide_by 1, same domain), so core->adddec->boundary paths are timed.
# rpt/orch_tile.genus.{cpu2mclk,mclk2cpu}.rpt must show REAL PATHS -- an empty
# report is the M9c bug back.
#
# Run from the block dir:  cd genus && make orch_tile.genus
#
################################################################################

set INPUT_DIR        ../common/in
set IP_DIR           /home/mseminario2/chips/myshkin/ip
set OUTPUT_DIR       out
set REPORT_DIR       rpt
set HDL_DIR          ../../hdl

set TOP_MODULE       orch_tile
set BASENAME         orch_tile.genus

# The wrapper's single instance name (orch_tile.vhd: `tile : entity
# work.hart_tile`). Every tile-internal hpin path goes through it.
set TILE_INST        tile

# CPR6 (R3/R5): the penta shape elaborates the orchestrator at SH_AW = 16,
# EXACTLY as genus/hart_tile does (PENTA_SH_AW there). The orchestrator wraps
# hart_tile and passes SH_AW straight through, so a wrapper left at the entity
# default 15 would emit a soft core one shared-window address bit short of the
# four hardened tiles it shares an arbiter with -- a silent configuration split
# of the F-K7-4 class. Guarded below on the emitted port width.
set PENTA_SH_AW      16

# 25 MHz, same as the tile and the flat flow.
set base_freq        25
set freq_mult        1
set MCLK_FREQ        [expr $base_freq * $freq_mult]
set MCLK_PERIOD      [expr 1 / [expr $MCLK_FREQ * 0.001]]
puts "Target mclk frequency: $MCLK_FREQ MHz (period $MCLK_PERIOD ns)"

# I/O budget split (ns) at the registered boundary + the unregistered pins.
set IO_BUDGET_HALF   [expr $MCLK_PERIOD / 2.0]  ;# 20 ns each side, reg boundary
set SLEEP_EXT        25.0                       ;# sleep: external side is long
set FLASH_OUT_EXT    10.0                       ;# flash_mab/mem_en: tile keeps 30
set FLASH_IN_EXT     10.0                       ;# flash_dout: tile keeps 30

################################################################################
# Procedures (as in the tile flow)
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

# Keep the netlist module named plain "orch_tile" (default naming appends the
# generic values: orch_tile_PC_RST_VAL0_SH_AW15). MCU.vhd binds the instance by
# entity name, and the MCU-level genus run reads the netlist as SOURCE, so the
# module name is a hard contract -- checked after elaborate below.
set_db hdl_parameter_naming_style ""

set_db init_lib_search_path [list \
	$IP_DIR/sram1p8k_hvt_pg \
	$INPUT_DIR/ \
	/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10/ecsm-timing/ \
	/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10-pmk/synopsys/ ]

set_db init_hdl_search_path [list \
	$HDL_DIR ]

# Same macro/std-cell kit as the tile. The pmk view stays in the list for
# read-parity with the tile flow even though no CPF is committed here (nothing
# instantiates a HEAD switch or an A2ISO clamp in an always-on run) -- an unused
# library costs nothing and keeps the two runs comparable.
set_db library [list \
	sram1p8k_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib \
	scadv10_cln65gp_hvt_tt_1p0v_25c.lib \
	scadv10pmk_tsmc65gp_hvt_tt_1p0v_25c.lib]

set_db tns_opto true
set_db auto_ungroup none
# boundary_opto: root attr is OBSOLETED in Genus 19.15 -- the effective
# per-module form is applied post-elaborate below (M9b lesson).
set_db lp_insert_clock_gating true
set_db lp_clock_gating_register_aware true

set_dont_use TIEHIX1MA10TH false
set_dont_use TIELOX1MA10TH false
set_db use_tiehilo_for_const duplicate

################################################################################
# Read HDL -- the hart_tile subset of the MCU_MP tree, PLUS the orch wrapper
################################################################################
puts "Reading HDL (hart_tile subset + orch_tile wrapper)"
set MP $HDL_DIR/common

# Packages + the synthesizable clock-gate wrapper
# VHDL sources use 2008 delimited comments
set_db hdl_vhdl_read_version 2008
read_hdl -vhdl -library work $MP/constants.vhd
read_hdl -vhdl -library work $MP/macros/macros.vhd
read_hdl -vhdl -library work $MP/MemoryMap.vhd
read_hdl -vhdl -library work $MP/commune/ClkGate_cmn65gp_ARM.vhd

# Vesta core
read_hdl -vhdl -library work $MP/vesta/div.vhd
read_hdl -vhdl -library work $MP/vesta/alu.vhd
read_hdl -vhdl -library work $MP/vesta/extend.vhd
read_hdl -vhdl -library work $MP/vesta/regfile_sbirq.vhd
read_hdl -vhdl -library work $MP/vesta/irq_handler.vhd
read_hdl -vhdl -library work $MP/vesta/loadext.vhd
read_hdl -vhdl -library work $MP/vesta/store_ext.vhd
read_hdl -vhdl -library work $MP/vesta/branch_valid.vhd
read_hdl -vhdl -library work $MP/vesta/csr_unit.vhd
read_hdl -vhdl -library work $MP/vesta/fpu_simple.vhd
read_hdl -vhdl -library work $MP/vesta/fpu.vhd
read_hdl -vhdl -library work $MP/vesta/datapath.vhd
read_hdl -vhdl -library work $MP/vesta/maindec.vhd
read_hdl -vhdl -library work $MP/vesta/controller.vhd
read_hdl -vhdl -library work $MP/vesta/c_dec.vhd
read_hdl -vhdl -library work $MP/vesta/pmp_unit.vhd
read_hdl -vhdl -library work $MP/vesta/vesta.vhd

# Tile = core + decoder + TCM (2026-08-16: sram1p8k -- the 8 KiB macro; hart_tile selects it on MemoryMap RamSize)
read_hdl -vhdl -library work $MP/adddec.vhd
read_hdl -vhdl -library work $MP/hart_tile.vhd
# CP2/D6: the wrapper. Read LAST -- it binds work.hart_tile directly.
read_hdl -vhdl -library work $MP/orch_tile.vhd

################################################################################
# Elaboration
################################################################################
puts "Elaborating $TOP_MODULE at SH_AW=$PENTA_SH_AW (CPR6 penta shared-window width)"
# NAMED generic override, the hart_tile form: Genus -parameters takes a list of
# {name value} PAIRS, so a flat {SH_AW 16} is read POSITIONALLY (CDFG-601) and
# the nested {{SH_AW 16}} is the by-name form. Only SH_AW is overridden; every
# other generic keeps its entity default, which is what both gate netlists and
# the generic-stripped MCU.vhd bind to.
elaborate $TOP_MODULE -parameters [list [list SH_AW $PENTA_SH_AW]]

# FULL-ISA GUARD (2026-08-17), the exact MIRROR of the minimal-ISA guard in
# genus/hart_tile/tcl/hart_tile.genus.tcl, and the reason it exists is that the
# two tiles are now DELIBERATELY DIFFERENT: harts 1..N-1 are rv32iac while HART 0
# -- this orchestrator -- keeps the full ISA. Nothing above names the ISA
# generics, so hart 0's ISA rests entirely on hart_tile.vhd's `:= true` defaults
# arriving through orch_tile's own defaults. That is correct but IMPLICIT, and an
# implicit ISA is exactly what silently produced a debug-OFF macro earlier in this
# flow. Assert the divider is PRESENT: if hart_tile's defaults are ever flipped to
# match the tiles, hart 0 would quietly lose M and the chip would have no hart
# able to multiply.
set N_DIV_ORCH [llength [get_db insts -if {.name =~ "*gen_div*"}]]
puts "### UNL STATUS ### : orchestrator divider instances = $N_DIV_ORCH (expect > 0 -- hart 0 is FULL ISA)"
if {$N_DIV_ORCH == 0} {
	puts "FATAL (orch ISA): the orchestrator has NO divider -- hart 0 came out minimal-ISA."
	puts "  Harts 1-4 are rv32iac BY DESIGN; hart 0 must keep M and B. Check hart_tile.vhd's"
	puts "  ENABLE_MUL/DIV/BITMANIP generic defaults and orch_tile.vhd's pass-through."
	exit 1
}

# The netlist module name is the contract with MCU_WOUND_PENTA_hier + the strip
# script. FATAL, not WARNING (the tile flow only warns because its consumers
# were already built when the check was added; here nothing downstream exists
# yet and a mangled name must stop the flow).
set DESIGN_NAME [get_db [get_db designs] .name]
puts "Elaborated design name: $DESIGN_NAME"
if {$DESIGN_NAME ne "orch_tile"} {
	puts "FATAL: design name is '$DESIGN_NAME', not 'orch_tile' -- hdl_parameter_naming_style did not take"
	exit 1
}

# ---- CPR6 HARD GUARDS (the hart_tile pattern), seconds after elaborate ------
# G1: the SH_AW override must have taken -- sh_addr is a [SH_AW-1:0] bus, so 16
#     bit-ports at the penta width, 15 at the entity default.
set N_SHADDR [llength [get_db ports {sh_addr[*]}]]
puts "### UNL STATUS ### : sh_addr port bit-count = $N_SHADDR (expect $PENTA_SH_AW)"
if {$N_SHADDR != $PENTA_SH_AW} {
	puts "FATAL (CPR6): sh_addr is $N_SHADDR bits, expected $PENTA_SH_AW -- SH_AW override did NOT take"
	exit 1
}
# G2: the CPR2/3b external TCM slave port must be on the WRAPPER boundary
#     (45 bits: req 1 + addr 11 + rdata 32 + done 1). MCU.vhd binds hart 0's
#     aperture straight to these pins (R4-A2), so a wrapper synthesized from
#     stale RTL loses the orchestrator's own window with no other symptom.
#     46 MEANS PRE-2026-08-24 RTL, not a missing port: tcm_ext_addr was 12 bits
#     until the unloaded bit 11 was removed. That bit was the tile's whole LVS
#     `Top Cell Has Extra Pins` finding, so a 46-bit wrapper is one that
#     reintroduces it. Do not widen this number back; fix the RTL.
set N_TCMEXT [llength [get_db ports {tcm_ext_req tcm_ext_addr[*] tcm_ext_rdata[*] tcm_ext_done}]]
set N_DBG    [llength [get_db ports {dbg_haltreq dbg_resethaltreq dbg_halted}]]
puts "### UNL STATUS ### : tcm_ext port bit-count = $N_TCMEXT (expect 45), dbg pins = $N_DBG (expect 3)"
if {$N_TCMEXT != 45 || $N_DBG != 3} {
	puts "FATAL (CPR6): tcm_ext=$N_TCMEXT dbg=$N_DBG -- stale orch_tile.vhd/hart_tile.vhd (pre-CPR2/pre-D1, or the pre-2026-08-24 12-bit tcm_ext_addr)"
	exit 1
}

# M9b GATE-SIM FIX: per-MODULE boundary_opto disable (root attr ignored).
set_db [get_db modules] .boundary_opto false
puts "boundary_opto disabled on [llength [get_db modules]] modules"

# CP1 D2: NO read_power_intent / apply_power_intent / commit_power_intent.
# See the header. This is a DELIBERATE omission, not an oversight.
puts "### UNL STATUS ### : always-on run -- no CPF committed (CP1 D2)"

################################################################################
# Constraints
################################################################################

# --- Clocks: mclk at the wrapper clk port; clk_cpu as a GENERATED clock of
# mclk (SAME domain -- the M9c SDC bug fix). NOTE the extra `$TILE_INST/` level
# vs the tile script: clk_cpu is an hpin of vesta inside hart_tile inside the
# wrapper. ---
create_clock -name mclk -period $MCLK_PERIOD port:$TOP_MODULE/clk
create_generated_clock -name clk_cpu -divide_by 1 \
	-source port:$TOP_MODULE/clk hpin:$TOP_MODULE/$TILE_INST/core/clk_cpu

# The XIP flash memory clock is a gated-clock OUTPUT (adddec cg_flash). Declare
# it so no data-style output budget is ever applied to it. It is left OPEN on
# the orchestrator instance at MCU level (D3: the flash quartet is hart 0's),
# but the pin exists and must be constrained like the tile's.
create_generated_clock -name flash_clk_mem -divide_by 1 \
	-source port:$TOP_MODULE/clk port:$TOP_MODULE/flash_clk_mem

# --- Cost/path groups ---
define_cost_group -name mclk_group    -weight 1
define_cost_group -name clk_cpu_group -weight 1
path_group -from mclk    -group mclk_group
path_group -from clk_cpu -group clk_cpu_group

# --- TCM PGEN/RETN: powered-down-macro timing exceptions (tile paths + tile/) ---
set_false_path -to pin:$TOP_MODULE/$TILE_INST/ram0/PGEN
set_false_path -to pin:$TOP_MODULE/$TILE_INST/ram0/RETN

# --- I/O budgets (identical to the tile: same ports, same boundary) ---
# CPR6 (R4, hard rule 3): the external TCM slave port joins the registered
# boundary here for the same reason it does in the tile flow -- tcm_ext_req/
# tcm_ext_addr land on bnd_tcm_ext's mclk flops, tcm_ext_rdata/tcm_ext_done
# leave from tx_rdata_r/tx_done_r, and it is its OWN transaction set (nothing
# here shares a transaction with sh_*), so the same half-period split applies.
#   REG_IN  += tcm_ext_req(1) + tcm_ext_addr[10:0](11)   = 12  -> 51 total
#   REG_OUT += tcm_ext_rdata[31:0](32) + tcm_ext_done(1) = 33  -> 89 total
#     (REG_OUT is 89 and not 87 because sh_addr widened to 16 bits at SH_AW=16.)
# THE D1 DBG TRIO IS NOW IN THESE LISTS (2026-08-16). The previous note said it
# was deliberately out because "the penta configs set no debug knob, so
# ENABLE_DEBUG stays false and genus constant-folds the boundary", and ended
# "Revisit if a debug-ON tile is ever hardened." THAT CONDITION IS NOW MET:
# debug.enable is a SHIPPED DEFAULT, so the boundary flops are real and the
# three ports were being left with NO I/O budget at all -- the M9c
# silently-unconstrained class, one layer out.
# Measured before fixing, so the severity is on record rather than guessed: the
# emitted ETM already carries 2 timing arcs on each of the three pins (the same
# as msip_in/sh_req), so CHIP-LEVEL timing of dm0 -> tile was never blind. What
# was missing is the budget the tile's own optimisation targets, on depth-1
# paths at a 40 ns period. Low impact, real defect, fixed here.
set REG_IN  [get_db ports {msip_in mtip_in meip_in sh_gnt sh_done sh_rdata[*] sh_scfail sh_resv_valid \
                           tcm_ext_req tcm_ext_addr[*] dbg_haltreq dbg_resethaltreq}]
set REG_OUT [get_db ports {sh_req sh_we[*] sh_addr[*] sh_wdata[*] sh_lrsc[*] sh_lock \
                           tcm_ext_rdata[*] tcm_ext_done dbg_halted}]
puts "### UNL STATUS ### : REG_IN = [llength $REG_IN] bits, REG_OUT = [llength $REG_OUT] bits"
set_input_delay  -clock [get_db clocks mclk] $IO_BUDGET_HALF $REG_IN
set_output_delay -clock [get_db clocks mclk] $IO_BUDGET_HALF $REG_OUT

set_input_delay  -clock [get_db clocks mclk] $SLEEP_EXT     [get_db ports sleep]
set_input_delay  -clock [get_db clocks mclk] $FLASH_IN_EXT  [get_db ports {flash_dout[*]}]
set_output_delay -clock [get_db clocks mclk] $FLASH_OUT_EXT [get_db ports {flash_mem_en flash_mab[*]}]

# Static straps and quasi-static observation pins (pd_sleep/pd_iso_en are
# strapped constants on this instance -- kept in the list so the port survives
# with the same treatment the tile gives it).
set_false_path -from [get_db ports {hart_id[*] tcm_pgen tcm_retn pd_sleep pd_iso_en}]
set_false_path -to   [get_db ports {trap_flag a0[*]}]
set_false_path -from [get_db ports resetn]

################################################################################
# Top Design Attributes
################################################################################
set_max_transition 0.5
set_load 0.600 [get_ports -filter "direction==out"]
set_driving_cell -lib_cell INVX1MA10TH [get_ports -filter "direction==in"]

################################################################################
# Synthesis -- TIME-OPTIMIZED, AREA-RELAXED (as the tile flow)
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

# SDC-fix negative controls (M9c): both must show real timed paths.
report_timing -from [get_db clocks clk_cpu] -to [get_db clocks mclk] -max_paths 10 \
	> $REPORT_DIR/$BASENAME.cpu2mclk.rpt
report_timing -from [get_db clocks mclk] -to [get_db clocks clk_cpu] -max_paths 10 \
	> $REPORT_DIR/$BASENAME.mclk2cpu.rpt

################################################################################
# CPR6 verification reports -- the R4-A1/A3 Q-shadow handshake in the SOFT copy
################################################################################
# The same mechanism the hardened tile carries, synthesized here as flat centre-
# band logic: tcm_q_arm is an mclk flop reading tcm_q_ack, tcm_q_ack is a
# clk_cpu flop reading tcm_q_arm. The clk_cpu->mclk leg is a real single-cycle
# mclk path (clk_cpu IS mclk, gated) and MUST BE TIMED -- an empty report is
# the M9c bug class, not a clean control. NOTE (measured at CPR5): get_db
# object names are DESIGN-RELATIVE, so a `$TOP_MODULE/...` pattern matches
# nothing and returns an empty list SILENTLY.
set QACK [get_db insts *tcm_q_ack_reg]
set QARM [get_db insts *tcm_q_arm_reg]
puts "### UNL STATUS ### : tcm_q_ack_reg=[llength $QACK] tcm_q_arm_reg=[llength $QARM]"
if {[llength $QACK] != 1 || [llength $QARM] != 1} {
	puts "FATAL (CPR6): the Q-shadow handshake flops are not both present -- R4-A1/A3 mechanism missing"
}
catch {report_timing -from $QACK -max_paths 10 > $REPORT_DIR/$BASENAME.tcmqack.rpt} e1
catch {report_timing -to   $QARM -max_paths 10 > $REPORT_DIR/$BASENAME.tcmqarm.rpt} e2
puts "### UNL STATUS ### : tcmqack rc='$e1' tcmqarm rc='$e2'"
# Both arms of the dual-gated ram0 clock mux must be timed (core arm cg_mem on
# gated clk_cpu, external arm cg_tcm_ext on gated mclk) -- no set_clock_groups
# anywhere (hard rule 3).
set RAM0_A   [get_db pins *ram0/A*]
set RAM0_CTL [concat [get_db pins *ram0/CEN] [get_db pins *ram0/GWEN] [get_db pins *ram0/WEN*]]
puts "### UNL STATUS ### : ram0 A pins=[llength $RAM0_A] ctl pins=[llength $RAM0_CTL]"
catch {report_timing -to $RAM0_A   -max_paths 20 > $REPORT_DIR/$BASENAME.ram0_a.rpt}   e3
catch {report_timing -to $RAM0_CTL -max_paths 20 > $REPORT_DIR/$BASENAME.ram0_ctl.rpt} e4
puts "### UNL STATUS ### : ram0_a rc='$e3' ram0_ctl rc='$e4'"

################################################################################
# Output Files -- RAW names. ../rename_orch_modules.sh turns these into
# out/orch_tile.renamed.{v,sdc,sdf}, which is what every downstream flow reads.
################################################################################
write_script > $OUTPUT_DIR/$BASENAME.g
write_hdl    > $OUTPUT_DIR/$BASENAME.v
write_sdc    > $OUTPUT_DIR/$BASENAME.sdc
write_sdf    > $OUTPUT_DIR/$BASENAME.sdf

toc
set total_run_time [getHMS $START_TIME $STOP_TIME]
puts "Genus orch_tile run is complete. Run time $total_run_time"
puts "NEXT: cd ../ ; ./orch_tile/rename_orch_modules.sh   (D6 module-namespace rename + disjointness assertion)"

exit
