################################################################################
#
# Genus TCL script -- CASTALIA-PENTA WOUND SoC, MCU HIERARCHICAL TOP (CP4a)
#
# = tcl/../../MCU_WOUND/tcl/MCU_WOUND_hier.genus.tcl (the 4-hart tape-out
#   hierarchical wound top, 2026-07-26) with the CP1 penta deltas folded in.
#   THAT FILE IS NOT TOUCHED -- it stays the reference cut.
#
# CPR6 RENUMBER (2026-08-15) -- THIS FILE WAS INVERTED. The CPR3 generator
# emits hart0 = orch_tile (the soft orchestrator, carrying the flash/XIP
# quartet + sleep + trap + a0) and hart1..hart4 = hart_tile (the hardened
# corner macros). Everything index-bearing below moved with it: the preserve
# loop, the per-instance clk_cpu generated clock (now clk_cpu0), the
# flash_clk_mem source (now the ORCHESTRATOR's port, since the flash quartet
# is hart 0's and hart 0 IS the orchestrator), and the TCM PGEN/RETN
# exceptions. The dummy SH_AW parameter injected into both gate netlists moved
# 15 -> 16 with memory map v2 (R3): both netlists are now SYNTHESIZED at
# SH_AW=16 and a stale 15 here is a silent one-bit-narrow lie.
#
# WHAT THIS BUILDS
#   The wound SoC top with FIVE harts:
#     * hart1..hart4 -> `hart_tile`, the HARDENED corner macro. Read as a gate
#       netlist source, dont_touch/preserve, LEF+ETM downstream. Unchanged.
#     * hart0        -> `orch_tile`, the SOFT always-on orchestrator (CP1 D6).
#       Also read as a gate netlist source -- but from genus/orch_tile, and
#       from its RENAMED product (out/orch_tile.renamed.v) whose module names
#       are `orch_`-prefixed so that NO module name is shared with the tile
#       netlist. That disjointness is what lets the strip script delete the
#       tile subtree from the flat P&R netlist while KEEPING the orchestrator's.
#
# THE FIVE PENTA DELTAS vs MCU_WOUND_hier (each marked `# PENTA-DELTA n` below)
#   1. WOUND_HDL -> ../common/in/penta_wound_hdl (config/penta_wound.json:
#      the wound peripheral set + numHarts 5 + orchestrator=true, the CPR3
#      renumber; `managementHart` was RETIRED from the schema at CPR1/R1).
#   2. The orchestrator netlist is read as a second gate source, with the same
#      dummy-parameter injection the tile gets (MCU.vhd passes PC_RST_VAL/SH_AW
#      to it; verilog modules have no parameters -> CDFG-214).
#   3. The MCU.vhd generic-strip sed drops `=> CORE_` (not just
#      `=> CORE_ENABLE_`): the CURRENT generator emits 25 associations per hart
#      including `PMP_ENTRIES => CORE_PMP_ENTRIES`, which the July-2026 wound
#      sed did not have to handle. Leaving it in strands a trailing comma on the
#      last surviving association and elaboration dies. All stripped generics
#      fall back to entity defaults, and those defaults are EXACTLY the values
#      the staged MemoryMap.vhd carries (verified CP4a: MUL/DIV/ATOMICS/
#      COMPRESSED/BITMANIP/TRAPCSR true, all X-series + UMODE/PMP/DEBUG false,
#      PMP_ENTRIES 16) -- i.e. the configuration both gate netlists were
#      synthesized with.
#   4. hart0 (the orchestrator) gets its own generated clk_cpu clock + cost/path group at THIS
#      level. The four tiles' clk_cpu hpins are inside a hardened macro and are
#      constrained by the tile's own SDC (M9c); the orchestrator's are NOT --
#      it is soft logic that Innovus will place and CTS in the centre band, so
#      its gated core clock must exist in the SDC this flow hands downstream.
#      The hpin path is DERIVED and CHECKED, never assumed (see PENTA-DELTA 4).
#   5. hart0's TCM PGEN/RETN false paths, at the orchestrator's own path.
#
# Everything else -- the wound peripheral read list, the qspi0/i3c0 baud
# generated clocks, the three EnMemPeriph negedge pre-latch clocks, i3c0 SDA_IN,
# nfc0 rf_clk, rtc0 lfxt_in, the cost/path groups, the SCL_IN->SDA_IN false
# path, the TRNG0 ring-oscillator preserve block + its 210-cell FATAL census,
# and the Genus-19.15 degenerate-clock power workaround -- is carried VERBATIM.
# Read the MCU_WOUND_hier header for the provenance of each.
#
# Run from the block dir:  cd genus && make MCU_PENTA_hier.genus
# PREREQUISITES (both are checked at the top of the read stage):
#   make hart_tile.genus                     (frozen -- do NOT re-run)
#   make orch_tile.genus && ./orch_tile/rename_orch_modules.sh
#   make chip CONFIG=config/penta_wound.json + stage MCU.vhd/MemoryMap.vhd
#     into ../common/in/penta_wound_hdl/
#
################################################################################

set INPUT_DIR        ../common/in
set IP_DIR           /home/mseminario2/chips/myshkin/ip
set IC_DIR           ../../ic
set OUTPUT_DIR       out
set REPORT_DIR       rpt
set HDL_DIR          ../../hdl
set SCRIPTS_DIR      tcl

# PENTA-DELTA 1: the staged penta-wound generated RTL (MemoryMap.vhd + MCU.vhd
# from config/penta_wound.json). Staged INSIDE genus/common/in so the whole
# synthesis input set is under one tree; ChipConfig.resolved.json is staged
# beside them as the provenance record.
set PENTA_HDL        $INPUT_DIR/penta_wound_hdl

# Is this a debug-ON build? Read it out of the STAGED MemoryMap.vhd rather than
# assuming, so the TCK guard below can never disagree with the RTL actually
# being synthesised. (CORE_ENABLE_DEBUG is what MCU.vhd passes to every tile and
# what gates the dm0/dtm0 emission.)
set CORE_DEBUG_ON 0
if {[catch {
	set __fh [open $PENTA_HDL/MemoryMap.vhd r]
	set __mm [read $__fh]
	close $__fh
	if {[regexp {CORE_ENABLE_DEBUG\s*:\s*boolean\s*:=\s*true} $__mm]} { set CORE_DEBUG_ON 1 }
} __e]} {
	puts "FATAL: cannot read $PENTA_HDL/MemoryMap.vhd to determine the debug polarity: $__e"
	exit 1
}
puts "### UNL STATUS ### : staged build is debug-[expr {$CORE_DEBUG_ON ? {ON} : {OFF}}]"

# The two gate-netlist sources.
set TILE_NETLIST     ../hart_tile/out/hart_tile.genus.v
set ORCH_NETLIST     ../orch_tile/out/orch_tile.renamed.v

set TOP_MODULE       MCU
set BASENAME         MCU_PENTA_hier.genus

# Hardened tiles only, and after the CPR6 renumber they are the CONTIGUOUS
# RANGE hart1..hart4 -- never a 0-based count. The orchestrator is hart0 and is
# counted separately everywhere: different module, different power/clock story.
set NUM_HARTS        4
set TILE_HART_LO     1
set TILE_HART_HI     4
set ORCH_HART        0
# Instance name of the hart_tile inside orch_tile (orch_tile.vhd: `tile : ...`).
set ORCH_TILE_INST   tile
# CPR6/R3: memory map v2 -- both gate netlists are synthesized at SH_AW = 16.
set PENTA_SH_AW      16

set base_freq 		25
set freq_mult 		1
set CLKHFXT_FREQ	[expr $base_freq * $freq_mult]
set CLKLFXT_FREQ	0.032768
set I2CSCL_FREQ		5
set SPISCK_FREQ		$CLKHFXT_FREQ
set FASTEST_FREQ	$CLKHFXT_FREQ
# JTAG TCK (2026-08-16). 7 MHz is not a guess: jtag_dtm.vhd states the
# functional ceiling in its own header -- "dtmcs.idle [14:12], in TCK cycles:
# 7 covers the worst DMI latency as long as TCK stays at or below about
# 7 MHz" -- so the timing constraint is set to the rate the RTL promises
# rather than to a round number that would over- or under-sell the TAP.
set TCK_FREQ		7

puts "Target CLKHFXT frequency in MHz: $CLKHFXT_FREQ"
puts "Target CLKLFXT frequency in MHz: $CLKLFXT_FREQ"
puts "Target I2CSCL frequency in MHz: $I2CSCL_FREQ"
puts "Target SPISCK frequency in MHz: $SPISCK_FREQ"
puts "Target maximum frequency in MHz: $FASTEST_FREQ"

set CLKHFXT_PERIOD	[expr 1 / [expr $CLKHFXT_FREQ * 0.001]]
set CLKLFXT_PERIOD	[expr 1 / [expr $CLKLFXT_FREQ * 0.001]]
set I2CSCL_PERIOD	[expr 1 / [expr $I2CSCL_FREQ * 0.001]]
set SPISCK_PERIOD	[expr 1 / [expr $SPISCK_FREQ * 0.001]]
set FASTEST_PERIOD	[expr 1 / [expr $FASTEST_FREQ * 0.001]]
set TCK_PERIOD		[expr 1 / [expr $TCK_FREQ * 0.001]]

puts "Target minimum period in ns: $FASTEST_PERIOD"

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
	set s $s_rem
	set hms [format "%02d:%02d:%02d" $h $m $s]
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

# hart_tile / orch_tile (and the analog blocks dco0/irq_gf0/por) elaborate as
# blackboxes -- that is the point of this script.
set_db hdl_error_on_blackbox false

# Keep the blackbox module names plain (default naming appends the generic
# values). Both gate netlists and every downstream consumer carry plain names.
set_db hdl_parameter_naming_style ""

set_db init_lib_search_path [list \
	$IP_DIR/rom_hvt_pg \
	$IP_DIR/sram1p16k_hvt_pg \
	$IP_DIR/sram1p8k_hvt_pg \
	$INPUT_DIR/ \
	/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10/ecsm-timing/ \
	/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10-pmk/synopsys/ ]

set_db init_hdl_search_path [list \
	$HDL_DIR ]

# 2026-08-16: BOTH SRAM macros are needed at the assembly level and they are
# not alternatives -- the 16 KiB macro is the SHARED fabric (4 bulk RAM banks
# from 0x10000 + the NPU staging RAM), the 8 KiB macro is the PRIVATE TCM
# inside each hart_tile/orch_tile netlist. Dropping either leaves unresolved
# macro instances at the tile boundary.
set_db library [list \
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
foreach f [list $TILE_NETLIST $ORCH_NETLIST $PENTA_HDL/MCU.vhd $PENTA_HDL/MemoryMap.vhd] {
	if {![file exists $f]} {
		puts "FATAL: missing input $f (see the PREREQUISITES block in this script's header)"
		exit 1
	}
}

################################################################################
# Read HDL (wound MCU top MINUS the harts: no vesta, no adddec, no hart_tile,
# no orch_tile RTL -- both hart bodies enter as gate netlists)
################################################################################
puts "Reading HDL (penta-wound MCU top; hart_tile + orch_tile as gate sources)"

set MP $HDL_DIR/common

# --- Commune / shared packages and cells ---
# VHDL sources use 2008 delimited comments
# BLOCKED -- READ THIS BEFORE TOUCHING THE READ ORDER (2026-08-17).
# This flow currently ABORTS during read_hdl, and it is PRE-EXISTING breakage,
# not the 8 KiB / asymmetric-ISA work. Proven three ways: the pre-2026-08-16
# script, and the CPR-era tcl/MCU_PENTA_hier.genus.cp5.tcl.bak that produced the
# last good netlist (out/, dated 2026-08-15), BOTH abort here on today's RTL.
#
# THE VICE, and it closes from both sides:
#   * fixed_float_types_c / fixed_pkg_c are the `_c` = COMPATIBILITY (VHDL-93)
#     forms. Read as 2008 they self-reject: their "IN VHDL-2006
#     std_logic_vector is a subtype of std_ulogic_vector" overload blocks become
#     EXACT DUPLICATES (2008 makes slv a subtype of sulv), so the parser reports
#     20 errors, does not store package fixed_pkg, and genus aborts.
#   * FPMac.vhd / FPSigmoid.vhd carry /* */ DELIMITED COMMENTS since the 2026-08
#     comment-style cleanup commits, and so REQUIRE 2008. Read as 93 the parser
#     walks into the comment text (FPSigmoid.vhd line 17 col 72 is inside a
#     /* */ block) and aborts too.
#   * The generated MCU.vhd also uses /* */, so 2008 is not optional here.
#   * Reading the package as 93 and the rest as 2008 IS NOT POSSIBLE:
#     "Error: Cannot mix VHDL 2008 files with previous VHDL versions. [HPT-88]".
#
# THE FIX is in the RTL, not in this script: delete the two VHDL-2006
# compatibility overload blocks from hdl/common/commune/fixed_pkg_c.vhdl (the
# declarations at ~1484-1521 and the matching bodies from ~9020). They are
# redundant under 2008 -- the RTL's to_sfixed(slv, ...) calls resolve to the
# std_ulogic_vector versions -- and that package is SHARED by the NPU, MCU_MP,
# MCU_DP and MCU_ARGUS flows, which set 2008 before it and are broken the same
# way. Left for a decision because it edits an IEEE-derived package.
#
# The order below is the one the sibling flows use (genus/NPU, genus/MCU_MP):
# 2008 first, then everything. It is kept so this script stays consistent with
# them and is correct the moment the package is fixed.
set_db hdl_vhdl_read_version 2008
read_hdl -vhdl -library work $MP/commune/fixed_float_types_c.vhdl
read_hdl -vhdl -library work $MP/commune/fixed_pkg_c.vhdl
read_hdl -vhdl -library work $MP/commune/FPMac.vhd
read_hdl -vhdl -library work $MP/commune/FPSigmoid.vhd
read_hdl -vhdl -library work $MP/commune/TieLow.vhd
read_hdl -vhdl -library work $MP/constants.vhd
read_hdl -vhdl -library work $MP/macros/macros.vhd
# PENTA-DELTA 1: the penta-wound MemoryMap (5 harts -> MW=3, CLINT layout
# shifted per CP1 D7, plus every wound digperiph vector/address).
read_hdl -vhdl -library work $PENTA_HDL/MemoryMap.vhd
read_hdl -vhdl -library work $MP/commune/ClkGate_cmn65gp_ARM.vhd
read_hdl -vhdl -library work $MP/commune/ClockMuxGlitchFree_cmn65gp_ARM.vhd
read_hdl -vhdl -library work $MP/commune/CRC16.vhd
read_hdl -vhdl -library work $MP/commune/ClkDivPower2.vhd

# --- Peripherals (the wound read list, verbatim; a MISSING read silently
#     BLACKBOXES the instance and only the gate sim's xmelab CUVMUR is loud.
#     The blackbox census at the end must stay EXACTLY dco0 / irq_gf0 / por.) ---
read_hdl -vhdl -library work $MP/periph/GPIO.vhd
read_hdl -vhdl -library work $MP/periph/SPI.vhd
read_hdl -vhdl -library work $MP/periph/UART.vhd
read_hdl -vhdl -library work $MP/periph/I2C.vhd
read_hdl -vhdl -library work $MP/periph/TIMER.vhd
read_hdl -vhdl -library work $MP/periph/SYSTEM.vhd
read_hdl -vhdl -library work $MP/periph/NPU.vhd
read_hdl -vhdl -library work $MP/periph/QSPI.vhd
read_hdl -vhdl -library work $MP/periph/I3C.vhd
read_hdl -vhdl -library work $MP/periph/NFC.vhd
read_hdl -vhdl -library work $MP/periph/RTC.vhd
read_hdl -vhdl -library work $MP/periph/PWM.vhd
read_hdl -vhdl -library work $MP/periph/OneWire.vhd
read_hdl -vhdl -library work $MP/periph/DMA.vhd
read_hdl -vhdl -library work $MP/periph/I2CTarget.vhd
read_hdl -vhdl -library work $MP/periph/TrngRoEnsemble.vhd
read_hdl -vhdl -library work $MP/periph/TRNG.vhd
read_hdl -vhdl -library work $MP/periph/EVFAB.vhd

# --- Debug transport (D2/D3): assembly-level, one per chip -------------------
# THESE WERE MISSING ENTIRELY and the omission was silent. MCU.vhd instantiates
# dm0 (debug_module) and dtm0 (jtag_dtm) whenever debug.enable is set, but this
# script never read either, so genus synthesized them as UNDEFINED BLACK BOXES
# and said so only in passing ("Found 1 module instances of undefined cell
# debug_module"). The assembly netlist then reached Innovus with a hole in it,
# and CTS is where it detonated: mclk fans into dm0, so ccopt_design refused to
# run at all -- "Clock tree mclk connects to 2 module(s) without definitions in
# the netlist" (IMPCCOPT-1349) -> "Cannot run ccopt_design because the command
# prerequisites were not met" (IMPCCOPT-2196), ~40 minutes into the chip run.
# They are MCU-level blocks, NOT tile logic: dm0/dtm0 sit beside the harts and
# must never be inside a hart_tile (TCK has to reach the transport while any
# hart is power-gated).
read_hdl -vhdl -library work $MP/debug_module.vhd
read_hdl -vhdl -library work $MP/jtag_dtm.vhd

# --- Multi-core infrastructure (control plane only) ---
read_hdl -vhdl -library work $MP/clint.vhd
read_hdl -vhdl -library work $MP/irq_router.vhd
read_hdl -vhdl -library work $MP/mp_arbiter.vhd
read_hdl -vhdl -library work $MP/mutex_bank.vhd
read_hdl -vhdl -library work $MP/pwr_ctrl.vhd
read_hdl -vhdl -library work $MP/resv_unit.vhd
# afe_stub: NOT instantiated in a wound config (cqAfeStubs=false -> QSPI0 takes
# page-0 slot 12), read for parity with the wound flows. Its CP1-D4 MGMT_HART
# generic therefore has no instance to apply to in THIS config -- the
# orchestrator's management privilege is a base-Castalia-penta feature only.
read_hdl -vhdl -library work $MP/afe_stub.vhd

# --- The four hardened tiles: gate netlist as verilog source ---
# MCU.vhd instantiates by DIRECT ENTITY INSTANTIATION (entity work.hart_tile),
# which genus 19.15 cannot blackbox (CDFG-254/CDFG-321). Dummy parameters are
# injected into the module header because MCU.vhd passes a generic map and the
# verilog module has no parameters (CDFG-214). Values = the one real
# configuration; all four instances bind identically. Intermediate name is
# _penta-suffixed so a concurrent MCU_WOUND_hier run cannot clobber it.
exec bash -c "mkdir -p $INPUT_DIR && awk '
	/^module hart_tile\\(/ { inhdr=1 }
	{ print }
	inhdr && /\\);\$/ { print \"  parameter PC_RST_VAL = 32'\\''h00000000;\"; print \"  parameter SH_AW = $PENTA_SH_AW;\"; inhdr=0 }
' $TILE_NETLIST > $INPUT_DIR/hart_tile_top_penta.gen.v"
read_hdl $INPUT_DIR/hart_tile_top_penta.gen.v

# CPR6 GUARD: the injected dummy is only a CDFG-214 silencer -- the real width
# is baked into the gate netlist's port declaration. Assert the two agree, so a
# stale netlist (or a stale injection) cannot pass silently.
set n_shaw_tile [exec bash -c "grep -c '^  output \\\[[expr $PENTA_SH_AW - 1]:0\\\] sh_addr;' $TILE_NETLIST || true"]
if {$n_shaw_tile != 1} {
	puts "FATAL (CPR6): $TILE_NETLIST does not declare sh_addr as \[[expr $PENTA_SH_AW - 1]:0\]"
	puts "              -- the hardened tile netlist is not the SH_AW=$PENTA_SH_AW cut."
	exit 1
}
puts "tile netlist sh_addr width verified = $PENTA_SH_AW"

# --- PENTA-DELTA 2: the soft orchestrator, same treatment, RENAMED netlist ---
# Every module below the top carries the `orch_` prefix (genus/orch_tile/
# rename_orch_modules.sh, which FATALs unless the tile and orchestrator module
# sets are disjoint). The TOP is still `orch_tile` because MCU.vhd binds
# `entity work.orch_tile` by that name.
exec bash -c "awk '
	/^module orch_tile\\(/ { inhdr=1 }
	{ print }
	inhdr && /\\);\$/ { print \"  parameter PC_RST_VAL = 32'\\''h00000000;\"; print \"  parameter SH_AW = $PENTA_SH_AW;\"; inhdr=0 }
' $ORCH_NETLIST > $INPUT_DIR/orch_tile_top_penta.gen.v"
read_hdl $INPUT_DIR/orch_tile_top_penta.gen.v

# >= 1, not == 1: the orchestrator netlist declares sh_addr TWICE -- once on
# the `orch_tile` wrapper and once on the `orch_hart_tile` it wraps. (The tile
# netlist declares it once, which is why that guard above is an equality.)
set n_shaw_orch [exec bash -c "grep -c '^  output \\\[[expr $PENTA_SH_AW - 1]:0\\\] sh_addr;' $ORCH_NETLIST || true"]
if {$n_shaw_orch < 1} {
	puts "FATAL (CPR6): $ORCH_NETLIST does not declare sh_addr as \[[expr $PENTA_SH_AW - 1]:0\]"
	puts "              -- re-run 'make orch_tile.genus' (it elaborates at SH_AW=$PENTA_SH_AW) + the rename."
	exit 1
}
# And the aperture pass-through must be on the wrapper (R4-A2: hart 0's
# aperture slave wires straight to these pins).
set n_tcmext_orch [exec bash -c "grep -c 'tcm_ext_req' $ORCH_NETLIST || true"]
if {$n_tcmext_orch < 1} {
	puts "FATAL (CPR6): $ORCH_NETLIST has no tcm_ext_req pin -- stale pre-CPR2 orchestrator netlist"
	exit 1
}
puts "orch netlist sh_addr width verified = $PENTA_SH_AW, tcm_ext pass-through present"

# --- Top level: the staged penta-wound MCU.vhd, generic-stripped ------------
# PENTA-DELTA 3: genus 19 cannot bind a VHDL BOOLEAN generic to a verilog
# parameter (CDFG-200), so every `=> CORE_*` association is stripped and the
# entity defaults (== the staged MemoryMap values == the values both gate
# netlists were synthesized with) apply. `=> CORE_` and not `=> CORE_ENABLE_`:
# `PMP_ENTRIES => CORE_PMP_ENTRIES` must go too, or it is left as the last
# association WITH a trailing comma. SH_AW then loses its trailing comma.
# Shape check below is a FATAL, not a comment: 5 harts x 25 associations.
# TILE_ENABLE_ JOINS CORE_ IN THE STRIP (2026-08-17). The asymmetric-ISA change
# made harts 1..N-1 take ENABLE_MUL/DIV/BITMANIP from TILE_ENABLE_* instead of
# CORE_ENABLE_*, and those are BOOLEAN generics exactly like the ones this sed
# already removes -- CDFG-200 applies identically. Left in, they survived the
# strip and produced a generic map whose surviving associations no longer form a
# legal list: "generic map aspect requires ')', read DEBUG_ENTRY_ADDR".
# STRIPPING THEM IS CORRECT, NOT A WORKAROUND, and for the same reason the CORE_
# strip is: harts 1..N-1 bind to the GATE NETLIST hart_tile.genus.v, whose ISA is
# already fixed in silicon by the -parameters override used to synthesize it
# (ENABLE_MUL/DIV/BITMANIP false, guarded there by a divider-count assertion).
# A generic association on a verilog gate module has nothing to bind to anyway.
# THE SH_AW DE-COMMA IS CONDITIONAL (2026-08-17). It exists because stripping
# every `=> CORE_` association used to leave SH_AW as the LAST one in the map,
# still carrying its trailing comma. That is no longer true whenever debug is on:
# DEBUG_ENTRY_ADDR is not a CORE_ association, so it SURVIVES the strip and lands
# after SH_AW -- and de-comma'ing SH_AW then produces
#     SH_AW            => SH_AW
#     DEBUG_ENTRY_ADDR => x"00010780"
# with no separator, i.e. "generic map aspect requires ')', read
# DEBUG_ENTRY_ADDR". A latent bug that armed itself when debug.enable became a
# shipped default. Decide from the file rather than assuming either shape.
set n_dbg_entry [exec bash -c "grep -c 'DEBUG_ENTRY_ADDR  =>' $PENTA_HDL/MCU.vhd || true"]

# THE STRIP IS ASSOCIATION-AWARE, NOT LINE-BASED, and it has to be. The original
# `sed '/=> CORE_/d'` deleted whole LINES, which is right only while every
# association sits on its own line. It does not: the Debug Module instance is
# emitted as
#     dm0: entity work.debug_module
#         generic map (ENABLE_DEBUG => CORE_ENABLE_DEBUG, NHARTS => 5,
# so the line delete removed `generic map (` AND `NHARTS => 5` along with the
# CORE_ association, leaving a headless association list ("component
# instantiation statement requires ';', read SH_AW"). That instance only exists
# on a debug build, which is why this never bit before debug.enable became a
# shipped default.
# Rules 1-2 drop associations that are ALONE on their line; rules 3-4 excise
# associations embedded in a line that carries other syntax. Both CORE_ and
# TILE_ENABLE_ are stripped for the same CDFG-200 reason (genus 19 cannot bind a
# VHDL boolean generic to a verilog parameter), and stripping them is safe
# because harts bind to GATE NETLISTS whose ISA is already fixed in silicon.
set STRIP_SED $INPUT_DIR/.strip_generics.sed
set _sfh [open $STRIP_SED w]
puts $_sfh {/^[[:space:]]*[A-Za-z_0-9]+[[:space:]]*=>[[:space:]]*CORE_[A-Za-z_0-9]+,?[[:space:]]*$/d}
puts $_sfh {/^[[:space:]]*[A-Za-z_0-9]+[[:space:]]*=>[[:space:]]*TILE_ENABLE_[A-Za-z_0-9]+,?[[:space:]]*$/d}
puts $_sfh {s/[A-Za-z_0-9]+[[:space:]]*=>[[:space:]]*CORE_[A-Za-z_0-9]+,[[:space:]]*//g}
puts $_sfh {s/[A-Za-z_0-9]+[[:space:]]*=>[[:space:]]*TILE_ENABLE_[A-Za-z_0-9]+,[[:space:]]*//g}
# DEBUG_ENTRY_ADDR GOES TOO. The harts bind to GATE NETLISTS, and a gate netlist
# has no parameters to bind to -- elaborate says so directly: "Unknown parameter.
# [CDFG-214] Could not find the parameter 'DEBUG_ENTRY_ADDR' in module
# 'orch_tile'". It is not a boolean, so the CORE_/TILE_ENABLE_ rules miss it; it
# only appears at all on a debug build, which is why this is new. Removing it
# restores exactly the pre-debug shape, where SH_AW is the last association --
# hence the de-comma below is unconditional again.
puts $_sfh {/^[[:space:]]*DEBUG_ENTRY_ADDR[[:space:]]*=>[[:space:]]*x"[0-9A-Fa-f]+"[[:space:]]*,?[[:space:]]*$/d}
puts $_sfh {s/SH_AW          => SH_AW,/SH_AW          => SH_AW/}
close $_sfh
puts "generic strip: DEBUG_ENTRY_ADDR on $n_dbg_entry instances -- stripped (gate netlists take no parameters)"
exec bash -c "sed -E -f $STRIP_SED $PENTA_HDL/MCU.vhd > $INPUT_DIR/MCU_top_penta_wound.gen.vhd"

# The generic map opener must survive the strip -- this is the dm0 defect above.
set n_gm_src [exec bash -c "grep -c 'generic map (' $PENTA_HDL/MCU.vhd || true"]
set n_gm_out [exec bash -c "grep -c 'generic map (' $INPUT_DIR/MCU_top_penta_wound.gen.vhd || true"]
puts "generic strip: generic map openers $n_gm_src -> $n_gm_out"
if {$n_gm_src != $n_gm_out} {
	puts "FATAL: the strip destroyed [expr {$n_gm_src - $n_gm_out}] 'generic map (' opener(s) --"
	puts "  an association sharing a line with the opener was line-deleted. The list is headless."
	exit 1
}
set n_core [exec bash -c "grep -c '=> CORE_' $PENTA_HDL/MCU.vhd || true"]
set n_tile [exec bash -c "grep -c '=> TILE_ENABLE_' $PENTA_HDL/MCU.vhd || true"]
set n_tile_left [exec bash -c "grep -c '=> TILE_ENABLE_' $INPUT_DIR/MCU_top_penta_wound.gen.vhd || true"]
puts "generic strip: $n_tile TILE_ENABLE_ associations removed, $n_tile_left remain"
if {$n_tile_left != 0} {
	puts "FATAL: TILE_ENABLE_ associations survived the strip -- the generic map will not parse."
	exit 1
}
set n_left [exec bash -c "grep -c '=> CORE_' $INPUT_DIR/MCU_top_penta_wound.gen.vhd || true"]
set n_shaw [exec bash -c "grep -c 'SH_AW          => SH_AW\$' $INPUT_DIR/MCU_top_penta_wound.gen.vhd || true"]
puts "generic strip: $n_core CORE_ associations removed, $n_left remain, $n_shaw SH_AW lines de-comma'd"
# SH_AW is last again for every hart once DEBUG_ENTRY_ADDR is stripped, so all
# five must have lost their comma regardless of the debug knob.
set n_shaw_want 5
if {$n_left != 0 || $n_shaw != $n_shaw_want} {
	puts "FATAL: generic strip shape wrong (want 0 CORE_ remaining, $n_shaw_want de-comma'd SH_AW lines; got $n_left / $n_shaw)"
	exit 1
}
read_hdl -vhdl -library work $INPUT_DIR/MCU_top_penta_wound.gen.vhd

################################################################################
# Elaboration
################################################################################
puts "Elaborating $TOP_MODULE"
elaborate $TOP_MODULE

set_db [get_db modules] .boundary_opto false
puts "boundary_opto disabled on [llength [get_db modules]] modules"

# The hardened tile is UNTOUCHABLE: one module, four instances, zero genus edits.
foreach tm [get_db modules -if {.name == hart_tile}] {
	catch { set_db $tm .dont_touch true }
	catch { set_db $tm .preserve true }
	puts "tile module preserved: [get_db $tm .name]"
}
for {set h $TILE_HART_LO} {$h <= $TILE_HART_HI} {incr h} {
	# CPR6 FINDING: `inst:MCU/hart<h>` is NOT a recognized genus object -- these
	# are HIERARCHICAL instances, so the type prefix is `hinst:`, and the CP-era
	# form has been a silent no-op inside its catch since CP4a (measured: TUI-182
	# "'inst:MCU/hart0' is not a recognized object/attribute"). Harmless in
	# practice -- the MODULE-level dont_touch/preserve above is what protects the
	# hardened tile -- but a dead guard is worse than none, so it is corrected and
	# its result is REPORTED rather than swallowed.
	set _hp 0
	catch { set_db hinst:$TOP_MODULE/hart$h .preserve true ; set _hp 1 }
	puts "### UNL STATUS ### : preserve hinst:$TOP_MODULE/hart$h -> [expr {$_hp ? {OK} : {UNRESOLVED}}]"
}

# PENTA-DELTA 2 (cont.): the orchestrator subtree is preserved too. It is SOFT
# (Innovus places and routes it), but it is already synthesized at high effort
# by genus/orch_tile -- and, decisively, re-optimizing it here could ungroup or
# RE-NAME its modules, which would destroy the D6 disjointness the whole scheme
# rests on. auto_ungroup none + preserve keeps the `orch_*` namespace intact all
# the way to the P&R netlist.
set orch_mods [get_db modules -if {.name == orch_tile}]
foreach m [get_db modules] {
	if {[string match orch_* [get_db $m .name]]} { lappend orch_mods $m }
}
set n_orch_mod 0
foreach m $orch_mods {
	catch { set_db $m .dont_touch true }
	catch { set_db $m .preserve true }
	incr n_orch_mod
}
puts "orchestrator modules preserved: $n_orch_mod (orch_tile + orch_* subtree)"
if {$n_orch_mod < 2} {
	puts "FATAL: the orchestrator subtree is not in the elaborated database -- did rename_orch_modules.sh run?"
	exit 1
}
set _hp 0
catch { set_db hinst:$TOP_MODULE/hart$ORCH_HART .preserve true ; set _hp 1 }
puts "### UNL STATUS ### : preserve hinst:$TOP_MODULE/hart$ORCH_HART -> [expr {$_hp ? {OK} : {UNRESOLVED}}]"

# ---- CPR6 SHAPE CENSUS: the renumber, asserted on the elaborated DB ---------
# Post-renumber the shape is hart0 = orch_tile, hart1..hart4 = hart_tile. The
# CP-era shape was the exact inverse, so a stale staged MCU.vhd would still
# elaborate cleanly and produce a chip with the orchestrator in a corner. This
# check is the difference between the two.
# THE CHECK IS ON THE SOURCE TEXT, NOT ON THE DB, and that is deliberate. Two
# genus addressing schemes were tried against the elaborated database first
# (`get_db insts MCU/hart1` and the typed `inst:MCU/hart1`) and BOTH returned
# empty lists SILENTLY -- these are HIERARCHICAL instances, and get_db object
# names are design-relative besides (the CPR5 silent-empty-report trap, in a
# second costume). A shape assertion that cannot distinguish "wrong shape" from
# "wrong query" is worse than none, so the authority here is the staged VHDL
# the run actually read, which is unambiguous, and the emitted netlist is
# re-asserted downstream by prep_top_netlist_penta.sh (A1/A2/A2b) on exactly
# the instantiation lines Innovus will bind.
# TCL QUOTING: a bracketed regex class inside a "..." string is COMMAND
# SUBSTITUTION -- `hart[1-4]` evaluates as `1-4` and dies with `invalid command
# name "1-4"`. The class is built as a literal here (RANGE from the two loop
# bounds, so it cannot drift out of step with them) and the brackets are
# escaped where they appear in a quoted string.
set TILE_CLASS "\[$TILE_HART_LO-$TILE_HART_HI\]"
set n_orch_src [exec bash -c "grep -cE '^ +hart$ORCH_HART: entity work.orch_tile\$' $PENTA_HDL/MCU.vhd || true"]
set n_tile_src [exec bash -c "grep -cE '^ +hart$TILE_CLASS: entity work.hart_tile\$' $PENTA_HDL/MCU.vhd || true"]
set n_stale_src [exec bash -c "grep -cE '^ +(hart$ORCH_HART: entity work.hart_tile|hart$TILE_CLASS: entity work.orch_tile)\$' $PENTA_HDL/MCU.vhd || true"]
puts "### UNL STATUS ### : staged MCU.vhd shape -- orch_tile at hart0 = $n_orch_src (expect 1),"
puts "### UNL STATUS ### :                        hart_tile at hart$TILE_HART_LO..hart$TILE_HART_HI = $n_tile_src (expect $NUM_HARTS),"
puts "### UNL STATUS ### :                        CP-era-shaped instantiations = $n_stale_src (expect 0)"
if {$n_orch_src != 1 || $n_tile_src != $NUM_HARTS || $n_stale_src != 0} {
	puts "FATAL (CPR6): the renumbered shape is NOT in the staged MCU.vhd."
	puts "              Expected hart0=orch_tile + hart1..4=hart_tile. The staged file is the"
	puts "              CP-era (orch-as-hart4) generation -- restage from config/penta_wound.json:"
	puts "              cd platform/common && make generate CONFIG=config/penta_wound.json,"
	puts "              copy out/hdl/{MCU,MemoryMap}.vhd into $PENTA_HDL/, then make chip to restore."
	exit 1
}
# Diagnostic only (never a gate): what the elaborated DB calls the five bodies.
catch {
	foreach _hi [get_db hinsts -if {.name == hart0 || .name == hart1 || .name == hart2 || .name == hart3 || .name == hart4}] {
		puts "### UNL STATUS ### : hinst [get_db $_hi .name] -> module [get_db $_hi .module.name]"
	}
}

# Blackbox census -- must be EXACTLY the three analog macros. A missing
# read_hdl silently blackboxes a peripheral and only the gate sim's xmelab
# CUVMUR is loud about it.
set bb_names {}
catch {
	foreach m [get_db modules] {
		if {[get_db $m .is_black_box]} { lappend bb_names [get_db $m .name] }
	}
}
set bb_names [lsort -unique $bb_names]
puts "### UNL STATUS ### : blackbox modules = [llength $bb_names] : $bb_names"

################################################################################
# Constraints
################################################################################

# --- Clocks generated inside system0 (shared by every hart) ---
create_clock -name mclk			-domain mclk_domain			-period $FASTEST_PERIOD	hpin:$TOP_MODULE/system0/mclk_out
create_clock -name smclk		-domain smclk_domain		-period $FASTEST_PERIOD	hpin:$TOP_MODULE/system0/smclk_out
create_clock -name clk_lfxt		-domain clk_lfxt_domain		-period $CLKLFXT_PERIOD	hpin:$TOP_MODULE/system0/clk_lfxt_out
create_clock -name clk_hfxt		-domain clk_hfxt_domain		-period $CLKHFXT_PERIOD	hpin:$TOP_MODULE/system0/clk_hfxt_out

# --- NO clk_cpu<h> clocks for harts 1-4 (CPR6 renumber): those hpins live
#     inside the hardened tile and are constrained by the tile's own SDC
#     (M9c fix). ---

# --- PENTA-DELTA 4: the ORCHESTRATOR's gated core clock. hart0 is SOFT logic
#     in the centre band -- Innovus places it, CTS must build its clock tree,
#     and every core register inside it is clocked by this gated mclk. Same
#     shape as the tile-internal generated clock (divide_by 1, SAME domain as
#     mclk -- the M9c interpretation: clk_cpu IS mclk, gated).
#     The hpin path is DERIVED from the netlist hierarchy, not assumed:
#     MCU/hart0 (orch_tile) -> tile (the hart_tile inside the wrapper) ->
#     core (vesta) -> clk_cpu. FATAL if it is not there, because a silently
#     missing generated clock is exactly the M9c bug class. ---
set ORCH_CLKCPU_HPIN hpin:$TOP_MODULE/hart$ORCH_HART/$ORCH_TILE_INST/core/clk_cpu
if {[llength [get_db $ORCH_CLKCPU_HPIN]] == 0} {
	puts "FATAL: $ORCH_CLKCPU_HPIN does not exist -- the orchestrator hierarchy is not"
	puts "       hart$ORCH_HART/$ORCH_TILE_INST/core/clk_cpu. Dump the netlist hierarchy and fix ORCH_TILE_INST."
	exit 1
}
create_generated_clock -name clk_cpu$ORCH_HART -divide_by 1 \
	-source hpin:$TOP_MODULE/system0/mclk_out -domain mclk_domain \
	$ORCH_CLKCPU_HPIN
puts "orchestrator generated clock: clk_cpu$ORCH_HART at $ORCH_CLKCPU_HPIN"

# --- hart 0's XIP flash memory clock: a gated mclk that EXITS the hart at
# flash_clk_mem and clocks spi0's flash-side logic. CPR6 INVERSION: hart 0 is
# now the ORCHESTRATOR, and R2 moves the whole ex-hart-0 wiring bundle onto it
# -- the flash/XIP quartet included. So this clock now leaves the SOFT
# orch_tile wrapper, and it is the FOUR HARDENED TILES whose flash_clk_mem
# pins are left OPEN at MCU level (they get no top-level generated clock).
# The hpin path is literally unchanged (`hart0/flash_clk_mem`) and that is a
# coincidence of the renumber, not a line that was left alone: it is the
# orchestrator's port now. Asserted below, because a generated clock silently
# attached to the wrong instance is the M9c bug class.
set FLASH_CLK_HPIN hpin:$TOP_MODULE/hart$ORCH_HART/flash_clk_mem
if {[llength [get_db $FLASH_CLK_HPIN]] == 0} {
	puts "FATAL (CPR6): $FLASH_CLK_HPIN does not exist -- hart$ORCH_HART is not the flash-carrying instance."
	exit 1
}
create_generated_clock -name flash_clk_mem -divide_by 1 \
	-source hpin:$TOP_MODULE/system0/mclk_out -domain mclk_domain \
	$FLASH_CLK_HPIN

# --- Peripheral source clocks ---
create_clock -name clk_scl0		-domain clk_scl0_domain		-period $I2CSCL_PERIOD	hpin:$TOP_MODULE/i2c0/SCL_IN
create_clock -name clk_scl1		-domain clk_scl1_domain		-period $I2CSCL_PERIOD	hpin:$TOP_MODULE/i2c1/SCL_IN
create_clock -name clk_sck0		-domain clk_sck0_domain		-period $SPISCK_PERIOD	hpin:$TOP_MODULE/spi0/sck_in
create_clock -name clk_sck1		-domain clk_sck1_domain		-period $SPISCK_PERIOD	hpin:$TOP_MODULE/spi1/sck_in

# ---- JTAG TCK ------------------------------------------------------------
# THE TAP HAD NO CLOCK AT ALL BEFORE THIS (2026-08-16). This flow descends from
# the debug-OFF wound assembly, where dtm0 did not exist, so no create_clock was
# ever written for it. When debug.enable became a SHIPPED DEFAULT the whole JTAG
# transport -- a 16-state TAP FSM, the 5-bit IR and four DRs -- got synthesised
# with NO timing constraint whatsoever, and the chip SDC inherited the hole: the
# ONLY tck line in the generated SDC was a `set_driving_cell ... [get_ports tck]`,
# which gen_MCU_castalia_penta_sdc.sh then DROPS along with every other
# [get_ports] line. Net effect: an entire clock domain untimed through synthesis
# AND P&R, invisible because nothing errors on a clock that was never declared.
#
# DECLARED ON THE INSTANCE PIN, NEVER THE PORT -- MCU.vhd states this contract
# verbatim ("TCK IS ITS OWN CLOCK DOMAIN, and it is declared to Genus on the
# dtm0 INSTANCE PIN, never on this port"), precisely because the chip SDC
# transform deletes port-scoped lines and FATALs if one survives.
#
# ITS OWN -domain, like every other asynchronous source here (clk_scl*, clk_sck*):
# TCK is asynchronous to mclk by construction and crosses on a 2-FF synchroniser
# with the payload held, so cross-domain paths must not be timed. A separate
# domain is how this flow expresses that.
#
# GUARDED, because debug is a knob: on a debug-OFF build dtm0 does not exist and
# an unguarded create_clock would hard-fail the run. Absence is legal there;
# absence on a debug-ON build is the defect above, so that case is LOUD.
# The check is POSITIVE -- attempt the clock, then ask whether it EXISTS -- and
# not a pre-flight object query. `get_db insts -if {.name == "dtm0"}` was tried
# first and returned EMPTY on a netlist that demonstrably contains dtm0, because
# that collection does not match hierarchical instances by leaf name; the guard
# then fired on a perfectly good build. Asking `get_db clocks` afterwards cannot
# be fooled that way: either the clock is there or it is not.
catch {create_clock -name clk_tck -domain clk_tck_domain -period $TCK_PERIOD hpin:$TOP_MODULE/dtm0/tck} __tck_err
if {[llength [get_db clocks -if {.name == "clk_tck"}]] > 0} {
	puts "### UNL STATUS ### : JTAG TCK clock created on dtm0/tck at $TCK_FREQ MHz (period $TCK_PERIOD ns)"
} elseif {$CORE_DEBUG_ON} {
	puts "FATAL: debug is ON but the TCK clock could not be created on dtm0/tck -- the JTAG TAP would be synthesised unclocked. ($__tck_err)"
	exit 1
} else {
	puts "### UNL STATUS ### : no dtm0 instance (debug-OFF build) -- no TCK clock, as expected"
}

################################################################################
# --- WOUND digperiph constraints -- IDENTICAL to MCU_WOUND_hier.genus.tcl.
#     See its header for the full rationale/provenance of every line. ---
create_generated_clock -name qspi0_baud_src -divide_by 1 \
	-source hpin:$TOP_MODULE/qspi0/clk hpin:$TOP_MODULE/qspi0/cg_clk_baud_src/ClkOut
create_generated_clock -name qspi0_baud     -divide_by 1 \
	-source hpin:$TOP_MODULE/qspi0/clk hpin:$TOP_MODULE/qspi0/cg_clk_baud/ClkOut
create_generated_clock -name i3c0_baud_src  -divide_by 1 \
	-source hpin:$TOP_MODULE/i3c0/clk hpin:$TOP_MODULE/i3c0/cg_clk_baud_src/ClkOut
create_generated_clock -name i3c0_baud      -divide_by 1 \
	-source hpin:$TOP_MODULE/i3c0/clk hpin:$TOP_MODULE/i3c0/cg_clk_baud/ClkOut

create_clock -name qspi0_enmem	-domain qspi0_enmem_domain	-period $FASTEST_PERIOD	hpin:$TOP_MODULE/qspi0/EnMemPeriph
create_clock -name i3c0_enmem	-domain i3c0_enmem_domain	-period $FASTEST_PERIOD	hpin:$TOP_MODULE/i3c0/EnMemPeriph
create_clock -name nfc0_enmem	-domain nfc0_enmem_domain	-period $FASTEST_PERIOD	hpin:$TOP_MODULE/nfc0/EnMemPeriph

create_clock -name i3c0_sda		-domain i3c0_sda_domain		-period $FASTEST_PERIOD	hpin:$TOP_MODULE/i3c0/SDA_IN
create_clock -name nfc0_rf		-domain nfc0_rf_domain		-period 50.0		hpin:$TOP_MODULE/nfc0/rf_clk
create_clock -name rtc0_lfxt	-domain rtc0_lfxt_domain	-period 100.0		hpin:$TOP_MODULE/rtc0/lfxt_in

define_cost_group -name qspi0_baud_group	-weight 1
define_cost_group -name i3c0_baud_group		-weight 1
define_cost_group -name nfc0_rf_group		-weight 1
define_cost_group -name rtc0_lfxt_group		-weight 1
path_group -from qspi0_baud	-group qspi0_baud_group
path_group -from i3c0_baud	-group i3c0_baud_group
path_group -from nfc0_rf	-group nfc0_rf_group
path_group -from rtc0_lfxt	-group rtc0_lfxt_group

set_false_path -from hpin:$TOP_MODULE/i3c0/SCL_IN -to [get_clocks i3c0_sda]
################################################################################

# --- Cost groups: each clock domain optimized independently ---
define_cost_group -name mclk_group			-weight 1
define_cost_group -name smclk_group			-weight 1
define_cost_group -name clk_lfxt_group		-weight 1
define_cost_group -name clk_hfxt_group		-weight 1
define_cost_group -name clk_scl0_group		-weight 1
define_cost_group -name clk_scl1_group		-weight 1
define_cost_group -name clk_sck0_group		-weight 1
define_cost_group -name clk_sck1_group		-weight 1
# PENTA-DELTA 4 (cont.): the orchestrator's own group, mirroring the flat
# flow's per-hart clk_cpu<h> groups.
define_cost_group -name clk_cpu${ORCH_HART}_group	-weight 1

path_group -from mclk			-group mclk_group
path_group -from smclk			-group smclk_group
path_group -from clk_lfxt		-group clk_lfxt_group
path_group -from clk_hfxt		-group clk_hfxt_group
path_group -from clk_scl0		-group clk_scl0_group
path_group -from clk_scl1		-group clk_scl1_group
path_group -from clk_sck0		-group clk_sck0_group
path_group -from clk_sck1		-group clk_sck1_group
path_group -from clk_cpu$ORCH_HART	-group clk_cpu${ORCH_HART}_group

# PGEN powered-down-macro exceptions (both gate netlists are loaded as SOURCE,
# so every TCM PGEN pin is visible and needs the exception).
set_false_path -to pin:$TOP_MODULE/rom0/PGEN
set_false_path -to pin:$TOP_MODULE/npuram0/PGEN
for {set h $TILE_HART_LO} {$h <= $TILE_HART_HI} {incr h} {
	set_false_path -to pin:$TOP_MODULE/hart$h/ram0/PGEN
}
# PENTA-DELTA 5: the orchestrator's TCM sits one level deeper (through the
# wrapper). It is never gated (CP1 D2: tcm_pgen '0', tcm_retn '1') -- the false
# path is for parity and costs nothing.
set_false_path -to pin:$TOP_MODULE/hart$ORCH_HART/$ORCH_TILE_INST/ram0/PGEN
set_false_path -to pin:$TOP_MODULE/hart$ORCH_HART/$ORCH_TILE_INST/ram0/RETN

################################################################################
# Top Design Attributes
################################################################################
set_max_transition 0.5
set_load 0.600 [get_ports -filter "direction==out"]
set_driving_cell -lib_cell INVX1MA10TH [get_ports -filter "direction==in"]

set_db net:$TOP_MODULE/npu0/Decision[15] .dont_touch true

# TRNG0 RO ensemble preserve -- carried VERBATIM from MCU_WOUND_hier (see its
# header): 202 preserved inverters + 8 NAND enables, FATAL if the count is off
# (a collapsed ring = no entropy, silently). u_ro is a TOP-LEVEL sibling of
# trng0, so the *u_ro* glob cannot collide with either hart subtree.
set ro_hinsts [get_db hinsts *u_ro*]
set_db $ro_hinsts .ungroup_ok false
set ro_mods [get_db modules *trng_*]
set_db $ro_mods .boundary_opto false
set n_ring 0
foreach h $ro_hinsts {
    if { [string match *inv* $h] || [string match *nand* $h] } { incr n_ring }
}
puts "TRNG RO census (pre-syn): [llength $ro_hinsts] hinsts under u_ro, $n_ring inverter/nand wrappers"
if { $n_ring < 210 } {
    puts "FATAL: TRNG RO pre-syn census $n_ring < 210 (202 inv + 8 nand)"
    exit 1
}

################################################################################
# Synthesis -- TIME-OPTIMIZED, AREA-RELAXED
################################################################################
puts "Synthesizing top design (penta-wound MCU hierarchical)"

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
set ro_hinsts_postmap [get_db hinsts *u_ro*]
set n_ring_postmap 0
foreach h $ro_hinsts_postmap {
    if { [string match *inv* $h] || [string match *nand* $h] } { incr n_ring_postmap }
}
puts "TRNG RO census (post-map): $n_ring_postmap inverter/nand wrappers"
if { $n_ring_postmap < 210 } {
    puts "FATAL: TRNG RO post-map census $n_ring_postmap < 210 -- ring collapse"
    exit 1
}
set_db $ro_hinsts_postmap .preserve true
syn_opt

################################################################################
# Reports
################################################################################
puts "Generating reports"
report_area           > $REPORT_DIR/$BASENAME.area.rpt
report_gates          > $REPORT_DIR/$BASENAME.gates.rpt
report_timing         > $REPORT_DIR/$BASENAME.timing.rpt
report_design_rules   > $REPORT_DIR/$BASENAME.rules.rpt

# Wound per-cost-group negative controls (an EMPTY report = a domain wrongly cut).
report_timing -group qspi0_baud_group -max_paths 10 > $REPORT_DIR/$BASENAME.qspi0_baud.rpt
report_timing -group i3c0_baud_group  -max_paths 10 > $REPORT_DIR/$BASENAME.i3c0_baud.rpt
report_timing -group nfc0_rf_group    -max_paths 15 > $REPORT_DIR/$BASENAME.nfc0_rf.rpt
report_timing -group rtc0_lfxt_group  -max_paths 10 > $REPORT_DIR/$BASENAME.rtc0_lfxt.rpt
catch { report_timing -through hpin:$TOP_MODULE/dma0/m_req -max_paths 10 > $REPORT_DIR/$BASENAME.dma0_mclk.rpt }

# PENTA negative controls -- the orchestrator must be REAL and TIMED.
#  (a) its own clk_cpu group must be non-empty,
#  (b) both directions across the orchestrator boundary (its registered shared-
#      bus port -> arbiter and back) must show paths. An empty (a) is the M9c
#      bug at chip level; an empty (b) means hart0 is not actually wired in.
catch { report_timing -group clk_cpu${ORCH_HART}_group -max_paths 10 > $REPORT_DIR/$BASENAME.orch_clkcpu.rpt }
catch { report_timing -through hpin:$TOP_MODULE/hart$ORCH_HART/sh_req -max_paths 10 > $REPORT_DIR/$BASENAME.orch_shreq.rpt }
catch { report_timing -through hpin:$TOP_MODULE/hart$ORCH_HART/sh_rdata[0] -max_paths 10 > $REPORT_DIR/$BASENAME.orch_shrdata.rpt }
# Orchestrator subtree size (the CP4a QoR deliverable).
catch { report_area -depth 2 > $REPORT_DIR/$BASENAME.area_d2.rpt }

################################################################################
# Output Files
################################################################################
write_script > $OUTPUT_DIR/$BASENAME.g
write_hdl    > $OUTPUT_DIR/$BASENAME.v
write_sdc    > $OUTPUT_DIR/$BASENAME.sdc
write_sdf    > $OUTPUT_DIR/$BASENAME.sdf

################################################################################
# GENUS 19.15 DEGENERATE-CLOCK POWER WORKAROUND (see MCU_WOUND_hier's header):
# i3c0/SDA_IN drives exactly ONE leaf flop and 19.15 then silently zeroes
# internal+switching power for the WHOLE design. Every honest-SDC output above
# is already written, so retiring SDA_IN for these two reports only is safe.
################################################################################
reset_clock -clock [get_clocks i3c0_sda]
report_power -by_hierarchy -levels 4 > $REPORT_DIR/$BASENAME.power.rpt
report_clock_gating   > $REPORT_DIR/$BASENAME.clk.rpt

toc
set total_run_time [getHMS $START_TIME $STOP_TIME]
puts "Genus MCU_PENTA_hier run is complete. Run time $total_run_time"
puts "NEXT: cd ../../innovus/common/MCU_castalia_penta && ./prep_top_netlist_penta.sh && ./gen_MCU_castalia_penta_sdc.sh"

exit
