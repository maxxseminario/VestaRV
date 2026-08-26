################################################################################
#
# Genus TCL script -- hart_tile TILE-ONLY synthesis (M14 physical flow)
#
# Derived from tcl/MCU_MP.genus.tcl (the flat 4-hart flow). This synthesizes
# ONE hart_tile standalone: the M13 tile extraction made all four hart
# instances structurally identical, so M14 hardens a single tile netlist and
# the top-level flow places it 4x (the flat flow uniquified the tile into
# hart_tile_PC_RST_VAL0_SH_AW15{,_1,_2,_3} -- this run is what delivers the
# one-netlist goal).
#
# THE SDC BUG FIX (M9c note in ~/vesta_docs/multicore_plan.md): the flat flow
# put clk_cpu<h> in its OWN clock domain, which false-paths every
# clk_cpu<->mclk path BY CONSTRUCTION. But clk_cpu IS mclk -- the same
# physical clock, gated by ClkGate inside vesta (en_clk_cpu). Core->adddec->
# boundary-register paths are real single-cycle mclk paths and were silently
# unconstrained in every flat run. Here clk_cpu is a GENERATED clock of mclk
# (divide_by 1, same domain), so those paths are timed. Verification reports
# rpt/hart_tile.genus.{cpu2mclk,mclk2cpu}.rpt must show REAL PATHS (the flat
# flow's equivalent cross-domain query returns none -- that is the
# constraint-level negative control).
#
# Registered tile boundary (M13, depth 1 on mclk): every shared-bus + IRQ
# port is flop->pin or pin->flop inside the tile, so I/O budgets are a clean
# half-period split. UNREGISTERED pins get explicit budgets/exceptions:
#   sleep         input, gates clk_cpu (SPI0 XIP stall). External side gets
#                 the larger share (25 ns): at top it travels SPI0->hart0 pin
#                 after placement; inside the tile it is a short hop into the
#                 ClkGate enable. A LATE sleep = core eats garbage flash_dout
#                 mid-XIP (M13 header) -- this budget is the contract that
#                 makes the top-level path checkable.
#   flash_mab/flash_mem_en  combinational core->adddec->pin (XIP address):
#                 tile keeps 30 ns (real logic depth), external 10 ns.
#   flash_dout    input into the core's read-data path (deep): external
#                 10 ns, tile keeps 30 ns.
#   flash_clk_mem GATED CLOCK OUTPUT (adddec cg_flash) -- declared as a
#                 generated clock at the port, never given a data budget.
#   hart_id/tcm_pgen  static straps -> false path.
#   trap_flag/a0  quasi-static observation -> false path.
#
################################################################################

set INPUT_DIR        ../common/in
set IP_DIR           /home/mseminario2/chips/myshkin/ip
set OUTPUT_DIR       out
set REPORT_DIR       rpt
set HDL_DIR          ../../hdl

set TOP_MODULE       hart_tile
set BASENAME         hart_tile.genus.isa_iac

# CPR5 (R3/R5, castalia_penta/cpr_architecture.md): the penta shape elaborates
# the tile at SH_AW = 16. The orchestrator config widens the shared window to
# 0x0-0x3FFFF (five read-only TCM apertures at 0x20000 + 0x4000*h, extended
# flash from 0x40000), so sh_addr is 16 bits and the MCU-level arbiter is a
# 16-bit-sh_addr arbiter -- the tile netlist MUST match or the assembly wires
# every tile one bit short. The hart_tile.vhd generic DEFAULT is still 15 and
# flips to 16 at CPR8 (R6) when penta becomes the shipped default; until then
# this override is what makes the hardened macro the penta macro.
set PENTA_SH_AW      16

# 25 MHz, same as the proven flat flow.
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
# Procedures (as in the flat flow)
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

# Keep the netlist module named plain "hart_tile" (default naming appends the
# generic values: hart_tile_PC_RST_VAL0_SH_AW15). The tile netlist/LEF/LIB/SDF
# must all carry ONE name so the hierarchical top and the gate sim resolve the
# 4 instances against it.
set_db hdl_parameter_naming_style ""

set_db init_lib_search_path [list \
	$IP_DIR/sram1p8k_hvt_pg \
	$INPUT_DIR/ \
	/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10/ecsm-timing/ \
	/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10-pmk/synopsys/ ]

set_db init_hdl_search_path [list \
	$HDL_DIR ]

# Tile macros: only the TCM SRAM (no ROM in a tile).
# M17: the ARM Power Management Kit (sc-ad10-pmk) joins the always-on kit —
# HEAD switches / A2ISO clamps / GPG always-on buffers for the CPF flow.
# NOTE the pmk view is NLDM (no ECSM exists for it in any Vt flavor — M17
# recon); mixing NLDM pmk + ECSM core in one library list is accepted, at
# some SI-accuracy cost on the handful of pmk instances.
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
# Read HDL -- the hart_tile subset of the MCU_MP tree
################################################################################
puts "Reading HDL (hart_tile subset)"
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
# X4 Zfinx FPU units — instantiated in datapath.vhd behind gen_fpu (ENABLE_ZFINX).
# Read before datapath.vhd so the component bindings resolve to the real entities
# in the ON build; harmless (uninstantiated) in the OFF build's inactive generate.
read_hdl -vhdl -library work $MP/vesta/fpu_simple.vhd
read_hdl -vhdl -library work $MP/vesta/fpu.vhd
read_hdl -vhdl -library work $MP/vesta/datapath.vhd
read_hdl -vhdl -library work $MP/vesta/maindec.vhd
read_hdl -vhdl -library work $MP/vesta/controller.vhd
read_hdl -vhdl -library work $MP/vesta/c_dec.vhd
# P3 PMP match unit — instantiated in vesta.vhd behind gen_pmp (ENABLE_PMP).
# Read before vesta.vhd so the component binding resolves in the ON build;
# harmless (uninstantiated) in the OFF build's inactive generate.
read_hdl -vhdl -library work $MP/vesta/pmp_unit.vhd
read_hdl -vhdl -library work $MP/vesta/vesta.vhd

# Tile = core + decoder + TCM (2026-08-16: sram1p8k -- the 8 KiB macro; hart_tile selects it on MemoryMap RamSize)
read_hdl -vhdl -library work $MP/adddec.vhd
read_hdl -vhdl -library work $MP/hart_tile.vhd

################################################################################
# Elaboration
################################################################################
puts "Elaborating $TOP_MODULE at SH_AW=$PENTA_SH_AW (CPR5 penta shared-window width)"
# NAMED generic override: Genus -parameters takes a list of {name value}
# PAIRS. A flat {SH_AW 16} is read POSITIONALLY (SH_AW parsed as a value ->
# CDFG-601); the nested {{SH_AW 16}} is the by-name form. Only SH_AW is
# overridden; PC_RST_VAL + the ENABLE_* ISA/priv/debug switches keep their
# entity defaults (ENABLE_DEBUG stays FALSE -- the penta configs set no debug
# knob, so the dbg_haltreq/dbg_resethaltreq/dbg_halted PINS exist on the
# boundary while the core-side debug logic does not).
# DEBUG (2026-08-16): named EXPLICITLY for the same reason SH_AW is, and the
# SH_AW comment's own logic applies verbatim -- the hardened macro MUST match
# what the assembly wires. MCU.vhd instantiates the tile with
# ENABLE_DEBUG => CORE_ENABLE_DEBUG, which is TRUE since debug.enable became a
# shipped default; a bare elaborate takes hart_tile.vhd's generic default, and
# when that default was still `false` THIS FLOW SILENTLY PRODUCED A DEBUG-OFF
# TILE -- measured, not hypothesised: the netlist came out byte-for-byte the
# pre-flip tile (15,096 cells / 2,464 sequential, identical area report). That
# is the M14 hw_clint_en VHDL-default-lost-at-netlist-boundary silicon bug
# reproduced exactly. The default is now true AND named here; the guard below
# is what makes a future divergence loud instead of silent.
set PENTA_ENABLE_DEBUG true
# ISA A/B VARIANT (iac): A+C only -- the "pretty minimal" satellite core (no M, no B)
# THE OVERRIDES MUST BE -parameters, NOT MemoryMap.vhd CONSTANTS. hart_tile's
# ISA switches are ENTITY GENERICS with `:= true` defaults; a bare
# `elaborate hart_tile` takes those defaults and IGNORES CORE_ENABLE_* entirely
# (MCU.vhd is what wires the constants to the generics, and there is no MCU.vhd
# in a tile-only run). Patching the memory map here would have produced a
# netlist identical to the full-ISA one and been read as "the ISA costs
# nothing" -- the same trap ENABLE_DEBUG sprang earlier in this flow.
elaborate $TOP_MODULE -parameters [list [list SH_AW $PENTA_SH_AW] \
                                       [list ENABLE_DEBUG $PENTA_ENABLE_DEBUG] \
                                       [list ENABLE_MUL false] \
                                       [list ENABLE_DIV false] \
                                       [list ENABLE_BITMANIP false]]

# Verify the parameter-naming suppression took (the netlist module name is the
# contract with the hierarchical top + gate sim).
set DESIGN_NAME [get_db [get_db designs] .name]
puts "Elaborated design name: $DESIGN_NAME"
if {$DESIGN_NAME ne "hart_tile"} {
	puts "WARNING: design name is '$DESIGN_NAME', not 'hart_tile' -- fix naming before the hierarchical top run"
}

# HARD GUARD (the hart_tile_argus pattern): the SH_AW override must have taken
# -- sh_addr is a [SH_AW-1:0] bus, so 16 bit-ports at the penta width, 15 at
# the Castalia entity default. Fail fast, seconds after elaborate, before the
# long synth.
set N_SHADDR [llength [get_db ports sh_addr*]]
puts "### UNL STATUS ### : sh_addr port bit-count = $N_SHADDR (expect $PENTA_SH_AW)"
if {$N_SHADDR != $PENTA_SH_AW} {
	puts "FATAL (CPR5): sh_addr is $N_SHADDR bits, expected $PENTA_SH_AW -- SH_AW override did NOT take"
	exit 1
}

# DEBUG GUARD (2026-08-16), the SH_AW guard's sibling and added for a defect
# that ACTUALLY HAPPENED here (see the elaborate comment above). The dbg_*
# PORTS are on the boundary either way -- they carry VHDL defaults, so a port
# census can NOT tell a debug-ON tile from a debug-OFF one, and that is exactly
# why the miss was invisible. The discriminator has to be internal: hart_tile's
# `gen_dbg_bnd` generate creates the bnd_haltreq_r / bnd_rsthalt_r / bnd_halted_r
# boundary flops, and the `gen_dbg_bnd_off` arm replaces them with constants, so
# the nets exist ONLY on a debug-ON elaborate.
# Fails CLOSED: if this query ever stops matching (a Genus naming change, a
# rename of the generate block) the count goes to 0 and the run STOPS. A guard
# that silently matches nothing is the thing it is here to prevent.
set N_DBGBND [llength [get_db nets -if {.name =~ "*bnd_haltreq_r*"}]]
puts "### UNL STATUS ### : debug boundary-flop nets = $N_DBGBND (expect >0 for ENABLE_DEBUG=$PENTA_ENABLE_DEBUG)"
if {$PENTA_ENABLE_DEBUG && $N_DBGBND == 0} {
	puts "FATAL (debug flip): ENABLE_DEBUG did NOT take -- gen_dbg_bnd emitted no"
	puts "  boundary flops, so this tile is DEBUG-OFF while MCU.vhd wires it DEBUG-ON."
	puts "  That is the M14 hw_clint_en netlist-boundary class. Do NOT harden this netlist."
	exit 1
}

# SECOND GUARD: the CPR2/3b external TCM slave port must be on the boundary
# (45 bits: req 1 + addr 11 + rdata 32 + done 1). A tile hardened without it
# cannot serve an aperture, and the omission is invisible until chip LVS.
# 46 MEANS PRE-2026-08-24 RTL, not a missing port: tcm_ext_addr was 12 bits
# until the unloaded bit 11 was removed. That bit was the tile's whole LVS
# `Top Cell Has Extra Pins` finding, so a 46-bit tile is one that reintroduces
# it. Do not widen this number back; fix the RTL that produced it.
set N_TCMEXT [llength [get_db ports {tcm_ext_req tcm_ext_addr[*] tcm_ext_rdata[*] tcm_ext_done}]]
set N_DBG    [llength [get_db ports {dbg_haltreq dbg_resethaltreq dbg_halted}]]
puts "### UNL STATUS ### : tcm_ext port bit-count = $N_TCMEXT (expect 45), dbg pins = $N_DBG (expect 3)"
if {$N_TCMEXT != 45 || $N_DBG != 3} {
	puts "FATAL (CPR5): tcm_ext=$N_TCMEXT dbg=$N_DBG -- stale hart_tile.vhd (pre-CPR2/pre-D1, or the pre-2026-08-24 12-bit tcm_ext_addr)"
	exit 1
}

# M9b GATE-SIM FIX: per-MODULE boundary_opto disable (root attr ignored).
set_db [get_db modules] .boundary_opto false
puts "boundary_opto disabled on [llength [get_db modules]] modules"

################################################################################
# Power intent (M17 MTCMOS) — the tile CPF: PD_GATED (default, shutoff =
# pd_sleep) + PD_AO (ram0 + ports + iso). Genus inserts the A2ISO output
# clamps and marks the domains; the switch fabric itself is Innovus's job.
################################################################################
read_power_intent -cpf ../../cpf/hart_tile.cpf -module hart_tile
apply_power_intent -summary
commit_power_intent
puts "### UNL STATUS ### : power intent committed (PD_GATED/PD_AO)"

################################################################################
# Constraints
################################################################################

# --- Clocks: mclk at the tile clk port; clk_cpu as a GENERATED clock of mclk
# (SAME domain -- the M9c SDC bug fix; see header). ---
create_clock -name mclk -period $MCLK_PERIOD port:$TOP_MODULE/clk
create_generated_clock -name clk_cpu -divide_by 1 \
	-source port:$TOP_MODULE/clk hpin:$TOP_MODULE/core/clk_cpu

# The XIP flash memory clock is a gated-clock OUTPUT (adddec cg_flash). Declare
# it so downstream consumers (SPI0 at top level) see a clock source, and so no
# data-style output budget is ever applied to it.
create_generated_clock -name flash_clk_mem -divide_by 1 \
	-source port:$TOP_MODULE/clk port:$TOP_MODULE/flash_clk_mem

# --- Cost/path groups ---
define_cost_group -name mclk_group    -weight 1
define_cost_group -name clk_cpu_group -weight 1
path_group -from mclk    -group mclk_group
path_group -from clk_cpu -group clk_cpu_group

# --- TCM PGEN: powered-down-macro timing exception (as in the flat flow) ---
set_false_path -to pin:$TOP_MODULE/ram0/PGEN
# PG1 F2: RETN is now a port strapped '1' at MCU level (AO) — same treatment.
set_false_path -to pin:$TOP_MODULE/ram0/RETN

# --- I/O budgets ---
# Registered boundary (M13 depth-1 flops at both ends): half-period split.
# X1 Zawrs (e3ba993) added sh_resv_valid — boundary-registered on mclk like
# sh_scfail (bnd_resvvld_r), so it joins the registered-boundary class. The
# Zawrs commit missed this list; caught at the Stage-F2a tile-port audit.
#
# CPR5 (R4, hard rule 3): the external TCM slave port joins the registered
# boundary in the SAME change that hardens it. tcm_ext_req/tcm_ext_addr land
# on bnd_tcm_ext's mclk flops (tx_req_r/tx_addr_r); tcm_ext_rdata/tcm_ext_done
# leave from tx_rdata_r/tx_done_r. It is its OWN transaction set (the D1 debug
# trio precedent) -- the M13 one-depth rule is about skew BETWEEN signals in
# ONE transaction, and nothing here shares a transaction with sh_*, so the same
# half-period split applies. The D1 debug trio is likewise depth-1 mclk and is
# NOT exempted the way `sleep` and the flash/XIP ports are.
#   REG_IN  += tcm_ext_req(1) + tcm_ext_addr[10:0](11)          = 12
#   REG_OUT += tcm_ext_rdata[31:0](32) + tcm_ext_done(1)        = 33
# The D1 dbg trio is deliberately NOT in these lists: the penta configs set no
# debug knob, so ENABLE_DEBUG stays false and genus constant-folds the boundary
# (`assign dbg_halted = 1'b0;`, both inputs tied off into the core). They are
# LEF pins with no timed path either way. Revisit if a debug-ON tile is ever
# hardened.
set REG_IN  [get_db ports {msip_in mtip_in meip_in sh_gnt sh_done sh_rdata[*] sh_scfail sh_resv_valid \
                           tcm_ext_req tcm_ext_addr[*]}]
set REG_OUT [get_db ports {sh_req sh_we[*] sh_addr[*] sh_wdata[*] sh_lrsc[*] sh_lock \
                           tcm_ext_rdata[*] tcm_ext_done}]
puts "### UNL STATUS ### : REG_IN = [llength $REG_IN] bits, REG_OUT = [llength $REG_OUT] bits"
set_input_delay  -clock [get_db clocks mclk] $IO_BUDGET_HALF $REG_IN
set_output_delay -clock [get_db clocks mclk] $IO_BUDGET_HALF $REG_OUT

# Unregistered pins (explicit budgets -- the M13 carry-forward list).
set_input_delay  -clock [get_db clocks mclk] $SLEEP_EXT     [get_db ports sleep]
set_input_delay  -clock [get_db clocks mclk] $FLASH_IN_EXT  [get_db ports {flash_dout[*]}]
set_output_delay -clock [get_db clocks mclk] $FLASH_OUT_EXT [get_db ports {flash_mem_en flash_mab[*]}]

# Static straps and quasi-static observation pins. M17: pd_sleep/pd_iso_en
# are quasi-static domain controls — they only transition while the domain
# is quiesced (pwr_ctrl sequencing), never against live logic.
set_false_path -from [get_db ports {hart_id[*] tcm_pgen tcm_retn pd_sleep pd_iso_en}]
set_false_path -to   [get_db ports {trap_flag a0[*]}]
# Async reset: deassertion is synchronized externally by the POR/reset fabric;
# recovery has huge margin at 25 MHz (same treatment the flat flow gave it by
# never constraining the POR-driven resetn).
set_false_path -from [get_db ports resetn]

################################################################################
# Top Design Attributes
################################################################################
set_max_transition 0.5
set_load 0.600 [get_ports -filter "direction==out"]
set_driving_cell -lib_cell INVX1MA10TH [get_ports -filter "direction==in"]

################################################################################
# Synthesis -- TIME-OPTIMIZED, AREA-RELAXED (as the flat flow)
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

# SDC-fix verification: these crossings were FALSE (empty) in every flat run.
# They must now show real timed paths (core clk_cpu regs -> mclk boundary/TCM
# side and back). An empty report here = the bug is back.
report_timing -from [get_db clocks clk_cpu] -to [get_db clocks mclk] -max_paths 10 \
	> $REPORT_DIR/$BASENAME.cpu2mclk.rpt
report_timing -from [get_db clocks mclk] -to [get_db clocks clk_cpu] -max_paths 10 \
	> $REPORT_DIR/$BASENAME.mclk2cpu.rpt

################################################################################
# CPR5 verification reports (R4-A1/A3 + the dual-gated ram0 clock)
################################################################################
#
# (1) THE tcm_q_ack EDGE. The Q-shadow handshake (R4-A1/A3) closes a loop that
#     crosses the gated-clock boundary IN BOTH DIRECTIONS: tcm_q_arm is an mclk
#     flop whose D reads tcm_q_ack, and tcm_q_ack is a clk_cpu flop whose D
#     reads tcm_q_arm. The clk_cpu->mclk leg (tcm_q_ack -> tcm_q_arm) is a NEW
#     member of the sh_dphase->boot_fetched class and MUST BE TIMED -- it is a
#     real single-cycle mclk path (clk_cpu IS mclk, gated), and false-pathing
#     it (the M9c clock-groups bug) would silently unconstrain the shadow-hold
#     handshake that keeps a contended TCM load from being corrupted. An EMPTY
#     report here is a FAILURE, not a clean result.
# NOTE ON get_db NAMES (measured, CPR5): object names here are DESIGN-RELATIVE
# ("ram0/CLK", "tcm_q_ack_reg") -- a `$TOP_MODULE/...` pattern matches NOTHING
# and get_db returns an empty list SILENTLY, so a report written that way is an
# empty file that looks like a passing negative control. The `pin:hart_tile/...`
# TYPED form used by the set_false_path lines above is a different addressing
# scheme and does resolve; patterns must not carry the design name.
set QACK [get_db insts *tcm_q_ack_reg]
set QARM [get_db insts *tcm_q_arm_reg]
puts "### UNL STATUS ### : tcm_q_ack_reg=[llength $QACK] tcm_q_arm_reg=[llength $QARM]"
if {[llength $QACK] != 1 || [llength $QARM] != 1} {
	puts "FATAL (CPR5): the Q-shadow handshake flops are not both present -- R4-A1/A3 mechanism missing"
}
catch {report_timing -from $QACK -max_paths 10 > $REPORT_DIR/$BASENAME.tcmqack.rpt} e1
catch {report_timing -to   $QARM -max_paths 10 > $REPORT_DIR/$BASENAME.tcmqarm.rpt} e2
puts "### UNL STATUS ### : tcmqack rc='$e1' tcmqarm rc='$e2'"

# (2) THE DUAL-GATED ram0 CLOCK. Since CPR2 the TCM macro's CLK has TWO gated
#     sources muxed by tx_sel: the core arm clk_mem(1) (adddec's cg_mem, a gated
#     clk_cpu = a gated mclk) and the external arm tx_ext_clk (cg_tcm_ext, a
#     directly gated mclk). BOTH are gated subsets of the one mclk, so there is
#     NO set_clock_groups anywhere (hard rule 3) and genus must propagate mclk
#     through both mux arms. These reports show the data paths INTO the muxed
#     macro pins from both sides: the core-side launch flops (clk_cpu domain,
#     via mem_addr/mem_en/wen_fe) and the external-side launch flops (mclk
#     domain, tx_addr_r / the tx FSM). If either arm is missing, the mux has
#     been treated as a domain crossing and the untimed arm is unconstrained.
set RAM0_A   [get_db pins *ram0/A*]
set RAM0_CTL [concat [get_db pins *ram0/CEN] \
                     [get_db pins *ram0/GWEN] \
                     [get_db pins *ram0/WEN*]]
puts "### UNL STATUS ### : ram0 A pins=[llength $RAM0_A] ctl pins=[llength $RAM0_CTL]"
catch {report_timing -to $RAM0_A   -max_paths 20 > $REPORT_DIR/$BASENAME.ram0_a.rpt}   e3
catch {report_timing -to $RAM0_CTL -max_paths 20 > $REPORT_DIR/$BASENAME.ram0_ctl.rpt} e4
puts "### UNL STATUS ### : ram0_a rc='$e3' ram0_ctl rc='$e4'"
# The clock structure itself, as genus sees it (which clocks reach ram0/CLK and
# what the two gating elements are).
catch {report_clocks > $REPORT_DIR/$BASENAME.clocks.rpt}
catch {
	set _p [get_db pins *ram0/CLK]
	puts "### UNL STATUS ### : ram0/CLK pins found = [llength $_p]"
	puts "### UNL STATUS ### : ram0/CLK clocks = [get_db $_p .clocks]"
	puts "### UNL STATUS ### : ram0/CLK net    = [get_db $_p .net.name]"
	puts "### UNL STATUS ### : ram0/CLK drivers= [get_db $_p .net.drivers]"
	puts "### UNL STATUS ### : ram0/CLK loads  = [get_db $_p .net.loads]"
}
# The two gating elements themselves: adddec's cg_mem (the core arm, gating
# clk_cpu) and hart_tile's cg_tcm_ext (the external arm, gating mclk directly).
catch {
	foreach _n {*cg_tcm_ext* *cg_mem* *cg_flash*} {
		foreach _i [get_db insts $_n] {
			puts "### UNL STATUS ### : gate [get_db $_i .name] cell=[get_db $_i .base_cell.name]"
		}
	}
}
# The external arm's clock, end to end: what launches onto ram0 from the mclk
# side (tx_addr_r / the tx FSM) and what the shadow returns.
catch {report_timing -from [get_db insts *tx_addr_r*] -max_paths 10 \
	> $REPORT_DIR/$BASENAME.tcm_ext_arm.rpt}

################################################################################
# Output Files
################################################################################
write_script > $OUTPUT_DIR/$BASENAME.g
write_hdl    > $OUTPUT_DIR/$BASENAME.v
write_sdc    > $OUTPUT_DIR/$BASENAME.sdc
write_sdf    > $OUTPUT_DIR/$BASENAME.sdf

toc
set total_run_time [getHMS $START_TIME $STOP_TIME]
puts "Genus hart_tile run is complete. Run time $total_run_time"

exit
