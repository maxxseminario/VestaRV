# ####################################################################

#  Created by Genus(TM) Synthesis Solution 19.15-s090_1 on Sun Jul 12 23:23:45 CDT 2026

# ####################################################################

set sdc_version 2.0

set_units -capacitance 1000fF
set_units -time 1000ps

# Set the current design
current_design chip_top_quad

create_clock -name "mclk" -period 40.0 -waveform {0.0 20.0} [get_pins mcu0/system0/mclk_out]
create_clock -name "smclk" -period 40.0 -waveform {0.0 20.0} [get_pins mcu0/system0/smclk_out]
create_clock -name "clk_lfxt" -period 30517.578 -waveform {0.0 15258.789} [get_pins mcu0/system0/clk_lfxt_out]
create_clock -name "clk_hfxt" -period 40.0 -waveform {0.0 20.0} [get_pins mcu0/system0/clk_hfxt_out]
create_generated_clock -name "flash_clk_mem" -divide_by 1     -source [get_pins mcu0/system0/mclk_out]   [get_pins mcu0/hart0/flash_clk_mem] 
create_clock -name "clk_scl0" -period 200.0 -waveform {0.0 100.0} [get_pins mcu0/i2c0/SCL_IN]
create_clock -name "clk_scl1" -period 200.0 -waveform {0.0 100.0} [get_pins mcu0/i2c1/SCL_IN]
create_clock -name "clk_sck0" -period 40.0 -waveform {0.0 20.0} [get_pins mcu0/spi0/sck_in]
create_clock -name "clk_sck1" -period 40.0 -waveform {0.0 20.0} [get_pins mcu0/spi1/sck_in]
set_false_path -from [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ] -to [get_clocks smclk]
set_false_path -from [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ] -to [get_clocks clk_lfxt]
set_false_path -from [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ] -to [get_clocks clk_hfxt]
set_false_path -from [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ] -to [get_clocks clk_scl0]
set_false_path -from [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ] -to [get_clocks clk_scl1]
set_false_path -from [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ] -to [get_clocks clk_sck0]
set_false_path -from [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks smclk] -to [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ]
set_false_path -from [get_clocks smclk] -to [get_clocks clk_lfxt]
set_false_path -from [get_clocks smclk] -to [get_clocks clk_hfxt]
set_false_path -from [get_clocks smclk] -to [get_clocks clk_scl0]
set_false_path -from [get_clocks smclk] -to [get_clocks clk_scl1]
set_false_path -from [get_clocks smclk] -to [get_clocks clk_sck0]
set_false_path -from [get_clocks smclk] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks clk_lfxt] -to [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ]
set_false_path -from [get_clocks clk_lfxt] -to [get_clocks smclk]
set_false_path -from [get_clocks clk_lfxt] -to [get_clocks clk_hfxt]
set_false_path -from [get_clocks clk_lfxt] -to [get_clocks clk_scl0]
set_false_path -from [get_clocks clk_lfxt] -to [get_clocks clk_scl1]
set_false_path -from [get_clocks clk_lfxt] -to [get_clocks clk_sck0]
set_false_path -from [get_clocks clk_lfxt] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks clk_hfxt] -to [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ]
set_false_path -from [get_clocks clk_hfxt] -to [get_clocks smclk]
set_false_path -from [get_clocks clk_hfxt] -to [get_clocks clk_lfxt]
set_false_path -from [get_clocks clk_hfxt] -to [get_clocks clk_scl0]
set_false_path -from [get_clocks clk_hfxt] -to [get_clocks clk_scl1]
set_false_path -from [get_clocks clk_hfxt] -to [get_clocks clk_sck0]
set_false_path -from [get_clocks clk_hfxt] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks clk_scl0] -to [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ]
set_false_path -from [get_clocks clk_scl0] -to [get_clocks smclk]
set_false_path -from [get_clocks clk_scl0] -to [get_clocks clk_lfxt]
set_false_path -from [get_clocks clk_scl0] -to [get_clocks clk_hfxt]
set_false_path -from [get_clocks clk_scl0] -to [get_clocks clk_scl1]
set_false_path -from [get_clocks clk_scl0] -to [get_clocks clk_sck0]
set_false_path -from [get_clocks clk_scl0] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks clk_scl1] -to [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ]
set_false_path -from [get_clocks clk_scl1] -to [get_clocks smclk]
set_false_path -from [get_clocks clk_scl1] -to [get_clocks clk_lfxt]
set_false_path -from [get_clocks clk_scl1] -to [get_clocks clk_hfxt]
set_false_path -from [get_clocks clk_scl1] -to [get_clocks clk_scl0]
set_false_path -from [get_clocks clk_scl1] -to [get_clocks clk_sck0]
set_false_path -from [get_clocks clk_scl1] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks clk_sck0] -to [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ]
set_false_path -from [get_clocks clk_sck0] -to [get_clocks smclk]
set_false_path -from [get_clocks clk_sck0] -to [get_clocks clk_lfxt]
set_false_path -from [get_clocks clk_sck0] -to [get_clocks clk_hfxt]
set_false_path -from [get_clocks clk_sck0] -to [get_clocks clk_scl0]
set_false_path -from [get_clocks clk_sck0] -to [get_clocks clk_scl1]
set_false_path -from [get_clocks clk_sck0] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks clk_sck1] -to [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ]
set_false_path -from [get_clocks clk_sck1] -to [get_clocks smclk]
set_false_path -from [get_clocks clk_sck1] -to [get_clocks clk_lfxt]
set_false_path -from [get_clocks clk_sck1] -to [get_clocks clk_hfxt]
set_false_path -from [get_clocks clk_sck1] -to [get_clocks clk_scl0]
set_false_path -from [get_clocks clk_sck1] -to [get_clocks clk_scl1]
set_false_path -from [get_clocks clk_sck1] -to [get_clocks clk_sck0]
set_false_path -to [list \
  [get_pins mcu0/rom0/PGEN]  \
  [get_pins mcu0/npuram0/PGEN] ]
group_path -weight 1.000000 -name mclk_group -from [get_clocks mclk]
group_path -weight 1.000000 -name smclk_group -from [get_clocks smclk]
group_path -weight 1.000000 -name clk_lfxt_group -from [get_clocks clk_lfxt]
group_path -weight 1.000000 -name clk_hfxt_group -from [get_clocks clk_hfxt]
group_path -weight 1.000000 -name clk_scl0_group -from [get_clocks clk_scl0]
group_path -weight 1.000000 -name clk_scl1_group -from [get_clocks clk_scl1]
group_path -weight 1.000000 -name clk_sck0_group -from [get_clocks clk_sck0]
group_path -weight 1.000000 -name clk_sck1_group -from [get_clocks clk_sck1]
# --- CQ8c: stale genus clock-gating path-groups REMOVED -----------------------
# The 8 `cg_enable_group_*` group_path -through blocks that lived here (C0-
# inherited, genus-emitted) referenced hard-coded RC_CG_HIER_INST<n> instance
# names from a superseded MCU synthesis. The 2026-07-16 AFE-stub re-synth
# (in/MCU_MP_hier.pnr.v) globally RENUMBERED every clock-gating instance, so all
# 855 through-pins missed -> 855 TCLCMD-917 (and the ~18 that still resolved now
# point at the WRONG cell). group_path is an optimization-ORDERING hint: it adds
# no timing constraint to any endpoint, so removing it is coverage-neutral
# (check_timing unconstrained-endpoint count is unchanged; endpoints are
# constrained solely by the create_clock domains + I/O delays above). This
# extends CQ4's own disposition (which dropped the hart<h> CG-enable entries as
# frozen-in-ETM) to the MCU-level entries the re-synth has now invalidated. The
# per-clock `group_path -from [get_clocks ...]` groups above (mclk/smclk/scl*/
# sck*/lfxt/hfxt) are KEPT and give CQ5 opt/CTS its per-clock path grouping
# without any instance-number dependency. To restore fine-grained per-CG groups
# after a future re-synth, harvest the current pins from the netlist:
#   tcl/harvest_cg_enables.py  ->  regenerated cg_enable_group_* blocks.
set_clock_gating_check -setup 0.0 
set_max_transition 0.5 [current_design]
set_wire_load_mode "enclosed"
set_dont_touch [get_cells {mcu0/hart0 mcu0/hart1 mcu0/hart2 mcu0/hart3}]
set_dont_touch [get_nets {mcu0/npu0/Decision[15]}]
set_dont_use false [get_lib_cells */TIEHIX1MA10TH]
set_dont_use false [get_lib_cells */TIELOX1MA10TH]

# --- C0 chip-top additions (not from genus) ---------------------------------
# Keep the dangling tb-visibility a0 buses + their iso-clamp drivers alive:
# the mcu0 instance leaves a0/a0_1/a0_2/a0_3 OPEN (Myshkin vesta_chip
# precedent) and optDesign would otherwise trim the unloaded driver cone. The
# gate tb probes these nets (primary probe path: the tiles' own ports
# mcu0/hart<h>/a0, which are trim-proof; this keeps the MCU-level clamped
# nets too).
set_dont_touch [get_nets -quiet {mcu0/a0[*]}]
set_dont_touch [get_nets -quiet {mcu0/a0_*}]

# --- CQ4 hardened-tile-boundary cleanup + unregistered-pin budget -------------
# (see ~/vesta_docs/castalia_quad/cq4_timing_budgets.md for the full derivation)
#
# This SDC was a sed of the C0 chip SDC (in/chip_top.sdc), which in turn is the
# genus-emitted MCU_MP SDC transformed to the chip. Ten TCLCMD-917 fired on
# objects that exist only INSIDE the pre-hardening tile (they are now absorbed
# into the per-corner ETM out/hart_tile.etm_{ss,ff}.lib). CQ4 dispositions:
#   * hart{0..3}/ram0/PGEN  : DROPPED from the PGEN set_false_path -to list --
#       ram0 is inside the tile ETM; the tile SDC already false-paths ram0/PGEN
#       (baked into the ETM as an absent arc). rom0/npuram0 PGEN kept (real
#       top-level macros, PGEN pins present).
#   * cg_enable_group_mclk  : the hart<h> internal CG-enable pins DROPPED (they
#       resolved to empty and were silently ignored -- not 917-firing -- but are
#       stale: the tiles' clock gating is frozen in the ETM and is not re-opt'd
#       at the chip level). MCU-level peripheral CG enables retained.
#   * get_designs hart_tile : RE-TARGETED to the four hardened tile INSTANCES
#       (get_cells mcu0/hart0..3) -- the boundary-real "do not touch the tiles".
#   * TIE lib-cell qualifier : stale genus lib name scadv10_..._tt_1p0v_25c
#       replaced with a wildcard */ (the cells exist under the assembly's own
#       lib name; proven get_lib_cells */TIEHIX1MA10TH -> 1 cell).
#
# GENERATED-CLOCK (M9c) CHECK -- carried for all four tiles: clk_cpu is a
# generated clock created INSIDE the tile SDC (create_generated_clock clk_cpu
# -source clk -divide_by 1 core/clk_cpu) and is baked into the ETM, so the
# assembly builds mcu0/hart{0..3}/clk_cpu automatically (verified: check_timing
# reports "Using master clock 'mclk' for generated clock mcu0/hart{0..3}/clk_cpu").
# flash_clk_mem is likewise an ETM generated clock on all four harts; SDC line 19
# additionally (re)asserts the chip-level "flash_clk_mem" on hart0's pin (only
# hart0 wires the boot flash) -- a benign re-assertion of the ETM's hart0 clock,
# kept to stay byte-aligned with C0.
#
# UNREGISTERED-PIN BUDGET (M14 list: hart0 flash quartet, sleep, straps).
#   * sleep / hart_id / pd_iso_en / tcm_* / resetn / a0 / trap_flag are
#     set_false_path'd IN THE TILE SDC -> those arcs are ABSENT from the ETM ->
#     they carry no chip-level timing (async / static config). Nothing to budget.
#   * flash quartet (flash_dout in; flash_mab, flash_mem_en out; flash_clk_mem
#     generated clock) is UNREGISTERED at the tile boundary but at the CHIP level
#     is an ordinary single-cycle mclk (40 ns) reg-to-reg path spanning the ETM
#     boundary between hart0's core flop and mcu0/spi0 (flash_mab->spi0/mab,
#     flash_mem_en->spi0/en_mem_flash, spi0/rdata_flash->flash_dout; harts 1-3
#     leave the flash port UNCONNECTED). clk_cpu / flash_clk_mem are both DIV1 of
#     mclk = one synchronous domain, so this path is checked at 40 ns.
#     Budget (ETM ss arcs + CQ geometry): flash_mab clk->pin <=1.4 ns; hart0
#     flash pins are on the tile's center-band-facing BOTTOM edge (global y=1639,
#     x~=476), and spi0 lands in the center band directly below -> worst-case
#     Manhattan route <=1.6 mm (~<=2 ns); spi0 input->flop a few ns; total <~6 ns
#     of the 40 ns period => >34 ns (>85%) margin. flash_dout setup at the tile
#     is small/relaxed (~ -0.4 ns) so the spi0->hart0 direction has ~the full
#     cycle. A chip-level set_max_delay of 10 ns (the TILE's standalone external
#     io reserve) would OVER-constrain this 40 ns-governed path, so -- exactly as
#     C0 does -- NO chip-level set_max_delay/set_input_delay/set_output_delay is
#     added here; the 40 ns mclk reg-to-reg check across the ETM boundary governs
#     and holds with >85% margin. Re-verify at CQ5 STA once spi0 is placed.
