# VestaRV: clock constraints for the fpga_default bring-up cut, out of context.
#
# TEMPLATE. No board is tracked in this repository, so every device pin below is
# a placeholder and the PACKAGE_PIN / IOSTANDARD lines are commented out. What is
# NOT a placeholder is the clock structure: the primary clocks, the twenty-five
# generated clocks the design builds out of them, and which of those are
# multiplexed and therefore mutually exclusive. That part is measured from
# config/fpga_default.json and is correct as written.
#
# Read with implementations/fpga/synth/README.md and hdl/fpga/README.md. The
# clock-net table in hdl/fpga/README.md is the budget these constraints describe:
# 25 generated clock nets plus 2 primaries against the 32 BUFGCTRL sites on an
# Artix-7.
#
# WHERE THE CLOCK ENTERS. There is no dedicated clock port on MCU. HFXT and LFXT
# are GPIO0 pins: P1.5 and P1.4, i.e. prt1_in[5] and prt1_in[4] (MemoryMap.vhd,
# pnum_gpio0_hfxt / pnum_gpio0_lfxt). On a board both must land on a
# clock-capable (MRCC or SRCC) pin.

# ---------------------------------------------------------------------------
# 1. Primary clocks
# ---------------------------------------------------------------------------
# 24 MHz on the HFXT pad. SYS_CLK_CR resets to zero, which selects clk_hfxt for
# both MCLK and SMCLK, so this is the clock the design runs on out of reset and
# it is the one every bench in the tree models. On a board it comes out of an
# MMCM (implementations/fpga/synth/mmcm_24mhz.vhd) rather than off the oscillator
# directly, because a board crystal is rarely 24 MHz and the firmware's UART
# divisors are written against that number.
create_clock -name clk_hfxt_pad -period 41.667 [get_ports {prt1_in[5]}]

# 32.768 kHz on the LFXT pad. Tie it low on a board that has no watch crystal and
# the whole lfxt branch folds away, taking one BUFGCE and one mux input with it.
create_clock -name clk_lfxt_pad -period 30517.578 [get_ports {prt1_in[4]}]

# The two DCOs need no primary clock. hdl/fpga/analog_stubs.vhd ties
# OscillatorCurrentStarved's output to '0', so clk_dco0 and clk_dco1 are
# constants, both source-mux slices fold, and the two ClkGate instances that
# would have buffered them disappear. That is 2 of the 27 buffers recovered for
# free, and it is also why firmware that selects a DCO stops the clock it is
# running on.

# I2C0 is a bus slave: its receive path is clocked by the wires, not by MCLK.
# SPI0's slave path is clocked by SCK. Frequencies are the bus maxima, not
# anything the design chooses.
# create_clock -name i2c0_scl -period 2500.0 [get_ports {prt2_in[0]}]
# create_clock -name spi0_sck -period 100.0  [get_ports {prt1_in[3]}]

# ---------------------------------------------------------------------------
# 2. Generated clocks: the eighteen enable-gated ones
# ---------------------------------------------------------------------------
# Each ClkGate in hdl/fpga/ is one ClkBufEn, which is one BUFGCE. A BUFGCE
# passes its input period unchanged, so Vivado DERIVES these automatically and
# no create_generated_clock is wanted: writing one here would override the
# derived clock and is the usual way to end up analyzing the wrong period.
# They are listed so a reader can count them against the budget.
#
#   system0/cg_clk_hfxt/gate/buf                     clk_hfxt      <- clk_hfxt_pad
#   system0/cg_clk_lfxt/gate/buf                     clk_lfxt      <- clk_lfxt_pad
#   system0/cg_smclk/gate/buf                        smclk_out     <- smclk
#   system0/cg_wdt_clk/gate/buf                      clk_wdt       <- mclk
#   system0/cg_unlock/gate/buf                       clk_unlock    <- mclk
#   hart0/core/cg_clk_cpu/gate/buf                   clk_cpu       <- mclk
#   hart0/cg_tcm_ext/gate/buf                        tx_ext_clk    <- mclk
#   hart0/adddec0/gen_cg_mem[1].cg_mem/gate/buf      clk_mem(1)    <- clk_cpu
#   hart0/adddec0/gen_flash_clk.cg_flash/gate/buf    clk_mem_flash <- clk_cpu inverted
#   timer0/clock_gate_timer/gate/buf                 clock_source  <- clock_mux_output
#   timer0/clock_gate_divider/gate/buf               divider_input <- clock_mux_output
#   spi0/cg_clk_baud_src/gate/buf                    clk_baud_src  <- smclk inverted
#   spi0/cg_clk_baud/gate/buf                        clk_baud      <- clk_baud_src
#   spi0/gen_flash.CGFlash/gate/buf                  ClkFlash      <- smclk
#   uart0/cgu_baud_clk_src/gate/buf                  baud_clk_src  <- smclk
#   uart0/cg_clk_baud/gate/buf                       clk_baud      <- baud_clk_src
#   uart0/cg_clk_tx/gate/buf                         clk_tx        <- clk_baud
#   i2c0/CGMaster/out_gate/buf                       ClkMaster     <- smclk
#
# adddec's other two memory gates and all sixteen peripheral gates are
# unconnected inside hart_tile (hdl/common/hart_tile.vhd:299 declares clk_periph
# and nothing reads it), so synthesis removes them and they cost nothing.
#
# The three chained baud gates in each of SPI0 and UART0 are the point of the
# BUFGCE substitution: every one of them is the SAME clock as its source, let
# through one cycle in N, so timing closes at the source period and the baud
# rate is an enable, not a frequency. Nothing needs a divide ratio declared.

# ---------------------------------------------------------------------------
# 3. Generated clocks: the five multiplexed ones
# ---------------------------------------------------------------------------
# hdl/fpga/ClockMuxGlitchFree.vhd is a one-hot fabric mux into ONE ClkBuf, so
# each instance has several masters and one output pin. The SDC form for that is
# one generated clock per master with -add, plus a clock group saying only one is
# ever live.
#
# -divide_by 1 on the two divider muxes is deliberate and conservative: the
# divisor is a runtime register field (SYS_CLK_DIV_CR, 1 to 128), so the fastest
# selectable clock is the one timing has to close at.

# smclk_undiv: HFXT or LFXT.
create_generated_clock -name smclk_undiv_hfxt -source [get_pins system0/cg_clk_hfxt/gate/buf/O] \
	-divide_by 1 [get_pins system0/smclk_mux/ob/buf/O]
create_generated_clock -name smclk_undiv_lfxt -source [get_pins system0/cg_clk_lfxt/gate/buf/O] \
	-divide_by 1 -add -master_clock clk_lfxt_pad [get_pins system0/smclk_mux/ob/buf/O]

# smclk: smclk_undiv divided by 1 to 128.
create_generated_clock -name smclk -source [get_pins system0/smclk_mux/ob/buf/O] \
	-divide_by 1 [get_pins system0/smclk_divider_mux/ob/buf/O]

# mclk_undiv: HFXT or SMCLK. ClkIn(1) of this mux is smclk, so MCLK can be a
# divided SMCLK and the two trees are not independent.
create_generated_clock -name mclk_undiv_hfxt -source [get_pins system0/cg_clk_hfxt/gate/buf/O] \
	-divide_by 1 [get_pins system0/mclk_mux/ob/buf/O]
create_generated_clock -name mclk_undiv_smclk -source [get_pins system0/smclk_divider_mux/ob/buf/O] \
	-divide_by 1 -add -master_clock smclk [get_pins system0/mclk_mux/ob/buf/O]

# mclk: mclk_undiv divided by 1 to 128. This is the CPU and bus clock.
create_generated_clock -name mclk -source [get_pins system0/mclk_mux/ob/buf/O] \
	-divide_by 1 [get_pins system0/mclk_div_mux/ob/buf/O]

# TIMER0's source mux: SMCLK, MCLK, LFXT or HFXT.
create_generated_clock -name t0_src_smclk -source [get_pins system0/smclk_divider_mux/ob/buf/O] \
	-divide_by 1 [get_pins timer0/clk_mux/ob/buf/O]
create_generated_clock -name t0_src_mclk -source [get_pins system0/mclk_div_mux/ob/buf/O] \
	-divide_by 1 -add -master_clock mclk [get_pins timer0/clk_mux/ob/buf/O]
create_generated_clock -name t0_src_lfxt -source [get_pins system0/cg_clk_lfxt/gate/buf/O] \
	-divide_by 1 -add -master_clock clk_lfxt_pad [get_pins timer0/clk_mux/ob/buf/O]
create_generated_clock -name t0_src_hfxt -source [get_pins system0/cg_clk_hfxt/gate/buf/O] \
	-divide_by 1 -add -master_clock clk_hfxt_pad [get_pins timer0/clk_mux/ob/buf/O]

# Only one slice of any mux is ever selected, so the alternatives must not be
# timed against each other.
set_clock_groups -logically_exclusive \
	-group [get_clocks smclk_undiv_hfxt] -group [get_clocks smclk_undiv_lfxt]
set_clock_groups -logically_exclusive \
	-group [get_clocks mclk_undiv_hfxt] -group [get_clocks mclk_undiv_smclk]
set_clock_groups -logically_exclusive \
	-group [get_clocks t0_src_smclk] -group [get_clocks t0_src_mclk] \
	-group [get_clocks t0_src_lfxt] -group [get_clocks t0_src_hfxt]

# HFXT and LFXT are separate oscillators with no phase relationship.
set_clock_groups -asynchronous -group [get_clocks clk_hfxt_pad] -group [get_clocks clk_lfxt_pad]

# ---------------------------------------------------------------------------
# 4. Generated clocks: the two fabric muxes with no buffer of their own
# ---------------------------------------------------------------------------
# These two are in hdl/common/ RTL, not in a cell hdl/fpga/ can substitute, and
# neither has a clock buffer in front of it. Vivado promotes them itself and
# warns; the properties below say to expect it.
#
#   hart0/ram_clk      hart_tile.vhd:759, tx_ext_clk or clk_mem(1). The RTL's own
#                      comment argues both inputs are low at every switch instant,
#                      so it is genuinely glitch-free and needs no interlock.
#   timer0/timer_clock TIMER.vhd, clock_source or one of twelve prescaler taps.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -hierarchical -quiet -filter {NAME =~ */ram_clk}]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -hierarchical -quiet -filter {NAME =~ */timer_clock}]

create_generated_clock -name t0_clk -source [get_pins timer0/clock_gate_timer/gate/buf/O] \
	-divide_by 1 [get_nets timer0/timer_clock]

# ---------------------------------------------------------------------------
# 5. Fabric-driven clock buffer inputs
# ---------------------------------------------------------------------------
# Every ClkBuf in hdl/fpga/ClockMuxGlitchFree.vhd is fed by a LUT, which Vivado
# refuses to place on the dedicated clock route without being told.
set_property CLOCK_DEDICATED_ROUTE FALSE \
	[get_nets -hierarchical -quiet -filter {NAME =~ */ob/Muxed}]

# ---------------------------------------------------------------------------
# 6. Asynchronous inputs
# ---------------------------------------------------------------------------
# resetn_in is a pad, asynchronous by construction, and SYSTEM.vhd releases it
# through its own two-stage synchronizer (SYSTEM.vhd:222).
set_false_path -from [get_ports resetn_in]
