################################################################################
#
# Genus TCL script -- MCU_hart, SINGLE-HART HIERARCHICAL TOP (2026-08-24)
#
# WHY THIS BLOCK EXISTS
#   LVS has never MATCHed at MCU or chip level.  The 2026-08-18 penta verdict
#   is a TOP-CELL PORT count mismatch (layout 60 : schematic 54 initial,
#   61 compare), i.e. a top-level assembly defect rather than a tile defect.
#   MCU_hart is the smallest vehicle that still has the same top-level shape:
#   the MCU block assembly, no pad ring, with ONE hardened hart_tile macro
#   instead of four or five.  Everything the chip-level compare exercises --
#   a boxed hcell with an internal switched rail, a boot-ROM macro, the shared
#   RAM macros, the analog component CDLs, virtual-connect labels, the short
#   sentinels -- is present exactly once.
#
# RELATION TO THE OTHER LINEAGES
#   Modelled on genus/MCU_ARGUS/tcl/MCU_ARGUS_hier.genus.tcl (the leanest
#   hierarchical top: tile read as a GATE NETLIST SOURCE, dont_touch/preserve,
#   no orchestrator) with the current-generator handling taken from
#   genus/MCU_PENTA/tcl/MCU_PENTA_hier.genus.tcl (the `=> CORE_` generic strip,
#   the debug_module/jtag_dtm reads, the full wound peripheral read list).
#   NEITHER of those files is touched.  MCU_hart is additive.
#
# WHAT IS DIFFERENT FROM PENTA, deliberately
#   1. NUM_HARTS = 1.  hart0 IS the hardened tile; there is no orchestrator,
#      so no orch_tile netlist is read and no orch_* module names exist.
#   2. The boot ROM entity is `rom2k_hvt_pg` (2048x32, A[10:0]).  The instance
#      is still named rom0 -- the set_false_path below is unchanged from the
#      three older scripts for exactly that reason.  Both ROM libs are loaded
#      so a config staged before the 8 KiB flip still resolves.
#   3. The hardened tile netlist is the CURRENT frozen cut
#      ../hart_tile/out/hart_tile.genus.v (8 KiB TCM, sram1p8k_hvt_pg).
#
# PREREQUISITES, all checked loudly before any work is done:
#   * ../hart_tile/out/hart_tile.genus.v      (frozen; never re-run that block)
#   * ../common/in/hart_hdl/MCU.vhd
#   * ../common/in/hart_hdl/MemoryMap.vhd
#     Stage those two from the single-hart config emit, e.g.
#       make chip CONFIG=platform/common/config/hart.json
#       cp out/hdl/{MCU,MemoryMap}.vhd genus/common/in/hart_hdl/
#     and drop ChipConfig.resolved.json beside them as the provenance record.
#
# Run from the genus dir:  cd genus && make MCU_hart_hier.genus
#
################################################################################

set INPUT_DIR        ../common/in
set IP_DIR           /home/mseminario2/chips/myshkin/ip
set OUTPUT_DIR       out
set REPORT_DIR       rpt
set HDL_DIR          ../../hdl
set SCRIPTS_DIR      tcl

# The staged single-hart generated RTL.  Overridable so a second config can be
# tried without editing this file.
set HART_HDL [expr {[info exists ::env(HART_HDL)] ? $::env(HART_HDL) : "$INPUT_DIR/hart_hdl"}]

set TILE_NETLIST     ../hart_tile/out/hart_tile.genus.v

set TOP_MODULE       MCU
set BASENAME         MCU_hart_hier.genus
set NUM_HARTS        1

set base_freq 		25
set freq_mult 		1
set CLKHFXT_FREQ	[expr $base_freq * $freq_mult]
set CLKLFXT_FREQ	0.032768
set I2CSCL_FREQ		5
set SPISCK_FREQ		$CLKHFXT_FREQ
set FASTEST_FREQ	$CLKHFXT_FREQ
# JTAG TCK: 7 MHz is the ceiling jtag_dtm.vhd states in its own header for the
# dtmcs.idle = 7 setting, so the constraint is the rate the RTL promises.
set TCK_FREQ		7

set CLKHFXT_PERIOD	[expr 1 / [expr $CLKHFXT_FREQ * 0.001]]
set CLKLFXT_PERIOD	[expr 1 / [expr $CLKLFXT_FREQ * 0.001]]
set I2CSCL_PERIOD	[expr 1 / [expr $I2CSCL_FREQ * 0.001]]
set SPISCK_PERIOD	[expr 1 / [expr $SPISCK_FREQ * 0.001]]
set FASTEST_PERIOD	[expr 1 / [expr $FASTEST_FREQ * 0.001]]
set TCK_PERIOD		[expr 1 / [expr $TCK_FREQ * 0.001]]
puts "Target mclk/hfxt period in ns: $FASTEST_PERIOD"

################################################################################
# Procedures
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

# Existence test for a genus db reference (pin:, hpin:, port:, inst:, ...).
# Written with catch because the two failure shapes differ by object class:
# some accessors return empty, some raise, and a raised error inside a -files
# script leaves genus sitting at an interactive prompt while STILL EXITING 0
# (the genus/Makefile wrapper exists for exactly that failure).
proc db_exists {ref} {
	set r ""
	if {[catch { set r [get_db $ref] }]} { return 0 }
	if {$r eq "" || $r eq "0x0"} { return 0 }
	return 1
}

# Apply a false path only when the pin actually exists.  Every optional
# exception in this file is guarded rather than hopeful.
proc fp_to_pin_if_present {p} {
	if {![db_exists pin:$p]} {
		puts "### UNL STATUS ### : SKIPPED false_path, no pin $p"
		return 0
	}
	if {[catch { set_false_path -to pin:$p } __e]} {
		puts "### UNL STATUS ### : SKIPPED false_path pin:$p ($__e)"
		return 0
	}
	puts "### UNL STATUS ### : false_path -to pin:$p"
	return 1
}

################################################################################
# Root Attributes
################################################################################
tic
set_db information_level 3

# hart_tile and the analog blocks (dco/por/glitch filter) elaborate as
# blackboxes.  That is the point of a hierarchical top.
set_db hdl_error_on_blackbox false

# Keep blackbox module names plain: the default naming style appends generic
# values, and the tile netlist / LEF / ETM all carry the plain name.
set_db hdl_parameter_naming_style ""

set_db init_lib_search_path [list \
	$IP_DIR/rom2k_hvt_pg \
	$IP_DIR/rom_hvt_pg \
	$IP_DIR/sram1p16k_hvt_pg \
	$IP_DIR/sram1p8k_hvt_pg \
	$INPUT_DIR/ \
	/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10/ecsm-timing/ \
	/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10-pmk/synopsys/ ]

set_db init_hdl_search_path [list \
	$HDL_DIR ]

# BOTH ROM libs and BOTH SRAM libs are loaded and they are not alternatives.
#   rom2k_hvt_pg    the 8 KiB boot ROM the current generator emits
#   rom_hvt_pg      the 16 KiB plate, kept so a pre-flip staged MCU.vhd resolves
#   sram1p16k       the shared bulk banks / NPU staging RAM at the top level
#   sram1p8k        the PRIVATE TCM inside the hart_tile gate netlist
# The pmk NLDM is needed because the tile netlist read as source below contains
# HEADBUF16MA10TH power switches.
set_db library [list \
	rom2k_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib \
	rom_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib \
	sram1p16k_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib \
	sram1p8k_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib \
	scadv10_cln65gp_hvt_tt_1p0v_25c.lib \
	scadv10pmk_tsmc65gp_hvt_tt_1p0v_25c.lib]

set_db tns_opto true
set_db auto_ungroup none
set_db lp_insert_clock_gating true
set_db lp_clock_gating_register_aware true

set_dont_use TIEHIX1MA10TH false
set_dont_use TIELOX1MA10TH false
set_db use_tiehilo_for_const duplicate

################################################################################
# Prerequisite checks -- loud, before any work
################################################################################
foreach f [list $TILE_NETLIST $HART_HDL/MCU.vhd $HART_HDL/MemoryMap.vhd] {
	if {![file exists $f]} {
		puts "FATAL: missing input $f (see the PREREQUISITES block in this header)"
		exit 1
	}
}

# Read the debug polarity out of the STAGED MemoryMap.vhd rather than assuming
# it, so the TCK constraint below can never disagree with the RTL being built.
set CORE_DEBUG_ON 0
if {[catch {
	set __fh [open $HART_HDL/MemoryMap.vhd r]
	set __mm [read $__fh]
	close $__fh
	if {[regexp {CORE_ENABLE_DEBUG\s*:\s*boolean\s*:=\s*true} $__mm]} { set CORE_DEBUG_ON 1 }
} __e]} {
	puts "FATAL: cannot read $HART_HDL/MemoryMap.vhd to determine the debug polarity: $__e"
	exit 1
}
puts "### UNL STATUS ### : staged build is debug-[expr {$CORE_DEBUG_ON ? {ON} : {OFF}}]"

# Which ROM entity did the generator actually emit?  This decides nothing in
# this script (the instance is rom0 either way) but a wrong answer here means
# the LVS include is missing a CDL, which is the 2026-08-16 NVN-13010 abort.
set ROM_ENTITY "unknown"
if {[catch {
	set __fh [open $HART_HDL/MCU.vhd r]
	set __mv [read $__fh]
	close $__fh
	if {[regexp {rom0\s*:\s*entity\s+work\.(rom[0-9a-zA-Z_]*)} $__mv -> __re]} { set ROM_ENTITY $__re }
} __e]} { }
puts "### UNL STATUS ### : staged boot ROM entity = $ROM_ENTITY  (LVS include MUST carry its CDL)"

################################################################################
# Read HDL (MCU top MINUS the hart: no vesta, no adddec, no hart_tile RTL)
################################################################################
puts "Reading HDL (single-hart MCU top; hart_tile as a gate source)"
set MP $HDL_DIR/common

# --- Commune / shared packages and cells ---
# VHDL sources use 2008 delimited comments, and genus refuses to mix versions
# in one session (HPT-88), so 2008 is set once here for everything.
set_db hdl_vhdl_read_version 2008
read_hdl -vhdl -library work $MP/commune/fixed_float_types_c.vhdl
read_hdl -vhdl -library work $MP/commune/fixed_pkg_c.vhdl
read_hdl -vhdl -library work $MP/commune/FPMac.vhd
read_hdl -vhdl -library work $MP/commune/FPSigmoid.vhd
read_hdl -vhdl -library work $MP/commune/TieLow.vhd
read_hdl -vhdl -library work $MP/constants.vhd
read_hdl -vhdl -library work $MP/macros/macros.vhd
# The STAGED single-hart MemoryMap, not hdl/common/MemoryMap.vhd.
read_hdl -vhdl -library work $HART_HDL/MemoryMap.vhd
read_hdl -vhdl -library work $MP/commune/ClkGate_cmn65gp_ARM.vhd
read_hdl -vhdl -library work $MP/commune/ClockMuxGlitchFree_cmn65gp_ARM.vhd
read_hdl -vhdl -library work $MP/commune/CRC16.vhd
read_hdl -vhdl -library work $MP/commune/ClkDivPower2.vhd

# --- Peripherals.  The SUPERSET is read on purpose: an unread peripheral is
#     silently BLACKBOXED, and the only loud symptom is a gate-sim CUVMUR much
#     later.  Reading an entity the staged config does not instantiate costs
#     nothing (auto_ungroup none, unreferenced modules are dropped at
#     elaborate) and makes this script config-agnostic. ---
#
#     ONE EXCEPTION, and it is CONFIG-DRIVEN rather than a list of names.
#     A peripheral whose registers the staged MemoryMap does not declare cannot
#     be ANALYZED at all: the entity references constants that do not exist, so
#     read_hdl raises VHDLPT-766 and the whole session dies at that read.
#     MEASURED on the first MCU_hart run, 2026-08-24: peripherals.npu = false
#     emits a MemoryMap with no MmrAddrNPU* constants, and NPU.vhd raised 18
#     errors on lines 346..846 and aborted the script before QSPI.vhd was ever
#     reached.  This is the same file, and the same reason, that
#     opensource_sim/mcu_hart/defs.bzl drops from the bazel analysis order.
#
#     The guard below is DERIVED, not a hard-coded NPU special case: it reads
#     the constant names the staged MemoryMap actually declares, and skips any
#     peripheral source that references one it does not.  Measured over the
#     whole tree, `MmrAddr*` is the only such constant family and the NPU is
#     its only user, so today this skips NPU.vhd and nothing else -- but a
#     future config-gated block gets the same treatment without editing here.
#     A SKIP IS ANNOUNCED, because a silently unread peripheral is exactly the
#     blackbox failure the paragraph above warns about.
set MMAP_DECLARED [dict create]
if {[catch { set _fh [open $HART_HDL/MemoryMap.vhd r] } _e]} {
	puts "### UNL FATAL ### : cannot open staged MemoryMap.vhd: $_e"
	exit 1
}
foreach _c [regexp -all -inline {MmrAddr[A-Za-z0-9_]+} [read $_fh]] {
	dict set MMAP_DECLARED $_c 1
}
close $_fh
puts "### UNL STATUS ### : staged MemoryMap declares [dict size $MMAP_DECLARED] MmrAddr* constant(s)"

# Read a peripheral source only if every MmrAddr* constant it references is
# declared by the staged MemoryMap.  Returns 1 if read, 0 if skipped.
proc read_periph_if_mapped {path} {
	global MMAP_DECLARED
	set fh [open $path r]
	set txt [read $fh]
	close $fh
	set missing {}
	foreach c [regexp -all -inline {MmrAddr[A-Za-z0-9_]+} $txt] {
		if {![dict exists $MMAP_DECLARED $c]} { lappend missing $c }
	}
	set missing [lsort -unique $missing]
	if {[llength $missing] > 0} {
		puts "### UNL STATUS ### : SKIPPED [file tail $path] -- staged MemoryMap declares none of: [join $missing { }]"
		puts "### UNL STATUS ### :   (this peripheral is OFF in the staged configuration; its entity would not analyze)"
		return 0
	}
	read_hdl -vhdl -library work $path
	return 1
}

read_periph_if_mapped $MP/periph/GPIO.vhd
read_periph_if_mapped $MP/periph/SPI.vhd
read_periph_if_mapped $MP/periph/UART.vhd
read_periph_if_mapped $MP/periph/I2C.vhd
read_periph_if_mapped $MP/periph/TIMER.vhd
read_periph_if_mapped $MP/periph/SYSTEM.vhd
read_periph_if_mapped $MP/periph/NPU.vhd
read_periph_if_mapped $MP/periph/QSPI.vhd
read_periph_if_mapped $MP/periph/I3C.vhd
read_periph_if_mapped $MP/periph/NFC.vhd
read_periph_if_mapped $MP/periph/RTC.vhd
read_periph_if_mapped $MP/periph/PWM.vhd
read_periph_if_mapped $MP/periph/OneWire.vhd
read_periph_if_mapped $MP/periph/DMA.vhd
read_periph_if_mapped $MP/periph/I2CTarget.vhd
read_periph_if_mapped $MP/periph/TrngRoEnsemble.vhd
read_periph_if_mapped $MP/periph/TRNG.vhd
read_periph_if_mapped $MP/periph/EVFAB.vhd

# --- Debug transport: assembly level, one per chip.  dm0/dtm0 sit BESIDE the
#     hart, never inside a hart_tile (TCK must reach the transport while the
#     hart is power gated).  Omitting these reads costs ~40 minutes of Innovus
#     before ccopt_design refuses to run (IMPCCOPT-1349/2196). ---
read_hdl -vhdl -library work $MP/debug_module.vhd
read_hdl -vhdl -library work $MP/jtag_dtm.vhd

# --- Multi-core infrastructure.  Present even at N=1: the generated MCU.vhd
#     still instantiates the arbiter/CLINT/router/mutex/resv/pwr_ctrl fabric,
#     just at width 1. ---
read_hdl -vhdl -library work $MP/clint.vhd
read_hdl -vhdl -library work $MP/irq_router.vhd
read_hdl -vhdl -library work $MP/mp_arbiter.vhd
read_hdl -vhdl -library work $MP/mutex_bank.vhd
read_hdl -vhdl -library work $MP/pwr_ctrl.vhd
read_hdl -vhdl -library work $MP/resv_unit.vhd
read_hdl -vhdl -library work $MP/afe_stub.vhd

# --- The tile: its HARDENED GATE NETLIST, read as source ---------------------
# MCU.vhd instantiates the tile by DIRECT ENTITY INSTANTIATION
# (entity work.hart_tile), which genus cannot blackbox from a port map alone
# (CDFG-254) and cannot bind to an entity without an architecture (CDFG-321).
# So the tile-only run's gate netlist is read as SOURCE and then frozen with
# dont_touch/preserve.  The generic map in MCU.vhd passes parameters that a
# verilog module does not have (CDFG-214), so matching DUMMY parameters are
# injected into a GENERATED COPY of the header -- the tile-only outputs stay
# pristine.  Values must equal the one real configuration the tile was
# synthesized with.
#
# SH_AW: memory map v2 synthesizes the tile at 16.  It is read back out of the
# staged MemoryMap.vhd when that is possible, because a stale literal here is a
# silent one-bit-narrow lie (the CPR6/R3 lesson).
set TILE_SH_AW 16
if {[regexp {SH_AW\s*:\s*(?:natural|integer)\s*:=\s*([0-9]+)} $__mm -> __shaw]} {
	set TILE_SH_AW $__shaw
}
puts "### UNL STATUS ### : tile dummy SH_AW = $TILE_SH_AW"

exec bash -c "mkdir -p $INPUT_DIR && awk '
	/^module hart_tile\\(/ { inhdr=1 }
	{ print }
	inhdr && /\\);\$/ { print \"  parameter PC_RST_VAL = 32'\\''h00000000;\"; print \"  parameter SH_AW = $TILE_SH_AW;\"; print \"  parameter ENABLE_MUL = 1;\"; print \"  parameter ENABLE_DIV = 1;\"; print \"  parameter ENABLE_ATOMICS = 1;\"; print \"  parameter ENABLE_COMPRESSED = 1;\"; print \"  parameter ENABLE_BITMANIP = 1;\"; inhdr=0 }
' $TILE_NETLIST > $INPUT_DIR/hart_tile_hart_top.gen.v"
read_hdl $INPUT_DIR/hart_tile_hart_top.gen.v

# --- Top level ---------------------------------------------------------------
# genus 19 cannot bind a VHDL BOOLEAN generic to a verilog parameter (CDFG-200),
# so this flow reads a GENERATED COPY of the staged MCU.vhd with every
# `=> CORE_...` association stripped from the hart generic map.  They fall back
# to the entity defaults, which are exactly the values the tile netlist was
# synthesized with.  The strip is `=> CORE_` and NOT `=> CORE_ENABLE_`: the
# current generator emits PMP_ENTRIES => CORE_PMP_ENTRIES too, and leaving that
# one in strands a trailing comma on the last surviving association.
# The SH_AW line then loses its now-trailing comma.  The staged MCU.vhd itself
# stays pristine -- it is the make-chip product.
exec bash -c "sed -e '/=> CORE_/d' \
	-e 's/SH_AW          => SH_AW,/SH_AW          => SH_AW/' \
	$HART_HDL/MCU.vhd > $INPUT_DIR/MCU_hart_top.gen.vhd"
read_hdl -vhdl -library work $INPUT_DIR/MCU_hart_top.gen.vhd

################################################################################
# Elaboration
################################################################################
puts "Elaborating $TOP_MODULE"
elaborate $TOP_MODULE

# Per-MODULE boundary_opto disable: the root attribute is ignored (M9b).
set_db [get_db modules] .boundary_opto false
puts "boundary_opto disabled on [llength [get_db modules]] modules"

# The hardened tile is UNTOUCHABLE: one module, one instance, zero genus edits.
foreach tm [get_db modules -if {.name == hart_tile}] {
	catch { set_db $tm .dont_touch true }
	catch { set_db $tm .preserve true }
	puts "tile module preserved: [get_db $tm .name]"
}
for {set h 0} {$h < $NUM_HARTS} {incr h} {
	catch { set_db inst:$TOP_MODULE/hart$h .preserve true }
}

# BLACKBOX CENSUS.  At this point the only undefined cells may be the analog
# components: por, dco0/dco1, irq_gf*.  Anything else is a MISSING read_hdl,
# which is silent here and detonates at gate sim or at Innovus CTS.
set __bb {}
foreach __i [get_db insts] {
	set __c ""
	catch { set __c [get_db $__i .module.name] }
	if {$__c eq ""} { lappend __bb [get_db $__i .name] }
}
puts "### UNL STATUS ### : blackbox census -- [llength $__bb] undefined instances"
foreach __b $__bb { puts "### UNL STATUS ### :   blackbox $__b" }

################################################################################
# Constraints
################################################################################

# --- Clocks generated inside system0 (control plane) ---
create_clock -name mclk			-domain mclk_domain			-period $FASTEST_PERIOD	hpin:$TOP_MODULE/system0/mclk_out
create_clock -name smclk		-domain smclk_domain		-period $FASTEST_PERIOD	hpin:$TOP_MODULE/system0/smclk_out
create_clock -name clk_lfxt		-domain clk_lfxt_domain		-period $CLKLFXT_PERIOD	hpin:$TOP_MODULE/system0/clk_lfxt_out
create_clock -name clk_hfxt		-domain clk_hfxt_domain		-period $CLKHFXT_PERIOD	hpin:$TOP_MODULE/system0/clk_hfxt_out

# --- NO clk_cpu0 clock: that hpin lives inside the hardened tile and is
#     constrained by the tile's own SDC (the M9c fix). ---

# --- hart0's XIP flash memory clock: a gated mclk that EXITS the tile at
#     flash_clk_mem and clocks spi0's flash-side logic.  Same waveform, same
#     domain (it IS mclk, gated). ---
if {[db_exists hpin:$TOP_MODULE/hart0/flash_clk_mem]} {
	create_generated_clock -name flash_clk_mem -divide_by 1 \
		-source hpin:$TOP_MODULE/system0/mclk_out -domain mclk_domain \
		hpin:$TOP_MODULE/hart0/flash_clk_mem
	puts "### UNL STATUS ### : flash_clk_mem generated clock created at hart0"
} else {
	puts "### UNL STATUS ### : no hart0/flash_clk_mem hpin -- generated clock SKIPPED"
}

# --- JTAG TCK, when the staged build is debug-ON ---
if {$CORE_DEBUG_ON} {
	if {[db_exists port:$TOP_MODULE/TCK]} {
		create_clock -name tck -domain tck_domain -period $TCK_PERIOD port:$TOP_MODULE/TCK
		puts "### UNL STATUS ### : TCK clock at $TCK_FREQ MHz"
	} else {
		puts "### UNL STATUS ### : debug is ON but there is no TCK port -- check the staged MCU.vhd"
	}
}

# --- Peripheral source clocks, each guarded (the staged config decides which
#     peripheral instances exist). ---
proc clk_on_hpin_if_present {name domain period hp} {
	if {![db_exists hpin:$hp]} {
		puts "### UNL STATUS ### : no hpin $hp -- clock $name SKIPPED"
		return 0
	}
	if {[catch { create_clock -name $name -domain $domain -period $period hpin:$hp } __e]} {
		puts "### UNL STATUS ### : clock $name SKIPPED at $hp ($__e)"
		return 0
	}
	return 1
}
set ACTIVE_CLKS {mclk smclk clk_lfxt clk_hfxt}
if {[clk_on_hpin_if_present clk_scl0 clk_scl0_domain $I2CSCL_PERIOD $TOP_MODULE/i2c0/SCL_IN]} { lappend ACTIVE_CLKS clk_scl0 }
if {[clk_on_hpin_if_present clk_scl1 clk_scl1_domain $I2CSCL_PERIOD $TOP_MODULE/i2c1/SCL_IN]} { lappend ACTIVE_CLKS clk_scl1 }
if {[clk_on_hpin_if_present clk_sck0 clk_sck0_domain $SPISCK_PERIOD $TOP_MODULE/spi0/sck_in]}  { lappend ACTIVE_CLKS clk_sck0 }
if {[clk_on_hpin_if_present clk_sck1 clk_sck1_domain $SPISCK_PERIOD $TOP_MODULE/spi1/sck_in]}  { lappend ACTIVE_CLKS clk_sck1 }
if {$CORE_DEBUG_ON && [db_exists port:$TOP_MODULE/TCK]} { lappend ACTIVE_CLKS tck }

# --- Cost groups / path groups, one per clock that actually exists ---
foreach c $ACTIVE_CLKS {
	define_cost_group -name ${c}_group -weight 1
	path_group -from $c -group ${c}_group
}
puts "### UNL STATUS ### : path groups for [llength $ACTIVE_CLKS] clocks: $ACTIVE_CLKS"

# --- PGEN powered-down-macro exceptions ---
# The ROM instance is rom0 whether the entity is rom_hvt_pg or rom2k_hvt_pg;
# the entity moved, the instance name did not.
fp_to_pin_if_present $TOP_MODULE/rom0/PGEN
# Shared bulk RAM banks and the NPU staging RAM, all guarded.
for {set b 0} {$b < 8} {incr b} {
	fp_to_pin_if_present $TOP_MODULE/shbank$b/PGEN
}
fp_to_pin_if_present $TOP_MODULE/npuram0/PGEN
# The tile netlist is loaded as source here, so hart0's TCM PGEN/RETN pins are
# visible and need the same exception the flat flow gave them.
fp_to_pin_if_present $TOP_MODULE/hart0/ram0/PGEN
fp_to_pin_if_present $TOP_MODULE/hart0/ram0/RETN

################################################################################
# Top Design Attributes
################################################################################
set_max_transition 0.5
set_load 0.600 [get_ports -filter "direction==out"]
set_driving_cell -lib_cell INVX1MA10TH [get_ports -filter "direction==in"]

################################################################################
# Synthesis -- TIME-OPTIMIZED, AREA-RELAXED
################################################################################
puts "Synthesizing MCU_hart (single-hart hierarchical top)"
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

################################################################################
# Output Files
################################################################################
write_script > $OUTPUT_DIR/$BASENAME.g
write_hdl    > $OUTPUT_DIR/$BASENAME.v
write_sdc    > $OUTPUT_DIR/$BASENAME.sdc
write_sdf    > $OUTPUT_DIR/$BASENAME.sdf

toc
set total_run_time [getHMS $START_TIME $STOP_TIME]
puts "Genus MCU_hart_hier run is complete. Run time $total_run_time"

exit
